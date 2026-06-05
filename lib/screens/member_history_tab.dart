import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/image_optimizer.dart';
import '../utils/pdf_exporter.dart';
import 'notifications_screen.dart';
import 'reservations/renewal_screen.dart';
import 'reservations/join_flow_screen.dart';
import 'past_library_detail_screen.dart';
import 'package:share_plus/share_plus.dart';

class MemberHistoryTab extends StatefulWidget {
  const MemberHistoryTab({super.key});

  @override
  State<MemberHistoryTab> createState() => _MemberHistoryTabState();
}

class _MemberHistoryTabState extends State<MemberHistoryTab> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;

  // Loading & Error states
  bool _isLoading = true;
  String? _errorMessage;
  bool _isLoadingMoreSessions = false;

  // Filter States
  String _selectedLibraryId = 'All'; // 'All' or libraryId
  String _selectedDateRange = 'This Month'; // This Week, This Month, Last Month, Last 3 Months, This Year, Custom
  DateTimeRange? _customDateRange;

  // Database Data Lists
  List<Map<String, dynamic>> _memberships = [];
  List<Map<String, dynamic>> _attendanceLogs = [];
  List<Map<String, dynamic>> _closures = [];
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _librariesList = [];

  // Sessions Tab State
  String _sessionFilter = 'All'; // All, Present, Absent, Incomplete, Manual, Auto-checkout, Offline Sync
  List<Map<String, dynamic>> _allGeneratedSessions = [];
  List<Map<String, dynamic>> _filteredSessions = [];
  int _visibleSessionsCount = 20;

  // Sessions Aggregate Stats
  int _presentCount = 0;
  int _absentCount = 0;
  double _totalHours = 0.0;
  double _avgHoursPerDay = 0.0;

  // Payments Tab State
  String _paymentFilter = 'All'; // All, Confirmed, Pending, Rejected, Cash, UPI

  // Memberships Tab State
  String _membershipFilter = 'All'; // All, Active, Expired, Exited, Trial, On Hold

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadHistoryData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Helper: Get Resolved Date Range
  DateTimeRange? _getDateRange() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    switch (_selectedDateRange) {
      case 'This Week':
        final weekday = now.weekday;
        final monday = todayStart.subtract(Duration(days: weekday - 1));
        return DateTimeRange(start: monday, end: todayEnd);
      case 'This Month':
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: todayEnd);
      case 'Last Month':
        final lastMonthFirst = DateTime(now.year, now.month - 1, 1);
        final lastMonthLast = DateTime(now.year, now.month, 0, 23, 59, 59, 999);
        return DateTimeRange(start: lastMonthFirst, end: lastMonthLast);
      case 'Last 3 Months':
        return DateTimeRange(start: DateTime(now.year, now.month - 3, 1), end: todayEnd);
      case 'This Year':
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: todayEnd);
      case 'Custom':
        if (_customDateRange != null) {
          return DateTimeRange(
            start: DateTime(_customDateRange!.start.year, _customDateRange!.start.month, _customDateRange!.start.day),
            end: DateTime(_customDateRange!.end.year, _customDateRange!.end.month, _customDateRange!.end.day, 23, 59, 59, 999),
          );
        }
        return null;
      default:
        return null;
    }
  }

  // Load all foundational lists
  Future<void> _loadHistoryData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception("User session missing.");

      // Fetch all memberships
      final membershipsRes = await _supabase
          .from('memberships')
          .select('*, libraries(*), shifts(*), seats(*)')
          .eq('member_id', user.id)
          .order('created_at', ascending: false);
      _memberships = List<Map<String, dynamic>>.from(membershipsRes);

      // Build library dropdown items
      _librariesList = _buildLibraryDropdownItems();

      // Ensure library selection is valid
      if (_selectedLibraryId != 'All') {
        final exists = _librariesList.any((lib) => lib['id'] == _selectedLibraryId);
        if (!exists) {
          _selectedLibraryId = 'All';
        }
      }

      // Fetch scheduled closures
      List<Map<String, dynamic>> closuresList = [];
      try {
        final closuresRes = await _supabase
            .from('scheduled_closures')
            .select('*');
        closuresList = List<Map<String, dynamic>>.from(closuresRes);
        closuresList.sort((a, b) {
          final dateA = a['closure_date'] ?? a['start_date'] ?? a['date'];
          final dateB = b['closure_date'] ?? b['start_date'] ?? b['date'];
          if (dateA == null || dateB == null) return 0;
          return dateB.toString().compareTo(dateA.toString());
        });
      } catch (e) {
        debugPrint('Could not fetch closures: $e');
      }
      _closures = closuresList;

      // Fetch filtered transactions/check-ins
      await _fetchFilteredData();

    } catch (e) {
      debugPrint('Error loading history tab: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Fetch filtered data based on active filters
  Future<void> _fetchFilteredData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Fetch payments
      var payQuery = _supabase
          .from('payments')
          .select('*, memberships(plan_type, shifts(name)), libraries(name, address_street, address_city, address_state)')
          .eq('member_id', user.id);

      if (_selectedLibraryId != 'All') {
        payQuery = payQuery.eq('library_id', _selectedLibraryId);
      }

      final range = _getDateRange();
      if (range != null) {
        payQuery = payQuery
            .gte('payment_date', range.start.toUtc().toIso8601String())
            .lte('payment_date', range.end.toUtc().toIso8601String());
      }

      final payRes = await payQuery.order('payment_date', ascending: false);
      _payments = List<Map<String, dynamic>>.from(payRes);

      // 2. Fetch ALL check-ins in selected period (to build in-memory sessions + calculate stats)
      var attQuery = _supabase
          .from('attendance')
          .select('*, libraries(name), shifts(name), seats(seat_label)')
          .eq('member_id', user.id);

      if (_selectedLibraryId != 'All') {
        attQuery = attQuery.eq('library_id', _selectedLibraryId);
      }
      if (range != null) {
        attQuery = attQuery
            .gte('check_in_time', range.start.toUtc().toIso8601String())
            .lte('check_in_time', range.end.toUtc().toIso8601String());
      }

      final attRes = await attQuery.order('check_in_time', ascending: false);
      _attendanceLogs = List<Map<String, dynamic>>.from(attRes);

      // Calculate aggregate stats
      _calculateSessionStats(_attendanceLogs, range);

      // Generate in-memory sessions list
      _generateSessionsList(range);

    } catch (e) {
      debugPrint('Error fetching filtered history lists: $e');
    }
  }

  // Build the unique list of libraries for dropdown filtering
  List<Map<String, dynamic>> _buildLibraryDropdownItems() {
    final Map<String, Map<String, dynamic>> libMap = {};
    final Map<String, bool> isActiveMap = {};
    final Map<String, DateTime?> exitDateMap = {};

    for (var m in _memberships) {
      final lib = m['libraries'] as Map<String, dynamic>?;
      if (lib == null) continue;
      final libId = lib['id'] as String;
      libMap[libId] = lib;

      final status = (m['status'] ?? '').toString().toLowerCase();
      final isActive = status == 'active' || status == 'trial' || status == 'hold';

      if (isActive) {
        isActiveMap[libId] = true;
      } else {
        isActiveMap.putIfAbsent(libId, () => false);
      }

      final exitStr = m['exited_at'] ?? m['end_date'];
      if (exitStr != null) {
        final exitDate = DateTime.tryParse(exitStr);
        if (exitDate != null) {
          final currentExit = exitDateMap[libId];
          if (currentExit == null || exitDate.isAfter(currentExit)) {
            exitDateMap[libId] = exitDate;
          }
        }
      }
    }

    final activeLibs = <Map<String, dynamic>>[];
    final pastLibs = <Map<String, dynamic>>[];

    libMap.forEach((libId, lib) {
      final isActive = isActiveMap[libId] ?? false;
      if (isActive) {
        activeLibs.add({
          'id': libId,
          'name': lib['name'],
          'isActive': true,
        });
      } else {
        final exitDate = exitDateMap[libId];
        pastLibs.add({
          'id': libId,
          'name': lib['name'],
          'isActive': false,
          'exitDate': exitDate,
          'exitLabel': exitDate != null ? DateFormat('MMM yyyy').format(exitDate) : 'N/A',
        });
      }
    });

    // Sort past libraries by most recent exit date first
    pastLibs.sort((a, b) {
      final dateA = a['exitDate'] as DateTime?;
      final dateB = b['exitDate'] as DateTime?;
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return 1;
      if (dateB == null) return -1;
      return dateB.compareTo(dateA);
    });

    return [
      {'id': 'All', 'name': 'All Libraries', 'isActive': null},
      ...activeLibs,
      ...pastLibs,
    ];
  }

  // Calculate stats for summary strip
  void _calculateSessionStats(List<Map<String, dynamic>> logs, DateTimeRange? range) {
    _presentCount = 0;
    _absentCount = 0;
    _totalHours = 0.0;
    _avgHoursPerDay = 0.0;

    if (range == null) return;

    // Count present check-ins
    _presentCount = logs.length;

    // Total hours calculated from completed sessions
    for (var a in logs) {
      if (a['check_in_time'] != null && a['check_out_time'] != null) {
        final ci = DateTime.parse(a['check_in_time']);
        final co = DateTime.parse(a['check_out_time']);
        final diff = co.difference(ci).inMinutes;
        _totalHours += diff / 60.0;
      }
    }

    // Days present (unique days checked in)
    final Set<String> presentDays = {};
    for (var a in logs) {
      if (a['check_in_time'] != null) {
        final date = DateTime.parse(a['check_in_time']).toLocal();
        presentDays.add(DateFormat('yyyy-MM-dd').format(date));
      }
    }
    final uniqueDaysPresent = presentDays.length;

    // Elapsed Days
    final elapsedDays = range.end.difference(range.start).inDays + 1;

    // Closed Days
    final Set<String> uniqueClosed = {};
    for (var c in _closures) {
      final dateStr = c['closure_date'] ?? c['start_date'] ?? c['date'];
      if (dateStr == null) continue;
      if (_selectedLibraryId != 'All' && c['library_id'] != _selectedLibraryId) continue;
      final date = DateTime.parse(dateStr.toString());
      if (date.isAfter(range.start.subtract(const Duration(days: 1))) && date.isBefore(range.end.add(const Duration(days: 1)))) {
        uniqueClosed.add(dateStr.toString().split('T').first);
      }
    }
    final closedDaysCount = uniqueClosed.length;

    // Absent Days = Total days - studied days - closed days
    int calcAbsent = elapsedDays - uniqueDaysPresent - closedDaysCount;
    _absentCount = calcAbsent < 0 ? 0 : calcAbsent;

    // Average Hours per Present Day
    _avgHoursPerDay = uniqueDaysPresent > 0 ? _totalHours / uniqueDaysPresent : 0.0;
  }

  // Check if user had a membership on a particular date
  bool _hasActiveMembershipOn(DateTime date) {
    for (var m in _memberships) {
      if (m['start_date'] == null) continue;
      final start = DateTime.parse(m['start_date']);
      final end = m['exited_at'] != null 
          ? DateTime.parse(m['exited_at'])
          : (m['end_date'] != null ? DateTime.parse(m['end_date']) : DateTime.now());

      final d = DateTime(date.year, date.month, date.day);
      final s = DateTime(start.year, start.month, start.day);
      final e = DateTime(end.year, end.month, end.day);

      if ((d.isAfter(s) || d.isAtSameMomentAs(s)) && (d.isBefore(e) || d.isAtSameMomentAs(e))) {
        return true;
      }
    }
    return false;
  }

  // Assemble full attendance, absent, and closed days list
  void _generateSessionsList(DateTimeRange? range) {
    _allGeneratedSessions = [];
    if (range == null) return;

    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);

    // Group logs by date
    final Map<String, List<Map<String, dynamic>>> logsMap = {};
    for (var a in _attendanceLogs) {
      if (a['check_in_time'] == null) continue;
      final ci = DateTime.parse(a['check_in_time']).toLocal();
      final key = DateFormat('yyyy-MM-dd').format(ci);
      logsMap.putIfAbsent(key, () => []).add(a);
    }

    // Collect closure dates
    final Set<String> closedDates = {};
    final Map<String, String> closedReasons = {};
    for (var c in _closures) {
      final dateStr = c['closure_date'] ?? c['start_date'] ?? c['date'];
      if (dateStr == null) continue;
      final formattedStr = dateStr.toString().split('T').first;
      closedDates.add(formattedStr);
      closedReasons[formattedStr] = c['reason'] ?? 'Scheduled Closure';
    }

    var curr = end;
    while (curr.isAfter(start) || curr.isAtSameMomentAs(start)) {
      final dateKey = DateFormat('yyyy-MM-dd').format(curr);
      final isFuture = curr.isAfter(DateTime.now());

      if (logsMap.containsKey(dateKey)) {
        final list = logsMap[dateKey]!;
        for (var a in list) {
          final isSync = a['offline_synced'] == true || a['device_id'] == 'mobile_offline';
          final co = a['check_out_time'];
          final type = a['session_type'] ?? 'normal';

          String subType = 'normal';
          if (co == null) {
            subType = 'incomplete';
          } else if (type == 'manual' || type == 'admin_edited') {
            subType = 'manual';
          } else if (type == 'auto_checkout') {
            subType = 'auto_checkout';
          } else if (isSync) {
            subType = 'offline_sync';
          }

          _allGeneratedSessions.add({
            'type': 'present',
            'session_type': subType,
            'date': curr,
            'data': a,
          });
        }
      } else if (closedDates.contains(dateKey) && !isFuture) {
        _allGeneratedSessions.add({
          'type': 'closed',
          'session_type': 'closed',
          'date': curr,
          'reason': closedReasons[dateKey] ?? 'Library Closed',
        });
      } else if (!isFuture && _hasActiveMembershipOn(curr)) {
        _allGeneratedSessions.add({
          'type': 'absent',
          'session_type': 'absent',
          'date': curr,
        });
      }

      curr = curr.subtract(const Duration(days: 1));
    }

    _applySessionsFilter();
  }

  // Filter sessions based on filter chips
  void _applySessionsFilter() {
    setState(() {
      _filteredSessions = _allGeneratedSessions.where((s) {
        if (_sessionFilter == 'All') return true;
        if (_sessionFilter == 'Present') return s['type'] == 'present';
        if (_sessionFilter == 'Absent') return s['type'] == 'absent';

        if (s['type'] != 'present') return false;
        final subType = s['session_type'];
        if (_sessionFilter == 'Incomplete') return subType == 'incomplete';
        if (_sessionFilter == 'Manual') return subType == 'manual';
        if (_sessionFilter == 'Auto-checkout') return subType == 'auto_checkout';
        if (_sessionFilter == 'Offline Sync') return subType == 'offline_sync';
        return true;
      }).toList();
    });
  }

  // Switch tabs programmatically
  void _switchToTab(int index, String? filterLibraryId) {
    if (filterLibraryId != null) {
      setState(() {
        _selectedLibraryId = filterLibraryId;
      });
    }
    _tabController.animateTo(index);
    _fetchFilteredData();
  }

  // Trigger custom calendar range picker
  Future<void> _selectCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 30)),
            end: DateTime.now(),
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFE65C00),
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _selectedDateRange = 'Custom';
      });
      _fetchFilteredData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF5EE),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header
          _buildHeader(),
          // 2. Global Filters
          _buildGlobalFilterBar(),
          // 3. Sub-tabs Tabs Row
          _buildSubTabsRow(),
          // 4. Content Area
          Expanded(
            child: _isLoading
                ? _buildSkeletonLoader()
                : _errorMessage != null
                    ? _buildErrorWidget()
                    : TabBarView(
                        controller: _tabController,
                        physics: const NeverScrollableScrollPhysics(), // Handle swipes programmatically
                        children: [
                          _buildSessionsSubTab(),
                          _buildPaymentsSubTab(),
                          _buildMembershipsSubTab(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // HEADER
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12, bottom: 20, left: 20, right: 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE65C00), Color(0xFFC44E00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Image.asset(
                    'assets/images/transparent_logo_with_white_name.png',
                    height: 24,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Text(
                      'SILENCE',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                'History',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Colors.white),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Your complete study record',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // GLOBAL FILTER BAR
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildGlobalFilterBar() {
    final showLibrarySelector = _librariesList.length > 2; // >1 library plus 'All' item

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFFBF5EE),
      child: Row(
        children: [
          // Library selector pill
          if (showLibrarySelector) ...[
            _buildLibrarySelectorPill(),
            const SizedBox(width: 8),
          ],
          // Date range pill
          Expanded(child: _buildDateRangeSelectorPill()),
          const SizedBox(width: 8),
          // Export button
          _buildExportButton(),
        ],
      ),
    );
  }

  Widget _buildLibrarySelectorPill() {
    final selectedLib = _librariesList.firstWhere(
      (lib) => lib['id'] == _selectedLibraryId,
      orElse: () => {'name': 'All Libraries', 'isActive': null},
    );

    return InkWell(
      onTap: () => _showLibrarySelectionPopup(),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectedLib['isActive'] != null)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: selectedLib['isActive'] == true ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
                  shape: BoxShape.circle,
                ),
              ),
            Text(
              selectedLib['name'] ?? 'All Libraries',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
            ),
            const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }

  void _showLibrarySelectionPopup() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'LibrarySwitcher',
      barrierColor: Colors.black.withOpacity(0.15),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: const Alignment(-0.8, -0.45),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 240,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 8))],
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  ..._librariesList.map((lib) {
                    final bool isSel = lib['id'] == _selectedLibraryId;
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          _selectedLibraryId = lib['id'];
                        });
                        _fetchFilteredData();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            if (lib['isActive'] != null)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: lib['isActive'] == true ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
                                  shape: BoxShape.circle,
                                ),
                              )
                            else
                              const Icon(Icons.apps_rounded, size: 14, color: Color(0xFF64748B)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                lib['name'] ?? '',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                  color: const Color(0xFF1E293B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (lib['exitLabel'] != null) ...[
                              const SizedBox(width: 4),
                              Text(
                                '(${lib['exitLabel']})',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                              ),
                            ],
                            if (isSel)
                              const Icon(Icons.check, color: Color(0xFFE65C00), size: 16),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(opacity: anim1, child: child);
      },
    );
  }

  Widget _buildDateRangeSelectorPill() {
    final label = _selectedDateRange == 'Custom' && _customDateRange != null
        ? '${DateFormat('dd MMM').format(_customDateRange!.start)} - ${DateFormat('dd MMM').format(_customDateRange!.end)}'
        : _selectedDateRange;

    return InkWell(
      onTap: () => _showDateRangeOptionsDialog(),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(Icons.date_range_outlined, size: 14, color: Color(0xFF64748B)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }

  void _showDateRangeOptionsDialog() {
    final options = ['This Week', 'This Month', 'Last Month', 'Last 3 Months', 'This Year', 'Custom'];
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Select Period',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ...options.map((opt) {
                  final isSel = _selectedDateRange == opt;
                  return ListTile(
                    dense: true,
                    title: Text(
                      opt,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        color: isSel ? const Color(0xFFE65C00) : const Color(0xFF1E293B),
                      ),
                    ),
                    trailing: isSel ? const Icon(Icons.check, color: Color(0xFFE65C00)) : null,
                    onTap: () {
                      Navigator.pop(context);
                      if (opt == 'Custom') {
                        _selectCustomDateRange();
                      } else {
                        setState(() {
                          _selectedDateRange = opt;
                        });
                        _fetchFilteredData();
                      }
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildExportButton() {
    return InkWell(
      onTap: () => _showExportOptionsBottomSheet(),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE65C00)),
        ),
        alignment: Alignment.center,
        child: Row(
          children: [
            const Icon(Icons.file_upload_outlined, size: 14, color: Color(0xFFE65C00)),
            const SizedBox(width: 4),
            Text(
              'Export',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // SUB-TABS ROW
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildSubTabsRow() {
    return Container(
      color: Colors.white,
      height: 48,
      child: TabBar(
        controller: _tabController,
        indicatorColor: const Color(0xFFE65C00),
        indicatorWeight: 3,
        labelColor: const Color(0xFFE65C00),
        unselectedLabelColor: const Color(0xFF64748B),
        labelStyle: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold),
        unselectedLabelStyle: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: 'Sessions'),
          Tab(text: 'Payments'),
          Tab(text: 'Memberships'),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // SESSIONS SUB-TAB
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildSessionsSubTab() {
    if (_allGeneratedSessions.isEmpty) {
      return _buildSessionsEmptyState();
    }

    final grouped = _groupSessions(_filteredSessions.take(_visibleSessionsCount).toList());
    final sortedKeys = grouped.keys.toList();

    return RefreshIndicator(
      onRefresh: _loadHistoryData,
      color: const Color(0xFFE65C00),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // Summary Stats Strip
          _buildSessionsSummaryStrip(),
          const SizedBox(height: 16),

          // Filter chips
          _buildSessionsFilterChips(),
          const SizedBox(height: 16),

          if (_filteredSessions.isEmpty) ...[
            const SizedBox(height: 32),
            Center(
              child: Text(
                'No sessions found matching this filter.',
                style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13),
              ),
            ),
          ] else ...[
            ...sortedKeys.map((key) {
              final list = grouped[key]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSessionGroupHeader(key, list),
                  const SizedBox(height: 8),
                  ...list.map((s) => _buildSessionRow(s)),
                  const SizedBox(height: 16),
                ],
              );
            }),
            if (_filteredSessions.length > _visibleSessionsCount)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 24.0),
                child: Center(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _visibleSessionsCount += 20;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE65C00)),
                      foregroundColor: const Color(0xFFE65C00),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: _isLoadingMoreSessions
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE65C00)))
                        : Text('Load More Sessions', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionsSummaryStrip() {
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildStatChip('Present', '$_presentCount Days', Icons.check_circle_outline, const Color(0xFF22C55E)),
          const SizedBox(width: 10),
          _buildStatChip('Absent', '$_absentCount Days', Icons.cancel_outlined, const Color(0xFFEF4444)),
          const SizedBox(width: 10),
          _buildStatChip('Total Hours', '${_totalHours.toStringAsFixed(1)} hrs', Icons.schedule, const Color(0xFFE65C00)),
          const SizedBox(width: 10),
          _buildStatChip('Avg Hours/Day', '${_avgHoursPerDay.toStringAsFixed(1)} hrs', Icons.analytics_outlined, const Color(0xFF0284C7)),
        ],
      ),
    );
  }

  Widget _buildStatChip(String title, String value, IconData icon, Color color) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B))),
                Text(value, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsFilterChips() {
    final filters = ['All', 'Present', 'Absent', 'Incomplete', 'Manual', 'Auto-checkout', 'Offline Sync'];
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSel = _sessionFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(filter),
              selected: isSel,
              selectedColor: const Color(0xFFE65C00),
              labelStyle: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isSel ? Colors.white : const Color(0xFF475569),
              ),
              onSelected: (val) {
                if (val) {
                  setState(() {
                    _sessionFilter = filter;
                    _applySessionsFilter();
                  });
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildSessionGroupHeader(String key, List<Map<String, dynamic>> list) {
    // Calculate sum of hours for this group
    double groupHours = 0.0;
    int groupPresents = 0;
    for (var s in list) {
      if (s['type'] == 'present') {
        groupPresents++;
        final data = s['data'] as Map<String, dynamic>?;
        if (data != null && data['check_in_time'] != null && data['check_out_time'] != null) {
          final ci = DateTime.parse(data['check_in_time']);
          final co = DateTime.parse(data['check_out_time']);
          groupHours += co.difference(ci).inMinutes / 60.0;
        }
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          key,
          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
        ),
        Text(
          '$groupPresents Studied  •  ${groupHours.toStringAsFixed(1)} hrs',
          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildSessionRow(Map<String, dynamic> s) {
    final type = s['type'];
    final date = s['date'] as DateTime;
    final dateStr = DateFormat('dd MMM').format(date);

    if (type == 'closed') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFECDD3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_busy, color: Color(0xFFF43F5E), size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Library Closed • $dateStr', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFBE123C))),
                  Text(s['reason'] ?? 'Scheduled Closure', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFE11D48))),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (type == 'absent') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: Color(0xFF64748B), size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Absent • $dateStr',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
              ),
            ),
          ],
        ),
      );
    }

    // Present sessions
    final data = s['data'] as Map<String, dynamic>;
    final ciStr = data['check_in_time'] as String;
    final coStr = data['check_out_time'] as String?;
    final libName = data['libraries']?['name'] ?? 'SILENCE Study';
    final seatLabel = data['seats']?['seat_label'] ?? 'N/A';
    final shiftName = data['shifts']?['name'] ?? 'N/A';

    String ciTime = 'N/A';
    String coTime = 'Ongoing';
    String duration = '';

    try {
      final ci = DateTime.parse(ciStr).toLocal();
      ciTime = DateFormat('hh:mm a').format(ci);
      if (coStr != null) {
        final co = DateTime.parse(coStr).toLocal();
        coTime = DateFormat('hh:mm a').format(co);
        final diff = co.difference(ci);
        duration = '${diff.inHours}h ${diff.inMinutes % 60}m';
      }
    } catch (_) {}

    Color badgeBg = const Color(0xFFDCFCE7);
    Color badgeTxt = const Color(0xFF16A34A);
    String badgeLabel = 'NORMAL';

    final subType = s['session_type'];
    if (subType == 'incomplete') {
      badgeBg = const Color(0xFFFEF3C7);
      badgeTxt = const Color(0xFFD97706);
      badgeLabel = 'ONGOING';
    } else if (subType == 'manual') {
      badgeBg = const Color(0xFFEFF6FF);
      badgeTxt = const Color(0xFF2563EB);
      badgeLabel = 'MANUAL';
    } else if (subType == 'auto_checkout') {
      badgeBg = const Color(0xFFF3E8FF);
      badgeTxt = const Color(0xFF7C3AED);
      badgeLabel = 'AUTO OUT';
    } else if (subType == 'offline_sync') {
      badgeBg = const Color(0xFFECFDF5);
      badgeTxt = const Color(0xFF059669);
      badgeLabel = 'SYNCED';
    }

    return InkWell(
      onTap: () => _showDayDetailBottomSheet(s),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Color(0xFFFFF3ED), shape: BoxShape.circle),
              child: const Icon(Icons.login, color: Color(0xFFE65C00), size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$dateStr • $ciTime - $coTime',
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          badgeLabel,
                          style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: badgeTxt),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$libName • Seat $seatLabel • $shiftName',
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                  ),
                  if (duration.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Duration: $duration',
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _calculateActiveStreak() {
    if (_attendanceLogs.isEmpty) return 0;
    final Set<String> uniqueDates = {};
    for (var l in _attendanceLogs) {
      if (l['check_in_time'] != null) {
        final date = DateTime.parse(l['check_in_time'] as String).toLocal();
        uniqueDates.add(DateFormat('yyyy-MM-dd').format(date));
      }
    }
    final sortedDates = uniqueDates.map((d) => DateTime.parse(d)).toList()..sort();
    if (sortedDates.isEmpty) return 0;

    int bestStreak = 0;
    int currentStreak = 1;

    for (int i = 0; i < sortedDates.length - 1; i++) {
      final diff = sortedDates[i+1].difference(sortedDates[i]).inDays;
      if (diff == 1) {
        currentStreak++;
      } else if (diff > 1) {
        if (currentStreak > bestStreak) {
          bestStreak = currentStreak;
        }
        currentStreak = 1;
      }
    }
    if (currentStreak > bestStreak) {
      bestStreak = currentStreak;
    }
    return bestStreak;
  }

  Future<void> _openWhatsApp(String phone, String message) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    final urlStr = "https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}";
    final uri = Uri.parse(urlStr);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $urlStr';
      }
    } catch (e) {
      debugPrint('WhatsApp launch failed: $e');
    }
  }

  void _showDayDetailBottomSheet(Map<String, dynamic> s) {
    final data = s['data'] as Map<String, dynamic>;
    final ciStr = data['check_in_time'] as String;
    final coStr = data['check_out_time'] as String?;
    final libName = data['libraries']?['name'] ?? 'SILENCE Study Zone';
    final seatLabel = data['seats']?['seat_label'] ?? 'N/A';
    final shiftName = data['shifts']?['name'] ?? 'N/A';
    final note = data['edit_reason'] ?? '';

    String dateStr = 'N/A';
    String ciTime = 'N/A';
    String coTime = 'Ongoing';
    String duration = 'N/A';

    try {
      final date = s['date'] as DateTime;
      dateStr = DateFormat('EEEE, dd MMMM yyyy').format(date);
      final ci = DateTime.parse(ciStr).toLocal();
      ciTime = DateFormat('hh:mm a').format(ci);
      if (coStr != null) {
        final co = DateTime.parse(coStr).toLocal();
        coTime = DateFormat('hh:mm a').format(co);
        final diff = co.difference(ci);
        duration = '${diff.inHours} hours, ${diff.inMinutes % 60} minutes';
      }
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Study Session Details',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _buildDetailRow('Library', libName),
              _buildDetailRow('Date', dateStr),
              _buildDetailRow('Check-in', ciTime),
              _buildDetailRow('Check-out', coTime),
              _buildDetailRow('Duration', duration),
              _buildDetailRow('Shift Assigned', shiftName),
              _buildDetailRow('Seat Assigned', seatLabel),
              _buildDetailRow('Sync Mode', data['offline_synced'] == true ? 'Offline Synced' : 'Online Check-in'),
              if (note.isNotEmpty) _buildDetailRow('Admin Notes', note),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Close Details'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No study logs found',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            Text(
              'Verify you have selected the correct library or date range above.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _loadHistoryData(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
              ),
              child: const Text('Refresh Screen'),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // PAYMENTS SUB-TAB
  // ───────────────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filteredPayments {
    return _payments.where((p) {
      final status = (p['status'] ?? 'pending').toString().toLowerCase();
      final method = (p['method'] ?? 'cash').toString().toLowerCase();
      if (_paymentFilter == 'Confirmed') return status == 'confirmed';
      if (_paymentFilter == 'Pending') return status == 'pending';
      if (_paymentFilter == 'Rejected') return status == 'rejected';
      if (_paymentFilter == 'Cash') return method == 'cash';
      if (_paymentFilter == 'UPI') return method == 'upi';
      return true;
    }).toList();
  }

  Widget _buildPaymentsSubTab() {
    if (_payments.isEmpty) {
      return _buildPaymentsEmptyState();
    }

    final filtered = _filteredPayments;

    // Group by month
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var p in filtered) {
      if (p['payment_date'] == null) continue;
      final date = DateTime.parse(p['payment_date']).toLocal();
      final key = DateFormat('MMMM yyyy').format(date);
      grouped.putIfAbsent(key, () => []).add(p);
    }

    final sortedMonths = grouped.keys.toList();

    // Sum total paid across all filtered payments
    final double totalPaid = _payments
        .where((p) => p['status'] == 'confirmed')
        .fold<double>(0.0, (sum, p) => sum + (p['amount'] as num? ?? 0).toDouble());

    final double totalPending = _payments
        .where((p) => p['status'] == 'pending')
        .fold<double>(0.0, (sum, p) => sum + (p['amount'] as num? ?? 0).toDouble());

    final int totalCount = _payments.length;

    return RefreshIndicator(
      onRefresh: _loadHistoryData,
      color: const Color(0xFFE65C00),
      child: Stack(
        children: [
          ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              // Summary stats strip
              _buildPaymentsSummaryStrip(totalPaid, totalPending, totalCount),
              const SizedBox(height: 16),

              // Filter chips
              _buildPaymentsFilterChips(),
              const SizedBox(height: 16),

              if (filtered.isEmpty) ...[
                const SizedBox(height: 32),
                Center(
                  child: Text(
                    'No payments found matching this filter.',
                    style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13),
                  ),
                ),
              ] else ...[
                ...sortedMonths.map((month) {
                  final list = grouped[month]!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPaymentMonthHeader(month, list),
                      const SizedBox(height: 8),
                      ...list.map((p) => _buildPaymentRow(p)),
                      const SizedBox(height: 16),
                    ],
                  );
                }),
              ],
              const SizedBox(height: 100), // space for total card
            ],
          ),
          // Sticky Bottom Total card
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _buildPaymentsBottomStickyCard(totalPaid, totalPending, totalCount),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsSummaryStrip(double paid, double pending, int count) {
    final isDuesPending = pending > 0;
    return Row(
      children: [
        Expanded(
          child: _buildStatChip('Total Paid', '₹${paid.toInt()}', Icons.check_circle, const Color(0xFF22C55E)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatChip(
            'Pending Dues',
            '₹${pending.toInt()}',
            Icons.pending,
            isDuesPending ? const Color(0xFFD97706) : const Color(0xFF16A34A),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatChip('Total Payments', '$count Invoices', Icons.receipt_long, const Color(0xFFE65C00)),
        ),
      ],
    );
  }

  Widget _buildPaymentsFilterChips() {
    final filters = ['All', 'Confirmed', 'Pending', 'Rejected', 'Cash', 'UPI'];
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSel = _paymentFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(filter),
              selected: isSel,
              selectedColor: const Color(0xFFE65C00),
              labelStyle: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isSel ? Colors.white : const Color(0xFF475569),
              ),
              onSelected: (val) {
                if (val) {
                  setState(() {
                    _paymentFilter = filter;
                  });
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildPaymentMonthHeader(String month, List<Map<String, dynamic>> list) {
    final double monthSum = list
        .where((p) => p['status'] == 'confirmed')
        .fold<double>(0.0, (sum, p) => sum + (p['amount'] as num? ?? 0).toDouble());

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(month, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF475569))),
        Text('Month Collections: ₹${monthSum.toInt()}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A))),
      ],
    );
  }

  Widget _buildPaymentRow(Map<String, dynamic> p) {
    final amount = p['amount'] ?? 0;
    final status = (p['status'] ?? 'pending').toString().toLowerCase();
    final method = (p['method'] ?? 'cash').toString().toUpperCase();
    final libName = p['libraries']?['name'] ?? 'Study Center';
    final ref = p['ref_id'] ?? '';
    final refShort = ref.length > 6 ? ref.substring(ref.length - 6) : ref;

    String dateStr = 'N/A';
    try {
      if (p['payment_date'] != null) {
        dateStr = DateFormat('dd MMM yyyy').format(DateTime.parse(p['payment_date']).toLocal());
      }
    } catch (_) {}

    Color statusBg = const Color(0xFFF1F5F9);
    Color statusTxt = const Color(0xFF475569);
    if (status == 'confirmed') {
      statusBg = const Color(0xFFDCFCE7);
      statusTxt = const Color(0xFF16A34A);
    } else if (status == 'rejected') {
      statusBg = const Color(0xFFFEE2E2);
      statusTxt = const Color(0xFFDC2626);
    } else if (status == 'pending') {
      statusBg = const Color(0xFFFEF3C7);
      statusTxt = const Color(0xFFD97706);
    }

    return InkWell(
      onTap: () => _showPaymentDetailBottomSheet(p),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: status == 'confirmed' ? const Color(0xFFDCFCE7) : const Color(0xFFFFF3ED), shape: BoxShape.circle),
              child: Icon(
                method == 'UPI' ? Icons.phone_android_rounded : Icons.payments_outlined,
                color: status == 'confirmed' ? const Color(0xFF16A34A) : const Color(0xFFE65C00),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '₹$amount • $method',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          status.toUpperCase(),
                          style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: statusTxt),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$libName • $dateStr ${refShort.isNotEmpty ? "• Ref: $refShort" : ""}',
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                  ),
                  if (status == 'rejected') ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => _showReuploadProofBottomSheet(p),
                      child: Text(
                        'Re-upload Proof →',
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentDetailBottomSheet(Map<String, dynamic> p) {
    final status = (p['status'] ?? 'pending').toString().toUpperCase();
    final amount = p['amount'] ?? 0;
    final method = (p['method'] ?? 'cash').toString().toUpperCase();
    final refId = p['ref_id'] ?? 'N/A';
    final senderName = p['upi_sender_name'] ?? 'N/A';
    final proof = p['proof_url'] ?? '';
    final plan = p['memberships']?['plan_type'] ?? 'N/A';
    final shift = p['memberships']?['shifts']?['name'] ?? 'N/A';
    final libName = p['libraries']?['name'] ?? 'SILENCE Study Zone';
    final libAddress = p['libraries']?['address_street'] ?? '';
    final notes = p['notes'] ?? '';

    String dateStr = 'N/A';
    try {
      if (p['payment_date'] != null) {
        dateStr = DateFormat('dd MMM yyyy hh:mm a').format(DateTime.parse(p['payment_date']).toLocal());
      }
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Transaction details',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Center(
                  child: Column(
                    children: [
                      Text('RECEIPT TOTAL', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B))),
                      const SizedBox(height: 4),
                      Text(
                        '₹$amount',
                        style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: status == 'CONFIRMED' ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          status,
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: status == 'CONFIRMED' ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildDetailRow('Library', libName),
                _buildDetailRow('Payment date', dateStr),
                _buildDetailRow('Method', method),
                _buildDetailRow('Transaction Ref ID', refId),
                if (method == 'UPI') ...[
                  _buildDetailRow('Sender name', senderName),
                ],
                _buildDetailRow('Membership plan', plan == 'monthly' ? 'Monthly' : plan == '3_month' ? '3-Month' : '6-Month'),
                _buildDetailRow('Shift assigned', shift),
                if (notes.isNotEmpty) _buildDetailRow('Notes', notes),

                if (proof.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Payment Proof Image:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      // Tap to zoom image dialog
                      showDialog(
                        context: context,
                        builder: (context) => Dialog(
                          child: InteractiveViewer(
                            child: Image.network(proof, fit: BoxFit.contain),
                          ),
                        ),
                      );
                    },
                    child: Container(
                      height: 180,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(proof, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image))),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text('Close', style: GoogleFonts.inter(color: const Color(0xFF475569))),
                      ),
                    ),
                    if (status == 'CONFIRMED') ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final userProfile = await _supabase.from('users').select('full_name').eq('id', _supabase.auth.currentUser!.id).maybeSingle();
                            final memberName = userProfile != null ? (userProfile['full_name'] ?? 'Member') : 'Member';
                            await PdfExporter.exportPaymentReceipt(
                              libraryName: libName,
                              libraryAddress: libAddress,
                              payment: p,
                              memberName: memberName,
                            );
                          },
                          icon: const Icon(Icons.share_rounded, size: 16),
                          label: const Text('Receipt'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE65C00),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPaymentsBottomStickyCard(double paid, double pending, int count) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Total Paid Collections', style: GoogleFonts.inter(fontSize: 10, color: Colors.white70)),
                Text('₹${paid.toInt()}', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
          ),
          Container(height: 24, width: 1, color: Colors.white30),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Dues Outstanding', style: GoogleFonts.inter(fontSize: 10, color: Colors.white70)),
                Text('₹${pending.toInt()}', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: pending > 0 ? const Color(0xFFF59E0B) : const Color(0xFF22C55E))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payment, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No payments logged',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            Text(
              'Verify you have selected the correct library or date range above.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _loadHistoryData(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
              ),
              child: const Text('Refresh Payments'),
            ),
          ],
        ),
      ),
    );
  }

  void _showReuploadProofBottomSheet(Map<String, dynamic> p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return ReuploadProofBottomSheet(
          payment: p,
          onSuccess: () {
            Navigator.pop(context);
            _loadHistoryData();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Payment proof re-submitted successfully! ✓'), backgroundColor: Color(0xFFE65C00)),
            );
          },
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // MEMBERSHIPS SUB-TAB
  // ───────────────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filteredMemberships {
    return _memberships.where((m) {
      final status = (m['status'] ?? 'expired').toString().toLowerCase();
      if (_membershipFilter == 'Active') return status == 'active';
      if (_membershipFilter == 'Expired') return status == 'expired';
      if (_membershipFilter == 'Exited') return status == 'exited';
      if (_membershipFilter == 'Trial') return status == 'trial';
      if (_membershipFilter == 'On Hold') return status == 'hold';
      return true;
    }).toList();
  }

  Widget _buildMembershipsSubTab() {
    if (_memberships.isEmpty) {
      return _buildMembershipsEmptyState();
    }

    final filtered = _filteredMemberships;

    return RefreshIndicator(
      onRefresh: _loadHistoryData,
      color: const Color(0xFFE65C00),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildMembershipsFilterChips(),
          const SizedBox(height: 16),

          if (filtered.isEmpty) ...[
            const SizedBox(height: 32),
            Center(
              child: Text(
                'No memberships found matching this filter.',
                style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13),
              ),
            ),
          ] else ...[
            for (var m in filtered) ...[
              _buildMembershipCard(m),
              const SizedBox(height: 12),
            ],
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildMembershipsFilterChips() {
    final chips = ['All', 'Active', 'Expired', 'Exited', 'Trial', 'On Hold'];
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        itemBuilder: (context, index) {
          final chip = chips[index];
          final isSel = _membershipFilter == chip;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(chip),
              selected: isSel,
              selectedColor: const Color(0xFFE65C00),
              labelStyle: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isSel ? Colors.white : const Color(0xFF475569),
              ),
              onSelected: (val) {
                if (val) {
                  setState(() {
                    _membershipFilter = chip;
                  });
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildMembershipCard(Map<String, dynamic> m) {
    final status = (m['status'] ?? 'expired').toString().toLowerCase();
    final plan = (m['plan_type'] ?? 'monthly').toString();
    final libName = m['libraries']?['name'] ?? 'SILENCE Study Zone';
    final seatLabel = m['seats']?['seat_label'] ?? 'Pending';
    final shiftName = m['shifts']?['name'] ?? 'N/A';

    Color cardBorderColor = const Color(0xFFE2E8F0);
    String statusTitle = status.toUpperCase();

    if (status == 'active') {
      cardBorderColor = const Color(0xFF22C55E);
    } else if (status == 'trial') {
      cardBorderColor = const Color(0xFF8B5CF6);
    } else if (status == 'expired') {
      cardBorderColor = const Color(0xFFEF4444);
    } else if (status == 'exited') {
      cardBorderColor = const Color(0xFF64748B);
    } else if (status == 'hold') {
      cardBorderColor = const Color(0xFFD97706);
      statusTitle = 'ON HOLD';
    }

    return Card(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cardBorderColor, width: status == 'active' ? 2 : 1),
      ),
      child: InkWell(
        onTap: () => _showMembershipDetailBottomSheet(m),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      libName,
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cardBorderColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusTitle,
                      style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: cardBorderColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Plan: ${plan == 'monthly' ? 'Monthly' : plan == '3_month' ? '3-Month' : '6-Month'} • Seat: $seatLabel • Shift: $shiftName',
                style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
              ),
              const Divider(height: 24),
              _buildMembershipCardContent(m, status),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMembershipCardContent(Map<String, dynamic> m, String status) {
    if (status == 'active') {
      final start = DateTime.tryParse(m['start_date'] ?? '') ?? DateTime.now();
      final end = DateTime.tryParse(m['end_date'] ?? '') ?? DateTime.now();
      final now = DateTime.now();
      final elapsed = now.difference(start).inDays;
      final total = end.difference(start).inDays;
      final progress = total > 0 ? (elapsed / total).clamp(0.0, 1.0) : 0.0;
      final daysLeft = end.difference(now).inDays;

      final streak = _calculateActiveStreak();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progress: ${(progress * 100).toInt()}% ($daysLeft days left)',
                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
              ),
              if (streak > 0)
                Row(
                  children: [
                    const Icon(Icons.local_fire_department, color: Colors.orange, size: 16),
                    const SizedBox(width: 2),
                    Text(
                      '$streak Day Streak!',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFFF1F5F9),
              color: const Color(0xFF22C55E),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildCardAction('View Attendance', () => _switchToTab(0, m['library_id'])),
              const SizedBox(width: 8),
              _buildCardAction('View Payments', () => _switchToTab(1, m['library_id'])),
              const SizedBox(width: 8),
              _buildCardAction('Renew', () {
                Navigator.pushNamed(context, '/member/renewal', arguments: {
                  'libraryId': m['library_id'],
                  'initialPlan': m['plan_type'],
                  'initialShiftId': m['shift_id'],
                });
              }, isPrimary: true),
            ],
          ),
        ],
      );
    }

    if (status == 'trial') {
      final end = DateTime.tryParse(m['end_date'] ?? '') ?? DateTime.now();
      final hoursLeft = end.difference(DateTime.now()).inHours;
      final daysLeft = (hoursLeft / 24.0).ceil();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trial active for next $daysLeft day${daysLeft > 1 ? "s" : ""}',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF8B5CF6)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/member/renewal', arguments: {
                  'libraryId': m['library_id'],
                  'initialPlan': 'monthly',
                  'initialShiftId': m['shift_id'],
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: const Text('Choose Study Plan'),
            ),
          ),
        ],
      );
    }

    if (status == 'expired') {
      final end = DateTime.tryParse(m['end_date'] ?? '') ?? DateTime.now();
      final endStr = DateFormat('dd MMM yyyy').format(end);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Expired on $endStr',
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFEF4444), fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/member/renewal', arguments: {
                  'libraryId': m['library_id'],
                  'initialPlan': m['plan_type'],
                  'initialShiftId': m['shift_id'],
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: const Text('Renew Subscription Plan'),
            ),
          ),
        ],
      );
    }

    if (status == 'exited') {
      final exited = DateTime.tryParse(m['exited_at'] ?? m['end_date'] ?? '') ?? DateTime.now();
      final exitedStr = DateFormat('dd MMM yyyy').format(exited);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Exited library on $exitedStr',
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    // Navigate to Past Library details S096
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PastLibraryDetailScreen(membershipId: m['id']),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    foregroundColor: const Color(0xFF475569),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('View Full History'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => JoinFlowScreen(
                          libraryId: m['library_id'],
                          initialShiftId: m['shift_id'],
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Text('Rejoin Library'),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (status == 'hold') {
      final resume = DateTime.tryParse(m['resume_date'] ?? m['hold_until'] ?? '') ?? DateTime.now();
      final resumeStr = DateFormat('dd MMM yyyy').format(resume);
      final libPhone = m['libraries']?['emergency_phone'] ?? m['libraries']?['phone'] ?? '919999999999';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'On hold. Scheduled to resume on $resumeStr',
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFD97706), fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openWhatsApp(libPhone, 'Hello, I would like to query about resuming my seat subscription.'),
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: const Text('Contact Study Center'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFD97706)),
                foregroundColor: const Color(0xFFD97706),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildCardAction(String label, VoidCallback onTap, {bool isPrimary = false}) {
    return Expanded(
      child: isPrimary
          ? ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                elevation: 0,
              ),
              child: Text(
                label,
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF475569),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(
                label,
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
    );
  }

  void _showMembershipDetailBottomSheet(Map<String, dynamic> m) {
    final status = (m['status'] ?? 'expired').toString().toLowerCase();
    final planType = (m['plan_type'] ?? 'monthly').toString();
    final startStr = m['start_date'];
    final endStr = m['end_date'];
    final exitedStr = m['exited_at'];
    final libName = m['libraries']?['name'] ?? 'SILENCE Study Zone';
    final libAddress = m['libraries']?['address_city'] ?? '';
    final libPhone = m['libraries']?['phone'] ?? 'N/A';
    final seatLabel = m['seats']?['seat_label'] ?? 'N/A';
    final shiftName = m['shifts']?['name'] ?? 'N/A';
    final shiftStart = m['shifts']?['start_time'] ?? '';
    final shiftEnd = m['shifts']?['end_time'] ?? '';

    String dateRange = 'N/A';
    try {
      final start = DateTime.parse(startStr!).toLocal();
      final end = DateTime.parse(endStr!).toLocal();
      dateRange = '${DateFormat('dd MMM yyyy').format(start)} - ${DateFormat('dd MMM yyyy').format(end)}';
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          minChildSize: 0.6,
          expand: false,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Membership details',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                _buildDetailRow('Library Name', libName),
                _buildDetailRow('City', libAddress),
                _buildDetailRow('Contact Phone', libPhone),
                _buildDetailRow('Subscription Status', status.toUpperCase()),
                _buildDetailRow('Plan Period Type', planType == 'monthly' ? 'Monthly' : planType == '3_month' ? '3-Month' : '6-Month'),
                _buildDetailRow('Validity Period', dateRange),
                if (exitedStr != null)
                  _buildDetailRow('Exited At', exitedStr),
                _buildDetailRow('Assigned Desk', seatLabel),
                _buildDetailRow('Assigned Shift', '$shiftName ($shiftStart - $shiftEnd)'),
                
                const Divider(height: 32),
                Text('Activity Overview', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.calendar_month_outlined, color: Color(0xFFE65C00)),
                  title: const Text('View Study Sessions Logs'),
                  subtitle: const Text('Filter and check check-in/out timeline logs'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    _switchToTab(0, m['library_id']);
                  },
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.payment, color: Color(0xFFE65C00)),
                  title: const Text('View Payment Invoices'),
                  subtitle: const Text('Check invoices receipt confirmations'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    _switchToTab(1, m['library_id']);
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Close Membership Sheet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMembershipsEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.workspace_premium, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No memberships found',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            Text(
              'Join a library to activate your study space subscription plan.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                // Navigate to S010 Explore Tab (usually S010 is first tab)
                Navigator.of(context).pushNamedAndRemoveUntil('/member/home', (route) => false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
              ),
              child: const Text('Find a Study Center'),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // SKELETON LOADERS & ERRORS
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildSkeletonLoader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 64,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: 4,
              itemBuilder: (context, index) {
                return Container(
                  height: 80,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              'Failed to load study history',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error occurred.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadHistoryData,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // GROUPING IN-MEMORY SESSIONS
  // ───────────────────────────────────────────────────────────────────────────
  Map<String, List<Map<String, dynamic>>> _groupSessions(List<Map<String, dynamic>> sessions) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var s in sessions) {
      final date = s['date'] as DateTime;
      String key;
      if (_selectedDateRange == 'Today' || _selectedDateRange == 'This Week') {
        key = DateFormat('EEEE, dd MMMM yyyy').format(date);
      } else if (_selectedDateRange == 'This Month' || _selectedDateRange == 'Last Month') {
        // Calculate the week index of the month
        final weekNum = ((date.day - 1) / 7).floor() + 1;
        key = 'Week $weekNum of ${DateFormat('MMMM yyyy').format(date)}';
      } else {
        key = DateFormat('MMMM yyyy').format(date);
      }
      grouped.putIfAbsent(key, () => []).add(s);
    }
    return grouped;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // PHASE 3 - EXPORT OPTIONS SHEET
  // ───────────────────────────────────────────────────────────────────────────
  void _showExportOptionsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return ExportOptionsBottomSheet(
          libraryId: _selectedLibraryId,
          dateRange: _getDateRange(),
          dateRangeLabel: _selectedDateRange,
          payments: _filteredPayments,
          attendance: _filteredSessions,
          memberships: _filteredMemberships,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RE-UPLOAD PROOF BOTTOM SHEET WIDGET (STATEFUL)
// ─────────────────────────────────────────────────────────────────────
class ReuploadProofBottomSheet extends StatefulWidget {
  final Map<String, dynamic> payment;
  final VoidCallback onSuccess;

  const ReuploadProofBottomSheet({
    super.key,
    required this.payment,
    required this.onSuccess,
  });

  @override
  State<ReuploadProofBottomSheet> createState() => _ReuploadProofBottomSheetState();
}

class _ReuploadProofBottomSheetState extends State<ReuploadProofBottomSheet> {
  final _supabase = Supabase.instance.client;
  final _refIdCtrl = TextEditingController();
  final _senderCtrl = TextEditingController();
  File? _imageFile;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _refIdCtrl.text = widget.payment['ref_id'] ?? '';
    _senderCtrl.text = widget.payment['upi_sender_name'] ?? '';
  }

  @override
  void dispose() {
    _refIdCtrl.dispose();
    _senderCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery);
    if (img == null) return;

    setState(() {
      _imageFile = File(img.path);
    });
  }

  Future<void> _submit() async {
    final ref = _refIdCtrl.text.trim();
    final sender = _senderCtrl.text.trim();

    if (ref.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction Ref ID is required')),
      );
      return;
    }

    if (sender.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('UPI Sender Name is required')),
      );
      return;
    }

    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Screenshot proof is required')),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Session missing');

      final fileName = 'proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = 'payment_proofs/${user.id}/$fileName';

      // Compress
      final bytes = await ImageOptimizer.compressImage(_imageFile!.path);

      // Upload binary
      await _supabase.storage.from('silence_assets').uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              cacheControl: '3600',
              upsert: true,
            ),
          );

      final proofUrl = _supabase.storage.from('silence_assets').getPublicUrl(path);

      // Update payment status to pending and re-save transaction data
      await _supabase.from('payments').update({
        'status': 'pending',
        'ref_id': ref,
        'upi_sender_name': sender,
        'proof_url': proofUrl,
        'created_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.payment['id']);

      widget.onSuccess();

    } catch (e) {
      debugPrint('Re-upload exception: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Re-submission failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 24, left: 24, right: 24
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Re-upload UPI Payment Proof',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _refIdCtrl,
            decoration: const InputDecoration(labelText: 'Transaction Reference ID (Ref ID) *'),
            style: GoogleFonts.inter(fontSize: 13.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _senderCtrl,
            decoration: const InputDecoration(labelText: 'UPI Sender Account Name *'),
            style: GoogleFonts.inter(fontSize: 13.5),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFFF8FAFC),
              ),
              alignment: Alignment.center,
              child: _imageFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(_imageFile!, fit: BoxFit.contain),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_upload_outlined, size: 32, color: Colors.grey[400]),
                        const SizedBox(height: 6),
                        Text(
                          'Tap to select UPI payment screenshot',
                          style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey[600]),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isUploading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65C00),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _isUploading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Submit Proof Details', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXPORT OPTIONS BOTTOM SHEET (PHASE 3)
