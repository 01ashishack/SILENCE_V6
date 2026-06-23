-- ============================================================================
-- 2026-06-22 — Shift overtime (30-min cap + auto-checkout) & out-of-shift
--              check-in approvals
-- ============================================================================
--
-- Three things, all server-authoritative so they work even when the member's
-- app is closed:
--
--   1. attendance gains overtime bookkeeping columns:
--        is_overtime       — session ran past shift end (or was an approved
--                            out-of-shift check-in)
--        overtime_minutes  — minutes counted as overtime, HARD-capped at 30
--        overtime_warned   — dedupe flag for the "shift ended, please check out"
--                            warning notification
--
--   2. process_shift_overtime()  (SECURITY DEFINER, run by pg_cron every ~5 min):
--        • WARN: open session whose shift has ended (now ≥ shift end, IST) and
--          not yet warned → insert a "shift ended, please check out" notification
--          + set overtime_warned.
--        • AUTO-CHECKOUT: open session still open 30 min past shift end →
--          force check-out, stamped at  greatest(shift_end, check_in) + 30min
--          (so recorded overtime never exceeds 30 min), session_type =
--          'auto_checkout', is_overtime = true, + notify the member.
--      The shift end is computed from the IST CALENDAR DATE of check_in, so a
--      session left open across days (the classic "forgot to check out" 45h
--      ghost session) is closed against its OWN day's shift end, not today's.
--
--   3. checkin_approvals: when a member scans OUTSIDE their shift window
--      (earlier than 15 min before start, or after end) the app files a PENDING
--      approval + notifies the owner. The owner approves/rejects in the Requests
--      tab; on approval the member re-scans and the (overtime-tagged) check-in
--      proceeds. Members can only file PENDING rows and read their own — they
--      can NOT self-approve (no member UPDATE; the 'used' flip goes through the
--      SECURITY DEFINER consume_checkin_approval() RPC).
--
-- PRECONDITION: ship the app build that reads/writes these columns + table and
--   calls consume_checkin_approval() together with applying this.
--
-- Idempotent: safe to re-run.
-- ============================================================================

-- 1. ── attendance overtime columns ─────────────────────────────────────────
ALTER TABLE public.attendance
    ADD COLUMN IF NOT EXISTS is_overtime      BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS overtime_minutes INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS overtime_warned  BOOLEAN NOT NULL DEFAULT false;

-- Cheap scan target for the cron: only the currently-open sessions.
CREATE INDEX IF NOT EXISTS idx_attendance_open
    ON public.attendance (check_in_time)
    WHERE check_out_time IS NULL;

-- 2. ── checkin_approvals table ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.checkin_approvals (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id       UUID NOT NULL REFERENCES public.memberships(id) ON DELETE CASCADE,
    member_id           UUID NOT NULL REFERENCES public.users(id)       ON DELETE CASCADE,
    library_id          UUID NOT NULL REFERENCES public.libraries(id)   ON DELETE CASCADE,
    shift_id            UUID REFERENCES public.shifts(id)               ON DELETE SET NULL,
    attempted_at        TIMESTAMPTZ NOT NULL DEFAULT now(),  -- when they tried to scan
    status              TEXT NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending','approved','rejected','expired','used')),
    decided_by          UUID REFERENCES public.users(id) ON DELETE SET NULL,
    decided_at          TIMESTAMPTZ,
    approval_expires_at TIMESTAMPTZ,  -- an approved row is only usable until this
    note                TEXT,
    created_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_checkin_approvals_library_status
    ON public.checkin_approvals (library_id, status, created_at);
CREATE INDEX IF NOT EXISTS idx_checkin_approvals_member_status
    ON public.checkin_approvals (member_id, status);

ALTER TABLE public.checkin_approvals ENABLE ROW LEVEL SECURITY;

-- Member: read own + file own PENDING requests (cannot self-approve).
DROP POLICY IF EXISTS "Member view own checkin approvals" ON public.checkin_approvals;
CREATE POLICY "Member view own checkin approvals" ON public.checkin_approvals
    FOR SELECT USING (member_id = auth.uid());

DROP POLICY IF EXISTS "Member file checkin approval" ON public.checkin_approvals;
CREATE POLICY "Member file checkin approval" ON public.checkin_approvals
    FOR INSERT WITH CHECK (member_id = auth.uid() AND status = 'pending');

-- Admin (library owner): read + decide (approve/reject) for their library.
DROP POLICY IF EXISTS "Admin view checkin approvals" ON public.checkin_approvals;
CREATE POLICY "Admin view checkin approvals" ON public.checkin_approvals
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.libraries WHERE id = library_id AND owner_id = auth.uid())
    );

DROP POLICY IF EXISTS "Admin decide checkin approval" ON public.checkin_approvals;
CREATE POLICY "Admin decide checkin approval" ON public.checkin_approvals
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM public.libraries WHERE id = library_id AND owner_id = auth.uid())
    ) WITH CHECK (
        EXISTS (SELECT 1 FROM public.libraries WHERE id = library_id AND owner_id = auth.uid())
    );

