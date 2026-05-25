# SILENCE App — Screen-by-Screen Specification
## Part 2 of 3: Announcements · Library Profile · Business Settings · Subscription · QR Assets

---

# SCREEN-040: Announcement Composer (Bottom Sheet)

```
ID:       S040
Name:     Announcement Composer
Type:     Bottom sheet (NOT full screen)
Trigger:  Admin Home → [Announce] quick action
          OR Announcement History → [+ New]
```

**Layout:**
```
┌─────────────────────────────┐
│ [Dim overlay 40%]           │
│ ┌─── Bottom Sheet ────────┐ │  ← slides up, radius 20px top
│ │ ─── drag handle ───     │ │
│ │ New Announcement    ✕   │ │
│ │ ──────────────────────  │ │
│ │                         │ │
│ │ Send To                 │ │  ← section label 12px #6B7280
│ │                         │ │
│ │ ┌──────────────────────┐│ │  ← recipient type cards
│ │ │ 👥 All Members    ●  ││ │    selected = orange border
│ │ │    85 members        ││ │
│ │ └──────────────────────┘│ │
│ │ ┌──────────────────────┐│ │
│ │ │ 👤 Individual Members││ │
│ │ │    Search & select   ││ │
│ │ └──────────────────────┘│ │
│ │ ┌──────────────────────┐│ │
│ │ │ 🎯 Filtered Group    ││ │
│ │ └──────────────────────┘│ │
│ │                         │ │
│ │ (If Filtered Group):    │ │  ← multi-select chips
│ │ [Expiring 7d][Expired]  │ │
│ │ [On Hold][Payment Due]  │ │
│ │ [Absent Today][Absent 3+]│ │
│ │ [Morning][Evening]      │ │
│ │ Preview: 12 members →→  │ │  ← avatar row + count
│ │                         │ │
│ │ Title (optional)        │ │
│ │ ┌──────────────────┐    │ │    80 chars max
│ │ │ Important Notice │    │ │    live counter right
│ │ │              72/80│   │ │
│ │ └──────────────────┘    │ │
│ │                         │ │
│ │ Message *               │ │
│ │ ┌──────────────────┐    │ │    500 chars max
│ │ │ Dear students,   │    │ │    textarea 120px
│ │ │ ...              │    │ │    live counter
│ │ │           450/500│    │ │
│ │ └──────────────────┘    │ │
│ │                         │ │
│ │ [  Send to 85 members  ]│ │  ← orange full width
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

**Pre-send confirmation:**
```
After tapping Send:
Bottom sheet (second one on top):
  "Sending to 85 members"
  [avatar][avatar][avatar][avatar][avatar] and 80 others
  Preview: "Dear students, Library will be..."
  [Cancel] [Send Now]
```

---

# SCREEN-041: Announcement History

```
ID:       S041
Name:     Announcement History
Route:    /admin/announcements
Entry:    Profile tab → Announcements
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Announcements  [+ New]   │  ← new button top right
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Announcement Row ─────┐ │  ← white card per announcement
│ │ Library Closed Tomorrow │ │    title 15px 600
│ │ All Members • 85 sent   │ │    recipient + count 12px #6B7280
│ │ 2 hours ago             │ │    time 11px
│ │ Read: 42/85             │ │  ← read ratio, amber if low
│ └─────────────────────────┘ │
│                             │
│ ┌── Announcement Row ─────┐ │
│ │ Fee Reminder            │ │
│ │ Expiring in 7d • 12 sent│ │
│ │ Yesterday               │ │
│ │ Read: 12/12 ✓           │ │  ← green if all read
│ └─────────────────────────┘ │
│                             │
│ ┌── Empty State ──────────┐ │
│ │ [📢 illustration]       │ │
│ │ No announcements yet    │ │
│ │ [Send your first one →] │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

---

# SCREEN-042: Manage Queries

```
ID:       S042
Name:     Manage Queries
Route:    /admin/queries
Entry:    Profile tab → Support & Help → Manage Queries
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Manage Queries            │
├─────────────────────────────┤
│ [Open ●][Replied][Closed]   │  ← status filter tabs
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Query Card ───────────┐ │
│ │ [📸] Rahul Sharma  [Open]│ │    member photo + name + badge
│ │ Seat G-A-12              │ │
│ │ "My QR is not scanning  │ │    message preview, 2 lines
│ │  properly since..."      │ │
│ │ 2 hours ago              │ │    time 11px #6B7280
│ └─────────────────────────┘ │
│                             │
│ ── QUERY DETAIL (tap) ──    │
│ Full screen stack:          │
│                             │
│ ← Query from Rahul Sharma   │
│ [Member message full]       │  ← white bubble, gray bg
│ [Admin reply section]       │  ← if replied: orange bubble
│                             │
│ ┌── Reply ────────────────┐ │
│ │ [Type your reply...  ]  │ │
│ └─────────────────────────┘ │
│ [Send Reply]                │
└─────────────────────────────┘
```

