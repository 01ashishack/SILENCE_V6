# SILENCE – Changes Applied to Original Specifications (v6.1 → Current)

This document lists all **changes** made to the original PRD and screen specification files during the development process.  
Original files:  
- `SILENCE_PRD_v6.1_Final.md`  
- `18_Screen_by_Screen_Spec_Part1.md`  
- `18_Screen_by_Screen_Spec_Part2.md`  
- `18_Screen_by_Screen_Spec_Part3.md` 

All changes below are **additions, deletions, or modifications** relative to the original v6.1 specs.

---

## 1. PRD (`SILENCE_PRD_v6.1_Final.md`) Changes

| Section | Change | Reason |
|---------|--------|--------|
| **Library Setup Stage 1 (S021)** | Removed entire **“Library Rules / Guidelines”** textarea. | Admin requested no rules field at initial setup; can be added later in Library Profile. |
| **Admin Home – Operational Mode (S004-B)** | **Quick Actions row** now has exactly **4 buttons**: Add Member, Announce, Queries, Close Library. **QR Codes** moved to a separate row below Quick Actions. | Cleaner UI, separates QR from daily actions. |
| **Subscription Screen (S050)** | Plan name changed from “Professional Plan ₹2,999/month” to **“Pro Plan ₹799/month”** (Starter/Basic/Pro model). | Align with actual subscription pricing. |
| **Shift & Plans (S023)** | Added **“Hourly Plan” toggle** within shift card. Admin can choose between “Fixed Hours” (start/end time) or “Hourly Plan” (hours per day). Database columns `shift_type` and `hours_per_day` added. | Support libraries that charge by hour. |
| **Payment Setup (S024)** | Moved **inside** Shifts & Plans screen (S023) as a “Payment Options” section. No longer a separate standalone screen. | Simplify onboarding; keep payment config with shift/pricing. |
| **Layout Setup (S022)** | Complete rewrite: removed pre‑filled dummy data, sections are **optional**, added interactive floor tabs, three‑dot menus for rename/delete, paginated seat grid (30 per page), seat actions bottom sheet. | Match actual library needs; no forced sections. |
| **Library Basic Details (S021)** | Removed **“About Description”** field. | Keep initial setup minimal. |
| **Amenities** | Added **“Add Amenity”** button; admin can add custom amenities. Pre‑defined amenities no longer have delete (✕) buttons; they are toggle‑selectable. | Flexibility. |
| **Photo Upload** | Added **crop/adjust** before upload (1:1 for profile, 16:9 for library cover). | User control over final image. |
| **Safe Area** | Wrapped all screens (except home) with `SafeArea(top: true)` to respect status bar. | Avoid overlap with system UI. |
| **Admin Name Greeting** | Fixed to display `users.full_name` from signup, not “Demo”. | Proper personalization. |
| **Flicker on App Open** | Added `FutureBuilder` / loading state on Admin Home to avoid showing wrong UI before database check. | Smooth UX. |
| **Manage Layout Redesign (S022)** | Replaced standard flat listings with a visual collapsible tree view representing Floor -> Section -> Seats. | High interactive value and cleaner structural visibility. |
| **Tree Action Logic (S022)** | The “+ Add Direct Seat” button is dynamically hidden for any floor that contains at least one section. Only visible if the floor has zero sections. | Strict hierarchy mapping: direct floor-level seats cannot coexist with sections. |
| **Section Tag Display (S022)** | Completely removed tags (e.g. “General”, “VIP”) from section names in the layout tree representation. Displays purely the section name. | Streamline tree readability. |
| **Auto-Prefix Generation (S072)** | Redesigned Add Seat sheet from single input to separate **Prefix** (e.g., “S”) and **Number** (e.g., “1”) fields. System auto-concatenates with a hyphen (`$prefix-$number`) and displays a live preview (e.g., “S-1”). | Improves consistency of seat labelling. |
| **Smart Seat Auto-Fill (S072)** | System automatically analyzes existing seat labels in the floor/section: pre-fills the **Prefix** with the longest common prefix, and sets the **Start Number** to the next available number (highest + 1). | Eliminates redundant manual entry during bulk creation. |
| **High Count Warning (S072)** | Displays an orange/yellow warning banner: *“⚠️ Generating X seats may take a few seconds. Continue?”* when bulk count is >= 100. | Keeps the UI responsive and warns the user about large inserts. |
| **Unique Constraint Pre-Checks** | Performs active database checks before generating/inserting seats, showing a toast warning instead of a database crash for duplicate key values. | Protects database state. |

---

## 2. Screen Specification Files (`Part1.md`, `Part2.md`, `Part3.md`) Changes

### Part1.md (Auth, Admin Home, Reservations, Layout Setup)

