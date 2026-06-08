# SILENCE — Phase 3: Member Flow Audit

**Phase:** 3 of 16 — Member (Student) Flow Audit
**Completed (local time):** 2026-06-08
**Auditor roles:** UX Designer (lead) · Senior Full-Stack Engineer · QA Lead · PM · Support-Ops analyst
**Mindset applied:** Reviewed as a *first-time student*, not a developer. Every behavioral claim carries `file:line`.
**Runtime classification:** No emulator/device was executed this phase. **All behavioral conclusions are `Code-Inferred`** from reading the implementation in full. Items needing a device are flagged for Phase 13. Where the code is unambiguous (hardcoded strings, missing handlers), confidence is high but still labeled Code-Inferred per the global rule.
**Constraint honored:** No application code modified.

---

## 1. Executive Summary

The member experience is **visually complete and, in the "happy path," largely coherent** — join, renewal, explore, history, logout, and password reset are wired with proper submit-guards, dup-checks, and empty/loading states. But reviewed as a real student, **the app makes several promises it does not keep, and two of them touch money and identity directly:**

- **🔴 P3-01 (Critical) — Members pay a FAKE/placeholder UPI account.** Both the join payment step and the renewal screen display **hardcoded** UPI IDs `owner@upi` / `9876543210@paytm` instead of the library owner's real UPI (`join_flow_screen.dart:1295`, `renewal_screen.dart:528`). A student following the on-screen instructions sends real money to a placeholder/none-of-the-admin's account, then uploads a screenshot the admin can never reconcile. This is the single most damaging member-facing defect found so far.
- **🟠 P3-02 (High) — "UPI deep-link payment apps" are fake.** The GPay/PhonePe/Paytm buttons only show a SnackBar `"Simulated deep link: Opening <app>..."` and launch nothing (`join_flow_screen.dart` `_buildPaymentAppButton`, `renewal_screen.dart:623`). A core advertised differentiator (India UPI deep-links) is a stub.
- **🟠 P3-03 (High) — Offline check-in fakes success for anyone.** The scanner's offline path (`qr_scanner_screen.dart:217-271`) performs **zero validation** — no membership, expiry, closure, seat, or duplicate check — and shows a green "Checked In Successfully" card to a non-member, expired member, or someone scanning a random library's QR.
- **🟠 P3-04 (High) — Expired-member check-in is a broken promise.** When an admin enables `allow_expired_checkin`, the home FAB appears (`member_home.dart:1017`), but the scanner hard-blocks every expired/on-hold member with the **misleading** message "Not a member here" (`qr_scanner_screen.dart:321-325`). The student is invited to scan, then told they don't belong.
- **🟠 P3-05 (High) — Notifications are unreachable.** The unread badge (`member_home.dart:1136`) links to a permanently empty placeholder (`notifications_screen.dart`; confirmed Phase 2 P2-01). A member is notified of nothing in-app.

Plus a cluster of **silent failures that bypass safety gates**: a failed closure-check lets a member check into a closed library (`qr:295-299`); a failed dues lookup lets a member exit despite owing money (`member_home.dart:5004-5008`).

**Member journey friction:** of 23 journeys, **6 are high-friction (score ≥7)**, **7 medium (4–6)**, **10 acceptable (≤3)**. Detailed registers in §8–§13.

---

## 2. What Was Reviewed
All 23 mandated member journeys, traced through: `member_home.dart` (5,384 ln, read in full via subagent), `reservations/qr_scanner_screen.dart` (1,374 ln, full), `reservations/join_flow_screen.dart`, `reservations/renewal_screen.dart`, `member_explore_screen.dart`, `member_profile_edit.dart`, `member_history_tab.dart`, `auth_screen.dart`, `member_profile_tab.dart`, plus the membership-card/hold/exit/seat-change paths.

