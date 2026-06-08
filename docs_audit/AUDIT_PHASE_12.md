# SILENCE — Phase 12: Error Handling & Resilience Audit

**Phase:** 12 of 16 — Error Handling Audit
**Completed (local time):** 2026-06-08
**Auditor roles:** Senior Full-Stack Engineer (lead) · SRE/Resilience · QA Lead · UX Designer · Support/CX Analyst
**Goal:** Verify how SILENCE behaves when things go wrong — network loss, session/auth expiry, payment failure, upload failure, offline-sync conflicts, missing tables, and null/empty data — and whether failures are **recovered, surfaced honestly, or silently swallowed.**
**Method:** Census of all 339 `try` / 344 `catch` sites, the 48 empty `catch(_){}` blocks, the 164 swallow-and-log catches, 107 silent-default returns, null-assertions, `mounted` discipline, and global error setup; per-flow failure-mode tracing. Behavior **Code-Inferred** (no emulator/fault injection) — declared limitation: actual on-device recovery (session-expiry redirect, ANR on jank) needs a device test (V-45…V-47).
**Constraint honored:** No code modified. Audit only.

**Cross-phase rule applied:** each finding is classified for impact on **Data Accuracy · User Trust · Security · Business Integrity · Operational Reliability/Observability.**

---

## 1. Executive Summary — Does it fail safely?

**It fails *quietly*, which is worse than failing loudly.** SILENCE is not careless about errors in the abstract — there are **339 try/catch blocks** and **473 `mounted` guards**, and the two most safety-critical flows are genuinely well-handled: **`auth_screen.dart`** uses typed `AuthException`/`PostgrestException` catches with specific, friendly messages and duplicate-email handling (`:145-225`), and **`qr_scanner_screen.dart`** distinguishes network vs logic failures, caps the offline queue at 500, and routes everything through a structured `_handleFailure` (`:122-269`). The team clearly *can* do resilient error handling.

The problem is that this discipline **is not applied consistently**, and three systemic gaps turn ordinary failures into invisible ones:

1. **No global safety net (P12-01).** `main.dart` has **no `FlutterError.onError`, no `runZonedGuarded`, no `ErrorWidget.builder`, and no crash reporting** (Sentry/Crashlytics absent) — only a `try/catch` around DB init (`main.dart:63-67`). Worse, there is **no `onAuthStateChange` listener anywhere in `lib/`**: when a session expires or a token refresh fails, nothing redirects to login or recovers — the user is left with a half-dead app and RLS-denied writes that fail silently (P6-05).

2. **Silent-failure is the default idiom (P12-02).** **164 catch blocks only `debugPrint` and continue**, and **48 are completely empty `catch(_){}`**; **107 error paths return `[]`/`null`/`{}`/`false`**. Because `debugPrint` is **stripped in release builds**, in production these are **100% invisible** — a failed write, a denied query, a swallowed exception all look identical to "no data" or "success." This is the engine behind the "beautiful-lie" UX of Phase 9 and the silent denials of Phase 6.

3. **No resilience for the network the app actually runs on (P12-04).** There is **no typing of `SocketException`/`TimeoutException`/`ClientException`** and **no retry/backoff** for normal reads/writes (only the offline *scan queue* retries). For Tier-2/3 users on flaky networks, a transient blip becomes a raw error string or a silent empty screen.

**Distribution:** 0 Critical · 4 High · 5 Medium · 2 Low (P12-01 … P12-11). No *new* Criticals — the catastrophic failures already live in Phases 6/10/11; Phase 12's contribution is showing that the app's error-handling **hides** them rather than catching them.

**Resilience posture: 4 / 10.** Two critical flows are solid; the surrounding system swallows, logs-to-nowhere, or leaks raw errors, and has no global recovery or observability. **A user whose session expires, whose write is denied by RLS, or whose network drops mid-action will, in the release build, most often see nothing at all — or a celebratory success for something that didn't happen.**

---

## 2. What Was Reviewed
All `try/catch` sites across `lib/**` (services + screens); empty/swallowing catches; silent-default returns; `currentUser!` force-unwraps; `mounted` usage vs `setState`; global error/zone setup in `main.dart`; typed-exception usage; the payment-failure path; offline-sync conflict handling; missing-table soft-fail handling.

