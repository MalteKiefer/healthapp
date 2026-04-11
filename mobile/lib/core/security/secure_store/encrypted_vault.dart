import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';

/// File-backed AES-256-GCM vault.
///
/// Wire format (version 0x01):
///
/// ```
/// 'HVLT' | 0x01 | salt(16) | wrappedDekLenBE(u16) | wrappedDek |
/// wrappedDekByBioLenBE(u16) | wrappedDekByBio |
/// entriesJsonLenBE(u32) | entriesJson
/// ```
///
/// Each entries-JSON value is base64 of `nonce(12)||ct||tag(16)` encrypted
/// with the DEK.
class EncryptedVault {
  EncryptedVault({required this.file, required this.kek, required this.dek});

  final File file;
  final KekService kek;
  final DekService dek;

  static const List<int> _magic = [0x48, 0x56, 0x4c, 0x54];
  static const int _version = 0x01;
  static const int _saltLen = 16;
  static const int _nonceLen = 12;
  static const int _tagLen = 16;

  final AesGcm _entryAes = AesGcm.with256bits();

  Uint8List? _salt;
  Uint8List? _wrappedDekByPin;
  Uint8List? _wrappedDekByBio;
  Uint8List? _dekInRam;
  Map<String, String> _entries = {};

  bool get isUnlocked => _dekInRam != null;

  Uint8List? get wrappedDekByBio =>
      _wrappedDekByBio == null ? null : Uint8List.fromList(_wrappedDekByBio!);

  Future<void> create({required String pin}) async {
    _salt = kek.generateSalt();
    final kekBytes = await kek.deriveKek(pin, _salt!);
    _dekInRam = dek.generateDek();
    _wrappedDekByPin = await dek.wrap(_dekInRam!, kekBytes);
    _wrappedDekByBio = null;
    _entries = {};
    await _writeAtomic();
  }

  Future<void> unlock({required String pin}) async {
    await _readFromDisk();
    final kekBytes = await kek.deriveKek(pin, _salt!);
    _dekInRam = await dek.unwrap(_wrappedDekByPin!, kekBytes);
  }

  Future<void> unlockWithBioKey(Uint8List bioKey) async {
    await _readFromDisk();
    if (_wrappedDekByBio == null) {
      throw const InvalidKeyException();
    }
    _dekInRam = await dek.unwrap(_wrappedDekByBio!, bioKey);
  }

  void lock() {
    _dekInRam = null;
  }

  Future<void> changePin({
    required String oldPin,
    required String newPin,
  }) async {
    if (_salt == null) await _readFromDisk();
    final oldKek = await kek.deriveKek(oldPin, _salt!);
    final dekBytes = await dek.unwrap(_wrappedDekByPin!, oldKek);
    _salt = kek.generateSalt();
    final newKek = await kek.deriveKek(newPin, _salt!);
    _wrappedDekByPin = await dek.wrap(dekBytes, newKek);
    _dekInRam = dekBytes;
    _wrappedDekByBio = null;
  }

  Future<void> setWrappedDekByBio(Uint8List bioKey) async {
    _requireUnlocked();
    _wrappedDekByBio = await dek.wrap(_dekInRam!, bioKey);
  }

  void clearWrappedDekByBio() {
    _wrappedDekByBio = null;
  }

  Future<void> putString(String key, String value) =>
      putBytes(key, Uint8List.fromList(utf8.encode(value)));

  Future<String?> getString(String key) async {
    final b = await getBytes(key);
    return b == null ? null : utf8.decode(b);
  }

  Future<void> putBytes(String key, Uint8List value) async {
    _requireUnlocked();
    final encoded = await _encryptEntry(value, _dekInRam!);
    _entries[key] = base64.encode(encoded);
  }

  Future<Uint8List?> getBytes(String key) async {
    _requireUnlocked();
    final b64 = _entries[key];
    if (b64 == null) return null;
    return _decryptEntry(Uint8List.fromList(base64.decode(b64)), _dekInRam!);
  }

