# SILENCE — Phase 9: UI/UX Audit (Usability · Trust · Adoption)

**Phase:** 9 of 16 — UX Audit (treated as a usability, trust & adoption audit, not visual review)
**Completed (local time):** 2026-06-08
**Auditor roles:** Senior UX Designer (lead) · Product Manager · QA Lead · Full-Stack Engineer · Support/CX Analyst
**Goal:** Determine whether users can **understand, trust, discover, and complete** their goals — judged on *actual* UX, not intended UX.
**Method:** Static screen-by-screen review + 12-persona user simulation. Behavior **Code-Inferred** (no emulator/live render). Every claim cites `file:line`. Trust > Clarity > Completion > Aesthetics. **A beautiful screen with misleading behavior scores poorly.**
**Constraint honored:** No UI/code modified.

> **Scoring legend (per journey):** Friction 0 (none) → 10 (severe). Trust/Discoverability/Completion-Confidence 0 (broken) → 10 (excellent).

---

## 1. Executive Summary — The Beautiful-Lie Problem

SILENCE is **visually polished and emotionally well-crafted** (warm palette, emoji affordances, motivational copy, password-strength meters, confirmation screens). That polish is precisely the risk: **the UI's confidence consistently exceeds the system's capability.** Screens render success states for actions the backend never truly performs. This is the worst UX failure mode — not ugliness, but *misplaced trust* that converts directly into refunds, disputes, and support tickets.

**The single most damaging finding (UX-integrity):** The standalone **Notifications screen is a hardcoded placeholder** that *always* renders "You're all caught up!" regardless of real notifications (`notifications_screen.dart:26-29`, entire file is a `StatelessWidget` with no data fetch). Members with pending payment reminders, approvals, or badge alerts are told, every single time, that nothing needs attention. This is not an empty state — it is a **false negative shown to 100% of users.**

**The most expensive finding (financial trust):** The **Subscription upgrade is a full payment theatre** — `Future.delayed(2000ms)` with an on-screen "Authorizing payment with bank gateway…" (`subscription_screen.dart:219,277`), after which it marks the account `active`, fabricates an invoice (`:300`), and shows "Plan upgraded… successfully! 👑 ✓" (`:305`) — **without any payment occurring.** Members will believe they paid. Disputes are inevitable.

**Distribution:** 2 Critical · 7 High · 11 Medium · 6 Low UX findings (P9-01 … P9-26), plus the 8 requested registers.

**Headline scores (12 special-focus journeys, averaged):**
| Dimension | Avg /10 | Verdict |
|---|---|---|
| Friction | 5.4 | Moderate-high; forms long, recovery weak |
| **Trust** | **3.1** | **Critical — UI promises ≠ system reality** |
| Discoverability | 4.8 | Key features buried; no notification surfacing |
| Completion Confidence | 4.2 | Users *think* they finished when they didn't |

**Verdict:** The app would demo beautifully and fail in production within the first billing cycle. **Trust erosion, not aesthetics, is the adoption blocker.**

---

## 2. What Was Reviewed
49 screen files across `lib/screens/**`. Twelve special-focus journeys deep-audited (join, renewal, payment, QR check-in, analytics, notifications, referrals, add-ons, queries, reviews, admin dashboard, admin setup wizard, member home). Each simulated against 12 personas.

## 3. Files Cited (evidence base)
`notifications_screen.dart`, `subscription_screen.dart`, `reservations/join_flow_screen.dart`, `reservations/renewal_screen.dart`, `reservations/qr_scanner_screen.dart`, `reservations/library_query_screen.dart`, `auth_screen.dart`, `member_home.dart`, `admin_home.dart`, `admin_analytics_tab.dart`, `member_analytics_tab.dart`, `library_setup_stage1-3.dart`, `referral_settings.dart`, `addon_services.dart`, `member_explore_screen.dart`; cross-phase: Phases 3,4,6,7,8.

---

## 4. User Simulation — 12 Personas × Key Screens (actual outcomes)

