import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';

void main() {
  final service = DekService();

  Uint8List key32() => Uint8List.fromList(List.generate(32, (i) => i));
  Uint8List otherKey32() =>
      Uint8List.fromList(List.generate(32, (i) => 255 - i));

  group('DekService.generateDek', () {
    test('returns 32 random bytes', () {
      final dek1 = service.generateDek();
      final dek2 = service.generateDek();
      expect(dek1, hasLength(32));
      expect(dek2, hasLength(32));
      expect(dek1, isNot(equals(dek2)));
    });
  });

  group('DekService wrap/unwrap', () {
    test('round-trip succeeds with correct key', () async {
      final kek = key32();
      final dek = service.generateDek();
      final wrapped = await service.wrap(dek, kek);
      final unwrapped = await service.unwrap(wrapped, kek);
      expect(unwrapped, equals(dek));
    });

    test('different wrap calls produce different ciphertext (nonce unique)',
        () async {
      final kek = key32();
      final dek = service.generateDek();
      final w1 = await service.wrap(dek, kek);
      final w2 = await service.wrap(dek, kek);
      expect(w1, isNot(equals(w2)));
    });

    test('unwrap with wrong key fails with InvalidKeyException', () async {
      final dek = service.generateDek();
      final wrapped = await service.wrap(dek, key32());
      expect(
        () => service.unwrap(wrapped, otherKey32()),
        throwsA(isA<InvalidKeyException>()),
      );
    });

    test('tampered ciphertext fails with InvalidKeyException', () async {
      final dek = service.generateDek();
      final wrapped = await service.wrap(dek, key32());
      wrapped[wrapped.length - 1] ^= 0x01;
      expect(
        () => service.unwrap(wrapped, key32()),
        throwsA(isA<InvalidKeyException>()),
      );
    });
  });
}
