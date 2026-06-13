# SILENCE — From-Scratch Setup + Full App Test Checklist

> You cleared the app **data** (user rows + uploaded files) but kept the tables, RLS, functions and
> storage buckets — so there is **nothing to rebuild**. **Part A** is a quick verify; **Part B is the
> full app test checklist** to walk through one-by-one from a clean (empty) state, and **Part C** lists
> this week's fixes to confirm. Tick boxes as you go; log issues in the table at the bottom.
> (Supersedes `TESTING_CHECKLIST.md`.)

---

# PART A — You only cleared DATA → verify (NO rebuild)

You deleted the *rows* (app user data) and the uploaded *files*, but kept the tables, RLS, functions and
buckets. **Do NOT re-run `supabase_schema.sql`** — the `42710 "trigger ... already exists"` error you saw
is EXPECTED and confirms your structure is intact. Just confirm a few things, then test on empty tables.

### A1. Confirm the structure is intact (SQL Editor)
- [ ] `select count(*) from information_schema.tables where table_schema='public';` → ~30 tables.
- [ ] `select id, public from storage.buckets;` → `silence_assets` (public=`true`) **and**
      `silence_private` (public=`false`) both present.
  - **Only if a bucket is missing:** run `silence_app/migrations/2026-06-12_storage_buckets_setup.sql`
    (idempotent — safe even if the buckets already exist; it just re-asserts the policies).
- [ ] (Optional) the server-tier RPC isn't used yet — you can run
      `silence_app/migrations/2026-06-12_rpc_find_user_by_contact.sql` now or later; skip if unsure.

### A2. App config & build
- [ ] `lib/core/supabase_config.dart` URL + anon key still match your project (unchanged if you only
      cleared data).
- [ ] `flutter pub get` → `flutter analyze` (only the known baseline infos) → launch.
- [ ] Device: **Android emulator/phone** for camera / crop / permissions / location / QR; the
      **Windows** build is fine for everything else (gallery upload works; camera shows a friendly
      message by design).

> If you also cleared the **Auth** users, your old logins won't work — sign up fresh accounts (the first
> one becomes your Admin in B1).
>
> ⚠️ **Mocked/disabled — do NOT log as bugs:** Razorpay subscription (mock plans), email/phone OTP
> (disabled), FCM push (pending).

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

## Reminder: you only cleared DATA — nothing to rebuild
- **Do NOT re-run `supabase_schema.sql`** — your tables / RLS / triggers are intact (that's exactly why
  it said "already exists"). It IS now safe to re-run if you ever truly drop tables, but you don't need
  to here.
- Storage buckets/policies persist; run `migrations/2026-06-12_storage_buckets_setup.sql` **only if a
  bucket is missing** (it's idempotent).
- `migrations/2026-06-12_rpc_find_user_by_contact.sql` is optional (not used yet).
