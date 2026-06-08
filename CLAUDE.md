# CLAUDE.md — SILENCE Project Memory & Audit Handoff

> **Purpose of this file.** This is the single source of truth a *new* Claude Code session
> reads first. It captures the full context of the 16-phase production-readiness audit
> completed on **2026-06-08**, links to every detailed report, and states **exactly what to
> do next**. If the chat session that produced the audit is deleted, this file lets the next
> session pick up without re-deriving anything.
>
> **Read order for a fresh session:** (1) this file → (2) `docs_audit/AUDIT_PHASE_16.md`
> (the consolidated verdict + roadmap) → (3) the specific phase report(s) for whatever you're
> about to work on.

---

## 0. TL;DR — Status & Next Action

- **What this is:** SILENCE — a Flutter + Supabase library / study-space management app for
  Indian Tier-2/3 cities (admins manage seats/members/attendance/payments/analytics; members
  track attendance, streaks, leaderboard, membership).
- **What just happened:** A full 17-report audit (Phases 0–16) was completed. **Audit only —
  no application code was modified at any point.**
- **The verdict:** **~2.5 / 10 production-readiness. NO-GO for public or paid release.**
- **Findings:** **22 Critical · 68 High · 63 Medium · 22 Low** (175 defects) + 38 capability
  gaps. ~90% of all findings trace to **5 root causes** (see §4).
- **The next action (when the user says "continue" / "start fixing"):** Begin **Wave 0 —
  Stop-the-bleeding** (see §5). It is mostly small RLS/storage/config changes and removes the
  PII-breach + deploy-breaking + build blockers, unlocking a controlled pilot. **Wave 0 is the
  first thing to do, and it is the cheapest high-impact work.**
- **The one architectural investment that fixes most of the board:** build a **server-side
  tier** (RPC / Supabase Edge Functions + precompute). This is Root Cause RC-1.

> ⚠️ **Before writing any code:** the audit was deliberately read-only. Starting remediation
> means changing that mode. Confirm with the user which Wave / which findings to fix, then make
> the change set small and reviewable (Wave 0 items are independent and can land one at a time).

---

## 1. Project Snapshot (verified facts)

| Attribute | Finding | Source of truth |
|---|---|---|
| Product | SILENCE — Library & study-space management (India, Tier 2/3) | `silence_app/01_Project_Brief.md` |
| Frontend | Flutter (Dart), Material 3, ~66 screen files, ~74.6k LOC | `lib/`, `pubspec.yaml` |
| Architecture | **Single-tier "fat client"** — no service/repo layer, no DI, no state-mgmt framework; 672 `setState` calls; `Supabase.instance.client` re-instantiated in 116 locations | `lib/main.dart`, Phase 1 report |
| Backend | Supabase (PostgreSQL + Auth + Storage), 25 tables | `silence_app/supabase_schema.sql` (~835 lines) |
| Data access | Direct client REST (`.from(...)`), **0 RPC / 0 Edge Functions** despite spec; **179 client-direct writes, 0 server-side validation** | Phase 6 report |
| Offline | `sqflite` local DB `silence_offline.db`; scan queue + read caches | `lib/core/offline_db.dart`, `lib/core/offline_sync.dart` |
| Roles | Admin (library owner) · Member (student) | `lib/screens/role_selection_screen.dart` |
| Payments | **Mocked** — no Razorpay SDK; `Future.delayed` simulation; hardcoded/placeholder UPI | `lib/screens/subscription_screen.dart` |
| Notifications | **No FCM/push**; notifications screen is a hardcoded "all caught up" stub | Phase 9 report |
| Auth | Supabase Auth; **email/phone OTP verification is mocked UI** | Phase 0/10 reports |
| Tests | One file only: `test/widget_test.dart` | `test/` |
| Secrets | Hardcoded Supabase anon key committed in `lib/core/supabase_config.dart` | Phase 1/10 reports |
| Build | Release build is **debug-signed** and **missing `INTERNET` permission** in release manifest | Phase 1/14 reports |

