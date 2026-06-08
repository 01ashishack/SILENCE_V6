# SILENCE — Phase 11: Performance & Scalability Audit

**Phase:** 11 of 16 — Performance & Scalability Audit
**Completed (local time):** 2026-06-08
**Auditor roles:** Senior Performance/Backend Engineer (lead) · Database Engineer · Full-Stack Engineer · SRE/Operational-Readiness · Data Analyst · QA Lead
**Goal:** Determine whether SILENCE stays **responsive, accurate, and operational at real scale** — not a tidy-up review. Concretely: can it serve **100 / 500 / 1,000 libraries** and **5,000 / 20,000 / 100,000 members** without unacceptable degradation, and **where does it break first?**
**Method:** Static analysis of query patterns, embeds, loops, pagination, and aggregation across the heavy screens + the analytics service + offline sync; cross-checked against the schema's indexes. Load behavior is **modelled (Code-Inferred)** — declared limitation: no live project, no profiler, no load test; row-count → cost is reasoned from the queries and index plan, to be confirmed with `EXPLAIN ANALYZE` + a k6/Artillery run (V-41…V-44).
**Constraint honored:** No code modified. Audit only.

**Cross-phase rule applied:** every performance finding is also classified for impact on **Data Accuracy · User Trust · Security · Business Integrity · Operational Reliability.**

---

## 1. Executive Summary — Will it hold at scale?

**Partially, and not where it matters most.** The database layer is, surprisingly, the *least* of the problems: the schema carries **23 sensible indexes** (incl. `attendance(member_id, check_in_time)` and `attendance(library_id, check_in_time)` — `supabase_schema.sql:472-473`), and most queries are library- or member-scoped and index-supported. Postgres on a managed Supabase tier can hold **1,000+ libraries and 100,000+ members** as *rows* without trouble.

The failure is in the **client-direct, recompute-on-every-open architecture** (the structural debt from P1/P6/P10): SILENCE has no server aggregation tier, so **every heavy number is produced by pulling raw rows to the device and looping over them in Dart** — repeatedly, per screen open, with no pagination and no precomputation. Three patterns dominate:

1. **The analytics "fast path" is dead, so every load is a full scan (P11-01).** `member_daily_stats` and `streaks` don't exist in the schema (P5-03/P8-02); every call falls through to scanning the member's **entire attendance history** and aggregating in Dart (`member_analytics_service.dart:78,134,340,362`). A member with 2 years of daily check-ins re-scans ~700+ rows **several times per analytics open**.
2. **The badge engine is an N+1 explosion (P11-02).** `syncAndFetchBadges` runs a **6-month loop** (each iteration a full stats scan + closures query) and a **4-week loop** (each iteration a **library-wide** leaderboard scan that joins `users` per row), plus a full member-attendance scan — **~15-20 queries and up to 4 whole-library scans, on every analytics open, for one member** (`:621-672, 604`).
3. **The admin dashboard counts by downloading rows (P11-03).** `_fetchRealStats` fires **8+ sequential** queries that `select('id')` and count with `.length` in Dart instead of a server `count` (`admin_home.dart:490-596`). A 5,000-member library ships ~5,000 ids per counter, serially, on every home open.

Add **deep-nested over-fetch** in admin analytics (`attendance.select('*, member_id(*), memberships(*, seats(*), shifts(*)))` — `admin_analytics_tab.dart:498`), **no pagination anywhere** (explore downloads *every* active library to *every* device — `member_explore_screen.dart:62-68`), and a **strictly-sequential offline-sync loop** (2-4 round-trips per queued scan — `offline_sync.dart:52-179`), and the picture is clear.

**Where it fails first (in order):**
1. **Member/Admin analytics on a large/old library** — the badge N+1 + full-history scans. Degrades at **~1,500-3,000 members or ~1 year of history per library**.
2. **Admin dashboard** — 8 sequential count-by-fetch — multi-second loads beyond **~2,000 members/library**.
3. **Explore** — all-libraries-to-every-device — sluggish at **~1,000 libraries**, painful at **5,000**.
4. **Offline-sync reconnect storm** at peak check-in.

