# SILENCE — Implementation Plan (UI/UX → Flow → Schema overhaul)

> Companion to `UIUX_OVERHAUL_DECISIONS.md` (the “what & why”). This file is the **“how & in what
> order.”** Built from the **actual codebase** inventory, not the stale spec. Execute top-to-bottom;
> each batch is small and reviewable. **Ask before adding anything not already decided.**
>
> Legend: 🆕 new screen/widget · ♻️ refactor existing · 🔌 wiring/function · 🗄️ schema · 🗑️ delete

> **CURRENT STATUS (2026-06-09):** Completed batches — A0 foundation · Notification center ·
> Join/Renewal payment reframe · Admin Payment Methods · member_home revamp (error/offline, expiry
> fix, bell, hold reframe, card redesign, session cards, recent-activities IST) · Scanner
> multi-session + 10-min disable · **Admin Hold/Resume** · **seat-change Reject** ·
> **Holiday management (rename "Close Today")** · **Contact Admin / Queries loop** ·
> **member screens states-pass (errors/honesty)**. Project-wide `flutter analyze` = **0 errors**
> (remaining items are pre-existing infos/deprecations).
> **NEXT:** Phase C **applied to live DB ✅** (2026-06-11) → optional §E `library_closures` drop +
> on-device smoke test of the touched flows.
>
> **Member-profile fixes + payments RLS hotfix — done (2026-06-12):** **member_detail_screen** —
> fixed the **Activity-tab freeze** (Activity/Payments were a bare `ListView.builder` inside a
> `SingleChildScrollView` → unbounded-height layout crash after build; now `shrinkWrap` +
> `NeverScrollableScrollPhysics`, which also renders the Payments list when rows exist); added
> **date-wise attendance analytics** (range picker default = this month + summary + per-day
> check-in/checkout/study-time, computed from loaded data); added a **per-member export** (header
> Export → Attendance/Payments checkboxes + date range + CSV & PDF, reusing `PdfExporter`/`CsvExporter`).
> **Transfer** action hidden when the admin owns one library (`member_detail._canTransfer` +
> `members_sub_tab` `ownedLibraryCount` from `reservations_tab`). **add_member_wizard** — compensating
> rollback (free seat + exit the new membership) so a failed step leaves no ghost member; dup-guard now
> also blocks `pending`. **Payments RLS hotfix:** `payments` had no admin-INSERT policy → admin
> add/approve inserts were RLS-rejected (42501 = "You don't have permission"), which also left Payments
> tabs empty. New `silence_app/migrations/2026-06-12_payments_admin_insert_rls.sql` + folded into
> canonical schema. **0 new analyze issues.** ✅ migration APPLIED to live DB (2026-06-18) — admin
add/approve payment inserts succeed, Payments tabs populate.
>
> **Reservation tab + add-member polish — done (2026-06-11):** **member_detail_screen** blank-screen
> fixed (eager `IndexedStack` that built all 5 tabs → **active-tab-only** build selected by tab name +
> a per-tab **error boundary**; null-`memberId` guard that was an infinite spinner). **members_sub_tab**
> — member **card tappable → full profile** (refresh on return), **⋮ moved to top-right corner**,
> **"View Details" removed**, menu = Renew / Hold-Resume / Transfer / Remove (real `memberships`+`seats`
> writes + member notify + audit + list refresh, confirm dialogs, `friendlyError`). **layout_sub_tab**
> — **reconcile-from-memberships on read + best-effort DB self-heal** (fixes "assigned seat shows
> vacant"); vacant-seat **"Assign Member"** is now a real picker of seatless members in that shift;
> occupied-seat "Renew"/"View Member Details" → working profile. **add_member_wizard** — seat-occupy
> write **moved before the payment insert**; duplicate-guard + `friendlyError` keep the wizard open on
> failure (no false success / no draft-save-on-error). **addon_services** — removed the "Total Available
> Inventory" box (defaults `total_inventory: 0`). **add_member_step2 ("Step 3" plan UI)** — add-on
> **price-type chip** (Monthly/One-time) + plan pills render only when that duration's price is
> configured (> 0). **0 new `flutter analyze` issues** across all files. Committed `30da253`.
> **`AGENTS.md`** added at repo root — cross-agent (e.g. Codex) onboarding: read-order + golden rules +
> hard constraints + current git state (SpecKit marker block preserved).
>
> **Offline cached membership card — done (2026-06-10):** member_home now **caches memberships +
> profile** (`member_memberships` / `member_profile` via `CacheService`) on every successful load.
> When `_loadInitialData` throws (offline/transient), it falls back to `_loadFromCache()` instead of
> the blocking error screen — rebuilds `_allMemberships`/`_myMemberships`/`_pastMemberships` from
> cache, forces the **not-checked-in card** (honest: live attendance can't be trusted offline), and
> sets `_isOfflineCached`. A slim **OfflineBanner** ("You're offline — showing saved data. Tap to
> retry.") sits above the content and re-runs the load on tap. Only shows the full error state when
> there's **no** cached membership. No fake/stale "checked-in" state.
>
> **Stats loading skeleton — done (2026-06-10):** **member_home**'s full-screen bare spinner
> replaced with a **layout-matching skeleton** (`_buildHomeSkeleton` using `Shimmer` + `SkeletonBox`
> from `widgets/states/`) — header + attendance + streak + quick-action tiles + activity rows — so the
> page doesn't jump when data lands. (member_analytics already used `_buildShimmerLoading`; admin
> dashboard/analytics already use skeletons; the remaining analytics `CircularProgressIndicator`s are
> a real attendance-% gauge + an in-button export spinner, correctly left as-is.)
>
> **Member home cards UI — done (2026-06-10):** **Streak card** reworked — week is now a fixed
> **Sunday→Saturday** calendar week (was a rolling 7 days, which mislabelled the columns); **today**
> is ring-highlighted, **future** days dimmed; added a details row (**This week N/7 · Best streak ·
> Total days**). **Quick Actions** got a section **title** and the 3 non-essential actions were
> replaced — now **Contact Admin · Refer & Earn · Renew · Find Library** (dropped Join-with-Code +
> Seat-Change from the row; both still reachable — join-with-code on the Explore screen, seat-change
> in the membership card ⋮ menu; deleted the now-dead `_openJoinWithCodeSheet`, which also had a raw
> `$e`). **Refer & Earn** opens an honest sheet with the real `referral_code` (generated/persisted if
> missing) + Copy + `Share.share`. **Renew** opens the real `RenewalScreen` for the primary
> membership. **Recent Activities** card is now **height-bounded (max 340) + internally scrollable
> (Scrollbar)** so it stops growing as activities accumulate. *(Deferred, no data model yet: dues
> banner on card, offline cached membership card — will not fake these.)*
>
> **Member screens states-pass — done (2026-06-09):** Swept member-facing screens for
> dishonest UI + raw `$e`. **member_explore**: killed the **dishonest "Suggestion submitted ✓"
> fallback** (it showed success even when the `leads` insert threw) — now shows `friendlyError` +
> keeps the form for retry; join-with-code + load errors use `friendlyError`. Replaced raw `$e`
> shown to users with `friendlyError(e)` in **member_profile_edit** (upload/verify/save),
> **member_privacy_security** (6 sites: settings/password/disconnect/export/schedule+cancel
> deletion), **member_notification_preferences** (save), **member_help_support** + **help_support**
> (launch/upload/submit), **member_history_tab** (load `_errorMessage` + re-submit + export),
> **member_analytics_tab** (session-logs `snapshot.error`). Removed 2 pre-existing dead imports.
> *(Agent-flagged "syntax errors" in the help screens were false — `flutter analyze` = 0 errors.)*
> **Still pending in member_home:** dues banner on card · offline cached card · broader declutter.
>
> **Contact Admin / Queries — built (2026-06-09):** New `lib/screens/contact_admin_screen.dart`
> (member hub titled **"Contact Admin"** with **2 sub-tabs: "My Queries" + "Replies"**; **submit-form
> compose** — NOT a chat — via "New query" FAB with a library picker when the member has >1 library;
> IST stamps; honest loading/empty/error states; pull-refresh). Member entry points: a **"Contact
> Admin" quick-action** on the home dashboard (**replaced the redundant "Scan QR" quick action** —
> scanning stays on the floating QR FAB), plus **profile tab → "Contact Admin"**. (Replaces the
> earlier `my_queries_screen.dart`, now deleted.) `admin_home._showManageQueries` rewritten:
> refreshable (StatefulBuilder), each query **tappable → reply sheet** that writes canonical
> `admin_reply` + `status='replied'` + `replied_at` **and notifies the member** (`notifications` type
> `query_reply`) — was read-only (loop dead at both ends). Admin side keeps the name **"Queries"**.
> Uses canonical `queries` columns (`message/status/admin_reply/replied_at`). The per-state "Contact
> Library" buttons (pending/trial/expired/hold) still work (same `queries` table) and now also surface
> in Contact Admin. *Phase C note: `queries` live-DB drift — `help_support_screen` inserts
> `subject`/`type` not in committed schema; old admin code used status `'resolved'` (CHECK allows
> open/replied/closed). Reconcile in Phase C.*
>
> **Holiday management — built (2026-06-09):** New canonical `lib/utils/holiday_service.dart`
> (`Holiday` model + `scheduled_closures` with **`start_date`/`end_date`** range; fetch /
> `holidayOn`(range-aware) / `todaysHoliday` / `addHoliday`(single+range) / `removeHoliday` /
> `notifyMembersOfHoliday` bulk insert). Rewrote `scheduled_closures.dart` → **"Holidays &
> Closures"** screen (single-day/range toggle, reason, notify, cancel/remove, honest
> loading/empty/error states, **removed the fake fallback list + dishonest "success" snackbar**).
> `admin_home`: Quick Action **"Close Library" → "Holidays"**; the sheet now writes the **correct
> table** via the service (was the dead `library_closures.closed_date`), can **close today** or open
> the full manager, and the dashboard shows a **"Today is a holiday"** banner. `qr_scanner`: closure
> check is now **range-aware on `start_date`/`end_date`** (was querying a non-existent `closed_date`).
> `member_home`: detects today's holiday per joined library → **"Library closed today" card +
> disabled check-in + FAB hidden** (streak-protected copy). `admin_analytics_tab`: **"N holidays in
> <month>"** card (range-aware day count). Notif icon for `holiday`/`closure` already existed.
> *Resolved a 3-way schema conflict: admin wrote `library_closures.closed_date`, the screen wrote
> `scheduled_closures.closure_date`, the scanner read `scheduled_closures.closed_date` — none matched
> the committed schema (`scheduled_closures.start_date/end_date`). All now standardized on it.
> Phase C still: drop/migrate the dead `library_closures` table.*

