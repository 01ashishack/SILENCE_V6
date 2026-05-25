# SILENCE App — Screen-by-Screen Specification
## Part 1 of 3: Auth · Onboarding · Admin Home · Reservations

**Version:** 1.0 | **For:** Antigravity No-Code Build  
**UI Reference:** Screenshots provided (Login, Role Selection, Reservations, Profile, Home)

---

## DESIGN TOKENS (use everywhere)

```
COLORS
  Background (app base):  #FBF5EE   ← warm cream, NOT white
  Primary Orange:         #E65C00
  Orange Light Tint:      #FFF3ED
  Orange Dark:            #C44E00
  White (cards):          #FFFFFF
  Text Primary:           #1A1A2E
  Text Secondary:         #6B7280
  Text Muted:             #9CA3AF
  Border Light:           #E5E7EB
  Success Green:          #22C55E
  Green Light:            #DCFCE7
  Warning Amber:          #F59E0B
  Amber Light:            #FEF3C7
  Error Red:              #EF4444
  Red Light:              #FEE2E2
  Hold Amber (seat):      #D97706
  Trial Purple:           #7C3AED
  Purple Light:           #EDE9FE
  Blue (occupied seat):   #3B82F6
  Blue Light:             #DBEAFE

TYPOGRAPHY
  Font family:    System default (Inter / SF Pro on iOS, Roboto on Android)
  H1 (screen title):   22px, weight 700, #1A1A2E
  H2 (section head):   18px, weight 600, #1A1A2E
  H3 (card title):     16px, weight 600, #1A1A2E
  Body:                14px, weight 400, #374151
  Small:               12px, weight 400, #6B7280
  Caption:             11px, weight 400, #9CA3AF
  Badge text:          11px, weight 600
  Seat label:          10px, weight 700, #FFFFFF
  Library code:        18px, weight 700, monospace, #E65C00
  Header name:         15px, weight 700, #FFFFFF
  Header subtext:      11px, weight 400, rgba(255,255,255,0.75)

SPACING
  xs: 4px | sm: 8px | md: 16px | lg: 24px | xl: 32px | 2xl: 48px

BORDER RADIUS
  Small (badges, chips): 6px
  Medium (inputs, cards): 12px
  Large (bottom sheets):  20px top corners only
  Header bottom:          28px
  Button:                 12px
  Circular (avatars):     50%

SHADOWS
  Card:    0px 1px 3px rgba(0,0,0,0.08), 0px 1px 2px rgba(0,0,0,0.06)
  Modal:   0px 20px 60px rgba(0,0,0,0.15)
  Button:  0px 4px 12px rgba(230,92,0,0.3)

BOTTOM NAVIGATION HEIGHT: 64px (safe area + 64px)
HEADER HEIGHT: 100px (status bar + content)
STATUS BAR ICONS: white on orange header, dark on cream background
```

---

# SCREEN-001: Splash Screen

```
ID:       S001
Name:     Splash Screen
Route:    / (initial load)
Role:     All users
Duration: ~1.5 seconds
```

**Layout:**
```
┌─────────────────────────────┐
│  [Status bar — dark icons]  │
│                             │
│                             │
│                             │
│       [SILENCE LOGO]        │  ← book + person illustration, orange
│         Silence             │  ← 32px, weight 800, #1A1A2E
│  Library Management & QR    │  ← 13px, #6B7280, letter-spacing 1px
│                             │
│                             │
│       [spinner — orange]    │  ← circular, 24px, #E65C00
│                             │
└─────────────────────────────┘
```

**Background:** `#FBF5EE`

**Logic:**
1. Check Supabase Auth session
2. If no session → S002 (Auth)
3. If session + no role → S003 (Role Selection)
4. If session + role = admin → check library count
   - library count = 0 → S010 (Admin Home) with Stage 1 modal forced open
   - library count > 0 → S010 (Admin Home)
5. If session + role = member → S040 (Member Home)

**States:** Single state. No loading skeleton needed (brief).

---

# SCREEN-002: Auth Screen

```
ID:       S002
Name:     Auth Screen
Route:    /auth
Role:     Unauthenticated users
```

**Layout:**
```
┌─────────────────────────────┐
│  [Status bar — dark icons]  │
│  Background: #FBF5EE        │
│                             │
│       [SILENCE LOGO]        │  ← 80px tall illustration
│         Silence             │  ← 32px, 800 weight, #1A1A2E
│  ── LIBRARY MANAGEMENT ──   │  ← 11px, caps, #E65C00, decorative lines
│                             │
│  ┌─────────────────────┐    │
│  │  [Tab: Login] [Signup] │  │  ← active = orange underline + text
│  │─────────────────────│  │
│  │                     │  │
│  │  ┌───────────────┐  │  │  ← email input, 56px height
│  │  │ ✉ Email addr  │  │  │    border: #E5E7EB, radius 12px
│  │  └───────────────┘  │  │
│  │  ┌───────────────┐  │  │  ← password input
│  │  │ 🔒 Password 👁│  │  │    eye toggle right side
│  │  └───────────────┘  │  │
│  │         Forgot Password?│  │  ← right aligned, #E65C00, 13px
│  │                     │  │
│  │  [     Login      ] │  │  ← full width, #E65C00, white text, 56px h
│  │                     │  │
│  │       ── or ──      │  │  ← divider with text
│  │                     │  │
│  │    [G]        [🍎]  │  │  ← circular 56px buttons, white bg, shadow
│  │                     │  │
│  └─────────────────────┘  │
│  white card, radius 20px   │
│  shadow: card shadow       │
│                             │
│  Don't have an account?    │
│  Sign Up →                 │  ← #E65C00 orange, tappable
└─────────────────────────────┘
```

**Tab behavior:**
- Login tab (default): shows email + password + forgot + login button + social
- Sign Up tab: shows Full Name + email + password (strength bar) + confirm password + create account + social
- No page reload on tab switch — animated slide or fade

**Password strength bar (Sign Up only):**
- Below password field: thin bar, full width
- Weak: red 33% filled | Medium: amber 66% | Strong: green 100%
- Label text: "Weak" / "Medium" / "Strong" in matching color

**Input field spec:**
- Height: 56px
- Border: 1px solid #E5E7EB (default), #E65C00 (focused), #EF4444 (error)
- Border-radius: 12px
- Left icon: 20px, #9CA3AF
- Placeholder: #9CA3AF
- Value text: #1A1A2E, 15px

**Error display:**
- Below the field that errored
- Red text, 12px, #EF4444
- Appears with a subtle fade-in
- Example: "Incorrect email or password."

**Primary button spec:**
- Height: 56px
- Border-radius: 12px
- Background: #E65C00
- Text: white, 16px, weight 600
- Shadow: 0px 4px 12px rgba(230,92,0,0.3)
- Active/pressed: #C44E00 (darker)
- Disabled: #D1D5DB background, #9CA3AF text

**Social buttons:**
- 56px × 56px circles
- Background: #FFFFFF
- Shadow: card shadow
- Google: official G logo (colored)
- Apple: Apple logo (black, iOS only)