## 3. Files Reviewed
`member_home.dart`, `qr_scanner_screen.dart`, `join_flow_screen.dart`, `renewal_screen.dart`, `member_explore_screen.dart`, `member_profile_edit.dart`, `member_history_tab.dart`, `auth_screen.dart`, `member_profile_tab.dart`, `widgets/seat_change_bottom_sheet.dart` (referenced).

## 4. Screens Reviewed
Member Home (9 states), QR Scanner, Join Flow (5 steps + confirmation), Renewal, Explore/Discovery, Library Public Profile (entry), Profile Edit (+OTP modal), History tab (payments/sessions/past libs + Reupload sheet), Auth (login/signup/forgot), Profile tab (logout). Notifications screen (placeholder).

---

## 5. Findings (member-facing)

> Effort: Small/Medium/Large. Critical/High mirrored to Cross-Phase Critical Findings (§14) + master report. All behavior **Code-Inferred**.

### P3-01 — Members pay a hardcoded placeholder UPI (money goes nowhere/wrong) 🔴 Critical
- **Category:** Payments · Broken Promise · Financial Loss
- **File/Lines:** `join_flow_screen.dart:1294-1296` and `renewal_screen.dart:527-529` — `SelectableText('owner@upi\n9876543210@paytm', …)` under a label "Admin UPI IDs."
- **Why it's a problem:** The value is a literal, not sourced from the library/owner record. The student is explicitly told these are "Admin UPI IDs" and instructed to pay them. There is no code path that substitutes the real owner UPI.
- **How it fails in production:** Student pays `9876543210@paytm` (a stranger or invalid handle), uploads a screenshot, waits "24 hours," and is rejected — money lost, no recourse in-app. Mass incidence: *every* UPI-paying member of *every* library.
- **Support/CX:** Floods of "I paid but got rejected / where did my money go" tickets; chargebacks; reputational damage.
- **Fix:** Render the owner's stored UPI ID(s) from the library/admin profile; block the UPI step if none configured.
- **Effort:** Small (wiring) — but **release-blocking**.

### P3-02 — UPI app deep-links are simulated stubs 🟠 High
- **Category:** Broken Promise · Payments UX
- **File/Lines:** `join_flow_screen.dart` `_buildPaymentAppButton` → `SnackBar('Simulated deep link: Opening $label app...')`; same in `renewal_screen.dart:622-623`.
- **Why it's a problem:** The brief's headline differentiator ("UPI deep-links: PhonePe, GPay, Paytm") does not exist; buttons imply an action that never happens.
- **How it fails in production:** Non-technical student taps "GPay," expects GPay to open pre-filled, nothing happens, gets confused, abandons or pays wrong.
- **Fix:** Implement real `upi://pay?pa=<vpa>&pn=<name>&am=<amt>` deep links via `url_launcher` (already a dependency); remove the simulation copy.
- **Effort:** Medium

### P3-03 — Offline check-in performs no validation; fakes success 🟠 High
- **Category:** Misleading UI · Data Integrity
- **File/Lines:** `qr_scanner_screen.dart:217-271` (offline branch) vs `:317-409` (online validation). Offline path writes to `offline_scan_queue` and shows the success card with **no** membership/expiry/closure/seat/duplicate checks.
- **Why it's a problem:** Student sees "Checked In Successfully ✓" while offline regardless of eligibility. On sync, `offline_sync.dart` discards invalid scans silently — so the attendance never actually records, but the student already saw success.
- **How it fails in production:** Expired/non-member students believe they checked in; attendance/streak silently wrong after sync; disputes ("the app said I was checked in").
- **Fix:** Validate against cached membership/closure data offline; show "saved, pending verification" rather than unqualified success.
- **Effort:** Medium