---

## Guiding constraints
- Source of truth = existing code. Keep warm-orange (`#E65C00`) Material 3 look; **refine, don’t redesign**.
- Every data surface gets honest **loading / empty / error / offline** states.
- **No fake UI**: no `Future.delayed` “payments”, no “Simulated deep link”, no always-positive stubs,
  no success before backend confirms.
- Run `flutter analyze` after each batch; keep a baseline first (`analyze_*.txt` exist at repo root).

---

# PHASE A — UI/UX layer
*Goal: every screen looks right and has every state; new screens exist (even if wired in Phase B).*

### A0 — Foundation ✅ DONE (clean `flutter analyze`)
> Built: `lib/theme/app_colors.dart` (tokens), `lib/widgets/states/` (`shimmer_box`, `loading_state`,
> `empty_state`, `error_state`, `offline_banner`, `states.dart` barrel), `lib/utils/error_messages.dart`
> (friendly mapper + `isNetworkError`), `lib/utils/upi_launcher.dart` (`detectUpiApp`, `buildUpiUri`,
> `launchUpiPayment`). Import states via `package:silence/widgets/states/states.dart`.

### A0 — Foundation (do FIRST; everything else depends on it)
- 🆕 **4 reusable state widgets** in `lib/widgets/states/`:
  - `LoadingState` (skeleton/shimmer, not just a spinner)
  - `EmptyState` (icon + message + optional CTA)
  - `ErrorState` (friendly message + **Retry**; never raw `$e`)
  - `OfflineBanner` (reusable top banner)
