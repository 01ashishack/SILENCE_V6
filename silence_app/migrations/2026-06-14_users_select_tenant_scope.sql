-- ============================================================================
-- 2026-06-14 — Tenant-scope the broad users SELECT (audit P10-04)
-- ============================================================================
--
-- WHY
--   The policy "Admins can view all users (for member lists)" let ANY library
--   owner SELECT the ENTIRE users table — every user's name, phone, email,
--   address, DOB, photo (the single largest PII exposure, audit P10-04, a
--   reportable DPDP breach). It was load-bearing because the Add-Member wizard
--   looked up an existing account by phone/email ACROSS ALL libraries — it had to
--   read users who are not yet members of the caller's library.
--
-- PRECONDITION (do NOT apply this before both are true):
--   1. migrations/2026-06-12_rpc_find_user_by_contact.sql is applied (the
--      owner-only resolver that replaces the cross-library lookup), AND
--   2. the client is wired to call it — the 3 add-member lookup sites now use
--      supabase.rpc('find_user_by_contact', ...) instead of users.select:
--        • add_member_step1.dart _lookupUserByEmail / _lookupUserByPhone
--        • add_member_wizard.dart _finalizeRegistration
--      and that flow is VERIFIED on a device (existing-account autofill + the
--      active-membership dup-guard still work).
--   Applying this before the wiring is verified WILL break existing-account
--   detection in Add-Member.
--
-- WHAT
--   Replace the table-wide owner SELECT with a membership-scoped one: an owner
--   may read only users who are members of a library they own (same scoping the
--   UPDATE policy "Owner can update their library members" already uses), PLUS
--   users who have a PENDING JOIN REQUEST at one of their libraries (those users
--   are not members yet, but the Requests tab must show their name/phone/photo
--   via the join_requests → member_id(...) embed). The self-SELECT policy
--   ("Users can view own profile") is unchanged, so every user still reads their
--   own row. The cross-library lookup now goes exclusively through the SECURITY
--   DEFINER RPC, which returns at most one minimal row.
--
-- VERIFY AFTER APPLYING (VC):
--   • Admin member lists + member detail still load (members of owned libraries).
--   • The Requests tab still shows each pending join request's member name/phone
--     /photo (the non-member-yet case this policy explicitly covers).
--   • Add-Member existing-account autofill still works (via the RPC).
--   • A library owner can NO LONGER select a user who is neither a member nor a
--     pending applicant of any of their libraries (other than via the RPC).
--
-- ROLLBACK:
--   DROP POLICY "Admins can view library members" ON public.users;
--   CREATE POLICY "Admins can view all users (for member lists)" ON public.users
--       FOR SELECT USING (EXISTS (SELECT 1 FROM libraries WHERE owner_id = auth.uid()));
-- ============================================================================

DROP POLICY IF EXISTS "Admins can view all users (for member lists)" ON public.users;
DROP POLICY IF EXISTS "Admins can view library members" ON public.users;

CREATE POLICY "Admins can view library members" ON public.users
    FOR SELECT
    USING (
        -- (a) users who are members of a library the caller owns
        EXISTS (
            SELECT 1 FROM memberships m
            JOIN libraries l ON l.id = m.library_id
            WHERE m.member_id = users.id AND l.owner_id = auth.uid()
        )
        -- (b) users with a PENDING join request at a library the caller owns
        --     (not members yet — the Requests tab reads them via member_id embed)
        OR EXISTS (
            SELECT 1 FROM join_requests jr
            JOIN libraries l ON l.id = jr.library_id
            WHERE jr.member_id = users.id
              AND jr.status = 'pending'
              AND l.owner_id = auth.uid()
        )
    );
