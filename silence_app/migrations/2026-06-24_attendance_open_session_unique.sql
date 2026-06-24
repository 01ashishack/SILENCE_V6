-- ============================================================================
-- 2026-06-24 — C4: one OPEN attendance session per (member, library)
-- ============================================================================
--
-- The scanner does read-then-insert (query check_out_time IS NULL → insert),
-- which races on two devices / a double-tap → two concurrent open sessions.
-- The second never accrues duration and shows as a perpetual "active" session.
--
-- This adds a partial UNIQUE index so the DB rejects a 2nd open session
-- (Postgres error 23505); the app treats that as "already checked in".
-- Different libraries keep independent open sessions (partition includes
-- library_id), so a member legitimately active at two libraries is unaffected.
--
-- STEP 1 first CLOSES any pre-existing duplicate opens (keeps the latest open;
-- older opens become zero-duration 'incomplete') so the unique index can build.
--
-- Idempotent: safe to re-run.
-- ============================================================================

-- 1. Clean up existing duplicate OPEN sessions (keep the most recent open one).
WITH ranked AS (
    SELECT id,
           row_number() OVER (PARTITION BY member_id, library_id
                              ORDER BY check_in_time DESC) AS rn
      FROM public.attendance
     WHERE check_out_time IS NULL
)
UPDATE public.attendance a
   SET check_out_time   = a.check_in_time,   -- zero-duration close
       duration_minutes = 0,
       session_type     = 'incomplete'
  FROM ranked r
 WHERE a.id = r.id
   AND r.rn > 1;

-- 2. At most one open session per (member, library).
CREATE UNIQUE INDEX IF NOT EXISTS uq_attendance_open_session
    ON public.attendance (member_id, library_id)
    WHERE check_out_time IS NULL;

-- ============================================================================
-- VERIFY:
--   SELECT member_id, library_id, count(*)
--     FROM public.attendance WHERE check_out_time IS NULL
--    GROUP BY 1,2 HAVING count(*) > 1;     -- expect 0 rows
--   -- a 2nd concurrent check-in insert now fails with SQLSTATE 23505.
-- ROLLBACK:
--   DROP INDEX IF EXISTS public.uq_attendance_open_session;
-- ============================================================================