## 3. Census (the numbers behind the findings)
| Pattern | Count | Meaning |
|---|---|---|
| `try` blocks | 339 | error handling is attempted widely |
| `catch` clauses | 344 | … |
| `rethrow` | 5 | errors almost never propagate up |
| empty `catch(_){}` | 48 | total swallow |
| catch that only `debugPrint` | 164 | swallow + log (invisible in release) |
| silent-default returns (`[]`/`null`/`{}`/`false`) in catch | 107 | failure looks like "no data" |
| `print()` | 22 | leftover console logging |
| `debugPrint()` | 296 | stripped in release → no prod logs |
| `currentUser!` force-unwrap | 3 | null-deref risk on lost session |
| `setState(` calls | 667 | … |
| `if (mounted)` guards | 473 | ~194 setState lack an adjacent guard |
| global error handler | **0** | no `FlutterError.onError`/zone/crash-reporting |
| `onAuthStateChange` listener | **0** | no session-expiry recovery |
| `SocketException`/`Timeout`/`ClientException` typing | **0** | no network-error resilience |

---

## 4. What's Done Well (credit where due)
- **`auth_screen.dart:145-225`** — typed `AuthException` + `PostgrestException` catches, duplicate-email (`23505`) handling, friendly fallback messages, `mounted` checks, deliberate `rethrow`. **This is the reference standard the rest of the app should match.**
- **`qr_scanner_screen.dart:122-269`** — structured `_handleFailure(title, message)`, explicit `Network Error` vs `Scan Failed` branches (`:184-186`), `Authentication Error` when no session (`:213`), and an offline-queue **500-item cap with a user-facing "Storage Full"** message (`:228`).
- **473 `mounted` guards** and `finally { if (mounted) setState(...) }` patterns show awareness of async-gap hazards.
- **`draft_service.dart:14-43`** — a deliberate `_isTableMissing` helper that soft-handles absent tables (good *intent*, though it also masks deploy errors — see P12-09).

> The audit's concern is **consistency and visibility**, not absence of effort.

---

## 5. Findings

### P12-01 — No global error handler and no session-expiry recovery 🟠 High
**Category:** Resilience / observability · **Cross-phase: Reliability + Trust + Security**
**Evidence:** `main.dart:63-70` — only a `try/catch` around DB init, then `runApp`; **no `FlutterError.onError`, `runZonedGuarded`, `ErrorWidget.builder`, or crash reporter.** Grep for `onAuthStateChange`/`authStateChanges`/`AuthChangeEvent` across `lib/**` = **0 matches**.
**Root cause:** App bootstrap never installs a global safety net or an auth-state subscription.
**Impact:** (a) Any uncaught exception shows the raw Flutter red screen (debug) or a frozen UI (release) with no report sent — **zero production observability.** (b) When the Supabase session expires or a refresh fails, nothing redirects to `/auth`; subsequent RLS-scoped calls fail (often silently, P6-05), so the app appears "dead" until force-relaunch. (c) `currentUser` becomes null while screens still assume a user (see P12-03).
**Fix:** Wrap `runApp` in `runZonedGuarded` + set `FlutterError.onError`; integrate Sentry/Crashlytics; subscribe to `supabase.auth.onAuthStateChange` at the app root and route to login on `signedOut`/expiry.

### P12-02 — Silent failure is the default: 164 swallow-and-log + 48 empty catches + 107 silent defaults 🟠 High
**Category:** Silent failure / observability · **Cross-phase: Accuracy + Trust + Security (BOTH)**
**Evidence:** 48 `catch(_){}` (e.g. `member_analytics_service.dart:697` `_awardBadge`; `admin_home.dart:226,256`; `member_home.dart:152,1015,1562,…`); 164 catches whose only action is `debugPrint`; 107 `return []/null/{}/false` on error (e.g. `member_analytics_service.dart:46,572,681`; `admin_analytics_tab.dart:490`). `debugPrint` is compiled out in release.
**Root cause:** Defensive "never crash" coding without a user-facing or telemetry channel.
**Impact:** In production, a denied write (P6-05), a missing table (P5-03), a network drop, or a logic bug **all render as empty data or silent success.** This is the mechanism behind Phase 9's false-positive notifications, Phase 6's silent RLS denials, and Phase 8's "no data" masking. Users and admins cannot tell "nothing happened" from "it failed."
**Fix:** Replace empty/log-only catches with: a user-visible error state **and** a telemetry event; reserve silent-default returns for genuinely optional data, and log those to telemetry too.

