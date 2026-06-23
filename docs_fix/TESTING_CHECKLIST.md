# SILENCE — Full Feature Testing Checklist

> Generated 2026-06-12. Tick each box as you verify. Test **Admin** and **Member** as two separate
> accounts. Items are grouped by role → area. `[exp]` = expected result.

---

## 0. Pre-flight (DO THIS FIRST — several tests fail without it)

- [ ] **Apply both RLS migrations** in the Supabase SQL editor (each is additive/idempotent/safe):
  - [ ] `silence_app/migrations/2026-06-12_payments_admin_insert_rls.sql` → add-member completes, **seat stays occupied**, Payments populate.
  - [ ] `silence_app/migrations/2026-06-12_users_owner_update_rls.sql` → member **photos + ID docs** persist, member **profile edits** save.
- [ ] **Pick the right device.** Camera, image-crop and runtime permissions are **mobile-only** → test on an **Android device/emulator** for full coverage. On the **Windows** build, gallery-based upload works but "Take Photo" only shows a friendly message (by design).
- [ ] **Know what is mocked / disabled** (do NOT log these as bugs):
  - Razorpay subscription = **mock plans** ("free during beta"); email/phone **OTP = disabled**; **FCM push = foundation shipped (web-verified); Android/iOS device test pending**; members-tab **bulk Announce = stubbed** snackbar. *(Bulk member CSV Export now works via the shared engine.)*

### Smoke test of THIS session's fixes
- [ ] Add a member with a **photo + 1 ID proof** → open their profile: avatar shows, **ID Documents render** (not "No documents uploaded"). Card in Members list also shows the avatar.
- [ ] That member's **assigned seat shows occupied** in Layout (same shift), not vacant.
- [ ] Open a member → **edit a detail / save private note** → it persists after reload.
- [ ] **Payments** tab shows the row created at add-time.
- [ ] **Windows desktop:** Add-member → tap **Gallery** = file dialog opens & uploads; tap **Camera** = friendly message, **no force-close**.

---

## 1. Auth & Onboarding

- [ ] Role selection screen → Admin vs Member routes correctly.
- [ ] Sign up (new email) → account created, lands in onboarding.
- [ ] Log in (existing) / log out / re-login.
- [ ] Wrong password / unknown email → **friendly error**, no raw exception.
- [ ] Admin profile completion (name, phone, gender, DOB, address, photo) → gates member-add until complete.
- [ ] Member profile completion.
- [ ] Account deletion request (Admin & Member) → **type-DELETE** confirm → sets pending-deletion flag, red banner on member home, check-in disabled. (No real purge — flag only.)

## 2. Admin — Library Setup

- [ ] Create a library (setup stages) → appears in Reservations.
- [ ] Branding / logo upload `[exp]` logo renders.
- [ ] Shifts: create, edit timings, archive `[exp]` archived shift drops out of pickers.
- [ ] Manage Layout: create floor → section → seats `[exp]` seats appear in grid.
- [ ] Payment Methods: set UPI ID `[exp]` saved & shown as configured (no JSONB overwrite of social links).
- [ ] Amenities / Add-ons: create add-on, set **Monthly vs One-time** price type + 1/3/6-month prices `[exp]` only configured durations show as pills; no "Total Inventory" box.
- [ ] Referral Rewards config (Operations) `[exp]` "manual crediting for now" honest copy.

## 3. Admin — Reservations → Layout sub-tab

- [ ] Floor + Shift selectors switch the grid; shift timings show.
- [ ] Overview cards (Floors / Sections / Total / Available) correct.
- [ ] Filters: All / Vacant / Occupied / Expiring / Hold / Maintenance.
- [ ] Tap **vacant** seat → **Assign Member** picker (seatless members in that shift) → occupies + notifies + audits.
- [ ] Tap **occupied** seat → View details / Hold / **Reassign** (to vacant seat same shift) / Renew / Manual check-in / Remove-from-seat.
- [ ] Seat ↔ membership stays in sync (no "assigned but vacant"); occupancy self-heals on reload.
- [ ] Reserve / Maintenance / Delete seat.

## 4. Admin — Reservations → Members sub-tab

- [ ] Member list loads (pagination on scroll); cached on reopen.
- [ ] Search by name/phone; Floor/Shift filters; sort options.
- [ ] Chip filters: All / Active / Pending / Expired / Hold / Trial / Pending Drafts.
- [ ] Tap card → opens full **member profile**; returns refresh the list.
- [ ] 3-dot (top-right): Renew · Hold/Resume · Transfer (hidden if 1 library) · Remove → each does real DB write + member notify + audit.
- [ ] Drafts show with DRAFT badge; Continue resumes wizard; Delete removes draft.

## 5. Admin — Add Member Wizard

- [ ] (Multi-library) library selection step shows; (single) auto-skips.
- [ ] Mode: New vs Existing.
- [ ] Step 1 personal: validation; **photo upload**; **≥1 ID proof required**; autofill on existing phone/email.
- [ ] Step 2 plan: shift select, plan type, price computed, discount, dates.
- [ ] Step 3 seat: only seats in chosen shift; **allot required**.
- [ ] Step 4 payment (new mode): method, paid vs request.
- [ ] Step 5 review → **Confirm** → "Member added", list refreshes, draft deleted.
- [ ] **Dup guard:** existing active/pending member in same library → blocked with dialog.
- [ ] **Failure path:** if a step fails, wizard stays open + friendly error + **no ghost member / no orphan seat** (rollback).
- [ ] Save Draft / exit prompt / resume.

## 6. Admin — Reservations → Requests & Archive

