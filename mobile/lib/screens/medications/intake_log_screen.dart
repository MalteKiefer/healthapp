import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../models/medication.dart';
import '../../models/medication_intake.dart';
import '../../providers/medication_intake_provider.dart';
import '../../widgets/skeletons.dart';

String _trOr(String key, String fallback) {
  final v = T.tr(key);
  return v == key ? fallback : v;
}

/// Displays a medication's intake history and lets the user log a new
/// intake, edit an existing one, or delete entries.
class IntakeLogScreen extends ConsumerStatefulWidget {
  final String profileId;
  final Medication medication;

  const IntakeLogScreen({
    super.key,
    required this.profileId,
    required this.medication,
  });

  @override
  ConsumerState<IntakeLogScreen> createState() => _IntakeLogScreenState();
}

class _IntakeLogScreenState extends ConsumerState<IntakeLogScreen> {
  MedicationIntakeKey get _key =>
      MedicationIntakeKey(widget.profileId, widget.medication.id);

  String get _defaultDose {
    final d = widget.medication.dosage;
    final u = widget.medication.unit;
    if (d == null || d.isEmpty) return '';
    if (u == null || u.isEmpty) return d;
    return '$d $u';
  }

  Future<void> _logNow() async {
    final controller = ref.read(medicationIntakeControllerProvider.notifier);
    final ok = await controller.logIntake(
      profileId: widget.profileId,
      medicationId: widget.medication.id,
      takenAt: DateTime.now(),
      doseTaken: _defaultDose.isEmpty ? null : _defaultDose,
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Intake logged')),
      );
    } else {
      final err = ref.read(medicationIntakeControllerProvider).error;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to log intake: $err')),
      );
    }
  }

  Future<void> _editIntake(MedicationIntake intake) async {
    final doseCtrl = TextEditingController(text: intake.doseTaken ?? '');
    final notesCtrl = TextEditingController(text: intake.notes ?? '');
    DateTime taken = DateTime.tryParse(intake.takenAt ?? '')?.toLocal() ??
        DateTime.now();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Edit intake'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Taken at'),
                      subtitle: Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(taken),
                      ),
                      trailing: const Icon(Icons.edit_calendar),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: ctx,
                          initialDate: taken,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now()
                              .add(const Duration(days: 1)),
                        );
                        if (date == null) return;
                        if (!ctx.mounted) return;
                        final time = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.fromDateTime(taken),
                        );
                        if (time == null) return;
                        setLocal(() {
                          taken = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                        });
                      },
                    ),
                    TextField(
                      controller: doseCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Dose taken'),
                    ),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(labelText: 'Notes'),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) return;

    final controller = ref.read(medicationIntakeControllerProvider.notifier);
    final ok = await controller.updateIntake(
      profileId: widget.profileId,
      medicationId: widget.medication.id,
      intakeId: intake.id,
      takenAt: taken,
      doseTaken: doseCtrl.text.trim(),
      notes: notesCtrl.text.trim(),
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      messenger.showSnackBar(const SnackBar(content: Text('Intake updated')));
    } else {
      final err = ref.read(medicationIntakeControllerProvider).error;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update intake: $err')),
      );
    }
  }

  Future<void> _deleteIntake(MedicationIntake intake) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete intake?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final controller = ref.read(medicationIntakeControllerProvider.notifier);
    final ok = await controller.deleteIntake(
      profileId: widget.profileId,
      medicationId: widget.medication.id,
      intakeId: intake.id,
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      messenger.showSnackBar(const SnackBar(content: Text('Intake deleted')));
    } else {
      final err = ref.read(medicationIntakeControllerProvider).error;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to delete intake: $err')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final intakesAsync = ref.watch(medicationIntakeListProvider(_key));
    final mutation = ref.watch(medicationIntakeControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_trOr('meds.intake.title', 'Intake log')} — ${widget.medication.name}',
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: mutation.loading ? null : _logNow,
        icon: const Icon(Icons.check_circle_outline),
        label: Text(_trOr('meds.intake.log_now', 'Log intake now')),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(medicationIntakeListProvider(_key));
          await ref.read(medicationIntakeListProvider(_key).future);
        },
        child: intakesAsync.when(
          loading: () => const SkeletonList(count: 5),
          error: (e, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'Failed to load intakes: $e',
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ],
          ),
          data: (intakes) {
            if (intakes.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Icon(
                      Icons.medication_outlined,
                      size: 64,
                      color: scheme.outline,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Text(
                      'No intakes logged yet',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: Text(
                      'Tap "${_trOr('meds.intake.log_now', 'Log intake now')}" to record your first dose',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              );
            }
            final sorted = [...intakes];
            sorted.sort((a, b) {
              final ta = a.takenAt ?? a.scheduledAt ?? '';
              final tb = b.takenAt ?? b.scheduledAt ?? '';
              return tb.compareTo(ta);
            });
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm + AppSpacing.xs,
                AppSpacing.sm + AppSpacing.xs,
                AppSpacing.sm + AppSpacing.xs,
                AppSpacing.xxl + AppSpacing.xxl,
              ),
              itemCount: sorted.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (ctx, i) {
                final it = sorted[i];
                final when = it.takenAt ?? it.scheduledAt;
                final parsed = when == null ? null : DateTime.tryParse(when);
                final label = parsed == null
                    ? (when ?? '—')
                    : DateFormat('EEE, MMM d yyyy • HH:mm')
                        .format(parsed.toLocal());
                return Card(
                  color: scheme.surfaceContainerHighest,
                  child: ListTile(
                    leading: Icon(
                      Icons.check_circle,
                      color: scheme.primary,
                    ),
                    title: Text(label),
                    subtitle: Text(
                      [
                        if (it.doseTaken != null && it.doseTaken!.isNotEmpty)
                          it.doseTaken!,
                        if (it.notes != null && it.notes!.isNotEmpty)
                          it.notes!,
                      ].join(' • '),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit',
                          onPressed: () => _editIntake(it),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: scheme.error,
                          ),
                          tooltip: 'Delete',
                          onPressed: () => _deleteIntake(it),
                        ),
                      ],
                    ),
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
