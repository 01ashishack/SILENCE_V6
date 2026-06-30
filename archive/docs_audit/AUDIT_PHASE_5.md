# SILENCE — Phase 5: Database Audit

**Phase:** 5 of 16 — Database Audit
**Completed (local time):** 2026-06-08
**Auditor roles:** Senior Full-Stack/Data Engineer (lead) · Security Auditor · Data Analyst · QA Lead
**Goal:** Determine whether the data model actually supports the product the UI/business logic claim — table-by-table, with drift, integrity, and RLS analysis. Connect DB findings back to P2/P3/P4.
**Sources:** `silence_app/supabase_schema.sql` (canonical, 835 lines, read in full), all root + `silence_app/*.sql` migration fragments, `lib/core/offline_db.dart`, and code `.from()`/insert/update usage across `lib/`.
**Limitation (declared):** No live Supabase access. **RLS and table existence are audited from committed SQL, not the running DB.** Where the deployed DB may differ, it is marked **UNVERIFIABLE**. Behavior labels: schema facts = **Verified (from SQL)**; runtime effects = **Code-Inferred**.
**Constraint honored:** No schema or code modified.

---

## 1. Executive Summary

The canonical schema (`supabase_schema.sql`) is, in isolation, **competently designed**: 25 tables, sensible FKs with deliberate `ON DELETE` semantics, CHECK constraints on enums, RLS enabled on every table, useful unique constraints (seat-per-shift, badge-per-member, one-review-per-member-per-library), rating/`updated_at` triggers, and reasonable indexes. **But the schema does not match the application built on top of it**, and that mismatch is the *root cause* of multiple Phase 2–4 failures. The database is the layer where "false success" originates.

**Phase 5 headline findings:**

- **🔴 P5-01 (Critical, Security) — `memberships` is writable by every authenticated user.** RLS policy `"System can update (auto-hold, auto-expiry)"` is `FOR UPDATE USING (true) WITH CHECK (true)` (`supabase_schema.sql:608-609`). As written this applies to all client roles, not just `service_role`. Combined with the **no-server-tier, client-direct** architecture (P1-03), **any member can update any membership** — extend their own expiry, flip status to `active`, reassign their `seat_id`, zero their `discount_amount`. This single line undermines the entire integrity model.
- **🔴 P5-02 (Critical, Integrity) — Expense tracking is schema-broken four ways.** There are **four conflicting `expenditures` definitions** (`expenditures.sql`, `expenditures_migration.sql`, `reviews_and_expenditures.sql`, `supabase_schema.sql`) with different category rules (none / 5-lowercase / none / 12-lowercase) and different `expense_date` types (TIMESTAMPTZ vs DATE). The **code inserts Title-Case categories** (`'Rent'`, `'Electricity'`, `'Salary'`, `'Others'`, `'Salaries'`) that **violate every lowercase CHECK variant** → if the canonical schema is deployed, **every expense insert fails the CHECK constraint**. Even without a CHECK, code categories disagree with each other (`Salary` vs `Salaries`, `Others` vs `miscellaneous`) → broken expense analytics (feeds Phase 8).
- **🔴 P5-03 (Critical, Drift) — 7 code-referenced tables are absent from the canonical schema; 5 have no migration anywhere.** `settings` (has `admin_settings_migration.sql`), `draft_members` (has `draft_members.sql`), and **`streaks`, `member_daily_stats`, `library_closures`, `leads`, `verification_requests` — NO migration in the repo at all.** A clean deploy from `supabase_schema.sql` is missing all 7 → admin settings, streak/analytics, "Close Today", explore lead-capture, and verified-badge requests **break on a fresh environment**.
- **🟠 P5-04/05 (High) — The notification & audit column mismatches that broke P4-06/P4-02 are DB-rooted.** `notifications` has `read_at`/`sent_at` (no `is_read`/`created_at`); `audit_log` requires NOT NULL `admin_id`/`action` and has `details/previous_value/new_value` (no `performer_name/category/action_title/action_details`). The code writes/reads the *wrong* columns → silent failures. **This phase confirms the schema is correct and the code is wrong**, narrowing the fix.
- **🟠 P5-06 (High, Integrity) — No DB guard against duplicate active memberships or seat double-booking.** There is no unique constraint on `(member_id, library_id)` for active memberships, and `seats.occupied_by_member_id`/`memberships.seat_id` have no uniqueness — two active memberships can point at the same seat. The app's in-code dup checks (Phase 4) are racy; the DB does not back them up.
- **🟠 P5-07 (High, Privacy) — Cross-tenant PII exposure via `users` RLS.** `"Admins can view all users"` = `EXISTS (SELECT 1 FROM libraries WHERE owner_id = auth.uid())` (`:531-532`) grants **any** library owner SELECT on **every** user row system-wide (email, phone, DOB, `id_proof_url`, address) — not just their own members.

