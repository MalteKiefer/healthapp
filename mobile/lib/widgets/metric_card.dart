import 'package:flutter/material.dart';

enum MetricTrend { up, down, stable }

class MetricCard extends StatelessWidget {
  final String name;
  final String value;
  final String? unit;
  final MetricTrend? trend;

  const MetricCard({
    super.key,
    required this.name,
    required this.value,
    this.unit,
    this.trend,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: tt.labelMedium?.copyWith(color: cs.outline)),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, style: tt.headlineSmall?.copyWith(color: cs.onSurface)),
                if (unit != null) ...[
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(unit!, style: tt.bodySmall?.copyWith(color: cs.outline)),
                  ),
                ],
                const Spacer(),
                if (trend != null) _TrendIcon(trend: trend!),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendIcon extends StatelessWidget {
  final MetricTrend trend;

  const _TrendIcon({required this.trend});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color) = switch (trend) {
      MetricTrend.up => (Icons.trending_up_rounded, cs.error),
      MetricTrend.down => (Icons.trending_down_rounded, cs.tertiary),
      MetricTrend.stable => (Icons.trending_flat_rounded, cs.outline),
    };
    return Icon(icon, size: 20, color: color);
  }
}
