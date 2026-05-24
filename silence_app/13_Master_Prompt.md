# SILENCE – Master Build Prompt for No‑Code AI

## Your Role
You are an expert full‑stack mobile app developer. You will build **SILENCE**, a library management platform for Indian study libraries. Use the attached files as your source of truth.

## Project Overview
- **Name:** SILENCE
- **Tagline:** "Library Management & QR Attendence"
- **Platforms:** Android & iOS (cross‑platform: Flutter or React Native)
- **Backend:** Supabase (PostgreSQL, Auth, Storage, Realtime)
- **Push Notifications:** Firebase Cloud Messaging (FCM)
- **Payments (subscriptions):** Razorpay (admin pays Silence)
- **Member payments:** Cash / UPI (offline, no gateway)

#Place LOGO.png and horizontal app logo.png in the assets/images/ folder. Use horizontal app logo.png for splash screen, LOGO.png for app icon.

## Key Constraints (Read First)
1. **Offline support:** SQLite/IndexedDB queue (max 500 scans) + read cache. See `12_Offline_Schema.sql`.
2. **Multi‑shift seats:** Same physical seat can be assigned to different members in different shifts.
3. **Static QR:** Printable, permanent. Regenerate with 7‑day grace period.
4. **Admin subscription:** Separate from member payments. Razorpay only for admin → Silence.
5. **No email verification at signup** (optional verification later for verified badge).
6. **Date pickers:** All must be calendar grid, not scroll drums.
7. **Empty states:** Every list/table must have a designed empty state.
8. **Critical actions:** Require type‑to‑confirm (REGENERATE, REMOVE, DELETE, library name, DELETE MY ACCOUNT). Two‑tap for exit.
9. **Hindi language:** Not in V1. Architecture ready (language_code in DB), no UI toggle.

## Build Order (Follow Exactly)

