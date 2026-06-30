# SILENCE — Phase 8: Calculations & Data Accuracy Audit

**Phase:** 8 of 16 — Calculations & Data Accuracy Audit
**Completed (local time):** 2026-06-08
**Auditor roles:** Senior Data Analyst (lead) · Full-Stack Engineer · QA Lead · Senior PM · Security Auditor
**Goal:** Recompute every user-visible number by hand against the code that produces it. Find formula defects, timezone/date-boundary errors, rounding/precision loss, division-by-zero, and double-counting — especially where offline sync, missing tables, or unenforced rules (Phases 5–7) corrupt the inputs.
**Method:** Static recomputation against code + schema. Behavior **Code-Inferred** (no emulator/live DB). Every formula traced from DB column → aggregation → display string. Cross-checked against Phase 5 (schema), Phase 6 (data-access), Phase 7 (rules).
**Constraint honored:** No code modified.

---

## 1. Executive Summary — Do the Numbers Mean What They Say?

Phase 8 audited **9 metric families** across 7 files: occupancy %, revenue/profit/dues, study hours, streaks, attendance rate, leaderboard, badges, expiry countdowns, and the heatmap/trend aggregates. The verdict: **the arithmetic is mostly mechanically correct, but the numbers are systematically *wrong-by-construction* because they rest on broken inputs and inconsistent time/date handling.** A formula that divides correctly still lies if its numerator is fabricated revenue (P7/P4-03) or its denominator silently excludes timezone-shifted days.

**Distribution:** 1 Critical · 6 High · 9 Medium · 5 Low (21 findings, P8-01 … P8-21).

**The five structural defects that poison many metrics at once:**

1. **Timezone inconsistency is pervasive and self-contradictory.** The same app computes "which day" three different ways: `.toLocal()` (device TZ), a hardcoded `toIST()` (+5:30), and raw UTC `DateTime.parse()` with no conversion. The streak engine keys days off `DateTime.now()` (device local) while attendance days are bucketed by `.toLocal()` — on a device not set to IST, a 11:30 PM IST check-in lands on the *previous* day, silently breaking streaks, attendance %, heatmap cells, and "days present." (P8-01, Critical.)

2. **Duration is trusted from a column that Phase 7 proved is never reliably written.** Almost every hour total reads `duration_minutes` (or `check_out − check_in`). With auto-checkout unimplemented (P7-04) and `session_type='incomplete'` sessions common, hours are under-counted in some paths and *over*-counted in others (open sessions billed to `DateTime.now()`). The two behaviors are not reconciled. (P8-04, P8-05.)

3. **Two analytics tables referenced in code do not exist in the schema.** `member_daily_stats` and `streaks` have **no `CREATE TABLE`** in `supabase_schema.sql`. Every call hits the `catch` and silently uses the Dart fallback — so the "fast path" is dead code, and the app pays a full attendance scan on every analytics load while *appearing* to have precomputed stats. (P8-02, High.)

4. **Revenue is real arithmetic over fake data.** `_totalRevenue`, `_netProfit`, donut splits, and shift/plan comparisons sum `payments.amount` correctly — but Phase 4/7 proved that amount is hardcoded (`1500/4000/7500`), discounts are never applied, and payments are self-confirmable. The analytics tab presents fabricated money to two decimals of false confidence. (P8-08, High — inherited mechanism.)

5. **Trend / "vs previous period" math has real bugs:** a `prevRev == 0 → +100%` rule that mislabels first-ever revenue as growth, a month-comparison helper that mishandles month-length, and a typo'd key (`prevStats['prevDaysAbsent']`) that never exists so absent-trend silently falls back. (P8-09, P8-10, P8-11.)

**Data-Accuracy Score: 3 / 10.** The calculator is honest; its inputs and its clock are not. No number in the admin or member analytics surface can currently be trusted for a business decision.

**Connect-back:** P8 is the *measurement layer* sitting on P5 (schema drift — missing tables), P6 (no server validation), P7 (unenforced rules + fabricated amounts). Fixing formulas without fixing those inputs changes nothing.

---

## 2. What Was Reviewed
Every computed value rendered to a user in the audited files: percentages, currency, durations, counts, ranks, streaks, countdowns, chart series, and CSV/export aggregates. Each traced from source column → transform → display.

