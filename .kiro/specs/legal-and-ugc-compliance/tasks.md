 # Implementation Plan

## Overview

Two compliance workstreams for SILENCE's launch: (1) sync all in-app legal/policy screens to the
canonical `legal/*.md` content from one in-app source, and (2) add honest UGC reporting, blocking,
and moderation (Google Play UGC policy). Schema ships as one user-applied migration; legal screens
reuse the existing dark-aware `_PolicyScaffold` (no new dependency).

> Conventions: run `flutter analyze` after each coding task (target 0 new errors over baseline).
> No new dependency is added, so no APK build is required unless that changes. Schema work ships as
> ONE migration the user applies manually; the agent never assumes it was applied. Commit/push only
> when the user explicitly asks (with the `Co-Authored-By:` trailer).

## Tasks

- [x] 1. Author the UGC moderation database migration (authored, pending user apply)
  - Create `silence_app/migrations/2026-06-28_ugc_moderation.sql` (idempotent) defining:
    `abuse_reports` (reporter_id, target_type, target_id, library_id, reason, description, status,
    reviewed_by, reviewed_at, created_at) with the closed `reason`/`status` CHECK domains and a
    UNIQUE partial index on (reporter_id, target_type, target_id) WHERE status='open'.
  - `user_blocks` (blocker_id, blocked_id, created_at) with UNIQUE(blocker_id, blocked_id) and
    CHECK(blocker_id <> blocked_id).
  - `reviews` add columns `hidden` (default false), `hidden_by`, `hidden_reason`.
  - Enable RLS + policies: report_insert_self, report_select_scoped (self / app-owner / lib-owner),
    report_update_moderator; user_blocks all-scoped-to-blocker; update the reviews SELECT policies
    so non-moderators don't see `hidden = true` rows (owner keeps full access via existing
    `admin_manage_reviews`).
  - Add a header comment block + a VERIFY/ROLLBACK section, and document the two lines to add to
    the account-deletion function (delete abuse_reports/user_blocks for the deleted user).
  - Do NOT fold into `supabase_schema.sql` yet and do NOT claim it is applied; mark it "pending
    user apply". Get SQL diagnostics on the file.
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 2.5, 4.1_

- [x] 2. Create the in-app legal content single source of truth
  - Add `lib/legal/legal_content.dart` with `LegalSection`, `LegalRelated`, `LegalDoc` models, the
    operator/contact constants (`kOperatorName`, `kOperatorPlace`, `kSupportEmail`, `kSupportPhone`,
    `kAppFullName`, `kWebsite`, `kLegalLastUpdated`) and six `const LegalDoc`s: terms, privacy,
    refund, cancellation, community, about.
  - Transcribe content faithfully from the canonical `legal/*.md` files (Terms, Privacy, Refund +
    Cancellation split, Community, About). Ensure: locked operator/grievance details; DPDP
    disclosures (Supabase Seoul ap-northeast-2 + cross-border, 30-day deletion, foreground-only
    location, camera/photo use, Firebase Analytics/Crashlytics/Cloud Messaging); out-of-app UPI
    model (SILENCE never holds/processes/refunds; owner = Data Fiduciary, SILENCE = Processor);
    non-refundable SaaS subscription; NO specific government ID type named.
  - Set `kLegalLastUpdated` to the finalization date and add `related` cross-links per doc.
  - _Requirements: 1.1, 1.3, 1.4, 1.5, 1.6, 1.9, 1.10_

- [x] 3. Build the shared legal renderer and refactor legal screens to use it
  - In `lib/screens/policy_screens.dart`, generalize `_PolicyScaffold` into a reusable
    `LegalDocScreen(doc: LegalDoc)` that renders intro + sections (dark-aware via `context.palette`,
    warm-orange app bar), shows `kLegalLastUpdated`, a contact footer (`kSupportEmail`), and a
    tappable "Related policies" footer that navigates via `Navigator.pushNamed`.
  - Point `RefundPolicyScreen`, `CancellationPolicyScreen`, `CommunityGuidelinesScreen` at
    `legalRefund` / `legalCancellation` / `legalCommunity`.
  - Refactor `member_terms_screen.dart` AND `terms_screen.dart` (admin) to render `legalTerms`
    (identical content); refactor `member_privacy_policy_screen.dart` to render `legalPrivacy`;
    refactor `member_about_screen.dart` AND `about_us_screen.dart` to render `legalAbout`.
  - Correct contact details (email/phone) on `/member/help` and `/admin/help-support` to the locked
    values without changing their support-form behavior. Leave `/member/licences` unchanged.
  - Verify light + dark rendering assumptions (no hardcoded white/black surfaces introduced).
  - _Requirements: 1.1, 1.2, 1.7, 1.8, 1.9, 1.10, 6.4_

- [x] 4. Implement the moderation service layer
  - Add `lib/services/moderation_service.dart` with `submitReport`, `blockUser`, `unblockUser`,
    `loadMyBlockedIds`, `myBlocks`, `hideReview`, `unhideReview` using direct `.from(...)` writes.
  - Map PostgREST `23505` on report insert to a friendly "already reported" signal; all methods
    throw on failure so callers can render honest errors via `friendlyError`.
  - Implement a pure, testable client-side filter helper
    `List<Map> filterBlocked(List<Map> reviews, Set<String> blockedIds)` and a hidden-filter helper.
  - _Requirements: 2.3, 2.4, 2.7, 3.2, 3.3, 3.4, 3.5, 4.3_

