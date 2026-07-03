import 'package:flutter_test/flutter_test.dart';
import 'package:silence/screens/shift_management.dart';

/// BUG 1 — "Update Opening Hours?" popup always fires.
///
/// EXPLORATION tests (bugfix workflow): they encode the EXPECTED (post-fix)
/// behavior. They FAILED on the unfixed code (the reminder fired
/// unconditionally); after the BUG 1 fix they PASS.
///
/// Root cause (design.md → BUG 1): `_handleSave()` in
/// lib/screens/shift_management.dart used to ALWAYS run
/// `await _showOpeningHoursReminder();` on the success path — there was no guard
/// for "did a timing change?" and no comparison against the library's
/// configured opening hours.
///
/// The fix extracts the reminder decision into the pure, top-level
/// `shouldShowOpeningHoursReminder(changedTimings, openingHoursRaw)` (plus the
/// `parseOpeningHours` / `timingWithinHours` helpers) which `_handleSave` now
/// delegates to. These tests exercise that REAL production logic directly.
///
/// isBugCondition(save) = (NOT anyTimingChanged) OR allChangedTimingsWithin(hours)
/// Expected: no popup when the bug condition holds; popup only when a changed
/// timing falls OUTSIDE the parsed opening hours (Req 2.1, 2.2, 2.7).
void main() {
  // The library's configured opening hours for cases B and C.
  const openingHours = '6:00 AM – 11:00 PM';

  group('BUG 1 · reminder must be suppressed for unchanged / inside-hours saves', () {
    test('Case A — unchanged save (no timing change) must NOT show the reminder (Req 2.2)', () {
      // Admin edited only a shift price and saved; no timing changed, so there
      // are no changed timings to feed the decision.
      final reminderShown = shouldShowOpeningHoursReminder(
        const <ShiftTiming>[],
        openingHours,
      );
      expect(reminderShown, isFalse,
          reason: 'BUG: reminder appears on an unchanged save (no timing changed)');
    });

    test('Case B — inside-hours change must NOT show the reminder (Req 2.1)', () {
      // Opening hours "6:00 AM – 11:00 PM"; shift changed to 7:00 AM–1:00 PM
      // (fully inside the configured hours).
      final reminderShown = shouldShowOpeningHoursReminder(
        const [ShiftTiming(7 * 60, 13 * 60)], // 07:00 – 13:00
        openingHours,
      );
      expect(reminderShown, isFalse,
          reason: 'BUG: reminder appears for a timing change that stays inside opening hours');
    });
  });

  group('BUG 1 · reminder is correct for out-of-hours changes (correct case)', () {
    test('Case C — outside-hours change SHOULD show the reminder (Req 2.7)', () {
      // Opening hours "6:00 AM – 11:00 PM"; shift changed to 5:00 AM–1:00 PM
      // (starts before open) → the ONE case where the popup is correct.
      final reminderShown = shouldShowOpeningHoursReminder(
        const [ShiftTiming(5 * 60, 13 * 60)], // 05:00 – 13:00
        openingHours,
      );
      expect(reminderShown, isTrue,
          reason: 'Outside-hours change must keep prompting (guards against over-suppression)');
    });
  });
}