## 3. Files Reviewed
`lib/utils/time_utils.dart`, `lib/core/member_analytics_service.dart` (1,077 ln), `lib/screens/admin_analytics_tab.dart` (5,443 ln), `lib/screens/member_analytics_tab.dart` (2,945 ln), `lib/screens/admin_home.dart` (4,832 ln), `lib/screens/member_home.dart` (5,384 ln), `lib/screens/past_library_detail_screen.dart` (1,576 ln); schema columns/types from `silence_app/supabase_schema.sql`.

## 4. Metrics Reviewed
Live occupancy %, active-rate %, revenue (month/today/total/net/donut/shift/plan/trend), pending/expired/expiring dues, expected-renewal revenue, study hours (member & admin & export), attendance rate, days present/absent, current/best streak, last-7-days strip, leaderboard rank + gap-to-top-5, badge thresholds, expiry/trial countdowns, activity heatmap, avg hours/session.

---

## 5. Findings

### P8-01 — Three contradictory "which day" definitions across the codebase 🔴 Critical
**Category:** Timezone / Date-boundary correctness
**Evidence:**
- `time_utils.dart:3` hardcodes IST: `utc.add(Duration(hours: 5, minutes: 30))`.
- `member_analytics_service.dart:158,384,487,1000` bucket attendance days via `DateTime.parse(checkIn).toLocal()` (**device** timezone).
- `member_analytics_service.dart:391,452` and `member_home.dart:728,737` compute streaks off `DateTime.now()` (**device** local, no IST).
- `admin_home.dart:595` parses payment date `.toLocal()`; `admin_analytics_tab.dart:595` also `.toLocal()`; but `_getClosures` (`member_analytics_service.dart:36`) compares **date strings** with no TZ at all.
**Root Cause:** No single "business day in IST" helper is used consistently. `toIST()` exists but the analytics/streak paths use `.toLocal()` / `DateTime.now()` instead.
**Impact:** On any device not set to IST (CI servers, travelling users, emulators defaulting to UTC/PST), a late-evening IST session is attributed to the wrong calendar day. This silently corrupts: days-present, attendance %, current/best streak, last-7-days strip, heatmap cells, daily revenue trend buckets, and "best/weakest day." Two users in different timezones see different stats for the same data.
**Exploitation/Failure Scenario:** Member checks in 11:45 PM IST. Device is UTC. `.toLocal()` → 18:15 same UTC day (OK here) but `DateTime.now()` streak pointer also UTC → "today" is the UTC date, which already rolled differently from the IST attendance bucket → streak shows broken when it isn't. Reverse for UTC+ devices.
**Recommended Fix:** Introduce one `istDay(DateTime utc) → 'yyyy-MM-dd'` built on `toIST()` and route **every** day-bucketing and streak comparison through it. Never use `.toLocal()` or bare `DateTime.now()` for business-day logic.

### P8-02 — Analytics reads two tables that don't exist; "fast path" is dead, scan path always runs 🟠 High
**Category:** Schema drift / performance-masking
**Evidence:** `member_analytics_service.dart:78` (`member_daily_stats`) and `:340` (`streaks`) are wrapped in try/catch that logs *"table not available"* and falls through. `supabase_schema.sql` has **no `CREATE TABLE member_daily_stats`** and **no `CREATE TABLE streaks`** (grep confirms `present_flag`/`total_minutes`/those table names absent).
**Root Cause:** Precompute tables were designed (and coded against) but never migrated; the fallback was left as the real implementation.
**Impact:** (a) Every member-analytics load silently throws + catches a PostgREST error (noise, latency). (b) The full `attendance` scan runs every time, so this is also a Phase 11 performance defect. (c) Anyone reading the code assumes precomputed stats exist. (d) The `consistent` badge loop (`:630`) calls `_calculateStatsForRange` 6×, each re-throwing on the missing table.
**Recommended Fix:** Either create the tables + a trigger/job to populate them, or delete the dead fast-path branches and the `streaks` branch so the scan is the explicit, single source of truth.

