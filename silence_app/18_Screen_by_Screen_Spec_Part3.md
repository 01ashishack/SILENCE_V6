# SILENCE App — Screen-by-Screen Specification
## Part 3 of 3: Member Screens · QR Scanner · Join Flow · Notifications · Shared Modals

---

# SCREEN-060: Member Home — My Library Tab

```
ID:       S060-A
Name:     Member Home (My Library tab)
Route:    /member/home
Role:     Member only
Default:  My Library tab active
```

**Full Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER — 100px]     │
│              SILENCE        │  ← white logo text, center
│                        🔔3  │  ← bell right, red badge
│ Good morning, Rahul 👋      │  ← 20px bold white
│ Track your attendance...    │  ← 12px white 75%
│ [rounded bottom: 28px]      │
├─────────────────────────────┤
│ [Sub-tabs — white bg]       │
│ [My Library ●]  [Explore]   │  ← orange underline on active
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ── PROFILE SETUP CARD ──    │  ← CONDITIONAL: only if profile incomplete
│ ┌─────────────────────────┐ │
│ │ Complete Your Profile   │ │  ← white card, orange left border 4px
│ │                         │ │
│ │ ⃝ Complete details   >  │ │  ← step rows
│ │ ✅ Upload ID proof       │ │    green = done, gray circle = pending
│ └─────────────────────────┘ │
│                             │
│ ── MEMBERSHIP CARD ──       │
│ ┌─────────────────────────┐ │  ← white card
│ │ ▌ SILENCE Study Zone ✓  │ │  ← 4px left border (green=active)
│ │   [Active]              │ │    verified ✓ if library is verified
│ │                         │ │
│ │ 🪑 G-A-12    ☀ Morning  │ │  ← seat + shift
│ │ 📋 Monthly  ₹1,500      │ │  ← plan + amount
│ │                         │ │
│ │ ████████░░  Expires: 4d │ │  ← expiry progress bar
│ │ 19 May 2025             │ │    countdown below
│ │                         │ │
│ │ [Renew Plan] [Seat Chg] │ │  ← action buttons
│ │ [More ▼]                │ │  ← dropdown button
│ └─────────────────────────┘ │
│                             │
│ ── SECOND LIBRARY CARD ──   │  ← if member in multiple libraries
│ ┌─────────────────────────┐ │  ← amber left border = expiring
│ │ ▌ City Center Library   │ │
│ │   [Expiring]            │ │
│ │ 🪑 B-02  ☽ Evening     │ │
│ │ ████░░░░  Expires: 2d   │ │
│ │ [Renew Plan] [More ▼]   │ │
│ └─────────────────────────┘ │
│                             │
│ ── NO LIBRARY STATE ──      │  ← if no memberships
│ ┌─────────────────────────┐ │
│ │ - - - - - - - - - - -   │ │  ← dashed border card
│ │ Join a library to start │ │
│ │ [Find a Library →]      │ │  ← orange button
│ └─────────────────────────┘ │
│                             │
│ ┌── Today's Attendance ───┐ │  ← white card
│ │ ✅ Checked In  9:05 AM  │ │    if checked in: green bg tint
│ │ 🕐 Session: 2h 15m      │ │    running time if still in
│ │ [Scan to Check Out]     │ │  ← if checked in, show checkout btn
│ │                         │ │
│ │ (if not scanned):       │ │
│ │ 📍 Not checked in yet   │ │
│ │ [Scan to Check In]      │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Announcements ────────┐ │  ← white card
│ │ Announcements           │ │
│ │                         │ │
│ │ ▌Library closed tomorrow│ │  ← unread: orange 4px left border
│ │ └ 2 hours ago           │ │    tap → full message → marked read
│ │                         │ │
│ │ ░ Fee reminder          │ │  ← read: gray border
│ │ └ Yesterday             │ │
│ └─────────────────────────┘ │
└─────────────────────────────┤
│ [FLOATING SCAN BUTTON]      │
│    ⬤ 64px orange circle     │  ← QR scan icon, white
│    above bottom nav         │
└─────────────────────────────┤
│ [BOTTOM NAV — 3 tabs]       │
│ 🏠Home  📊Analytics  👤Profile│
└─────────────────────────────┘
```

**Membership card — left border colors:**
```
Active:          #22C55E  (green)
Expiring Soon:   #F59E0B  (amber)
Expired:         #EF4444  (red)
Hold:            #D97706  (orange-amber)
Trial:           #7C3AED  (purple)
Pending:         #9CA3AF  (gray)
```

**More dropdown options:**
```
Bottom sheet with:
  [Request Hold / Pause]
  [Exit Library]          ← red text
  [Cancel]
