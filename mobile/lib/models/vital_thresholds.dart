/// Vital threshold configuration for a profile.
///
/// Each metric has an optional low and high bound. When a measurement
/// falls outside the [low, high] range it can be highlighted in the UI.
///
/// The wire format matches the web frontend / backend:
///   {
///     "blood_pressure_systolic":  { "low": 100, "high": 140 },
///     "blood_pressure_diastolic": { "low":  60, "high":  90 },
///     "pulse":                    { "low":  50, "high": 100 },
///     "body_temperature":         { "low":  36, "high":  37.5 },
///     "oxygen_saturation":        { "low":  94, "high": 100 },
///     "blood_glucose":            { "low":   4, "high":   7 },
///     "weight":                   { "low":  50, "high":  90 }
///   }
///
/// See `web/src/pages/Vitals.tsx` (THRESHOLD_METRICS) for the canonical
/// list of metric keys. Unknown metric keys returned by the backend are
/// preserved in [extras] so a round-trip save does not lose data.
class VitalThresholds {
  /// Systolic blood pressure (mmHg).
  final double? systolicLow;
  final double? systolicHigh;

  /// Diastolic blood pressure (mmHg).
  final double? diastolicLow;
  final double? diastolicHigh;

  /// Heart rate / pulse (bpm).
  final double? heartRateLow;
  final double? heartRateHigh;

  /// Body temperature (°C).
  final double? temperatureLow;
  final double? temperatureHigh;

  /// Blood oxygen saturation SpO2 (%).
  final double? spo2Low;
  final double? spo2High;

  /// Blood glucose (mmol/L).
  final double? glucoseLow;
  final double? glucoseHigh;

  /// Body weight (kg).
  final double? weightLow;
  final double? weightHigh;

  /// Raw map of any additional/unknown metric keys, preserved as-is so a
  /// save round-trip does not drop fields that the mobile UI does not
  /// yet render.
  final Map<String, Map<String, dynamic>> extras;

  const VitalThresholds({
    this.systolicLow,
    this.systolicHigh,
    this.diastolicLow,
    this.diastolicHigh,
    this.heartRateLow,
    this.heartRateHigh,
    this.temperatureLow,
    this.temperatureHigh,
    this.spo2Low,
    this.spo2High,
    this.glucoseLow,
    this.glucoseHigh,
    this.weightLow,
    this.weightHigh,
    this.extras = const {},
  });

  /// Canonical metric keys used on the wire, in the same order as
  /// `web/src/pages/Vitals.tsx` (THRESHOLD_METRICS).
  static const String kSystolic = 'blood_pressure_systolic';
  static const String kDiastolic = 'blood_pressure_diastolic';
  static const String kHeartRate = 'pulse';
  static const String kTemperature = 'body_temperature';
  static const String kSpo2 = 'oxygen_saturation';
  static const String kGlucose = 'blood_glucose';
  static const String kWeight = 'weight';

