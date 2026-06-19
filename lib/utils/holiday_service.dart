import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'time_utils.dart';

/// A single library closure / holiday.
///
/// Canonical table is `scheduled_closures` with a DATE range
/// (`start_date` .. `end_date`). A single-day holiday simply has
/// `start_date == end_date`. This is the ONLY closure table the app should
/// touch — the legacy `library_closures` table is dead and must not be used.
class Holiday {
  final String id;
  final String libraryId;
  final DateTime startDate; // date-only (local wall date)
  final DateTime endDate; // date-only, inclusive
  final String reason;
  final bool notifyMembers;

  Holiday({
    required this.id,
    required this.libraryId,
    required this.startDate,
    required this.endDate,
    required this.reason,
    this.notifyMembers = true,
  });

  bool get isRange => !_sameDay(startDate, endDate);

  /// True if [day] falls within [startDate]..[endDate] inclusive (date-only).
  bool covers(DateTime day) {
    final d = _dateOnly(day);
    return !d.isBefore(_dateOnly(startDate)) && !d.isAfter(_dateOnly(endDate));
  }

  /// Number of calendar days this holiday spans (inclusive).
  int get dayCount => _dateOnly(endDate).difference(_dateOnly(startDate)).inDays + 1;

  factory Holiday.fromRow(Map<String, dynamic> row) {
    // Be tolerant of historical column drift (closure_date / date) while always
    // preferring the canonical start_date/end_date.
    final rawStart = row['start_date'] ?? row['closure_date'] ?? row['date'];
    final rawEnd = row['end_date'] ?? rawStart;
    final start = _parseDate(rawStart);
    final end = _parseDate(rawEnd) ?? start;
    return Holiday(
      id: row['id'].toString(),
      libraryId: (row['library_id'] ?? '').toString(),
      startDate: start ?? DateTime.now(),
      endDate: end ?? start ?? DateTime.now(),
      reason: (row['reason'] ?? 'Holiday').toString(),
      notifyMembers: row['notify_members'] ?? true,
    );
  }
}

class HolidayService {
  HolidayService._();
  static final HolidayService instance = HolidayService._();
  final _supabase = Supabase.instance.client;

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// All closures for a library, newest first by start date.
  Future<List<Holiday>> fetchForLibrary(String libraryId) async {
    final res = await _supabase
        .from('scheduled_closures')
        .select()
        .eq('library_id', libraryId);
    final list = List<Map<String, dynamic>>.from(res).map(Holiday.fromRow).toList();
    list.sort((a, b) => b.startDate.compareTo(a.startDate));
    return list;
  }

  /// The holiday covering [day] for [libraryId], or null. Range-aware.
  Future<Holiday?> holidayOn(String libraryId, DateTime day) async {
    final d = _fmt(day);
    try {
      final res = await _supabase
          .from('scheduled_closures')
          .select()
          .eq('library_id', libraryId)
          .lte('start_date', d)
          .gte('end_date', d)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(res);
      if (list.isEmpty) return null;
      return Holiday.fromRow(list.first);
    } catch (_) {
      // Tolerate older single-column rows: fall back to a full scan + covers().
      try {
        final all = await fetchForLibrary(libraryId);
        for (final h in all) {
          if (h.covers(day)) return h;
        }
      } catch (_) {}
      return null;
    }
  }

  /// Convenience: today's holiday for a library (null if open).
  Future<Holiday?> todaysHoliday(String libraryId) =>
      holidayOn(libraryId, istNow());

  /// Create a closure. [start]..[end] inclusive; pass the same date for a
  /// single-day holiday. Returns the created [Holiday]. Notifies members when
  /// [notifyMembers] is true. Throws on failure (caller shows honest error).
  Future<Holiday> addHoliday({
    required String libraryId,
    required DateTime start,
    required DateTime end,
    required String reason,
    bool notifyMembers = true,
  }) async {
    final s = _dateOnly(start);
    var e = _dateOnly(end);
    if (e.isBefore(s)) e = s;

    final inserted = await _supabase
        .from('scheduled_closures')
        .insert({
          'library_id': libraryId,
          'start_date': _fmt(s),
          'end_date': _fmt(e),
          'reason': reason.trim().isEmpty ? 'Holiday' : reason.trim(),
          'notify_members': notifyMembers,
        })
        .select()
        .single();

    final holiday = Holiday.fromRow(inserted);

    if (notifyMembers) {
      await notifyMembersOfHoliday(holiday);
    }
    return holiday;
  }

  /// Remove a closure. If [holiday] is given, the closure still covers today or
  /// the future, and it had member-notification on, members are told the
  /// library has reopened. Past closures are deleted silently (no reopen spam).
  Future<void> removeHoliday(String id, {Holiday? holiday}) async {
    await _supabase.from('scheduled_closures').delete().eq('id', id);
    if (holiday == null || !holiday.notifyMembers) return;
    final today = _dateOnly(istNow());
    final endDay = _dateOnly(holiday.endDate);
    if (endDay.isBefore(today)) return; // a past closure — nothing to reopen
    await notifyMembersOfReopen(holiday);
  }

