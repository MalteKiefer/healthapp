# Mobile Security Foundation + PIN/Biometric — Design Spec

**Date:** 2026-04-10
**Scope:** Flutter mobile app (`mobile/`)
**Sprint:** 1 of 3 (Security Foundation)
**Status:** Approved for implementation planning

## 1. Context and Goals

The Flutter mobile app currently exposes several production-blocking security gaps identified in the 2026-04-10 mobile audit:

1. Session cookies persisted to a plaintext `.cookies` file via `PersistCookieJar(FileStorage(...))`
2. No certificate pinning — vulnerable to MITM through rogue CAs or corporate proxies
3. No app-lock on background/resume — an unlocked phone grants full access to all health data
4. No PIN or biometric authentication at all (`local_auth` not in `pubspec.yaml`)
5. No screenshot/task-switcher protection — health data visible in app-switcher previews
6. TLS downgrade path to HTTP in debug mode that could leak into release builds
7. `android:allowBackup` not disabled — Google-backup exfiltration of credentials
8. Logout does not wipe cookies file or cached documents in the temp directory

Sprint 1 addresses all eight items plus introduces user-requested PIN and biometric authentication. The user explicitly requires that **a PIN must be set before biometrics can be enabled**, and that all sensitive data must be encrypted.

This spec is Sprint 1 of a three-sprint roadmap. Sprints 2 and 3 cover feature parity with the web/API and Material 3 UX hardening respectively; they are out of scope here.

## 2. Architecture Overview

### 2.1 New module: `lib/core/security/`

A new security module replaces scattered auth/crypto logic with a central, testable layer:

```
lib/core/security/
├── key_management/
│   ├── kek_service.dart          # Argon2id(PIN, salt) → Key Encryption Key
│   ├── dek_service.dart          # Random 256-bit Data Encryption Key, wrapped
│   └── keystore_binding.dart     # Android StrongBox / iOS Secure Enclave handles
├── pin/
│   ├── pin_service.dart          # Setup, verify, change, forgotten-wipe
│   └── pin_attempt_tracker.dart  # Progressive lockouts + wipe-after-10
├── biometric/
│   └── biometric_service.dart    # local_auth wrapper, unlocks DEK via keystore
├── secure_store/
│   └── encrypted_vault.dart      # AES-256-GCM vault over flutter_secure_storage
├── tls/
│   ├── tofu_pinning_interceptor.dart  # Dio interceptor: SPKI check per request
│   └── cert_fingerprint_store.dart    # Reads/writes TOFU pins from vault
├── app_lock/
│   ├── app_lock_controller.dart       # Riverpod controller, lifecycle, timeouts
│   └── lifecycle_observer.dart        # WidgetsBindingObserver
└── security_state.dart                # State enum
```

### 2.2 Modified existing modules

- `lib/core/api/api_client.dart` — `PersistCookieJar` replaced by `EncryptedCookieJar`, TOFU interceptor injected, HTTP fallback compile-removed from release builds
- `lib/core/auth/auth_service.dart` — credentials read/write via `EncryptedVault`; `clearCredentials()` additionally wipes cookie file, temp-dir cached documents, and old keystore entries
- `lib/core/crypto/auth_crypto.dart` — PBKDF2 kept for server login, but salt is fetched from new `GET /auth/salt?email=...` endpoint instead of derived from `SHA256(email)`
- `lib/main.dart` — registers `LifecycleObserver`, initializes `AppLockController`
- `lib/core/router/app_router.dart` — redirect logic extended to handle `locked`, `loggedInNoPin`, `unregistered` states; three new full-screen routes added
- `android/app/src/main/kotlin/.../MainActivity.kt` — sets `FLAG_SECURE`
- `android/app/src/main/AndroidManifest.xml` — `android:allowBackup="false"`, `dataExtractionRules`
- `android/app/src/main/res/xml/data_extraction_rules.xml` — **new**
- `android/app/build.gradle.kts` — R8/ProGuard enabled for release
- `android/app/proguard-rules.pro` — **new**
- `ios/Runner/SceneDelegate.swift` — **new if missing**; installs blur overlay on `sceneWillResignActive`
- `ios/Runner/Info.plist` — adds `NSFaceIDUsageDescription`
- `ios/Runner/PrivacyInfo.xcprivacy` — **new**