### P8-03 — `parseDBTimeToUtc` treats naive timestamps as UTC, but Postgres `timestamptz` already serializes with offset — double/zero conversion risk 🟠 High
**Category:** Timezone parsing
**Evidence:** `time_utils.dart:31-46`: if the string lacks `Z`/`+`, it rebuilds it as `DateTime.utc(...)` — i.e. assumes the wall-clock is UTC. Elsewhere the same raw strings are fed to `DateTime.parse(...).toLocal()` (analytics) which assumes they carry an offset.
**Root Cause:** Inconsistent assumptions about whether DB timestamps include a timezone offset.
**Impact:** If a column is ever stored/returned without an offset (e.g. `date`/`timestamp` vs `timestamptz`, or an offline-synced value), one code path treats it as UTC and another as local — up to a 5.5h skew on the same value depending on which helper reads it.
**Recommended Fix:** Standardize all timestamp columns as `timestamptz`; parse with one helper; assert offset presence in debug.

### P8-04 — Study hours under-count: incomplete/open sessions contribute 0 in member paths 🟠 High
**Category:** Aggregation correctness
**Evidence:** `member_analytics_service.dart:162` (`if sessionType != 'incomplete' && duration != null` → add) and `:884`, `:1001` (`if sessionType == 'incomplete' continue`). `member_home.dart:338-341` only adds hours when `check_out_time != null`. `past_library_detail_screen.dart:190-194` same.
**Root Cause:** Sessions with no checkout (auto-checkout never implemented — P7-04) are dropped entirely from totals.
**Impact:** A member who checks in daily but never scans out (common; checkout is a second QR scan, P7) shows **0 study hours** and may still get "days present" — internally inconsistent. Total study hours systematically under-reported.
**Recommended Fix:** Decide a policy (cap open sessions at shift-end or N hours) and apply it uniformly; surface "session not closed" rather than silently zeroing.

### P8-05 — Admin paths OVER-count the same open sessions by billing to `DateTime.now()` 🟠 High
**Category:** Aggregation correctness / inconsistency with P8-04
**Evidence:** `admin_analytics_tab.dart:2950-2951` (`checkOut ?? DateTime.now()` then `/60`), `:3177-3178` (`co = coStr != null ? parse : DateTime.now()`), `:3272`.
**Root Cause:** Admin analytics assume an open session is "still running" and count elapsed time to *now*; member analytics (P8-04) count it as zero.
**Impact:** The **same attendance row** yields different hours on the admin screen vs the member screen and the CSV export. An abandoned session from 5 days ago (never closed) is billed as a ~120-hour session in admin leaderboards/exports. Directly inflates admin "Total Hours," avg hours/session (`:3197`), and member-wise CSV.
**Exploitation:** Member checks in, leaves without scanning out. Admin's member-attendance CSV shows them as the top studier with hundreds of hours.
**Recommended Fix:** One shared duration function with an explicit open-session policy (clamp to shift end / max session length), used by member, admin, and export alike.

### P8-06 — Occupancy % counts seats, not the multi-shift model it advertises 🟠 High
**Category:** Formula vs domain model
**Evidence:** `admin_home.dart:611-626`: `_totalSeats = activeSeats.length`, `_occupancyPercentage = occupied/total*100`, where `activeSeats` is filtered to the *current* shift's seats. But P7-01 proved setup only generates seats for the **first** shift.
**Root Cause:** Occupancy denominator is "rows in `seats` for the current shift," which is empty/partial for non-first shifts.
**Impact:** During a shift that has no generated seats, `_totalSeats == 0` → occupancy renders `0%` (the guard returns 0.0) even if members are physically present. During the first shift it may look 100%. Occupancy is not comparable across shifts.
**Recommended Fix:** Fix seat generation (P7-01) first; then define occupancy against capacity, not row count.

### P8-07 — "Active rate" and live occupancy mix incompatible numerators/denominators 🟡 Medium
**Category:** Formula semantics
**Evidence:** `admin_home.dart:2662` `activeTodayCount / totalActiveMembers * 100` ("active rate"); `admin_analytics_tab.dart:3048-3049` shift occupancy uses `activeCount / (totalSeatsCount==0 ? 30 : ...) * 100` — a **magic fallback of 30 seats**.
**Root Cause:** Denominators chosen for "a number that renders," not a defined capacity.
**Impact:** The `?? 30` fallback fabricates a denominator, so occupancy % is meaningful only when seats happen to be generated; otherwise it silently assumes a 30-seat library. Misleads capacity planning.
**Recommended Fix:** Use real library capacity; render "—" when capacity is unknown rather than assuming 30.

