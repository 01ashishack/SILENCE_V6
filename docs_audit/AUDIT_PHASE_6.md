# SILENCE — Phase 6: API / Data-Access Audit

**Phase:** 6 of 16 — API / Data-Access (Trust-Model) Audit
**Completed (local time):** 2026-06-08
**Auditor roles:** Senior Security Auditor (lead) · Full-Stack Engineer · Data Analyst · QA Lead
**Goal:** Determine whether the data-access layer can be trusted. Trace writes User→Screen→Supabase→DB→outcome; classify every operation by trust boundary; answer whether P1-03/P5-01/P4-03/P3-03/P2-03 are isolated defects or one systemic failure.
**Method:** Static inventory of all 179 write operations + RLS (from `supabase_schema.sql`) + code validation paths. **No DB access** → exploitability is **"appears possible" (Code-Inferred)**, never executed. No exploitation performed.
**Constraint honored:** No code modified.

---

## 1. Executive Summary — One Failure, Many Symptoms

**The answer to the central question is unambiguous: the Phase 1–5 findings are NOT isolated defects. They are symptoms of a single systemic trust-model failure.**

The data-access layer is **179 client-direct write operations** (64 insert · 84 update · 23 delete · 8 upsert), **0 via RPC**, against a backend whose **only server-side logic is `update_updated_at` and a rating trigger — zero validation functions, zero Edge Functions** (`supabase/functions` does not exist). Therefore:

> **The client is the application. The database is a shared, directly-writable store. RLS is the *only* trust boundary — and it is miscalibrated in both directions.**

This produces two failure modes that explain every upstream symptom:

1. **RLS too loose → manipulation possible.** The open `memberships` UPDATE (P5-01), self-set `role:'admin'` (P6-02), self-activated subscription (P6-03), and unvalidated self-check-in (P6-04) let an authenticated member or owner rewrite money, status, identity, and attendance.
2. **RLS too tight → silent broken features.** Member writes the app *issues* but canonical RLS *denies* — payment re-upload (P6-05a) and exit-frees-seat (P6-05b) — fail silently (errors swallowed), leaving desynced data (compounds P4-08).

**Mapping the five named findings to the one root cause:**

| Named finding | Not isolated — it is… |
|---|---|
| **P1-03** client-direct architecture | …the **root cause** itself |
| **P5-01** open membership UPDATE | …RLS-too-loose instance of P1-03 (no server tier to enforce) |
| **P4-03** revenue inaccuracy | …client computes/sends `amount`; nothing validates it (P1-03) |
| **P3-03** offline check-in false success | …client self-reports attendance; no server validation (P1-03) |
| **P2-03** add-ons disappearing | …client omits add-ons from the write; no server contract enforces completeness (P1-03) |

**New Critical/High findings this phase:** systemic trust-model failure (P6-01), role self-escalation → all-PII read (P6-02), subscription self-activation/billing bypass (P6-03), attendance fabrication (P6-04), RLS-denied silent member writes (P6-05), self-verification (P6-06), client-side structural deletes (P6-07).

**Data-access trust classification (179 ops): SERVER-TRUSTED 0 · SAFE 0 · RLS-TRUSTED ~120 (scoped, but unverified vs live DB) · CLIENT-TRUSTED ~45 · UNPROTECTED ~14 · UNVERIFIED (7 non-schema tables).** Not a single write is server-validated.

---

## 2. What Was Reviewed
Every `.from(...).insert/update/delete/upsert` in `lib/` (179 ops), each mapped to source screen, trigger action, target table, validation path, authorization (RLS) path, error handling, retry, and offline behavior; cross-referenced with the canonical RLS and the (absent) server logic.

## 3. Files Reviewed
All write-bearing screens: `requests_sub_tab.dart`, `member_detail_screen.dart`, `layout_sub_tab.dart`, `qr_scanner_screen.dart`, `member_home.dart`, `member_history_tab.dart`, `member_profile_tab.dart`, `member_profile_edit.dart`, `subscription_screen.dart`, `admin_home.dart`, `add_member_wizard.dart`, `join_flow_screen.dart`, `renewal_screen.dart`, `library_setup_stage2/3.dart`, `core/offline_sync.dart`, `core/admin_settings_service.dart`, `services/draft_service.dart`; RLS from `supabase_schema.sql`.

