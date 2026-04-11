import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/spacing.dart';
import '../../models/common.dart';
import '../../providers/appointment_extras_provider.dart';
import '../../widgets/skeletons.dart';

/// Lists a profile's upcoming appointments and allows marking them complete.
class UpcomingAppointmentsScreen extends ConsumerWidget {
  final String profileId;

  const UpcomingAppointmentsScreen({
    super.key,
    required this.profileId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcomingAsync = ref.watch(upcomingAppointmentsProvider(profileId));
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('Upcoming Appointments'),
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(upcomingAppointmentsProvider(profileId));
          await ref.read(upcomingAppointmentsProvider(profileId).future);
        },
        child: upcomingAsync.when(
          loading: () => const SkeletonList(count: 5),
          error: (e, _) => _ErrorView(
            message: e.toString(),
            onRetry: () =>
                ref.invalidate(upcomingAppointmentsProvider(profileId)),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const _EmptyState();
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
              itemBuilder: (context, index) {
                final appt = items[index];
                return _UpcomingAppointmentTile(
                  profileId: profileId,
                  appointment: appt,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _UpcomingAppointmentTile extends ConsumerWidget {
  final String profileId;
  final Appointment appointment;

  const _UpcomingAppointmentTile({
    required this.profileId,
    required this.appointment,
  });

  String _formatScheduledAt(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('EEE, MMM d, y  HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }

  Future<void> _handleComplete(BuildContext context, WidgetRef ref) async {
    final notes = await _promptForNotes(context);
    // User dismissed the sheet (null) -> cancel; empty string means "no notes".
    if (notes == null) return;

    final controller =
        ref.read(appointmentCompletionControllerProvider.notifier);
    final success = await controller.complete(
      profileId,
      appointment.id,
      notes: notes.isEmpty ? null : notes,
    );

    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (success) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Appointment marked as complete')),
      );
    } else {
      final error =
          ref.read(appointmentCompletionControllerProvider).error ??
              'Unknown error';
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to complete: $error')),
      );
    }
  }

  Future<String?> _promptForNotes(BuildContext context) {
    final controller = TextEditingController();
    return showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md + bottomInset,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Complete appointment',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      color: colors.onSurface,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Add optional notes about this visit.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: controller,
                maxLines: 4,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Notes (optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Mark complete'),
                    onPressed: () =>
                        Navigator.of(ctx).pop(controller.text.trim()),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final completionState = ref.watch(appointmentCompletionControllerProvider);
    final isThisLoading = completionState.isLoading;

    return Card(
      elevation: 0,
      color: colors.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event, color: colors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    appointment.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(Icons.schedule,
                    size: 16, color: colors.onSurfaceVariant),
                const SizedBox(width: AppSpacing.xs + 2),
                Expanded(
                  child: Text(
                    _formatScheduledAt(appointment.scheduledAt),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
            if ((appointment.location ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Icon(Icons.place,
                      size: 16, color: colors.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.xs + 2),
                  Expanded(
                    child: Text(
                      appointment.location!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                icon: isThisLoading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onSecondaryContainer,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: const Text('Mark complete'),
                onPressed: isThisLoading
                    ? null
                    : () => _handleComplete(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: AppSpacing.xxl * 2),
        Icon(
          Icons.event_available,
          size: 72,
          color: colors.onSurfaceVariant,
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Text(
            'No upcoming appointments',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.onSurface,
                ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Text(
            'You are all caught up.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SizedBox(height: AppSpacing.xxl * 2),
        Icon(Icons.error_outline, size: 64, color: colors.error),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Text(
            'Failed to load appointments',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.onSurface,
                ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}
