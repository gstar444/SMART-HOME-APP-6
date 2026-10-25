import 'mqtt_config.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_provider.dart';
import 'secure_storage.dart';
import 'settings.dart';

/// Syncs non-sensitive app settings to Firestore per authenticated user.
///
/// Sensitive credentials (MQTT password, API keys, ESP32 access tokens) are
/// deliberately excluded — they remain in [`SecureStorage`] on the device and
/// are never uploaded to the cloud.
class CloudSync {
  CloudSync(this._authProvider, this._firestore, this._secureStorage);

  final AuthProvider _authProvider;
  final FirebaseFirestore _firestore;
  final SecureStorage _secureStorage;

  String? get _uid => _authProvider.user?.uid;
  bool get _enabled => _authProvider.isAuthenticated;

  /// Reference to this user's settings document.
  DocumentReference<Map<String, dynamic>>? _settingsRef() {
    if (!_enabled || _uid == null) return null;
    return _firestore.collection('users').doc(_uid).collection('app').doc('settings');
  }

  /// Reference to this user's owned ESP32 devices (pairing/ownership).
  CollectionReference<Map<String, dynamic>> _devicesRef() {
    if (!_enabled || _uid == null) {
      throw StateError('Not authenticated');
    }
    return _firestore.collection('users').doc(_uid!).collection('esp32_devices');
  }

  // ------------------------------------------------------------- settings sync

  /// Saves [settings] (minus sensitive fields) to Firestore under the user's UID.
  Future<void> saveSettings(AppSettings settings) async {
    final ref = _settingsRef();
    if (ref == null) return;
    // Strip MQTT credentials before uploading — keep them device-local only.
    final safe = settings.copyWith(
      mqttConfig: const MqttConfig(
        enabled: false,
        broker: '',
        port: 1883,
        username: '',
        password: '',
        topicPrefix: 'smarthome',
      ),
    );
    await ref.set(safe.toJson(), SetOptions(merge: true));
  }

  /// Loads settings from Firestore, merging over local defaults without
  /// touching locally-stored MQTT credentials.
  Future<AppSettings?> loadSettings() async {
    final ref = _settingsRef();
    if (ref == null) return null;
    final doc = await ref.get();
    if (!doc.exists) return null;
    return AppSettings.fromJson(Map<String, dynamic>.from(doc.data()!));
  }

  // ------------------------------------------------------------- device pairing

  /// Records that the authenticated user owns/controls the ESP32 at [url].
  ///
  /// This is the explicit ownership mechanism: a user must pair a device before
  /// the cloud treats it as theirs. Login alone does not grant access to an
  /// arbitrary ESP32.
  Future<void> pairDevice({
    required String url,
    String name = 'ESP32',
    String? friendlyName,
  }) async {
    if (!_enabled || _uid == null) {
      throw StateError('Not authenticated');
    }
    final docId = _deviceDocId(url);
    await _devicesRef().doc(docId).set({
      'url': url,
      'name': name,
      'friendlyName': friendlyName ?? name,
      'pairedAt': FieldValue.serverTimestamp(),
      'ownerUid': _uid,
    }, SetOptions(merge: true));
  }

  /// Removes the pairing for [url].
  Future<void> unpairDevice(String url) async {
    if (!_enabled || _uid == null) {
      throw StateError('Not authenticated');
    }
    await _devicesRef().doc(_deviceDocId(url)).delete();
  }

  /// Returns the URLs of ESP32 devices paired to the authenticated user.
  Future<List<String>> pairedDeviceUrls() async {
    if (!_enabled || _uid == null) return const <String>[];
    final snap = await _devicesRef().get();
    return <String>[
      for (final d in snap.docs)
        if (d.data()['url'] is String) d.data()['url'] as String,
    ];
  }

  /// Checks whether the authenticated user owns [url].
  Future<bool> ownsDevice(String url) async {
    if (!_enabled || _uid == null) return false;
    final doc = await _devicesRef().doc(_deviceDocId(url)).get();
    return doc.exists;
  }

  String _deviceDocId(String url) {
    // A stable, filesystem-safe id derived from the URL.
    return url
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .substring(0, (url.length < 80 ? url.length : 80));
  }

  // ------------------------------------------------------------------ listeners

  Stream<DocumentSnapshot<Map<String, dynamic>>>? settingsStream() {
    final ref = _settingsRef();
    if (ref == null) return null;
    return ref.snapshots();
  }
}