---

# SCREEN-043: Library Profile Screen

```
ID:       S043
Name:     Library Profile
Route:    /admin/library/:id/profile
Entry:    Profile tab → Your Libraries → tap library
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Library Profile           │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Cover Photo ──────────┐ │  ← full width, 200px height
│ │ [LIBRARY PHOTO]    ✏️   │ │    edit button overlay
│ └─────────────────────────┘ │
│                             │
│ ┌── Identity ─────────────┐ │
│ │ [64px logo] Downtown ✓  │ │  ← verified tick if earned
│ │ Branch Name             │ │
│ │ ★★★★½  4.8 (42 reviews) │ │  ← star rating
│ │ [120 Members]           │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Quick Actions ────────┐ │
│ │[Share][Preview][QR][Edit]│ │  ← 4 icon buttons
│ └─────────────────────────┘ │
│                             │
│ ┌── Profile Completion ───┐ │
│ │ ████████░░  78%         │ │  ← orange progress bar
│ │ Complete to get Verified │ │    motivational text
│ └─────────────────────────┘ │
│                             │
│ ┌── About ────────────────┐ │
│ │ Best study space in...  │ │  ← about text
│ │                  [Edit] │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Stats Row ────────────┐ │
│ │ [120]  [86%]  [3]  [2yr]│ │  ← 4 stats in a row
│ │ Members Occ  Shifts Years│ │    value 18px 700, label 11px
│ └─────────────────────────┘ │
│                             │
│ ┌── Settings List ────────┐ │
│ │ General Information    >│ │  ← tappable rows
│ │ Amenities              >│ │
│ │ Membership Plans       >│ │
│ │ Photos & Gallery       >│ │
│ │ Rules & Guidelines     >│ │
│ │ How to Join            >│ │
│ │ Social Links           >│ │
│ │ Add-on Services        >│ │
│ │ Contact Information    >│ │  ← includes public phone
│ └─────────────────────────┘ │
│                             │
│ ┌── Emergency Contact ────┐ │  ← member-visible section
│ │ 📞 +91 98765 43210      │ │    tap to call
│ │ For urgent queries      │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Social Links ─────────┐ │
│ │ [📸][▶][👍][💬][🌐]     │ │  ← icon row, tappable
│ └─────────────────────────┘ │
│                             │
│ ┌── Ratings & Reviews ────┐ │
│ │ ★ 4.8   ████████ 5★ 32  │ │  ← overall + bar breakdown
│ │         ██████   4★ 8   │ │
│ │         ██       3★ 2   │ │
│ │ [View All Reviews →]    │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Recent Visitors ──────┐ │
│ │ [😊][😊][😊][😊]+12 more│ │  ← avatars, last 7 days
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

---

# SCREEN-044: Business Rules Screen

```
ID:       S044
Name:     Business Rules
Route:    /admin/settings/business-rules
Entry:    Profile tab → Business Settings → Membership Rules
```

**Layout (from screenshot):**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Business Rules            │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Membership ───────────┐ │  ← section header 12px caps #6B7280
│ │ Membership Durations   >│ │    tappable rows
│ │ Manage membership periods│ │    desc 12px #6B7280
│ │                         │ │
│ │ Grace Periods          >│ │
│ │ Configure grace period  │ │
│ │                         │ │
│ │ Late Payment Rules     >│ │
│ │ Set late fee and penalties│ │
│ │                         │ │
│ │ Attendance Rules       >│ │
│ │ Manage attendance policies│ │
│ │                         │ │
│ │ Renewal Rules          >│ │
│ │ Set renewal and expiry  │ │
│ │                         │ │
│ │ Auto-Expiry            >│ │
│ │ Configure auto expiry   │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Toggles ──────────────┐ │
│ │ Allow expired check-in  │ │
│ │ Members scan after exp  │ │
│ │                    [●]  │ │  ← toggle
│ │                         │ │
│ │ Expiry grace before hold│ │
│ │ 3 days          [3   ]  │ │  ← number input
│ │                         │ │
│ │ Max discount allowed    │ │
│ │ 100%            [100 ]  │ │
│ │                         │ │
│ │ Max hold duration (days)│ │
│ │ 30 days         [30  ]  │ │
│ │                         │ │
│ │ Max holds per period    │ │
│ │ 2               [2   ]  │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Scheduled Closures ───┐ │
│ │ Manage Closures        >│ │  ← navigates to S045
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

---

# SCREEN-045: Shift Management Screen (Canonical)

```
ID:       S045
Name:     Shift Management
Route:    /admin/settings/shifts
Entry:    Profile tab → Business Settings → Shift Config
          OR Library Profile → Timings & Shifts
          OR Library Setup Stage 3
