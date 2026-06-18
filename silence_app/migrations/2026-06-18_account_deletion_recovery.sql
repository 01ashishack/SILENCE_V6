-- ============================================================================
-- 2026-06-18 — Account deletion with 7-day recovery + owner approval (P14-02)
-- ============================================================================
--
-- WHY
--   "Delete account" must (a) schedule deletion, recoverable for 7 days, then
--   permanently purge; (b) freeze the account meanwhile; (c) route recovery
--   requests to the APP OWNER, who approves/denies. This adds the one column the
--   recovery state machine needs. (scheduled_for_deletion + deletion_scheduled_at
--   already exist; deletion_scheduled_at now stores the PURGE date = request+7d.)
--
-- STATE MACHINE (users.deletion_recovery_status):
--   'none'      — deletion requested, no recovery asked yet (frozen).
--   'requested' — user asked to recover; waiting for app-owner decision.
--   'approved'  — owner restored the account (set together with
--                 scheduled_for_deletion=false; effectively back to normal).
--   'denied'    — owner refused; account stays scheduled and will be purged.
--
-- The purge cron (Edge Function process-account-deletions) deletes users where
--   scheduled_for_deletion = true AND deletion_scheduled_at < now()
--   AND deletion_recovery_status <> 'approved'.
--
-- APPLY: run once in the Supabase SQL editor.
-- ROLLBACK: ALTER TABLE public.users DROP COLUMN deletion_recovery_status;
-- ============================================================================

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS deletion_recovery_status TEXT NOT NULL DEFAULT 'none';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'users_deletion_recovery_status_check'
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_deletion_recovery_status_check
      CHECK (deletion_recovery_status IN ('none', 'requested', 'approved', 'denied'));
  END IF;
END $$;

-- Helps the owner console list pending recovery requests quickly.
CREATE INDEX IF NOT EXISTS idx_users_recovery_pending
  ON public.users (deletion_recovery_status)
  WHERE scheduled_for_deletion = true;