**Database Trustworthiness Score: 3.5 / 10.** Good bones, but a critical RLS hole, pervasive drift, broken expense constraints, and integrity gaps mean the DB cannot currently be trusted to enforce the product's rules — and actively causes the silent failures seen upstream.

---

## 2. What Was Reviewed
All 25 canonical tables (columns, types, defaults, CHECKs, FKs/`ON DELETE`, uniques, triggers, indexes), all RLS policies (per table), all root + `silence_app` migration `.sql` fragments for drift/conflict, the offline SQLite schema (`offline_db.dart`), and the full code `.from()`/insert/update column usage.

## 3. Files Reviewed
`silence_app/supabase_schema.sql`; `draft_members.sql`, `expenditures.sql`, `indices.sql` (root); `silence_app/{admin_settings_migration,expenditures_migration,reviews_and_expenditures,add_shift_columns,storage_setup}.sql`; `lib/core/offline_db.dart`; insert/update sites in `requests_sub_tab.dart`, `admin_home.dart`, `member_analytics_service.dart`, `verified_badge_screen.dart`, `member_explore_screen.dart`, `admin_settings_service.dart`, `add_expense_bottom_sheet.dart`, `admin_analytics_tab.dart`.

## 4. Screens Reviewed
N/A (data layer). Screen↔table references are captured in the Data Model Map (§9.1) and Table Health Scorecard (§9.3).

---

## 5. Findings

> Effort: Small/Medium/Large. Critical/High mirrored to Cross-Phase Critical Findings (§13) + master report.

### P5-01 — `memberships` UPDATE granted to all authenticated users (RLS hole) 🔴 Critical
- **Category:** Security · Authorization · Data Integrity
- **File/Lines:** `supabase_schema.sql:608-609`
  ```sql
  CREATE POLICY "System can update (auto-hold, auto-expiry)" ON memberships
      FOR UPDATE USING (true) WITH CHECK (true); -- service_role bypassed dynamically
  ```
