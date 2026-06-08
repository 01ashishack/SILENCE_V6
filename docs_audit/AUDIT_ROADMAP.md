# SILENCE — Master Audit Roadmap

> **Status:** Roadmap only. No phase has been executed yet.
> **Working mode:** Phase-by-phase. After each phase I STOP and wait for `Start Phase X`.
> **Roles assumed:** Senior PM · Senior UX Designer · Senior Full-Stack Engineer · Senior Security Auditor · QA Lead · Data Analyst · App Store Review Consultant.

---

## 0. Project Snapshot (verified, not assumed)

| Attribute | Finding | Source of truth |
|---|---|---|
| Product | SILENCE — Library & study-space management platform (India, Tier 2/3) | `silence_app/01_Project_Brief.md` |
| Frontend | Flutter (Dart), Material 3, 88 Dart files, ~74,660 LOC | `lib/`, `pubspec.yaml` |
| Backend | Supabase (PostgreSQL + Auth + Storage), 25 tables | `silence_app/supabase_schema.sql` (834 lines) |
| Data access | Direct client REST builder (`.from(...)`), **no RPC / Edge Functions** despite spec | `docs_audit/KNOWN_GAPS.md`, 63 files instantiate the client inline |
| Offline | `sqflite` local DB `silence_offline.db`, scan queue + read caches | `lib/core/offline_db.dart`, `offline_sync.dart` |
| Roles | Admin (library owner) · Member (student) | `lib/screens/role_selection_screen.dart` |
| Payments | **Mocked** (no Razorpay SDK; `Future.delayed` simulation) | `lib/screens/subscription_screen.dart` |
| Notifications | **No FCM**; DB-table notifications fetched client-side | `docs_audit/KNOWN_GAPS.md` |
| Auth | Supabase Auth; **OTP phone/email verification is mocked UI** | `docs_audit/FEATURE_MATRIX.md` |
| Tests | One file only: `test/widget_test.dart` | `test/` |
| Static analysis | Pre-existing analyzer output present (`analyze_errors.txt`, etc.) | repo root |

### Known risk flags already documented (to be verified, not trusted blindly)
- Sensitive ID proofs / payment screenshots uploaded to **public** bucket `silence_assets` instead of `silence_private`.
- Business rules (max discount, seat-hold caps) **saved but not enforced** at transaction time.
- "PDF" exports actually write `.txt`; no Excel output.
- Hardcoded Supabase anon key in `lib/core/supabase_config.dart` (committed to source).

> **Missing-information register (declared up front):**
> - No live Supabase project access — schema/RLS audited from `.sql`/`.json` files, not the running DB. **Cannot verify deployed RLS matches repo.**
> - No running build/emulator confirmed — UX/QA phases audit code + specs, and will flag anything that requires live device verification.
> - `08_Razorpay_Spec.md` is **empty (0 bytes)** — payment spec must be treated as undefined.
> - No CI/CD config located yet — to be confirmed in Phase 1.

---

## Severity Scoring Model (applies to every phase)

| Severity | Definition | Example | SLA |
|---|---|---|---|
| **Critical** | Data loss, security breach, money handled incorrectly, or app unusable for a core role. Ship-blocker. | Public ID-proof URLs; payment marked paid without payment | Fix before any release |
| **High** | Core feature broken/incomplete, exploitable abuse, or store-rejection cause. | Business rule not enforced; OTP mocked; missing RLS | Fix before production |
| **Medium** | Partial feature, correctness gap in non-critical path, notable UX friction. | TXT-as-PDF export; missing empty states | Fix in next sprint |
| **Low** | Cosmetic, minor inconsistency, tech-debt, nice-to-have. | Copy typos; dead imports | Backlog |

**Finding ID format:** `P<phase>-<seq>` (e.g., `P10-03`). Cross-phase duplicates are linked, not repeated.

**Per-finding fields (every finding carries all of these):**
ID · Severity · Category · Description · Evidence (`file:line`) · Root Cause · Impact · Exploitation Scenario (if applicable) · Recommended Fix · Implementation Example.

---

## Per-Phase Deliverable Format (every phase produces this exact structure)

1. Executive Summary
2. What Was Reviewed
3. Files Reviewed
4. Screens Reviewed
5. Findings (full field set above)
6. Missing Connections (button→flow, admin↔member parity, table→UI, API→consumer, screen→navigation)
7. Incomplete Features (half-built, dead code, unused APIs/tables, placeholder UI, missing backend logic)
8. Improvement Suggestions
9. Priority Fix List (ordered)

