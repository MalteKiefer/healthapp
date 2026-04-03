import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/i18n/translations.dart';
import '../../models/common.dart';
import '../../providers/providers.dart';

// -- Provider -----------------------------------------------------------------

final _tasksProvider =
    FutureProvider.family<List<Task>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final data = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/tasks');
  return (data['items'] as List)
      .map((e) => Task.fromJson(e as Map<String, dynamic>))
      .toList();
});

// -- Screen -------------------------------------------------------------------

class TasksScreen extends ConsumerStatefulWidget {
  final String profileId;
  const TasksScreen({super.key, required this.profileId});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  bool _openOnly = true;

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(T.tr('tasks.delete')),
        content: Text(T.tr('tasks.delete_body')),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(T.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(T.tr('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(apiClientProvider)
          .delete('/api/v1/profiles/${widget.profileId}/tasks/$id');
      ref.invalidate(_tasksProvider(widget.profileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _toggleCompletion(Task task) async {
    try {
      await ref.read(apiClientProvider).patch<void>(
            '/api/v1/profiles/${widget.profileId}/tasks/${task.id}',
            body: {'completed': !task.completed},
          );
      ref.invalidate(_tasksProvider(widget.profileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showFormSheet({Task? existing}) async {
    final api = ref.read(apiClientProvider);
    final isEdit = existing != null;
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final dueDateCtrl = TextEditingController(
        text: isEdit && existing.dueAt != null
            ? (existing.dueAt!.length >= 10
                ? existing.dueAt!.substring(0, 10)
                : existing.dueAt!)
            : '');
    final notesCtrl =
        TextEditingController(text: existing?.description ?? '');
    final formKey = GlobalKey<FormState>();
    String priority = existing?.priority ?? 'medium';
    String? status = existing?.status;

    const statuses = ['open', 'in_progress', 'completed', 'cancelled'];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) => StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Form(
              key: formKey,
              child: ListView(
                controller: scrollCtrl,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    isEdit ? T.tr('tasks.edit') : T.tr('tasks.add'),
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: titleCtrl,
                    decoration: InputDecoration(labelText: T.tr('field.title_required')),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? T.tr('common.required') : null,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: dueDateCtrl,
                    decoration: InputDecoration(
                      labelText: T.tr('field.due_date'),
                      hintText: 'YYYY-MM-DD',
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    readOnly: true,
                    onTap: () async {
                      final initDate = dueDateCtrl.text.isNotEmpty
                          ? (DateTime.tryParse(dueDateCtrl.text) ??
                              DateTime.now())
                          : DateTime.now();
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: initDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        dueDateCtrl.text =
                            DateFormat('yyyy-MM-dd').format(picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: priority,
                    decoration: InputDecoration(labelText: T.tr('field.priority')),
                    items: [
                      DropdownMenuItem(
                          value: 'low', child: Text(T.tr('priority.low'))),
                      DropdownMenuItem(
                          value: 'medium',
                          child: Text(T.tr('priority.medium'))),
                      DropdownMenuItem(
                          value: 'high',
                          child: Text(T.tr('priority.high'))),
                    ],
                    onChanged: (v) {
                      if (v != null) setSheetState(() => priority = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: statuses.contains(status) ? status : null,
                    decoration: InputDecoration(
                        labelText: T.tr('tasks.status')),
                    items: statuses
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(T.tr('tasks.status_$s')),
                            ))
                        .toList(),
                    onChanged: (v) => setSheetState(() => status = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                        labelText: T.tr('common.notes')),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.pop(ctx);
                      final body = <String, dynamic>{
                        'title': titleCtrl.text.trim(),
                        'priority': priority,
                        if (status != null) 'status': status,
                        if (dueDateCtrl.text.trim().isNotEmpty)
                          'due_at':
                              '${dueDateCtrl.text.trim()}T00:00:00.000Z',
                        if (notesCtrl.text.trim().isNotEmpty)
                          'description': notesCtrl.text.trim(),
                      };
                      try {
                        if (isEdit) {
                          await api.patch<void>(
                            '/api/v1/profiles/${widget.profileId}/tasks/${existing.id}',
                            body: body,
                          );
                        } else {
                          await api.post<void>(
                            '/api/v1/profiles/${widget.profileId}/tasks',
                            body: body,
                          );
                        }
                        ref.invalidate(
                            _tasksProvider(widget.profileId));
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                    child: Text(T.tr('common.save')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    titleCtrl.dispose();
    dueDateCtrl.dispose();
    notesCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final asyncVal = ref.watch(_tasksProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(
        title: Text(T.tr('tasks.title')),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormSheet(),
        tooltip: T.tr('tasks.add'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text(T.tr('status.open')),
                  selected: _openOnly,
                  onSelected: (_) => setState(() => _openOnly = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(T.tr('status.completed')),
                  selected: !_openOnly,
                  onSelected: (_) => setState(() => _openOnly = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: asyncVal.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline, size: 48, color: cs.error),
                  const SizedBox(height: 12),
                  Text(T.tr('tasks.failed'), style: tt.bodyLarge),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () =>
                        ref.invalidate(_tasksProvider(widget.profileId)),
                    child: Text(T.tr('common.retry')),
                  ),
                ]),
              ),
              data: (items) {
                final list = _openOnly
                    ? items.where((t) => !t.completed).toList()
                    : items.where((t) => t.completed).toList();
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.task_alt_outlined,
                              size: 48, color: cs.outline),
                          const SizedBox(height: 12),
                          Text(
                            _openOnly
                                ? T.tr('tasks.no_open')
                                : T.tr('tasks.no_completed'),
                            style: tt.bodyLarge
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ]),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _TaskCard(
                    task: list[i],
                    onDelete: () => _delete(list[i].id),
                    onToggle: () => _toggleCompletion(list[i]),
                    onEdit: () => _showFormSheet(existing: list[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// -- Card ---------------------------------------------------------------------

class _TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onDelete;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  const _TaskCard({
    required this.task,
    required this.onDelete,
    required this.onToggle,
    required this.onEdit,
  });

  Color _priorityColor(String? priority, ColorScheme cs) {
    switch (priority?.toLowerCase()) {
      case 'high':
        return cs.error;
      case 'medium':
        return cs.tertiary;
      default:
        return cs.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final priColor = _priorityColor(task.priority, cs);

    String? dueStr;
    bool isOverdue = false;
    if (task.dueAt != null) {
      try {
        final d = DateTime.parse(task.dueAt!);
        dueStr = DateFormat('MMM d, yyyy').format(d);
        isOverdue = d.isBefore(DateTime.now()) && !task.completed;
      } catch (_) {
        dueStr = task.dueAt;
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onLongPress: onDelete,
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Checkbox(
                value: task.completed,
                onChanged: (_) => onToggle(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              decoration: task.completed
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        if (task.priority != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: priColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              T.tr('priority.${task.priority}'),
                              style: TextStyle(
                                fontSize: 10,
                                color: priColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (dueStr != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${T.tr('field.due_date')}: $dueStr',
                        style: tt.bodySmall?.copyWith(
                          color: isOverdue ? cs.error : cs.onSurfaceVariant,
                          fontWeight:
                              isOverdue ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                    if (task.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        task.description!,
                        style: tt.bodySmall?.copyWith(color: cs.outline),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