- 🆕 **Design tokens pass**: confirm a single source for colors/spacing/typography (reuse existing
  theme). Document the palette + hierarchy so all new screens match.
- 🆕 **UPI deep-link helper** `lib/utils/upi_launcher.dart`: builds `upi://pay?pa=&pn=&am=&tn=` and
  detects app (GPay/PhonePe/Paytm) from handle suffix; returns icon + label. (Used by A2 join/renewal.)
- 🆕 **Friendly-error mapper** `lib/utils/error_messages.dart`: maps PostgREST/Supabase exceptions to
  human copy (used by `ErrorState` and snackbars).

### A1 — Shared / auth / entry
- ♻️ `splash`, `auth_screen`, `role_selection` — state polish, remove any demo seams.
- 🆕 **Verification screens (DISABLED)**: build email/phone-OTP verify UI + a clearly **disabled**
  “Verify” entry point. Remove mock `123456` and the self-set “verified” flag/badge.

### A2 — Member screens
- ◐ **`member_home`** (biggest — doing in safe sub-batches):
  - ✅ Sub-batch 1: crash screen → friendly offline-aware **ErrorState** (retry, no raw `$e`);
    **expiry “0 days left” bug fixed** via date-only `_daysLeftDateOnly` helper (used in card + expiring
    stage; honest copy “ends today” / “N days left”).
  - ✅ Sub-batch 2a: header **bell** now opens the real `NotificationsScreen` (was opening a hidden
    duplicate “all caught up” stub — now deleted) + **unread badge** from the real `notifications` table
    (`_unreadNotifications`, refreshed on return).
  - ✅ Sub-batch 2b (hold reframe): **removed member-side “create hold”** (deleted `_openHoldRequestSheet`
    + its More-options entry + helper + now-unused `calendar_picker` import); on-hold stage now has a
    **“Request to resume early”** button that routes to the library query inbox pre-filled (honest, reuses
    existing infra). *(Admin-creates-hold + un-hold approval = A3/Phase B.)*
  - ✅ Sub-batch 2c (user-requested revamp): **library card redesign** (21px bold name, 2-col labeled
    grid: Seat/Shift/Timing/Joined/Plan/Price, shift timing in IST 12h via `_formatShiftRange`, joining
    date, overflow-safe), **active card = Renew-only** (removed Seat Chg + ▼ dropdown → seat-change/exit
    no longer on card); **session cards**: previous session now shows below the running session
    (`showPrev` fix) + multi-session aware fetch, relative titles "Today's/Yesterday's Session"
    (`_relativeDayLabel`); **Recent Activities** times fixed to **IST** + added join/renewal events
    (payments/seat/hold already present), cap 8→15.
  - ✅ Scanner: **multi-session per day** (removed "Already Checked In today" block) + **10-min checkout
    cooldown disabled** (`minCheckoutMinutes=0`, re-enable by setting to 10) + honest check-in hint.
  - ☐ Still pending: **dues banner** on card; offline **cached card**; broader declutter.
