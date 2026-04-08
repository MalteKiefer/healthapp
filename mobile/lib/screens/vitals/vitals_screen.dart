import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/i18n/translations.dart';
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

const _rangeKeys = ['3d', '7d', '30d', '90d', '1y', 'All'];

String _rangeLabel(String key) => T.tr('range.${key.toLowerCase()}');

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

  // -- Add/Edit vital bottom sheet --------------------------------------------

  Future<void> _showFormSheet({Vital? existing}) async {
    final api = ref.read(apiClientProvider);
    final isEdit = existing != null;
    final ctrl = {
      'systolic': TextEditingController(
          text: existing?.systolic?.toStringAsFixed(0) ?? ''),
      'diastolic': TextEditingController(
          text: existing?.diastolic?.toStringAsFixed(0) ?? ''),
      'pulse': TextEditingController(
          text: existing?.pulse?.toStringAsFixed(0) ?? ''),
      'weight': TextEditingController(
          text: existing?.weight?.toStringAsFixed(1) ?? ''),
      'height': TextEditingController(
          text: existing?.height?.toStringAsFixed(1) ?? ''),
      'temp': TextEditingController(
          text: existing?.temperature?.toStringAsFixed(1) ?? ''),
      'spo2': TextEditingController(
          text: existing?.oxygenSaturation?.toStringAsFixed(0) ?? ''),
      'glucose': TextEditingController(
          text: existing?.bloodGlucose?.toStringAsFixed(0) ?? ''),
      'respiratory_rate': TextEditingController(
          text: existing?.respiratoryRate?.toString() ?? ''),
      'waist': TextEditingController(
          text: existing?.waistCircumference?.toStringAsFixed(1) ?? ''),
      'hip': TextEditingController(
          text: existing?.hipCircumference?.toStringAsFixed(1) ?? ''),
      'body_fat': TextEditingController(
          text: existing?.bodyFatPercentage?.toStringAsFixed(1) ?? ''),
      'bmi': TextEditingController(
          text: existing?.bmi?.toStringAsFixed(1) ?? ''),
      'sleep_duration': TextEditingController(
          text: existing?.sleepDurationMinutes?.toString() ?? ''),
      'device': TextEditingController(text: existing?.device ?? ''),
      'notes': TextEditingController(text: existing?.notes ?? ''),
    };
    int sleepQuality = existing?.sleepQuality ?? 5;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) {
          bool isSaving = false;
          return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: ListView(
              controller: scrollCtrl,
              children: [
                const SizedBox(height: 8),
                Text(
                  isEdit ? T.tr('vitals.edit') : T.tr('vitals.add'),
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                // -- Core vitals --
                _sheetField(ctrl['systolic']!, T.tr('vitals.systolic'), 'mmHg'),
                _sheetField(ctrl['diastolic']!, T.tr('vitals.diastolic'), 'mmHg'),
                _sheetField(ctrl['pulse']!, T.tr('vitals.pulse'), 'bpm'),
                _sheetField(ctrl['weight']!, T.tr('vitals.weight'), 'kg'),
                _sheetField(ctrl['height']!, T.tr('vitals.height'), 'cm'),
                _sheetField(ctrl['temp']!, T.tr('vitals.temperature'), '\u00b0C'),
                _sheetField(ctrl['spo2']!, T.tr('vitals.spo2'), '%'),
                _sheetField(ctrl['glucose']!, T.tr('vitals.blood_glucose'), 'mg/dL'),
                _sheetField(ctrl['respiratory_rate']!,
                    T.tr('vitals.respiratory_rate'), '/min',
                    decimal: false),
                // -- Body measurements (expanded) --
                ExpansionTile(
                  title: Text(T.tr('vitals.body_section')),
                  children: [
                    _sheetField(ctrl['waist']!,
                        T.tr('vitals.waist_circumference'), 'cm'),
                    _sheetField(ctrl['hip']!,
                        T.tr('vitals.hip_circumference'), 'cm'),
                    _sheetField(ctrl['body_fat']!,
                        T.tr('vitals.body_fat_percentage'), '%'),
                    _sheetField(ctrl['bmi']!, T.tr('vitals.bmi'), ''),
                  ],
                ),
                // -- Sleep (expanded) --
                ExpansionTile(
                  title: Text(T.tr('vitals.sleep_section')),
                  children: [
                    _sheetField(ctrl['sleep_duration']!,
                        T.tr('vitals.sleep_duration'), 'min',
                        decimal: false),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${T.tr('vitals.sleep_quality')}: $sleepQuality',
                            style: Theme.of(ctx)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                    color: Theme.of(ctx)
                                        .colorScheme
                                        .onSurfaceVariant),
                          ),
                          Slider(
                            value: sleepQuality.toDouble(),
                            min: 1,
                            max: 10,
                            divisions: 9,
                            label: sleepQuality.toString(),
                            onChanged: (v) =>
                                setSheetState(() => sleepQuality = v.round()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // -- Advanced --
                ExpansionTile(
                  title: Text(T.tr('common.advanced')),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: ctrl['device']!,
                        decoration: InputDecoration(
                            labelText: T.tr('vitals.device')),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: ctrl['notes']!,
                        decoration: InputDecoration(
                            labelText: T.tr('common.notes')),
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: isSaving ? null : () async {
                    setSheetState(() => isSaving = true);
                    double? d(String key) =>
                        double.tryParse(ctrl[key]!.text.trim());
                    int? i(String key) =>
                        int.tryParse(ctrl[key]!.text.trim());
                    final body = <String, dynamic>{
                      'measured_at': isEdit
                          ? existing.measuredAt
                          : DateTime.now().toUtc().toIso8601String(),
                      if (d('systolic') != null)
                        'blood_pressure_systolic': d('systolic'),
                      if (d('diastolic') != null)
                        'blood_pressure_diastolic': d('diastolic'),
                      if (d('pulse') != null) 'pulse': d('pulse'),
                      if (d('weight') != null) 'weight': d('weight'),
                      if (d('height') != null) 'height': d('height'),
                      if (d('temp') != null) 'body_temperature': d('temp'),
                      if (d('spo2') != null) 'oxygen_saturation': d('spo2'),
                      if (d('glucose') != null) 'blood_glucose': d('glucose'),
                      if (i('respiratory_rate') != null)
                        'respiratory_rate': i('respiratory_rate'),
                      if (d('waist') != null)
                        'waist_circumference': d('waist'),
                      if (d('hip') != null) 'hip_circumference': d('hip'),
                      if (d('body_fat') != null)
                        'body_fat_percentage': d('body_fat'),
                      if (d('bmi') != null) 'bmi': d('bmi'),
                      if (i('sleep_duration') != null)
                        'sleep_duration_minutes': i('sleep_duration'),
                      if (existing?.sleepQuality != null ||
                          sleepQuality != 5)
                        'sleep_quality': sleepQuality,
                      if (ctrl['device']!.text.trim().isNotEmpty)
                        'device': ctrl['device']!.text.trim(),
                      if (ctrl['notes']!.text.trim().isNotEmpty)
                        'notes': ctrl['notes']!.text.trim(),
                    };
                    try {
                      if (isEdit) {
                        await api.patch<void>(
                          '/api/v1/profiles/${widget.profileId}/vitals/${existing.id}',
                          body: body,
                        );
                      } else {
                        await api.post<void>(
                          '/api/v1/profiles/${widget.profileId}/vitals',
                          body: body,
                        );
                      }
                      ref.invalidate(_vitalsProvider(widget.profileId));
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      if (ctx.mounted) {
                        setSheetState(() => isSaving = false);
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                  },
                  child: isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(T.tr('common.save')),
                ),
              ],
            ),
          ),
        );
        },
      ),
    );
    for (final c in ctrl.values) {
      c.dispose();
    }
  }

  Widget _sheetField(TextEditingController ctrl, String label, String suffix,
      {bool decimal = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : const TextInputType.numberWithOptions(decimal: false),
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
        title: Text(T.tr('vitals.delete')),
        content: Text(T.tr('vitals.delete_body')),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(T.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(T.tr('common.delete')),
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

  // -- Share ------------------------------------------------------------------

  void _shareVitals(List<Vital> vitals) {
    if (vitals.isEmpty) return;
    final latest = vitals.last;
    final parts = <String>[
      'My Vitals (${DateFormat('dd.MM.yyyy').format(DateTime.now())})',
    ];
    if (latest.systolic != null && latest.diastolic != null) {
      parts.add(
          'BP: ${latest.systolic!.toInt()}/${latest.diastolic!.toInt()} mmHg');
    }
    if (latest.pulse != null) {
      parts.add('Pulse: ${latest.pulse!.toInt()} bpm');
    }
    if (latest.weight != null) {
      parts.add('Weight: ${latest.weight!.toStringAsFixed(1)} kg');
    }
    if (latest.temperature != null) {
      parts.add('Temp: ${latest.temperature!.toStringAsFixed(1)} \u00b0C');
    }
    if (latest.oxygenSaturation != null) {
      parts.add('SpO\u2082: ${latest.oxygenSaturation!.toInt()} %');
    }
    if (latest.bloodGlucose != null) {
      parts.add('Glucose: ${latest.bloodGlucose!.toInt()} mg/dL');
    }
    Share.share(parts.join('\n'));
  }

  // -- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final vitalsAsync = ref.watch(_vitalsProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(
        title: Text(T.tr('vitals.title')),
        automaticallyImplyLeading: false,
        actions: [
          vitalsAsync.whenOrNull(
                data: (vitals) => IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: T.tr('common.share'),
                  onPressed: () => _shareVitals(_filtered(vitals)),
                ),
              ) ??
              const SizedBox.shrink(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormSheet(),
        child: const Icon(Icons.add),
      ),
      body: vitalsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(T.tr('vitals.failed'), style: tt.bodyLarge),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () =>
                  ref.invalidate(_vitalsProvider(widget.profileId)),
              child: Text(T.tr('common.retry')),
            ),
          ]),
        ),
        data: (vitals) {
          final filtered = _filtered(vitals);
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_vitalsProvider(widget.profileId));
            },
            child: CustomScrollView(
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
                    children: _rangeKeys.map((r) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(_rangeLabel(r)),
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
                    T.tr('vitals.readings'),
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
                        T.tr('vitals.no_data'),
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
                      return _VitalCard(
                        vital: v,
                        onDelete: () => _delete(v.id),
                        onTap: () => _showFormSheet(existing: v),
                      );
                    },
                    childCount: filtered.length,
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
            ],
          ),
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
            '${T.tr('vitals.no_data')} (${metric.label})',
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
  final VoidCallback onTap;
  const _VitalCard({
    required this.vital,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final date = DateTime.tryParse(vital.measuredAt);
    final dateStr =
        date != null ? DateFormat('MMM d, yyyy \u2013 HH:mm').format(date.toLocal()) : vital.measuredAt;

    final entries = <MapEntry<String, String>>[];
    if (vital.systolic != null && vital.diastolic != null) {
      entries.add(MapEntry(T.tr('vitals.bp'), '${vital.systolic!.toInt()}/${vital.diastolic!.toInt()} mmHg'));
    }
    if (vital.pulse != null) {
      entries.add(MapEntry(T.tr('vitals.pulse'), '${vital.pulse!.toInt()} bpm'));
    }
    if (vital.weight != null) {
      entries.add(MapEntry(T.tr('vitals.weight'), '${vital.weight!.toStringAsFixed(1)} kg'));
    }
    if (vital.temperature != null) {
      entries.add(MapEntry(T.tr('vitals.temperature'), '${vital.temperature!.toStringAsFixed(1)} \u00b0C'));
    }
    if (vital.oxygenSaturation != null) {
      entries.add(MapEntry(T.tr('vitals.spo2'), '${vital.oxygenSaturation!.toInt()} %'));
    }
    if (vital.bloodGlucose != null) {
      entries.add(MapEntry(T.tr('vitals.blood_glucose'), '${vital.bloodGlucose!.toInt()} mg/dL'));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Dismissible(
        key: ValueKey(vital.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          onDelete();
          return false;
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: cs.error,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.delete_outline, color: cs.onError),
        ),
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
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
      ),
    );
  }
}