### 2.3 New pubspec dependencies

```yaml
local_auth: ^2.3.0          # Biometric authentication
cryptography: ^2.7.0        # Argon2id + AES-256-GCM (pointycastle stays for PBKDF2)
connectivity_plus: ^6.0.0   # Retry / offline detection (bonus)
```

`pointycastle` remains in the tree for the existing server-login PBKDF2 path. No migration of that code.

### 2.4 Security state machine

```
[Fresh Install]
      │ server URL + login
      ▼
[Logged in, no PIN]
      │ PIN setup (mandatory)
      ▼
[Unlocked] ──5 min background──▶ [Locked] ──Bio/PIN ok──▶ [Unlocked]
   │                                │
   │                                ├─10 failed PINs─▶ [Wiped] ─▶ [Fresh Install]
   │                                └─"PIN forgotten"─▶ [Wiped] ─▶ [Fresh Install]
   │
   ├──24 h absolute session timeout──▶ [Logged out fully]
   └──manual logout───────────────────▶ [Logged out fully]
```

PIN setup is **mandatory** immediately after the first successful server login. The user cannot dismiss it or use the app without setting a PIN. Biometric enrollment is optional and only available after a PIN exists.

## 3. Cryptography

### 3.1 Key hierarchy

```
           PIN (6 digits)
                │
                ▼  Argon2id(salt, memCost=64 MiB, parallelism=4, iterations=3, 32 B output)
              KEK  (transient, RAM only)
                │
                ▼  AES-256-GCM unwrap
              DEK  (256-bit random, persistent as wrapped blob)
                │
                ▼  AES-256-GCM
         vault entries (cookies, tokens, TOFU pins, server config)
```

**Rationale:**

- Only the DEK encrypts actual data; the KEK exists solely to unwrap the DEK.
- Changing the PIN only requires re-wrapping the DEK (cheap, atomic) — no re-encryption of all vault entries.
- Biometric enrollment adds a **second** parallel wrap of the DEK: an Android Keystore / iOS Keychain key with `biometryCurrentSet` / `invalidatedByBiometricEnrollment` flags wraps the same DEK. Unlocking via biometric → OS verifies biometric → keystore releases the wrapped DEK → vault opens. PIN stays always available as the guaranteed fallback.

### 3.2 Argon2id parameters

| Parameter | Value | Rationale |
| --- | --- | --- |
| Algorithm | Argon2id | Hybrid resistance to GPU and side-channel attacks |
| Memory cost | 64 MiB | OWASP 2024 mobile guidance; ~300 ms on mid-range devices |
| Iterations | 3 | OWASP interactive-login recommendation |
| Parallelism | 4 | Uses typical mobile core count |
| Salt length | 16 bytes | SecureRandom, generated once at PIN setup |
| Output | 32 bytes | AES-256 key size |

Tests use reduced parameters (`memCost=1 MiB, iter=1`) via a `@visibleForTesting` constructor so the suite runs in <1 s. A single production-parameter sanity test is kept.

### 3.3 EncryptedVault on-disk format

One file `vault.enc` in `getApplicationSupportDirectory()`:

```
Offset  Length  Field
0       4       Magic "HVLT"
4       1       Version (0x01)
5       16      Argon2id salt
21      variable  Wrapped DEK: 12-byte GCM nonce || ciphertext || 16-byte tag
...     variable  Optional second wrap: wrappedDekByBio (same structure)
...     variable  Entries table (JSON envelope, each entry: { key, nonce, ct, tag })
```

Each vault entry uses a **fresh 12-byte random nonce** (no nonce reuse across writes). The `cryptography` package enforces this via its `SecretBox` API.

### 3.4 Vault contents

| Data | Today | After Sprint 1 |
| --- | --- | --- |
| `email`, `authHash`, `serverUrl` | `flutter_secure_storage` | Vault entries |
| Session cookies | plaintext `.cookies` via `FileStorage` | Vault entry `cookies.v1` |
| TOFU cert pin (SPKI-SHA256) | does not exist | Vault entry `tofu.pin.v1` |
| Failed PIN attempts counter | does not exist | Vault entry `pin.attempts.v1` |
| PIN hash | — | **Not stored.** PIN verification = successful DEK unwrap (GCM tag check) |
| Language, theme | `SharedPreferences` | Stays in `SharedPreferences` (non-sensitive) |

