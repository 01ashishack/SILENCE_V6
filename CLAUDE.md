# CLAUDE.md — SILENCE Project Memory & Audit Handoff

> **Single source of truth a new session reads first.** Captures (a) the 16-phase audit (2026-06-08,
> evidence in `docs_audit/`) and (b) the **active remediation** since 2026-06-09 (3-phase UI/UX → Flow
> → Schema overhaul). Historical detail lives in `docs_fix/` + `docs_audit/`; this file is the index +
> current state. **Keep it under 40k chars** (trim oldest historical log when it grows).
>
> **Read order for a fresh session:**
> 1. **This file** (status + what's done + what's next).
> 2. **`docs_fix/UIUX_OVERHAUL_DECISIONS.md`** — product/UX decisions + golden rules. ⭐ OVERRIDES old spec.
> 3. **`docs_fix/IMPLEMENTATION_PLAN.md`** — 3-phase plan + full running build log (the detailed "what's done").
> 4. **`docs_fix/AUDIT_CHECKLIST.md`** — done/partial/pending vs the 16-phase audit. Fastest "what's left".
> 5. `docs_audit/AUDIT_PHASE_16.md` + the specific phase report — evidence behind a defect.

---

## 0. TL;DR — Status & Next Action

- **What this is:** SILENCE — Flutter + Supabase library / study-space management app for Indian
  Tier-2/3 cities (admins manage seats/members/attendance/payments/analytics; members track
  attendance, streaks, leaderboard, membership). **Single-tier "fat client"** — direct `.from(...)`
  writes; server tier (RC-1) is being introduced incrementally via Postgres `SECURITY DEFINER` RPCs +
  (now) the first Supabase Edge Function.
- **Mode: ACTIVE REMEDIATION.** Audit baseline was **~2.5/10** (22 C · 68 H · 63 M · 22 L). Executing a
  user-directed **3-phase overhaul: (A) UI/UX → (B) Flow/Functions → (C) Schema.**
- **⚠️ Source of truth = the EXISTING CODEBASE, not `silence_app/` spec.** Several decisions in
  `docs_fix/UIUX_OVERHAUL_DECISIONS.md` deliberately diverge from spec/audit.
- **Working rules:** refine warm-orange Material-3 (no redesign); UI consistency + color hierarchy;
  **no dishonest UI**; **ask before adding**; run `flutter analyze` after edits (0 new errors;
  pre-existing infos = baseline). **No live-DB access from agent** — schema changes are authored as
  `silence_app/migrations/*.sql` the USER applies. Commit/push only when asked; `Co-Authored-By` trailer.
- **Live DB project ref:** `kndeshxeerldamafweru` (`lib/core/supabase_config.dart`). Branch `main`,
  remote `origin` (github.com/01ashishack/SILENCE_V6).

### Session 2026-06-17 — Add-Member wizard fixes (verified by user on-device)
All in `lib/screens/admin/` (+ migrations). `flutter analyze` clean on touched files. Committed+pushed.
- **ID upload rework** (`add_member_step1.dart`): removed doc-type dropdown; single **"Upload ID"** =
  **Front (required)** + **Back (optional, no "optional" label)** square tiles; uploads to
  `silence_private` **immediately** with circular-progress overlay; `MemberData` gained
  `idProof1Url/idProof2Url`; validation requires Front; finalize reuses uploaded paths.
- **Add-Member "permission denied" — ROOT CAUSE (no DB change fix):** new-member `users` insert used
  `.insert(...).select('id')` → `INSERT ... RETURNING id`. The tenant-scoped SELECT policy
  (`Admins can view library members`, 2026-06-14) only lets an owner read a user who is ALREADY a
  member; a brand-new member has no membership yet → RETURNING rejected `42501`. **Fix:** generate id
  client-side (`uuid`), insert **without** `.select()` (`add_member_wizard.dart`). Added per-step
  `opLabel` + auth/tenant diagnostics in `_finalizeRegistration`.
- **"Could not save your changes" = `email NOT NULL`** (wizard treats email optional → NULL → 23502).
  Fix migration **`2026-06-17_users_email_nullable.sql`** (DROP NOT NULL, keep UNIQUE). Schema synced.
