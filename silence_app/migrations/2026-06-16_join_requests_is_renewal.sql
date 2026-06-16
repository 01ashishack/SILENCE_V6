-- 2026-06-16 — Mark a join_request as a RENEWAL of an existing membership.
--
-- Why: members renewing an active/expiring membership submit the same
-- join_requests row as a brand-new join. Without a flag the admin can't tell
-- them apart, and the approve flow mistakes every renewal for a "duplicate
-- membership" and offers to reject it (the member already has an active
-- membership — which is exactly what a renewal is).
--
-- This flag lets the UI badge renewals and lets the approve flow EXTEND the
-- existing membership (keeping the same seat) instead of treating it as a
-- duplicate. Additive + backward-compatible: old rows default to false.
--
-- Safe to run more than once.

ALTER TABLE public.join_requests
  ADD COLUMN IF NOT EXISTS is_renewal boolean NOT NULL DEFAULT false;

-- (No RLS change: the existing insert/select policies already cover this column.)
