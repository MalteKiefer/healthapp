import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../models/lab.dart';
import '../../providers/lab_trends_provider.dart';
import '../../widgets/skeletons.dart';

/// Returns the translation for [key] if present, otherwise [fallback].
/// `T.tr` returns the key itself when no entry is found, so we use that
/// sentinel to detect missing keys and fall back to the English literal.
String _trOr(String key, String fallback) {
  final v = T.tr(key);
  return v == key ? fallback : v;
}

/// Sprint 2: Lab Trends Visualization.
///
/// Shows a marker picker at the top and an `fl_chart` LineChart below that
/// visualizes the selected marker's values over time. The reference-range
/// band (if provided by the API) is drawn as a translucent horizontal band.
class LabTrendsScreen extends ConsumerStatefulWidget {
  final String profileId;

  const LabTrendsScreen({super.key, required this.profileId});

  @override
  ConsumerState<LabTrendsScreen> createState() => _LabTrendsScreenState();
}

class _LabTrendsScreenState extends ConsumerState<LabTrendsScreen> {
  String? _selectedMarker;

  @override
  Widget build(BuildContext context) {
    final markersAsync =
        ref.watch(availableLabMarkersProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(
        title: Text(_trOr('labs.trends.title', 'Lab Trends')),
      ),
      body: markersAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: SkeletonCard(height: 240),
        ),
        error: (e, _) => _ErrorView(
          message: 'Failed to load markers: $e',
          onRetry: () =>
              ref.invalidate(availableLabMarkersProvider(widget.profileId)),
        ),
        data: (markers) {
          if (markers.isEmpty) {
            return const _EmptyView(
              icon: Icons.science_outlined,
              title: 'No lab markers yet',
              subtitle:
                  'Add lab results with at least one marker to see trends here.',
            );
          }

          // Default-select the first marker once data is loaded.
          final selected = _selectedMarker ?? markers.first;
          if (!markers.contains(selected)) {
            // Selection no longer valid — fall back to the first marker.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _selectedMarker = markers.first);
              }
            });
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: _MarkerPicker(
                  markers: markers,
                  selected: selected,
                  onChanged: (m) => setState(() => _selectedMarker = m),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _MarkerTrendChart(
                  profileId: widget.profileId,
                  marker: selected,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Marker picker
// ---------------------------------------------------------------------------

class _MarkerPicker extends StatelessWidget {
  final List<String> markers;
  final String selected;
  final ValueChanged<String> onChanged;

  const _MarkerPicker({
    required this.markers,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Prefer a horizontal chip list for <= 12 markers, else a dropdown.
    if (markers.length > 12) {
      return DropdownButtonFormField<String>(
        initialValue: selected,
        decoration: InputDecoration(
          labelText: _trOr('labs.trends.marker', 'Marker'),
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final m in markers)
            DropdownMenuItem(value: m, child: Text(m)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );
    }

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: markers.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) {
          final m = markers[i];
          final isSelected = m == selected;
          return ChoiceChip(
            label: Text(m),
            selected: isSelected,
            onSelected: (_) => onChanged(m),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chart
// ---------------------------------------------------------------------------

class _MarkerTrendChart extends ConsumerWidget {
  final String profileId;
  final String marker;

  const _MarkerTrendChart({required this.profileId, required this.marker});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = LabTrendKey(profileId, marker);
    final trendAsync = ref.watch(singleMarkerTrendProvider(key));

    return trendAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: SkeletonCard(height: 240),
      ),
      error: (e, _) => _ErrorView(
        message: 'Failed to load trend: $e',
        onRetry: () => ref.invalidate(singleMarkerTrendProvider(key)),
      ),
      data: (trend) {
        if (trend.dataPoints.isEmpty) {
          return _EmptyView(
            icon: Icons.show_chart,
            title: 'No data for "$marker"',
            subtitle:
                'This marker has no recorded values yet. Add a lab result to see its trend.',
          );
        }
        return _LineChartView(trend: trend);
      },
    );
  }
}

class _LineChartView extends StatelessWidget {
  final MarkerTrend trend;

  const _LineChartView({required this.trend});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Sort data points chronologically. We keep the parsed DateTime so we can
    // use milliseconds-since-epoch as the X axis for even spacing over time.
    final sortedPoints = [...trend.dataPoints];
    sortedPoints.sort((a, b) {
      final da = DateTime.tryParse(a.date) ?? DateTime(1970);
      final db = DateTime.tryParse(b.date) ?? DateTime(1970);
      return da.compareTo(db);
    });

    final spots = <FlSpot>[];
    final dates = <DateTime>[];
    for (final p in sortedPoints) {
      final dt = DateTime.tryParse(p.date);
      if (dt == null) continue;
      dates.add(dt);
      spots.add(FlSpot(dt.millisecondsSinceEpoch.toDouble(), p.value));
    }

    if (spots.isEmpty) {
      return _EmptyView(
        icon: Icons.show_chart,
        title: 'No plottable data',
        subtitle:
            'Values for "${trend.marker}" could not be parsed into a timeline.',
      );
    }

    // Derive Y-axis bounds from both the data and the reference range (if any)
    // so the reference band is always visible.
    final values = spots.map((s) => s.y).toList();
    double yMin = values.reduce((a, b) => a < b ? a : b);
    double yMax = values.reduce((a, b) => a > b ? a : b);
    final refLow = trend.referenceLow;
    final refHigh = trend.referenceHigh;
    if (refLow != null && refLow < yMin) yMin = refLow;
    if (refHigh != null && refHigh > yMax) yMax = refHigh;
    // Pad 10% on either side so points don't sit on the chart edge.
    final yPad = (yMax - yMin).abs() * 0.1;
    final yMinPadded = yMin - (yPad == 0 ? 1 : yPad);
    final yMaxPadded = yMax + (yPad == 0 ? 1 : yPad);

    final xMin = spots.first.x;
    final xMax = spots.last.x;
    final xRange = xMax - xMin;

    final unitSuffix =
        (trend.unit != null && trend.unit!.isNotEmpty) ? ' ${trend.unit}' : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trend.marker,
            style: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
          ),
          if (trend.unit != null && trend.unit!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Unit: ${trend.unit}',
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          if (refLow != null || refHigh != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _referenceLabel(refLow, refHigh, trend.unit),
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: LineChart(
              LineChartData(
                minX: xMin,
                maxX: xMax == xMin ? xMin + 1 : xMax,
                minY: yMinPadded,
                maxY: yMaxPadded,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    left: BorderSide(color: scheme.outlineVariant),
                    bottom: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    axisNameWidget: Text(
                      'Value${unitSuffix.isEmpty ? '' : unitSuffix}',
                      style: textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            _formatY(value),
                            style: textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: Text(
                      'Date',
                      style: textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      // Show up to ~4 date labels evenly spaced.
                      interval: xRange <= 0 ? null : xRange / 3,
                      getTitlesWidget: (value, meta) {
                        final dt = DateTime.fromMillisecondsSinceEpoch(
                            value.toInt());
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _formatDate(dt),
                            style: textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Reference-range band: drawn as two horizontal lines that
                // delimit the "normal" zone. fl_chart 1.x does not expose a
                // first-class band primitive, so we rely on extraLinesData.
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    if (refLow != null)
                      HorizontalLine(
                        y: refLow,
                        color: scheme.tertiary.withValues(alpha: 0.6),
                        strokeWidth: 1,
                        dashArray: [6, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topLeft,
                          padding: const EdgeInsets.only(left: 4, bottom: 2),
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.tertiary,
                          ),
                          labelResolver: (_) => 'Low',
                        ),
                      ),
                    if (refHigh != null)
                      HorizontalLine(
                        y: refHigh,
                        color: scheme.tertiary.withValues(alpha: 0.6),
                        strokeWidth: 1,
                        dashArray: [6, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topLeft,
                          padding: const EdgeInsets.only(left: 4, bottom: 2),
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.tertiary,
                          ),
                          labelResolver: (_) => 'High',
                        ),
                      ),
                  ],
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: false,
                    color: scheme.primary,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) {
                        final inRange = _inRange(spot.y, refLow, refHigh);
                        return FlDotCirclePainter(
                          radius: 4,
                          color: inRange ? scheme.primary : scheme.error,
                          strokeWidth: 1.5,
                          strokeColor: scheme.surface,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: scheme.primary.withValues(alpha: 0.10),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) =>
                        scheme.inverseSurface.withValues(alpha: 0.95),
                    getTooltipItems: (spots) => spots.map((ts) {
                      final dt = DateTime.fromMillisecondsSinceEpoch(
                          ts.x.toInt());
                      return LineTooltipItem(
                        '${_formatDate(dt)}\n'
                        '${_formatY(ts.y)}$unitSuffix',
                        TextStyle(
                          color: scheme.onInverseSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${dates.length} data point${dates.length == 1 ? '' : 's'}',
            style: textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  static bool _inRange(double v, double? low, double? high) {
    if (low != null && v < low) return false;
    if (high != null && v > high) return false;
    return true;
  }

  static String _referenceLabel(double? low, double? high, String? unit) {
    final u = (unit != null && unit.isNotEmpty) ? ' $unit' : '';
    if (low != null && high != null) {
      return 'Reference range: ${_formatNum(low)}–${_formatNum(high)}$u';
    }
    if (low != null) return 'Reference: ≥ ${_formatNum(low)}$u';
    if (high != null) return 'Reference: ≤ ${_formatNum(high)}$u';
    return '';
  }

  static String _formatY(double v) => _formatNum(v);

  static String _formatNum(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    if (v.abs() >= 100) return v.toStringAsFixed(0);
    if (v.abs() >= 10) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }

  static String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyView({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
            Text(
              title,
              textAlign: TextAlign.center,
              style:
                  textTheme.titleMedium?.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.xs + 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
