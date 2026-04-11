import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../models/medication_adherence.dart';
import '../../providers/medication_adherence_provider.dart';
import '../../widgets/skeletons.dart';

String _trOr(String key, String fallback) {
  final v = T.tr(key);
  return v == key ? fallback : v;
}

/// Displays adherence per medication as progress bars plus a summary row.
class AdherenceScreen extends ConsumerWidget {
  final String profileId;
  const AdherenceScreen({super.key, required this.profileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(medicationAdherenceProvider(profileId));

    return Scaffold(
      appBar: AppBar(
        title: Text(_trOr('meds.adherence.title', 'Adherence')),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(medicationAdherenceProvider(profileId));
          await ref.read(medicationAdherenceProvider(profileId).future);
        },
        child: async.when(
          loading: () => ListView(
            children: const [
              SkeletonCard(),
              SkeletonList(count: 5),
            ],
          ),
          error: (e, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'Failed to load adherence: $e',
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ],
          ),
          data: (data) {
            if (data.perMedication.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Icon(
                      Icons.insights_outlined,
                      size: 64,
                      color: scheme.outline,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Text(
                      'No adherence data yet',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: Text(
                      'Log some intakes to see your stats',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                _SummaryCard(summary: data.summary),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Per medication',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                ...data.perMedication.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(
                      bottom: AppSpacing.sm + AppSpacing.xs,
                    ),
                    child: _AdherenceRow(entry: e),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final MedicationAdherenceSummary summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = summary.overallPct;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Overall adherence',
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              pct == null ? '—' : '${pct.toStringAsFixed(0)}%',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: scheme.onPrimaryContainer),
            ),
            if (summary.totalDoses != null || summary.missedDoses != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                [
                  if (summary.totalDoses != null)
                    '${summary.totalDoses} total doses',
                  if (summary.missedDoses != null)
                    '${summary.missedDoses} missed',
                ].join(' • '),
                style: TextStyle(color: scheme.onPrimaryContainer),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AdherenceRow extends StatelessWidget {
  final MedicationAdherenceEntry entry;
  const _AdherenceRow({required this.entry});

  Color _colorForPct(ColorScheme scheme, double pct) {
    if (pct >= 0.8) return scheme.primary;
    if (pct >= 0.5) return scheme.tertiary;
    return scheme.error;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pctRaw = entry.adherencePct;
    // Accept both 0..1 and 0..100 representations.
    final pct01 = pctRaw > 1 ? (pctRaw / 100).clamp(0.0, 1.0) : pctRaw.clamp(0.0, 1.0);
    final pctLabel = (pct01 * 100).toStringAsFixed(0);
    final lastTaken = entry.lastTakenAt;
    final lastParsed =
        lastTaken == null ? null : DateTime.tryParse(lastTaken);
    final lastLabel = lastParsed == null
        ? (lastTaken ?? 'Never')
        : DateFormat('MMM d, HH:mm').format(lastParsed.toLocal());

    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.medicationName ?? entry.medicationId,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$pctLabel%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _colorForPct(scheme, pct01),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct01,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _colorForPct(scheme, pct01),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Last taken: $lastLabel',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                Text(
                  'Missed 7d: ${entry.missedDosesLast7d}',
                  style: TextStyle(
                    color: entry.missedDosesLast7d > 0
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
