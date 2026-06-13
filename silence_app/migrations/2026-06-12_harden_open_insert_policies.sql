-- ============================================================================
-- 2026-06-12 — Harden the four open `WITH CHECK (true)` insert policies
-- ============================================================================
--
-- CONTEXT (audit P5-08 / P10-10..12)
--   notifications, audit_log, badges and referrals each had an INSERT policy of
--   WITH CHECK (true) — so ANY caller, including the UNAUTHENTICATED `anon` role
--   (which only needs the public anon key shipped in the app), could insert
--   arbitrary rows: forged notifications / phishing, fake audit entries,
--   self-granted badges, fabricated referrals.
--
-- WHAT THIS DOES  (the SAFE, non-breaking part)
--   Require the inserter to be AUTHENTICATED: WITH CHECK (auth.uid() IS NOT NULL).
--   Every legitimate insert into these tables in the app happens AFTER login, so
--   this breaks nothing — it just removes the unauthenticated forgery surface.
--
-- WHAT THIS DELIBERATELY DOES *NOT* DO  (see docs_fix/SECURITY_RLS_ANALYSIS.md)
--   It does NOT scope the insert to "actor = self / row belongs to me". The app
--   performs legitimate CROSS-ACTOR client writes that such a policy would reject
--   today, e.g.:
--     • join_flow_screen.dart:633/650 — a MEMBER writes an audit_log row and a
--       notification ADDRESSED TO THE LIBRARY OWNER during a rejoin.
--     • member_analytics_service.dart:_awardBadge — the badge engine inserts a
--       badge + notification for a memberId that is not always auth.uid().
--   Properly scoping these requires moving the privileged write behind a
--   SECURITY DEFINER RPC / Edge Function first (root cause RC-1: no server tier).
--
-- SAFE TO APPLY with no app changes (additive hardening, no behavior change for
--   authenticated users).
-- VERIFY (one quick check): after applying, trigger any in-app notification
--   (e.g. admin Hold or Remove a member) and confirm it still arrives — i.e.
--   authenticated inserts still succeed.
-- ROLLBACK: re-create each policy below with `WITH CHECK (true)`.
-- ============================================================================

DROP POLICY IF EXISTS "System insert notifications" ON notifications;
CREATE POLICY "System insert notifications" ON notifications
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "System insert audit log" ON audit_log;
CREATE POLICY "System insert audit log" ON audit_log
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "System insert badges" ON badges;
CREATE POLICY "System insert badges" ON badges
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "System insert referrals" ON referrals;
CREATE POLICY "System insert referrals" ON referrals
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
