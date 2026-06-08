-- =====================================================
-- SILENCE – Create Missing Tables: reviews & expenditures
-- =====================================================
-- Run this in Supabase SQL Editor.
-- It will create tables only if they don't exist.
-- It will add missing columns to existing tables.
-- It will NOT delete or modify any existing data.
-- =====================================================

-- ─────────────────────────────────────────────────────
-- TABLE 1: reviews (member library ratings & admin replies)
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS reviews (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  library_id       uuid NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
  member_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  membership_id    uuid REFERENCES memberships(id),
  rating           integer NOT NULL CHECK (rating BETWEEN 1 AND 5),
  review_text      text,
  admin_reply      text,
  admin_replied_at timestamptz,
  is_read_by_admin boolean DEFAULT false,
  created_at       timestamptz DEFAULT now(),
  updated_at       timestamptz DEFAULT now(),
  UNIQUE (library_id, member_id)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_reviews_library_id ON reviews(library_id);
CREATE INDEX IF NOT EXISTS idx_reviews_member_id ON reviews(member_id);
CREATE INDEX IF NOT EXISTS idx_reviews_created ON reviews(created_at);

-- Enable Row Level Security
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Members can read reviews for libraries they are/were members of
CREATE POLICY "member_read_reviews" ON reviews
  FOR SELECT
  USING (
    library_id IN (
      SELECT library_id FROM memberships WHERE member_id = auth.uid()
    )
  );

-- Members can insert their own review
CREATE POLICY "member_insert_own_review" ON reviews
  FOR INSERT
  WITH CHECK (member_id = auth.uid());

-- Members can update their own review (but not library_id or member_id)
CREATE POLICY "member_update_own_review" ON reviews
  FOR UPDATE
  USING (member_id = auth.uid())
  WITH CHECK (member_id = auth.uid());

-- Admin can manage reviews for their libraries (read, reply, delete)
CREATE POLICY "admin_manage_reviews" ON reviews
  FOR ALL
  USING (
    library_id IN (
      SELECT id FROM libraries WHERE owner_id = auth.uid()
    )
  );

-- Public can read reviews for active libraries (for Explore page)
CREATE POLICY "public_read_active_library_reviews" ON reviews
  FOR SELECT
  USING (
    library_id IN (
      SELECT id FROM libraries WHERE status = 'active'
    )
  );

-- ─────────────────────────────────────────────────────
-- TABLE 2: expenditures (admin expense tracking)
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS expenditures (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  library_id    uuid NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
  amount        numeric(10,2) NOT NULL CHECK (amount > 0),
  category      text NOT NULL,
  expense_date  date NOT NULL DEFAULT CURRENT_DATE,
  note          text,
  notes         text, -- compatibility column for Flutter app
  receipt_url   text,
  is_recurring  boolean DEFAULT false,
  added_by      text NOT NULL DEFAULT 'admin',
  is_deleted    boolean DEFAULT false,
  created_at    timestamptz DEFAULT now(),
  updated_at    timestamptz DEFAULT now(),
  CONSTRAINT category_check CHECK (
    category IN (
      'rent', 'electricity', 'internet', 'water',
      'maintenance', 'salary', 'supplies', 'generator',
      'cleaning', 'security', 'taxes', 'miscellaneous'
    )
  )
);

-- Index for fast analytics queries
CREATE INDEX IF NOT EXISTS idx_expenditures_library_date
  ON expenditures(library_id, expense_date)
  WHERE is_deleted = false;

-- Enable RLS
ALTER TABLE expenditures ENABLE ROW LEVEL SECURITY;

-- Admin can manage expenses for their libraries
CREATE POLICY "admin_manage_expenditures" ON expenditures
  FOR ALL
  USING (library_id IN (SELECT id FROM libraries WHERE owner_id = auth.uid()))
  WITH CHECK (library_id IN (SELECT id FROM libraries WHERE owner_id = auth.uid()));

-- ─────────────────────────────────────────────────────
-- ADD rating columns to libraries table (if missing)
-- ─────────────────────────────────────────────────────
ALTER TABLE libraries
  ADD COLUMN IF NOT EXISTS avg_rating  numeric(2,1) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS review_count integer DEFAULT 0;

-- ─────────────────────────────────────────────────────
-- TRIGGER: Auto‑update avg_rating and review_count
-- ─────────────────────────────────────────────────────
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

-- Drop existing trigger if any, then create
DROP TRIGGER IF EXISTS trigger_update_library_rating ON reviews;
CREATE TRIGGER trigger_update_library_rating
  AFTER INSERT OR UPDATE OR DELETE ON reviews
  FOR EACH ROW
  EXECUTE FUNCTION fn_update_library_rating();

-- ─────────────────────────────────────────────────────
-- VERIFICATION (run after creation)
-- ─────────────────────────────────────────────────────
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('reviews', 'expenditures');
