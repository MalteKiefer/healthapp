import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: 64, color: cs.outline),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: tt.titleMedium?.copyWith(color: cs.onSurface),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle,
                style: tt.bodySmall?.copyWith(color: cs.outline),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
