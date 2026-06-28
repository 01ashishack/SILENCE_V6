-- ============================================================================
-- 2026-06-28 — Member preset avatar (icon index) + expose it on the leaderboard
-- ============================================================================
-- Members pick one of 10 preset icon-avatars instead of a real photo. We store
-- the chosen index (0–9) in users.avatar_id and surface it on the leaderboard
-- so co-members see each other's avatar. avatar_id is just an icon index (NOT a
-- photo), so broadcasting it raises no privacy concern.
--
-- Idempotent. Apply in the Supabase SQL editor; folded into supabase_schema.sql.
-- ============================================================================

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS avatar_id INT;

-- Return type changes (3 → 4 cols), so CREATE OR REPLACE can't alter it —
-- drop the old function first, then recreate with avatar_id.
DROP FUNCTION IF EXISTS public.library_leaderboard(uuid, date, date);

-- Recreate the leaderboard RPC to also return avatar_id.
CREATE OR REPLACE FUNCTION public.library_leaderboard(
    p_library uuid, p_start date, p_end date)
RETURNS TABLE(member_id uuid, name text, total_minutes bigint, avatar_id int)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.memberships m
                   WHERE m.library_id = p_library AND m.member_id = auth.uid())
       AND NOT EXISTS (SELECT 1 FROM public.libraries l
                       WHERE l.id = p_library AND l.owner_id = auth.uid()) THEN
        RETURN;
    END IF;
    RETURN QUERY
        SELECT mds.member_id,
               COALESCE(NULLIF(public.sanitize_display_name(
                 CASE
                   WHEN u.nickname IS NOT NULL AND btrim(u.nickname) <> ''
                       THEN split_part(btrim(u.nickname), ' ', 1)
                   WHEN position(' ' IN btrim(coalesce(u.full_name, ''))) > 0
                       THEN split_part(btrim(u.full_name), ' ', 1) || ' '
                            || left(split_part(btrim(u.full_name), ' ', 2), 1) || '.'
                   ELSE coalesce(nullif(btrim(u.full_name), ''), 'User')
                 END
               ), ''), 'User') AS name,
               sum(mds.total_minutes)::bigint AS total_minutes,
               u.avatar_id AS avatar_id
        FROM public.member_daily_stats mds
        JOIN public.users u ON u.id = mds.member_id
        WHERE mds.library_id = p_library
          AND mds.date BETWEEN p_start AND p_end
        GROUP BY mds.member_id, u.nickname, u.full_name, u.avatar_id
        HAVING sum(mds.total_minutes) > 0
        ORDER BY total_minutes DESC;
END;
$$;
REVOKE ALL ON FUNCTION public.library_leaderboard(uuid, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.library_leaderboard(uuid, date, date) TO authenticated;
