import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../core/offline_sync.dart';
import '../core/cache_service.dart';
import '../utils/time_utils.dart';
import '../services/notification_service.dart';
import '../utils/holiday_service.dart';
import '../utils/error_messages.dart';
import '../widgets/states/states.dart';
import 'reservations/qr_scanner_screen.dart';
import 'reservations/join_flow_screen.dart';
import 'member_profile_edit.dart';
import 'member_analytics_tab.dart';
import 'library_public_profile_screen.dart';
import 'member_history_tab.dart';
import '../widgets/seat_change_bottom_sheet.dart';
import 'reservations/renewal_screen.dart';
import 'reservations/library_query_screen.dart';
import 'member_profile_tab.dart';
import 'notifications_screen.dart';
import 'contact_admin_screen.dart';

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
  // True when the load failed (offline) but we rendered from cached memberships.
  bool _isOfflineCached = false;

  // Domain data
  Map<String, dynamic>? _userProfile;
  List<Map<String, dynamic>> _myMemberships = [];
  List<Map<String, dynamic>> _pastMemberships = [];
  List<Map<String, dynamic>> _allMemberships = [];
  Map<String, dynamic>? _pendingRequest;
  // Most recent join request that was rejected by an admin — surfaced (with the
  // reason + re-apply) when the member has no membership and no pending request.
  Map<String, dynamic>? _rejectedRequest;
  List<Map<String, dynamic>> _announcements = [];
  Set<String> _readAnnouncementIds = {};
  int _unreadNotifications = 0; // unread rows in notifications table (header bell badge)
  Map<String, dynamic>? _activeAttendance;
  Map<String, dynamic>? _lastCompletedAttendance;
  
  // Explore list in cache
  List<Map<String, dynamic>> _exploreLibraries = [];
  
  // Attendance Live Ticker (ValueNotifiers for UI updates without full screen rebuilds)
  final ValueNotifier<Duration> _sessionDurationNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _shiftRemainingNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<double> _shiftProgressNotifier = ValueNotifier(0.0);

  // Session data
  bool _isCheckedIn = false;
  bool _hasSessionEndedToday = false;
  bool _shiftEndedWithoutCheckin = false;
  DateTime? _checkInTime;
  DateTime? _checkOutTime;
  Duration _sessionDuration = Duration.zero;

  int _streak = 0;
  int _shiftEndHour = 14;

  // Previous session (for small extra card)
  Map<String, dynamic>? _previousSession;

  // Today's holiday per joined library (libraryId -> Holiday). Empty = open.
  Map<String, Holiday> _todayHolidays = {};

  // Timer
  Timer? _sessionTimer;
  // Client-side overtime handling for the live session: warn the member when
  // their shift ends, and (if the library allows it) auto-check-out 30 min later
  // so the timer stops immediately instead of waiting for the 5-min server cron.
  String? _timerSessionId;       // attendance id the flags below belong to
  bool _shiftEndWarnSent = false;
  bool _autoCheckoutSent = false;
  bool _autoCheckoutOvertime = true; // library setting (default on)
  // Realtime: refresh when THIS member's own rows change (approval, check-in,
  // notification) so the home screen updates without a manual pull-to-refresh.
  RealtimeChannel? _realtimeChannel;
  Timer? _realtimeDebounce;
  
  // Cache of all study dates (for streak calculation)
  Set<String> _studyDates = {};

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
    _checkRoleGuard();
    _loadCachedLibraries();
    _hydrateFromCacheThenLoad();

    // Start listening for internet status to sync offline scans
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OfflineSyncManager.instance.startListening(context);
    });

    _setupRealtime();
  }

  /// Subscribe to changes on this member's own memberships / attendance /
  /// notifications and refresh (debounced). Requires the tables to be in the
  /// `supabase_realtime` publication — see migrations/2026-06-16_enable_realtime.sql.
  void _setupRealtime() {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;
    _realtimeChannel?.unsubscribe();

    void onChange(_) {
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 700), () {
        if (mounted) _loadInitialData();
      });
    }

    _realtimeChannel = supabase
        .channel('member_home_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'memberships',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'member_id', value: user.id),
          callback: onChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'member_id', value: user.id),
          callback: onChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: user.id),
          callback: onChange,
        )
        .subscribe();
  }

  Future<void> _checkRoleGuard() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user != null) {
        final userData = await supabase.from('users').select('role').eq('id', user.id).maybeSingle();
        if (userData != null && userData['role'] == 'admin') {
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/admin/home');
          }
        }
      }
    } catch (e) {
      debugPrint('Member role guard check error: $e');
    }
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _realtimeDebounce?.cancel();
    _realtimeChannel?.unsubscribe();
    _sessionDurationNotifier.dispose();
    _shiftRemainingNotifier.dispose();
    _shiftProgressNotifier.dispose();
    OfflineSyncManager.instance.stopListening();
    super.dispose();
  }

  Future<void> _loadCachedLibraries() async {
    try {
      final cached = await CacheService.instance
          .readCacheFresh('explore_libraries_list', const Duration(hours: 24));
      if (cached != null && cached is List) {
        if (mounted) {
          setState(() {
            _exploreLibraries = List<Map<String, dynamic>>.from(cached);
          });
        }
      }
    } catch (_) {}
  }

  /// Render instantly from cached profile/memberships, then refresh in the
  /// background. Avoids a full-screen skeleton on app open when we already have
  /// data cached from a previous session (stale-while-revalidate).
  Future<void> _hydrateFromCacheThenLoad() async {
    final used = await _loadFromCache();
    if (used && mounted) {
      setState(() {}); // paint the cached membership card immediately
    }
    await _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    debugPrint('[Home Refresh Audit] Attendance reload initiated');
    if (!mounted) return;
    // Stale-while-revalidate: only blank to the full-screen skeleton when there
    // is nothing to show yet. Refreshes (navigation-return, pull-to-refresh)
    // keep the current content visible and reload silently.
    final hasContent = _userProfile != null ||
        _myMemberships.isNotEmpty ||
        _pendingRequest != null;
    setState(() {
      if (!hasContent) _isLoading = true;
      _errorMessage = null;
      _isOfflineCached = false;
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

      final rejectedReqFuture = supabase
          .from('join_requests')
          .select('*, libraries(*)')
          .eq('member_id', currentUser.id)
          .eq('status', 'rejected')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final membershipsFuture = supabase
          .from('memberships')
          .select('*, libraries(*), shifts(*), seats(*)')
          .eq('member_id', currentUser.id)
          .order('created_at', ascending: false);

      final attendanceFuture = supabase
          .from('attendance')
          .select('*, memberships(*, seats(*)), shifts(*), libraries(*)')
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

      // Latest confirmed payment per membership → real price for the card
      // (the plan-price columns can be 0/null, which showed a dishonest ₹0).
      final paymentsFuture = supabase
          .from('payments')
          .select('membership_id, amount, status, payment_date')
          .eq('member_id', currentUser.id)
          .order('payment_date', ascending: false);

      final results = await Future.wait([
        profileFuture,
        pendingReqsFuture,
        membershipsFuture,
        attendanceFuture,
        lastCompletedFuture,
        exploreFuture,
        rejectedReqFuture,
        paymentsFuture,
      ]);

      if (!mounted) return;

      _userProfile = results[0] as Map<String, dynamic>?;

      // Account scheduled for deletion → freeze (block dashboard).
      if (_userProfile?['scheduled_for_deletion'] == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/account-frozen', (r) => false);
          }
        });
        return;
      }
      
      final pendingReqs = List<Map<String, dynamic>>.from(results[1] as List? ?? []);
      _pendingRequest = pendingReqs.isNotEmpty ? pendingReqs.first : null;
      _rejectedRequest = results[6] as Map<String, dynamic>?;

      final allMemberships = List<Map<String, dynamic>>.from(results[2] as List? ?? []);
      // Attach each membership's latest confirmed payment amount (honest price).
      final paymentRows = List<Map<String, dynamic>>.from(results[7] as List? ?? []);
      final Map<String, int> paidByMembership = {};
      for (final p in paymentRows) {
        final mid = p['membership_id']?.toString();
        if (mid == null) continue;
        final status = (p['status'] ?? '').toString();
        if (status == 'rejected') continue; // ignore rejected payments
        // Rows are newest-first, so the first one we see per membership wins.
        paidByMembership.putIfAbsent(mid, () => (p['amount'] as num? ?? 0).toInt());
      }
      for (final m in allMemberships) {
        final mid = m['id']?.toString();
        if (mid != null && paidByMembership.containsKey(mid)) {
          m['_paid_amount'] = paidByMembership[mid];
        }
      }
      _allMemberships = allMemberships;
      // Cache memberships + profile so the card still renders when offline.
      CacheService.instance.writeCache('member_memberships', allMemberships);
      if (_userProfile != null) {
        CacheService.instance.writeCache('member_profile', _userProfile);
      }

      _activeAttendance = results[3] as Map<String, dynamic>?;
      _lastCompletedAttendance = results[4] as Map<String, dynamic>?;
      debugPrint('[Home Refresh Audit] Attendance reload completed. Active attendance: $_activeAttendance, Last completed: $_lastCompletedAttendance');
      
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

      await _determineCurrentState();

      CacheService.instance.writeCacheTimed('explore_libraries_list', _exploreLibraries);

      // ── Non-critical extras (announcements, streak, activity feed) ─────────
      // Wrapped separately so a failure here NEVER discards the core profile /
      // memberships / state already loaded above (previously any error dropped
      // the whole screen to stale cache).
      try {
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
            .gte('sent_at', DateTime.now().toUtc().subtract(const Duration(hours: 24)).toIso8601String())
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

      // Unread in-app notifications (header bell badge).
      try {
        final notifRes = await supabase
            .from('notifications')
            .select('id')
            .eq('user_id', currentUser.id)
            .isFilter('read_at', null);
        _unreadNotifications = (notifRes as List).length;
      } catch (_) {
        _unreadNotifications = 0;
      }

      // Today's holidays for joined libraries (range-aware). Drives the
      // member dashboard "Closed today" state + disabled check-in.
      _todayHolidays = {};
      if (joinedLibIds.isNotEmpty) {
        try {
          final todayStr = istTodayKey();
          final closureRes = await supabase
              .from('scheduled_closures')
              .select('library_id, reason, start_date, end_date')
              .inFilter('library_id', joinedLibIds)
              .lte('start_date', todayStr)
              .gte('end_date', todayStr);
          for (final row in List<Map<String, dynamic>>.from(closureRes)) {
            final h = Holiday.fromRow(row);
            _todayHolidays[h.libraryId] = h;
          }
        } catch (e) {
          debugPrint('member holiday fetch failed: $e');
        }
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
          // Bucket the study day in IST (not device-local) so streaks agree
          // regardless of device timezone (P8-01).
          studyDates.add(istDateKeyFromDb(checkIn));
          if (checkOut != null) {
            final inUtc = DateTime.parse(checkIn);
            final outUtc = DateTime.parse(checkOut);
            hoursSum += outUtc.difference(inUtc).inMinutes / 60.0;
          }
        }
      }
      _studyDates = studyDates;
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
        supabase.from('join_requests').select('created_at, status, plan_type, libraries(name)').eq('member_id', currentUser.id).order('created_at', ascending: false).limit(5),
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
          'action': 'Membership Hold',
          'details': 'Status: ${status.toString().toUpperCase()}',
          'location': libName,
          'color': status == 'approved' ? const Color(0xFF22C55E) : (status == 'rejected' ? const Color(0xFFEF4444) : const Color(0xFF3B82F6)),
        });
      }

      // Join / Renewal requests
      final jrList = List<Map<String, dynamic>>.from(activityFutures[4]);
      for (var jr in jrList) {
        final libName = jr['libraries']?['name'] ?? 'Library';
        final status = (jr['status'] ?? 'pending').toString();
        activities.add({
          'time': DateTime.parse(jr['created_at']),
          'action': status == 'approved'
              ? 'Membership Approved'
              : status == 'rejected'
                  ? 'Membership Request Rejected'
                  : 'Membership Request',
          'details': 'Status: ${status.toUpperCase()}',
          'location': libName,
          'color': status == 'approved'
              ? const Color(0xFF22C55E)
              : (status == 'rejected' ? const Color(0xFFEF4444) : const Color(0xFF3B82F6)),
        });
      }

      activities.sort((a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime));
      _recentActivities = activities.take(15).toList();
      } catch (eNonCritical) {
        debugPrint('Non-critical home data (announcements/streak/activities) failed: $eNonCritical');
      }

    } catch (e) {
      debugPrint('Error loading member home data: $e');
      // Offline (or transient network) → try to render from cache instead of a
      // blocking error screen. Only fall back to the error state if we have no
      // cached membership to show.
      final usedCache = await _loadFromCache();
      if (usedCache) {
        _isOfflineCached = true;
        _errorMessage = null;
      } else {
        _errorMessage = friendlyError(e);
      }
    } finally {
      debugPrint('[HOME] Attendance reload complete');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Populates the home from locally cached membership/profile data. Returns
  /// true if a cached membership was found (so the card can render offline).
  Future<bool> _loadFromCache() async {
    try {
      final cachedProfile = await CacheService.instance.readCache('member_profile');
      if (cachedProfile is Map) {
        _userProfile = Map<String, dynamic>.from(cachedProfile);
      }
      final cached = await CacheService.instance.readCache('member_memberships');
      if (cached is! List || cached.isEmpty) return false;

      final all = cached
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      _allMemberships = all;
      _myMemberships = all
          .where((m) => ['active', 'trial', 'hold', 'expired'].contains(m['status']))
          .toList();
      _pastMemberships = all.where((m) => m['status'] == 'exited').toList();
      // We can't trust live attendance offline; show the not-checked-in card.
      _activeAttendance = null;
      _isCheckedIn = false;
      _stopSessionTimer();
      return _myMemberships.isNotEmpty;
    } catch (e) {
      debugPrint('Cache load failed: $e');
      return false;
    }
  }

  String formatShiftTimeString(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return 'N/A';
    try {
      final parts = timeStr.split(':');
      int hour = 0;
      int minute = 0;
      if (parts.length >= 2) {
        hour = int.tryParse(parts[0]) ?? 0;
        minute = int.tryParse(parts[1]) ?? 0;
      }
      final tempDt = DateTime(2026, 1, 1, hour, minute);
      return DateFormat('hh:mm a').format(tempDt);
    } catch (_) {
      return 'N/A';
    }
  }

  Future<void> _determineCurrentState() async {
    debugPrint('[HOME] _determineCurrentState() executing. Active session is: $_activeAttendance');
    if (_activeAttendance != null && _activeAttendance?['check_out_time'] == null && _activeAttendance?['check_in_time'] != null) {
      _isCheckedIn = true;
      _hasSessionEndedToday = false;
      _shiftEndedWithoutCheckin = false;
      
      final checkInStr = _activeAttendance!['check_in_time'] as String;
      _checkInTime = DateTime.parse(checkInStr);
      _checkOutTime = null;

      // Read the library's overtime auto-checkout setting (default ON).
      final lib = _activeAttendance!['libraries'] as Map<String, dynamic>?;
      _autoCheckoutOvertime = lib?['auto_checkout_overtime'] != false;

      final membership = _activeAttendance!['memberships'] as Map<String, dynamic>? ?? {};
      final shift = _activeAttendance!['shifts'] as Map<String, dynamic>? ?? membership['shifts'] as Map<String, dynamic>? ?? {};
      final shiftEndTimeStr = shift['end_time'] as String? ?? '14:00:00';
      final parts = shiftEndTimeStr.split(':');
      _shiftEndHour = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 14) : 14;
      
      _startSessionTimer();
    } else {
      _isCheckedIn = false;
      _checkInTime = null;
      _checkOutTime = null;
      _stopSessionTimer();

      await _fetchPreviousSession();
    }
    debugPrint('[Home Refresh Audit] Card state calculation: _isCheckedIn = $_isCheckedIn, _hasSessionEndedToday = $_hasSessionEndedToday, _shiftEndedWithoutCheckin = $_shiftEndedWithoutCheckin');
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _updateSessionTimerValues();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateSessionTimerValues();
    });
  }

  void _stopSessionTimer() {
    debugPrint('[Home Refresh Audit] Timer cancellation triggered');
    _sessionTimer?.cancel();
    _sessionTimer = null;
  }

  void _updateSessionTimerValues() {
    if (_checkInTime == null) return;

    // New session? reset the one-shot client guards.
    final sessionId = _activeAttendance?['id']?.toString();
    if (sessionId != _timerSessionId) {
      _timerSessionId = sessionId;
      _shiftEndWarnSent = false;
      _autoCheckoutSent = false;
    }

    final nowUtc = DateTime.now().toUtc();
    final checkInUtc = _checkInTime!.toUtc();
    
    var sessionDur = nowUtc.difference(checkInUtc);
    if (sessionDur.isNegative) {
      sessionDur = Duration.zero;
    }
    
    final nowIst = toIST(nowUtc);
    
    String endTimeStr = '14:00:00';
    String startTimeStr = '06:00:00';
    if (_activeAttendance != null) {
      final membership = _activeAttendance!['memberships'] as Map<String, dynamic>? ?? {};
      final shift = _activeAttendance!['shifts'] as Map<String, dynamic>? ?? membership['shifts'] as Map<String, dynamic>? ?? {};
      endTimeStr = shift['end_time'] as String? ?? '14:00:00';
      startTimeStr = shift['start_time'] as String? ?? '06:00:00';
    } else {
      final membership = _myMemberships.isNotEmpty ? _myMemberships.first : null;
      final shift = membership != null ? (membership['shifts'] as Map<String, dynamic>?) : null;
      endTimeStr = shift != null ? (shift['end_time'] as String? ?? '14:00:00') : '14:00:00';
      startTimeStr = shift != null ? (shift['start_time'] as String? ?? '06:00:00') : '06:00:00';
    }

    final endParts = endTimeStr.split(':');
    int endHour = 14, endMin = 0;
    if (endParts.length >= 2) {
      endHour = int.tryParse(endParts[0]) ?? 14;
      endMin = int.tryParse(endParts[1]) ?? 0;
    }
    final shiftEndIst = DateTime.utc(nowIst.year, nowIst.month, nowIst.day, endHour, endMin);
    
    final startParts = startTimeStr.split(':');
    int startHour = 6, startMin = 0;
    if (startParts.length >= 2) {
      startHour = int.tryParse(startParts[0]) ?? 6;
      startMin = int.tryParse(startParts[1]) ?? 0;
    }
    final shiftStartIst = DateTime.utc(nowIst.year, nowIst.month, nowIst.day, startHour, startMin);

    final remaining = shiftEndIst.difference(nowIst);
    
    final shiftDuration = shiftEndIst.difference(shiftStartIst).inSeconds;
    final elapsedInShift = nowIst.difference(toIST(checkInUtc)).inSeconds;
    final progress = shiftDuration > 0 ? (elapsedInShift / shiftDuration).clamp(0.0, 1.0) : 0.0;

    _sessionDurationNotifier.value = sessionDur;
    _shiftRemainingNotifier.value = remaining;
    _shiftProgressNotifier.value = progress;

    _sessionDuration = sessionDur;

    // Shift ended → warn the member once; 30 min later → auto-checkout (if the
    // library allows it) so the timer stops without waiting for the server cron.
    _maybeWarnShiftEnd(remaining);
    _maybeAutoCheckout(remaining, shiftEndIst);
  }

  /// One-shot "your shift has ended" notification to the member. Sets
  /// attendance.overtime_warned so the server cron does not double-warn. Skips
  /// if the cron already warned (the loaded row says so).
  void _maybeWarnShiftEnd(Duration remaining) {
    if (!remaining.isNegative || _shiftEndWarnSent) return;
    final att = _activeAttendance;
    if (att == null) return;
    if (att['overtime_warned'] == true) {
      _shiftEndWarnSent = true; // server already warned
      return;
    }
    _shiftEndWarnSent = true;
    final id = att['id'];
    final memberId = att['member_id']?.toString();
    if (id == null || memberId == null) return;
    final supabase = Supabase.instance.client;
    () async {
      try {
        await supabase.from('attendance').update({'overtime_warned': true}).eq('id', id);
        await supabase.from('notifications').insert({
          'user_id': memberId,
          'title': 'Your shift has ended',
          'body': _autoCheckoutOvertime
              ? 'Your shift is over. Please scan to check out. If you stay, the extra time '
                  'counts as overtime and you will be auto-checked-out after 30 minutes.'
              : 'Your shift is over. Please scan to check out. Any extra time is recorded as overtime.',
          'data': {'type': 'shift_end', 'route': '/member/home'},
        });
      } catch (e) {
        debugPrint('client shift-end warn failed: $e');
      }
    }();
  }

  /// One-shot client auto-checkout at shift end + 30 min, gated by the library
  /// setting. Caps overtime at 30 min and tags the session, then stops the timer
  /// and reloads. Server cron is the backstop when the app is closed.
  void _maybeAutoCheckout(Duration remaining, DateTime shiftEndIst) {
    if (!_autoCheckoutOvertime || _autoCheckoutSent) return;
    if (remaining.inSeconds > -1800) return; // not yet 30 min past shift end
    final att = _activeAttendance;
    if (att == null || _checkInTime == null) return;
    _autoCheckoutSent = true;

    final id = att['id'];
    final memberId = att['member_id']?.toString();
    final libraryId = att['library_id']?.toString();
    final shiftEndUtc = shiftEndIst.subtract(const Duration(hours: 5, minutes: 30));
    final checkInUtc = _checkInTime!.toUtc();
    final anchor = checkInUtc.isAfter(shiftEndUtc) ? checkInUtc : shiftEndUtc;
    final capCheckoutUtc = anchor.add(const Duration(minutes: 30));
    var dur = capCheckoutUtc.difference(checkInUtc).inMinutes;
    if (dur < 0) dur = 0;

    final supabase = Supabase.instance.client;
    () async {
      try {
        final res = await supabase
            .from('attendance')
            .update({
              'check_out_time': capCheckoutUtc.toIso8601String(),
              'duration_minutes': dur,
              'session_type': 'auto_checkout',
              'is_overtime': true,
              'overtime_minutes': 30,
            })
            .eq('id', id)
            .isFilter('check_out_time', null)
            .select();
        if ((res as List).isNotEmpty) {
          if (memberId != null) {
            await supabase.from('notifications').insert({
              'user_id': memberId,
              'title': 'Auto checked out',
              'body': 'You were automatically checked out 30 minutes after your shift ended. '
                  'This session is tagged as overtime.',
              'data': {'type': 'auto_checkout', 'route': '/member/home'},
            });
          }
          if (libraryId != null && libraryId.isNotEmpty) {
            await NotificationService.notifyLibraryOwner(
              libraryId: libraryId,
              title: 'Member auto checked out',
              body: 'A member was auto-checked-out 30 minutes after their shift ended (overtime).',
              type: 'check_out',
            );
          }
        }
      } catch (e) {
        debugPrint('client auto-checkout failed: $e');
      } finally {
        if (mounted) {
          _stopSessionTimer();
          await _loadInitialData();
        }
      }
    }();
  }

  String _getMotivationalMessage(double progress) {
    if (progress <= 0.10) {
      return "Great start! Let's build some momentum.";
    } else if (progress <= 0.25) {
      return "Keep going! You are settling in nicely.";
    } else if (progress <= 0.50) {
      return "Almost halfway there! Stay focused.";
    } else if (progress <= 0.75) {
      return "More than halfway! You are doing amazing.";
    } else if (progress <= 0.90) {
      return "Homestretch! Finish strong today.";
    } else {
      return "Fantastic job! Wrap up your session when ready.";
    }
  }

  String _getCompletionMessage(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes < 30) {
      return "Short but sweet study session. Every minute counts!";
    } else if (minutes < 120) {
      return "Solid study block completed! Consistency is key.";
    } else if (minutes < 240) {
      return "Great session! You've put in a lot of hard work today.";
    } else {
      return "Incredible effort! You studied like a champ today.";
    }
  }

  Future<void> _fetchPreviousSession() async {
    try {
      final supabase = Supabase.instance.client;
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final completedSessionsRes = await supabase
          .from('attendance')
          .select('*, libraries(name), shifts(name), memberships(seats(seat_label))')
          .eq('member_id', currentUser.id)
          .not('check_out_time', 'is', null)
          .order('check_in_time', ascending: false)
          .limit(2);

      _hasSessionEndedToday = false;
      _previousSession = null;
      _streak = _currentStreak;

      final todayStr = DateFormat('yyyy-MM-dd').format(toIST(DateTime.now().toUtc()));

      if (completedSessionsRes.isNotEmpty) {
        final sessions = List<Map<String, dynamic>>.from(completedSessionsRes);
        final firstSession = sessions[0];
        final firstCheckInStr = firstSession['check_in_time'] as String;
        final firstCheckInUtc = DateTime.parse(firstCheckInStr);
        final firstCheckInIst = toIST(firstCheckInUtc);
        final firstSessionDateStr = DateFormat('yyyy-MM-dd').format(firstCheckInIst);

        if (_isCheckedIn) {
          // A session is currently running. Show the most recent COMPLETED
          // session as the "previous" card below it (supports multiple
          // sessions in one day).
          _previousSession = _formatSessionMap(firstSession);
        } else if (firstSessionDateStr == todayStr) {
          _hasSessionEndedToday = true;
          final checkInTime = DateTime.parse(firstSession['check_in_time'] as String);
          final checkOutTime = DateTime.parse(firstSession['check_out_time'] as String);
          _sessionDuration = checkOutTime.difference(checkInTime);
          _checkInTime = checkInTime;
          _checkOutTime = checkOutTime;

          if (sessions.length > 1) {
            _previousSession = _formatSessionMap(sessions[1]);
          }
        } else {
          _previousSession = _formatSessionMap(firstSession);
        }
      }

      if (!_isCheckedIn && !_hasSessionEndedToday) {
        final membership = _myMemberships.isNotEmpty ? _myMemberships.first : null;
        final shift = membership != null ? (membership['shifts'] as Map<String, dynamic>?) : null;
        final endTimeStr = shift != null ? (shift['end_time'] as String? ?? '14:00:00') : '14:00:00';
        final parts = endTimeStr.split(':');
        _shiftEndHour = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 14) : 14;

        final nowIst = toIST(DateTime.now().toUtc());
        if (nowIst.hour >= _shiftEndHour) {
          _shiftEndedWithoutCheckin = true;
        } else {
          _shiftEndedWithoutCheckin = false;
        }
      } else {
        _shiftEndedWithoutCheckin = false;
      }

    } catch (e) {
      debugPrint('Error fetching previous session: $e');
    }
  }

  Map<String, dynamic>? _formatSessionMap(Map<String, dynamic> session) {
    try {
      final checkInTime = DateTime.parse(session['check_in_time'] as String);
      final checkOutTime = DateTime.parse(session['check_out_time'] as String);
      final duration = checkOutTime.difference(checkInTime);
      final libName = session['libraries']?['name'] ?? 'SILENCE Library';
      final shift = session['shifts'] as Map<String, dynamic>? ?? {};
      final shiftName = shift['name'] ?? 'N/A';
      
      final membership = session['memberships'] as Map<String, dynamic>? ?? {};
      final seat = membership['seats'] as Map<String, dynamic>? ?? {};
      final seatLabel = seat.isNotEmpty ? (seat['seat_label'] ?? 'Pending') : 'Seat pending';
      final streakAtDate = _calculateStreakAtDate(_studyDates, toIST(checkInTime));

      return {
        'duration': formatDurationHuman(duration),
        'check_in_time': formatTimeIST(checkInTime),
        'check_out_time': formatTimeIST(checkOutTime),
        'library_name': libName,
        'shift_name': shiftName,
        'seat_label': seatLabel,
        'date': DateFormat('E, d MMM').format(toIST(checkInTime)),
        'title': _relativeDayLabel(toIST(checkInTime)),
        'streak': '$streakAtDate Day${streakAtDate == 1 ? "" : "s"} 🔥',
      };
    } catch (_) {
      return null;
    }
  }

  /// A relative, friendly title for a session based on its IST date:
  /// "Today's Session" / "Yesterday's Session" / else the date ("Sun, 7 Jun").
  String _relativeDayLabel(DateTime ist) {
    final nowIst = toIST(DateTime.now().toUtc());
    final day = DateTime(ist.year, ist.month, ist.day);
    final today = DateTime(nowIst.year, nowIst.month, nowIst.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return "Today's Session";
    if (diff == 1) return "Yesterday's Session";
    return DateFormat('E, d MMM').format(ist);
  }

  int _calculateStreakAtDate(Set<String> studyDates, DateTime date) {
    final targetDateStr = DateFormat('yyyy-MM-dd').format(date);
    final yesterdayOfTarget = DateFormat('yyyy-MM-dd').format(date.subtract(const Duration(days: 1)));
    
    bool hasTarget = studyDates.contains(targetDateStr);
    bool hasYesterday = studyDates.contains(yesterdayOfTarget);
    
    if (!hasTarget && !hasYesterday) return 0;
    
    int streak = 0;
    DateTime current = hasTarget ? date : date.subtract(const Duration(days: 1));
    
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

  Future<void> _onCheckOutPressed() async {
    // Open QR scanner for checkout (second scan)
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerScreen()),
    );
    debugPrint('[HOME] Received scanner result');
    debugPrint('[HOME] Received scanner result: $result');
    if (result == true) {
      debugPrint('[HOME] Refresh triggered');
      await _refreshHome();
    }
  }

  int _calculateCurrentStreak(Set<String> studyDates) {
    final todayStr = DateFormat('yyyy-MM-dd').format(istNow());
    final yesterdayStr = DateFormat('yyyy-MM-dd').format(istNow().subtract(const Duration(days: 1)));
    
    bool hasToday = studyDates.contains(todayStr);
    bool hasYesterday = studyDates.contains(yesterdayStr);
    
    if (!hasToday && !hasYesterday) return 0;
    
    int streak = 0;
    DateTime current = hasToday ? istNow() : istNow().subtract(const Duration(days: 1));
    
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

  /// Current calendar week, Sunday → Saturday (fixed order, not a rolling 7
  /// days). Each entry: dayLabel (S/M/T/W/T/F/S), attended, isToday, isFuture.
  List<Map<String, dynamic>> _getLast7DaysAttendance(Set<String> studyDates) {
    final now = istNow();
    final today = DateTime(now.year, now.month, now.day);
    // weekday: Mon=1..Sun=7 → days since the most recent Sunday.
    final sunday = today.subtract(Duration(days: today.weekday % 7));
    List<Map<String, dynamic>> list = [];
    for (int i = 0; i < 7; i++) {
      final day = sunday.add(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(day);
      list.add({
        'dayLabel': DateFormat('E').format(day)[0], // S M T W T F S
        'attended': studyDates.contains(dateStr),
        'isToday': day == today,
        'isFuture': day.isAfter(today),
      });
    }
    return list;
  }

  /// Count of days attended within the current Sunday→Saturday week.
  int get _thisWeekCount =>
      _streakLast7Days.where((d) => d['attended'] == true).length;

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

    final today = istNow();
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
    list.sort((a, b) {
      final nameA = (a['name'] ?? '').toString().toLowerCase();
      final nameB = (b['name'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });
    return list;
  }



  /// Top safe-area (status-bar) color. It must EXACTLY match the colour at the
  /// very top of the current tab's header so there's no visible seam. Because
  /// every header gradient now starts (top edge) with its first colour, we use
  /// that first colour here. Home is state-driven (orange / amber-pending /
  /// red-expired / purple-trial …); the other three tabs share the brand orange.
  Color get _topSafeAreaColor {
    if (_currentBottomTab == 0) {
      return _getHeaderGradient(_getMemberState()).colors.first;
    }
    return const Color(0xFFE65C00);
  }

  @override
  Widget build(BuildContext context) {
    // Status-bar icons are always light — the inset is the orange header on
    // every tab.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
      // Top inset = current tab's header color; bottom inset handled below.
      backgroundColor: _topSafeAreaColor,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Scaffold(
          backgroundColor: const Color(0xFFFBF5EE),
          body: _isLoading
              ? _buildHomeSkeleton()
              : _errorMessage != null
                  ? _buildErrorState()
                  : _buildCurrentTabContent(),
          // White bottom inset so the nav bar (white) blends with the gesture area.
          bottomNavigationBar: Container(
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: _buildBottomNav(),
            ),
          ),
          floatingActionButton: _shouldShowFAB()
              ? FloatingActionButton(
                  onPressed: _onScanFabPressed,
                  backgroundColor: const Color(0xFFE65C00),
                  foregroundColor: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 6,
                  child: const Icon(Icons.qr_code_scanner, size: 28),
                )
              : null,
        ),
      ),
    ),
    );
  }

  /// Today's holiday for the member's primary membership library, or null.
  Holiday? get _primaryLibraryHoliday {
    if (_todayHolidays.isEmpty || _myMemberships.isEmpty) return null;
    final libId = _myMemberships.first['library_id']?.toString();
    if (libId == null) return null;
    return _todayHolidays[libId];
  }

  /// True when the member has requested account deletion (grace period).
  bool get _isPendingDeletion => _userProfile?['scheduled_for_deletion'] == true;

  bool _shouldShowFAB() {
    // Permanent on the Home tab. Eligibility is enforced on tap (with a clear
    // warning) instead of hiding the button, so members always know where the
    // scanner is.
    return _currentBottomTab == 0;
  }

  /// Returns a warning message when the member is NOT eligible to scan
  /// (check-in/out), or null when they are eligible.
  String? _scanIneligibleReason() {
    if (_isPendingDeletion) {
      return 'Check-in is disabled while your account deletion is pending. Cancel the request in Privacy & Security to continue.';
    }
    if (_primaryLibraryHoliday != null) {
      return 'The library is closed today (holiday), so check-in is unavailable.';
    }
    final state = _getMemberState();
    switch (state) {
      case MemberState.active:
      case MemberState.trial:
      case MemberState.expiringSoon:
        return null; // eligible to check in / out
      case MemberState.expired:
        final expiredM = _allMemberships.firstWhere(
          (m) => _isExpiredMembership(m),
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
          if (rules['allow_expired_checkin'] == true) return null;
        }
        return 'Your membership has expired. Renew it to check in again.';
      case MemberState.onHold:
        return 'Your membership is on hold. Ask the admin to resume it before checking in.';
      case MemberState.applicationPending:
        return 'Your application is under review. You can check in once it is approved.';
      case MemberState.exited:
      case MemberState.profileCompleteNoLib:
      case MemberState.freshInstall:
        return 'Join a library first to check in — tap "Find a Library" to get started.';
    }
  }

  void _onScanFabPressed() {
    // A member with no membership yet (fresh / profile-complete / past member)
    // must be able to scan a JOIN QR — opening the scanner lets them do that;
    // the scanner itself routes a join QR to the library profile and an
    // attendance QR to check-in (and tells a non-member to join first).
    final state = _getMemberState();
    if (state == MemberState.freshInstall ||
        state == MemberState.profileCompleteNoLib ||
        state == MemberState.exited) {
      _openQRScanner();
      return;
    }

    final reason = _scanIneligibleReason();
    if (reason == null) {
      _openQRScanner();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(reason, style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
        backgroundColor: const Color(0xFFE65C00),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Widget _buildErrorState() {
    // Friendly, offline-aware error with retry (no raw exception text).
    return ErrorState(error: _errorMessage, onRetry: _loadInitialData);
  }

  /// Skeleton placeholder shown while the dashboard + stats load — mirrors the
  /// real layout (attendance, streak, quick actions, activities) so the page
  /// doesn't jump when data arrives. Replaces the bare spinner.
  Widget _buildHomeSkeleton() {
    Widget block(double h) => SkeletonBox(
          height: h,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
        );
    return Shimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            block(96), // header / greeting strip
            const SizedBox(height: 16),
            block(150), // today's attendance card
            const SizedBox(height: 16),
            block(170), // streak card
            const SizedBox(height: 20),
            const SkeletonBox(width: 120, height: 16), // "Quick Actions" title
            const SizedBox(height: 12),
            Row(
              children: List.generate(
                4,
                (i) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == 3 ? 0 : 8),
                    child: const SkeletonBox(
                      height: 70,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const SkeletonBox(width: 140, height: 16), // "Recent Activities" title
            const SizedBox(height: 12),
            block(64),
            const SizedBox(height: 12),
            block(64),
            const SizedBox(height: 12),
            block(64),
          ],
        ),
      ),
    );
  }

  /// Whole days from today (date-only, local) until [end]. 0 = ends today (still
  /// the last active day), negative = already past. Avoids the `.inDays`
  /// truncation that wrongly showed "0 days left" on the final active day.
  /// Canonical "is this membership expired?" test — status 'expired', or an
  /// active membership whose end_date is already past (IST). Kept in one place
  /// so the expired-state screens don't duplicate/diverge the predicate (H8).
  bool _isExpiredMembership(Map<String, dynamic> m) {
    if (m['status'] == 'expired') return true;
    if (m['status'] == 'active' && m['end_date'] != null) {
      try {
        return DateTime.parse(m['end_date']).isBefore(istNow());
      } catch (_) {}
    }
    return false;
  }

  int _daysLeftDateOnly(DateTime? end) {
    if (end == null) return -1;
    final e = end.toLocal();
    final endDay = DateTime(e.year, e.month, e.day);
    final now = istNow();
    final today = DateTime(now.year, now.month, now.day);
    return endDay.difference(today).inDays;
  }

  Widget _buildCurrentTabContent() {
    final content = IndexedStack(
      index: _currentBottomTab,
      children: [
        _buildHomeTab(),
        _buildAnalyticsTab(),
        const MemberHistoryTab(),
        _buildProfileTab(),
      ],
    );
    final banners = <Widget>[
      if (_primaryLibraryHoliday != null && _currentBottomTab == 0)
        _buildClosedTodayBanner(_primaryLibraryHoliday!),
      if (_isPendingDeletion) _buildDeletionBanner(),
      if (_isOfflineCached)
        InkWell(
          onTap: _loadInitialData,
          child: const OfflineBanner(
            message: "You're offline — showing saved data. Tap to retry.",
          ),
        ),
    ];
    if (banners.isEmpty) return content;
    return Column(
      children: [
        ...banners,
        Expanded(child: content),
      ],
    );
  }

  /// Red banner shown while the account is scheduled for deletion. Tapping it
  /// opens Privacy & Security where the member can cancel the request.
  Widget _buildDeletionBanner() {
    return Material(
      color: const Color(0xFFFEF2F2),
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, '/member/settings/privacy')
            .then((_) => _loadInitialData()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFDC2626)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Account scheduled for deletion. Check-in is disabled. Tap to cancel.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF991B1B),
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Color(0xFFDC2626)),
            ],
          ),
        ),
      ),
    );
  }

  /// Prominent RED banner shown across the Home tab whenever the member's
  /// primary library is closed today (holiday/closure). Honest + unmissable so
  /// a member doesn't show up to a closed library or wonder why check-in fails.
  Widget _buildClosedTodayBanner(Holiday holiday) {
    final reason = holiday.reason.trim();
    return Material(
      color: const Color(0xFFDC2626), // strong red
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.event_busy_rounded, size: 20, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Library closed today',
                    style: GoogleFonts.outfit(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    reason.isEmpty
                        ? 'Check-in is disabled for today.'
                        : '$reason · Check-in is disabled for today.',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
    final unreadCount = _unreadNotifications;

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
                    icon: const Icon(Icons.notifications_none, color: Colors.white, size: 24),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                      );
                      _refreshUnreadNotifications();
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
            style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
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
                            // Exploring libraries needs no profile — the
                            // complete-profile gate applies only at JOIN time.
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
                  // Shows only if the member's most recent request was rejected.
                  _buildRejectedRequestCard(),
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
  Widget _sectionHeader(IconData icon, String title, Color color) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 8),
        Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
      ],
    );
  }

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
                  _sectionHeader(Icons.bolt_rounded, 'Quick Actions', const Color(0xFFF59E0B)),
                  const SizedBox(height: 12),
                  _buildQuickActionsRow(),
                  const SizedBox(height: 24),

                  // Announcements
                  if (_announcements.isNotEmpty) ...[
                    _sectionHeader(Icons.campaign_rounded, 'Announcements', const Color(0xFF0EA5E9)),
                    const SizedBox(height: 10),
                    _buildAnnouncementsSection(),
                    const SizedBox(height: 24),
                  ],

                  // Recent Activities
                  _sectionHeader(Icons.history_rounded, 'Recent Activities', const Color(0xFF7C3AED)),
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
    
    int trialDaysLeft = _daysLeftDateOnly(DateTime.tryParse(trialMembership['end_date']?.toString() ?? ''));
    if (trialDaysLeft < 0) trialDaysLeft = 0;

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
    
    int daysLeft = _daysLeftDateOnly(DateTime.tryParse(expiringM['end_date']?.toString() ?? ''));
    if (daysLeft < 0) daysLeft = 0;

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
              subtitle: daysLeft <= 0
                  ? "Your plan ends today — renew now"
                  : "Only $daysLeft day${daysLeft == 1 ? '' : 's'} left on your plan",
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
                            daysLeft <= 0
                                ? 'Your plan ends today. Renew now to keep your seat.'
                                : 'Plan expiring in $daysLeft day${daysLeft == 1 ? '' : 's'}. Renew now to keep your seat.',
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
      (m) => _isExpiredMembership(m),
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
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8)],
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
              subtitle: "Your membership is paused",
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
                        _buildHoldBulletInfo('Billing is paused and the paused days are added back to your plan.'),
                        const SizedBox(height: 6),
                        _buildHoldBulletInfo('QR Scanner Check-in is NOT available during holds.'),
                        const SizedBox(height: 12),
                        Text(
                          "You'll be notified the moment your membership resumes.",
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF78350F)),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Member can ask the admin to lift the hold early (admins own
                  // holds now; this routes a request via the library query inbox).
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          '/member/query',
                          arguments: {
                            'libraryId': holdM['library_id'],
                            'preFilledMessage':
                                'I would like to resume my membership early. Please lift the hold on my account.',
                          },
                        );
                      },
                      icon: const Icon(Icons.play_circle_outline, size: 18),
                      label: const Text('Request to resume early'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE65C00),
                        side: const BorderSide(color: Color(0xFFE65C00)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
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
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8)],
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
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8)],
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 4))],
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

  /// Card shown (in the no-library state) when the member's most recent join
  /// request was rejected: shows the reason + lets them re-apply or contact the
  /// admin. Hidden otherwise.
  Widget _buildRejectedRequestCard() {
    final req = _rejectedRequest;
    if (req == null) return const SizedBox.shrink();
    final lib = req['libraries'] as Map<String, dynamic>? ?? {};
    final libName = (lib['name'] ?? 'the library').toString();
    final reason = (req['rejection_reason'] ?? '').toString().trim();
    final libraryId = (req['library_id'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cancel_outlined, color: Color(0xFFDC2626), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Join request not approved',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF991B1B)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Your request to join $libName was not approved.',
            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF7F1D1D)),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Reason: $reason',
              style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF991B1B), fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/member/explore').then((_) => _loadInitialData());
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Apply again', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
              if (libraryId.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LibraryQueryScreen(
                            libraryId: libraryId,
                            preFilledMessage:
                                'Hello, my join request was not approved. Could you tell me what I need to correct so I can re-apply? Thank you!',
                          ),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFDC2626)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('Contact admin', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ],
          ),
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
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
                // .select() returns the affected rows: if RLS silently matched
                // 0 rows (no policy / already processed), we get an empty list
                // and report honestly instead of a false "withdrawn".
                final res = await supabase
                    .from('join_requests')
                    .update({'status': 'withdrawn'})
                    .eq('id', requestId)
                    .eq('status', 'pending')
                    .select('id');
                if (mounted) {
                  _loadInitialData();
                }
                if ((res as List).isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Could not withdraw — it may already be approved or processed.')),
                  );
                } else {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Application withdrawn.')),
                  );
                }
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text(friendlyError(e))),
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
    final fullName = _userProfile?['full_name'] as String? ??
        Supabase.instance.client.auth.currentUser?.userMetadata?['full_name'] as String? ??
        'Student';
    final firstName = fullName.split(' ').first;
    return firstName;
  }

  String _getGreetingTime() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  LinearGradient _getHeaderGradient(MemberState state) {
    // Vertical gradients: the TOP edge is a single uniform colour (the first
    // colour), so the status-bar strip (which uses that same first colour) meets
    // the header with no visible seam across the full width.
    const begin = Alignment.topCenter;
    const end = Alignment.bottomCenter;
    switch (state) {
      case MemberState.freshInstall:
      case MemberState.profileCompleteNoLib:
      case MemberState.active:
        return const LinearGradient(
          colors: [Color(0xFFE65C00), Color(0xFFC44E00)],
          begin: begin,
          end: end,
        );
      case MemberState.applicationPending:
      case MemberState.expiringSoon:
        return const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
          begin: begin,
          end: end,
        );
      case MemberState.trial:
        return const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)],
          begin: begin,
          end: end,
        );
      case MemberState.expired:
        return const LinearGradient(
          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
          begin: begin,
          end: end,
        );
      case MemberState.onHold:
        return const LinearGradient(
          colors: [Color(0xFFD97706), Color(0xFFB45309)],
          begin: begin,
          end: end,
        );
      case MemberState.exited:
        return const LinearGradient(
          colors: [Color(0xFF6B7280), Color(0xFF4B5563)],
          begin: begin,
          end: end,
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
          _buildHowItWorksRow(1, 'Complete your profile', 'Add your details, photo and ID — needed before you join.', Icons.person_outline_rounded),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          _buildHowItWorksRow(2, 'Find & request to join', 'Explore nearby libraries, scan a join QR, or use a library code, then pick a shift and plan.', Icons.search_rounded),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          _buildHowItWorksRow(3, 'Pay & get approved', 'Pay the library directly (cash/UPI). The admin confirms your payment and assigns your seat.', Icons.verified_user_outlined),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          _buildHowItWorksRow(4, 'Scan to check in & out', 'Use the QR scanner at the library to mark attendance and build your streak.', Icons.qr_code_scanner_rounded),
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

  /// Honest price for the membership card: the amount the member actually paid
  /// (latest confirmed payment) wins; otherwise the shift's plan price; if both
  /// are missing/zero, show '—' rather than a misleading ₹0.
  String _membershipPriceLabel(Map<String, dynamic> membership, Map<String, dynamic> shift) {
    final paid = membership['_paid_amount'];
    if (paid is num && paid > 0) return '₹${paid.toInt()}';
    int planPrice = 0;
    if (shift.isNotEmpty) {
      switch (membership['plan_type']) {
        case 'monthly':
          planPrice = (shift['price_monthly'] as num? ?? 0).toInt();
          break;
        case '3_month':
          planPrice = (shift['price_3month'] as num? ?? 0).toInt();
          break;
        case '6_month':
          planPrice = (shift['price_6month'] as num? ?? 0).toInt();
          break;
        default:
          planPrice = (shift['price_monthly'] as num? ?? 0).toInt();
      }
    }
    return planPrice > 0 ? '₹$planPrice' : '—';
  }

  Widget _buildMembershipCard(Map<String, dynamic> membership, MemberState state) {
    final status = membership['status'] as String? ?? 'pending';
    final library = membership['libraries'] as Map<String, dynamic>? ?? {};
    final shift = membership['shifts'] as Map<String, dynamic>? ?? {};
    final seat = membership['seats'] as Map<String, dynamic>? ?? {};
    final libName = (library['name'] ?? 'SILENCE Zone').toString();
    final libInitial = libName.trim().isNotEmpty ? libName.trim()[0].toUpperCase() : 'L';
    final libPhoto = (library['cover_photo_url'] ?? '').toString().isNotEmpty
        ? library['cover_photo_url'].toString()
        : ((library['photos'] is List && (library['photos'] as List).isNotEmpty)
            ? (library['photos'] as List).first.toString()
            : '');
    final libCity = (library['address_city'] ?? '').toString();
    
    Color borderColor;
    String statusLabel;
    
    DateTime? endDate;
    if (membership['end_date'] != null) {
      endDate = DateTime.parse(membership['end_date']);
    }
    final remainingDays = endDate != null ? _daysLeftDateOnly(endDate) : -1;

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
          // Primary Renew action + a compact "more" menu (Change Seat / Exit).
          return Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (_isProfileIncomplete()) {
                      _showProfileIncompleteDialog();
                      return;
                    }
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
                  icon: const Icon(Icons.autorenew_rounded, size: 18),
                  label: Text('Renew Plan', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE65C00),
                    side: const BorderSide(color: Color(0xFFE65C00)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
                  tooltip: 'More options',
                  onPressed: () => _openMembershipMoreOptions(membership),
                ),
              ),
            ],
          );
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            const Color(0xFFFFF7F0),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: borderColor, width: 4)),
        boxShadow: [
          BoxShadow(color: borderColor.withValues(alpha: 0.13), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: ID-card style — library photo + library name (big) + city, status + menu
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFFFFF1E8),
                backgroundImage: libPhoto.isNotEmpty ? CachedNetworkImageProvider(libPhoto) : null,
                child: libPhoto.isEmpty
                    ? Text(
                        libInitial,
                        style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            libName,
                            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A), height: 1.1),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.verified, color: Colors.blue, size: 16),
                        ],
                      ],
                    ),
                    if (libCity.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.location_on_rounded, size: 13, color: Colors.grey[500]),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              libCity,
                              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: borderColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusLabel,
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: borderColor),
                        ),
                      ),
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_vert, color: Color(0xFF94A3B8), size: 20),
                          tooltip: 'Options',
                          onPressed: () => _openMembershipMoreOptions(membership),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 18),
          // Info grid (2 columns) — labeled, bigger values, overflow-safe
          Row(
            children: [
              Expanded(
                child: _cardInfoItem(
                  Icons.event_seat_rounded,
                  'Seat',
                  seat.isNotEmpty ? (seat['seat_label'] ?? 'Pending') : 'Pending',
                  accent: const Color(0xFFE65C00),
                  valueColor: const Color(0xFFE65C00),
                ),
              ),
              Expanded(
                child: _cardInfoItem(
                  Icons.wb_sunny_rounded,
                  'Shift',
                  shift.isNotEmpty ? (shift['name'] ?? 'Shift') : 'Pending',
                  accent: const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _cardInfoItem(Icons.schedule_rounded, 'Timing', _formatShiftRange(shift),
                    accent: const Color(0xFF6366F1)),
              ),
              Expanded(
                child: _cardInfoItem(
                  Icons.calendar_today_rounded,
                  'Joined',
                  membership['start_date'] != null
                      ? DateFormat('dd MMM yyyy').format(DateTime.parse(membership['start_date']))
                      : '—',
                  accent: const Color(0xFF22C55E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _cardInfoItem(
                  Icons.workspace_premium_rounded,
                  'Plan',
                  membership['plan_type'] == 'monthly'
                      ? 'Monthly'
                      : membership['plan_type'] == '3_month'
                          ? '3-Month'
                          : membership['plan_type'] == '6_month'
                              ? '6-Month'
                              : 'Trial',
                  accent: const Color(0xFF7C3AED),
                ),
              ),
              Expanded(
                child: _cardInfoItem(
                  Icons.payments_rounded,
                  'Price',
                  _membershipPriceLabel(membership, shift),
                  accent: const Color(0xFF10B981),
                ),
              ),
            ],
          ),
          if (endDate != null && status != 'pending') ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey[200],
                color: borderColor,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Expires: ${DateFormat('dd MMM yyyy').format(endDate)}',
                  style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey[500]),
                ),
                Text(
                  remainingDays > 0 ? '$remainingDays days left' : remainingDays == 0 ? 'Last day today' : 'Expired',
                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: remainingDays <= 7 ? const Color(0xFFEF4444) : Colors.grey[600]),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          // Active card is ID-style — its actions (Renew/Seat/Exit) live in the
          // top-right ⋮ menu. Other states keep their inline CTA buttons.
          if (state != MemberState.active) buildButtons(),
        ],
      ),
    );
  }

  /// One labeled info cell for the membership card: a soft tinted icon chip +
  /// small label + bold value. Wrapped in Expanded by callers; value ellipsizes.
  Widget _cardInfoItem(IconData icon, String label, String value,
      {Color accent = const Color(0xFFE65C00), Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: GoogleFonts.inter(fontSize: 10.5, color: Colors.grey[500], fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: valueColor ?? const Color(0xFF1E293B)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Formats a shift's start–end into IST 12-hour text, e.g. "9:00 AM – 9:00 PM".
  /// Shift times are stored as wall-clock time-of-day, so no UTC offset is applied.
  String _formatShiftRange(Map<String, dynamic> shift) {
    if (shift.isEmpty) return '—';
    final start = _formatShiftTime(shift['start_time']?.toString());
    final end = _formatShiftTime(shift['end_time']?.toString());
    if (start.isEmpty && end.isEmpty) return '—';
    if (end.isEmpty) return start;
    if (start.isEmpty) return end;
    return '$start – $end';
  }

  String _formatShiftTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final s = raw.trim();
    try {
      if (s.toLowerCase().contains('am') || s.toLowerCase().contains('pm')) {
        final dt = DateFormat('h:mm a').parse(s.toUpperCase());
        return DateFormat('h:mm a').format(dt);
      }
      final parts = s.split(':');
      final h = int.parse(parts[0]);
      final m = parts.length > 1 ? int.parse(parts[1].split(' ').first) : 0;
      return DateFormat('h:mm a').format(DateTime(2000, 1, 1, h, m));
    } catch (_) {
      return s;
    }
  }

  Widget _buildTodayAttendanceCard() {
    Widget mainCard;

    if (_isCheckedIn) {
      mainCard = _buildActiveSessionCard();
    } else if (_hasSessionEndedToday) {
      mainCard = _buildSessionEndedTodayCard();
    } else if (_shiftEndedWithoutCheckin) {
      mainCard = _buildShiftEndedCard();
    } else {
      mainCard = _buildNotCheckedInCard();
    }

    // Show the previous-session card below the main card in all states,
    // including while a session is running (so members see their last session).
    final showPrev = _previousSession != null;

    if (showPrev) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          mainCard,
          _buildPreviousSessionCard(),
        ],
      );
    }

    return mainCard;
  }

  Widget _buildActiveSessionCard() {
    final attendance = _activeAttendance;
    if (attendance == null) return const SizedBox.shrink();

    final checkInStr = attendance['check_in_time'] as String;
    final checkInTime = DateTime.parse(checkInStr);

    final membership = attendance['memberships'] as Map<String, dynamic>? ?? {};
    final shift = attendance['shifts'] as Map<String, dynamic>? ?? membership['shifts'] as Map<String, dynamic>? ?? {};
    final seat = attendance['seats'] as Map<String, dynamic>? ?? membership['seats'] as Map<String, dynamic>? ?? {};
    final seatLabel = seat.isNotEmpty ? (seat['seat_label'] ?? 'Pending') : 'Seat pending';

    final shiftEndTimeStr = shift['end_time'] as String? ?? '14:00:00';
    final shiftStartTimeStr = shift['start_time'] as String? ?? '06:00:00';
    final shiftName = shift['name'] ?? 'N/A';

    final startParts = shiftStartTimeStr.split(':');
    int startHour = 6, startMin = 0;
    if (startParts.length >= 2) {
      startHour = int.tryParse(startParts[0]) ?? 6;
      startMin = int.tryParse(startParts[1]) ?? 0;
    }
    final nowIst = toIST(DateTime.now().toUtc());
    final shiftStartIst = DateTime.utc(nowIst.year, nowIst.month, nowIst.day, startHour, startMin);

    final endParts = shiftEndTimeStr.split(':');
    int endHour = 14, endMin = 0;
    if (endParts.length >= 2) {
      endHour = int.tryParse(endParts[0]) ?? 14;
      endMin = int.tryParse(endParts[1]) ?? 0;
    }
    final shiftEndIst = DateTime.utc(nowIst.year, nowIst.month, nowIst.day, endHour, endMin);
    final shiftDurationMinutes = shiftEndIst.difference(shiftStartIst).inMinutes;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22C55E).withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ===== Green gradient header: live status + big running timer =====
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF15803D), Color(0xFF22C55E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'LIVE SESSION',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatDateIST(checkInTime.toUtc()),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ValueListenableBuilder<Duration>(
                  valueListenable: _sessionDurationNotifier,
                  builder: (context, dur, child) {
                    return Text(
                      formatDurationHMS(dur),
                      style: GoogleFonts.spaceMono(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.0,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.login_rounded, size: 14, color: Colors.white.withValues(alpha: 0.85)),
                    const SizedBox(width: 5),
                    Text(
                      'Checked in at ${formatTimeIST(checkInTime.toUtc())}',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ===== White body: progress, info chips, remaining, CTA =====
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Shift progress
                ValueListenableBuilder<double>(
                  valueListenable: _shiftProgressNotifier,
                  builder: (context, progress, child) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'SHIFT PROGRESS',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF64748B),
                                letterSpacing: 1.0,
                              ),
                            ),
                            Text(
                              '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}% · ${formatDurationHuman(Duration(minutes: shiftDurationMinutes))} shift',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: const Color(0xFFF1F5F9),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF22C55E)),
                            minHeight: 8,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                // Seat + Shift info chips
                Row(
                  children: [
                    Expanded(
                      child: _cardInfoItem(
                        Icons.event_seat_rounded,
                        'Seat',
                        seatLabel,
                        accent: const Color(0xFFE65C00),
                        valueColor: const Color(0xFFE65C00),
                      ),
                    ),
                    Expanded(
                      child: _cardInfoItem(
                        Icons.wb_sunny_rounded,
                        'Shift',
                        shiftName,
                        accent: const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _cardInfoItem(
                  Icons.schedule_rounded,
                  'Shift Timing',
                  '${formatShiftTimeString(shiftStartTimeStr)} – ${formatShiftTimeString(shiftEndTimeStr)}',
                  accent: const Color(0xFF6366F1),
                ),
                const SizedBox(height: 18),
                // Time remaining / overtime (overtime capped at 30 min, then the
                // server auto-checks-out). Auto-checkout clock = shift end + 30m.
                ValueListenableBuilder<Duration>(
                  valueListenable: _shiftRemainingNotifier,
                  builder: (context, rem, child) {
                    final isOvertime = rem.isNegative;
                    const overtimeCap = Duration(minutes: 30);
                    final rawOver = rem.abs();
                    final cappedOver = isOvertime && rawOver > overtimeCap ? overtimeCap : rawOver;
                    final capReached = isOvertime && rawOver >= overtimeCap;
                    final accent = isOvertime ? const Color(0xFFEF4444) : const Color(0xFFF97316);
                    final autoCheckoutLabel =
                        DateFormat('hh:mm a').format(shiftEndIst.add(overtimeCap));
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isOvertime ? Icons.error_outline_rounded : Icons.hourglass_bottom_rounded,
                                size: 20,
                                color: accent,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  isOvertime ? 'Overtime (max 30 min)' : 'Time remaining in shift',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF475569),
                                  ),
                                ),
                              ),
                              Text(
                                formatDurationHMS(isOvertime ? cappedOver : rem),
                                style: GoogleFonts.spaceMono(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: accent,
                                ),
                              ),
                            ],
                          ),
                          if (isOvertime) ...[
                            const SizedBox(height: 6),
                            Text(
                              capReached
                                  ? 'Overtime maxed — you will be auto-checked-out shortly.'
                                  : 'Please check out. Auto check-out at $autoCheckoutLabel (shift end + 30 min).',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: accent,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                // Motivational message
                ValueListenableBuilder<double>(
                  valueListenable: _shiftProgressNotifier,
                  builder: (context, progress, child) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.auto_awesome_rounded, size: 15, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _getMotivationalMessage(progress),
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontStyle: FontStyle.italic,
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                // Check Out button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _onCheckOutPressed,
                    icon: const Icon(Icons.logout_rounded, size: 20),
                    label: Text(
                      'Check Out',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionEndedTodayCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              color: const Color(0xFFE65C00),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF22C55E),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Today's Session",
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                    if (_checkInTime != null)
                      Text(
                        formatDateIST(_checkInTime!.toUtc()),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Timeline bar
                if (_checkInTime != null && _checkOutTime != null)
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Check-in: ${formatTimeIST(_checkInTime!.toUtc())}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                          Text(
                            'Check-out: ${formatTimeIST(_checkOutTime!.toUtc())}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF22C55E), Color(0xFFE65C00)],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                
                // 3-stat row
                if (_checkInTime != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem('Duration', formatDurationHuman(_sessionDuration)),
                      _buildStatItem('Check-In', formatTimeIST(_checkInTime!.toUtc())),
                      _buildStatItem('Streak', '$_streak Day${_streak == 1 ? "" : "s"} 🔥'),
                    ],
                  ),
                const SizedBox(height: 20),
                
                // Completion message
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getCompletionMessage(_sessionDuration),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftEndedCard() {
    final membership = _myMemberships.isNotEmpty ? _myMemberships.first : null;
    final shift = membership != null ? (membership['shifts'] as Map<String, dynamic>?) : null;
    final seat = membership != null ? (membership['seats'] as Map<String, dynamic>?) : null;
    final seatLabel = seat != null ? (seat['seat_label'] ?? 'Pending') : 'Seat pending';
    final shiftStartTimeStr = shift != null ? (shift['start_time'] as String? ?? '06:00:00') : '06:00:00';
    final shiftEndTimeStr = shift != null ? (shift['end_time'] as String? ?? '14:00:00') : '14:00:00';
    final shiftName = shift != null ? (shift['name'] ?? 'N/A') : 'N/A';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              color: const Color(0xFF9CA3AF),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "TODAY'S SESSION",
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF94A3B8),
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      formatDateIST(DateTime.now().toUtc()),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.timer_off_outlined, color: Color(0xFF64748B), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Session Ended for Today',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Your shift end time has passed.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFFF1F5F9)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Shift timings',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '$shiftName · ${formatShiftTimeString(shiftStartTimeStr)} – ${formatShiftTimeString(shiftEndTimeStr)}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Your Seat',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      seatLabel,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Your shift ended without a check-in today. You can check in for your next shift tomorrow.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHolidayClosedCard(Holiday holiday) {
    final dateLabel = holiday.isRange
        ? '${DateFormat('dd MMM').format(holiday.startDate)} – ${DateFormat('dd MMM').format(holiday.endDate)}'
        : DateFormat('EEEE, dd MMM').format(holiday.startDate);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 4, color: const Color(0xFFE65C00)),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "TODAY'S SESSION",
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF94A3B8),
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      formatDateIST(DateTime.now().toUtc()),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFF3ED),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.event_busy,
                          color: Color(0xFFE65C00), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Library closed today',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF9A3412),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$dateLabel · ${holiday.reason}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined,
                          color: Color(0xFF15803D), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your study streak is protected for today.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF15803D),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.block, size: 18),
                    label: Text(
                      'Check-in disabled (holiday)',
                      style: GoogleFonts.inter(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      disabledBackgroundColor: const Color(0xFFE2E8F0),
                      disabledForegroundColor: const Color(0xFF94A3B8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotCheckedInCard() {
    final holiday = _primaryLibraryHoliday;
    if (holiday != null) {
      return _buildHolidayClosedCard(holiday);
    }
    final membership = _myMemberships.isNotEmpty ? _myMemberships.first : null;
    final shift = membership != null ? (membership['shifts'] as Map<String, dynamic>?) : null;
    final seat = membership != null ? (membership['seats'] as Map<String, dynamic>?) : null;
    final seatLabel = seat != null ? (seat['seat_label'] ?? 'Pending') : 'Seat pending';
    final shiftStartTimeStr = shift != null ? (shift['start_time'] as String? ?? '06:00:00') : '06:00:00';
    final shiftEndTimeStr = shift != null ? (shift['end_time'] as String? ?? '14:00:00') : '14:00:00';
    final shiftName = shift != null ? (shift['name'] ?? 'N/A') : 'N/A';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              color: const Color(0xFF9CA3AF),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "TODAY'S SESSION",
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF94A3B8),
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      formatDateIST(DateTime.now().toUtc()),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1E8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.location_off_rounded, color: Color(0xFFE65C00), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Not checked in yet',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Scan your library QR to check in.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFFF1F5F9)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Shift timings',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '$shiftName · ${formatShiftTimeString(shiftStartTimeStr)} – ${formatShiftTimeString(shiftEndTimeStr)}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Your Seat',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      seatLabel,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                
                // Scan to Check In button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _openQRScanner,
                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                    label: Text(
                      'Scan to Check In',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviousSessionCard() {
    final prev = _previousSession;
    if (prev == null) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: title + date
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  (prev['title'] as String?)?.toUpperCase() ?? "PREVIOUS SESSION",
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF94A3B8),
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  prev['date'] ?? '',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Only: Duration · Check-In · Check-Out
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatItem('Duration', prev['duration'] ?? 'N/A'),
                _buildStatItem('Check-In', prev['check_in_time'] ?? 'N/A'),
                _buildStatItem('Check-Out', prev['check_out_time'] ?? 'N/A'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.outfit(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF94A3B8),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }

  Widget _buildStreakCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFF8A3D), Color(0xFFE65C00)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'Study Streak',
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1E8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department_rounded, color: Color(0xFFE65C00), size: 15),
                    const SizedBox(width: 4),
                    Text(
                      _currentStreak == 1 ? '1 Day' : '$_currentStreak Days',
                      style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                    ),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'This week',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 12),
          // Current week, Sunday → Saturday.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _streakLast7Days.map((day) {
              final attended = day['attended'] as bool;
              final isToday = day['isToday'] as bool;
              final isFuture = day['isFuture'] as bool;

              Color circleColor;
              Gradient? circleGradient;
              Widget? inner;
              if (attended) {
                circleColor = const Color(0xFF22C55E);
                circleGradient = const LinearGradient(
                  colors: [Color(0xFF34D399), Color(0xFF16A34A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                );
                inner = const Icon(Icons.check_rounded, color: Colors.white, size: 18);
              } else if (isFuture) {
                circleColor = const Color(0xFFF8FAFC);
                inner = null;
              } else {
                circleColor = Colors.grey[200]!;
                inner = null;
              }

              return Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: circleGradient == null ? circleColor : null,
                      gradient: circleGradient,
                      shape: BoxShape.circle,
                      boxShadow: attended
                          ? [BoxShadow(color: const Color(0xFF22C55E).withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 2))]
                          : null,
                      border: isToday
                          ? Border.all(color: const Color(0xFFE65C00), width: 2)
                          : (isFuture ? Border.all(color: Colors.grey[200]!) : null),
                    ),
                    alignment: Alignment.center,
                    child: inner ??
                        (isToday
                            ? const Icon(Icons.circle, color: Color(0xFFE65C00), size: 7)
                            : null),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    day['dayLabel'] as String,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: isToday ? const Color(0xFFE65C00) : Colors.grey[500],
                      fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                    ),
                  )
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),
          // Details row.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _streakStat('This week', '$_thisWeekCount/7'),
              _streakDivider(),
              _streakStat('Best streak', _bestStreak == 1 ? '1 day' : '$_bestStreak days'),
              _streakDivider(),
              _streakStat('Total days', '$_daysPresent'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _streakStat(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: GoogleFonts.outfit(
                fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
        const SizedBox(height: 2),
        Text(label,
            style: GoogleFonts.inter(fontSize: 10.5, color: Colors.grey[500])),
      ],
    );
  }

  Widget _streakDivider() =>
      Container(width: 1, height: 26, color: const Color(0xFFF1F5F9));

  Widget _buildQuickActionsRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildQuickActionButton(
            label: 'Contact Admin',
            icon: Icons.support_agent,
            onPressed: _openContactAdmin,
            accent: const Color(0xFF0EA5E9),
          ),
          const SizedBox(width: 8),
          _buildQuickActionButton(
            label: 'Refer & Earn',
            icon: Icons.card_giftcard_rounded,
            onPressed: _openReferSheet,
            accent: const Color(0xFF7C3AED),
          ),
          const SizedBox(width: 8),
          _buildQuickActionButton(
            label: 'Renew',
            icon: Icons.autorenew_rounded,
            onPressed: _openRenewForPrimary,
            accent: const Color(0xFFE65C00),
          ),
        ],
      ),
    );
  }

  /// Renew the member's primary membership (opens the real renewal flow).
  void _openRenewForPrimary() {
    if (_myMemberships.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have no membership to renew yet. Join a library first.')),
      );
      return;
    }
    final m = _myMemberships.first;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RenewalScreen(
          libraryId: m['library_id']?.toString() ?? '',
          initialPlan: 'monthly',
        ),
      ),
    ).then((_) => _loadInitialData());
  }

  /// Refer & earn: shows the member's referral code with copy + share.
  /// Honest — reuses the real `referral_code` (generated/persisted if missing).
  Future<void> _openReferSheet() async {
    final user = Supabase.instance.client.auth.currentUser;
    var code = _userProfile?['referral_code']?.toString();
    if ((code == null || code.isEmpty) && user != null) {
      final shortId = user.id.length >= 5 ? user.id.substring(0, 5).toUpperCase() : 'XXXXX';
      code = 'REF-$shortId';
      try {
        await Supabase.instance.client
            .from('users')
            .update({'referral_code': code}).eq('id', user.id);
        _userProfile?['referral_code'] = code;
      } catch (e) {
        debugPrint('Could not persist referral_code: $e');
        _userProfile?['referral_code'] = code;
      }
    }
    final refCode = code ?? 'REF-XXXX';
    final shareText =
        'Join me at SILENCE Study Zone using my referral code: $refCode. Download the app here: https://silenceapp.in/download';

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Icon(Icons.card_giftcard, color: Color(0xFFE65C00), size: 40),
            const SizedBox(height: 10),
            Text('Refer & Earn',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
            const SizedBox(height: 6),
            Text(
              'Share your code with friends. When they join SILENCE, you can earn membership extension days (if your library has rewards enabled).',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey[600], height: 1.4),
            ),
            const SizedBox(height: 18),
            // Code chip
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD1B3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(refCode,
                      style: GoogleFonts.spaceMono(
                          fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: refCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Referral code copied!'),
                          backgroundColor: Color(0xFF22C55E),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        const Icon(Icons.copy, size: 16, color: Color(0xFFE65C00)),
                        const SizedBox(width: 4),
                        Text('Copy',
                            style: GoogleFonts.inter(
                                fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () => Share.share(shareText),
              icon: const Icon(Icons.share, size: 18),
              label: Text('Share code',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButton({required String label, required IconData icon, required VoidCallback onPressed, Color accent = const Color(0xFFE65C00)}) {
    return Container(
      width: 100,
      height: 76,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 19),
              ),
              const SizedBox(height: 7),
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.01), blurRadius: 8)],
      ),
      // Bounded height so the card stops growing as activities accumulate;
      // it scrolls internally past ~5 items.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 340),
        child: Scrollbar(
          child: ListView.builder(
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: _recentActivities.length,
            itemBuilder: (context, index) {
          final act = _recentActivities[index];
          final DateTime dt = act['time'] as DateTime;
          // Show in IST 12-hour (DB timestamps are UTC).
          final dateStr = DateFormat('dd MMM, hh:mm a').format(toIST(dt));
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
        ),
      ),
    );
  }

  Widget _buildLastActivityCard() {
    if (_lastCompletedAttendance == null) {
      return const SizedBox.shrink();
    }
    final checkOutStr = _lastCompletedAttendance!['check_out_time'] as String;
    final dt = toIST(DateTime.parse(checkOutStr));
    final dateStr = DateFormat('dd MMM yyyy, h:mm a').format(dt);
    final libName = _lastCompletedAttendance!['libraries']?['name'] ?? 'Library';
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.01), blurRadius: 4)],
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        child: Column(
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
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: (isUnread ? const Color(0xFFE65C00) : const Color(0xFF94A3B8)).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.campaign_rounded, size: 18, color: isUnread ? const Color(0xFFE65C00) : const Color(0xFF94A3B8)),
                ),
                const SizedBox(width: 10),
                Expanded(
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
                if (isUnread) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: const BoxDecoration(color: Color(0xFFE65C00), shape: BoxShape.circle),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
        ),
      ),
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
                        if (!mounted) return;
                        
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
        if (index == 0) {
          _loadInitialData();
        }
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
      onTap: () {
        setState(() {
          _currentBottomTab = index;
        });
        if (index == 0) {
          _loadInitialData();
        }
      },
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

  Future<void> _refreshHome() async {
    await _loadInitialData();
    if (mounted) setState(() {});
  }

  void _openContactAdmin() {
    final libId = _myMemberships.isNotEmpty
        ? _myMemberships.first['library_id']?.toString()
        : null;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContactAdminScreen(defaultLibraryId: libId),
      ),
    );
  }

  Future<void> _openQRScanner() async {
    if (_isPendingDeletion) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check-in is disabled while your account is scheduled for deletion. Cancel the request to continue.')),
      );
      return;
    }
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );
    debugPrint('[HOME] Received scanner result');
    debugPrint('[HOME] Received scanner result: $result');
    if (result == true) {
      debugPrint('[HOME] Refresh triggered');
      await _refreshHome();
    }
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
                leading: const Icon(Icons.autorenew_rounded, color: Color(0xFFE65C00)),
                title: Text('Renew Plan', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  final lib = membership['libraries'] as Map<String, dynamic>? ?? {};
                  final sh = membership['shifts'] as Map<String, dynamic>? ?? {};
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RenewalScreen(
                        libraryId: lib['id'] ?? '',
                        initialShiftId: sh['id'],
                        initialPlan: membership['plan_type'],
                      ),
                    ),
                  ).then((_) => _loadInitialData());
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
        bool duesError = false;

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
                      duesError = true;
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
                  else if (duesError) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Text(
                        "Couldn't check your pending dues right now. For your safety we can't "
                        "process the exit until this is confirmed. Check your connection and retry.",
                        style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF7F1D1D), height: 1.4),
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => setSheetState(() {
                              checkedDues = false;
                              duesError = false;
                            }),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE65C00),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Retry'),
                          ),
                        ),
                      ],
                    ),
                  ]
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
    // Days left on the active plan (shown so the member knows what they forfeit).
    final endStr = membership['end_date']?.toString();
    final endDate = endStr != null ? DateTime.tryParse(endStr) : null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int daysLeft = 0;
    if (endDate != null) {
      daysLeft = DateTime(endDate.year, endDate.month, endDate.day).difference(today).inDays;
      if (daysLeft < 0) daysLeft = 0;
    }
    bool wantRefund = false;
    final reasonCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.red[50],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
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
                  if (daysLeft > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFD1B3)),
                      ),
                      child: Text(
                        'Your plan is still active with $daysLeft day${daysLeft == 1 ? '' : 's'} left'
                        '${endDate != null ? ' (till ${DateFormat('dd MMM yyyy').format(endDate)})' : ''}. '
                        'You will forfeit these days.',
                        style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF92400E), height: 1.35),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: wantRefund,
                          activeColor: const Color(0xFFE65C00),
                          onChanged: (v) => setSheet(() => wantRefund = v ?? false),
                        ),
                        Expanded(
                          child: Text('Also request a refund from the admin',
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                        ),
                      ],
                    ),
                    if (wantRefund)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: TextField(
                          controller: reasonCtrl,
                          maxLines: 2,
                          style: GoogleFonts.inter(fontSize: 13),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            hintText: 'Reason for refund (optional)',
                            hintStyle: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey[400]),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'A refund is decided and paid by the admin — this only sends them a request.',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
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
                              // Member self-exit via RPC (verifies ownership,
                              // releases seat, marks exited). Direct membership
                              // UPDATE is no longer permitted (P5-01 lock).
                              await supabase.rpc('exit_my_membership',
                                  params: {'p_membership_id': membership['id']});

                              // Notify the owner that a member left.
                              final exitLibId = membership['library_id']?.toString();
                              if (exitLibId != null && exitLibId.isNotEmpty) {
                                await NotificationService.notifyLibraryOwner(
                                  libraryId: exitLibId,
                                  title: 'Member left',
                                  body: 'A member has exited your library. Their seat is now free.',
                                  type: 'member_exited',
                                );
                              }

                              // Optional refund REQUEST → goes to the admin as a query.
                              if (wantRefund && daysLeft > 0) {
                                final uid = supabase.auth.currentUser?.id;
                                final libId = membership['library_id'];
                                if (uid != null && libId != null) {
                                  final reason = reasonCtrl.text.trim();
                                  await supabase.from('queries').insert({
                                    'member_id': uid,
                                    'library_id': libId,
                                    'subject': 'Refund request',
                                    'type': 'refund_request',
                                    'message': 'I exited with $daysLeft day(s) left and would like to request a refund.'
                                        '${reason.isEmpty ? '' : ' Reason: $reason'}',
                                    'status': 'open',
                                  });
                                  // Ping the owner about the refund request.
                                  await NotificationService.notifyLibraryOwner(
                                    libraryId: libId.toString(),
                                    title: 'Refund request',
                                    body: 'A member who exited with $daysLeft day(s) left has requested a refund. See Queries.',
                                    type: 'refund_request',
                                  );
                                }
                              }

                              navigator.pop();
                              messenger.showSnackBar(
                                SnackBar(content: Text(wantRefund && daysLeft > 0
                                    ? 'Exited. Your refund request was sent to the admin.'
                                    : 'Successfully exited library. ✓')),
                              );
                              if (mounted) {
                                _loadInitialData();
                              }
                            } catch (e) {
                              messenger.showSnackBar(
                                SnackBar(content: Text(friendlyError(e))),
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
            ),
          ),
        );
      },
    );
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

  Future<void> _refreshUnreadNotifications() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', user.id)
          .isFilter('read_at', null);
      if (mounted) setState(() => _unreadNotifications = (res as List).length);
    } catch (_) {}
  }
}
