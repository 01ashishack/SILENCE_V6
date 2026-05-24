-- ============================================================
-- SILENCE Offline Storage Schema (SQLite)
-- Used for: Offline scan queue + Read cache
-- Platforms: Android (SQLite via sqflite), iOS (SQLite), Web (IndexedDB)
-- ============================================================

-- ------------------------------------------------------------
-- 1. OFFLINE SCAN QUEUE (Write Queue)
-- Stores scans that haven't been synced to Supabase yet.
-- Max 500 rows enforced by application logic.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS offline_scan_queue (
    id TEXT PRIMARY KEY,                     -- local UUID
    type TEXT NOT NULL,                      -- 'checkin' or 'checkout'
    library_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    shift_id TEXT NOT NULL,
    qr_version INTEGER NOT NULL,
    timestamp TEXT NOT NULL,                 -- ISO 8601 string
    device_id TEXT,
    retry_count INTEGER DEFAULT 0,
    synced INTEGER DEFAULT 0,                -- 0 = pending, 1 = synced
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Index for pending scans (fast sync)
CREATE INDEX idx_offline_queue_pending ON offline_scan_queue(synced, created_at);

-- Index for member+shift to detect double scans offline
CREATE INDEX idx_offline_queue_member_shift ON offline_scan_queue(member_id, shift_id, timestamp);

-- ------------------------------------------------------------
-- 2. READ CACHE - MEMBERS (Admin only, max 200 rows)
-- Stores recently active members for offline admin view.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cache_members (
    id TEXT PRIMARY KEY,                     -- member_id (same as Supabase)
    library_id TEXT NOT NULL,
    full_name TEXT NOT NULL,
    phone TEXT,
    photo_url TEXT,
    status TEXT,                             -- 'active', 'expired', 'hold', 'trial'
    seat_label TEXT,
    shift_name TEXT,
    expiry_date TEXT,
    last_seen TEXT,                          -- last check-in time
    cached_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Index for library-based queries
CREATE INDEX idx_cache_members_library ON cache_members(library_id);

-- Limit: application will keep only 200 most recent (by last_seen)

-- ------------------------------------------------------------
-- 3. READ CACHE - TODAY'S ATTENDANCE (Admin)
-- Stores check-ins for the current day for each library.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cache_attendance_today (
    id TEXT PRIMARY KEY,                     -- local row id
    library_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    member_name TEXT,
    seat_label TEXT,
    check_in_time TEXT,
    check_out_time TEXT,
    status TEXT,                             -- 'checked_in', 'checked_out'
    session_type TEXT,                       -- 'normal', 'manual', 'auto_checkout'
    cached_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Index for library+date
CREATE INDEX idx_cache_attendance_library ON cache_attendance_today(library_id);

-- Application will replace all rows for a library on each cache refresh

-- ------------------------------------------------------------
-- 4. READ CACHE - SEAT GRID (Admin)
-- Stores seat occupancy for a specific shift (last viewed).
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cache_seat_grid (
    id TEXT PRIMARY KEY,
    library_id TEXT NOT NULL,
    shift_id TEXT NOT NULL,
    floor_id TEXT,
    section_id TEXT,
    seat_label TEXT NOT NULL,
    seat_status TEXT,                        -- 'vacant', 'occupied', 'hold', 'maintenance'
    occupied_by_member_name TEXT,
    occupied_by_member_id TEXT,
    cached_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Index for fast retrieval by library+shift
CREATE INDEX idx_cache_seat_grid_library_shift ON cache_seat_grid(library_id, shift_id);

-- Application caches current shift's grid; max rows = total seats in that shift

-- ------------------------------------------------------------
-- 5. READ CACHE - MEMBER OWN DATA (Member offline view)
-- Stores member's own memberships and recent attendance.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cache_member_memberships (
    id TEXT PRIMARY KEY,
    member_id TEXT NOT NULL,
    library_id TEXT NOT NULL,
    library_name TEXT,
    seat_label TEXT,
    shift_name TEXT,
    plan_type TEXT,
    start_date TEXT,
    end_date TEXT,
    status TEXT,
    days_remaining INTEGER,
    dues_amount INTEGER,
    cached_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS cache_member_attendance (
    id TEXT PRIMARY KEY,
    member_id TEXT NOT NULL,
    library_id TEXT,
    check_in_time TEXT,
    check_out_time TEXT,
    duration_minutes INTEGER,
    session_type TEXT,
    date TEXT,                               -- YYYY-MM-DD for quick lookup
    cached_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_cache_member_attendance_date ON cache_member_attendance(member_id, date);

-- Limit: last 30 days of attendance

-- ------------------------------------------------------------
-- 6. SYNC METADATA (Track last sync times and cache versions)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sync_metadata (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Insert default values
INSERT OR IGNORE INTO sync_metadata (key, value) VALUES 
    ('last_member_sync', '1970-01-01T00:00:00Z'),
    ('last_attendance_sync', '1970-01-01T00:00:00Z'),
    ('last_seatgrid_sync', '1970-01-01T00:00:00Z'),
    ('cache_version_members', '1'),
    ('cache_version_seatgrid', '1');

-- ============================================================
-- IndexedDB Schema Equivalent (for Web / React Native Web)
-- ============================================================
/*
Database Name: silence_offline_db
Version: 1

Object Stores:
1. offline_scan_queue (keyPath: id)
   - indexes: synced, member_shift (compound: member_id, shift_id, timestamp)
2. cache_members (keyPath: id)
   - indexes: library_id
3. cache_attendance_today (keyPath: id)
   - indexes: library_id
4. cache_seat_grid (keyPath: id)
   - indexes: library_shift (compound: library_id, shift_id)
5. cache_member_memberships (keyPath: id)
   - indexes: member_id
6. cache_member_attendance (keyPath: id)
   - indexes: member_id, date
7. sync_metadata (keyPath: key)
*/

-- ============================================================
-- Sync Algorithm (Application Logic)
-- ============================================================
/*
On app startup with internet:
1. Sync offline_scan_queue:
   - Fetch all rows where synced = 0, order by created_at ASC (FIFO)
   - For each row, call Supabase RPC to insert attendance record
   - If success: update synced = 1
   - If conflict (duplicate): delete row
   - If network error: keep row, increment retry_count (max 3)
2. After sync, show toast: "X scans synced"
3. Refresh read caches:
   - For admin: fetch latest 200 members (by last_seen), today's attendance, seat grid for current shift
   - For member: fetch own memberships + last 30 days attendance
   - Replace cache tables (delete old, insert new)
   - Update sync_metadata with timestamps

On app startup without internet:
1. Load all caches from local DB
2. Display cached data with "Offline Mode" banner
3. Accept new scans, add to offline_scan_queue
4. Block operations that require internet (join request, announcement send, etc.)

Offline queue full (500 rows):
- Block new scans, show alert: "Offline storage full. Please reconnect to internet."
- Do NOT discard silently.
*/