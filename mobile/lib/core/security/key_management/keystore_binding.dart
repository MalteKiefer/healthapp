import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

class BiometricCancelledException implements Exception {
  const BiometricCancelledException();
}

class KeystoreUnavailableException implements Exception {
  const KeystoreUnavailableException();
}

/// Abstracts the platform keystore/keychain. Implementations live in
/// native-backed and fake flavors so tests can run without real
/// biometrics.
abstract class KeystoreBinding {
  Future<bool> hasKey(String alias);

  /// Create a new 32-byte key in the keystore gated by biometric auth.
  /// Returns the raw bytes once (callers must wrap the DEK immediately).
  Future<Uint8List> createBioBoundKey(String alias);

  /// Prompt the OS for biometric auth and return the stored key on
  /// success. Throws [BiometricCancelledException] if the user cancels.
  Future<Uint8List> unwrapBioKey(String alias);

  Future<void> deleteKey(String alias);
}

/// Dart-only fake for tests. Holds keys in memory, no platform calls.
class FakeKeystoreBinding implements KeystoreBinding {
  final Map<String, Uint8List> _store = {};
  bool authorizeNext = true;

  @override
  Future<bool> hasKey(String alias) async => _store.containsKey(alias);

  @override
  Future<Uint8List> createBioBoundKey(String alias) async {
    final key = SecretKeyData.random(length: 32).bytes;
    _store[alias] = Uint8List.fromList(key);
    return Uint8List.fromList(key);
  }

  @override
  Future<Uint8List> unwrapBioKey(String alias) async {
    if (!authorizeNext) {
      throw const BiometricCancelledException();
    }
    final k = _store[alias];
    if (k == null) throw const KeystoreUnavailableException();
    return Uint8List.fromList(k);
  }

  @override
  Future<void> deleteKey(String alias) async {
    _store.remove(alias);
  }
}

/// Real implementation using a MethodChannel to native code. The native
/// side lives in MainActivity.kt (Android) and AppDelegate.swift (iOS),
/// added in Phase 7 of this plan.
class NativeKeystoreBinding implements KeystoreBinding {
  static const _channel = MethodChannel('healthvault.security/keystore');

  @override
  Future<bool> hasKey(String alias) async {
    try {
      return await _channel.invokeMethod<bool>('hasKey', {'alias': alias}) ??
          false;
    } on PlatformException {
      throw const KeystoreUnavailableException();
    }
  }

  @override
  Future<Uint8List> createBioBoundKey(String alias) async {
    try {
      final raw = await _channel
          .invokeMethod<Uint8List>('createBioBoundKey', {'alias': alias});
      if (raw == null) throw const KeystoreUnavailableException();
      return raw;
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') throw const BiometricCancelledException();
      throw const KeystoreUnavailableException();
    }
  }

  @override
  Future<Uint8List> unwrapBioKey(String alias) async {
    try {
      final raw = await _channel
          .invokeMethod<Uint8List>('unwrapBioKey', {'alias': alias});
      if (raw == null) throw const BiometricCancelledException();
      return raw;
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') throw const BiometricCancelledException();
      throw const KeystoreUnavailableException();
    }
  }

  @override
  Future<void> deleteKey(String alias) async {
    try {
      await _channel.invokeMethod('deleteKey', {'alias': alias});
    } on PlatformException {
      // swallow — best effort
    }
  }
}
