# SILENCE Pre-Production Technical Audit

Date: 2026-06-29

Scope: Source-code-only technical audit of the Flutter/Supabase application for commercial SaaS launch readiness. Documentation, prior audit notes, project memory, and comments were not treated as proof. Findings below are based on source code, schema SQL, migrations, routing, runtime implementation, tests, and static analysis.

## Executive Verdict

No-Go for public commercial launch yet.

The app is functional enough for a controlled beta and `flutter test` passed, but the code shows production blockers in canonical schema drift, private-storage URL expiry, client-trusted writes, unbounded dashboards, realtime fanout, release operations, and subscription readiness.

## Scores

| Area | Score |
|---|---:|
| Architecture | 4/10 |
| Code Quality | 5/10 |
| Performance | 4/10 |
| Security | 5/10 |
| Scalability | 3/10 |
| Maintainability | 3/10 |
| UX | 6/10 |
| Production Readiness | 4/10 |

## Verification Performed

- `flutter analyze`: completed with 2 `use_build_context_synchronously` info issues.
- `flutter test`: passed 8 tests.
- `flutter pub outdated`: completed and showed multiple outdated direct/transitive dependencies.
- Git status at audit time: clean `main` tracking `origin/main`.

## Top Critical Findings

### 1. Canonical schema drift breaks fresh push deploys

- Files: `lib/services/push_notification_service.dart:207`, `supabase/functions/send-push/index.ts:72`, `silence_app/supabase_schema.sql:55`
- Function(s): `PushNotificationService._saveToken`, `send-push` Edge Function
- Root cause: Runtime code and Edge Function use `device_tokens`, but the canonical `supabase_schema.sql` does not define the table.
- Evidence: Client upserts to `device_tokens`; Edge Function selects from `device_tokens`; base schema only defines `users.fcm_token`.
- Problem: A fresh production rebuild from canonical schema will not support push notifications.
- Impact: Push token registration and send-side lookup fail.
- Recommended fix: Fold `2026-06-17_device_tokens.sql` into `supabase_schema.sql`, including table, index, RLS, and policies.

### 2. Canonical schema misses `auto_checkout_grace_minutes`

- Files: `lib/screens/app_settings_screen.dart:43`, `lib/screens/app_settings_screen.dart:83`, `silence_app/supabase_schema.sql:117`, `silence_app/migrations/2026-06-26_overtime_grace_minutes.sql:7`
- Function(s): `_loadOvertimeSetting`, `_setGraceMinutes`, `process_shift_overtime`
- Root cause: Runtime code reads/writes a column added by migration, but the canonical library table definition omits it.
- Evidence: App selects and updates `auto_checkout_grace_minutes`; base schema defines `auto_checkout_overtime` but not the grace column.
- Problem: Fresh DB setup or disaster recovery from canonical schema breaks the settings screen and overtime cron.
- Impact: Production rebuild drift and runtime PostgREST errors.
- Recommended fix: Add the column and `libraries_grace_minutes_bound` constraint to `supabase_schema.sql`.

### 3. Payment proof links expire before admin review

- Files: `lib/screens/reservations/join_flow_screen.dart:545`, `lib/screens/reservations/join_flow_screen.dart:686`, `lib/screens/reservations/requests_sub_tab.dart:1473`
- Function(s): `_uploadProofImage`, `_submitJoinRequest`, `_docThumb`
- Root cause: The app stores a one-hour signed URL in `join_requests.payment_proof_url` instead of storing a private storage path.
- Evidence: `createSignedUrl(path, 3600)` is assigned to `_proofUrl`; request payload stores `_proofUrl`; admin review renders it directly with `Image.network`.
- Problem: The admin may review after the signed URL expires.
- Impact: Payment verification becomes impossible or unreliable.
- Recommended fix: Store the storage object path, then create a fresh signed URL on every admin/member view.

### 4. ID document review has the same signed-URL expiry bug

- Files: `lib/screens/member_profile_edit.dart:384`, `lib/screens/reservations/requests_sub_tab.dart:1682`, `lib/screens/reservations/requests_sub_tab.dart:1473`
- Function(s): `_pickAndUploadImage`, `_showReviewSheet`, `_docThumb`
- Root cause: ID document uploads store signed URLs, while request review does not re-sign them.
- Evidence: Private bucket document upload uses `createSignedUrl(path, 3600)`; request review passes those raw values to `Image.network`.
- Problem: Admin document review fails after expiration.
- Impact: KYC/identity verification workflow is unreliable.
- Recommended fix: Store private object paths and use a shared signing helper before display/export.

