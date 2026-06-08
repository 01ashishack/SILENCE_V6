# SILENCE — Phase 13: QA & Edge Cases Audit

**Phase:** 13 of 16 — QA & Edge Cases Audit
**Completed (local time):** 2026-06-08
**Auditor roles:** QA Lead (lead) · Full-Stack Engineer · UX Designer · SRE/Resilience · Support/CX Analyst · Data Analyst
**Goal:** Determine whether SILENCE stays **correct, usable, recoverable, and trustworthy** when users misbehave, data is imperfect, networks are unreliable, and workflows are interrupted. **Audit actual behavior under edge conditions, not intended behavior.**
**Method:** 15-persona simulation + edge-case enumeration + workflow-interruption tracing + boundary testing, grounded in code already cited in Phases 0–12 plus targeted edge-case verification (double-submit guards, unique constraints, drafts, seat concurrency). Behavior **Code-Inferred** (no device/fault-injection) — declared limitation: timing-sensitive races and on-device interruption need an emulator run (V-48…V-50).
**Constraint honored:** No code modified. Audit only.

**QA classification used:** FUNCTIONAL FAILURE · DATA-INTEGRITY FAILURE · RECOVERY FAILURE · UX FAILURE · TRUST FAILURE · SECURITY-RELEVANT · PERFORMANCE-RELEVANT · UNVERIFIED.

---

## 0. Consistency Check (run before finalizing — as required)

| Check | Result |
|---|---|
| Master report synchronization | ✅ Phases 0–12 banners all present (lines 173…4396); content intact |
| TOC synchronization | ✅ 0–12 ✅ Complete, 13–16 Pending |
| Severity reconciliation | ✅ "through Phase 12" = 21 C · 62 H · 57 M · 20 L; per-phase distributions present |
| Cross-Phase Critical Findings | ✅ current through P12-01…04 |
| Open Questions | ⚠️ **Minor:** line read "Phases 8–10 added none" though 11–12 also added none → **corrected to "Phases 8–13 added none."** |
| Verification Pending | ✅ 47 (through V-47); Phase 13 appends V-48…V-50 |

**Discrepancy reported & fixed:** the Open-Questions wording lag (8–10 → 8–13). No severity/TOC/critical-table drift found. Master is otherwise synchronized.

---

## 1. Executive Summary — Does it hold up in the real world?

**No. SILENCE is built for the happy path and degrades — often invisibly — the moment reality deviates from it.** Phases 0–12 proved the individual defects; Phase 13's job was to run the system as *real users* would and watch what breaks. The pattern is consistent and damning: **the app almost never tells the truth about failure.** It shows success for pending/failed actions (Phase 4/9), swallows errors into empty states (Phase 12), and has **no server-side guard** to stop the duplicates, races, and partial writes that edge conditions create (Phase 6/10).

**The five edge behaviors that will generate the most pain:**

1. **Duplicates are unprevented (P13-01, DATA-INTEGRITY).** `memberships`, `attendance`, and `join_requests` have **no uniqueness constraint** (only `reviews` does — `supabase_schema.sql:384`). Combined with client-only submit guards (P13-03), offline resync (P11/P12), and no server idempotency (P6-01), a double-tap, a retry, or an offline→online transition can create **duplicate active memberships, duplicate check-ins (inflated streaks/hours/revenue), and duplicate join requests.**
2. **Concurrency silently corrupts seats (P13-02).** Seat occupancy is a single overwrite column (`status` + `occupied_by_member_id`), last-write-wins, no conflict detection — two admins (or an admin + a member request) assigning the same seat **overwrite each other with no error**, desyncing seat↔membership (extends P4-08).
3. **Interruptions lose work and leave partial state (P13-04/P13-05, RECOVERY).** The member-side join/renewal flow has **no draft persistence** (only the admin add-member wizard does, via `draft_service.dart`); app-kill or network loss mid-flow loses entered data and can leave a half-created request, with **no recovery path**.
4. **The clock/timezone edges (P8) bite at midnight (P13-08).** On a non-IST device, a late-evening check-in lands on the wrong day → broken streaks, "0 days left" while active, wrong heatmap cells. Two users see different truths for the same data.
5. **Fail-open + false-success + silent-failure compound (P13-09…P13-12).** The offline scanner fakes success for anyone (P3-03), dues/closure gates fail open (P3-06), success banners fire before confirmation (P9-17), and release-build errors are invisible (P12-02). Under edge conditions these don't just misbehave — they **actively mislead** the user into thinking things worked.

