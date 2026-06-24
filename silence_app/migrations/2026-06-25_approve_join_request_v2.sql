-- ============================================================================
-- 2026-06-25 — approve_join_request() v2 (joining-process improvements)
-- ============================================================================
--
-- Supersedes the 2-arg approve_join_request (2026-06-24). Adds:
--   • p_discount       — admin can grant a discount AT approval (₹, on the plan
--                        price). Falls back to the request's discount_amount.
--   • p_discount_reason— recorded on the payment + surfaced to the member.
--   • p_start_date     — admin can SET / CORRECT the membership start date
--                        (e.g. an EXISTING offline member's real joining date).
--                        Falls back to join_requests.existing_member_join_date,
--                        then today (IST).  ← fixes "joining date not honored".
--
-- Payment now records original_amount + discount_amount + discount_reason so the
-- member-detail Payments tab can show "₹700 → ₹500 (₹200 off — reason)".
-- Everything still happens in ONE transaction with the atomic seat claim.
--
-- Old 2-arg callers keep working (the 3 new args default to NULL).
-- ============================================================================

DROP FUNCTION IF EXISTS public.approve_join_request(uuid, uuid);

CREATE OR REPLACE FUNCTION public.approve_join_request(
    p_request_id     uuid,
    p_seat_id        uuid,
    p_discount       integer DEFAULT NULL,
    p_discount_reason text   DEFAULT NULL,
    p_start_date     date    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid        uuid := auth.uid();
    v_req        public.join_requests%ROWTYPE;
    v_shift      public.shifts%ROWTYPE;
    v_existing   public.memberships%ROWTYPE;
    v_owner      uuid;
    v_today      date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
    v_months     int;
    v_plan_full  int;     -- plan price before discount
    v_discount   int;
    v_addon_tot  int := 0;
    v_original   int;     -- plan_full + add-ons (pre-discount)
    v_amount     int;     -- charged
    v_seat_label text;
    v_mid        uuid;
    v_start      date;
    v_new_end    date;
    v_renewal    boolean := false;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not signed in' USING errcode = '42501';
    END IF;

    SELECT * INTO v_req FROM public.join_requests WHERE id = p_request_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Request not found' USING errcode = 'P0002';
    END IF;
    IF v_req.status <> 'pending' THEN
        RAISE EXCEPTION 'This request has already been processed' USING errcode = 'P0001';
    END IF;

    SELECT owner_id INTO v_owner FROM public.libraries WHERE id = v_req.library_id;
    IF v_owner IS DISTINCT FROM v_uid THEN
        RAISE EXCEPTION 'Not authorized for this library' USING errcode = '42501';
    END IF;

    SELECT * INTO v_shift FROM public.shifts WHERE id = v_req.shift_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shift not found for this request' USING errcode = 'P0002';
    END IF;

    -- Atomically claim the seat (must belong to the library and be vacant).
    UPDATE public.seats
       SET status = 'occupied', occupied_by_member_id = v_req.member_id, updated_at = now()
     WHERE id = p_seat_id AND library_id = v_req.library_id AND status = 'vacant'
     RETURNING seat_label INTO v_seat_label;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Seat is no longer available — pick another' USING errcode = 'P0001';
    END IF;

    v_months := CASE v_req.plan_type WHEN '6_month' THEN 6 WHEN '3_month' THEN 3 ELSE 1 END;
    v_plan_full := CASE v_req.plan_type
        WHEN '6_month' THEN COALESCE(v_shift.price_6month, v_shift.price_monthly * 6)
        WHEN '3_month' THEN COALESCE(v_shift.price_3month, v_shift.price_monthly * 3)
        WHEN 'trial'   THEN 0
        ELSE v_shift.price_monthly END;
    v_plan_full := COALESCE(v_plan_full, 0);

    -- Discount: admin override → request value → 0; clamp to [0, plan price].
    v_discount := COALESCE(p_discount, v_req.discount_amount, 0);
    IF v_discount < 0 THEN v_discount := 0; END IF;
    IF v_discount > v_plan_full THEN v_discount := v_plan_full; END IF;

    IF v_req.selected_addon_ids IS NOT NULL
       AND array_length(v_req.selected_addon_ids, 1) > 0 THEN
        SELECT COALESCE(sum(price), 0) INTO v_addon_tot
          FROM public.add_ons
         WHERE id = ANY (v_req.selected_addon_ids) AND library_id = v_req.library_id;
    END IF;

    v_original := v_plan_full + v_addon_tot;
    v_amount   := (v_plan_full - v_discount) + v_addon_tot;

    -- Existing live/expired membership at this library → renewal; else new.
    SELECT * INTO v_existing FROM public.memberships
     WHERE member_id = v_req.member_id AND library_id = v_req.library_id
       AND status IN ('active', 'trial', 'expired')
     ORDER BY created_at DESC LIMIT 1;

    IF FOUND THEN
        v_renewal := true;
        -- Renewal base: explicit override → later of (current end, today).
        v_start := COALESCE(p_start_date, GREATEST(COALESCE(v_existing.end_date, v_today), v_today));
        v_new_end := (v_start + (v_months || ' months')::interval)::date;
        UPDATE public.memberships
           SET start_date = LEAST(start_date, v_start),
               end_date = v_new_end, status = 'active', plan_type = v_req.plan_type,
               seat_id = p_seat_id, shift_id = v_req.shift_id
         WHERE id = v_existing.id;
        v_mid := v_existing.id;
    ELSE
        -- New: admin start date → member's chosen offline join date → today.
        v_start := COALESCE(p_start_date, v_req.existing_member_join_date, v_today);
        v_new_end := (v_start + (v_months || ' months')::interval)::date;
        INSERT INTO public.memberships (member_id, library_id, shift_id, seat_id,
                    plan_type, start_date, end_date, status)
        VALUES (v_req.member_id, v_req.library_id, v_req.shift_id, p_seat_id,
                v_req.plan_type, v_start, v_new_end, 'active')
        RETURNING id INTO v_mid;
    END IF;

    INSERT INTO public.payments (membership_id, member_id, library_id, amount,
                original_amount, discount_amount, discount_reason, method,
                status, payment_date, confirmed_by_admin_id, proof_url, upi_sender_name)
    VALUES (v_mid, v_req.member_id, v_req.library_id, v_amount,
            v_original, v_discount, p_discount_reason,
            COALESCE(v_req.payment_method, 'cash'), 'confirmed', now(), v_uid,
            v_req.payment_proof_url, v_req.upi_sender_name);

    IF v_req.selected_addon_ids IS NOT NULL
       AND array_length(v_req.selected_addon_ids, 1) > 0 THEN
        INSERT INTO public.member_add_ons (membership_id, add_on_id, deposit_paid)
        SELECT v_mid, a.id, COALESCE(a.refundable_deposit, 0)
          FROM public.add_ons a
         WHERE a.id = ANY (v_req.selected_addon_ids) AND a.library_id = v_req.library_id;
    END IF;

    UPDATE public.join_requests SET status = 'approved' WHERE id = p_request_id;

    INSERT INTO public.notifications (user_id, title, body, data)
    VALUES (v_req.member_id,
            CASE WHEN v_renewal THEN 'Membership renewed' ELSE 'Welcome aboard!' END,
            (CASE WHEN v_renewal THEN 'Your renewal is confirmed. ' ELSE 'Your membership is approved. ' END)
            || 'Seat ' || v_seat_label || ' is assigned. Plan starts ' || v_start
            || '. Payment of ₹' || v_amount || ' recorded.'
            || CASE WHEN v_discount > 0
                    THEN ' A discount of ₹' || v_discount
                         || COALESCE(' (' || p_discount_reason || ')', '') || ' was applied.'
                    ELSE '' END,
            jsonb_build_object('type', 'join_approved', 'route', '/member/home'));

    INSERT INTO public.audit_log (admin_id, library_id, action, details)
    VALUES (v_uid, v_req.library_id,
            CASE WHEN v_renewal THEN 'membership_renew' ELSE 'membership_approve' END,
            jsonb_build_object('category', 'members',
                'title', CASE WHEN v_renewal THEN 'Renewed membership' ELSE 'Approved join request' END,
                'details', 'seat ' || v_seat_label || ' · ₹' || v_amount
                           || CASE WHEN v_discount > 0 THEN ' (₹' || v_discount || ' off)' ELSE '' END
                           || ' · plan ' || v_req.plan_type || ' · from ' || v_start,
                'performer_name', 'Admin'));

    RETURN jsonb_build_object('membership_id', v_mid, 'end_date', v_new_end,
            'start_date', v_start, 'seat_label', v_seat_label, 'amount', v_amount,
            'discount', v_discount, 'is_renewal', v_renewal);
END;
$$;
REVOKE ALL ON FUNCTION public.approve_join_request(uuid, uuid, integer, text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_join_request(uuid, uuid, integer, text, date) TO authenticated;

-- ============================================================================
-- VERIFY:
--   SELECT public.approve_join_request('<req>', '<seat>');                  -- defaults
--   SELECT public.approve_join_request('<req>', '<seat>', 200, 'Loyalty', '2026-06-01');
--     → start_date honored, discount applied, payment shows original/discount.
-- ROLLBACK: DROP FUNCTION IF EXISTS public.approve_join_request(uuid,uuid,integer,text,date);
--   then re-create the 2-arg version from 2026-06-24_approve_join_request_rpc.sql.
-- ============================================================================