```

**Dues banner (inside card, conditional):**
```
Orange-tinted strip inside card:
₹500 pending  [Pay Now →]
Orange text, tappable
```

---

# SCREEN-060: Member Home — Explore Tab

```
ID:       S060-B
Name:     Member Home (Explore tab)
Route:    /member/home/explore
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│              SILENCE   [📤] │  ← share app button right
│ Good morning, Rahul 👋      │
├─────────────────────────────┤
│ [My Library]  [Explore ●]   │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Search ───────────────┐ │
│ │ 🔍 Search library, city │ │  ← white input, full width
│ └─────────────────────────┘ │
│                             │
│ [Join with Code]            │  ← orange outlined button
│                             │
│ ── Library Cards ──         │
│ ┌── Library Card ─────────┐ │  ← white card
│ │ [LIBRARY PHOTO 140px h] │ │    image top, radius 12px top corners
│ │ SILENCE Study Zone ✓    │ │  ← name + verified tick
│ │ Jaipur, Rajasthan       │ │    city
│ │ [Morning][Evening][+1]  │ │  ← shift pills
│ │ From ₹1,200/month       │ │    starting price
│ │ [AC][WiFi][Lockers]     │ │  ← amenity pills
│ │ 🆓 Free Trial Available │ │  ← if trial configured
│ │ [Apply to Join →]       │ │  ← orange button
│ └─────────────────────────┘ │
│                             │
│ ┌── Library Card ─────────┐ │
│ │ [PHOTO]                 │ │
│ │ City Center Library     │ │
│ │ Indore, Madhya Pradesh  │ │
│ │ [Morning][Full Day]     │ │
│ │ From ₹900/month         │ │
│ │ Already a Member ✓      │ │  ← gray, non-tappable
│ └─────────────────────────┘ │
│                             │
│ ┌── Don't see library? ───┐ │  ← always at bottom
│ │ Suggest a library       │ │
│ │ [Library Name           ]│ │
│ │ [Location               ]│ │
│ │ [Owner Phone (optional) ]│ │
│ │ [Submit Suggestion]     │ │
│ └─────────────────────────┘ │
│                             │
│ ── EMPTY STATE ──           │  ← when no search results
│    🔍                        │
│  No libraries found.        │
│  Try a different name or    │
│  use a library code.        │
└─────────────────────────────┘
```

**Join with Code bottom sheet:**
```
┌─────────────────────────────┐
│ Join with Library Code      │  ← 18px 600
│ ✕                           │
│                             │
│ ┌───────────────────────┐   │
│ │ SIL-4K9M-2P           │   │  ← auto-formats with hyphens
│ │                       │   │    case-insensitive
│ └───────────────────────┘   │
│ e.g. SIL-4K9M2P             │  ← helper text
│                             │
│ [  Find Library  ]          │  ← orange button
└─────────────────────────────┘
```

---

# SCREEN-061: QR Scanner

```
ID:       S061
Name:     QR Scanner
Route:    /member/scan
Trigger:  Floating scan button on Home OR notification tap
```

**Full Layout:**
```
┌─────────────────────────────┐
│ [STATUS BAR — white icons]  │
│ Background: #0D1B2A (dark)  │
│                             │
│ ← (back button, white)      │  ← top left
│                             │
│  ┌── OFFLINE BANNER ──────┐ │  ← CONDITIONAL: yellow top banner
│  │ ⚠️ You are offline.     │ │    when no internet
│  │ Scan saved, syncs later │ │
│  └────────────────────────┘ │
│                             │
│                             │
│  ┌──── VIEWFINDER ────────┐ │
│  │ ⌐──────────────────¬   │ │  ← 260×260px
│  │ |                  |   │ │    white L-bracket corners
│  │ |                  |   │ │    4px thick
│  │ |   [camera feed]  |   │ │
│  │ |      inside      |   │ │
│  │ └──────────────────┘   │ │
│  │  ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬  │ │  ← animated orange scan line
│  │  (moves top to bottom) │ │    moves continuously
│  └────────────────────────┘ │
│                             │
│     Point at QR code        │  ← white 14px, below viewfinder
│                             │
│                             │
│                             │
│  [After 3 failed scans:]    │  ← CONDITIONAL: appears after 2 fails
│  ┌────────────────────────┐ │
│  │[Contact Admin for      │ │  ← white outlined buttons
│  │ Manual Check-in]       │ │
│  │                        │ │
│  │[Report via Queries]    │ │
│  └────────────────────────┘ │
└─────────────────────────────┘
```

**Success State — Check-in:**
```
Background fades from dark to green tint temporarily, then:

┌─────────────────────────────┐
│ Background: #0D1B2A         │
│                             │
│  ┌── Success Card ────────┐ │  ← white card, center of screen
│  │                        │ │    slides up with animation
│  │    ✅                  │ │    green checkmark, 64px
│  │    (checkmark animation)│ │    bounces in
│  │                        │ │
│  │  Checked In!           │ │    22px, 700, #1A1A2E
│  │  9:05 AM               │ │    18px, #6B7280
│  │                        │ │
│  │  SILENCE Study Zone    │ │    library name 14px
│  │  Seat G-A-12           │ │    seat 13px #E65C00
│  │                        │ │
│  │  [offline notice if]   │ │  ← if offline: "Scan saved offline"
│  │                        │ │
│  │  [Done]                │ │  ← button (auto-dismiss 3s if online)
│  └────────────────────────┘ │
└─────────────────────────────┘
```

**Success State — Check-out:**
```
Same card but:
  Red checkmark (✓)
  "Checked Out!"
  "Session: 2h 45m"
  Duration in large text
