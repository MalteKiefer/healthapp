import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/providers.dart';

class _MoreItem {
  final String label;
  final IconData icon;
  final String route;
  const _MoreItem(this.label, this.icon, this.route);
}

const _modules = [
  _MoreItem('Allergies', Icons.warning_amber_outlined, '/allergies'),
  _MoreItem('Diagnoses', Icons.local_hospital_outlined, '/diagnoses'),
  _MoreItem('Vaccinations', Icons.vaccines_outlined, '/vaccinations'),
  _MoreItem('Appointments', Icons.event_outlined, '/appointments'),
  _MoreItem('Contacts', Icons.contacts_outlined, '/contacts'),
  _MoreItem('Tasks', Icons.task_alt_outlined, '/tasks'),
  _MoreItem('Diary', Icons.book_outlined, '/diary'),
  _MoreItem('Symptoms', Icons.sick_outlined, '/symptoms'),
  _MoreItem('Documents', Icons.folder_outlined, '/documents'),
];

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final profile = ref.watch(selectedProfileProvider);

    void goTo(String route) {
      if (profile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a profile first.')),
        );
        return;
      }
      context.go('$route/${profile.id}');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Section: Health Modules
          Text('Health Modules',
              style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < _modules.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 56,
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ListTile(
                    leading: Icon(_modules[i].icon, color: cs.onSurfaceVariant),
                    title: Text(_modules[i].label),
                    trailing: Icon(Icons.chevron_right,
                        size: 20, color: cs.outline),
                    onTap: () => goTo(_modules[i].route),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section: App
          Text('App',
              style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.info_outline, color: cs.onSurfaceVariant),
                  title: const Text('About HealthVault'),
                  trailing:
                      Icon(Icons.chevron_right, size: 20, color: cs.outline),
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'HealthVault',
                      applicationVersion: '1.0.0',
                      applicationIcon: Icon(Icons.favorite,
                          size: 48, color: cs.primary),
                      children: [
                        const Text(
                            'Self-hosted health data platform.\nYour health, your data.'),
                      ],
                    );
                  },
                ),
                Divider(
                  height: 1,
                  indent: 56,
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
                ListTile(
                  leading:
                      Icon(Icons.logout, color: cs.error),
                  title: Text('Sign Out',
                      style: TextStyle(color: cs.error)),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Sign Out'),
                        content:
                            const Text('Are you sure you want to sign out?'),
                        actions: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              context.go('/login');
                            },
                            child: const Text('Sign Out'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
