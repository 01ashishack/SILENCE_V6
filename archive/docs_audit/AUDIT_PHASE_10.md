# SILENCE — Phase 10: Security Audit (Threat Model · Authorization · PII · Abuse)

**Phase:** 10 of 16 — Security Audit
**Completed (local time):** 2026-06-08
**Auditor roles:** Senior Security Auditor (lead) · Full-Stack Engineer · Backend/Data Engineer · App Store Review Consultant · QA Lead
**Goal:** Determine whether user data, payments, memberships, attendance, revenue, admin privileges, and personal documents can be **viewed, modified, forged, escalated, or abused** by unauthorized actors.
**Method:** White-box review of RLS (`supabase_schema.sql`), storage policies (`storage_setup.sql`), every data-write site, auth/session flows, secrets, and the offline store. Threat-modeled across 8 attacker profiles. Behavior is **Code-Inferred** against the *committed* policy files — **declared limitation: no live Supabase project, so I audit the policies the repo would deploy, not the policies currently live.** Every claim cites `file:line`.
**Constraint honored:** No code modified. Audit only.

**Security classification used per finding:** Confidentiality · Integrity · Availability · Authorization · Authentication · Privacy · Business-Logic Abuse.

---

## 1. Executive Summary — Is the front door locked?

**No. The application cannot be safely exposed to real users today.** SILENCE has **no server-side authorization tier** (0 RPC, 0 Edge Functions, no `supabase/functions` directory — confirmed Phase 6 P6-01). Its *entire* security model is the public `anon` key shipped in the binary plus PostgreSQL Row-Level Security. That single line of defense is **porous by design in the committed policies**: multiple tables and both storage buckets grant access on conditions that any authenticated user — or, for the public bucket, *anyone on the internet* — trivially satisfies.

The result is that a **malicious member armed only with the app's own anon key and their own login token** (both extractable from the APK in minutes) can, via crafted REST calls that never touch the app UI:

- **Read every user's PII** — name, phone, email, address, DOB, ID-proof URLs — for *all* libraries, by inserting one `libraries` row (P10-04).
- **Download every member's ID proof and payment screenshot** from the "private" bucket, which has **no per-user scoping** (P10-01), and from the **public** bucket, which needs no login at all (P10-02).
- **Overwrite or delete any file** in any bucket — wipe a rival library's QR codes, replace a member's ID with garbage (P10-03).
- **Rewrite any membership** — extend their own expiry to 2099, flip status to `active`, or sabotage another member (P10-05).
- **Promote themselves to admin** and **activate a paid subscription without paying** (P10-06, P10-07).
- **Fabricate attendance, badges, referrals, audit-log entries, and notifications addressed to any user** (P10-09 … P10-12).

None of these require a jailbroken device, a stolen credential, or a server exploit. They require `curl`.

**Distribution (Phase 10):** 8 Critical · 8 High · 6 Medium · 2 Low (P10-01 … P10-24). Of these, **9 are net-new** to the audit; the remainder consolidate and sharpen Critical/High findings already raised in Phases 0–6 (linked, not double-counted).

**Security posture score: 1.5 / 10.** The data layer is effectively a shared, world-writable database with a thin coat of UI on top. The "private" bucket is not private; the "Verified" badge verifies nothing; the audit log can be forged by the people it audits.

**The four structural truths behind every finding:**
1. **No server tier (P6-01/P10-08):** there is nowhere to enforce a rule the client can't be trusted to keep. RLS is the only gate, and RLS cannot express "the amount equals price minus a capped discount" or "you may only read your own bucket folder" as written here.
2. **RLS confuses "authenticated" with "authorized" (P10-04/05/10/11):** many policies use `WITH CHECK (true)` or check only that *some* library is owned, not that *this* row belongs to the actor.
3. **Storage policies scope by bucket, not by path/owner (P10-01/03):** `silence_private` is "any logged-in user can read/write/delete anything." Predictable paths (`member_profiles/{uuid}/id_document_1.jpg`) make enumeration trivial.
4. **Identity is self-asserted (P10-06/07/13):** role, subscription status, and "verified" flags are columns the user can write to their own row.

---

## 2. What Was Reviewed

- **Authorization:** all 50+ RLS policies in `silence_app/supabase_schema.sql:501-835` across 25 tables.
- **Storage:** `silence_app/storage_setup.sql` (3 buckets, 12 policies) + all 42 `.storage.from(...)` call sites in `lib/**`.
- **Authentication / sessions:** `auth_screen.dart` (login/signup/reset), Supabase session persistence, SharedPreferences trust.
- **PII handling:** `users` schema, ID-proof and payment-screenshot upload sites, offline cache (`offline_db.dart`).
- **Identity & privilege:** role-switch site, subscription self-activation, mock-OTP "verification."
- **Secrets/config:** `supabase_config.dart`, signing config, presence of service-role keys / `.env` / `google-services.json`.
- **Client-trust & abuse:** attendance/badge/referral/notification/audit self-inserts; payment honor-system; injection surface.
- **Platform:** Android manifest + iOS `Info.plist` permissions and export flags.

## 3. Files & Artifacts Reviewed (evidence base)
`silence_app/supabase_schema.sql` (RLS §501-835), `silence_app/storage_setup.sql`, `lib/core/supabase_config.dart`, `lib/core/offline_db.dart`, `lib/screens/auth_screen.dart`, `lib/screens/member_profile_tab.dart`, `lib/screens/member_profile_edit.dart`, `lib/screens/subscription_screen.dart`, `lib/screens/admin_home.dart`, `lib/screens/reservations/{join_flow_screen,renewal_screen,qr_scanner_screen,member_detail_screen}.dart`, `lib/screens/member_history_tab.dart`, `lib/screens/admin/{add_member_step1,add_member_wizard}.dart`, `lib/screens/admin_profile_tab.dart`, `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts`, `ios/Runner/Info.plist`.

