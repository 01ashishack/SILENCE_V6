import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Central writer for the `audit_log` table.
///
/// The committed schema is:
///   audit_log(admin_id, library_id, action, details JSONB,
///             previous_value, new_value, ip_address, created_at)
///
/// The reader UI groups entries by a `category` and shows a `title` /
/// `details` / `performer_name`. To keep ONE canonical table (instead of the
/// old drift where two writers used different flat columns), we store those
/// display fields inside the `details` JSONB. The reader falls back to legacy
/// flat columns for any old rows.
///
/// Best-effort: never throws into the caller — an audit failure must not abort
/// the business action it's recording.
class AuditLogger {
  AuditLogger._();
  static final AuditLogger instance = AuditLogger._();
  final _supabase = Supabase.instance.client;

  static const categoryMembers = 'members';
  static const categoryPayments = 'payments';
  static const categoryQr = 'qr';
  static const categorySettings = 'settings';

  Future<void> log({
    required String action,
    required String category,
    required String title,
    required String details,
    String? libraryId,
    String? previousValue,
    String? newValue,
  }) async {
    final admin = _supabase.auth.currentUser;
    if (admin == null) return;
    try {
      await _supabase.from('audit_log').insert({
        'admin_id': admin.id,
        'library_id': ?libraryId,
        'action': action,
        'details': {
          'category': category,
          'title': title,
          'details': details,
          'performer_name': admin.email ?? 'Admin',
        },
        'previous_value': ?previousValue,
        'new_value': ?newValue,
      });
    } catch (e) {
      debugPrint('AuditLogger.log failed: $e');
    }
  }
}
