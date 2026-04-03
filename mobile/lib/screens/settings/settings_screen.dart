import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/i18n/translations.dart';
import '../../providers/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final lang = ref.watch(languageProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(T.tr('settings.title')),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          const SizedBox(height: 16),
          // Language
          Text(T.tr('settings.language'),
              style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'de',
                  label: Text(T.tr('settings.german')),
                ),
                ButtonSegment(
                  value: 'en',
                  label: Text(T.tr('settings.english')),
                ),
              ],
              selected: {lang},
              onSelectionChanged: (s) async {
                final newLang = s.first;
                ref.read(languageProvider.notifier).state = newLang;
                T.setLanguage(newLang);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('language', newLang);
              },
            ),
          ),
          const SizedBox(height: 32),

          // Theme
          Text(T.tr('settings.theme'),
              style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text(T.tr('settings.theme_system')),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text(T.tr('settings.theme_light')),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text(T.tr('settings.theme_dark')),
                ),
              ],
              selected: {themeMode},
              onSelectionChanged: (s) async {
                final mode = s.first;
                ref.read(themeModeProvider.notifier).state = mode;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('themeMode', mode.name);
              },
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
