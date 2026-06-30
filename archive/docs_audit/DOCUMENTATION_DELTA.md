# SILENCE V6 — Project Documentation Delta Report

This report documents all structural and functional discrepancies identified between the original specifications (including `SILENCE_PRD_v6.1_Final.md`, screen flow specs, and original screen inventory) and the actual implementation in the current Flutter codebase (`lib/`).

---

## 1. Added Screens (In Code but Not in Original Specs)

The following 19 screen-level classes and major overlay widgets exist in the codebase but were missing or omitted from the original screen inventory and screen-by-screen specifications:

1. **`LibraryPublicProfileScreen` ([library_public_profile_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/library_public_profile_screen.dart))**: Renders the public-facing details, shifts, amenities, and user reviews of a library for student members.
2. **`ExploreScreen` ([member_explore_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/member_explore_screen.dart))**: A search and discover screen allowing members to find study zones by name, city, or library code.
3. **`LibraryQueryScreen` ([library_query_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/reservations/library_query_screen.dart))**: Allows members to submit messages, questions, and bug reports directly to library admins.
4. **`RenewalScreen` ([renewal_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/reservations/renewal_screen.dart))**: Provides a wizard for members to renew their plans, select new shifts, and apply discount codes.
5. **`PastLibraryDetailScreen` ([past_library_detail_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/past_library_detail_screen.dart))**: Renders details of a member's past or expired memberships.
6. **`SocialLinksEditScreen` ([social_links_edit_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/social_links_edit_screen.dart))**: Form interface allowing admins to link Facebook, Instagram, Twitter, and UPI payment details.
7. **`AboutUsScreen` ([about_us_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/about_us_screen.dart))**: Renders company info, version details, and standard licenses in the admin menu.
8. **`HelpSupportScreen` ([help_support_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/help_support_screen.dart))**: Admin interface for submitting inquiries and bugs.
9. **`TermsScreen` ([terms_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/terms_screen.dart))**: Renders legal terms of service for admins.
10. **`AppSettingsScreen` ([app_settings_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/app_settings_screen.dart))**: Settings listing for admins (cache clearing, links, preferences).
11. **`MemberAboutScreen` ([member_about_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/member_about_screen.dart))**: Company info screen on the member side.
12. **`MemberHelpSupportScreen` ([member_help_support_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/member_help_support_screen.dart))**: Support inquiry screen on the member side.
13. **`MemberTermsScreen` ([member_terms_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/member_terms_screen.dart))**: Terms of service on the member side.
14. **`MemberPrivacyPolicyScreen` ([member_privacy_policy_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/member_privacy_policy_screen.dart))**: Privacy policy on the member side.
15. **`MemberLicencesScreen` ([member_licences_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/member_licences_screen.dart))**: Legal licensing details on the member side.
16. **`MemberNotificationPreferencesScreen` ([member_notification_preferences_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/member_notification_preferences_screen.dart))**: Notification toggles on the member side.
17. **`MemberPrivacySecurityScreen` ([member_privacy_security_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/member_privacy_security_screen.dart))**: Security preferences for member profiles.
18. **`NotificationsScreen` ([notifications_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/notifications_screen.dart))**: Generic fallback screen displaying a "caught up" illustration for notifications.
19. **`MemberHistoryTab` ([member_history_tab.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/member_history_tab.dart))**: Inner tab view displaying logs of past visits, queries raised, and active plans.

---

## 2. Renamed Screens (Path / Naming Discrepancies)

- **`LibraryProfileScreen`**: Class name defined in [library_profile_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/library_profile_screen.dart). Original specs documented this path as `lib\screens\library_profile.dart` (lacking the `_screen` suffix).

---

## 3. Removed Screens (Documented but Missing in Code)

No major functional screen has been entirely deleted, but several documented helper components and entry configurations are organized inside the codebase differently:
- **`SilenceApp`**: Documented as a screen in `15_Screen_Inventory.csv` but is actually the root application class in `lib/main.dart`.
- **`_CalendarDialogPicker`**: Documented as a separate screen but is a helper class in `lib/core/calendar_picker.dart` instantiated dynamically as a dialog.
- **`QRModal` / `SeatGenerationInlineWidget` / `VacantSeatGrid`**: Documented as screens, but exist as reusable widgets under `lib/widgets/`.

