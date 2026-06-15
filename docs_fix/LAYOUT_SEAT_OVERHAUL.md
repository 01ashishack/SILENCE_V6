# Admin Layout / Seat Management — analysis & plan

> Created 2026-06-15 from user-reported issues + screenshots. The whole seat
> subsystem (lib/screens/reservations/layout_sub_tab.dart, ~3700 lines) needs a
> careful pass because **most issues share one root cause: the per-shift seat
> data model.**

## Root cause — the data model
`seats` table: `shift_id UUID NOT NULL`, `UNIQUE (library_id, seat_label, shift_id)`.
So a physical seat "B-11" is **one row per shift**. Status / occupied_by_member are
per (seat, shift). This is correct for booking (different members per shift) BUT the
layout UI treats each row as a separate seat → duplicates, per-shift delete, etc.

**Design principle:** treat a *physical seat* = all rows sharing `seat_label` (in a
library/floor/section). The UI shows ONE tile per physical seat; per-shift status is
an overlay. A specific-shift view still shows that shift's row.

---

## Issues, root cause, and plan (analyst + user view)

### 1. "All Shifts" shows the same seat twice (e.g. B-11 vacant + B-11 occupied)
- **Cause:** `_fetchSeatsAndSections` (≈247) drops the `shift_id` filter when shift=='all'
  → returns every shift's row; `_buildSeatGrid` renders each → duplicates.
