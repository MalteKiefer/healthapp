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
import 'core/security/secure_store/encrypted_cookie_jar.dart';
import 'core/security/secure_store/encrypted_vault.dart';
import 'core/security/security_state.dart';
import 'core/theme/app_theme.dart';
import 'providers/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final savedLangPref = prefs.getString('language') ?? 'system';
  final savedTheme = prefs.getString('themeMode') ?? 'system';
  T.setLanguage(savedLangPref);

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
  final controller = AppLockController(
    pinService: pinService,
    authService: authService,
  );
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

  // Build the ProviderContainer up-front so the synchronous bootstrap work
  // (cookie jar installation, post-unlock baseUrl restore) shares the same
  // ApiClient singleton as the widget tree.
  final container = ProviderContainer(
    overrides: [
      languageProvider.overrideWith((ref) => savedLangPref),
      themeModeProvider.overrideWith((ref) => themeMode),
      authServiceProvider.overrideWithValue(authService),
      appLockControllerProvider.overrideWith((ref) => controller),
    ],
  );

  // Install a vault-backed cookie jar immediately. While the vault is still
  // locked the jar keeps cookies in memory and flushes them once unlocked,
  // so the very first login after setupPin does not lose its session.
  final apiClient = container.read(apiClientProvider);
  final cookieJar = EncryptedCookieJar(vault: vault);
  apiClient.setCookieJar(cookieJar);

  // Once the vault becomes unlocked (either via PIN entry on an existing
  // install or via setupPin after first login), restore the saved server URL
  // onto ApiClient and reload persisted cookies from the vault.
  container.listen<SecurityState>(appLockControllerProvider, (prev, next) async {
    if (next == SecurityState.unlocked) {
      try {
        if (apiClient.baseUrl.isEmpty) {
          final creds = await authService.loadCredentials();
          if (creds != null) {
            await apiClient.setBaseUrl(creds.serverUrl);
          }
        }
        await cookieJar.reload();
      } catch (_) {
        // Swallow — the UI surfaces a friendly error via apiErrorMessage.
      }
    }
  });

  runApp(UncontrolledProviderScope(
    container: container,
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
    final pref = ref.watch(languageProvider);
    final effective = T.effectiveLanguage(pref);
    T.setLanguage(pref);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp.router(
          title: 'HealthVault',
          theme: AppTheme.lightFromDynamic(lightDynamic),
          darkTheme: AppTheme.darkFromDynamic(darkDynamic),
          themeMode: themeMode,
          routerConfig: ref.watch(appRouterProvider),
          debugShowCheckedModeBanner: false,
          locale: Locale(effective),
          supportedLocales: const [
            Locale('en'),
            Locale('de'),
            Locale('fr'),
            Locale('es'),
            Locale('it'),
            Locale('pl'),
          ],
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