---

## 2. Audit Document Map (path links)

All paths are **relative to the repo root** (`SILENCE_V6/`). Use these so links work regardless
of the absolute checkout path.

### Master & consolidated
- **`docs_audit/AUDIT_ROADMAP.md`** — the master plan: phase definitions, severity model,
  per-phase deliverable format, execution-order DAG, working protocol.
- **`docs_audit/AUDIT_PHASE_16.md`** — ⭐ **READ THIS SECOND.** Final consolidated report:
  executive summary, posture scorecard, the 21-critical register, 5 root causes, release
  verdict per channel, and the **Wave 0–4 remediation roadmap**.

### Phase reports (each is the detailed source of truth for its area)

| Phase | Area | One-line takeaway | Report |
|---|---|---|---|
| 0 | Product Understanding | Broad, UI-complete surface; several documented-as-done features are mocked | `docs_audit/AUDIT_PHASE_0.md` |
| 1 | Architecture | Single-tier fat client; no layering/DI; god files; debug-signed build | `docs_audit/AUDIT_PHASE_1.md` |
| 2 | Feature Mapping | Wide surface but ~60% hollow; loops broken at the "last mile" | `docs_audit/AUDIT_PHASE_2.md` |
| 3 | Member Flow | Money & check-in flows mislead; fail-open gates; placeholder UPI | `docs_audit/AUDIT_PHASE_3.md` |
| 4 | Admin Flow | False-success ops (Close-Today, Confirm-Pay); audit log broken both ends | `docs_audit/AUDIT_PHASE_4.md` |
| 5 | Database | RLS holes, schema drift, missing tables/uniques, `expenditures` conflicts | `docs_audit/AUDIT_PHASE_5.md` |
| 6 | API / Data-Access | One systemic trust-model failure: 179 client writes, 0 server validation | `docs_audit/AUDIT_PHASE_6.md` |
| 7 | Business Logic | Of ~26 rules: 0 server-enforced; ~17 documented-only/broken/contradictory | `docs_audit/AUDIT_PHASE_7.md` |
| 8 | Calculations / Accuracy | Arithmetic mostly correct but wrong-by-construction (fabricated inputs, TZ-broken clock) | `docs_audit/AUDIT_PHASE_8.md` |
| 9 | UI/UX (Trust) | "Beautiful-lie" — confidence ≫ capability; fake "paid", fake "all caught up" | `docs_audit/AUDIT_PHASE_9.md` |
| 10 | Security | ⚠️ **1.5/10.** Porous RLS; PII/ID docs exposed; self-asserted identity; self-escalation | `docs_audit/AUDIT_PHASE_10.md` |
| 11 | Performance / Scale | Thick-client recompute; analytics full-history scans freeze at scale | `docs_audit/AUDIT_PHASE_11.md` |
| 12 | Error Handling | Silent-failure default; 48 empty catches, 164 swallow-and-log; no global handler/telemetry | `docs_audit/AUDIT_PHASE_12.md` |
| 13 | QA / Edge Cases | 13/15 personas hit a failure; ~0 recovery; duplicates/races have no DB guard | `docs_audit/AUDIT_PHASE_13.md` |
| 14 | Store Readiness | Not submittable; iOS location crash; debug signing; honest Data Safety form impossible | `docs_audit/AUDIT_PHASE_14.md` |
| 15 | Missing Features | ~60% of a viable V1; spine (ops + trust) missing; 38 capability gaps (MC-01…MC-38) | `docs_audit/AUDIT_PHASE_15.md` |
| 16 | **Consolidated Report** | The capstone — verdict, root causes, Wave 0–4 roadmap | `docs_audit/AUDIT_PHASE_16.md` |

> **Phase order note:** Phase 14 was deferred and completed *after* Phase 16. Therefore Phase
> 14 carries the **latest cumulative totals (22 C · 68 H · 63 M · 22 L)**, while the body of
> Phase 16 still shows the pre-Phase-14 numbers (21 C · 64 H · 60 M · 21 L). When citing totals,
> use the Phase-14 numbers.