**Data operations:**
- Login: `supabase.auth.signInWithPassword(email, password)`
- Google: `supabase.auth.signInWithOAuth({ provider: 'google' })`
- Apple: `supabase.auth.signInWithOAuth({ provider: 'apple' })` — iOS only
- Sign Up: `supabase.auth.signUp(email, password)` → then create `member_profiles` or wait for role selection

**Navigation after auth:**
- Success → run startup routing logic (same as splash)

---

# SCREEN-003: Role Selection Screen

```
ID:       S003
Name:     Role Selection
Route:    /role-select
Role:     New users (no role in DB yet)
```

**Layout:**
```
┌─────────────────────────────┐
│  [Status bar — dark]        │
│  Background: #FBF5EE        │
│                             │
│       [SILENCE LOGO]        │  ← same as auth
│         Silence             │
│  ── LIBRARY MANAGEMENT ──   │
│                             │
│    Select Your Role         │  ← 22px, 700, #1A1A2E, center
│  Choose the role that       │
│  best describes you         │  ← 14px, #6B7280, center
│                             │
│  ┌─────────────────────┐    │  ← Admin card
│  │  [👤 orange circle] │    │    white bg, radius 16px, shadow
│  │  Admin           >  │    │    icon: person with tie, 48px circle
│  │  Runs and manages   │    │    title: 18px 600
│  │  the library/study  │    │    desc: 13px #6B7280
│  │  space.             │    │
│  └─────────────────────┘    │
│                             │
│  ┌─────────────────────┐    │  ← Member card
│  │  [📚 orange circle] │    │
│  │  Member          >  │    │
│  │  Studies, tracks    │    │
│  │  attendance,        │    │
│  │  manages membership.│    │
│  └─────────────────────┘    │
│                             │
│  ┌──────────────────────┐   │  ← Info card, cream bg, orange border
│  │ 🛡 Your role helps   │   │    lighter styling
│  │   us personalize     │   │
│  │   your experience.   │   │
│  └──────────────────────┘   │
└─────────────────────────────┘
```

**Card states:**
- Default: white card, subtle shadow, right chevron (>)
- Selected: orange border 2px, light orange bg tint `#FFF3ED`, filled orange radio dot in top-right

**Selection behavior:**
- Tap Admin card → card gets selected state → "Continue as Library Owner" button appears at bottom (fixed, above safe area)
- Tap Member card → selected state → "Continue as Student" button appears
- Button: full width, orange, 56px, only visible after selection

**On Continue tap:**
- Save role to Supabase: `INSERT INTO admin_profiles(user_id)` or `member_profiles(user_id)`
- Navigate: admin → S010, member → S040

**Warning text (below cards):**
- Lock icon + "You cannot change your role after selection."
- 12px, #9CA3AF, italic, center

---

# SCREEN-010: Admin Home — Setup Mode

```
ID:       S010-A
Name:     Admin Home (Setup Mode)
Route:    /admin/home
Role:     Admin only
State:    Before library launch (is_launched = false)
```