- **Block admin/owner contacts:** RPC **`2026-06-17_rpc_contact_in_use.sql`** (boolean, owner-only, no
  PII) + step1 `_blockIfContactReserved` → clears field + "Already Registered" dialog when an
  email/phone belongs to an admin/owner (members still autofilled via `find_user_by_contact`).
- **UI:** Gender + Preparing-For dropdowns white + curved; added **Teacher** to Preparing For.
- **Migrations APPLIED to live DB:** `users_email_nullable` + `rpc_contact_in_use`. (Earlier
  `2026-06-17_users_owner_insert_member_rls.sql` is redundant/harmless — real cause was RETURNING.)

### Session 2026-06-17 (b) — FCM push: foundation SHIPPED & web-verified end-to-end
- **Firebase project `silence-v6`**; `flutterfire configure` (android/ios/web/win/macOS) →
  `lib/firebase_options.dart`, `android/app/google-services.json`, gradle plugins.
- **App-side** (`lib/services/push_notification_service.dart`, wired in `main.dart`): permission, FCM
  token → **`device_tokens`** table (multi-device), refresh + sign-in re-save, background handler,
  tap/foreground stubs. Web uses VAPID key (`_webVapidKey`).
- **DB:** `silence_app/migrations/2026-06-17_device_tokens.sql` (token PK, user-scoped RLS) — APPLIED.
- **Send-side (first Edge Function!):** `supabase/functions/send-push/index.ts` — a **Database Webhook**
  on `notifications` INSERT calls it; it reads recipient `device_tokens` (service role) → **FCM HTTP v1**
  (service account = base64 secret `FIREBASE_SERVICE_ACCOUNT_B64`). Deployed `--no-verify-jwt`; webhook
  `send_push_on_notification` wired. **✅ Verified end-to-end on web.** All committed+pushed.
- **Pending FCM:** foreground heads-up banner (`flutter_local_notifications`), tap→navigation,
  Android/iOS device test (iOS needs Apple Developer + APNs key), **shared-secret header** to harden the
  `--no-verify-jwt` webhook→function call.
- **Subscription decision (2026-06-17):** **in-app Razorpay ruled out**; either store IAP OR
  website+Razorpay. See `docs_fix/UIUX_OVERHAUL_DECISIONS.md` + `SUBSCRIPTION_ARCHITECTURE.md`.

### Session 2026-06-18 — audit-fix batch (code-only, full project `flutter analyze` clean)
Worked through safe audit items (baseline `SILENCE_COMPLETE_AUDIT_REPORT.md`):
- **P7-01 (flagship) multi-shift seats** (`library_setup_stage2.dart`): setup now creates one seat row
  **per shift** (same label) — was only first shift → 0 seats in other shifts; load **dedupes by
  label**; delete-detection made **label-aware** so sibling shift-rows aren't wrongly deleted.
- **P12-03** guarded 3 `currentUser!` force-unwraps → null checks (admin_home trial, member_history
  receipt, join_flow proof upload).
- **P7-02** discount cap: `add_member_step4` loads `business_rules.max_discount` (%) and clamps the
  discount to base×max%/100 (+ helper + snackbar). *Client-side only; server cap needs Wave 1.*
- **P7-06** QR regeneration grace: scanner accepts current **or immediately-previous** version (no
  more instant-break of printed QRs). *Precise 7-day window needs a `qr_version_updated_at` column.*
- **P12-01** global error handler: `main()` wrapped in `runZonedGuarded` + `FlutterError.onError`.
- **P10-02 / R-01 (storage PII)**: payment proofs in **renewal** + **history-reupload** now upload to
  `silence_private` (+ signed URL) instead of the PUBLIC `silence_assets` bucket (join_flow already
  did). ID docs + payment proofs are now all private. *(Profile photos stay public by decision.)*
  ✅ **APPLIED (2026-06-18):** `silence_app/migrations/2026-06-14_storage_private_owner_scoping.sql`
  (owner-scopes who can READ silence_private). Follow-up: proof display uses 1h signed URLs (join
  pattern) — old proofs may need re-signing on display (affects join too).
