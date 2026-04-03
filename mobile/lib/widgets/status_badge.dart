import 'package:flutter/material.dart';

enum HealthStatus { normal, high, low, critical, active, inactive }

class StatusBadge extends StatelessWidget {
  final HealthStatus status;
  final String? label;

  const StatusBadge({super.key, required this.status, this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg, defaultLabel) = switch (status) {
      HealthStatus.normal => (
          cs.secondaryContainer,
          cs.onSecondaryContainer,
          'Normal'
        ),
      HealthStatus.high => (
          cs.errorContainer,
          cs.onErrorContainer,
          'High'
        ),
      HealthStatus.low => (
          cs.tertiaryContainer,
          cs.onTertiaryContainer,
          'Low'
        ),
      HealthStatus.critical => (cs.error, cs.onError, 'Critical'),
      HealthStatus.active => (
          cs.primaryContainer,
          cs.onPrimaryContainer,
          'Active'
        ),
      HealthStatus.inactive => (
          cs.surfaceContainerHighest,
          cs.outline,
          'Inactive'
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label ?? defaultLabel,
        style: TextStyle(
            fontSize: 11, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
