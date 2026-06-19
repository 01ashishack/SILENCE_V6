-- ============================================================================
-- 2026-06-18 — Lock the library "Verified" badge (self-assertion / forgeable
--              trust signal; P6-family)
-- ============================================================================
--
-- verified_badge_screen wrote libraries.verified = true directly from the
-- client, gated only by CLIENT-side eligibility. The verified/verified_at
-- columns were not locked, so an owner could forge the trust badge via the API.
--
-- Fix: a SECURITY DEFINER claim_verified_badge() RPC re-checks every eligibility
-- rule SERVER-side, then sets verified; a trigger blocks any other direct change
-- to verified/verified_at. (The app-owner can still verify manually via the
-- dashboard — service_role bypasses the trigger.)
--
-- Eligibility mirrors the client: owner of the library · library ≥ 30 days old ·
-- setup complete (floors+sections+seats+non-archived shifts) · ≥10 active
-- members · ≥50 check-ins · owner profile complete (name/phone/gender/dob/photo)
-- · active subscription (plan not null/'none').
--
-- Idempotent.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.guard_library_verified()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (NEW.verified IS DISTINCT FROM OLD.verified
        OR NEW.verified_at IS DISTINCT FROM OLD.verified_at)
       AND current_setting('app.allow_verify', true) IS DISTINCT FROM 'on' THEN
        RAISE EXCEPTION 'Library verification can only be set via claim_verified_badge()'
            USING errcode = '42501';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_library_verified ON public.libraries;
CREATE TRIGGER trg_guard_library_verified
    BEFORE UPDATE OF verified, verified_at ON public.libraries
    FOR EACH ROW EXECUTE FUNCTION public.guard_library_verified();

CREATE OR REPLACE FUNCTION public.claim_verified_badge(p_library uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid     uuid := auth.uid();
    v_created timestamptz;
    v_floors  int; v_sections int; v_seats int; v_shifts int;
    v_members int; v_checkins int;
    v_name text; v_phone text; v_gender text; v_dob date; v_photo text;
    v_plan text; v_status text;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not signed in' USING errcode = '42501';
    END IF;

    SELECT created_at INTO v_created
      FROM public.libraries WHERE id = p_library AND owner_id = v_uid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Not your library' USING errcode = '42501';
    END IF;

    IF v_created IS NULL OR v_created > now() - interval '30 days' THEN
        RAISE EXCEPTION 'Library must be active for 30 days' USING errcode = 'P0001';
    END IF;

    SELECT count(*) INTO v_floors  FROM public.floors  WHERE library_id = p_library;
    SELECT count(*) INTO v_sections FROM public.sections s
        JOIN public.floors f ON f.id = s.floor_id WHERE f.library_id = p_library;
    SELECT count(*) INTO v_seats   FROM public.seats   WHERE library_id = p_library;
    SELECT count(*) INTO v_shifts  FROM public.shifts  WHERE library_id = p_library AND is_archived = false;
    IF v_floors = 0 OR v_sections = 0 OR v_seats = 0 OR v_shifts = 0 THEN
        RAISE EXCEPTION 'Library setup is incomplete' USING errcode = 'P0001';
    END IF;

    SELECT count(*) INTO v_members FROM public.memberships
        WHERE library_id = p_library AND status = 'active';
    IF v_members < 10 THEN
        RAISE EXCEPTION 'At least 10 active members are required' USING errcode = 'P0001';
    END IF;

    SELECT count(*) INTO v_checkins FROM public.attendance WHERE library_id = p_library;
    IF v_checkins < 50 THEN
        RAISE EXCEPTION 'At least 50 check-ins are required' USING errcode = 'P0001';
    END IF;

    SELECT full_name, phone, gender, date_of_birth, photo_url,
           subscription_plan, subscription_status
      INTO v_name, v_phone, v_gender, v_dob, v_photo, v_plan, v_status
      FROM public.users WHERE id = v_uid;
    IF coalesce(btrim(v_name), '') = '' OR coalesce(btrim(v_phone), '') = ''
       OR coalesce(btrim(v_gender), '') = '' OR v_dob IS NULL
       OR coalesce(btrim(v_photo), '') = '' THEN
        RAISE EXCEPTION 'Complete your admin profile first' USING errcode = 'P0001';
    END IF;
    IF coalesce(v_plan, 'none') = 'none' OR v_status IS DISTINCT FROM 'active' THEN
        RAISE EXCEPTION 'An active subscription is required' USING errcode = 'P0001';
    END IF;

    PERFORM set_config('app.allow_verify', 'on', true);
    UPDATE public.libraries SET verified = true, verified_at = now() WHERE id = p_library;
    INSERT INTO public.verification_requests (library_id, status, reviewed_at, admin_notes)
    VALUES (p_library, 'approved', now(), 'Auto-verified: eligibility met (server-checked).');
END;
$$;
REVOKE ALL ON FUNCTION public.claim_verified_badge(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_verified_badge(uuid) TO authenticated;

-- ============================================================================
-- VERIFY:
--   select public.claim_verified_badge('<eligible-lib>');   -- sets verified
--   update public.libraries set verified=true where id='<lib>';  -- must FAIL 42501
-- ROLLBACK:
--   drop trigger if exists trg_guard_library_verified on public.libraries;
--   drop function if exists public.guard_library_verified();
--   drop function if exists public.claim_verified_badge(uuid);
-- ============================================================================
