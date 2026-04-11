import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/i18n/translations.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _info = info);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final versionString =
        _info == null ? '—' : '${_info!.version}+${_info!.buildNumber}';

    final features = [
      ('vitals', Icons.favorite_outline),
      ('labs', Icons.science_outlined),
      ('meds', Icons.medication_outlined),
      ('allergies', Icons.warning_amber_outlined),
      ('diagnoses', Icons.local_hospital_outlined),
      ('vaccinations', Icons.vaccines_outlined),
      ('appointments', Icons.event_outlined),
      ('contacts', Icons.contacts_outlined),
      ('tasks', Icons.task_alt_outlined),
      ('diary', Icons.book_outlined),
      ('symptoms', Icons.sick_outlined),
      ('documents', Icons.folder_outlined),
      ('encryption', Icons.lock_outline),
      ('offline', Icons.offline_bolt_outlined),
      ('selfhosted', Icons.dns_outlined),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(T.tr('about.title')),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          const SizedBox(height: 24),
          // App icon + name + version
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.favorite, size: 48, color: cs.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'HealthVault',
              style:
                  tt.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '${T.tr('about.version')} $versionString',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                T.tr('about.description'),
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Features section
          Text(T.tr('about.features'),
              style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < features.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 56,
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ListTile(
                    leading: Icon(features[i].$2, color: cs.onSurfaceVariant),
                    title:
                        Text(T.tr('about.feature_${features[i].$1}')),
                    dense: true,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // License & Source
          Text(T.tr('more.app'),
              style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading:
                      Icon(Icons.gavel_outlined, color: cs.onSurfaceVariant),
                  title: Text(T.tr('about.license')),
                  trailing: Text('MIT',
                      style: tt.bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ),
                Divider(
                  height: 1,
                  indent: 56,
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
                ListTile(
                  leading:
                      Icon(Icons.code_outlined, color: cs.onSurfaceVariant),
                  title: Text(T.tr('about.source')),
                  trailing:
                      Icon(Icons.open_in_new, size: 18, color: cs.outline),
                  onTap: () {
                    launchUrl(
                      Uri.parse(
                          'https://github.com/maltekiefer/healthvault'),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Tech info
          Text(T.tr('about.tech'),
              style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.phone_android_outlined,
                      color: cs.onSurfaceVariant),
                  title: const Text('Flutter'),
                  trailing: Text('Mobile App',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ),
                Divider(
                  height: 1,
                  indent: 56,
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
                ListTile(
                  leading: Icon(Icons.dns_outlined,
                      color: cs.onSurfaceVariant),
                  title: const Text('Go'),
                  trailing: Text('Backend API',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ),
                Divider(
                  height: 1,
                  indent: 56,
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
                ListTile(
                  leading: Icon(Icons.storage_outlined,
                      color: cs.onSurfaceVariant),
                  title: const Text('PostgreSQL'),
                  trailing: Text('Database',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
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
