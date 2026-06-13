# SILENCE — From-Scratch Setup + Full App Test Checklist

> You deleted the Supabase DB **and** storage. Nothing works until the backend is rebuilt, so this doc
> is two parts: **Part A — rebuild the backend** (do in order), then **Part B — test the whole app**
> from a clean slate. Tick boxes as you go; log issues in the table at the bottom.
> (Supersedes `TESTING_CHECKLIST.md` for the wiped-DB scenario.)

---

# PART A — Rebuild the backend (in this exact order)

### A1. Recreate the database schema
- [ ] Open Supabase → SQL Editor → paste & run **`silence_app/supabase_schema.sql`** (whole file).
  - This creates ALL tables + RLS + triggers, and **already includes** every recent policy fix
    (Phase C reconciliation, payments admin-insert, users owner-update, the hardened
    `auth.uid() IS NOT NULL` insert policies). You do **NOT** run those migration files separately.
  - **Safe to re-run:** the file now clears existing policies/triggers first, so if a previous/partial
    run left objects behind (e.g. error `42710 "trigger ... already exists"`), just run it again.
  - `[exp]` "Success. No rows returned." If it errors, paste me the error.

### A2. Add the server-tier RPC (not folded into the schema)
- [ ] Run **`silence_app/migrations/2026-06-12_rpc_find_user_by_contact.sql`**.
  - `[exp]` Success. (It's only *used* after the client is wired to it — currently optional, but
    harmless to create now.)

### A3. Recreate storage (buckets + policies)
- [ ] Run **`silence_app/migrations/2026-06-12_storage_buckets_setup.sql`**.
  - Creates `silence_assets` (public) + `silence_private` (private) + functional policies.
  - `[exp]` Success. Then Storage tab shows both buckets.

