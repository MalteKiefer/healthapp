# HealthVault Security Architecture

## Zero-Knowledge Architecture

HealthVault is designed so that the server never has access to plaintext health data. All medical records are encrypted client-side before transmission. The server stores only ciphertext and never possesses the keys required to decrypt it.

- The user's passphrase never leaves the browser.
- Encryption and decryption happen exclusively in the client using the WebCrypto API (`window.crypto.subtle`).
- The server authenticates users via a derived auth hash, which is a separate derivation from the same passphrase but with a different salt -- the server never sees the passphrase itself.
- Even a full database compromise yields only ciphertext and public keys.

---

## Key Hierarchy

### PEK (Personal Encryption Key)

- Derived from the user's passphrase via PBKDF2-SHA256 (600,000 iterations, WebCrypto-native) using a per-user `pek_salt`.
- Produces an AES-256-GCM key.
- Used to encrypt/decrypt the user's private keys (identity and signing).
- Held only in browser memory; never persisted to disk or sent to the server.

### Auth Hash

- Derived from the same passphrase using a separate `auth_salt` (also PBKDF2-SHA256, 600,000 iterations).
- The resulting 256-bit hash is sent to the server for authentication.
- The server stores this auth hash after a second round of hashing with Argon2id (see below).
- Salt separation ensures that compromising the auth hash does not reveal the PEK.

### Profile Keys (PK)

- Each profile has its own random AES-256-GCM key generated via `crypto.subtle.generateKey`.
- All health records within a profile are encrypted with that profile's PK.
- Profile keys are extractable so they can be wrapped (encrypted) for sharing and grants.

### Identity Keypair

- ECDH P-256 keypair used for key exchange (profile key grants between users).
- The public key is stored on the server in plaintext.
- The private key is encrypted with the PEK and stored on the server as `identity_privkey_enc`.
- Used to derive shared secrets for wrapping/unwrapping profile keys during grant operations.

### Signing Keypair

- Reserved for future use (Ed25519 signatures).
- The public key is stored on the server in plaintext.
- The private key is encrypted with the PEK and stored on the server as `signing_privkey_enc`.

### Key Wrapping for Grants

- When granting another user access to a profile, the profile key is wrapped (encrypted) using AES-256-GCM with a key derived from an ECDH shared secret between the granter's and grantee's identity keypairs.
- The wrapped key blob is stored in `profile_key_grants`.
- Grant signatures provide cryptographic proof of authorization.

---

## Argon2id Password Hashing (Server-Side)

The auth hash received from the client is hashed again server-side using Argon2id before storage.

Parameters:
- **Algorithm:** Argon2id (hybrid, resistant to both side-channel and GPU attacks)
- **Memory:** 64 MB (`m=65536`)
- **Iterations:** 3 (`t=3`)
- **Parallelism:** 4 threads (`p=4`)
- **Output length:** 32 bytes
- **Salt length:** 16 bytes (random per user)

Verification uses constant-time comparison (`crypto/subtle.ConstantTimeCompare`) to prevent timing attacks.

Storage format: `$argon2id$v=19$m=65536,t=3,p=4$<salt>$<hash>` (PHC string format).

---

## JWT RS256 Token Management

### Token Types

- **Access Token:** Short-lived, carries `uid` (user ID), `role`, and `type: "access"`. Signed with RS256.
- **Refresh Token:** Longer-lived, used to obtain new access tokens without re-authentication.

### Signing

- Tokens are signed using RSA PKCS#1 v1.5 (RS256) with a server-held private key.
- Verification uses the corresponding public key.
- The issuer claim is set to `healthvault`.

### Revocation

- A Redis-based denylist tracks revoked token JTIs (JWT IDs).
- On logout or session revocation, the JTI is added to the denylist with a TTL matching the token's remaining lifetime.
- Every token verification checks the denylist before accepting the token.

### Session Tracking

- Each token pair is associated with a session record containing device hint, IP address, creation time, and expiry.
- Users can list active sessions and revoke individual sessions or all other sessions.

---

## Rate Limiting

Rate limiting uses a Redis-backed sliding window counter. Limits are enforced per IP address (default) or per authenticated user.

### Tiers

