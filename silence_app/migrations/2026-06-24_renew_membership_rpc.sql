-- ============================================================================
-- 2026-06-24 — renew_membership() atomic RPC (audit M7 + C5)
-- ============================================================================
--
-- The admin "direct renew" previously did 4 separate client writes (membership
-- update → payment insert → notification → audit) with a CLIENT-SUPPLIED amount
-- on a 'confirmed' payment. Two problems:
--   • M7 (atomicity): a failure between the membership extend and the payment
--     insert left the member renewed with NO payment recorded (free renewal).
--   • C5 (trust): the amount was a client integer — a tampered client could
--     record any value on a confirmed payment.
--
-- This RPC does everything in ONE transaction, server-side:
--   • verifies the caller OWNS the membership's library,
--   • DERIVES the amount from shifts.price_* for the chosen plan (never trusts
--     a client amount),
--   • extends end_date from GREATEST(current end, today) in IST,
--   • records a CONFIRMED payment, writes the audit row, notifies the member.
--
-- Idempotent: CREATE OR REPLACE. Safe to re-run.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.renew_membership(
    p_membership_id uuid,
    p_plan_type     text,
    p_method        text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid     uuid := auth.uid();
    v_m       public.memberships%ROWTYPE;
    v_shift   public.shifts%ROWTYPE;
    v_owner   uuid;
    v_months  int;
    v_amount  int;
    v_base    date;
    v_new_end date;
    v_today   date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not signed in' USING errcode = '42501';
    END IF;
    IF p_plan_type NOT IN ('monthly', '3_month', '6_month') THEN
        RAISE EXCEPTION 'Invalid plan type' USING errcode = '22023';
    END IF;
    IF p_method NOT IN ('cash', 'upi') THEN
        RAISE EXCEPTION 'Invalid payment method' USING errcode = '22023';
    END IF;

    SELECT * INTO v_m FROM public.memberships WHERE id = p_membership_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Membership not found' USING errcode = 'P0002';
    END IF;

    -- Caller must own the library this membership belongs to.
    SELECT owner_id INTO v_owner FROM public.libraries WHERE id = v_m.library_id;
    IF v_owner IS DISTINCT FROM v_uid THEN
        RAISE EXCEPTION 'Not authorized for this library' USING errcode = '42501';
    END IF;

    SELECT * INTO v_shift FROM public.shifts WHERE id = v_m.shift_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shift not found for this membership' USING errcode = 'P0002';
    END IF;

    v_months := CASE p_plan_type WHEN '6_month' THEN 6 WHEN '3_month' THEN 3 ELSE 1 END;
    v_amount := CASE p_plan_type
                  WHEN '6_month' THEN COALESCE(v_shift.price_6month, v_shift.price_monthly * 6)
                  WHEN '3_month' THEN COALESCE(v_shift.price_3month, v_shift.price_monthly * 3)
                  ELSE v_shift.price_monthly END;
    IF v_amount IS NULL OR v_amount < 0 THEN
        RAISE EXCEPTION 'Shift has no price for this plan' USING errcode = '22023';
    END IF;

    -- Extend from the later of (current end, today). Postgres clamps month-ends.
    v_base := GREATEST(COALESCE(v_m.end_date, v_today), v_today);
    v_new_end := (v_base + (v_months || ' months')::interval)::date;

    UPDATE public.memberships
       SET end_date = v_new_end, status = 'active', plan_type = p_plan_type
     WHERE id = p_membership_id;

    INSERT INTO public.payments (membership_id, member_id, library_id, amount,
                                 method, status, payment_date, confirmed_by_admin_id)
    VALUES (p_membership_id, v_m.member_id, v_m.library_id, v_amount,
            p_method, 'confirmed', now(), v_uid);

    INSERT INTO public.audit_log (admin_id, library_id, action, details, new_value)
    VALUES (v_uid, v_m.library_id, 'membership_renewed',
            jsonb_build_object(
                'category', 'payments',
                'title', 'Renewed membership',
                'details', 'Plan ' || p_plan_type || ' · ₹' || v_amount
                           || ' · new expiry ' || v_new_end,
                'performer_name', 'Admin'),
            v_new_end::text);

    INSERT INTO public.notifications (user_id, title, body, data)
    VALUES (v_m.member_id, 'Membership renewed',
            'Your membership was renewed (' || p_plan_type || '). New expiry: '
            || v_new_end || '. Payment of ₹' || v_amount || ' recorded.',
            jsonb_build_object('type', 'membership_renewed', 'route', '/member/home'));

    RETURN jsonb_build_object('end_date', v_new_end, 'amount', v_amount, 'months', v_months);
END;
$$;
REVOKE ALL ON FUNCTION public.renew_membership(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.renew_membership(uuid, text, text) TO authenticated;

-- ============================================================================
-- VERIFY:
--   SELECT public.renew_membership('<membership_id>', 'monthly', 'cash');
--     → {"end_date":"...","amount":N,"months":1}; payment row is 'confirmed'
--       with the SERVER-derived amount; audit + notification rows created.
--   As a NON-owner: same call → 'Not authorized for this library' (42501).
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS public.renew_membership(uuid, text, text);
-- ============================================================================
