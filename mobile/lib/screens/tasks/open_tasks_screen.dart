import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/common.dart';
import '../../providers/open_tasks_provider.dart';

/// A screen that lists only the open (not-yet-done) tasks for a profile.
///
/// Tasks are sorted ascending by due date. Tasks whose due date has
/// passed are highlighted using [ColorScheme.error]. Tapping a tile
/// toggles its local selection state; long-pressing opens a simple
/// detail dialog.
///
/// This screen is intentionally read-only: creation, editing and
/// completion toggling continue to live in the main tasks screen.
class OpenTasksScreen extends ConsumerStatefulWidget {
  final String profileId;

  const OpenTasksScreen({super.key, required this.profileId});

  @override
  ConsumerState<OpenTasksScreen> createState() => _OpenTasksScreenState();
}

class _OpenTasksScreenState extends ConsumerState<OpenTasksScreen> {
  final Set<String> _selected = <String>{};

  DateTime? _parseDue(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  List<Task> _sortByDueAsc(List<Task> tasks) {
    final sorted = [...tasks];
    sorted.sort((a, b) {
      final da = _parseDue(a.dueAt);
      final db = _parseDue(b.dueAt);
      if (da == null && db == null) return 0;
      if (da == null) return 1; // tasks without a due date go last
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return sorted;
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _showDetail(Task task) async {
    final due = _parseDue(task.dueAt);
    final dueLabel = due == null
        ? 'No due date'
        : DateFormat.yMMMd().add_Hm().format(due);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(task.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Due: $dueLabel'),
            if (task.priority != null && task.priority!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Priority: ${task.priority}'),
              ),
            if (task.status != null && task.status!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Status: ${task.status}'),
              ),
            if (task.description != null && task.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(task.description!),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final asyncTasks = ref.watch(openTasksProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Open tasks'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(openTasksProvider(widget.profileId));
          await ref.read(openTasksProvider(widget.profileId).future);
        },
        child: asyncTasks.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(
                child: Text(
                  'Failed to load open tasks',
                  style: tt.bodyLarge?.copyWith(color: cs.error),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () =>
                      ref.invalidate(openTasksProvider(widget.profileId)),
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
          data: (tasks) {
            if (tasks.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 160),
                  Center(
                    child: Text(
                      'No open tasks',
                      style: tt.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              );
            }

            final sorted = _sortByDueAsc(tasks);
            final now = DateTime.now();

            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: sorted.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final task = sorted[index];
                final due = _parseDue(task.dueAt);
                final isOverdue = due != null && due.isBefore(now);
                final isSelected = _selected.contains(task.id);

                final titleColor = isOverdue ? cs.error : cs.onSurface;
                final subtitleColor =
                    isOverdue ? cs.error : cs.onSurfaceVariant;

                final dueLabel = due == null
                    ? null
                    : DateFormat.yMMMd().add_Hm().format(due);

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  color: isSelected
                      ? cs.secondaryContainer
                      : cs.surfaceContainerHighest,
                  child: ListTile(
                    onTap: () => _toggleSelection(task.id),
                    onLongPress: () => _showDetail(task),
                    leading: Icon(
                      isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: isSelected ? cs.primary : cs.outline,
                    ),
                    title: Text(
                      task.title,
                      style: tt.bodyLarge?.copyWith(
                        color: titleColor,
                        fontWeight:
                            isOverdue ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    subtitle: dueLabel == null
                        ? null
                        : Text(
                            isOverdue
                                ? 'Overdue — $dueLabel'
                                : 'Due $dueLabel',
                            style: tt.bodySmall?.copyWith(
                              color: subtitleColor,
                            ),
                          ),
                    trailing: _PriorityBadge(priority: task.priority),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Small colored badge that displays a task's priority.
///
/// Falls back to a neutral surface tint when no priority is set.
class _PriorityBadge extends StatelessWidget {
  final String? priority;

  const _PriorityBadge({required this.priority});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final p = (priority ?? '').toLowerCase().trim();
    if (p.isEmpty) {
      return const SizedBox.shrink();
    }

    Color bg;
    Color fg;
    switch (p) {
      case 'high':
      case 'urgent':
      case 'critical':
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
        break;
      case 'medium':
      case 'normal':
        bg = cs.tertiaryContainer;
        fg = cs.onTertiaryContainer;
        break;
      case 'low':
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        break;
      default:
        bg = cs.surfaceContainerHigh;
        fg = cs.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        priority!,
        style: tt.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