  static const Set<String> _knownKeys = {
    kSystolic,
    kDiastolic,
    kHeartRate,
    kTemperature,
    kSpo2,
    kGlucose,
    kWeight,
  };

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) {
      final trimmed = v.trim();
      if (trimmed.isEmpty) return null;
      return double.tryParse(trimmed);
    }
    return null;
  }

  static ({double? low, double? high}) _pair(
    Map<String, dynamic> json,
    String key,
  ) {
    final entry = json[key];
    if (entry is Map) {
      return (
        low: _asDouble(entry['low']),
        high: _asDouble(entry['high']),
      );
    }
    return (low: null, high: null);
  }

  factory VitalThresholds.fromJson(Map<String, dynamic> json) {
    final systolic = _pair(json, kSystolic);
    final diastolic = _pair(json, kDiastolic);
    final heartRate = _pair(json, kHeartRate);
    final temperature = _pair(json, kTemperature);
    final spo2 = _pair(json, kSpo2);
    final glucose = _pair(json, kGlucose);
    final weight = _pair(json, kWeight);

    final extras = <String, Map<String, dynamic>>{};
    for (final entry in json.entries) {
      if (_knownKeys.contains(entry.key)) continue;
      final value = entry.value;
      if (value is Map) {
        extras[entry.key] = Map<String, dynamic>.from(value);
      }
    }

    return VitalThresholds(
      systolicLow: systolic.low,
      systolicHigh: systolic.high,
      diastolicLow: diastolic.low,
      diastolicHigh: diastolic.high,
      heartRateLow: heartRate.low,
      heartRateHigh: heartRate.high,
      temperatureLow: temperature.low,
      temperatureHigh: temperature.high,
      spo2Low: spo2.low,
      spo2High: spo2.high,
      glucoseLow: glucose.low,
      glucoseHigh: glucose.high,
      weightLow: weight.low,
      weightHigh: weight.high,
      extras: extras,
    );
  }

  Map<String, dynamic> _pairJson(double? low, double? high) {
    return {
      'low': low,
      'high': high,
    };
  }

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      kSystolic: _pairJson(systolicLow, systolicHigh),
      kDiastolic: _pairJson(diastolicLow, diastolicHigh),
      kHeartRate: _pairJson(heartRateLow, heartRateHigh),
      kTemperature: _pairJson(temperatureLow, temperatureHigh),
      kSpo2: _pairJson(spo2Low, spo2High),
      kGlucose: _pairJson(glucoseLow, glucoseHigh),
      kWeight: _pairJson(weightLow, weightHigh),
    };
    // Preserve any unknown metric keys the backend returned.
    for (final entry in extras.entries) {
      out[entry.key] = entry.value;
    }
    return out;
  }

  VitalThresholds copyWith({
    double? systolicLow,
    double? systolicHigh,
    double? diastolicLow,
    double? diastolicHigh,
    double? heartRateLow,
    double? heartRateHigh,
    double? temperatureLow,
    double? temperatureHigh,
    double? spo2Low,
    double? spo2High,
    double? glucoseLow,
    double? glucoseHigh,
    double? weightLow,
    double? weightHigh,
    Map<String, Map<String, dynamic>>? extras,
    // Explicit clearing flags, because `null` can't distinguish "unset"
    // from "leave unchanged" in copyWith.
    bool clearSystolicLow = false,
    bool clearSystolicHigh = false,
    bool clearDiastolicLow = false,
    bool clearDiastolicHigh = false,
    bool clearHeartRateLow = false,
    bool clearHeartRateHigh = false,
    bool clearTemperatureLow = false,
    bool clearTemperatureHigh = false,
    bool clearSpo2Low = false,
    bool clearSpo2High = false,
    bool clearGlucoseLow = false,
    bool clearGlucoseHigh = false,
    bool clearWeightLow = false,
    bool clearWeightHigh = false,
  }) {
    return VitalThresholds(
      systolicLow: clearSystolicLow ? null : (systolicLow ?? this.systolicLow),
      systolicHigh:
          clearSystolicHigh ? null : (systolicHigh ?? this.systolicHigh),
      diastolicLow:
          clearDiastolicLow ? null : (diastolicLow ?? this.diastolicLow),
      diastolicHigh:
          clearDiastolicHigh ? null : (diastolicHigh ?? this.diastolicHigh),
      heartRateLow:
          clearHeartRateLow ? null : (heartRateLow ?? this.heartRateLow),
      heartRateHigh:
          clearHeartRateHigh ? null : (heartRateHigh ?? this.heartRateHigh),
      temperatureLow:
          clearTemperatureLow ? null : (temperatureLow ?? this.temperatureLow),
      temperatureHigh: clearTemperatureHigh
          ? null
          : (temperatureHigh ?? this.temperatureHigh),
      spo2Low: clearSpo2Low ? null : (spo2Low ?? this.spo2Low),
      spo2High: clearSpo2High ? null : (spo2High ?? this.spo2High),
      glucoseLow: clearGlucoseLow ? null : (glucoseLow ?? this.glucoseLow),
      glucoseHigh: clearGlucoseHigh ? null : (glucoseHigh ?? this.glucoseHigh),
      weightLow: clearWeightLow ? null : (weightLow ?? this.weightLow),
      weightHigh: clearWeightHigh ? null : (weightHigh ?? this.weightHigh),
      extras: extras ?? this.extras,
    );
  }

  static const VitalThresholds empty = VitalThresholds();
}
