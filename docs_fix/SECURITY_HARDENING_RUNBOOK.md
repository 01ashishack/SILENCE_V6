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
Today any authenticated user can read `silence_private` (member ID docs + payment proofs). Path families found:
- `library_members/<library_id>/<sub>/<file>` — ID docs (admin add-member, member self-upload).
- `payment_proofs/<user_id>/<file>` — payment proofs (member uploads; **admin must read**).
1. **Enumerate ALL silence_private writers first** (confirm every path family) — currently:
   `add_member_wizard.dart:316`, `join_flow_screen.dart:526`, `member_profile_edit.dart:363`,
   `admin_profile_tab.dart:369`. Confirm member_profile_edit's exact path before writing policy.
2. **Author** `migrations/2026-06-14_storage_private_owner_scoping.sql` replacing the baseline
   `silence_private` policies with path-scoped ones:
   - `library_members/<lib>/…`: read/write/delete if `auth.uid()` owns `<lib>` (join `libraries`), OR the owning member (self).
   - `payment_proofs/<uid>/…`: write/read by `<uid>` self; read by the admin who owns the library the member belongs to (join `memberships`→`libraries`).
   - Keep `silence_assets` public-read (it's intentionally public for photos/logos).
3. **Verify on device** (critical — easy to over-lock): admin can still open a member's ID via signed URL;
   member can still upload ID + payment proof; admin can still view payment proof. Rollback = restore baseline policies.
> ⚠️ Do NOT apply blind — a wrong policy silently breaks signed-URL reads. Verify each read path.

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
- ⏭️ Next executable step: **Cycle 1 step 2** (wire the 3 lookup sites) — gated on a device test, do it during/after the P1 smoke test.