> Still pending (need live DB / server tier / decisions): RLS column
> locks (P5-01/P6-06 — P6-02 role-escalation now closed via `change_my_role()`, apply+test pending),
> server tier RPCs (RC-1), cron automation (P7-04/09, referral credit),
> analytics precompute (P11), real payments (RC-2, deferred), OTP (disabled by decision).
> *(Storage PII off public bucket + owner-scoping migration (P10-01/02/03, DPDP) and account-deletion
> purge cron (P14-02) — migrations APPLIED 2026-06-18; recovery purge still needs a destructive test.)*

### Session 2026-06-18 (b) — Account deletion + 7-day recovery + owner approval (P14-02)
Full flow built; `flutter analyze` clean. **Migrations APPLIED + Edge Function deployed (2026-06-18); still TEST (destructive) on a throwaway account before relying on purge:**
- **Flow:** request delete → `scheduled_for_deletion=true, deletion_scheduled_at=now()+7d,
  deletion_recovery_status='none'` → dashboard **fully blocked** (`account_frozen_screen.dart`,
  routed from splash + admin_home + member_home guards) → user taps **Request Recovery**
  (`status='requested'`) → **app-owner** reviews in **`owner_recovery_console_screen.dart`** (gated to
  `SupabaseConfig.appOwnerUserId`; entry in admin profile Operations) → Approve (restore) / Deny →
  after 7d unapproved, **Edge Function `process-account-deletions`** (cron) purges everything.
- **App owner = a DB flag** `users.is_app_owner` (NOT a hardcoded uid). Designate your owner account:
  `UPDATE public.users SET is_app_owner = true WHERE email = 'you@example.com';` — the Recovery
  Console entry + owner RPCs gate on this flag. Migration: `2026-06-18_app_owner_flag.sql`.
- **CURRENT decision (2026-06-18): recovery approval = Supabase DASHBOARD SQL (Option B)**, NOT the
  in-app console — no owner account/flag needed yet. The in-app Owner Recovery Console + `is_app_owner`
  flag + `app_owner_flag.sql` are built but **dormant** (entry hidden since no account is flagged);
  enable later when a dedicated admin/owner account exists. Approve/deny meanwhile via:
  `UPDATE users SET scheduled_for_deletion=false, deletion_scheduled_at=NULL, deletion_recovery_status='approved' WHERE id='…';`
  (deny → `deletion_recovery_status='denied'`).
- **Migrations APPLIED to live DB (2026-06-18):** `2026-06-18_account_deletion_recovery.sql`
  (recovery_status col) + `2026-06-18_account_recovery_rpcs.sql` (RPCs + `purge_account`) +
  `2026-06-18_app_owner_flag.sql` (is_app_owner col + re-gates the owner RPCs on the flag — ran LAST).
- **Edge Function DEPLOYED (2026-06-18):** `process-account-deletions` deployed + cron scheduled.
- ⛔ Purge is destructive/irreversible — verify `purge_account` covers your FK tables + test on a
  throwaway account before relying on the cron. Self-cancel removed (recovery is owner-approved).
- Minor: descriptive "30-day" copy in member_about / privacy_policy not yet updated to 7-day.

### Session 2026-06-18 (h) — P11-01: precompute member_daily_stats
`2026-06-18_member_daily_stats_precompute.sql` — a `SECURITY DEFINER` trigger on `attendance`
(INSERT/UPDATE/DELETE) maintains the `member_daily_stats` rollup (present_flag + total_minutes) per
`(member, library, IST-day)` via `recompute_member_daily_stat()`, plus a one-time backfill. IST-day
bucketing (`AT TIME ZONE 'Asia/Kolkata'`) matches the app clock. **No Dart change** — the service's
existing `member_daily_stats` fast path now hits indexed rows instead of scanning all attendance
(also speeds up the `consistent` badge). Folded into canonical (backfill omitted). `flutter analyze`
n/a (SQL only). ⛔ apply migration; verify `select count(*) from member_daily_stats > 0` + a fresh
check-out updates the day row.
- **P11-02 (badge N+1) — remaining:** `early_bird`/`night_owl` (need check-in hour) and `top_of_week`
  (per-week library leaderboard scan) still scan attendance — batch 2 (needs a small precompute or a
  scheduled recompute).

