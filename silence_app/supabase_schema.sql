-- ============================================================
-- SILENCE Supabase Database Schema (PostgreSQL)
-- Version: 1.0
-- Description: Complete initialization script including tables,
--              constraints, triggers, indexes, and RLS policies.
-- ============================================================

-- Enable pgcrypto extension for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ------------------------------------------------------------
-- 1. UTILITY FUNCTIONS & TRIGGERS
-- ------------------------------------------------------------

-- Trigger to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- 1b. MAKE THIS SCRIPT RE-RUNNABLE (idempotent)
-- ------------------------------------------------------------
-- CREATE TRIGGER and CREATE POLICY are NOT idempotent, so re-running this file
-- on a database that already has some objects fails with errors like
-- 42710 "trigger ... already exists". This block clears the existing app
-- policies + triggers first; everything below then recreates them cleanly.
-- Tables use CREATE TABLE IF NOT EXISTS, so existing tables (and any rows) are
-- preserved. It does NOT drop the schema, so Supabase's role grants stay intact.
DO $$
DECLARE r record;
BEGIN
    -- Drop every Row-Level-Security policy on public tables.
    FOR r IN SELECT schemaname, tablename, policyname
             FROM pg_policies WHERE schemaname = 'public' LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I',
                       r.policyname, r.schemaname, r.tablename);
    END LOOP;
    -- Drop every trigger on public tables (the updated_at triggers below
    -- get recreated).
    FOR r IN SELECT event_object_table AS tbl, trigger_name AS trg
             FROM information_schema.triggers WHERE trigger_schema = 'public' LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', r.trg, r.tbl);
    END LOOP;
END $$;

-- ------------------------------------------------------------
-- 2. TABLE DEFINITIONS
-- ------------------------------------------------------------

-- Users Table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE, -- nullable: email is optional for members (UNIQUE still allows multiple NULLs); see migrations/2026-06-17_users_email_nullable.sql
    phone TEXT UNIQUE,
    full_name TEXT NOT NULL,
    nickname TEXT,
    role TEXT CHECK (role IN ('admin', 'member')), -- nullable until /role-select sets it (signup inserts role=null)
    gender TEXT CHECK (gender IN ('male', 'female', 'other', 'prefer_not_to_say')),
    date_of_birth DATE,
    photo_url TEXT,
    exam_category TEXT,
    address TEXT,
    phone_verified BOOLEAN DEFAULT false,
    email_verified BOOLEAN DEFAULT false,
    language_code TEXT DEFAULT 'en',
    fcm_token TEXT,
    id_proof_url TEXT,
    id_proof_2_url TEXT,
    id_type TEXT,
    father_name TEXT,
    emergency_contact TEXT,
    subscription_plan TEXT CHECK (subscription_plan IN ('starter', 'basic', 'pro', 'trial')),
    subscription_status TEXT DEFAULT 'active' CHECK (subscription_status IN ('active', 'grace', 'readonly', 'locked', 'cancelled')),
    subscription_expiry TIMESTAMPTZ,
    referral_code TEXT,
    scheduled_for_deletion BOOLEAN DEFAULT false,
    deletion_scheduled_at TIMESTAMPTZ,
    deletion_recovery_status TEXT NOT NULL DEFAULT 'none' CHECK (deletion_recovery_status IN ('none','requested','approved','denied')), -- 7-day recovery flow; see migrations/2026-06-18_account_deletion_recovery.sql
    is_app_owner BOOLEAN NOT NULL DEFAULT false, -- app-owner flag (recovery console); see migrations/2026-06-18_app_owner_flag.sql
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TRIGGER trigger_update_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Libraries Table
CREATE TABLE IF NOT EXISTS libraries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    library_code TEXT UNIQUE NOT NULL,
    address_street TEXT,
    address_city TEXT NOT NULL,
    address_state TEXT,
    address_pincode TEXT,
    photos TEXT[] DEFAULT '{}',
    amenities TEXT[] DEFAULT '{}',
    rules TEXT,
    about_text TEXT,
    emergency_phone TEXT,
    social_links JSONB DEFAULT '{}',
    status TEXT DEFAULT 'setup' CHECK (status IN ('setup', 'active', 'closed')),
    verified BOOLEAN DEFAULT false,
    verified_at TIMESTAMPTZ,
    qr_version INTEGER DEFAULT 1,
    avg_rating NUMERIC(2,1) DEFAULT 0,
    review_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Shifts Table
CREATE TABLE IF NOT EXISTS shifts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    price_monthly INTEGER NOT NULL,
    price_3month INTEGER,
    price_6month INTEGER,
    trial_days INTEGER DEFAULT 0,
    shift_type TEXT DEFAULT 'fixed',
    hours_per_day INTEGER DEFAULT 4,
    is_archived BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Floors Table
CREATE TABLE IF NOT EXISTS floors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    order_index INTEGER DEFAULT 0
);

-- Sections Table
CREATE TABLE IF NOT EXISTS sections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    floor_id UUID NOT NULL REFERENCES floors(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    tag TEXT CHECK (tag IN ('boys', 'girls', 'general', 'premium'))
);

