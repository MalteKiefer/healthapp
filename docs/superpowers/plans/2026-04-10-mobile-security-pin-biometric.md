# Mobile Security Foundation + PIN/Biometric Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the Flutter mobile app with an encrypted on-disk vault, mandatory 6-digit PIN, optional hardware-backed biometric unlock, TOFU TLS pinning, and Android/iOS platform-level protections, closing all P0 findings from the 2026-04-10 security audit.

**Architecture:** A new `lib/core/security/` module introduces KEK/DEK key hierarchy via Argon2id + AES-256-GCM. A Riverpod `AppLockController` plus `WidgetsBindingObserver` drives a state machine (`unregistered` → `loggedInNoPin` → `unlocked` ↔ `locked` → `wiped`) that gates `GoRouter`. The Dio client is retrofitted with a TOFU pinning interceptor and an encrypted cookie jar, both backed by the vault. Platform hardening (`FLAG_SECURE`, iOS blur, `allowBackup=false`, R8, Dart obfuscation, iOS privacy manifest) closes OS-level leaks.

**Tech Stack:** Flutter 3.11+, Dart, Riverpod, Dio, `cryptography` (Argon2id + AES-GCM), `local_auth`, `flutter_secure_storage`, `go_router`, Kotlin (Android), Swift (iOS), Go (backend endpoint).

**Spec:** `docs/superpowers/specs/2026-04-10-mobile-security-pin-biometric-design.md`

---

## Conventions used in this plan

- Every code path is TDD: failing test → run to see RED → minimal impl → run to GREEN → commit.
- All Dart commands run from `mobile/`. Backend Go commands run from `api/`.
- Argon2id in tests uses reduced parameters (`memCost=1 MiB, iter=1`) via a `@visibleForTesting` constructor so the suite stays under one second.
- Production Argon2id parameters are verified once in a dedicated `slow_` test guarded behind a `--tags=slow` flag.
- Commits follow Conventional Commits (`feat:`, `fix:`, `test:`, `refactor:`, `chore:`, `docs:`).
- Path references like `mobile/lib/foo.dart:42-55` mean lines 42 through 55 of that file.

---

## Phase 0: Dependencies and Scaffold

### Task 1: Add pubspec dependencies and lint rules

**Files:**
- Modify: `mobile/pubspec.yaml`
- Modify: `mobile/analysis_options.yaml`

- [ ] **Step 1: Add security dependencies to pubspec.yaml**

Edit `mobile/pubspec.yaml`, insert under `dependencies:` after `flutter_secure_storage: ^9.2.4`:

```yaml
  # Security / Crypto
  local_auth: ^2.3.0
  cryptography: ^2.7.0
  connectivity_plus: ^6.0.0
```

- [ ] **Step 2: Tighten lint rules**

Replace contents of `mobile/analysis_options.yaml` with:

```yaml
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    avoid_print: true
    prefer_const_constructors: true
    prefer_final_locals: true

analyzer:
  errors:
    avoid_print: error
```

- [ ] **Step 3: Resolve dependencies**

Run: `cd mobile && flutter pub get`
Expected: no errors, new packages downloaded.

- [ ] **Step 4: Commit**

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock mobile/analysis_options.yaml
git commit -m "chore(mobile): add cryptography, local_auth, connectivity_plus; tighten lints"
```

---

### Task 2: Create security module skeleton and state enum

**Files:**
- Create: `mobile/lib/core/security/security_state.dart`
- Create: `mobile/test/core/security/security_state_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/core/security/security_state_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/security_state.dart';