| Persona | Where it breaks (actual behavior) | Evidence |
|---|---|---|
| **First-time user** | Signs up with email+password; **never asked to verify** anything; lands with no guidance on next step. OTP/verification is absent entirely. | `auth_screen.dart` (no OTP code path; only `signInWithPassword`/signup + password-strength meter `:56-86`) |
| **Returning user** | Opens Notifications expecting reminders → **always "You're all caught up!"** even with pending dues. | `notifications_screen.dart:26-29` |
| **Power user** | Wants fast renewal; instead re-enters payment method + uploads UPI screenshot every cycle; no saved method. | `renewal_screen.dart:41-46,220-223` |
| **Non-technical user** | UPI flow shows raw IDs `owner@upi / 9876543210@paytm` (hardcoded sample), taps "pay" → **"Simulated deep link: Opening … app"** — no real app opens; confusion. | `join_flow_screen.dart:1295,1393-1394` |
| **Frustrated user** | After "Submit Application" sees a celebratory confirmation (`:1497`), but membership is *pending manual admin approval*; no ETA → repeated taps/support. | `join_flow_screen.dart:1481-1497` |
| **Poor-network user** | QR scan & joins wrapped in try/catch with SnackBar — OK; but analytics screens scan full tables (Phase 8/11) → long blank/spinner with no skeleton. | `join_flow_screen.dart:606-609` (full-screen spinner only) |
| **Incomplete-profile user** | Many admin actions blocked with "Complete your profile first" SnackBars scattered across analytics (`admin_analytics_tab.dart:771,805,936`) — message repeats but no single CTA to *go* complete it. | `admin_analytics_tab.dart:771,805` |
| **Expired-membership user** | Home FAB respects `allow_expired_checkin`; **scanner does not** (Phase 3 P3-04) → inconsistent: home blocks, QR allows (or vice-versa). | `member_home.dart:1017`; `qr_scanner_screen.dart` |
| **Failed-payment user** | Cannot fail — subscription payment is `Future.delayed` that always succeeds (`subscription_screen.dart:277-305`); UPI join "payment" is just a screenshot upload, also can't fail at pay-time. No failure UX exists to exercise. | `subscription_screen.dart:277` |
| **Invalid-data user** | Join form validates name/phone/shift (`join_flow_screen.dart:744-784`) — good; but amount is hardcoded downstream (Phase 4 P4-03), so valid input still yields wrong money. | `join_flow_screen.dart:744-784` |
| **Unexpected-action user** | Cancels subscription → **"Subscription cancellation is locked in simulated mode."** (`subscription_screen.dart:433`) — admits the mock to the user. | `subscription_screen.dart:433` |
| **Small-screen user** | 5,443/5,384-line analytics & home screens with dense stat grids and custom painters; no evidence of responsive breakpoints (`LayoutBuilder`/`MediaQuery` scaling) around stat cards. High overflow risk on <360dp. | `admin_analytics_tab.dart`, `member_home.dart` (size from Phase 8) |

---

## 5. Findings

### P9-01 — Notifications screen is a hardcoded "all caught up" stub 🔴 Critical
**Category:** UX Integrity / false negative
**Evidence:** `notifications_screen.dart` (whole file) — a `StatelessWidget` whose body is `Center(Column[ Icon(notifications_none), Text("You're all caught up!") ])` (`:24-29`). **No query, no data, no state.**
**Reality vs UI:** Phase 5/7 confirmed notifications are DB rows (`notifications` table, written by `_awardBadge` etc.). This screen **never reads them.** Every user, always, is told there is nothing.
**Impact:** Payment reminders, approval results, badge unlocks, announcements — all invisible. Users miss renewals → involuntary churn; miss approvals → re-apply → duplicate requests → support tickets. Destroys trust the moment a user discovers a missed reminder.
**Personas hit:** Returning, expired-membership, failed-payment (the people who most need notifications).
**Fix:** Wire the screen to fetch `notifications` for the user, with real empty/loading/error states and mark-as-read.

### P9-02 — Subscription upgrade is payment theatre that fabricates a paid invoice 🔴 Critical
**Category:** UX Integrity / financial trust
**Evidence:** `subscription_screen.dart:219` "Authorizing payment with bank gateway…"; `:231-245` "Simulated payment" rows ("Instant authorization", "All Indian banks integrated"); `:277` `await Future.delayed(2000ms) // Simulated delay`; `:282,289` writes `subscription_status:'active'`; `:300` inserts a fake `INV-2026-…` invoice; `:305` "Plan upgraded to Pro Plan successfully! 👑 ✓".
**Reality vs UI:** No money moves; the UI states a bank authorized a card.
**Impact:** Admin believes they paid for Pro; later billed or locked out → dispute/chargeback/refund demand. "Netbanking — All Indian banks integrated" is an outright false capability claim (store-policy risk, Phase 14).
**Fix:** Remove fake gateway copy; gate behind a real processor or label clearly "Demo / not charged."