### Session 2026-06-18 (g) — P8-01 batch 1: canonical IST clock (member dashboard / scanner / holidays)
Added canonical IST helpers to `lib/utils/time_utils.dart` — `istNow()`, `istToday()`, `istTodayKey()`,
`istDateKeyFromDb(dbTime)`. Routed the member-facing day-boundary logic through them (was a mix of
device-local `.toLocal()` and UTC date-keys):
- **Closure "today" key (always off-by-one 00:00–05:30 IST):** `qr_scanner_screen` + `member_home` now
  use `istTodayKey()`.
- **Streaks / study-days:** `member_home` `_studyDates` bucketing → `istDateKeyFromDb`; `_calculateCurrentStreak`,
  `_getLast7DaysAttendance`, `_computeMemberState` + expired lookups → `istNow()`/`istToday()`.
- **Holidays:** `holiday_service.todaysHoliday` / reopen check → `istNow()`.
- `flutter analyze` clean. ⛔ device-verify streak/“studied today”/closure near midnight.
- **P8-01 batch 2 (DONE 2026-06-18):** added `istWallClockToUtc()` helper. Analytics ENGINE
  (`member_analytics_service`) + TABS (`member_analytics_tab`, `admin_analytics_tab`) now build all
  ranges from `istNow()` and convert query bounds via `istWallClockToUtc()` (was naive
  `DateTime(y,m,d).toIso8601String()`/`.toUtc()` → the window was 5.5h off even on IST devices for the
  engine). Attendance/streak/revenue bucketing → `istDateKeyFromDb`/`toIST`. Relative windows
  (last-7/180d) and export date-stamps left as-is. `flutter analyze` clean. ⛔ device-verify analytics
  numbers (revenue, attendance rate, leaderboard, heatmap, today/this-week filters).

### Session 2026-06-18 (f) — P5-08: actor-scope the forgeable inserts — APPLIED
`2026-06-18_actor_scope_inserts.sql` (+ folded into canonical) — **applied to live DB 2026-06-18**.
Replaced the open `WITH CHECK (auth.uid() IS NOT NULL)` on **notifications / audit_log / badges / referrals** with
relationship-scoped checks that still allow every real cross-actor write:
- **notifications:** self · owner→member · owner→applicant · (member|applicant)→owner. Covers all
  ~15 notify sites (admin→member actions, broadcasts, member→owner queries, badge self-notify).
- **audit_log:** `admin_id = auth.uid()` only. Code: `join_flow_screen` no longer writes an
  owner-attributed audit row (kept the owner notification, which is allowed).
- **badges:** self-award or owner-of-the-badge's-library (covers member analytics + admin viewing).
- **referrals:** inserter must be referrer or referred.
- `flutter analyze` clean. ⛔ **apply + device-verify** (notify-heavy flows: approve/reject/hold/end/
  seat/query/broadcast deliver; member query reaches owner; streak badge awards; forgery of an
  unrelated notification/badge fails). One-line rollback per policy in the migration.

### Session 2026-06-18 (e) — Security hardening batch: lock privileged columns + tenant-scope + membership lock — APPLIED
Device available; adopt-then-tighten. `flutter analyze` clean. **All migrations applied to live DB 2026-06-18:**
- **P6-03/P6-06 — subscription + verified lock** (`2026-06-18_lock_user_privileged_columns.sql`):
  consolidated the role lock into one `guard_user_privileged_columns` trigger (GUC
  `app.allow_privileged_update`) covering `role` + `subscription_plan/status/expiry` +
  `phone_verified/email_verified`. New `start_my_trial()` RPC (admin one-time 14-day starter);
  `admin_home` launch now calls it instead of a direct `users.update`. `change_my_role` re-created on the
  unified GUC (replaces standalone `guard_role_change`). Verified flags had no client writer → pure lock.
- **P10-04 — tenant-scope users SELECT**: folded the authored `2026-06-14_users_select_tenant_scope.sql`
  into canonical (owner reads only members + pending applicants of their libraries; cross-library lookup
  via `find_user_by_contact` RPC, already wired). User applies + verifies member lists / Requests tab /
  add-member autofill.
