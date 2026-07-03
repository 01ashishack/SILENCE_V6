# Bugfix Requirements Document

## Introduction

This spec captures four defects in the SILENCE admin & member shift-management and requests flow. Each defect is documented as a bug condition with the current (defective) behavior, the expected (correct) behavior, and the surrounding behavior that must remain unchanged so the fix does not cause a regression.

The four defects are:

- **BUG 1 — "Update Opening Hours?" popup always fires.** In the admin Shifts & Pay Method Setup screen (`lib/screens/shift_management.dart`), the reminder popup appears on every save regardless of whether the shift timing falls inside or outside the library's configured opening hours.
- **BUG 2 — 24-hour time format on member "Request Shift Change".** In `lib/screens/member_home.dart`, the shift-change selection shows raw `HH:mm:ss` timings instead of a friendly 12-hour format.
- **BUG 3 — Shift selection popup styling.** The shift-change selection control on the same member screen does not use a white background with rounded (curved) edges.
- **BUG 4 — Admin Requests sub-tab shows no requests + broken notification routing.** In `lib/screens/reservations/requests_sub_tab.dart` the request lists do not render (only the per-tab count is visible), and tapping a "request" notification does not navigate the admin to the Requests sub-tab.

All fixes must respect the project golden rules: no dishonest UI, keep the warm-orange (`#E65C00`) Material 3 style (refine, don't redesign), and treat the existing codebase as the source of truth. This is a single-tier fat client with no server tier.

## Bug Analysis

### Current Behavior (Defect)

**BUG 1 — Opening Hours reminder popup**

1.1 WHEN the admin saves a new or changed shift whose timing falls INSIDE the library's configured opening hours THEN the system still shows the "Update Opening Hours?" popup
1.2 WHEN the admin saves shifts without changing any shift timing THEN the system still shows the "Update Opening Hours?" popup

**BUG 2 — Member shift-change time format**

1.3 WHEN a member opens the "Request Shift Change" selection THEN the system displays each shift's timing in 24-hour format including seconds (e.g. "Morning (06:00:00–12:00:00)", "Evening Shift (19:00:00–23:00:00)")

**BUG 3 — Shift selection popup styling**

1.4 WHEN a member opens the shift selection on the "Request Shift Change" screen THEN the selection popup/list does not present a white background with curved (rounded) edges

**BUG 4 — Admin Requests sub-tab list + notification routing**

1.5 WHEN the admin opens the Requests sub-tab and a request type has one or more pending requests THEN the system shows only the count/number at the top and does not render the individual request items in the list
1.6 WHEN the admin taps a "request" notification (e.g. a shift-change / seat-change / join request) THEN the system does not navigate/redirect the admin to the Requests sub-tab

### Expected Behavior (Correct)

**BUG 1 — Opening Hours reminder popup**

2.1 WHEN the admin saves a new or changed shift whose timing falls INSIDE the library's configured opening hours THEN the system SHALL save without showing the "Update Opening Hours?" popup
2.2 WHEN the admin saves shifts without changing any shift timing THEN the system SHALL save without showing the "Update Opening Hours?" popup
2.7 WHEN the admin saves a new or changed shift whose timing falls OUTSIDE the library's configured opening hours THEN the system SHALL show the "Update Opening Hours?" popup

**BUG 2 — Member shift-change time format**

2.3 WHEN a member opens the "Request Shift Change" selection THEN the system SHALL display each shift's timing in 12-hour format with AM/PM and no seconds (e.g. "6:00 AM – 12:00 PM", "7:00 PM – 11:00 PM")

**BUG 3 — Shift selection popup styling**

2.4 WHEN a member opens the shift selection on the "Request Shift Change" screen THEN the selection popup/list SHALL present a white background with curved (rounded) edges, consistent with the warm-orange Material 3 style

**BUG 4 — Admin Requests sub-tab list + notification routing**

2.5 WHEN the admin opens the Requests sub-tab and a request type has one or more pending requests THEN the system SHALL render each pending request as an item in the list (in addition to showing the count)
2.6 WHEN the admin taps a "request" notification THEN the system SHALL navigate/redirect the admin to the Requests sub-tab screen

### Unchanged Behavior (Regression Prevention)

3.1 WHEN the admin saves shifts and payment options THEN the system SHALL CONTINUE TO persist shifts, archive removed shifts, replicate seat layouts, and save payment settings exactly as before
3.2 WHEN the admin saves shifts THEN the system SHALL CONTINUE TO show the existing success confirmation ("Shifts & payment options saved successfully! ✓")
3.3 WHEN a member submits a shift change request THEN the system SHALL CONTINUE TO insert the pending `shift_change_requests` row, notify the library owner, and show the honest success message
3.4 WHEN a member views the shift-change selection THEN the system SHALL CONTINUE TO list only other (non-current, non-archived) shifts in the same library and preserve the reason field and send behavior
3.5 WHEN the admin views the Requests sub-tab THEN the system SHALL CONTINUE TO show the correct per-type counts and the Join / Seats / Holds / Check-ins / Shifts tab toggles
3.6 WHEN the admin approves or rejects any request THEN the system SHALL CONTINUE TO perform the existing approval/rejection actions, notifications, and audit logging unchanged
3.7 WHEN the admin taps a non-request notification (e.g. payment, reply, approval) THEN the system SHALL CONTINUE TO route to its existing destination unchanged
3.8 WHEN any screen renders THEN the system SHALL CONTINUE TO honor the warm-orange (#E65C00) Material 3 theme and light/dark palette

## Bug Conditions and Properties

### BUG 1 — Opening Hours reminder popup

```pascal
FUNCTION isBugCondition(X)
  INPUT: X of type ShiftSave   // { shifts, openingHours, timingChanged }
  OUTPUT: boolean

  // Bug triggers whenever the popup shows for a save that should NOT prompt:
  // either timings were unchanged, or the (new/changed) timing is within opening hours.
  RETURN (NOT X.timingChanged) OR allShiftTimingsWithin(X.shifts, X.openingHours)
END FUNCTION
```

```pascal
// Property: Fix Checking - popup only for out-of-hours timing changes
FOR ALL X WHERE isBugCondition(X) DO
  result ← handleSave'(X)
  ASSERT openingHoursPopupShown(result) = FALSE
END FOR
```

```pascal
// Property: Preservation Checking
FOR ALL X WHERE NOT isBugCondition(X) DO
  ASSERT handleSave(X) = handleSave'(X)   // out-of-hours change still prompts; persistence unchanged
END FOR
```

### BUG 2 — Member shift-change time format

```pascal
FUNCTION isBugCondition(X)
  INPUT: X of type Shift   // { name, start_time, end_time }
  OUTPUT: boolean

  RETURN hasValidTimes(X.start_time, X.end_time)   // any shift with displayable times
END FUNCTION
```

```pascal
// Property: Fix Checking - 12-hour formatted display
FOR ALL X WHERE isBugCondition(X) DO
  label ← formatShiftOption'(X)
  ASSERT isTwelveHourFormat(label) AND NOT containsSeconds(label)
END FOR
```

### BUG 3 — Shift selection popup styling

```pascal
// Property: styling invariant
FOR ALL renders of the shift-change selection DO
  ASSERT background = white AND cornerRadius > 0
END FOR
```

### BUG 4 — Admin Requests sub-tab list + notification routing

```pascal
FUNCTION isBugCondition(X)
  INPUT: X of type RequestsView   // { pendingCountByType, tappedNotificationType }
  OUTPUT: boolean

  RETURN anyPendingRequests(X.pendingCountByType)
      OR isRequestNotification(X.tappedNotificationType)
END FUNCTION
```

```pascal
// Property: Fix Checking - list renders and notification routes
FOR ALL X WHERE anyPendingRequests(X.pendingCountByType) DO
  view ← renderRequests'(X)
  ASSERT renderedItemCount(view, type) = X.pendingCountByType[type]
END FOR

FOR ALL X WHERE isRequestNotification(X.tappedNotificationType) DO
  dest ← handleNotificationTap'(X)
  ASSERT dest = RequestsSubTab
END FOR
```

**Key Definitions:**
- **F** — the current code before the fix (`handleSave`, `formatShiftOption`, `renderRequests`, `handleNotificationTap`).
- **F'** — the code after the fix.
