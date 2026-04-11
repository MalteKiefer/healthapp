import 'dart:io';

import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';
import 'package:path_provider/path_provider.dart';

class StoredCredentials {
  StoredCredentials({
    required this.email,
    required this.authHash,
    required this.serverUrl,
  });

  final String email;
  final String authHash;
  final String serverUrl;
}

class AuthService {
  AuthService({required this.vault});

  final EncryptedVault vault;

  static const _kEmail = 'auth.email.v1';
  static const _kHash = 'auth.hash.v1';
  static const _kServerUrl = 'auth.server_url.v1';

  Future<void> saveCredentials(StoredCredentials c) async {
    await vault.putString(_kEmail, c.email);
    await vault.putString(_kHash, c.authHash);
    await vault.putString(_kServerUrl, c.serverUrl);
    await vault.flush();
  }

  Future<StoredCredentials?> loadCredentials() async {
    final e = await vault.getString(_kEmail);
    final h = await vault.getString(_kHash);
    final u = await vault.getString(_kServerUrl);
    if (e == null || h == null || u == null) return null;
    return StoredCredentials(email: e, authHash: h, serverUrl: u);
  }

  /// Delete stored credentials plus temp-dir cached documents.
  /// The full wipe (vault deletion, keystore cleanup) is handled by
  /// PinService.wipe() — this method only clears mid-session data.
  Future<void> clearCredentials() async {
    await vault.delete(_kEmail);
    await vault.delete(_kHash);
    await vault.delete(_kServerUrl);
    await vault.flush();
    try {
      final tmp = await getTemporaryDirectory();
      if (tmp.existsSync()) {
        for (final f in tmp.listSync()) {
          if (f is File) {
            try {
              f.deleteSync();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }
}
