# Requirements Document

Legal Pages Sync + UGC Reporting & Moderation

## Introduction

SILENCE ("Silence – Library Management & QR Attendance") is preparing for commercial launch
on the Google Play Store (India first) and later the Apple App Store. Two compliance-critical
gaps remain after the consolidated legal content was authored under `legal/`:

1. **In-app legal screens are out of sync.** The app's existing legal/policy screens
   (`/member/terms`, `/member/privacy-policy`, `/member/about`, `/member/help`,
   `/member/licences`, `/policy/refund`, `/policy/cancellation`, `/policy/community`,
   `/admin/terms`, `/admin/about-us`, `/admin/help-support`) contain older, hardcoded text
   that contradicts the newly finalized canonical documents in `legal/` (operator name, Alwar
   address, grievance officer, out-of-app UPI model, no-refund SaaS subscription, 18+ policy,
   Seoul data region, 30-day deletion, Firebase analytics disclosure, etc.).

2. **No User-Generated-Content (UGC) reporting/moderation exists.** Google Play's
   User-Generated Content policy requires apps that host user content (profile names & photos,
   library photos, member↔library messages/queries) to provide an in-app way to **report**
   objectionable content and to **block** abusive users, plus a moderation/removal path for the
   operator. This is currently missing and is a likely rejection cause.

This spec covers (a) syncing the in-app legal screens to the canonical `legal/` documents, and
(b) building a minimal, honest UGC report + block + moderation capability.

### Canonical source of truth
- Legal copy: the five files under `legal/` (`privacy_policy.md`, `terms_and_conditions.md`,
  `refund_and_cancellation_policy.md`, `community_and_content_policy.md`, `about_and_contact.md`).
- Locked operator facts: Ashish Kumar (sole proprietor, Alwar, Rajasthan, India);
  `ashish.premierbro@gmail.com`, +91 72978 79930; grievance ack 48h / resolve 15 days;
  domain `silenceapp.in` (planned); region Supabase Seoul (ap-northeast-2); deletion within 30 days.

### Out of scope (explicitly)
- Buying/hosting the `silenceapp.in` domain or the public website pages (user task).
- Lawyer review / legal sign-off (user task; docs are informational, not legal advice).
- Razorpay / real payments, OTP, subscription enforcement (deferred elsewhere).
- Replacing the out-of-app UPI payment model.

