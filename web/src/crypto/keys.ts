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

// Key store — in-memory only, never persisted to disk
let pek: CryptoKey | null = null;
const profileKeys: Map<string, CryptoKey> = new Map();

export function setPEK(key: CryptoKey) {
  pek = key;
}

export function getPEK(): CryptoKey | null {
  return pek;
}

export function setProfileKey(profileId: string, key: CryptoKey) {
  profileKeys.set(profileId, key);
}

export function getProfileKey(profileId: string): CryptoKey | null {
  return profileKeys.get(profileId) || null;
}

export function clearAllKeys() {
  pek = null;
  profileKeys.clear();
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

  // Derive AES-256-GCM key
  const key = await crypto.subtle.deriveKey(
    {
      name: 'PBKDF2',
      salt: saltBytes as BufferSource,
      iterations: 600000, // OWASP recommended minimum for PBKDF2-SHA256
      hash: 'SHA-256',
    },
    keyMaterial,
    { name: 'AES-GCM', length: 256 },
    false, // non-extractable
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

