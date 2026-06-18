# Reservation / Attendance / Requests fixes — 2026-06-15

> Single commit: **`2a55f4d`** (HEAD, not pushed). `flutter analyze`: **0 issues** project-wide.
> Static-analysis verified only — **not device-tested**. Builds on the seat-overhaul plan in
> `LAYOUT_SEAT_OVERHAUL.md` (batches 1–3) plus a round of user-reported screenshot fixes.

## ✅ Migration APPLIED 2026-06-18 (gated several features — now live)
`silence_app/migrations/2026-06-15_join_requests_payment_status.sql`
- Adds `join_requests.payment_status` (`unverified` | `verified` | `rejected`, default `unverified`).
- Extends the `status` CHECK to allow `withdrawn`.
- Additive + idempotent; folded into canonical `supabase_schema.sql`.
- **Now applied:** Reject-Pay / Confirm-Pay, member Withdraw Application, and the rejected-request
  card all work (the DB CHECK accepts the new values).

## Seat layout (`lib/screens/reservations/layout_sub_tab.dart`)
- **All-Shifts dedupe** — one tile per physical seat (`_collapsePhysicalSeats`), aggregate status
  occupied>hold>maintenance>vacant, `_booked_elsewhere` corner marker.
- **Per-shift action sheet** — tapping a seat in All-Shifts shows a compact **day booking strip**
  (library open→close, booked=blue / free=green via `_buildDayBookingStrip`) + per-shift rows that
  each open that shift's normal action set. Full-day bookings show overlapping shifts as
  "Booked • via full-day booking" (`_effectivelyBooked`).
- **Time-overlap availability** — `lib/utils/shift_overlap.dart` (`shiftRangesOverlap`,
  `overlappingShiftIds`, `blockedSeatLabels`); assign/reassign pickers exclude a chair that's taken in
  a time-overlapping shift. Used by layout + members assign-seat.
- **Orphaned-shift filtering** — `_validShiftSeats` drops seat rows whose `shift_id` is not in
  `_shiftsList` (deleted shifts) so phantom "Shift" entries disappear. *(Note: `_totalSeatsCount`/
  `_availableSeatsCount` still count raw rows incl. orphans — optional DB cleanup pending.)*
- **Selector** — dropdown offers "All Floors/All Shifts" only when `items.length > 1`; default is
  "all" when >1 else the single item; trailing **"Shift"** stripped from names (`_displayShiftName`).
- **Occupied seats first** — `_getFilteredSeats` sorts occupied → hold → maintenance → vacant, then by
  seat label.
- **Seat-sheet scroll** — wrapped in `SingleChildScrollView` (fixes the bottom overflow).

## Manual attendance (`layout_sub_tab.dart`)
- **One smart toggle** `_manualAttendanceToggle` → `_doManualCheckIn` / `_doManualCheckOut` (open
  session → checkout, else check-in; no duplicate in/out).
- **Future-time bug fixed** — removed the +1-day rollover; checkout anchored to the check-in's local
  date with minute-granular compares.
- **Flagged** `session_type='manual'` on both; **notifies** the member (`_notifySeatMember`, type
  `attendance_manual`); admin-picked time via `showTimePicker`.

## "Manual" tag (`lib/utils/attendance_format.dart`)
- `attendanceTag(sessionType)` → `{label, isManual}` (manual/admin_edited → "Manual", normal → "Auto").
- Applied in: member detail session chip, member analytics chip, past-library chip, **CSV** (Session
  Type column), **PDF** (new "Type" column). Admin + member panels.

## Admin home Today's Attendance (`lib/screens/admin_home.dart`)
- Removed the shift filter chips (and the `_selectedShiftFilter` field).
- Circles show the **member profile photo** (`Image.network` + `_attendanceInitial` fallback) with a
  status ring; below shows **check-in/out time** instead of seat; whole strip on a **white card**,
  horizontal slider, newest first.
- **Separate In/Out entries** — each session emits a distinct "In" (at check-in) and, once checked
  out, a distinct "Out" (at check-out); the check-in tile no longer mutates. One In + one Out per
  member (latest each), sorted newest-event-first.

## Members / Requests
- **`members_sub_tab.dart`:** "Trial" filter → **"No Seat"** (active/trial with `seat_id` null);
  **Assign Seat** 3-dots action (overlap-filtered picker); **Renew** now opens `showAdminRenewSheet`
  (was routing to `/admin/member`).
- **`admin_renew_sheet.dart`** (new): admin direct renewal — plan pills (1/3/6mo at shift prices),
  cash/UPI, extends `end_date` from max(current, today), inserts a confirmed payment, notifies, audits.
- **`requests_sub_tab.dart`:** `_confirmPayment` persists `payment_status='verified'`; `_rejectPayment`
  sets `payment_status='rejected'` + notifies the member + **keeps the request pending** (no longer
  cancels the join); card reads persisted `payment_status`; hardcoded ₹1,500 replaced with a
  **computed amount** (`_requestAmounts` via `_computeApprovalAmount`).
- **`member_home.dart`:** rejected-request card (`_buildRejectedRequestCard` — reason + Apply again /
  Contact admin); **soft withdraw** (`status='withdrawn'`); **permanent QR FAB** that's
  **eligibility-gated** (`_scanIneligibleReason` / `_onScanFabPressed` — scans when active/trial/
  expiring or expired-with-allow, else a contextual warning snackbar).

## Open follow-ups
- ✅ 2026-06-15 migration applied (2026-06-18). Remaining: on-device smoke test of every flow above.
- Optional: delete orphaned `seats` rows at the DB level (shift_id not in `shifts`) so counts match.
- A full-screen story viewer for Today's Attendance (current "slide" = horizontal scroll).