### A4. Verify the backend (quick SQL checks)
- [ ] `select count(*) from information_schema.tables where table_schema='public';` → ~30 tables.
- [ ] `select id, public from storage.buckets;` → `silence_assets=true`, `silence_private=false`.
- [ ] In Auth → confirm there are **no users** yet (you'll create them by signing up).

### A5. Point the app at the project & build
- [ ] Confirm `lib/core/supabase_config.dart` URL + anon key match THIS project. **If you recreated the
      project (new ref)**, update both, or the app can't connect.
- [ ] `flutter pub get` → `flutter analyze` (expect only the known baseline infos) → launch.
- [ ] Device choice: use an **Android emulator/phone** for camera/crop/permissions/location/QR. The
      **Windows** build is fine for everything else (gallery upload works; camera shows a friendly
      message by design).

> ⚠️ **Mocked/disabled — do NOT log as bugs:** Razorpay subscription (mock plans), email/phone OTP
> (disabled), FCM push (pending), Members-tab bulk Announce/Export is real now but other "coming soon"
> labels are intentional.

---

# PART B — Full app test (clean-slate order)

## B1. Auth & the first admin
- [ ] Sign up a new account (email+password) → lands in onboarding.
- [ ] Pick role **Admin**.
- [ ] Log out → log back in. Wrong password → **friendly error**, no raw exception.

## B2. Admin profile & first library
- [ ] Complete admin profile: name, phone, gender, DOB, address, **photo upload** → photo shows.
- [ ] Create a library (setup stages complete) → it appears under Reservations.
- [ ] Branding: upload logo/cover → renders.

## B3. Library setup (build the structure members will use)
- [ ] Shifts: create 2+ (e.g. Morning, Full Day) with timings; edit; archive one → drops from pickers.
- [ ] Manage Layout: create floor → section → several seats → appear in the grid.
- [ ] Payment Methods: set the admin UPI ID → saved, shown as configured.
- [ ] Amenities/Add-ons: create one Monthly + one One-time add-on; set 1/3/6-month prices → only
      configured durations show as pills.
- [ ] Referral Rewards config → honest "manual crediting for now" copy.

## B4. Add members — verify this week's fixes ⭐
- [ ] Add a member: choose mode → fill details → **upload profile photo + 1 ID proof** → pick shift →
      **allot a seat** → payment → review → Confirm.
  - [ ] `[exp]` "Member added", list refreshes, no error.
  - [ ] Open the member's profile → **avatar shows** AND **ID Documents render** (not "No documents
        uploaded"). *(verifies users owner-update RLS)*
  - [ ] **Members list card shows the avatar.**
  - [ ] Layout (same shift) → the allotted **seat shows Occupied**, not vacant. *(verifies payments
        admin-insert RLS — no rollback)*
  - [ ] Member detail → **Payments tab** has the row created at add-time.
- [ ] Dup guard: try adding the same phone again → "Active Membership Found" dialog, blocked.
- [ ] Add-member failure stays open with a friendly error and leaves **no ghost member / no orphan seat**.
- [ ] Save Draft mid-wizard → exit → resume from Members → Pending Drafts.
- [ ] **Windows desktop:** Camera → friendly message (no force-close); Gallery → file dialog uploads. ⭐

## B5. Reservations (admin)
- [ ] **Layout sub-tab:** floor/shift selectors; overview counts; filters (Vacant/Occupied/Expiring/
      Hold/Maintenance); tap a vacant seat → **Assign Member**; tap an occupied seat → Reassign /
      Hold / Renew / Manual check-in / Remove-from-seat; seat↔membership stays in sync.
- [ ] **Members sub-tab:** search by name/phone; floor/shift filters; sort; tap card → profile;
      3-dot → Renew / Hold-Resume / Transfer(hidden if 1 library) / Remove; **bulk select → Announce
      (real notification) + Export (real CSV)**. ⭐
- [ ] **Requests sub-tab:** approve/reject a join request; approve/reject a seat-change.
- [ ] **Archive sub-tab:** exited members appear, read-only.
- [ ] **Member detail:** Overview / **Attendance tab (date-wise analytics, no freeze)** / Payments /
      Activity; header **Export** → CSV & PDF; Hold/Resume; Transfer; Renew.

## B6. Attendance / QR
- [ ] Scan a member QR → check-in; scan again → checkout; multi-session same day allowed.
- [ ] Mark today a holiday (Holidays screen) → check-in is blocked + "closed today" banners show.

## B7. Admin home / analytics / queries / notifications / subscription
- [ ] Home quick actions; "Today is a holiday" banner when applicable.
- [ ] Analytics: stats + charts; add an expense (category saves); "N holidays in <month>" card.
- [ ] Holidays & Closures: add single + range, notify, remove.
- [ ] Queries: a member's query → **reply** → member notified + status `replied`.
- [ ] Notification center: real list + unread badge.
- [ ] Subscription & Billing → mock plans (free during beta). *(mocked)*

## B8. Member account (second account)
- [ ] Sign up / log in as a **Member** (or use the member the admin added). Complete member profile.
- [ ] Home: membership card (IST 12h shift time, joining date, Renew + ⋮); expiry days-left correct;
      **streak card = Sun→Sat week**; session cards; Recent Activities (IST, join/renewal events).
- [ ] Quick actions: Contact Admin · Refer & Earn (copy/share real code) · Renew · Find Library.
- [ ] Bell → notifications + unread badge.
- [ ] Offline: kill network → cached card renders (forced not-checked-in) + tap-to-retry banner.

## B9. Member membership & payments
- [ ] FAB → QR scanner → check-in/out; History tab.
- [ ] Renewal: **real UPI deep-link** opens a UPI app → pay externally → **"I have paid"** → admin
      confirms (loop closes). *(out-of-app by design)*
- [ ] Early-resume **request** (members can't self-hold).

## B10. Member other
- [ ] Leaderboard / streaks / badges render.
- [ ] **Find Library / Explore: location prompt works — on iOS this must NOT crash** (verifies the
      Info.plist location fix). ⭐ Submit a suggestion → honest success/error (no fake ✓).
- [ ] Reviews: submit/update own; read others.
- [ ] Contact Admin: submit a query (library picker) → appears in My Queries; admin reply shows inline.
- [ ] Profile: edit (**photo upload**), privacy/security, notification prefs, help/support (attach an
      image), referral, account deletion (type-DELETE → pending-deletion banner, check-in disabled).

## B11. Cross-cutting (watch throughout)
- [ ] **No dishonest UI** — never shows success/"paid"/"notified"/"uploaded" for something that didn't
      happen.
- [ ] Errors = friendly copy, never raw `$e`. Loading = skeletons. Times in **IST**.
- [ ] **Notifications still arrive** after the hardened insert policy (hold/remove/announce a member).
- [ ] Double-tap submit/approve doesn't double-write.

---

# PART C — This week's fixes, at a glance (must all pass)
- [ ] Member **photo + ID docs persist** and render (users owner-update RLS).
- [ ] Newly added member's **seat shows occupied**; **Payments** populate (payments admin-insert RLS).
- [ ] **Editing a member's profile saves** (same RLS).
- [ ] **Windows**: all 8 image-upload screens — gallery works, camera = friendly message, **no crash**.
- [ ] **iOS**: find-library / location screens don't crash.
- [ ] Members-tab **bulk Announce = real notification**, **Export = real CSV**.
- [ ] Honest states across member screens (no fake "submitted ✓").

---

# PART D — Bug log (fill as you find issues)

| # | Screen / step | What happened | Expected | Device | Notes |
|---|---------------|---------------|----------|--------|-------|
|   |               |               |          |        |       |

---

## Reminder: migrations to run for a from-scratch DB
1. `silence_app/supabase_schema.sql`  *(all tables + RLS + folded fixes)*
2. `silence_app/migrations/2026-06-12_rpc_find_user_by_contact.sql`  *(server-tier RPC #1)*
3. `silence_app/migrations/2026-06-12_storage_buckets_setup.sql`  *(buckets + policies)*

You do **not** need to run the individual payments / users-owner-update / hardened-insert / Phase-C
migration files — they're already inside `supabase_schema.sql`.