-- Seats Table (Multi-shift model)
CREATE TABLE IF NOT EXISTS seats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    floor_id UUID REFERENCES floors(id) ON DELETE SET NULL,
    section_id UUID REFERENCES sections(id) ON DELETE SET NULL,
    shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
    seat_label TEXT NOT NULL,
    status TEXT DEFAULT 'vacant' CHECK (status IN ('vacant', 'occupied', 'hold', 'maintenance')),
    occupied_by_member_id UUID REFERENCES users(id) ON DELETE SET NULL,
    maintenance_reason TEXT,
    maintenance_until DATE,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT unique_seat_per_library_shift UNIQUE (library_id, seat_label, shift_id)
);

CREATE TRIGGER trigger_update_seats_updated_at
BEFORE UPDATE ON seats
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Memberships Table
CREATE TABLE IF NOT EXISTS memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE RESTRICT,
    shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE RESTRICT,
    seat_id UUID REFERENCES seats(id) ON DELETE SET NULL,
    plan_type TEXT NOT NULL CHECK (plan_type IN ('monthly', '3_month', '6_month')),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'trial', 'hold', 'expired', 'transferred', 'exited')),
    trial_used BOOLEAN DEFAULT false,
    discount_amount INTEGER DEFAULT 0,
    discount_reason TEXT,
    join_request_submitted_at TIMESTAMPTZ DEFAULT now(),
    approved_at TIMESTAMPTZ,
    hold_until DATE,
    exited_at TIMESTAMPTZ,
    transferred_from UUID REFERENCES memberships(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Attendance Table
CREATE TABLE IF NOT EXISTS attendance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id UUID NOT NULL REFERENCES memberships(id) ON DELETE CASCADE,
    member_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE RESTRICT,
    shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE RESTRICT,
    check_in_time TIMESTAMPTZ NOT NULL,
    check_out_time TIMESTAMPTZ,
    duration_minutes INTEGER,
    session_type TEXT DEFAULT 'normal' CHECK (session_type IN ('normal', 'manual', 'auto_checkout', 'incomplete', 'admin_edited')),
    edited_by_admin_id UUID REFERENCES users(id) ON DELETE SET NULL,
    edit_reason TEXT,
    qr_version INTEGER,
    offline_synced BOOLEAN DEFAULT false,
    device_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT chk_attendance_checkout_after_checkin
        CHECK (check_out_time IS NULL OR check_out_time >= check_in_time),
    CONSTRAINT chk_attendance_duration_nonneg
        CHECK (duration_minutes IS NULL OR duration_minutes >= 0)
);

-- Payments Table
CREATE TABLE IF NOT EXISTS payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id UUID NOT NULL REFERENCES memberships(id) ON DELETE CASCADE,
    member_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE RESTRICT,
    amount INTEGER NOT NULL,
    original_amount INTEGER,
    discount_amount INTEGER DEFAULT 0,
    discount_reason TEXT,
    method TEXT NOT NULL CHECK (method IN ('cash', 'upi')),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'rejected', 'disputed', 'written_off')),
    payment_date TIMESTAMPTZ NOT NULL,
    confirmed_by_admin_id UUID REFERENCES users(id) ON DELETE SET NULL,
    proof_url TEXT,
    upi_sender_name TEXT,
    ref_id TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Join Requests Table
CREATE TABLE IF NOT EXISTS join_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
    plan_type TEXT NOT NULL,
    payment_method TEXT,
    payment_proof_url TEXT,
    upi_sender_name TEXT,
    discount_amount INTEGER DEFAULT 0,
    discount_reason TEXT,
    requested_seat_id UUID REFERENCES seats(id) ON DELETE SET NULL,
    selected_addon_ids UUID[],
    is_renewal BOOLEAN NOT NULL DEFAULT false,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'expired', 'withdrawn')),
    payment_status TEXT NOT NULL DEFAULT 'unverified' CHECK (payment_status IN ('unverified', 'verified', 'rejected')),
    rejection_reason TEXT,
    existing_member_join_date DATE,
    created_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ DEFAULT (now() + interval '7 days')
);

-- Seat Change Requests Table
CREATE TABLE IF NOT EXISTS seat_change_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id UUID NOT NULL REFERENCES memberships(id) ON DELETE CASCADE,
    member_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    current_seat_id UUID REFERENCES seats(id) ON DELETE SET NULL,
    preferred_section TEXT,
    reason TEXT NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
    new_seat_id UUID REFERENCES seats(id) ON DELETE SET NULL,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Hold Requests Table
CREATE TABLE IF NOT EXISTS hold_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id UUID NOT NULL REFERENCES memberships(id) ON DELETE CASCADE,
    member_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    reason TEXT NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Transfers Table
CREATE TABLE IF NOT EXISTS transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    from_membership_id UUID REFERENCES memberships(id) ON DELETE SET NULL,
    to_membership_id UUID REFERENCES memberships(id) ON DELETE SET NULL,
    from_library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    to_library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    transfer_date TIMESTAMPTZ NOT NULL,
    initiated_by_admin_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Add-ons Table
CREATE TABLE IF NOT EXISTS add_ons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    price INTEGER NOT NULL,
    price_type TEXT NOT NULL CHECK (price_type IN ('one_time', 'monthly')),
    refundable_deposit INTEGER DEFAULT 0,
    max_available INTEGER,
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Member Add-ons Table
CREATE TABLE IF NOT EXISTS member_add_ons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id UUID NOT NULL REFERENCES memberships(id) ON DELETE CASCADE,
    add_on_id UUID NOT NULL REFERENCES add_ons(id) ON DELETE RESTRICT,
    deposit_paid INTEGER DEFAULT 0,
    deposit_refunded BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Referrals Table
