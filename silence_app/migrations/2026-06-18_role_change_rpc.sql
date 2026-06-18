-- ============================================================================
-- 2026-06-18 — Role change: 7-day window + data wipe + self-escalation lock
--              (audit P6-02 — role self-escalation)
-- ============================================================================
--
-- PRODUCT RULE (decided with user 2026-06-18):
--   The "Change Role" option exists only to fix an ACCIDENTAL wrong-role signup.
--   * Allowed ONLY within 7 days of signup (users.created_at).
--   * Changing role PERMANENTLY DELETES the current role's account data and
--     starts a brand-new, empty account in the new role. The login identity
--     (auth user / email / phone) is kept; all operational data is wiped.
--   * The app shows a strict type-to-confirm dialog before calling this.
--
-- SECURITY: after this is applied, a normal client can no longer flip its own
--   `users.role` directly (the trigger blocks it). The ONLY way to change role
--   is change_my_role(), which enforces the 7-day rule server-side. Because the
--   change also wipes all data and is time-boxed, self-escalation to admin is
--   pointless and impossible after 7 days.
--
-- Idempotent: safe to re-run.
-- ============================================================================

-- 1) Guard trigger: block direct role flips (escalation) ---------------------
--    Allows: INSERTs, null->role onboarding (role_selection upsert), and
--    same-value writes (profile-edit upserts that re-send the unchanged role).
--    Blocks: a real flip between two non-null roles unless change_my_role()
--    set the transaction-local flag first.
CREATE OR REPLACE FUNCTION public.guard_role_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.role IS NOT NULL AND NEW.role IS DISTINCT FROM OLD.role THEN
        IF current_setting('app.allow_role_change', true) IS DISTINCT FROM 'on' THEN
            RAISE EXCEPTION 'Role can only be changed through change_my_role()'
                USING errcode = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_role_change ON public.users;
CREATE TRIGGER trg_guard_role_change
    BEFORE UPDATE OF role ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION public.guard_role_change();

-- 2) change_my_role(): the only sanctioned way to switch role ----------------
--    SECURITY DEFINER so it can purge across tables under tightened RLS.
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
    -- 7-day window from signup; null created_at (legacy) is treated as expired.
    IF v_created IS NULL OR v_created < now() - interval '7 days' THEN
        RAISE EXCEPTION 'Role can only be changed within 7 days of signup'
            USING errcode = 'P0001';
    END IF;

    -- ---- wipe ALL role-specific data (keep the auth identity row) ----------
    -- member-side activity
    DELETE FROM public.attendance            WHERE member_id  = v_uid;
    DELETE FROM public.payments              WHERE member_id  = v_uid;
    DELETE FROM public.seat_change_requests  WHERE member_id  = v_uid;
    DELETE FROM public.hold_requests         WHERE member_id  = v_uid;
    DELETE FROM public.join_requests         WHERE member_id  = v_uid;
    DELETE FROM public.reviews               WHERE member_id  = v_uid;
    DELETE FROM public.badges                WHERE member_id  = v_uid;
    DELETE FROM public.referrals             WHERE referrer_id = v_uid OR referred_id = v_uid;
    DELETE FROM public.queries               WHERE member_id  = v_uid;
    DELETE FROM public.notifications         WHERE user_id    = v_uid;
    DELETE FROM public.transfers             WHERE member_id  = v_uid;
    BEGIN DELETE FROM public.streaks            WHERE member_id = v_uid; EXCEPTION WHEN undefined_table THEN NULL; END;
    BEGIN DELETE FROM public.member_daily_stats WHERE member_id = v_uid; EXCEPTION WHEN undefined_table THEN NULL; END;
    -- free any seats this member occupies (in other owners' libraries)
    UPDATE public.seats SET status = 'vacant', occupied_by_member_id = NULL
        WHERE occupied_by_member_id = v_uid;
    DELETE FROM public.memberships           WHERE member_id  = v_uid;
    -- admin-side
    BEGIN DELETE FROM public.settings    WHERE admin_id = v_uid; EXCEPTION WHEN undefined_table THEN NULL; END;
    DELETE FROM public.announcements         WHERE admin_id   = v_uid;
    DELETE FROM public.audit_log             WHERE admin_id   = v_uid;
    -- owned libraries cascade their floors/sections/seats/shifts + memberships
    DELETE FROM public.libraries             WHERE owner_id   = v_uid;
    -- NOTE: device_tokens are kept (same device stays signed in). Storage
    -- objects (old ID docs / proofs) are NOT purged here — minor orphan cleanup,
    -- low risk; revisit if needed.

    -- ---- flip role + reset operational fields (identity stays) -------------
    PERFORM set_config('app.allow_role_change', 'on', true);
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
-- VERIFY (run after applying):
--   -- within 7 days, as the signed-in user:
--   select public.change_my_role('admin');   -- should succeed once
--   select public.change_my_role('admin');   -- 'You are already a admin'
--   -- direct flip must now fail:
--   update public.users set role='admin' where id = auth.uid();  -- 42501
-- ROLLBACK:
--   drop trigger if exists trg_guard_role_change on public.users;
--   drop function if exists public.change_my_role(text);
--   drop function if exists public.guard_role_change();
-- ============================================================================
