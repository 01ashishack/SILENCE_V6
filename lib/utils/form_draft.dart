import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/cache_service.dart';

/// Lightweight per-user, per-library draft store for in-progress forms
/// (member join / renewal). Backed by [CacheService] (SharedPreferences), so a
/// half-filled form survives an app restart. Nothing here ever throws into the
/// caller — a draft is a convenience, never a source of failure.
///
/// A draft is local-only and is NOT a submission. It must be cleared on a
/// successful submit so the member is never shown stale, already-sent data.
class FormDraft {
  /// The storage key, scoped to the form type, the library, and the signed-in
  /// user so two members on the same device never see each other's drafts.
  final String key;

  FormDraft(String scope, String libraryId)
      : key = 'draft_${scope}_${libraryId}_'
            '${Supabase.instance.client.auth.currentUser?.id ?? 'anon'}';

  Future<void> save(Map<String, dynamic> data) {
    return CacheService.instance.writeCache(key, {
      ...data,
      'savedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>?> load() async {
    final raw = await CacheService.instance.readCache(key);
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  Future<void> clear() => CacheService.instance.clearCache(key);

  /// Human-friendly "saved 5 min ago" label for the restore prompt.
  static String savedAgo(dynamic iso) {
    if (iso is! String) return 'earlier';
    final t = DateTime.tryParse(iso);
    if (t == null) return 'earlier';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} hr ago';
    return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
  }
}
