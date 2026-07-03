# Shift Requests Bugfixes — Bugfix Design

## Overview

This document diagnoses the root cause of the four defects captured in `bugfix.md`
and specifies a targeted, minimal fix for each. All four fixes stay inside the
existing screens and honor the golden rules: no dishonest UI, keep the warm-orange
(`#E65C00`) Material 3 style (refine, don't redesign), the existing codebase is the
source of truth, and this is a single-tier fat client (no server tier / no new RPC).

The four fixes at a glance:

- **BUG 1** (`lib/screens/shift_management.dart`) — `_handleSave()` calls
  `_showOpeningHoursReminder()` unconditionally after every successful save. There
  is no tracking of whether any shift timing actually changed, and no comparison
  against the library's configured opening hours. The fix adds (a) capture of the
  original timings at load, (b) parsing of the free-text `libraries.opening_hours`,
  and (c) a guard that only shows the reminder when a new/changed shift timing falls
  OUTSIDE the parsed opening hours.
- **BUG 2** (`lib/screens/member_home.dart`) — the "Request Shift Change" dropdown
  builds its option label from the raw `start_time`/`end_time` strings
  (`HH:mm:ss`). The fix reuses the screen's existing `_formatShiftRange(shift)`
  helper to render a 12-hour AM/PM range with no seconds.
- **BUG 3** (same screen) — the shift-selection dropdown uses default Material menu
  styling. The fix gives the dropdown menu a white surface and rounded (curved)
  corners consistent with the warm-orange Material 3 theme.
- **BUG 4** (`lib/screens/reservations/requests_sub_tab.dart` + notification
  routing) — the per-type request lists never populate because `_fetchRequests()`
  runs all four rich embedded selects under a single `try/catch`; one failing embed
  aborts the whole method and leaves every list empty, while the parent
  `reservations_tab` badge (a lightweight `select('id')` count) still shows a
  non-zero number — hence "only the count shows". Separately, request-type
  notifications route to `/admin/home` (the dashboard) instead of the Requests
  sub-tab. The fix isolates each fetch (per-type `try/catch` + honest error state)
  and wires request-type notification taps to the already-existing
  `_navigateToReservationsRequestsTab()` jump via a consumed navigation intent.

## Glossary

- **Bug_Condition (C)**: The condition under which a defect manifests (per bug,
  formalized below).
- **Property (P)**: The desired post-fix behavior for inputs satisfying C.
- **Preservation**: Existing behavior for inputs NOT satisfying C that must remain
  byte-for-byte identical after the fix.
- **`_handleSave` / `_showOpeningHoursReminder`**: Methods in
  `lib/screens/shift_management.dart` that persist shifts/payment settings and show
  the "Update Opening Hours?" dialog.
- **`libraries.opening_hours`**: A free-text column set by the admin under
  Profile → Library Management → About & Info (e.g. `"6:00 AM – 11:00 PM"`,
  `"Open 24 Hours"`). Not a structured time range.
- **`_openShiftChangeRequestSheet`**: Method in `lib/screens/member_home.dart` that
  presents the member "Request Shift Change" bottom sheet + shift dropdown.
- **`_formatShiftRange` / `_formatShiftTime`**: Existing 12-hour AM/PM formatting
  helpers already present in `member_home.dart` (lines ~4115–4140).
- **`_fetchRequests`**: Method in `requests_sub_tab.dart` that loads the five pending
  request lists (join, seat-change, hold, check-in approval, shift-change).
- **`routeForType` / `_onTapNotification`**: The notification routing switch in
  `lib/services/notification_service.dart` and the in-app tap handler in
  `lib/screens/notifications_screen.dart`.
- **`_navigateToReservationsRequestsTab()`**: Existing method in
  `lib/screens/admin_home.dart` that sets `_reservationsInitialSubTab = 2` and
  `_currentTab = 1` to land the admin on Reservations → Requests.
- **`ActiveLibraryStore.switchRequest`**: An existing `ValueNotifier<String?>`
  consumed-then-nulled pattern used to broadcast a "switch library" intent from the
  notification center into `admin_home`. The BUG 4 routing fix mirrors this pattern.

## Bug Details

### BUG 1 — "Update Opening Hours?" popup always fires

#### Bug Condition

`_handleSave()` (in `shift_management.dart`) always runs
`await _showOpeningHoursReminder();` on the success path, regardless of whether any
timing changed or whether the timing is inside the configured opening hours. The
method never loads `libraries.opening_hours` and never records the shifts' original
timings, so it cannot make the decision correctly.

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type ShiftSave   // { shifts, originalShifts, openingHours }
  OUTPUT: boolean

  // The popup should NOT fire in either of these cases; today it always fires.
  RETURN (NOT anyTimingChanged(input.shifts, input.originalShifts))
         OR allChangedTimingsWithin(input.shifts, input.originalShifts, input.openingHours)
END FUNCTION
```

Where:
- `anyTimingChanged` = there is at least one new shift (id == null) OR an existing
  shift whose `startTime`/`endTime` differs from what was loaded.
- `allChangedTimingsWithin` = every new/changed shift's `[start, end]` falls inside
  the parsed opening-hours range (and the opening hours parsed to a definite range
  or "all day").

### Examples

- Admin edits only a shift's **price** (no timing change) and saves → **today:**
  popup shows. **Expected:** no popup (Req 2.2).
- Library opening hours are `"6:00 AM – 11:00 PM"`; admin changes a shift to
  `7:00 AM–1:00 PM` (inside) and saves → **today:** popup shows. **Expected:** no
  popup (Req 2.1).
- Library opening hours are `"6:00 AM – 11:00 PM"`; admin changes a shift to
  `5:00 AM–1:00 PM` (starts before open) and saves → **today:** popup shows.
  **Expected:** popup shows (Req 2.7) — this is the one case where it is correct.
- Opening hours are `"Open 24 Hours"`; admin changes any shift and saves →
  **Expected:** no popup (every timing is within 24h).
- Opening hours are blank/garbled and admin changes a timing → **Expected:** popup
  shows (conservative fallback — see Testing Strategy tradeoffs).

### BUG 2 — Member shift-change time format (24-hour + seconds)

#### Bug Condition

In `_openShiftChangeRequestSheet`, the dropdown item label is built from raw DB
strings:
```dart
final st = (s['start_time'] ?? '').toString();   // "06:00:00"
final en = (s['end_time'] ?? '').toString();      // "12:00:00"
final time = (st.isNotEmpty && en.isNotEmpty) ? '  ($st–$en)' : '';
```
so the option reads `Morning  (06:00:00–12:00:00)`.

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type Shift   // { name, start_time, end_time }
  OUTPUT: boolean

  RETURN hasValidTimes(input.start_time, input.end_time)   // any shift with displayable times
END FUNCTION
```

### Examples

- `start_time = "06:00:00", end_time = "12:00:00"` → **today:** `(06:00:00–12:00:00)`.
  **Expected:** `6:00 AM – 12:00 PM` (Req 2.3).
- `start_time = "19:00:00", end_time = "23:00:00"` → **today:** `(19:00:00–23:00:00)`.
  **Expected:** `7:00 PM – 11:00 PM`.
- A shift with an empty/malformed time → **Expected:** the range gracefully collapses
  (helper already returns `—`/single value); the option still shows the shift name.

### BUG 3 — Shift selection popup styling

#### Bug Condition

The `DropdownButtonFormField<String>` in `_openShiftChangeRequestSheet` uses the
default dropdown menu surface (theme `canvasColor`) and default (square) menu
corners. It does not present the white, curved surface required by Req 2.4.

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type SelectionRender
  OUTPUT: boolean

  RETURN (selectionMenuBackground(input) != white)
         OR (selectionMenuCornerRadius(input) == 0)
END FUNCTION
```

### Examples

- Member opens the shift dropdown → **today:** menu surface follows the default
  theme canvas with square corners. **Expected:** white background, rounded corners
  (Req 2.4), warm-orange accent preserved.

### BUG 4 — Admin Requests sub-tab list + notification routing

#### Bug Condition

Two independent defects share this screen/flow:

1. **List does not render.** `_fetchRequests()` executes four rich embedded selects
   (join, seat-change, hold, check-in approval) under **one** `try/catch`. If any
   single embed fails to resolve (e.g. a PostgREST relationship/embed error or an
   RLS visibility issue on an embedded table), the whole method throws before
   `setState`, leaving all five lists at their initial `[]`. Meanwhile the parent
   `reservations_tab._loadPendingRequestsCount()` uses lightweight
   `select('id')` count queries (no embeds) that still succeed → the sub-tab badge
   shows a non-zero count while the list shows the empty state. Additionally, the
   empty state text ("No pending join requests.") is shown even when the count is
   non-zero — a **dishonest UI** we must correct.
2. **Notification routing.** `routeForType` and `notifications_screen._onTapNotification`
   map request-type notifications (`join_request`, `new_join_request`,
   `seat_change_request`, `shift_change_request`, `hold_request`,
   `checkin_approval_request`) to `/admin/home` (the dashboard), never to the
   Requests sub-tab. (`shift_change_request` is additionally missing from
   `routeForType`'s admin cases entirely.)

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type RequestsView   // { pendingCountByType, tappedNotificationType }
  OUTPUT: boolean

  RETURN anyPendingRequests(input.pendingCountByType)          // list must render items
      OR isRequestNotification(input.tappedNotificationType)   // tap must land on Requests
END FUNCTION
```

Where `isRequestNotification(t)` is true for `t` in
`{ join_request, new_join_request, seat_change_request, shift_change_request,
   hold_request, checkin_approval_request }`.

### Examples

- Library has 2 pending join requests → **today:** "Joins" badge shows `2`, list
  shows "No pending join requests." **Expected:** two request cards render (Req 2.5).
- One embed (e.g. seat-change) errors while joins are fine → **today:** ALL five
  lists blank. **Expected:** the healthy lists still render; only the failing list
  shows an honest error/retry state.
- Admin taps a "shift change request" notification → **today:** lands on the admin
  dashboard. **Expected:** lands on Reservations → Requests (Req 2.6).
- Admin taps a `payment_submitted` / `check_in` notification → **Expected:**
  unchanged — still lands on the dashboard (Req 3.7).

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- BUG 1: `_handleSave` must still archive removed shifts, guard archive against
  active memberships, update/insert shifts, replicate seat layouts, save payment
  settings, and show the success snackbar ("Shifts & payment options saved
  successfully! ✓") in the same order (Req 3.1, 3.2). The reminder dialog's own
  content/style is unchanged — only *whether* it appears changes.
- BUG 2/3: the shift-change sheet must still list only other (non-current,
  non-archived) shifts in the same library, preserve the reason field, the
  "Send request" insert into `shift_change_requests`, the owner notification, and
  the honest success message (Req 3.3, 3.4). Only the option label text (BUG 2) and
  the menu surface/corners (BUG 3) change.
- BUG 4: the Requests sub-tab must still show the correct per-type counts and the
  Join / Seats / Holds / Check-ins / Shifts toggles (Req 3.5); approve/reject flows,
  notifications, and audit logging are unchanged (Req 3.6); non-request notifications
  route to their existing destinations (Req 3.7).
- All screens keep the warm-orange (`#E65C00`) Material 3 theme and light/dark
  palette (Req 3.8).

**Scope:**
Inputs that do NOT satisfy each bug condition must be completely unaffected:
- BUG 1: saves with no timing change, and timing changes that stay inside opening
  hours (no popup either way — that IS the corrected behavior); persistence path
  untouched.
- BUG 2/3: shifts with no displayable times still render their name.
- BUG 4: request types NOT in the request-notification set; and any list whose fetch
  succeeds.

## Hypothesized Root Cause

### BUG 1
1. **Unconditional call**: `_handleSave` always calls `_showOpeningHoursReminder()`
   on success — there is no condition at all.
2. **No original-timing snapshot**: `_loadData` populates `_shifts` but never
   records the loaded start/end, so "did a timing change?" cannot be answered.
3. **Opening hours never loaded**: `_loadData` selects only `social_links`; it does
   not read `libraries.opening_hours`, so an inside/outside comparison is impossible.

### BUG 2
1. **Raw string interpolation**: the dropdown label uses `start_time`/`end_time`
   verbatim (`HH:mm:ss`) instead of the existing formatter.

### BUG 3
1. **Default menu surface**: `DropdownButtonFormField` is created without
   `dropdownColor` or `borderRadius`, so it inherits the default theme canvas and
   square corners.

### BUG 4
1. **Single shared `try/catch`**: one failing embedded select in `_fetchRequests`
   zeroes out all lists (the `shift_change_requests` fetch already has its own
   `try/catch`; the other four do not).
2. **Fragile/embedded selects**: the join and seat-change selects rely on PostgREST
   resource embedding (`member_id(...)`, `shifts(name)`, `seats:requested_seat_id(...)`,
   and two FKs to `seats` via `current_seat:current_seat_id` / `new_seat:new_seat_id`).
   An embed that fails to resolve (schema-cache/relationship error) or an RLS block
   on an embedded table throws the whole method.
3. **Dishonest empty state**: a thrown fetch shows "No pending X" even when pending
   items exist.
4. **Routing target**: request-type notifications map to `/admin/home` instead of the
   Requests sub-tab; `shift_change_request` is also absent from `routeForType`.

## Correctness Properties

Property 1: Bug Condition — Opening-hours reminder only for out-of-hours timing changes

_For any_ save where the bug condition holds (no shift timing changed, OR every
new/changed shift timing falls within the parsed opening hours), the fixed
`_handleSave` SHALL persist normally and NOT show the "Update Opening Hours?" dialog;
and _for any_ save where a new/changed shift timing falls outside the parsed opening
hours, it SHALL show the dialog.

**Validates: Requirements 2.1, 2.2, 2.7**

Property 2: Bug Condition — 12-hour shift-change option formatting

_For any_ shift with displayable start/end times shown in the member "Request Shift
Change" dropdown, the fixed option label SHALL render the timing in 12-hour AM/PM
format with no seconds (e.g. `6:00 AM – 12:00 PM`).

**Validates: Requirements 2.3**

Property 3: Bug Condition — Shift selection popup styling

_For any_ render of the member shift-selection menu, the fixed control SHALL present
a white background with a corner radius greater than zero, consistent with the
warm-orange Material 3 theme.

**Validates: Requirements 2.4**

Property 4: Bug Condition — Requests list renders + notification routes to Requests

_For any_ request type with one or more pending requests whose fetch succeeds, the
fixed Requests sub-tab SHALL render one card per pending request (in addition to the
count); and _for any_ request-type notification tap, the fixed routing SHALL land the
admin on the Reservations → Requests sub-tab.

**Validates: Requirements 2.5, 2.6**

Property 5: Preservation — non-bug inputs unchanged

_For any_ input where the bug condition does NOT hold, the fixed code SHALL produce
the same result as the original code: shift/payment persistence, archive, seat
replication and success message (BUG 1); the shift-list filtering, reason field,
insert, owner notification and success message (BUG 2/3); the per-type counts,
approve/reject/audit flows, and non-request notification destinations (BUG 4).

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8**

## Fix Implementation

### BUG 1 — Conditional opening-hours reminder

**File**: `lib/screens/shift_management.dart`

**Functions**: `_loadData`, `_handleSave`, `_showOpeningHoursReminder`, plus new
helpers.

**Specific Changes**:
1. **Snapshot original timings on load**: in `_loadData`, after building each
   `_ShiftModel`, record its id + start/end into a `Map<String, (TimeOfDay,TimeOfDay)>`
   `_originalTimings` (keyed by shift id). New shifts (id == null) are, by definition,
   changed.
2. **Load opening hours**: extend the existing `libraries` select in `_loadData` from
   `select('social_links')` to `select('social_links, opening_hours')` and store the
   raw text in `String? _openingHoursRaw`.
3. **Add a robust free-text parser** `_HoursRange? _parseOpeningHours(String? raw)`:
   - Normalize: lowercase, replace en/em dashes and the words `to`/`till`/`until`
     with a common separator.
   - "All day" detection: if the text contains `24` + `hour`, `24/7`, `24x7`,
     `all day`, `always open`, or `open 24` → return an `allDay` range (never
     out-of-hours).
   - Otherwise extract time tokens with a regex like
     `(\d{1,2})(?::(\d{2}))?\s*(am|pm)?` and take the FIRST token as open and the
     LAST token as close. Interpret 12-hour (am/pm) or 24-hour based on the token.
   - If fewer than two tokens parse → return `null` (unparseable).
4. **Add a range comparison** `bool _timingWithin(TimeOfDay s, TimeOfDay e, _HoursRange r)`:
   - Convert to minutes-since-midnight. If the opening range closes past midnight
     (`close <= open`), add 24h to close; likewise if a shift ends past midnight.
   - Return `open <= start && end <= close`.
5. **Guard the reminder** in `_handleSave` (replace the unconditional call):
   - Compute `changed` = list of shifts that are new or whose start/end differs from
     `_originalTimings`.
   - `bool shouldRemind`:
     - if `changed.isEmpty` → `false` (Req 2.2);
     - else parse opening hours: if `allDay` → `false`; if parsed range → `true` iff
       ANY changed shift is NOT `_timingWithin` (Req 2.1 / 2.7);
     - if unparseable/blank → `true` (conservative fallback — see tradeoffs).
   - Only `await _showOpeningHoursReminder();` when `shouldRemind`. Everything else in
     the success path (snackbar, `Navigator.pop(context, true)`) is unchanged.

### BUG 2 — 12-hour option formatting (reuse existing helper)

**File**: `lib/screens/member_home.dart`

**Function**: `_openShiftChangeRequestSheet` (dropdown item builder).

**Specific Changes**:
1. Replace the raw-string label with the existing formatter. Since each `s` is a
   shift map with `start_time`/`end_time`, call `_formatShiftRange(s)` (already returns
   `"6:00 AM – 12:00 PM"`, collapses gracefully when a time is missing). Compose the
   label as `'${s['name']}  ($range)'` when `range` is non-empty and not `—`, else
   just the name. No new helper is introduced (Req 2.3, reuse mandate).

### BUG 3 — White, rounded shift selection menu

**File**: `lib/screens/member_home.dart`

**Function**: `_openShiftChangeRequestSheet` (the `DropdownButtonFormField`).

**Specific Changes**:
1. Set `dropdownColor: Colors.white` and `borderRadius: BorderRadius.circular(12)` on
   the `DropdownButtonFormField` so the opened menu is white with curved corners.
2. Round the field's own border: give the `InputDecoration.border`/`enabledBorder`/
   `focusedBorder` an `OutlineInputBorder(borderRadius: BorderRadius.circular(12))`
   with the warm-orange focus color, keeping M3 consistency (Req 2.4, 3.8). Do not
   change layout or the accent hierarchy.

### BUG 4 — Resilient fetch + honest states + notification routing

**File**: `lib/screens/reservations/requests_sub_tab.dart`

**Function**: `_fetchRequests` + per-tab empty/error rendering.

**Specific Changes**:
1. **Isolate each fetch**: wrap each of the join, seat-change, hold, and check-in
   selects in its own `try/catch` (mirroring the existing `shift_change_requests`
   block) so one failing embed cannot blank the others. Track per-type load failure
   in booleans (e.g. `_joinLoadFailed`, ...).
2. **Harden the embeds**: verify each embed hint against the schema and disambiguate
   explicitly. `seat_change_requests` has two FKs to `seats`
   (`current_seat_id`, `new_seat_id`) — keep the `alias:fk_column(...)` disambiguation
   and confirm the FK names match the schema. If any embed still cannot resolve
   reliably, fall back to a plain column `select()` for that type plus a small keyed
   lookup for the related label (documented tradeoff below), so the list still
   renders honest data.
3. **Honest states**: when a type's fetch fails, render an error/retry tile for that
   tab instead of the "No pending X" empty state (which must only show when the fetch
   succeeded AND the list is genuinely empty). This removes the dishonest UI.

**File**: `lib/services/notification_service.dart`

**Function**: `routeForType`.
4. Keep request-type notifications routed to the admin shell, but make the target the
   Requests sub-tab rather than the bare dashboard. Add the missing
   `shift_change_request` case to the admin group so it is handled consistently.

**File**: `lib/core/active_library_store.dart` (or a small dedicated intent store).
5. Add a navigation-intent `ValueNotifier` — e.g.
   `static final ValueNotifier<String?> adminDestinationRequest` — mirroring the
   existing `switchRequest` consumed-then-nulled pattern. A value of `'requests'`
   means "open Reservations → Requests".

**File**: `lib/screens/notifications_screen.dart` (`_onTapNotification`) and
`lib/services/push_notification_service.dart` (deep-link tap handler).
6. When the tapped notification `type` is in the request-notification set, set
   `adminDestinationRequest.value = 'requests'` (in addition to the existing
   `ActiveLibraryStore.requestSwitch(libId)` when a `library_id` is present), then
   navigate to `/admin/home`. Non-request types are untouched (Req 3.7).

**File**: `lib/screens/admin_home.dart`.
7. In `initState`, add a listener on `adminDestinationRequest` (like
   `_onExternalSwitchRequest`). On a `'requests'` value, call the EXISTING
   `_navigateToReservationsRequestsTab()` (which already sets
   `_reservationsInitialSubTab = 2` + `_currentTab = 1`), then null the notifier to
   consume it. Remove the listener in `dispose`. Ordering note: when both a library
   switch and a requests intent are pending, apply the library switch first, then the
   sub-tab jump, so `initialSubTab` is honored for the correct library.

## Testing Strategy

### Validation Approach

Two phases: first surface counterexamples that demonstrate each bug on the UNFIXED
code (confirming the root cause), then verify the fix produces correct behavior and
preserves everything else. Because this is a Flutter fat client with no server tier,
tests are widget/unit tests plus pure-function property tests over the new helpers
(opening-hours parsing/comparison, label formatting, request-notification
classification). DB-embedded fetch behavior (BUG 4 rendering) is validated with
widget tests that inject stub request lists / an injected failure, since we cannot
hit the live Supabase DB from tests.

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate each bug BEFORE implementing the
fix, to confirm or refute the root-cause analysis. If refuted, re-hypothesize.

**Test Plan**: Drive each screen/helper and assert the current (wrong) behavior, then
after the fix assert the corrected behavior.

**Test Cases**:
1. **BUG 1 unchanged-save**: save with no timing change → assert reminder shown
   (fails-as-bug on unfixed code; must be no-popup after fix).
2. **BUG 1 inside-hours change**: opening hours `6:00 AM–11:00 PM`, change shift to
   `7 AM–1 PM` → assert reminder shown (bug), no-popup after fix.
3. **BUG 1 outside-hours change**: same hours, change shift to `5 AM–1 PM` → reminder
   shown before AND after (correct case; guards against over-suppression).
4. **BUG 2 format**: dropdown option for `06:00:00–12:00:00` → assert label contains
   `06:00:00` (bug); after fix contains `6:00 AM – 12:00 PM` and no `:00:00`.
5. **BUG 3 styling**: open dropdown → assert menu surface not white / square corners
   (bug); after fix white + radius > 0.
6. **BUG 4 list**: seed non-empty join list → assert zero cards rendered while badge
   shows count (bug); after fix card count == list length.
7. **BUG 4 isolation**: inject a failing seat-change fetch with a healthy join fetch →
   assert joins still render after fix (all-blank on unfixed code).
8. **BUG 4 routing**: tap a `shift_change_request` notification → assert lands on
   dashboard (bug); after fix lands on Requests sub-tab.

**Expected Counterexamples**:
- Reminder appears on unchanged/inside-hours saves.
- Option label contains `HH:mm:ss`.
- Dropdown menu is non-white / square.
- Request lists render 0 items despite a positive count; a single embed failure
  blanks all lists.
- Request notification lands on the dashboard, not the Requests sub-tab.

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed
function produces the expected behavior.

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition(input) DO
  result := fixedFunction(input)
  ASSERT expectedBehavior(result)
END FOR
```
Concretely:
- BUG 1: `FOR ALL saves WHERE (no timing change) OR (all changed timings within hours)
  → ASSERT popupShown == false`; and outside-hours change → `ASSERT popupShown == true`.
- BUG 2: `FOR ALL shifts WITH valid times → ASSERT isTwelveHour(label) AND NOT hasSeconds(label)`.
- BUG 3: `FOR ALL renders → ASSERT background == white AND cornerRadius > 0`.
- BUG 4: `FOR ALL types WITH pending>0 AND fetch OK → ASSERT renderedCards == pending`;
  `FOR ALL request-notification taps → ASSERT destination == RequestsSubTab`.

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed
function produces the same result as the original function.

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT originalFunction(input) = fixedFunction(input)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation because
it generates many inputs across the domain and catches edge cases manual tests miss.
For the pure helpers (opening-hours parse/compare, label formatter,
`isRequestNotification`) generate random valid times/strings/types and assert
invariants. For screen behavior, use widget tests with stubbed data.

**Test Plan**: Observe behavior on UNFIXED code first for the non-bug inputs, then
write tests that assert the fix keeps them identical.

**Test Cases**:
1. **BUG 1 persistence**: observe that a save archives/updates/inserts shifts,
   replicates seats, saves payment settings, and shows the success snackbar; assert
   unchanged after fix (Req 3.1, 3.2).
2. **BUG 2/3 send flow**: observe the shift-list filtering (other, non-archived
   shifts), reason field, insert into `shift_change_requests`, owner notification and
   success message; assert unchanged after fix (Req 3.3, 3.4).
3. **BUG 4 counts + approve/reject**: observe correct per-type counts and the
   approve/reject/audit flows; assert unchanged after fix (Req 3.5, 3.6).
4. **BUG 4 non-request routing**: observe `payment_submitted`, `check_in`,
   `daily_summary` etc. route to the dashboard; assert unchanged after fix (Req 3.7).
5. **Theme**: assert warm-orange `#E65C00` M3 palette unchanged across the touched
   widgets (Req 3.8).

### Documented Tradeoffs (free-text opening-hours parsing — BUG 1)

`libraries.opening_hours` is free text, so parsing is best-effort:
- **"All day" forms** (`24 hours`, `24/7`, `open 24`, `all day`) → treated as always
  in-hours → never prompt.
- **Parseable ranges** (two time tokens, 12h or 24h, en/em dash or `to`) → first token
  = open, last = close; midnight-crossing handled by +24h normalization.
- **Unparseable/blank** → fall back to prompting whenever a timing changed. Rationale:
  the golden "no dishonest UI" rule favors a false-positive reminder (a minor
  annoyance) over a false-negative (public hours silently drift out of sync). This
  fallback is explicitly asserted in tests so the behavior is intentional, not
  accidental.

### Unit Tests

- Opening-hours parser: 12h, 24h, `to`/dash separators, `24 hours`/`24/7`, blank,
  garbage.
- `_timingWithin`: inside, boundary-equal, before-open, after-close, midnight-cross.
- Label formatter reuse: seconds stripped, AM/PM correct, missing-time collapse.
- `isRequestNotification`: request vs non-request types.

### Property-Based Tests

- Generate random `[start,end]` and a random parsed range → the reminder decision
  equals `changed AND NOT within` (for parseable ranges).
- Generate random `HH:mm:ss` pairs → formatted label is 12-hour and seconds-free.
- Generate random request lists → rendered card count equals list length (fetch OK).
- Generate random notification types → request types route to Requests, others to
  their existing destinations (preservation).

### Integration Tests

- Full save flow in `shift_management`: change inside-hours vs outside-hours vs
  no-change → correct popup / no-popup, persistence intact.
- Full member shift-change flow: open sheet → formatted, white/rounded dropdown →
  send request → success + owner notified.
- Full admin flow: tap request notification → lands on Reservations → Requests →
  pending cards render → approve/reject works; tap non-request notification → lands on
  dashboard.
