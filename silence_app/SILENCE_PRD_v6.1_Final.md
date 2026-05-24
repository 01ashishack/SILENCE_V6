# SILENCE
## Library & Study Space Management Platform
### Product Requirements Document — Version 6.1 (Final Pre-Build)

| Field | Value |
|---|---|
| Version | 6.1 — Final Pre-Build |
| Platform | Android · iOS |
| Market | India — Tier 2/3 Cities |
| Date | May 2026 |
| Roles | Library Owner (Admin) · Student (Member) |
| Based on | v6.0 + 33 patches (DeepSeek v6 audit + Cross-AI missed fixes) |

> **Ready for developer handoff after:** Section 21 pricing is finalized by product owner.

---

# 1. Product Overview

Silence is a mobile-first platform for Indian study libraries. It replaces the fragmented combination of WhatsApp groups, physical attendance registers, and spreadsheets that most library owners use today with a single operational app — built specifically for Tier-2 and Tier-3 Indian cities where thousands of students prepare for competitive exams in shared study spaces.

## 1.1 Two Sides of the Same Platform

| Role | Who They Are | Primary Goal |
|---|---|---|
| Library Owner (Admin) | Runs a physical study space with numbered seats | Replace register and WhatsApp with one operational app |
| Student (Member) | Studies at one or more libraries daily for competitive exam prep | Track attendance, manage membership, see personal progress |

## 1.2 What Makes This Different

- **Dashboard-first design** — admin lands on operational control center, not a setup wizard
- **Multi-shift seat model** — same physical seat assigned to different members across shifts
- **Static, printable QR** — print it, laminate it, fix it on wall. Works forever.
- **Offline scan capability** — scans stored locally (up to 500), synced on reconnect
- **Streak + leaderboard** — motivates daily attendance
- **Library codes (SIL-4K9M2P)** — UPI-ID-style, shareable anywhere
- **Built for India** — rupee, UPI deep-links, cash receipts, exam categories, realistic pricing

## 1.3 What is IN Scope (V1)

- Admin: full library management, multi-library support, member management, multi-shift seat grid, QR codes, verified badge, audit log
- Admin: payments (UPI deep-links + cash + discount support), announcements, analytics with expenditure tracking, library profile, scheduled closures
- Admin: ratings & reviews, subscription management, add-ons management (with refundable deposits), referral notification system
- Member: membership card, QR attendance, personal analytics, streaks, leaderboard, badges, attendance CSV export
- Member: library discovery, join flow, free trial (admin-enabled), seat change requests, hold/pause requests, library support queries, referral tracking
- Shared: push notifications, offline attendance sync, auto-checkout sweep, member transfer between libraries (same admin)

## 1.4 What is OUT of Scope (V2)

- Study section — timer, planner, Pomodoro
- Group study rooms and collaborative features
- Staff sub-accounts and role hierarchy
- Waitlist with auto-notification
- Scheduled announcements and timetable
- **Hindi language** — architecture ready (language_code in DB, defaults to 'en'), translation in V2. **No language toggle shown in V1.**
- Analytics PDF export — CSV only in V1
- **Partial / installment payments** — full payment only in V1. *Clarification: "Discount" (admin reduces plan price) is V1. "Partial payment" (member pays in installments over time) is V2. These are different things.*
- Bulk member CSV import
- Guest pass / visitor management
- Spend limits per member
- Batch admission / coaching institute tie-up
- Personal study goals / leaderboard demotivation handling
- Tax-compliant GST export

---

# 2. App Architecture & Navigation

## 2.1 How the App Opens Every Time

| Step | Action |
|---|---|
| 1 | App opens → Orange splash screen: SILENCE logo + spinner |
| 2 | Check Supabase session → is user logged in? |
| 3 | No session → Auth Screen |
| 4 | Session exists → read role from DB |
| 5 | No role → Role Selection Screen |
| 6 | Role = admin → **check if library exists for this account** |
| 6a | **No library (new admin):** Library Setup Stage 1 opens as mandatory modal on top of Admin Home. Admin Home renders behind but is inaccessible until Stage 1 saves a library name. Prevents null-library crashes. |
| 6b | Library exists → Admin Home Dashboard |
| 7 | Role = member → Member Home |

## 2.2 Admin Navigation Structure

**4 permanent bottom tabs:**

| Tab | Icon | Contents |
|---|---|---|
| Home | House | Live operational dashboard |
| Reservations | Grid | Seat layout, members, requests, archive |
| Analytics | Chart | Revenue, occupancy, attendance, expenditure |
| Profile | Person | Settings, library management, billing, audit log |

**Stack screens (no bottom nav):**
Complete Profile → Library Setup (3 stages) → Payment Setup → Add Member wizard → Member Detail → Announcement Composer → Announcement History → Manage Queries → Notifications → Subscription → Library Profile → QR Asset modal → Seat Actions modal → Generate Seats modal → Renewal Screen → Add-on Management → Referral Settings → Verified Badge screen → Audit Log → Scheduled Closures → Hold Requests

## 2.3 Member Navigation Structure

**3 permanent bottom tabs:**

| Tab | Contents |
|---|---|
| Home | Membership cards, attendance status, announcements, scan button, explore |
| Analytics | Personal stats, streak, leaderboard, badges, charts |
| Profile | Personal profile, joined libraries, past libraries, referral, help, logout |

**Stack screens:** QR Scanner → Join Flow → Member Notifications → Library Query Composer

---

# 3. Auth & Onboarding

## 3.1 Auth Screen

| Element | Spec |
|---|---|
| Two tabs | Log In / Sign Up |
| Log In fields | Email + Password (show/hide) |
| Log In actions | [Log In] · [Continue with Google] · [Continue with Apple (iOS)] · Forgot Password |
| Sign Up fields | Full Name + Email + Password (strength indicator) + Confirm Password |
| Sign Up actions | [Create Account] · [Continue with Google] · [Continue with Apple] · Terms link |
| Verification at signup | **None.** App is usable without verification. Phone/email verification is optional — accessible from Profile tab. Required only for Verified Badge eligibility (admin phone OTP). |
| After signup | → Role Selection (no verification gate) |
| After Google/Apple | Check role exists → dashboard or Role Selection |
| Errors | Red inline text below field. Never popup. |

## 3.2 Role Selection Screen

| Element | Spec |
|---|---|
| Language selector | **Not shown in V1.** Hindi in V2. |
| Card 1 | Library Owner — Manage seats, members, payments and attendance |
| Card 2 | Student / Member — Track attendance, compete on leaderboard |
| Selection state | Orange border + radio fill + light orange tint |
| Warning | "You cannot change your role after selection." |
| Role conversion | Profile → Help → "Request Role Change" → support ticket. 24h response. No self-serve in V1. |
| Continue | Disabled until selection. Active text: "Continue as Library Owner / Student" |
| After | Role saved → Admin Home or Member Home |

## 3.3 Admin Onboarding — Dashboard-First

Admin → Admin Home always. **If no library exists: Library Setup Stage 1 opens as mandatory modal (Step 6a).** Once library name saved, modal closes. Setup progress card on dashboard guides remaining steps.

| Step | Title | Complete When |
|---|---|---|
| 1 | Admin Profile | Name + phone + gender + DOB all filled |
| 2 | Library Basic Details | At least one library name saved |
| 3 | Shift & Plans | At least one shift + payment method configured |
| 4 | Layout Setup | At least one floor/section/seat created |

Progress bar fills 25% per step. All 4 done → [Launch Library] button → marks library live → setup card hidden permanently.

**Profile Completion Score (0–100%):** Separate from launch checklist. Profile tab shows score. Includes: photo, phone verified, email verified, social links, library photos, about text, amenities. Motivates deeper setup without blocking launch.

## 3.4 Member Onboarding

Member → Member Home. Profile setup card if incomplete. Steps: (1) Details including **nickname** (required for leaderboard). (2) ID proof upload.

**Members can explore before completing profile.** Missing fields collected inline during join flow (Section 14 Step 0). No blocking.