**Distribution (Phase 13):** 0 Critical · 2 High · 3 Medium · 1 Low **new** (P13-01…P13-06), plus **9 linked edge findings** (P13-07…P13-15) that catalog how prior-phase Criticals/Highs behave under edge conditions (counted in their owning phases).

**QA verdict: 3 / 10.** Of 15 personas, **2 have a clean experience** (first-time signup, basic QR check-in on good network); the other **13 hit a failure, a lie, or a dead end** that either needs support or erodes trust. **Recovery exists for almost nothing.** The app is demo-robust and production-fragile.

---

## 2. Mandatory User Simulation — 15 Personas

> Columns: **Expects → System actually does → Recovery? → Support needed? → Trust ↑/↓**. Evidence cites the owning phase/finding.

| # | Persona | Expects | System actually does | Recovery | Support | Trust |
|---|---|---|---|---|---|---|
| 1 | **First-time user** | sign up, verify, get going | signs up (real Supabase auth ✅); **never verifies** (mock OTP P10-13); lands with no guidance | n/a | No | ↓ slight |
| 2 | **Returning user** | see reminders/dues | Notifications **always "all caught up"** (P9-01) → misses renewal | none | Yes (later) | **↓↓** |
| 3 | **Power user** | fast renewal | re-enters method + re-uploads proof every cycle (P9-05); success ≠ renewed | manual | Yes | ↓ |
| 4 | **Non-technical user** | tap "pay", money moves | sees hardcoded sample UPI + "Simulated deep link" (P3-01/P9-04); may pay nobody | none | Yes (refund) | **↓↓** |
| 5 | **Frustrated user** | confirmation it's done | celebratory "Submitted! 🎉" for a **pending** request (P9-03); re-taps, may dup (P13-01/03) | none | Yes | ↓ |
| 6 | **Poor-network user** | retry on blip | raw `$e` or blank screen; **no retry UI**, no typed network errors (P12-04) | none | Yes | ↓ |
| 7 | **Offline user** | honest offline state | QR **fakes success for anyone** (P3-03); queue caps at 500 then blocks (P12 nuance); invalid scans silently discarded on sync (P11-07/P12-08) | partial/lossy | Yes | **↓↓** |
| 8 | **Incomplete-profile user** | clear next step | repeated "Complete your profile first" SnackBars, **no CTA to go do it** (P9-14) | manual | maybe | ↓ |
| 9 | **Expired-membership user** | consistent rule | **home FAB invites, scanner rejects** (P3-04); inconsistent | none | Yes | ↓ |
| 10 | **Failed-payment user** | clear failure + retry | **cannot fail** — subscription always "succeeds" (P9-02); persistence error swallowed (P12-05) | none | Yes (dispute) | **↓↓** |
| 11 | **Invalid-data user** | validation blocks bad input | form validates name/phone/shift (✅ join `:744`); but amount hardcoded downstream (P4-03) so valid input → wrong money | partial | Yes | ↓ |
| 12 | **Unexpected-action user** (self-escalate, edit prefs) | blocked | **self-promote to admin / self-activate sub** succeed (P10-06/07); cancel sub admits "simulated mode" (P9-21) | n/a (abuse) | No | **↓↓ / security** |
| 13 | **Small-screen user** | fits screen | 5k-line dense screens, no responsive breakpoints (P9-19); overflow risk <360dp | none | maybe | ↓ |
| 14 | **Admin under operational pressure** (peak check-in) | fast dashboard | 8 sequential count-by-fetch lag (P11-03); "Close Today" is a no-op lie (P4-04); audit log forgeable/broken (P4-02/P10-11) | none | Yes | **↓↓** |
| 15 | **Owner with thousands of members** | analytics/export works | analytics **freezes** (badge N+1 + full scans P11-01/02); export OOM risk (P11-10); occupancy "0%" misleads (P9-13) | none | Yes | **↓↓** |

