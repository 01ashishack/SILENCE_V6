-- SQL Script to set up Supabase Storage Buckets and RLS Policies for SILENCE App.
-- Execute this script in your Supabase SQL Editor (https://supabase.com/dashboard/project/_/sql).

-- =========================================================================
-- 1. Create Buckets
-- =========================================================================

-- Insert 'silence_assets' bucket (public bucket for library photos, QR codes, avatars)
INSERT INTO storage.buckets (id, name, public)
VALUES ('silence_assets', 'silence_assets', true)
ON CONFLICT (id) DO NOTHING;

-- Insert 'silence_private' bucket (private bucket for member profiles, payment proofs, admin docs)
INSERT INTO storage.buckets (id, name, public)
VALUES ('silence_private', 'silence_private', false)
ON CONFLICT (id) DO NOTHING;

-- Insert 'silence_temp' bucket (temporary public bucket)
INSERT INTO storage.buckets (id, name, public)
VALUES ('silence_temp', 'silence_temp', true)
ON CONFLICT (id) DO NOTHING;

-- =========================================================================
-- 2. Setup Policies for silence_assets
-- =========================================================================

DROP POLICY IF EXISTS "Public Read Access for silence_assets" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Insert for silence_assets" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Update for silence_assets" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Delete for silence_assets" ON storage.objects;

-- SELECT: Anyone can read public assets
CREATE POLICY "Public Read Access for silence_assets"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'silence_assets');

-- INSERT: Authenticated users (admins/members) can upload assets
CREATE POLICY "Authenticated Insert for silence_assets"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'silence_assets');

-- UPDATE: Authenticated users can update assets
CREATE POLICY "Authenticated Update for silence_assets"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'silence_assets')
WITH CHECK (bucket_id = 'silence_assets');

-- DELETE: Authenticated users can delete assets
CREATE POLICY "Authenticated Delete for silence_assets"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'silence_assets');

-- =========================================================================
-- 3. Setup Policies for silence_private
-- =========================================================================

DROP POLICY IF EXISTS "Authenticated Read Access for silence_private" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Insert for silence_private" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Update for silence_private" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Delete for silence_private" ON storage.objects;

-- SELECT: Authenticated users can read private assets (RLS rules on table handle user-specific rules)
CREATE POLICY "Authenticated Read Access for silence_private"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'silence_private');

-- INSERT: Authenticated users can insert private assets
CREATE POLICY "Authenticated Insert for silence_private"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'silence_private');

-- UPDATE: Authenticated users can update private assets
CREATE POLICY "Authenticated Update for silence_private"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'silence_private')
WITH CHECK (bucket_id = 'silence_private');

-- DELETE: Authenticated users can delete private assets
CREATE POLICY "Authenticated Delete for silence_private"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'silence_private');

-- =========================================================================
-- 4. Setup Policies for silence_temp
-- =========================================================================

DROP POLICY IF EXISTS "Public Read Access for silence_temp" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Insert for silence_temp" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Update for silence_temp" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Delete for silence_temp" ON storage.objects;

-- SELECT: Public read access
CREATE POLICY "Public Read Access for silence_temp"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'silence_temp');

-- INSERT: Authenticated users can insert temp assets
CREATE POLICY "Authenticated Insert for silence_temp"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'silence_temp');

-- UPDATE: Authenticated users can update temp assets
CREATE POLICY "Authenticated Update for silence_temp"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'silence_temp')
WITH CHECK (bucket_id = 'silence_temp');

-- DELETE: Authenticated users can delete temp assets
CREATE POLICY "Authenticated Delete for silence_temp"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'silence_temp');
