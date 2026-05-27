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

---

## 2. Screen Specification Files (`Part1.md`, `Part2.md`, `Part3.md`) Changes

### Part1.md (Auth, Admin Home, Reservations)

| Screen ID | Change |
|-----------|--------|
| **S004-B** | Quick Actions: changed to 4 buttons (Add Member, Announce, Queries, Close Library). QR Codes section moved below. |
| **S021** | Removed “Library Rules” field. |
| **S022** | Full rewrite – see above (Layout Setup). |
| **S023** | Added “Hourly Plan” toggle and “Payment Options” section inside. |
| **S024** | Deleted (merged into S023). |
| **S010** (Admin Home) | Added loading state to prevent flicker; fixed greeting name. |

### Part2.md (Announcements, Library Profile, Business Settings, Subscription)

| Screen ID | Change |
|-----------|--------|
| **S050** (Subscription) | Plan price changed to ₹799/month for Pro. Plan name “Pro Plan”. |
| **S043** (Library Profile) | No changes. |
| **S044–S058** | No changes. |

### Part3.md (Member Screens, QR Scanner, Join Flow)

| Screen ID | Change |
|-----------|--------|
| **S060** (Member Home) | No changes. |
| **S061** (QR Scanner) | No changes. |
| **S062** (Join Flow) | No changes. |
| **S067–S069** | No changes. |

---

## 3. Database Schema Changes (`supabase_schema.sql`)

Added to `shifts` table:

```sql
ALTER TABLE shifts 
ADD COLUMN IF NOT EXISTS shift_type TEXT DEFAULT 'fixed' CHECK (shift_type IN ('fixed', 'hourly'));

ALTER TABLE shifts 
ADD COLUMN IF NOT EXISTS hours_per_day INTEGER;