**PIN verification by unwrap:** A correct PIN derives a correct KEK which successfully decrypts the wrapped DEK (GCM tag validates). A wrong PIN fails the tag check. There is no separate PIN hash to manipulate, and the timing is constant within Argon2id variance.

### 3.5 Wipe semantics

A "wipe" means:

1. Delete `vault.enc`
2. Delete keystore entries (Android `KeyStore.deleteEntry`, iOS `SecItemDelete`)
3. Delete any legacy `.cookies` file
4. Empty `getTemporaryDirectory()` (cached documents)
5. Clear security-relevant `SharedPreferences` keys (language/theme kept)
6. Re-create the Riverpod `ProviderContainer` to dispose every provider

Server-side data is **never** affected. After a wipe the app is in `unregistered` state.

### 3.6 Atomicity

All vault writes go through a temp-file + `rename()` pattern: write `vault.enc.tmp`, `flush`+`fsync`, then `rename` to `vault.enc`. Unix `rename` is atomic on both Android and iOS. A CRC32 over the vault header is verified on open; corruption triggers a "vault unrecoverable, please re-login" wipe path.

## 4. App-Lock and Lifecycle

### 4.1 SecurityState enum

```dart
enum SecurityState {
  unregistered,    // No server configured
  loggedInNoPin,   // Server auth succeeded, PIN setup pending
  locked,          // Vault exists, needs PIN/bio to unlock
  unlocking,       // Unlock attempt in flight
  unlocked,        // DEK in RAM, app operational
  wiped,           // Wipe just performed (for one-shot warning UX)
}
```

### 4.2 AppLockController (Riverpod)

Holds:

- Current `SecurityState`
- DEK reference (in RAM only; never serialized into the provider graph)
- `sessionStartAt` — set on successful unlock/login
- `backgroundedAt` — set when app enters `paused` state
- `lastInteractionAt` — advanced on successful API responses and root-level touches

### 4.3 Two independent timers

| Timer | Trigger | Action |
| --- | --- | --- |
| Background lock | `backgroundedAt + 5 min < now` | Transition to `locked`; PIN or biometric suffices |
| Absolute session | `sessionStartAt + 24 h < now` (active or not) | Full logout; server password required |

Both timers are checked on lifecycle `resumed` and additionally by a periodic check in the controller.

### 4.4 Lifecycle observer

A `WidgetsBindingObserver` registered in `main.dart` reacts to `AppLifecycleState`:

- **`inactive`** (iOS app-switcher, control-center swipe) → show snapshot-blur view, DEK stays in RAM, no lock
- **`paused`** (actually backgrounded) → record `backgroundedAt`; after 5 min: `state = locked`, zero DEK in RAM
- **`resumed`** → check both timers, route accordingly
- **`detached`** → dispose DEK, dispose provider container

### 4.5 Router integration

`GoRouter.redirect` is extended:

```
securityState == unregistered   → /login
securityState == loggedInNoPin  → /setup-pin   (all other routes blocked)
securityState == locked         → /lock        (all other routes blocked)
securityState == unlocked       → normal routes
```

Three new full-screen routes, outside the `ShellRoute` (no navigation bar):

- `/setup-pin`
- `/lock`
- `/trust-server`

### 4.6 Screens

**`/setup-pin`**
1. Page 1: "Wähle einen 6-stelligen PIN" + numpad
2. Page 2: "PIN wiederholen" + numpad
3. On mismatch: return to page 1 with error message
4. On success: optional biometric opt-in (if available)
5. No cancel button — user is already logged in and cannot use the app without a PIN

**`/lock`**
- Six-dot PIN indicator
- Numpad 0–9, backspace, biometric icon (when enabled)
- Auto-triggers biometric prompt on open (if enabled); user can dismiss and use PIN
- "PIN vergessen?" link → forgotten flow
- Attempt counter: "2 / 10 Fehlversuche" displayed starting from the first failed try, red from 7 onward
- Lockout countdown when `lockoutUntil > now`

**`/trust-server`** — two modes
- **Initial trust (friendly):** "Erster Verbindungsaufbau zu `https://...`. Fingerprint: `ab:cd:ef:...`" → `[Vertrauen]` / `[Abbrechen]`
- **Cert change warning (red, stern):** warn icon; old fingerprint, new fingerprint; message warning about potential MITM; `[Neues Zertifikat akzeptieren]` (small, secondary) / `[Abbrechen und ausloggen]` (large, primary)