**Distribution (Phase 11):** 2 Critical · 5 High · 5 Medium · 2 Low (P11-01 … P11-14). **Performance posture: 3.5 / 10** — survives a pilot (one small/medium library), degrades badly at growth, and several of these defects are **both performance *and* correctness/trust** problems (the same dead-table fallback that's slow also produces the wrong streak — P8-02).

**Operational verdict:** **Pilot-ready (≤ ~50 libraries, small branches). NOT ready for 500+ libraries or any library above a few thousand members without a server-side aggregation/precompute tier.** The fix is the same missing piece flagged since Phase 1: a server tier (RPC/Edge + precomputed daily stats) — it resolves performance, accuracy (P8), and security (P10) at once.

---

## 2. Performance Architecture Map

```
                         ┌──────────────────────────────────────────────┐
   EVERY screen open ──► │  Flutter client (does ALL aggregation in Dart) │
                         └──────────────────────────────────────────────┘
                                   │  N direct REST calls per screen (no RPC)
        ┌──────────────────────────┼───────────────────────────────────────────┐
        ▼                          ▼                                            ▼
  PostgREST /rest/v1        PostgREST (embeds)                          Storage (images)
  (indexed, but returns     attendance.select('*, member_id(*),         public/​private URLs
   ALL matching rows —      memberships(*, seats(*), shifts(*)))         (Phase 10)
   no count(), no limit)    → multi-table payload per row
        │                          │
        ▼                          ▼
  ┌───────────────┐         ┌──────────────────────────────────────────────┐
  │  PostgreSQL   │         │  DEAD fast-path tables: member_daily_stats,    │
  │  25 tables,   │◄────────│  streaks  (never created — P5-03/P8-02)        │
  │  23 indexes   │         │  ⇒ every analytics call falls back to a        │
  └───────────────┘         │     FULL attendance scan + Dart aggregation    │
                            └──────────────────────────────────────────────┘
   Offline path:  sqflite offline_scan_queue ──(sequential, 2-4 RT/scan)──► Supabase
```
**Core property:** the app is a **thick client over a thin data API**. There is no materialized view, no `count`, no server aggregate, no job tier. Cost scales with **rows-returned × screen-opens**, not with the size of the answer. Indexes keep individual filters fast; the volume of returned rows and the **repeated re-derivation per open** are what degrade.

---

## 3. Query Inventory (per major screen) — classified

Legend: **OPTIMIZED** (server-bounded/aggregated) · **ACCEPTABLE** (bounded, scoped, modest) · **INEFFICIENT** (unbounded return / Dart aggregation, OK at small scale) · **HIGH-RISK** (N+1 / whole-table / per-open re-scan) · **UNVERIFIED** (needs live measurement).

| Screen / unit | Major queries (file:line) | Count/load | Pagination | Aggregation | Class |
|---|---|---|---|---|---|
| **Admin Home dashboard** (`admin_home.dart`) | users role `:155`; libraries `:327`; shifts `:417`; floors/seats `:437-448`; then `_fetchRealStats`: attendance `:490`, memberships ×5 `:502/512/521/553/573`, payments `:531`, shifts `:584`, seats `:593`; feeds: join_requests `:630`, attendance today `:723`, audit_log `:758` | **~16-18, mostly SEQUENTIAL** | none | counts via `.length`; revenue summed in Dart | **HIGH-RISK** |
| **Admin Analytics** (`admin_analytics_tab.dart`) | `Future.wait`: payments+embeds `:476`, expenditures `:482`, memberships `*,member_id(*),seats(*),shifts(*)` (no date filter) `:493`, attendance `*,member_id(*),memberships(*,seats(*),shifts(*))` `:498`, seats `:504`, trend memberships `:508`; +hold-noshow `:528` | **7 parallel + 1**, huge payloads | none | all member-wise sums in Dart `:2935-3200` | **HIGH-RISK** (over-fetch) |
| **Member Analytics** (`member_analytics_tab.dart` → service) | `fetchStreak` `:200`, `fetchAnalyticsSummary` (×2 internally) `:211/275`, `fetchLeaderboardDetails` `:344`, `fetchDailyStudyHours` `:307`, `fetchActivityHeatmap` `:378`, `syncAndFetchBadges` `:325` | **dozens** (see N+1 §5) | none | full-history scans, all Dart | **HIGH-RISK** |
| **Member Home** (`member_home.dart`) | 39 `.from`, **8 have `.limit`** — better; loads memberships, attendance, notifications-count, streak bits | ~12-15 | partial (8 limits) | streak/hours in Dart `:727-778` | **INEFFICIENT** |
| **Member Explore** (`member_explore_screen.dart`) | `libraries.select(...).eq('status','active')` **ALL active libraries** `:62`; fallback same `:77`; per-detail `:263` | 1 big + per-tap | **none** | filter+sort **all libs in Dart** `:138-188` | **HIGH-RISK** at library scale |
| **Notifications** (`notifications_screen.dart`) | **0 queries** — static stub (P9-01) | 0 | n/a | n/a | (broken, not slow) |
| **Member History** (`member_history_tab.dart`) | 14 `.from`, `select('*')` `:149`, **0 limits** | unbounded history | none | Dart | **INEFFICIENT→HIGH-RISK** |
| **QR Scanner** (`qr_scanner_screen.dart`) | membership/library lookups `+` insert; **2 limits present** | ~4-6 per scan | partial | minimal | **ACCEPTABLE** (per-scan); see peak §7 |
| **Layout sub-tab** (`layout_sub_tab.dart`) | 41 `.from`, `select('*')` `:186/2476/2487/2494`, **0 limits** | many | none | Dart | **INEFFICIENT** |
| **Leaderboard** (`service:285,714`) | `attendance.select('member_id,duration,users(...)').eq(library).range(dates)` — **whole library range**, join per row, **no limit** | 1 big / call (×4 in badges) | none | rank in Dart `:297-333` | **HIGH-RISK** |
| **Heatmap** (`service:955`) | full member attendance for range `:972` + closures `:979` | 2 / call | none | bucket in Dart | **INEFFICIENT** |
| **Export (admin member-wise)** (`admin_analytics_tab.dart:3160+`) | reuses `_attendanceLogs` (full nested fetch); builds CSV in `StringBuffer` over all rows `:3192-3203` | in-memory all | none | Dart | **HIGH-RISK** (memory) |
| **Offline sync** (`offline_sync.dart:52`) | per scan: resolve lib `:66`, find membership `:84`, insert `:102` / update `:138`, delete; sequential | **N×(2-4) sequential** | n/a | n/a | **HIGH-RISK** at backlog |

---

## 4. Analytics Scalability Investigation (deep)

| Subsystem | Intended fast path | Actually executed | When table missing | At 100k attendance rows | At 1M rows |
|---|---|---|---|---|---|
| **member_daily_stats** | precomputed per-day rows; analytics reads a handful | **dead** — table absent (P5-03); every call throws+catches `:127` and **scans raw attendance** | always (it's never created) | full member-range scan, Dart aggregation; ×2 (cur+prev) per summary | device memory + parse cost spikes; multi-second; jank/ANR risk |
| **streaks** | read `current/longest` in O(1) `:340` | **dead** — table absent; falls to **full member history scan**, `.order desc`, Dart streak walk `:362-439` | always | scans entire member history every open | unbounded; worst on long-tenured members |
| **attendance scans** | bounded, server-aggregated | unbounded row return, Dart sum/group (`:134,289,362,604,718,962`) | n/a | OK per-query (indexed) but **payload + Dart loop** grow linearly | large transfer; UI thread aggregation = jank |
| **leaderboard** | server top-N | whole-library range scan + `users` embed per row, sort in Dart `:289-333,714` | n/a | downloads **all** sessions in range for the library | heavy; ×4 inside badge `top_of_week` |
| **heatmap** | precomputed daily buckets | full member range scan + closures `:955` | n/a | linear | linear, plus closures `select('*')` |
| **admin analytics** | server aggregates | 7 parallel deep-embed fetches, Dart member-wise loop `:474-512,2935+` | n/a | multi-MB nested payload at month-end | likely OOM/jank on device |
| **member analytics (whole tab)** | one cheap call | **fetchStreak + summary×2 + leaderboardDetails + dailyHours + heatmap + badges(≈15-20q)** sequential | always (dead tables) | tens of queries, several full scans **per open** | unusable |

**Verdict:** the analytics design *assumed* a precompute tier (daily stats + streaks tables + presumably a job to fill them). That tier was never built (P5-03), so the written-as-fallback scan path **is** the implementation. This is the single biggest scalability liability and it is **both a performance and a correctness defect** (the same fallback yields the TZ-broken/duration-inconsistent numbers of P8).

---

## 5. N+1 Register

| # | Location | Loop | Query inside | Multiplier | Sev |
|---|---|---|---|---|---|
| N+1-1 | `member_analytics_service.dart:622-643` `consistent` badge | 6 iterations (last 6 months) | `_calculateStatsForRange` → **full attendance scan + closures query** each | **×6 = 12 queries** | 🔴 |
| N+1-2 | `member_analytics_service.dart:649-672` `top_of_week` badge | 4 iterations (last 4 weeks) | `fetchLeaderboardDetails` → **library-wide attendance scan + users embed** each | **×4 whole-library scans** | 🔴 |
| N+1-3 | `member_analytics_service.dart:604` early/night badge | — | full member attendance `select('check_in_time')` (unbounded) | ×1 full scan | 🟠 |
| N+1-4 | `member_analytics_tab.dart:200-399` tab load | sequential awaits | streak + summary×2 + leaderboard + dailyHours + heatmap + badges | compounded | 🟠 |
| N+1-5 | `admin_home.dart:502-573` `_fetchRealStats` | 5 membership counters | each a separate `select('id')` round-trip (sequential) | ×5 + others | 🟠 |
| N+1-6 | `offline_sync.dart:52-179` | per queued scan | resolve-lib + find-membership + insert/update + delete | ×N scans, ×(2-4) RT | 🟠 |

> **Root:** absence of precompute tables (P5-03/P8-02) + no server aggregation (P6-01). Each missing table converts an O(1) read into an O(history) scan, and the badge loops multiply it.

---

## 6. Over-Fetch Register

| # | Site | What's over-fetched | Cheaper alternative | Sev |
|---|---|---|---|---|
| OF-1 | `admin_analytics_tab.dart:498` | `attendance.select('*, member_id(*), memberships(*, seats(*), shifts(*)))` — full user+membership+seats+shifts **per attendance row** | select only needed cols; aggregate server-side | 🟠 |
| OF-2 | `admin_analytics_tab.dart:493` | `memberships.select('*, member_id(*), seats(*), shifts(*))` with **no date filter** — entire library history | bound by status/date; server count | 🟠 |
| OF-3 | `admin_home.dart:490-596` | counts fetched as row lists (`select('id')`) then `.length` | `count: 'exact', head: true` | 🟠 |
| OF-4 | `member_explore_screen.dart:62` | **all** active libraries (+shifts embed) to every device | server search + pagination + geo bbox | 🟠 |
| OF-5 | `member_analytics_service.dart:362` | entire member attendance history for a streak | precomputed `streaks` row | 🟠 |
| OF-6 | `*.select('*')` ×99 across `lib/` | whole rows where few columns are used | explicit column lists | 🟡 |
| OF-7 | `fetchAttendanceForExport:1040` / export `_attendanceLogs` | full nested rows materialized in memory for CSV | streamed/server export | 🟡 |

---

## 7. Performance Failure Simulations

| Scenario | Expected load | Likely bottleneck | Failure mode | User-visible impact | Recovery path |
|---|---|---|---|---|---|
| **New library** (0-20 members) | trivial | none | none | snappy | — |
| **Medium library** (300-800 members, 6mo history) | ~tens of K attendance rows | analytics full scans; dashboard sequential counts | 1-3s loads | acceptable but laggy analytics | add limits/count |
| **Large library** (3,000 members, 18mo) | ~300K+ attendance rows | **badge N+1 (×4 library scans) + member analytics full scans**; admin analytics nested over-fetch | 5-15s analytics; possible ANR/jank on mid devices | "app freezes on Analytics" | precompute tables + server aggregation |
| **Multi-branch operator** (10 branches, `libraryId='all'`) | `inFilter` across 10 libs, all history | heatmap/summary scan across all branches; no pagination | very large payloads; device memory | slow/instable cross-branch analytics | per-branch server rollups |
| **Peak check-in hour** (200 members in 30 min, one QR) | 200 check-ins + dashboard refresh `:667` | concurrent attendance inserts (fine) **but** each admin dashboard refresh re-runs 8 sequential counts; QR scans OK | dashboard lag while scanning floods | stale/slow admin numbers at the worst time | server counts; debounce refresh |
| **Month-end reporting** | admin opens Analytics + exports | OF-1/OF-2 deep-nested unbounded fetch; CSV built in memory | multi-MB download; `StringBuffer` over all rows; jank/OOM on large branch | "export hangs / app crashes" | server-side export job, streaming |
| **Large export generation** | all member-wise attendance | full `_attendanceLogs` in RAM `:3192-3203` | OOM on low-RAM device for big libraries | crash mid-export, no partial file | paginated/server export |

---

## 8. Offline Architecture Audit

| Dimension | Finding | Evidence | Risk |
|---|---|---|---|
| **Queue growth** | unbounded `offline_scan_queue`; grows with outage length × scan rate | `offline_db.dart:31-42` | OK short outages; large after long ones |
| **Sync complexity** | **strictly sequential** per-scan, 2-4 round-trips each (resolve lib, find membership, insert/update, delete) | `offline_sync.dart:52-179` | reconnect storm: N×(2-4) serial calls; slow drain at peak |
| **Conflict resolution** | string-match on error text `contains('duplicate')/('already')` → delete | `:182-184` | brittle; locale/driver-dependent; silent mis-handling |
| **Duplicate prevention** | relies on DB throwing + the string match; **no idempotency key**; no unique constraint cited (P5-06) | `:183`; schema lacks partial uniques | double check-ins possible (compounds P6-04) |
| **Failed-sync handling** | retry_count < 3 then **permanently deleted** | `:188-191` | **silent data loss** after 3 fails |
| **Invalid-scan handling** | no membership / bad lib code → **discarded** at sync time, success was already shown offline | `:77,94,176` | **connects P3-03**: offline "success" was a lie; the scan vanishes |
| **Data-loss risk** | orphaned checkout discarded `:176`; permanent delete `:190` | — | attendance gaps; no user notice |

**Conclusion:** offline is **functional for brief, low-volume outages** but is a **reliability liability at peak** and **silently loses data** on sustained failure — and it operationalizes the P3-03 correctness bug (false success offline → silent discard online).

---

## 9. Special-Focus Cross-Phase Connections (correctness vs performance vs both)

| Prior finding | Performance effect (Phase 11) | Classification |
|---|---|---|
| **P3-03** offline check-in false success | invalid scans accumulate, then sequential sync discards them silently; reconnect-storm cost | **BOTH** (correctness + reliability/perf) |
| **P5-03** missing analytics tables | forces full attendance scans on every analytics open (P11-01/N+1) | **BOTH** (the schema gap *is* the perf gap) |
| **P6-01** client-trusted/no server tier | no `count`, no aggregate, no precompute, no job → all work on device, per open | **BOTH** (root cause of perf *and* security) |
| **P8-02** fallback scans | dead fast-path means scan path always runs; also re-throws PostgREST error each call | **BOTH** (latency + the wrong numbers) |
| **P8-04 / P8-05** duration inconsistency | admin bills open sessions to `now` → forces recompute over all rows; member zeroes them | **mostly correctness**, minor perf (recompute) |

---

## 10. Scalability Risk Register (per subsystem)

| Subsystem | Current capacity (est.) | Expected bottleneck | Scaling limit | Redesign threshold |
|---|---|---|---|---|
| **Postgres / data layer** | 100k+ members, 1,000+ libraries (rows) | connection pool at peak; no read replicas | tier-dependent; pooler handles 1000s | add replicas/pooling at ~5k libs |
| **Admin dashboard** | ~2,000 members/library | 8 sequential count-by-fetch | multi-second >2k | server `count`/RPC at ~1k |
| **Member analytics + badges** | ~1,500 members or ~1yr history/library | badge N+1 + full-history scans | unusable at large/old libraries | **precompute tables now** |
| **Admin analytics + export** | small/medium library, short range | deep-nested over-fetch, in-RAM CSV | OOM/jank at large branch month-end | server aggregates + export job |
| **Explore/search** | ~500-1,000 libraries | all-libs-to-device + Dart filter | painful at 5,000 | server search + pagination |
| **Offline sync** | short outages, <~100 queued | sequential drain; silent drop | reconnect storm at peak | batch + idempotency keys |
| **Realtime/notifications** | n/a (stub) | — | — | build a real notification fetch (P9-01) with pagination |

---

## 11. Capacity Estimate Matrix (the headline question)

> Assumes a managed Supabase tier (not free). "Libraries" stresses multi-tenancy + explore; "members" stresses per-library hot screens. The DB tolerates far more than the **client screens** do — the limit is the thick-client recompute, not Postgres.

| Target | DB feasible? | Client screens feasible? | Net verdict |
|---|---|---|---|
| **100 libraries** | ✅ easily | ✅ explore OK; analytics OK if branches small | ✅ **Yes** |
| **500 libraries** | ✅ | ⚠️ explore ships 500 libs/device; analytics OK only if each branch < ~1.5k members | ⚠️ **Conditional** (needs explore pagination) |
| **1,000 libraries** | ✅ (watch pool at peak) | ❌ explore + any large branch analytics degrade | ❌ **No** without server tier |
| **5,000 members (total)** | ✅ | ✅ if spread across many small libraries | ✅ **Yes** |
| **20,000 members (total)** | ✅ | ⚠️ any single branch >~2-3k members hits dashboard/analytics limits | ⚠️ **Conditional** |
| **100,000 members (total)** | ✅ at DB | ❌ large branches' analytics/dashboard unusable; explore/export strain | ❌ **No** without precompute + server aggregation |

**Single largest determinant:** *members-per-library* and *history depth*, **not** total counts. A platform of 100,000 members across 2,000 tiny libraries is fine; **one** library of 5,000 active members is not (its analytics, badges, dashboard, and export all break).

---

## 12. Performance Debt Register

| ID | Debt | Owning findings | Effort |
|---|---|---|---|
| PD-1 | No precompute tier (daily stats + streaks tables + fill job) | P11-01, P11-02, P5-03, P8-02 | Large |
| PD-2 | No server aggregation/`count`/RPC (everything in Dart) | P11-03, P11-09, P6-01 | Large |
| PD-3 | No pagination/limits on lists, history, explore, analytics | P11-04, P11-06 | Medium |
| PD-4 | Deep-nested embeds / `select('*')` over-fetch (×99) | P11-04, OF-1…7 | Medium |
| PD-5 | Sequential dashboard + sequential offline sync (no batching/parallelism) | P11-03, P11-07 | Medium |
| PD-6 | In-memory export (no streaming/server export) | P11-10 | Medium |
| PD-7 | God-file whole-screen rebuilds (672 setState; 5k-line screens) | P11-11, P1-05 | Large |
| PD-8 | Offline: no idempotency, silent 3-retry drop | P11-12, P3-03 | Medium |

---

## 13. Findings

### P11-01 — Analytics runs on dead precompute tables → every load is a full-history attendance scan 🔴 Critical
**Category:** Scalability / architecture · **Cross-phase: Data Accuracy + Trust + Reliability (BOTH)**
**Evidence:** `member_analytics_service.dart:78` (`member_daily_stats` — table absent, P5-03), `:340` (`streaks` — absent); both `try` blocks fall through (`:127,358`) to **full attendance scans** (`:134,362`) aggregated in Dart. `_calculateStatsForRange` is called **twice** per `fetchAnalyticsSummary` (`:246,266`).
**Impact:** O(member-history) work on every analytics open; scales linearly with tenure and library size; also the source of the wrong numbers in P8. The "fast path" is permanently dead code that *looks* optimized.
**Fix:** Create `member_daily_stats` + `streaks` with a trigger/cron to populate them; read them O(1). (Same fix closes P8-02.)

### P11-02 — Badge engine N+1 explosion: 6-month + 4-week loops trigger full + library-wide scans every open 🔴 Critical
**Category:** N+1 / scalability · **Cross-phase: Reliability + Trust (BOTH)**
**Evidence:** `syncAndFetchBadges` — `consistent` loops 6 months each calling `_calculateStatsForRange` (full scan + closures) `:622-643`; `top_of_week` loops 4 weeks each calling `fetchLeaderboardDetails` (**library-wide** attendance scan + `users` embed) `:649-672`; early/night badge full member scan `:604`.
**Impact:** ~15-20 queries and up to **4 whole-library attendance scans per member per analytics open**. On a 3,000-member library this is several hundred-K rows scanned to draw a few badge icons. Primary cause of analytics freeze at scale.
**Fix:** Compute badges server-side on attendance write (or a nightly job); never recompute on read; cap/lazy-load badges.

### P11-03 — Admin dashboard counts by downloading rows in 8+ sequential queries 🟠 High
**Category:** Over-fetch + sequential latency · **Cross-phase: Reliability (BOTH)**
**Evidence:** `admin_home.dart:490-596` — attendance `select('member_id')`, memberships ×5 `select('id')` then `.length`, payments summed in Dart, shifts, seats — all awaited **sequentially**; runs on every home open and on post-approval refresh `:667`.
**Impact:** Latency = Σ round-trips; payload grows with library size (~5k ids/counter at 5k members). Worst exactly at peak check-in when the dashboard refreshes.
**Fix:** `count: 'exact', head: true` (or an RPC returning all stats in one call); parallelize with `Future.wait`.

### P11-04 — Admin analytics deep-nested over-fetch + unbounded memberships, no pagination 🟠 High
**Category:** Over-fetch · **Cross-phase: Reliability**
**Evidence:** `admin_analytics_tab.dart:498` `attendance.select('*, member_id(*), memberships(*, seats(*), shifts(*)))`; `:493` `memberships.select('*, member_id(*), seats(*), shifts(*))` with **no date filter**; no `.limit` anywhere; member-wise aggregation in Dart `:2935-3200`.
**Impact:** Multi-MB nested payloads at month-end for a busy library; device-side aggregation jank/OOM.
**Fix:** Select only needed columns; bound memberships by status/date; server-side aggregates; paginate.

### P11-05 — Leaderboard & heatmap pull whole-library/whole-member ranges and rank/bucket in Dart 🟠 High
**Category:** Scalability · **Cross-phase: Trust (BOTH — also P8 metrics)**
**Evidence:** `member_analytics_service.dart:289-333` and `:714-799` (library-wide scan + `users` embed per row, sort in Dart, **no limit**); heatmap `:962-1029` full member range scan.
**Impact:** Downloads and processes the entire library's sessions for a range; ×4 inside the badge loop (P11-02).
**Fix:** Server-side `GROUP BY member_id` top-N RPC; precomputed daily buckets for heatmap.

### P11-06 — No pagination anywhere; Explore ships every active library to every device 🟠 High
**Category:** Over-fetch / scalability · **Cross-phase: Reliability**
**Evidence:** `member_explore_screen.dart:62-68` fetches **all** `status='active'` libraries (+shifts embed); filtered/sorted entirely in Dart `:138-188`; history/roster/layout tabs also unbounded (`member_history_tab.dart:149`, `layout_sub_tab.dart:186`).
**Impact:** Grows with the **global** libraries table, not user need; sluggish at ~1,000 libraries, painful at 5,000; wasted bandwidth on every open.
**Fix:** Server-side search (city/geo bbox/text) + pagination + `limit`.

### P11-07 — Offline sync is strictly sequential with 2-4 round-trips per scan 🟠 High
**Category:** Scalability / reliability · **Cross-phase: Reliability + Accuracy (BOTH — P3-03)**
**Evidence:** `offline_sync.dart:52-179` — per scan: resolve library `:66`, find membership `:84`, insert/update, delete; one-at-a-time loop; success Snackbar after the drain.
**Impact:** A backlog of N scans = N×(2-4) serial network calls; slow drain and UI churn on reconnect at peak; invalid scans only detected here and silently discarded.
**Fix:** Batch insert; resolve library/membership once per (member,library); idempotency keys; parallelize with a bounded pool.

### P11-08 — Repeated/duplicate queries within a single analytics load (no shared fetch) 🟡 Medium
**Category:** Redundant queries
**Evidence:** `_getClosures` called by stats(×2), streak `:369`, heatmap `:979`; attendance re-scanned independently by stats, streak, leaderboard, heatmap, badges. No per-load cache.
**Impact:** The same closures/attendance fetched 4-6× per analytics open.
**Fix:** Fetch once per load; pass down; memoize closures.

### P11-09 — Pervasive client-side aggregation instead of SQL/RPC 🟡 Medium
**Category:** Architecture · **Cross-phase: Accuracy (BOTH — P8)**
**Evidence:** revenue sum `admin_home.dart:540-548`; occupancy `:598-626`; member-wise hours `admin_analytics_tab.dart:2935-3200`; streak/hours `member_home.dart:727-778`.
**Impact:** CPU/memory on device; large lists materialized; also where the P8 math errors live.
**Fix:** Move sums/counts/groupings to SQL aggregates / RPC.

### P11-10 — Export builds the full dataset in memory with no streaming or cap 🟡 Medium
**Category:** Memory / export
**Evidence:** `admin_analytics_tab.dart:3192-3203` (`StringBuffer` over all member rows → `writeAsString`); `fetchAttendanceForExport:1040` full nested fetch.
**Impact:** OOM/jank for large libraries; no partial output on failure.
**Fix:** Server-side/streamed export; paginate; cap rows with a warning.

### P11-11 — God-file whole-screen rebuilds (5k-line screens, 672 setState) 🟡 Medium · Links **P1-05**
**Category:** Frontend rendering
**Evidence:** `admin_analytics_tab.dart` (5,443 ln), `member_home.dart` (5,384 ln); 672 `setState` (Phase 1); custom painters for charts; no state-management/memoization.
**Impact:** Broad rebuilds on small state changes; jank with large lists/charts; compounds the data costs above.
**Fix:** Decompose; `const`; selective rebuilds / a state-management layer.

### P11-12 — Offline queue: silent data loss after 3 retries; no idempotency 🟡 Medium · Links **P3-03, P5-06**
**Category:** Reliability · **Cross-phase: Accuracy + Trust (BOTH)**
**Evidence:** `offline_sync.dart:188-191` permanent delete after 3 attempts; conflict handling by error-string match `:183`; no idempotency key; no DB unique guard (P5-06).
**Impact:** Sustained outage → lost attendance with no user notice; possible double check-ins.
**Fix:** Idempotency keys + DB partial-unique; dead-letter instead of delete; notify on drop.

### P11-13 — Hard `as int` casts + full-object caching inflate memory/fragility 🟢 Low · Links **P8-17**
**Category:** Memory / robustness
**Evidence:** `member_analytics_service.dart:301,730` `as int`; offline caches store full member/attendance objects (`offline_db.dart:51-93`).
**Impact:** A single bad value throws the whole leaderboard; cached full rows grow device DB.
**Fix:** `as num`; cache only needed columns.

### P11-14 — No use of server `count`/`head:true`; every count materializes rows 🟢 Low
**Category:** Query efficiency (overlaps P11-03)
**Evidence:** No `count:` / `head: true` found in `lib/**`; counts via `.length` over fetched lists.
**Impact:** Counts cost a full row transfer.
**Fix:** Use PostgREST exact/planned counts.

---

## 14. Improvement Suggestions (sequenced)
1. **Build the precompute tier (PD-1):** `member_daily_stats` + `streaks` tables, populated by a Postgres trigger/cron; read O(1). Fixes P11-01/02/05 *and* P8-02 accuracy.
2. **Add a server aggregation tier (PD-2):** RPC/Edge for dashboard stats, leaderboard top-N, revenue sums, badges-on-write. Fixes P11-03/09 *and* the P10 trust model.
3. **Paginate & bound everything (PD-3/4):** `limit`/`range`, server search for explore, explicit column lists, drop deep embeds.
4. **Parallelize & batch (PD-5):** `Future.wait` the dashboard; batch + idempotent offline sync.
5. **Server/streamed export (PD-6).**
6. **Decompose god-files (PD-7)** with selective rebuilds.
7. **Add `EXPLAIN ANALYZE` + a load test (k6/Artillery)** to CI to lock capacity (feeds Phase 13).

## 15. Priority Fix List (Phase 11, ordered)
1. **P11-01 / P11-02** — Precompute daily stats + streaks + badges; kill the dead-fast-path scans and badge N+1. *(Highest scale leverage; also fixes accuracy.)*
2. **P11-03** — Server `count`/RPC for the admin dashboard; parallelize.
3. **P11-04 / P11-05** — Bound + server-aggregate analytics/leaderboard/heatmap; drop deep embeds.
4. **P11-06** — Server search + pagination for explore (and lists).
5. **P11-07 / P11-12** — Batch, idempotent, non-lossy offline sync.
6. **P11-10 / P11-11** — Streamed export; decompose god-files.
7. **P11-08 / P11-09 / P11-13 / P11-14** — Dedupe per-load fetches; SQL aggregates; cast/count hygiene.

---

## 16. Feature Checklist (Phase 11 scope — performance/scale)
| Q | Verdict |
|---|---|
| Responsive at small scale | Yes (pilot/one small branch). |
| Responsive at medium scale | Marginal — analytics/dashboard lag at ~1-2k members/library. |
| Responsive at large scale | **No** — analytics/badges/dashboard/export degrade or freeze. |
| DB schema scalable | Mostly — good indexes; missing precompute tables + partial-uniques. |
| Pagination/limits | **No** — largely absent. |
| Server aggregation | **None** — all in Dart. |
| Offline robust at scale | **No** — sequential, silent data loss. |
| Production-ready (scale) | **Pilot only.** |

---

## 17. Operational Readiness Assessment — the answer

- **50 libraries?** ✅ **Yes** (small/medium branches) — this is the safe pilot envelope.
- **500 libraries?** ⚠️ **Conditional** — DB is fine, but Explore shipping all libraries to every device (P11-06) and any branch over ~1.5k members (P11-01/02/03) must be fixed first.
- **5,000 libraries?** ❌ **No** — not without the server aggregation + precompute tier and paginated explore; the thick-client recompute model does not hold.

- **5,000 members?** ✅ **Yes** if spread across many small libraries.
- **20,000 members?** ⚠️ **Conditional** — any single branch above ~2-3k active members hits the dashboard/analytics walls.
- **100,000 members?** ❌ **No** at the client tier — DB copes; large branches' analytics, badges, dashboard, and export do not.

**Where it fails first:** **member/admin analytics on the largest, oldest library** (badge N+1 + dead-fast-path full scans), then the **admin dashboard** (sequential count-by-fetch), then **Explore** (all-libraries-to-device), then **offline-sync reconnect storms** at peak check-in.

**Bottom line:** SILENCE is **pilot-ready, not scale-ready.** The blocker is architectural and already named since Phase 1/6/10: **no server-side aggregation or precompute tier.** Building it (PD-1 + PD-2) is the one change that simultaneously fixes performance (Phase 11), accuracy (Phase 8), and the trust/security model (Phase 10). Until then, capacity is bounded by *members-per-library*, and the honest operating limit is **a few dozen small-to-medium libraries.**

---

**Limitations honored:** No live project/profiler/load test — row-count → latency is modelled from query shapes and the index plan, to be confirmed with `EXPLAIN ANALYZE` and a load test (Verification Pending V-41…V-44). Findings that are also correctness/trust issues are cross-referenced to Phases 3/5/6/8/10, not re-litigated. No code was modified.

**Next:** `Start Phase 12` — Error Handling Audit.
