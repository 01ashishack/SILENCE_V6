# SILENCE — Audit Remediation Checklist

> **What this is.** A single living checklist mapping the **16-phase audit** (baseline ~2.5/10,
> 22 C · 68 H · 63 M · 22 L — see `docs_audit/`) against the **remediation actually shipped** in the
> UI/UX → Flow → Schema overhaul. Use it to see at a glance what's **done**, **partial**, or **pending**.
>
> Legend: ✅ done · 🟡 partial (started / honest-interim) · ⬜ not started · ⛔ blocked on live DB/device/server-tier
>
> Companion docs: `IMPLEMENTATION_PLAN.md` (build log) · `UIUX_OVERHAUL_DECISIONS.md` (decisions) ·
> `PHASE_C_SCHEMA.md` (schema reconciliation) · `../CLAUDE.md` §0 (status).
> Audit evidence: `../docs_audit/AUDIT_PHASE_*.md`.
> **Last updated: 2026-06-11.**

---

## 0. TL;DR scoreboard

| Track | Done | Partial | Pending |
|---|---|---|---|
| Member↔admin payments (out-of-app reframe) | UPI deep-links, real amount, verify→confirm notify | subscription (Razorpay) | account-of-record polish |
| Honest UI / trust (Phase 9) | notifications real, dishonest successes killed, friendly errors, states | a few admin screens left | — |
| Holidays / closures (3-way schema conflict) | ✅ reconciled in code + ✅ Phase C migration **applied** (dead `library_closures` retired via opt-in §E) | — | optional §E drop |
| Queries loop | ✅ Contact Admin + admin reply + notify + ✅ Phase C (`subject`/`type`/`screenshot_url`) **applied** | — | — |
| Audit log | ✅ central helper + reader aligned | — | broaden to every mutating action |
| Security (RLS / storage / identity) | — | — | ⛔ **entire Wave 0** (needs live DB) |
| Schema deploy (missing/conflicting tables) | ✅ **Phase C applied to live DB** (migration run; 6 tables RLS-on, columns, guarded constraints) | — | optional §E drop + smoke test |
| Server tier (RPC/Edge) | — | — | ⛔ Wave 1 (large) |
| Perf precompute (analytics/badges) | — | — | ⬜ Wave 2 |
| Build / store readiness | — | — | ⛔ keystore, INTERNET, iOS crash |

---

## 1. The 22 Critical Findings

