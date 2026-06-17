# Server tier (RC-1) — plan & backlog

> Generated 2026-06-12. This is the unlock for the audit's root cause **RC-1 (no server tier)** and,
> by extension, most of the security RLS tightenings that `docs_fix/SECURITY_RLS_ANALYSIS.md` showed
> are blocked. The idea: every privileged or cross-actor write the fat client does today gets a small
> server-side function that enforces authorization; the client calls the function instead of writing
> directly; then the permissive RLS that made the direct write possible can be locked down.

## Decision: Postgres `SECURITY DEFINER` RPCs (not Edge Functions, yet)

- **Form:** plain SQL functions in `public`, applied as migrations (same flow you already use), called
  from Dart via `supabase.rpc('name', params: {...})`.
- **Why this over Edge Functions for now:** no extra deploy infra / runtime; runs in the DB next to the
  data; a `SECURITY DEFINER` function can bypass RLS *and* enforce its own checks; fits the
  migrations-you-apply workflow. Edge Functions come later only where we need non-DB work (e.g. calling
  Razorpay, sending FCM).
- **Where they live:** `silence_app/migrations/*_rpc_*.sql` (functions accumulate in migrations; the
  table-centric `supabase_schema.sql` stays the canonical for tables + RLS).

## Security template (every RPC follows this)

1. `SECURITY DEFINER` + `SET search_path = public, pg_temp` (prevents search_path hijacking).
2. Authorize **inside** the function from `auth.uid()` (which is still the *caller* under DEFINER):
   check authenticated + the right ownership/membership; `RAISE EXCEPTION ... USING errcode='42501'`
   otherwise.
3. Do the minimum: validate/normalize inputs, touch only the intended rows/columns, return minimal data.
4. `REVOKE ALL ... FROM PUBLIC;` then `GRANT EXECUTE ... TO authenticated;` (anon can't call it).
5. Additive: ship the function first (changes nothing), wire the client second (testable), tighten the
   replaced RLS third (testable).

## The "adopt then tighten" loop (per RPC)

```
ship RPC (additive, safe)  →  wire client to call it  →  verify that ONE flow on a device
                                                          →  tighten the RLS the RPC replaced
                                                          →  re-verify the flow
```
Never tighten the RLS before the client is calling the RPC and verified — that's what makes each step
revertible and testable in isolation.

## Backlog (priority order — each RPC unlocks a specific tightening)

| # | RPC | Replaces (client direct write) | Unlocks (then-safe RLS tightening) | Audit |
|---|-----|--------------------------------|------------------------------------|-------|
| 1 | **`find_user_by_contact`** ✅ drafted | add-member existing-user lookup (`users.select` by phone/email across libraries) | tenant-scope the broad `users` SELECT | P10-04 |
| 2 | `admin_record_membership_update` | `member_home.dart:5670` member-side `memberships.update` (+ admin update paths) | drop `memberships` `USING(true) WITH CHECK(true)` | P5-01 |
| 3 | `log_rejoin_profile_change` | `join_flow:633/650` (member writes owner-attributed audit + notifies owner) | actor-scope `audit_log` + `notifications` inserts | P5-08 |
| 4 | `award_member_badge` | `_awardBadge` (cross-actor badge + notification) | scope `badges` insert to the member | P5-08 |
| 5 | `set_subscription` | `admin_home:982` subscription trial write | lock `users.subscription_*` columns | P6-03 |
| 6 | `switch_role` (if kept a feature) | `member_profile_tab:1463` / `admin_profile_tab:516` role flips | lock `users.role` column | P6-02 |

> Note on #6: in this app, becoming an `admin` is the legitimate path to creating a library — so
> "self-escalation" may be intended, not a vuln. Decide whether role-switch stays a free client action
> before building an RPC + column lock for it.

## Status

- **First Edge Function LIVE (2026-06-17):** `supabase/functions/send-push` — the "later, non-DB work"
  this doc anticipated (sending FCM). Deployed `--no-verify-jwt`; a Database Webhook on `notifications`
  INSERT invokes it; it reads `device_tokens` (service role) and sends FCM HTTP v1. Service account is
  a base64 secret (`FIREBASE_SERVICE_ACCOUNT_B64`). Web-verified end-to-end. *Harden:* add a shared-secret
  header so the public function URL can't be abused to spam pushes.
- **RPCs `find_user_by_contact` + `contact_in_use` (add-member) — APPLIED & wired** (existing-user
  autofill + admin-email block). The broad users SELECT was tenant-scoped (2026-06-14).
- **RPC #1 `find_user_by_contact` — drafted & ready to apply:**
  `silence_app/migrations/2026-06-12_rpc_find_user_by_contact.sql`. Additive; nothing calls it yet.
- **Next step (needs one on-device test):** wire the 3 add-member lookup call sites to
  `supabase.rpc('find_user_by_contact', ...)` (proposed diff handed to you for review). Verify
  add-member existing-user autofill + the active-membership guard still work. **Only then** author the
  follow-up migration that tenant-scopes the `users` SELECT (closes P10-04).
