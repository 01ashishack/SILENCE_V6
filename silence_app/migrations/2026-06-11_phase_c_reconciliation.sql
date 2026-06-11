-- ============================================================================
-- SILENCE — Phase C Schema Reconciliation
-- Authored: 2026-06-11
-- ----------------------------------------------------------------------------
-- WHAT THIS IS
--   Brings the live Supabase schema in line with what the (heavily remediated)
--   Flutter code actually reads and writes today. Source of truth = the CODE.
--
-- HOW TO RUN
--   Run section by section in the Supabase SQL editor, TOP TO BOTTOM.
--   1. Run §A (read-only checks) FIRST and read the output.
--   2. If §A shows ZERO violating rows, run §B..§F straight through.
--   3. If §A shows violations, clean that data, then run §F (the guarded
--      constraints).  §B..§E are safe regardless of §A.
--
-- SAFETY
--   * Everything is idempotent (IF NOT EXISTS / guarded DO blocks) — safe to
--     re-run.
--   * This migration is ADDITIVE ONLY. It does NOT touch any existing RLS
--     policy on an existing table. The dangerous-policy hardening (audit
--     P5-01 / P5-07 / P5-08) is deliberately OUT OF SCOPE here and tracked
--     separately on the Wave-0/1 security track — see docs_fix/PHASE_C_SCHEMA.md.
--   * The only destructive step (§E DROP library_closures) is commented out and
--     guarded — you opt in after confirming it is empty.
--
-- NOT VERIFIED ON A LIVE DB
--   Authored without live Supabase access. The §A pre-checks + the post-apply
--   spot-checks in PHASE_C_SCHEMA.md are the verification step.
-- ============================================================================


-- ============================================================================
-- §A — PRE-FLIGHT CHECKS  (READ-ONLY — run these first, fix data before §F)
-- ============================================================================

-- A1. Duplicate live memberships for one member in one library.
--     §F adds a partial-unique that will FAIL to create if any group has >1.
SELECT member_id, library_id, count(*) AS live_memberships
FROM memberships
WHERE status IN ('active', 'trial', 'hold')
GROUP BY member_id, library_id
HAVING count(*) > 1;

-- A2. One seat held by more than one live membership.
--     §F adds a partial-unique on seat_id for live rows.
SELECT seat_id, count(*) AS live_holders
FROM memberships
WHERE seat_id IS NOT NULL
  AND status IN ('active', 'trial')
GROUP BY seat_id
HAVING count(*) > 1;

-- A3. Invalid attendance rows (checkout before checkin, or negative duration).
--     §F adds CHECKs as NOT VALID so these legacy rows won't block the migration,
--     but you should clean them before running `VALIDATE CONSTRAINT` later.
SELECT id, check_in_time, check_out_time, duration_minutes
FROM attendance
WHERE (check_out_time IS NOT NULL AND check_out_time < check_in_time)
   OR (duration_minutes IS NOT NULL AND duration_minutes < 0);


-- ============================================================================
-- §B — ADDITIVE COLUMNS  (code already writes these; schema was stale)
-- ============================================================================

-- B1. join_requests.selected_addon_ids
--     join_flow_screen.dart writes a uuid[] of chosen add-ons (with a retry
--     fallback for when the column is absent). Adding it retires that fallback.
ALTER TABLE join_requests
    ADD COLUMN IF NOT EXISTS selected_addon_ids uuid[];

-- B2. queries.subject / type / screenshot_url
--     help_support_screen.dart + member_help_support_screen.dart write a bug
--     report subject, a type ('bug'), and an optional screenshot url.
ALTER TABLE queries
    ADD COLUMN IF NOT EXISTS subject TEXT;
ALTER TABLE queries
    ADD COLUMN IF NOT EXISTS type TEXT;
ALTER TABLE queries
    ADD COLUMN IF NOT EXISTS screenshot_url TEXT;

-- B3. users.referral_code + account-deletion request flags
--     member_home / member_profile_tab write referral_code; the account-deletion
--     flow (member_privacy_security + admin_profile_tab) writes the two deletion
--     flags. These are honest "request" flags — no server-side purge yet.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS referral_code TEXT;
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS scheduled_for_deletion BOOLEAN DEFAULT false;
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS deletion_scheduled_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_users_referral_code ON users(referral_code);