## 4. Screens Reviewed
N/A (cross-cutting). Operation→screen map in §9.1.

---

## 5. Findings

### P6-01 — Systemic trust-model failure: 179 client-direct writes, 0 server validation 🔴 Critical
- **Category:** Architecture · Security · Integrity (meta-finding)
- **Evidence:** 64 insert / 84 update / 23 delete / 8 upsert across `lib/`; `0` `.rpc(`; no `supabase/functions`; only `update_updated_at_column` + `fn_update_library_rating` triggers (`supabase_schema.sql:16,392`). Every business rule (discount caps, dues, hold limits, seat occupancy, payment amount, attendance validity) is computed client-side or not at all.
- **Why it's a problem:** there is no trusted boundary between the user and their data. RLS can only express *row ownership*, not *business validity* (it cannot check "amount equals plan price minus a capped discount" or "no overlapping active membership"). So the rules the product depends on are unenforceable.
- **Appears possible (Code-Inferred):** a scripted client using the shipped anon key (P0-08) performs any write RLS permits, skipping all UI validation.
- **Fix:** move money/seat/lifecycle/attendance transactions to Postgres RPC/Edge Functions; tighten RLS to deny direct writes to those tables; keep reads client-direct.
- **Effort:** Large

### P6-02 — Role self-escalation (member→admin) → all-user PII read 🔴 Critical
- **Category:** Authorization · Privilege Escalation
- **Evidence:** `member_profile_tab.dart:1437` `from('users').update({'role':'admin'}).eq('id', user.id)`; `users` RLS "Users can update own profile" has **no column restriction** (`supabase_schema.sql:534-535`). Once `role='admin'`, the "Admins can view all users" policy (P5-07, `:531-532`) grants SELECT on **every** user's PII.
- **Why it's a problem:** the UI exposes a "switch to owner" button, but the underlying permission is column-unrestricted — any client can set `role:'admin'` and then read the entire user base (emails, phones, DOB, `id_proof_url`, addresses).
- **Appears possible:** member taps switch (or crafts the update) → becomes admin → enumerates all users.
- **Fix:** restrict updatable columns (deny `role`, `subscription_*`, `verified` on self-update via a trigger/RPC); scope admin SELECT to own members (P5-07).
- **Effort:** Medium

### P6-03 — Subscription self-activation without payment (billing bypass) 🔴 Critical
- **Category:** Commerce · Authorization
- **Evidence:** `subscription_screen.dart:287` sets `subscription_plan:'pro', subscription_status:'active'` after the **mocked** payment (P0-01); `admin_home.dart:973` self-sets `starter/active`. RLS allows self-update of own `users` row.
- **Why it's a problem:** admins grant themselves any paid tier for free; even when real billing exists, the client writes the entitlement directly with nothing to verify a payment occurred.
- **Appears possible:** owner (or crafted request) sets `subscription_status:'active'`, `subscription_plan:'pro'` indefinitely.
- **Fix:** entitlement must be written only by a server verifying a real payment (webhook/Edge Function); deny client writes to `subscription_*`.
- **Effort:** Medium (after payments exist)

### P6-04 — Attendance fabrication: unvalidated self-insert with client timestamps 🟠 High
- **Category:** Integrity · Gamification fraud
- **Evidence:** `qr_scanner_screen.dart:417` and `offline_sync.dart:102` insert `attendance` with member-supplied `check_in_time`, `qr_version`, `offline_synced`, `device_id`; RLS "Member insert (check-in/out)" only checks `member_id = auth.uid()` (`:618-619`). No server check of membership validity, library QR, closure, or time plausibility.
- **Why it's a problem:** streak, total hours, leaderboard, and badges (P5-08 lets badges be forged too) all derive from a table the member can write arbitrarily.
- **Appears possible:** scripted client inserts months of back-dated sessions → tops leaderboard, earns badges, inflates hours.
- **Connect:** this is the *write-side* of P3-03 (offline fake success) — the data layer cannot tell a real scan from a crafted one.
- **Fix:** check-in via RPC that validates membership/QR/closure/time and stamps server time.
- **Effort:** Large

