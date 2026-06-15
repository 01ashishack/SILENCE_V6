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
  Keep the per-shift rows on the tile for the detail sheet (#7).

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
  no seat** → opens a seat picker for their shift. Batch 2.

### 5. Time-overlap: a full-day booking should block overlapping shifts
- **Cause:** seats/availability are per-shift with no time-overlap check. A member booked
  in a full-day shift still appears bookable in a shift whose hours fall inside it.
- **Plan:** when assigning/among "available" seats, compute shift time ranges; a physical
  seat occupied in shift X is **unavailable** in any shift whose [start,end] overlaps X.
  Needs shift start/end times (shifts table) + an overlap helper. Batch 2 (careful).

### 6. "All Shifts" filter: one tile per seat + a marker that it's booked elsewhere
- Same fix as #1. The single tile gets a small **badge/dot** (e.g. corner colour) meaning
  "booked in another shift" so the admin knows it isn't fully free. Batch 2.

### 7. Tapping a seat should show its status (esp. per-shift)
- **Cause:** the action sheet shows one status. In "All Shifts" it should show the
  **per-shift breakdown** (which shift occupied / vacant / reserved).
- **Plan:** seat detail sheet lists each shift's status for that physical seat. Batch 2.

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
- **Batch 2:** #1/#6 All-Shifts dedupe + cross-shift marker · #7 per-shift status sheet.
- **Batch 3:** #4 re-assign seatless member (picker + 3-dots) · #5 time-overlap availability.
