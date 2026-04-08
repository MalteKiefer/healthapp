class Medication {
  final String id;
  final String name;
  final String? dosage;
  final String? unit;
  final String? route;
  final String? frequency;
  final String? startedAt;
  final String? endedAt;
  final String? prescribedBy;
  final String? reason;
  final String? notes;
  final bool isActive;

  Medication({
    required this.id,
    required this.name,
    this.dosage,
    this.unit,
    this.route,
    this.frequency,
    this.startedAt,
    this.endedAt,
    this.prescribedBy,
    this.reason,
    this.notes,
    this.isActive = true,
  });

  factory Medication.fromJson(Map<String, dynamic> json) => Medication(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        dosage: json['dosage'],
        unit: json['unit'],
        route: json['route'],
        frequency: json['frequency'],
        startedAt: json['started_at'],
        endedAt: json['ended_at'],
        prescribedBy: json['prescribed_by'],
        reason: json['reason'],
        notes: json['notes'],
        isActive: json['is_active'] ?? true,
      );
}
