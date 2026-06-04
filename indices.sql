-- Indexes for optimizing query performance on library_id fields

-- Index on memberships table
CREATE INDEX IF NOT EXISTS idx_memberships_library_id ON memberships(library_id);

-- Index on seats table
CREATE INDEX IF NOT EXISTS idx_seats_library_id ON seats(library_id);

-- Index on attendance table
CREATE INDEX IF NOT EXISTS idx_attendance_library_id ON attendance(library_id);

-- Index on shifts table
CREATE INDEX IF NOT EXISTS idx_shifts_library_id ON shifts(library_id);

-- Index on floors table
CREATE INDEX IF NOT EXISTS idx_floors_library_id ON floors(library_id);

-- Index on sections table
CREATE INDEX IF NOT EXISTS idx_sections_library_id ON sections(library_id);

-- Index on announcements table
CREATE INDEX IF NOT EXISTS idx_announcements_library_id ON announcements(library_id);
