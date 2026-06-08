# SILENCE — Phase 2: Feature Mapping Audit

**Phase:** 2 of 16 — Feature Mapping & End-to-End Connectivity
**Completed (local time):** 2026-06-08
**Auditor roles:** Senior PM (lead) · Full-Stack Engineer · UX Designer · QA Lead
**Scope:** Verify every claimed feature exists as a *complete, connected, usable* workflow — not merely "screen exists" or "table exists." Each verdict is evidence-backed.
**Global rule applied:** User Simulation Layer included (§ "User Experience & User Simulation Findings"). Behavior is labeled **Runtime-Verified** or **Code-Inferred**. No emulator was run this phase → all behavioral conclusions are **Code-Inferred** unless stated.
**Constraint honored:** No application code modified.

---

## 1. Executive Summary

End-to-end tracing of ~40 features against routes, screens, `.from()`/`.storage`/`.insert` calls, and admin↔member parity yields a clear picture: **SILENCE is broad and mostly wired, but several user-facing loops are broken at the "last mile."** The headline gaps found this phase:

- **Notifications screen is a static placeholder.** `notifications_screen.dart` is 37 lines, a hardcoded "You're all caught up!" — it **never queries the `notifications` table**, even though 3 code sites *write* notifications. The entire in-app notification surface for members is **UI-ONLY / MOCKED**. *(Code-Inferred, high confidence — file read in full.)*
- **Referral reward loop never closes.** Referrals are inserted (`join_flow_screen.dart:574`) and *counted* by status, but **no code ever sets status to `credited`/`rewarded`** and no membership is extended. The feature is **PARTIALLY COMPLETE (BACKEND-WRITE ONLY)**.
- **Add-ons are sold but not recorded.** Join flow reads `add_ons` and adds their price to the total, but the selection is **not persisted** to `member_add_ons` (table = ORPHAN) nor included in the `join_requests` payload. Admin can never see/fulfill what was purchased. **PARTIALLY COMPLETE.**
- **Member transfer is fully absent.** `transfers` table exists; **zero** code references; no UI entry point. **ORPHANED (backend-only table) / feature DEAD.**
- **`PaymentSetupScreen` is dead code** — defined in `payment_setup.dart`, **not imported in `main.dart`**, never routed or pushed. **DEAD CODE.**
- **7 tables are undocumented** (queried in code, absent from `supabase_schema.sql`): `settings`, `streaks`, `member_daily_stats`, `library_closures`, `leads`, `verification_requests`, `draft_members`.

A **correction to a prior-doc claim**: Phase-0 inherited a claim that "PDF export writes `.txt`." **Code contradicts this** — `pdf_exporter.dart` and `export_center.dart` use the real `pdf`/`printing` packages (`pw.Document()`, `Printing.sharePdf`). PDF export is **COMPLETE** (subject to render verification in Phase 8). This is exactly why we verify against code.

**Feature Completion Scorecard (40 features): COMPLETE 22 · PARTIAL 8 · UI-ONLY/MOCKED 4 · ORPHANED/DEAD 3 · UNVERIFIED 3.** Details in §11.6.

---

## 2. What Was Reviewed
Route map (`main.dart`), all 64 public screen widgets (reachability), every `.from('<table>')` usage (25 schema tables + 7 undocumented), `.storage.from()` bucket calls, `.insert`/`.update` sites for create/manage parity, and the specific last-mile persistence of join/add-on/referral/notification/transfer flows.

## 3. Files Reviewed (key)
`main.dart`, `notifications_screen.dart` (full), `reservations/join_flow_screen.dart`, `reservations/requests_sub_tab.dart`, `widgets/seat_change_bottom_sheet.dart`, `member_home.dart` (request inserts), `core/member_analytics_service.dart` (badges/referrals/notifications), `utils/pdf_exporter.dart`, `export_center.dart`, `payment_setup.dart`, `verified_badge_screen.dart`, `member_explore_screen.dart` (leads), plus aggregate greps across all 88 lib files.

## 4. Screens Reviewed
Reachability computed for **all 64** public screen widgets. Behavioral spot-reads on the screens above. (Per-screen UX deep-dive is Phases 3–4/9.)

