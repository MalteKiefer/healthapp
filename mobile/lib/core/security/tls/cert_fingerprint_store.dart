import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';

/// Stores TOFU SPKI-SHA256 fingerprints per hostname inside the
/// encrypted vault. Hostnames are the vault key suffix.
class CertFingerprintStore {
  CertFingerprintStore({required this.vault});

  final EncryptedVault vault;

  static const String _prefix = 'tofu.pin.v1.';

  Future<String?> expected(String host) =>
      vault.getString('$_prefix$host');

  Future<void> save(String host, String fingerprint) async {
    await vault.putString('$_prefix$host', fingerprint);
    await vault.flush();
  }

  Future<void> delete(String host) async {
    await vault.delete('$_prefix$host');
    await vault.flush();
  }
}
