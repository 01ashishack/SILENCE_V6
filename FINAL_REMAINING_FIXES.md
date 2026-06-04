# FINAL REMAINING FIXES REPORT

This report details remaining stability risks ranked by severity (P0, P1, P2) with exact file names and line numbers. Unused imports, deprecated APIs, style issues, and low-risk analyzer hints have been ignored.

---

## P0: Critical Crash Risks (Realistically Reachable)

### 1. Context Async Gaps (No Mounted Guards in Catch Blocks)
These are locations where an async operation (like database updates or storage uploads) is awaited, and if it fails or returns an error, the `catch` block invokes `BuildContext` operations (like showing a SnackBar) without any `mounted` guard. If the user exits the screen while the operation is pending, the app will crash on error:

* **`lib/screens/reservations/join_flow_screen.dart`**
  * **Line 213**: `ScaffoldMessenger.of(context).showSnackBar(...)` inside `_uploadProofImage()`'s catch block.
  * **Line 337**: `ScaffoldMessenger.of(context).showSnackBar(...)` inside `_submitJoinRequest()`'s catch block.
* **`lib/screens/member_home.dart`**
  * **Line 1868**: `ScaffoldMessenger.of(context).showSnackBar(...)` inside seat-change submission's catch block.
  * **Line 2120**: `ScaffoldMessenger.of(context).showSnackBar(...)` inside hold request submission's catch block.
  * **Line 2374**: `ScaffoldMessenger.of(context).showSnackBar(...)` inside library exit's catch block.
  * **Line 2542**: `ScaffoldMessenger.of(context).showSnackBar(...)` inside scan-to-join's catch block.

### 2. Unmounted Navigation pop
* **`lib/screens/shift_management.dart`**
  * **Line 253**: `Navigator.pop(context);` is executed after an `await` database insert. If the user dismisses the bottom sheet or exits the page before the insert finishes, the context is unmounted when popped.

### 3. Unsafe Null Assertions (!) on JSON maps and Database payloads
If these optional columns or keys are missing or null in the database database payload, these assertions will crash the application immediately:
* **`lib/screens/admin_home.dart`**
  * **Line 2982**: `student['name']![0]` (Will crash with null assertion if name is missing or empty string range error).
  * **Line 3006**: `student['name']!` (Will crash if name is null).
  * **Line 3016**: `student['seat']!` (Will crash if seat label is null).
* **`lib/screens/member_home.dart`**
  * **Line 153**: `final checkInStr = _activeAttendance!['check_in_time'] as String;` (Will crash if active attendance record is null/missing).
  * **Line 253-257**: `_userProfile!['full_name']` (Will crash if profile loading failed or returned null).
* **`lib/screens/reservations/join_flow_screen.dart`**
  * **Lines 231, 233, 236**: `_selectedShift!['price_3month']` (Will crash if shift is null/missing).

### 4. Unsafe Null Assertions (!) on Auth User properties
Supabase phone-only logins will have null emails. Stating `user.email!` unconditionally will crash:
* **`lib/screens/member_profile_edit.dart`**
  * **Line 321**: `'email': user.email!,`
* **`lib/screens/role_selection_screen.dart`**
  * **Line 43**: `'email': user.email!,`
* **`lib/screens/admin_profile_complete.dart`**
  * **Line 339**: `'email': user.email!,`

---

## P1: Important Analyzer Warnings (Guarded but Needs Refactoring)

### 1. BuildContext Async Gaps (Using `context.mounted` in Stateful States)
The compiler flags these with `use_build_context_synchronously` or `guarded by an unrelated mounted check` because `context.mounted` is used inside a `State` class instead of the widget state's own direct `mounted` getter. This should be refactored to `mounted` to align with static analysis requirements:

* **`lib/screens/reservations/member_detail_screen.dart`**
  * **Lines 231, 237, 257, 263**: `if (context.mounted)` should be replaced with `if (mounted)`.
* **`lib/screens/admin_home.dart`**
  * **Lines 2669, 2677**: `if (context.mounted)` should be replaced with `if (mounted)`.
* **`lib/screens/member_home.dart`**
  * **Lines 1861, 2113, 2366, 2533**: `if (context.mounted)` should be replaced with `if (mounted)`.

---

## P2: Low Risk or Safely Guarded Null Assertions

These are null assertions that are already safely guarded by local logical checks, but could be refactored to remove the `!` operator for cleaner code:

* **`lib/screens/admin/add_member_wizard.dart`**
  * **Lines 60, 82, 108**: `_loadDraft(_draftId!);` (Safe: guarded by `_draftId != null`).
  * **Line 292**: `return _memberData.planStartDate!;` (Safe: guarded by check).
  * **Lines 378, 387, 389**: (Safe: guarded by null checks on files).
  * **Line 436**: `_draftId!` (Safe: guarded by null check).
* **`lib/screens/reservations/qr_scanner_screen.dart`**
  * **Line 95**: `_lastScanTime!` (Safe: guarded by `_lastScanTime != null`).
* **`lib/screens/reservations/layout_sub_tab.dart`**
  * **Lines 56-58**: `_seatsChannel!` (Safe: guarded by null checks).
  * **Line 3601**: `_bulkLimitWarning!` (Safe: guarded by null check).

---

## 4. Remaining int.parse/double.parse on User Input

* **None**.
* There are **no remaining unsafe parsing calls** on user-supplied input strings in the entire codebase. (The only remaining `int.parse` in `lib/screens/branding_assets.dart:50` parses a structured database color integer, which is safe).
