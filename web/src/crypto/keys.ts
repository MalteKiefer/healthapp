/**
 * HealthVault Client-Side Cryptography
 *
 * Key Hierarchy:
 * - PEK (Personal Encryption Key): derived from passphrase via Argon2id → AES-256-GCM
 * - Identity Keypair: X25519 for ECDH key exchange
 * - Signing Keypair: Ed25519 for signatures (future)
 * - Profile Key (PK): random AES-256-GCM key per profile
 *
 * All crypto uses WebCrypto API (window.crypto.subtle).
 * No third-party crypto libraries.
 */

import { encrypt, decryptToBytes } from './encrypt';

// Key store — held in sessionStorage (dies on tab close) so page refresh
// via refresh-token flow doesn't drop the crypto state. Keys are stashed as
// JWK, not in base64url raw form, to keep WebCrypto's usages metadata.
//
// Security trade-off: sessionStorage is readable by XSS, so a malicious
// script loaded in this tab could exfiltrate the profile keys. That is a
// known limitation of SPA E2E apps; a Service-Worker-scoped key store
// would be stricter but adds significant complexity.

const SS_PEK = 'hv_pek_jwk';
const SS_ID_PRIV = 'hv_id_priv_jwk';
const SS_PROFILE_KEYS = 'hv_profile_keys_jwk'; // { [profileId]: JsonWebKey }

let pek: CryptoKey | null = null;
let identityPrivKey: CryptoKey | null = null;
const profileKeys: Map<string, CryptoKey> = new Map();

function safeSessionSet(k: string, v: string) {
  try { sessionStorage.setItem(k, v); } catch { /* quota or disabled */ }
}
function safeSessionGet(k: string): string | null {
  try { return sessionStorage.getItem(k); } catch { return null; }
}
function safeSessionRemove(k: string) {
  try { sessionStorage.removeItem(k); } catch { /* ignore */ }
}

export function setPEK(key: CryptoKey) {
  pek = key;
  // key is extractable (see derivePEK) → stash as JWK so reloads can rehydrate.
  crypto.subtle.exportKey('jwk', key)
    .then((jwk) => safeSessionSet(SS_PEK, JSON.stringify(jwk)))
    .catch(() => { /* non-extractable, skip */ });
}

export function getPEK(): CryptoKey | null {
  return pek;
}

export function setIdentityPrivateKey(key: CryptoKey) {
  identityPrivKey = key;
  crypto.subtle.exportKey('jwk', key)
    .then((jwk) => safeSessionSet(SS_ID_PRIV, JSON.stringify(jwk)))
    .catch(() => { /* non-extractable, skip */ });
}

export function getIdentityPrivateKey(): CryptoKey | null {
  return identityPrivKey;
}

export function setProfileKey(profileId: string, key: CryptoKey) {
  profileKeys.set(profileId, key);
  // Persist the whole map — sessionStorage lookups are cheap.
  (async () => {
    const map: Record<string, JsonWebKey> = {};
    for (const [id, k] of profileKeys.entries()) {
      try {
        map[id] = await crypto.subtle.exportKey('jwk', k);
      } catch { /* skip non-extractable */ }
    }
    safeSessionSet(SS_PROFILE_KEYS, JSON.stringify(map));
  })();
}

export function getProfileKey(profileId: string): CryptoKey | null {
  return profileKeys.get(profileId) || null;
}

export function clearAllKeys() {
  pek = null;
  identityPrivKey = null;
  profileKeys.clear();
  safeSessionRemove(SS_PEK);
  safeSessionRemove(SS_ID_PRIV);
  safeSessionRemove(SS_PROFILE_KEYS);
}

/**
 * Rehydrate keys from sessionStorage on module load. Safe to call repeatedly.
 * Used by the app entry point so a page refresh (refresh-token session)
 * doesn't drop the profile-key material.
 */
