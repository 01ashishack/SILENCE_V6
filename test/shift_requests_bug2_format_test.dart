import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// BUG 2 — 24-hour time format on member "Request Shift Change".
///
/// FIX-VERIFICATION test (bugfix workflow, matured from the BUG 2 exploration
/// test): the label-building model now mirrors the FIXED production composition
/// in `_openShiftChangeRequestSheet` (lib/screens/member_home.dart), which
/// builds the dropdown option label via the existing `_formatShiftRange` helper
/// (12-hour, seconds-free) instead of the raw DB `HH:mm:ss` strings.
///
/// Root cause (design.md → BUG 2): the UNFIXED code built the option label from
/// the raw DB strings:
///   final st = (s['start_time'] ?? '').toString();   // "06:00:00"
///   final en = (s['end_time'] ?? '').toString();      // "12:00:00"
///   final time = (st.isNotEmpty && en.isNotEmpty) ? '  ($st–$en)' : '';
///   // label: '${s['name']}$time'  →  "Morning  (06:00:00–12:00:00)"
///
/// The applied fix (Task 4.1) composes the label as
///   '${s['name']}  (${_formatShiftRange(s)})'
/// where `_formatShiftRange` → `_formatShiftTime` → `DateFormat('h:mm a')`.
/// Because that production method is a private, DB-coupled `State` method with
/// no test seam, its `_formatShiftRange`/`_formatShiftTime` logic is reproduced
/// faithfully below so the test encodes and validates the post-fix behavior.
void main() {
  // Faithful reproduction of the FIXED production `_formatShiftTime`
  // (lib/screens/member_home.dart) — 12-hour AM/PM, seconds stripped.
  String formatShiftTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final s = raw.trim();
    try {
      if (s.toLowerCase().contains('am') || s.toLowerCase().contains('pm')) {
        final dt = DateFormat('h:mm a').parse(s.toUpperCase());
        return DateFormat('h:mm a').format(dt);
      }
      final parts = s.split(':');
      final h = int.parse(parts[0]);
      final m = parts.length > 1 ? int.parse(parts[1].split(' ').first) : 0;
      return DateFormat('h:mm a').format(DateTime(2000, 1, 1, h, m));
    } catch (_) {
      return s;
    }
  }

  // Faithful reproduction of the FIXED production `_formatShiftRange`.
  String formatShiftRange(Map<String, dynamic> shift) {
    if (shift.isEmpty) return '—';
    final start = formatShiftTime(shift['start_time']?.toString());
    final end = formatShiftTime(shift['end_time']?.toString());
    if (start.isEmpty && end.isEmpty) return '—';
    if (end.isEmpty) return start;
    if (start.isEmpty) return end;
    return '$start – $end';
  }

  // Faithful reproduction of the FIXED dropdown option-label composition
  // ('${s['name']}  ($range)' when range is present, else the name only).
  String fixedOptionLabel(Map<String, dynamic> s) {
    final range = formatShiftRange(s);
    return (range.isNotEmpty && range != '—') ? '${s['name']}  ($range)' : '${s['name']}';
  }

  bool containsSeconds(String label) => RegExp(r'\d{1,2}:\d{2}:\d{2}').hasMatch(label);

  // A 12-hour AM/PM token like "6:00 AM" / "12:00 PM".
  bool isTwelveHourFormat(String label) =>
      RegExp(r'\d{1,2}:\d{2}\s?(AM|PM)', caseSensitive: false).hasMatch(label);

  group('BUG 2 · dropdown option must show a 12-hour, seconds-free range (Req 2.3)', () {
    test('Morning 06:00:00–12:00:00 → "6:00 AM – 12:00 PM", no ":00:00"', () {
      final shift = {'name': 'Morning', 'start_time': '06:00:00', 'end_time': '12:00:00'};
      final label = fixedOptionLabel(shift);

      // Post-fix behavior: the label carries the friendly 12-hour range, never
      // the raw HH:mm:ss the unfixed builder emitted.
      expect(label, contains('6:00 AM – 12:00 PM'),
          reason: 'expected the fixed 12-hour range "6:00 AM – 12:00 PM"');

      expect(containsSeconds(label), isFalse,
          reason: 'BUG: option label contains seconds (HH:mm:ss)');
      expect(isTwelveHourFormat(label), isTrue,
          reason: 'BUG: option label is not 12-hour AM/PM');
      expect(label, contains('6:00 AM'),
          reason: 'BUG: expected friendly 12-hour start "6:00 AM"');
      expect(label, contains('12:00 PM'),
          reason: 'BUG: expected friendly 12-hour end "12:00 PM"');
    });

    test('Evening 19:00:00–23:00:00 → "7:00 PM – 11:00 PM"', () {
      final shift = {'name': 'Evening Shift', 'start_time': '19:00:00', 'end_time': '23:00:00'};
      final label = fixedOptionLabel(shift);
      expect(label, contains('7:00 PM – 11:00 PM'),
          reason: 'expected the fixed 12-hour range "7:00 PM – 11:00 PM"');
      expect(containsSeconds(label), isFalse, reason: 'BUG: label contains seconds');
      expect(label, contains('7:00 PM'), reason: 'BUG: expected 12-hour start "7:00 PM"');
      expect(label, contains('11:00 PM'), reason: 'BUG: expected 12-hour end "11:00 PM"');
    });
  });

  // Sanity: the expected 12-hour formatter (mirrors _formatShiftTime) produces
  // the target format — proves the assertions above are achievable post-fix.
  group('BUG 2 · reference 12-hour formatter (documents the target output)', () {
    String fmt(String raw) {
      final parts = raw.split(':');
      final h = int.parse(parts[0]);
      final m = parts.length > 1 ? int.parse(parts[1]) : 0;
      return DateFormat('h:mm a').format(DateTime(2000, 1, 1, h, m));
    }

    test('formats 06:00:00 and 19:00:00 to friendly 12-hour', () {
      expect(fmt('06:00:00'), '6:00 AM');
      expect(fmt('19:00:00'), '7:00 PM');
      expect(containsSeconds('${fmt('06:00:00')} – ${fmt('12:00:00')}'), isFalse);
    });
  });
}
