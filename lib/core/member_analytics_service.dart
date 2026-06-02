import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class MemberAnalyticsService {
  static final MemberAnalyticsService instance = MemberAnalyticsService._init();
  MemberAnalyticsService._init();

  final _supabase = Supabase.instance.client;

  // 1. Fetch Analytics Summary
  Future<Map<String, dynamic>> fetchAnalyticsSummary(String memberId, String libraryId, DateTime startDate, DateTime endDate) async {
    final startStr = startDate.toIso8601String();
    final endStr = endDate.toIso8601String();

    final response = await _supabase
        .from('attendance')
        .select()
        .eq('member_id', memberId)
        .eq('library_id', libraryId)
        .gte('check_in_time', startStr)
        .lte('check_in_time', endStr);

    final List<dynamic> attendanceList = response as List<dynamic>;
    
    int daysPresent = 0;
    int totalHours = 0;
    Set<String> uniqueDays = {};

    for (var record in attendanceList) {
      if (record['check_out_time'] != null && record['duration_minutes'] != null) {
        totalHours += ((record['duration_minutes'] as int) / 60).floor();
        final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.parse(record['check_in_time']));
        uniqueDays.add(dateStr);
      }
    }

    daysPresent = uniqueDays.length;
    int totalDays = endDate.difference(startDate).inDays + 1;
    if (totalDays <= 0) totalDays = 1;
    
    int daysAbsent = totalDays - daysPresent;
    if (daysAbsent < 0) daysAbsent = 0;
    
    double attendanceRate = (daysPresent / totalDays) * 100;

    return {
      'daysPresent': daysPresent,
      'daysAbsent': daysAbsent,
      'totalHours': totalHours,
      'attendanceRate': attendanceRate,
      'rawAttendance': attendanceList, // Used for bar chart/heatmap later
    };
  }

  // 2. Fetch Leaderboard
  Future<List<Map<String, dynamic>>> fetchLeaderboard(String libraryId, DateTime startDate, DateTime endDate) async {
    final startStr = startDate.toIso8601String();
    final endStr = endDate.toIso8601String();

    // Query attendance within range, then group by member ID manually since we don't have an RPC
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

    // Append duplicates suffix (e.g. Rahul (1), Rahul (2))
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
  Future<Map<String, int>> fetchStreak(String memberId, String libraryId) async {
    // A real production app would calculate this daily via cron.
    // Client-side approximation:
    final attendanceRes = await _supabase
        .from('attendance')
        .select('check_in_time')
        .eq('member_id', memberId)
        .eq('library_id', libraryId)
        .order('check_in_time', ascending: false);

    if (attendanceRes.isEmpty) {
      return {'current': 0, 'best': 0};
    }

    final closuresRes = await _supabase
        .from('scheduled_closures')
        .select('start_date, end_date')
        .eq('library_id', libraryId);

    // Flatten closures into a Set of strings (yyyy-MM-dd)
    Set<String> closedDays = {};
    for (var c in closuresRes) {
      DateTime start = DateTime.parse(c['start_date']);
      DateTime end = DateTime.parse(c['end_date']);
      for (int i = 0; i <= end.difference(start).inDays; i++) {
        closedDays.add(DateFormat('yyyy-MM-dd').format(start.add(Duration(days: i))));
      }
    }

    Set<String> attendedDays = {};
    for (var r in attendanceRes) {
      attendedDays.add(DateFormat('yyyy-MM-dd').format(DateTime.parse(r['check_in_time'])));
    }

    int currentStreak = 0;
    int bestStreak = 0;
    
    DateTime today = DateTime.now();
    DateTime ptr = today;

    // Current Streak logic
    while (true) {
      String ptrStr = DateFormat('yyyy-MM-dd').format(ptr);
      if (attendedDays.contains(ptrStr)) {
        currentStreak++;
        ptr = ptr.subtract(const Duration(days: 1));
      } else if (closedDays.contains(ptrStr)) {
        // Freeze streak, skip day
        ptr = ptr.subtract(const Duration(days: 1));
      } else {
        // Missed day.
        // Wait, if today is missed but yesterday was attended, streak might still be alive?
        // Usually, streak is alive if you attended today OR yesterday.
        if (ptrStr == DateFormat('yyyy-MM-dd').format(today)) {
           ptr = ptr.subtract(const Duration(days: 1));
           continue; // Allow missing today since day isn't over
        }
        break;
      }
    }

    // Best Streak logic (full scan)
    // Convert all attended days to DateTimes
    List<DateTime> allDates = attendedDays.map((e) => DateTime.parse(e)).toList()..sort();
    int tempStreak = 0;
    for (int i = 0; i < allDates.length; i++) {
      if (i == 0) {
        tempStreak = 1;
        bestStreak = 1;
        continue;
      }
      int diff = allDates[i].difference(allDates[i-1]).inDays;
      if (diff == 1) {
        tempStreak++;
      } else {
        // Check if intermediate days were closed
        bool allIntermediateClosed = true;
        for (int d = 1; d < diff; d++) {
          String midDay = DateFormat('yyyy-MM-dd').format(allDates[i-1].add(Duration(days: d)));
          if (!closedDays.contains(midDay)) {
            allIntermediateClosed = false;
            break;
          }
        }
        if (allIntermediateClosed) {
          tempStreak++; // Keep streak alive through closed days
        } else {
          tempStreak = 1;
        }
      }
      if (tempStreak > bestStreak) bestStreak = tempStreak;
    }

    if (currentStreak > bestStreak) bestStreak = currentStreak;

    return {'current': currentStreak, 'best': bestStreak};
  }

  // 4. Badges Sync
  Future<List<Map<String, dynamic>>> syncAndFetchBadges(String memberId, String libraryId) async {
    // Fetch currently earned badges
    final existingBadges = await _supabase.from('badges').select().eq('member_id', memberId);
    Set<String> earnedTypes = existingBadges.map((b) => b['badge_type'] as String).toSet();

    // Re-evaluate unearned badges
    final streak = await fetchStreak(memberId, libraryId);
    
    // Evaluate 7 day
    if (!earnedTypes.contains('7_day_streak') && streak['best']! >= 7) {
      await _awardBadge(memberId, libraryId, '7_day_streak');
      earnedTypes.add('7_day_streak');
    }
    // Evaluate 30 day
    if (!earnedTypes.contains('30_day_streak') && streak['best']! >= 30) {
      await _awardBadge(memberId, libraryId, '30_day_streak');
      earnedTypes.add('30_day_streak');
    }
    // Evaluate 100 days club
    if (!earnedTypes.contains('100_days_club')) {
      final totalDaysRes = await _supabase.from('attendance').select('id').eq('member_id', memberId);
      if (totalDaysRes.length >= 100) {
        await _awardBadge(memberId, libraryId, '100_days_club');
        earnedTypes.add('100_days_club');
      }
    }
    // Early Bird & Night Owl
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

    // Return fresh list
    return await _supabase.from('badges').select().eq('member_id', memberId);
  }

  Future<void> _awardBadge(String memberId, String libraryId, String badgeType) async {
    try {
      await _supabase.from('badges').insert({
        'member_id': memberId,
        'library_id': libraryId,
        'badge_type': badgeType,
      });
      // Optionally insert notification here
      await _supabase.from('notifications').insert({
        'user_id': memberId,
        'title': 'New Badge Earned!',
        'body': 'You just unlocked the $badgeType badge. Keep it up!',
      });
    } catch (e) {
      // ignore duplicate conflicts
    }
  }

  // 5. Referrals
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
}
