import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';
import 'package:healthapp/core/security/pin/pin_service.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pin_svc_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  PinService makeService() {
    final vault = EncryptedVault(
      file: File('${tempDir.path}/vault.enc'),
      kek: KekService.fastForTests(),
      dek: DekService(),
    );
    return PinService(vault: vault);
  }

  group('PinService.setupPin', () {
    test('rejects non-numeric PIN', () async {
      final s = makeService();
      expect(
        () => s.setupPin('12a456'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects PIN shorter than 6 digits', () async {
      final s = makeService();
      expect(
        () => s.setupPin('12345'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects PIN longer than 6 digits', () async {
      final s = makeService();
      expect(
        () => s.setupPin('1234567'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('creates vault and marks unlocked', () async {
      final s = makeService();
      await s.setupPin('123456');
      expect(s.isUnlocked, isTrue);
    });
  });

  group('PinService.verifyPin', () {
    test('correct PIN unlocks and resets failures', () async {
      final s = makeService();
      await s.setupPin('123456');
      s.lock();
      await s.verifyPin('654321').catchError((_) => false);
      await s.verifyPin('123456');
      expect(s.isUnlocked, isTrue);
      expect(s.failedAttempts, 0);
    });

    test('wrong PIN increments counter', () async {
      final s = makeService();
      await s.setupPin('123456');
      s.lock();
      await expectLater(
        s.verifyPin('111111'),
        throwsA(isA<InvalidKeyException>()),
      );
      expect(s.failedAttempts, 1);
    });

    test('10 wrong PINs sets wipeRequested', () async {
      // Use a mockable clock so we can fast-forward past each lockout
      // window and keep recording failures.
      var fakeNow = DateTime(2026, 4, 10, 12);
      final vault = EncryptedVault(
        file: File('${tempDir.path}/vault.enc'),
        kek: KekService.fastForTests(),
        dek: DekService(),
      );
      final s = PinService(vault: vault, now: () => fakeNow);
      await s.setupPin('123456');
      s.lock();
      for (var i = 0; i < 10; i++) {
        try {
          await s.verifyPin('000000');
        } on InvalidKeyException {
          // expected
        } on LockedOutException {
          // expected after attempt 5; fall through to advance clock
        }
        // Advance past any possible lockout window (>1 h covers all tiers).
        fakeNow = fakeNow.add(const Duration(hours: 2));
      }
      expect(s.wipeRequested, isTrue);
    });

    test('lockout window blocks verifyPin with LockedOutException', () async {
      final s = makeService();
      await s.setupPin('123456');
      s.lock();
      for (var i = 0; i < 5; i++) {
        try {
          await s.verifyPin('000000');
        } catch (_) {}
      }
      expect(
        () => s.verifyPin('123456'),
        throwsA(isA<LockedOutException>()),
      );
    });
  });

  group('PinService.changePin', () {
    test('changePin updates vault without data loss', () async {
      final s = makeService();
      await s.setupPin('111111');
      await s.vault.putString('key', 'val');
      await s.changePin(oldPin: '111111', newPin: '222222');
      s.lock();
      await s.verifyPin('222222');
      expect(await s.vault.getString('key'), 'val');
    });
  });

  group('PinService.wipe', () {
    test('wipe clears vault and counters', () async {
      final s = makeService();
      await s.setupPin('123456');
      await s.wipe();
      expect(s.isUnlocked, isFalse);
      expect(s.failedAttempts, 0);
    });
  });
}
