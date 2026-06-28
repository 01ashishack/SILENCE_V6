-- ============================================================================
-- 2026-06-27 — Let an owner delete their OWN library regardless of status
-- ============================================================================
-- BUG: deleting a library from the admin Profile tab showed a "deleted"
--   snackbar but the row stayed. Cause: the DELETE policy only allowed
--   status = 'setup' rows. An 'active' library's delete was blocked by RLS —
--   and PostgREST does NOT error on an RLS-blocked delete, it just removes 0
--   rows — so the client wrongly reported success.
--
-- FIX: allow the owner to delete their own library in any status. The dependent
--   rows are handled by the ON DELETE CASCADE FKs added in
--   2026-06-26_library_delete_cascade.sql, and the UI already requires typing
--   the library name to confirm. The client is also being hardened to verify
--   the delete (… .delete().select()) so it can no longer claim a false success.
--
-- Idempotent. Apply once in the Supabase SQL editor; folded into supabase_schema.sql.
-- ============================================================================

DROP POLICY IF EXISTS "Only owner can delete (only if status = setup)" ON public.libraries;
DROP POLICY IF EXISTS "Owner can delete own library" ON public.libraries;

CREATE POLICY "Owner can delete own library" ON public.libraries
    FOR DELETE USING (auth.uid() = owner_id);
