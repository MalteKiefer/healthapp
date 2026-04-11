import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vital_thresholds.dart';
import 'providers.dart';

/// Family provider that fetches the current [VitalThresholds] for a profile.
///
/// Endpoint: `GET /api/v1/profiles/{profileId}/vital-thresholds`
final vitalThresholdsProvider =
    FutureProvider.family<VitalThresholds, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final raw = await api.get<Map<String, dynamic>>(
    '/api/v1/profiles/$profileId/vital-thresholds',
  );
  return VitalThresholds.fromJson(raw);
});

/// Immutable state for the save flow.
class VitalThresholdsSaveState {
  final bool saving;
  final Object? error;
  final bool success;

  const VitalThresholdsSaveState({
    this.saving = false,
    this.error,
    this.success = false,
  });

  VitalThresholdsSaveState copyWith({
    bool? saving,
    Object? error,
    bool? success,
    bool clearError = false,
  }) {
    return VitalThresholdsSaveState(
      saving: saving ?? this.saving,
      error: clearError ? null : (error ?? this.error),
      success: success ?? this.success,
    );
  }

  static const VitalThresholdsSaveState idle = VitalThresholdsSaveState();
}

/// StateNotifier that performs the PUT request to replace a profile's
/// vital thresholds.
///
/// Endpoint: `PUT /api/v1/profiles/{profileId}/vital-thresholds`
///
/// NOTE: The shared [ApiClient] currently only exposes
/// `get`/`post`/`patch`/`delete`. Once a typed `put<T>` method is added to
/// `ApiClient`, swap [_api.patch] below for [_api.put]. The backend route
/// for this feature uses PUT semantics (replace-all); PATCH with the full
/// document is accepted as an interim fallback, so the behaviour is
/// equivalent from the server's perspective for this endpoint.
class VitalThresholdsSaveNotifier
    extends StateNotifier<VitalThresholdsSaveState> {
  VitalThresholdsSaveNotifier(this._ref)
      : super(VitalThresholdsSaveState.idle);

  final Ref _ref;

  Future<bool> save(String profileId, VitalThresholds thresholds) async {
    state = state.copyWith(
      saving: true,
      success: false,
      clearError: true,
    );
    try {
      final api = _ref.read(apiClientProvider);
      // TODO(api_client): swap for api.put once ApiClient exposes a put<T>.
      await api.patch<dynamic>(
        '/api/v1/profiles/$profileId/vital-thresholds',
        body: thresholds.toJson(),
      );
      // Invalidate the read-side provider so fresh data is pulled.
      _ref.invalidate(vitalThresholdsProvider(profileId));
      state = const VitalThresholdsSaveState(success: true);
      return true;
    } catch (e) {
      state = VitalThresholdsSaveState(error: e);
      return false;
    }
  }

  void reset() {
    state = VitalThresholdsSaveState.idle;
  }
}

final vitalThresholdsSaveProvider = StateNotifierProvider<
    VitalThresholdsSaveNotifier, VitalThresholdsSaveState>(
  (ref) => VitalThresholdsSaveNotifier(ref),
);