### P9-03 — Join "Submit Application" shows celebratory success for a pending, manually-approved request 🟠 High
**Category:** False confidence / completion ambiguity
**Evidence:** `join_flow_screen.dart:734` button "Submit Application"; `:1497` confirmation "Application Submitted!" full-screen celebration. Backend just inserts a `pending` `join_requests` row (Phase 3/4); approval is manual and async.
**Impact:** Members think they're *in* (seat secured) when they're queued. They show up at the library; seat not assigned → friction, support. No status/ETA/"what happens next."
**Fix:** Reframe as "Request sent — awaiting library approval," show pending status + expected response window.

### P9-04 — UPI payment is a screenshot-upload honor system presented as "Pay securely" 🟠 High
**Category:** UX Integrity / trust
**Evidence:** `join_flow_screen.dart:1282` "📱 UPI / Online Transfer — Pay securely using GPay, PhonePe…"; but flow only collects `upi_sender_name` (`:1342-1345`) + a screenshot proof (`:531-551`, `payment_proof_url`). Tapping an app shows `:1393-1394` "Simulated deep link: Opening … app". Hardcoded sample UPI IDs `owner@upi / 9876543210@paytm` (`:1295`).
**Impact:** "Pay securely" overstates a manual, forgeable proof workflow (screenshot can be faked — Phase 6/7). Sample UPI IDs may be mistaken for real payee → money sent to nobody. High dispute risk.
**Fix:** Replace "Pay securely" copy with the truth ("Upload payment screenshot for admin to verify"); never ship placeholder UPI IDs; remove "Simulated deep link."

### P9-05 — Renewal repeats full payment entry every cycle; no saved method, success ≠ renewed 🟠 High
**Category:** Friction + false confidence
**Evidence:** `renewal_screen.dart:41-46` re-collects method; `:220-223` requires screenshot again; `:255` "Request Submitted! 🎉" but inserts a `join_requests` row pending approval (`:248`).
**Impact:** Power users churn from repeated friction; "Request Submitted 🎉" implies renewed, but membership only extends on manual approval + (broken) amount logic. Lapse risk during the approval gap.
**Fix:** Saved payment method; status-accurate copy ("Renewal requested — pending approval").

### P9-06 — No OTP / phone / email verification anywhere; signup trust signal absent 🟠 High
**Category:** Trust / security-UX (cross-ref Phase 6 P6-06)
**Evidence:** `auth_screen.dart` — only `signInWithPassword` (`:115`) and password signup with a strength meter (`:56-86`); grep for OTP/verify/code = **no matches**. Profile screens self-set `verified` flags (Phase 6 P6-06).
**Impact:** No proof the phone/email is real; members can't trust "verified" badges; admins can't trust member contact data → failed reminders, no-shows. Anyone can sign up with anyone's email.
**Fix:** Enable Supabase email/phone verification; reflect a real verified state.

### P9-07 — QR "Outdated QR Code" is a hard, immediate rejection (no 7-day grace) 🟠 High
**Category:** Error UX / promised-but-absent grace
**Evidence:** `qr_scanner_screen.dart:328-333` strict `qrVersion != dbQrVersion` → `_handleFailure('Outdated QR Code', 'scan the newly printed QR')`. Phase 7 (P7-06) documented a *promised* 7-day regeneration grace that isn't implemented.
**Impact:** The instant an admin regenerates a QR, every printed poster breaks mid-session; members at the desk can't check in → immediate support spike, perceived outage.
**Fix:** Honor the documented grace window, or warn admins that regeneration is breaking-immediate.

### P9-08 — "Already Checked In" blocks legitimate multi-session days 🟡 Medium
**Category:** Error UX / over-blocking
**Evidence:** `qr_scanner_screen.dart:407` `_handleFailure('Already Checked In', 'You are already checked in today.')` keyed off any completed session today.
**Impact:** A member who studied morning, left, returns evening cannot re-check-in → undercounts hours (compounds Phase 8 P8-04) and frustrates. Message implies user error, not a policy.
**Fix:** Allow multiple sessions/day or clearly state the one-session policy.

### P9-09 — Analytics present false-precision numbers as fact (no "estimated/unverified" signal) 🟠 High
**Category:** Trust (inherits Phase 8)
**Evidence:** Currency `toStringAsFixed(0)` and rates `toStringAsFixed(1)` throughout `admin_analytics_tab.dart` (e.g. revenue `:2180`, change `:2182`); member streaks/hours in `member_home.dart`/`member_analytics_tab.dart`. Phase 8 proved these rest on fabricated amounts (P8-08), TZ-broken days (P8-01), divergent durations (P8-04/05).
**Impact:** Admins make pricing/staffing decisions on wrong revenue/occupancy; members distrust the app the first time a streak is visibly wrong. Confident formatting = false authority.
**Fix:** Until Phase 8 fixes land, mark computed figures as estimates; don't render decimals on fabricated money.