**Score:** 2/15 clean (personas 1 partial, basic check-in on good net). **13/15 hit failure/lie/dead-end.** Recovery exists for **~0**.

---

## 3. Edge-Case Inventory (behavior under each condition)

| Edge case | Actual behavior | Class | Owning/links |
|---|---|---|---|
| **Auth: signup with existing email** | handled — "User already exists" (`auth_screen.dart:209`) | ✅ ok | P12 |
| **Auth: session expiry mid-use** | no `onAuthStateChange`; silent denials / `currentUser!` crash | RECOVERY/SECURITY | P12-01/03 |
| **Role change member→admin** | succeeds (self-update) | SECURITY | P10-06 |
| **Membership expiry** | status flips only via client/admin; member can self-extend | DATA-INTEGRITY | P10-05 |
| **Renewal at expiry boundary** | renewal = pending request; lapse during approval gap | UX/FUNCTIONAL | P9-05 |
| **Trial boundary (repeat trial)** | `trial_used` never read → unlimited trials | FUNCTIONAL/BUSINESS | P7-03 |
| **Discount boundary (>max)** | cap never enforced; up to 100% | BUSINESS | P7-02 |
| **Seat allocation boundary** | seats only generated for first shift | FUNCTIONAL | P7-01 |
| **Seat occupancy conflict (concurrent)** | last-write-wins overwrite, no detection | **DATA-INTEGRITY** | **P13-02** / P4-08 |
| **Attendance double check-in** | no DB unique → duplicate rows | **DATA-INTEGRITY** | **P13-01** / P5-06 |
| **Midnight / day-transition** | wrong-day attribution off-IST | DATA-ACCURACY | P8-01 / P13-08 |
| **Timezone (non-IST device)** | streaks/heatmap/"days left" wrong | DATA-ACCURACY | P8-01/20 |
| **Referral timing** | never credited; status stuck pending | FUNCTIONAL/TRUST | P2-02/P7-05 |
| **Payment timing** | mocked; no real settlement | TRUST/BUSINESS | P0-01/P9-02 |
| **Duplicate submission** | client guard only; dup possible on retry/offline | DATA-INTEGRITY | **P13-01/03** |
| **Double-click / rage-click** | most buttons guarded by `_isSubmitting`; some slow paths re-tappable | UX | **P13-06** |
| **Offline→online transition** | sequential resync, dup risk, lossy conflict | DATA-INTEGRITY/PERF | P11-07/P12-08 / P13-05 |
| **Network loss during write** | partial state (e.g., membership w/o payment); no rollback | **RECOVERY** | **P13-05** |
| **Network loss during upload** | raw `$e`; proof lost; request may persist without proof | RECOVERY/UX | P12-03/07 |
| **App termination mid-workflow** | admin wizard drafts survive; **member join/renewal loses all** | **RECOVERY** | **P13-04** / P9-15 |
| **Background/resume** | no auth re-check; stale "Active" from prefs (P9-20); no refresh | UX/TRUST | P9-20 / P12-01 |
| **Notifications** | static stub; never shows anything | FUNCTIONAL/TRUST | P9-01 |
| **Export (large/empty)** | empty → header-only; large → OOM/jank | PERF/UX | P11-10 |
| **Analytics (0 / 1 / huge records)** | 0 guarded; huge → freeze; corrupt → `as int` throws | PERF/FUNCTIONAL | P11-01 / P8-17 |
| **Library closure** | "Close Today" writes dead table; scanner ignores | FUNCTIONAL/TRUST | P4-04 |

---

## 4. Workflow Interruption Register

> For each workflow: **Close app · Lose internet · Change device · Logout · Session expiry · Navigate away · Submit twice · Refresh mid-flow.**

