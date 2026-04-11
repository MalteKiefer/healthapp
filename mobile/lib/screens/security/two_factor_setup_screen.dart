import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../providers/two_factor_provider.dart';
import '../../widgets/skeletons.dart';

/// Returns the translation for [key] if present, otherwise [fallback].
/// `T.tr` returns the key itself when no entry is found, so we use that
/// sentinel to detect missing keys and fall back to the English literal.
String _trOr(String key, String fallback) {
  final v = T.tr(key);
  return v == key ? fallback : v;
}

/// Sprint 2: Two-Factor Authentication setup screen.
///
/// Walks the user through:
///   1. Fetching a fresh TOTP secret + provisioning URI from the server
///   2. Showing the provisioning URI (and raw secret) so the user can
///      add it to their authenticator app
///   3. Collecting a 6-digit TOTP code to confirm possession
///   4. On success, displaying the generated recovery codes with a
///      copy-to-clipboard button
///
/// Note: no `qr_flutter` dependency is present in pubspec.yaml yet, so
/// this screen currently renders the provisioning URI as selectable
/// text rather than a scannable QR image. Swap in a QR widget when
/// the dependency is added in a later sprint.
class TwoFactorSetupScreen extends ConsumerStatefulWidget {
  const TwoFactorSetupScreen({super.key});

  @override
  ConsumerState<TwoFactorSetupScreen> createState() =>
      _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends ConsumerState<TwoFactorSetupScreen> {
  final _codeCtrl = TextEditingController();

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
    await ref.read(twoFactorControllerProvider.notifier).enable(code);
    if (!mounted) return;
    final state = ref.read(twoFactorControllerProvider);
    if (state.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.error!)),
      );
    }
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final setupAsync = ref.watch(twoFactorSetupProvider);
    final controllerState = ref.watch(twoFactorControllerProvider);

    // Once enable succeeds, show the recovery-codes screen instead.
    if (controllerState.success && controllerState.recoveryCodes.isNotEmpty) {
      return _RecoveryCodesView(
        codes: controllerState.recoveryCodes,
        onCopy: (text) =>
            _copy(text, _trOr('twofactor.recovery_codes', 'Recovery codes')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_trOr('twofactor.setup', 'Set up 2FA'))),
      body: setupAsync.when(
        loading: () => const SkeletonCard(height: 220),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'Failed to load setup: $err',
              style: tt.bodyLarge?.copyWith(color: cs.error),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (setup) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.shield_outlined, size: 56, color: cs.primary),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Protect your account',
                style: tt.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Add the following setup key to your authenticator '
                'app (for example Aegis, 1Password, or Google '
                'Authenticator), then enter the 6-digit code it '
                'generates to confirm.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Provisioning URI (QR code content)
              Card(
                color: cs.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Provisioning URI',
                          style: tt.labelLarge
                              ?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: AppSpacing.sm),
                      SelectableText(
                        setup.provisioningUri,
                        style: tt.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy URI'),
                          onPressed: () =>
                              _copy(setup.provisioningUri, 'URI'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xs),

              // Raw secret
              Card(
                color: cs.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          _trOr('twofactor.secret_label',
                              'Setup key (manual entry)'),
                          style: tt.labelLarge
                              ?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: AppSpacing.sm),
                      SelectableText(
                        setup.secret,
                        style: tt.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                          letterSpacing: 2,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy key'),
                          onPressed: () => _copy(setup.secret, 'Secret'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                autofillHints: const [AutofillHints.oneTimeCode],
                style: tt.headlineSmall?.copyWith(letterSpacing: 8),
                decoration: InputDecoration(
                  labelText:
                      _trOr('twofactor.enter_code', 'Enter 6-digit code'),
                  counterText: '',
                  border: const OutlineInputBorder(),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: controllerState.loading ? null : _submit,
                child: controllerState.loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_trOr('twofactor.setup', 'Enable 2FA')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecoveryCodesView extends StatelessWidget {
  final List<String> codes;
  final ValueChanged<String> onCopy;

  const _RecoveryCodesView({required this.codes, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final joined = codes.join('\n');

    return Scaffold(
      appBar: AppBar(
        title: Text(_trOr('twofactor.recovery_codes', 'Recovery codes')),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.verified_user, color: cs.primary, size: 48),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
              Text(
                'Two-factor authentication enabled',
                style: tt.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Store these codes somewhere safe. Each code can be '
                'used once if you lose access to your authenticator.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: Card(
                  color: cs.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        joined,
                        style: tt.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy all codes'),
                onPressed: () => onCopy(joined),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
