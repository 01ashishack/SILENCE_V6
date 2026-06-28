-- ============================================================================
-- 2026-06-27 — RLS / privilege VERIFICATION (read-only, run in Supabase SQL editor)
-- ============================================================================
-- Pre-launch confirmation that all Wave-0 locks are actually live. This script
-- only SELECTs — it changes nothing. Run each block and compare to "EXPECT".
-- ============================================================================

-- 1) RLS must be ENABLED on every app table. EXPECT: zero rows.
--    (Any row returned = a table with RLS OFF = world-readable/writable.)
SELECT c.relname AS table_without_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relrowsecurity = false
  AND c.relname IN (
    'users','libraries','shifts','floors','sections','seats','memberships',
    'attendance','payments','join_requests','seat_change_requests','hold_requests',
    'checkin_approvals','transfers','add_ons','member_add_ons','referrals','badges',
    'announcements','announcement_reads','queries','notifications','audit_log',
    'scheduled_closures','reviews','expenditures','settings','streaks',
    'member_daily_stats','leads','verification_requests','draft_members','device_tokens'
  )
ORDER BY 1;

-- 2) The privileged-column guard trigger must exist and fire on INSERT+UPDATE.
--    EXPECT: one row, tgenabled = 'O', and the definition shows
--    "BEFORE INSERT OR UPDATE OF role, ... , is_app_owner".
SELECT tgname,
       tgenabled,
       pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t
WHERE NOT t.tgisinternal
  AND t.tgname = 'trg_guard_user_privileged_columns';

-- 3) The guard function body must reference is_app_owner (the new lock).
--    EXPECT: one row (count = 1).
SELECT count(*) AS guards_is_app_owner
FROM pg_proc
WHERE proname = 'guard_user_privileged_columns'
  AND pg_get_functiondef(oid) ILIKE '%is_app_owner%';

-- 4) Permissive policies audit. EXPECT: only the INTENTIONAL public-read rows
--    below (SELECT on explore/join tables) + the users signup INSERT. Anything
--    else with qual = 'true' / with_check = 'true' deserves a second look.
--      intentional SELECT 'true' : shifts, floors, sections, seats, add_ons,
--                                  (reviews public-active is scoped, not 'true')
--      intentional INSERT 'true' : users "Anyone can insert (signup)"
SELECT tablename, policyname, cmd,
       qual         AS using_expr,
       with_check   AS check_expr
FROM pg_policies
WHERE schemaname = 'public'
  AND (qual = 'true' OR with_check = 'true')
ORDER BY tablename, cmd, policyname;

-- 5) Storage policies must be owner-scoped on the private bucket.
--    EXPECT: policies on storage.objects referencing 'silence_private' with an
--    owner/path check (NOT a bare 'true'). Review the definitions by eye.
SELECT policyname, cmd, qual AS using_expr, with_check AS check_expr
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects'
ORDER BY cmd, policyname;

-- 6) Sanity: nobody already self-granted app-owner. EXPECT: only the rows you
--    deliberately made owners (ideally 0 or 1). Investigate any unexpected id.
SELECT id, email, role, is_app_owner, subscription_plan, subscription_status
FROM public.users
WHERE is_app_owner = true;

-- 7) Sanity: no client-side paid plan that didn't come from billing. During beta
--    everything is unlocked anyway, but EXPECT no surprise 'pro'/'basic'/'starter'
--    rows you didn't create.
SELECT subscription_plan, count(*)
FROM public.users
GROUP BY subscription_plan
ORDER BY 1;
