import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  static const _keyEmail = 'auth_email';
  static const _keyAuthHash = 'auth_hash';
  static const _keyServerUrl = 'auth_server_url';

  static Future<void> saveCredentials({
    required String email,
    required String authHash,
    required String serverUrl,
  }) async {
    await Future.wait([
      _storage.write(key: _keyEmail, value: email),
      _storage.write(key: _keyAuthHash, value: authHash),
      _storage.write(key: _keyServerUrl, value: serverUrl),
    ]);
  }

  static Future<({String email, String authHash, String serverUrl})?> loadCredentials() async {
    final results = await Future.wait([
      _storage.read(key: _keyEmail),
      _storage.read(key: _keyAuthHash),
      _storage.read(key: _keyServerUrl),
    ]);
    final email = results[0];
    final authHash = results[1];
    final serverUrl = results[2];
    if (email == null || authHash == null || serverUrl == null) return null;
    return (email: email, authHash: authHash, serverUrl: serverUrl);
  }

  static Future<void> clearCredentials() async {
    await Future.wait([
      _storage.delete(key: _keyEmail),
      _storage.delete(key: _keyAuthHash),
      _storage.delete(key: _keyServerUrl),
    ]);
  }
}
