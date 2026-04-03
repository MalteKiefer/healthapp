import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_service.dart';
import '../../core/crypto/auth_crypto.dart';
import '../../core/i18n/translations.dart';
import '../../models/auth.dart';
import '../../providers/providers.dart';

// Top-level function for compute() - must not be a closure
class _HashParams {
  final String password;
  final String email;
  _HashParams(this.password, this.email);
}

String _deriveHash(_HashParams p) =>
    AuthCrypto.deriveAuthHash(p.password, p.email);

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
    final creds = await AuthService.loadCredentials();
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

      final password = _passwordCtrl.text;
      final email = _emailCtrl.text;
      final authHash = await compute(
        _deriveHash,
        _HashParams(password, email),
      );

      await api.post<Map<String, dynamic>>(
        '/api/v1/auth/login',
        body:
            LoginRequest(email: _emailCtrl.text, authHash: authHash).toJson(),
      );

      await AuthService.saveCredentials(
        email: _emailCtrl.text,
        authHash: authHash,
        serverUrl: api.baseUrl,
      );

      if (mounted) context.go('/home');
    } catch (e) {
      setState(() {
        _error = e.toString();
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
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
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