- **Plan:** when shift=='all', **group rows by seat_label** and render ONE tile per
  physical seat. Aggregate status: occupied-in-any > hold > maintenance > vacant.
  Keep the per-shift rows on the tile for the detail sheet (#7). ✅ Batch 2.

### 2. No way to un-reserve / un-maintenance a seat
- **Cause:** `_showSeatActionsBottomSheet` else-branch only offers Reserve/Maintenance;
  a hold/maintenance seat has no "make available". `_markSeatStatus` supports any status.
- **Plan:** add **"Mark as Available"** (→ status 'vacant') when status is hold/maintenance;
  header label shows Reserved / Under Maintenance instead of "Vacant Seat". ✅ Batch 1.

### 3. Delete seat should remove it from ALL shifts
- **Cause:** `_deleteSeat` (910) deletes by `id` → only that shift's row.
- **Plan:** delete by `library_id` + `seat_label` (all shifts). Confirm copy clearly.
  Also mirror in the tree-sheet `_deleteSeat` (≈3234). ✅ Batch 1.

### 4. Removed member can't be re-assigned a seat
- **Cause:** after `_releaseSeat`, the member has no seat. The "Assign Member" picker
  (`_assignMemberToSeat`, 641) may filter to a shift and miss them; the member card /
  3-dots has no "Assign Seat" action.
- **Plan:** (a) `_assignMemberToSeat` lists **all seatless active/trial members of the
  selected shift** (members whose `memberships.seat_id` is null). (b) Add **"Assign Seat"**
  to the member 3-dots (members_sub_tab / member_detail) shown **only when the member has
  no seat** → opens a seat picker for their shift. ✅ Batch 3.

### 5. Time-overlap: a full-day booking should block overlapping shifts
- **Cause:** seats/availability are per-shift with no time-overlap check. A member booked
  in a full-day shift still appears bookable in a shift whose hours fall inside it.
- **Plan:** when assigning/among "available" seats, compute shift time ranges; a physical
  seat occupied in shift X is **unavailable** in any shift whose [start,end] overlaps X.
  Needs shift start/end times (shifts table) + an overlap helper. ✅ Batch 3.

### 6. "All Shifts" filter: one tile per seat + a marker that it's booked elsewhere
- Same fix as #1. The single tile gets a small **badge/dot** (e.g. corner colour) meaning
  "booked in another shift" so the admin knows it isn't fully free. ✅ Batch 2.

### 7. Tapping a seat should show its status (esp. per-shift)
- **Cause:** the action sheet shows one status. In "All Shifts" it should show the
  **per-shift breakdown** (which shift occupied / vacant / reserved).
- **Plan:** seat detail sheet lists each shift's status for that physical seat. ✅ Batch 2.

---

## Edge cases to honour
- Deleting a seat that's occupied in some shift → warn; null the membership.seat_id (FK
  is ON DELETE SET NULL) so no dangling ref; member stays (just seatless → #4).
- Assign/overlap must respect membership shift, not just the layout filter.
- Reconcile-from-memberships (289+) must still run after dedupe (don't lose self-heal).
- "All Shifts" actions (reserve/maintenance/delete) act on the **physical seat (all
  shifts)**; specific-shift view acts on that shift's row only.
- Don't break the existing single-shift view (it's correct today).

## Implementation order
- **Batch 1 (this pass, low risk):** #2 Mark-as-Available undo · #3 delete-all-shifts.
- **Batch 2 ✅ DONE:** #1/#6 All-Shifts dedupe + cross-shift marker · #7 per-shift status sheet.
- **Batch 3 ✅ DONE:** #4 re-assign seatless member (picker + 3-dots) · #5 time-overlap availability.

## Batch 3 — what shipped (2026-06-15)
`flutter analyze`: clean (0 issues, the 3 touched items + project-wide).
- **New `lib/utils/shift_overlap.dart`** (shared, fat-client style): `shiftRangesOverlap`
  (handles overnight ranges; fail-safe = treat unparseable times as a clash), `overlappingShiftIds`,
  and `blockedSeatLabels(client, …)` — given candidate seat labels in a target shift, returns the
  labels whose physical chair is occupied/held in a TIME-OVERLAPPING shift (checks both seats.status
  and live memberships, so a stale row can't leak a taken seat). Best-effort: on query error it
  returns empty (never blocks assignment over a transient failure — there's no DB seat-lock anyway).
- **#5 layout_sub_tab:** `_reassignSeat` now filters its vacant-seat picker through
  `blockedSeatLabels`; `_assignMemberToSeat` guards the tapped seat up-front (honest "occupied in an
  overlapping shift" message) so one chair can't be double-booked across overlapping shifts.
- **#4b members_sub_tab:** the member 3-dots sheet shows **"Assign Seat"** ONLY when the member is
  live (active/trial) and has no `seat_id`. New `_assignSeatToMember` lists vacant seats in the
  member's own shift (overlap-filtered), re-validates vacancy on pick, then occupies the seat + sets
  `memberships.seat_id` + notifies the member + audits + refreshes the list. (#4a was already
  satisfied — `_assignMemberToSeat` already lists seatless members scoped to the shift.)
- **⚠️ Verification:** static analysis only — no on-device test of the overlap exclusion or the
  member-side assign picker yet. Overlap correctness depends on shifts carrying sane
  `start_time`/`end_time`; missing times fail safe (seat treated as blocked).

## Batch 2 — what shipped (2026-06-15)
All in `lib/screens/reservations/layout_sub_tab.dart`; `flutter analyze`: clean (0 issues,
file + project-wide).
- **`_collapsePhysicalSeats(rows)`** groups per-shift rows by `floor_id|section_id|seat_label`
  into ONE representative tile; aggregate status precedence occupied>hold>maintenance>vacant.
  Attaches `_shift_rows` (per-shift rows) + `_booked_elsewhere` (booked in some shift, free in
  another). Result sorted by `seat_label` for stable order.
- New field **`_displaySeats`** computed in `_fetchSeatsAndSections` setState:
  `_selectedShiftId == 'all' ? _collapsePhysicalSeats(seatsList) : seatsList`. Single-shift view
  is byte-for-byte unchanged. Reconcile-from-memberships still runs first (collapse consumes the
  already-reconciled rows). Grid + section/floor badge counts now read `_displaySeats`.
- **Cross-shift marker:** seat tile shows a small blue corner dot when `_booked_elsewhere`.
- **Per-shift status sheet (#7):** in All-Shifts, the seat sheet shows "Status by shift" — each
  shift's coloured dot + status (+ member name when occupied; tap an occupied shift → member
  profile). Per-shift mutations (reserve/assign/maintenance) are intentionally NOT offered on the
  collapsed tile (would silently touch one shift); an honest note directs the admin to pick a
  shift first. Delete Seat (all shifts) stays available. Helpers added: `_shiftLabel`,
  `_seatStatusColor`, `_seatStatusText`.
- **Not changed (out of Batch 2 scope):** overview "Total/Available" counts remain library-wide
  per-shift-row counts (a different scope from the floor grid; pre-existing, not newly dishonest).
- **⚠️ Verification:** static analysis only — no on-device test of the All-Shifts grid/sheet yet.
