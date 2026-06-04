-- Create reviews table
CREATE TABLE IF NOT EXISTS reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    member_id UUID NOT NULL REFERENCES users(id),
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    admin_reply TEXT,
    replied_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT unique_member_library_review UNIQUE (member_id, library_id)
);

-- Add indexes for performance optimization
CREATE INDEX IF NOT EXISTS idx_reviews_library ON reviews(library_id);
CREATE INDEX IF NOT EXISTS idx_reviews_member ON reviews(member_id);
CREATE INDEX IF NOT EXISTS idx_reviews_rating ON reviews(rating);

-- Add emergency_phone column to libraries if not exists
ALTER TABLE libraries ADD COLUMN IF NOT EXISTS emergency_phone TEXT;

-- Add location_link column to libraries if not exists
ALTER TABLE libraries ADD COLUMN IF NOT EXISTS location_link TEXT;
