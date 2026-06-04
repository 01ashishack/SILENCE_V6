-- SUPABASE MIGRATION SCRIPT
-- RUN THIS IN YOUR SUPABASE SQL EDITOR TO ADD THE REQUIRED COLUMNS

-- 1. Add missing total_inventory column to the add_ons table
ALTER TABLE add_ons 
ADD COLUMN IF NOT EXISTS total_inventory INTEGER DEFAULT 0;

-- 2. Add missing subject and type columns to the queries table
ALTER TABLE queries 
ADD COLUMN IF NOT EXISTS subject TEXT,
ADD COLUMN IF NOT EXISTS type TEXT;
