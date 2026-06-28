import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown when a user tries to file a second OPEN report for the same target.
/// Backed by the `uq_abuse_open` partial unique index (PostgREST code 23505).
class DuplicateReportException implements Exception {
  const DuplicateReportException();
}

/// UGC moderation: reporting objectionable content, blocking abusive users, and
/// hiding reviews. All DB writes are direct `.from(...)` calls protected by RLS
/// (see migrations/2026-06-28_ugc_moderation.sql). Methods throw on failure so
/// callers can show an honest error via `AppSnackbar` / `friendlyError` — we
/// never report a success that did not happen.
class ModerationService {
  ModerationService._();

  static SupabaseClient get _db => Supabase.instance.client;

  /// Allowed report reasons (must match the DB CHECK domain).
  static const List<String> reasons = [
    'spam',
    'harassment',
    'inappropriate',
    'impersonation',
    'copyright',
    'other',
  ];

  /// Allowed report target types (must match the DB CHECK domain).
  static const List<String> targetTypes = ['review', 'query', 'user', 'library'];

  /// File an abuse report. Throws [DuplicateReportException] if an open report
  /// for the same (reporter, target) already exists; rethrows other errors.
  static Future<void> submitReport({
    required String targetType,
    required String targetId,
    String? libraryId,
    required String reason,
    String? description,
  }) async {
    assert(targetTypes.contains(targetType), 'invalid target_type: $targetType');
    assert(reasons.contains(reason), 'invalid reason: $reason');
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Not signed in');
    try {
      await _db.from('abuse_reports').insert({
        'reporter_id': uid,
        'target_type': targetType,
        'target_id': targetId,
        'library_id': ?libraryId,
        'reason': reason,
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw const DuplicateReportException();
      rethrow;
    }
  }

  /// Block another user. Idempotent — re-blocking an already-blocked user is a
  /// no-op (the unique constraint is swallowed).
  static Future<void> blockUser(String blockedUserId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Not signed in');
    try {
      await _db.from('user_blocks').insert({
        'blocker_id': uid,
        'blocked_id': blockedUserId,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // already blocked
      rethrow;
    }
  }

  /// Remove a block.
  static Future<void> unblockUser(String blockedUserId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Not signed in');
    await _db
        .from('user_blocks')
        .delete()
        .eq('blocker_id', uid)
        .eq('blocked_id', blockedUserId);
  }

  /// The set of user-ids the current user has blocked (for client-side
  /// filtering of UGC). Returns an empty set on failure (fail-open for reads).
  static Future<Set<String>> loadMyBlockedIds() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return <String>{};
    try {
      final rows = await _db.from('user_blocks').select('blocked_id').eq('blocker_id', uid);
      return (rows as List)
          .map((r) => (r['blocked_id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// The current user's blocks with the blocked user's display info, for the
  /// "Blocked users" management screen.
  static Future<List<Map<String, dynamic>>> myBlocks() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _db
        .from('user_blocks')
        .select('id, blocked_id, created_at, blocked:blocked_id (full_name, nickname, photo_url)')
        .eq('blocker_id', uid)
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Hide a review (reversible moderation). Allowed for the library owner (via
  /// admin_manage_reviews) and the app-owner.
  static Future<void> hideReview(String reviewId, {String? reason}) async {
    final uid = _db.auth.currentUser?.id;
    await _db.from('reviews').update({
      'hidden': true,
      'hidden_by': uid,
      if (reason != null && reason.trim().isNotEmpty) 'hidden_reason': reason.trim(),
    }).eq('id', reviewId);
  }

  /// Un-hide a previously hidden review.
  static Future<void> unhideReview(String reviewId) async {
    await _db.from('reviews').update({
      'hidden': false,
      'hidden_by': null,
      'hidden_reason': null,
    }).eq('id', reviewId);
  }

  // ── Pure helpers (no network) — easy to unit/property test ────────────────

  /// Returns the reviews whose author (`member_id`) is NOT in [blockedIds].
  /// Pure function of its inputs (Property 4).
  static List<Map<String, dynamic>> filterBlocked(
    List<Map<String, dynamic>> reviews,
    Set<String> blockedIds,
  ) {
    if (blockedIds.isEmpty) return reviews;
    return reviews
        .where((r) => !blockedIds.contains((r['member_id'] ?? '').toString()))
        .toList();
  }

  /// Returns the reviews that are not hidden (treats null/absent as visible).
  /// Pure function of its inputs (Property 5).
  static List<Map<String, dynamic>> filterHidden(List<Map<String, dynamic>> reviews) {
    return reviews.where((r) => r['hidden'] != true).toList();
  }
}
