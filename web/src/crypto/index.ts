/**
 * Crypto utilities — E2E content encryption has been fully removed.
 * Only auth-related crypto (PBKDF2 auth hash, recovery code generation) remains.
 */

export async function deriveAuthHash(passphrase: string, email: string): Promise<string> {
  const enc = new TextEncoder();
  // Deterministic salt from email — must match registration
  const emailHash = await crypto.subtle.digest('SHA-256', enc.encode(email.toLowerCase().trim()));
  const saltBytes = new Uint8Array(emailHash);

  const keyMaterial = await crypto.subtle.importKey(
    'raw', enc.encode(passphrase), 'PBKDF2', false, ['deriveBits'],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt: saltBytes as BufferSource, iterations: 600000, hash: 'SHA-256' },
    keyMaterial, 256,
  );
  return Array.from(new Uint8Array(bits)).map(b => b.toString(16).padStart(2, '0')).join('');
}

export function generateRecoveryCodes(count: number): string[] {
  const codes: string[] = [];
  for (let i = 0; i < count; i++) {
    const bytes = new Uint8Array(5);
    crypto.getRandomValues(bytes);
    codes.push(Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('').toUpperCase());
  }
  return codes;
}

// No-op stub kept for useIdleTimeout and Layout logout.
export function clearAllKeys() {}
