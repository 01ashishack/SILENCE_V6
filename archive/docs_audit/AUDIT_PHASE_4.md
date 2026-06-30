# SILENCE — Phase 4: Admin Flow Audit

**Phase:** 4 of 16 — Admin (Library Owner) Flow Audit
**Completed (local time):** 2026-06-08
**Auditor roles:** Senior PM (lead) · Full-Stack Engineer · QA Lead · UX Designer · Data Analyst
**Focus:** Admin actions are audited *with their member-side outcome* — every action checked for: can-perform · persisted · member receives outcome · member experience updated · dashboard reflects reality · reversible · auditable · failure-recovery.
**Runtime classification:** No emulator executed. All behavior **Code-Inferred** from full reads + schema cross-check. The schema-mismatch findings are verified against `supabase_schema.sql` directly (high confidence).
**Constraint honored:** No application code modified.

> ⚠️ **This phase produced two Phase-2 corrections.** Deep verification revealed that `audit_log` (marked COMPLETE in Phase 2 on the basis of insert/read *sites* existing) is in fact **broken on both ends** (P4-02), and several "notification written" loops are **broken at the column level** (P4-06). This is exactly the kind of false-positive that only end-to-end verification catches.

---

## 1. Executive Summary

The admin side is **feature-rich and the screens exist**, but auditing each action *through to the member outcome* reveals that **many admin actions either don't persist, persist incorrectly, or never reach the member — while telling the admin they succeeded.** The dashboard and audit trail therefore present a picture that diverges from reality.

**Resolved special investigation (UPI):**
- **The admin DOES configure a real UPI** — stored in `libraries.social_links.upi_ids` (`library_setup_stage3.dart:357`).
- **The admin is told it worked** — `admin_home.dart:426-433` reads it back and sets `isPaymentConfigured = true` / `_step4Complete = true`, showing a green "configured" state.
- **But the member payment screens never read it** — `join_flow_screen.dart` and `renewal_screen.dart` contain **zero** references to `upi_ids`/`social_links`; they hardcode `owner@upi` / `9876543210@paytm`.
- **Verdict: this is a WIRING BUG, not an intentional mock and not a data problem.** The data flows admin→DB correctly; only the member-side consumption is hardcoded. **An admin absolutely can — and will — believe payments are configured when members are shown a placeholder.** (Confirms & root-causes Critical P3-01.)

**Other headline findings (all newly verified this phase):**
- **🔴 P4-02 (Critical) — The audit trail is fake.** The primary `_logAudit` (`requests_sub_tab.dart:361-378`) inserts columns that don't exist (`performer_name, category, action_title, action_details`) and omits NOT NULL `admin_id`/`action` → **every insert throws and is swallowed**. The audit *reader* (`audit_log_screen.dart:58-61`) reads those same non-existent columns → renders **generic placeholder text** ("System Admin / Updated Settings / Modified metadata rules"). The one correctly-written audit row (`join_flow_screen.dart:498`) would still display as generic because the reader looks for the wrong columns. **No admin action produces a viewable, accurate audit entry.**
- **🔴 P4-03 (Critical for revenue) — Approved-membership payment amounts are fabricated.** Join approval hardcodes `amount = 1500 / 4000 / 7500` ("generic pricing", `requests_sub_tab.dart:328`), ignoring the shift's real configured price **and any discount**. Every payment created via the approvals path stores a fictional amount → revenue dashboards/exports are wrong (major Phase-8 input). Inconsistent with the Add-Member wizard, which uses the real `finalPrice` (`add_member_wizard.dart:462`).
- **🟠 P4-04 (High) — "Close Today" doesn't close anything.** It writes to `library_closures` (`admin_home.dart:3503`) — a table **not in the schema** (P2-06) and **never read by the scanner** (which checks `scheduled_closures`, `qr_scanner_screen.dart:284`). Admin sees "🔒 Library marked as closed for today. Members notified." — **both claims false**: scanner still admits members; no notification is written. (Scheduled/future closures *do* work — they use the right table.)
- **🟠 P4-05 (High) — Join approval is silent to the member.** Approval writes membership + seat + payment but **no notification and no audit** (`requests_sub_tab.dart:234-356`). Combined with the broken notification inserts (P4-06) and placeholder notifications screen (P3-05), the member learns of approval only by chance.
- **🟠 P4-06 (High) — "Member notified" is false in seat-change & hold paths.** Those `notifications` inserts use non-existent `is_read`/`created_at` columns (`requests_sub_tab.dart:392-394`, `:1099-1100`) → throw → swallowed.
- **🟠 P4-07 (High) — "Confirm Pay" persists nothing.** `_confirmPayment` (`requests_sub_tab.dart:154-160`) only adds to an in-memory `Set` and shows "Payment confirmed! ✓"; no DB write. State is lost on app restart.
- **🟠 P4-08 (High) — Seat/membership desync.** "Release", "Maintenance/Hold on occupied", and "Delete" mutate `seats` without touching `memberships` (`layout_sub_tab.dart:393-434, 526-553`), leaving stale `seat_id`/`status`. **"Reassign Seat" is a no-op** — it just navigates to the setup screen (`layout_sub_tab.dart:654`).
- **🟠 P4-09 (High) — Force-exit ignores dues.** `_forceExitMember` (`member_detail_screen.dart:478-555`) exits a member regardless of unpaid dues — contradicting the member-side dues block (P3) — with no notification, no audit.

