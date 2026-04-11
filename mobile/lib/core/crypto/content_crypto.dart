import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Profile content encryption primitive — AES-256-GCM with AAD bound to
/// (profileId, entityType, rowId) to prevent row/profile swap attacks.
///
/// Must match `web/src/crypto/content.ts` byte-for-byte.
///
/// Wire format: `base64(iv(12) || ciphertext || tag(16))`.
class ContentCrypto {
  ContentCrypto._();

  static const int _ivLength = 12;
  static const int _tagLength = 16;

  /// Build the AAD binding a decrypted content blob to its row identity.
  /// Must match web's `makeAAD` byte-for-byte.
  static Uint8List buildAad(
    String profileId,
    String entityType,
    String rowId,
  ) {
    final s = 'healthvault:v1:$profileId:$entityType:$rowId';
    return Uint8List.fromList(utf8.encode(s));
  }

  /// Decrypt a `content_enc` blob for a row. Returns the parsed JSON map.
  ///
  /// Throws [StateError] on AES-GCM tag mismatch (wrong key, tampered
  /// ciphertext, or AAD mismatch such as a row-swap).
  static Future<Map<String, dynamic>> decrypt({
    required String contentEncBase64,
    required Uint8List profileKey,
    required String profileId,
    required String entityType,
    required String rowId,
  }) async {
    final combined = base64Decode(contentEncBase64);
    if (combined.length < _ivLength + _tagLength) {
      throw StateError('content_enc too short');
    }
    final iv = combined.sublist(0, _ivLength);
    final tag = combined.sublist(combined.length - _tagLength);
    final ct = combined.sublist(_ivLength, combined.length - _tagLength);

    final aad = buildAad(profileId, entityType, rowId);
    final aesGcm = AesGcm.with256bits();
    final secretBox = SecretBox(ct, nonce: iv, mac: Mac(tag));

    final List<int> plaintext;
    try {
      plaintext = await aesGcm.decrypt(
        secretBox,
        secretKey: SecretKey(profileKey),
        aad: aad,
      );
    } on SecretBoxAuthenticationError {
      throw StateError(
        'content_enc AES-GCM authentication failed '
        '(wrong key, tampered blob, or AAD mismatch)',
      );
    }

    final decoded = json.decode(utf8.decode(plaintext));
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw StateError(
      'decrypted content is not a JSON object (got ${decoded.runtimeType})',
    );
  }

  /// Encrypt a content map for a row. Returns the base64 wire format.
  static Future<String> encrypt({
    required Map<String, dynamic> content,
    required Uint8List profileKey,
    required String profileId,
    required String entityType,
    required String rowId,
  }) async {
    final aad = buildAad(profileId, entityType, rowId);
    final plaintext = Uint8List.fromList(utf8.encode(json.encode(content)));

    final aesGcm = AesGcm.with256bits();
    final secretBox = await aesGcm.encrypt(
      plaintext,
      secretKey: SecretKey(profileKey),
      aad: aad,
      // AesGcm.with256bits() generates a random 12-byte nonce when
      // `nonce` is omitted.
    );

    final iv = secretBox.nonce;
    final ct = secretBox.cipherText;
    final tag = secretBox.mac.bytes;
    if (iv.length != _ivLength) {
      throw StateError('unexpected IV length ${iv.length}');
    }
    if (tag.length != _tagLength) {
      throw StateError('unexpected tag length ${tag.length}');
    }

    final out = Uint8List(iv.length + ct.length + tag.length);
    out.setRange(0, iv.length, iv);
    out.setRange(iv.length, iv.length + ct.length, ct);
    out.setRange(iv.length + ct.length, out.length, tag);
    return base64Encode(out);
  }
}
