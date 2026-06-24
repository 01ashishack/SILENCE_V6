-- ============================================================================
-- 2026-06-24 — Time-based notifications (pg_cron, server-authoritative)
-- ============================================================================
--
-- Five scheduled jobs that write into public.notifications so reminders fire
-- even when the app is closed. Every job is SECURITY DEFINER, idempotent and
-- self-deduping (it never sends the same reminder twice in the same IST day),
-- and uses the SAME `data.type` values the app's notification center already
-- routes + styles (notifications_screen.dart + notification_service.dart):
--
--   MEMBER:
--     • expiry         — membership expires in 3 days / 1 day / today
--     • streak_reminder— attended yesterday, not yet today → keep the streak
--   ADMIN (library owner):
--     • expiring_digest— N members expiring within 3 days
--     • daily_summary  — today's confirmed collection (₹ + count)
--     • dues_digest    — members whose membership has lapsed (end_date < today)
--
-- All times are computed in IST. pg_cron on Supabase fires in UTC, so the
-- schedules below are the UTC equivalents of the intended IST times (noted
-- inline). No app changes are required — the types are already wired.
--
-- Idempotent: safe to re-run (CREATE OR REPLACE + re-schedule replaces jobs).
-- ============================================================================

-- Helper-free design: each function inlines its IST "today" so there are no
-- cross-object dependencies to manage.

-- 1. ── MEMBER: membership expiry reminders (3d / 1d / today) ────────────────
CREATE OR REPLACE FUNCTION public.notify_membership_expiry()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
    r       RECORD;
    v_days  int;
    v_sent  int := 0;
BEGIN
    FOR r IN
        SELECT m.id, m.member_id, m.end_date, l.name AS lib_name
          FROM public.memberships m
          JOIN public.libraries l ON l.id = m.library_id
         WHERE m.status IN ('active', 'trial')
           AND m.end_date IN (v_today, v_today + 1, v_today + 3)
    LOOP
        v_days := r.end_date - v_today;     -- 0, 1 or 3

        -- Dedupe: one reminder per membership per offset per IST day.
        IF EXISTS (
            SELECT 1 FROM public.notifications n
             WHERE n.user_id = r.member_id
               AND n.data->>'type' = 'expiry'
               AND n.data->>'membership_id' = r.id::text
               AND n.data->>'days_left' = v_days::text
               AND (n.sent_at AT TIME ZONE 'Asia/Kolkata')::date = v_today
        ) THEN
            CONTINUE;
        END IF;

        INSERT INTO public.notifications (user_id, title, body, data)
        VALUES (
            r.member_id,
            CASE WHEN v_days = 0 THEN 'Membership expires today'
                 WHEN v_days = 1 THEN 'Membership expires tomorrow'
                 ELSE 'Membership expiring soon' END,
            CASE WHEN v_days = 0
                     THEN 'Your membership at ' || r.lib_name || ' expires today. Renew to keep your seat.'
                 WHEN v_days = 1
                     THEN 'Your membership at ' || r.lib_name || ' expires tomorrow. Renew now to avoid losing your seat.'
                 ELSE 'Your membership at ' || r.lib_name || ' expires in ' || v_days
                      || ' days. Renew soon to keep your seat.' END,
            jsonb_build_object('type', 'expiry', 'route', '/member/home',
                               'membership_id', r.id, 'days_left', v_days)
        );
        v_sent := v_sent + 1;
    END LOOP;

    RETURN jsonb_build_object('sent', v_sent, 'ran_at', now());
END;
$$;
REVOKE ALL ON FUNCTION public.notify_membership_expiry() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.notify_membership_expiry() TO service_role;

-- 2. ── ADMIN: expiring-members digest (≤3 days out) ─────────────────────────
CREATE OR REPLACE FUNCTION public.notify_admin_expiring_digest()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
    r       RECORD;
    v_sent  int := 0;
BEGIN
    FOR r IN
        SELECT l.owner_id, l.id AS lib_id, l.name AS lib_name, count(*) AS cnt
          FROM public.memberships m
          JOIN public.libraries l ON l.id = m.library_id
         WHERE m.status IN ('active', 'trial')
           AND m.end_date BETWEEN v_today AND v_today + 3
         GROUP BY l.owner_id, l.id, l.name
    LOOP
        IF EXISTS (
            SELECT 1 FROM public.notifications n
             WHERE n.user_id = r.owner_id
               AND n.data->>'type' = 'expiring_digest'
               AND n.data->>'library_id' = r.lib_id::text
               AND (n.sent_at AT TIME ZONE 'Asia/Kolkata')::date = v_today
        ) THEN
            CONTINUE;
        END IF;

        INSERT INTO public.notifications (user_id, title, body, data)
        VALUES (
            r.owner_id,
            'Memberships expiring soon',
            r.cnt || ' member' || CASE WHEN r.cnt = 1 THEN '' ELSE 's' END
            || ' at ' || r.lib_name || ' ' || CASE WHEN r.cnt = 1 THEN 'is' ELSE 'are' END
            || ' expiring within 3 days. Review and follow up for renewals.',
            jsonb_build_object('type', 'expiring_digest', 'route', '/admin/home',
                               'library_id', r.lib_id, 'count', r.cnt)
        );
        v_sent := v_sent + 1;
    END LOOP;

    RETURN jsonb_build_object('sent', v_sent, 'ran_at', now());
