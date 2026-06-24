-- ============================================================================
-- 2026-06-24 — approve_join_request() atomic RPC (audit C3 + C5/M7 on the
--              join-approval path)
-- ============================================================================
--
-- The admin "approve join request + assign seat" flow did ~7 separate client
-- writes (seat occupy → request status → membership upsert → payment → add-ons
-- → notify → audit). Problems:
--   • C3: the seat occupy was a blind UPDATE with only a client-side vacancy
--     re-check → two admins approving in the same second could double-book.
--   • C5/M7: amount was client-computed and the writes were non-atomic → a
--     mid-sequence failure left the member approved with no payment / no add-ons.
--
-- This RPC does it all in ONE transaction, server-side:
--   • owner-checks the library, requires the request to still be 'pending',
--   • ATOMICALLY occupies the seat (UPDATE ... WHERE status='vacant' RETURNING;
--     0 rows → raises, whole txn rolls back → no double-booking),
--   • DERIVES the amount from shifts.price_* (− discount) + add-on prices,
--   • renews or creates the membership (IST dates), records a CONFIRMED payment,
--     inserts member_add_ons, approves the request, notifies + audits.
--
-- Idempotent: CREATE OR REPLACE. The 'pending' guard makes a double-call a no-op
-- (2nd call raises 'already processed').
-- ============================================================================

CREATE OR REPLACE FUNCTION public.approve_join_request(
    p_request_id uuid,
    p_seat_id    uuid
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
    v_plan_amt   int;
    v_addon_tot  int := 0;
    v_amount     int;
    v_seat_label text;
    v_mid        uuid;
    v_base       date;
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

    -- Atomically claim the seat: must belong to the library and be vacant.
    UPDATE public.seats
       SET status = 'occupied', occupied_by_member_id = v_req.member_id, updated_at = now()
     WHERE id = p_seat_id AND library_id = v_req.library_id AND status = 'vacant'
     RETURNING seat_label INTO v_seat_label;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Seat is no longer available — pick another' USING errcode = 'P0001';
    END IF;

    v_months := CASE v_req.plan_type WHEN '6_month' THEN 6 WHEN '3_month' THEN 3 ELSE 1 END;
    v_plan_amt := CASE v_req.plan_type
        WHEN '6_month' THEN COALESCE(v_shift.price_6month, v_shift.price_monthly * 6)
        WHEN '3_month' THEN COALESCE(v_shift.price_3month, v_shift.price_monthly * 3)
        WHEN 'trial'   THEN 0
        ELSE v_shift.price_monthly END;
    v_plan_amt := GREATEST(0, COALESCE(v_plan_amt, 0) - COALESCE(v_req.discount_amount, 0));

    IF v_req.selected_addon_ids IS NOT NULL
       AND array_length(v_req.selected_addon_ids, 1) > 0 THEN
        SELECT COALESCE(sum(price), 0) INTO v_addon_tot
          FROM public.add_ons
         WHERE id = ANY (v_req.selected_addon_ids) AND library_id = v_req.library_id;
    END IF;
    v_amount := v_plan_amt + v_addon_tot;

    -- Renewal (an existing live/expired membership) vs a brand-new one.
    SELECT * INTO v_existing FROM public.memberships
     WHERE member_id = v_req.member_id AND library_id = v_req.library_id
       AND status IN ('active', 'trial', 'expired')
     ORDER BY created_at DESC LIMIT 1;

    IF FOUND THEN
        v_renewal := true;
        v_base := GREATEST(COALESCE(v_existing.end_date, v_today), v_today);
        v_new_end := (v_base + (v_months || ' months')::interval)::date;
        UPDATE public.memberships
           SET end_date = v_new_end, status = 'active', plan_type = v_req.plan_type,
               seat_id = p_seat_id, shift_id = v_req.shift_id
         WHERE id = v_existing.id;
        v_mid := v_existing.id;
    ELSE
        v_new_end := (v_today + (v_months || ' months')::interval)::date;
        INSERT INTO public.memberships (member_id, library_id, shift_id, seat_id,
                    plan_type, start_date, end_date, status)
        VALUES (v_req.member_id, v_req.library_id, v_req.shift_id, p_seat_id,
                v_req.plan_type, v_today, v_new_end, 'active')
        RETURNING id INTO v_mid;
    END IF;

    INSERT INTO public.payments (membership_id, member_id, library_id, amount, method,
                status, payment_date, confirmed_by_admin_id, proof_url, upi_sender_name)
    VALUES (v_mid, v_req.member_id, v_req.library_id, v_amount,
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
            CASE WHEN v_renewal
                THEN 'Your renewal is confirmed. Seat ' || v_seat_label
                     || ' is assigned. Payment of ₹' || v_amount || ' recorded.'
                ELSE 'Your membership is approved. Seat ' || v_seat_label
                     || ' is assigned. Payment of ₹' || v_amount
                     || ' recorded. You can check in now.' END,
            jsonb_build_object('type', 'join_approved', 'route', '/member/home'));

    INSERT INTO public.audit_log (admin_id, library_id, action, details)
    VALUES (v_uid, v_req.library_id,
            CASE WHEN v_renewal THEN 'membership_renew' ELSE 'membership_approve' END,
            jsonb_build_object('category', 'members',
                'title', CASE WHEN v_renewal THEN 'Renewed membership' ELSE 'Approved join request' END,
                'details', 'seat ' || v_seat_label || ' · ₹' || v_amount
                           || ' · plan ' || v_req.plan_type,
                'performer_name', 'Admin'));

    RETURN jsonb_build_object('membership_id', v_mid, 'end_date', v_new_end,
            'seat_label', v_seat_label, 'amount', v_amount, 'is_renewal', v_renewal);
END;
$$;
REVOKE ALL ON FUNCTION public.approve_join_request(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_join_request(uuid, uuid) TO authenticated;

-- ============================================================================
-- VERIFY:
--   SELECT public.approve_join_request('<request_id>', '<vacant_seat_id>');
--     → {membership_id, end_date, seat_label, amount, is_renewal}; seat occupied;
--       payment confirmed with SERVER amount; request 'approved'; add-ons + audit
--       + notification created — or nothing at all if any step fails.
--   • Re-call same request → 'already been processed'.
--   • Concurrent call on the same seat → one wins, other gets 'Seat is no longer
--     available' and rolls back fully (no half-approval).
--   • As a non-owner → 'Not authorized'.
-- ROLLBACK: DROP FUNCTION IF EXISTS public.approve_join_request(uuid, uuid);
-- ============================================================================