---

# 4. Admin Home — Operational Dashboard

## 4.1 Header

| Element | Spec |
|---|---|
| Background | Solid orange #E65C00, large rounded bottom corners (28px) |
| Left | Library photo (44px circle) → library name (bold white 15px) → chevron-down → address (white 75% opacity 11px) |
| Right | Date pill + Bell icon (red unread badge) |
| Library switcher | Dropdown: All Libraries (checkmark on current) → individual libraries → + Add Library. "All Libraries" valid selection for aggregate stats. |
| Greeting | Good [time], [Admin name] 👋 white 20px bold. Subtext: "Here's what's happening today." |

## 4.2 Setup Mode

Setup card at top. Stats show zeros. White card, orange left accent border, step rows with numbered circles (gray → green checkmark), progress bar, Continue Setup button, Launch Library button (when all 4 done).

## 4.3 Operational Mode

**Library Photo Carousel:** Up to 4 photos, horizontal scroll, pagination dots.

**Library Code Card:** SIL-4K9M2P in orange monospace. [Share] [Copy] buttons.

**Stats Grid:**

| Card | Shows | Tap → |
|---|---|---|
| Revenue This Month | Confirmed + Pending + Today's | Analytics tab |
| Active Today | Scanned today / total | Members → Active filter |
| Expired | Past expiry | Members → Expired filter |
| New Joinings | This month + today | Members → All |
| Expiring Soon | Within 7 days | Members → Expiring filter |
| Live Occupancy | Donut: Occupied % + legend | Reservations → Layout |

Layout: Full-width Revenue → 2×2 grid → full-width Occupancy donut.

**All Libraries aggregation:**
- Revenue, Expenses = sum
- Net Profit = Total Revenue − Total Expenses
- Attendance = sum of daily scans across all libraries
- Occupancy = weighted average by seat count
- Leaderboard not shown in All Libraries view

**Today's Attendance Strip:**
Horizontal scroll of member photos with colored rings. Green = checked in. Red = checked out. Red overlay = expired scan.

**Shift filter above strip:** [All Shifts] [Morning] [Evening] ... (only existing shifts shown). Active chip = orange. Default = All Shifts. Counter: "Present today: X / Total: Y."

Below each photo: name (truncated), last scan time, seat number. View All link. Empty state: "No check-ins yet today."

**Action Required Banner:** Amber card — payment proofs pending + join requests pending. Tappable rows. Hidden when empty.

**Quick Actions Row:** [Add Member] [Announce] [Joining QR] [Attendance QR]

**Close Today / Scheduled Closures:**
Secondary button in Quick Actions (or overflow):
- **Close Today:** Confirmation bottom sheet → "Mark [Library] closed today?" → members notified → streak frozen → scans accepted but day flagged. Button changes to [Reopen Today]. Amber banner on Home. Auto-resets midnight.
- **Scheduled Closures:** Business Settings → Membership Rules → Scheduled Closures. Add single day or date range (e.g., Diwali Oct 20-24). Name/reason field. Notify members toggle. During closure: streak frozen, QR shows "Library closed today ([reason])". Closure calendar shows upcoming + past closures. Admin can delete upcoming ones.

**QR Code Section:** Two QR cards — Joining QR and Attendance QR. Each: [Download as PDF] [Share] buttons. Library code + Copy below.

**Recent Activities Feed:** Last 10 events, reverse chronological. View All link.

## 4.4 QR Code Modal

| Element | Spec |
|---|---|
| Design | Overlay modal, × close top right |
| QR display | 220×220px, orange corner brackets |
| Library code | Below QR: code in orange + copy icon |
| Actions | [Download as PDF] [Share] [Regenerate] |
| Tabs | Joining QR \| Attendance QR |
| Joining QR footer | "Anyone who scans can submit a join request." |
| Attendance QR footer | "Permanent static code — print, laminate, fix on wall. Server validates membership on each scan. Regenerate only if code compromised." |

**Regenerate — Critical Action:**
Bottom sheet: "⚠️ Regenerate QR?" → Old QR continues working for **7 days** (grace period). Type "REGENERATE" → [Cancel] [Confirm Regeneration].

**QR version tracking:** Each QR has integer version. Offline scans store qr_version at scan time. Sync rules in Section 20.

---

# 5. Admin Setup Screens

## 5.1 Complete Profile

| Field | Spec |
|---|---|
| Photo | Tap → [Take Photo (front camera)] or [Choose from Gallery]. Optional. |
| Fields | Full Name (req) + Gender (radio) + Date of Birth (calendar picker) + Phone (+91) + Email (pre-filled) |
| Date pickers | All date pickers across entire app use calendar grid view — not scroll drum. |
| Pre-fill | All saved values pre-filled on return |
| Save | → success toast → Step 1 marked complete |

**Phone/Email Verification (optional):**
From Profile tab: "Verify Phone" or "Verify Email" → OTP. Adds verified tick + increases profile completion score. Required for Verified Badge eligibility (admin phone only).

## 5.2 Library Setup — 3 Stages

### Stage 1 — Basic Info

| Field | Spec |
|---|---|
| Library Name | Required |
| Address | Street + City (req) + State dropdown + PIN |
| Photos | Up to 4 from gallery. Permanent cloud URLs. |
| Amenities | Multi-select: AC, WiFi, Lockers, Drinking Water, CCTV, Sections, Parking, Washroom |
| Rules | Optional text area |
| Library code | Auto-generated: SIL-[6-char alphanumeric]. Uniqueness check with retry. City prefix removed (collision risk eliminated). Shown after generation. |
| Social links | **Not here — moved to Library Profile → Social Links.** |

### Stage 2 — Floors, Sections & Seats

| Element | Spec |
|---|---|
| Floor tabs | Scrollable pills. Long press OR three-dot menu → Rename/Delete. |
| Add Floor | Orange dashed button → bottom sheet |
| Sections | Name + tag pill (Boys/Girls/General/Premium) + three-dot menu |
| Seat generation | Bulk (prefix + range) or Single. Preview first 6 labels. |
| Section assignment | Toggle: assign to section or leave on floor |
| Seat grid performance | Virtualized rendering (FlashList). Paginated in groups of 30: [← Prev 30] [Next 30 →]. Search bar (see Section 6.1 for spec). [List View] toggle. |

### Stage 3 — Shifts & Plans *(Canonical shift screen)*

| Element | Spec |
|---|---|
| Shift card fields | Name + Start Time + End Time + Monthly ₹ + 3-Month ₹ + 6-Month ₹ + Trial Days (0 = none) |
| Add/Remove | [+ Add New Shift] · × to remove (if >1 shift) |
| Shift overlap | Yellow warning if times overlap. Admin must explicitly confirm. |
| Save behavior | **Upsert + soft-delete** — existing shifts updated by shift_id, new ones inserted, removed shifts marked `is_archived = true`. No destructive delete. Foreign key integrity preserved. Historical member records remain intact. |
| Save & Finish | Success alert → Admin Home with Steps 2+3 complete |

**This is the canonical shift screen.** Entry points: Library Setup Stage 3 · Business Settings → Shift Config · Library Profile → Timings & Shifts. All three open the same component.

## 5.3 Payment Setup

| Element | Spec |
|---|---|
| Cash toggle | Accept Cash Payments — ON by default |
| UPI IDs | Text input + [Add]. Multiple IDs as removable rows. |
| UPI deep-link icons | Below each UPI ID: PhonePe, Google Pay, Paytm, Amazon Pay icons based on UPI handle suffix (@ybl=PhonePe, @okicici=GPay, @paytm=Paytm). Member tapping any icon → deep-linked to that app with UPI ID pre-filled. |
| Validation | At least one method active |

---

# 6. Reservations Tab

4 sub-tabs: **Layout · Members · Requests · Archive**

## 6.1 Layout Sub-tab

**⚠️ MULTI-SHIFT MODEL:** Seat grid indexed by `(seat_id, shift_id)`. Same physical seat → different members in different shifts. Standard Indian library operation.

