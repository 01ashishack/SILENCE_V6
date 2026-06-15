-- ============================================================================
-- 2026-06-14 — Fix: member "Complete/Edit Profile" save shows an error but the
--               profile details never actually save
-- ============================================================================
--
-- SYMPTOM
--   A member completes their profile, taps save → a "please try again" /
--   "something went wrong" error shows. The basic row (from signup) is in the DB
--   so it LOOKS like data saved, but the profile fields (phone/gender/dob/
--   address/ID) were NOT written.
--
-- ROOT CAUSE
--   member_profile_edit.dart upserts into `users` with columns that the live
--   table is missing — `id_proof_2_url`, `id_type`, `father_name`,
--   `emergency_contact`. PostgREST rejects the whole upsert (PGRST204
--   "Could not find the 'X' column"), so nothing in that write persists. The
--   canonical schema never declared these columns and the live table predates
--   them (same class as the expenditures fix).
--
-- FIX
--   Additively add the missing columns (idempotent). Folded into canonical
--   supabase_schema.sql too, so fresh DBs get them.
--
-- APPLY: paste + Run once in the Supabase SQL editor. Safe to re-run.
-- ============================================================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS id_proof_2_url    TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS id_type           TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS father_name       TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS emergency_contact TEXT;