### Supporting / pre-audit docs (context, not findings)
- `docs_audit/CURRENT_PRD.md`, `docs_audit/CURRENT_STATE.md` — pre-audit product/state snapshots
- `docs_audit/FEATURE_MATRIX.md`, `docs_audit/KNOWN_GAPS.md` — early gap registers
- `docs_audit/SCREEN_MATRIX.md`, `docs_audit/UPDATED_Screen_Inventory.csv`, `screen_inventory.csv` (repo root)
- `docs_audit/UPDATED_Business_Rules.csv`, `docs_audit/DOCUMENTATION_DELTA.md`
- `FINAL_FIX_AUDIT.md`, `FINAL_REMAINING_FIXES.md`, `CHANGES_APPLIED.md` (repo root) — prior fix logs

### Original product spec (the "what it should be")
- `silence_app/` — the authoritative spec set: `01_Project_Brief.md`, `06_Business_Rules.csv`,
  `07_Workflows.yaml`, `SILENCE_PRD_v6.1_Final.md`, `supabase_schema.sql`, `05_RLS_Rules.json`,
  `17_API_Endpoints.md`, `08_Razorpay_Spec.md` (⚠️ empty/0-byte), `16_Design_System.json`, etc.

---

## 3. The 22 Critical Findings (consolidated register)

From `docs_audit/AUDIT_PHASE_16.md` §4 (+ Phase 14). Effort and target Wave shown. Open the
named phase report for full evidence (`file:line`), root cause, exploitation scenario, and fix.

| # | ID | Title | Effort | Wave |
|---|---|---|---|---|
| 1 | P10-01 | "Private" bucket not owner-scoped → any user reads all ID/payment docs | Small | 0 |
| 2 | R-01 / P10-02 | Sensitive PII in **PUBLIC** bucket → readable with no login | Medium | 0 |
| 3 | P10-03 | Storage world-writable/deletable (tamper/DoS) | Small | 0 |
| 4 | P10-04 | Any user reads entire `users` table via creating a library | Small | 0 |
| 5 | P5-01 / P10-05 | `memberships` UPDATE open to all (free/sabotage) | Small | 0 |
| 6 | P6-02 | Role self-escalation member→admin | Medium | 0 |
| 7 | P6-03 | Subscription self-activation (billing bypass) | Medium | 0/1 |
| 8 | P6-01 / P10-08 | **No server tier; RLS is sole, porous control (ROOT)** | Large | 1 |
| 9 | P0-01 | Payments fully mocked; no SDK | Large | 1 |
| 10 | P9-02 | Subscription payment theatre + fabricated invoice | Large | 1 |
| 11 | P3-01 | Members pay hardcoded placeholder UPI (money lost) | Small | 1 |
| 12 | P4-01 | Admin UPI stored but never consumed (false "configured") | Small | 1 |
| 13 | P4-03 | Approval hardcodes amount; ignores price + discount | Small | 1 |
| 14 | P4-02 | Audit log broken on write AND read | Medium | 1/2 |
| 15 | P9-01 | Notifications screen hardcoded "all caught up" stub | Medium | 1 |
| 16 | P5-03 | 7 code tables missing from schema; 5 no migration → clean deploy breaks | Medium | 0 |
| 17 | P5-02 | 4 conflicting `expenditures` schemas; Title-Case violates CHECK → inserts fail | Medium | 0 |
| 18 | P8-01 | Three contradictory "which day" defs → TZ-broken metrics | Medium | 2 |
| 19 | P11-01 | Analytics fast-path tables absent → full-history scans every open | Large | 2 |
| 20 | P11-02 | Badge engine N+1 (6-month + 4-week loops, library-wide scans) | Large | 2 |
| 21 | P1-01 / P1-02 | Release manifest missing INTERNET + debug-signed build | Small | 0 |
| 22 | P14-03 | iOS crashes on a core screen (location) before review concludes | — | 0/1 |

