# SILENCE — Phase 7: Business Logic Audit

**Phase:** 7 of 16 — Business Logic (Policy vs Reality) Audit
**Completed (local time):** 2026-06-08
**Auditor roles:** Senior PM (lead) · Full-Stack Engineer · Data Analyst · QA Lead · Security Auditor
**Goal:** Verify whether documented rules are *enforced*, not whether they *exist*. Every rule traced through its enforcement chain; the exact failing layer named.
**Method:** Static verification against code + schema + Phases 3–6 evidence. Behavior **Code-Inferred** (no emulator). Prior `UPDATED_Business_Rules.csv` enforcement claims were **independently re-verified**, not trusted.
**Constraint honored:** No code modified.

---

## 1. Executive Summary — Which Promises Are True?

Building on Phase 6's proof that **no rule is server-enforced**, Phase 7 verifies each documented rule against code. The result is stark: **of ~26 documented business rules, 0 are enforced server-side, ~3 are enforced (by DB constraints), ~6 are client-only/partial, and ~17 are documented-only, broken, or contradictory.**

**Which business promises are actually TRUE (enforced):**
- Review uniqueness (one review per member/library) — DB unique constraint.
- Announcement-read uniqueness; seat *definition* uniqueness per shift — DB constraints.
- Library rating auto-maintenance — DB trigger.
- Duplicate **email** at signup is blocked (Supabase Auth unique).

**Which are PARTIALLY true:**
- Exit dues block — **member UI only**; admin force-exit ignores it (P4-09); even member path fails open on query error (P3-06).
- `allow_expired_checkin` — **contradictory**: home FAB respects it, scanner ignores it (P3-04).
- Duplicate-phone — detected on admin-add/signup, but no "returning member reactivation," and `users.phone` UNIQUE can still be bypassed by the no-auth manual-add path (P4-13).
- Multi-shift seat model (the flagship differentiator) — schema + layout tab support it, **but setup generates seats for only the first shift** (see P7-01).
- Seat single-occupancy — racy client check, no DB guard (P5-06).

**Which are merely CLAIMED (documented-only / broken / contradictory):**
- **Discount cap** (`max_discount`) — saved in settings, **never compared** at write; admin can grant up to 100% (P7-02).
- **Trial-once** (`trial_used`) — the flag is **never read or written** in code; unlimited trials (P7-03).
- **Hold limits** (`max_hold_days`, `max_holds_per_period`) — **no validation** (P3-07).
- **Auto-checkout**, **auto-hold**, **streak-freeze-on-closure** — **not implemented**; only UI labels and history filters (no jobs exist; consistent with no server tier) (P7-04).
- **Referral rewards** — conditions never evaluated; status never set to `credited`; no membership extension (P2-02) (P7-05).
- **Payment amount = price − discount** — **hardcoded** `1500/4000/7500` at approval (P4-03).
- **QR 7-day regeneration grace** — scanner does a **strict** version-mismatch rejection; old printed QRs break immediately (P7-06).
- **Join-request auto-expiry / reminders / payment reminders / expiry notifications** — DB sets `expires_at` default but **no cleanup/reminder job**; notifications broken anyway (P5-04).
- **Subscription grace/readonly/lock lifecycle** — **not enforced** (only dialogs); self-activatable (P6-03).
- **Verification** — self-set flags (P6-06); no real approval consumer.

**Policy-vs-Reality Score: 2.5 / 10.** The product's rule-set is almost entirely *aspirational*: configured in UI, stored in tables, but unenforced where it matters (money, eligibility, lifecycle, gamification).

**Connect-back to named findings:** P3-01 (members pay fake UPI) + P4-03 (fictional revenue) + P5-01 (membership integrity) + P6-01 (trust-model failure) are the *mechanisms*; this phase shows the *consequence* — the business rules that depend on those mechanisms cannot hold.

---

## 2. What Was Reviewed
All 33 rows of `06_Business_Rules.csv` (collapsed to ~26 distinct rules), the 7 workflow state machines (`07_Workflows.yaml`), relevant user stories, and their enforcement points in code + schema. Prior `UPDATED_Business_Rules.csv` claims re-verified.

