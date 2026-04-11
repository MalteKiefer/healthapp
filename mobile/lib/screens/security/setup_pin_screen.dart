import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthapp/core/security/app_lock/app_lock_controller.dart';
import 'package:healthapp/widgets/pin_numpad.dart';

/// Mandatory 6-digit PIN setup screen shown after first successful
/// server login. User cannot dismiss or navigate away.
class SetupPinScreen extends ConsumerStatefulWidget {
  const SetupPinScreen({super.key});

  @override
  ConsumerState<SetupPinScreen> createState() => _SetupPinScreenState();
}

class _SetupPinScreenState extends ConsumerState<SetupPinScreen> {
  String? _first;
  String? _error;

  Future<void> _onCompleted(String pin) async {
    if (_first == null) {
      setState(() {
        _first = pin;
        _error = null;
      });
      return;
    }
    if (_first != pin) {
      setState(() {
        _first = null;
        _error = 'PINs stimmen nicht überein. Bitte erneut wählen.';
      });
      return;
    }
    try {
      await ref.read(appLockControllerProvider.notifier).setupPin(pin);
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() {
        _first = null;
        _error = 'Fehler: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prompt = _first == null
        ? 'Wähle einen 6-stelligen PIN'
        : 'PIN zur Bestätigung wiederholen';
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline,
                    size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(prompt, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 32),
                PinNumpad(onCompleted: _onCompleted, errorText: _error),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