### 4.7 Locked-state access

**Nothing** is reachable in the `locked` state — not even About/Imprint/Settings. The server URL itself lives in the vault and is inaccessible without the PIN. Emergency-access pre-lock screens are explicitly deferred to Sprint 3.

### 4.8 Provider invalidation on lock

On `unlocked → locked`, all data-carrying providers (profiles, vitals, labs, medications, …) are invalidated via `ref.invalidate` so no health record survives in the provider cache. The Dio client keeps its configuration but the `EncryptedCookieJar` enters a locked state that returns empty cookies until the DEK is restored.

## 5. PIN Flows

### 5.1 Flow A — First PIN setup (mandatory after first login)

1. User logs in with email + password (existing flow)
2. Server responds 200 → `SecurityState = loggedInNoPin`
3. Router redirects to `/setup-pin`, blocking all other routes
4. User enters PIN (6 digits) twice
5. On match:
   1. `SecureRandom.generateBytes(16)` → salt
   2. `Argon2id(pin, salt, …)` → KEK
   3. `SecureRandom.generateBytes(32)` → DEK
   4. AES-256-GCM encrypt DEK under KEK → `wrappedDekByPin`
   5. Create `vault.enc` (atomic temp+rename)
   6. Migrate existing `email`, `authHash`, `serverUrl` from `flutter_secure_storage` into the vault
   7. Delete legacy `flutter_secure_storage` entries
   8. `sessionStartAt = now`; `SecurityState = unlocked`
6. Optional biometric opt-in screen (flow B)
7. Router → `/home`

### 5.2 Flow B — Enable biometrics (opt-in)

Can run immediately after first PIN setup, or later from Settings.

1. Probe `local_auth.canCheckBiometrics && deviceSupportsBiometrics`
2. If not available → disable toggle with reason text
3. User taps "Biometrie aktivieren"
4. User must enter the current PIN (authorization)
5. Derive DEK via PIN
6. Create OS keystore key:
   - **Android** `KeyGenParameterSpec` with `setUserAuthenticationRequired(true)`, `setInvalidatedByBiometricEnrollment(true)`, `setIsStrongBoxBacked(true)` where supported
   - **iOS** `SecAccessControl` with `.biometryCurrentSet` and `.privateKeyUsage`
7. Wrap DEK using that keystore key → `wrappedDekByBio`
8. Store `wrappedDekByBio` as second wrap in the vault
9. `biometric_enabled = true` preference stored inside the vault

`invalidatedByBiometricEnrollment` / `biometryCurrentSet` are critical: adding a new fingerprint or face to the OS invalidates the biometric wrap, forcing a PIN fallback. This blocks the "attacker with an unlocked phone enrolls their own biometric" attack.

### 5.3 Flow C — Unlock

1. App resumes; `SecurityState == locked`
2. Router → `/lock`
3. If biometric enabled and available → auto-trigger bio prompt
4. On bio success:
   1. Keystore releases `wrappedDekByBio` after OS verifies biometry
   2. Unwrap DEK; load into RAM
   3. `SecurityState = unlocked`; `failedAttempts` not touched (bio failure does not increment)
   4. Router back to last route or `/home`
5. On bio failure or cancel → numpad path
6. PIN entry:
   1. Check lockout window — if active, numpad disabled with countdown
   2. `Argon2id(pin, salt)` → KEK
   3. Attempt AES-GCM unwrap
   4. GCM tag OK → DEK in RAM; unlocked; `failedAttempts = 0`
   5. GCM tag fail → `failedAttempts++`; write to vault; apply lockout table

### 5.4 Lockout table

Stored in the vault so an attacker cannot reset it by editing disk state:

| Failed attempts | Reaction |
| --- | --- |
| 1–4 | "Falscher PIN" error, no delay |
| 5 | 1-minute lockout with countdown |
| 6 | 5 minutes |
| 7 | 15 minutes |
| 8 | 30 minutes |
| 9 | 1 hour |
| **10** | **Wipe** (flow D) |

A successful unlock resets the counter to zero. There is no time-window reset — an attacker with patience would otherwise be rewarded.

