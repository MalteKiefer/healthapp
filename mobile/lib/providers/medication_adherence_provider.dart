import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/medication_adherence.dart';
import 'providers.dart';

/// Fetches the adherence summary + per-medication breakdown for a profile.
final medicationAdherenceProvider =
    FutureProvider.family<MedicationAdherence, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get<Map<String, dynamic>>(
    '/api/v1/profiles/$profileId/medications/adherence',
  );
  return MedicationAdherence.fromJson(data);
});