| # | ID | Title | Status | Where / note |
|---|---|---|---|---|
| 1 | P10-01 | Private bucket not owner-scoped | ✅ | `2026-06-14_storage_private_owner_scoping.sql` **applied 2026-06-18** — `silence_private` reads owner-scoped (3-seg `family/<id>/<file>`). Device-verify signed-URL reads recommended |
| 2 | P10-02 | PII in **public** bucket | ✅ | ID docs + payment proofs moved to `silence_private` (code, 2026-06-18) + owner-scoping migration applied (DPDP). Profile photos stay public by decision |
| 3 | P10-03 | Storage world-writable/deletable | ✅ | owner-scoped read/write/delete policies in `2026-06-14_storage_private_owner_scoping.sql` **applied 2026-06-18** |
| 4 | P10-04 | Any user reads `users` table | ✅ | tenant-scoped SELECT **applied 2026-06-18** (`2026-06-14_users_select_tenant_scope.sql`; owner reads only members+pending applicants; cross-library lookup via `find_user_by_contact` RPC) |
| 5 | P5-01/P10-05 | `memberships` UPDATE open to all | ✅ | open `USING(true)` **dropped + applied 2026-06-18**; member self-exit via `exit_my_membership()` RPC; admin writes owner-scoped |
| 6 | P6-02 | Role self-escalation member→admin | ✅ | **Role-change redesign applied + device-verified (2026-06-18)** (`2026-06-18_role_change_rpc.sql` + both profile tabs): `change_my_role()` RPC enforces a **7-day-from-signup** window, **wipes all role data** + starts a fresh account; a trigger blocks any other direct `role` flip (self-escalation closed) |
| 7 | P6-03 | Subscription self-activation | ✅ | self-activation removed (B6) + **`subscription_*`/`verified` columns locked** by `guard_user_privileged_columns` trigger **applied 2026-06-18** — only `start_my_trial()` / billing may write; (paid-tier *limit* enforcement still gated behind `betaMode`, by decision) |
| 8 | P6-01/P10-08 | **No server tier (root)** | 🟡 | foundation now exists — SECURITY DEFINER RPCs (`change_my_role`, `start_my_trial`, `exit_my_membership`, `find_user_by_contact`, account-recovery) + Edge Functions (`send-push`, `process-account-deletions`); still needed for real payments + OTP (both deferred by decision) |
| 9 | P0-01 | Payments fully mocked | 🟡 | reframed to **out-of-app UPI** + real amount; Razorpay (subscription) deferred to last |
| 10 | P9-02 | Subscription payment theatre + fake invoice | ✅ | **B6** — subscription_screen rewritten: 3 honest mock plans (Free/₹499/₹799); removed Razorpay sim sheet, `Future.delayed`, fake invoice, self-activation; "free during beta / coming soon" |
| 11 | P3-01 | Members pay hardcoded placeholder UPI | ✅ | join/renewal read admin `social_links.upi_ids` → real `upi://pay` deep-links |
| 12 | P4-01 | Admin UPI stored but never consumed | ✅ | Payment Methods section + consumed in join/renewal |
| 13 | P4-03 | Approval hardcodes amount | ✅ | **B1** — `_computeApprovalAmount` (plan price + add-ons − discount) |
| 14 | P4-02 | Audit log broken on write AND read | ✅ | **B4** — `lib/utils/audit_logger.dart` canonical + reader aligned |
| 15 | P9-01 | Notifications hardcoded "all caught up" stub | ✅ | real notification center + notify on approve/reject/hold/seat/holiday/query/payment |
| 16 | P5-03 | 7 code tables missing from schema | ✅ | **Phase C applied to live DB** — all 6 tables created with RLS (`settings`,`streaks`,`member_daily_stats`,`leads`,`verification_requests`,`draft_members`); RLS check = `relrowsecurity=true` for all 6 |
| 17 | P5-02 | 4 conflicting `expenditures` schemas | ✅ | **Phase C applied** — canonical schema unified, loose files superseded, `admin_analytics_tab` normalized to lowercase keys, existing rows migrated (§D) |
| 18 | P8-01 | Three contradictory "which day" defs (TZ) | ✅ | **IST is now the single clock (2026-06-18).** Batch 1: `istNow/istToday/istTodayKey/istDateKeyFromDb` + member dashboard/scanner/holidays. Batch 2: `istWallClockToUtc` helper; analytics **engine** (`member_analytics_service`) + **tabs** (member/admin) build ranges from `istNow()` and convert query bounds via `istWallClockToUtc` (fixes the 5.5h-off analytics window); attendance/revenue bucketing → IST. Device-verify analytics numbers |
| 19 | P11-01 | Analytics fast-path tables absent | ✅ | `member_daily_stats` now precomputed via an attendance trigger + backfill (`2026-06-18_member_daily_stats_precompute.sql`, IST-day rollups); the service's existing fast-path now hits indexed rows instead of full attendance scans |
| 20 | P11-02 | Badge engine N+1 | ✅ | all badge checks now read the precomputed rollup: `100_days_club`/`consistent`/`early_bird`/`night_owl` via `member_daily_stats`, `top_of_week` via the indexed `member_is_week_top()` RPC — no more per-analytics-load attendance scans (`2026-06-18_badge_precompute_batch3.sql`) |
| 21 | P1-01/P1-02 | Release manifest missing INTERNET + debug-signed | ✅ | INTERNET permission present in manifest; release `signingConfig` wired to `key.properties` (gitignored) with debug fallback — user generates the keystore (`key.properties.example`) |
| 22 | P14-03 | iOS crashes on location screen | ⛔ | needs device/iOS build |

