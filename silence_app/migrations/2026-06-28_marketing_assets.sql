-- ============================================================================
-- 2026-06-28 — Marketing posters asset library (manual upload, no AI)
-- ============================================================================
-- The app owner manually creates posters (Canva/AI/designer) and uploads the
-- finished images. Library owners (admins) browse them category-wise and
-- download. Two visibility scopes:
--   • general        → shown to ALL library owners
--   • personalised  → shown ONLY to the owner of `target_library_id`
--
-- Images live in a PUBLIC storage bucket `marketing`; this table is the catalog
-- (the RLS here controls what each owner can DISCOVER). Writes are app-owner only.
--
-- Idempotent. Apply in the Supabase SQL editor, then fold into supabase_schema.sql.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.marketing_assets (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scope             TEXT NOT NULL CHECK (scope IN ('general', 'personalised')),
    category          TEXT NOT NULL CHECK (category IN
                        ('wall_poster', 'pamphlet', 'banner', 'social', 'other')),
    target_library_id UUID REFERENCES public.libraries(id) ON DELETE CASCADE,
    title             TEXT,
    image_path        TEXT NOT NULL,            -- object path inside the `marketing` bucket
    sort_order        INT DEFAULT 0,            -- optional manual ordering (lower = first)
    active            BOOLEAN DEFAULT true,
    created_by        UUID REFERENCES public.users(id),
    created_at        TIMESTAMPTZ DEFAULT now(),
    -- a personalised asset MUST target a library; a general one MUST NOT
    CONSTRAINT marketing_scope_target_chk CHECK (
        (scope = 'general' AND target_library_id IS NULL)
        OR (scope = 'personalised' AND target_library_id IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_marketing_scope    ON public.marketing_assets(scope, category);
CREATE INDEX IF NOT EXISTS idx_marketing_target   ON public.marketing_assets(target_library_id);

ALTER TABLE public.marketing_assets ENABLE ROW LEVEL SECURITY;

-- Read: general (active) to everyone signed in; personalised only to the owner
-- of the target library; app-owner sees everything.
DROP POLICY IF EXISTS "marketing_select_scoped" ON public.marketing_assets;
CREATE POLICY "marketing_select_scoped" ON public.marketing_assets
    FOR SELECT USING (
        (active AND scope = 'general')
        OR (active AND scope = 'personalised' AND target_library_id IN (
              SELECT id FROM public.libraries WHERE owner_id = auth.uid()))
        OR EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.is_app_owner)
    );

-- Only the app owner can create/edit/remove catalog rows.
DROP POLICY IF EXISTS "marketing_write_app_owner" ON public.marketing_assets;
CREATE POLICY "marketing_write_app_owner" ON public.marketing_assets
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.is_app_owner)
    ) WITH CHECK (
        EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.is_app_owner)
    );

-- ─────────────────────────────────────────────────────────────────────────
-- Storage bucket `marketing` (PUBLIC) + object policies
-- ─────────────────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('marketing', 'marketing', true)
ON CONFLICT (id) DO NOTHING;

-- Public read (so getPublicUrl + download work for everyone).
DROP POLICY IF EXISTS "marketing_obj_public_read" ON storage.objects;
CREATE POLICY "marketing_obj_public_read" ON storage.objects
    FOR SELECT USING (bucket_id = 'marketing');

-- Writes restricted to the app owner (for a future in-app upload screen;
-- manual dashboard uploads use the service role and bypass this).
DROP POLICY IF EXISTS "marketing_obj_app_owner_write" ON storage.objects;
CREATE POLICY "marketing_obj_app_owner_write" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'marketing'
        AND EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.is_app_owner)
    );
DROP POLICY IF EXISTS "marketing_obj_app_owner_modify" ON storage.objects;
CREATE POLICY "marketing_obj_app_owner_modify" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'marketing'
        AND EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.is_app_owner)
    );
DROP POLICY IF EXISTS "marketing_obj_app_owner_delete" ON storage.objects;
CREATE POLICY "marketing_obj_app_owner_delete" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'marketing'
        AND EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.is_app_owner)
    );

-- ============================================================================
-- HOW TO ADD A POSTER (manual, via Supabase dashboard):
--   1. Storage → bucket `marketing` → upload your image into a folder named by
--      category, e.g.  general/wall_poster/diwali_offer.jpg
--      or for a specific library:  personalised/banner/<anything>.jpg
--   2. Table editor → marketing_assets → Insert row:
--        scope     = 'general'  (everyone)   OR  'personalised'
--        category  = 'wall_poster' | 'pamphlet' | 'banner' | 'social' | 'other'
--        image_path= the exact path you uploaded to (e.g. general/wall_poster/diwali_offer.jpg)
--        title     = optional label (e.g. "Diwali Offer")
--        target_library_id = (only for personalised) the library's id from the
--                            libraries table; leave NULL for general.
--   3. Save. It appears instantly in that library owner's Marketing & Posters.
-- ============================================================================
