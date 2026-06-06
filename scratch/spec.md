<USER_REQUEST>
We need to build the Member History tab (bottom nav tab 3) and its sub‑screens exactly as specified below. Follow the spec strictly.

**Background:** #FBF5EE, no floating button. Use existing design tokens (orange #E65C00, white cards, Outfit/Inter fonts). All data from Supabase.

**Phases:** Do it in phases (1 → 2 → 3). After each phase, send a short screen recording and wait for my approval.

**Performance rule:** Use small, focused queries – not one huge join. Paginate sessions (20 per page). Cache where appropriate.

---

## PHASE 1 – HEADER, GLOBAL FILTERS, SUB‑TABS, SESSIONS SUB‑TAB

### 1.1 Header (orange gradient)
File: `lib/screens/member_history_tab.dart`

- Gradient: `#E65C00` → `#C44E00`, bottom radius 28px, height ~100px including status bar.
- Top row: left – SILENCE logo (small image), center – "History" (white, bold), right – bell icon → navigates to `NotificationsScreen`.
- Below title: small subtitle "Your complete study record" (11px white 70%).

### 1.2 Global Filter Bar (sticky, below header)
Row with three elements:

- **Library selector pill** – only show if member has 2+ libraries.  
  Dropdown shows:
  - "All Libraries" (default)
  - Active libraries (green dot)
  - Past libraries (gray, with exit month/year) – sorted by most recent exit first.
- **Date range pill** – options: This Week / This Month / Last Month / Last 3 Months / This Year / Custom.  
  Custom → opens dual‑month calendar picker (start and end date). Default = This Month.
- **Export button** – outlined orange, 32px height. Tap → export options bottom sheet (implemented in Phase 3).

**Rule:** Both filters apply to all three sub‑tabs. Switching sub‑tab does NOT reset filters.

### 1.3 Sub‑tabs Row (below filter bar)
Three tabs: `Sessions` | `Payments` | `Memberships`  
White background, orange underline + text on active tab. 14px 600, equal width.

### 1.4 Sessions Sub‑tab

#### Summary Strip (four stat chips, horizontal scroll)
- [X Present] [Y Absent] [Z Total H
<truncated 8320 bytes>
ented.
- Loading skeletons for all async sections.
- Error handling: if a query fails, show a friendly error message + retry button.
- Run `flutter analyze` – zero errors.
- Test on a device with:
  - Member with 1 library (library selector hidden)
  - Member with 2+ libraries (selector visible)
  - Member with past memberships
  - Export CSV and PDF for all periods
  - Returning member join flow (recognise, pre‑fill, update, admin notification)

---

## NAVIGATION SUMMARY

| Tap | Destination |
|-----|-------------|
| Bell icon | Notifications |
| Library selector pill | dropdown (active + past libraries) |
| Date range pill | options + custom calendar |
| Export button | export options bottom sheet |
| Session row | Day Detail bottom sheet |
| Payment row | Payment Detail bottom sheet + receipt download |
| Membership card (body) | Membership Detail bottom sheet |
| [View Attendance] (in membership detail) | switch to Sessions sub‑tab, filter to that library |
| [View Payments] (in membership detail) | switch to Payments sub‑tab, filter to that library |
| [Renew Plan] | RenewalScreen |
| [Rejoin] (exited card) | JoinFlow with that library |
| [View Full History] (exited card) | Past Library Detail Screen |
| Past library card (Profile tab) | Past Library Detail Screen |
| [Find a Library] (empty state) | switch to Explore tab |

---

## VERIFICATION AFTER EACH PHASE

After each phase, run `flutter analyze` and send a short video (30‑60 sec) showing the main interactions. I will approve before you move to the next phase.

Do not skip any spec detail. If something is unclear, ask me.
</USER_REQUEST>
<ADDITIONAL_METADATA>
The current local time is: 2026-06-05T17:00:08+05:30.
</ADDITIONAL_METADATA>
<USER_SETTINGS_CHANGE>
The user changed setting `Model Selection` from Gemini 3.5 Flash (Medium) to Gemini 3.5 Flash (High). No need to comment on this change if the user doesn't ask about it. If reporting what model you are, please use a human readable name instead of the exact string.
</USER_SETTINGS_CHANGE>