---

## 4. Threat Model

### 4.1 Trust boundaries
```
[ Flutter client (UNTRUSTED) ]  ── anon key (public, in binary) + user JWT ──►  [ Supabase ]
   • app UI / business logic          /rest/v1/*   (PostgREST)  → guarded ONLY by RLS
   • SharedPreferences (sub/role)      /storage/v1/* (Storage)   → guarded ONLY by bucket policy
   • sqflite silence_offline.db        /auth/v1/*   (GoTrue)     → real Supabase Auth
                                       (NO /functions — no server logic exists)
```
The only real trust boundary is Supabase's RLS/Storage policy engine. **There is no server-side application code**, so every invariant the app "enforces" in Dart is advisory — bypassable by talking to PostgREST directly. The anon key is *meant* to be public; the security therefore rests entirely on RLS being correct. It is not.

### 4.2 Attacker profiles (simulated) — what each can actually do
| # | Actor | Capability with the shipped anon key + their own session | Worst outcome |
|---|---|---|---|
| T1 | **Normal member** (UI only) | Bounded by screens; sees own data | — |
| T2 | **Curious member** (reads network tab / app logs) | Learns endpoints, own JWT, the anon key, storage URL patterns | Recon for T3 |
| T3 | **Malicious member** (crafted REST) | **Read all users' PII (P10-04); read/overwrite/delete any storage object (P10-01/03); rewrite any membership (P10-05); self-promote to admin (P10-06); self-activate subscription (P10-07); fabricate attendance/badges/referrals/audit/notifications (P10-09…12)** | Full data breach + tamper |
| T4 | **Malicious admin** (owns ≥1 library) | All of T3 **plus** legitimately-broad reads; cross-tenant reads of *other* libraries' members via P10-04; forge audit entries for any library | Cross-tenant breach |
| T5 | **Ex-member** (membership expired, JWT still valid) | Most table policies check only `auth.uid()` existence, not active membership → can still self-insert attendance, read buckets, **re-activate own membership (P10-05)** until token expiry | Revocation is ineffective |
| T6 | **Stolen / rooted device** | Reads unencrypted `silence_offline.db` (member roster: names+phones) (P10-15); reuses persisted session token = full account; SharedPreferences shows "Active" plan | Offline PII + account takeover |
| T7 | **Reverse-engineered client** | Extracts anon key + URL from APK (trivial); reconstructs all of T3 without the app | Same as T3, at scale/scriptable |
| T8 | **Unauthenticated internet** | **Reads the entire public `silence_assets` bucket — payment screenshots, member photos, admin-uploaded member photos — with no login (P10-02)**; reads all active libraries/seats/shifts/pricing (P10-21) | Mass PII scrape, zero credentials |

### 4.3 Likelihood × Impact
The exploits require only widely-available tooling (`curl`/Postman) and public artifacts (the APK). **Likelihood is High; Impact is Critical** for confidentiality, integrity, authorization, and business/revenue. This is not a theoretical chain — each step is a single REST call permitted by a policy quoted below.

---

## 5. Attack Surface Map

| Surface | Endpoint(s) | Guard | State |
|---|---|---|---|
| **Database** | `/rest/v1/{table}` (PostgREST) for all 25 tables | RLS only | **Multiple holes (P10-04/05/10/11/12, P5-01/07)** |
| **Storage – public** | `/storage/v1/object/public/silence_assets/*` | Public read (`TO public`); auth write (any) | **PII exposed unauthenticated (P10-02); world-writable (P10-03)** |
| **Storage – "private"** | `/storage/v1/object/silence_private/*` | Auth read/write — **not** owner-scoped | **Any user reads/writes all docs (P10-01/03)** |
| **Storage – temp** | `silence_temp` | Public read; auth write | **Open dumping ground (P10-19)** |
| **Auth** | `/auth/v1/*` (GoTrue) | Supabase-managed | Email confirmation not enforced; mock OTP on top (P10-13) |
| **Client binary** | APK/IPA | None | Anon key + URL extractable (by design); debug-signed release (P10-14) |
| **Local storage** | `silence_offline.db`, SharedPreferences | OS sandbox only | Unencrypted PII at rest (P10-15); client-authoritative sub/role (P10-20) |
| **Server functions** | — | — | **None exist** → no server defense possible (P10-08) |

---

## 6. Findings

> Legend: **🔴 Critical · 🟠 High · 🟡 Medium · 🟢 Low**. "Links" = consolidates a prior-phase finding (counted once, in its owning phase).

