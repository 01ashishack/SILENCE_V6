import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/member_analytics_service.dart';
import '../utils/csv_exporter.dart';
import '../utils/time_utils.dart';
import '../utils/attendance_format.dart';
import '../utils/error_messages.dart';
import '../widgets/states/shimmer_box.dart';
import '../widgets/states/error_state.dart';
import '../theme/app_palette.dart';

// Import removed to avoid unused library dependency

class MemberAnalyticsTab extends StatefulWidget {
  final Map<String, dynamic>? userProfile;
  final String? activeLibraryId;
  final List<dynamic> memberLibraries; // List of memberships the member is part of
  final void Function(int)? onSwitchTab; // Callback to switch bottom nav tab

  const MemberAnalyticsTab({
    super.key,
    required this.userProfile,
    required this.activeLibraryId,
    required this.memberLibraries,
    this.onSwitchTab,
  });

  @override
  State<MemberAnalyticsTab> createState() => _MemberAnalyticsTabState();
}

class _MemberAnalyticsTabState extends State<MemberAnalyticsTab> with AutomaticKeepAliveClientMixin {
  bool _isLoading = true;
  String? _errorMessage; // set when the first load fails (shows ErrorState instead of fake zeros)

  // Global period filters
  String _dateFilter = 'this_month'; // 'today', 'this_week', 'this_month', 'all_time'
  DateTimeRange _dateRange = _getMonthRange();

  String? _selectedLibraryId; // 'all' or specific library UUID
  String? _streakLibraryId;   // specific library UUID for the streak card

  // Current Period Stats
  int _daysPresent = 0;
  int _daysAbsent = 0;
  double _totalHours = 0.0;
  double _attendanceRate = 0.0;

  // Previous Period Stats (for trends)
  int _prevDaysPresent = 0;
  int _prevDaysAbsent = 0;
  double _prevTotalHours = 0.0;
  double _prevAttendanceRate = 0.0;
  String _trendLabel = '';

  // Streak Card Data
  int _currentStreak = 0;
  int _bestStreak = 0;
  List<Map<String, dynamic>> _last7Days = [];

  // Leaderboard Data (independent filters)
  List<Map<String, dynamic>> _leaderboardList = [];
  Map<String, dynamic>? _currentUserLeaderboardRow;
  int? _currentUserLeaderboardRank;
  double _leaderboardGapToTop5 = 0.0;
  int _leaderboardTotalMembers = 0;
  String? _leaderboardLibraryId; // per-library selector
  String _leaderboardPeriod = 'this_week'; // 'this_week', 'this_month', 'all_time'

  // Daily Study Hours Chart Data
  List<Map<String, dynamic>> _chartData = [];
  String? _bestDayText;
  String? _weakestDayText;

  // Heatmap Data
  Map<String, dynamic> _heatmapData = {};
  DateTime _heatmapMonth = DateTime.now();

  // Keys for scrolling
  final GlobalKey _calendarKey = GlobalKey();
  final GlobalKey _chartKey = GlobalKey();

  // Badge Data
  List<Map<String, dynamic>> _earnedBadges = [];
  bool _isExporting = false;

  // Realtime & Debouncer
  RealtimeChannel? _realtimeChannel;
  Timer? _debounceTimer;

  static DateTimeRange _getMonthRange() {
    final now = istNow();
    return DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
  }

  List<Map<String, dynamic>> _getUniqueLibraries() {
    final uniqueLibraries = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    for (var m in widget.memberLibraries) {
      final lib = m['libraries'] as Map<String, dynamic>?;
      final libId = m['library_id'] as String? ?? lib?['id'] as String?;
      if (libId != null && !seenIds.contains(libId)) {
        seenIds.add(libId);
        uniqueLibraries.add({
          'id': libId,
          'name': lib?['name'] ?? 'Library',
        });
      }
    }
    return uniqueLibraries;
  }

  DateTimeRange _getLeaderboardDateRange() {
    final now = istNow();
    if (_leaderboardPeriod == 'this_week') {
      final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
      return DateTimeRange(start: start, end: end);
    } else if (_leaderboardPeriod == 'this_month') {
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
      return DateTimeRange(start: start, end: end);
    } else {
      return DateTimeRange(start: DateTime(2020, 1, 1), end: DateTime(now.year, now.month, now.day, 23, 59, 59));
    }
  }

  @override
  void initState() {
    super.initState();
    final uniqueLibs = _getUniqueLibraries();
    
    // Initialize global library selector
    if (uniqueLibs.length >= 2) {
      _selectedLibraryId = 'all';
    } else if (uniqueLibs.isNotEmpty) {
      _selectedLibraryId = uniqueLibs.first['id'];
    } else {
      _selectedLibraryId = widget.activeLibraryId;
    }

    // Initialize streak library selector (always per-library)
    if (uniqueLibs.isNotEmpty) {
      _streakLibraryId = uniqueLibs.first['id'];
    } else {
      _streakLibraryId = widget.activeLibraryId;
    }

    // Initialize leaderboard library selector
    _leaderboardLibraryId = _streakLibraryId;

    _loadAllData();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtimeSubscription() {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    _realtimeChannel = Supabase.instance.client
        .channel('public:attendance:member_id=eq.${currentUser.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'member_id',
            value: currentUser.id,
          ),
          callback: (payload) {
            debugPrint('Real-time update in attendance logs detected!');
            _onRealtimeEvent();
          },
        );
    _realtimeChannel!.subscribe();
  }