- **Why it's a problem:** RLS policies are permissive and OR-combined; a `USING(true)` UPDATE policy with no role restriction applies to `anon`/`authenticated`. `service_role` already bypasses RLS, so this policy's only *effect* is to open membership UPDATE to ordinary clients.
- **How it fails in production (Code-Inferred exploit):** with the shipped anon key and client-direct writes (P1-03), a member calls `supabase.from('memberships').update({'end_date': '2030-01-01','status':'active','discount_amount':99999}).eq('id', anyId)` — extending their own (or others') membership, self-approving, or stealing a seat by setting `seat_id`. No server check exists.
- **Connect:** This is the DB enabler behind the client-trust risk (P1-03) and makes revenue/membership integrity unenforceable.
- **Fix:** Restrict to `service_role` (`TO service_role`) or drop the policy and perform auto-hold/expiry via a server job/Edge Function; keep only the scoped admin/member policies.
- **Effort:** Small (policy) + Medium (move automation server-side)

### P5-02 — Four conflicting `expenditures` schemas + code category CHECK violation 🔴 Critical
- **Category:** Schema Drift · Data Integrity · Feature Breakage
- **Evidence:**
  - `supabase_schema.sql:423-429` CHECK = 12 **lowercase** categories; `expense_date DATE`; has both `note` **and** `notes` (`:431-432`).
  - `silence_app/expenditures_migration.sql` CHECK = **5 lowercase** (`rent,electricity,internet,maintenance,other`).
  - `expenditures.sql` & `reviews_and_expenditures.sql` = **no CHECK**, and differing `expense_date` types (TIMESTAMPTZ vs DATE).
  - Code inserts **Title-Case**: `add_expense_bottom_sheet.dart:35-40` (`'Rent','Electricity','Maintenance','Salary'…`); `admin_analytics_tab.dart:953` (`'Salaries','Others'`).
- **Why it's a problem:** `'Rent' ≠ 'rent'` under a CHECK → insert violates constraint and throws. Category strings also disagree across code (`Salary`/`Salaries`, `Others`/`miscellaneous`) so grouping/sums are wrong even where inserts succeed.
- **How it fails in production:** if canonical schema is deployed, **admins cannot record any expense** (silent failure → "expense didn't save"); expense analytics/exports under-report.
- **Connect:** feeds Phase 8 (expense accuracy) and the revenue picture (with P4-03).
- **Fix:** one canonical `expenditures` definition; normalize categories to a single set (store lowercase keys, display labels in UI); migrate existing rows.
- **Effort:** Medium

### P5-03 — Seven tables in code, missing from canonical schema (5 with no migration) 🔴 Critical
- **Category:** Schema Drift · Missing Migrations · Deploy Breakage
- **Evidence:** missing from `supabase_schema.sql`: `settings` (only `admin_settings_migration.sql`), `draft_members` (only `draft_members.sql`), `streaks`, `member_daily_stats`, `library_closures`, `leads`, `verification_requests` — the **last five have no `CREATE TABLE` anywhere in the repo**.
- **Why it's a problem:** the canonical schema cannot reproduce the running app. Five features depend on tables that exist (if at all) only because someone hand-created them in the dashboard — **UNVERIFIABLE**, and very likely **without RLS** (see P5-08).
- **How it fails in production:** clean env → settings load, streak/daily-stats analytics, "Close Today", explore lead capture, and verified-badge submission all throw `PGRST205 table not found` (which `draft_service.dart` even has special handling for).
- **Connect:** root of P2-06; explains why "Close Today" (P4-04) writes to a table the scanner can't read.
- **Fix:** author migrations for all 7; fold into one source-of-truth schema; add CI check that every `.from('x')` has a matching table.
- **Effort:** Medium

### P5-04 — `notifications` column drift (DB root cause of P4-06/P3-05) 🟠 High
- **Category:** Schema Drift · Silent Failure
- **Evidence:** schema `notifications` = `user_id,title,body,data,sent_at,read_at` (`:337-345`). Code inserts `is_read` + `created_at` (`requests_sub_tab.dart:392-394`, `:1099-1100`) → unknown-column error → swallowed.
- **Fix:** code should use `read_at`(null)/omit `created_at`; OR add compatibility columns. Schema is the more correct side.
- **Effort:** Small

### P5-05 — `audit_log` column drift (DB root cause of P4-02) 🟠 High
- **Category:** Schema Drift · Auditability
- **Evidence:** schema requires NOT NULL `admin_id`,`action`; columns `details,previous_value,new_value` (`:348-358`). Main writer inserts `performer_name,category,action_title,action_details` (`requests_sub_tab.dart:368`) → fails; reader reads same non-existent columns (`audit_log_screen.dart:58-61`) → shows hardcoded defaults. Only `join_flow_screen.dart:498` writes valid columns.
- **Fix:** align one audit helper to schema; align reader. (Phase-4 P4-02 owns the app side.)
- **Effort:** Medium

### P5-06 — No DB-level prevention of duplicate memberships / seat double-booking 🟠 High
- **Category:** Data Integrity · Concurrency
- **Evidence:** `memberships` has no unique/partial-unique on `(member_id, library_id)` for live statuses; `seats.occupied_by_member_id` and `memberships.seat_id` are plain nullable FKs (no unique). Seat uniqueness exists only for *definition* (`unique_seat_per_library_shift`, `:129`), not *occupancy*.
- **Why it's a problem:** two concurrent approvals (P4 weak guards) can assign one seat to two members, or create two active memberships for one member/library; the DB accepts both.
- **How it fails:** seat conflicts, double counts in occupancy/revenue (Phase 8).
- **Fix:** partial unique indexes — e.g. `UNIQUE (member_id, library_id) WHERE status IN ('active','trial','hold')`, and `UNIQUE (seat_id) WHERE status='active' AND seat_id IS NOT NULL`.
- **Effort:** Medium

### P5-07 — Cross-tenant PII exposure via `users` SELECT RLS 🟠 High
- **Category:** Security · Privacy (→ Phase 10)
- **Evidence:** `:531-532` — any user who owns *any* library may SELECT *all* `users` rows (incl. `email,phone,date_of_birth,id_proof_url,address`).
- **Why it's a problem:** a single library owner can enumerate the entire user base's PII; violates least-privilege and (with public-bucket ID proofs, R-01) compounds exposure.
- **Fix:** scope admin SELECT to users who have a membership/join_request in that admin's libraries.
- **Effort:** Medium

### P5-08 — `WITH CHECK (true)` INSERT policies allow forged rows 🟡 Medium
- **Category:** Security · Integrity
- **Evidence:** `referrals` (`:724-725`), `badges` (`:734-735`), `notifications` (`:775-776`), `audit_log` (`:785-786`) all `FOR INSERT WITH CHECK (true)`.
- **Why it's a problem:** any authenticated client can insert arbitrary badges (fake achievements), referrals (fake reward claims), notifications to other users (spam/phishing), and — if column names were fixed — forged audit entries (defeating the audit's purpose).
- **Fix:** constrain to `service_role` or scope by ownership/`auth.uid()`.
- **Effort:** Small

