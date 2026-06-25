import 'package:supabase_flutter/supabase_flutter.dart';

/// Single source of truth for the 7-day account-deletion request, shared by the
/// member profile tab and the privacy/security screen (previously duplicated,
/// which risked the two flows diverging).
///
/// NOTE: this only RECORDS the scheduled deletion + recovery window on the user
/// row (immediate freeze handled by routing to /account-frozen). The actual
/// purge needs the server tier and is out of scope here.
class AccountDeletionService {
  AccountDeletionService._();

  static const Duration window = Duration(days: 7);

  /// Schedules deletion for the current user; returns the scheduled time.
  /// Throws on failure so callers can surface an honest error.
  static Future<DateTime> schedule() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in.');
    }
    final deletionTime = DateTime.now().add(window);
    await supabase.from('users').update({
      'scheduled_for_deletion': true,
      'deletion_scheduled_at': deletionTime.toIso8601String(),
      'deletion_recovery_status': 'none',
    }).eq('id', user.id);
    return deletionTime;
  }

  /// Cancels a pending deletion request for the current user.
  static Future<void> cancel() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await supabase.from('users').update({
      'scheduled_for_deletion': false,
      'deletion_scheduled_at': null,
    }).eq('id', user.id);
  }
}
