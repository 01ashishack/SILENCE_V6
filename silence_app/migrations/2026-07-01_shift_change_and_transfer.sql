-- ============================================================================
-- 2026-07-01 — Shift change (member request) + admin shift transfer
-- ============================================================================
--
-- 1. shift_change_requests — member asks to move to a different shift. Mirrors
--    seat_change_requests RLS (member inserts/reads own; owner reads/updates for
--    their library).
--
-- 2. transfer_member_shift() — owner-checked RPC that moves a member to a new
--    shift. Because seats belong to a specific shift (seats.shift_id), the old
--    seat is FREED; an optional new seat in the target shift is claimed
--    atomically. A price adjustment (₹, +charge or −credit) is recorded as a
--    payment row: charge-now → 'confirmed', else → 'pending' (a due). Notifies
--    the member + writes an audit row. All in one transaction.
--
-- Additive + idempotent.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.shift_change_requests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id   UUID NOT NULL REFERENCES memberships(id) ON DELETE CASCADE,
    member_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id      UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    current_shift_id   UUID REFERENCES shifts(id) ON DELETE SET NULL,
    requested_shift_id UUID REFERENCES shifts(id) ON DELETE SET NULL,
    reason          TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
    decided_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_shift_change_lib_status
    ON public.shift_change_requests (library_id, status, created_at);
CREATE INDEX IF NOT EXISTS idx_shift_change_member
    ON public.shift_change_requests (member_id, status);

ALTER TABLE public.shift_change_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Member view own shift change requests" ON public.shift_change_requests;
CREATE POLICY "Member view own shift change requests" ON public.shift_change_requests
    FOR SELECT USING (member_id = auth.uid());

DROP POLICY IF EXISTS "Admin view shift change requests" ON public.shift_change_requests;
CREATE POLICY "Admin view shift change requests" ON public.shift_change_requests
    FOR SELECT USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

DROP POLICY IF EXISTS "Member insert shift change request" ON public.shift_change_requests;
CREATE POLICY "Member insert shift change request" ON public.shift_change_requests
    FOR INSERT WITH CHECK (member_id = auth.uid());

DROP POLICY IF EXISTS "Admin update shift change request" ON public.shift_change_requests;
CREATE POLICY "Admin update shift change request" ON public.shift_change_requests
    FOR UPDATE USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