### P3-04 — Expired check-in: FAB invites, scanner rejects as "Not a member here" 🟠 High
- **Category:** Broken Promise · Misleading Error
- **File/Lines:** FAB shows for expired when `allow_expired_checkin==true` (`member_home.dart:1001-1018`); scanner blocks all non-active/non-trial with generic "Not a member here" (`qr_scanner_screen.dart:321-325`) — **ignores** the same rule.
- **Why it's a problem:** Direct contradiction between two screens; the error misidentifies an expired member as a non-member.
- **How it fails in production:** Admin enables grace check-in to be lenient; members still can't check in and are told they're not members → support tickets, distrust.
- **Fix:** Make scanner honor `allow_expired_checkin`; give expired members an accurate "Membership expired — renew" message.
- **Effort:** Small

### P3-05 — Notification badge → permanently empty screen 🟠 High
- **Category:** Dead-end · Missing Feedback (re-confirms P2-01 from the member's seat)
- **File/Lines:** badge `member_home.dart:1136`; target screen static (`notifications_screen.dart:1-37`). Real events (approval/rejection/hold) are written to `notifications` but never displayed; no FCM (P0-03).
- **Fix:** Build the reader (P2-01). **Effort:** Medium.

### P3-06 — Silent failures bypass safety gates 🟠 High (aggregate)
- **Category:** Silent Failure · Financial / Integrity
- **Evidence:**
  - Closure-check error ignored → check-in into a closed library proceeds: `qr_scanner_screen.dart:295-299` (`debugPrint('...Ignored error...')`).
  - Exit dues-query `.catchError` sets `checkedDues=true` with `pendingDues=0` → **member with dues can exit if the lookup errors**: `member_home.dart:5004-5008`.
  - `_fetchPreviousSession` failure silently shows wrong attendance card: `member_home.dart:648`.
- **Why it's a problem:** Errors are swallowed in paths that gate money/closure/streak correctness.
- **Fix:** Fail closed (block the action) and surface a retry; never default a financial gate to "0 owed."
- **Effort:** Medium

### P3-07 — Hold request has no rule enforcement 🟡 Medium
- **Category:** Missing Validation (UX side of Phase-7 rules)
- **File/Lines:** `member_home.dart:4908-4912` (only "reason required"); date pickers bound ±30d (`:4811,4850`) but **no** min-days, max-days, or max-holds-per-period check; no duplicate-pending guard; submit has **no spinner/disable** (double-submit) and does **not** refresh home data after insert (`:4906,4920,4930`).
- **How it fails in production:** Members spam holds, request 1-day holds the spec forbids, double-submit; the new pending item doesn't appear until manual refresh → "my hold didn't save."
- **Fix:** Enforce rules client-side (and server-side per P1-03); disable button while submitting; reload after success.
- **Effort:** Medium

### P3-08 — member_home has no offline state; goes to generic crash screen 🟡 Medium
- **Category:** Missing Offline UX
- **File/Lines:** `member_home.dart` has only `OfflineSyncManager.startListening` (`:111`); no connectivity listener, no offline banner. Offline, `_loadInitialData` throws → full-screen "Failed to load dashboard" with **raw exception** (`:1023-1044`). Cached membership data is not shown.
- **Contrast:** the scanner does it right (yellow offline banner, `qr:971-996`).
- **Fix:** Detect offline, show a banner, render cached membership card.
- **Effort:** Medium

### P3-09 — Dues invisible on the membership card 🟡 Medium
- **Category:** Missing Information
- **File/Lines:** card builder `member_home.dart:2778-3223` shows seat/shift/plan/expiry but never dues; no `dues` member-state (`:25-35`); dues computed only inside the Exit sheet (`:4988`).
- **How it fails in production:** A member owing money sees a normal "Active" card, is surprised at renewal/exit.
- **Fix:** Surface a dues banner on the card.
- **Effort:** Small

### P3-10 — Scanner dead-ends and a likely-broken "Report via Queries" 🟡 Medium
- **Category:** Dead-end · Silent Failure
- **File/Lines:** After ≥2 failed scans, retry is replaced by: "Contact Admin for Manual Check-in" → hardcoded SnackBar "Contact details: Jaipur, Rajasthan" (`qr_scanner_screen.dart:1213-1215`, no real contact); "Report via Queries" → inserts against a **zero-UUID** library via an extension `libraryIdOrFallback()` (`qr:1238,1320-1325`) wrapped in `catch(_){}` (`qr:1248`) → no feedback, filed against a nonexistent library.
- **Fix:** Use the real library contact; fix the queries insert and surface success/failure.
- **Effort:** Medium

### P3-11 — Scan promises a beep/vibrate that doesn't exist; raw `$e` strings to users 🟢 Low
- **Evidence:** `qr_scanner_screen.dart:113` comment "// Vibrate/Beep simulation" with no implementation (no sound/haptic anywhere). Raw exception strings shown in several SnackBars: `member_home.dart:2427,4936,5200,5310`; join `:413,594`.
- **Fix:** Add real haptic feedback (`HapticFeedback`); map exceptions to friendly messages.
- **Effort:** Small

### P3-12 — OTP mock discloses the test code to the user 🟢 Low (security-adjacent → Phase 10)
- **Evidence:** `member_profile_edit.dart:480` `'Mock OTP Code Sent: 123456'`; `:497` error "Invalid code. Please enter 123456 for testing."
- **Why it's a problem:** "Verified" badge is meaningless; production users see test scaffolding.
- **Fix:** Real OTP (Phase 10) or remove the feature for V1. **Effort:** Medium.

**Positive findings (verified working):** join submit has `_isSubmitting` guard + success confirmation screen + existing-membership pre-check (`join_flow:69,587,464-476`); renewal has the same guard + dup-check (`renewal:46,208-214,640`); explore has search by name/city/code, loading spinner, "No libraries found" empty state, verified badge (`explore:374,571,694`); **forgot-password works** (`auth_screen.dart:309` `resetPasswordForEmail`); **logout has a confirm dialog** (`member_profile_tab.dart:1802`); exit has a real two-step confirm + dues block when the query succeeds (`member_home.dart:5038-5209`); rejected-payment **re-upload-proof recovery** exists in history (`member_history_tab.dart:1699-1702`).

---

## 6. User Simulation — Persona Matrix (Code-Inferred)

Legend: 🟢 ok · 🟡 friction · 🔴 broken. (Representative high-impact journeys; full per-journey scores in §9.)

| Persona | Discovery | Join | QR Check-in | Renewal | Hold | Notifications |
|---|---|---|---|---|---|---|
| First-time | 🟢 clear search/empty state | 🟡 pays fake UPI 🔴 | 🟡 ok online | 🟡 fake UPI 🔴 | 🟡 no rules shown | 🔴 always empty |
| Returning | 🟢 | 🟢 dup-check blocks re-apply | 🟢 | 🟢 dup-check | 🟡 | 🔴 |
| Power user | 🟢 | 🟡 add-ons lost (P2-03) | 🟡 | 🟢 | 🔴 spam holds, no cap | 🔴 |
| Non-technical | 🟡 code format unclear | 🔴 fake deep-links confuse | 🟡 no haptic feedback | 🔴 deep-links | 🟡 | 🔴 |
| Frustrated | 🟡 | 🔴 money lost → rage | 🟡 ≥2 fails → dead-ends | 🟡 | 🟡 double-submit | 🔴 rage-click empty bell |
| Poor-network | 🟡 spinner ok | 🟡 upload may fail (raw $e) | 🔴 fake offline success | 🟡 | 🟡 | 🔴 |
| Incomplete-profile | 🟢 inline collection | 🟢 collects missing fields | n/a | n/a | n/a | 🔴 |
| Expired-membership | 🟡 | n/a | 🔴 FAB invites, scanner rejects | 🟢 renew path | n/a | 🔴 |
| Failed-payment | n/a | 🟡 rejected w/o reason clarity | n/a | 🟡 | n/a | 🔴 (would-be notify) |
| Invalid-data | 🟡 | 🟡 some validation | 🟡 generic errors | 🟡 | 🟡 | 🔴 |
| Unexpected-action | 🟢 guarded | 🟢 dup-guard | 🟡 retry-spam → dead-end | 🟢 | 🔴 double-submit | 🔴 |
| Small-screen | 🟡 (verify Phase 9) | 🟡 long forms scroll | 🟡 success card overlay | 🟡 | 🟡 | 🟢 |

---

## 7. Reality Check (broken promises / misleading UI / hidden limitations)

| Type | Item | Evidence |
|---|---|---|
| Broken promise (money) | Real UPI → hardcoded placeholder | `join:1295`, `renewal:528` |
| Broken promise (feature) | UPI deep-links → simulated SnackBar | `join` `_buildPaymentAppButton`, `renewal:623` |
| Broken promise (engagement) | Notifications → empty placeholder | `member_home:1136`→`notifications_screen` |
| Broken promise (sensory) | "Vibrate/Beep" comment, no haptic | `qr:113` |
| Misleading UI | Expired = "Not a member here" | `qr:321-325` |
| Misleading UI | Offline = unqualified "Checked In ✓" | `qr:217-271` |
| Hidden limitation | Add-ons paid but not saved | (P2-03) `join:439-558` |
| Missing success feedback | Hold submit no refresh; checkout uses inconsistent SnackBar | `member_home:4920`, `qr:840` |
| Missing failure feedback | closure/dues/queries errors swallowed | `qr:295`, `member_home:5004`, `qr:1248` |
| Missing loading state | hold/exit/withdraw/join-code buttons not disabled | `member_home:4906,5172,2412,5271` |
| Missing offline state | member_home no offline UI | `member_home` (no listener) |
| Empty-state problem | Notifications permanently empty | `notifications_screen` |

---

## 8. Support Perspective (predicted tickets/complaints per screen)

| Screen | Likely top tickets | Confusion points |
|---|---|---|
| Join — Payment | "I paid, got rejected, where's my money?" (P3-01); "GPay didn't open" (P3-02) | Which UPI is real; is payment instant |
| QR Scanner | "App said checked-in but my attendance is missing" (P3-03); "Says I'm not a member but I am" (P3-04) | Offline success; expired handling |
| Notifications | "I never get notified" (P3-05) | Why bell is always empty |
| Renewal | same UPI issues as join; "double charged?" (double-submit elsewhere) | UPI authenticity |
| Hold | "My hold didn't save"; "I was charged during hold" | No confirmation refresh; no rule visibility |
| Membership card | "I didn't know I had dues" (P3-09) | Hidden dues |
| Referral (Phase 2) | "Never got my free days" (P2-02) | Reward never credited |

---

## 9. Required Artifacts

### 9.1 Member Journey Map (entry → outcome; ⚠ = friction point)
```
DISCOVERY  Explore(search name/city/code)🟢 → Library Public Profile🟢 → "Join"
REGISTER   Auth signup(email+pwd, strength)🟢 → Role select🟢 → Profile setup(nickname req)🟢
JOIN       Step1 profile(inline-collect)🟢 → Step2 shift/plan/trial🟢 → Step3 add-ons⚠(not saved)
           → Step4 payment(cash | UPI: FAKE id🔴 + sim deep-link🔴 + screenshot→silence_assets)
           → Step5 review → submit(guard✅) → "Application Submitted / Review Pending"🟢
ACTIVATION admin approves(elsewhere) → membership card🟢 (dues hidden⚠)
CHECK-IN   FAB(state-gated)🟢 → Scanner: online(validated)🟢 / offline(NO validation→fake ✓)🔴
           expired: FAB shows but scanner rejects "Not a member here"🔴
           ≥2 fails → dead-end buttons🔴
ATTENDANCE today card🟢 ; previous-session fetch silent-fail⚠
ANALYTICS  streak/leaderboard/badges (calc → Phase 8)
RENEWAL    select shift/plan/start🟢 → payment(same FAKE UPI🔴) → submit(guard✅, dup-check✅) → pending🟢
HOLD       sheet → reason req only⚠ (no rules, double-submit, no refresh) → pending
SEAT-CHG   bottom sheet → admin manages🟢 (loop complete, Phase 2)
EXIT       More → dues check(spinner)🟢 → block if dues🟢 (but query-error→exit⚠) → two-step confirm🟢
SUPPORT    Queries/Help🟢 ; Reviews🟢 ; Notifications🔴(empty)
REFERRAL   code/share🟢 → reward NEVER credited🔴 (Phase 2)
RECOVERY   Forgot password(resetPasswordForEmail)🟢
SESSION    Logout(confirm dialog)🟢 → re-login🟢
```

### 9.2 Member Friction Register
| Journey | Friction (0–10) | Drop-off | Rage-click | Trust | Refund/Dispute | Support burden |
|---|---|---|---|---|---|---|
| Join — Payment (UPI) | **9** | High | High | Severe | **Severe** | Severe |
| Notifications | 8 | High | High | High | — | High |
| QR offline check-in | 8 | Med | Med | High | Med | High |
| Expired check-in | 7 | Med | High | High | — | High |
| Renewal payment | 7 | Med | Med | High | High | High |
| Referral reward | 7 | High | Med | High | — | High |
| Hold request | 6 | Med | Med | Med | — | Med |
| Add-ons at join | 6 | Low | Low | Med | High | Med |
| member_home offline | 6 | Med | Med | Med | — | Med |
| Dues visibility | 5 | Low | Low | Med | Med | Med |
| Profile OTP verify | 5 | Low | Low | Med | — | Low |
| Discovery | 3 | Low | Low | Low | — | Low |
| Join (non-payment steps) | 3 | Low | Low | Low | — | Low |
| Logout / Recovery | 2 | Low | Low | Low | — | Low |

### 9.3 User Confusion Register
| # | Confusion | Source |
|---|---|---|
| C1 | "Which UPI do I actually pay?" | `join:1295` fake id |
| C2 | "Why didn't GPay open?" | `join` sim deep-link |
| C3 | "It said checked-in — why no attendance?" | `qr:217` offline |
| C4 | "Says I'm not a member, but I am" | `qr:323` expired |
| C5 | "Why is my notifications screen always empty?" | `notifications_screen` |
| C6 | "Did my hold save?" | `member_home:4920` no refresh |
| C7 | "I didn't know I owed dues" | card hides dues |
| C8 | "Where do I get my referral reward?" | P2-02 |

### 9.4 Support Ticket Prediction Register
| Rank | Predicted ticket | Volume | Root finding |
|---|---|---|---|
| 1 | "Paid via UPI, rejected, lost money" | Very High | P3-01 |
| 2 | "Never receive any notification" | High | P3-05 |
| 3 | "Checked in but attendance missing" | High | P3-03 |
| 4 | "Can't check in though admin allows expired" | High | P3-04 |
| 5 | "GPay/PhonePe button does nothing" | Med | P3-02 |
| 6 | "Referral reward never arrived" | Med | P2-02 |
| 7 | "Paid for locker, didn't get it" | Med | P2-03 |
| 8 | "Charged/held wrongly; hold didn't save" | Med | P3-07 |

### 9.5 Drop-Off Risk Register
| Stage | Risk | Driver |
|---|---|---|
| Payment (join) | **Highest** | Fake UPI → lost money/abandon |
| First check-in | High | Offline fake success / expired rejection |
| Day-2 engagement | High | Empty notifications, no push |
| Renewal | High | Repeats payment distrust |
| Referral | Med | Reward never arrives |

### 9.6 Trust Risk Register
| Trust risk | Severity | Evidence |
|---|---|---|
| Money sent to placeholder account | Critical | P3-01 |
| "Verified" badge from mock OTP | Med | P3-12 |
| Success shown for failed offline scan | High | P3-03 |
| Misidentifying members as non-members | High | P3-04 |
| Permanently empty notifications | High | P3-05 |
| Raw exception strings leaking internals | Low | P3-11 |

---

## 10. Incomplete Features (member-side, this phase)
Real UPI wiring; UPI deep-links; offline scan validation; expired-checkin consistency; notifications reader; hold rule enforcement; member_home offline UX; dues surfacing; scanner contact/queries actions; real OTP.

## 11. Improvement Suggestions
1. **Fix the money path first** (P3-01) — it's a Small change with Critical impact; then deep-links (P3-02).
2. **Make success/failure honest** — never show "Checked In ✓" without a real record; honor `allow_expired_checkin` everywhere.
3. **Close the notification loop** (reader + eventual FCM).
4. **Fail closed on financial/closure gates** (dues, closures) instead of swallowing errors.
5. **Add per-action loading/disable** universally to kill double-submits.

## 12. Priority Fix List (Phase 3)
| # | Item | Severity | Effort |
|---|---|---|---|
| 1 | Real owner UPI in join+renewal (P3-01) | Critical | Small |
| 2 | Real UPI deep-links (P3-02) | High | Medium |
| 3 | Offline scan validation + honest copy (P3-03) | High | Medium |
| 4 | Scanner honors expired rule + accurate error (P3-04) | High | Small |
| 5 | Notifications reader (P3-05/P2-01) | High | Medium |
| 6 | Fail-closed on dues/closure errors (P3-06) | High | Medium |
| 7 | Hold rules + loading + refresh (P3-07) | Medium | Medium |
| 8 | member_home offline UX (P3-08) | Medium | Medium |
| 9 | Surface dues on card (P3-09) | Medium | Small |
| 10 | Fix scanner dead-ends/queries (P3-10) | Medium | Medium |

---

## 13. Cross-Phase Critical Findings (additions this phase)
| Ref | Sev | Title | Evidence | Effort |
|---|---|---|---|---|
| P3-01 | **Critical** | Members pay hardcoded placeholder UPI in join + renewal | `join_flow_screen.dart:1295`, `renewal_screen.dart:528` | Small |
| P3-02 | High | UPI app deep-links are simulated stubs | `join` `_buildPaymentAppButton`, `renewal:623` | Medium |
| P3-03 | High | Offline check-in validates nothing; fakes success | `qr_scanner_screen.dart:217-271` | Medium |
| P3-04 | High | Expired-checkin: FAB invites, scanner rejects as "not a member" | `member_home.dart:1017` vs `qr:321-325` | Small |
| P3-05 | High | Notifications unreachable (badge→empty screen) | `member_home.dart:1136`; `notifications_screen.dart` | Medium |
| P3-06 | High | Silent failures bypass dues/closure safety gates | `qr:295-299`, `member_home.dart:5004-5008` | Medium |

## 14. Open Questions (additions)
16. Are the hardcoded UPI/deep-links a leftover demo placeholder slated for wiring, or was real-UPI never built admin-side? (Admin UPI setup exists in `admin_profile_tab` — check Phase 4 whether it's stored and simply not consumed.)
17. Does the admin approval path record add-ons or real payment amounts the member entered? → Phase 4.
18. Is leaderboard "nickname-only" privacy actually enforced? → Phase 8/10.

## 15. Verification Pending (additions — need device, Phase 13)
| VID | Item | Method |
|---|---|---|
| V-19 | Offline scan true behavior end-to-end (fake success → sync discard) | Device airplane-mode run |
| V-20 | Expired-member scan message on device | Device with expired membership |
| V-21 | UPI deep-link buttons (confirm no launch) | Device tap |
| V-22 | Small-screen overflow on join/scanner/card | Device 320px width (Phase 9/13) |

---

*End of Phase 3. No code modified. Stopped; awaiting approval for Phase 4 (Admin Flow Audit).*
