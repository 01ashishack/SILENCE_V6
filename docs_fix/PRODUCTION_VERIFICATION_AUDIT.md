# SILENCE — Production Verification Audit

> Goal: validate every user flow, screen, button, navigation path, permission and
> runtime behaviour before declaring launch-ready, after audit fix Waves 0–9.
>
> **Methodology & honest limitation.** This is a **static** verification: code-path
> tracing, route-table integrity, RLS/permission mapping, and the automated CI
> gates (analyze + unit/integration tests + schema-drift + release-compile). Per
> the project's golden rules the agent has **no live-DB and no device access**, so
> anything that can only be proven by running the app on a device or against the
> live Postgres/RLS is listed in §7 "On-device verification checklist (USER must
> run)". Static analysis ≠ on-device testing — that distinction is kept explicit.

Last verified commit: `7609837` (Wave 8.4 + Wave 9). Branch `main`.

---

## 1. Automated quality gates (verified green by the agent)

| Gate | Command | Result |
|------|---------|--------|
| Static analysis | `flutter analyze` | **2 issues** — both pre-existing baseline `use_build_context_synchronously` infos (`admin_profile_tab.dart:2108`, `member_home.dart:534`). **0 new** across all Wave 0–9 edits. |
| Unit / integration tests | `flutter test` | **21 passed** (`time_utils_test`, `storage_urls_test`, `moderation_service_test`). |
| Schema-drift | `dart run tool/check_schema_drift.dart` | **OK** — every migration `CREATE TABLE/FUNCTION` is folded into `supabase_schema.sql` (fixed 6 historically-unfolded RPCs in this pass). |
| Release compile | `flutter build apk --release` (CI) | Wired in CI (`.github/workflows/ci.yml`); runs on push/PR. Debug-signed fallback for CI; strict signing gated behind `requireReleaseSigning`/`CI` for the real release pipeline. |

CI now runs all four on every push/PR to `main`, so these gates stay green going forward.

---

## 2. Navigation / route integrity

The `MaterialApp.routes` table in `lib/main.dart` registers **56 named routes**. Every
*literal* `pushNamed` / `pushReplacementNamed` / `pushNamedAndRemoveUntil` target found
in `lib/` resolves to a registered route (spot-checked across splash→auth→role→home,
member profile/settings/legal, admin settings, setup stages, member detail, add-member,
renewal, query, analytics, library-history, policy screens, notifications).

**Dynamic-route notes (low risk, app-controlled):**
- `notifications_screen.dart` deep-links via `data['route']` from a notification row.
  These values are written by the app's own inserts (always registered routes) and the
  navigation is wrapped in try/catch. There is **no `onUnknownRoute` fallback** on
  `MaterialApp`, so a malformed/stale `route` value could throw. **Recommendation
  (post-launch, optional):** add an `onUnknownRoute` that routes to home — cheap safety
  net. Not a launch blocker because routes are not user-supplied.
- `policy_screens.dart` navigates via `r.route` from a static list whose values match
  registered `/policy/*` and `/member/*` routes.

---

## 3. Permissions / RLS matrix (key tables)

| Table | Read (SELECT) | Write | Notes |
|-------|---------------|-------|-------|
| `users` | self + tenant-scoped (admins see their library members; cross-lib lookup via `find_user_by_contact` RPC) | privileged columns locked (role/subscription/verified); owner can't edit member email/phone (`guard_user_contact_columns`) | Wave 1/3 |
| `payments` | member-own + owner | member insert forced `status='pending'` (trigger); relationship-checked insert | Wave 0/3 |
| `attendance` | member-own + owner | member insert requires owning membership + library/shift match + active/trial | Wave 3 (**highest regression risk** — see §7) |
| `seats` | **owner OR member-of-library** (was public) | owner-only writes; atomic RPCs | Wave 8.4 — migration authored, **apply+test pending** |
| `seat/shift/hold requests` | member-own + owner | member insert pinned `status='pending'` | Wave 0 |
| `add_ons` | public (price catalog, no PII) | owner-only | intentionally public for prospective joiners |
| `notifications` / `audit_log` / `badges` / `referrals` | scoped | relationship-scoped inserts | prior P5-08 |

Atomic, owner-checked SECURITY DEFINER RPCs back the dangerous multi-step flows:
`approve_join_request` (v3 pay-later), `reassign_seat`, `approve_seat_change`,
`transfer_member_shift`, `exit_my_membership` (dues-guarded), `change_my_role`,
`renew_membership`, account recovery/purge.

---

## 4. Critical user-flow traces (static)

Each flow was traced through its screens/RPCs/RLS touchpoints. "Static OK" = the code
path is wired correctly and the permissions allow it; the on-device confirmation is in §7.

1. **Auth → role → onboarding.** `splash` reads session+role → routes to `/auth`,
   `/role-select`, `/account-frozen`, `/admin/home`, or `/member/home`. Role flips are
   blocked except via `change_my_role()` (7-day window + data wipe). Static OK.
2. **Member join → admin approve (pay-later + correction).** Join writes a `join_requests`
   row (status pinned pending); admin reviews via `requests_sub_tab` → `approve_join_request`
   v3 (atomic membership+seat+payment, pay-later → payment `pending`, correction-note path).
   Member can't read seats of unrelated libraries (Wave 8.4) but join flow doesn't read
   seats. Static OK.
3. **Check-in / check-out (online).** `qr_scanner` validates QR version, closure day,
   active membership, shift window / overtime approval, then inserts/updates `attendance`.
   Member insert RLS requires the owning membership (Wave 3). **On-device verify required**
   (RLS predicate correctness).
