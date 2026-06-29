import 'package:flutter_test/flutter_test.dart';
import 'package:silence/utils/time_utils.dart';

/// Pure-logic tests for the canonical IST clock. The admin dashboard "today"
/// window (Wave 8.3) and all day-boundary math depend on these being correct,
/// so they're locked in here. No network / no DB.
void main() {
  group('toIST', () {
    test('adds 5h30m to a UTC instant', () {
      final utc = DateTime.utc(2026, 7, 7, 0, 0, 0); // 00:00 UTC
      final ist = toIST(utc);
      expect(ist.year, 2026);
      expect(ist.month, 7);
      expect(ist.day, 7);
      expect(ist.hour, 5);
      expect(ist.minute, 30);
    });

    test('normalizes a non-UTC input to UTC first', () {
      final utc = DateTime.utc(2026, 1, 1, 18, 30);
      expect(toIST(utc).day, 2); // 18:30Z → 00:00 IST next day
      expect(toIST(utc).hour, 0);
    });
  });

  group('istWallClockToUtc (DB query bounds)', () {
    test('IST midnight maps to 18:30Z of the previous day', () {
      final istMidnight = DateTime(2026, 6, 19, 0, 0, 0);
      final utc = istWallClockToUtc(istMidnight);
      expect(utc.isUtc, isTrue);
      expect(utc.year, 2026);
      expect(utc.month, 6);
      expect(utc.day, 18);
      expect(utc.hour, 18);
      expect(utc.minute, 30);
    });

    test('round-trips with toIST (wall-clock preserved)', () {
      final wall = DateTime(2026, 3, 15, 9, 45, 0);
      final back = toIST(istWallClockToUtc(wall));
      expect(back.year, wall.year);
      expect(back.month, wall.month);
      expect(back.day, wall.day);
      expect(back.hour, wall.hour);
      expect(back.minute, wall.minute);
    });
  });

  group('parseDBTimeToUtc', () {
    test('treats a trailing Z as UTC', () {
      final dt = parseDBTimeToUtc('2026-07-07T10:00:00Z');
      expect(dt.isUtc, isTrue);
      expect(dt.hour, 10);
    });

    test('treats an offset-less timestamp as UTC wall-clock', () {
      final dt = parseDBTimeToUtc('2026-07-07T10:00:00');
      expect(dt.isUtc, isTrue);
      expect(dt.hour, 10);
    });
  });

  group('istDateKeyFromDb', () {
    test('a 23:00Z timestamp rolls into the next IST day', () {
      // 2026-07-07 23:00Z → 2026-07-08 04:30 IST.
      expect(istDateKeyFromDb('2026-07-07T23:00:00Z'), '2026-07-08');
    });

    test('an early-UTC timestamp stays on the same IST day', () {
      // 2026-07-07 06:00Z → 2026-07-07 11:30 IST.
      expect(istDateKeyFromDb('2026-07-07T06:00:00Z'), '2026-07-07');
    });
  });

  group('formatShiftTimeString', () {
    test('formats HH:mm to a 12-hour label', () {
      expect(formatShiftTimeString('07:00'), '07:00 AM');
      expect(formatShiftTimeString('13:30'), '01:30 PM');
    });

    test('returns N/A for null/empty', () {
      expect(formatShiftTimeString(null), 'N/A');
      expect(formatShiftTimeString(''), 'N/A');
    });
  });
}