CREATE TABLE IF NOT EXISTS referrals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_member_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    referred_member_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    referral_code_used TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'credited', 'cancelled')),
    reward_days INTEGER,
    credited_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Badges Table
CREATE TABLE IF NOT EXISTS badges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    badge_type TEXT NOT NULL CHECK (badge_type IN ('7_day_streak', '30_day_streak', 'early_bird', 'night_owl', 'top_of_week', '100_days_club', 'consistent')),
    earned_at TIMESTAMPTZ DEFAULT now(),
    library_id UUID REFERENCES libraries(id) ON DELETE CASCADE,
    CONSTRAINT unique_badge_per_member UNIQUE (member_id, badge_type)
);

-- Announcements Table
CREATE TABLE IF NOT EXISTS announcements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    admin_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    title TEXT,
    message TEXT NOT NULL,
    recipient_filter JSONB DEFAULT '{}',
    sent_at TIMESTAMPTZ DEFAULT now()
);

-- Announcement Reads Table
CREATE TABLE IF NOT EXISTS announcement_reads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    announcement_id UUID NOT NULL REFERENCES announcements(id) ON DELETE CASCADE,
    member_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    read_at TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT unique_announcement_read UNIQUE (announcement_id, member_id)
);

-- Queries Table
CREATE TABLE IF NOT EXISTS queries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    subject TEXT,
    type TEXT,
    message TEXT NOT NULL,
    screenshot_url TEXT,
    status TEXT DEFAULT 'open' CHECK (status IN ('open', 'replied', 'closed')),
    admin_reply TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    replied_at TIMESTAMPTZ
);

-- Notifications Table
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT,
    body TEXT,
    data JSONB DEFAULT '{}',
    sent_at TIMESTAMPTZ DEFAULT now(),
    read_at TIMESTAMPTZ
);

-- Audit Log Table
CREATE TABLE IF NOT EXISTS audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    library_id UUID REFERENCES libraries(id) ON DELETE CASCADE,
    action TEXT NOT NULL,
    details JSONB DEFAULT '{}',
    previous_value TEXT,
    new_value TEXT,
    ip_address INET,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Scheduled Closures Table
CREATE TABLE IF NOT EXISTS scheduled_closures (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    reason TEXT,
    notify_members BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Reviews Table
CREATE TABLE IF NOT EXISTS reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    member_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    membership_id UUID REFERENCES memberships(id),
    rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    review_text TEXT,
    admin_reply TEXT,
    admin_replied_at TIMESTAMPTZ,
    is_read_by_admin BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE (library_id, member_id)
);

CREATE TRIGGER trigger_update_reviews_updated_at
BEFORE UPDATE ON reviews
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- TRIGGER: Auto-update avg_rating and review_count on libraries
CREATE OR REPLACE FUNCTION fn_update_library_rating()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE libraries
  SET
    avg_rating = (
      SELECT COALESCE(ROUND(AVG(rating)::numeric, 1), 0)
      FROM reviews
      WHERE library_id = NEW.library_id
    ),
    review_count = (
      SELECT COUNT(*)
      FROM reviews
      WHERE library_id = NEW.library_id
    )
  WHERE id = NEW.library_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_library_rating ON reviews;
CREATE TRIGGER trigger_update_library_rating
  AFTER INSERT OR UPDATE OR DELETE ON reviews
  FOR EACH ROW
  EXECUTE FUNCTION fn_update_library_rating();

-- Expenditures Table
CREATE TABLE IF NOT EXISTS expenditures (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    amount NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    category TEXT NOT NULL CHECK (
        category IN (
            'rent', 'electricity', 'internet', 'water',
            'maintenance', 'salary', 'supplies', 'generator',
            'cleaning', 'security', 'taxes', 'miscellaneous'
        )
    ),
    expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
    note TEXT,
    notes TEXT, -- compatibility column for Flutter app
    receipt_url TEXT,
    is_recurring BOOLEAN DEFAULT false,
    added_by TEXT NOT NULL DEFAULT 'admin',
    is_deleted BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TRIGGER trigger_update_expenditures_updated_at
BEFORE UPDATE ON expenditures
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ------------------------------------------------------------
-- 2b. PHASE C RECONCILIATION TABLES
--     Referenced by code; folded in from loose migrations + drift.
--     (See silence_app/migrations/2026-06-11_phase_c_reconciliation.sql)
-- ------------------------------------------------------------

-- Settings Table (admin per-library / global key-value config)
CREATE TABLE IF NOT EXISTS settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id UUID REFERENCES libraries(id) ON DELETE CASCADE,
    scope TEXT NOT NULL,
    value JSONB NOT NULL DEFAULT '{}',
    updated_at TIMESTAMPTZ DEFAULT now()
);
-- library_id is NULLABLE (global scope) so the upsert key must treat NULLs as
-- equal, else the global row can't be matched on conflict (Postgres 15+).
CREATE UNIQUE INDEX IF NOT EXISTS uq_settings_admin_lib_scope
    ON settings (admin_id, library_id, scope) NULLS NOT DISTINCT;