## 3. Files Reviewed
`business_rules.dart`, `admin/add_member_step1/step4.dart`, `requests_sub_tab.dart`, `member_home.dart`, `member_detail_screen.dart`, `qr_scanner_screen.dart`, `library_setup_stage2/3.dart`, `layout_sub_tab.dart`, `referral_settings.dart`, `core/member_analytics_service.dart`, `scheduled_closures.dart`, `admin_home.dart`, `subscription_screen.dart`, `core/offline_sync.dart`; schema constraints/triggers from `supabase_schema.sql`.

## 4. Screens Reviewed
Business-rules settings, add-member wizard (steps 1/4), join approval, renewal, hold/exit/seat-change, QR scanner, library setup S2/S3, layout tab, referral settings, analytics service, closures, subscription.

---

## 5. Findings

### P7-01 — Multi-shift seat model (flagship differentiator) broken at setup 🟠 High
- **Category:** Core Feature · Partial Implementation
- **File/Lines:** `library_setup_stage2.dart:823-825` — `shiftId = newShift['id']` or `shiftsRaw.first['id']`; seat inserts use that single `'shift_id': shiftId` (`:893,919`). **No loop over shifts.**
- **Why it's a problem:** the headline promise is "same physical seat, different members per shift." Each seat row is bound to one `shift_id` (schema `unique_seat_per_library_shift`). Setup creates seats for **only the first shift** → a 3-shift library with 50 seats has 50 seats in shift 1 and **0 in shifts 2 & 3**.
- **How it fails (Code-Inferred):** members joining the morning/evening shift can't be assigned seats; admin must manually recreate every seat per shift in the layout tab (which *does* support per-shift, `layout_sub_tab.dart:376,3486`).
- **Business impact:** the differentiator silently doesn't work for multi-shift libraries — the core market (libraries running 2–3 shifts on shared seats).
- **Fix:** generate seats for every shift at setup (loop), or model physical seats separately from per-shift occupancy.
- **Effort:** Medium

### P7-02 — Discount cap not enforced (revenue leakage / abuse) 🟠 High
- **Category:** Revenue · Rule Enforcement
- **Evidence:** `business_rules.dart:81` saves `max_discount`; `add_member_step4.dart:184-186` sets `discount = entered value`, clamped only to `totalBasePrice` (i.e., up to **100%**); the configured `max_discount` is **never read** at the discount-entry or approval path.
- **Enforcement chain:** Doc ✔ → UI (cap shown in settings) ✔ → **Client logic ✘ (no comparison)** → Data ✘ → DB ✘ → RLS ✘. **Fails at client logic.**
- **Impact:** any admin (or, via P5-01, a crafted client) applies unlimited discounts → revenue loss; no audit (P4-02) to detect it.
- **Fix:** validate discount ≤ `max_discount` at entry and (authoritatively) server-side.
- **Effort:** Small (client) / Medium (server)

### P7-03 — Trial-once-per-member not enforced (free-trial farming) 🟠 High
- **Category:** Eligibility · Revenue
- **Evidence:** `trial_used` exists in schema (`memberships.trial_used`) but is **never read or written** in `lib/` (grep: 0). The only checks are for *currently active* memberships (`add_member_step1`, `requests_sub_tab:498`), not lifetime trial usage.
- **Impact:** a member exits and rejoins repeatedly for unlimited free trials → indefinite free usage; revenue loss.
- **Fix:** set `trial_used=true` on first trial; block subsequent trial selection (server-checked).
- **Effort:** Medium

### P7-04 — Auto-checkout, auto-hold, streak-freeze: documented, not implemented 🟠 High
- **Category:** Lifecycle · Gamification
- **Evidence:** no scheduler/cron/Timer for any of these (only a 1-sec UI clock `member_home.dart:491`). "Streak freeze applied" (`admin_home.dart:3464`) writes nothing. `auto_checkout` appears only as a history *filter* value (`member_history_tab.dart:430`) — records that a non-existent job would create. Closures screen advertises "registers streak freeze" (`scheduled_closures.dart:178`) with no backing logic.
- **Why:** these are inherently server/scheduled operations; with no server tier (P6-01) they cannot exist.
- **Impact:** open sessions never auto-close (skewed hours, Phase 8); expired memberships never auto-hold (seats blocked); streaks break on closure days (members penalized → the exact demotivation the feature was meant to prevent).
- **Fix:** implement as Edge Function cron jobs.
- **Effort:** Large

