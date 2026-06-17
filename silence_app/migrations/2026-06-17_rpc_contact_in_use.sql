-- ============================================================================
-- 2026-06-17 — Server tier: RPC contact_in_use (block admin emails in Add-Member)
-- ============================================================================
--
-- WHY
--   The Add-Member wizard resolves an existing MEMBER by phone/email via
--   find_user_by_contact (migrations/2026-06-12_rpc_find_user_by_contact.sql).
--   That resolver DELIBERATELY excludes admins / library owners (their PII must
--   not be fetchable here). Side effect: if an admin's email/phone is typed, the
--   wizard sees "no existing user", proceeds, and only fails at the very end on
--   the users.email / users.phone UNIQUE constraint with a confusing generic
--   error. Requirement: a member must NOT be registerable on an admin's email/
--   phone, and the admin should be told upfront that the contact is taken.
--
-- WHAT
--   A boolean SECURITY DEFINER probe: for an authenticated LIBRARY OWNER only,
--   returns TRUE when the given phone OR email already belongs to an
--   ADMIN / library-owner account. It returns NO PII — just true/false — so it
--   does not reopen the admin-profile exposure that find_user_by_contact closed.
--   (Existing MEMBERS are intentionally NOT flagged here: those are handled by
--   find_user_by_contact, which autofills them.)
--
-- SAFETY
--   * SECURITY DEFINER + pinned search_path.
--   * Authorization enforced inside: caller must be authenticated AND own >= 1
--     library, else raises 42501.
--   * Exact match only. Returns boolean only.
--   * EXECUTE granted only to `authenticated`; revoked from PUBLIC (anon).
--
-- ADDITIVE & SAFE: nothing else depends on it; applying it changes no other
--   behavior. The client calls it best-effort (wrapped in try/catch), so the
--   app still works if this migration has not been applied yet.
--
-- ROLLBACK: DROP FUNCTION public.contact_in_use(text, text);
-- ============================================================================

CREATE OR REPLACE FUNCTION public.contact_in_use(
    p_phone text DEFAULT NULL,
    p_email text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_phone text := nullif(btrim(coalesce(p_phone, '')), '');
    v_email text := lower(nullif(btrim(coalesce(p_email, '')), ''));
BEGIN
    IF auth.uid() IS NULL
       OR NOT EXISTS (SELECT 1 FROM public.libraries WHERE owner_id = auth.uid()) THEN
        RAISE EXCEPTION 'not authorized to look up contacts' USING errcode = '42501';
    END IF;

    IF v_phone IS NULL AND v_email IS NULL THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM public.users u
        WHERE (
                (v_phone IS NOT NULL AND u.phone = v_phone)
             OR (v_email IS NOT NULL AND lower(u.email) = v_email)
              )
          -- only flag ADMIN / library-owner accounts (members are autofilled
          -- by find_user_by_contact instead)
          AND (
                u.role = 'admin'
             OR EXISTS (SELECT 1 FROM public.libraries l WHERE l.owner_id = u.id)
              )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.contact_in_use(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.contact_in_use(text, text) TO authenticated;
