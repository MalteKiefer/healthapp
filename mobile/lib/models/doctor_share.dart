/// Model for temporary doctor share links.
///
/// Matches the list response item shape from
/// `GET /api/v1/profiles/{profileID}/shares`, which is implemented by
/// `api/internal/api/handlers/doctor_share.go#HandleListShares`:
///
/// ```json
/// {
///   "share_id":   "hexstring",
///   "label":      "Dr. Weber — Cardiology",
///   "expires_at": "2026-04-18T12:00:00Z",
///   "revoked_at": "2026-04-11T08:00:00Z" | null,
///   "created_at": "2026-04-11T04:00:00Z",
///   "active":     true
/// }
/// ```
///
/// On the create side (`POST /api/v1/profiles/{profileID}/share`) the server
/// returns `share_id`, `share_url` and `expires_at`; the full share record is
/// only available by re-fetching the list.
///
/// NOTE: The backend currently models a share by `label` + `expires_in_hours`
/// + an opaque `encrypted_data` bundle (end-to-end encrypted with a temp key
/// held in the URL fragment). There is no server-side `content_scope` or
/// `allow_domains` field — those would require additional backend work. This
/// model therefore exposes `label` as the human-visible identifier instead of
/// a `scope` list.
library;

class DoctorShare {
  /// The opaque share identifier (also used in the public URL path).
  final String id;

  /// The profile this share belongs to.
  ///
  /// The list endpoint does not echo the `profile_id` back on each item — the
  /// caller always knows it from the request path — so this is filled in on
  /// the client side by [DoctorShare.fromJson] callers that have the profile
  /// id in scope.
  final String profileId;

  /// Human-readable label, e.g. "Dr. Weber — Cardiology visit".
  final String label;

  /// Full public share URL, if known. Only populated for newly-created shares
  /// (the list endpoint does not return the URL).
  final String? shareUrl;

  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;

  /// Whether the server currently considers the share usable.
  /// Mirrors `active` from the list endpoint, or is derived locally.
  final bool active;

  const DoctorShare({
    required this.id,
    required this.profileId,
    required this.label,
    required this.createdAt,
    required this.expiresAt,
    this.shareUrl,
    this.revokedAt,
    required this.active,
  });

  bool get isRevoked => revokedAt != null;
  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt.toUtc());

  factory DoctorShare.fromJson(
    Map<String, dynamic> json, {
    required String profileId,
  }) {
    final id = (json['share_id'] ?? json['id'] ?? '') as String;
    final createdRaw = json['created_at'] as String?;
    final expiresRaw = json['expires_at'] as String?;
    final revokedRaw = json['revoked_at'] as String?;
    final created = createdRaw != null
        ? DateTime.parse(createdRaw).toLocal()
        : DateTime.now();
    final expires = expiresRaw != null
        ? DateTime.parse(expiresRaw).toLocal()
        : DateTime.now();
    final revoked =
        revokedRaw != null ? DateTime.parse(revokedRaw).toLocal() : null;
    final serverActive = json['active'] as bool?;
    final active = serverActive ??
        (revoked == null && DateTime.now().toUtc().isBefore(expires.toUtc()));
    return DoctorShare(
      id: id,
      profileId: profileId,
      label: (json['label'] as String?) ?? '',
      shareUrl: json['share_url'] as String?,
      createdAt: created,
      expiresAt: expires,
      revokedAt: revoked,
      active: active,
    );
  }

  Map<String, dynamic> toJson() => {
        'share_id': id,
        'profile_id': profileId,
        'label': label,
        if (shareUrl != null) 'share_url': shareUrl,
        'created_at': createdAt.toUtc().toIso8601String(),
        'expires_at': expiresAt.toUtc().toIso8601String(),
        if (revokedAt != null)
          'revoked_at': revokedAt!.toUtc().toIso8601String(),
        'active': active,
      };
}
