import 'dart:async';
import 'dart:math';
import 'dart:convert';
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
import 'reservations/renewal_screen.dart';
import 'reservations/library_query_screen.dart';
import 'member_profile_tab.dart';

enum MemberState {
  freshInstall,           // profile incomplete
  profileCompleteNoLib,   // profile complete, no memberships, no pending request
  applicationPending,     // join_requests status = 'pending' and no active membership
  trial,                  // memberships status = 'trial'
  active,                 // status = 'active' and end_date > today + 7
  expiringSoon,           // end_date between today and today+7
  expired,                // end_date < today (or status = 'expired')
  onHold,                 // status = 'hold'
  exited,                 // status = 'exited' (or most recent membership is exited)
}

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
  List<Map<String, dynamic>> _allMemberships = [];
  Map<String, dynamic>? _pendingRequest;
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

      // 1. Create parallel futures
      final profileFuture = supabase
          .from('users')
          .select()
          .eq('id', currentUser.id)
          .maybeSingle();

      final pendingReqsFuture = supabase
          .from('join_requests')
          .select('*, libraries(*)')
          .eq('member_id', currentUser.id)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final membershipsFuture = supabase
          .from('memberships')
          .select('*, libraries(*), shifts(*), seats(*)')
          .eq('member_id', currentUser.id)
          .order('created_at', ascending: false);

      final attendanceFuture = supabase
          .from('attendance')
          .select('*, memberships(*), shifts(*), libraries(*)')
          .eq('member_id', currentUser.id)
          .isFilter('check_out_time', null)
          .order('check_in_time', ascending: false)
          .limit(1)
          .maybeSingle();

      final lastCompletedFuture = supabase
          .from('attendance')
          .select('*, libraries(name)')
          .eq('member_id', currentUser.id)
          .not('check_out_time', 'is', null)
          .order('check_in_time', ascending: false)
          .limit(1)
          .maybeSingle();

      final exploreFuture = supabase
          .from('libraries')
          .select('id, name, address_city, address_street, verified, photos, amenities, library_code, status, rules, shifts(id, name, price_monthly, trial_days, start_time, end_time)')
          .eq('status', 'active');

      final results = await Future.wait([
        profileFuture,
        pendingReqsFuture,
        membershipsFuture,
        attendanceFuture,
        lastCompletedFuture,
        exploreFuture,
      ]);

      if (!mounted) return;

      _userProfile = results[0] as Map<String, dynamic>?;
      
      final pendingReqs = List<Map<String, dynamic>>.from(results[1] as List? ?? []);
      _pendingRequest = pendingReqs.isNotEmpty ? pendingReqs.first : null;

      final allMemberships = List<Map<String, dynamic>>.from(results[2] as List? ?? []);
      _allMemberships = allMemberships;

      _activeAttendance = results[3] as Map<String, dynamic>?;
      _lastCompletedAttendance = results[4] as Map<String, dynamic>?;
      
      final exploreRes = List<Map<String, dynamic>>.from(results[5] as List? ?? []);
      if (exploreRes.isNotEmpty) {
        _exploreLibraries = exploreRes;
      }

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

      // Filter memberships
      _myMemberships = allMemberships.where((m) => ['active', 'trial', 'hold', 'expired'].contains(m['status'])).toList();
      _pastMemberships = allMemberships.where((m) => m['status'] == 'exited').toList();

      final checkInStr = _activeAttendance?['check_in_time'] as String?;
      if (checkInStr != null) {
        _startAttendanceTicker(DateTime.parse(checkInStr));
      } else {
        _attendanceTimer?.cancel();
        _liveSessionDuration = '0h 0m 0s';
      }

      CacheService.instance.writeCache('explore_libraries_list', _exploreLibraries);

      // Load Announcements for my joined libraries
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
    if (_isProfileIncomplete()) {
      return MemberState.freshInstall;
    }

    // trial > active > expiringSoon > expired > hold > applicationPending > exited > profileCompleteNoLib > freshInstall

    // 1. trial
    final hasTrial = _allMemberships.any((m) => m['status'] == 'trial');
    if (hasTrial) return MemberState.trial;

    final today = DateTime.now();
    final todayPlus7 = today.add(const Duration(days: 7));

    // 2. active (end_date > today + 7)
    final hasActive = _allMemberships.any((m) {
      if (m['status'] != 'active') return false;
      if (m['end_date'] == null) return false;
      try {
        final endDate = DateTime.parse(m['end_date']);
        return endDate.isAfter(todayPlus7);
      } catch (_) {
        return false;
      }
    });
    if (hasActive) return MemberState.active;

    // 3. expiringSoon (end_date between today and today + 7)
    final hasExpiringSoon = _allMemberships.any((m) {
      if (m['status'] != 'active') return false;
      if (m['end_date'] == null) return false;
      try {
        final endDate = DateTime.parse(m['end_date']);
        return endDate.isAfter(today) && !endDate.isAfter(todayPlus7);
      } catch (_) {
        return false;
      }
    });
    if (hasExpiringSoon) return MemberState.expiringSoon;

    // 4. expired (end_date < today or status = 'expired')
    final hasExpired = _allMemberships.any((m) {
      if (m['status'] == 'expired') return true;
      if (m['status'] == 'active' && m['end_date'] != null) {
        try {
          final endDate = DateTime.parse(m['end_date']);
          return endDate.isBefore(today);
        } catch (_) {
          return false;
        }
      }
      return false;
    });
    if (hasExpired) return MemberState.expired;

    // 5. hold
    final hasHold = _allMemberships.any((m) => m['status'] == 'hold');
    if (hasHold) return MemberState.onHold;

    // 6. applicationPending
    if (_pendingRequest != null) {
      return MemberState.applicationPending;
    }

    // 7. exited
    final hasExited = _allMemberships.any((m) => m['status'] == 'exited');
    if (hasExited) return MemberState.exited;

    // 8. profileCompleteNoLib
    return MemberState.profileCompleteNoLib;
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
    if (state == MemberState.active || state == MemberState.trial || state == MemberState.expiringSoon) {
      return true;
    }
    if (state == MemberState.expired) {
      final expiredM = _allMemberships.firstWhere(
        (m) => m['status'] == 'expired' || (m['status'] == 'active' && m['end_date'] != null && DateTime.parse(m['end_date']).isBefore(DateTime.now())),
        orElse: () => {},
      );
      if (expiredM.isNotEmpty) {
        final lib = expiredM['libraries'] as Map<String, dynamic>? ?? {};
        final rawRules = lib['rules_metadata'] ?? lib['rules'];
        Map<String, dynamic> rules = {};
        if (rawRules is Map) {
          rules = Map<String, dynamic>.from(rawRules);
        } else if (rawRules is String) {
          try {
            rules = Map<String, dynamic>.from(jsonDecode(rawRules));
          } catch (_) {}
        }
        return rules['allow_expired_checkin'] == true;
      }
    }
    return false;
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
      case MemberState.freshInstall:
        return _buildFreshState();
      case MemberState.profileCompleteNoLib:
        return _buildProfileCompleteNoLibState();
      case MemberState.applicationPending:
        return _buildApplicationPendingState();
      case MemberState.trial:
        return _buildTrialState();
      case MemberState.active:
        return _buildActiveState();
      case MemberState.expiringSoon:
        return _buildExpiringSoonState();
      case MemberState.expired:
        return _buildExpiredState();
      case MemberState.onHold:
        return _buildOnHoldState();
      case MemberState.exited:
        return _buildExitedState();
    }
  }

  // CURVED HEADERS FOR STAGES
  Widget _buildCurvedHeader({required String greeting, required String subtitle, required MemberState state, bool showLogo = true}) {
    final unreadCount = _announcements.where((a) => !_readAnnouncementIds.contains(a['id'])).length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: _getHeaderGradient(state),
        borderRadius: const BorderRadius.only(
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

  // STAGE 1: FRESH INSTALL (profile incomplete)
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
              greeting: "Welcome to SILENCE 👋",
              subtitle: "Let's get you set up",
              state: MemberState.freshInstall,
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Setup progress card
                  _buildSetupProgressCard(
                    title: "Set Up Your Account",
                    activeStep: 1,
                    stepTitles: [
                      "Complete your profile",
                      "Find a library",
                      "Apply and get your seat"
                    ],
                    stepCompleted: [false, false, false],
                    onButtonTap: _navigateToEditProfile,
                    buttonText: "Complete Profile Now",
                  ),
                  const SizedBox(height: 16),
                  
                  // Dashed membership placeholder
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.badge_outlined, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text(
                          'Your library membership will appear here',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500], fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Why SILENCE Card
                  _buildHowItWorksCard(),
                  const SizedBox(height: 24),

                  // Nearby Libraries preview
                  if (nearLibs.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Libraries Near You',
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                        ),
                        TextButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please complete your profile first.')),
                            );
                          },
                          child: Text('View all', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFE65C00), fontWeight: FontWeight.bold)),
                        )
                      ],
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
              greeting: "${_getGreetingTime()}, ${_getGreetingName()} 👋",
              subtitle: "Find a study library near you",
              state: MemberState.profileCompleteNoLib,
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Setup progress card
                  _buildSetupProgressCard(
                    title: "Almost there!",
                    activeStep: 2,
                    stepTitles: [
                      "Profile complete ✓",
                      "Join a library",
                      "Get your seat"
                    ],
                    stepCompleted: [true, false, false],
                    onButtonTap: () {
                      Navigator.pushNamed(context, '/member/explore').then((_) => _loadInitialData());
                    },
                    buttonText: "Find a Library Now",
                  ),
                  const SizedBox(height: 16),

                  // Dashed placeholder card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.business, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text(
                          'No library joined yet',
                          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500], fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/member/explore').then((_) => _loadInitialData());
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE65C00),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Find a Library'),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Nearby libraries preview
                  if (nearLibs.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Libraries Near You',
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/member/explore').then((_) => _loadInitialData());
                          },
                          child: Text('View all', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFE65C00), fontWeight: FontWeight.bold)),
                        )
                      ],
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

  // STAGE 3: APPLICATION PENDING
  Widget _buildApplicationPendingState() {
    final nearLibs = _getNearLibraries();
    final libraryId = _pendingRequest?['library_id'] ?? '';

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: const Color(0xFFE65C00),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCurvedHeader(
              greeting: "Hang tight, ${_getGreetingName()} ⏳",
              subtitle: "Your application is under review",
              state: MemberState.applicationPending,
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildApplicationPendingCard(),
                  const SizedBox(height: 16),

                  // What to expect card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7), // light amber bg
                      borderRadius: BorderRadius.circular(12),
                      border: const Border(left: BorderSide(color: Color(0xFFD97706), width: 4)),
                    ),
                    child: Text(
                      'SILENCE Admins usually review and approve pending seat applications within 24 hours. Once approved, your membership card and QR check-in will become active.',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFB45309), height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Contact library button
                  if (libraryId.isNotEmpty) ...[
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LibraryQueryScreen(
                              libraryId: libraryId,
                              preFilledMessage: 'Hello, I submitted my application for your library and wanted to check if you need any additional documents. Thank you!',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.mail_outline),
                      label: const Text('Contact Library Admin'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE65C00),
                        side: const BorderSide(color: Color(0xFFE65C00)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Explore libraries list preview
                  if (nearLibs.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Explore Study Zones',
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/member/explore').then((_) => _loadInitialData());
                          },
                          child: Text('View all', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFE65C00), fontWeight: FontWeight.bold)),
                        )
                      ],
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

  // STAGE 4: ACTIVE MEMBER (normal)
  Widget _buildActiveState() {
    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: const Color(0xFFE65C00),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCurvedHeader(
              greeting: "${_getGreetingTime()}, ${_getGreetingName()} 👋",
              subtitle: "Track your study progress",
              state: MemberState.active,
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Membership cards
                  ..._myMemberships.map((m) => _buildMembershipCard(m, MemberState.active)),
                  const SizedBox(height: 16),

                  // Today's attendance card
                  _buildTodayAttendanceCard(),
                  const SizedBox(height: 16),

                  // Streak card
                  _buildStreakCard(),
                  const SizedBox(height: 16),

                  // Quick actions row
                  _buildQuickActionsRow(),
                  const SizedBox(height: 24),

                  // Announcements
                  if (_announcements.isNotEmpty) ...[
                    Text(
                      'Announcements',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 10),
                    _buildAnnouncementsSection(),
                    const SizedBox(height: 24),
                  ],

                  // Recent Activities
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

  // STAGE 5: TRIAL MEMBER
  Widget _buildTrialState() {
    final trialMembership = _allMemberships.firstWhere((m) => m['status'] == 'trial', orElse: () => {});
    if (trialMembership.isEmpty) return const SizedBox.shrink();
    
    int trialDaysLeft = 0;
    if (trialMembership['end_date'] != null) {
      try {
        trialDaysLeft = DateTime.parse(trialMembership['end_date']).difference(DateTime.now()).inDays;
        if (trialDaysLeft < 0) trialDaysLeft = 0;
      } catch (_) {}
    }

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: const Color(0xFFE65C00),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCurvedHeader(
              greeting: "${_getGreetingTime()}, ${_getGreetingName()} ✨",
              subtitle: "Trial ends in $trialDaysLeft days",
              state: MemberState.trial,
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMembershipCard(trialMembership, MemberState.trial),
                  const SizedBox(height: 16),

                  _buildTrialProgressCard(trialMembership),
                  const SizedBox(height: 16),

                  if (trialDaysLeft <= 3) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF5FF), // light purple bg
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.purple[200]!),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star, color: Color(0xFF7C3AED), size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Don\'t lose your progress!', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF5B21B6))),
                                const SizedBox(height: 2),
                                InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => RenewalScreen(
                                          libraryId: trialMembership['library_id'],
                                          initialPlan: 'monthly',
                                          initialShiftId: trialMembership['shift_id'],
                                        ),
                                      ),
                                    ).then((_) => _loadInitialData());
                                  },
                                  child: Text(
                                    'Choose a Plan Now →',
                                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF7C3AED), fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                  ),
                                )
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  _buildTodayAttendanceCard(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // STAGE 6: EXPIRING SOON (<=7 days left)
  Widget _buildExpiringSoonState() {
    final expiringM = _allMemberships.firstWhere((m) => m['status'] == 'active', orElse: () => {});
    if (expiringM.isEmpty) return const SizedBox.shrink();
    
    int daysLeft = 0;
    if (expiringM['end_date'] != null) {
      try {
        daysLeft = DateTime.parse(expiringM['end_date']).difference(DateTime.now()).inDays;
        if (daysLeft < 0) daysLeft = 0;
      } catch (_) {}
    }

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: const Color(0xFFE65C00),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCurvedHeader(
              greeting: "Hey ${_getGreetingName()}, renew soon ⏰",
              subtitle: "Only $daysLeft days left on your plan",
              state: MemberState.expiringSoon,
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Urgency Banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7), // amber bg
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Plan expiring in $daysLeft days. Renew now to keep your seat.',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFB45309)),
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  _buildMembershipCard(expiringM, MemberState.expiringSoon),
                  const SizedBox(height: 16),

                  _buildQuickRenewalPills(expiringM['library_id']),
                  const SizedBox(height: 16),

                  _buildTodayAttendanceCard(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // STAGE 7: EXPIRED
  Widget _buildExpiredState() {
    final expiredM = _allMemberships.firstWhere(
      (m) => m['status'] == 'expired' || (m['status'] == 'active' && m['end_date'] != null && DateTime.parse(m['end_date']).isBefore(DateTime.now())),
      orElse: () => {},
    );
    if (expiredM.isEmpty) return const SizedBox.shrink();

    final lib = expiredM['libraries'] as Map<String, dynamic>? ?? {};
    final rawRules = lib['rules_metadata'] ?? lib['rules'];
    Map<String, dynamic> rules = {};
    if (rawRules is Map) {
      rules = Map<String, dynamic>.from(rawRules);
    } else if (rawRules is String) {
      try {
        rules = Map<String, dynamic>.from(jsonDecode(rawRules));
      } catch (_) {}
    }
    final bool allowScan = rules['allow_expired_checkin'] == true;
    final graceDays = rules['grace_days'] as int? ?? 3;

    final seat = expiredM['seats'] as Map<String, dynamic>? ?? {};
    final seatLabel = seat.isNotEmpty ? (seat['seat_label'] ?? 'Seat') : 'your seat';

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: const Color(0xFFE65C00),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCurvedHeader(
              greeting: "Membership Expired ❌",
              subtitle: "Renew to continue studying",
              state: MemberState.expired,
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMembershipCard(expiredM, MemberState.expired),
                  const SizedBox(height: 16),

                  // Scanning status banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: allowScan ? const Color(0xFFFFF3ED) : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: allowScan ? const Color(0xFFFCD34D) : const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          allowScan ? Icons.qr_code_scanner : Icons.block,
                          color: allowScan ? const Color(0xFFD97706) : const Color(0xFFDC2626),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            allowScan
                                ? '📱 You can still scan QR. Renew soon to secure your seat.'
                                : '⛔ QR check-in blocked. Renew to check in again.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: allowScan ? const Color(0xFFB45309) : const Color(0xFF991B1B),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Renewal nudge card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('💡 Renew to keep your seat', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text(
                          'Your seat $seatLabel is currently reserved. After the admin\'s grace period ($graceDays days), it may be assigned to another student.',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600], height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RenewalScreen(
                                  libraryId: expiredM['library_id'],
                                  initialPlan: 'monthly',
                                  initialShiftId: expiredM['shift_id'],
                                ),
                              ),
                            ).then((_) => _loadInitialData());
                          },
                          child: Text(
                            'Choose Renewal Plan →',
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFE65C00), fontWeight: FontWeight.bold),
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Today's attendance (only if allowed)
                  if (allowScan)
                    _buildTodayAttendanceCard()
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: [
                          Icon(Icons.lock, color: Colors.grey[300], size: 48),
                          const SizedBox(height: 12),
                          Text('Check-in is blocked', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.grey[700])),
                          Text('Renew your plan to resume checking in.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[550])),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => RenewalScreen(
                                    libraryId: expiredM['library_id'],
                                  ),
                                ),
                              ).then((_) => _loadInitialData());
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                            child: const Text('Renew Plan Now'),
                          )
                        ],
                      ),
                    ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // STAGE 8: ON HOLD
  Widget _buildOnHoldState() {
    final holdM = _allMemberships.firstWhere((m) => m['status'] == 'hold', orElse: () => {});
    if (holdM.isEmpty) return const SizedBox.shrink();

    String resumeDate = 'soon';
    if (holdM['end_date'] != null) {
      try {
        final dt = DateTime.parse(holdM['end_date']);
        resumeDate = DateFormat('dd MMM yyyy').format(dt);
      } catch (_) {}
    }

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: const Color(0xFFE65C00),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCurvedHeader(
              greeting: "Membership on Pause ⏸",
              subtitle: "Resumes on $resumeDate",
              state: MemberState.onHold,
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMembershipCard(holdM, MemberState.onHold),
                  const SizedBox(height: 16),

                  // Hold Info Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED), // light amber bg
                      borderRadius: BorderRadius.circular(16),
                      border: const Border(left: BorderSide(color: Color(0xFFB45309), width: 4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Membership Paused Info', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFB45309))),
                        const SizedBox(height: 8),
                        _buildHoldBulletInfo('Your assigned seat is reserved for you.'),
                        const SizedBox(height: 6),
                        _buildHoldBulletInfo('Billing is paused and plan expiration is extended.'),
                        const SizedBox(height: 6),
                        _buildHoldBulletInfo('QR Scanner Check-in is NOT available during holds.'),
                        const SizedBox(height: 12),
                        Text(
                          'Come back on $resumeDate to resume studying.',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF78350F)),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (_announcements.isNotEmpty) ...[
                    Text(
                      'Announcements',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 10),
                    _buildAnnouncementsSection(),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHoldBulletInfo(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.circle, size: 6, color: Color(0xFFB45309)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF92400E)))),
      ],
    );
  }

  // STAGE 9: EXITED
  Widget _buildExitedState() {
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
              greeting: "Welcome back, ${_getGreetingName()} 👋",
              subtitle: "Ready to study again?",
              state: MemberState.exited,
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Previous Exited Membership Card (muted/grayed out)
                  if (_pastMemberships.isNotEmpty) ...[
                    Opacity(
                      opacity: 0.8,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: const Border(left: BorderSide(color: Color(0xFF9CA3AF), width: 4)), // gray
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Previous Membership',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[400]),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              lastLibName,
                              style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Exited: $exitDateStr • Member for $durationMonths month${durationMonths > 1 ? 's' : ''}',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.check_circle_outline, color: Color(0xFF22C55E), size: 16),
                                const SizedBox(width: 6),
                                Text('History & streaks preserved', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF16A34A), fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            
                            Row(
                              children: [
                                Expanded(
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
                                    ),
                                    child: Text('Rejoin This Library', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () {
                                      Navigator.pushNamed(context, '/member/explore').then((_) => _loadInitialData());
                                    },
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Color(0xFFE65C00)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    child: Text('Find New', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Find your next study library CTA
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.orange[200]!, style: BorderStyle.solid),
                    ),
                    child: Column(
                      children: [
                        Text('Find your next study library', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/member/explore').then((_) => _loadInitialData());
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE65C00),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Find a Library →'),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Lifetime stats card
                  InkWell(
                    onTap: () {
                      setState(() => _currentBottomTab = 1); // Analytics
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Lifetime Progress', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatColumn('${_totalStudyHours.toStringAsFixed(1)}h', 'Total Hours'),
                              ),
                              Container(width: 1, height: 32, color: Colors.grey[200]),
                              Expanded(
                                child: _buildStatColumn('$_daysPresent', 'Present Days'),
                              ),
                              Container(width: 1, height: 32, color: Colors.grey[200]),
                              Expanded(
                                child: _buildStatColumn('$_bestStreak d', 'Best Streak'),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Nearby libraries preview
                  if (suggested.isNotEmpty) ...[
                    Text(
                      'Suggested Study Libraries',
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

  Widget _buildStatColumn(String val, String label) {
    return Column(
      children: [
        Text(val, style: GoogleFonts.spaceMono(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
      ],
    );
  }

  Widget _buildSetupProgressCard({
    required String title,
    required int activeStep,
    required List<String> stepTitles,
    required List<bool> stepCompleted,
    required VoidCallback onButtonTap,
    required String buttonText,
  }) {
    final progress = activeStep / stepTitles.length;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: const Border(left: BorderSide(color: Color(0xFFE65C00), width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
              Text('Step $activeStep of ${stepTitles.length}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[200],
              color: const Color(0xFFE65C00),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(stepTitles.length, (index) {
            final isCompleted = stepCompleted[index];
            final isActive = index == activeStep - 1;
            
            Widget leadingIcon;
            if (isCompleted) {
              leadingIcon = const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 20);
            } else if (isActive) {
              leadingIcon = Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(color: Color(0xFFFFF3ED), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Color(0xFFE65C00), shape: BoxShape.circle),
                ),
              );
            } else {
              leadingIcon = Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(color: Colors.grey[200], shape: BoxShape.circle),
              );
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                children: [
                  leadingIcon,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      stepTitles[index],
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: isActive || isCompleted ? FontWeight.bold : FontWeight.normal,
                        color: isActive ? const Color(0xFFE65C00) : (isCompleted ? const Color(0xFF15803D) : Colors.grey[500]),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onButtonTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(buttonText, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildApplicationPendingCard() {
    if (_pendingRequest == null) return const SizedBox.shrink();
    
    final lib = _pendingRequest!['libraries'] as Map<String, dynamic>? ?? {};
    final libName = lib['name'] ?? 'SILENCE Library';
    final plan = _pendingRequest!['plan_type'] ?? 'monthly';
    final payment = _pendingRequest!['payment_method'] ?? 'cash';
    final createdAtStr = _pendingRequest!['created_at'] as String?;
    
    DateTime createdAt = DateTime.now();
    if (createdAtStr != null) {
      try {
        createdAt = DateTime.parse(createdAtStr);
      } catch (_) {}
    }
    
    // Assume 5 days validity
    final expiresAt = createdAt.add(const Duration(days: 5));
    final daysRemaining = expiresAt.difference(DateTime.now()).inDays;
    
    String planLabel = plan == 'monthly' ? 'Monthly' : plan == '3_month' ? '3-Month' : plan == '6_month' ? '6-Month' : 'Trial';
    String paymentLabel = payment == 'upi' ? 'UPI screenshot uploaded' : 'Cash payment declared';
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: const Border(left: BorderSide(color: Color(0xFFF59E0B), width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('APPLICATION SUBMITTED', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 1)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
                child: Text('Pending', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFD97706))),
              )
            ],
          ),
          const SizedBox(height: 12),
          Text(libName, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
          const SizedBox(height: 8),
          Text('Plan: $planLabel | Method: $paymentLabel', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 16),
          
          // Progress indicator step 2 of 3
          Row(
            children: [
              const Icon(Icons.payment, color: Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Step 2 of 3: Payment & admin review',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFD97706)),
                ),
              ),
            ],
          ),
          
          if (daysRemaining <= 2) ...[
            const SizedBox(height: 12),
            Text(
              '⚠️ Application expires in $daysRemaining days',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFD97706)),
            ),
          ],
          const Divider(height: 24),
          
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: () => _confirmWithdrawApplication(_pendingRequest!['id']),
              child: Text(
                'Withdraw Application',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.redAccent),
              ),
            ),
          )
        ],
      ),
    );
  }

  void _confirmWithdrawApplication(String requestId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Withdraw Application', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to withdraw your join request? This cannot be undone.', style: GoogleFonts.inter()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              try {
                final supabase = Supabase.instance.client;
                await supabase.from('join_requests').delete().eq('id', requestId);
                if (mounted) {
                  _loadInitialData();
                }
                messenger.showSnackBar(
                  const SnackBar(content: Text('Application withdrawn successfully.')),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: Text('Withdraw', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildTrialProgressCard(Map<String, dynamic> membership) {
    final seat = membership['seats'] as Map<String, dynamic>? ?? {};
    final seatLabel = seat.isNotEmpty ? (seat['seat_label'] ?? 'Seat') : 'Pending';
    
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3E8FF), // light purple bg
        borderRadius: BorderRadius.circular(16),
        border: const Border(left: BorderSide(color: Color(0xFF7C3AED), width: 4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TRIAL PROGRESS', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF7C3AED), letterSpacing: 1)),
          const SizedBox(height: 12),
          _buildTrialBullet('Reserved Seat: $seatLabel'),
          const SizedBox(height: 8),
          _buildTrialBullet('$_daysPresent study sessions completed'),
          const SizedBox(height: 8),
          _buildTrialBullet('${_totalStudyHours.toStringAsFixed(1)} total study hours'),
          const SizedBox(height: 12),
          Text(
            '⏳ Pay before trial ends to keep seat',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFD97706)),
          ),
        ],
      ),
    );
  }

  Widget _buildTrialBullet(String text) {
    return Row(
      children: [
        const Icon(Icons.check_circle_outline, color: Color(0xFF7C3AED), size: 18),
        const SizedBox(width: 8),
        Text(text, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF5B21B6), fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildQuickRenewalPills(String libraryId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Renew Options',
          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildRenewalPill(libraryId, 'monthly', 'Monthly', '₹1,500'),
            const SizedBox(width: 8),
            _buildRenewalPill(libraryId, '3_month', '3-Month', '₹4,000'),
            const SizedBox(width: 8),
            _buildRenewalPill(libraryId, '6_month', '6-Month', '₹7,500'),
          ],
        ),
      ],
    );
  }

  Widget _buildRenewalPill(String libraryId, String planKey, String label, String price) {
    return Expanded(
      child: OutlinedButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RenewalScreen(
                libraryId: libraryId,
                initialPlan: planKey,
              ),
            ),
          ).then((_) => _loadInitialData());
        },
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFF59E0B)),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: Colors.white,
        ),
        child: Column(
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFB45309))),
            Text(price, style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[650])),
          ],
        ),
      ),
    );
  }

  String _getGreetingName() {
    final nickname = _userProfile?['nickname'] as String?;
    return (nickname != null && nickname.isNotEmpty && nickname != 'N/A')
        ? nickname
        : (_userProfile?['full_name'] ?? 'Student');
  }

  String _getGreetingTime() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  LinearGradient _getHeaderGradient(MemberState state) {
    switch (state) {
      case MemberState.freshInstall:
      case MemberState.profileCompleteNoLib:
      case MemberState.active:
        return const LinearGradient(
          colors: [Color(0xFFE65C00), Color(0xFFC44E00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case MemberState.applicationPending:
      case MemberState.expiringSoon:
        return const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case MemberState.trial:
        return const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case MemberState.expired:
        return const LinearGradient(
          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case MemberState.onHold:
        return const LinearGradient(
          colors: [Color(0xFFD97706), Color(0xFFB45309)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case MemberState.exited:
        return const LinearGradient(
          colors: [Color(0xFF6B7280), Color(0xFF4B5563)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  // ==========================================
  // SHARED WIDGET BUILDERS
  // ==========================================

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

  Widget _buildMembershipCard(Map<String, dynamic> membership, MemberState state) {
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

    switch (state) {
      case MemberState.trial:
        borderColor = const Color(0xFF7C3AED); // purple
        statusLabel = 'Trial';
        break;
      case MemberState.active:
        borderColor = const Color(0xFF22C55E); // green
        statusLabel = 'Active';
        break;
      case MemberState.expiringSoon:
        borderColor = const Color(0xFFF59E0B); // amber
        statusLabel = 'Expiring Soon';
        break;
      case MemberState.expired:
        borderColor = const Color(0xFFEF4444); // red
        statusLabel = 'Expired';
        break;
      case MemberState.onHold:
        borderColor = const Color(0xFFEAB308); // yellow
        statusLabel = 'Hold';
        break;
      default:
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
        break;
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

    Widget buildButtons() {
      switch (state) {
        case MemberState.trial:
          return Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RenewalScreen(
                          libraryId: library['id'] ?? '',
                          initialShiftId: shift['id'],
                          initialPlan: 'monthly',
                        ),
                      ),
                    ).then((_) => _loadInitialData());
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(color: borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Choose a Plan →', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: borderColor)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LibraryQueryScreen(
                          libraryId: library['id'] ?? '',
                          preFilledMessage: 'Hello, I have a query about my trial membership.',
                        ),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(color: borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Contact Library', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: borderColor)),
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
          );
        case MemberState.expiringSoon:
          return Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RenewalScreen(
                          libraryId: library['id'] ?? '',
                          initialShiftId: shift['id'],
                          initialPlan: membership['plan_type'],
                        ),
                      ),
                    ).then((_) => _loadInitialData());
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(color: borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Renew Now →', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: borderColor)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openSeatChangeSheet(membership),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(color: borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Seat Chg', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: borderColor)),
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
          );
        case MemberState.expired:
          return Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RenewalScreen(
                          libraryId: library['id'] ?? '',
                          initialShiftId: shift['id'],
                          initialPlan: membership['plan_type'],
                        ),
                      ),
                    ).then((_) => _loadInitialData());
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(color: borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Renew Immediately →', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: borderColor)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LibraryQueryScreen(
                          libraryId: library['id'] ?? '',
                          preFilledMessage: 'Hello, I have a query about my expired membership.',
                        ),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(color: borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Contact Library', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: borderColor)),
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
          );
        case MemberState.onHold:
          return Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LibraryQueryScreen(
                          libraryId: library['id'] ?? '',
                          preFilledMessage: 'Hello, I have a query about my paused membership.',
                        ),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(color: borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Contact Library', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: borderColor)),
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
          );
        case MemberState.active:
        default:
          return Row(
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
          );
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
          buildButtons(),
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
      onSwitchTab: (index) {
        setState(() => _currentBottomTab = index);
      },
    );
  }

  // ==========================================
  // TAB 3: PROFILE TAB
  // ==========================================
  Widget _buildProfileTab() {
    return MemberProfileTab(
      onSwitchTab: (index) {
        setState(() {
          _currentBottomTab = index;
        });
      },
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
                            
                            final navigator = Navigator.of(context);
                            final messenger = ScaffoldMessenger.of(context);
                            
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
                              
                              navigator.pop();
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Hold Request submitted! ✓')),
                              );
                            } catch (e) {
                              messenger.showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
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
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
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
                          
                          navigator.pop();
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Successfully exited library. ✓')),
                          );
                          if (mounted) {
                            _loadInitialData();
                          }
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
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
                    
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    
                    try {
                      final supabase = Supabase.instance.client;
                      final libRes = await supabase
                          .from('libraries')
                          .select()
                          .eq('library_code', code)
                          .maybeSingle();
                      
                      if (libRes == null) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Library not found. Check code prefix or suffix.')),
                        );
                        return;
                      }
                      
                      navigator.pop();
                      navigator.push(
                        MaterialPageRoute(
                          builder: (context) => LibraryPublicProfileScreen(
                            libraryId: libRes['id'],
                            isAdmin: false,
                            showProceedButton: true,
                          ),
                        ),
                      ).then((_) {
                        if (mounted) {
                          _loadInitialData();
                        }
                      });
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Error finding library: $e')),
                      );
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
