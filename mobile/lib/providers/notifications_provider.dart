import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../models/notification.dart';
import 'providers.dart';

/// Result of a notifications list fetch — items plus server-reported total.
class NotificationListResult {
  final List<AppNotification> items;
  final int total;
  const NotificationListResult({required this.items, required this.total});

  int get unreadCount => items.where((n) => n.isUnread).length;
}

/// Fetches the current user's notifications from `/api/v1/notifications`.
///
/// Backend returns `{items: [...], total: N}`. Invalidate this provider to
/// force a refetch after mutations.
final notificationsProvider =
    FutureProvider<NotificationListResult>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get<Map<String, dynamic>>('/api/v1/notifications');
  final items = (data['items'] as List? ?? [])
      .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
      .toList();
  final total = (data['total'] as num?)?.toInt() ?? items.length;
  return NotificationListResult(items: items, total: total);
});

/// Mutation state for mark-read / mark-all-read / delete actions.
class NotificationMutationState {
  final bool busy;
  final String? error;
  const NotificationMutationState({this.busy = false, this.error});

  NotificationMutationState copyWith({bool? busy, String? error}) =>
      NotificationMutationState(busy: busy ?? this.busy, error: error);
}

class NotificationsController
    extends StateNotifier<NotificationMutationState> {
  NotificationsController(this._api, this._ref)
      : super(const NotificationMutationState());

  final ApiClient _api;
  final Ref _ref;

  /// POST /api/v1/notifications/{id}/read
  Future<void> markRead(String id) async {
    state = state.copyWith(busy: true, error: null);
    try {
      await _api.post<void>('/api/v1/notifications/$id/read');
      _ref.invalidate(notificationsProvider);
      state = const NotificationMutationState();
    } catch (e) {
      state = NotificationMutationState(busy: false, error: e.toString());
    }
  }

  /// POST /api/v1/notifications/read-all
  Future<void> markAllRead() async {
    state = state.copyWith(busy: true, error: null);
    try {
      await _api.post<void>('/api/v1/notifications/read-all');
      _ref.invalidate(notificationsProvider);
      state = const NotificationMutationState();
    } catch (e) {
      state = NotificationMutationState(busy: false, error: e.toString());
    }
  }

  /// DELETE /api/v1/notifications/{id}
  Future<void> delete(String id) async {
    state = state.copyWith(busy: true, error: null);
    try {
      await _api.delete('/api/v1/notifications/$id');
      _ref.invalidate(notificationsProvider);
      state = const NotificationMutationState();
    } catch (e) {
      state = NotificationMutationState(busy: false, error: e.toString());
    }
  }
}

final notificationsControllerProvider = StateNotifierProvider<
    NotificationsController, NotificationMutationState>((ref) {
  return NotificationsController(ref.read(apiClientProvider), ref);
});
