/// A single entry in a profile's activity log.
///
/// Models the response of `GET /api/v1/profiles/{profileId}/activity`. The
/// backend returns items with the shape:
///
///     {
///       "id":         <uuid>,
///       "profile_id": <uuid>,
///       "action":     "create" | "update" | "delete" | ...,
///       "entity":     "medication" | "vital" | "lab" | ...,
///       "entity_id":  <uuid|null>,
///       "details":    <string|null>,
///       "created_at": <RFC3339>
///     }
///
/// Older / alternate spellings (`entity_type`, `metadata`, `actor_id`,
/// `record_id`) are accepted as fallbacks so the model stays robust to
/// shape drift between the web frontend's [ActivityLog] page and the API.
class ActivityEntry {
  final String id;
  final String profileId;
  final String action;
  final String entityType;
  final String? entityId;
  final String? details;
  final String? actorId;
  final DateTime createdAt;

  const ActivityEntry({
    required this.id,
    required this.profileId,
    required this.action,
    required this.entityType,
    required this.createdAt,
    this.entityId,
    this.details,
    this.actorId,
  });

  factory ActivityEntry.fromJson(Map<String, dynamic> json) {
    // Backend currently returns `entity`; spec also mentions `entity_type`
    // and the older `module` column name. Accept any of them.
    final entity = (json['entity'] ??
            json['entity_type'] ??
            json['module'] ??
            json['resource'] ??
            '')
        .toString();

    // `details` is preferred; fall back to `metadata` (which may be a Map
    // or a primitive depending on the backend version).
    String? details;
    final rawDetails = json['details'] ?? json['metadata'];
    if (rawDetails is String) {
      details = rawDetails.isEmpty ? null : rawDetails;
    } else if (rawDetails != null) {
      details = rawDetails.toString();
    }

    final entityId = (json['entity_id'] ?? json['record_id'])?.toString();
    final actorId = (json['actor_id'] ?? json['user_id'])?.toString();

    final createdRaw = json['created_at']?.toString() ?? '';
    final created = DateTime.tryParse(createdRaw)?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0).toLocal();

    return ActivityEntry(
      id: (json['id'] ?? '').toString(),
      profileId: (json['profile_id'] ?? '').toString(),
      action: (json['action'] ?? '').toString(),
      entityType: entity,
      entityId: entityId,
      details: details,
      actorId: actorId,
      createdAt: created,
    );
  }
}
