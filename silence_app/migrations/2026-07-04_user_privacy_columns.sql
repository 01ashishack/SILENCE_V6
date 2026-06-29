-- ============================================================================
-- 2026-07-04 — user privacy columns + privacy-aware leaderboard (audit P0)
-- ============================================================================
--
-- PROBLEM: member_privacy_security_screen reads/writes show_on_leaderboard,
-- show_hours, hide_nickname on `users`, but those columns DID NOT EXIST. The
-- update failed silently (UI still showed success), and library_leaderboard
-- exposed opted-out members' name/hours anyway. Privacy + dishonest-UI defect.
--
-- FIX:
--   1) Add the 3 boolean columns (defaults preserve current behaviour: visible).
--      Member-self-writable via existing "Users can update own profile"; NOT in
--      the privileged-column lock trigger, so members can toggle them.
--   2) Make library_leaderboard honour them — SAME return signature (no Dart
--      change needed):
--        • show_on_leaderboard = false  → excluded entirely
--        • show_hours          = false  → excluded (can't rank on hidden hours)
--        • hide_nickname       = true   → name masked to 'Member'
--
-- Idempotent + additive. Apply in the Supabase SQL editor.
-- ============================================================================

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS show_on_leaderboard boolean NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS show_hours          boolean NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS hide_nickname       boolean NOT NULL DEFAULT false;

-- Return signature unchanged → CREATE OR REPLACE (no DROP needed).
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
               CASE WHEN COALESCE(u.hide_nickname, false) THEN 'Member'
                    ELSE COALESCE(NULLIF(public.sanitize_display_name(
                      CASE
                        WHEN u.nickname IS NOT NULL AND btrim(u.nickname) <> ''
                            THEN split_part(btrim(u.nickname), ' ', 1)
                        WHEN position(' ' IN btrim(coalesce(u.full_name, ''))) > 0
                            THEN split_part(btrim(u.full_name), ' ', 1) || ' '
                                 || left(split_part(btrim(u.full_name), ' ', 2), 1) || '.'
                        ELSE coalesce(nullif(btrim(u.full_name), ''), 'User')
                      END
                    ), ''), 'User')
               END AS name,
               sum(mds.total_minutes)::bigint AS total_minutes,
               u.avatar_id AS avatar_id
        FROM public.member_daily_stats mds
        JOIN public.users u ON u.id = mds.member_id
        WHERE mds.library_id = p_library
          AND mds.date BETWEEN p_start AND p_end
          AND COALESCE(u.show_on_leaderboard, true)   -- opted-out → excluded
          AND COALESCE(u.show_hours, true)            -- hours hidden → excluded
        GROUP BY mds.member_id, u.nickname, u.full_name, u.avatar_id, u.hide_nickname
        HAVING sum(mds.total_minutes) > 0
        ORDER BY total_minutes DESC;
END;
$$;
REVOKE ALL ON FUNCTION public.library_leaderboard(uuid, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.library_leaderboard(uuid, date, date) TO authenticated;

-- ============================================================================
-- VERIFY:
--   • Toggle show_on_leaderboard=false → member disappears from library_leaderboard.
--   • show_hours=false → member excluded from the (hours) leaderboard.
--   • hide_nickname=true → member's row shows 'Member' instead of their name.
--   • Privacy screen now shows success ONLY when the DB update succeeds.
-- ROLLBACK:
--   ALTER TABLE public.users DROP COLUMN IF EXISTS show_on_leaderboard,
--       DROP COLUMN IF EXISTS show_hours, DROP COLUMN IF EXISTS hide_nickname;
--   then re-create library_leaderboard from the prior canonical copy.
-- ============================================================================
