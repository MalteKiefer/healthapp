import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/pointycastle.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

class AuthCrypto {
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
}
