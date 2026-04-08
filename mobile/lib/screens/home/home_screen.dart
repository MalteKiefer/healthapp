import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/i18n/translations.dart';
import '../../models/profile.dart';
import '../../models/vital.dart';
import '../../models/medication.dart';
import '../../models/common.dart';
import '../../providers/providers.dart';

// -- Providers ----------------------------------------------------------------

final _vitalsProvider =
    FutureProvider.family<List<Vital>, String>((ref, profileId) async {
  if (profileId.isEmpty) return [];
  final api = ref.read(apiClientProvider);
  final data =
      await api.get<Map<String, dynamic>>('/api/v1/profiles/$profileId/vitals');
  return (data['items'] as List)
      .map((v) => Vital.fromJson(v as Map<String, dynamic>))
      .toList();
});

final _medicationsProvider =
    FutureProvider.family<List<Medication>, String>((ref, profileId) async {
  if (profileId.isEmpty) return [];
  final api = ref.read(apiClientProvider);
  final data = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/medications');
  return (data['items'] as List)
      .map((m) => Medication.fromJson(m as Map<String, dynamic>))
      .toList();
});

final _appointmentsProvider =
    FutureProvider.family<List<Appointment>, String>((ref, profileId) async {
  if (profileId.isEmpty) return [];
  final api = ref.read(apiClientProvider);
  final data = await api.get<Map<String, dynamic>>(
      '/api/v1/profiles/$profileId/appointments');
  return (data['items'] as List)
      .map((a) => Appointment.fromJson(a as Map<String, dynamic>))
      .toList();
});

