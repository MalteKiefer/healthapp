/// Global search result model for the HealthVault mobile app.
///
/// Mirrors the shape returned by `GET /api/v1/search?q=...`, which groups
/// results by domain (medication, lab, vital, etc.). The backend returns a
/// heterogeneous payload per domain, so this model normalizes the common
/// fields every row exposes: id, profileId, title, subtitle, matchedSnippet.
library;

/// All domains supported by the global-search endpoint.
enum SearchResultType {
  medication,
  lab,
  vital,
  appointment,
  task,
  diary,
  contact,
  diagnosis,
  allergy,
  symptom,
  vaccination,
  document,
  unknown,
}

extension SearchResultTypeX on SearchResultType {
  /// Wire value — the plural key used by the API when grouping results
  /// (`{"results": {"medications": [...], ...}}`).
  String get wireKey {
    switch (this) {
      case SearchResultType.medication:
        return 'medications';
      case SearchResultType.lab:
        return 'labs';
      case SearchResultType.vital:
        return 'vitals';
      case SearchResultType.appointment:
        return 'appointments';
      case SearchResultType.task:
        return 'tasks';
      case SearchResultType.diary:
        return 'diary';
      case SearchResultType.contact:
        return 'contacts';
      case SearchResultType.diagnosis:
        return 'diagnoses';
      case SearchResultType.allergy:
        return 'allergies';
      case SearchResultType.symptom:
        return 'symptoms';
      case SearchResultType.vaccination:
        return 'vaccinations';
      case SearchResultType.document:
        return 'documents';
      case SearchResultType.unknown:
        return 'unknown';
    }
  }

  /// Human-readable label shown as the list section header.
  String get label {
    switch (this) {
      case SearchResultType.medication:
        return 'Medications';
      case SearchResultType.lab:
        return 'Lab Results';
      case SearchResultType.vital:
        return 'Vitals';
      case SearchResultType.appointment:
        return 'Appointments';
      case SearchResultType.task:
        return 'Tasks';
      case SearchResultType.diary:
        return 'Diary Entries';
      case SearchResultType.contact:
        return 'Contacts';
      case SearchResultType.diagnosis:
        return 'Diagnoses';
      case SearchResultType.allergy:
        return 'Allergies';
      case SearchResultType.symptom:
        return 'Symptoms';
      case SearchResultType.vaccination:
        return 'Vaccinations';
      case SearchResultType.document:
        return 'Documents';
      case SearchResultType.unknown:
        return 'Other';
    }
  }

  /// Profile-scoped route base (the screen will append `/<profileId>`).
  String get routeBase {
    switch (this) {
      case SearchResultType.medication:
        return '/medications';
      case SearchResultType.lab:
        return '/labs';
      case SearchResultType.vital:
        return '/vitals';
      case SearchResultType.appointment:
        return '/appointments';
      case SearchResultType.task:
        return '/tasks';
      case SearchResultType.diary:
        return '/diary';
      case SearchResultType.contact:
        return '/contacts';
      case SearchResultType.diagnosis:
        return '/diagnoses';
      case SearchResultType.allergy:
        return '/allergies';
      case SearchResultType.symptom:
        return '/symptoms';
      case SearchResultType.vaccination:
        return '/vaccinations';
      case SearchResultType.document:
        return '/documents';
      case SearchResultType.unknown:
        return '/home';
    }
  }
}

SearchResultType searchResultTypeFromWire(String raw) {
  final key = raw.toLowerCase();
  for (final t in SearchResultType.values) {
    if (t.wireKey == key || t.name == key) return t;
  }
  // Tolerate singular forms.
  switch (key) {
    case 'medication':
      return SearchResultType.medication;
    case 'lab':
      return SearchResultType.lab;
    case 'vital':
      return SearchResultType.vital;
    case 'appointment':
      return SearchResultType.appointment;
    case 'task':
      return SearchResultType.task;
    case 'contact':
      return SearchResultType.contact;
    case 'diagnosis':
      return SearchResultType.diagnosis;
    case 'allergy':
      return SearchResultType.allergy;
    case 'symptom':
      return SearchResultType.symptom;
    case 'vaccination':
      return SearchResultType.vaccination;
    case 'document':
      return SearchResultType.document;
  }
  return SearchResultType.unknown;
}

class SearchResult {
  final SearchResultType type;
  final String id;
  final String? profileId;
  final String title;
  final String? subtitle;
  final String? matchedSnippet;

  const SearchResult({
    required this.type,
    required this.id,
    required this.profileId,
    required this.title,
    required this.subtitle,
    required this.matchedSnippet,
  });

  /// Flexible parser that handles both the documented flat shape
  /// (`{type, id, profile_id, title, subtitle, matched_field}`) and the
  /// grouped shape observed in the web client
  /// (`{results: {<type>: [{id, name?/title?/vaccine_name?/marker?, ...}]}}`).
  factory SearchResult.fromJson(
    Map<String, dynamic> json, {
    SearchResultType? fallbackType,
  }) {
    final typeRaw = (json['type'] as String?) ?? '';
    final type = typeRaw.isNotEmpty
        ? searchResultTypeFromWire(typeRaw)
        : (fallbackType ?? SearchResultType.unknown);

    final id = (json['id'] ?? '').toString();
    final profileId = (json['profile_id'] ?? json['profileId']) as String?;

    // Title fallback chain — matches the fields the web UI probes.
    final title = (json['title'] ??
            json['name'] ??
            json['vaccine_name'] ??
            json['marker'] ??
            json['subject'] ??
            json['label'] ??
            id)
        .toString();

    final subtitle = (json['subtitle'] ??
            json['description'] ??
            json['value'] ??
            json['notes'])
        ?.toString();

    final matched = (json['matched_snippet'] ??
            json['matchedSnippet'] ??
            json['matched_field'] ??
            json['matchedField'])
        ?.toString();

    return SearchResult(
      type: type,
      id: id,
      profileId: profileId,
      title: title,
      subtitle: subtitle,
      matchedSnippet: matched,
    );
  }
}
