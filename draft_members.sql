-- ⚠️ SUPERSEDED (2026-06-11, Phase C). DO NOT RUN.
-- `draft_members` is now folded into silence_app/supabase_schema.sql (§2b) and
-- silence_app/migrations/2026-06-11_phase_c_reconciliation.sql. Kept for history.
-- ---------------------------------------------------------------------------
-- SQL Migration: Create draft_members table and set up security
-- Run this in your Supabase SQL Editor (https://supabase.com/dashboard/project/kndeshxeerldamafweru/sql/new)

CREATE TABLE IF NOT EXISTS draft_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    draft_data JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE draft_members ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS "Admins full access on own drafts" ON draft_members;

-- Create policy for Admin full access
CREATE POLICY "Admins full access on own drafts" ON draft_members
    FOR ALL 
    USING (
        admin_id = auth.uid() 
        OR EXISTS (
            SELECT 1 FROM libraries 
            WHERE id = library_id AND owner_id = auth.uid()
        )
    )
    WITH CHECK (
        admin_id = auth.uid() 
        OR EXISTS (
            SELECT 1 FROM libraries 
            WHERE id = library_id AND owner_id = auth.uid()
        )
    );

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_draft_members_library_id ON draft_members(library_id);
CREATE INDEX IF NOT EXISTS idx_draft_members_admin_id ON draft_members(admin_id);