### 5. Attendance insert RLS trusts client-supplied relationship fields

- Files: `silence_app/supabase_schema.sql:198`, `silence_app/supabase_schema.sql:980`
- Function(s): RLS policy `"Member insert (check-in/out)"`
- Root cause: Policy checks only `member_id = auth.uid()`, not that `membership_id`, `library_id`, and `shift_id` belong to an active membership for the user.
- Evidence: Attendance table stores `membership_id`, `member_id`, `library_id`, and `shift_id`; insert policy only validates `member_id`.
- Problem: A modified client can forge attendance rows against arbitrary library/shift ids visible through public reads.
- Impact: Attendance integrity and analytics can be corrupted.
- Recommended fix: Replace client insert with RPC or add `EXISTS` policy verifying active/trial membership consistency.

### 6. Payment insert RLS trusts client-supplied relationship fields

- Files: `silence_app/supabase_schema.sql:228`, `silence_app/supabase_schema.sql:1001`
- Function(s): RLS policy `"Member insert (upload proof)"`
- Root cause: Policy checks only `member_id = auth.uid()`.
- Evidence: Payments table stores `membership_id`, `member_id`, `library_id`, amount, status, and proof; member insert policy validates only the member id.
- Problem: A client can submit bogus pending payment/proof rows for mismatched membership/library ids if RLS allows row visibility.
- Impact: Dues, revenue, and admin payment review can be polluted.
- Recommended fix: Require matching membership ownership and library consistency in RLS or submit proofs through an RPC.

### 7. Public RLS exposes tenant layout and operational metadata

- Files: `silence_app/supabase_schema.sql:878`, `silence_app/supabase_schema.sql:886`, `silence_app/supabase_schema.sql:894`, `silence_app/supabase_schema.sql:898`, `silence_app/supabase_schema.sql:1100`
- Function(s): RLS policies for `shifts`, `floors`, `sections`, `seats`, `add_ons`
- Root cause: Several tables use `FOR SELECT USING (true)`.
- Evidence: Shifts, floors, sections, seats, and add-ons are globally readable.
- Problem: Any client can enumerate capacity, floor/section layout, seat status, and pricing/add-on data beyond the selected active library context.
- Impact: Tenant privacy, competitor intelligence, UUID discovery, and realtime fanout risk.
- Recommended fix: Scope public reads to active library explore needs and hide occupied member ids/status unless tenant-related.

### 8. `users` insert is too open

- Files: `silence_app/supabase_schema.sql:852`, `silence_app/supabase_schema.sql:1354`
- Function(s): RLS policy `"Anyone can insert (signup)"`, trigger `guard_user_privileged_columns`
- Root cause: Insert policy allows `WITH CHECK (true)`.
- Evidence: Trigger sanitizes privileged fields on insert, but policy does not require `id = auth.uid()`.
- Problem: A crafted client can attempt junk/spoof profile rows.
- Impact: Data pollution and attack surface around onboarding.
- Recommended fix: Restrict insert to authenticated users where `id = auth.uid()` or move profile bootstrap into an RPC.

### 9. Seat assignment is non-transactional

- Files: `lib/screens/reservations/layout_sub_tab.dart:731`, `lib/screens/reservations/layout_sub_tab.dart:743`, `lib/screens/reservations/layout_sub_tab.dart:747`, `lib/screens/reservations/layout_sub_tab.dart:751`
- Function(s): seat reassignment flow in layout tab
- Root cause: The client performs separate read/update/update/update calls without a database transaction or row lock.
- Evidence: Code re-validates seat status, frees old seat, occupies new seat, then updates membership in separate PostgREST calls.
- Problem: Concurrent admins/actions can interleave.
- Impact: Double booking, orphaned seat occupancy, or membership/seat mismatch.
- Recommended fix: Move seat assignment/reassignment to a single `SECURITY DEFINER` RPC using row locks and consistency checks.

### 10. Seat-change approval is non-transactional