-- Streaks Table (per member, per library; analytics cache)
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

-- Member Daily Stats Table (precomputed per-day attendance facts)
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

-- Leads Table (member-suggested new libraries; explore lead capture)
CREATE TABLE IF NOT EXISTS leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_name TEXT NOT NULL,
    location TEXT,
    owner_phone TEXT,
    suggested_by_member_id UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Verification Requests Table (library "verified badge" submissions)
CREATE TABLE IF NOT EXISTS verification_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending',
    reviewed_at TIMESTAMPTZ,
    admin_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Draft Members Table (admin's in-progress "add member" drafts)
CREATE TABLE IF NOT EXISTS draft_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    draft_data JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------
-- 3. INDEXES
-- ------------------------------------------------------------

-- Users Indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_referral_code ON users(referral_code);

-- Libraries Indexes
CREATE INDEX IF NOT EXISTS idx_libraries_owner ON libraries(owner_id);
CREATE INDEX IF NOT EXISTS idx_libraries_code ON libraries(library_code);
CREATE INDEX IF NOT EXISTS idx_libraries_city ON libraries(address_city);

-- Shifts Indexes
CREATE INDEX IF NOT EXISTS idx_shifts_library ON shifts(library_id);

-- Seats Indexes
CREATE INDEX IF NOT EXISTS idx_seats_library_shift ON seats(library_id, shift_id);
CREATE INDEX IF NOT EXISTS idx_seats_label ON seats(library_id, seat_label);

-- Memberships Indexes
CREATE INDEX IF NOT EXISTS idx_memberships_member ON memberships(member_id, status);
CREATE INDEX IF NOT EXISTS idx_memberships_library ON memberships(library_id, status);
CREATE INDEX IF NOT EXISTS idx_memberships_expiry ON memberships(end_date);
-- Integrity: at most one live membership per (member, library); one seat per live membership.
CREATE UNIQUE INDEX IF NOT EXISTS uq_membership_active_per_member_library
    ON memberships (member_id, library_id)
    WHERE status IN ('active', 'trial', 'hold');
CREATE UNIQUE INDEX IF NOT EXISTS uq_membership_active_seat
    ON memberships (seat_id)
    WHERE seat_id IS NOT NULL AND status IN ('active', 'trial');

-- Attendance Indexes
CREATE INDEX IF NOT EXISTS idx_attendance_member ON attendance(member_id, check_in_time);
CREATE INDEX IF NOT EXISTS idx_attendance_library_date ON attendance(library_id, check_in_time);

-- Payments Indexes
CREATE INDEX IF NOT EXISTS idx_payments_membership ON payments(membership_id);
CREATE INDEX IF NOT EXISTS idx_payments_member ON payments(member_id);

-- Join Requests Indexes
CREATE INDEX IF NOT EXISTS idx_join_requests_library_status ON join_requests(library_id, status);

-- Referrals Indexes
CREATE INDEX IF NOT EXISTS idx_referrals_referrer ON referrals(referrer_member_id);

-- Audit Log Indexes
CREATE INDEX IF NOT EXISTS idx_audit_library ON audit_log(library_id, created_at);

-- Reviews Indexes
CREATE INDEX IF NOT EXISTS idx_reviews_library_id ON reviews(library_id);
CREATE INDEX IF NOT EXISTS idx_reviews_member_id ON reviews(member_id);
CREATE INDEX IF NOT EXISTS idx_reviews_created ON reviews(created_at);

-- Expenditures Indexes
CREATE INDEX IF NOT EXISTS idx_expenditures_library_date ON expenditures(library_id, expense_date) WHERE is_deleted = false;

-- Phase C table indexes
CREATE INDEX IF NOT EXISTS idx_streaks_member_library ON streaks(member_id, library_id);
CREATE INDEX IF NOT EXISTS idx_mds_member_library_date ON member_daily_stats(member_id, library_id, date);
CREATE INDEX IF NOT EXISTS idx_verification_requests_library ON verification_requests(library_id);
CREATE INDEX IF NOT EXISTS idx_draft_members_library_id ON draft_members(library_id);
CREATE INDEX IF NOT EXISTS idx_draft_members_admin_id ON draft_members(admin_id);

-- ------------------------------------------------------------
-- 4. ROW LEVEL SECURITY (RLS) POLICIES
-- ------------------------------------------------------------

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE libraries ENABLE ROW LEVEL SECURITY;
ALTER TABLE shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE floors ENABLE ROW LEVEL SECURITY;
ALTER TABLE sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE seats ENABLE ROW LEVEL SECURITY;
ALTER TABLE memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE join_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE seat_change_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE hold_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE add_ons ENABLE ROW LEVEL SECURITY;
ALTER TABLE member_add_ons ENABLE ROW LEVEL SECURITY;
ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcement_reads ENABLE ROW LEVEL SECURITY;
ALTER TABLE queries ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE scheduled_closures ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenditures ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE streaks ENABLE ROW LEVEL SECURITY;
ALTER TABLE member_daily_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE verification_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE draft_members ENABLE ROW LEVEL SECURITY;

-- 4.1 Users Policies
CREATE POLICY "Users can view own profile" ON users
    FOR SELECT USING (auth.uid() = id);

-- P10-04: a library owner may read only users who are MEMBERS of a library they
-- own, plus users with a PENDING join request at one of their libraries (the
-- Requests tab reads applicant name/phone/photo via the member_id embed). The
-- cross-library existing-account lookup goes through the SECURITY DEFINER RPC
-- find_user_by_contact (returns one minimal row). Canonical copy of
-- migrations/2026-06-14_users_select_tenant_scope.sql.
CREATE POLICY "Admins can view library members" ON users
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM memberships m
            JOIN libraries l ON l.id = m.library_id
            WHERE m.member_id = users.id AND l.owner_id = auth.uid()
        )
        OR EXISTS (
            SELECT 1 FROM join_requests jr
            JOIN libraries l ON l.id = jr.library_id
            WHERE jr.member_id = users.id
              AND jr.status = 'pending'
              AND l.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can update own profile" ON users
    FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- A library owner records a member's photo / ID documents / details (Add-Member
-- wizard + member profile edit). The member's row is owned by the member, not
-- the owner, so the self-update policy above does not cover this. Scope it
-- through memberships so an owner can only touch users who are members of one of
-- their libraries. (see migrations/2026-06-12_users_owner_update_rls.sql)
CREATE POLICY "Owner can update their library members" ON users
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM memberships m
            JOIN libraries l ON l.id = m.library_id
            WHERE m.member_id = users.id AND l.owner_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM memberships m
            JOIN libraries l ON l.id = m.library_id
            WHERE m.member_id = users.id AND l.owner_id = auth.uid()
        )
    );

