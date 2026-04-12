import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HKDF-SHA256 matches RFC 5869 Test Case 1', () async {
    final ikm = Uint8List.fromList(List.filled(22, 0x0b));
    final salt = Uint8List.fromList([0,1,2,3,4,5,6,7,8,9,0xa,0xb,0xc]);
    final info = Uint8List.fromList([0xf0,0xf1,0xf2,0xf3,0xf4,0xf5,0xf6,0xf7,0xf8,0xf9]);

    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 42);
    final result = await hkdf.deriveKey(
      secretKey: SecretKey(ikm),
      nonce: salt,
      info: info,
    );
    final bytes = await result.extractBytes();
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    
    expect(hex, '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865');
  });
}
