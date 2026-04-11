import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/common.dart';
import 'providers.dart';

/// Fetches only the open (not-yet-done) tasks for a given profile.
///
/// Backed by `GET /api/v1/profiles/{profileId}/tasks/open`, which returns
/// only tasks that have not been completed. The response is expected to
/// follow the same `{ "items": [...] }` envelope used by the regular
/// tasks list endpoint.
///
/// Usage:
/// ```dart
/// final asyncTasks = ref.watch(openTasksProvider(profileId));
/// ```
final openTasksProvider =
    FutureProvider.family<List<Task>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final data = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/tasks/open');
  final items = (data['items'] as List?) ?? const [];
  return items
      .map((e) => Task.fromJson(e as Map<String, dynamic>))
      .toList();
});
