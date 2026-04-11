import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'base64_util.dart';

/// Personal Encryption Key (PEK) derivation.
///
/// Mirrors the web client's `derivePEK` in `web/src/crypto/keys.ts`, which
/// derives a 32-byte AES-256-GCM key from the user's passphrase and a
/// per-user salt using PBKDF2-SHA256 with 600000 iterations.
class PekCrypto {
  PekCrypto._();

  /// PBKDF2 iterations. Must match the web client exactly.
  static const int pbkdf2Iterations = 600000;

  /// AES-256 key length in bytes.
  static const int keyLengthBytes = 32;

  /// Derives a 32-byte AES-256 key from the user's passphrase and the
  /// server-provided `pekSalt` (base64-encoded). Uses PBKDF2-SHA256 with
  /// 600000 iterations to match the web client exactly.
  ///
  /// The returned bytes MUST be the same as
  /// `crypto.subtle.deriveKey({name:'PBKDF2', salt, iterations:600000, hash:'SHA-256'}, ..., {name:'AES-GCM', length:256})`
  /// exports when WebCrypto runs the equivalent call.
  static Future<Uint8List> derivePek(
    String passphrase,
    String pekSaltBase64,
  ) async {
    final salt = base64DecodeTolerant(pekSaltBase64);

    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: pbkdf2Iterations,
      bits: keyLengthBytes * 8,
    );

    final secret = SecretKey(utf8.encode(passphrase));
    final derived = await pbkdf2.deriveKey(
      secretKey: secret,
      nonce: salt,
    );
    final bytes = await derived.extractBytes();
    return Uint8List.fromList(bytes);
  }
}
