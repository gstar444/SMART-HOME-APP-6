import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted key/value storage backed by `flutter_secure_storage`.
///
/// On Android this uses EncryptedSharedPreferences, on iOS the Keychain.
/// Nothing is ever written to disk in plain text.
class SecureStorage {
  SecureStorage(this._storage);

  final FlutterSecureStorage _storage;

  /// Keys used across the app.
  static const String mqttBroker = 'mqtt_broker';
  static const String mqttPort = 'mqtt_port';
  static const String mqttUsername = 'mqtt_username';
  static const String mqttPassword = 'mqtt_password';
  static const String mqttTopicPrefix = 'mqtt_topic_prefix';
  static const String mqttEnabled = 'mqtt_enabled';
  static const String mqttConfig = 'mqtt_config';
  static const String apiKey = 'api_key';

  /// Reads a String, returning [defaultValue] when absent or unreadable.
  Future<String> readString(String key, {String defaultValue = ''}) async {
    try {
      final value = await _storage.read(key: key);
      return value ?? defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  /// Writes a String.
  Future<void> writeString(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  /// Reads an int, returning [defaultValue] when absent or unreadable.
  Future<int> readInt(String key, {int defaultValue = 0}) async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null) return defaultValue;
      return int.tryParse(raw) ?? defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  /// Writes an int.
  Future<void> writeInt(String key, int value) async {
    await _storage.write(key: key, value.toString());
  }

  /// Reads a bool, returning [defaultValue] when absent or unreadable.
  Future<bool> readBool(String key, {bool defaultValue = false}) async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null) return defaultValue;
      return raw == '1' || raw == 'true';
    } catch (_) {
      return defaultValue;
    }
  }

  /// Writes a bool.
  Future<void> writeBool(String key, bool value) async {
    await _storage.write(key: key, value ? '1' : '0');
  }

  /// Reads a JSON object, returning [defaultValue] when absent or unreadable.
  Future<Map<String, dynamic>> readJson(
    String key, {
    Map<String, dynamic> defaultValue = const {},
  }) async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null || raw.isEmpty) return Map<String, dynamic>.of(defaultValue);
      final decoded = jsonDecode(raw) as Map<String, dynamic>?;
      return decoded ?? Map<String, dynamic>.of(defaultValue);
    } catch (_) {
      return Map<String, dynamic>.of(defaultValue);
    }
  }

  /// Writes a JSON object.
  Future<void> writeJson(String key, Map<String, dynamic> value) async {
    await _storage.write(key: key, jsonEncode(value));
  }

  /// Removes a key.
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }
}

/// Snapshot of the MQTT settings kept in secure storage.
class MqttConfig {
  const MqttConfig({
    required this.enabled,
    required this.broker,
    required this.port,
    required this.username,
    required this.password,
    required this.topicPrefix,
  });

  final bool enabled;
  final String broker;
  final int port;
  final String username;
  final String password;
  final String topicPrefix;

  /// Command topic the app subscribes to (ESP32 publishes state here; app listens
  /// on the command topic and the ESP32 subscribes to it).
  String get commandTopic => '$topicPrefix/command';
  /// State topic the app publishes device state to.
  String get stateTopic => '$topicPrefix/state';

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'broker': broker,
        'port': port,
        'username': username,
        'password': password,
        'topicPrefix': topicPrefix,
      };

  factory MqttConfig.fromJson(Map<String, dynamic> json) => MqttConfig(
        enabled: json['enabled'] == true,
        broker: (json['broker'] as String?) ?? '',
        port: (json['port'] as int?) ?? 1883,
        username: (json['username'] as String?) ?? '',
        password: (json['password'] as String?) ?? '',
        topicPrefix: (json['topicPrefix'] as String?) ?? 'smarthome',
      );

  MqttConfig copyWith({
    bool? enabled,
    String? broker,
    int? port,
    String? username,
    String? password,
    String? topicPrefix,
  }) {
    return MqttConfig(
      enabled: enabled ?? this.enabled,
      broker: broker ?? this.broker,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      topicPrefix: topicPrefix ?? this.topicPrefix,
    );
  }
}
