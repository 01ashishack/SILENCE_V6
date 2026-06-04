-- SQL Migration: Create expenditures table and set up security
-- Run this in your Supabase SQL Editor (https://supabase.com/dashboard/project/kndeshxeerldamafweru/sql/new)

CREATE TABLE IF NOT EXISTS expenditures (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    amount NUMERIC(10, 2) NOT NULL,
    category TEXT NOT NULL,
    notes TEXT,
    expense_date TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable Row Level Security (RLS)
ALTER TABLE expenditures ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS "Admins full access on own expenditures" ON expenditures;

-- Create policy for Admin full access on their own library expenditures
CREATE POLICY "Admins full access on own expenditures" ON expenditures
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM libraries
            WHERE id = expenditures.library_id AND owner_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM libraries
            WHERE id = expenditures.library_id AND owner_id = auth.uid()
        )
    );

-- Create indexes for query performance
CREATE INDEX IF NOT EXISTS idx_expenditures_library_id ON expenditures(library_id);
CREATE INDEX IF NOT EXISTS idx_expenditures_expense_date ON expenditures(expense_date);