  void _onRealtimeEvent() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _loadRealtimeData();
    });
  }

  Future<void> _loadRealtimeData() async {
    if (widget.userProfile == null) return;
    final String memberId = widget.userProfile!['id'];
    final uniqueLibs = _getUniqueLibraries();
    final List<String> memberLibraryIds = uniqueLibs.map((e) => e['id'] as String).toList();

    try {
      // 1. Reload Streak only
      if (_streakLibraryId != null) {
        final streak = await MemberAnalyticsService.instance.fetchStreak(memberId, _streakLibraryId!);
        if (mounted) {
          setState(() {
            _currentStreak = streak['current'] ?? 0;
            _bestStreak = streak['best'] ?? 0;
            _last7Days = streak['last7Days'] ?? [];
          });
        }
      }

      // 2. Reload Summary Stats
      final summary = await MemberAnalyticsService.instance.fetchAnalyticsSummary(
        memberId,
        _selectedLibraryId ?? 'all',
        _dateRange.start,
        _dateRange.end,
        dateFilter: _dateFilter,
        memberLibraryIds: _selectedLibraryId == 'all' ? memberLibraryIds : null,
      );

      if (mounted) {
        setState(() {
          _daysPresent = summary['daysPresent'] ?? 0;
          _daysAbsent = summary['daysAbsent'] ?? 0;
          _totalHours = (summary['totalHours'] as num?)?.toDouble() ?? 0.0;
          _attendanceRate = (summary['attendanceRate'] as num?)?.toDouble() ?? 0.0;
          
          _prevDaysPresent = summary['prevDaysPresent'] ?? 0;
          _prevDaysAbsent = summary['prevDaysAbsent'] ?? 0;
          _prevTotalHours = (summary['prevTotalHours'] as num?)?.toDouble() ?? 0.0;
          _prevAttendanceRate = (summary['prevAttendanceRate'] as num?)?.toDouble() ?? 0.0;
          _trendLabel = summary['trendLabel'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error loading real-time analytics data: $e');
    }
  }

  void _setDateFilter(String filter) {
    final now = istNow();
    DateTime start;
    DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    if (filter == 'today') {
      start = DateTime(now.year, now.month, now.day);
    } else if (filter == 'this_week') {
      start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    } else if (filter == 'this_month') {
      start = DateTime(now.year, now.month, 1);
    } else {
      start = DateTime(2020, 1, 1);
    }

    setState(() {
      _dateFilter = filter;
      _dateRange = DateTimeRange(start: start, end: end);
    });
    _loadAllData();
  }

  bool _hasLoadedOnce = false;
  String? _lastBadgeSyncLib;

  Future<void> _loadAllData() async {
    if (widget.userProfile == null) {
      setState(() => _isLoading = false);
      return;
    }

    // Stale-while-revalidate: only show the full shimmer on the first load;
    // filter/library changes and pull-to-refresh keep the current cards visible
    // and refresh quietly instead of blanking the screen.
    if (!_hasLoadedOnce) {
      setState(() => _isLoading = true);
    }
    _errorMessage = null;

    final String memberId = widget.userProfile!['id'];
    final uniqueLibs = _getUniqueLibraries();
    final List<String> memberLibraryIds = uniqueLibs.map((e) => e['id'] as String).toList();

    try {
      // 1. Fetch Summary Stats
      final summary = await MemberAnalyticsService.instance.fetchAnalyticsSummary(
        memberId,
        _selectedLibraryId ?? 'all',
        _dateRange.start,
        _dateRange.end,
        dateFilter: _dateFilter,
        memberLibraryIds: _selectedLibraryId == 'all' ? memberLibraryIds : null,
      );

      _daysPresent = summary['daysPresent'] ?? 0;
      _daysAbsent = summary['daysAbsent'] ?? 0;
      _totalHours = (summary['totalHours'] as num?)?.toDouble() ?? 0.0;
      _attendanceRate = (summary['attendanceRate'] as num?)?.toDouble() ?? 0.0;

      _prevDaysPresent = summary['prevDaysPresent'] ?? 0;
      _prevDaysAbsent = summary['prevDaysAbsent'] ?? 0;
      _prevTotalHours = (summary['prevTotalHours'] as num?)?.toDouble() ?? 0.0;
      _prevAttendanceRate = (summary['prevAttendanceRate'] as num?)?.toDouble() ?? 0.0;
      _trendLabel = summary['trendLabel'] ?? '';

      // 2. Fetch Streak Card Data (always per-library)
      if (_streakLibraryId != null) {
        final streak = await MemberAnalyticsService.instance.fetchStreak(memberId, _streakLibraryId!);
        _currentStreak = streak['current'] ?? 0;
        _bestStreak = streak['best'] ?? 0;
        _last7Days = streak['last7Days'] ?? [];
      }

      // 3. Fetch Leaderboard Data (independent filters)
      await _loadLeaderboardDataOnlyInternal(memberId);

      // 4. Fetch Daily Study Hours (using selected library & period)
      final chartStats = await MemberAnalyticsService.instance.fetchDailyStudyHours(
        memberId: memberId,
        libraryId: _selectedLibraryId ?? 'all',
        startDate: _dateRange.start,
        endDate: _dateRange.end,
        dateFilter: _dateFilter,
        memberLibraryIds: _selectedLibraryId == 'all' ? memberLibraryIds : null,
      );
      _chartData = List<Map<String, dynamic>>.from(chartStats['chartData'] ?? []);
      _bestDayText = chartStats['bestDayText'];
      _weakestDayText = chartStats['weakestDayText'];

      // 5. Fetch Heatmap Data (using selected library & period)
      await _loadHeatmapDataOnlyInternal(memberId);

    } catch (e) {
      debugPrint('Error loading member analytics data: $e');
      // Don't show fake zeros on a failed FIRST load — surface a real error so
      // the member knows it's a fetch problem, not "no activity". A refresh
      // failure with data already on screen keeps the (stale) data instead.
      if (!_hasLoadedOnce) _errorMessage = friendlyError(e);
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _hasLoadedOnce = true;
      });
    }

    // Badge sync is an N+1-heavy job (full-history scans + nested loops). Run it
    // OFF the critical path so it never blocks first paint, and only once per
    // streak-library (not on every filter change / pull-to-refresh).
    _maybeSyncBadges(memberId);
  }

  Future<void> _maybeSyncBadges(String memberId) async {
    final lib = _streakLibraryId;
    if (lib == null) return;
    // Already synced for this library this session — skip the heavy job.
    if (lib == _lastBadgeSyncLib && _earnedBadges.isNotEmpty) return;
    try {
      final badges =
          await MemberAnalyticsService.instance.syncAndFetchBadges(memberId, lib);
      _lastBadgeSyncLib = lib;
      if (mounted) setState(() => _earnedBadges = badges);
    } catch (e) {
      debugPrint('Error syncing badges: $e');
    }
  }

  Future<void> _loadLeaderboardDataOnlyInternal(String memberId) async {
    if (_leaderboardLibraryId == null) return;
    final lbRange = _getLeaderboardDateRange();
    final lbDetails = await MemberAnalyticsService.instance.fetchLeaderboardDetails(
      _leaderboardLibraryId!,
      memberId,
      lbRange.start,
      lbRange.end,
    );
    _leaderboardList = List<Map<String, dynamic>>.from(lbDetails['leaderboard'] ?? []);
    _currentUserLeaderboardRow = lbDetails['currentUserRow'];
    _currentUserLeaderboardRank = lbDetails['currentUserRank'];
    _leaderboardGapToTop5 = lbDetails['gapToTop5'] ?? 0.0;
    _leaderboardTotalMembers = lbDetails['totalMembersCount'] ?? 0;
  }

  Future<void> _loadLeaderboardDataOnly() async {
    if (widget.userProfile == null) return;
    await _loadLeaderboardDataOnlyInternal(widget.userProfile!['id']);
    if (mounted) setState(() {});
  }

  Future<void> _loadHeatmapDataOnlyInternal(String memberId) async {
    final uniqueLibs = _getUniqueLibraries();
    final List<String> memberLibraryIds = uniqueLibs.map((e) => e['id'] as String).toList();
    
    DateTime start;
    DateTime end;

    if (_dateFilter == 'all_time') {
      end = istNow();
      start = end.subtract(const Duration(days: 364));
    } else {
      start = DateTime(_heatmapMonth.year, _heatmapMonth.month, 1);
      end = DateTime(_heatmapMonth.year, _heatmapMonth.month + 1, 0, 23, 59, 59);
    }

    final heatmapStats = await MemberAnalyticsService.instance.fetchActivityHeatmap(
      memberId: memberId,
      libraryId: _selectedLibraryId ?? 'all',
      startDate: start,
      endDate: end,
      memberLibraryIds: _selectedLibraryId == 'all' ? memberLibraryIds : null,
    );
    _heatmapData = Map<String, dynamic>.from(heatmapStats);
  }

  Future<void> _loadHeatmapDataOnly() async {
    if (widget.userProfile == null) return;
    await _loadHeatmapDataOnlyInternal(widget.userProfile!['id']);
    if (mounted) setState(() {});
  }

  Future<void> _loadStreakDataOnly() async {
    if (widget.userProfile == null || _streakLibraryId == null) return;
    final String memberId = widget.userProfile!['id'];

    try {
      final streak = await MemberAnalyticsService.instance.fetchStreak(memberId, _streakLibraryId!);
      if (mounted) {
        setState(() {
          _currentStreak = streak['current'] ?? 0;
          _bestStreak = streak['best'] ?? 0;
          _last7Days = streak['last7Days'] ?? [];
        });
      }
    } catch (e) {
      debugPrint('Error loading streak data: $e');
    }
  }

  List<Map<String, dynamic>> _getDisplayChartData() {
    if (_chartData.isNotEmpty) return _chartData;

    final List<Map<String, dynamic>> data = [];
    final now = istNow();
    if (_dateFilter == 'today') {
      data.add({
        'label': DateFormat('EEEE').format(now),
        'dateStr': DateFormat('yyyy-MM-dd').format(now),
        'hours_by_library': <String, double>{},
      });
    } else if (_dateFilter == 'this_week') {
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final List<String> weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      for (int i = 0; i < 7; i++) {
        final date = monday.add(Duration(days: i));
        data.add({
          'label': weekdays[i],
          'dateStr': DateFormat('yyyy-MM-dd').format(date),
          'hours_by_library': <String, double>{},
        });
      }
    } else if (_dateFilter == 'this_month') {
      final start = DateTime(now.year, now.month, 1);
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      for (int i = 0; i < daysInMonth; i++) {
        final date = start.add(Duration(days: i));
        data.add({
          'label': '${date.day}',
          'dateStr': DateFormat('yyyy-MM-dd').format(date),
          'hours_by_library': <String, double>{},
        });
      }
    } else {
      for (int i = 5; i >= 0; i--) {
        final date = DateTime(now.year, now.month - i, 1);
        data.add({
          'label': DateFormat('MMM').format(date),
          'dateStr': DateFormat('yyyy-MM').format(date),
          'hours_by_library': <String, double>{},
        });
      }
    }
    return data;
  }

  void _scrollToSection(GlobalKey key) {
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  bool _isYesterdayClosed() {
    final yesterdayStr = DateFormat('yyyy-MM-dd').format(istNow().subtract(const Duration(days: 1)));
    for (var day in _last7Days) {
      if (day['dateStr'] == yesterdayStr && day['status'] == 'closed') {
        return true;
      }
    }
    return false;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // No libraries joined yet: show the REAL analytics layout with empty/zero
    // values (cards + graphs) instead of an explore CTA — so the member sees
    // exactly what their analytics will look like, just at zero. (Exploring /
    // joining a library now lives on the Home tab.)
    if (widget.memberLibraries.isEmpty) {
      return Scaffold(
        backgroundColor: context.palette.scaffold,
        body: Column(
          children: [
            _buildHeaderAndFilters(),
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 100, top: 16),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFD1B3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.insights_rounded, size: 18, color: Color(0xFFB45309)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Join a library and check in — your streak, hours and '
                                'attendance will fill in here.',
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF92400E), height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildStreakCard(),
                    const SizedBox(height: 16),
                    _buildSummaryGrid(),
                    const SizedBox(height: 24),
                    _buildBarChart(),
                    const SizedBox(height: 24),
                    _buildHeatmap(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.palette.scaffold,
      body: Column(
        children: [
          _buildHeaderAndFilters(),
          Expanded(
            child: _errorMessage != null
                ? ErrorState(error: _errorMessage, onRetry: _loadAllData)
                : _isLoading
                    ? _buildShimmerLoading()
                    : RefreshIndicator(
                    color: const Color(0xFFE65C00),
                    onRefresh: _loadAllData,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 100, top: 16),
                      child: Column(
                        children: [
                          _buildStreakCard(),
                          const SizedBox(height: 16),
                          _buildSummaryGrid(),
                          const SizedBox(height: 24),
                          _buildBadgesSection(),
                          const SizedBox(height: 24),
                          _buildLeaderboardCard(),
                          const SizedBox(height: 24),
                          _buildBarChart(),
                          const SizedBox(height: 24),
                          _buildHeatmap(),
                          const SizedBox(height: 24),
                          _buildExportButton(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // 1. Header & Filters
  // ---------------------------------------------------------
  Widget _buildHeaderAndFilters() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE65C00), Color(0xFFC44E00)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        bottom: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Analytics',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildPeriodSelectorRow(),
          _buildLibrarySelectorRow(),
        ],
      ),
    );
  }

  Widget _buildPeriodSelectorRow() {
    final filters = [
      {'label': 'Today', 'value': 'today'},
      {'label': 'This Week', 'value': 'this_week'},
      {'label': 'This Month ●', 'value': 'this_month'},
      {'label': 'All Time', 'value': 'all_time'},
    ];

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (c, i) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final f = filters[index];
          final isSelected = _dateFilter == f['value'];
          return GestureDetector(
            onTap: () => _setDateFilter(f['value']!),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  f['label']!,
                  style: GoogleFonts.inter(
                    color: isSelected ? const Color(0xFFE65C00) : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLibrarySelectorRow() {
    final uniqueLibraries = _getUniqueLibraries();
    if (uniqueLibraries.length < 2) return const SizedBox.shrink();

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: uniqueLibraries.length + 1,
        separatorBuilder: (c, i) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final String id = isAll ? 'all' : uniqueLibraries[index - 1]['id'];
          final String name = isAll ? 'All Libraries' : uniqueLibraries[index - 1]['name'];
          final isSelected = _selectedLibraryId == id;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedLibraryId = id;
              });
              _loadAllData();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  name,
                  style: GoogleFonts.inter(
                    color: isSelected ? const Color(0xFFE65C00) : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------
  // 2. Streak Card
  // ---------------------------------------------------------
  Widget _buildStreakCard() {
    final uniqueLibraries = _getUniqueLibraries();
    final String selectedStreakLibName = uniqueLibraries.firstWhere(
      (lib) => lib['id'] == _streakLibraryId,
      orElse: () => {'id': '', 'name': 'SILENCE Study Zone'},
    )['name'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF8C00), Color(0xFFE65C00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE65C00).withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox.shrink(),
                PopupMenuButton<String>(
                  onSelected: (val) {
                    setState(() {
                      _streakLibraryId = val;
                    });
                    _loadStreakDataOnly();
                  },
                  offset: const Offset(0, 30),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selectedStreakLibName,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 14),
                      ],
                    ),
                  ),
                  itemBuilder: (context) {
                    return uniqueLibraries.map((lib) {
                      return PopupMenuItem<String>(
                        value: lib['id'],
                        child: Text(
                          lib['name'],
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      );
                    }).toList();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('🔥', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 8),
            Text(
              '$_currentStreak',
              style: GoogleFonts.outfit(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.0,
              ),
            ),
            Text(
              'Day Streak',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Best ever: $_bestStreak days',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
            const Divider(color: Colors.white24, height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _last7Days.map((day) {
                final status = day['status'] as String;
                final label = day['label'] as String;
                final dateStr = day['dateStr'] as String;

                Widget circleWidget;
                if (status == 'present') {
                  circleWidget = Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0xFF22C55E),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.check, color: Colors.white, size: 18),
                    ),
                  );
                } else if (status == 'closed') {
                  circleWidget = Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.28),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
                    ),
                    child: const Center(
                      child: Text('❄', style: TextStyle(fontSize: 16, color: Colors.white)),
                    ),
                  );
                } else if (status == 'today_partial') {
                  // Today, not scanned yet: solid white ring with a filled centre
                  // so "today" reads clearly against the orange card.
                  circleWidget = Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                    child: Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                } else if (status == 'future') {
                  // Upcoming day: subtle but still legible dashed-feel ring.
                  circleWidget = Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1.5),
                    ),
                  );
                } else {
                  // Missed / absent past day: clearly-bordered hollow ring with a
                  // faint fill so it's distinct from "future" and visible on orange.
                  circleWidget = Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
                    ),
                    child: Center(
                      child: Container(
                        width: 10,
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  );
                }

                return GestureDetector(
                  onTap: () {
                    if (status != 'future') {
                      _showDayAttendancePopup(dateStr, status);
                    }
                  },
                  child: Column(
                    children: [
                      circleWidget,
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Incomplete sessions protect streak but count 0 hours.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.8),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
            if (_isYesterdayClosed()) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.ac_unit, color: Colors.white, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    'Yesterday was closed: streak protected!',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // 3. Summary Grid (2x2)
  // ---------------------------------------------------------
  Widget _buildSummaryGrid() {
    final double daysPresentDiff = (_daysPresent - _prevDaysPresent).toDouble();
    final double daysAbsentDiff = (_daysAbsent - _prevDaysAbsent).toDouble();
    final double totalHoursDiff = _totalHours - _prevTotalHours;
    final double rateDiff = _attendanceRate - _prevAttendanceRate;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        // Taller cells than before (1.55 overflowed by ~9-11px once the value
        // font grew to 30 and Total Hours added an avg/day subtitle).
        childAspectRatio: 1.28,
        children: [
          _buildStatCard(
            title: 'Days Present',
            value: '$_daysPresent',
            valueColor: const Color(0xFFE65C00),
            trendWidget: _buildTrendIndicator(daysPresentDiff),
            onTap: () => _scrollToSection(_calendarKey),
          ),
          _buildStatCard(
            title: 'Days Absent',
            value: '$_daysAbsent',
            valueColor: context.palette.textPrimary,
            trendWidget: _buildTrendIndicator(daysAbsentDiff, isLowerBetter: true),
            onTap: () => _scrollToSection(_calendarKey),
          ),
          _buildStatCard(
            title: 'Total Hours',
            value: '${_totalHours.toStringAsFixed(1)}h',
            valueColor: context.palette.textPrimary,
            subValue: '${(_totalHours / (_daysPresent > 0 ? _daysPresent : 1)).toStringAsFixed(1)}h avg/day',
            trendWidget: _buildTrendIndicator(totalHoursDiff, unit: 'h'),
            onTap: () => _scrollToSection(_chartKey),
          ),
          _buildStatCard(
            title: 'Attendance Rate',
            value: '${_attendanceRate.toStringAsFixed(0)}%',
            valueColor: _getAttendanceColor(_attendanceRate),
            trendWidget: _buildTrendIndicator(rateDiff, unit: '%'),
            rightWidget: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                value: _attendanceRate / 100.0,
                strokeWidth: 3.5,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(_getAttendanceColor(_attendanceRate)),
              ),
            ),
            onTap: () => _scrollToSection(_chartKey),
          ),
        ],
      ),
    );
  }

  Color _getAttendanceColor(double rate) {
    if (rate >= 80.0) return const Color(0xFF22C55E);
    if (rate >= 50.0) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required Color valueColor,
    required Widget trendWidget,
    String? subValue,
    Widget? rightWidget,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.inter(
                      color: context.palette.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ?rightWidget,
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    color: valueColor,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subValue != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subValue,
                    style: GoogleFonts.inter(
                      color: const Color(0xFF94A3B8),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showTrendComparisonSheet,
              child: trendWidget,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendIndicator(double diff, {bool isLowerBetter = false, String unit = ''}) {
    if (_dateFilter == 'all_time') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.trending_flat, color: Colors.grey, size: 12),
          const SizedBox(width: 2),
          Text(
            'Flat',
            style: GoogleFonts.inter(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      );
    }

    if (diff == 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.trending_flat, color: Colors.grey, size: 12),
          const SizedBox(width: 2),
          Text(
            'Same',
            style: GoogleFonts.inter(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      );
    }

    final bool isGood = isLowerBetter ? diff < 0 : diff > 0;
    final color = isGood ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final icon = diff > 0 ? Icons.trending_up : Icons.trending_down;
    final sign = diff > 0 ? '+' : '';
    final valStr = diff.abs().toStringAsFixed(diff.truncateToDouble() == diff ? 0 : 1);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 2),
        Text(
          '$sign$valStr$unit vs last',
          style: GoogleFonts.inter(color: color, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  // 4. Comparison Bottom Sheet
  // ---------------------------------------------------------
  void _showTrendComparisonSheet() {
    if (_dateFilter == 'all_time') return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final String currentPeriodLabel = _dateFilter == 'today'
            ? 'Today'
            : _dateFilter == 'this_week'
                ? 'This Week'
                : 'This Month';
        final String prevPeriodLabel = _dateFilter == 'today'
            ? 'Yesterday'
            : _dateFilter == 'this_week'
                ? 'Last Week'
                : 'Last Month';

        Widget comparisonRow(String label, String currentVal, String prevVal, String deltaText, Color deltaColor) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    label,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    currentVal,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: context.palette.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    prevVal,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: context.palette.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    deltaText,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: deltaColor),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          );
        }

        final double daysPresentDiff = (_daysPresent - _prevDaysPresent).toDouble();
        final double daysAbsentDiff = (_daysAbsent - _prevDaysAbsent).toDouble();
        final double totalHoursDiff = _totalHours - _prevTotalHours;
        final double rateDiff = _attendanceRate - _prevAttendanceRate;

        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Performance Comparison',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                _trendLabel,
                style: GoogleFonts.inter(fontSize: 12, color: context.palette.textMuted),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text('Metric', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8))),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(currentPeriodLabel, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)), textAlign: TextAlign.center),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(prevPeriodLabel, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)), textAlign: TextAlign.center),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('Delta', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)), textAlign: TextAlign.right),
                  ),
                ],
              ),
              const Divider(height: 24),
              comparisonRow(
                'Days Present',
                '$_daysPresent',
                '$_prevDaysPresent',
                '${daysPresentDiff >= 0 ? '+' : ''}${daysPresentDiff.toStringAsFixed(0)}',
                daysPresentDiff >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
              ),
              comparisonRow(
                'Days Absent',
                '$_daysAbsent',
                '$_prevDaysAbsent',
                '${daysAbsentDiff <= 0 ? '' : '+'}${daysAbsentDiff.toStringAsFixed(0)}',
                daysAbsentDiff <= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
              ),
              comparisonRow(
                'Total Hours',
                '${_totalHours.toStringAsFixed(1)}h',
                '${_prevTotalHours.toStringAsFixed(1)}h',
                '${totalHoursDiff >= 0 ? '+' : ''}${totalHoursDiff.toStringAsFixed(1)}h',
                totalHoursDiff >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
              ),
              comparisonRow(
                'Attendance',
                '${_attendanceRate.toStringAsFixed(0)}%',
                '${_prevAttendanceRate.toStringAsFixed(0)}%',
                '${rateDiff >= 0 ? '+' : ''}${rateDiff.toStringAsFixed(0)}%',
                rateDiff >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text('Close', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------
  // 5. Day Attendance Popup (S076)
  // ---------------------------------------------------------
  void _showDayAttendancePopup(String dateStr, String status) async {
    if (widget.userProfile == null) return;
    
    final DateTime date = DateTime.parse(dateStr);
    final heading = DateFormat('EEEE, dd MMM yyyy').format(date);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: MemberAnalyticsService.instance.fetchDaySessions(widget.userProfile!['id'], dateStr),
          builder: (context, snapshot) {
            Widget content;
            if (snapshot.connectionState == ConnectionState.waiting) {
              content = const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator(color: Color(0xFFE65C00))),
              );
            } else if (snapshot.hasError) {
              content = SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    friendlyError(snapshot.error),
                    style: GoogleFonts.inter(color: Colors.red),
                  ),
                ),
              );
            } else {
              final logs = snapshot.data ?? [];
              if (logs.isEmpty) {
                if (status == 'closed') {
                  content = Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.ac_unit, color: Color(0xFF64748B), size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'Library Closed',
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'This day was scheduled as a closure. Your study streak was protected!',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 13, color: context.palette.textMuted),
                        ),
                      ],
                    ),
                  );
                } else if (status == 'today_partial') {
                  content = Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.qr_code_scanner, color: Color(0xFFE65C00), size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'No Scan Yet Today',
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Scan your QR at the entry gate to start your study session and keep your streak alive!',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 13, color: context.palette.textMuted),
                        ),
                      ],
                    ),
                  );
                } else {
                  content = Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.event_busy, color: Color(0xFFEF4444), size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'No Sessions',
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'No sessions on this day',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 13, color: context.palette.textMuted),
                        ),
                      ],
                    ),
                  );
                }
              } else {
                content = Container(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    itemCount: logs.length,
                    separatorBuilder: (c, i) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      final durationMins = log['duration_minutes'] as int;
                      final hrs = durationMins ~/ 60;
                      final mins = durationMins % 60;
                      final String durationStr = hrs > 0 ? '${hrs}h ${mins}m' : '${mins}m';

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.palette.scaffold,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    log['library_name'],
                                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Builder(builder: (_) {
                                  final tag = attendanceTag(log['session_type']);
                                  final bool incomplete = log['session_type'] == 'incomplete';
                                  final bool isOvertime = log['is_overtime'] == true;
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isOvertime) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF1F2),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'OVERTIME',
                                            style: GoogleFonts.inter(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFFE11D48),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: incomplete
                                              ? const Color(0xFFFFF1F2)
                                              : tag.isManual
                                                  ? const Color(0xFFFFF7E6)
                                                  : const Color(0xFFEFF6FF),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          tag.label.toUpperCase(),
                                          style: GoogleFonts.inter(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: incomplete
                                                ? const Color(0xFFE11D48)
                                                : tag.isManual
                                                    ? const Color(0xFFB45309)
                                                    : const Color(0xFF2563EB),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }),
                              ],
                            ),
                            const Divider(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Time Session', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
                                    const SizedBox(height: 2),
                                    Text('${log['check_in']} - ${log['check_out']}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textSecondary)),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('Duration', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
                                    const SizedBox(height: 2),
                                    Text(durationStr, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Seat', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
                                    const SizedBox(height: 2),
                                    Text(log['seat'], style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textSecondary)),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('Shift', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
                                    const SizedBox(height: 2),
                                    Text(log['shift'], style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textSecondary)),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              }
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Attendance Details',
                          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      heading,
                      style: GoogleFonts.inter(fontSize: 12, color: context.palette.textMuted),
                    ),
                  ),
                  const SizedBox(height: 12),
                  content,
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65C00),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text('Close', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------
  // 6. Leaderboard Card
  // ---------------------------------------------------------
  Widget _buildLeaderboardCard() {
    final uniqueLibraries = _getUniqueLibraries();
    final String selectedLeaderboardLibName = uniqueLibraries.firstWhere(
      (lib) => lib['id'] == _leaderboardLibraryId,
      orElse: () => {'id': '', 'name': 'SILENCE Study Zone'},
    )['name'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Leaderboard',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                ),
                // Period Filters specific to Leaderboard
                Row(
                  children: [
                    _leaderboardPeriodPill('Week', 'this_week'),
                    const SizedBox(width: 4),
                    _leaderboardPeriodPill('Month', 'this_month'),
                    const SizedBox(width: 4),
                    _leaderboardPeriodPill('All', 'all_time'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Library dropdown selector specific to Leaderboard
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                PopupMenuButton<String>(
                  onSelected: (val) {
                    setState(() {
                      _leaderboardLibraryId = val;
                    });
                    _loadLeaderboardDataOnly();
                  },
                  offset: const Offset(0, 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3ED),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE65C00).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selectedLeaderboardLibName,
                          style: GoogleFonts.inter(
                            color: const Color(0xFFE65C00),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down, color: Color(0xFFE65C00), size: 12),
                      ],
                    ),
                  ),
                  itemBuilder: (context) {
                    return uniqueLibraries.map((lib) {
                      return PopupMenuItem<String>(
                        value: lib['id'],
                        child: Text(
                          lib['name'],
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      );
                    }).toList();
                  },
                ),
                const SizedBox.shrink(),
              ],
            ),
            const SizedBox(height: 16),
            if (_leaderboardList.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                child: Center(
                  child: Text(
                    _leaderboardTotalMembers <= 1 && _leaderboardTotalMembers > 0
                        ? 'Be the first on the leaderboard! Start scanning.'
                        : 'No data for this period.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                  ),
                ),
              )
            else ...[
              // Top 10 members — scrollable when there are many; the member's own
              // pinned row (rendered below) stays fixed and never scrolls away.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const ClampingScrollPhysics(),
                  children: _leaderboardList.map((entry) {
                final rank = entry['rank'] as int;
                final isMe = entry['member_id'] == widget.userProfile?['id'];
                
                String rankIcon = '$rank';
                if (rank == 1) {
                  rankIcon = '🥇';
                } else if (rank == 2) {
                  rankIcon = '🥈';
                } else if (rank == 3) {
                  rankIcon = '🥉';
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? const Color(0xFFFFF3ED) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isMe ? const Color(0xFFE65C00).withValues(alpha: 0.3) : const Color(0xFFF1F5F9),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          rankIcon,
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: rank <= 3 ? 15 : 12,
                            color: context.palette.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isMe ? 'You (${entry['name']})' : entry['name'],
                          style: GoogleFonts.inter(
                            fontWeight: isMe ? FontWeight.bold : FontWeight.w500,
                            color: isMe ? const Color(0xFFE65C00) : context.palette.textPrimary,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      Text(
                        '${(entry['hours'] as double).toStringAsFixed(1)}h',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: isMe ? const Color(0xFFE65C00) : context.palette.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                );
                  }).toList(),
                ),
              ),

              // Dotted divider and current user row if outside top 10 — this row
              // is OUTSIDE the scroll area above, so it's always visible.
              if (_currentUserLeaderboardRow != null && _currentUserLeaderboardRank != null && _currentUserLeaderboardRank! > 10) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4.0),
                  child: Divider(color: Color(0xFFCBD5E1), thickness: 1.0),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3ED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE65C00).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '#$_currentUserLeaderboardRank',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: const Color(0xFFE65C00),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You (${_currentUserLeaderboardRow!['name']})',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFE65C00),
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      Text(
                        '${(_currentUserLeaderboardRow!['hours'] as double).toStringAsFixed(1)}h',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFE65C00),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Gap to top 5 note if applicable
              if (_leaderboardGapToTop5 > 0.0) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 4.0),
                  child: Text(
                    'Gap to top 10: need ${_leaderboardGapToTop5.toStringAsFixed(1)}h more',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.palette.textMuted,
                    ),
                  ),
                ),
              ],
            ]
          ],
        ),
      ),
    );
  }

  Widget _leaderboardPeriodPill(String label, String val) {
    final isSelected = _leaderboardPeriod == val;
    return GestureDetector(
      onTap: () {
        setState(() {
          _leaderboardPeriod = val;
        });
        _loadLeaderboardDataOnly();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE65C00) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isSelected ? Colors.white : context.palette.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // 7. Daily Study Hours Chart
  // ---------------------------------------------------------
  Widget _buildBarChart() {
    final displayData = _getDisplayChartData();

    bool isAllZero = true;
    for (var item in displayData) {
      final hoursMap = item['hours_by_library'] as Map<String, dynamic>? ?? {};
      double total = hoursMap.values.fold(0.0, (a, b) => a + (b as num).toDouble());
      if (total > 0.0) {
        isAllZero = false;
        break;
      }
    }

    return Padding(
      key: _chartKey,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Study Hours',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
            ),
            const SizedBox(height: 24),
            Stack(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      onTapDown: (details) {
                        if (isAllZero) return;

                        final localPos = details.localPosition;
                        final int barCount = displayData.length;
                        final double leftPadding = 35.0;
                        final double totalWidth = constraints.maxWidth - leftPadding;
                        final double spacing = totalWidth / (barCount * 3.5);
                        final double barWidth = (totalWidth - (spacing * (barCount + 1))) / barCount;

                        for (int i = 0; i < barCount; i++) {
                          final double xStart = leftPadding + spacing + i * (barWidth + spacing);
                          final double xEnd = xStart + barWidth;
                          if (localPos.dx >= xStart && localPos.dx <= xEnd) {
                            final item = displayData[i];
                            final dateStr = item['dateStr'] as String;
                            final hoursMap = item['hours_by_library'] as Map<String, dynamic>? ?? {};
                            final double hours = hoursMap.values.fold(0.0, (a, b) => a + (b as num).toDouble());

                            if (_dateFilter == 'all_time') {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Total in $dateStr: ${hours.toStringAsFixed(1)} hrs'),
                                  backgroundColor: const Color(0xFFE65C00),
                                ),
                              );
                            } else {
                              _showDayAttendancePopup(dateStr, hours > 0.0 ? 'present' : 'absent');
                            }
                            break;
                          }
                        }
                      },
                      child: SizedBox(
                        height: 130,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _StackedBarChartPainter(
                            chartData: displayData,
                            uniqueLibraries: _getUniqueLibraries(),
                            dateFilter: _dateFilter,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (isAllZero)
                  Positioned.fill(
                    bottom: 15,
                    left: 35,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          'No data yet. Start studying to see your hours.',
                          style: GoogleFonts.inter(
                            color: context.palette.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (!isAllZero && (_bestDayText != null || _weakestDayText != null)) ...[
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(left: 4.0),
                child: Text(
                  '${_bestDayText != null ? "Best day: $_bestDayText" : ""}${_weakestDayText != null ? "  ·  Weakest: $_weakestDayText" : ""}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: context.palette.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // 8. Calendar Heatmaps
  // ---------------------------------------------------------
  Widget _buildHeatmap() {
    return SizedBox(
      key: _calendarKey,
      width: double.infinity,
      child: _dateFilter == 'all_time' ? _buildYearHeatmap() : _buildMonthHeatmap(),
    );
  }

  Widget _buildYearHeatmap() {
    final today = DateTime.now();
    final start = today.subtract(const Duration(days: 364));
    final mondayOfStartWeek = start.subtract(Duration(days: start.weekday - 1));
    
    int totalDays = today.difference(mondayOfStartWeek).inDays + 1;
    int totalWeeks = (totalDays / 7).ceil();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Activity Heatmap',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: List.generate(totalWeeks, (weekIdx) {
                  return Column(
                    children: List.generate(7, (dayIdx) {
                      final date = mondayOfStartWeek.add(Duration(days: weekIdx * 7 + dayIdx));
                      final dateStr = DateFormat('yyyy-MM-dd').format(date);
                      final isFuture = date.isAfter(today);
                      
                      Widget cell;
                      if (isFuture) {
                        cell = const SizedBox(width: 12, height: 12);
                      } else {
                        final dynamic rawHours = _heatmapData[dateStr]?['hours'];
                        final double hours = rawHours != null ? (rawHours as num).toDouble() : 0.0;
                        final bool isClosed = _heatmapData[dateStr]?['is_closed'] == true;

                        Color color;
                        if (isClosed) {
                          color = const Color(0xFFE2E8F0);
                        } else if (hours >= 4.0) {
                          color = const Color(0xFFE65C00);
                        } else if (hours >= 2.0) {
                          color = const Color(0xFFFF9A4D);
                        } else if (hours > 0.0 || _heatmapData[dateStr] != null) {
                          color = const Color(0xFFFFCBA0);
                        } else {
                          color = Colors.white;
                        }

                        final todayStrLocal = DateFormat('yyyy-MM-dd').format(today);
                        cell = GestureDetector(
                          onTap: () => _showDayAttendancePopup(dateStr, isClosed ? 'closed' : (hours > 0 ? 'present' : 'absent')),
                          child: Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(
                                color: dateStr == todayStrLocal
                                    ? const Color(0xFFE65C00)
                                    : Colors.grey.withValues(alpha: 0.15),
                                width: dateStr == todayStrLocal ? 1.5 : 0.8,
                              ),
                            ),
                          ),
                        );
                      }
                      return cell;
                    }),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            _buildHeatmapLegend(showClosed: true),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthHeatmap() {
    final firstDayOfMonth = DateTime(_heatmapMonth.year, _heatmapMonth.month, 1);
    final lastDayOfMonth = DateTime(_heatmapMonth.year, _heatmapMonth.month + 1, 0);
    final offset = firstDayOfMonth.weekday - 1;
    
    final List<Widget> cells = [];
    final List<String> weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    for (var day in weekdays) {
      cells.add(
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text(
              day,
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)),
            ),
          ),
        ),
      );
    }

    for (int i = 0; i < offset; i++) {
      cells.add(const SizedBox.shrink());
    }

    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    for (int i = 1; i <= lastDayOfMonth.day; i++) {
      final date = DateTime(_heatmapMonth.year, _heatmapMonth.month, i);
      final dateStr = DateFormat('yyyy-MM-dd').format(date);

      final dynamic rawHours = _heatmapData[dateStr]?['hours'];
      final double hours = rawHours != null ? (rawHours as num).toDouble() : 0.0;
      final bool isClosed = _heatmapData[dateStr]?['is_closed'] == true;

      Color color;
      Widget? centerIcon;

      if (isClosed) {
        color = const Color(0xFFE2E8F0);
        centerIcon = const Text('❄', style: TextStyle(fontSize: 8));
      } else if (hours >= 4.0) {
        color = const Color(0xFFE65C00);
      } else if (hours >= 2.0) {
        color = const Color(0xFFFF9A4D);
      } else if (hours > 0.0 || _heatmapData[dateStr] != null) {
        // Present that day (any attendance record) — always shade it, even if
        // the session was short or its duration wasn't computed yet.
        color = const Color(0xFFFFCBA0);
      } else {
        color = Colors.white;
      }

      final isToday = dateStr == todayStr;

      cells.add(
        GestureDetector(
          onTap: () => _showDayAttendancePopup(dateStr, isClosed ? 'closed' : (hours > 0 ? 'present' : 'absent')),
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isToday ? const Color(0xFFE65C00) : Colors.grey.withValues(alpha: 0.15),
                width: isToday ? 2.0 : 0.8,
              ),
              boxShadow: isToday
                  ? [BoxShadow(color: const Color(0xFFE65C00).withValues(alpha: 0.15), blurRadius: 4, spreadRadius: 1)]
                  : null,
            ),
            child: Stack(
              children: [
                Center(
                  child: Text(
                    '$i',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                      color: isClosed
                          ? context.palette.textMuted
                          : hours >= 4.0
                              ? Colors.white
                              : context.palette.textPrimary,
                    ),
                  ),
                ),
                if (centerIcon != null)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: centerIcon,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: _pickHeatmapMonthYear,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('MMMM yyyy').format(_heatmapMonth),
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down, color: Color(0xFFE65C00), size: 22),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: Color(0xFFE65C00)),
                      onPressed: (_heatmapMonth.year <= 2020 && _heatmapMonth.month == 1)
                          ? null
                          : () {
                              setState(() {
                                _heatmapMonth = DateTime(_heatmapMonth.year, _heatmapMonth.month - 1, 1);
                              });
                              _loadHeatmapDataOnly();
                            },
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, color: Color(0xFFE65C00)),
                      onPressed: _heatmapMonth.year == DateTime.now().year && _heatmapMonth.month == DateTime.now().month
                          ? null
                          : () {
                              setState(() {
                                _heatmapMonth = DateTime(_heatmapMonth.year, _heatmapMonth.month + 1, 1);
                              });
                              _loadHeatmapDataOnly();
                            },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.custom(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.0,
              ),
              childrenDelegate: SliverChildListDelegate(cells),
            ),
            const SizedBox(height: 16),
            _buildHeatmapLegend(showClosed: true),
          ],
        ),
      ),
    );
  }

  // Month + year picker for the calendar heatmap. A year stepper (← 20xx →)
  // bounded between 2020 and the current year, plus a 12-month grid; picking a
  // month jumps the heatmap and reloads its data.
  Future<void> _pickHeatmapMonthYear() async {
    final now = DateTime.now();
    int pickerYear = _heatmapMonth.year;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    final result = await showDialog<DateTime>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              backgroundColor: context.palette.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Year stepper
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left, color: Color(0xFFE65C00)),
                          onPressed: pickerYear <= 2020 ? null : () => setLocal(() => pickerYear--),
                        ),
                        Text(
                          '$pickerYear',
                          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, color: Color(0xFFE65C00)),
                          onPressed: pickerYear >= now.year ? null : () => setLocal(() => pickerYear++),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Month grid
                    GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.6,
                      children: List.generate(12, (i) {
                        final monthNum = i + 1;
                        final isFuture = pickerYear == now.year && monthNum > now.month;
                        final isSelected = pickerYear == _heatmapMonth.year && monthNum == _heatmapMonth.month;
                        return GestureDetector(
                          onTap: isFuture ? null : () => Navigator.pop(context, DateTime(pickerYear, monthNum, 1)),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFE65C00) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isSelected ? const Color(0xFFE65C00) : const Color(0xFFE2E8F0)),
                            ),
                            child: Center(
                              child: Text(
                                months[i],
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isFuture
                                      ? const Color(0xFFCBD5E1)
                                      : isSelected
                                          ? Colors.white
                                          : context.palette.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.inter(color: context.palette.textMuted)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() => _heatmapMonth = result);
      _loadHeatmapDataOnly();
    }
  }

  Widget _buildHeatmapLegend({required bool showClosed}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendItem(Colors.white, 'Absent'),
        const SizedBox(width: 8),
        _legendItem(const Color(0xFFFFCBA0), '<2h'),
        const SizedBox(width: 8),
        _legendItem(const Color(0xFFFF9A4D), '2-4h'),
        const SizedBox(width: 8),
        _legendItem(const Color(0xFFE65C00), '4h+'),
        if (showClosed) ...[
          const SizedBox(width: 8),
          _legendItem(const Color(0xFFE2E8F0), 'Closed ❄'),
        ],
      ],
    );
  }

  Widget _legendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2), width: 0.5),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.inter(fontSize: 10, color: context.palette.textMuted),
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  // 9. Shimmer Loading Skeleton
  // ---------------------------------------------------------
  Widget _buildShimmerLoading() {
    return Shimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100, top: 16),
        child: Column(
          children: [
            // Streak card skeleton
            _shimmerCard(height: 200),
            const SizedBox(height: 16),
            // Summary grid skeleton
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(child: _shimmerCard(height: 100, padding: EdgeInsets.zero)),
                  const SizedBox(width: 16),
                  Expanded(child: _shimmerCard(height: 100, padding: EdgeInsets.zero)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(child: _shimmerCard(height: 100, padding: EdgeInsets.zero)),
                  const SizedBox(width: 16),
                  Expanded(child: _shimmerCard(height: 100, padding: EdgeInsets.zero)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Badges skeleton
            _shimmerCard(height: 80),
            const SizedBox(height: 24),
            // Leaderboard skeleton
            _shimmerCard(height: 200),
            const SizedBox(height: 24),
            // Chart skeleton
            _shimmerCard(height: 180),
          ],
        ),
      ),
    );
  }

  Widget _shimmerCard({required double height, EdgeInsetsGeometry? padding}) {
    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16.0),
      child: SkeletonBox(
        width: double.infinity,
        height: height,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  // ---------------------------------------------------------
  // 10. Badges Section
  // ---------------------------------------------------------
  static const List<Map<String, String>> _allBadgeDefinitions = [
    {'type': '7_day_streak', 'title': '7-Day Streak', 'emoji': '🔥', 'condition': 'Study for 7 consecutive days'},
    {'type': '30_day_streak', 'title': '30-Day Streak', 'emoji': '💪', 'condition': 'Study for 30 consecutive days'},
    {'type': 'early_bird', 'title': 'Early Bird', 'emoji': '🌅', 'condition': 'Check in before 7:00 AM, 5 times'},
    {'type': 'night_owl', 'title': 'Night Owl', 'emoji': '🦉', 'condition': 'Check in after 8:00 PM, 5 times'},
    {'type': '100_days_club', 'title': '100 Days Club', 'emoji': '🏆', 'condition': 'Be present for 100 total days'},
    {'type': 'consistent', 'title': 'Consistent', 'emoji': '📊', 'condition': '90%+ attendance rate in a month'},
    {'type': 'top_of_week', 'title': 'Top of the Week', 'emoji': '👑', 'condition': 'Rank #1 on leaderboard for a week'},
  ];

  /// Badge definitions ordered so EARNED badges come first (most recently earned
  /// first), then the still-locked ones in their canonical order — the member
  /// sees their achievements up front instead of having to scroll past locked
  /// ones. Stable: ties keep canonical order.
  List<Map<String, String>> get _orderedBadgeDefinitions {
    DateTime? earnedAt(String type) {
      final b = _earnedBadges.firstWhere(
        (e) => e['badge_type'] == type,
        orElse: () => const {},
      );
      final raw = b['created_at'];
      return raw is String ? DateTime.tryParse(raw) : null;
    }

    final earned = <Map<String, String>>[];
    final locked = <Map<String, String>>[];
    for (final def in _allBadgeDefinitions) {
      if (_earnedBadges.any((b) => b['badge_type'] == def['type'])) {
        earned.add(def);
      } else {
        locked.add(def);
      }
    }
    // Most recently earned first; unknown dates fall back to canonical order.
    earned.sort((a, b) {
      final da = earnedAt(a['type']!);
      final db = earnedAt(b['type']!);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return [...earned, ...locked];
  }

  Widget _buildBadgesSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Achievements',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                ),
                Text(
                  '${_earnedBadges.length}/${_allBadgeDefinitions.length}',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _orderedBadgeDefinitions.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final badgeDef = _orderedBadgeDefinitions[index];
                  final String type = badgeDef['type']!;
                  final bool isEarned = _earnedBadges.any((b) => b['badge_type'] == type);

                  // Find earned date
                  String? earnedDate;
                  if (isEarned) {
                    final badge = _earnedBadges.firstWhere((b) => b['badge_type'] == type, orElse: () => {});
                    if (badge.isNotEmpty && badge['created_at'] != null) {
                      earnedDate = DateFormat('dd MMM yyyy').format(DateTime.parse(badge['created_at']).toLocal());
                    }
                  }

                  return GestureDetector(
                    onTap: () => _showBadgeDetailSheet(badgeDef, isEarned, earnedDate),
                    child: SizedBox(
                      width: 72,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: isEarned ? const Color(0xFFFFF3ED) : const Color(0xFFF1F5F9),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isEarned ? const Color(0xFFE65C00) : Colors.grey[300]!,
                                width: isEarned ? 2.0 : 1.0,
                              ),
                              boxShadow: isEarned
                                  ? [BoxShadow(color: const Color(0xFFE65C00).withValues(alpha: 0.15), blurRadius: 6, spreadRadius: 1)]
                                  : null,
                            ),
                            child: Center(
                              child: isEarned
                                  ? Text(badgeDef['emoji']!, style: const TextStyle(fontSize: 24))
                                  : Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Opacity(
                                          opacity: 0.3,
                                          child: Text(badgeDef['emoji']!, style: const TextStyle(fontSize: 24)),
                                        ),
                                        const Icon(Icons.lock, size: 14, color: Color(0xFF94A3B8)),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            badgeDef['title']!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: isEarned ? FontWeight.bold : FontWeight.w500,
                              color: isEarned ? context.palette.textPrimary : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBadgeDetailSheet(Map<String, String> badgeDef, bool isEarned, String? earnedDate) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: isEarned ? const Color(0xFFFFF3ED) : const Color(0xFFF8FAFC),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isEarned ? const Color(0xFFE65C00) : Colors.grey[300]!,
                    width: 2.5,
                  ),
                ),
                child: Center(
                  child: isEarned
                      ? Text(badgeDef['emoji']!, style: const TextStyle(fontSize: 36))
                      : Opacity(
                          opacity: 0.35,
                          child: Text(badgeDef['emoji']!, style: const TextStyle(fontSize: 36)),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                badgeDef['title']!,
                style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isEarned ? const Color(0xFFDCFCE7) : const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isEarned ? '✅ Earned' : '🔒 Locked',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isEarned ? const Color(0xFF16A34A) : const Color(0xFFEF4444),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                badgeDef['condition']!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, color: context.palette.textMuted, height: 1.5),
              ),
              if (isEarned && earnedDate != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Earned $earnedDate',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text('Close', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------
  // 11. Export CSV Button
  // ---------------------------------------------------------
  Widget _buildExportButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _isExporting ? null : _handleExportCSV,
          icon: _isExporting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: const Color(0xFFE65C00).withValues(alpha: 0.6),
                  ),
                )
              : const Icon(Icons.file_download_outlined, size: 18),
          label: Text(
            _isExporting ? 'Exporting...' : 'Export My Attendance CSV',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFE65C00),
            side: BorderSide(color: const Color(0xFFE65C00).withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  Future<void> _handleExportCSV() async {
    if (widget.userProfile == null) return;
    setState(() => _isExporting = true);

    try {
      final String memberId = widget.userProfile!['id'];
      final String nickname = widget.userProfile!['nickname'] ?? widget.userProfile!['full_name'] ?? 'Member';
      final uniqueLibs = _getUniqueLibraries();
      final List<String> memberLibraryIds = uniqueLibs.map((e) => e['id'] as String).toList();

      final logs = await MemberAnalyticsService.instance.fetchAttendanceForExport(
        memberId: memberId,
        libraryId: _selectedLibraryId ?? 'all',
        startDate: _dateRange.start,
        endDate: _dateRange.end,
        memberLibraryIds: _selectedLibraryId == 'all' ? memberLibraryIds : null,
      );

      final startLabel = DateFormat('dd_MMM_yyyy').format(_dateRange.start);
      final endLabel = DateFormat('dd_MMM_yyyy').format(_dateRange.end);
      final dateRangeLabel = '${startLabel}_to_$endLabel';

      if (logs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No attendance data to export for this period.', style: GoogleFonts.inter()),
              backgroundColor: context.palette.textMuted,
            ),
          );
        }
      } else {
        await CsvExporter.exportMemberAttendance(
          nickname: nickname,
          dateRangeLabel: dateRangeLabel,
          logs: logs,
        );
      }
    } catch (e) {
      debugPrint('Error exporting CSV: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export: $e', style: GoogleFonts.inter()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  // ---------------------------------------------------------
  // 12. Notifications → real shared NotificationsScreen (see the bell above)
  // ---------------------------------------------------------
}

// ---------------------------------------------------------
// Custom Painter for Stacked Bar Chart (Phase 2)
// ---------------------------------------------------------
class _StackedBarChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> chartData;
  final List<Map<String, dynamic>> uniqueLibraries;
  final String dateFilter;

  final List<Color> colors = [
    const Color(0xFFE65C00),
    const Color(0xFFF47B2E),
    const Color(0xFFFF9A4D),
    const Color(0xFFFFCBA0),
  ];

  _StackedBarChartPainter({
    required this.chartData,
    required this.uniqueLibraries,
    required this.dateFilter,
  });

  Color _getLibraryColor(String libId) {
    final idx = uniqueLibraries.indexWhere((e) => e['id'] == libId);
    if (idx == -1) return colors[0];
    return colors[idx % colors.length];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (chartData.isEmpty) return;

    double maxHours = 0.0;
    for (var item in chartData) {
      final hoursMap = item['hours_by_library'] as Map<String, dynamic>? ?? {};
      double total = hoursMap.values.fold(0.0, (a, b) => a + (b as num).toDouble());
      if (total > maxHours) maxHours = total;
    }

    final bool isAllZero = maxHours <= 0.0;
    if (isAllZero) {
      maxHours = 8.0; // default y-axis max hours
    } else {
      if (maxHours < 4.0) {
        maxHours = 4.0;
      } else {
        maxHours = ((maxHours / 2).ceil() * 2).toDouble();
      }
    }

    final double leftPadding = 35.0;
    final double chartHeight = size.height - 15;
    final double chartWidth = size.width - leftPadding;

    final int barCount = chartData.length;
    final double spacing = chartWidth / (barCount * 3.5);
    final double barWidth = (chartWidth - (spacing * (barCount + 1))) / barCount;

    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // 1. Draw Grid Lines and Y-Axis Scale Labels
    final gridPaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..strokeWidth = 1.0;

    final double stepVal = maxHours / 4;
    for (int j = 0; j <= 4; j++) {
      final double val = maxHours - (j * stepVal);
      final double y = (j / 4) * chartHeight;

      final yLabelPainter = TextPainter(
        text: TextSpan(
          text: '${val.toStringAsFixed(1)}h',
          style: GoogleFonts.inter(
            fontSize: 8,
            color: const Color(0xFF94A3B8),
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      yLabelPainter.layout();
      yLabelPainter.paint(
        canvas,
        Offset(leftPadding - yLabelPainter.width - 6, y - (yLabelPainter.height / 2)),
      );

      // Draw horizontal grid line
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    // 2. Draw Bars and X-Axis Labels
    for (int i = 0; i < barCount; i++) {
      final item = chartData[i];
      final label = item['label'] as String;
      final dateStr = item['dateStr'] as String;
      final hoursMap = item['hours_by_library'] as Map<String, dynamic>? ?? {};

      final double x = leftPadding + spacing + i * (barWidth + spacing);
      final double totalDayHours = hoursMap.values.fold(0.0, (a, b) => a + (b as num).toDouble());

      // Draw label below bar
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: GoogleFonts.inter(
            fontSize: 9,
            color: const Color(0xFF94A3B8),
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x + (barWidth - textPainter.width) / 2, chartHeight + 6),
      );

      if (totalDayHours == 0.0) {
        final zeroPaint = Paint()..color = const Color(0xFFE2E8F0);
        canvas.drawRRect(
          RRect.fromLTRBR(
            x,
            chartHeight - 1.5,
            x + barWidth,
            chartHeight,
            const Radius.circular(1),
          ),
          zeroPaint,
        );
        continue;
      }

      // Draw stacked segments
      double currentY = chartHeight;
      final bool isToday = dateStr == todayStr;

      hoursMap.forEach((libId, hoursVal) {
        final double hours = (hoursVal as num).toDouble();
        final double segmentHeight = (hours / maxHours) * chartHeight;
        if (segmentHeight <= 0.0) return;

        final Color baseColor = _getLibraryColor(libId);
        final Color segmentColor = isToday ? baseColor.withValues(alpha: 0.9) : baseColor;

        final segmentPaint = Paint()..color = segmentColor;

        final rect = RRect.fromLTRBR(
          x,
          currentY - segmentHeight,
          x + barWidth,
          currentY,
          const Radius.circular(3),
        );
        canvas.drawRRect(rect, segmentPaint);
        currentY -= segmentHeight;
      });

      // Draw border ring for today
      if (isToday) {
        final ringPaint = Paint()
          ..color = const Color(0xFFE65C00)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        final totalHeight = (totalDayHours / maxHours) * chartHeight;
        final rect = RRect.fromLTRBR(
          x - 1,
          chartHeight - totalHeight - 1,
          x + barWidth + 1,
          chartHeight + 1,
          const Radius.circular(4),
        );
        canvas.drawRRect(rect, ringPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
