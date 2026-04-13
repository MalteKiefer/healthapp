/**
 * Crypto stubs - E2E encryption has been removed.
 * These no-op functions exist to prevent import errors from pages
 * that previously used crypto operations.
 */

// Key management stubs
export function setPEK(_key: CryptoKey) {}
export function getPEK(): CryptoKey | null { return null; }
export function setIdentityPrivateKey(_key: CryptoKey) {}
export function getIdentityPrivateKey(): CryptoKey | null { return null; }
export function setProfileKey(_profileId: string, _key: CryptoKey) {}
export function getProfileKey(_profileId: string): CryptoKey | null { return null; }
export function clearAllKeys() {}
export function rehydrateKeysFromSession() {}

// Key derivation stubs - these still need to work for auth
export async function derivePEK(_passphrase: string, _salt: string): Promise<CryptoKey> {
  // Return a dummy key - not actually used for crypto anymore
  return {} as CryptoKey;
}

export async function deriveAuthHash(passphrase: string, email: string): Promise<string> {
  // Simple PBKDF2-based auth hash for login compatibility
  const enc = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey(
    'raw', enc.encode(passphrase), 'PBKDF2', false, ['deriveBits'],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt: enc.encode(email), iterations: 100000, hash: 'SHA-256' },
    keyMaterial, 256,
  );
  return Array.from(new Uint8Array(bits)).map(b => b.toString(16).padStart(2, '0')).join('');
}

export async function generateIdentityKeyPair() {
  return { publicKey: {} as CryptoKey, privateKey: {} as CryptoKey };
}

export async function exportPublicKey(_key: CryptoKey): Promise<string> { return 'none'; }
export async function exportPrivateKeyEncrypted(_key: CryptoKey, _pek: CryptoKey): Promise<string> { return 'none'; }
export async function importPrivateKeyEncrypted(_enc: string, _pek: CryptoKey): Promise<CryptoKey> { return {} as CryptoKey; }
export function bytesToBase64(_bytes: Uint8Array): string { return ''; }
export function base64ToBytes(_b64: string): Uint8Array { return new Uint8Array(); }
export function generateRandomBytes(_n: number): Uint8Array { return crypto.getRandomValues(new Uint8Array(_n)); }
export async function generateProfileKey(): Promise<CryptoKey> { return {} as CryptoKey; }
export async function createKeyGrant(..._args: unknown[]): Promise<string> { return ''; }
export function generateRecoveryCodes(count: number): string[] {
  const codes: string[] = [];
  for (let i = 0; i < count; i++) {
    const bytes = new Uint8Array(5);
    crypto.getRandomValues(bytes);
    codes.push(Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('').toUpperCase());
  }
  return codes;
}

export async function ensureProfileKey(..._args: unknown[]): Promise<void> {}

// Content encryption stubs
export async function encryptProfileContent(..._args: unknown[]): Promise<string> { return ''; }
export async function decryptProfileContent<T>(..._args: unknown[]): Promise<T> { return {} as T; }
export function makeAAD(..._args: string[]): Uint8Array { return new Uint8Array(); }

// Sharing stubs
export async function importPublicKey(_b64: string): Promise<CryptoKey> { return {} as CryptoKey; }
export async function receiveKeyGrant(..._args: unknown[]): Promise<CryptoKey> { return {} as CryptoKey; }
