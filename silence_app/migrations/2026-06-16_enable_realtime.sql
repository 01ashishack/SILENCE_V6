-- 2026-06-16 — Enable Supabase Realtime on the tables the app subscribes to.
--
-- Why: the app already opens realtime channels (admin_home → join_requests,
-- layout_sub_tab → seats, member_analytics → attendance, etc.) but the live DB
-- never pushes changes because those tables are NOT in the `supabase_realtime`
-- publication. Result: admins/members must pull-to-refresh repeatedly to see
-- new requests, check-ins, seat changes. Adding the tables to the publication
-- makes the EXISTING subscriptions (and the new member_home one) fire.
--
-- Idempotent: each table is added only if it isn't already a member of the
-- publication, so this is safe to run more than once.

DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'join_requests',
    'memberships',
    'attendance',
    'seats',
    'notifications',
    'seat_change_requests',
    'hold_requests'
  ];
BEGIN
  -- The publication exists by default on Supabase; guard just in case.
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;

  FOREACH t IN ARRAY tables LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END $$;

-- Verify (optional): list realtime-enabled public tables.
-- SELECT tablename FROM pg_publication_tables
--   WHERE pubname = 'supabase_realtime' AND schemaname = 'public' ORDER BY 1;