| Element | Spec |
|---|---|
| Header | **Shift selector (mandatory, left)** + Floor selector + Filter + Search |
| Shift selector | Re-renders entire grid for chosen shift. "All Shifts" = merged view (seat occupied in ANY shift = Occupied). |
| Status filter chips | All · Vacant · Occupied · Expiring Soon · [Section names] |
| Seat grid | Virtualized + paginated (30/page). Search bar above. [List View] toggle. |
| Seat colors | 🟢 Vacant · 🔵 Occupied · 🔵+🟡 Expiring · 🔵+🔴 Fee Pending · 🟠 Hold · ⚪+🔧 Maintenance |
| Seat size | 52×44px, border-radius 8px, label 10px white |
| Legend | Bottom of page |

**Seat search specification:**
Seats stored with: `library_id, floor_id, section_id, seat_label, shift_id, member_id, status`. Composite DB index on `(library_id, seat_label)`. "Jump to G-A-124" → DB query or in-memory binary search on offline cache → highlights seat + auto-switches floor if needed. If occupied: shows member name in search result.

**Auto-checkout Sweep + Overtime (unified rule):**
- **One check-in = one session.** Session ends on checkout scan or auto-checkout. Never split.
- **Auto-checkout:** Fires 10 minutes after shift end time — but ONLY for members who have NOT scanned after shift end. If member scans (checkout) within those 10 minutes, auto-checkout does NOT fire for them.
- **Post-shift scan:** If member has an open session and scans after shift end: treated as checkout for existing session. Actual scan time = checkout time. Overtime included in duration. Admin gets passive notification: "[Member] checked out [X] min after [Shift] ended." No action needed.
- **Result:** Every check-in has exactly one session. No duplicate sessions. No confusion.

**Manual Check-in by Admin:**
On Today's Attendance strip (Home): tap absent member → [Mark Present] with timestamp picker. From Member Detail → Attendance tab → [+ Add Manual Entry]. All manual entries flagged as "Manual Entry" in analytics.

**Seat Actions — Occupied:**

| Action | Behavior |
|---|---|
| View Member Details | → Member Detail |
| Mark as Hold | Seat → amber. Member notified. |
| Reassign Seat | Seat picker (same shift, vacant only) → confirm |
| Renew Membership | → Renewal Screen (Section 6.5) |
| Remove from Seat | Critical action: reason field + type "REMOVE" + [Cancel] [Confirm Remove]. Member notified. Dues check: if dues > 0, show write-off/keep warning (Section 12.3 force-exit spec). |

**Seat Actions — Vacant:**

| Action | Behavior |
|---|---|
| Assign Member | Member search → assign for selected shift |
| Reserve Seat | Hold for specific member |
| Mark for Maintenance | Gray+wrench. Issue description. Auto-notify admin if >7 days. |
| Delete Seat | Critical action: type "DELETE" + confirm |

## 6.2 Members Sub-tab

**Filter chips:** All · Active · Pending · Trial · Expired · Hold · Exp. Soon · Missing ID

**Member cards:** Photo + name + status + seat pill + shift + expiry/dues info + three-dot menu.

**Select Mode (Bulk):**
Three-dot menu → "Select Members" → checkboxes appear. Bottom action bar:
- [Send Announcement] → Announcement Composer pre-filled with selected recipients
- [Export Selected] → CSV
- [Cancel]

**Member Detail Screen:**

| Element | Spec |
|---|---|
| Header | Photo (64px, orange ring) + name + status badge + Member ID + join date |
| Info grid | Seat · Shift · Plan · Expires |
| Tabs | Overview · Attendance · Payments · Activity · Notes |
| Overview | Membership + Attendance Summary + Payment Summary |
| Attendance tab | Calendar (present/absent). Tap day → popup: check-in time, checkout time, duration, session type (Normal/Manual/Auto-Checkout/Incomplete). [Edit Duration] button (admin only) — reason required. Edited sessions tagged "Admin Edited". [+ Add Manual Entry]. |
| Payments tab | Date + amount + method + status (Confirmed/Pending/Rejected/Disputed/Written Off) + plan period (from–to) + Ref ID (last 6 chars of payment_id) + discount info if applied ("₹700 plan → ₹500 charged — ₹200 discount. Reason: [X]. By [Admin].") |
| Activity tab | Timeline of all events |
| Notes tab | Admin private notes. Not visible to member. |
| Three-dot menu | [Transfer to Another Library] (if admin owns 2+ libraries) — see Section 6.6 |
| Discount field | [Apply Discount] toggle → enter amount charged + optional reason. Stored in payment record. |
| Edit button | Pencil top right → all fields pre-filled |

**Audit trail for discounts:**
Every discounted payment record stores: original price, charged amount, discount value, reason, admin name, timestamp. Viewable in Payments tab and Audit Log.

## 6.3 Requests Sub-tab

Sub-tabs: **[Join Requests] [Seat Changes] [Hold Requests]**

**Filter chips on Join Requests:** All · New (today) · Aging (5+ days) · Expiring Today

**Sort order:** Oldest at top (most urgent first).

**Join Request card:**

| Element | Spec |
|---|---|
| Content | Photo + name + request time + shift + plan + payment method + ID thumbnails |
| Aging indicator | Gray (1-4d) → amber (5-6d) → red (7d + "Expires today") |
| Payment proof | UPI screenshot thumbnail + sender name (member-entered) + amount. [View Full Image]. |
| Payment actions | [Confirm Payment] [Reject Payment] — payment confirmed/rejected BEFORE membership approve/reject unlocks |
| Payment rejection reason | Required: Amount not received / Screenshot unreadable / Wrong amount / Other. Member sees this reason. |
| Approve flow | [Approve Membership] → shift selector → seat picker (vacant only, for chosen shift) → **server re-validates seat vacancy at final confirm tap** → if taken: "Seat just assigned, pick another" → dialog → membership created → member notified |
| Reject flow | Reason picker → member notified |

**Day-6 notification to admin:** "[Name]'s join request expires tomorrow."
**Day-5 notification to member:** "Your application at [Library] will expire in 2 days. Contact library or reapply."

**Seat Change Request card:**
Member photo + name + current seat + reason + preferred section. [Assign New Seat] or [No Seats Available].

**Hold Request card:**
Member photo + name + reason + requested dates. [Approve Hold] [Reject Hold]. On approval: seat → amber, expiry extended by hold duration, member notified.

## 6.4 Archive Sub-tab

Faded profile rows. Name + "Exited on [date]" + "Member since [date]" + duration pill. Tap → read-only full history. Search by name.

## 6.5 Renewal Screen *(Full spec)*

**Entry points:** Seat Actions (Occupied) → Renew · Member Detail → Renew · Member card → [Renew Plan] · Expiry notification tap

**Header:** "Renew Membership — [Name]" (admin) / "Renew Your Plan" (member)

**Current summary (read-only):** Plan, shift, seat, expiry, paid amount, outstanding dues.

**Fields:**

| Field | Spec |
|---|---|
| Shift | Dropdown, pre-filled. Changeable. If changed, seat may change. |
| Plan Duration | Monthly / 3-Month / 6-Month pills with prices |
| Start Date | Radio: "Continue from expiry: [date]" (default) OR "Start from today: [date]" (auto-selected if already expired). Calendar picker for custom date. |
| Seat | Read-only if shift unchanged. Seat picker if shift changed (vacant only, new shift). |
| Discount | [Apply Discount] toggle → enter charged amount + reason. Stored in payment record. |
| Amount | Pre-filled with plan/discounted price. Admin editable. Member read-only. |
| Payment Method | Cash or UPI |

**Renewal prompt (admin view) — expired member:**

| Scenario | Admin sees |
|---|---|
| Expired ≤ 3 days | Default: "Continue from expiry." No special prompt. |
| Expired 4+ days + absent those days | Yellow banner: "Member absent [X] days since expiry." Prominent buttons: [From Expiry: date] [From Today: date] + calendar picker. |

