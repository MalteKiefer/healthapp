class Vital {
  final String id;
  final String profileId;
  final String measuredAt;
  final double? systolic;
  final double? diastolic;
  final double? pulse;
  final double? weight;
  final double? height;
  final double? temperature;
  final double? oxygenSaturation;
  final double? bloodGlucose;
  final int? respiratoryRate;
  final double? waistCircumference;
  final double? hipCircumference;
  final double? bodyFatPercentage;
  final double? bmi;
  final int? sleepDurationMinutes;
  final int? sleepQuality;
  final String? device;
  final String? notes;

  Vital({
    required this.id,
    required this.profileId,
    required this.measuredAt,
    this.systolic,
    this.diastolic,
    this.pulse,
    this.weight,
    this.height,
    this.temperature,
    this.oxygenSaturation,
    this.bloodGlucose,
    this.respiratoryRate,
    this.waistCircumference,
    this.hipCircumference,
    this.bodyFatPercentage,
    this.bmi,
    this.sleepDurationMinutes,
    this.sleepQuality,
    this.device,
    this.notes,
  });

  factory Vital.fromJson(Map<String, dynamic> json) => Vital(
        id: json['id'] as String? ?? '',
        profileId: json['profile_id'] as String? ?? '',
        measuredAt: json['measured_at'] as String? ?? '',
        systolic: (json['blood_pressure_systolic'] as num?)?.toDouble(),
        diastolic: (json['blood_pressure_diastolic'] as num?)?.toDouble(),
        pulse: (json['pulse'] as num?)?.toDouble(),
        weight: (json['weight'] as num?)?.toDouble(),
        height: (json['height'] as num?)?.toDouble(),
        temperature: (json['body_temperature'] as num?)?.toDouble(),
        oxygenSaturation: (json['oxygen_saturation'] as num?)?.toDouble(),
        bloodGlucose: (json['blood_glucose'] as num?)?.toDouble(),
        respiratoryRate: (json['respiratory_rate'] as num?)?.toInt(),
        waistCircumference:
            (json['waist_circumference'] as num?)?.toDouble(),
        hipCircumference: (json['hip_circumference'] as num?)?.toDouble(),
        bodyFatPercentage:
            (json['body_fat_percentage'] as num?)?.toDouble(),
        bmi: (json['bmi'] as num?)?.toDouble(),
        sleepDurationMinutes: (json['sleep_duration_minutes'] as num?)?.toInt(),
        sleepQuality: (json['sleep_quality'] as num?)?.toInt(),
        device: json['device'] as String?,
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'measured_at': measuredAt};
    if (systolic != null) map['blood_pressure_systolic'] = systolic;
    if (diastolic != null) map['blood_pressure_diastolic'] = diastolic;
    if (pulse != null) map['pulse'] = pulse;
    if (weight != null) map['weight'] = weight;
    if (height != null) map['height'] = height;
    if (temperature != null) map['body_temperature'] = temperature;
    if (oxygenSaturation != null) map['oxygen_saturation'] = oxygenSaturation;
    if (bloodGlucose != null) map['blood_glucose'] = bloodGlucose;
    if (respiratoryRate != null) map['respiratory_rate'] = respiratoryRate;
    if (waistCircumference != null) {
      map['waist_circumference'] = waistCircumference;
    }
    if (hipCircumference != null) map['hip_circumference'] = hipCircumference;
    if (bodyFatPercentage != null) {
      map['body_fat_percentage'] = bodyFatPercentage;
    }
    if (bmi != null) map['bmi'] = bmi;
    if (sleepDurationMinutes != null) {
      map['sleep_duration_minutes'] = sleepDurationMinutes;
    }
    if (sleepQuality != null) map['sleep_quality'] = sleepQuality;
    if (device != null) map['device'] = device;
    if (notes != null) map['notes'] = notes;
    return map;
  }
}
