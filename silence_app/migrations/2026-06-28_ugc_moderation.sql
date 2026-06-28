-- ============================================================================
-- 2026-06-28 — UGC moderation: reporting, blocking, and hide-review
-- ============================================================================
-- WHY: Google Play's User-Generated Content policy requires apps that host user
--   content (reviews, member↔library queries, profile names/photos, library
--   photos) to provide an in-app way to REPORT objectionable content, BLOCK
--   abusive users, and a path to MODERATE/REMOVE content. SILENCE had none.
--
-- WHAT THIS ADDS:
--   • abuse_reports  — a report row per (reporter, target); one OPEN report per
--                      (reporter, target) via a partial unique index.
--   • user_blocks    — a blocker→blocked relationship (client-side filtering
--                      hides a blocked author's content for the blocker; there
--                      is no server tier to intercept delivery — documented).
--   • reviews.hidden / hidden_by / hidden_reason — reversible moderation. Owners
--     can already DELETE their library's reviews (admin_manage_reviews FOR ALL);
--     hiding is the honest, recoverable default. Public/member SELECT policies
--     are updated to exclude hidden rows for non-moderators.
--
-- SAFETY: idempotent (IF NOT EXISTS, policy drop/create). No data is destroyed.
--   Apply once in the Supabase SQL editor, verify (see VERIFY), then fold into
--   supabase_schema.sql. The app treats this feature as PENDING until applied.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────
-- 1) abuse_reports
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.abuse_reports (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    target_type  TEXT NOT NULL CHECK (target_type IN ('review','query','user','library')),
    target_id    UUID NOT NULL,
    library_id   UUID REFERENCES public.libraries(id) ON DELETE CASCADE,  -- context, nullable
    reason       TEXT NOT NULL CHECK (reason IN
                   ('spam','harassment','inappropriate','impersonation','copyright','other')),
    description  TEXT,
    status       TEXT NOT NULL DEFAULT 'open'
                   CHECK (status IN ('open','reviewed','actioned','dismissed')),
    reviewed_by  UUID REFERENCES public.users(id),
    reviewed_at  TIMESTAMPTZ,
    created_at   TIMESTAMPTZ DEFAULT now()
);

-- At most one OPEN report per (reporter, target) → blocks duplicate spam.
CREATE UNIQUE INDEX IF NOT EXISTS uq_abuse_open
    ON public.abuse_reports(reporter_id, target_type, target_id)
    WHERE status = 'open';

CREATE INDEX IF NOT EXISTS idx_abuse_status  ON public.abuse_reports(status, created_at);
CREATE INDEX IF NOT EXISTS idx_abuse_library ON public.abuse_reports(library_id);

ALTER TABLE public.abuse_reports ENABLE ROW LEVEL SECURITY;

-- Insert only as yourself.
DROP POLICY IF EXISTS "report_insert_self" ON public.abuse_reports;
CREATE POLICY "report_insert_self" ON public.abuse_reports
    FOR INSERT WITH CHECK (reporter_id = auth.uid());

-- Read: your own reports, OR app-owner, OR the owner of the report's library.
DROP POLICY IF EXISTS "report_select_scoped" ON public.abuse_reports;
CREATE POLICY "report_select_scoped" ON public.abuse_reports
    FOR SELECT USING (
        reporter_id = auth.uid()
        OR EXISTS (SELECT 1 FROM public.users u
                   WHERE u.id = auth.uid() AND u.is_app_owner)
        OR EXISTS (SELECT 1 FROM public.libraries l
                   WHERE l.id = public.abuse_reports.library_id
                     AND l.owner_id = auth.uid())
    );

-- Update (triage status / set reviewer): app-owner, or the library's owner.
DROP POLICY IF EXISTS "report_update_moderator" ON public.abuse_reports;
CREATE POLICY "report_update_moderator" ON public.abuse_reports
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM public.users u
                WHERE u.id = auth.uid() AND u.is_app_owner)
        OR EXISTS (SELECT 1 FROM public.libraries l
                   WHERE l.id = public.abuse_reports.library_id
                     AND l.owner_id = auth.uid())
    ) WITH CHECK (true);

