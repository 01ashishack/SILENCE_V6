# SILENCE v6.0 — Production Verification Audit Report
**Date:** 30 June 2026  
**Auditor:** Antigravity (Advanced Agentic Coding Pair)  
**Status:** **NOT READY FOR RELEASE** (Contains Blocker P1 Issues)

---

## 1. Executive Summary & Readiness Scores

This audit evaluates the **SILENCE v6.0** mobile application from a production user's perspective. It examines the integrity of routes, business rules, legal compliance, and critical workflows (auth, check-in, referrals, and add-ons) directly from the codebase implementation. 

### Launch-Readiness Scores

| Category | Score | Status | Description |
| :--- | :---: | :---: | :--- |
| **Core Workflows** | **7.5/10** | 🟡 WARNING | Check-in/out and setups work but are impeded by a blocked expired check-in gate and add-on profile desyncs. |
| **Referral Loops** | **2.0/10** | 🔴 CRITICAL | Fully broken. Verification uses wrong columns, and the member-side referrals panel is permanently hidden. |
| **Legal & Compliance** | **8.5/10** | 🟡 WARNING | Legal copy is single-sourced and accurate, but a Privacy Policy link is missing from the admin profile page. |
| **UI/UX Polish** | **7.0/10** | 🟡 WARNING | Contains dead tap targets (Walkthrough card) and lacks quick actions (Renew) on the member details screen. |
| **Code & Route Integrity** | **7.5/10** | 🟡 WARNING | Contains orphaned screens and redundant database exceptions due to obsolete column references. |
| **Overall Launch Readiness** | **6.5/10** | 🔴 BLOCK | **DO NOT SUBMIT TO STORES.** P1 blockers must be resolved first. |

---

## 2. Priority Findings (P0 to P3)

### 🔴 High Priority (P1) — Release Blockers

