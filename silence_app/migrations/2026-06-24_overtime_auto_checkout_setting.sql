-- ============================================================================
-- 2026-06-24 — Per-library "auto check-out on overtime" setting
-- ============================================================================
--
-- Adds libraries.auto_checkout_overtime (default TRUE) so an admin can decide
-- whether sessions are force-closed 30 min after the shift ends.
--
--   • TRUE  (default): process_shift_overtime() warns at shift end AND
--     auto-checks-out 30 min later (capped overtime) — current behaviour.
--   • FALSE: it still WARNS at shift end, but never force-closes; the member
--     (or the admin) checks out manually. Overtime is still recorded.
--
-- Re-creates process_shift_overtime() to read the flag per session. The 30-min
-- warning is unchanged; only the auto-checkout branch is gated.
--
-- Idempotent: safe to re-run.
-- PRECONDITION: ship the app build that reads `auto_checkout_overtime`.
-- ============================================================================

ALTER TABLE public.libraries
    ADD COLUMN IF NOT EXISTS auto_checkout_overtime BOOLEAN NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.process_shift_overtime()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    r              RECORD;
    v_shift_end    TIMESTAMPTZ;
    v_cap_checkout TIMESTAMPTZ;
    v_warned       INTEGER := 0;
    v_closed       INTEGER := 0;
    v_dur          INTEGER;
    v_ot           INTEGER;
BEGIN
    FOR r IN
        SELECT a.id, a.member_id, a.check_in_time, a.overtime_warned,
               s.end_time, s.name AS shift_name,
               COALESCE(l.auto_checkout_overtime, true) AS auto_checkout
          FROM public.attendance a
          JOIN public.shifts s    ON s.id = a.shift_id
          JOIN public.libraries l ON l.id = a.library_id
         WHERE a.check_out_time IS NULL
    LOOP
        v_shift_end := (((r.check_in_time AT TIME ZONE 'Asia/Kolkata')::date
                          + r.end_time) AT TIME ZONE 'Asia/Kolkata');
        v_cap_checkout := GREATEST(v_shift_end, r.check_in_time) + interval '30 minutes';

        IF r.auto_checkout AND now() >= v_cap_checkout THEN
            -- AUTO-CHECKOUT (capped) — only when the library allows it.
            v_dur := GREATEST(0, CEIL(EXTRACT(EPOCH FROM (v_cap_checkout - r.check_in_time)) / 60.0))::int;
            v_ot  := 30;
            UPDATE public.attendance
               SET check_out_time   = v_cap_checkout,
                   duration_minutes = v_dur,
                   session_type     = 'auto_checkout',
                   is_overtime      = true,
                   overtime_minutes = v_ot
             WHERE id = r.id;

            INSERT INTO public.notifications (user_id, title, body, data)
            VALUES (r.member_id,
                    'Auto checked out',
                    'You did not check out, so we automatically checked you out 30 minutes after your '
                    || r.shift_name || ' shift ended. This session is tagged as overtime.',
                    jsonb_build_object('type', 'auto_checkout', 'route', '/member/home'));
            v_closed := v_closed + 1;

        ELSIF now() >= v_shift_end AND NOT r.overtime_warned
              AND r.check_in_time < v_shift_end THEN
            -- WARN once: shift ended, still checked in. (Runs regardless of the
            -- auto-checkout setting.)
            UPDATE public.attendance SET overtime_warned = true WHERE id = r.id;
            INSERT INTO public.notifications (user_id, title, body, data)
            VALUES (r.member_id,
                    'Your shift has ended',
                    'Your ' || r.shift_name || ' shift is over. Please scan to check out.'
                    || CASE WHEN r.auto_checkout
                            THEN ' If you stay, the extra time counts as overtime and you will be '
                                 || 'auto-checked-out after 30 minutes.'
                            ELSE ' Any extra time will be recorded as overtime.' END,
                    jsonb_build_object('type', 'shift_end', 'route', '/member/home'));
            v_warned := v_warned + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object('warned', v_warned, 'auto_closed', v_closed, 'ran_at', now());
END;
$$;
REVOKE ALL ON FUNCTION public.process_shift_overtime() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_shift_overtime() TO service_role;

-- ============================================================================
-- VERIFY:
--   SELECT auto_checkout_overtime FROM libraries LIMIT 5;   -- default true
--   UPDATE libraries SET auto_checkout_overtime = false WHERE id = '<lib>';
--   SELECT public.process_shift_overtime();  -- {warned, auto_closed, ran_at}
--   -- with the flag false, an over-cap open session is WARNED but NOT closed.
-- ROLLBACK:
--   ALTER TABLE public.libraries DROP COLUMN IF EXISTS auto_checkout_overtime;
--   -- (then re-apply 2026-06-22_overtime_and_checkin_approvals.sql's function)
-- ============================================================================
