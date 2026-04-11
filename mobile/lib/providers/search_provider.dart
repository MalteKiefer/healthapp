import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../models/search_result.dart';
import 'providers.dart';

/// Debounced global-search controller.
///
/// Backs the Sprint 2 global search feature: users type into the search bar
/// on [SearchScreen], and every keystroke is funneled into [query]. The
/// controller debounces keystrokes for 400ms and then issues a single
/// `GET /api/v1/search?q=...` request via [ApiClient].
class SearchNotifier extends StateNotifier<AsyncValue<List<SearchResult>>> {
  SearchNotifier(this._api) : super(const AsyncValue.data(<SearchResult>[]));

  final ApiClient _api;
  Timer? _debounce;
  String _lastIssuedQuery = '';

  static const Duration _debounceDuration = Duration(milliseconds: 400);

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
    try {
      final encoded = Uri.encodeQueryComponent(q);
      final data = await _api
          .get<Map<String, dynamic>>('/api/v1/search?q=$encoded');
      // If a newer query came in while we were awaiting, discard this result.
      if (_lastIssuedQuery != q) return;
      final results = _parse(data);
      state = AsyncValue.data(results);
    } catch (err, st) {
      if (_lastIssuedQuery != q) return;
      state = AsyncValue.error(err, st);
    }
  }

  /// Parses the two known response shapes:
  ///   1. Flat list:  `{"results": [ {type, id, ...}, ... ]}`
  ///   2. Grouped:    `{"results": {"medications": [...], "labs": [...]}}`
  List<SearchResult> _parse(Map<String, dynamic> data) {
    final raw = data['results'];
    final out = <SearchResult>[];

    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          out.add(SearchResult.fromJson(item));
        }
      }
    } else if (raw is Map<String, dynamic>) {
      for (final entry in raw.entries) {
        final fallback = searchResultTypeFromWire(entry.key);
        final list = entry.value;
        if (list is List) {
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              out.add(SearchResult.fromJson(item, fallbackType: fallback));
            }
          }
        }
      }
    }
    return out;
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
  return SearchNotifier(api);
});
