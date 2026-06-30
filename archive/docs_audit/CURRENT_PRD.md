# SILENCE — Implemented Product Requirements Summary (Current State)

This document describes the actual, implemented features and functional workflows of the **SILENCE** Flutter application as of the current codebase. It serves as the single source of truth for the product's operational state.

---

## 1. Core Product Description
**SILENCE** is a mobile-first workspace management platform designed for library owners (Admins) and co-studying students (Members). The system coordinates seat allocations, access control, plan renewals, collections tracking, and operational analytics.

---

## 2. User Roles & Implemented Workflows

### A. Admin / Library Owner perspective

#### 1. Onboarding & Workspace Setup
- **Admin Profile Setup**: Completes registration, email/phone capture, and personal credentials.
- **Library Setup Wizard**:
  - **Stage 1 (Details)**: Input library name, address, contact, about text, amenities list, and rules.
  - **Stage 2 (Layout Grid)**: Configure floor count, name sections (General, Boys, Girls, Premium), and add seats with custom labels.
  - **Stage 3 (Timings & Plans)**: Configure shift periods (fixed times, pricing, monthly/multi-month models, trial days).

#### 2. Operations & Member Roster
- **Dashboard**: Track active seats occupied, occupancy rates, check-in history lists, pending join requests, and confirmed revenue counts.
- **Join Approvals**: Review student detail proofs, assign vacant seats, and approve memberships.
- **Roster & Attendance**: View active, pending, and expired lists. Force exit members, edit checkout histories, or check-in members manually.
- **Add-on Services**: Setup locker allocations or study packs with pricing.

#### 3. Administrative Settings
- **Closures Calendar**: Mark holidays to block member scanner entries.
- **Announcements**: Write notices logged to the database for member feed displays.
- **Referrals Rules**: Set reward days given to students for affiliate signups.
- **Exports Center**: Download member rosters, payments, revenue, and attendance logs.

---

### B. Member / Student perspective

#### 1. Registration & Library Search
- **Profile Registration**: Setup credentials, select exam categories (e.g. UPSC, JEE, NEET), and upload profile images.
- **Discover Study Zones**: Search libraries by name, city, or code. View library public profiles, select shifts, choose plans, and submit applications.

#### 2. Workspace Access (Check-In)
- **QR Entry/Exit**: Scan the library's physical QR code using the in-app camera to record real-time check-in and check-out logs.

#### 3. Account History & renewals
- **Membership Tab**: Renders active subscription status, seat labels, and plan expiry countdowns.
- **Renewals**: Submit renewal requests for active or expired memberships, choose new shifts, and submit payments.
- **Hold Requests**: Submit hold/pause requests with date ranges and reason inputs.
- **Inquiries**: File feedback tickets and bug reports directly to library owners.

---

## 3. Storage, Database, & Offline Sync

- **Database Backend**: Uses Supabase Postgres database.
- **Local SQLite Caching**: Implements local database `silence_offline.db` inside client devices. Stores attendance scans in a queue (`offline_scan_queue`) when offline, syncing automatically when connectivity is restored.
- **File Uploads**: Profiles, payment screenshots, and member ID verification files upload to Supabase Storage.

---

## 4. Current Operational Limitations & Mocked Modules

The following specifications are mocked, simulated, or have specific deviations in the current code:
1. **Mocked OTP Authentication**: Verification overlays for phone and email profiles are simulated in the UI; no live SMS/Email OTP code transmission takes place.
2. **Simulated Payments**: Payments are handled via visual checkout modal sheet sheets with delayed timers simulating Razorpay transaction responses.
3. **Local Database Notifications**: Real-time Firebase Cloud Messaging (FCM) is unimplemented. Notifications write directly to the database and are fetched client-side.
4. **TXT-Based PDF Exports**: Reports exported under the "PDF" option write formatted plain text to `.txt` files instead of compiling binary PDF documents.
5. **No Excel spreadsheet output**: Spreadsheet downloads are unsupported.
6. **Public Bucket Uploads**: Sensitive files (IDs and UPI screenshots) upload to the public bucket `silence_assets` instead of the RLS-protected `silence_private` bucket.
7. **Unenforced Business Rules**: Maximum discount caps and seat hold limits are saved in configurations but not verified when creating transactions.
8. **Restricted Expense Categories**: The Postgres expenditures table restricts category inputs to 5 types, unlike the 12 listed in original specs.
