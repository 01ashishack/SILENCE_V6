-- ============================================================================
-- 2026-06-12 — Server tier (RC-1), RPC #1: find_user_by_contact
-- ============================================================================
--
-- WHY
--   The Add-Member wizard detects an existing account by reading the `users`
--   table by phone/email across ALL libraries
--   (add_member_step1.dart:_lookupUserByEmail/_lookupUserByPhone,
--   add_member_wizard.dart:_finalizeRegistration). That works today only because
--   of the broad "Admins can view all users (for member lists)" SELECT policy —
--   the same policy that lets ANY library owner read the ENTIRE users table
--   (audit P10-04, the largest PII exposure). We cannot tenant-scope that SELECT
--   until this cross-library lookup has a narrow, owner-only path. This RPC is
--   that path — the first brick of the server tier (root cause RC-1).
--
-- WHAT  (UPDATED 2026-06-14: excludes admins/owners from results)
--   A SECURITY DEFINER function that, for an authenticated LIBRARY OWNER only,
--   returns the single existing MEMBER matching an exact phone OR email (exactly
--   the fields the wizard autofills). Admins / library owners are NOT returned —
--   this lookup is only for adding members, so an admin's profile must not be
--   fetchable here. Call it from the client as:
--       supabase.rpc('find_user_by_contact',
--                    params: {'p_phone': '...', 'p_email': '...'})
--   It returns a list of 0 or 1 row.
--
-- SAFETY
--   * SECURITY DEFINER + pinned search_path (no search_path hijacking).
--   * Authorization enforced INSIDE the function: the caller must be
--     authenticated AND own >= 1 library, else it raises (SQLSTATE 42501).
--   * Exact match only (no LIKE) + LIMIT 1 — a resolver, not a browse/enumerate
--     endpoint.
--   * EXECUTE granted only to `authenticated`; revoked from PUBLIC (anon).
--
-- ADDITIVE & SAFE TO APPLY NOW: nothing calls it yet, so applying it changes no
--   app behavior. Wiring the client to use it is a SEPARATE, testable step;
--   only after that is verified should the broad users SELECT be tenant-scoped
--   (a later migration).
--
-- ROLLBACK: DROP FUNCTION public.find_user_by_contact(text, text);
-- ============================================================================

CREATE OR REPLACE FUNCTION public.find_user_by_contact(
    p_phone text DEFAULT NULL,
    p_email text DEFAULT NULL
)
RETURNS TABLE (
    id uuid,
    full_name text,
    phone text,
    email text,
    gender text,
    date_of_birth date,
    address text,
    exam_category text,
    photo_url text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_phone text := nullif(btrim(coalesce(p_phone, '')), '');
    v_email text := lower(nullif(btrim(coalesce(p_email, '')), ''));
BEGIN
    -- Only an authenticated library owner may resolve an existing account.
    IF auth.uid() IS NULL
       OR NOT EXISTS (SELECT 1 FROM public.libraries WHERE owner_id = auth.uid()) THEN
        RAISE EXCEPTION 'not authorized to look up users' USING errcode = '42501';
    END IF;

    -- Ignore empty probes (need at least one contact value).
    IF v_phone IS NULL AND v_email IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT u.id, u.full_name, u.phone, u.email, u.gender, u.date_of_birth,
           u.address, u.exam_category, u.photo_url
    FROM public.users u
    WHERE (
            (v_phone IS NOT NULL AND u.phone = v_phone)
         OR (v_email IS NOT NULL AND lower(u.email) = v_email)
          )
      -- Never resolve admins / library owners: this lookup is only for adding
      -- MEMBERS, so an admin's profile must not be fetchable here.
      AND u.role IS DISTINCT FROM 'admin'
      AND NOT EXISTS (SELECT 1 FROM public.libraries l WHERE l.owner_id = u.id)
    ORDER BY u.created_at DESC
    LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.find_user_by_contact(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.find_user_by_contact(text, text) TO authenticated;