**Admin journey friction:** of the audited admin journeys, **5 are high-risk operational failures** (config/closure/audit/approval-silence/payment-amount), each capable of making an owner mis-run their library while believing all is well.

---

## 2. What Was Reviewed
Every mandated admin area, traced to member outcome: library creation & 3-stage setup, UPI/payment setup, join approval + payment confirm/reject, manual member creation (5-step wizard), seat allocation/maintenance/reassign/release/delete, manual check-in & attendance edit, holds & seat-change handling, scheduled closures & "Close Today", announcements, queries, reviews, referrals, add-ons, exports, analytics inputs, settings, and the verification workflow. Schema cross-checked for every write.

## 3. Files Reviewed
`requests_sub_tab.dart`, `member_detail_screen.dart`, `layout_sub_tab.dart` (full, via subagent), `admin_home.dart`, `admin_profile_tab.dart`, `library_setup_stage2.dart`, `library_setup_stage3.dart`, `scheduled_closures.dart`, `export_center.dart`, `verified_badge_screen.dart`, `admin/add_member_wizard.dart` + steps, plus `supabase_schema.sql` (notifications, audit_log, payments, seats) and member consumers (`member_home.dart`, `notifications_screen.dart`).

## 4. Screens Reviewed
Admin Home/Dashboard, Library Setup S1–S3, Reservations (Requests/Members/Layout/Archive sub-tabs), Member Detail, Add-Member Wizard (5 steps), Scheduled Closures, Announcements (composer + history), Export Center, Verified Badge, Subscription, Profile/Settings cluster.

---

## 5. Findings

> Effort: Small/Medium/Large. Critical/High mirrored to Cross-Phase Critical Findings (§13) + master report.

### P4-01 — UPI consumption wiring bug + false admin confidence 🔴 Critical
- **Category:** Payments · Configuration · Broken Promise (root cause of P3-01)
- **Evidence:** admin writes `social_links.upi_ids` (`library_setup_stage3.dart:355-358`); admin home reads it → `isPaymentConfigured=true` (`admin_home.dart:426-433`); member screens hardcode UPI and never read `upi_ids` (`join_flow_screen.dart:1295`, `renewal_screen.dart:528`; grep: 0 `upi_ids` in either).
- **Member outcome:** member pays a placeholder; admin can't reconcile; admin believes setup is complete.
- **Fix:** member payment screens must load `social_links.upi_ids` for the target library; show per-library UPI; block UPI if none.
- **Effort:** Small · **Release-blocking**

