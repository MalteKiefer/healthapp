import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/common.dart';
import 'providers.dart';

part 'open_tasks_provider.g.dart';

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
@riverpod
Future<List<Task>> openTasks(OpenTasksRef ref, String profileId) async {
  final api = ref.read(apiClientProvider);
  final crypto = ref.watch(e2eCryptoServiceProvider);
  final data = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/tasks/open');
  final rawItems = (data['items'] as List?) ?? const [];
  final decrypted = await crypto.decryptRows(
    rows: rawItems,
    profileId: profileId,
    entityType: 'tasks',
  );
  return decrypted.map(Task.fromJson).toList();
}
