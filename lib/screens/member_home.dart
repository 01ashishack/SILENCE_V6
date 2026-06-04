import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import '../core/offline_sync.dart';
import '../core/cache_service.dart';
import 'reservations/qr_scanner_screen.dart';
import 'reservations/join_flow_screen.dart';
import 'member_profile_edit.dart';
import 'member_analytics_tab.dart';
import 'library_public_profile_screen.dart';
import 'member_history_tab.dart';
import 'help_support_screen.dart';
import 'about_us_screen.dart';
import 'terms_screen.dart';
import 'app_settings_screen.dart';
import 'package:flutter/services.dart';
import '../core/calendar_picker.dart';
import '../widgets/seat_change_bottom_sheet.dart';
import 'member_explore_screen.dart';

enum MemberState { fresh, profileCompleteNoLib, activeMember, returning }

class MemberHomeScreen extends StatefulWidget {
  const MemberHomeScreen({super.key});

  @override
  State<MemberHomeScreen> createState() => _MemberHomeScreenState();
}

class _MemberHomeScreenState extends State<MemberHomeScreen> with SingleTickerProviderStateMixin {
  int _currentBottomTab = 0; // 0 = Home, 1 = Analytics, 2 = History, 3 = Profile
  
  bool _isLoading = true;
  String? _errorMessage;

  // Domain data
  Map<String, dynamic>? _userProfile;
  List<Map<String, dynamic>> _myMemberships = [];
  List<Map<String, dynamic>> _pastMemberships = [];
  List<Map<String, dynamic>> _announcements = [];
  Set<String> _readAnnouncementIds = {};
  Map<String, dynamic>? _activeAttendance;
  Map<String, dynamic>? _lastCompletedAttendance;
  
  // Location
  bool _hasRequestedLocation = false;
  Position? _currentPosition;
  
  // Explore list in cache
  List<Map<String, dynamic>> _exploreLibraries = [];
  
  // Attendance Live Ticker
  Timer? _attendanceTimer;
  String _liveSessionDuration = '0h 0m 0s';

  // Computed Stage Stats
  int _currentStreak = 0;
  int _bestStreak = 0;
  double _totalStudyHours = 0;
  int _daysPresent = 0;
  List<Map<String, dynamic>> _streakLast7Days = [];
  List<Map<String, dynamic>> _recentActivities = [];