#### Finding 1: Mismatched Referral Code Verification
* **Screen:** Join Flow Screen (Step 5 - Referral Input)
* **File:** [join_flow_screen.dart](file:///C:/Users/kumar/combined/SILENCE_V6/lib/screens/reservations/join_flow_screen.dart#L739)
* **Root Cause:** When checking the referred code, the query searches the `nickname` column of the `users` table (`.eq('nickname', refCode)`) instead of the unique `referral_code` column (`.eq('referral_code', refCode)`).
* **User Impact:** A joining member who inputs a valid referral code (e.g. `REF-ABCDE` shown on the referrer's screen) will always fail to attribute the referral, as no user has that code as a *nickname*. The referral will fail silently.
* **Business Impact:** Completely breaks the viral user-acquisition engine.
* **Recommended Fix:** Update the query on line 739 to use the correct database column:
  ```diff
  - .eq('nickname', refCode)
  + .eq('referral_code', refCode)
  ```

---

#### Finding 2: Broken Referral UI Gate on Profile
* **Screen:** Member Profile Screen
* **File:** [member_profile_tab.dart](file:///C:/Users/kumar/combined/SILENCE_V6/lib/screens/member_profile_tab.dart#L112-L119)
* **Root Cause:** The tab checks `lib['referral_rewards_enabled'] == true` on the `libraries` table. However, `referral_rewards_enabled` does not exist in the `libraries` schema. Referral settings are stored in the JSONB `settings` table under the `referral_settings` scope.
* **User Impact:** The "Refer a Friend" sharing panel is permanently hidden from members on the profile tab, even if the admin has enabled referrals.
* **Business Impact:** Students cannot find or share their referral codes via the profile tab.
* **Recommended Fix:** Retrieve settings using the standard settings table:
  ```dart
  final settings = await AdminSettingsService.load(scope: 'referral_settings', libraryId: libId);
  _referralRewardsEnabled = settings['enabled'] == true;
  ```

---

#### Finding 3: Violated Expired Member Check-in Gate
* **Screen:** Member Home Screen
* **File:** [member_home.dart](file:///C:/Users/kumar/combined/SILENCE_V6/lib/screens/member_home.dart#L1404) & [member_home.dart](file:///C:/Users/kumar/combined/SILENCE_V6/lib/screens/member_home.dart#L2305)
* **Root Cause:** Expired member check-ins are blocked unless `allow_expired_checkin` is set to true in `rules_metadata`. Because `rules_metadata` doesn't exist on `libraries`, the check always returns false. This violates the decision in `AGENTS.md` to drop this gate entirely and allow expired check-ins with warnings.
* **User Impact:** Expired members are locked out and unable to check in, showing: `"⛔ QR check-in blocked. Renew to check in again."`
* **Business Impact:** High friction. Library owners are forced to manually override or block students instead of letting them scan with warning notes.
* **Recommended Fix:** Remove the check-in block from `member_home.dart` entirely, permitting check-in for expired states while retaining the visual warning/nudge banner.

---

#### Finding 4: Library Profile Screen Add-on Display Desync
* **Screen:** Library Profile Screen (Admin)
* **File:** [library_profile_screen.dart](file:///C:/Users/kumar/combined/SILENCE_V6/lib/screens/library_profile_screen.dart#L66)
* **Root Cause:** The screen fetches active add-ons from `settings` scope `addon_services`, but the management screens (`addon_services.dart` and `admin_profile_tab.dart`) save add-ons directly to the `add_ons` database table.
* **User Impact:** The library profile page will always show 0 active add-ons (empty state), even when add-ons are correctly saved in the DB.
* **Business Impact:** Renders library profiles incomplete/broken to both admins and students.
* **Recommended Fix:** Query the `add_ons` table directly:
  ```dart
  final addonsRes = await _supabase.from('add_ons').select().eq('library_id', currentLibId).eq('active', true);
  _addons = List<Map<String, dynamic>>.from(addonsRes);
  ```

---

### 🟡 Medium Priority (P2) — Functional & Compliance Gaps

#### Finding 5: Failing Queries / Non-Existent Column `rules_metadata`
* **Screen:** Business Rules Screen
* **File:** [business_rules.dart](file:///C:/Users/kumar/combined/SILENCE_V6/lib/screens/business_rules.dart#L54) & [business_rules.dart](file:///C:/Users/kumar/combined/SILENCE_V6/lib/screens/business_rules.dart#L92)
* **Root Cause:** The code queries and updates the `rules_metadata` column on `libraries`. Since the column does not exist, it throws silent PostgREST exceptions every time the screen is opened or saved.
* **User Impact:** Silent background errors, failing database transactions, and redundant network requests.
* **Business Impact:** High technical debt and potential for silent failures.
* **Recommended Fix:** Rely solely on `AdminSettingsService` (which uses the `settings` table with scope `'business_rules'`) and remove the direct `libraries.rules_metadata` updates.

---

#### Finding 6: Dishonest UI (Fake Add-on Occupancy Counts)
* **Screen:** Add-on Services Screen (Admin)
* **File:** [addon_services.dart](file:///C:/Users/kumar/combined/SILENCE_V6/lib/screens/addon_services.dart#L97-L107)
* **Root Cause:** The `allocatedCount` of lockers/parking spaces is calculated on-the-fly using hardcoded percentage multipliers on `totalInventory` instead of querying the actual active allocations from `member_add_ons` table.
* **User Impact:** Admins see fake resource occupancy numbers (e.g. exactly 45% of lockers are shown occupied).
* **Business Impact:** Violates the project's golden rule ("No dishonest UI").
* **Recommended Fix:** Query the actual number of active member allocations from the `member_add_ons` table in the database and display the real count.

---

#### Finding 7: Missing Privacy Policy Link (Admin Profile)
* **Screen:** Admin Profile Settings Tab
* **File:** [admin_profile_tab.dart](file:///C:/Users/kumar/combined/SILENCE_V6/lib/screens/admin_profile_tab.dart#L1056-L1065)
* **Root Cause:** The list of policies under 'App & Support' includes Terms, Refund Policy, Cancellation Policy, and Community Guidelines, but lacks a link to the Privacy Policy.
* **User Impact:** Signed-in library owners cannot access the Privacy Policy.
* **Business Impact:** **App Store Submission Risk.** Both Google Play and Apple App Store require the Privacy Policy to be easily accessible from anywhere in the app.
* **Recommended Fix:** Add a ListTile for the Privacy Policy linking to the role-agnostic `/member/privacy-policy` route.

---

### 🟢 Low Priority (P3) — UX Polish & Technical Debt

#### Finding 8: Orphaned Screen: Copy Library Settings Screen
* **Screen:** Copy Library Settings Screen
* **File:** [copy_library_settings_screen.dart](file:///C:/Users/kumar/combined/SILENCE_V6/lib/screens/admin/copy_library_settings_screen.dart)
* **Root Cause:** Fully implemented settings copying tool, but has no button, menu item, or navigation hook pointing to it. Not even registered in `main.dart` routes.
* **User Impact:** Multi-library owners cannot access this time-saving feature.
* **Recommended Fix:** Register in `main.dart` and add a link in the admin profile tab under "Operations" (e.g. "Apply to Other Branches").

---

#### Finding 9: Orphaned Screen: Pricing Plans Screen
* **Screen:** Pricing Plans Screen
* **File:** [pricing_plans.dart](file:///C:/Users/kumar/combined/SILENCE_V6/lib/screens/pricing_plans.dart)
* **Root Cause:** Unused code and route `/admin/settings/pricing` left in the app after plan pricing was moved into shifts (`shift_management.dart`).
* **User Impact:** Dead code weight.
* **Recommended Fix:** Remove the file and delete the route from `main.dart`.

---

#### Finding 10: Duplicated Add-on Management UI
* **Screen:** Add-on Services Screen & AddonsAmenitiesSheet
* **File:** [addon_services.dart](file:///C:/Users/kumar/combined/SILENCE_V6/lib/screens/addon_services.dart) & [admin_profile_tab.dart](file:///C:/Users/kumar/combined/SILENCE_V6/lib/screens/admin_profile_tab.dart)
* **Root Cause:** The app has two completely separate implementations for managing add-ons (a full screen and an inline sheet).
* **User Impact:** Confusing admin experience since both modify the same data but look different.
* **Business Impact:** High maintenance cost.
* **Recommended Fix:** Consolidate both into a single shared widget or screen.

---

#### Finding 11: Dead Tap Target (App Walkthrough)
* **Screen:** Member Help & Support Screen
* **File:** [member_help_support_screen.dart](file:///C:/Users/kumar/combined/SILENCE_V6/lib/screens/member_help_support_screen.dart#L611-L683)
* **Root Cause:** The "SILENCE Member App Walkthrough" card displays a play icon, but has no `InkWell` or tap handler.
* **User Impact:** Tapping the play button does nothing, frustrating users who expect a video guide.
* **Recommended Fix:** Show a dialog/snackbar explaining that the walkthrough is coming soon when tapped.

---

#### Finding 12: Missing Renewal Shortcut on Member Details Screen
* **Screen:** Member Detail Screen
* **File:** [member_detail_screen.dart](file:///C:/Users/kumar/combined/SILENCE_V6/lib/screens/reservations/member_detail_screen.dart)
* **Root Cause:** The administrator cannot renew a member's membership directly from their full profile details tab.
* **User Impact:** Admin must go back to the members list or layout tab to perform a renewal, adding extra taps.
* **Recommended Fix:** Add a "Renew Membership" button in the quick actions section of `member_detail_screen.dart`.

---

## 3. Final Pre-Publish Checklist

Before releasing the app to public app stores, the developer must complete the following actions:

### Phase 1: Code Fixes (BLOCKERS)
- [ ] Fix referral code verification in `join_flow_screen.dart` (Finding 1).
- [ ] Fix referral card gate in `member_profile_tab.dart` (Finding 2).
- [ ] Remove expired check-in block in `member_home.dart` (Finding 3).
- [ ] Unify add-on database queries in `library_profile_screen.dart` (Finding 4).
- [ ] Fix business rules database exceptions in `business_rules.dart` (Finding 5).
- [ ] Add Privacy Policy link to `admin_profile_tab.dart` (Finding 7).

### Phase 2: On-Device Verification (USER)
- [ ] Run a test on a physical Android device to verify that check-in works successfully for active members.
- [ ] Verify that an expired member check-in displays a warning but does not block check-in.
- [ ] Verify that registering with a member's referral code correctly links the referrer and referee.
- [ ] Verify that the Privacy Policy, Terms, Refund, and Cancellation policy pages display correctly on both Admin and Member panels.
- [ ] Verify Google Sign-In with a clean account (without a pre-existing DB record).

### Phase 3: Store Compliance
- [ ] Generate the release keystore for Android and add the release SHA-1 fingerprint to the Firebase Console / Google Cloud console (required for Google Sign-In to work in the production APK).
- [ ] Submit the Firebase/Google OAuth consent screen for review (move out of "Testing" to "Production").
- [ ] Add `NSPhotoLibraryAddUsageDescription` in `Info.plist` for saving marketing posters on iOS.
