# SILENCE — Pre-Production Audit Fix Plan

> Source: two independent audits (audit-1 `pre_production_audit_report.md`, audit-2
> `PRE_PRODUCTION_TECHNICAL_AUDIT_2026-06-29.md`), **independently verified against source**.
> Verified false-positives are EXCLUDED (see bottom). Ordered into waves by risk + value.
>
> **Working rules (non-negotiable):** migrations are AUTHORED here, the USER applies them to the live
> DB and confirms before fold; `flutter analyze` after every change (0 new issues); no live-DB access
> from the agent; small reviewable batches; commit/push only when asked; preserve working features,
> no gratuitous refactor. Each item is done + verified before the next.

Status keys: ⬜ not started · �doing · ✅ done

---

## WAVE 0 — Safe quick wins (low risk, high value, no behaviour change)

### 0.1 ⬜ Schema drift fold (A2-1, A2-2)
- **Problem:** `device_tokens` table + `auto_checkout_grace_minutes` column are used at runtime but absent
  from canonical `supabase_schema.sql` → fresh deploy breaks push + overtime settings.
- **Change:** `silence_app/supabase_schema.sql` only (fold existing applied migrations
  `2026-06-17_device_tokens.sql` + the grace column/constraint from `2026-06-26_overtime_grace_minutes.sql`).
- **Migration:** none (live DB already has them; this only fixes fresh-deploy reproducibility).
- **Verify:** grep schema for `device_tokens` + `auto_checkout_grace_minutes`; confirm RLS/policies/constraint present.
- **Regression risk:** ~0 (doc/SQL file only, not executed against live DB).

### 0.2 ⬜ Android `POST_NOTIFICATIONS` permission (A2-18)
- **Change:** `android/app/src/main/AndroidManifest.xml` — add `<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />`.
- **Verify:** manifest contains the line; `flutter analyze`.
- **Regression risk:** ~0.

### 0.3 ⬜ Payment self-confirm trigger (A1-1, A2-6)
- **Problem:** `payments` insert RLS = `member_id = auth.uid()` only → a member can POST `status='confirmed'`.
- **Change:** new migration — `BEFORE INSERT ON payments` trigger: if the inserting role is not the
  library owner / service_role, force `status='pending'` and `confirmed_by_admin_id = NULL`. Admin RPCs
  (SECURITY DEFINER) and owner inserts unaffected.
- **Migration:** `2026-07-03_payments_status_guard.sql` (USER applies).
- **Files:** migration + schema fold.
- **Verify (user, SQL editor):** as a member, insert with `status='confirmed'` → row lands as `pending`;
  admin confirm still works; `approve_join_request` pay-later path still works.
- **Regression risk:** low-med — must confirm admin/RPC confirmations still write `confirmed`
  (they run as definer/owner so the guard should exempt them). **Safer alt:** if any legit client path
  needs to set confirmed, scope the guard to members only via role check.

### 0.4 ⬜ Request status pinned to 'pending' on member insert (A1-4,5,6)
- **Problem:** `seat_change_requests`, `shift_change_requests`, `hold_requests` member inserts don't
  restrict `status` (low real impact — admin tabs filter pending — but defense-in-depth).
- **Change:** migration adds `WITH CHECK (... AND status = 'pending')` to the member INSERT policies
  (or a shared BEFORE INSERT trigger forcing pending for non-owners).
- **Migration:** `2026-07-03_request_status_guard.sql` (USER applies). Fold after.
- **Verify:** member insert with `status='approved'` → rejected or coerced; admin approve flow unaffected.
- **Regression risk:** low.

**Commit checkpoint A** (after 0.1–0.4 verified): "schema fold + write-guard hardening".

---

## WAVE 1 — Privacy + honesty (P0, golden-rule)

### 1.1 ⬜ Privacy-columns silent leak (A1-2) — HIGH
- **Problem:** `member_privacy_security_screen.dart` reads/writes `show_on_leaderboard`, `show_hours`,
  `hide_nickname` which DO NOT EXIST → update fails silently, UI shows fake success, and
  `library_leaderboard` still exposes opted-out members.