### P10-01 — The "private" storage bucket is not private: any authenticated user can read every member's ID proofs & payment docs 🔴 Critical
**Class:** Confidentiality · Privacy · Authorization
**Evidence:** `storage_setup.sql:67-70` — `CREATE POLICY "Authenticated Read Access for silence_private" ON storage.objects FOR SELECT TO authenticated USING (bucket_id = 'silence_private');`. The policy scopes by **bucket only** — there is **no `auth.uid()` / path / `owner` predicate**. The inline comment ("RLS rules on table handle user-specific rules") describes scoping that **does not exist**. Upload paths are predictable: `member_profiles/{user_id}/id_document_1.jpg` / `id_document_2.jpg` (`member_profile_edit.dart:344-346`), and ID/payment docs land here (`join_flow_screen.dart:395-406`, `member_detail_screen.dart:789-836`, `add_member_wizard.dart:416`).
**Root cause:** Bucket-level policy substituted for object-level (owner/path) authorization; signed URLs are used by the *uploader* but the underlying objects are readable by any logged-in user regardless.
**Impact:** Every government ID and KYC document of every member is readable by **any** member. The `user_id` needed to build the path is itself leakable (P10-04, join requests, referrals).
**Exploitation (T3):** Log in as any member → `GET /storage/v1/object/silence_private/member_profiles/{victim_uuid}/id_document_1.jpg` with the anon key + own JWT → receive the victim's Aadhaar/PAN image.
**Fix:** Scope `silence_private` SELECT to the owner: `USING (bucket_id='silence_private' AND (storage.foldername(name))[2] = auth.uid()::text)` (or store ownership in `storage.objects.owner` and check it), plus an admin-of-that-library exception. Never rely on signed-URL secrecy for authorization.

### P10-02 — Sensitive PII uploaded to a fully public bucket, readable by the unauthenticated internet 🔴 Critical · Links **R-01**
**Class:** Confidentiality · Privacy
**Evidence:** `storage_setup.sql:9-10` — `silence_assets` created `public = true`; `:33-36` SELECT `TO public`. Sensitive content is uploaded there: **payment screenshots** (`renewal_screen.dart:148-158`, `member_history_tab.dart:2730-2740`), **member profile photos** (`member_profile_tab.dart:378-388`, `add_member_step1.dart:523-533`), **admin-uploaded member photos & docs** (`add_member_wizard.dart:317-342` → `getPublicUrl`). All return `getPublicUrl` (no auth, no expiry).
**Root cause:** "Public for logos/QR" bucket reused for personal/financial documents; no separation of asset classes.
**Impact:** Anyone with a URL — or anyone enumerating predictable paths (`payment_proofs/{uuid}/...`, `member_profiles/{uuid}/profile.jpg`) — downloads payment proofs and member photos **without logging in**. URLs are also cached/CDN-served and may be indexed.
**Exploitation (T8):** No account needed. Enumerate `…/public/silence_assets/payment_proofs/{uuid}/...` using UUIDs harvested via P10-04.
**Fix:** Move all member/payment/ID media to a correctly owner-scoped private bucket (see P10-01 fix); restrict `silence_assets` to genuinely public, non-personal assets (logos, QR, library photos).

### P10-03 — Storage is world-writable and world-deletable: any authenticated user can overwrite or destroy any object 🔴 Critical
**Class:** Integrity · Availability
**Evidence:** `storage_setup.sql` — for **both** buckets, INSERT/UPDATE/DELETE are `TO authenticated WITH CHECK/USING (bucket_id = '<bucket>')` with **no owner/path check** (`:39-55` assets, `:73-89` private). Uploads use `upsert: true` (`member_history_tab.dart:2734`, `renewal_screen.dart:153`, etc.), so a write to an existing path replaces it.
**Root cause:** Same bucket-only scoping as P10-01, applied to mutations.
**Impact:** A malicious member can (a) **overwrite** another member's ID proof / a library's QR-code image / logo with arbitrary content, (b) **delete** any object — payment proofs (destroying evidence in a dispute), QR codes (denial of check-in for a whole library), branding. This is both tampering and a targeted DoS.
**Exploitation (T3):** `DELETE /storage/v1/object/silence_private/member_profiles/{victim_uuid}/id_document_1.jpg`, or `POST` a new QR image over `qr_codes/{rival_library}/...`.
**Fix:** Scope INSERT/UPDATE/DELETE to the owning user's folder (and admins to their library's folder), as in P10-01.

### P10-04 — Any user can read the entire `users` table (all PII, all tenants) by creating one library row 🔴 Critical · Links **P5-07, P6-02**
**Class:** Confidentiality · Privacy · Authorization
**Evidence:** `supabase_schema.sql:531-532` — `CREATE POLICY "Admins can view all users (for member lists)" ON users FOR SELECT USING (EXISTS (SELECT 1 FROM libraries WHERE owner_id = auth.uid()));`. The predicate checks **library ownership, not role** and is **not tenant-scoped** (no link between the viewed user and the viewer's library). `:547-548` — `libraries` INSERT is `WITH CHECK (auth.uid() = owner_id)` with **no role gate**, so *any* authenticated user can create a library.
**Root cause:** "Admin can list members" was implemented as "owns any library ⇒ read all users," and member-of-this-library scoping was never added.
**Impact:** The full PII spine of the platform — every user's `full_name`, `phone`, `email`, `address`, `date_of_birth`, ID-proof URLs — is readable across **all** libraries by anyone who owns (or creates) a single library row. No `role='admin'` even required.
**Exploitation (T3→T4):** `INSERT libraries {owner_id: me, name:'x', status:'setup'}` → `GET /rest/v1/users?select=*` → entire user table. Two REST calls.
**Fix:** Scope to shared membership: `USING (EXISTS (SELECT 1 FROM memberships m JOIN libraries l ON l.id=m.library_id WHERE l.owner_id=auth.uid() AND m.member_id=users.id))`. Restrict `libraries` INSERT to vetted owners or gate behind a server function.

### P10-05 — `memberships` is updatable by everyone: self-renew, self-activate, or sabotage any member 🔴 Critical · Links **P5-01**
**Class:** Authorization · Integrity · Business-Logic Abuse
**Evidence:** `supabase_schema.sql:608-609` — `CREATE POLICY "System can update (auto-hold, auto-expiry)" ON memberships FOR UPDATE USING (true) WITH CHECK (true);`. The trailing comment assumes a `service_role` job, but the policy applies to **all** roles including `authenticated`/`anon`.
**Root cause:** A policy intended for a privileged backend job was written as `true/true` and there is no backend job (P6-01) — only clients hit it.
**Impact:** Any member can `UPDATE memberships SET end_date='2099-12-31', status='active'` on **their own** row (free infinite membership) or on **anyone else's** (cancel a rival's membership, free their seat, change their plan). Directly corrupts revenue, occupancy, and access control.
**Exploitation (T3/T5):** `PATCH /rest/v1/memberships?id=eq.{any}` → arbitrary fields.
**Fix:** Replace with owner-and-self-scoped policies; move auto-hold/expiry to a `service_role` cron or Edge Function and grant `true` only to `service_role`.

