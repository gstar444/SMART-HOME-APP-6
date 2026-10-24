import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'auth_page.dart';
import 'auth_provider.dart';
import 'cloud_sync.dart';
import 'dashboard_page.dart';
import 'esp32_api.dart';
import 'mqtt_service.dart';
import 'secure_storage.dart';
import 'settings.dart';

export 'settings.dart' show esp32Url, defaultEsp32Url;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final secureStorage = SecureStorage(const FlutterSecureStorage());
  final controller = await SettingsController.load(secureStorage: secureStorage);
  final esp = Esp32Controller(controller);
  final mqtt = MqttService(
    secureStorage,
    onCommand: (command) => _handleMqttCommand(esp, command),
  );
  await mqtt.load();

  final auth = AuthProvider();
  final firestore = FirebaseFirestore.instance;
  final cloudSync = CloudSync(auth, firestore, secureStorage);

  runApp(SmartHomeApp(
    auth: auth,
    controller: controller,
    esp: esp,
    mqtt: mqtt,
    secureStorage: secureStorage,
    cloudSync: cloudSync,
  ));
}

/// An MQTT command (e.g. `{"id":"light","on":true}`) is applied through the
/// normal HTTP API so a single code path handles local and cloud control.
void _handleMqttCommand(Esp32Controller esp, Map<String, dynamic> command) {
  final id = command['id'] as String?;
  if (id == null || id.isEmpty) return;
  final on = command['on'] as bool?;
  if (on == null) return;
  unawaited(esp.setDevice(id, on));
}

ThemeData buildTheme(Color accent, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness);
  final background = dark ? const Color(0xFF0C1117) : const Color(0xFFF5F8FC);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

class SmartHomeApp extends StatelessWidget {
  const SmartHomeApp({
    super.key,
    required this.auth,
    required this.controller,
    required this.esp,
    required this.mqtt,
    required this.secureStorage,
    required this.cloudSync,
  });

  final AuthProvider auth;
  final SettingsController controller;
  final Esp32Controller esp;
  final MqttService mqtt;
  final SecureStorage secureStorage;
  final CloudSync cloudSync;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, auth]),
      builder: (context, _) {
        final s = controller.value;
        final accent = Color(s.accent);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: s.title,
          themeMode: s.themeMode,
          theme: buildTheme(accent, Brightness.light),
          darkTheme: buildTheme(accent, Brightness.dark),
          home: AuthGate(
            auth: auth,
            controller: controller,
            esp: esp,
            mqtt: mqtt,
            secureStorage: secureStorage,
            cloudSync: cloudSync,
          ),
        );
      },
    );
  }
}
