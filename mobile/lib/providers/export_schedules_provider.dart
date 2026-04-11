import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/api_error_messages.dart';
import '../models/export_schedule.dart';
import 'providers.dart';

/// Fetches the list of scheduled exports for the current user.
///
/// Endpoint: `GET /api/v1/export/schedules`. The backend response is
/// expected to be either a `{items: [...]}` envelope or a bare JSON array;
/// both shapes are supported.
final exportSchedulesProvider =
    FutureProvider<List<ExportSchedule>>((ref) async {
  final api = ref.read(apiClientProvider);
  final raw = await api.get<dynamic>('/api/v1/export/schedules');
  final list = raw is Map<String, dynamic>
      ? (raw['items'] as List? ?? const [])
      : (raw as List? ?? const []);
  return list
      .whereType<Map>()
      .map((e) => ExportSchedule.fromJson(e.cast<String, dynamic>()))
      .toList();
});

/// Mutation state for create / delete actions on export schedules.
class ExportSchedulesMutationState {
  final bool busy;
  final String? error;
  final bool success;

  const ExportSchedulesMutationState({
    this.busy = false,
    this.error,
    this.success = false,
  });

  ExportSchedulesMutationState copyWith({
    bool? busy,
    String? error,
    bool? success,
    bool clearError = false,
  }) =>
      ExportSchedulesMutationState(
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
        success: success ?? this.success,
      );

  static const ExportSchedulesMutationState idle =
      ExportSchedulesMutationState();
}

/// Controller for create / delete operations on export schedules.
class ExportSchedulesController
    extends StateNotifier<ExportSchedulesMutationState> {
  ExportSchedulesController(this._api, this._ref)
      : super(ExportSchedulesMutationState.idle);

  final ApiClient _api;
  final Ref _ref;

  /// POST /api/v1/export/schedule
  Future<bool> create({
    required String profileId,
    required String format,
    required String cron,
    required String destination,
  }) async {
    state = state.copyWith(busy: true, success: false, clearError: true);
    try {
      await _api.post<dynamic>(
        '/api/v1/export/schedule',
        body: ExportSchedule.createBody(
          profileId: profileId,
          format: format,
          cron: cron,
          destination: destination,
        ),
      );
      _ref.invalidate(exportSchedulesProvider);
      state = const ExportSchedulesMutationState(success: true);
      return true;
    } catch (e) {
      state = ExportSchedulesMutationState(error: apiErrorMessage(e));
      return false;
    }
  }

  /// DELETE /api/v1/export/schedules/{scheduleId}
  Future<bool> delete(String scheduleId) async {
    state = state.copyWith(busy: true, success: false, clearError: true);
    try {
      await _api.delete('/api/v1/export/schedules/$scheduleId');
      _ref.invalidate(exportSchedulesProvider);
      state = const ExportSchedulesMutationState(success: true);
      return true;
    } catch (e) {
      state = ExportSchedulesMutationState(error: apiErrorMessage(e));
      return false;
    }
  }

  void reset() {
    state = ExportSchedulesMutationState.idle;
  }
}

final exportSchedulesControllerProvider = StateNotifierProvider<
    ExportSchedulesController, ExportSchedulesMutationState>((ref) {
  return ExportSchedulesController(ref.read(apiClientProvider), ref);
});
