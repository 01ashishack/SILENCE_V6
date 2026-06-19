-- ============================================================================
-- 2026-06-18 — Precompute member_daily_stats (audit P11-01)
-- ============================================================================
--
-- member_analytics_service._calculateStatsForRange already queries
-- member_daily_stats FIRST (fast path) and only falls back to scanning the
-- whole attendance table if that table is empty. It was never populated, so
-- every analytics load did a full attendance scan.
--
-- This adds a trigger that keeps member_daily_stats fresh on every attendance
-- INSERT/UPDATE/DELETE (one indexed upsert per affected member+library+IST-day)
-- plus a one-time backfill of existing rows. Day bucketing uses IST
-- (Asia/Kolkata) to match the app's single-clock model (P8-01).
--
-- Idempotent. Additive: if the trigger ever errors, the service's attendance
-- fallback still returns correct numbers.
-- ============================================================================

-- Recompute the rollup for one (member, library, IST-date) from attendance.
CREATE OR REPLACE FUNCTION public.recompute_member_daily_stat(
    p_member uuid, p_library uuid, p_date date)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_count   integer;
    v_present boolean;
    v_minutes integer;
BEGIN
    SELECT count(*)::int,
           bool_or(a.check_out_time IS NOT NULL OR a.session_type IS DISTINCT FROM 'incomplete'),
           COALESCE(sum(CASE WHEN a.session_type IS DISTINCT FROM 'incomplete'
                             THEN a.duration_minutes ELSE 0 END), 0)::int
      INTO v_count, v_present, v_minutes
    FROM public.attendance a
    WHERE a.member_id = p_member
      AND a.library_id = p_library
      AND (a.check_in_time AT TIME ZONE 'Asia/Kolkata')::date = p_date;

    IF v_count = 0 THEN
        DELETE FROM public.member_daily_stats
         WHERE member_id = p_member AND library_id = p_library AND date = p_date;
        RETURN;
    END IF;

    INSERT INTO public.member_daily_stats (member_id, library_id, date, present_flag, total_minutes)
    VALUES (p_member, p_library, p_date, COALESCE(v_present, false), COALESCE(v_minutes, 0))
    ON CONFLICT (member_id, library_id, date)
    DO UPDATE SET present_flag = EXCLUDED.present_flag,
                  total_minutes = EXCLUDED.total_minutes;
END;
$$;

-- Trigger: keep the rollup current on any attendance change.
CREATE OR REPLACE FUNCTION public.trg_attendance_daily_stats()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        PERFORM public.recompute_member_daily_stat(
            OLD.member_id, OLD.library_id,
            (OLD.check_in_time AT TIME ZONE 'Asia/Kolkata')::date);
        RETURN OLD;
    END IF;

    PERFORM public.recompute_member_daily_stat(
        NEW.member_id, NEW.library_id,
        (NEW.check_in_time AT TIME ZONE 'Asia/Kolkata')::date);

    IF (TG_OP = 'UPDATE') THEN
        -- If the day/member/library moved, refresh the old bucket too.
        IF (OLD.member_id, OLD.library_id, (OLD.check_in_time AT TIME ZONE 'Asia/Kolkata')::date)
           IS DISTINCT FROM
           (NEW.member_id, NEW.library_id, (NEW.check_in_time AT TIME ZONE 'Asia/Kolkata')::date) THEN
            PERFORM public.recompute_member_daily_stat(
                OLD.member_id, OLD.library_id,
                (OLD.check_in_time AT TIME ZONE 'Asia/Kolkata')::date);
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_attendance_daily_stats ON public.attendance;
CREATE TRIGGER trg_attendance_daily_stats
    AFTER INSERT OR UPDATE OR DELETE ON public.attendance
    FOR EACH ROW EXECUTE FUNCTION public.trg_attendance_daily_stats();

-- One-time backfill from existing attendance (safe to re-run).
INSERT INTO public.member_daily_stats (member_id, library_id, date, present_flag, total_minutes)
SELECT a.member_id,
       a.library_id,
       (a.check_in_time AT TIME ZONE 'Asia/Kolkata')::date AS d,
       bool_or(a.check_out_time IS NOT NULL OR a.session_type IS DISTINCT FROM 'incomplete'),
       COALESCE(sum(CASE WHEN a.session_type IS DISTINCT FROM 'incomplete'
                         THEN a.duration_minutes ELSE 0 END), 0)::int
FROM public.attendance a
GROUP BY a.member_id, a.library_id, d
ON CONFLICT (member_id, library_id, date)
DO UPDATE SET present_flag = EXCLUDED.present_flag,
              total_minutes = EXCLUDED.total_minutes;

-- ============================================================================
-- VERIFY:
--   select count(*) from member_daily_stats;            -- > 0 after backfill
--   -- a fresh check-in/out updates the matching day row:
--   select * from member_daily_stats where member_id = '<id>' order by date desc limit 5;
-- ROLLBACK:
--   drop trigger if exists trg_attendance_daily_stats on public.attendance;
--   drop function if exists public.trg_attendance_daily_stats();
--   drop function if exists public.recompute_member_daily_stat(uuid, uuid, date);
--   -- (member_daily_stats rows can stay; the service tolerates stale rows)
-- ============================================================================