### P8-08 — Revenue, net profit, and donut splits are precise sums of fabricated amounts 🟠 High
**Category:** Input integrity (inherited P4-03/P7)
**Evidence:** `admin_analytics_tab.dart:591,600,649,664` (`curRev += amt`, `_netProfit = curRev - curExp`), donut `:4756`. `admin_home.dart:538-548`. Amounts originate hardcoded at approval (P4-03) and payments are self-confirmable (P6).
**Root Cause:** The metric layer faithfully sums values that the business layer fabricates.
**Impact:** `₹{_totalRevenue.toStringAsFixed(0)}`, net profit, expected-renewal revenue (`:2330,2356`), and cash/UPI/addon donut are all authoritative-looking but built on amounts that ignore discounts and actual payment. False financial reporting.
**Recommended Fix:** Out of scope to fix here, but every currency figure should be flagged "unverified" until P4-03/P7-02 (discount cap) are resolved and amounts are server-derived.

### P8-09 — `+100%` sentinel for zero-baseline trend mislabels first revenue as growth 🟡 Medium
**Category:** Trend math
**Evidence:** `admin_analytics_tab.dart:650`: `_revenueChangePct = prevRev == 0.0 ? 100.0 : ((cur-prev)/prev)*100`.
**Root Cause:** Division-by-zero avoided with a constant `100.0` that is presented as a real percentage with a `+` sign (`:2182`).
**Impact:** A library's first-ever month shows "+100.0% vs prev" implying doubling, not "no prior data." If `prevRev>0` and `curRev==0`, it correctly shows -100%, but the asymmetry is confusing.
**Recommended Fix:** When `prevRev == 0`, render "New" / "—", not a numeric %.

### P8-10 — Previous-month comparison window is off for unequal month lengths 🟡 Medium
**Category:** Date-range math
**Evidence:** `member_analytics_service.dart:203-217` `_getPreviousPeriod('this_month')`: clamps `prevDay` to `lastDayOfPrevMonth` but builds `prevStart` at day 1 and compares against a current range whose *start* may not be day 1.
**Root Cause:** "Previous month" assumes current range starts on the 1st; if the current range is a partial month (e.g. month-to-date), the prior window is a full-month-to-clamped-day — unequal elapsed days.
**Impact:** Month-over-month deltas compare a partial current period against a differently-sized previous period → distorted % change. Compounds with the elapsed-days logic in `_calculateStatsForRange` (`:107-115`).
**Recommended Fix:** Define previous period as "same number of elapsed days, shifted back," not "calendar month boundaries."

### P8-11 — Typo'd key makes absent-day trend silently fall back to current value 🟡 Medium
**Category:** Bug — wrong key
**Evidence:** `member_analytics_service.dart:277`: `'prevDaysAbsent': prevStats['prevDaysAbsent'] ?? prevStats['daysAbsent']`. `_calculateStatsForRange` returns only `daysAbsent` (`:119-123,182-187`), never `prevDaysAbsent`. So the left operand is **always null** and it always uses `prevStats['daysAbsent']` — meaning the line is dead but *harmless by accident*; however line `:259` in the `all_time` branch sets `prevDaysAbsent` from `currentStats['daysAbsent']`, so naming is inconsistent and fragile.
**Root Cause:** Copy-paste of a non-existent key.
**Impact:** Currently masked, but any refactor that trusts `prevDaysAbsent` will break. Indicates the trend object schema is unverified.
**Recommended Fix:** Remove the `prevStats['prevDaysAbsent'] ??` and standardize the prev-object keys.

