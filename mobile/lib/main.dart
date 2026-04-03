import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/i18n/translations.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'providers/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final savedLang = prefs.getString('language') ?? 'de';
  final savedTheme = prefs.getString('themeMode') ?? 'system';
  T.setLanguage(savedLang);

  final themeMode = switch (savedTheme) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  runApp(ProviderScope(
    overrides: [
      languageProvider.overrideWith((ref) => savedLang),
      themeModeProvider.overrideWith((ref) => themeMode),
    ],
    child: const HealthVaultApp(),
  ));
}

class HealthVaultApp extends ConsumerWidget {
  const HealthVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    // Watch language to trigger rebuild on change
    ref.watch(languageProvider);

    return MaterialApp.router(
      title: 'HealthVault',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