### P4-02 — Audit log broken on both write and read (audit trail is fiction) 🔴 Critical
- **Category:** Auditability · Data Integrity · **Corrects Phase 2**
- **Evidence (write):** `requests_sub_tab.dart:368-374` inserts `performer_name, category, action_title, action_details, created_at`. Schema `audit_log` = `admin_id (NOT NULL), library_id, action (NOT NULL), details, previous_value, new_value, ip_address, created_at` (`supabase_schema.sql:348-358`). → NOT-NULL violation + unknown columns → throws → swallowed (`:376`).
- **Evidence (read):** `audit_log_screen.dart:58-61` reads `performer_name/category/action_title/action_details` (non-existent) → falls back to hardcoded defaults "System Admin / Updated Settings / Modified metadata rules" (`:60-61`).
- **Evidence (the one valid writer):** `join_flow_screen.dart:498-512` uses correct columns, but the reader still won't display it correctly.
- **Member/admin outcome:** the Audit Log screen shows fabricated-looking generic rows or nothing; **no accountability** for approvals, discounts, exits, seat changes.
- **Fix:** align insert columns to schema (and supply `admin_id`/`action`); align reader to real columns; centralize a single audit helper.
- **Effort:** Medium

### P4-03 — Fabricated payment amounts on approval (revenue is wrong) 🔴 Critical (revenue)
- **Category:** Calculations · Data Accuracy (feeds Phase 8)
- **Evidence:** `requests_sub_tab.dart:328` `'amount': plan=='monthly'?1500:(plan=='3_month'?4000:7500) // generic pricing`. Ignores the shift's actual `price_*` and any discount. Contrast `add_member_wizard.dart:462` `'amount': finalPrice` (correct).
- **Member/admin outcome:** member's payment history shows wrong amount; admin revenue dashboard & CSV/PDF exports are fiction.
- **Fix:** compute amount from the chosen shift's plan price minus applied discount; unify with wizard logic.
- **Effort:** Small

### P4-04 — "Close Today" is a no-op with a false success message 🟠 High
- **Category:** Operational Failure · Misleading UI
- **Evidence:** writes `library_closures` (`admin_home.dart:3503`; not in schema, P2-06); scanner reads only `scheduled_closures` (`qr_scanner_screen.dart:284`; 0 refs to `library_closures`); SnackBar claims "closed for today. Members notified" with no notification write.
- **Member/admin outcome:** library appears closed to the admin, stays open to members; streak-freeze (Phase 7) won't trigger.
- **Fix:** write the same table the scanner reads (`scheduled_closures`) with today's date; write notifications; reconcile tables (P2-07).
- **Effort:** Small

### P4-05 — Join approval doesn't notify or audit the member 🟠 High
- **Category:** Admin→Member Outcome · Auditability
- **Evidence:** `_approveJoinRequestTransaction` (`requests_sub_tab.dart:234-356`) writes seat/join_request/membership/payment but **no** `notifications`, **no** `audit_log`.
- **Member outcome:** approved member gets no signal (and the notification screen is a placeholder anyway, P3-05).
- **Fix:** write a schema-valid notification + audit row on approval/reject.
- **Effort:** Small

### P4-06 — Seat-change & hold notifications use invalid columns 🟠 High
- **Category:** Admin→Member Outcome · Silent Failure
- **Evidence:** `requests_sub_tab.dart:392-394` (`is_read`,`created_at`) and `:1099-1100` (`created_at`) — neither column exists (`notifications` has `read_at`,`sent_at`). Inserts throw; seat-change wrapped in `catch→debugPrint` (`:397`), hold insert has no local catch.
- **Fix:** use `title/body/data` (+ optional `read_at` null); add error surfacing.
- **Effort:** Small

### P4-07 — "Confirm Payment" persists nothing 🟠 High
- **Category:** Misleading UI · Data Loss
- **Evidence:** `_confirmPayment` (`requests_sub_tab.dart:154-160`) → in-memory `Set _confirmedPaymentsInUi` + SnackBar "Payment confirmed! ✓"; no DB write. The real `payments` row is created later at approval (`:324`).
- **Admin outcome:** if the app is restarted before approval, the confirmation is lost; admin re-does it. The "confirmed" state is not durable or auditable.
- **Fix:** persist a payment/verification state or fold confirmation into the approval transaction with clear copy.
- **Effort:** Medium