**Full Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER — 100px]     │
│ [lib photo 44px] Downtown▾  │  ← library switcher left
│ 123 MG Road, Indore         │  ← address, small
│         [📅 MON 19] [🔔 3] │  ← date pill + bell right
│ Good morning, Ashish 👋     │  ← 20px bold white
│ Here's what's happening...  │  ← 12px white 75%
│ [rounded bottom: 28px]      │
├─────────────────────────────┤
│ [SCROLLABLE BODY — #FBF5EE] │
│                             │
│ ┌── Setup Card ───────────┐ │  ← white card, 4px orange left border
│ │ Complete Library Setup  │ │    title 16px 600
│ │                  0/4 ✓  │ │    counter right, #6B7280
│ │ [████░░░░░░░░░░░░░] 25% │ │    thin orange progress bar
│ │                         │ │
│ │ ⃝ 1 Admin Profile  >   │ │  ← gray circle = incomplete
│ │   Add your personal...  │ │    green checkmark = complete
│ │                         │ │
│ │ ⃝ 2 Library Details >  │ │
│ │   Add library info...   │ │
│ │                         │ │
│ │ ⃝ 3 Shift & Plans  >   │ │
│ │   Add shifts, plans...  │ │
│ │                         │ │
│ │ ⃝ 4 Layout Setup  >    │ │
│ │   Add floors, seats...  │ │
│ │                         │ │
│ │ [Continue Setup →]      │ │  ← orange btn, full width inside card
│ └─────────────────────────┘ │
│                             │
│                             │
│ ┌── Stats Grid ───────────┐ │
│ │ ┌─────────────────────┐ │ │  ← Revenue: full width
│ │ │💰 Revenue This Month│ │ │    white card, tappable
│ │ │ ₹24,500             │ │ │    value: 24px 700
│ │ │ +₹1,200 today       │ │ │    sub: 12px green
│ │ │ ₹3,200 pending      │ │ │    pending: 12px amber
│ │ └─────────────────────┘ │ │
│ │ ┌──────┐ ┌──────┐      │ │  ← 2x2 grid, equal width cards
│ │ │Active│ │Expird│      │ │
│ │ │  42  │ │   8  │      │ │    value: 22px 700
│ │ │today │ │      │      │ │    label: 11px #6B7280
│ │ └──────┘ └──────┘      │ │
│ │ ┌──────┐ ┌──────┐      │ │
│ │ │New   │ │Expir-│      │ │
│ │ │ 12   │ │ Soon │      │ │
│ │ │this  │ │  5   │      │ │
│ │ │month │ │ 7days│      │ │
│ │ └──────┘ └──────┘      │ │
│ │ ┌─────────────────────┐ │ │  ← Occupancy: full width
│ │ │🔵 Live Occupancy    │ │ │    donut chart + legend
│ │ │  [donut: 73%]       │ │ │
│ │ │ ● Occup 73  ○ Vacant│ │ │
│ │ └─────────────────────┘ │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Action Required ──────┐ │  ← CONDITIONAL: only if actions pending
│ │ ⚠️ Action Required      │ │    amber left border 4px
│ │ 3 payment proofs pending│ │    tappable rows
│ │ 2 join requests pending │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Quick Actions ────────┐ │
│ │  [Add+]  [📢]  [💬]  [🔒]│ │  ← 4 buttons, 56px circles
│ │  Add     Ann-   Quer- Close│ │    labels below each (Icons: Add Member = blue, Announce = purple, Queries = teal, Close Library = orange)
│ │  Member  ounce  ies   Library│
│ └─────────────────────────┘ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Attendance Strip ─────┐ │
│ │ Today's Attendance  All │ │
│ │ [Shift: All▾]           │ │  ← shift filter chips
│ │ Present: 38/85          │ │  ← counter
│ │ [😊●][😊●][😊●][😊○]→  │ │  ← horizontal scroll
│ │ Arjun  Sana  Rohan ...  │ │    green ring=in, red ring=out
│ │             View All →  │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── QR Codes ─────────────┐ │
│ │ [Attendance QR][Join QR]│ │  ← two cards side by side
│ │ [QR image 80px]         │ │
│ │ [Download][Share]       │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Recent Activity ──────┐ │
│ │ Recent Activities       │ │    View All →
│ │ 🟢 Arjun checked in 5m  │ │
│ │ 🔵 New request from... 2h│ │
│ │ 🟠 Payment ₹1500    3h  │ │
│ └─────────────────────────┘ │
└─────────────────────────────┤
│ [BOTTOM NAV — 64px]         │
│ 🏠Home  ⊞Reserv  📊Ana  👤Pro│
└─────────────────────────────┘
```

**Header spec:**
- Background: `#E65C00` solid
- Border-bottom-left-radius: 28px
- Border-bottom-right-radius: 28px
- Library photo: 44px circle, 2px white border
- Library name: 15px, white, weight 700
- Chevron down: white, 16px
- Address: 11px, white 75% opacity
- Date pill: calendar icon + "MON 19 MAY", white outline pill, 12px
- Bell icon: 22px white, red badge (count, 10px white text)

**Setup card step row:**
- Height: 56px per row
- Left: numbered circle (24px) — gray outline = incomplete, green fill + white checkmark = complete
- Center: title (14px, 600) + subtitle (12px, #6B7280)
- Right: orange chevron >
- Tap: navigate to that setup screen
- Divider: 1px #F3F4F6 between rows

**Stats grid in setup mode:**
- All values show "0" or "₹0"
- Cards are visible but values are muted (#9CA3AF)
- Non-tappable in setup mode (or tap shows "Complete setup to activate")

**Bottom navigation:**
```
Tab 1: Home icon — "Home"
Tab 2: Grid icon — "Reservations"  
Tab 3: Chart icon — "Analytics"
Tab 4: Person icon — "Profile"

Active tab: icon + label in #E65C00
Inactive: icon + label in #9CA3AF
Background: #FFFFFF
Top border: 1px #E5E7EB
Height: 64px + safe area bottom
```

---

# SCREEN-010: Admin Home — Operational Mode

```
ID:       S010-B
Name:     Admin Home (Operational Mode)
Route:    /admin/home
Role:     Admin only
State:    After library launch (is_launched = true)
```

**Full Layout (scrollable body):**
```
┌─────────────────────────────┐
│ [ORANGE HEADER — same]      │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Photo Carousel ───────┐ │  ← horizontal scroll, 160px height
│ │ [photo1][photo2][photo3]│ │    rounded corners 12px
│ │         ● ○ ○           │ │    pagination dots below
│ └─────────────────────────┘ │
│                             │
│ ┌── Library Code Card ────┐ │  ← white card
│ │ Library Code            │ │    label 12px #6B7280
│ │ SIL-4K9M2P   [Share]   │ │    code: 18px monospace #E65C00
│ │ [Copy Code]             │ │    copy: outlined orange btn
│ └─────────────────────────┘ │
│                             │
│ ┌── Stats Grid ───────────┐ │
│ │ ┌─────────────────────┐ │ │  ← Revenue: full width
│ │ │💰 Revenue This Month│ │ │    white card, tappable
│ │ │ ₹24,500             │ │ │    value: 24px 700
│ │ │ +₹1,200 today       │ │ │    sub: 12px green
│ │ │ ₹3,200 pending      │ │ │    pending: 12px amber
│ │ └─────────────────────┘ │ │
│ │ ┌──────┐ ┌──────┐      │ │  ← 2x2 grid, equal width cards
│ │ │Active│ │Expird│      │ │
│ │ │  42  │ │   8  │      │ │    value: 22px 700
│ │ │today │ │      │      │ │    label: 11px #6B7280
│ │ └──────┘ └──────┘      │ │
│ │ ┌──────┐ ┌──────┐      │ │
│ │ │New   │ │Expir-│      │ │
│ │ │ 12   │ │ Soon │      │ │
│ │ │this  │ │  5   │      │ │
│ │ │month │ │ 7days│      │ │
│ │ └──────┘ └──────┘      │ │
│ │ ┌─────────────────────┐ │ │  ← Occupancy: full width
│ │ │🔵 Live Occupancy    │ │ │    donut chart + legend
│ │ │  [donut: 73%]       │ │ │
│ │ │ ● Occup 73  ○ Vacant│ │ │
│ │ └─────────────────────┘ │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Action Required ──────┐ │  ← CONDITIONAL: only if actions pending
│ │ ⚠️ Action Required      │ │    amber left border 4px
│ │ 3 payment proofs pending│ │    tappable rows
│ │ 2 join requests pending │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Quick Actions ────────┐ │
│ │  [Add+]  [📢]  [💬]  [🔒]│ │  ← 4 buttons, 56px circles
│ │  Add     Ann-   Quer- Close│ │    labels below each  (Icons: Add Member = blue, Announce = purple, Queries = teal, Close Library = orange)
│ │  Member  ounce  ies   Library│
│ └─────────────────────────┘ │
│                             │
│ ┌── Attendance Strip ─────┐ │
│ │ Today's Attendance  All │ │
│ │ [Shift: All▾]           │ │  ← shift filter chips
│ │ Present: 38/85          │ │  ← counter
│ │ [😊●][😊●][😊●][😊○]→  │ │  ← horizontal scroll
│ │ Arjun  Sana  Rohan ...  │ │    green ring=in, red ring=out
│ │             View All →  │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── QR Codes ─────────────┐ │
│ │ [Attendance QR][Join QR]│ │  ← two cards side by side
│ │ [QR image 80px]         │ │
│ │ [Download][Share]       │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Recent Activity ──────┐ │
│ │ Recent Activities       │ │    View All →
│ │ 🟢 Arjun checked in 5m  │ │
│ │ 🔵 New request from... 2h│ │
│ │ 🟠 Payment ₹1500    3h  │ │
│ └─────────────────────────┘ │
└─────────────────────────────┤
│ [BOTTOM NAV]                │
└─────────────────────────────┘
```

**Quick Actions row — circular button spec:**
```
Each button:
  Size: 56px circle
  Icon: 24px, white
  Label: 12px, #374151, below button
  Spacing: equal, in a row of 4

Button colors (from screenshot):
  Attendance QR:  #E65C00 (orange)
  Add Member:     #3B82F6 (blue)
  Mark Paid:      #10B981 (green)
  Announce:       #8B5CF6 (purple)
  (variations per screen state)
```

**Attendance strip — avatar spec:**
```
Avatar circle: 52px
Photo: circular crop
Ring color: 
  Green (#22C55E, 2.5px) = checked in
  Red (#EF4444, 2.5px)   = checked out
  Red overlay on photo   = expired member
Below: 
  Name: 11px, #1A1A2E, max 8 chars + ...
  Time: 10px, #6B7280
  Seat: 10px, #E65C00
```

**Stat card tap actions:**
- Revenue → Analytics tab
- Active Today → Reservations/Members filtered Active
- Expired → Members filtered Expired
- New Joinings → Members filtered All
- Expiring Soon → Members filtered Expiring
- Occupancy → Reservations/Layout

**Realtime subscriptions:**
```javascript
// Subscribe on mount, unsubscribe on unmount
supabase
  .channel('admin-home')
  .on('postgres_changes', {
    event: 'INSERT',
    schema: 'public',
    table: 'attendance_logs',
    filter: `library_id=eq.${libraryId}`
  }, handleNewAttendance)
  .on('postgres_changes', {
    event: 'INSERT',
    table: 'join_requests',
    filter: `library_id=eq.${libraryId}`
  }, handleNewRequest)
  .subscribe()
```

**Loading state:** Skeleton cards — gray animated shimmer for each card section.

**Error state:** "Could not load dashboard. Pull to refresh." with retry button.

---

# SCREEN-011: QR Code Modal

```
ID:       S011
Name:     QR Code Modal
Type:     Overlay modal (not full screen)
Trigger:  Quick Actions → Attendance QR or Joining QR
          OR QR cards in Home
```

**Layout:**
```
┌─────────────────────────────┐
│  [Dim overlay — 40% black]  │
│                             │
│  ┌───────────────────────┐  │  ← white card, radius 20px top corners
│  │  Joining QR│Attend QR │  │  ← tab switcher top
│  │  ──────────────────── │  │  ← orange underline on active tab
│  │                    ✕  │  │  ← close button top-right, 24px
│  │                       │  │
│  │  ┌─────────────────┐  │  │  ← QR code display
│  │  │  [CORNER ⌐  ¬]  │  │  │    220×220px
│  │  │                 │  │  │    orange L-bracket corners
│  │  │   [QR IMAGE]    │  │  │    white padding around QR
│  │  │                 │  │  │
│  │  │  [CORNER L  ┘]  │  │  │
│  │  └─────────────────┘  │  │
│  │                       │  │
│  │  Library Code         │  │  ← label 12px #6B7280
│  │  SIL-4K9M2P  [copy]  │  │  ← 18px monospace orange + copy icon
│  │                       │  │
│  │  ┌──────┐ ┌──────┐ ┌──┐│  │  ← 3 equal buttons
│  │  │  ⬇  │ │Share │ │🔄││  │    Download as PDF, Share, Regenerate
│  │  │ PDF  │ │      │ │  ││  │
│  │  └──────┘ └──────┘ └──┘│  │
│  │                        │  │
│  │  🔒 Attendance QR:      │  │  ← footer note, 11px #6B7280
│  │  Print, laminate, fix   │  │
│  │  on wall. Works forever.│  │
│  └───────────────────────┘  │
└─────────────────────────────┘
```

**Regenerate confirmation bottom sheet:**
```
┌─────────────────────────────┐
│  ⚠️ Regenerate QR?          │  ← 18px 600, amber icon
│                             │
│  Old QR continues working   │
│  for 7 days after this.     │  ← 14px #374151
│                             │
│  ┌───────────────────────┐  │
│  │ Type REGENERATE below │  │  ← instruction, 13px
│  │ [REGENERATE        ]  │  │  ← text input, red border when wrong
│  └───────────────────────┘  │
│                             │
│  [Cancel]  [Confirm Regen.] │  ← Cancel: text btn | Confirm: red btn
└─────────────────────────────┘
```

---

# SCREEN-020: Complete Profile (Admin)

```
ID:       S020
Name:     Complete Profile (Admin)
Route:    /admin/profile/complete
Role:     Admin
Entry:    Setup card Step 1 OR Profile tab → Edit Profile
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Complete Profile          │  ← back arrow left, title center
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│  ┌──── Photo Section ────┐  │
│  │                       │  │  ← white card
│  │     [PHOTO CIRCLE]    │  │    96px circle, dashed orange border
│  │         88px          │  │    if no photo: person icon #9CA3AF
│  │   📷  Tap to add      │  │    camera icon + text below
│  │   [Take Photo][Gallery]│  │  ← two small buttons
│  └───────────────────────┘  │
│                             │
│  ┌──── Form Fields ──────┐  │
│  │                       │  │  ← white card
│  │  Full Name *          │  │    label 12px #6B7280 above input
│  │  ┌───────────────┐    │  │
│  │  │ Your Name     │    │  │    56px input field
│  │  └───────────────┘    │  │
│  │                       │  │
│  │  Gender               │  │
│  │  ┌──┐ ┌──┐ ┌──┐ ┌──┐ │  │  ← radio pill buttons
│  │  │♂ │ │♀ │ │⚧ │ │--│ │  │    Male/Female/Other/Prefer not
│  │  └──┘ └──┘ └──┘ └──┘ │  │    selected: orange fill, white text
│  │                       │  │    unselected: white, orange border
│  │  Date of Birth        │  │
│  │  ┌───────────────┐    │  │
│  │  │ 12 May 1992 📅│    │  │    calendar icon right, opens picker
│  │  └───────────────┘    │  │
│  │                       │  │
│  │  Contact Number       │  │
│  │  ┌──┐ ┌────────────┐  │  │  ← +91 prefix box + number input
│  │  │+91│ │98765 43210│  │  │
│  │  └──┘ └────────────┘  │  │
│  │                       │  │
│  │  Email                │  │
│  │  ┌───────────────┐    │  │    pre-filled from auth, editable
│  │  │youremail@gmail.com │  │  
│  │  └───────────────┘    │  │
│  └───────────────────────┘  │
│                             │
│  [error box if any]         │  ← red bg tint, error text 13px
│                             │
│  [    Save Profile    ]     │  ← orange full width button
└─────────────────────────────┘
```

**Calendar date picker (all date pickers in app):**
```
Bottom sheet with:
  Month/Year selector at top (← March 2026 →)
  7-column calendar grid
  Day cells: 40×40px
  Selected day: orange circle
  Today: orange dot below number
  [Cancel] [Select] buttons at bottom
```

**On save:**
- Validate: Full Name required, phone 10 digits
- Save to `admin_profiles` table
- Success toast: "Profile saved ✓"
- Navigate back to Admin Home
- Admin Home re-evaluates step 1 as complete

---

# SCREEN-021: Library Setup — Stage 1

```
ID:       S021
Name:     Library Setup — Stage 1 (Basic Info)
Route:    /admin/library/setup/1
Role:     Admin
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Library Setup             │
│     ●──○──○                 │  ← stage indicator: filled=done, outline=current
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌─── Basic Info ──────────┐ │  ← white card
│ │  Library Name *         │ │
│ │  ┌─────────────────┐    │ │
│ │  │ SILENCE Study   │    │ │
│ │  └─────────────────┘    │ │
│ │                         │ │
│ │  Street Address         │ │
│ │  ┌─────────────────┐    │ │
│ │  │ 123 MG Road     │    │ │
│ │  └─────────────────┘    │ │
│ │                         │ │
│ │  City *   State         │ │
│ │  ┌──────┐ ┌──────────┐  │ │  ← side by side
│ │  │Indore│ │Madhya P. ▾│  │ │
│ │  └──────┘ └──────────┘  │ │
│ │                         │ │
│ │  PIN Code               │ │
│ │  ┌─────────────────┐    │ │
│ │  │ PINCODE         │    │ │
│ │  └─────────────────┘    │ │
│ └─────────────────────────┘ │
│                             │
│ ┌─── Library Photos ──────┐ │
│ │  Add Photos (up to 4)   │ │
│ │  ┌──┐ ┌──┐ ┌──┐ ┌────┐  │ │  ← thumbnail grid
│ │  │📸│ │📸│ │📸│ │ + │  │ │    added photos + add button
│ │  └──┘ └──┘ └──┘ └────┘  │ │    each 80×80px, radius 8px
│ └─────────────────────────┘ │
│                             │
│ ┌─── Amenities ───────────┐ │
│ │  [AC ✓][WiFi ✓][Locker] │ │  ← pill toggles
│ │  [Water][CCTV][Sections]│ │    selected: orange bg white text
│ │  [Parking][Washroom]    │ │    unselected: white, #E5E7EB border
│ └─────────────────────────┘ │
│                             │
│                             │
│ ┌── Library Code ─────────┐ │  ← shows after first save
│ │  Your Library Code      │ │
│ │  SIL-4K9M2P    [Copy]  │ │
│ │  Share this to invite   │ │
│ │  members                │ │
│ └─────────────────────────┘ │
│                             │
│  [    Next: Layout →    ]   │  ← orange button
└─────────────────────────────┘
```

---

# SCREEN-022: Library Setup — Stage 2 (Floors & Seats)

```
ID:       S022
Name:     Library Setup — Stage 2
Route:    /admin/library/setup/2
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Library Setup             │
│     ●──●──○                 │  ← stage 2 current
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌─── Floor Tabs ──────────┐ │  ← horizontal scroll
│ │ [+] [Ground●] [First○]  │ │    + = add floor (dashed)
│ │                         │ │    active = orange pill
│ └─────────────────────────┘ │
│                             │
│ ┌─── Sections ────────────┐ │  ← for active floor
│ │ General Study      ···  │ │    section header row
│ │ 🧑 Boys  62 seats       │ │    three-dot menu right
│ │                         │ │
│ │ ┌──┐┌──┐┌──┐┌──┐┌──┐┌──┐│ │  ← seat grid
│ │ │G-A│G-A│G-A│G-A│G-A│G-A│ │  │    6 columns
│ │ │01 │02 │03 │04 │05 │06 │ │  │    green = vacant
│ │ └──┘└──┘└──┘└──┘└──┘└──┘│ │    blue = occupied
│ │ [row 2] [row 3] ...     │ │
│ │               [+ add]   │ │  ← dashed square at end
│ │                         │ │
│ │ Girls Section      ···  │ │
│ │ 🚺 Girls  36 seats      │ │
│ │ [seat grid...]          │ │
│ └─────────────────────────┘ │
│                             │
│  [    Next: Shifts →    ]   │
└─────────────────────────────┘
```

---

# SCREEN-023: Library Setup — Stage 3 (Shifts & Plans)

```
ID:       S023
Name:     Library Setup — Stage 3
Route:    /admin/library/setup/3
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Library Setup             │
│     ●──●──●                 │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌─── Shift 1 ─────────────┐ │  ← white card per shift
│ │                      ✕  │ │    × to remove (if >1 shift)
│ │  Shift Name             │ │
│ │  ┌──────────────────┐   │ │
│ │  │ Morning Shift    │   │ │
│ │  └──────────────────┘   │ │
│ │                         │ │
│ │  Start Time  End Time   │ │  ← side by side time pickers
│ │  ┌──────┐   ┌──────┐   │ │    opens time wheel / clock
│ │  │ 6:00 │   │14:00 │   │ │
│ │  └──────┘   └──────┘   │ │
│ │                         │ │
│ │  Monthly   3-Month  6-M │ │  ← pricing row
│ │  ┌──────┐ ┌─────┐ ┌───┐│ │    ₹ prefix inside
│ │  │₹700  │ │₹2000│ │₹..││ │
│ │  └──────┘ └─────┘ └───┘│ │
│ │                         │ │
│ │  Trial Days: [0      ]  │ │  ← number input, 0 = no trial
│ └─────────────────────────┘ │
│                             │
│  [+ Add New Shift]          │  ← dashed border button, full width
│                             │
│  [  Save & Finish ✓  ]      │  ← orange solid button
└─────────────────────────────┘
```

---

# SCREEN-024: Payment Setup

```
ID:       S024
Name:     Payment Setup
Route:    /admin/payment/setup
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Payment Setup             │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌─── Cash Payment ────────┐ │
│ │  Accept Cash Payments   │ │  ← label left
│ │  Members pay in person  │ │    desc 12px
│ │                    [●] │ │  ← toggle right, orange when ON
│ └─────────────────────────┘ │
│                             │
│ ┌─── UPI IDs ─────────────┐ │
│ │  Your UPI IDs           │ │
│ │  ┌────────────────────┐ │ │
│ │  │ UPI@paytm          │ │ │  ← text input
│ │  └────────────────────┘ │ │
│ │  [+ Add UPI ID]         │ │  ← text button orange
│ │                         │ │
│ │  Added IDs:             │ │
│ │  ● 9876@paytm    n[🗑]   │ │  ← removable rows
│ │  ● upi1   @ybl    [🗑]   │ │
│ │                         │ │
│ │  💳 Payment App Icons:  │ │  ← auto-detected from UPI handles
│ │  [PhonePe][GPay][Paytm] │ │    color icons, 32px each
│ └─────────────────────────┘ │
│                             │
│  [     Save & Continue    ] │
└─────────────────────────────┘
```

---

# SCREEN-030: Reservations — Layout Tab

```
ID:       S030
Name:     Reservations — Layout
Route:    /admin/reservations/layout
Role:     Admin
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ Reservations  [Manage 🔧]   │  ← title left, manage pill right
├─────────────────────────────┤
│ [Sub-tabs — white bg]       │
│ [Layout●] [Members] [Req] [Archive] │  ← horizontal tabs
│ ─────── orange underline ───│
├─────────────────────────────┤
│ [SHIFT SELECTOR + FLOOR]    │  ← sticky below tabs
│ [Morning Shift ▾] [Ground ▾]│  ← two dropdowns side by side
│ [🔍 Search seat...]         │  ← search bar
│ [All][Vacant][Occupied][...] │  ← filter chips, horizontal scroll
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── General Study ────────┐ │  ← section header
│ │ 👥  62 Seats  •  54 Occ │ │    icon + counts + three-dot menu
│ │ 8 Vacant                │ │
│ │ ┌──┐┌──┐┌──┐┌──┐┌──┐┌──┐│ │  ← seat grid, 6 columns
│ │ │G-A│G-A│G-A│G-A│G-A│G-A│ │    page 1 of N (30 per page)
│ │ │01 │02 │03 │04 │05 │06 │ │
│ │ └🟢┘└🔵┘└🔵┘└🔵┘└🔵┘└🔵┘│ │  ← color indicators
│ │ ... rows ...             │ │
│ │ [◀ Prev 30] [Next 30 ▶] │ │  ← pagination bar
│ │                   [+]   │ │  ← dashed add seat at end
│ └─────────────────────────┘ │
│                             │
│ ┌── Girls Section ────────┐ │  ← second section
│ │ 🚺  36 Seats  •  31 Occ │ │
│ │ [seat grid...]           │ │
│ └─────────────────────────┘ │
│                             │
│ ─── Legend ───────────────  │
│ 🟢Vacant 🔵Occupied          │
│ 🟡Expiring 🔴Fee Pending     │
│ 🟠Hold ⚪Maintenance         │
└─────────────────────────────┘
│ [BOTTOM NAV]                │
└─────────────────────────────┘
```

**Seat square spec:**
```
Size: 52×44px
Border-radius: 8px
Label: seat_label, 10px, white, center
Colors:
  Vacant:        background #22C55E (green)
  Occupied:      background #3B82F6 (blue)
  Expiring Soon: background #3B82F6 + yellow dot top-right (8px)
  Fee Pending:   background #3B82F6 + red dot top-right (8px)
  Hold:          background #D97706 (amber)
  Maintenance:   background #9CA3AF (gray) + wrench icon
  Selected:      orange border 2px
```

**Filter chips:**
```
All (default), Vacant, Occupied, Expiring Soon, + section names
Active chip: orange bg, white text, radius 20px
Inactive: white bg, #E5E7EB border
```

---

# SCREEN-031: Seat Actions Modal — Occupied Seat

```
ID:       S031-A
Name:     Seat Actions (Occupied)
Type:     Bottom sheet modal
Trigger:  Tap on occupied seat in grid
```

**Layout:**
```
┌─────────────────────────────┐
│ [Dim overlay]               │
│ ┌─── Bottom Sheet ────────┐ │  ← white, radius 20px top
│ │ ─── drag handle ───     │ │
│ │                     ✕   │ │  ← close
│ │                         │ │
│ │ [G-A-12] Rahul Sharma   │ │  ← seat pill + member name
│ │ [Active]  Expires in 4d │ │  ← status badge + expiry
│ │                         │ │
│ │ ────────────────────    │ │  ← divider
│ │                         │ │
│ │ 👤 View Member Details  >│ │  ← action row, 56px height
│ │ ⏸  Mark as Hold        >│ │  ← icon + label + chevron
│ │ 🔄 Reassign Seat        >│ │
│ │ ↻  Renew Membership     >│ │
│ │                         │ │
│ │ 🗑 Remove from Seat      │ │  ← RED text, destructive
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

**Action row spec:**
- Height: 56px
- Left icon: 20px, #374151 (red for destructive)
- Label: 15px, #1A1A2E (red for destructive)
- Right chevron: 16px, #9CA3AF (none for destructive)
- Tap: ripple effect + action

---

# SCREEN-031: Seat Actions Modal — Vacant Seat

```
ID:       S031-B
Name:     Seat Actions (Vacant)
Type:     Bottom sheet
```

**Layout:**
```
│ ┌─── Bottom Sheet ────────┐ │
│ │ [G-A-21]   Vacant Seat  │ │  ← green pill + status
│ │ [Vacant]                │ │
│ │ ───────────────────     │ │
│ │ 👤 Assign Member       >│ │
│ │ 🔒 Reserve Seat        >│ │
│ │ 🔧 Mark for Maintenance >│ │
│ │                         │ │
│ │ 🗑 Delete Seat           │ │  ← red, destructive
│ └─────────────────────────┘ │
```

---

# SCREEN-032: Reservations — Members Tab

```
ID:       S032
Name:     Reservations — Members
Route:    /admin/reservations/members
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ Reservations  [Manage 🔧]   │
├─────────────────────────────┤
│ [Sub-tabs]                  │
│ [Layout] [Members●] [Req] [Archive]│
├─────────────────────────────┤
│ 🔍 Search by name, phone... │  ← search bar, full width, white
│                             │
│ [All●][Active][Pending][Exp]│  ← filter chips, horizontal scroll
│ [Hold][Exp.Soon][Trial][MissingID]│
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Member Card ──────────┐ │  ← white card
│ │ [📸 52px] Rahul Sharma  │ │    photo circle left
│ │ [G-A-12] [Active]       │ │    seat pill + status badge
│ │ ☀ Morning Shift         │ │    shift with colored dot
│ │ Expires in 4 days       │ │    expiry info
│ │                     ··· │ │    three-dot menu right
│ └─────────────────────────┘ │
│                             │
│ ┌── Member Card ──────────┐ │
│ │ [📸] Arjun Verma        │ │
│ │ [G-A-03] [Payment Due]  │ │  ← amber status
│ │ ☀ Morning Shift         │ │
│ │ Dues: ₹500              │ │  ← amber text
│ │                     ··· │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Member Card ──────────┐ │
│ │ [📸] Sneha Patel  [Hold]│ │  ← amber badge
│ │ [G-A-07]  On Hold       │ │
│ │ ☽ Evening Shift         │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Member Card ──────────┐ │
│ │ [📸] Rohit Singh [Expird]│ │  ← red badge
│ │ [G-A-16]                │ │
│ │ Expired 5 days ago      │ │  ← red text
│ └─────────────────────────┘ │
└─────────────────────────────┤
│ [BOTTOM NAV]                │
└─────────────────────────────┘
```

**Member card status badges:**
```
Active:       green bg #DCFCE7, green text #16A34A
Expiring Soon: amber bg #FEF3C7, amber text #D97706
Payment Due:  amber bg #FEF3C7, amber text #D97706
Hold:         amber bg, amber text
Expired:      red bg #FEE2E2, red text #DC2626
Trial:        purple bg #EDE9FE, purple text #7C3AED
Pending:      gray bg #F3F4F6, gray text #6B7280
```

**Floating + button:**
- 52×52px orange circle
- White + icon, 24px
- Bottom-right corner, above nav
- Tap → Add Member Wizard

**Select mode (three-dot → "Select Members"):**
- Checkboxes appear on left of each card
- Bottom bar slides up: [Send Announcement] [Export Selected] [Cancel]

---

# SCREEN-033: Member Detail Screen

```
ID:       S033
Name:     Member Detail
Route:    /admin/member/:id
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Member Details      ✏️   │  ← back + edit pencil right
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Profile Header ───────┐ │  ← white card
│ │    [PHOTO 64px]         │ │    orange ring border
│ │    Rahul Sharma         │ │    name 20px 700
│ │    [Active]             │ │    status badge
│ │    MEM-1024             │ │    member ID 12px #6B7280
│ │    Joined 12 Apr 2025   │ │    join date 12px
│ │                         │ │
│ │ ┌──────┬──────┬──────┬──┐│ │  ← 4-cell info grid
│ │ │ Seat │Shift │ Plan │Exp│ │  │    each: icon + label + value
│ │ │G-A-12│Morn- │1 Mon-│19 │ │  │    12px label #6B7280
│ │ │      │ ing  │ th   │May│ │  │    14px value #1A1A2E 600
│ │ └──────┴──────┴──────┴──┘│ │
│ └─────────────────────────┘ │
│                             │
│ [Tab bar]                   │
│ [Overview●][Attend][Pay][Act][Notes]│
│ ── orange underline ────────│
│                             │
│ ── OVERVIEW TAB ──          │
│ ┌── Membership ───────────┐ │
│ │ Started    12 Apr 2025  │ │
│ │ Expires    19 May 2025  │ │
│ │ Status     Active       │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Attendance Summary ───┐ │
│ │ ┌──────┐┌──────┐┌──────┐│ │  ← 3 stats
│ │ │  22  ││  18  ││  7   ││ │    value 20px 700
│ │ │Total ││ This ││Streak││ │    label 11px #6B7280
│ │ │Visits││Month ││ Days ││ │
│ │ └──────┘└──────┘└──────┘│ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Payment Summary ──────┐ │
│ │ Paid     ₹3,000         │ │
│ │ Dues     ₹0     [green] │ │
│ │ Last Pay 12 Apr 2025    │ │
│ └─────────────────────────┘ │
│                             │
│ ── ATTENDANCE TAB ──        │
│ ┌── Calendar ─────────────┐ │
│ │ ◀ May 2025 ▶            │ │  ← month navigation
│ │ Su Mo Tu We Th Fr Sa    │ │
│ │ [1][2●][3●][4●][5●]...  │ │  ← ● = present (orange circle)
│ │ empty = absent           │ │    tap day → popup
│ └─────────────────────────┘ │
│                             │
│ ── PAYMENTS TAB ──          │
│ ┌── Payment Row ──────────┐ │  ← white card per payment
│ │ ₹1,500      [Confirmed] │ │
│ │ Cash   •  12 Apr 2025   │ │
│ │ Apr 12 – May 11         │ │
│ │ Ref: A3K9M2             │ │
│ └─────────────────────────┘ │
│                             │
│ ── ACTIVITY TAB ──          │
│ Timeline with colored dots  │
│ ● Joined library  12 Apr   │
│ ● Seat assigned G-A-12      │
│ ● Payment ₹1,500 confirmed  │
│                             │
│ ── NOTES TAB ──             │
│ ┌── Admin Notes ──────────┐ │
│ │ Private note...         │ │  ← textarea, not visible to member
│ │ [Save Note]             │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

---

# SCREEN-034: Reservations — Requests Tab

```
ID:       S034
Name:     Reservations — Requests
Route:    /admin/reservations/requests
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ Reservations                │
├─────────────────────────────┤
│ [Sub-tabs: Layout/Members/Requests●/Archive] │
├─────────────────────────────┤
│ [Join Requests●][Seat Changes][Hold Req] │  ← toggle
├─────────────────────────────┤
│ [All][New][Aging 5+d][Expiring Today] │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Join Request Card ────┐ │
│ │ [📸 48px] Ananya Gupta  │ │    photo left
│ │ Requested 15 May, 10:30 │ │    time 12px #6B7280
│ │                         │ │
│ │ ☀ Evening Shift         │ │    colored dot + shift
│ │ 📋 1 Month Plan         │ │
│ │ 💳 UPI Payment          │ │
│ │                         │ │
│ │ ┌── Payment Proof ────┐ │ │    screenshot thumbnail
│ │ │ [screenshot 80px]   │ │ │    sender: "Ananya G."
│ │ │ Sent by: Ananya G.  │ │ │    amount: ₹1,500
│ │ └─────────────────────┘ │ │
│ │ [Confirm Pay] [Reject Pay]│ │  ← payment action buttons first
│ │                         │ │
│ │ [  Approve  ] [ Reject ]│ │  ← GRAYED until payment confirmed
│ └─────────────────────────┘ │
│                             │
│ ┌── Join Request Card ────┐ │  ← aging request
│ │ [📸] Vikram Rao         │ │
│ │ Submitted 3 days ago    │ │    aging 3d = gray
│ │ ⚠ Aging — 4 days left  │ │    day 5+ = amber warning
│ │ ☀ Morning Shift  Cash   │ │
│ │ [ Approve ] [ Reject ]  │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

**Approve flow (seat picker):**
```
1. Tap [Approve Membership]
2. Bottom sheet opens: "Select a Seat — [Shift Name]"
3. Cinema grid shows ONLY vacant seats for that shift
4. Member taps seat → confirmation dialog:
   "Assign seat G-A-05 to Ananya Gupta?"
   [Cancel] [Confirm]
5. On Confirm: re-validate vacancy at DB level
6. If taken: error toast "Seat just assigned, pick another"
7. If free: membership created, member notified
```

---

# SCREEN-035: Reservations — Archive Tab

```
ID:       S035
Name:     Archive
Route:    /admin/reservations/archive
```

**Layout:**
```
┌─────────────────────────────┐
│ [Sub-tabs: .../Archive●]    │
├─────────────────────────────┤
│ 🔍 Search archived members  │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Archive Row ──────────┐ │
│ │ [📸 faded] Neha Tiwari  │ │    photo slightly faded (70% opacity)
│ │ Exited 10 May 2025      │ │    12px #6B7280
│ │ Member since 12 Jan 2025│ │
│ │ [4 Months]              │ │  ← duration pill, gray bg
│ └─────────────────────────┘ │
│                             │
│ ┌── Empty State ──────────┐ │  ← when no archived members
│ │  [📦 box illustration]  │ │    icon 80px, muted
│ │  No past members yet    │ │    14px #9CA3AF
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

---

# SCREEN-036: Add Member Wizard

```
ID:       S036
Name:     Add Member Wizard
Type:     Stack screen (full screen, no bottom nav)
Steps:    4 steps with progress bar at top
```

**Progress bar:**
```
┌─────────────────────────────┐
│ ← Add Member                │
│ Step 1 of 4                 │
│ ████░░░░░░░░░  25%          │  ← thin orange progress bar
└─────────────────────────────┘
```

**Step 1 — Personal Info:**
```
Fields in white card:
  Profile Photo: [Take Photo] or [Choose Gallery] — optional
  Full Name *
  Phone Number * (+91 prefix)
  Email
  Gender (radio pills)
  Date of Birth (calendar picker)
  Address (textarea)
  Exam Category (dropdown: UPSC/NEET/JEE/SSC/PCS/Other)
  
  [Next →] orange button
```

**Step 2 — ID Verification:**
```
White card:
  [Take Photo (rear camera)] — for physical ID at counter
  [Choose from Gallery] — for soft copy (WhatsApp sent)
  
  ID Type selector: [Aadhaar][PAN][Voter ID][Driving License]
  
  Uploaded: thumbnail 80×80 with × remove
  
  "ID will be marked as Verified by Admin"
  
  [Skip for now — Add Later] text link (creates Missing ID flag)
  [Next →] orange button
```

**Step 3 — Plan & Seat:**
```
White card:
  Shift: [Morning Shift] [Evening Shift] — selectable cards
  
  Plan Duration:
  [Monthly — ₹1,500 ●] [3-Month — ₹4,000] [6-Month — ₹7,500]
  — pill cards, selected = orange
  
  Discount toggle:
  [Apply Discount ○] → if ON shows:
    Charge Amount: ₹[input]
    Original: ₹1,500 → Discount: ₹200
    Reason: [text field]
  
  Seat Selection:
  [Cinema grid — vacant seats only for chosen shift]
  
  [Next →]
```

**Step 4 — Payment:**
```
White card:
  Plan: Morning Shift • Monthly
  Amount: ₹1,500 (or discounted amount)
  
  Payment Method:
  [💵 Cash ●] [📱 UPI]
  — selectable cards
  
  [Mark as Received] — orange button
  
  If UPI selected:
    Admin's UPI IDs listed
    [PhonePe][GPay][Paytm] deep-link icons
    Screenshot upload: [📤 Upload Screenshot]
    Sender Name: [text field, required]
```

**Summary screen (after Step 4):**
```
White card showing:
  Library: SILENCE Study Zone
  Member: Rahul Sharma
  Shift: Morning Shift
  Plan: Monthly (12 Apr – 11 May)
  Seat: G-A-12
  Amount: ₹1,500
  Method: Cash — Received
  
  [Confirm & Add Member] — orange button
  [← Back] — text button
```

---

# SCREEN-037: Renewal Screen

```
ID:       S037
Name:     Renewal Screen
Route:    /admin/member/:id/renew  OR  /member/renew/:membershipId
Role:     Admin + Member
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Renew Membership          │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Current Plan (read-only)┐│
│ │ Rahul Sharma              ││
│ │ Morning Shift • G-A-12    ││
│ │ Valid: 12 Apr – 11 May    ││
│ │ Status: [Expiring in 4d]  ││
│ └──────────────────────────┘│
│                             │
│ ⚠ [Banner if 4+ days expired]│  ← yellow banner
│ "Member absent X days since  │
│  expiry. Choose start date:" │
│ [From Expiry: May 11] [Today]│  ← prominent button choices
│                             │
│ ┌── Renewal Options ──────┐ │
│ │ Shift  [Morning ▾]      │ │
│ │                         │ │
│ │ Plan Duration           │ │
│ │ [Monthly][3-Month][6-M] │ │  ← pill selector
│ │                         │ │
│ │ Start Date              │ │
│ │ ○ Continue from May 11  │ │  ← radio options
│ │ ○ Start from today      │ │
│ │ ○ Custom date [📅]      │ │
│ │                         │ │
│ │ Discount                │ │
│ │ [Apply Discount ○]      │ │
│ │                         │ │
│ │ Amount: ₹1,500          │ │
│ │ Method: [Cash] [UPI]    │ │
│ └─────────────────────────┘ │
│                             │
│ Admin options (admin view):  │
│ [Renew Silently] [Notify First]│  ← two buttons
│                             │
│ (Member view — single btn): │
│ [  Submit Renewal Request  ]│
└─────────────────────────────┘
```

---

# SCREEN-038: Analytics Tab

```
ID:       S038
Name:     Analytics
Route:    /admin/analytics
Role:     Admin
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ Analytics  [SIL-Study ▾]    │  ← library switcher pill right
├─────────────────────────────┤
│ [Today][7 Days][This Month●][Custom] │  ← date filter pills
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Revenue Row ──────────┐ │  ← two cards side by side
│ │ ┌──────────┐┌──────────┐│ │
│ │ │Today's   ││Monthly   ││ │
│ │ │Revenue   ││Revenue   ││ │
│ │ │₹3,200    ││₹24,500   ││ │
│ │ │Cash/UPI  ││18 paid   ││ │
│ │ └──────────┘└──────────┘│ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Expenses & Profit ────┐ │  ← two cards
│ │ ┌──────────┐┌──────────┐│ │
│ │ │Monthly   ││Net Profit ││ │
│ │ │Expenses  ││           ││ │
│ │ │₹8,500    ││₹16,000   ││ │  ← green if +, red if -
│ │ └──────────┘└──────────┘│ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Dues ─────────────────┐ │
│ │ Total Dues: ₹4,200      │ │
│ │ 8 members pending       │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Financial Trend ──────┐ │  ← line chart
│ │ Revenue vs Expenses     │ │    orange = revenue
│ │ [LINE CHART — 200px h]  │ │    purple dashed = expenses
│ │ Jan Feb Mar Apr May     │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Revenue Split ────────┐ │  ← donut chart
│ │ [DONUT] Cash 60% UPI 40%│ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Attendance Chart ─────┐ │  ← bar chart
│ │ Daily check-ins         │ │    orange bars
│ │ [BAR CHART — 160px h]   │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Expenditure ──────────┐ │
│ │ Monthly Expenses   [+ Add Expense] │  ← inline add button
│ │ Rent        ████  ₹5,000│ │    category bars
│ │ Electricity ██    ₹2,000│ │
│ │ Internet    █     ₹500  │ │
│ │                         │ │
│ │ [History list...]       │ │
│ └─────────────────────────┘ │
│                             │
│ [Export CSV]                │  ← outlined button, bottom
└─────────────────────────────┘
```

---

# SCREEN-039: Admin Profile Tab

```
ID:       S039
Name:     Admin Profile
Route:    /admin/profile
Role:     Admin
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│         Profile             │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Profile Header ───────┐ │  ← white card
│ │ [PHOTO 80px] Ashish Kumar│ │
│ │ Owner • SILENCE Study Zone│ │    14px #6B7280
│ │ [2 Libraries][Pro Plan] │ │  ← count pills
│ │ ● All systems operational│ │  ← green pill status
│ └─────────────────────────┘ │
│                             │
│ ┌── Your Libraries ───────┐ │
│ │ [lib photo] Downtown     │ │  ← tappable rows
│ │ 120 Members • 86% Occ  > │ │
│ │                          │ │
│ │ [lib photo] City Center  │ │
│ │ 95 Members • 68% Occ   > │ │
│ │                          │ │
│ │ [Manage Libraries]       │ │  ← orange text button
│ └─────────────────────────┘ │
│                             │
│ ┌── Business Settings ────┐ │
│ │ [⏰][💺][📋][⏱] [View All]│ │  ← icon grid 2 rows
│ │ Hours Pricing Rules Shift│ │    icon + label below
│ │ [📊][🎨]                 │ │
│ │ Attend Branding          │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Account ──────────────┐ │
│ │ Edit Profile           >│ │  ← tappable rows
│ │ Subscription           >│ │
│ │ Announcements          >│ │
│ │ Exports & Reports      >│ │
│ │ Audit Log              >│ │
│ │ Referral Settings      >│ │
│ │ Support & Help         >│ │
│ │ About & Legal          >│ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Logout ───────────────┐ │
│ │ 🚪 Logout               │ │  ← red text
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

---

*Part 1 of 3 complete.*
*Part 2 covers: Announcement screens, Library Profile, Subscription, Business Settings, QR Assets.*
*Part 3 covers: All Member screens (Home, Analytics, Profile, QR Scanner, Join Flow).*