**Admin renewal options:**
- [Renew Silently] — activates immediately. Member sees updated card. Suitable for in-person cash payment.
- [Notify Member First] — push to member: "Your library prepared a renewal for [Plan] at [Price]. [Confirm] [Decline] — 24h." If no response: auto-confirm. If admin already confirmed, any pending member self-renewal auto-cancelled: "Your library renewed your plan."

**Seat stays assigned during entire renewal flow.**

**On save:** New membership record. Old marked "Renewed." Member notified: "Plan renewed. Valid until [date]. Seat [X]. Ref: [ID]."

## 6.6 Member Transfer Between Libraries *(Same Admin)*

**Entry:** Member Detail → three-dot menu → [Transfer to Another Library] (visible only if admin owns 2+ libraries)

**Transfer bottom sheet:**
- Destination library dropdown (admin's other libraries)
- New shift dropdown (destination library shifts)
- New seat picker (vacant seats in destination, chosen shift)
- Transfer date (calendar picker, default: today)
- Notify member toggle (default: ON)

**On confirm:**
- Current membership at Library A → status: "Transferred" (not "Exited")
- New membership created at Library B, same member_id
- Seat A freed, Seat B assigned
- Full history (attendance, payments, badges) preserved under same member_id
- Streak continues unbroken
- Both libraries' activity feeds show transfer event
- Member notified: "Your membership has been transferred from [Library A] to [Library B]. Seat: [X]. Shift: [Y]."

## 6.7 Add-ons Management Screen

**Entry:** Business Settings → Add-on Services

Each add-on:
- Name (e.g., Locker, AC Premium, Charging Point)
- Price: One-time OR Monthly recurring
- Refundable Deposit toggle → enter deposit amount. Tracked separately from revenue. On member exit: "Pending Refund" in payment records. Admin marks refunded manually.
- Max available count (e.g., 20 lockers)
- Active/Inactive toggle

**Revenue:** Add-on revenue separate line in Analytics. Deposits shown as liability, not revenue.

---

# 7. Add Member Flow (4-step wizard)

| Step | Fields | Required |
|---|---|---|
| 1 — Personal Info | Full name, phone, email, gender, DOB, address, exam category. Photo: [Take Photo (front)] or [Choose from Gallery]. | Name + phone |
| 2 — ID Verification | [Take Photo (rear camera)] for physical ID or [Choose from Gallery] for soft copy. Type: Aadhaar/PAN/Voter ID/Driving License. Admin-verified = "Verified by Admin" in DB. [Skip — Add Later] creates "Missing ID" flag. | 1 doc or skip |
| 3 — Plan & Seat | Shift selector. Plan duration. Price. [Apply Discount] toggle → charged amount + reason. Seat picker (cinema grid, vacant for chosen shift). Free trial NOT offered here — trial is member-initiated from their own join flow. | Shift + plan |
| 4 — Payment | Cash or UPI. Amount (pre-filled). UPI: admin's IDs + deep-link icons. [Mark as Received] for cash. | Method |

**Summary screen** before save: full review. On save: membership created, seat marked occupied for shift, member notified.

**Cash payment confirmation → member notification:** "₹[Amount] cash payment recorded at [Library]. [Start–End]. Seat [X]. Ref: [ID]." Serves as receipt.

---

# 8. Announcements & Member Queries

## 8.1 Announcement Composer *(Bottom sheet only)*

Triggered from: Admin Home → [Announce] · Announcement History → [+ New Announcement]

Contents: Recipient selector (All Members / Individual / Filtered Group) · Filtered Group options (Expiring 7d, Expired, On Hold, Payment Pending, Absent Today, Absent 3+ Days, per shift, per exam category) · Filter preview · Title (80 chars max) · Message (500 chars max) · [Send to X members].

**Pre-send confirmation bottom sheet:** "Sending to X members." Avatar row (first 5 + "and X others"). Message preview. [Cancel] [Send Now].

**"Read" definition:** Marked read when member taps announcement (from notification OR Home section). Push notification open alone does NOT count.

**Announcement History** is a SEPARATE screen. Profile tab → Announcements. Reverse chronological list. Each row: title + recipients + sent time + read count (X/Y). Tap → read-only view.

## 8.2 Member Queries

One-directional: member → admin. Admin replies. Member can also tap [Contact Library] from dispute or scan-fail scenarios. Admin replies from Profile tab → Manage Queries.

## 8.3 Payment Disputes

When admin rejects UPI proof, must select reason: Amount not received / Screenshot unreadable / Wrong amount / Other. Member sees reason on application card. Member options: [Re-upload Screenshot] or [Contact Library] (pre-filled query).

Admin sees "Disputed" badge on application in Requests sub-tab. Outcome: admin marks Confirmed (accept) or Unresolved (close without action).

---

# 9. Analytics Tab

| Element | Spec |
|---|---|
| Header | Library switcher pill + Analytics title |
| Date filter | Today · 7 Days · This Month · Custom (calendar picker) |
| Revenue cards | Today + Monthly. Cash/UPI split + paid count. |
| Expenditure + Profit | Monthly Expenses + Net Profit (green/red) |
| Dues card | Total dues + pending count |
| Annual view | Annual Revenue + Expenses + Net Profit |
| Financial Trend | Line chart: Revenue (orange) vs Expenses (purple dashed) |
| Revenue Breakdown | Donut: Cash vs UPI vs Add-ons |
| Latest Payments | Recent confirmed and pending |
| Attendance chart | Bar chart — daily check-in counts |
| Occupancy chart | Shift-wise — horizontal bars |
| Expenditure section | [+ Add Expense] inline button in section header + breakdown + history |
| Export | [Export CSV] — selected period. **CSV only in V1.** |

## 9.1 Add Expenditure

[+ Add Expense] inline button in Expenditure section header. NOT a floating button.

Bottom sheet: Library selector (if All Libraries view) + Amount + Category + Date (calendar picker, default today) + Note + [Attach Receipt Photo].

**Categories:** Rent · Electricity · Internet · Water · Maintenance/Repair · Salary · Supplies · Generator/Diesel · Cleaning · Security · Taxes (GST/Professional) · Miscellaneous.

**Recurring flag:** "Mark as recurring monthly" → pre-fills next month. Admin edits as needed.

History: date + category pill + amount + note + receipt icon + delete (soft delete, confirmation required).

---

# 10. Library Profile & Customization

## 10.1 Library Profile Screen

Cover photo (full-width) · Library identity (name + verified tick if earned) · Stats (rating + member count) · Quick actions (Share Profile / Preview as Member / QR Codes / Customise) · Profile Completion bar · About · Stats row · Settings list · Ratings & Reviews · Recent Visitors.

**Social Links section (shown to members):**
Icons for Instagram, YouTube, Facebook, WhatsApp, Website (from admin config). Visible on public profile and in member's Profile tab under joined library.

**Emergency Contact section (visible to members):**
Phone icon + admin's public contact number → tap to call native dialer. WhatsApp icon if configured. "For urgent queries, call directly. For non-urgent: use the Queries feature." Admin configures public contact number in Customise → Library Information (separate from personal account phone, defaults to account phone if not set).

**Verified Badge:** Shown if earned. Orange ✓ tick.

## 10.2 Customise Library Profile

Sections: Cover Photo & Gallery · Library Information (includes Public Contact Number) · About Library · Amenities · Timings & Shifts (→ canonical shift screen) · Membership Plans · Rules & Guidelines · How to Join · Social Links · Add-on Services.

## 10.3 Verified Badge System

**Criteria (ALL must be met):**
1. Admin profile 100% complete: name + photo + phone + gender + DOB filled **AND phone OTP-verified**
2. Library profile 80%+ complete: name + at least 2 photos + about text (50+ chars) + at least 3 amenities + rules text
3. Library active (launched) for at least 30 consecutive days
4. At least **20 confirmed payments from at least 10 distinct members** (unique member_ids)
5. At least 10 member check-ins recorded
6. No open unresolved dispute flags
7. No active write-off dues within last 30 days *(relaxed from "no write-offs ever")*

**System checks criteria automatically.** When all met: push notification → "🎖️ [Library Name] earned the Verified badge!"

**What it does:** Orange ✓ on library name in Explore, profile header, member's card. Verified libraries rank higher in Explore. Admin can share "Verified Library" status.

**Badge hidden (not deleted)** if library closed or subscription lapses 60+ days. Restored on re-activation.

## 10.4 Ratings & Reviews

Same as v5. Admin can reply to reviews. Paginated.

## 10.5 Library Permanent Closure

Entry: Library Profile → three-dot → "Close Library Permanently"

**Step 0 — Pre-closure check (auto):**
System checks and shows admin: "X members on trial, Y pending applications, Z active memberships. All will be notified. Pending requests auto-rejected. Active members lose remaining days (no automatic refund)."
[Notify All & Continue] [Cancel]

**Step 1 — Confirmation:**
Type library name → [Confirm Permanent Closure]

**On confirm:**
- All members notified: "[Library] has permanently closed. Your history is preserved."
- Pending requests auto-rejected: "Library has closed."
- Library status = Closed (shown on Explore as "Permanently Closed", gray, not joinable)
- Attendance QR → "This library is closed."
- Admin: read-only mode.

**Data retention:** Member PII: 12 months → anonymized. Library structure: 3 years.

**Account deletion:** Profile → Account → Delete Account. Only if all libraries closed. Irreversible. Deletes PII, anonymizes financial records.

---

# 11. Admin Profile Tab

| Element | Spec |
|---|---|
| Header | Admin photo (camera or gallery) + name + "Owner · [Library]" + library count pill + subscription pill |
| System status | Green = active + no sync errors. Amber = grace period OR offline queue >24h. Red = Full Lock OR Supabase unreachable >5min. Tap → status detail. |
| Your Libraries | One card per library. Tap → Library Profile. |
| Manage Libraries | Search + list + [+ Add New Library] |
| Business Settings | Seat Pricing · Shift Config · Membership Rules · Branding · QR Assets · Add-on Services · Notifications · Exports |
| Account | Edit Profile · Subscription · Announcements · Exports & Reports · **Audit Log** · Referral Settings · Support & Help · About & Legal |
| Logout | Red text + confirmation |

## 11.1 Business Settings

**Membership Rules (expanded):**
- Membership Durations · Grace Periods · Late Payment Rules · Attendance Rules · Renewal Rules · Auto-Expiry
- **Allow expired member check-in:** Toggle (default ON). When OFF: expired scan → error to member + admin notification.
- **Expiry grace period before auto-hold:** Integer, default 3 days, min 1, max 14. "Days before expired seat auto-holds."
- **Max discount allowed (%):** Integer, default 100 (no restriction). Admin can set 50% etc.
- **Hold rules:** Max hold duration (days, default 30). Max holds per membership period (default 2).
- **Scheduled Closures:** Date-range closure management (see Section 4.3).

**Free Trial toggle (per shift in Shift Config):**
- Admin enables trial per shift. Sets Trial Days.
- Library's Explore card shows "Free Trial Available" badge.
- Actual trial/pay choice in Join Flow Step 2.
- System tracks `trial_used` per member-library pair. Once used, trial option hidden forever for that member at that library (even after rejoin).

**Exports:** CSV only (Members, Attendance, Payments, Revenue, Occupancy). PDF/Excel = V2.

**Popular tag:** Max ONE per shift. If admin marks multiple, system ignores and auto-shows "Most Chosen" badge based on actual data.

## 11.2 Subscription Screen

**Subscription = Silence app ↔ Admin relationship (Razorpay). Completely separate from membership (library ↔ member, cash/UPI).**

**Three plans in V1:**

| Plan | Monthly | Libraries | Members | Key Features |
|---|---|---|---|---|
| Starter | ₹[TBD] | 1 | Up to 30 | Full attendance + QR, basic analytics, CSV export |
| Basic | ₹[TBD] | 1 | Up to 150 | All Starter + expenditure tracking, ratings & reviews |
| Pro | ₹[TBD] | Up to 5 | Unlimited | All Basic + multi-library, branding, verified badge eligibility, priority support |

> ⚠️ **Owner action needed:** Fill prices before build. See Section 21 for recommendation.

**Free Trial:** 14-day Pro trial. No payment required. One time per account. Trial status: "Pro Trial — X days remaining."

**Upgrade/Downgrade flow:** Both plans shown side by side. Current plan badged. Upgrade: price + billing date + [Confirm]. Downgrade: features lost warning + extra libraries archived if downgrading. Cancel: data retained 90 days post Full Lock.

## 11.3 Referral Settings

**Entry:** Profile tab → Account → Referral Settings

**Admin controls:**
- Enable Referral Rewards toggle (ON/OFF)
- If ON: reward = "Free Days" (admin sets number, e.g., 3) for both referrer and new joiner
- If OFF: tracking still active. Admin gets notification when referral join happens and can manually reward.

**Referral reward anti-abuse lock:**
Reward held as "Pending" until new member completes **5 check-ins** OR has been a member for **7 days** — whichever comes first. If member exits before meeting condition, reward cancelled and referrer notified.

Admin can manually override: Member Detail → [Release Referral Reward].

**Code generation:** `REF-[first 4 chars of member_id]-[3 random alphanumeric]`. Uniqueness verified.

**Deep-link attribution:** Join link with `?ref=CODE` auto-fills referral field in Join Flow Step 5. Source tracked as `referral_link` or `manual_entry`. Admin Analytics: "X referrals via link, Y via manual."

**Member view (Profile → Refer a Friend):** Referral code + Share button + "You've referred X members" + pending/credited rewards.

---

# 12. Member Home Screen

## 12.1 Header

Orange #E65C00, SILENCE logo (white), bell icon (red badge), greeting.

## 12.2 Sub-tabs

My Library (default) · Explore

## 12.3 My Library Tab

**Profile setup card:** When profile incomplete. Steps: (1) Details + nickname. (2) ID upload. Hides permanently when both done.

**Membership cards:**

Left border color: green=active, amber=expiring, red=expired, purple=trial, yellow=hold.

Contents:
- Library name + Verified ✓ (if library earned badge) + status badge
- Seat + Shift
- Plan type + amount + discount note ("₹500 — ₹200 discount applied" if discounted)
- Expiry progress bar + countdown
- Dues banner if pending: "₹[X] pending · [Pay Now]"
- Trial banner if in trial: "Trial ends in X days · [Pay to Continue]"

**Card action buttons:** [Renew Plan] → Renewal Screen · [Request Seat Change] → bottom sheet · [More ▼]

**More dropdown:**
- **[Request Hold / Pause]** → Hold Request bottom sheet:
  - Reason (required, 150 chars max)
  - Start date (calendar, min tomorrow, max 7 days from now)
  - End date (calendar, max 30 days from start, min 3 days)
  - Helper: "Your seat stays reserved. Billing pauses. Expiry extends by hold duration."
  - [Cancel] [Submit Hold Request]
  - After submit: button changes to "Hold Requested ⏳" (amber, non-tappable)

- **Exit Library** → Dues check first → if dues > 0: block with "Clear dues before exiting." If no dues:
  - **Step 1:** Bottom sheet: "Exit [Library Name]? Seat [X] freed. [X] remaining days lost. History preserved." [Cancel] [Yes, I Want to Exit →]
  - **Step 2 (1 second delay, fat-finger protection):** Red sheet: "This cannot be undone. Seat freed immediately." [Cancel] [Confirm Exit] (red)

**Seat Change Request bottom sheet:**
Current seat (read-only) · Reason (required, 200 chars) · Preferred section (optional dropdown) · [Cancel] [Submit Request]. After submit: button → "Seat Change Requested ⏳".

**Today's Attendance card:** Check-in + check-out times + duration. [Scan to Check In].

**Announcements:** Last 3. Unread = orange left border. Tap → read → marked as read.

**Floating Scan button:** 64px orange circle, bottom center. My Library tab only.

## 12.4 Explore Tab

Search bar (name/city/code) · [Join with Code] button · Library cards.

Library cards show: Free Trial badge (if admin enabled) + Verified ✓ (if earned) + [Apply to Join] or "Already a Member ✓".

Library detail page shows social links icons.

---

# 13. QR Scanner

| Element | Spec |
|---|---|
| Background | #0D1B2A full dark |
| Viewfinder | 260×260px, white L-brackets, orange scanning line animation |
| Offline banner | Yellow: "Offline. Scan will be saved and synced." |

**On Joining QR scan:** Already member → check-in prompt. Not member → Join Flow.

**On Attendance QR scan:**
1. Not a member of this library → error card: "This QR belongs to **[Library Name]**. You are not a member here. [Scan My Library's QR] [Join This Library]"
2. Expired scan + admin toggle OFF → error: "Membership expired. Renew to enter."
3. No scan today → check-in. Checked in, no checkout → checkout. Both done → "Session complete."

**Post-shift scan (overtime):** Treated as checkout for existing open session. Duration includes overtime. Admin passive notification. No second session created.

**Success cards:**
- Check-in: green checkmark + "Checked In! [time]." Auto-dismiss 3s online. [Done] button offline.
- Checkout: "Checked Out! [duration]."

**Double scan (within 3 min):** Show same success card: "Already checked in at [time]." Not silently ignored.

**After 2 failed scans:** [Contact Admin — Request Manual Check-in] button → sends admin push notification: "[Member] couldn't scan, requesting manual check-in at [time]." + [Report via Queries] option. No self-serve override.

**Offline storage:** Record = {library_id, member_id, timestamp, qr_version, shift_id, device_id}. Stored in IndexedDB/SQLite. Separate from read cache.

**Offline double-scan check:** Before storing, check local queue for same member+shift within 3 min. If found: discard + "Already scanned recently."

---

# 14. Member Join Flow

**Step 0 (auto):** Profile completeness check. Missing fields collected inline. Saved to profile on submission. No blocking.

**Step 1 — Existing Member?**
Yes/No cards. If Yes: optional joining date, plan, expiry fields. Trial hidden. Admin sees "Existing Member" badge.

Duplicate phone check: same phone = same member. System detects → "Welcome back! Found your previous membership." → admin sees "Returning Member" badge → on approval, old record reactivated, history preserved.

**Returning member with changed phone:** "Have you studied here before?" → "What was your previous phone?" Optional. Or match by email or Aadhaar last 4. If match found: [Yes, Link] → history merged. Admin notified.

**Step 2 — Shift & Plan:**
Shift list. Plan: Monthly/3-Month/6-Month.
If trial available AND member hasn't used trial at this library: two options shown: "Start with Free Trial" (skips payment) or "Pay Now." Trial selected → payment step skipped entirely.

**Step 3 — Add-ons:**
If admin configured any. Toggle. Refundable deposit clearly labeled. Skipped if none.

**Step 4 — Payment:**
If trial selected: this step skipped entirely.
If paying: Cash or UPI. UPI: admin IDs + deep-link icons (PhonePe/GPay/Paytm/Amazon) + upload screenshot (required) + **UPI sender name field (required): "Enter the name shown on your payment app."**

**Step 5 — Review & Submit:**
Full summary including referral code field (optional, shows if library has referral active). Submit → "Application Submitted — Payment Under Review." Member status: "Payment Pending." Cannot scan yet. Note: "Typically confirmed within 24 hours."

**UPI payment SLA:**
- Admin notified immediately on proof upload
- 48h no action → escalation push to admin
- 7 days no action → auto-expire. Member notified with reason + option to reapply.

## 14.1 Trial Membership Rules

- Duration = Trial Days from shift config
- Full scanning access
- Seat assigned during trial approval (same flow as regular)
- ₹0. Payment step skipped. Status badge: "Trial — X days left" (purple)
- Streak counts during trial
- 1 day before end: "Trial ends tomorrow. Pay to keep seat and streak."
- On end: "Trial Expired." Admin converts via Renewal Screen.
- `trial_used = true` set on member-library record. Trial never available again for same member at same library, even after rejoin.
- Admin sees trial members in Members sub-tab: "Trial" filter chip (purple).

---

# 15. Member Analytics Tab

**Library scope:**
- Summary cards = aggregate across ALL joined libraries
- Total Hours = completed sessions only (checkout − check-in). Incomplete = 0 hours.
- Streak = per-library. Library selector pill if 2+ libraries.
- Leaderboard = per-library. Library selector above card.
- Bar chart + heatmap = aggregate, library selector to filter.
- Badges = global.

**Date filter:** Today · This Week · This Month · All Time

**Summary cards (2×2):** Days Present · Days Absent · Total Hours · Attendance Rate %

**Trend indicators on each card:**
- ↑ +X% vs last [period] (green) · ↓ -X% (red) · → Same (gray)
- Matches selected filter: "vs last week" for This Week, "vs last month" for This Month.
- Not shown for Today or All Time.
- Tap → comparison popup: "This month: X hours. Last month: Y hours. Difference: +Z hours."

**Streak card:** Orange, flame 🔥, current streak large, best ever below. Library selector. Note: "Incomplete sessions count for streak but not for study hours."

**Leaderboard card:** Top 5 by hours. This Week / This Month / All Time toggle. Nickname only. **Duplicate nickname handling:** if two members have same nickname in same library, display as "Rahul (1)", "Rahul (2)" (older member gets lower number). Current member highlighted even outside top 5. "vs last week" trend (↑/↓).

**Badges:** Horizontal scroll. Earned = full color + date. Unearned = gray + requirement.

**Bar chart:** Daily hours. Orange bars. Today darker.

**Calendar heatmap:** 30-day grid. White=0h, light orange=1-2h, dark orange=4h+. Tap → check-in, checkout, hours, session type.

**Export Attendance:** [Export My Attendance CSV] button. Columns: Date, Check-in Time, Check-out Time, Duration, Session Type, Library, Seat. Filename: `Silence_Attendance_[Nickname]_[DateRange].csv`. Use case: prove attendance to coaching/parents/scholarship.

## 15.1 Badge System

| Badge | Emoji | Condition |
|---|---|---|
| 7-Day Streak | 🔥 | 7 consecutive days with any scan |
| 30-Day Streak | 💯 | 30 consecutive days |
| Early Bird | ⏰ | Check-in before 7:00 AM on 5 different days |
| Night Owl | 🦉 | Check-in after 8:00 PM on 5 different days |
| Top of Week | 🏆 | Ranked #1 on library leaderboard any week |
| 100 Days Club | 📅 | 100 total days present at any library |
| Consistent | ⚡ | 90%+ attendance rate in any calendar month |

**Streak rules:** Consecutive calendar days with any scan. Resets if day missed. Freezes on admin-closed days (single-day or scheduled range). Expired membership does NOT break streak. Trial counts.

---

# 16. Member Profile Tab

| Element | Spec |
|---|---|
| Header | Photo (tap → camera or gallery) + name + nickname + exam category badge + [Edit Profile] |
| Edit Profile | Name, nickname (leaderboard name), phone, email, gender, DOB, address, exam category, ID documents. Verify phone/email optional (OTP). |
| Hide contact | **Removed entirely.** Admin always sees phone. Members only see other members' nicknames and exam category — no phone numbers between members anywhere in app. |
| Refer a Friend | Code (REF-XXXX-XXX) + [Share] + "Referred X members" + pending/credited rewards |
| Joined Libraries | Active memberships: library name + Verified ✓ + status + days remaining + social links icons. [+ Join Another Library] → Explore. |
| Past Libraries | Exited libraries: name + "Exited [date]" + duration. Tap → read-only history (attendance, payments, badges). Permanent. |
| Verify Phone/Email | OTP. Adds verified tick. Required for Verified Badge. |
| App section | Refer a Friend · Help & Support · Terms · Privacy · Logout |
| Logout | Confirmation → Auth screen |

---

# 17. Notifications

## 17.1 Bell Icon

Both admin and member headers. Red badge = unread count. Tap → Notifications screen.

## 17.2 Notifications Screen

Reverse chronological. Unread = orange-tinted bg. Read = white. Tap → marks read + navigates to relevant screen. Mark All Read button. 30-day display limit (data retained in DB; "Load older" pagination available).

## 17.3 Complete Notification Events

| Event | Who | Message | Timing |
|---|---|---|---|
| Join approved | Member | ✅ Approved! Seat [X] at [Library]. Starts [date]. | Immediate |
| Join rejected | Member | Application not approved at [Library]. Reason: [X] | Immediate |
| Payment confirmed | Member | ₹[Amount] confirmed at [Library]. Plan: [dates]. Seat [X]. Ref: [ID]. | Immediate |
| Payment rejected | Member | Payment not confirmed. Reason: [X]. Re-upload or contact library. | Immediate |
| Plan expiring in 7 days | Member | Your plan at [Library] expires in X days. Tap to renew. | 9 AM, 7 days before |
| Plan expires today | Member | Your plan at [Library] expires today. Renew to keep seat [X]. | 9 AM on expiry date |
| Plan expired yesterday | Member | Membership at [Library] expired. Renew — seat may be reassigned in 3 days. | 9 AM day after |
| Join request expiring in 2 days | Member | Your application at [Library] will expire in 2 days. Contact library or reapply. | Day 5 at 9 AM |
| Join request auto-expired | Member | Application at [Library] expired. Contact library or reapply. | Day 7 |
| Badge earned | Member | 🏆 You earned [Badge]! Check Analytics. | Immediate |
| Announcement | Member | [Library]: [preview] | Immediate |
| Trial ending tomorrow | Member | Trial at [Library] ends tomorrow. Pay to keep seat and streak. | 9 AM |
| Hold approved | Member | Hold at [Library] approved. Seat [X] reserved until [end date]. Expiry extended to [date]. | Immediate |
| Hold rejected | Member | Hold request at [Library] not approved. Contact library. | Immediate |
| Hold ending in 2 days | Member | Membership hold at [Library] ends in 2 days. Resume studying! | 9 AM |
| Hold auto-cancelled | Member | Hold at [Library] ended and seat released. Rejoin to continue. | On trigger |
| Referral reward pending | Member | Reward for referring [Name] — pending (X of 5 check-ins done). | On referral join |
| Referral reward credited | Member | 🎁 [X] free days added! [Name] completed their check-ins. | On lock release |
| Referral reward cancelled | Member | Referral reward for [Name] cancelled — they left the library. | On member exit |
| Member renewal needed | Member | Your library prepared a renewal: [Plan] ₹[Price]. [Confirm] [Decline] — 24h. | Immediate (if notify option) |
| Transfer completed | Member | Membership transferred from [Library A] to [Library B]. Seat [X], Shift [Y]. | Immediate |
| Library closed today | Member | [Library] is closed today ([reason]). Your streak is protected. | Immediate on Close Today |
| Scheduled closure reminder | Member | [Library] closed [date]–[date] for [reason]. Your streak is protected. | On closure saved |
| Manual check-in requested | Admin | [Member] couldn't scan — requesting manual check-in at [time]. | Immediate |
| New join request | Admin | New application from [Member Name] | Immediate |
| Payment proof submitted | Admin | [Member] submitted ₹X proof — confirm? | Immediate |
| Payment pending 48h | Admin | ⚠️ [Member]'s payment proof waiting 48 hours. Review now. | 48h after submission |
| Member exited | Admin | [Member] exited [Library] | Immediate |
| Seat change requested | Admin | [Member] requested seat change | Immediate |
| Hold request submitted | Admin | [Member] requested hold [date] to [date]. Reason: [X] | Immediate |
| Subscription expiring | Admin | Your plan expires in X days | Immediate |
| Seat auto-held | Admin | [Member]'s seat auto-held (expired 3 days ago) | Immediate |
| Member referred new joiner | Admin | [Member A] referred [Member B] who just joined. Reward [Member A]? | Immediate |
| Join request expiring tomorrow | Admin | [Name]'s join request expires tomorrow. Approve or reject now. | Day 6 at 9 AM |
| Maintenance seat >7 days | Admin | Seat [X] in maintenance 7 days. Fixed? | 7 days after marking |
| Post-shift scan | Admin | [Member] checked out [X] min after [Shift] ended. | Immediate |
| Verified badge earned | Admin | 🎖️ [Library] earned the Verified badge! | Immediate |
| Flagged offline sync | Admin | [Member]'s scan from [date] needs review (QR grace period expired). | On sync |

---

# 18. Edge Cases & Behavioral Rules

## 18.1 Empty States

| Screen | Empty State |
|---|---|
| Stats grid (pre-launch) | All 0s. Cards visible. |
| Attendance strip | "No check-ins yet today" |
| Recent Activities | "No recent activities" |
| Member List | "No members yet. Add your first member or share your library code." |
| Join Requests | "No pending requests." |
| Hold Requests | "No hold requests right now." |
| Seat Change Requests | "No seat change requests right now." |
| Archive | Box illustration + "No past members yet" |
| Analytics charts | Ghost placeholder + "No data for this period" |
| Notifications | Bell icon + "You're all caught up!" |
| Explore search | "No libraries found. Try a different name or code." |
| Member — no library | Dashed card: "Join a library to get started" + [Find a Library] |
| Audit Log | "No actions recorded yet." |

## 18.2 Key Behavioral Rules

**QR & Scanning:**
- Attendance QR is static (library_id + qr_version integer). Server validates membership per scan. Printable permanently. No daily refresh.
- Offline scan stores: library_id, member_id, timestamp, qr_version, shift_id, device_id.
- **Offline queue and read cache are separate systems.** Queue = pending writes (scans). Cache = downloaded read data. Do not mix.
- **Offline queue limit: 500.** On overflow: block new scans with "Storage full — please reconnect." No silent discard.
- Offline double-scan: check local queue before storing. Same member+shift within 3 min → discard + "Already scanned recently."
- QR regeneration grace period: old QR valid for 7 days post-regeneration. After grace: flagged for admin review.
- **Offline sync QR version check:** Scan before regeneration → accept. Scan after regeneration but within 7-day grace → accept. Scan after grace period → flag for admin review.
- Clock skew >15 min → flagged (not rejected). Admin reviews.
- Double scan within 3 min (online): show success card with "Already checked in at [time]." Not silent.
- 2 failed scans → [Contact Admin] notification button. No self-serve override.
- **Auto-checkout + overtime:** One session per check-in. Auto-checkout fires 10 min after shift end, only for members who haven't scanned yet. Post-shift scan = checkout for existing session (not new session). Overtime included in duration.

**Sessions & Hours:**
- Incomplete session = 0 hours for leaderboard. Counts as present for streak.
- Admin can edit session duration: Member Detail → Attendance → tap session → [Edit Duration] (reason req). Tagged "Admin Edited."
- Batch Close: Admin closes all open sessions for a shift. Default checkout = shift end time.

**Memberships:**
- Active members always check in/out UNLESS admin has explicitly placed on Hold or removed.
- Seat NOT freed on expiry. Seat stays occupied.
- **Auto-hold trigger:** Configurable (default 3 days, max 14). After expiry + grace days with no admin action: seat → Hold. Admin notified.
- Expired ≤ 3 days → renewal defaults to "Continue from expiry."
- Expired 4+ days + absent those days → admin sees date-choice prompt (from expiry / from today / calendar).
- Exit Library (member): blocked if dues > 0. Two-tap confirmation (no typing). Admin force-exit: write-off/keep dues choice.
- Admin renewing directly: [Renew Silently] or [Notify Member First]. If admin renews while member self-renewal is pending: admin renewal wins. Member's pending cancelled.
- Duplicate phone = same member. Returning member flow activated.
- `trial_used` = permanent per member-library pair. Cannot trial again at same library.

**Payments:**
- UPI: screenshot + sender name (required). Deep-link icons based on UPI handle.
- Cash confirmation → member notification with receipt details.
- Discount = admin reduces plan price. Not the same as partial payment. Discount is V1. Installments are V2.
- Discount stored with: original price, charged amount, discount value, reason, admin name.
- Max discount % configurable in Business Rules (default 100% = no limit).
- Admin force-exit with dues: [Mark as Write-off] or [Keep in Records]. Write-offs excluded from Net Profit (bad debt).

**Critical Action Confirmations (type to confirm):**
- QR Regeneration: type "REGENERATE"
- Remove Member from Seat: type "REMOVE" + reason
- Delete Seat: type "DELETE"
- Library Permanent Closure: type library name
- Account Deletion: type "DELETE MY ACCOUNT"

**Double-tap confirmations (no typing — mobile-friendly):**
- Exit Library (member): two-tap (Step 1 warning → Step 2 final red button)

**Other rules:**
- Stats always show 0 for no data. Never blank or "--".
- All setup screens pre-fill existing data.
- All date pickers: calendar grid view. No scroll drum.
- Popular tag: max ONE per shift. System auto-shows "Most Chosen" if admin hasn't set one.
- Exam category: used for admin filter (Members sub-tab) and announcement targeting.
- Social links: in Library Profile (admin config). Shown to members on library profile + their Profile tab.
- Shift overlap: yellow warning, admin must explicitly confirm.
- Photo source: all users — camera OR gallery for all photo types. ID documents = camera (rear) or gallery.
- Announcement read: member taps it. Push open alone ≠ read.

**Discount audit trail (implicit):**
Every discounted payment shows: original price + charged + discount + reason + admin name. Viewable in Member Detail → Payments and Admin Audit Log.

## 18.3 Subscription Expiry Behavior

| State | Timing | Admin | Member |
|---|---|---|---|
| Grace | Days 1–7 | Full access. Orange non-dismissable banner. | Unaffected. No notice. |
| Read Only | Days 8–30 | View only. Blocked actions → Renew Modal. | Scanning continues. Passive card notice: "Library management temporarily paused. Your membership is safe." |
| Full Lock | Day 31+ | Single paywall screen. Data safe. [Renew Now] only. | Scanning continues. Same passive notice. |

**Renew Modal (Read-Only blocked actions):**
Current plan + price + expired X days ago + feature list + [Renew Now — ₹X] (Razorpay) + [Remind Me Tomorrow]. On payment: immediate reactivation. Blocked action proceeds. Toast: "Subscription renewed! You're back."

**Data retention:** 90 days post-Full Lock before PII deletion. Structure retained 3 years.

---

# 19. Library Codes & Joining Methods

Format: **SIL-[6-char alphanumeric].** Example: SIL-4K9M2P. Uniqueness check with retry.

*(City prefix removed — collision risk eliminated. e.g., Bangalore/Bankura both = BAN.)*

| Entry Point | How |
|---|---|
| Explore search bar | Type code → resolves → join flow |
| [Join with Code] button | Bottom sheet, case-insensitive, auto-formats |
| WhatsApp shared link | Tap → app or Play Store/App Store → auto-navigate |
| Scan Joining QR | → join flow |
| Admin adds manually | Add Member wizard |

---

# 20. Offline Support

**Two separate systems — not the same:**
- **Write queue (scan queue):** Stores unsynced scans. Max 500. Syncs to DB on internet restore. "Pending uploads."
- **Read cache:** Local copy of data for viewing offline. Refreshed FROM server. "Downloaded for offline viewing."

**Offline scan queue:**

| Stage | Behavior |
|---|---|
| Member scans offline | Save to IndexedDB/SQLite: {library_id, member_id, timestamp, qr_version, shift_id, device_id} |
| Success shown | "Checked In! [time] — Offline. Scan saved." [Done] button. |
| Double-scan check | Before storing: check queue for same member+shift within 3 min → if found: discard + "Already scanned recently." |
| App online | Reads queue → inserts to Supabase → clears queue → "X scans synced" toast. |
| QR version mismatch | Before regeneration timestamp → accept. Within 7-day grace period → accept. After grace period → flag for admin review. |
| Clock skew | Device clock >15 min from server NTP → flagged (not rejected). Admin reviews. |
| Queue limit | **500 scans max.** On overflow: block new scans + "Storage full — please reconnect." No silent discard. |

**Offline read cache (exact contents):**

For admin offline:
- Member list: up to 200 most recently active (sorted by last_seen). Fields: name, phone, photo URL, status, seat, shift, expiry.
- Today's check-ins: full list with check-in/out time, member name, seat, status.
- Seat grid: occupancy for currently selected shift (at last sync).
- Cache refreshes every 5 min when online. Stored in SQLite/IndexedDB separate from write queue.

For member offline:
- Own membership cards (all joined libraries): status, seat, expiry, dues.
- Own attendance history: last 30 days.
- Today's check-in status.

Not cached: Analytics charts, leaderboard, announcement history beyond last 3.

---

# 21. Admin Audit Log

**Entry:** Profile tab → Account → Audit Log

**Actions automatically logged:**
- Member approved / rejected
- Member removed from seat (with reason)
- Payment confirmed or rejected
- Discount applied (amount, reason, who)
- QR code regenerated
- Seat manually reassigned
- Membership manually renewed (silent or notified)
- Announcement sent (recipients, preview)
- Library closed
- Member force-exited (with dues action: write-off or kept)
- Transfer completed (from/to which library)
- Hold approved / rejected

**Each log row:** Timestamp · Action type (colored pill) · Details · Previous → New value (where applicable).

**Retention:** 90 days. Read-only. Visible only to library owner (account creator).

---

# 22. Subscription Pricing Recommendation

> ⚠️ **Owner action required before build. Recommended model below.**

**Recommendation: Member-count tiered pricing.**

*Not revenue-based* (cash/UPI payments unverifiable). *Not one flat price* (unfair to small libraries).

| Plan | Monthly | Annual (÷12) | Members | Libraries |
|---|---|---|---|---|
| Starter | ₹199 | ₹166 | Up to 30 | 1 |
| Basic | ₹399 | ₹333 | Up to 150 | 1 |
| Pro | ₹799 | ₹666 | Unlimited | Up to 5 |

**Annual discount:** 2 months free (≈17% off). Preferred by Indian SMBs for budgeting.

**Free trial:** 14 days Pro. One time per account. No card required.

**Rationale:**
- Alwar/Bhilwara library, 50 members × ₹600/month = ₹30,000/month revenue. Basic at ₹399 = 1.3% of revenue. Affordable.
- Kota/Jaipur library, 200 members × ₹1,300/month = ₹2,60,000/month. Pro at ₹799 = 0.3% of revenue. Trivial.
- Starter captures new/small libraries without pricing them out.

**Payment gateway for subscriptions:** Razorpay (or final choice before build). Separate from member UPI payments.

---

# APPENDIX: Change Log (v5 → v6.1)

| Version | Key Changes |
|---|---|
| v5.0 | Original PRD |
| v6.0 | 43 fixes from Claude + DeepSeek + Gemini + ChatGPT audits + 18 owner requirements |
| v6.1 | 33 additional patches: offline queue 500, auto-checkout overtime fix, referral anti-abuse lock, verified badge stronger criteria, referral code format, hold expiry auto-cancel, discount audit log, day-5 member notification, seat search DB index, offline cache exact spec, partial vs discount clarification, returning member phone change, library closure pre-check, bulk announcement preview, trial_used flag, duplicate nicknames, auto-hold configurable, admin renewal options, attendance strip shift filter, member CSV export, force-exit write-off flow, 4 contradiction resolutions, 7 missed cross-AI fixes (self-initiated hold, audit log, emergency contact, vs-last-month analytics, multi-day closure, exit two-tap, member transfer) |

---

*SILENCE PRD v6.1 — May 2026*
*Status: Ready for developer handoff pending Section 22 pricing confirmation*
*Total sections: 22 · Total notification events: 38 · Total behavioral rules: 30+*
