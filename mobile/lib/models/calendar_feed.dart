/// Domain model for a user-owned iCalendar (ICS) feed.
///
/// Represents a row from `GET /api/v1/calendar/feeds`. The backend returns
/// individual `include_*` boolean flags per content type; this model
/// flattens them into a single [contentTypes] list keyed by the values in
/// [CalendarFeedContentType] for easier UI handling.
///
/// On create (`POST /api/v1/calendar/feeds`) the backend additionally
/// returns a one-time-visible plaintext `token` and a fully-formed `url`.
/// Subsequent reads (`GET /api/v1/calendar/feeds` and
/// `GET /api/v1/calendar/feeds/{feedId}`) only return the `token_hash`,
/// so [token] / [url] will be null for items loaded from the list.
class CalendarFeed {
  final String id;
  final String name;

  /// First profile in the backend's `profile_ids` list. The Sprint 3 mobile
  /// UI only supports a single profile per feed; if the backend ever
  /// stores multiple, the rest are preserved on edit via [extraProfileIds].
  final String profileId;

  /// Any additional profile IDs returned by the backend beyond [profileId].
  /// Empty for feeds created from this client.
  final List<String> extraProfileIds;

  /// Hash of the bearer token (server-side identifier). Always present.
  final String token;

  /// Plaintext bearer token. Only populated immediately after creation —
  /// the backend never returns it again.
  final String? plaintextToken;

  /// Fully-formed ICS URL returned by the backend on create. May be null
  /// for feeds loaded from the list endpoint, in which case the UI builds
  /// it from the API base URL + [token].
  final String? url;

  final List<String> contentTypes;
  final bool verboseMode;
  final String? createdAt;

  const CalendarFeed({
    required this.id,
    required this.name,
    required this.profileId,
    required this.extraProfileIds,
    required this.token,
    required this.contentTypes,
    this.verboseMode = false,
    this.plaintextToken,
    this.url,
    this.createdAt,
  });

  factory CalendarFeed.fromJson(Map<String, dynamic> json) {
    // The list/get endpoints return the feed object directly. The create
    // endpoint wraps it in `{ ...feed, token, url }`, so the same parser
    // works for both shapes.
    final profileIdsRaw = (json['profile_ids'] as List?) ?? const [];
    final profileIds = profileIdsRaw.map((e) => e.toString()).toList();

    final types = <String>[];
    if (json['include_appointments'] == true) {
      types.add(CalendarFeedContentType.appointments);
    }
    if (json['include_medications'] == true) {
      types.add(CalendarFeedContentType.medications);
    }
    if (json['include_labs'] == true) {
      types.add(CalendarFeedContentType.labs);
    }
    if (json['include_vaccinations'] == true) {
      types.add(CalendarFeedContentType.vaccinations);
    }
    if (json['include_tasks'] == true) {
      types.add(CalendarFeedContentType.tasks);
    }
    // Vitals are not yet wired on the backend (no `include_vitals` flag),
    // but the UI surfaces the option for forward compatibility.
    if (json['include_vitals'] == true) {
      types.add(CalendarFeedContentType.vitals);
    }

    return CalendarFeed(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      profileId: profileIds.isNotEmpty ? profileIds.first : '',
      extraProfileIds:
          profileIds.length > 1 ? profileIds.sublist(1) : const <String>[],
      token: (json['token_hash'] as String?) ?? '',
      plaintextToken: json['token'] as String?,
      url: json['url'] as String?,
      contentTypes: types,
      verboseMode: json['verbose_mode'] as bool? ?? false,
      createdAt: json['created_at'] as String?,
    );
  }

  /// Builds a JSON body for `POST /api/v1/calendar/feeds` or
  /// `PATCH /api/v1/calendar/feeds/{id}` from a UI selection.
  static Map<String, dynamic> buildWriteBody({
    required String name,
    required String profileId,
    required List<String> contentTypes,
    List<String> extraProfileIds = const <String>[],
    bool verboseMode = false,
  }) {
    return <String, dynamic>{
      'name': name,
      'profile_ids': <String>[profileId, ...extraProfileIds],
      'include_appointments':
          contentTypes.contains(CalendarFeedContentType.appointments),
      'include_medications':
          contentTypes.contains(CalendarFeedContentType.medications),
      'include_labs': contentTypes.contains(CalendarFeedContentType.labs),
      'include_vaccinations':
          contentTypes.contains(CalendarFeedContentType.vaccinations),
      'include_tasks': contentTypes.contains(CalendarFeedContentType.tasks),
      'include_vitals': contentTypes.contains(CalendarFeedContentType.vitals),
      'verbose_mode': verboseMode,
    };
  }

  CalendarFeed copyWith({
    String? id,
    String? name,
    String? profileId,
    List<String>? extraProfileIds,
    String? token,
    String? plaintextToken,
    String? url,
    List<String>? contentTypes,
    bool? verboseMode,
    String? createdAt,
  }) {
    return CalendarFeed(
      id: id ?? this.id,
      name: name ?? this.name,
      profileId: profileId ?? this.profileId,
      extraProfileIds: extraProfileIds ?? this.extraProfileIds,
      token: token ?? this.token,
      plaintextToken: plaintextToken ?? this.plaintextToken,
      url: url ?? this.url,
      contentTypes: contentTypes ?? this.contentTypes,
      verboseMode: verboseMode ?? this.verboseMode,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Canonical content-type identifiers used by the mobile UI. These are
/// translated to the backend's individual `include_*` flags by
/// [CalendarFeed.buildWriteBody].
class CalendarFeedContentType {
  CalendarFeedContentType._();

  static const String vitals = 'vitals';
  static const String medications = 'medications';
  static const String labs = 'labs';
  static const String appointments = 'appointments';
  static const String vaccinations = 'vaccinations';
  static const String tasks = 'tasks';

  /// Stable display order for the UI.
  static const List<String> all = <String>[
    vitals,
    medications,
    labs,
    appointments,
    vaccinations,
    tasks,
  ];

  static String label(String type) {
    switch (type) {
      case vitals:
        return 'Vitals';
      case medications:
        return 'Medications';
      case labs:
        return 'Lab results';
      case appointments:
        return 'Appointments';
      case vaccinations:
        return 'Vaccinations';
      case tasks:
        return 'Tasks';
      default:
        return type;
    }
  }
}