- [ ] Join requests: approve `[exp]` membership+seat+payment created, member notified; reject `[exp]` notified.
- [ ] Seat-change requests: approve / reject.
- [ ] Archive: exited members listed, read-only.

## 7. Admin — Member Detail screen

- [ ] Header: photo, seat/shift/plan/expiry chips.
- [ ] Overview: contact info, **ID documents** (signed URLs), membership, attendance & payment summaries, referral.
- [ ] Attendance tab: **date-wise analytics** (range picker, default this month, per-day check-in/out/study-time) — no freeze.
- [ ] Payments tab: rows render (after migration); confirm/reject pending payment → member notified.
- [ ] Activity tab: timeline (no freeze).
- [ ] **Export** (header): Attendance/Payments + date range → CSV & PDF.
- [ ] Hold/Resume, Transfer, Renew actions.

## 8. Admin — Attendance / QR Scanner

- [ ] Scan member QR → check-in; scan again → checkout (cooldown currently 0).
- [ ] Multi-session same day allowed.
- [ ] Closure/holiday gate blocks check-in on a closed day (range-aware).
- [ ] Manual check-in from Layout.

## 9. Admin — Home / Analytics / Holidays / Queries / Notifications

- [ ] Home quick actions; "Today is a holiday" banner when applicable.
- [ ] Analytics: dashboard stats, charts, expenses add (categories = lowercase canonical), "N holidays in <month>" card.
- [ ] Holidays & Closures: add single + range, notify members, remove; honest states.
- [ ] Queries: view member query → **reply** → member notified + status replied.
- [ ] Notification center: real list + unread badge.
- [ ] Subscription & Billing entry → mock plans (free during beta). *(mocked)*

## 10. Member — Home

- [ ] Library membership card (name, IST 12h shift timing, joining date, Renew + ⋮).
- [ ] Expiry days-left correct (no "0 days left" bug); expired state honest.
- [ ] Streak card = **Sun→Sat** week, today highlighted, details row (this week N/7, best, total).
- [ ] Session cards: running + previous-below, multi-session, Today's/Yesterday's labels.
- [ ] Recent Activities: IST times, includes join/renewal events; scrollable.
- [ ] Quick actions: Contact Admin · Refer & Earn (copy/share real code) · Renew · Find Library.
- [ ] Bell → notifications + unread badge.
- [ ] Offline: kill network → cached card renders (forced not-checked-in) + tap-to-retry banner.
- [ ] "Library closed today" card disables check-in/FAB on a holiday.

## 11. Member — Attendance / Membership / Payments

- [ ] FAB → QR scanner → check-in/out.
- [ ] History tab.
- [ ] Join with code (if entry point used).
- [ ] Renewal: **real UPI deep-link** (`upi://pay`) opens UPI app → pay externally → **"I have paid"** → admin confirms loop. *(out-of-app by design)*
- [ ] Early-resume **request** (members can't self-hold).

## 12. Member — Other

- [ ] Leaderboard / streaks / badges render from data.
- [ ] Explore / Find Library; submit a suggestion `[exp]` honest success or honest error (no fake "submitted ✓").
- [ ] Reviews: submit/update own; read others.
- [ ] Contact Admin: submit query (library picker) → appears in My Queries; admin reply shows **inline**.
- [ ] Profile: edit (photo upload), privacy/security, notification prefs, help/support, referral, account deletion.

## 13. Cross-cutting (watch during every test)

- [ ] **Exports & Reports (2026-06-23 overhaul)** — test on **web (Chrome) AND a mobile build**:
  - [ ] Admin Profile → **Exports & Reports**: top has NO preset bar; tapping **CSV/PDF** on a report first asks the **period** (Today/Week/Month/Custom) then shares the file. **CSV must NOT crash** ("_Namespace" is fixed).
  - [ ] Export Center → **Attendance Log** card has **Date-wise / Member-wise** buttons → opens the preview screen.
  - [ ] Analytics → **Attendance** tab → **Preview & Export**: Date-wise (date/range filter shows every member's Name/Seat/In/Out/Duration/Overtime); Member-wise (month + **Shift/Floor/Category facet filters** + Members checklist, default **All**) → grouped per member.
  - [ ] Analytics → **Revenue** tab → report buttons open a **date-filtered preview** with **working** CSV **and** PDF (no dead buttons).
  - [ ] **PDF look**: orange letterhead band with a **visible white logo** (not blended), no big blank strip above it, footer black-name-with-tag logo, **₹ amounts render** (not boxes), times in **IST**, totals rows present. Members Roster has a **Joined** column.
  - [ ] **CSV opens in Excel/Sheets**: header on row 1, amounts are plain numbers, `=SUM()` works, dates sortable.
  - [ ] Member: History → Export (CSV/PDF) and Analytics → "Export My Attendance CSV" both work and show Shift/Overtime/Seat.

## 13b. General cross-cutting (watch during every test)

- [ ] **No dishonest UI** — never shows success/"paid"/"notified"/"uploaded" for something that didn't happen.
- [ ] Errors show **friendlyError** copy, never raw `$e`.
- [ ] Loading = skeletons/spinners; empty states are clear; offline states honest.
- [ ] Times shown in **IST**; dates correct.
- [ ] Orange status/top-bar consistency across screens.
- [ ] Duplicate-prevention (double-tap submit / approve) doesn't double-write.

---

## Bug-log table (fill as you find issues)

| # | Screen / step | What happened | Expected | Device | Migration applied? |
|---|---------------|---------------|----------|--------|--------------------|
|   |               |               |          |        |                    |