### P9-10 — Queries submit into a void: no response channel, no status tracking for the member 🟡 Medium
**Category:** Discoverability / completion confidence
**Evidence:** `library_query_screen.dart:79-83` inserts `queries{status:'open'}`; success SnackBar `:87-90`. No member-side list of past queries / admin replies surfaced (no read path observed); notifications stub (P9-01) can't deliver a reply anyway.
**Impact:** Member asks a question, gets a SnackBar, then silence → re-asks via WhatsApp/call → support burden. "Open" status never visibly closes for the member.
**Fix:** Member "My Queries" list with admin replies; deliver via working notifications.

### P9-11 — Referral UI implies rewards that are never credited 🟡 Medium
**Category:** UX Integrity (inherits Phase 7 P7-05/P2-02)
**Evidence:** `referral_settings.dart` configures rewards; `member_analytics_service.dart:701-711` counts `pending`/`credited`, but Phase 7 proved status is never set to `credited` and no membership extension occurs.
**Impact:** Members refer friends expecting a reward, see perpetual "pending," feel cheated → trust erosion + support ("where's my referral bonus?").
**Fix:** Either implement crediting or remove the reward promise from the UI.

### P9-12 — Add-ons configurable but not enforced/charged at transaction 🟡 Medium
**Category:** UX Integrity (inherits Phase 7)
**Evidence:** `addon_services.dart` (locker/add-on inventory) — Phase 7 found business rules saved-not-enforced; no charge path at join/renewal couples add-ons to amount (amount hardcoded, P4-03).
**Impact:** Admin enables a paid locker add-on; member is never charged for it / it isn't reserved → revenue leak + member confusion over what they're entitled to.
**Fix:** Wire add-on selection into the priced transaction.

### P9-13 — Admin dashboard shows "0%" occupancy that means "no seats generated," not "empty" 🟡 Medium
**Category:** Misleading metric (cross-ref Phase 8 P8-06)
**Evidence:** `admin_home.dart:624-626` occupancy guard returns `0.0` when `_totalSeats==0`; `:4562-4564` renders "0%". Phase 7/8: non-first shifts have no generated seats.
**Impact:** Admin sees 0% occupancy during a busy non-first shift → thinks library is empty, may discount/over-admit. Opposite of reality.
**Fix:** Distinguish "no capacity configured" from "0 occupied."

### P9-14 — "Complete your profile first" gating repeats with no in-context CTA 🟡 Medium
**Category:** Friction / dead-end messaging
**Evidence:** `admin_analytics_tab.dart:771,780,805,814,936,945` — six near-identical SnackBars ("Complete your profile first to manage expenses" / "Set up your library first"). They inform but don't navigate.
**Impact:** Admin bounced repeatedly with no button to resolve the blocker → frustration, abandonment during onboarding.
**Fix:** Replace with a single banner + "Complete profile" button that routes to the wizard.

### P9-15 — Setup wizard work-loss risk: unclear per-step persistence 🟡 Medium
**Category:** Friction / data-loss anxiety
**Evidence:** 3-stage wizard `library_setup_stage1-3.dart`; Phase 4 found multi-stage setup with seat generation only at a later stage. No autosave/draft indicator observed.
**Impact:** Long setup; if the admin backs out or the app dies, re-entry risk → abandonment at onboarding (the highest-stakes funnel).
**Fix:** Per-step persistence + "Draft saved" indicator + resume.

### P9-16 — Full-screen spinner as the only loading state (no skeletons) on heavy screens 🟡 Medium
**Category:** Loading-state quality
**Evidence:** `join_flow_screen.dart:606-609`, `renewal_screen.dart:64-118`, `library_query_screen.dart:126`. Analytics/home do full-table scans (Phase 8 P8-02, Phase 11) behind a single spinner.
**Impact:** Poor-network users stare at a blank orange spinner for seconds with no content/skeleton/progress → perceived hang, force-quit.
**Fix:** Skeleton placeholders; progressive render.

