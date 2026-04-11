import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../providers/providers.dart';
import '../../providers/two_factor_provider.dart';

/// Returns the translation for [key] if present, otherwise [fallback].
String _trOr(String key, String fallback) {
  final v = T.tr(key);
  return v == key ? fallback : v;
}

/// Sprint 2: Login-time 2FA challenge screen.
///
/// Shown after the initial `POST /api/v1/auth/login` responds with
/// `{requires_totp: true, challenge_token: ..., user_id: ...}`. The
/// caller is responsible for passing the [userId] and
/// [challengeToken] through to this screen.
///
/// On a valid code the server completes the login (setting auth
/// cookies) and this screen triggers
/// `appLockControllerProvider.notifier.onLoginSuccess()` which hands
/// off to the router's redirect logic (setup-pin or home).
class TwoFactorChallengeScreen extends ConsumerStatefulWidget {
  final String userId;
  final String challengeToken;

  const TwoFactorChallengeScreen({
    super.key,
    required this.userId,
    required this.challengeToken,
  });

  @override
  ConsumerState<TwoFactorChallengeScreen> createState() =>
      _TwoFactorChallengeScreenState();
}

class _TwoFactorChallengeScreenState
    extends ConsumerState<TwoFactorChallengeScreen> {
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
        SnackBar(
          content: Text(_trOr('twofactor.enter_code', 'Enter 6-digit code')),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(twoFactorControllerProvider.notifier).submitLoginChallenge(
            userId: widget.userId,
            code: code,
            challengeToken: widget.challengeToken,
          );

      if (!mounted) return;
      final state = ref.read(twoFactorControllerProvider);
      if (state.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.error!)),
        );
        // Clear the field so the user can retry.
        _codeCtrl.clear();
        return;
      }
      if (state.success) {
        // Hand off to the app-lock controller, which drives the
        // router redirect to /setup-pin or /home depending on the
        // current security state.
        ref.read(appLockControllerProvider.notifier).onLoginSuccess();
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
      appBar: AppBar(
        title: const Text('Two-Factor Verification'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg + AppSpacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.phonelink_lock,
                      size: 40, color: cs.onPrimaryContainer),
                ),
                const SizedBox(height: AppSpacing.lg - AppSpacing.xs),
                Text(
                  _trOr(
                      'twofactor.enter_code', 'Enter your authenticator code'),
                  style: tt.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Open your authenticator app and enter the current '
                  '6-digit code for your health account.',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  style: tt.headlineMedium?.copyWith(letterSpacing: 10),
                  decoration: const InputDecoration(
                    counterText: '',
                    border: OutlineInputBorder(),
                    hintText: '000000',
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Verify'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
