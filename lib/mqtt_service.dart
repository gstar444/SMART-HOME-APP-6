import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'esp32_api.dart';
import 'models.dart';
import 'mqtt_config.dart';
import 'secure_storage.dart';

export 'mqtt_config.dart';

/// MQTT bridge between the app and an MQTT broker.
///
/// The ESP32 publishes its state to `<prefix>/state` and listens on
/// `<prefix>/command`. Incoming command messages are forwarded to [onCommand].
class MqttService extends ChangeNotifier {
  MqttService(this._storage, {this.onCommand});

  final SecureStorage _storage;
  final void Function(Map<String, dynamic> command)? onCommand;

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;
  Timer? _reconnectTimer;

  MqttConfig _config = const MqttConfig(
    enabled: false,
    broker: '',
    port: 1883,
    username: '',
    password: '',
    topicPrefix: 'smarthome',
  );

  bool _connected = false;
  bool _connecting = false;
  bool _disposed = false;
  String? _error;

  MqttConfig get config => _config;
  bool get enabled => _config.enabled;
  bool get connected => _connected;
  bool get connecting => _connecting;
  String? get error => _error;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Loads persisted MQTT config from secure storage.
  Future<void> load() async {
    final raw = await _storage.readJson(SecureStorage.mqttConfig);
    if (raw.isNotEmpty) {
      _config = MqttConfig.fromJson(raw);
    }
    _notify();
  }

  /// Persists the given config and (re)connects when enabled.
  Future<void> setConfig(MqttConfig next) async {
    _config = next;
    await _storage.writeJson(SecureStorage.mqttConfig, next.toJson());
    await _storage.writeBool(SecureStorage.mqttEnabled, next.enabled);
    await _storage.writeString(SecureStorage.mqttBroker, next.broker);
    await _storage.writeInt(SecureStorage.mqttPort, next.port);
    await _storage.writeString(SecureStorage.mqttUsername, next.username);
    await _storage.writeString(SecureStorage.mqttPassword, next.password);
    await _storage.writeString(SecureStorage.mqttTopicPrefix, next.topicPrefix);
    _notify();
    if (next.enabled) {
      await connect();
    } else {
      await disconnect();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _connecting = false;
    _connected = false;
    _reconnectTimer?.cancel();
    _updatesSub?.cancel();
    final c = _client;
    _client = null;
    c?.onDisconnected = null;
    c?.disconnect();
    super.dispose();
  }

  Future<void> connect() async {
    if (_disposed) return;
    if (!_config.enabled || _config.broker.isEmpty) return;
    if (_connecting || _connected) return;

    await disconnect();

    _connecting = true;
    _error = null;
    _notify();

    final client = MqttServerClient.withPort(
      _config.broker,
      'flutter_app_${DateTime.now().millisecondsSinceEpoch}',
      _config.port,
    );
    client.keepAlivePeriod = 30;
    client.secure = _config.port == 8883;
    if (client.secure) {
      client.securityContext = SecurityContext.defaultContext;
    }
    client.onConnected = _onConnected;
    client.onDisconnected = _onDisconnected;
    client.logging(on: false);

    _client = client;

    String? err;
    try {
      await client
          .connect(
            _config.username.isEmpty ? null : _config.username,
            _config.password.isEmpty ? null : _config.password,
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      err = 'connect failed: ${_mqttError(e)}';
    }

    // Replaced, disconnected or disposed while connecting.
    if (_disposed || !_connecting || _client != client) return;

    _connecting = false;
    if (err == null &&
        client.connectionStatus?.state == MqttConnectionState.connected) {
      _connected = true;
      _error = null;
      _subscribe(client);
    } else {
      _connected = false;
      _error = err ??
          'broker rejected connection: '
              '${client.connectionStatus?.state ?? 'unknown'}';
      client.disconnect();
      _scheduleReconnect();
    }
    _notify();
  }

  Future<void> disconnect() async {
    _connecting = false;
    _connected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _updatesSub?.cancel();
    _updatesSub = null;

    final c = _client;
    _client = null;
    if (c != null) {
      c.onDisconnected = null;
      c.disconnect();
    }
    _notify();
  }

  void _subscribe(MqttServerClient client) {
    client.subscribe(_config.commandTopic, MqttQos.atLeastOnce);
    _updatesSub?.cancel();
    _updatesSub = client.updates?.listen(_onMessages);
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> msgs) {
    for (final msg in msgs) {
      if (msg.topic != _config.commandTopic) continue;
      final pub = msg.payload;
      if (pub is! MqttPublishMessage) continue;
      final text = MqttPublishPayload.bytesToStringAsString(pub.payload.message);
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          onCommand?.call(decoded);
        }
      } catch (_) {
        // Ignore malformed command payloads.
      }
    }
  }

  void _onConnected() {
    _connected = true;
    _error = null;
    _notify();
  }

  void _onDisconnected() {
    _connected = false;
    _notify();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || !_config.enabled || _connected || _connecting) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_config.enabled && !_connected && !_connecting) {
        connect();
      }
    });
  }

  /// Publishes the full device state snapshot.
  Future<void> publishState(Esp32State state) async {
    final client = _client;
    if (!_connected || client == null) return;
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(_stateToJson(state)));
    client.publishMessage(
      _config.stateTopic,
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  /// Publishes a single device change.
  Future<void> publishDevice(Esp32Device device) async {
    final client = _client;
    if (!_connected || client == null) return;
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode({
      'id': device.id,
      'on': device.on,
      'watts': device.watts,
      'ts': DateTime.now().millisecondsSinceEpoch,
    }));
    client.publishMessage(
      '${_config.stateTopic}/device/${device.id}',
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  String _mqttError(Object e) => e.toString();

  Map<String, dynamic> _stateToJson(Esp32State s) => {
        'name': s.name,
        'fw': s.fw,
        'ssid': s.ssid,
        'ip': s.ip,
        'online': s.wifiConnected,
        'dnd': s.dnd,
        'powerW': s.powerW,
        'temp': s.temp,
        'hum': s.hum,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'devices': [
          for (final d in s.devices)
            {
              'id': d.id,
              'name': d.name,
              'type': d.type,
              'group': d.group,
              'icon': d.icon,
              'room': d.room,
              'on': d.on,
              'watts': d.watts,
              'wh': d.wh,
              'pin': d.pin,
            },
        ],
      };
}
