import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/auth/auth_service.dart';
import 'core/i18n/translations.dart';
import 'core/router/app_router.dart';
import 'core/security/app_lock/app_lock_controller.dart';
import 'core/security/app_lock/lifecycle_observer.dart';
import 'core/security/key_management/dek_service.dart';
import 'core/security/key_management/kek_service.dart';
import 'core/security/pin/pin_service.dart';
import 'core/security/secure_store/encrypted_vault.dart';
import 'core/theme/app_theme.dart';
import 'providers/providers.dart';

Future<void> main() async {
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

  // Bootstrap the encrypted vault, PIN service, and app-lock controller.
  // Credential loading is deferred until after the vault is unlocked and is
  // handled lazily via the router redirect / providers.
  final supportDir = await getApplicationSupportDirectory();
  final vaultFile = File('${supportDir.path}/vault.enc');
  final vault = EncryptedVault(
    file: vaultFile,
    kek: KekService.production(),
    dek: DekService(),
  );
  final pinService = PinService(vault: vault);
  final authService = AuthService(vault: vault);
  final controller = AppLockController(pinService: pinService);
  await controller.bootstrap(vaultExists: vaultFile.existsSync());

  final lifecycle = SecurityLifecycleObserver(controller);
  WidgetsBinding.instance.addObserver(lifecycle);

  runApp(ProviderScope(
    overrides: [
      languageProvider.overrideWith((ref) => savedLang),
      themeModeProvider.overrideWith((ref) => themeMode),
      authServiceProvider.overrideWithValue(authService),
      appLockControllerProvider.overrideWith((ref) => controller),
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
