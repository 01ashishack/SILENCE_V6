-- ============================================================================
-- 2026-06-17 — Fix: admin cannot create a NEW member (Add-Member wizard)
-- ============================================================================
--
-- SYMPTOM
--   Completing the Add-Member wizard ("Confirm & Add Member") fails with
--   "Permission denied while creating the member profile." (the new
--   per-step diagnostic in add_member_wizard.dart). The blocked write is the
--   INSERT into public.users for the brand-new member.
--
-- ROOT CAUSE
--   RLS is enabled on public.users, but the open signup insert policy from the
--   canonical schema —
--       CREATE POLICY "Anyone can insert (signup)" ON users
--           FOR INSERT WITH CHECK (true);
--   — is NOT present on this database (dropped, never created, or replaced with
--   a self-only rule such as WITH CHECK (auth.uid() = id) during hardening).
--   With no permissive INSERT policy that an ADMIN satisfies, an admin creating
--   ANOTHER person's user row (member_id != auth.uid()) is rejected with
--   SQLSTATE 42501. (Self-signup still works because that row's id = auth.uid().)
--
--   This app has NO server tier (root cause RC-1): the admin inserts the
--   member's public.users row directly from the client during Add-Member. So
--   the DB MUST allow a library OWNER to insert a member row.
--
-- FIX (additive, non-destructive)
--   ADD a permissive, owner-scoped INSERT policy. Postgres OR-combines
--   PERMISSIVE policies, so this does NOT remove or weaken any existing
--   self-only signup policy you may have added — it only grants the extra path
--   "an authenticated library owner may insert a user row". It does NOT reopen
--   anonymous/forged inserts (the inserter must own at least one library).
--
-- APPLY: run this whole file once in the Supabase SQL editor.
-- VERIFY: re-run the Add-Member wizard end-to-end for a brand-NEW member (one
--         whose phone/email is not already in users) — it should complete with
--         "Member added successfully" (no "creating the member profile" error).
-- ============================================================================

DROP POLICY IF EXISTS "Owner can insert library members" ON users;
CREATE POLICY "Owner can insert library members" ON users
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM libraries
            WHERE owner_id = auth.uid()
        )
    );

-- ----------------------------------------------------------------------------
-- DIAGNOSTIC (optional) — run this BEFORE the fix to confirm the cause. It
-- lists every INSERT policy currently on public.users and its WITH CHECK
-- expression. If you do NOT see a policy whose qual is `true` (or one matching
-- the owner condition below), that confirms why the admin insert is rejected:
--
--   SELECT polname,
--          pg_get_expr(polwithcheck, polrelid) AS with_check
--   FROM   pg_policy
--   WHERE  polrelid = 'public.users'::regclass
--     AND  polcmd IN ('a', '*');   -- 'a' = INSERT, '*' = ALL
-- ----------------------------------------------------------------------------

-- ROLLBACK:
--   DROP POLICY IF EXISTS "Owner can insert library members" ON users;
-- ============================================================================
