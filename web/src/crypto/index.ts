/**
 * HealthVault Crypto Module — Public API
 *
 * All client-side cryptographic operations are exposed through this module.
 * Uses WebCrypto API exclusively — no third-party crypto libraries.
 */

export {
  // Key management
  setPEK,
  getPEK,
  setProfileKey,
  getProfileKey,
  clearAllKeys,
  derivePEK,
  deriveAuthHash,
  generateProfileKey,
  generateIdentityKeyPair,
  exportPublicKey,
  exportPrivateKeyEncrypted,
  importPrivateKeyEncrypted,
  // Utilities
  bytesToBase64,
  base64ToBytes,
  generateRandomBytes,
} from './keys';

export {
  encrypt,
  encryptString,
  decrypt,
  decryptToBytes,
  encryptFile,
  wrapKey,
  unwrapKey,
} from './encrypt';

export {
  importPublicKey,
  createKeyGrant,
  receiveKeyGrant,
  generateRecoveryCodes,
} from './sharing';