- Files: `lib/screens/reservations/requests_sub_tab.dart:639`, `lib/screens/reservations/requests_sub_tab.dart:652`, `lib/screens/reservations/requests_sub_tab.dart:657`, `lib/screens/reservations/requests_sub_tab.dart:663`
- Function(s): `_approveSeatChange`
- Root cause: Same multi-step client-side mutation pattern as seat reassignment.
- Evidence: Checks new seat, updates membership, frees old seat, occupies new seat, then updates request status.
- Problem: Partial failure leaves inconsistent state.
- Impact: Seat map integrity failure.
- Recommended fix: Create one RPC for approve/reject seat change.

### 11. Realtime layout subscriptions are globally broad

- Files: `lib/screens/reservations/layout_sub_tab.dart:117`, `lib/screens/reservations/layout_sub_tab.dart:131`, `lib/screens/reservations/layout_sub_tab.dart:145`
- Function(s): `_setupRealtimeSubscription`
- Root cause: Subscribes to all changes on `seats`, `floors`, and `sections` without filters.
- Evidence: `onPostgresChanges` has table names only, no library/floor filters.
- Problem: Every tenant's layout changes wake every open layout screen.
- Impact: Realtime connection load and unnecessary data refreshes at scale.
- Recommended fix: Add filters where supported; otherwise create library-scoped channels or targeted refresh triggers.

### 12. Request tab realtime subscriptions are globally broad

- Files: `lib/screens/reservations/requests_sub_tab.dart:113`
- Function(s): `_setupRealtimeSubscription`
- Root cause: Subscribes to all changes on request tables without library filters.
- Evidence: Channel listens to `join_requests`, `checkin_approvals`, `shift_change_requests`, and `seat_change_requests` without filters.
- Problem: All admins receive cross-tenant change events and reload their own data.
- Impact: High fanout and excess queries under growth.
- Recommended fix: Use library-filtered realtime or poll with server-side invalidation.

### 13. Admin dashboard counts fetch full row lists

- Files: `lib/screens/admin_home.dart:582`, `lib/screens/admin_home.dart:604`
- Function(s): `_fetchRealStats`
- Root cause: Counts and sums are computed client-side from selected rows.
- Evidence: Code selects rows from attendance, memberships, and payments, then counts/sums in Dart.
- Problem: Bandwidth and memory grow with tenant size.
- Impact: Slow dashboard, higher Supabase egress, mobile memory pressure.
- Recommended fix: Use PostgREST exact counts, aggregate RPCs, or precomputed daily library stats.

### 14. Admin analytics loads entire tenant datasets into memory

- Files: `lib/screens/admin_analytics_tab.dart:536`
- Function(s): `_fetchAnalyticsData`
- Root cause: Analytics queries fetch payments, expenses, memberships, attendance, seats, and trend memberships as raw rows.
- Evidence: `Future.wait` fetches broad `select('*')` style nested datasets, then processes client-side.
- Problem: Unbounded analytics will degrade with large libraries.
- Impact: The analytics tab is likely an early performance bottleneck.
- Recommended fix: Paginate detail tables and use aggregate SQL/RPC/materialized stats for charts.

### 15. Explore and member home fetch all active libraries

- Files: `lib/screens/member_explore_screen.dart:57`, `lib/screens/member_home.dart:307`
- Function(s): `_loadLibraries`, `_loadInitialData`
- Root cause: No pagination or city/search filtering at query level.
- Evidence: Both code paths query active libraries and nested shifts without `.range()` or `.limit()`.
- Problem: As public library count grows, every member downloads too much data.
- Impact: Slow first load and high egress.
- Recommended fix: Add city/search filters, pagination, and lazy loading.

### 16. Missing hot-path indexes

- Files: `silence_app/supabase_schema.sql:690`
- Function(s): schema index block
- Root cause: Indexes exist for core tables, but not for several frequent filters.
- Evidence: Code filters `notifications(user_id, read_at)`, `queries(library_id, status)`, `scheduled_closures(library_id, start/end)`, `hold_requests(library_id,status)`, and `seat_change_requests(library_id,status)`; canonical index block lacks those composites.
- Problem: Queries can become full scans.
- Impact: Dashboard/request/load latency grows with total rows.
- Recommended fix: Add composite indexes matching actual query predicates.

### 17. Push webhook can fail open

