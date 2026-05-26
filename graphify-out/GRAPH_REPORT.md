# Graph Report - .  (2026-05-25)

## Corpus Check
- 111 files · ~226,029 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 370 nodes · 385 edges · 22 communities detected
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 8 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Dart Intl Adminhomescreen|Dart Intl Adminhomescreen]]
- [[_COMMUNITY_Build Buildactivefloorcontent Buildbulkaddrow|Build Buildactivefloorcontent Buildbulkaddrow]]
- [[_COMMUNITY_Dart Package Flutter|Dart Package Flutter]]
- [[_COMMUNITY_Addnewshift Addupiid Build|Addnewshift Addupiid Build]]
- [[_COMMUNITY_Window Messagehandler Oncreate|Window Messagehandler Oncreate]]
- [[_COMMUNITY_Authscreen Authscreenstate Build|Authscreen Authscreenstate Build]]
- [[_COMMUNITY_Addupiid Build Buildappbadge|Addupiid Build Buildappbadge]]
- [[_COMMUNITY_Dart Screens Screen|Dart Screens Screen]]
- [[_COMMUNITY_Dart Package Adminprofilecompletescreen|Dart Package Adminprofilecompletescreen]]
- [[_COMMUNITY_Dart Build Dispose|Dart Build Dispose]]
- [[_COMMUNITY_Application Main Init|Application Main Init]]
- [[_COMMUNITY_Build Calendargridpicker Calendargridpickerstate|Build Calendargridpicker Calendargridpickerstate]]
- [[_COMMUNITY_Cache Dart Attendance|Cache Dart Attendance]]
- [[_COMMUNITY_Appdelegate Swift Flutterappdelegate|Appdelegate Swift Flutterappdelegate]]
- [[_COMMUNITY_Swift Mainflutterwindow Registergeneratedplugins|Swift Mainflutterwindow Registergeneratedplugins]]
- [[_COMMUNITY_Cpp Wwinmain Createandattachconsole|Cpp Wwinmain Createandattachconsole]]
- [[_COMMUNITY_Runnertests Swift Testexample|Runnertests Swift Testexample]]
- [[_COMMUNITY_Lldb Handle New|Lldb Handle New]]
- [[_COMMUNITY_Generatedpluginregistrant Java Registerwith|Generatedpluginregistrant Java Registerwith]]
- [[_COMMUNITY_Generatedpluginregistrant Registerwithregistry|Generatedpluginregistrant Registerwithregistry]]
- [[_COMMUNITY_Scenedelegate Flutterscenedelegate Swift|Scenedelegate Flutterscenedelegate Swift]]
- [[_COMMUNITY_Mainactivity|Mainactivity]]

## God Nodes (most connected - your core abstractions)
1. `package:flutter/material.dart` - 13 edges
2. `package:google_fonts/google_fonts.dart` - 12 edges
3. `package:supabase_flutter/supabase_flutter.dart` - 11 edges
4. `AppDelegate` - 8 edges
5. `Create()` - 6 edges
6. `Destroy()` - 6 edges
7. `MessageHandler()` - 5 edges
8. `RunnerTests` - 4 edges
9. `OnCreate()` - 4 edges
10. `WndProc()` - 4 edges

## Surprising Connections (you probably didn't know these)
- `AppDelegate` --inherits--> `FlutterImplicitEngineDelegate`  [EXTRACTED]
  macos/Runner/AppDelegate.swift → ios/Runner/AppDelegate.swift
- `my_application_activate()` --calls--> `fl_register_plugins()`  [INFERRED]
  linux/runner/my_application.cc → linux/flutter/generated_plugin_registrant.cc
- `main()` --calls--> `my_application_new()`  [INFERRED]
  linux/runner/main.cc → linux/runner/my_application.cc
- `OnCreate()` --calls--> `RegisterPlugins()`  [INFERRED]
  windows/runner/flutter_window.cpp → windows/flutter/generated_plugin_registrant.cc
- `OnCreate()` --calls--> `GetClientArea()`  [INFERRED]
  windows/runner/flutter_window.cpp → windows/runner/win32_window.cpp

## Communities (33 total, 6 thin omitted)

### Community 0 - "Dart Intl Adminhomescreen"
Cohesion: 0.04
Nodes (55): AdminHomeScreen, _AdminHomeScreenState, build, _buildAboutLibraryCard, _buildActionIconButton, _buildActionRequiredBanner, _buildActionRequiredRow, _buildAdminDetailsCard (+47 more)

### Community 1 - "Build Buildactivefloorcontent Buildbulkaddrow"
Cohesion: 0.05
Nodes (42): build, _buildActiveFloorContent, _buildBulkAddRow, _buildEmptyFloorState, _buildEmptySectionState, _buildFloorLevelSeats, _buildFloorTabs, _buildSaveButton (+34 more)

### Community 2 - "Dart Package Flutter"
Cohesion: 0.07
Nodes (27): SupabaseConfig, build, MemberHomeScreen, Scaffold, SizedBox, build, _buildRoleCard, GestureDetector (+19 more)

### Community 3 - "Addnewshift Addupiid Build"
Cohesion: 0.07
Nodes (28): _addNewShift, _addUpiId, build, _buildCashToggleCard, _buildPriceField, _buildSectionHeader, _buildShiftCard, _buildTimePicker (+20 more)

