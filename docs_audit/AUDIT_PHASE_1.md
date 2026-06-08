# SILENCE — Phase 1: Architecture Audit

**Phase:** 1 of 16 — Architecture Audit
**Completed (local time):** 2026-06-08
**Auditor roles applied:** Senior Full-Stack Engineer (lead) · Security Auditor · QA Lead · PM
**Scope:** Deep architectural review — not a folder listing. Every claim carries `file:line` + excerpt.
**Constraint honored:** No application code modified. Audit only.

---

## 1. Executive Summary

SILENCE is a **single-tier "fat client" architecture**: a Flutter app talking **directly** to Supabase Postgres/Auth/Storage with **no intermediate server, no service layer, no repository layer, and no state-management framework**. All domain logic, validation, calculations, and orchestration live **inside StatefulWidget screens** (66 stateful screens, only 9 stateless; 672 `setState` calls; no Provider/Bloc/Riverpod). Data access is `Supabase.instance.client` re-instantiated as a field in **116 screen locations** (127 total references).

This architecture is internally consistent and was clearly optimized for **build speed of a prototype**, but it has **three release-blocking infrastructure defects** discovered this phase that are independent of feature logic:

- **C-1 (Critical):** The **release** Android manifest is missing the `INTERNET` permission (it exists only in `debug`/`profile` manifests). A release APK cannot reach Supabase at all — the app is non-functional when shipped.
- **C-2 (Critical):** The release build is **signed with debug keys** (`build.gradle.kts:37`, with a `TODO`). It cannot be uploaded to Play Store and has no release integrity.
- **C-3 (High→Critical at scale):** **No server-side tier** means every business rule, money calculation, and authorization decision is enforced (or not) on the client; integrity rests entirely on RLS, which itself is unverified against the live DB (carried from Phase 0).

Beyond these, the architecture exhibits the classic risks of layerless client apps: **god files** (4 screens > 4,000 LOC, top is 5,443), **logic-in-UI coupling** (33 screens perform date/money math inline), **no DI**, **no offline DB migration path** (`version: 1`, no `onUpgrade`), and **fragmented configuration/secrets**. There is **no CI/CD** of any kind.

**Phase 1 verdict:** The architecture is a **functional prototype, not a production architecture**. It will not survive (a) a real release build, (b) schema evolution, or (c) team scale-up without significant structural work. Target architecture is defined in §11.

---

## 2. What Was Reviewed

- **Bootstrap & composition root:** `lib/main.dart`, `lib/screens/splash_screen.dart`.
- **Core layer:** `lib/core/` — `supabase_config.dart`, `offline_db.dart`, `offline_sync.dart`, `cache_service.dart`, `admin_settings_service.dart`, `member_analytics_service.dart`, `image_optimizer.dart`, `calendar_picker.dart`.
- **Only service/model abstraction:** `lib/services/draft_service.dart`, `lib/models/`.
- **Auth/authz flow:** `splash_screen.dart`, `auth_screen.dart`, `role_selection_screen.dart`.
- **State/nav patterns:** repo-wide greps (state libs, `setState`, `ValueNotifier`, routes, realtime channels).
- **Build/release/config:** `pubspec.yaml`, `android/app/build.gradle.kts`, `android/app/src/{main,debug,profile}/AndroidManifest.xml`, `ios/Runner/Info.plist`, `.gitignore`, env search.
- **CI/CD:** `.github/`, repo-wide CI config search.

---

## 3. Files Reviewed

`main.dart`, `splash_screen.dart`, `auth_screen.dart`, `role_selection_screen.dart`, `core/supabase_config.dart`, `core/offline_db.dart`, `core/offline_sync.dart`, `core/cache_service.dart`, `core/admin_settings_service.dart`, `services/draft_service.dart`, `android/app/build.gradle.kts`, 3× `AndroidManifest.xml`, `ios/Runner/Info.plist`, `.gitignore`, `pubspec.yaml`, `test/widget_test.dart` — plus aggregate greps across all 88 `lib/**/*.dart`.

## 4. Screens Reviewed
Architectural sampling only (full behavioral review is Phases 3–4/9): `admin_home.dart`, `member_home.dart`, `admin_analytics_tab.dart`, `reservations/layout_sub_tab.dart` (for god-file/coupling/realtime patterns), `member_analytics_tab.dart` (realtime).