### P12-03 — `currentUser!` force-unwrap on critical paths → null-deref crash on lost session 🟠 High
**Category:** Null safety · **Cross-phase: Reliability + Business**
**Evidence:** `join_flow_screen.dart:392` (`payment_proofs/${supabase.auth.currentUser!.id}/…` — **mid payment-proof upload**), `admin_home.dart:979` (trial activation update), `member_history_tab.dart:1849` (profile fetch). If the session expired during the async gap (no recovery — P12-01), `currentUser` is null and `!` throws.
**Root cause:** Assuming a non-null session at await points with no guard.
**Impact:** Hard exception on a money/identity path (join payment proof) → upload aborts; with no global handler (P12-01) it surfaces raw or crashes.
**Fix:** Null-check `currentUser` and route to login; never `!`-unwrap auth state after an await.

### P12-04 — No network-error typing or retry/backoff for normal requests 🟠 High
**Category:** Network resilience · **Cross-phase: Reliability + Trust**
**Evidence:** 0 matches for `SocketException`/`TimeoutException`/`ClientException` in `lib/**`; connectivity is used only to trigger the offline *scan* sync (`offline_sync.dart:18`, `qr_scanner_screen.dart:71`). All other reads/writes rely on generic `catch` → raw `$e` or swallow.
**Root cause:** Transient network failure isn't modeled as a distinct, retryable condition for general data calls.
**Impact:** On Tier-2/3 flaky networks a blip becomes a raw error string or a blank screen with no "retry"; no exponential backoff; no offline UX outside the QR flow (cross-ref P3 member_home offline gap).
**Fix:** Detect transient network errors; show a retry affordance; add bounded retry/backoff for idempotent reads; broaden offline-aware UI.

### P12-05 — Payment cannot fail, and its persistence failure is swallowed 🟡 Medium · Links **P9-02**
**Category:** Failure-path absence · **Cross-phase: Trust + Business**
**Evidence:** `subscription_screen.dart:277` `Future.delayed(2000ms)` always resolves; the subsequent DB write is wrapped in `catch(_){}` (`:286-292`), after which the UI shows "Plan upgraded… successfully ✓" regardless. UPI join "payment" is a screenshot upload with no pay-time failure either (Phase 9 P9-04).
**Root cause:** Mocked payment (P0-01) with no real failure branch, and the persistence error is silently absorbed.
**Impact:** Even when the `subscription_status` write **fails**, the user is told they succeeded → divergent client/server state, disputes (compounds P9-02). There is literally no failure UX to exercise.
**Fix:** Real processor with explicit failure states; never swallow the activation write; reconcile UI to server truth.

### P12-06 — ~194 `setState` calls without an adjacent `mounted` guard 🟡 Medium
**Category:** Async-gap safety
**Evidence:** 667 `setState` vs 473 `mounted` guards; many `setState` follow `await` in `initState`/handlers (e.g. across `member_home.dart`, `admin_home.dart`, analytics tabs). Not all are post-await, but the gap is large.
**Root cause:** Inconsistent guarding after async returns.
**Impact:** "setState() called after dispose()" exceptions on fast navigation / slow networks → with no global handler (P12-01) these can surface raw or spam logs; minor data-integrity risk but real UX jank/crashes.
**Fix:** Lint rule (`use_build_context_synchronously`); guard every post-await `setState`.

### P12-07 — Raw exception strings surfaced to users 🟡 Medium · Links **P9-22, P10-23**
**Category:** Error-message quality · **Cross-phase: Security (info leak) + Trust**
**Evidence:** `join_flow_screen.dart:594`, `renewal_screen.dart:165`, `library_query_screen.dart:99`, `addon_services.dart:136,178`, `add_member_step1.dart:547`, `qr_scanner_screen.dart:186,269` (`…: ${e.toString()}`).
**Impact:** PostgREST/Supabase internals (table/column/policy hints) leak to end users; confusing for non-technical Tier-2/3 audience; aids the attacks in Phase 10.
**Fix:** Friendly messages; log `$e` to telemetry only.

