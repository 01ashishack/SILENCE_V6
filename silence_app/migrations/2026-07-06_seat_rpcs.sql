-- ============================================================================
-- 2026-07-06 — atomic seat mutation RPCs (audit P1: non-transactional seat ops)
-- ============================================================================
--
-- PROBLEM: admin seat reassignment (layout tab) and seat-change approval
-- (requests tab) did read→free-old→occupy-new→update-membership as SEPARATE
-- client calls. Concurrent actions could interleave → double-booking / orphaned
-- occupancy / membership-seat mismatch.
--
-- FIX: two owner-checked SECURITY DEFINER RPCs that claim the new seat with an
-- atomic conditional UPDATE (only if vacant), free the old seat, and sync the
-- membership in ONE transaction. Notifications + audit stay client-side.
--
-- PRECONDITION: ship the app build that calls these RPCs together with applying.
-- Idempotent. Apply in the Supabase SQL editor.
-- ============================================================================

-- ── reassign_seat: admin moves a member to another vacant seat (layout tab) ──
CREATE OR REPLACE FUNCTION public.reassign_seat(
    p_member_id  uuid,
    p_library_id uuid,
    p_new_seat_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid       uuid := auth.uid();
    v_mid       uuid;
    v_old_seat  uuid;
    v_new_label text;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not signed in' USING errcode = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.libraries
                    WHERE id = p_library_id AND owner_id = v_uid) THEN
        RAISE EXCEPTION 'Not authorized for this library' USING errcode = '42501';
    END IF;

    SELECT id, seat_id INTO v_mid, v_old_seat
      FROM public.memberships
     WHERE member_id = p_member_id AND library_id = p_library_id
       AND status IN ('active', 'trial')
     ORDER BY created_at DESC LIMIT 1;
    IF v_mid IS NULL THEN
        RAISE EXCEPTION 'No active membership for this member' USING errcode = 'P0002';
    END IF;

    -- Atomically claim the new seat (must be vacant and in this library).
    UPDATE public.seats
       SET status = 'occupied', occupied_by_member_id = p_member_id, updated_at = now()
     WHERE id = p_new_seat_id AND library_id = p_library_id AND status = 'vacant'
     RETURNING seat_label INTO v_new_label;
    IF v_new_label IS NULL THEN
        RAISE EXCEPTION 'That seat was just taken — pick another' USING errcode = 'P0001';
    END IF;

    IF v_old_seat IS NOT NULL AND v_old_seat <> p_new_seat_id THEN
        UPDATE public.seats
           SET status = 'vacant', occupied_by_member_id = NULL, updated_at = now()
         WHERE id = v_old_seat;
    END IF;

    UPDATE public.memberships SET seat_id = p_new_seat_id WHERE id = v_mid;

    RETURN jsonb_build_object('membership_id', v_mid, 'new_seat_label', v_new_label);
END;
$$;
REVOKE ALL ON FUNCTION public.reassign_seat(uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reassign_seat(uuid, uuid, uuid) TO authenticated;

-- ── approve_seat_change: owner approves a member's seat-change request ───────
CREATE OR REPLACE FUNCTION public.approve_seat_change(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid       uuid := auth.uid();
    v_req       public.seat_change_requests%ROWTYPE;
    v_new_label text;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not signed in' USING errcode = '42501';
    END IF;
    SELECT * INTO v_req FROM public.seat_change_requests WHERE id = p_request_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Request not found' USING errcode = 'P0002';
    END IF;
    IF v_req.status <> 'pending' THEN
        RAISE EXCEPTION 'This request has already been processed' USING errcode = 'P0001';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.libraries
                    WHERE id = v_req.library_id AND owner_id = v_uid) THEN
        RAISE EXCEPTION 'Not authorized for this library' USING errcode = '42501';
    END IF;
    IF v_req.new_seat_id IS NULL THEN
        RAISE EXCEPTION 'This request has no selected target seat' USING errcode = 'P0001';
    END IF;

    -- Claim the target seat: vacant, or already held by this member (idempotent).
    UPDATE public.seats
       SET status = 'occupied', occupied_by_member_id = v_req.member_id, updated_at = now()
     WHERE id = v_req.new_seat_id AND library_id = v_req.library_id
       AND (status = 'vacant' OR occupied_by_member_id = v_req.member_id)
     RETURNING seat_label INTO v_new_label;
    IF v_new_label IS NULL THEN
        RAISE EXCEPTION 'Target seat is no longer vacant — choose another' USING errcode = 'P0001';
    END IF;

    IF v_req.current_seat_id IS NOT NULL AND v_req.current_seat_id <> v_req.new_seat_id THEN
        UPDATE public.seats
           SET status = 'vacant', occupied_by_member_id = NULL, updated_at = now()
         WHERE id = v_req.current_seat_id;
    END IF;

    UPDATE public.memberships SET seat_id = v_req.new_seat_id WHERE id = v_req.membership_id;
    UPDATE public.seat_change_requests
       SET status = 'approved', approved_at = now() WHERE id = p_request_id;

    RETURN jsonb_build_object('member_id', v_req.member_id, 'new_seat_label', v_new_label);
END;
$$;
REVOKE ALL ON FUNCTION public.approve_seat_change(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_seat_change(uuid) TO authenticated;

-- ============================================================================
-- VERIFY:
--   • Admin reassign in layout tab → seat moves, old freed, membership synced.
--   • Two admins reassign to the same seat → one succeeds, the other gets
--     'That seat was just taken' (no double-book).
--   • Approve a seat-change request → seat moves + request marked approved.
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS public.reassign_seat(uuid,uuid,uuid);
--   DROP FUNCTION IF EXISTS public.approve_seat_change(uuid);
--   (then the client falls back to its prior multi-step path if reverted)
-- ============================================================================