---

## 5. Findings

> Per new rule: every Critical/High is mirrored into **Cross-Phase Critical Findings** (§12) and the master report. Effort estimates: Small (<1 day) · Medium (1–5 days) · Large (>5 days / multi-sprint).

### P1-01 — Release Android manifest missing `INTERNET` permission
- **Severity:** **Critical**
- **Category:** Build/Release · Configuration
- **File/Lines:** `android/app/src/main/AndroidManifest.xml` (grep `INTERNET` → 0 matches); present only in `android/app/src/debug/AndroidManifest.xml` and `android/app/src/profile/AndroidManifest.xml`.
- **Excerpt:** main manifest declares `CAMERA`, `READ_MEDIA_IMAGES`, `READ/WRITE_EXTERNAL_STORAGE` — but **no `android.permission.INTERNET`**.
- **Why it's a problem:** Flutter's debug/profile templates auto-inject `INTERNET`, so it works in `flutter run`. In a **release** build, only the main manifest applies → no network permission.
- **How it fails in production:** Every Supabase call (auth, data, storage) throws a socket/permission error on a shipped release build. The app is effectively **dead on arrival** for real users while appearing fine in development.
- **Fix:** Add `<uses-permission android:name="android.permission.INTERNET"/>` to `src/main/AndroidManifest.xml`. Also add `ACCESS_NETWORK_STATE` (used by `connectivity_plus`).
- **Effort:** **Small**

### P1-02 — Release build signed with debug keys
- **Severity:** **Critical**
- **Category:** Build/Release · Security
- **File/Lines:** `android/app/build.gradle.kts:34-38`
- **Excerpt:**
  ```kotlin
  buildTypes {
      release {
          // TODO: Add your own signing config for the release build.
          // Signing with the debug keys for now, so `flutter run --release` works.
          signingConfig = signingConfigs.getByName("debug")
      }
  }
  ```
- **Why it's a problem:** Debug keys are public/shared; Play Store rejects debug-signed AABs; no app-integrity guarantee; updates can't be authenticated.
- **How it fails in production:** Cannot publish; if side-loaded, any party can sign a malicious update with the same well-known debug key.
- **Fix:** Create an upload keystore, wire `signingConfigs.release` from a non-committed `key.properties`, set `minifyEnabled`/`shrinkResources` consciously.
- **Effort:** **Small**

### P1-03 — No server-side tier: all logic/authorization on the client
- **Severity:** **High** (Critical at scale / for money & seat integrity)
- **Category:** Architecture · Data Integrity · Security
- **Evidence:** `0` `.rpc(`/`functions.invoke` in `lib/` (Phase 0, re-confirmed). Writes are direct: `offline_sync.dart` inserts into `attendance`; `draft_service.dart` writes `draft_members`; 116 screen fields hold `Supabase.instance.client`. Business math is inline in 33 screens.
- **Why it's a problem:** There is no trusted boundary. A modified client (or crafted REST call with the shipped anon key) can write anything RLS doesn't explicitly forbid. Multi-step invariants (seat uniqueness per shift, payment→membership atomicity, discount caps) cannot be enforced transactionally from a client.
- **How it fails in production:** Race conditions assign one seat to two members; a tampered client marks unpaid memberships active; discount/hold caps bypassed (to be quantified in Phase 7).
- **Fix:** Introduce Postgres RPCs / Edge Functions for *transactional* operations (check-in, approve, renew, hold, transfer, payment-confirm) and tighten RLS to deny direct writes to those tables. Keep simple reads client-direct.
- **Effort:** **Large**

