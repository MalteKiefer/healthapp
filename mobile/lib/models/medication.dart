class Medication {
  final String id;
  final String name;
  final String? dosage;
  final String? frequency;
  final String? startedAt;
  final String? endedAt;
  final String? notes;
  final bool isActive;

  Medication({
    required this.id,
    required this.name,
    this.dosage,
    this.frequency,
    this.startedAt,
    this.endedAt,
    this.notes,
    this.isActive = true,
  });

  factory Medication.fromJson(Map<String, dynamic> json) => Medication(
        id: json['id'],
        name: json['name'],
        dosage: json['dosage'],
        frequency: json['frequency'],
        startedAt: json['started_at'],
        endedAt: json['ended_at'],
        notes: json['notes'],
        isActive: json['is_active'] ?? true,
      );
}