Each phase also answers the 13-point feature checklist (why added · solves problem · flow complete · FE↔BE connected · DB correct · permissions correct · data accurate · usable · edge cases · abuse/hack · UI clear · UX smooth · production-ready) for the features in its scope.

---

## The Phases

### Phase 0 — Product Understanding
- **Objective:** Establish the authoritative "what & why" — purpose, users, roles, business logic, feature inventory, monetization. Baseline every later phase references.
- **Inspect:** `silence_app/01_Project_Brief.md`, `02_User_Stories.csv`, `06_Business_Rules.csv`, `07_Workflows.yaml`, `SILENCE_PRD_v6.1_Final.md`, `docs_audit/CURRENT_PRD.md`, `CURRENT_STATE.md`, `FEATURE_MATRIX.md`, `KNOWN_GAPS.md`.
- **Methodology:** Cross-read all PRD/spec docs; build a canonical role × feature × monetization model; list documented-vs-claimed deltas. Pure synthesis, no code judgments.
- **Deliverables:** Product charter, role model, feature catalog, business-logic glossary, open-questions list.

### Phase 1 — Architecture Audit
- **Objective:** Validate the technical structure: layering, routing, state management, data-access pattern, offline architecture, config/secrets, build/CI.
- **Inspect:** `lib/main.dart`, `lib/core/*` (`supabase_config.dart`, `offline_db.dart`, `offline_sync.dart`, `cache_service.dart`, `admin_settings_service.dart`), `lib/services/`, `pubspec.yaml`, `analysis_options.yaml`, `android/`, `ios/`, `web/`, CI files.
- **Methodology:** Map dependency graph and layer boundaries; assess the "no service layer / inline Supabase in 63 files" pattern; review routing table in `main.dart`; secrets handling; offline-sync design.
- **Deliverables:** Architecture diagram (textual), layering assessment, tech-debt register, secrets/config findings.

### Phase 2 — Feature Mapping Audit
- **Objective:** Build the master feature inventory and map each feature → screen(s) → table(s) → route(s); detect orphans.
- **Inspect:** All `lib/screens/**`, `lib/widgets/`, route map in `main.dart`, `docs_audit/SCREEN_MATRIX.md`, `UPDATED_Screen_Inventory.csv`, `screen_inventory.csv`.
- **Methodology:** Static cross-reference of routes, screen files, and table usage; produce a traceability matrix; flag screens with no route, routes with no nav entry, tables with no screen.
- **Deliverables:** Feature × screen × table × route traceability matrix; orphan list (feeds Phases 3–7).

### Phase 3 — User (Member) Flow Audit
- **Objective:** End-to-end member journeys: discover → join → approval → check-in/out → renewal → hold → analytics → support.
- **Inspect:** `member_home.dart`, `member_explore_screen.dart`, `library_public_profile_screen.dart`, `reservations/join_flow_screen.dart`, `qr_scanner_screen.dart`, `renewal_screen.dart`, `library_query_screen.dart`, `member_history_tab.dart`, `member_analytics_tab.dart`, `member_profile_*`, member settings screens.
- **Methodology:** Trace each flow screen→state→DB write; verify completeness, edge cases, FE↔BE wiring; confirm navigation reachability.
- **Deliverables:** Member-flow findings, broken/dead-end flows, missing connections.

### Phase 4 — Admin Flow Audit
- **Objective:** End-to-end owner journeys: onboarding → library setup (3 stages) → dashboard → join approvals → roster/attendance → add-member wizard → settings → closures/announcements/exports.
- **Inspect:** `admin_home.dart`, `admin_profile_complete.dart`, `library_setup_stage1-3.dart`, `reservations/*` (requests, members, layout, archive sub-tabs, member_detail), `admin/add_member_*` wizard, all `/admin/settings/*` screens.
- **Methodology:** Trace each admin flow to DB; verify multi-shift seat logic, seat assignment, approval state machine; permission checks per action.
- **Deliverables:** Admin-flow findings, state-machine gaps, missing connections, admin↔member parity notes.

