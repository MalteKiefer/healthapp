import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../models/common.dart';
import '../../providers/vaccination_due_provider.dart';
import '../../widgets/skeletons.dart';

/// Shows vaccinations that are overdue or coming due soon.
///
/// Three sections:
///   * Overdue        — `next_due_at` is in the past (red badge).
///   * Due this month — due within the current calendar month (orange).
///   * Due later      — due after the current month (neutral).
class VaccinationDueScreen extends ConsumerWidget {
  final String profileId;

  const VaccinationDueScreen({super.key, required this.profileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncVal = ref.watch(vaccinationDueProvider(profileId));
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upcoming Vaccinations'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(vaccinationDueProvider(profileId));
          await ref.read(vaccinationDueProvider(profileId).future);
        },
        child: asyncVal.when(
          loading: () => const SkeletonList(count: 4),
          error: (err, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 120),
              Center(
                child: Column(
                  children: [
                    Icon(Icons.error_outline, color: cs.error, size: 40),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      T.tr('vaccinations.failed'),
                      style: tt.bodyLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: () => ref
                          .invalidate(vaccinationDueProvider(profileId)),
                      child: Text(T.tr('common.retry')),
                    ),
                  ],
                ),
              ),
            ],
          ),
          data: (items) {
            final now = DateTime.now();
            final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

            final overdue = <_DueEntry>[];
            final dueThisMonth = <_DueEntry>[];
            final dueLater = <_DueEntry>[];

            for (final v in items) {
              final due = _tryParse(v.nextDueAt);
              if (due == null) continue;
              final entry = _DueEntry(v, due);
              if (due.isBefore(now)) {
                overdue.add(entry);
              } else if (!due.isAfter(monthEnd)) {
                dueThisMonth.add(entry);
              } else {
                dueLater.add(entry);
              }
            }

            overdue.sort((a, b) => a.due.compareTo(b.due));
            dueThisMonth.sort((a, b) => a.due.compareTo(b.due));
            dueLater.sort((a, b) => a.due.compareTo(b.due));

            if (overdue.isEmpty &&
                dueThisMonth.isEmpty &&
                dueLater.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.verified,
                            color: cs.tertiary, size: 48),
                        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                        Text(
                          T.tr('vaccinations.no_data'),
                          style: tt.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          "You're all caught up.",
                          style: tt.bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                if (overdue.isNotEmpty) ...[
                  _SectionHeader(
                    label: T.tr('status.overdue'),
                    color: cs.error,
                    count: overdue.length,
                  ),
                  for (final e in overdue)
                    _DueTile(
                      entry: e,
                      badgeColor: cs.error,
                      badgeOnColor: cs.onError,
                      now: now,
                    ),
                ],
                if (dueThisMonth.isNotEmpty) ...[
                  _SectionHeader(
                    label: T.tr('status.upcoming'),
                    color: cs.tertiary,
                    count: dueThisMonth.length,
                  ),
                  for (final e in dueThisMonth)
                    _DueTile(
                      entry: e,
                      badgeColor: cs.tertiary,
                      badgeOnColor: cs.onTertiary,
                      now: now,
                    ),
                ],
                if (dueLater.isNotEmpty) ...[
                  _SectionHeader(
                    label: T.tr('status.scheduled'),
                    color: cs.onSurface,
                    count: dueLater.length,
                  ),
                  for (final e in dueLater)
                    _DueTile(
                      entry: e,
                      badgeColor: cs.surfaceContainerHighest,
                      badgeOnColor: cs.onSurface,
                      now: now,
                    ),
                ],
                const SizedBox(height: AppSpacing.lg),
              ],
            );
          },
        ),
      ),
    );
  }

  static DateTime? _tryParse(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return DateTime.parse(s).toLocal();
    } catch (_) {
      return null;
    }
  }
}

class _DueEntry {
  final Vaccination vaccination;
  final DateTime due;
  const _DueEntry(this.vaccination, this.due);
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color color;
  final int count;

  const _SectionHeader({
    required this.label,
    required this.color,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: AppSpacing.sm,
            height: AppSpacing.sm,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: tt.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: AppSpacing.xs + 2),
          Text(
            '($count)',
            style: tt.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DueTile extends StatelessWidget {
  final _DueEntry entry;
  final Color badgeColor;
  final Color badgeOnColor;
  final DateTime now;

  const _DueTile({
    required this.entry,
    required this.badgeColor,
    required this.badgeOnColor,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final due = entry.due;
    final formattedDate = DateFormat('MMM d, yyyy').format(due);
    final remaining = _formatRemaining(now, due);

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: badgeColor,
          foregroundColor: badgeOnColor,
          child: const Icon(Icons.vaccines),
        ),
        title: Text(
          entry.vaccination.vaccine.isEmpty
              ? 'Unnamed vaccine'
              : entry.vaccination.vaccine,
          style: tt.titleMedium?.copyWith(color: cs.onSurface),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.event,
                      size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Next due: $formattedDate',
                    style: tt.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.schedule,
                      size: 14, color: badgeColor),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    remaining,
                    style: tt.bodySmall?.copyWith(
                      color: badgeColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatRemaining(DateTime now, DateTime due) {
    final diff = due.difference(now);
    final days = diff.inDays;
    if (days < 0) {
      final overdueDays = -days;
      if (overdueDays == 0) return 'Overdue today';
      if (overdueDays == 1) return 'Overdue by 1 day';
      if (overdueDays < 30) return 'Overdue by $overdueDays days';
      final months = (overdueDays / 30).floor();
      return months == 1
          ? 'Overdue by 1 month'
          : 'Overdue by $months months';
    }
    if (days == 0) return 'Due today';
    if (days == 1) return 'Due tomorrow';
    if (days < 30) return 'Due in $days days';
    final months = (days / 30).floor();
    return months == 1 ? 'Due in 1 month' : 'Due in $months months';
  }
}