### P5-09 — `attendance` allows invalid/negative sessions 🟡 Medium
- **Category:** Data Integrity (→ Phase 8)
- **Evidence:** no CHECK that `check_out_time >= check_in_time` or `duration_minutes >= 0`. Offline sync computes `difference(...).inMinutes` (`offline_sync.dart`) and the orphaned-checkout fallback can attach a checkout earlier than a stale check-in → negative duration.
- **Fix:** CHECK `(check_out_time IS NULL OR check_out_time >= check_in_time)` and `duration_minutes >= 0`.
- **Effort:** Small

### P5-10 — Orphan tables fully defined but unused (`transfers`, `member_add_ons`) 🟡 Medium
- **Category:** Dead Schema
- **Evidence:** both have tables + RLS (`:245-256, 271-279, 688-696, 706-715`) but **0** code refs. Confirms P2-03/04 from the DB side: the data model supports add-on purchases and transfers that the app never writes.
- **Fix:** build the features or remove the tables.
- **Effort:** N/A (decision)

### P5-11 — Redundant/contradictory columns & migration sprawl 🟢 Low
- **Evidence:** `expenditures.note` **and** `notes` (`:431-432`, "compatibility column"); multiple overlapping `.sql` files (`indices.sql` re-creates indexes also implied elsewhere). Increases drift risk.
- **Fix:** consolidate; drop redundant column after backfill.
- **Effort:** Small

### P5-12 — Duplicate closure concept (`scheduled_closures` vs `library_closures`) 🟡 Medium
- **Category:** Drift · Contradictory concepts
- **Evidence:** `scheduled_closures` (in schema, used by closures screen + scanner) vs `library_closures` (not in schema, written by "Close Today" `admin_home.dart:3503`). Two tables for one concept; scanner reads only the former.
- **Fix:** consolidate to `scheduled_closures` (single-day = same start/end date). Owns P4-04 root.
- **Effort:** Small

