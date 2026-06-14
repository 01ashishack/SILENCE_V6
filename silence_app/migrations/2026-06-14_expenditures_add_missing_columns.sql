-- ============================================================================
-- 2026-06-14 — Fix: "Failed to add expense: Could not find the 'notes' column
--               of 'expenditures'" (PGRST204)
-- ============================================================================
--
-- SYMPTOM
--   Adding an expense fails with
--     PostgrestException(... Could not find the 'notes' column of
--     'expenditures' in the schema cache, code: PGRST204 ...)
--
-- ROOT CAUSE
--   The live `expenditures` table predates several columns the Flutter app
--   writes. The canonical supabase_schema.sql declares them, but it uses
--   `CREATE TABLE IF NOT EXISTS`, which does NOT add columns to a table that
--   already exists — so re-running the schema never patched the live table.
--   add_expense_bottom_sheet.dart inserts: notes, note, receipt_url,
--   is_recurring, added_by, is_deleted; admin_analytics_tab reads/writes `notes`.
--
-- FIX
--   Additively add any of those columns that are missing (idempotent — existing
--   columns are skipped). Types match the canonical schema.
--
-- APPLY: paste + Run once in the Supabase SQL editor. Safe to re-run.
-- ============================================================================

ALTER TABLE expenditures ADD COLUMN IF NOT EXISTS notes        TEXT;
ALTER TABLE expenditures ADD COLUMN IF NOT EXISTS note         TEXT;
ALTER TABLE expenditures ADD COLUMN IF NOT EXISTS receipt_url  TEXT;
ALTER TABLE expenditures ADD COLUMN IF NOT EXISTS is_recurring BOOLEAN DEFAULT false;
ALTER TABLE expenditures ADD COLUMN IF NOT EXISTS is_deleted   BOOLEAN DEFAULT false;
ALTER TABLE expenditures ADD COLUMN IF NOT EXISTS added_by     TEXT;