---

## 5. Findings

> Effort: Small (<1d) · Medium (1–5d) · Large (>5d). Critical/High mirrored to Cross-Phase Critical Findings (§13) and master report.

### P2-01 — Member notifications screen is a static placeholder (notifications never displayed)
- **Severity:** High
- **Category:** Missing Connection · Incomplete Feature
- **File/Lines:** `lib/screens/notifications_screen.dart:1-37` (entire file). Route `/member/notifications` → this widget (`main.dart:140`).
- **Excerpt:** `StatelessWidget` whose body is `Icon(Icons.notifications_none)` + `Text("You're all caught up!")`. No `.from('notifications')` anywhere in the file.
- **Counter-evidence (writes exist):** notifications are inserted at `join_flow_screen.dart:515`, `requests_sub_tab.dart:386`, `:1096`, `member_analytics_service.dart:692`.
- **Why it's a problem:** The system generates notifications (join request, payment confirm/reject, hold decisions, badges) into a table that the user-facing screen ignores. Combined with **no FCM** (Phase 0 P0-03), members have **no way to ever see any notification**.
- **How it fails in production:** Member is approved/rejected and never finds out in-app; opens "Notifications," always sees "all caught up," loses trust / files a support ticket.
- **Fix:** Implement the screen to query `notifications` for `currentUser`, mark-as-read, paginate; wire unread badge.
- **Effort:** Medium

### P2-02 — Referral reward loop incomplete (never credited, no membership extension)
- **Severity:** High
- **Category:** Incomplete Feature · Business Value
- **Evidence:** Insert at `join_flow_screen.dart:574`; reads/counts at `referral_settings.dart:63` (`status == 'credited' || 'rewarded'`) and `member_analytics_service.dart:702-710`. **No code writes** `status='credited'` or extends `memberships.end_date` for a referral. (Searched all `.update`/status writes.)
- **Why it's a problem:** The reward — the entire incentive — never fires. UI advertises "Rewards are authorized after 7 days / 5 check-ins" (`referral_settings.dart:238`) but nothing evaluates that condition.
- **How it fails in production:** Members refer friends, see "pending" forever, never get free days → broken promise, support tickets, churn.
- **Fix:** Server-side job/RPC (ties to P1-03) to evaluate referral conditions, set `credited`, extend membership; or interim client/admin action. Verify rule values in Phase 7.
- **Effort:** Large

### P2-03 — Add-ons sold in join flow but never persisted (orphan `member_add_ons`)
- **Severity:** High
- **Category:** Missing Connection · Data Loss
- **Evidence:** `join_flow_screen.dart:206-214` loads `add_ons`; `:439-441` sums selected add-on prices into the total; the `requestPayload` (`:546-558`) **omits add-ons entirely**; `member_add_ons` table has **0** `.from()` references.
- **Why it's a problem:** The member pays for a locker/premium add-on (it's in the total they're told to pay), but **which** add-ons were chosen is never stored. Admin cannot fulfill or reconcile.
- **How it fails in production:** Member pays for locker; admin has no record; dispute; manual WhatsApp reconciliation — defeating the product's core promise.
- **Fix:** Persist selected add-ons to `member_add_ons` on approval (or embed in payload); surface in admin member detail.
- **Effort:** Medium

### P2-04 — Member transfer feature absent despite table + spec
- **Severity:** Medium
- **Category:** Orphaned · Missing Admin Flow
- **Evidence:** `transfers` table in schema; **0** `.from('transfers')`; no "Transfer" UI action in any screen (grep). Documented in `07_Workflows.yaml` #6 and US row23.
- **Why it's a problem:** A P1-documented admin capability (consolidate members across own libraries) does not exist.
- **How it fails in production:** Multi-library admins cannot move members; data model implies a feature that isn't there.
- **Fix:** Build the transfer flow (admin member-detail → destination/shift/seat → write `transfers` + new membership) or formally de-scope and drop the table.
- **Effort:** Medium

