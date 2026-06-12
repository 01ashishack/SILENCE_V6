# GitLab Duo — workspace rules for SILENCE

Read `AGENTS.md` (repo root) FIRST, then `CLAUDE.md` and the `docs_fix/` docs it lists. Summarize the
current state back to the user and wait for approval before editing. These rules are non-negotiable:

1. **No dishonest UI.** Never show success / "paid" / "notified" / "submitted" for something that did
   not actually happen. Honest error + retry instead.
2. **Keep the warm-orange `#E65C00` Material 3 style.** Refine, don't redesign; maintain UI + color
   hierarchy. Reuse existing widgets in `lib/widgets/states/` and helpers in `lib/utils/`.
3. **Ask before adding** anything not already decided. Don't invent features, abstractions, or scope.
4. **Source of truth = the existing codebase**, NOT the `silence_app/` spec (it is stale; several
   decisions in `docs_fix/UIUX_OVERHAUL_DECISIONS.md` deliberately diverge from it).
5. **Run `flutter analyze` after every change; target 0 NEW errors.** Pre-existing noise is BASELINE —
   do NOT "fix" it: `withOpacity`, `use_build_context_synchronously`, `avoid_print`, unused imports.
6. **No live Supabase DB access.** Schema/RLS changes must be authored as a runnable `.sql` migration in
   `silence_app/migrations/` that the USER applies and verifies. Never assume the live DB changed.
7. **No server tier exists** (0 RPC/Edge, direct `.from(...)` writes). Don't fake server behaviour.
8. **Commit/push ONLY when the user explicitly asks.** End commit messages with a `Co-Authored-By:`
   trailer naming your model. Work in small, reviewable batches and update `CLAUDE.md` + `docs_fix/`
   as state changes.

⛔ **Open blocker:** the payments RLS hotfix migration
(`silence_app/migrations/2026-06-12_payments_admin_insert_rls.sql`) must be applied to the live DB —
until then, adding a member fails with "You don't have permission" (42501) and Payments tabs stay empty.

Windows env; shell path is `/c/Users/kumar/combined/SILENCE_V6`. Use forward slashes / Unix shell syntax.
