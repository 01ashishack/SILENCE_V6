# SILENCE — Phase 0: Product Understanding

**Phase:** 0 of 16 — Product Understanding
**Completed (local time):** 2026-06-08
**Auditor roles applied:** Senior PM · Senior UX Designer · Senior Full-Stack Engineer · Senior Security Auditor · QA Lead · Data Analyst · App Store Review Consultant
**Verification stance:** Every product claim below is cross-checked against actual code. Documentation is treated as a *claim*, not a *fact*, until verified. Unverifiable items are listed in "Verification Pending."

---

## 1. Executive Summary

SILENCE is a **mobile-first (Flutter) library & study-space management platform** targeting study-library owners and students in Indian Tier-2/Tier-3 cities. It replaces the WhatsApp + paper-register + spreadsheet stack with one operational app: admins manage seats, members, attendance, payments and analytics; students track attendance, streaks, leaderboard and membership status. Backend is **Supabase (PostgreSQL + Auth + Storage)**.

The product is **feature-broad and largely UI-complete** (66 screen files, ~74.6k LOC, 25 documented tables) but Phase 0 verification already confirms several **structural deviations from its own specifications** that materially affect production-readiness:

- **Payments are entirely mocked** — no Razorpay SDK exists in the project; checkout is a `Future.delayed` simulation. *(Verified)*
- **No server-side business logic** — the documented RPC/Edge-Function layer does not exist; all writes go direct from client via `.from(...)`. *(Verified: 0 `.rpc(` / `functions.invoke` calls in `lib/`)*
- **No push notifications** — no Firebase/FCM dependency or code. *(Verified)*
- **OTP verification is mocked** — code literally prints `Mock OTP Code Sent: 123456`. *(Verified)*
- **Social login (Google/Apple) is documented but absent** — `0` `signInWithOAuth` calls. *(Verified)*
- **Sensitive PII goes to a public bucket** — `silence_assets` (public) referenced ~30× vs `silence_private` ~11×. *(Verified — deep-dived in Phase 10)*
- **Schema/code drift** — 7 tables are queried in code but absent from `supabase_schema.sql`; 2 schema tables are never queried. *(Verified)*

**Phase 0 verdict:** The product vision is coherent and well-documented; the *implementation* is a high-fidelity prototype with critical backend/commerce/notification subsystems simulated. None of this is a defect of Phase 0 — it scopes *what to scrutinize* in Phases 1–16. No code changes are made in Phase 0.

---

## 2. What Was Reviewed

Authoritative product/spec documents (read in full or substantially), then **independently verified against `lib/` source**:

- Product specs: `silence_app/01_Project_Brief.md`, `SILENCE_PRD_v6.1_Final.md`, `02_User_Stories.csv`, `06_Business_Rules.csv`, `07_Workflows.yaml`, `17_API_Endpoints.md`.
- Implemented-state docs (themselves prior artifacts, treated as claims): `docs_audit/CURRENT_PRD.md`, `CURRENT_STATE.md`, `FEATURE_MATRIX.md`, `KNOWN_GAPS.md`, `UPDATED_Business_Rules.csv`.
- Code verification: `lib/main.dart`, `lib/core/supabase_config.dart`, `lib/screens/role_selection_screen.dart`, `lib/screens/subscription_screen.dart`, `lib/screens/member_profile_edit.dart`, plus repo-wide greps for SDK presence, auth methods, RPC calls, table usage, and bucket targets.

---

## 3. Files Reviewed

| File | Purpose | Used for |
|---|---|---|
| `silence_app/01_Project_Brief.md` | Vision, market, stack, roles | Product purpose, value prop |
| `silence_app/SILENCE_PRD_v6.1_Final.md` | Full PRD (in/out scope, nav, flows) | Feature inventory, scope boundaries |
| `silence_app/02_User_Stories.csv` | 49 user stories (Admin/Member/System) | Capability lists, journeys |
| `silence_app/06_Business_Rules.csv` | 33 configurable rules + defaults | Business-logic glossary |
| `silence_app/07_Workflows.yaml` | 7 state machines | Workflow overview |
| `silence_app/17_API_Endpoints.md` | Documented RPC/Edge contract | API expectation baseline |
| `docs_audit/CURRENT_PRD.md` | Claimed implemented state | Delta vs spec |
| `docs_audit/FEATURE_MATRIX.md` | Story→code sync claims | Cross-check target |
| `docs_audit/KNOWN_GAPS.md` | Prior gap catalogue | Risk seeding |
| `docs_audit/UPDATED_Business_Rules.csv` | Claimed enforcement status | Cross-check target |
| `lib/main.dart` | Routes, theme, bootstrap | Module map |
| `lib/core/supabase_config.dart` | Backend config | Secrets/architecture |
| `lib/screens/role_selection_screen.dart` | Role model | Roles verification |
| `lib/screens/subscription_screen.dart` | Subscription/payment | Payment-mock verification |
| `lib/screens/member_profile_edit.dart` | Profile + OTP | OTP-mock verification |

