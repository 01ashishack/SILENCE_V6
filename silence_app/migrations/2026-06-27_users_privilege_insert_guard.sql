-- ============================================================================
-- 2026-06-27 — Close the remaining users-table privilege holes (Wave 0 finish)
-- ============================================================================
-- WHY (audit):
--   * The privileged-column guard (2026-06-18_lock_user_privileged_columns.sql)
--     fired only BEFORE UPDATE OF role/subscription_*/*_verified. Two gaps:
--       1. `is_app_owner` (recovery-console superuser flag) was NOT guarded at
--          all — a logged-in user could `UPDATE users SET is_app_owner = true`
--          on their OWN row (allowed by "Users can update own profile") and
--          unlock the owner Recovery Console. Escalation.
--       2. The `users` INSERT policy is `WITH CHECK (true)` (it must stay open
--          because admins insert manually-added member rows with a generated
--          UUID, and role is self-chosen at signup). But that also let a client
--          INSERT/UPSERT a row that pre-grants itself a paid plan, an active
--          paid subscription, verified flags, or is_app_owner = true — none of
--          which the UPDATE trigger caught (it doesn't run on INSERT).
--
-- WHAT this does:
--   * Rewrites guard_user_privileged_columns() to also run on INSERT and to
--     cover `is_app_owner`.
--       - UPDATE: blocks client changes to role / subscription_* / *_verified /
--         is_app_owner (unchanged behaviour + is_app_owner added).
--       - INSERT: sanitises a client-created row to a safe baseline (no
--         self-granted app-owner / verified flags / paid plan / expiry). Role is
--         deliberately NOT touched on INSERT — choosing Owner vs Member at
--         signup is by design; later role CHANGES stay locked on UPDATE.
--   * Re-points the trigger to BEFORE INSERT OR UPDATE OF (...).
--
-- ESCAPE HATCH (unchanged): the SECURITY DEFINER RPCs (start_my_trial,
--   change_my_role, account-recovery) set `app.allow_privileged_update = 'on'`
--   and are exempt. To grant is_app_owner / fix a plan manually from the
--   Supabase SQL editor, wrap the statement:
--       SET LOCAL app.allow_privileged_update = 'on';
--       UPDATE public.users SET is_app_owner = true WHERE id = '...';
--
-- SAFE / NON-BREAKING: verified against the codebase — signup (auth_screen),
--   role selection, member_home self-insert, admin add-member (role:'member',
--   generated id) and profile upserts set NONE of the sanitised columns, so the
--   INSERT branch is a no-op for every real flow.
--
-- Idempotent: CREATE OR REPLACE + DROP TRIGGER IF EXISTS. Apply once in the
-- Supabase SQL editor; folded into supabase_schema.sql.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.guard_user_privileged_columns()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF current_setting('app.allow_privileged_update', true) IS DISTINCT FROM 'on' THEN

        IF TG_OP = 'UPDATE' THEN
            IF OLD.role IS NOT NULL AND NEW.role IS DISTINCT FROM OLD.role THEN
                RAISE EXCEPTION 'Role can only be changed through change_my_role()'
                    USING errcode = '42501';
            END IF;
            IF NEW.subscription_plan   IS DISTINCT FROM OLD.subscription_plan
            OR NEW.subscription_status IS DISTINCT FROM OLD.subscription_status
            OR NEW.subscription_expiry IS DISTINCT FROM OLD.subscription_expiry THEN
                RAISE EXCEPTION 'Subscription can only be changed by the trial/billing flow'
                    USING errcode = '42501';
            END IF;
            IF NEW.phone_verified IS DISTINCT FROM OLD.phone_verified
            OR NEW.email_verified IS DISTINCT FROM OLD.email_verified THEN
                RAISE EXCEPTION 'Verification flags are set only after OTP verification'
                    USING errcode = '42501';
            END IF;
            IF NEW.is_app_owner IS DISTINCT FROM OLD.is_app_owner THEN
                RAISE EXCEPTION 'The app-owner flag cannot be changed by clients'
                    USING errcode = '42501';
            END IF;

        ELSIF TG_OP = 'INSERT' THEN
            -- A client-created row may not pre-grant itself privileges. Role is
            -- self-chosen at signup (by product design) and is locked against
            -- later escalation on UPDATE; everything else is forced to a safe
            -- baseline so a crafted INSERT/UPSERT can't bypass the trial/billing
            -- /verification/owner flows.
            NEW.is_app_owner        := false;
            NEW.phone_verified      := false;
            NEW.email_verified      := false;
            NEW.subscription_expiry := NULL;
            IF NEW.subscription_plan IS NOT NULL
               AND NEW.subscription_plan NOT IN ('free', 'trial') THEN
                NEW.subscription_plan := 'free';
            END IF;
            -- subscription_status keeps its column default ('active' = account
            -- state, not a paid grant; paid tier is gated by plan + expiry).
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_user_privileged_columns ON public.users;
CREATE TRIGGER trg_guard_user_privileged_columns
    BEFORE INSERT OR UPDATE OF role, subscription_plan, subscription_status,
                     subscription_expiry, phone_verified, email_verified, is_app_owner
    ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION public.guard_user_privileged_columns();
