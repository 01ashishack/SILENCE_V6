-- ============================================================================
-- 2026-06-15 — Decouple payment verification from the join decision
-- ============================================================================
--
-- SYMPTOM
--   A join request carried BOTH the UPI payment-verification step and the
--   membership decision on one row. The admin's "Reject Pay" button set the
--   whole join_requests row to status='rejected', so the request vanished from
--   the pending list and no further action (re-pay / approve) was possible. The
--   member was also not notified. "Confirm Pay" was only an in-memory UI flag,
--   so it was lost on refresh.
--
-- FIX (this migration — app changes ride along in requests_sub_tab.dart)
--   1. Add join_requests.payment_status: 'unverified' | 'verified' | 'rejected'.
--      - Confirm Pay  -> payment_status='verified' (persisted; survives refresh).
--      - Reject Pay   -> payment_status='rejected' (request STAYS pending; the
--                        member is notified to re-pay / re-upload proof).
--      - Approve/Reject (membership) stay the only actions that finalize/cancel
--        the request.
--   2. Allow status='withdrawn' so a member withdrawing an application is a soft
--      state change (keeps history) instead of a hard row delete.
--
-- Additive + idempotent. Existing rows default to 'unverified'. No RLS change.
-- ============================================================================

-- 1. payment_status column ---------------------------------------------------
ALTER TABLE join_requests
  ADD COLUMN IF NOT EXISTS payment_status TEXT NOT NULL DEFAULT 'unverified';

ALTER TABLE join_requests DROP CONSTRAINT IF EXISTS join_requests_payment_status_check;
ALTER TABLE join_requests
  ADD CONSTRAINT join_requests_payment_status_check
  CHECK (payment_status IN ('unverified', 'verified', 'rejected'));

-- 2. allow 'withdrawn' on the status CHECK -----------------------------------
-- (the original inline CHECK is auto-named join_requests_status_check)
ALTER TABLE join_requests DROP CONSTRAINT IF EXISTS join_requests_status_check;
ALTER TABLE join_requests
  ADD CONSTRAINT join_requests_status_check
  CHECK (status IN ('pending', 'approved', 'rejected', 'expired', 'withdrawn'));
