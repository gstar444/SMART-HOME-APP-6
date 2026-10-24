import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_user.dart';

/// Authentication errors surfaced to the user.
class AuthException implements Exception {
  AuthException(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() => 'AuthException($code, $message)';
}

/// Central authentication state manager.
///
/// Listens to Firebase Auth state changes and exposes sign-in / sign-up /
/// sign-out / password-reset operations. All credentials stay on the device
/// (Firebase handles them server-side); this provider never stores passwords.
class AuthProvider extends ChangeNotifier {
  AuthProvider() : _auth = FirebaseAuth.instance {
    _auth.authStateChanges().listen((user) {
      _user = user == null ? null : _toAppUser(user);
      notifyListeners();
    });
  }

  final FirebaseAuth _auth;
  AppUser? _user;
  bool _initializing = true;
  String? _initError;

  AppUser? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get initializing => _initializing;
  String? get initError => _initError;
  bool get emailVerified => _user?.emailVerified ?? false;

  /// Initializes Firebase and returns the current signed-in user (if any).
  /// Firebase must already be initialized (e.g. in main()) before calling this.
  Future<void> initialize() async {
    try {
      // Firebase.initializeApp() is called in main(); here we just sync the
      // current user. Re-initializing would throw a duplicate-app error.
      if (Firebase.apps.isNotEmpty) {
        _user = _auth.currentUser == null
            ? null
            : _toAppUser(_auth.currentUser!);
      } else {
        await Firebase.initializeApp();
        _user = _auth.currentUser == null
            ? null
            : _toAppUser(_auth.currentUser!);
      }
    } on FirebaseException catch (e) {
      _initError = e.code;
      if (kDebugMode) print('[auth] Firebase init error: ${e.code}');
    } catch (e) {
      _initError = 'unknown_init_error';
      if (kDebugMode) print('[auth] Firebase init error: $e');
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  AppUser _toAppUser(User u) => AppUser(
        uid: u.uid,
        email: u.email ?? '',
        displayName: u.displayName,
        photoUrl: u.photoURL,
        emailVerified: u.emailVerified,
        provider: _providerName(u),
      );

  String _providerName(User u) {
    final providers = u.providerData;
    for (final p in providers) {
      if (p.providerId == 'google.com') return 'google';
      if (p.providerId == 'password') return 'password';
    }
    return 'unknown';
  }

  // ------------------------------------------------------------------ Google

  /// Signs in with Google OAuth. Requires `google-services.json` (Android) and
  /// `GoogleService-Info.plist` (iOS) plus a configured Firebase project.
  Future<AppUser> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(
        // Scopes beyond basic profile are not needed for smart home control.
        scopes: <String>['email', 'profile'],
      );
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw AuthException('user_cancelled', 'Sign-in was cancelled.');
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      return _toAppUser(userCredential.user!);
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.code ?? 'google_sign_in_failed', e.message);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('google_sign_in_failed', e.toString());
    }
  }

  // --------------------------------------------------------------- email/pass

  /// Creates a new email/password account and sends email verification.
  Future<AppUser> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      email = email.trim();
      if (email.isEmpty) throw AuthException('invalid_email', 'Email is required.');
      if (password.length < 6) {
        throw AuthException('weak_password', 'Password must be at least 6 characters.');
      }
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCredential.user;
      if (user == null) {
        throw AuthException('sign_up_failed', 'Account creation returned no user.');
      }
      if (displayName != null && displayName.isNotEmpty) {
        await user.updateDisplayName(displayName);
      }
      // Send verification email so the user must confirm before relying on the account.
      await user.sendEmailVerification();
      return _toAppUser(user);
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.code ?? 'sign_up_failed', e.message);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('sign_up_failed', e.toString());
    }
  }

  /// Signs in with email and password.
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      email = email.trim();
      if (email.isEmpty) throw AuthException('invalid_email', 'Email is required.');
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCredential.user;
      if (user == null) {
        throw AuthException('sign_in_failed', 'Sign-in returned no user.');
      }
      return _toAppUser(user);
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.code ?? 'sign_in_failed', e.message);
    } catch (e) {
      throw AuthException('sign_in_failed', e.toString());
    }
  }

  /// Re-sends the email verification link.
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw AuthException('not_authenticated', 'No signed-in user.');
    }
    await user.sendEmailVerification();
  }

  /// Sends a password-reset email to [email].
  Future<void> resetPassword(String email) async {
    email = email.trim();
    if (email.isEmpty) throw AuthException('invalid_email', 'Email is required.');
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.code ?? 'password_reset_failed', e.message);
    } catch (e) {
      throw AuthException('password_reset_failed', e.toString());
    }
  }

  // ------------------------------------------------------------------ sign out

  /// Signs out of Firebase and Google. Does not touch local device settings.
  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // Google sign-out is best-effort; continue with Firebase sign-out.
    }
    await _auth.signOut();
    // _user is set to null via the authStateChanges listener above.
  }

  /// Reloads the current user's fresh auth state (e.g. emailVerified flag).
  Future<void> refreshUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      _user = null;
      notifyListeners();
      return;
    }
    await user.reload();
    _user = _toAppUser(_auth.currentUser!);
    notifyListeners();
  }
}
