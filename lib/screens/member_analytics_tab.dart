import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../core/member_analytics_service.dart';

class MemberAnalyticsTab extends StatefulWidget {
  final Map<String, dynamic>? userProfile;
  final String? activeLibraryId;
  final List<dynamic> memberLibraries; // List of libraries the member is part of

  const MemberAnalyticsTab({
    super.key,
    required this.userProfile,
    required this.activeLibraryId,
    required this.memberLibraries,
  });

  @override
  State<MemberAnalyticsTab> createState() => _MemberAnalyticsTabState();
}

class _MemberAnalyticsTabState extends State<MemberAnalyticsTab> with AutomaticKeepAliveClientMixin {
  bool _isLoading = true;

  String _dateFilter = 'this_month'; // 'today', 'this_week', 'this_month', 'all_time'
  DateTimeRange _dateRange = _getMonthRange();

  String? _selectedLibraryId;

  // Analytics Data
  int _daysPresent = 0;
  int _daysAbsent = 0;
  int _totalHours = 0;
  double _attendanceRate = 0.0;
  List<dynamic> _rawAttendance = [];

  // Streak Data
  int _currentStreak = 0;
  int _bestStreak = 0;

  // Leaderboard Data
  List<Map<String, dynamic>> _leaderboard = [];

  // Badges Data
  List<Map<String, dynamic>> _badges = [];

  @override
  void initState() {
    super.initState();
    _selectedLibraryId = widget.activeLibraryId;
    if (_selectedLibraryId != null) {
      final exists = widget.memberLibraries.any((lib) => lib['library_id'] == _selectedLibraryId);
      if (!exists) {
        _selectedLibraryId = widget.memberLibraries.isNotEmpty ? widget.memberLibraries.first['library_id'] : null;
      }
    } else if (widget.memberLibraries.isNotEmpty) {
      _selectedLibraryId = widget.memberLibraries.first['library_id'];
    }
    _loadAllData();
  }

  static DateTimeRange _getMonthRange() {
    final now = DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
  }