- **P5-01 — open memberships UPDATE**: dropped `"System can update USING(true)"`; member self-exit moved
  to `exit_my_membership()` RPC (`2026-06-18_memberships_member_exit_rpc.sql`, `member_home` wired). Admin
  writes stay owner-scoped; cron uses service_role.
- ⛔ **Still open (next):** actor-scope the cross-actor inserts (P5-08 — join_flow owner notify/audit,
  badge award) via RPCs; server tier RC-1; analytics precompute (P11); build/keystore (P1); iOS (P14-03).
- **Subscription display (same session, P6-03 related):** `start_my_trial()` now grants a **30-day Free
  window** (`plan='free'` + 30d expiry) instead of the legacy `'starter'` grant (which `plan_service`
  mapped to "Pro" — confusing). Subscription screen shows "Free — X days left" and the bottom Razorpay
  note was removed. **Deferred (user's call):** real trial *enforcement* (countdown that actually limits)
  — `betaMode=true` keeps everything unlocked for now; revisit with Razorpay/website. Existing
  'starter'/'basic' admins need a one-time reset:
  `begin; set local app.allow_privileged_update='on'; update public.users set subscription_plan='free', subscription_status='active', subscription_expiry=now()+interval '30 days' where subscription_plan in ('starter','basic'); commit;`

### Session 2026-06-18 (d) — Role-change redesign + self-escalation lock (P6-02) — APPLIED & VERIFIED
User decision: the "Change Role" option exists ONLY to fix an accidental wrong-role signup. Migration
applied to live DB + device-verified both directions (2026-06-18); `flutter analyze` clean. New rules:
- **7-day window** from signup (`users.created_at`) — after that, role is fixed (honest "not available" dialog).
- **Role change = full data wipe + fresh account:** the current role's data (memberships, attendance,
  payments, owned libraries+their members, streaks, etc.) is permanently deleted; the login identity
  (auth user / email / phone / created_at) is kept; a brand-new empty account starts in the new role.
- **Strict type-to-confirm:** user must type `ADMIN`/`MEMBER` to enable the destructive button; red
  warning explains the permanent deletion.
- **Server-enforced + escalation locked:** `silence_app/migrations/2026-06-18_role_change_rpc.sql` —
  `change_my_role(p_new_role)` (SECURITY DEFINER) does the window check + purge + role flip atomically;
  a `BEFORE UPDATE OF role` trigger (`guard_role_change`) blocks ANY other direct role flip unless the
  RPC set its transaction-local flag. Allows INSERTs, null→role onboarding, and same-value upserts, so
  `role_selection`/`member_profile_edit`/admin onboarding upserts are unaffected. Folded into canonical
  `supabase_schema.sql`. This closes audit **P6-02** (member self-escalation to admin).
- **Code:** `lib/screens/member_profile_tab.dart` + `lib/screens/admin_profile_tab.dart` — both
  `_showChangeRoleDialog` rewritten (was a plain `users.update({'role':...})`) to: fetch `created_at`,
  gate on the 7-day window, show the strict dialog, call `rpc('change_my_role', ...)`, then clear prefs
  + signOut + route to `/auth` (re-login lands in the fresh new-role onboarding).
- ✅ **APPLIED + device-verified (2026-06-18):** migration run on live DB; role change tested both
  directions within 7 days (data wiped, fresh account), the >7-day block, and normal signup/profile-edit
  upserts still work under the trigger. **Bug fixed during testing:** `change_my_role()` (and the existing
  `purge_account`) referenced non-existent `referrals.referrer_id/referred_id` → corrected to
  `referrer_member_id/referred_member_id` (42703). `created_at` kept (original signup) so the 7-day clock
  does NOT reset on role change — prevents repeat flip/wipe abuse.

### Session 2026-06-18 (c) — All pending live-DB migrations APPLIED (user-run)
User confirmed running every outstanding migration in the Supabase SQL editor + deploying the Edge
Function. No code change this session; docs synced. Now live:
- `2026-06-15_join_requests_payment_status.sql` — requests **Reject-Pay/Confirm-Pay**, member
  **Withdraw Application**, and the **rejected-request card** now work (DB CHECK accepts the values).