**Positive findings (schema strengths):**
- RLS **enabled on all 25** canonical tables; most policies are correctly ownership-scoped.
- Good `ON DELETE` design: `RESTRICT` on financially/operationally sensitive parents (`libraries.owner_id`, `memberships.library_id/shift_id`, `payments.library_id`), `CASCADE` on children, `SET NULL` on optional FKs.
- Strong unique constraints: `unique_seat_per_library_shift`, `unique_badge_per_member`, `unique_announcement_read`, `reviews UNIQUE(library_id, member_id)`, `users.email/phone UNIQUE`, `libraries.library_code UNIQUE`.
- Triggers: `updated_at` automation; `fn_update_library_rating` keeps `avg_rating`/`review_count` correct on review change.
- Indexes cover the hot paths (member/library/status, attendance by member/date, join_requests by library/status, partial index on non-deleted expenditures).

---

## 6. Schema Drift Register

| Type | Item | Detail | Evidence |
|---|---|---|---|
| Table in code, absent in schema | `settings` | migration exists separately | `admin_settings_migration.sql`; `admin_settings_service.dart` |
| Table in code, absent in schema | `draft_members` | migration exists separately | `draft_members.sql`; `draft_service.dart` |
| Table in code, NO migration | `streaks` | analytics depends on it | `member_analytics_service.dart` |
| Table in code, NO migration | `member_daily_stats` | analytics | `member_analytics_service.dart` |
| Table in code, NO migration | `library_closures` | "Close Today" | `admin_home.dart:3503` |
| Table in code, NO migration | `leads` | explore lead capture | `member_explore_screen.dart:323` |
| Table in code, NO migration | `verification_requests` | verified-badge submit | `verified_badge_screen.dart:176` |
| Table in schema, unused | `transfers` | 0 code refs | `:245`, P2-04 |
| Table in schema, unused | `member_add_ons` | 0 code refs | `:271`, P2-03 |
| Column referenced, absent | `notifications.is_read`, `.created_at` | code inserts them | `requests_sub_tab.dart:392-394` |
| Column referenced, absent | `audit_log.performer_name/category/action_title/action_details` | write+read | `requests_sub_tab.dart:368`, `audit_log_screen.dart:58` |
| Column present, redundant | `expenditures.note` vs `notes` | dual columns | `:431-432` |
| Duplicate concept | closures: `scheduled_closures` vs `library_closures` | two tables | P5-12 |
| Contradictory definitions | `expenditures` ×4 schemas | category/date differ | P5-02 |
| Value drift | expenditure category case | code Title-Case vs schema lowercase | P5-02 |

---

## 7. Data Integrity Audit (per workflow)

| Question | Answer | Evidence |
|---|---|---|
| Can duplicate data be created? | **Yes** — duplicate active memberships (no unique), forged badges/referrals/notifications (P5-08) | P5-06, P5-08 |
| Can invalid states exist? | **Yes** — membership any user can flip to `active`; negative attendance durations | P5-01, P5-09 |
| Can orphan records exist? | Partially mitigated by FKs/CASCADE; but `memberships.seat_id` left stale by seat ops (P4-08) → logical orphan | P4-08 |
| Can inconsistent relationships exist? | **Yes** — membership points at vacant/maintenance/deleted seat; seat occupied_by not synced | P4-08, P5-06 |
| Can revenue become inaccurate? | **Yes** — hardcoded amounts (P4-03) + expense CHECK failures (P5-02) + membership self-edit (P5-01) | P4-03, P5-01/02 |
| Can attendance become inaccurate? | **Yes** — negative durations, offline fake scans discarded, manual/admin_edited taxonomy split | P5-09, P3-03, P4-12 |
| Can memberships become inaccurate? | **Yes** — open UPDATE policy; no dup guard | P5-01, P5-06 |
| Can seat allocation become inaccurate? | **Yes** — no occupancy uniqueness; seat ops desync | P5-06, P4-08 |

---

## 8. RLS & Trust Model

- **App assumes RLS is the only protection** (no server tier, P1-03) — so RLS correctness is load-bearing.
- **Defined & reasonable:** 23/25 tables have scoped policies that match intended access.
- **Defined but dangerous:** `memberships` open UPDATE (P5-01); `users` over-broad admin SELECT (P5-07); four `WITH CHECK(true)` inserts (P5-08).
- **Unverifiable:** the **7 non-schema tables** — if hand-created in the dashboard, their RLS state is unknown. `settings` holds admin configuration; `verification_requests`, `leads` hold PII-ish data. If created without `ENABLE ROW LEVEL SECURITY`, they are **world-readable/writable** to any authenticated client. **Cannot confirm without live DB access (V-01).**
- **If deployed RLS differs from repo:** every Phase 3/4 exploit surface widens or narrows unpredictably; the audit's RLS conclusions are valid only for the committed file.