### P7-05 — Referral reward logic absent (broken promise) 🟠 High
- **Category:** Growth · Broken Promise (re-confirms P2-02)
- **Evidence:** no code evaluates `referral_reward_min_checkins`/`min_days`; `referrals.status` only ever **read** as `credited` (counters), never **written**; no membership extension. UI advertises "rewards authorized after 7 days / 5 check-ins" (`referral_settings.dart:238`).
- **Impact:** referrers never rewarded → churn, support tickets, broken growth loop.
- **Fix:** server job to evaluate conditions, set `credited`, extend membership.
- **Effort:** Large

### P7-06 — QR 7-day regeneration grace not honored 🟡 Medium
- **Category:** Operational · Contradiction
- **Evidence:** rule `regeneration_grace_days=7` (old QR valid 7 days). Scanner does **strict** rejection: `if (qrVersion != dbQrVersion)` → "outdated" error (`qr_scanner_screen.dart:328-331`). No grace window.
- **Impact:** the moment an admin regenerates a QR, **every printed/laminated QR breaks instantly** — contradicting the "print once, use forever" differentiator and causing mass check-in failures.
- **Fix:** accept `dbQrVersion-1` within a 7-day window; track regeneration timestamp.
- **Effort:** Small

### P7-07 — `allow_expired_checkin` contradiction 🟡 Medium
- **Category:** Contradiction (re-confirms P3-04)
- **Evidence:** FAB honors the rule (`member_home.dart:1001-1018`); scanner blocks all expired as "Not a member here" (`qr_scanner_screen.dart:321-325`). The rule is half-applied and the error misleads.
- **Fix:** scanner honors the rule; accurate message.
- **Effort:** Small

### P7-08 — Exit dues block partial / bypassable 🟡 Medium
- **Category:** Financial Rule (re-confirms P4-09, P3-06)
- **Evidence:** member exit checks dues (`member_home.dart:4982-5055`) but admin force-exit ignores them (`member_detail_screen.dart:478`); member path fails open if the dues query errors (`member_home.dart:5004-5008`).
- **Fix:** apply dues policy in both paths; fail closed.
- **Effort:** Small

### P7-09 — Join-request auto-expiry / all time-based notifications absent 🟡 Medium
- **Category:** Lifecycle · Notifications
- **Evidence:** `join_requests.expires_at` defaults to +7d (schema `:215`) but **no job** marks them expired; `join_request_reminder`, `payment_reminder`, `expiry_notification` rules have no implementation; notification writes are broken anyway (P5-04) and unreadable (P3-05).
- **Fix:** server cron + working notifications.
- **Effort:** Large

### P7-10 — Subscription lifecycle (grace/readonly/lock) not enforced 🟡 Medium
- **Category:** Commerce lifecycle
- **Evidence:** rules define grace(7)/readonly(23)/lock + 90-day retention; code only shows dialogs; status is self-writable (P6-03). No read-only enforcement, no lock, no retention/deletion.
- **Fix:** server-driven entitlement + enforcement.
- **Effort:** Large

**Enforced (positive) rules:** review-per-member uniqueness, announcement-read uniqueness, seat-definition uniqueness (DB constraints); rating auto-update (trigger); signup email uniqueness (Auth). These are the *only* rules backed by an authoritative layer — and notably all are **DB-level**, never application-level.

---

## 6. Business Rule Enforcement Matrix (Documented → Outcome; failing layer named)

