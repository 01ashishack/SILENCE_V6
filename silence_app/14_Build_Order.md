# SILENCE – Build Order & Milestones

## Overview
This document outlines the **phased development sequence** for SILENCE. Each milestone is self‑contained and should be completed, tested, and signed off before moving to the next.

**Total estimated developer days:** 25–30 days (single developer)  
**Total estimated calendar time:** 5–6 weeks with testing iterations.

---

## Milestone 1: Auth, Role Selection & Project Setup (2–3 days)

### Deliverables
- Supabase project created (PostgreSQL, Auth, Storage, Realtime)
- All database tables created (from `04_Database_Schema.json`)
- Row Level Security policies applied (from `05_RLS_Rules.json`)
- Auth screens (Login/Signup with email/password, Google, Apple)
- Role Selection screen (Library Owner / Student)
- Routing logic (no library → mandatory Library Setup modal)

### Acceptance Criteria
- [ ] User can sign up and log in
- [ ] Role saved to `users` table
- [ ] Admin with no library sees Library Setup Stage 1 modal on first dashboard open
- [ ] Admin with existing library goes directly to operational dashboard
- [ ] Member goes directly to Member Home

---

## Milestone 2: Admin Onboarding & Library Setup (3–4 days)

### Deliverables
- Complete Profile screen (Step 1 of setup)
- Library Setup – Stage 1: Basic Info (name, address, photos, amenities, rules)
- Library Setup – Stage 2: Floors, Sections, Seats (grid with pagination + search)
- Library Setup – Stage 3: Shifts & Plans (upsert model, overlap validation)
- Payment Setup screen (Cash toggle, UPI IDs with deep‑link icons)
- Admin Home setup card (progress bar, step completion tracking)
- Launch Library button → transition to operational dashboard

### Acceptance Criteria
- [ ] Admin can complete all 4 steps
- [ ] Library code generated (`SIL-XXXXXX`, unique)
- [ ] Seats created with correct floor/section/shift linkage
- [ ] Shifts saved with upsert (no orphaned memberships)
- [ ] Setup card hides after launch
- [ ] Operational dashboard visible (stats show zeros)

---

## Milestone 3: Admin Operational Dashboard & Reservations (5–7 days)

### Deliverables
- Admin Home (operational): header, library switcher, stats grid, attendance strip, action banner, quick actions, QR cards, recent activities
- QR modal: [Download PDF] [Share] [Regenerate] (type‑to‑confirm, 7‑day grace)
- Reservations – Layout sub‑tab: shift selector, floor selector, seat grid (colours), seat actions bottom sheet (occupied/vacant), multi‑shift support, manual check‑in from attendance strip
- Reservations – Members sub‑tab: member list, filters, search, member detail screen (overview, attendance with edit session, payments, activity, notes), bulk operations (select mode)
- Reservations – Requests sub‑tab: join requests (aging indicator, payment confirmation before approve, seat picker with re‑validation), seat change requests, hold requests
- Reservations – Archive sub‑tab: read‑only historical members

### Acceptance Criteria
- [ ] Stats grid updates in real time (use Supabase Realtime or periodic refresh)
- [ ] Admin can approve join request with seat assignment
- [ ] Admin can reject with reason
- [ ] Admin can manually check in a member (manual entry flagged)
- [ ] Admin can edit session duration (reason required, tagged "Admin Edited")
- [ ] Seat grid renders with pagination/search for 500+ seats
- [ ] QR regeneration works with 7‑day grace period
- [ ] Multi‑shift seat assignment works (same seat different shifts)

---

## Milestone 4: Member Home, Join Flow & QR Scanner (4–5 days)

### Deliverables
- Member Home – My Library tab: profile setup card (inline collection), membership cards (colour borders, actions: Renew, Seat Change, Hold, Exit – two‑tap), today's attendance card (live timer for hourly plans), announcements, floating scan button
- Explore tab: search (name/city/code), library cards, library detail (social links, emergency contact with call button)
- Join Flow (5 steps): profile check, existing member?, shift+plan (trial option), add‑ons, payment (UPI deep‑link icons + screenshot + sender name; cash no upload), review & submit
- QR Scanner: camera view, offline detection, double‑scan feedback, post‑shift scan as checkout, 2 failed scans → [Contact Admin] button
- Offline queue integration: store scans in SQLite/IndexedDB, sync on reconnect, queue limit 500 (block if full)

### Acceptance Criteria
- [ ] Member can find library and submit join request
- [ ] UPI payment shows admin's IDs with app icons (PhonePe, GPay, Paytm)
- [ ] Screenshot + sender name required for UPI
- [ ] Free trial option appears only if available and not used before
- [ ] Member can scan check‑in/out (online and offline)
- [ ] Offline queue persists across app restarts
- [ ] After 2 failed scans, only "Contact Admin" button appears (no self‑override)
- [ ] Post‑shift scan creates overtime (duration includes extra time) and notifies admin

---

## Milestone 5: Member Analytics, Badges & Referrals (3–4 days)

### Deliverables
- Member Analytics tab: summary cards with trend indicators, streak card (library selector), leaderboard (nickname only, duplicate suffix), badges (horizontal scroll), bar chart, calendar heatmap, [Export Attendance CSV]
- Badge system: compute badges via scheduled job (or on check‑in). Badges: 7‑day streak, 30‑day streak, early bird, night owl, top of week, 100 days club, consistent. Streak freeze on closed days.
- Referral system: member profile → referral code, share button; join flow optional referral code field; admin referral settings (enable/disable rewards, free days); reward lock (min check‑ins or days); credit free days when conditions met; admin notification for manual reward if disabled.

