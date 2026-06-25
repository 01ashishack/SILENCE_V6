# CLAUDE.md — SILENCE Project Memory & Audit Handoff

> **Single source of truth a new session reads first.** Captures (a) the 16-phase audit (2026-06-08,
> evidence in `docs_audit/`) and (b) the **active remediation** since 2026-06-09 (3-phase UI/UX → Flow
> → Schema overhaul). Historical detail lives in `docs_fix/` + `docs_audit/`; this file is the index +
> current state. **Keep it under 40k chars** (trim oldest historical log when it grows).
>
> **Read order for a fresh session:**
> 1. **This file** (status + what's done + what's next).
> 2. **`docs_fix/UIUX_OVERHAUL_DECISIONS.md`** — product/UX decisions + golden rules. ⭐ OVERRIDES old spec.
> 3. **`docs_fix/IMPLEMENTATION_PLAN.md`** — 3-phase plan + full running build log (the detailed "what's done").
> 4. **`docs_fix/AUDIT_CHECKLIST.md`** — done/partial/pending vs the 16-phase audit. Fastest "what's left".
> 5. `docs_audit/AUDIT_PHASE_16.md` + the specific phase report — evidence behind a defect.

---

## 0. TL;DR — Status & Next Action

- **What this is:** SILENCE — Flutter + Supabase library / study-space management app for Indian
  Tier-2/3 cities (admins manage seats/members/attendance/payments/analytics; members track
  attendance, streaks, leaderboard, membership). **Single-tier "fat client"** — direct `.from(...)`
  writes; server tier (RC-1) is being introduced incrementally via Postgres `SECURITY DEFINER` RPCs +
  (now) the first Supabase Edge Function.
- **Mode: ACTIVE REMEDIATION.** Audit baseline was **~2.5/10** (22 C · 68 H · 63 M · 22 L). Executing a
  user-directed **3-phase overhaul: (A) UI/UX → (B) Flow/Functions → (C) Schema.**
- **⚠️ Source of truth = the EXISTING CODEBASE, not `silence_app/` spec.** Several decisions in
  `docs_fix/UIUX_OVERHAUL_DECISIONS.md` deliberately diverge from spec/audit.
- **Working rules:** refine warm-orange Material-3 (no redesign); UI consistency + color hierarchy;
  **no dishonest UI**; **ask before adding**; run `flutter analyze` after edits (0 new errors;
  pre-existing infos = baseline). **No live-DB access from agent** — schema changes are authored as
  `silence_app/migrations/*.sql` the USER applies. Commit/push only when asked; `Co-Authored-By` trailer.
- **Live DB project ref:** `kndeshxeerldamafweru` (`lib/core/supabase_config.dart`). Branch `main`,
  remote `origin` (github.com/01ashishack/SILENCE_V6).

### ⏳ REMAINING TASKS (open — not started)

**R1. Google social login — ✅ DONE + DEVICE-VERIFIED (2026-06-24).** Apple still stubbed.
`auth_screen.dart` `_handleGoogleSignIn()` does the native flow: `GoogleSignIn.instance.initialize(serverClientId: SupabaseConfig.googleWebClientId)` → `authenticate()` → `authorizationClient` for the access token → `supabase.auth.signInWithIdToken(provider: google, idToken, accessToken)`; web falls back to `signInWithOAuth`. After sign-in it bootstraps the `users` row (`_routeAfterAuth`) and routes like login (role null → `/role-select`, else admin/member home); user-cancel (`GoogleSignInException.canceled`) is silent. `google_sign_in: ^7.2.0`. **Web client ID `1085738355311-4pbt15ndhhcngedpp28ob8ru2bsl7bdl...` baked as the `googleWebClientId` default** (public, safe in-APK; `--dart-define=GOOGLE_WEB_CLIENT_ID=` still overrides) so plain `flutter run`/`build` work without flags. **Console DONE (user):** OAuth consent screen (External, test users), Web + Android (`com.silence.app.silence` + debug SHA-1 `7E:39:...:63`) client IDs, Supabase Google provider enabled (Web+Android client IDs, Web secret). Apple → "coming soon".
- **⚠️ Before Play Store:** add the **release keystore SHA-1** to the Android OAuth client (debug SHA-1 only works for `flutter run`/debug APK). Consent screen is in **Testing** → only added test users can log in until Published.

**R1-old. Google + Apple social login (UI exists, wiring is a stub).**
`auth_screen.dart` already shows Google/Apple buttons but `_handleOAuth()` just shows a "disabled"
message. To finish:
- **Code (agent):** add `google_sign_in` + `sign_in_with_apple` deps; replace `_handleOAuth` with the
  native ID-token flow → `supabase.auth.signInWithIdToken(...)` (web/desktop fallback =
  `signInWithOAuth`); after sign-in **bootstrap the `users` row** (id/email/full_name from OAuth
  metadata, role=null) and route exactly like login (role null → `/role-select`, else admin/member
  home); capture Apple name on FIRST sign-in only; handle user-cancel without an error snackbar.
- **Console (user, no code):** Google Cloud OAuth clients (Web + Android with debug+release **SHA-1/256**
  + iOS); enable Google in **Supabase → Auth → Providers** (paste client id/secret + authorized client
  ids); enable Apple (Service ID + Team ID + Key ID + .p8) — **needs paid Apple Developer + a Mac**.
- **Decision:** account-linking (Google email == existing email/password) — link vs separate identity.
- **Plan:** ship **Google first (Android + web)** from Windows; **Apple later** with the iOS build.

**R2. ⚠️ No Mac for Apple Sign-In / iOS.** Alternatives: ship Android+Google first (no Mac needed);
later use a **cloud Mac** (MacinCloud/MacStadium) or **CI macOS runner** (Codemagic/Bitrise/GitHub
Actions) for the iOS build/test. A **paid Apple Developer account (~₹8k/yr)** is required for Apple
Sign-In + App Store regardless.

**R3. Move all Google/Firebase to a dedicated BUSINESS Gmail.**
- **Preferred = TRANSFER ownership, do NOT recreate**: add the new business Gmail as **Owner** in
  Google Cloud (IAM) + Firebase (Project settings → Users and permissions), verify, then remove the old
  owner. Link/transfer the **billing account** separately. **If transferred, the project stays
  `silence-v6` → NO code/FCM changes needed.**
- **Only if a NEW Firebase project is created instead** (avoid this), the agent must update:
  `lib/firebase_options.dart`, `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`,
  Google OAuth client IDs, and the **FCM service-account/key secret** in the Supabase `send-push` Edge
  Function — plus re-register SHA fingerprints. (Much more work + risk.)
- GitHub / Supabase being on **different emails is fine** — no dependency between them.


**Batch B — DONE (fixes CRITICAL-1: settings screens self-resolving the library):** `flutter analyze`
0 issues; debug build OK. The old `eq('owner_id', uid).maybeSingle()` fallback **threw** for owners with
2+ libraries (PostgREST multi-row) and otherwise picked an arbitrary library.
- `active_library_store.dart`: added `resolve(passedId)` → passedId ?? persisted-active ?? first-owned
  (`order('created_at').limit(1)`, never `.maybeSingle()` on multi-row). Single safe resolver.
- Rewired the self-resolving screens to `ActiveLibraryStore.resolve(...)`: `scheduled_closures.dart`
  (was ignoring its passed `widget.libraryId`!), `shift_management.dart`, `qr_assets.dart`,
  `pricing_plans.dart`, `business_rules.dart`. Removed now-dead `_supabase` + supabase import in
  scheduled_closures. `admin_settings_service.firstOwnedLibraryId()` and `export_center._firstOwnedLibraryId()`
  now also go through `resolve(null)` so settings key off the active library, not an arbitrary first.
- **Remaining:** C = library-aware notifications (HIGH-1); D = combined dashboard + cross-library analytics
  (HIGH-2); E = "copy from / apply to other libraries". (Per-library vs global settings audit — MED-1 — is
  largely handled now that `settings` resolves to the active library; a fuller per-scope pass can come with D.)

**Batch C — DONE (fixes HIGH-1: library-aware notifications):** `flutter analyze` 0 issues; debug build OK.
**No DB migration** — `library_id` rides inside the existing `notifications.data` JSONB.
- `notification_service.dart`: `send`/`sendMany` take optional `libraryId` → stamped into `data.library_id`;
  `notifyLibraryOwner` (which already has the libraryId) now always stamps it. So every owner notification
  routed through the helper is library-aware automatically.
- `join_flow_screen.dart`: the direct "New join request" owner insert (most common owner notif, not via the
  helper) now includes `data.library_id`.
- `active_library_store.dart`: added `switchRequest` ValueNotifier + `requestSwitch(libId)` (persist +
  broadcast). `admin_home` listens (`_onExternalSwitchRequest`) and switches the active library + jumps to
  the dashboard tab when another screen requests it.
- `notifications_screen.dart`: loads the owner's `id→name` map; shows a **library chip** on each tile (only
  for multi-library owners); tapping an admin-destination notification calls `requestSwitch` so the shell
  opens on the **right** library (was always the active one). Members/single-library owners see no chip — graceful.
- **Coverage note:** chip+switch appear only for notifications that carry `data.library_id` (everything via
  `notifyLibraryOwner` + the join-request insert). Other direct inserts degrade gracefully (no chip). A later
  pass can stamp the remaining direct owner inserts.
- **Remaining:** D = combined dashboard + cross-library analytics (HIGH-2); E = "copy from / apply to other libraries".

**Batch D — DONE (fixes HIGH-2: combined / cross-library overview):** `flutter analyze` 0 issues; debug build OK.
- New `lib/screens/admin/all_libraries_overview_screen.dart` — read-only, additive cross-library dashboard:
  totals across all owned libraries (revenue this month, active members, pending requests, expiring ≤7d) +
  a per-library card (revenue / members / occupancy% / expiring + pending pill). Tapping a library calls
  `ActiveLibraryStore.requestSwitch(id)` and pops → admin shell switches to it. Pull-to-refresh.
- Aggregate queries grouped in Dart (no N+1), mirroring admin_home's exact columns (payments
  `status='confirmed'`+`payment_date>=firstOfMonth`; memberships `status` active/trial + `end_date`;
  seats `status` occupied/hold; join_requests `status='pending'`). **No DB changes.**
