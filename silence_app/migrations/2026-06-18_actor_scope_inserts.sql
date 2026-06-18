-- ============================================================================
-- 2026-06-18 — Actor-scope the forgeable INSERTs (audit P5-08)
-- ============================================================================
--
-- Previously notifications / audit_log / badges / referrals had
--     WITH CHECK (auth.uid() IS NOT NULL)
-- i.e. any signed-in user could forge a row for anyone (spam notifications,
-- fake badges/referrals, write audit entries attributed to an owner). This
-- replaces each with a relationship-scoped check that still allows every
-- legitimate cross-actor write the app actually performs.
--
-- Companion code change: join_flow_screen no longer writes an owner-attributed
-- audit_log row (it kept only the owner notification, which is still allowed).
--
-- Idempotent.
-- ============================================================================

-- 1) notifications: self · owner→(member|applicant) · (member|applicant)→owner
DROP POLICY IF EXISTS "System insert notifications" ON public.notifications;
CREATE POLICY "Scoped insert notifications" ON public.notifications
    FOR INSERT WITH CHECK (
        -- a) a user notifying themselves
        user_id = auth.uid()
        -- b) a library owner notifying a MEMBER of one of their libraries
        OR EXISTS (
            SELECT 1 FROM memberships m
            JOIN libraries l ON l.id = m.library_id
            WHERE m.member_id = notifications.user_id AND l.owner_id = auth.uid()
        )
        -- c) a library owner notifying a pending/past APPLICANT at their library
        OR EXISTS (
            SELECT 1 FROM join_requests jr
            JOIN libraries l ON l.id = jr.library_id
            WHERE jr.member_id = notifications.user_id AND l.owner_id = auth.uid()
        )
        -- d) a member/applicant notifying the OWNER of a related library
        OR EXISTS (
            SELECT 1 FROM libraries l
            WHERE l.owner_id = notifications.user_id
              AND (
                EXISTS (SELECT 1 FROM memberships m
                        WHERE m.library_id = l.id AND m.member_id = auth.uid())
                OR EXISTS (SELECT 1 FROM join_requests jr
                           WHERE jr.library_id = l.id AND jr.member_id = auth.uid())
              )
        )
    );

-- 2) audit_log: only the acting admin may write their own entry
DROP POLICY IF EXISTS "System insert audit log" ON public.audit_log;
CREATE POLICY "Scoped insert audit log" ON public.audit_log
    FOR INSERT WITH CHECK (admin_id = auth.uid());

-- 3) badges: self-award, or the owner of the badge's library
DROP POLICY IF EXISTS "System insert badges" ON public.badges;
CREATE POLICY "Scoped insert badges" ON public.badges
    FOR INSERT WITH CHECK (
        member_id = auth.uid()
        OR EXISTS (SELECT 1 FROM libraries l
                   WHERE l.id = badges.library_id AND l.owner_id = auth.uid())
    );

-- 4) referrals: the inserting user must be a party to the referral
DROP POLICY IF EXISTS "System insert referrals" ON public.referrals;
CREATE POLICY "Scoped insert referrals" ON public.referrals
    FOR INSERT WITH CHECK (
        referrer_member_id = auth.uid() OR referred_member_id = auth.uid()
    );

-- ============================================================================
-- VERIFY (device):
--   • Admin: approve/reject a join request, hold/resume, end membership, assign
--     seat, answer a query, broadcast announcement → member gets the notification.
--   • Member: send a query / contact admin → owner gets the notification.
--   • Member analytics: a streak badge is awarded (self) with no error.
--   • Forgery: as a member, insert a notification for an UNRELATED user_id →
--     must FAIL; insert a badge for someone else's library → must FAIL.
-- ROLLBACK (restore open authenticated inserts):
--   each: DROP POLICY "Scoped insert X"; CREATE POLICY "System insert X"
--         FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
-- ============================================================================