4. **Check-in / check-out (offline).** Decision now uses the **latest queued scan**
   (Wave 7.1) not "any unsynced check-in"; sync is FIFO; failed scans dead-letter
   (`status='failed'`) with a visible "couldn't sync" banner (Wave 7.2); honest "Saved
   offline — pending sync" label (Wave 7.3). Local sqflite migrates v1→v2. Static OK;
   on-device offline cycle recommended.
5. **Payments.** Member proof submit stores object **path** (Wave 2), signed-on-view at
   admin review; member can't self-confirm (trigger forces pending). Static OK.
6. **Seat reassign / seat-change approve.** Both go through atomic owner-checked RPCs
   (Wave 4) — no client multi-step race. Static OK; concurrent double-book test in §7.
7. **Shift change request → transfer.** Member files request (pending); admin transfers
   via `transfer_member_shift()` with price adjustment. Realtime now library-scoped
   (Wave 6) so the request reaches the right admin's Requests tab. Static OK.
8. **Exit with dues guard.** `exit_my_membership` refuses exit with pending dues →
   member sees pay/contact popup; only admin can mark paid. Static OK.
9. **Explore / search.** Browse capped at 50 (newest); search is server-side `ilike`
   over name/city/code with sanitized input + spinner (Wave 5.3). Doesn't read seats.
   Static OK.
10. **Dashboard.** Count stats use HEAD `.count()` (Wave 5.1); today-feed window uses
    true IST midnight (Wave 8.3); perf indexes back the hot lists (Wave 5.2). Static OK.

---

## 5. Audit-fix regression checklist (per wave)

| Wave | Change | On-device / live check to confirm |
|------|--------|-----------------------------------|
| 0 | schema fold, POST_NOTIFICATIONS, payment/request status guards | member can't insert confirmed payment / approved request |
| 1 | privacy columns + honest privacy UI + leaderboard masking | opt-out hides member on leaderboard; toggle persists |
| 2 | signed-URL-on-view for proof/ID | proof opens >1h after upload; old full-URL rows still open |
| 3 | attendance/payment relationship RLS + owner can't edit member contact | **real member check-in/out + proof submit still work** |
| 4 | atomic seat RPCs | reassign + approve work; concurrent claim → clean error, no double-book |
| 5 | head-counts, indexes, explore search | dashboard numbers correct; explore search returns DB-wide matches |
| 6 | tenant-scoped realtime | library A change doesn't wake an admin on library B; same-lib still live |
| 7 | offline state-loop / dead-letter / label | offline checkin→checkout→checkin cycles correctly; failed scans surface |
| 8.2/8.3 | release fail-fast signing; IST feed | feed boundary correct; `-PrequireReleaseSigning` fails without keystore |
| 8.4 | seats tenant-read RLS | layout/add-member/member-seat still work; unrelated user reads 0 seats |
| 9 | CI + schema-drift + tests | CI green on PR |

---

## 6. Outstanding live-DB / config actions (USER)

1. **Apply `2026-07-08_seats_tenant_read_scope.sql`** (Wave 8.4), then live-test layout
   tab, admin add-member seat picker, a member seeing their own seat, and Explore. Then
   tell the agent to fold it into `supabase_schema.sql`.
2. **Wave 8.1** `send-push` fail-closed on `PUSH_WEBHOOK_SECRET` — do this with the FCM
   rollout (verify the live webhook header is set first, else push breaks).
3. Storage MIME/size limits (A1-9,10) — Supabase dashboard checklist, not code.

---

## 7. On-device verification checklist (USER must run before launch)

These cannot be proven statically. Run on a real device against the live DB:

**Auth/identity:** signup (email + phone), role select, change-role within 7 days,
account freeze/recovery, logout.
**Member:** join (pay-now + pay-later), see pending dues, renew, exit blocked by dues,
seat shown on home, history/analytics, leaderboard privacy opt-out, explore search,
contact-admin query, notifications deep-link taps.
**Admin:** approve/reject join (incl. correction-note), verify payment, manual check-in/out,
reassign seat, approve seat-change, shift transfer with price adjustment, hold, mark dues
paid, library setup stages, add-member + WhatsApp share, marketing posters, audit log,
scheduled closures, verified-badge.
**Permissions (most important — RLS correctness):**
- A real member check-in **succeeds** (Wave 3 predicate not over-tightened).
- A member querying another library's `seats`/`payments`/`attendance` gets **0 rows**.
- A member cannot POST a `confirmed` payment or an `approved` request.
- An owner cannot edit a member's email/phone.
**Concurrency:** two admins reassign to the same seat → exactly one wins.
**Offline:** airplane-mode check-in then check-out then check-in; reconnect → correct sync;
force a sync failure → "couldn't sync" banner appears, scan retained.
**Realtime:** open two libraries on two admin sessions → updates don't cross.

---

## 8. Launch-readiness verdict

**Code/static: ready.** All launch-blocker waves (0–3), scale/integrity waves (4–7) and
the P2 hardening that's safe without live access (8.2, 8.3) are implemented, analyze-clean,
test-green and pushed. CI + schema-drift now guard regressions.

**Conditional gates before declaring launch-ready:**
1. Apply the Wave 8.4 seats RLS migration and pass its live test (§6.1).
2. Complete the §7 on-device checklist — especially the **Wave 3 attendance RLS**
   (a wrong predicate silently blocks real check-ins) and the **8.4 seats scope**.
3. Resolve FCM/push config (8.1) if push is in the launch scope.

Until the §7 device pass is done, the app is **"code-complete & statically verified,
pending on-device sign-off"** — not yet "verified launch-ready", because no agent-side
device/live-DB testing was possible.
