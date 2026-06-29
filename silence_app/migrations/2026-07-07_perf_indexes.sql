-- ============================================================================
-- 2026-07-07 — performance indexes (audit P1: missing composite/functional idx)
-- ============================================================================
--
-- PROBLEM: several hot list/filter queries do sequential scans as data grows
-- (notification center, query inbox, closures, hold/seat-change request tabs,
-- audit-log screen, per-day attendance rollups). At a few hundred rows this is
-- invisible; past a few thousand it shows up as the "atak-atak" lag the user
-- reported.
--
-- FIX: additive composite + one functional index. Pure performance — no schema
-- or behaviour change, near-zero risk. Idempotent (IF NOT EXISTS). Apply in the
-- Supabase SQL editor.
--
-- NOTE: audit_log has no `category` column (it has `action` + `library_id`); the
-- audit-log screen filters by library and orders by recency, so we index
-- (library_id, created_at) instead.
-- ============================================================================

-- Notification center: unread-first per user.
CREATE INDEX IF NOT EXISTS idx_notifications_user_read
    ON notifications (user_id, read_at);

-- Member query inbox: open/replied filter per library.
CREATE INDEX IF NOT EXISTS idx_queries_library_status
    ON queries (library_id, status, created_at);

-- Scheduled closures: date-range lookups per library.
CREATE INDEX IF NOT EXISTS idx_scheduled_closures_library_dates
    ON scheduled_closures (library_id, start_date, end_date);

-- Hold requests tab: pending-first per library.
CREATE INDEX IF NOT EXISTS idx_hold_requests_library_status
    ON hold_requests (library_id, status, created_at);

-- Seat-change requests tab: pending-first per library.
CREATE INDEX IF NOT EXISTS idx_seat_change_library_status
    ON seat_change_requests (library_id, status, created_at);

-- Audit-log screen: recent-first per library.
CREATE INDEX IF NOT EXISTS idx_audit_log_library_created
    ON audit_log (library_id, created_at);

-- Per-day attendance rollups in IST (analytics / daily counts per library).
CREATE INDEX IF NOT EXISTS idx_attendance_library_ist_date
    ON attendance (library_id, ((check_in_time AT TIME ZONE 'Asia/Kolkata')::date));

-- ============================================================================
-- VERIFY (optional): EXPLAIN ANALYZE the notification/query/closure/request
--   list queries and confirm an Index Scan replaces the Seq Scan.
-- ROLLBACK:
--   DROP INDEX IF EXISTS idx_notifications_user_read;
--   DROP INDEX IF EXISTS idx_queries_library_status;
--   DROP INDEX IF EXISTS idx_scheduled_closures_library_dates;
--   DROP INDEX IF EXISTS idx_hold_requests_library_status;
--   DROP INDEX IF EXISTS idx_seat_change_library_status;
--   DROP INDEX IF EXISTS idx_audit_log_library_created;
--   DROP INDEX IF EXISTS idx_attendance_library_ist_date;
-- ============================================================================
