import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/auth/auth_service.dart';
import 'core/i18n/translations.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'models/auth.dart';
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

class HealthVaultApp extends ConsumerStatefulWidget {
  const HealthVaultApp({super.key});

  @override
  ConsumerState<HealthVaultApp> createState() => _HealthVaultAppState();
}

class _HealthVaultAppState extends ConsumerState<HealthVaultApp> {
  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    final creds = await AuthService.loadCredentials();
    if (creds == null) {
      appRouter.go('/login');
      return;
    }
    try {
      final api = ref.read(apiClientProvider);
      await api.setBaseUrl(creds.serverUrl);
      await api.post<dynamic>(
        '/api/v1/auth/login',
        body: LoginRequest(email: creds.email, authHash: creds.authHash).toJson(),
      );
      if (mounted) appRouter.go('/home');
    } catch (_) {
      if (mounted) appRouter.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    ref.watch(languageProvider);
    final lang = ref.watch(languageProvider);

    return MaterialApp.router(
      title: 'HealthVault',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      locale: Locale(lang),
      supportedLocales: const [Locale('de'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
