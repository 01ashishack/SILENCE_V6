import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_settings_service.dart';

/// Copies a library's configuration from a SOURCE library into a TARGET library.
/// Used by:
///   • the "Copy settings from another library" screen, and
///   • the Add-Library flow (a new library inherits the first library's settings
///     so the owner only fills Basic Details + Layout).
///
/// COPY (one-time), not LINK — copied rows are independent. Layout (floors/
/// sections/seats) is intentionally NOT copied (each library has its own).
class LibrarySettingsCopier {
  LibrarySettingsCopier._();

  static final SupabaseClient _sb = Supabase.instance.client;

  /// Copies shifts & plans, add-ons, amenities and business rules from
  /// [sourceId] into [targetId]. Best-effort: a failure in one section is
  /// logged and skipped, never thrown into the caller.
  static Future<void> copyAll({
    required String sourceId,
    required String targetId,
  }) async {
    await _copyShifts(sourceId, targetId);
    await _copyAddons(sourceId, targetId);
    await _copyAmenities(sourceId, targetId);
    await _copyRules(sourceId, targetId);
  }

  static Future<void> _copyShifts(String sourceId, String targetId) async {
    try {
      final rows = await _sb
          .from('shifts')
          .select(
              'name, start_time, end_time, price_monthly, price_3month, price_6month, trial_days, shift_type, hours_per_day')
          .eq('library_id', sourceId)
          .eq('is_archived', false);
      final list = List<Map<String, dynamic>>.from(rows);
      if (list.isEmpty) return;
      await _sb.from('shifts').insert(
            list.map((s) => {...s, 'library_id': targetId}).toList(),
          );
    } catch (e) {
      debugPrint('copyShifts failed: $e');
    }
  }

  static Future<void> _copyAddons(String sourceId, String targetId) async {
    try {
      final rows = await _sb
          .from('add_ons')
          .select('name, price, price_type, refundable_deposit, max_available, active')
          .eq('library_id', sourceId);
      final list = List<Map<String, dynamic>>.from(rows);
      if (list.isEmpty) return;
      await _sb.from('add_ons').insert(
            list.map((a) => {...a, 'library_id': targetId}).toList(),
          );
    } catch (e) {
      debugPrint('copyAddons failed: $e');
    }
  }

  static Future<void> _copyAmenities(String sourceId, String targetId) async {
    try {
      final src = await _sb
          .from('libraries')
          .select('amenities')
          .eq('id', sourceId)
          .maybeSingle();
      final amenities = src?['amenities'];
      if (amenities == null) return;
      await _sb.from('libraries').update({'amenities': amenities}).eq('id', targetId);
    } catch (e) {
      debugPrint('copyAmenities failed: $e');
    }
  }

  static Future<void> _copyRules(String sourceId, String targetId) async {
    try {
      final rules = await AdminSettingsService.load(
        scope: 'business_rules',
        libraryId: sourceId,
      );
      if (rules.isNotEmpty) {
        await AdminSettingsService.save(
          scope: 'business_rules',
          libraryId: targetId,
          value: rules,
        );
      }
      // NOTE: business rules live in the `settings` table (scope 'business_rules'),
      // copied above. The old `libraries.rules_metadata` column does not exist in
      // the schema — querying it threw a (swallowed) PostgREST 42703 and copied
      // nothing, so that dead block was removed.
    } catch (e) {
      debugPrint('copyRules failed: $e');
    }
  }
}
