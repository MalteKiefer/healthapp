import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../models/symptom_chart_data.dart';
import '../../providers/providers.dart';
import '../../providers/symptom_chart_provider.dart';
import '../../widgets/skeletons.dart';

/// Shows severity trends over time per symptom.
///
/// X-axis: date (based on the point index across the selected series).
/// Y-axis: severity (0–10, matching the backend `intensity` scale used by
/// the web frontend).
class SymptomChartScreen extends ConsumerStatefulWidget {
  const SymptomChartScreen({super.key});

  @override
  ConsumerState<SymptomChartScreen> createState() => _SymptomChartScreenState();
}

class _SymptomChartScreenState extends ConsumerState<SymptomChartScreen> {
  String? _selectedSymptom;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(selectedProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(T.tr('symptoms.title')),
      ),
      body: profile == null
          ? const _CenteredMessage(message: 'No profile selected')
          : _buildBody(context, profile.id),
    );
  }

  Widget _buildBody(BuildContext context, String profileId) {
    final async = ref.watch(symptomChartProvider(profileId));

    return async.when(
      loading: () => const Column(
        children: [
          SkeletonCard(height: 48),
          SkeletonCard(height: 240),
          SkeletonCard(height: 96),
        ],
      ),
      error: (err, _) => _CenteredMessage(
        message: '${T.tr('symptoms.failed')}\n$err',
      ),
      data: (chart) {
        if (chart.isEmpty) {
          return _CenteredMessage(
            message: T.tr('symptoms.no_active'),
          );
        }

        // Initialize the selection lazily on first successful load.
        final names = chart.series.map((s) => s.symptomName).toList();
        final selected = (_selectedSymptom != null &&
                names.contains(_selectedSymptom))
            ? _selectedSymptom!
            : names.first;

        final series = chart.series.firstWhere(
          (s) => s.symptomName == selected,
        );

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(symptomChartProvider(profileId));
            await ref.read(symptomChartProvider(profileId).future);
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _SymptomFilterChips(
                names: names,
                selected: selected,
                onSelected: (name) => setState(() => _selectedSymptom = name),
              ),
              const SizedBox(height: AppSpacing.md),
              _ChartCard(series: series),
              const SizedBox(height: AppSpacing.md),
              _SeriesSummary(series: series),
            ],
          ),
        );
      },
    );
  }
}

class _SymptomFilterChips extends StatelessWidget {
  final List<String> names;
  final String selected;
  final ValueChanged<String> onSelected;

  const _SymptomFilterChips({
    required this.names,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final name in names)
          ChoiceChip(
            label: Text(name),
            selected: name == selected,
            onSelected: (_) => onSelected(name),
          ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  final SymptomSeries series;

  const _ChartCard({required this.series});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final points = series.dataPoints;

    if (points.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: Text(
              '${T.tr('symptoms.no_active')} (${series.symptomName})',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].severity),
    ];

    final dateFmt = DateFormat.Md();
    const minY = 0.0;
    const maxY = 10.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm + AppSpacing.xs,
          AppSpacing.md + AppSpacing.xs,
          AppSpacing.lg - AppSpacing.xs,
          AppSpacing.sm + AppSpacing.xs,
        ),
        child: SizedBox(
          height: 260,
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              minX: 0,
              maxX: (points.length - 1).toDouble().clamp(0, double.infinity),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                  strokeWidth: 0.5,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 2,
                    getTitlesWidget: (v, _) => Text(
                      v.toStringAsFixed(0),
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: _bottomInterval(points.length),
                    getTitlesWidget: (v, meta) {
                      final idx = v.round();
                      if (idx < 0 || idx >= points.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs + 2),
                        child: Text(
                          dateFmt.format(points[idx].date),
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) =>
                      cs.surfaceContainerHighest.withValues(alpha: 0.95),
                  getTooltipItems: (spots) => spots.map((spot) {
                    final idx = spot.x.round();
                    final date = (idx >= 0 && idx < points.length)
                        ? DateFormat.yMMMd().format(points[idx].date)
                        : '';
                    return LineTooltipItem(
                      '$date\nSeverity: ${spot.y.toStringAsFixed(1)}',
                      TextStyle(color: cs.onSurface, fontSize: 12),
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: cs.primary,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, a, b, c) => FlDotCirclePainter(
                      radius: 3,
                      color: cs.primary,
                      strokeColor: cs.surface,
                      strokeWidth: 1.5,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: cs.primary.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _bottomInterval(int count) {
    if (count <= 1) return 1;
    if (count <= 6) return 1;
    return (count / 5).ceilToDouble();
  }
}

class _SeriesSummary extends StatelessWidget {
  final SymptomSeries series;

  const _SeriesSummary({required this.series});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final points = series.dataPoints;
    if (points.isEmpty) return const SizedBox.shrink();

    final avg =
        points.map((p) => p.severity).reduce((a, b) => a + b) / points.length;
    final max = points.map((p) => p.severity).reduce((a, b) => a > b ? a : b);
    final min = points.map((p) => p.severity).reduce((a, b) => a < b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              series.symptomName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: cs.onSurface,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _StatTile(label: 'Entries', value: '${points.length}'),
                _StatTile(label: 'Avg', value: avg.toStringAsFixed(1)),
                _StatTile(label: 'Min', value: min.toStringAsFixed(0)),
                _StatTile(label: 'Max', value: max.toStringAsFixed(0)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final String message;

  const _CenteredMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}