### P12-08 — Offline-sync conflict handling is string-matched and lossy 🟡 Medium · Links **P11-12, P3-03**
**Category:** Conflict resolution / data loss · **Cross-phase: Accuracy + Reliability (BOTH)**
**Evidence:** `offline_sync.dart:182-184` resolves "conflicts" via `e.toString().contains('duplicate')||contains('already')` → delete; permanent delete after 3 retries (`:188-191`); invalid scans discarded silently (`:77,94,176`).
**Root cause:** No idempotency key / typed conflict detection; retry policy drops data.
**Impact:** Locale/driver-dependent matching; sustained outage → **silently lost attendance** with no user notice; operationalizes the P3-03 false-success bug.
**Fix:** Idempotency keys + DB partial-unique (P5-06); typed conflict detection; dead-letter queue + user notification instead of delete.

### P12-09 — Missing-table errors caught as soft "no data" hide deploy/config failures 🟡 Medium · Links **P5-03, P8-02**
**Category:** Failure masquerade · **Cross-phase: Accuracy + Reliability**
**Evidence:** `draft_service.dart:14-43` `_isTableMissing` swallows table-absent errors; analytics fallbacks treat absent `member_daily_stats`/`streaks` as "fall through" (`member_analytics_service.dart:127,358`).
**Root cause:** Defensive handling of expected-missing tables, applied so broadly that a genuine misconfiguration is indistinguishable from "empty."
**Impact:** If a migration fails to deploy a table in production, the app shows empty/wrong data with **no error** — the exact failure mode that let `member_daily_stats`/`streaks` ship absent for the whole product life.
**Fix:** Distinguish "expected-optional" from "required-missing"; alert/telemetry on required-table absence; fail loudly in non-prod.

