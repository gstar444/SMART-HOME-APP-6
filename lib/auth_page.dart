import 'esp32_api.dart';
import 'mqtt_service.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_provider.dart';
import 'cloud_sync.dart';
import 'dashboard_page.dart';
import 'secure_storage.dart';
import 'settings.dart';

/// Authentication flow.
///
/// Routes:
///   [AuthMode.welcome]      -> welcome / "get started" screen
///   [AuthMode.signIn]       -> email/password login + Google button
///   [AuthMode.signUp]       -> email/password registration + Google button
///   [AuthMode.verify]       -> email-verification pending screen
///   [AuthMode.forgotPassword] -> password reset screen
enum AuthMode { welcome, signIn, signUp, verify, forgotPassword }

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.auth, required this.onAuthenticated});

  final AuthProvider auth;
  final VoidCallback onAuthenticated;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  AuthMode _mode = AuthMode.welcome;
  bool _loading = false;
  String? _error;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _resetEmailCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _displayNameCtrl.dispose();
    _resetEmailCtrl.dispose();
    super.dispose();
  }

  void _setError(String? e) => setState(() => _error = e);

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) widget.onAuthenticated();
    } on AuthException catch (e) {
      _setError(_friendly(e));
    } catch (e) {
      _setError('Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendly(AuthException e) {
    switch (e.code) {
      case 'user_cancelled':
        return 'Sign-in cancelled.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'weak-password':
        return 'Password is too weak (min 6 characters).';
      case 'network-request-failed':
        return 'No internet connection. Check your network.';
      case 'not_authenticated':
        return 'You are not signed in.';
      default:
        return e.message ?? 'Authentication failed.';
    }
  }

  Future<void> _signInWithGoogle() => _run(widget.auth.signInWithGoogle);

  Future<void> _signInEmail() => _run(() => widget.auth.signInWithEmail(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      ));

  Future<void> _signUpEmail() => _run(() => widget.auth.signUpWithEmail(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        displayName: _displayNameCtrl.text.trim().isEmpty
            ? null
            : _displayNameCtrl.text.trim(),
      ));

  Future<void> _resetPassword() => _run(() => widget.auth.resetPassword(_resetEmailCtrl.text));

  Future<void> _resendVerification() => _run(widget.auth.sendEmailVerification);

  Widget _googleButton() {
    return OutlinedButton.icon(
      icon: const Icon(Icons.login, size: 20),
      label: const Text('Continue with Google'),
      onPressed: _loading ? null : _signInWithGoogle,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  Widget _textField(TextEditingController c, {required String label, bool secret = false, TextInputType? type}) {
    return TextField(
      controller: c,
      obscureText: secret,
      keyboardType: type,
      enabled: !_loading,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        filled: true,
      ),
    );
  }

  Widget _form({
    required List<Widget> fields,
    required String primaryLabel,
    required VoidCallback onPrimary,
    required String secondaryLabel,
    required VoidCallback onSecondary,
    required Widget secondaryButton,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...fields,
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _loading ? null : onPrimary,
          child: _loading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(primaryLabel),
        ),
        const SizedBox(height: 12),
        secondaryButton,
        const SizedBox(height: 8),
        TextButton(onPressed: _loading ? null : onSecondary, child: Text(secondaryLabel)),
      ],
    );
  }

  Widget _buildWelcome() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.home_outlined, size: 80, color: Colors.blueAccent),
        const SizedBox(height: 24),
        Text(
          'Smart Home',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Control your ESP32 devices securely',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
        ),
        const SizedBox(height: 32),
        _googleButton(),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _loading ? null : () => setState(() => _mode = AuthMode.signIn),
          child: const Text('Sign in with email'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _loading ? null : () => setState(() => _mode = AuthMode.signUp),
          child: const Text('Create account'),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _loading ? null : widget.onAuthenticated,
          child: const Text('Continue without signing in (local only)'),
        ),
      ],
    );
  }

  Widget _buildSignIn() {
    return _form(
      fields: [
        _textField(_emailCtrl, label: 'Email', type: TextInputType.emailAddress),
        const SizedBox(height: 12),
        _textField(_passwordCtrl, label: 'Password', secret: true),
      ],
      primaryLabel: 'Sign in',
      onPrimary: _signInEmail,
      secondaryLabel: 'Need an account?',
      onSecondary: () => setState(() => _mode = AuthMode.signUp),
      secondaryButton: _googleButton(),
    );
  }

  Widget _buildSignUp() {
    return _form(
      fields: [
        _textField(_displayNameCtrl, label: 'Display name (optional)'),
        const SizedBox(height: 12),
        _textField(_emailCtrl, label: 'Email', type: TextInputType.emailAddress),
        const SizedBox(height: 12),
        _textField(_passwordCtrl, label: 'Password', secret: true),
        const SizedBox(height: 12),
        _textField(_confirmPasswordCtrl, label: 'Confirm password', secret: true),
      ],
      primaryLabel: 'Create account',
      onPrimary: _signUpEmail,
      secondaryLabel: 'Already have an account?',
      onSecondary: () => setState(() => _mode = AuthMode.signIn),
      secondaryButton: _googleButton(),
    );
  }

  Widget _buildVerify() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.verified_outlined, size: 64, color: Colors.amber),
        const SizedBox(height: 16),
        Text(
          'Verify your email',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'A verification link was sent to ${widget.auth.user?.email}. Open it, then tap below.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _loading ? null : _resendVerification,
          icon: const Icon(Icons.email_outlined, size: 18),
          label: const Text('Resend verification email'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _loading ? null : () {
            widget.auth.refreshUser();
            if (widget.auth.emailVerified) widget.onAuthenticated();
            else _setError('Email not yet verified. Check your inbox.');
          },
          child: const Text('I verified my email'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _loading ? null : () => setState(() => _mode = AuthMode.signIn),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }

  Widget _buildForgotPassword() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.email_outlined, size: 64),
        const SizedBox(height: 16),
        Text('Forgot password?', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Enter your email and we’ll send a reset link.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        _textField(_resetEmailCtrl, label: 'Email', type: TextInputType.emailAddress),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _loading ? null : _resetPassword,
          child: _loading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Send reset email'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _loading ? null : () => setState(() => _mode = AuthMode.signIn),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    final isVerify = mode == AuthMode.verify;
    final isForgot = mode == AuthMode.forgotPassword;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (isVerify)
                  _buildVerify()
                else if (isForgot)
                  _buildForgotPassword()
                else if (mode == AuthMode.welcome)
                  _buildWelcome()
                else if (mode == AuthMode.signIn)
                  _buildSignIn()
                else
                  _buildSignUp(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps the app so that unauthenticated users see [AuthPage] and authenticated
/// users see the dashboard. Local-only use is supported via the "Continue
/// without signing in" path which calls [AuthPage.onAuthenticated] directly.
class AuthGate extends StatefulWidget {
  const AuthGate({
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
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _ready = false;
  bool _useLocalMode = false;

  @override
  void initState() {
    super.initState();
    widget.auth.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    });
    // Rebuild whenever auth state changes (sign in / sign out).
    widget.auth.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final user = widget.auth.user;
    if (user != null && widget.controller.value.userId != user.uid) {
      // Associate settings with the authenticated user and sync from cloud.
      unawaited(widget.controller.setUserId(user.uid, cloudSync: widget.cloudSync));
      unawaited(widget.cloudSync.loadSettings());
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || widget.auth.initializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.auth.isAuthenticated || _useLocalMode) {
      return DashboardPage(
        settings: widget.controller,
        esp: widget.esp,
        mqtt: widget.mqtt,
        auth: widget.auth,
      );
    }
    return AuthPage(
      auth: widget.auth,
      onAuthenticated: () {
        if (!mounted) return;
        setState(() => _useLocalMode = true);
      },
    );
  }
}