- Files: `supabase/functions/send-push/index.ts:42`
- Function(s): Edge Function request handler
- Root cause: The webhook secret check is conditional on `PUSH_WEBHOOK_SECRET` existing.
- Evidence: If env var is absent, the check is skipped.
- Problem: A production deploy without the secret leaves a public function callable.
- Impact: Push abuse and FCM quota/cost risk.
- Recommended fix: Fail closed in production or require a secret unconditionally.

### 18. Android notification permission is missing from manifest

- Files: `lib/services/push_notification_service.dart:123`, `android/app/src/main/AndroidManifest.xml:1`
- Function(s): `_initLocalNotifications`
- Root cause: Runtime requests Android 13 notification permission, but manifest does not declare `android.permission.POST_NOTIFICATIONS`.
- Evidence: Manifest includes camera, internet, storage/media permissions only.
- Problem: Push/local notification permission may not work correctly on Android 13+.
- Impact: Notifications unreliable on modern Android.
- Recommended fix: Add `<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />`.

### 19. Release builds can be debug-signed

- Files: `android/app/build.gradle.kts:65`
- Function(s): Android release build config
- Root cause: Release signing config falls back to debug when `key.properties` is absent.
- Evidence: `signingConfig = ... else signingConfigs.getByName("debug")`.
- Problem: CI/local release can accidentally produce a debug-signed artifact.
- Impact: Store upload failure or accidental non-production artifact.
- Recommended fix: Fail release builds when production signing config is absent.

### 20. Keystore ignore claim is false in source

- Files: `android/app/build.gradle.kts:14`, `.gitignore:1`
- Function(s): release signing setup
- Root cause: Gradle comments say `key.properties` and keystores are gitignored, but `.gitignore` does not include them.
- Evidence: Search found no `key.properties`, `*.jks`, or `*.keystore` entries in `.gitignore`.
- Problem: Future developers may commit secrets.
- Impact: Release key compromise.
- Recommended fix: Add explicit ignore rules for `android/key.properties`, `*.jks`, and `*.keystore`.

### 21. Subscription enforcement is disabled

- Files: `lib/core/plan_service.dart:40`, `lib/screens/subscription_screen.dart:112`
- Function(s): `PlanService`, `_onSelectPaidPlan`
- Root cause: `betaMode` is hardcoded true and paid plans are informational.
- Evidence: `PlanService.betaMode = true`; paid plan tap says coming soon and no payment is taken.
- Problem: The product is not ready for paid SaaS monetization.
- Impact: Commercial launch cannot enforce entitlements or collect owner subscriptions.
- Recommended fix: Implement billing/webhook flow, test RLS locks, and flip enforcement through environment/config rather than a code constant.

### 22. Verified badge client/server subscription mismatch

- Files: `lib/screens/verified_badge_screen.dart:137`, `silence_app/supabase_schema.sql:2435`
- Function(s): `_checkEligibility`, `claim_verified_badge`
- Root cause: Client treats any non-`none` active plan as eligible, while server rejects null/none active subscription.
- Evidence: Client defaults status to `trial`; server requires non-none plan and active status.
- Problem: UI can show eligibility assumptions that server rejects.
- Impact: Confusing owner UX.
- Recommended fix: Derive eligibility from the same RPC or expose a server eligibility function.

### 23. Local offline database stores PII unencrypted

- Files: `lib/core/offline_db.dart:50`, `lib/core/offline_db.dart:67`, `lib/core/offline_db.dart:101`
- Function(s): `OfflineDatabase._createDB`
- Root cause: SQLite cache stores member names, phones, seat labels, attendance, and dues without encryption.
- Evidence: Tables `cache_members`, `cache_attendance_today`, `cache_member_memberships`, and `cache_member_attendance`.
- Problem: Device compromise exposes personal/operational data.
- Impact: Privacy and compliance risk.
- Recommended fix: Minimize cached PII or use encrypted storage with clear retention.

### 24. Offline sync silently deletes permanently failed scans

- Files: `lib/core/offline_sync.dart:188`, `lib/core/offline_sync.dart:190`
- Function(s): `syncPendingScans`
- Root cause: After retries, failed scans are deleted rather than retained for operator/user recovery.
- Evidence: On retry count >= 2, code deletes row and logs debug output.
- Problem: Attendance events can be lost without user-visible resolution.
- Impact: Trust/accounting disputes.
- Recommended fix: Add dead-letter status and visible retry/support workflow.