### P2-05 — Dead code: `PaymentSetupScreen`
- **Severity:** Low
- **Category:** Dead Code
- **Evidence:** `payment_setup.dart` defines `PaymentSetupScreen`; **not imported** in `main.dart`; no route; no `PaymentSetupScreen(` call anywhere.
- **Why it's a problem:** Misleads readers into thinking payment setup exists; maintenance noise; the *actual* admin UPI setup lives elsewhere (`admin_profile_tab`).
- **Fix:** Delete the file or wire it if intended.
- **Effort:** Small

### P2-06 — Seven undocumented tables (UI exists, schema absent)
- **Severity:** High (data-integrity / environment reproducibility — escalated to Phase 5)
- **Category:** Missing Connection (UI→table) · Schema Drift
- **Evidence (code uses, `supabase_schema.sql` lacks):** `settings` (`admin_settings_service.dart`), `streaks` & `member_daily_stats` (`member_analytics_service.dart`), `library_closures` (`admin_home.dart`), `leads` (`member_explore_screen.dart:323`), `verification_requests` (`verified_badge_screen.dart:176`), `draft_members` (has its own `draft_members.sql` only).
- **Why it's a problem:** A fresh environment built from the canonical schema would crash these features. `verification_requests` has **no migration at all**.
- **How it fails in production:** Verified-badge requests, settings, streak analytics, closures, and explore-lead capture break on any clean deploy.
- **Fix:** Reconcile into one migration set (Phase 5 owns the table-by-table reconciliation).
- **Effort:** Medium

### P2-07 — Duplicate `library_closures` vs `scheduled_closures` (two closure tables)
- **Severity:** Medium
- **Category:** Missing Connection · Schema Drift
- **Evidence:** Code uses both `scheduled_closures` (8 refs, in schema) and `library_closures` (1 ref `admin_home.dart`, **not** in schema). Likely two implementations of the same concept.
- **Why it's a problem:** Closure data may split across two tables → streak-freeze / scanner-block logic reads the wrong one.
- **Fix:** Consolidate to one table; verify scanner & streak logic in Phase 7.
- **Effort:** Small

### P2-08 — Notifications written but several are dead-ends without a reader
- **Severity:** Medium (compound of P2-01 + P0-03)
- **Category:** API/data exists but not consumed
- **Evidence:** 4 insert sites populate `notifications`; only consumers are analytics service internals — **no list UI** reads them (P2-01).
- **Fix:** Covered by P2-01 (build reader). Track here for the data-flow graph.
- **Effort:** (see P2-01)

---

## 6. Missing Connection Analysis (as requested, by pattern)

| Pattern | Instance | Evidence | Verdict |
|---|---|---|---|
| Table exists, UI absent | `transfers` | 0 code refs | ORPHANED (P2-04) |
| Table exists, UI absent | `member_add_ons` | 0 code refs; add-ons not saved | ORPHANED (P2-03) |
| UI/code exists, table absent | `settings`,`streaks`,`member_daily_stats`,`library_closures`,`leads`,`verification_requests`,`draft_members` | used in code, not in schema | DRIFT (P2-06) |
| API/data written, never read | `notifications` (insert ×4, no list reader) | `notifications_screen.dart` static | MISSING READER (P2-01) |
| Member creates, admin can't fully manage | Add-ons (member pays, admin has no record) | payload omits add-ons | BROKEN LOOP (P2-03) |
| Admin configures, member never benefits | Referral rewards (configured, never credited) | no `credited` write | BROKEN LOOP (P2-02) |
| Screen with no entry point | `PaymentSetupScreen` | not imported/routed | DEAD (P2-05) |
| Button with no meaningful outcome | "Verify Phone/Email" (mock `123456`) | `member_profile_edit.dart:480` | MOCKED (P0-04) |
| Feature with no business value yet | Notifications screen (always "caught up") | static placeholder | UI-ONLY (P2-01) |
| Navigation path missing | Member in-app notifications unreachable as real data | route exists, content fake | MISSING (P2-01) |

