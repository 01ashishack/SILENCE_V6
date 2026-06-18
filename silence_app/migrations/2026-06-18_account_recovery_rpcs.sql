-- ============================================================================
-- 2026-06-18 — Account-recovery owner RPCs + purge (P14-02)
-- ============================================================================
--
-- These run server-side (SECURITY DEFINER) because the owner console must
-- read/update ARBITRARY users and the purge must delete across tenants — both
-- of which normal RLS forbids.
--
-- ⚠️ SET THE APP-OWNER UID: replace the placeholder uid below with YOUR app-owner
--    account id (same value as SupabaseConfig.appOwnerUserId in the app).
--
-- ⛔ PURGE IS DESTRUCTIVE & IRREVERSIBLE. Review the delete list against your
--    live FK constraints and TEST on a throwaway account before scheduling the
--    cron (Edge Function process-account-deletions).
-- ============================================================================

-- 1) List pending recovery requests (owner console reads this) ---------------
CREATE OR REPLACE FUNCTION public.owner_list_recovery_requests()
RETURNS TABLE (
    id uuid, full_name text, email text, phone text, role text,
    deletion_scheduled_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() <> '1ce8bdfb-8364-4eef-91e1-aa70ab84edc1'::uuid THEN
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

-- 2) Approve / deny a recovery request --------------------------------------
CREATE OR REPLACE FUNCTION public.owner_decide_recovery(p_user_id uuid, p_approve boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() <> '1ce8bdfb-8364-4eef-91e1-aa70ab84edc1'::uuid THEN
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

-- 3) Hard-delete all DB data for a user (called by the purge Edge Function) --
--    Storage objects + the auth user are deleted by the Edge Function (SQL
--    cannot). Deletes child rows first, then libraries (cascades their layout),
--    then the user. ⚠️ Verify this matches your FK set before enabling.
CREATE OR REPLACE FUNCTION public.purge_account(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    -- member-side activity
    DELETE FROM public.attendance            WHERE member_id = p_user_id;
    DELETE FROM public.payments              WHERE member_id = p_user_id;
    DELETE FROM public.seat_change_requests  WHERE member_id = p_user_id;
    DELETE FROM public.hold_requests         WHERE member_id = p_user_id;
    DELETE FROM public.join_requests         WHERE member_id = p_user_id;
    DELETE FROM public.reviews               WHERE member_id = p_user_id;
    DELETE FROM public.badges                WHERE member_id = p_user_id;
    DELETE FROM public.referrals             WHERE referrer_id = p_user_id OR referred_id = p_user_id;
    DELETE FROM public.queries               WHERE member_id = p_user_id;
    DELETE FROM public.notifications         WHERE user_id   = p_user_id;
    DELETE FROM public.device_tokens         WHERE user_id   = p_user_id;
    DELETE FROM public.transfers             WHERE member_id = p_user_id;
    -- best-effort on optional/analytics tables (ignore if absent)
    BEGIN DELETE FROM public.streaks            WHERE member_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
    BEGIN DELETE FROM public.member_daily_stats WHERE member_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
    -- free any seats this member occupies (in other owners' libraries)
    UPDATE public.seats SET status = 'vacant', occupied_by_member_id = NULL
        WHERE occupied_by_member_id = p_user_id;
    DELETE FROM public.memberships           WHERE member_id = p_user_id;
    -- admin-side
    BEGIN DELETE FROM public.settings    WHERE admin_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
    DELETE FROM public.announcements         WHERE admin_id = p_user_id;
    DELETE FROM public.audit_log             WHERE admin_id = p_user_id;
    -- owned libraries (cascades floors/sections/seats/shifts + their memberships)
    DELETE FROM public.libraries             WHERE owner_id = p_user_id;
    -- finally the profile row
    DELETE FROM public.users                 WHERE id = p_user_id;
END;
$$;
REVOKE ALL ON FUNCTION public.purge_account(uuid) FROM PUBLIC;
-- Only the service role (the cron Edge Function) may purge.
GRANT EXECUTE ON FUNCTION public.purge_account(uuid) TO service_role;