### 25. Offline check-in success can be misleading

- Files: `lib/screens/reservations/qr_scanner_screen.dart:258`
- Function(s): offline QR scan flow
- Root cause: The UI displays a success-style card after only local queue insertion.
- Evidence: `_showSuccess` is called with `libraryName: 'SILENCE Study Zone (Offline)'`, `seatLabel: 'Reserved Seat'`.
- Problem: The event has not been server validated.
- Impact: User may believe attendance is accepted when it can later be discarded.
- Recommended fix: Label as "Saved offline, pending validation" and show eventual sync result.

### 26. No CI workflow found

- Files: `.gitlab/duo/chat-rules.md:1`, absence of `.github` workflows
- Function(s): DevOps
- Root cause: No automated pipeline in repo.
- Evidence: Repo contains `.gitlab/duo/chat-rules.md`; no `.github` directory/workflow and no CI config running analyze/test/build.
- Problem: Regressions can enter production unchecked.
- Impact: Higher launch risk.
- Recommended fix: Add CI for `flutter analyze`, `flutter test`, build, schema drift checks, and dependency audit.

### 27. Test coverage is minimal

- Files: `test/moderation_service_test.dart`, `test/widget_test.dart`
- Function(s): test suite
- Root cause: Only moderation utility and smoke test coverage.
- Evidence: `flutter test` ran 8 tests.
- Problem: Payments, attendance, joins, approvals, storage, offline sync, and RLS assumptions are not tested.
- Impact: High regression risk.
- Recommended fix: Add integration tests for top launch journeys and unit tests for critical services.

### 28. Analyzer reports async-context issues

- Files: `lib/screens/admin_profile_tab.dart:2108`, `lib/screens/member_home.dart:534`
- Function(s): time picker flow, member activity building
- Root cause: `BuildContext` is used across async gaps or after unrelated mounted checks.
- Evidence: `flutter analyze` reported two `use_build_context_synchronously` infos.
- Problem: Can cause crashes or incorrect theme/context access after navigation/disposal.
- Impact: Stability risk.
- Recommended fix: Capture needed values before awaits or check the exact context's mounted status.

### 29. Dependency drift is significant

- Files: `pubspec.yaml`, `pubspec.lock`
- Function(s): package management
- Root cause: Many dependencies are locked behind resolvable/latest versions.
- Evidence: `flutter pub outdated` showed `supabase_flutter` current lock 2.12.4, resolvable/latest 2.15.0, plus many plugin updates.
- Problem: Missing bug/security fixes and future upgrade pain.
- Impact: Maintenance and security review risk.
- Recommended fix: Schedule controlled dependency upgrade and regression pass.

### 30. Hardcoded Supabase and OAuth/Firebase config prevents environment separation

- Files: `lib/core/supabase_config.dart:6`, `lib/core/supabase_config.dart:7`, `lib/firebase_options.dart:44`, `web/firebase-messaging-sw.js:8`
- Function(s): app initialization/config
- Root cause: Production project config is compiled into source.
- Evidence: Supabase URL/anon key and Firebase API keys are constants.
- Problem: No clean dev/staging/prod separation and rotation requires rebuild.
- Impact: Operational fragility.
- Recommended fix: Use `--dart-define-from-file` or flavor-based environment config.

## High Priority Improvements