-- B4. seat_change_requests.approved_at
--     requests_sub_tab.dart stamps this when an admin approves a seat change.
ALTER TABLE seat_change_requests
    ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;


-- ============================================================================
-- §C — MISSING TABLES  (referenced by code, absent from canonical schema)
--      Each gets RLS enabled + ownership-scoped policies, matching the
--      existing draft_members.sql pattern. (Authoring policies for NEW tables
--      is part of creating them correctly — no EXISTING policy is touched.)
-- ============================================================================

-- C1. settings — admin per-library / global key-value config
--     admin_settings_service.dart: upsert on (admin_id, library_id, scope).
--     library_id is NULLABLE for global scope, so the unique must treat NULLs
--     as equal (NULLS NOT DISTINCT, Postgres 15+) or the global upsert can't
--     find its existing row.
CREATE TABLE IF NOT EXISTS settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id UUID REFERENCES libraries(id) ON DELETE CASCADE,
    scope TEXT NOT NULL,
    value JSONB NOT NULL DEFAULT '{}',
    updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_settings_admin_lib_scope
    ON settings (admin_id, library_id, scope) NULLS NOT DISTINCT;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin manage own settings" ON settings;
CREATE POLICY "Admin manage own settings" ON settings
    FOR ALL USING (admin_id = auth.uid())
    WITH CHECK (admin_id = auth.uid());

-- C2. streaks — per member, per library streak cache
--     member_analytics_service.dart reads current_streak/longest_streak/
--     last_present_date (Wave-2 server job will populate it).
CREATE TABLE IF NOT EXISTS streaks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    current_streak INTEGER DEFAULT 0,
    longest_streak INTEGER DEFAULT 0,
    last_present_date DATE,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT uq_streaks_member_library UNIQUE (member_id, library_id)
);
ALTER TABLE streaks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Member view own streaks" ON streaks;
CREATE POLICY "Member view own streaks" ON streaks
    FOR SELECT USING (member_id = auth.uid());
DROP POLICY IF EXISTS "Admin view library streaks" ON streaks;
CREATE POLICY "Admin view library streaks" ON streaks
    FOR SELECT USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

-- C3. member_daily_stats — precomputed per-day attendance facts (analytics cache)
--     member_analytics_service.dart reads date/present_flag/total_minutes.
CREATE TABLE IF NOT EXISTS member_daily_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    present_flag BOOLEAN DEFAULT false,
    total_minutes INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT uq_mds_member_library_date UNIQUE (member_id, library_id, date)
);
ALTER TABLE member_daily_stats ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Member view own daily stats" ON member_daily_stats;
CREATE POLICY "Member view own daily stats" ON member_daily_stats
    FOR SELECT USING (member_id = auth.uid());
DROP POLICY IF EXISTS "Admin view library daily stats" ON member_daily_stats;
CREATE POLICY "Admin view library daily stats" ON member_daily_stats
    FOR SELECT USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

-- C4. leads — member-suggested new libraries (explore screen lead capture)
--     member_explore_screen.dart inserts library_name/location/owner_phone/
--     suggested_by_member_id. Read by the app-owner (no in-app console yet).
CREATE TABLE IF NOT EXISTS leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_name TEXT NOT NULL,
    location TEXT,
    owner_phone TEXT,
    suggested_by_member_id UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Member submit lead" ON leads;
CREATE POLICY "Member submit lead" ON leads
    FOR INSERT WITH CHECK (suggested_by_member_id = auth.uid());
DROP POLICY IF EXISTS "Member view own leads" ON leads;
CREATE POLICY "Member view own leads" ON leads
    FOR SELECT USING (suggested_by_member_id = auth.uid());

-- C5. verification_requests — library "verified badge" submissions
--     verified_badge_screen.dart inserts library_id/status/reviewed_at/admin_notes.
CREATE TABLE IF NOT EXISTS verification_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending',
    reviewed_at TIMESTAMPTZ,
    admin_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE verification_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Owner manage verification requests" ON verification_requests;
CREATE POLICY "Owner manage verification requests" ON verification_requests
    FOR ALL USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