**Healthy loops confirmed (positive findings):**
- **Seat-change request:** member creates (`seat_change_bottom_sheet.dart:108` insert) → admin manages (`requests_sub_tab.dart:125,458`). ✅ COMPLETE parity.
- **Hold request:** member creates (`member_home.dart:4920` insert) → admin approves/updates (`requests_sub_tab.dart:1065,1091`). ✅ COMPLETE parity (enforcement of limits = Phase 7).
- **Reviews:** member writes (`library_public_profile_screen`, `past_library_detail_screen`) → admin views/replies (`admin/all_reviews_screen.dart`, `reply_to_review_bottom_sheet.dart`). ✅ COMPLETE parity.
- **Queries/support:** member submits (`member_help_support_screen`, `library_query_screen`) → admin manages (`admin_home.dart`). ✅ COMPLETE parity.
- **Join request:** member submits (`join_flow_screen`) → admin approve/reject + audit + notify (`requests_sub_tab.dart`). ✅ COMPLETE (add-on sub-gap noted).
- **Badges:** actually awarded (`member_analytics_service.dart:687` insert). ✅ COMPLETE (criteria correctness = Phase 8).

---

## 7. User Experience & User Simulation Findings (NEW — global requirement)

Per the User Simulation Requirement. **Limitation:** no emulator/device executed this phase → all rows **Code-Inferred** from implementation; runtime confirmation deferred to Phases 3/4/9/13. Simulated against the feature-mapping lens (discoverability, completion, dead-ends).

### Feature: In-app Notifications
| Persona | Sees (Code-Inferred) | Expects | Actually happens | Stuck? | Recover? |
|---|---|---|---|---|---|
| First-time user | "You're all caught up!" empty bell | a list of alerts | always empty regardless of events | No, but misled | N/A |
| Returning user (was approved) | same empty screen | "Approved!" notice | never shown → reopens app repeatedly | Effectively yes | Only via My-Library card |
| Bad internet | static screen (no fetch) | maybe a spinner | renders instantly (nothing to load) | No | N/A |
| User who made a mistake | n/a | n/a | n/a | — | — |
**Verdict:** UI-ONLY. High drop-off/trust risk. Friction 8/10.

### Feature: Referral
| Persona | Sees | Expects | Actually happens | Stuck? | Recover? |
|---|---|---|---|---|---|
| Power user (refers 5) | "Pending" counts | free days after friend stays 7d/5 check-ins | never credited | Yes (waiting forever) | No in-app path |
| Non-technical user | "Rewards authorized after 7 days…" copy | automatic reward | nothing | Yes | files ticket |
**Verdict:** PARTIAL (write-only). Friction 7/10 once a reward is "due."

### Feature: Add-ons at Join
| Persona | Sees | Expects | Actually happens | Stuck? | Recover? |
|---|---|---|---|---|---|
| First-time user | add-on checkboxes + price added to total | locker reserved after pay | selection lost; admin has no record | Not in-flow; later dispute | Manual contact |
| Frustrated user | paid more, got nothing | the add-on | unfulfilled | Post-pay | Support only |
**Verdict:** PARTIAL. Trust/refund risk. Friction 6/10.

### Feature: Transfer (multi-library admin)
| Persona | Sees | Expects | Actually happens | Stuck? |
|---|---|---|---|---|
| Power admin | no Transfer option anywhere | move member between own libraries | feature absent | Yes (must exit+rejoin) |
**Verdict:** ORPHANED. Friction N/A (invisible) but capability gap.

*(Full multi-persona matrices for primary journeys are produced in Phases 3–4 per the global rule; this phase covers the connectivity-relevant subset.)*

---

## 8. Incomplete Features (consolidated this phase)
Notifications reader (UI-only), Referral crediting (write-only), Add-on persistence (partial), Transfer (absent), Verified-badge backend table (no migration), OTP verify (mock, P0-04), Payments (mock, P0-01), FCM (absent, P0-03).

## 9. Improvement Suggestions
1. Close the **last-mile loops** before adding features: notifications reader, referral crediting, add-on persistence — these are *broken promises*, the worst UX category.
2. Delete or wire **dead/orphan** artifacts (`PaymentSetupScreen`, `transfers`, `member_add_ons`) to reduce false surface area.
3. Reconcile the **7 undocumented tables** (Phase 5) so clean deploys don't silently break features.
4. Decide closure-table canonical source (`scheduled_closures` vs `library_closures`).