- `2026-06-14_storage_private_owner_scoping.sql` — `silence_private` reads owner-scoped (P10-01/03, DPDP).
- `2026-06-18_account_deletion_recovery.sql` + `2026-06-18_account_recovery_rpcs.sql` +
  `2026-06-18_app_owner_flag.sql` (last) — account-deletion 7-day recovery + `purge_account` (P14-02).
- Edge Function `process-account-deletions` deployed + cron scheduled.
- **No outstanding live-DB action.** Next: on-device smoke-test the gated flows; verify `purge_account`
  on a throwaway account before relying on the cron (destructive). `is_app_owner` flag stays dormant
  (recovery still approved via dashboard SQL — Option B) until a dedicated owner account exists.
- Uncommitted working tree: two FCM build edits (`android/app/build.gradle.kts` desugaring +
  `2026-06-17_device_tokens.sql` newline tidy) — commit when user asks.

### Key reframes (these OVERRIDE the old spec/audit "fixes")
- **Member ↔ library-admin payment is OUT OF APP.** Real `upi://pay` deep-link + "I have paid";
  admin verifies in their bank app + confirms. No in-app gateway, no screenshot-theatre.
- **Subscription (app-owner ↔ library-owner):** NOT in-app — **DECIDED (2026-06-18): Razorpay on the
  website only** for subscription management; the app just READS `subscription_*` (written by the
  website/webhook). In-app subscription screen shows the plan + a 30-day Free window (display-only;
  `betaMode=true` keeps features unlocked). First 1–2 months free tier.
- **Member-side "create hold" REMOVED** — only admins hold/resume; members request an early resume.
- **Identity verification (email/phone OTP): built but DISABLED.**
- **Notifications:** in-app center real; **FCM push foundation shipped + web-verified** (see above).

### What's DONE so far (remediation) — full detail in `docs_fix/IMPLEMENTATION_PLAN.md`
Shipped areas (each honest, `flutter analyze`-clean): A0 foundation (`app_colors`, `widgets/states/`,
`friendlyError`, `upi_launcher`); real notification center; join/renewal UPI reframe; admin Payment
Methods; member_home revamp (honest states, IST, bell+badge, hold reframe, library/session cards,
streak week, quick actions, offline cached card); scanner multi-session; admin Hold/Resume +
seat-change reject; Holidays/closures (`holiday_service` on `scheduled_closures` start/end); Contact
Admin↔Queries loop; states-pass on member screens; **Phase B**: real payment amount + add-ons persist
+ notify + central `audit_logger` + seat reassign/release sync + honest subscription screen + account
deletion (type-DELETE, `scheduled_for_deletion`) + referral config + member transfer + draft
persistence; **Phase C** schema reconciliation **APPLIED** (6 tables RLS-on + columns/constraints);
add-member & amenities polish; admin Reservation-tab fixes; member-profile + payments/users RLS
hotfixes (APPLIED); desktop image-pick guards; iOS location + Android INTERNET + release-keystore
scaffold; harden open insert policies (APPLIED); RPC `find_user_by_contact` + tenant-scope users
SELECT; **2026-06-15 reservation/attendance/requests overhaul** (`2a55f4d` — seat dedupe + overlap
availability, smart manual check-in/out + "Manual" tag, admin-home attendance redesign, members
"No Seat"+Assign, admin Renew sheet, requests payment-decoupled + rejected-card + soft withdraw,
permanent eligibility-gated member QR FAB; detail in `docs_fix/LAYOUT_SEAT_OVERHAUL.md` +
`RESERVATION_FIXES_2026-06-15.md`).

### Next action (when the user says "continue"/"GO")
- ✅ **Wave-0 security: ALL APPLIED to live DB (2026-06-18).** role lock (P6-02), subscription/verified
  lock (P6-03/06), tenant-scope users SELECT (P10-04), membership self-exit + open-UPDATE drop (P5-01),
  actor-scoped inserts (P5-08), storage owner-scoping (P10-01/02/03). Build/release: INTERNET + signing
  scaffold present (P1) — user generates the keystore.