### Acceptance Criteria
- [ ] Member sees correct streak and leaderboard position
- [ ] Badges earned and displayed with earned date
- [ ] Member can export attendance CSV
- [ ] Referral code works, creates pending referral record
- [ ] Reward credited only after new member completes required check‑ins/days
- [ ] Admin can toggle referral rewards on/off

---

## Milestone 6: Subscription (Razorpay) & Admin Analytics (3–4 days)

### Deliverables
- Admin Profile → Subscription screen: current plan, usage stats, upgrade/downgrade flow
- Razorpay integration (backend webhook, Supabase Edge Function): create subscription, handle payment success/failure, update `users.subscription_status`
- Subscription state machine: active → grace (7 days, orange banner) → readonly (days 8‑30, blocked actions) → locked (day 31+, paywall)
- Free trial: new admin gets 14‑day Pro trial (no Razorpay), auto‑expiry to grace
- Admin Analytics tab: revenue, expenses, profit, dues cards, financial trend chart, revenue breakdown (donut), latest payments, attendance bar chart, occupancy chart, expenditure section (add expense with receipt photo, categories, recurring flag), CSV export

### Acceptance Criteria
- [ ] Admin can upgrade/downgrade via Razorpay (test mode)
- [ ] Webhook updates subscription status correctly
- [ ] Grace period shows orange banner, no functional restrictions
- [ ] Read‑only mode blocks sensitive actions, shows renew modal
- [ ] Locked mode shows only paywall
- [ ] Admin can add expenses with receipt photo
- [ ] Net Profit calculation updates instantly

---

## Milestone 7: Notifications, Offline Sync Polish & Admin Audit Log (2–3 days)

### Deliverables
- Push notifications: integrate Firebase Cloud Messaging, store `fcm_token`, implement all 38 notification events (from PRD Section 17.3) via Supabase Edge Function or backend
- Offline sync polish: implement sync metadata, cache refresh (every 5 min online), queue overflow handling, conflict resolution (newer timestamp wins)
- Admin audit log: log all critical actions (member approval, discount applied, seat removal, QR regeneration, etc.) with timestamp, admin ID, details. Display in Profile → Account → Audit Log (read‑only, 90‑day retention)
- Scheduled jobs: auto‑checkout sweep (10 min after shift end), auto‑hold (after expiry grace), expiry notifications (7 days and 1 day before), join request expiry (7 days, reminder day 5), trial expiry reminder (1 day before)

### Acceptance Criteria
- [ ] Admin and member receive push notifications for all events
- [ ] Offline queue syncs correctly, shows toast
- [ ] Read cache updates every 5 min when online
- [ ] Audit log shows all critical actions
- [ ] Scheduled jobs run correctly (use Supabase pg_cron or Edge Function cron)

---

## Milestone 8: Edge Cases, Testing & Launch Preparation (2–3 days)

### Deliverables
- Implement all remaining edge cases from PRD Section 18.2 and `11_Test_Scenarios.csv`
- Two‑tap exit (no typing), force‑exit with dues (write‑off/keep), duplicate phone detection (reactivate old membership), member transfer (preserve streak), scheduled closures, close today, library permanent closure (pre‑closure check)
- All date pickers → calendar grid (no scroll drums)
- All empty states (illustration + text)
- Critical action confirmations: type‑to‑confirm for destructive actions
- Performance testing: seat grid with 1000 seats, offline queue with 500 items, leaderboard with 500 members

### Acceptance Criteria
- [ ] All 76 test scenarios from `11_Test_Scenarios.csv` pass
- [ ] App runs on Android 8+ and iOS 13+ (test on low‑end device)
- [ ] Offline queue does not lose data
- [ ] No crashes or ANRs
- [ ] App ready for beta testing with 5 real libraries

---

## Milestone 9: Beta & Bug Fixes (1–2 weeks, iterative)

### Deliverables
- Deploy to TestFlight (iOS) and Internal Test Track (Android)
- Onboard 3–5 pilot libraries (free Pro trial)
- Collect feedback, fix critical bugs
- Optimise performance (seat grid rendering, sync speed)
- Finalise notification templates based on pilot feedback

### Acceptance Criteria
- [ ] Pilot libraries use app for 7 days without showstopper bugs
- [ ] Offline sync works in real‑world low‑internet conditions
- [ ] Admin satisfaction > 8/10
- [ ] All P0 test scenarios pass

---

## Milestone 10: Production Launch (1 day)

### Deliverables
- Submit to Google Play Store and Apple App Store
- Razorpay production keys configured
- Webhook URLs updated to production
- Monitoring (Supabase logs, Firebase Crashlytics) set up
- Launch marketing: WhatsApp broadcasts to 100+ libraries

### Acceptance Criteria
- [ ] App approved by both stores
- [ ] First 10 paying subscribers within 2 weeks
- [ ] No critical production crashes
- [ ] Support channels (email/WhatsApp) responsive

---

## Total Estimated Effort

| Milestone | Days |
|-----------|------|
| 1 – Auth & Setup | 2–3 |
| 2 – Admin Onboarding | 3–4 |
| 3 – Dashboard & Reservations | 5–7 |
| 4 – Member Join & Scanner | 4–5 |
| 5 – Analytics, Badges, Referrals | 3–4 |
| 6 – Subscription & Admin Analytics | 3–4 |
| 7 – Notifications, Offline, Audit | 2–3 |
| 8 – Edge Cases & Testing | 2–3 |
| 9 – Beta & Bug Fixes | 5–10 (parallel) |
| 10 – Production Launch | 1 |

**Total build (core):** 25–33 days  
**Total with beta:** 30–40 days

Ready for handoff.