-- ── transfer_member_shift() ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.transfer_member_shift(
    p_membership_id    uuid,
    p_new_shift_id     uuid,
    p_new_seat_id      uuid    DEFAULT NULL,
    p_price_adjustment integer DEFAULT 0,
    p_charge_now       boolean DEFAULT true,
    p_reason           text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid        uuid := auth.uid();
    v_owner      uuid;
    v_member     uuid;
    v_lib        uuid;
    v_old_shift  uuid;
    v_old_seat   uuid;
    v_new_shift  public.shifts%ROWTYPE;
    v_new_label  text;
    v_pay_status text;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not signed in' USING errcode = '42501';
    END IF;

    SELECT member_id, library_id, shift_id, seat_id
      INTO v_member, v_lib, v_old_shift, v_old_seat
      FROM public.memberships WHERE id = p_membership_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Membership not found' USING errcode = 'P0002';
    END IF;

    SELECT owner_id INTO v_owner FROM public.libraries WHERE id = v_lib;
    IF v_owner IS DISTINCT FROM v_uid THEN
        RAISE EXCEPTION 'Not authorized for this library' USING errcode = '42501';
    END IF;

    SELECT * INTO v_new_shift FROM public.shifts WHERE id = p_new_shift_id;
    IF NOT FOUND OR v_new_shift.library_id <> v_lib THEN
        RAISE EXCEPTION 'Target shift not found in this library' USING errcode = 'P0002';
    END IF;
    IF p_new_shift_id = v_old_shift THEN
        RAISE EXCEPTION 'Member is already on that shift' USING errcode = 'P0001';
    END IF;

    -- Claim the new seat first (if one was chosen) so a race fails before we
    -- free the old seat. The seat must belong to the target shift + library.
    IF p_new_seat_id IS NOT NULL THEN
        UPDATE public.seats
           SET status = 'occupied', occupied_by_member_id = v_member, updated_at = now()
         WHERE id = p_new_seat_id AND library_id = v_lib
               AND shift_id = p_new_shift_id AND status = 'vacant'
         RETURNING seat_label INTO v_new_label;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Chosen seat is not available in the new shift' USING errcode = 'P0001';
        END IF;
    END IF;

    -- Free the old seat.
    IF v_old_seat IS NOT NULL THEN
        UPDATE public.seats
           SET status = 'vacant', occupied_by_member_id = NULL, updated_at = now()
         WHERE id = v_old_seat;
    END IF;

    -- Move the membership to the new shift (+ new seat or none).
    UPDATE public.memberships
       SET shift_id = p_new_shift_id, seat_id = p_new_seat_id
     WHERE id = p_membership_id;

    -- Price adjustment → a payment row (skip when zero).
    IF COALESCE(p_price_adjustment, 0) <> 0 THEN
        v_pay_status := CASE WHEN p_charge_now THEN 'confirmed' ELSE 'pending' END;
        INSERT INTO public.payments (membership_id, member_id, library_id, amount,
                    method, status, payment_date, confirmed_by_admin_id, notes)
        VALUES (p_membership_id, v_member, v_lib, p_price_adjustment,
                CASE WHEN p_charge_now THEN 'cash' ELSE 'request' END,
                v_pay_status, now(),
                CASE WHEN p_charge_now THEN v_uid ELSE NULL END,
                'Shift change adjustment'
                  || CASE WHEN p_reason IS NOT NULL AND length(trim(p_reason)) > 0
                          THEN ' — ' || p_reason ELSE '' END);
    END IF;

    INSERT INTO public.notifications (user_id, title, body, data)
    VALUES (v_member, 'Shift changed',
            'Your shift has been changed to ' || v_new_shift.name
            || COALESCE('. Seat ' || v_new_label, '. A seat will be assigned shortly')
            || CASE WHEN COALESCE(p_price_adjustment, 0) > 0
                    THEN '. An adjustment of ₹' || p_price_adjustment
                         || CASE WHEN p_charge_now THEN ' was recorded.' ELSE ' is pending.' END
                    WHEN COALESCE(p_price_adjustment, 0) < 0
                    THEN '. A credit of ₹' || abs(p_price_adjustment) || ' was applied.'
                    ELSE '.' END,
            jsonb_build_object('type', 'shift_change', 'route', '/member/home'));

    INSERT INTO public.audit_log (admin_id, library_id, action, details)
    VALUES (v_uid, v_lib, 'membership_shift_transfer',
            jsonb_build_object('category', 'members',
                'title', 'Transferred shift',
                'details', 'to ' || v_new_shift.name
                           || COALESCE(' · seat ' || v_new_label, '')
                           || CASE WHEN COALESCE(p_price_adjustment,0) <> 0
                                   THEN ' · adj ₹' || p_price_adjustment
                                        || CASE WHEN p_charge_now THEN '' ELSE ' (pending)' END
                                   ELSE '' END,
                'performer_name', 'Admin'));

    RETURN jsonb_build_object('membership_id', p_membership_id,
            'new_shift_id', p_new_shift_id, 'new_seat_label', v_new_label,
            'price_adjustment', COALESCE(p_price_adjustment, 0));
END;
$$;
REVOKE ALL ON FUNCTION public.transfer_member_shift(uuid, uuid, uuid, integer, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transfer_member_shift(uuid, uuid, uuid, integer, boolean, text) TO authenticated;

-- ============================================================================
-- VERIFY:
--   SELECT public.transfer_member_shift('<membership>', '<new_shift>', '<seat>', 200, true, 'Upgrade');
--     → old seat freed, new seat claimed, membership on new shift, ₹200 payment.
--   Member: INSERT into shift_change_requests (member_id = auth.uid()) succeeds;
--     reading another member's row is blocked.
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS public.transfer_member_shift(uuid,uuid,uuid,integer,boolean,text);
--   DROP TABLE IF EXISTS public.shift_change_requests;
-- ============================================================================
