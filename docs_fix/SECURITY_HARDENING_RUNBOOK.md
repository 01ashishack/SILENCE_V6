# Security Hardening — ordered execution runbook

> Created 2026-06-14. The single ordered checklist for the security track. The *why/evidence* lives in
> `docs_fix/SECURITY_RLS_ANALYSIS.md` (what's safe vs. blocked) and `docs_fix/SERVER_TIER_PLAN.md`
> (the RPC backlog + template). This file is just the **do-this-in-this-order** view.
>
> **Golden rule (RC-1):** the fat client does privileged + cross-actor writes, so the permissive RLS
> is *load-bearing*. You can't deny via RLS a write the client still performs. Every tightening below
> follows the **adopt-then-tighten loop** and is gated on a device test:
> ```
> ship RPC/policy (additive, safe) → wire client → verify ONE flow on device → tighten the RLS → re-verify
> ```
> Never tighten before the client side is verified. Each step is independently revertible.

---

## Prerequisites (before any tightening)
- **P0.** Apply `migrations/2026-06-13_users_role_nullable.sql` + delete stuck auth user → signup works.
- **P1.** Clean-state functional smoke test (`docs_fix/FROM_SCRATCH_SETUP_AND_TEST.md`) with the
  **functional baseline** storage policies (`migrations/2026-06-12_storage_buckets_setup.sql`) and
  RPC #1 applied. Confirm uploads, add-member, reservation tabs all work BEFORE locking anything down.

---

## Cycle order (by PII/risk priority)

### 🥇 Cycle 1 — Tenant-scope `users` SELECT (P10-04) — *largest PII exposure*
Today any library owner can `SELECT` the **entire** `users` table. RPC #1 is already drafted.
1. ✅ **Ship:** `migrations/2026-06-12_rpc_find_user_by_contact.sql` (owner-only, SECURITY DEFINER, exact-match LIMIT 1). Additive. **← user must apply this to the live DB.**
2. ✅ **Wire client** (3 sites) to `supabase.rpc('find_user_by_contact', params:{p_phone, p_email})` — **DONE** (committed):
   - `add_member_step1.dart:_lookupUserByEmail` — now `rpc('find_user_by_contact', {p_email})`
   - `add_member_step1.dart:_lookupUserByPhone` — now `rpc('find_user_by_contact', {p_phone})`
   - `add_member_wizard.dart:_finalizeRegistration` — now `rpc('find_user_by_contact', {p_phone, p_email})`
3. ⏭️ **Verify on device (USER):** with RPC #1 applied, add a member by an existing user's phone/email →
   autofill sheet appears; the active-membership dup-guard still blocks a second active membership.
4. ⏭️ **Tighten (GATED on step 3):** apply `migrations/2026-06-14_users_select_tenant_scope.sql`
   (replaces the broad "admins view all users" SELECT with a `memberships`→`libraries` scoped SELECT;
   self-row SELECT stays). **Authored, NOT yet folded into canonical** (a pointer comment marks the spot).
5. ⏭️ **Re-verify:** member lists + member detail still load; cross-library lookup now ONLY works via the RPC.
   Then fold the tightened policy into `supabase_schema.sql` (replace the ⚠️ P10-04 block).

### 🥈 Cycle 2 — Storage owner-scoping (P10-01/02/03) — *DPDP legal blocker (exposed ID docs)*
Today any authenticated user can read `silence_private` (member ID docs + payment proofs).
1. ✅ **Enumerated all 4 path families** (writers in `lib/`):
   - `library_members/<library_id>/…` — member ID doc, admin-uploaded (`add_member_wizard.dart:316`)
   - `member_profiles/<user_id>/…` — member ID doc, self-uploaded (`member_profile_edit.dart:363`)
   - `payment_proofs/<user_id>/…` — payment proof, member-uploaded (`join_flow_screen.dart:526`)
   - `admin_profiles/<user_id>/…` — admin's own photo (`admin_profile_tab.dart:369`)
2. ✅ **Authored** `migrations/2026-06-14_storage_private_owner_scoping.sql` (gated, NOT applied):
   read = self for own-id folders + library owner for `library_members`/their members' `member_profiles`/`payment_proofs`;
   write = self for own-id folders + library owner for `library_members`. Uses `storage.foldername(name)`.
   Includes a per-path VERIFY block + a one-paste ROLLBACK to the functional baseline.
3. ⏭️ **Verify on device (USER, critical — easy to over-lock):** run the migration's VERIFY block —
   admin uploads + views a member ID; member uploads + views own ID; payment-proof upload + both reads.
   If any image goes blank → run the ROLLBACK. Only fold into canonical after a clean device pass.
> ⚠️ Do NOT apply blind — a wrong policy silently breaks signed-URL reads (blank images, no error).
> ✅ Tangential bug FIXED (2026-06-16): `admin_profile_tab` uploaded the admin photo to the PRIVATE
>   bucket then called `getPublicUrl` (an unsigned URL that never loads). Admin photos are public-facing
>   (shown on the library's public profile), so they now upload to PUBLIC `silence_assets` +
>   `getPublicUrl` — the correct working pair. This also means the storage migration's `admin_profiles`
>   family no longer holds new objects; its self-scoped clauses remain only for any legacy private photo.
>
> 🔎 Pre-apply code sweep (2026-06-16) — every `silence_private` writer verified to use the
>   3-segment `family/<id>/<file>` path the policy assumes (`foldername[1]/[2]`):
>   - `add_member_wizard` ID docs → `library_members/<library_id>/…` (owner write ✓)
>   - `member_profile_edit` ID docs → `member_profiles/<user_id>/…` (self write ✓, owner read ✓)
>   - `join_flow_screen` payment proof → `payment_proofs/<user_id>/…` (self write ✓, owner read ✓)
>   No flat/legacy private paths exist, so no writer is silently blocked. Migration is correct as-is.

### 🥉 Cycle 3 — Actor-scope the 4 forgeable inserts (P5-08)
`auth.uid() IS NOT NULL` is already shipped (blocks anon forgery). Full actor-scoping needs RPCs first:
- RPC `log_rejoin_profile_change` → replaces `join_flow:633/650` (member writes owner-attributed audit + notifies owner) → then actor-scope `audit_log` + `notifications` inserts.
- RPC `award_member_badge` → replaces `_awardBadge` cross-actor write → then scope `badges` insert to the member.

### 4 — Member-scope `memberships` UPDATE (P5-01)
RPC `admin_record_membership_update` (+ a narrow "member updates own membership, whitelisted columns" policy) to replace `member_home.dart:~5670`, → then drop the `USING(true) WITH CHECK(true)` membership UPDATE.

### 5 — Lock `users.subscription_*` / `*_verified` columns (P6-03)
RPC `set_subscription` → replaces `admin_home:~982` trial write → then `REVOKE UPDATE (subscription_*, phone_verified, email_verified) ON users FROM authenticated`.

### 6 — `users.role` lock (P6-02) — *DECISION NEEDED FIRST*
In this app becoming `admin` is the legitimate path to creating a library, so client-side role-switch may be **intended, not a vuln**. Decide whether role-switch stays a free client action before building RPC `switch_role` + the column REVOKE.

---

## Status
- ✅ Shipped: `2026-06-12_harden_open_insert_policies.sql` (anon-forgery block).
- ✅ Drafted, additive, ready: RPC #1 `find_user_by_contact`.
- ✅ Cycle 1 step 2 (wire the 3 lookup sites) — DONE, committed.
- 🛠️ **Cycle 1 tighten migration corrected (2026-06-16):** the tenant-scope SELECT
  (`2026-06-14_users_select_tenant_scope.sql`) would have **blanked the Requests tab** — a
  pending join-request's applicant is NOT a member yet, so the `join_requests → member_id(...)`
  embed in `requests_sub_tab.dart:128` would return null under a members-only policy. Added an
  `OR EXISTS (pending join_requests at an owned library)` clause so applicants' name/phone/photo
  still resolve. Swept all admin-side `users` reads/embeds: every other `member_id(...)` embed
  (seat-change, hold, attendance, payments, layout, archive, members list) reads existing
  **members** (membership row exists → covered by clause (a)); only pending join-requests needed
  clause (b). Transfer screen doesn't read `users`. So the corrected policy is the complete set.
- ⏭️ **Next executable step (USER, gated):** apply RPC #1 to the live DB if not already, device-verify
  add-member autofill + the Requests tab shows applicant details, THEN apply the corrected
  tenant-scope migration and re-verify (member lists, member detail, Requests tab all still load).
  Only then fold the tightened policy into `supabase_schema.sql`.