### Community 4 - "Window Messagehandler Oncreate"
Cohesion: 0.11
Nodes (19): RegisterPlugins(), FlutterWindow(), OnCreate(), Create(), Destroy(), EnableFullDpiSupportIfAvailable(), GetClientArea(), GetThisFromHandle() (+11 more)

### Community 5 - "Authscreen Authscreenstate Build"
Cohesion: 0.08
Nodes (24): AuthScreen, _AuthScreenState, build, _buildInputField, _buildLoginTab, _buildPrimaryButton, _buildSignupTab, _buildSocialCircleButton (+16 more)

### Community 6 - "Addupiid Build Buildappbadge"
Cohesion: 0.12
Nodes (16): _addUpiId, build, _buildAppBadge, Container, dispose, Icon, initState, PaymentSetupScreen (+8 more)

### Community 7 - "Dart Screens Screen"
Cohesion: 0.12
Nodes (15): build, main, MaterialApp, SilenceApp, core/offline_db.dart, core/supabase_config.dart, screens/admin_home.dart, screens/admin_profile_complete.dart (+7 more)

### Community 8 - "Dart Package Adminprofilecompletescreen"
Cohesion: 0.12
Nodes (15): AdminProfileCompleteScreen, _AdminProfileCompleteScreenState, BucketOptions, build, dispose, Expanded, _getMonthName, Icon (+7 more)

### Community 9 - "Dart Build Dispose"
Cohesion: 0.13
Nodes (14): build, dispose, _generateLibraryCode, GestureDetector, Icon, initState, LibrarySetupStage1Screen, _LibrarySetupStage1ScreenState (+6 more)

### Community 10 - "Application Main Init"
Cohesion: 0.14
Nodes (4): fl_register_plugins(), main(), my_application_activate(), my_application_new()

### Community 11 - "Build Calendargridpicker Calendargridpickerstate"
Cohesion: 0.15
Nodes (12): build, _CalendarGridPicker, _CalendarGridPickerState, DateTime, _daysInMonth, GestureDetector, _getMonthName, initState (+4 more)

### Community 12 - "Cache Dart Attendance"
Cohesion: 0.15
Nodes (12): cache_attendance_today, cache_member_attendance, cache_member_memberships, cache_members, cache_seat_grid, offline_scan_queue, OfflineDatabase, openDatabase (+4 more)

### Community 13 - "Appdelegate Swift Flutterappdelegate"
Cohesion: 0.22
Nodes (3): FlutterAppDelegate, FlutterImplicitEngineDelegate, AppDelegate

### Community 14 - "Swift Mainflutterwindow Registergeneratedplugins"
Cohesion: 0.33
Nodes (3): RegisterGeneratedPlugins(), NSWindow, MainFlutterWindow

### Community 15 - "Cpp Wwinmain Createandattachconsole"
Cohesion: 0.47
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

## Knowledge Gaps
- **264 isolated node(s):** `MainActivity`, `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`, `FlutterAppDelegate`, `FlutterImplicitEngineDelegate`, `-registerWithRegistry` (+259 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `package:flutter/material.dart` connect `Dart Package Flutter` to `Dart Intl Adminhomescreen`, `Build Buildactivefloorcontent Buildbulkaddrow`, `Addnewshift Addupiid Build`, `Authscreen Authscreenstate Build`, `Addupiid Build Buildappbadge`, `Dart Screens Screen`, `Dart Package Adminprofilecompletescreen`, `Dart Build Dispose`, `Build Calendargridpicker Calendargridpickerstate`?**
  _High betweenness centrality (0.170) - this node is a cross-community bridge._
- **Why does `package:google_fonts/google_fonts.dart` connect `Dart Package Flutter` to `Dart Intl Adminhomescreen`, `Build Buildactivefloorcontent Buildbulkaddrow`, `Addnewshift Addupiid Build`, `Authscreen Authscreenstate Build`, `Addupiid Build Buildappbadge`, `Dart Screens Screen`, `Dart Package Adminprofilecompletescreen`, `Dart Build Dispose`, `Build Calendargridpicker Calendargridpickerstate`?**
  _High betweenness centrality (0.155) - this node is a cross-community bridge._
- **Why does `package:supabase_flutter/supabase_flutter.dart` connect `Dart Package Flutter` to `Dart Intl Adminhomescreen`, `Build Buildactivefloorcontent Buildbulkaddrow`, `Addnewshift Addupiid Build`, `Authscreen Authscreenstate Build`, `Addupiid Build Buildappbadge`, `Dart Package Adminprofilecompletescreen`, `Dart Build Dispose`?**
  _High betweenness centrality (0.112) - this node is a cross-community bridge._
- **What connects `MainActivity`, `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`, `FlutterAppDelegate` to the rest of the system?**
  _264 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Dart Intl Adminhomescreen` be split into smaller, more focused modules?**
  _Cohesion score 0.04 - nodes in this community are weakly interconnected._
- **Should `Build Buildactivefloorcontent Buildbulkaddrow` be split into smaller, more focused modules?**
  _Cohesion score 0.05 - nodes in this community are weakly interconnected._
- **Should `Dart Package Flutter` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._