Clock-tamper guard: if `DateTime.now() < lastInteractionAt` the system clock has likely been rolled back; treat as a tamper attempt and set `lockoutUntil = now + currentLockoutDuration * 2`. Not perfect on rooted devices but removes the easiest offline attack.

### 5.5 Flow D — Wipe

Triggered by: 10 failed PIN attempts, "PIN vergessen", or explicit logout.

1. Confirmation dialog: "Dieser Vorgang löscht alle lokalen Daten dieser App. Deine Daten auf dem Server bleiben unverändert. Nach dem Wipe musst du dich mit Email + Passwort neu einloggen." (Automatic 10-fail path skips the dialog.)
2. Delete `vault.enc`
3. Delete keystore entries (Android and iOS)
4. Delete legacy `.cookies` file if present
5. Empty `getTemporaryDirectory()`
6. Clear security-relevant `SharedPreferences` keys
7. Re-create the Riverpod `ProviderContainer`
8. `SecurityState = wiped` (then `unregistered`)
9. Router → `/login`
10. One-shot banner at next start: "Aus Sicherheitsgründen wurden lokale Daten gelöscht."

### 5.6 Flow E — "PIN vergessen"

1. Tap "PIN vergessen?" on `/lock`
2. Warn dialog: "Alle lokalen Daten werden gelöscht. Willst du fortfahren?"
3. On confirm → wipe (flow D) → `/login`

No separate "soft" server-password re-auth path. It is technically identical to wipe+login; keeping one path reduces code and confusion.

### 5.7 Flow F — Change PIN (Settings)

1. Settings → "PIN ändern"
2. Enter old PIN (verified through the normal unlock path; counts toward `failedAttempts`)
3. Enter new PIN twice
4. Generate a fresh Argon2id salt (salt rotation)
5. `newKEK = Argon2id(newPin, newSalt)`
6. DEK unchanged; new wrap = `AES-GCM-encrypt(DEK, newKEK)`
7. Atomic vault update
8. If biometric was enabled: delete old bio keystore key, drop `wrappedDekByBio`, offer immediate re-enrollment

The DEK is deliberately **not** rotated on PIN change: there is no security gain (old DEK was never compromised) and it would require re-encryption of every vault entry, increasing complexity and atomicity risk.

### 5.8 Flow G — Disable biometrics

1. Settings → toggle biometric off
2. Verify current PIN
3. Delete bio keystore key
4. Drop `wrappedDekByBio` from vault
5. `biometric_enabled = false`

### 5.9 Edge cases

- **OS biometrics disabled/removed** (e.g. user deletes all fingerprints): next app open falls back to PIN; stale `wrappedDekByBio` stays until the next settings change (harmless, still encrypted)
- **App update with new vault version:** version byte in header; migration path in `EncryptedVault` open code. Sprint 1 ships version 0x01 but the structure is versioned
- **Device without StrongBox / Secure Enclave:** software-backed keystore is still better than nothing; warning hint in Settings, no hard fail

## 6. TLS, TOFU Certificate Pinning, Platform Hardening

### 6.1 EncryptedCookieJar

Replaces `PersistCookieJar(FileStorage(...))`. Backed by an in-memory `DefaultCookieJar` working copy:

- On unlock: read vault entry `cookies.v1`, deserialize into memory
- On lock: clear in-memory jar, DEK dropped
- On save/load: operate in memory
- On flush (debounced max once every 2 s, and on lock/background): serialize to vault

Cookies therefore never touch plaintext disk.

### 6.2 TOFU pinning interceptor

Implemented as a Dio `IOHttpClientAdapter` that wraps `HttpClient`. `badCertificateCallback` is **not** used to accept invalid certs — standard CA validation stays on. Additionally, after each successful TLS handshake the interceptor:

1. Extracts the peer X.509 certificate via a custom `HttpClient` wrapper that hooks `openUrl` to capture the socket's certificate into a request-scoped context
2. Computes SPKI-SHA256 of the peer cert
3. Reads the expected pin from `certFingerprintStore` (vault entry)
4. If no pin is stored and the `/trust-server` flow has already completed: pass (impossible in practice, see below)
5. If pin stored and matches → pass
6. If pin stored and mismatches → throw `TlsPinMismatchException`, router redirects to `/trust-server` in cert-change mode
7. If cert extraction fails → fail the request (fail-closed, no silent pass)

