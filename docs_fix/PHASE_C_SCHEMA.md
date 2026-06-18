# SILENCE — Phase C: Schema Reconciliation

> **Status: AUTHORED 2026-06-11, APPLIED to the live DB.** The migration was run in
> the Supabase SQL editor (6 new tables RLS-on + additive columns + guarded
> constraints; expenditures normalized). Confirmed in `../CLAUDE.md` §0. The §A
> pre-checks + per-screen verification were the gate — see **§5** for the
> live-verification log.

This closes the **schema-drift** half of the audit (P5-02 / P5-03 / P5-06 /
P5-12). It deliberately does **not** touch the **RLS/security** half
(P5-01 / P5-07 / P5-08) — those stay on the separate Wave-0/1 security track
(see §6).

---

## 1. What changed (the deliverables)

| Artifact | Change |
|---|---|
| `silence_app/migrations/2026-06-11_phase_c_reconciliation.sql` | **NEW.** The runnable migration: §A pre-flight checks → §B additive columns → §C missing tables → §D expenditures normalization → §E (opt-in) drop dead `library_closures` → §F guarded integrity constraints. Idempotent; safe to re-run. |
| `silence_app/supabase_schema.sql` | **UPDATED.** Folded every additive change in so a **clean deploy** reproduces the running app (closes P5-03). |
| `lib/screens/admin_analytics_tab.dart` | **CODE FIX.** Expense add/edit now store **canonical lowercase** category keys (`Salaries→salary`, `Others→miscellaneous`, …) and map back to Title-Case labels for display. Both expense-entry paths now share one vocabulary → CHECK holds, analytics group correctly (closes the P5-02 code side). |
| `expenditures.sql`, `draft_members.sql`, `indices.sql` (repo root) | **SUPERSEDED headers** added (DO NOT RUN). Their content now lives in the canonical schema. Resolves the "4 conflicting expenditures schemas" drift. |

### §B — Additive columns (code already writes these)
- `join_requests.selected_addon_ids uuid[]` — retires the in-code retry fallback.
- `queries.subject`, `queries.type`, `queries.screenshot_url` — written by the help/bug-report screens.
- `users.referral_code`, `users.scheduled_for_deletion`, `users.deletion_scheduled_at` — referral + account-deletion-request flags (honest request flags; no server purge yet).
- `seat_change_requests.approved_at` — stamped on admin approval.

### §C — Missing tables (referenced by code, were absent / loose)
`settings`, `streaks`, `member_daily_stats`, `leads`, `verification_requests`,
`draft_members` — each created **with RLS enabled + ownership-scoped policies**
(matching the existing `draft_members.sql` pattern). Authoring RLS for *new*
tables is part of creating them correctly; **no existing table's policy is
modified.**

> `settings` upsert is on `(admin_id, library_id, scope)` where `library_id` is
> **nullable** (global scope). The unique index uses `NULLS NOT DISTINCT`
> (Postgres 15+) so the global-scope row is matched on conflict — otherwise the
> upsert would insert duplicates.

### §F — Guarded integrity constraints (P5-06)
- Partial-unique: one live membership per `(member_id, library_id)`.
- Partial-unique: one live membership per `seat_id` (no seat double-booking).
- CHECK: attendance checkout ≥ checkin; duration ≥ 0 (added `NOT VALID` in the
  migration so legacy rows don't block creation; inline in the canonical schema).

---

## 2. How to apply (manual, in order)

1. **Back up** (Supabase dashboard → Database → Backups, or `pg_dump`).
2. Open `silence_app/migrations/2026-06-11_phase_c_reconciliation.sql`.
3. Run **§A** (read-only). Note any rows returned.
4. Run **§B, §C, §D** — safe regardless of §A output.
   - §D prints any expense row still outside the canonical category set; expect none.
5. If **§A** returned **zero** rows, run **§F**. If it returned rows, **clean
   them first** (dedupe memberships, fix bad attendance), then run §F.
6. **§E** is destructive and commented out — only uncomment `DROP TABLE IF EXISTS
   library_closures;` after confirming the table is empty/unneeded.
7. After cleaning §A3 rows, optionally run the two `VALIDATE CONSTRAINT`
   statements at the bottom of §F.

The app code already tolerates a not-yet-migrated DB (graceful fallbacks for
`selected_addon_ids`, `screenshot_url`, and the analytics drift tables), so there
was **no hard ordering** between deploying the app and applying the migration —
the migration has now been applied, so those features work fully.

---

## 3. Decisions taken (with the user)
- **Scope = additive only.** No changes to existing RLS policies (security track stays separate).
- **Constraints = include, guarded.** Pre-check queries (§A) run before enforcement.
- **Expenditures = fix the code to canonical** (not relax the CHECK), so the two entry screens share one category vocabulary and analytics stay correct.

---

## 4. Audit findings this closes
- **P5-02** (4 conflicting expenditures schemas + Title-Case CHECK violation) — ✅ schema unified + code normalized + existing rows migrated (§D).
- **P5-03** (7 code tables missing from schema) — ✅ all now in the canonical schema (`settings`, `streaks`, `member_daily_stats`, `leads`, `verification_requests`, `draft_members`; `member_add_ons`/`transfers` already present and now wired).
- **P5-06** (no dup-membership / seat-occupancy guard) — ✅ partial-uniques (guarded).
- **P5-09** (negative/invalid attendance) — ✅ CHECKs added.
- **P5-12** (`scheduled_closures` vs dead `library_closures`) — ✅ code already canonical; §E retires the dead table (opt-in).
- **P5-11** (migration sprawl / redundant columns) — ✅ loose files superseded; one source of truth.

---

## 5. Live-verification log (migration applied; some on-device checks remain)
| VID | Item | Method | Status |
|---|---|---|---|
| VC-01 | Run §A pre-checks; confirm zero violations (or clean) | Supabase SQL editor | ✅ done (applied) |
| VC-02 | Apply §B/§C/§D/§F; confirm no errors | SQL editor | ✅ done (applied) |
| VC-03 | Test insert from each touched screen (join w/ add-ons, bug report w/ screenshot, expense add/edit, referral code, account-deletion toggle, seat-change approve) | On-device / DB row check | ⏭️ on-device smoke test pending |
| VC-04 | Confirm the 6 new tables exist **with RLS enabled** in the live DB | `select * from pg_policies` | ✅ confirmed (6 tables RLS-on) |
| VC-05 | Confirm `settings` global-scope (null library_id) upsert updates in place | SQL editor | ⏭️ pending |
| VC-06 | After cleanup, `VALIDATE CONSTRAINT` the two attendance CHECKs | SQL editor | ⏭️ pending |

---

## 6. Explicitly OUT of scope (still open — security track)
These dangerous-RLS findings are **not** addressed here and remain open:
- **P5-01** `memberships` `FOR UPDATE USING(true) WITH CHECK(true)` — any authenticated user can rewrite any membership.
- **P5-07** `users` admin SELECT exposes **all** users' PII to any library owner.
- **P5-08** `WITH CHECK(true)` inserts on `referrals` / `badges` / `notifications` / `audit_log` (forgery/spam).

They need least-privilege RLS rewrites + ideally a server tier, and must be
tested against a live DB. Tracked as **Wave 0/1 security** in `../CLAUDE.md` and
`AUDIT_CHECKLIST.md` §6.
