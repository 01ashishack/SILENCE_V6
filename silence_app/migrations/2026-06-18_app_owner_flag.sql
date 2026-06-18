-- ============================================================================
-- 2026-06-18 — App-owner flag (replaces the hardcoded owner uid)
-- ============================================================================
--
-- WHY
--   The recovery console / owner RPCs were gated to a hardcoded uid (a testing
--   account). Instead, designate the app owner with a DB flag you control.
--
-- SET YOUR OWNER ACCOUNT (run once, with YOUR real owner email):
--   UPDATE public.users SET is_app_owner = true WHERE email = 'you@example.com';
--   (You can flag more than one account if needed. Unflag with = false.)
--
-- APPLY: run this whole file once in the Supabase SQL editor (it also re-creates
--   the two owner RPCs to gate on the flag instead of a uid).
-- ============================================================================

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS is_app_owner BOOLEAN NOT NULL DEFAULT false;

-- Re-gate: list pending recovery requests (app owner only) -------------------
CREATE OR REPLACE FUNCTION public.owner_list_recovery_requests()
RETURNS TABLE (
    id uuid, full_name text, email text, phone text, role text,
    deletion_scheduled_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND is_app_owner = true) THEN
        RAISE EXCEPTION 'not authorized' USING errcode = '42501';
    END IF;
    RETURN QUERY
        SELECT u.id, u.full_name, u.email, u.phone, u.role, u.deletion_scheduled_at
        FROM public.users u
        WHERE u.scheduled_for_deletion = true
          AND u.deletion_recovery_status = 'requested'
        ORDER BY u.deletion_scheduled_at ASC NULLS LAST;
END;
$$;
REVOKE ALL ON FUNCTION public.owner_list_recovery_requests() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_list_recovery_requests() TO authenticated;

-- Re-gate: approve / deny a recovery request (app owner only) ----------------
CREATE OR REPLACE FUNCTION public.owner_decide_recovery(p_user_id uuid, p_approve boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND is_app_owner = true) THEN
        RAISE EXCEPTION 'not authorized' USING errcode = '42501';
    END IF;

    IF p_approve THEN
        UPDATE public.users
           SET scheduled_for_deletion = false,
               deletion_scheduled_at = NULL,
               deletion_recovery_status = 'approved'
         WHERE id = p_user_id;
        INSERT INTO public.notifications (user_id, title, body, data)
        VALUES (p_user_id, 'Account restored',
                'Your account recovery was approved — welcome back!',
                '{"type":"account_restored"}'::jsonb);
    ELSE
        UPDATE public.users
           SET deletion_recovery_status = 'denied'
         WHERE id = p_user_id;
        INSERT INTO public.notifications (user_id, title, body, data)
        VALUES (p_user_id, 'Recovery request declined',
                'Your account recovery request was not approved.',
                '{"type":"account_recovery_denied"}'::jsonb);
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.owner_decide_recovery(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_decide_recovery(uuid, boolean) TO authenticated;
