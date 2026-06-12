# SILENCE — Pending Fixes That Need NO Device Testing

> Generated 2026-06-12. These are remaining work items that can be **implemented and verified
> statically** — by code review + `flutter analyze`, or by running a SQL migration (like the two you
> just applied). None require running the app on a phone to do or to confirm.
>
> **Tiers:** T1 = safe code fix, verify with `flutter analyze`. · T2 = SQL/config you apply (no app
> test). · T3 = needs server work or a product decision (listed for completeness; not actionable now).

---

## T1 — Safe code fixes (verify with `flutter analyze`, no device)

### 1. Kill dishonest "success" snackbars (violates the no-dishonest-UI rule)
- [ ] `lib/screens/reservations/members_sub_tab.dart` → `_sendBulkAnnouncement()` shows **"Announcement broadcasted successfully"** but sends nothing. Make honest: either insert real `notifications` rows for the selected members, or relabel to "coming soon" and disable.
- [ ] `lib/screens/reservations/members_sub_tab.dart` → `_exportSelectedMembers()` shows **"Exported … to CSV successfully"** but exports nothing. Make honest: wire to the existing `CsvExporter`/`PdfExporter`, or disable with honest copy.
- [ ] Sweep for other fake-success copy: grep `successfully|broadcasted|Exported|notified` and confirm each only fires after a real DB/IO op.

### 2. Apply the desktop image-pick guard to the other 9 screens
Same crash as Add-Member (mobile-only `permission_handler` / `image_cropper` thrown on Windows/desktop). Apply the `isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS)` guard + try/catch around `pickImage`, skip cropper on web/desktop:
- [ ] `lib/screens/member_profile_edit.dart`
- [ ] `lib/screens/member_profile_tab.dart`
- [ ] `lib/screens/admin_profile_tab.dart`
- [ ] `lib/screens/admin_profile_complete.dart`
- [ ] `lib/screens/library_setup_stage1.dart`
- [ ] `lib/screens/branding_assets.dart`
- [ ] `lib/screens/member_help_support_screen.dart`
- [ ] `lib/screens/member_explore_screen.dart` *(uses `Permission.` — likely location; guard so desktop doesn't throw)*
- [ ] `lib/screens/member_home.dart` *(uses `Permission.` — likely location/notification; same)*
- [ ] Consider extracting one shared `pickAndOptionallyCropImage()` helper so this logic lives in one place.

### 3. Analyzer baseline cleanups (drop to a cleaner baseline)
- [ ] Remove unused import `../../core/cache_service.dart` in `lib/screens/admin/add_member_wizard.dart`.
- [ ] Remove unused import `../../widgets/year_month_day_picker.dart` in `lib/screens/admin/add_member_step1.dart`.
- [ ] `add_member_step1.dart` lines ~771/857/999: deprecated `value:` on form fields → `initialValue:`.
- [ ] Replace stray production `print(...)` debug logging in `lib/screens/reservations/layout_sub_tab.dart` with `debugPrint` or remove.

### 4. iOS location crash (P14-03) — code-only, can't device-test on Windows anyway
- [ ] Guard the location call on the offending screen (permission + try/catch + graceful fallback) so iOS doesn't crash before a permission prompt. Verifiable by review; real confirmation later on iOS.

---

## T2 — SQL / config you apply (no app testing; same flow as the migrations you ran)

### 5. Build / manifest
- [ ] Add `<uses-permission android:name="android.permission.INTERNET"/>` to `android/app/src/main/AndroidManifest.xml` (audit **P1-01**). Debug auto-adds it; **release builds need it** or all network/uploads fail.
- [ ] Add a real **release keystore + signingConfig** in `android/app/build.gradle.kts` (audit **P1-02**; currently debug-signed).

### 6. Security / RLS migrations (author + apply; additive & scoped — minimal app-behavior risk)
- [ ] **P10-04** — scope `users` SELECT to tenant instead of "any library owner reads all users"; gate library creation.
- [ ] **P5-08 / `WITH CHECK(true)`** — tighten the forged-insert policies on `notifications` / `audit_log` / `badges` / `referrals` so a client can't insert arbitrary rows.
- [ ] **P6-02 / P6-06** — block client writes to `role`, `subscription_*`, `*_verified` columns (column privileges or a guard trigger) → stops self-escalation / self-activation.
- [ ] **Storage scoping (P10-01/02/03)** — make the private bucket read/write/delete owner-scoped; move any PII off the public bucket.
- [ ] **P5-01** — review/remove the `memberships` "System can update" `USING(true) WITH CHECK(true)` policy. ⚠️ Higher risk: confirm no client flow relies on it (auto-hold/expiry are meant to be server-side) before removing.
- [ ] **Phase C §E** (optional) — drop the dead `library_closures` table.
> Note: write each as a numbered file in `silence_app/migrations/` + fold into `supabase_schema.sql`, exactly like the two you just ran. No app test needed to apply; behavioral confirmation can come later.

### 7. Secrets
- [ ] Move the hardcoded Supabase anon key out of `lib/core/supabase_config.dart` into `--dart-define`/env (audit flag). Anon key is low-severity but shouldn't be the only thing committed.

---

## T3 — Needs server work or a product decision (NOT actionable without testing/infra; listed only)

- [ ] **FCM push send** — needs a server/Edge function + device tokens.
- [ ] **Email/phone OTP** — screens exist but disabled; needs auth/server wiring.
- [ ] **Referral auto-credit** — needs a server job (currently manual).
- [ ] **Owner console for deletion requests** — app-owner tier.
- [ ] **Razorpay app-owner ↔ library-owner subscription** — integrate last; currently mock plans.
- [ ] **Decision:** re-enable the QR checkout cooldown (`minCheckoutMinutes` is currently `0`) — pick the value.

---

## Suggested order to knock these out
1. **T1.1** (honest UI) — quick, removes a rule violation.
2. **T1.2** (desktop guards) — unblocks you testing more flows on Windows without crashes.
3. **T1.3** (analyzer cleanups) — fast, clean baseline.
4. **T2.5** (INTERNET + keystore) — needed before any real build.
5. **T2.6** (RLS migrations) — author + you apply; do the low-risk ones first, `memberships` P5-01 last with care.
6. **T1.4 / T3** — iOS + server-tier, as scheduled.
