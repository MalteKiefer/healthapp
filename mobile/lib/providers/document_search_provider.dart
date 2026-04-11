import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/common.dart';
import 'providers.dart';

/// Debounced OCR-indexed document search controller.
///
/// Backs the Sprint 3 document search feature: every keystroke is funneled
/// into [search] and debounced for 400ms before issuing
/// `GET /api/v1/profiles/{profileId}/documents/search?q=...`.
///
/// Empty / whitespace-only queries clear results without hitting the
/// network. If a newer query arrives while a request is in flight, the
/// older response is discarded.
class DocumentSearchNotifier
    extends StateNotifier<AsyncValue<List<Document>>> {
  DocumentSearchNotifier(this._ref)
      : super(const AsyncValue.data(<Document>[]));

  final Ref _ref;
  Timer? _debounce;
  String _lastIssuedQuery = '';
  String _lastProfileId = '';

  static const Duration _debounceDuration = Duration(milliseconds: 400);

  /// Schedule a debounced search for [query] within [profileId].
  void search(String profileId, String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    _lastProfileId = profileId;

    if (trimmed.isEmpty) {
      _lastIssuedQuery = '';
      state = const AsyncValue.data(<Document>[]);
      return;
    }

    _debounce = Timer(_debounceDuration, () => _run(profileId, trimmed));
  }

  /// Cancel any pending debounce and clear the result list.
  void clear() {
    _debounce?.cancel();
    _lastIssuedQuery = '';
    state = const AsyncValue.data(<Document>[]);
  }

  Future<void> _run(String profileId, String q) async {
    _lastIssuedQuery = q;
    state = const AsyncValue.loading();
    try {
      final api = _ref.read(apiClientProvider);
      final encoded = Uri.encodeQueryComponent(q);
      final data = await api.get<Map<String, dynamic>>(
        '/api/v1/profiles/$profileId/documents/search?q=$encoded',
      );
      // Discard stale responses (user kept typing or switched profile).
      if (_lastIssuedQuery != q || _lastProfileId != profileId) return;
      final results = _parse(data);
      state = AsyncValue.data(results);
    } catch (err, st) {
      if (_lastIssuedQuery != q || _lastProfileId != profileId) return;
      state = AsyncValue.error(err, st);
    }
  }

  List<Document> _parse(Map<String, dynamic> data) {
    final raw = data['items'] ?? data['results'] ?? const <dynamic>[];
    if (raw is! List) return const <Document>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Document.fromJson)
        .toList(growable: false);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final documentSearchProvider = StateNotifierProvider<DocumentSearchNotifier,
    AsyncValue<List<Document>>>(
  (ref) => DocumentSearchNotifier(ref),
);