CREATE POLICY "Anyone can insert (signup)" ON users
    FOR INSERT WITH CHECK (true);

CREATE POLICY "No delete for regular users" ON users
    FOR DELETE USING (false);

-- 4.2 Libraries Policies
CREATE POLICY "Anyone can view active libraries" ON libraries
    FOR SELECT USING (status = 'active' OR status = 'setup' OR owner_id = auth.uid());

CREATE POLICY "Only owner can insert" ON libraries
    FOR INSERT WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Only owner can update" ON libraries
    FOR UPDATE USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Only owner can delete (only if status = setup)" ON libraries
    FOR DELETE USING (auth.uid() = owner_id AND status = 'setup');

-- 4.3 Shifts Policies
CREATE POLICY "Admins can manage shifts of their libraries" ON shifts
    FOR ALL USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Anyone can view shifts (for explore/join)" ON shifts
    FOR SELECT USING (true);

-- 4.4 Floors Policies
CREATE POLICY "Owner full access on floors" ON floors
    FOR ALL USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Read only for others on floors" ON floors
    FOR SELECT USING (true);

-- 4.5 Sections Policies
CREATE POLICY "Owner full access on sections" ON sections
    FOR ALL USING (EXISTS (SELECT 1 FROM floors JOIN libraries ON floors.library_id = libraries.id WHERE floors.id = floor_id AND libraries.owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM floors JOIN libraries ON floors.library_id = libraries.id WHERE floors.id = floor_id AND libraries.owner_id = auth.uid()));

CREATE POLICY "Read only for others on sections" ON sections
    FOR SELECT USING (true);

-- 4.6 Seats Policies
CREATE POLICY "Anyone can view seats" ON seats
    FOR SELECT USING (true);

CREATE POLICY "Owner can update seats" ON seats
    FOR UPDATE USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Owner can insert seats" ON seats
    FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Owner can delete seats" ON seats
    FOR DELETE USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

-- 4.7 Memberships Policies
CREATE POLICY "Member view own memberships" ON memberships
    FOR SELECT USING (member_id = auth.uid());

CREATE POLICY "Admin view all memberships of their libraries" ON memberships
    FOR SELECT USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Admin insert (add member manually)" ON memberships
    FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Admin update (approve, renew, hold, transfer)" ON memberships
    FOR UPDATE USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

