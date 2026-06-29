-- ============================================================================
-- 2026-06-30 — exit_my_membership(): server-side DUES guard
-- ============================================================================
--
-- The member-side Exit flow already blocks exit in the UI when there are
-- pending dues, but the SECURITY DEFINER exit_my_membership() RPC did not
-- enforce it — a crafted client call could still exit while owing money.
--
-- FIX: before marking the membership 'exited', sum the member's PENDING
-- payments for that membership. If > 0, refuse with a clear message. Only the
-- admin can clear dues (mark a payment 'confirmed'), so the member must settle
-- with the owner first. Refund rows (negative amounts) are ignored.
--
-- Idempotent: CREATE OR REPLACE. Same signature, so all callers keep working.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.exit_my_membership(p_membership_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid   uuid := auth.uid();
    v_owner uuid;
    v_seat  uuid;
    v_dues  int;
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

    -- Dues guard: any positive pending payment on this membership blocks exit.
    SELECT COALESCE(sum(amount), 0) INTO v_dues
      FROM public.payments
     WHERE membership_id = p_membership_id
       AND status = 'pending'
       AND amount > 0;
    IF v_dues > 0 THEN
        RAISE EXCEPTION
            'You have pending dues of ₹% at this library. Please clear them with the library owner before exiting.', v_dues
            USING errcode = 'P0001';
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

-- ============================================================================
-- VERIFY:
--   • Member with a pending payment → exit_my_membership(...) raises the dues
--     message (UI already pre-blocks; this is defense in depth).
--   • Admin marks the payment 'confirmed' → member can now exit.
-- ROLLBACK: re-create the no-dues-check body from
--   migrations/2026-06-18_memberships_member_exit_rpc.sql.
-- ============================================================================
