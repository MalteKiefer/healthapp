import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';

/// A [CookieJar] that serializes state into an encrypted vault entry.
///
/// Working copy is an in-memory [DefaultCookieJar]; flush writes to the
/// vault. On lock() the in-memory jar is emptied and load returns
/// nothing until reload() is called after the vault is unlocked again.
class EncryptedCookieJar implements CookieJar {
  EncryptedCookieJar({required this.vault});

  final EncryptedVault vault;
  final DefaultCookieJar _mem = DefaultCookieJar();
  bool _loaded = false;
  bool _jarLocked = false;

  static const String _key = 'cookies.v1';

  final Set<Uri> _touched = {};

  /// Populate in-memory jar from the vault. No-op if already loaded.
  Future<void> reload() async {
    if (!vault.isUnlocked) return;
    final raw = await vault.getString(_key);
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in map.entries) {
        final url = Uri.parse(entry.key);
        final list = entry.value as List<dynamic>;
        final cookies = list
            .map((c) => _decodeCookie(c as Map<String, dynamic>))
            .toList();
        await _mem.saveFromResponse(url, cookies);
        _touched.add(url);
      }
    }
    _loaded = true;
    _jarLocked = false;
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded && !_jarLocked) await reload();
  }

  @override
  Future<List<Cookie>> loadForRequest(Uri uri) async {
    if (_jarLocked) return const [];
    await _ensureLoaded();
    return _mem.loadForRequest(uri);
  }

  @override
  Future<void> saveFromResponse(Uri uri, List<Cookie> cookies) async {
    if (_jarLocked) return;
    await _ensureLoaded();
    _touched.add(uri);
    await _mem.saveFromResponse(uri, cookies);
  }

  @override
  Future<void> delete(Uri uri, [bool withDomainSharedCookie = false]) async {
    if (_jarLocked) return;
    await _mem.delete(uri, withDomainSharedCookie);
  }

  @override
  Future<void> deleteAll() async {
    _touched.clear();
    await _mem.deleteAll();
  }

  @override
  bool get ignoreExpires => _mem.ignoreExpires;

  void lock() {
    _jarLocked = true;
    _mem.deleteAll();
    _touched.clear();
    _loaded = false;
  }

  /// Flush in-memory jar state into the vault.
  Future<void> flush() async {
    if (!vault.isUnlocked) return;
    final map = <String, dynamic>{};
    for (final uri in _touched) {
      final cs = await _mem.loadForRequest(uri);
      map[uri.toString()] = cs.map(_encodeCookie).toList();
    }
    await vault.putString(_key, jsonEncode(map));
    await vault.flush();
  }

  Map<String, dynamic> _encodeCookie(Cookie c) => {
        'name': c.name,
        'value': c.value,
        'domain': c.domain,
        'path': c.path,
        'expires': c.expires?.toIso8601String(),
        'httpOnly': c.httpOnly,
        'secure': c.secure,
      };

  Cookie _decodeCookie(Map<String, dynamic> m) {
    final c = Cookie(m['name'] as String, m['value'] as String);
    c.domain = m['domain'] as String?;
    c.path = m['path'] as String?;
    final e = m['expires'] as String?;
    if (e != null) c.expires = DateTime.parse(e);
    c.httpOnly = m['httpOnly'] as bool? ?? false;
    c.secure = m['secure'] as bool? ?? false;
    return c;
  }
}