### P10-06 — Role self-escalation: a member promotes themselves to admin by writing their own row 🔴 Critical · Links **P6-02**
**Class:** Authorization · Privilege Escalation
**Evidence:** `member_profile_tab.dart:1437` — `await _supabase.from('users').update({'role': 'admin'}).eq('id', user.id);`. Permitted by `supabase_schema.sql:534-535` — `users` UPDATE `USING (auth.uid()=id) WITH CHECK (auth.uid()=id)` with **no column restriction** on `role`.
**Root cause:** Self-service "switch to admin" UX backed by an unconstrained self-update; RLS cannot restrict *which columns* a user may change.
**Impact:** Self-grant of the admin role. Even without the role flip, P10-04 shows library creation alone suffices for PII; the role flip additionally unlocks admin-only UI/flows and compounds T4.
**Exploitation (T3):** One `PATCH`. The app even offers a button for it.
**Fix:** Block client writes to `role`/`subscription_*`/`*_verified` via a column-restricted policy or a `BEFORE UPDATE` trigger that rejects privilege-column changes from non-service roles; perform role changes server-side only.

### P10-07 — Billing bypass: subscription marked `active` and membership activated with no payment 🔴 Critical · Links **P6-03**
**Class:** Business-Logic Abuse · Integrity
**Evidence:** `subscription_screen.dart:282-289` — client `update({'subscription_plan':'pro','subscription_status':'active'})` after a `Future.delayed` "payment"; `admin_home.dart:970-979` — client grants a 14-day `active` trial via direct update; `payments` INSERT is member-self-allowed (`supabase_schema.sql:639-640`) with no status restriction, so a member can also insert a `verified`/`paid` payment row.
**Root cause:** Payment is mocked (P0-01) and there is no server to authorize state transitions; status is a client-writable column.
**Impact:** Free Pro/Starter for anyone; fabricated `payments` rows feed fabricated revenue (P8-08). Combined with P10-05, a member self-provisions a fully active paid membership end-to-end.
**Fix:** Gate all subscription/payment state behind a verified payment webhook on the server; make `subscription_*` and `payments.status` non-writable by clients.

### P10-08 — No server-side authorization tier exists; RLS is the only control and it is incomplete 🔴 Critical · Links **P6-01**
**Class:** Authorization (systemic / root cause)
**Evidence:** 0 `.rpc(` calls in `lib/**`; **no `supabase/functions` directory** (confirmed). 179 direct client writes (Phase 6). Several RLS policies are `WITH CHECK (true)` (`memberships:608`, `notifications:101`, `audit_log:111`, `badges:60`, `referrals:50`, `users` signup `:537`).
**Root cause:** The documented RPC/Edge layer was never built; the client writes straight to tables.
**Impact:** There is **no place** to enforce cross-column invariants (amount = price − capped discount), rate limits, idempotency, or privileged jobs. Every business rule is advisory. This is the parent of P10-04/05/07/09/10/11.
**Fix:** Introduce Edge Functions / Postgres RPC (`SECURITY DEFINER`) for all privileged mutations (approve join, record payment, change role, renew); reduce table-level grants to least privilege; reserve `true` policies for `service_role`.

### P10-09 — Attendance fabrication: members self-insert attendance with no validation 🟠 High · Links **P6-04, P3-03**
**Class:** Integrity · Business-Logic Abuse
**Evidence:** `supabase_schema.sql:618-619` — `attendance` INSERT `WITH CHECK (member_id = auth.uid())` (no check of active membership, real presence, QR, or library closure); client inserts at `qr_scanner_screen.dart:417` and offline sync at `offline_sync.dart:102`. Offline check-in "succeeds" for anyone (P3-03).
**Impact:** Members forge streaks, study-hours, attendance %, and leaderboard rank (gamification fraud; corrupts every Phase 8 metric). Ex-members (T5) can keep inserting.
**Fix:** Record attendance only via a server function that validates an active membership, a fresh signed QR nonce, and open hours; constrain `attendance` INSERT accordingly.