### P6-05 — RLS-denied member writes fail silently (broken features + desync) 🟠 High
- **Category:** Authorization mismatch · Silent Failure
- **Evidence (a):** `member_history_tab.dart:2743` — member updates `payments` (reupload sets `status:'pending'`). Canonical `payments` RLS has **no member UPDATE** policy (`:632-644`) → denied.
- **Evidence (b):** `member_home.dart:5180` — member exit updates `seats` (`status:'vacant'`). `seats` UPDATE is **owner-only** (`:584-586`) → denied.
- **Why it's a problem:** the app issues writes the policy forbids; the errors are swallowed (Phase 3/4 pattern) → the member believes reupload/exit worked, but the payment stays rejected and the **seat stays occupied** (compounds P4-08 desync; a "exited" member still holds a seat in `seats`).
- **Appears possible:** confirmed by RLS reading; runtime-pending (V-31).
- **Fix:** route these via admin action or an RPC with appropriate authority; surface failures.
- **Effort:** Medium

### P6-06 — Self-verification of phone/email 🟠 High
- **Category:** Trust · Authorization
- **Evidence:** `member_profile_edit.dart:509,520` set `phone_verified:true`/`email_verified:true` on the member's own `users` row (after mock OTP, P0-04); RLS permits self-update.
- **Why it's a problem:** the "verified" trust signals are self-asserted; duplicate-account prevention and any trust feature relying on them are meaningless.
- **Fix:** set verification flags only server-side after a real OTP challenge.
- **Effort:** Medium

### P6-07 — Client-side deletes of structural data (orphan risk) 🟡 Medium
- **Category:** Integrity
- **Evidence:** client `delete()` on `seats`(×5), `sections`(×3), `floors`(×2), `add_ons`, `scheduled_closures`, `join_requests`, `expenditures`, `draft_members`. `seats`/`add_ons` deletes have **no occupancy/reference guard** (P5-06); deleting an occupied seat or a purchased add-on orphans `memberships.seat_id`/financial history.
- **Fix:** guard deletes (block if referenced) — ideally server-side.
- **Effort:** Medium

**Positive notes:** most *read* paths and many writes are correctly RLS-scoped by ownership (join/seat-change/hold requests, queries, reviews, announcements). The schema's intent is sound; the failure is the absence of a server tier to enforce *business* rules and the two miscalibrated policies.

---

## 6. Trust Boundary Audit (per workflow)

| Workflow | What's trusted | Should it be? | Modified client bypass? | Direct REST bypass? | Member can manipulate? |
|---|---|---|---|---|---|
| Join approval | client (admin) writes membership/seat/payment | No | Yes | Yes | member can't approve (RLS), but admin client unbounded |
| Membership activation/renewal | client sets status/dates | **No** | **Yes (P5-01)** | **Yes** | **Yes — self-extend** |
| Attendance | client self-reports | **No** | **Yes** | **Yes** | **Yes — fabricate (P6-04)** |
| Seat assignment | client sets seat/occupancy | No | Yes | Yes | partial (P5-01 seat_id) |
| Payment verification | client sets `status:'confirmed'` (admin) | No | Yes | Yes | member reupload denied (P6-05a) |
| Referral rewards | client (never credits anyway) | No | Yes | Yes | forge `referrals` (P5-08) |
| Add-ons | client omits them (P2-03) | No | Yes | Yes | n/a (data lost) |
| Holds | client sets status/extends expiry | No | Yes | Yes | self-approve via P5-01 |
| Closures | client writes (wrong table P4-04) | No | Yes | Yes | n/a |
| Queries/Reviews | RLS-scoped | mostly | limited | limited | own rows only |
| Notifications | `WITH CHECK(true)` insert | No | Yes | Yes | spam others (P5-08) |
| Role/Subscription/Verify | client self-set | **No** | **Yes** | **Yes** | **Yes (P6-02/03/06)** |