---

## 4. Screens Reviewed

Phase 0 is product-level, not screen-by-screen (that is Phases 3–4 & 9). Screen **inventory** was established for the feature map: **66 screen files** total — 9 in `screens/admin/`, 10 in `screens/reservations/`, 14 `member_*`, remainder in `screens/`. Detailed per-screen behavioral review is deferred to later phases by design.

---

## 5. Findings

> Phase 0 findings are **product-understanding observations**: scope deltas, role/value clarifications, and seeds for later deep-dives. Severity here reflects product/release risk; technical exploitation detail is produced in the owning phase (noted per finding).

### P0-01 — Payments are fully mocked; no payment SDK exists
- **Severity:** Critical (release-blocker for any monetized flow)
- **Category:** Commerce / Feature Completeness
- **Description:** Both admin subscription billing and (per docs) member payment flows are simulated. No Razorpay package is declared or imported.
- **Evidence:** `pubspec.yaml` contains no razorpay dependency (grep: none). `lib/screens/subscription_screen.dart` uses `_buildRazorpaySimulationSheet()` and `await Future.delayed(const Duration(milliseconds: 2000)); // Simulated delay` (line ~277); cancellation shows "locked in simulated mode" (line ~433). `silence_app/08_Razorpay_Spec.md` is **0 bytes**.
- **Root Cause:** Payment integration deferred; spec file never authored.
- **Impact:** No real money can be collected; admin subscription gating is non-functional; revenue model unvalidated.
- **Exploitation Scenario:** N/A here (correctness). Abuse potential (marking unpaid as paid) is assessed in Phase 7/10.
- **Recommended Fix:** Treat Razorpay (or equivalent) integration as a tracked epic; author `08_Razorpay_Spec.md`; deep audit in **Phase 7 (Business Logic)** and **Phase 14 (Store readiness / payment policy)**.
- **Implementation Example:** Add `razorpay_flutter`, implement order creation server-side (Edge Function), verify signature, persist verified `payments` rows — detailed in Phase 7.

### P0-02 — Documented RPC/Edge-Function layer does not exist
- **Severity:** High
- **Category:** Architecture / Data Integrity
- **Description:** `17_API_Endpoints.md` specifies critical transactions (check-in, renewal, hold) as Postgres RPCs/Edge Functions for server-side validation. Code performs all of these as direct client REST writes.
- **Evidence:** Repo-wide grep for `.rpc(` and `functions.invoke` in `lib/` returns **0 matches**. Table writes are direct, e.g. `.from('attendance').insert(...)`, `.from('memberships')...`.
- **Root Cause:** Client-direct approach chosen over documented server layer.
- **Impact:** Business rules cannot be enforced centrally; all integrity depends on RLS + client honesty. Directly enables several enforcement gaps (Phase 7).
- **Recommended Fix:** Decide architecture intentionally (RPC for money/seat/lifecycle transactions vs. hardened RLS + DB triggers). Full analysis in **Phase 6 (API)** and **Phase 7**.

### P0-03 — Push notifications (FCM) entirely absent
- **Severity:** High
- **Category:** Feature Completeness / Engagement
- **Description:** PRD §17.3 and `09_Notification_Payloads.json` define FCM push for join requests, payments, expiry, etc. No Firebase dependency or messaging code exists; notifications are DB rows fetched client-side.
- **Evidence:** `pubspec.yaml` has no `firebase_*` package; grep for `firebase|fcm|messaging` in `lib/` finds only an unrelated UI string.
- **Root Cause:** FCM integration not implemented.
- **Impact:** Core engagement loop (real-time alerts) is non-functional; users must open the app to discover events. Affects retention metrics named in the brief.
- **Recommended Fix:** Scope FCM as an epic; verify notification *data model* completeness in **Phase 5/6**, delivery in **Phase 14**.

