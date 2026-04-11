import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';

/// Holds the raw material of a P-256 identity key pair.
///
/// - [privateScalar] is the 32-byte raw private key scalar (d).
/// - [publicKeyRaw] is the 65-byte uncompressed point (0x04 || X || Y)
///   used by the web client's `exportPublicKey`.
class IdentityKeyPair {
  final Uint8List privateScalar;
  final Uint8List publicKeyRaw;
  const IdentityKeyPair({
    required this.privateScalar,
    required this.publicKeyRaw,
  });
}

/// P-256 (secp256r1) identity key helpers.
///
/// Handles decryption of the server-stored `identity_privkey_enc` blob
/// (AES-GCM over PKCS#8 DER, produced by the web client's
/// `exportPrivateKeyEncrypted`) and parsing of the resulting PKCS#8 DER
/// into raw scalar + uncompressed public point form.
class IdentityKey {
  IdentityKey._();

  /// Decrypts the server-stored `identity_privkey_enc` blob with the
  /// passphrase-derived PEK, parses the resulting PKCS#8 DER, and returns
  /// the raw P-256 private scalar plus the reconstructed public key bytes.
  ///
  /// Throws [FormatException] if the PKCS#8 cannot be parsed.
  /// Throws [StateError] if AES-GCM authentication fails (wrong PEK).
  static Future<IdentityKeyPair> decryptPkcs8(
    String identityPrivkeyEncBase64,
    Uint8List pek,
  ) async {
    final combined = base64Decode(identityPrivkeyEncBase64);
    if (combined.length < 12 + 16) {
      throw const FormatException(
        'identity_privkey_enc too short: expected iv(12)||ct||tag(16)',
      );
    }

    final nonce = combined.sublist(0, 12);
    final ctAndTag = combined.sublist(12);
    final tagStart = ctAndTag.length - 16;
    final cipher = ctAndTag.sublist(0, tagStart);
    final tag = ctAndTag.sublist(tagStart);

    final algo = AesGcm.with256bits();
    List<int> plaintext;
    try {
      plaintext = await algo.decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(tag)),
        secretKey: SecretKey(pek),
      );
    } on SecretBoxAuthenticationError catch (e) {
      throw StateError(
        'AES-GCM authentication failed while decrypting identity key: $e',
      );
    }

    return _parsePkcs8(Uint8List.fromList(plaintext));
  }

  /// Utility: parses a base64 uncompressed EC public key (65 bytes,
  /// leading 0x04) into a 64-byte X||Y form suitable for cryptography's
  /// SimplePublicKey. Throws FormatException on malformed input.
  static Uint8List parsePublicKeyRaw(String publicKeyBase64) {
    final bytes = base64Decode(publicKeyBase64);
    if (bytes.length != 65) {
      throw FormatException(
        'Public key must be 65 bytes (uncompressed 0x04||X||Y), got ${bytes.length}',
      );
    }
    if (bytes[0] != 0x04) {
      throw FormatException(
        'Public key must be uncompressed (leading 0x04), got 0x${bytes[0].toRadixString(16)}',
      );
    }
    return Uint8List.fromList(bytes.sublist(1));
  }

  // ---------------------------------------------------------------------------
  // PKCS#8 parsing
  // ---------------------------------------------------------------------------

  /// Walks the PKCS#8 DER tree emitted by WebCrypto's
  /// `crypto.subtle.exportKey('pkcs8', p256PrivateKey)`:
  ///
  /// ```
  /// SEQUENCE {
  ///   INTEGER 0                        -- version
  ///   SEQUENCE {
  ///     OID 1.2.840.10045.2.1          -- ecPublicKey
  ///     OID 1.2.840.10045.3.1.7        -- prime256v1
  ///   }
  ///   OCTET STRING {                   -- privateKeyInfo.privateKey
  ///     SEQUENCE {
  ///       INTEGER 1                    -- ECPrivateKey version
  ///       OCTET STRING                 -- 32-byte raw private scalar (d)
  ///       [1] IMPLICIT BIT STRING      -- 65-byte uncompressed public point (optional)
  ///     }
  ///   }
  /// }
  /// ```
  static IdentityKeyPair _parsePkcs8(Uint8List der) {
    try {
      final topParser = ASN1Parser(der);
      final top = topParser.nextObject();
      if (top is! ASN1Sequence) {
        throw const FormatException('PKCS#8: top-level is not SEQUENCE');
      }
      if (top.elements == null || top.elements!.length < 3) {
        throw const FormatException(
          'PKCS#8: top SEQUENCE must have at least 3 elements',
        );
      }

      // elements[0] = version INTEGER 0
      // elements[1] = AlgorithmIdentifier SEQUENCE
      // elements[2] = OCTET STRING containing ECPrivateKey SEQUENCE
      final privKeyOctet = top.elements![2];
      if (privKeyOctet is! ASN1OctetString) {
        throw const FormatException(
          'PKCS#8: privateKey field is not OCTET STRING',
        );
      }
      final inner = privKeyOctet.valueBytes;
      if (inner == null) {
        throw const FormatException(
          'PKCS#8: privateKey OCTET STRING has no value',
        );
      }

      final innerParser = ASN1Parser(Uint8List.fromList(inner));
      final ecPrivateKey = innerParser.nextObject();
      if (ecPrivateKey is! ASN1Sequence) {
        throw const FormatException(
          'PKCS#8: inner ECPrivateKey is not SEQUENCE',
        );
      }
      final ecElements = ecPrivateKey.elements;
      if (ecElements == null || ecElements.length < 2) {
        throw const FormatException(
          'PKCS#8: ECPrivateKey SEQUENCE must have at least 2 elements',
        );
      }

      // ecElements[0] = INTEGER 1 (ECPrivateKey version)
      // ecElements[1] = OCTET STRING 32-byte private scalar d
      final scalarOct = ecElements[1];
      if (scalarOct is! ASN1OctetString || scalarOct.valueBytes == null) {
        throw const FormatException(
          'PKCS#8: private scalar field is not OCTET STRING',
        );
      }
      final rawScalar = scalarOct.valueBytes!;
      // Left-pad to 32 bytes if encoder stripped leading zeros (rare).
      final privateScalar = Uint8List(32);
      if (rawScalar.length > 32) {
        throw FormatException(
          'PKCS#8: private scalar too long (${rawScalar.length} bytes)',
        );
      }
      privateScalar.setRange(
        32 - rawScalar.length,
        32,
        rawScalar,
      );

      // Look for optional [1] context-tagged public key.
      Uint8List? publicKeyRaw;
      for (var i = 2; i < ecElements.length; i++) {
        final el = ecElements[i];
        final bytes = _tryExtractContextTaggedPublicKey(el);
        if (bytes != null) {
          publicKeyRaw = bytes;
          break;
        }
      }

      publicKeyRaw ??= _derivePublicKeyFromScalar(privateScalar);

      return IdentityKeyPair(
        privateScalar: privateScalar,
        publicKeyRaw: publicKeyRaw,
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Failed to parse PKCS#8 DER: $e');
    }
  }

  /// The optional public key in ECPrivateKey is:
  ///
  ///   publicKey [1] BIT STRING OPTIONAL
  ///
  /// In DER this becomes a context-specific, constructed tag `0xA1`.
  /// Different ASN1 libraries may surface this as ASN1BitString, an
  /// ASN1OctetString, or a raw ASN1Object — so we sniff on encoded bytes.
  static Uint8List? _tryExtractContextTaggedPublicKey(ASN1Object el) {
    // Fast paths: recognised decoded types.
    if (el is ASN1BitString) {
      final bs = el.stringValues ?? el.valueBytes;
      if (bs != null && bs.isNotEmpty) {
        final list = List<int>.from(bs);
        // BIT STRING value often starts with the "unused bits" byte (0x00).
        // In the WebCrypto PKCS#8 form that byte is 0 and the rest is the
        // 65-byte 0x04||X||Y point, but ASN1BitString implementations vary
        // in whether they include that leading byte or not.
        if (list.length == 66 && list.first == 0x00 && list[1] == 0x04) {
          return Uint8List.fromList(list.sublist(1));
        }
        if (list.length == 65 && list.first == 0x04) {
          return Uint8List.fromList(list);
        }
      }
    }

    // Generic fallback: inspect encoded bytes for context-specific tag [1].
    final encoded = el.encodedBytes;
    if (encoded != null && encoded.isNotEmpty && encoded.first == 0xA1) {
      // Inside [1] lives a BIT STRING whose content is (unused=0x00) || 0x04 || X || Y.
      // Scan for the 0x04 uncompressed marker near the end.
      for (var i = 0; i < encoded.length; i++) {
        if (encoded[i] == 0x04 && encoded.length - i >= 65) {
          final candidate = encoded.sublist(i, i + 65);
          if (candidate.length == 65 && candidate.first == 0x04) {
            return Uint8List.fromList(candidate);
          }
        }
      }
    }
    return null;
  }

  /// Fallback: compute the public key by scalar-multiplying the
  /// secp256r1 base point with the given private scalar.
  static Uint8List _derivePublicKeyFromScalar(Uint8List scalar) {
    final curve = ECCurve_secp256r1();
    final d = _bytesToUnsignedBigInt(scalar);
    final q = curve.G * d;
    if (q == null) {
      throw const FormatException(
        'Failed to derive public key: scalar multiplication returned null',
      );
    }
    final encoded = q.getEncoded(false); // false => uncompressed 0x04||X||Y
    if (encoded.length != 65 || encoded.first != 0x04) {
      throw FormatException(
        'Derived public key is not uncompressed 65 bytes (got ${encoded.length})',
      );
    }
    return Uint8List.fromList(encoded);
  }

  /// Decodes an unsigned big-endian byte array into a [BigInt].
  /// Local replacement for `pointycastle/src/utils.dart` helpers to avoid
  /// importing from another package's `lib/src` directory.
  static BigInt _bytesToUnsignedBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b & 0xff);
    }
    return result;
  }
}
