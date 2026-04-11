import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Two-mode screen used for:
/// - initial TOFU trust after user enters server URL for the first time
/// - cert-change warning when a pinned fingerprint no longer matches
class TrustServerScreen extends StatelessWidget {
  const TrustServerScreen({
    super.key,
    required this.host,
    required this.newFingerprint,
    this.previousFingerprint,
  });

  final String host;
  final String newFingerprint;
  final String? previousFingerprint;

  bool get isChange => previousFingerprint != null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(isChange
            ? 'Zertifikat geändert'
            : 'Server vertrauen'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isChange)
                Icon(Icons.warning_amber_rounded, size: 64, color: cs.error)
              else
                Icon(Icons.shield_outlined, size: 64, color: cs.primary),
              const SizedBox(height: 16),
              Text(
                host,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (isChange) ...[
                Text(
                  'Das Zertifikat dieses Servers hat sich geändert. '
                  'Wenn du die Rotation nicht selbst veranlasst hast, '
                  'könnte ein Man-in-the-Middle-Angriff vorliegen.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                Text('Bisher:',
                    style: Theme.of(context).textTheme.labelLarge),
                SelectableText(previousFingerprint!, style: _mono),
                const SizedBox(height: 12),
                Text('Neu:', style: Theme.of(context).textTheme.labelLarge),
                SelectableText(newFingerprint, style: _mono),
              ] else ...[
                Text(
                  'Bitte überprüfe den folgenden Fingerprint mit dem '
                  'Betreiber des Servers, bevor du vertraust:',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                SelectableText(newFingerprint, style: _mono),
              ],
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(isChange
                    ? 'Neues Zertifikat akzeptieren'
                    : 'Vertrauen'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _mono =
      TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.4);
}