-- P5-01: member self-exit goes through the SECURITY DEFINER exit_my_membership()
-- RPC (verifies ownership, releases seat, marks exited). The old open
-- "System can update USING(true)" policy is removed; admin writes stay covered by
-- the owner-scoped UPDATE policy above and server cron uses service_role.
-- Canonical copy of migrations/2026-06-18_memberships_member_exit_rpc.sql.
CREATE OR REPLACE FUNCTION public.exit_my_membership(p_membership_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid   uuid := auth.uid();
    v_owner uuid;
    v_seat  uuid;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not signed in' USING errcode = '42501';
    END IF;
    SELECT member_id, seat_id INTO v_owner, v_seat
      FROM public.memberships WHERE id = p_membership_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Membership not found' USING errcode = 'P0002';
    END IF;
    IF v_owner <> v_uid THEN
        RAISE EXCEPTION 'Not your membership' USING errcode = '42501';
    END IF;
    IF v_seat IS NOT NULL THEN
        UPDATE public.seats
           SET status = 'vacant', occupied_by_member_id = NULL
         WHERE id = v_seat;
    END IF;
    UPDATE public.memberships
       SET status = 'exited', exited_at = now()
     WHERE id = p_membership_id;
END;
$$;
REVOKE ALL ON FUNCTION public.exit_my_membership(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.exit_my_membership(uuid) TO authenticated;

-- 4.8 Attendance Policies
CREATE POLICY "Member view own attendance" ON attendance
    FOR SELECT USING (member_id = auth.uid());

CREATE POLICY "Admin view all attendance of their libraries" ON attendance
    FOR SELECT USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Member insert (check-in/out)" ON attendance
    FOR INSERT WITH CHECK (member_id = auth.uid());

CREATE POLICY "Admin insert (manual check-in)" ON attendance
    FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Admin update (edit session duration)" ON attendance
    FOR UPDATE USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Member update (check-out)" ON attendance
    FOR UPDATE USING (member_id = auth.uid())
    WITH CHECK (member_id = auth.uid());

-- 4.9 Payments Policies
CREATE POLICY "Member view own payments" ON payments
    FOR SELECT USING (member_id = auth.uid());

CREATE POLICY "Admin view all payments of their libraries" ON payments
    FOR SELECT USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Member insert (upload proof)" ON payments
    FOR INSERT WITH CHECK (member_id = auth.uid());

-- Owner records a member's payment via the Add-Member wizard / approval flow.
-- (member_id is the member, not the owner, so the member-insert policy above
-- does not cover this — see migrations/2026-06-12_payments_admin_insert_rls.sql)
CREATE POLICY "Admin insert payments for their libraries" ON payments
    FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Admin update status" ON payments
    FOR UPDATE USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

-- 4.10 Join Requests Policies
CREATE POLICY "Member view own requests" ON join_requests
    FOR SELECT USING (member_id = auth.uid());

CREATE POLICY "Admin view requests for their libraries" ON join_requests
    FOR SELECT USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Member insert new request" ON join_requests
    FOR INSERT WITH CHECK (member_id = auth.uid());

CREATE POLICY "Admin update (approve/reject)" ON join_requests
    FOR UPDATE USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

-- A member may withdraw their OWN pending request (and only to 'withdrawn').
CREATE POLICY "Member withdraw own pending request" ON join_requests
    FOR UPDATE
    USING (member_id = auth.uid() AND status = 'pending')
    WITH CHECK (member_id = auth.uid() AND status = 'withdrawn');

-- 4.11 Seat Change Requests Policies
CREATE POLICY "Member view own seat change requests" ON seat_change_requests
    FOR SELECT USING (member_id = auth.uid());

CREATE POLICY "Admin view seat change requests" ON seat_change_requests
    FOR SELECT USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Member insert seat change request" ON seat_change_requests
    FOR INSERT WITH CHECK (member_id = auth.uid());

CREATE POLICY "Admin update seat change request" ON seat_change_requests
    FOR UPDATE USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

-- 4.12 Hold Requests Policies
CREATE POLICY "Member view own hold requests" ON hold_requests
    FOR SELECT USING (member_id = auth.uid());

CREATE POLICY "Admin view hold requests" ON hold_requests
    FOR SELECT USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Member insert hold request" ON hold_requests
    FOR INSERT WITH CHECK (member_id = auth.uid());

CREATE POLICY "Admin update hold request" ON hold_requests
    FOR UPDATE USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

-- 4.13 Transfers Policies
CREATE POLICY "Member view own transfers" ON transfers
    FOR SELECT USING (member_id = auth.uid());

CREATE POLICY "Admin view transfers" ON transfers
    FOR SELECT USING (EXISTS (SELECT 1 FROM libraries WHERE id = from_library_id AND owner_id = auth.uid()) OR EXISTS (SELECT 1 FROM libraries WHERE id = to_library_id AND owner_id = auth.uid()));

CREATE POLICY "Admin insert transfer" ON transfers
    FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = from_library_id AND owner_id = auth.uid()));

-- 4.14 Add-ons Policies
CREATE POLICY "Anyone can view add-ons" ON add_ons
    FOR SELECT USING (true);

CREATE POLICY "Owner manage add-ons" ON add_ons
    FOR ALL USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

-- 4.15 Member Add-ons Policies
CREATE POLICY "Member view own member add-ons" ON member_add_ons
    FOR SELECT USING (EXISTS (SELECT 1 FROM memberships WHERE id = membership_id AND member_id = auth.uid()));

CREATE POLICY "Admin view member add-ons" ON member_add_ons
    FOR SELECT USING (EXISTS (SELECT 1 FROM add_ons JOIN libraries ON add_ons.library_id = libraries.id WHERE add_ons.id = add_on_id AND libraries.owner_id = auth.uid()));

CREATE POLICY "Admin manage member add-ons" ON member_add_ons
    FOR ALL USING (EXISTS (SELECT 1 FROM add_ons JOIN libraries ON add_ons.library_id = libraries.id WHERE add_ons.id = add_on_id AND libraries.owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM add_ons JOIN libraries ON add_ons.library_id = libraries.id WHERE add_ons.id = add_on_id AND libraries.owner_id = auth.uid()));

-- 4.16 Referrals Policies
CREATE POLICY "Member view own referrals" ON referrals
    FOR SELECT USING (referrer_member_id = auth.uid() OR referred_member_id = auth.uid());

CREATE POLICY "Admin view referrals" ON referrals
    FOR SELECT USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Scoped insert referrals" ON referrals
    FOR INSERT WITH CHECK (
        referrer_member_id = auth.uid() OR referred_member_id = auth.uid()
    ); -- P5-08; canonical copy of migrations/2026-06-18_actor_scope_inserts.sql

