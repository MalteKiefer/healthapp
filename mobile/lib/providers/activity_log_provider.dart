import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/activity_entry.dart';
import 'providers.dart';

/// Fetches the activity log for a single profile.
///
/// Calls `GET /api/v1/profiles/{profileId}/activity`. The backend wraps the
/// list in `{items: [...], total: N}`; this provider unwraps and returns just
/// the parsed [ActivityEntry] list, sorted newest-first (the backend already
/// orders by `created_at DESC`, but we re-sort defensively).
///
/// Invalidate this provider after any mutation that should immediately appear
/// in the activity log.
final activityLogProvider =
    FutureProvider.family<List<ActivityEntry>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get<Map<String, dynamic>>(
    '/api/v1/profiles/$profileId/activity?limit=200',
  );
  final items = (data['items'] as List? ?? const [])
      .map((e) => ActivityEntry.fromJson(e as Map<String, dynamic>))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return items;
});