  @override
  void initState() {
    super.initState();
    _loadCachedLibraries();
    _loadInitialData();
    _requestLocation();
    
    // Start listening for internet status to sync offline scans
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OfflineSyncManager.instance.startListening(context);
    });
  }

  @override
  void dispose() {
    _attendanceTimer?.cancel();
    OfflineSyncManager.instance.stopListening();
    super.dispose();
  }

  Future<void> _loadCachedLibraries() async {
    try {
      final cached = await CacheService.instance.readCache('explore_libraries_list');
      if (cached != null && cached is List) {
        if (mounted) {
          setState(() {
            _exploreLibraries = List<Map<String, dynamic>>.from(cached);
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _requestLocation() async {
    if (_hasRequestedLocation) return;
    _hasRequestedLocation = true;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 3),
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        throw Exception('No logged in user found.');
      }

      // 1. Load User Profile
      final profileRes = await supabase
          .from('users')
          .select()
          .eq('id', currentUser.id)
          .maybeSingle();
      
      _userProfile = profileRes;

      if (_userProfile == null) {
        final email = currentUser.email ?? '';
        final name = email.split('@').first;
        final newProfile = {
          'id': currentUser.id,
          'email': email,
          'full_name': name,
          'role': 'member',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        };
        await supabase.from('users').insert(newProfile);
        _userProfile = newProfile;
      }

      // 2. Load all memberships
      final membershipsRes = await supabase
          .from('memberships')
          .select('*, libraries(*), shifts(*), seats(*)')
          .eq('member_id', currentUser.id)
          .order('created_at', ascending: false);

      final allMemberships = List<Map<String, dynamic>>.from(membershipsRes);
      
      // Filter memberships
      _myMemberships = allMemberships.where((m) => ['active', 'trial', 'pending', 'hold'].contains(m['status'])).toList();
      _pastMemberships = allMemberships.where((m) => ['exited', 'expired'].contains(m['status'])).toList();

      // 3. Load Active Attendance (if checked in)
      final attendanceRes = await supabase
          .from('attendance')
          .select('*, memberships(*), shifts(*), libraries(*)')
          .eq('member_id', currentUser.id)
          .isFilter('check_out_time', null)
          .order('check_in_time', ascending: false)
          .limit(1)
          .maybeSingle();

      _activeAttendance = attendanceRes;
      final checkInStr = _activeAttendance?['check_in_time'] as String?;
      if (checkInStr != null) {
        _startAttendanceTicker(DateTime.parse(checkInStr));
      } else {
        _attendanceTimer?.cancel();
        _liveSessionDuration = '0h 0m 0s';
      }

      // Load last completed attendance
      final lastCompletedRes = await supabase
          .from('attendance')
          .select('*, libraries(name)')
          .eq('member_id', currentUser.id)
          .not('check_out_time', 'is', null)
          .order('check_in_time', ascending: false)
          .limit(1)
          .maybeSingle();
      _lastCompletedAttendance = lastCompletedRes;

      // 4. Load Announcements for my joined libraries
      final joinedLibIds = allMemberships
          .map((m) => m['library_id'] as String)
          .toSet()
          .toList();

      if (joinedLibIds.isNotEmpty) {
        final announcementsRes = await supabase
            .from('announcements')
            .select('*, libraries(name)')
            .inFilter('library_id', joinedLibIds)
            .order('sent_at', ascending: false)
            .limit(5);

        _announcements = List<Map<String, dynamic>>.from(announcementsRes);

        final readsRes = await supabase
            .from('announcement_reads')
            .select('announcement_id')
            .eq('member_id', currentUser.id);
        
        _readAnnouncementIds = (readsRes as List)
            .map((r) => r['announcement_id'] as String)
            .toSet();
      } else {
        _announcements = [];
        _readAnnouncementIds = {};
      }

      // 5. Load Explore Libraries (All active libraries)
      try {
        final exploreRes = await supabase
            .from('libraries')
            .select('id, name, address_city, address_street, verified, photos, amenities, library_code, status, latitude, longitude, shifts(id, name, price_monthly, trial_days, start_time, end_time), reviews(rating)')
            .eq('status', 'active');

        _exploreLibraries = List<Map<String, dynamic>>.from(exploreRes);
      } catch (e) {
        debugPrint('Error loading libraries explore: $e');
        try {
          final exploreRes = await supabase
              .from('libraries')
              .select('id, name, address_city, verified, photos, amenities, library_code, status, shifts(id, name, price_monthly, trial_days, start_time, end_time)')
              .eq('status', 'active');
          _exploreLibraries = List<Map<String, dynamic>>.from(exploreRes);
        } catch (_) {}
      }
      CacheService.instance.writeCache('explore_libraries_list', _exploreLibraries);

      // 6. Calculate Streak and Trophy Stats from full history
      final allAttendanceRes = await supabase
          .from('attendance')
          .select('check_in_time, check_out_time')
          .eq('member_id', currentUser.id)
          .order('check_in_time', ascending: false);
      
      final allAttendance = List<Map<String, dynamic>>.from(allAttendanceRes);
      Set<String> studyDates = {};
      double hoursSum = 0;
      for (var a in allAttendance) {
        final checkIn = a['check_in_time'] as String?;
        final checkOut = a['check_out_time'] as String?;
        if (checkIn != null) {
          final localIn = DateTime.parse(checkIn).toLocal();
          studyDates.add(DateFormat('yyyy-MM-dd').format(localIn));
          if (checkOut != null) {
            final localOut = DateTime.parse(checkOut).toLocal();
            hoursSum += localOut.difference(localIn).inMinutes / 60.0;
          }
        }
      }
      _currentStreak = _calculateCurrentStreak(studyDates);
      _bestStreak = _calculateBestStreak(studyDates);
      _totalStudyHours = hoursSum;
      _daysPresent = studyDates.length;
      _streakLast7Days = _getLast7DaysAttendance(studyDates);

      // 7. Recent Activities Timeline
      final activityFutures = await Future.wait([
        supabase.from('attendance').select('check_in_time, check_out_time, libraries(name)').eq('member_id', currentUser.id).order('check_in_time', ascending: false).limit(5),
        supabase.from('payments').select('payment_date, amount, status, libraries(name)').eq('member_id', currentUser.id).order('payment_date', ascending: false).limit(5),
        supabase.from('seat_change_requests').select('created_at, status, reason, libraries(name)').eq('member_id', currentUser.id).order('created_at', ascending: false).limit(5),
        supabase.from('hold_requests').select('created_at, status, start_date, end_date, libraries(name)').eq('member_id', currentUser.id).order('created_at', ascending: false).limit(5),
      ]);

      List<Map<String, dynamic>> activities = [];
      // Attendance check-ins/outs
      final attList = List<Map<String, dynamic>>.from(activityFutures[0]);
      for (var a in attList) {
        final libName = a['libraries']?['name'] ?? 'Library';
        if (a['check_in_time'] != null) {
          activities.add({
            'time': DateTime.parse(a['check_in_time']),
            'action': 'Checked In',
            'details': 'Started study session',
            'location': libName,
            'color': const Color(0xFF22C55E),
          });
        }
        if (a['check_out_time'] != null) {
          activities.add({
            'time': DateTime.parse(a['check_out_time']),
            'action': 'Checked Out',
            'details': 'Completed study session',
            'location': libName,
            'color': const Color(0xFF64748B),
          });
        }
      }

      // Payments
      final payList = List<Map<String, dynamic>>.from(activityFutures[1]);
      for (var p in payList) {
        final libName = p['libraries']?['name'] ?? 'Library';
        final status = p['status'] ?? 'pending';
        activities.add({
          'time': DateTime.parse(p['payment_date'] ?? DateTime.now().toIso8601String()),
          'action': 'Payment of ₹${p['amount']}',
          'details': 'Status: ${status.toString().toUpperCase()}',
          'location': libName,
          'color': status == 'confirmed' ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
        });
      }

      // Seat Changes
      final scList = List<Map<String, dynamic>>.from(activityFutures[2]);
      for (var scr in scList) {
        final libName = scr['libraries']?['name'] ?? 'Library';
        final status = scr['status'] ?? 'pending';
        activities.add({
          'time': DateTime.parse(scr['created_at']),
          'action': 'Seat Change Request',
          'details': 'Status: ${status.toString().toUpperCase()}',
          'location': libName,
          'color': status == 'approved' ? const Color(0xFF22C55E) : (status == 'rejected' ? const Color(0xFFEF4444) : const Color(0xFF3B82F6)),
        });
      }

      // Hold/Pauses
      final hdList = List<Map<String, dynamic>>.from(activityFutures[3]);
      for (var hr in hdList) {
        final libName = hr['libraries']?['name'] ?? 'Library';
        final status = hr['status'] ?? 'pending';
        activities.add({
          'time': DateTime.parse(hr['created_at']),
          'action': 'Membership Pause Request',
          'details': 'Status: ${status.toString().toUpperCase()}',
          'location': libName,
          'color': status == 'approved' ? const Color(0xFF22C55E) : (status == 'rejected' ? const Color(0xFFEF4444) : const Color(0xFF3B82F6)),
        });
      }

      activities.sort((a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime));
      _recentActivities = activities.take(8).toList();

    } catch (e) {
      debugPrint('Error loading member home data: $e');
      _errorMessage = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startAttendanceTicker(DateTime checkInTime) {
    _attendanceTimer?.cancel();
    _updateLiveDuration(checkInTime);
    _attendanceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateLiveDuration(checkInTime);
    });
  }

  void _updateLiveDuration(DateTime checkInTime) {
    final diff = DateTime.now().difference(checkInTime.toLocal());
    final hrs = diff.inHours;
    final mins = diff.inMinutes.remainder(60);
    final secs = diff.inSeconds.remainder(60);
    if (mounted) {
      setState(() {
        _liveSessionDuration = '${hrs}h ${mins}m ${secs}s';
      });
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final c = cos;
    final a = 0.5 - c((lat2 - lat1) * p)/2 + 
          c(lat1 * p) * c(lat2 * p) * 
          (1 - c((lon2 - lon1) * p))/2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  int _calculateCurrentStreak(Set<String> studyDates) {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final yesterdayStr = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));
    
    bool hasToday = studyDates.contains(todayStr);
    bool hasYesterday = studyDates.contains(yesterdayStr);
    
    if (!hasToday && !hasYesterday) return 0;
    
    int streak = 0;
    DateTime current = hasToday ? DateTime.now() : DateTime.now().subtract(const Duration(days: 1));
    
    while (true) {
      final curStr = DateFormat('yyyy-MM-dd').format(current);
      if (studyDates.contains(curStr)) {
        streak++;
        current = current.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  int _calculateBestStreak(Set<String> studyDates) {
    if (studyDates.isEmpty) return 0;
    
    List<DateTime> sortedDates = studyDates
        .map((d) => DateTime.parse(d))
        .toList()
      ..sort();
      
    int maxStreak = 0;
    int currentStreak = 0;
    DateTime? prevDate;
    
    for (var date in sortedDates) {
      if (prevDate == null) {
        currentStreak = 1;
      } else {
        final diff = date.difference(prevDate).inDays;
        if (diff == 1) {
          currentStreak++;
        } else if (diff > 1) {
          if (currentStreak > maxStreak) {
            maxStreak = currentStreak;
          }
          currentStreak = 1;
        }
      }
      prevDate = date;
    }
    
    if (currentStreak > maxStreak) {
      maxStreak = currentStreak;
    }
    
    return maxStreak;
  }

  List<Map<String, dynamic>> _getLast7DaysAttendance(Set<String> studyDates) {
    List<Map<String, dynamic>> list = [];
    for (int i = 6; i >= 0; i--) {
      final day = DateTime.now().subtract(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(day);
      final dayLabel = DateFormat('E').format(day)[0];
      list.add({
        'dayLabel': dayLabel,
        'attended': studyDates.contains(dateStr),
      });
    }
    return list;
  }

  bool _isProfileIncomplete() {
    final name = _userProfile?['full_name'] as String?;
    final phone = _userProfile?['phone'] as String?;
    final nickname = _userProfile?['nickname'] as String?;
    final gender = _userProfile?['gender'] as String?;
    final dob = _userProfile?['date_of_birth'] as String?;
    final address = _userProfile?['address'] as String?;
    final examCategory = _userProfile?['exam_category'] as String?;
    final photo = _userProfile?['photo_url'] as String?;
    final idProof = _userProfile?['id_proof_url'] as String?;
    
    return name == null || name.trim().isEmpty || 
           phone == null || phone.trim().isEmpty || 
           nickname == null || nickname.trim().isEmpty ||
           gender == null || gender.trim().isEmpty ||
           dob == null || dob.trim().isEmpty ||
           address == null || address.trim().isEmpty ||
           examCategory == null || examCategory.trim().isEmpty ||
           photo == null || photo.trim().isEmpty ||
           idProof == null || idProof.trim().isEmpty;
  }

  MemberState _getMemberState() {
    bool hasActive = _myMemberships.any((m) => m['status'] == 'active');
    if (hasActive) return MemberState.activeMember;

    bool hasPast = _pastMemberships.isNotEmpty;
    if (hasPast) return MemberState.returning;

    if (!_isProfileIncomplete()) {
      return MemberState.profileCompleteNoLib;
    }

    return MemberState.fresh;
  }

  void _showProfileIncompleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Complete Your Profile', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text('Please complete your profile before joining a library.', style: GoogleFonts.inter()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MemberProfileEditScreen()),
              ).then((result) {
                if (result == true) {
                  _loadInitialData();
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65C00),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Edit Profile', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getNearLibraries() {
    List<Map<String, dynamic>> list = List.from(_exploreLibraries);
    if (_currentPosition != null) {
      list.sort((a, b) {
        final aLat = a['latitude'] as num?;
        final aLng = a['longitude'] as num?;
        final bLat = b['latitude'] as num?;
        final bLng = b['longitude'] as num?;
        if (aLat == null || aLng == null) return 1;
        if (bLat == null || bLng == null) return -1;
        final distA = _calculateDistance(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          aLat.toDouble(),
          aLng.toDouble(),
        );
        final distB = _calculateDistance(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          bLat.toDouble(),
          bLng.toDouble(),
        );
        return distA.compareTo(distB);
      });
    } else {
      list.sort((a, b) {
        final nameA = (a['name'] ?? '').toString().toLowerCase();
        final nameB = (b['name'] ?? '').toString().toLowerCase();
        return nameA.compareTo(nameB);
      });
    }
    return list;
  }

  String _getYesterdayOrLastSessionText() {
    if (_lastCompletedAttendance == null) {
      return "No recent study sessions recorded.";
    }
    final checkInStr = _lastCompletedAttendance!['check_in_time'] as String;
    final checkOutStr = _lastCompletedAttendance!['check_out_time'] as String;
    final checkIn = DateTime.parse(checkInStr).toLocal();
    final checkOut = DateTime.parse(checkOutStr).toLocal();
    
    final duration = checkOut.difference(checkIn);
    final hrs = duration.inHours;
    final mins = duration.inMinutes.remainder(60);
    
    final formattedTime = DateFormat('h:mm a').format(checkIn);
    final durationStr = "${hrs}h ${mins}m";
    
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    
    if (checkIn.year == yesterday.year && checkIn.month == yesterday.month && checkIn.day == yesterday.day) {
      return "Yesterday: checked in at $formattedTime, $durationStr";
    } else if (checkIn.year == now.year && checkIn.month == now.month && checkIn.day == now.day) {
      return "Today's previous session: checked in at $formattedTime, $durationStr";
    } else {
      final dateStr = DateFormat('dd MMM').format(checkIn);
      return "Last session ($dateStr): checked in at $formattedTime, $durationStr";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE65C00),
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: const Color(0xFFFBF5EE),
          body: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
              : _errorMessage != null
                  ? _buildErrorState()
                  : _buildCurrentTabContent(),
          bottomNavigationBar: _buildBottomNav(),
          floatingActionButton: _shouldShowFAB()
              ? FloatingActionButton(
                  onPressed: _openQRScanner,
                  backgroundColor: const Color(0xFFE65C00),
                  foregroundColor: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 6,
                  child: const Icon(Icons.qr_code_scanner, size: 28),
                )
              : null,
        ),
      ),
    );
  }

  bool _shouldShowFAB() {
    if (_currentBottomTab != 0) return false;
    final state = _getMemberState();
    return state == MemberState.activeMember || state == MemberState.returning;
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              'Failed to load dashboard',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error occurred.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadInitialData,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTabContent() {
    return IndexedStack(
      index: _currentBottomTab,
      children: [
        _buildHomeTab(),
        _buildAnalyticsTab(),
        const MemberHistoryTab(),
        _buildProfileTab(),
      ],
    );
  }

  // ==========================================
  // TAB 0: HOME TAB (Multi-stage workflow)
  // ==========================================
  Widget _buildHomeTab() {
    final state = _getMemberState();
    switch (state) {
      case MemberState.fresh:
        return _buildFreshState();
      case MemberState.profileCompleteNoLib:
        return _buildProfileCompleteNoLibState();
      case MemberState.activeMember:
        return _buildActiveMemberState();
      case MemberState.returning:
        return _buildReturningState();
    }
  }

  // CURVED ORANGE HEADERS FOR STAGES
  Widget _buildCurvedHeader({required String greeting, required String subtitle, bool showLogo = true}) {
    final unreadCount = _announcements.where((a) => !_readAnnouncementIds.contains(a['id'])).length;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFE65C00),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              showLogo
                  ? Image.asset(
                      'assets/images/BLack_name_with_tag.png',
                      height: 28,
                      fit: BoxFit.contain,
                      color: Colors.white,
                    )
                  : const SizedBox(height: 28),
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none, color: Colors.white, size: 28),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => _buildNotificationsScreen()),
                      );
                    },
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          '$unreadCount',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                ],
              )
            ],
          ),
          const SizedBox(height: 16),
          Text(
            greeting,
            style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withOpacity(0.85)),
          ),
        ],
      ),
    );
  }

  // STAGE 1: FRESH INSTALL
  Widget _buildFreshState() {
    final nearLibs = _getNearLibraries();

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: const Color(0xFFE65C00),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCurvedHeader(
              greeting: "Welcome to SILENCE!",
              subtitle: "Complete your profile to start studying",
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Complete Profile Card
                  _buildProfileSetupCard(),
                  const SizedBox(height: 8),
                  
                  // How SILENCE Works Card
                  _buildHowItWorksCard(),
                  const SizedBox(height: 20),
                  
                  // Find a Library Button
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/member/explore').then((_) => _loadInitialData());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Find a Library', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  const SizedBox(height: 12),
                  
                  // Join with code button
                  OutlinedButton(
                    onPressed: _openJoinWithCodeSheet,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFFE65C00), width: 1.5),
                      foregroundColor: const Color(0xFFE65C00),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Join with Code', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 24),

                  // Libraries Near You section
                  if (nearLibs.isNotEmpty) ...[
                    Text(
                      'Libraries Near You',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: min(5, nearLibs.length),
                        itemBuilder: (context, index) {
                          return _buildLibraryCardHorizontal(nearLibs[index]);
                        },
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

  // STAGE 2: PROFILE COMPLETE, NO LIBRARY
  Widget _buildProfileCompleteNoLibState() {
    final nearLibs = _getNearLibraries();

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: const Color(0xFFE65C00),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCurvedHeader(
              greeting: "Ready to Study!",
              subtitle: "Your profile is set. Now find a library.",
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Celebration Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7), // green-50
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Profile Complete ✓',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: const Color(0xFF14532D),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Your account credentials and ID documents are verified.',
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF166534)),
                              )
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Find a Library Button
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/member/explore').then((_) => _loadInitialData());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Find a Library', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  const SizedBox(height: 12),
                  
                  // Join with code button
                  OutlinedButton(
                    onPressed: _openJoinWithCodeSheet,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFFE65C00), width: 1.5),
                      foregroundColor: const Color(0xFFE65C00),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Join with Code', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 24),

                  // Libraries Near You section
                  if (nearLibs.isNotEmpty) ...[
                    Text(
                      'Libraries Near You',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: min(5, nearLibs.length),
                        itemBuilder: (context, index) {
                          return _buildLibraryCardHorizontal(nearLibs[index]);
                        },
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

  // STAGE 3: ACTIVE MEMBER
  Widget _buildActiveMemberState() {
    final nickname = _userProfile?['nickname'] as String?;
    final userName = (nickname != null && nickname.isNotEmpty && nickname != 'N/A')
        ? nickname
        : (_userProfile?['full_name'] ?? 'Student');

    final greetingText = "${DateTime.now().hour < 12 ? 'Good morning' : (DateTime.now().hour < 17 ? 'Good afternoon' : 'Good evening')}, $userName 👋";

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: const Color(0xFFE65C00),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCurvedHeader(
              greeting: greetingText,
              subtitle: "Track your attendance and manage seats",
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // My Memberships Section
                  Text(
                    'My Memberships',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 10),
                  ..._myMemberships.map((m) => _buildMembershipCard(m)),
                  const SizedBox(height: 16),

                  // Today's Attendance card
                  _buildTodayAttendanceCard(),
                  const SizedBox(height: 16),

                  // Study Streak card
                  _buildStreakCard(),
                  const SizedBox(height: 16),

                  // Quick Actions Row
                  _buildQuickActionsRow(),
                  const SizedBox(height: 24),

                  // Announcements section
                  if (_announcements.isNotEmpty) ...[
                    Text(
                      'Announcements',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 10),
                    _buildAnnouncementsSection(),
                    const SizedBox(height: 24),
                  ],

                  // Recent Activities Timeline
                  Text(
                    'Recent Activities',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 12),
                  _buildActivitiesTimeline(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // STAGE 4: RETURNING STATE
  Widget _buildReturningState() {
    final suggested = _exploreLibraries.take(2).toList();
    
    // Find last library details
    Map<String, dynamic>? lastLib;
    String exitDateStr = 'some time ago';
    int durationMonths = 1;
    
    if (_pastMemberships.isNotEmpty) {
      final lastM = _pastMemberships.first;
      lastLib = lastM['libraries'] as Map<String, dynamic>?;
      final exitDateRaw = lastM['exited_at'] ?? lastM['end_date'];
      if (exitDateRaw != null) {
        try {
          final dt = DateTime.parse(exitDateRaw);
          exitDateStr = DateFormat('dd MMM yyyy').format(dt);
        } catch (_) {}
      }
      
      // Calculate duration
      final startStr = lastM['start_date'];
      final endStr = lastM['end_date'];
      if (startStr != null && endStr != null) {
        try {
          final s = DateTime.parse(startStr);
          final e = DateTime.parse(endStr);
          final days = e.difference(s).inDays;
          durationMonths = (days / 30.0).round();
          if (durationMonths <= 0) durationMonths = 1;
        } catch (_) {}
      }
    }
    
    final lastLibName = lastLib?['name'] ?? 'SILENCE Space';

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: const Color(0xFFE65C00),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCurvedHeader(
              greeting: "Welcome back!",
              subtitle: "You can rejoin or discover new spaces.",
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Previous Membership Card
                  if (_pastMemberships.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: const Border(left: BorderSide(color: Color(0xFFF59E0B), width: 4)), // amber
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Previous Membership',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[500]),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            lastLibName,
                            style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Exited: $exitDateStr • Active for $durationMonths month${durationMonths > 1 ? 's' : ''}',
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[650]),
                          ),
                          const SizedBox(height: 16),
                          
                          // Trophy/Stats Container
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7), // amber-100
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.emoji_events_outlined, color: Color(0xFFB45309), size: 24),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Trophy Stat',
                                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFB45309)),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${_totalStudyHours.toStringAsFixed(1)} hours in $_daysPresent days present',
                                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF78350F)),
                                      ),
                                    ],
                                  ),
                                )
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () {
                                if (lastLib != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => JoinFlowScreen(libraryId: lastLib!['id']),
                                    ),
                                  ).then((_) => _loadInitialData());
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFE65C00)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              child: Text('Rejoin Now', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Quick Actions row
                  _buildQuickActionsRow(),
                  const SizedBox(height: 20),

                  // Streak card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED), // orange-50
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.local_fire_department, color: Color(0xFFE65C00), size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your Best Streak: $_bestStreak days',
                                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFFC2410C)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Rejoin a library to resume study streaks and boost performance!',
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFEA580C)),
                              )
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Find Library Button
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/member/explore').then((_) => _loadInitialData());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Find a Library', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  const SizedBox(height: 24),

                  // Suggested Libraries section
                  if (suggested.isNotEmpty) ...[
                    Text(
                      'Suggested Libraries',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: suggested.length,
                        itemBuilder: (context, index) {
                          return _buildLibraryCardHorizontal(suggested[index]);
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Last Activity Card
                  _buildLastActivityCard(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // SHARED WIDGET BUILDERS
  // ==========================================
  Widget _buildProfileSetupCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: const Border(
          left: BorderSide(color: Color(0xFFE65C00), width: 4),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFFE65C00), size: 24),
              const SizedBox(width: 8),
              Text(
                'Complete Your Profile',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Provide your photo, contact details, and ID document on a single quick page.',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600], height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _navigateToEditProfile,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Get Started'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          )
        ],
      ),
    );
  }

  void _navigateToEditProfile() async {
    final success = await Navigator.pushNamed(context, '/member/edit-profile');
    if (success == true) {
      _loadInitialData();
    }
  }

  Widget _buildHowItWorksCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange[200]!, style: BorderStyle.solid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How SILENCE Works',
            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 12),
          _buildHowItWorksRow(1, 'Complete Profile', 'Submit photo and ID details.', Icons.person_outlined),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          _buildHowItWorksRow(2, 'Find a Library', 'Search study zones near you.', Icons.search),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          _buildHowItWorksRow(3, 'Scan & Study', 'Check attendance using QR scanner.', Icons.qr_code_scanner),
        ],
      ),
    );
  }

  Widget _buildHowItWorksRow(int step, String title, String subtitle, IconData icon) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: const Color(0xFFFFF3ED), shape: BoxShape.circle),
          child: Icon(icon, color: const Color(0xFFE65C00), size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Step $step: $title',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              Text(
                subtitle,
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildLibraryCardHorizontal(Map<String, dynamic> lib) {
    final name = lib['name'] ?? 'SILENCE Space';
    final photos = lib['photos'] as List? ?? [];
    final shifts = lib['shifts'] as List? ?? [];
    
    // Distance
    double? distanceKm;
    final aLat = lib['latitude'] as num?;
    final aLng = lib['longitude'] as num?;
    if (_currentPosition != null && aLat != null && aLng != null) {
      distanceKm = _calculateDistance(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        aLat.toDouble(),
        aLng.toDouble(),
      );
    }
    final distanceText = distanceKm != null ? '${distanceKm.toStringAsFixed(1)} km' : null;

    // Minimum starting price
    int startingPrice = 0;
    for (var s in shifts) {
      final p = s['price_monthly'] as int? ?? 999999;
      if (startingPrice == 0 || p < startingPrice) {
        startingPrice = p;
      }
    }

    // Rating
    final reviews = lib['reviews'] as List? ?? [];
    double avgRating = 0.0;
    if (reviews.isNotEmpty) {
      final total = reviews.fold<num>(0, (sum, item) => sum + (item['rating'] as num? ?? 0));
      avgRating = total / reviews.length;
    }

    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 16),
      child: Card(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => LibraryPublicProfileScreen(
                  libraryId: lib['id'],
                  isAdmin: false,
                ),
              ),
            ).then((_) => _loadInitialData());
          },
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                child: photos.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: photos.first.toString(),
                        height: 90,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      )
                    : Container(height: 90, color: Colors.orange[50], child: const Icon(Icons.image, color: Color(0xFFE65C00))),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (reviews.isNotEmpty)
                          Row(
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 12),
                              const SizedBox(width: 2),
                              Text(
                                avgRating.toStringAsFixed(1),
                                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          )
                        else
                          Text('New', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.bold)),
                        
                        if (distanceText != null)
                          Text(
                            distanceText,
                            style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFFE65C00), fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      startingPrice > 0 ? 'From ₹$startingPrice/mo' : 'Price TBA',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMembershipCard(Map<String, dynamic> membership) {
    final status = membership['status'] as String? ?? 'pending';
    final library = membership['libraries'] as Map<String, dynamic>? ?? {};
    final shift = membership['shifts'] as Map<String, dynamic>? ?? {};
    final seat = membership['seats'] as Map<String, dynamic>? ?? {};
    
    Color borderColor;
    String statusLabel;
    
    DateTime? endDate;
    if (membership['end_date'] != null) {
      endDate = DateTime.parse(membership['end_date']);
    }
    final remainingDays = endDate != null ? endDate.difference(DateTime.now()).inDays : -1;

    if (status == 'active' && remainingDays <= 7 && remainingDays >= 0) {
      borderColor = const Color(0xFFF59E0B); // expiring (amber)
      statusLabel = 'Expiring Soon';
    } else {
      switch (status) {
        case 'active':
          borderColor = const Color(0xFF22C55E); // green
          statusLabel = 'Active';
          break;
        case 'expired':
          borderColor = const Color(0xFFEF4444); // red
          statusLabel = 'Expired';
          break;
        case 'hold':
          borderColor = const Color(0xFFEAB308); // yellow
          statusLabel = 'Hold';
          break;
        case 'trial':
          borderColor = const Color(0xFF7C3AED); // purple
          statusLabel = 'Trial';
          break;
        case 'pending':
        default:
          borderColor = const Color(0xFF9CA3AF); // gray
          statusLabel = 'Pending';
          break;
      }
    }

    final isVerified = library['verified'] == true;
    double progress = 0.0;
    if (membership['start_date'] != null && membership['end_date'] != null) {
      final start = DateTime.parse(membership['start_date']);
      final end = DateTime.parse(membership['end_date']);
      final total = end.difference(start).inDays;
      if (total > 0) {
        final elapsed = DateTime.now().difference(start).inDays;
        progress = (elapsed / total).clamp(0.0, 1.0);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: borderColor, width: 4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      library['name'] ?? 'SILENCE Zone',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                    ),
                    if (isVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, color: Colors.blue, size: 16),
                    ]
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: borderColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: borderColor),
                ),
              )
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.event_seat, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                seat.isNotEmpty ? (seat['seat_label'] ?? 'Pending') : 'Seat Pending',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFE65C00)),
              ),
              const SizedBox(width: 24),
              const Icon(Icons.wb_sunny_outlined, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                shift.isNotEmpty ? (shift['name'] ?? 'Shift') : 'Shift Pending',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[700]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.receipt_long, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                '${membership['plan_type'] == 'monthly' ? 'Monthly' : membership['plan_type'] == '3_month' ? '3-Month' : '6-Month'} Plan',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(width: 24),
              Text(
                '₹${shift.isNotEmpty ? (membership['plan_type'] == 'monthly' ? (shift['price_monthly'] ?? 0) : membership['plan_type'] == '3_month' ? (shift['price_3month'] ?? 0) : (shift['price_6month'] ?? 0)) : 0}',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
            ],
          ),
          
          if (endDate != null && status != 'pending') ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey[200],
                color: borderColor,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Expires: ${DateFormat('dd MMM yyyy').format(endDate)}',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                ),
                Text(
                  remainingDays > 0 ? '$remainingDays days left' : remainingDays == 0 ? 'Expires today' : 'Expired',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: remainingDays <= 7 ? Colors.redAccent : Colors.grey[600]),
                ),
              ],
            ),
          ],
          
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    if (_isProfileIncomplete()) {
                      _showProfileIncompleteDialog();
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => JoinFlowScreen(
                          libraryId: library['id'],
                          initialShiftId: shift['id'],
                        ),
                      ),
                    ).then((_) => _loadInitialData());
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: const BorderSide(color: Color(0xFFE65C00)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Renew Plan', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openSeatChangeSheet(membership),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: const BorderSide(color: Color(0xFFE65C00)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Seat Chg', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey, size: 20),
                  onPressed: () => _openMembershipMoreOptions(membership),
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildTodayAttendanceCard() {
    final attendance = _activeAttendance;
    final checkedIn = attendance != null;

    return Container(
      decoration: BoxDecoration(
        color: checkedIn ? const Color(0xFFDCFCE7) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Today's Attendance",
            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 12),
          if (checkedIn) ...[
            Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Checked In • ${_formatTimeString(attendance['check_in_time'])}',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF15803D)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Session Time: $_liveSessionDuration',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFF166534), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openQRScanner,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Check Out'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                const Icon(Icons.location_off, color: Colors.grey, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Not checked in yet',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Scan your library QR to check in.',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openQRScanner,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Scan to Check In'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            _getYesterdayOrLastSessionText(),
            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildStreakCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department, color: Color(0xFFE65C00), size: 28),
              const SizedBox(width: 8),
              Text(
                'Study Streak',
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const Spacer(),
              Text(
                '$_currentStreak Days',
                style: GoogleFonts.spaceMono(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
              )
            ],
          ),
          const SizedBox(height: 16),
          // Last 7 days circles
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _streakLast7Days.map((day) {
              final active = day['attended'] as bool;
              return Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF22C55E) : Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: active
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    day['dayLabel'] as String,
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w500),
                  )
                ],
              );
            }).toList(),
          )
        ],
      ),
    );
  }

  Widget _buildQuickActionsRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildQuickActionButton(
            label: 'Scan QR',
            icon: Icons.qr_code_scanner,
            onPressed: _openQRScanner,
          ),
          const SizedBox(width: 8),
          _buildQuickActionButton(
            label: 'Find Library',
            icon: Icons.explore_outlined,
            onPressed: () {
              Navigator.pushNamed(context, '/member/explore').then((_) => _loadInitialData());
            },
          ),
          const SizedBox(width: 8),
          _buildQuickActionButton(
            label: 'Join with Code',
            icon: Icons.vpn_key_outlined,
            onPressed: _openJoinWithCodeSheet,
          ),
          const SizedBox(width: 8),
          _buildQuickActionButton(
            label: 'Seat Change',
            icon: Icons.event_seat,
            onPressed: () {
              if (_myMemberships.isNotEmpty) {
                _openSeatChangeSheet(_myMemberships.first);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No active membership found to request seat change.')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({required String label, required IconData icon, required VoidCallback onPressed}) {
    return Container(
      width: 100,
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFFE65C00), size: 20),
              const SizedBox(height: 6),
              Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF475569))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivitiesTimeline() {
    if (_recentActivities.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Center(
          child: Text('No activities recorded yet.', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500])),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 8)],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _recentActivities.length,
        itemBuilder: (context, index) {
          final act = _recentActivities[index];
          final DateTime dt = act['time'] as DateTime;
          final dateStr = DateFormat('dd MMM, hh:mm a').format(dt);
          final color = act['color'] as Color;

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Timeline Line & Dot
                Column(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    if (index != _recentActivities.length - 1)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Colors.grey[200],
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          act['action'] as String,
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                        ),
                        Text(
                          '${act['details']} • ${act['location']}',
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600]),
                        ),
                        Text(
                          dateStr,
                          style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[400]),
                        ),
                      ],
                    ),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLastActivityCard() {
    if (_lastCompletedAttendance == null) {
      return const SizedBox.shrink();
    }
    final checkOutStr = _lastCompletedAttendance!['check_out_time'] as String;
    final dt = DateTime.parse(checkOutStr).toLocal();
    final dateStr = DateFormat('dd MMM yyyy, h:mm a').format(dt);
    final libName = _lastCompletedAttendance!['libraries']?['name'] ?? 'Library';
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 4)],
      ),
      child: Row(
        children: [
          const Icon(Icons.history, color: Colors.grey, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Last Study Session', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                const SizedBox(height: 2),
                Text('Checked Out of $libName', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                Text(dateStr, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600])),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildAnnouncementsSection() {
    return Column(
      children: _announcements.map((announce) {
        final isUnread = !_readAnnouncementIds.contains(announce['id']);
        final libraryName = announce['libraries']?['name'] ?? 'Library';
        final sentAtStr = announce['sent_at'] as String?;
        String sentTime = 'Just now';
        if (sentAtStr != null) {
          final dt = DateTime.parse(sentAtStr).toLocal();
          final diff = DateTime.now().difference(dt);
          if (diff.inHours < 1) {
            sentTime = '${diff.inMinutes} mins ago';
          } else if (diff.inDays < 1) {
            sentTime = '${diff.inHours} hours ago';
          } else {
            sentTime = DateFormat('dd MMM').format(dt);
          }
        }

        return InkWell(
          onTap: () => _viewAnnouncement(announce),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(
                  color: isUnread ? const Color(0xFFE65C00) : Colors.grey[350]!, 
                  width: 4
                )
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      libraryName,
                      style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                    ),
                    Text(
                      sentTime,
                      style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[500]),
                    )
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  announce['title'] ?? 'Notice',
                  style: GoogleFonts.inter(
                    fontSize: 13, 
                    fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                    color: const Color(0xFF1E293B)
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  announce['message'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _viewAnnouncement(Map<String, dynamic> announce) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                announce['title'] ?? 'Notice',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 4),
              Text(
                announce['libraries']?['name'] ?? 'Library notice',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFE65C00), fontWeight: FontWeight.bold),
              ),
              const Divider(height: 24),
              Text(
                announce['message'] ?? '',
                style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[800], height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    
                    final supabase = Supabase.instance.client;
                    final currentUser = supabase.auth.currentUser;
                    if (currentUser != null) {
                      try {
                        await supabase.from('announcement_reads').upsert({
                          'announcement_id': announce['id'],
                          'member_id': currentUser.id,
                          'read_at': DateTime.now().toIso8601String(),
                        });
                        
                        setState(() {
                          _readAnnouncementIds.add(announce['id']);
                        });
                      } catch (e) {
                        debugPrint('Error marking read: $e');
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                  child: const Text('Close'),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // TAB 1: ANALYTICS TAB
  // ==========================================
  Widget _buildAnalyticsTab() {
    String? activeLibId;
    if (_myMemberships.isNotEmpty) {
      activeLibId = _myMemberships.first['library_id'];
    } else if (_exploreLibraries.isNotEmpty) {
      activeLibId = _exploreLibraries.first['id'];
    }
    
    return MemberAnalyticsTab(
      userProfile: _userProfile,
      activeLibraryId: activeLibId,
      memberLibraries: _myMemberships,
    );
  }

  // ==========================================
  // TAB 3: PROFILE TAB
  // ==========================================
  Widget _buildProfileTab() {
    final name = _userProfile?['full_name'] ?? 'Student User';
    final email = _userProfile?['email'] ?? '';
    final phone = _userProfile?['phone'] ?? 'Enter Phone Number';
    final nickname = _userProfile?['nickname'] ?? 'N/A';
    final photoUrl = _userProfile?['photo_url'] as String?;

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xFFE65C00),
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text(
              'Profile',
              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ),
        
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE65C00), width: 3),
                        ),
                        child: CircleAvatar(
                          backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                          backgroundColor: Colors.orange[50],
                          child: photoUrl == null ? const Icon(Icons.person, size: 40, color: Color(0xFFE65C00)) : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                      ),
                      if (nickname != 'N/A') ...[
                        const SizedBox(height: 2),
                        Text(
                          '@$nickname',
                          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500]),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _openEditProfileModal,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text('Edit Profile'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      _buildProfileItem(Icons.phone, 'Phone', phone),
                      const Divider(height: 1, indent: 56),
                      _buildProfileItem(Icons.email, 'Email', email),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                _buildReferralSection(),
                const SizedBox(height: 16),

                Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.help_outline, color: Color(0xFFE65C00)),
                        title: Text('Help & Support', style: GoogleFonts.inter(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500)),
                        trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const HelpSupportScreen()),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.gavel_outlined, color: Color(0xFFE65C00)),
                        title: Text('Terms & Conditions', style: GoogleFonts.inter(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500)),
                        trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const TermsScreen()),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.info_outline, color: Color(0xFFE65C00)),
                        title: Text('About SILENCE', style: GoogleFonts.inter(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500)),
                        trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const AboutUsScreen()),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.settings_outlined, color: Color(0xFFE65C00)),
                        title: Text('Local Settings', style: GoogleFonts.inter(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500)),
                        trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const AppSettingsScreen()),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await Supabase.instance.client.auth.signOut();
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(context, '/login');
                      }
                    },
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Logout'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[50],
                      foregroundColor: Colors.redAccent,
                      elevation: 0,
                      side: BorderSide(color: Colors.red[100]!),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildProfileItem(IconData icon, String title, String val) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFFE65C00)),
      title: Text(title, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
      subtitle: Text(val, style: GoogleFonts.inter(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildReferralSection() {
    final uid = _userProfile?['id']?.toString() ?? 'XXXX';
    final shortUid = uid.length >= 4 ? uid.substring(0, 4).toUpperCase() : 'XXXX';
    final refCode = 'REF-$shortUid';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.group_add, color: Color(0xFFB45309)),
              const SizedBox(width: 8),
              Text('Refer a Friend', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFB45309))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Invite your friends to study here and earn free extension days when they join!',
            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF92400E)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFCD34D)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(refCode, style: GoogleFonts.spaceMono(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFB45309), letterSpacing: 2)),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy, color: Color(0xFFB45309), size: 20),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: refCode));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Referral code copied!')));
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.share, color: Color(0xFFB45309), size: 20),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opening Share Dialog...')));
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                )
              ],
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<dynamic>>(
            future: Supabase.instance.client.from('referrals').select().eq('referrer_member_id', uid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
              final list = snapshot.data ?? [];
              final pending = list.where((r) => r['status'] == 'pending').length;
              final credited = list.where((r) => r['status'] == 'credited').length;
              if (list.isEmpty) return const SizedBox.shrink();
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total Referred: ${list.length}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFB45309))),
                  Text('Pending: $pending | Earned: $credited', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF92400E))),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // NAVIGATION & BOTTOM SHEETS
  // ==========================================
  Widget _buildBottomNav() {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavItem(0, Icons.home, 'Home'),
          _buildNavItem(1, Icons.bar_chart, 'Analytics'),
          _buildNavItem(2, Icons.history, 'History'),
          _buildNavItem(3, Icons.person, 'Profile'),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final selected = _currentBottomTab == index;
    return InkWell(
      onTap: () => setState(() => _currentBottomTab = index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? const Color(0xFFE65C00) : Colors.grey[500], size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11, 
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? const Color(0xFFE65C00) : Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeString(String isoString) {
    final dt = DateTime.parse(isoString).toLocal();
    return DateFormat('hh:mm a').format(dt);
  }

  void _openQRScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    ).then((_) => _loadInitialData());
  }

  void _openSeatChangeSheet(Map<String, dynamic> membership) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        return SeatChangeBottomSheet(
          membership: membership,
          onSuccess: _loadInitialData,
        );
      },
    );
  }

  void _openMembershipMoreOptions(Map<String, dynamic> membership) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.pause_circle_outline, color: Color(0xFFD97706)),
                title: Text('Hold / Pause', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _openHoldRequestSheet(membership);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.event_seat, color: Color(0xFFE65C00)),
                title: Text('Change Seat', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _openSeatChangeSheet(membership);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.redAccent),
                title: Text('Exit Library', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  _openExitLibrarySheetFlow(membership);
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Cancel'),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  void _openHoldRequestSheet(Map<String, dynamic> membership) {
    final library = membership['libraries'] as Map<String, dynamic>? ?? {};
    final reasonCtrl = TextEditingController();
    
    DateTime holdStart = DateTime.now().add(const Duration(days: 1)); // min tomorrow
    DateTime holdEnd = holdStart.add(const Duration(days: 7)); // default 7 days

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                left: 20, right: 20, top: 20
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Pause Membership', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  Text(
                    library['name'] ?? 'SILENCE Study Zone',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const Divider(height: 24),
                  
                  Text('Reason *', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500])),
                  const SizedBox(height: 6),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(hintText: 'e.g. Preparing for examinations at home...'),
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Start Date *', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final picked = await showCalendarGridBottomSheet(
                                  context,
                                  initialDate: holdStart,
                                  firstDate: DateTime.now().add(const Duration(days: 1)),
                                  lastDate: DateTime.now().add(const Duration(days: 30)),
                                );
                                if (picked != null) {
                                  setSheetState(() {
                                    holdStart = picked;
                                    if (holdEnd.isBefore(holdStart)) {
                                      holdEnd = holdStart.add(const Duration(days: 7));
                                    }
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(DateFormat('dd MMM yyyy').format(holdStart), style: GoogleFonts.inter(fontSize: 13)),
                                    const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                                  ],
                                ),
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('End Date *', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final picked = await showCalendarGridBottomSheet(
                                  context,
                                  initialDate: holdEnd,
                                  firstDate: holdStart.add(const Duration(days: 1)),
                                  lastDate: holdStart.add(const Duration(days: 30)),
                                );
                                if (picked != null) {
                                  setSheetState(() {
                                    holdEnd = picked;
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(DateFormat('dd MMM yyyy').format(holdEnd), style: GoogleFonts.inter(fontSize: 13)),
                                    const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                                  ],
                                ),
                              ),
                            )
                          ],
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFBF5EE), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE65C00).withOpacity(0.3))),
                    child: Column(
                      children: [
                        _buildHoldBullet('Seat stays reserved for you'),
                        const SizedBox(height: 6),
                        _buildHoldBullet('Billing parses and extends after pause'),
                        const SizedBox(height: 6),
                        _buildHoldBullet('Expiry extends automatically by pause length'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            if (reasonCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please provide a reason.')),
                              );
                              return;
                            }
                            
                            try {
                              final supabase = Supabase.instance.client;
                              await supabase.from('hold_requests').insert({
                                'membership_id': membership['id'],
                                'member_id': membership['member_id'],
                                'library_id': library['id'],
                                'start_date': DateFormat('yyyy-MM-dd').format(holdStart),
                                'end_date': DateFormat('yyyy-MM-dd').format(holdEnd),
                                'reason': reasonCtrl.text.trim(),
                                'status': 'pending',
                              });
                              
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Hold Request submitted! ✓')),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE65C00),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Submit →'),
                        ),
                      )
                    ],
                  )
                ],
              ),
            );
          }
        );
      },
    );
  }

  Widget _buildHoldBullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check, size: 16, color: Color(0xFF22C55E)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[750]))),
      ],
    );
  }

  void _openExitLibrarySheetFlow(Map<String, dynamic> membership) {
    final library = membership['libraries'] as Map<String, dynamic>? ?? {};
    final seat = membership['seats'] as Map<String, dynamic>? ?? {};
    final seatLabel = seat.isNotEmpty ? (seat['seat_label'] ?? 'Seat') : 'Seat';
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        int pendingDues = 0;
        bool checkedDues = false;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (!checkedDues) {
              final supabase = Supabase.instance.client;
              supabase
                  .from('payments')
                  .select('amount')
                  .eq('membership_id', membership['id'])
                  .eq('status', 'pending')
                  .then((res) {
                    int sum = 0;
                    for (var r in res) {
                      sum += (r['amount'] as num? ?? 0).toInt();
                    }
                    setSheetState(() {
                      pendingDues = sum;
                      checkedDues = true;
                    });
                  })
                  .catchError((err) {
                    setSheetState(() {
                      checkedDues = true;
                    });
                  });
            }

            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
                      const SizedBox(width: 8),
                      Text('Exit Library?', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    library['name'] ?? 'SILENCE Study Zone',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const Divider(height: 24),

                  if (!checkedDues)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20.0),
                        child: CircularProgressIndicator(color: Color(0xFFE65C00)),
                      ),
                    )
                  else if (pendingDues > 0) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Pending Dues: ₹$pendingDues',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF991B1B),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'You have outstanding dues at this library. Please clear all pending payments with your admin before exiting.',
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF7F1D1D), height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                            child: const Text('Close'),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Text('This will:', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                    const SizedBox(height: 12),
                    _buildExitBulletRow(false, 'Free your seat $seatLabel immediately'),
                    const SizedBox(height: 8),
                    _buildExitBulletRow(false, 'End your membership subscription'),
                    const SizedBox(height: 8),
                    _buildExitBulletRow(false, 'Lose any remaining plan days'),
                    const SizedBox(height: 8),
                    _buildExitBulletRow(true, 'Your attendance history remains preserved'),
                    const SizedBox(height: 8),
                    _buildExitBulletRow(true, 'All earned badges will be kept in your profile'),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Future.delayed(const Duration(milliseconds: 300), () {
                                _openExitLibraryFinalConfirmSheet(membership);
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Yes, Exit →'),
                          ),
                        )
                      ],
                    )
                  ]
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openExitLibraryFinalConfirmSheet(Map<String, dynamic> membership) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.red[50],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text(
                '⚠️ Final Confirmation',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent),
              ),
              const SizedBox(height: 12),
              Text(
                'This cannot be undone. Your seat will be freed immediately and you will no longer be an active member of this library.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red[900]),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Colors.redAccent),
                        foregroundColor: Colors.redAccent,
                      ),
                      child: const Text('← Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          final supabase = Supabase.instance.client;
                          final seatId = membership['seat_id'];
                          if (seatId != null) {
                            await supabase.from('seats').update({
                              'status': 'vacant',
                              'occupied_by_member_id': null,
                            }).eq('id', seatId);
                          }
                          
                          await supabase.from('memberships').update({
                            'status': 'exited',
                            'exited_at': DateTime.now().toIso8601String(),
                          }).eq('id', membership['id']);
                          
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Successfully exited library. ✓')),
                            );
                            _loadInitialData();
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Confirm Exit'),
                    ),
                  )
                ],
              )
            ],
          ),
        );
      },
    );
  }

  void _openJoinWithCodeSheet() {
    final codeCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 20, right: 20, top: 20
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Join with Library Code', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 16),
              
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                onChanged: (val) {
                  String clean = val.replaceAll('-', '').toUpperCase();
                  if (clean.length > 3) {
                    clean = '${clean.substring(0, 3)}-${clean.substring(3)}';
                  }
                  if (clean.length > 10) {
                    clean = '${clean.substring(0, 10)}-${clean.substring(10)}';
                  }
                  codeCtrl.value = TextEditingValue(
                    text: clean,
                    selection: TextSelection.fromPosition(TextPosition(offset: clean.length)),
                  );
                },
                decoration: const InputDecoration(
                  labelText: 'Library Code',
                  hintText: 'e.g. SIL-4K9M-2P',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final code = codeCtrl.text.trim();
                    if (code.isEmpty) return;
                    
                    try {
                      final supabase = Supabase.instance.client;
                      final libRes = await supabase
                          .from('libraries')
                          .select()
                          .eq('library_code', code)
                          .maybeSingle();
                      
                      if (libRes == null) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Library not found. Check code prefix or suffix.')),
                          );
                        }
                        return;
                      }
                      
                      if (context.mounted) {
                        Navigator.pop(context);
                        if (_isProfileIncomplete()) {
                          _showProfileIncompleteDialog();
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => JoinFlowScreen(libraryId: libRes['id'])),
                        ).then((_) => _loadInitialData());
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error finding library: $e')),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Find Library'),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  void _openEditProfileModal() async {
    final success = await Navigator.pushNamed(context, '/member/edit-profile');
    if (success == true) {
      _loadInitialData();
    }
  }

  Widget _buildExitBulletRow(bool isPositive, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isPositive ? Icons.check_circle_outline : Icons.remove_circle_outline,
          color: isPositive ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF475569),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationsScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFFE65C00),
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: const Color(0xFFFBF5EE),
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            foregroundColor: Colors.white,
            title: Text('Notifications', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  "You're all caught up!",
                  style: GoogleFonts.outfit(fontSize: 16, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
