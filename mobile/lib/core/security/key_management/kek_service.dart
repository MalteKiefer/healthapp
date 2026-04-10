import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Derives the Key Encryption Key from a PIN using Argon2id.
class KekService {
  KekService({
    required this.memoryMiB,
    required this.iterations,
    required this.parallelism,
  })  : assert(memoryMiB > 0),
        assert(iterations > 0),
        assert(parallelism > 0);

  factory KekService.production() =>
      KekService(memoryMiB: 64, iterations: 3, parallelism: 4);

  @visibleForTesting
  factory KekService.fastForTests() =>
      KekService(memoryMiB: 1, iterations: 1, parallelism: 1);

  final int memoryMiB;
  final int iterations;
  final int parallelism;

  static const int _saltLength = 16;
  static const int _kekLength = 32;

  Uint8List generateSalt() {
    final bytes = SecretKeyData.random(length: _saltLength).bytes;
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> deriveKek(String pin, Uint8List salt) async {
    if (pin.isEmpty) {
      throw ArgumentError.value(pin, 'pin', 'PIN must not be empty');
    }
    if (salt.length != _saltLength) {
      throw ArgumentError.value(
        salt.length,
        'salt.length',
        'expected $_saltLength bytes',
      );
    }

    final algo = Argon2id(
      memory: memoryMiB * 1024, // cryptography takes memory in KiB blocks
      parallelism: parallelism,
      iterations: iterations,
      hashLength: _kekLength,
    );
    final secret = SecretKey(Uint8List.fromList(pin.codeUnits));
    final derived = await algo.deriveKey(secretKey: secret, nonce: salt);
    final extracted = await derived.extractBytes();
    return Uint8List.fromList(extracted);
  }
}
