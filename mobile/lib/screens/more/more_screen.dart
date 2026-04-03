import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_service.dart';
import '../../core/i18n/translations.dart';
import '../../providers/providers.dart';

class _MoreItem {
  final String labelKey;
  final IconData icon;
  final String route;
  const _MoreItem(this.labelKey, this.icon, this.route);
}

const _modules = [
  _MoreItem('allergies.title', Icons.warning_amber_outlined, '/allergies'),
  _MoreItem('diagnoses.title', Icons.local_hospital_outlined, '/diagnoses'),
  _MoreItem(
      'vaccinations.title', Icons.vaccines_outlined, '/vaccinations'),
  _MoreItem('appointments.title', Icons.event_outlined, '/appointments'),
  _MoreItem('contacts.title', Icons.contacts_outlined, '/contacts'),
  _MoreItem('tasks.title', Icons.task_alt_outlined, '/tasks'),
  _MoreItem('diary.title', Icons.book_outlined, '/diary'),
  _MoreItem('symptoms.title', Icons.sick_outlined, '/symptoms'),
  _MoreItem('documents.title', Icons.folder_outlined, '/documents'),
];

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final profile = ref.watch(selectedProfileProvider);
    // Watch language to rebuild on change
    ref.watch(languageProvider);

    void goTo(String route) {
      if (profile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(T.tr('home.select_profile'))),
        );
        return;
      }
      context.go('$route/${profile.id}');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(T.tr('more.title')),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Section: Health Modules
          Text(T.tr('more.modules'),
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
                    title: Text(T.tr(_modules[i].labelKey)),
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
          Text(T.tr('more.app'),
              style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.info_outline, color: cs.onSurfaceVariant),
                  title: Text(T.tr('more.about')),
                  trailing:
                      Icon(Icons.chevron_right, size: 20, color: cs.outline),
                  onTap: () => context.go('/about'),
                ),
                Divider(
                  height: 1,
                  indent: 56,
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
                ListTile(
                  leading:
                      Icon(Icons.settings_outlined, color: cs.onSurfaceVariant),
                  title: Text(T.tr('more.settings')),
                  trailing:
                      Icon(Icons.chevron_right, size: 20, color: cs.outline),
                  onTap: () => context.go('/settings'),
                ),
                Divider(
                  height: 1,
                  indent: 56,
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
                ListTile(
                  leading: Icon(Icons.logout, color: cs.error),
                  title: Text(T.tr('more.sign_out'),
                      style: TextStyle(color: cs.error)),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(T.tr('more.sign_out')),
                        content: Text(T.tr('more.sign_out_confirm')),
                        actions: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(T.tr('common.cancel')),
                          ),
                          FilledButton(
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await AuthService.clearCredentials();
                              if (context.mounted) context.go('/login');
                            },
                            child: Text(T.tr('more.sign_out')),
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