---

## 4. Navigation Flow Deviations

The implemented button clicks and navigation flows in the Flutter app differ from the expected UX specs in these critical areas:
1. **Admin Dashboard Tiles Redirect to Onboarding**: Tapping "Library Information", "Amenities & Facilities", or "Rules & Guidelines" on the Admin home screen directs users to the initial Stage 1 setup wizard (`/admin/library/setup/1`) instead of the dedicated, implemented management pages.
2. **Shift & Pricing Dashboard Tiles Redirect to Onboarding**: Tapping "Shift Configuration" or "Membership Seat Pricing" on the Admin home screen directs users to the initial Stage 3 setup wizard (`/admin/library/setup/3`) rather than their respective settings pages.
3. **Seat Action Redirects**: In the layout grid, selecting "Reassign Seat" or "Renew Membership" in a seat's context menu routes to setup wizards `/admin/library/setup/2` and `/admin/library/setup/3` instead of launching specific reassignment/renewal modals.
4. **Broken Notifications Route**: In `ExploreScreen`, clicking the notification icon pushes `/member/notifications` which is unregistered in `main.dart` and triggers a route crash.

---

## 5. Missing Features (In Specs but Not in Code)

Several key features detailed in the PRD and technical design specifications are missing or only exist as visual mocks in the codebase:

1. **OTP Verification via Phone/Email**: The onboarding specs specify OTP-based authentication using SMS/Email gateways. In code, the OTP verification form is simulated; entering any code progresses the user without backend verification.
2. **FCM Real-Time Push Notifications**: Documented payloads and triggers for real-time check-ins and renewals are not integrated. Firebase Messaging is omitted, and notifications are processed locally in tables.
3. **Razorpay Standard Checkout SDK**: The PRD outlines a full integration with the Razorpay payment checkout wrapper. The actual implementation uses a simulated bottom sheet overlay with visual timers to mock checkout success.
4. **Excel Spreadsheet Export**: The Export Center specifies `.xlsx` spreadsheet files. The implementation has no Excel package dependencies and does not support `.xlsx` formats.
5. **Standard PDF Exporting**: Exporting reports to PDF is simulated; the export writes plain text with monospaced margins directly to a `.txt` file rather than generating a binary PDF document.
6. **Automatic Seat Expiry & Holds**: Business rules outline automatic holds and grace periods. In the codebase, memberships expire but no automatic script runs to vacate seats or handle hold expirations.
7. **Security Groupings**: Sensitive documents (member ID proofs, payment screenshots) upload directly to the public bucket `silence_assets` instead of the RLS-governed private bucket `silence_private`.
8. **Enforcement of Business Rules**: Values configured in the business rules dashboard (such as maximum discount cap, maximum hold duration, and hold request limits) are saved to settings but **never validated or enforced** when processing transactions in the code.
9. **Full Expense Categories List**: The specs list 12 expense categories, but the PostgreSQL table `expenditures` enforces a strict CHECK constraint allowing only 5 categories (`rent`, `electricity`, `internet`, `maintenance`, `other`).

---

## 6. Extra Features (In Code but Not in Specs)

Several features have been built into the codebase that were not part of the original design documents:

1. **Referral Reward Nickname Tracking**: The join wizard and referral tabs fully implement referral input and nick-matching code, tracking user links during signup.
2. **Admin Audit Logs screen**: A complete audit trail UI page that queries system events recorded in the `audit_log` table.
3. **Offline Scanner Access Cache & SQLite Sync Queue**: A complete offline Scan-Queue engine built with `sqflite` inside `silence_offline.db` that syncs pending check-ins automatically when network availability is restored.
4. **Add-on Services Inventory**: An optional locker and addon manager in the Admin profile, integrated directly into the member join checkout flow.
