import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../models/emergency_access.dart';
import 'providers.dart';

/// Riverpod providers for the Emergency Access feature.
///
/// Endpoints (Sprint 3):
///   GET    /api/v1/profiles/{profileId}/emergency-card
///   GET    /api/v1/profiles/{profileId}/emergency-access
///   POST   /api/v1/profiles/{profileId}/emergency-access
///   DELETE /api/v1/profiles/{profileId}/emergency-access
///   GET    /api/v1/emergency/pending
///   POST   /api/v1/emergency/approve/{requestId}
///   POST   /api/v1/emergency/deny/{requestId}

// ---------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------

/// Read-only emergency card for a profile. The endpoint may legitimately
/// return 404 when the feature is disabled — callers should handle the
/// resulting [AsyncError] (or check `EmergencyAccessConfig.enabled` first).
final emergencyCardProvider =
    FutureProvider.family<EmergencyCard, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final raw = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/emergency-card');
  return EmergencyCard.fromJson(raw);
});

/// Current configuration row for a profile. If the server returns 404 we
/// surface a default disabled config so the UI does not need an extra
/// branch for "no config yet".
final emergencyAccessConfigProvider =
    FutureProvider.family<EmergencyAccessConfig, String>(
        (ref, profileId) async {
  final api = ref.read(apiClientProvider);
  try {
    final raw = await api.get<Map<String, dynamic>>(
      '/api/v1/profiles/$profileId/emergency-access',
    );
    final cfg = EmergencyAccessConfig.fromJson(raw);
    // Make sure profileId is populated even if the server omitted it.
    return cfg.profileId.isEmpty
        ? cfg.copyWith(profileId: profileId)
        : cfg;
  } on ApiException catch (e) {
    if (e.statusCode == 404) {
      return EmergencyAccessConfig.disabled(profileId);
    }
    rethrow;
  }
});

/// Pending incoming emergency requests for the current user.
///
/// Backend shape: `{ items: [...] }`.
final emergencyPendingRequestsProvider =
    FutureProvider<List<EmergencyRequest>>((ref) async {
  final api = ref.read(apiClientProvider);
  final raw = await api.get<Map<String, dynamic>>('/api/v1/emergency/pending');
  final items = raw['items'];
  if (items is! List) return const <EmergencyRequest>[];
  return items
      .whereType<Map>()
      .map((e) => EmergencyRequest.fromJson(Map<String, dynamic>.from(e)))
      .toList();
});

// ---------------------------------------------------------------------------
// Mutation state
// ---------------------------------------------------------------------------

/// Tracks the state of a single mutation flow (save / disable / approve /
/// deny). Errors are stored as [Object] so callers can pass them straight
/// to `apiErrorMessage()`.
class EmergencyAccessMutationState {
  final bool busy;
  final Object? error;
  final bool success;

  const EmergencyAccessMutationState({
    this.busy = false,
    this.error,
    this.success = false,
  });

  static const EmergencyAccessMutationState idle =
      EmergencyAccessMutationState();

  EmergencyAccessMutationState copyWith({
    bool? busy,
    Object? error,
    bool? success,
    bool clearError = false,
  }) {
    return EmergencyAccessMutationState(
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      success: success ?? this.success,
    );
  }
}

// ---------------------------------------------------------------------------
// Config save / disable
// ---------------------------------------------------------------------------

class EmergencyAccessConfigController
    extends StateNotifier<EmergencyAccessMutationState> {
  EmergencyAccessConfigController(this._ref)
      : super(EmergencyAccessMutationState.idle);

  final Ref _ref;

  /// POST /api/v1/profiles/{profileId}/emergency-access
  Future<bool> save(EmergencyAccessConfig config) async {
    state = state.copyWith(busy: true, success: false, clearError: true);
    try {
      final api = _ref.read(apiClientProvider);
      await api.post<dynamic>(
        '/api/v1/profiles/${config.profileId}/emergency-access',
        body: config.toCreateJson(),
      );
      _ref.invalidate(emergencyAccessConfigProvider(config.profileId));
      _ref.invalidate(emergencyCardProvider(config.profileId));
      state = const EmergencyAccessMutationState(success: true);
      return true;
    } catch (e) {
      state = EmergencyAccessMutationState(error: e);
      return false;
    }
  }

  /// DELETE /api/v1/profiles/{profileId}/emergency-access
  Future<bool> disable(String profileId) async {
    state = state.copyWith(busy: true, success: false, clearError: true);
    try {
      final api = _ref.read(apiClientProvider);
      await api.delete('/api/v1/profiles/$profileId/emergency-access');
      _ref.invalidate(emergencyAccessConfigProvider(profileId));
      _ref.invalidate(emergencyCardProvider(profileId));
      state = const EmergencyAccessMutationState(success: true);
      return true;
    } catch (e) {
      state = EmergencyAccessMutationState(error: e);
      return false;
    }
  }

  void reset() {
    state = EmergencyAccessMutationState.idle;
  }
}

final emergencyAccessConfigControllerProvider = StateNotifierProvider<
    EmergencyAccessConfigController, EmergencyAccessMutationState>(
  (ref) => EmergencyAccessConfigController(ref),
);

// ---------------------------------------------------------------------------
// Approve / deny pending requests
// ---------------------------------------------------------------------------

class EmergencyRequestsController
    extends StateNotifier<EmergencyAccessMutationState> {
  EmergencyRequestsController(this._ref)
      : super(EmergencyAccessMutationState.idle);

  final Ref _ref;

  /// POST /api/v1/emergency/approve/{requestId}
  Future<bool> approve(String requestId) async {
    state = state.copyWith(busy: true, success: false, clearError: true);
    try {
      final api = _ref.read(apiClientProvider);
      await api.post<dynamic>('/api/v1/emergency/approve/$requestId');
      _ref.invalidate(emergencyPendingRequestsProvider);
      state = const EmergencyAccessMutationState(success: true);
      return true;
    } catch (e) {
      state = EmergencyAccessMutationState(error: e);
      return false;
    }
  }

  /// POST /api/v1/emergency/deny/{requestId}
  Future<bool> deny(String requestId) async {
    state = state.copyWith(busy: true, success: false, clearError: true);
    try {
      final api = _ref.read(apiClientProvider);
      await api.post<dynamic>('/api/v1/emergency/deny/$requestId');
      _ref.invalidate(emergencyPendingRequestsProvider);
      state = const EmergencyAccessMutationState(success: true);
      return true;
    } catch (e) {
      state = EmergencyAccessMutationState(error: e);
      return false;
    }
  }

  void reset() {
    state = EmergencyAccessMutationState.idle;
  }
}

final emergencyRequestsControllerProvider = StateNotifierProvider<
    EmergencyRequestsController, EmergencyAccessMutationState>(
  (ref) => EmergencyRequestsController(ref),
);