export async function rehydrateKeysFromSession(): Promise<void> {
  if (typeof sessionStorage === 'undefined') return;

  const pekJwk = safeSessionGet(SS_PEK);
  if (pekJwk && !pek) {
    try {
      const jwk = JSON.parse(pekJwk) as JsonWebKey;
      pek = await crypto.subtle.importKey(
        'jwk', jwk, { name: 'AES-GCM', length: 256 }, true, ['encrypt', 'decrypt'],
      );
    } catch { safeSessionRemove(SS_PEK); }
  }

  const idPrivJwk = safeSessionGet(SS_ID_PRIV);
  if (idPrivJwk && !identityPrivKey) {
    try {
      const jwk = JSON.parse(idPrivJwk) as JsonWebKey;
      identityPrivKey = await crypto.subtle.importKey(
        'jwk', jwk, { name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveKey', 'deriveBits'],
      );
    } catch { safeSessionRemove(SS_ID_PRIV); }
  }

  const profileKeysJwk = safeSessionGet(SS_PROFILE_KEYS);
  if (profileKeysJwk) {
    try {
      const map = JSON.parse(profileKeysJwk) as Record<string, JsonWebKey>;
      for (const [id, jwk] of Object.entries(map)) {
        if (profileKeys.has(id)) continue;
        const key = await crypto.subtle.importKey(
          'jwk', jwk, { name: 'AES-GCM', length: 256 }, true, ['encrypt', 'decrypt'],
        );
        profileKeys.set(id, key);
      }
    } catch { safeSessionRemove(SS_PROFILE_KEYS); }
  }
}

/**
 * Derive PEK from passphrase using PBKDF2 (WebCrypto).
 * In production, this would use Argon2id via WASM.
 * PBKDF2 is used as a WebCrypto-native fallback.
 */
export async function derivePEK(passphrase: string, salt: string): Promise<CryptoKey> {
  const encoder = new TextEncoder();
  const saltBytes = base64ToBytes(salt);

  // Import passphrase as key material
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    encoder.encode(passphrase),
    'PBKDF2',
    false,
    ['deriveBits', 'deriveKey'],
  );

  // Derive AES-256-GCM key. Marked extractable=true so setPEK() can stash the
  // JWK in sessionStorage and rehydrate across page refreshes. This is a
  // deliberate security/UX trade-off for Stage 2.
  const key = await crypto.subtle.deriveKey(
    {
      name: 'PBKDF2',
      salt: saltBytes as BufferSource,
      iterations: 600000, // OWASP recommended minimum for PBKDF2-SHA256
      hash: 'SHA-256',
    },
    keyMaterial,
    { name: 'AES-GCM', length: 256 },
    true,
    ['encrypt', 'decrypt'],
  );

  return key;
}

/**
 * Derive auth hash from passphrase — sent to server for authentication.
 * Uses SHA-256(email) as a deterministic salt so that login and registration
 * always produce the same auth_hash without needing a server round-trip.
 */
export async function deriveAuthHash(passphrase: string, email: string): Promise<string> {
  const encoder = new TextEncoder();

  // Deterministic salt from email — same on register and login
  const emailHash = await crypto.subtle.digest('SHA-256', encoder.encode(email.toLowerCase().trim()));
  const saltBytes = new Uint8Array(emailHash);

  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    encoder.encode(passphrase),
    'PBKDF2',
    false,
    ['deriveBits'],
  );

  const bits = await crypto.subtle.deriveBits(
    {
      name: 'PBKDF2',
      salt: saltBytes as BufferSource,
      iterations: 600000,
      hash: 'SHA-256',
    },
    keyMaterial,
    256,
  );

  return bytesToBase64(new Uint8Array(bits));
}

/**
 * Generate a random AES-256-GCM key for profile encryption.
 */
export async function generateProfileKey(): Promise<CryptoKey> {
  return crypto.subtle.generateKey(
    { name: 'AES-GCM', length: 256 },
    true, // extractable — needed for wrapping/sharing
    ['encrypt', 'decrypt'],
  );
}

/**
 * Generate an X25519 key pair for ECDH key exchange.
 * Falls back to P-256 ECDH since X25519 WebCrypto support varies.
 */
export async function generateIdentityKeyPair(): Promise<CryptoKeyPair> {
  return crypto.subtle.generateKey(
    { name: 'ECDH', namedCurve: 'P-256' },
    true,
    ['deriveKey', 'deriveBits'],
  );
}

/**
 * Export a public key to base64 for storage on the server.
 */
export async function exportPublicKey(key: CryptoKey): Promise<string> {
  const raw = await crypto.subtle.exportKey('raw', key);
  return bytesToBase64(new Uint8Array(raw));
}

/**
 * Export a private key, encrypted with PEK.
 */
export async function exportPrivateKeyEncrypted(
  privateKey: CryptoKey,
  encryptionKey: CryptoKey,
): Promise<string> {
  const exported = await crypto.subtle.exportKey('pkcs8', privateKey);
  return encrypt(new Uint8Array(exported), encryptionKey);
}

/**
 * Import a private key that was encrypted with PEK.
 */
export async function importPrivateKeyEncrypted(
  encryptedKey: string,
  decryptionKey: CryptoKey,
): Promise<CryptoKey> {
  const decrypted = await decryptToBytes(encryptedKey, decryptionKey);
  return crypto.subtle.importKey(
    'pkcs8',
    decrypted as BufferSource,
    { name: 'ECDH', namedCurve: 'P-256' },
    true,
    ['deriveKey', 'deriveBits'],
  );
}

// ── Utility functions ──────────────────────────────────────────────

export function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

export function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

export function generateRandomBytes(length: number): Uint8Array {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytes;
}