```

**Error State — Wrong Library:**
```
┌── Error Card ──────────────┐
│    ❌                       │
│  Not a member here         │  ← 18px 600
│  This QR belongs to        │
│  "City Center Library"     │  ← library name from QR
│                            │
│  [Scan My Library's QR]    │  ← outlined button
│  [Join This Library →]     │  ← orange button
└────────────────────────────┘
```

**Error State — Expired (when toggle OFF):**
```
┌── Error Card ──────────────┐
│    ⛔                       │
│  Membership Expired        │
│  Your plan ended 3 days ago│
│  [Renew Now →]             │
└────────────────────────────┘
```

**Double scan (within 3 min):**
```
Shows same success card (check-in):
  ✅ Already Checked In
  "You checked in at 9:05 AM"
  (not an error — just confirmation)
```

---

# SCREEN-062: Join Flow

```
ID:       S062
Name:     Join Library Flow
Type:     Multi-step stack screen (no bottom nav)
Trigger:  Explore → Apply to Join
          OR Join with Code
          OR Scan Joining QR
Steps:    5 steps (Step 3 add-ons may be skipped)
```

**Progress header (all steps):**
```
┌─────────────────────────────┐
│ ← Join [Library Name]       │
│ Step 2 of 5                 │
│ ████████░░░░░░░  40%        │  ← orange progress bar
└─────────────────────────────┘
```

---

## Step 0 — Profile Check (auto, no screen shown)

```
App checks profile completeness.
If complete: auto-fill all form fields. Skip to Step 1.
If incomplete: collect inline. After join submitted, save to profile.
No blocking screen. Inline collection in Step 1.
```

---

## Step 1 — Existing Member?

```
┌─────────────────────────────┐
│ ← Join SILENCE Study Zone   │
│ Step 1 of 5  ████░░░░  20%  │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Question Card ────────┐ │  ← white card
│ │ Have you studied here   │ │    18px 600
│ │ before?                 │ │
│ │                         │ │
│ │ ┌─────────────────────┐ │ │
│ │ │  ✕  No, I'm new     │ │ │  ← selection cards
│ │ │  First time here    │ │ │    default selected
│ │ └─────────────────────┘ │ │    selected: orange border
│ │                         │ │
│ │ ┌─────────────────────┐ │ │
│ │ │  ✓  Yes, returning  │ │ │
│ │ │  I've been here     │ │ │
│ │ └─────────────────────┘ │ │
│ └─────────────────────────┘ │
│                             │
│ (If "Yes" selected):        │
│ ┌── Optional History ─────┐ │  ← slides in below
│ │ Joining Date (optional) │ │
│ │ [calendar picker]       │ │
│ │                         │ │
│ │ Plan Type (optional)    │ │
│ │ [Monthly ▾]             │ │
│ │                         │ │
│ │ Expiry Date (optional)  │ │
│ │ [calendar picker]       │ │
│ └─────────────────────────┘ │
│                             │
│ ── INLINE PROFILE (if incomplete) ──
│ ┌── Complete Your Details ┐ │
│ │ Full Name *             │ │
│ │ [text input]            │ │
│ │ Phone * (+91)           │ │
│ │ [text input]            │ │
│ │ Nickname (leaderboard)  │ │
│ │ [text input]            │ │
│ └─────────────────────────┘ │
│                             │
│ [  Next →  ]                │
└─────────────────────────────┘
```

---

## Step 2 — Shift & Plan

```
┌─────────────────────────────┐
│ Step 2 of 5  ████████ 40%   │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Select Shift ─────────┐ │
│ │ Choose a Shift          │ │    18px 600
│ │                         │ │
│ │ ┌─────────────────────┐ │ │  ← shift card, selectable
│ │ │ ☀ Morning Shift  ●  │ │ │    selected: orange border + fill
│ │ │ 6:00 AM – 2:00 PM   │ │ │    time 13px
│ │ │ ₹1,500/month        │ │ │    price 14px 600
│ │ │ 8 seats available   │ │ │    availability 12px green
│ │ └─────────────────────┘ │ │
│ │                         │ │
│ │ ┌─────────────────────┐ │ │
│ │ │ ☽ Evening Shift     │ │ │
│ │ │ 2:00 PM – 10:00 PM  │ │ │
│ │ │ ₹1,200/month        │ │ │
│ │ │ 3 seats available   │ │ │
│ │ └─────────────────────┘ │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Choose Plan ──────────┐ │
│ │                         │ │
│ │ (If trial available     │ │
│ │  AND not used before):  │ │
│ │ ┌─────────────────────┐ │ │  ← trial option card
│ │ │ 🆓 Free Trial       │ │ │    purple border
│ │ │ 7 days free         │ │ │
│ │ │ Try before you pay  │ │ │
│ │ └─────────────────────┘ │ │
│ │ ── or pay now ──        │ │  ← divider
│ │                         │ │
│ │ [Monthly  ₹1,500 ●]     │ │  ← plan pills
│ │ [3-Month  ₹4,000 ]      │ │    selected = orange
│ │ [6-Month  ₹7,500 ]      │ │
│ └─────────────────────────┘ │
│                             │
│ [  Next →  ]                │
└─────────────────────────────┘
```

---

## Step 3 — Add-ons (auto-skipped if none configured)

```
┌─────────────────────────────┐
│ Step 3 of 5  ████████████ 60%│
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Add-ons ──────────────┐ │
│ │ Extra Services          │ │    18px 600
│ │ (optional)              │ │    14px #6B7280
│ │                         │ │
│ │ ┌─────────────────────┐ │ │  ← add-on toggle cards
│ │ │ 🔒 Locker      [○]  │ │ │    toggle right side
│ │ │ ₹200/month          │ │ │
│ │ │ Deposit: ₹500 🔄    │ │ │    🔄 = refundable
│ │ └─────────────────────┘ │ │
│ │                         │ │
│ │ ┌─────────────────────┐ │ │
│ │ │ ❄️ AC Premium  [●]  │ │ │  ← selected: orange toggle
│ │ │ ₹300/month          │ │ │
│ │ │ No deposit          │ │ │
│ │ └─────────────────────┘ │ │
│ └─────────────────────────┘ │
│                             │
│ Selected Total: +₹300/month │  ← running total
│                             │
│ [  Next →  ]                │
└─────────────────────────────┘
```

---

## Step 4 — Payment (skipped entirely if trial selected in Step 2)

```
┌─────────────────────────────┐
│ Step 4 of 5  ██████████████ 80%│
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Payment Summary ──────┐ │  ← white card, read-only
│ │ Monthly Plan  ₹1,500    │ │
│ │ AC Premium    ₹300      │ │
│ │ ─────────────────────   │ │
│ │ Total         ₹1,800    │ │    bold 18px
│ └─────────────────────────┘ │
│                             │
│ ┌── Payment Method ───────┐ │
│ │ How will you pay?       │ │
│ │                         │ │
│ │ ┌──────────────────────┐│ │  ← method cards
│ │ │ 💵 Cash        ●    ││ │    selected = orange border
│ │ │ Pay at library      ││ │
│ │ └──────────────────────┘│ │
│ │                         │ │
│ │ ┌──────────────────────┐│ │
│ │ │ 📱 UPI              ││ │
│ │ │ Pay via UPI         ││ │
│ │ └──────────────────────┘│ │
│ └─────────────────────────┘ │
│                             │
│ (If UPI selected):          │
│ ┌── UPI Payment ──────────┐ │
│ │ Admin's UPI IDs:        │ │
│ │ 9876543210@paytm        │ │    monospace
│ │ ashish@ybl              │ │
│ │                         │ │
│ │ Pay using:              │ │
│ │ [PhonePe][GPay][Paytm]  │ │  ← colored app icons, 44px
│ │ [Amazon Pay]            │ │    deep-link on tap
│ │                         │ │
│ │ Upload Screenshot *     │ │
│ │ ┌────────────────────┐  │ │
│ │ │ [📤 Upload / Tap]  │  │ │  ← dashed border upload area
│ │ │ Screenshot of      │  │ │    80×80px after upload
│ │ │ payment            │  │ │
│ │ └────────────────────┘  │ │
│ │                         │ │
│ │ UPI Sender Name *       │ │
│ │ ┌────────────────────┐  │ │
│ │ │ Rahul Sharma       │  │ │  ← required field
│ │ └────────────────────┘  │ │
│ │ ℹ Helps admin verify    │ │  ← helper 12px #6B7280
│ │   your payment faster   │ │
│ └─────────────────────────┘ │
│                             │
│ [  Next →  ]                │
└─────────────────────────────┘
```

---

## Step 5 — Review & Submit

```
┌─────────────────────────────┐
│ Step 5 of 5  ████████████████│
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Review Your Application ┐│
│ │ Library                   ││
│ │ SILENCE Study Zone      │ │
│ │                         │ │
│ │ Shift                   │ │
│ │ Morning (6AM – 2PM)     │ │
│ │                         │ │
│ │ Plan                    │ │
│ │ Monthly • ₹1,500        │ │
│ │                         │ │
│ │ Add-ons                 │ │
│ │ AC Premium • ₹300/month │ │
│ │                         │ │
│ │ Payment                 │ │
│ │ UPI • Screenshot ✓      │ │
│ │ Sender: Rahul Sharma    │ │
│ │                         │ │
│ │ Total: ₹1,800/month     │ │    bold orange
│ │                         │ │
│ │ Referral Code           │ │  ← optional field
│ │ [REF-A3K9-7XP      ]    │ │    if library has referrals active
│ └─────────────────────────┘ │
│                             │
│ [  Submit Application  ]    │  ← orange full width
└─────────────────────────────┘
```

**After Submit — Confirmation Screen:**
```
┌─────────────────────────────┐
│ [centered content]          │
│                             │
│          📋                 │  ← clipboard illustration
│                             │
│   Application Submitted!    │  ← 22px 700
│                             │
│   Your payment is under     │
│   review. Admin typically   │
│   confirms within 24 hours. │  ← 14px #6B7280 center
│                             │
│   Status: Payment Pending   │  ← amber badge
│                             │
│ [  Go to Home  ]            │  ← orange button
│ [View Application]          │  ← text link
└─────────────────────────────┘
```

---

# SCREEN-063: Member Analytics Tab

```
ID:       S063
Name:     Member Analytics
Route:    /member/analytics
```

**Full Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│          Analytics          │
├─────────────────────────────┤
│ [Today][This Week][This Month●][All Time] │  ← date filter
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Summary Cards ────────┐ │  ← 2×2 grid
│ │ ┌──────────┐┌──────────┐│ │
│ │ │ 22       ││ 8        ││ │    value 24px 700
│ │ │ Days     ││ Days     ││ │    label 11px #6B7280
│ │ │ Present  ││ Absent   ││ │
│ │ │ ↑ +12%  ││ ↓ -8%   ││ │  ← trend: 11px green/red
│ │ │ vs last m││vs last m ││ │    tappable → comparison popup
│ │ └──────────┘└──────────┘│ │
│ │ ┌──────────┐┌──────────┐│ │
│ │ │ 42h      ││ 73%      ││ │
│ │ │ Total    ││ Attend-  ││ │
│ │ │ Hours    ││ ance     ││ │
│ │ │ ↑ +5h   ││ ↑ +3%   ││ │
│ │ └──────────┘└──────────┘│ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Streak Card ──────────┐ │  ← orange card, prominent
│ │ [SILENCE Study Zone ▾]  │ │  ← library selector (if 2+ libs)
│ │                         │ │
│ │        🔥               │ │    flame emoji 32px
│ │        12               │ │    current streak: 48px 800
│ │   Day Streak            │ │    14px below
│ │                         │ │
│ │  Best: 28 days          │ │    12px white 80%
│ │                         │ │
│ │ ℹ Incomplete sessions   │ │  ← tiny note 11px white 70%
│ │   don't count for hours │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Leaderboard ──────────┐ │  ← white card
│ │ Leaderboard             │ │
│ │ [SILENCE Study Zone ▾]  │ │  ← library selector
│ │ [This Week][This Month●][All]│  ← period toggle
│ │                         │ │
│ │ 🥇 Priya S.    48h  +2h │ │  ← rank + nickname + hours + trend
│ │ 🥈 Rohit K.    45h      │ │
│ │ 🥉 Ananya G.   42h      │ │
│ │    Dev M.      38h      │ │
│ │    Sneha P.    35h      │ │
│ │ ─────────────────────   │ │  ← separator if user not in top 5
│ │ 8th You (Rahul) 22h     │ │  ← highlighted in orange bg
│ │         Gap: -13h to #5 │ │    gap to top 5
│ └─────────────────────────┘ │
│                             │
│ ┌── Badges ───────────────┐ │  ← horizontal scroll row
│ │ Earned Badges           │ │
│ │                         │ │
│ │ [🔥][💯]  [⏰] ...      │ │  ← earned: full color circle
│ │ 7d  30d  Early ...      │ │    unearned: gray circle
│ │ Apr May   ?             │ │    earned date below earned ones
│ └─────────────────────────┘ │
│                             │
│ ┌── Study Hours Chart ────┐ │  ← bar chart
│ │ Daily Study Hours       │ │
│ │ [BAR CHART 180px]       │ │    orange bars
│ │ Mo Tu We Th Fr Sa Su    │ │    today slightly darker
│ └─────────────────────────┘ │
│                             │
│ ┌── Calendar Heatmap ─────┐ │
│ │ May 2025       ◀ ▶      │ │  ← month nav
│ │ Su Mo Tu We Th Fr Sa    │ │
│ │ [1][2●][3●][4 ][5●]...  │ │    ● = any hours (orange dot)
│ │                         │ │    tap → day popup
│ │ Legend:                 │ │
│ │ ⬜ No study  🟧 1-2h    │ │
│ │ 🟥 4h+ study            │ │    (orange shades)
│ └─────────────────────────┘ │
│                             │
│ [Export My Attendance CSV]  │  ← outlined button, full width
└─────────────────────────────┘
```

**Trend comparison popup (on tap of trend indicator):**
```
Bottom sheet:
  "This month vs Last month"
  [Metric]: This month X | Last month Y | Diff: +Z
  Simple 2-bar comparison visual
  [Close]
```

**Day tap popup (calendar heatmap):**
```
Overlay card on the tapped day cell:
  Date: Wednesday, 14 May
  Check-in: 9:05 AM
  Check-out: 5:30 PM
  Total: 8h 25m
  Session type: Normal
  Library: SILENCE Study Zone
  [×] close
```

**Badge detail (on tap):**
```
Bottom sheet:
  [full color or gray icon — 80px]
  Badge Name — 20px 700
  Condition: "7 consecutive study days"
  Status: Earned on 12 Apr 2025 (green)
         OR "3 of 7 days completed" + progress bar (gray)
  [Close]
```

---

# SCREEN-064: Member Profile Tab

```
ID:       S064
Name:     Member Profile
Route:    /member/profile
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│          Profile            │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Profile Header ───────┐ │  ← white card
│ │    [PHOTO 80px]         │ │    orange ring border
│ │    Rahul Sharma         │ │    20px 700
│ │    @rahulstudy          │ │    nickname, 14px #6B7280
│ │    [UPSC]               │ │    exam category badge
│ │    [Edit Profile →]     │ │    orange text button
│ └─────────────────────────┘ │
│                             │
│ ┌── Refer a Friend ───────┐ │  ← white card
│ │ 🎁 Refer a Friend       │ │
│ │ REF-A3K9-7XP            │ │    monospace code, orange
│ │ [Copy Code] [Share 📤]  │ │
│ │                         │ │
│ │ You've referred 3 members│ │    12px #6B7280
│ │ Rewards: 9 free days ✓  │ │    green if rewarded
│ └─────────────────────────┘ │
│                             │
│ ┌── Joined Libraries ─────┐ │
│ │ Active Memberships      │ │    section label
│ │                         │ │
│ │ ┌─────────────────────┐ │ │  ← library row
│ │ │ [📸] SILENCE Zone ✓ │ │ │    photo + name + verified
│ │ │ Active • 4 days left│ │ │    status + days
│ │ │ [📸][▶][💬]         │ │ │  ← social link icons
│ │ └─────────────────────┘ │ │
│ │                         │ │
│ │ [+ Join Another Library]│ │    orange text button → Explore
│ └─────────────────────────┘ │
│                             │
│ ┌── Past Libraries ───────┐ │  ← only if has exited libraries
│ │ Past Libraries          │ │
│ │                         │ │
│ │ ┌─────────────────────┐ │ │
│ │ │ City Center Library │ │ │
│ │ │ Exited 10 Mar 2025  │ │ │
│ │ │ [8 Months]          │ │ │  ← duration pill
│ │ └─────────────────────┘ │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Account ──────────────┐ │
│ │ Verify Phone           >│ │  ← optional, shows if not verified
│ │ Help & Support         >│ │
│ │ Terms & Conditions     >│ │
│ │ Privacy Policy         >│ │
│ └─────────────────────────┘ │
│                             │
│ 🚪 Logout                  │  ← red text
└─────────────────────────────┘
```

---

# SCREEN-065: Member Edit Profile

```
ID:       S065
Name:     Edit Profile (Member)
Route:    /member/profile/edit
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Edit Profile              │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Photo ────────────────┐ │
│ │ [PHOTO CIRCLE 96px]     │ │    orange ring
│ │ [Take Photo][Gallery]   │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Personal Details ─────┐ │
│ │ Full Name *             │ │
│ │ [Rahul Sharma         ] │ │
│ │                         │ │
│ │ Nickname (leaderboard)  │ │
│ │ [rahulstudy           ] │ │    shown in leaderboard
│ │                         │ │
│ │ Phone                   │ │
│ │ [+91][9876543210      ] │ │
│ │ [Verify →] (if unverif) │ │  ← OTP verify link
│ │                         │ │
│ │ Email                   │ │
│ │ [rahul@gmail.com      ] │ │
│ │ [Verify →] (if unverif) │ │
│ │                         │ │
│ │ Gender                  │ │
│ │ [Male ●][Female][Other] │ │
│ │                         │ │
│ │ Date of Birth           │ │
│ │ [12 May 1998       📅]  │ │    calendar picker
│ │                         │ │
│ │ Address                 │ │
│ │ [textarea              ]│ │
│ │                         │ │
│ │ Exam Category           │ │
│ │ [UPSC                 ▾]│ │    dropdown
│ └─────────────────────────┘ │
│                             │
│ ┌── ID Documents ─────────┐ │
│ │ [Aadhaar ✓][PAN: pending]│ │  ← uploaded docs status
│ │ [+ Add Document]        │ │
│ └─────────────────────────┘ │
│                             │
│ [  Save Changes  ]          │  ← orange button
└─────────────────────────────┘
```

---

# SCREEN-066: Notifications Screen

```
ID:       S066
Name:     Notifications
Route:    /notifications
Role:     Admin + Member (same screen, different content)
Entry:    Bell icon in header
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Notifications  [Mark All] │  ← mark all read right
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ── TODAY ──                 │  ← date group header, 12px caps #9CA3AF
│                             │
│ ┌── Notification Row ─────┐ │  ← UNREAD: #FFF3ED bg tint
│ │ 🟢 Join Approved        │ │    colored icon square 40px
│ │ Approved! Seat G-A-05   │ │    title 14px 600 #1A1A2E
│ │ at SILENCE Study Zone.  │ │    body 13px #374151
│ │                  2h ago │ │    time right, 11px #9CA3AF
│ │ [unread orange dot left]│ │    3px orange left border
│ └─────────────────────────┘ │
│                             │
│ ┌── Notification Row ─────┐ │  ← READ: white bg
│ │ 💰 Payment Confirmed    │ │
│ │ ₹1,500 confirmed at     │ │
│ │ SILENCE. Ref: A3K9M2    │ │
│ │                  5h ago │ │    no orange dot
│ └─────────────────────────┘ │
│                             │
│ ── YESTERDAY ──             │  ← date group header
│                             │
│ ┌── Notification Row ─────┐ │
│ │ 🔥 Badge Earned!        │ │
│ │ You earned 7-Day Streak!│ │
│ │ Check Analytics.        │ │
│ │                 1d ago  │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Empty State ──────────┐ │
│ │       🔔                │ │    bell icon 64px
│ │  You're all caught up!  │ │    14px #9CA3AF
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

**Notification icon colors by type:**
```
Join approved:      #22C55E  green
Join rejected:      #EF4444  red
Payment confirmed:  #22C55E  green
Payment rejected:   #EF4444  red
Payment pending:    #F59E0B  amber
Expiry warning:     #F59E0B  amber
Badge earned:       #E65C00  orange
Announcement:       #3B82F6  blue
QR/scan:            #8B5CF6  purple
Hold:               #D97706  amber
Referral:           #10B981  teal
Transfer:           #6366F1  indigo
```

**Tap behavior:**
- Mark as read
- Navigate to deep link:
  - Join approved → My Library card
  - Payment confirmed → Payments tab in membership detail
  - Badge earned → Analytics tab
  - Announcement → Home announcements section
  - Join request (admin) → Reservations → Requests tab

---

# SCREEN-067: Member — Seat Change Request

```
ID:       S067
Name:     Seat Change Request Bottom Sheet
Type:     Bottom sheet
Trigger:  Membership card → [Seat Change] button
```

**Layout:**
```
┌─────────────────────────────┐
│ ┌── Bottom Sheet ─────────┐ │
│ │ Request Seat Change     │ │    18px 600
│ │ SILENCE Study Zone  ✕  │ │    library name + close
│ │ ──────────────────────  │ │
│ │                         │ │
│ │ Current Seat            │ │    12px label
│ │ [G-A-12]                │ │    blue pill, read-only
│ │                         │ │
│ │ Reason *                │ │
│ │ ┌────────────────────┐  │ │
│ │ │ Current seat has   │  │ │    textarea, 100px
│ │ │ poor lighting...   │  │ │    max 200 chars
│ │ │              180/200│  │ │    counter
│ │ └────────────────────┘  │ │
│ │ e.g. need window seat   │ │    placeholder hint
│ │                         │ │
│ │ Preferred Section       │ │
│ │ [General Study      ▾]  │ │    dropdown, optional
│ │ (optional)              │ │    12px hint
│ │                         │ │
│ │ ℹ Admin will assign the │ │  ← info box, light bg
│ │   best available seat.  │ │
│ │                         │ │
│ │ [Cancel]  [Submit →]    │ │  ← Cancel: outlined, Submit: orange
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

---

# SCREEN-068: Member — Hold Request

```
ID:       S068
Name:     Hold Request Bottom Sheet
Type:     Bottom sheet
Trigger:  Membership card → More ▼ → Request Hold
```

**Layout:**
```
┌─────────────────────────────┐
│ ┌── Bottom Sheet ─────────┐ │
│ │ Pause Membership    ✕   │ │    18px 600
│ │ SILENCE Study Zone      │ │
│ │ ──────────────────────  │ │
│ │                         │ │
│ │ Reason *                │ │
│ │ ┌────────────────────┐  │ │
│ │ │ Appearing in board │  │ │    100px textarea
│ │ │ exams for 2 weeks  │  │ │
│ │ └────────────────────┘  │ │
│ │                         │ │
│ │ Hold Start Date *       │ │
│ │ [Tomorrow, 20 May  📅]  │ │    min: tomorrow
│ │                         │ │
│ │ Hold End Date *         │ │
│ │ [3 Jun 2025        📅]  │ │    max: 30 days from start
│ │                         │ │
│ │ ┌── Info Box ─────────┐ │ │  ← cream bg, orange border
│ │ │ ● Seat stays reserved│ │ │
│ │ │ ● Billing pauses    │ │ │
│ │ │ ● Expiry extends    │ │ │    checkmarks or bullets
│ │ │   by hold duration  │ │ │
│ │ └─────────────────────┘ │ │
│ │                         │ │
│ │ [Cancel]  [Submit →]    │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

---

# SCREEN-069: Exit Library Confirmation

```
ID:       S069
Name:     Exit Library (Two-step)
Type:     Two bottom sheets in sequence
Trigger:  Membership card → More ▼ → Exit Library
```

**Step 1 — Warning:**
```
┌── Bottom Sheet ─────────────┐
│ Exit Library?               │  ← 18px 600
│ SILENCE Study Zone          │
│ ─────────────────────────── │
│                             │
│ This will:                  │  ← 14px #374151
│ ✗ Free your seat G-A-12     │  ← red × bullets
│ ✗ End your membership       │
│ ✗ Lose 4 remaining days     │
│                             │
│ ✓ History preserved         │  ← green ✓
│ ✓ Badges kept               │
│                             │
│ [Cancel]   [Yes, Exit →]    │
└─────────────────────────────┘
```

**Step 2 — Final Confirm (appears 1 second after Step 1):**
```
┌── Bottom Sheet (RED TINT) ──┐
│ ⚠️ Final Confirmation       │  ← amber icon
│ ─────────────────────────── │
│                             │
│ This cannot be undone.      │  ← 14px, bold
│ Your seat will be freed     │
│ immediately.                │
│                             │
│ [← Cancel]  [Confirm Exit] │  ← Confirm: red button
└─────────────────────────────┘
```

**Dues blocking (if dues > 0):**
```
Instead of Step 1, show:
┌── Bottom Sheet ─────────────┐
│ ⚠️ Cannot Exit              │
│ ─────────────────────────── │
│ You have ₹500 in pending    │
│ dues at SILENCE Study Zone. │
│                             │
│ Please clear dues before    │
│ exiting, or contact your    │
│ library admin.              │
│                             │
│ [Close]   [Contact Library] │
└─────────────────────────────┘
```

---

# SCREEN-070: Library Query Composer

```
ID:       S070
Name:     Library Query
Route:    /member/query/:libraryId
Trigger:  Membership card → More → Contact Library
          OR Scan fail → [Report via Queries]
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Contact Library           │
│ SILENCE Study Zone          │
├─────────────────────────────┤
│ [WHITE BODY — #FBF5EE]      │
│                             │
│ (Past queries if any)       │
│ ┌── Message Bubble ───────┐ │  ← member messages: right, orange
│ │ "My QR not scanning..." │ │
│ │                5:02 PM  │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Reply Bubble ─────────┐ │  ← admin replies: left, white
│ │ "Please update app...   │ │
│ │                6:15 PM  │ │
│ └─────────────────────────┘ │
│                             │
│ ────────────────────────    │  ← spacer
│                             │
│ ┌── Input Row ────────────┐ │  ← fixed at bottom
│ │ [Type your message... ] │ │    text input
│ │                    [→]  │ │    send button (orange arrow)
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

---

# SCREEN-071: Manage Layout Bottom Sheet

```
ID:       S071
Name:     Manage Layout Modal
Type:     Bottom sheet
Trigger:  Reservations → Layout → [Manage] pill button
```

**Layout (from screenshot):**
```
┌─────────────────────────────┐
│ ┌── Bottom Sheet ─────────┐ │
│ │ Manage Layout       ✕   │ │
│ │ ──────────────────────  │ │
│ │                         │ │
│ │ FLOORS                  │ │  ← section label 11px caps #6B7280
│ │                         │ │
│ │ + Add Floor             │ │  ← orange + icon left
│ │ ✏ Rename Floor          │ │
│ │ 🗑 Delete Floor         │ │  ← red text
│ │                         │ │
│ │ SECTIONS                │ │
│ │                         │ │
│ │ + Add Section           │ │
│ │ ✏ Edit Section          │ │
│ │ 🗑 Delete Section       │ │
│ │                         │ │
│ │ SEATS                   │ │
│ │                         │ │
│ │ ⬛ Generate Seats        │ │
│ │ + Add Seat              │ │
│ │ ☑ Bulk Actions          │ │
│ │                         │ │
│ │ TOOLS                   │ │
│ │                         │ │
│ │ 📤 Export Layout        │ │
│ │ 🔄 Reset Empty Seats    │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

---

# SCREEN-072: Generate Seats Bottom Sheet

```
ID:       S072
Name:     Generate Seats Modal
Type:     Bottom sheet with tab switcher
Trigger:  + dashed seat button OR Manage Layout → Generate Seats
```

**Layout:**
```
┌─────────────────────────────┐
│ ┌── Bottom Sheet ─────────┐ │
│ │ Generate Seats      ✕   │ │
│ │ Ground Floor → General  │ │  ← breadcrumb, 12px #6B7280
│ │ ──────────────────────  │ │
│ │ [Bulk Generate●][Single]│ │  ← tab switcher
│ │                         │ │
│ │ ── BULK GENERATE ──     │ │
│ │                         │ │
│ │ Prefix                  │ │
│ │ ┌────────┐              │ │
│ │ │ G-A    │              │ │    e.g. G-A → G-A-01, G-A-02
│ │ └────────┘              │ │
│ │ Seats will be G-A-01... │ │    12px helper text
│ │                         │ │
│ │ From    To              │ │
│ │ ┌────┐  ┌────┐          │ │    side by side numbers
│ │ │ 1  │  │ 20 │          │ │
│ │ └────┘  └────┘          │ │
│ │ Will generate 20 seats  │ │    auto-calc, 12px orange
│ │                         │ │
│ │ Number format:          │ │
│ │ [01 02 03 ●] [1 2 3]   │ │    two pills
│ │                         │ │
│ │ ┌── Preview ──────────┐ │ │  ← gray bg box
│ │ │ [G-A-01][G-A-02]    │ │ │    first 6 as colored squares
│ │ │ [G-A-03][G-A-04]    │ │ │    + "...and 14 more" text
│ │ │ [G-A-05][G-A-06]    │ │ │
│ │ │ ...and 14 more      │ │ │
│ │ └─────────────────────┘ │ │
│ │                         │ │
│ │ Assign to section?      │ │
│ │ [Yes ●] [No]            │ │    toggle
│ │ [General Study      ▾]  │ │    section dropdown (if Yes)
│ │                         │ │
│ │ [Generate 20 Seats]     │ │  ← orange full width
│ │                         │ │
│ │ ── SINGLE SEAT ──       │ │  ← alternate tab
│ │ Prefix + Number         │ │
│ │ [G-A  ][  25]           │ │
│ │ Preview: G-A-25         │ │
│ │ [Add Seat]              │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

---

# SCREEN-073: Add Expenditure Bottom Sheet

```
ID:       S073
Name:     Add Expenditure
Type:     Bottom sheet
Trigger:  Analytics → [+ Add Expense] inline button
```

**Layout:**
```
┌─────────────────────────────┐
│ ┌── Bottom Sheet ─────────┐ │
│ │ Add Expense         ✕   │ │
│ │ ──────────────────────  │ │
│ │                         │ │
│ │ Library (if All Libs)   │ │  ← dropdown, only in All Libraries view
│ │ [SILENCE Study Zone ▾]  │ │
│ │                         │ │
│ │ Amount *                │ │
│ │ ₹ [2,000            ]   │ │    ₹ prefix, number input
│ │                         │ │
│ │ Category *              │ │
│ │ [Electricity        ▾]  │ │    full category list dropdown
│ │                         │ │
│ │ Date                    │ │
│ │ [19 May 2025       📅]  │ │    defaults to today
│ │                         │ │
│ │ Note (optional)         │ │
│ │ [Monthly electricity bil]│ │    single line
│ │                         │ │
│ │ [📎 Attach Receipt]     │ │  ← optional photo attach
│ │                         │ │
│ │ [Mark as recurring ○]   │ │  ← toggle: monthly recurring
│ │                         │ │
│ │ [  Save Expense  ]      │ │  ← orange full width
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

---

# SCREEN-074: Critical Action Confirmation Bottom Sheets

```
ID:       S074
Name:     Critical Action Confirmations
Type:     Bottom sheets (reusable pattern)
```

**Pattern — Type to Confirm (for destructive admin actions):**
```
Used for: QR Regeneration, Remove Member, Delete Seat, 
          Library Closure, Account Deletion

┌── Bottom Sheet ─────────────┐
│ ⚠️ [Action Name]            │  ← amber icon + title 18px 600
│ ─────────────────────────── │
│                             │
│ [Specific warning text      │  ← describes exactly what happens
│  about this action]         │
│                             │
│ Type "[KEYWORD]" to confirm │  ← instruction 13px
│ ┌────────────────────────┐  │
│ │                        │  │  ← text input
│ │ [red border if wrong]  │  │    green border if correct
│ └────────────────────────┘  │
│                             │
│ [Cancel]  [Confirm]         │  ← Confirm: red, disabled until keyword correct
└─────────────────────────────┘
```

**Keywords by action:**
```
QR Regeneration:  "REGENERATE"
Remove Member:    "REMOVE"
Delete Seat:      "DELETE"
Library Closure:  [library name itself]
Account Delete:   "DELETE MY ACCOUNT"
```

---

# SCREEN-075: Seat Picker (Cinema Grid Modal)

```
ID:       S075
Name:     Seat Picker Modal
Type:     Full-screen modal (not bottom sheet — needs space for grid)
Trigger:  Approve join request → select seat
          OR Renewal → shift changed → select seat
```

**Layout:**
```
┌─────────────────────────────┐
│ Select a Seat           ✕   │  ← header row
│ Morning Shift           │   │  ← shift name
│ Vacant seats only shown │   │  ← 12px hint #6B7280
├─────────────────────────────┤
│                             │
│ [🔍 Search seat...    ]     │  ← search bar
│                             │
│ General Study               │  ← section header
│ ┌──┐┌──┐┌──┐┌──┐┌──┐┌──┐   │  ← ONLY vacant shown as green
│ │G-A│G-A│G-A│G-A│G-A│   │   │    occupied seats shown grayed
│ │01 │02 │05 │07 │09 │   │   │    (greyed = cannot tap)
│ └🟢┘└🟢┘└🟢┘└🟢┘└🟢┘       │
│                             │
│ Girls Section               │
│ ┌──┐┌──┐┌──┐               │
│ │G-B│G-B│G-B│               │
│ └🟢┘└🟢┘└🟢┘               │
│                             │
│ ── Selected: G-A-05 ──      │  ← appears after selection
│ [Confirm: Assign G-A-05]    │  ← orange full width button
│ [Cancel Selection]          │  ← text button
└─────────────────────────────┘
```

---

# SCREEN-076: Day Attendance Popup (Calendar Tap)

```
ID:       S076
Name:     Day Attendance Popup
Type:     Small overlay popup on calendar tap
```

```
┌── Popup ────────────────────┐
│ Wednesday, 14 May           │  ← date, 14px 600
│ ─────────────────────────── │
│ Check-in:   9:05 AM         │
│ Check-out:  5:30 PM         │
│ Duration:   8h 25m          │
│ Type:       Normal          │  ← session type
│ Library:    SILENCE Study Z.│  ← if multi-library
│                         ✕   │  ← close
└─────────────────────────────┘
```

Admin version of this popup (Member Detail → Attendance tab):
```
Same info + [Edit Duration] button at bottom → opens edit form
```

---

# COMPONENT LIBRARY — Reusable Components

## StatusBadge
```
Props: status (string)
Variants:
  Active:      green bg #DCFCE7,  text #16A34A,  "Active"
  Expiring:    amber bg #FEF3C7,  text #D97706,  "Expiring"
  Expired:     red bg #FEE2E2,    text #DC2626,  "Expired"
  Hold:        amber bg #FEF3C7,  text #D97706,  "On Hold"
  Trial:       purple bg #EDE9FE, text #7C3AED,  "Trial"
  Pending:     gray bg #F3F4F6,   text #6B7280,  "Pending"
  Transfer:    blue bg #DBEAFE,   text #1D4ED8,  "Transferred"

Size: 24px height, 8px horizontal padding, 6px radius
Font: 11px weight 600 uppercase
```

## SeatPill
```
Props: label (string), shift (optional)
Variants:
  Active shift:   #E65C00 bg, white text
  Default:        #FFF3ED bg, #E65C00 text, orange border
Size: 28px height, 8px padding, 6px radius
Font: 12px weight 600
```

## Toast
```
Position: top center, below status bar
Animation: slides down, fades after 3s
Variants:
  Success: green bg #22C55E, white text, ✓ icon
  Error:   red bg #EF4444, white text, ✕ icon
  Info:    #1A1A2E bg, white text, ℹ icon
Size: auto width, 44px height, 12px padding, 20px radius
```

## EmptyState
```
Props: icon (emoji or illustration), title, subtitle (optional), action (optional)
Layout: centered vertically in available space
  Icon: 64px
  Title: 16px 600 #374151
  Subtitle: 13px #9CA3AF
  Action button: optional orange outlined
```

## SkeletonCard
```
Used during loading state for all cards
Animated shimmer: gray #E5E7EB with lighter #F3F4F6 moving highlight
Shape: matches the card it replaces (same height, rounded corners)
```

## BottomSheetWrapper
```
Overlay: rgba(0,0,0,0.4) behind sheet
Sheet: white, radius 20px top-left and top-right
Drag handle: 4px × 36px, #E5E7EB, centered top
Animation: slides up from bottom 300ms ease-out
Dismiss: tap overlay OR drag down
```

---

# NAVIGATION MAP — Complete

```
ADMIN NAVIGATION TREE:

/admin/home                    ← Admin Home (S010)
  → /admin/library/setup/1    ← Library Setup Stage 1 (S021)
  → /admin/library/setup/2    ← Library Setup Stage 2 (S022)
  → /admin/library/setup/3    ← Library Setup Stage 3 (S023)
  → /admin/member/add         ← Add Member Wizard (S036)
  [modal] QR Modal             ← QR Code Modal (S011)
  [bottomsheet] Announcements  ← Composer (S040)

/admin/reservations            ← Reservations Tab
  /layout                     ← Layout (S030)
    [bottomsheet] SeatActions  ← Occupied/Vacant (S031)
    [bottomsheet] ManageLayout ← Manage Modal (S071)
    [bottomsheet] GenerateSeats← Generate (S072)
    [modal] SeatPicker         ← Seat Picker (S075)
  /members                    ← Members (S032)
    → /admin/member/:id       ← Member Detail (S033)
      → /admin/member/:id/renew ← Renewal (S037)
    → /admin/member/add       ← Add Member Wizard (S036)
  /requests                   ← Requests (S034)
    [modal] SeatPicker         ← For approval
  /archive                    ← Archive (S035)

/admin/analytics               ← Analytics (S038)
  [bottomsheet] AddExpense     ← Add Expenditure (S073)

/admin/profile                 ← Profile (S039)
  → /admin/profile/complete    ← Complete Profile (S020)
  → /admin/library/:id/profile ← Library Profile (S043)
  → /admin/libraries           ← Library List
  → /admin/settings/business-rules ← Business Rules (S044)
  → /admin/settings/shifts     ← Shift Management (S045)
  → /admin/settings/pricing    ← Pricing Plans (S046)
  → /admin/settings/branding   ← Branding (S047)
  → /admin/settings/qr         ← QR Assets (S048)
  → /admin/settings/notifications ← Notifications (S051)
  → /admin/settings/addons     ← Add-on Services (S057)
  → /admin/settings/closures   ← Scheduled Closures (S056)
  → /admin/subscription        ← Subscription (S050)
  → /admin/announcements       ← Announcement History (S041)
  → /admin/exports             ← Export Center (S049)
  → /admin/queries             ← Manage Queries (S042)
  → /admin/audit-log           ← Audit Log (S055)
  → /admin/settings/referrals  ← Referral Settings (S058)
  → /admin/verified-badge      ← Verified Badge (S054)
  → /admin/support             ← Support & Help (S052)
  → /admin/about               ← About & Legal (S053)

MEMBER NAVIGATION TREE:

/member/home                   ← Member Home (S060)
  → /member/scan               ← QR Scanner (S061)
  → /member/join/:libraryId    ← Join Flow (S062)
  [bottomsheet] SeatChange     ← Seat Change (S067)
  [bottomsheet] HoldRequest    ← Hold Request (S068)
  [bottomsheet] ExitLibrary    ← Exit Confirm (S069)
  [bottomsheet] JoinWithCode   ← Code Entry

/member/analytics              ← Analytics (S063)

/member/profile                ← Profile (S064)
  → /member/profile/edit      ← Edit Profile (S065)
  → /member/query/:libraryId  ← Query (S070)

SHARED:
/notifications                 ← Notifications (S066)
/auth                          ← Auth (S002)
/role-select                   ← Role Selection (S003)
```

---

*Screen-by-Screen Specification — COMPLETE*
*Total screens specified: 76 (including variants and modals)*
*Parts: 1 (Auth + Admin Home + Reservations) · 2 (Settings + Library Profile) · 3 (Member + QR + Join + Shared)*
*UI Reference: Login mockup · Role Selection · Reservations grid · Profile screens · Home actions strip*
