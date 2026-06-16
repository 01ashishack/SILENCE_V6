-- ============================================================================
-- 2026-06-14 — Storage: owner-scope the silence_private bucket (audit P10-01/02/03)
-- ============================================================================
--
-- WHY
--   The functional baseline (migrations/2026-06-12_storage_buckets_setup.sql)
--   lets ANY authenticated user read/write the silence_private bucket — i.e. any
--   logged-in user can fetch any member's ID document or payment proof. That is
--   the audit's P10-01/02/03 exposure and a reportable DPDP breach (identity
--   documents). This migration scopes silence_private to the owner of each
--   object's path.
--
-- ⛔ DO NOT APPLY BLIND — storage policies are the easiest to get subtly wrong,
--   and a wrong predicate SILENTLY breaks signed-URL reads / uploads (no error,
--   just blank images). Apply on a test project / off-peak and run the VERIFY
--   block below on a device BEFORE relying on it. Rollback at the bottom restores
--   the functional baseline.
--
-- PATH FAMILIES in silence_private (from the upload sites in lib/):
--   library_members/<library_id>/<sub>/<file>  admin uploads a member's ID doc
--                                               (add_member_wizard.dart:316)
--   member_profiles/<user_id>/<file>            member uploads their OWN ID doc
--                                               (member_profile_edit.dart:363)
--   payment_proofs/<user_id>/<file>             member uploads a payment proof
--                                               (join_flow_screen.dart:526)
--   admin_profiles/<user_id>/<file>             admin's own photo. NOTE: as of
--                                               2026-06-16 NEW admin photos go to
--                                               the PUBLIC silence_assets bucket
--                                               (shown on the public library
--                                               profile). The self-scoped
--                                               admin_profiles clauses below stay
--                                               only so a LEGACY admin photo left
--                                               in silence_private is still
--                                               readable by its owner.
--   storage.foldername(name) → text[]; [1] = family, [2] = owning id.
--
-- READ (signed URLs / createSignedUrl):
--   • self — my own uploads (member_profiles/payment_proofs/admin_profiles where
--     [2] = auth.uid()).
--   • library owner — a member ID doc I uploaded (library_members where I own [2]),
--     AND a member's self-uploaded ID / payment proof (member_profiles/
--     payment_proofs where [2] is a member of one of my libraries). member_detail
--     resolves whichever path the stored id_proof_url points to, so the owner
--     must be able to read BOTH families.
--
-- WRITE (insert/update/delete):
--   • self writes their own-id folders (member_profiles/payment_proofs/admin_profiles).
--   • library owner writes library_members/<their library id>.
--
-- NOTE: silence_assets (PUBLIC) is intentionally left public-read (profile photos,
--   logos). Moving any genuine PII off the public bucket is a separate task
--   (audit R-01 / P10-02) and needs an object migration, not just a policy.
-- ============================================================================

drop policy if exists "silence_private read"   on storage.objects;
drop policy if exists "silence_private insert" on storage.objects;
drop policy if exists "silence_private update" on storage.objects;
drop policy if exists "silence_private delete" on storage.objects;

-- READ ----------------------------------------------------------------------
create policy "silence_private read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'silence_private' AND (
      -- self: my own uploads
      (
        (storage.foldername(name))[1] in ('payment_proofs', 'member_profiles', 'admin_profiles')
        and (storage.foldername(name))[2] = auth.uid()::text
      )
      or
      -- library owner: a member ID doc I uploaded for one of my libraries
      (
        (storage.foldername(name))[1] = 'library_members'
        and exists (
          select 1 from public.libraries l
          where l.id::text = (storage.foldername(name))[2] and l.owner_id = auth.uid()
        )
      )
      or
      -- library owner: a member's self-uploaded ID / payment proof, where that
      -- member belongs to one of my libraries
      (
        (storage.foldername(name))[1] in ('member_profiles', 'payment_proofs')
        and exists (
          select 1 from public.memberships m
          join public.libraries l on l.id = m.library_id
          where m.member_id::text = (storage.foldername(name))[2] and l.owner_id = auth.uid()
        )
      )
    )
  );

-- WRITE: insert / update / delete share one ownership predicate ---------------
create policy "silence_private insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'silence_private' AND (
      (
        (storage.foldername(name))[1] in ('payment_proofs', 'member_profiles', 'admin_profiles')
        and (storage.foldername(name))[2] = auth.uid()::text
      )
      or
      (
        (storage.foldername(name))[1] = 'library_members'
        and exists (
          select 1 from public.libraries l
          where l.id::text = (storage.foldername(name))[2] and l.owner_id = auth.uid()
        )
      )
    )
  );

create policy "silence_private update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'silence_private' AND (
      (
        (storage.foldername(name))[1] in ('payment_proofs', 'member_profiles', 'admin_profiles')
        and (storage.foldername(name))[2] = auth.uid()::text
      )
      or
      (
        (storage.foldername(name))[1] = 'library_members'
        and exists (
          select 1 from public.libraries l
          where l.id::text = (storage.foldername(name))[2] and l.owner_id = auth.uid()
        )
      )
    )
  )
  with check (
    bucket_id = 'silence_private' AND (
      (
        (storage.foldername(name))[1] in ('payment_proofs', 'member_profiles', 'admin_profiles')
        and (storage.foldername(name))[2] = auth.uid()::text
      )
      or
      (
        (storage.foldername(name))[1] = 'library_members'
        and exists (
          select 1 from public.libraries l
          where l.id::text = (storage.foldername(name))[2] and l.owner_id = auth.uid()
        )
      )
    )
  );

create policy "silence_private delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'silence_private' AND (
      (
        (storage.foldername(name))[1] in ('payment_proofs', 'member_profiles', 'admin_profiles')
        and (storage.foldername(name))[2] = auth.uid()::text
      )
      or
      (
        (storage.foldername(name))[1] = 'library_members'
        and exists (
          select 1 from public.libraries l
          where l.id::text = (storage.foldername(name))[2] and l.owner_id = auth.uid()
        )
      )
    )
  );

-- ============================================================================
-- VERIFY ON A DEVICE (each must still work; if any fails, ROLLBACK below):
--   1. Add-member as an admin: upload a member ID doc → succeeds (library_members write).
--   2. Open that member in Reservations → member detail: the ID doc image loads
--      (owner read of library_members + member_profiles).
--   3. As that member: upload own ID in profile edit → succeeds (member_profiles write);
--      it displays back (self read).
--   4. Member join flow: upload a payment proof → succeeds (payment_proofs write) and
--      displays back (self read); the admin can view it (owner read of payment_proofs).
--   5. NEGATIVE: a member can no longer fetch another member's doc by guessing a path.
--
-- ROLLBACK (restore the functional any-authenticated baseline):
--   drop policy if exists "silence_private read"   on storage.objects;
--   drop policy if exists "silence_private insert" on storage.objects;
--   drop policy if exists "silence_private update" on storage.objects;
--   drop policy if exists "silence_private delete" on storage.objects;
--   create policy "silence_private read"   on storage.objects for select to authenticated using (bucket_id = 'silence_private');
--   create policy "silence_private insert" on storage.objects for insert to authenticated with check (bucket_id = 'silence_private');
--   create policy "silence_private update" on storage.objects for update to authenticated using (bucket_id = 'silence_private') with check (bucket_id = 'silence_private');
--   create policy "silence_private delete" on storage.objects for delete to authenticated using (bucket_id = 'silence_private');
-- ============================================================================
