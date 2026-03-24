import { describe, it, expect } from 'vitest';
import { bytesToBase64, base64ToBytes, generateRandomBytes } from './keys';

describe('Crypto utilities', () => {
  it('base64 roundtrip', () => {
    const original = new Uint8Array([1, 2, 3, 255, 128, 0]);
    const encoded = bytesToBase64(original);
    const decoded = base64ToBytes(encoded);
    expect(Array.from(decoded)).toEqual(Array.from(original));
  });

  it('generateRandomBytes returns correct length', () => {
    const bytes16 = generateRandomBytes(16);
    expect(bytes16.length).toBe(16);

    const bytes32 = generateRandomBytes(32);
    expect(bytes32.length).toBe(32);
  });

  it('generateRandomBytes produces unique values', () => {
    const a = generateRandomBytes(32);
    const b = generateRandomBytes(32);
    expect(bytesToBase64(a)).not.toBe(bytesToBase64(b));
  });

  it('base64ToBytes handles empty string edge case', () => {
    const empty = base64ToBytes(btoa(''));
    expect(empty.length).toBe(0);
  });
});
