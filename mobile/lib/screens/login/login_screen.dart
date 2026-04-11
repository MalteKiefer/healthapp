import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_error_messages.dart';
import '../../core/auth/auth_service.dart';
import '../../core/crypto/auth_crypto.dart';
import '../../core/i18n/translations.dart';
import '../../core/security/app_lock/app_lock_controller.dart';
import '../../models/auth.dart';
import '../../providers/providers.dart';

// Top-level function for compute() - must not be a closure.
// `password` is intentionally mutable so the calling isolate can null it
// out immediately after the derivation completes (memory hygiene).
class _HashParams {
  String? password;
  final Uint8List salt;
  _HashParams(this.password, this.salt);
}

String _deriveHashWithSalt(_HashParams p) =>
    AuthCrypto.deriveAuthHashWithSalt(p.password!, p.salt);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _serverCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedServer();
  }

  Future<void> _loadSavedServer() async {
    final creds = await ref.read(authServiceProvider).loadCredentials();
    if (creds != null && mounted) {
      setState(() {
        _serverCtrl.text = creds.serverUrl;
        _emailCtrl.text = creds.email;
      });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      await api.setBaseUrl(_serverCtrl.text);

      final email = _emailCtrl.text;

      // v2: fetch PBKDF2 salt from server (falls back to SHA256(email)
      // for legacy servers that don't yet expose /api/v1/auth/salt).
      final saltBytes = await AuthCrypto.fetchSalt(
        getJson: (path) async {
          return await api.get<Map<String, dynamic>>(path);
        },
        email: email,
      );

      // Memory hygiene: build params, hand off to compute(), then null
      // out the password reference so it can be GC'd ASAP.
      final hashParams = _HashParams(_passwordCtrl.text, saltBytes);
      final authHash = await compute(_deriveHashWithSalt, hashParams);
      hashParams.password = null;

      await api.post<Map<String, dynamic>>(
        '/api/v1/auth/login',
        body: LoginRequest(email: email, authHash: authHash).toJson(),
      );

      await ref.read(authServiceProvider).saveCredentials(
            StoredCredentials(
              email: email,
              authHash: authHash,
              serverUrl: api.baseUrl,
            ),
          );

      // Memory hygiene: wipe the password field once login succeeded.
      _passwordCtrl.clear();

      // Transition security state; the router redirect takes over and
      // sends the user to /setup-pin (or /home if PIN already exists).
      if (mounted) {
        ref.read(appLockControllerProvider.notifier).onLoginSuccess();
      }
    } catch (e) {
      setState(() {
        _error = apiErrorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.favorite,
                      size: 40, color: cs.onPrimaryContainer),
                ),
                const SizedBox(height: 20),
                Text(T.tr('login.title'),
                    style: tt.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(T.tr('login.subtitle'),
                    style: tt.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 40),

                // Fields
                TextField(
                  controller: _emailCtrl,
                  decoration: InputDecoration(
                    labelText: T.tr('login.email'),
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passwordCtrl,
                  decoration: InputDecoration(
                    labelText: T.tr('login.password'),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      tooltip: 'Toggle password visibility',
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  // Security hardening: block clipboard / selection menu so
                  // the password can never be copied out of the field.
                  enableInteractiveSelection: false,
                  contextMenuBuilder: (context, editableTextState) =>
                      const SizedBox.shrink(),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _serverCtrl,
                  decoration: InputDecoration(
                    labelText: T.tr('login.server'),
                    prefixIcon: const Icon(Icons.dns_outlined),
                    hintText: 'health.example.com',
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 24),

                // Error
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Card(
                      color: cs.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                size: 20, color: cs.onErrorContainer),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style: tt.bodySmall
                                    ?.copyWith(color: cs.onErrorContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Button
                FilledButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cs.onPrimary),
                        )
                      : Text(T.tr('login.sign_in')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
