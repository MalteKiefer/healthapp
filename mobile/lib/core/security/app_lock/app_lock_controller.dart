import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthapp/core/auth/auth_service.dart';
import 'package:healthapp/core/security/pin/pin_service.dart';
import 'package:healthapp/core/security/security_state.dart';

/// Riverpod state notifier driving the security state machine.
class AppLockController extends StateNotifier<SecurityState> {
  AppLockController({
    required this.pinService,
    this.authService,
    DateTime Function()? now,
    this.backgroundTimeout = const Duration(minutes: 5),
    this.absoluteSessionTimeout = const Duration(hours: 24),
  })  : _now = now ?? DateTime.now,
        super(SecurityState.unregistered);

  final PinService pinService;

  /// Optional: when provided, [setupPin] persists any credentials
  /// stashed via [onLoginSuccess] into the vault after it is created.
  /// Tests can omit this and handle persistence themselves.
  final AuthService? authService;

  /// Optional callback invoked after the vault is unlocked but BEFORE
  /// the security state flips to [SecurityState.unlocked]. Use this
  /// to restore API session state (baseUrl, cookies, key cache) so that
  /// the first screen rendered after unlock already has a working
  /// network session.
  Future<void> Function()? onBeforeUnlock;

  final DateTime Function() _now;
  final Duration backgroundTimeout;
  final Duration absoluteSessionTimeout;

  DateTime? _sessionStartAt;
  DateTime? _backgroundedAt;

  /// Credentials captured from a successful server login, waiting for
  /// the vault to exist (i.e. waiting for [setupPin]) before they can
  /// be encrypted and persisted. Null when no login is pending.
  StoredCredentials? _pendingCredentials;

  Future<void> bootstrap({required bool vaultExists}) async {
    state = vaultExists ? SecurityState.locked : SecurityState.unregistered;
  }

  Future<void> setupPin(String pin) async {
    state = SecurityState.unlocking;
    await pinService.setupPin(pin);
    // Vault is now created and unlocked — flush any pending login
    // credentials into it before announcing the unlocked state.
    final pending = _pendingCredentials;
    if (pending != null && authService != null) {
      await authService!.saveCredentials(pending);
      _pendingCredentials = null;
    }
    await onBeforeUnlock?.call();
    _sessionStartAt = _now();
    state = SecurityState.unlocked;
  }

  Future<void> unlockWithPin(String pin) async {
    state = SecurityState.unlocking;
    try {
      await pinService.verifyPin(pin);
      await onBeforeUnlock?.call();
      _sessionStartAt = _now();
      state = SecurityState.unlocked;
    } catch (e) {
      if (pinService.wipeRequested) {
        await wipe();
      } else {
        state = SecurityState.locked;
      }
      rethrow;
    }
  }

  /// Called by the LifecycleObserver on resume.
  void onResumed() {
    // 1. Absolute session timeout
    if (_sessionStartAt != null &&
        _now().difference(_sessionStartAt!) >= absoluteSessionTimeout) {
      _sessionStartAt = null;
      _backgroundedAt = null;
      pinService.lock();
      state = SecurityState.unregistered;
      return;
    }
    // 2. Background timeout
    if (_backgroundedAt != null &&
        _now().difference(_backgroundedAt!) >= backgroundTimeout) {
      pinService.lock();
      state = SecurityState.locked;
    }
    _backgroundedAt = null;
  }

  void onBackgrounded() {
    _backgroundedAt = _now();
  }

  void lock() {
    pinService.lock();
    state = SecurityState.locked;
  }

  Future<void> wipe() async {
    await pinService.wipe();
    state = SecurityState.wiped;
    _sessionStartAt = null;
    _backgroundedAt = null;
    state = SecurityState.unregistered;
  }

  /// Called after a successful server login when no vault/PIN exists yet.
  /// The router observes [SecurityState.loggedInNoPin] and forces the
  /// user through the PIN setup flow.
  ///
  /// When [credentials] is provided, they are stashed in memory and
  /// automatically persisted into the encrypted vault during
  /// [setupPin] — after the vault has been created and unlocked.
  /// This avoids the "vault is locked" error that would occur if the
  /// login screen tried to write credentials before the PIN exists.
  void onLoginSuccess([StoredCredentials? credentials]) {
    if (credentials != null) {
      _pendingCredentials = credentials;
    }
    state = SecurityState.loggedInNoPin;
  }

  /// Called from bootstrap when legacy `flutter_secure_storage`
  /// credentials from a pre-vault installation are detected but no
  /// encrypted vault exists yet. Transitions to
  /// [SecurityState.migrationPending] so the router surfaces the
  /// migration screen.
  void onMigrationDetected() {
    state = SecurityState.migrationPending;
  }

  /// Called from the migration screen once the user has acknowledged the
  /// upgrade notice. Moves into [SecurityState.loggedInNoPin] so the
  /// router forwards to the regular PIN setup flow.
  void acknowledgeMigration() {
    if (state == SecurityState.migrationPending) {
      state = SecurityState.loggedInNoPin;
    }
  }
}

/// Stub provider — overridden in `main.dart` once a real [PinService]
/// bound to the app documents directory is available. Keeping the
/// provider exported here lets later tasks (router, screens) import it
/// without reaching into bootstrap code.
final appLockControllerProvider =
    StateNotifierProvider<AppLockController, SecurityState>((ref) {
  throw UnimplementedError(
    'appLockControllerProvider must be overridden in main.dart with a '
    'real PinService bound to the app documents directory',
  );
});
