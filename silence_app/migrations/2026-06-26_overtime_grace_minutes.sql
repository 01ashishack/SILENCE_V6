-- 2026-06-26 — Configurable overtime auto-checkout grace window.
-- Adds libraries.auto_checkout_grace_minutes (default 30) so each admin can set
-- how many minutes after a shift ends a member is auto-checked-out, and
-- re-creates process_shift_overtime() to honour it (was hardcoded 30).
-- Idempotent + additive. Apply in the Supabase SQL editor.

ALTER TABLE public.libraries
    ADD COLUMN IF NOT EXISTS auto_checkout_grace_minutes INTEGER NOT NULL DEFAULT 30;

-- Keep the value sane (5 min – 6 h).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'libraries_grace_minutes_bound'
    ) THEN
        ALTER TABLE public.libraries
            ADD CONSTRAINT libraries_grace_minutes_bound
            CHECK (auto_checkout_grace_minutes BETWEEN 5 AND 360) NOT VALID;
    END IF;
END$$;

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
    v_grace        INTEGER;
BEGIN
    FOR r IN
        SELECT a.id, a.member_id, a.check_in_time, a.overtime_warned,
               s.end_time, s.name AS shift_name,
               COALESCE(l.auto_checkout_overtime, true) AS auto_checkout,
               COALESCE(l.auto_checkout_grace_minutes, 30) AS grace_minutes
          FROM public.attendance a
          JOIN public.shifts s    ON s.id = a.shift_id
          JOIN public.libraries l ON l.id = a.library_id
         WHERE a.check_out_time IS NULL
    LOOP
        v_grace := GREATEST(1, COALESCE(r.grace_minutes, 30));
        v_shift_end := (((r.check_in_time AT TIME ZONE 'Asia/Kolkata')::date
                          + r.end_time) AT TIME ZONE 'Asia/Kolkata');
        v_cap_checkout := GREATEST(v_shift_end, r.check_in_time) + make_interval(mins => v_grace);

        IF r.auto_checkout AND now() >= v_cap_checkout THEN
            v_dur := GREATEST(0, CEIL(EXTRACT(EPOCH FROM (v_cap_checkout - r.check_in_time)) / 60.0))::int;
            UPDATE public.attendance
               SET check_out_time   = v_cap_checkout,
                   duration_minutes = v_dur,
                   session_type     = 'auto_checkout',
                   is_overtime      = true,
                   overtime_minutes = v_grace
             WHERE id = r.id;
            INSERT INTO public.notifications (user_id, title, body, data)
            VALUES (r.member_id, 'Auto checked out',
                    'You did not check out, so we automatically checked you out '
                    || v_grace || ' minutes after your '
                    || r.shift_name || ' shift ended. This session is tagged as overtime.',
                    jsonb_build_object('type', 'auto_checkout', 'route', '/member/home'));
            v_closed := v_closed + 1;
        ELSIF now() >= v_shift_end AND NOT r.overtime_warned
              AND r.check_in_time < v_shift_end THEN
            UPDATE public.attendance SET overtime_warned = true WHERE id = r.id;
            INSERT INTO public.notifications (user_id, title, body, data)
            VALUES (r.member_id, 'Your shift has ended',
                    'Your ' || r.shift_name || ' shift is over. Please scan to check out.'
                    || CASE WHEN r.auto_checkout
                            THEN ' If you stay, the extra time counts as overtime and you will be '
                                 || 'auto-checked-out after ' || v_grace || ' minutes.'
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
