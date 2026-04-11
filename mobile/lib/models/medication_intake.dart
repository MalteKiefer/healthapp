/// Data model for a single logged medication intake event.
///
/// Mirrors the server-side `MedicationIntake` entity. The API uses
/// `dose_taken` as the free-form string describing the dose actually taken
/// (e.g. "1 tablet", "5 mg"). The Sprint 2 spec referred to this as
/// `dose_amount`; we accept either key for forward/backward compatibility
/// but always emit `dose_taken` on write.
class MedicationIntake {
  final String id;
  final String medicationId;
  final String? scheduledAt;
  final String? takenAt;
  final String? doseTaken;
  final String? skippedReason;
  final String? notes;
  final String? createdAt;

  const MedicationIntake({
    required this.id,
    required this.medicationId,
    this.scheduledAt,
    this.takenAt,
    this.doseTaken,
    this.skippedReason,
    this.notes,
    this.createdAt,
  });

  factory MedicationIntake.fromJson(Map<String, dynamic> json) {
    return MedicationIntake(
      id: json['id'] as String? ?? '',
      medicationId: json['medication_id'] as String? ?? '',
      scheduledAt: json['scheduled_at'] as String?,
      takenAt: json['taken_at'] as String?,
      doseTaken: (json['dose_taken'] ?? json['dose_amount']) as String?,
      skippedReason: json['skipped_reason'] as String?,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'medication_id': medicationId,
    };
    if (scheduledAt != null) map['scheduled_at'] = scheduledAt;
    if (takenAt != null) map['taken_at'] = takenAt;
    if (doseTaken != null) map['dose_taken'] = doseTaken;
    if (skippedReason != null) map['skipped_reason'] = skippedReason;
    if (notes != null) map['notes'] = notes;
    if (createdAt != null) map['created_at'] = createdAt;
    return map;
  }

  MedicationIntake copyWith({
    String? id,
    String? medicationId,
    String? scheduledAt,
    String? takenAt,
    String? doseTaken,
    String? skippedReason,
    String? notes,
    String? createdAt,
  }) {
    return MedicationIntake(
      id: id ?? this.id,
      medicationId: medicationId ?? this.medicationId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      takenAt: takenAt ?? this.takenAt,
      doseTaken: doseTaken ?? this.doseTaken,
      skippedReason: skippedReason ?? this.skippedReason,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
