-- 2026-06-16 — Let a member WITHDRAW their own pending join request.
--
-- BUG: the member "Withdraw Application" button ran
--   UPDATE join_requests SET status='withdrawn' WHERE id = <req>
-- but join_requests had only an ADMIN update policy. RLS silently matched 0
-- rows (no error), so the button showed "withdrawn successfully" while the row
-- stayed status='pending' — the admin still saw it in action-required / join
-- requests and could approve it.
--
-- FIX: a narrow member policy that allows ONLY the transition
--   own pending request  ->  status='withdrawn'
-- (USING gates the row to the member's own pending request; WITH CHECK forces
-- the new status to 'withdrawn', so a member can't self-approve.)
--
-- Additive + idempotent.

DROP POLICY IF EXISTS "Member withdraw own pending request" ON public.join_requests;

CREATE POLICY "Member withdraw own pending request" ON public.join_requests
    FOR UPDATE
    USING (member_id = auth.uid() AND status = 'pending')
    WITH CHECK (member_id = auth.uid() AND status = 'withdrawn');
