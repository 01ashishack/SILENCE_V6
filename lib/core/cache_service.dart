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
}