### Phase 5 — Database Audit
- **Objective:** Validate schema integrity, relationships, constraints, indexes, RLS policy correctness, and code-vs-schema drift.
- **Inspect:** `silence_app/supabase_schema.sql`, `04_Database_Schema.json`, `05_RLS_Rules.json`, `12_Offline_Schema.sql`, all `*.sql` (root + `silence_app/`), `lib/core/offline_db.dart`.
- **Methodology:** Enumerate 25 tables; check FK/cascade, NOT NULL, CHECK, uniqueness, indexes vs query patterns; map every table to RLS coverage; flag columns referenced in code but absent in schema (and vice-versa). **Declared limitation:** policies audited from files, not the live DB.
- **Deliverables:** Schema integrity report, RLS coverage matrix, drift list, indexing recommendations.

### Phase 6 — API / Data-Access Audit
- **Objective:** Audit every Supabase interaction: correctness of queries, error handling, the documented-RPC-vs-actual-REST gap, N+1 patterns, unconsumed endpoints.
- **Inspect:** Every `.from(...)`, `.rpc(...)`, `.storage`, `.auth` call across `lib/**`; `silence_app/17_API_Endpoints.md`.
- **Methodology:** Catalog all data calls per screen; compare against documented API contract; identify missing server-side validation now that RPCs are bypassed; spot over-fetching.
- **Deliverables:** Data-access catalog, spec-vs-code API gap report, server-side-validation risk list.

### Phase 7 — Business Logic Audit
- **Objective:** Verify the rules engine: shifts, seat occupancy (multi-shift sharing), membership lifecycle (trial/active/grace/expired), discounts, holds, transfers, referrals, closures.
- **Inspect:** `business_rules.dart`, `shift_management.dart`, `pricing_plans.dart`, `referral_settings.dart`, `scheduled_closures.dart`, `addon_services.dart`, `renewal_screen.dart`, `join_flow_screen.dart`, `core/admin_settings_service.dart`; `06_Business_Rules.csv`, `07_Workflows.yaml`.
- **Methodology:** Encode each documented rule as an assertion; verify enforcement at write time (esp. discount caps & seat-hold limits flagged as unenforced); test lifecycle transitions.
- **Deliverables:** Rule-enforcement matrix (configured vs enforced), lifecycle correctness findings.

### Phase 8 — Calculations & Data Accuracy Audit
- **Objective:** Verify every computed value: occupancy %, revenue, expenses, study hours, streaks, leaderboard, expiry countdowns, analytics aggregates.
- **Inspect:** `admin_analytics_tab.dart`, `member_analytics_tab.dart`, `core/member_analytics_service.dart`, `admin_home.dart` (donut/stats), `member_home.dart`, `utils/time_utils.dart`, `past_library_detail_screen.dart`.
- **Methodology:** Recompute formulas by hand against code; check timezone/date-boundary handling, rounding, division-by-zero, double-count on offline sync; validate data sources for each metric.
- **Deliverables:** Metric-by-metric accuracy table, formula defects, edge-case math failures.

### Phase 9 — UI/UX Audit
- **Objective:** Assess usability, consistency, discoverability, accessibility, empty/loading/error states against the design system.
- **Inspect:** All screens (visual/structural), `lib/widgets/*`, `16_Design_System.json`, `main.dart` theme, `docs_audit/member_home_ui_prompts.md`.
- **Methodology:** Heuristic evaluation (Nielsen), design-system conformance, navigation discoverability, contrast/tap-target/accessibility checks, state coverage. **Declared limitation:** no live render; flags items needing on-device confirmation.
- **Deliverables:** UX findings by screen, consistency/accessibility issues, discoverability gaps.

### Phase 10 — Security Audit
- **Objective:** Identify vulnerabilities across auth, authorization (RLS), storage privacy, secrets, input validation, client-trust, injection, offline-data exposure.
- **Inspect:** `supabase_config.dart` (hardcoded key), `auth_screen.dart`, RLS files, storage upload sites (`join_flow_screen.dart`, `member_profile_edit.dart`, `admin_profile_tab.dart`), QR scan trust, `offline_db.dart`; Android/iOS manifests & permissions.
- **Methodology:** Threat-model per role; verify least-privilege RLS; test public-bucket exposure of PII; client-side-only auth checks; secret management; OWASP Mobile Top 10 pass.
- **Deliverables:** Vulnerability register with exploitation scenarios, RLS gap list, PII-exposure report.

