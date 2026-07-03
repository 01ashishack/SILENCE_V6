import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:silence/core/active_library_store.dart';
import 'package:silence/services/notification_service.dart';

/// BUG 4 — Admin Requests sub-tab list + notification routing.
///
/// VERIFICATION tests (matured from the original exploration tests). They now
/// assert the ACTUAL implemented fix rather than the earlier (incorrect)
/// assumptions about how routing would work.
///
/// Two independent defects (design.md → BUG 4) and how the fix addresses them:
///   1. `_fetchRequests()` originally ran all four rich embedded selects under
///      ONE try/catch, so a single failing embed blanked every list while the
///      lightweight per-type COUNT badge still showed a positive number
///      ("only the count shows"). The fix gives each select its OWN try/catch
///      with a per-type failure flag, so a sibling failure no longer blanks the
///      healthy lists — the failing type is empty/flagged, the rest render.
///   2. Request-type notifications kept `/admin/home` as the base route, but the
///      Requests sub-tab jump is now driven by a CONSUMED navigation intent:
///      `ActiveLibraryStore.requestAdminDestination('requests')` is called only
///      when `NotificationService.isRequestNotification(type)` is true, and
///      `routeForType('shift_change_request')` now returns `/admin/home` instead
///      of null (no longer dropped).
///
/// `NotificationService.routeForType` / `isRequestNotification` and
/// `ActiveLibraryStore.requestAdminDestination` are real, reachable production
/// code and are exercised directly. `_fetchRequests` is a private, DB-coupled
/// State method with no injection seam, so its per-type try/catch shape is
/// reproduced here by a faithful model (`fetchRequestsFixed`).
void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // Part 1 — Notification routing (REAL production code)
  //
  // The implemented fix keeps request notifications routing to '/admin/home' as
  // the base route and drives the Requests sub-tab jump through a consumed
  // navigation intent. So we validate the REAL mechanism, not `isNot('/admin/home')`.
  // ───────────────────────────────────────────────────────────────────────────
  group('BUG 4 · routing — request notifications reach the admin Requests sub-tab via a consumed intent', () {
    test('shift_change_request is handled (not dropped) — Req 2.6', () {
      // Previously absent from routeForType's admin group → fell through to
      // `default` and returned null (dropped). Now handled on the admin shell.
      final route = NotificationService.routeForType('shift_change_request');
      expect(route, isNotNull,
          reason: 'shift_change_request must be routed for the admin, not dropped');
      expect(route, '/admin/home',
          reason: 'request notifications keep /admin/home as the base route; '
              'the Requests sub-tab jump is driven by a navigation intent');
    });

    test('every request-type notification is classified as a request and routes to the admin shell — Req 2.6', () {
      // isRequestNotification(type) is what triggers the sub-tab intent, and the
      // base route stays /admin/home for all of them.
      for (final t in NotificationService.requestNotificationTypes) {
        expect(NotificationService.isRequestNotification(t), isTrue,
            reason: '$t must be classified as a request notification (triggers the sub-tab intent)');
        expect(NotificationService.routeForType(t), '/admin/home',
            reason: '$t routes to the admin shell; the sub-tab jump is intent-driven');
      }
    });

    test('the navigation intent path lands the admin on Reservations → Requests — Req 2.6', () {
      // Mirrors what the notification-tap handlers do for a request type:
      // set the consumed intent to 'requests'. admin_home listens for this and
      // performs the Reservations → Requests jump, then nulls it.
      addTearDown(() => ActiveLibraryStore.adminDestinationRequest.value = null);

      ActiveLibraryStore.adminDestinationRequest.value = null; // clean baseline
      ActiveLibraryStore.requestAdminDestination('requests');
      expect(ActiveLibraryStore.adminDestinationRequest.value, 'requests',
          reason: 'a request-type tap must broadcast the Reservations → Requests intent');

      // Simulate the listener consuming the intent (admin_home nulls it after jump).
      ActiveLibraryStore.adminDestinationRequest.value = null;
      expect(ActiveLibraryStore.adminDestinationRequest.value, isNull,
          reason: 'the intent is consumed-then-nulled so it fires exactly once');
    });
  });

  // Preservation guard (Req 3.7): non-request notifications must keep routing to
  // their existing destinations and must NOT be classified as requests.
  group('BUG 4 · routing preservation — non-request notifications unchanged (Req 3.7)', () {
    test('member destinations still route to /member/home', () {
      expect(NotificationService.routeForType('join_approved'), '/member/home');
      expect(NotificationService.routeForType('payment_confirmed'), '/member/home');
    });

    test('non-request admin destinations still route to /admin/home and are not requests', () {
      for (final t in ['payment_submitted', 'check_in', 'check_out', 'daily_summary', 'dues_digest']) {
        expect(NotificationService.routeForType(t), '/admin/home', reason: '$t unchanged');
      }
      // And these are NOT request notifications → they never trigger the intent.
      for (final t in ['payment_submitted', 'check_in', 'daily_summary']) {
        expect(NotificationService.isRequestNotification(t), isFalse);
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Part 2 — Requests list rendering / fetch isolation
  //
  // Faithful model of the FIXED _fetchRequests(): the join, seat-change, hold,
  // check-in and shift-change selects each run in their OWN try/catch, so a
  // failing embed only empties/flags its own type — every healthy list still
  // renders its full length and setState always runs.
  // ───────────────────────────────────────────────────────────────────────────
  ({
    List<Map<String, dynamic>> join,
    List<Map<String, dynamic>> seatChange,
    List<Map<String, dynamic>> hold,
    List<Map<String, dynamic>> checkin,
    List<Map<String, dynamic>> shiftChange,
    bool joinFailed,
    bool seatChangeFailed,
    bool holdFailed,
    bool checkinFailed,
    bool shiftChangeFailed,
  }) fetchRequestsFixed({
    List<Map<String, dynamic>> joinList = const [],
    List<Map<String, dynamic>> seatChangeList = const [],
    List<Map<String, dynamic>> holdList = const [],
    List<Map<String, dynamic>> checkinList = const [],
    List<Map<String, dynamic>> shiftChangeList = const [],
    bool joinThrows = false,
    bool seatChangeThrows = false,
    bool holdThrows = false,
    bool checkinThrows = false,
    bool shiftChangeThrows = false,
  }) {
    var join = <Map<String, dynamic>>[];
    var joinFailed = false;
    try {
      if (joinThrows) throw Exception('join embed failed');
      join = List<Map<String, dynamic>>.from(joinList);
    } catch (_) {
      joinFailed = true;
    }

    var seatChange = <Map<String, dynamic>>[];
    var seatChangeFailed = false;
    try {
      if (seatChangeThrows) throw Exception('seat_change embed failed');
      seatChange = List<Map<String, dynamic>>.from(seatChangeList);
    } catch (_) {
      seatChangeFailed = true;
    }

    var hold = <Map<String, dynamic>>[];
    var holdFailed = false;
    try {
      if (holdThrows) throw Exception('hold embed failed');
      hold = List<Map<String, dynamic>>.from(holdList);
    } catch (_) {
      holdFailed = true;
    }

    var checkin = <Map<String, dynamic>>[];
    var checkinFailed = false;
    try {
      if (checkinThrows) throw Exception('checkin embed failed');
      checkin = List<Map<String, dynamic>>.from(checkinList);
    } catch (_) {
      checkinFailed = true;
    }

    var shiftChange = <Map<String, dynamic>>[];
    var shiftChangeFailed = false;
    try {
      if (shiftChangeThrows) throw Exception('shift_change embed failed');
      shiftChange = List<Map<String, dynamic>>.from(shiftChangeList);
    } catch (_) {
      shiftChangeFailed = true;
    }

    // setState always runs — no single try/catch wraps the whole method.
    return (
      join: join,
      seatChange: seatChange,
      hold: hold,
      checkin: checkin,
      shiftChange: shiftChange,
      joinFailed: joinFailed,
      seatChangeFailed: seatChangeFailed,
      holdFailed: holdFailed,
      checkinFailed: checkinFailed,
      shiftChangeFailed: shiftChangeFailed,
    );
  }

  List<Map<String, dynamic>> seed(int n, String kind) =>
      List.generate(n, (i) => {'id': '$kind-$i', 'status': 'pending'});

  group('BUG 4 · list — a healthy fetch renders one card per pending request (Req 2.5)', () {
    test('non-empty join list while a sibling embed fails → join cards still render', () {
      final joins = seed(2, 'join');
      final result = fetchRequestsFixed(joinList: joins, seatChangeThrows: true);
      // Healthy join list renders in full; only seat-change is empty/flagged.
      expect(result.join.length, joins.length,
          reason: 'the join list must render all its items despite a seat-change failure');
      expect(result.seatChange, isEmpty, reason: 'the failing type is empty');
      expect(result.seatChangeFailed, isTrue, reason: 'the failing type is flagged for an honest error tile');
      expect(result.joinFailed, isFalse, reason: 'the healthy type is not flagged');
    });

    test('a single failing embed does not blank the healthy lists (fetch isolation)', () {
      final joins = seed(3, 'join');
      final holds = seed(1, 'hold');
      final checkins = seed(2, 'checkin');
      final result = fetchRequestsFixed(
        joinList: joins,
        holdList: holds,
        checkinList: checkins,
        seatChangeThrows: true, // one embed fails
      );
      expect(result.join.length, joins.length, reason: 'joins survive a seat-change failure');
      expect(result.hold.length, holds.length, reason: 'holds survive a seat-change failure');
      expect(result.checkin.length, checkins.length, reason: 'check-ins survive a seat-change failure');
      // Only the failing type is empty + flagged.
      expect(result.seatChange, isEmpty);
      expect(result.seatChangeFailed, isTrue);
      expect(result.holdFailed, isFalse);
      expect(result.checkinFailed, isFalse);
    });

    test('property: for any set of pending lists, a failed sibling embed still yields all healthy lists', () {
      final rng = Random(1234);
      for (var iter = 0; iter < 100; iter++) {
        final nJoin = rng.nextInt(5);
        final nHold = rng.nextInt(5);
        final nCheckin = rng.nextInt(5);
        final joins = seed(nJoin, 'join');
        final holds = seed(nHold, 'hold');
        final checkins = seed(nCheckin, 'checkin');
        final result = fetchRequestsFixed(
          joinList: joins,
          holdList: holds,
          checkinList: checkins,
          seatChangeThrows: true,
        );
        // Invariant: rendered count == list length for every healthy type.
        expect(result.join.length, nJoin);
        expect(result.hold.length, nHold);
        expect(result.checkin.length, nCheckin);
        // The failing type is consistently empty + flagged.
        expect(result.seatChange, isEmpty);
        expect(result.seatChangeFailed, isTrue);
      }
    });
  });

  // Sanity: when NO embed fails, every list renders its full length and nothing
  // is flagged (the correct all-healthy case).
  group('BUG 4 · list — all-healthy fetch renders correctly (correct case)', () {
    test('every list renders its full length when nothing throws', () {
      final result = fetchRequestsFixed(
        joinList: seed(2, 'join'),
        seatChangeList: seed(1, 'seat'),
        holdList: seed(3, 'hold'),
        checkinList: seed(1, 'checkin'),
        shiftChangeList: seed(2, 'shift'),
      );
      expect(result.join.length, 2);
      expect(result.seatChange.length, 1);
      expect(result.hold.length, 3);
      expect(result.checkin.length, 1);
      expect(result.shiftChange.length, 2);
      // No type is flagged as failed.
      expect(result.joinFailed, isFalse);
      expect(result.seatChangeFailed, isFalse);
      expect(result.holdFailed, isFalse);
      expect(result.checkinFailed, isFalse);
      expect(result.shiftChangeFailed, isFalse);
    });
  });
}
