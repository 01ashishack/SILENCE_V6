-- ============================================================================
-- 2026-07-03 — request status guard (seat/shift/hold member inserts → pending)
-- ============================================================================
--
-- PROBLEM: member INSERT policies on seat_change_requests / shift_change_requests
-- / hold_requests check only `member_id = auth.uid()` — a member could POST a row
-- with status='approved'. (Low real impact: admin tabs filter status='pending'
-- and the seat/shift only actually moves via an owner-run RPC/flow — but this is
-- defense-in-depth so a self-set status can never short-circuit review.)
--
-- FIX: re-create each member INSERT policy with `AND status = 'pending'`. Admin
-- (owner-scoped) update policies are untouched; the app already inserts these as
-- 'pending', so no legitimate flow changes.
--
-- Idempotent. Apply in the Supabase SQL editor.
-- ============================================================================

DROP POLICY IF EXISTS "Member insert seat change request" ON public.seat_change_requests;
CREATE POLICY "Member insert seat change request" ON public.seat_change_requests
    FOR INSERT WITH CHECK (member_id = auth.uid() AND status = 'pending');

DROP POLICY IF EXISTS "Member insert shift change request" ON public.shift_change_requests;
CREATE POLICY "Member insert shift change request" ON public.shift_change_requests
    FOR INSERT WITH CHECK (member_id = auth.uid() AND status = 'pending');

DROP POLICY IF EXISTS "Member insert hold request" ON public.hold_requests;
CREATE POLICY "Member insert hold request" ON public.hold_requests
    FOR INSERT WITH CHECK (member_id = auth.uid() AND status = 'pending');

-- ============================================================================
-- VERIFY:
--   • As a member, insert a seat/shift/hold request with status='approved'
--       → REJECTED by RLS. With status='pending' (or default) → OK.
--   • Admin approve/reject (owner UPDATE policy) → unaffected.
-- ROLLBACK: re-create each policy with only `WITH CHECK (member_id = auth.uid())`.
-- ============================================================================
