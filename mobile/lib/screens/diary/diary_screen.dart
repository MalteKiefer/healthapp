import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/common.dart';
import '../../providers/providers.dart';

// -- Provider -----------------------------------------------------------------

final _diaryProvider =
    FutureProvider.family<List<DiaryEvent>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final data = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/diary');
  return (data['items'] as List)
      .map((e) => DiaryEvent.fromJson(e as Map<String, dynamic>))
      .toList();
});

// -- Screen -------------------------------------------------------------------

class DiaryScreen extends ConsumerStatefulWidget {
  final String profileId;
  const DiaryScreen({super.key, required this.profileId});

  @override
  ConsumerState<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends ConsumerState<DiaryScreen> {
  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry'),
        content: const Text('This diary entry will be permanently removed.'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(apiClientProvider)
          .delete('/api/v1/profiles/${widget.profileId}/diary/$id');
      ref.invalidate(_diaryProvider(widget.profileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showAddSheet() async {
    final contentCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String mood = 'neutral';
    int moodScore = 5;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.45,
        maxChildSize: 0.9,
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
                  Text('Add Diary Entry',
                      style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    value: mood,
                    decoration: const InputDecoration(labelText: 'Mood'),
                    items: const [
                      DropdownMenuItem(
                          value: 'great', child: Text('Great')),
                      DropdownMenuItem(value: 'good', child: Text('Good')),
                      DropdownMenuItem(
                          value: 'neutral', child: Text('Neutral')),
                      DropdownMenuItem(value: 'bad', child: Text('Bad')),
                      DropdownMenuItem(
                          value: 'terrible', child: Text('Terrible')),
                    ],
                    onChanged: (v) {
                      if (v != null) setSheetState(() => mood = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Mood Score: $moodScore',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleSmall
                        ?.copyWith(
                            color:
                                Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                  Slider(
                    value: moodScore.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: moodScore.toString(),
                    onChanged: (v) =>
                        setSheetState(() => moodScore = v.round()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: contentCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final body = <String, dynamic>{
                        'recorded_at':
                            DateTime.now().toUtc().toIso8601String(),
                        'mood': mood,
                        'mood_score': moodScore,
                        if (contentCtrl.text.trim().isNotEmpty)
                          'content': contentCtrl.text.trim(),
                      };
                      try {
                        await ref.read(apiClientProvider).post<void>(
                              '/api/v1/profiles/${widget.profileId}/diary',
                              body: body,
                            );
                        ref.invalidate(
                            _diaryProvider(widget.profileId));
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                    child: const Text('Add Entry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    contentCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final asyncVal = ref.watch(_diaryProvider(widget.profileId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diary'),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        tooltip: 'Add entry',
        child: const Icon(Icons.add),
      ),
      body: asyncVal.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text('Failed to load diary', style: tt.bodyLarge),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () =>
                  ref.invalidate(_diaryProvider(widget.profileId)),
              child: const Text('Retry'),
            ),
          ]),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.book_outlined, size: 48, color: cs.outline),
                const SizedBox(height: 12),
                Text('No diary entries yet',
                    style:
                        tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            );
          }

          // Sort newest first
          final sorted = [...items]
            ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

          // Group by date for timeline headers
          final groups = <String, List<DiaryEvent>>{};
          for (final entry in sorted) {
            String dateKey;
            try {
              final d = DateTime.parse(entry.recordedAt);
              dateKey = DateFormat('MMM d, yyyy').format(d);
            } catch (_) {
              dateKey = 'Unknown';
            }
            groups.putIfAbsent(dateKey, () => []).add(entry);
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
            itemCount: groups.length,
            itemBuilder: (_, i) {
              final dateKey = groups.keys.elementAt(i);
              final entries = groups[dateKey]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      dateKey,
                      style: tt.titleSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  ...entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DiaryCard(
                          entry: e,
                          onDelete: () => _delete(e.id),
                        ),
                      )),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// -- Card ---------------------------------------------------------------------

class _DiaryCard extends StatelessWidget {
  final DiaryEvent entry;
  final VoidCallback onDelete;
  const _DiaryCard({required this.entry, required this.onDelete});

  Color _moodColor(int? score, ColorScheme cs) {
    if (score == null) return cs.primary;
    if (score >= 8) return Colors.green;
    if (score >= 6) return cs.primary;
    if (score >= 4) return cs.tertiary;
    return cs.error;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final moodColor = _moodColor(entry.moodScore, cs);

    String? timeStr;
    try {
      final d = DateTime.parse(entry.recordedAt);
      timeStr = DateFormat('HH:mm').format(d.toLocal());
    } catch (_) {}

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.book,
                        size: 20, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.mood ?? 'Entry',
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (timeStr != null)
                          Text(
                            timeStr,
                            style: tt.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  if (entry.moodScore != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: moodColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${entry.moodScore}/10',
                        style: TextStyle(
                          fontSize: 10,
                          color: moodColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              if (entry.moodScore != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: entry.moodScore! / 10.0,
                    minHeight: 6,
                    backgroundColor: cs.surfaceContainerHighest,
                    color: moodColor,
                  ),
                ),
              ],
              if (entry.content != null) ...[
                const SizedBox(height: 8),
                Text(
                  entry.content!,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