Note:     ALL three entry points open this same screen
```

**Layout (from screenshot):**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Shifts          [+ Add]   │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Shift Card ───────────┐ │  ← white card per shift
│ │ ● Morning Shift         │ │    colored dot left (schedule color)
│ │ 6:00 AM – 2:00 PM      │ │    time 13px #6B7280
│ │ Occupancy: 80%  ████░   │ │  ← mini progress bar
│ │ ₹1,500/mo               │ │    price
│ │ Trial: 7 days           │ │    trial config
│ │               [Edit ✏️] │ │  ← edit button right
│ └─────────────────────────┘ │
│                             │
│ ┌── Shift Card ───────────┐ │
│ │ 🟡 Day Shift            │ │
│ │ 2:00 PM – 7:00 PM      │ │
│ │ Occupancy: 65%  ████░   │ │    amber (65%)
│ │ ₹1,200/mo               │ │
│ │               [Edit ✏️] │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Shift Card ───────────┐ │
│ │ 🟢 Evening Shift        │ │
│ │ 7:00 PM – 11:00 PM     │ │
│ │ Occupancy: 75%          │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Shift Card ───────────┐ │
│ │ 🔴 Night Shift          │ │
│ │ 11:00 PM – 6:00 AM     │ │
│ │ Occupancy: 40%  ██░░░   │ │  ← red (low)
│ └─────────────────────────┘ │
│                             │
│ [  + Add New Shift  ]       │  ← orange full-width dashed button
└─────────────────────────────┘
```

**Edit Shift bottom sheet:**
```
Fields: Shift Name, Start Time, End Time, Prices (monthly/3m/6m), Trial Days
Save: upsert to DB (not delete + insert)
```

---

# SCREEN-046: Pricing Plans Screen

```
ID:       S046
Name:     Pricing Plans
Route:    /admin/settings/pricing
Entry:    Profile tab → Business Settings → Seat Pricing
```

**Layout (from screenshot):**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Pricing Plans   [+ Add]   │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Plan Card ────────────┐ │
│ │ Daily Pass              │ │  ← plan name
│ │ Valid for 1 Day         │ │    validity
│ │ ₹150            [Active]│ │  ← price + active toggle
│ └─────────────────────────┘ │
│                             │
│ ┌── Plan Card ────────────┐ │
│ │ Weekly Pass             │ │
│ │ Valid for 7 Days        │ │
│ │ ₹700            [Active]│ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Plan Card ────────────┐ │
│ │ Monthly Pass     [Popular]│ │ ← Popular tag: orange badge
│ │ Valid for 30 Days       │ │
│ │ ₹2,000          [Active]│ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Plan Card ────────────┐ │
│ │ Quarterly Pass          │ │
│ │ Valid for 90 Days       │ │
│ │ ₹5,000         [Inactive]│ │  ← gray toggle
│ └─────────────────────────┘ │
│                             │
│ Popular tag rule shown:     │
│ ℹ Max 1 plan per shift     │
│   can be marked Popular     │
└─────────────────────────────┘
```

---

# SCREEN-047: Branding & Assets

```
ID:       S047
Name:     Branding & Assets
Route:    /admin/settings/branding
```

**Layout (from screenshot):**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Branding & Assets         │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Grid ─────────────────┐ │  ← 3x2 icon grid
│ │ [🖼][🏷][🎨][📋]       │ │
│ │ Cover Logo Theme Print  │ │    icon + label each cell
│ └─────────────────────────┘ │
│                             │
│ ┌── Library Cover Photos ─┐ │
│ │ [photo1][photo2][+ add] │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Logo ─────────────────┐ │
│ │ [LOGO UPLOAD AREA]      │ │
│ │ Tap to upload logo      │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Theme & Colors ───────┐ │
│ │ Primary: [🟠 #E65C00]   │ │  ← color picker
│ └─────────────────────────┘ │
│                             │
│ ┌── Printable Assets ─────┐ │
│ │ Posters, banners & more │ │
│ │ [Generate Assets]       │ │
│ └─────────────────────────┘ │
│                             │
│ [Preview Branding]          │  ← outlined button
└─────────────────────────────┘
```

