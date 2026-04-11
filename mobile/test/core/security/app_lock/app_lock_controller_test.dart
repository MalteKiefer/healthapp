import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/auth/auth_service.dart';
import 'package:healthapp/core/security/app_lock/app_lock_controller.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';
import 'package:healthapp/core/security/pin/pin_service.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';
import 'package:healthapp/core/security/security_state.dart';

void main() {
  late Directory tempDir;
  late DateTime fakeNow;
  DateTime now() => fakeNow;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('alc_');
    fakeNow = DateTime(2026, 4, 10, 12);
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  AppLockController makeController() {
    final vault = EncryptedVault(
      file: File('${tempDir.path}/vault.enc'),
      kek: KekService.fastForTests(),
      dek: DekService(),
    );
    final pin = PinService(vault: vault, now: now);
    return AppLockController(
      pinService: pin,
      now: now,
      backgroundTimeout: const Duration(minutes: 5),
      absoluteSessionTimeout: const Duration(hours: 24),
    );
  }

  test('initial state is unregistered when no vault exists', () async {
    final c = makeController();
    await c.bootstrap(vaultExists: false);
    expect(c.state, SecurityState.unregistered);
  });

  test('initial state is locked when vault exists', () async {
    final c = makeController();
    await c.pinService.setupPin('123456');
    c.pinService.lock();
    await c.bootstrap(vaultExists: true);
    expect(c.state, SecurityState.locked);
  });

  test('setupPin transitions to unlocked', () async {
    final c = makeController();
    await c.bootstrap(vaultExists: false);
    await c.setupPin('123456');
    expect(c.state, SecurityState.unlocked);
  });

  test('lock() transitions unlocked → locked', () async {
    final c = makeController();
    await c.setupPin('123456');
    c.lock();
    expect(c.state, SecurityState.locked);
  });

  test('unlock with correct pin transitions locked → unlocked', () async {
    final c = makeController();
    await c.setupPin('123456');
    c.lock();
    await c.unlockWithPin('123456');
    expect(c.state, SecurityState.unlocked);
  });

  test('onBackgrounded schedules lock after timeout', () async {
    final c = makeController();
    await c.setupPin('123456');
    c.onBackgrounded();
    expect(c.state, SecurityState.unlocked);
    fakeNow = fakeNow.add(const Duration(minutes: 4, seconds: 59));
    c.onResumed();
    expect(c.state, SecurityState.unlocked);
  });

  test('onResumed after 5 min transitions to locked', () async {
    final c = makeController();
    await c.setupPin('123456');
    c.onBackgrounded();
    fakeNow = fakeNow.add(const Duration(minutes: 5, seconds: 1));
    c.onResumed();
    expect(c.state, SecurityState.locked);
  });

  test('onResumed after 24 h triggers full logout', () async {
    final c = makeController();
    await c.setupPin('123456');
    fakeNow = fakeNow.add(const Duration(hours: 24, seconds: 1));
    c.onResumed();
    expect(c.state, SecurityState.unregistered);
  });

  test('wipe transitions to wiped then unregistered', () async {
    final c = makeController();
    await c.setupPin('123456');
    await c.wipe();
    expect(c.state, SecurityState.unregistered);
  });

  test('onLoginSuccess transitions to loggedInNoPin', () async {
    final c = makeController();
    await c.bootstrap(vaultExists: false);
    c.onLoginSuccess();
    expect(c.state, SecurityState.loggedInNoPin);
  });

  test(
      'onLoginSuccess stashes credentials and setupPin persists them into vault',
      () async {
    final vault = EncryptedVault(
      file: File('${tempDir.path}/vault.enc'),
      kek: KekService.fastForTests(),
      dek: DekService(),
    );
    final pin = PinService(vault: vault, now: now);
    final authService = AuthService(vault: vault);
    final c = AppLockController(
      pinService: pin,
      authService: authService,
      now: now,
    );

    await c.bootstrap(vaultExists: false);
    c.onLoginSuccess(StoredCredentials(
      email: 'alice@example.com',
      authHash: 'hash-abc',
      serverUrl: 'https://example.com',
    ));
    expect(c.state, SecurityState.loggedInNoPin);

    // At this point the vault does NOT exist yet. Saving credentials
    // directly would throw "Vault is locked" — that was the bug.
    await c.setupPin('123456');
    expect(c.state, SecurityState.unlocked);

    // The pending credentials must now be readable from the vault.
    final stored = await authService.loadCredentials();
    expect(stored, isNotNull);
    expect(stored!.email, 'alice@example.com');
    expect(stored.authHash, 'hash-abc');
    expect(stored.serverUrl, 'https://example.com');
  });

  test('onMigrationDetected transitions to migrationPending', () async {
    final c = makeController();
    await c.bootstrap(vaultExists: false);
    c.onMigrationDetected();
    expect(c.state, SecurityState.migrationPending);
  });

  test('acknowledgeMigration moves migrationPending → loggedInNoPin',
      () async {
    final c = makeController();
    await c.bootstrap(vaultExists: false);
    c.onMigrationDetected();
    c.acknowledgeMigration();
    expect(c.state, SecurityState.loggedInNoPin);
  });

  test('acknowledgeMigration is a no-op outside migrationPending', () async {
    final c = makeController();
    await c.bootstrap(vaultExists: false);
    c.acknowledgeMigration();
    expect(c.state, SecurityState.unregistered);
  });
}
