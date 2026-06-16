import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

class MemberAnalyticsService {
  static final MemberAnalyticsService instance = MemberAnalyticsService._init();
  MemberAnalyticsService._init();

  final _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> _getClosures({
    String? libraryId,
    List<String>? memberLibraryIds,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _supabase.from('scheduled_closures').select('*');
      if (libraryId != null && libraryId != 'all') {
        query = query.eq('library_id', libraryId);
      } else if (memberLibraryIds != null && memberLibraryIds.isNotEmpty) {
        query = query.inFilter('library_id', memberLibraryIds);
      }
      
      final res = await query;
      final list = List<Map<String, dynamic>>.from(res);
      
      if (startDate != null && endDate != null) {
        final startStr = DateFormat('yyyy-MM-dd').format(startDate);
        final endStr = DateFormat('yyyy-MM-dd').format(endDate);
        
        return list.where((c) {
          final dateStr = c['closure_date'] ?? c['start_date'] ?? c['date'];
          if (dateStr == null) return false;
          try {
            final dateStrOnly = dateStr.toString().split('T').first;
            return dateStrOnly.compareTo(startStr) >= 0 && dateStrOnly.compareTo(endStr) <= 0;
          } catch (_) {
            return false;
          }
        }).toList();
      }
      return list;
    } catch (e) {
      debugPrint('Error getting closures: $e');
      return [];
    }
  }

  /// Fetches closures count for libraries within a date range.
  Future<int> _fetchClosuresCount(String? libraryId, DateTime startDate, DateTime endDate, {List<String>? memberLibraryIds}) async {
    final list = await _getClosures(
      libraryId: libraryId,
      memberLibraryIds: memberLibraryIds,
      startDate: startDate,
      endDate: endDate,
    );
    Set<String> uniqueDates = {};
    for (var c in list) {
      final dateStr = c['closure_date'] ?? c['start_date'] ?? c['date'];
      if (dateStr != null) {
        uniqueDates.add(dateStr.toString().split('T').first);
      }
    }
    return uniqueDates.length;
  }

  /// Calculates statistics (Days Present, Days Absent, Total Hours, Attendance Rate) for a specific range.
  Future<Map<String, dynamic>> _calculateStatsForRange({
    required String memberId,
    required String? libraryId,
    required DateTime startDate,
    required DateTime endDate,
    List<String>? memberLibraryIds,
  }) async {
    // Don't count days BEFORE the member actually joined as "absent". Clamp the
    // elapsed-days anchor to the membership start when it falls inside the range
    // (fixes inflated absent counts for members who joined mid-period).
    DateTime effectiveStart = startDate;
    try {
      var msQ = _supabase.from('memberships').select('start_date');
      if (libraryId != null && libraryId != 'all') {
        msQ = msQ.eq('library_id', libraryId);
      } else if (memberLibraryIds != null && memberLibraryIds.isNotEmpty) {
        msQ = msQ.inFilter('library_id', memberLibraryIds);
      }
      final msRes = await msQ
          .eq('member_id', memberId)
          .order('start_date', ascending: true)
          .limit(1)
          .maybeSingle();
      final joinStr = msRes?['start_date']?.toString();
      if (joinStr != null && joinStr.isNotEmpty) {
        final join = DateTime.tryParse(joinStr);
        if (join != null && join.isAfter(startDate)) {
          effectiveStart = DateTime(join.year, join.month, join.day);
        }
      }
    } catch (_) {
      // No membership row / query unavailable → fall back to the period start.
    }

    // 1. Try querying member_daily_stats table first
    try {
      var query = _supabase.from('member_daily_stats').select();
      if (libraryId != null && libraryId != 'all') {
        query = query.eq('library_id', libraryId);
      } else if (memberLibraryIds != null && memberLibraryIds.isNotEmpty) {
        query = query.inFilter('library_id', memberLibraryIds);
      }
      
      final statsRes = await query
          .eq('member_id', memberId)
          .gte('date', DateFormat('yyyy-MM-dd').format(startDate))
          .lte('date', DateFormat('yyyy-MM-dd').format(endDate));

      final List<dynamic> statsList = statsRes as List<dynamic>;
      if (statsList.isNotEmpty) {
        Set<String> presentDays = {};
        double totalMinutes = 0.0;
        
        for (var row in statsList) {
          final dateStr = row['date'] as String;
          if (row['present_flag'] == true) {
            presentDays.add(dateStr);
          }
          totalMinutes += (row['total_minutes'] as num).toDouble();
        }

        int daysPresent = presentDays.length;
        int closedDaysCount = await _fetchClosuresCount(libraryId, startDate, endDate, memberLibraryIds: memberLibraryIds);

        final DateTime now = DateTime.now();
        final DateTime elapsedEnd = endDate.isAfter(now) ? now : endDate;
        int elapsedDays = elapsedEnd.difference(effectiveStart).inDays + 1;
        if (elapsedDays < 1) elapsedDays = 1;

        int daysAbsent = elapsedDays - daysPresent - closedDaysCount;
        if (daysAbsent < 0) daysAbsent = 0;

        int totalActiveDays = elapsedDays - closedDaysCount;
        double attendanceRate = totalActiveDays > 0 ? (daysPresent / totalActiveDays) * 100 : 0.0;
        if (attendanceRate > 100.0) attendanceRate = 100.0;

        return {
          'daysPresent': daysPresent,
          'daysAbsent': daysAbsent,
          'totalHours': totalMinutes / 60.0,
          'attendanceRate': attendanceRate,
          'rawAttendance': [],
        };
      }
    } catch (e) {
      debugPrint('member_daily_stats query not available: $e');
    }

    // 2. Fallback: Query raw attendance table and calculate in Dart
    final startStr = startDate.toIso8601String();
    final endStr = endDate.toIso8601String();

    var attendanceQuery = _supabase.from('attendance').select();
    if (libraryId != null && libraryId != 'all') {
      attendanceQuery = attendanceQuery.eq('library_id', libraryId);
    } else if (memberLibraryIds != null && memberLibraryIds.isNotEmpty) {
      attendanceQuery = attendanceQuery.inFilter('library_id', memberLibraryIds);
    }

    final response = await attendanceQuery
        .eq('member_id', memberId)
        .gte('check_in_time', startStr)
        .lte('check_in_time', endStr);

    final List<dynamic> attendanceList = response as List<dynamic>;

    Set<String> presentDays = {};
    double totalMinutes = 0.0;

    for (var record in attendanceList) {
      final sessionType = record['session_type'] as String?;
      final checkOut = record['check_out_time'];
      final duration = record['duration_minutes'] as num?;

      if (checkOut != null || sessionType != 'incomplete') {
        final checkInTimeStr = record['check_in_time'] as String;
        final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.parse(checkInTimeStr).toLocal());
        presentDays.add(dateStr);
      }

      if (sessionType != 'incomplete' && duration != null) {
        totalMinutes += duration.toDouble();
      }
    }

