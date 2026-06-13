# SECURITY RLS — what's safe now vs. blocked on the server tier

> Generated 2026-06-12 while attempting T2.6 (the audit's Wave-0/1 security RLS tightenings).
> **Headline:** I investigated each tightening to author it as a safe, individually-appliable
> migration. **All but one collide with a live, currently-client-side flow** — applying them today
> would knowingly break a working feature (and you can't test to catch it right now). So this doc
> records the evidence and the real path, and ships only the one genuinely non-breaking change.
>
> Root cause is the audit's **RC-1 (no server tier):** the fat client performs privileged and
> cross-actor writes directly, which means the permissive RLS is *load-bearing*. You can't deny a
> write via RLS that the client still has to perform. The unlock is to move each privileged write
> behind a `SECURITY DEFINER` RPC / Edge Function, **then** tighten the policy.

---

## ✅ Applied now (safe, non-breaking)

**`2026-06-12_harden_open_insert_policies.sql`** — change the four `WITH CHECK (true)` insert
policies (`notifications`, `audit_log`, `badges`, `referrals`) to `WITH CHECK (auth.uid() IS NOT NULL)`.

- **Why safe:** every legitimate insert into these tables happens *after* login. This only removes
  the **unauthenticated** forgery surface (someone with just the public anon key, no account).
- **What it does NOT fix:** an *authenticated* user can still forge rows for other users — that needs
  actor-scoping, which is blocked below.
- **Verify:** apply, then trigger any in-app notification (admin Hold/Remove a member) — it should
  still arrive. Rollback = restore `WITH CHECK (true)`.

---

## ⛔ Blocked on the server tier (do NOT apply as-is — each breaks a live flow)

### 1. Lock `users.role` / `subscription_*` / `*_verified` (audit P6-02 / P6-06)
- **Threat:** a member self-escalates to `admin`, or self-activates a paid subscription, via a direct
  `users.update`.
- **Conflicting client code (all legitimate today):**
  - role switch: `member_profile_tab.dart:1463` (`update({'role':'admin'})`), `admin_profile_tab.dart:516`
    (`update({'role':'member'})`), `role_selection_screen.dart:54`.
  - subscription trial: `admin_home.dart:982-984` (`subscription_plan/status/expiry`).
  - verification flags: `member_profile_edit.dart:533/544/617-618` (`phone_verified`/`email_verified`).
- **Why blocked:** the app *intentionally* lets a user flip their own role (member⇄admin) and set
  trial/verification client-side. `REVOKE UPDATE (role, …)` would break all of the above.
- **Unlock:** move role-switch, subscription, and verification to RPCs (or a real OTP/billing flow),
  then `REVOKE UPDATE (role, subscription_plan, subscription_status, subscription_expiry,
  phone_verified, email_verified) ON users FROM authenticated;`.

### 2. Scope `notifications` / `audit_log` / `badges` / `referrals` inserts to the actor (audit P5-08)
- **Threat:** an authenticated user forges a notification/audit/badge/referral for someone else.
- **Conflicting client code (cross-actor by design):**
  - `join_flow_screen.dart:633` — a **member** inserts an `audit_log` row with `admin_id = owner_id`
    (attributed to the library owner, not the inserting member).
  - `join_flow_screen.dart:650` — the **member** inserts a `notification` addressed to the **owner**.
  - `member_analytics_service.dart:_awardBadge` (687/692) — inserts a badge + notification for a
    `memberId` that is not guaranteed to be `auth.uid()`.
- **Why blocked:** an `actor = self` or `row-belongs-to-me` check would reject these. A bidirectional
  relationship policy is *possible* but fragile (some inserts happen pre-membership) and unverifiable
  right now.
- **Unlock:** route the cross-actor writes (rejoin audit/notify, badge award) through a
  `SECURITY DEFINER` RPC, then scope each insert policy to the actor.

### 3. Drop the `memberships` `USING(true) WITH CHECK(true)` update (audit P5-01)
- **Threat:** any user updates any membership (free time / sabotage).
- **Conflicting client code:** `member_home.dart:5670` — a **member-side** `memberships.update`. There
  is no "member updates own membership" policy, so that write currently relies on the open `true/true`
  policy. Dropping it breaks that member flow.
- **Unlock:** add a narrow member-update policy (own membership, whitelisted columns only) or move that
  write server-side, **then** drop the `true/true` policy.

### 4. Tenant-scope `users` SELECT (audit P10-04)
- **Threat:** any library owner can read the entire `users` table (all PII).
- **Conflicting client code:** the Add-Member wizard looks up an existing user by phone/email across
  **all** libraries (`add_member_wizard.dart` `users.select(...).or('phone.eq...,email.eq...')`) — it
  must read users who are *not yet* members of the caller's library. A membership-scoped SELECT returns
  nothing for them, breaking existing-account detection.
- **Unlock:** a `SECURITY DEFINER` "find user by phone/email" RPC that returns only a minimal record,
  then scope the broad SELECT down to tenant members.

### 5. Storage object-scoping (audit P10-01/02/03)
- **Threat:** private ID/payment docs not owner-scoped; PII potentially on a public bucket.
- **Blocker:** the current `storage.objects` policies live in the Supabase dashboard, **not** in this
  repo, so they can't be reviewed/authored from here without breaking signed-URL reads/uploads.
- **Action first:** export the current storage policies (Dashboard → Storage → Policies, or
  `select * from storage.objects` policies) and paste them in; then scope the private bucket
  read/write/delete to the owning library's path.

---

## Sequencing (the real plan)
1. **Now:** apply `2026-06-12_harden_open_insert_policies.sql` (above) — the only safe interim.
2. **Server tier (RC-1):** stand up `SECURITY DEFINER` RPCs / Edge Functions for the privileged +
   cross-actor writes (role/subscription/verify; rejoin audit+notify; badge award; user lookup).
3. **Then tighten**, one table at a time, re-verifying the matching flow after each:
   actor-scope the four inserts → lock `users` sensitive columns → member-scope `memberships` update →
   tenant-scope `users` SELECT → storage object-scoping.

> Until step 2 exists, the remaining tightenings are not "no-test config" — they are app-architecture
> changes. Don't apply them blind.