- Entry point: the in-home library switcher sheet shows an "All libraries overview" tile (multi-library only).
- **⚠️ DEVICE-VERIFY** the aggregate numbers against the per-library dashboards (queries couldn't be runtime-tested here).
- **Remaining:** E = "copy from / apply to other libraries" time-saver (per-library settings reuse).

**Batch E — DONE (time-saver: copy settings between libraries):** `flutter analyze` 0 issues; debug build OK.
- New `lib/screens/admin/copy_library_settings_screen.dart` — copy config INTO the current library from a
  chosen source library. Toggles: Shifts & plans / Add-ons / Amenities / Business rules. **COPY (one-time),
  not LINK** — copied rows are independent (no accidental cross-library coupling), additive (never deletes
  target data), warns about duplicate shifts/add-ons on re-run. Honest result snackbar (copied / failed counts).
  Queries mirror the canonical columns (shifts: name/times/price_*/trial_days/shift_type/hours_per_day,
  non-archived; add_ons: name/price/price_type/refundable_deposit/max_available/active; libraries.amenities;
  settings scope 'business_rules' + libraries.rules_metadata). **No DB changes.**
- Entry point: profile-tab library section → "Copy settings from another library" button (multi-library only),
  targets the active library; refreshes on success.
- **⚠️ DEVICE-VERIFY** (writes config to a live library): after a copy, confirm shifts/plans/add-ons/amenities/
  rules appear correctly in the target and the source is unchanged.

### ✅ Multi-library audit remediation A–E COMPLETE (app-layer). Remaining (not app-code):
- Device-verify all batches (Batch D aggregate numbers, C tap-switch, E copy results).
- Optional: stamp `library_id` on the remaining direct owner-notification inserts (C coverage).
- Optional: a fuller per-scope per-library-vs-global settings classification.

### Session 2026-06-25 (f) — Multi-library audit + Batch A (active-library single source of truth)

**Audit (this session):** SILENCE is multi-library-*capable* (data scoped by `library_id`; admin switcher
in reservations/analytics tabs; member analytics has 'all'+per-library) but not multi-library-*professional*.
Found: (CRITICAL-1) several settings screens self-resolve the library via `owner_id … maybeSingle()/limit(1)`
→ break or pick arbitrary with 2+ libraries; (CRITICAL-2) profile-tab had TWO sources of truth — a local
`_selectedLibraryIdToManage` dropdown that didn't switch the global active library, so settings opened a
different library than selected; (HIGH-1) notifications are per-user with no library label/scope, tap routes
to active lib not the originating one; (HIGH-2) no combined/cross-library dashboard; (MED) no persisted
active library, no current-library indicator on sub-screens. Scores: Mgmt 5, UX 4, Data-integrity 6.5,
Scalability 3.5. No cross-OWNER leakage found (DB scoping is sound); this is an app-architecture/UX problem.

**Batch A — DONE (fixes CRITICAL-2 + MEDIUM-3 persistence):** `flutter analyze` 0 issues; debug build OK.
- New `lib/core/active_library_store.dart` — persists the admin's last-active library id in SharedPreferences.
- `admin_home.dart`: added `_pickActiveLibraryId()` (prefers the persisted library if still owned, else first)
  used at both initial-load spots; added `_switchActiveLibrary(libId)` as the SINGLE switch entry point
  (setState + persist + reload); routed all 4 switch sites through it (in-home switcher sheet + the 3 tab
  `onLibraryChanged` callbacks). On launch the persisted library is restored before cached/fresh loads.
- `admin_profile_tab.dart`: the "manage which library" dropdown now calls `widget.onLibraryChanged(val)` so
  selecting a library **switches the global active library** (no more local-only divergence). `_buildSettingsItem`
  now passes `_selectedLibraryIdToManage ?? widget.libraryId` so every settings screen opens the selected lib.
- **Remaining (next batches):** B = remove `owner_id … maybeSingle()` self-resolution in settings screens
  (CRITICAL-1) + per-library vs global settings audit; C = library-aware notifications (HIGH-1);
  D = combined dashboard + cross-library analytics (HIGH-2); E = "copy from / apply to other libraries" time-saver.

### Session 2026-06-25 (e) — Perf batch 2: font subsetting + list-laziness audit

- **List laziness audit (no code change needed):** verified the heavy unbounded data lists already use
  lazy `ListView.builder`/`.separated` — members list, notifications, requests (join/seat-change/hold/
  checkin), archive, member-detail histories. The remaining eager `ListView(children:[...])` are all
  bounded (report sections, bottom-sheets). So no churn — the pagination/laziness win was already in place.
- **Font subsetting:** `tools/build_static_fonts.py` now also subsets each instanced static (fontTools
  `subset.Subsetter`) to Latin + the symbol ranges the app renders as text — verified to keep ₹ (U+20B9),
  • — – … "" ✓ ★ × é etc. Inter dropped **333 KB → 173 KB** per weight; bundled fonts total
  **~1.6 MB → 946 KB in the APK** (~650 KB saved + less per-font decode RAM on low-RAM phones). Inter/Outfit
  carry no Devanagari anyway, so Hindi names still fall back to the system font exactly as before — no change.
- **Verified:** ₹/✓/•/é/—/×/' glyphs present in the subset (fontTools cmap check); `flutter build apk
  --debug` succeeded; all 9 subset fonts confirmed inside the APK.

### Session 2026-06-25 (d) — Font bundling (eliminate first-paint font fetch jank) — ✅ DONE + build-verified

The app uses `GoogleFonts.inter()` / `GoogleFonts.outfit()` everywhere; previously these were fetched
over HTTP on first run (text flash / jank, and broke offline-first paint). Now the common static weights
are **bundled in `assets/google_fonts/`** so GoogleFonts uses them directly (no network fetch, instant
first paint). **Runtime fetching left ON** (default) as a safety net for any rare unbundled variant
(e.g. italics) — bundled assets take priority, so zero regression risk.
- Bundled weights (named exactly as the GoogleFonts API expects so the package auto-matches them):
  - Inter: Regular(400), Medium(500), SemiBold(600), Bold(700)
  - Outfit: Regular(400), Medium(500), SemiBold(600), Bold(700), ExtraBold(800)  *(w800 = section headers)*
  - `OFL.txt` shipped alongside; registered in `main.dart` via `LicenseRegistry` so it shows in the
    app's licence list.
- google/fonts only ships **variable** fonts for Inter/Outfit, so `tools/build_static_fonts.py`
  (one-off helper) downloads the VFs and instances the static weights with `fontTools` (pip:
  `fonttools brotli`). VF sources cached in `tools/_var_cache/` (gitignored); the generated statics
  (~1.6 MB total) are committed under `assets/google_fonts/`.
- `pubspec.yaml`: added `- assets/google_fonts/` to `flutter > assets`.
- `lib/main.dart`: foundation import now also shows `LicenseRegistry, LicenseEntryWithLineBreaks`;
  OFL license registered.
- **Verified:** `flutter analyze lib/main.dart` 0 issues; `flutter build apk --debug` **succeeded** and
  all 10 font files confirmed present inside the APK (`assets/flutter_assets/assets/google_fonts/...`).
- **NOT yet committed** (this + the (c) image-RAM batch are uncommitted).

### Session 2026-06-25 (c) — Performance wins for low-RAM phones (image RAM) — ✅ batch 1

Zero-dependency RAM wins to keep the app smooth on low-RAM devices (no new packages; these screens
don't use `cached_network_image`, so this only trims **decode/in-memory** cost — no disk cache added).
- `lib/main.dart` — global image-cache cap in `runZonedGuarded` after the kReleaseMode block:
  `imageCache.maximumSizeBytes = 50 << 20` (50 MB) + `maximumSize = 200` entries. Bounds the worst-case
  bitmap RAM that was previously unbounded.
- Downsized network-image decodes (decode at display size, not full-res) via `cacheWidth` (Image.network)
  / `ResizeImage(NetworkImage(...))` (avatars):
  - `requests_sub_tab.dart` — doc zoom `cacheWidth:1080` + thumb `ResizeImage w:300`; UPI proof zoom
    `ResizeImage w:1080` + thumb `w:150`.
  - `member_detail_screen.dart` — avatar `cacheWidth:200`; doc image `cacheWidth:720`.
  - `layout_sub_tab.dart` — seat-grid member photo `cacheWidth:120`; candidate-list avatar `ResizeImage w:150`.
  - `archive_sub_tab.dart` — list avatar `ResizeImage w:150`.
  - `library_setup_stage1.dart` — cover avatar `ResizeImage w:200`; gallery thumb `cacheWidth:360`.
- `flutter analyze` (6 touched files): **0 issues.** **NOT yet committed.**
- **Deferred (#3 fonts bundling):** GoogleFonts currently fetches at runtime; bundling the woff/ttf would
  cut first-paint jank but needs the font files / user OK. Recommend `flutter build apk --release
  --split-per-abi` for real perf testing (debug builds are not representative).

### Session 2026-06-25 (b) — Add-on save 400 (schema drift) RESOLVED + admin add-on UX hardening

**Root cause (found via Chrome `POST /add_ons → 400`):** the live `add_ons` table had drifted from the
canonical schema (missing `price_type` and/or `max_available`; possibly a legacy `total_inventory`), so
every add-on insert was rejected. On mobile the failed insert cascaded into the `_dependents.isEmpty`
red-screen. **Fix:** `migrations/2026-06-25_addons_schema_reconcile.sql` (idempotent — adds/renames the
missing columns, relaxes legacy `total_inventory`, reloads PostgREST cache) — **APPLIED to live DB;
verified columns now match (price_type NOT NULL default 'monthly', max_available present), add-on add
works.** Note: live `price_type` lacks the canonical CHECK; app only ever sends 'monthly'/'one_time' so harmless.
- Hardening done alongside (admin_profile_tab `_AddonsAmenitiesSheetState`): removed the loader-dialog +
  double-`Navigator.pop(sheetContext)` (replaced with inline button spinner + single pop), unfocus before
  pop, `_dataFuture` set directly in initState. `addon_services.dart` (separate `/admin/settings/addons`
  screen) also fixed: payload `price_type`+`max_available`, one-time init guard, deferred save, disposed controllers.
- Profile-tab grid item relabeled **"Amenities" → "Amenities & Add-ons"**.
- Join wizard: back now skips the (empty) add-ons step consistently with forward.

### Session 2026-06-25 — Joining-process overhaul (5c) — ✅ COMPLETE (device-test pending)

User-directed improvements to the whole join/approval flow. **No inflated scope** — "existing member"
= an OFFLINE member being migrated in (admin sets their real historical joining date).
- **5c-iii reject templates + review sheet + tag + discount/start-date DONE** — reject dialog has 4
  quick-pick reason chips; tapping a join-request card opens an applicant review sheet (personal details,
  ID docs front/back zoomable, payment proof, plan/shift/joining date, returning-member history) with
  Approve/Reject; each card shows a New / Existing(offline) / Renewal pill; the confirm-assignment dialog
  lets the admin set the start/joining date + an optional discount+reason → passed to RPC v2.
- **5c-iv Past requests DONE** — "Past requests" button above the join list opens a sheet of rejected +
  withdrawn requests with status pill + reason.
- `flutter analyze` 0 issues. **⚠️ DEVICE-TEST the whole flow** (submit→home; reject→reason+reapply to
  same library; approve new/existing with discount+date; existing-member joining date now shows; Past sheet).
- **Note:** the renewal-request path (`_approveRenewalRequest`) is still a separate non-atomic flow — a
  follow-up could route it through the RPC too (it keeps the existing seat, so needs a tweak).
- Files: `requests_sub_tab.dart` (+ earlier `join_flow_screen.dart`, `member_home.dart`, schema, migration).
- **5c-i DONE — `approve_join_request` v2** (`migrations/2026-06-25_approve_join_request_v2.sql`, folded into
  schema; DROPs the 2-arg, adds `p_discount`/`p_discount_reason`/`p_start_date`, all defaulting NULL so the
  existing 2-arg client call still works): honors `existing_member_join_date` (or admin override) as the
  membership `start_date` (fixes "joining date shows today"); admin discount applied to the plan price;
  payment records `original_amount`/`discount_amount`/`discount_reason`; member notification states the
  start date + any discount. **⏳ APPLY this migration to live DB.**
- **5c-ii DONE — member redirects:** (#1) join-flow confirmation "Go to Home" →
  `pushNamedAndRemoveUntil('/member/home')` (was a pop back to the library profile); (#2) rejected-request
  "Apply again" → pushes `JoinFlowScreen(sameLibraryId)` (was → explore).
- **5c-iii TODO (admin side):** tap a request card → applicant review screen (personal details, ID docs,
  payment proof, plan/shift, joining date, New/Existing tag, returning-member history); admin discount
  input + start-date edit (→ RPC v2 params); reject with 3-4 **template reasons** (no typing); changes notify.
- **5c-iv TODO:** requests "Past" section (rejected + withdrawn, with reason).
- Files so far: `join_flow_screen.dart`, `member_home.dart`, `supabase_schema.sql`, migration (new).

### Session 2026-06-24 (j) — Re-audit Batch 5b: atomic approve_join_request RPC (C3 + C5/M7)

`flutter analyze` **0 issues**.
- New `approve_join_request(p_request_id, p_seat_id)` SECURITY DEFINER RPC
  (`migrations/2026-06-24_approve_join_request_rpc.sql`, folded into `supabase_schema.sql`): owner-checked,
  requires the request still 'pending', **atomically claims the seat** (`UPDATE seats … WHERE status='vacant'
  RETURNING`; 0 rows → raises → full rollback, so **no double-booking** — closes C3 on this path),
  **derives the amount** from `shifts.price_*` − discount + add-on prices (no client-trusted amount),
  renews/creates the membership (IST dates), records the confirmed payment, inserts member_add_ons,
  approves the request, notifies + audits — **all in one transaction** (closes C5/M7 on the join path).
- `requests_sub_tab.dart` `_approveJoinRequestTransaction` now calls the RPC instead of ~7 separate client
  writes; success snackbar uses the RPC's returned seat label. (The 5a add-on M8 branch is now moot — it's
  all-or-nothing in the txn.)
- **⏳ APPLY to live DB:** `silence_app/migrations/2026-06-24_approve_join_request_rpc.sql`.
- **⚠️ DEVICE-TEST REQUIRED** (critical daily flow): approve a join (new + renewal), concurrent-seat race
  (second admin gets "Seat is no longer available", nothing half-written), add-ons persisted, payment
  confirmed with server amount, request → approved.
- **STILL OPEN:** the **add-member wizard** (`add_member_wizard.dart`) is the other non-atomic
  membership+seat+payment path (C3/C5/M7) — defer to a follow-up RPC. C2 offline full re-validation also open.
- Files: `requests_sub_tab.dart`, `supabase_schema.sql`, migration (new).

### Session 2026-06-24 (i) — Re-audit follow-ups Batch 5a (N1/N3/M8/Missed-1)

`flutter analyze` **0 issues**. Closes the safe, contained residuals the re-audit found.
- **N3 (urgent)** — `sanitize_display_name()` flipped from an `[:alpha:]` WHITELIST (which erased
  Devanagari/accented names → "User") to a BLACKLIST that only strips digits + `@ : /`. Names in ANY
  script now survive; phone numbers / URLs still stripped. Migration `2026-06-24_name_unicode_and_amount_bound.sql`
  + canonical schema updated.
- **Missed-1** — `payments.amount` now bounded `CHECK (amount BETWEEN -100000 AND 10000000)` (canonical
  inline; live DB via the same migration as `NOT VALID` so legacy rows aren't scanned). Blocks a tampered
  client recording a huge negative "payment" on the non-RPC insert paths.
- **N1** — join-approval renewal/new-membership dates in `requests_sub_tab.dart` now use `istNow()` (was
  device-local `DateTime.now()` → off-by-one expiry for non-IST admins). Same bug the H7 fix missed.
- **M8** — add-on insert failure in `requests_sub_tab` is no longer silent: the approval snackbar turns
  amber and says "add-ons could NOT be saved — please add them manually" (honest UI).
- **✅ APPLIED to live DB (2026-06-24):** `silence_app/migrations/2026-06-24_name_unicode_and_amount_bound.sql`.
- **STILL OPEN (next, larger + needs device testing):** C5/M7 atomicity on the join-approval +
  add-member-wizard money paths (route through an `approve_join_request` / shared RPC) and C3 (pending-seat
  + non-atomic `seats.status` flip — best fixed together with that RPC); C2 full offline-sync re-validation.
- Files: `requests_sub_tab.dart`, `supabase_schema.sql`, migration (new).

### Session 2026-06-24 (h) — Audit Batch 4 (scale/polish: L6, M5, H4, M4)

`flutter analyze` **0 issues**.
- **L6** — `main.dart` silences `debugPrint` in `kReleaseMode` (member IDs / library codes no longer leak
  to device logs; verbose in debug/profile).
- **M5** — `CacheService.writeCacheTimed()`/`readCacheFresh(ttl)` added; member-home explore-library cache
  now written timed + read with a 24h freshness gate (genuinely stale offline lists aren't shown forever).
- **H4** — new immutable `sanitize_display_name()` (letters/spaces/.'- only, strips digits/URLs, cap 20);
  `library_leaderboard()` formats names through it so an unmoderated nickname (phone/URL) isn't broadcast.
  Migration `2026-06-24_leaderboard_name_sanitize.sql` + folded into schema.
- **M4** — `purge_old_notifications()` + weekly pg_cron job deletes READ notifications older than 60 days
  (unread never deleted). Migration `2026-06-24_notifications_purge.sql` + folded into schema. (Client-side
  list pagination deferred.)
- **Deferred (with rationale):** H1 cron health-probe (DR safety net; live DB currently has all jobs),
  M3 leaderboard materialization (premature — fine to hundreds/library), M6 multi-library member-home
  aggregate state (UX edge).
- **✅ APPLIED to live DB (2026-06-24):** `2026-06-24_leaderboard_name_sanitize.sql`, `2026-06-24_notifications_purge.sql`.
- Files: `main.dart`, `cache_service.dart`, `member_home.dart`, `supabase_schema.sql`, 2 migrations (new).

### Session 2026-06-24 (g) — Audit Batch 3 (finance hardening: M7 + C5)

`flutter analyze` **0 issues**.
- **M7 + C5** — new `renew_membership(p_membership_id, p_plan_type, p_method)` SECURITY DEFINER RPC
  (`migrations/2026-06-24_renew_membership_rpc.sql`, folded into `supabase_schema.sql`): owner-checked,
  **derives the amount from `shifts.price_*`** (no client-trusted amount), extends `end_date` (IST),
  records a CONFIRMED payment + audit + member notification in ONE transaction. `admin_renew_sheet.dart`
  now calls the RPC instead of 4 separate client writes; removed the dead `_planLabel`/`_libraryId`/
  `_memberId`/AuditLogger usage.
- **M2 — already satisfied** (audit false positive): `expenditures.amount` already has `CHECK (amount > 0)`
  + category whitelist in the schema. No change.
- **H2 — accepted as-is**: a UNIQUE index for digest dedupe isn't feasible (the IST-date expression
  `(sent_at AT TIME ZONE 'Asia/Kolkata')::date` is STABLE, not IMMUTABLE, so it can't be indexed). The
  existing per-run EXISTS guard + single daily cron makes double-fire very unlikely; revisit only if cron
  parallelism is introduced.
- **✅ APPLIED to live DB (2026-06-24):** `silence_app/migrations/2026-06-24_renew_membership_rpc.sql`.
- Files: `admin_renew_sheet.dart`, `supabase_schema.sql`, migration (new).

### Session 2026-06-24 (f) — Audit Batch 2 (trust + quick wins, client-only)

`flutter analyze` **0 issues**. **No DB changes.**
- **H3** — FCM tap routing fixed: `_routeFromData` now deep-links via `data['route']` → else
  `NotificationService.routeForType(data['type'])` → else the user-scoped notifications center. Previously
  it ALWAYS opened `/member/notifications`, ignoring the payload (the advertised deep-link never happened).
- **H5** — `main.dart` textTheme built from `Typography.material2021().black` instead of
  `Theme.of(context)` (which, above the MaterialApp, silently dropped the custom theme).
- **H7** — admin-renew extends `end_date` from `istNow()` (was device-local `DateTime.now()` → off-by-one
  for non-IST devices).
- **H8** — extracted `_isExpiredMembership()` helper in member_home; both expired-state `firstWhere`
  predicates now call it (DRY; behavior unchanged — both already used `istNow()`).
- **M1** — deleted dead `MemberAnalyticsService.fetchLeaderboard()` (superseded by the RPC-based
  `fetchLeaderboardDetails()`).
- **Deferred:** L5 (`minCheckoutMinutes` is intentionally 0 — re-enabling is a product decision, left as-is).
- Files: `push_notification_service.dart`, `main.dart`, `admin_renew_sheet.dart`, `member_home.dart`,
  `member_analytics_service.dart`.

### Session 2026-06-24 (e) — Audit re-audit: Batch 1 (attendance data integrity: C1/C2/C4)

`flutter analyze` **0 issues**. Fixes the 3 confirmed-critical attendance-integrity bugs from the
2026-06-24 GLM re-audit (C3 was overstated — `uq_membership_active_seat` already prevents two
active/trial members on a seat; C5 is admin-records-own-revenue, low impact; H6 already a PK).
- **C4** — duplicate open sessions: new migration `2026-06-24_attendance_open_session_unique.sql`
  (cleans existing dup opens → 'incomplete', then partial UNIQUE index `uq_attendance_open_session`
  on `attendance(member_id, library_id) WHERE check_out_time IS NULL`). Scanner check-in now catches
  `23505` → "You are already checked in" instead of opening a 2nd session. Folded into `supabase_schema.sql`.
- **C1** — offline checkout no longer re-closes an already-closed row (that produced multi-day phantom
  durations). The dangerous "find latest row & re-close" fallback is removed; an orphan checkout is
  discarded (FIFO guarantees a real check-in syncs first). Normal checkout update now guarded with
  `.isFilter('check_out_time', null)`.
- **C2** (interim) — offline check-in sync now discards rows landing on a CLOSURE day; offline rows stay
  flagged via `offline_synced=true`. Full shift-window/overtime re-validation on sync still TODO.
- **✅ APPLIED to live DB (2026-06-24):** `silence_app/migrations/2026-06-24_attendance_open_session_unique.sql`.
- Files: `offline_sync.dart`, `qr_scanner_screen.dart`, `supabase_schema.sql`, migration (new).

### Session 2026-06-24 (d) — Overtime/holiday auto-checkout fixes + admin overtime setting

`flutter analyze` **0 issues**. Touches holiday flow, live-session timer, scanner notification, admin profile,
and the overtime cron. **2 new migrations to apply** (see below).
- **Holiday force-checkout now notifies members** — `HolidayService.closeOpenSessionsNow()` collects each
  open session's `member_id`, force-checks-out (session_type='closed'), AND inserts an `auto_checkout`
  notification ("Checked out — library closed"). The notification also makes the member's home reload
  (notifications channel) so the **live timer stops** without a manual refresh.
- **Reason-warning z-index fixed** — both add-holiday sheets (`admin_home.dart`, `scheduled_closures.dart`)
  showed "Please add a reason" via a SnackBar that rendered BEHIND the bottom sheet. Now an inline
  `errorText` on the reason field (clears on typing).
- **Client-side overtime auto-checkout + shift-end warning** (`member_home.dart` `_updateSessionTimerValues`):
  when the shift ends it warns the member once (`shift_end`, sets `overtime_warned` to dedupe the cron);
  30 min later it auto-checks-out (capped 30, session_type='auto_checkout'), stops the timer, reloads, and
  notifies member + owner — instead of waiting up to 5 min for the server cron. Gated by the library setting.
- **Admin checkout notification is specific** — scanner `_notifyOwnerAttendance(..., overtimeMinutes, afterShift)`
  → "X checked out after their shift ended — N min of overtime."
- **NEW admin setting `libraries.auto_checkout_overtime`** (default true). Toggle in Admin Profile
  ("Auto check-out on overtime", per active library). `process_shift_overtime()` re-created to honor it
  (always warns at shift end; only auto-closes when ON). Client `member_home` reads it from `libraries(*)`.
- **✅ APPLIED to live DB (2026-06-24):** `silence_app/migrations/2026-06-24_overtime_auto_checkout_setting.sql`
  (adds the column + re-creates the cron fn; folded into `supabase_schema.sql`) AND
  `2026-06-24_realtime_publication_gaps.sql` (publication gaps + REPLICA IDENTITY FULL — timer stops instantly
  when the SERVER cron closes a session while the app is open). **No outstanding live-DB action.** On-device
  verification of the overtime/holiday flows still recommended.
- Files: `holiday_service.dart`, `admin_home.dart`, `scheduled_closures.dart`, `qr_scanner_screen.dart`,
  `member_home.dart`, `admin_profile_tab.dart`, `supabase_schema.sql`, migration (new).

### Session 2026-06-24 (c) — Time-based notifications (pg_cron) — ✅ APPLIED to live DB

**No code changes** (types were already wired in (a)). Migration
`silence_app/migrations/2026-06-24_time_based_notifications.sql` — 5 SECURITY DEFINER functions +
pg_cron jobs, all idempotent & self-deduping (never twice in the same IST day), reusing the
already-routed/styled types:
- `notify_membership_expiry()` — MEMBER `expiry` at 3d / 1d / today (daily 09:00 IST).
- `notify_admin_expiring_digest()` — OWNER `expiring_digest`, members ≤3 days out (daily 09:30 IST).
- `notify_streak_reminders()` — MEMBER `streak_reminder`, attended yesterday not today (daily 19:00 IST).
- `notify_daily_collection_summary()` — OWNER `daily_summary`, today's confirmed ₹+count (daily 21:30 IST, skips ₹0 days).
- `notify_dues_digest()` — OWNER `dues_digest`, lapsed memberships (end_date < today) (weekly Mon 09:00 IST).
- **✅ APPLIED to live DB (2026-06-24)** + folded into `supabase_schema.sql`. All 5 cron jobs confirmed
  active in `cron.job` (jobids 1-5: silence-expiry-reminders / -expiring-digest / -streak-reminders /
  -daily-collection / -dues-digest). pg_cron fires in UTC = the IST times above. **No outstanding live-DB action.**

### Session 2026-06-24 (b) — Google Sign-In (native) wired + device-verified

`flutter analyze` **0 issues**. **No DB/migration changes.**
- `google_sign_in: ^7.2.0`. `auth_screen.dart`: real `_handleGoogleSignIn()` (v7 API: `initialize(serverClientId:)`
  → `authenticate()` → `authorizationClient.authorizeScopes` → `signInWithIdToken(google,...)`); `_routeAfterAuth`
  bootstraps the `users` row + routes like email login; cancel = silent; web = `signInWithOAuth` fallback.
- `supabase_config.dart`: `googleWebClientId`/`googleIosClientId` (dart-define overridable). **Web client ID baked
  as default** so every build works without flags. Android client ID + Web client secret live only in Supabase/console.
- **User completed the console side** (consent screen + Web/Android OAuth clients + Supabase provider) and **verified
  Google login works on device.** Apple still a "coming soon" stub (R2 — needs Mac + paid Apple acct).
- Files: `pubspec.yaml`, `lib/core/supabase_config.dart`, `lib/screens/auth_screen.dart`.

### Session 2026-06-24 (a) — Notifications: shared helper + full coverage + click-redirect audit

`flutter analyze` **0 issues (whole project)**. **No DB/migration changes** (time-based digests still pending — see below).
- **New `lib/services/notification_service.dart`** — single place that writes `notifications` rows with a
  consistent payload `{type, route?, ...extra}`. Methods: `send`, `sendMany`, `notifyLibraryOwner`,
  `routeForType` (type → canonical named route, only routes that exist in the table). All sends are
  best-effort (never throw into the caller — a failed notification must never break the action).
- **Newly-wired button-triggered notifications** (were missing): `seat_change_request` → owner
  (`seat_change_bottom_sheet.dart`); `new_review` → owner (`library_public_profile_screen.dart` +
  `past_library_detail_screen.dart`); `member_exited` + `refund_request` → owner (`member_home.dart` on
  self-exit); `badge` payload upgraded with `type`/`route`/friendly label (`member_analytics_service.dart`).
- **Click-redirect audit of ALL existing notifications** — `notifications_screen.dart` `_onTapNotification`
  switch + `_NotifStyle.forType` (icon/colour) now cover every `type` used anywhere in the app. Found &
  fixed 3 types that had NO route/icon (fell to default bell, no navigation): **`check_in`/`check_out`**
  (owner attendance pings → `/admin/home`, login/logout icons) and **`attendance_manual`** (admin manual
  check-in/out of a member → `/member/home`, login icon). Member types → `/member/home`, admin → `/admin/home`;
  `query_reply`/`new_query`/`refund_request` → `ContactAdminScreen`; `announcement` → in-place dialog.
- **Verified existing loops are intact**: admin query **reply** → member `query_reply`; member **query**
  → owner `new_query`; join/payment/hold/renew/transfer/seat all carry a covered `type`.
- **Still pending (separate batch — needs a pg_cron migration the USER applies, like the overtime one):**
  time-based notifications — expiry reminders (3d/1d/today), admin expiring-members digest, streak
  reminder, daily collection summary, dues digest. Their `type`s are already mapped in `routeForType`.
- Files: `notification_service.dart` (new), `notifications_screen.dart`, `seat_change_bottom_sheet.dart`,
  `library_public_profile_screen.dart`, `past_library_detail_screen.dart`, `member_home.dart`,
  `member_analytics_service.dart`.

### Session 2026-06-23 (e) — Member top-bar / status-bar color unified across tabs & states
`flutter analyze` 0 issues. **No DB/migration changes.**
- All 4 member tabs' headers unified to the brand `[#E65C00, #C44E00]` **vertical** gradient
  (`topCenter→bottomCenter`) so the header's top edge is one uniform colour (Analytics was the odd one
  using brighter `#FF6B00`; Profile was already correct). History + Home stage gradients also made vertical.
- `member_home._topSafeAreaColor` is now **dynamic** = the current header's first colour: Home → the current
  `MemberState` colour (orange / amber-pending / red-expired / purple-trial / amber-hold / grey-exited);
  Analytics/History/Profile → `#E65C00`. Status-bar strip now matches the header in **every** tab and Home
  state with no seam (fixes the "yellow home but orange/white status bar" mismatch).
- Files: `member_home.dart`, `member_analytics_tab.dart`, `member_history_tab.dart`.

### Session 2026-06-23 (d) — CSV export crash fix (web "_Namespace") + key mismatch
`flutter analyze` 0 issues. **No DB/migration changes.**
- **CSV "Unsupported operation: _Namespace" fixed**: CSV sharing wrote a temp file via `dart:io`
  `Directory.systemTemp`, which throws on web (PDF worked because `printing` shares bytes). Now branches on
  `kIsWeb`: **web → share bytes via `XFile.fromData`**, **native → temp file** (the proven path). Fixed in
  `csv_exporter.dart` `_shareFile` and the member-history combined CSV (`member_history_tab.dart`).
- **CSV key mismatch fixed**: `MemberAnalyticsService.fetchAttendanceForExport` didn't supply `shift`,
  `is_overtime`, and its `seat` was always N/A (attendance has no seat column). Now joins
  `memberships(seats(seat_label))` and returns shift + overtime + real seat, so the member's own attendance
  CSV columns fill correctly.


`flutter analyze` 0 issues. **No DB/migration changes.**
- **Member-wise attendance** (`attendance_export_preview.dart`): replaced the flat member-name chips with
  **faceted filters — Shift / Floor / Category** (+ a **Members** checklist), each opening a multi-select
  bottom-sheet (default **All**). Effective member set = facet-filtered ∩ manual member selection. Loads
  shift/floor (via `floors`)/`exam_category` per member.
- **Export Center** (`export_center.dart`): removed the top Today/Week/Month/Custom bar. Tapping **CSV/PDF**
  on a report now opens a **period chooser** (Today / This Week / This Month / Custom Range) and then exports
  for the chosen range. The **Attendance Log** card now has **Date-wise / Member-wise** buttons that open the
  full attendance preview screen (its own filters + CSV/PDF).
- Files: `lib/screens/reports/attendance_export_preview.dart`, `lib/screens/export_center.dart`.
- (Library facet omitted — the Export Center / analytics are already scoped to a single library.)


`flutter analyze` 0 issues (whole project). **No DB/migration changes.**
- **PDF layout/logo fixes** (`pdf_exporter.dart`): top margin 122→18 (killed the big blank strip above the
  letterhead), bottom 58→20; header logo switched to the pure-white `WHITE_WITH_TAGLINE.png` at 42px (was
  blending into the orange); footer logo switched to `BLack_name_with_tag.png` at 26px (bigger). **Times now
  render in IST** in both PDF & CSV (was UTC). **Members Roster** gained a **Joined** column.
- **New report types** in the shared engine: `exportExpenses`, `exportMemberwiseAttendance` (grouped per
  member: Date/Check-in/Check-out/Duration/Overtime).
- **Attendance preview screen** (`lib/screens/reports/attendance_export_preview.dart`): the admin Analytics
  Attendance tab "Preview & Export" now opens this. **Date-wise** → date/range picker + every member's
  attendance (Member, Seat, Check-in, Check-out, Duration, Overtime). **Member-wise** → month stepper +
  member multi-select (All / one / more) + per-member sessions. Both export CSV/PDF from the preview via the
  shared engines (respecting the on-screen filter).
- **Revenue preview screen** (`lib/screens/reports/revenue_report_preview.dart`): the Revenue tab "Export &
  View Reports" buttons now open this (Revenue & Expenses / Expenses / Payments) with a **date filter**
  (Today/Week/Month/Custom, default This Month) and **working** CSV+PDF exports that emit the filtered data —
  the old `_showReportGridModal` (with dead `debugPrint` placeholder exports) is removed.
- **Member-detail ("profile") attendance export**: CSV now carries the overtime flag + shift; PDF reshape
  (Member/Seat/Shift) was fixed earlier.
- **Files:** `lib/utils/pdf_exporter.dart`, `lib/utils/csv_exporter.dart`,
  `lib/screens/reports/attendance_export_preview.dart` (new), `lib/screens/reports/revenue_report_preview.dart`
  (new), `lib/screens/admin_analytics_tab.dart`, `lib/screens/reservations/member_detail_screen.dart`.
- **Note:** header white logo assumes `WHITE_WITH_TAGLINE.png` is a true-white wordmark; if it still blends,
  swap the asset. The empty mid-page area on a near-empty report is inherent to a full-page A4 layout.


`flutter analyze` 0 issues (whole project). **No DB/migration changes.** Reworked all PDF/CSV exports to 10/10.
- **One engine, no divergence:** `export_center.dart` (admin Exports & Reports Center) no longer has its own
  inline PDF/CSV logic — it now only fetches rows and delegates to the shared `PdfExporter` / `CsvExporter`.
  Every screen (admin center, admin analytics, member history/analytics, member-detail) shares one output format.
- **₹ glyph fixed:** `pdf_exporter.dart` now embeds Noto Sans (via `PdfGoogleFonts`, cached) as the document
  theme, so the rupee symbol renders instead of a blank box; graceful fallback to the base font if offline.
- **PDF redesign:** brand orange letterhead band with the **white logo** (`transparent_logo_with_white_name.png`),
  KPI summary tiles, zebra tables with right-aligned money + bold **TOTAL** rows, footer with the **dark logo**
  (`transparent_logo_with_black_name.png`) + page numbers; receipt uses the **app icon** (`only_icon.png`).
  Money via `NumberFormat en_IN` (₹1,00,000 grouping).
- **CSV machine-friendly:** column header is row 1 (clean import), amount columns are plain numbers labelled
  `(INR)` (so `=SUM()` works), single sortable `yyyy-MM-dd[ HH:mm]` dates, a trailing `# Summary` block with
  totals + meta, and a UTF-8 BOM so Excel detects encoding.
- **Bug fixes:** admin single-member **PDF attendance** now reshapes rows (was N/A for Member/Seat/Shift);
  Export Center **occupancy** relabelled an honest "current snapshot"; **revenue** now merges `expenditures`
  into a real daily P&L with cash/UPI split + grand total.
- **Completeness:** added **Upcoming Expirations** + **Attendance Summary** (member-wise check-ins/hours/avg)
  to the shared engine; replaced the old hack that mis-rendered member-wise hours through `exportDues`
  (and removed a `$widget.libraryName` interpolation bug in the old inline CSV). Overtime `+OT` tag flows
  through attendance lists, history, PDF and CSV.
- **Files:** `lib/utils/pdf_exporter.dart` (rewritten), `lib/utils/csv_exporter.dart` (rewritten),
  `lib/screens/export_center.dart` (rewritten — delegates), `lib/screens/reservations/member_detail_screen.dart`,
  `lib/screens/admin_analytics_tab.dart`.
- **Note:** Noto Sans is fetched on first use (network, then cached) like the app's existing GoogleFonts usage;
  bundle a TTF later if fully-offline ₹ rendering is required. Member History's combined CSV (3 datasets in one
  file) stays a multi-section format by design; its PDF path uses the shared engine.


