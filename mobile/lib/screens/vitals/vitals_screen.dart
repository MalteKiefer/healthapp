import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/vital.dart';
import '../../providers/providers.dart';

// -- Providers ----------------------------------------------------------------

final _vitalsProvider =
    FutureProvider.family<List<Vital>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final data =
      await api.get<Map<String, dynamic>>('/api/v1/profiles/$profileId/vitals');
  return (data['items'] as List)
      .map((v) => Vital.fromJson(v as Map<String, dynamic>))
      .toList();
});

// -- Helpers ------------------------------------------------------------------

enum _Metric { bp, pulse, weight, temp, spo2, glucose }

extension _MetricExt on _Metric {
  String get label => const {
        _Metric.bp: 'BP',
        _Metric.pulse: 'Pulse',
        _Metric.weight: 'Weight',
        _Metric.temp: 'Temp',
        _Metric.spo2: 'SpO\u2082',
        _Metric.glucose: 'Glucose',
      }[this]!;

  String get unit => const {
        _Metric.bp: 'mmHg',
        _Metric.pulse: 'bpm',
        _Metric.weight: 'kg',
        _Metric.temp: '\u00b0C',
        _Metric.spo2: '%',
        _Metric.glucose: 'mg/dL',
      }[this]!;

  IconData get icon => const {
        _Metric.bp: Icons.favorite,
        _Metric.pulse: Icons.timeline,
        _Metric.weight: Icons.monitor_weight_outlined,
        _Metric.temp: Icons.thermostat,
        _Metric.spo2: Icons.air,
        _Metric.glucose: Icons.water_drop_outlined,
      }[this]!;

  double? valueFrom(Vital v) => switch (this) {
        _Metric.bp => v.systolic,
        _Metric.pulse => v.pulse,
        _Metric.weight => v.weight,
        _Metric.temp => v.temperature,
        _Metric.spo2 => v.oxygenSaturation,
        _Metric.glucose => v.bloodGlucose,
      };

  (double, double)? get normalRange => switch (this) {
        _Metric.bp => (90.0, 120.0),
        _Metric.pulse => (60.0, 100.0),
        _Metric.temp => (36.1, 37.2),
        _Metric.spo2 => (95.0, 100.0),
        _Metric.glucose => (70.0, 100.0),
        _Metric.weight => null,
      };
}

const _ranges = ['3d', '7d', '30d', '90d', '1y', 'All'];

DateTime _rangeStart(String range) {
  final now = DateTime.now();
  return switch (range) {
    '3d' => now.subtract(const Duration(days: 3)),
    '7d' => now.subtract(const Duration(days: 7)),
    '30d' => now.subtract(const Duration(days: 30)),
    '90d' => now.subtract(const Duration(days: 90)),
    '1y' => now.subtract(const Duration(days: 365)),
    _ => DateTime(2000),
  };
}

// -- Screen -------------------------------------------------------------------

class VitalsScreen extends ConsumerStatefulWidget {
  final String profileId;
  const VitalsScreen({super.key, required this.profileId});

  @override
  ConsumerState<VitalsScreen> createState() => _VitalsScreenState();
}

class _VitalsScreenState extends ConsumerState<VitalsScreen> {
  String _range = '3d';
  _Metric _metric = _Metric.bp;

  List<Vital> _filtered(List<Vital> all) {
    final cutoff = _rangeStart(_range);
    return all
        .where((v) => DateTime.tryParse(v.measuredAt)?.isAfter(cutoff) ?? true)
        .toList()
      ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
  }

  // -- Add vital bottom sheet -------------------------------------------------

