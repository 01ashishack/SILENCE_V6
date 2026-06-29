-- ============================================================================
-- 2026-07-03 — payments insert status guard (audit: member self-confirm bypass)
-- ============================================================================
--
-- PROBLEM: the member INSERT policy on payments is `WITH CHECK (member_id =
-- auth.uid())` with no restriction on `status`. A member could POST directly to
-- PostgREST a row with status='confirmed' (polluting revenue/dues; faking paid).
--
-- FIX: a BEFORE INSERT trigger that forces any insert NOT made by the library
-- owner (or a SECURITY DEFINER RPC / service_role, where auth.uid() is the owner
-- or NULL) to status='pending' + confirmed_by_admin_id=NULL. Legitimate admin
-- inserts (add-member wizard, approve_join_request, transfer_member_shift, the
-- member_detail confirm) all run as the owner → unaffected. Members can still
-- submit a (pending) proof row; they just can't self-confirm.
--
-- SECURITY DEFINER so the owner lookup isn't blocked by libraries RLS.
-- Idempotent. Apply in the Supabase SQL editor.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.guard_payment_status()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
BEGIN
    -- service_role / definer cron (no JWT) → trust as-is.
    IF v_uid IS NULL THEN
        RETURN NEW;
    END IF;
    -- Library owner (admin, incl. owner-context SECURITY DEFINER RPCs) → trust.
    IF EXISTS (SELECT 1 FROM public.libraries
                WHERE id = NEW.library_id AND owner_id = v_uid) THEN
        RETURN NEW;
    END IF;
    -- Anyone else (a member) cannot self-confirm a payment.
    NEW.status := 'pending';
    NEW.confirmed_by_admin_id := NULL;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_payment_status ON public.payments;
CREATE TRIGGER trg_guard_payment_status
    BEFORE INSERT ON public.payments
    FOR EACH ROW EXECUTE FUNCTION public.guard_payment_status();

-- ============================================================================
-- VERIFY:
--   • As a MEMBER (PostgREST), insert payment with status='confirmed'
--       → row lands as status='pending', confirmed_by_admin_id NULL.
--   • As the OWNER (add member / confirm payment) → status preserved.
--   • approve_join_request / transfer_member_shift (run by owner) → unaffected.
-- ROLLBACK:
--   DROP TRIGGER IF EXISTS trg_guard_payment_status ON public.payments;
--   DROP FUNCTION IF EXISTS public.guard_payment_status();
-- ============================================================================
