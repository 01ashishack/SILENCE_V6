-- ============================================================================
-- 2026-06-12 — Fix: admin cannot record a member's payment (Add-Member wizard)
-- ============================================================================
--
-- SYMPTOM
--   Completing the Add-Member wizard ("Save & Add Member") failed with
--   "You don't have permission to do this." The membership + seat were already
--   written, so a half-created "ghost" member appeared in the list; saving a
--   draft on top produced a visible duplicate.
--
-- ROOT CAUSE
--   The `payments` table had only a MEMBER insert policy:
--       "Member insert (upload proof)"  WITH CHECK (member_id = auth.uid())
--   When a library OWNER inserts a payment for a member, member_id is the
--   member's id (not the owner's), so the WITH CHECK fails and RLS rejects the
--   insert (SQLSTATE 42501). There was no admin/owner insert policy. (Compare:
--   `memberships`, `attendance`, `seats` already have owner-insert policies —
--   only `payments` was missing one.)
--
-- FIX
--   Add an owner-scoped INSERT policy on `payments`, mirroring the existing
--   "Admin update status" policy. Additive, idempotent, owner-scoped — safe to
--   run on the live DB. No data change.
--
-- APPLY: run this whole file once in the Supabase SQL editor.
-- VERIFY: re-run the Add-Member wizard end-to-end — it should complete with
--         "Member added successfully", create the payment row, and delete the
--         draft (no duplicate, no permission error).
-- ============================================================================

DROP POLICY IF EXISTS "Admin insert payments for their libraries" ON payments;
CREATE POLICY "Admin insert payments for their libraries" ON payments
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM libraries
            WHERE id = library_id AND owner_id = auth.uid()
        )
    );

-- Note: the member self-insert policy is intentionally KEPT (members upload
-- their own out-of-app "I have paid" proof). Both insert paths now coexist.