- [x]* 4.1 Property tests for the pure moderation helpers
  - Add `test/moderation_service_test.dart` exercising the pure helpers (no network):
    `filterBlocked` removes exactly the blocked authors (Property 4); hidden filter excludes hidden
    rows for non-moderators (Property 5); reason/status domain guards (Property 6); duplicate/error
    → no-success mapping logic for the result mapper (Property 2, 8).
  - _Requirements: 2.5, 3.3, 4.1, 4.3_

- [x] 5. Build the report bottom sheet and wire entry points
  - Add `lib/widgets/report_sheet.dart` — `showReportSheet(context, {targetType, targetId,
    libraryId, targetLabel})` with reason chips (spam, harassment, inappropriate, impersonation,
    copyright, other) + optional description; success → `AppSnackbar.success`, duplicate →
    `AppSnackbar.info`, other failure → `AppSnackbar.error`. Dark-aware, warm-orange.
  - Add a review overflow menu in `library_public_profile_screen.dart`,
    `admin/all_reviews_screen.dart`, and `library_profile_screen.dart` recent reviews with
    `Report review` + `Block this user` (hidden on the viewer's own review — Property 1).
  - Add `Report library` to the library public profile header; add `Report member` in the admin
    query/member context (`admin_home.dart`).
  - _Requirements: 2.1, 2.2, 2.4, 2.5, 2.6_

- [x] 6. Implement block management UI and apply block/hidden filtering
  - Add `lib/screens/member_blocked_users_screen.dart` (route `/settings/blocked`) listing blocked
    users with Unblock and an honest empty state; register the route in `main.dart` and add an entry
    in `member_privacy_security_screen.dart`.
  - Wire `Block this user` (from the review menu / profile) through `ModerationService.blockUser`
    with honest confirmation.
  - On review-list loads (public profile, all_reviews, library_profile), apply `filterBlocked`
    (using `loadMyBlockedIds`) and the hidden filter so blocked authors' and hidden reviews don't
    render for non-moderators.
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.6_

- [x] 7. Implement moderation/removal surfaces
  - Add owner inline `Hide review` / `Unhide` actions on `admin/all_reviews_screen.dart` (and the
    reply sheet) via `ModerationService.hideReview/unhideReview`, scoped to the owner's library.
  - Add `lib/screens/owner_abuse_reports_screen.dart` (route `/owner/abuse-reports`) gated by
    `users.is_app_owner` (mirror `owner_recovery_console_screen.dart`): list `open` reports with
    actions Hide content (reviews), Dismiss (status→dismissed), Mark actioned (status→actioned).
  - Register the route in `main.dart` and add an `is_app_owner`-gated entry in
    `admin_profile_tab.dart` Operations section next to Recovery Console.
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [x] 8. Resolve placeholders, verify, and document store-readiness mapping
  - Replace the `[INSERT DATE]` placeholders in the five `legal/*.md` files with the finalization
    date (matching `kLegalLastUpdated`).
  - Run `flutter analyze` and resolve any new errors introduced by this work (0 new over baseline).
  - Update `CLAUDE.md` + the relevant `docs_fix/` note: legal screens synced; UGC report/block/
    moderation added; migration `2026-06-28_ugc_moderation.sql` AUTHORED + PENDING user apply
    (with the apply/verify steps and the account-deletion-function lines to add); map each Play UGC
    requirement (in-app report, block users, moderation/removal) + Data-Safety/privacy disclosures
    to the delivered pieces; note the block client-side-filtering limitation.
  - Do NOT commit/push unless the user asks.
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

## Task Dependency Graph

```json
{
  "waves": [
    { "wave": 1, "tasks": ["1", "2", "4"] },
    { "wave": 2, "tasks": ["3", "4.1", "5", "6", "7"] },
    { "wave": 3, "tasks": ["8"] }
  ],
  "dependencies": {
    "1": [],
    "2": [],
    "3": ["2"],
    "4": [],
    "4.1": ["4"],
    "5": ["4"],
    "6": ["4"],
    "7": ["4"],
    "8": ["3", "5", "6", "7"]
  }
}
```

```
1 (migration)            2 (legal_content)
   │                        │
   │                        ▼
   │                     3 (legal screens refactor)
   ▼
4 (moderation service) ──► 4.1* (property tests)
   │
   ├──► 5 (report sheet + entry points)
   ├──► 6 (block UI + filtering)
   └──► 7 (moderation/removal surfaces)

5, 6, 7  ─────────────────► 8 (placeholders, verify, docs/store mapping)
2, 3 ─────────────────────► 8
```

- Tasks 2 → 3 are sequential (content before renderer refactor).
- Task 1 (migration) and Task 4 (service) are independent of the legal stream and can run in
  parallel with 2/3. Tasks 5, 6, 7 depend on Task 4 (and on Task 1 being applied for live use).
- Task 8 is the final gate (depends on 3, 5, 6, 7).
- Task 4.1 is optional (property tests for the pure helpers from Task 4).

## Notes

- **Migration is user-applied:** after Task 1, the user runs the SQL in Supabase and verifies; the
  feature stays "pending apply" until confirmed, then folds into `supabase_schema.sql`.
- **No new dependency / analyze-only:** legal screens reuse `_PolicyScaffold`; UGC UI uses existing
  widgets (`AppSnackbar`, `context.palette`). An APK build is only needed if a dependency is added.
- **Honest UI everywhere:** report/block/hide actions show success only on confirmed DB writes.
- **Block limitation:** client-side filtering only (no server tier) — documented, never overstated.
- **Out of scope:** buying/hosting `silenceapp.in` + website pages, lawyer sign-off, per-owner
  report inbox, server-enforced blocking, `flutter_markdown` viewer.
- **Commit/push only when the user explicitly asks**, ending the message with the
  `Co-Authored-By:` trailer.
