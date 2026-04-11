import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/common.dart';
import 'providers.dart';

/// Fetches only upcoming appointments for a given profile.
///
/// Backed by `GET /api/v1/profiles/{profileId}/appointments/upcoming`.
final upcomingAppointmentsProvider =
    FutureProvider.family<List<Appointment>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final crypto = ref.watch(e2eCryptoServiceProvider);
  final data = await api.get<Map<String, dynamic>>(
    '/api/v1/profiles/$profileId/appointments/upcoming',
  );
  final rawItems = (data['items'] as List?) ?? const [];
  final decrypted = await crypto.decryptRows(
    rows: rawItems,
    profileId: profileId,
    entityType: 'appointments',
  );
  return decrypted.map(Appointment.fromJson).toList();
});

/// State of the appointment completion action.
class AppointmentCompletionState {
  final bool isLoading;
  final String? error;
  final String? completedId;

  const AppointmentCompletionState({
    this.isLoading = false,
    this.error,
    this.completedId,
  });

  AppointmentCompletionState copyWith({
    bool? isLoading,
    String? error,
    String? completedId,
  }) {
    return AppointmentCompletionState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      completedId: completedId ?? this.completedId,
    );
  }

  static const AppointmentCompletionState initial =
      AppointmentCompletionState();
}

/// StateNotifier that marks an appointment as complete and invalidates the
/// upcoming list on success.
class AppointmentCompletionController
    extends StateNotifier<AppointmentCompletionState> {
  AppointmentCompletionController(this._ref)
      : super(AppointmentCompletionState.initial);

  final Ref _ref;

  Future<bool> complete(
    String profileId,
    String apptId, {
    String? notes,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final api = _ref.read(apiClientProvider);
      final body = <String, dynamic>{};
      if (notes != null && notes.trim().isNotEmpty) {
        body['notes'] = notes.trim();
      }
      await api.post<dynamic>(
        '/api/v1/profiles/$profileId/appointments/$apptId/complete',
        body: body.isEmpty ? null : body,
      );
      _ref.invalidate(upcomingAppointmentsProvider(profileId));
      state = AppointmentCompletionState(
        isLoading: false,
        completedId: apptId,
      );
      return true;
    } catch (e) {
      state = AppointmentCompletionState(
        isLoading: false,
        error: e.toString(),
      );
      return false;
    }
  }

  void reset() {
    state = AppointmentCompletionState.initial;
  }
}

final appointmentCompletionControllerProvider = StateNotifierProvider<
    AppointmentCompletionController, AppointmentCompletionState>(
  (ref) => AppointmentCompletionController(ref),
);
