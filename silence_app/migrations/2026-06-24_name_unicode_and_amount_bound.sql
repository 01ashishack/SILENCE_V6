-- ============================================================================
-- 2026-06-24 — Batch 5: Unicode-safe name sanitize (N3) + payment amount bound
-- ============================================================================
--
-- N3: the first version of sanitize_display_name() WHITELISTED [:alpha:], which
-- under the C/default collation strips NON-ASCII letters — so Devanagari
-- ("राहुल") or accented ("José") names collapsed to '' → "User" on the
-- leaderboard. For an India-first app that erases most real names. This flips to
-- a BLACKLIST: strip only digits and URL/handle chars (0-9 @ : /), which still
-- kills phone numbers and links but preserves names in ANY script.
--
-- Missed-1: payments.amount had no bound. A tampered client on a non-RPC insert
-- path could record a huge negative "payment" to wipe out dues. Add a sanity
-- bound (refunds use small negatives, so the lower bound stays generous). Added
-- NOT VALID so legacy rows aren't scanned/blocked; new + updated rows are checked.
--
-- Idempotent: CREATE OR REPLACE + guarded ADD CONSTRAINT.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.sanitize_display_name(p text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$
  SELECT left(btrim(regexp_replace(coalesce(p, ''), '[0-9@:/]+', '', 'g')), 20);
$$;

-- Payment amount sanity bound (Missed-1). NOT VALID = enforce going forward
-- without scanning/locking existing rows.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_payments_amount_bound'
    ) THEN
        ALTER TABLE public.payments
            ADD CONSTRAINT chk_payments_amount_bound
            CHECK (amount BETWEEN -100000 AND 10000000) NOT VALID;
    END IF;
END $$;

-- ============================================================================
-- VERIFY:
--   SELECT public.sanitize_display_name('राहुल 99');   -- 'राहुल ' → trimmed 'राहुल'
--   SELECT public.sanitize_display_name('José');        -- 'José'
--   SELECT public.sanitize_display_name('9876543210');  -- '' → leaderboard 'User'
--   -- INSERT a payment with amount = -999999 → rejected (23514).
--   -- (optional, after confirming legacy rows are in range:)
--   -- ALTER TABLE public.payments VALIDATE CONSTRAINT chk_payments_amount_bound;
-- ROLLBACK:
--   ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS chk_payments_amount_bound;
--   -- and restore the previous sanitize_display_name body.
-- ============================================================================
