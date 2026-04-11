/// Per-medication adherence statistics returned by
/// `GET /api/v1/profiles/{profileId}/medications/adherence`.
class MedicationAdherenceEntry {
  final String medicationId;
  final String? medicationName;
  final double adherencePct;
  final String? lastTakenAt;
  final int missedDosesLast7d;

  const MedicationAdherenceEntry({
    required this.medicationId,
    this.medicationName,
    required this.adherencePct,
    this.lastTakenAt,
    required this.missedDosesLast7d,
  });

  factory MedicationAdherenceEntry.fromJson(Map<String, dynamic> json) {
    return MedicationAdherenceEntry(
      medicationId: json['medication_id'] as String? ?? '',
      medicationName: json['medication_name'] as String? ??
          json['name'] as String?,
      adherencePct: _toDouble(json['adherence_pct']),
      lastTakenAt: json['last_taken_at'] as String?,
      missedDosesLast7d:
          (json['missed_doses_last_7d'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'medication_id': medicationId,
        if (medicationName != null) 'medication_name': medicationName,
        'adherence_pct': adherencePct,
        if (lastTakenAt != null) 'last_taken_at': lastTakenAt,
        'missed_doses_last_7d': missedDosesLast7d,
      };
}

/// Top-level summary block from the adherence endpoint. Shape is intentionally
/// permissive: the server may return any combination of overall_pct, total
/// doses, etc.
class MedicationAdherenceSummary {
  final double? overallPct;
  final int? totalDoses;
  final int? missedDoses;
  final Map<String, dynamic> raw;

  const MedicationAdherenceSummary({
    this.overallPct,
    this.totalDoses,
    this.missedDoses,
    this.raw = const {},
  });

  factory MedicationAdherenceSummary.fromJson(Map<String, dynamic> json) {
    return MedicationAdherenceSummary(
      overallPct: json['overall_pct'] == null
          ? null
          : _toDouble(json['overall_pct']),
      totalDoses: (json['total_doses'] as num?)?.toInt(),
      missedDoses: (json['missed_doses'] as num?)?.toInt(),
      raw: Map<String, dynamic>.from(json),
    );
  }
}

/// Combined response envelope: `{summary, per_medication: [...] }`.
class MedicationAdherence {
  final MedicationAdherenceSummary summary;
  final List<MedicationAdherenceEntry> perMedication;

  const MedicationAdherence({
    required this.summary,
    required this.perMedication,
  });

  factory MedicationAdherence.fromJson(Map<String, dynamic> json) {
    final summaryJson = (json['summary'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final perMed = (json['per_medication'] as List?) ?? const [];
    return MedicationAdherence(
      summary: MedicationAdherenceSummary.fromJson(summaryJson),
      perMedication: perMed
          .whereType<Map>()
          .map((m) =>
              MedicationAdherenceEntry.fromJson(m.cast<String, dynamic>()))
          .toList(),
    );
  }
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}
