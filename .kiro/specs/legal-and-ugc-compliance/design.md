# Design Document

Legal Pages Sync + UGC Reporting & Moderation

## Overview

This design delivers two compliance-critical capabilities for SILENCE's commercial launch:

1. **Legal content sync** — make every in-app legal/policy screen reflect the finalized canonical
   documents in `legal/`, from a single in-app source of truth, with correct operator/grievance
   details, DPDP disclosures, the out-of-app UPI model, and dark-mode/warm-orange styling.

2. **UGC reporting & moderation** — add an honest in-app way to **report** objectionable content
   (reviews, queries, user profiles, libraries), **block** abusive users, and let owners /
   the app-owner **moderate (hide/remove)** content, satisfying Google Play's User-Generated
   Content policy.

### Key constraints honored
- **No live-DB access:** all schema work ships as one runnable migration under
  `silence_app/migrations/`; the agent never assumes it was applied. Status stays
  "authored, pending user apply" until the user confirms.
- **No new server tier:** prefer direct `.from(...)` writes; RLS does the enforcement. The only
  exception considered (block enforcement) is documented as client-side filtering with a stated
  limitation, since there is no server tier to intercept reads.
- **No new dependency for legal screens:** reuse the existing dark-aware `_PolicyScaffold`
  pattern instead of adding `flutter_markdown` — keeps the change `flutter analyze`-only (no APK
  build needed) and avoids drift. (Tradeoff discussed in Decision D1.)
- **No dishonest UI:** every report/block/removal shows a real result via `AppSnackbar`; failures
  are surfaced honestly and never reported as success.
- **Refine, don't redesign:** warm-orange (#E65C00) Material 3, `context.palette` for all surfaces.

### Existing assets this design builds on
- `lib/screens/policy_screens.dart` — `_PolicyScaffold` + `_PolicySection` (dark-aware, styled).
- Legal screens/routes: `/member/terms`, `/member/privacy-policy`, `/member/about`,
  `/member/help`, `/member/licences`, `/policy/refund|cancellation|community`, `/admin/terms`,
  `/admin/about-us`, `/admin/help-support`.
- `reviews` table (+ `admin_manage_reviews` FOR ALL owner policy, rating trigger), `queries`
  table, `users.is_app_owner`, `owner_recovery_console_screen.dart` (app-owner gating pattern).
- `lib/core/app_snackbar.dart`, `lib/theme/app_palette.dart`, actor-scoped RLS conventions in
  `migrations/2026-06-18_actor_scope_inserts.sql`.

---

## Architecture

