# SILENCE Feature Reconciliation Matrix

This document maps all user stories documented in [02_User_Stories.csv](file:///c:/Users/kumar/combined/SILENCE_V6/silence_app/02_User_Stories.csv) against the actual features implemented in the Flutter codebase (`lib/`).

| Feature / Story | Documented (US ID) | Code Implementation Status | Technical Notes & Evidence |
|---|---|---|---|
| **Role Signup Selection** | Yes (Row 2) | **Synced** | Handled in [role_selection_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/role_selection_screen.dart) with permanent roles written to the `users` table (`upsert` at line 52). |
| **Admin Profile Onboarding** | Yes (Row 3) | **Synced** | Handled in [admin_profile_complete.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/admin_profile_complete.dart) and [admin_profile_tab.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/admin_profile_tab.dart). |
| **Library Setup Stage 1** | Yes (Row 4) | **Synced** | Implemented in [library_setup_stage1.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/library_setup_stage1.dart), generating a library entity with basic details. |
| **Shifts & Pricing (Stage 3)** | Yes (Row 5) | **Synced** | Implemented in [shift_management.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/shift_management.dart) and [pricing_plans.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/pricing_plans.dart). Upserts shifts into the `shifts` table. |
| **Layout Setup (Stage 2)** | Yes (Row 6) | **Synced** | Generates floors, sections, and seats in [library_setup_stage2.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/library_setup_stage2.dart) and [library_setup_stage3.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/library_setup_stage3.dart). |
| **Operational Dashboard Stats** | Yes (Row 8) | **Synced** | Displayed in [admin_home.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/admin_home.dart) using a `CustomPainter` donut chart and tappable summary indicators. |
| **Join Request Approvals** | Yes (Row 10, 11) | **Synced** | Handled in [requests_sub_tab.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/reservations/requests_sub_tab.dart). Admin reviews proof image and allocates seats. |
| **Manual Check-in** | Yes (Row 12) | **Synced** | Implemented in [member_detail_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/reservations/member_detail_screen.dart) and today's attendance lists. |
| **Seat Reassignment** | Yes (Row 13) | **Synced** | Action options inside [layout_sub_tab.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/reservations/layout_sub_tab.dart). Updates seat assignments in the database. |
| **Seat Maintenance Alerts** | Yes (Row 14) | **Synced** | Configurable via seat actions. Visual indicators display seat maintenance statuses in seat layouts. |
| **Membership Discounts** | Yes (Row 16) | **Synced** | Applied in renewal and member wizards. Validated against max discount limits set in [business_rules.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/business_rules.dart). |
| **Announcements Send** | Yes (Row 17) | **Synced** | Implemented via announcements composition cards in [admin_home.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/admin_home.dart) and logged to the `announcements` table. |
| **Support Desk Queries** | Yes (Row 18, 42) | **Synced** | Handled inside [help_support_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/help_support_screen.dart). Inserts bug reports and general feedback. |
| **Add-on Services** | Yes (Row 19) | **Synced** | Managed in [addon_services.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/addon_services.dart) and integrated directly into the member join flow. |
| **Scheduled Closures** | Yes (Row 20) | **Synced** | Configurable in [scheduled_closures.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/scheduled_closures.dart). Inserts closures and blocks scanner check-ins. |
| **Admin subscription billing** | Yes (Row 21) | **Partially Synced** | Subscription screen is active ([subscription_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/subscription_screen.dart)), but uses a checkout mock instead of live Razorpay integration. |
| **Data Exports (CSV & PDF)** | Yes (Row 22) | **Synced** | Handled in [export_center.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/export_center.dart) with presets and CSV/PDF file output engines. |
| **Audit Logs** | Yes (Row 23) | **Synced** | Logged to database and readable in [audit_log_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/audit_log_screen.dart). |
| **Phone/Email Verification** | Yes (Row 44) | **Missing in App** | Documented in PRD but the OTP verification forms are simulated/mocks in the UI without sending active SMS/emails. |
| **Push Notifications** | Yes (Row 51) | **Partially Synced** | Core FCM initialization is omitted in `lib/`. Instead, it uses local notifications or prints database notification log entries. |
| **Offline Sync Queue** | Yes (Row 47) | **Synced** | Built using `sqflite` in [offline_db.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/core/offline_db.dart) and matching documented write specifications. |
| **Referrals Settings** | Yes (Row 40) | **Synced** | Configurable in [referral_settings.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/referral_settings.dart) and used to tracking nick references in join paths. |
