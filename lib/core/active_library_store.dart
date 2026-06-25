import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists the admin's last-active library across app restarts so a
/// multi-library owner doesn't have to re-pick a library every session.
///
/// This is intentionally tiny and dependency-free: a single string keyed in
/// SharedPreferences. `admin_home` is the single source of truth for the
/// in-memory active library; this just remembers it between launches.
class ActiveLibraryStore {
  ActiveLibraryStore._();

  static const String _key = 'admin_active_library_id';

  /// Lets any screen (e.g. the notification center) ask the admin shell to
  /// switch its active library. `admin_home` listens to this and performs the
  /// actual switch + jumps to the dashboard. Value is the requested library id;
  /// the listener resets it to null after consuming.
  static final ValueNotifier<String?> switchRequest = ValueNotifier<String?>(null);

  /// Persist + broadcast a request to make [libraryId] the active library.
  static void requestSwitch(String libraryId) {
    save(libraryId);
    switchRequest.value = libraryId;
  }

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

  /// Resolve the library a screen should act on, in priority order:
  /// 1. the explicitly-passed id (route argument / widget param),
  /// 2. the persisted active library,
  /// 3. the owner's first library (last resort).
  ///
  /// Replaces the old per-screen `eq('owner_id', uid).maybeSingle()` fallback,
  /// which **threw** for owners with 2+ libraries and otherwise picked an
  /// arbitrary library. This keeps the fallback aligned with whatever library
  /// the admin is actively managing.
  static Future<String?> resolve(String? passedId) async {
    if (passedId != null && passedId.isNotEmpty && passedId != 'null' && passedId != 'all') {
      return passedId;
    }
    final persisted = await load();
    if (persisted != null) return persisted;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return null;
      final res = await Supabase.instance.client
          .from('libraries')
          .select('id')
          .eq('owner_id', user.id)
          .order('created_at')
          .limit(1)
          .maybeSingle();
      return res?['id']?.toString();
    } catch (_) {
      return null;
    }
  }
}
