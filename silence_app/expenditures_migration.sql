-- SILENCE expenditures Table Migration
-- Run this script in your Supabase SQL Editor (https://supabase.com/dashboard)

-- 1. Create expenditures table
CREATE TABLE IF NOT EXISTS expenditures (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    amount INTEGER NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('rent', 'electricity', 'internet', 'maintenance', 'other')),
    notes TEXT,
    proof_url TEXT,
    is_recurring BOOLEAN DEFAULT false,
    recurring_interval TEXT CHECK (recurring_interval IN ('monthly', 'quarterly', 'yearly')),
    expense_date TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Enable Row Level Security (RLS)
ALTER TABLE expenditures ENABLE ROW LEVEL SECURITY;

-- 3. Create RLS Policy for Admins
DROP POLICY IF EXISTS "Admins full access on own expenditures" ON expenditures;
CREATE POLICY "Admins full access on own expenditures" ON expenditures
    FOR ALL USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

-- 4. Create Indexes for optimization
CREATE INDEX IF NOT EXISTS idx_expenditures_library ON expenditures(library_id, expense_date);
