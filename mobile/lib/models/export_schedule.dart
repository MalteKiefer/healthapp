/// Models for scheduled health-data exports.
///
/// Mirrors the backend `export_schedules` table exposed by:
///   * POST   /api/v1/export/schedule
///   * GET    /api/v1/export/schedules
///   * DELETE /api/v1/export/schedules/{scheduleId}
library;

/// Supported export formats. Strings deliberately match the values the
/// backend persists in the `format` column and accepts in
/// `POST /api/v1/export` request bodies.
class ExportFormats {
  static const fhir = 'fhir';
  static const pdf = 'pdf';
  static const ics = 'ics';

  static const all = <String>[fhir, pdf, ics];

  static String label(String format) {
    switch (format) {
      case fhir:
        return 'FHIR Bundle';
      case pdf:
        return 'PDF Report';
      case ics:
        return 'ICS Calendar';
      default:
        return format.toUpperCase();
    }
  }

  static String extension(String format) {
    switch (format) {
      case fhir:
        return 'json';
      case pdf:
        return 'pdf';
      case ics:
        return 'ics';
      default:
        return 'bin';
    }
  }

  static String mimeType(String format) {
    switch (format) {
      case fhir:
        return 'application/fhir+json';
      case pdf:
        return 'application/pdf';
      case ics:
        return 'text/calendar';
      default:
        return 'application/octet-stream';
    }
  }
}

/// Common cron presets exposed in the schedules UI. Each entry is
/// `(label, cronExpression)`. The backend accepts any standard 5-field
/// cron expression; the presets are just convenience shortcuts.
class CronPresets {
  static const Map<String, String> presets = {
    'Daily (08:00)': '0 8 * * *',
    'Weekly (Mon 08:00)': '0 8 * * 1',
    'Monthly (1st 08:00)': '0 8 1 * *',
  };
}

/// A persisted export schedule.
///
/// Matches the JSON shape returned by `GET /api/v1/export/schedules`:
///
/// ```json
/// {
///   "id": "uuid",
///   "profile_id": "uuid",
///   "format": "fhir" | "pdf" | "ics",
///   "cron": "0 8 * * 1",
///   "destination": "email:user@example.com" | "local",
///   "created_at": "2026-04-10T12:00:00Z"
/// }
/// ```
class ExportSchedule {
  final String id;
  final String profileId;
  final String format;
  final String cron;
  final String destination;
  final DateTime createdAt;

  const ExportSchedule({
    required this.id,
    required this.profileId,
    required this.format,
    required this.cron,
    required this.destination,
    required this.createdAt,
  });

  factory ExportSchedule.fromJson(Map<String, dynamic> json) {
    final created = json['created_at'] as String?;
    return ExportSchedule(
      id: json['id'] as String? ?? '',
      profileId: (json['profile_id'] ?? json['profileId']) as String? ?? '',
      format: json['format'] as String? ?? '',
      cron: json['cron'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      createdAt:
          created != null ? DateTime.parse(created).toLocal() : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'profile_id': profileId,
        'format': format,
        'cron': cron,
        'destination': destination,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  /// Body for POST /api/v1/export/schedule.
  static Map<String, dynamic> createBody({
    required String profileId,
    required String format,
    required String cron,
    required String destination,
  }) =>
      {
        'profile_id': profileId,
        'format': format,
        'cron': cron,
        'destination': destination,
      };
}