| Rule | Documented | Implemented | Enforced | Bypassable | Class | Fails at layer |
|---|---|---|---|---|---|---|
| max_discount_percent | ✔ | UI save only | ✘ | yes | **CLIENT-ONLY/BROKEN** | client logic (P7-02) |
| max_hold_days / max_holds | ✔ | ✘ | ✘ | yes | **DOCUMENTED-ONLY** | client (P3-07) |
| trial_once_per_member | ✔ | ✘ (flag unused) | ✘ | yes | **DOCUMENTED-ONLY** | client+server (P7-03) |
| allow_expired_checkin | ✔ | partial | partial | n/a | **CONTRADICTORY** | client (P7-07) |
| exit_dues_block | ✔ | partial | partial | yes (admin) | **PARTIAL/CONTRADICTORY** | client+RLS (P7-08) |
| auto_checkout_delay | ✔ | ✘ | ✘ | n/a | **DOCUMENTED-ONLY** | server (P7-04) |
| auto_hold (grace) | ✔ | ✘ | ✘ | n/a | **DOCUMENTED-ONLY** | server (P7-04) |
| streak_freeze_on_closure | ✔ | label only | ✘ | n/a | **BROKEN** | server (P7-04) |
| referral rewards | ✔ | partial (insert) | ✘ | n/a | **BROKEN** | server (P7-05) |
| payment amount = price−discount | ✔ | hardcoded | ✘ | yes | **BROKEN** | client (P4-03) |
| seat single-occupancy | ✔ | racy | partial | yes | **PARTIAL** | DB (P5-06) |
| multi-shift seat model | ✔ | partial | partial | n/a | **PARTIAL** | setup logic (P7-01) |
| duplicate-phone prevention | ✔ | partial | partial | yes | **PARTIAL** | client (P4-13) |
| qr_regeneration_grace | ✔ | ✘ (strict) | ✘ | n/a | **CONTRADICTORY** | client (P7-06) |
| join_request_auto_expiry | ✔ | DB default only | ✘ | n/a | **PARTIAL** | server (P7-09) |
| maintenance_alert_days | ✔ | ✘ | ✘ | n/a | **DOCUMENTED-ONLY** | server |
| expiry/payment/reminder notifs | ✔ | ✘ | ✘ | n/a | **DOCUMENTED-ONLY** | server (P7-09) |
| subscription grace/readonly/lock | ✔ | dialogs only | ✘ | yes | **BROKEN** | server (P7-10) |
| verification (phone/email/badge) | ✔ | self-set/mock | ✘ | yes | **BROKEN** | server (P6-06) |
| membership expiry status | ✔ | client display | partial | yes (P5-01) | **PARTIAL** | server/RLS |
| expense_categories | ✔ | mismatch | ✘ (CHECK breaks) | n/a | **BROKEN** | schema/code (P5-02) |
| review uniqueness | ✔ | ✔ | **✔** | no | **ENFORCED** | DB ✓ |
| announcement-read uniqueness | ✔ | ✔ | **✔** | no | **ENFORCED** | DB ✓ |
| seat-definition uniqueness | ✔ | ✔ | **✔** | no | **ENFORCED** | DB ✓ |
| rating auto-update | ✔ | ✔ | **✔** | no | **ENFORCED** | DB trigger ✓ |
| signup email uniqueness | ✔ | ✔ | **✔** | no | **ENFORCED** | Auth ✓ |

**Tally:** ENFORCED 5 · PARTIAL 6 · CLIENT-ONLY 1 · DOCUMENTED-ONLY 6 · BROKEN 6 · CONTRADICTORY 2. **(0 enforced at the application layer; all 5 enforced rules are DB/Auth-level.)**

---

## 7. Business Rule Contradiction Register

