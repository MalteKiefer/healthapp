/// Data model for an active user session.
///
/// Backed by `GET /api/v1/users/me/sessions` on the health server.
/// Each entry represents a server-side session record (cookie /
/// refresh token) belonging to the currently signed-in user.
library;

class UserSession {
  /// Stable server-side identifier for the session row. Passed to
  /// `DELETE /api/v1/users/me/sessions/{sessionId}` to revoke.
  final String id;

  /// Friendly device label, when known. May be empty if the server
  /// did not derive one (in which case the UI falls back to the
  /// raw [userAgent]).
  final String device;

  /// IP address recorded at session creation time. May be empty.
  final String ip;

  /// Raw User-Agent header from the session's first request.
  final String userAgent;

  /// When the session was first created (server clock, converted to
  /// the device's local time zone).
  final DateTime createdAt;

  /// When the session was most recently observed making an
  /// authenticated request. Used to surface "last active" hints in
  /// the UI.
  final DateTime lastSeenAt;

  /// True iff this session corresponds to the cookie that the app
  /// is currently using. The server is responsible for marking
  /// exactly one session as current.
  final bool isCurrent;

  const UserSession({
    required this.id,
    required this.device,
    required this.ip,
    required this.userAgent,
    required this.createdAt,
    required this.lastSeenAt,
    required this.isCurrent,
  });

  factory UserSession.fromJson(Map<String, dynamic> json) {
    DateTime parseTs(dynamic v, {DateTime? fallback}) {
      if (v is String && v.isNotEmpty) {
        try {
          return DateTime.parse(v).toLocal();
        } catch (_) {/* fall through */}
      }
      return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
    }

    final created = parseTs(
      json['created_at'] ?? json['createdAt'],
    );
    final lastSeen = parseTs(
      json['last_seen_at'] ?? json['lastSeenAt'] ?? json['last_used_at'],
      fallback: created,
    );

    return UserSession(
      id: (json['id'] ?? '').toString(),
      device: (json['device'] ?? json['device_name'] ?? '').toString(),
      ip: (json['ip'] ?? json['ip_address'] ?? '').toString(),
      userAgent:
          (json['user_agent'] ?? json['userAgent'] ?? '').toString(),
      createdAt: created,
      lastSeenAt: lastSeen,
      isCurrent: (json['is_current'] ?? json['current'] ?? false) as bool,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'device': device,
        'ip': ip,
        'user_agent': userAgent,
        'created_at': createdAt.toUtc().toIso8601String(),
        'last_seen_at': lastSeenAt.toUtc().toIso8601String(),
        'is_current': isCurrent,
      };
}