END;
$$;
REVOKE ALL ON FUNCTION public.notify_admin_expiring_digest() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.notify_admin_expiring_digest() TO service_role;

-- 3. ── MEMBER: streak reminder (attended yesterday, not yet today) ──────────
CREATE OR REPLACE FUNCTION public.notify_streak_reminders()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
    r       RECORD;
    v_sent  int := 0;
BEGIN
    FOR r IN
        SELECT DISTINCT a.member_id
          FROM public.attendance a
         WHERE (a.check_in_time AT TIME ZONE 'Asia/Kolkata')::date = v_today - 1
           -- still an active member somewhere
           AND EXISTS (
               SELECT 1 FROM public.memberships m
                WHERE m.member_id = a.member_id AND m.status IN ('active', 'trial'))
           -- has NOT checked in today yet
           AND NOT EXISTS (
               SELECT 1 FROM public.attendance a2
                WHERE a2.member_id = a.member_id
                  AND (a2.check_in_time AT TIME ZONE 'Asia/Kolkata')::date = v_today)
    LOOP
        IF EXISTS (
            SELECT 1 FROM public.notifications n
             WHERE n.user_id = r.member_id
               AND n.data->>'type' = 'streak_reminder'
               AND (n.sent_at AT TIME ZONE 'Asia/Kolkata')::date = v_today
        ) THEN
            CONTINUE;
        END IF;

        INSERT INTO public.notifications (user_id, title, body, data)
        VALUES (
            r.member_id,
            'Keep your streak alive 🔥',
            'You studied yesterday but haven''t checked in today. Drop by and keep your streak going!',
            jsonb_build_object('type', 'streak_reminder', 'route', '/member/home')
        );
        v_sent := v_sent + 1;
    END LOOP;

    RETURN jsonb_build_object('sent', v_sent, 'ran_at', now());
END;
$$;
REVOKE ALL ON FUNCTION public.notify_streak_reminders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.notify_streak_reminders() TO service_role;

