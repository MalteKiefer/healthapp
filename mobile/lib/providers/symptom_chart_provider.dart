import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/symptom_chart_data.dart';
import 'providers.dart';

/// Fetches symptom chart data for a given profile id.
///
/// Calls `GET /api/v1/profiles/{profileId}/symptoms/chart` and returns a
/// [SymptomChartData] instance with one [SymptomSeries] per distinct
/// symptom type.
final symptomChartProvider =
    FutureProvider.family<SymptomChartData, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final raw = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/symptoms/chart');
  return SymptomChartData.fromJson(raw);
});
