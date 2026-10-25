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
    await _storage.write(key: key, value: value.toString());
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
    await _storage.write(key: key, value: value ? '1' : '0');
  }

  /// Reads a JSON object, returning [defaultValue] when absent or unreadable.
  Future<Map<String, dynamic>> readJson(
    String key, {
    Map<String, dynamic> defaultValue = const {},
  }) async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null) return defaultValue;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return defaultValue;
    }
  }

  /// Writes a JSON object.
  Future<void> writeJson(String key, Map<String, dynamic> value) async {
    await _storage.write(key: key, value: jsonEncode(value));
  }

  /// Deletes a key.
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }
}