// ─────────────────────────────────────────────────────────────────────
class ExportOptionsBottomSheet extends StatefulWidget {
  final String libraryId;
  final DateTimeRange? dateRange;
  final String dateRangeLabel;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> attendance;
  final List<Map<String, dynamic>> memberships;

  const ExportOptionsBottomSheet({
    super.key,
    required this.libraryId,
    required this.dateRange,
    required this.dateRangeLabel,
    required this.payments,
    required this.attendance,
    required this.memberships,
  });

  @override
  State<ExportOptionsBottomSheet> createState() => _ExportOptionsBottomSheetState();
}

class _ExportOptionsBottomSheetState extends State<ExportOptionsBottomSheet> {
  final _supabase = Supabase.instance.client;
  bool _exportAttendance = true;
  bool _exportPayments = true;
  bool _exportMemberships = true;
  bool _isExporting = false;

  Future<void> _triggerExport(String format) async {
    setState(() => _isExporting = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Session missing');

      // Fetch user profile to get nickname
      final profile = await _supabase.from('users').select('nickname, full_name').eq('id', user.id).maybeSingle();
      final nickname = profile != null ? (profile['nickname'] ?? profile['full_name'] ?? 'User') : 'User';
      final cleanNickname = nickname.toString().replaceAll(' ', '_');

      // Fetch active library details for header info
      String libName = 'All Libraries';
      String libAddress = '';
      if (widget.libraryId != 'All') {
        final lib = await _supabase.from('libraries').select('name, address_city, address_state').eq('id', widget.libraryId).maybeSingle();
        if (lib != null) {
          libName = lib['name'] ?? 'Library';
          libAddress = '${lib['address_city'] ?? ""}, ${lib['address_state'] ?? ""}';
        }
      }

      final dateRangeStr = widget.dateRangeLabel;
      final filePrefix = 'Silence_${cleanNickname}_${dateRangeStr.replaceAll(' ', '_')}';

      if (format == 'CSV') {
        final buffer = StringBuffer();
        buffer.writeln('SILENCE Study Record Export');
        buffer.writeln('Member:, $nickname');
        buffer.writeln('Library Group:, $libName');
        buffer.writeln('Period:, $dateRangeStr');
        buffer.writeln('Export Date:, ${DateFormat('dd MMM yyyy hh:mm a').format(DateTime.now())}');
        buffer.writeln();

        if (_exportAttendance && widget.attendance.isNotEmpty) {
          buffer.writeln('=== ATTENDANCE RECORDS ===');
          buffer.writeln('Date,Type,Details,Timeline');
          for (var s in widget.attendance) {
            final dateStr = DateFormat('yyyy-MM-dd').format(s['date']);
            final type = s['type'] == 'present' ? 'Present (${s['session_type'].toString().toUpperCase()})' : s['type'].toString().toUpperCase();
            String details = '';
            String timeline = '';

            if (s['type'] == 'present') {
              final data = s['data'] as Map<String, dynamic>;
              final lib = data['libraries']?['name'] ?? 'SILENCE';
              final seat = data['seats']?['seat_label'] ?? 'N/A';
              final shift = data['shifts']?['name'] ?? 'N/A';
              details = '$lib (Seat $seat, Shift $shift)';
              
              final ci = DateTime.parse(data['check_in_time']).toLocal();
              final coStr = data['check_out_time'];
              final co = coStr != null ? DateFormat('hh:mm a').format(DateTime.parse(coStr).toLocal()) : 'Ongoing';
              timeline = '${DateFormat('hh:mm a').format(ci)} - $co';
            } else if (s['type'] == 'closed') {
              details = s['reason'] ?? 'Closed';
            }
            buffer.writeln('"$dateStr","$type","$details","$timeline"');
          }
          buffer.writeln();
        }

        if (_exportPayments && widget.payments.isNotEmpty) {
          buffer.writeln('=== PAYMENTS INVOICES ===');
          buffer.writeln('Date,Amount,Method,Status,Ref ID,Library');
          for (var p in widget.payments) {
            final dateStr = p['payment_date'] != null ? DateFormat('yyyy-MM-dd').format(DateTime.parse(p['payment_date'])) : 'N/A';
            buffer.writeln('"$dateStr","₹${p['amount']}","${(p['method'] ?? 'cash').toString().toUpperCase()}","${(p['status'] ?? 'pending').toString().toUpperCase()}","${p['ref_id'] ?? ''}","${p['libraries']?['name'] ?? ''}"');
          }
          buffer.writeln();
        }

        if (_exportMemberships && widget.memberships.isNotEmpty) {
          buffer.writeln('=== MEMBERSHIPS SUMMARY ===');
          buffer.writeln('Library,Plan,Validity,Status,Seat,Shift');
          for (var m in widget.memberships) {
            buffer.writeln('"${m['libraries']?['name'] ?? ''}","${m['plan_type'] ?? ''}","${m['start_date']} to ${m['end_date']}","${(m['status'] ?? '').toString().toUpperCase()}","${m['seats']?['seat_label'] ?? 'Pending'}","${m['shifts']?['name'] ?? 'N/A'}"');
          }
        }

        final tempDir = Directory.systemTemp;
        final file = File('${tempDir.path}/$filePrefix.csv');
        await file.writeAsString(buffer.toString());
        await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')], subject: 'Silence Study Record Export');

      } else if (format == 'PDF') {
        // PDF Generation using PdfExporter
        if (_exportAttendance) {
          // Flatten attendance map for pdf generator
          final List<Map<String, dynamic>> pdfAttendanceLogs = [];
          for (var s in widget.attendance) {
            if (s['type'] != 'present') continue;
            final data = s['data'] as Map<String, dynamic>;
            pdfAttendanceLogs.add({
              'member_name': nickname,
              'check_in_time': data['check_in_time'],
              'check_out_time': data['check_out_time'],
              'shift_name': data['shifts']?['name'] ?? 'N/A',
              'seat_label': data['seats']?['seat_label'] ?? 'N/A',
            });
          }
          await PdfExporter.exportAttendance(
            libraryName: libName,
            libraryAddress: libAddress,
            dateRange: dateRangeStr,
            logs: pdfAttendanceLogs,
          );
        } else if (_exportPayments) {
          final List<Map<String, dynamic>> pdfPayments = [];
          for (var p in widget.payments) {
            pdfPayments.add({
              'id': p['id'],
              'member_name': nickname,
              'payment_date': p['payment_date'],
              'amount': p['amount'],
              'method': p['method'],
              'status': p['status'],
            });
          }
          await PdfExporter.exportPayments(
            libraryName: libName,
            libraryAddress: libAddress,
            dateRange: dateRangeStr,
            payments: pdfPayments,
          );
        } else if (_exportMemberships) {
          final List<Map<String, dynamic>> pdfMembers = [];
          for (var m in widget.memberships) {
            pdfMembers.add({
              'full_name': nickname,
              'email': user?.email ?? 'N/A',
              'phone': m['phone'] ?? 'N/A',
              'created_at': m['created_at'],
              'expiry_date': m['end_date'],
              'status': m['status'],
            });
          }
          await PdfExporter.exportMembers(
            libraryName: libName,
            libraryAddress: libAddress,
            members: pdfMembers,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report generated & shared successfully ✓'), backgroundColor: Color(0xFFE65C00)),
        );
      }

    } catch (e) {
      debugPrint('Export failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate export file: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Export History Reports',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Selected range: ${widget.dateRangeLabel}',
            style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: Text('Include Attendance Ledger', style: GoogleFonts.inter(fontSize: 13.5)),
            value: _exportAttendance,
            activeColor: const Color(0xFFE65C00),
            onChanged: (val) => setState(() => _exportAttendance = val ?? false),
          ),
          CheckboxListTile(
            title: Text('Include Payments Ledger', style: GoogleFonts.inter(fontSize: 13.5)),
            value: _exportPayments,
            activeColor: const Color(0xFFE65C00),
            onChanged: (val) => setState(() => _exportPayments = val ?? false),
          ),
          CheckboxListTile(
            title: Text('Include Memberships Summary', style: GoogleFonts.inter(fontSize: 13.5)),
            value: _exportMemberships,
            activeColor: const Color(0xFFE65C00),
            onChanged: (val) => setState(() => _exportMemberships = val ?? false),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isExporting ? null : () => _triggerExport('CSV'),
                  icon: const Icon(Icons.table_chart_outlined, size: 16),
                  label: const Text('Export CSV'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF475569),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isExporting ? null : () => _triggerExport('PDF'),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                  label: const Text('Export PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