### P9-17 — Success states fire before backend confirmation in several flows 🟡 Medium
**Category:** Optimistic-UI honesty
**Evidence:** Join `:1497`, renewal `:255`, subscription `:305`, badge award notification insert in `member_analytics_service.dart:692` (fire-and-forget, swallowed `catch{}` `:697`).
**Impact:** "🎉 Submitted/Upgraded/Badge earned" can show even when the downstream write is denied/swallowed (Phase 6 P6-05 silent failures) → user believes a thing happened that didn't.
**Fix:** Confirm writes before celebrating; surface failures.

### P9-18 — Hardcoded sample/placeholder content shipped in user-facing surfaces 🟢 Low
**Category:** Polish / trust
**Evidence:** UPI IDs `owner@upi / 9876543210@paytm` (`join_flow_screen.dart:1295`); fake invoice number/date `'27 May 2026', 799` (`subscription_screen.dart:300`); seat fallback `'G-A-01'` (`qr_scanner_screen.dart:340`).
**Impact:** Placeholder data reads as real → wrong payee, confusion.
**Fix:** Remove placeholders; source from config.

### P9-19 — No accessibility affordances observed (semantics, contrast, tap targets) 🟡 Medium
**Category:** Accessibility
**Evidence:** Heavy use of `GoogleFonts`, custom `CustomPainter` charts (`admin_analytics_tab.dart:4754+`), emoji-as-meaning ("💵","📱","🔥"), color-only status (orange/green dots, `member_analytics_service.dart:503-522`). No `Semantics`, `excludeSemantics`, or `Tooltip` density seen; charts have no text alternative.
**Impact:** Screen-reader users get unlabeled painters; color-blind users can't distinguish present/absent/closed dots that differ only by color; emoji-only CTAs unreadable by TalkBack.
**Fix:** Add Semantics labels, text+icon (not color-only) status, chart data tables.

### P9-20 — "Active" subscription status sourced from SharedPreferences, not server 🟡 Medium
**Category:** Trust / stale-state
**Evidence:** `subscription_screen.dart:52` `_status = prefs.getString('sub_status_${user.id}') ?? 'Active'`; defaults to **"Active"** if unknown.
**Impact:** A brand-new/unknown admin sees "Active" by default; status can diverge from server; uninstall/reinstall flips perceived plan. Defaulting to "Active" hides un-subscribed state.
**Fix:** Server-authoritative status; default to a neutral/unknown state.

### P9-21 — Cancellation path admits the mock to the user 🟢 Low
**Category:** Trust signal
**Evidence:** `subscription_screen.dart:433` "Subscription cancellation is locked in simulated mode."
**Impact:** Breaks the fourth wall; signals an unfinished product to paying admins.
**Fix:** Hide demo seams in any build shown to real users.

### P9-22 — Error messages expose raw exceptions to end users 🟢 Low
**Category:** Error-state quality
**Evidence:** `join_flow_screen.dart:594` `'Failed to submit application: $e'`; `renewal_screen.dart:165` `'Failed to upload screenshot: $e'`; `library_query_screen.dart:99` `'Failed to submit query: $e'`.
**Impact:** Stack-traceish strings (PostgREST/Supabase errors) confuse non-technical users and leak internals.
**Fix:** Friendly messages; log `$e` to telemetry, not the SnackBar.

### P9-23 — Member home dense multi-stage UI; key actions compete for attention 🟢 Low
**Category:** Information hierarchy / cognitive load
**Evidence:** `member_home.dart` (5,384 ln) renders state-dependent cards (trial/active/expiring/expired/hold + setup progress + streak + activity timeline + expiry banner `:1647-1668`). Multiple CTAs per state.
**Impact:** First-time/non-technical users face high cognitive load; primary next action not always singular/obvious.
**Fix:** One primary CTA per state; demote secondary cards.

### P9-24 — Expiry banner can read "Only 0 days left" while still active 🟡 Medium
**Category:** Copy correctness (cross-ref Phase 8 P8-20)
**Evidence:** `member_home.dart:1653` `daysLeft = parse(end).difference(now).inDays` (truncates); `:1668` "Only $daysLeft days left on your plan".
**Impact:** "0 days left" on the final active day reads as expired → premature panic or, worse, distrust when access still works.
**Fix:** Date-only IST diff or `ceil`.

### P9-25 — Empty states are inconsistent: some informative, notifications fake-positive 🟢 Low
**Category:** Empty-state consistency
**Evidence:** Good: query screen, analytics show real empties. Bad: notifications always-positive (P9-01). Heatmap/analytics empties depend on broken inputs (Phase 8).
**Impact:** Inconsistent trust; the one empty state users check most (notifications) is the dishonest one.
**Fix:** Standardize honest empty states.

