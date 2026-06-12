# AGENTS.md — SILENCE (agent onboarding & operating rules)

> Any AI coding agent (Codex, etc.): read this FIRST, every session. This file is the entry
> point. The full project memory lives in `CLAUDE.md`; this file points you there and pins the
> non-negotiable rules. (Claude Code reads `CLAUDE.md` automatically; other agents should start
> here.)

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

- Branch `main`. Recent commits:
  - `df70f7b` — Remediation: UI/UX honesty pass, Phase B wiring, Phase C schema reconciliation
  - `30da253` — reservation-tab fix + four-problem fix (addon_services, add_member_step2,
    layout_sub_tab, member_detail_screen, members_sub_tab)
- Phase C schema reconciliation: **authored AND applied to the live DB** (see
  `docs_fix/PHASE_C_SCHEMA.md`). 6 new tables verified RLS-on.
- Uncommitted at last handoff: `lib/screens/admin/add_member_wizard.dart` (working-tree change).
  Run `git status` first and confirm with the user before committing.
- Next candidates (user-directed, NOT automatic — confirm scope first): security/RLS Wave 0/1
  (needs live DB), FCM push, real payments, OTP enablement.

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->