### Phase 11 — Performance Audit
- **Objective:** Find slow paths, over-fetching, N+1, unbounded lists, image/QR cost, rebuild storms, offline-sync cost.
- **Inspect:** High-traffic screens (`admin_home`, `member_home`, `layout_sub_tab`, analytics tabs), `core/cache_service.dart`, `image_optimizer.dart`, `offline_sync.dart`, query patterns from Phase 6.
- **Methodology:** Static analysis of query/render patterns; list pagination; index alignment (with Phase 5); widget rebuild scope; large-file complexity (e.g., 5,443-line analytics tab).
- **Deliverables:** Performance findings, query-cost hotspots, caching/pagination recommendations.

### Phase 12 — Error Handling Audit
- **Objective:** Verify failure handling: network loss, auth expiry, payment failure, upload failure, offline-sync conflicts, empty/null safety.
- **Inspect:** `try/catch`/`print` sites across services and screens; `offline_sync.dart` conflict logic; payment mock failure path; null-assertion sites (`scratch/analyze_null_assertions.py` output).
- **Methodology:** Enumerate failure modes per flow; verify user-facing recovery vs silent `print`; check retry/rollback; surface swallowed exceptions.
- **Deliverables:** Error-handling gap list, silent-failure register, resilience recommendations.

### Phase 13 — QA & Edge Cases Audit
- **Objective:** Define a structured test plan and probe edge cases; assess existing test coverage (currently 1 widget test).
- **Inspect:** `test/widget_test.dart`, `silence_app/11_Test_Scenarios.csv`, all flows from Phases 3–4.
- **Methodology:** Build test matrix (unit/widget/integration) per feature; enumerate edge cases (double check-in, expired-membership scan, concurrent seat assignment, offline→online dup, timezone, leap/boundary dates); coverage-gap analysis.
- **Deliverables:** Test plan, edge-case catalog with expected vs likely-actual behavior, coverage gap report.

### Phase 14 — Play Store / App Store Readiness Audit
- **Objective:** Assess store-submission readiness: permissions justification, privacy policy/data-safety, content, versioning, signing, account deletion, payment-policy compliance.
- **Inspect:** `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`, permission usage (`geolocator`, `image_picker`, `permission_handler`, camera/`mobile_scanner`), `member_privacy_policy_screen.dart`, `member_terms_screen.dart`, `member_licences_screen.dart`, `pubspec.yaml` versioning, `08_Razorpay_Spec.md`.
- **Methodology:** Map each runtime permission to a declared purpose; check Apple/Google data-safety, account-deletion, and in-app-purchase/external-payment policy; review store metadata readiness.
- **Deliverables:** Store-readiness checklist (Android + iOS), rejection-risk list, required-disclosure gaps.

### Phase 15 — Missing Features & Product Improvement Audit
- **Objective:** Identify gaps vs PRD, vs competitors, and vs user needs; recommend roadmap improvements.
- **Inspect:** Cross-output of Phases 2–14, `SILENCE_PRD_v6.1_Final.md` "Out of Scope" list, `KNOWN_GAPS.md`, `FINAL_REMAINING_FIXES.md`.
- **Methodology:** Gap analysis (documented-but-unbuilt, built-but-undocumented, neither-but-needed); prioritize by impact/effort.
- **Deliverables:** Prioritized product-improvement backlog, V1-blocker vs V2 split.

### Phase 16 — Final Consolidated Report
- **Objective:** Single executive report unifying all phases: posture, severity rollup, prioritized remediation roadmap, release recommendation.
- **Inspect:** All phase outputs.
- **Methodology:** Aggregate findings; dedupe; severity heat-map; sequence remediation; go/no-go per release channel.
- **Deliverables:** Executive summary, consolidated findings register, master priority fix list, release-readiness verdict.

---

## Execution Order & Dependencies

```
0 ──► 1 ──► 2 ──┬─► 3 ──┐
                ├─► 4 ──┤
                ├─► 5 ──┼─► 7 ──► 8 ──► 9 ──► 10 ──► 11 ──► 12 ──► 13 ──► 14 ──► 15 ──► 16
                └─► 6 ──┘
```
Phase 2's traceability matrix feeds 3–7. Phase 5 (schema) and 6 (API) feed 7, 8, 10, 11. Phase 16 consumes all.

---

## Working Protocol
- I execute **one phase per command** (`Start Phase X`), then **STOP** and wait for approval.
- Each phase is delivered as its **own report** (separate file `docs_audit/AUDIT_PHASE_<n>.md` + inline summary). No combined dump.
- Anything unverifiable (live DB, on-device render, empty specs) is **explicitly flagged as missing**, never assumed.
