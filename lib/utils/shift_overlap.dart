import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Time-overlap helpers for the per-shift seat model.
///
/// A physical seat exists once per shift (`seats` has one row per
/// (seat_label × shift)). If a member occupies a seat in shift X, that same
/// chair is physically unavailable during any shift whose hours overlap X —
/// even though the overlapping shift has its own, nominally "vacant", seats row.
/// These helpers let seat pickers exclude such physically-taken seats so an
/// admin can't double-book one chair across two overlapping shifts.
///
/// Times are stored as "HH:MM" or "HH:MM:SS" strings. A range whose end is at or
/// before its start is treated as crossing midnight (e.g. 22:00 → 06:00).

int? _toMinutes(dynamic timeStr) {
  if (timeStr == null) return null;
  final s = timeStr.toString().trim();
  if (s.isEmpty) return null;
  final parts = s.split(':');
  final h = int.tryParse(parts[0]);
  if (h == null) return null;
  final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  return h * 60 + m;
}

/// The minute-intervals a shift occupies within a 24h clock (1 interval, or 2
/// if it wraps past midnight).
List<List<int>> _dayIntervals(int start, int end) {
  if (end > start) {
    return [
      [start, end]
    ];
  }
  if (end < start) {
    return [
      [start, 1440],
      [0, end]
    ];
  }
  // end == start: ambiguous (zero-length or full-day). Treat as full 24h so we
  // err on the safe side and never hand out a possibly-taken seat.
  return [
    [0, 1440]
  ];
}

/// Do two [start,end) shift ranges overlap in time? Handles overnight ranges.
/// If any time can't be parsed, returns `true` (fail safe → treat as a clash so
/// we don't assign a seat that might already be taken).
bool shiftRangesOverlap(
    dynamic startA, dynamic endA, dynamic startB, dynamic endB) {
  final sA = _toMinutes(startA);
  final eA = _toMinutes(endA);
  final sB = _toMinutes(startB);
  final eB = _toMinutes(endB);
  if (sA == null || eA == null || sB == null || eB == null) return true;

  for (final ia in _dayIntervals(sA, eA)) {
    for (final ib in _dayIntervals(sB, eB)) {
      if (ia[0] < ib[1] && ib[0] < ia[1]) return true;
    }
  }
  return false;
}

/// Ids of shifts in [allShifts] whose hours overlap the shift [targetShiftId],
/// excluding the target itself. [allShifts] items must carry 'id',
/// 'start_time', 'end_time'.
Set<String> overlappingShiftIds(
    String targetShiftId, List<Map<String, dynamic>> allShifts) {
  Map<String, dynamic>? target;
  for (final s in allShifts) {
    if (s['id'].toString() == targetShiftId) {
      target = s;
      break;
    }
  }
  if (target == null) return <String>{};

  final result = <String>{};
  for (final s in allShifts) {
    final id = s['id'].toString();
    if (id == targetShiftId) continue;
    if (shiftRangesOverlap(
        target['start_time'], target['end_time'], s['start_time'], s['end_time'])) {
      result.add(id);
    }
  }
  return result;
}

/// Of [candidateLabels] (seat labels nominally vacant in [targetShiftId]), the
/// subset that are physically taken in an OVERLAPPING shift and therefore must
/// NOT be offered. A seat is "taken" if its row in an overlapping shift is
/// occupied/hold, OR a live membership in an overlapping shift claims it.
///
/// Best-effort: on any query error this returns an empty set (don't block
/// assignment over a transient failure — there is no DB-level seat lock anyway).
Future<Set<String>> blockedSeatLabels(
  SupabaseClient client, {
  required String libraryId,
  required String targetShiftId,
  required List<Map<String, dynamic>> allShifts,
  required List<String> candidateLabels,
}) async {
  if (candidateLabels.isEmpty) return <String>{};
  final overlapIds = overlappingShiftIds(targetShiftId, allShifts);
  if (overlapIds.isEmpty) return <String>{};

  final blocked = <String>{};
  try {
    final seatRows = await client
        .from('seats')
        .select('id, seat_label, status')
        .eq('library_id', libraryId)
        .inFilter('shift_id', overlapIds.toList())
        .inFilter('seat_label', candidateLabels);

    final Map<String, String> seatIdToLabel = {};
    for (final r in List<Map<String, dynamic>>.from(seatRows)) {
      final label = r['seat_label'].toString();
      seatIdToLabel[r['id'].toString()] = label;
      final st = (r['status'] ?? 'vacant').toString();
      if (st == 'occupied' || st == 'hold') blocked.add(label);
    }

    // Also catch seats whose row status is stale but a live membership claims it.
    final mems = await client
        .from('memberships')
        .select('seat_id')
        .eq('library_id', libraryId)
        .inFilter('shift_id', overlapIds.toList())
        .inFilter('status', ['active', 'trial', 'hold'])
        .not('seat_id', 'is', null);
    for (final m in List<Map<String, dynamic>>.from(mems)) {
      final sid = m['seat_id']?.toString();
      if (sid != null && seatIdToLabel.containsKey(sid)) {
        blocked.add(seatIdToLabel[sid]!);
      }
    }
  } catch (e) {
    debugPrint('blockedSeatLabels overlap check failed: $e');
  }
  return blocked;
}