  /// Tell members the library is open again after an upcoming/active closure was
  /// removed. Best-effort (mirrors notifyMembersOfHoliday).
  Future<int> notifyMembersOfReopen(Holiday holiday) async {
    try {
      final memberRows = await _supabase
          .from('memberships')
          .select('member_id')
          .eq('library_id', holiday.libraryId);
      final memberIds = <String>{};
      for (final r in List<Map<String, dynamic>>.from(memberRows)) {
        final id = r['member_id']?.toString();
        if (id != null && id.isNotEmpty) memberIds.add(id);
      }
      if (memberIds.isEmpty) return 0;

      final whenLabel = holiday.isRange
          ? '${_human(holiday.startDate)} – ${_human(holiday.endDate)}'
          : _human(holiday.startDate);
      final body = 'The library will now be OPEN as usual — the planned closure '
          '($whenLabel) has been cancelled.';

      final rows = memberIds
          .map((mid) => {
                'user_id': mid,
                'title': 'Library reopened',
                'body': body,
                'data': {
                  'type': 'reopen',
                  'start_date': _fmt(holiday.startDate),
                  'end_date': _fmt(holiday.endDate),
                },
              })
          .toList();

      await _supabase.from('notifications').insert(rows);
      return memberIds.length;
    } catch (e) {
      debugPrint('notifyMembersOfReopen failed: $e');
      return 0;
    }
  }

  /// How many members currently have an OPEN session (checked in, not yet
  /// checked out) at this library. These are the sessions a "close today"
  /// would end — surfaced in the close-library confirmation.
  Future<int> openSessionsNow(String libraryId) async {
    try {
      final res = await _supabase
          .from('attendance')
          .select('id')
          .eq('library_id', libraryId)
          .isFilter('check_out_time', null);
      return List<Map<String, dynamic>>.from(res).length;
    } catch (e) {
      debugPrint('openSessionsNow failed: $e');
      return 0;
    }
  }

  /// Count of members with a live membership (active/trial/hold) at this
  /// library — shown for context in the close-library confirmation.
  Future<int> activeMembersCount(String libraryId) async {
    try {
      final res = await _supabase
          .from('memberships')
          .select('id')
          .eq('library_id', libraryId)
          .inFilter('status', ['active', 'trial', 'hold']);
      return List<Map<String, dynamic>>.from(res).length;
    } catch (e) {
      debugPrint('activeMembersCount failed: $e');
      return 0;
    }
  }

  /// Auto-checks-out every currently-open session at this library (used when the
  /// admin closes the library for today). Sets check_out_time = now, computes
  /// duration, and flags the session as 'closed'. Returns how many sessions were
  /// ended. Best-effort per row so one failure doesn't abort the rest.
  Future<int> closeOpenSessionsNow(String libraryId) async {
    int closed = 0;
    try {
      final res = await _supabase
          .from('attendance')
          .select('id, check_in_time')
          .eq('library_id', libraryId)
          .isFilter('check_out_time', null);
      final now = DateTime.now().toUtc();
      for (final row in List<Map<String, dynamic>>.from(res)) {
        try {
          final ci = DateTime.tryParse(row['check_in_time']?.toString() ?? '');
          int dur = 0;
          if (ci != null) {
            dur = now.difference(ci.toUtc()).inMinutes;
            if (dur < 0) dur = 0;
          }
          await _supabase.from('attendance').update({
            'check_out_time': now.toIso8601String(),
            'duration_minutes': dur,
            'session_type': 'closed',
          }).eq('id', row['id']);
          closed++;
        } catch (e) {
          debugPrint('closeOpenSessionsNow row failed: $e');
        }
      }
    } catch (e) {
      debugPrint('closeOpenSessionsNow failed: $e');
    }
    return closed;
  }

  /// Sends an in-app notification to every member of the library. Best-effort:
  /// logs and returns on failure rather than throwing (the holiday already
  /// exists; a notification failure must not roll it back).
  Future<int> notifyMembersOfHoliday(Holiday holiday) async {
    try {
      final memberRows = await _supabase
          .from('memberships')
          .select('member_id')
          .eq('library_id', holiday.libraryId);

      final memberIds = <String>{};
      for (final r in List<Map<String, dynamic>>.from(memberRows)) {
        final id = r['member_id']?.toString();
        if (id != null && id.isNotEmpty) memberIds.add(id);
      }
      if (memberIds.isEmpty) return 0;

      final title = holiday.isRange ? 'Library closed (holiday)' : 'Library closed today';
      final whenLabel = holiday.isRange
          ? '${_human(holiday.startDate)} – ${_human(holiday.endDate)}'
          : _human(holiday.startDate);
      final body = 'The library will be closed on $whenLabel. Reason: ${holiday.reason}. '
          'Your study streak is protected for these days.';

      final rows = memberIds
          .map((mid) => {
                'user_id': mid,
                'title': title,
                'body': body,
                'data': {
                  'type': 'holiday',
                  'start_date': _fmt(holiday.startDate),
                  'end_date': _fmt(holiday.endDate),
                },
              })
          .toList();

      await _supabase.from('notifications').insert(rows);
      return memberIds.length;
    } catch (e) {
      debugPrint('notifyMembersOfHoliday failed: $e');
      return 0;
    }
  }

  static String _human(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().split('T').first;
  return DateTime.tryParse(s);
}
