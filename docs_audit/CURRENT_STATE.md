# SILENCE Codebase Current State & Architectural Summary

This document describes the current architectural state of the **SILENCE** Flutter application (`lib/`), which serves as the source of truth for all modules, screens, database relations, and service integrations.

---

## 1. Navigation & Routing System

The routing is centralized in [lib/main.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/main.dart). The application uses static routes defined inside the `MaterialApp` widget. 

### Map of Active Named Routes in App

| Named Route | Widget Name | File Path |
|---|---|---|
| `/` | `SplashScreen` | [splash_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/splash_screen.dart) |
| `/login` | `AuthScreen` | [auth_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/auth_screen.dart) |
| `/auth` | `AuthScreen` | [auth_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/auth_screen.dart) |
| `/role` | `RoleSelectionScreen` | [role_selection_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/role_selection_screen.dart) |
| `/role-select` | `RoleSelectionScreen` | [role_selection_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/role_selection_screen.dart) |
| `/admin` | `AdminHomeScreen` | [admin_home.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/admin_home.dart) |
| `/admin/home` | `AdminHomeScreen` | [admin_home.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/admin_home.dart) |
| `/member` | `MemberHomeScreen` | [member_home.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/member_home.dart) |
| `/member/home` | `MemberHomeScreen` | [member_home.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/member_home.dart) |
| `/admin/profile/complete` | `AdminProfileCompleteScreen` | [admin_profile_complete.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/admin_profile_complete.dart) |
| `/admin/library/setup/1` | `LibrarySetupStage1Screen` | [library_setup_stage1.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/library_setup_stage1.dart) |
| `/admin/library/setup/2` | `LibrarySetupStage2Screen` | [library_setup_stage2.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/library_setup_stage2.dart) |
| `/admin/library/setup/3` | `LibrarySetupStage3Screen` | [library_setup_stage3.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/library_setup_stage3.dart) |
| `/admin/member` | `MemberDetailScreen` | [member_detail_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/reservations/member_detail_screen.dart) |
| `/admin/library/profile` | `LibraryProfileScreen` | [library_profile_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/library_profile_screen.dart) |
| `/admin/settings/social-links` | `SocialLinksEditScreen` | [social_links_edit_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/social_links_edit_screen.dart) |
| `/admin/about-us` | `AboutUsScreen` | [about_us_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/about_us_screen.dart) |
| `/admin/help-support` | `HelpSupportScreen` | [help_support_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/help_support_screen.dart) |
| `/admin/terms` | `TermsScreen` | [terms_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/terms_screen.dart) |
| `/admin/app-settings` | `AppSettingsScreen` | [app_settings_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/app_settings_screen.dart) |
| `/admin/verified-badge` | `VerifiedBadgeScreen` | [verified_badge_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/verified_badge_screen.dart) |
| `/admin/settings/shifts` | `ShiftManagementScreen` | [shift_management.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/shift_management.dart) |
| `/admin/settings/pricing` | `PricingPlansScreen` | [pricing_plans.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/pricing_plans.dart) |
| `/admin/settings/business-rules` | `BusinessRulesScreen` | [business_rules.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/business_rules.dart) |
| `/admin/settings/branding` | `BrandingAssetsScreen` | [branding_assets.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/branding_assets.dart) |
| `/admin/settings/qr` | `QRAssetsScreen` | [qr_assets.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/qr_assets.dart) |
| `/admin/settings/addons` | `AddonServicesScreen` | [addon_services.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/addon_services.dart) |
| `/admin/settings/notifications` | `NotificationPreferencesScreen` | [notification_preferences.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/notification_preferences.dart) |
| `/admin/exports` | `ExportCenterScreen` | [export_center.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/export_center.dart) |
| `/admin/announcements` | `AnnouncementsHistoryScreen` | [announcements_history_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/announcements_history_screen.dart) |
| `/admin/subscription` | `SubscriptionScreen` | [subscription_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/subscription_screen.dart) |
| `/admin/audit-log` | `AuditLogScreen` | [audit_log_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/audit_log_screen.dart) |
| `/admin/settings/referrals` | `ReferralSettingsScreen` | [referral_settings.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/referral_settings.dart) |
| `/admin/settings/closures` | `ScheduledClosuresScreen` | [scheduled_closures.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/scheduled_closures.dart) |
| `/admin/member/add` | `AddMemberWizard` | [add_member_wizard.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/admin/add_member_wizard.dart) |

---

## 2. Database & Storage Architecture

### Remote Database (Supabase)
The app interacts directly with a PostgreSQL schema hosted on Supabase using `supabase_flutter`. Direct REST requests are initiated via client builders rather than SQL RPC procedures or Edge functions.

- **Primary Tables Audited**:
  - `users`: ID profiles, credentials, role types, subscription structures.
  - `libraries`: Library entity details, address blocks, metadata properties.
  - `floors`, `sections`, `seats`: Space mapping tables.
  - `shifts`: Configuration profiles representing seat occupancy sessions.
  - `memberships`, `attendance`: Log events tracking entry check-ins.
  - `verification_requests`: Verification badges requesting logic workflows.
  - `payments`: Local ledger records documenting transaction details.
  - `scheduled_closures`: Closures mapping scheduled holidays.
  - `add_ons`: Custom optional services configuring catalog inventory.
  - `queries`: Support inquiries and user bugs filed.
  - `expenditures`: Balance logs documenting expenses.
  - `referrals`: Affiliate reward links tracing active referrals.

### Storage Buckets
The application uploads user assets, ID proofs, and branding graphics using Supabase Storage buckets.
- **Main Public Bucket**: `silence_assets` is used as the default target destination for all uploads (profile pictures, library graphics, member IDs).
- **Private Bucket**: `silence_private` is attempted as a write target for admin profile edits, but falls back to `silence_assets` on permission failure.

---

## 3. Local Offline Sync Schema

Local caching and offline queue writes are stored using `sqflite` inside a database named `silence_offline.db`.

- **Queue Table**: `offline_scan_queue` stores pending scans (`checkin` / `checkout`) structured in ISO 8601 formats.
- **Cache Tables**:
  - `cache_members`: Local mirror mapping active library members.
  - `cache_attendance_today`: Records check-ins for the current day.
  - `cache_seat_grid`: Map data detailing current occupancy status.
  - `cache_member_memberships` & `cache_member_attendance`: Local records mapping user logins.
- **Sync Method**: Initialized via [offline_db.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/core/offline_db.dart), verifying database migrations during startup.

---

## 4. Payment Integrations

- **Razorpay Payments**: Implemented via a simulation mock flow in [subscription_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/subscription_screen.dart#L119-L272) instead of importing external Razorpay SDK binaries. The simulation updates local state and writes success indicators to remote Supabase profiles.
