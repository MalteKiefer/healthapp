/**
 * AES-256-GCM encryption and decryption.
 *
 * Format: base64(iv || ciphertext || tag)
 * - IV: 12 bytes (96 bits), random per encryption
 * - Tag: 128 bits (included by WebCrypto in ciphertext output)
 */

import { bytesToBase64, base64ToBytes } from './keys';

const IV_LENGTH = 12;

/**
 * Encrypt data with AES-256-GCM.
 * Returns base64(iv + ciphertext).
 */
export async function encrypt(data: Uint8Array, key: CryptoKey): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(IV_LENGTH));

  const ciphertext = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv, tagLength: 128 },
    key,
    data as BufferSource,
  );

  // Concatenate IV + ciphertext
  const combined = new Uint8Array(IV_LENGTH + ciphertext.byteLength);
  combined.set(iv);
  combined.set(new Uint8Array(ciphertext), IV_LENGTH);

  return bytesToBase64(combined);
}

/**
 * Encrypt a string with AES-256-GCM.
 */
export async function encryptString(plaintext: string, key: CryptoKey): Promise<string> {
  const encoder = new TextEncoder();
  return encrypt(encoder.encode(plaintext), key);
}

/**
 * Decrypt data from base64(iv + ciphertext).
 * Returns the decrypted string.
 */
export async function decrypt(encryptedBase64: string, key: CryptoKey): Promise<string> {
  const bytes = await decryptToBytes(encryptedBase64, key);
  const decoder = new TextDecoder();
  return decoder.decode(bytes);
}

/**
 * Decrypt data from base64(iv + ciphertext).
 * Returns raw bytes.
 */
export async function decryptToBytes(encryptedBase64: string, key: CryptoKey): Promise<Uint8Array> {
  const combined = base64ToBytes(encryptedBase64);

  if (combined.length < IV_LENGTH + 1) {
    throw new Error('Invalid ciphertext: too short');
  }

  const iv = combined.slice(0, IV_LENGTH);
  const ciphertext = combined.slice(IV_LENGTH);

  const plaintext = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv, tagLength: 128 },
    key,
    ciphertext,
  );

  return new Uint8Array(plaintext);
}

/**
 * Encrypt a file (Blob/File) with AES-256-GCM.
 * Returns encrypted data as a Blob.
 */
export async function encryptFile(file: File, key: CryptoKey): Promise<Blob> {
  const data = new Uint8Array(await file.arrayBuffer());
  const encrypted = await encrypt(data, key);
  return new Blob([encrypted], { type: 'application/octet-stream' });
}

/**
 * Wrap (encrypt) one AES key with another.
 * Used for profile key grants — wrap the Profile Key with a derived shared secret.
 */
export async function wrapKey(keyToWrap: CryptoKey, wrappingKey: CryptoKey): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(IV_LENGTH));

  const wrapped = await crypto.subtle.wrapKey(
    'raw',
    keyToWrap,
    wrappingKey,
    { name: 'AES-GCM', iv, tagLength: 128 },
  );

  const combined = new Uint8Array(IV_LENGTH + wrapped.byteLength);
  combined.set(iv);
  combined.set(new Uint8Array(wrapped), IV_LENGTH);

  return bytesToBase64(combined);
}

/**
 * Unwrap (decrypt) an AES key that was wrapped with another.
 */
export async function unwrapKey(wrappedBase64: string, unwrappingKey: CryptoKey): Promise<CryptoKey> {
  const combined = base64ToBytes(wrappedBase64);
  const iv = combined.slice(0, IV_LENGTH);
  const wrapped = combined.slice(IV_LENGTH);

  return crypto.subtle.unwrapKey(
    'raw',
    wrapped,
    unwrappingKey,
    { name: 'AES-GCM', iv, tagLength: 128 },
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  );
}
