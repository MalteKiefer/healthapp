import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class InvalidKeyException implements Exception {
  const InvalidKeyException();
  @override
  String toString() => 'InvalidKeyException';
}

/// Generates a 256-bit DEK and (un)wraps it using AES-256-GCM under a
/// 32-byte KEK. Wire format: nonce(12) || ciphertext || tag(16).
class DekService {
  DekService();

  static const int _dekLength = 32;
  static const int _nonceLength = 12;
  static const int _tagLength = 16;

  final AesGcm _aes = AesGcm.with256bits();

  Uint8List generateDek() {
    final data = SecretKeyData.random(length: _dekLength);
    return Uint8List.fromList(data.bytes);
  }

  Future<Uint8List> wrap(Uint8List dek, Uint8List kek) async {
    _checkLength(dek, _dekLength, 'dek');
    _checkLength(kek, _dekLength, 'kek');

    final nonce = _aes.newNonce();
    final secret = SecretKey(kek);
    final box = await _aes.encrypt(dek, secretKey: secret, nonce: nonce);

    return Uint8List.fromList([
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Future<Uint8List> unwrap(Uint8List wrapped, Uint8List kek) async {
    _checkLength(kek, _dekLength, 'kek');
    if (wrapped.length < _nonceLength + _tagLength) {
      throw const InvalidKeyException();
    }

    final nonce = wrapped.sublist(0, _nonceLength);
    final tagStart = wrapped.length - _tagLength;
    final cipher = wrapped.sublist(_nonceLength, tagStart);
    final tag = wrapped.sublist(tagStart);

    try {
      final secret = SecretKey(kek);
      final box = SecretBox(cipher, nonce: nonce, mac: Mac(tag));
      final plain = await _aes.decrypt(box, secretKey: secret);
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const InvalidKeyException();
    }
  }

  void _checkLength(Uint8List bytes, int expected, String name) {
    if (bytes.length != expected) {
      throw ArgumentError.value(
        bytes.length,
        '$name.length',
        'expected $expected bytes',
      );
    }
  }
}