### P4-08 — Seat operations desync from memberships; "Reassign" is a no-op 🟠 High
- **Category:** Data Integrity · Misleading UI
- **Evidence:** `layout_sub_tab.dart` has 0 `memberships` writes; `_releaseSeatVacancy:393-413` and `_markSeatStatus:415-434` mutate only `seats`; `_deleteSeat:526-553` hard-deletes without occupancy check; **"Reassign Seat" `:654` only `Navigator.pushNamed('/admin/library/setup/2')`**.
- **Member outcome:** member keeps `active` membership pointing at a seat that's now vacant/maintenance/deleted → card shows stale/incorrect seat; no notification.
- **Fix:** every seat mutation must update the affected `memberships` row + notify; implement real reassign (pick vacant seat in same shift, free old, set `seat_id`); guard delete against occupancy.
- **Effort:** Medium

### P4-09 — Force-exit ignores dues 🟠 High
- **Category:** Business Rule · Consistency
- **Evidence:** `_forceExitMember` (`member_detail_screen.dart:478-555`) sets membership `exited`, frees seat; no `_isFeePending` check; no notification/audit. Member-side exit blocks on dues (P3) — admin path doesn't.
- **Fix:** apply the same dues policy (or require explicit override + audit).
- **Effort:** Small

### P4-10 — No reject path for seat-change or hold requests 🟡 Medium
- **Evidence:** `requests_sub_tab.dart:1018-1037` (seat-change) and `:1062-1118` (hold) render Approve-only; no reject handler.
- **Member outcome:** a request the admin doesn't want to grant sits "pending" forever; member can't get a "no."
- **Fix:** add reject + reason + notification.
- **Effort:** Small

### P4-11 — Hold approval: no guard → cumulative expiry extension; no feedback 🟡 Medium
- **Evidence:** `requests_sub_tab.dart:1080-1088` extends `end_date` by hold days; button not disabled; no success SnackBar/spinner. Repeated taps extend repeatedly.
- **Fix:** disable while processing; idempotency; success feedback.
- **Effort:** Small

### P4-12 — Manual check-in tagged inconsistently 🟡 Medium
- **Evidence:** layout path `session_type:'manual'` no reason (`layout_sub_tab.dart:378`); member-detail path `session_type:'admin_edited'` reason required (`member_detail_screen.dart:432-433`). Analytics filtering on one value misses the other.
- **Fix:** standardize session_type taxonomy; require reason consistently.
- **Effort:** Small

### P4-13 — Manually-added members can't access the app (no auth account) 🟡 Medium
- **Evidence:** `add_member_wizard.dart:357-367` inserts a `users` row (no Supabase Auth user). Such a member has profile+membership+seat but no credentials; QR/check-in needs `auth.currentUser==member_id`.
- **Outcome:** likely intended as "offline member tracking," but there is **no claim/link flow** if that member later wants the app; a self-signup creates a *different* uid → duplicate.
- **Fix:** document the offline-member model; add a phone-based claim/link flow (ties to duplicate-phone prevention, Phase 7).
- **Effort:** Medium

**Positive findings (verified working):**
- **Scheduled (future) closures work end-to-end** — written to and read from `scheduled_closures` (`scheduled_closures.dart:65,106`; scanner `:284`).
- **Announcements loop works** — admin insert (`admin_home.dart:3148`) → member read (`member_home.dart:301`) + history (`announcements_history_screen.dart:52`).
- **Exports are real** — `_generatePdfReport` + `Printing.sharePdf` (`export_center.dart:106-109`), CSV path, with "No data available" empty state (`:310`).
- **Seat-change *approval* is correct** — frees old seat, occupies new, updates `memberships.seat_id` (`requests_sub_tab.dart:442-456`) (only its notification/audit are broken).
- **Add-Member wizard uses real price** (`finalPrice`, `:462`) and guards duplicate active memberships (`:470`).
- **Library setup S1–S3 persists** library/floors/sections/seats/shifts correctly (spot-verified).