-- ─────────────────────────────────────────────────────────────────────────
-- 2) user_blocks
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_blocks (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    blocked_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ DEFAULT now(),
    UNIQUE (blocker_id, blocked_id),
    CHECK (blocker_id <> blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_user_blocks_blocker ON public.user_blocks(blocker_id);

ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;

-- A user manages only their own block rows.
DROP POLICY IF EXISTS "blocks_owner_all" ON public.user_blocks;
CREATE POLICY "blocks_owner_all" ON public.user_blocks
    FOR ALL USING (blocker_id = auth.uid())
    WITH CHECK (blocker_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────
-- 3) reviews moderation columns + hidden-aware SELECT policies
-- ─────────────────────────────────────────────────────────────────────────
ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS hidden        BOOLEAN DEFAULT false;
ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS hidden_by     UUID REFERENCES public.users(id);
ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS hidden_reason TEXT;

-- Recreate the two SELECT policies so non-moderators don't see hidden rows.
-- (The library owner keeps full access via admin_manage_reviews FOR ALL; the
--  app-owner gets an explicit read policy below for the moderation console.
--  The author may still see their own review so it doesn't appear to vanish.)
DROP POLICY IF EXISTS "member_read_reviews" ON public.reviews;
CREATE POLICY "member_read_reviews" ON public.reviews
    FOR SELECT
    USING (
        library_id IN (SELECT library_id FROM public.memberships WHERE member_id = auth.uid())
        AND (hidden IS NOT TRUE OR member_id = auth.uid())
    );

DROP POLICY IF EXISTS "public_read_active_library_reviews" ON public.reviews;
CREATE POLICY "public_read_active_library_reviews" ON public.reviews
    FOR SELECT
    USING (
        library_id IN (SELECT id FROM public.libraries WHERE status = 'active')
        AND (hidden IS NOT TRUE OR member_id = auth.uid())
    );

-- App-owner can read all reviews (incl. hidden) for the moderation console.
DROP POLICY IF EXISTS "app_owner_read_reviews" ON public.reviews;
CREATE POLICY "app_owner_read_reviews" ON public.reviews
    FOR SELECT
    USING (EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.is_app_owner));

-- ============================================================================
-- ACCOUNT-DELETION CLEANUP (manual follow-up — NOT auto-applied here)
-- ----------------------------------------------------------------------------
-- Add these lines to the account-deletion / data-wipe routines so a removed
-- user's moderation rows are cleaned up. Locations (each has a member-wipe block
-- alongside the existing `DELETE FROM public.reviews WHERE member_id = ...`):
--   • supabase_schema.sql  (canonical deletion function)
--   • migrations/2026-06-18_role_change_rpc.sql        (change_my_role)
--   • migrations/2026-06-18_lock_user_privileged_columns.sql
--   • migrations/2026-06-18_account_recovery_rpcs.sql  (uses p_user_id)
--
--   DELETE FROM public.abuse_reports WHERE reporter_id = <uid>;
--   DELETE FROM public.user_blocks   WHERE blocker_id  = <uid> OR blocked_id = <uid>;
--
-- (Reports/blocks that merely TARGET the deleted user are removed via the
--  ON DELETE CASCADE FKs on reporter_id/blocker_id/blocked_id where applicable;
--  abuse_reports.target_id is a loose UUID by design and needs no FK.)
-- ============================================================================

-- ============================================================================
-- VERIFY (run as different signed-in users in the SQL editor / app):
--   • Insert an abuse_reports row with reporter_id = auth.uid()  → OK.
--   • Insert one with a DIFFERENT reporter_id                    → must FAIL (RLS).
--   • Insert a 2nd OPEN report for the same (reporter,target)    → must FAIL (uq_abuse_open / 23505).
--   • Insert user_blocks with blocker_id = blocked_id           → must FAIL (CHECK).
--   • Set a review hidden = true; read it as a non-member/public → row NOT returned.
--     Read it as the library owner or app-owner                 → row returned.
-- ROLLBACK (if ever needed):
--   DROP POLICY ... ; DROP TABLE public.abuse_reports; DROP TABLE public.user_blocks;
--   ALTER TABLE public.reviews DROP COLUMN hidden, DROP COLUMN hidden_by, DROP COLUMN hidden_reason;
--   and restore the original member_read_reviews / public_read_active_library_reviews policies.
-- ============================================================================
