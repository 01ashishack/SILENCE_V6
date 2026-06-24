import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static final CacheService instance = CacheService._init();
  CacheService._init();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get prefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Write dynamic JSON encodable data into local cache under the specified key.
  Future<void> writeCache(String key, dynamic data) async {
    try {
      final p = await prefs;
      final String jsonStr = jsonEncode(data);
      await p.setString(key, jsonStr);
    } catch (_) {
      // Catch exceptions silently to prevent UI disruption
    }
  }

  /// Read JSON cached data under the specified key. Returns null if missing or on error.
  Future<dynamic> readCache(String key) async {
    try {
      final p = await prefs;
      final String? jsonStr = p.getString(key);
      if (jsonStr == null) return null;
      return jsonDecode(jsonStr);
    } catch (_) {
      return null;
    }
  }

  /// Clear a cached key.
  Future<void> clearCache(String key) async {
    try {
      final p = await prefs;
      await p.remove(key);
    } catch (_) {}
  }

  /// Write with a `_storedAt` envelope so readers can enforce freshness (M5).
  Future<void> writeCacheTimed(String key, dynamic data) async {
    await writeCache(key, {
      '_storedAt': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    });
  }

  /// Read a timed cache entry. Returns null if missing, malformed, or older
  /// than [ttl] — so genuinely stale data (e.g. an offline-for-days library
  /// list) is not shown indefinitely. Pair with [writeCacheTimed].
  Future<dynamic> readCacheFresh(String key, Duration ttl) async {
    final raw = await readCache(key);
    if (raw is! Map || raw['_storedAt'] == null) return null;
    final ts = DateTime.tryParse(raw['_storedAt'].toString());
    if (ts == null) return null;
    if (DateTime.now().toUtc().difference(ts) > ttl) return null;
    return raw['data'];
  }
}