### P8-12 — Attendance-rate denominator (`elapsedDays − closedDays`) double-discounts and can misclassify 🟡 Medium
**Category:** Formula correctness
**Evidence:** `member_analytics_service.dart:107-116,170-180`: `elapsedDays = (min(now,end) − start)+1`; `totalActiveDays = elapsedDays − closedDaysCount`; `attendanceRate = daysPresent/totalActiveDays*100` clamped to 100. `daysAbsent = elapsedDays − daysPresent − closedDaysCount` clamped ≥0.
**Root Cause:** `closedDaysCount` is counted within `[start,end]` regardless of whether those closed days fell *before* `now`/elapsed window; a closure scheduled later in the range still shrinks the denominator. Also `daysPresent` can include a day that is also a closed day (member came on a "closed" day), making `present + closed > elapsed` → absent clamped to 0 hides the inconsistency.
**Impact:** Attendance % can exceed reality (smaller denominator) or absent days vanish. The `>100 → 100` clamp (`:116`) is a symptom that the formula already overshoots.
**Recommended Fix:** Compute closed days only within the elapsed (≤now) sub-window; ensure present∩closed days are reconciled before subtraction.

### P8-13 — Two different "best streak" algorithms; admin/member/past-library disagree 🟡 Medium
**Category:** Duplicated logic divergence
**Evidence:** Three implementations: `member_analytics_service.dart:410-439` (closure-aware: bridges gaps if all intermediate days closed), `member_home.dart:751-778` (`_calculateBestStreak`, **not** closure-aware), `past_library_detail_screen.dart:212-240` (`_computeBestStreak`, not closure-aware, and only updates `bestStreak` on gap — see P8-14).
**Root Cause:** Streak logic copy-pasted and diverged; only the service version honors closures.
**Impact:** The same member sees different "best streak" on home vs analytics vs past-library detail. Closure-aware vs not produces materially different numbers for libraries with weekly offs.
**Recommended Fix:** Single shared streak utility (closure-aware) used everywhere.

### P8-14 — `past_library_detail` best-streak can under-report the final run 🟡 Medium
**Category:** Off-by-one / loop boundary
**Evidence:** `past_library_detail_screen.dart:227-239`: loops `i < length-1`, only comparing adjacent diffs; updates `bestStreak` on `diff>1`. The trailing `if (currentStreak > bestStreak) bestStreak = currentStreak` (`:238`) saves the last run — so this one is actually OK — **but** a `diff == 0` (duplicate date, impossible after Set, fine) and the `diff` not equal to 1 or >1 path leaves `currentStreak` unchanged. Confirmed correct for the dedup'd set; flagged Medium because the member_home variant (`:763-778`) uses the same shape and is the canonical risk if dedup is ever removed.
**Root Cause:** Fragile last-run handling across copies.
**Impact:** Low today (Set dedup protects it); becomes a real off-by-one if inputs change. Documented to prevent regression.
**Recommended Fix:** Fold into the shared utility (P8-13) with explicit last-run handling + tests.

