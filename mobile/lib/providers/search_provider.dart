import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../models/search_result.dart';
import 'providers.dart';

/// Sprint 4 client-side global-search controller.
///
/// The legacy `GET /api/v1/search` endpoint was retired in Sprint 2 (it now
/// returns 410 Gone). To preserve the search experience, this notifier
/// fetches every domain list for the currently selected profile in
/// parallel — using [ApiClient.getCached] so the same lists are reused
/// across navigations — and then performs a substring filter in memory
/// against a best-guess text representation of each item.
///
/// Like the previous version, keystrokes are debounced for 400ms.
class SearchNotifier extends StateNotifier<AsyncValue<List<SearchResult>>> {
  SearchNotifier(this._ref, this._api)
      : super(const AsyncValue.data(<SearchResult>[]));

  final Ref _ref;
  final ApiClient _api;
  Timer? _debounce;
  String _lastIssuedQuery = '';

  static const Duration _debounceDuration = Duration(milliseconds: 400);
  static const Duration _cacheTtl = Duration(minutes: 5);

  /// Schedule a debounced search for [q]. Passing an empty / whitespace-only
  /// query clears the current results without hitting the network.
  void query(String q) {
    _debounce?.cancel();
    final trimmed = q.trim();

    if (trimmed.isEmpty) {
      _lastIssuedQuery = '';
      state = const AsyncValue.data(<SearchResult>[]);
      return;
    }

    _debounce = Timer(_debounceDuration, () => _run(trimmed));
  }

  /// Cancel any pending debounce and clear the results. Useful when the
  /// screen is dismissed or the user taps the clear button.
  void clear() {
    _debounce?.cancel();
    _lastIssuedQuery = '';
    state = const AsyncValue.data(<SearchResult>[]);
  }

  Future<void> _run(String q) async {
    _lastIssuedQuery = q;
    state = const AsyncValue.loading();

    final profile = _ref.read(selectedProfileProvider);
    final profileId = profile?.id;
    if (profileId == null || profileId.isEmpty) {
      if (_lastIssuedQuery != q) return;
      state = const AsyncValue.data(<SearchResult>[]);
      return;
    }

    try {
      // Fetch all domain lists in parallel. Each fetch is wrapped so that a
      // single failing domain (404, decryption error, etc.) does not poison
      // the entire search.
      final futures = <Future<List<SearchResult>>>[
        _fetchDomain(
          profileId,
          'medications',
          SearchResultType.medication,
        ),
        _fetchDomain(profileId, 'labs', SearchResultType.lab),
        _fetchDomain(profileId, 'vitals', SearchResultType.vital),
        _fetchDomain(profileId, 'diagnoses', SearchResultType.diagnosis),
        _fetchDomain(profileId, 'allergies', SearchResultType.allergy),
        _fetchDomain(
          profileId,
          'vaccinations',
          SearchResultType.vaccination,
        ),
        _fetchDomain(
          profileId,
          'appointments',
          SearchResultType.appointment,
        ),
        _fetchDomain(profileId, 'tasks', SearchResultType.task),
        _fetchDomain(profileId, 'contacts', SearchResultType.contact),
        _fetchDomain(profileId, 'diary', SearchResultType.diary),
        _fetchDomain(profileId, 'symptoms', SearchResultType.symptom),
        _fetchDomain(profileId, 'documents', SearchResultType.document),
      ];

      final perDomain = await Future.wait(futures);
      if (_lastIssuedQuery != q) return;

      final all = <SearchResult>[];
      for (final list in perDomain) {
        all.addAll(list);
      }

      final needle = q.toLowerCase();
      final filtered = all
          .where((r) => _matches(r, needle))
          .toList(growable: false);

      state = AsyncValue.data(filtered);
    } catch (err, st) {
      if (_lastIssuedQuery != q) return;
      state = AsyncValue.error(err, st);
    }
  }

