import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  final vaultExists = vaultFile.existsSync();
  await controller.bootstrap(vaultExists: vaultExists);

  // Detect pre-vault (pre-refactor) credentials that the old static
  // `AuthService` wrote directly into `flutter_secure_storage`. If any
  // legacy key is still present on the device but no encrypted vault
  // exists yet, we route the user through the migration screen before
  // forcing a fresh PIN setup + re-login.
  if (!vaultExists) {
    final hasLegacyCreds = await _probeLegacyCredentials();
    if (hasLegacyCreds) {
      controller.onMigrationDetected();
    }
  }

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

/// Returns true when any of the pre-vault `flutter_secure_storage`
/// credential keys still exist on the device. Wrapped in try/catch so a
/// missing backing store on a fresh install never breaks startup.
Future<bool> _probeLegacyCredentials() async {
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  const legacyKeys = <String>[
    'auth_email',
    'auth_hash',
    'auth_server_url',
  ];
  for (final key in legacyKeys) {
    try {
      final value = await storage.read(key: key);
      if (value != null) return true;
    } catch (_) {
      // Secure storage unavailable (e.g. fresh install, platform quirk) —
      // treat as "no legacy creds" and continue.
      return false;
    }
  }
  return false;
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

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp.router(
          title: 'HealthVault',
          theme: AppTheme.lightFromDynamic(lightDynamic),
          darkTheme: AppTheme.darkFromDynamic(darkDynamic),
          themeMode: themeMode,
          routerConfig: ref.watch(appRouterProvider),
          debugShowCheckedModeBanner: false,
          locale: Locale(lang),
          supportedLocales: const [Locale('de'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        );
      },
    );
  }
}
