-- ============================================================
-- SILENCE Migration Script: Add Shift Columns
-- Description: Add shift_type and hours_per_day columns to shifts table
-- ============================================================

-- 1. Add shift_type column if it does not exist
ALTER TABLE shifts ADD COLUMN IF NOT EXISTS shift_type TEXT DEFAULT 'fixed';

-- 2. Validate/ensure the shift_type column can only be 'fixed' or 'hourly'
-- Note: We wrap in a block to handle cases where the constraint might already exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.constraint_column_usage 
        WHERE table_name = 'shifts' AND constraint_name = 'shifts_shift_type_check'
    ) THEN
        ALTER TABLE shifts ADD CONSTRAINT shifts_shift_type_check CHECK (shift_type IN ('fixed', 'hourly'));
    END IF;
END $$;

-- 3. Add hours_per_day column if it does not exist
ALTER TABLE shifts ADD COLUMN IF NOT EXISTS hours_per_day INTEGER DEFAULT NULL;
