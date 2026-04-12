import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';

import 'base64_util.dart';
import 'content_crypto.dart';
import 'content_fields.dart';
import 'grant_crypto.dart';
import 'identity_key.dart';
import 'key_cache.dart';
import 'pek.dart';

const _uuid = Uuid();

/// Result of [E2eCryptoService.encryptForWrite]: the row id to use
/// (client-generated for inserts), the `content_enc` blob to send, and
/// the structural (non-content) fields that remain plaintext.
class EncryptedWrite {
  EncryptedWrite({
    required this.id,
    required this.contentEnc,
    required this.structural,
  });

  final String id;
  final String? contentEnc;
  final Map<String, dynamic> structural;

  /// Build the JSON body for a POST/PATCH call: spreads the structural
  /// fields, always includes `id`, and adds `content_enc` when a blob
  /// was produced.
  Map<String, dynamic> toBody() => <String, dynamic>{
        ...structural,
        'id': id,
        if (contentEnc != null) 'content_enc': contentEnc,
      };
}

/// End-to-end crypto facade: orchestrates PEK → identity → profile keys →
/// content decryption. Depends on an [ApiClient] for fetching grants.
class E2eCryptoService {
  E2eCryptoService(this._api);

  final ApiClient _api;

  /// Called from LoginScreen after `/auth/login` returns 200. Derives
  /// the PEK, decrypts the identity private key, and stashes both in
  /// the key cache along with user identity fields so subsequent
  /// profile-key unwrap calls succeed.
  ///
  /// Any failure throws — callers should present a generic
  /// "could not unlock keys" error.
  Future<void> unlockWithPassword({
    required String passphrase,
    required String pekSaltBase64,
    required String identityPrivkeyEnc,
    required String userId,
    required String identityPubkeyBase64,
  }) async {
    final pek = await PekCrypto.derivePek(passphrase, pekSaltBase64);
    final kp = await IdentityKey.decryptPkcs8(identityPrivkeyEnc, pek);
    final cache = E2eKeyCache.instance;
    cache.pek = pek;
    cache.identityPrivateScalar = kp.privateScalar;
    cache.identityPublicRaw = kp.publicKeyRaw;
    cache.currentUserId = userId;
    cache.currentUserIdentityPubkeyBase64 = identityPubkeyBase64;

    // Consistency check: verify d*G == extracted public key.
    final curve = ECCurve_secp256r1();
    var d = BigInt.zero;
    for (final b in kp.privateScalar) {
      d = (d << 8) | BigInt.from(b);
    }
    final derivedQ = curve.G * d;
    final derivedPub = Uint8List.fromList(derivedQ!.getEncoded(false));
    final scalarMatchesPub = _bytesEqual(derivedPub, kp.publicKeyRaw);
    debugPrint('[e2e] unlock: scalar↔pubkey consistent: $scalarMatchesPub');
    if (!scalarMatchesPub) {
      debugPrint('[e2e]   derived[0..4]: ${derivedPub.sublist(0, 5)}');
      debugPrint('[e2e]   pkcs8[0..4]:   ${kp.publicKeyRaw.sublist(0, 5)}');
    }
  }

