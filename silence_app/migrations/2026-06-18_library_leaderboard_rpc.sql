-- ============================================================================
-- 2026-06-18 — Leaderboard RPC (fixes member leaderboard under tenant-scoped
--              users SELECT, P10-04)
-- ============================================================================
--
-- The member analytics leaderboard read other members' names via a users(...)
-- embed on attendance. With users SELECT now tenant-scoped (a member can read
-- only their own users row), that embed returns null for everyone else and the
-- leaderboard collapses for member viewers.
--
-- This SECURITY DEFINER RPC computes the ranked leaderboard server-side from the
-- precomputed member_daily_stats, returning only a PRIVACY-FORMATTED name
-- ("Priya S.") + minutes — never other members' raw PII. The caller must belong
-- to (or own) the library, else it returns nothing.
--
-- Idempotent.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.library_leaderboard(
    p_library uuid, p_start date, p_end date)
RETURNS TABLE(member_id uuid, name text, total_minutes bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    -- Authorization: only a member or the owner of this library may read it.
    IF NOT EXISTS (SELECT 1 FROM public.memberships m
                   WHERE m.library_id = p_library AND m.member_id = auth.uid())
       AND NOT EXISTS (SELECT 1 FROM public.libraries l
                       WHERE l.id = p_library AND l.owner_id = auth.uid()) THEN
        RETURN;
    END IF;

    RETURN QUERY
        SELECT mds.member_id,
               CASE
                 WHEN u.nickname IS NOT NULL AND btrim(u.nickname) <> ''
                     THEN split_part(btrim(u.nickname), ' ', 1)
                 WHEN position(' ' IN btrim(coalesce(u.full_name, ''))) > 0
                     THEN split_part(btrim(u.full_name), ' ', 1) || ' '
                          || left(split_part(btrim(u.full_name), ' ', 2), 1) || '.'
                 ELSE coalesce(nullif(btrim(u.full_name), ''), 'User')
               END AS name,
               sum(mds.total_minutes)::bigint AS total_minutes
        FROM public.member_daily_stats mds
        JOIN public.users u ON u.id = mds.member_id
        WHERE mds.library_id = p_library
          AND mds.date BETWEEN p_start AND p_end
        GROUP BY mds.member_id, u.nickname, u.full_name
        HAVING sum(mds.total_minutes) > 0
        ORDER BY total_minutes DESC;
END;
$$;
REVOKE ALL ON FUNCTION public.library_leaderboard(uuid, uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.library_leaderboard(uuid, uuid, date) TO authenticated;

-- ============================================================================
-- VERIFY (as a member of the library):
--   select * from public.library_leaderboard('<lib>', current_date - 6, current_date);
-- ============================================================================