| CID | UI/Doc says | Code/Schema does | Evidence |
|---|---|---|---|
| BC-01 | "Pay these Admin UPI IDs" | hardcoded placeholder UPI | P3-01 |
| BC-02 | "Revenue ₹X collected" | amounts hardcoded `1500/4000/7500` | P4-03 |
| BC-03 | "Library closed today, members notified" | wrong table; scanner open; no notify | P4-04 |
| BC-04 | Expired members may check in (rule on) | scanner: "Not a member here" | P7-07 |
| BC-05 | "Print once, use forever" QR | strict version reject, no grace | P7-06 |
| BC-06 | "Rewards after 7 days / 5 check-ins" | never evaluated/credited | P7-05 |
| BC-07 | Max discount cap configured | unlimited discount accepted | P7-02 |
| BC-08 | Trial once per member | unlimited trials | P7-03 |
| BC-09 | Streak frozen on closures | nothing freezes | P7-04 |
| BC-10 | "Member notified" (approval/hold/seat) | notification inserts fail/unreadable | P4-05/06, P5-04 |
| BC-11 | Exit blocked if dues | admin bypasses; member fails open | P7-08 |
| BC-12 | Multi-shift shared seats | setup seats only first shift | P7-01 |
| BC-13 | "Audit log of critical actions" | writes/reads broken | P4-02 |
| BC-14 | Verified badge (trust) | self-set mock flags | P6-06 |

---

## 8. Business Abuse Simulation

| Persona | Can bypass | Creates dispute | Revenue loss | Support burden |
|---|---|---|---|---|
| Honest member | n/a | hit by fake UPI, no notifications, broken referral | — | high (confusion) |
| **Clever member** | unlimited trials (P7-03); self-extend membership (P5-01); self-verify (P6-06) | — | **high** | med |
| **Malicious member** | become admin→all PII (P6-02); fabricate attendance/streak/badges (P6-04); free Pro if owner (P6-03) | — | **high** | high |
| Busy admin | accidental: reassign no-op, close-today no-op, audit blind | seat conflicts (P5-06) | leakage via discounts (P7-02) | high |
| **Revenue-focused admin** | unlimited discounts; can't trust revenue numbers (P4-03) | refunds (fake UPI) | **direct leakage + fictional books** | high |
| Forgetful admin | no auto-checkout/hold/expiry to save them | members stuck expired | seats blocked, unbilled | high |

---

## 9. Required Artifacts

### 9.1 Business Rule Enforcement Matrix — §6.
### 9.2 Contradiction Register — §7.

### 9.3 Revenue Leakage Register
| RLID | Leak | Mechanism | Severity |
|---|---|---|---|
| RV-01 | Fictional revenue (wrong amounts) | hardcoded approval amount | Critical (P4-03) |
| RV-02 | Unlimited discounts | cap unenforced | High (P7-02) |
| RV-03 | Free-trial farming | trial-once unenforced | High (P7-03) |
| RV-04 | Free Pro subscription | self-activation | Critical (P6-03) |
| RV-05 | UPI payments lost | fake UPI id | Critical (P3-01) |
| RV-06 | Unbilled expired usage | no auto-hold; expired check-in inconsistency | Med (P7-04/07) |
| RV-07 | Add-on revenue lost/unfulfilled | not persisted | High (P2-03) |
| RV-08 | Expenses unrecordable/miscategorized | CHECK breakage | Med (P5-02) |

### 9.4 Membership Integrity Register
| MI | Risk | Root |
|---|---|---|
| MI-01 | Any user rewrites any membership | P5-01 |
| MI-02 | Duplicate active memberships | P5-06 |
| MI-03 | Membership→seat desync (exit/seat ops) | P4-08, P6-05 |
| MI-04 | Status transitions manual, no lifecycle automation | P7-04 |
| MI-05 | Manual-added member has no auth/login | P4-13 |

### 9.5 Attendance Integrity Register
| AI | Risk | Root |
|---|---|---|
| AI-01 | Self-insert arbitrary attendance | P6-04 |
| AI-02 | Offline fake-success scans | P3-03 |
| AI-03 | Negative/invalid durations | P5-09 |
| AI-04 | No auto-checkout → open/909 sessions | P7-04 |
| AI-05 | Manual vs admin_edited taxonomy split | P4-12 |
| AI-06 | QR grace not honored → mass check-in failure | P7-06 |

### 9.6 Business Abuse Register — §8.

### 9.7 Policy-vs-Reality Score
**2.5 / 10.** Enforced 5/26 (all DB/Auth-level, none application-level); the rules governing money, eligibility, lifecycle, and gamification — the ones that define the product — are documented-only, broken, or contradictory. Weighting money/integrity rules heavily pulls the score down.

