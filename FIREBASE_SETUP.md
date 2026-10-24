# Firebase Setup Guide — ESP32 Smart Home Authentication

This document walks you through enabling Firebase Authentication (email/password +
Google Sign-In) and Firestore cloud sync for the ESP32 Smart Home Flutter app.

## 1. Create a Firebase project

1. Go to https://console.firebase.google.com/
2. Add project → give it a name (e.g. `esp32-smart-home`) → Continue.
3. Disable Google Analytics (optional) → Create project.

## 2. Register your Android app

1. In the Firebase console, Project settings → General → Your apps → Add app → Android.
2. **Android package name:** `com.example.esp32_controller` (matches the Flutter
   `package:` in `android/app/build.gradle.kts` / `AndroidManifest.xml`).
3. **App nickname:** `ESP32 Smart Home` (optional).
4. **Debug signing certificate SHA-1:** required for Google Sign-In.
   - Get it from your debug keystore:
     ```powershell
     keytool -list -v -alias androiddebugkey -keystore "%USERPROFILE%\.android\debug.keystore" -storepass android -keypass android
     ```
   - Copy the SHA-1 fingerprint into the Firebase console.
5. Click **Register app**.
6. Download **`google-services.json`** and place it at:
   ```
   android/app/google-services.json
   ```
   **Never commit this file to version control.** It contains configuration
   identifiers (not secret keys, but still treat it as private).

## 3. Enable Authentication providers

In the Firebase console → Build → Authentication → Sign-in method:

### Email/Password
1. Click Email/Password → Enable → Save.

### Google Sign-In
1. Click Google → Enable → Save.
2. Select your support email.
3. Firebase auto-configures the OAuth client; no manual secrets are needed in
   your code. The `google-services.json` carries the config.

## 4. Create a Firestore database

1. Firebase console → Build → Firestore Database → Create database.
2. Choose **Start in test mode** (temporary) or **Locked mode**, then apply the
   security rules below.
3. Select a location close to your users.

## 5. Apply Firestore security rules

Copy `firestore.rules` into the Firebase console → Firestore Database → Rules,
then publish:

```text
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid}/documents/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
    match /users/{uid}/app/settings {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
    match /users/{uid}/esp32_devices/{deviceId} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
      allow create: if request.auth != null
        && request.auth.uid == uid
        && request.resource.data.ownerUid == uid;
    }
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

These rules ensure:
- Each user can only read/write their own documents under `/users/{uid}/...`.
- Login alone does **not** grant access to another user's ESP32 devices.
- Device pairing records include `ownerUid` and are validated on create.

## 6. Android gradle wiring

### `android/build.gradle.kts` (project level)
Add the Google Services plugin to the `buildscript` / `plugins` block:

```kotlin
buildscript {
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
    }
}
```

And apply it in `android/app/build.gradle.kts`:

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")  // add this
}
```

### `android/app/google-services.json`
Place the file downloaded from Firebase here. Do **not** commit it.

## 7. iOS (optional, if you build for iOS)

1. Register your iOS app in Firebase console (bundle ID from
   `ios/Runner/Info.plist`).
2. Download `GoogleService-Info.plist` and add it to the Xcode runner target.
3. Enable App Store / In-House / Ad Hoc distribution certificates for Google
   Sign-In if distributing beyond development.

## 8. Web (optional)

Firebase Auth email/password works on web. Google Sign-In on web requires
adding your `localhost` / hosted domain to the Firebase console → Authentication
→ Sign-in method → Google → Authorized domains.

## 9. Security rules recap

- **Never upload MQTT passwords, Telegram bot tokens, API keys, or ESP32
  access tokens to Firestore.** These remain in `flutter_secure_storage`
  (EncryptedSharedPreferences on Android, Keychain on iOS).
- `CloudSync` deliberately strips MQTT credentials before writing settings to
  Firestore.
- Device ownership is explicit: a user must `pairDevice(url)` before the app
  treats an ESP32 as theirs. The security rules enforce `ownerUid == uid`.

## 10. Do not hardcode credentials

- `google-services.json` contains configuration identifiers — keep it out of
  Git (add to `.gitignore`).
- No OAuth client secrets or Firebase API keys should appear in Dart source.
  The Firebase SDK reads them from `google-services.json` at build time.

## 11. Testing

After configuration:
```powershell
flutter pub get
flutter analyze
flutter test
```

Then run on a device/emulator and verify:
- Email/password sign-up sends a verification email.
- Google Sign-In completes and returns a profile.
- Password reset email arrives.
- Signing out returns to the welcome screen.
- Local-only use ("Continue without signing in") still works and preserves
  existing settings.