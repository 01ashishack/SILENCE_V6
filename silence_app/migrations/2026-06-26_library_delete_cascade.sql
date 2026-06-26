-- 2026-06-26_library_delete_cascade.sql
-- ---------------------------------------------------------------------------
-- FIX: "Delete library" fails when the library has any memberships /
-- attendance / payments rows.
--
-- Root cause: memberships.library_id, attendance.library_id and
-- payments.library_id reference libraries(id) with ON DELETE RESTRICT, so
-- Postgres blocks the parent delete the moment any child row exists. Other
-- child tables (floors, seats, shifts, queries, audit_log, reviews, ...) are
-- already ON DELETE CASCADE.
--
-- This migration converts EVERY foreign key that references libraries(id) and
-- is currently RESTRICT or NO ACTION into ON DELETE CASCADE, so a single
-- `DELETE FROM libraries WHERE id = ...` cleanly removes the library and all
-- of its dependent rows (members, attendance, payments, etc.).
--
-- Safe to run multiple times: it only touches constraints that are NOT already
-- CASCADE/SET NULL/SET DEFAULT.
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.conname,
           c.conrelid::regclass::text AS child_table,
           pg_get_constraintdef(c.oid) AS def
    FROM pg_constraint c
    WHERE c.contype = 'f'
      AND c.confrelid = 'public.libraries'::regclass
      AND c.confdeltype IN ('a', 'r')  -- a = NO ACTION, r = RESTRICT
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.child_table, r.conname);
    EXECUTE format(
      'ALTER TABLE %s ADD CONSTRAINT %I %s ON DELETE CASCADE',
      r.child_table,
      r.conname,
      regexp_replace(
        r.def,
        '\s+ON DELETE (NO ACTION|RESTRICT|SET NULL|SET DEFAULT|CASCADE)',
        '',
        'gi'
      )
    );
    RAISE NOTICE 'Converted % on % to ON DELETE CASCADE', r.conname, r.child_table;
  END LOOP;
END $$;