**Criticals closed: 19 ✅ · 2 🟡 (P0-01 payments, P6-01 server-tier-partial) · 1 ⬜ (P14-03 iOS — needs a Mac). All Wave-0 RLS/storage/identity locks applied 2026-06-18; IST is the single clock app-wide; analytics + badges fully precomputed.**

---

## 2. Five Root Causes

1. **RC-4 — Self-asserted identity & permissive RLS/storage** → ✅ **largely closed (applied 2026-06-18):**
   storage owner-scoping (P10-01/02/03); role self-escalation (P6-02, verified); subscription/verified
   locks (P6-03/06); tenant-scope users SELECT (P10-04); open membership UPDATE (P5-01); forgeable
   inserts actor-scoped (P5-08). Remaining: identity-verify (disabled by decision).
2. **RC-3 — Schema drift / missing tables & constraints** → ✅ **Phase C applied to live DB** (6 tables + columns + guarded constraints; closures reconciled); concurrency-safe seats deferred (server tier).
3. **RC-1 — No server-side tier** → ⛔ pending (Wave 1, large).
4. **RC-2 — Money is mocked** → 🟡 member↔admin made **real & honest** (out-of-app UPI + derived amount); app-owner↔library Razorpay deferred.
5. **RC-5 — Dishonest UX + silent failure** → ✅ **largely addressed** (real notifications, honest states, friendly errors, killed false-success fallbacks, one IST clock on touched surfaces).

---

## 3. Remediation SHIPPED (the UI/Flow track) — ✅

### Foundation & shared
- [x] `lib/theme/app_colors.dart` tokens
- [x] `lib/widgets/states/` — Loading (skeleton)/Empty/Error/Offline reusable states
- [x] `lib/utils/error_messages.dart` — `friendlyError` / `isNetworkError`
- [x] `lib/utils/upi_launcher.dart` — UPI deep-link + app detection
- [x] `lib/utils/holiday_service.dart` — canonical closures helper
- [x] `lib/utils/audit_logger.dart` — canonical audit writer

