-- ============================================================================
-- 2026-07-08 — tenant-scope seat reads (audit P2 A2-7: occupant-identity leak)
-- ============================================================================
--
-- PROBLEM: `seats` had a blanket `FOR SELECT USING (true)` policy. Because
-- `seats.occupied_by_member_id` records WHO sits on each seat, any authenticated
-- user could query another library's seats and map members → seats (tenant PII
-- leak). RLS can't hide a single column, so we scope WHICH rows a caller can
-- read instead.
--
-- WHO LEGITIMATELY READS seats (verified against the codebase):
--   • Library OWNER — layout/admin screens (needs occupant) → owns the library.
--   • A MEMBER of that library — sees their own seat via the embedded
--     memberships→seats read → has a membership in that library.
--   • Admin "add member" seat picker (VacantSeatGrid) → admin owns the library.
--   • Explore / member join flow → DO NOT read `seats` at all (they read
--     `libraries` + `shifts`), so no prospective-joiner seat read to preserve.
--
-- FIX: replace the public SELECT with owner-OR-member-of-library scoping. No app
-- code change is required (no cross-tenant seat read exists). Writes/INSERT/
-- UPDATE/DELETE policies are unchanged (still owner-only).
--
-- NOTE: `add_ons` keeps its public read — it's a price catalog (name/price/
-- deposit) with NO member PII and IS needed by prospective joiners selecting
-- add-ons before they belong to the library. `floors`/`sections` likewise carry
-- no PII. Only `seats` exposes occupant identity, so only `seats` is scoped.
--
-- Idempotent. Apply in the Supabase SQL editor.
-- ============================================================================

DROP POLICY IF EXISTS "Anyone can view seats" ON seats;

CREATE POLICY "Owner or member can view seats" ON seats
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM libraries l
             WHERE l.id = seats.library_id
               AND l.owner_id = auth.uid()
        )
        OR EXISTS (
            SELECT 1 FROM memberships m
             WHERE m.library_id = seats.library_id
               AND m.member_id = auth.uid()
        )
    );

-- ============================================================================
-- VERIFY:
--   • Owner: layout tab still shows all seats + occupant names. ✓
--   • Member: own seat label still renders on home/history (embedded read). ✓
--   • Admin add-member: VacantSeatGrid still lists vacant seats. ✓
--   • A user with NO relationship to library X gets ZERO rows from
--     `select * from seats where library_id = '<X>'` (no occupant leak). ✓
--   • Explore + member join flow unaffected (they don't read seats). ✓
-- ROLLBACK:
--   DROP POLICY IF EXISTS "Owner or member can view seats" ON seats;
--   CREATE POLICY "Anyone can view seats" ON seats FOR SELECT USING (true);
-- ============================================================================
