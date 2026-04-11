import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../models/export_schedule.dart';
import '../../providers/export_schedules_provider.dart';
import '../../providers/providers.dart';
import '../../widgets/skeletons.dart';

/// `T.tr` returns the key itself when no entry is found, so we use that
/// to fall back to a hard-coded English string when a translation is missing.
String _trOr(String key, String fallback) {
  final v = T.tr(key);
  return v == key ? fallback : v;
}

/// Screen listing every persisted export schedule, with a + action to
/// create a new one and a swipe / trash icon to delete an existing row.
class ExportSchedulesScreen extends ConsumerWidget {
  const ExportSchedulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final asyncList = ref.watch(exportSchedulesProvider);
    final mutation = ref.watch(exportSchedulesControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_trOr('export.schedules', 'Export schedules')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: mutation.busy
            ? null
            : () => _openCreateSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New schedule'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(exportSchedulesProvider);
          await ref.read(exportSchedulesProvider.future);
        },
        child: asyncList.when(
          loading: () => const SkeletonList(count: 3),
          error: (err, _) => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const SizedBox(height: 80),
              Icon(Icons.error_outline, size: 48, color: colors.error),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
              Center(
                child: Text(
                  'Failed to load schedules',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Text(
                  err.toString(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: FilledButton.tonal(
                  onPressed: () => ref.invalidate(exportSchedulesProvider),
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
          data: (schedules) {
            if (schedules.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  Icon(Icons.schedule, size: 64, color: colors.outline),
                  const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                  Center(
                    child: Text(
                      'No schedules yet',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Center(
                    child: Text(
                      'Tap the + button to create one.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.outline),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: schedules.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: colors.outlineVariant),
              itemBuilder: (ctx, i) =>
                  _ScheduleTile(schedule: schedules[i]),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openCreateSheet(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(selectedProfileProvider);
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a profile first.')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _CreateScheduleSheet(profileId: profile.id),
    );
  }
}

// -- Tile ---------------------------------------------------------------------

class _ScheduleTile extends ConsumerWidget {
  final ExportSchedule schedule;
  const _ScheduleTile({required this.schedule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.onPrimaryContainer,
        child: Icon(_iconFor(schedule.format)),
      ),
      title: Text(
        ExportFormats.label(schedule.format),
        style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'cron: ${schedule.cron}',
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (schedule.destination.isNotEmpty)
            Text(
              schedule.destination,
              style: text.bodySmall?.copyWith(color: colors.outline),
            ),
        ],
      ),
      trailing: IconButton(
        tooltip: 'Delete',
        icon: Icon(Icons.delete_outline, color: colors.error),
        onPressed: () => _confirmDelete(context, ref),
      ),
    );
  }

  IconData _iconFor(String format) {
    switch (format) {
      case ExportFormats.fhir:
        return Icons.local_hospital_outlined;
      case ExportFormats.pdf:
        return Icons.picture_as_pdf_outlined;
      case ExportFormats.ics:
        return Icons.event_outlined;
      default:
        return Icons.archive_outlined;
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete schedule?'),
        content: Text(
          'This will permanently delete the ${ExportFormats.label(schedule.format)} schedule.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final success = await ref
        .read(exportSchedulesControllerProvider.notifier)
        .delete(schedule.id);
    if (!context.mounted) return;
    if (!success) {
      final err = ref.read(exportSchedulesControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err ?? 'Failed to delete schedule.')),
      );
    }
  }
}

// -- Create sheet -------------------------------------------------------------

class _CreateScheduleSheet extends ConsumerStatefulWidget {
  final String profileId;
  const _CreateScheduleSheet({required this.profileId});

  @override
  ConsumerState<_CreateScheduleSheet> createState() =>
      _CreateScheduleSheetState();
}

class _CreateScheduleSheetState extends ConsumerState<_CreateScheduleSheet> {
  String _format = ExportFormats.fhir;
  String _selectedPreset = CronPresets.presets.keys.first;
  bool _customCron = false;
  final TextEditingController _cronController = TextEditingController(
    text: CronPresets.presets.values.first,
  );
  final TextEditingController _destinationController = TextEditingController(
    text: 'local',
  );

  @override
  void dispose() {
    _cronController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mutation = ref.watch(exportSchedulesControllerProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg - AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.lg - AppSpacing.xs,
        (AppSpacing.lg - AppSpacing.xs) + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'New export schedule',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Format', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: ExportFormats.fhir,
                  label: Text('FHIR'),
                  icon: Icon(Icons.local_hospital_outlined),
                ),
                ButtonSegment(
                  value: ExportFormats.pdf,
                  label: Text('PDF'),
                  icon: Icon(Icons.picture_as_pdf_outlined),
                ),
                ButtonSegment(
                  value: ExportFormats.ics,
                  label: Text('ICS'),
                  icon: Icon(Icons.event_outlined),
                ),
              ],
              selected: {_format},
              onSelectionChanged: (s) => setState(() => _format = s.first),
            ),
            const SizedBox(height: AppSpacing.lg - AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Schedule',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      'Custom',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    Switch(
                      value: _customCron,
                      onChanged: (v) => setState(() => _customCron = v),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_customCron)
              TextField(
                controller: _cronController,
                decoration: const InputDecoration(
                  labelText: 'Cron expression',
                  hintText: '0 8 * * 1',
                  border: OutlineInputBorder(),
                ),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _selectedPreset,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Preset',
                  border: OutlineInputBorder(),
                ),
                items: CronPresets.presets.entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.key),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _selectedPreset = v;
                    _cronController.text = CronPresets.presets[v] ?? '';
                  });
                },
              ),
            const SizedBox(height: AppSpacing.lg - AppSpacing.xs),
            Text('Destination', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _destinationController,
              decoration: const InputDecoration(
                labelText: 'Destination',
                hintText: 'local | email:user@example.com',
                border: OutlineInputBorder(),
              ),
            ),
            if (mutation.error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                mutation.error!,
                style: TextStyle(color: colors.error),
              ),
            ],
            const SizedBox(height: AppSpacing.lg - AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: mutation.busy
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: mutation.busy ? null : _submit,
                  icon: mutation.busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Create'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final cron = _customCron
        ? _cronController.text.trim()
        : (CronPresets.presets[_selectedPreset] ?? '').trim();
    if (cron.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cron expression is required.')),
      );
      return;
    }
    final dest = _destinationController.text.trim();
    if (dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Destination is required.')),
      );
      return;
    }
    final ok = await ref
        .read(exportSchedulesControllerProvider.notifier)
        .create(
          profileId: widget.profileId,
          format: _format,
          cron: cron,
          destination: dest,
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Schedule created.')),
      );
    }
  }
}