| Endpoint | Requests | Window | Block Duration |
|----------|----------|--------|----------------|
| /auth/register | 3 | 1 hour | 1 hour |
| /auth/register/complete | 3 | 1 hour | 1 hour |
| /auth/login | 5 | 15 minutes | 30 minutes |
| /auth/login/2fa | 5 | 15 minutes | 30 minutes |
| /auth/recovery | 3 | 1 hour | 2 hours |

When the limit is exceeded and a block duration is configured, subsequent requests are rejected for the block duration without consuming further counter entries.

On Redis failure, the limiter fails open (allows the request) to avoid locking out users.

Standard `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`, and `Retry-After` headers are returned.

---

## Emergency Access Model

Emergency access allows a third party (e.g., paramedic) to request access to a user's health data through a controlled process.

### Configuration

- Each profile can enable emergency access with configurable parameters:
  - `wait_hours`: Delay before auto-approval (gives the owner time to deny).
  - `auto_approve`: Whether requests are auto-approved after the wait period.
  - `notify_on_request`: Whether the owner is notified of access requests.
  - `visible_fields`: Restrict which data categories are visible.

### Flow

1. The user generates an emergency card/token for a profile.
2. A third party submits a request via `POST /emergency/request/{token}`.
3. The request enters `pending` status (or `approved` immediately if `auto_approve` is true and `wait_hours` is 0).
4. The profile owner can approve or deny pending requests.
5. After `wait_hours`, pending requests are auto-approved if configured.

### Data Scope

- Emergency card data is a pre-encrypted blob stored server-side.
- Visible fields are controlled by the emergency access configuration, limiting exposure to only what the user has opted to share.

---

## Temporary Doctor Access (Fragment-Based)

Temporary doctor shares provide time-limited, read-only access to selected health records without requiring the doctor to have a HealthVault account.

### Flow

1. The user's browser generates a random 256-bit temporary key.
2. Selected records are re-encrypted client-side with this temporary key.
3. The ciphertext bundle is uploaded to the server, which returns a `share_id`.
4. A share URL is constructed: `https://<host>/share/<share_id>#<base64(tempKey)>`.
5. The URL fragment (`#<tempKey>`) is never sent to the server (per the URL specification).
6. The doctor opens the URL; the browser fetches the ciphertext and decrypts it using the fragment key.
7. Shares are read-only and expire after a configurable period (maximum 7 days).

### Security Properties

- The server never possesses the decryption key for the shared data.
- Revoking a share deletes the ciphertext from the server, making the URL useless.
- Each share is independently encrypted; revoking one does not affect others.
- The temporary key is distinct from all other keys in the hierarchy.

---

## Backup Encryption

- Data exports and backups contain only ciphertext as stored in the database.
- Since the server never has plaintext, backups are encrypted at rest by design.
- Scheduled exports (`POST /export/schedule`) produce encrypted archives that can only be decrypted by the user who holds the profile keys.
- FHIR R4 exports (`GET /profiles/{profileID}/export/fhir`) return encrypted payloads that the client decrypts before use.

---

## WebCrypto Implementation Notes

All client-side cryptography uses the W3C WebCrypto API exclusively. No third-party cryptography libraries are used.

### Algorithms

| Purpose | Algorithm | Parameters |
|---------|-----------|------------|
| PEK derivation | PBKDF2-SHA256 | 600,000 iterations |
| Auth hash derivation | PBKDF2-SHA256 | 600,000 iterations, separate salt |
| Record encryption | AES-256-GCM | 12-byte random IV, 128-bit tag |
| Key exchange | ECDH P-256 | WebCrypto `deriveKey` / `deriveBits` |
| Key wrapping | AES-256-GCM `wrapKey` | 12-byte random IV, 128-bit tag |
| Random generation | `crypto.getRandomValues` | CSPRNG |

### Ciphertext Format

All encrypted values are stored as `base64(IV || ciphertext || tag)`:
- IV: 12 bytes (96 bits), randomly generated per encryption operation.
- Tag: 128 bits, appended by WebCrypto as part of the AES-GCM ciphertext output.

### Key Storage

- Keys are held only in JavaScript memory (`CryptoKey` objects).
- Keys are never serialized to `localStorage`, `sessionStorage`, `IndexedDB`, or cookies.
- `clearAllKeys()` zeroes the in-memory key store on logout.
- PEK is marked as non-extractable; profile keys are extractable only to support wrapping for grants.
