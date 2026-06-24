-- ============================================================================
-- 2026-06-24 — H4: sanitize leaderboard display names
-- ============================================================================
--
-- library_leaderboard() broadcasts a co-member's name (from users.nickname /
-- full_name) to every member of the library. Those are unmoderated free-text
-- fields, so a member could set their nickname to a phone number or URL and
-- have it shown to all co-members (low-grade PII / spam vector).
--
-- sanitize_display_name() keeps only letters, spaces and a little safe
-- punctuation ('.', apostrophe, hyphen), strips digits / @ / slashes / colons
-- (so phone numbers + URLs don't survive), and caps the length at 20. The
-- leaderboard now formats the name THROUGH it (falling back to 'User').
--
-- Idempotent: CREATE OR REPLACE. Safe to re-run.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.sanitize_display_name(p text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$
  SELECT left(
           btrim(
             regexp_replace(coalesce(p, ''), '[^[:alpha:][:space:].''\-]', '', 'g')
           ),
           20);
$$;

CREATE OR REPLACE FUNCTION public.library_leaderboard(
    p_library uuid, p_start date, p_end date)
RETURNS TABLE(member_id uuid, name text, total_minutes bigint)
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
REVOKE ALL ON FUNCTION public.library_leaderboard(uuid, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.library_leaderboard(uuid, date, date) TO authenticated;

-- ============================================================================
-- VERIFY:
--   SELECT public.sanitize_display_name('9876543210');      -- '' → leaderboard shows 'User'
--   SELECT public.sanitize_display_name('Rahul');           -- 'Rahul'
--   SELECT public.sanitize_display_name('spam www.x.com/9'); -- 'spam www.x.com' digits/slash stripped, capped
-- ROLLBACK: re-apply the previous library_leaderboard (without sanitize) and
--   DROP FUNCTION IF EXISTS public.sanitize_display_name(text);
-- ============================================================================
