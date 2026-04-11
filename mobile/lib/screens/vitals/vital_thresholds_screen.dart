import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/vital_thresholds.dart';
import '../../providers/vital_thresholds_provider.dart';

/// Configuration screen for per-profile vital thresholds.
///
/// Renders a form with low/high pairs for blood pressure (systolic and
/// diastolic), heart rate, body temperature, SpO2, blood glucose and
/// body weight. Saving issues a PUT to the vital-thresholds endpoint via
/// [vitalThresholdsSaveProvider].
class VitalThresholdsScreen extends ConsumerStatefulWidget {
  const VitalThresholdsScreen({
    super.key,
    required this.profileId,
  });

  final String profileId;

  @override
  ConsumerState<VitalThresholdsScreen> createState() =>
      _VitalThresholdsScreenState();
}

class _VitalThresholdsScreenState
    extends ConsumerState<VitalThresholdsScreen> {
  final _formKey = GlobalKey<FormState>();

  // One controller per field. Keyed so we can programmatically populate
  // them when the async read finishes.
  late final Map<String, TextEditingController> _controllers = {
    for (final k in _fieldKeys) k: TextEditingController(),
  };

  // Preserved extras from the GET response so a save round-trip does not
  // drop unknown metric keys the UI does not render.
  Map<String, Map<String, dynamic>> _extras = const {};

  bool _initialized = false;

  static const List<_ThresholdMetric> _metrics = [
    _ThresholdMetric(
      label: 'Blood pressure — systolic',
      unit: 'mmHg',
      lowKey: 'systolic_low',
      highKey: 'systolic_high',
      decimals: false,
      minValue: 40,
      maxValue: 260,
    ),
    _ThresholdMetric(
      label: 'Blood pressure — diastolic',
      unit: 'mmHg',
      lowKey: 'diastolic_low',
      highKey: 'diastolic_high',
      decimals: false,
      minValue: 20,
      maxValue: 200,
    ),
    _ThresholdMetric(
      label: 'Heart rate',
      unit: 'bpm',
      lowKey: 'heart_rate_low',
      highKey: 'heart_rate_high',
      decimals: false,
      minValue: 20,
      maxValue: 250,
    ),
    _ThresholdMetric(
      label: 'Body temperature',
      unit: '°C',
      lowKey: 'temperature_low',
      highKey: 'temperature_high',
      decimals: true,
      minValue: 30,
      maxValue: 45,
    ),
    _ThresholdMetric(
      label: 'Oxygen saturation (SpO2)',
      unit: '%',
      lowKey: 'spo2_low',
      highKey: 'spo2_high',
      decimals: false,
      minValue: 50,
      maxValue: 100,
    ),
    _ThresholdMetric(
      label: 'Blood glucose',
      unit: 'mmol/L',
      lowKey: 'glucose_low',
      highKey: 'glucose_high',
      decimals: true,
      minValue: 0,
      maxValue: 40,
    ),
    _ThresholdMetric(
      label: 'Weight',
      unit: 'kg',
      lowKey: 'weight_low',
      highKey: 'weight_high',
      decimals: true,
      minValue: 0,
      maxValue: 400,
    ),
  ];

  static Iterable<String> get _fieldKeys sync* {
    for (final m in _metrics) {
      yield m.lowKey;
      yield m.highKey;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _populate(VitalThresholds t) {
    String fmt(double? v) => v == null ? '' : _stripTrailingZero(v);
    _controllers['systolic_low']!.text = fmt(t.systolicLow);
    _controllers['systolic_high']!.text = fmt(t.systolicHigh);
    _controllers['diastolic_low']!.text = fmt(t.diastolicLow);
    _controllers['diastolic_high']!.text = fmt(t.diastolicHigh);
    _controllers['heart_rate_low']!.text = fmt(t.heartRateLow);
    _controllers['heart_rate_high']!.text = fmt(t.heartRateHigh);
    _controllers['temperature_low']!.text = fmt(t.temperatureLow);
    _controllers['temperature_high']!.text = fmt(t.temperatureHigh);
    _controllers['spo2_low']!.text = fmt(t.spo2Low);
    _controllers['spo2_high']!.text = fmt(t.spo2High);
    _controllers['glucose_low']!.text = fmt(t.glucoseLow);
    _controllers['glucose_high']!.text = fmt(t.glucoseHigh);
    _controllers['weight_low']!.text = fmt(t.weightLow);
    _controllers['weight_high']!.text = fmt(t.weightHigh);
    _extras = t.extras;
    _initialized = true;
  }

  static String _stripTrailingZero(double v) {
    if (v == v.truncateToDouble()) {
      return v.toStringAsFixed(0);
    }
    return v.toString();
  }

  double? _parse(String key) {
    final raw = _controllers[key]!.text.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw.replaceAll(',', '.'));
  }

  VitalThresholds _buildPayload() {
    return VitalThresholds(
      systolicLow: _parse('systolic_low'),
      systolicHigh: _parse('systolic_high'),
      diastolicLow: _parse('diastolic_low'),
      diastolicHigh: _parse('diastolic_high'),
      heartRateLow: _parse('heart_rate_low'),
      heartRateHigh: _parse('heart_rate_high'),
      temperatureLow: _parse('temperature_low'),
      temperatureHigh: _parse('temperature_high'),
      spo2Low: _parse('spo2_low'),
      spo2High: _parse('spo2_high'),
      glucoseLow: _parse('glucose_low'),
      glucoseHigh: _parse('glucose_high'),
      weightLow: _parse('weight_low'),
      weightHigh: _parse('weight_high'),
      extras: _extras,
    );
  }

  Future<void> _onSave() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final payload = _buildPayload();
    final ok = await ref
        .read(vitalThresholdsSaveProvider.notifier)
        .save(widget.profileId, payload);

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Vital thresholds saved')),
      );
      Navigator.of(context).maybePop();
    } else {
      final err = ref.read(vitalThresholdsSaveProvider).error;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to save thresholds: $err')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(vitalThresholdsProvider(widget.profileId));
    final saveState = ref.watch(vitalThresholdsSaveProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vital thresholds'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: scheme.error, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Could not load thresholds',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '$e',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(
                    vitalThresholdsProvider(widget.profileId),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (thresholds) {
          if (!_initialized) {
            _populate(thresholds);
          }
          return _buildForm(context, scheme, saveState);
        },
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    ColorScheme scheme,
    VitalThresholdsSaveState saveState,
  ) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            color: scheme.surfaceContainerHighest,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Define normal low/high ranges for each metric. '
                      'Leave a field empty to remove that bound.',
                      style: TextStyle(color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final m in _metrics) ...[
            _MetricCard(
              metric: m,
              lowController: _controllers[m.lowKey]!,
              highController: _controllers[m.highKey]!,
              validator: (low, high) => _validatePair(m, low, high),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: saveState.saving ? null : _onSave,
            icon: saveState.saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(saveState.saving ? 'Saving…' : 'Save thresholds'),
          ),
        ],
      ),
    );
  }

  String? _validatePair(_ThresholdMetric m, String? lowRaw, String? highRaw) {
    double? parse(String? s) {
      if (s == null) return null;
      final t = s.trim();
      if (t.isEmpty) return null;
      return double.tryParse(t.replaceAll(',', '.'));
    }

    final lowStr = (lowRaw ?? '').trim();
    final highStr = (highRaw ?? '').trim();

    if (lowStr.isNotEmpty && parse(lowStr) == null) {
      return 'Low: enter a valid number';
    }
    if (highStr.isNotEmpty && parse(highStr) == null) {
      return 'High: enter a valid number';
    }
    final low = parse(lowStr);
    final high = parse(highStr);

    if (low != null && (low < m.minValue || low > m.maxValue)) {
      return 'Low out of range (${_fmt(m.minValue)}–${_fmt(m.maxValue)})';
    }
    if (high != null && (high < m.minValue || high > m.maxValue)) {
      return 'High out of range (${_fmt(m.minValue)}–${_fmt(m.maxValue)})';
    }
    if (low != null && high != null && low > high) {
      return 'Low must be ≤ high';
    }
    return null;
  }

  static String _fmt(double v) {
    if (v == v.truncateToDouble()) return v.toStringAsFixed(0);
    return v.toString();
  }
}