### P1-04 — No state-management or DI architecture (logic-in-widget)
- **Severity:** High
- **Category:** Maintainability · Separation of Concerns
- **Evidence:** No `provider/riverpod/bloc/get_it` in `pubspec.yaml`. 66 StatefulWidgets vs 9 StatelessWidgets; **672 `setState` calls**; ad-hoc `ValueNotifier`s (e.g., `member_home.dart:69-71`). Each screen owns its data fetching, caching, business logic, and rendering.
- **Why it's a problem:** No separation of concerns; logic is untestable without the widget tree (hence only 1 widget test). Shared state (current library, user profile) is re-fetched per screen rather than held centrally.
- **How it fails in production:** Inconsistent state across tabs; duplicated/divergent business rules; high regression risk on every change; onboarding new engineers is slow.
- **Fix:** Adopt a layered approach: Repository (data) → Controller/Notifier (state, e.g. Riverpod) → View. Migrate incrementally, highest-churn screens first.
- **Effort:** **Large**

### P1-05 — God files: 4 screens exceed 4,000 LOC
- **Severity:** High
- **Category:** Maintainability · Technical Debt
- **Evidence:** `admin_analytics_tab.dart` 5,443 · `member_home.dart` 5,384 · `admin_home.dart` 4,832 · `layout_sub_tab.dart` 4,014. These mix UI, data access (up to 69 Supabase calls in one file — `layout_sub_tab.dart`), realtime subscriptions, and math.
- **Why it's a problem:** Exceeds reviewable/comprehensible size; merge-conflict magnets; impossible to unit test; high cognitive load.
- **How it fails in production:** Defects hide in 5k-line files; "fix one thing, break another"; analytics/dashboard correctness (Phase 8) is hard to verify.
- **Fix:** Extract widgets, data sources, and view-models; target < 400 LOC per file.
- **Effort:** **Large**

### P1-06 — Offline DB has no migration strategy
- **Severity:** High
- **Category:** Offline Architecture · Data Loss Risk
- **File/Lines:** `core/offline_db.dart:22-25` → `version: 1, onCreate: _createDB` with **no `onUpgrade`**.
- **Why it's a problem:** Any future change to the 6 local tables (queue + caches) has no upgrade path. `openDatabase` won't re-run `onCreate` on an existing DB.
- **How it fails in production:** Shipping a schema change either crashes on missing columns or silently runs against the old schema; the only "fix" becomes app reinstall (data loss of the offline scan queue → lost attendance).
- **Fix:** Add `onUpgrade` with incremental migrations and bump `version`; add a guarded `ALTER`/recreate strategy for caches (safe to drop) vs queue (must preserve).
- **Effort:** Medium

### P1-07 — Hardcoded, unmanaged configuration & secrets
- **Severity:** High
- **Category:** Configuration · Environment · Security
- **File/Lines:** `core/supabase_config.dart:5-7` (literal `url` + `anonKey`); no `.env`, no `String.fromEnvironment`/`--dart-define` anywhere in `lib/`; project dashboard URLs leaked in `*.sql` files.
- **Why it's a problem:** One hardcoded environment → no separation of dev/staging/prod; key rotation requires a code change + rebuild; secrets live in VCS history.
- **How it fails in production:** Cannot run a staging environment; a leaked/abused key can't be rotated quickly; tests and prod hit the same DB.
- **Fix:** `--dart-define-from-file` per environment; `SupabaseConfig` reads from `String.fromEnvironment`; remove literals from VCS; document rotation.
- **Effort:** Medium

### P1-08 — No CI/CD; effectively no automated quality gate
- **Severity:** Medium
- **Category:** Build/Release · Process
- **Evidence:** No `.github/workflows`, no fastlane/codemagic/gitlab CI. Single test `test/widget_test.dart` (a smoke test). Analyzer is run manually (committed `analyze_*.txt` logs).
- **Why it's a problem:** No gate on analyzer errors, tests, formatting, or builds; regressions ship freely.
- **How it fails in production:** The very `INTERNET`/signing defects above would have been caught by a release-build CI job.
- **Fix:** Add CI (analyze + test + `flutter build apk --release` smoke) on PR; later add lane for store builds.
- **Effort:** Medium

### P1-09 — Admin onboarding gate collapsed in router logic
- **Severity:** Medium (architectural — full behavioral check in Phase 4)
- **Category:** Navigation Architecture · Separation of Concerns
- **File/Lines:** `splash_screen.dart:74-87` — both `hasLibrary` and `!hasLibrary` branches `pushReplacementNamed('/admin/home')` (identical), with a comment claiming a "Setup Mode" that the router does not enforce.
- **Excerpt:**
  ```dart
  if (!hasLibrary) {
    Navigator.of(context).pushReplacementNamed('/admin/home'); // "Setup Mode"
  } else {
    Navigator.of(context).pushReplacementNamed('/admin/home'); // Operational
  }
  ```