### 9.5 RLS Coverage Matrix (canonical tables)
| Table | RLS on | SELECT | INSERT | UPDATE | DELETE | Risk |
|---|---|---|---|---|---|---|
| users | ✅ | own + **all-by-any-admin** | anyone | own | none | P5-07 |
| libraries | ✅ | active/own | owner | owner | owner(setup) | ok |
| shifts/floors/sections/seats | ✅ | public read | owner | owner | owner | seats: public read ok |
| memberships | ✅ | own/admin | admin | **ALL (true)** + admin | — | **P5-01** |
| attendance | ✅ | own/admin | member/admin | own/admin | — | ok |
| payments | ✅ | own/admin | member | admin | — | ok |
| join/seat_change/hold_requests | ✅ | own/admin | member | admin | — | ok |
| transfers | ✅ | own/admin | admin | — | — | unused (P5-10) |
| add_ons / member_add_ons | ✅ | public/own | owner/admin | — | — | member_add_ons unused |
| referrals | ✅ | own/admin | **any (true)** | — | — | P5-08 |
| badges | ✅ | own/admin | **any (true)** | — | — | P5-08 |
| announcements/reads | ✅ | scoped | admin/member | admin | — | ok |
| queries | ✅ | own/admin | member | admin | — | ok |
| notifications | ✅ | own | **any (true)** | own | — | P5-08 |
| audit_log | ✅ | admin | **any (true)** | — | — | P5-08 |
| scheduled_closures | ✅ | member/admin | admin | admin | — | ok |
| reviews | ✅ | member/public | member | member/admin | admin | ok |
| expenditures | ✅ | admin | admin | admin | admin | ok (but CHECK breaks insert) |
| **settings, streaks, member_daily_stats, library_closures, leads, verification_requests, draft_members** | **❓ UNVERIFIABLE** | — | — | — | — | **not in schema** |

---

## 9. Required Artifacts

### 9.1 Complete Data Model Map (canonical, with screen refs)
```
users(1)─<owns>─libraries(1)─┬─<has>─shifts─<has>─seats>─occupied_by─users
   │   admin_profile/role     ├─floors─sections─seats   layout_sub_tab
   │                          ├─memberships─┬─attendance   member_home/qr
   │  member_home/detail      │             ├─payments     requests/history
   │                          │             ├─member_add_ons(UNUSED)
   │                          │             ├─seat_change_requests / hold_requests
   │                          │             └─reviews
   │                          ├─join_requests   requests_sub_tab
   │                          ├─add_ons         addon_services
   │                          ├─announcements─announcement_reads
   │                          ├─queries / scheduled_closures / expenditures / audit_log
   │                          └─transfers(UNUSED)
   ├─referrals (referrer/referred)   referral_settings / member_profile
   ├─badges                          member_analytics
   └─notifications                   (writer-only; reader screen = placeholder P3-05)
OFFLINE (sqflite): offline_scan_queue + 5 cache tables (offline_db.dart)
NON-SCHEMA (drift): settings · streaks · member_daily_stats · library_closures · leads · verification_requests · draft_members
```

### 9.2 Schema Drift Register — see §6.

