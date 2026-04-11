import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../providers/providers.dart';

// Returns the translation for [key] or [fallback] if the key is missing.
// T.tr returns the key itself when no translation is found, so we compare.
String _trOr(String key, String fallback) {
  final v = T.tr(key);
  return v == key ? fallback : v;
}

// Supported language options for the settings picker.
// `system` follows the OS locale; other values are ISO 639-1 codes.
const List<({String value, String nativeName})> _kLanguageOptions = [
  (value: 'system', nativeName: 'System'),
  (value: 'en', nativeName: 'English'),
  (value: 'de', nativeName: 'Deutsch'),
  (value: 'fr', nativeName: 'Français'),
  (value: 'es', nativeName: 'Español'),
  (value: 'it', nativeName: 'Italiano'),
  (value: 'pl', nativeName: 'Polski'),
];

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final lang = ref.watch(languageProvider);
    final themeMode = ref.watch(themeModeProvider);
    final firstDay = ref.watch(firstDayOfWeekProvider);

    final currentLanguageOption = _kLanguageOptions.firstWhere(
      (o) => o.value == lang,
      orElse: () => _kLanguageOptions.first,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(T.tr('settings.title')),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        children: [
          const SizedBox(height: AppSpacing.md),
          // Language
          Text(_trOr('settings.language', 'Language'),
              style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.sm),
          Material(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: Icon(Icons.language, color: cs.primary),
              title: Text(
                _trOr('settings.language', 'Language'),
                style: tt.bodyLarge?.copyWith(color: cs.onSurface),
              ),
              subtitle: Text(
                currentLanguageOption.nativeName,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              onTap: () => _showLanguagePicker(context, ref, lang),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

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

          // First day of week
          Text(T.tr('settings.first_day'),
              style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(
                  value: 1,
                  label: Text(T.tr('settings.monday')),
                ),
                ButtonSegment(
                  value: 7,
                  label: Text(T.tr('settings.sunday')),
                ),
              ],
              selected: {firstDay},
              onSelectionChanged: (s) async {
                final day = s.first;
                ref.read(firstDayOfWeekProvider.notifier).state = day;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('first_day_of_week', day);
              },
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _showLanguagePicker(
    BuildContext context,
    WidgetRef ref,
    String currentValue,
  ) async {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: cs.surface,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Text(
                    _trOr('settings.language', 'Language'),
                    style: tt.titleMedium?.copyWith(color: cs.onSurface),
                  ),
                ),
                for (final opt in _kLanguageOptions)
                  RadioListTile<String>(
                    value: opt.value,
                    groupValue: currentValue,
                    activeColor: cs.primary,
                    title: Text(
                      opt.nativeName,
                      style: tt.bodyLarge?.copyWith(color: cs.onSurface),
                    ),
                    onChanged: (newValue) async {
                      if (newValue == null) return;
                      Navigator.of(ctx).pop();
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('language', newValue);
                      ref.read(languageProvider.notifier).state = newValue;
                      // Keep the legacy in-memory translator in sync when a
                      // concrete locale is chosen; `system` leaves the app
                      // free to resolve the OS locale in main.dart.
                      if (newValue != 'system') {
                        T.setLanguage(newValue);
                      }
                    },
                  ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        );
      },
    );
  }
}
