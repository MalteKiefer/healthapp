import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthapp/core/security/app_lock/app_lock_controller.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/pin/pin_service.dart';
import 'package:healthapp/widgets/pin_numpad.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String? _error;
  int _failed = 0;
  DateTime? _lockoutUntil;

  Future<void> _attempt(String pin) async {
    final controller = ref.read(appLockControllerProvider.notifier);
    try {
      await controller.unlockWithPin(pin);
      if (mounted) context.go('/home');
    } on LockedOutException catch (e) {
      setState(() {
        _lockoutUntil = e.until;
        _error = 'Zu viele Fehlversuche. Wartezeit bis ${e.until}.';
      });
    } on InvalidKeyException {
      setState(() {
        _failed = controller.pinService.failedAttempts;
        _error = 'Falscher PIN. Fehlversuche: $_failed/10';
      });
    }
  }

  Future<void> _forgotPin() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PIN vergessen?'),
        content: const Text(
          'Alle lokalen Daten dieser App werden gelöscht. '
          'Deine Daten auf dem Server bleiben unverändert. '
          'Du musst dich danach mit Email und Passwort neu einloggen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Daten löschen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(appLockControllerProvider.notifier).wipe();
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _lockoutUntil != null &&
        DateTime.now().isBefore(_lockoutUntil!);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'PIN eingeben',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 32),
                PinNumpad(
                  onCompleted: _attempt,
                  errorText: _error,
                  enabled: !locked,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _forgotPin,
                  child: const Text('PIN vergessen?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
