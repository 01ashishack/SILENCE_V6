-- ============================================================================
-- 2026-07-05 — write-path integrity (audit P0: client-trusted relationship cols)
-- ============================================================================
--
-- ⚠️ HIGHER REGRESSION RISK — apply, then LIVE-TEST a real member check-in and a
-- real payment before relying on it. A too-strict predicate silently blocks
-- legitimate writes. (Do NOT fold into supabase_schema.sql until verified.)
--
-- PROBLEMS:
--  (A) attendance + payments member INSERT policies only checked
--      `member_id = auth.uid()` — not that membership_id/library_id actually
--      belong to an ACTIVE membership of that member. A crafted client could
--      attribute attendance/payments to arbitrary library ids.
--  (B) "Owner can update their library members" lets an owner rewrite a
--      member's email/phone (decoupling them from Supabase Auth / lockout).
--
-- FIXES:
--  (A) Tighten the member INSERT WITH CHECK with an EXISTS over memberships:
--      the membership must belong to the caller and the row's library_id must
--      match it (active/trial for attendance). shift_id is intentionally NOT
--      constrained, to avoid blocking out-of-shift/edge check-in flows.
--  (B) A BEFORE UPDATE OF email,phone trigger that REVERTS those columns when a
--      different signed-in user (an owner) edits the row. Self-edits
--      (auth.uid() = id) and service_role/definer (auth.uid() IS NULL) pass
--      through. Silent revert (not an exception) so the owner's other edits in
--      the same UPDATE still succeed.
--
-- Idempotent. Apply in the Supabase SQL editor.
-- ============================================================================

-- ── (A1) Attendance member insert: must match an active/trial membership ────
DROP POLICY IF EXISTS "Member insert (check-in/out)" ON public.attendance;
CREATE POLICY "Member insert (check-in/out)" ON public.attendance
    FOR INSERT WITH CHECK (
        member_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.memberships m
            WHERE m.id = attendance.membership_id
              AND m.member_id = auth.uid()
              AND m.library_id = attendance.library_id
              AND m.status IN ('active', 'trial')
        )
    );

-- ── (A2) Payment member insert: must match the caller's membership/library ──
-- (Status is additionally forced to 'pending' for members by the Wave 0.3
--  guard trigger; this adds relationship integrity.)
DROP POLICY IF EXISTS "Member insert (upload proof)" ON public.payments;
CREATE POLICY "Member insert (upload proof)" ON public.payments
    FOR INSERT WITH CHECK (
        member_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.memberships m
            WHERE m.id = payments.membership_id
              AND m.member_id = auth.uid()
              AND m.library_id = payments.library_id
        )
    );

-- ── (B) Lock member email/phone against non-self (owner) edits ──────────────
CREATE OR REPLACE FUNCTION public.guard_user_contact_columns()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    -- Only restrict when a DIFFERENT signed-in user (e.g. a library owner) edits
    -- this row. Self-edits and service_role/definer flows (auth.uid() NULL) pass.
    IF auth.uid() IS NOT NULL AND auth.uid() IS DISTINCT FROM NEW.id THEN
        NEW.email := OLD.email;
        NEW.phone := OLD.phone;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_user_contact_columns ON public.users;
CREATE TRIGGER trg_guard_user_contact_columns
    BEFORE UPDATE OF email, phone ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.guard_user_contact_columns();

-- ============================================================================
-- VERIFY (LIVE — do before fold):
--   1. Real member QR check-in (online AND offline-then-sync) → succeeds.
--   2. Member with an active membership: attendance/payment insert for a
--      mismatched library_id/foreign membership_id → REJECTED by RLS.
--   3. Member edits their OWN phone/email in profile → saves.
--   4. Owner edits a member (name/photo) → saves, but a phone/email change by
--      the owner is silently kept at the old value.
-- ROLLBACK:
--   Re-create both policies with only `WITH CHECK (member_id = auth.uid())`;
--   DROP TRIGGER trg_guard_user_contact_columns ON public.users;
--   DROP FUNCTION public.guard_user_contact_columns();
-- ============================================================================
