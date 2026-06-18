-- ============================================================================
-- 2026-06-18 — Close the open memberships UPDATE (audit P5-01)
-- ============================================================================
--
-- The policy "System can update (auto-hold, auto-expiry)" was
--     FOR UPDATE USING (true) WITH CHECK (true)
-- i.e. ANY authenticated user could rewrite ANY membership (extend their own
-- end_date, free time, sabotage others). It was load-bearing for exactly ONE
-- client flow: a member exiting their own membership (member_home → set
-- status='exited' + release the seat).
--
-- FIX
--   * Move member self-exit behind a SECURITY DEFINER RPC exit_my_membership()
--     that verifies the membership belongs to the caller, then releases the seat
--     and marks the membership exited.
--   * DROP the USING(true) policy. Admin writes stay covered by
--     "Admin update (approve, renew, hold, transfer)" (owner-scoped). Server
--     cron jobs (auto-hold/expiry) run as service_role, which bypasses RLS.
--
-- PRECONDITION: ship the app build that calls rpc('exit_my_membership', ...)
--   (member_home) together with applying this — otherwise member exit breaks.
--
-- Idempotent: safe to re-run.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.exit_my_membership(p_membership_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid   uuid := auth.uid();
    v_owner uuid;
    v_seat  uuid;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not signed in' USING errcode = '42501';
    END IF;
    SELECT member_id, seat_id INTO v_owner, v_seat
      FROM public.memberships WHERE id = p_membership_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Membership not found' USING errcode = 'P0002';
    END IF;
    IF v_owner <> v_uid THEN
        RAISE EXCEPTION 'Not your membership' USING errcode = '42501';
    END IF;

    IF v_seat IS NOT NULL THEN
        UPDATE public.seats
           SET status = 'vacant', occupied_by_member_id = NULL
         WHERE id = v_seat;
    END IF;
    UPDATE public.memberships
       SET status = 'exited', exited_at = now()
     WHERE id = p_membership_id;
END;
$$;
REVOKE ALL ON FUNCTION public.exit_my_membership(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.exit_my_membership(uuid) TO authenticated;

-- Remove the world-open membership UPDATE.
DROP POLICY IF EXISTS "System can update (auto-hold, auto-expiry)" ON public.memberships;

-- ============================================================================
-- VERIFY (on a device):
--   • As a member, exit a membership → it flips to 'exited' and the seat frees.
--   • As that member, a direct  update public.memberships set end_date=...
--       where id='<own membership>'  → must FAIL (no permission).
--   • Admin renew / hold / seat-change / transfer still work (owner-scoped policy).
-- ROLLBACK:
--   CREATE POLICY "System can update (auto-hold, auto-expiry)" ON public.memberships
--       FOR UPDATE USING (true) WITH CHECK (true);
--   DROP FUNCTION IF EXISTS public.exit_my_membership(uuid);
-- ============================================================================
