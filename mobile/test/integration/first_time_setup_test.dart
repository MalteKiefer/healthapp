import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/app_lock/app_lock_controller.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';
import 'package:healthapp/core/security/pin/pin_service.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';
import 'package:healthapp/core/security/security_state.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('e2e_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('first-time setup: bootstrap -> login -> PIN -> unlocked', () async {
    final vault = EncryptedVault(
      file: File('${tempDir.path}/vault.enc'),
      kek: KekService.fastForTests(),
      dek: DekService(),
    );
    final pin = PinService(vault: vault);
    final ctrl = AppLockController(pinService: pin);

    await ctrl.bootstrap(vaultExists: false);
    expect(ctrl.state, SecurityState.unregistered);

    ctrl.onLoginSuccess();
    expect(ctrl.state, SecurityState.loggedInNoPin);

    await ctrl.setupPin('123456');
    expect(ctrl.state, SecurityState.unlocked);
    expect(vault.file.existsSync(), isTrue);
  });

  test('lock -> unlock via PIN', () async {
    final vault = EncryptedVault(
      file: File('${tempDir.path}/vault.enc'),
      kek: KekService.fastForTests(),
      dek: DekService(),
    );
    final pin = PinService(vault: vault);
    final ctrl = AppLockController(pinService: pin);
    ctrl.onLoginSuccess();
    await ctrl.setupPin('123456');
    ctrl.lock();
    expect(ctrl.state, SecurityState.locked);
    await ctrl.unlockWithPin('123456');
    expect(ctrl.state, SecurityState.unlocked);
  });

  test('wipe after 10 wrong PINs', () async {
    var fakeNow = DateTime(2026, 4, 10, 12);
    final vault = EncryptedVault(
      file: File('${tempDir.path}/vault.enc'),
      kek: KekService.fastForTests(),
      dek: DekService(),
    );
    final pin = PinService(vault: vault, now: () => fakeNow);
    final ctrl = AppLockController(pinService: pin, now: () => fakeNow);
    ctrl.onLoginSuccess();
    await ctrl.setupPin('123456');
    ctrl.lock();

    for (var i = 0; i < 10; i++) {
      try {
        await ctrl.unlockWithPin('000000');
      } catch (_) {}
      fakeNow = fakeNow.add(const Duration(hours: 2));
    }
    expect(ctrl.state, SecurityState.unregistered);
    expect(vault.file.existsSync(), isFalse);
  });
}