-- 4. ── ADMIN: daily collection summary (today's confirmed payments) ─────────
CREATE OR REPLACE FUNCTION public.notify_daily_collection_summary()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
    r       RECORD;
    v_sent  int := 0;
BEGIN
    FOR r IN
        SELECT l.owner_id, l.id AS lib_id, l.name AS lib_name,
               count(*) AS cnt, COALESCE(sum(p.amount), 0) AS total
          FROM public.payments p
          JOIN public.libraries l ON l.id = p.library_id
         WHERE p.status = 'confirmed'
           AND (p.payment_date AT TIME ZONE 'Asia/Kolkata')::date = v_today
         GROUP BY l.owner_id, l.id, l.name
    LOOP
        -- Only worth sending when there was money in (skip silent zero days).
        IF r.cnt = 0 THEN CONTINUE; END IF;

        IF EXISTS (
            SELECT 1 FROM public.notifications n
             WHERE n.user_id = r.owner_id
               AND n.data->>'type' = 'daily_summary'
               AND n.data->>'library_id' = r.lib_id::text
               AND (n.sent_at AT TIME ZONE 'Asia/Kolkata')::date = v_today
        ) THEN
            CONTINUE;
        END IF;

        INSERT INTO public.notifications (user_id, title, body, data)
        VALUES (
            r.owner_id,
            'Today''s collection',
            'You collected ₹' || r.total || ' from ' || r.cnt || ' payment'
            || CASE WHEN r.cnt = 1 THEN '' ELSE 's' END || ' at ' || r.lib_name || ' today.',
            jsonb_build_object('type', 'daily_summary', 'route', '/admin/home',
                               'library_id', r.lib_id, 'count', r.cnt, 'total', r.total)
        );
        v_sent := v_sent + 1;
    END LOOP;

    RETURN jsonb_build_object('sent', v_sent, 'ran_at', now());
END;
$$;
REVOKE ALL ON FUNCTION public.notify_daily_collection_summary() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.notify_daily_collection_summary() TO service_role;

-- 5. ── ADMIN: weekly dues digest (lapsed memberships) ───────────────────────
CREATE OR REPLACE FUNCTION public.notify_dues_digest()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
    r       RECORD;
    v_sent  int := 0;
BEGIN
    FOR r IN
        SELECT l.owner_id, l.id AS lib_id, l.name AS lib_name, count(*) AS cnt
          FROM public.memberships m
          JOIN public.libraries l ON l.id = m.library_id
         WHERE m.status IN ('active', 'expired')   -- still on the books, but lapsed
           AND m.end_date < v_today
         GROUP BY l.owner_id, l.id, l.name
    LOOP
        IF r.cnt = 0 THEN CONTINUE; END IF;

        IF EXISTS (
            SELECT 1 FROM public.notifications n
             WHERE n.user_id = r.owner_id
               AND n.data->>'type' = 'dues_digest'
               AND n.data->>'library_id' = r.lib_id::text
               AND (n.sent_at AT TIME ZONE 'Asia/Kolkata')::date = v_today
        ) THEN
            CONTINUE;
        END IF;

        INSERT INTO public.notifications (user_id, title, body, data)
        VALUES (
            r.owner_id,
            'Members with dues',
            r.cnt || ' member' || CASE WHEN r.cnt = 1 THEN '' ELSE 's' END
            || ' at ' || r.lib_name || ' ' || CASE WHEN r.cnt = 1 THEN 'has' ELSE 'have' END
            || ' an expired membership pending renewal. Follow up to recover dues.',
            jsonb_build_object('type', 'dues_digest', 'route', '/admin/home',
                               'library_id', r.lib_id, 'count', r.cnt)
        );
        v_sent := v_sent + 1;
    END LOOP;

    RETURN jsonb_build_object('sent', v_sent, 'ran_at', now());
END;
$$;
REVOKE ALL ON FUNCTION public.notify_dues_digest() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.notify_dues_digest() TO service_role;

-- 6. ── schedule the crons (best-effort; skipped if pg_cron isn't installed) ─
-- pg_cron fires in UTC on Supabase. IST = UTC + 5:30, so:
--   09:00 IST = 03:30 UTC · 09:30 IST = 04:00 UTC · 19:00 IST = 13:30 UTC
--   21:30 IST = 16:00 UTC · Mon 09:00 IST = Mon 03:30 UTC
DO $cronwrap$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule('silence-expiry-reminders',  '30 3 * * *',
                              'SELECT public.notify_membership_expiry();');
        PERFORM cron.schedule('silence-expiring-digest',   '0 4 * * *',
                              'SELECT public.notify_admin_expiring_digest();');
        PERFORM cron.schedule('silence-streak-reminders',  '30 13 * * *',
                              'SELECT public.notify_streak_reminders();');
        PERFORM cron.schedule('silence-daily-collection',  '0 16 * * *',
                              'SELECT public.notify_daily_collection_summary();');
        PERFORM cron.schedule('silence-dues-digest',       '30 3 * * 1',
                              'SELECT public.notify_dues_digest();');
    ELSE
        RAISE NOTICE 'pg_cron not installed — enable it (Dashboard → Database → Extensions) then re-run this file, or schedule the five functions manually under Database → Cron.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron scheduling skipped: %', SQLERRM;
END
$cronwrap$;

-- ============================================================================
-- VERIFY (run each manually first — they are safe, idempotent and dedupe):
--   SELECT public.notify_membership_expiry();         -- {sent, ran_at}
--   SELECT public.notify_admin_expiring_digest();
--   SELECT public.notify_streak_reminders();
--   SELECT public.notify_daily_collection_summary();
--   SELECT public.notify_dues_digest();
--   -- then check: SELECT title, body, data FROM notifications ORDER BY sent_at DESC LIMIT 20;
--   -- Running any of them twice in the same IST day inserts NOTHING the 2nd time.
--   SELECT * FROM cron.job WHERE jobname LIKE 'silence-%';
-- ROLLBACK:
--   DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
--     PERFORM cron.unschedule('silence-expiry-reminders');
--     PERFORM cron.unschedule('silence-expiring-digest');
--     PERFORM cron.unschedule('silence-streak-reminders');
--     PERFORM cron.unschedule('silence-daily-collection');
--     PERFORM cron.unschedule('silence-dues-digest');
--   END IF; END $$;
--   DROP FUNCTION IF EXISTS public.notify_membership_expiry();
--   DROP FUNCTION IF EXISTS public.notify_admin_expiring_digest();
--   DROP FUNCTION IF EXISTS public.notify_streak_reminders();
--   DROP FUNCTION IF EXISTS public.notify_daily_collection_summary();
--   DROP FUNCTION IF EXISTS public.notify_dues_digest();
-- ============================================================================
