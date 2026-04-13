// Stub - E2E encryption removed
export async function encrypt(_data: string, _key: CryptoKey): Promise<string> { return _data; }
export async function encryptString(_data: string, _key: CryptoKey): Promise<string> { return _data; }
export async function decrypt(_data: string, _key: CryptoKey): Promise<string> { return _data; }
export async function decryptToBytes(_data: string, _key: CryptoKey): Promise<Uint8Array> { return new Uint8Array(); }
export async function encryptFile(file: File, _key: CryptoKey): Promise<Blob> { return file; }
export async function wrapKey(_key: CryptoKey, _wrapKey: CryptoKey): Promise<string> { return ''; }
export async function unwrapKey(_wrapped: string, _unwrapKey: CryptoKey): Promise<CryptoKey> { return {} as CryptoKey; }