### P12-10 — No telemetry/crash reporting; 296 `debugPrint` is the only diagnostic 🟢 Low · Links **P12-01**
**Category:** Observability
**Evidence:** 296 `debugPrint` + 22 `print`; no Sentry/Crashlytics/analytics SDK in `pubspec.yaml`/code.
**Impact:** Production failures are unknowable to the team; no MTTR; no error rates. (Foundational gap that makes P12-02's silent failures permanent.)
**Fix:** Add crash + error telemetry; route swallowed catches there.

### P12-11 — Inconsistent null/type guards (hard casts throw) 🟢 Low · Links **P8-17, P11-13**
**Category:** Null/type safety
**Evidence:** `member_analytics_service.dart:301,730` `as int` (throws on null/double); mixed `??` usage; some maps accessed without null checks.
**Impact:** A single unexpected value throws an entire list/screen (e.g. leaderboard) rather than degrading gracefully.
**Fix:** `as num?` + null-coalescing; defensive parsing at boundaries.

---

## 6. Silent-Failure Register (where failures vanish in release)

| # | Site | Failure swallowed | Looks like | Real consequence | Sev |
|---|---|---|---|---|---|
| SF-1 | `member_analytics_service.dart:697` `_awardBadge` `catch(_){}` | badge + notification insert fails | "no badge yet" | earned badge/notification lost (P9-17) | High |
| SF-2 | `subscription_screen.dart:286-292` `catch(_){}` | `subscription_status` write fails | "upgraded ✓" | client says paid, server didn't (P12-05/P9-02) | High |
| SF-3 | 107 `return []/null` on error | any query failure | "empty data" | denied/failed reads look empty (P6-05) | High |
| SF-4 | `member_home.dart:152,1015,1562,1655,1732,…` `catch(_){}` | home data loads fail | partial/blank cards | silent missing state | Med |
| SF-5 | `offline_sync.dart:176,190` discard/delete | invalid or 3×-failed scan | (offline said ✓) | **lost attendance** (P3-03/P12-08) | Med |
| SF-6 | `admin_home.dart:226,256` `catch(_){}` | cached dashboard load fails | stale/empty stats | admin acts on wrong/empty numbers | Med |
| SF-7 | missing-table soft-catch | required table absent in prod | "no data" | undetected deploy failure (P12-09) | Med |
| SF-8 | 164 debugPrint-only catches | everything above, in release | nothing | no signal at all | High (systemic) |

---

## 7. Error-Handling Gap List (per failure mode × flow)

| Failure mode | Auth/Signup | Join/Renewal pay | QR check-in | Analytics load | Offline sync | Admin dashboard |
|---|---|---|---|---|---|---|
| **Network loss** | typed-ish (generic msg) | raw `$e` (P12-07) | **handled** (`:184`) | swallow→empty (P12-02) | queue+retry | swallow→empty |
| **Session/auth expiry** | n/a | `currentUser!` crash (P12-03) | "Auth Error" (`:213`) | silent empties (P12-01/02) | n/a | `currentUser!` (`:979`) |
| **Payment failure** | n/a | **cannot fail** (P12-05) | n/a | n/a | n/a | n/a |
| **Upload failure** | n/a | raw `$e` (P12-07) | n/a | n/a | n/a | raw `$e` |
| **Write denied (RLS)** | handled (signup) | silent (SF-3, P6-05) | partial | silent | discard (SF-5) | silent |
| **Missing table** | n/a | n/a | n/a | soft→empty (P12-09) | n/a | n/a |
| **Null/empty data** | guarded | mixed | guarded | hard `as int` throws (P12-11) | guarded | mixed |
| **Verdict** | ✅ good | ⚠️ weak | ✅ good | ❌ silent | ⚠️ lossy | ⚠️ silent |

---

## 8. Resilience Recommendations (sequenced)
1. **Install the global safety net (P12-01/P12-10):** `runZonedGuarded` + `FlutterError.onError` + crash/error telemetry; subscribe to `onAuthStateChange` and route to login on expiry.
2. **Ban silent swallow (P12-02):** lint against empty `catch(_){}` and log-only catches; every catch either recovers, shows an error state, or emits telemetry.
3. **Network resilience (P12-04):** typed transient-error detection + retry/backoff + universal "retry" UI; offline-aware screens beyond QR.
4. **Kill null-deref on auth (P12-03):** guard `currentUser`; lint `!` on auth.
5. **Honest payment/write failures (P12-05):** never swallow activation writes; real failure UX.
6. **Idempotent, non-lossy offline sync (P12-08):** keys + DB uniques + dead-letter.
7. **Required-vs-optional table distinction (P12-09);** friendly errors (P12-07); `mounted` lint (P12-06); `as num?` (P12-11).
8. **Adopt the `auth_screen`/`qr_scanner` pattern as the house standard** and refactor outward.

## 9. Priority Fix List (Phase 12, ordered)
1. **P12-01** — Global error handler + session-expiry recovery + crash reporting.
2. **P12-02** — Eliminate silent swallow; add telemetry on every catch.
3. **P12-03 / P12-04** — Null-safe auth; network typing + retry.
4. **P12-05** — Real payment failure path; stop swallowing the activation write.
5. **P12-08 / P12-09** — Non-lossy offline sync; detect required-table absence.
6. **P12-06 / P12-07 / P12-10 / P12-11** — `mounted` lint, friendly errors, telemetry, type-safe parsing.

---

## 10. Feature Checklist (Phase 12 scope — error handling)
| Q | Verdict |
|---|---|
| Fails safely | Partially — auth/QR yes; most flows swallow. |
| User-visible recovery | Weak — silent or raw `$e`; no global session recovery. |
| Retries/rollback | Only offline scan queue (lossy); none elsewhere. |
| Observability | **None** — no telemetry; release logs stripped. |
| Null/empty safe | Mixed — guards present but hard casts throw. |
| Production-ready (resilience) | **No** — silent failure + no observability + no session recovery. |

---

**Limitations honored:** Recovery behaviors (session-expiry redirect, ANR, setState-after-dispose) are code-inferred and need on-device/fault-injection confirmation (Verification Pending V-45 global-handler behavior, V-46 session-expiry UX, V-47 release-build silent-failure repro). Catastrophic failures (data breach, billing bypass) are owned by Phases 6/10/11; Phase 12 documents how error handling **hides** rather than catches them. No code was modified.

**Next:** `Start Phase 13` — QA & Edge Cases Audit.