---

# SCREEN-048: QR Assets Screen

```
ID:       S048
Name:     QR Assets
Route:    /admin/settings/qr
```

**Layout (from screenshot — shows Joining QR tab):**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← QR Assets                 │
├─────────────────────────────┤
│ [Joining QR ●][Attendance QR]│  ← tab switcher
├─────────────────────────────┤
│ [WHITE BODY]                │
│                             │
│ ┌── QR Display ───────────┐ │
│ │     Downtown Branch     │ │    library name
│ │     Scan to Join        │ │    subtitle
│ │                         │ │
│ │  [QR CODE IMAGE 200px]  │ │    centered
│ │  ⌐──────────────────¬  │ │    orange corner brackets
│ │  |                  |  │ │
│ │  |    [QR IMAGE]    |  │ │
│ │  └──────────────────┘  │ │
│ │                         │ │
│ │  [⬇ Download][📤 Share] │ │  ← two buttons
│ │  [🖨 Print Poster]      │ │  ← "Print Poster" full width below
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

---

# SCREEN-049: Export Center

```
ID:       S049
Name:     Export Center
Route:    /admin/exports
```

**Layout (from screenshot):**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Export Center             │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ Date Range: [This Month ▾]  │  ← filter
│                             │
│ ┌── Export Options ───────┐ │
│ │ 📋 Members Export      >│ │  ← row with icon
│ │ Member list and details  │ │    desc 12px
│ │                         │ │
│ │ 📊 Attendance Export   >│ │
│ │ Export attendance records│ │
│ │                         │ │
│ │ 💳 Payments Export     >│ │
│ │ Export payment transactions│ │
│ │                         │ │
│ │ 💰 Revenue Export      >│ │
│ │ Export revenue and income│ │
│ │                         │ │
│ │ 🪑 Occupancy Export    >│ │
│ │ Export seat occupancy   │ │
│ └─────────────────────────┘ │
│                             │
│ Format: [PDF][Excel][CSV●] │  ← CSV only active in V1
│ (PDF/Excel grayed out)      │    grayed: "Coming soon"
└─────────────────────────────┘
```

---

# SCREEN-050: Subscription & Billing

```
ID:       S050
Name:     Subscription
Route:    /admin/subscription
```

**Layout (from screenshot):**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Subscription & Billing    │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Current Plan ─────────┐ │  ← gradient card (orange)
│ │ 👑 Pro Plan            │ │    crown icon
│ │ ₹799/month     [Active] │ │    plan name + price + badge
│ │ Renewal on 12 Jun 2026  │ │    renewal date
│ │                         │ │
│ │ ✓ Up to 5 libraries     │ │    feature list
│ │ ✓ Unlimited members     │ │    checkmarks
│ │ ✓ Analytics & exports   │ │
│ │ ✓ Priority support      │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Plan Features ────────┐ │
│ │ [Plan Features]        >│ │
│ │ View plan features       │ │
│ │                         │ │
│ │ [Billing History]      >│ │
│ │ View invoices            │ │
│ │                         │ │
│ │ [Payment Methods]      >│ │
│ │ Manage payment methods  │ │
│ └─────────────────────────┘ │
│                             │
│ [  Manage Subscription  ]   │  ← orange full-width button
└─────────────────────────────┘
```

**Read-Only state banner (Days 8–30):**
```
Orange non-dismissable banner at top of EVERY screen:
[⚠️ Subscription expired 10 days ago. Renew to restore full access. [Renew Now]]
```

**Full Lock (Day 31+):**
```
Entire app replaced with paywall screen:
  SILENCE logo
  "Your subscription has expired."
  Plan details
  [Renew Now — ₹X/month] orange button
  (Nothing else accessible)
```

---

# SCREEN-051: Notification Preferences

```
ID:       S051
Name:     Notification Preferences
Route:    /admin/settings/notifications
```