---

## 10. Connect-Back (per the brief)
- **P3-01 (payment flow)** → BC-01, RV-05: the payment promise is false end-to-end.
- **P4-03 (fictional revenue)** → BC-02, RV-01: the revenue rule (amount=price−discount) is the most-violated rule.
- **P5-01 (membership integrity)** → MI-01, RV-: makes every membership/eligibility rule bypassable.
- **P6-01 (trust-model failure)** → the *reason* 0 rules are server-enforced; every "BROKEN/DOCUMENTED-ONLY" row traces here.
**Which promises are true?** Only the 5 DB/Auth-enforced ones. **Partially true:** dues block, expired-checkin, duplicate-phone, multi-shift, seat-occupancy. **Merely claimed:** discounts, trials, holds, referrals, auto-lifecycle, streak-freeze, QR grace, subscription lifecycle, verification, revenue accuracy.

## 11. Improvement Suggestions
1. **Decide the V1 rule-set honestly** — either enforce a rule server-side or remove its UI promise (stop advertising unenforced caps/rewards/grace).
2. **Server-validate the money/eligibility rules first** (discount cap, trial-once, payment amount, subscription) — these are revenue.
3. **Implement the scheduled jobs** (auto-checkout/hold, expiry, referral credit, streak-freeze) as Edge cron.
4. **Fix the flagship** multi-shift seat generation (P7-01) — it's the product's reason to exist.
5. **Reconcile contradictions** (QR grace, expired-checkin, closures) so UI copy matches behavior.

## 12. Priority Fix List (Phase 7)
| # | Item | Severity | Effort |
|---|---|---|---|
| 1 | Fix payment amount = price−discount (P4-03) | Critical | Small |
| 2 | Enforce discount cap (P7-02) | High | Small/Med |
| 3 | Enforce trial-once (P7-03) | High | Medium |
| 4 | Fix multi-shift seat generation (P7-01) | High | Medium |
| 5 | Implement auto-checkout/hold/expiry/streak jobs (P7-04) | High | Large |
| 6 | Implement referral crediting (P7-05) | High | Large |
| 7 | QR regeneration grace (P7-06) | Medium | Small |
| 8 | Dues block both paths + fail-closed (P7-08) | Medium | Small |
| 9 | Honor expired-checkin in scanner (P7-07) | Medium | Small |

---

## 13. Cross-Phase Critical Findings (additions this phase)
| Ref | Sev | Title | Evidence | Effort |
|---|---|---|---|---|
| P7-01 | High | Multi-shift seat model broken at setup (seats only for first shift) | `library_setup_stage2.dart:823-919` | Medium |
| P7-02 | High | Discount cap saved but never enforced (unlimited discounts) | `business_rules.dart:81` vs `add_member_step4.dart:184` | Small |
| P7-03 | High | Trial-once not enforced (`trial_used` unused) → free-trial farming | grep: 0 refs | Medium |
| P7-04 | High | Auto-checkout/auto-hold/streak-freeze not implemented (labels only) | `admin_home.dart:3464`, no scheduler | Large |
| P7-05 | High | Referral rewards never evaluated/credited | `referral_settings.dart:238` vs no credit logic | Large |

## 14. Open Questions (additions)
27. Is the multi-shift "seat" meant to be one physical seat across shifts (needs per-shift rows) or per-shift independent seats? Confirms P7-01 fix shape.
28. Are auto-* jobs intended for V1 or deferred? (changes severity of P7-04/09).

## 15. Verification Pending (additions)
| VID | Item | Method | Phase |
|---|---|---|---|
| V-34 | Confirm multi-shift seat gap on a 3-shift setup (P7-01) | Device/integration | 13 |
| V-35 | Confirm discount cap bypass end-to-end (P7-02) | Device | 13 |
| V-36 | Confirm repeat-trial possible (P7-03) | Device | 13 |

---

*End of Phase 7. No code modified. Stopped; awaiting approval for Phase 8 (Calculations & Data Accuracy Audit).*