## 10. Priority Fix List (Phase 2)
| # | Item | Severity | Effort |
|---|---|---|---|
| 1 | Build real notifications reader (P2-01) | High | Medium |
| 2 | Implement referral crediting + extension (P2-02) | High | Large |
| 3 | Persist add-ons & surface to admin (P2-03) | High | Medium |
| 4 | Reconcile 7 undocumented tables (P2-06) | High | Medium |
| 5 | Consolidate closure tables (P2-07) | Medium | Small |
| 6 | Build or de-scope transfer (P2-04) | Medium | Medium |
| 7 | Remove `PaymentSetupScreen` dead code (P2-05) | Low | Small |

---

## 11. Required Artifacts

### 11.1 Feature Dependency Graph (text)
```
AUTH ─► role(users) ─┬─► ADMIN ─► library(libraries) ─► setup{floors,sections,seats,shifts}
                     │                                   │
                     │             ┌─────────────────────┼──────────────────────────┐
                     │             ▼                     ▼                          ▼
                     │     dashboard(memberships,   join approval(join_requests   settings(settings⚠undoc)
                     │     attendance,payments,     →memberships,seats,audit_log, business_rules→libraries
                     │     seats; realtime joins)   notifications✚)               pricing(shifts)
                     │             │                     │                          │
                     │             ▼                     ▼                          ▼
                     │     analytics(attendance,    add-ons(add_ons READ only;   referrals(referrals
                     │     expenditures; streaks⚠,  member_add_ons✗ORPHAN)        write-only; credit✗)
                     │     member_daily_stats⚠)     reviews◄►(reviews)            closures(scheduled_closures
                     │             │                queries◄►(queries)            + library_closures⚠dup)
                     │             ▼                                              verified(verification_requests⚠
                     │     exports(CSV+PDF real)    transfers✗ORPHAN              no-migration)
                     │
                     └─► MEMBER ─► explore(libraries; leads⚠insert) ─► join_flow ─► membership
                                   │                                                  │
                                   ▼                                                  ▼
                          membership card(memberships) ─┬─ QR(attendance + offline_scan_queue)
                          renewal(memberships,payments) ├─ seat-change◄►(seat_change_requests)
                          hold◄►(hold_requests)         ├─ exit(memberships)
                          analytics(streaks⚠,badges✚)   └─ notifications(route→PLACEHOLDER✗)
Legend: ◄► full two-way loop · ✚ written · ✗ broken/absent · ⚠ undocumented/duplicate table
```

### 11.2 Orphan Feature Register
| Item | Type | Evidence | Verdict |
|---|---|---|---|
| `transfers` table | Backend-only | 0 code refs; no UI | ORPHANED |
| `member_add_ons` table | Backend-only | 0 code refs | ORPHANED |
| Member transfer feature | Capability | no entry point | ORPHANED/DEAD |

### 11.3 Dead Code Register
| Item | File | Evidence | Action |
|---|---|---|---|
| `PaymentSetupScreen` | `payment_setup.dart` | not imported in `main.dart`; 0 external refs | Delete/Wire |
| (watch) `leads` write w/o reader | `member_explore_screen.dart:323` | insert-only, no admin view | Verify Phase 4 |

### 11.4 Mocked Feature Register
| Feature | Evidence | Status |
|---|---|---|
| In-app notifications screen | `notifications_screen.dart` static | MOCKED/UI-ONLY |
| OTP phone/email verify | `member_profile_edit.dart:480` `123456` | MOCKED |
| Payments (member + subscription) | `subscription_screen.dart:277` `Future.delayed` | MOCKED |
| Push (FCM) | no firebase dep | ABSENT |