    int daysPresent = presentDays.length;
    int closedDaysCount = await _fetchClosuresCount(libraryId, startDate, endDate, memberLibraryIds: memberLibraryIds);

    final DateTime now = DateTime.now();
    final DateTime elapsedEnd = endDate.isAfter(now) ? now : endDate;
    int elapsedDays = elapsedEnd.difference(effectiveStart).inDays + 1;
    if (elapsedDays < 1) elapsedDays = 1;

    int daysAbsent = elapsedDays - daysPresent - closedDaysCount;
    if (daysAbsent < 0) daysAbsent = 0;

    int totalActiveDays = elapsedDays - closedDaysCount;
    double attendanceRate = totalActiveDays > 0 ? (daysPresent / totalActiveDays) * 100 : 0.0;
    if (attendanceRate > 100.0) attendanceRate = 100.0;

    return {
      'daysPresent': daysPresent,
      'daysAbsent': daysAbsent,
      'totalHours': totalMinutes / 60.0,
      'attendanceRate': attendanceRate,
      'rawAttendance': attendanceList,
    };
  }

  /// Calculates comparison trend range based on selected filter.
  DateTimeRange _getPreviousPeriod(String filter, DateTime start, DateTime end) {
    if (filter == 'today') {
      return DateTimeRange(
        start: start.subtract(const Duration(days: 1)),
        end: end.subtract(const Duration(days: 1)),
      );
    } else if (filter == 'this_week') {
      return DateTimeRange(
        start: start.subtract(const Duration(days: 7)),
        end: end.subtract(const Duration(days: 7)),
      );
    } else if (filter == 'this_month') {
      int prevYear = start.year;
      int prevMonth = start.month - 1;
      if (prevMonth == 0) {
        prevMonth = 12;
        prevYear--;
      }
      DateTime prevStart = DateTime(prevYear, prevMonth, 1);
      
      int lastDayOfPrevMonth = DateTime(prevYear, prevMonth + 1, 0).day;
      int currentOffset = end.day;
      int prevDay = currentOffset > lastDayOfPrevMonth ? lastDayOfPrevMonth : currentOffset;
      DateTime prevEnd = DateTime(prevYear, prevMonth, prevDay, 23, 59, 59);
      
      return DateTimeRange(start: prevStart, end: prevEnd);
    } else {
      return DateTimeRange(start: start, end: end);
    }
  }

  /// Helper to get trend label.
  String _getTrendLabel(String filter) {
    switch (filter) {
      case 'today':
        return 'Today vs Yesterday';
      case 'this_week':
        return 'This Week vs Last Week';
      case 'this_month':
        return 'This Month vs Last Month';
      default:
        return 'All Time';
    }
  }

  // 1. Fetch Analytics Summary with Trend Comparison
  Future<Map<String, dynamic>> fetchAnalyticsSummary(
    String memberId,
    String libraryId,
    DateTime startDate,
    DateTime endDate, {
    String dateFilter = 'this_month',
    List<String>? memberLibraryIds,
  }) async {
    final currentStats = await _calculateStatsForRange(
      memberId: memberId,
      libraryId: libraryId,
      startDate: startDate,
      endDate: endDate,
      memberLibraryIds: memberLibraryIds,
    );

    if (dateFilter == 'all_time') {
      return {
        ...currentStats,
        'prevDaysPresent': currentStats['daysPresent'],
        'prevDaysAbsent': currentStats['daysAbsent'],
        'prevTotalHours': currentStats['totalHours'],
        'prevAttendanceRate': currentStats['attendanceRate'],
        'trendLabel': 'All Time',
      };
    }

    final prevRange = _getPreviousPeriod(dateFilter, startDate, endDate);
    final prevStats = await _calculateStatsForRange(
      memberId: memberId,
      libraryId: libraryId,
      startDate: prevRange.start,
      endDate: prevRange.end,
      memberLibraryIds: memberLibraryIds,
    );

    return {
      ...currentStats,
      'prevDaysPresent': prevStats['daysPresent'],
      'prevDaysAbsent': prevStats['prevDaysAbsent'] ?? prevStats['daysAbsent'],
      'prevTotalHours': prevStats['totalHours'],
      'prevAttendanceRate': prevStats['attendanceRate'],
      'trendLabel': _getTrendLabel(dateFilter),
    };
  }

  // 2. Fetch Leaderboard (Phase 2 Stub / Existing code preserved)
  Future<List<Map<String, dynamic>>> fetchLeaderboard(String libraryId, DateTime startDate, DateTime endDate) async {
    final startStr = startDate.toIso8601String();
    final endStr = endDate.toIso8601String();

    final attendanceRes = await _supabase
        .from('attendance')
        .select('member_id, duration_minutes, users(nickname, full_name)')
        .eq('library_id', libraryId)
        .gte('check_in_time', startStr)
        .lte('check_in_time', endStr)
        .not('duration_minutes', 'is', null);

    Map<String, Map<String, dynamic>> memberStats = {};

    for (var record in attendanceRes) {
      final mId = record['member_id'];
      final duration = record['duration_minutes'] as int;
      final userMap = record['users'] as Map<String, dynamic>?;
      
      if (!memberStats.containsKey(mId)) {
        String name = userMap?['nickname'] ?? userMap?['full_name'] ?? 'User';
        if (userMap?['nickname'] == null && userMap?['full_name'] != null) {
          name = userMap!['full_name'].toString().split(' ').first;
        }
        memberStats[mId] = {
          'member_id': mId,
          'name': name,
          'total_duration': 0,
        };
      }
      memberStats[mId]!['total_duration'] += duration;
    }

    List<Map<String, dynamic>> leaderboard = memberStats.values.toList();
    leaderboard.sort((a, b) => (b['total_duration'] as int).compareTo(a['total_duration'] as int));

    Map<String, int> nameCounts = {};
    for (var entry in leaderboard) {
      String name = entry['name'];
      if (nameCounts.containsKey(name)) {
        nameCounts[name] = nameCounts[name]! + 1;
        entry['display_name'] = '$name (${nameCounts[name]})';
      } else {
        nameCounts[name] = 0;
        entry['display_name'] = name;
      }
    }

    return leaderboard;
  }

  // 3. Streak Calculation
  Future<Map<String, dynamic>> fetchStreak(String memberId, String libraryId) async {
    // 3.1 Attempt to query streaks table
    try {
      final streakRes = await _supabase
          .from('streaks')
          .select('current_streak, longest_streak, last_present_date')
          .eq('member_id', memberId)
          .eq('library_id', libraryId)
          .maybeSingle();

      if (streakRes != null) {
        // Query last 7 days of details
        final last7Days = await _calculateLast7Days(memberId, libraryId);
        return {
          'current': streakRes['current_streak'] ?? 0,
          'best': streakRes['longest_streak'] ?? 0,
          'lastPresentDate': streakRes['last_present_date'],
          'last7Days': last7Days,
        };
      }
    } catch (e) {
      debugPrint('streaks table not available: $e');
    }

    // 3.2 Fallback: Calculate streak and last 7 days in Dart
    final attendanceRes = await _supabase
        .from('attendance')
        .select('check_in_time, check_out_time, session_type')
        .eq('member_id', memberId)
        .eq('library_id', libraryId)
        .order('check_in_time', ascending: false);

    final closuresRes = await _getClosures(libraryId: libraryId);

    Set<String> closedDays = {};
    for (var c in closuresRes) {
      final dateStr = c['closure_date'] ?? c['start_date'] ?? c['date'];
      if (dateStr != null) {
        closedDays.add(dateStr.toString().split('T').first);
      }
    }

    Set<String> attendedDays = {};
    for (var r in attendanceRes) {
      final sessionType = r['session_type'] as String?;
      final checkOut = r['check_out_time'];
      if (checkOut != null || sessionType != 'incomplete') {
        attendedDays.add(DateFormat('yyyy-MM-dd').format(DateTime.parse(r['check_in_time']).toLocal()));
      }
    }

    int currentStreak = 0;
    int bestStreak = 0;

    DateTime today = DateTime.now();
    DateTime ptr = today;

    while (true) {
      String ptrStr = DateFormat('yyyy-MM-dd').format(ptr);
      if (attendedDays.contains(ptrStr)) {
        currentStreak++;
        ptr = ptr.subtract(const Duration(days: 1));
      } else if (closedDays.contains(ptrStr)) {
        ptr = ptr.subtract(const Duration(days: 1));
      } else {
        if (ptrStr == DateFormat('yyyy-MM-dd').format(today)) {
          ptr = ptr.subtract(const Duration(days: 1));
          continue;
        }
        break;
      }
    }

    List<DateTime> allDates = attendedDays.map((e) => DateTime.parse(e)).toList()..sort();
    int tempStreak = 0;
    for (int i = 0; i < allDates.length; i++) {
      if (i == 0) {
        tempStreak = 1;
        bestStreak = 1;
        continue;
      }
      int diff = allDates[i].difference(allDates[i - 1]).inDays;
      if (diff == 1) {
        tempStreak++;
      } else {
        bool allIntermediateClosed = true;
        for (int d = 1; d < diff; d++) {
          String midDay = DateFormat('yyyy-MM-dd').format(allDates[i - 1].add(Duration(days: d)));
          if (!closedDays.contains(midDay)) {
            allIntermediateClosed = false;
            break;
          }
        }
        if (allIntermediateClosed) {
          tempStreak++;
        } else {
          tempStreak = 1;
        }
      }
      if (tempStreak > bestStreak) bestStreak = tempStreak;
    }

    if (currentStreak > bestStreak) bestStreak = currentStreak;

    final last7Days = await _calculateLast7Days(memberId, libraryId);

    return {
      'current': currentStreak,
      'best': bestStreak,
      'last7Days': last7Days,
    };
  }

  /// Calculates status for the current week's 7 days (Monday to Sunday)
  Future<List<Map<String, dynamic>>> _calculateLast7Days(String memberId, String libraryId) async {
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final monday = now.subtract(Duration(days: now.weekday - 1));

    // Fetch this week's attendance
    final startStr = DateTime(monday.year, monday.month, monday.day).toIso8601String();
    final endStr = DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();

    final attendanceRes = await _supabase
        .from('attendance')
        .select('check_in_time, check_out_time, session_type')
        .eq('member_id', memberId)
        .eq('library_id', libraryId)
        .gte('check_in_time', startStr)
        .lte('check_in_time', endStr);

    final closuresRes = await _getClosures(
      libraryId: libraryId,
      startDate: monday,
      endDate: now,
    );

    Set<String> closedDays = {};
    for (var c in closuresRes) {
      final dateStr = c['closure_date'] ?? c['start_date'] ?? c['date'];
      if (dateStr != null) {
        closedDays.add(dateStr.toString().split('T').first);
      }
    }

    Set<String> attendedDays = {};
    Set<String> incompleteDays = {};
    for (var r in attendanceRes) {
      final sessionType = r['session_type'] as String?;
      final checkOut = r['check_out_time'];
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.parse(r['check_in_time']).toLocal());
      if (checkOut != null || sessionType != 'incomplete') {
        attendedDays.add(dateStr);
      } else {
        incompleteDays.add(dateStr);
      }
    }

    List<Map<String, dynamic>> last7Days = [];
    final List<String> dayLabels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

    for (int i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final label = dayLabels[i];

      String status;
      if (dateStr == todayStr) {
        if (attendedDays.contains(dateStr)) {
          status = 'present';
        } else if (incompleteDays.contains(dateStr)) {
          status = 'today_partial';
        } else {
          status = 'today_partial'; // Orange dot for today if not checked in yet
        }
      } else if (date.isAfter(now)) {
        status = 'future';
      } else {
        if (attendedDays.contains(dateStr)) {
          status = 'present';
        } else if (closedDays.contains(dateStr)) {
          status = 'closed';
        } else {
          status = 'absent';
        }
      }

      last7Days.add({
        'dateStr': dateStr,
        'label': label,
        'status': status,
      });
    }

    return last7Days;
  }

  /// Fetches all sessions for a specific date (used by Day Attendance Popup S076)
  Future<List<Map<String, dynamic>>> fetchDaySessions(String memberId, String dateStr) async {
    final date = DateTime.parse(dateStr);
    final startStr = DateTime(date.year, date.month, date.day).toIso8601String();
    final endStr = DateTime(date.year, date.month, date.day, 23, 59, 59).toIso8601String();

    final response = await _supabase
        .from('attendance')
        .select('*, libraries(name), shifts(name)')
        .eq('member_id', memberId)
        .gte('check_in_time', startStr)
        .lte('check_in_time', endStr)
        .order('check_in_time', ascending: true);

    final List<dynamic> list = response as List<dynamic>;
    return list.map((item) {
      final checkIn = DateTime.parse(item['check_in_time']).toLocal();
      final checkOut = item['check_out_time'] != null ? DateTime.parse(item['check_out_time']).toLocal() : null;
      return {
        'id': item['id'],
        'check_in': DateFormat('hh:mm a').format(checkIn),
        'check_out': checkOut != null ? DateFormat('hh:mm a').format(checkOut) : 'Active',
        'duration_minutes': item['duration_minutes'] ?? 0,
        'session_type': item['session_type'] ?? 'normal',
        'library_name': item['libraries']?['name'] ?? 'SILENCE Study Zone',
        'seat': item['seat_label'] ?? item['seat_id'] ?? 'N/A',
        'shift': item['shifts']?['name'] ?? 'N/A',
      };
    }).toList();
  }

  // 4. Badges Sync
  Future<List<Map<String, dynamic>>> syncAndFetchBadges(String memberId, String libraryId) async {
    List<dynamic> existingBadges;
    try {
      existingBadges = await _supabase.from('badges').select().eq('member_id', memberId);
    } catch (e) {
      debugPrint('badges table not available: $e');
      return [];
    }
    Set<String> earnedTypes = existingBadges.map((b) => b['badge_type'] as String).toSet();

    final streak = await fetchStreak(memberId, libraryId);
    
    // 1. 7-day streak
    if (!earnedTypes.contains('7_day_streak') && (streak['best'] ?? 0) >= 7) {
      await _awardBadge(memberId, libraryId, '7_day_streak');
      earnedTypes.add('7_day_streak');
    }
    // 2. 30-day streak
    if (!earnedTypes.contains('30_day_streak') && (streak['best'] ?? 0) >= 30) {
      await _awardBadge(memberId, libraryId, '30_day_streak');
      earnedTypes.add('30_day_streak');
    }
    // 3. 100 days club
    if (!earnedTypes.contains('100_days_club')) {
      final totalDaysRes = await _supabase.from('attendance').select('id').eq('member_id', memberId);
      final Set<String> uniqueDays = {};
      for (var r in totalDaysRes) {
        if (r['check_in_time'] != null) {
          uniqueDays.add(DateFormat('yyyy-MM-dd').format(DateTime.parse(r['check_in_time'] as String).toLocal()));
        }
      }
      if (uniqueDays.length >= 100) {
        await _awardBadge(memberId, libraryId, '100_days_club');
        earnedTypes.add('100_days_club');
      }
    }
    // 4 & 5. Early bird and night owl
    if (!earnedTypes.contains('early_bird') || !earnedTypes.contains('night_owl')) {
      final timesRes = await _supabase.from('attendance').select('check_in_time').eq('member_id', memberId);
      int earlyCount = 0;
      int nightCount = 0;
      for (var r in timesRes) {
        DateTime dt = DateTime.parse(r['check_in_time']).toLocal();
        if (dt.hour < 7) earlyCount++;
        if (dt.hour >= 20) nightCount++;
      }
      if (!earnedTypes.contains('early_bird') && earlyCount >= 5) {
        await _awardBadge(memberId, libraryId, 'early_bird');
        earnedTypes.add('early_bird');
      }
      if (!earnedTypes.contains('night_owl') && nightCount >= 5) {
        await _awardBadge(memberId, libraryId, 'night_owl');
        earnedTypes.add('night_owl');
      }
    }
    // 6. Consistent (90%+ attendance rate in any calendar month)
    if (!earnedTypes.contains('consistent')) {
      try {
        final now = DateTime.now();
        // Check last 6 months
        for (int m = 0; m < 6; m++) {
          final checkMonth = DateTime(now.year, now.month - m, 1);
          final monthEnd = DateTime(checkMonth.year, checkMonth.month + 1, 0, 23, 59, 59);
          final effectiveEnd = monthEnd.isAfter(now) ? now : monthEnd;
          final stats = await _calculateStatsForRange(
            memberId: memberId,
            libraryId: libraryId,
            startDate: checkMonth,
            endDate: effectiveEnd,
          );
          final rate = (stats['attendanceRate'] as num?)?.toDouble() ?? 0.0;
          final daysPresent = (stats['daysPresent'] as int?) ?? 0;
          if (rate >= 90.0 && daysPresent >= 10) {
            await _awardBadge(memberId, libraryId, 'consistent');
            earnedTypes.add('consistent');
            break;
          }
        }
      } catch (e) {
        debugPrint('Error checking consistent badge: $e');
      }
    }
    // 7. Top of week (ranked #1 on leaderboard any week)
    if (!earnedTypes.contains('top_of_week')) {
      try {
        final now = DateTime.now();
        // Check current and last 3 weeks
        for (int w = 0; w < 4; w++) {
          final weekStart = now.subtract(Duration(days: now.weekday - 1 + (w * 7)));
          final weekEnd = weekStart.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
          final lbDetails = await fetchLeaderboardDetails(
            libraryId,
            memberId,
            DateTime(weekStart.year, weekStart.month, weekStart.day),
            DateTime(weekEnd.year, weekEnd.month, weekEnd.day, 23, 59, 59),
          );
          final rank = lbDetails['currentUserRank'] as int?;
          if (rank == 1) {
            await _awardBadge(memberId, libraryId, 'top_of_week');
            earnedTypes.add('top_of_week');
            break;
          }
        }
      } catch (e) {
        debugPrint('Error checking top_of_week badge: $e');
      }
    }

    // Return all badges for this member
    try {
      return List<Map<String, dynamic>>.from(
        await _supabase.from('badges').select().eq('member_id', memberId),
      );
    } catch (e) {
      debugPrint('Error fetching badges: $e');
      return [];
    }
  }

  Future<void> _awardBadge(String memberId, String libraryId, String badgeType) async {
    try {
      await _supabase.from('badges').insert({
        'member_id': memberId,
        'library_id': libraryId,
        'badge_type': badgeType,
      });
      await _supabase.from('notifications').insert({
        'user_id': memberId,
        'title': 'New Badge Earned!',
        'body': 'You just unlocked the $badgeType badge. Keep it up!',
      });
    } catch (_) {}
  }

  // 5. Referrals (Existing preserved)
  Future<Map<String, dynamic>> fetchReferralStats(String memberId) async {
    final res = await _supabase.from('referrals').select().eq('referrer_member_id', memberId);
    int total = res.length;
    int pending = 0;
    int credited = 0;
    for (var r in res) {
      if (r['status'] == 'pending') pending++;
      if (r['status'] == 'credited') credited++;
    }
    return {'total': total, 'pending': pending, 'credited': credited};
  }

  // 6. Upgraded Leaderboard Details (Phase 2)
  Future<Map<String, dynamic>> fetchLeaderboardDetails(String libraryId, String currentMemberId, DateTime startDate, DateTime endDate) async {
    final startStr = startDate.toIso8601String();
    final endStr = endDate.toIso8601String();

    final attendanceRes = await _supabase
        .from('attendance')
        .select('member_id, duration_minutes, users(id, nickname, full_name)')
        .eq('library_id', libraryId)
        .gte('check_in_time', startStr)
        .lte('check_in_time', endStr)
        .not('duration_minutes', 'is', null);

    Map<String, Map<String, dynamic>> memberStats = {};

    for (var record in attendanceRes) {
      final mId = record['member_id'];
      final duration = record['duration_minutes'] as int;
      final userMap = record['users'] as Map<String, dynamic>?;
      if (userMap == null) continue;

      if (!memberStats.containsKey(mId)) {
        String name = userMap['nickname'] ?? userMap['full_name'] ?? 'User';
        if (userMap['nickname'] == null && userMap['full_name'] != null) {
          name = userMap['full_name'].toString().split(' ').first;
        }
        
        // Privacy format: "Priya S."
        if (name.contains(' ')) {
          final parts = name.split(' ');
          name = '${parts.first} ${parts.last[0]}.';
        } else if (name.length > 8) {
          name = '${name.substring(0, 7)}...';
        }

        memberStats[mId] = {
          'member_id': mId,
          'name': name,
          'total_duration': 0,
        };
      }
      memberStats[mId]!['total_duration'] += duration;
    }

    List<Map<String, dynamic>> leaderboard = memberStats.values.toList();
    leaderboard.sort((a, b) => (b['total_duration'] as int).compareTo(a['total_duration'] as int));

    List<Map<String, dynamic>> rankedList = [];
    int currentRank = 1;
    for (int i = 0; i < leaderboard.length; i++) {
      final item = leaderboard[i];
      if (i > 0 && item['total_duration'] < leaderboard[i - 1]['total_duration']) {
        currentRank = i + 1;
      }
      rankedList.add({
        'rank': currentRank,
        'member_id': item['member_id'],
        'name': item['name'],
        'hours': item['total_duration'] / 60.0,
      });
    }

    int userRankIndex = rankedList.indexWhere((e) => e['member_id'] == currentMemberId);
    Map<String, dynamic>? currentUserRow;
    int? currentUserRank;
    double gapToTop5 = 0.0;

    if (userRankIndex != -1) {
      currentUserRow = rankedList[userRankIndex];
      currentUserRank = currentUserRow['rank'];
    }

    if (rankedList.length >= 5) {
      final double hours5th = rankedList[4]['hours'] as double;
      final double myHours = currentUserRow != null ? (currentUserRow['hours'] as double) : 0.0;
      if (myHours < hours5th) {
        gapToTop5 = hours5th - myHours;
      }
    }

    return {
      'leaderboard': rankedList.take(5).toList(),
      'currentUserRow': currentUserRow,
      'currentUserRank': currentUserRank,
      'gapToTop5': gapToTop5,
      'totalMembersCount': rankedList.length,
    };
  }

  // 7. Fetch Daily Study Hours (Phase 2)
  Future<Map<String, dynamic>> fetchDailyStudyHours({
    required String memberId,
    required String libraryId,
    required DateTime startDate,
    required DateTime endDate,
    required String dateFilter,
    List<String>? memberLibraryIds,
  }) async {
    var query = _supabase.from('attendance').select();
    if (libraryId != 'all') {
      query = query.eq('library_id', libraryId);
    } else if (memberLibraryIds != null && memberLibraryIds.isNotEmpty) {
      query = query.inFilter('library_id', memberLibraryIds);
    }

    final startStr = startDate.toIso8601String();
    final endStr = endDate.toIso8601String();

    final attendanceRes = await query
        .eq('member_id', memberId)
        .gte('check_in_time', startStr)
        .lte('check_in_time', endStr);

    final List<dynamic> attendanceList = attendanceRes as List<dynamic>;

    Map<String, Map<String, double>> grouped = {}; // key -> { library_id: hours }
    List<Map<String, dynamic>> chartData = [];
    
    if (dateFilter == 'today') {
      final dateStr = DateFormat('yyyy-MM-dd').format(startDate);
      grouped[dateStr] = {};
      chartData.add({
        'label': DateFormat('EEEE').format(startDate),
        'dateStr': dateStr,
        'hours_by_library': grouped[dateStr]!,
      });
    } else if (dateFilter == 'this_week') {
      final List<String> weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      for (int i = 0; i < 7; i++) {
        final date = startDate.add(Duration(days: i));
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        grouped[dateStr] = {};
        chartData.add({
          'label': weekdays[i],
          'dateStr': dateStr,
          'hours_by_library': grouped[dateStr]!,
        });
      }
    } else if (dateFilter == 'this_month') {
      int daysInMonth = endDate.difference(startDate).inDays + 1;
      for (int i = 0; i < daysInMonth; i++) {
        final date = startDate.add(Duration(days: i));
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        grouped[dateStr] = {};
        chartData.add({
          'label': '${date.day}',
          'dateStr': dateStr,
          'hours_by_library': grouped[dateStr]!,
        });
      }
    } else {
      DateTime ptr = DateTime(startDate.year, startDate.month, 1);
      while (ptr.isBefore(endDate) || (ptr.year == endDate.year && ptr.month == endDate.month)) {
        final monthStr = DateFormat('yyyy-MM').format(ptr);
        grouped[monthStr] = {};
        chartData.add({
          'label': DateFormat('MMM').format(ptr),
          'dateStr': monthStr,
          'hours_by_library': grouped[monthStr]!,
        });
        ptr = DateTime(ptr.year, ptr.month + 1, 1);
      }
    }

    for (var record in attendanceList) {
      final sessionType = record['session_type'] as String?;
      if (sessionType == 'incomplete') continue;

      final checkInTimeStr = record['check_in_time'] as String;
      final checkIn = DateTime.parse(checkInTimeStr).toLocal();
      final libId = record['library_id'] as String;
      final durationMins = (record['duration_minutes'] as num?)?.toDouble() ?? 0.0;
      final double hours = durationMins / 60.0;

      String key;
      if (dateFilter == 'all_time') {
        key = DateFormat('yyyy-MM').format(checkIn);
      } else {
        key = DateFormat('yyyy-MM-dd').format(checkIn);
      }

      if (grouped.containsKey(key)) {
        grouped[key]![libId] = (grouped[key]![libId] ?? 0.0) + hours;
      }
    }

    double maxHours = 0.0;
    double minHours = double.infinity;
    String? bestDayStr;
    String? weakestDayStr;

    for (var item in chartData) {
      final dateStr = item['dateStr'] as String;
      final hoursMap = item['hours_by_library'] as Map<String, double>;
      double totalDayHours = hoursMap.values.fold(0.0, (a, b) => a + b);

      if (totalDayHours > 0.0) {
        if (totalDayHours > maxHours) {
          maxHours = totalDayHours;
          if (dateFilter == 'all_time') {
            final date = DateFormat('yyyy-MM').parse(dateStr);
            bestDayStr = DateFormat('MMMM yyyy').format(date);
          } else {
            final date = DateFormat('yyyy-MM-dd').parse(dateStr);
            bestDayStr = DateFormat('EEEE').format(date);
          }
        }

        if (totalDayHours < minHours) {
          minHours = totalDayHours;
          if (dateFilter == 'all_time') {
            final date = DateFormat('yyyy-MM').parse(dateStr);
            weakestDayStr = DateFormat('MMMM yyyy').format(date);
          } else {
            final date = DateFormat('yyyy-MM-dd').parse(dateStr);
            weakestDayStr = DateFormat('EEEE').format(date);
          }
        }
      }
    }

    String formatDurationText(double hours) {
      final int hrs = hours.floor();
      final int mins = ((hours - hrs) * 60).round();
      if (hrs > 0) {
        return '${hrs}h ${mins}m';
      } else {
        return '${mins}m';
      }
    }

    String? bestDayText = bestDayStr != null ? '$bestDayStr ${formatDurationText(maxHours)}' : null;
    String? weakestDayText = weakestDayStr != null && minHours != double.infinity ? '$weakestDayStr ${formatDurationText(minHours)}' : null;

    return {
      'chartData': chartData,
      'bestDayText': bestDayText,
      'weakestDayText': weakestDayText,
    };
  }

  // 8. Fetch Activity Heatmap (Phase 2)
  Future<Map<String, dynamic>> fetchActivityHeatmap({
    required String memberId,
    required String libraryId,
    required DateTime startDate,
    required DateTime endDate,
    List<String>? memberLibraryIds,
  }) async {
    var attQuery = _supabase.from('attendance').select();
    if (libraryId != 'all') {
      attQuery = attQuery.eq('library_id', libraryId);
    } else if (memberLibraryIds != null && memberLibraryIds.isNotEmpty) {
      attQuery = attQuery.inFilter('library_id', memberLibraryIds);
    }

    final startStr = startDate.toIso8601String();
    final endStr = endDate.toIso8601String();

    final attendanceRes = await attQuery
        .eq('member_id', memberId)
        .gte('check_in_time', startStr)
        .lte('check_in_time', endStr);

    final List<dynamic> attendanceList = attendanceRes as List<dynamic>;

    final closureList = await _getClosures(
      libraryId: libraryId == 'all' ? null : libraryId,
      memberLibraryIds: memberLibraryIds,
      startDate: startDate,
      endDate: endDate,
    );

    Map<String, String> closures = {};
    for (var c in closureList) {
      final dateStr = c['closure_date'] ?? c['start_date'] ?? c['date'];
      if (dateStr != null) {
        closures[dateStr.toString().split('T').first] = c['reason'] ?? 'Closed';
      }
    }

    Map<String, double> attendance = {};
    for (var r in attendanceList) {
      final sessionType = r['session_type'] as String?;
      if (sessionType == 'incomplete') continue;

      final checkInTimeStr = r['check_in_time'] as String;
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.parse(checkInTimeStr).toLocal());
      final durationMins = (r['duration_minutes'] as num?)?.toDouble() ?? 0.0;
      final double hours = durationMins / 60.0;

      attendance[dateStr] = (attendance[dateStr] ?? 0.0) + hours;
    }

    Map<String, Map<String, dynamic>> heatmapData = {};
    
    closures.forEach((dateStr, reason) {
      heatmapData[dateStr] = {
        'hours': 0.0,
        'is_closed': true,
        'reason': reason,
      };
    });

    attendance.forEach((dateStr, hours) {
      if (heatmapData.containsKey(dateStr)) {
        heatmapData[dateStr]!['hours'] = hours;
      } else {
        heatmapData[dateStr] = {
          'hours': hours,
          'is_closed': false,
          'reason': null,
        };
      }
    });

    return heatmapData;
  }

  // 9. Fetch Attendance for CSV Export
  Future<List<Map<String, dynamic>>> fetchAttendanceForExport({
    required String memberId,
    required String libraryId,
    required DateTime startDate,
    required DateTime endDate,
    List<String>? memberLibraryIds,
  }) async {
    var query = _supabase.from('attendance').select('*, libraries(name), shifts(name)');
    if (libraryId != 'all') {
      query = query.eq('library_id', libraryId);
    } else if (memberLibraryIds != null && memberLibraryIds.isNotEmpty) {
      query = query.inFilter('library_id', memberLibraryIds);
    }

    final response = await query
        .eq('member_id', memberId)
        .gte('check_in_time', startDate.toIso8601String())
        .lte('check_in_time', endDate.toIso8601String())
        .order('check_in_time', ascending: true);

    final List<dynamic> list = response as List<dynamic>;
    return list.map((item) {
      final checkIn = DateTime.parse(item['check_in_time']).toLocal();
      final checkOut = item['check_out_time'] != null
          ? DateTime.parse(item['check_out_time']).toLocal()
          : null;

      final durationMins = item['duration_minutes'] as int? ?? 0;
      final hrs = durationMins ~/ 60;
      final mins = durationMins % 60;
      final durationStr = hrs > 0 ? '${hrs}h ${mins}m' : '${mins}m';

      return {
        'date': DateFormat('dd MMM yyyy').format(checkIn),
        'check_in': DateFormat('hh:mm a').format(checkIn),
        'check_out': checkOut != null ? DateFormat('hh:mm a').format(checkOut) : 'Active',
        'duration': durationStr,
        'session_type': (item['session_type'] ?? 'normal').toString(),
        'library': item['libraries']?['name'] ?? 'Library',
        'seat': item['seat_label'] ?? item['seat_id'] ?? 'N/A',
      };
    }).toList();
  }
}