### 9.3 Table Health Scorecard
| Table | Classification | RLS | Integrity risk | Notes |
|---|---|---|---|---|
| users | ACTIVE | ⚠ over-broad SELECT | PII exposure | P5-07 |
| libraries | ACTIVE | ok | low | social_links holds UPI (P4-01) |
| shifts/floors/sections | ACTIVE | ok | low | pricing source (P4-03 should use) |
| seats | ACTIVE | ok | **occupancy not unique** | P5-06 |
| memberships | ACTIVE | ⚠ **open UPDATE** | **critical** | P5-01, P5-06 |
| attendance | ACTIVE | ok | negative durations | P5-09 |
| payments | ACTIVE | ok | wrong amounts (app) | P4-03 |
| join/seat_change/hold_requests | ACTIVE | ok | low | hold reject missing (app) |
| transfers | ORPHANED | ok | — | P5-10 |
| add_ons | ACTIVE | ok | low | — |
| member_add_ons | ORPHANED | ok | — | P5-10/P2-03 |
| referrals | PARTIALLY USED | ⚠ open insert | forge rewards | P5-08, P2-02 |
| badges | ACTIVE | ⚠ open insert | forge badges | P5-08 |
| announcements/reads | ACTIVE | ok | low | works |
| queries | ACTIVE | ok | low | works |
| notifications | DRIFTED | ⚠ open insert | writes fail (cols) | P5-04, P5-08 |
| audit_log | DRIFTED/DEAD | ⚠ open insert | writes+reads fail | P5-05 |
| scheduled_closures | ACTIVE | ok | low | works |
| reviews | ACTIVE | ok | low | trigger-maintained |
| expenditures | DRIFTED | ok | **CHECK breaks insert** | P5-02 |
| settings | UNVERIFIED | ❓ | unknown | drift |
| streaks | UNVERIFIED | ❓ | unknown | no migration |
| member_daily_stats | UNVERIFIED | ❓ | unknown | no migration |
| library_closures | UNVERIFIED | ❓ | unknown | no migration; P4-04 |
| leads | UNVERIFIED | ❓ | unknown | no migration |
| verification_requests | UNVERIFIED | ❓ | unknown | no migration |
| draft_members | DRIFTED | ⚠ (own sql) | unknown | separate migration |

### 9.4 Data Integrity Risk Register
| DIRID | Risk | Severity | Root |
|---|---|---|---|
| DI-01 | Any user rewrites any membership | Critical | P5-01 |
| DI-02 | Expense inserts fail / mis-categorized | Critical | P5-02 |
| DI-03 | Features break on clean deploy (7 tables) | Critical | P5-03 |
| DI-04 | Duplicate memberships / seat double-book | High | P5-06 |
| DI-05 | Cross-tenant PII read | High | P5-07 |
| DI-06 | Forged badges/referrals/notifications/audit | Medium | P5-08 |
| DI-07 | Negative/invalid attendance durations | Medium | P5-09 |
| DI-08 | Notification/audit writes silently fail | High | P5-04/05 |

### 9.5 RLS Coverage Matrix — see §8.

### 9.6 Orphan Table Register
| Table | Reason | Action |
|---|---|---|
| transfers | feature never built (P2-04) | build or drop |
| member_add_ons | add-ons not persisted (P2-03) | wire or drop |

### 9.7 Missing Migration Register
| Table | Migration present? | Action |
|---|---|---|
| settings | `admin_settings_migration.sql` (not in canonical) | fold into schema |
| draft_members | `draft_members.sql` (not in canonical) | fold into schema |
| streaks | ❌ none | author migration |
| member_daily_stats | ❌ none | author migration |
| library_closures | ❌ none | author/replace with scheduled_closures |
| leads | ❌ none | author migration |
| verification_requests | ❌ none | author migration |

### 9.8 Database Trustworthiness Score
**3.5 / 10.** Breakdown: Schema design **7/10** (good FKs/uniques/triggers) · Drift control **1/10** (7 missing tables, 4 expenditure variants, column mismatches) · RLS correctness **3/10** (one critical open-UPDATE, over-broad user SELECT, 4 open inserts, 7 unverifiable tables) · Integrity guarantees **3/10** (no dup/seat-occupancy uniqueness, no attendance CHECK). Weighted → **3.5**.

---

## 10. Cross-Phase Investigation — DB roots of upstream symptoms
| Upstream symptom | DB root cause |
|---|---|
| **False success** (Close Today, Confirm Pay, "member notified") | `library_closures` missing (P5-03/12); notification column drift (P5-04) |
| **Data disappearing** (add-ons, hold not saved) | `member_add_ons` orphan (P5-10); membership writes unguarded (P5-01) |
| **Data not reaching users** (notifications) | `notifications` column drift → inserts fail (P5-04) |
| **Revenue inaccuracies** | hardcoded amounts (P4-03) + expense CHECK breakage (P5-02) + membership self-edit (P5-01) |
| **Notification failures** | P5-04 (columns) + P3-05 (reader) |
| **Audit failures** | P5-05 (columns, both ends) |