### Member side
- [x] Notification center (real `notifications`; fixed broken insert sites)
- [x] member_home revamp — honest error/offline, expiry "0 days" fix, bell + unread badge, hold reframe
- [x] Library card redesign (IST 12h timing, joining date, Renew + ⋮ menu)
- [x] Session cards (prev-below-running, multi-session, relative titles)
- [x] Recent Activities — IST + all activity types + **bounded scroll**
- [x] Streak card — **Sunday→Saturday** week + today highlight + details row
- [x] Quick Actions — title + Contact Admin / Refer & Earn / Renew / Find Library
- [x] Stats loading **skeleton** (replaced spinner)
- [x] **Offline cached membership card** (cache + fallback + OfflineBanner, no fake live state)
- [x] Join/Renewal payment reframe (real UPI, "I have paid", honest copy)
- [x] **Contact Admin** hub (single screen — replies shown inline; submit-form compose)
- [x] Member screens states-pass (friendlyError sweep; killed explore's fake "submitted ✓")
- [x] Member holiday state ("Library closed today" + disabled check-in/FAB)
- [x] **Account deletion** reflects on dashboard (pending-deletion banner + check-in disabled)
- [x] Scanner — multi-session + 10-min cooldown disabled + range-aware closure gate

### Admin side
- [x] Payment Methods section (+ fixed social_links JSONB overwrite bug; deleted dead `payment_setup.dart`)
- [x] Hold / Resume a member's membership
- [x] Reject paths for join + seat-change requests (reason + notify + audit)
- [x] Holiday management ("Close Today" → Holidays: single/range, notify, dashboard banner, analytics card)
- [x] Manage Queries → **reply + notify** member
- [x] **B1** real payment amount · **B3** notify on approve/reject + payment confirm/reject · **B4** audit helper
- [x] **B5** seat reassign/release sync · **B6** honest subscription screen (Free/₹499/₹799)
- [x] Subscription & Billing entry in admin profile · **account deletion** (admin danger zone, type-DELETE)
- [x] Dup-prevention (admin approval re-entrancy guard) · global status-bar/top-bar consistency
- [x] **Reservation tab fix (2026-06-11)** — member_detail blank-screen (active-tab-only build + per-tab error boundary + null-id guard); members_sub_tab card → full profile + ⋮ to top-right + "View Details" removed + Renew/Hold-Resume/Transfer/Remove (real writes + notify + audit); layout_sub_tab seat-desync reconcile + self-heal + real "Assign Member" picker
- [x] **Add-member / amenities polish (2026-06-11)** — wizard dup-guard + honest error (keeps open) + seat-occupy before payment; removed add-on "Total Available Inventory" box; Step-3 add-on price-type chip + configured-only plan pills
- [x] **Member-profile fixes + payments RLS hotfix (2026-06-12)** — fixed Activity-tab freeze (shrink-wrapped the unbounded Activity/Payments lists); date-wise attendance analytics (range + per-day check-in/out/study-time); per-member CSV/PDF export; Transfer hidden when admin owns 1 library; add_member_wizard compensating rollback + `pending` dup-guard. **Payments RLS hotfix** authored (`migrations/2026-06-12_payments_admin_insert_rls.sql` — owner-scoped INSERT on `payments`; was the cause of the add-member 42501 error + empty Payments tab). ✅ Applied to live DB.

---

## 4. Phase B (flow wiring) — done vs remaining

**Done ✅**
- [x] **Real payment amount** (B1) — shift price + add-ons − discount; killed hardcoded 1500/4000/7500
- [x] **Add-ons persist** (B2) — join writes `selected_addon_ids` (graceful); approval inserts `member_add_ons` *(Phase C: add the column)*
- [x] **Notify on approve/reject** (B3) + payment confirm/reject
- [x] **Central audit helper** (B4) — `audit_logger.dart` canonical + reader aligned
- [x] **Seat reassign/release sync** (B5) — real Reassign dialog + `memberships.seat_id` sync + notify (no desync)
- [x] **Honest subscription screen** (B6) — Free/₹499/₹799 mock plans; removed Razorpay sim sheet + fake invoice + self-activation
- [x] **Account deletion** — member + admin: type-DELETE confirm + warnings; member dashboard banner + disabled check-in
- [x] **Status-bar/top-bar consistency** — global `SystemUiOverlayStyle` + `AppBarTheme`
- [x] **Dup-prevention** — member submit gated on `_isSubmitting`; admin approval `_isApproving` re-entrancy guard

**Remaining ⬜ / blocked ⛔**
- ✅ **FCM push send** — server tier SHIPPED (`supabase/functions/send-push` + Database Webhook on `notifications` INSERT; `device_tokens` table); **web-verified end-to-end** (2026-06-17). Pending: Android/iOS device test, foreground banner, webhook shared-secret hardening.
- ⛔ **Manually-added member claim/link** — needs phone OTP (verification disabled by decision)
- 🟡 **Referral** — share works; **admin config** screen ✅ built + wired (admin profile → Operations → "Referral Rewards" → `/admin/settings/referrals`: enable toggle + referrer/referee extra days, saved to `settings` via `AdminSettingsService`, honest "manual crediting for now" copy); **auto-credit** after 30-day use still needs a server job
- ✅ **Member transfer** — `lib/screens/reservations/member_transfer_screen.dart` (entry: member_detail → "Transfer to another library"): pick target owned library → shift → vacant seat (or "assign later") → confirm; frees old seat, marks old membership `transferred`, inserts new membership (expiry/plan/discount carried, `transferred_from` set) + `transfers` row, occupies new seat, notifies member, audits. Expiry preserved, no new payment (honest). Dup-membership + seat-race guards. *(Phase C: `transfers` orphan table now wired)*
- ✅ **Draft persistence** — `lib/utils/form_draft.dart` (per-user, per-library, SharedPreferences-backed). Join + renewal forms auto-save (debounced text + on step/selection changes), offer a **Resume / Start fresh** prompt on re-entry, and clear on successful submit. Survives app restart; honest (local draft, not a submission). Granularity: per completed step/selection — mid-step typing before the 600 ms debounce isn't guaranteed across a hard kill.
- ⬜ **Owner-visibility of deletion requests** — needs an app-owner console (out of current scope)
- [ ] Verification screens (email/phone OTP) — **built but DISABLED** per decision; enable later

---

## 5. Phase C (schema reconciliation) — ✅ AUTHORED + APPLIED to live DB 2026-06-11

> Deliverables: `silence_app/migrations/2026-06-11_phase_c_reconciliation.sql` (runnable) +
> unified `silence_app/supabase_schema.sql` + `admin_analytics_tab` code fix + superseded loose
> files. Full detail + apply order + verification gate in **`PHASE_C_SCHEMA.md`**.

- [x] Drop / migrate dead **`library_closures`** — code already canonical; migration §E retires the table (opt-in, guarded)
- [x] Add **`join_requests.selected_addon_ids`** (UUID[]) — retires the in-code retry fallback
- [x] Reconcile **`queries`** drift — added `subject`/`type`/`screenshot_url`; status already canonical (`open/replied/closed`) in current code
- [x] Reconcile **`expenditures`** — canonical schema unified; loose files superseded; `admin_analytics_tab` normalized to lowercase keys + label map; existing rows migrated (§D)
- [x] Add migrations for the **missing tables** (settings, streaks, member_daily_stats, leads, verification_requests, draft_members) — folded into canonical schema + migration, each with RLS
- [x] Wire orphan tables: **`member_add_ons`** (written on approval), **`transfers`** (member transfer flow)
- [x] Uniqueness/idempotency — partial-unique indexes (one live membership per member/library; one seat per live membership) — **guarded** (§A pre-checks first)
- [x] Attendance validity CHECKs (checkout ≥ checkin, duration ≥ 0) — added `NOT VALID` in migration, inline in canonical schema
- [x] Added `users.referral_code` / `scheduled_for_deletion` / `deletion_scheduled_at` + `seat_change_requests.approved_at`
- [ ] ⛔ **Concurrency-safe seats** (conditional update / version column) — deferred (needs server tier / Wave 2)
- [x] **Applied + verified on live DB (2026-06-11)** — §A/§D pre-checks clean ("Success. No rows returned"); RLS check = all 6 new tables `relrowsecurity=true`. *(optional §E `library_closures` drop + on-device smoke test still pending)*

---

## 6. REMAINING — Security Wave 0 (⛔ needs live Supabase project — flag user first)

- [ ] Object-scope private storage; move PII off public bucket; lock write/delete (P10-01/02/03)
- [ ] Tenant-scope `users` SELECT + gate library creation (P10-04)
- [ ] Remove `memberships` open UPDATE + open `WITH CHECK(true)` inserts (P5-01/P10-05/10/11/12)
- [ ] Lock client writes to `role` / `subscription_*` / `*_verified` columns (P6-02/06)
- [ ] Real release **keystore** + add `INTERNET` to release manifest (P1-01/02)
- [ ] Fix iOS location crash before any TestFlight (P14-03)

## 7. REMAINING — Wave 1+ (bigger bets)

- [ ] **Server tier** (RPC/Edge + `SECURITY DEFINER`) for all privileged mutations (RC-1)
- [ ] **Real payment gateway** (Razorpay, app-owner↔library) + webhook verification (RC-2, deferred last)
- [ ] Identity verification (email confirm + phone OTP) — enable the built screens
- [ ] Analytics precompute (daily-stats + streaks + badges-on-write) (P11-01/02)
- [ ] Global error handler + session recovery + telemetry; network retry

---

*Keep this current as batches land. A box flips to ✅ only when the work is done AND `flutter analyze`
is clean vs baseline; ⛔ items stay blocked until a live DB / device / server tier exists.*