### P8-15 — Current-streak engine assumes "today not yet checked in" is free, but uses device clock 🟡 Medium
**Category:** Streak boundary
**Evidence:** `member_analytics_service.dart:402-405` and `member_home.dart:727-748`: if `ptr == today` and not attended, it skips today (doesn't break). Today is `DateTime.now()` device-local (see P8-01).
**Root Cause:** "Grace for today" keyed off device midnight, not IST midnight.
**Impact:** Around IST midnight, "today" differs from the IST attendance day → streak either breaks a day early or extends a day late depending on device TZ.
**Recommended Fix:** Key the grace day off IST (P8-01 fix).

### P8-16 — Leaderboard `gapToTop5` only computed when ≥5 ranked; ties and sub-5 libraries get 0 🟢 Low
**Category:** Edge case
**Evidence:** `member_analytics_service.dart:785-791`: `gapToTop5` set only `if (rankedList.length >= 5)`; otherwise stays 0.0.
**Impact:** In libraries with <5 active members the "gap to top 5" UI shows 0 (looks like "you're in top 5") which is technically true but the metric is undefined; minor.
**Recommended Fix:** Hide the metric when `totalMembersCount < 5`.

### P8-17 — Leaderboard duration cast `as int` will throw if column is numeric/null 🟡 Medium
**Category:** Type safety
**Evidence:** `member_analytics_service.dart:301,302` `final duration = record['duration_minutes'] as int;` and `:731`. Schema: `attendance.duration_minutes INTEGER` (`supabase_schema.sql:167`) — nullable. The query filters `.not('duration_minutes','is',null)` (`:295,724`) so null is excluded, but a hard `as int` (vs `as num`) is brittle if offline-synced rows store it as a double.
**Root Cause:** Hard cast to `int` instead of `as num`.
**Impact:** A single non-int value throws and the **entire leaderboard fails** (no per-row guard), unlike other paths that use `as num?`.
**Recommended Fix:** Use `(record['duration_minutes'] as num).toInt()`.

### P8-18 — Payment amount is INTEGER but expenditures are NUMERIC — profit mixes precision 🟢 Low
**Category:** Schema/type consistency
**Evidence:** `supabase_schema.sql:183` `payments.amount INTEGER`; `:422` `expenditures.amount NUMERIC(10,2)`. `admin_analytics_tab.dart:591,661,664` sums both as `double` then `_netProfit = curRev - curExp`.
**Root Cause:** Rupee amounts modeled as whole integers for payments but decimals for expenses.
**Impact:** Net profit subtracts a 2-decimal expense from an integer revenue; display is `toStringAsFixed(0)` so rounding hides it, but any future paise-level revenue is impossible and reports can be off by sub-rupee accumulation.
**Recommended Fix:** Standardize on `NUMERIC(10,2)` (or integer paise) across both.

### P8-19 — Heatmap/daily-trend bucket by `.toLocal()`; "best/weakest day" inherits TZ + tie bias 🟡 Medium
**Category:** Aggregation + TZ
**Evidence:** `member_analytics_service.dart:882,889-895` (bucket key `.toLocal()`), `:909-930` best/weakest pick first strict `>max` / `<min`. `minHours` init `double.infinity`; a day with exactly 0 never becomes weakest (correct), but ties pick the earliest-iterated day arbitrarily.
**Root Cause:** TZ bucketing (P8-01) + non-deterministic tie-break.
**Impact:** "Best day: Tuesday" can flip with device TZ and is arbitrary on ties.
**Recommended Fix:** IST bucketing; define tie-break (latest, or list all).

### P8-20 — Expiry/trial countdowns use `inDays` truncation → "0 days left" on the last day 🟡 Medium
**Category:** Countdown rounding
**Evidence:** `member_home.dart:1560` `trialDaysLeft = parse(end).difference(now).inDays`; `:1653` `daysLeft = parse(end).difference(now).inDays` (clamped ≥0). `inDays` truncates toward zero.
**Root Cause:** `Duration.inDays` floors; a membership ending tonight (e.g. 8h away) reports `0` days left.
**Impact:** "0 days left" shown while still active all day; "Only 0 days left on your plan" (`:1668`) reads as expired. Also `end_date` is a `date` (midnight) compared against `DateTime.now()` with time component → consistently one day short.
**Recommended Fix:** Compare IST calendar dates: `daysLeft = endDateIST.difference(todayIST).inDays` using date-only values; or `ceil` the duration.
**Cross-ref:** Phase 3 `expiringSoon` state (`member_home.dart:31`).

### P8-21 — Distance (Haversine) is correct but unguarded against null coords → silent 0 km 🟢 Low
**Category:** Calculation robustness
**Evidence:** `member_home.dart:718-725` Haversine is mathematically correct (R=6371). Callers pass library lat/lng that may be null/0 (schema allows null), yielding "0 km away" for un-geocoded libraries.
**Impact:** Explore/nearby sorting treats un-located libraries as "right next to you," ranking them first. Minor but misleading.
**Recommended Fix:** Skip/deprioritize libraries with null coordinates.

---

## 6. Missing Connections
- **`member_daily_stats` / `streaks` tables → no schema, no writer.** Code consumes them (`:78,:340`) but nothing creates or populates them (P8-02). The `_awardBadge` writer (`:685`) writes `badges` + `notifications`, but `streaks` is never written by anyone → fallback-only forever.
- **Duration policy → no shared source.** Member, admin, and export each re-derive hours with different open-session handling (P8-04/05). No single `sessionDurationMinutes()` utility.
- **Streak utility → 3 copies, 1 closure-aware** (P8-13). No connection between them.
- **IST helper → exists (`toIST`) but disconnected** from the analytics/streak paths that need it (P8-01).
- **Occupancy capacity → no `capacity` source;** denominator improvised from seat rows or magic `30` (P8-06/07).

## 7. Incomplete / Half-Built Calculations
- Precompute fast-path (`member_daily_stats`, `streaks`) — coded, never migrated (dead branch).
- `prevDaysAbsent` trend key — referenced, never produced (P8-11).
- Closure-aware streak — implemented only in the service, not propagated.
- Expected-renewal revenue (`:2330,2356`) — sums pending dues as if guaranteed; no probability/▲ for churn.
- Badge thresholds (`early_bird hour<7`, `night_owl hour>=20`, `:609`) use `.toLocal()` hour, not IST → wrong bucket off-IST (extends P8-01).

## 8. Improvement Suggestions
1. **One clock.** A single `IstClock`/`istDay()` utility; ban `.toLocal()` and bare `DateTime.now()` in business-day logic (lint rule). Fixes P8-01, 15, 19, 20, and badge buckets in one stroke.
2. **One duration function** with explicit open-session policy; reuse in member/admin/export (P8-04/05).
3. **One streak utility** (closure-aware) (P8-13/14/15).
4. **Decide the precompute story:** build `member_daily_stats`+`streaks` with triggers, or delete the dead branches (P8-02). Either fixes correctness *and* Phase 11 perf.
5. **Trend honesty:** "New"/"—" for zero baselines; equal-length comparison windows (P8-09/10).
6. **Type hygiene:** `as num` not `as int` (P8-17); unify currency type (P8-18).
7. **Golden tests:** lock each formula with fixture-based unit tests (feeds Phase 13). Especially TZ boundary cases at IST midnight.

## 9. Priority Fix List (ordered)
1. **P8-01** (Critical) — Unify on IST business-day; remove `.toLocal()`/`DateTime.now()` from day/streak logic.
2. **P8-05 + P8-04** (High) — Single duration policy; stop billing open sessions to `now` in admin/export.
3. **P8-02** (High) — Resolve missing `member_daily_stats`/`streaks` (build or delete branch).
4. **P8-03** (High) — Standardize timestamp parsing (`timestamptz` end-to-end).
5. **P8-06/07** (High/Med) — Fix occupancy denominator (depends on P7-01 seat generation); kill magic `30`.
6. **P8-08** (High, inherited) — Flag all currency as unverified until P4-03/P7-02 land.
7. **P8-09/10/11/12** (Med) — Trend + attendance-rate formula fixes.
8. **P8-13/14/15** (Med) — Consolidate streak logic.
9. **P8-17** (Med) — `as num` cast on leaderboard duration.
10. **P8-16/18/19/20/21** (Low/Med) — Edge cases, type unification, countdown rounding, distance guard.

---

## Feature Checklist (Phase 8 scope — analytics & computed values)
| Q | Verdict |
|---|---|
| Why added | Give admins/members decision-useful metrics — **valid intent.** |
| Solves problem | Partially; numbers exist but are untrustworthy (P8-01/08). |
| Flow complete | No — precompute tables missing (P8-02); duration policy split. |
| FE↔BE connected | Reads exist; two reads hit non-existent tables (P8-02). |
| DB correct | Type mismatch (P8-18); missing analytics tables (P8-02). |
| Permissions correct | Out of scope here (see Phase 10). |
| Data accurate | **No** — TZ, duration, fabricated amounts (P8-01/04/05/08). |
| Usable | Renders cleanly; that's the danger — false precision. |
| Edge cases | Many unhandled: zero baseline, <5 members, open sessions, IST midnight. |
| Abuse/hack | Open-session inflation gameable (P8-05); inherited payment fabrication. |
| UI clear | Yes — `toStringAsFixed` everywhere; clarity exceeds correctness. |
| UX smooth | Yes, but trust-destroying once a user spots a wrong streak. |
| Production-ready | **No.** |

---

**Limitations honored:** No live DB or device — TZ defects (P8-01) reasoned from code + schema, to be confirmed on an emulator set to a non-IST timezone (a one-line QA test). Fabricated-amount findings (P8-08) inherited from verified Phases 4/7, not re-litigated here.

**Next:** `Start Phase 9` — UI/UX Audit.
