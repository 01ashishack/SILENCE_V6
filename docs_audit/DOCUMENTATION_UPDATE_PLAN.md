# SILENCE Documentation Update Plan

This document provides specific, actionable steps to update the files in `silence_app/` to align them with the codebase (the source of truth).

---

## 1. Mapped Document Revisions

### [15_Screen_Inventory.csv](file:///c:/Users/kumar/combined/SILENCE_V6/silence_app/15_Screen_Inventory.csv)
- **Required Action**:
  - Rename `LibraryProfileScreen` path from `lib\screens\library_profile.dart` to `lib\screens\library_profile_screen.dart`.
  - Add newly implemented screens:
    - `SocialLinksEditScreen` (`lib/screens/social_links_edit_screen.dart`)
    - `AboutUsScreen` (`lib/screens/about_us_screen.dart`)
    - `HelpSupportScreen` (`lib/screens/help_support_screen.dart`)
    - `TermsScreen` (`lib/screens/terms_screen.dart`)
    - `AppSettingsScreen` (`lib/screens/app_settings_screen.dart`)

### [03_Screen_Flow_Diagram.mmd](file:///c:/Users/kumar/combined/SILENCE_V6/silence_app/03_Screen_Flow_Diagram.mmd)
- **Required Action**:
  - Insert routing links from the updated `AppSettingsScreen` to `SocialLinksEditScreen`, `HelpSupportScreen`, `AboutUsScreen`, and `TermsScreen` endpoints.

### [17_API_Endpoints.md](file:///c:/Users/kumar/combined/SILENCE_V6/silence_app/17_API_Endpoints.md)
- **Required Action**:
  - Deprecate sections describing database RPC function calls (`rpc(...)`) and Edge Functions.
  - Document client-side REST queries targeting the database tables directly.

### [10_Storage_Folders.txt](file:///c:/Users/kumar/combined/SILENCE_V6/silence_app/10_Storage_Folders.txt)
- **Required Action**:
  - Update policies to reflect that files are uploaded to the public `silence_assets` bucket, noting the fallback from `silence_private` inside profile photo uploads.

### [08_Razorpay_Spec.md](file:///c:/Users/kumar/combined/SILENCE_V6/silence_app/08_Razorpay_Spec.md)
- **Required Action**:
  - Add an appendix specifying that the payment flow is currently running in a mocked simulation container using a simulated check-out UI bottom sheet.

### [06_Business_Rules.csv](file:///c:/Users/kumar/combined/SILENCE_V6/silence_app/06_Business_Rules.csv)
- **Required Action**:
  - Adjust rule limits to match the application code:
    - Default `max_discount_percent` from `100` to `15` (matching default settings).
    - Default `max_hold_days` from `30` to `15`.
    - Change default `allow_expired_checkin` from `true` to `false`.
