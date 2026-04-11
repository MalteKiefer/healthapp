import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/common.dart';
import 'providers.dart';

part 'vaccination_due_provider.g.dart';

/// Fetches vaccinations that are due soon or overdue for the given profile.
///
/// Backend endpoint: `GET /api/v1/profiles/{profileId}/vaccinations/due`.
///
/// Response shape (mirrors `web/src/api/vaccinations.ts`):
/// ```json
/// {
///   "items": [
///     {
///       "id": "...",
///       "vaccine_name": "Tetanus",
///       "trade_name": "...",
///       "manufacturer": "...",
///       "dose_number": 2,
///       "administered_at": "2024-04-10T00:00:00Z",
///       "next_due_at": "2026-04-10T00:00:00Z",
///       "site": "...",
///       "notes": "..."
///     }
///   ],
///   "total": 1
/// }
/// ```
///
/// The existing [Vaccination] model in `models/common.dart` is reused
/// as-is; no wrapper is introduced. `vaccine_name` is mapped onto the
/// existing `vaccine` field for compatibility with both the current
/// mobile list screen and the web API shape.
@riverpod
Future<List<Vaccination>> vaccinationDue(
  VaccinationDueRef ref,
  String profileId,
) async {
  final api = ref.read(apiClientProvider);
  final crypto = ref.watch(e2eCryptoServiceProvider);
  final data = await api.get<Map<String, dynamic>>(
    '/api/v1/profiles/$profileId/vaccinations/due',
  );
  final rawItems = (data['items'] as List?) ?? const [];
  final decrypted = await crypto.decryptRows(
    rows: rawItems,
    profileId: profileId,
    entityType: 'vaccinations',
  );
  final items = decrypted.map((raw) {
    // The /due endpoint may return `vaccine_name` (web shape) while the
    // existing mobile model expects `vaccine`. Normalize before parsing.
    final normalized = Map<String, dynamic>.from(raw);
    if (!normalized.containsKey('vaccine') &&
        normalized['vaccine_name'] != null) {
      normalized['vaccine'] = normalized['vaccine_name'];
    }
    return Vaccination.fromJson(normalized);
  }).toList();
  return items;
}
