-- ============================================================================
-- 2026-06-18 — Allow 'free' as a subscription_plan value
-- ============================================================================
--
-- The new-admin "30-day Free window" (start_my_trial) sets
-- users.subscription_plan = 'free', but the original CHECK only allowed
-- ('starter','basic','pro','trial') → library launch failed with 23514
-- (users_subscription_plan_check). 'free' is now a first-class plan value
-- (plan_service treats it as the Free tier). Add it to the CHECK.
--
-- Idempotent.
-- ============================================================================

ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_subscription_plan_check;
ALTER TABLE public.users ADD CONSTRAINT users_subscription_plan_check
    CHECK (subscription_plan IN ('free', 'starter', 'basic', 'pro', 'trial'));