### P9-26 — Discoverability: critical features buried or unreachable 🟡 Medium
**Category:** Discoverability
**Evidence:** Notifications stub hides all alerts (P9-01); queries have no return channel (P9-10); referral rewards invisible (P9-11); add-ons not surfaced at purchase (P9-12). Phase 2 orphan list corroborates unreachable surfaces.
**Impact:** Users can't find/track the things that retain them (alerts, support replies, rewards).
**Fix:** Notification center, "My Queries," referral status, add-on selection at checkout.

---

## 6. Friction Analysis — 12 Special-Focus Journeys

| Journey | Friction | Trust | Discoverability | Completion-Confidence | Note |
|---|---:|---:|---:|---:|---|
| **Join flow** | 6 | 3 | 6 | 4 | Long form OK; "Pay securely" + celebratory success mislead (P9-03/04) |
| **Renewal** | 7 | 3 | 5 | 4 | Re-enter everything; success ≠ renewed (P9-05) |
| **Payment (subscription)** | 4 | **1** | 6 | 3 | Full payment theatre (P9-02) — lowest trust in app |
| **QR check-in** | 5 | 5 | 7 | 6 | Solid flow; hard QR-version reject + already-checked-in over-block (P9-07/08) |
| **Attendance analytics** | 3 | 2 | 6 | 3 | Pretty, precise, wrong (P9-09) |
| **Notifications** | 2 | **1** | **2** | 2 | Hardcoded "all caught up" (P9-01) |
| **Referrals** | 4 | 2 | 4 | 3 | Rewards never credited (P9-11) |
| **Add-ons** | 5 | 3 | 4 | 4 | Configurable, not charged (P9-12) |
| **Queries** | 4 | 4 | 3 | 4 | Submit into void, no reply channel (P9-10) |
| **Reviews** | 4 | 5 | 5 | 5 | Reply path exists (admin/reply sheet); delivery depends on notifications |
| **Admin dashboard** | 5 | 3 | 6 | 5 | 0%-occupancy ambiguity (P9-13); fabricated revenue (P9-09) |
| **Admin setup wizard** | 7 | 5 | 5 | 5 | Long; work-loss risk (P9-15); profile-gate dead-ends (P9-14) |
| **Member home** | 5 | 4 | 6 | 5 | Dense; "0 days left" copy bug (P9-24) |
| **Averages** | **5.0** | **3.1** | **4.8** | **4.1** | Trust is the systemic failure |

---

## 7. Requested Registers

### 7.1 Screen Inventory with UX Scores (major screens)
| Screen | Hierarchy | Clarity | Empty | Loading | Error | Success | Trust | A11y | Overall |
|---|---|---|---|---|---|---|---|---|---|
| Notifications | — | ✓ | ✗ fake | ✗ none | ✗ none | ✗ | **1** | ✗ | **1/10** |
| Subscription | ✓ | ✓ | ✓ | ✓ | ✗ can't fail | ✗ fake | **1** | ✗ | **2/10** |
| Join flow | ✓ | △ | n/a | ✓ spinner | ✓ | △ misleading | 3 | ✗ | 4/10 |
| Renewal | ✓ | △ | n/a | ✓ | ✓ | △ | 3 | ✗ | 4/10 |
| QR scanner | ✓ | ✓ | n/a | ✓ | ✓ rich | ✓ cards | 5 | △ | 6/10 |
| Admin analytics | △ dense | ✓ | ✓ | ✓ spinner | △ swallow | ✓ | 2 | ✗ painters | 4/10 |
| Member analytics | △ | ✓ | ✓ | ✓ | △ | ✓ | 2 | ✗ | 4/10 |
| Admin home | △ | ✓ | △ | ✓ | △ | ✓ | 3 | ✗ | 5/10 |
| Member home | △ dense | △ | ✓ | ✓ | △ | ✓ | 4 | ✗ | 5/10 |
| Setup wizard | ✓ | ✓ | n/a | ✓ | ✓ validate | ✓ | ✗ | 5/10 |
| Queries | ✓ | ✓ | ✓ | ✓ | ✓ | △ void | 4 | ✗ | 5/10 |
| Auth | ✓ | ✓ | n/a | ✓ | ✓ | ✓ | 4 no-verify | ✗ | 5/10 |