class _ThresholdMetric {
  final String label;
  final String unit;
  final String lowKey;
  final String highKey;
  final bool decimals;
  final double minValue;
  final double maxValue;

  const _ThresholdMetric({
    required this.label,
    required this.unit,
    required this.lowKey,
    required this.highKey,
    required this.decimals,
    required this.minValue,
    required this.maxValue,
  });
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.metric,
    required this.lowController,
    required this.highController,
    required this.validator,
  });

  final _ThresholdMetric metric;
  final TextEditingController lowController;
  final TextEditingController highController;
  final String? Function(String? low, String? high) validator;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inputFormatters = <TextInputFormatter>[
      FilteringTextInputFormatter.allow(
        metric.decimals ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
      ),
    ];
    final keyboard = TextInputType.numberWithOptions(
      decimal: metric.decimals,
      signed: false,
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    metric.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  metric.unit,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: lowController,
                    keyboardType: keyboard,
                    inputFormatters: inputFormatters,
                    decoration: const InputDecoration(
                      labelText: 'Low',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    // Field-level validator delegates to the shared
                    // pair validator so we show a single combined error.
                    validator: (_) =>
                        validator(lowController.text, highController.text),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: highController,
                    keyboardType: keyboard,
                    inputFormatters: inputFormatters,
                    decoration: const InputDecoration(
                      labelText: 'High',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (_) => null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
