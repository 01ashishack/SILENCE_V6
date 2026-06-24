import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Single place that writes rows into the `notifications` table so every
/// notification carries a consistent payload:
///   { type, route?, ...extra }
/// `type`  → drives the icon + colour in the notification center.
/// `route` → optional named route the center deep-links to on tap.
///
/// All sends are best-effort and never throw into the caller (a notification
/// failing must never break the action that triggered it).
class NotificationService {
  static final SupabaseClient _sb = Supabase.instance.client;

  /// Canonical named-route for a notification type. Only returns routes that
  /// actually exist in the app's route table; `query_reply`, `new_query`,
  /// `refund_request`, `new_review` and `announcement` are handled directly in
  /// the notification center (widget push / dialog), so they return null here.
  static String? routeForType(String type) {
    switch (type) {
      // ── member destinations ──
      case 'join_approved':
      case 'join_rejected':
      case 'payment_confirmed':
      case 'payment_rejected':
      case 'payment_received':
      case 'hold':
      case 'hold_approved':
      case 'hold_lifted':
      case 'seat_assigned':
      case 'seat_change_approved':
      case 'seat_change_rejected':
      case 'membership_renewed':
      case 'membership_transferred':
      case 'membership_removed':
      case 'membership_removed_refund':
      case 'membership_exited':
      case 'expiry':
      case 'renewal':
      case 'shift_end':
      case 'auto_checkout':
      case 'checkin_approved':
      case 'checkin_rejected':
      case 'attendance_manual':
      case 'badge':
      case 'leaderboard':
      case 'referral_credited':
      case 'streak_reminder':
      case 'holiday':
      case 'reopen':
      case 'closure':
        return '/member/home';
      // ── admin destinations ──
      case 'join_request':
      case 'new_join_request':
      case 'seat_change_request':
      case 'hold_request':
      case 'checkin_approval_request':
      case 'payment_submitted':
      case 'member_exited':
      case 'check_in':
      case 'check_out':
      case 'expiring_digest':
      case 'daily_summary':
      case 'dues_digest':
        return '/admin/home';
      default:
        return null; // query_reply / new_query / refund_request / new_review / announcement
    }
  }

  /// Send one notification to a single user.
  static Future<void> send({
    required String userId,
    required String title,
    required String body,
    required String type,
    String? route,
    Map<String, dynamic>? extra,
  }) async {
    final r = route ?? routeForType(type);
    try {
      await _sb.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'body': body,
        'data': {
          'type': type,
          'route': ?r,
          if (extra != null) ...extra,
        },
      });
    } catch (e) {
      debugPrint('NotificationService.send failed ($type): $e');
    }
  }

  /// Send the same notification to many users in one insert.
  static Future<void> sendMany({
    required List<String> userIds,
    required String title,
    required String body,
    required String type,
    String? route,
    Map<String, dynamic>? extra,
  }) async {
    if (userIds.isEmpty) return;
    final r = route ?? routeForType(type);
    try {
      final rows = userIds
          .toSet()
          .map((uid) => {
                'user_id': uid,
                'title': title,
                'body': body,
                'data': {
                  'type': type,
                  'route': ?r,
                  if (extra != null) ...extra,
                },
              })
          .toList();
      await _sb.from('notifications').insert(rows);
    } catch (e) {
      debugPrint('NotificationService.sendMany failed ($type): $e');
    }
  }

  /// Convenience: notify the OWNER of a library (looks up `owner_id`).
  static Future<void> notifyLibraryOwner({
    required String libraryId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final lib = await _sb.from('libraries').select('owner_id').eq('id', libraryId).maybeSingle();
      final ownerId = lib?['owner_id']?.toString();
      if (ownerId == null || ownerId.isEmpty) return;
      await send(userId: ownerId, title: title, body: body, type: type, extra: extra);
    } catch (e) {
      debugPrint('NotificationService.notifyLibraryOwner failed ($type): $e');
    }
  }
}
