import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../providers/two_factor_provider.dart';

/// Sprint 2: Two-Factor Authentication disable screen.
///
/// Prompts for the user's current 6-digit TOTP code and sends it to
/// `POST /api/v1/auth/2fa/disable` together with the stored
/// `current_auth_hash` (the server refuses to disable 2FA without
/// re-verifying the password hash, as a guard against a hijacked
/// session silently turning 2FA off).
class TwoFactorDisableScreen extends ConsumerStatefulWidget {
  const TwoFactorDisableScreen({super.key});

  @override
  ConsumerState<TwoFactorDisableScreen> createState() =>
      _TwoFactorDisableScreenState();
}

class _TwoFactorDisableScreenState
    extends ConsumerState<TwoFactorDisableScreen> {
  final _codeCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit code')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final creds = await ref.read(authServiceProvider).loadCredentials();
      if (creds == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No stored credentials — please log in again'),
          ),
        );
        return;
      }

      await ref.read(twoFactorControllerProvider.notifier).disable(
            code: code,
            currentAuthHash: creds.authHash,
          );

      if (!mounted) return;
      final state = ref.read(twoFactorControllerProvider);
      if (state.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.error!)),
        );
        return;
      }
      if (state.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Two-factor authentication disabled'),
          ),
        );
        Navigator.of(context).maybePop();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Disable Two-Factor Auth')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 56, color: cs.error),
              const SizedBox(height: 16),
              Text(
                'Disable two-factor authentication?',
                style: tt.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your account will only be protected by your '
                'password. Enter the current 6-digit code from your '
                'authenticator app to confirm.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: tt.headlineSmall?.copyWith(letterSpacing: 8),
                decoration: const InputDecoration(
                  labelText: '6-digit code',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.errorContainer,
                  foregroundColor: cs.onErrorContainer,
                ),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Disable 2FA'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).maybePop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
