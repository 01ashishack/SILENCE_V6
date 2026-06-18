-- ============================================================================
-- 2026-06-17 — device_tokens (FCM push: per-device token registry)
-- ============================================================================
--
-- WHY
--   FCM push needs each device's registration token. `users.fcm_token` only
--   holds one token per user (last device wins) — but a user can have phone +
--   web at once. This table holds one row PER DEVICE.
--
-- WHO WRITES / READS
--   • Client (authenticated user): upserts/reads/deletes ONLY their own rows
--     (RLS below). The app writes its token here on launch/login.
--   • Send-side Edge Function `send-push`: reads tokens with the SERVICE-ROLE
--     key (bypasses RLS) to know where to push, and prunes dead tokens.
--
-- NOTE: `token` is the PRIMARY KEY so the same device upserts in place. If a
--   device is re-used by a different user, the new user's upsert may be blocked
--   by RLS (the row still belongs to the old user) — acceptable for v1; the
--   Edge Function also prunes tokens FCM reports as UNREGISTERED.
--
-- APPLY: run once in the Supabase SQL editor.
-- ROLLBACK: DROP TABLE public.device_tokens;
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.device_tokens (
    token       text PRIMARY KEY,
    user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    platform    text,                       -- 'android' | 'ios' | 'web' | ...
    updated_at  timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON public.device_tokens(user_id);

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "own device tokens select" ON public.device_tokens;
CREATE POLICY "own device tokens select" ON public.device_tokens
    FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS "own device tokens insert" ON public.device_tokens;
CREATE POLICY "own device tokens insert" ON public.device_tokens
    FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "own device tokens update" ON public.device_tokens;
CREATE POLICY "own device tokens update" ON public.device_tokens
    FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "own device tokens delete" ON public.device_tokens;
CREATE POLICY "own device tokens delete" ON public.device_tokens
    FOR DELETE USING (user_id = auth.uid());