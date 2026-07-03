# AGENTS.md — SILENCE (agent onboarding & operating rules)

> Any AI coding agent (GitLab Duo Agent Platform, Codex, Claude Code, etc.): read this FIRST, every
> session. This file is the entry point. The full project memory lives in `CLAUDE.md`; this file points
> you there and pins the non-negotiable rules.
> - **GitLab Duo Agent** auto-reads this root `AGENTS.md` (always in context) AND the workspace rules
>   file `.gitlab/duo/chat-rules.md`. Caveat: Duo applies rules only to NEW conversations started after
>   the file exists — start a fresh chat after pulling. Its project search is keyword-based, not semantic.
> - **Claude Code** reads `CLAUDE.md` automatically; **Codex** reads this `AGENTS.md`.

## 0. Before you write ANY code

Read these files in this exact order, then STOP and summarize back to the user
(current state + the golden rules + what is uncommitted). Do not edit anything until the user
approves your summary.

1. `CLAUDE.md`                            — status, what's done, what's next (source of truth)
2. `docs_fix/UIUX_OVERHAUL_DECISIONS.md`  — product/UX decisions that OVERRIDE the old spec
3. `docs_fix/IMPLEMENTATION_PLAN.md`      — 3-phase plan + running build log
4. `docs_fix/AUDIT_CHECKLIST.md`          — done / partial / pending checklist
5. `docs_fix/PHASE_C_SCHEMA.md`           — schema migration + how it was applied

## 1. What this project is

SILENCE — a Flutter (Dart, Material 3) + Supabase (PostgreSQL/Auth/Storage) library &
study-space management app for Indian Tier-2/3 cities. Roles: Admin (library owner) and
Member (student). Single-tier "fat client": direct `.from(...)` REST writes, **no server tier
(0 RPC / 0 Edge Functions)**. Warm-orange theme, primary `#E65C00`.

## 2. Golden rules (NON-NEGOTIABLE — never violate)

- **No dishonest UI.** Never show success / "paid" / "notified" / "submitted" for something
  that did not actually happen. Honest error + retry instead.
