import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/key_management/keystore_binding.dart';

void main() {
  group('FakeKeystoreBinding', () {
    test('createBioBoundKey stores and returns a key', () async {
      final ks = FakeKeystoreBinding();
      final key = await ks.createBioBoundKey('alias-1');
      expect(key, hasLength(32));
      expect(await ks.hasKey('alias-1'), isTrue);
    });

    test('unwrapBioKey returns the same key when bio is authorized', () async {
      final ks = FakeKeystoreBinding()..authorizeNext = true;
      final stored = await ks.createBioBoundKey('alias-1');
      final retrieved = await ks.unwrapBioKey('alias-1');
      expect(retrieved, equals(stored));
    });

    test('unwrapBioKey fails with BiometricCancelledException when cancelled', () async {
      final ks = FakeKeystoreBinding()..authorizeNext = false;
      await ks.createBioBoundKey('alias-1');
      expect(
        () => ks.unwrapBioKey('alias-1'),
        throwsA(isA<BiometricCancelledException>()),
      );
    });

    test('deleteKey removes it', () async {
      final ks = FakeKeystoreBinding();
      await ks.createBioBoundKey('alias-1');
      await ks.deleteKey('alias-1');
      expect(await ks.hasKey('alias-1'), isFalse);
    });
  });
}
