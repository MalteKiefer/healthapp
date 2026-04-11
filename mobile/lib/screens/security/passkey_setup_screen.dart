import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/translations.dart';
import '../../core/security/passkey/passkey_service.dart';
import '../../core/theme/spacing.dart';
import '../../providers/passkey_provider.dart';

String _trOr(String key, String fallback) {
  final v = T.tr(key);
  return v == key ? fallback : v;
}

class PasskeySetupScreen extends ConsumerWidget {
  const PasskeySetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supportAsync = ref.watch(passkeySupportProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_trOr('passkey.title', 'Passkey')),
      ),
      body: supportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            err.toString(),
            style: TextStyle(color: scheme.error),
          ),
        ),
        data: (support) => _Body(support: support, scheme: scheme),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.support, required this.scheme});

  final PasskeySupport support;
  final ColorScheme scheme;

  Future<void> _onEnroll(BuildContext context, WidgetRef ref) async {
    final svc = ref.read(passkeyServiceProvider);
    try {
      // TODO(passkey-backend): fetch challenge from
      // POST /auth/webauthn/register/begin, call svc.register(...),
      // then POST /auth/webauthn/register/complete with the attestation.
      await svc.register(
        PasskeyRegistrationRequest(
          rpId: 'healthvault.local',
          rpName: 'HealthVault',
          userId: Uint8List(0),
          userName: 'user',
          userDisplayName: 'HealthVault User',
          challenge: Uint8List(0),
        ),
      );
    } on PasskeyBackendUnavailable {
      if (!context.mounted) return;
      _showComingSoon(context);
    }
  }

  void _showComingSoon(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _trOr('passkey.coming_soon', 'Coming soon'),
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _trOr(
                  'passkey.coming_soon_detail',
                  'Server-side WebAuthn endpoints are not yet implemented.',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(_trOr('common.ok', 'OK')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (support) {
      case PasskeySupport.unavailable:
        return _UnavailableView(scheme: scheme);
      case PasskeySupport.available:
        return _AvailableView(
          scheme: scheme,
          onEnroll: () => _onEnroll(context, ref),
        );
      case PasskeySupport.enrolled:
        return _EnrolledView(
          scheme: scheme,
          onRemove: () => _showComingSoon(context),
        );
    }
  }
}

class _UnavailableView extends StatelessWidget {
  const _UnavailableView({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: scheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: scheme.primary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      _trOr(
                        'passkey.unavailable',
                        'Passkeys will be available once your HealthVault '
                            'server supports WebAuthn (coming in a future '
                            'release).',
                      ),
                      style: TextStyle(color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.key),
            label: Text(_trOr('passkey.enroll', 'Set up passkey')),
          ),
        ],
      ),
    );
  }
}

class _AvailableView extends StatelessWidget {
  const _AvailableView({required this.scheme, required this.onEnroll});
  final ColorScheme scheme;
  final VoidCallback onEnroll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: scheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.fingerprint, color: scheme.primary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      _trOr(
                        'passkey.available',
                        'Enroll a platform passkey to sign in without '
                            'typing your password. Your device will ask '
                            'for your fingerprint, face, or PIN.',
                      ),
                      style: TextStyle(color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: onEnroll,
            icon: const Icon(Icons.key),
            label: Text(_trOr('passkey.enroll', 'Set up passkey')),
          ),
        ],
      ),
    );
  }
}

class _EnrolledView extends StatelessWidget {
  const _EnrolledView({required this.scheme, required this.onRemove});
  final ColorScheme scheme;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: scheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user, color: scheme.primary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      _trOr(
                        'passkey.enrolled',
                        'Passkey enrolled on this device',
                      ),
                      style: TextStyle(color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
            label: Text(_trOr('passkey.remove', 'Remove')),
          ),
        ],
      ),
    );
  }
}