- **Changes:**
  1. **Migration** `2026-07-04_user_privacy_columns.sql`: add the 3 boolean columns to `users`
     (defaults: `show_on_leaderboard=true`, `show_hours=true`, `hide_nickname=false`); these are
     member-self-writable (existing user self-update policy) and NOT in the privileged-lock trigger.
  2. **`library_leaderboard` RPC** (in same migration): exclude `show_on_leaderboard=false`; null out
     hours when `show_hours=false`; return nickname-masked label when `hide_nickname=true`.
  3. **`member_privacy_security_screen.dart`**: keep the now-working DB write; remove the
     dishonest unconditional success — only show success when the DB write actually succeeds.
  4. **`member_analytics_tab.dart`** leaderboard rendering: respect the masked fields the RPC returns.
- **Migration:** USER applies; fold after. RPC return type may change → `DROP FUNCTION` first (as the
  avatar migration did).
- **Verify:** opt out on device → member disappears / hours hidden / nickname masked on leaderboard;
  toggle persists across reinstall (server-stored, not just local prefs).
- **Regression risk:** low-med — leaderboard RPC change must be tested (member + admin leaderboard).
  **Safer alt:** ship the columns + honest-UI first; add RPC masking in a second step so the
  leaderboard query is changed in isolation.

**Commit checkpoint B.**

---

## WAVE 2 — Storage URL correctness (P0, payments/KYC blocker)

### 2.1 ⬜ Signed-URL expiry on payment proof + ID docs (A2-3, A2-4)
- **Problem:** app stores a 1-hour signed URL in `join_requests.payment_proof_url` / user ID-doc fields;
  admin review hours later → expired → proof/KYC unviewable.
- **Strategy (non-destructive):** store the **storage object path**, and **sign-on-view**. Existing rows
  already hold full URLs → render-time detection: if the value looks like a path (no `http`), sign it;
  if it's already a URL, use as-is. No destructive backfill.
- **Changes:**
  1. New helper `lib/core/storage_urls.dart` — `Future<String?> signedUrlFor(path, {bucket})` +
     `bool isStoragePath(value)`.
  2. **Write side:** `join_flow_screen.dart` (`_uploadProofImage`/`_submitJoinRequest`),
     `member_profile_edit.dart` (ID upload), `add_member_wizard.dart` if it stores proof — store the
     **path** instead of the signed URL.
  3. **Read side:** `requests_sub_tab.dart` `_docThumb` + applicant review, member/admin payment views,
     `pdf_exporter` proof rendering — resolve via the helper before display.
- **Migration:** none required (path-vs-URL handled at render).
- **Verify:** upload proof, wait >1h (or shorten TTL in test), open admin review → image still loads;
  old rows (full URL) still load.
- **Regression risk:** med — touches upload + multiple viewers + export. **Safer alt:** land the
  read-side helper first (handles both path and URL), THEN switch write-side to paths — so old + new
  both work at every step.

**Commit checkpoint C.**

---

## WAVE 3 — Write-path integrity RLS (P0/P1, test-heavy)

### 3.1 ✅ Attendance + payment insert relationship checks (A2-5, A2-6)
- **Problem:** insert policies validate only `member_id = auth.uid()`, not that
  `membership_id/library_id/shift_id` belong to an active membership of that member → forgeable rows.
- **Change:** migration tightens the member INSERT `WITH CHECK` with
  `EXISTS (SELECT 1 FROM memberships m WHERE m.id = membership_id AND m.member_id = auth.uid()
   AND m.library_id = <row>.library_id AND m.shift_id = <row>.shift_id AND m.status IN ('active','trial'))`.
- **Migration:** `2026-07-05_write_relationship_rls.sql` (USER applies).
- **Verify (CRITICAL):** real member check-in/out still works; real proof submit still works; forged
  ids rejected. **Test live with an actual member account before fold.**
- **Regression risk:** **HIGH** — a wrong predicate silently blocks legitimate check-ins/payments.
  **Safer alt:** keep current policy live; add the new policy in a test project / behind verification;
  only replace after a member round-trip passes. Offline check-in path also writes attendance — verify it.

### 3.2 ✅ Owner cannot rewrite member email/phone (A1-3)
- **Change:** scope `"Owner can update their library members"` to non-identity columns, OR route owner
  edits through an RPC that excludes `email`/`phone`. Migration `2026-07-05_owner_update_scope.sql`.
- **Verify:** owner can still edit allowed fields (name/avatar/etc.); email/phone update by owner rejected.
- **Regression risk:** med — confirm admin member-edit screen doesn't rely on writing those fields.