### 7.2 UX Integrity Register (UI says X · System does Y)
| # | UI says | System does | Evidence |
|---|---|---|---|
| UXI-1 | "You're all caught up!" (always) | Never reads notifications table | `notifications_screen.dart:26-29` |
| UXI-2 | "Authorizing payment with bank gateway…" / "Plan upgraded successfully ✓" | `Future.delayed`, no charge, fake invoice | `subscription_screen.dart:219,277,300,305` |
| UXI-3 | "Pay securely using GPay/PhonePe" | Uploads a screenshot for manual admin check | `join_flow_screen.dart:1282,531-551` |
| UXI-4 | "Opening … app" (deep link) | "Simulated deep link" — nothing opens | `join_flow_screen.dart:1393-1394` |
| UXI-5 | "Application Submitted! 🎉" (looks done) | Inserts pending request; manual approval | `join_flow_screen.dart:1497`,`248` |
| UXI-6 | "Request Submitted! 🎉" (renewed) | Pending request; not yet renewed | `renewal_screen.dart:255,248` |
| UXI-7 | "Netbanking — All Indian banks integrated" | No integration | `subscription_screen.dart:245` |
| UXI-8 | Referral "pending → reward" | Never credited; no extension | Phase 7 P7-05; `member_analytics_service.dart:701-711` |
| UXI-9 | Revenue ₹X / Occupancy Y% (exact) | Fabricated amounts, TZ-broken days | Phase 8 P8-01/08; `admin_analytics_tab.dart:2180` |
| UXI-10 | "Verified" badge | Self-set flag, no verification | Phase 6 P6-06 |
| UXI-11 | Subscription "Active" | Read from SharedPreferences, defaults Active | `subscription_screen.dart:52` |
| UXI-12 | "0% occupancy" | No seats generated ≠ empty | `admin_home.dart:624-626,4562` |
| UXI-13 | "Only 0 days left" | Still active that day | `member_home.dart:1653,1668` |

### 7.3 User Friction Register (expanded)
| Screen | Friction source | Severity |
|---|---|---|
| Renewal | Re-enter method + screenshot every cycle | High |
| Subscription | Can't truly pay/cancel | High |
| Setup wizard | Long, work-loss risk | High |
| Join | 5 steps + manual proof | Med |
| Analytics | Full-screen spinner, slow scans | Med |
| Admin analytics | Repeated profile-gate SnackBars, no CTA | Med |
| QR | Hard reject on regenerated QR / multi-session block | Med |
| Errors | Raw `$e` strings | Low |

### 7.4 Discoverability Register
| Hidden/unreachable | Why it matters | Evidence |
|---|---|---|
| All notifications | Reminders/approvals invisible | `notifications_screen.dart` |
| Query replies / status | Support answers never reach member | `library_query_screen.dart` (no read path) |
| Referral reward status | Retention driver invisible | Phase 7 P7-05 |
| Add-on purchase at checkout | Revenue + entitlement | `addon_services.dart` |
| Profile-completion route | Bounced w/o CTA | `admin_analytics_tab.dart:771` |

### 7.5 Accessibility Register
| Issue | Evidence | Impact |
|---|---|---|
| No Semantics on custom charts | `admin_analytics_tab.dart:4754+` painters | Screen readers get nothing |
| Color-only status dots | `member_analytics_service.dart:503-522` | Color-blind can't differentiate |
| Emoji-as-meaning CTAs | `join_flow_screen.dart:1280-1282` | TalkBack unreadable |
| No responsive scaling on stat grids | `member_home.dart`, analytics | <360dp overflow |
| GoogleFonts fixed sizes | throughout | Ignores OS text-scale |

### 7.6 Trust Erosion Register (ordered by damage)
| Rank | Trust breaker | Evidence |
|---|---|---|
| 1 | Fake bank-gateway payment + fabricated invoice | `subscription_screen.dart:219,277,300` |
| 2 | Notifications always "caught up" → missed reminders | `notifications_screen.dart:26` |
| 3 | "Pay securely" over a screenshot honor-system | `join_flow_screen.dart:1282` |
| 4 | Celebratory success for pending/unconfirmed actions | `:1497`, `renewal:255` |
| 5 | Precise but fabricated revenue/occupancy/streaks | Phase 8 |
| 6 | Referral rewards never paid | Phase 7 P7-05 |
| 7 | No identity verification; self-set "Verified" | `auth_screen.dart`; Phase 6 |
| 8 | "Locked in simulated mode" admits incompleteness | `subscription_screen.dart:433` |

