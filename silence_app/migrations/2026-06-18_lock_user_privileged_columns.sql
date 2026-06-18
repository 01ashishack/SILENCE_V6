-- ============================================================================
-- 2026-06-18 — Lock privileged users columns (P6-02 role + P6-06 subscription
--              + self-asserted verification flags)
-- ============================================================================
--
-- Consolidates the role lock (was 2026-06-18_role_change_rpc.sql) and adds
-- subscription + verification-flag locks into ONE guard trigger + ONE flag GUC
-- (app.allow_privileged_update). After this, a normal client can no longer
-- directly change any of:
--     role, subscription_plan/status/expiry, phone_verified, email_verified
-- The only sanctioned writers set the GUC inside a SECURITY DEFINER RPC:
--     * change_my_role()  — role switch (7-day window + data wipe, see below)
--     * start_my_trial()  — admin's one-time 14-day starter trial on launch
-- (Razorpay billing will later update subscription via service role / webhook,
--  which bypasses this trigger.)
--
-- Verification flags currently have NO client writer (OTP is disabled), so this
-- simply prevents self-asserted "verified" until a real OTP flow sets them
-- through a future RPC.
--
-- Idempotent: safe to re-run. Replaces the standalone guard_role_change trigger.
-- ============================================================================

-- Retire the older role-only guard (superseded by the combined one below).
DROP TRIGGER IF EXISTS trg_guard_role_change ON public.users;
DROP FUNCTION IF EXISTS public.guard_role_change();

-- 1) Combined guard trigger --------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_user_privileged_columns()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF current_setting('app.allow_privileged_update', true) IS DISTINCT FROM 'on' THEN
        -- role: allow INSERT-time set + null->role onboarding + same-value upserts;
        -- block only a real flip between two non-null roles.
        IF OLD.role IS NOT NULL AND NEW.role IS DISTINCT FROM OLD.role THEN
            RAISE EXCEPTION 'Role can only be changed through change_my_role()'
                USING errcode = '42501';
        END IF;
        -- subscription: block any client change (trial/billing only).
        IF NEW.subscription_plan   IS DISTINCT FROM OLD.subscription_plan
        OR NEW.subscription_status IS DISTINCT FROM OLD.subscription_status
        OR NEW.subscription_expiry IS DISTINCT FROM OLD.subscription_expiry THEN
            RAISE EXCEPTION 'Subscription can only be changed by the trial/billing flow'
                USING errcode = '42501';
        END IF;
        -- verification flags: only a real OTP flow may set these.
        IF NEW.phone_verified IS DISTINCT FROM OLD.phone_verified
        OR NEW.email_verified IS DISTINCT FROM OLD.email_verified THEN
            RAISE EXCEPTION 'Verification flags are set only after OTP verification'
                USING errcode = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_user_privileged_columns ON public.users;
CREATE TRIGGER trg_guard_user_privileged_columns
    BEFORE UPDATE OF role, subscription_plan, subscription_status,
                     subscription_expiry, phone_verified, email_verified
    ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION public.guard_user_privileged_columns();

-- 2) start_my_trial(): new admin's one-time 30-day FREE window --------------
--    Sets plan='free' (displays as "Free") with a 30-day expiry marker — NOT a
--    paid 'starter' grant (which the app maps to "Pro"). During beta everything
--    is unlocked regardless; the window is shown on the subscription screen.
CREATE OR REPLACE FUNCTION public.start_my_trial()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid  uuid := auth.uid();
    v_role text;
    v_plan text;
    v_exp  timestamptz;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not signed in' USING errcode = '42501';
    END IF;
    SELECT role, subscription_plan, subscription_expiry
      INTO v_role, v_plan, v_exp
      FROM public.users WHERE id = v_uid;
    IF v_role IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'Only admins have a subscription' USING errcode = '42501';
    END IF;
    -- Grant once: skip if a free window was already set or any plan exists.
    IF v_exp IS NOT NULL OR v_plan IS NOT NULL THEN
        RETURN;
    END IF;
    PERFORM set_config('app.allow_privileged_update', 'on', true);
    UPDATE public.users SET
        subscription_plan   = 'free',
        subscription_status = 'active',
        subscription_expiry = now() + interval '30 days',
        updated_at          = now()
      WHERE id = v_uid;