-- C6. draft_members — admin's in-progress "add member" drafts
--     Folded in from the loose draft_members.sql (now superseded).
CREATE TABLE IF NOT EXISTS draft_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    draft_data JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE draft_members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins full access on own drafts" ON draft_members;
CREATE POLICY "Admins full access on own drafts" ON draft_members
    FOR ALL
    USING (admin_id = auth.uid()
           OR EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (admin_id = auth.uid()
           OR EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));
CREATE INDEX IF NOT EXISTS idx_draft_members_library_id ON draft_members(library_id);
CREATE INDEX IF NOT EXISTS idx_draft_members_admin_id ON draft_members(admin_id);


-- ============================================================================
-- §D — EXPENDITURES NORMALIZATION
--      The canonical CHECK is the 12 lowercase categories. add_expense_bottom_
--      sheet.dart already lowercases. admin_analytics_tab.dart historically
--      wrote Title-Case ('Salaries','Others', ...) — that is fixed IN CODE in
--      this same change (map → canonical lowercase keys on write). This step
--      migrates any EXISTING rows that were written with the old vocabulary so
--      grouping/totals are consistent and pass the CHECK.
-- ============================================================================

-- Lowercase everything, then remap the two legacy aliases to canonical keys.
UPDATE expenditures SET category = lower(category)
    WHERE category <> lower(category);
UPDATE expenditures SET category = 'salary'
    WHERE category IN ('salaries');
UPDATE expenditures SET category = 'miscellaneous'
    WHERE category IN ('others', 'other');

-- Any row whose category is still outside the canonical set would block a
-- (re)added CHECK. List them so you can decide (most likely none).
SELECT id, category FROM expenditures
WHERE category NOT IN (
    'rent','electricity','internet','water','maintenance','salary',
    'supplies','generator','cleaning','security','taxes','miscellaneous'
);


-- ============================================================================
-- §E — RETIRE dead `library_closures`  (DESTRUCTIVE — opt-in)
--      Closures are canonical on scheduled_closures(start_date,end_date). The
--      old library_closures table is no longer referenced by any code. If it
--      exists in your live DB and holds no rows you still need, drop it.
-- ============================================================================

-- First, see whether it exists and whether it holds anything:
--   SELECT count(*) FROM library_closures;   -- run only if the table exists
--
-- Then, once you've confirmed it's safe, UNCOMMENT to drop:
-- DROP TABLE IF EXISTS library_closures;


-- ============================================================================
-- §F — GUARDED INTEGRITY CONSTRAINTS  (run only after §A is clean)
--      Partial-unique indexes use IF NOT EXISTS (idempotent). The attendance
--      CHECKs are added NOT VALID so legacy rows don't block creation; run the
--      VALIDATE statements at the bottom after you've cleaned §A3 rows.
-- ============================================================================

-- F1. At most one live membership per (member_id, library_id).
CREATE UNIQUE INDEX IF NOT EXISTS uq_membership_active_per_member_library
    ON memberships (member_id, library_id)
    WHERE status IN ('active', 'trial', 'hold');

-- F2. A seat can be held by at most one live membership.
CREATE UNIQUE INDEX IF NOT EXISTS uq_membership_active_seat
    ON memberships (seat_id)
    WHERE seat_id IS NOT NULL AND status IN ('active', 'trial');

-- F3. Attendance validity — checkout not before checkin, no negative duration.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_attendance_checkout_after_checkin'
    ) THEN
        ALTER TABLE attendance
            ADD CONSTRAINT chk_attendance_checkout_after_checkin
            CHECK (check_out_time IS NULL OR check_out_time >= check_in_time) NOT VALID;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_attendance_duration_nonneg'
    ) THEN
        ALTER TABLE attendance
            ADD CONSTRAINT chk_attendance_duration_nonneg
            CHECK (duration_minutes IS NULL OR duration_minutes >= 0) NOT VALID;
    END IF;
END $$;

-- After cleaning the §A3 rows, validate the CHECKs against existing data:
-- ALTER TABLE attendance VALIDATE CONSTRAINT chk_attendance_checkout_after_checkin;
-- ALTER TABLE attendance VALIDATE CONSTRAINT chk_attendance_duration_nonneg;

-- ============================================================================
-- End of Phase C reconciliation.
-- ============================================================================