### Milestone 1: Auth & Role Selection (P0)
- **Files:** `04_Database_Schema.json`, `05_RLS_Rules.json`
- **Actions:**
  - Create Supabase project. Enable Auth (email/password, Google, Apple). Disable email verification.
  - Run schema SQL to create all tables, indexes, RLS policies.
  - Build screens:
    - Splash screen (orange #E65C00) → check session → Auth Screen.
    - Auth Screen: Login tab (email + password) / Signup tab (name, email, password, confirm). Google/Apple buttons.
    - After signup → Role Selection Screen (Library Owner / Student). Save role to `users.role`.
    - After role selection → direct to Admin Home or Member Home.
  - Special case: Admin with no library → open Library Setup Stage 1 as modal.

### Milestone 2: Admin Onboarding & Library Setup (P0)
- **Files:** `04_Database_Schema.json`, `06_Business_Rules.csv`, `07_Workflows.yaml`
- **Build screens:**
  - **Admin Home** (setup mode): Setup card with 4 steps. Progress bar 25% each.
    - Step 1: Complete Profile (name, phone, gender, DOB, optional photo)
    - Step 2: Library Setup – Stage 1 (Basic Info: name, address, city, state, PIN, up to 4 photos, amenities, rules). Auto‑generate library code `SIL-XXXXXX` (6‑char alphanumeric, unique).
    - Step 3: Library Setup – Stage 2 (Floors, Sections, Seats). Seat grid with virtualized + paginated (30 per page). Search bar for seat label.
    - Step 4: Library Setup – Stage 3 (Shifts & Plans). Upsert model (no destructive delete). Shift overlap validation (yellow warning).
    - Step 4a: Payment Setup (Cash toggle, UPI IDs with deep‑link icons).
  - After all steps complete: Launch button → setup card disappears → operational dashboard.
- **Business Rules:** Apply defaults from `06_Business_Rules.csv`. Make rules editable in Business Settings.

### Milestone 3: Admin Operational Dashboard (P0)
- **Files:** `04_Database_Schema.json`, `03_Screen_Flow_Diagram.mmd`
- **Build screens:**
  - **Admin Home** (operational):
    - Header: library switcher (dropdown, "All Libraries" allowed), date pill, bell icon.
    - Library photo carousel.
    - Stats grid: Revenue This Month, Active Today, Expired, New Joinings, Expiring Soon, Live Occupancy (donut). All tappable → filtered members.
    - Today's Attendance strip (horizontal scroll, shift filter above). Click member → Mark Present (manual check‑in).
    - Action Required banner (pending payments + join requests).
    - Quick Actions: Add Member, Announce, Joining QR, Attendance QR, Close Today.
    - QR Section: two cards. [Download PDF] [Share] [Regenerate] (type‑to‑confirm, 7‑day grace).
    - Recent Activities feed.
  - **Reservations Tab**:
    - Layout sub‑tab: Shift selector (mandatory), floor selector, seat grid (colors: green vacant, blue occupied, etc.). Seat actions bottom sheet (occupied/vacant). Multi‑shift seat model: seat data indexed by (seat_id, shift_id).
    - Members sub‑tab: list with filters, search. Member detail screen (tabs: Overview, Attendance (edit session duration allowed), Payments, Activity, Notes). Bulk operations (select mode).
    - Requests sub‑tab: Join Requests (aging indicator, payment confirmation before approval, seat picker with re‑validation), Seat Change Requests, Hold Requests.
    - Archive sub‑tab: read‑only historical members.
  - **Analytics Tab**: Revenue, expenses, profit, dues, charts (financial trend, breakdown), expenditure section with inline add expense, CSV export.
  - **Profile Tab**: Admin photo, libraries list, Business Settings (Seat Pricing, Shift Config, Membership Rules, Branding, QR Assets, Add‑on Services, Notifications, Exports), Account (Subscription, Announcements, Exports, Audit Log, Referral Settings, Support).

### Milestone 4: Member Home & Join Flow (P0)
- **Files:** `04_Database_Schema.json`, `07_Workflows.yaml`
- **Build screens:**
  - **Member Home** – My Library tab:
    - Profile setup card (collects nickname, ID proof). Inline collection during join if missing.
    - Membership cards (left border colour: green=active, amber=expiring, red=expired, purple=trial, yellow=hold). Card actions: Renew Plan, Request Seat Change, More (Hold Request, Exit Library – two‑tap confirm, blocked if dues).
    - Today's Attendance card (check‑in/out times, session duration, live timer for hourly plans).
    - Announcements section (last 3, unread orange border).
    - Floating Scan button (bottom center, orange).
  - **Explore Tab**:
    - Search bar (name/city/code), [Join with Code] button.
    - Library cards (free trial badge, verified tick, apply to join).
    - Library detail page (social links, emergency contact phone with call button).
  - **Join Flow** (5 steps):
    - Step 0: Profile check – missing fields collected inline.
    - Step 1: Existing member? (Yes/No) – if Yes, optional join date, plan, expiry. Hide trial.
    - Step 2: Shift & Plan – trial option shown only if available and member hasn't used trial. Two options: "Start with Free Trial" (skips payment) or "Pay Now".
    - Step 3: Add‑ons (if configured by admin).
    - Step 4: Payment (UPI deep‑link icons, screenshot + sender name required; cash no upload).
    - Step 5: Review & Submit – referral code field (optional).
    - On submit: join request created, admin notified.
  - **QR Scanner**:
    - Full‑screen camera view, orange scanning line.
    - Offline detection → yellow banner, saves to offline queue (max 500).
    - After 2 failed scans → [Contact Admin] button (no self‑serve override).
    - Post‑shift scan → treated as checkout for existing session (overtime included). Admin passively notified.
    - Double scan within 3 min → show "Already checked in at [time]" (not silent).

### Milestone 5: Member Analytics, Badges, Referrals (P1)
- **Files:** `04_Database_Schema.json`, `06_Business_Rules.csv`
- **Build screens:**
  - **Member Analytics Tab:**
    - Summary cards (days present/absent, total hours, attendance rate) with trend indicators (↑/↓ vs last period).
    - Streak card (per‑library selector), leaderboard (nickname only, duplicate suffix).
    - Badges (horizontal scroll, earned/unearned).
    - Bar chart (daily hours), calendar heatmap (tap day → popup).
    - [Export Attendance CSV] button.
  - **Badge system:** Compute badges automatically via scheduled job or trigger:
    - 7‑day streak, 30‑day streak, Early Bird (5 check‑ins before 7 AM), Night Owl (5 after 8 PM), Top of Week (rank #1), 100 Days Club, Consistent (90% monthly attendance).
    - Streak freezes on library‑closed days.
  - **Referral System:**
    - Member Profile → Refer a Friend: code (REF-XXXX-XXX), share button, referral count.
    - Join flow: optional referral code field.
    - On referral join: create referral record (status='pending').
    - Reward lock: new member must complete `referral_reward_min_checkins` or `referral_reward_min_days`.
    - When conditions met: credit free days to referrer. Notify both.
    - Admin can enable/disable rewards (Referral Settings). If disabled, admin gets notification to manually reward.

### Milestone 6: Subscription & Razorpay (Admin → Silence) (P0)
- **Files:** `08_Razorpay_Spec.md`
- **Build:**
  - Admin Profile → Subscription screen: display current plan (Starter/Basic/Pro/Trial), usage stats.
  - Upgrade/Downgrade flow: show plan cards, price, [Confirm Upgrade].
  - Call backend to create Razorpay subscription → open Razorpay Checkout.
  - Webhook handler (Supabase Edge Function or server) to update `users.subscription_status`.
  - Subscription state machine (active → grace → readonly → locked). Apply restrictions:
    - Grace period (7 days): full access, orange banner.
    - Read‑only (days 8‑30): view only, blocked actions show renew modal.
    - Locked (day 31+): single paywall screen.
  - Free trial: new admin gets 14‑day Pro trial. No Razorpay during trial.

### Milestone 7: Notifications & Offline Sync (P0)
- **Files:** `09_Notification_Payloads.json` (to be rebuilt), `12_Offline_Schema.sql`
- **Build:**
  - Setup Firebase project. Get FCM server key. Store in Supabase secrets.
  - When user logs in: save `fcm_token` to `users` table.
  - Send notifications via Supabase Edge Function or backend server. All 38 events from PRD Section 17.3.
  - Offline sync: implement SQLite/IndexedDB as per `12_Offline_Schema.sql`.
    - On scan with no internet: store in `offline_scan_queue`.
    - On internet restore: sync queue FIFO (max 500). Show toast.
    - On queue full: block new scans, show "Storage full – reconnect".
  - Read cache: refresh every 5 min when online. Store `cache_members` (max 200), `cache_attendance_today`, `cache_seat_grid`, `cache_member_memberships`, `cache_member_attendance`.

### Milestone 8: Polish & Edge Cases (P0/P1)
- **Files:** `11_Test_Scenarios.csv`
- **Implement all edge cases from PRD Section 18.2:**
  - Auto‑checkout sweep: 10 min after shift end, only for open sessions with no post‑shift scan.
  - Auto‑hold: after `expiry_grace_days`, seat status → hold. Configurable.
  - Duplicate phone: detect, reactivate old membership, merge history.
  - QR regeneration grace: old QR works for 7 days.
  - Admin manual check‑in: requires reason, flagged.
  - Discount audit log: store original price, discount amount, reason, admin name.
  - Two‑tap exit (no typing).
  - Force‑exit with dues: admin chooses write‑off or keep record.
  - Member transfer: preserve streak, history.
  - Scheduled closures: admin can set date ranges; streak freeze.
  - Critical action confirmations: type‑to‑confirm for destructive actions.

### Milestone 9: Testing (as per `11_Test_Scenarios.csv`)
- Run all 76 test scenarios. Each must pass before launch.
- Pay special attention to offline sync, multi‑shift seat occupancy, and subscription state transitions.

## Design System (from PRD)
- **Primary colour:** Orange `#E65C00`
- **Dark background (scanner):** `#0D1B2A`
- **Spacing:** Use 8dp grid.
- **Typography:** Sans‑serif (system default). Headings bold 15‑20px. Body 12‑14px.
- **Icons:** Feather or Material Icons. Use consistent set.
- **Bottom sheets:** For compose actions (announcements, seat actions, QR generation). Use modal dialogs for critical confirmations.
- **Empty states:** Show illustration + helpful text (never blank).

## Reference to Attached Files
- `01_Project_Brief.md` – high‑level overview
- `02_User_Stories.csv` – 60+ user stories with acceptance criteria
- `03_Screen_Flow_Diagram.mmd` – navigation map
- `04_Database_Schema.json` – complete Supabase schema
- `05_RLS_Rules.json` – row level security policies
- `06_Business_Rules.csv` – configurable rules and defaults
- `07_Workflows.yaml` – state machines for critical flows
- `08_Razorpay_Spec.md` – subscription integration
- `09_Notification_Payloads.json` – (to be rebuilt later)
- `10_Storage_Folders.txt` – Supabase Storage structure
- `11_Test_Scenarios.csv` – QA test cases
- `12_Offline_Schema.sql` – client‑side offline storage
- `14_Build_Order.md` – milestone sequence (this prompt already includes it)

## Final Instructions
- **Do NOT invent features** beyond what is in these files and the PRD v6.1.
- **Ask clarifying questions** if any step is ambiguous.
- **Prioritise** P0 features over P1. Do not implement V2 features (Hindi, partial payments, staff accounts).
- **Log all admin actions** in `audit_log` table as specified.
- **Test offline behaviour** thoroughly – it is a key differentiator.
- **Deliver a working Android + iOS app** with Supabase backend and Firebase notifications.

All RPC functions and Edge Functions defined in 17_API_Endpoints.md must be implemented as specified.

Begin building Milestone 1 now.