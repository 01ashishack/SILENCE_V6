-- ============================================================================
-- 2026-06-24 — M4: bound notifications growth (purge old READ notifications)
-- ============================================================================
--
-- The notifications table has no retention; over months it grows unbounded and
-- the member center (limit 100) keeps scanning a larger table. This adds a
-- weekly pg_cron purge that deletes notifications the user has ALREADY READ and
-- that are older than 60 days. Unread notifications are NEVER deleted, and
-- nothing newer than 60 days is touched. (Client-side pagination of the list is
-- a separate, deferred UI task.)
--
-- Idempotent: safe to re-run.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.purge_old_notifications()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_deleted bigint;
BEGIN
    WITH del AS (
        DELETE FROM public.notifications
         WHERE read_at IS NOT NULL
           AND sent_at < now() - interval '60 days'
        RETURNING 1
    )
    SELECT count(*) INTO v_deleted FROM del;
    RETURN jsonb_build_object('deleted', v_deleted, 'ran_at', now());
END;
$$;
REVOKE ALL ON FUNCTION public.purge_old_notifications() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.purge_old_notifications() TO service_role;

-- Schedule weekly (Sun 03:00 IST = Sat 21:30 UTC). Best-effort.
DO $cronwrap$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule('silence-purge-notifications', '30 21 * * 6',
                              'SELECT public.purge_old_notifications();');
    ELSE
        RAISE NOTICE 'pg_cron not installed — schedule purge_old_notifications() weekly manually.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron scheduling skipped: %', SQLERRM;
END
$cronwrap$;

-- ============================================================================
-- VERIFY:
--   SELECT public.purge_old_notifications();   -- {deleted, ran_at}
--   SELECT * FROM cron.job WHERE jobname = 'silence-purge-notifications';
-- ROLLBACK:
--   DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron')
--     THEN PERFORM cron.unschedule('silence-purge-notifications'); END IF; END $$;
--   DROP FUNCTION IF EXISTS public.purge_old_notifications();
-- ============================================================================