| Workflow | Close app | Lose internet | Change device | Logout/Expiry | Submit twice | Net verdict |
|---|---|---|---|---|---|---|
| **Join** | ❌ loses entered data (no draft P13-04) | ❌ raw error/partial (P13-05) | ❌ progress not portable | ❌ `currentUser!` crash on upload (P12-03) | ⚠️ guarded client-side; dup if retried (P13-01/03) | **Fragile** |
| **Renewal** | ❌ loses data | ❌ proof upload fails raw | ❌ | ⚠️ | ⚠️ dup request possible | **Fragile** |
| **Payment (sub)** | state from prefs; "Active" persists | n/a (mock) | ❌ prefs not portable (P9-20) | ⚠️ | "succeeds" twice harmlessly but fake | **Misleading** |
| **Check-in (QR)** | scan lost if pre-insert | ✅ queues offline (caps 500) | session-bound | "Auth Error" handled (`:213`) | "Already checked in" blocks (P9-08) **or** dup if offline (P13-01) | **Mixed** |
| **Offline sync** | resumes on reconnect | core design | queue is device-local → **lost on device change** | n/a | dup/lossy (P11-07/P12-08) | **Lossy** |
| **Seat request** | lost | raw error | n/a | silent (RLS) | dup request | **Weak** |
| **Hold request** | lost | raw error | n/a | silent | dup; cumulative-extension bug (P7) | **Weak** |
| **Query** | lost | raw error (`:99`) | n/a | silent | dup query | **Weak** |
| **Review** | lost | raw error | n/a | silent | **blocked by UNIQUE** (`:384`) ✅ | **Best-guarded** |
| **Referral** | n/a | — | n/a | — | dup rows possible | **Weak** |
| **Admin approval** | in-memory "Confirm Pay" lost (P4-07) | raw error | n/a | silent | dup membership/payment (P13-01) + wrong amount (P4-03) | **Fragile** |

**Key insight:** the **only workflow with a real interruption guard is Reviews** (DB `UNIQUE(library_id, member_id)`), and the **only workflow with draft persistence is the admin add-member wizard**. Everything members do is interruption-fragile.

---

## 5. Boundary Condition Register

| Feature | 0 records | 1 record | Max/huge | Duplicate | Corrupt | Missing | Fails safely? | Fails visibly? |
|---|---|---|---|---|---|---|---|---|
| Notifications | fake "all caught up" (P9-01) | never shown | never shown | n/a | n/a | reads nothing | ❌ | ❌ (lies) |
| Analytics summary | guarded (÷0 → 0) | ok | **freeze** (P11-01) | dup check-ins inflate (P13-01) | `as int` throws (P8-17) | dead-table→empty (P12-09) | ⚠️ | ❌ silent |
| Leaderboard | empty ok | ok | scan + Dart sort, slow | dup inflate | one bad row kills list (P11-13) | n/a | ❌ | ❌ |
| Occupancy | "0%" = ambiguous (P9-13) | ok | ok | n/a | seat overwrite (P13-02) | no seats→0% | ❌ misleads | ❌ |
| Explore/search | "no results" ok | ok | all-libs-to-device (P11-06) | n/a | null coords→0km (P8-21) | fallback query | ⚠️ | ⚠️ |
| Revenue | 0 ok; "+100%" sentinel (P8-09) | ok | sums fabricated amounts (P8-08) | dup payments inflate | int/numeric mix (P8-18) | excluded silently | ❌ | ❌ |
| Export | header-only file | ok | OOM/jank (P11-10) | dups in output | parse throw | partial | ⚠️ | ⚠️ |
| Memberships | ok | ok | dashboard lag (P11-03) | **dup active** (P13-01) | status free-write (P10-05) | n/a | ❌ | ❌ |

**Summary:** features **fail safely rarely, fail visibly almost never, and several corrupt or inconsistent state** (duplicates, seat overwrite, free-write membership/role).

---

## 6. Special-Focus Revisit — how prior findings behave under edge conditions

