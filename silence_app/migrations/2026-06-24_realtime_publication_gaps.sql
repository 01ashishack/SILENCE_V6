-- ============================================================================
-- 2026-06-24 — Realtime publication gaps + REPLICA IDENTITY FULL
-- ============================================================================
--
-- WHY
--   2026-06-16_enable_realtime.sql added 7 tables to `supabase_realtime`
--   (attendance, hold_requests, join_requests, memberships, notifications,
--   seat_change_requests, seats) — confirmed live. But screens subscribe to a
--   few MORE tables that were never added, so those views stay stale until a
--   manual pull-to-refresh:
--     • checkin_approvals  — Requests tab (created later, 2026-06-22)
--     • floors, sections   — Seat-layout tab
--     • payments           — collection / revenue figures
--     • queries            — admin queries inbox / member replies
--
--   Also: with the default REPLICA IDENTITY (primary key only), Postgres only
--   ships the PK in the OLD tuple of UPDATE/DELETE WAL records. Supabase
--   Realtime evaluates a channel's `filter` (e.g. member_id=eq.<uid>) against
--   that record, so FILTERED channels can MISS update/delete events. Setting
--   REPLICA IDENTITY FULL ships the whole old row, making filtered UPDATE/DELETE
--   delivery reliable (cost: a bit more WAL — fine at this scale).
--
-- Idempotent: safe to re-run.
-- NOTE: adding a table to the publication only helps screens that actually
--   open a channel on it. payments/queries are included so revenue + query
--   views update live ONCE a subscription is added in the app (follow-up).
-- ============================================================================

-- 1. ── add the missing tables to the realtime publication ──────────────────
DO $$
DECLARE
  t      text;
  tables text[] := ARRAY[
    'checkin_approvals',
    'floors',
    'sections',
    'payments',
    'queries'
  ];
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;

  FOREACH t IN ARRAY tables LOOP
    -- Only add tables that exist and aren't already published.
    IF EXISTS (
         SELECT 1 FROM information_schema.tables
          WHERE table_schema = 'public' AND table_name = t)
       AND NOT EXISTS (
         SELECT 1 FROM pg_publication_tables
          WHERE pubname = 'supabase_realtime'
            AND schemaname = 'public'
            AND tablename = t)
    THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END $$;

-- 2. ── REPLICA IDENTITY FULL on every realtime table ───────────────────────
--    (the original 7 + the 5 above) so filtered UPDATE/DELETE events fire.
DO $$
DECLARE
  t      text;
  tables text[] := ARRAY[
    'attendance', 'hold_requests', 'join_requests', 'memberships',
    'notifications', 'seat_change_requests', 'seats',
    'checkin_approvals', 'floors', 'sections', 'payments', 'queries'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    IF EXISTS (
         SELECT 1 FROM information_schema.tables
          WHERE table_schema = 'public' AND table_name = t)
    THEN
      EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', t);
    END IF;
  END LOOP;
END $$;

-- ============================================================================
-- VERIFY:
--   SELECT tablename FROM pg_publication_tables
--    WHERE pubname='supabase_realtime' AND schemaname='public' ORDER BY 1;
--   -- expect the original 7 + checkin_approvals, floors, sections, payments, queries
--   SELECT relname, relreplident FROM pg_class
--    WHERE relname = ANY (ARRAY['attendance','memberships','seats','floors',
--      'sections','checkin_approvals','payments','queries'])
--    ORDER BY relname;   -- relreplident should be 'f' (FULL)
-- ROLLBACK (publication only; leaving REPLICA IDENTITY FULL is harmless):
--   ALTER PUBLICATION supabase_realtime DROP TABLE public.checkin_approvals;
--   ALTER PUBLICATION supabase_realtime DROP TABLE public.floors;
--   ALTER PUBLICATION supabase_realtime DROP TABLE public.sections;
--   ALTER PUBLICATION supabase_realtime DROP TABLE public.payments;
--   ALTER PUBLICATION supabase_realtime DROP TABLE public.queries;
-- ============================================================================
