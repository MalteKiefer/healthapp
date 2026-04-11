import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/providers.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final selectedProfile = ref.watch(selectedProfileProvider);
    final pid = selectedProfile?.id;
    final hasProfile = pid != null && pid.isNotEmpty;
    const noProfileSubtitle = 'Select a profile first';

    Widget sectionHeader(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: tt.labelMedium?.copyWith(color: cs.primary),
          ),
        );

    ListTile navTile({
      required IconData icon,
      required String label,
      required String route,
      bool requiresProfile = false,
    }) {
      final disabled = requiresProfile && !hasProfile;
      return ListTile(
        leading: Icon(
          icon,
          color: disabled ? cs.onSurface.withValues(alpha: 0.38) : null,
        ),
        title: Text(
          label,
          style: disabled
              ? TextStyle(color: cs.onSurface.withValues(alpha: 0.38))
              : null,
        ),
        subtitle: disabled ? const Text(noProfileSubtitle) : null,
        enabled: !disabled,
        onTap: disabled ? null : () => context.go(route),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          // Profile
          sectionHeader('Profile'),
          navTile(
            icon: Icons.people_outline,
            label: 'Profile Management',
            route: '/profiles',
          ),
          navTile(
            icon: Icons.tune,
            label: 'Vital Thresholds',
            route: '/vitals/$pid/thresholds',
            requiresProfile: true,
          ),
          navTile(
            icon: Icons.history,
            label: 'Activity Log',
            route: '/activity/$pid',
            requiresProfile: true,
          ),
          const Divider(),

          // Security
          sectionHeader('Security'),
          navTile(
            icon: Icons.security,
            label: '2FA Setup',
            route: '/2fa/setup',
          ),
          navTile(
            icon: Icons.devices,
            label: 'Active Sessions',
            route: '/sessions',
          ),
          const Divider(),

          // Data
          sectionHeader('Data'),
          navTile(
            icon: Icons.show_chart,
            label: 'Lab Trends',
            route: '/labs/$pid/trends',
            requiresProfile: true,
          ),
          navTile(
            icon: Icons.medication_outlined,
            label: 'Medication Adherence',
            route: '/medications/$pid/adherence',
            requiresProfile: true,
          ),
          navTile(
            icon: Icons.sick_outlined,
            label: 'Symptom Chart',
            route: '/symptoms/$pid/chart',
            requiresProfile: true,
          ),
          navTile(
            icon: Icons.search,
            label: 'Document Search',
            route: '/documents/$pid/search',
            requiresProfile: true,
          ),
          navTile(
            icon: Icons.upload_file_outlined,
            label: 'Bulk Upload',
            route: '/documents/$pid/bulk',
            requiresProfile: true,
          ),
          navTile(
            icon: Icons.download_outlined,
            label: 'Export',
            route: '/export/$pid',
            requiresProfile: true,
          ),
          navTile(
            icon: Icons.schedule_outlined,
            label: 'Export Schedules',
            route: '/export/schedules',
          ),
          const Divider(),

          // Sharing
          sectionHeader('Sharing'),
          navTile(
            icon: Icons.share_outlined,
            label: 'Doctor Shares',
            route: '/shares/$pid',
            requiresProfile: true,
          ),
          navTile(
            icon: Icons.calendar_today_outlined,
            label: 'Calendar Feeds',
            route: '/calendar-feeds',
          ),
          navTile(
            icon: Icons.emergency_outlined,
            label: 'Emergency Access',
            route: '/emergency/$pid',
            requiresProfile: true,
          ),
          const Divider(),

          // Filters / Quick Views
          sectionHeader('Filters / Quick Views'),
          navTile(
            icon: Icons.task_alt_outlined,
            label: 'Open Tasks',
            route: '/tasks/$pid/open',
            requiresProfile: true,
          ),
          navTile(
            icon: Icons.event_outlined,
            label: 'Upcoming Appointments',
            route: '/appointments/$pid/upcoming',
            requiresProfile: true,
          ),
          navTile(
            icon: Icons.vaccines_outlined,
            label: 'Vaccinations Due',
            route: '/vaccinations/$pid/due',
            requiresProfile: true,
          ),
          const Divider(),

          // About
          sectionHeader('About'),
          navTile(
            icon: Icons.settings_outlined,
            label: 'Settings',
            route: '/settings',
          ),
          navTile(
            icon: Icons.info_outline,
            label: 'About',
            route: '/about',
          ),
          ListTile(
            leading: Icon(Icons.logout, color: cs.error),
            title: Text('Sign Out', style: TextStyle(color: cs.error)),
            onTap: () => context.go('/sign-out'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
