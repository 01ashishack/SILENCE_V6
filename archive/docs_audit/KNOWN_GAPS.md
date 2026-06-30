# SILENCE Documented Specs vs Codebase Implementation - Known Gaps

This document catalogues all functional gaps and architectural deviations identified between the original documentation (`silence_app/`) and the current Flutter codebase (`lib/`).

---

## 1. API & Backend Communication (REST vs. RPC/Edge Functions)
- **Documented Spec (`17_API_Endpoints.md`)**: Specifies that critical transactions (like checking in, renewing, or processing holds) are executed via PostgreSQL Remote Procedure Calls (RPCs) and Supabase Edge Functions.
- **Codebase Reality**: The app does **not** call any RPCs or Edge functions. It queries, updates, and inserts directly using the client-side Supabase REST builder (e.g., `_supabase.from('tableName').insert(...)` or `.update(...)`).
- **Code Evidence**:
  - Check-in writes are saved directly using `.from('attendance').insert(...)` in [join_flow_screen.dart](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/reservations/join_flow_screen.dart).
  - Business rules configurations write directly to libraries in [business_rules.dart:L96](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/business_rules.dart#L96-L100).
- **Risk Level**: **Medium**. Bypasses server-side schema constraints and centralized database trigger execution logic.

---

## 2. Storage Buckets (Public `silence_assets` vs. Private `silence_private`)
- **Documented Spec (`10_Storage_Folders.txt`)**: Requires uploading member ID proofs, owner registration files, and sensitive documents to a private storage bucket (`silence_private`) governed by Row Level Security (RLS) policies.
- **Codebase Reality**: Almost all image uploads and ID proofs default to the public bucket `silence_assets`. Only profile photos in `admin_profile_tab.dart` attempt to use `silence_private` as a primary path, falling back to `silence_assets` on error.
- **Code Evidence**:
  - Member join uploads in [join_flow_screen.dart:L198](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/reservations/join_flow_screen.dart#L198-L200) target `silence_assets`.
  - Member profile edits in [member_profile_edit.dart:L254](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/member_profile_edit.dart#L254-L256) target `silence_assets`.
- **Risk Level**: **High** (Data Privacy). Member ID proofs are publicly readable via generated public URLs.

---

## 3. Razorpay Payments Integration (Mocked Simulation)
- **Documented Spec (`08_Razorpay_Spec.md`)**: Outlines complete integration with Razorpay Standard Checkout SDKs, callback handlers, signature verification, and edge hooks.
- **Codebase Reality**: Payment processing is completely simulated using a mock UI bottom sheet. No external SDK binaries or packages for Razorpay are imported.
- **Code Evidence**:
  - The payment checkout UI is defined in [subscription_screen.dart:L119-L272](file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/subscription_screen.dart#L119-L272) using visual indicators and mock timers (`Future.delayed`).
- **Risk Level**: **Low** (Simulation Status). Currently in test mode; integration is required for production.

---

## 4. Push Notifications (Local/Database Logs Only)
- **Documented Spec (`09_Notification_Payloads.json`)**: Details FCM notification payloads for real-time check-ins, closure announcements, and dues alerts.
- **Codebase Reality**: The application lacks Firebase Cloud Messaging (FCM) implementation. Notifications are logged locally in tables or printed to debug consoles.
- **Risk Level**: **Medium**. Users will not receive push notifications on mobile devices until client listeners and triggers are configured.
