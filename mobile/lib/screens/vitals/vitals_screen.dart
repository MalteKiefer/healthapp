import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../models/vital.dart';
import '../../providers/providers.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _vitalsProvider =
    FutureProvider.family<List<Vital>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final data =
      await api.get<Map<String, dynamic>>('/api/v1/profiles/$profileId/vitals');
  return (data['items'] as List)
      .map((v) => Vital.fromJson(v as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

enum _Metric { bp, pulse, weight, temp, spo2, glucose }

extension _MetricExt on _Metric {
  String get label => const {
        _Metric.bp: 'BP',
        _Metric.pulse: 'Pulse',
        _Metric.weight: 'Weight',
        _Metric.temp: 'Temp',
        _Metric.spo2: 'SpO2',
        _Metric.glucose: 'Glucose',
      }[this]!;

  String get unit => const {
        _Metric.bp: 'mmHg',
        _Metric.pulse: 'bpm',
        _Metric.weight: 'kg',
        _Metric.temp: '°C',
        _Metric.spo2: '%',
        _Metric.glucose: 'mg/dL',
      }[this]!;

  double? valueFrom(Vital v) => switch (this) {
        _Metric.bp => v.systolic,
        _Metric.pulse => v.pulse,
        _Metric.weight => v.weight,
        _Metric.temp => v.temperature,
        _Metric.spo2 => v.oxygenSaturation,
        _Metric.glucose => v.bloodGlucose,
      };

  // [min, max] normal range for reference lines; null = no line
  (double, double)? get normalRange => switch (this) {
        _Metric.bp => (90.0, 120.0),
        _Metric.pulse => (60.0, 100.0),
        _Metric.temp => (36.1, 37.2),
        _Metric.spo2 => (95.0, 100.0),
        _Metric.glucose => (70.0, 100.0),
        _Metric.weight => null,
      };
}

const _ranges = ['7d', '30d', '90d', '1y', 'All'];

DateTime _rangeStart(String range) {
  final now = DateTime.now();
  return switch (range) {
    '7d' => now.subtract(const Duration(days: 7)),
    '30d' => now.subtract(const Duration(days: 30)),
    '90d' => now.subtract(const Duration(days: 90)),
    '1y' => now.subtract(const Duration(days: 365)),
    _ => DateTime(2000),
  };
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class VitalsScreen extends ConsumerStatefulWidget {
  final String profileId;
  const VitalsScreen({super.key, required this.profileId});

  @override
  ConsumerState<VitalsScreen> createState() => _VitalsScreenState();
}

class _VitalsScreenState extends ConsumerState<VitalsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _range = '30d';
  _Metric _metric = _Metric.bp;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Data helpers
  // -------------------------------------------------------------------------

  List<Vital> _filtered(List<Vital> all) {
    final cutoff = _rangeStart(_range);
    return all
        .where((v) => DateTime.tryParse(v.measuredAt)?.isAfter(cutoff) ?? true)
        .toList()
      ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
  }

  // -------------------------------------------------------------------------
  // Dialogs
  // -------------------------------------------------------------------------

  Future<void> _showAddDialog() async {
    final ctrl = {
      'systolic': TextEditingController(),
      'diastolic': TextEditingController(),
      'pulse': TextEditingController(),
      'weight': TextEditingController(),
      'temp': TextEditingController(),
      'spo2': TextEditingController(),
      'glucose': TextEditingController(),
    };
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Vital'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _numField(ctrl['systolic']!, 'Systolic (mmHg)'),
              _numField(ctrl['diastolic']!, 'Diastolic (mmHg)'),
              _numField(ctrl['pulse']!, 'Pulse (bpm)'),
              _numField(ctrl['weight']!, 'Weight (kg)'),
              _numField(ctrl['temp']!, 'Temperature (°C)'),
              _numField(ctrl['spo2']!, 'SpO2 (%)'),
              _numField(ctrl['glucose']!, 'Blood Glucose (mg/dL)'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              double? _d(String key) =>
                  double.tryParse(ctrl[key]!.text.trim());
              final body = <String, dynamic>{
                'measured_at': DateTime.now().toUtc().toIso8601String(),
                if (_d('systolic') != null)
                  'blood_pressure_systolic': _d('systolic'),
                if (_d('diastolic') != null)
                  'blood_pressure_diastolic': _d('diastolic'),
                if (_d('pulse') != null) 'pulse': _d('pulse'),
                if (_d('weight') != null) 'weight': _d('weight'),
                if (_d('temp') != null) 'body_temperature': _d('temp'),
                if (_d('spo2') != null) 'oxygen_saturation': _d('spo2'),
                if (_d('glucose') != null) 'blood_glucose': _d('glucose'),
              };
              try {
                final api = ref.read(apiClientProvider);
                await api.post<void>(
                    '/api/v1/profiles/${widget.profileId}/vitals',
                    body: body);
                ref.invalidate(_vitalsProvider(widget.profileId));
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    for (final c in ctrl.values) {
      c.dispose();
    }
  }

  Future<void> _delete(String vitalId) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.delete(
          '/api/v1/profiles/${widget.profileId}/vitals/$vitalId');
      ref.invalidate(_vitalsProvider(widget.profileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final vitalsAsync = ref.watch(_vitalsProvider(widget.profileId));
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: const Text('Vitals'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(icon: Icon(Icons.list)), Tab(icon: Icon(Icons.show_chart))],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: vitalsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (vitals) => Column(
          children: [
            _RangeFilter(
              selected: _range,
              onSelected: (r) => setState(() => _range = r),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _ListView(
                    vitals: _filtered(vitals),
                    onDelete: _delete,
                  ),
                  _ChartView(
                    vitals: _filtered(vitals),
                    metric: _metric,
                    onMetricChanged: (m) => setState(() => _metric = m),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Range filter row
// ---------------------------------------------------------------------------

class _RangeFilter extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;
  const _RangeFilter({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: _ranges
            .map((r) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(r),
                    selected: r == selected,
                    onSelected: (_) => onSelected(r),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// List view
// ---------------------------------------------------------------------------

class _ListView extends StatelessWidget {
  final List<Vital> vitals;
  final Future<void> Function(String) onDelete;
  const _ListView({required this.vitals, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    if (vitals.isEmpty) {
      return const Center(child: Text('No vitals recorded.'));
    }
    return ListView.builder(
      itemCount: vitals.length,
      itemBuilder: (ctx, i) {
        final v = vitals[vitals.length - 1 - i]; // newest first
        return Dismissible(
          key: ValueKey(v.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Theme.of(ctx).colorScheme.error,
            child: Icon(Icons.delete,
                color: Theme.of(ctx).colorScheme.onError),
          ),
          onDismissed: (_) => onDelete(v.id),
          child: _VitalCard(vital: v),
        );
      },
    );
  }
}

class _VitalCard extends StatelessWidget {
  final Vital vital;
  const _VitalCard({required this.vital});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(vital.measuredAt);
    final fmt = date != null ? DateFormat('dd MMM yyyy HH:mm').format(date) : vital.measuredAt;
    final chips = <String>[];
    if (vital.systolic != null && vital.diastolic != null) {
      chips.add('BP ${vital.systolic!.toInt()}/${vital.diastolic!.toInt()} mmHg');
    }
    if (vital.pulse != null) chips.add('Pulse ${vital.pulse!.toInt()} bpm');
    if (vital.weight != null) chips.add('${vital.weight!.toStringAsFixed(1)} kg');
    if (vital.temperature != null) chips.add('${vital.temperature!.toStringAsFixed(1)} °C');
    if (vital.oxygenSaturation != null) chips.add('SpO2 ${vital.oxygenSaturation!.toInt()}%');
    if (vital.bloodGlucose != null) chips.add('Glu ${vital.bloodGlucose!.toInt()} mg/dL');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fmt,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: chips
                  .map((c) => Chip(
                        label: Text(c,
                            style: Theme.of(context).textTheme.bodySmall),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chart view
// ---------------------------------------------------------------------------

class _ChartView extends StatelessWidget {
  final List<Vital> vitals;
  final _Metric metric;
  final ValueChanged<_Metric> onMetricChanged;
  const _ChartView(
      {required this.vitals,
      required this.metric,
      required this.onMetricChanged});

  @override
  Widget build(BuildContext context) {
    final points = vitals
        .asMap()
        .entries
        .where((e) => metric.valueFrom(e.value) != null)
        .map((e) => FlSpot(e.key.toDouble(), metric.valueFrom(e.value)!))
        .toList();

    return Column(
      children: [
        // Metric selector chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: _Metric.values
                .map((m) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(m.label),
                        selected: m == metric,
                        onSelected: (_) => onMetricChanged(m),
                      ),
                    ))
                .toList(),
          ),
        ),
        Expanded(
          child: points.isEmpty
              ? const Center(child: Text('No data for selected metric.'))
              : Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 24, 16),
                  child: _buildChart(context, points),
                ),
        ),
      ],
    );
  }

  Widget _buildChart(BuildContext context, List<FlSpot> points) {
    final cs = Theme.of(context).colorScheme;
    final minY = points.map((p) => p.y).reduce((a, b) => a < b ? a : b);
    final maxY = points.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY) * 0.15).clamp(1.0, double.infinity);
    final range = metric.normalRange;

    final refLines = <HorizontalLine>[
      if (range != null) ...[
        HorizontalLine(
          y: range.$1,
          color: Colors.green.withOpacity(0.5),
          strokeWidth: 1,
          dashArray: [6, 4],
          label: HorizontalLineLabel(
            show: true,
            labelResolver: (_) => 'Min',
            style: TextStyle(color: Colors.green.shade700, fontSize: 10),
          ),
        ),
        HorizontalLine(
          y: range.$2,
          color: Colors.orange.withOpacity(0.5),
          strokeWidth: 1,
          dashArray: [6, 4],
          label: HorizontalLineLabel(
            show: true,
            labelResolver: (_) => 'Max',
            style: TextStyle(color: Colors.orange.shade700, fontSize: 10),
          ),
        ),
      ],
    ];

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        extraLinesData: ExtraLinesData(horizontalLines: refLines),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              final idx = s.x.toInt();
              final dateStr = idx < vitals.length
                  ? vitals[idx].measuredAt
                  : '';
              final date = DateTime.tryParse(dateStr);
              final label = date != null
                  ? DateFormat('dd MMM').format(date)
                  : '';
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
              FlLine(color: cs.outlineVariant, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: Text(metric.unit,
                style: TextStyle(color: cs.outline, fontSize: 11)),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
                  style: TextStyle(color: cs.outline, fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: (points.length / 4).ceilToDouble().clamp(1, double.infinity),
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= vitals.length) return const SizedBox();
                final date = DateTime.tryParse(vitals[idx].measuredAt);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    date != null ? DateFormat('dd/MM').format(date) : '',
                    style: TextStyle(color: cs.outline, fontSize: 9),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: points,
            isCurved: true,
            curveSmoothness: 0.35,
            color: cs.primary,
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 3,
                color: cs.primary,
                strokeWidth: 1.5,
                strokeColor: cs.surface,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: cs.primary.withOpacity(0.08),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _numField(TextEditingController ctrl, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