1. Fold every applied migration into `supabase_schema.sql`.
2. Add a schema drift test comparing runtime table/column references to canonical schema.
3. Replace private signed URL persistence with storage-path persistence.
4. Centralize private-storage signing and thumbnail rendering.
5. Move seat assignment and seat-change approval to RPCs.
6. Move attendance check-in/out to validated RPCs.
7. Move payment proof creation to validated RPCs.
8. Add tenant-consistency checks to all write policies.
9. Restrict public layout reads.
10. Add filtered realtime subscriptions.
11. Add request queue pagination.
12. Add dashboard aggregate RPCs.
13. Add materialized/precomputed library daily stats.
14. Paginate explore libraries.
15. Paginate notifications.
16. Paginate audit logs beyond fixed latest view.
17. Add composite indexes for notification/query/request/closure hot paths.
18. Add CI for analyze/test/build.
19. Add release signing fail-fast.
20. Add keystore ignore rules.
21. Add Android notification permission.
22. Fail closed in `send-push` without webhook secret.
23. Add Edge Function tests for push payload validation.
24. Encrypt or minimize local SQLite PII.
25. Add offline dead-letter queue and visible sync status.
26. Add end-to-end tests for join request, approval, renewal, exit, attendance, and payments.
27. Add load tests for dashboard and analytics queries.
28. Externalize environment config.
29. Replace `betaMode` code constant with remote/server-controlled rollout flag.
30. Build real subscription billing before paid launch.
31. Standardize error handling instead of catch-and-debug-print.
32. Add structured production logging for Edge Functions.
33. Add database advisor/performance checks to release process.
34. Add RLS verification tests with anon/authenticated roles.
35. Add storage policy tests for private bucket paths.
36. Add dependency update cadence.
37. Add crash reporting/analytics if acceptable for privacy policy.
38. Reduce god files by extracting services/controllers.
39. Move business logic out of widgets.
40. Add DTO/model parsing for Supabase rows.
41. Use counts/heads instead of selecting ids for counts.
42. Avoid global public realtime publication on high-churn tables where possible.
43. Add debounce/backoff for realtime-triggered reloads.
44. Add server-side search for libraries.
45. Add image upload size/type enforcement server-side.
46. Store payment proof metadata separately from membership approval.
47. Add audit rows via triggers/RPC, not ad hoc client inserts.
48. Add data retention policies for notifications and local cache.
49. Add backup/restore runbook based on canonical schema.
50. Add launch checklist with verified live DB schema, webhooks, secrets, and signing.

## Scalability Bottlenecks

The current architecture can support a small beta and probably 100 concurrent users if tenants are small. It is not ready for 100,000 users.

| Scale | Assessment |
|---|---|
| 100 concurrent users | Likely acceptable for small tenant data. |
| 1,000 users | Acceptable only if libraries, attendance, payments, and requests remain small. |
| 10,000 users | Explore, dashboards, analytics, realtime fanout, and missing indexes begin to hurt. |
| 100,000 users | Not realistically ready without aggregate RPCs, pagination, stricter realtime, indexes, and storage fixes. |
| 1,000,000 users | Current direct fat-client architecture is not viable. |

First components likely to fail:

1. Admin analytics and dashboard data loading.
2. Explore/member-home active library queries.
3. Realtime fanout on seats/layout/request tables.
4. Request queues without pagination.
5. Missing indexes on notifications/queries/closures/request queues.
6. Mobile memory pressure from large nested Supabase result sets.

## Technical Debt Report

- Several screens exceed 3,000 to 6,000 lines, including `member_home.dart`, `admin_home.dart`, `layout_sub_tab.dart`, `admin_analytics_tab.dart`, and `admin_profile_tab.dart`.
- Business logic, Supabase queries, UI state, storage uploads, and domain calculations are mixed inside widgets.
- There is no dependency injection boundary around Supabase.
- Many features use direct table writes from the client rather than a small RPC/service layer for integrity-sensitive operations.
- Local caching exists but is partial, unencrypted, and not a full offline sync model.
- Error handling often falls back to `debugPrint` and continues.
- The canonical schema is not a reliable source for fresh production setup until drift is fixed.

## Launch Risk Assessment

Risk level: High.

Primary launch risks:

- Fresh production environment mismatch due to schema drift.
- Payment/ID proof review failure due to expired signed URLs.
- Data integrity issues from client-trusted attendance/payment/seat mutations.
- Performance collapse in dashboards and analytics with larger tenants.
- Notification reliability and webhook hardening gaps.
- Release artifact/signing mistakes.
- No automated CI gate.

## Go / No-Go Recommendation

No-Go for public paid/commercial launch.

Go only for controlled beta after fixing:

1. Canonical schema drift.
2. Private proof/document URL persistence.
3. RLS relationship checks for attendance/payment/join-related writes.
4. Transactional RPCs for seat mutation flows.
5. Release signing and keystore ignore rules.
6. Android notification permission and push webhook fail-closed behavior.
7. Worst unbounded dashboard/explore/request queries.
8. CI for analyze/test/build.

