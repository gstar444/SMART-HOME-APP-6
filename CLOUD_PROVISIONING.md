# Cloud / remote provisioning guide

This project controls an ESP32 over the local LAN by default (HTTP). This guide
explains how to reach the ESP32 from outside the home network safely, and how to
use the optional MQTT bridge to a cloud broker.

## Security rules (read first)

1. **Never expose the ESP32 HTTP port (80) directly to the internet.** The ESP32
   web/API server is not hardened for public exposure.
2. **Always use a private VPN** (Tailscale, WireGuard, ZeroTiers, etc.) to join
   the home LAN from outside, then use the ESP32's local IP exactly as you would
   at home.
3. **If you set `API_KEY` in the firmware**, enter the same key in the app
   Settings -> *API key*. It is sent as the `X-API-Key` header on every API call.
4. **MQTT credentials live in encrypted secure storage** (Keychain on iOS,
   EncryptedSharedPreferences on Android). They are never written to
   `shared_preferences` plain text and are excluded from backups
   (`android:allowBackup="false"`).

## Option A: Private VPN (recommended)

Run a VPN server inside your home network and connect your phone to it. The ESP32
stays reachable on its LAN IP; no ports are opened on the router.

- Tailscale: install on the phone and on a home device with subnet routing enabled,
  then access the ESP32 at its Tailscale IP.
- WireGuard: set up a WireGuard server at home; connect the phone; route the home
  LAN subnet through the tunnel.

No app changes are needed. In Settings, set the ESP32 URL to the VPN/LAN IP
(e.g. `http://10.x.y.z/`).

## Option B: MQTT bridge to a cloud broker

The app can publish ESP32 state to, and receive commands from, an MQTT broker
(broker.emqx.io, HiveMQ Cloud, Mosquitto, AWS IoT Core, etc.). The ESP32 firmware
connects to the same broker when `ENABLE_MQTT 1` is set and `PubSubClient` is
installed.

### Topics

| Topic | Direction | Meaning |
|-------|-----------|---------|
| `<prefix>/state` | ESP32 -> broker -> app | Full state JSON (same shape as `/api/state`) |
| `<prefix>/command` | app/broker -> ESP32 | `{"id":"light","on":true}` |

`<prefix>` defaults to `smarthome` and is set in Settings -> *MQTT broker* ->
*Topic prefix*.

### Firmware setup

1. In `esp32_smart_home.ino`, "YOUR SETTINGS":
   ```cpp
   #define ENABLE_MQTT 1
   const char* MQTT_BROKER = "broker.emqx.io";
   const uint16_t MQTT_PORT  = 1883;   // 8883 for TLS
   const char* MQTT_USER     = "";
   const char* MQTT_PASS     = "";
   const char* MQTT_PREFIX   = "smarthome";
   ```
2. Install the **PubSubClient** library (Nick O'Leary) via Arduino Library Manager.
3. Set `MQTT_PORT` to `8883` only if your broker supports TLS and you have
   configured the broker CA on the ESP32 (PubSubClient needs `setClientCert` /
   `setCACert` for verified TLS; plain TCP to 8883 may be rejected).

### App setup

1. Open Settings -> *MQTT broker*.
2. Turn on *Enable MQTT*.
3. Enter Broker address, Port, Username, Password, Topic prefix.
4. Tap *Save*. Credentials are stored in encrypted secure storage.

The dashboard shows a cloud icon: filled = connected to the broker. Outgoing MQTT
commands are applied through the normal HTTP API path so a single code path
handles local and cloud control.

### Cloud broker examples

- **Public test broker:** `broker.emqx.io:1883` (no auth, public - do not use for
  real homes; anyone can publish).
- **HiveMQ Cloud:** TLS on 8883 with username/password.
- **Self-hosted Mosquitto:** on a home server or VPS, with TLS + auth.

### Do not

- Do not put the ESP32's local HTTP port on a port-forward / DMZ.
- Do not commit real MQTT passwords or the ESP32 `API_KEY` to version control.
- Do not use the public test broker for anything other than experiments.

## Android network security

`android/app/src/main/AndroidManifest.xml` references
`res/xml/network_security_config.xml`. Cleartext traffic is permitted because the
app talks to the ESP32 over plain HTTP on the LAN. Credentials are stored
encrypted and backups are disabled.