  void _setDateFilter(String filter) {
    final now = DateTime.now();
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

  Future<void> _loadAllData() async {
    if (_selectedLibraryId == null || widget.userProfile == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    final String memberId = widget.userProfile!['id'];

    try {
      // 1. Fetch Summary
      final summary = await MemberAnalyticsService.instance.fetchAnalyticsSummary(
        memberId,
        _selectedLibraryId!,
        _dateRange.start,
        _dateRange.end,
      );

      _daysPresent = summary['daysPresent'];
      _daysAbsent = summary['daysAbsent'];
      _totalHours = summary['totalHours'];
      _attendanceRate = summary['attendanceRate'];
      _rawAttendance = summary['rawAttendance'];

      // 2. Fetch Streaks
      final streak = await MemberAnalyticsService.instance.fetchStreak(memberId, _selectedLibraryId!);
      _currentStreak = streak['current'] ?? 0;
      _bestStreak = streak['best'] ?? 0;

      // 3. Fetch Badges
      final badges = await MemberAnalyticsService.instance.syncAndFetchBadges(memberId, _selectedLibraryId!);
      _badges = List<Map<String, dynamic>>.from(badges);

      // 4. Fetch Leaderboard
      final lb = await MemberAnalyticsService.instance.fetchLeaderboard(_selectedLibraryId!, _dateRange.start, _dateRange.end);
      _leaderboard = lb;

    } catch (e) {
      debugPrint('Error loading member analytics: $e');
    }

    setState(() => _isLoading = false);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFFFBF5EE),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
                : RefreshIndicator(
                    color: const Color(0xFFE65C00),
                    onRefresh: _loadAllData,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 100), // FAB space
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                          const SizedBox(height: 32),
                          _buildExportButton(),
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
  // 1. Header (Matches Premium Immersive Shell)
  // ---------------------------------------------------------
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF6B00), Color(0xFFE65C00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        bottom: 24,
        left: 16,
        right: 16,
      ),
      child: Column(
        children: [
          // Top Row: Logo & Dropdown
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'My Progress',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (widget.memberLibraries.length > 1)
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: const Color(0xFFE65C00),
                    icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                    value: widget.memberLibraries.any((lib) => lib['library_id'] == _selectedLibraryId) ? _selectedLibraryId : null,
                    items: widget.memberLibraries.map((lib) {
                      return DropdownMenuItem<String>(
                        value: lib['library_id'],
                        child: Text(
                          lib['libraries']?['name'] ?? 'Library',
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedLibraryId = val);
                        _loadAllData();
                      }
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          // Date Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterPill('Today', 'today'),
                const SizedBox(width: 8),
                _buildFilterPill('This Week', 'this_week'),
                const SizedBox(width: 8),
                _buildFilterPill('This Month', 'this_month'),
                const SizedBox(width: 8),
                _buildFilterPill('All Time', 'all_time'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill(String label, String value) {
    final isSelected = _dateFilter == value;
    return GestureDetector(
      onTap: () => _setDateFilter(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isSelected ? const Color(0xFFE65C00) : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // 2. Streak Card
  // ---------------------------------------------------------
  Widget _buildStreakCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFE65C00),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: const Color(0xFFE65C00).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Text('🔥', style: TextStyle(fontSize: 32)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current Streak', style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('$_currentStreak', style: GoogleFonts.outfit(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      Text('Days', style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Best', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
                Text('$_bestStreak Days', style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            )
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // 3. Summary Grid
  // ---------------------------------------------------------
  Widget _buildSummaryGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.4,
        children: [
          _buildStatCard('Days Present', '$_daysPresent', Icons.event_available, const Color(0xFF22C55E)),
          _buildStatCard('Days Absent', '$_daysAbsent', Icons.event_busy, const Color(0xFFEF4444)),
          _buildStatCard('Total Hours', '$_totalHours', Icons.timer, const Color(0xFF3B82F6)),
          _buildStatCard('Attendance Rate', '${_attendanceRate.toStringAsFixed(0)}%', Icons.analytics, const Color(0xFF8B5CF6)),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.bold)),
              Icon(icon, size: 16, color: color),
            ],
          ),
          Text(value, style: GoogleFonts.outfit(color: const Color(0xFF1E293B), fontSize: 24, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // 4. Badges Section
  // ---------------------------------------------------------
  Widget _buildBadgesSection() {
    final earnedBadgeTypes = _badges.map((b) => b['badge_type'] as String).toSet();
    
    final List<Map<String, dynamic>> allBadges = [
      {'type': '7_day_streak', 'icon': '🔥', 'name': '7-Day Streak', 'desc': 'Check in 7 days in a row.'},
      {'type': '30_day_streak', 'icon': '💯', 'name': '30-Day Streak', 'desc': 'Check in 30 days in a row.'},
      {'type': 'early_bird', 'icon': '⏰', 'name': 'Early Bird', 'desc': 'Check in before 7 AM 5 times.'},
      {'type': 'night_owl', 'icon': '🦉', 'name': 'Night Owl', 'desc': 'Check in after 8 PM 5 times.'},
      {'type': 'consistent', 'icon': '⚡', 'name': 'Consistent', 'desc': 'Achieve 90%+ attendance this month.'},
      {'type': '100_days_club', 'icon': '📅', 'name': '100 Days Club', 'desc': 'Total 100 days of studying.'},
      {'type': 'top_of_week', 'icon': '🏆', 'name': 'Top of Week', 'desc': 'Ranked #1 in Leaderboard.'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text('Achievements', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E))),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: allBadges.length,
            separatorBuilder: (c, i) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final b = allBadges[index];
              final isEarned = earnedBadgeTypes.contains(b['type']);
              return GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${b['name']}: ${b['desc']} ${isEarned ? '(Earned ✓)' : '(Locked)'}'),
                    duration: const Duration(seconds: 2),
                  ));
                },
                child: Container(
                  width: 80,
                  decoration: BoxDecoration(
                    color: isEarned ? const Color(0xFFFEF3C7) : Colors.grey[200],
                    borderRadius: BorderRadius.circular(16),
                    border: isEarned ? Border.all(color: const Color(0xFFF59E0B), width: 2) : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(b['icon'], style: TextStyle(fontSize: 32, color: isEarned ? null : Colors.grey)),
                      const SizedBox(height: 8),
                      Text(
                        b['name'],
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isEarned ? const Color(0xFFB45309) : Colors.grey[500],
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  // 5. Leaderboard Card
  // ---------------------------------------------------------
  Widget _buildLeaderboardCard() {
    final String memberId = widget.userProfile?['id'] ?? '';
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Leaderboard', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E))),
                Text('Top 5', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            if (_leaderboard.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(child: Text('No data for this period.', style: GoogleFonts.inter(color: Colors.grey))),
              )
            else
              ...List.generate(_leaderboard.length > 5 ? 5 : _leaderboard.length, (index) {
                final entry = _leaderboard[index];
                final isMe = entry['member_id'] == memberId;
                final hrs = (entry['total_duration'] as int) ~/ 60;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: isMe ? const Color(0xFFFEF3C7) : Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: isMe ? Border.all(color: const Color(0xFFF59E0B)) : Border.all(color: Colors.transparent),
                  ),
                  child: Row(
                    children: [
                      Text('#${index + 1}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: isMe ? const Color(0xFFB45309) : Colors.grey[600])),
                      const SizedBox(width: 16),
                      Expanded(child: Text(isMe ? 'You' : entry['display_name'], style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)))),
                      Text('${hrs}h', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: isMe ? const Color(0xFFB45309) : const Color(0xFFE65C00))),
                    ],
                  ),
                );
              }),
              
              // If 'You' are not in Top 5, append at bottom
              if (_leaderboard.length > 5 && !_leaderboard.take(5).any((e) => e['member_id'] == memberId)) ...[
                const Divider(),
                Builder(builder: (context) {
                  final myIndex = _leaderboard.indexWhere((e) => e['member_id'] == memberId);
                  if (myIndex == -1) return const SizedBox.shrink();
                  final entry = _leaderboard[myIndex];
                  final hrs = (entry['total_duration'] as int) ~/ 60;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: Row(
                      children: [
                        Text('#${myIndex + 1}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFFB45309))),
                        const SizedBox(width: 16),
                        Expanded(child: Text('You', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)))),
                        Text('${hrs}h', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFFB45309))),
                      ],
                    ),
                  );
                })
              ]
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // 6. Bar Chart (Daily Hours)
  // ---------------------------------------------------------
  Widget _buildBarChart() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        height: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Daily Study Hours', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E))),
            const SizedBox(height: 16),
            Expanded(
              child: CustomPaint(
                painter: _BarChartPainter(_rawAttendance, _dateRange),
                child: Container(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // 7. Heatmap
  // ---------------------------------------------------------
  Widget _buildHeatmap() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Activity Heatmap (30 Days)', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E))),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7, // 7 days a week
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: 30, // Last 30 days
              itemBuilder: (context, index) {
                final date = DateTime.now().subtract(Duration(days: 29 - index));
                final dateStr = DateFormat('yyyy-MM-dd').format(date);
                
                // Calculate hours for this day
                int mins = 0;
                for (var r in _rawAttendance) {
                  if (r['check_in_time'] != null && r['duration_minutes'] != null) {
                    final d = DateFormat('yyyy-MM-dd').format(DateTime.parse(r['check_in_time']));
                    if (d == dateStr) {
                      mins += r['duration_minutes'] as int;
                    }
                  }
                }
                
                final hrs = mins / 60.0;
                Color boxColor = Colors.white;
                if (hrs > 0 && hrs <= 2) boxColor = const Color(0xFFFFEDD5); // Very light orange
                else if (hrs > 2 && hrs <= 5) boxColor = const Color(0xFFFDBA74); // Light orange
                else if (hrs > 5 && hrs <= 8) boxColor = const Color(0xFFF97316); // Orange
                else if (hrs > 8) boxColor = const Color(0xFFC2410C); // Dark orange
                
                return GestureDetector(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('${DateFormat('MMM dd').format(date)}: ${hrs.toStringAsFixed(1)} hrs'),
                      duration: const Duration(seconds: 2),
                    ));
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: boxColor,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.withOpacity(0.2)),
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Future<void> _exportAttendanceCSV() async {
    if (_selectedLibraryId == null || widget.userProfile == null) return;
    
    final String memberId = widget.userProfile!['id'];
    
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generating CSV...')),
      );

      final response = await Supabase.instance.client
          .from('attendance')
          .select()
          .eq('member_id', memberId)
          .eq('library_id', _selectedLibraryId!)
          .order('check_in_time', ascending: false);

      final List<dynamic> logs = response as List<dynamic>;

      final buffer = StringBuffer('Log ID,Check-in Time,Check-out Time,Duration (Minutes),Status\n');
      
      String csvValue(Object? value) {
        final text = (value ?? '').toString().replaceAll('"', '""');
        return '"$text"';
      }

      for (var row in logs) {
        buffer.writeln([
          row['id'],
          row['check_in_time'],
          row['check_out_time'] ?? 'N/A',
          row['duration_minutes'] ?? '0',
          row['check_out_time'] == null ? 'Active' : 'Completed',
        ].map(csvValue).join(','));
      }

      final startFmt = DateFormat('yyyy-MM-dd').format(_dateRange.start);
      final endFmt = DateFormat('yyyy-MM-dd').format(_dateRange.end);

      await Share.share(
        buffer.toString(),
        subject: 'SILENCE_my_attendance_${startFmt}_to_$endFmt.csv',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ---------------------------------------------------------
  // 8. Export Button
  // ---------------------------------------------------------
  Widget _buildExportButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _exportAttendanceCSV,
          icon: const Icon(Icons.download),
          label: const Text('Export Attendance CSV'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFE65C00),
            side: const BorderSide(color: Color(0xFFE65C00)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }
}

// Custom Painter for simple Bar Chart
class _BarChartPainter extends CustomPainter {
  final List<dynamic> attendance;
  final DateTimeRange range;

  _BarChartPainter(this.attendance, this.range);

  @override
  void paint(Canvas canvas, Size size) {
    int days = range.end.difference(range.start).inDays + 1;
    if (days <= 0) days = 1;
    
    // Group attendance by day
    Map<String, double> hoursPerDay = {};
    for (int i = 0; i < days; i++) {
      hoursPerDay[DateFormat('yyyy-MM-dd').format(range.start.add(Duration(days: i)))] = 0.0;
    }

    for (var r in attendance) {
      if (r['check_in_time'] != null && r['duration_minutes'] != null) {
        final dStr = DateFormat('yyyy-MM-dd').format(DateTime.parse(r['check_in_time']));
        if (hoursPerDay.containsKey(dStr)) {
          hoursPerDay[dStr] = hoursPerDay[dStr]! + ((r['duration_minutes'] as int) / 60.0);
        }
      }
    }

    List<double> values = hoursPerDay.values.toList();
    double maxVal = values.isEmpty ? 1 : values.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) maxVal = 1; // Prevent divide by zero

    final paint = Paint()
      ..color = const Color(0xFFFDBA74)
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final todayPaint = Paint()
      ..color = const Color(0xFFE65C00)
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    double barWidth = (size.width / days) * 0.6;
    double spacing = (size.width / days) * 0.4;

    for (int i = 0; i < days; i++) {
      String dStr = DateFormat('yyyy-MM-dd').format(range.start.add(Duration(days: i)));
      double val = hoursPerDay[dStr] ?? 0.0;
      double barHeight = (val / maxVal) * size.height;
      
      double left = i * (barWidth + spacing) + spacing / 2;
      double top = size.height - barHeight;
      double right = left + barWidth;
      double bottom = size.height;

      final rect = RRect.fromLTRBR(left, top, right, bottom, const Radius.circular(4));
      
      if (dStr == todayStr) {
        canvas.drawRRect(rect, todayPaint);
      } else {
        canvas.drawRRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
