import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/calendar_feed.dart';
import 'providers.dart';

/// Loads the user's calendar feeds via `GET /api/v1/calendar/feeds`.
///
/// The list endpoint is unauthenticated only when the bearer token in the
/// URL path is used; this provider is the authenticated management view.
final calendarFeedsListProvider =
    FutureProvider<List<CalendarFeed>>((ref) async {
  final api = ref.read(apiClientProvider);
  final raw = await api.get<Map<String, dynamic>>('/api/v1/calendar/feeds');
  final items = (raw['items'] as List?) ?? const [];
  return items
      .map((e) => CalendarFeed.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Loads a single calendar feed via `GET /api/v1/calendar/feeds/{feedId}`.
final calendarFeedProvider =
    FutureProvider.family<CalendarFeed, String>((ref, feedId) async {
  final api = ref.read(apiClientProvider);
  final raw =
      await api.get<Map<String, dynamic>>('/api/v1/calendar/feeds/$feedId');
  return CalendarFeed.fromJson(raw);
});

/// Immutable state for the calendar feed CRUD flow.
class CalendarFeedsMutationState {
  final bool busy;
  final Object? error;

  /// Populated only after a successful create — contains the one-time
  /// plaintext token + URL the backend returns.
  final CalendarFeed? lastCreated;

  const CalendarFeedsMutationState({
    this.busy = false,
    this.error,
    this.lastCreated,
  });

  CalendarFeedsMutationState copyWith({
    bool? busy,
    Object? error,
    CalendarFeed? lastCreated,
    bool clearError = false,
    bool clearLastCreated = false,
  }) {
    return CalendarFeedsMutationState(
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      lastCreated:
          clearLastCreated ? null : (lastCreated ?? this.lastCreated),
    );
  }

  static const CalendarFeedsMutationState idle = CalendarFeedsMutationState();
}

/// StateNotifier that performs create / update / delete on calendar feeds.
///
/// All mutations invalidate [calendarFeedsListProvider] (and the per-feed
/// detail provider where applicable) so the UI re-fetches fresh data.
class CalendarFeedsNotifier extends StateNotifier<CalendarFeedsMutationState> {
  CalendarFeedsNotifier(this._ref) : super(CalendarFeedsMutationState.idle);

  final Ref _ref;

  /// `POST /api/v1/calendar/feeds`
  Future<CalendarFeed?> create({
    required String name,
    required String profileId,
    required List<String> contentTypes,
    bool verboseMode = false,
  }) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final api = _ref.read(apiClientProvider);
      final body = CalendarFeed.buildWriteBody(
        name: name,
        profileId: profileId,
        contentTypes: contentTypes,
        verboseMode: verboseMode,
      );
      final raw = await api.post<Map<String, dynamic>>(
        '/api/v1/calendar/feeds',
        body: body,
      );
      final feed = CalendarFeed.fromJson(raw);
      _ref.invalidate(calendarFeedsListProvider);
      state = CalendarFeedsMutationState(lastCreated: feed);
      return feed;
    } catch (e) {
      state = CalendarFeedsMutationState(error: e);
      return null;
    }
  }

  /// `PATCH /api/v1/calendar/feeds/{feedId}`
  Future<bool> update({
    required String feedId,
    required String name,
    required String profileId,
    required List<String> contentTypes,
    List<String> extraProfileIds = const <String>[],
    bool verboseMode = false,
  }) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final api = _ref.read(apiClientProvider);
      final body = CalendarFeed.buildWriteBody(
        name: name,
        profileId: profileId,
        extraProfileIds: extraProfileIds,
        contentTypes: contentTypes,
        verboseMode: verboseMode,
      );
      await api.patch<dynamic>(
        '/api/v1/calendar/feeds/$feedId',
        body: body,
      );
      _ref.invalidate(calendarFeedsListProvider);
      _ref.invalidate(calendarFeedProvider(feedId));
      state = const CalendarFeedsMutationState();
      return true;
    } catch (e) {
      state = CalendarFeedsMutationState(error: e);
      return false;
    }
  }

  /// `DELETE /api/v1/calendar/feeds/{feedId}`
  Future<bool> delete(String feedId) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final api = _ref.read(apiClientProvider);
      await api.delete('/api/v1/calendar/feeds/$feedId');
      _ref.invalidate(calendarFeedsListProvider);
      state = const CalendarFeedsMutationState();
      return true;
    } catch (e) {
      state = CalendarFeedsMutationState(error: e);
      return false;
    }
  }

  void reset() {
    state = CalendarFeedsMutationState.idle;
  }
}

final calendarFeedsNotifierProvider = StateNotifierProvider<
    CalendarFeedsNotifier, CalendarFeedsMutationState>(
  (ref) => CalendarFeedsNotifier(ref),
);

/// Builds the public ICS URL for a feed token, using the API client's
/// configured base URL. Used by the list screen's copy button when the
/// backend didn't return a fully-formed `url` (i.e. the feed was loaded
/// from `GET /calendar/feeds`, not freshly created).
String buildIcsUrl(String baseUrl, String tokenOrHash) {
  final cleaned = baseUrl.replaceAll(RegExp(r'/+$'), '');
  return '$cleaned/cal/$tokenOrHash.ics';
}