| Screen ID | Change |
|-----------|--------|
| **S004-B** | Quick Actions: changed to 4 buttons (Add Member, Announce, Queries, Close Library). QR Codes section moved below. |
| **S021** | Removed “Library Rules” field. |
| **S022** | Full rewrite — redesigned as visual hierarchical tree view (Floor -> Section -> Seats). Shows "+ Add Direct Seat" only if zero sections exist. Excluded section tag labels in tree rows. |
| **S023** | Added “Hourly Plan” toggle and “Payment Options” section inside. |
| **S024** | Deleted (merged into S023). |
| **S010** (Admin Home) | Added loading state to prevent flicker; fixed greeting name. |
| **S025 / S072** | Overhauled seat insertion with dual fields (Prefix, Number), live hyphenated previews, smart pattern auto-filling (LCP for prefix, next incremental integer for numbers), and heavy seat generation warnings. |
| **S011** (QR Modal) | Created overlay popup modal dialog with tabs for Joining and Attendance QRs, custom orange corner bracket painter framing, clipboard copy button, automatic A4 PDF layout generation, sharing sheets, and confirmation regeneration bottom-sheet. |

### Part2.md (Announcements, Library Profile, Business Settings, Subscription)

| Screen ID | Change |
|-----------|--------|
| **S050** (Subscription) | Plan price changed to ₹799/month for Pro. Plan name “Pro Plan”. |
| **S043** (Library Profile) | No changes. |
| **S044–S058** | No changes. |

### Part3.md (Member Home, QR Scanner, Join Flow Wizard)

| Screen ID | Change |
|-----------|--------|
| **S060** (Member Home) | Redesigned orange curved header and announcement feed layout. Displays a unified visual **Profile setup card** that links to a full-screen edit page. Implemented pixel-perfect notch-safe navigation alignment using dummy symmetric opacity spacers and normal-sized FAB to eliminate overlapping. |
| **S060 (Timer & Timers)** | Attendance card utilizes a **live ticking timer** for hourly check-in sessions. Includes custom confirm pause/hold requests and two-tap confirmation sheets for leaving the library. |
| **S061** (QR Scanner) | QR camera overlay styled with modern bracket viewfinders and an animated sweeping orange laser line. Implemented manual block overrides if scan fails 2+ times, and 3-minute anti-spam duplicate scan thresholds. |
| **S062** (Join Flow Wizard) | Multi-step stack wizard featuring UPI receipt uploads to `silence_assets` bucket, deep-linked payment triggers (PhonePe/GPay), cash at library config, and custom referral code checkings. |
| **S065** (Profile Edit Screen) | Created unified full-screen member edit profile screen capturing name, phone, dob, address, exam category, profile picture cropping, and Aadhaar/PAN/Voter ID uploads (mapped to unused `fcm_token` column). |
| **Offline Syncing** | Scans during outage are cached inside local SQLite `offline_scan_queue` table. Automatic listener triggers batch FIFO uploads to Supabase when network connectivity is restored. |

---

## 3. Database Schema Changes (`supabase_schema.sql`)

### 1. Shift Tables (`shifts`)
Added to support hourly-rated study models:
```sql
ALTER TABLE shifts 
ADD COLUMN IF NOT EXISTS shift_type TEXT DEFAULT 'fixed' CHECK (shift_type IN ('fixed', 'hourly'));

ALTER TABLE shifts 
ADD COLUMN IF NOT EXISTS hours_per_day INTEGER;
```

### 2. Layout Cascade Deletion
Configured foreign key constraints to support cascade deletion on database layout removals:
```sql
ALTER TABLE sections
DROP CONSTRAINT IF EXISTS sections_floor_id_fkey,
ADD CONSTRAINT sections_floor_id_fkey FOREIGN KEY (floor_id) REFERENCES floors(id) ON DELETE CASCADE;

ALTER TABLE seats
DROP CONSTRAINT IF EXISTS seats_floor_id_fkey,
ADD CONSTRAINT seats_floor_id_fkey FOREIGN KEY (floor_id) REFERENCES floors(id) ON DELETE CASCADE,
DROP CONSTRAINT IF EXISTS seats_section_id_fkey,
ADD CONSTRAINT seats_section_id_fkey FOREIGN KEY (section_id) REFERENCES sections(id) ON DELETE CASCADE;
```

### 3. SQLite Offline Scan Queue (`offline_scan_queue`)
Created local table inside mobile storage to queue checkins and checkouts during network outages:
```sql
CREATE TABLE IF NOT EXISTS offline_scan_queue (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  member_id TEXT NOT NULL,
  library_id TEXT NOT NULL,
  shift_id TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  qr_version INTEGER NOT NULL,
  device_id TEXT,
  retry_count INTEGER DEFAULT 0,
  synced INTEGER DEFAULT 0,
  created_at TEXT NOT NULL
);
```