**Layout (from screenshot):**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Notification Preferences  │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Notifications ────────┐ │
│ │ Push Notifications      │ │  ← row: label + toggle right
│ │ Receive push notifications│ │   desc 12px below label
│ │                    [●]  │ │  ← toggle ON (orange)
│ │ ─────────────────────── │ │  ← divider
│ │ Payment Reminders  [●]  │ │
│ │ Get payment reminders   │ │
│ │ ─────────────────────── │ │
│ │ Expiry Alerts      [●]  │ │
│ │ Get membership expiry   │ │
│ │ ─────────────────────── │ │
│ │ Attendance Alerts  [○]  │ │  ← OFF
│ │ Get attendance alerts   │ │
│ │ ─────────────────────── │ │
│ │ Announcements      [●]  │ │
│ │ Receive announcements   │ │
│ └─────────────────────────┘ │
│                             │
│ [  Save Preferences  ]      │  ← orange button
└─────────────────────────────┘
```

---

# SCREEN-052: Support & Help

```
ID:       S052
Name:     Support & Help
Route:    /admin/support
```

**Layout (from screenshot):**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Support & Help            │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Help Options ─────────┐ │
│ │ ❓ FAQs                >│ │
│ │ Find answers to questions│ │
│ │                         │ │
│ │ 💬 Contact Support     >│ │
│ │ Chat or call support    │ │
│ │                         │ │
│ │ 💚 WhatsApp Support    >│ │
│ │ Chat on WhatsApp        │ │  ← opens WhatsApp
│ │                         │ │
│ │ 🐛 Report an Issue     >│ │
│ │ Report a bug or issue   │ │
│ │                         │ │
│ │ 📖 App Guide           >│ │
│ │ Learn how to use app    │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

---

# SCREEN-053: About & Legal

```
ID:       S053
Name:     About & Legal
Route:    /admin/about
```

**Layout (from screenshot):**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← About & Legal             │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── About ────────────────┐ │
│ │ ℹ About SILENCE        >│ │
│ │ Version 2.4.0            │ │  ← version shown
│ │                         │ │
│ │ 🔒 Privacy Policy      >│ │
│ │ Read our privacy policy  │ │
│ │                         │ │
│ │ 📄 Terms & Conditions  >│ │
│ │ Read our terms           │ │
│ │                         │ │
│ │ 📜 Licenses            >│ │
│ │ Open source licenses    │ │
│ └─────────────────────────┘ │
│                             │
│ 🚪 Logout                  │  ← red text at bottom
└─────────────────────────────┘
```

---

# SCREEN-054: Verified Badge Screen

```
ID:       S054
Name:     Verified Badge
Route:    /admin/verified-badge
Entry:    Library Profile → Profile Completion bar → "Get Verified"
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Verified Badge            │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Hero ─────────────────┐ │  ← white card, centered
│ │    🎖️                   │ │    large badge icon
│ │  Verified Library        │ │    22px 700
│ │  Stand out on Explore    │ │    14px #6B7280 center
│ └─────────────────────────┘ │
│                             │
│ ┌── Requirements ─────────┐ │
│ │ Criteria                │ │  ← section label
│ │                         │ │
│ │ ✅ Admin profile 100%   │ │  ← green check = met
│ │    Phone verified       │ │    desc 12px
│ │                         │ │
│ │ ✅ Library 30+ days     │ │
│ │                         │ │
│ │ ⏳ 20 payments          │ │  ← amber clock = in progress
│ │    from 10+ members     │ │
│ │    Progress: 12/20      │ │  ← progress bar
│ │                         │ │
│ │ ❌ Library profile 80%  │ │  ← red X = not met
│ │    Currently 65%        │ │
│ │    [Complete Profile →] │ │    action link
│ │                         │ │
│ │ ✅ 10+ check-ins        │ │
│ │                         │ │
│ │ ✅ No open disputes     │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Benefits ─────────────┐ │
│ │ ✓ Orange ✓ on your name │ │
│ │ ✓ Higher Explore ranking│ │
│ │ ✓ Member trust signal   │ │
│ └─────────────────────────┘ │
│                             │
│ [2 more requirements needed]│  ← summary text
│ [Complete remaining steps]  │  ← orange button if close
└─────────────────────────────┘
```

---

# SCREEN-055: Audit Log