---

## 6. Admin → Member Outcome Verification (the 6 questions, per feature)

| Admin feature | Achieves goal? | Member benefits? | Member can see it? | Member can act? | Member can verify? |
|---|---|---|---|---|---|
| UPI/payment setup | ❌ not consumed (P4-01) | ❌ pays placeholder | shows fake UPI | pays wrong acct | ❌ |
| Join approval | ⚠️ membership/seat yes; amount wrong (P4-03) | ✅ becomes member | ❌ no notify (P4-05) | uses app | via card only |
| Payment confirm | ❌ no write (P4-07) | n/a | ❌ | n/a | ❌ |
| Seat reassign | ❌ no-op (P4-08) | ❌ | ❌ | ❌ | ❌ |
| Seat release/maint/delete | ⚠️ seat only; membership desync | ❌ stale seat | ❌ | ❌ | inconsistent card |
| Manual check-in | ✅ attendance row | ✅ counted | partially (history) | n/a | yes (history) |
| Force-exit | ✅ exits (ignores dues, P4-09) | ⚠️ removed | ❌ no notify | n/a | card changes |
| "Close Today" | ❌ no-op (P4-04) | ❌ not closed | ❌ false notify | n/a | ❌ |
| Scheduled closure | ✅ works | ✅ blocked correctly | partial | n/a | scanner msg |
| Announcement | ✅ works | ✅ | ✅ home feed | reads | ✅ |
| Hold approval | ⚠️ extends (cumulative bug) | ✅ paused | ❌ notify broken (P4-06) | n/a | card |
| Seat-change approval | ✅ reseats | ✅ | ❌ notify broken | n/a | card |
| Discount | ⚠️ not enforced (Phase 7) | ? | on card (Phase 3) | n/a | ? |
| Audit log | ❌ broken both ends (P4-02) | n/a (admin) | n/a | n/a | ❌ |
| Exports/Analytics | ⚠️ real files but wrong amounts (P4-03) | n/a | n/a | n/a | n/a |

---

## 7. User Simulation — Admin Personas (Code-Inferred)

| Persona | Key experience | Friction | Trust | Support burden | Op-failure risk |
|---|---|---|---|---|---|
| First-time admin | Setup completes; "payment configured ✓" — but members pay placeholder | 7 | **2** | High | **High** |
| Non-technical owner | Believes audit log, "Close Today", "Confirm Pay" all work; none do | 8 | **1** | Severe | **Severe** |
| Busy owner | Approves fast (no double-submit guards); silent member outcomes → more queries | 6 | 3 | High | High |
| Multi-library owner | No transfer (P2-04); per-library UPI not shown to members | 7 | 2 | High | Med |
| Owner recovering from mistake | No undo on approve/exit/delete; no real audit to trace | 8 | 2 | High | High |
| Poor-network admin | Approvals throw on flaky net; swallowed errors; "Confirm Pay" lost on restart | 7 | 3 | Med | High |

**Trust scores are low because the app reports success it didn't achieve** — the most corrosive pattern for an operational tool.

---

## 8. Required Artifacts