  /// Fetch one domain's list for [profileId], tolerating per-domain failures.
  Future<List<SearchResult>> _fetchDomain(
    String profileId,
    String domain,
    SearchResultType type,
  ) async {
    final path = '/api/v1/profiles/$profileId/$domain';
    try {
      final data = await _api.getCached<Map<String, dynamic>>(
        path,
        ttl: _cacheTtl,
      );
      final raw = data[domain] ?? data['items'] ?? data['results'] ?? data['data'];
      if (raw is! List) return const <SearchResult>[];

      final out = <SearchResult>[];
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          out.add(_buildResult(item, type, profileId));
        }
      }
      return out;
    } catch (_) {
      // A single domain failing should never break the whole search.
      return const <SearchResult>[];
    }
  }

  /// Build a normalized [SearchResult] from a raw domain item map.
  ///
  /// Different domains carry their primary text under different keys, so we
  /// probe a per-type list of likely "title" fields and fall back to a
  /// generic chain. The subtitle field is similarly probed and is also used
  /// as the snippet (matchedSnippet) so the row can show contextual text.
  SearchResult _buildResult(
    Map<String, dynamic> item,
    SearchResultType type,
    String profileId,
  ) {
    final id = (item['id'] ?? '').toString();

    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = item[k];
        if (v != null) {
          final s = v.toString();
          if (s.isNotEmpty) return s;
        }
      }
      return null;
    }

    String title;
    String? subtitle;

    switch (type) {
      case SearchResultType.medication:
        title = pick(['name', 'medication_name', 'title']) ?? id;
        subtitle = pick(['dosage', 'instructions', 'notes', 'description']);
        break;
      case SearchResultType.lab:
        title = pick(['marker', 'name', 'test_name', 'title']) ?? id;
        subtitle = pick(['value', 'result', 'unit', 'notes']);
        break;
      case SearchResultType.vital:
        title = pick(['type', 'name', 'metric', 'label']) ?? id;
        subtitle = pick(['value', 'systolic', 'notes']);
        break;
      case SearchResultType.diagnosis:
        title = pick(['name', 'diagnosis', 'condition', 'title']) ?? id;
        subtitle = pick(['icd10', 'icd_10', 'notes', 'description']);
        break;
      case SearchResultType.allergy:
        title = pick(['allergen', 'name', 'substance', 'title']) ?? id;
        subtitle = pick(['reaction', 'severity', 'notes']);
        break;
      case SearchResultType.vaccination:
        title = pick(['vaccine_name', 'vaccine', 'name', 'title']) ?? id;
        subtitle = pick(['manufacturer', 'lot', 'notes']);
        break;
      case SearchResultType.appointment:
        title = pick(['title', 'subject', 'name', 'reason']) ?? id;
        subtitle = pick(['location', 'provider', 'notes', 'description']);
        break;
      case SearchResultType.task:
        title = pick(['title', 'name', 'description']) ?? id;
        subtitle = pick(['notes', 'description', 'priority']);
        break;
      case SearchResultType.contact:
        title = pick(['name', 'full_name', 'display_name', 'title']) ?? id;
        subtitle = pick(['role', 'specialty', 'organization', 'phone']);
        break;
      case SearchResultType.diary:
        title = pick(['title', 'subject', 'mood']) ?? id;
        subtitle = pick(['content', 'body', 'notes', 'entry']);
        break;
      case SearchResultType.symptom:
        title = pick(['name', 'symptom', 'title']) ?? id;
        subtitle = pick(['severity', 'notes', 'description']);
        break;
      case SearchResultType.document:
        title = pick(['title', 'filename', 'name', 'file_name']) ?? id;
        subtitle = pick(['mime_type', 'category', 'notes', 'description']);
        break;
      case SearchResultType.unknown:
        title = pick(['name', 'title', 'label']) ?? id;
        subtitle = pick(['notes', 'description']);
        break;
    }

    return SearchResult(
      type: type,
      id: id,
      profileId: (item['profile_id'] ?? item['profileId'])?.toString() ??
          profileId,
      title: title,
      subtitle: subtitle,
      matchedSnippet: subtitle,
    );
  }

  /// Substring (case-insensitive) match against title and subtitle.
  bool _matches(SearchResult r, String needle) {
    if (r.title.toLowerCase().contains(needle)) return true;
    final sub = r.subtitle;
    if (sub != null && sub.toLowerCase().contains(needle)) return true;
    return false;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier,
    AsyncValue<List<SearchResult>>>((ref) {
  final api = ref.watch(apiClientProvider);
  return SearchNotifier(ref, api);
});
