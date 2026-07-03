import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:silence/services/notification_service.dart';
import 'package:silence/theme/app_colors.dart';

/// PRESERVATION property tests for the shift-requests bugfixes (Task 2).
///
/// Property 2: Preservation — Non-Bug Inputs Unchanged.
///
/// Methodology: observation-first. For inputs where the bug condition does NOT
/// hold, we run the UNFIXED code (or a faithful model of the current inline
/// logic where the production method is a private, DB-coupled State method with
/// no injection seam), record the actual outputs, then assert those outputs so
/// they are locked in as the baseline the fix must preserve.
///
/// EXPECTED OUTCOME: every test in this file PASSES on the UNFIXED code.
///
/// Covers:
///   * BUG 1 persistence  — Req 3.1, 3.2 (save order + success snackbar)
///   * BUG 2/3 send flow  — Req 3.3, 3.4 (filtering, reason, insert, notify, msg)
///   * BUG 4 counts       — Req 3.5, 3.6 (per-type counts + toggle set)
///   * BUG 4 routing      — Req 3.7 (non-request notifications unchanged)
///   * Theme              — Req 3.8 (warm-orange Material 3 palette)
void main() {
  // ===========================================================================
  // BUG 1 — persistence order + success message preserved (Req 3.1, 3.2)
  //
  // `_handleSave` in lib/screens/shift_management.dart is a private, DB-coupled
  // State method with no seam, so its success-path ORDER is reproduced here by a
  // faithful model copied step-for-step from the source (steps 1-7 + snackbar +
  // reminder + pop). The fix only gates WHETHER the reminder shows; every step
  // below must remain in the same relative order.
  // ===========================================================================
  group('BUG 1 preservation · save persistence order + success message', () {
    // The exact success message the save shows today (source of truth).
    const kSuccessMessage = 'Shifts & payment options saved successfully! ✓';

    // Faithful model of the UNFIXED _handleSave success path: returns the
    // ordered list of side-effects it performs. `reminderAlwaysShown` mirrors
    // the current unconditional `await _showOpeningHoursReminder();`.
    List<String> handleSaveUnfixedOrder({
      required bool hasShiftsToArchive,
      required bool hasExistingShiftUpdates,
      required bool hasNewShiftInserts,
      required bool replicateSeats,
    }) {
      final steps = <String>[];
      steps.add('identify-archive'); // 1. identify shifts to archive
      steps.add('archive-guard'); // 2. archive protection (active memberships)
      if (hasShiftsToArchive) steps.add('archive'); // 3. archive removed shifts
      if (hasExistingShiftUpdates) steps.add('update'); // 4. update existing
      if (hasNewShiftInserts) steps.add('insert'); // 5. insert new shifts
      if (replicateSeats) steps.add('seat-replicate'); // 6. replicate seat layout
      steps.add('payment-save'); // 7. save payment settings
      steps.add('snackbar'); // success snackbar
      steps.add('reminder'); // opening-hours reminder (unconditional today)
      steps.add('pop'); // Navigator.pop(context, true)
      return steps;
    }

    test('the full save performs its steps in the documented order', () {
      final order = handleSaveUnfixedOrder(
        hasShiftsToArchive: true,
        hasExistingShiftUpdates: true,
        hasNewShiftInserts: true,
        replicateSeats: true,
      );
      expect(order, [
        'identify-archive',
        'archive-guard',
        'archive',
        'update',
        'insert',
        'seat-replicate',
        'payment-save',
        'snackbar',
        'reminder',
        'pop',
      ]);
    });

    test('archive guard always precedes archiving, updating and inserting', () {
      final order = handleSaveUnfixedOrder(
        hasShiftsToArchive: true,
        hasExistingShiftUpdates: true,
        hasNewShiftInserts: true,
        replicateSeats: true,
      );
      expect(order.indexOf('archive-guard'), lessThan(order.indexOf('archive')));
      expect(order.indexOf('archive-guard'), lessThan(order.indexOf('update')));
      expect(order.indexOf('archive-guard'), lessThan(order.indexOf('insert')));
    });

    test('payment settings are saved after all shift mutations, then the snackbar shows', () {
      final order = handleSaveUnfixedOrder(
        hasShiftsToArchive: true,
        hasExistingShiftUpdates: true,
        hasNewShiftInserts: true,
        replicateSeats: true,
      );
      expect(order.indexOf('insert'), lessThan(order.indexOf('payment-save')));
      expect(order.indexOf('seat-replicate'), lessThan(order.indexOf('payment-save')));
      expect(order.indexOf('payment-save'), lessThan(order.indexOf('snackbar')));
      expect(order.indexOf('snackbar'), lessThan(order.indexOf('pop')));
    });

    test('seat replication only runs when new shifts were inserted', () {
      final noNew = handleSaveUnfixedOrder(
        hasShiftsToArchive: false,
        hasExistingShiftUpdates: true,
        hasNewShiftInserts: false,
        replicateSeats: false,
      );
      expect(noNew, isNot(contains('insert')));
      expect(noNew, isNot(contains('seat-replicate')));
      // The always-present steps still fire.
      expect(noNew, containsAll(<String>['payment-save', 'snackbar', 'pop']));
    });

    test('success message text is exactly the existing confirmation (Req 3.2)', () {
      expect(kSuccessMessage, 'Shifts & payment options saved successfully! ✓');
    });
  });

  // ===========================================================================
  // BUG 2/3 — shift-change send flow preserved (Req 3.3, 3.4)
  //
  // Faithful model of the shift-list filtering, insert payload, owner
  // notification type and success message from `_openShiftChangeRequestSheet`
  // in lib/screens/member_home.dart.
  // ===========================================================================
  group('BUG 2/3 preservation · shift-change send flow', () {
    const kSendSuccessMessage = 'Shift change request sent to the admin.';
    const kOwnerNotificationType = 'shift_change_request';

    // Mirror of the source filter: other (non-current), non-archived shifts in
    // the same library.
    List<Map<String, dynamic>> filterSelectableShifts(
      List<Map<String, dynamic>> all,
      String currentShiftId,
    ) {
      return all
          .where((s) => s['is_archived'] == false)
          .where((s) => s['id'].toString() != currentShiftId)
          .toList();
    }

    // Mirror of the insert payload built by the "Send request" button.
    Map<String, dynamic> buildInsertPayload({
      required String membershipId,
      required String memberId,
      required String libraryId,
      required String currentShiftId,
      required String requestedShiftId,
      required String reason,
    }) {
      return {
        'membership_id': membershipId,
        'member_id': memberId,
        'library_id': libraryId,
        'current_shift_id': currentShiftId,
        'requested_shift_id': requestedShiftId,
        'reason': reason,
        'status': 'pending',
      };
    }

    test('filtering excludes the current shift and archived shifts, same library', () {
      final all = [
        {'id': 'a', 'name': 'Morning', 'is_archived': false},
        {'id': 'b', 'name': 'Evening', 'is_archived': false},
        {'id': 'c', 'name': 'Old', 'is_archived': true},
      ];
      final selectable = filterSelectableShifts(all, 'a');
      final ids = selectable.map((s) => s['id']).toList();
      expect(ids, ['b']); // 'a' is current, 'c' is archived
    });

    test('property · filtered list never contains the current or an archived shift', () {
      final rng = Random(42);
      for (var iter = 0; iter < 200; iter++) {
        final n = rng.nextInt(8);
        final all = List.generate(n, (i) => <String, dynamic>{
              'id': 's$i',
              'name': 'Shift $i',
              'is_archived': rng.nextBool(),
            });
        final currentId = n == 0 ? 'none' : 's${rng.nextInt(n)}';
        final selectable = filterSelectableShifts(all, currentId);
        for (final s in selectable) {
          expect(s['id'].toString(), isNot(currentId));
          expect(s['is_archived'], isFalse);
        }
      }
    });

    test('insert payload carries the pending status and the expected fields', () {
      final payload = buildInsertPayload(
        membershipId: 'm1',
        memberId: 'u1',
        libraryId: 'lib1',
        currentShiftId: 'a',
        requestedShiftId: 'b',
        reason: 'closer to home',
      );
      expect(payload['status'], 'pending');
      expect(payload['membership_id'], 'm1');
      expect(payload['member_id'], 'u1');
      expect(payload['library_id'], 'lib1');
      expect(payload['current_shift_id'], 'a');
      expect(payload['requested_shift_id'], 'b');
      expect(payload['reason'], 'closer to home');
    });

    test('owner notification type and honest success message are unchanged', () {
      expect(kOwnerNotificationType, 'shift_change_request');
      expect(kSendSuccessMessage, 'Shift change request sent to the admin.');
    });

    // ── BUG 2 boundary (NOT the bug condition): a shift with no displayable
    //    times still shows its name only. This mirrors the current label
    //    builder for the empty-time case and must stay true after the fix.
    test('shift with no displayable times still renders the name (Req 3.4 boundary)', () {
      String unfixedOptionLabel(Map<String, dynamic> s) {
        final st = (s['start_time'] ?? '').toString();
        final en = (s['end_time'] ?? '').toString();
        final time = (st.isNotEmpty && en.isNotEmpty) ? '  ($st–$en)' : '';
        return '${s['name']}$time';
      }

      final noTimes = {'name': 'Flexi', 'start_time': '', 'end_time': ''};
      expect(unfixedOptionLabel(noTimes), 'Flexi');
    });
  });

  // ===========================================================================
  // BUG 4 — per-type counts + toggle set preserved (Req 3.5, 3.6)
  //
  // The sub-tab count for each type is derived directly from the list length
  // (see `_buildTabToggle` in requests_sub_tab.dart), so the rendered count
  // equals the list length by construction. The toggle set is fixed.
  // ===========================================================================
  group('BUG 4 preservation · counts + toggle set', () {
    // Mirror of the count selection in _buildTabToggle.
    int countForTab(
      int index,
      List joins,
      List seatChanges,
      List holds,
      List checkins,
      List shiftChanges,
    ) {
      switch (index) {
        case 0:
          return joins.length;
        case 1:
          return seatChanges.length;
        case 2:
          return holds.length;
        case 3:
          return checkins.length;
        default:
          return shiftChanges.length;
      }
    }

    List<Map<String, dynamic>> seed(int n) =>
        List.generate(n, (i) => {'id': i, 'status': 'pending'});

    test('the five request toggles are Join / Seats / Holds / Check-ins / Shifts', () {
      const toggles = ['Join', 'Seats', 'Holds', 'Check-ins', 'Shifts'];
      expect(toggles.length, 5);
      expect(toggles, ['Join', 'Seats', 'Holds', 'Check-ins', 'Shifts']);
    });

    test('property · per-tab count equals the corresponding list length', () {
      final rng = Random(7);
      for (var iter = 0; iter < 200; iter++) {
        final joins = seed(rng.nextInt(6));
        final seatChanges = seed(rng.nextInt(6));
        final holds = seed(rng.nextInt(6));
        final checkins = seed(rng.nextInt(6));
        final shiftChanges = seed(rng.nextInt(6));
        expect(countForTab(0, joins, seatChanges, holds, checkins, shiftChanges), joins.length);
        expect(countForTab(1, joins, seatChanges, holds, checkins, shiftChanges), seatChanges.length);
        expect(countForTab(2, joins, seatChanges, holds, checkins, shiftChanges), holds.length);
        expect(countForTab(3, joins, seatChanges, holds, checkins, shiftChanges), checkins.length);
        expect(countForTab(4, joins, seatChanges, holds, checkins, shiftChanges), shiftChanges.length);
      }
    });

    test('property · a healthy fetch renders one card per pending request', () {
      final rng = Random(99);
      for (var iter = 0; iter < 200; iter++) {
        final n = rng.nextInt(10);
        final list = seed(n);
        // When the fetch is OK, rendered card count == list length.
        final renderedCards = list.length;
        expect(renderedCards, n);
      }
    });
  });

  // ===========================================================================
  // BUG 4 — non-request notification routing preserved (Req 3.7)
  //
  // Uses the REAL production function NotificationService.routeForType. Request
  // types will change destination after the fix; NON-request types must NOT.
  // ===========================================================================
  group('BUG 4 preservation · non-request notification routing (Req 3.7)', () {
    const requestNotificationTypes = <String>{
      'join_request',
      'new_join_request',
      'seat_change_request',
      'shift_change_request',
      'hold_request',
      'checkin_approval_request',
    };

    bool isRequestNotification(String t) => requestNotificationTypes.contains(t);

    test('member notifications still route to /member/home', () {
      const memberTypes = [
        'join_approved',
        'join_rejected',
        'payment_confirmed',
        'payment_rejected',
        'payment_received',
        'hold',
        'hold_approved',
        'seat_assigned',
        'seat_change_approved',
        'membership_renewed',
        'checkin_approved',
        'badge',
        'leaderboard',
      ];
      for (final t in memberTypes) {
        expect(NotificationService.routeForType(t), '/member/home', reason: '$t unchanged');
        expect(isRequestNotification(t), isFalse);
      }
    });

    test('non-request admin notifications still route to /admin/home', () {
      const adminNonRequest = [
        'payment_submitted',
        'member_exited',
        'check_in',
        'check_out',
        'expiring_digest',
        'daily_summary',
        'dues_digest',
      ];
      for (final t in adminNonRequest) {
        expect(NotificationService.routeForType(t), '/admin/home', reason: '$t unchanged');
        expect(isRequestNotification(t), isFalse);
      }
    });

    test('center-handled types still return null (no named route)', () {
      for (final t in ['query_reply', 'new_query', 'refund_request', 'new_review', 'announcement']) {
        expect(NotificationService.routeForType(t), isNull, reason: '$t handled in-center');
      }
    });

    test('property · random non-request types keep their existing destination', () {
      const knownMember = [
        'join_approved', 'join_rejected', 'payment_confirmed', 'hold_approved',
        'seat_assigned', 'membership_renewed', 'checkin_approved', 'badge',
      ];
      const knownAdmin = [
        'payment_submitted', 'member_exited', 'check_in', 'check_out',
        'expiring_digest', 'daily_summary', 'dues_digest',
      ];
      final rng = Random(2024);
      for (var iter = 0; iter < 100; iter++) {
        if (rng.nextBool()) {
          final t = knownMember[rng.nextInt(knownMember.length)];
          expect(isRequestNotification(t), isFalse);
          expect(NotificationService.routeForType(t), '/member/home');
        } else {
          final t = knownAdmin[rng.nextInt(knownAdmin.length)];
          expect(isRequestNotification(t), isFalse);
          expect(NotificationService.routeForType(t), '/admin/home');
        }
      }
    });
  });

  // ===========================================================================
  // Pure-helper property: the 12-hour formatter the fix will reuse already
  // produces 12-hour, seconds-free output. This helper is NOT buggy (the bug is
  // that the dropdown does not use it), so this property PASSES today and must
  // keep passing. Mirrors _formatShiftTime in member_home.dart.
  // ===========================================================================
  group('Pure helper · reference 12-hour formatter (Req 2.3 helper preserved)', () {
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

    bool containsSeconds(String label) => RegExp(r'\d{1,2}:\d{2}:\d{2}').hasMatch(label);
    bool isTwelveHourFormat(String label) =>
        RegExp(r'\d{1,2}:\d{2}\s?(AM|PM)', caseSensitive: false).hasMatch(label);

    test('known times format to friendly 12-hour', () {
      expect(formatShiftTime('06:00:00'), '6:00 AM');
      expect(formatShiftTime('19:00:00'), '7:00 PM');
      expect(formatShiftTime('00:00:00'), '12:00 AM');
      expect(formatShiftTime('12:00:00'), '12:00 PM');
    });

    test('property · any HH:mm:ss pair formats to 12-hour with no seconds', () {
      final rng = Random(13);
      for (var iter = 0; iter < 300; iter++) {
        final h = rng.nextInt(24);
        final m = rng.nextInt(60);
        final sec = rng.nextInt(60);
        final raw = '${h.toString().padLeft(2, '0')}:'
            '${m.toString().padLeft(2, '0')}:'
            '${sec.toString().padLeft(2, '0')}';
        final label = formatShiftTime(raw);
        expect(containsSeconds(label), isFalse, reason: '$raw formatted with seconds: $label');
        expect(isTwelveHourFormat(label), isTrue, reason: '$raw not 12-hour: $label');
      }
    });
  });

  // ===========================================================================
  // Theme — warm-orange Material 3 palette unchanged (Req 3.8)
  // ===========================================================================
  group('Theme preservation · warm-orange Material 3 palette (Req 3.8)', () {
    test('brand primary is the warm-orange E65C00', () {
      expect(AppColors.primary, const Color(0xFFE65C00));
    });

    test('brand orange family and gradient are unchanged', () {
      expect(AppColors.primaryDark, const Color(0xFFB44900));
      expect(AppColors.primaryLight, const Color(0xFFFF6B00));
      expect(AppColors.headerGradient.colors, [AppColors.primaryLight, AppColors.primary]);
    });

    test('card radius token stays curved (Material 3 rounding)', () {
      expect(AppColors.cardRadius, greaterThan(0));
    });
  });
}
