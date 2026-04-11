/// Models for the Emergency Access feature.
///
/// Wire shapes are based on `web/src/pages/EmergencyAccess.tsx` plus the
/// Sprint 3 API contract:
///
///   GET    /api/v1/profiles/{profileId}/emergency-card
///   GET    /api/v1/profiles/{profileId}/emergency-access
///   POST   /api/v1/profiles/{profileId}/emergency-access
///   DELETE /api/v1/profiles/{profileId}/emergency-access
///   GET    /api/v1/emergency/pending
///   POST   /api/v1/emergency/approve/{requestId}
///   POST   /api/v1/emergency/deny/{requestId}
///
/// Where the wire payload is not yet locked down, every field is treated
/// as optional and parsed defensively so that older or newer server
/// versions do not crash the screen.
library;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String? _asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

bool _asBool(dynamic v, {bool fallback = false}) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
  }
  return fallback;
}

int _asInt(dynamic v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? fallback;
  return fallback;
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String && v.isNotEmpty) {
    return DateTime.tryParse(v);
  }
  return null;
}

List<String> _asStringList(dynamic v) {
  if (v is List) {
    return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
  }
  return const <String>[];
}

// ---------------------------------------------------------------------------
// EmergencyCard — read-only summary returned by GET /emergency-card
// ---------------------------------------------------------------------------

/// Read-only emergency card summary.
///
/// The minimal contract used by the web client is `{ token, url }`. Some
/// backend revisions also include the decoded card payload (blood type,
/// allergies, medications, diagnoses, contacts and a free-form message).
/// Both shapes are parsed; missing fields are simply left as null/empty.
class EmergencyCard {
  final String? token;
  final String? url;

  final String? bloodType;
  final List<String> allergies;
  final List<String> medications;
  final List<String> diagnoses;
  final List<EmergencyCardContact> contacts;
  final String? message;
  final DateTime? generatedAt;

  const EmergencyCard({
    this.token,
    this.url,
    this.bloodType,
    this.allergies = const [],
    this.medications = const [],
    this.diagnoses = const [],
    this.contacts = const [],
    this.message,
    this.generatedAt,
  });