// -- Screen -------------------------------------------------------------------

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfiles());
  }

  Future<void> _loadProfiles() async {
    final profiles = await ref.read(profilesProvider('').future);
    if (!mounted) return;
    if (profiles.isNotEmpty && ref.read(selectedProfileProvider) == null) {
      ref.read(selectedProfileProvider.notifier).state = profiles.first;
    }
  }

  void _goTo(String route) {
    final profile = ref.read(selectedProfileProvider);
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(T.tr('home.select_profile'))),
      );
      return;
    }
    context.go('$route/${profile.id}');
  }

  // -- Profile selector -------------------------------------------------------

  Widget _buildProfileSelector(List<Profile> profiles) {
    final selected = ref.watch(selectedProfileProvider);
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Profile: ${selected?.displayName ?? 'None selected'}',
      child: PopupMenuButton<Profile>(
      tooltip: 'Select profile',
      icon: CircleAvatar(
        radius: 18,
        backgroundColor: cs.primaryContainer,
        child: Text(
          (selected?.displayName ?? '?').substring(0, 1).toUpperCase(),
          style: TextStyle(
            color: cs.onPrimaryContainer,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      onSelected: (p) =>
          ref.read(selectedProfileProvider.notifier).state = p,
      itemBuilder: (_) => profiles
          .map((p) => PopupMenuItem<Profile>(
                value: p,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: cs.secondaryContainer,
                      child: Text(
                        p.displayName.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: cs.onSecondaryContainer,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(p.displayName),
                    if (selected?.id == p.id) ...[
                      const Spacer(),
                      Icon(Icons.check, size: 18, color: cs.primary),
                    ],
                  ],
                ),
              ))
          .toList(),
    ),
    );
  }

  // -- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final profilesAsync = ref.watch(profilesProvider(''));
    final selected = ref.watch(selectedProfileProvider);
    final pid = selected?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text('HealthVault', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        actions: [
          profilesAsync.when(
            data: (profiles) =>
                profiles.isNotEmpty ? _buildProfileSelector(profiles) : const SizedBox.shrink(),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: profilesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 16),
              Text(T.tr('home.failed_profiles'), style: tt.titleMedium),
              const SizedBox(height: 8),
              Text(e.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () => ref.invalidate(profilesProvider('')),
                child: Text(T.tr('common.retry')),
              ),
            ]),
          ),
        ),
        data: (_) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(profilesProvider(''));
            if (pid.isNotEmpty) {
              ref.invalidate(_vitalsProvider(pid));
              ref.invalidate(_medicationsProvider(pid));
              ref.invalidate(_appointmentsProvider(pid));
            }
          },
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              // -- Welcome -------------------------------------------------
              if (selected != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${T.tr('home.welcome')}, ${selected.displayName}',
                  style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('EEEE, MMMM d').format(DateTime.now()),
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 20),

              // -- Quick Actions -------------------------------------------
              Text(T.tr('home.quick_actions'), style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _QuickAction(
                    icon: Icons.favorite_outline,
                    label: T.tr('home.add_vital'),
                    color: cs.error,
                    onTap: () => _goTo('/vitals'),
                  ),
                  const SizedBox(width: 12),
                  _QuickAction(
                    icon: Icons.science_outlined,
                    label: T.tr('home.add_lab'),
                    color: cs.tertiary,
                    onTap: () => _goTo('/labs'),
                  ),
                  const SizedBox(width: 12),
                  _QuickAction(
                    icon: Icons.medication_outlined,
                    label: T.tr('home.add_med'),
                    color: cs.primary,
                    onTap: () => _goTo('/medications'),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // -- Recent Vitals -------------------------------------------
              if (pid.isNotEmpty) ...[
                Text(T.tr('home.recent_vitals'), style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 10),
                _RecentVitals(profileId: pid),
                const SizedBox(height: 24),

                // -- Active Medications ------------------------------------
                Text(T.tr('home.active_meds'), style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 10),
                _ActiveMedications(profileId: pid),
                const SizedBox(height: 24),

                // -- Upcoming Appointments ---------------------------------
                Text(T.tr('home.upcoming'), style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 10),
                _UpcomingAppointments(profileId: pid),
                const SizedBox(height: 32),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// -- Quick Action Button ------------------------------------------------------

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Semantics(
        label: label,
        button: true,
        child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: 8),
                Text(label, style: tt.labelMedium?.copyWith(color: cs.onSurface)),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

// -- Recent Vitals Section ----------------------------------------------------

class _RecentVitals extends ConsumerWidget {
  final String profileId;
  const _RecentVitals({required this.profileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final async = ref.watch(_vitalsProvider(profileId));

    return async.when(
      loading: () => const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(T.tr('home.could_not_load_vitals'), style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ),
      ),
      data: (vitals) {
        if (vitals.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Icon(Icons.favorite_outline, color: cs.outline),
                const SizedBox(width: 12),
                Text(T.tr('home.no_vitals'), style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          );
        }
        // Sort by date, get latest
        final sorted = [...vitals]
          ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
        final latest = sorted.first;

        final items = <_VitalSummaryItem>[];
        if (latest.systolic != null && latest.diastolic != null) {
          items.add(_VitalSummaryItem(
            label: T.tr('vitals.bp'),
            value: '${latest.systolic!.toInt()}/${latest.diastolic!.toInt()}',
            unit: 'mmHg',
            icon: Icons.favorite,
            color: cs.error,
          ));
        }
        if (latest.pulse != null) {
          items.add(_VitalSummaryItem(
            label: T.tr('vitals.pulse'),
            value: '${latest.pulse!.toInt()}',
            unit: 'bpm',
            icon: Icons.timeline,
            color: cs.tertiary,
          ));
        }
        if (latest.weight != null) {
          items.add(_VitalSummaryItem(
            label: T.tr('vitals.weight'),
            value: latest.weight!.toStringAsFixed(1),
            unit: 'kg',
            icon: Icons.monitor_weight_outlined,
            color: cs.primary,
          ));
        }
        if (latest.temperature != null) {
          items.add(_VitalSummaryItem(
            label: T.tr('vitals.temperature'),
            value: latest.temperature!.toStringAsFixed(1),
            unit: '\u00b0C',
            icon: Icons.thermostat,
            color: Colors.orange,
          ));
        }
        if (latest.oxygenSaturation != null) {
          items.add(_VitalSummaryItem(
            label: T.tr('vitals.spo2'),
            value: '${latest.oxygenSaturation!.toInt()}',
            unit: '%',
            icon: Icons.air,
            color: Colors.teal,
          ));
        }
        if (latest.bloodGlucose != null) {
          items.add(_VitalSummaryItem(
            label: T.tr('vitals.blood_glucose'),
            value: '${latest.bloodGlucose!.toInt()}',
            unit: 'mg/dL',
            icon: Icons.water_drop_outlined,
            color: Colors.purple,
          ));
        }

        if (items.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(T.tr('home.no_vital_values'), style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(T.tr('home.latest_reading'), style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                    const Spacer(),
                    Text(
                      _formatDate(latest.measuredAt),
                      style: tt.labelSmall?.copyWith(color: cs.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: items,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return DateFormat('MMM d, HH:mm').format(d);
    } catch (_) {
      return iso;
    }
  }
}

class _VitalSummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  const _VitalSummaryItem({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SizedBox(
      width: 140,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: tt.labelSmall?.copyWith(color: cs.outline)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 2),
                  Text(unit, style: tt.labelSmall?.copyWith(color: cs.outline)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -- Active Medications -------------------------------------------------------

class _ActiveMedications extends ConsumerWidget {
  final String profileId;
  const _ActiveMedications({required this.profileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final async = ref.watch(_medicationsProvider(profileId));

    return async.when(
      loading: () => const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(T.tr('home.could_not_load_meds'), style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ),
      ),
      data: (meds) {
        final active = meds.where((m) => m.isActive).toList();
        if (active.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Icon(Icons.medication_outlined, color: cs.outline),
                const SizedBox(width: 12),
                Text(T.tr('home.no_active_meds'), style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          );
        }
        return Card(
          child: Column(
            children: [
              for (int i = 0; i < active.length && i < 3; i++) ...[
                if (i > 0) Divider(indent: 16, endIndent: 16, color: cs.outlineVariant.withValues(alpha: 0.3)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(active[i].name, style: tt.bodyLarge),
                            if (active[i].dosage != null || active[i].frequency != null)
                              Text(
                                [
                                  if (active[i].dosage != null) active[i].dosage!,
                                  if (active[i].frequency != null) active[i].frequency!,
                                ].join(' \u00b7 '),
                                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (active.length > 3)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '+${active.length - 3} ${T.tr('home.more_count')}',
                    style: tt.labelSmall?.copyWith(color: cs.primary),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// -- Upcoming Appointments ----------------------------------------------------

class _UpcomingAppointments extends ConsumerWidget {
  final String profileId;
  const _UpcomingAppointments({required this.profileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final async = ref.watch(_appointmentsProvider(profileId));

    return async.when(
      loading: () => const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(T.tr('home.could_not_load_appts'), style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ),
      ),
      data: (appts) {
        final now = DateTime.now();
        final upcoming = appts.where((a) {
          if (a.scheduledAt == null) return false;
          final d = DateTime.tryParse(a.scheduledAt!);
          return d != null && d.isAfter(now);
        }).toList()
          ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));

        if (upcoming.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Icon(Icons.event_outlined, color: cs.outline),
                const SizedBox(width: 12),
                Text(T.tr('home.no_upcoming'), style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          );
        }

        return Card(
          child: Column(
            children: [
              for (int i = 0; i < upcoming.length && i < 3; i++) ...[
                if (i > 0) Divider(indent: 16, endIndent: 16, color: cs.outlineVariant.withValues(alpha: 0.3)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.event, size: 18, color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(upcoming[i].title, style: tt.bodyLarge),
                            if (upcoming[i].scheduledAt != null)
                              Text(
                                _formatDate(upcoming[i].scheduledAt!),
                                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 20, color: cs.outline),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return DateFormat('EEE, MMM d \u2013 HH:mm').format(d);
    } catch (_) {
      return iso;
    }
  }
}