- **Keep the warm-orange (#E65C00) Material 3 style. Refine, don't redesign.** Maintain UI
  consistency and color hierarchy.
- **Ask before adding** anything not already decided. Don't invent features, abstractions,
  or scope.
- **Source of truth = the EXISTING CODEBASE, not the `silence_app/` spec.** The user changed
  features after the spec was written; several decisions in
  `docs_fix/UIUX_OVERHAUL_DECISIONS.md` deliberately diverge from spec/audit.
- **Run `flutter analyze` after every change. Target: 0 NEW errors.** Pre-existing noise is
  BASELINE — do NOT "fix" it: `withOpacity`, `use_build_context_synchronously`, `avoid_print`,
  unused imports already present at HEAD. Establish the baseline first, then ensure your diff
  adds nothing new.
- **Commit/push ONLY when the user explicitly asks.** End commit messages with a
  `Co-Authored-By:` trailer naming your model.

## 3. Hard constraints (project-specific traps)

- **No live Supabase DB access from the agent.** Any schema change must be authored as a
  runnable `.sql` migration under `silence_app/migrations/` that the USER applies manually and
  verifies. Never assume you mutated the live DB. (Phase C is already authored AND applied.)
- **No server tier.** Security/RLS hardening (audit Wave 0/1) needs the live DB and is the
  user's call — don't fake it client-side.
- **Payments are out-of-app:** Member↔admin = real `upi://pay` deep-link + "I have paid"
  (no in-app gateway, no screenshot theatre). Razorpay is app-owner↔library-owner only and
  integrated last; the subscription screen shows mock plans (Free / ₹499 / ₹799) for now.
- **OTP / identity verification: built but DISABLED.** FCM push: pending. In-app notification
  center: real.
- **Windows environment.** Working dir `C:\Users\kumar\combined\SILENCE_V6` (shell sees it as
  `/c/Users/kumar/combined/SILENCE_V6`). Mind path separators. Normal local git checkout on
  `main`, remote `origin`.

## 4. Working method

- Work in small, reviewable batches. Report after each completed unit; let the user review
  before starting the next.
- Don't re-read large files in full — use ranged reads / targeted search.
- Update `CLAUDE.md` and the relevant `docs_fix/` file as state changes, so the next session
  (any agent) can continue without re-deriving anything.
- Be honest about verification: static analysis ≠ on-device testing. If you can't run the app
  or the DB, say so explicitly.

## 5. Current state (keep this in sync)

- Branch `main`. Latest committed checkpoint: **`3e7b45d`** (2026-07-02) — membership-lifecycle
  overhaul + performance. Recent line: legal/UGC + marketing posters + member avatars/leaderboard →
  **membership lifecycle** (pay-later approval, correction-request, dues exit-guard, shift
  change/transfer) → **bug fixes** (shift-card overflow, shift-request visibility + notif routing,
  revenue cards, Report-Bug quick action) → **perf** (payments index + admin-dashboard `Future.wait`)
  → **shift & requests bugfixes** (2026-07-03: conditional opening-hours reminder, 12h shift-change
  labels, white/rounded shift dropdown, resilient Requests-sub-tab fetch + honest error tiles +
  request-notification routing to the Requests sub-tab — spec `.kiro/specs/shift-requests-bugfixes/`,
  62/62 tests pass, no live-DB change). See CLAUDE.md for the full breakdown.
- **✅ Migrations APPLIED to live DB + folded into `supabase_schema.sql` (2026-06-29 → 07-02), no
  outstanding live-DB action:** `2026-06-29_join_approval_v3_paylater_correction.sql` (approve v3 +
  `p_payment_pending`; `join_requests.correction_note`/`correction_requested_at`),
  `2026-06-30_exit_dues_guard.sql` (`exit_my_membership` refuses exit with pending dues),
  `2026-07-01_shift_change_and_transfer.sql` (`shift_change_requests` table + RLS +
  `transfer_member_shift()` RPC), `2026-07-02_payments_perf_index.sql`
  (`payments(library_id,status,payment_date)` index).
- **✅ Migrations APPLIED to live DB (2026-06-28):** `2026-06-28_ugc_moderation.sql` (abuse_reports,
  user_blocks, reviews.hidden), `2026-06-28_marketing_assets.sql` (marketing_assets + public
  `marketing` bucket), `2026-06-28_member_avatar.sql` (`users.avatar_id` + leaderboard RPC returns
  avatar_id). All folded. **No outstanding live-DB action.**
- **✅ Migrations APPLIED to live DB (2026-06-26):** `2026-06-26_overtime_grace_minutes.sql`
  (configurable auto-checkout grace) + `2026-06-26_library_delete_cascade.sql` (RESTRICT→CASCADE FKs to
  libraries on memberships/attendance/payments so library delete works). Both folded into
  `supabase_schema.sql`. **No outstanding live-DB action.**
- **✅ Migration APPLIED to live DB (2026-06-19)** + folded into `supabase_schema.sql`:
  `silence_app/migrations/2026-06-19_library_display_fields.sql` (opening_hours, display_members_joined).
  **No outstanding live-DB action.** *(lat/long geo feature dropped — `location_link` "View on Map" used instead.)*
- **Phase C** schema reconciliation: authored AND **applied to the live DB** (6 new tables RLS-on) —
  see `docs_fix/PHASE_C_SCHEMA.md`. Earlier payments/users RLS hotfixes also applied.
- **✅ All previously-pending migrations APPLIED to the live DB (2026-06-18):**
  `2026-06-15_join_requests_payment_status.sql` (requests payment flow + member withdraw +
  rejected-card now live), `2026-06-14_storage_private_owner_scoping.sql` (owner-scopes
  `silence_private` reads — DPDP), and the account-deletion set
  `2026-06-18_account_deletion_recovery.sql` + `2026-06-18_account_recovery_rpcs.sql` +
  `2026-06-18_app_owner_flag.sql`. `process-account-deletions` Edge Function deployed + cron
  scheduled. All folded into canonical `supabase_schema.sql`.
- **✅ Role-change migration APPLIED + device-verified (2026-06-18):**
  `silence_app/migrations/2026-06-18_role_change_rpc.sql` — `change_my_role()` RPC (7-day window +
  data wipe + fresh account) + `guard_role_change` trigger that locks direct `role` flips (closes
  P6-02 self-escalation). Rewritten Change-Role dialogs call the RPC. (A `referrals` column-name bug
  found in testing was fixed; re-applied.) Folded into canonical schema. No outstanding live-DB action.
- **✅ Wave-0 security batch APPLIED to live DB (2026-06-18 (e)+(f)):**
  `2026-06-18_lock_user_privileged_columns.sql` (locks `role`+`subscription_*`+`*_verified`; `start_my_trial()`
  grants a 30-day **Free** window; supersedes the standalone role trigger), `2026-06-14_users_select_tenant_scope.sql`
  (tenant-scope users SELECT, P10-04/DPDP), `2026-06-18_memberships_member_exit_rpc.sql` (member self-exit
  RPC + drop open `memberships` UPDATE, P5-01), `2026-06-18_actor_scope_inserts.sql` (relationship-scoped
  notifications/audit_log/badges/referrals inserts, P5-08). All folded into canonical. **No outstanding
  live-DB action.** (Existing 'starter'/'basic' admins reset to free+30d via the documented `set local` SQL.)
- **✅ IST single clock + analytics/badge precompute + setup fixes APPLIED & verified (2026-06-18):**
  `2026-06-18_subscription_plan_allow_free.sql` (allow `'free'` plan — fixes launch 23514),
  `2026-06-18_member_daily_stats_precompute.sql` (attendance→rollup trigger + backfill, P11-01),
  `2026-06-18_badge_precompute_batch3.sql` (early/night counts + `member_is_week_top()`, P11-02),
  `2026-06-18_library_leaderboard_rpc.sql` (`library_leaderboard()` — fixes member leaderboard under
  tenant-scoped users SELECT). Code: IST clock app-wide (P8-01), duplicate-contact friendly warnings.
  **All migrations applied; no outstanding live-DB action.** Audit: 19 ✅ · 2 🟡 (out-of-app payments,
  server-tier-partial) · 1 ⬜ (iOS P14-03 — needs a Mac).
- **Subscription enforcement deferred** (`betaMode=true` keeps all features unlocked; 30-day window is
  display-only). Build/release: INTERNET + signing scaffold present (P1); user generates the keystore.
- **Working tree:** clean (last code in `git log`); local-only `devtools_options.yaml` stays out of commits.
- What's covered by `2a55f4d` (details in `docs_fix/LAYOUT_SEAT_OVERHAUL.md` + `RESERVATION_FIXES_2026-06-15.md`):
  All-Shifts seat dedupe + per-shift action sheet + day booking strip; time-overlap seat
  availability; orphaned-shift filtering; selector "All" only when >1; strip trailing "Shift" from
  names; occupied-seats-first ordering; seat-sheet scroll/overflow fix; **one smart manual
  check-in/out** (flagged `manual`, notifies member, future-time bug fixed); **"Manual" tag** in
  analytics/history/CSV/PDF (both panels); members **"No Seat"** filter + **Assign Seat**; **admin
  direct Renew sheet**; requests **payment-verify decoupled from join reject** (honest computed
  amount); member **rejected-request card** + **soft withdraw**; admin-home **Today's Attendance**
  redesign (profile photos + check-in/out times on a white card, separate In/Out entries);
  **permanent eligibility-gated QR FAB** on member home.
- Next candidates (user-directed — confirm scope first): on-device smoke test of the 2026-06-15
  reservation batch + account-deletion/recovery flow (now that migrations are live); FCM remaining is
  config + device test only (foreground banner + tap→nav + webhook-secret check already in code);
  optional DB cleanup of orphaned `seats` rows; real payments; OTP; security RLS
  Wave 0/1.


<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->