| Prior finding | Under edge conditions | Reinforces pattern |
|---|---|---|
| **P3-03 Offline check-in** | offline "success" for anyone → on resync, invalid scans silently discarded → attendance gap with no notice | False-Success + Trust-Model + Data-Accuracy |
| **P3-06 Fail-open gates** | dues/closure checks throw → caught → **proceed anyway**; under network blip a barred member checks in | Trust-Model + Security-relevant |
| **P4 false-success** (Close Today, Confirm Pay, approval amount) | every interruption/retry produces a confident lie or wrong money | False-Success |
| **P5 data integrity** (no uniques, RLS holes, schema drift) | edge conditions (double-submit, concurrency, offline) **convert missing guards into actual duplicate/corrupt rows** | Schema-Drift + Data-Accuracy |
| **P6 trust model** (client-direct, no validation) | every duplicate/partial/escalation is *permitted* because nothing server-side says no | Trust-Model + Security |
| **P8 clock/date** | at IST midnight off-IST: streak breaks, "0 days left," wrong heatmap; two users disagree | Data-Accuracy |
| **P11 offline queue** | 500-cap blocks check-ins during long peak outage; resync storm; dup rows | Performance + Data-Integrity |
| **P12 silent failure** | release-build errors invisible → every edge failure looks like "nothing happened/success" | False-Success + Trust |

**Conclusion:** the prior-phase defects are **not independent** — under edge conditions they **chain**: a missing server guard (P6) + no DB unique (P5) + client-only submit guard (P13-03) + silent failure (P12) + false-success UI (P9) = a member who double-taps a flaky renewal ends up with **two pending requests, possibly two memberships, a lost payment proof, a "success" message, and no notification** — every layer that should have caught it instead hid it.

---

## 7. Findings (new this phase)

### P13-01 — No uniqueness on memberships/attendance/join_requests → duplicates under double-submit, offline resync, or concurrency 🟠 High (NEW)
**Class:** DATA-INTEGRITY FAILURE · **Cross-phase: Schema-Drift (P5-06) + Trust-Model (P6-01) + Performance (P11-07)**
**Evidence:** Only `reviews` has `UNIQUE(library_id, member_id)` (`supabase_schema.sql:384`); `memberships`, `attendance`, `join_requests` have **no unique/partial-unique constraint** (schema grep). Submit guards are client-only `_isSubmitting` (`join_flow_screen.dart:454`); offline resync re-inserts (`offline_sync.dart:102`); no server idempotency (P6-01).
**Edge trigger:** double-tap on slow network; offline→online with a scan already synced; concurrent admin+member actions; a crafted/retried REST call.
**Impact:** duplicate **active memberships** (double billing/seat), duplicate **attendance** (inflated streak/hours/revenue — corrupts all Phase 8 metrics), duplicate **join requests** (admin confusion, double approval → P4-03 wrong amount ×2).
**Fix:** partial-unique indexes — `memberships(member_id, library_id) WHERE status IN ('active','trial')`; `attendance(member_id, library_id, date_trunc('day', check_in_time))` or an idempotency key; `join_requests(member_id, library_id) WHERE status='pending'`.

### P13-02 — Seat occupancy is last-write-wins; concurrent assignment silently overwrites 🟠 High (NEW)
**Class:** DATA-INTEGRITY FAILURE · **Cross-phase: P4-08 (seat desync) + P6-01**
**Evidence:** occupancy stored as `seats.status` + `occupied_by_member_id` single columns (`layout_sub_tab.dart:267,397,557`); assignment is a plain `update` with no optimistic-concurrency/version check; `unique_seat_per_library_shift` (`:129`) guards seat *rows*, not *occupancy*.
**Edge trigger:** two admins assign the same seat; admin assigns while a member seat-change is approved; offline check-in claims a seat already taken.
**Impact:** silent overwrite → two members believe they hold one seat; seat↔membership desync; occupancy count wrong. No error shown.
**Fix:** conditional update (`...WHERE status='vacant'`) + check rows-affected; or a `version`/`updated_at` optimistic lock; surface conflict.