  factory EmergencyCard.fromJson(Map<String, dynamic> json) {
    // Some revisions wrap the data fields under a `card` key.
    final card = json['card'];
    final cardMap = card is Map<String, dynamic> ? card : json;

    return EmergencyCard(
      token: _asString(json['token']),
      url: _asString(json['url']),
      bloodType: _asString(cardMap['blood_type']),
      allergies: _asStringList(cardMap['allergies']),
      medications: _asStringList(cardMap['medications']),
      diagnoses: _asStringList(cardMap['diagnoses']),
      contacts: (cardMap['contacts'] is List)
          ? (cardMap['contacts'] as List)
              .whereType<Map>()
              .map((e) => EmergencyCardContact.fromJson(
                  Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      message: _asString(cardMap['message']),
      generatedAt: _asDate(json['generated_at'] ?? json['updated_at']),
    );
  }

  bool get hasUrl => (url ?? '').isNotEmpty;
  bool get isEmpty =>
      bloodType == null &&
      allergies.isEmpty &&
      medications.isEmpty &&
      diagnoses.isEmpty &&
      contacts.isEmpty &&
      (message ?? '').isEmpty;
}

class EmergencyCardContact {
  final String? name;
  final String? phone;
  final String? email;
  final String? relation;

  const EmergencyCardContact({this.name, this.phone, this.email, this.relation});

  factory EmergencyCardContact.fromJson(Map<String, dynamic> json) {
    return EmergencyCardContact(
      name: _asString(json['name']),
      phone: _asString(json['phone']),
      email: _asString(json['email']),
      relation: _asString(json['relation'] ?? json['relationship']),
    );
  }
}

// ---------------------------------------------------------------------------
// EmergencyAccessConfig — server-side configuration row
// ---------------------------------------------------------------------------

/// Configuration for the emergency access feature on a single profile.
///
/// The Sprint 3 POST body is:
///   { access_type, delay_hours, notify_contacts }
///
/// The GET response also exposes the existing legacy fields for backward
/// compatibility (`enabled`, `wait_hours`, `data_fields`, `message`,
/// `emergency_contact_user_id`). They are parsed when present.
class EmergencyAccessConfig {
  final String? id;
  final String profileId;
  final bool enabled;
  final String accessType;
  final int delayHours;
  final List<String> notifyContacts;
  final List<String> dataFields;
  final String? emergencyContactUserId;
  final String? message;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const EmergencyAccessConfig({
    this.id,
    required this.profileId,
    this.enabled = false,
    this.accessType = 'delayed',
    this.delayHours = 48,
    this.notifyContacts = const [],
    this.dataFields = const [],
    this.emergencyContactUserId,
    this.message,
    this.createdAt,
    this.updatedAt,
  });

  /// A safe "empty" / disabled config used when the server returns 404.
  factory EmergencyAccessConfig.disabled(String profileId) =>
      EmergencyAccessConfig(profileId: profileId);

  factory EmergencyAccessConfig.fromJson(Map<String, dynamic> json) {
    return EmergencyAccessConfig(
      id: _asString(json['id']),
      profileId: _asString(json['profile_id']) ?? '',
      enabled: _asBool(json['enabled'], fallback: false),
      accessType: _asString(json['access_type']) ?? 'delayed',
      delayHours: _asInt(
        json['delay_hours'] ?? json['wait_hours'],
        fallback: 48,
      ),
      notifyContacts: _asStringList(
        json['notify_contacts'] ?? json['notified_contacts'],
      ),
      dataFields: _asStringList(json['data_fields']),
      emergencyContactUserId: _asString(json['emergency_contact_user_id']),
      message: _asString(json['message']),
      createdAt: _asDate(json['created_at']),
      updatedAt: _asDate(json['updated_at']),
    );
  }

  /// Body for POST /api/v1/profiles/{profileId}/emergency-access.
  ///
  /// Per spec the canonical fields are `access_type`, `delay_hours`,
  /// `notify_contacts`. We also forward the legacy fields so older
  /// backends keep working.
  Map<String, dynamic> toCreateJson() {
    return {
      'access_type': accessType,
      'delay_hours': delayHours,
      'notify_contacts': notifyContacts,
      // Legacy compatibility:
      'wait_hours': delayHours,
      'data_fields': dataFields,
      if (message != null) 'message': message,
      if (emergencyContactUserId != null)
        'emergency_contact_user_id': emergencyContactUserId,
    };
  }

  EmergencyAccessConfig copyWith({
    String? id,
    String? profileId,
    bool? enabled,
    String? accessType,
    int? delayHours,
    List<String>? notifyContacts,
    List<String>? dataFields,
    String? emergencyContactUserId,
    String? message,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmergencyAccessConfig(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      enabled: enabled ?? this.enabled,
      accessType: accessType ?? this.accessType,
      delayHours: delayHours ?? this.delayHours,
      notifyContacts: notifyContacts ?? this.notifyContacts,
      dataFields: dataFields ?? this.dataFields,
      emergencyContactUserId:
          emergencyContactUserId ?? this.emergencyContactUserId,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Allowed values for [EmergencyAccessConfig.accessType]. Mirrors what the
/// web client uses; unknown values are still accepted by the model.
class EmergencyAccessType {
  EmergencyAccessType._();
  static const String immediate = 'immediate';
  static const String delayed = 'delayed';
  static const String approval = 'approval';

  static const List<String> all = [immediate, delayed, approval];

  static String label(String type) {
    switch (type) {
      case immediate:
        return 'Immediate';
      case delayed:
        return 'Delayed (wait period)';
      case approval:
        return 'Manual approval';
      default:
        return type;
    }
  }
}

// ---------------------------------------------------------------------------
// EmergencyRequest — entries returned by GET /emergency/pending
// ---------------------------------------------------------------------------

class EmergencyRequest {
  final String id;
  final String? profileId;
  final String? profileName;
  final String? requesterId;
  final String? requesterName;
  final String? requesterEmail;
  final String? reason;
  final String status;
  final DateTime? requestedAt;
  final DateTime? availableAt;

  const EmergencyRequest({
    required this.id,
    required this.status,
    this.profileId,
    this.profileName,
    this.requesterId,
    this.requesterName,
    this.requesterEmail,
    this.reason,
    this.requestedAt,
    this.availableAt,
  });

  factory EmergencyRequest.fromJson(Map<String, dynamic> json) {
    return EmergencyRequest(
      id: _asString(json['id']) ?? '',
      profileId: _asString(json['profile_id']),
      profileName: _asString(json['profile_name']),
      requesterId: _asString(json['requester_id']),
      requesterName: _asString(json['requester_name']),
      requesterEmail: _asString(json['requester_email']),
      reason: _asString(json['reason']),
      status: _asString(json['status']) ?? 'pending',
      requestedAt: _asDate(json['requested_at']),
      availableAt: _asDate(json['available_at']),
    );
  }

  String get displayRequester {
    if ((requesterName ?? '').isNotEmpty) return requesterName!;
    if ((requesterEmail ?? '').isNotEmpty) return requesterEmail!;
    if ((requesterId ?? '').isNotEmpty) return requesterId!;
    return 'Unknown requester';
  }
}
