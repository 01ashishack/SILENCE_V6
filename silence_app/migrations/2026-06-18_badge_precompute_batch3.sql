-- ============================================================================
-- 2026-06-18 — Badge engine N+1, batch 3 (audit P11-02)
-- ============================================================================
--
-- Removes the last per-analytics-load attendance scans in syncAndFetchBadges:
--   * early_bird / night_owl: add per-day early/night session counts to
--     member_daily_stats (maintained by the existing trigger) so the badge
--     reads a sum of a few indexed rows instead of scanning every check-in.
--   * top_of_week: a member_is_week_top() RPC computes the weekly library
--     leader from member_daily_stats (indexed aggregate) instead of scanning
--     the whole library's attendance four times.
--
-- IST (Asia/Kolkata) hour is used for early(<07:00)/night(>=20:00), matching
-- the app clock. Idempotent.
-- ============================================================================

ALTER TABLE public.member_daily_stats
    ADD COLUMN IF NOT EXISTS early_count INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS night_count INTEGER DEFAULT 0;

-- Recompute now also rolls up early/night check-in counts for the day.
CREATE OR REPLACE FUNCTION public.recompute_member_daily_stat(
    p_member uuid, p_library uuid, p_date date)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_count   integer;
    v_present boolean;
    v_minutes integer;
    v_early   integer;
    v_night   integer;
BEGIN
    SELECT count(*)::int,
           bool_or(a.check_out_time IS NOT NULL OR a.session_type IS DISTINCT FROM 'incomplete'),
           COALESCE(sum(CASE WHEN a.session_type IS DISTINCT FROM 'incomplete'
                             THEN a.duration_minutes ELSE 0 END), 0)::int,
           count(*) FILTER (WHERE extract(hour FROM (a.check_in_time AT TIME ZONE 'Asia/Kolkata')) < 7)::int,
           count(*) FILTER (WHERE extract(hour FROM (a.check_in_time AT TIME ZONE 'Asia/Kolkata')) >= 20)::int
      INTO v_count, v_present, v_minutes, v_early, v_night
    FROM public.attendance a
    WHERE a.member_id = p_member
      AND a.library_id = p_library
      AND (a.check_in_time AT TIME ZONE 'Asia/Kolkata')::date = p_date;

    IF v_count = 0 THEN
        DELETE FROM public.member_daily_stats
         WHERE member_id = p_member AND library_id = p_library AND date = p_date;
        RETURN;
    END IF;

    INSERT INTO public.member_daily_stats
        (member_id, library_id, date, present_flag, total_minutes, early_count, night_count)
    VALUES (p_member, p_library, p_date, COALESCE(v_present, false),
            COALESCE(v_minutes, 0), COALESCE(v_early, 0), COALESCE(v_night, 0))
    ON CONFLICT (member_id, library_id, date)
    DO UPDATE SET present_flag  = EXCLUDED.present_flag,
                  total_minutes = EXCLUDED.total_minutes,
                  early_count   = EXCLUDED.early_count,
                  night_count   = EXCLUDED.night_count;
END;
$$;

-- Backfill the new columns for existing rows.
INSERT INTO public.member_daily_stats
    (member_id, library_id, date, present_flag, total_minutes, early_count, night_count)
SELECT a.member_id,
       a.library_id,
       (a.check_in_time AT TIME ZONE 'Asia/Kolkata')::date AS d,
       bool_or(a.check_out_time IS NOT NULL OR a.session_type IS DISTINCT FROM 'incomplete'),
       COALESCE(sum(CASE WHEN a.session_type IS DISTINCT FROM 'incomplete'
                         THEN a.duration_minutes ELSE 0 END), 0)::int,
       count(*) FILTER (WHERE extract(hour FROM (a.check_in_time AT TIME ZONE 'Asia/Kolkata')) < 7)::int,
       count(*) FILTER (WHERE extract(hour FROM (a.check_in_time AT TIME ZONE 'Asia/Kolkata')) >= 20)::int
FROM public.attendance a
GROUP BY a.member_id, a.library_id, d
ON CONFLICT (member_id, library_id, date)
DO UPDATE SET present_flag  = EXCLUDED.present_flag,
              total_minutes = EXCLUDED.total_minutes,
              early_count   = EXCLUDED.early_count,
              night_count   = EXCLUDED.night_count;

-- Weekly library leader (rank 1, ties allowed) computed from the rollup.
CREATE OR REPLACE FUNCTION public.member_is_week_top(
    p_library uuid, p_member uuid, p_start date, p_end date)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    WITH totals AS (
        SELECT member_id, sum(total_minutes) AS mins
        FROM public.member_daily_stats
        WHERE library_id = p_library AND date BETWEEN p_start AND p_end
        GROUP BY member_id
    )
    SELECT COALESCE(
        (SELECT mins FROM totals WHERE member_id = p_member) > 0
        AND (SELECT mins FROM totals WHERE member_id = p_member)
            >= COALESCE((SELECT max(mins) FROM totals), 0),
    false);
$$;
REVOKE ALL ON FUNCTION public.member_is_week_top(uuid, uuid, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.member_is_week_top(uuid, uuid, date, date) TO authenticated;

-- ============================================================================
-- VERIFY:
--   select member_id, sum(early_count), sum(night_count) from member_daily_stats group by member_id;
--   select public.member_is_week_top('<lib>','<member>', current_date - 6, current_date);
-- ROLLBACK: drop function member_is_week_top(...); columns can stay.
-- ============================================================================