### P13-03 — Submit guards are client-only; no server idempotency 🟡 Medium (NEW)
**Class:** FUNCTIONAL/DATA-INTEGRITY · **Cross-phase: P6-01**
**Evidence:** 450 `_isLoading/_isSubmitting`-style flags guard the UI, but they reset on rebuild/app-restart and are absent from the data layer; no `Idempotency-Key`, no upsert-by-natural-key on requests.
**Impact:** the guard works for an ordinary double-tap but **not** for app-kill+retry, two devices, or crafted requests → feeds P13-01.
**Fix:** server idempotency keys; upsert by natural key; debounce + disable on all mutating buttons.

### P13-04 — Member-side workflows have no draft persistence → app-kill/interruption loses all progress 🟡 Medium (NEW)
**Class:** RECOVERY FAILURE · **Cross-phase: P9-15**
**Evidence:** `draft_service.dart` persists drafts **only** for the admin add-member wizard; member `join_flow_screen.dart` / `renewal_screen.dart` keep state in widget memory; no autosave.
**Edge trigger:** call interrupts a 5-step join; app backgrounded+killed by OS; battery dies.
**Impact:** member re-enters everything (name/phone/shift/proof) → abandonment at the highest-stakes funnel; if the request was partially created, a re-do duplicates (P13-01).
**Fix:** autosave member flow to local draft (reuse `draft_service` pattern); resume on return.

### P13-05 — No recovery for interrupted writes → partial/inconsistent state 🟡 Medium (NEW)
**Class:** RECOVERY FAILURE · **Cross-phase: P6-01 (no transaction tier) + P12**
**Evidence:** multi-step mutations are separate client calls with no transaction/saga: e.g., approval updates membership then inserts payment then (tries to) notify (`requests_sub_tab`), attendance inserts check-in with `check_out_time:null` (`offline_sync.dart:108`); a network drop between steps leaves step 1 done, step 2 not.
**Impact:** membership active without payment row (or vice-versa); check-in without checkout (skews hours — P8-04/05); no rollback, no retry of the missing step.
**Fix:** server RPC performing multi-row changes in one transaction; reconciliation job for orphaned half-states.

### P13-06 — Rage-click window on slow/delayed actions 🟢 Low (NEW)
**Class:** UX FAILURE
**Evidence:** the 2s `Future.delayed` "payment" (`subscription_screen.dart:277`) and full-screen spinners (P9-16) create a wait where some secondary buttons aren't disabled; combined with no skeletons, users tap repeatedly.
**Impact:** extra taps → possible dup actions where the guard is missing (P13-01/03); frustration.
**Fix:** disable all actions during async; skeletons; idempotency as backstop.

### P13-07 … P13-15 — Linked edge findings (cataloged, counted in owning phase)
| ID | Edge finding | Owning |
|---|---|---|
| P13-07 | Day-transition/TZ wrong-day attribution (streaks, "0 days left") | P8-01/20 |
| P13-08 | Fail-open dues/closure gates under network blip | P3-06 |
| P13-09 | Expired-member home-allows/scanner-rejects inconsistency | P3-04 |
| P13-10 | False-success banners for pending/failed actions | P9-02/03/17 |
| P13-11 | Release-build silent failure → edge errors invisible | P12-02 |
| P13-12 | Offline fake-success + silent discard on resync | P3-03/P12-08 |
| P13-13 | Corrupt record (`as int`) throws whole list | P8-17/P11-13 |
| P13-14 | Self-escalation / billing-bypass as "unexpected action" | P10-06/07 |
| P13-15 | Notifications stub hides all edge alerts | P9-01 |

---

## 8. QA Failure Matrix (by class)

