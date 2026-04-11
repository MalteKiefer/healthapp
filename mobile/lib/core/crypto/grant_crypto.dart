import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/ecc/api.dart'
    show ECDomainParameters, ECPrivateKey, ECPublicKey;
import 'package:pointycastle/ecc/curves/prime256v1.dart'
    show ECCurve_prime256v1;
import 'package:pointycastle/ecc/ecdh.dart';

import 'base64_util.dart';

/// Grant unwrap primitive: ECDH(P-256) + HKDF(SHA-256) + AES-GCM
/// unwrap of a 32-byte Profile Key.
///
/// Must produce the same bytes as `receiveKeyGrant` in
/// `web/src/crypto/sharing.ts`.
///
/// ## Implementation note
///
/// The `package:cryptography` factory `Ecdh.p256(...)` resolves to
/// `DartEcdh` on non-browser platforms, and `DartEcdh` throws
/// `UnimplementedError` for both `newKeyPairFromSeed` and
/// `sharedSecretKey`. On Flutter mobile (no `BrowserEcdh`, no
/// `cryptography_flutter`) the only in-process P-256 primitive that
/// actually runs is the one provided by `package:pointycastle`.
///
/// So the pipeline used below is:
///
///   1. Pointycastle ECDHBasicAgreement on curve `prime256v1` to derive
///      the raw shared secret (X coordinate, encoded as a 32-byte
///      big-endian integer — this matches WebCrypto's raw ECDH output).
///   2. `package:cryptography` `Hkdf(hmac: Hmac.sha256(), outputLength:
///      32)` with `nonce` = salt and `info` = info (same `info`/`salt`
///      byte strings as the web client).
///   3. `package:cryptography` `AesGcm.with256bits()` to decrypt the
///      wrapped blob.
class GrantCrypto {
  GrantCrypto._();

  /// Build the exact context string used by `HealthVault-ProfileKeyGrant-v1`
  /// HKDF derivation. Must match the web client byte-for-byte.
  static String grantContext(
    String profileId,
    String granterId,
    String granteeId,
  ) {
    if (granterId == granteeId) return 'selfgrant:$granterId';
    return '$profileId:$granterId:$granteeId';
  }

  /// Unwrap a grant `encrypted_key` blob into the raw 32-byte profile key.
  ///
  /// [myPrivateScalar] is the 32-byte P-256 private scalar (from
  /// `IdentityKeyPair.privateScalar`).
  /// [granterPublicKeyRaw] is the granter's 65-byte uncompressed P-256
  /// public key (0x04 prefix). Caller must base64-decode first.
  /// [wrappedKeyBase64] is the `grant.encrypted_key` value from the
  /// `/my-grant` endpoint.
  /// [context] is the [grantContext] output.
  static Future<Uint8List> unwrapProfileKey({
    required Uint8List myPrivateScalar,
    required Uint8List granterPublicKeyRaw,
    required String wrappedKeyBase64,
    required String context,
  }) async {
    if (myPrivateScalar.length != 32) {
      throw ArgumentError(
        'myPrivateScalar must be 32 bytes, got ${myPrivateScalar.length}',
      );
    }
    if (granterPublicKeyRaw.length != 65 || granterPublicKeyRaw[0] != 0x04) {
      throw ArgumentError(
        'granterPublicKeyRaw must be 65-byte uncompressed P-256 '
        '(0x04||X||Y), got ${granterPublicKeyRaw.length} bytes',
      );
    }

    // Step 1: ECDH (pointycastle) — raw shared secret = X coordinate,
    // 32 bytes big-endian.
    final sharedBits = _ecdhP256(myPrivateScalar, granterPublicKeyRaw);

    // Step 2: HKDF-SHA256 → 32-byte wrapping key.
    final salt = Uint8List.fromList(
      utf8.encode('HealthVault-ProfileKeyGrant-v1'),
    );
    final info = Uint8List.fromList(
      utf8.encode('HealthVault ProfileKeyGrant v1 $context'),
    );
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final wrappingKeyData = await hkdf.deriveKey(
      secretKey: SecretKey(sharedBits),
      nonce: salt,
      info: info,
    );
    final wrappingKeyBytes = await wrappingKeyData.extractBytes();

    // Step 3: AES-256-GCM decrypt the wrapped blob.
    // Wire format: base64(iv(12) || ciphertext || tag(16)).
    final blob = base64DecodeTolerant(wrappedKeyBase64);
    if (blob.length < 12 + 16) {
      throw StateError('wrapped key blob too short');
    }
    final iv = blob.sublist(0, 12);
    final tag = blob.sublist(blob.length - 16);
    final ct = blob.sublist(12, blob.length - 16);

    final aesGcm = AesGcm.with256bits();
    final secretBox = SecretBox(ct, nonce: iv, mac: Mac(tag));
    final List<int> plaintext;
    try {
      plaintext = await aesGcm.decrypt(
        secretBox,
        secretKey: SecretKey(wrappingKeyBytes),
        // No AAD for the grant unwrap — web uses `wrapKey`/`unwrapKey`
        // without additionalData.
      );
    } on SecretBoxAuthenticationError {
      throw StateError(
        'grant unwrap failed: AES-GCM authentication tag mismatch',
      );
    }
    if (plaintext.length != 32) {
      throw StateError(
        'unwrapped profile key must be 32 bytes, got ${plaintext.length}',
      );
    }
    return Uint8List.fromList(plaintext);
  }

  // ---------------------------------------------------------------------
  // Internal: raw P-256 ECDH via pointycastle.
  // ---------------------------------------------------------------------

  /// Derives the raw ECDH shared secret for P-256 as a 32-byte
  /// big-endian X coordinate. This matches what WebCrypto returns from
  /// `crypto.subtle.deriveBits({name:'ECDH'}, ..., 256)`.
  static Uint8List _ecdhP256(
    Uint8List privateScalar,
    Uint8List publicKeyRaw,
  ) {
    // Use the concrete curve class so we do not depend on the
    // pointycastle runtime registry having been populated.
    final ECDomainParameters domain = ECCurve_prime256v1();

    // Private scalar as BigInt (big-endian).
    final d = _bytesToBigInt(privateScalar);
    final privKey = ECPrivateKey(d, domain);

    // Public key: decode uncompressed point (0x04 || X || Y).
    final Q = domain.curve.decodePoint(publicKeyRaw);
    if (Q == null || Q.isInfinity) {
      throw ArgumentError('granter public key decodes to infinity');
    }
    final pubKey = ECPublicKey(Q, domain);

    final agreement = ECDHBasicAgreement()..init(privKey);
    final sharedX = agreement.calculateAgreement(pubKey);

    // Convert to 32-byte big-endian (field size for P-256 is 32).
    return _bigIntToFixedBytes(sharedX, 32);
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static Uint8List _bigIntToFixedBytes(BigInt value, int length) {
    if (value.isNegative) {
      throw ArgumentError('value must be non-negative');
    }
    final out = Uint8List(length);
    var v = value;
    final mask = BigInt.from(0xff);
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (v & mask).toInt();
      v = v >> 8;
    }
    if (v != BigInt.zero) {
      throw ArgumentError('value does not fit in $length bytes');
    }
    return out;
  }
}