- **Remaining (need decision / environment / large):**
  - **Server tier RC-1:** foundation exists (RPCs + Edge Functions); real **payments** (Razorpay) +
    **OTP** still need it — both deferred by product decision.
  - **Subscription enforcement:** `betaMode=true` keeps all features free/unlocked; 30-day Free window
    is display-only. Flip + enforce later with billing.
  - **Analytics precompute (P11-01/02):** Wave-2 perf — precompute tables/cron.
  - **iOS location crash (P14-03):** needs a Mac/iOS build.
  - **TZ reconcile (P8-01):** one IST clock everywhere + precompute.
- **FCM follow-ups:** foreground banner, tap→navigation, Android/iOS device test, webhook shared-secret.
- **FCM follow-ups:** foreground banner, tap→navigation, Android/iOS device test, webhook shared-secret.

---

## Historical audit reference (2026-06-08 baseline — evidence in `docs_audit/`)

> Everything below is the original audit context — the baseline + *why/where* of each defect. For
> current status use §0 above + `docs_fix/`. Full evidence (`file:line`), root causes, and the Wave 0–4
> roadmap are in **`docs_audit/AUDIT_PHASE_16.md`** (capstone) and the per-phase reports
> `docs_audit/AUDIT_PHASE_0..16.md`. Totals to cite: **22 C · 68 H · 63 M · 22 L** (Phase-14-updated).

**Baseline snapshot (as audited):** Flutter (~66 screens, ~74.6k LOC), Supabase (25 tables), **0 RPC /
0 Edge Functions**, 179 client-direct writes / 0 server validation; payments mocked; notifications a
stub; OTP mocked; hardcoded anon key; release debug-signed + missing INTERNET. Security scored 1.5/10
(porous RLS, PII/ID docs exposed, self-asserted identity, self-escalation).

**5 root causes (fix order):** RC-4 self-asserted identity & permissive RLS/storage → RC-3 schema
drift/missing tables → **RC-1 no server tier** (master unlock) → RC-2 money mocked → RC-5 dishonest
UX/silent failure.

**Wave roadmap:** **W0** stop-the-bleeding (storage object-scoping, tenant-scope users SELECT, remove
open UPDATE/inserts, lock role/subscription/verified cols, schema deploy fixes, keystore+INTERNET, iOS
location crash) → **W1** spine (server tier, real payments+webhook, identity verify, notifications) →
**W2** correctness (analytics precompute, one IST clock, uniqueness/idempotency, global error handler,
immutable audit) → **W3** operability (renewals, self-service, bulk ops, automation, roles, referral,
transfer) → **W4** scale (search/pagination, multi-branch, offline sync, deletion/export, WhatsApp, GST).

**22 criticals (IDs for cross-ref):** P10-01/02/03 storage exposure · P10-04 users-table read · P5-01
memberships open UPDATE · P6-02 role escalation · P6-03 subscription self-activation · P6-01/P10-08 no
server tier (ROOT) · P0-01 payments mocked · P9-02 subscription theatre · P3-01 placeholder UPI · P4-01
admin UPI unused · P4-03 hardcoded amount · P4-02 audit log broken · P9-01 notifications stub · P5-03
missing tables · P5-02 expenditures conflict · P8-01 TZ day-defs · P11-01/02 analytics scans/N+1 ·
P1-01/02 INTERNET+signing · P14-03 iOS location crash. (Many now remediated — see `docs_fix/AUDIT_CHECKLIST.md`.)

**Release verdict (baseline):** internal demo ✅; closed pilot ⚠️ only after Wave 0; public/paid ❌
until Waves 0–2/0–3. **Legal flag:** PII/ID-doc exposure (P10-01/02/04) is a reportable **DPDP** breach.

**Don't break (genuinely solid):** `auth_screen`, `qr_scanner` (typed exceptions, friendly msgs,
500-cap offline queue); 23 good DB indexes; offline queue/retry foundation; differentiators
(multi-shift seats, streaks/badges, referrals) exist in schema — broken, not absent (repair > rebuild).

**Caveats:** audit had no live DB / device / profiler — ~50 Verification-Pending items (V-01…V-53) need
live verification; 28 Open Questions remain. Don't trust "fixed" on those without live checks.

---

*Originally generated 2026-06-08 as a session-durable handoff; condensed 2026-06-17 to stay under the
context limit (historical detail preserved in `docs_audit/` + `docs_fix/`). Keep it current.*