| Class | Findings | Worst examples |
|---|---|---|
| **FUNCTIONAL FAILURE** | P7-01/03, P4-04, P9-01, P13-04 | Close-Today no-op; notifications stub; seats only first shift |
| **DATA-INTEGRITY FAILURE** | **P13-01, P13-02**, P5-01/02/03/06, P10-05 | dup memberships/attendance; seat overwrite; free-write membership |
| **RECOVERY FAILURE** | **P13-04, P13-05**, P12-01/03, P11-12 | no draft; partial writes; no session recovery; lossy sync |
| **UX FAILURE** | P9-03/04/14/16, P13-06 | false success; "pay securely" lie; no CTA |
| **TRUST FAILURE** | P9-01/02, P3-03, P4-02, P10-11 | payment theatre; fake notifications; forgeable audit |
| **SECURITY-RELEVANT** | P10-01…08, P13-14 | self-escalation; PII exposure; billing bypass |
| **PERFORMANCE-RELEVANT** | P11-01/02/03, P13-01 (dup scans) | analytics freeze; dup-inflated aggregates |
| **UNVERIFIED** | races (P13-02), TZ on-device (P8-01) | need emulator/fault-injection (V-48…50) |

---

## 9. Recovery Capability Register

| Scenario | Recovery mechanism present? | Quality |
|---|---|---|
| Session expiry | ❌ none (no `onAuthStateChange`) | absent |
| Network loss (general) | ❌ no retry UI (only QR queue) | absent |
| App-kill mid-flow (member) | ❌ no draft | absent |
| App-kill mid-flow (admin add-member) | ✅ draft_service | good |
| Offline check-in | ⚠️ queue, but lossy/dup | weak |
| Failed write (partial) | ❌ no rollback/reconcile | absent |
| Duplicate created | ❌ no dedup | absent |
| Wrong/expired QR | ✅ structured `_handleFailure` | good |
| Failed payment | ❌ can't fail / swallowed | absent |
| **Overall** | **~2 of 9 recoverable** | **3/10** |

---

## 10. Data-Corruption Risk Register

| Risk | Trigger | Result | Sev |
|---|---|---|---|
| Duplicate active memberships | double-submit/concurrency (P13-01) | double billing, seat conflict, wrong revenue | 🟠 |
| Duplicate attendance | offline resync/double-tap (P13-01) | inflated streaks/hours/leaderboard/revenue | 🟠 |
| Seat double-booking | concurrent assign (P13-02) | two members, one seat; desync | 🟠 |
| Free-write membership/role | RLS holes (P10-05/06) | corrupted entitlements | 🔴 (P10) |
| Orphaned half-write | network loss mid-multistep (P13-05) | membership w/o payment; checkin w/o checkout | 🟠 |
| Wrong-day attendance | TZ off-IST (P8-01) | corrupted day buckets | 🟡 |
| Lost attendance | 3-retry delete / discard (P11-12/P12-08) | attendance gaps | 🟡 |

---

## 11. User Confusion Register

| Confusion | Source | Likely user reaction |
|---|---|---|
| "I submitted — where's my seat?" | celebratory success for pending (P9-03) | re-submit (dup), call support |
| "App said all caught up — I missed renewal" | notifications stub (P9-01) | anger, churn |
| "I paid but it says I owe" | mock payment + dues (P9-02/P3) | dispute |
| "My streak reset though I came" | TZ/day bug (P8-01) | distrust analytics |
| "0 days left but I can still use it" | inDays truncation (P8-20) | panic then distrust |
| "Why are there two of me / two check-ins" | duplicates (P13-01) | confusion, support |
| "Occupancy 0% but library is full" | no-seats=0% (P9-13) | wrong decisions |

---

## 12. Trust Failure Register (edge-condition view)

| Rank | Trust breaker under edge conditions | Evidence |
|---|---|---|
| 1 | Success shown for failed/pending/duplicate actions | P9-02/03/17 + P13-01/10 |
| 2 | Notifications never deliver edge alerts | P9-01 |
| 3 | Offline fakes success then silently drops | P3-03 + P12-08 |
| 4 | Money paths lie (mock pay, wrong amount, dup) | P9-02/04, P4-03, P13-01 |
| 5 | Analytics visibly wrong at edges (streak/0-days/dup) | P8 + P13-01 |
| 6 | No recovery → user stuck, must contact support | P12-01, P13-04/05 |

---

## 13. Support Escalation Priority Matrix

> **Priority = Likelihood × Severity × (Recovery difficulty).** P1 = will flood support.

