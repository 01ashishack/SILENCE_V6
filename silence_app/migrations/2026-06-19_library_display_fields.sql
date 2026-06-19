-- ============================================================
-- SILENCE — Library display fields (admin-editable, public-profile facing)
-- Date: 2026-06-19
-- Adds two manual, admin-controlled fields to `libraries`:
--   * opening_hours          — free text shown as the library's opening time
--                              (e.g. "6:00 AM – 11:00 PM" or "Open 24 Hours").
--                              Edited in Profile → Library Management → About & Info.
--   * display_members_joined — manual social-proof label shown on the public
--                              profile (e.g. "500+"). NOT the live membership
--                              count; it's the number the admin wants to show.
-- Both are nullable; existing rows default to NULL (UI falls back gracefully).
-- Owner UPDATE is already covered by the existing libraries RLS policy, so no
-- new policy is required.
-- Apply manually, then verify in Supabase, then fold into supabase_schema.sql.
-- ============================================================

ALTER TABLE libraries ADD COLUMN IF NOT EXISTS opening_hours TEXT;
ALTER TABLE libraries ADD COLUMN IF NOT EXISTS display_members_joined TEXT;
