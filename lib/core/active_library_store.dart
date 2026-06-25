import 'package:shared_preferences/shared_preferences.dart';

/// Persists the admin's last-active library across app restarts so a
/// multi-library owner doesn't have to re-pick a library every session.
///
/// This is intentionally tiny and dependency-free: a single string keyed in
/// SharedPreferences. `admin_home` is the single source of truth for the
/// in-memory active library; this just remembers it between launches.
class ActiveLibraryStore {
  ActiveLibraryStore._();

  static const String _key = 'admin_active_library_id';

  /// Returns the persisted active-library id, or null if none saved yet.
  static Future<String?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_key);
      if (id == null || id.isEmpty || id == 'null' || id == 'all') return null;
      return id;
    } catch (_) {
      return null;
    }
  }

  /// Persists the active-library id (best-effort; never throws into callers).
  static Future<void> save(String? libraryId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (libraryId == null || libraryId.isEmpty || libraryId == 'null' || libraryId == 'all') {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, libraryId);
      }
    } catch (_) {
      // Persisting the active library is a convenience, not critical.
    }
  }
}
