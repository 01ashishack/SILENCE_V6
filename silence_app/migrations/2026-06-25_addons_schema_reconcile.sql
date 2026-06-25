-- ============================================================================
-- 2026-06-25 — Reconcile live add_ons table to the app/canonical shape
-- ============================================================================
--
-- Symptom: POST /rest/v1/add_ons → 400 Bad Request when an admin adds an add-on.
-- Cause: the live add_ons table drifted from the canonical schema — the app's
-- insert sends { name, price, price_type, refundable_deposit, max_available,
-- active } but the live table is missing one of those (or still has a legacy
-- NOT-NULL `total_inventory` the insert doesn't fill), so PostgREST rejects it.
--
-- This brings the live table to the expected shape WITHOUT data loss:
--   • ensures price_type (default 'monthly'), max_available, refundable_deposit,
--     active exist;
--   • migrates a legacy total_inventory → max_available (rename) if present;
--   • if total_inventory still exists, relaxes it (nullable + default 0) so
--     inserts that omit it don't fail;
--   • reloads PostgREST's schema cache.
--
-- Idempotent: safe to re-run.
-- ============================================================================

DO $$
BEGIN
    -- price_type (app always sends it; give a default so legacy rows are valid)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='add_ons' AND column_name='price_type') THEN
        ALTER TABLE public.add_ons ADD COLUMN price_type TEXT;
    END IF;
    UPDATE public.add_ons SET price_type = 'monthly' WHERE price_type IS NULL;
    ALTER TABLE public.add_ons ALTER COLUMN price_type SET DEFAULT 'monthly';

    -- max_available (current name). Migrate a legacy total_inventory if needed.
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='add_ons' AND column_name='max_available') THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='add_ons' AND column_name='total_inventory') THEN
            ALTER TABLE public.add_ons RENAME COLUMN total_inventory TO max_available;
        ELSE
            ALTER TABLE public.add_ons ADD COLUMN max_available INTEGER;
        END IF;
    END IF;

    -- refundable_deposit / active safety
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='add_ons' AND column_name='refundable_deposit') THEN
        ALTER TABLE public.add_ons ADD COLUMN refundable_deposit INTEGER DEFAULT 0;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='add_ons' AND column_name='active') THEN
        ALTER TABLE public.add_ons ADD COLUMN active BOOLEAN DEFAULT true;
    END IF;

    -- If a legacy total_inventory column still exists (wasn't renamed because
    -- max_available already existed), make sure it can't block inserts.
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema='public' AND table_name='add_ons' AND column_name='total_inventory') THEN
        ALTER TABLE public.add_ons ALTER COLUMN total_inventory DROP NOT NULL;
        ALTER TABLE public.add_ons ALTER COLUMN total_inventory SET DEFAULT 0;
    END IF;
END $$;

-- Reload PostgREST's schema cache so the new/renamed columns are recognised.
NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- VERIFY:
--   SELECT column_name, data_type, is_nullable, column_default
--     FROM information_schema.columns
--    WHERE table_schema='public' AND table_name='add_ons' ORDER BY ordinal_position;
--   -- then add an add-on from the app → should save (no 400).
-- ============================================================================