### P0-04 — OTP phone/email verification is mocked
- **Severity:** High
- **Category:** Auth / Trust & Safety
- **Description:** "Verify Phone/Email" issues no real OTP; the code reveals a hardcoded code to the user.
- **Evidence:** `lib/screens/member_profile_edit.dart:480` → `_showSuccessSnackBar('Mock OTP Code Sent: 123456');` with local comparison at line ~492. `lib/screens/member_about_screen.dart:52` advertises "mock OTP authentication."
- **Root Cause:** Verification stubbed for prototype.
- **Impact:** Profile "verified" badges are meaningless; duplicate-account prevention (a documented System story) cannot rely on verified contact. Security implications in **Phase 10**.
- **Recommended Fix:** Wire Supabase Auth phone/email OTP (or provider) before any trust-dependent feature ships.

### P0-05 — Social login (Google/Apple) documented but not implemented
- **Severity:** Medium
- **Category:** Auth / Onboarding
- **Description:** PRD and user stories promise "Continue with Google / Apple"; code only does email/password.
- **Evidence:** Repo-wide auth-method grep: `signInWithPassword` ×1, `signUp` ×1, **`signInWithOAuth` ×0**. Auth verified in Phase 1/10.
- **Root Cause:** OAuth not built.
- **Impact:** Onboarding friction higher than designed; iOS App Store may *require* Apple Sign-In if other social logins are later added (Phase 14 watch item).
- **Recommended Fix:** Implement or formally de-scope; if de-scoped, remove promises from store metadata.

### P0-06 — Schema ↔ code table drift (7 missing tables, 2 unused tables)
- **Severity:** High
- **Category:** Data Integrity / Architecture
- **Description:** Code queries tables not present in the canonical `supabase_schema.sql`, and the schema contains tables never queried. The live DB therefore cannot be fully reconstructed from the committed schema.
- **Evidence:** Queried-but-not-in-`supabase_schema.sql`: `settings`, `streaks`, `member_daily_stats`, `library_closures`, `leads`, `verification_requests`, `draft_members` (the last has a standalone `draft_members.sql`; `verification_requests` has **no migration anywhere**). In-schema-but-never-queried: `member_add_ons`, `transfers`. (Add-ons are written through a different path — to confirm in Phase 6/7.)
- **Root Cause:** Schema file not kept in lockstep with iterative code; migrations scattered across root + `silence_app/`.
- **Impact:** Onboarding a new environment from the committed schema would break the app (missing tables) and ship dead tables. Migration provenance is fragmented.
- **Recommended Fix:** Reconcile into a single source-of-truth migration set; full table-by-table reconciliation in **Phase 5 (Database)**.

### P0-07 — "Implemented-state" docs make enforcement claims that must be independently re-verified
- **Severity:** Medium (process risk)
- **Category:** Documentation Integrity
- **Description:** `UPDATED_Business_Rules.csv` and `FEATURE_MATRIX.md` assert specific enforcement statuses (e.g., "max_discount not enforced," "exit_dues_block not enforced"). These are plausible and partly spot-confirmed, but were authored by a prior pass and **will not be trusted as evidence** — each is a hypothesis to verify in the owning phase.
- **Evidence:** Conflicting defaults across docs (e.g., `max_discount_percent` = 100 in `06_Business_Rules.csv` vs 15 in `UPDATED_Business_Rules.csv`) prove the docs are not mutually authoritative.
- **Root Cause:** Multiple doc generations without reconciliation.
- **Impact:** Risk of inheriting wrong assumptions. Mitigation: treat as Open Questions / Verification-Pending, resolve with code in Phases 5–8.
- **Recommended Fix:** Each enforcement claim is tracked in the Verification Checklist (§13) and closed only with a `file:line` code reference.

### P0-08 — Hardcoded Supabase credentials committed in source
- **Severity:** High (flagged here, fully assessed in Phase 10)
- **Category:** Security / Secrets
- **Description:** Supabase URL and anon key are hardcoded literals in `lib/core/supabase_config.dart` and committed.
- **Evidence:** `lib/core/supabase_config.dart` — `static const String url = 'https://kndeshxeerldamafweru.supabase.co';` and a literal `anonKey`.
- **Root Cause:** No env/secret management.
- **Impact:** Anon key is client-distributed by nature, but committing project URL + key concentrates exposure and makes rotation hard; the real risk is whether RLS is airtight (Phase 5/10). Several SQL files also leak the project dashboard URL.
- **Recommended Fix:** Externalize config (`--dart-define`/env); full secret + RLS posture in **Phase 10**.

---

## 6. Missing Connections (initial, product-level)

These are *suspected* disconnects identified from spec-vs-code signals; each is assigned to a later phase for confirmation (button→flow, table→UI, API→consumer, screen→nav):