**Commit checkpoint D.**

---

## WAVE 4 — Seat transaction integrity (P1)

### 4.1 ✅ Atomic seat assignment + seat-change approval (A2-9, A2-10)
- **Problem:** layout reassign + `_approveSeatChangeRequest` do multi-step client read→free→occupy→update
  without a transaction → races / double-book.
- **Change:** migration adds `reassign_seat(...)` + `approve_seat_change(...)` SECURITY DEFINER RPCs
  (owner-checked, row-locked, atomic) mirroring the proven `approve_join_request` pattern; switch the two
  call sites to the RPCs.
- **Migration:** `2026-07-06_seat_rpcs.sql` (USER applies). Files: `layout_sub_tab.dart`,
  `requests_sub_tab.dart`.
- **Verify:** reassign + seat-change approve still work; concurrent attempt fails cleanly (no double-book).
- **Regression risk:** med — replaces working flows. **Safer alt:** add RPCs alongside, switch one call
  site at a time, keep the client path until each RPC is verified on device.

**Commit checkpoint E.**

---

## WAVE 5 — Performance + scale (P1)

### 5.1 ✅ Dashboard counts via `count: head:true` (A1-14, A2-13)
- Convert `admin_home` `.select('id').length` counts to head-count requests (no row download).
  Already parallelized via `Future.wait`. Files: `admin_home.dart`. No migration.
  **DONE:** used postgrest 2.7 `.count(CountOption.exact)` (HEAD request) for active/expired/
  expiring-today/expiring-soon members, unread notifications, open queries, exits-today.
  Revenue + new-joinings still fetch rows (need amounts/dates). `flutter analyze` clean.

### 5.2 ✅ Missing composite + functional indexes (A1-23,25, A2-16)
- Migration adds: `notifications(user_id, read_at)`, `queries(library_id, status)`,
  `scheduled_closures(library_id, start_date, end_date)`, `hold_requests(library_id, status)`,
  `seat_change_requests(library_id, status)`, `audit_log(category)`, and a functional index
  `attendance(((check_in_time AT TIME ZONE 'Asia/Kolkata')::date))`.
- **Migration:** `2026-07-07_perf_indexes.sql` (USER applies). Additive, near-zero risk.

### 5.3 ✅ Server-side explore search + pagination (A1-15, A2-15)
- `member_explore_screen`: browse list now `.order(created_at desc).limit(50)` (bounded payload);
  search pushes name/city/code to PostgREST via `.or(ilike)` + `.limit(50)` so it covers the whole
  DB (not just the capped browse list), with input sanitized for the or() grammar, a stale-result
  guard, and a search spinner. No migration. `flutter analyze` clean.

### 5.4 🟡 History + analytics + audit-log pagination (A1-16–20,43, A2-14)
- `audit_log_screen` already capped at `.limit(40)`. `admin_analytics_tab` queries are date-range
  bounded (natural window). `member_history_tab` attendance query feeds in-memory session/stats
  math — a blind `.limit()` would silently corrupt totals, so it needs true paged loading + a
  server-side aggregate for stats. DEFERRED (UI rework + correctness risk); revisit post-launch.

**Commit checkpoints F1–F4 (one per sub-item).**

---

## WAVE 6 — Realtime fanout (P1, test live)

### 6.1 ✅ Tenant-scope realtime subscriptions (A1-11,12,13, A2-11,12)
- `layout_sub_tab` (seats + floors) + `requests_sub_tab` (join/checkin/shift/seat) now subscribe
  with a `PostgresChangeFilter(library_id = eq <id>)` and library-scoped channel names, so an admin
  viewing library A is no longer woken by library B's changes. `sections` has no library_id column
  (links via floor_id) so it stays global — section edits are rare and a sibling seat/floor change
  refreshes it anyway. `admin_home` join-requests stream was already scoped. `flutter analyze` clean.

**Commit checkpoint G.**

---

## WAVE 7 — Offline integrity (P1)

### 7.1 ✅ Offline checkout state-loop (A1-26)
- `qr_scanner_screen` offline path now decides check-in vs checkout from the member's **latest**
  queued scan (`ORDER BY timestamp DESC LIMIT 1`, type check) instead of "any unsynced check-in
  exists" — which got stuck forcing 'checkout' forever after an offline checkin→checkout pair. Also
  fixed a missing `whereArgs` bind. `flutter analyze` clean.

