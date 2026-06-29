-- ============================================================================
-- 2026-07-02 — payments performance index
-- ============================================================================
--
-- Hot read paths filter payments by (library_id, status) and often a date:
--   • Admin Home revenue   : library_id + status='confirmed' + payment_date >= month
--   • Admin Home dues       : library_id + status='pending'
--   • Analytics / reports   : library_id + status + payment_date range
--
-- Existing indexes are only on membership_id and member_id, so these queries
-- do a sequential scan of all payments for the library. This composite index
-- lets Postgres jump straight to the matching rows (the reel's tip #1).
--
-- Additive + idempotent. No data change.
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_payments_library_status_date
    ON public.payments (library_id, status, payment_date);

-- ============================================================================
-- VERIFY:
--   EXPLAIN ANALYZE SELECT amount FROM payments
--     WHERE library_id = '<lib>' AND status = 'pending';
--   → should show an Index Scan using idx_payments_library_status_date.
-- ROLLBACK: DROP INDEX IF EXISTS public.idx_payments_library_status_date;
-- ============================================================================
