import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';

import 'models.dart';
import 'secure_storage.dart';

/// MQTT bridge between the app and an MQTT broker.
///
/// The ESP32 firmware publishes its state to `<prefix>/state` and subscribes to
/// `<prefix>/command`. This service mirrors that: it publishes the local state
/// snapshot to `state` and forwards incoming `command` messages through
/// [onCommand] so the dashboard can act on them (over the normal HTTP API).
class MqttService extends ChangeNotifier {
  MqttService(this._storage, {this.onCommand});

  final SecureStorage _storage;
  final void Function(Map<String, dynamic> command)? onCommand;

  MqttClient? _client;
  StreamSubscription<MqttPublishMessage>? _updatesSub;
  Timer? _reconnectTimer;
  Timer? _publishTimer;

  MqttConfig _config = const MqttConfig(
    enabled: false,
    broker: '',
    port: 1883,
    username: '',
    password: '',
    topicPrefix: 'smarthome',
  );

  bool _connected = false;
  String? _error;
  bool _connecting = false;

  MqttConfig get config => _config;
  bool get enabled => _config.enabled;
  bool get connected => _connected;
  bool get connecting => _connecting;
  String? get error => _error;

  /// Loads persisted MQTT config from secure storage.
  Future<void> load() async {
    final raw = await _storage.readJson(SecureStorage.mqttConfig);
    if (raw.isNotEmpty) {
      _config = MqttConfig.fromJson(raw);
    }
    notifyListeners();
  }

  /// Persists the given config and (re)connects when enabled.
  Future<void> setConfig(MqttConfig next) async {
    _config = next;
    await _storage.writeJson(SecureStorage.mqttConfig, next.toJson());
    // Keep individual fields too so legacy reads still work.
    await _storage.writeBool(SecureStorage.mqttEnabled, next.enabled);
    await _storage.writeString(SecureStorage.mqttBroker, next.broker);
    await _storage.writeInt(SecureStorage.mqttPort, next.port);
    await _storage.writeString(SecureStorage.mqttUsername, next.username);
    await _storage.writeString(SecureStorage.mqttPassword, next.password);
    await _storage.writeString(SecureStorage.mqttTopicPrefix, next.topicPrefix);
    notifyListeners();
    if (next.enabled) {
      connect();
    } else {
      disconnect();
    }
  }

  @override
  void dispose() {
    disconnect();
    _reconnectTimer?.cancel();
    _publishTimer?.cancel();
    _updatesSub?.cancel();
    super.dispose();
  }

  Future<void> connect() async {
    if (!_config.enabled || _config.broker.isEmpty) return;
    if (_connecting || _connected) return;
    _connecting = true;
    _error = null;
    notifyListeners();

    await disconnect();

    final client = MqttClient(_config.broker, 'flutter_app_${DateTime.now().millisecondsSinceEpoch}')
      ..port = _config.port
      ..keepAlivePeriod = 30
      ..secure = _config.port == 8883
      ..onConnected = _onConnected
      ..onDisconnected = _onDisconnected
      ..onSubscribed = _onSubscribed
      ..logging = false;

    if (_config.username.isNotEmpty) {
      client.username = _config.username;
      client.password = _config.password;
    }

    _client = client;

    bool ok;
    try {
      ok = await client.connect(_config.username, _config.password).timeout(
            const Duration(seconds: 10),
          );
    } catch (e) {
      ok = false;
      _setError('connect failed: ${_mqttError(e)}');
    }

    if (!_connecting) return; // disposed or replaced meanwhile

    _connecting = false;
    if (ok && client.connectionStatus?.state == MqttConnectionState.connected) {
      _connected = true;
      _error = null;
      _subscribe();
      notifyListeners();
    } else {
      _connected = false;
      if (_error == null) {
        _setError('broker rejected connection '
            '${client.connectionStatus?.state ?? 'unknown'}');
      }
      _scheduleReconnect();
      notifyListeners();
    }
  }

  void disconnect() {
    _connecting = false;
    _connected = false;
    _reconnectTimer?.cancel();
    _publishTimer?.cancel();
    _updatesSub?.cancel();
    try {
      _client?.disconnect();
    } catch (_) {}
    _client = null;
    notifyListeners();
  }

  void _onConnected() {
    _connected = true;
    _error = null;
    _reconnectTimer?.cancel();
    notifyListeners();
    _subscribe();
  }

  void _onDisconnected() {
    _connected = false;
    if (_config.enabled) {
      _setError('disconnected from broker');
      _scheduleReconnect();
    }
    notifyListeners();
  }

  void _onSubscribed(String topic) {
    // no-op; kept for parity
  }

  void _subscribe() {
    final client = _client;
    if (client == null || !_connected) return;
    _updatesSub?.cancel();
    _updatesSub = client.updates!.listen((msg) {
      final topic = msg.topicName;
      final payload = MqttPublishPayload.bytesToStringAsString(msg.payload.message);
      if (topic == _config.commandTopic) {
        _handleCommand(payload);
      }
    });
    client.subscribe(_config.commandTopic, MqttQos.atLeastOnce);
  }

  void _handleCommand(String payload) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (onCommand != null) onCommand!(json);
  }

  /// Publishes the current ESP32 state snapshot to the broker.
  Future<void> publishState(Esp32State state) async {
    if (!_connected || _client == null) return;
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(_stateToJson(state)));
    _client!.publishMessage(
      _config.stateTopic,
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  /// Publishes a single device change.
  Future<void> publishDevice(Esp32Device device) async {
    if (!_connected || _client == null) return;
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode({
      'id': device.id,
      'on': device.on,
      'watts': device.watts,
      'ts': DateTime.now().millisecondsSinceEpoch,
    }));
    _client!.publishMessage('${_config.stateTopic}/device/${device.id}',
        MqttQos.atLeastOnce, builder.payload!);
  }

  void _scheduleReconnect() {
    if (!_config.enabled || _connected || _connecting) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_config.enabled && !_connected && !_connecting) connect();
    });
  }

  void _setError(String message) {
    _error = message;
    if (kDebugMode) print('[mqtt] $message');
  }

  String _mqttError(Object e) {
    if (e is MqttException) return e.toString();
    return e.toString();
  }

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
