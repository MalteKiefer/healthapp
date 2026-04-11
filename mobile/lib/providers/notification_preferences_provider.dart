import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../models/notification.dart';
import 'providers.dart';

/// Reads the current user's notification channel preferences from
/// `/api/v1/notifications/preferences`.
///
/// If no preferences exist yet the backend returns a default-populated
/// struct, so the provider always resolves to a valid
/// [NotificationPreferences].
final notificationPreferencesProvider =
    FutureProvider<NotificationPreferences>((ref) async {
  final api = ref.read(apiClientProvider);
  final data =
      await api.get<Map<String, dynamic>>('/api/v1/notifications/preferences');
  return NotificationPreferences.fromJson(data);
});

/// Thin controller responsible for persisting preference edits.
///
/// Usage: `ref.read(notificationPreferencesControllerProvider.notifier)
///              .save(newPrefs);`
class NotificationPreferencesController extends StateNotifier<AsyncValue<void>> {
  NotificationPreferencesController(this._api, this._ref)
      : super(const AsyncValue.data(null));

  final ApiClient _api;
  final Ref _ref;

  /// PATCH /api/v1/notifications/preferences with the full preferences
  /// object. Invalidates [notificationPreferencesProvider] on success so
  /// the UI re-reads the server-normalised values.
  Future<void> save(NotificationPreferences prefs) async {
    state = const AsyncValue.loading();
    try {
      await _api.patch<Map<String, dynamic>>(
        '/api/v1/notifications/preferences',
        body: prefs.toJson(),
      );
      _ref.invalidate(notificationPreferencesProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

final notificationPreferencesControllerProvider =
    StateNotifierProvider<NotificationPreferencesController, AsyncValue<void>>(
        (ref) {
  return NotificationPreferencesController(
      ref.read(apiClientProvider), ref);
});
