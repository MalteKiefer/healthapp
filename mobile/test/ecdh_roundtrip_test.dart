import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/ecc/curves/prime256v1.dart';
import 'package:healthapp/core/crypto/grant_crypto.dart';

void main() {
  test('wrapProfileKey then unwrapProfileKey round-trips', () async {
    final domain = ECCurve_prime256v1();
    
    // Deterministic test private key
    final privScalar = Uint8List(32);
    for (var i = 0; i < 32; i++) privScalar[i] = (i * 7 + 13) % 256;
    
    // Derive public key
    final d = _bytesToBigInt(privScalar);
    final Q = domain.G * d;
    final pubRaw = Uint8List.fromList(Q!.getEncoded(false));
    
    // Test profile key
    final profileKey = Uint8List(32);
    for (var i = 0; i < 32; i++) profileKey[i] = (i * 3 + 42) % 256;
    
    const context = 'selfgrant:test-user-id';
    
    final wrapped = await GrantCrypto.wrapProfileKey(
      profileKey: profileKey,
      myPrivateScalar: privScalar,
      myPublicKeyRaw: pubRaw,
      context: context,
    );
    
    final unwrapped = await GrantCrypto.unwrapProfileKey(
      myPrivateScalar: privScalar,
      granterPublicKeyRaw: pubRaw,
      wrappedKeyBase64: wrapped,
      context: context,
    );
    
    expect(unwrapped, equals(profileKey));
  });
}

BigInt _bytesToBigInt(Uint8List bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}