### P10-10 — Notification spoofing: any user can insert a notification addressed to any user 🟠 High (NEW)
**Class:** Integrity · Authorization (latent phishing)
**Evidence:** `supabase_schema.sql:101-102` — `notifications` INSERT `WITH CHECK (true)`; `user_id` is attacker-controlled.
**Impact:** An attacker writes arbitrary notifications to any `user_id` ("Account suspended — pay at this link"). Currently *latent* because the member Notifications screen is a hardcoded stub that never reads the table (P9-01) — but the moment that screen is fixed (a required fix), this becomes a live, app-trusted phishing channel. Also enables notification flooding (availability/nuisance).
**Fix:** `WITH CHECK` restricting inserts to `service_role` (or to the acting admin for their own library's members); never allow arbitrary `user_id` targeting from clients.

### P10-11 — Audit-log forgery: the audited can write the audit trail 🟠 High (NEW) · relates P4-02/P5-05
**Class:** Integrity · Non-repudiation
**Evidence:** `supabase_schema.sql:111-112` — `audit_log` INSERT `WITH CHECK (true)`; any authenticated user can insert rows for **any** `library_id`. Reads/writes are already broken by column drift (P4-02/P5-05), so even the legitimate trail is unreliable.
**Impact:** No trustworthy audit/compliance trail: an attacker can fabricate or bury entries (e.g., forge "admin approved" actions, or spam a rival's log). Defeats forensics and accountability.
**Fix:** Insert audit rows only from `service_role`/triggers; make the table append-only and client-unwritable.

### P10-12 — Self-awarded badges & forged referrals via open inserts 🟡 Medium (NEW)
**Class:** Integrity · Business-Logic Abuse
**Evidence:** `supabase_schema.sql:60-61` (`badges` INSERT `WITH CHECK (true)`) and `:50-51` (`referrals` INSERT `WITH CHECK (true)`).
**Impact:** Members self-award achievement badges and inject referral rows (gaming any future referral payout; polluting analytics). Lower severity only because referral rewards are currently never credited (P7-05) — but it pre-loads abuse for when they are.
**Fix:** Restrict to `service_role`/server logic that validates the earning condition.

### P10-13 — Authentication theatre: mock OTP self-sets "verified"; email confirmation not enforced 🟠 High · Links **P0-04, P6-06**
**Class:** Authentication · Integrity · Privacy
**Evidence:** `member_profile_edit.dart:480` "Mock OTP Code Sent: 123456"; `:492` hardcoded `123456`; on "verify" the client self-updates `phone_verified:true` / `email_verified:true` (`:509-520`). Account auth itself is real Supabase (`auth_screen.dart:115,160`), but there is no evidence email confirmation is required before use, and the phone/email "verified" flags are self-asserted.
**Impact:** "Verified" badges are meaningless; a user can claim any phone/email and mark it verified; admins cannot trust member contact data (failed reminders, impersonation). Anyone can sign up using someone else's email.
**Fix:** Use Supabase phone/email OTP (real), require email confirmation, and make `*_verified` server-set only.

### P10-14 — Release build signed with debug keystore; release manifest lacks INTERNET 🟠 High · Links **P1-02, P1-01**
**Class:** Integrity (supply chain) · Availability
**Evidence:** `android/app/build.gradle.kts:34-37` — release `signingConfig = signingConfigs.getByName("debug")`; `AndroidManifest.xml` (main) declares CAMERA/READ_MEDIA/etc. but **no `INTERNET`** (P1-01). Debug keys are publicly known → anyone can sign a malicious update with the same key (no signature pinning value); a Play upload is also blocked.
**Impact:** No authentic provenance for the app; potential update/impersonation risk; release build is also non-functional without INTERNET (ship-blocker).
**Fix:** Generate a private release keystore; add `INTERNET` to the release manifest; never ship debug-signed.

### P10-15 — Member PII cached unencrypted on-device (sqflite) 🟠 High (NEW)
**Class:** Confidentiality · Privacy (data-at-rest)
**Evidence:** `offline_db.dart:51-62` — `cache_members(full_name, phone, photo_url, seat_label, expiry_date, …)`; `:69-79` `cache_attendance_today(member_name, …)`. Stored in plaintext `silence_offline.db`; no encryption (no SQLCipher/`sqlite3_key`). On an admin's device this is the **entire member roster** (names + phones).
**Impact:** A lost/stolen/rooted device or a device-backup extraction exposes the full member roster and recent attendance. The persisted Supabase session token additionally grants account takeover (T6).
**Fix:** Encrypt the offline DB (SQLCipher) or store only non-PII keys; rely on OS keystore for the session; consider not caching phone numbers.

### P10-16 — Payment "proof" is a forgeable honor system over hardcoded amounts 🟠 High · Links **P3-01, P4-03, P9-04**
**Class:** Business-Logic Abuse · Integrity
**Evidence:** Join/renewal collect a sender name + screenshot (`join_flow_screen.dart:531-551`, `renewal_screen.dart:220-223`); approval hardcodes the amount `1500/4000/7500` ignoring price/discount (`requests_sub_tab:328`, P4-03); the UPI payee is a hardcoded placeholder (`join_flow_screen.dart:1295`, P3-01). Screenshots are user-supplied images.
**Impact:** A member uploads any image as "proof"; admin approves a fabricated amount; no money is verified to have moved. Revenue figures are fiction (P8-08); refund/chargeback disputes are inevitable (P9 Support Burden).
**Fix:** Integrate a real payment processor with server-side verification; derive amounts server-side from plan+capped discount.

### P10-17 — PostgREST filter injection via string-interpolated `.or(...)` 🟡 Medium (NEW)
**Class:** Integrity (injection surface)
**Evidence:** `add_member_wizard.dart:352` — `.or('phone.eq.${_memberData.phone},email.eq.${_memberData.email}')`. User/admin-entered values are concatenated into a PostgREST filter string without escaping. A value containing `,`, `)`, or PostgREST operators can alter the filter (e.g., broaden the match or error it).
**Impact:** Limited blast radius (read filter for duplicate-check, values are staff-entered), but it is a real injection pattern that could leak/return unintended rows or break the query; sets a dangerous precedent if copied.
**Fix:** Use parameterized `.or()` with proper encoding or split into discrete `.eq()` calls; validate/escape phone/email before interpolation.

### P10-18 — Hardcoded single-environment config; no key rotation/separation 🟡 Medium · Links **P0-08, P1-07**
**Class:** Confidentiality (config hygiene)
**Evidence:** `supabase_config.dart:5-6` — URL + anon JWT committed in source; one project for all builds; no `.env`/`--dart-define`. (No `service_role` key or `.env`/`google-services.json` is leaked — verified — which avoids a worse outcome.)
**Nuance:** The anon key is *designed* to be public; on its own it is **not** the vulnerability. The danger is that this public key is the master key to the **broken RLS** above, and there is no environment separation or rotation path, so a policy mistake is immediately internet-exposed with no staging buffer.
**Fix:** Move config to build-time `--dart-define`/secrets; separate dev/staging/prod projects; document rotation. (Real fix is to close the RLS holes so the public key is harmless, as intended.)

### P10-19 — `silence_temp` public bucket: open read + authenticated write, unclear lifecycle 🟡 Medium (NEW)
**Class:** Confidentiality · Availability
**Evidence:** `storage_setup.sql:18-21, 100-123` — `silence_temp` is `public=true`, public read, authenticated write/delete (no scoping). No code path that purges it was found.
**Impact:** A third public, world-writable dumping ground; anything transiently stored is publicly readable and tamperable; potential storage-cost abuse / illicit-content hosting.
**Fix:** Make private + owner-scoped, or remove the bucket if unused; add TTL cleanup.

### P10-20 — Privileged state trusted from the client (SharedPreferences) 🟡 Medium · Links **P9-20**
**Class:** Authorization · Integrity
**Evidence:** `subscription_screen.dart:52` reads sub status from `SharedPreferences` (defaults `'Active'`); role/sub used for gating decisions client-side. No server re-validation before privileged actions.
**Impact:** Client-authoritative entitlement; clearing/editing prefs or reinstalling changes perceived plan; defaults to "Active." Gating is decorative.
**Fix:** Server-authoritative entitlement checks; neutral default; re-verify on each privileged action.

### P10-21 — Over-broad world-readable tenant data (layout, capacity, pricing, contacts) 🟡 Medium (NEW)
**Class:** Confidentiality (competitive/recon)
**Evidence:** `supabase_schema.sql` — `shifts:561-562`, `floors:569-570`, `sections:577-578`, `seats:581-582`, `add_ons:?`, `libraries:544-545` all `FOR SELECT USING (true)` / status-permissive. Library owner contact and pricing are broadly visible.
**Impact:** Any client can enumerate every library's full seat map, capacity, shift pricing, and add-on prices — competitor recon and a UUID source feeding P10-01/02/04. Not "secret" data per se, but bulk-exposed beyond the join/explore need.
**Fix:** Return only fields needed for explore; consider gating detailed layout to members of that library.

### P10-22 — Excessive Android storage permissions 🟢 Low · Links **P1-11**
**Class:** Privacy (over-permission)
**Evidence:** `AndroidManifest.xml` declares `WRITE_EXTERNAL_STORAGE`/`READ_EXTERNAL_STORAGE` alongside `READ_MEDIA_IMAGES`; geolocator pulls location permissions for narrow use.
**Impact:** Larger attack/privacy surface and a Play data-safety/justification burden (Phase 14).
**Fix:** Drop legacy storage perms on modern SDKs; scope media access; justify or remove location.

### P10-23 — Raw backend exceptions surfaced to users 🟢 Low · Links **P9-22**
**Class:** Confidentiality (info leak)
**Evidence:** `join_flow_screen.dart:594`, `renewal_screen.dart:165`, `library_query_screen.dart:99` — `'Failed …: $e'` prints PostgREST/Supabase errors to the UI.
**Impact:** Leaks table/column/policy hints useful for crafting the attacks above.
**Fix:** Friendly messages; log details to telemetry only.

### P10-24 — Launcher activity `exported=true`; no deep-link scheme hardening 🟢 Low (NEW)
**Class:** Integrity (platform)
**Evidence:** `AndroidManifest.xml:17` `android:exported="true"` on the main activity (standard for launcher). UPI "deep links" are simulated (P3-02), so no real intent-filter validation exists yet.
**Impact:** Minimal today, but if real payment deep links are added later without intent verification, this is the place spoofing would enter.
**Fix:** Keep only the launcher intent-filter exported; validate any future deep-link inputs server-side.

---

## 7. Requested Security Registers

### 7.1 Privilege-Escalation Register
| # | From → To | Mechanism | Evidence | Sev |
|---|---|---|---|---|
| PE-1 | member → admin (role) | self-update `users.role` | `member_profile_tab.dart:1437`; RLS `:534-535` | 🔴 |
| PE-2 | member → all-tenant PII reader | create a library row ⇒ `users` SELECT-all | RLS `:531-532, 547-548` | 🔴 |
| PE-3 | member → free paid member | self-`UPDATE memberships` (status/expiry/seat) | RLS `:608-609` | 🔴 |
| PE-4 | member → Pro/Starter subscriber | self-write `subscription_status` / insert payment | `subscription_screen.dart:282`; `admin_home.dart:970`; RLS `:639` | 🔴 |
| PE-5 | ex-member → active member | revocation not checked; self-reactivate | RLS `:608-609`; attendance `:618` | 🟠 |
| PE-6 | any → forged "verified" identity | self-set `*_verified` | `member_profile_edit.dart:509-520` | 🟠 |

### 7.2 PII-Exposure Register
| Data | Where exposed | Who can read | Evidence | Sev |
|---|---|---|---|---|
| ID proofs (Aadhaar/PAN images) | `silence_private` (not scoped) | any authenticated user | `storage_setup.sql:67-70`; paths `member_profile_edit.dart:344` | 🔴 |
| Payment screenshots | `silence_assets` (public) | **anyone, no login** | `renewal_screen.dart:158`; `member_history_tab.dart:2740` | 🔴 |
| Member photos | `silence_assets` (public) | anyone | `member_profile_tab.dart:388`; `add_member_step1.dart:533` | 🟠 |
| Name/phone/email/address/DOB | `users` table | any user owning a library | RLS `:531-532` | 🔴 |
| Roster + phones (offline) | `silence_offline.db` plaintext | device holder | `offline_db.dart:51-62` | 🟠 |
| Library layout/pricing/owner contact | world-readable tables | any client | RLS `:544-582` | 🟡 |

### 7.3 Business-Abuse Register
| Abuse | How | Evidence | Sev |
|---|---|---|---|
| Free/infinite membership | self-`UPDATE memberships` | RLS `:608` | 🔴 |
| Free Pro/Starter subscription | self-write sub status; no payment | `subscription_screen.dart:282` | 🔴 |
| Fabricated revenue | hardcoded amounts + self-insert payments | `requests_sub_tab:328`; RLS `:639` | 🔴 |
| Attendance/streak/leaderboard fraud | self-insert attendance | RLS `:618`; `qr:417` | 🟠 |
| Forged proof of payment | upload any image | `renewal_screen.dart:220` | 🟠 |
| Self-awarded badges / forged referrals | open inserts | RLS `:60,:50` | 🟡 |
| Sabotage rival (cancel membership, delete QR/proofs) | open membership UPDATE + storage DELETE | RLS `:608`; `storage_setup.sql:52-55,86-89` | 🔴 |

### 7.4 Security Risk Matrix (Likelihood × Impact)
| Finding | Likelihood | Impact | Risk | Class |
|---|---|---|---|---|
| P10-01 private bucket read | High | Critical | **Critical** | Confidentiality/Privacy |
| P10-02 public PII | High | Critical | **Critical** | Confidentiality/Privacy |
| P10-03 storage tamper/delete | High | Critical | **Critical** | Integrity/Availability |
| P10-04 all-users read | High | Critical | **Critical** | Confidentiality/Authz |
| P10-05 memberships open UPDATE | High | Critical | **Critical** | Authz/Integrity/Business |
| P10-06 role escalation | High | High | **Critical** | Privilege Escalation |
| P10-07 billing bypass | High | High | **Critical** | Business Abuse |
| P10-08 no server tier | Certain | High | **Critical** | Authorization (root) |
| P10-09 attendance fraud | High | Med | **High** | Integrity/Business |
| P10-10 notification spoof | Med (latent) | High | **High** | Integrity/Phishing |
| P10-11 audit forgery | Med | High | **High** | Integrity/Non-repud |
| P10-13 auth theatre | High | Med | **High** | Authentication |
| P10-14 debug-signed/no INTERNET | Certain | Med | **High** | Integrity/Avail |
| P10-15 offline PII at rest | Med | High | **High** | Confidentiality |
| P10-16 payment honor system | High | High | **High** | Business Abuse |
| P10-12/17/19/20/21 | Med | Med | **Medium** | mixed |
| P10-18/22/23/24 | Low–Med | Low–Med | **Low–Med** | mixed |

### 7.5 Release-Blocker Register (must fix before ANY real-user exposure)
| # | Blocker | Owning findings |
|---|---|---|
| RB-1 | Storage object-level authorization (scope private bucket read/write/delete to owner; move PII off public bucket) | P10-01, P10-02, P10-03, P10-19 |
| RB-2 | Fix `users` SELECT to tenant scope; gate library creation | P10-04 |
| RB-3 | Remove `WITH CHECK (true)` on `memberships`/`notifications`/`audit_log`/`badges`/`referrals`; restrict to `service_role` | P10-05, P10-10, P10-11, P10-12 |
| RB-4 | Block client writes to `role`/`subscription_*`/`*_verified`; move to server | P10-06, P10-07, P10-13 |
| RB-5 | Introduce a server tier (RPC/Edge) for all privileged mutations + real payment verification | P10-08, P10-16 |
| RB-6 | Real authentication/verification (email confirm, real OTP) | P10-13 |
| RB-7 | Release keystore + `INTERNET` permission | P10-14 |
| RB-8 | Encrypt offline DB / drop PII caching | P10-15 |
| RB-9 | Server-authoritative entitlement; remove client-trust gating | P10-20 |

---

## 8. Special-Focus Deep Dives (as requested)

- **P5-01 (memberships UPDATE `true/true`) →** confirmed and elevated as **P10-05/PE-3**. This single policy converts the membership lifecycle into a free-for-all and, with P10-08 (no server job), is hit only by clients. It is the highest-leverage one-line fix in the codebase.
- **P5-07 (users SELECT to any owner) →** confirmed and **sharpened to P10-04/PE-2**: the policy isn't even role-gated; *library ownership* is the key, and ownership is self-grantable. This is the platform-wide PII breach.
- **P6-02 (role self-escalation) →** confirmed as **P10-06/PE-1**; note it is *not even required* for the PII breach (P10-04 stands alone), making the chain shorter than originally modeled.
- **P6-03 (subscription self-activation) →** confirmed as **P10-07/PE-4**, and extended: `payments` self-insert (`:639`) lets a member fabricate the payment record too.
- **Public-bucket usage →** the storage policy file proves it is worse than "PII in a public bucket": the bucket is `TO public` read **and** authenticated write/delete with no scoping (P10-02/03), and the *private* bucket shares the no-scoping flaw (P10-01).
- **OTP mock behavior →** `123456` self-verification (P10-13); account auth is real Supabase but identity attributes are self-asserted.
- **Hardcoded configuration →** reframed accurately (P10-18): the anon key is meant to be public; the real exposure is broken RLS behind it + no environment separation. Do not "fix" by hiding the key; fix the policies.
- **Direct-write architecture →** the root cause (P10-08): with 179 client writes and 0 server functions, **no** cross-column/business invariant can be enforced. Every finding above is a symptom of this.

---

## 9. Improvement Suggestions (security)
1. **Adopt object-level storage RLS** keyed on `(storage.foldername(name))[k] = auth.uid()` for member folders; one private bucket, owner+admin scoped; no PII in public buckets.
2. **Rewrite table RLS to least privilege:** every policy answers "does *this row* belong to the actor or the actor's tenant?"; ban `WITH CHECK (true)` for `authenticated`.
3. **Stand up a server tier** (Supabase Edge Functions / `SECURITY DEFINER` RPC) for approve-join, record-payment, change-role, renew, award-badge, write-audit, send-notification; revoke direct table writes for those.
4. **Real payment + webhook verification** before any `active`/`paid` state.
5. **Real identity verification** (email confirm, phone OTP); server-set `*_verified`.
6. **Encrypt at rest** (SQLCipher) and minimize cached PII; rely on OS keystore for sessions.
7. **Harden the build:** private keystore, `INTERNET` perm, drop excess permissions, friendly errors.
8. **Add automated RLS tests** (a "malicious member" integration suite that asserts each cross-row write/read is denied) — feeds Phase 13.

## 10. Priority Fix List (Phase 10, ordered)
1. **P10-01/02/03** — Fix storage authorization (private-bucket scoping; move PII off public; stop world-write/delete). *Highest blast radius, smallest change.*
2. **P10-05** — Remove `memberships` `true/true` UPDATE.
3. **P10-04** — Tenant-scope `users` SELECT + gate library creation.
4. **P10-06/07** — Lock `role`/`subscription_*`/`*_verified` from client writes.
5. **P10-08** — Introduce server tier; route privileged mutations through it.
6. **P10-10/11/12** — Close open `WITH CHECK (true)` inserts.
7. **P10-13/16** — Real verification + real payment.
8. **P10-14/15** — Keystore + INTERNET; encrypt/​minimize offline PII.
9. **P10-17/19/20/21** — Injection, temp bucket, client-trust, over-broad reads.
10. **P10-18/22/23/24** — Config hygiene, permissions, error leakage, export.

---

## 11. Feature Checklist (Phase 10 scope — security)
| Q | Verdict |
|---|---|
| Permissions correct | **No** — RLS grants cross-row/cross-tenant access; storage unscoped. |
| Data protected (confidentiality) | **No** — ID proofs & payment docs readable by any user / the public. |
| Integrity protected | **No** — memberships/attendance/audit/storage are tamperable. |
| Authentication sound | Partial — account auth real; identity attributes self-asserted; mock OTP. |
| Authorization sound | **No** — "authenticated" ≠ "authorized"; no server tier. |
| Abuse/hack resistant | **No** — billing bypass, fraud, sabotage all one REST call away. |
| Secrets managed | Partial — no `service_role` leak; anon key public-by-design but behind broken RLS. |
| Production-ready (security) | **No.** |

---

## 12. The Direct Answer — Could this app be safely exposed to real users today?

**No — unequivocally not.** Exposing SILENCE to real users today would, on day one, place every member's government ID, payment screenshot, phone number, and home address within reach of any other user (and, for the public bucket, anyone on the internet with no account), while letting any user grant themselves free paid memberships, rewrite or destroy others' records, and forge the audit trail meant to catch them. These are not edge cases requiring sophistication; each is a single crafted request permitted by the committed policies, reproducible with `curl` and the app's own (public) key.

**Go/No-Go: NO-GO for any public or paid release.** The release-blocker register (§7.5, RB-1…RB-9) is the gate. The encouraging part: the highest-impact fixes (P10-01/02/03/05/04) are **policy changes, not rewrites** — closing them removes most of the Critical surface quickly. But until a real **server-side authorization tier (P10-08)** exists, the client-trust model means new holes will keep appearing, and no amount of UI can compensate.

**Personal-data / regulatory note:** Under India's DPDP Act, exposing identity documents and contact data as described would be a reportable personal-data breach. This is a legal blocker, not only an engineering one.

---

**Limitations honored:** Policies were audited from the committed `supabase_schema.sql` / `storage_setup.sql`; I could not confirm the *live* project's deployed policies (declared in the roadmap). If production RLS differs from these files, findings P10-01…P10-12 and P10-19/21 must be re-verified against the live project (added to Verification Pending V-37…V-40). No `service_role` key, `.env`, or `google-services.json` was found committed (verified) — which prevents an even more severe outcome. No code was modified.

**Next:** `Start Phase 11` — Performance Audit.