### Non-negotiable project rules that constrain this work
- **No dishonest UI** — never claim an action happened if it did not.
- **Warm-orange (#E65C00) Material 3 style; refine, don't redesign.** Dark-mode must be honored
  via `context.palette`; snackbars via `AppSnackbar`.
- **No live-DB access by the agent** — any schema change is authored as a runnable
  `silence_app/migrations/*.sql` for the user to apply, then folded into `supabase_schema.sql`.
- **No server tier preference** — favor direct `.from(...)` writes; only use RPC where RLS
  integrity requires it.
- **Run `flutter analyze` after changes; 0 new errors.** Commit/push only when the user asks.

---

## Glossary

- **UGC (User-Generated Content):** Content created by users that the app stores/displays — here:
  profile names & photos, library photos, and member↔library messages/queries.
- **Data Fiduciary / Data Processor (DPDP Act 2023):** The library owner decides why/how member
  data is used (Fiduciary); SILENCE processes it on their behalf (Processor).
- **Grievance Officer:** The contact responsible for handling complaints under Indian IT/DPDP
  rules — here Ashish Kumar, ack within 48h, resolution within 15 days.
- **Canonical legal docs:** The five finalized files under `legal/` that are the single source of
  truth for all in-app and website legal copy.
- **App-owner:** The platform operator account flag (`is_app_owner`) with platform-wide rights.
- **`AppSnackbar`:** Project-standard snackbar helper (`success`/`error`/`warning`/`info`).
- **`context.palette`:** Theme accessor providing dark/light-aware surface and text colors.

## Requirements

### Requirement 1: In-app legal screens reflect the canonical legal documents

**User Story:** As a user (member or library owner), I want the in-app legal/policy screens to
show the same, current, accurate legal content that is published for the platform, so that I am
correctly informed and the app meets store and DPDP disclosure requirements.

#### Acceptance Criteria
1. WHEN a user opens any in-app legal/policy screen (`/member/terms`, `/member/privacy-policy`,
   `/member/about`, `/member/help`, `/member/licences`, `/policy/refund`, `/policy/cancellation`,
   `/policy/community`, `/admin/terms`, `/admin/about-us`) THEN the displayed content SHALL be
   consistent with the corresponding canonical file under `legal/`.
2. WHERE the same policy is reachable from both the member and admin sides (Terms, About),
   the system SHALL present the same canonical content (single source of truth, no divergence).
3. THE legal screens SHALL display the locked operator identity and contact details: operator
   "Ashish Kumar", Alwar (Rajasthan, India), email `ashish.premierbro@gmail.com`,
   phone +91 72978 79930, and the Grievance Officer with 48-hour acknowledgement / 15-day
   resolution commitment.
4. THE Privacy content SHALL disclose: data stored in Supabase Seoul (ap-northeast-2) with
   cross-border transfer, deletion within 30 days of an account-deletion request, foreground-only
   location use for nearby libraries, camera/photo use for QR and uploads, and the analytics
   providers actually used (Firebase Analytics, Crashlytics, Cloud Messaging).
5. THE Terms / payment-related content SHALL state the out-of-app UPI model (SILENCE never holds,
   processes, or refunds member↔library payments; the library owner sets all membership terms and
   is the Data Fiduciary while SILENCE is the Data Processor) and that SaaS subscription fees
   (when charged) are non-refundable.
6. THE app SHALL NOT name a specific government ID type in any user-facing legal screen (ID
   collection is described generically, consistent with the locked decision).
7. WHEN the canonical `legal/` content is updated in future THEN updating the in-app screens
   SHALL require changing content in a single, well-defined location (the design SHALL choose and
   justify one approach — bundled markdown asset + viewer, or per-screen rewrite — to avoid
   drift), and the chosen approach SHALL be documented.
8. THE updated screens SHALL render correctly in both light and dark mode (using `context.palette`,
   no hardcoded white/black surfaces) and SHALL keep the warm-orange Material 3 styling.
9. THE "Last updated" label shown on each screen SHALL reflect the date the canonical content was
   finalized rather than a stale hardcoded date, and SHALL match the date in the `legal/` files.
10. WHEN content references another policy (e.g., Terms → Privacy/Refund/Community) THEN the
    in-app screen SHALL allow the user to navigate to that related policy.

---

### Requirement 2: Members and owners can report objectionable content/users

**User Story:** As a user, I want to report objectionable user-generated content (a profile, a
library, a photo, or a message) so that harmful content can be reviewed and removed.

#### Acceptance Criteria
1. THE app SHALL provide an in-app "Report" action on each surface that displays user-generated
   content, at minimum: another user's profile/name, a library profile/photos, and member↔library
   messages or queries.
2. WHEN a user taps "Report" THEN the system SHALL present a short form allowing selection of a
   reason (e.g., spam, harassment/abuse, inappropriate/explicit, impersonation, copyright, other)
   and an optional free-text description.
3. WHEN a user submits a report THEN the system SHALL persist the report to a dedicated
   `abuse_reports` table including reporter id, reported entity type and id, reason, optional
   description, and timestamp.
4. WHEN a report is submitted successfully THEN the system SHALL show an honest success
   confirmation via `AppSnackbar.success`; IF the write fails THEN it SHALL show an honest error
   via `AppSnackbar.error` and SHALL NOT claim the report was sent.
5. THE system SHALL prevent a user from submitting duplicate identical reports for the same entity
   within a short window (no silent duplicate spam), and SHALL not allow reporting one's own
   content where that is meaningless.
6. THE report flow SHALL be reachable without leaving the app and SHALL NOT require email as the
   only channel (email remains a documented fallback, per the Community Policy).
7. THE `abuse_reports` writes SHALL be protected by RLS so a user can insert only reports where
   they are the reporter, consistent with existing actor-scoped insert policies.

---

### Requirement 3: Users can block abusive users

**User Story:** As a user, I want to block another user so that I no longer receive interactions
(messages/queries) from them, satisfying the Play UGC "block users" requirement.

#### Acceptance Criteria
1. THE app SHALL provide a "Block" action on a user's profile and/or on a message/query thread
   from that user.
2. WHEN a user blocks another user THEN the system SHALL persist the block relationship and SHALL
   confirm honestly via `AppSnackbar`.
3. WHILE a user is blocked, the blocking user SHALL NOT receive new messages/queries from the
   blocked user through the app's UGC surfaces.
4. THE app SHALL allow the user to view and undo (unblock) their blocks.
5. THE block relationship SHALL be protected by RLS so a user can create/remove only their own
   block records.
6. WHERE the app's current member↔owner interaction model makes a full mutual-block infeasible
   without server logic, the design SHALL document the minimum honest behavior implemented and any
   limitation, with no dishonest "blocked" claim.

---

### Requirement 4: Operator/library owner can moderate and remove content

**User Story:** As the platform operator (and, for their own library, a library owner), I want to
review reports and remove or hide offending content, so that the platform can enforce the
Community & Content Policy within the stated 24-hour review goal.

#### Acceptance Criteria
1. THE library owner SHALL be able to remove or hide user-generated content on their own library
   (consistent with the Community Policy statement) where such content exists in-app.
2. THE platform operator (app-owner flag) SHALL have a path to view reported content/reports and
   take removal/suspension action.
3. WHEN content is removed THEN it SHALL no longer be displayed to other users, and the action
   SHALL be honest (no fake removal).
4. THE moderation/removal capability SHALL respect existing roles and RLS (owner scoped to their
   library; app-owner platform-wide), authored as a migration the user applies — the agent SHALL
   NOT assume any live-DB mutation occurred.
5. WHERE full operator tooling is too large for this iteration, the design SHALL define a minimal
   honest mechanism (e.g., report visibility + removal of the specific content type that exists)
   and clearly list deferred moderation work.

---

### Requirement 5: Database schema for UGC moderation is authored safely

**User Story:** As the developer, I want the UGC moderation schema delivered as a reviewable
migration with RLS, so I can apply it manually and keep the canonical schema in sync without the
agent touching the live database.

#### Acceptance Criteria
1. THE schema changes (e.g., `abuse_reports`, `user_blocks`, any moderation columns) SHALL be
   authored as a new runnable file under `silence_app/migrations/` with a dated filename.
2. THE migration SHALL enable RLS on new tables with policies consistent with the project's
   actor-scoped pattern (reporter/blocker can insert their own rows; appropriate read scope for
   the owner/app-owner moderation path).
3. THE migration SHALL be idempotent-friendly where practical (guarded `create table if not
   exists`, policy drops/creates) so re-running is safe.
4. AFTER authoring, the change SHALL be foldable into `silence_app/supabase_schema.sql`, and the
   spec SHALL note that the user must apply it to the live DB and verify before the feature is
   considered live.
5. THE agent SHALL NOT claim the migration was applied; status SHALL remain "authored, pending
   user apply" until the user confirms.

---

### Requirement 6: Verification and store-readiness alignment

**User Story:** As the developer, I want the changes verified statically and aligned with store
policy expectations, so that this work measurably reduces rejection risk.

#### Acceptance Criteria
1. AFTER each change, `flutter analyze` SHALL be run and SHALL introduce 0 new errors over the
   established baseline.
2. WHERE a new dependency is introduced (e.g., a markdown renderer), the change SHALL be built
   (not analyze-only) and the dependency pinned, per project token/verification rules.
3. THE delivered work SHALL map back to the relevant store requirements (Play UGC policy:
   in-app report + block + moderation; Data Safety / privacy disclosures matching the in-app
   Privacy screen) and the spec SHALL record which store requirement each piece satisfies.
4. THE `[INSERT DATE]` placeholders in the `legal/` files SHALL be resolved to the finalization
   date as part of completing the content sync.
5. NO commit or push SHALL occur unless the user explicitly requests it; when requested, the
   commit message SHALL end with the `Co-Authored-By:` trailer.
