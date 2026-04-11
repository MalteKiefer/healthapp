import 'dart:async';

/// Minimal TTL-aware in-memory cache for API responses.
///
/// This is opt-in: callers pick keys and a TTL explicitly. Entries expire
/// lazily on read (no background timer), and expired entries are
/// overwritten on the next `put`.
///
/// Intended use from inside a Riverpod provider or the ApiClient wrapper:
///
/// ```dart
/// final cached = TtlMemoryCache.instance.get<List<Foo>>('foos:$profileId');
/// if (cached != null) return cached;
/// final fresh = await api.get<Map<String, dynamic>>('...');
/// final parsed = ...;
/// TtlMemoryCache.instance.put('foos:$profileId', parsed, const Duration(minutes: 5));
/// return parsed;
/// ```
class TtlMemoryCache {
  TtlMemoryCache._();
  static final TtlMemoryCache instance = TtlMemoryCache._();

  final Map<String, _Entry> _store = {};

  /// Returns the cached value if present AND not expired.
  T? get<T>(String key) {
    final e = _store[key];
    if (e == null) return null;
    if (DateTime.now().isAfter(e.expiresAt)) {
      _store.remove(key);
      return null;
    }
    return e.value as T?;
  }

  /// Stores a value with a relative TTL.
  void put<T>(String key, T value, Duration ttl) {
    _store[key] = _Entry(value, DateTime.now().add(ttl));
  }

  /// Invalidate one key.
  void invalidate(String key) => _store.remove(key);

  /// Invalidate every entry whose key starts with [prefix].
  void invalidatePrefix(String prefix) {
    _store.removeWhere((k, _) => k.startsWith(prefix));
  }

  /// Drop everything. Call on logout / vault wipe.
  void clear() => _store.clear();

  int get length => _store.length;
}

class _Entry {
  _Entry(this.value, this.expiresAt);
  final Object? value;
  final DateTime expiresAt;
}
