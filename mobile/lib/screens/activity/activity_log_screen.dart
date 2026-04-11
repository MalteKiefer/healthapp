import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_error_messages.dart';
import '../../models/activity_entry.dart';
import '../../providers/activity_log_provider.dart';
import '../../providers/providers.dart';

/// Activity Log screen.
///
/// Shows a chronological feed (newest first) of all create/update/delete
/// events that occurred across health domains for the currently selected
/// profile. Entries are visually grouped by date bucket:
///
///   * Today
///   * Yesterday
///   * This week (anything within the last 7 days that isn't Today/Yesterday)
///   * Earlier
///
/// Each row uses a domain-specific icon (medication = pill, vital = heart,
/// lab = flask, ...) and renders an English action verb plus a short
/// human-readable description of the changed entity.
class ActivityLogScreen extends ConsumerWidget {
  const ActivityLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final profile = ref.watch(selectedProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Activity Log')),
      body: profile == null
          ? Center(
              child: Text(
                'No profile selected',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            )
          : _ActivityList(profileId: profile.id),
    );
  }
}

// ── List ───────────────────────────────────────────────────────────────────

class _ActivityList extends ConsumerWidget {
  final String profileId;
  const _ActivityList({required this.profileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final async = ref.watch(activityLogProvider(profileId));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(activityLogProvider(profileId));
        await ref.read(activityLogProvider(profileId).future);
      },
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: colors.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      apiErrorMessage(err),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurface),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () =>
                          ref.invalidate(activityLogProvider(profileId)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 160),
                Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.history,
                        size: 48,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No activity recorded',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return _GroupedList(entries: entries);
        },
      ),
    );
  }
}

// ── Grouping ───────────────────────────────────────────────────────────────

enum _Bucket { today, yesterday, thisWeek, earlier }

String _bucketLabel(_Bucket b) {
  switch (b) {
    case _Bucket.today:
      return 'Today';
    case _Bucket.yesterday:
      return 'Yesterday';
    case _Bucket.thisWeek:
      return 'This week';
    case _Bucket.earlier:
      return 'Earlier';
  }
}

_Bucket _bucketFor(DateTime when, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final entryDay = DateTime(when.year, when.month, when.day);
  final diff = today.difference(entryDay).inDays;
  if (diff <= 0) return _Bucket.today;
  if (diff == 1) return _Bucket.yesterday;
  if (diff < 7) return _Bucket.thisWeek;
  return _Bucket.earlier;
}

class _GroupedList extends StatelessWidget {
  final List<ActivityEntry> entries;
  const _GroupedList({required this.entries});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();

    // Build interleaved list of header + tile widgets, preserving the
    // newest-first order from the provider.
    final children = <Widget>[];
    _Bucket? currentBucket;
    for (final entry in entries) {
      final bucket = _bucketFor(entry.createdAt, now);
      if (bucket != currentBucket) {
        currentBucket = bucket;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              _bucketLabel(bucket),
              style: text.labelLarge?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }
      children.add(_ActivityTile(entry: entry));
      children.add(
        Divider(height: 1, color: colors.outlineVariant),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }
}

// ── Row ────────────────────────────────────────────────────────────────────

class _ActivityTile extends StatelessWidget {
  final ActivityEntry entry;
  const _ActivityTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final timeFmt = DateFormat.jm();

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.onPrimaryContainer,
        child: Icon(_iconFor(entry.entityType), size: 20),
      ),
      title: Text(
        '${_actionVerb(entry.action)} ${_entityLabel(entry.entityType)}',
        style: text.titleSmall?.copyWith(
          color: colors.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: entry.details != null && entry.details!.isNotEmpty
          ? Text(
              entry.details!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.onSurfaceVariant),
            )
          : null,
      trailing: Text(
        timeFmt.format(entry.createdAt),
        style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      ),
    );
  }
}

// ── Mappings ───────────────────────────────────────────────────────────────

/// Maps a backend `entity` / `entity_type` value to a Material icon.
///
/// Falls back to a generic history icon for unknown entity types so the row
/// never renders blank.
IconData _iconFor(String entity) {
  switch (entity.toLowerCase()) {
    case 'medication':
    case 'medications':
    case 'medication_intake':
      return Icons.medication;
    case 'vital':
    case 'vitals':
      return Icons.favorite;
    case 'lab':
    case 'labs':
    case 'lab_result':
      return Icons.science;
    case 'allergy':
    case 'allergies':
      return Icons.warning_amber;
    case 'diagnosis':
    case 'diagnoses':
      return Icons.local_hospital;
    case 'vaccination':
    case 'vaccinations':
      return Icons.vaccines;
    case 'appointment':
    case 'appointments':
      return Icons.event;
    case 'document':
    case 'documents':
      return Icons.description;
    case 'contact':
    case 'contacts':
      return Icons.contact_phone;
    case 'symptom':
    case 'symptoms':
      return Icons.healing;
    case 'diary':
    case 'diary_entry':
      return Icons.book;
    case 'task':
    case 'tasks':
      return Icons.check_circle_outline;
    case 'profile':
    case 'profiles':
      return Icons.person;
    default:
      return Icons.history;
  }
}

/// Maps a backend `action` to a short English verb.
String _actionVerb(String action) {
  switch (action.toLowerCase()) {
    case 'create':
    case 'created':
    case 'add':
    case 'added':
    case 'insert':
      return 'Added';
    case 'update':
    case 'updated':
    case 'edit':
    case 'edited':
    case 'modify':
      return 'Updated';
    case 'delete':
    case 'deleted':
    case 'remove':
    case 'removed':
      return 'Deleted';
    case 'view':
    case 'viewed':
    case 'read':
      return 'Viewed';
    case 'export':
    case 'exported':
      return 'Exported';
    case 'import':
    case 'imported':
      return 'Imported';
    default:
      return action.isEmpty
          ? 'Changed'
          : action[0].toUpperCase() + action.substring(1);
  }
}

/// Maps a backend entity key to a singular English noun for the row title.
String _entityLabel(String entity) {
  switch (entity.toLowerCase()) {
    case 'medication':
    case 'medications':
      return 'medication';
    case 'medication_intake':
      return 'medication intake';
    case 'vital':
    case 'vitals':
      return 'vital';
    case 'lab':
    case 'labs':
    case 'lab_result':
      return 'lab result';
    case 'allergy':
    case 'allergies':
      return 'allergy';
    case 'diagnosis':
    case 'diagnoses':
      return 'diagnosis';
    case 'vaccination':
    case 'vaccinations':
      return 'vaccination';
    case 'appointment':
    case 'appointments':
      return 'appointment';
    case 'document':
    case 'documents':
      return 'document';
    case 'contact':
    case 'contacts':
      return 'contact';
    case 'symptom':
    case 'symptoms':
      return 'symptom';
    case 'diary':
    case 'diary_entry':
      return 'diary entry';
    case 'task':
    case 'tasks':
      return 'task';
    case 'profile':
    case 'profiles':
      return 'profile';
    default:
      return entity.isEmpty ? 'entry' : entity.replaceAll('_', ' ');
  }
}