  Future<void> _showAddSheet() async {
    final ctrl = {
      'systolic': TextEditingController(),
      'diastolic': TextEditingController(),
      'pulse': TextEditingController(),
      'weight': TextEditingController(),
      'temp': TextEditingController(),
      'spo2': TextEditingController(),
      'glucose': TextEditingController(),
    };

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (ctx, scrollCtrl) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: ListView(
            controller: scrollCtrl,
            children: [
              const SizedBox(height: 8),
              Text('Add Vital', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 20),
              _sheetField(ctrl['systolic']!, 'Systolic', 'mmHg'),
              _sheetField(ctrl['diastolic']!, 'Diastolic', 'mmHg'),
              _sheetField(ctrl['pulse']!, 'Pulse', 'bpm'),
              _sheetField(ctrl['weight']!, 'Weight', 'kg'),
              _sheetField(ctrl['temp']!, 'Temperature', '\u00b0C'),
              _sheetField(ctrl['spo2']!, 'SpO\u2082', '%'),
              _sheetField(ctrl['glucose']!, 'Blood Glucose', 'mg/dL'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  double? d(String key) =>
                      double.tryParse(ctrl[key]!.text.trim());
                  final body = <String, dynamic>{
                    'measured_at': DateTime.now().toUtc().toIso8601String(),
                    if (d('systolic') != null)
                      'blood_pressure_systolic': d('systolic'),
                    if (d('diastolic') != null)
                      'blood_pressure_diastolic': d('diastolic'),
                    if (d('pulse') != null) 'pulse': d('pulse'),
                    if (d('weight') != null) 'weight': d('weight'),
                    if (d('temp') != null) 'body_temperature': d('temp'),
                    if (d('spo2') != null) 'oxygen_saturation': d('spo2'),
                    if (d('glucose') != null) 'blood_glucose': d('glucose'),
                  };
                  try {
                    final api = ref.read(apiClientProvider);
                    await api.post<void>(
                      '/api/v1/profiles/${widget.profileId}/vitals',
                      body: body,
                    );
                    ref.invalidate(_vitalsProvider(widget.profileId));
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
    for (final c in ctrl.values) {
      c.dispose();
    }
  }

  Widget _sheetField(TextEditingController ctrl, String label, String suffix) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
        ),
      ),
    );
  }

  // -- Delete -----------------------------------------------------------------

  Future<void> _delete(String vitalId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Vital'),
        content: const Text('This reading will be permanently removed.'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final api = ref.read(apiClientProvider);
      await api
          .delete('/api/v1/profiles/${widget.profileId}/vitals/$vitalId');
      ref.invalidate(_vitalsProvider(widget.profileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // -- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final vitalsAsync = ref.watch(_vitalsProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vitals'),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        child: const Icon(Icons.add),
      ),
      body: vitalsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text('Failed to load vitals', style: tt.bodyLarge),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () =>
                  ref.invalidate(_vitalsProvider(widget.profileId)),
              child: const Text('Retry'),
            ),
          ]),
        ),
        data: (vitals) {
          final filtered = _filtered(vitals);
          return CustomScrollView(
            slivers: [
              // Metric chips
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: _Metric.values.map((m) {
                      final selected = m == _metric;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          avatar: Icon(m.icon, size: 16),
                          label: Text(m.label),
                          selected: selected,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _metric = m),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              // Time range chips
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: _ranges.map((r) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(r),
                          selected: r == _range,
                          onSelected: (_) => setState(() => _range = r),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              // Chart
              SliverToBoxAdapter(
                child: _ChartSection(
                  vitals: filtered,
                  metric: _metric,
                ),
              ),
              // Heading
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Readings',
                    style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
              // Value cards
              if (filtered.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No vitals for this period',
                        style: tt.bodyMedium?.copyWith(color: cs.outline),
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final v = filtered[filtered.length - 1 - i]; // newest first
                      return _VitalCard(vital: v, onDelete: () => _delete(v.id));
                    },
                    childCount: filtered.length,
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
            ],
          );
        },
      ),
    );
  }
}

// -- Chart Section ------------------------------------------------------------

class _ChartSection extends StatelessWidget {
  final List<Vital> vitals;
  final _Metric metric;
  const _ChartSection({required this.vitals, required this.metric});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final points = vitals
        .asMap()
        .entries
        .where((e) => metric.valueFrom(e.value) != null)
        .map((e) => FlSpot(e.key.toDouble(), metric.valueFrom(e.value)!))
        .toList();

