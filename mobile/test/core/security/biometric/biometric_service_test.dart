import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/biometric/biometric_service.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';
import 'package:healthapp/core/security/key_management/keystore_binding.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bio_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  EncryptedVault makeVault() => EncryptedVault(
        file: File('${tempDir.path}/vault.enc'),
        kek: KekService.fastForTests(),
        dek: DekService(),
      );

  test('enroll writes wrappedDekByBio into vault', () async {
    final vault = makeVault();
    await vault.create(pin: '123456');
    final ks = FakeKeystoreBinding();
    final svc = BiometricService(keystore: ks);

    await svc.enroll(vault: vault);

    expect(vault.wrappedDekByBio, isNotNull);
    expect(await ks.hasKey(BiometricService.keyAlias), isTrue);
  });

  test('unlockWithBiometrics round-trip recovers DEK', () async {
    final vault = makeVault();
    await vault.create(pin: '123456');
    final ks = FakeKeystoreBinding()..authorizeNext = true;
    final svc = BiometricService(keystore: ks);
    await svc.enroll(vault: vault);
    await vault.flush();
    vault.lock();

    await svc.unlock(vault: vault);
    expect(vault.isUnlocked, isTrue);
  });

  test('unlock fails when user cancels biometric prompt', () async {
    final vault = makeVault();
    await vault.create(pin: '123456');
    final ks = FakeKeystoreBinding();
    final svc = BiometricService(keystore: ks);
    await svc.enroll(vault: vault);
    await vault.flush();
    vault.lock();

    ks.authorizeNext = false;
    expect(
      () => svc.unlock(vault: vault),
      throwsA(isA<BiometricCancelledException>()),
    );
  });

  test('disable removes keystore key and wrappedDekByBio', () async {
    final vault = makeVault();
    await vault.create(pin: '123456');
    final ks = FakeKeystoreBinding();
    final svc = BiometricService(keystore: ks);
    await svc.enroll(vault: vault);

    await svc.disable(vault: vault);

    expect(vault.wrappedDekByBio, isNull);
    expect(await ks.hasKey(BiometricService.keyAlias), isFalse);
  });
}