- **Why it's a problem:** PRD §2.1 mandates Stage-1 setup as a blocking modal to "prevent null-library crashes." The gate is now delegated entirely to `admin_home.dart` internal state, not the navigation layer — a fragile single point that, if mis-handled, risks the null-library crash the design tried to prevent.
- **How it fails in production:** If `admin_home` doesn't perfectly detect "no library," the dashboard renders against null library data → crash/empty-state.
- **Fix:** Either remove the dead branch or route new admins to a dedicated setup route; assert the invariant in one place. Verify `admin_home` guard in Phase 4.
- **Effort:** Small

### P1-10 — `connectivity_plus` network-state permission not declared for release
- **Severity:** Medium
- **Category:** Configuration · Offline Architecture
- **Evidence:** `offline_sync.dart` uses `Connectivity().onConnectivityChanged`; `splash_screen.dart` starts the listener; main manifest lacks `ACCESS_NETWORK_STATE`.
- **Why it's a problem:** On release, connectivity detection (which drives offline-scan sync) may misbehave without the permission, compounding P1-01.
- **How it fails in production:** Offline scans never sync (sync is triggered by connectivity-restored events) → silent attendance data loss.
- **Fix:** Add `ACCESS_NETWORK_STATE` to main manifest (bundled with P1-01).
- **Effort:** Small

