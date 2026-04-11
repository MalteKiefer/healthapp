/// Models for in-app notifications.
///
/// Deliberately named [AppNotification] to avoid colliding with the Flutter
/// platform-channel `Notification` class (used by the widget tree
/// NotificationListener).
library;

/// A single notification delivered to the authenticated user.
///
/// Matches the `/api/v1/notifications` list response item shape
/// (see `api/internal/domain/notifications/model.go#Notification`):
///
/// ```json
/// {
///   "id": "uuid",
///   "user_id": "uuid",
///   "type": "vaccination_due",
///   "title": "…",
///   "body": "…",
///   "metadata": { ... },
///   "read_at": "2026-04-10T12:34:56Z" | null,
///   "created_at": "2026-04-10T12:00:00Z"
/// }
/// ```
class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;
  final Map<String, dynamic> metadata;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.metadata = const {},
  });

  bool get isRead => readAt != null;
  bool get isUnread => readAt == null;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final created = json['created_at'] as String?;
    final read = json['read_at'] as String?;
    return AppNotification(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      createdAt:
          created != null ? DateTime.parse(created).toLocal() : DateTime.now(),
      readAt: read != null ? DateTime.parse(read).toLocal() : null,
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

/// Known notification-type string values emitted by the backend.
///
/// These mirror the icons/labels used by the web NotificationBell and the
/// per-channel toggles in [NotificationPreferences]. Unknown types are
/// rendered with a generic icon/label at the UI layer.
class NotificationTypes {
  static const vaccinationDue = 'vaccination_due';
  static const medicationReminder = 'medication_reminder';
  static const appointmentReminder = 'appointment_reminder';
  static const labResultAbnormal = 'lab_result_abnormal';
  static const emergencyAccessRequest = 'emergency_access_request';
  static const sessionNew = 'session_new';
  static const storageQuotaWarning = 'storage_quota_warning';
  static const familyInvite = 'family_invite';
  static const keyRotationRequired = 'key_rotation_required';
  static const exportReady = 'export_ready';
  static const backupFailed = 'backup_failed';
}

/// User-level notification channel preferences.
///
/// Matches `api/internal/domain/notifications/model.go#NotificationPreferences`.
/// A boolean controls whether the server will emit a given notification type
/// for this user at all; [vaccinationDueDays] is how many days in advance a
/// vaccination-due notification fires.
class NotificationPreferences {
  final bool vaccinationDue;
  final int vaccinationDueDays;
  final bool medicationReminder;
  final bool labResultAbnormal;
  final bool emergencyAccess;
  final bool exportReady;
  final bool familyInvite;
  final bool keyRotationRequired;
  final bool sessionNew;
  final bool storageQuotaWarning;

  const NotificationPreferences({
    this.vaccinationDue = true,
    this.vaccinationDueDays = 30,
    this.medicationReminder = true,
    this.labResultAbnormal = true,
    this.emergencyAccess = true,
    this.exportReady = true,
    this.familyInvite = true,
    this.keyRotationRequired = true,
    this.sessionNew = true,
    this.storageQuotaWarning = true,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      vaccinationDue: json['vaccination_due'] as bool? ?? false,
      vaccinationDueDays: (json['vaccination_due_days'] as num?)?.toInt() ?? 30,
      medicationReminder: json['medication_reminder'] as bool? ?? false,
      labResultAbnormal: json['lab_result_abnormal'] as bool? ?? false,
      emergencyAccess: json['emergency_access'] as bool? ?? false,
      exportReady: json['export_ready'] as bool? ?? false,
      familyInvite: json['family_invite'] as bool? ?? false,
      keyRotationRequired: json['key_rotation_required'] as bool? ?? false,
      sessionNew: json['session_new'] as bool? ?? false,
      storageQuotaWarning: json['storage_quota_warning'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'vaccination_due': vaccinationDue,
        'vaccination_due_days': vaccinationDueDays,
        'medication_reminder': medicationReminder,
        'lab_result_abnormal': labResultAbnormal,
        'emergency_access': emergencyAccess,
        'export_ready': exportReady,
        'family_invite': familyInvite,
        'key_rotation_required': keyRotationRequired,
        'session_new': sessionNew,
        'storage_quota_warning': storageQuotaWarning,
      };

  NotificationPreferences copyWith({
    bool? vaccinationDue,
    int? vaccinationDueDays,
    bool? medicationReminder,
    bool? labResultAbnormal,
    bool? emergencyAccess,
    bool? exportReady,
    bool? familyInvite,
    bool? keyRotationRequired,
    bool? sessionNew,
    bool? storageQuotaWarning,
  }) {
    return NotificationPreferences(
      vaccinationDue: vaccinationDue ?? this.vaccinationDue,
      vaccinationDueDays: vaccinationDueDays ?? this.vaccinationDueDays,
      medicationReminder: medicationReminder ?? this.medicationReminder,
      labResultAbnormal: labResultAbnormal ?? this.labResultAbnormal,
      emergencyAccess: emergencyAccess ?? this.emergencyAccess,
      exportReady: exportReady ?? this.exportReady,
      familyInvite: familyInvite ?? this.familyInvite,
      keyRotationRequired: keyRotationRequired ?? this.keyRotationRequired,
      sessionNew: sessionNew ?? this.sessionNew,
      storageQuotaWarning: storageQuotaWarning ?? this.storageQuotaWarning,
    );
  }
}
