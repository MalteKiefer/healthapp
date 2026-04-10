import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/app_lock/app_lock_controller.dart';

/// Intermediate screen shown once when legacy credentials (from the
/// pre-vault flutter_secure_storage implementation) are detected on an
/// installation that has no encrypted vault yet.
///
/// Explains the upgrade to the user and then transitions the
/// [AppLockController] out of [SecurityState.migrationPending] so the
/// router can forward to the regular PIN-setup flow.
class MigrationScreen extends ConsumerWidget {
  const MigrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 64),
              const SizedBox(height: 16),
              Text(
                'HealthVault wurde aktualisiert',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Aus Sicherheitsgründen musst du einen PIN einrichten. '
                'Nach der Einrichtung wirst du dich einmal neu einloggen müssen.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () {
                  ref
                      .read(appLockControllerProvider.notifier)
                      .acknowledgeMigration();
                },
                child: const Text('Weiter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
