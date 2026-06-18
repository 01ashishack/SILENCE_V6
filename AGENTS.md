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

- Branch `main`. Latest committed checkpoint: **`9ea0403`** (2026-06-18) — member-exit dues
  fail-open (P7-08) + 7-day deletion copy. Recent: account-deletion 7-day recovery flow, app-owner
  flag, storage-PII move, FCM push foundation, add-member wizard fixes, audit-fix batch. HEAD is
  **fully synced with `origin/main`** (0 ahead / 0 behind).
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
  reservation batch + account-deletion/recovery flow (now that migrations are live); commit the two
  pending FCM build edits; FCM follow-ups (foreground banner, tap→nav, device test, webhook
  shared-secret); optional DB cleanup of orphaned `seats` rows; real payments; OTP; security RLS
  Wave 0/1.


<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->