  /// AES-256-GCM encrypts [plaintext] under [key]. Wire format:
  /// `nonce(12) || ct || tag(16)`.
  Future<Uint8List> _encryptEntry(Uint8List plaintext, Uint8List key) async {
    final nonce = _entryAes.newNonce();
    final secret = SecretKey(key);
    final box = await _entryAes.encrypt(
      plaintext,
      secretKey: secret,
      nonce: nonce,
    );
    return Uint8List.fromList([
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Future<Uint8List> _decryptEntry(Uint8List wire, Uint8List key) async {
    if (wire.length < _nonceLen + _tagLen) {
      throw const InvalidKeyException();
    }
    final nonce = wire.sublist(0, _nonceLen);
    final tagStart = wire.length - _tagLen;
    final cipher = wire.sublist(_nonceLen, tagStart);
    final tag = wire.sublist(tagStart);
    try {
      final secret = SecretKey(key);
      final box = SecretBox(cipher, nonce: nonce, mac: Mac(tag));
      final plain = await _entryAes.decrypt(box, secretKey: secret);
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const InvalidKeyException();
    }
  }

  Future<void> delete(String key) async {
    _entries.remove(key);
  }

  Future<void> flush() => _writeAtomic();

  Future<void> wipe() async {
    _dekInRam = null;
    _wrappedDekByPin = null;
    _wrappedDekByBio = null;
    _salt = null;
    _entries = {};
    if (file.existsSync()) await file.delete();
    final tmp = File('${file.path}.tmp');
    if (tmp.existsSync()) await tmp.delete();
  }

  void _requireUnlocked() {
    if (_dekInRam == null) throw StateError('Vault is locked');
  }

  Future<void> _writeAtomic() async {
    final bb = BytesBuilder();
    bb.add(_magic);
    bb.addByte(_version);
    bb.add(_salt!);
    _writeLenPrefixed(bb, _wrappedDekByPin!);
    _writeLenPrefixed(bb, _wrappedDekByBio ?? Uint8List(0));
    final entriesJson = utf8.encode(jsonEncode(_entries));
    final len = ByteData(4)..setUint32(0, entriesJson.length);
    bb.add(len.buffer.asUint8List());
    bb.add(entriesJson);

    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bb.toBytes(), flush: true);
    await tmp.rename(file.path);
  }

  void _writeLenPrefixed(BytesBuilder bb, Uint8List data) {
    final len = ByteData(2)..setUint16(0, data.length);
    bb.add(len.buffer.asUint8List());
    bb.add(data);
  }

  Future<void> _readFromDisk() async {
    if (!file.existsSync()) {
      throw StateError('Vault file not found at ${file.path}');
    }
    final bytes = await file.readAsBytes();
    var offset = 0;

    for (var i = 0; i < _magic.length; i++) {
      if (bytes[offset + i] != _magic[i]) {
        throw StateError('Bad vault magic');
      }
    }
    offset += _magic.length;

    final version = bytes[offset++];
    if (version != _version) {
      throw StateError('Unsupported vault version $version');
    }

    _salt = Uint8List.fromList(bytes.sublist(offset, offset + _saltLen));
    offset += _saltLen;

    final pinLen = _readU16(bytes, offset);
    offset += 2;
    _wrappedDekByPin =
        Uint8List.fromList(bytes.sublist(offset, offset + pinLen));
    offset += pinLen;

    final bioLen = _readU16(bytes, offset);
    offset += 2;
    _wrappedDekByBio = bioLen == 0
        ? null
        : Uint8List.fromList(bytes.sublist(offset, offset + bioLen));
    offset += bioLen;

    final entriesLen = _readU32(bytes, offset);
    offset += 4;
    final entriesJson =
        utf8.decode(bytes.sublist(offset, offset + entriesLen));
    _entries = Map<String, String>.from(
      jsonDecode(entriesJson) as Map<String, dynamic>,
    );
  }

  int _readU16(Uint8List b, int off) =>
      ByteData.sublistView(b, off, off + 2).getUint16(0);
  int _readU32(Uint8List b, int off) =>
      ByteData.sublistView(b, off, off + 4).getUint32(0);
}