`flutter analyze` 0 issues (whole project). Committed+pushed at **`5e9212e`**.
- **✅ Migration APPLIED to live DB (2026-06-22)** + folded into `supabase_schema.sql`:
  `silence_app/migrations/2026-06-22_overtime_and_checkin_approvals.sql` — adds
  `attendance.is_overtime/overtime_minutes/overtime_warned`, the `checkin_approvals` table (+RLS),
  `consume_checkin_approval(uuid)` RPC, and the `process_shift_overtime()` cron (every 5 min).
  **No outstanding live-DB action.** *(If `pg_cron` wasn't present, confirm `process_shift_overtime()` is
  scheduled manually — Dashboard → Database → Cron, every 5 min — else shift-end warnings + auto-checkout won't fire.)*
- **Overtime (30-min hard cap) + auto-checkout:** manual checkout (`qr_scanner_screen.dart`) caps the
  recorded check-out at `greatest(shiftEnd, checkIn)+30min`, tags `is_overtime`/`overtime_minutes` (≤30).
  `process_shift_overtime()` (cron) **WARNs once** ("your shift ended, please check out") when a session
  passes shift end, then **auto-checks-out** 30 min later (`session_type='auto_checkout'`, overtime-tagged),
  notifying the member. Active-session card now shows "Overtime (max 30 min)" + the auto-checkout clock.
- **Out-of-shift check-in approval flow:** scanning earlier than 15 min before shift start, or after shift
  end, files a **pending `checkin_approvals`** row + notifies the owner, and shows the member a warning
  (wait for approval / contact admin) — **no attendance written**. Admin approves/rejects in a new
  **"Check-ins" tab** in Requests (`requests_sub_tab.dart`); approval is valid 30 min and notifies the
  member to re-scan; the resulting check-in is **overtime-tagged** and the approval is burned via
  `consume_checkin_approval()`. Rejection notifies the member to contact the admin.
- **Overtime tag surfaced** in member analytics session list, history list, **PDF & CSV** exports (`+OT`).
- **Notifications** (`notifications_screen.dart`): icons/routes for `shift_end`, `auto_checkout`,
  `checkin_approved`, `checkin_rejected`, `checkin_approval_request`.
- **Analytics fixes** (`member_analytics_tab.dart` + `member_analytics_service.dart`):
  - **Streak count bug fixed** — `fetchStreak` now computes current/best FROM ATTENDANCE (authoritative);
    the unmaintained `streaks` table is only a defensive floor for best (a stale `current_streak=0` row no
    longer forces "0 Day Streak" when present days exist).
  - **Week-day circles** made clearly visible on the orange card (filled rings/centres per state).
  - **Stat-card overflow fixed** — `childAspectRatio 1.55→1.28` (the 30px value + avg/day subtitle overflowed).
  - **Achievements: earned badges first** via `_orderedBadgeDefinitions` (most-recently-earned first, then locked).
- **Member safe-area color** (`member_home.dart`): all four member tabs open on the orange header, so the
  status-bar inset is now always primary orange (was cream over Analytics/History → mismatched their orange headers).


Builds on the still-uncommitted member-home work; this batch is being committed now (see commit at end).
`flutter analyze` 0 issues on all touched files. **No DB/migration changes.**
- **Member-home membership card** (`member_home.dart`, `_buildMembershipCard`): reworked into a
  **library ID-card** — header shows the **library cover photo + library name (big) + city** (was member
  photo/name), verified tick kept; soft **warm-cream gradient** (`white → #FFF7F0`) instead of the earlier
  status-green wash (user: green looked bad); status-tinted shadow + colored left border retained; Renew
  moved into the top-right ⋮ menu; colorful tinted info chips (Seat/Shift/Timing/Joined/Plan/Price).
- **Active Session card** (`_buildActiveSessionCard`): redesigned — **green-gradient header** with a
  "LIVE SESSION" badge + big running HH:MM:SS timer + "Checked in at…", white body with shift-progress
  bar, Seat + Shift chips, full-width **Shift Timing** row (fixes the truncated `07:00 AM–07…`),
  time-remaining/overtime tinted box, motivational line, orange Check Out CTA. **Seat "pending" bug:**
  the active-attendance query had no seats join → now `memberships(*, seats(*))` so the real seat shows.
- **Previous/Yesterday session card** (`_buildPreviousSessionCard`): removed the `widthFactor 0.82`
  wrapper (full-width again, just compact height) — only Date + Duration + Check-In + Check-Out.
- **History tab — "every sub-tab shows Refresh" ROOT CAUSE FIXED** (`member_history_tab.dart`): the
  attendance fetch joined `seats(seat_label)` directly, but `attendance` has **no `seat_id` FK** →
  PostgREST relationship error blanked the whole tab into the error state. Switched to
  `memberships(seats(seat_label))` (valid path) and flatten `seats` back onto each row so renderers are
  unchanged. Sessions/Payments/Memberships load again.
- **Analytics tab** (`member_analytics_tab.dart` + `member_analytics_service.dart`):
  - 4 stat cards: shorter (`childAspectRatio 1.25→1.55`) + bigger text (value 22→30, title 10→12) to
    kill the blank space.
  - **Leaderboard → top 10** (was top 5; service `.take(10)` + gap-to-10th); list scrolls in a capped
    box while the member's own **pinned rank row stays fixed** below (never scrolls out) when outside top 10.
  - **Calendar heatmap fix:** present days were only shaded at `hours ≥ 1.0`, so short/uncomputed days
    stayed white (only today's border showed) — now **any attendance day** gets ≥ the lightest tier, with
    2-4h / 4h+ intensities on top (both month + year views; legend → Absent/<2h/2-4h/4h+). Added **month+year
    picker** (tap the calendar title → year stepper 2020→now + 12-month grid); back-chevron relaxed to 2020.


Committed+pushed at **`a26943a`** (analytics + headers + profile + signup + member polish). The
follow-up member-home audit-fix batch + the 2026-06-20 visual overhaul / history / analytics work are
**now committed** (see the 2026-06-20 session above). `flutter analyze` 0 errors throughout.
**✅ Migration APPLIED to live DB (2026-06-19) + folded into `supabase_schema.sql`:**
`2026-06-19_library_display_fields.sql` (libraries.`opening_hours`, `display_members_joined`).
**No outstanding live-DB action.**
*(The geo `latitude/longitude` migration was dropped — coordinates are impractical for admins; the
public profile's "View on Map" button uses `location_link` (Google Maps link) instead.)*

- **Admin Analytics tab** (`admin_analytics_tab.dart` + new `lib/widgets/charts/analytics_painters.dart`):
  filter change re-processes cached raw (no re-fetch); every chart painter has a correct `shouldRepaint`
  (no per-frame repaint); fetch joins trimmed to needed columns; bigger KPI cards; smooth (Catmull-Rom)
  line chart; 10 painters extracted to a widget file; header date → IST; **Refund Requests** stat folded
  into Net Profit subtitle (`Expenses ₹X · Refunds N`); **'Today' preset removed** from Revenue + Shifts&Plans,
  default **This Month**; Floor/Shift selectors Expanded (no blank gap).
- **Unified admin sub-screen header**: new `lib/widgets/app_gradient_scaffold.dart` (curved orange-gradient
  header) applied to **14 sub-screens** (About/Help/Terms/Audit/App-Settings/Referrals/Subscription/Shifts/
  Exports/Announcements/Verified-Badge/Edit-Profile/Recovery/Payment-Methods). New tokens in `AppColors`:
  `headerGradient`, `primaryLight`, `cardRadius`. Export now uses the app's custom calendar (was stock range picker).
- **Admin Profile tab** (`admin_profile_tab.dart`): library-profile **completeness progress bar** (green) +
  pending-detail chips; sections reordered priority-wise; new **Privacy & Account** section (Change Role +
  Logout + Delete Account moved there); **About & Info** option on the Library-Management card — admin edits
  **About / Opening Hours / Members-Joined label**, all synced to the public profile + completeness bar;
  Library-Management grid reorder (Edit Profile first, Rules last) + Rules sheet note ("shown in member app,
  not public profile"); plan name now via `PlanService.displayPlanName` (Free/Pro/Premium — was raw 'Starter');
  removed fake "All systems operational"; verified tick orange.
- **Public profile** (`library_public_profile_screen.dart`): shows manual `opening_hours` (else shift-derived)
  + a stats strip (Members joined / Rating / Reviews) using admin's `display_members_joined`.
- **Signup fix** (`auth_screen.dart`): profile-row write only when a session exists (kills the JWT error);
  on "already registered" it auto signs-in with the same creds (no dead "already member"); confirmation-pending → Login tab.
- **Admin Home**: top "in today" = total who came today; "Active Now" card = LIVE present (checked-in, not
  out) / total; stat-card sizing + gap fixed; **new notifications** — join request → admin, member check-in/out → admin
  (approve/reject→member already existed). Notifications rely on the applied actor-scope RLS (no new migration).
- **Member**: profile-edit ID upload → **Front (required) + Back** photos (matches add-member wizard); seat-grid
  avatar `BoxFit.cover` (was original-ratio with blue gaps).
- **Member-home AUDIT fixes (now committed — see 2026-06-20 session):**
  - **C1** unguarded `setState` in `finally` → `mounted`-guarded (join_flow ×2, member_profile_tab photo).
  - **C2** join_flow `maybeSingle()` on non-unique filters → `.limit(1)`; referral block isolated + non-fatal (runs post-commit).
  - **H1** Explore distance feature **removed entirely** (lat/long impractical for admins): dropped GPS/
    `geolocator` permission prompt, `_calculateDistance`, distance display, and the lat/long fields in
    admin Basic Details. Members reach a library's location via the public-profile "View on Map" button
    (uses admin's `location_link` Google-Maps link, with address-search fallback).
  - **H2** History "Absent" miscount → absent now scoped to active-membership days, open days, ≤ today (matches the list).
  - **H3** Analytics tab had no error state → real `ErrorState`+retry on first-load failure (no fake zeros).
  - **H4** member_home one big `try` → non-critical tail (announcements/streak/activities) isolated so it can't drop core data to stale cache.
  - **H5 + M1** timezone: renewal gate, history ranges/absent loop, trial days-left, `_daysLeftDateOnly` all on `istNow()`.
  - **Deferred (noted):** P1 streak full-attendance scan (perf); M2 multi-library single-state; M3 profile expired-as-active;
    M5 notifications 100-cap; M6 profile pull-to-refresh.

### Session 2026-06-17 — Add-Member wizard fixes (verified by user on-device)
All in `lib/screens/admin/` (+ migrations). `flutter analyze` clean on touched files. Committed+pushed.
- **ID upload rework** (`add_member_step1.dart`): removed doc-type dropdown; single **"Upload ID"** =
  **Front (required)** + **Back (optional, no "optional" label)** square tiles; uploads to
  `silence_private` **immediately** with circular-progress overlay; `MemberData` gained
  `idProof1Url/idProof2Url`; validation requires Front; finalize reuses uploaded paths.
- **Add-Member "permission denied" — ROOT CAUSE (no DB change fix):** new-member `users` insert used
  `.insert(...).select('id')` → `INSERT ... RETURNING id`. The tenant-scoped SELECT policy
  (`Admins can view library members`, 2026-06-14) only lets an owner read a user who is ALREADY a
  member; a brand-new member has no membership yet → RETURNING rejected `42501`. **Fix:** generate id
  client-side (`uuid`), insert **without** `.select()` (`add_member_wizard.dart`). Added per-step
  `opLabel` + auth/tenant diagnostics in `_finalizeRegistration`.
- **"Could not save your changes" = `email NOT NULL`** (wizard treats email optional → NULL → 23502).
  Fix migration **`2026-06-17_users_email_nullable.sql`** (DROP NOT NULL, keep UNIQUE). Schema synced.
- **Block admin/owner contacts:** RPC **`2026-06-17_rpc_contact_in_use.sql`** (boolean, owner-only, no
  PII) + step1 `_blockIfContactReserved` → clears field + "Already Registered" dialog when an
  email/phone belongs to an admin/owner (members still autofilled via `find_user_by_contact`).
- **UI:** Gender + Preparing-For dropdowns white + curved; added **Teacher** to Preparing For.
- **Migrations APPLIED to live DB:** `users_email_nullable` + `rpc_contact_in_use`. (Earlier
  `2026-06-17_users_owner_insert_member_rls.sql` is redundant/harmless — real cause was RETURNING.)

### Session 2026-06-17 (b) — FCM push: foundation SHIPPED & web-verified end-to-end
- **Firebase project `silence-v6`**; `flutterfire configure` (android/ios/web/win/macOS) →
  `lib/firebase_options.dart`, `android/app/google-services.json`, gradle plugins.
- **App-side** (`lib/services/push_notification_service.dart`, wired in `main.dart`): permission, FCM
  token → **`device_tokens`** table (multi-device), refresh + sign-in re-save, background handler,
  tap/foreground stubs. Web uses VAPID key (`_webVapidKey`).
- **DB:** `silence_app/migrations/2026-06-17_device_tokens.sql` (token PK, user-scoped RLS) — APPLIED.
- **Send-side (first Edge Function!):** `supabase/functions/send-push/index.ts` — a **Database Webhook**
  on `notifications` INSERT calls it; it reads recipient `device_tokens` (service role) → **FCM HTTP v1**
  (service account = base64 secret `FIREBASE_SERVICE_ACCOUNT_B64`). Deployed `--no-verify-jwt`; webhook
  `send_push_on_notification` wired. **✅ Verified end-to-end on web.** All committed+pushed.
- **FCM status (verified 2026-06-18):** foreground heads-up banner + tap→navigation are **DONE & wired**
  (`push_notification_service.dart`: `_showForegroundNotification` via `flutter_local_notifications`,
  `_routeFromData`; `main.dart` has the background handler + `navigatorKey` + `initialize()`).
  Webhook shared-secret **check is in code** (constant-time, `send-push`). **✅ ANDROID ON-DEVICE VERIFIED
  (2026-06-24)** — token saved to `device_tokens`, heads-up banner in foreground + background, tap opens the
  notification center. Firebase project unchanged after the owner transfer (silence-v6) so no config churn.
  **Remaining = OPTIONAL/iOS only:** (a) hardening — set `PUSH_WEBHOOK_SECRET` + `x-webhook-secret` header on
  the `send_push_on_notification` webhook; (b) iOS push (needs Apple Developer + APNs key, with R2).
- **Subscription decision (2026-06-17):** **in-app Razorpay ruled out**; either store IAP OR
  website+Razorpay. See `docs_fix/UIUX_OVERHAUL_DECISIONS.md` + `SUBSCRIPTION_ARCHITECTURE.md`.

### Session 2026-06-18 — audit-fix batch (code-only, full project `flutter analyze` clean)
Worked through safe audit items (baseline `SILENCE_COMPLETE_AUDIT_REPORT.md`):
- **P7-01 (flagship) multi-shift seats** (`library_setup_stage2.dart`): setup now creates one seat row
  **per shift** (same label) — was only first shift → 0 seats in other shifts; load **dedupes by
  label**; delete-detection made **label-aware** so sibling shift-rows aren't wrongly deleted.
- **P12-03** guarded 3 `currentUser!` force-unwraps → null checks (admin_home trial, member_history
  receipt, join_flow proof upload).
- **P7-02** discount cap: `add_member_step4` loads `business_rules.max_discount` (%) and clamps the
  discount to base×max%/100 (+ helper + snackbar). *Client-side only; server cap needs Wave 1.*
- **P7-06** QR regeneration grace: scanner accepts current **or immediately-previous** version (no
  more instant-break of printed QRs). *Precise 7-day window needs a `qr_version_updated_at` column.*
- **P12-01** global error handler: `main()` wrapped in `runZonedGuarded` + `FlutterError.onError`.
- **P10-02 / R-01 (storage PII)**: payment proofs in **renewal** + **history-reupload** now upload to
  `silence_private` (+ signed URL) instead of the PUBLIC `silence_assets` bucket (join_flow already
  did). ID docs + payment proofs are now all private. *(Profile photos stay public by decision.)*
  ✅ **APPLIED (2026-06-18):** `silence_app/migrations/2026-06-14_storage_private_owner_scoping.sql`
  (owner-scopes who can READ silence_private). Follow-up: proof display uses 1h signed URLs (join
  pattern) — old proofs may need re-signing on display (affects join too).
> Still pending (need live DB / server tier / decisions): RLS column
> locks (P5-01/P6-06 — P6-02 role-escalation now closed via `change_my_role()`, apply+test pending),
> server tier RPCs (RC-1), cron automation (P7-04/09, referral credit),
> analytics precompute (P11), real payments (RC-2, deferred), OTP (disabled by decision).
> *(Storage PII off public bucket + owner-scoping migration (P10-01/02/03, DPDP) and account-deletion
> purge cron (P14-02) — migrations APPLIED 2026-06-18; recovery purge still needs a destructive test.)*

### Session 2026-06-18 (b) — Account deletion + 7-day recovery + owner approval (P14-02)
Full flow built; `flutter analyze` clean. **Migrations APPLIED + Edge Function deployed (2026-06-18); still TEST (destructive) on a throwaway account before relying on purge:**
- **Flow:** request delete → `scheduled_for_deletion=true, deletion_scheduled_at=now()+7d,
  deletion_recovery_status='none'` → dashboard **fully blocked** (`account_frozen_screen.dart`,
  routed from splash + admin_home + member_home guards) → user taps **Request Recovery**
  (`status='requested'`) → **app-owner** reviews in **`owner_recovery_console_screen.dart`** (gated to
  `SupabaseConfig.appOwnerUserId`; entry in admin profile Operations) → Approve (restore) / Deny →
  after 7d unapproved, **Edge Function `process-account-deletions`** (cron) purges everything.
- **App owner = a DB flag** `users.is_app_owner` (NOT a hardcoded uid). Designate your owner account:
  `UPDATE public.users SET is_app_owner = true WHERE email = 'you@example.com';` — the Recovery
  Console entry + owner RPCs gate on this flag. Migration: `2026-06-18_app_owner_flag.sql`.
- **CURRENT decision (2026-06-18): recovery approval = Supabase DASHBOARD SQL (Option B)**, NOT the
  in-app console — no owner account/flag needed yet. The in-app Owner Recovery Console + `is_app_owner`
  flag + `app_owner_flag.sql` are built but **dormant** (entry hidden since no account is flagged);
  enable later when a dedicated admin/owner account exists. Approve/deny meanwhile via:
  `UPDATE users SET scheduled_for_deletion=false, deletion_scheduled_at=NULL, deletion_recovery_status='approved' WHERE id='…';`
  (deny → `deletion_recovery_status='denied'`).
- **Migrations APPLIED to live DB (2026-06-18):** `2026-06-18_account_deletion_recovery.sql`
  (recovery_status col) + `2026-06-18_account_recovery_rpcs.sql` (RPCs + `purge_account`) +
  `2026-06-18_app_owner_flag.sql` (is_app_owner col + re-gates the owner RPCs on the flag — ran LAST).
- **Edge Function DEPLOYED (2026-06-18):** `process-account-deletions` deployed + cron scheduled.
- ⛔ Purge is destructive/irreversible — verify `purge_account` covers your FK tables + test on a
  throwaway account before relying on the cron. Self-cancel removed (recovery is owner-approved).
- Minor: descriptive "30-day" copy in member_about / privacy_policy not yet updated to 7-day.

### Session 2026-06-18 (h) — P11-01: precompute member_daily_stats
`2026-06-18_member_daily_stats_precompute.sql` — a `SECURITY DEFINER` trigger on `attendance`
(INSERT/UPDATE/DELETE) maintains the `member_daily_stats` rollup (present_flag + total_minutes) per
`(member, library, IST-day)` via `recompute_member_daily_stat()`, plus a one-time backfill. IST-day
bucketing (`AT TIME ZONE 'Asia/Kolkata'`) matches the app clock. **No Dart change** — the service's
existing `member_daily_stats` fast path now hits indexed rows instead of scanning all attendance
(also speeds up the `consistent` badge). Folded into canonical (backfill omitted). `flutter analyze`
n/a (SQL only). ⛔ apply migration; verify `select count(*) from member_daily_stats > 0` + a fresh
check-out updates the day row.
- **P11-02 (badge N+1) — remaining:** `early_bird`/`night_owl` (need check-in hour) and `top_of_week`
  (per-week library leaderboard scan) still scan attendance — batch 2 (needs a small precompute or a
  scheduled recompute).

### Session 2026-06-18 (k) — Honest-UI sweep + lock self-granted "Verified" badge
Sweep result: C1 (fake-success messages) already **clean** — the old "broadcasted/Exported successfully"
stubs are gone, bulk-announce really inserts notifications, all other success snackbars fire after a
real await. C2 (7-day deletion copy) already **correct** everywhere (privacy policy / about /
privacy-security / recovery console) — done in `9ea0403`; the prior "not yet updated" note was stale.
**Found + fixed:** the library **Verified badge was self-granted** — `verified_badge_screen` wrote
`libraries.verified=true` directly (client-side eligibility only) and the column was unlocked → a
forgeable trust signal (dishonest "verified"). New `claim_verified_badge()` SECURITY DEFINER RPC
re-checks all eligibility server-side; a `guard_library_verified` trigger blocks any other direct
verified/verified_at change (`2026-06-18_lock_library_verified.sql`). Screen wired to the RPC; folded
into canonical. `flutter analyze` clean. ⛔ apply migration + verify claim works for an eligible library
and a direct `update ... set verified=true` is rejected.

### Session 2026-06-18 (j) — Bug sweep: fix member leaderboard broken by tenant-scope
Full-project `flutter analyze` clean. Reviewed RLS-tightening flows: audit_log (`admin_id=auth.uid()`)
and notifications (relationship policy) are safe — every audit write uses the current admin's id, and
notify targets always have a membership or pending join_request. **Found + fixed:** the member
**leaderboard** read co-members' names via a `users(...)` embed, which the tenant-scoped users SELECT
(P10-04, applied) now blocks for member viewers → leaderboard collapsed. New SECURITY DEFINER
`library_leaderboard(p_library,p_start,p_end)` RPC (`2026-06-18_library_leaderboard_rpc.sql`) computes
ranked, privacy-formatted names + minutes from `member_daily_stats` (caller must belong to/own the
library); `fetchLeaderboardDetails` now uses it. Unused `fetchLeaderboard` left as dead code.
`flutter analyze` clean. ⛔ apply migration + verify member leaderboard shows co-members again.

### Session 2026-06-18 (i) — P11-02: badge engine fully off attendance scans
`2026-06-18_badge_precompute_batch3.sql` — added `early_count`/`night_count` to `member_daily_stats`
(maintained by the existing trigger + backfilled) and a `member_is_week_top()` indexed-aggregate RPC.
`member_analytics_service`: `early_bird`/`night_owl` now sum the rollup; `top_of_week` calls the RPC per
week (was 4 full library attendance scans). Combined with (h), badge sync no longer scans attendance on
analytics load. Folded into canonical (table cols + recompute body + RPC). `flutter analyze` clean.
⛔ apply migration + verify badges still award.

### Session 2026-06-18 (g) — P8-01 batch 1: canonical IST clock (member dashboard / scanner / holidays)
Added canonical IST helpers to `lib/utils/time_utils.dart` — `istNow()`, `istToday()`, `istTodayKey()`,
`istDateKeyFromDb(dbTime)`. Routed the member-facing day-boundary logic through them (was a mix of
device-local `.toLocal()` and UTC date-keys):
- **Closure "today" key (always off-by-one 00:00–05:30 IST):** `qr_scanner_screen` + `member_home` now
  use `istTodayKey()`.
- **Streaks / study-days:** `member_home` `_studyDates` bucketing → `istDateKeyFromDb`; `_calculateCurrentStreak`,
  `_getLast7DaysAttendance`, `_computeMemberState` + expired lookups → `istNow()`/`istToday()`.
- **Holidays:** `holiday_service.todaysHoliday` / reopen check → `istNow()`.
- `flutter analyze` clean. ⛔ device-verify streak/“studied today”/closure near midnight.
- **P8-01 batch 2 (DONE 2026-06-18):** added `istWallClockToUtc()` helper. Analytics ENGINE
  (`member_analytics_service`) + TABS (`member_analytics_tab`, `admin_analytics_tab`) now build all
  ranges from `istNow()` and convert query bounds via `istWallClockToUtc()` (was naive
  `DateTime(y,m,d).toIso8601String()`/`.toUtc()` → the window was 5.5h off even on IST devices for the
  engine). Attendance/streak/revenue bucketing → `istDateKeyFromDb`/`toIST`. Relative windows
  (last-7/180d) and export date-stamps left as-is. `flutter analyze` clean. ⛔ device-verify analytics
  numbers (revenue, attendance rate, leaderboard, heatmap, today/this-week filters).

### Session 2026-06-18 (f) — P5-08: actor-scope the forgeable inserts — APPLIED
`2026-06-18_actor_scope_inserts.sql` (+ folded into canonical) — **applied to live DB 2026-06-18**.
Replaced the open `WITH CHECK (auth.uid() IS NOT NULL)` on **notifications / audit_log / badges / referrals** with
relationship-scoped checks that still allow every real cross-actor write:
- **notifications:** self · owner→member · owner→applicant · (member|applicant)→owner. Covers all
  ~15 notify sites (admin→member actions, broadcasts, member→owner queries, badge self-notify).
- **audit_log:** `admin_id = auth.uid()` only. Code: `join_flow_screen` no longer writes an
  owner-attributed audit row (kept the owner notification, which is allowed).
- **badges:** self-award or owner-of-the-badge's-library (covers member analytics + admin viewing).
- **referrals:** inserter must be referrer or referred.
- `flutter analyze` clean. ⛔ **apply + device-verify** (notify-heavy flows: approve/reject/hold/end/
  seat/query/broadcast deliver; member query reaches owner; streak badge awards; forgery of an
  unrelated notification/badge fails). One-line rollback per policy in the migration.

### Session 2026-06-18 (e) — Security hardening batch: lock privileged columns + tenant-scope + membership lock — APPLIED
Device available; adopt-then-tighten. `flutter analyze` clean. **All migrations applied to live DB 2026-06-18:**
- **P6-03/P6-06 — subscription + verified lock** (`2026-06-18_lock_user_privileged_columns.sql`):
  consolidated the role lock into one `guard_user_privileged_columns` trigger (GUC
  `app.allow_privileged_update`) covering `role` + `subscription_plan/status/expiry` +
  `phone_verified/email_verified`. New `start_my_trial()` RPC (admin one-time 14-day starter);
  `admin_home` launch now calls it instead of a direct `users.update`. `change_my_role` re-created on the
  unified GUC (replaces standalone `guard_role_change`). Verified flags had no client writer → pure lock.
- **P10-04 — tenant-scope users SELECT**: folded the authored `2026-06-14_users_select_tenant_scope.sql`
  into canonical (owner reads only members + pending applicants of their libraries; cross-library lookup
  via `find_user_by_contact` RPC, already wired). User applies + verifies member lists / Requests tab /
  add-member autofill.
- **P5-01 — open memberships UPDATE**: dropped `"System can update USING(true)"`; member self-exit moved
  to `exit_my_membership()` RPC (`2026-06-18_memberships_member_exit_rpc.sql`, `member_home` wired). Admin
  writes stay owner-scoped; cron uses service_role.
- ⛔ **Still open (next):** actor-scope the cross-actor inserts (P5-08 — join_flow owner notify/audit,
  badge award) via RPCs; server tier RC-1; analytics precompute (P11); build/keystore (P1); iOS (P14-03).
- **Subscription display (same session, P6-03 related):** `start_my_trial()` now grants a **30-day Free
  window** (`plan='free'` + 30d expiry) instead of the legacy `'starter'` grant (which `plan_service`
  mapped to "Pro" — confusing). Subscription screen shows "Free — X days left" and the bottom Razorpay
  note was removed. **Deferred (user's call):** real trial *enforcement* (countdown that actually limits)
  — `betaMode=true` keeps everything unlocked for now; revisit with Razorpay/website. Existing
  'starter'/'basic' admins need a one-time reset:
  `begin; set local app.allow_privileged_update='on'; update public.users set subscription_plan='free', subscription_status='active', subscription_expiry=now()+interval '30 days' where subscription_plan in ('starter','basic'); commit;`

### Session 2026-06-18 (d) — Role-change redesign + self-escalation lock (P6-02) — APPLIED & VERIFIED
User decision: the "Change Role" option exists ONLY to fix an accidental wrong-role signup. Migration
applied to live DB + device-verified both directions (2026-06-18); `flutter analyze` clean. New rules:
- **7-day window** from signup (`users.created_at`) — after that, role is fixed (honest "not available" dialog).
- **Role change = full data wipe + fresh account:** the current role's data (memberships, attendance,
  payments, owned libraries+their members, streaks, etc.) is permanently deleted; the login identity
  (auth user / email / phone / created_at) is kept; a brand-new empty account starts in the new role.
- **Strict type-to-confirm:** user must type `ADMIN`/`MEMBER` to enable the destructive button; red
  warning explains the permanent deletion.
- **Server-enforced + escalation locked:** `silence_app/migrations/2026-06-18_role_change_rpc.sql` —
  `change_my_role(p_new_role)` (SECURITY DEFINER) does the window check + purge + role flip atomically;
  a `BEFORE UPDATE OF role` trigger (`guard_role_change`) blocks ANY other direct role flip unless the
  RPC set its transaction-local flag. Allows INSERTs, null→role onboarding, and same-value upserts, so
  `role_selection`/`member_profile_edit`/admin onboarding upserts are unaffected. Folded into canonical
  `supabase_schema.sql`. This closes audit **P6-02** (member self-escalation to admin).
- **Code:** `lib/screens/member_profile_tab.dart` + `lib/screens/admin_profile_tab.dart` — both
  `_showChangeRoleDialog` rewritten (was a plain `users.update({'role':...})`) to: fetch `created_at`,
  gate on the 7-day window, show the strict dialog, call `rpc('change_my_role', ...)`, then clear prefs
  + signOut + route to `/auth` (re-login lands in the fresh new-role onboarding).
- ✅ **APPLIED + device-verified (2026-06-18):** migration run on live DB; role change tested both
  directions within 7 days (data wiped, fresh account), the >7-day block, and normal signup/profile-edit
  upserts still work under the trigger. **Bug fixed during testing:** `change_my_role()` (and the existing
  `purge_account`) referenced non-existent `referrals.referrer_id/referred_id` → corrected to
  `referrer_member_id/referred_member_id` (42703). `created_at` kept (original signup) so the 7-day clock
  does NOT reset on role change — prevents repeat flip/wipe abuse.

### Session 2026-06-18 (c) — All pending live-DB migrations APPLIED (user-run)
User confirmed running every outstanding migration in the Supabase SQL editor + deploying the Edge
Function. No code change this session; docs synced. Now live:
- `2026-06-15_join_requests_payment_status.sql` — requests **Reject-Pay/Confirm-Pay**, member
  **Withdraw Application**, and the **rejected-request card** now work (DB CHECK accepts the values).
- `2026-06-14_storage_private_owner_scoping.sql` — `silence_private` reads owner-scoped (P10-01/03, DPDP).
- `2026-06-18_account_deletion_recovery.sql` + `2026-06-18_account_recovery_rpcs.sql` +
  `2026-06-18_app_owner_flag.sql` (last) — account-deletion 7-day recovery + `purge_account` (P14-02).
- Edge Function `process-account-deletions` deployed + cron scheduled.
- **No outstanding live-DB action.** Next: on-device smoke-test the gated flows; verify `purge_account`
  on a throwaway account before relying on the cron (destructive). `is_app_owner` flag stays dormant
  (recovery still approved via dashboard SQL — Option B) until a dedicated owner account exists.
- Uncommitted working tree: two FCM build edits (`android/app/build.gradle.kts` desugaring +
  `2026-06-17_device_tokens.sql` newline tidy) — commit when user asks.

### Key reframes (these OVERRIDE the old spec/audit "fixes")
- **Member ↔ library-admin payment is OUT OF APP.** Real `upi://pay` deep-link + "I have paid";
  admin verifies in their bank app + confirms. No in-app gateway, no screenshot-theatre.
- **Subscription (app-owner ↔ library-owner):** NOT in-app — **DECIDED (2026-06-18): Razorpay on the
  website only** for subscription management; the app just READS `subscription_*` (written by the
  website/webhook). In-app subscription screen shows the plan + a 30-day Free window (display-only;
  `betaMode=true` keeps features unlocked). First 1–2 months free tier.
- **Member-side "create hold" REMOVED** — only admins hold/resume; members request an early resume.
- **Identity verification (email/phone OTP): built but DISABLED.**
- **Notifications:** in-app center real; **FCM push foundation shipped + web-verified** (see above).

### What's DONE so far (remediation) — full detail in `docs_fix/IMPLEMENTATION_PLAN.md`
Shipped areas (each honest, `flutter analyze`-clean): A0 foundation (`app_colors`, `widgets/states/`,
`friendlyError`, `upi_launcher`); real notification center; join/renewal UPI reframe; admin Payment
Methods; member_home revamp (honest states, IST, bell+badge, hold reframe, library/session cards,
streak week, quick actions, offline cached card); scanner multi-session; admin Hold/Resume +
seat-change reject; Holidays/closures (`holiday_service` on `scheduled_closures` start/end); Contact
Admin↔Queries loop; states-pass on member screens; **Phase B**: real payment amount + add-ons persist
+ notify + central `audit_logger` + seat reassign/release sync + honest subscription screen + account
deletion (type-DELETE, `scheduled_for_deletion`) + referral config + member transfer + draft
persistence; **Phase C** schema reconciliation **APPLIED** (6 tables RLS-on + columns/constraints);
add-member & amenities polish; admin Reservation-tab fixes; member-profile + payments/users RLS
hotfixes (APPLIED); desktop image-pick guards; iOS location + Android INTERNET + release-keystore
scaffold; harden open insert policies (APPLIED); RPC `find_user_by_contact` + tenant-scope users
SELECT; **2026-06-15 reservation/attendance/requests overhaul** (`2a55f4d` — seat dedupe + overlap
availability, smart manual check-in/out + "Manual" tag, admin-home attendance redesign, members
"No Seat"+Assign, admin Renew sheet, requests payment-decoupled + rejected-card + soft withdraw,
permanent eligibility-gated member QR FAB; detail in `docs_fix/LAYOUT_SEAT_OVERHAUL.md` +
`RESERVATION_FIXES_2026-06-15.md`).

### Next action (when the user says "continue"/"GO")
- ✅ **Wave-0 security: ALL APPLIED + verified (2026-06-18).** role lock (P6-02), subscription/verified
  lock (P6-03/06), tenant-scope users SELECT (P10-04), membership self-exit + open-UPDATE drop (P5-01),
  actor-scoped inserts (P5-08), storage owner-scoping (P10-01/02/03). Build/release: INTERNET + signing
  scaffold present (P1) — user generates the keystore.
- ✅ **IST single clock (P8-01) APPLIED + verified.** member dashboard/scanner/holidays + analytics
  engine/tabs all on IST (`istNow`/`istWallClockToUtc`/`istDateKeyFromDb`).
- ✅ **Analytics + badge precompute (P11-01/02) APPLIED + verified.** `member_daily_stats` trigger +
  backfill; all badges off attendance scans; `member_is_week_top()` + `library_leaderboard()` RPCs.
- ✅ **Setup fixes APPLIED:** `'free'` subscription_plan allowed (launch 23514); duplicate-contact
  friendly warning (admin + member profile); member leaderboard fixed via `library_leaderboard()` RPC.
- **Remaining (need decision / environment — NOT pure code):**
  - **Server tier RC-1 / real payments (Razorpay = website only) / OTP** — deferred by product decision.
  - **Subscription enforcement:** `betaMode=true` keeps features unlocked; 30-day Free window is
    display-only. Flip + enforce later with the website/billing.
  - **iOS location crash (P14-03):** needs a Mac/iOS build.
- **FCM (verified done in code):** foreground banner + tap→nav implemented & wired; webhook-secret check
  in code. Remaining = config (set `PUSH_WEBHOOK_SECRET` + webhook header) + on-device test (Android; iOS needs Mac/Apple).

---

## Historical audit reference (2026-06-08 baseline — evidence in `docs_audit/`)

> Everything below is the original audit context — the baseline + *why/where* of each defect. For
> current status use §0 above + `docs_fix/`. Full evidence (`file:line`), root causes, and the Wave 0–4
> roadmap are in **`docs_audit/AUDIT_PHASE_16.md`** (capstone) and the per-phase reports
> `docs_audit/AUDIT_PHASE_0..16.md`. Totals to cite: **22 C · 68 H · 63 M · 22 L** (Phase-14-updated).

**Baseline snapshot (as audited):** Flutter (~66 screens, ~74.6k LOC), Supabase (25 tables), **0 RPC /
0 Edge Functions**, 179 client-direct writes / 0 server validation; payments mocked; notifications a
stub; OTP mocked; hardcoded anon key; release debug-signed + missing INTERNET. Security scored 1.5/10
(porous RLS, PII/ID docs exposed, self-asserted identity, self-escalation).

**5 root causes (fix order):** RC-4 self-asserted identity & permissive RLS/storage → RC-3 schema
drift/missing tables → **RC-1 no server tier** (master unlock) → RC-2 money mocked → RC-5 dishonest
UX/silent failure.

**Wave roadmap:** **W0** stop-the-bleeding (storage object-scoping, tenant-scope users SELECT, remove
open UPDATE/inserts, lock role/subscription/verified cols, schema deploy fixes, keystore+INTERNET, iOS
location crash) → **W1** spine (server tier, real payments+webhook, identity verify, notifications) →
**W2** correctness (analytics precompute, one IST clock, uniqueness/idempotency, global error handler,
immutable audit) → **W3** operability (renewals, self-service, bulk ops, automation, roles, referral,
transfer) → **W4** scale (search/pagination, multi-branch, offline sync, deletion/export, WhatsApp, GST).

**22 criticals (IDs for cross-ref):** P10-01/02/03 storage exposure · P10-04 users-table read · P5-01
memberships open UPDATE · P6-02 role escalation · P6-03 subscription self-activation · P6-01/P10-08 no
server tier (ROOT) · P0-01 payments mocked · P9-02 subscription theatre · P3-01 placeholder UPI · P4-01
admin UPI unused · P4-03 hardcoded amount · P4-02 audit log broken · P9-01 notifications stub · P5-03
missing tables · P5-02 expenditures conflict · P8-01 TZ day-defs · P11-01/02 analytics scans/N+1 ·
P1-01/02 INTERNET+signing · P14-03 iOS location crash. (Many now remediated — see `docs_fix/AUDIT_CHECKLIST.md`.)

**Release verdict (baseline):** internal demo ✅; closed pilot ⚠️ only after Wave 0; public/paid ❌
until Waves 0–2/0–3. **Legal flag:** PII/ID-doc exposure (P10-01/02/04) is a reportable **DPDP** breach.

**Don't break (genuinely solid):** `auth_screen`, `qr_scanner` (typed exceptions, friendly msgs,
500-cap offline queue); 23 good DB indexes; offline queue/retry foundation; differentiators
(multi-shift seats, streaks/badges, referrals) exist in schema — broken, not absent (repair > rebuild).

**Caveats:** audit had no live DB / device / profiler — ~50 Verification-Pending items (V-01…V-53) need
live verification; 28 Open Questions remain. Don't trust "fixed" on those without live checks.

---

*Originally generated 2026-06-08 as a session-durable handoff; condensed 2026-06-17 to stay under the
context limit (historical detail preserved in `docs_audit/` + `docs_fix/`). Keep it current.*