### 6.3 First-contact TOFU flow

1. User enters server URL in the login screen and taps "Weiter"
2. App issues a probe request (e.g. `GET /api/v1/auth/policy`) with a 10 s timeout
3. Standard TLS + CA validation
4. Extract peer cert → SPKI-SHA256 → hex fingerprint
5. No pin stored yet → router goes to `/trust-server` in initial-trust mode
6. UI shows server URL and fingerprint in grouped hex, message asking the user to verify with their server operator
7. On confirm: provisional pin held in `AppLockController` RAM (vault does not exist yet because PIN is not set)
8. Login flow continues: email + password → server auth → mandatory PIN setup
9. On successful PIN setup, the provisional pin and the server URL are persisted into the newly created vault as their first entries

### 6.4 Cert change warning flow

1. Mid-session the server cert changes (e.g. Let's Encrypt renewal by the admin)
2. Next API request → interceptor detects SPKI mismatch
3. `TlsPinMismatchException` thrown; all in-flight requests cancelled; `AppLockController` sets a cert-change flag
4. Router redirects to `/trust-server` in cert-change mode
5. Screen shows old fingerprint, new fingerprint, warning text
6. On accept: pin updated in vault; cookies retained; user continues
7. On cancel: cookies wiped; user must log in again (but server URL stays)

If the cert changed while the app was closed, the first probe request at startup hits the same exception and the same UI — identical UX.

### 6.5 TLS downgrade fix

The existing `_resolveBaseUrl` in `api_client.dart` falls back to `http://` for localhost in debug mode. Replaced with:

```dart
const bool allowInsecureLocal = bool.fromEnvironment(
  'HEALTHVAULT_ALLOW_INSECURE_LOCAL',
  defaultValue: false,
);
if (allowInsecureLocal && kDebugMode && isLocal) {
  candidates.add('http://$cleaned:3101');
}
```

Release builds have `kDebugMode == false` and the constant defaults to `false`, so Dart tree-shaking removes the HTTP path entirely from release binaries. Developers need to opt in explicitly via `--dart-define=HEALTHVAULT_ALLOW_INSECURE_LOCAL=true` even in debug.

### 6.6 Android hardening

**`AndroidManifest.xml`:** add `android:allowBackup="false"`, `android:dataExtractionRules="@xml/data_extraction_rules"`, `android:fullBackupContent="false"`.

**`data_extraction_rules.xml`** (new): excludes all shared prefs and files from cloud backup and device transfer.

**`MainActivity.kt`:** set `FLAG_SECURE` in `onCreate`:

```kotlin
window.setFlags(
    WindowManager.LayoutParams.FLAG_SECURE,
    WindowManager.LayoutParams.FLAG_SECURE,
)
```

This blocks screenshots, screen recording, and task-switcher previews globally.

**`network_security_config.xml`** (existing, extended):

```xml
<network-security-config>
  <base-config cleartextTrafficPermitted="false">
    <trust-anchors><certificates src="system" /></trust-anchors>
  </base-config>
  <debug-overrides>
    <trust-anchors><certificates src="system" /><certificates src="user" /></trust-anchors>
  </debug-overrides>
</network-security-config>
```

**`build.gradle.kts`** release block: `isMinifyEnabled = true`, `isShrinkResources = true`, ProGuard files wired up.

**`proguard-rules.pro`** (new): keep rules for Flutter engine and any reflection-using codegen (freezed/json_serializable when adopted).

**Release build command:**

```
flutter build apk --release --obfuscate --split-debug-info=build/symbols
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
```

### 6.7 iOS hardening

**`Info.plist`:** add `NSFaceIDUsageDescription` with a user-facing reason string.

**`SceneDelegate.swift`** (new if missing): installs a blur view on `sceneWillResignActive`, removes it on `sceneDidBecomeActive`, protecting the app-switcher snapshot.

**`PrivacyInfo.xcprivacy`** (new): minimal manifest; declares `NSPrivacyCollectedDataTypeHealthRecords` as `AppFunctionality`, not linked to user, not tracking.

**ATS** remains default (HTTPS only), no exceptions.

### 6.8 Transit threat coverage

| Threat | Mitigation |
| --- | --- |
| Public Wi-Fi sniffing | TLS via system CAs |
| Rogue CA in store | TOFU pinning |
| Corporate SSL proxy | TOFU pinning |
| Legitimate cert rotation | Cert change warning with user consent |
| HTTP downgrade | Compile-time removal in release |
| Android cleartext | `cleartextTrafficPermitted="false"` |
| iOS cleartext | ATS default |
| Backup exfiltration | `allowBackup=false` + extraction rules |
| Screenshot leak | `FLAG_SECURE` (Android) + blur (iOS) |
| Task-switcher leak | `FLAG_SECURE` (Android) + blur (iOS) |
| Reverse engineering | R8 + Dart obfuscation + StrongBox/Secure Enclave |

## 7. Backend Changes

Only one API change is required for Sprint 1:

### 7.1 `GET /api/v1/auth/salt?email=...`

Returns the per-user server-generated PBKDF2 salt used for the authentication hash. Replaces the current deterministic `SHA256(email)` derivation.

- Rate-limited to 1 request / 5 s per IP to deter email enumeration
- For unknown users, returns a deterministic pseudo-salt computed as `HMAC(serverSecret, email)` so the response shape and timing are indistinguishable from the known-user path
- Registration must generate and store a random salt (verify in the existing code; add a migration if not already the case)

### 7.2 Backward compatibility (Option A — recommended)

During rollout, old mobile clients (using `SHA256(email)`) and new mobile clients (using server salt) must coexist. The login endpoint accepts a `salt_version` field: `"v1"` for the legacy path, `"v2"` for the new path. The user database holds both hashes during a three-month transition; on successful v2 login the v1 hash is invalidated. After the transition, v1 is switched off hard.

### 7.3 Explicitly out of scope

- 2FA/TOTP flows (Sprint 2)
- Refresh token rotation with shorter session TTLs (Sprint 2)
- Device-management / sessions listing (Sprint 2)

## 8. Testing Strategy

The mobile app currently has zero tests. Sprint 1 seeds the test suite with a focus on security-critical components.

### 8.1 Structure

```
test/
├── core/
│   ├── security/
│   │   ├── key_management/
│   │   │   ├── kek_service_test.dart
│   │   │   └── dek_service_test.dart
│   │   ├── pin/
│   │   │   ├── pin_service_test.dart
│   │   │   └── pin_attempt_tracker_test.dart
│   │   ├── secure_store/
│   │   │   └── encrypted_vault_test.dart
│   │   ├── tls/
│   │   │   ├── tofu_pinning_interceptor_test.dart
│   │   │   └── cert_fingerprint_store_test.dart
│   │   └── app_lock/
│   │       └── app_lock_controller_test.dart
│   └── api/
│       └── api_client_test.dart
└── integration/
    ├── first_time_setup_test.dart
    ├── lock_unlock_flow_test.dart
    ├── wipe_after_10_failed_test.dart
    └── cert_change_warning_test.dart
```

### 8.2 Infrastructure

- Riverpod overrides for every security provider — most tests are pure unit tests with no real crypto
- Reduced Argon2id parameters (`memCost=1 MiB, iter=1`) via `@visibleForTesting` constructor to keep the suite under one second
- One "slow" test verifies production parameters
- `FakeSecureStorage` implementing the `flutter_secure_storage` interface
- `FakeKeystoreBinding` mocking the platform channel for keystore/keychain
- `MockHttpClient` capable of injecting arbitrary peer certs for TLS interceptor tests

### 8.3 Coverage targets

- `lib/core/security/**` ≥ 80 %
- `lib/core/api/**` ≥ 50 %
- Screens remain untested in Sprint 1 — M3/UX rework in Sprint 3 will add widget tests

### 8.4 CI integration

A new `flutter test` step is added to the existing CI pipeline alongside web and API lint steps. A new Makefile target `mobile-test` runs `cd mobile && flutter test --coverage`.

## 9. Migration for Existing Users

### 9.1 First app start after update

1. `AppLockController` checks: does `vault.enc` exist?
2. If no, check for legacy entries in `flutter_secure_storage`
3. If legacy found → `SecurityState = migrationPending`
4. Router shows migration screen: "HealthVault wurde aktualisiert. Aus Sicherheitsgründen musst du einen PIN einrichten."
5. User taps `[Weiter]` → `/setup-pin`
6. PIN setup runs; vault created; legacy `email`/`authHash`/`serverUrl` migrated; legacy entries deleted; legacy `.cookies` file deleted
7. `SecurityState = unlocked`; user is asked to log in once more (cookies were not migrated)

### 9.2 Cookies are intentionally not migrated

They could be expired; they were plaintext on disk and must be considered potentially compromised; a clean re-login is cheap insurance. The migration screen clearly announces "Nach PIN-Einrichtung wirst du dich einmal neu einloggen müssen."

## 10. Build Configuration and CI

### 10.1 `pubspec.yaml`

New dependencies pinned with caret to allow patch updates only:

```yaml
local_auth: ^2.3.0
cryptography: ^2.7.0
connectivity_plus: ^6.0.0
```

### 10.2 `analysis_options.yaml`

Add lint rules:

```yaml
linter:
  rules:
    avoid_print: true
    prefer_const_constructors: true
```

### 10.3 Makefile targets

```
mobile-test: ; cd mobile && flutter test --coverage
mobile-build-release: ; cd mobile && flutter build apk --release --obfuscate --split-debug-info=build/symbols
```

### 10.4 CI pipeline

A new `mobile-tests` job runs before `mobile-build` and must be green.

## 11. Rollout Plan

1. Week 1 — API `/auth/salt` endpoint merged and deployed; backward compatibility verified against old clients
2. Week 2 — Mobile Sprint 1 implementation; local test suite; staging integration
3. Week 3 — Internal test builds via Android Internal Testing and iOS TestFlight; one or two internal testers
4. Week 4 — Wider beta; production release
5. Post-release — legacy v1 salt path remains on the server for three months; then hard-disabled

## 12. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Vault corruption mid-write | Low | High (user locked out) | Atomic temp+rename; CRC32 on open; corrupted-vault path triggers wipe + re-login with a clear message |
| Argon2id > 1 s on old devices | Medium | Low (UX annoyance) | Progress spinner during key derivation; ability to tune parameters downward if necessary |
| Biometric keystore key invalidated unexpectedly | Medium | Low (PIN fallback works) | PIN is always available; UI shows "bitte PIN eingeben" silently |
| TOFU probe request fails | Low | Medium (login blocked) | 10 s timeout; clear error message; retry button |
| Admin-driven cert rotation without app update | High | Low (one re-trust tap) | Cert change warning is designed for this; clear UI |
| Migration breaks existing users | Low | High | Thorough migration test suite; rollback plan keeps the old build downloadable |
| `cryptography` package minor-version API break | Low | Medium | Pin with caret (`^2.7.0`); explicit review on `flutter pub upgrade` |
| Toddler wipes the app by playing with the phone | Medium | High (user frustration) | Prominent "PIN vergessen" button; escalating lockouts give time to stop; documented behavior |

## 13. Out of Scope (Explicit)

- Offline-first / local encrypted cache of health data → Sprint 3
- 2FA / TOTP support → Sprint 2
- Device management / sessions list → Sprint 2
- Multi-server / multi-account → future
- Per-widget screenshot protection → global `FLAG_SECURE` is sufficient
- Hardware security keys (FIDO2) → future
- Emergency access pre-lock screen → Sprint 3
- Material 3 UX overhaul → Sprint 3
- Feature parity with web → Sprints 2 and 3
- `@riverpod` code-generation migration → cross-cutting, not part of Sprint 1 DoD

## 14. Definition of Done

- All eight P0 items from the security audit resolved
- Mandatory 6-digit numeric PIN setup after first login
- Optional biometric authentication, only available after PIN is set, hardware-backed where possible
- Auto-lock after 5 minutes backgrounded; absolute 24-hour session timeout
- Progressive lockouts at 5 → 6 → 7 → 8 → 9 failed attempts; wipe at 10
- "PIN vergessen" flows through the wipe path
- TOFU certificate pinning with cert-change warning UX
- Encrypted cookie jar; no plaintext cookies on disk
- `FLAG_SECURE` on Android; snapshot blur on iOS
- `allowBackup=false` plus `dataExtractionRules`
- R8/ProGuard and Dart obfuscation enabled for release builds
- iOS privacy manifest present
- Server-side PBKDF2 salt endpoint deployed; mobile switched to v2
- Tests covering `lib/core/security/**` at ≥ 80 %
- Migration path functional for existing installs
- CI green on Android and iOS release builds
