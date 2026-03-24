import { describe, it, expect } from 'vitest';
import { generateRecoveryCodes } from './sharing';

describe('Recovery codes', () => {
  it('generates 10 codes by default', () => {
    const codes = generateRecoveryCodes();
    expect(codes).toHaveLength(10);
  });

  it('generates specified number of codes', () => {
    const codes = generateRecoveryCodes(5);
    expect(codes).toHaveLength(5);
  });

  it('codes are formatted with dashes', () => {
    const codes = generateRecoveryCodes(1);
    expect(codes[0]).toMatch(/^[A-Z2-7]{4}-[A-Z2-7]{4}-[A-Z2-7]{4}-[A-Z2-7]{4}$/);
  });

  it('generates unique codes', () => {
    const codes = generateRecoveryCodes(10);
    const unique = new Set(codes);
    expect(unique.size).toBe(10);
  });
});