### P1-11 — `geolocator` dependency: heavy permission surface, narrow use
- **Severity:** Low (flagged for Phase 14)
- **Category:** Dependency Structure · Store Readiness
- **Evidence:** `geolocator: ^11.0.2` used only in `member_explore_screen.dart`, `member_home.dart`; location permission **not** in Android main manifest. Location is a sensitive permission requiring store justification.
- **Why it's a problem:** Either location is used (then release manifest is missing the permission → runtime failure) or it's near-vestigial (then it's an unjustified store-review risk).
- **Fix:** Decide intent; if kept, declare permissions + Play Data-safety rationale (Phase 14); if not, remove the dependency.
- **Effort:** Small

### P1-12 — Raw `print()` in shipped code paths
- **Severity:** Low
- **Category:** Technical Debt · Security (info leak)
- **Evidence:** 22 `print(` vs 296 `debugPrint(`; e.g., `main.dart` prints DB-init status. `print` is not stripped in release like `debugPrint` partially is.
- **Why it's a problem:** Console noise in release; potential leakage of internal state to logcat.
- **Fix:** Replace `print` with a logger gated on `kDebugMode`.
- **Effort:** Small

---

## 6. Missing Connections (architectural)

- **Realtime is partial and inconsistent:** only 3 sites use Supabase Realtime (`admin_home.dart:655` join_requests, `member_analytics_tab.dart:165` attendance, `layout_sub_tab.dart:134` seats). The PRD's "live occupancy dashboard" is realtime in some places, manual-refresh in others — no unified realtime strategy.
- **`draft_service` is the *only* repository-style abstraction**; every other feature bypasses it and talks to Supabase inline → inconsistent caching/fallback behavior (drafts have offline fallback; nothing else does in a uniform way).
- **`AdminSettingsService` writes to a `settings` table** absent from `supabase_schema.sql` (Phase 0 drift R-05) — a core service depends on an undocumented table.
- **No central "session/app state"** holds current user/role/active-library; each screen re-derives it from `auth.currentUser` (95 references) → no single source of truth in the app layer.

## 7. Incomplete Features (architectural)

| Item | Signal | Owning Phase |
|---|---|---|
| Server-side tier (RPC/Edge) | 0 implementations | 6,7 |
| Release build config (signing, INTERNET) | debug keys + missing perm | 14 |
| Offline DB migrations | `version:1`, no `onUpgrade` | 12 |
| Environment/config separation | single hardcoded env | — |
| CI/CD | none | — |
| Unified realtime/state layer | 3 ad-hoc channels | 11 |

## 8. Security Issues (architectural seeds → Phase 10)

- Debug-signed release (P1-02) — integrity/authenticity.
- Hardcoded creds + single env (P1-07) — rotation/exposure.
- Client-trust model (P1-03) — no server validation boundary.
- `print()` info leakage (P1-12).
*(All carried to Phase 10 with exploitation detail; see also Phase 0 R-01 PII bucket.)*

## 9. Improvement Suggestions

1. **Fix release blockers first** (P1-01, P1-02) — Small effort, ship-stopping impact.
2. **Introduce a thin Repository layer** behind which the 116 inline clients hide; this enables testing and a future server tier without rewriting every screen.
3. **Add a session/app-state holder** (even a single Riverpod provider) for user/role/active-library.
4. **Stand up minimal CI** (analyze + test + release-build smoke) — would have caught P1-01/02.
5. **Establish migration discipline** for both Postgres (single source of truth) and the offline SQLite DB.

## 10. Priority Fix List (Phase 1)

| # | Item | Severity | Effort |
|---|---|---|---|
| 1 | Add `INTERNET` (+`ACCESS_NETWORK_STATE`) to main manifest (P1-01,10) | Critical | Small |
| 2 | Real release signing config (P1-02) | Critical | Small |
| 3 | Decide & begin server-side tier for transactional ops (P1-03) | High | Large |
| 4 | Offline DB `onUpgrade` migrations (P1-06) | High | Medium |
| 5 | Externalize config/secrets per environment (P1-07) | High | Medium |
| 6 | Introduce repository + state layer; split god files (P1-04,05) | High | Large |
| 7 | Stand up CI/CD (P1-08) | Medium | Medium |
| 8 | Fix collapsed onboarding gate (P1-09) | Medium | Small |

---

## 11. Required Architecture Outputs

### 11.1 Architecture Diagram (current — "as built")
```
┌───────────────────────────────────────────────────────────────┐
│                        FLUTTER CLIENT (single tier)            │
│                                                                │
│  main.dart  ── bootstraps Supabase + OfflineDB; static routes  │
│      │                                                         │
│  ┌───┴─────────────────────────── PRESENTATION = LOGIC ──────┐ │
│  │ 66 StatefulWidget screens (9 Stateless)                    │ │
│  │  • UI + business rules + date/money math + caching         │ │
│  │  • 672 setState; ad-hoc ValueNotifier; NO state framework  │ │
│  │  • 116 inline `Supabase.instance.client` fields            │ │
│  │  • 3 ad-hoc Realtime channels                              │ │
│  └───┬───────────────┬───────────────┬──────────────┬────────┘ │
│      │               │               │              │          │
│   core/ (thin)   services/        widgets/       utils/        │
│  offline_db      draft_service    seat grid,     csv/pdf,      │
│  offline_sync    (ONLY repo-like) qr modal       time_utils    │
│  cache_service   admin_settings_service                        │
│  member_analytics_service                                      │
│      │                                                         │
│  ┌───┴──────────── LOCAL (sqflite: silence_offline.db) ───────┐│
│  │ offline_scan_queue + 5 cache tables (version:1, no upgrade)││
│  └────────────────────────────────────────────────────────────┘│
└──────────────────────────────┬─────────────────────────────────┘
                               │  direct REST / Realtime / Storage / Auth
                               │  (anon key shipped in client; NO server tier)
                               ▼
┌───────────────────────────────────────────────────────────────┐
│                          SUPABASE (BaaS)                       │
│  Postgres (25 tables, RLS = only trust boundary) ·            │
│  Auth (email/pwd only) · Storage (silence_assets PUBLIC /      │
│  silence_private) · Realtime                                   │
│  ✗ No RPC/Edge Functions   ✗ No FCM   ✗ Payments (mocked)      │
└───────────────────────────────────────────────────────────────┘
```

### 11.2 Target Architecture (recommended)
```
Flutter (View) → Controller/Notifier (Riverpod) → Repository (interface)
     → SupabaseDataSource (reads + simple writes)
     → RPC/EdgeClient (transactional writes: check-in, approve, renew, hold,
                       transfer, payment-confirm)  ← server-validated
Offline: Repository decides cache vs network; versioned SQLite w/ onUpgrade
Config: --dart-define-from-file per env; no secrets in VCS
CI: analyze → test → release-build smoke → store lanes
Supabase: RLS DENIES direct writes to transactional tables; RPCs enforce invariants
```

### 11.3 Data Flow Diagram (representative paths)
```
WRITE — Member QR check-in (current):
 Camera → qr_scanner_screen → (online?) ──yes──► supabase.from('attendance').insert()
                                   └──no──► OfflineDatabase.offline_scan_queue
 Connectivity-restored event → OfflineSyncManager.syncPendingScans()
        → resolve library_code → find active membership → insert attendance
        → on duplicate: delete from queue (conflict = "newer/exists wins")
 ⚠ No server validation; client decides membership validity & dedup.

READ — Admin dashboard (current):
 admin_home initState → multiple direct .from(...) selects (memberships,
        attendance, payments, seats) → compute revenue/occupancy IN WIDGET
        → setState → render donut. Realtime channel on join_requests only.
 ⚠ Aggregations client-side (Phase 8 risk); partial realtime.

CONFIG/BOOT:
 main() → SupabaseConfig.initialize() [hardcoded url/key]
        → OfflineDatabase.database [version 1]
        → runApp → SplashScreen → auth.currentSession?
              → users.role → admin(library?)/member route
```

### 11.4 Dependency Map
```
External (pubspec) — runtime-critical:
  supabase_flutter ─► auth, postgREST, storage, realtime (the spine)
  sqflite + path ──► offline_db / caches
  connectivity_plus ─► sync trigger (needs ACCESS_NETWORK_STATE on release)
  shared_preferences ─► CacheService (JSON blobs), session prefs
External — feature:
  image_picker, image_cropper, image, permission_handler ─► uploads
  mobile_scanner, qr_flutter ─► QR in/out + asset gen
  pdf, printing, share_plus, url_launcher ─► exports/sharing
  geolocator ─► explore/home ONLY (perm not declared for release) [P1-11]
  google_fonts, font_awesome_flutter, cupertino_icons, cached_network_image ─► UI
  intl, uuid ─► formatting/ids
Notably ABSENT: razorpay_*, firebase_* , any state-mgmt/DI lib.

Internal coupling (imports from screens):
  → core/        : 36   (healthy: shared infra)
  → models/      :  9
  → widgets/     :  7
  → services/    :  3   (only draft_service)
  → other screens: 13   (screen→screen coupling; navigation/embedding)
Client instantiation: 116 screens each hold their own Supabase client field.
```

### 11.5 Layer Responsibility Matrix (as-built vs ideal)
| Concern | Where it lives NOW | Where it SHOULD live | Gap |
|---|---|---|---|
| Routing | `main.dart` static map | Router module | OK (acceptable) |
| Session/role/active-library | re-derived per screen (`auth.currentUser` ×95) | App-state provider | **Missing layer** |
| Business rules / lifecycle | inside screens (33 do date/money math) | Domain/server (RPC) | **Misplaced** |
| Data access | inline `.from()` ×116 | Repository + DataSource | **Missing layer** |
| Caching/offline | `core/offline_*`, `cache_service`, ad-hoc | Repository-coordinated | Partial |
| Validation/authorization | client + RLS only | Server (RPC) + RLS | **No server boundary** |
| Calculations (revenue/hours/streak) | in analytics widgets | Domain service / SQL views | **Misplaced** (Phase 8) |
| Config/secrets | hardcoded constant | env injection | **Missing** |
| Notifications | DB rows, client poll | FCM + server | **Missing** |
| Error handling | per-screen try/catch + print | centralized policy | Inconsistent (Phase 12) |

### 11.6 Architecture Risk Register (Phase 1)
| ARID | Risk | Trigger | Impact | Severity | Effort to fix |
|---|---|---|---|---|---|
| AR-01 | Release APK can't reach network (no INTERNET perm) | First real release build | App dead on arrival | Critical | Small |
| AR-02 | Debug-signed release | Play upload / update | Can't publish; integrity loss | Critical | Small |
| AR-03 | No server tier → client-trust integrity | Tampered client / race | Seat/payment/data corruption | High | Large |
| AR-04 | Logic-in-widget, no state layer | Any feature change | Regressions, untestable | High | Large |
| AR-05 | God files (5k LOC) | Maintenance/review | Hidden defects, conflicts | High | Large |
| AR-06 | Offline DB no `onUpgrade` | Any local-schema change | Crash / data loss | High | Medium |
| AR-07 | Single hardcoded env/secret | Rotation/staging need | Ops fragility, exposure | High | Medium |
| AR-08 | No CI/CD | Every merge | Defects ship unchecked | Medium | Medium |
| AR-09 | Partial/ad-hoc realtime | Live-dashboard expectations | Stale data UX | Medium | Medium |
| AR-10 | Collapsed onboarding gate | New admin w/o library | Null-library crash risk | Medium | Small |

### 11.7 Technical Debt Register (Phase 1)
| TDID | Debt | Location | Interest (cost of leaving) | Effort |
|---|---|---|---|---|
| TD-01 | 4 god files > 4k LOC | analytics/home/layout tabs | Compounds every edit | Large |
| TD-02 | 116 duplicated client fields | all screens | Blocks repository/test | Medium |
| TD-03 | 672 `setState`, no state mgmt | app-wide | Bugs, no reuse | Large |
| TD-04 | `print()` ×22 in paths | incl. `main.dart` | Log noise/leak | Small |
| TD-05 | `settings` table undocumented dep | `admin_settings_service` | Schema drift | Small (+Phase5) |
| TD-06 | Only 1 widget test | `test/` | No safety net | Large |
| TD-07 | Manual analyzer logs in repo | root `analyze_*.txt` | Stale noise in VCS | Small |
| TD-08 | `draft_service` lone abstraction | inconsistent patterns | Cognitive overhead | Medium |

---

## 12. Cross-Phase Critical Findings (NEW — appended live)

> Per the new rule, Critical/High findings are surfaced immediately rather than deferred.

| Ref | Severity | Title | Evidence | Effort |
|---|---|---|---|---|
| **P1-01** | Critical | Release manifest missing `INTERNET` → release app has no network | `android/app/src/main/AndroidManifest.xml` (0 `INTERNET`); present only in debug/profile | Small |
| **P1-02** | Critical | Release signed with debug keys | `android/app/build.gradle.kts:34-38` | Small |
| **P1-03** | High | No server tier; client-trust integrity model | 0 `.rpc(`/Edge in `lib/`; 116 inline clients | Large |
| **P1-04** | High | No state-management/DI; logic-in-widget | no state lib; 672 `setState` | Large |
| **P1-05** | High | God files >4k LOC | `admin_analytics_tab.dart:5443` et al. | Large |
| **P1-06** | High | Offline DB no migration path | `core/offline_db.dart:22-25` | Medium |
| **P1-07** | High | Hardcoded creds/single env | `core/supabase_config.dart:5-7` | Medium |

*(P0-01 payment mock, P0-06 schema drift, R-01 PII public bucket remain open from Phase 0 and are also tracked in the master Cross-Phase section.)*

---

## 13. Open Questions (Phase 1 additions)
8. Is there an upstream remote/repo with CI not present in this working copy? (None found locally.)
9. Does `admin_home.dart` reliably guard the no-library state (mitigating P1-09)? → **Phase 4**.
10. Are the 3 realtime channels intended as the full realtime strategy, or partial WIP? → product decision.
11. Is `geolocator` a committed feature (location-based explore) or vestigial? → affects Phase 14 permissions.

## 14. Verification Pending (Phase 1 additions)
| VID | Item | Method | Phase |
|---|---|---|---|
| V-11 | Release build actually fails network (confirm P1-01 empirically) | `flutter build apk --release` + run | 14 |
| V-12 | `admin_home` no-library guard behavior | Read `admin_home.dart` init logic | 4 |
| V-13 | RLS denies direct writes assumed safe by client-trust model | Live DB / RLS file deep-read | 5,10 |
| V-14 | iOS signing/capabilities parity | Inspect `ios/Runner.xcodeproj`, entitlements | 14 |

---

*End of Phase 1. No code was modified. Auditor stopped here and awaits approval to begin Phase 2.*