- **`transfers` table (schema) → no consumer:** member-transfer workflow documented (`07_Workflows.yaml` #6) and table exists, but `0` code references. *Verify Phase 4/6.*
- **`member_add_ons` table → no direct query:** add-ons sold in join flow but this junction table is unused in `lib/`. *Verify Phase 6/7.*
- **FCM event catalogue (`09_Notification_Payloads.json`) → no delivery path:** notification *intent* defined, delivery missing. *Verify Phase 6.*
- **RPC contract (`17_API_Endpoints.md`) → no callers:** entire documented API surface unconsumed. *Verify Phase 6.*
- **`verification_requests` queried in code → no schema/migration:** UI may write to a table that does not exist in any committed migration. *Verify Phase 5.*
- **Google/Apple login buttons (PRD) → no OAuth handler:** UI may present unsupported options. *Verify Phase 3/9.*

---

## 7. Incomplete Features (initial register)

| Feature | Status signal | Owning phase |
|---|---|---|
| Razorpay payments (member + admin subscription) | Mocked (`Future.delayed`) | 7, 14 |
| Push notifications (FCM) | Not implemented | 6, 14 |
| OTP phone/email verification | Mocked (`123456`) | 10 |
| Google/Apple OAuth | Not implemented | 3, 10 |
| Server-side RPC/Edge layer | Not implemented | 6, 7 |
| PDF export | Reportedly writes `.txt` (claim) | 8, 15 |
| Streak freeze on closure | Claimed unimplemented | 7, 8 |
| Referral reward crediting | Claimed records-only, no day-extension | 7 |
| Auto-checkout sweep | Claimed client-side unimplemented | 7 |
| Member transfer between libraries | Table present, no consumer | 4 |

*(All "claimed" items are unverified prior-doc assertions; do not treat as confirmed until the owning phase closes them.)*

---

## 8. Security Issues (Phase 0 seeds → owned by Phase 10)

- **PII in public bucket:** `silence_assets` (public) is the dominant upload target (~30 refs) over `silence_private` (~11). ID proofs / payment screenshots likely publicly readable. **Critical candidate.**
- **Hardcoded credentials & dashboard URLs** in `supabase_config.dart` and multiple `.sql` files.
- **No server-side validation** (no RPC) → integrity rests entirely on RLS, which is audited only from files, not the live DB.
- **Mocked OTP** undermines any identity-trust feature.

*(All escalated to Phase 10 with exploitation scenarios; listed here only to seed the cumulative Security register.)*

---

## 9. Improvement Suggestions (product-level)

1. **Establish a single source of truth for schema/migrations** before deeper DB work (prevents compounding drift).
2. **Author the empty `08_Razorpay_Spec.md`** and a notification-delivery design before claiming V1 readiness.
3. **Separate "prototype-simulated" from "production" features explicitly** in a release matrix so stakeholders aren't misled by UI completeness.
4. **Externalize configuration/secrets** immediately (cheap, reduces rotation pain).
5. **Reconcile the three conflicting business-rule documents** into one authoritative, code-linked rules registry.

---

## 10. Priority Fix List (Phase 0 — investigation priorities, not yet code fixes)

| # | Item | Severity | Owning Phase |
|---|---|---|---|
| 1 | Confirm PII public-bucket exposure end-to-end | Critical | 10 |
| 2 | Confirm payment mock + design real flow | Critical | 7, 14 |
| 3 | Resolve schema↔code table drift (esp. `verification_requests` with no migration) | High | 5 |
| 4 | Verify business-rule enforcement gaps (discount, dues, holds) | High | 7 |
| 5 | Decide & document server-side vs RLS-only integrity model | High | 6, 7 |
| 6 | Confirm OTP/OAuth auth gaps | High/Med | 10, 3 |
| 7 | Confirm notification delivery gap | High | 6 |

---

## 11. Product Understanding Deliverables

### 11.1 Product Purpose
Replace the fragmented WhatsApp + paper-register + spreadsheet workflow of Indian study libraries with **one operational app** that handles seats, members, attendance, payments, and analytics — and gives students personal progress tracking. *(Source: `01_Project_Brief.md`, `SILENCE_PRD_v6.1_Final.md` §1.)*

### 11.2 Target Users
- **Primary:** Study-library owners in Tier-2/3 Indian cities (Alwar, Bhilwara, Kota, Jaipur).
- **Secondary:** Students preparing for competitive exams (UPSC, NEET, JEE, SSC).

### 11.3 User Roles (verified)
Exactly two app roles, chosen once and **permanent** (`role_selection_screen.dart:54,63` upserts `role`; UI warns "cannot change your role after selection"):
- **`admin`** — Library Owner.
- **`member`** — Student.
- Plus a **`System`** actor in specs (automated workflows: auto-checkout, auto-hold, sync, streak-freeze) — not a login role; implemented (if at all) as client/scheduled logic. *No staff/sub-account role in V1 (out of scope).*

### 11.4 Core Value Proposition
"Replace the register and WhatsApp with one operational app." Differentiators: dashboard-first admin UX, **multi-shift seat model** (one physical seat → different members per shift), **static printable QR**, **offline-first scanning** (≤500 queued), India-specific payments (UPI deep-links/cash), and student **streak + leaderboard** gamification.

### 11.5 Complete Feature Inventory

**Admin / Library Owner**
- Auth & role selection; admin profile onboarding.
- Library setup wizard: Stage 1 details (+ `SIL-XXXXXX` code, photos, amenities), Stage 2 layout (floors/sections/seats), Stage 3 shifts & pricing (monthly/3/6-month, trial days).
- Operational dashboard (revenue this month, active today, expired, new joinings, expiring soon, live occupancy donut; tappable filters).
- Member roster & filters; member detail; manual check-in; checkout edit.
- Join-request approval/reject; payment confirmation (UPI screenshot / cash receipt).
- Seat management: reassign, mark maintenance, multi-shift grid.
- Membership renewal; discounts; holds; transfers (multi-library); add-on services (lockers/premium, refundable deposit).
- Announcements (targeted); query/support replies; scheduled closures / close-today; referral settings.
- Analytics + expenditure tracking; exports (CSV; "PDF" claim); audit log; verified badge; subscription/billing; library public profile, branding, QR assets, social links; permanent library closure.

**Member / Student**
- Auth & role selection; profile setup (nickname required, ID proof upload).
- Explore/discover libraries (name/city/code), public profile, verified tick.
- Join flow (profile inline → existing-member → shift & plan + trial → add-ons → payment → review); UPI screenshot upload; "Payment Under Review."
- Membership card(s): seat, shift, plan, expiry progress, dues/trial banners.
- QR check-in/out (offline-capable); renewal; seat-change request; hold/pause; exit (dues-blocked per spec).
- Personal analytics: days present/absent, hours, attendance rate, **streak, leaderboard (nickname), badges**, bar chart, calendar heatmap; attendance CSV export.
- Referrals (code, share, reward days); announcements feed; library queries; contact/social links; (mocked) phone/email verification.

**System (automated, documented)**
- Auto-checkout at shift end (+delay); auto-hold after grace; offline scan sync (FIFO, newer-timestamp-wins); streak freeze on closure; QR 7-day regeneration grace; duplicate-phone prevention; FCM push for all PRD §17.3 events.

### 11.6 Feature Hierarchy Map
```
SILENCE
├── Auth & Identity
│   ├── Sign up / Log in (email+pwd ✔; Google/Apple ✘)
│   ├── Role selection (admin | member, permanent)
│   └── Profile + verification (OTP mocked)
├── ADMIN
│   ├── Onboarding (profile → library setup S1–S3 → launch)
│   ├── Operations (dashboard, roster, requests, attendance, seat grid)
│   ├── Membership ops (renewal, discount, hold, transfer, add-ons)
│   ├── Communication (announcements, queries, closures)
│   ├── Monetization (subscription/billing — mocked)
│   └── Settings & Trust (business rules, pricing, branding, QR, referrals,
│       verified badge, audit log, exports, library profile/closure)
├── MEMBER
│   ├── Discovery (explore, public profile)
│   ├── Join (multi-step flow, trial, add-ons, payment proof)
│   ├── Membership (card, renewal, seat-change, hold, exit)
│   ├── Attendance (QR check-in/out, offline queue)
│   └── Engagement (analytics, streak, leaderboard, badges, referrals, queries)
├── SHARED / SYSTEM
│   ├── Notifications (DB-only; FCM ✘)
│   ├── Offline sync (sqflite queue + caches)
│   └── Automated rules (auto-checkout, auto-hold, streak-freeze) — verify Phase 7
└── BACKEND (Supabase)
    ├── PostgreSQL (25 documented tables; drift noted)
    ├── Auth (email/pwd)
    └── Storage (silence_assets public / silence_private)
```

### 11.7 Module Relationships
- **`main.dart`** is the composition root: bootstraps Supabase + offline SQLite, defines theme and **all named routes** (admin + member stacks).
- **`core/`** = cross-cutting services: `supabase_config` (backend), `offline_db`/`offline_sync`/`cache_service` (offline + caching), `admin_settings_service`, `member_analytics_service`, `image_optimizer`, `calendar_picker`.
- **`screens/`** = feature UI, each screen talking **directly** to Supabase (no repository layer; ~63 files instantiate the client) — a key architectural fact for Phase 1/6.
- **`widgets/`** = reusable UI (seat grid, QR modal, bottom sheets).
- **`models/`** + **`services/draft_service.dart`** = the only model/service abstraction (member drafts) — minimal domain layer.
- **`utils/`** = CSV/PDF export, time utilities.

### 11.8 Admin Capabilities & 11.9 Member Capabilities — see §11.5 (verified inventory).

### 11.10 User Journey Overview
- **App open (PRD §2.1):** Splash → session check → Auth (if none) → role read → Role Selection (if none) → admin: library-exists check → Setup Stage 1 (mandatory modal) or Dashboard; member → Member Home.
- **Admin happy path:** onboard → setup library (3 stages) → launch → approve joins → confirm payments → daily ops (attendance, seats) → renew/hold/transfer → analyze → export.
- **Member happy path:** sign up → profile → explore → join (trial or pay) → await approval → QR check-in daily → track streak/analytics → renew → (hold/seat-change/exit as needed).

### 11.11 Business Workflow Overview (7 documented state machines, `07_Workflows.yaml`)
1. **Join request:** draft → pending(7-day expiry) → approved/rejected/expired.
2. **Renewal:** initiated → (admin-silent | notify-member→wait 24h | member-self) → renewed/cancelled.
3. **Hold:** pending → active_hold (bill paused, expiry extended) → resumed/rejected.
4. **Seat change:** pending → assigned/rejected/cancelled.
5. **Attendance:** no_session ⇄ active_session with normal/overtime/auto/admin/forgot transitions.
6. **Transfer:** initiated → transferred (history/streak preserved).
7. **Library closure:** active → pre_closure_check → closing (irreversible).
*(Enforcement of each verified in Phase 7.)*

### 11.12 Suspected Risk Areas to Investigate Later
(See Risk Register §12 — consolidated.)

### 11.13 Unknowns Requiring Verification
(See Verification Pending §15 and Open Questions §14.)

---

## 12. Audit Risk Register (Initial Version)

| RID | Risk | Likelihood | Impact | Suspected Severity | Owning Phase | Status |
|---|---|---|---|---|---|---|
| R-01 | PII (ID proofs, payment screenshots) publicly readable via `silence_assets` | High | Severe | Critical | 10 | Open |
| R-02 | Payments mocked; no real collection / no abuse controls | Confirmed | Severe | Critical | 7,14 | Open |
| R-03 | No server-side validation (no RPC) → integrity = RLS + client honesty | Confirmed | High | High | 6,7 | Open |
| R-04 | RLS audited from files only; live DB may differ | High | High | High | 5,10 | Open |
| R-05 | Schema↔code table drift; `verification_requests` has no migration | Confirmed | High | High | 5 | Open |
| R-06 | Business rules saved but unenforced (discount caps, dues block, holds) | High (claimed) | High | High | 7 | Open |
| R-07 | No push notifications (FCM) → engagement loop broken | Confirmed | High | High | 6,14 | Open |
| R-08 | OTP & OAuth gaps → weak identity / onboarding | Confirmed | Med | High/Med | 10,3 | Open |
| R-09 | Offline sync correctness (dup scans, conflict resolution) | Med | High | High | 8,12,13 | Open |
| R-10 | Calculation accuracy (revenue, hours, streaks, occupancy) | Med | High | High | 8 | Open |
| R-11 | Hardcoded secrets / dashboard URLs in repo | Confirmed | Med | High | 10 | Open |
| R-12 | "PDF" export writes `.txt`; no Excel | Med (claimed) | Med | Medium | 8,15 | Open |
| R-13 | Giant screen files (5k+ LOC) → maintainability/perf | Confirmed | Med | Medium | 11 | Open |
| R-14 | Single widget test; no automated coverage | Confirmed | Med | Medium | 13 | Open |
| R-15 | Store-readiness (permissions justification, data-safety, account deletion, payment policy) | Med | High | High | 14 | Open |

---

## 13. Feature Traceability Matrix (Initial Version)

*Status legend:* ✔ verified-present · ◐ partial/claimed · ✘ verified-absent · ? to-verify. Columns deepen in Phase 2.

| Feature | Primary Screen(s) | Key Table(s) | Route | Spec Source | Phase-0 Status | Verify In |
|---|---|---|---|---|---|---|
| Role selection | `role_selection_screen.dart` | `users` | `/role-select` | US row2 | ✔ | 3,4 |
| Admin profile onboarding | `admin_profile_complete.dart`, `admin_profile_tab.dart` | `users` | `/admin/profile/complete` | US row3 | ✔ | 4 |
| Library setup S1–S3 | `library_setup_stage1-3.dart` | `libraries`,`floors`,`sections`,`seats`,`shifts` | `/admin/library/setup/1..3` | US row4-6 | ✔ | 4 |
| Admin dashboard | `admin_home.dart` | `memberships`,`attendance`,`payments`,`seats` | `/admin/home` | US row8 | ✔ (calc?) | 4,8 |
| Join approvals | `reservations/requests_sub_tab.dart` | `join_requests`,`memberships`,`seats` | (tab) | US row10-11 | ✔ | 4 |
| Payment confirm | `requests_sub_tab.dart`,`subscription_screen.dart` | `payments` | (tab)/`/admin/subscription` | US row10,21 | ◐ mock | 7,14 |
| Manual check-in | `reservations/member_detail_screen.dart` | `attendance` | `/admin/member` | US row12 | ? | 4,8 |
| Seat reassign/maintenance | `reservations/layout_sub_tab.dart` | `seats`,`memberships` | (tab) | US row13-14 | ? | 4,7 |
| Renewal | `reservations/renewal_screen.dart` | `memberships`,`payments` | `/member/renewal` | US row14,33 | ? | 7 |
| Discounts | `business_rules.dart` + renewal/wizard | `memberships` | `/admin/settings/business-rules` | US row15 | ◐ enforce? | 7 |
| Announcements | `admin_home.dart`,`announcements_history_screen.dart` | `announcements`,`announcement_reads` | `/admin/announcements` | US row16 | ✔ | 4 |
| Queries/support | `help_support_screen.dart`,`library_query_screen.dart` | `queries` | `/member/query` | US row17,40 | ✔ | 3,4 |
| Add-ons | `addon_services.dart` | `add_ons`,`member_add_ons`(unused?) | `/admin/settings/addons` | US row18 | ◐ | 6,7 |
| Scheduled closures | `scheduled_closures.dart` | `scheduled_closures`/`library_closures`? | `/admin/settings/closures` | US row19 | ? drift | 5,7 |
| Subscription/billing | `subscription_screen.dart` | `users`/subscription cols | `/admin/subscription` | US row20 | ◐ mock | 7,14 |
| Exports CSV/PDF | `export_center.dart`,`utils/*` | many | `/admin/exports` | US row21 | ◐ PDF? | 8,15 |
| Audit log | `audit_log_screen.dart` | `audit_log` | `/admin/audit-log` | US row22 | ? | 4,10 |
| Transfer | (none found) | `transfers`(unused) | — | US row23 | ✘? | 4 |
| Permanent closure | `library_profile_screen.dart` | `libraries` | `/admin/library/profile` | US row24 | ? | 4 |
| Explore/discover | `member_explore_screen.dart`,`library_public_profile_screen.dart` | `libraries` | `/member/explore` | US row26 | ✔ | 3 |
| Join flow | `reservations/join_flow_screen.dart` | `join_requests`,`payments`,`silence_assets` | (stack) | US row28 | ✔ | 3 |
| QR check-in/out | `reservations/qr_scanner_screen.dart`,`offline_db.dart` | `attendance`,`offline_scan_queue` | (stack) | US row30 | ✔ | 3,8 |
| Membership card | `member_home.dart` | `memberships` | `/member/home` | US row31 | ✔ | 3,8 |
| Seat-change request | `member_home.dart` | `seat_change_requests` | — | US row34 | ? | 3,7 |
| Hold request | `member_home.dart` | `hold_requests` | — | US row35 | ◐ enforce? | 7 |
| Exit library | `member_home.dart` | `memberships` | — | US row36 | ◐ dues? | 7 |
| Member analytics | `member_analytics_tab.dart`,`member_analytics_service.dart` | `attendance`,`streaks`(drift),`member_daily_stats`(drift) | `/member/analytics` | US row37 | ◐ calc | 8 |
| Badges/streaks | `member_analytics_tab.dart` | `badges`,`streaks` | — | US row38 | ? | 7,8 |
| Referrals | `referral_settings.dart`,`join_flow_screen.dart` | `referrals` | `/admin/settings/referrals` | US row40 | ◐ reward? | 7 |
| Verification (OTP) | `member_profile_edit.dart` | `users` | `/member/edit-profile` | US row44 | ✘ mock | 10 |
| Push notifications | `notifications_screen.dart` | `notifications` | `/member/notifications` | US row51 | ✘ FCM | 6 |
| Offline sync | `core/offline_db.dart`,`offline_sync.dart` | `offline_scan_queue` | — | US row47 | ✔ | 8,12 |
| Auto-checkout | (system) | `attendance` | — | US row43 | ? | 7 |
| Auto-hold | (system) | `memberships` | — | US row44(sys) | ? | 7 |
| Streak freeze on closure | (system) | `streaks`,`scheduled_closures` | — | US row46 | ◐ claimed ✘ | 7 |
| Duplicate-phone prevention | join flow | `users`,`memberships` | — | US row48 | ? | 7,10 |

---

## 14. Open Questions

1. Does the **live** Supabase DB match `supabase_schema.sql`, or the (drifted) code? Cannot resolve without DB access. *(R-04, R-05)*
2. Where is `verification_requests` defined? No migration found — is it created manually in the dashboard? *(Phase 5)*
3. Is the **add-on** purchase persisted to `member_add_ons` via a path other than `.from('member_add_ons')` (e.g., embedded JSON), or is the junction genuinely unused? *(Phase 6/7)*
4. Is **member transfer** reachable in the UI at all, or is the `transfers` table dead? *(Phase 4)*
5. Are automated **System** workflows (auto-checkout, auto-hold, streak-freeze) implemented as client logic, DB triggers, or not at all? No RPC/Edge found. *(Phase 7)*
6. Which business-rule **defaults** are authoritative (conflicts between `06_Business_Rules.csv` and `UPDATED_Business_Rules.csv`)? *(Phase 7)*
7. Is there **any CI/CD**? None located yet. *(Phase 1)*

## 15. Verification Pending Items (carry-forward)

| VID | Item | Method to verify | Owning Phase |
|---|---|---|---|
| V-01 | RLS policies as deployed | Requires live Supabase access (NOT available) | 5,10 |
| V-02 | On-device UI/UX behavior, empty/error states | Requires running build/emulator (NOT confirmed) | 9,12,13 |
| V-03 | Business-rule enforcement (discount/dues/holds/referral) | Code trace at write sites | 7 |
| V-04 | Calculation correctness (revenue/hours/streak/occupancy) | Hand-recompute vs code | 8 |
| V-05 | PII bucket exposure end-to-end | Trace upload→URL→access | 10 |
| V-06 | "PDF"-as-`.txt`, no-Excel claims | Inspect `utils/pdf_exporter.dart`,`csv_exporter.dart` | 8 |
| V-07 | `verification_requests` / drift tables existence | Migration + dashboard audit | 5 |
| V-08 | Transfer & add-on junction consumers | Full repo trace | 4,6 |
| V-09 | Auto-* system workflows presence | Repo + DB trigger search | 7 |
| V-10 | CI/CD & signing config | Inspect repo + platform folders | 1,14 |

---

## 16. Verification Checklist (Initial Version)

Phase-0 claims and their verification state (✔ done this phase / ⏳ deferred):

- [✔] No Razorpay SDK in project — grep `pubspec.yaml` + `lib/`.
- [✔] Payment is `Future.delayed` simulation — `subscription_screen.dart:277,433`.
- [✔] No RPC/Edge calls — `0` matches for `.rpc(`/`functions.invoke` in `lib/`.
- [✔] No FCM/Firebase — `pubspec.yaml` + `lib/` grep.
- [✔] OTP mocked (`123456`) — `member_profile_edit.dart:480,492`.
- [✔] No OAuth — `0` `signInWithOAuth`; `1` `signInWithPassword`.
- [✔] Public bucket dominant — `silence_assets` 30 vs `silence_private` 11.
- [✔] Two permanent roles `admin`/`member` — `role_selection_screen.dart:54,63,158`.
- [✔] Schema↔code table drift (7 missing / 2 unused) — grep cross-check.
- [✔] Hardcoded creds — `supabase_config.dart`.
- [⏳] RLS as deployed — needs live DB (V-01).
- [⏳] Business-rule enforcement — Phase 7 (V-03).
- [⏳] Calculation accuracy — Phase 8 (V-04).
- [⏳] PII exposure end-to-end — Phase 10 (V-05).
- [⏳] PDF/Excel export claims — Phase 8 (V-06).

---

*End of Phase 0. No code was modified. Auditor stopped here and awaits approval to begin Phase 1.*