---

## 11. Improvement Suggestions
1. **Single source-of-truth schema** — collapse all `.sql` fragments into one migration set; delete contradictory ones; add the 7 missing tables; add a CI check `every .from('x') ⊆ schema tables`.
2. **Fix the membership RLS hole first** (P5-01) — one-line, Critical.
3. **Normalize expenditure categories** (lowercase keys + UI labels) and pick one definition.
4. **Add integrity constraints** — partial uniques for active membership/seat occupancy; attendance CHECKs.
5. **Tighten `WITH CHECK(true)` inserts and the users SELECT policy.**
6. **Verify deployed RLS against the repo** the moment DB access is available (close V-01).

## 12. Priority Fix List (Phase 5)
| # | Item | Severity | Effort |
|---|---|---|---|
| 1 | Restrict `memberships` UPDATE policy to service_role (P5-01) | Critical | Small |
| 2 | One `expenditures` schema + category normalization (P5-02) | Critical | Medium |
| 3 | Author 7 missing-table migrations; unify schema (P5-03) | Critical | Medium |
| 4 | Fix notification/audit columns (P5-04/05) | High | Small/Med |
| 5 | Partial-unique constraints for memberships/seats (P5-06) | High | Medium |
| 6 | Scope `users` admin SELECT (P5-07) | High | Medium |
| 7 | Constrain `WITH CHECK(true)` inserts (P5-08) | Medium | Small |
| 8 | Attendance validity CHECKs (P5-09) | Medium | Small |

---

## 13. Cross-Phase Critical Findings (additions this phase)
| Ref | Sev | Title | Evidence | Effort |
|---|---|---|---|---|
| P5-01 | **Critical** | `memberships` UPDATE RLS open to all authenticated users | `supabase_schema.sql:608-609` | Small |
| P5-02 | **Critical** | 4 conflicting `expenditures` schemas; code categories violate CHECK | `supabase_schema.sql:423-432` vs `add_expense_bottom_sheet.dart:35` | Medium |
| P5-03 | **Critical** | 7 code tables missing from schema; 5 have no migration | grep cross-check | Medium |
| P5-04 | High | `notifications` column drift → inserts fail (root of P4-06/P3-05) | schema `:337` vs `requests_sub_tab:392` | Small |
| P5-05 | High | `audit_log` column drift → write+read fail (root of P4-02) | schema `:348` vs `requests_sub_tab:368`/`audit_log_screen:58` | Medium |
| P5-06 | High | No DB guard vs duplicate memberships / seat double-booking | schema (no partial uniques) | Medium |
| P5-07 | High | `users` RLS exposes all-user PII to any library owner | `:531-532` | Medium |

## 14. Open Questions (additions)
22. Which `expenditures` definition is actually deployed? (determines whether expense insert fails outright) — needs live DB.
23. Do the 7 non-schema tables exist in the live DB, and is RLS enabled on them? — needs live DB (V-01).
24. Is the `memberships` open-UPDATE policy present in the deployed DB as written? — needs live DB (it's the single highest-risk line).

## 15. Verification Pending (additions)
| VID | Item | Method | Phase |
|---|---|---|---|
| V-27 | Confirm deployed RLS matches repo (esp. P5-01) | Live DB introspection | 10 |
| V-28 | Confirm which expenditures schema is live (P5-02) | Live DB / test insert | 8,10 |
| V-29 | Confirm existence + RLS of 7 non-schema tables (P5-03) | Live DB | 10 |
| V-30 | Confirm duplicate-membership/seat possible at runtime (P5-06) | Concurrency test | 13 |

---

*End of Phase 5. No schema or code modified. Stopped; awaiting approval for Phase 6 (API / Data-Access Audit).*