### 8.1 Admin Journey Map (⚠ = breaks; ✓ = works)
```
ONBOARD  signup→role(admin)✓ → profile✓ → Library Setup S1(details)✓
SETUP    S2(floors/sections/seats)✓ → S3(shifts/pricing/UPI→social_links.upi_ids)✓
         → admin_home reads back → "Payment configured ✓"✓  [but members never read it ⚠P4-01]
LAUNCH   dashboard (occupancy/revenue) — revenue skewed by hardcoded amounts ⚠P4-03
JOINS    Requests tab → "Confirm Pay"(no write⚠P4-07) → Approve(seat+membership+payment)✓
         → member NOT notified/audited ⚠P4-05
ADD MEMBER wizard 5 steps → users(no auth⚠P4-13)+membership+payment(finalPrice✓)
ROSTER   Member Detail → manual check-in(reason✓) / payment confirm/reject(no audit)
         → Force-Exit(ignores dues⚠P4-09, no notify)
SEATS    Layout → Reassign(NO-OP⚠P4-08) / Release・Maintenance・Delete(desync⚠P4-08)
REQUESTS Hold approve(cumulative bug⚠P4-11, notify broken⚠P4-06, no reject⚠P4-10)
         Seat-change approve(reseat✓; notify broken⚠P4-06; no reject⚠P4-10)
CLOSURES Scheduled(works✓) | "Close Today"(NO-OP + false notify⚠P4-04)
COMMS    Announcement(works✓→member feed) | Queries(works✓) | Reviews reply(works✓)
TRUST    Verified badge → verification_requests insert; no in-app approval consumer (external)
SETTINGS business rules/pricing/referrals saved (enforcement→Phase 7)
RECORDS  Audit Log(BROKEN both ends⚠P4-02) | Exports(real files, wrong amounts⚠P4-03)
```

### 8.2 Admin Friction Register
| Journey | Friction (0–10) | Trust | Support burden | Op-failure risk |
|---|---|---|---|---|
| UPI/payment setup | 7 | 2 | High | High |
| "Close Today" | 8 | 1 | High | High |
| Audit log | 8 | 1 | Med | High (compliance) |
| Join approval (silent + amount) | 7 | 2 | High | High |
| Seat management | 7 | 2 | High | High |
| "Confirm Pay" | 6 | 2 | Med | Med |
| Hold/seat-change handling | 6 | 3 | Med | Med |
| Force-exit | 5 | 3 | Med | Med |
| Scheduled closures | 2 | 7 | Low | Low |
| Announcements | 2 | 7 | Low | Low |
| Exports | 4 | 5 | Low | Med (wrong $) |

### 8.3 Admin-to-Member Outcome Matrix — see §6.

### 8.4 Operational Failure Register
| OFID | Failure | Admin believes | Reality | Evidence |
|---|---|---|---|---|
| OF-01 | Members pay placeholder UPI | "Payments configured" | wrong/none account | P4-01 |
| OF-02 | "Close Today" | "Library closed, members notified" | open; no notify | P4-04 |
| OF-03 | Audit log | "All actions tracked" | nothing persisted/displayed | P4-02 |
| OF-04 | Approval notifications | "Member notified" | no/failed notify | P4-05,06 |
| OF-05 | "Confirm Pay" | "Payment confirmed" | no DB write | P4-07 |
| OF-06 | Reassign seat | "Seat reassigned" | navigates only | P4-08 |
| OF-07 | Seat release/maintenance | "Seat updated" | membership desynced | P4-08 |
| OF-08 | Revenue dashboard/exports | "₹X collected" | fabricated amounts | P4-03 |
| OF-09 | Force-exit | "Member exited cleanly" | dues ignored, no audit | P4-09 |

### 8.5 Configuration Risk Register
| CRID | Config | Risk | Evidence |
|---|---|---|---|
| CR-01 | UPI ids stored but unconsumed | members can't pay correctly; false "configured" | P4-01 |
| CR-02 | Two closure tables | "Close Today" hits dead table | P4-04, P2-07 |
| CR-03 | Pricing in shifts not used at approval | revenue wrong | P4-03 |
| CR-04 | Business rules saved, not enforced | discounts/holds/dues unenforced (Phase 7) | P0-07/Phase7 |
| CR-05 | Verification requests with no approval consumer | badge only settable out-of-band | §5 |
| CR-06 | `library_closures`, `settings`, etc. undocumented | clean deploy breaks (P2-06) | P2-06 |

---

## 9. Phase-2 Corrections (issued this phase)
- **`audit_log`: COMPLETE → BROKEN** (P4-02). Insert sites exist but write invalid columns; reader reads invalid columns.
- **Notifications loop: "written" → "write fails in seat-change/hold paths"** (P4-06). Only the join_flow owner-notification uses valid columns.
- **"Close Today": implied working → NO-OP** (P4-04). (Scheduled closures remain COMPLETE.)