-- 4.17 Badges Policies
CREATE POLICY "Member view own badges" ON badges
    FOR SELECT USING (member_id = auth.uid());

CREATE POLICY "Admin view member badges" ON badges
    FOR SELECT USING (EXISTS (SELECT 1 FROM memberships WHERE memberships.member_id = badges.member_id AND library_id = badges.library_id AND EXISTS (SELECT 1 FROM libraries WHERE id = memberships.library_id AND owner_id = auth.uid())));

CREATE POLICY "Scoped insert badges" ON badges
    FOR INSERT WITH CHECK (
        member_id = auth.uid()
        OR EXISTS (SELECT 1 FROM libraries l
                   WHERE l.id = badges.library_id AND l.owner_id = auth.uid())
    ); -- P5-08

-- 4.18 Announcements Policies
CREATE POLICY "Admin insert announcements" ON announcements
    FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Admin update/delete announcements" ON announcements
    FOR UPDATE USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Members view announcements" ON announcements
    FOR SELECT USING (EXISTS (SELECT 1 FROM memberships WHERE memberships.library_id = announcements.library_id AND memberships.member_id = auth.uid()));

-- 4.19 Announcement Reads Policies
CREATE POLICY "Member insert own read" ON announcement_reads
    FOR INSERT WITH CHECK (member_id = auth.uid());

CREATE POLICY "Member view own reads" ON announcement_reads
    FOR SELECT USING (member_id = auth.uid());

CREATE POLICY "Admin view announcement reads" ON announcement_reads
    FOR SELECT USING (EXISTS (SELECT 1 FROM announcements WHERE announcements.id = announcement_id AND EXISTS (SELECT 1 FROM libraries WHERE libraries.id = announcements.library_id AND libraries.owner_id = auth.uid())));

-- 4.20 Queries Policies
CREATE POLICY "Member insert query" ON queries
    FOR INSERT WITH CHECK (member_id = auth.uid());

CREATE POLICY "Member view own queries" ON queries
    FOR SELECT USING (member_id = auth.uid());

CREATE POLICY "Admin view queries" ON queries
    FOR SELECT USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Admin update queries" ON queries
    FOR UPDATE USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

-- 4.21 Notifications Policies
CREATE POLICY "User view own notifications" ON notifications
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Scoped insert notifications" ON notifications
    FOR INSERT WITH CHECK (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM memberships m
            JOIN libraries l ON l.id = m.library_id
            WHERE m.member_id = notifications.user_id AND l.owner_id = auth.uid()
        )
        OR EXISTS (
            SELECT 1 FROM join_requests jr
            JOIN libraries l ON l.id = jr.library_id
            WHERE jr.member_id = notifications.user_id AND l.owner_id = auth.uid()
        )
        OR EXISTS (
            SELECT 1 FROM libraries l
            WHERE l.owner_id = notifications.user_id
              AND (
                EXISTS (SELECT 1 FROM memberships m
                        WHERE m.library_id = l.id AND m.member_id = auth.uid())
                OR EXISTS (SELECT 1 FROM join_requests jr
                           WHERE jr.library_id = l.id AND jr.member_id = auth.uid())
              )
        )
    ); -- P5-08

CREATE POLICY "User update read status" ON notifications
    FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- 4.22 Audit Log Policies
CREATE POLICY "Admin view own audit log" ON audit_log
    FOR SELECT USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Scoped insert audit log" ON audit_log
    FOR INSERT WITH CHECK (admin_id = auth.uid()); -- P5-08

-- 4.23 Scheduled Closures Policies
CREATE POLICY "Admin manage scheduled closures" ON scheduled_closures
    FOR ALL USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

CREATE POLICY "Members view scheduled closures" ON scheduled_closures
    FOR SELECT USING (EXISTS (SELECT 1 FROM memberships WHERE memberships.library_id = scheduled_closures.library_id AND memberships.member_id = auth.uid()));

-- 4.24 Reviews Policies
CREATE POLICY "member_read_reviews" ON reviews
  FOR SELECT
  USING (
    library_id IN (
      SELECT library_id FROM memberships WHERE member_id = auth.uid()
    )
  );

CREATE POLICY "member_insert_own_review" ON reviews
  FOR INSERT
  WITH CHECK (member_id = auth.uid());

CREATE POLICY "member_update_own_review" ON reviews
  FOR UPDATE
  USING (member_id = auth.uid())
  WITH CHECK (member_id = auth.uid());

CREATE POLICY "admin_manage_reviews" ON reviews
  FOR ALL
  USING (
    library_id IN (
      SELECT id FROM libraries WHERE owner_id = auth.uid()
    )
  );

CREATE POLICY "public_read_active_library_reviews" ON reviews
  FOR SELECT
  USING (
    library_id IN (
      SELECT id FROM libraries WHERE status = 'active'
    )
  );

-- 4.25 Expenditures Policies
CREATE POLICY "admin_manage_expenditures" ON expenditures
  FOR ALL
  USING (library_id IN (SELECT id FROM libraries WHERE owner_id = auth.uid()))
  WITH CHECK (library_id IN (SELECT id FROM libraries WHERE owner_id = auth.uid()));