-- Member marks an APPROVED row 'used' after a successful re-scan check-in.
-- SECURITY DEFINER so the member never gets a raw UPDATE grant (which would let
-- them set status='approved' themselves — RLS WITH CHECK can't see the prior
-- value to forbid that transition).
CREATE OR REPLACE FUNCTION public.consume_checkin_approval(p_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_row public.checkin_approvals%ROWTYPE;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not signed in' USING errcode = '42501';
    END IF;
    SELECT * INTO v_row FROM public.checkin_approvals WHERE id = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Approval not found' USING errcode = 'P0002';
    END IF;
    IF v_row.member_id <> v_uid THEN
        RAISE EXCEPTION 'Not your approval' USING errcode = '42501';
    END IF;
    IF v_row.status <> 'approved' THEN
        RAISE EXCEPTION 'Approval is not in an approved state' USING errcode = 'P0001';
    END IF;
    UPDATE public.checkin_approvals
       SET status = 'used', decided_at = COALESCE(decided_at, now())
     WHERE id = p_id;
END;
$$;
REVOKE ALL ON FUNCTION public.consume_checkin_approval(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consume_checkin_approval(uuid) TO authenticated;

-- 3. ── process_shift_overtime(): warnings + auto-checkout (cron) ────────────
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
               s.end_time, s.name AS shift_name
          FROM public.attendance a
          JOIN public.shifts s ON s.id = a.shift_id
         WHERE a.check_out_time IS NULL
    LOOP
        -- Shift end on the check-in's OWN IST calendar date, back to UTC.
        v_shift_end := (((r.check_in_time AT TIME ZONE 'Asia/Kolkata')::date
                          + r.end_time) AT TIME ZONE 'Asia/Kolkata');
        -- Overtime window closes 30 min after shift end, but never before the
        -- member actually checked in (covers approved after-shift check-ins).
        v_cap_checkout := GREATEST(v_shift_end, r.check_in_time) + interval '30 minutes';

        IF now() >= v_cap_checkout THEN
            -- AUTO-CHECKOUT (capped). The cap is exactly 30 min past the shift
            -- end (or past check-in for an approved after-shift session), so the
            -- recorded overtime is always the full 30-min grace.
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
                    jsonb_build_object('type', 'auto_checkout'));
            v_closed := v_closed + 1;

        ELSIF now() >= v_shift_end AND NOT r.overtime_warned
              AND r.check_in_time < v_shift_end THEN
            -- WARN once: shift ended, still checked in (inside the 30-min grace).
            UPDATE public.attendance SET overtime_warned = true WHERE id = r.id;
            INSERT INTO public.notifications (user_id, title, body, data)
            VALUES (r.member_id,
                    'Your shift has ended',
                    'Your ' || r.shift_name || ' shift is over. Please scan to check out. '
                    || 'If you stay, the extra time counts as overtime and you will be auto-checked-out '
                    || 'after 30 minutes.',
                    jsonb_build_object('type', 'shift_end'));
            v_warned := v_warned + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object('warned', v_warned, 'auto_closed', v_closed, 'ran_at', now());
END;
$$;
REVOKE ALL ON FUNCTION public.process_shift_overtime() FROM PUBLIC;
-- Only the cron/service role should run it; expose to service_role explicitly.
GRANT EXECUTE ON FUNCTION public.process_shift_overtime() TO service_role;

-- 4. ── schedule the cron (best-effort; skipped if pg_cron isn't installed) ──
DO $cronwrap$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- Every 5 minutes. Re-scheduling with the same name replaces the job.
        PERFORM cron.schedule('silence-shift-overtime', '*/5 * * * *',
                              'SELECT public.process_shift_overtime();');
    ELSE
        RAISE NOTICE 'pg_cron not installed — schedule process_shift_overtime() manually (Dashboard → Database → Cron, every 5 min).';
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron scheduling skipped: %', SQLERRM;
END
$cronwrap$;

-- ============================================================================
-- VERIFY:
--   • SELECT public.process_shift_overtime();  → returns {warned, auto_closed,…}.
--   • Open a session, set its shift end in the past (or wait): after the cron
--     runs you get a "Your shift has ended" notification; 30 min later it
--     auto-checks-out with session_type='auto_checkout', is_overtime=true,
--     overtime_minutes ≤ 30, duration_minutes ≥ 0.
--   • As a member: INSERT a checkin_approvals row with status='pending' → OK;
--     INSERT with status='approved' → REJECTED; UPDATE any row → REJECTED.
--   • As the library owner: UPDATE the row to status='approved' → OK.
--   • As the member: SELECT public.consume_checkin_approval('<id>') flips an
--     approved row to 'used'; calling it on a non-approved row raises.
-- ROLLBACK:
--   DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron')
--     THEN PERFORM cron.unschedule('silence-shift-overtime'); END IF; END $$;
--   DROP FUNCTION IF EXISTS public.process_shift_overtime();
--   DROP FUNCTION IF EXISTS public.consume_checkin_approval(uuid);
--   DROP TABLE IF EXISTS public.checkin_approvals;
--   ALTER TABLE public.attendance
--     DROP COLUMN IF EXISTS is_overtime,
--     DROP COLUMN IF EXISTS overtime_minutes,
--     DROP COLUMN IF EXISTS overtime_warned;
-- ============================================================================
