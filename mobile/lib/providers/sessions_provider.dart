import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../models/user_session.dart';
import 'providers.dart';

/// Fetches the list of active sessions for the currently signed-in
/// user from `GET /api/v1/users/me/sessions`.
///
/// The server returns either a bare JSON array or an object of the
/// form `{items: [...]}`. Both shapes are accepted so the UI does
/// not have to care about minor server variations.
final sessionsListProvider =
    FutureProvider.autoDispose<List<UserSession>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get<dynamic>('/api/v1/users/me/sessions');

  List<dynamic> raw;
  if (data is List) {
    raw = data;
  } else if (data is Map<String, dynamic>) {
    final items = data['items'] ?? data['sessions'];
    raw = (items is List) ? items : const [];
  } else {
    raw = const [];
  }

  final sessions = raw
      .whereType<Map>()
      .map((m) => UserSession.fromJson(Map<String, dynamic>.from(m)))
      .toList();

  // Pin the current session at the top, then order remaining
  // sessions by most-recently-seen first.
  sessions.sort((a, b) {
    if (a.isCurrent && !b.isCurrent) return -1;
    if (!a.isCurrent && b.isCurrent) return 1;
    return b.lastSeenAt.compareTo(a.lastSeenAt);
  });

  return sessions;
});

/// Mutation state for revoke actions.
class SessionsActionState {
  /// Set of session ids currently being revoked. Used to disable
  /// the per-row "Revoke" button while the request is in flight.
  final Set<String> revokingIds;

  /// True while a "revoke all other sessions" call is in flight.
  final bool revokingAll;

  /// Last error message, if any. Cleared on the next attempt.
  final String? error;

  const SessionsActionState({
    this.revokingIds = const {},
    this.revokingAll = false,
    this.error,
  });

  SessionsActionState copyWith({
    Set<String>? revokingIds,
    bool? revokingAll,
    String? error,
    bool clearError = false,
  }) =>
      SessionsActionState(
        revokingIds: revokingIds ?? this.revokingIds,
        revokingAll: revokingAll ?? this.revokingAll,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Coordinates session revoke actions and invalidates
/// [sessionsListProvider] on success so the UI re-fetches.
class SessionsController extends StateNotifier<SessionsActionState> {
  SessionsController(this._api, this._ref)
      : super(const SessionsActionState());

  final ApiClient _api;
  final Ref _ref;

  /// DELETE /api/v1/users/me/sessions/{sessionId}
  Future<void> revoke(String sessionId) async {
    if (sessionId.isEmpty) return;
    final next = Set<String>.from(state.revokingIds)..add(sessionId);
    state = state.copyWith(revokingIds: next, clearError: true);
    try {
      await _api.delete('/api/v1/users/me/sessions/$sessionId');
      _ref.invalidate(sessionsListProvider);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    } finally {
      final after = Set<String>.from(state.revokingIds)..remove(sessionId);
      state = state.copyWith(revokingIds: after);
    }
  }

  /// DELETE /api/v1/users/me/sessions
  ///
  /// Revokes every session belonging to the user EXCEPT the one
  /// making the request. The server is responsible for preserving
  /// the current session.
  Future<void> revokeAllOthers() async {
    state = state.copyWith(revokingAll: true, clearError: true);
    try {
      await _api.delete('/api/v1/users/me/sessions');
      _ref.invalidate(sessionsListProvider);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    } finally {
      state = state.copyWith(revokingAll: false);
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final sessionsControllerProvider =
    StateNotifierProvider<SessionsController, SessionsActionState>((ref) {
  return SessionsController(ref.read(apiClientProvider), ref);
});