## 10. Improvement Suggestions
1. **Make success truthful** — no SnackBar should claim an outcome the code didn't persist (UPI, Close Today, Confirm Pay, notifications).
2. **One audit helper, schema-aligned, called by every mutating action** (approve, discount, exit, seat ops, closures).
3. **Compute money once** (shared pricing/discount function) used by approval + wizard + analytics.
4. **Every seat mutation updates the membership and notifies** the member.
5. **Reconcile closure tables and consume `upi_ids`** before any pilot.

## 11. Priority Fix List (Phase 4)
| # | Item | Severity | Effort |
|---|---|---|---|
| 1 | Consume `social_links.upi_ids` in member payment screens (P4-01) | Critical | Small |
| 2 | Fix payment amount at approval (real price−discount) (P4-03) | Critical | Small |
| 3 | Fix audit_log write+read (P4-02) | Critical | Medium |
| 4 | Make "Close Today" write the scanner's table + notify (P4-04) | High | Small |
| 5 | Notify+audit on approval; fix notification columns (P4-05/06) | High | Small |
| 6 | Persist payment confirmation (P4-07) | High | Medium |
| 7 | Seat ops update membership + real reassign (P4-08) | High | Medium |
| 8 | Force-exit dues policy (P4-09) | High | Small |
| 9 | Add reject paths + guards for hold/seat-change (P4-10/11) | Medium | Small |

---

## 12. Cross-Phase Critical Findings (additions this phase)
| Ref | Sev | Title | Evidence | Effort |
|---|---|---|---|---|
| P4-01 | **Critical** | UPI configured by admin but never consumed by member screens (false "configured") | `library_setup_stage3:357`, `admin_home:426`, `join_flow:1295` | Small |
| P4-02 | **Critical** | Audit log broken on write AND read (no real audit trail) | `requests_sub_tab:368` vs schema `:348`; `audit_log_screen:58-61` | Medium |
| P4-03 | **Critical** (revenue) | Approval hardcodes payment amount; ignores price+discount | `requests_sub_tab:328` | Small |
| P4-04 | High | "Close Today" writes dead table; scanner ignores; false notify | `admin_home:3503` vs `qr:284` | Small |
| P4-05 | High | Join approval doesn't notify/audit member | `requests_sub_tab:234-356` | Small |
| P4-06 | High | Seat-change/hold notifications use non-existent columns | `requests_sub_tab:392-394,1099-1100` | Small |
| P4-07 | High | "Confirm Pay" persists nothing | `requests_sub_tab:154-160` | Medium |
| P4-08 | High | Seat ops desync membership; "Reassign" is a no-op | `layout_sub_tab:393-434,526-553,654` | Medium |
| P4-09 | High | Force-exit ignores dues | `member_detail_screen:478-555` | Small |

## 13. Open Questions (resolved + new)
- **RESOLVED 16/17:** Admin UPI is stored real; members use placeholder → wiring bug; admin can be falsely confident (P4-01).
- **NEW 19:** Is the offline (no-auth) manually-added member intended, and is a claim/link flow planned? (P4-13)
- **NEW 20:** Are payment amounts meant to come from `shifts.price_*` minus discount? Confirm canonical pricing source for Phase 8. (P4-03)
- **NEW 21:** Who approves `verification_requests` (no in-app consumer)? Platform-owner tool? (CR-05)

## 14. Verification Pending (additions)
| VID | Item | Method | Phase |
|---|---|---|---|
| V-23 | Confirm audit_log insert actually throws at runtime (PostgREST error) | Device/integration run | 13 |
| V-24 | Confirm "Close Today" leaves scanner open | Device run | 13 |
| V-25 | Confirm approval notification absence on member device | Device run | 13 |
| V-26 | Revenue figure delta from hardcoded amounts | Phase 8 recompute | 8 |

---

*End of Phase 4. No code modified. Stopped; awaiting approval for Phase 5 (Database Audit).*
