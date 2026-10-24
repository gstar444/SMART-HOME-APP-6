import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  final _storage = const FlutterSecureStorage();

  Future<String?> read(String key) async {
    return await _storage.read(key: key);
  }

  Future<void> writeString(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<void> writeStringValue(String key, dynamic value) async {
    await _storage.write(key: key, value: value.toString());
  }

  Future<void> writeBool(String key, bool value) async {
    await _storage.write(key: key, value: value ? '1' : '0');
  }

  Future<void> writeJson(String key, dynamic value) async {
    await _storage.write(key: key, value: jsonEncode(value));
  }

  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }
}
