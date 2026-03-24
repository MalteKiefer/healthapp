/**
 * Profile Key Sharing via ECDH
 *
 * When sharing a profile with another user:
 * 1. Fetch their public key
 * 2. Perform ECDH to derive a shared secret
 * 3. Derive a wrapping key from the shared secret via HKDF
 * 4. Wrap the Profile Key with the wrapping key
 * 5. Send the wrapped key to the server as a key grant
 *
 * The server never sees the Profile Key in plaintext.
 */

import { base64ToBytes, bytesToBase64 } from './keys';
import { wrapKey, unwrapKey } from './encrypt';

/**
 * Import another user's public key from base64.
 */
export async function importPublicKey(publicKeyBase64: string): Promise<CryptoKey> {
  const raw = base64ToBytes(publicKeyBase64);
  return crypto.subtle.importKey(
    'raw',
    raw,
    { name: 'ECDH', namedCurve: 'P-256' },
    true,
    [],
  );
}

/**
 * Derive a wrapping key from ECDH shared secret.
 * Uses HKDF with a context string to prevent key reuse.
 */
async function deriveWrappingKey(
  privateKey: CryptoKey,
  publicKey: CryptoKey,
  context: string,
): Promise<CryptoKey> {
  // Step 1: ECDH → shared secret bits
  const sharedBits = await crypto.subtle.deriveBits(
    { name: 'ECDH', public: publicKey },
    privateKey,
    256,
  );

  // Step 2: Import shared bits as HKDF key material
  const hkdfKey = await crypto.subtle.importKey(
    'raw',
    sharedBits,
    'HKDF',
    false,
    ['deriveKey'],
  );

  // Step 3: HKDF → AES-256-GCM wrapping key
  const encoder = new TextEncoder();
  return crypto.subtle.deriveKey(
    {
      name: 'HKDF',
      hash: 'SHA-256',
      salt: new Uint8Array(0),
      info: encoder.encode(`HealthVault ProfileKeyGrant v1 ${context}`),
    },
    hkdfKey,
    { name: 'AES-GCM', length: 256 },
    false,
    ['wrapKey', 'unwrapKey'],
  );
}

/**
 * Create a profile key grant for another user.
 *
 * @param profileKey - The Profile Key to share
 * @param myPrivateKey - My ECDH private key
 * @param theirPublicKey - Recipient's ECDH public key (base64)
 * @param context - Unique context string (e.g. profileId + ownerId + granteeId)
 * @returns Base64 encoded wrapped key
 */
export async function createKeyGrant(
  profileKey: CryptoKey,
  myPrivateKey: CryptoKey,
  theirPublicKeyBase64: string,
  context: string,
): Promise<string> {
  const theirPublicKey = await importPublicKey(theirPublicKeyBase64);
  const wrappingKey = await deriveWrappingKey(myPrivateKey, theirPublicKey, context);
  return wrapKey(profileKey, wrappingKey);
}

/**
 * Receive and unwrap a profile key grant from another user.
 *
 * @param wrappedKeyBase64 - The wrapped Profile Key from the server
 * @param myPrivateKey - My ECDH private key
 * @param theirPublicKeyBase64 - Granter's ECDH public key (base64)
 * @param context - Same context string used during creation
 * @returns The unwrapped Profile Key
 */
export async function receiveKeyGrant(
  wrappedKeyBase64: string,
  myPrivateKey: CryptoKey,
  theirPublicKeyBase64: string,
  context: string,
): Promise<CryptoKey> {
  const theirPublicKey = await importPublicKey(theirPublicKeyBase64);
  const unwrappingKey = await deriveWrappingKey(myPrivateKey, theirPublicKey, context);
  return unwrapKey(wrappedKeyBase64, unwrappingKey);
}

/**
 * Generate recovery codes — random 128-bit values encoded as base32.
 * Returns 10 codes, each 26 characters.
 */
export function generateRecoveryCodes(count: number = 10): string[] {
  const codes: string[] = [];
  const charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  for (let i = 0; i < count; i++) {
    const bytes = new Uint8Array(16); // 128 bits
    crypto.getRandomValues(bytes);

    let code = '';
    for (let j = 0; j < bytes.length; j++) {
      code += charset[bytes[j] % 32];
    }
    // Format as XXXX-XXXX-XXXX-XXXX for readability
    code = code.match(/.{1,4}/g)!.join('-');
    codes.push(code);
  }

  return codes;
}
