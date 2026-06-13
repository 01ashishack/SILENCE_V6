-- ============================================================================
-- 2026-06-12 — Storage buckets + policies (FROM-SCRATCH bring-up)
-- ============================================================================
--
-- WHY
--   Storage was wiped. The app uploads to two buckets:
--     • silence_assets  (PUBLIC)  — profile photos, library logos/covers,
--                                   expense proofs, help-support attachments.
--                                   Served via getPublicUrl().
--     • silence_private (PRIVATE) — member ID documents. Served via
--                                   createSignedUrl() (short-lived signed links).
--   Without the buckets + policies, every image upload fails.
--
-- WHAT THIS IS
--   A FUNCTIONAL BASELINE so the app works end-to-end: any AUTHENTICATED user can
--   read/write the buckets (public read on silence_assets). It is intentionally
--   NOT yet owner/path-scoped — that hardening is audit P10-01/02/03 and belongs
--   to the storage step of the server-tier work (see SECURITY_RLS_ANALYSIS.md).
--   For a clean-slate functional + UX test this is the right baseline.
--
-- APPLY: run once in the Supabase SQL editor (after supabase_schema.sql).
-- ============================================================================

-- 1. Buckets ----------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('silence_assets', 'silence_assets', true)
on conflict (id) do update set public = excluded.public;

insert into storage.buckets (id, name, public)
values ('silence_private', 'silence_private', false)
on conflict (id) do update set public = excluded.public;

-- 2. silence_assets (PUBLIC): public read; authenticated write/update/delete --
drop policy if exists "silence_assets read"   on storage.objects;
drop policy if exists "silence_assets insert" on storage.objects;
drop policy if exists "silence_assets update" on storage.objects;
drop policy if exists "silence_assets delete" on storage.objects;

create policy "silence_assets read" on storage.objects
  for select using (bucket_id = 'silence_assets');
create policy "silence_assets insert" on storage.objects
  for insert to authenticated with check (bucket_id = 'silence_assets');
create policy "silence_assets update" on storage.objects
  for update to authenticated using (bucket_id = 'silence_assets') with check (bucket_id = 'silence_assets');
create policy "silence_assets delete" on storage.objects
  for delete to authenticated using (bucket_id = 'silence_assets');

-- 3. silence_private (PRIVATE): authenticated read (for signed URLs)/write -----
drop policy if exists "silence_private read"   on storage.objects;
drop policy if exists "silence_private insert" on storage.objects;
drop policy if exists "silence_private update" on storage.objects;
drop policy if exists "silence_private delete" on storage.objects;

create policy "silence_private read" on storage.objects
  for select to authenticated using (bucket_id = 'silence_private');
create policy "silence_private insert" on storage.objects
  for insert to authenticated with check (bucket_id = 'silence_private');
create policy "silence_private update" on storage.objects
  for update to authenticated using (bucket_id = 'silence_private') with check (bucket_id = 'silence_private');
create policy "silence_private delete" on storage.objects
  for delete to authenticated using (bucket_id = 'silence_private');
