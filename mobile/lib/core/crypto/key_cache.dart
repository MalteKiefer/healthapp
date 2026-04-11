import 'dart:typed_data';

/// In-memory key cache for the E2E crypto pipeline.
///
/// Holds the user's PEK, identity key material, and unwrapped profile
/// keys for the lifetime of the app session. Nothing is persisted — this
/// class is cleared on logout or wipe.
///
/// Singleton: access via [E2eKeyCache.instance].
class E2eKeyCache {
  E2eKeyCache._();

  static final E2eKeyCache instance = E2eKeyCache._();

  /// Personal Encryption Key (32-byte AES-256) — derived from the
  /// passphrase + per-user salt via PBKDF2. Used to unwrap the identity
  /// private key.
  Uint8List? pek;

  /// Raw 32-byte P-256 private scalar for this user's identity key.
  Uint8List? identityPrivateScalar;

  /// Raw 65-byte uncompressed P-256 public key (0x04 || X || Y) for
  /// this user's identity key.
  Uint8List? identityPublicRaw;

  /// Current logged-in user id (used to compute self-grant contexts).
  String? currentUserId;

  /// Base64-encoded public identity key of the current user, as stored
  /// on the server. Convenience for UI/debug.
  String? currentUserIdentityPubkeyBase64;

  final Map<String, Uint8List> _profileKeys = <String, Uint8List>{};

  /// Store an unwrapped 32-byte profile key.
  void putProfileKey(String profileId, Uint8List key) {
    _profileKeys[profileId] = key;
  }

  /// Fetch a previously unwrapped profile key, or null if not cached.
  Uint8List? getProfileKey(String profileId) => _profileKeys[profileId];

  /// Whether a profile key is currently cached for [profileId].
  bool hasProfileKey(String profileId) =>
      _profileKeys.containsKey(profileId);

  /// Wipe all cached key material. Call on logout, passphrase change,
  /// or explicit wipe.
  void clear() {
    pek = null;
    identityPrivateScalar = null;
    identityPublicRaw = null;
    currentUserId = null;
    currentUserIdentityPubkeyBase64 = null;
    _profileKeys.clear();
  }
}