---

## 4. Five Root Causes (~90% of all findings)

From `docs_audit/AUDIT_PHASE_16.md` §5. **Fix these five, in this order, and most of the board
clears.**

1. **RC-4 — Self-asserted identity & permissive RLS/storage** → PII breach, escalation, tamper.
   *Fix:* object-scoped storage + least-privilege RLS + lock identity columns. **(Wave 0)**
2. **RC-3 — Schema drift / missing tables & constraints** → broken inserts, dead fast-paths,
   duplicates, deploy failures. *Fix:* migrations + uniques + precompute tables. **(Wave 0/2)**
3. **RC-1 — No server-side tier** (0 RPC/Edge; 179 client-direct writes) → every security hole,
   perf wall, missing automation, no idempotency, no integrity enforcement. *Fix:* build
   RPC/Edge tier + precompute (the master unlock). **(Wave 1)**
4. **RC-2 — Money is mocked** (no SDK; hardcoded UPI/amounts) → fake revenue, disputes, lost
   payments. *Fix:* real payment + webhook verification; derive amounts server-side. **(Wave 1)**
5. **RC-5 — Dishonest UX + silent failure** → false success, hidden errors, broken
   notifications, wrong analytics. *Fix:* honest status, real notifications, telemetry, one IST
   clock. **(Wave 1/2)**

**Fix order mnemonic:** RC-4 (lock the data) → RC-3 (make it deploy) → RC-1 (build the server
tier) → RC-2 (make money real) → RC-5 (make it honest).

---

## 5. Remediation Roadmap — what to do next (Waves)

From `docs_audit/AUDIT_PHASE_16.md` §7. **Start at Wave 0.** Each item links to its finding ID;
open the relevant phase report for the implementation example.

### Wave 0 — Stop-the-bleeding (days; mostly small policy/config) → unlocks a safe pilot
1. **Storage object-scoping** (P10-01/02/03): private bucket read/write/delete scoped to owner;
   move all PII off the public bucket.
2. **Tenant-scope `users` SELECT + gate library creation** (P10-04).
3. **Remove `memberships` `true/true` UPDATE** + open `WITH CHECK(true)` inserts on
   notifications/audit/badges/referrals (P5-01 / P10-05/10/11/12).
4. **Lock client writes to `role` / `subscription_*` / `*_verified`** columns (P6-02/06, P10-06/07).
5. **Schema deploy fixes:** add the 5 missing-migration tables; reconcile `expenditures` schema +
   category case (P5-02/03).
6. **Build:** real release keystore + add `INTERNET` to release manifest (P1-01/02). Also address
   iOS location crash (P14-03) before any TestFlight.

### Wave 1 — The spine (weeks; Large) → public-free becomes conceivable
7. **Server tier** (RPC/Edge + `SECURITY DEFINER`) for all privileged mutations (P6-01 / P10-08). *RC-1.*
8. **Real payments + webhook verification**; derive amounts server-side from plan + capped
   discount (P0-01 / P9-02 / P3-01 / P4-01 / P4-03 / P6-03). *RC-2.*
9. **Real identity verification** (email confirm + phone OTP) (P10-13). *RC-5.*
10. **Working notifications** (in-app center + push) (P9-01). *RC-5.*

### Wave 2 — Correctness & resilience (weeks)
11. **Analytics precompute** (daily-stats + streaks + badges-on-write) (P5-03 / P8-02 / P11-01/02).
12. **One IST clock** + duration policy (P8-01/04/05).
13. **DB uniqueness + idempotency**; concurrency-safe seats; transactional multi-step writes (P13-01/02/05).
14. **Global error handler + session recovery + telemetry**; kill silent swallow; network retry (P12-01/02/04).
15. **Working, immutable audit log** (P4-02 / P10-11).