---

## 7. Critical Investigation — "dangerous if…" (per the brief)

| Condition | Operations that become dangerous |
|---|---|
| **Client is modified** | membership update (P5-01), role/subscription/verify self-set (P6-02/03/06), attendance insert (P6-04), payment amount (P4-03), discount/hold beyond caps |
| **Requests replayed** | attendance inserts (duplicate sessions, P5-06/P5-09), notification/badge/referral inserts (forge, P5-08), payment inserts |
| **Requests crafted manually** | every write RLS permits — esp. memberships, attendance, users.role, users.subscription |
| **RLS differs from repo** | all 7 non-schema tables (settings/streaks/leads/verification_requests…) — if RLS off, world-writable; and any policy weaker than repo widens the above |
| **Validation skipped** (it's client-only) | discount caps, dues block, hold limits, trial-once, duplicate-phone, seat occupancy, payment amount, expense category — **all** business rules (none are server-enforced) |

---

## 8. User Abuse Simulation (appears-possible; not executed)

| Persona | Plausible action | Enabled by |
|---|---|---|
| Curious user | read own data, notice client writes | baseline |
| **Malicious member** | extend own membership; mark active; fabricate attendance/streak; forge badges; self-verify; become admin then read all PII | P5-01, P6-02/04/06, P5-08, P5-07 |
| **Library owner abusing privilege** | self-grant Pro subscription free; read entire platform's user PII; forge audit-free actions | P6-03, P5-07, P4-02 |
| **Scripted client** | bulk-insert attendance/notifications; mass-craft memberships | P1-03, P6-04, P5-08 |
| **Replayed request** | duplicate payments/attendance; re-trigger writes | no idempotency, P5-06 |
| **Offline manipulation** | queue arbitrary scans; fake success locally; sync writes unvalidated | P3-03, P6-04 |

---

## 9. Required Artifacts

### 9.1 API / Data-Access Map (write ops by table → screens)
```
users        : ins×3 update×20 — auth, profile edits, role-switch(P6-02), subscription(P6-03), verify(P6-06), add-member
libraries    : ins×2 update×16 — setup S1-3, profile, UPI(social_links), branding
shifts/floors/sections/seats : setup + layout (owner); seats also written by approval/exit/manual
memberships  : ins×2 update×5 — approval, renewal, hold, exit, transfer(unused) — OPEN UPDATE (P5-01)
attendance   : ins×4 update×4 — qr scan(member self), offline_sync, manual(admin) — UNVALIDATED (P6-04)
payments     : ins×2 update×3 — approval(admin, hardcoded amt P4-03), reupload(member→DENIED P6-05a)
join/seat_change/hold_requests : member insert / admin update (scoped)
add_ons      : ins×1 (admin) ; member_add_ons : NONE (P2-03)
referrals/badges/notifications : WITH CHECK(true) inserts — forgeable (P5-08)
audit_log    : ins×2 — one valid(join_flow), one broken-columns(requests P4-02)
expenditures : ins×2 update×1 delete×1 — category CHECK breakage (P5-02)
leads/verification_requests/settings/streaks/... : non-schema tables (P5-03, UNVERIFIED)
```

### 9.2 Trust Boundary Matrix — see §6.

### 9.3 Validation Coverage Matrix
| Workflow | UI | Client code | DB constraint | RLS | Server logic | Verdict |
|---|---|---|---|---|---|---|
| Join approval | ✔ | ✔ (seat recheck) | partial | scoped | ✘ | client-trusted |
| Renewal/activation | ✔ | partial | enum only | **open (P5-01)** | ✘ | **unprotected** |
| Attendance | ✔ | partial | none (P5-09) | own-id only | ✘ | **unprotected** |
| Payment amount | ✘ | hardcoded (P4-03) | NOT NULL only | scoped | ✘ | wrong-by-design |
| Discount cap | ✔ (sometimes) | ✘ | ✘ | ✘ | ✘ | **missing** |
| Hold limits | ✘ | ✘ | ✘ | ✘ | ✘ | **missing** |
| Trial-once | ✘ | ✘ | bool flag only | ✘ | ✘ | **missing** |
| Duplicate-phone | partial | partial | unique(phone) | ✘ | ✘ | partial |
| Seat occupancy | ✔ | racy | def-unique only | scoped | ✘ | **race-prone (P5-06)** |
| Expense category | ✔ dropdown | ✘ | CHECK (breaks, P5-02) | scoped | ✘ | broken |

### 9.4 Authorization Coverage Matrix
| Table | Member write | Admin write | Over-grant | Under-grant |
|---|---|---|---|---|
| memberships | **ALL via P5-01** | scoped | **P5-01** | — |
| users | own (incl. role/sub/verify) | own members read-all (P5-07) | **P6-02/03/06, P5-07** | — |
| payments | insert only | update status | — | **member reupload denied (P6-05a)** |
| seats | — | owner | — | **member exit-free denied (P6-05b)** |
| attendance | insert/update own | admin | **no validation (P6-04)** | — |
| notifications/badges/referrals/audit_log | insert (true) | — | **forgeable (P5-08)** | — |

### 9.5 Abuse Scenario Register — see §8.

### 9.6 Direct-Write Risk Register
| DWID | Operation | Class | Risk | Root |
|---|---|---|---|---|
| DW-01 | `memberships.update` any row | UNPROTECTED | self-extend/activate/seat-steal | P5-01 |
| DW-02 | `users.update role` | CLIENT-TRUSTED | escalate→all PII | P6-02/P5-07 |
| DW-03 | `users.update subscription_*` | UNPROTECTED | free Pro | P6-03 |
| DW-04 | `attendance.insert` | CLIENT-TRUSTED | streak/hours fraud | P6-04 |
| DW-05 | `users.update *_verified` | CLIENT-TRUSTED | fake verification | P6-06 |
| DW-06 | `badges/referrals/notifications.insert (true)` | UNPROTECTED | forge/spam | P5-08 |
| DW-07 | `payments.insert` amount | CLIENT-TRUSTED | wrong revenue | P4-03 |
| DW-08 | `seats/add_ons.delete` | CLIENT-TRUSTED | orphan/financial loss | P6-07 |
| DW-09 | member `payments/seats.update` | UNDER-GRANTED | silent broken feature | P6-05 |

### 9.7 Business Rule Enforcement Matrix
| Rule (06_Business_Rules.csv) | Enforced where | Verdict |
|---|---|---|
| max_discount_percent | nowhere (server) | **NOT enforced** (→Phase 7) |
| max_hold_days / max_holds | nowhere | **NOT enforced** |
| exit_dues_block | member UI only (admin bypasses, P4-09) | **partial** |
| trial_once_per_member | nowhere | **NOT enforced** |
| allow_expired_checkin | client UI (FAB) only, scanner inconsistent (P3-04) | partial |
| auto_checkout / auto_hold | not implemented (no server) | **missing** |
| referral reward conditions | never credited | **missing (P2-02)** |
| payment amount = price − discount | hardcoded (P4-03) | **wrong** |
| seat single-occupancy | racy client check | **not guaranteed (P5-06)** |
| **All rules** | **no server tier** | **client-only or missing** |

---

## 10. Data-Access Classification Summary
- **SERVER-TRUSTED:** 0
- **SAFE (immutable/validated):** 0
- **RLS-TRUSTED (ownership-scoped, *unverified vs live DB*):** ~120 ops (reads + scoped writes: requests, queries, reviews, announcements, library/shift/seat owner writes)
- **CLIENT-TRUSTED (RLS allows, no validation):** ~45 (attendance, role/sub/verify self-set, payment amount, discounts)
- **UNPROTECTED (open/forgeable):** ~14 (memberships update, `WITH CHECK(true)` inserts)
- **UNVERIFIED (non-schema tables):** all writes to settings/streaks/leads/verification_requests/etc.

---

## 11. Connect-Back: isolated defects or systemic? → **Systemic**
All five named findings reduce to **P1-03 (no server tier) + RLS-as-sole-boundary**:
- **P5-01** = RLS-too-loose under P1-03.
- **P4-03** = client sends money value; P1-03 means nothing checks it.
- **P3-03** = client self-reports attendance; P1-03 means nothing validates it (P6-04 is its write-side).
- **P2-03** = client controls the write payload; P1-03 means no contract enforces completeness.
**Conclusion:** fixing them individually is whack-a-mole; the durable fix is a **server-validated transaction tier** + RLS recalibration.

## 12. Improvement Suggestions
1. **Introduce RPC/Edge transactions** for: check-in, approve, renew, hold (approve/reject), seat assign/reassign/release, payment-confirm, subscription entitlement, referral credit. Make these the *only* writers to memberships/payments/attendance/seats; RLS denies direct client writes there.
2. **Recalibrate RLS:** close P5-01; column-restrict `users` self-update (deny role/subscription/verified); scope admin user-SELECT; constrain `WITH CHECK(true)` inserts.
3. **Add idempotency keys** to payment/attendance writes (replay defense).
4. **Surface RLS-denied writes** instead of swallowing (fixes the silent P6-05 failures).

## 13. Priority Fix List (Phase 6)
| # | Item | Severity | Effort |
|---|---|---|---|
| 1 | Server tier for money/seat/lifecycle/attendance (P6-01) | Critical | Large |
| 2 | Deny self-set of role/subscription/verified (P6-02/03/06) | Critical | Medium |
| 3 | Close membership open-UPDATE (P5-01) | Critical | Small |
| 4 | Validate attendance server-side (P6-04) | High | Large |
| 5 | Fix/route RLS-denied member writes (P6-05) | High | Medium |
| 6 | Constrain forgeable inserts (P5-08) | Medium | Small |
| 7 | Guard structural deletes (P6-07) | Medium | Medium |

---

## 14. Cross-Phase Critical Findings (additions this phase)
| Ref | Sev | Title | Evidence | Effort |
|---|---|---|---|---|
| P6-01 | **Critical** | Systemic trust-model failure: 179 client-direct writes, 0 server validation | grep (179 writes, 0 rpc, no functions dir) | Large |
| P6-02 | **Critical** | Role self-escalation member→admin → all-user PII read | `member_profile_tab.dart:1437` + `:531-532` | Medium |
| P6-03 | **Critical** | Subscription self-activation without payment (billing bypass) | `subscription_screen.dart:287`, `admin_home.dart:973` | Medium |
| P6-04 | High | Attendance fabrication via unvalidated self-insert | `qr_scanner_screen.dart:417`, `offline_sync.dart:102` | Large |
| P6-05 | High | RLS-denied member writes fail silently (payment reupload, exit-free seat) | `member_history_tab.dart:2743`, `member_home.dart:5180` | Medium |
| P6-06 | High | Self-verification of phone/email | `member_profile_edit.dart:509,520` | Medium |

## 15. Open Questions (additions)
25. Is the role-switch (member↔admin) an intended product feature, and if so should it remain client-writable? (security vs UX)
26. Does deployed RLS actually deny the member payment/seat writes (P6-05), or is it more permissive? — needs live DB.

## 16. Verification Pending (additions)
| VID | Item | Method | Phase |
|---|---|---|---|
| V-31 | Confirm member payment/seat writes are RLS-denied at runtime (P6-05) | Live DB / device | 10,13 |
| V-32 | Confirm membership/attendance/role writes succeed via crafted REST (P6-01/02/04) | Authorized pen-test only | 10 |
| V-33 | Confirm subscription self-write persists (P6-03) | Live DB | 10 |

---

*End of Phase 6. No code modified. Stopped; awaiting approval for Phase 7 (Business Logic Audit).*
