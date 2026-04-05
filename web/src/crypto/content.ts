/**
 * Profile content encryption — AES-256-GCM with additional-authenticated-data
 * bound to (profileId, entityType, rowId) so ciphertext can't be swapped
 * between rows or profiles on the server.
 *
 * Wire format: same as `encrypt()` in ./encrypt.ts — base64(iv ‖ ciphertext).
 * The tag is included in ciphertext by WebCrypto. The AAD is NOT stored with
 * the ciphertext; it's reconstructed from structural columns on decrypt.
 */

import { bytesToBase64, base64ToBytes } from './keys';

const IV_LENGTH = 12;

export function makeAAD(profileId: string, entityType: string, rowId: string): Uint8Array {
  // Deterministic byte form: "healthvault:v1:<profileId>:<entity>:<rowId>".
  // Version prefix lets us rotate the binding rule later without breaking old rows.
  const s = `healthvault:v1:${profileId}:${entityType}:${rowId}`;
  return new TextEncoder().encode(s);
}

/**
 * Encrypt a JSON-serialisable object as profile content. AAD binds the
 * ciphertext to its row identity.
 */
export async function encryptProfileContent(
  content: unknown,
  profileKey: CryptoKey,
  aad: Uint8Array,
): Promise<string> {
  const plaintext = new TextEncoder().encode(JSON.stringify(content ?? {}));
  const iv = crypto.getRandomValues(new Uint8Array(IV_LENGTH));
  const ciphertext = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv, additionalData: aad as BufferSource, tagLength: 128 },
    profileKey,
    plaintext as BufferSource,
  );
  const combined = new Uint8Array(IV_LENGTH + ciphertext.byteLength);
  combined.set(iv);
  combined.set(new Uint8Array(ciphertext), IV_LENGTH);
  return bytesToBase64(combined);
}

/**
 * Decrypt profile content blob back to the JSON object it was built from.
 * Throws if the AAD does not match the row identity (tamper / row-swap).
 */
export async function decryptProfileContent<T = Record<string, unknown>>(
  blobBase64: string,
  profileKey: CryptoKey,
  aad: Uint8Array,
): Promise<T> {
  const combined = base64ToBytes(blobBase64);
  if (combined.length < IV_LENGTH + 16) {
    throw new Error('content_enc too short');
  }
  const iv = combined.slice(0, IV_LENGTH);
  const ciphertext = combined.slice(IV_LENGTH);
  const plaintext = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv, additionalData: aad as BufferSource, tagLength: 128 },
    profileKey,
    ciphertext as BufferSource,
  );
  return JSON.parse(new TextDecoder().decode(plaintext)) as T;
}
