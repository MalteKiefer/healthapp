import 'dart:convert';
import 'dart:typed_data';

import '../api/api_client.dart';
import 'content_crypto.dart';
import 'grant_crypto.dart';
import 'identity_key.dart';
import 'key_cache.dart';
import 'pek.dart';

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
    if (priv == null || userId == null) return null;

    try {
      final grant = await _api.get<Map<String, dynamic>>(
        '/api/v1/profiles/$profileId/my-grant',
      );
      final encryptedKey = grant['encrypted_key'] as String;
      final granterId = grant['granted_by_user_id'] as String;
      final granterPubB64 = grant['granter_identity_pubkey'] as String;
      final granterPubRaw = _decodePublicKeyRaw(granterPubB64);
      final ctx = GrantCrypto.grantContext(profileId, granterId, userId);
      final profileKey = await GrantCrypto.unwrapProfileKey(
        myPrivateScalar: priv,
        granterPublicKeyRaw: granterPubRaw,
        wrappedKeyBase64: encryptedKey,
        context: ctx,
      );
      cache.putProfileKey(profileId, profileKey);
      return profileKey;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Helper to turn a base64 P-256 uncompressed public key (65 bytes,
  /// leading 0x04) into raw bytes. Throws on malformed input.
  static Uint8List _decodePublicKeyRaw(String base64PublicKey) {
    final raw = base64Decode(base64PublicKey);
    if (raw.length != 65 || raw[0] != 0x04) {
      throw const FormatException('invalid P-256 public key bytes');
    }
    return raw;
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
    final profileKey = await ensureProfileKey(profileId);
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

  /// Drop all cached key material. Call on logout / wipe.
  void clear() => E2eKeyCache.instance.clear();
}