### 7.2 ✅ Offline sync dead-letter instead of delete (A1-27, A2-24)
- `offline_db.dart`: schema v2 (onUpgrade ALTER TABLE) adds `status` + `last_error` to
  `offline_scan_queue`, plus `failedScanCount()` / `retryFailedScans()` helpers.
- `offline_sync.dart`: on retry exhaustion the scan is flagged `status='failed'` (kept, with the
  error) instead of deleted; pending query scoped to `status='pending'`; after each sync pass a
  visible red "couldn't sync — retry" SnackBar surfaces any dead-lettered scans. `flutter analyze` clean.

### 7.3 ✅ Honest offline check-in label (A2-25)
- `qr_scanner` offline success card now reads "Saved offline — pending sync."

**Commit checkpoint H.**

---

## WAVE 8 — Release / DevOps / hardening (P2)

- ⬜ **8.1** `send-push` fail-closed when `PUSH_WEBHOOK_SECRET` set in prod (A2-17) — verify live webhook
  header is set first, else push breaks. **NEEDS LIVE EDGE-FUNCTION VERIFY — flagged to user; not
  touched (FCM is config-pending).**
- ✅ **8.2** Release build fail-fast when `key.properties` absent (A2-19) — `android/app/build.gradle.kts`
  release block now throws when signing is required (`-PrequireReleaseSigning=true` or `CI=true`) and
  key.properties is missing; keeps the debug fallback for local `flutter run`.
- ✅ **8.3** `istNow()` in `admin_home._loadOperationalFeeds` (A1-39) — the "today" feed window is now
  built from IST wall-clock → UTC (`istWallClockToUtc`, matching analytics) so the boundary is true IST
  midnight regardless of device timezone.
- ⬜ **8.4** Public `USING(true)` read scoping for seats/add_ons occupant data (A2-7) — careful, Explore
  depends on shift/price reads. **NEEDS LIVE RLS CHANGE + verify — flagged to user (highest realtime/
  Explore regression risk). Safer alt:** hide `occupied_by_member_id` from public seat reads only.
- 🟡 **8.5** Double-submit guard in `contact_admin_screen` (A1-48) — **already present** (button disabled
  + `sending` spinner before the await). No-Seat filter optimistic refresh (A1-44) — minor UI, deferred.
- ⬜ **8.6** Public-config note (A1-36, A2-30): anon key/Firebase keys are public by design; optionally
  move to `--dart-define-from-file` for env separation. Low urgency.

---

## WAVE 9 — Engineering hygiene (P3, post-launch ok)

- ⬜ CI workflow (analyze + test + build + schema-drift check) (A2-26).
- ⬜ Tests for critical services/RPCs: approve, exit-dues, transfer, payments, offline state (A1-35, A2-27).
- ⬜ Resolve the 2 baseline `use_build_context_synchronously` infos (A2-28).
- ⬜ Dependency upgrade pass (A2-29).
- ⬜ God-file decomposition (member_home/admin_analytics/layout) — large, last (A1-31,32,33).
- ⬜ Repository/service layer for Supabase calls (A1-34).
- ⬜ Monetization/billing before paid launch; replace `betaMode` constant with config (A1-38, A2-21).

---

## EXCLUDED — verified false positives / already-fixed (do NOT implement)
- ❌ Notification spoofing (A1-7) — already scoped via "Scoped insert notifications" (P5-08).
- ❌ abuse_reports reporter_id spoofing (A1-8) — `WITH CHECK (reporter_id = auth.uid())` enforced.
- ❌ Keystore not gitignored (A2-20) — `android/.gitignore` already ignores `key.properties`/`*.jks`/`*.keystore`.
- ⚠️ Storage MIME/size limits (A1-9,10) — configured in Supabase dashboard, not verifiable from source;
  treat as a dashboard checklist item, not a code fix.

---

## Suggested execution order (recommended)
**Wave 0 → 1 → 2 → 3** are the launch blockers (do first, in order).
**Wave 4 → 5 → 6 → 7** are scale/integrity (before heavy growth).
**Wave 8 → 9** are hardening/hygiene (can trail launch).

Each wave: author migration (if any) → user applies + confirms → fold into schema → code change →
`flutter analyze` (0 new) → device sanity check → commit (on user request). No wave starts until the
previous is verified.