### 11.5 User Friction Register (initial — cumulative in master)
| Feature | Friction (0–10) | Top sources | Drop-off / Rage-click risk |
|---|---|---|---|
| In-app Notifications | 8 | Always-empty, misleading, no real data | High drop-off; repeat-open rage |
| Referral | 7 | Reward never arrives; false promise copy | Churn; support tickets |
| Add-ons at Join | 6 | Paid, not fulfilled/recorded | Refund disputes |
| Transfer (admin) | n/a (invisible) | Capability missing | Workaround burden |
| Verify Phone/Email | 5 | Mock; meaningless badge | Confusion |
*(All Code-Inferred; runtime confirmation in Phases 3/4/9/13.)*

### 11.6 Feature Completion Scorecard (40 features)
**COMPLETE (22):** role selection; admin profile; library setup S1–S3; dashboard stats; join approval; payment confirm (cash/UPI proof flow as workflow, money mocked); manual check-in; seat reassign/maintenance; renewal; announcements; queries (both sides); reviews (both sides); seat-change request loop; hold request loop; scheduled closures; CSV export; **PDF export (real)**; audit log (written+read); explore/discover; QR check-in/out + offline queue; badges (awarded); membership card.
**PARTIALLY COMPLETE (8):** referrals (write-only); add-ons (no persistence); subscription/billing (mock pay); discounts (enforcement TBD Phase 7); auto-checkout/auto-hold (system logic TBD Phase 7); streak-freeze (TBD Phase 7); duplicate-phone prevention (TBD Phase 7); exit-dues block (TBD Phase 7).
**UI-ONLY / MOCKED (4):** in-app notifications screen; OTP verify; payment checkout; FCM (absent).
**ORPHANED / DEAD (3):** transfers (table+feature); member_add_ons (table); PaymentSetupScreen (dead file).
**UNVERIFIED (3):** leads capture purpose; verification_requests end-to-end (no schema); library_closures vs scheduled_closures canonical.

*Score: 22 / 8 / 4 / 3 / 3.*

---

## 12. Classification Summary (per mandatory output)
| Feature | Classification |
|---|---|
| Notifications (in-app) | UI-ONLY |
| Referral reward | PARTIALLY COMPLETE (backend-write only) |
| Add-ons | PARTIALLY COMPLETE |
| Transfer | ORPHANED |
| PaymentSetupScreen | DEAD CODE |
| Payments / Subscription | MOCKED |
| OTP verify | MOCKED |
| PDF export | COMPLETE (render-verify Phase 8) |
| Seat-change / Hold / Reviews / Queries | COMPLETE |
| Join + approval | COMPLETE (add-on sub-gap) |
| Streak-freeze / auto-checkout / discounts enforcement | UNVERIFIED → Phase 7 |

---

## 13. Cross-Phase Critical Findings (additions this phase)
| Ref | Sev | Title | Evidence | Effort |
|---|---|---|---|---|
| P2-01 | High | Member notifications screen is static placeholder; table never read | `notifications_screen.dart:1-37`; writes at 4 sites | Medium |
| P2-02 | High | Referral reward never credited / no membership extension | no `credited` write; `join_flow:574` insert only | Large |
| P2-03 | High | Add-ons sold but not persisted (orphan `member_add_ons`) | `join_flow:439-558`; payload omits add-ons | Medium |
| P2-06 | High | 7 undocumented tables; `verification_requests` has no migration | code-vs-schema grep | Medium |

## 14. Open Questions (additions)
12. Is `leads` (explore insert) a real lead-capture feature or experimental? No reader found. → Phase 4.
13. Was add-on persistence meant to happen on *approval* (admin side) rather than join? → Phase 4 check `requests_sub_tab` approval path.
14. Which closure table is canonical (`scheduled_closures` vs `library_closures`)? → Phase 5/7.
15. Is `transfers` planned for V1 or deferred? (US row23 = P1.) → product decision.

## 15. Verification Pending (additions)
| VID | Item | Method | Phase |
|---|---|---|---|
| V-15 | Notifications screen behavior on device | Emulator run | 3,9 |
| V-16 | Referral credit truly never fires (confirm no trigger/RPC) | Live DB trigger search | 5,7 |
| V-17 | Add-on approval-path persistence | Read approval code path | 4 |
| V-18 | PDF export renders valid binary on device | Run export | 8 |

---

*End of Phase 2. No code modified. Stopped; awaiting approval for Phase 3.*
