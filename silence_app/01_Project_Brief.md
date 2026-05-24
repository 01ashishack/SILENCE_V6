# SILENCE – Project Brief

## Product Name
**SILENCE** – Library & Study Space Management Platform

## Tagline
*"Replace the register and WhatsApp with one operational app."*

## Problem Statement
Indian study libraries (Tier 2/3 cities) run on fragmented systems: WhatsApp groups for announcements, paper registers for attendance, and spreadsheets for memberships. Owners waste hours manually tracking payments, seat occupancy, and renewals. Students have no visibility into their attendance, streaks, or study hours.

## Solution
SILENCE is a mobile-first platform (Android + iOS) that gives library owners a single dashboard to manage seats, members, attendance, payments, and analytics. Students get a personal app to track their study streaks, leaderboard rank, and membership status.

## Target Market
- **Primary:** Study library owners in Indian Tier 2/3 cities (Alwar, Bhilwara, Kota, Jaipur, etc.)
- **Secondary:** Students preparing for competitive exams (UPSC, NEET, JEE, SSC)

## Key Differentiators
- **Dashboard-first** – owner lands on live stats, not a setup wizard.
- **Multi-shift seat model** – same physical seat can be assigned to different members in morning/evening shifts.
- **Static printable QR** – print once, laminate, use forever. No daily refresh needed.
- **Offline-first scanning** – scans stored locally (up to 500) and sync when internet returns.
- **India-specific payments** – UPI deep-links (PhonePe, GPay, Paytm), cash receipt photos, discounts.
- **Streak + leaderboard** – gamification for students.
- **Verified badge** – builds trust for serious libraries.

## Platform & Tech Stack (AI Build Instructions)

| Component | Technology | Responsibility |
|-----------|------------|----------------|
| **Frontend** | Flutter (or React Native) | Cross-platform UI (Android + iOS) |
| **Backend database** | Supabase (PostgreSQL) | All app data: users, libraries, seats, attendance, payments, audit log |
| **Authentication** | Supabase Auth (email/password, Google, Apple) | Single source of truth; RLS integration |
| **File storage** | Supabase Storage | Library photos, member profiles, ID proofs, payment screenshots |
| **Real-time updates** | Supabase Realtime (optional) | Live occupancy dashboard |
| **Push notifications** | Firebase Cloud Messaging (FCM) | Only for notifications – not for data storage |
| **Subscription payments** | Razorpay | Admin pays SILENCE (Starter/Basic/Pro plans) |
| **Offline storage** | IndexedDB / SQLite | Scan queue (500 max) + read cache |

> ⚠️ **Do NOT use Firebase Authentication or Firestore.** They would conflict with Supabase RLS and create data duplication. Firebase is used **only** for push notifications.

## Two User Roles

### 1. Library Owner (Admin)
- Manages one or multiple libraries.
- Tracks revenue, occupancy, member attendance.
- Approves join requests, confirms payments, sends announcements.
- Configures shifts, seats, pricing, add-ons.
- Earns Verified badge after meeting quality criteria.

### 2. Student (Member)
- Joins libraries via QR or library code.
- Scans QR to check in/out.
- Views personal analytics: streak, total hours, leaderboard.
- Requests seat change, pause membership, transfers.
- Refers friends for free days.

## Core Flows (High Level)
- **Admin onboarding:** Setup library → add shifts → configure seats → launch.
- **Member join:** Find library → apply (or trial) → admin approves → seat assigned.
- **Daily attendance:** Member scans QR at entrance → check-in → study → scan to check-out.
- **Renewal:** Member or admin renews membership (payment via cash/UPI, offline).
- **Analytics:** Admin sees revenue/expenses/occupancy; member sees study progress.

## Multi‑Language Support (Architecture Ready – V2)
- **V1:** English only. No language toggle shown.
- **V2:** Hindi will be added. The backend already stores `users.language_code` (default 'en').
- **What is NOT translated in V2:** Admin‑created content (announcements, library rules) – admin can write bilingual if desired.

## Out of Scope for V1
- Hindi language UI (V2)
- Partial / installment payments (V2)
- Staff sub-accounts (V2)
- Batch CSV import of members (V1.5)
- Guest passes (V2)
- Automated GST invoicing (V2)

## Success Metrics (for AI to optimise)
- Admin daily active users (DAU)
- Member retention after 7 days
- QR scan success rate (including offline)
- Average time from join request to approval
- Leaderboard engagement (weekly active participants)

## Reference Documents
This brief is part of a set. See:
- `02_User_Stories.csv`
- `03_Screen_Flow_Diagram.mmd`
- `04_Database_Schema.json`
- `05_RLS_Rules.json`
- `06_Business_Rules.csv`
- `07_Workflows.yaml`
- `08_Razorpay_Spec.md`
- `09_Notification_Payloads.json`
- `10_Storage_Folders.txt`
- `11_Test_Scenarios.csv`
- `12_Offline_Schema.sql`
- `13_Master_Prompt.md`
- `14_Build_Order.md`

## Ready for AI Build
This brief provides the **what** and **why**. The companion files provide the **how** (schema, rules, flows, tests). Feed all files into your no‑code AI builder in the order specified in `14_Build_Order.md`.