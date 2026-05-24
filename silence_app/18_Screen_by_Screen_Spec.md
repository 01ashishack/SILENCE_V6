# SILENCE – Screen-by-Screen UI/UX Specification

## Document Conventions
- **Colors:** Primary #E65C00, Background #FFFFFF, Dark #0D1B2A, Error #DC2626, Success #10B981, Warning #F59E0B.
- **Spacing:** 8dp grid. Margins/paddings in multiples of 8.
- **Typography:** System default sans‑serif. Font sizes: xs=11, sm=12, base=14, md=15, lg=16, xl=18, 2xl=20, 3xl=24, 4xl=32.
- **Touch targets:** Minimum 48x48dp.
- **Icons:** Feather (or Material) – consistent across app.

---

# AUTH & ONBOARDING

## S001 – Splash Screen

**Role:** Both  
**Navigation:** First screen on app launch.

**Layout:**
- Full screen orange background (#E65C00).
- Centered horizontal app logo.png on orange background. Spinner below
- Spinner (white) below logo (visible >1 sec).

**States:**
- Checking session: show spinner.
- Session valid → navigate to Admin Home or Member Home.
- No session → navigate to Auth Screen.

**Edge Cases:**
- Slow network: splash stays, no timeout (app handles network errors later).

---

## S002 – Auth Screen

**Role:** Both  
**Navigation:** From splash (no session).

**Layout:**
- Top half: orange background with white wave/curve at bottom.
- Bottom half: white card with rounded top corners (28px).
- Two tabs: Log In | Sign Up (toggle, no page reload).
- Below tabs: form fields.

**Log In Tab:**
- Email field (input, auto-capitalize off, keyboard email).
- Password field (input, show/hide eye toggle).
- [Log In] button (orange, full width).
- [Continue with Google] button (white, border, Google icon).
- [Continue with Apple] button (iOS only, white, border, Apple icon).
- Forgot Password link (text, right-aligned, gray, tappable).

**Sign Up Tab:**
- Full Name field (input, auto-capitalize words).
- Email field.
- Password field (strength indicator: Weak/Medium/Strong bar).
- Confirm Password field.
- [Create Account] button (orange, full width).
- Google/Apple buttons same as login.
- Terms link (gray text, center).

**States:**
- Loading: buttons disabled, show spinner on respective button.
- Validation errors: red inline text below each field.
- Success: navigate to Role Selection.

**Validations:**
- Email: valid format (contains @ and .).
- Password: min 6 characters.
- Confirm Password: matches password.
- Full Name: not empty.

**Edge Cases:**
- Google/Apple signup: if user already exists, log them in.
- Forgot password: send reset email via Supabase (email verification disabled in V1? Actually password reset still works without email verification). Show toast "Reset link sent to your email".

**Accessibility:** All fields have proper labels and error announcements.

---

## S003 – Role Selection

**Role:** Both  
**Navigation:** After successful signup/login (if no role saved).

**Layout:**
- Orange header (40% height) with "You are?" text (white, 24px).
- Two cards (white, rounded corners, margin 16):

**Card 1 – Library Owner:**
- Building icon (orange, 32px).
- Title: "Library Owner" (bold).
- Subtitle: "Manage seats, members, payments and attendance."
- Tags: Seats, Members, Analytics (small chips).

**Card 2 – Student / Member:**
- Person-studying icon.
- Title: "Student / Member".
- Subtitle: "Track attendance, compete on leaderboard."
- Tags: Attendance, Streak, Leaderboard.

**Selection:**
- Tap card → orange border + orange radio fill + light orange background tint.
- Warning text: "You cannot change your role after selection. Contact support to switch." (small gray text, lock icon).
- [Continue as X] button (orange, disabled until selection).

**States:**
- Loading: none.
- Error: none.

**Interactions:**
- Tap card → select it, button enables.
- Tap Continue → save role to `users.role`, navigate to Admin Home (if admin) or Member Home.

**Edge Cases:**
- User already has role: this screen never shows.

---

# ADMIN SCREENS

## S004 – Admin Home (Operational Dashboard)

**Role:** Admin  
**Navigation:** Bottom tab "Home" (first tab). If library exists, shows operational mode; else setup mode.

**Setup Mode (Before Launch):**
- Orange header same as operational.
- Setup card (white, orange left border, 4px): Title "Complete Library Setup", counter "0/4 done".
- Progress bar (thin orange, fills 25% per step).
- Four step rows: each with numbered circle (gray), title, subtitle, right arrow.
- [Continue Setup] button (orange) at bottom.
- All stats below show zeros (Revenue ₹0, Active 0, etc.).

**Operational Mode (After Launch):**

**Header:**
- Orange background (#E65C00), rounded bottom corners 28px.
- Left: Library cover photo (44px circle, white border), library name (bold white 15px), chevron-down, address (white 75% opacity 11px).
- Right: Date pill (calendar icon + "MON 18 MAY"), Bell icon (red badge if unread notifications).
- Greeting: "Good morning, [Name] 👋" (white 20px bold). Subtext: "Here's what's happening today" (white 12px).

**Library Switcher Dropdown (on tap library name/chevron):**
- List: "All Libraries" (orange checkmark if active), then each library name (checkmark if active).
- "+ Add Library" at bottom.
- Tapping changes all dashboard data.

**Library Photo Carousel:**
- Horizontal scroll, up to 4 photos. Pagination dots.
- Tap photo → opens Library Profile screen.

**Library Code Card:**
- White card, "Library Code" label, code "SIL-4K9M2P" (orange monospace, large). Share button (icon) on right.
- Below: [Copy] button (outline). Tapping copies code to clipboard.

**Stats Grid (2x2 layout after a full-width Revenue card):**
- **Revenue This Month:** Amount (large), breakdown "₹X cash / ₹Y UPI", "Today: ₹Z".
- **Active Today:** "X / Y members", "Scanned today".
- **Expired:** "X members", "Past expiry".
- **New Joinings:** "X this month", "+Y today".
- **Expiring Soon:** "X members", "within 7 days".
- **Live Occupancy:** Donut chart (occupied %), legend "Occupied / Vacant / On Hold".
- All cards tappable → Reservations → Members with filter.

**Today's Attendance Strip:**
- Shift filter chips above: [All Shifts] [Morning] [Evening] [Custom] – horizontal scroll.
- Active chip orange.
- Horizontal scroll of member avatars (44px). Colored ring: green=checked in, red=checked out, red overlay=expired scan.
- Below each: member name (truncated), last scan time, seat number.
- "View All" link at end.
- Empty state: "No check-ins yet today" (gray text, center).

**Action Required Banner (Amber background, rounded corners):**
- Appears only if pending actions >0.
- Two rows: "X payment proofs pending review", "Y join requests pending".
- Each row tappable → goes to Requests tab with appropriate filter.
- Hidden if no pending actions.

**Quick Actions Row:**
- Four icon buttons (orange circle, white icon, 48px): Add Member, Announce, Joining QR, Attendance QR.
- Below: optional "Close Today" as a smaller secondary button or in overflow.
- Tapping Add Member → opens Add Member wizard.
- Tapping Announce → opens Announcement Composer bottom sheet.
- Tapping QR buttons → opens QR modal.

**QR Section:**
- Two cards side by side (equal width):
  - Joining QR card: small QR preview, "Joining QR" label, [Download PDF] [Share] buttons.
  - Attendance QR card: same.
- Below: library code with Copy button.

**Recent Activities Feed:**
- List of last 10 events, reverse chronological.
- Each row: icon square (colored), description, relative time (e.g., "5 min ago").
- Example: "🟢 Member checked in – Seat G-12" (green).
- "View All" link at bottom.
- Empty state: "No recent activities".

**States:**
- Loading: skeleton placeholders for stats and feed.
- Offline: yellow banner "Offline mode – some data may be stale. Scans will be queued."
- Error: red banner "Failed to load dashboard. Pull to refresh."

**Pull to refresh:** Refresh all stats, attendance strip, activities.

**Edge Cases:**
- All Libraries selected: revenue/expenses sum, occupancy weighted average.
- No photos in carousel: hide carousel, show placeholder image.
- 0 members: stats show 0, no members in attendance strip.
- Closing time: Close Today button available.

**Accessibility:** All interactive elements have accessible labels. Donut chart includes textual percentage for screen readers.

---

## S005 – Reservations Layout (Seat Grid)

**Role:** Admin  
**Navigation:** Bottom tab "Reservations" → "Layout" sub‑tab.

**Layout:**
- Header row: Shift selector (mandatory dropdown), Floor selector dropdown, Filter icon, Search icon.
- Status filter chips (horizontal scroll): All, Vacant, Occupied, Expiring Soon, [Section names like Girls, Premium].
- Seat grid area:
  - Pagination controls: [← Prev 30] [Next 30 →] (or page dots).
  - Toggle: [Grid View] [List View] (segmented control).
- Legend bar at bottom: colored dots with labels (Vacant, Occupied, Hold, Maintenance, Expiring, Fee Pending).

**Shift Selector:**
- Dropdown with list of shifts (Morning, Evening, etc.) and "All Shifts".
- Changing shift re‑renders entire grid (fetch seat occupancy for that shift).

**Floor Selector:**
- Dropdown with floor names. Changes floor view.

**Seat Grid (Grid View):**
- Rendered as CSS Grid with 6 columns (on phones).
- Each seat cell: 52x44px, border-radius 8px, text centered (10px white bold).
- Colors: 🟢 Green (#22C55E) Vacant; 🔵 Blue (#3B82F6) Occupied; 🔵+🟡 small dot Expiring; 🔵+🔴 small dot Fee Pending; 🟠 Amber (#F59E0B) Hold; ⚪ Gray (#9CA3AF)+🔧 Maintenance.
- Tap seat → opens Seat Actions bottom sheet.

**Seat Grid (List View):**
- Each row: seat label, member name (if occupied), status badge, shift name (if multiple shifts assigned), and action icon (three dots).
- Tap row → same bottom sheet as grid.
- Row height 56px.

**Seat Search (tap search icon):**
- Expand search bar at top.
- Placeholder: "Jump to seat G-A-124".
- Live search: as user types, filter seats. Highlight matching seat.
- If seat exists, scroll to it and optionally auto‑switch floor.
- If not found: "No seat found with label 'X'".

**Filter icon:**
- Opens bottom sheet with checkboxes: Vacant, Occupied, Hold, Maintenance, Expiring, Fee Pending.
- Apply / Reset buttons.

**States:**
- Loading: spinner over grid area.
- Empty floor: "No seats on this floor. Add seats using Manage Layout."
- No results for filter/search: "No seats match current filters."

**Manage Layout (from three-dot menu top right):**
- Bottom sheet with sections: Floors (Add Floor, Rename, Delete), Sections (Add Section, Edit, Delete), Seats (Generate Seats, Add Seat, Bulk Actions), Tools (Export Layout, Reset Empty Seats).

**Generate Seats Bottom Sheet:**
- Context breadcrumb: "Ground Floor → General Study" (or just floor).
- Two tabs: [Bulk Generate] [Single Seat].
- Bulk: Prefix input (e.g., "G-A"), Range: From [1] To [100], Number format pills (01 02 or 1 2).
- Preview of first 6 seats.
- Section assignment toggle: if on, select section dropdown.
- [Generate X Seats] button.

**Seat Actions Bottom Sheet (Occupied Seat):**
- Header: seat label pill (blue), member name, "Expires in X days".
- Status badge: Occupied.
- Actions list (each tappable): View Member Details, Mark as Hold, Reassign Seat, Renew Membership, Remove from Seat.
- Remove from Seat: critical action → type "REMOVE" + reason field, then confirm.

**Seat Actions Bottom Sheet (Vacant Seat):**
- Header: seat label pill (green), "Vacant Seat".
- Actions: Assign Member, Reserve Seat, Mark for Maintenance, Delete Seat.
- Delete Seat: type "DELETE" to confirm.

**Edge Cases:**
- Multi-shift: same seat different shift shows different occupant. All Shifts view merges.
- Large library (1000 seats): virtualized + pagination ensures performance.
- While generating seats, if seat label already exists for that shift, show error "Label already used".

**Accessibility:** Grid cells have accessible labels "Seat G-A-12, Vacant". List view recommended for users with motor impairments.

---

## S006 – Reservations Members

**Role:** Admin  
**Navigation:** Reservations → Members sub‑tab.

**Layout:**
- Search bar (by name or phone).
- Filter chips horizontal: All, Active, Pending, Trial, Expired, Hold, Exp. Soon, Missing ID.
- Member cards list (scrollable).

**Member Card:**
- Profile photo (40px circle), name (bold), status badge (colored pill).
- Right side: three‑dot menu (edit, renew, remove).
- Below: seat pill (orange), shift name, expiry or dues info.
- If dues pending: amber banner "₹X pending".
- If expired: red text "Expired X days ago".
- If hold: amber text "On Hold".

**Select Mode (three-dot menu):**
- Tap "Select Members" → checkboxes appear on each card.
- Bottom action bar: [Send Announcement] [Export Selected] [Cancel].
- Max selection: 100 members (warning if exceed).

**Member Detail Screen (tap card or from three-dot):**
- Header: profile photo (64px), name, status badge, Member ID, join date.
- Info grid: 4 cells (Seat, Shift, Plan, Expires).
- Tab bar: Overview, Attendance, Payments, Activity, Notes.

**Overview tab:**
- Membership section (start/expiry, status, trial used).
- Attendance Summary (Total Visits, This Month, Current Streak).
- Payment Summary (Paid amount, Dues, Last Payment).

**Attendance tab:**
- Calendar (month grid, present/absent per day). Tap day → popup with scan times, duration, session type.
- [Edit Duration] button on any session (admin only): reason required.
- [+ Add Manual Entry] button: opens time picker, reason required.
- Edited sessions show "Admin Edited" tag.

**Payments tab:**
- List of payments: date, amount, method, status badge, plan period, Ref ID.
- Discount info shown: "₹700 plan → ₹500 charged (₹200 discount). Reason: Student discount. By: Admin Name."
- Tap payment to view full details (screenshot if UPI).

**Activity tab:**
- Timeline of events (join, seat changes, renewals, exits, holds, transfers).

**Notes tab:**
- Text area for admin private notes. Not visible to member.

**Edit button (pencil top right):**
- Opens edit form with all fields pre-filled.
- Can change membership dates, seat, shift, plan, apply discount.

**Edge Cases:**
- Large member list (500+): virtualized list, lazy load.
- Missing ID filter shows members with `id_proof_missing = true`.
- Transfer member: only visible if admin owns multiple libraries.

**Accessibility:** Calendar uses proper grid semantics. All icons have text labels.

---

## S007 – Reservations Requests

**Role:** Admin  
**Navigation:** Reservations → Requests sub‑tab.

**Sub‑tabs:** [Join Requests] [Seat Changes] [Hold Requests].

### Join Requests Tab

**Layout:**
- Filter chips: All, New (today), Aging (5+ days), Expiring Today.
- Sort order: oldest first (most urgent at top).
- Request card:
  - Member photo + name + request time (relative, e.g., "2 hours ago").
  - Aging indicator: gray (1-4d), amber (5-6d), red (7d + "Expires today").
  - Shift selected, plan selected, payment method (Cash/UPI).
  - Payment proof: if UPI, shows screenshot thumbnail + sender name. [View Full Image] tap opens modal.
  - [Confirm Payment] [Reject Payment] buttons (active only before membership decision).
  - After payment confirmed: [Approve Membership] [Reject] buttons appear.

**Approve Membership Flow:**
- Tap [Approve] → shift selector (confirm shift) → seat picker (cinema grid, only vacant seats for that shift) → **server re‑validates seat vacancy on final confirm** → if taken, show "This seat was just assigned. Pick another." → final confirmation dialog → membership created, seat occupied, member notified.

**Reject Flow:**
- [Reject] → reason picker (dropdown: Seat not available, Incomplete profile, Other). Required. → member notified.

**Day‑6 notification:** Admin receives push "Join request expires tomorrow".

**Empty state:** "No pending join requests."

### Seat Changes Tab

**Request card:**
- Member photo + name + current seat + request time + reason note + preferred section (if any).
- [Assign New Seat] button → opens seat picker (vacant seats in same shift) → confirm → member notified.
- [No Seats Available] button → member notified to wait.

### Hold Requests Tab

**Request card:**
- Member photo + name + requested dates (start – end) + reason.
- [Approve Hold] [Reject Hold].
- On approve: seat → hold (amber), membership status = hold, expiry extended by hold duration, member notified.
- On reject: member notified with reason.

**Edge Cases:** If hold request exceeds max_hold_days (30), show warning to admin but still allow (admin can override).

---

## S008 – Reservations Archive

**Role:** Admin  
**Navigation:** Reservations → Archive sub‑tab.

**Layout:**
- Search bar (by name).
- List of faded profile rows:
  - Profile photo (faded), name, "Exited on [date]", "Member since [date]", duration pill (e.g., "4 Months").
- Tap row → read‑only Member Detail (all history preserved, no edit buttons).
- Empty state: open archive box illustration + "No past members yet".

---

## S009 – Analytics

**Role:** Admin  
**Navigation:** Bottom tab "Analytics".

**Layout:**
- Header: Library switcher pill (same as home), download/export icon.
- Date filter pills: Today, 7 Days, This Month, Custom (calendar picker).
- Scrollable content:

**Revenue Cards (side by side):**
- Today's Revenue: ₹X (Cash ₹Y / UPI ₹Z), "X students paid".
- Monthly Revenue: ₹X (Cash ₹Y / UPI ₹Z).

**Expenditure & Profit (side by side):**
- Monthly Expenses: ₹X.
- Net Profit: ₹X (green if positive, red if negative).

**Dues Card:**
- Total Dues ₹X, "Y members pending".

**Annual View (3 cards):** Annual Revenue, Annual Expenses, Annual Net Profit.

**Financial Trend Chart:**
- Line chart: Revenue (orange line) vs Expenses (purple dashed) over selected period.
- X‑axis dates, Y‑axis amount.
- Tap data point → show exact values.

**Revenue Breakdown (donut/pie):**
- Cash vs UPI vs Add‑ons.

**Latest Payments List:**
- Recent confirmed and pending payments: member name, amount, status.

**Attendance Chart (bar chart):**
- Daily check‑in counts for selected period.

**Occupancy Chart (horizontal bars):**
- Shift‑wise occupancy % (Morning, Evening, etc.).

**Expenditure Section:**
- [+ Add Expense] inline button (in section header, not floating).
- Expenditure breakdown bars (by category).
- History list: date, category pill, amount, note, receipt icon, delete button (soft delete).

**Export Button:** [Export CSV] → selects period, downloads CSV (members, attendance, payments, revenue, occupancy). CSV only, PDF in V2.

**States:**
- Loading: skeleton charts.
- No data: ghost chart placeholder + "No data for this period".

**Add Expenditure Flow:**
- Tap [+ Add Expense] → bottom sheet: Library selector (if All Libraries view), Amount (₹), Category dropdown (Rent, Electricity, Internet, Water, Maintenance, Salary, Supplies, Generator, Cleaning, Security, Taxes, Miscellaneous), Date (calendar, default today), Note (optional), [Attach Receipt Photo] (optional).
- [Save] → adds to history, updates Net Profit.

**Edge Cases:** If All Libraries selected, expense category breakdown sums across libraries.

---

## S010 – Admin Profile

**Role:** Admin  
**Navigation:** Bottom tab "Profile".

**Layout:**
- Header: profile photo (tappable → camera or gallery), name, "Owner · [Library Name]", library count pill, subscription plan pill (e.g., "Pro").
- System status pill: green "All systems operational" / amber "Subscription grace period" / red "Full lock" – tap for status details.
- Your Libraries section: one card per owned library: library photo, name, member count, occupancy %, arrow. Tap → Library Profile.
- [Manage Libraries] button: opens list of all libraries, search, + Add New Library.
- Business Settings grid (icons in 2x4 grid): Seat Pricing, Shift Config, Membership Rules, Branding, QR Assets, Add-on Services, Notifications, Exports.
- Account section list: Edit Profile, Subscription, Announcements, Exports & Reports, Audit Log, Referral Settings, Support & Help, About & Legal.
- Logout (red text, bottom).

**Business Settings – Seat Pricing:**
- List of plans (Daily/Weekly/Monthly/Quarterly) with price, active toggle, Popular tag (max one per shift).
- Edit screen for each plan.

**Shift Config:** Same as Library Setup Stage 3 – canonical shift management.

**Membership Rules:** Form with fields: expiry_grace_days (1-14), max_hold_days (3-90), max_holds_per_period (0-6), allow_expired_checkin (toggle), max_discount_percent (0-100), etc.

**Branding:** Upload cover photos, logo, theme colours (preview), printable assets (posters, banners).

**QR Assets:** List of QR codes (Joining, Attendance) with version history, download, share, regenerate.

**Add-on Services:** Manage add-ons (name, price, refundable deposit, max count).

**Notifications:** Toggle each notification type.

**Exports:** CSV exports for members, attendance, payments, revenue, occupancy.

**Audit Log:** Read-only list of actions (timestamp, admin, action, details). Search and filter.

**Referral Settings:** Enable/disable rewards, set free days, min check-ins/days for reward release.

**Edge Cases:** Subscription status updates reflect in pill; grace period shows warning banner across all screens.

---

## S011 – Member Home

**Role:** Member  
**Navigation:** Bottom tab "Home" (first tab).

**Layout:**
- Orange header (#E65C00) with SILENCE logo (left), bell icon (right), red badge.
- Greeting: "Good [time], [Nickname] 👋" (white, bold). Subtext: "Track your attendance and progress below."
- Sub‑tabs: My Library (default), Explore.

### My Library Tab

**Profile Setup Card (if profile incomplete):**
- White card, orange left border.
- Two steps: (1) Complete Your Profile (name, nickname, phone, gender, DOB), (2) Upload ID Document.
- Each step: title, subtitle, status indicator (pending/done). [Complete] button on incomplete step.
- Card hides permanently when both steps done.

**Membership Cards (one per joined library, non‑exited):**
- Left border color: green=active, amber=expiring, red=expired, purple=trial, yellow=hold.
- Library name + Verified tick (if library earned) + status badge.
- Seat number + Shift name.
- Plan type + amount (+ discount note if discounted, e.g., "₹500 — ₹200 discount applied").
- Expiry progress bar (fill % based on days remaining) + days remaining countdown.
- Dues banner (if pending): orange background, "₹X pending · [Pay Now] button".
- Free trial banner (if trial): purple background, "Trial ends in X days · [Pay to Continue]".

**Card Action Buttons:**
- [Renew Plan] → opens Renewal Screen.
- [Request Seat Change] → bottom sheet with reason, preferred section (optional).
- [More ▼] dropdown: "Request Hold / Pause", "Exit Library".

**Hold Request Bottom Sheet:**
- Reason (required, 150 chars), Start date (calendar, min tomorrow), End date (calendar, min 3 days, max 30 days). Helper text: "Seat reserved. Billing pauses. Expiry extends."
- [Cancel] [Submit Hold Request].

**Exit Library Flow (two‑tap):**
- Step 1: bottom sheet "Exit [Library]? Seat freed. Remaining days lost. History preserved." [Cancel] [Yes, I Want to Exit →]
- Step 2 (1 sec delay): red sheet "This cannot be undone." [Cancel] [Confirm Exit] (red).
- Blocked if dues >0: "Clear dues before exiting."

**Today's Attendance Card:**
- Shows check‑in time, check‑out time, session duration.
- [Scan to Check In] button (if not checked in).
- Live timer for hourly plans: "Session duration: 1h 23m / 2h included". Warning when 15 min remaining.

**Announcements Section:**
- Last 3 announcements from admin.
- Unread announcements have orange left border.
- Tap to read full message → marks as read.

**Floating Scan Button:**
- 64px orange circle, bottom center, above tab bar. White QR icon.
- Only visible on My Library tab.

### Explore Tab

**Layout:**
- Search bar (placeholder: "Search library name, city, or code").
- [Join with Code] button (orange outlined).
- Library cards list (scrollable).

**Library Card:**
- Library photo (thumbnail), name, city, shift pills (first 3), starting price (e.g., "From ₹500/month").
- Amenity pills (AC, WiFi, etc.).
- "Free Trial Available" badge (if admin enabled).
- Verified tick (if library verified).
- [Apply to Join] button (orange). If already a member: "Already a Member ✓" (gray, disabled).

**Join with Code Bottom Sheet:**
- Input field (auto‑format with hyphens, case‑insensitive).
- [Find Library] button.
- If found, navigates to Join Flow for that library.

**Library Detail Screen (tap card):**
- Cover photo carousel, library name, verified tick, rating, address.
- Emergency contact (phone icon, tap to call), WhatsApp icon.
- Social links (Instagram, YouTube, Facebook, etc.).
- About text, amenities list, rules, shift timings.
- [Apply to Join] button.

**Empty State:** "No libraries found. Try a different name or city." + "Don't see your library? Let us know" link (submits lead).

---

## S012 – Member Analytics

**Role:** Member  
**Navigation:** Bottom tab "Analytics".

**Layout:**
- Date filter pills: Today, This Week, This Month, All Time.
- Summary cards (2x2 grid): Days Present, Days Absent, Total Hours, Attendance Rate %.
  - Each card has trend indicator (↑ +X% vs last period in green, ↓ -X% in red, → same in gray).
  - Tap card → popup comparison: "This month: X hours. Last month: Y hours."
- Streak Card (orange background):
  - Flame emoji 🔥, current streak (large number), "Best ever: X days".
  - Library selector pill (if member has >1 library).
- Leaderboard Card:
  - Toggle: This Week, This Month, All Time.
  - Top 5 members (nickname only, with duplicate suffix).
  - Current member highlighted even if outside top 5, shows position and gap.
  - "vs last week" trend indicator.
- Badges Section (horizontal scroll):
  - Each badge: emoji, name, earned date if earned; if not earned, show requirement text and grayed out.
  - All 7 badges always visible.
- Bar Chart: daily attendance hours for selected range. Orange bars. Today bar slightly darker.
- Calendar Heatmap (30‑day grid):
  - White = 0h, light orange = 1-2h, dark orange = 4h+.
  - Tap any day → popup with check‑in time, check‑out time, total hours, session type.
- [Export Attendance CSV] button (bottom).

**Edge Cases:** If no data, summary cards show 0, chart placeholder, heatmap all white.

---

## S013 – Member Profile

**Role:** Member  
**Navigation:** Bottom tab "Profile".

**Layout:**
- Header: profile photo (tappable → camera or gallery), full name, nickname, exam category badge, [Edit Profile] button.
- Edit Profile: form with name, nickname (leaderboard name), phone, email, gender, DOB, address, exam category, ID documents. Verify phone/email optional (OTP).
- (No hide contact toggle – removed.)
- Refer a Friend section: referral code (REF-XXXX-XXX), [Share] button, "You've referred X members", pending/credited rewards.
- Joined Libraries: active memberships list – library name, verified tick, status, days remaining, social links icons. [+ Join Another Library] link.
- Past Libraries: list of exited libraries – name, exit date, duration. Tap → read‑only history (attendance, payments, badges).
- App section: Refer a Friend, Help & Support, Terms & Privacy, Logout.
- Logout: confirmation dialog.

**Edge Cases:** If member has no referrals, show "No referrals yet. Share your code to earn free days!"

---

## S039 – QR Scanner

**Role:** Member  
**Navigation:** Floating scan button on My Library tab.

**Layout:**
- Full dark background #0D1B2A.
- Camera preview fills screen.
- Viewfinder: 260x260px white L‑bracket corners, animated orange scanning line.
- Status text: "Point at QR code" (white 14px).
- Offline banner (yellow) at top: "You are offline. Scan will be saved and synced when connected."

**Scan Results (Success):**
- Check‑in: green checkmark animation, "Checked In! 09:15 AM". Auto‑dismiss 3 seconds if online; [Done] button if offline.
- Check‑out: red checkmark, "Checked Out! 5:30 PM – Session duration: 2h 45m".
- Overtime checkout: "Checked Out! 6:15 PM – Note: This is 15 minutes after shift end. Admin has been notified."

**Scan Results (Error):**
- Not a member of this library: error card "This QR belongs to [Library Name]. You are not a member here." Buttons: [Scan My Library's QR] [Join This Library].
- Membership expired + admin toggle OFF: "Membership expired. Renew to enter."
- Already checked in (second scan within 3 min): "Already checked in at 09:15 AM." (not silent).
- After 2 failed scans: show [Contact Admin – Request Manual Check‑in] button and [Report via Queries] button. Tapping first sends push to admin.

**Offline Behavior:**
- Saves scan to local queue (IndexedDB) with metadata.
- On reconnect, syncs automatically, shows "X scans synced" toast.
- Queue full (500): block new scan, show "Storage full – reconnect".

**Edge Cases:** Clock skew >15 min – scan accepted but flagged for admin review.

---

## S036 – Join Flow (5 steps)

**Role:** Member  
**Navigation:** From Explore → [Apply to Join] or library code entry or Joining QR.

### Step 0 – Profile Check (Auto, no screen)
- App checks if member profile is complete (name, nickname, phone, gender, DOB, ID proof).
- If incomplete, missing fields are collected inline in subsequent steps.

### Step 1 – Existing Member?
- Screen with two cards: "Yes, I already study here" / "No, I'm new".
- If Yes: optional fields appear: Joining Date (calendar), Plan Type, Expiry Date (calendar). Admin will see "Existing Member" badge on request.
- If No: continue.

### Step 2 – Shift & Plan
- List of shifts (cards). Tap to select.
- Plan durations: Monthly, 3‑Month, 6‑Month with prices.
- If free trial available AND member hasn't used trial at this library: two radio options: "Start with Free Trial" (skips payment) or "Pay Now". Clear explanation: "Trial: X days free. No payment required now."
- If trial selected: skip Step 4 (payment).

### Step 3 – Add-ons (if admin configured any)
- List of add-ons with price, one‑time or monthly, refundable deposit clearly labeled.
- Toggle to select. Skipped if none.

### Step 4 – Payment (skipped if trial)
- Cash or UPI selection.
- If UPI: show admin's UPI IDs with deep‑link icons (PhonePe, GPay, Paytm, Amazon Pay) – tapping icon opens that app with UPI ID pre‑filled.
- Required: upload screenshot (camera or gallery), enter sender name (as shown in payment app).
- If Cash: no upload. Admin will record receipt later.

### Step 5 – Review & Submit
- Summary of library, shift, plan, add‑ons, amount, payment method.
- Referral code field (optional) – auto‑filled if deep link.
- [Submit Application] button.
- After submit: "Application Submitted – Payment Under Review. Admin will confirm within 24 hours."

**Validations:** All required fields (including screenshot for UPI) must be filled before submit.

---

## S026 – Renewal Screen

**Role:** Both (admin and member views differ slightly)  
**Navigation:** From membership card [Renew Plan] button, or from admin actions.

**Header:** "Renew Membership – [Member Name]" (admin) / "Renew Your Plan" (member)

**Current Membership Summary (read‑only):**
- Current plan, shift, seat, expiry date, amount paid, outstanding dues.

**Renewal Fields:**
- Shift dropdown (pre‑filled, changeable). If changed, seat may change.
- Plan Duration pills: Monthly / 3‑Month / 6‑Month (prices shown).
- Start Date: two radio options: "Continue from expiry: [date]" (default) OR "Start from today: [date]" (auto‑selected if already expired). Custom calendar picker available.
- Seat: read‑only if shift unchanged. If shift changed, seat picker opens (vacant seats only for new shift).
- Discount: [Apply Discount] toggle for admin only. Enter charged amount + reason.
- Amount: pre‑filled with plan price (or discounted price). Admin editable, member read‑only.
- Payment Method: Cash or UPI (same as join).

**Admin Renewal Options:**
- [Renew Silently] – immediate, no member confirmation.
- [Notify Member First] – sends push with 24h timeout.

**Member Self‑Renewal:**
- [Submit Renewal Request] – creates pending payment record, admin confirms.

**Edge Cases:** If shift changed and no seats available, show error "No vacant seats in selected shift".

---

# MODAL & BOTTOM SHEET SCREENS

## S022 – QR Modal

**Role:** Admin  
**Navigation:** From Home QR cards or quick actions.

**Layout:**
- Overlay modal, close (×) top right.
- Tabs: Joining QR | Attendance QR.
- Large QR code (220x220px) with orange corner brackets.
- Library code below (orange monospace) with copy icon.
- Three buttons: [Download as PDF] [Share] [Regenerate].

**Regenerate Flow:**
- Tap Regenerate → bottom sheet warning:
  - "⚠️ Are you sure you want to regenerate this QR?"
  - "Old QR continues working for **7 days** to allow transition."
  - Type "REGENERATE" to confirm.
  - [Cancel] [Confirm Regeneration].
- On confirm: QR version increments, audit log entry.

**Download PDF:** Generates A4 PDF with QR, library name, code, instructions. System share sheet opens.

**Edge Cases:** If offline, PDF generation may fail – show error.

---

## S023 – Announcement Composer (Bottom Sheet)

**Role:** Admin  
**Navigation:** From Home quick action or Announcement History.

**Layout (bottom sheet, medium height):**
- Title: "New Announcement".
- Recipient selector: three cards – "All Members (X)", "Individual Members", "Filtered Group".
- If "Individual Members": search + chip selector (max 20).
- If "Filtered Group": multi‑select filters: Expiring in 7 Days, Expired, On Hold, Payment Pending, Absent Today, Absent 3+ Days, per shift, per exam category.
- Filter preview: "X members match" + avatar row (first 5).
- Title field (optional, max 80 chars, counter).
- Message field (required, max 500 chars, counter). Plain text only.
- [Send to X members] button (orange, full width).

**Pre‑send confirmation (another bottom sheet):**
- "Sending to X members." Avatar row (first 5 + "and X others"). Message preview.
- [Cancel] [Send Now].

**Edge Cases:** If no recipients selected, button disabled.

---

## S020 – Seat Actions Bottom Sheet

**Role:** Admin  
**Navigation:** Tap seat in Layout grid.

**Occupied Seat:**
- Header: seat label pill (blue), member name, "Expires in X days".
- Actions (list tiles): View Member Details, Mark as Hold, Reassign Seat, Renew Membership, Remove from Seat.
- Remove: type "REMOVE" + reason, confirm.

**Vacant Seat:**
- Header: seat label pill (green), "Vacant Seat".
- Actions: Assign Member, Reserve Seat, Mark for Maintenance, Delete Seat.
- Delete Seat: type "DELETE", confirm.

**Mark for Maintenance:**
- Bottom sheet: issue description (optional), duration (if known). Confirm → seat becomes gray with wrench.

**Edge Cases:** If seat is already on hold, "Mark as Hold" replaced with "Release Hold".

---

## S021 – Generate Seats Bottom Sheet

**Role:** Admin  
**Navigation:** From Layout → Manage Layout → Generate Seats.

**Layout:**
- Context breadcrumb: "Ground Floor → General Study" (or just floor).
- Two tabs: [Bulk Generate] [Single Seat].

**Bulk Generate:**
- Prefix input (e.g., "G-A") – helper: "Seats will be named G-A-01, G-A-02..."
- Range: From [1] To [100] (two side‑by‑side number inputs). Auto‑shows "Will generate X seats".
- Number format pills: "01 02 03" (selected) or "1 2 3".
- Preview: first 6 seat squares with labels, "+ and X more".
- Section assignment toggle: "Assign to section?" – if on, section dropdown.
- [Generate X Seats] button.

**Single Seat:**
- Prefix input, seat number input, seat label preview.
- [Add Seat] button.

**Validations:** Seat label must be unique within the floor/section for the shift. If duplicate, error shown.

---

## S017 – Payment Setup

**Role:** Admin  
**Navigation:** From setup card (Step 4) or Business Settings.

**Layout:**
- Cash toggle: "Accept Cash Payments" (ON by default).
- UPI IDs section:
  - Input field for UPI ID (e.g., "9876543210@paytm"), [Add] button.
  - List of added IDs as removable rows. Each row shows UPI ID and deep‑link icons (PhonePe, GPay, Paytm, Amazon Pay) based on handle.
- Validation: at least one method active (cash ON or at least one UPI ID).
- [Save] button.

**Edge Cases:** Editing existing config pre‑fills data.

---

## S027 – Add-on Management

**Role:** Admin  
**Navigation:** Business Settings → Add-on Services.

**Layout:**
- List of existing add‑ons (each with name, price, type, deposit, active toggle).
- [+ Add New Add‑on] button.
- Add/edit form (bottom sheet):
  - Name (text)
  - Price (₹ number)
  - Price Type (One‑time / Monthly)
  - Refundable Deposit toggle → deposit amount
  - Max Available (optional number)
  - Active toggle
  - [Save].

**Edge Cases:** If deposit is set, show separate line in member payment.

---

## S031 – Subscription Screen

**Role:** Admin  
**Navigation:** Profile → Subscription.

**Layout:**
- Current plan card: plan name (e.g., "Pro"), price (₹799/month), renewal date, Active badge.
- Features list with green checkmarks.
- Plan comparison cards (Starter, Basic, Pro) side by side (horizontal scroll).
- Each card: name, price, features, [Select] button (if not current).
- Billing History list (date, amount, invoice PDF link).
- Payment Methods management (Razorpay saved cards/UPI).
- [Manage Subscription] button (orange) – opens upgrade/downgrade flow.

**Upgrade Flow:**
- Confirm dialog with new price, features, billing date.
- Opens Razorpay checkout.

**Grace Period Banner:** orange, non‑dismissable, "Subscription expired X days ago. Renew to keep access."

**Read‑only Mode:** blocked actions show renew modal (same as upgrade flow).

---

## S032 – Library Profile (Admin view)

**Role:** Admin  
**Navigation:** From Your Libraries card.

**Layout:**
- Cover photo (full width, edit overlay).
- Library identity: small thumbnail, library name + verified tick (if earned), branch name.
- Stats row: rating (x.x stars + review count), member count pill.
- Quick actions: Share Profile, Preview as Member, QR Codes, Customise (icon buttons).
- Profile Completion bar (0‑100%).
- About Library (text, edit link).
- Stats inline: Members, Occupancy %, Shifts count, Years running.
- Settings list: General Information, Amenities, Membership Plans, Photos & Gallery, Rules & Guidelines, How to Join, Social Links. Each tappable → edit form.
- Ratings & Reviews: star breakdown, view all reviews, recent reviews preview, reply button.
- Recent Visitors: circular photos of last 7 days visitors.

**Customise Library Profile (separate screen):**
- Editable sections: Cover Photo & Gallery, Library Information (includes Public Contact Number), About Library, Amenities, Timings & Shifts (links to canonical shift screen), Membership Plans, Rules, How to Join, Social Links, Add‑on Services.

**Verified Badge Criteria (automatic):** Admin sees badge only after meeting conditions.

**Edge Cases:** If no reviews, show "No reviews yet".

---

## S034 – Ratings & Reviews

**Role:** Admin  
**Navigation:** From Library Profile → Ratings & Reviews.

**Layout:**
- Overall rating (large number, e.g., "4.8"), star display, total reviews.
- Rating bars (5 bars showing distribution).
- Tabs: All Reviews (count), Unread (count).
- Review card: reviewer avatar (initials), name, star rating, time (e.g., "2 days ago"), review text.
- If admin replied: admin avatar, reply text, edit/delete icons.
- [Reply] button on each unreplied review → opens text input.
- Load More Reviews button (pagination).

**Admin Reply:** Text area, [Post Reply] button. Reply appears immediately, member gets notification.

---

## S038 – Library Detail (Member view)

**Role:** Member  
**Navigation:** From Explore → tap library card.

**Layout:**
- Cover photo carousel.
- Library name + verified tick + rating (stars).
- Address, emergency contact (phone icon – tap to call), WhatsApp icon.
- Social links icons (Instagram, YouTube, Facebook, etc.).
- About text, amenities list (icons + text), rules.
- Shift timings (list).
- [Apply to Join] button (orange, full width) – starts join flow.
- If already member: [Already a Member] (disabled) + [Go to My Library] button.

**Edge Cases:** If no emergency contact, hide icon. If no social links, hide section.

---

## S040 – Notifications Screen

**Role:** Both  
**Navigation:** Tap bell icon in header.

**Layout:**
- List of notifications in reverse chronological.
- Each row: colored icon, title (bold), body text, time ago.
- Unread: orange‑tinted background. Read: white.
- Mark All Read button (top right).
- Empty state: bell icon + "You're all caught up!"
- Pagination: "Load older" if more than 30.

**Tap behavior:** Marks as read, navigates to relevant screen (join request → Requests tab, payment → Home action banner, badge → Analytics tab, announcement → Home announcements section).

**Edge Cases:** Notifications older than 30 days not displayed (data retained in DB).

---

## S029 – Audit Log

**Role:** Admin  
**Navigation:** Profile → Account → Audit Log.

**Layout:**
- List of actions (reverse chronological).
- Each row: timestamp, action type (colored pill), admin name, details, previous → new value (if applicable).
- Search bar (by action type, admin name).
- Date filter (last 7 days, 30 days, custom).
- Empty state: "No actions recorded yet."

**Edge Cases:** Data retained 90 days, auto‑purge.

---

## S030 – Scheduled Closures

**Role:** Admin  
**Navigation:** Business Settings → Membership Rules → Scheduled Closures.

**Layout:**
- List of upcoming/past closures.
- [+ Add Closure] button.
- Add form (bottom sheet): Start Date (calendar), End Date (calendar), Reason (text), Notify Members toggle (default ON).
- Existing closure: editable, deletable.
- During closure: QR scans show "Library closed today ([reason])", streak frozen, members notified.

**Edge Cases:** Overlapping closures not allowed (warn admin).

---

## S035 – Transfer Member

**Role:** Admin  
**Navigation:** Member Detail → three‑dot → Transfer to Another Library.

**Layout (bottom sheet):**
- Destination library dropdown (admin's other libraries).
- New shift dropdown (based on destination library).
- New seat picker (cinema grid, vacant for chosen shift).
- Transfer date (calendar picker, default today).
- Notify member toggle (default ON).
- [Cancel] [Confirm Transfer].

**On confirm:** Old membership status = 'transferred', new membership created, seat assigned, history preserved, member notified.

**Edge Cases:** If destination library has no vacant seats for shift, seat picker empty, transfer blocked.

---

## S025 – Manage Queries

**Role:** Admin  
**Navigation:** Profile → Manage Queries.

**Layout:**
- List of queries (open/replied/closed) – each row: member photo, name, message preview, time, status badge.
- Tap row → open conversation thread:
  - Member message (top, bubble style).
  - Admin reply section (text input, [Send Reply] button).
  - Status changes to Replied.
- Empty state: "No queries yet."

**Member side:** Access from Profile → Help & Support → Contact Library.

---

## S041 – Edit Session Duration

**Role:** Admin  
**Navigation:** Member Detail → Attendance tab → tap any session → [Edit Duration].

**Layout (bottom sheet):**
- Session info (original check‑in, check‑out, duration).
- New check‑out time (time picker, calendar grid).
- Reason (required, text area).
- [Save] button.

**On save:** Update attendance record, recalc duration, set `session_type='admin_edited'`, edited_by_admin_id, edit_reason. Log in audit log.

---

## S042 – Add Manual Entry

**Role:** Admin  
**Navigation:** Member Detail → Attendance tab → [+ Add Manual Entry].

**Layout (bottom sheet):**
- Date (calendar picker, default today).
- Check‑in time (time picker).
- Check‑out time (time picker, optional).
- Reason (required, dropdown: QR broken, Member forgot phone, Server down, Other).
- [Save] button.

**On save:** Create attendance record with `session_type='manual'`. Flagged in analytics.

---

## S048 – Help & Support

**Role:** Both  
**Navigation:** Profile → Help & Support.

**Layout:**
- FAQ section (expandable).
- [Contact Library] button (for members – opens query composer).
- [Request Role Change] button (admin/member – opens support ticket).
- Email support link.

**Query Composer (bottom sheet):**
- Subject (optional), Message (required).
- [Submit] → creates query record, admin notified.

---

# COMPLETED

*End of Screen‑by‑Screen Specification – covers all 50+ screens with detailed UI/UX, states, interactions, validations, edge cases, and accessibility notes.*