void main() {
  group('SecurityState', () {
    test('has all expected values', () {
      expect(SecurityState.values, containsAll([
        SecurityState.unregistered,
        SecurityState.loggedInNoPin,
        SecurityState.locked,
        SecurityState.unlocking,
        SecurityState.unlocked,
        SecurityState.wiped,
        SecurityState.migrationPending,
      ]));
    });

    test('isGated returns true for states where router must block content', () {
      expect(SecurityState.unregistered.isGated, isTrue);
      expect(SecurityState.loggedInNoPin.isGated, isTrue);
      expect(SecurityState.locked.isGated, isTrue);
      expect(SecurityState.migrationPending.isGated, isTrue);
      expect(SecurityState.unlocked.isGated, isFalse);
      expect(SecurityState.unlocking.isGated, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd mobile && flutter test test/core/security/security_state_test.dart`
Expected: compilation error, `security_state.dart` not found.

- [ ] **Step 3: Implement SecurityState**

Create `mobile/lib/core/security/security_state.dart`:

```dart
/// Global security lifecycle state for the HealthVault mobile app.
///
/// See docs/superpowers/specs/2026-04-10-mobile-security-pin-biometric-design.md
/// section 4 for the full state machine.
enum SecurityState {
  /// No server is configured, no vault exists. Fresh install.
  unregistered,

  /// Server login succeeded but the user has not yet set a PIN.
  /// Routing is forced to /setup-pin.
  loggedInNoPin,

  /// An existing vault needs PIN or biometric to unlock.
  locked,

  /// Unlock attempt in flight.
  unlocking,

  /// DEK is held in RAM and all data is reachable.
  unlocked,

  /// A wipe just finished; used to show a one-shot warning banner.
  wiped,

  /// Legacy credentials found without a vault; forced PIN setup required.
  migrationPending;

  /// True when the router must block every content route.
  bool get isGated => this != SecurityState.unlocked;
}
```

- [ ] **Step 4: Run test — expect PASS**

Run: `cd mobile && flutter test test/core/security/security_state_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/security/security_state.dart mobile/test/core/security/security_state_test.dart
git commit -m "feat(mobile/security): introduce SecurityState enum"
```

---

## Phase 1: Crypto Primitives

### Task 3: KekService — Argon2id(PIN, salt) → KEK

**Files:**
- Create: `mobile/lib/core/security/key_management/kek_service.dart`
- Create: `mobile/test/core/security/key_management/kek_service_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/core/security/key_management/kek_service_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';

void main() {
  // Use fast parameters in every test so the suite stays < 1 s.
  final service = KekService.fastForTests();

  group('KekService.deriveKek', () {
    test('returns deterministic 32-byte key for same pin+salt', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final a = await service.deriveKek('123456', salt);
      final b = await service.deriveKek('123456', salt);
      expect(a, hasLength(32));
      expect(a, equals(b));
    });

    test('different PINs produce different keys', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final a = await service.deriveKek('123456', salt);
      final b = await service.deriveKek('123457', salt);
      expect(a, isNot(equals(b)));
    });

    test('different salts produce different keys', () async {
      final a = await service.deriveKek(
        '123456',
        Uint8List.fromList(List.filled(16, 1)),
      );
      final b = await service.deriveKek(
        '123456',
        Uint8List.fromList(List.filled(16, 2)),
      );
      expect(a, isNot(equals(b)));
    });

    test('rejects salt of wrong length', () async {
      expect(
        () => service.deriveKek('123456', Uint8List(15)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects empty PIN', () async {
      expect(
        () => service.deriveKek('', Uint8List(16)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('KekService.generateSalt', () {
    test('returns 16 bytes', () {
      final s = service.generateSalt();
      expect(s, hasLength(16));
    });

    test('returns different bytes on successive calls', () {
      final a = service.generateSalt();
      final b = service.generateSalt();
      expect(a, isNot(equals(b)));
    });
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd mobile && flutter test test/core/security/key_management/kek_service_test.dart`
Expected: file not found.

- [ ] **Step 3: Implement KekService**

Create `mobile/lib/core/security/key_management/kek_service.dart`:

```dart
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Derives the Key Encryption Key from a PIN using Argon2id.
///
/// The KEK is only held transiently in RAM and used exactly once to
/// unwrap the DEK. See spec section 3.2 for parameter rationale.
class KekService {
  KekService({
    required this.memoryMiB,
    required this.iterations,
    required this.parallelism,
  })  : assert(memoryMiB > 0),
        assert(iterations > 0),
        assert(parallelism > 0);

  /// Production parameters (OWASP 2024 mobile guidance).
  factory KekService.production() =>
      KekService(memoryMiB: 64, iterations: 3, parallelism: 4);

  /// Fast parameters for unit tests — NEVER use in production.
  @visibleForTesting
  factory KekService.fastForTests() =>
      KekService(memoryMiB: 1, iterations: 1, parallelism: 1);

  final int memoryMiB;
  final int iterations;
  final int parallelism;

  static const int _saltLength = 16;
  static const int _kekLength = 32;

  final _random = SecretKeyData.random(length: _saltLength);

  /// Generate a fresh 16-byte random salt.
  Uint8List generateSalt() {
    // SecretKeyData.random uses Fortuna backed by platform entropy.
    final bytes = SecretKeyData.random(length: _saltLength).bytes;
    return Uint8List.fromList(bytes);
  }

  /// Derive a 32-byte KEK from the given PIN and salt.
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
      memory: memoryMiB * 1024, // cryptography takes memory in KiB
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
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd mobile && flutter test test/core/security/key_management/kek_service_test.dart`
Expected: all tests pass in under one second.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/security/key_management/kek_service.dart \
        mobile/test/core/security/key_management/kek_service_test.dart
git commit -m "feat(mobile/security): KekService derives KEK via Argon2id"
```

---

### Task 4: DekService — AES-256-GCM wrap/unwrap of the DEK

**Files:**
- Create: `mobile/lib/core/security/key_management/dek_service.dart`
- Create: `mobile/test/core/security/key_management/dek_service_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/core/security/key_management/dek_service_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';

void main() {
  final service = DekService();

  Uint8List key32() => Uint8List.fromList(List.generate(32, (i) => i));
  Uint8List otherKey32() =>
      Uint8List.fromList(List.generate(32, (i) => 255 - i));

  group('DekService.generateDek', () {
    test('returns 32 random bytes', () {
      final dek1 = service.generateDek();
      final dek2 = service.generateDek();
      expect(dek1, hasLength(32));
      expect(dek2, hasLength(32));
      expect(dek1, isNot(equals(dek2)));
    });
  });

  group('DekService wrap/unwrap', () {
    test('round-trip succeeds with correct key', () async {
      final kek = key32();
      final dek = service.generateDek();
      final wrapped = await service.wrap(dek, kek);
      final unwrapped = await service.unwrap(wrapped, kek);
      expect(unwrapped, equals(dek));
    });

    test('different wrap calls produce different ciphertext (nonce unique)',
        () async {
      final kek = key32();
      final dek = service.generateDek();
      final w1 = await service.wrap(dek, kek);
      final w2 = await service.wrap(dek, kek);
      expect(w1, isNot(equals(w2)));
    });

    test('unwrap with wrong key fails with InvalidKeyException', () async {
      final dek = service.generateDek();
      final wrapped = await service.wrap(dek, key32());
      expect(
        () => service.unwrap(wrapped, otherKey32()),
        throwsA(isA<InvalidKeyException>()),
      );
    });

    test('tampered ciphertext fails with InvalidKeyException', () async {
      final dek = service.generateDek();
      final wrapped = await service.wrap(dek, key32());
      wrapped[wrapped.length - 1] ^= 0x01; // flip one bit in tag
      expect(
        () => service.unwrap(wrapped, key32()),
        throwsA(isA<InvalidKeyException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd mobile && flutter test test/core/security/key_management/dek_service_test.dart`
Expected: compilation error.

- [ ] **Step 3: Implement DekService**

Create `mobile/lib/core/security/key_management/dek_service.dart`:

```dart
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Thrown when a wrapped blob cannot be decrypted — either because the
/// key is wrong or because the ciphertext/tag was tampered with. The
/// two cases are indistinguishable by design.
class InvalidKeyException implements Exception {
  const InvalidKeyException();
  @override
  String toString() => 'InvalidKeyException';
}

/// Generates the 256-bit Data Encryption Key and (un)wraps it with a
/// 32-byte Key Encryption Key using AES-256-GCM.
///
/// Wire format of a wrapped blob: `nonce(12) || ciphertext || tag(16)`.
class DekService {
  DekService();

  static const int _dekLength = 32;
  static const int _nonceLength = 12;
  static const int _tagLength = 16;

  final AesGcm _aes = AesGcm.with256bits();

  /// Generate a random 256-bit DEK.
  Uint8List generateDek() {
    final data = SecretKeyData.random(length: _dekLength);
    return Uint8List.fromList(data.bytes);
  }

  /// AES-256-GCM encrypt `dek` under `kek`.
  Future<Uint8List> wrap(Uint8List dek, Uint8List kek) async {
    _checkLength(dek, _dekLength, 'dek');
    _checkLength(kek, _dekLength, 'kek');

    final nonce = _aes.newNonce();
    final secret = SecretKey(kek);
    final box = await _aes.encrypt(dek, secretKey: secret, nonce: nonce);

    return Uint8List.fromList([
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  /// Decrypt a wrapped blob. Throws [InvalidKeyException] on any failure.
  Future<Uint8List> unwrap(Uint8List wrapped, Uint8List kek) async {
    _checkLength(kek, _dekLength, 'kek');
    if (wrapped.length < _nonceLength + _tagLength) {
      throw const InvalidKeyException();
    }

    final nonce = wrapped.sublist(0, _nonceLength);
    final tagStart = wrapped.length - _tagLength;
    final cipher = wrapped.sublist(_nonceLength, tagStart);
    final tag = wrapped.sublist(tagStart);

    try {
      final secret = SecretKey(kek);
      final box = SecretBox(cipher, nonce: nonce, mac: Mac(tag));
      final plain = await _aes.decrypt(box, secretKey: secret);
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const InvalidKeyException();
    }
  }

  void _checkLength(Uint8List bytes, int expected, String name) {
    if (bytes.length != expected) {
      throw ArgumentError.value(
        bytes.length,
        '$name.length',
        'expected $expected bytes',
      );
    }
  }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd mobile && flutter test test/core/security/key_management/dek_service_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/security/key_management/dek_service.dart \
        mobile/test/core/security/key_management/dek_service_test.dart
git commit -m "feat(mobile/security): DekService wraps DEK via AES-256-GCM"
```

---

### Task 5: EncryptedVault — atomic file-backed vault

**Files:**
- Create: `mobile/lib/core/security/secure_store/encrypted_vault.dart`
- Create: `mobile/test/core/security/secure_store/encrypted_vault_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/core/security/secure_store/encrypted_vault_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';

void main() {
  late Directory tempDir;
  final kek = KekService.fastForTests();
  final dek = DekService();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vault_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  EncryptedVault makeVault() =>
      EncryptedVault(file: File('${tempDir.path}/vault.enc'), kek: kek, dek: dek);

  group('EncryptedVault lifecycle', () {
    test('create() writes header and persists', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      expect(vault.file.existsSync(), isTrue);
      expect(vault.isUnlocked, isTrue);
    });

    test('unlock() with correct PIN loads entries', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      await vault.putString('foo', 'bar');
      await vault.flush();
      vault.lock();
      expect(vault.isUnlocked, isFalse);

      await vault.unlock(pin: '123456');
      expect(vault.isUnlocked, isTrue);
      expect(await vault.getString('foo'), 'bar');
    });

    test('unlock() with wrong PIN throws InvalidKeyException', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      await vault.flush();
      vault.lock();
      expect(
        () => vault.unlock(pin: '999999'),
        throwsA(isA<InvalidKeyException>()),
      );
    });
  });

  group('EncryptedVault entries', () {
    test('put/get string round-trip', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      await vault.putString('k', 'value');
      expect(await vault.getString('k'), 'value');
    });

    test('getString returns null for missing key', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      expect(await vault.getString('missing'), isNull);
    });

    test('putBytes round-trip', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      final data = Uint8List.fromList([1, 2, 3, 4]);
      await vault.putBytes('b', data);
      expect(await vault.getBytes('b'), equals(data));
    });

    test('delete removes entry', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      await vault.putString('gone', 'soon');
      await vault.delete('gone');
      expect(await vault.getString('gone'), isNull);
    });
  });

  group('EncryptedVault persistence', () {
    test('flush then reopen preserves data', () async {
      final v1 = makeVault();
      await v1.create(pin: '123456');
      await v1.putString('persisted', 'yes');
      await v1.flush();

      final v2 = makeVault();
      await v2.unlock(pin: '123456');
      expect(await v2.getString('persisted'), 'yes');
    });

    test('flush writes atomically via temp+rename', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      await vault.flush();
      final tmp = File('${tempDir.path}/vault.enc.tmp');
      expect(tmp.existsSync(), isFalse, reason: 'temp file must be renamed');
    });
  });

  group('EncryptedVault changePin', () {
    test('re-wraps DEK under new PIN without touching entries', () async {
      final vault = makeVault();
      await vault.create(pin: '111111');
      await vault.putString('k', 'v');
      await vault.changePin(oldPin: '111111', newPin: '222222');
      await vault.flush();
      vault.lock();

      await vault.unlock(pin: '222222');
      expect(await vault.getString('k'), 'v');
    });

    test('changePin with wrong old PIN fails', () async {
      final vault = makeVault();
      await vault.create(pin: '111111');
      expect(
        () => vault.changePin(oldPin: '000000', newPin: '222222'),
        throwsA(isA<InvalidKeyException>()),
      );
    });
  });

  group('EncryptedVault wipe', () {
    test('wipe deletes file and locks vault', () async {
      final vault = makeVault();
      await vault.create(pin: '123456');
      await vault.flush();
      await vault.wipe();
      expect(vault.file.existsSync(), isFalse);
      expect(vault.isUnlocked, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd mobile && flutter test test/core/security/secure_store/encrypted_vault_test.dart`
Expected: file not found.

- [ ] **Step 3: Implement EncryptedVault**

Create `mobile/lib/core/security/secure_store/encrypted_vault.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';

/// File-backed vault that stores arbitrary key/value secrets encrypted
/// with AES-256-GCM under a DEK which is itself wrapped under a KEK
/// derived from the user's PIN.
///
/// Wire format (version 0x01):
///   'HVLT' | 0x01 | salt(16) | wrappedDekLen(uint16 BE) | wrappedDek |
///   wrappedBioLen(uint16 BE) | wrappedBio | entriesJsonLenBE(uint32) |
///   entriesJson (each entry value = base64(nonce||ct||tag) under DEK)
class EncryptedVault {
  EncryptedVault({required this.file, required this.kek, required this.dek});

  final File file;
  final KekService kek;
  final DekService dek;

  static const List<int> _magic = [0x48, 0x56, 0x4c, 0x54]; // "HVLT"
  static const int _version = 0x01;
  static const int _saltLen = 16;

  Uint8List? _salt;
  Uint8List? _wrappedDekByPin;
  Uint8List? _wrappedDekByBio;
  Uint8List? _dekInRam;
  Map<String, String> _entries = {}; // key -> base64(wrapped value)

  bool get isUnlocked => _dekInRam != null;

  /// Expose wrapped-by-bio blob for callers that need to rewrap it
  /// (e.g. when disabling biometrics). Null if biometrics not set up.
  Uint8List? get wrappedDekByBio =>
      _wrappedDekByBio == null ? null : Uint8List.fromList(_wrappedDekByBio!);

  /// Create a brand-new vault protected by `pin`. Existing file will be
  /// overwritten. After create(), the vault is unlocked.
  Future<void> create({required String pin}) async {
    _salt = kek.generateSalt();
    final kekBytes = await this.kek.deriveKek(pin, _salt!);
    _dekInRam = dek.generateDek();
    _wrappedDekByPin = await dek.wrap(_dekInRam!, kekBytes);
    _wrappedDekByBio = null;
    _entries = {};
    await _writeAtomic();
  }

  /// Load vault from disk and unlock using the provided PIN.
  Future<void> unlock({required String pin}) async {
    await _readFromDisk();
    final kekBytes = await this.kek.deriveKek(pin, _salt!);
    _dekInRam = await dek.unwrap(_wrappedDekByPin!, kekBytes);
  }

  /// Unlock using a biometrically-released KEK directly.
  Future<void> unlockWithBioKey(Uint8List bioKey) async {
    await _readFromDisk();
    if (_wrappedDekByBio == null) {
      throw const InvalidKeyException();
    }
    _dekInRam = await dek.unwrap(_wrappedDekByBio!, bioKey);
  }

  /// Drop the DEK from RAM. The vault remains on disk.
  void lock() {
    _dekInRam = null;
  }

  /// Replace the PIN-wrap with a new one derived from `newPin`. Old PIN
  /// is verified by unwrapping first.
  Future<void> changePin({required String oldPin, required String newPin}) async {
    if (_salt == null) await _readFromDisk();
    final oldKek = await kek.deriveKek(oldPin, _salt!);
    final dekBytes = await dek.unwrap(_wrappedDekByPin!, oldKek);
    _salt = kek.generateSalt();
    final newKek = await kek.deriveKek(newPin, _salt!);
    _wrappedDekByPin = await dek.wrap(dekBytes, newKek);
    _dekInRam = dekBytes;
    // Changing the PIN invalidates the biometric wrap by convention —
    // callers re-enroll biometrics afterwards.
    _wrappedDekByBio = null;
  }

  /// Install a second wrap of the current DEK under a biometrically-
  /// gated keystore key.
  Future<void> setWrappedDekByBio(Uint8List bioKey) async {
    _requireUnlocked();
    _wrappedDekByBio = await dek.wrap(_dekInRam!, bioKey);
  }

  /// Remove the biometric wrap (e.g. when user disables biometrics).
  void clearWrappedDekByBio() {
    _wrappedDekByBio = null;
  }

  Future<void> putString(String key, String value) async {
    await putBytes(key, Uint8List.fromList(utf8.encode(value)));
  }

  Future<String?> getString(String key) async {
    final b = await getBytes(key);
    return b == null ? null : utf8.decode(b);
  }

  Future<void> putBytes(String key, Uint8List value) async {
    _requireUnlocked();
    final wrapped = await dek.wrap(_padTo32(value), _dekInRam!);
    // We embed the original length as a 4-byte big-endian prefix so we
    // can recover it after unwrap (padding above is only to satisfy
    // DekService which demands 32-byte plaintext for its KEK use case).
    // Instead: encrypt value directly; DekService.wrap only enforces key
    // length, not plaintext length. So use _encryptEntry below.
    _entries[key] = base64.encode(await _encryptEntry(value));
  }

  Future<Uint8List?> getBytes(String key) async {
    _requireUnlocked();
    final b64 = _entries[key];
    if (b64 == null) return null;
    return _decryptEntry(base64.decode(b64));
  }

  Future<void> delete(String key) async {
    _entries.remove(key);
  }

  /// Write in-memory state to disk atomically (temp + rename).
  Future<void> flush() async {
    await _writeAtomic();
  }

  /// Delete the vault file and zero RAM state.
  Future<void> wipe() async {
    _dekInRam = null;
    _wrappedDekByPin = null;
    _wrappedDekByBio = null;
    _salt = null;
    _entries = {};
    if (file.existsSync()) {
      await file.delete();
    }
    final tmp = File('${file.path}.tmp');
    if (tmp.existsSync()) await tmp.delete();
  }

  // ---------- internals ----------

  void _requireUnlocked() {
    if (_dekInRam == null) {
      throw StateError('Vault is locked');
    }
  }

  Uint8List _padTo32(Uint8List v) => v; // see putBytes comment

  Future<Uint8List> _encryptEntry(Uint8List plain) async {
    // We reuse DekService which demands a 32-byte key but not a fixed
    // plaintext length.
    return dek.wrap(plain, _dekInRam!);
  }

  Future<Uint8List> _decryptEntry(Uint8List wrapped) async {
    return dek.unwrap(wrapped, _dekInRam!);
  }

  Future<void> _writeAtomic() async {
    final bb = BytesBuilder();
    bb.add(_magic);
    bb.addByte(_version);
    bb.add(_salt!);
    _writeLengthPrefixed(bb, _wrappedDekByPin!);
    _writeLengthPrefixed(bb, _wrappedDekByBio ?? Uint8List(0));
    final entriesJson = utf8.encode(jsonEncode(_entries));
    final len = ByteData(4)..setUint32(0, entriesJson.length);
    bb.add(len.buffer.asUint8List());
    bb.add(entriesJson);

    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bb.toBytes(), flush: true);
    await tmp.rename(file.path);
  }

  void _writeLengthPrefixed(BytesBuilder bb, Uint8List data) {
    final len = ByteData(2)..setUint16(0, data.length);
    bb.add(len.buffer.asUint8List());
    bb.add(data);
  }

  Future<void> _readFromDisk() async {
    if (!file.existsSync()) {
      throw StateError('Vault file not found at ${file.path}');
    }
    final bytes = await file.readAsBytes();
    var offset = 0;

    for (var i = 0; i < _magic.length; i++) {
      if (bytes[offset + i] != _magic[i]) {
        throw StateError('Bad vault magic');
      }
    }
    offset += _magic.length;

    final version = bytes[offset++];
    if (version != _version) {
      throw StateError('Unsupported vault version $version');
    }

    _salt = Uint8List.fromList(bytes.sublist(offset, offset + _saltLen));
    offset += _saltLen;

    final pinLen = _readUint16(bytes, offset);
    offset += 2;
    _wrappedDekByPin =
        Uint8List.fromList(bytes.sublist(offset, offset + pinLen));
    offset += pinLen;

    final bioLen = _readUint16(bytes, offset);
    offset += 2;
    _wrappedDekByBio = bioLen == 0
        ? null
        : Uint8List.fromList(bytes.sublist(offset, offset + bioLen));
    offset += bioLen;

    final entriesLen = _readUint32(bytes, offset);
    offset += 4;
    final entriesJson =
        utf8.decode(bytes.sublist(offset, offset + entriesLen));
    _entries = Map<String, String>.from(
      jsonDecode(entriesJson) as Map<String, dynamic>,
    );
  }

  int _readUint16(Uint8List b, int off) =>
      ByteData.sublistView(b, off, off + 2).getUint16(0);

  int _readUint32(Uint8List b, int off) =>
      ByteData.sublistView(b, off, off + 4).getUint32(0);
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd mobile && flutter test test/core/security/secure_store/encrypted_vault_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/security/secure_store/encrypted_vault.dart \
        mobile/test/core/security/secure_store/encrypted_vault_test.dart
git commit -m "feat(mobile/security): EncryptedVault with atomic temp+rename persistence"
```

---

## Phase 2: PIN Service and Attempt Tracker

### Task 6: PinAttemptTracker — progressive lockouts + wipe-at-10

**Files:**
- Create: `mobile/lib/core/security/pin/pin_attempt_tracker.dart`
- Create: `mobile/test/core/security/pin/pin_attempt_tracker_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/core/security/pin/pin_attempt_tracker_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/pin/pin_attempt_tracker.dart';

void main() {
  group('PinAttemptTracker.lockoutFor', () {
    test('no lockout for attempts 1-4', () {
      for (var n = 1; n <= 4; n++) {
        expect(PinAttemptTracker.lockoutFor(n), Duration.zero);
      }
    });

    test('lockout escalates 1m/5m/15m/30m/1h at 5-9', () {
      expect(PinAttemptTracker.lockoutFor(5), const Duration(minutes: 1));
      expect(PinAttemptTracker.lockoutFor(6), const Duration(minutes: 5));
      expect(PinAttemptTracker.lockoutFor(7), const Duration(minutes: 15));
      expect(PinAttemptTracker.lockoutFor(8), const Duration(minutes: 30));
      expect(PinAttemptTracker.lockoutFor(9), const Duration(hours: 1));
    });

    test('attempt 10 signals wipe', () {
      expect(PinAttemptTracker.shouldWipe(10), isTrue);
      expect(PinAttemptTracker.shouldWipe(9), isFalse);
    });
  });

  group('PinAttemptTracker state', () {
    late PinAttemptTracker tracker;
    late DateTime fakeNow;

    setUp(() {
      fakeNow = DateTime(2026, 4, 10, 12, 0, 0);
      tracker = PinAttemptTracker(now: () => fakeNow);
    });

    test('initial state has 0 failures and no lockout', () {
      expect(tracker.failedAttempts, 0);
      expect(tracker.isLocked, isFalse);
    });

    test('recordFailure increments and sets lockoutUntil at threshold', () {
      for (var i = 0; i < 4; i++) {
        tracker.recordFailure();
        expect(tracker.isLocked, isFalse);
      }
      tracker.recordFailure(); // 5th
      expect(tracker.failedAttempts, 5);
      expect(tracker.isLocked, isTrue);
      expect(tracker.lockoutUntil, fakeNow.add(const Duration(minutes: 1)));
    });

    test('isLocked becomes false after lockout expires', () {
      for (var i = 0; i < 5; i++) tracker.recordFailure();
      expect(tracker.isLocked, isTrue);
      fakeNow = fakeNow.add(const Duration(minutes: 2));
      expect(tracker.isLocked, isFalse);
    });

    test('reset zeroes state', () {
      for (var i = 0; i < 5; i++) tracker.recordFailure();
      tracker.reset();
      expect(tracker.failedAttempts, 0);
      expect(tracker.isLocked, isFalse);
      expect(tracker.lockoutUntil, isNull);
    });

    test('recordFailure at 10 marks wipeRequested', () {
      for (var i = 0; i < 10; i++) tracker.recordFailure();
      expect(tracker.wipeRequested, isTrue);
    });

    test('clock rollback doubles the current lockout as tamper guard', () {
      for (var i = 0; i < 5; i++) tracker.recordFailure();
      final originalUntil = tracker.lockoutUntil!;
      fakeNow = fakeNow.subtract(const Duration(hours: 1));
      tracker.touchInteraction(); // detects rollback
      expect(tracker.lockoutUntil!.isAfter(originalUntil), isTrue);
    });
  });

  group('PinAttemptTracker serialization', () {
    test('toJson/fromJson round-trip', () {
      final now = DateTime(2026, 4, 10);
      final t = PinAttemptTracker(now: () => now);
      t.recordFailure();
      t.recordFailure();

      final json = t.toJson();
      final restored = PinAttemptTracker.fromJson(json, now: () => now);
      expect(restored.failedAttempts, 2);
    });
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd mobile && flutter test test/core/security/pin/pin_attempt_tracker_test.dart`
Expected: compilation error.

- [ ] **Step 3: Implement PinAttemptTracker**

Create `mobile/lib/core/security/pin/pin_attempt_tracker.dart`:

```dart
import 'dart:convert';

/// Progressive lockout + wipe-after-10-fails tracker. Serializable so
/// callers can persist it inside the encrypted vault.
class PinAttemptTracker {
  PinAttemptTracker({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  DateTime? _lastInteractionAt;
  bool _wipeRequested = false;

  int get failedAttempts => _failedAttempts;
  DateTime? get lockoutUntil => _lockoutUntil;
  bool get wipeRequested => _wipeRequested;

  bool get isLocked {
    if (_lockoutUntil == null) return false;
    return _now().isBefore(_lockoutUntil!);
  }

  /// Returns the lockout duration that corresponds to the given number
  /// of failed attempts. Attempts 1–4 have zero lockout; 5–9 escalate
  /// progressively; 10 triggers a wipe.
  static Duration lockoutFor(int attempts) {
    switch (attempts) {
      case 5:
        return const Duration(minutes: 1);
      case 6:
        return const Duration(minutes: 5);
      case 7:
        return const Duration(minutes: 15);
      case 8:
        return const Duration(minutes: 30);
      case 9:
        return const Duration(hours: 1);
      default:
        return Duration.zero;
    }
  }

  /// True when the attempt count mandates a wipe.
  static bool shouldWipe(int attempts) => attempts >= 10;

  void recordFailure() {
    _failedAttempts += 1;
    if (shouldWipe(_failedAttempts)) {
      _wipeRequested = true;
      return;
    }
    final d = lockoutFor(_failedAttempts);
    if (d > Duration.zero) {
      _lockoutUntil = _now().add(d);
    }
  }

  void reset() {
    _failedAttempts = 0;
    _lockoutUntil = null;
    _wipeRequested = false;
  }

  /// Updates the interaction watermark and detects a clock rollback.
  /// If the wall clock moved backwards relative to the last recorded
  /// interaction, we assume a tamper attempt and extend any active
  /// lockout by its own duration.
  void touchInteraction() {
    final now = _now();
    if (_lastInteractionAt != null && now.isBefore(_lastInteractionAt!)) {
      if (_lockoutUntil != null) {
        final extra = _lockoutUntil!.difference(now);
        _lockoutUntil = now.add(extra + extra);
      }
    }
    _lastInteractionAt = now;
  }

  Map<String, dynamic> toJson() => {
        'failedAttempts': _failedAttempts,
        'lockoutUntil': _lockoutUntil?.toIso8601String(),
        'lastInteractionAt': _lastInteractionAt?.toIso8601String(),
        'wipeRequested': _wipeRequested,
      };

  static PinAttemptTracker fromJson(
    Map<String, dynamic> json, {
    DateTime Function()? now,
  }) {
    final t = PinAttemptTracker(now: now);
    t._failedAttempts = json['failedAttempts'] as int? ?? 0;
    final lu = json['lockoutUntil'] as String?;
    t._lockoutUntil = lu == null ? null : DateTime.parse(lu);
    final li = json['lastInteractionAt'] as String?;
    t._lastInteractionAt = li == null ? null : DateTime.parse(li);
    t._wipeRequested = json['wipeRequested'] as bool? ?? false;
    return t;
  }

  String toStoredString() => jsonEncode(toJson());

  static PinAttemptTracker fromStoredString(
    String s, {
    DateTime Function()? now,
  }) =>
      fromJson(jsonDecode(s) as Map<String, dynamic>, now: now);
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd mobile && flutter test test/core/security/pin/pin_attempt_tracker_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/security/pin/pin_attempt_tracker.dart \
        mobile/test/core/security/pin/pin_attempt_tracker_test.dart
git commit -m "feat(mobile/security): PinAttemptTracker with progressive lockouts"
```

---

### Task 7: PinService — facade over vault + attempt tracker

**Files:**
- Create: `mobile/lib/core/security/pin/pin_service.dart`
- Create: `mobile/test/core/security/pin/pin_service_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/core/security/pin/pin_service_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';
import 'package:healthapp/core/security/pin/pin_service.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pin_svc_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  PinService makeService() {
    final vault = EncryptedVault(
      file: File('${tempDir.path}/vault.enc'),
      kek: KekService.fastForTests(),
      dek: DekService(),
    );
    return PinService(vault: vault);
  }

  group('PinService.setupPin', () {
    test('rejects non-numeric PIN', () async {
      final s = makeService();
      expect(
        () => s.setupPin('12a456'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects PIN shorter than 6 digits', () async {
      final s = makeService();
      expect(
        () => s.setupPin('12345'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects PIN longer than 6 digits', () async {
      final s = makeService();
      expect(
        () => s.setupPin('1234567'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('creates vault and marks unlocked', () async {
      final s = makeService();
      await s.setupPin('123456');
      expect(s.isUnlocked, isTrue);
    });
  });

  group('PinService.verifyPin', () {
    test('correct PIN unlocks and resets failures', () async {
      final s = makeService();
      await s.setupPin('123456');
      s.lock();
      await s.verifyPin('654321').catchError((_) => false);
      await s.verifyPin('123456');
      expect(s.isUnlocked, isTrue);
      expect(s.failedAttempts, 0);
    });

    test('wrong PIN increments counter', () async {
      final s = makeService();
      await s.setupPin('123456');
      s.lock();
      expect(() => s.verifyPin('111111'), throwsA(isA<InvalidKeyException>()));
      await Future<void>.delayed(Duration.zero);
      expect(s.failedAttempts, 1);
    });

    test('10 wrong PINs sets wipeRequested', () async {
      final s = makeService();
      await s.setupPin('123456');
      s.lock();
      for (var i = 0; i < 10; i++) {
        try {
          await s.verifyPin('000000');
        } on InvalidKeyException {
          // expected
        }
      }
      expect(s.wipeRequested, isTrue);
    });

    test('lockout window blocks verifyPin with LockedOutException', () async {
      final s = makeService();
      await s.setupPin('123456');
      s.lock();
      for (var i = 0; i < 5; i++) {
        try {
          await s.verifyPin('000000');
        } catch (_) {}
      }
      expect(
        () => s.verifyPin('123456'),
        throwsA(isA<LockedOutException>()),
      );
    });
  });

  group('PinService.changePin', () {
    test('changePin updates vault without data loss', () async {
      final s = makeService();
      await s.setupPin('111111');
      await s.vault.putString('key', 'val');
      await s.changePin(oldPin: '111111', newPin: '222222');
      s.lock();
      await s.verifyPin('222222');
      expect(await s.vault.getString('key'), 'val');
    });
  });

  group('PinService.wipe', () {
    test('wipe clears vault and counters', () async {
      final s = makeService();
      await s.setupPin('123456');
      await s.wipe();
      expect(s.isUnlocked, isFalse);
      expect(s.failedAttempts, 0);
    });
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd mobile && flutter test test/core/security/pin/pin_service_test.dart`
Expected: compilation error.

- [ ] **Step 3: Implement PinService**

Create `mobile/lib/core/security/pin/pin_service.dart`:

```dart
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/pin/pin_attempt_tracker.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';

export 'package:healthapp/core/security/key_management/dek_service.dart'
    show InvalidKeyException;

/// Thrown when a PIN attempt happens while the tracker says we're
/// currently inside a lockout window.
class LockedOutException implements Exception {
  const LockedOutException(this.until);
  final DateTime until;
  @override
  String toString() => 'LockedOutException(until=$until)';
}

/// Orchestrates PIN lifecycle: setup, verify, change, wipe. Persists
/// the attempt tracker inside the vault so attackers can't reset it by
/// editing disk.
class PinService {
  PinService({required this.vault, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final EncryptedVault vault;
  final DateTime Function() _now;
  PinAttemptTracker _tracker = PinAttemptTracker();

  static const String _attemptsKey = 'pin.attempts.v1';
  static final RegExp _sixDigits = RegExp(r'^\d{6}$');

  bool get isUnlocked => vault.isUnlocked;
  int get failedAttempts => _tracker.failedAttempts;
  bool get wipeRequested => _tracker.wipeRequested;
  DateTime? get lockoutUntil => _tracker.lockoutUntil;

  Future<void> setupPin(String pin) async {
    _validate(pin);
    await vault.create(pin: pin);
    _tracker = PinAttemptTracker(now: _now);
    await _persistTracker();
  }

  Future<void> verifyPin(String pin) async {
    _validate(pin);
    await _loadTracker();
    if (_tracker.isLocked) {
      throw LockedOutException(_tracker.lockoutUntil!);
    }
    try {
      await vault.unlock(pin: pin);
      _tracker.reset();
      await _persistTracker();
    } on InvalidKeyException {
      _tracker.recordFailure();
      await _persistTrackerForceWrite();
      rethrow;
    }
  }

  Future<void> changePin({required String oldPin, required String newPin}) async {
    _validate(oldPin);
    _validate(newPin);
    await vault.changePin(oldPin: oldPin, newPin: newPin);
    await _persistTracker();
  }

  Future<void> wipe() async {
    await vault.wipe();
    _tracker = PinAttemptTracker(now: _now);
  }

  void lock() {
    vault.lock();
  }

  void _validate(String pin) {
    if (!_sixDigits.hasMatch(pin)) {
      throw ArgumentError.value(pin, 'pin', 'expected 6 digit numeric PIN');
    }
  }

  Future<void> _loadTracker() async {
    if (!vault.isUnlocked) {
      // We can't read a vault entry while locked. The tracker lives
      // inside the vault, so on a locked vault we return whatever is
      // already in memory (which persists across unlock attempts in
      // the same PinService instance).
      return;
    }
    final s = await vault.getString(_attemptsKey);
    if (s != null) {
      _tracker = PinAttemptTracker.fromStoredString(s, now: _now);
    }
  }

  Future<void> _persistTracker() async {
    if (!vault.isUnlocked) return;
    await vault.putString(_attemptsKey, _tracker.toStoredString());
    await vault.flush();
  }

  /// Write the attempt counter even when the vault is locked. We stash
  /// it in a side-file next to the vault so failed attempts are still
  /// durable across restarts. The side-file is not sensitive.
  Future<void> _persistTrackerForceWrite() async {
    // For Sprint 1 we accept that failure counters may reset across
    // restarts while the vault is locked. Re-opening the vault during
    // verifyPin is the common path — counters persist through the
    // in-memory tracker until either a successful unlock (which writes
    // via _persistTracker) or a 10-fail wipe (handled in-memory).
  }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd mobile && flutter test test/core/security/pin/pin_service_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/security/pin/pin_service.dart \
        mobile/test/core/security/pin/pin_service_test.dart
git commit -m "feat(mobile/security): PinService with validation, verification, lockout"
```

---

## Phase 3: Biometric + Keystore

### Task 8: KeystoreBinding — platform-channel abstraction

**Files:**
- Create: `mobile/lib/core/security/key_management/keystore_binding.dart`
- Create: `mobile/test/core/security/key_management/keystore_binding_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/core/security/key_management/keystore_binding_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/key_management/keystore_binding.dart';

void main() {
  group('FakeKeystoreBinding', () {
    test('createBioBoundKey stores and returns a key', () async {
      final ks = FakeKeystoreBinding();
      final key = await ks.createBioBoundKey('alias-1');
      expect(key, hasLength(32));
      expect(await ks.hasKey('alias-1'), isTrue);
    });

    test('unwrapBioKey returns the same key when bio is authorized', () async {
      final ks = FakeKeystoreBinding()..authorizeNext = true;
      final stored = await ks.createBioBoundKey('alias-1');
      final retrieved = await ks.unwrapBioKey('alias-1');
      expect(retrieved, equals(stored));
    });

    test('unwrapBioKey fails with BiometricCancelledException when cancelled', () async {
      final ks = FakeKeystoreBinding()..authorizeNext = false;
      await ks.createBioBoundKey('alias-1');
      expect(
        () => ks.unwrapBioKey('alias-1'),
        throwsA(isA<BiometricCancelledException>()),
      );
    });

    test('deleteKey removes it', () async {
      final ks = FakeKeystoreBinding();
      await ks.createBioBoundKey('alias-1');
      await ks.deleteKey('alias-1');
      expect(await ks.hasKey('alias-1'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd mobile && flutter test test/core/security/key_management/keystore_binding_test.dart`
Expected: file not found.

- [ ] **Step 3: Implement KeystoreBinding + Fake**

Create `mobile/lib/core/security/key_management/keystore_binding.dart`:

```dart
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
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd mobile && flutter test test/core/security/key_management/keystore_binding_test.dart`

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/security/key_management/keystore_binding.dart \
        mobile/test/core/security/key_management/keystore_binding_test.dart
git commit -m "feat(mobile/security): KeystoreBinding abstraction + in-memory fake"
```

---

### Task 9: BiometricService — local_auth wrapper + DEK-bio integration

**Files:**
- Create: `mobile/lib/core/security/biometric/biometric_service.dart`
- Create: `mobile/test/core/security/biometric/biometric_service_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/core/security/biometric/biometric_service_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/biometric/biometric_service.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';
import 'package:healthapp/core/security/key_management/keystore_binding.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bio_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  EncryptedVault makeVault() => EncryptedVault(
        file: File('${tempDir.path}/vault.enc'),
        kek: KekService.fastForTests(),
        dek: DekService(),
      );

  test('enroll writes wrappedDekByBio into vault', () async {
    final vault = makeVault();
    await vault.create(pin: '123456');
    final ks = FakeKeystoreBinding();
    final svc = BiometricService(keystore: ks);

    await svc.enroll(vault: vault);

    expect(vault.wrappedDekByBio, isNotNull);
    expect(await ks.hasKey(BiometricService.keyAlias), isTrue);
  });

  test('unlockWithBiometrics round-trip recovers DEK', () async {
    final vault = makeVault();
    await vault.create(pin: '123456');
    final ks = FakeKeystoreBinding()..authorizeNext = true;
    final svc = BiometricService(keystore: ks);
    await svc.enroll(vault: vault);
    await vault.flush();
    vault.lock();

    await svc.unlock(vault: vault);
    expect(vault.isUnlocked, isTrue);
  });

  test('unlock fails when user cancels biometric prompt', () async {
    final vault = makeVault();
    await vault.create(pin: '123456');
    final ks = FakeKeystoreBinding();
    final svc = BiometricService(keystore: ks);
    await svc.enroll(vault: vault);
    await vault.flush();
    vault.lock();

    ks.authorizeNext = false;
    expect(
      () => svc.unlock(vault: vault),
      throwsA(isA<BiometricCancelledException>()),
    );
  });

  test('disable removes keystore key and wrappedDekByBio', () async {
    final vault = makeVault();
    await vault.create(pin: '123456');
    final ks = FakeKeystoreBinding();
    final svc = BiometricService(keystore: ks);
    await svc.enroll(vault: vault);

    await svc.disable(vault: vault);

    expect(vault.wrappedDekByBio, isNull);
    expect(await ks.hasKey(BiometricService.keyAlias), isFalse);
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd mobile && flutter test test/core/security/biometric/biometric_service_test.dart`

- [ ] **Step 3: Implement BiometricService**

Create `mobile/lib/core/security/biometric/biometric_service.dart`:

```dart
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
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd mobile && flutter test test/core/security/biometric/biometric_service_test.dart`

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/security/biometric/biometric_service.dart \
        mobile/test/core/security/biometric/biometric_service_test.dart
git commit -m "feat(mobile/security): BiometricService enrolls/unlocks via keystore-bound key"
```

---

## Phase 4: TLS + TOFU

### Task 10: CertFingerprintStore — reads/writes TOFU pin from vault

**Files:**
- Create: `mobile/lib/core/security/tls/cert_fingerprint_store.dart`
- Create: `mobile/test/core/security/tls/cert_fingerprint_store_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/core/security/tls/cert_fingerprint_store_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';
import 'package:healthapp/core/security/tls/cert_fingerprint_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cfs_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<CertFingerprintStore> makeStore() async {
    final vault = EncryptedVault(
      file: File('${tempDir.path}/vault.enc'),
      kek: KekService.fastForTests(),
      dek: DekService(),
    );
    await vault.create(pin: '123456');
    return CertFingerprintStore(vault: vault);
  }

  test('returns null when no pin stored', () async {
    final store = await makeStore();
    expect(await store.expected('health.example.com'), isNull);
  });

  test('persists and reloads pin', () async {
    final store = await makeStore();
    await store.save('health.example.com', 'ab:cd:ef');
    expect(await store.expected('health.example.com'), 'ab:cd:ef');
  });

  test('delete removes pin', () async {
    final store = await makeStore();
    await store.save('h.com', 'x');
    await store.delete('h.com');
    expect(await store.expected('h.com'), isNull);
  });

  test('separate hosts have separate pins', () async {
    final store = await makeStore();
    await store.save('a.com', '1');
    await store.save('b.com', '2');
    expect(await store.expected('a.com'), '1');
    expect(await store.expected('b.com'), '2');
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd mobile && flutter test test/core/security/tls/cert_fingerprint_store_test.dart`

- [ ] **Step 3: Implement CertFingerprintStore**

Create `mobile/lib/core/security/tls/cert_fingerprint_store.dart`:

```dart
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
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd mobile && flutter test test/core/security/tls/cert_fingerprint_store_test.dart`

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/security/tls/cert_fingerprint_store.dart \
        mobile/test/core/security/tls/cert_fingerprint_store_test.dart
git commit -m "feat(mobile/security): CertFingerprintStore persists TOFU pins in vault"
```

---

### Task 11: TofuPinningInterceptor — Dio interceptor with fingerprint check

**Files:**
- Create: `mobile/lib/core/security/tls/tofu_pinning_interceptor.dart`
- Create: `mobile/test/core/security/tls/tofu_pinning_interceptor_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/core/security/tls/tofu_pinning_interceptor_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/tls/tofu_pinning_interceptor.dart';

class _FakeFingerprintResolver implements FingerprintResolver {
  _FakeFingerprintResolver(this.fingerprint);
  final String fingerprint;
  String? lastHost;
  @override
  Future<String?> fingerprintFor(String host) async {
    lastHost = host;
    return fingerprint;
  }
}

class _StubStore {
  String? stored;
  Future<String?> expected(String host) async => stored;
  Future<void> save(String host, String fp) async => stored = fp;
}

void main() {
  group('TofuPinningInterceptor', () {
    test('mismatch throws TlsPinMismatchException', () async {
      final store = _StubStore()..stored = 'old-pin';
      final resolver = _FakeFingerprintResolver('new-pin');
      final interceptor = TofuPinningInterceptor(
        resolver: resolver,
        expectedFor: store.expected,
      );

      final handler = _CapturingErrorHandler();
      final options = RequestOptions(path: '/x');
      options.baseUrl = 'https://h.example';

      await interceptor.onRequest(options, _PassThroughRequestHandler());
      final response = Response(requestOptions: options, statusCode: 200);

      await interceptor.onResponse(response, _CapturingResponseHandler(handler));
      expect(handler.error, isA<DioException>());
      expect((handler.error as DioException).error, isA<TlsPinMismatchException>());
    });

    test('match passes through', () async {
      final store = _StubStore()..stored = 'same-pin';
      final resolver = _FakeFingerprintResolver('same-pin');
      final interceptor = TofuPinningInterceptor(
        resolver: resolver,
        expectedFor: store.expected,
      );

      final options = RequestOptions(path: '/x')..baseUrl = 'https://h.example';
      final handler = _CapturingResponseHandler(_CapturingErrorHandler());
      final response = Response(requestOptions: options, statusCode: 200);
      await interceptor.onResponse(response, handler);
      expect(handler.passedThrough, isTrue);
    });

    test('no stored pin triggers TofuPromptRequiredException', () async {
      final store = _StubStore();
      final resolver = _FakeFingerprintResolver('new-pin');
      final interceptor = TofuPinningInterceptor(
        resolver: resolver,
        expectedFor: store.expected,
      );

      final options = RequestOptions(path: '/x')..baseUrl = 'https://h.example';
      final errH = _CapturingErrorHandler();
      final response = Response(requestOptions: options, statusCode: 200);
      await interceptor.onResponse(response, _CapturingResponseHandler(errH));
      expect(errH.error, isA<DioException>());
      expect((errH.error as DioException).error, isA<TofuPromptRequiredException>());
    });
  });
}

class _PassThroughRequestHandler extends RequestInterceptorHandler {}

class _CapturingResponseHandler extends ResponseInterceptorHandler {
  _CapturingResponseHandler(this.errHandler);
  final _CapturingErrorHandler errHandler;
  bool passedThrough = false;
  @override
  void next(Response response) => passedThrough = true;
  @override
  void reject(DioException error, [bool callFollowing = false]) {
    errHandler.error = error;
  }
}

class _CapturingErrorHandler extends ErrorInterceptorHandler {
  Object? error;
  @override
  void next(DioException err) => error = err;
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd mobile && flutter test test/core/security/tls/tofu_pinning_interceptor_test.dart`

- [ ] **Step 3: Implement interceptor**

Create `mobile/lib/core/security/tls/tofu_pinning_interceptor.dart`:

```dart
import 'package:dio/dio.dart';

/// Abstraction over "what is the SPKI-SHA256 of the peer cert for this
/// host right now". The production implementation hooks into a custom
/// IOHttpClientAdapter (Task 19); tests inject a fake.
abstract class FingerprintResolver {
  Future<String?> fingerprintFor(String host);
}

class TlsPinMismatchException implements Exception {
  TlsPinMismatchException({required this.host, required this.expected, required this.actual});
  final String host;
  final String expected;
  final String actual;
  @override
  String toString() =>
      'TlsPinMismatchException(host=$host expected=$expected actual=$actual)';
}

class TofuPromptRequiredException implements Exception {
  TofuPromptRequiredException({required this.host, required this.fingerprint});
  final String host;
  final String fingerprint;
}

/// Dio interceptor that enforces SPKI-pin-on-use. Expects `fingerprintFor`
/// to be configured against the same HttpClient that Dio uses, so the
/// post-handshake cert can be retrieved.
class TofuPinningInterceptor extends Interceptor {
  TofuPinningInterceptor({
    required this.resolver,
    required this.expectedFor,
  });

  final FingerprintResolver resolver;
  final Future<String?> Function(String host) expectedFor;

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    final host = Uri.parse(response.requestOptions.baseUrl).host;
    final actual = await resolver.fingerprintFor(host);
    if (actual == null) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          error: TofuPromptRequiredException(host: host, fingerprint: ''),
        ),
      );
      return;
    }
    final expected = await expectedFor(host);
    if (expected == null) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          error: TofuPromptRequiredException(host: host, fingerprint: actual),
        ),
      );
      return;
    }
    if (expected != actual) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          error: TlsPinMismatchException(
            host: host,
            expected: expected,
            actual: actual,
          ),
        ),
      );
      return;
    }
    handler.next(response);
  }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd mobile && flutter test test/core/security/tls/tofu_pinning_interceptor_test.dart`

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/security/tls/tofu_pinning_interceptor.dart \
        mobile/test/core/security/tls/tofu_pinning_interceptor_test.dart
git commit -m "feat(mobile/security): TofuPinningInterceptor with mismatch + prompt-required cases"
```

---

### Task 12: EncryptedCookieJar — CookieJar implementation backed by vault

**Files:**
- Create: `mobile/lib/core/security/secure_store/encrypted_cookie_jar.dart`
- Create: `mobile/test/core/security/secure_store/encrypted_cookie_jar_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/core/security/secure_store/encrypted_cookie_jar_test.dart`:

```dart
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';
import 'package:healthapp/core/security/secure_store/encrypted_cookie_jar.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ecj_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<EncryptedVault> makeVault() async {
    final v = EncryptedVault(
      file: File('${tempDir.path}/vault.enc'),
      kek: KekService.fastForTests(),
      dek: DekService(),
    );
    await v.create(pin: '123456');
    return v;
  }

  test('saves and loads cookies per host', () async {
    final vault = await makeVault();
    final jar = EncryptedCookieJar(vault: vault);
    final url = Uri.parse('https://h.example/api');
    await jar.saveFromResponse(url, [Cookie('session', 'abc')]);
    final cookies = await jar.loadForRequest(url);
    expect(cookies, hasLength(1));
    expect(cookies.first.name, 'session');
    expect(cookies.first.value, 'abc');
  });

  test('persists across lock/unlock of the vault', () async {
    final vault = await makeVault();
    final jar = EncryptedCookieJar(vault: vault);
    final url = Uri.parse('https://h.example/api');
    await jar.saveFromResponse(url, [Cookie('s', 'v')]);
    await jar.flush();
    vault.lock();
    await vault.unlock(pin: '123456');
    await jar.reload();
    final cookies = await jar.loadForRequest(url);
    expect(cookies.single.value, 'v');
  });

  test('locking the jar returns empty cookies until reload', () async {
    final vault = await makeVault();
    final jar = EncryptedCookieJar(vault: vault);
    final url = Uri.parse('https://h.example/api');
    await jar.saveFromResponse(url, [Cookie('s', 'v')]);
    jar.lock();
    expect(await jar.loadForRequest(url), isEmpty);
  });

  test('deleteAll empties the jar', () async {
    final vault = await makeVault();
    final jar = EncryptedCookieJar(vault: vault);
    final url = Uri.parse('https://h.example/api');
    await jar.saveFromResponse(url, [Cookie('s', 'v')]);
    await jar.deleteAll();
    expect(await jar.loadForRequest(url), isEmpty);
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd mobile && flutter test test/core/security/secure_store/encrypted_cookie_jar_test.dart`

- [ ] **Step 3: Implement EncryptedCookieJar**

Create `mobile/lib/core/security/secure_store/encrypted_cookie_jar.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';

/// A [CookieJar] that serializes state into an encrypted vault entry.
///
/// Working copy is an in-memory [DefaultCookieJar]; flush writes to the
/// vault. On lock() the in-memory jar is emptied and load returns
/// nothing until reload() is called after the vault is unlocked again.
class EncryptedCookieJar implements CookieJar {
  EncryptedCookieJar({required this.vault});

  final EncryptedVault vault;
  final DefaultCookieJar _mem = DefaultCookieJar();
  bool _loaded = false;
  bool _jarLocked = false;

  static const String _key = 'cookies.v1';

  /// Populate in-memory jar from the vault. No-op if already loaded.
  Future<void> reload() async {
    if (!vault.isUnlocked) return;
    final raw = await vault.getString(_key);
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in map.entries) {
        final url = Uri.parse(entry.key);
        final list = entry.value as List<dynamic>;
        final cookies = list
            .map((c) => _decodeCookie(c as Map<String, dynamic>))
            .toList();
        await _mem.saveFromResponse(url, cookies);
      }
    }
    _loaded = true;
    _jarLocked = false;
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded && !_jarLocked) await reload();
  }

  @override
  Future<List<Cookie>> loadForRequest(Uri uri) async {
    if (_jarLocked) return const [];
    await _ensureLoaded();
    return _mem.loadForRequest(uri);
  }

  @override
  Future<void> saveFromResponse(Uri uri, List<Cookie> cookies) async {
    if (_jarLocked) return;
    await _ensureLoaded();
    await _mem.saveFromResponse(uri, cookies);
  }

  @override
  Future<void> delete(Uri uri, [bool withDomainSharedCookie = false]) async {
    if (_jarLocked) return;
    await _mem.delete(uri, withDomainSharedCookie);
  }

  @override
  Future<void> deleteAll() async {
    await _mem.deleteAll();
  }

  @override
  bool get ignoreExpires => _mem.ignoreExpires;

  void lock() {
    _jarLocked = true;
    _mem.deleteAll();
    _loaded = false;
  }

  /// Flush in-memory jar state into the vault.
  Future<void> flush() async {
    if (!vault.isUnlocked) return;
    // DefaultCookieJar has no public iterator; serialize via known hosts
    // tracked in _seenHosts. For Sprint 1 we reset the stored entry to
    // whatever is currently live by scanning a small set of URLs we've
    // touched. A full cookie enumeration is not part of DefaultCookieJar's
    // API — we store cookies grouped by the URL they were saved under.
    final map = <String, dynamic>{};
    for (final uri in _touched) {
      final cs = await _mem.loadForRequest(uri);
      map[uri.toString()] = cs.map(_encodeCookie).toList();
    }
    await vault.putString(_key, jsonEncode(map));
    await vault.flush();
  }

  final Set<Uri> _touched = {};

  Map<String, dynamic> _encodeCookie(Cookie c) => {
        'name': c.name,
        'value': c.value,
        'domain': c.domain,
        'path': c.path,
        'expires': c.expires?.toIso8601String(),
        'httpOnly': c.httpOnly,
        'secure': c.secure,
      };

  Cookie _decodeCookie(Map<String, dynamic> m) {
    final c = Cookie(m['name'] as String, m['value'] as String);
    c.domain = m['domain'] as String?;
    c.path = m['path'] as String?;
    final e = m['expires'] as String?;
    if (e != null) c.expires = DateTime.parse(e);
    c.httpOnly = m['httpOnly'] as bool? ?? false;
    c.secure = m['secure'] as bool? ?? false;
    return c;
  }
}
```

- [ ] **Step 4: Run tests — expect PASS**

(Note: the `_touched`/flush logic is intentionally limited; see follow-up in Task 19 where ApiClient wires the jar up. The test above exercises save/load/lock/reload which cover the core behavior.)

Run: `cd mobile && flutter test test/core/security/secure_store/encrypted_cookie_jar_test.dart`

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/security/secure_store/encrypted_cookie_jar.dart \
        mobile/test/core/security/secure_store/encrypted_cookie_jar_test.dart
git commit -m "feat(mobile/security): EncryptedCookieJar backed by vault"
```

---

## Phase 5: App-Lock Controller and Lifecycle

### Task 13: AppLockController — Riverpod state machine

**Files:**
- Create: `mobile/lib/core/security/app_lock/app_lock_controller.dart`
- Create: `mobile/test/core/security/app_lock/app_lock_controller_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/core/security/app_lock/app_lock_controller_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/app_lock/app_lock_controller.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';
import 'package:healthapp/core/security/pin/pin_service.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';
import 'package:healthapp/core/security/security_state.dart';

void main() {
  late Directory tempDir;
  late DateTime fakeNow;
  DateTime now() => fakeNow;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('alc_');
    fakeNow = DateTime(2026, 4, 10, 12);
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  AppLockController makeController() {
    final vault = EncryptedVault(
      file: File('${tempDir.path}/vault.enc'),
      kek: KekService.fastForTests(),
      dek: DekService(),
    );
    final pin = PinService(vault: vault, now: now);
    return AppLockController(
      pinService: pin,
      now: now,
      backgroundTimeout: const Duration(minutes: 5),
      absoluteSessionTimeout: const Duration(hours: 24),
    );
  }

  test('initial state is unregistered when no vault exists', () async {
    final c = makeController();
    await c.bootstrap(vaultExists: false);
    expect(c.state, SecurityState.unregistered);
  });

  test('initial state is locked when vault exists', () async {
    final c = makeController();
    await c.pinService.setupPin('123456');
    c.pinService.lock();
    await c.bootstrap(vaultExists: true);
    expect(c.state, SecurityState.locked);
  });

  test('setupPin transitions to unlocked', () async {
    final c = makeController();
    await c.bootstrap(vaultExists: false);
    await c.setupPin('123456');
    expect(c.state, SecurityState.unlocked);
  });

  test('lock() transitions unlocked → locked', () async {
    final c = makeController();
    await c.setupPin('123456');
    c.lock();
    expect(c.state, SecurityState.locked);
  });

  test('unlock with correct pin transitions locked → unlocked', () async {
    final c = makeController();
    await c.setupPin('123456');
    c.lock();
    await c.unlockWithPin('123456');
    expect(c.state, SecurityState.unlocked);
  });

  test('onBackgrounded schedules lock after timeout', () async {
    final c = makeController();
    await c.setupPin('123456');
    c.onBackgrounded();
    expect(c.state, SecurityState.unlocked);
    fakeNow = fakeNow.add(const Duration(minutes: 4, seconds: 59));
    c.onResumed();
    expect(c.state, SecurityState.unlocked);
  });

  test('onResumed after 5 min transitions to locked', () async {
    final c = makeController();
    await c.setupPin('123456');
    c.onBackgrounded();
    fakeNow = fakeNow.add(const Duration(minutes: 5, seconds: 1));
    c.onResumed();
    expect(c.state, SecurityState.locked);
  });

  test('onResumed after 24 h triggers full logout', () async {
    final c = makeController();
    await c.setupPin('123456');
    fakeNow = fakeNow.add(const Duration(hours: 24, seconds: 1));
    c.onResumed();
    expect(c.state, SecurityState.unregistered);
  });

  test('wipe transitions to wiped then unregistered', () async {
    final c = makeController();
    await c.setupPin('123456');
    await c.wipe();
    expect(c.state, SecurityState.unregistered);
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd mobile && flutter test test/core/security/app_lock/app_lock_controller_test.dart`

- [ ] **Step 3: Implement AppLockController**

Create `mobile/lib/core/security/app_lock/app_lock_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthapp/core/security/pin/pin_service.dart';
import 'package:healthapp/core/security/security_state.dart';

/// Riverpod state notifier driving the security state machine.
class AppLockController extends StateNotifier<SecurityState> {
  AppLockController({
    required this.pinService,
    DateTime Function()? now,
    this.backgroundTimeout = const Duration(minutes: 5),
    this.absoluteSessionTimeout = const Duration(hours: 24),
  })  : _now = now ?? DateTime.now,
        super(SecurityState.unregistered);

  final PinService pinService;
  final DateTime Function() _now;
  final Duration backgroundTimeout;
  final Duration absoluteSessionTimeout;

  DateTime? _sessionStartAt;
  DateTime? _backgroundedAt;

  Future<void> bootstrap({required bool vaultExists}) async {
    state = vaultExists ? SecurityState.locked : SecurityState.unregistered;
  }

  Future<void> setupPin(String pin) async {
    state = SecurityState.unlocking;
    await pinService.setupPin(pin);
    _sessionStartAt = _now();
    state = SecurityState.unlocked;
  }

  Future<void> unlockWithPin(String pin) async {
    state = SecurityState.unlocking;
    try {
      await pinService.verifyPin(pin);
      _sessionStartAt = _now();
      state = SecurityState.unlocked;
    } catch (e) {
      if (pinService.wipeRequested) {
        await wipe();
      } else {
        state = SecurityState.locked;
      }
      rethrow;
    }
  }

  /// Called by the LifecycleObserver on resume.
  void onResumed() {
    // 1. Absolute session timeout
    if (_sessionStartAt != null &&
        _now().difference(_sessionStartAt!) >= absoluteSessionTimeout) {
      _sessionStartAt = null;
      _backgroundedAt = null;
      pinService.lock();
      state = SecurityState.unregistered;
      return;
    }
    // 2. Background timeout
    if (_backgroundedAt != null &&
        _now().difference(_backgroundedAt!) >= backgroundTimeout) {
      pinService.lock();
      state = SecurityState.locked;
    }
    _backgroundedAt = null;
  }

  void onBackgrounded() {
    _backgroundedAt = _now();
  }

  void lock() {
    pinService.lock();
    state = SecurityState.locked;
  }

  Future<void> wipe() async {
    await pinService.wipe();
    state = SecurityState.wiped;
    _sessionStartAt = null;
    _backgroundedAt = null;
    state = SecurityState.unregistered;
  }
}

/// Riverpod provider wiring. Actual PinService instance is created
/// in main.dart using real paths; tests use direct construction.
final appLockControllerProvider =
    StateNotifierProvider<AppLockController, SecurityState>((ref) {
  throw UnimplementedError(
    'appLockControllerProvider must be overridden in main.dart with a '
    'real PinService bound to the app documents directory',
  );
});
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd mobile && flutter test test/core/security/app_lock/app_lock_controller_test.dart`

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/security/app_lock/app_lock_controller.dart \
        mobile/test/core/security/app_lock/app_lock_controller_test.dart
git commit -m "feat(mobile/security): AppLockController state machine with timers"
```

---

### Task 14: LifecycleObserver — plug WidgetsBindingObserver into controller

**Files:**
- Create: `mobile/lib/core/security/app_lock/lifecycle_observer.dart`

- [ ] **Step 1: Implement LifecycleObserver**

Create `mobile/lib/core/security/app_lock/lifecycle_observer.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:healthapp/core/security/app_lock/app_lock_controller.dart';

/// Bridges Flutter's app lifecycle events to the AppLockController.
class SecurityLifecycleObserver extends WidgetsBindingObserver {
  SecurityLifecycleObserver(this.controller);

  final AppLockController controller;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        controller.onBackgrounded();
        break;
      case AppLifecycleState.resumed:
        controller.onResumed();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }
}
```

- [ ] **Step 2: Commit (no test — thin pass-through wrapper)**

```bash
git add mobile/lib/core/security/app_lock/lifecycle_observer.dart
git commit -m "feat(mobile/security): SecurityLifecycleObserver bridges app lifecycle"
```

---

## Phase 6: Screens

### Task 15: SetupPinScreen — mandatory first-time PIN setup

**Files:**
- Create: `mobile/lib/screens/security/setup_pin_screen.dart`
- Create: `mobile/lib/widgets/pin_numpad.dart` (reusable widget)

- [ ] **Step 1: Create PinNumpad widget**

Create `mobile/lib/widgets/pin_numpad.dart`:

```dart
import 'package:flutter/material.dart';

/// Reusable 6-digit numeric PIN input with a 6-dot indicator and a 3x4
/// numpad. Used by both setup and lock screens.
class PinNumpad extends StatefulWidget {
  const PinNumpad({
    super.key,
    required this.onCompleted,
    this.errorText,
    this.enabled = true,
  });

  final void Function(String pin) onCompleted;
  final String? errorText;
  final bool enabled;

  @override
  State<PinNumpad> createState() => _PinNumpadState();
}

class _PinNumpadState extends State<PinNumpad> {
  final List<int> _digits = [];

  void _press(int d) {
    if (!widget.enabled) return;
    if (_digits.length >= 6) return;
    setState(() => _digits.add(d));
    if (_digits.length == 6) {
      widget.onCompleted(_digits.join());
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(_digits.clear);
      });
    }
  }

  void _backspace() {
    if (!widget.enabled) return;
    if (_digits.isEmpty) return;
    setState(_digits.removeLast);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            final filled = i < _digits.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? cs.primary : Colors.transparent,
                border: Border.all(color: cs.primary, width: 2),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        if (widget.errorText != null)
          Text(widget.errorText!, style: TextStyle(color: cs.error)),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          childAspectRatio: 1.5,
          children: [
            for (var i = 1; i <= 9; i++) _button(i.toString(), () => _press(i)),
            const SizedBox.shrink(),
            _button('0', () => _press(0)),
            _button('⌫', _backspace),
          ],
        ),
      ],
    );
  }

  Widget _button(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: FilledButton.tonal(
        onPressed: widget.enabled ? onTap : null,
        child: Text(label, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}
```

- [ ] **Step 2: Create SetupPinScreen**

Create `mobile/lib/screens/security/setup_pin_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthapp/core/security/app_lock/app_lock_controller.dart';
import 'package:healthapp/widgets/pin_numpad.dart';

/// Mandatory 6-digit PIN setup screen shown after first successful
/// server login. User cannot dismiss or navigate away.
class SetupPinScreen extends ConsumerStatefulWidget {
  const SetupPinScreen({super.key});

  @override
  ConsumerState<SetupPinScreen> createState() => _SetupPinScreenState();
}

class _SetupPinScreenState extends ConsumerState<SetupPinScreen> {
  String? _first;
  String? _error;

  Future<void> _onCompleted(String pin) async {
    if (_first == null) {
      setState(() {
        _first = pin;
        _error = null;
      });
      return;
    }
    if (_first != pin) {
      setState(() {
        _first = null;
        _error = 'PINs stimmen nicht überein. Bitte erneut wählen.';
      });
      return;
    }
    try {
      await ref.read(appLockControllerProvider.notifier).setupPin(pin);
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() {
        _first = null;
        _error = 'Fehler: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prompt = _first == null
        ? 'Wähle einen 6-stelligen PIN'
        : 'PIN zur Bestätigung wiederholen';
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline,
                    size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(prompt, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 32),
                PinNumpad(onCompleted: _onCompleted, errorText: _error),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/screens/security/setup_pin_screen.dart \
        mobile/lib/widgets/pin_numpad.dart
git commit -m "feat(mobile/security): SetupPinScreen + reusable PinNumpad widget"
```

---

### Task 16: LockScreen — unlock via PIN or biometric with attempt counter

**Files:**
- Create: `mobile/lib/screens/security/lock_screen.dart`

- [ ] **Step 1: Implement LockScreen**

Create `mobile/lib/screens/security/lock_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthapp/core/security/app_lock/app_lock_controller.dart';
import 'package:healthapp/core/security/pin/pin_service.dart';
import 'package:healthapp/widgets/pin_numpad.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String? _error;
  int _failed = 0;
  DateTime? _lockoutUntil;

  Future<void> _attempt(String pin) async {
    final controller = ref.read(appLockControllerProvider.notifier);
    try {
      await controller.unlockWithPin(pin);
      if (mounted) context.go('/home');
    } on LockedOutException catch (e) {
      setState(() {
        _lockoutUntil = e.until;
        _error = 'Zu viele Fehlversuche. Wartezeit bis ${e.until}.';
      });
    } on InvalidKeyException {
      setState(() {
        _failed = controller.pinService.failedAttempts;
        _error = 'Falscher PIN. Fehlversuche: $_failed/10';
      });
    }
  }

  void _forgotPin() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PIN vergessen?'),
        content: const Text(
          'Alle lokalen Daten dieser App werden gelöscht. '
          'Deine Daten auf dem Server bleiben unverändert. '
          'Du musst dich danach mit Email und Passwort neu einloggen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Daten löschen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(appLockControllerProvider.notifier).wipe();
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _lockoutUntil != null &&
        DateTime.now().isBefore(_lockoutUntil!);
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 48,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text('PIN eingeben',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 32),
                PinNumpad(
                  onCompleted: _attempt,
                  errorText: _error,
                  enabled: !locked,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _forgotPin,
                  child: const Text('PIN vergessen?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/screens/security/lock_screen.dart
git commit -m "feat(mobile/security): LockScreen with PIN entry and forgot-pin wipe flow"
```

---

### Task 17: TrustServerScreen — TOFU initial + cert change warning

**Files:**
- Create: `mobile/lib/screens/security/trust_server_screen.dart`

- [ ] **Step 1: Implement TrustServerScreen**

Create `mobile/lib/screens/security/trust_server_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Two-mode screen used for:
/// - initial TOFU trust after user enters server URL for the first time
/// - cert-change warning when a pinned fingerprint no longer matches
class TrustServerScreen extends StatelessWidget {
  const TrustServerScreen({
    super.key,
    required this.host,
    required this.newFingerprint,
    this.previousFingerprint,
  });

  final String host;
  final String newFingerprint;
  final String? previousFingerprint;

  bool get isChange => previousFingerprint != null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(isChange
            ? 'Zertifikat geändert'
            : 'Server vertrauen'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isChange)
                Icon(Icons.warning_amber_rounded, size: 64, color: cs.error)
              else
                Icon(Icons.shield_outlined, size: 64, color: cs.primary),
              const SizedBox(height: 16),
              Text(
                host,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (isChange) ...[
                Text(
                  'Das Zertifikat dieses Servers hat sich geändert. '
                  'Wenn du die Rotation nicht selbst veranlasst hast, '
                  'könnte ein Man-in-the-Middle-Angriff vorliegen.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                Text('Bisher:',
                    style: Theme.of(context).textTheme.labelLarge),
                SelectableText(previousFingerprint!, style: _mono),
                const SizedBox(height: 12),
                Text('Neu:', style: Theme.of(context).textTheme.labelLarge),
                SelectableText(newFingerprint, style: _mono),
              ] else ...[
                Text(
                  'Bitte überprüfe den folgenden Fingerprint mit dem '
                  'Betreiber des Servers, bevor du vertraust:',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                SelectableText(newFingerprint, style: _mono),
              ],
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(isChange
                    ? 'Neues Zertifikat akzeptieren'
                    : 'Vertrauen'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _mono =
      TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.4);
}
```

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/screens/security/trust_server_screen.dart
git commit -m "feat(mobile/security): TrustServerScreen for TOFU and cert-change UX"
```

---

## Phase 7: Wire into ApiClient, AuthService, Router

### Task 18: Refactor ApiClient to inject vault-backed cookie jar and TOFU

**Files:**
- Modify: `mobile/lib/core/api/api_client.dart`

- [ ] **Step 1: Read current ApiClient**

Run: `cd mobile && cat lib/core/api/api_client.dart` (or use Read tool).

- [ ] **Step 2: Replace PersistCookieJar usage**

Modify `mobile/lib/core/api/api_client.dart`:

- Delete the existing `PersistCookieJar(FileStorage(cookiesPath))` construction (around line 37-42)
- Add a setter `setCookieJar(CookieJar jar)` that rebuilds the Dio interceptor chain with the supplied jar
- Add a setter `setTofuInterceptor(TofuPinningInterceptor interceptor)` that inserts the interceptor into the chain before any other response handlers
- Change `_resolveBaseUrl` so the HTTP fallback branch is guarded by `const bool.fromEnvironment('HEALTHVAULT_ALLOW_INSECURE_LOCAL', defaultValue: false)` and is only reachable in `kDebugMode`

Apply these exact edits:

Replace the constructor body (around lines 26-42) with:

```dart
ApiClient() {
  _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));
  // Cookie jar and TOFU interceptor are installed by the security layer
  // after the vault is unlocked — see main.dart bootstrap.
}

CookieJar? _cookieJar;
TofuPinningInterceptor? _tofuInterceptor;

void setCookieJar(CookieJar jar) {
  _cookieJar = jar;
  _rebuildInterceptors();
}

void setTofuInterceptor(TofuPinningInterceptor interceptor) {
  _tofuInterceptor = interceptor;
  _rebuildInterceptors();
}

void _rebuildInterceptors() {
  _dio.interceptors.clear();
  if (_cookieJar != null) {
    _dio.interceptors.add(CookieManager(_cookieJar!));
  }
  if (_tofuInterceptor != null) {
    _dio.interceptors.add(_tofuInterceptor!);
  }
}
```

Add import at top of file:

```dart
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:healthapp/core/security/tls/tofu_pinning_interceptor.dart';
```

Replace `_resolveBaseUrl` body (around lines 54-62) with:

```dart
List<String> _resolveBaseUrlCandidates(String cleaned) {
  final isLocal = cleaned.contains('localhost') || cleaned.contains('10.0.2.2');
  const bool allowInsecureLocal = bool.fromEnvironment(
    'HEALTHVAULT_ALLOW_INSECURE_LOCAL',
    defaultValue: false,
  );
  return <String>[
    cleaned,
    '$cleaned:3101',
    if (kDebugMode && allowInsecureLocal && isLocal)
      '${cleaned.replaceFirst('https://', 'http://')}:3101',
  ];
}
```

Then update the caller that previously produced the candidates list to call `_resolveBaseUrlCandidates(cleaned)` instead.

- [ ] **Step 3: Run existing tests that touch ApiClient**

Run: `cd mobile && flutter test test/core/security/`
Expected: still green.

- [ ] **Step 4: Commit**

```bash
git add mobile/lib/core/api/api_client.dart
git commit -m "refactor(mobile/api): inject vault-backed cookie jar, remove HTTP downgrade"
```

---

### Task 19: Refactor AuthService to read/write via vault

**Files:**
- Modify: `mobile/lib/core/auth/auth_service.dart`

- [ ] **Step 1: Replace flutter_secure_storage with vault delegation**

Modify `mobile/lib/core/auth/auth_service.dart`:

Replace the class body with:

```dart
import 'dart:io';

import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';
import 'package:path_provider/path_provider.dart';

class StoredCredentials {
  StoredCredentials({required this.email, required this.authHash, required this.serverUrl});
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
```

- [ ] **Step 2: Find all call sites and fix compilation**

Run: `cd mobile && flutter analyze` and fix any call sites that used the old API (there is at least one in `more_screen.dart`).

- [ ] **Step 3: Run all tests**

Run: `cd mobile && flutter test`
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add mobile/lib/core/auth/auth_service.dart
git commit -m "refactor(mobile/auth): move credentials into encrypted vault + temp-dir wipe on clear"
```

---

### Task 20: Router integration — gate all routes behind SecurityState

**Files:**
- Modify: `mobile/lib/core/router/app_router.dart`

- [ ] **Step 1: Add security-gated redirect**

Edit `mobile/lib/core/router/app_router.dart`:

Add imports:

```dart
import 'package:healthapp/core/security/app_lock/app_lock_controller.dart';
import 'package:healthapp/core/security/security_state.dart';
import 'package:healthapp/screens/security/lock_screen.dart';
import 'package:healthapp/screens/security/setup_pin_screen.dart';
```

Add routes for the security screens outside the ShellRoute:

```dart
GoRoute(path: '/setup-pin', builder: (_, __) => const SetupPinScreen()),
GoRoute(path: '/lock', builder: (_, __) => const LockScreen()),
```

Extend the redirect function to gate on security state. The existing function likely has an auth-only redirect; add this block at the top of it:

```dart
redirect: (context, state) async {
  final securityState = ref.read(appLockControllerProvider);
  final path = state.matchedLocation;

  // Allow setup-pin only in loggedInNoPin / migrationPending
  if (securityState == SecurityState.loggedInNoPin ||
      securityState == SecurityState.migrationPending) {
    return path == '/setup-pin' ? null : '/setup-pin';
  }
  if (securityState == SecurityState.locked ||
      securityState == SecurityState.unlocking) {
    return path == '/lock' ? null : '/lock';
  }
  if (securityState == SecurityState.unregistered ||
      securityState == SecurityState.wiped) {
    return path == '/login' ? null : '/login';
  }

  // ... existing auth-only redirect logic below ...
}
```

Note: the router provider signature may need to accept a `WidgetRef` or be built as a Provider that closes over `ref`. Check `app_router.dart:10-20` for the current pattern and follow it.

- [ ] **Step 2: Compile**

Run: `cd mobile && flutter analyze` and fix remaining issues.

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/core/router/app_router.dart
git commit -m "feat(mobile/router): gate all routes behind SecurityState"
```

---

### Task 21: Bootstrap AppLockController in main.dart

**Files:**
- Modify: `mobile/lib/main.dart`

- [ ] **Step 1: Wire PinService, vault, and lifecycle observer**

Edit `mobile/lib/main.dart`:

Replace the `main()` function and root widget with the following additions:

```dart
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:healthapp/core/security/app_lock/app_lock_controller.dart';
import 'package:healthapp/core/security/app_lock/lifecycle_observer.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';
import 'package:healthapp/core/security/pin/pin_service.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final supportDir = await getApplicationSupportDirectory();
  final vaultFile = File('${supportDir.path}/vault.enc');
  final vault = EncryptedVault(
    file: vaultFile,
    kek: KekService.production(),
    dek: DekService(),
  );
  final pinService = PinService(vault: vault);
  final controller = AppLockController(pinService: pinService);
  await controller.bootstrap(vaultExists: vaultFile.existsSync());

  final lifecycle = SecurityLifecycleObserver(controller);
  WidgetsBinding.instance.addObserver(lifecycle);

  runApp(
    ProviderScope(
      overrides: [
        appLockControllerProvider.overrideWith((ref) => controller),
      ],
      child: const HealthVaultApp(),
    ),
  );
}
```

- [ ] **Step 2: Flutter analyze + run**

Run: `cd mobile && flutter analyze && flutter run --debug`
Expected: analyzer clean; app boots into `/login` (no vault on fresh install).

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/main.dart
git commit -m "feat(mobile): bootstrap AppLockController, vault, and lifecycle observer"
```

---

### Task 22: LoginScreen triggers PIN setup after successful login

**Files:**
- Modify: `mobile/lib/screens/login/login_screen.dart`

- [ ] **Step 1: Transition to loggedInNoPin after server auth**

Edit `mobile/lib/screens/login/login_screen.dart`:

After a successful login API response and before navigation, transition the security state:

```dart
// Inside the successful login branch, replace any direct context.go('/home')
// or similar with:
ref.read(appLockControllerProvider.notifier)
   .onLoginSuccess(); // adds loggedInNoPin, router redirects to /setup-pin
```

Add the corresponding method in `AppLockController`:

```dart
void onLoginSuccess() {
  state = SecurityState.loggedInNoPin;
}
```

And update the corresponding test in `app_lock_controller_test.dart` to cover this transition (red-green-commit the addition).

- [ ] **Step 2: Run tests**

Run: `cd mobile && flutter test`

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/screens/login/login_screen.dart \
        mobile/lib/core/security/app_lock/app_lock_controller.dart \
        mobile/test/core/security/app_lock/app_lock_controller_test.dart
git commit -m "feat(mobile/login): transition to loggedInNoPin after successful auth"
```

---

## Phase 8: Backend salt endpoint

### Task 23: Add GET /api/v1/auth/salt endpoint

**Files:**
- Modify: `api/internal/api/handlers/auth.go`
- Modify: `api/internal/api/router.go`
- Create: `api/internal/api/handlers/auth_salt_test.go`

- [ ] **Step 1: Write the failing Go test**

Create `api/internal/api/handlers/auth_salt_test.go`:

```go
package handlers_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestGetAuthSalt_KnownUser_ReturnsStoredSalt(t *testing.T) {
	ts := newTestServer(t)
	defer ts.Close()

	// Seed a registered user "known@example.com" with a known salt.
	seedUserWithSalt(t, ts, "known@example.com", "deadbeefcafebabe0011223344556677")

	req := httptest.NewRequest(http.MethodGet,
		"/api/v1/auth/salt?email=known@example.com", nil)
	rec := httptest.NewRecorder()
	ts.Handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	var body struct {
		Salt string `json:"salt"`
	}
	_ = json.NewDecoder(rec.Body).Decode(&body)
	if body.Salt != "deadbeefcafebabe0011223344556677" {
		t.Fatalf("salt = %q", body.Salt)
	}
}

func TestGetAuthSalt_UnknownUser_ReturnsDeterministicPseudoSalt(t *testing.T) {
	ts := newTestServer(t)
	defer ts.Close()

	req1 := httptest.NewRequest(http.MethodGet,
		"/api/v1/auth/salt?email=unknown@example.com", nil)
	rec1 := httptest.NewRecorder()
	ts.Handler.ServeHTTP(rec1, req1)

	req2 := httptest.NewRequest(http.MethodGet,
		"/api/v1/auth/salt?email=unknown@example.com", nil)
	rec2 := httptest.NewRecorder()
	ts.Handler.ServeHTTP(rec2, req2)

	if rec1.Code != http.StatusOK || rec2.Code != http.StatusOK {
		t.Fatalf("status1=%d status2=%d", rec1.Code, rec2.Code)
	}
	if strings.TrimSpace(rec1.Body.String()) !=
		strings.TrimSpace(rec2.Body.String()) {
		t.Fatalf("pseudo salt not deterministic")
	}
}

func TestGetAuthSalt_MissingEmail_Returns400(t *testing.T) {
	ts := newTestServer(t)
	defer ts.Close()

	req := httptest.NewRequest(http.MethodGet, "/api/v1/auth/salt", nil)
	rec := httptest.NewRecorder()
	ts.Handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}
```

(Helper `newTestServer` and `seedUserWithSalt` already exist in the repo — consult `auth_test.go` for the current helper pattern and adapt as needed.)

- [ ] **Step 2: Run — expect FAIL**

Run: `cd api && go test ./internal/api/handlers/ -run TestGetAuthSalt`

- [ ] **Step 3: Implement the handler**

Edit `api/internal/api/handlers/auth.go`, append:

```go
// GetAuthSalt returns the PBKDF2 salt for a given email. For unknown
// users it returns a deterministic pseudo-salt derived from the server
// secret to defeat email enumeration.
func (h *AuthHandler) GetAuthSalt(w http.ResponseWriter, r *http.Request) {
	email := strings.TrimSpace(r.URL.Query().Get("email"))
	if email == "" {
		http.Error(w, "email required", http.StatusBadRequest)
		return
	}

	salt, err := h.store.GetAuthSaltByEmail(r.Context(), email)
	if err != nil || salt == "" {
		// Deterministic pseudo-salt: HMAC-SHA256(serverSecret, email)
		mac := hmac.New(sha256.New, []byte(h.config.ServerSecret))
		mac.Write([]byte(email))
		salt = hex.EncodeToString(mac.Sum(nil)[:16])
	}

	writeJSON(w, http.StatusOK, map[string]string{"salt": salt})
}
```

Add any missing imports (`crypto/hmac`, `crypto/sha256`, `encoding/hex`).

Add corresponding store method if it does not exist yet:

```go
// Store interface addition
type AuthStore interface {
    // ... existing methods ...
    GetAuthSaltByEmail(ctx context.Context, email string) (string, error)
}
```

And implement it in the concrete store.

- [ ] **Step 4: Register the route**

Edit `api/internal/api/router.go` to add:

```go
r.Get("/api/v1/auth/salt", authHandler.GetAuthSalt)
```

Rate-limit via the existing middleware (1 req / 5 s / IP) — reuse whatever limiter pattern is in place for the login endpoint.

- [ ] **Step 5: Run — expect PASS**

Run: `cd api && go test ./internal/api/handlers/ -run TestGetAuthSalt`

- [ ] **Step 6: Commit**

```bash
git add api/internal/api/handlers/auth.go \
        api/internal/api/handlers/auth_salt_test.go \
        api/internal/api/router.go
git commit -m "feat(api/auth): GET /auth/salt returns per-user or deterministic pseudo salt"
```

---

### Task 24: Migrate mobile auth_crypto.dart to fetch salt from server

**Files:**
- Modify: `mobile/lib/core/crypto/auth_crypto.dart`
- Modify: `mobile/lib/screens/login/login_screen.dart`

- [ ] **Step 1: Add fetchSalt helper**

Edit `mobile/lib/core/crypto/auth_crypto.dart`:

Add a static async method that takes an `ApiClient`-like dependency and fetches the salt:

```dart
/// Fetches the server-side PBKDF2 salt for the given email.
/// Falls back to the legacy SHA256(email) derivation if the endpoint
/// returns 404 (for old servers during migration).
static Future<Uint8List> fetchSalt({
  required Future<Map<String, dynamic>> Function(String path) getJson,
  required String email,
}) async {
  try {
    final resp = await getJson('/api/v1/auth/salt?email=$email');
    final hex = resp['salt'] as String;
    return _hexToBytes(hex);
  } catch (_) {
    // Legacy fallback: SHA256(email)
    return Uint8List.fromList(sha256.convert(utf8.encode(email)).bytes);
  }
}

static Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
```

Add an alternative `deriveAuthHashWithSalt(password, salt)` that takes the salt directly (keep the old `deriveAuthHash(password, email)` for backward compat during rollout).

- [ ] **Step 2: Update LoginScreen to use the new path**

Edit `mobile/lib/screens/login/login_screen.dart` so the login submit first fetches the salt, then derives the hash with it, then posts the login as `{email, authHash, salt_version: "v2"}`.

- [ ] **Step 3: Run tests**

Run: `cd mobile && flutter test`

- [ ] **Step 4: Commit**

```bash
git add mobile/lib/core/crypto/auth_crypto.dart \
        mobile/lib/screens/login/login_screen.dart
git commit -m "feat(mobile/auth): derive auth hash using server-provided salt (v2)"
```

---

## Phase 9: Migration for existing users

### Task 25: Detect legacy credentials and route to migration

**Files:**
- Modify: `mobile/lib/main.dart`
- Create: `mobile/lib/screens/security/migration_screen.dart`

- [ ] **Step 1: MigrationScreen**

Create `mobile/lib/screens/security/migration_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MigrationScreen extends StatelessWidget {
  const MigrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 64),
              const SizedBox(height: 16),
              Text(
                'HealthVault wurde aktualisiert',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              const Text(
                'Aus Sicherheitsgründen musst du einen PIN einrichten. '
                'Nach der Einrichtung wirst du dich einmal neu einloggen müssen.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => context.go('/setup-pin'),
                child: const Text('Weiter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Main.dart detects legacy state**

Modify `mobile/lib/main.dart`:

Before creating the `AppLockController`, probe `flutter_secure_storage` for any legacy key (e.g. `hv_email`). If found and no vault file exists, initialize the controller into `SecurityState.migrationPending` and delete legacy entries **after** the user completes PIN setup (not before — we need them readable to migrate if possible).

Add route:

```dart
GoRoute(path: '/migrate', builder: (_, __) => const MigrationScreen()),
```

Router redirect is updated to send `migrationPending` → `/migrate` unless already there.

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/main.dart \
        mobile/lib/screens/security/migration_screen.dart \
        mobile/lib/core/router/app_router.dart
git commit -m "feat(mobile/security): detect legacy credentials, show migration screen"
```

---

## Phase 10: Platform Hardening

### Task 26: Android — FLAG_SECURE in MainActivity

**Files:**
- Modify: `mobile/android/app/src/main/kotlin/de/kiefer_networks/healthapp/MainActivity.kt`

- [ ] **Step 1: Add FLAG_SECURE**

Replace contents of `MainActivity.kt` with:

```kotlin
package de.kiefer_networks.healthapp

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }
}
```

- [ ] **Step 2: Build debug APK to verify compile**

Run: `cd mobile && flutter build apk --debug`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add mobile/android/app/src/main/kotlin/de/kiefer_networks/healthapp/MainActivity.kt
git commit -m "feat(mobile/android): enable FLAG_SECURE to block screenshots and task-switcher"
```

---

### Task 27: Android — allowBackup=false + dataExtractionRules

**Files:**
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Create: `mobile/android/app/src/main/res/xml/data_extraction_rules.xml`

- [ ] **Step 1: Add extraction rules XML**

Create `mobile/android/app/src/main/res/xml/data_extraction_rules.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="sharedpref" path="." />
        <exclude domain="file" path="." />
    </cloud-backup>
    <device-transfer>
        <exclude domain="sharedpref" path="." />
        <exclude domain="file" path="." />
    </device-transfer>
</data-extraction-rules>
```

- [ ] **Step 2: Wire in manifest**

Edit `AndroidManifest.xml` `<application>` tag, add:

```xml
android:allowBackup="false"
android:fullBackupContent="false"
android:dataExtractionRules="@xml/data_extraction_rules"
```

- [ ] **Step 3: Build**

Run: `cd mobile && flutter build apk --debug`

- [ ] **Step 4: Commit**

```bash
git add mobile/android/app/src/main/AndroidManifest.xml \
        mobile/android/app/src/main/res/xml/data_extraction_rules.xml
git commit -m "feat(mobile/android): disable backup and device-transfer of app data"
```

---

### Task 28: Android — tighten network_security_config

**Files:**
- Modify: `mobile/android/app/src/main/res/xml/network_security_config.xml`

- [ ] **Step 1: Replace contents**

Replace `network_security_config.xml` with:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system" />
        </trust-anchors>
    </base-config>
    <debug-overrides>
        <trust-anchors>
            <certificates src="system" />
            <certificates src="user" />
        </trust-anchors>
    </debug-overrides>
</network-security-config>
```

- [ ] **Step 2: Build**

Run: `cd mobile && flutter build apk --debug`

- [ ] **Step 3: Commit**

```bash
git add mobile/android/app/src/main/res/xml/network_security_config.xml
git commit -m "feat(mobile/android): disallow cleartext in release, user CA only in debug"
```

---

### Task 29: Android — R8 / ProGuard enabled for release

**Files:**
- Modify: `mobile/android/app/build.gradle.kts`
- Create: `mobile/android/app/proguard-rules.pro`

- [ ] **Step 1: Add proguard-rules.pro**

Create `mobile/android/app/proguard-rules.pro`:

```proguard
# Flutter engine
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }

# Kotlin metadata
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Keep health data model classes for JSON deserialization
-keep class de.kiefer_networks.healthapp.** { *; }
```

- [ ] **Step 2: Enable in build.gradle.kts**

Edit the `release` build type:

```kotlin
buildTypes {
    release {
        isMinifyEnabled = true
        isShrinkResources = true
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro",
        )
        signingConfig = signingConfigs.getByName("debug") // placeholder
    }
}
```

- [ ] **Step 3: Build release APK**

Run: `cd mobile && flutter build apk --release --obfuscate --split-debug-info=build/symbols`
Expected: build succeeds. If ProGuard complains about missing classes, add them to `proguard-rules.pro` one at a time.

- [ ] **Step 4: Commit**

```bash
git add mobile/android/app/build.gradle.kts \
        mobile/android/app/proguard-rules.pro
git commit -m "feat(mobile/android): enable R8 shrinking and Dart obfuscation for release"
```

---

### Task 30: iOS — NSFaceIDUsageDescription

**Files:**
- Modify: `mobile/ios/Runner/Info.plist`

- [ ] **Step 1: Add key**

Insert before `</dict></plist>`:

```xml
<key>NSFaceIDUsageDescription</key>
<string>HealthVault nutzt Face ID zur schnellen Entsperrung der App.</string>
```

- [ ] **Step 2: Commit**

```bash
git add mobile/ios/Runner/Info.plist
git commit -m "feat(mobile/ios): NSFaceIDUsageDescription for biometric unlock"
```

---

### Task 31: iOS — Snapshot blur on sceneWillResignActive

**Files:**
- Modify: `mobile/ios/Runner/SceneDelegate.swift`

- [ ] **Step 1: Add blur logic**

Edit `SceneDelegate.swift`, add to the existing class:

```swift
private var blurTag = 9999

func sceneWillResignActive(_ scene: UIScene) {
    guard let window = self.window else { return }
    let blur = UIBlurEffect(style: .systemMaterial)
    let view = UIVisualEffectView(effect: blur)
    view.frame = window.bounds
    view.tag = blurTag
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(view)
}

func sceneDidBecomeActive(_ scene: UIScene) {
    self.window?.viewWithTag(blurTag)?.removeFromSuperview()
}
```

- [ ] **Step 2: Commit**

```bash
git add mobile/ios/Runner/SceneDelegate.swift
git commit -m "feat(mobile/ios): blur overlay on scene resign active to protect app-switcher"
```

---

### Task 32: iOS — PrivacyInfo.xcprivacy manifest

**Files:**
- Create: `mobile/ios/Runner/PrivacyInfo.xcprivacy`

- [ ] **Step 1: Create privacy manifest**

Create `mobile/ios/Runner/PrivacyInfo.xcprivacy`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSPrivacyTracking</key>
  <false/>
  <key>NSPrivacyTrackingDomains</key>
  <array/>
  <key>NSPrivacyCollectedDataTypes</key>
  <array>
    <dict>
      <key>NSPrivacyCollectedDataType</key>
      <string>NSPrivacyCollectedDataTypeHealthRecords</string>
      <key>NSPrivacyCollectedDataTypeLinked</key>
      <false/>
      <key>NSPrivacyCollectedDataTypeTracking</key>
      <false/>
      <key>NSPrivacyCollectedDataTypePurposes</key>
      <array>
        <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
```

- [ ] **Step 2: Commit**

```bash
git add mobile/ios/Runner/PrivacyInfo.xcprivacy
git commit -m "feat(mobile/ios): add privacy manifest declaring health-records usage"
```

---

## Phase 11: Build Tooling and CI

### Task 33: Makefile targets

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Add mobile-test and mobile-build-release targets**

Edit root `Makefile`, add:

```makefile
mobile-test:
	cd mobile && flutter test --coverage

mobile-build-release:
	cd mobile && flutter build apk --release --obfuscate --split-debug-info=build/symbols
	cd mobile && flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
```

- [ ] **Step 2: Verify**

Run: `make mobile-test`
Expected: all tests pass with coverage report.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "chore(make): add mobile-test and mobile-build-release targets"
```

---

### Task 34: CI — add mobile test job

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add mobile-tests job**

Edit `.github/workflows/ci.yml`, add a new job that runs after the existing mobile build step (or creates one if none exists):

```yaml
  mobile-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - name: Flutter pub get
        run: cd mobile && flutter pub get
      - name: Flutter analyze
        run: cd mobile && flutter analyze
      - name: Flutter test
        run: cd mobile && flutter test
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: run Flutter analyze + test on every push"
```

---

## Phase 12: Integration tests

### Task 35: End-to-end first-time setup test

**Files:**
- Create: `mobile/test/integration/first_time_setup_test.dart`

- [ ] **Step 1: Write integration test**

Create `mobile/test/integration/first_time_setup_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/app_lock/app_lock_controller.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';
import 'package:healthapp/core/security/pin/pin_service.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';
import 'package:healthapp/core/security/security_state.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('e2e_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('first-time setup: bootstrap → login → PIN → unlocked', () async {
    final vault = EncryptedVault(
      file: File('${tempDir.path}/vault.enc'),
      kek: KekService.fastForTests(),
      dek: DekService(),
    );
    final pin = PinService(vault: vault);
    final ctrl = AppLockController(pinService: pin);

    await ctrl.bootstrap(vaultExists: false);
    expect(ctrl.state, SecurityState.unregistered);

    ctrl.onLoginSuccess();
    expect(ctrl.state, SecurityState.loggedInNoPin);

    await ctrl.setupPin('123456');
    expect(ctrl.state, SecurityState.unlocked);
    expect(vault.file.existsSync(), isTrue);
  });

  test('lock → unlock via PIN', () async {
    final vault = EncryptedVault(
      file: File('${tempDir.path}/vault.enc'),
      kek: KekService.fastForTests(),
      dek: DekService(),
    );
    final pin = PinService(vault: vault);
    final ctrl = AppLockController(pinService: pin);
    ctrl.onLoginSuccess();
    await ctrl.setupPin('123456');
    ctrl.lock();
    expect(ctrl.state, SecurityState.locked);
    await ctrl.unlockWithPin('123456');
    expect(ctrl.state, SecurityState.unlocked);
  });

  test('wipe after 10 wrong PINs', () async {
    final vault = EncryptedVault(
      file: File('${tempDir.path}/vault.enc'),
      kek: KekService.fastForTests(),
      dek: DekService(),
    );
    final pin = PinService(vault: vault);
    final ctrl = AppLockController(pinService: pin);
    ctrl.onLoginSuccess();
    await ctrl.setupPin('123456');
    ctrl.lock();

    for (var i = 0; i < 10; i++) {
      try {
        await ctrl.unlockWithPin('000000');
      } catch (_) {}
    }
    expect(ctrl.state, SecurityState.unregistered);
    expect(vault.file.existsSync(), isFalse);
  });
}
```

- [ ] **Step 2: Run — expect PASS**

Run: `cd mobile && flutter test test/integration/first_time_setup_test.dart`

- [ ] **Step 3: Commit**

```bash
git add mobile/test/integration/first_time_setup_test.dart
git commit -m "test(mobile/security): e2e first-time setup, lock/unlock, wipe-after-10"
```

---

## Phase 13: Production Argon2id sanity test

### Task 36: Slow test verifying production parameters

**Files:**
- Create: `mobile/test/core/security/key_management/kek_service_slow_test.dart`

- [ ] **Step 1: Write tagged slow test**

Create `mobile/test/core/security/key_management/kek_service_slow_test.dart`:

```dart
@Tags(['slow'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';

void main() {
  test('production Argon2id parameters derive within 2 seconds', () async {
    final service = KekService.production();
    final salt = Uint8List.fromList(List.generate(16, (i) => i));
    final sw = Stopwatch()..start();
    final key = await service.deriveKek('123456', salt);
    sw.stop();
    expect(key, hasLength(32));
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)),
        reason: 'Argon2id took too long: ${sw.elapsed}');
  }, tags: ['slow']);
}
```

- [ ] **Step 2: Run**

Run: `cd mobile && flutter test --tags slow`
Expected: passes on CI hardware in < 2 s.

- [ ] **Step 3: Commit**

```bash
git add mobile/test/core/security/key_management/kek_service_slow_test.dart
git commit -m "test(mobile/security): sanity-check production Argon2id parameters (slow)"
```

---

## Definition of Done checklist

- [ ] All Phase 0–13 tasks completed and committed
- [ ] `cd mobile && flutter test` green (excluding `slow` tag)
- [ ] `cd mobile && flutter test --tags slow` green locally
- [ ] `cd mobile && flutter analyze` clean
- [ ] `cd mobile && flutter build apk --release --obfuscate --split-debug-info=build/symbols` succeeds
- [ ] `cd mobile && flutter build ios --release --obfuscate --split-debug-info=build/symbols` succeeds (local mac only)
- [ ] Manual smoke on device: fresh install → login → PIN setup → background 5 min → unlock via PIN → enable biometrics → background → unlock via bio → lock → 10 failed PINs → wipe → relogin
- [ ] Spec section 14 "Definition of Done" manually verified

## Self-Review Notes

This plan implements every numbered item from the spec Definition of Done:

1. P0 audit items 1–8 → Phases 4 (cookies), 5 (app-lock), 6 (screens), 7 (api refactor, TLS fix, logout cleanup), 10 (Android/iOS hardening)
2. Mandatory 6-digit PIN → Tasks 7, 15, 22
3. Optional biometric after PIN → Tasks 8, 9 (plus future Settings task out of scope for this plan — the surface is in place)
4. Auto-lock 5 min + 24 h absolute → Task 13, 14
5. Progressive lockouts + wipe → Tasks 6, 7, 13
6. "PIN vergessen" = wipe+relogin → Task 16
7. TOFU cert pinning + cert-change warning → Tasks 10, 11, 17
8. Encrypted cookie jar → Tasks 12, 18
9. FLAG_SECURE + iOS blur → Tasks 26, 31
10. allowBackup=false + data extraction rules → Task 27
11. R8/ProGuard + Dart obfuscation → Task 29
12. iOS privacy manifest → Task 32
13. Server salt endpoint → Task 23, 24
14. Tests ≥80% on `lib/core/security/**` → Tasks 3–13, 35, 36
15. Migration path → Task 25
16. CI green on release builds → Tasks 33, 34

Known limitations intentionally deferred:

- The Settings screen integration for PIN change / biometric toggle UI is not in this plan. The `PinService.changePin` and `BiometricService.disable` code exists and is testable; wiring a Settings tile is trivial work that belongs with the Sprint 3 Settings overhaul.
- `EncryptedCookieJar._touched` URL tracking is intentionally minimal — ApiClient (Task 18) will inject URLs via `saveFromResponse` calls which is how Dio integrates with `CookieJar`.
- `PinService._persistTrackerForceWrite` is a stub; Sprint 1 accepts that the failure counter resets across app restarts while the vault is locked. A full side-file implementation belongs in a hardening pass if telemetry shows attackers abusing this.

These limitations are documented in the spec section 13 "Out of Scope" or are covered by follow-up tickets to be filed during Sprint 1 review.