| Edge case | Likelihood | Severity | Recovery diff. | Support burden | **Priority** |
|---|---|---|---|---|---|
| Missed renewal (notifications stub) | High | High | Easy (manual) | High volume | **P1** |
| "Paid but not active" (mock/dup/swallow) | High | High | Hard (refund) | High + financial | **P1** |
| Duplicate membership/check-in | Med | High | Hard (manual dedup) | Med + data fix | **P1** |
| Offline check-in lost/dup | Med-High | Med | Hard | Med | **P2** |
| Seat double-booking | Med | Med | Med (manual reassign) | Med | **P2** |
| Session expiry dead app | Med | Med | Easy (relaunch) | Med (confusing) | **P2** |
| Join progress lost (no draft) | Med | Med | None (re-do) | Med (abandonment) | **P2** |
| Wrong streak / "0 days left" | High | Low | n/a | Low-Med (complaints) | **P3** |
| Occupancy 0% confusion | Med | Low | n/a | Low | **P3** |
| Raw error strings | Med | Low | n/a | Low | **P3** |

---

## 14. Improvement Suggestions (QA-driven, sequenced)
1. **Add DB uniqueness + idempotency (P13-01/03):** partial-unique indexes + server idempotency keys — kills the duplicate class outright.
2. **Concurrency-safe seat assignment (P13-02):** conditional update + rows-affected check.
3. **Member-side drafts + interruption recovery (P13-04):** reuse `draft_service`.
4. **Transactional multi-step mutations + reconciliation (P13-05):** server RPC.
5. **Honest states everywhere:** confirm-before-celebrate, real notifications, retry UI (closes P9/P12 edges).
6. **Edge-case test suite (this phase → automated):** double-submit, offline→online dup, IST-midnight, concurrent seat, session-expiry, 0/1/huge records. Wire into CI.

## 15. Priority Fix List (Phase 13, ordered)
1. **P13-01** — Uniqueness/idempotency (data-integrity, P1 support).
2. **P13-02** — Concurrency-safe seats.
3. **P13-05** — Transactional writes + reconciliation.
4. **P13-04** — Member draft/resume.
5. **P13-03 / P13-06** — Server idempotency; disable-during-async.
6. (Linked) honest states + recovery from P9/P12.

---

## 16. Feature Checklist (Phase 13 scope — QA/edge)
| Q | Verdict |
|---|---|
| Correct under edge conditions | **No** — duplicates, races, TZ, partial writes. |
| Usable when interrupted | **No** — member flows lose work. |
| Recoverable | **No** — ~2 of 9 scenarios recover. |
| Fails safely | Rarely. |
| Fails visibly | Almost never (silent/false-success). |
| Corrupts/inconsistent state | Yes — duplicates, seat overwrite, half-writes. |
| Production-ready (QA) | **No.** |

---

## 17. Verdict

**SILENCE passes the demo and fails the field.** Under the conditions real Tier-2/3 users create — flaky networks, interruptions, double-taps, expired sessions, shared seats, midnight check-ins — the app produces **duplicates it can't prevent, partial state it can't recover, and "success" messages it can't honor**, while its release-build silence (P12) ensures neither the user nor the team learns anything failed. **13 of 15 personas hit a failure that needs support or erodes trust, and recovery exists for almost nothing.** The edge-case defects are overwhelmingly **consequences of the same root cause named since Phase 1/6: no server tier** — without it, the database has no guard against the duplicates and races, and the client has no honest, recoverable failure path. **QA go/no-go: NO-GO** until P13-01/02/05 and the false-success/silent-failure chain (P9/P12) are fixed.

---

**Limitations honored:** Timing-dependent races (P13-02 seat concurrency, P13-01 offline dup) and on-device interruption/TZ behavior are code-inferred and need an emulator + fault-injection run (Verification Pending V-48 concurrent-seat race, V-49 offline→online duplicate repro, V-50 app-kill mid-join recovery). Catastrophic root causes are owned by Phases 5/6/10/11/12; Phase 13 demonstrates how they manifest under edge conditions. No code was modified.

**Next:** `Start Phase 14` — Play Store / App Store Readiness Audit.