```
ID:       S055
Name:     Audit Log
Route:    /admin/audit-log
Entry:    Profile tab → Account → Audit Log
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Audit Log                 │
├─────────────────────────────┤
│ [All][Members][Payments][QR]│  ← filter tabs
│ Last 90 days                │  ← subtitle
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Log Row ──────────────┐ │  ← white card
│ │ [👤 Approved]  2h ago   │ │    action pill (green) + time
│ │ Ananya Gupta approved   │ │    description
│ │ Seat G-A-05, Morning    │ │    detail
│ │ By: You                 │ │    who performed it
│ └─────────────────────────┘ │
│                             │
│ ┌── Log Row ──────────────┐ │
│ │ [💰 Discount]  5h ago   │ │  ← amber pill
│ │ ₹200 discount on Rahul  │ │
│ │ ₹1,500 → ₹1,300         │ │    before/after
│ │ Reason: Regular student │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Log Row ──────────────┐ │
│ │ [🔄 QR Regen]  Yesterday │ │  ← blue pill
│ │ Attendance QR regenerated│ │
│ │ v3 → v4                  │ │    version change
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

---

# SCREEN-056: Scheduled Closures

```
ID:       S056
Name:     Scheduled Closures
Route:    /admin/settings/closures
Entry:    Business Rules → Scheduled Closures
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Scheduled Closures [+ Add]│
├─────────────────────────────┤
│ [Upcoming ●][Past]          │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Closure Card ─────────┐ │
│ │ 🎆 Diwali Break         │ │    name
│ │ Oct 20 – Oct 24, 2026   │ │    date range
│ │ 5 days • All members    │ │    duration + notification sent
│ │ notified ✓              │ │
│ │              [Delete 🗑]│ │    delete (upcoming only)
│ └─────────────────────────┘ │
│                             │
│ ┌── Empty State ──────────┐ │
│ │ 📅 No upcoming closures │ │
│ │ Add holidays or breaks  │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

**Add Closure bottom sheet:**
```
Closure Name: [text input]
Single day / Date range: [toggle]
Start Date: [calendar picker]
End Date: [calendar picker] — if range
Notify Members: [toggle ON]
[Save Closure]
```

---

# SCREEN-057: Add-on Services Management

```
ID:       S057
Name:     Add-on Services
Route:    /admin/settings/addons
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Add-on Services  [+ Add]  │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Add-on Card ──────────┐ │
│ │ 🔒 Locker               │ │    name + icon
│ │ ₹200/month  Recurring   │ │    price + type
│ │ Deposit: ₹500 (refund)  │ │    deposit info
│ │ Available: 8/20         │ │    inventory
│ │                   [●]   │ │    active toggle
│ └─────────────────────────┘ │
│                             │
│ ┌── Add-on Card ──────────┐ │
│ │ ❄️ AC Premium Seat       │ │
│ │ ₹300/month  Recurring   │ │
│ │ No deposit              │ │
│ │ Available: 15/30        │ │
│ │                   [●]   │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

---

# SCREEN-058: Referral Settings

```
ID:       S058
Name:     Referral Settings
Route:    /admin/settings/referrals
Entry:    Profile tab → Account → Referral Settings
```

**Layout:**
```
┌─────────────────────────────┐
│ [ORANGE HEADER]             │
│ ← Referral Settings         │
├─────────────────────────────┤
│ [SCROLLABLE — #FBF5EE]      │
│                             │
│ ┌── Enable Referrals ─────┐ │
│ │ Referral Rewards        │ │
│ │ Reward members for      │ │
│ │ referring new students  │ │
│ │                   [●]   │ │  ← toggle
│ └─────────────────────────┘ │
│                             │
│ ┌── Reward Config ────────┐ │  ← shows when toggle ON
│ │ Free Days for Referrer  │ │
│ │ ┌─────┐                 │ │
│ │ │  3  │ days            │ │    number input
│ │ └─────┘                 │ │
│ │                         │ │
│ │ Free Days for New Member│ │
│ │ ┌─────┐                 │ │
│ │ │  3  │ days            │ │
│ │ └─────┘                 │ │
│ │                         │ │
│ │ ℹ Reward held 7 days or │ │  ← info box
│ │ 5 check-ins (whichever  │ │
│ │ first) to prevent abuse │ │
│ └─────────────────────────┘ │
│                             │
│ ┌── Stats ────────────────┐ │
│ │ Total referrals: 12     │ │
│ │ Pending: 3              │ │
│ │ Rewarded: 9             │ │
│ └─────────────────────────┘ │
│                             │
│ [  Save Settings  ]         │
└─────────────────────────────┘
```

---

*Part 2 of 3 complete.*
*Part 3 covers: Member Home, Member Analytics, Member Profile, QR Scanner, Join Flow, Notifications.*