- ♻️ **`qr_scanner_screen`**: multi-session-friendly copy; **expired → warning card** (“expired /
  expiring — renew soon”) but **still allow**; honest offline copy (“saved, pending sync”, not green ✓
  for the ineligible); fix dead-end “contact admin/report” actions to use real data. *(logic in Phase B)*
- ✅ **`join_flow_screen`** + **`renewal_screen`** payment reframe: hardcoded UPI (`owner@upi…`) replaced
  with **real deep-link app buttons** from `social_links.upi_ids` (`detectUpiApp` + `launchUpiPayment`,
  `upi://pay`), copy-UPI, **“I have made this payment”** required declaration, honest note (admin verifies
  externally), **optional** screenshot (no longer mandatory), honest success copy (“Request sent”, not
  “🎉 Submitted/Done”). Loading/error use state widgets. Removed “Simulated deep link”.
  *Note: the UPI card helpers are duplicated across both screens — candidate to extract a shared
  `UpiPaymentCard` widget later. Add-on persistence still pending (Phase B).*
- ✅ **Notification center** (replaced `notifications_screen` stub): real `notifications` read, skeleton/
  empty/error states, tap-to-mark-read, mark-all-read, pull-to-refresh, type-based icons. **Also fixed
  2 broken notification inserts** in `requests_sub_tab.dart` (`is_read`/`created_at` → schema-valid).
  *Pending (Phase B): bell **unread-badge** count in `member_home`. **FCM push ✅ SHIPPED** (2026-06-17): `device_tokens` + `send-push` Edge Function + Database Webhook, web-verified; device test/foreground/hardening pending.*