### Wave 3 — Operability & retention (Phase-15 P1 layer)
16. Saved payment / 1-tap renewal · renewal reminders · member self-service + status tracker · query inbox.
17. Admin bulk ops · automation (auto-checkout/hold/expiry) · refund/dispute workflow · real reporting.
18. Staff/sub-admin roles · referral crediting · add-on billing · member transfer.

### Wave 4 — Scale & roadmap
19. Server search + pagination · multi-branch console · offline-first idempotent sync · account deletion/data export.
20. WhatsApp notifications · GST invoicing · study planner · public API.

---

## 6. Release-Readiness Verdict (per channel)

| Channel | Verdict | Gate |
|---|---|---|
| Internal / investor demo | ✅ GO | already demos well; disclose "simulated payments" |
| Controlled closed pilot | ⚠️ CONDITIONAL | **only after Wave 0** (storage/RLS + deploy + build). Real-PII exposure makes a pilot with real member IDs unsafe until then |
| Public free release | ❌ NO-GO | requires Waves 0–2 (security + spine + correctness); DPDP breach risk |
| Paid / production | ❌ NO-GO | requires Waves 0–3 (incl. real payments + operability) |

> **Legal flag:** exposing identity documents + contact data (P10-01/02/04) is a reportable
> personal-data breach under India's **DPDP Act** — a legal, not just engineering, blocker.

---

## 7. Important Constraints & Caveats for the Next Session

- **The audit modified no code.** If you see git diffs in `lib/`, they are *new work*, not audit
  artifacts. The audit's only outputs are the `docs_audit/AUDIT_PHASE_*.md` files.
- **Declared limitations (whole audit):** no live Supabase project (RLS/storage audited from
  *committed* SQL files, not the running DB), no on-device render, no profiler/load-test, no
  fault injection. **50 "Verification-Pending" items (V-01…V-53)** require live DB / device /
  load-test to confirm — see each phase report. Do **not** trust "fixed" status on these without
  the corresponding live verification.
- **28 Open Questions** remain across phases (product/spec ambiguities) — listed in the phase
  reports; resolve with the user before building dependent features.
- **Totals to cite:** 22 C · 68 H · 63 M · 22 L (Phase-14-updated). Phase 16's body shows the
  older 21/64/60/21 because it was written before Phase 14 completed.
- **What's done well (don't break it):** `auth_screen` and `qr_scanner` are genuinely solid
  (typed exceptions, friendly messages, 500-cap offline queue); 23 good DB indexes; reasonable
  offline queue/retry foundation; the differentiators (multi-shift seats, streaks/badges,
  referrals) exist in the schema — they're *broken, not absent*, so repair is cheaper than rebuild.

---

## 8. Git State (as of audit completion, 2026-06-08)

- Branch: `main`. Phase reports **0–8 are committed**; **9–16 were untracked** at handoff time
  (newly created). If these are still untracked, consider committing them as a checkpoint before
  starting code changes.
- Audit reports live in `docs_audit/`. This file (`CLAUDE.md`) lives at the repo root.

---

## 9. How to Continue (instructions for a fresh session)

1. Read `docs_audit/AUDIT_PHASE_16.md` for the full verdict + roadmap.
2. Confirm with the user **which Wave / which findings** to act on (default starting point: **Wave 0**).
3. For each finding you fix, open its phase report, read the **Evidence (`file:line`)**, **Root
   Cause**, and **Recommended Fix / Implementation Example** before editing.
4. Keep Wave 0 changes small and independent (they can land one at a time). Re-run
   `flutter analyze` after edits (note: pre-existing analyzer output is in `analyze_*.txt` at the
   repo root — establish a baseline first).
5. After Waves 0–2 land, **re-audit (regression)** the affected phases — especially the
   Verification-Pending items that need a live DB / device.
6. Update this `CLAUDE.md` as state changes (what's fixed, what Wave you're on) so the handoff
   stays accurate.

---

*Generated 2026-06-08 as a session-durable handoff after the SILENCE Phases 0–16 audit. Keep it
current.*