-- 4.26 Settings Policies (Phase C)
CREATE POLICY "Admin manage own settings" ON settings
    FOR ALL USING (admin_id = auth.uid())
    WITH CHECK (admin_id = auth.uid());

-- 4.27 Streaks Policies (Phase C)
CREATE POLICY "Member view own streaks" ON streaks
    FOR SELECT USING (member_id = auth.uid());
CREATE POLICY "Admin view library streaks" ON streaks
    FOR SELECT USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

-- 4.28 Member Daily Stats Policies (Phase C)
CREATE POLICY "Member view own daily stats" ON member_daily_stats
    FOR SELECT USING (member_id = auth.uid());
CREATE POLICY "Admin view library daily stats" ON member_daily_stats
    FOR SELECT USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

-- 4.29 Leads Policies (Phase C)
CREATE POLICY "Member submit lead" ON leads
    FOR INSERT WITH CHECK (suggested_by_member_id = auth.uid());
CREATE POLICY "Member view own leads" ON leads
    FOR SELECT USING (suggested_by_member_id = auth.uid());

-- 4.30 Verification Requests Policies (Phase C)
CREATE POLICY "Owner manage verification requests" ON verification_requests
    FOR ALL USING (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

-- 4.31 Draft Members Policies (Phase C)
CREATE POLICY "Admins full access on own drafts" ON draft_members
    FOR ALL
    USING (admin_id = auth.uid()
           OR EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()))
    WITH CHECK (admin_id = auth.uid()
           OR EXISTS (SELECT 1 FROM libraries WHERE id = library_id AND owner_id = auth.uid()));

-- ============================================================================
-- 5. Privileged users-column locks — role (P6-02) + subscription (P6-06) +
--    verification flags. Canonical copy of
--    migrations/2026-06-18_lock_user_privileged_columns.sql.
--    role/subscription/verified can only change via change_my_role() /
--    start_my_trial() (which set app.allow_privileged_update); the trigger
--    blocks any other direct change.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.guard_user_privileged_columns()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF current_setting('app.allow_privileged_update', true) IS DISTINCT FROM 'on' THEN
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
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_user_privileged_columns ON public.users;
CREATE TRIGGER trg_guard_user_privileged_columns
    BEFORE UPDATE OF role, subscription_plan, subscription_status,
                     subscription_expiry, phone_verified, email_verified
    ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION public.guard_user_privileged_columns();

CREATE OR REPLACE FUNCTION public.start_my_trial()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid  uuid := auth.uid();
    v_role text;
    v_plan text;
    v_exp  timestamptz;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not signed in' USING errcode = '42501';
    END IF;
    SELECT role, subscription_plan, subscription_expiry
      INTO v_role, v_plan, v_exp
      FROM public.users WHERE id = v_uid;
    IF v_role IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'Only admins have a subscription' USING errcode = '42501';
    END IF;
    IF v_exp IS NOT NULL OR v_plan IS NOT NULL THEN
        RETURN;
    END IF;
    PERFORM set_config('app.allow_privileged_update', 'on', true);
    UPDATE public.users SET
        subscription_plan   = 'free',
        subscription_status = 'active',
        subscription_expiry = now() + interval '30 days',
        updated_at          = now()
      WHERE id = v_uid;
END;
$$;
REVOKE ALL ON FUNCTION public.start_my_trial() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_my_trial() TO authenticated;

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
    IF v_created IS NULL OR v_created < now() - interval '7 days' THEN
        RAISE EXCEPTION 'Role can only be changed within 7 days of signup'
            USING errcode = 'P0001';
    END IF;

    DELETE FROM public.attendance            WHERE member_id  = v_uid;
    DELETE FROM public.payments              WHERE member_id  = v_uid;
    DELETE FROM public.seat_change_requests  WHERE member_id  = v_uid;
    DELETE FROM public.hold_requests         WHERE member_id  = v_uid;
    DELETE FROM public.join_requests         WHERE member_id  = v_uid;
    DELETE FROM public.reviews               WHERE member_id  = v_uid;
    DELETE FROM public.badges                WHERE member_id  = v_uid;
    DELETE FROM public.referrals             WHERE referrer_member_id = v_uid OR referred_member_id = v_uid;
    DELETE FROM public.queries               WHERE member_id  = v_uid;
    DELETE FROM public.notifications         WHERE user_id    = v_uid;
    DELETE FROM public.transfers             WHERE member_id  = v_uid;
    BEGIN DELETE FROM public.streaks            WHERE member_id = v_uid; EXCEPTION WHEN undefined_table THEN NULL; END;
    BEGIN DELETE FROM public.member_daily_stats WHERE member_id = v_uid; EXCEPTION WHEN undefined_table THEN NULL; END;
    UPDATE public.seats SET status = 'vacant', occupied_by_member_id = NULL
        WHERE occupied_by_member_id = v_uid;
    DELETE FROM public.memberships           WHERE member_id  = v_uid;
    BEGIN DELETE FROM public.settings    WHERE admin_id = v_uid; EXCEPTION WHEN undefined_table THEN NULL; END;
    DELETE FROM public.announcements         WHERE admin_id   = v_uid;
    DELETE FROM public.audit_log             WHERE admin_id   = v_uid;
    DELETE FROM public.libraries             WHERE owner_id   = v_uid;

    PERFORM set_config('app.allow_privileged_update', 'on', true);
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