    if (points.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'No ${metric.label} data for this period',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.outline),
          ),
        ),
      );
    }

    final minY = points.map((p) => p.y).reduce((a, b) => a < b ? a : b);
    final maxY = points.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY) * 0.15).clamp(1.0, double.infinity);
    final range = metric.normalRange;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 20, 0),
      child: SizedBox(
        height: 200,
        child: LineChart(
          LineChartData(
            minY: minY - pad,
            maxY: maxY + pad,
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                if (range != null) ...[
                  HorizontalLine(
                    y: range.$1,
                    color: Colors.green.withValues(alpha: 0.4),
                    strokeWidth: 1,
                    dashArray: [6, 4],
                  ),
                  HorizontalLine(
                    y: range.$2,
                    color: Colors.orange.withValues(alpha: 0.4),
                    strokeWidth: 1,
                    dashArray: [6, 4],
                  ),
                ],
              ],
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => spots.map((s) {
                  final idx = s.x.toInt();
                  final dateStr =
                      idx < vitals.length ? vitals[idx].measuredAt : '';
                  final date = DateTime.tryParse(dateStr);
                  final label =
                      date != null ? DateFormat('MMM d').format(date) : '';
                  return LineTooltipItem(
                    '$label\n${s.y.toStringAsFixed(1)} ${metric.unit}',
                    TextStyle(color: cs.onSurface, fontSize: 12),
                  );
                }).toList(),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: cs.outlineVariant.withValues(alpha: 0.3), strokeWidth: 0.5),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 42,
                  getTitlesWidget: (v, _) => Text(
                    v.toStringAsFixed(0),
                    style: TextStyle(color: cs.outline, fontSize: 10),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval:
                      (points.length / 4).ceilToDouble().clamp(1, double.infinity),
                  getTitlesWidget: (v, _) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= vitals.length) {
                      return const SizedBox();
                    }
                    final date = DateTime.tryParse(vitals[idx].measuredAt);
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        date != null ? DateFormat('d/M').format(date) : '',
                        style: TextStyle(color: cs.outline, fontSize: 9),
                      ),
                    );
                  },
                ),
              ),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: points,
                isCurved: true,
                curveSmoothness: 0.3,
                color: cs.primary,
                barWidth: 2.5,
                dotData: FlDotData(
                  show: points.length <= 30,
                  getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                    radius: 3,
                    color: cs.primary,
                    strokeWidth: 1.5,
                    strokeColor: cs.surface,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      cs.primary.withValues(alpha: 0.15),
                      cs.primary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -- Vital Card ---------------------------------------------------------------

class _VitalCard extends StatelessWidget {
  final Vital vital;
  final VoidCallback onDelete;
  const _VitalCard({required this.vital, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final date = DateTime.tryParse(vital.measuredAt);
    final dateStr =
        date != null ? DateFormat('MMM d, yyyy \u2013 HH:mm').format(date.toLocal()) : vital.measuredAt;

    final entries = <MapEntry<String, String>>[];
    if (vital.systolic != null && vital.diastolic != null) {
      entries.add(MapEntry('BP', '${vital.systolic!.toInt()}/${vital.diastolic!.toInt()} mmHg'));
    }
    if (vital.pulse != null) {
      entries.add(MapEntry('Pulse', '${vital.pulse!.toInt()} bpm'));
    }
    if (vital.weight != null) {
      entries.add(MapEntry('Weight', '${vital.weight!.toStringAsFixed(1)} kg'));
    }
    if (vital.temperature != null) {
      entries.add(MapEntry('Temp', '${vital.temperature!.toStringAsFixed(1)} \u00b0C'));
    }
    if (vital.oxygenSaturation != null) {
      entries.add(MapEntry('SpO\u2082', '${vital.oxygenSaturation!.toInt()} %'));
    }
    if (vital.bloodGlucose != null) {
      entries.add(MapEntry('Glucose', '${vital.bloodGlucose!.toInt()} mg/dL'));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onLongPress: onDelete,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateStr,
                  style: tt.labelSmall?.copyWith(color: cs.outline),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: entries.map((e) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(e.key, style: tt.labelSmall?.copyWith(color: cs.outline)),
                        const SizedBox(height: 2),
                        Text(
                          e.value,
                          style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
