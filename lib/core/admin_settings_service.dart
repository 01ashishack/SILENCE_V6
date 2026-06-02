import 'package:supabase_flutter/supabase_flutter.dart';

class AdminSettingsService {
  AdminSettingsService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<String?> firstOwnedLibraryId() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final res = await _supabase
        .from('libraries')
        .select('id')
        .eq('owner_id', user.id)
        .limit(1)
        .maybeSingle();
    return res?['id']?.toString();
  }

  static Future<Map<String, dynamic>> load({
    required String scope,
    String? libraryId,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return {};

    final query = _supabase
        .from('settings')
        .select('value')
        .eq('admin_id', user.id)
        .eq('scope', scope);

    final res = libraryId == null
        ? await query.isFilter('library_id', null).maybeSingle()
        : await query.eq('library_id', libraryId).maybeSingle();

    final value = res?['value'];
    return value is Map<String, dynamic> ? value : {};
  }

  static Future<void> save({
    required String scope,
    required Map<String, dynamic> value,
    String? libraryId,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    await _supabase.from('settings').upsert({
      'admin_id': user.id,
      'library_id': libraryId,
      'scope': scope,
      'value': value,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'admin_id,library_id,scope');
  }
}