```
┌──────────────────────────── In-App Legal (Req 1) ────────────────────────────┐
│  lib/legal/legal_content.dart   ← SINGLE in-app source of truth (mirrors      │
│     kLegalLastUpdated, LegalDoc {title, intro, sections[], related[]}            │
│     terms / privacy / refund / cancellation / community / about                  │
│                    │                                                             │
│  policy_screens.dart (_PolicyScaffold)  ─ renders ─►  Refund/Cancellation/      │
│  member_terms_screen / terms_screen (admin)             Community/Terms/Privacy/ │
│  member_privacy_policy_screen / member_about / about_us  About screens           │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────── UGC Report / Block / Moderate (Req 2–5) ──────────────┐
│  DB (migration 2026-06-28_ugc_moderation.sql):                                  │
│    abuse_reports(reporter_id, target_type, target_id, library_id, reason,       │
│                  description, status, reviewed_by, reviewed_at)  + RLS           │
│    user_blocks(blocker_id, blocked_id)  + RLS  + unique                          │
│    reviews.hidden / hidden_by / hidden_reason  (+ SELECT policies filter hidden) │
│                                                                                  │
│  Widgets/Services:                                                              │
│    report_sheet.dart   showReportSheet(targetType,targetId,libraryId)            │
│    moderation_service.dart  submitReport / blockUser / unblockUser /             │
│                             loadMyBlockedIds / hideReview / unhideReview         │
│  Entry points:                                                                  │
│    • Review card overflow → Report / Block author   (public profile, all_reviews)│
│    • Library public profile → Report library                                     │
│    • Admin query/member view → Report member                                     │
│    • Owner all_reviews / reply sheet → Hide review (own library)                 │
│    • App-owner → /owner/abuse-reports console (open reports + hide/dismiss)       │
│    • Settings → /settings/blocked (manage/unblock)                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Components and Interfaces

### Part A — Legal content sync

#### A1. `lib/legal/legal_content.dart` (new — single source of truth)
A pure-Dart content module (no dependency). Mirrors the `legal/*.md` files.

```dart
class LegalSection { final String heading; final String body;
  const LegalSection(this.heading, this.body); }

class LegalDoc {
  final String title;
  final String intro;
  final List<LegalSection> sections;
  final List<LegalRelated> related;   // e.g. ('Privacy Policy', '/member/privacy-policy')
  const LegalDoc({required this.title, required this.intro,
                  required this.sections, this.related = const []});
}

const String kLegalLastUpdated = 'Last updated: <FINALIZATION DATE>';
const String kSupportEmail   = 'ashish.premierbro@gmail.com';
const String kSupportPhone   = '+91 72978 79930';
const String kOperatorName   = 'Ashish Kumar';
const String kOperatorPlace  = 'Alwar, Rajasthan, India';
const String kAppFullName    = 'Silence – Library Management & QR Attendance';
const String kWebsite        = 'https://silenceapp.in';

const LegalDoc legalTerms = LegalDoc( ... );
const LegalDoc legalPrivacy = LegalDoc( ... );
const LegalDoc legalRefund = LegalDoc( ... );
const LegalDoc legalCancellation = LegalDoc( ... );
const LegalDoc legalCommunity = LegalDoc( ... );
const LegalDoc legalAbout = LegalDoc( ... );
```

Content is transcribed from the canonical `legal/*.md` files (paraphrased into the
section/heading shape `_PolicyScaffold` expects). The `[INSERT DATE]` placeholders in the `.md`
files are resolved to the finalization date and mirrored in `kLegalLastUpdated`.

#### A2. Shared renderer (extend `_PolicyScaffold`)
Promote/extend `_PolicyScaffold` (currently private in `policy_screens.dart`) into a reusable
widget `LegalDocScreen(doc: LegalDoc)`:
- Header "Last updated" reads `kLegalLastUpdated` (no stale hardcoded dates).
- Renders intro + sections (dark-aware via `context.palette`, warm-orange app bar).
- Renders a "Related policies" footer of tappable chips → `Navigator.pushNamed` (Req 1.10).
- Footer contact card shows `kSupportEmail`.

#### A3. Screen refactors (point each to `legal_content`)
| Screen / route | Renders |
|---|---|
| `RefundPolicyScreen` `/policy/refund` | `legalRefund` |
| `CancellationPolicyScreen` `/policy/cancellation` | `legalCancellation` |
| `CommunityGuidelinesScreen` `/policy/community` | `legalCommunity` |
| `MemberTermsScreen` `/member/terms` · `TermsScreen` `/admin/terms` | `legalTerms` (identical) |
| `MemberPrivacyPolicyScreen` `/member/privacy-policy` | `legalPrivacy` |
| `MemberAboutScreen` `/member/about` · `AboutUsScreen` `/admin/about-us` | `legalAbout` (identical) |

`/member/help` and `/admin/help-support` stay functional support/report forms; only their
contact details (email/phone) are corrected to the locked values. `/member/licences` stays as-is
(third-party licences) — out of scope for legal copy.

> Refund + Cancellation remain two screens (existing routes) but their content is sourced from the
> single `refund_and_cancellation_policy.md`, split into the two `LegalDoc`s.

### Part B — UGC schema (migration)

`silence_app/migrations/2026-06-28_ugc_moderation.sql` (idempotent; folded into
`supabase_schema.sql` after the user applies it):

```sql
-- abuse_reports ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS abuse_reports (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_type  TEXT NOT NULL CHECK (target_type IN ('review','query','user','library')),
  target_id    UUID NOT NULL,
  library_id   UUID REFERENCES libraries(id) ON DELETE CASCADE,  -- context, nullable
  reason       TEXT NOT NULL CHECK (reason IN
                 ('spam','harassment','inappropriate','impersonation','copyright','other')),
  description  TEXT,
  status       TEXT NOT NULL DEFAULT 'open'
                 CHECK (status IN ('open','reviewed','actioned','dismissed')),
  reviewed_by  UUID REFERENCES users(id),
  reviewed_at  TIMESTAMPTZ,
  created_at   TIMESTAMPTZ DEFAULT now()
);
-- one OPEN report per (reporter, target) → blocks duplicate spam
CREATE UNIQUE INDEX IF NOT EXISTS uq_abuse_open
  ON abuse_reports(reporter_id, target_type, target_id) WHERE status = 'open';

ALTER TABLE abuse_reports ENABLE ROW LEVEL SECURITY;
-- insert only as yourself
CREATE POLICY "report_insert_self" ON abuse_reports
  FOR INSERT WITH CHECK (reporter_id = auth.uid());
-- read: your own reports, OR app-owner, OR owner of the report's library
CREATE POLICY "report_select_scoped" ON abuse_reports
  FOR SELECT USING (
    reporter_id = auth.uid()
    OR EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.is_app_owner)
    OR EXISTS (SELECT 1 FROM libraries l WHERE l.id = abuse_reports.library_id
               AND l.owner_id = auth.uid())
  );
-- update (status/review): app-owner, or owner of the report's library
CREATE POLICY "report_update_moderator" ON abuse_reports
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.is_app_owner)
    OR EXISTS (SELECT 1 FROM libraries l WHERE l.id = abuse_reports.library_id
               AND l.owner_id = auth.uid())
  ) WITH CHECK (true);

-- user_blocks ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_blocks (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ DEFAULT now(),
  UNIQUE (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);
ALTER TABLE user_blocks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "blocks_owner_all" ON user_blocks
  FOR ALL USING (blocker_id = auth.uid()) WITH CHECK (blocker_id = auth.uid());

-- reviews moderation columns ---------------------------------------------------
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS hidden     BOOLEAN DEFAULT false;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS hidden_by  UUID REFERENCES users(id);
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS hidden_reason TEXT;
-- public/member SELECT policies updated to exclude hidden rows for non-moderators
-- (owner via admin_manage_reviews FOR ALL still sees/manages them).
```

The migration also documents (in a comment) the two lines to add to the account-deletion
function so a deleted user's `abuse_reports`/`user_blocks` rows are cleaned up.

> **Owner delete already works:** `admin_manage_reviews` (FOR ALL) lets a library owner DELETE a
> review on their own library today. We add a reversible **hide** (`hidden`) as the primary,
> honest moderation action (recoverable, audit-friendly); hard delete stays available.

### Part C — UGC UI & service

#### C1. `lib/services/moderation_service.dart` (new)
```dart
class ModerationService {
  static Future<void> submitReport({
    required String targetType, required String targetId,
    String? libraryId, required String reason, String? description });
    // maps 23505 (duplicate open report) → friendly "already reported" message

  static Future<void> blockUser(String blockedUserId);
  static Future<void> unblockUser(String blockedUserId);
  static Future<Set<String>> loadMyBlockedIds();      // for client-side filtering
  static Future<List<Map<String,dynamic>>> myBlocks();// for the manage screen

  static Future<void> hideReview(String reviewId, {String? reason});
  static Future<void> unhideReview(String reviewId);
}
```
All methods throw on failure (callers show `AppSnackbar.error` via `friendlyError`).

#### C2. `lib/widgets/report_sheet.dart` (new)
`Future<bool> showReportSheet(BuildContext, {required String targetType, required String targetId,
String? libraryId, String? targetLabel})` — modal bottom sheet:
- Reason as selectable chips (Spam, Harassment/abuse, Inappropriate, Impersonation, Copyright,
  Other), optional multiline description, Submit.
- On submit → `ModerationService.submitReport`; success → `AppSnackbar.success("Report sent")`;
  duplicate → `AppSnackbar.info("You've already reported this — we're reviewing it")`; other
  failure → `AppSnackbar.error(friendlyError(e))`. Dark-aware, warm-orange.

#### C3. Entry points (wire into existing screens)
- **Review overflow menu** in `library_public_profile_screen.dart`, `admin/all_reviews_screen.dart`,
  `library_profile_screen.dart` recent reviews → `Report review` + `Block this user` (not shown on
  your own review). Owner/app-owner additionally see `Hide review`.
- **Library public profile** header overflow → `Report library`.
- **Admin query / member context** (`admin_home.dart` query view) → `Report member`.
- **Hidden reviews** are filtered out of public/member-facing lists client-side too (defense in
  depth); blocked authors' reviews filtered using `loadMyBlockedIds()`.

#### C4. `lib/screens/member_blocked_users_screen.dart` (new) — route `/settings/blocked`
List of blocked users with Unblock. Entry from member privacy/security settings
(`member_privacy_security_screen.dart`). Honest empty state when none.

#### C5. `lib/screens/owner_abuse_reports_screen.dart` (new) — route `/owner/abuse-reports`
Gated by `users.is_app_owner` (same guard as recovery console). Lists `open` reports
(target type, reason, description, time). Per report: open the target where feasible, and actions
**Hide content** (for reviews → `hideReview`), **Dismiss** (status→`dismissed`), **Mark actioned**
(status→`actioned`). Entry added to `admin_profile_tab.dart` Operations section (next to
Recovery Console), only when `_isAppOwner`.

Library owners reach reports about their own library through the same data via RLS; for this
iteration the app-owner console is the primary moderation surface, and owner-side review hiding is
available inline on `all_reviews_screen`. Broader per-owner report inbox is listed as deferred.

---

## Data Models

| Table | New? | Key columns | RLS summary |
|---|---|---|---|
| `abuse_reports` | new | reporter_id, target_type, target_id, library_id, reason, description, status, reviewed_by/at | insert self · select self/app-owner/lib-owner · update moderator |
| `user_blocks` | new | blocker_id, blocked_id (unique pair) | all scoped to blocker_id |
| `reviews` | +cols | hidden, hidden_by, hidden_reason | SELECT excludes hidden for non-moderators; owner manages |

Report `reason` enum: `spam | harassment | inappropriate | impersonation | copyright | other`.
Report `status` enum: `open | reviewed | actioned | dismissed`.

---

## Error Handling

- **Report submit failure / duplicate:** never claim success. PostgREST `23505` (unique open
  report) → friendly "already reported". Network/other → `friendlyError` + retry affordance.
- **Block/unblock failure:** honest error; the block list reflects only confirmed DB state.
- **Hide/unhide failure:** the review's visible state only changes after the DB write succeeds.
- **App-owner console:** if `is_app_owner` is false (or the check fails) the screen shows an
  "not authorized" state and does not load reports (mirrors recovery console).
- **Block enforcement limitation (documented):** with no server tier, blocking hides the blocked
  user's content from the blocker client-side and prevents the blocker's UI from initiating new
  contact; it cannot force-stop server-side delivery. The UI never claims more than it does.

---

## Testing Strategy

- **Static:** `flutter analyze` after each batch — target 0 new errors over baseline. No new
  dependency is introduced, so an APK build is not required (per project token rules); a build is
  only triggered if that assumption changes.
- **Migration safety:** SQL is idempotent (`if not exists`, policy drop/create); the user applies
  it in the Supabase SQL editor and verifies with quick checks (insert own report OK; insert
  report as someone else FAILS; block self FAILS via CHECK; hidden review not visible to a
  non-owner member). The spec keeps the migration "pending user apply" until confirmed.
- **Manual device checks (documented for the user):** report a review → appears in app-owner
  console; owner hides a review → disappears from public profile; block a user → their review
  hides for me; unblock → returns; legal screens render correctly in light + dark with correct
  operator/grievance/region copy and working related-policy links.
- **Store mapping verification:** confirm each Play UGC requirement (in-app report, block users,
  moderation/removal) and the Data-Safety/privacy disclosures map to a delivered piece.

---

## Design Decisions and Rationales

- **D1 — Dart content module over `flutter_markdown` asset viewer.** A bundled-markdown viewer
  gives literal single-sourcing but adds a dependency (build required), heavier rendering, and the
  `.md` files' link/format quirks. The existing `_PolicyScaffold` is already dark-aware and on-brand.
  Choosing a single `legal_content.dart` keeps one in-app update location (satisfies Req 1.7),
  needs no new dependency (analyze-only, token-friendly), and preserves styling. Cost: legal copy
  is mirrored from `.md` to Dart manually — mitigated by keeping both in one PR and noting the link.
- **D2 — Reversible `hidden` flag over hard delete for moderation.** Hiding is honest, recoverable,
  and audit-friendly; the rating trigger can be kept consistent. Owner hard-delete remains possible
  via existing RLS for genuine removal.
- **D3 — App-owner console as the primary moderation surface this iteration.** RLS already lets the
  owner manage their library's reviews; building a full per-owner report inbox is larger. A minimal
  app-owner console + inline owner hide covers the policy requirement now; per-owner inbox is
  explicitly deferred (Req 4.5).
- **D4 — Client-side block filtering with a documented limitation.** Honors the "no server tier"
  rule and the "no dishonest UI" rule rather than faking server-enforced blocking.
- **D5 — Unique partial index for duplicate-report prevention.** Enforces "no silent duplicate
  spam" (Req 2.5) at the DB level, surfaced to the user as a friendly message.

---

## Correctness Properties

These invariants should hold for any valid input and are good candidates for property-based or
table-driven tests where the logic is pure/testable (model + service layer).

### Property 1: No self-report of own review
For any user `u` and review `r` authored by `u`, the report entry point is not offered, and a
forged self-report is meaningless (UI guards it).

**Validates: Requirements 2.5**

### Property 2: No duplicate open report
For any (reporter, target_type, target_id), at most one row with `status = 'open'` can exist (DB
unique partial index); a second attempt yields a friendly "already reported" outcome, never a
success claim.

**Validates: Requirements 2.3, 2.5**

### Property 3: Block is scoped in ownership
For any blocker `b` and blocked `x`, `loadMyBlockedIds()` for `b` contains `x` iff a
`user_blocks(b, x)` row exists; `b` can only ever create/remove rows where `blocker_id = b`.
`b == x` is rejected (CHECK).

**Validates: Requirements 3.2, 3.5**

### Property 4: Block hides content
For any review list `R` and blocked set `B` for the current user, the rendered list contains no
review whose author ∈ `B` (client filter is a pure function of `R` and `B`).

**Validates: Requirements 3.3**

### Property 5: Hidden reviews invisible to non-moderators
For any review `r` with `hidden = true`, `r` is excluded from public/member-facing lists; it
remains visible only to the library owner / app-owner. Hiding then unhiding returns `r` to its
prior visibility (idempotent toggle).

**Validates: Requirements 4.1, 4.3**

### Property 6: Report reason/status domains are closed
Any persisted `reason` ∈ the fixed reason set and any `status` ∈ {open, reviewed, actioned,
dismissed} (DB CHECK constraints).

**Validates: Requirements 2.2, 5.2**

### Property 7: Legal content single-sourcing
Every legal screen's rendered title/sections/last-updated derive from exactly one
`LegalDoc`/constant in `legal_content.dart`; the member and admin variants of Terms (and of
About) render identical content.

**Validates: Requirements 1.2, 1.7**

### Property 8: Honest result mapping
For every report/block/hide action, a success toast is shown iff the underlying DB write returned
success; any thrown error maps to an error/info toast and no success is shown.

**Validates: Requirements 2.4, 3.2, 4.3**

## Out of Scope / Deferred

- Buying/hosting `silenceapp.in` and website legal pages (user task).
- Lawyer review / legal sign-off (user task; docs are informational, not legal advice).
- Per-library-owner full report inbox UI (app-owner console + inline hide ship now).
- Server-enforced (vs client-side) block delivery — needs a server tier the project intentionally
  avoids.
- `flutter_markdown`-based dynamic rendering of the `.md` files.
