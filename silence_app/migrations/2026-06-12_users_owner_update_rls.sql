-- ============================================================================
-- 2026-06-12 — Fix: admin cannot save a member's photo / ID documents / details
-- ============================================================================
--
-- SYMPTOM
--   In Reservations → Members, member cards and the member profile never showed
--   a photo, and "ID Documents" always read "No documents uploaded" — even right
--   after the admin uploaded them in the Add-Member wizard. Editing a member's
--   details from their profile also silently did nothing.
--
-- ROOT CAUSE
--   The `users` table had only a SELF update policy:
--       "Users can update own profile"  USING (auth.uid() = id)
--   When a library OWNER updates a MEMBER's row (to store photo_url /
--   id_proof_url / id_type / refreshed contact details), auth.uid() is the
--   owner — not the member — so the UPDATE matched 0 rows and was silently
--   dropped (no error raised, nothing saved). There was no owner/admin update
--   policy for member rows. (The INSERT that creates a new member succeeds via
--   "Anyone can insert (signup)", which is why the basic fields appear — only
--   the follow-up photo / ID writes were lost.)
--
-- FIX
--   Add an owner-scoped UPDATE policy on `users`, scoped through `memberships`:
--   an owner may update a user who holds a membership in one of the owner's
--   libraries. Additive, idempotent, owner-scoped — safe to run on the live DB.
--   No data change.
--
--   The app was also reordered so the Add-Member wizard creates the membership
--   BEFORE writing the member's photo / ID docs — that membership is the link
--   this policy checks, so the policy now applies to brand-new members too.
--
-- APPLY: run this whole file once in the Supabase SQL editor.
-- VERIFY: add a member with a photo + an ID proof, then open their profile —
--         the avatar and ID document(s) now render. Editing details from the
--         profile saves. (Existing members added before this fix won't backfill
--         a photo they never had; re-upload from the member's profile.)
-- ============================================================================

DROP POLICY IF EXISTS "Owner can update their library members" ON users;
CREATE POLICY "Owner can update their library members" ON users
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM memberships m
            JOIN libraries l ON l.id = m.library_id
            WHERE m.member_id = users.id AND l.owner_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM memberships m
            JOIN libraries l ON l.id = m.library_id
            WHERE m.member_id = users.id AND l.owner_id = auth.uid()
        )
    );

-- Note: the existing "Users can update own profile" policy is KEPT (members
-- still edit their own profile). Both update paths coexist — RLS policies for
-- the same command are OR'd, so each role keeps exactly the access it needs.
