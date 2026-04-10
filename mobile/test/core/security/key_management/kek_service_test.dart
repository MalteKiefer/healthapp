import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';

void main() {
  final service = KekService.fastForTests();

  group('KekService.deriveKek', () {
    test('returns deterministic 32-byte key for same pin+salt', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final a = await service.deriveKek('123456', salt);
      final b = await service.deriveKek('123456', salt);
      expect(a, hasLength(32));
      expect(a, equals(b));
    });

    test('different PINs produce different keys', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final a = await service.deriveKek('123456', salt);
      final b = await service.deriveKek('123457', salt);
      expect(a, isNot(equals(b)));
    });

    test('different salts produce different keys', () async {
      final a = await service.deriveKek(
        '123456',
        Uint8List.fromList(List.filled(16, 1)),
      );
      final b = await service.deriveKek(
        '123456',
        Uint8List.fromList(List.filled(16, 2)),
      );
      expect(a, isNot(equals(b)));
    });

    test('rejects salt of wrong length', () async {
      expect(
        () => service.deriveKek('123456', Uint8List(15)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects empty PIN', () async {
      expect(
        () => service.deriveKek('', Uint8List(16)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('KekService.generateSalt', () {
    test('returns 16 bytes', () {
      final s = service.generateSalt();
      expect(s, hasLength(16));
    });

    test('returns different bytes on successive calls', () {
      final a = service.generateSalt();
      final b = service.generateSalt();
      expect(a, isNot(equals(b)));
    });
  });
}