  /// Lazy profile key resolver. Checks the cache first; on miss, calls
  /// `GET /api/v1/profiles/{id}/my-grant`, unwraps the grant via ECDH
  /// against the cached identity private key, and stores the resulting
  /// profile AES key in the cache.
  ///
  /// Returns null if the current session does not have the identity
  /// private key cached (caller should show a re-login prompt) or if
  /// the server responds with 404 (no active grant — unusual for a
  /// normal profile, caller can surface a warning).
  ///
  /// Any other error is rethrown.
  Future<Uint8List?> ensureProfileKey(String profileId) async {
    final cache = E2eKeyCache.instance;
    final cached = cache.getProfileKey(profileId);
    if (cached != null) return cached;
    final priv = cache.identityPrivateScalar;
    final userId = cache.currentUserId;
    if (priv == null || userId == null) {
      debugPrint('[e2e] ensureProfileKey($profileId): identity not unlocked');
      return null;
    }

    try {
      final grant = await _api.get<Map<String, dynamic>>(
        '/api/v1/profiles/$profileId/my-grant',
      );
      final encryptedKey = grant['encrypted_key'] as String;
      final granterId = grant['granted_by_user_id'] as String;
      final granterPubB64 = grant['granter_identity_pubkey'] as String;
      debugPrint('[e2e] DUMP encrypted_key=$encryptedKey');
      debugPrint('[e2e] DUMP granterPub=$granterPubB64');
      debugPrint('[e2e] DUMP granterId=$granterId userId=$userId');
      debugPrint('[e2e] DUMP privScalarHex=${priv.map((b) => b.toRadixString(16).padLeft(2, "0")).join()}');
      final granterPubRaw = _decodePublicKeyRaw(granterPubB64);

      // Diagnostic: for self-grants, verify that the public key from the
      // server matches what we extracted from our PKCS#8 identity key.
      if (granterId == userId) {
        final myPub = cache.identityPublicRaw;
        if (myPub != null) {
          final match = granterPubRaw.length == myPub.length &&
              _bytesEqual(granterPubRaw, myPub);
          debugPrint(
            '[e2e] self-grant pubkey match: $match '
            '(server=${granterPubRaw.length}b, pkcs8=${myPub.length}b)',
          );
          if (!match) {
            debugPrint(
              '[e2e]   server[0..4]: ${granterPubRaw.sublist(0, 5)}',
            );
            debugPrint(
              '[e2e]   pkcs8[0..4]:  ${myPub.sublist(0, 5)}',
            );
          }
        }
      }

      final ctx = GrantCrypto.grantContext(profileId, granterId, userId);
      try {
        final profileKey = await GrantCrypto.unwrapProfileKey(
          myPrivateScalar: priv,
          granterPublicKeyRaw: granterPubRaw,
          wrappedKeyBase64: encryptedKey,
          context: ctx,
        );
        cache.putProfileKey(profileId, profileKey);
        debugPrint('[e2e] ensureProfileKey($profileId): unwrap OK');
        return profileKey;
      } on StateError catch (e) {
        // AES-GCM tag mismatch → stale grant (encrypted with old/different
        // identity keys). We cannot recover the profile key — the existing
        // content_enc data was encrypted with that key and minting a NEW
        // key would make the data permanently unreadable. Return null so
        // screens fall back to showing structural fields.
        debugPrint(
          '[e2e] ensureProfileKey($profileId): stale grant, '
          'cannot unwrap ($e). Open web client to re-sync keys.',
        );
        return null;
      }
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        debugPrint('[e2e] ensureProfileKey($profileId): 404, trying self-grant');
        return _mintSelfGrant(profileId, priv, cache);
      }
      debugPrint('[e2e] ensureProfileKey($profileId): api ${e.statusCode} $e');
      return null;
    } catch (e, st) {
      debugPrint('[e2e] ensureProfileKey($profileId): $e\n$st');
      return null;
    }
  }

  /// Lazy self-grant mint fallback. When no active grant exists for a
  /// profile (404 from /my-grant), generate a fresh 32-byte AES-256
  /// profile key, wrap it via ECDH(myPriv, myPub) + HKDF + AES-GCM,
  /// and POST it as a self-grant to the server. Mirrors the web client's
  /// `ensureProfileKey` 404 fallback in `web/src/crypto/profileKey.ts`.
  ///
  /// Returns the profile key on success, null on failure (logged).
  Future<Uint8List?> _mintSelfGrant(
    String profileId,
    Uint8List priv,
    E2eKeyCache cache,
  ) async {
    final pub = cache.identityPublicRaw;
    final userId = cache.currentUserId;
    if (pub == null || userId == null) {
      debugPrint('[e2e] _mintSelfGrant($profileId): no identity public key');
      return null;
    }

    try {
      // 1. Generate random 32-byte profile key.
      final rng = Random.secure();
      final profileKey = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        profileKey[i] = rng.nextInt(256);
      }

      // 2. Wrap it.
      final ctx = GrantCrypto.grantContext(profileId, userId, userId);
      final wrappedKey = await GrantCrypto.wrapProfileKey(
        profileKey: profileKey,
        myPrivateScalar: priv,
        myPublicKeyRaw: pub,
        context: ctx,
      );

      // 3. POST grant to server (only succeeds if we're the profile owner).
      await _api.post<Map<String, dynamic>>(
        '/api/v1/profiles/$profileId/grants',
        body: <String, dynamic>{
          'grantee_user_id': userId,
          'encrypted_key': wrappedKey,
          'grant_signature': '',
        },
      );

      cache.putProfileKey(profileId, profileKey);
      debugPrint('[e2e] _mintSelfGrant($profileId): OK');
      return profileKey;
    } catch (e, st) {
      debugPrint('[e2e] _mintSelfGrant($profileId): $e\n$st');
      return null;
    }
  }

  /// Helper to turn a base64 P-256 public key into the raw 65-byte
  /// uncompressed form (0x04 || X || Y). Accepts both the 65-byte
  /// uncompressed representation and a bare 64-byte X||Y (some older
  /// encoders omit the leading 0x04). Throws on anything else.
  static Uint8List _decodePublicKeyRaw(String base64PublicKey) {
    final raw = base64DecodeTolerant(base64PublicKey);
    if (raw.length == 65 && raw[0] == 0x04) {
      return raw;
    }
    if (raw.length == 64) {
      final out = Uint8List(65);
      out[0] = 0x04;
      out.setRange(1, 65, raw);
      return out;
    }
    throw FormatException(
      'invalid P-256 public key bytes (len=${raw.length}, '
      'first=${raw.isNotEmpty ? raw[0].toRadixString(16) : "-"})',
    );
  }

  /// Decrypts a single row's `content_enc` field and merges the decrypted
  /// JSON into the row. Mutates the row map in-place and returns it for
  /// chaining. If the row has no `content_enc`, returns it unchanged.
  /// If the profile key is not available, returns the row unchanged so
  /// callers still get the plaintext columns that the server passes
  /// through for legacy rows.
  Future<Map<String, dynamic>> decryptRow({
    required Map<String, dynamic> row,
    required String profileId,
    required String entityType,
  }) async {
    final contentEnc = row['content_enc'] as String?;
    if (contentEnc == null || contentEnc.isEmpty) return row;
    Uint8List? profileKey;
    try {
      profileKey = await ensureProfileKey(profileId);
    } catch (e) {
      debugPrint('[e2e] decryptRow($entityType): key unavailable: $e');
      return row;
    }
    if (profileKey == null) return row;
    final rowId = row['id']?.toString() ?? '';
    if (rowId.isEmpty) return row;
    try {
      final content = await ContentCrypto.decrypt(
        contentEncBase64: contentEnc,
        profileKey: profileKey,
        profileId: profileId,
        entityType: entityType,
        rowId: rowId,
      );
      // Splat decrypted fields onto the row, overwriting any plaintext
      // that might still be present for legacy rows.
      row.addAll(content);
    } catch (_) {
      // Decrypt failure is surfaced as missing fields so the UI shows
      // the existing plaintext fallback (or empty state).
    }
    return row;
  }

  /// Batch variant for list endpoints. Runs decryptRow sequentially
  /// (AES-GCM is fast enough and keeps errors localized per row).
  Future<List<Map<String, dynamic>>> decryptRows({
    required List<dynamic> rows,
    required String profileId,
    required String entityType,
  }) async {
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      if (r is! Map<String, dynamic>) continue;
      out.add(await decryptRow(
        row: r,
        profileId: profileId,
        entityType: entityType,
      ));
    }
    return out;
  }

  /// Encrypt a map of content fields into the wire-format content_enc
  /// blob for a row. Used by write-path providers before POST/PATCH.
  /// Returns null if profile key is unavailable.
  Future<String?> encryptContentFor({
    required Map<String, dynamic> content,
    required String profileId,
    required String entityType,
    required String rowId,
  }) async {
    final profileKey = await ensureProfileKey(profileId);
    if (profileKey == null) return null;
    return ContentCrypto.encrypt(
      content: content,
      profileKey: profileKey,
      profileId: profileId,
      entityType: entityType,
      rowId: rowId,
    );
  }

  /// Build the wire body for a create/update call: splits the plaintext
  /// `body` into a structural half (non-content fields) and an encrypted
  /// `content_enc` blob built from the content fields declared in
  /// [kContentFields] for this `entityType`.
  ///
  /// - For inserts, pass `existingId: null` and a fresh UUID v4 will be
  ///   generated on the client so the AAD can bind the row identity
  ///   before the server sees it.
  /// - For updates, pass the existing row id.
  ///
  /// Returns an [EncryptedWrite]. If the profile key is unavailable
  /// (e.g. user not yet unlocked) the returned `contentEnc` will be null
  /// and all fields will stay in the structural half — matching the web
  /// client's "best-effort" behavior for legacy-mode writes.
  Future<EncryptedWrite> encryptForWrite({
    required String profileId,
    required String entityType,
    required Map<String, dynamic> body,
    String? existingId,
  }) async {
    final fields = kContentFields[entityType];
    if (fields == null) {
      throw ArgumentError(
        'encryptForWrite: no content field list for entity "$entityType"',
      );
    }
    final id = existingId ?? _uuid.v4();

    // Split body into content vs structural halves.
    final content = <String, dynamic>{};
    final structural = <String, dynamic>{};
    body.forEach((k, v) {
      if (k == 'id' || k == 'content_enc') return;
      if (fields.contains(k)) {
        if (v != null) content[k] = v;
      } else {
        structural[k] = v;
      }
    });

    String? contentEnc;
    if (content.isNotEmpty) {
      contentEnc = await encryptContentFor(
        content: content,
        profileId: profileId,
        entityType: entityType,
        rowId: id,
      );
      // If the profile key wasn't available, fall back to sending the
      // plaintext columns so the write still succeeds on legacy servers.
      if (contentEnc == null) {
        structural.addAll(content);
      }
    }

    return EncryptedWrite(
      id: id,
      contentEnc: contentEnc,
      structural: structural,
    );
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Drop all cached key material. Call on logout / wipe.
  void clear() => E2eKeyCache.instance.clear();
}