- 🆕 **“My Queries”** screen: member’s queries with status + admin replies. *(wiring Phase B)*
- ♻️ `member_explore`, `member_history_tab`, `member_analytics_tab`, `member_profile_tab`,
  `member_profile_edit`, settings/privacy/help/about/terms screens — apply the 4 states; friendly errors;
  remove `app_settings`-style fake buttons (make real or remove); honest account-deletion copy.
- ♻️ **Member “request to lift hold”** entry (replaces the removed member-side *create*-hold UI).

### A3 — Admin screens
- ✅ **“Payment Methods” section**: new `PaymentMethodsScreen` (cash toggle + UPI IDs list with
  `detectUpiApp` badges, add/remove, **merge-save** into `social_links`), wired into the admin profile
  grid. 🗑️ deleted dead `payment_setup.dart`. **Also fixed a real bug:** the Social Links sheet was
  overwriting the whole `social_links` JSONB (wiping `upi_ids`/`cash_enabled`) → now merges.
- ♻️ **`admin_home` dashboard**: cards for **expiring/expired members** (red), **“Today is a holiday”**
  banner, pending-actions surface (new joinings/requests). Declutter + states.
- 🆕 **Holiday management** (rename/expand “Close Today”): single-day / date-range / scheduled, with
  **reason**, plus **cancel/remove**. *(writes correct table + notify in Phase B)*
- ♻️ **`requests_sub_tab`**: approve **and reject** for join / seat-change / **un-hold** requests;
  honest copy; no “confirmed ✓” without persistence; disable-on-submit. *(Seat-change **reject** added —
  reason dialog + member notification + audit; join reject already existed.)*
- ♻️ **`layout_sub_tab`**: real **Reassign dialog** (vacant seats in same shift); release/maintenance/
  delete with occupancy guards + member-sync messaging. *(sync logic Phase B)*
- ✅ **`member_detail_screen`**: **admin Hold / Resume membership** — Hold dialog (days + reason) sets
  `status='hold'` + records the hold window in `hold_requests`; Resume extends `end_date` by the days
  actually paused (today − hold start) and reactivates; both notify the member. Replaces the removed
  member-side create-hold. Member on-hold card copy made honest (no wrong "resumes on" date).
- ♻️ **`member_detail_screen`**: **admin hold member** action (X days) + un-hold; force-exit dues
  handling copy; add-ons shown; manual check-in consistent.
- 🆕 **Member-to-Member referral config** (admin profile tab): activate + set extra days for referrer.
- ♻️ **Member-to-Admin referral screen**: show conditions (refer a library owner → setup + add members +
  30-day use → ₹200 / membership discount → contact app-owner).
- 🆕 **Member transfer** flow (admin moves a member between own libraries). *(wiring Phase B)*
- ♻️ **`subscription_screen`**: real plan cards — **Free + 2 paid (mock)** *(values: TBD from user)*;
  remove payment theatre/fake invoice/“simulated mode”; “Upgrade” → honest “Free during beta / contact
  owner”. *(Razorpay last)*
