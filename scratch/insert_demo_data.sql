-- SQL Script: Seeding Demo Data for Azad Library (library_id: '6bdd5d6a-29e5-4152-91c2-ce04c86d1f59')
-- Run this in your Supabase SQL Editor (https://supabase.com/dashboard/project/kndeshxeerldamafweru/sql/new)

-- 1. Insert/Update Users (Admin & Members)
INSERT INTO users (id, email, full_name, nickname, role, phone, gender, exam_category)
VALUES 
  ('5db67d18-fd2b-45b0-a25f-f95644ab9def', 'owner@silence.com', 'Azad Owner', 'Azad', 'admin', '9166658636', 'male', NULL),
  ('a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', 'member1@silence.com', 'Ashish Sharma', 'Ashish', 'member', '9876543210', 'male', 'UPSC'),
  ('b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e', 'member2@silence.com', 'Priya Patel', 'Priya', 'member', '9876543211', 'female', 'CAT')
ON CONFLICT (id) DO UPDATE 
SET 
  email = EXCLUDED.email,
  full_name = EXCLUDED.full_name,
  nickname = EXCLUDED.nickname,
  role = EXCLUDED.role,
  phone = EXCLUDED.phone,
  gender = EXCLUDED.gender,
  exam_category = EXCLUDED.exam_category;

-- 2. Insert Memberships
INSERT INTO memberships (id, member_id, library_id, shift_id, seat_id, plan_type, start_date, end_date, status)
VALUES
  ('11111111-2222-3333-4444-555555555555', 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '6bdd5d6a-29e5-4152-91c2-ce04c86d1f59', '9fd014c0-7b17-42f5-a2a5-e26c55adf65a', '60f8c201-3d6f-4352-8732-25e8be534e9c', 'Monthly', '2026-06-01', '2026-06-30', 'active'),
  ('22222222-3333-4444-5555-666666666666', 'b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e', '6bdd5d6a-29e5-4152-91c2-ce04c86d1f59', '9fd014c0-7b17-42f5-a2a5-e26c55adf65a', '60f8c201-3d6f-4352-8732-25e8be534e9c', 'Monthly', '2026-06-01', '2026-06-30', 'active')
ON CONFLICT (id) DO NOTHING;

-- 3. Insert Payments
INSERT INTO payments (id, membership_id, member_id, library_id, amount, method, status, payment_date, confirmed_by_admin_id)
VALUES
  ('33333333-4444-5555-6666-777777777777', '11111111-2222-3333-4444-555555555555', 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '6bdd5d6a-29e5-4152-91c2-ce04c86d1f59', 1200, 'UPI', 'confirmed', '2026-06-02T10:00:00Z', '5db67d18-fd2b-45b0-a25f-f95644ab9def'),
  ('44444444-5555-6666-7777-888888888888', '22222222-3333-4444-5555-666666666666', 'b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e', '6bdd5d6a-29e5-4152-91c2-ce04c86d1f59', 1500, 'Cash', 'pending', '2026-06-02T11:00:00Z', NULL)
ON CONFLICT (id) DO NOTHING;

-- 4. Insert Attendance check-in
INSERT INTO attendance (id, membership_id, member_id, library_id, shift_id, check_in_time, check_out_time, session_type, qr_version)
VALUES
  ('55555555-6666-7777-8888-999999999999', '11111111-2222-3333-4444-555555555555', 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '6bdd5d6a-29e5-4152-91c2-ce04c86d1f59', '9fd014c0-7b17-42f5-a2a5-e26c55adf65a', '2026-06-02T08:30:00Z', NULL, 'normal', 1)
ON CONFLICT (id) DO NOTHING;

-- 5. Set seat status to occupied
UPDATE seats 
SET status = 'occupied', occupied_by_member_id = 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d'
WHERE id = '60f8c201-3d6f-4352-8732-25e8be534e9c';
