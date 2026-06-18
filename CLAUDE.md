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

### Session 2026-06-18 (d) — Role-change redesign + self-escalation lock (P6-02)
User decision: the "Change Role" option exists ONLY to fix an accidental wrong-role signup. New rules
(built; `flutter analyze` clean on both touched files; **migration NOT yet applied / not device-tested**):
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
- ⛔ **APPLY + TEST (destructive):** apply the migration, then on-device verify both directions within
  7 days (data really wiped, fresh account), the >7-day block, and that normal signup/profile-edit
  upserts still work under the trigger. Decision to confirm: `created_at` is kept (original signup), so
  the 7-day clock does NOT reset on role change — prevents repeat flip/wipe abuse.

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
- **Subscription (app-owner ↔ library-owner):** NOT in-app Razorpay — store IAP or website+Razorpay
  (TBD). First 1–2 months free tier; subscription screen shows mock plans (Free/₹499/₹799).
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
- ✅ **All pending migrations APPLIED (2026-06-18)** — `2026-06-15_join_requests_payment_status.sql`,
  `2026-06-14_storage_private_owner_scoping.sql`, and the account-deletion set. `process-account-deletions`
  Edge Function deployed + cron scheduled. **Now on-device smoke-test** the 2026-06-15 reservation/
  requests batch + the account-deletion/recovery flow.
- **FCM follow-ups:** foreground banner, tap→navigation, Android/iOS device test, webhook shared-secret.
- **Phase C:** optional §E `library_closures` drop; on-device smoke test of touched flows.
- **Security/RLS (Wave 0/1, ⛔ needs live DB + device):** checklist in
  `docs_fix/SECURITY_HARDENING_RUNBOOK.md` (adopt-then-tighten). Priority: tenant-scope `users` SELECT
  (done via RPC), storage owner-scoping (P10-01/02/03, DPDP), then P5-01/P6-02/06 column locks.
- **Phase B remaining (server/OTP-gated):** claim/link (phone OTP, disabled) · referral auto-credit
  (server job) · owner-visibility of deletion requests (app-owner console) · real payments/subscription.

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