- ♻️ **`audit_log_screen`**: render real columns (no fabricated generic rows). *(writer fix Phase B)*
- ♻️ `admin_analytics_tab`: add **holiday card** (“N holidays this month”); apply states; mark
  computed figures honestly until Phase B/C correctness lands.
- ♻️ Remaining admin settings screens (shifts/pricing/business-rules/branding/qr/addons/closures/
  referrals/exports/announcements/verified-badge): 4 states + friendly errors + honest copy.

**Phase A exit criteria:** every screen renders all states, no fake/simulated/placeholder strings, all
new screens exist (wired or stubbed-honest), `flutter analyze` clean vs baseline.

---

# PHASE B — Navigation + Flow + Functions
*Goal: wire each screen to honest, recoverable behavior.*

> **Phase B progress (2026-06-10):** ✅ **B1 real payment amount** — `_approveJoinRequestTransaction`
> now derives amount from the **shift price for the plan + selected add-ons − `discount_amount`**
> (`_computeApprovalAmount`); the hardcoded `1500/4000/7500` is gone. ✅ **B2 add-ons persist** —
> join_flow writes `selected_addon_ids` onto the request (graceful: retries without the field if the
> column is absent → **Phase C must add `join_requests.selected_addon_ids`**); on approval the admin
> inserts **`member_add_ons`** rows + folds add-on price into the amount. ✅ **B3 notify** — member is
> notified on join/renewal **approve** (`join_approved`) and **reject** (`join_rejected`), and on
> **payment confirm/reject** in member_detail (`payment_confirmed`/`payment_rejected`). ✅ **B4 audit**
> — new `lib/utils/audit_logger.dart` writes the **canonical** `audit_log` (admin_id/library_id/action/
> details JSONB, display fields inside `details`); `requests_sub_tab._logAudit` + `audit_log_screen`
> reader aligned to it (legacy flat-column fallback kept); approve/reject/payment now audit. ✅ **B5
> seat reassign/release sync** — `layout_sub_tab`: **Reassign** is now a real dialog (vacant seats in
> the **same shift** → frees old seat + occupies new + updates `memberships.seat_id` + notifies +
> audits; was a no-op that opened the layout editor); **Remove from Seat** now also nulls the
> member's `memberships.seat_id` (no more seat↔membership desync) + notifies + audits; race-checked.
> ✅ **B6 honest subscription screen** — `subscription_screen.dart` rewritten to 3 **mock plans**
> (Free / Pro ₹499 / Premium ₹799); **removed** the Razorpay "mock checkout" sheet, simulated
> UPI/Card/Netbanking rows ("All Indian banks integrated"), `Future.delayed` upgrade, **fake invoice**,
> and the **self-activation** (prefs + users.subscription write). Now: "Your plan: Free · FREE DURING
> BETA", paid plans show **"Coming soon"** with an honest no-charge explainer; Razorpay deferred.
> ✅ **Account deletion + UX fixes (2026-06-10):** member delete now needs a **type-DELETE** confirm
> + explicit warnings; **member_home reflects it** — red "scheduled for deletion" banner (tap →
> Privacy) + **check-in disabled** (FAB hidden + `_openQRScanner` guard); **admin** got the same
> feature (danger zone, type-DELETE, honest `scheduled_for_deletion` request flag — no real purge,
> that's server-tier). **Admin profile** now has a **Subscription & Billing** item (`/admin/subscription`).
> **Contact Admin**: removed the redundant **Replies** sub-tab (My Queries already shows replies
> inline) — now a single screen.
>
> ✅ **Consistency + dup-prevention (2026-06-10):** global **status-bar style** (orange + light icons)
> via `main()` `SystemChrome` + `AppBarTheme.systemOverlayStyle` → safe-area/top-bar match the brand on
> every screen. **Dup-prevention:** member join/renewal submit buttons already gated on `_isSubmitting`;
> added an **`_isApproving` re-entrancy guard** to the admin approval transaction (fast double-tap can't
> create two memberships/payments). **Honest status of remaining Phase B:** ✅ **FCM send** (server
> tier shipped: `send-push` Edge Function + webhook; web-verified — device test/hardening pending) ·
> ⛔ **claim/link** (needs phone OTP, disabled by decision) ·
> 🟡 **referral** (share works; auto-credit after 30-day use needs a server job; admin config screen not
> built) · **member transfer** (large multi-library flow — deferred) · **owner-visibility of deletion**
> (needs an app-owner console). The pure-client items are done; the rest are server/OTP-gated and won't
> be faked.

- 🔌 **Payments (member↔admin, out-of-app):** join/renewal read admin `social_links.upi_ids` → deep-link
  buttons → **“I have paid”** sets request to *awaiting-verification* → admin **verify → confirm** →
  membership active + payment row with **real amount (shared pricing fn: price − discount)**.
- 🔌 **Notifications:** fix all insert sites to **schema-correct columns** (`title/body/data/read_at`),
  add notify on approve/reject/hold/seat-change/holiday/announcement; build reader query + mark-read; add
  **FCM** (token registration + server send path) — *(FCM send needs the eventual server tier; in-app first)*.
- 🔌 **Central audit helper** called by every mutating admin action (approve, reject, confirm, exit, seat
  ops, holiday, price change) with schema-valid rows; reader aligned.
- 🔌 **Holidays:** write `scheduled_closures` (the table the scanner reads) for today/range; notify
  members; member dashboard + scanner **disable check-in on holiday** (UI from Phase A); analytics counts.
- 🔌 **Seat ops:** reassign/release/maintenance/delete update the affected `memberships` row + notify;
  reassign picks a vacant seat in the same shift; concurrency-safe conditional update.
- 🔌 **Admin holds member:** set hold window, push expiry by held days on resume; notify; **un-hold
  request** loop (member request → admin approve).
- 🔌 **Referrals:** (a) member→member crediting when conditions met (extend referrer membership);
  (b) member→admin = informational + contact path (no auto-credit).
- 🔌 **Add-ons:** persist selection to `member_add_ons`; surface in member detail.
- 🔌 **Member transfer:** write `transfers` + new membership + free/occupy seats + notify.
- 🔌 **Multi-session check-in:** allow repeat sessions/day; session list; remove blanket block; expired
  → warning-but-allow; honest offline validation against cached membership/closure.
- 🔌 **Manually-added member claim/link:** phone-based linking (OTP-gated when verification is enabled);
  dedupe guard.
- 🔌 **Queries reply:** admin reply persists; member “My Queries” reads it; notify on reply.
- 🔌 **Account deletion (honest):** request flag + owner visibility + honest status copy (no real purge
  yet — that’s server-tier later).
- 🔌 **Recovery & dup-prevention (client layer):** disable-on-submit everywhere; member-side **draft
  persistence** for join/renewal (reuse `draft_service`); fail-closed on dues/closure gates.

**Phase B exit criteria:** no success shown for unpersisted actions; every admin action audits + notifies;
member always sees the true state of their request/membership.

---

# PHASE C — Backend schema (the “heavy” reconciliation)
*Goal: one canonical schema; kill duplicates/conflicts; add the missing guards.*

- 🗄️ **Reconcile `expenditures`** (4 conflicting shapes; Title-Case vs CHECK) → one schema + category
  case fix so inserts stop failing.
- 🗄️ **Reconcile closures**: pick **`scheduled_closures`** canonical; drop/migrate `library_closures`.
- 🗄️ **Add migrations for the 7 undocumented tables** (`settings`, `streaks`, `member_daily_stats`,
  `leads`, `verification_requests`, `draft_members`, + closure) so clean deploys don’t break.
- 🗄️ **Wire orphan tables**: `member_add_ons` (now written on approval by Phase B), `transfers`.
- 🗄️ **Add `join_requests.selected_addon_ids`** (UUID[] or JSONB) — Phase B writes it gracefully
  (retries without it); the column must exist for member add-on selections to reach approval. Also
  reconcile `audit_log` (canonical `details` JSONB now used) + `queries` drift (`subject`/`type`,
  `resolved`→`closed`).
- 🗄️ **Uniqueness / idempotency**: partial-unique indexes on `memberships` (active/trial),
  `attendance` (per member/library/day), `join_requests` (pending) → kills duplicates.
- 🗄️ **Concurrency-safe seats**: conditional update / version column.
- 🗄️ **(Related security track — recommend doing alongside)**: object-scope storage + least-privilege
  RLS + lock identity/role/subscription columns (audit Wave 0). Flag for the user before touching, since
  it needs the live Supabase project.

**Phase C exit criteria:** clean deploy from one schema; no conflicting tables; duplicates/races guarded.

---

## Suggested execution rhythm
1. **A0 foundation** → then **A2/A3 in parallel batches** (member + admin), screen-group at a time,
   each behind review.
2. After Phase A sign-off → **Phase B** wiring in the same screen-group order.
3. **Phase C** last (schema), with a **re-audit/regression** of touched areas (esp. live-DB items).

## Open inputs needed from user
- **Subscription plan values**: names, prices, feature bullets for Free + 2 paid (for A3 `subscription_screen`).
- Phase C: confirm canonical choices when we get there (expenditures shape, which closure table, etc.).

---

*This plan is intentionally incremental — we land one screen-group at a time so nothing big breaks.*



---

## Post-plan work log (where the latest work is documented)
The 3-phase plan above is complete; ongoing user-directed work is logged in dedicated docs:
- **`LAYOUT_SEAT_OVERHAUL.md`** — admin seat-layout overhaul (batches 1–3 + round-2 screenshot fixes).
- **`RESERVATION_FIXES_2026-06-15.md`** — reservation/attendance/requests batch committed in `2a55f4d`
  (manual attendance, "Manual" tag, admin renew sheet, requests payment/join decoupling, admin-home
  attendance redesign, permanent eligibility-gated member QR FAB). ⛔ Includes a **pending migration**:
  `silence_app/migrations/2026-06-15_join_requests_payment_status.sql`.
- See `CLAUDE.md` §0 + `AGENTS.md` §5 for the canonical current state.

### 2026-06-22 → 23 — Overtime / check-in approvals + Exports overhaul
- **Shift overtime + out-of-shift check-in approvals** (committed `5e9212e`). ⛔ Includes an **applied**
  migration `silence_app/migrations/2026-06-22_overtime_and_checkin_approvals.sql` (attendance overtime
  columns, `checkin_approvals` table + RLS, `consume_checkin_approval()` RPC, `process_shift_overtime()` cron).
- **Exports overhaul** (committed `cf3bc89`): unified `PdfExporter` / `CsvExporter` (one engine, no second
  code path). Redesigned PDF — brand letterhead band (white logo) + footer (black-name-with-tag), tighter
  margins, KPI tiles, zebra tables with totals, embedded **Noto Sans** so the ₹ glyph renders, IST times,
  Members Roster gains a **Joined** column. Machine-friendly CSV (header row 1, numeric INR columns, sortable
  dates, trailing summary, UTF-8 BOM). **Fixed the web CSV crash** (`Unsupported operation: _Namespace`) by
  branching on `kIsWeb` — bytes via `XFile.fromData` on web, temp file on native.
- **Preview screens** (new, `lib/screens/reports/`): `attendance_export_preview.dart` (date-wise + faceted
  member-wise — Shift/Floor/Category + member checklist, default All) and `revenue_report_preview.dart`
  (date-filtered, working CSV/PDF). Admin Analytics attendance tab + Export Center route to them; Export
  Center now asks the period on each export tap and offers date-wise/member-wise for the Attendance Log.
- **No DB change in the exports batch.** Canonical current state stays in `CLAUDE.md` §0.
