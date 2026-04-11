import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';

void main() {
  late Directory tempDir;
  final kek = KekService.fastForTests();
  final dek = DekService();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vault_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  EncryptedVault makeVault() =>
      EncryptedVault(file: File('${tempDir.path}/vault.enc'), kek: kek, dek: dek);

  group('EncryptedVault lifecycle', () {
    test('create() writes header and persists', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      expect(vault.file.existsSync(), isTrue);
      expect(vault.isUnlocked, isTrue);
    });

    test('unlock() with correct PIN loads entries', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      await vault.putString('foo', 'bar');
      await vault.flush();
      vault.lock();
      expect(vault.isUnlocked, isFalse);

      await vault.unlock(pin: '123456');
      expect(vault.isUnlocked, isTrue);
      expect(await vault.getString('foo'), 'bar');
    });

    test('unlock() with wrong PIN throws InvalidKeyException', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      await vault.flush();
      vault.lock();
      expect(
        () => vault.unlock(pin: '999999'),
        throwsA(isA<InvalidKeyException>()),
      );
    });
  });

  group('EncryptedVault entries', () {
    test('put/get string round-trip', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      await vault.putString('k', 'value');
      expect(await vault.getString('k'), 'value');
    });

    test('getString returns null for missing key', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      expect(await vault.getString('missing'), isNull);
    });

    test('putBytes round-trip', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      final data = Uint8List.fromList([1, 2, 3, 4]);
      await vault.putBytes('b', data);
      expect(await vault.getBytes('b'), equals(data));
    });

    test('delete removes entry', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      await vault.putString('gone', 'soon');
      await vault.delete('gone');
      expect(await vault.getString('gone'), isNull);
    });
  });

  group('EncryptedVault persistence', () {
    test('flush then reopen preserves data', () async {
      final v1 = makeVault();
      await v1.create(pin: '123456');
      await v1.putString('persisted', 'yes');
      await v1.flush();

      final v2 = makeVault();
      await v2.unlock(pin: '123456');
      expect(await v2.getString('persisted'), 'yes');
    });

    test('flush writes atomically via temp+rename', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      await vault.flush();
      final tmp = File('${tempDir.path}/vault.enc.tmp');
      expect(tmp.existsSync(), isFalse, reason: 'temp file must be renamed');
    });
  });

  group('EncryptedVault changePin', () {
    test('re-wraps DEK under new PIN without touching entries', () async {
      final vault = makeVault();
      await vault.create(pin: '111111');
      await vault.putString('k', 'v');
      await vault.changePin(oldPin: '111111', newPin: '222222');
      await vault.flush();
      vault.lock();

      await vault.unlock(pin: '222222');
      expect(await vault.getString('k'), 'v');
    });

    test('changePin with wrong old PIN fails', () async {
      final vault = makeVault();
      await vault.create(pin: '111111');
      expect(
        () => vault.changePin(oldPin: '000000', newPin: '222222'),
        throwsA(isA<InvalidKeyException>()),
      );
    });
  });

  group('EncryptedVault wipe', () {
    test('wipe deletes file and locks vault', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      await vault.flush();
      await vault.wipe();
      expect(vault.file.existsSync(), isFalse);
      expect(vault.isUnlocked, isFalse);
    });
  });
}
