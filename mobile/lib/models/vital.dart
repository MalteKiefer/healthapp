class Vital {
  final String id;
  final String profileId;
  final String measuredAt;
  final double? systolic;
  final double? diastolic;
  final double? pulse;
  final double? weight;
  final double? temperature;
  final double? oxygenSaturation;
  final double? bloodGlucose;
  final String? notes;

  Vital({
    required this.id,
    required this.profileId,
    required this.measuredAt,
    this.systolic,
    this.diastolic,
    this.pulse,
    this.weight,
    this.temperature,
    this.oxygenSaturation,
    this.bloodGlucose,
    this.notes,
  });

  factory Vital.fromJson(Map<String, dynamic> json) => Vital(
        id: json['id'],
        profileId: json['profile_id'],
        measuredAt: json['measured_at'],
        systolic: (json['blood_pressure_systolic'] as num?)?.toDouble(),
        diastolic: (json['blood_pressure_diastolic'] as num?)?.toDouble(),
        pulse: (json['pulse'] as num?)?.toDouble(),
        weight: (json['weight'] as num?)?.toDouble(),
        temperature: (json['body_temperature'] as num?)?.toDouble(),
        oxygenSaturation: (json['oxygen_saturation'] as num?)?.toDouble(),
        bloodGlucose: (json['blood_glucose'] as num?)?.toDouble(),
        notes: json['notes'],
      );

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'measured_at': measuredAt};
    if (systolic != null) map['blood_pressure_systolic'] = systolic;
    if (diastolic != null) map['blood_pressure_diastolic'] = diastolic;
    if (pulse != null) map['pulse'] = pulse;
    if (weight != null) map['weight'] = weight;
    if (temperature != null) map['body_temperature'] = temperature;
    if (oxygenSaturation != null) map['oxygen_saturation'] = oxygenSaturation;
    if (bloodGlucose != null) map['blood_glucose'] = bloodGlucose;
    if (notes != null) map['notes'] = notes;
    return map;
  }
}
