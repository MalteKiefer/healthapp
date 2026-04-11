import 'package:healthapp/core/security/key_management/keystore_binding.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';

export 'package:healthapp/core/security/key_management/keystore_binding.dart'
    show BiometricCancelledException, KeystoreUnavailableException;

/// Couples the platform keystore to the vault. Enrolling stores a
/// second DEK-wrap protected by a biometrically gated keystore key;
/// unlocking asks the OS for biometric auth, retrieves that key, and
/// unwraps the DEK.
class BiometricService {
  BiometricService({required this.keystore});

  final KeystoreBinding keystore;

  static const String keyAlias = 'healthvault.dek.bio';

  Future<bool> isAvailable() async {
    // local_auth availability is checked at call time in the UI layer
    // via the LocalAuthentication plugin. At this layer we check the
    // keystore only — existence of a working key implies the device
    // was previously enrolled.
    return keystore.hasKey(keyAlias);
  }

  /// Requires a currently unlocked vault. Creates a bio-bound keystore
  /// key, wraps the in-memory DEK under it, and stores the wrap in the
  /// vault.
  Future<void> enroll({required EncryptedVault vault}) async {
    if (!vault.isUnlocked) {
      throw StateError('Vault must be unlocked to enroll biometrics');
    }
    // If a previous enrollment exists, remove it first.
    if (await keystore.hasKey(keyAlias)) {
      await keystore.deleteKey(keyAlias);
    }
    final bioKey = await keystore.createBioBoundKey(keyAlias);
    await vault.setWrappedDekByBio(bioKey);
    await vault.flush();
  }

  /// Unlocks the vault using the keystore-bound bio key.
  Future<void> unlock({required EncryptedVault vault}) async {
    final bioKey = await keystore.unwrapBioKey(keyAlias);
    await vault.unlockWithBioKey(bioKey);
  }

  /// Remove the keystore entry and the wrapped-bio blob from the vault.
  Future<void> disable({required EncryptedVault vault}) async {
    await keystore.deleteKey(keyAlias);
    vault.clearWrappedDekByBio();
    if (vault.isUnlocked) {
      await vault.flush();
    }
  }
}