END;
$$;
REVOKE ALL ON FUNCTION public.start_my_trial() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_my_trial() TO authenticated;

-- 3) change_my_role(): re-create using the unified GUC -----------------------
--    (7-day window + full data wipe + fresh account; see prior migration's
--    notes. Identity row kept; created_at preserved so the 7-day clock does
--    not reset on role change.)
CREATE OR REPLACE FUNCTION public.change_my_role(p_new_role text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid     uuid := auth.uid();
    v_role    text;
    v_created timestamptz;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not signed in' USING errcode = '42501';
    END IF;
    IF p_new_role NOT IN ('admin', 'member') THEN
        RAISE EXCEPTION 'Invalid role: %', p_new_role USING errcode = '22023';
    END IF;

    SELECT role, created_at INTO v_role, v_created
      FROM public.users WHERE id = v_uid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User profile not found' USING errcode = 'P0002';
    END IF;
    IF v_role = p_new_role THEN
        RAISE EXCEPTION 'You are already a %', p_new_role USING errcode = '22023';
    END IF;
    IF v_created IS NULL OR v_created < now() - interval '7 days' THEN
        RAISE EXCEPTION 'Role can only be changed within 7 days of signup'
            USING errcode = 'P0001';
    END IF;

    DELETE FROM public.attendance            WHERE member_id  = v_uid;
    DELETE FROM public.payments              WHERE member_id  = v_uid;
    DELETE FROM public.seat_change_requests  WHERE member_id  = v_uid;
    DELETE FROM public.hold_requests         WHERE member_id  = v_uid;
    DELETE FROM public.join_requests         WHERE member_id  = v_uid;
    DELETE FROM public.reviews               WHERE member_id  = v_uid;
    DELETE FROM public.badges                WHERE member_id  = v_uid;
    DELETE FROM public.referrals             WHERE referrer_member_id = v_uid OR referred_member_id = v_uid;
    DELETE FROM public.queries               WHERE member_id  = v_uid;
    DELETE FROM public.notifications         WHERE user_id    = v_uid;
    DELETE FROM public.transfers             WHERE member_id  = v_uid;
    BEGIN DELETE FROM public.streaks            WHERE member_id = v_uid; EXCEPTION WHEN undefined_table THEN NULL; END;
    BEGIN DELETE FROM public.member_daily_stats WHERE member_id = v_uid; EXCEPTION WHEN undefined_table THEN NULL; END;
    UPDATE public.seats SET status = 'vacant', occupied_by_member_id = NULL
        WHERE occupied_by_member_id = v_uid;
    DELETE FROM public.memberships           WHERE member_id  = v_uid;
    BEGIN DELETE FROM public.settings    WHERE admin_id = v_uid; EXCEPTION WHEN undefined_table THEN NULL; END;
    DELETE FROM public.announcements         WHERE admin_id   = v_uid;
    DELETE FROM public.audit_log             WHERE admin_id   = v_uid;
    DELETE FROM public.libraries             WHERE owner_id   = v_uid;

    PERFORM set_config('app.allow_privileged_update', 'on', true);
    UPDATE public.users SET
        role                     = p_new_role,
        exam_category            = NULL,
        subscription_plan        = NULL,
        subscription_status      = 'active',
        subscription_expiry      = NULL,
        id_proof_url             = NULL,
        id_proof_2_url           = NULL,
        id_type                  = NULL,
        scheduled_for_deletion   = false,
        deletion_scheduled_at    = NULL,
        deletion_recovery_status = 'none',
        updated_at               = now()
      WHERE id = v_uid;
END;
$$;
REVOKE ALL ON FUNCTION public.change_my_role(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.change_my_role(text) TO authenticated;

-- ============================================================================
-- VERIFY (signed in on a device):
--   select public.start_my_trial();                              -- admin: sets starter/active/+14d once
--   update public.users set subscription_status='active', subscription_plan='pro'
--     where id = auth.uid();                                     -- must FAIL 42501
--   update public.users set phone_verified=true where id=auth.uid(); -- must FAIL 42501
--   select public.change_my_role('admin');                       -- still works within 7 days
-- ROLLBACK (restores the open behaviour):
--   drop trigger if exists trg_guard_user_privileged_columns on public.users;
--   drop function if exists public.guard_user_privileged_columns();
--   drop function if exists public.start_my_trial();
-- ============================================================================
