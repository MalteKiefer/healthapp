import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/pointycastle.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

class AuthCrypto {
  /// Legacy derivation: PBKDF2 with salt = SHA256(email.lowercase).
  /// Kept for backward compatibility during rollout of server-provided salts.
  static String deriveAuthHash(String passphrase, String email) {
    // Step 1: SHA-256(email.lowercase) as salt
    final emailBytes = utf8.encode(email.toLowerCase().trim());
    final sha256 = SHA256Digest();
    final salt = sha256.process(Uint8List.fromList(emailBytes));

    // Step 2: PBKDF2-HMAC-SHA256, 600k iterations, 256 bits
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(Pbkdf2Parameters(salt, 600000, 32));
    final hash = pbkdf2.process(Uint8List.fromList(utf8.encode(passphrase)));

    // Step 3: base64 encode
    return base64.encode(hash);
  }

  /// Fetches the server-side PBKDF2 salt for the given email.
  /// Falls back to SHA256(email.lowercase) if the endpoint is unreachable
  /// (legacy servers during rollout).
  static Future<Uint8List> fetchSalt({
    required Future<Map<String, dynamic>> Function(String path) getJson,
    required String email,
  }) async {
    try {
      final resp = await getJson('/api/v1/auth/salt?email=$email');
      final hex = resp['salt'] as String;
      return _hexToBytes(hex);
    } catch (_) {
      // Legacy fallback: SHA256(email.lowercase)
      final emailBytes = utf8.encode(email.toLowerCase().trim());
      return SHA256Digest().process(Uint8List.fromList(emailBytes));
    }
  }

  /// Derives the auth hash using a caller-provided salt (v2 path).
  /// Same PBKDF2-HMAC-SHA256 parameters as [deriveAuthHash]:
  /// 600k iterations, 256-bit output, base64-encoded.
  static String deriveAuthHashWithSalt(String password, Uint8List salt) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(Pbkdf2Parameters(salt, 600000, 32));
    final hash = pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
    return base64.encode(hash);
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
