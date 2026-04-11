import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/medication_intake.dart';
import 'providers.dart';

/// Composite key for the intake list provider.
class MedicationIntakeKey {
  final String profileId;
  final String medicationId;
  const MedicationIntakeKey(this.profileId, this.medicationId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MedicationIntakeKey &&
          other.profileId == profileId &&
          other.medicationId == medicationId);

  @override
  int get hashCode => Object.hash(profileId, medicationId);
}

/// Fetches the list of logged intakes for a given medication.
final medicationIntakeListProvider = FutureProvider.family<
    List<MedicationIntake>, MedicationIntakeKey>((ref, key) async {
  final api = ref.read(apiClientProvider);
  final crypto = ref.watch(e2eCryptoServiceProvider);
  final data = await api.get<Map<String, dynamic>>(
    '/api/v1/profiles/${key.profileId}/medications/${key.medicationId}/intake',
  );
  final rawItems = (data['items'] as List?) ?? const [];
  final decrypted = await crypto.decryptRows(
    rows: rawItems,
    profileId: key.profileId,
    entityType: 'medication_intake',
  );
  return decrypted.map(MedicationIntake.fromJson).toList();
});

/// Public state for the intake mutation controller.
class MedicationIntakeMutationState {
  final bool loading;
  final Object? error;
  const MedicationIntakeMutationState({this.loading = false, this.error});

  MedicationIntakeMutationState copyWith({bool? loading, Object? error}) =>
      MedicationIntakeMutationState(
        loading: loading ?? this.loading,
        error: error,
      );
}

/// Handles create / update / delete for medication intakes. Callers should
/// `invalidate` the relevant [medicationIntakeListProvider] family entry
/// afterwards (the notifier does this automatically on success).
class MedicationIntakeController
    extends StateNotifier<MedicationIntakeMutationState> {
  MedicationIntakeController(this._ref)
      : super(const MedicationIntakeMutationState());

  final Ref _ref;

  Future<bool> logIntake({
    required String profileId,
    required String medicationId,
    required DateTime takenAt,
    String? doseTaken,
    String? notes,
  }) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final api = _ref.read(apiClientProvider);
      final body = <String, dynamic>{
        'taken_at': takenAt.toUtc().toIso8601String(),
        if (doseTaken != null && doseTaken.isNotEmpty) 'dose_taken': doseTaken,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      };
      final crypto = _ref.read(e2eCryptoServiceProvider);
      final write = await crypto.encryptForWrite(
        profileId: profileId,
        entityType: 'medication_intake',
        body: body,
        existingId: null,
      );
      await api.post(
        '/api/v1/profiles/$profileId/medications/$medicationId/intake',
        body: write.toBody(),
      );
      _ref.invalidate(
        medicationIntakeListProvider(
          MedicationIntakeKey(profileId, medicationId),
        ),
      );
      state = const MedicationIntakeMutationState();
      return true;
    } catch (e) {
      state = MedicationIntakeMutationState(loading: false, error: e);
      return false;
    }
  }

  Future<bool> updateIntake({
    required String profileId,
    required String medicationId,
    required String intakeId,
    DateTime? takenAt,
    String? doseTaken,
    String? notes,
  }) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final api = _ref.read(apiClientProvider);
      final body = <String, dynamic>{};
      if (takenAt != null) {
        body['taken_at'] = takenAt.toUtc().toIso8601String();
      }
      if (doseTaken != null) body['dose_taken'] = doseTaken;
      if (notes != null) body['notes'] = notes;
      final crypto = _ref.read(e2eCryptoServiceProvider);
      final write = await crypto.encryptForWrite(
        profileId: profileId,
        entityType: 'medication_intake',
        body: body,
        existingId: intakeId,
      );
      await api.patch(
        '/api/v1/profiles/$profileId/medications/$medicationId/intake/${write.id}',
        body: write.toBody(),
      );
      _ref.invalidate(
        medicationIntakeListProvider(
          MedicationIntakeKey(profileId, medicationId),
        ),
      );
      state = const MedicationIntakeMutationState();
      return true;
    } catch (e) {
      state = MedicationIntakeMutationState(loading: false, error: e);
      return false;
    }
  }

  Future<bool> deleteIntake({
    required String profileId,
    required String medicationId,
    required String intakeId,
  }) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final api = _ref.read(apiClientProvider);
      await api.delete(
        '/api/v1/profiles/$profileId/medications/$medicationId/intake/$intakeId',
      );
      _ref.invalidate(
        medicationIntakeListProvider(
          MedicationIntakeKey(profileId, medicationId),
        ),
      );
      state = const MedicationIntakeMutationState();
      return true;
    } catch (e) {
      state = MedicationIntakeMutationState(loading: false, error: e);
      return false;
    }
  }
}

final medicationIntakeControllerProvider = StateNotifierProvider<
    MedicationIntakeController, MedicationIntakeMutationState>(
  (ref) => MedicationIntakeController(ref),
);