### 7.7 Support Burden Register
| Screen | Likely ticket | Likely complaint | Refund/dispute cause |
|---|---|---|---|
| Subscription | "I paid but got billed / locked" | "Charged for nothing" | **Chargeback** (UXI-2) |
| Notifications | "I never got my reminder" | "App said all caught up" | Churn, not refund |
| Join/Renewal | "Where's my seat? I submitted" | "It said success" | Refund of UPI sent (UXI-5/6) |
| UPI pay | "I paid wrong number" | sample UPI ID confusion | Money-to-nobody dispute |
| Referrals | "Where's my bonus?" | "Stuck pending forever" | Goodwill credit demands |
| Analytics | "These numbers are wrong" | distrust whole app | — |
| QR | "Can't check in, QR outdated" | "App broke at the desk" | — |

### 7.8 Drop-Off Register (likely abandonment points)
| Funnel point | Why users abandon | Evidence |
|---|---|---|
| Admin setup wizard (mid) | Long + fear of losing work | `library_setup_stage1-3` |
| Join → payment step | "Pay securely" but manual screenshot confuses | `join_flow_screen.dart:1280-1394` |
| Subscription upgrade | Senses it's fake ("simulated mode") | `subscription_screen.dart:433` |
| Post-submit wait | No status/ETA after "Submitted 🎉" | `:1497` |
| Notifications | Nothing ever there → stops opening | `notifications_screen.dart` |
| Renewal | Repeat friction → lapses instead | `renewal_screen.dart:41-46` |

---

## 8. User Reality Audit (actual, not intended)
- **Screens that promise things that don't work:** Notifications (UXI-1), Subscription (UXI-2/7), UPI "Pay securely" (UXI-3/4), Referrals (UXI-8).
- **Screens that hide critical information:** Notifications (all alerts), Queries (replies), Admin dashboard ("0%" hides config gap), Member home (expiry math).
- **Screens that create false confidence:** Join/Renewal success (UXI-5/6), Subscription (UXI-2), Analytics (UXI-9).
- **Screens that encourage support tickets:** Subscription, Notifications, Join/Renewal, Referrals.
- **Screens that cause refunds/disputes:** Subscription (chargeback), UPI join (money-to-nobody), Renewal.
- **Screens where users abandon:** Setup wizard, payment steps, post-submit wait (see Drop-Off Register).

---

## 9. Priority Fix List (Phase 9, ordered by trust impact)
1. **P9-01** (Critical) — Wire the Notifications screen to real data; remove the always-positive stub.
2. **P9-02** (Critical) — Remove fake payment gateway/invoice or clearly mark "Demo, not charged."
3. **P9-03/05** (High) — Make join/renewal success copy status-accurate ("pending approval"); show next-steps.
4. **P9-04** (High) — Replace "Pay securely"/"Opening app" with truthful screenshot-verification copy; remove sample UPI IDs.
5. **P9-06** (High) — Enable real email/phone verification; reflect honest verified state.
6. **P9-07** (High) — Honor QR regeneration grace (or warn admins it's breaking-immediate).
7. **P9-09** (High) — Stop rendering fabricated numbers as exact; mark estimates until Phase 8 fixes land.
8. **P9-10/11/12/26** (Med) — Build notification center, "My Queries," referral status, add-on-at-checkout (discoverability + integrity).
9. **P9-13/14/16/17/19/20/24** (Med) — Occupancy clarity, profile-gate CTA, skeletons, confirm-before-celebrate, accessibility, server-authoritative status, expiry copy.
10. **P9-18/21/22/23/25** (Low) — Remove placeholders/demo seams, friendly errors, declutter home, consistent empty states.

---

## 10. Feature Checklist (Phase 9 scope — UX)
| Q | Verdict |
|---|---|
| Usable | Visually yes; behaviorally misleading. |
| UI clear | Mostly; some dense screens (member home, analytics). |
| UX smooth | Until the first broken promise (notifications/payment). |
| Edge cases | Loading=spinner only; errors leak `$e`; empties inconsistent. |
| Abuse/hack | Honor-system payments + self-verify gameable (Phase 6/7). |
| **Trust** | **Critical failure — UI confidence ≫ system capability.** |
| Production-ready (UX) | **No** — trust + notifications + payment must be fixed first. |

---

**Limitations honored:** No live render/emulator — accessibility, overflow, and contrast flags (P9-19, small-screen sims) are code-inferred and need on-device confirmation (Phase 13). Behavioral claims are grounded in cited code; financial/rule failures inherited from verified Phases 6–8.

**Next:** `Start Phase 10` — Security Audit.
