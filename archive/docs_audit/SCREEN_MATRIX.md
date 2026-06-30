# SILENCE Screen Reconciliation Inventory Matrix

This matrix maps all screen classes in `lib/screens/` against the original screen inventory listed in [15_Screen_Inventory.csv](file:///c:/Users/kumar/combined/SILENCE_V6/silence_app/15_Screen_Inventory.csv).

| Screen ID / Class | File Path (Source of Truth) | Documented Path | Status | Notes / Key Deviations |
|---|---|---|---|---|
| `SplashScreen` | [splash_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/splash_screen.dart) | `lib\screens\splash_screen.dart` | **Synced** | Handles initial logo display and checks active auth sessions. |
| `AuthScreen` | [auth_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/auth_screen.dart) | `lib\screens\auth_screen.dart` | **Synced** | Handles login/signup for both owners and members. |
| `RoleSelectionScreen` | [role_selection_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/role_selection_screen.dart) | `lib\screens\role_selection_screen.dart` | **Synced** | Directs new signups to owner or student flows. |
| `AdminHomeScreen` | [admin_home.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/admin_home.dart) | `lib\screens\admin_home.dart` | **Synced** | Main admin hub dashboard tab host. |
| `MemberHomeScreen` | [member_home.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/member_home.dart) | `lib\screens\member_home.dart` | **Synced** | Main member dashboard hub tab host. |
| `LibraryProfileScreen` | [library_profile_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/library_profile_screen.dart) | `lib\screens\library_profile.dart` | **Renamed** | File renamed during development (added `_screen` suffix). |
| `SocialLinksEditScreen`| [social_links_edit_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/social_links_edit_screen.dart) | None | **Missing in Docs** | Implemented screen allowing admins to configure social icons. |
| `AboutUsScreen` | [about_us_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/about_us_screen.dart) | None | **Missing in Docs** | Details company terms and licensing profiles. |
| `HelpSupportScreen` | [help_support_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/help_support_screen.dart) | None | **Missing in Docs** | Integrated screen allowing users to submit bug reports and contact support. |
| `TermsScreen` | [terms_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/terms_screen.dart) | None | **Missing in Docs** | Legalese and terms display screen. |
| `AppSettingsScreen` | [app_settings_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/app_settings_screen.dart) | None | **Missing in Docs** | Renders unified settings groups (preferences, cache clear, links). |
| `VerifiedBadgeScreen` | [verified_badge_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/verified_badge_screen.dart) | `lib\screens\verified_badge_screen.dart` | **Synced** | Shows badges rules and locks criteria. |
| `ShiftManagementScreen`| [shift_management.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/shift_management.dart) | `lib\screens\shift_management.dart` | **Synced** | Handles configuring shifts and prices. |
| `BusinessRulesScreen` | [business_rules.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/business_rules.dart) | `lib\screens\business_rules.dart` | **Synced** | Sets discount caps and grace boundaries. |
| `AddonServicesScreen` | [addon_services.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/addon_services.dart) | `lib\screens\addon_services.dart` | **Synced** | Controls lockers and add-on inventory. |
| `ExportCenterScreen` | [export_center.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/export_center.dart) | `lib\screens\export_center.dart` | **Synced** | Performs CSV/PDF reports exports. |
| `SubscriptionScreen` | [subscription_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/subscription_screen.dart) | `lib\screens\subscription_screen.dart` | **Synced** | Displays plan levels and invoice simulations. |
| `AuditLogScreen` | [audit_log_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/audit_log_screen.dart) | `lib\screens\audit_log_screen.dart` | **Synced** | Displays system audit trails. |
| `AddMemberWizard` | [add_member_wizard.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/admin/add_member_wizard.dart) | `lib\screens\admin\add_member_wizard.dart` | **Synced** | Coordinates steps for member creation. |
| `JoinFlowScreen` | [join_flow_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/reservations/join_flow_screen.dart) | `lib\screens\reservations\join_flow_screen.dart` | **Synced** | Controls student admission flow wizard. |
| `MemberDetailScreen` | [member_detail_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/reservations/member_detail_screen.dart) | `lib\screens\reservations\member_detail_screen.dart` | **Synced** | Handles viewing detailed member records. |
| `LibraryPublicProfileScreen` | [library_public_profile_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/library_public_profile_screen.dart) | None | **Missing in Docs** | Renders unified public details, shift details, amenities, location links, and user reviews. |
