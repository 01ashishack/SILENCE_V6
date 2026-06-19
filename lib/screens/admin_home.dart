import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/cache_service.dart';
import '../core/plan_service.dart';
import '../widgets/upgrade_sheet.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'reservations/reservations_tab.dart';
import '../widgets/qr_modal.dart';
import 'admin_analytics_tab.dart';
import 'admin_profile_tab.dart';
import 'scheduled_closures.dart';
import '../utils/holiday_service.dart';
import '../core/calendar_picker.dart';
import '../widgets/states/shimmer_box.dart';

class AdminHomeScreen extends StatefulWidget {
  final bool startInSetupMode;
  const AdminHomeScreen({super.key, this.startInSetupMode = false});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen>
    with SingleTickerProviderStateMixin {
  late bool _inSetupMode;
  bool _initialLoadDone = false;
  int _currentTab = 0; // Stateful Bottom Navigation Bar index

  // One-shot entrance animation for the dashboard sections (plays once after
  // the first load; stays at its final value on later rebuilds → no flicker).
  late final AnimationController _introCtrl;
  bool _introStarted = false;

  // Step completion flags (4 steps: Profile, Basic Info, Layout, Shifts+Payment)
  bool _step1Complete = false;
  bool _step2Complete = false;
  bool _step3Complete = false;
  bool _step4Complete = false;

  // Onboarding status text helper
  int get _stepsDoneCount {
    int count = 0;
    if (_step1Complete) count++;
    if (_step2Complete) count++;
    if (_step3Complete) count++;
    if (_step4Complete) count++;
    return count;
  }

  // Setup progress ratio
  double get _setupProgress {
    return _stepsDoneCount / 4.0;
  }

  // Loaded database references
  String? _libraryId;
  String _libraryCode = 'SIL-XXXXXX';
  String _libraryName = 'Your Library';
  Holiday? _todayHoliday;
  String _libraryAddress = 'Setup your library details to activate';
  String? _coverPhotoUrl;
  int _qrVersion = 1;
  List<Map<String, dynamic>> _myLibraries = [];

  // Stats Counters
  int _totalMembers = 0;
  int _activeMembers = 0;
  int _totalSeats = 0;

  // Dynamic metrics (reflecting actual DB state)
  int _revenueThisMonth = 0;
  int _revenueToday = 0;
  final int _revenuePending = 0;
  int _expiredCount = 0;
  int _newJoiningsThisMonth = 0;
  int _expiringSoonCount = 0;
  int _occupiedSeatsCount = 0;
  int _shiftsCount = 0;

  // Real-time Supabase metrics additions
  int _activeTodayCount = 0;
  int _totalActiveMembers = 0;
  int _expiringTodayCount = 0;
  int _newJoiningsToday = 0;
  int _exitsToday = 0; // members who left the library today
  int _vacantSeatsCount = 0;
  int _holdSeatsCount = 0;
  double _occupancyPercentage = 0.0;
  bool _isStatsLoading = false;

  // New action required stats & navigation variables
  int _pendingPaymentProofsCount = 0;
  int _pendingJoinRequestsCount = 0;
  int _reservationsInitialSubTab = 0;
  RealtimeChannel? _joinRequestsChannel;

  // Form Controllers & State
  // Step 1: Profile
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  // Step 2: Library Stage 1
  final _libNameController = TextEditingController();
  final _libStreetController = TextEditingController();
  final _libCityController = TextEditingController();
  final _libStateController = TextEditingController();
  final _libPinController = TextEditingController();
  final _libRulesController = TextEditingController();
  final _libAboutController = TextEditingController();
  final _libEmergencyPhoneController = TextEditingController();

  // Step 3: Floor, Section & Seats

  // Step 4: Shifts & Plans
  final _shiftNameController = TextEditingController(text: 'General Shift');
  final _priceController = TextEditingController(text: '1000');
  final _trialDaysController = TextEditingController(text: '0');

  // Step 4a: Payments
  final _upiPaytmController = TextEditingController();
  final _upiPhonePeController = TextEditingController();
  final _upiGPayController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _checkRoleGuard();
    _inSetupMode = widget.startInSetupMode;
    _loadCachedInitialData().then((_) {
      _loadInitialData();
    });
  }

  Future<void> _checkRoleGuard() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user != null) {
        final userData = await supabase.from('users').select('role').eq('id', user.id).maybeSingle();
        if (userData != null && userData['role'] == 'member') {
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/member/home');
          }
        }
      }
    } catch (e) {
      debugPrint('Admin role guard check error: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _libNameController.dispose();
    _libStreetController.dispose();
    _libCityController.dispose();
    _libStateController.dispose();
    _libPinController.dispose();
    _libRulesController.dispose();
    _libAboutController.dispose();
    _libEmergencyPhoneController.dispose();
    _shiftNameController.dispose();
    _priceController.dispose();
    _trialDaysController.dispose();
    _upiPaytmController.dispose();
    _upiPhonePeController.dispose();
    _upiGPayController.dispose();
    if (_joinRequestsChannel != null) {
      Supabase.instance.client.removeChannel(_joinRequestsChannel!);
    }
    _introCtrl.dispose();
    super.dispose();
  }

  String _getAdminName() {
    final user = Supabase.instance.client.auth.currentUser;
    final metaName = user?.userMetadata?['full_name'] as String?;
    if (metaName != null && metaName.trim().isNotEmpty) {
      return metaName.trim();
    }
    if (_nameController.text.trim().isNotEmpty) {
      return _nameController.text.trim();
    }
    return 'Admin';
  }

  Future<void> _loadCachedInitialData() async {
    try {
      final cached = await CacheService.instance.readCache(
        'admin_owned_libraries',
      );
      if (cached != null && cached is List) {
        if (mounted) {
          setState(() {
            _myLibraries = List<Map<String, dynamic>>.from(cached);
            if (_myLibraries.isNotEmpty) {
              final bool hasMatch =
                  _libraryId != null &&
                  _myLibraries.any((l) => l['id'] == _libraryId);
              if (!hasMatch) {
                _libraryId = _myLibraries.first['id'];
              }
            }
          });
          if (_libraryId != null) {
            await _loadCachedDashboardStats(_libraryId!);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadCachedDashboardStats(String libId) async {
    try {
      final cached = await CacheService.instance.readCache(
        'admin_dashboard_stats_$libId',
      );
      if (cached != null && cached is Map) {
        if (mounted) {
          setState(() {
            _hasCachedStats = true;
            _shiftsCount = cached['shiftsCount'] ?? 0;
            _totalSeats = cached['totalSeats'] ?? 0;
            _occupiedSeatsCount = cached['occupiedSeatsCount'] ?? 0;
            _totalMembers = cached['totalMembers'] ?? 0;
            _activeMembers = cached['activeMembers'] ?? 0;
            _expiredCount = cached['expiredCount'] ?? 0;
            _newJoiningsThisMonth = cached['newJoiningsThisMonth'] ?? 0;
            _todayAttendance = List<Map<String, dynamic>>.from(
              cached['todayAttendance'] ?? [],
            );
            _libraryName = cached['libraryName'] ?? 'Your Library';
            _libraryCode = cached['libraryCode'] ?? 'SIL-XXXXXX';
            _coverPhotoUrl = cached['coverPhotoUrl'];
            _libraryAddress =
                cached['libraryAddress'] ??
                'Setup your library details to activate';
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _writeDashboardStatsToCache(String libId) async {
    final stats = {
      'shiftsCount': _shiftsCount,
      'totalSeats': _totalSeats,
      'occupiedSeatsCount': _occupiedSeatsCount,
      'totalMembers': _totalMembers,
      'activeMembers': _activeMembers,
      'expiredCount': _expiredCount,
      'newJoiningsThisMonth': _newJoiningsThisMonth,
      'todayAttendance': _todayAttendance,
      'libraryName': _libraryName,
      'libraryCode': _libraryCode,
      'coverPhotoUrl': _coverPhotoUrl,
      'libraryAddress': _libraryAddress,
    };
    await CacheService.instance.writeCache(
      'admin_dashboard_stats_$libId',
      stats,
    );
    if (!mounted) return;
  }

  Future<void> _loadInitialData() async {
    if (_myLibraries.isEmpty) {
      setState(() {});
    }
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    _step1Complete = false;
    _step2Complete = false;
    _step3Complete = false;
    _step4Complete = false;

    if (user != null) {
      _nameController.text = user.userMetadata?['full_name'] ?? '';
      try {
        // 1. Fetch User Profile
        final userData = await supabase
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();
        if (userData != null) {
          // Account scheduled for deletion → freeze (block dashboard).
          if (userData['scheduled_for_deletion'] == true) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/account-frozen', (r) => false);
              }
            });
            return;
          }
          // Keep PlanService in sync so feature gates read the right plan.
          PlanService.instance.hydrateFromRow(userData);
          _nameController.text = userData['full_name'] ?? '';
          _phoneController.text = userData['phone'] ?? '';
          final String name = userData['full_name'] ?? '';
          final String phone = userData['phone'] ?? '';
          final String gender = userData['gender'] ?? '';
          final String dob = userData['date_of_birth'] ?? '';
          final String address = userData['address'] ?? '';
          final String photoUrl = userData['photo_url'] ?? '';
          if (name.isNotEmpty &&
              phone.isNotEmpty &&
              gender.isNotEmpty &&
              dob.isNotEmpty &&
              address.isNotEmpty &&
              photoUrl.isNotEmpty) {
            _step1Complete = true;
          }
        }

        // 2. Fetch All Owned Libraries Info
        final libsRes = await supabase
            .from('libraries')
            .select()
            .eq('owner_id', user.id);
        _myLibraries = List<Map<String, dynamic>>.from(libsRes);
        CacheService.instance.writeCache('admin_owned_libraries', libsRes);

        if (_myLibraries.isNotEmpty) {
          final bool hasMatch =
              _libraryId != null &&
              _myLibraries.any((l) => l['id'] == _libraryId);
          if (!hasMatch) {
            _libraryId = _myLibraries.first['id'];
          }
          await _loadLibrarySpecificData(_libraryId!);
        } else {
          _inSetupMode = true;
          _libraryCode = 'SIL-XXXXXX';
          _libraryName = 'Your Library';
          _libraryAddress = 'Setup your library details to activate';
        }
      } catch (e) {
        debugPrint('Error loading admin setup data: $e');
      }
    } else {
      _inSetupMode = true;
    }

    if (mounted) {
      setState(() {
        _initialLoadDone = true;
      });
    }
  }

  Future<void> _loadLibrarySpecificData(String libId) async {
    final supabase = Supabase.instance.client;
    try {
      final libData = await supabase
          .from('libraries')
          .select()
          .eq('id', libId)
          .maybeSingle();
      if (libData != null) {
        _libraryId = libData['id'];
        _libraryCode = libData['library_code'] ?? 'SIL-XXXXXX';
        _libraryName = libData['name'] ?? 'Your Library';
        _coverPhotoUrl = libData['cover_photo_url'];
        _qrVersion = libData['qr_version'] ?? 1;
        if (_coverPhotoUrl == null || _coverPhotoUrl!.isEmpty) {
          final photosArr = libData['photos'] as List?;
          if (photosArr != null && photosArr.isNotEmpty) {
            _coverPhotoUrl = photosArr.first.toString();
          }
        }

        final String street = libData['address_street'] ?? '';
        final String city = libData['address_city'] ?? '';
        _libraryAddress = street.isNotEmpty
            ? '$street, $city'
            : 'Setup your library details to activate';

        _libNameController.text = _libraryName;
        _libStreetController.text = libData['address_street'] ?? '';
        _libCityController.text = libData['address_city'] ?? '';
        _libStateController.text = libData['address_state'] ?? '';
        _libPinController.text = libData['address_pincode'] ?? '';
        _libRulesController.text = libData['rules'] ?? '';
        _libAboutController.text = libData['about_text'] ?? '';
        _libEmergencyPhoneController.text = libData['emergency_phone'] ?? '';

        // Step 2 Complete if basic fields are set
        final String state = libData['address_state'] ?? '';
        final String pincode = libData['address_pincode'] ?? '';
        if (_libraryName.isNotEmpty &&
            street.isNotEmpty &&
            city.isNotEmpty &&
            state.isNotEmpty &&
            pincode.isNotEmpty) {
          _step2Complete = true;
        }

        final String status = libData['status'] ?? 'setup';
        _inSetupMode = (status == 'setup');

        // 3. Check Shifts Setup (Step 4)
        final shifts = await supabase
            .from('shifts')
            .select('id')
            .eq('library_id', libId)
            .eq('is_archived', false);
        _shiftsCount = shifts.length;
        bool isPaymentConfigured = false;
        final socialLinks = libData['social_links'] as Map<String, dynamic>?;
        if (socialLinks != null) {
          final cashEnabled = socialLinks['cash_enabled'] as bool? ?? false;
          final upiIds = socialLinks['upi_ids'] as List? ?? [];
          if (cashEnabled || upiIds.isNotEmpty) {
            isPaymentConfigured = true;
          }
        }
        if (shifts.isNotEmpty && isPaymentConfigured) {
          _step4Complete = true;
        }

        // 4. Check Layout/Seats Setup (Step 3)
        final floors = await supabase
            .from('floors')
            .select('id')
            .eq('library_id', libId);
        final seats = await supabase
            .from('seats')
            .select('id')
            .eq('library_id', libId);
        _totalSeats = seats.length;
        if (floors.isNotEmpty && seats.isNotEmpty) {
          _step3Complete = true;
          final occupiedSeats = await supabase
              .from('seats')
              .select('id')
              .eq('library_id', libId)
              .eq('status', 'occupied');
          _occupiedSeatsCount = occupiedSeats.length;
        }

        // Fetch operational stats dynamically from memberships
        await _fetchRealStats(libId);

        await _loadOperationalFeeds(libId);
        _setupJoinRequestsSubscription(libId);
        await _writeDashboardStatsToCache(libId);
        await _loadOpenQueriesCount(libId);
        await _loadUnreadNotifications();

        try {
          _todayHoliday = await HolidayService.instance.todaysHoliday(libId);
        } catch (_) {
          _todayHoliday = null;
        }
      }
    } catch (e) {
      debugPrint('Error loading library specific data: $e');
    }
  }

  bool _hasCachedStats = false; // true once cached dashboard stats are hydrated

  int _openQueriesCount = 0; // unreplied (status='open') queries → Queries badge
  int _unreadNotifications = 0; // unread in-app notifications → header bell badge

  Future<void> _loadUnreadNotifications() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final rows = await Supabase.instance.client
          .from('notifications')
          .select('id')
          .eq('user_id', user.id)
          .isFilter('read_at', null);
      if (mounted) setState(() => _unreadNotifications = (rows as List).length);
    } catch (e) {
      debugPrint('Unread notifications count load failed: $e');
    }
  }

  Future<void> _loadOpenQueriesCount(String libId) async {
    try {
      final rows = await Supabase.instance.client
          .from('queries')
          .select('id')
          .eq('library_id', libId)
          .eq('status', 'open');
      if (mounted) setState(() => _openQueriesCount = (rows as List).length);
    } catch (e) {
      debugPrint('Open queries count load failed: $e');
    }
  }

  Future<void> _fetchRealStats(String libId) async {
    // Only blank the stat cards to skeletons when we have no cached values to
    // show; otherwise keep the cached numbers and refresh silently.
    if (mounted && !_hasCachedStats) {
      setState(() => _isStatsLoading = true);
    }
    final supabase = Supabase.instance.client;
    final now = DateTime.now();

    final todayMidnight = DateTime(now.year, now.month, now.day);
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final firstDayOfMonthStr = DateTime(
      now.year,
      now.month,
      1,
    ).toIso8601String();
    final tomorrowStr = DateFormat(
      'yyyy-MM-dd',
    ).format(now.add(const Duration(days: 1)));
    final sevenDaysLaterStr = DateFormat(
      'yyyy-MM-dd',
    ).format(now.add(const Duration(days: 7)));

    try {
      // 1. Active Today: distinct members count with attendance today
      final attendanceRes = await supabase
          .from('attendance')
          .select('member_id')
          .eq('library_id', libId)
          .gte('check_in_time', todayMidnight.toIso8601String());

      _activeTodayCount = (attendanceRes as List)
          .map((row) => row['member_id'])
          .toSet()
          .length;

      // Total active members: memberships status = 'active'
      final activeMembershipsRes = await supabase
          .from('memberships')
          .select('id')
          .eq('library_id', libId)
          .eq('status', 'active');

      _totalActiveMembers = activeMembershipsRes.length;

      // 2. Expired: status = 'expired' and end_date < today
      final expiredRes = await supabase
          .from('memberships')
          .select('id')
          .eq('library_id', libId)
          .eq('status', 'expired')
          .lt('end_date', todayStr);

      _expiredCount = expiredRes.length;

      // Expiring Today: end_date = today
      final expiringTodayRes = await supabase
          .from('memberships')
          .select('id')
          .eq('library_id', libId)
          .eq('end_date', todayStr);

      _expiringTodayCount = expiringTodayRes.length;

      // 3. Revenue This Month: payments amount sum where status = 'confirmed' and payment_date >= first day of month
      // Today's revenue: payment_date = today
      final paymentsRes = await supabase
          .from('payments')
          .select('amount, payment_date')
          .eq('library_id', libId)
          .eq('status', 'confirmed')
          .gte('payment_date', firstDayOfMonthStr);

      int revSum = 0;
      int revToday = 0;
      for (final p in paymentsRes as List) {
        final amt = p['amount'] as int? ?? 0;
        revSum += amt;
        final pDateStr = p['payment_date'] as String?;
        if (pDateStr != null && pDateStr.startsWith(todayStr)) {
          revToday += amt;
        }
      }
      _revenueThisMonth = revSum;
      _revenueToday = revToday;

      // 4. New Joinings: memberships created_at >= first day of month
      // Today's count: created_at >= today midnight
      final joiningsRes = await supabase
          .from('memberships')
          .select('created_at')
          .eq('library_id', libId)
          .gte('created_at', firstDayOfMonthStr);

      int joinMonth = 0;
      int joinToday = 0;
      final todayMidnightIso = todayMidnight.toIso8601String();
      for (final m in joiningsRes as List) {
        joinMonth++;
        final created = m['created_at'] as String?;
        if (created != null && created.compareTo(todayMidnightIso) >= 0) {
          joinToday++;
        }
      }
      _newJoiningsThisMonth = joinMonth;
      _newJoiningsToday = joinToday;

      // 4b. Exits today: memberships that left (status 'exited') today.
      try {
        final exitsRes = await supabase
            .from('memberships')
            .select('id')
            .eq('library_id', libId)
            .eq('status', 'exited')
            .gte('exited_at', todayMidnightIso);
        _exitsToday = (exitsRes as List).length;
      } catch (e) {
        debugPrint('Error loading exits today: $e');
        _exitsToday = 0;
      }

      // 5. Expiring Soon: memberships end_date between tomorrow and today+7 days
      final expiringSoonRes = await supabase
          .from('memberships')
          .select('id')
          .eq('library_id', libId)
          .gte('end_date', tomorrowStr)
          .lte('end_date', sevenDaysLaterStr);

      _expiringSoonCount = expiringSoonRes.length;

      // 6. Live Occupancy: seats occupied for current shift (or all shifts if no current shift)
      final shiftsRes = await supabase
          .from('shifts')
          .select()
          .eq('library_id', libId)
          .eq('is_archived', false);

      final currentShifts = (shiftsRes as List)
          .where((s) => _isCurrentShift(s, now))
          .toList();

      final seatsRes = await supabase
          .from('seats')
          .select()
          .eq('library_id', libId);

      final seatList = List<Map<String, dynamic>>.from(seatsRes);
      List<Map<String, dynamic>> activeSeats = seatList;
      if (currentShifts.isNotEmpty) {
        final currentShiftIds = currentShifts
            .map((s) => s['id'].toString())
            .toSet();
        activeSeats = seatList
            .where(
              (seat) => currentShiftIds.contains(seat['shift_id']?.toString()),
            )
            .toList();
      }

      _totalSeats = activeSeats.length;
      _occupiedSeatsCount = activeSeats
          .where((seat) => seat['status'] == 'occupied')
          .length;
      _vacantSeatsCount = activeSeats
          .where((seat) => seat['status'] == 'vacant' || seat['status'] == null)
          .length;
      _holdSeatsCount = activeSeats
          .where((seat) => seat['status'] == 'hold')
          .length;
      _occupancyPercentage = _totalSeats > 0
          ? (_occupiedSeatsCount / _totalSeats) * 100
          : 0.0;

      // Fetch pending join requests for this library (Issue 1)
      final pendingRequestsRes = await supabase
          .from('join_requests')
          .select('id, payment_proof_url')
          .eq('library_id', libId)
          .eq('status', 'pending');

      final List pendingList = pendingRequestsRes as List;
      _pendingJoinRequestsCount = pendingList.length;
      _pendingPaymentProofsCount = pendingList
          .where((r) => r['payment_proof_url'] != null && r['payment_proof_url'].toString().trim().isNotEmpty)
          .length;
    } catch (e) {
      debugPrint('Error loading real-time dashboard stats: $e');
    } finally {
      if (mounted) {
        setState(() => _isStatsLoading = false);
      }
    }
  }

  void _setupJoinRequestsSubscription(String libId) {
    final supabase = Supabase.instance.client;
    if (_joinRequestsChannel != null) {
      supabase.removeChannel(_joinRequestsChannel!);
    }
    _joinRequestsChannel = supabase
        .channel('public:join_requests:library_id=eq.$libId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'join_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'library_id',
            value: libId,
          ),
          callback: (payload) {
            if (mounted) {
              _fetchRealStats(libId);
              _loadOperationalFeeds(libId);
            }
          },
        )
        .subscribe();
  }

  bool _isCurrentShift(Map<String, dynamic> shift, DateTime now) {
    try {
      final startStr = shift['start_time'] as String?;
      final endStr = shift['end_time'] as String?;
      if (startStr == null || endStr == null) return false;

      final startParts = startStr.split(':');
      final endParts = endStr.split(':');

      final int startHour = startParts.isNotEmpty
          ? (int.tryParse(startParts[0]) ?? 8)
          : 8;
      final int startMin = startParts.length > 1
          ? (int.tryParse(startParts[1]) ?? 0)
          : 0;
      final int endHour = endParts.isNotEmpty
          ? (int.tryParse(endParts[0]) ?? 17)
          : 17;
      final int endMin = endParts.length > 1
          ? (int.tryParse(endParts[1]) ?? 0)
          : 0;

      final currentMinutes = now.hour * 60 + now.minute;
      final startMinutes = startHour * 60 + startMin;
      int endMinutes = endHour * 60 + endMin;

      if (endMinutes < startMinutes) {
        return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
      } else {
        return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
      }
    } catch (e) {
      return false;
    }
  }

  Future<void> _loadOperationalFeeds(String libId) async {
    final supabase = Supabase.instance.client;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    final endOfDay = DateTime(
      now.year,
      now.month,
      now.day + 1,
    ).toIso8601String();

    try {
      final attendanceRes = await supabase
          .from('attendance')
          .select(
            'check_in_time, check_out_time, member_id(id, full_name, photo_url), memberships(seats(seat_label))',
          )
          .eq('library_id', libId)
          .gte('check_in_time', startOfDay)
          .lt('check_in_time', endOfDay)
          .order('check_in_time', ascending: false)
          .limit(50);

      // Build SEPARATE check-in and check-out entries (a member who checked in
      // and out appears twice: one "In" at their check-in time and one "Out" at
      // their check-out time). At most one In and one Out per member (latest of
      // each), all sorted newest-event-first.
      final seenIn = <String>{};
      final seenOut = <String>{};
      final events = <Map<String, dynamic>>[];
      String fmt(String? raw) {
        if (raw == null || raw.isEmpty) return '';
        try {
          return DateFormat('hh:mm a').format(DateTime.parse(raw).toLocal());
        } catch (_) {
          return '';
        }
      }

      for (final row in List<Map<String, dynamic>>.from(attendanceRes)) {
        final member = row['member_id'];
        final memberId = member is Map ? member['id']?.toString() : null;
        final name = member is Map ? (member['full_name'] ?? 'Member').toString() : 'Member';
        final photo = member is Map ? (member['photo_url'] ?? '').toString() : '';
        final membership = row['memberships'];
        final seat = membership is Map ? membership['seats'] : null;
        final seatLabel = seat is Map ? (seat['seat_label'] ?? '').toString() : '';
        final ciRaw = row['check_in_time']?.toString();
        final coRaw = row['check_out_time']?.toString();

        // Check-in entry (latest per member).
        if (ciRaw != null && (memberId == null || !seenIn.contains(memberId))) {
          if (memberId != null) seenIn.add(memberId);
          events.add({
            'name': name,
            'photo': photo,
            'seat': seatLabel.isNotEmpty ? seatLabel : 'No Seat',
            'status': 'in',
            'time': fmt(ciRaw),
            '_sort': DateTime.tryParse(ciRaw) ?? DateTime(1970),
          });
        }
        // Check-out entry (latest per member), only if they actually checked out.
        if (coRaw != null && coRaw.isNotEmpty && (memberId == null || !seenOut.contains(memberId))) {
          if (memberId != null) seenOut.add(memberId);
          events.add({
            'name': name,
            'photo': photo,
            'seat': seatLabel.isNotEmpty ? seatLabel : 'No Seat',
            'status': 'out',
            'time': fmt(coRaw),
            '_sort': DateTime.tryParse(coRaw) ?? DateTime(1970),
          });
        }
      }

      events.sort((a, b) => (b['_sort'] as DateTime).compareTo(a['_sort'] as DateTime));
      for (final e in events) {
        e.remove('_sort');
      }
      _todayAttendance = events;
    } catch (e) {
      debugPrint('Error loading today attendance: $e');
      _todayAttendance = [];
    }

    try {
      final activityRes = await supabase
          .from('audit_log')
          .select('category, action_title, action_details, created_at')
          .order('created_at', ascending: false)
          .limit(6);

      _recentActivities = List<Map<String, dynamic>>.from(activityRes).map((
        row,
      ) {
        final title = row['action_title']?.toString() ?? 'Activity recorded';
        final details = row['action_details']?.toString() ?? '';
        return {
          'type': row['category']?.toString() ?? 'settings',
          'desc': details.isNotEmpty ? '$title: $details' : title,
          'time': _formatRelativeTime(row['created_at']),
        };
      }).toList();
    } catch (e) {
      debugPrint('Error loading recent activities: $e');
      _recentActivities = [];
    }
  }

  String _formatRelativeTime(dynamic value) {
    if (value == null) return '';
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Now';
      if (diff.inHours < 1) return '${diff.inMinutes}m';
      if (diff.inDays < 1) return '${diff.inHours}h';
      return '${diff.inDays}d';
    } catch (_) {
      return '';
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: const Color(0xFFE65C00),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _formatSpacedCode(String code) {
    return code.split('').join(' ');
  }

  // Dialog-based onboarding methods removed in favor of full-screen screens

  void _showCongratulationsPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF3ED),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('🎉', style: TextStyle(fontSize: 36)),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Congratulations!',
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFE65C00),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Your library is now live.',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'You can now add members, manage seats, and track attendance. Complete additional details like social links, library rules, and branding from the Library Profile section.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF64748B),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _inSetupMode = false;
                      });
                      _loadInitialData();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Go to Dashboard',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _generateLibraryCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = math.Random();
    final code = List.generate(
      6,
      (index) => chars[rand.nextInt(chars.length)],
    ).join();
    return 'SIL-$code';
  }

  // --- LAUNCH LIBRARY ACTION ---
  Future<void> _launchLibrary() async {
    if (_stepsDoneCount < 4) {
      _showErrorSnackBar(
        'Please complete all 4 onboarding steps before launching.',
      );
      return;
    }

    setState(() {});
    try {
      final supabase = Supabase.instance.client;
      final uniqueCode = _generateLibraryCode();

      // Update library status to active AND assign the unique code upon launch
      await supabase
          .from('libraries')
          .update({'status': 'active', 'library_code': uniqueCode})
          .eq('id', _libraryId!);

      // Activate the admin's one-time 14-day starter trial via RPC. Direct
      // client writes to subscription_* are blocked by the privileged-column
      // guard (migrations/2026-06-18_lock_user_privileged_columns.sql).
      final trialUid = supabase.auth.currentUser?.id;
      if (trialUid == null) {
        if (mounted) _showErrorSnackBar('Session expired. Please sign in again.');
        return;
      }
      await supabase.rpc('start_my_trial');
      if (!mounted) return;

      _showCongratulationsPopup();
    } catch (e) {
      _showErrorSnackBar('Failed to launch library space: $e');
    } finally {
      setState(() {});
    }
  }

  void _continueSetup() {
    if (!_step1Complete) {
      Navigator.pushNamed(
        context,
        '/admin/profile/complete',
      ).then((_) => _loadInitialData());
    } else if (!_step2Complete) {
      Navigator.pushNamed(
        context,
        '/admin/library/setup/1',
      ).then((_) => _loadInitialData());
    } else if (!_step3Complete) {
      Navigator.pushNamed(
        context,
        '/admin/library/setup/2',
      ).then((_) => _loadInitialData());
    } else if (!_step4Complete) {
      Navigator.pushNamed(
        context,
        '/admin/library/setup/3',
      ).then((_) => _loadInitialData());
    }
  }

  void _showPrerequisiteDialog(int stepNum, String prerequisiteTitle, String route) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(
            'Prerequisite Required',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
          ),
          content: Text(
            'You must complete Step $stepNum ($prerequisiteTitle) first. Would you like to complete it now?',
            style: GoogleFonts.inter(color: const Color(0xFF64748B)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(color: Colors.grey[500], fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final res = await Navigator.pushNamed(context, route);
                if (res == true || res == null) {
                  _loadInitialData();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Complete Now',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  // --- SUB-VIEWS BUILDERS (TABS) ---

  // TAB 0: HOME / DASHBOARD TAB
  Widget _buildHomeTab() {
    // Kick off the one-shot entrance animation the first time the loaded
    // dashboard is built.
    if (_initialLoadDone && !_introStarted) {
      _introStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _introCtrl.forward();
      });
    }
    if (!_initialLoadDone) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Shimmer(
              child: Container(
                height: 180,
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: const [
                    SkeletonBox(width: 150, height: 24),
                    SizedBox(height: 8),
                    SkeletonBox(width: 250, height: 16),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Shimmer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SkeletonBox(height: 120),
                    const SizedBox(height: 16),
                    const SkeletonBox(width: 120, height: 20),
                    const SizedBox(height: 12),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.5,
                      children: const [
                        SkeletonBox(),
                        SkeletonBox(),
                        SkeletonBox(),
                        SkeletonBox(),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const SkeletonBox(width: 140, height: 20),
                    const SizedBox(height: 12),
                    const SkeletonBox(height: 80),
                    const SizedBox(height: 12),
                    const SkeletonBox(height: 80),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _loadInitialData(),
      color: const Color(0xFFE65C00),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Curved Gradient Banner Header (Matching Image 2)
            _buildCurvedHeader(),

            // 2. Onboarding Setup Card OR Operational Dashboard (Below Banner)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_inSetupMode) ...[
                    // Checklist Onboarding Card
                    _buildSetupOnboardingCard(),
                    const SizedBox(height: 16),
                    // Monospaced Code Card
                    _buildInvitationCodeCard(),
                    const SizedBox(height: 20),
                    // Stats Grid showing zeros as per spec S010-A
                    _buildOperationalStatsSection(),
                  ] else ...[
                    // S010-B Operational Dashboard
                    _buildOperationalDashboard(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- SUB-WIDGETS BUILDERS ---

  void _showLibrarySwitcherPopup(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Library Switcher',
      barrierColor: Colors.black.withValues(alpha: 0.15),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: const Alignment(-0.85, -0.72),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 280,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  ..._myLibraries.map((lib) {
                    final bool isSelected =
                        lib['id'].toString().toLowerCase() ==
                        _libraryId.toString().toLowerCase();
                    final String? city = lib['address_city'];
                    final String? coverUrl = lib['cover_photo_url'];
                    final List<dynamic> photos = lib['photos'] ?? [];
                    String? itemCover;
                    if (coverUrl != null && coverUrl.isNotEmpty) {
                      itemCover = coverUrl;
                    } else if (photos.isNotEmpty) {
                      itemCover = photos.first.toString();
                    }

                    return InkWell(
                      onTap: () async {
                        Navigator.pop(context);
                        setState(() {
                          _libraryId = lib['id'];
                        });
                        await _loadLibrarySpecificData(lib['id']);
                        if (mounted) {
                          setState(() {});
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFF1F5F9),
                              ),
                              child: itemCover != null && itemCover.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(20),
                                      child: Image.network(
                                        itemCover,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const Icon(
                                                  Icons.business_rounded,
                                                  color: Color(0xFFE65C00),
                                                  size: 20,
                                                ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.business_rounded,
                                      color: Color(0xFFE65C00),
                                      size: 20,
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    lib['name'] ?? 'Library',
                                    style: GoogleFonts.outfit(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    city ?? 'Location',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check,
                                color: Color(0xFFE65C00),
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  InkWell(
                    onTap: () async {
                      final nav = Navigator.of(context);
                      // Adding a SECOND+ library is a Premium (multi-library) feature.
                      // Gate BEFORE closing the switcher so the context stays valid
                      // (inert during beta — see core/plan_service.dart).
                      if (!await ensurePlan(context, AdminFeature.multiLibrary,
                          featureLabel: 'Managing multiple libraries')) {
                        return;
                      }
                      nav.pop(); // close the switcher
                      nav.pushNamed('/admin/library/setup/1').then((_) {
                        _loadInitialData();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.add,
                            color: Color(0xFFE65C00),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '+ Add Library',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFE65C00),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
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

  Widget _buildCurvedHeader() {
    final todayFormatted = DateFormat(
      'EEE dd/MM',
    ).format(DateTime.now()).toUpperCase();

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 16,
        right: 16,
        bottom: 32,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFF6B00), // Vibrant Bright Orange
            Color(0xFFE65C00), // Primary Brand Orange
          ],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.0),
                  color: Colors.white,
                ),
                child: _coverPhotoUrl != null && _coverPhotoUrl!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(25),
                        child: Image.network(
                          _coverPhotoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.business_rounded,
                                color: Color(0xFFE65C00),
                                size: 26,
                              ),
                        ),
                      )
                    : const Icon(
                        Icons.business_rounded,
                        color: Color(0xFFE65C00),
                        size: 26,
                      ),
              ),
              const SizedBox(width: 8),

              // Library Dropdown Title with switcher
              Expanded(
                child: _myLibraries.isEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _libraryName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: Colors.white70,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _libraryAddress,
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    color: Colors.white.withValues(alpha: 0.85),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : InkWell(
                        onTap: () => _showLibrarySwitcherPopup(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _libraryName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  color: Colors.white70,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    _libraryAddress,
                                    style: GoogleFonts.inter(
                                      fontSize: 10.5,
                                      color: Colors.white.withValues(alpha: 0.85),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
              ),

              const SizedBox(width: 8),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5),
                        width: 1.0,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    child: Text(
                      todayFormatted,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.notifications_none_rounded,
                          color: Colors.white.withValues(alpha: 0.9),
                          size: 28,
                        ),
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            '/member/notifications',
                          );
                        },
                      ),
                      if (_unreadNotifications > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white, width: 1.4),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _unreadNotifications > 9 ? '9+' : '$_unreadNotifications',
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Greeting line
          Text(
            'Good morning, ${_getAdminName()} 👏',
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Here's what's happening today.",
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          if (!_inSetupMode) ...[
            const SizedBox(height: 16),
            _buildHeaderSummary(),
          ],
        ],
      ),
    );
  }

  /// A one-glance summary strip on the header: who's in, what's pending, today's
  /// revenue. Read-only (no new actions) — additive scannability.
  Widget _buildHeaderSummary() {
    final pending = _pendingPaymentProofsCount + _pendingJoinRequestsCount;
    final inCount = _todayAttendance.length;
    final money = _revenueToday >= 100000
        ? '₹${(_revenueToday / 1000).toStringAsFixed(0)}k'
        : '₹$_revenueToday';

    Widget chip(IconData icon, String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ]),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip(Icons.login_rounded, '$inCount in today'),
        chip(Icons.pending_actions_rounded, '$pending pending'),
        chip(Icons.payments_rounded, '$money today'),
      ]),
    );
  }

  Widget _buildSetupOnboardingCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: const Border(
          left: BorderSide(color: Color(0xFFE65C00), width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Complete Library setup',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                Text(
                  '$_stepsDoneCount/4 done',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _setupProgress,
                minHeight: 6,
                backgroundColor: Colors.grey[100],
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFE65C00),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 5 Step List items
            _buildSetupStepItem(
              stepNum: 1,
              title: 'Admin Profile',
              subtitle: 'Add your personal details',
              isDone: _step1Complete,
              onTap: () async {
                final res = await Navigator.pushNamed(
                  context,
                  '/admin/profile/complete',
                );
                if (res == true || res == null) {
                  _loadInitialData();
                }
              },
            ),
            _buildSetupStepItem(
              stepNum: 2,
              title: 'Library Basic Info',
              subtitle: 'Add library details & photos',
              isDone: _step2Complete,
              onTap: () async {
                if (!_step1Complete) {
                  _showPrerequisiteDialog(1, 'Admin Profile', '/admin/profile/complete');
                  return;
                }
                final res = await Navigator.pushNamed(
                  context,
                  '/admin/library/setup/1',
                );
                if (res == true || res == null) {
                  _loadInitialData();
                }
              },
            ),
            _buildSetupStepItem(
              stepNum: 3,
              title: 'Layout Setup',
              subtitle: 'Add floors, sections & seats',
              isDone: _step3Complete,
              onTap: () async {
                if (!_step1Complete) {
                  _showPrerequisiteDialog(1, 'Admin Profile', '/admin/profile/complete');
                  return;
                }
                if (!_step2Complete) {
                  _showPrerequisiteDialog(2, 'Library Basic Info', '/admin/library/setup/1');
                  return;
                }
                final res = await Navigator.pushNamed(
                  context,
                  '/admin/library/setup/2',
                );
                if (res == true || res == null) {
                  _loadInitialData();
                }
              },
            ),
            _buildSetupStepItem(
              stepNum: 4,
              title: 'Shifts & Plans + Payment',
              subtitle: 'Timings, pricing, Cash & UPI setup',
              isDone: _step4Complete,
              onTap: () async {
                if (!_step1Complete) {
                  _showPrerequisiteDialog(1, 'Admin Profile', '/admin/profile/complete');
                  return;
                }
                if (!_step2Complete) {
                  _showPrerequisiteDialog(2, 'Library Basic Info', '/admin/library/setup/1');
                  return;
                }
                if (!_step3Complete) {
                  _showPrerequisiteDialog(3, 'Layout Setup', '/admin/library/setup/2');
                  return;
                }
                final res = await Navigator.pushNamed(
                  context,
                  '/admin/library/setup/3',
                );
                if (res == true || res == null) {
                  _loadInitialData();
                }
              },
            ),

            const SizedBox(height: 18),

            // Launch Library Button or Continue Setup Button
            ElevatedButton(
              onPressed: () {
                if (_stepsDoneCount >= 4) {
                  _launchLibrary();
                } else {
                  _continueSetup();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: Text(
                _stepsDoneCount >= 4 ? 'Launch Library 🚀' : 'Continue Setup →',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupStepItem({
    required int stepNum,
    required String title,
    required String subtitle,
    required bool isDone,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? const Color(0xFF22C55E) : Colors.transparent,
                border: Border.all(
                  color: isDone ? const Color(0xFF22C55E) : Colors.grey[300]!,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : Text(
                        '$stepNum',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                          fontSize: 13,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildInvitationCodeCard() {
    final spacedCode = _formatSpacedCode(_libraryCode);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Library Code',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                spacedCode,
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFE65C00),
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: () =>
                _showSuccessSnackBar('Library Code copied to clipboard!'),
            icon: const Icon(Icons.share, size: 16, color: Color(0xFFE65C00)),
            label: Text(
              'Share',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFE65C00),
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: const Color(0xFFE65C00).withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  // State variables for Operational Mode Dashboard
  int _carouselIndex = 0;

  List<Map<String, dynamic>> _todayAttendance = [];

  List<Map<String, dynamic>> _recentActivities = [];

  /// Staggered fade + slide-up entrance for a dashboard section. Driven by the
  /// one-shot _introCtrl, so it plays once and then renders at its final state.
  Widget _intro(int order, Widget child) {
    final start = (order * 0.07).clamp(0.0, 0.55);
    final anim = CurvedAnimation(
      parent: _introCtrl,
      curve: Interval(start, (start + 0.45).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - anim.value)),
          child: child,
        ),
      ),
    );
  }

  Widget _buildOperationalDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 0. Today-is-a-holiday banner (conditional)
        if (_todayHoliday != null) ...[
          _intro(0, _buildHolidayBanner(_todayHoliday!)),
          const SizedBox(height: 16),
        ],

        // 1. Action Required — highest priority, directly under the header.
        if (_pendingPaymentProofsCount + _pendingJoinRequestsCount > 0) ...[
          _intro(1, _buildActionRequiredBanner()),
          const SizedBox(height: 20),
        ],

        // 2. Stats Section (Revenue, 2x2 grid, Live Occupancy)
        _intro(2, _buildOperationalStatsSection()),
        const SizedBox(height: 20),

        // 3. Today's Attendance strip
        _intro(3, _buildAttendanceStrip()),
        const SizedBox(height: 20),

        // 4. Quick Actions Row
        _intro(4, _buildQuickActionsRow()),
        const SizedBox(height: 20),

        // 5. QR Codes Row
        _intro(5, _buildQRCodesRow()),
        const SizedBox(height: 20),

        // 6. Recent Activities Feed
        _intro(6, _buildRecentActivityFeed()),
        const SizedBox(height: 20),

        // 7. Secondary / least daily-critical → moved to the bottom:
        //    library code (share to grow) + decorative photo carousel.
        if (!_inSetupMode) ...[
          _intro(7, _buildInvitationCodeCard()),
          const SizedBox(height: 20),
        ],
        _intro(8, _buildPhotoCarousel()),
      ],
    );
  }

  Widget _buildPhotoCarousel() {
    final List<String> carouselTitles = [
      'Silent Reading Zone',
      'Discussion Lounge',
      'Personal Locker Section',
    ];
    final List<List<Color>> carouselGradients = [
      [const Color(0xFFFF6B00), const Color(0xFFC44E00)],
      [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)],
      [const Color(0xFF10B981), const Color(0xFF047857)],
    ];

    return Column(
      children: [
        SizedBox(
          height: 160,
          child: PageView.builder(
            itemCount: 3,
            onPageChanged: (index) {
              setState(() {
                _carouselIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: carouselGradients[index],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.1,
                        child: Image.asset(
                          'assets/images/horizontal app logo.png',
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Downtown Branch',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            carouselTitles[index],
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Premium ergonomically designed desking space',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _carouselIndex == index ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: _carouselIndex == index
                    ? const Color(0xFFE65C00)
                    : const Color(0xFFE5E7EB),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 80,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonRevenueCard() {
    return Container(
      height: 96,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 120,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 80,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '💰 Revenue This Month',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF6B7280),
                ),
              ),
              GestureDetector(
                onTap: () =>
                    setState(() => _currentTab = 2), // Go to Bookings/Analytics
                child: const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '₹$_revenueThisMonth',
            style: GoogleFonts.outfit(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.arrow_upward,
                size: 14,
                color: Color(0xFF22C55E),
              ),
              const SizedBox(width: 4),
              Text(
                '+₹$_revenueToday today',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF22C55E),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: Color(0xFF9CA3AF),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '₹$_revenuePending pending',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonOccupancyCard() {
    return Container(
      height: 120,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 100,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOccupancyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '🔵 Live Occupancy',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF6B7280),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _currentTab =
                        1; // Navigate to Reservations (which contains layout sub-tab)
                  });
                },
                icon: const Icon(
                  Icons.map_outlined,
                  size: 14,
                  color: Color(0xFFE65C00),
                ),
                label: Text(
                  'View Map',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFE65C00),
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: _totalSeats > 0
                          ? (_occupiedSeatsCount / _totalSeats)
                          : 0.0,
                      strokeWidth: 10,
                      backgroundColor: const Color(0xFFE5E7EB),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF3B82F6),
                      ),
                    ),
                  ),
                  Text(
                    "${_occupancyPercentage.toStringAsFixed(0)}%",
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFF3B82F6),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Occupied: $_occupiedSeatsCount seats',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1A1A2E),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE5E7EB),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Vacant: $_vacantSeatsCount seats',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF59E0B),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Hold: $_holdSeatsCount seats',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOperationalStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title Overview
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Text(
            'Overview',
            style: GoogleFonts.outfit(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A1A2E),
            ),
          ),
        ),

        // 1. Revenue Card (Full Width)
        _isStatsLoading ? _buildSkeletonRevenueCard() : _buildRevenueCard(),
        const SizedBox(
          height: 8,
        ), // Spacing reduced from 12 to 8 to make them closer
        // 2. 2x2 Stats Grid
        _isStatsLoading
            ? GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.35,
                children: [
                  _buildSkeletonCard(),
                  _buildSkeletonCard(),
                  _buildSkeletonCard(),
                  _buildSkeletonCard(),
                ],
              )
            : GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.35,
                children: [
                  _buildOperationalStatCard(
                    index: 0,
                    label: 'Active Today',
                    value: '$_activeTodayCount / $_totalActiveMembers',
                    subtext:
                        '${_totalActiveMembers > 0 ? (_activeTodayCount / _totalActiveMembers * 100).toStringAsFixed(0) : 0}% active rate',
                    icon: Icons.people,
                    iconColor: const Color(0xFF3B82F6),
                  ),
                  _buildOperationalStatCard(
                    index: 1,
                    label: 'Expired',
                    value: '$_expiredCount',
                    subtext: '$_expiringTodayCount Expiring Today',
                    icon: Icons.person_off,
                    iconColor: const Color(0xFFEF4444),
                  ),
                  _buildOperationalStatCard(
                    index: 2,
                    label: 'New Joinings',
                    value: '$_newJoiningsThisMonth',
                    subtext: '+$_newJoiningsToday today · $_exitsToday exits',
                    icon: Icons.person_add,
                    iconColor: const Color(0xFF10B981),
                  ),
                  _buildOperationalStatCard(
                    index: 3,
                    label: 'Expiring Soon',
                    value: '$_expiringSoonCount',
                    subtext: 'Within 7 Days',
                    icon: Icons.running_with_errors,
                    iconColor: const Color(0xFFF59E0B),
                  ),
                ],
              ),
        const SizedBox(height: 12),

        // 3. Live Occupancy card (Full Width)
        _isStatsLoading ? _buildSkeletonOccupancyCard() : _buildOccupancyCard(),
      ],
    );
  }

  Widget _buildOperationalStatCard({
    required String label,
    required String value,
    required String subtext,
    required IconData icon,
    required Color iconColor,
    int index = 0,
  }) {
    final Color finalIconColor = _inSetupMode
        ? const Color(0xFF9CA3AF)
        : iconColor;
    final Color finalValueColor = _inSetupMode
        ? const Color(0xFF9CA3AF)
        : const Color(0xFF1A1A2E);

    final Widget card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon in a soft tinted circle (no chevron — cards aren't tappable).
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: finalIconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: finalIconColor, size: 24),
          ),
          const SizedBox(height: 14),
          // Text block fills the freed space; FittedBox scales it down only on
          // very small screens so it never overflows.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: GoogleFonts.outfit(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: finalValueColor,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtext,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    // Entrance animation: fade + slide-up + subtle scale, staggered per card.
    // Cards are NOT tappable (tapping does nothing) except the setup-mode hint.
    return GestureDetector(
      onTap: _inSetupMode
          ? () => _showSuccessSnackBar('Complete setup to activate dashboard stats.')
          : null,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: Duration(milliseconds: 400 + index * 90),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) {
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - t)),
              child: Transform.scale(
                scale: 0.96 + 0.04 * t,
                child: child,
              ),
            ),
          );
        },
        child: card,
      ),
    );
  }

  Widget _buildActionRequiredBanner() {
    if (_pendingPaymentProofsCount == 0 && _pendingJoinRequestsCount == 0) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Action Required',
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w600, // semi-bold
            color: const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 12),
        if (_pendingPaymentProofsCount > 0) ...[
          _buildRedesignedActionRequiredRow(
            icon: Icons.payment_rounded,
            text: '$_pendingPaymentProofsCount payment proofs pending review',
            onTap: () {
              _navigateToReservationsRequestsTab();
            },
          ),
          if (_pendingJoinRequestsCount > 0) const SizedBox(height: 8),
        ],
        if (_pendingJoinRequestsCount > 0) ...[
          _buildRedesignedActionRequiredRow(
            icon: Icons.person_add_rounded,
            text: '$_pendingJoinRequestsCount join requests pending',
            onTap: () {
              _navigateToReservationsRequestsTab();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildRedesignedActionRequiredRow({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              // ignore: deprecated_member_use
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFE65C00), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  void _navigateToReservationsRequestsTab() {
    setState(() {
      _reservationsInitialSubTab = 2; // Requests sub-tab
      _currentTab = 1; // Reservations tab
    });
  }

  Widget _buildQuickActionsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildCircularActionButton(
              icon: Icons.person_add,
              label: 'Add Member',
              color: const Color(0xFF3B82F6), // Blue
              onTap: _showAddMemberWizard,
            ),
            _buildCircularActionButton(
              icon: Icons.campaign,
              label: 'Announce',
              color: const Color(0xFF8B5CF6), // Purple
              onTap: _showAnnouncementComposer,
            ),
            _buildCircularActionButton(
              icon: Icons.chat_bubble,
              label: 'Queries',
              color: const Color(0xFF06B6D4), // Teal
              badgeCount: _openQueriesCount,
              onTap: () async {
                await _showManageQueries();
                if (_libraryId != null && _libraryId != 'all') {
                  _loadOpenQueriesCount(_libraryId!);
                }
              },
            ),
            _buildCircularActionButton(
              icon: Icons.event_busy,
              label: 'Holidays',
              color: const Color(0xFFE65C00), // Orange
              onTap: _showCloseLibrarySheet,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCircularActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              if (badgeCount > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF374151),
          ),
        ),
      ],
    );
  }

  // ── Add Member Wizard (from Quick Action) ──────────────────────────────────
  void _showAddMemberWizard() {
    if (_libraryId == null) {
      _showErrorSnackBar('Please complete library setup first.');
      return;
    }
    // Guard: prevent adding member when no specific library is selected
    // (This can happen if the library switcher is showing "All Libraries")
    if (_libraryId == 'all') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a specific library first to add a member.'),
          backgroundColor: Color(0xFFE65C00),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.pushNamed(
      context,
      '/admin/member/add',
      arguments: {'libraryId': _libraryId},
    ).then((result) {
      if (result == true) {
        _loadLibrarySpecificData(_libraryId!).then((_) {
          if (mounted) setState(() {});
        });
      }
    });
  }

  // ── Announcement Composer Bottom Sheet ─────────────────────────────────────
  void _showAnnouncementComposer() {
    if (_libraryId == null) {
      _showErrorSnackBar('Please complete library setup first.');
      return;
    }
    final msgController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(
                        Icons.campaign,
                        color: Color(0xFF8B5CF6),
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'New Announcement',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Broadcast a message to all members of this library.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: msgController,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: InputDecoration(
                      hintText: 'Write your announcement here...',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF8B5CF6),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () async {
                      if (msgController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please write an announcement message.',
                            ),
                          ),
                        );
                        return;
                      }
                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      final supabase = Supabase.instance.client;
                      final msg = msgController.text.trim();
                      try {
                        await supabase.from('announcements').insert({
                          'library_id': _libraryId!,
                          'message': msg,
                          'admin_id': supabase.auth.currentUser?.id,
                        });

                        // Deliver to each member's notification centre (the bell
                        // reads `notifications`, not `announcements`). This is
                        // what made the broadcast feel "dead" before.
                        int delivered = 0;
                        try {
                          final memberRows = await supabase
                              .from('memberships')
                              .select('member_id')
                              .eq('library_id', _libraryId!);
                          final ids = <String>{};
                          for (final r in List<Map<String, dynamic>>.from(memberRows)) {
                            final id = r['member_id']?.toString();
                            if (id != null && id.isNotEmpty) ids.add(id);
                          }
                          if (ids.isNotEmpty) {
                            final rows = ids
                                .map((id) => {
                                      'user_id': id,
                                      'title': 'Announcement',
                                      'body': msg,
                                      'data': {'type': 'announcement'},
                                    })
                                .toList();
                            await supabase.from('notifications').insert(rows);
                            delivered = ids.length;
                          }
                        } catch (e) {
                          debugPrint('announcement notify failed: $e');
                        }

                        navigator.pop();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(delivered > 0
                                ? '📢 Announcement sent to $delivered member${delivered == 1 ? '' : 's'}.'
                                : '📢 Announcement saved (no members to notify yet).'),
                            backgroundColor: const Color(0xFF8B5CF6),
                          ),
                        );
                      } catch (e) {
                        messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    },
                    icon: const Icon(Icons.send, size: 18),
                    label: Text(
                      'Broadcast Now',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Manage Queries Bottom Sheet ─────────────────────────────────────────────
  Future<void> _showManageQueries() async {
    if (_libraryId == null) {
      _showErrorSnackBar('Please complete library setup first.');
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        // Hoist the query so incidental sheet rebuilds don't re-run it; only an
        // explicit refresh (after a reply) reassigns it.
        Future buildQuery() => Supabase.instance.client
            .from('queries')
            .select('*')
            .eq('library_id', _libraryId!)
            .order('created_at', ascending: false)
            .limit(30);
        var queriesFuture = buildQuery();
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return FutureBuilder(
              future: queriesFuture,
              builder: (context, AsyncSnapshot snapshot) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(
                            Icons.chat_bubble,
                            color: Color(0xFF06B6D4),
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Member Queries',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1A1A2E),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap a query to reply. The member sees your reply in "My Queries".',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        Shimmer(
                          child: Column(
                            children: List.generate(3, (index) => Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SkeletonBox(width: 40, height: 40, borderRadius: BorderRadius.all(Radius.circular(20))),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: const [
                                        SkeletonBox(width: 120, height: 16),
                                        SizedBox(height: 6),
                                        SkeletonBox(height: 14),
                                        SizedBox(height: 4),
                                        SkeletonBox(width: 180, height: 12),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )),
                          ),
                        )
                      else if (snapshot.hasError ||
                          snapshot.data == null ||
                          (snapshot.data as List).isEmpty)
                        Container(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                size: 48,
                                color: Colors.grey[300],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No queries yet',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF6B7280),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Member queries will appear here.',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.45,
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: (snapshot.data as List).length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final q = (snapshot.data as List)[i]
                                  as Map<String, dynamic>;
                              final status = (q['status'] ?? 'open').toString();
                              final replied = status == 'replied';
                              final closed = status == 'closed';
                              final hasReply =
                                  (q['admin_reply'] ?? '').toString().isNotEmpty;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                onTap: () => _openReplyToQuery(q,
                                    () => setSheet(() {
                                          queriesFuture = buildQuery();
                                        })),
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFFF0FDFA),
                                  child: Icon(
                                    hasReply
                                        ? Icons.mark_chat_read_outlined
                                        : Icons.help_outline,
                                    color: (replied || closed)
                                        ? Colors.green
                                        : const Color(0xFF06B6D4),
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  q['message'] ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: hasReply
                                    ? Text(
                                        'You replied: ${q['admin_reply']}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          color: const Color(0xFF16A34A),
                                        ),
                                      )
                                    : Text(
                                        'Tap to reply',
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (replied || closed)
                                        ? const Color(0xFFDCFCE7)
                                        : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: (replied || closed)
                                          ? const Color(0xFF16A34A)
                                          : const Color(0xFFD97706),
                                    ),
                                  ),
                                ),
                              );
                            },
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
      },
    );
  }

  // Reply to a member query: writes admin_reply + status='replied' + replied_at,
  // notifies the member, then refreshes the queries sheet. [onDone] re-renders.
  void _openReplyToQuery(Map<String, dynamic> query, VoidCallback onDone) {
    final existingReply = (query['admin_reply'] ?? '').toString();
    final replyCtrl = TextEditingController();
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Reply to member',
                  style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A1A2E))),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  query['message']?.toString() ?? '',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: const Color(0xFF475569)),
                ),
              ),
              if (existingReply.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Previous reply',
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF16A34A))),
                      const SizedBox(height: 4),
                      Text(existingReply,
                          style: GoogleFonts.inter(
                              fontSize: 12.5, color: const Color(0xFF166534))),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: replyCtrl,
                maxLines: 5,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  hintText: existingReply.isEmpty
                      ? 'Type your reply…'
                      : 'Add another reply…',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        final text = replyCtrl.text.trim();
                        if (text.isEmpty) {
                          ScaffoldMessenger.of(sheetCtx).showSnackBar(
                            const SnackBar(content: Text('Please type a reply.')),
                          );
                          return;
                        }
                        setSheet(() => saving = true);
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          final supabase = Supabase.instance.client;
                          final combined = existingReply.isEmpty
                              ? text
                              : '$existingReply\n\n— $text';
                          await supabase.from('queries').update({
                            'admin_reply': combined,
                            'status': 'replied',
                            'replied_at': DateTime.now().toIso8601String(),
                          }).eq('id', query['id']);

                          // Notify the member (honest: only after the write).
                          try {
                            await supabase.from('notifications').insert({
                              'user_id': query['member_id'],
                              'title': 'Your query was answered',
                              'body': text,
                              'data': {
                                'type': 'query_reply',
                                'query_id': query['id'],
                              },
                            });
                          } catch (e) {
                            debugPrint('query reply notify failed: $e');
                          }

                          if (!sheetCtx.mounted) return;
                          Navigator.pop(sheetCtx);
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Reply sent. Member notified.'),
                              backgroundColor: Color(0xFFE65C00),
                            ),
                          );
                          onDone();
                        } catch (e) {
                          setSheet(() => saving = false);
                          messenger.showSnackBar(
                            SnackBar(content: Text('Could not send reply: $e')),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text('Send reply',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── Holiday / Closure Bottom Sheet ─────────────────────────────────────────
  void _showCloseLibrarySheet() {
    if (_libraryId == null) {
      _showErrorSnackBar('Please complete library setup first.');
      return;
    }
    final reasonCtrl = TextEditingController();
    bool notify = true;
    bool saving = false;
    bool isRange = false;
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    DateTime startDate = today;
    DateTime endDate = today;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          Future<void> pickStart() async {
            final picked = await showCalendarGridBottomSheet(
              sheetCtx,
              initialDate: startDate,
              firstDate: today,
              lastDate: today.add(const Duration(days: 365)),
            );
            if (picked != null) {
              setSheet(() {
                startDate = DateTime(picked.year, picked.month, picked.day);
                if (endDate.isBefore(startDate)) endDate = startDate;
              });
            }
          }

          Future<void> pickEnd() async {
            final picked = await showCalendarGridBottomSheet(
              sheetCtx,
              initialDate: endDate.isBefore(startDate) ? startDate : endDate,
              firstDate: startDate,
              lastDate: startDate.add(const Duration(days: 365)),
            );
            if (picked != null) {
              setSheet(() => endDate = DateTime(picked.year, picked.month, picked.day));
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
              top: 20,
              left: 20,
              right: 20,
            ),
            child: SingleChildScrollView(
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3ED),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.event_busy,
                            color: Color(0xFFE65C00), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Add holiday / closure',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1A1A2E),
                              ),
                            ),
                            Text(
                              'Close the library for a day, a range, or a future date',
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Single day vs Date range toggle
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        _holidaySegment('Single day', !isRange, () {
                          setSheet(() {
                            isRange = false;
                            endDate = startDate;
                          });
                        }),
                        _holidaySegment('Date range', isRange, () {
                          setSheet(() {
                            isRange = true;
                            if (!endDate.isAfter(startDate)) {
                              endDate = startDate.add(const Duration(days: 1));
                            }
                          });
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  _holidayDateRow(isRange ? 'From' : 'Date', startDate, pickStart),
                  if (isRange) ...[
                    const SizedBox(height: 8),
                    _holidayDateRow('To', endDate, pickEnd),
                  ],
                  const SizedBox(height: 16),

                  // Instruction card (kept).
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFD1B3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What happens when you close:',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF92400E),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildCloseInfoRow('🛡️', 'Members’ study streaks are protected'),
                        const SizedBox(height: 4),
                        _buildCloseInfoRow('🚫', 'Check-in is blocked for everyone on these days'),
                        const SizedBox(height: 4),
                        _buildCloseInfoRow('⏹️', 'If you close today, anyone checked in is auto-checked-out'),
                        const SizedBox(height: 4),
                        _buildCloseInfoRow(
                            '🔔',
                            notify
                                ? 'Members get an in-app notification'
                                : 'Members are NOT notified'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: reasonCtrl,
                    style: GoogleFonts.inter(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Reason (e.g. Holi, Maintenance)',
                      hintStyle:
                          GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Notify all members',
                        style: GoogleFonts.inter(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    value: notify,
                    activeThumbColor: const Color(0xFFE65C00),
                    onChanged: (v) => setSheet(() => notify = v),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            if (reasonCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                const SnackBar(content: Text('Please add a reason.')),
                              );
                              return;
                            }
                            final end = isRange ? endDate : startDate;
                            final ok = await _confirmCloseLibrary(startDate, end);
                            if (ok != true) return;
                            if (!mounted) return;
                            setSheet(() => saving = true);
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              final created = await HolidayService.instance.addHoliday(
                                libraryId: _libraryId!,
                                start: startDate,
                                end: end,
                                reason: reasonCtrl.text.trim(),
                                notifyMembers: notify,
                              );
                              // If the closure covers today, end any open sessions.
                              int ended = 0;
                              if (created.covers(today)) {
                                ended = await HolidayService.instance
                                    .closeOpenSessionsNow(_libraryId!);
                                if (mounted) setState(() => _todayHoliday = created);
                              }
                              if (!sheetCtx.mounted) return;
                              Navigator.pop(sheetCtx);
                              final extra = ended > 0
                                  ? ' $ended active session${ended == 1 ? '' : 's'} ended.'
                                  : '';
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text((notify
                                          ? 'Holiday saved. Members notified.'
                                          : 'Holiday saved.') +
                                      extra),
                                  backgroundColor: const Color(0xFFE65C00),
                                ),
                              );
                              if (_libraryId != null) _loadLibrarySpecificData(_libraryId!);
                            } catch (e) {
                              setSheet(() => saving = false);
                              messenger.showSnackBar(
                                SnackBar(content: Text('Could not close: $e')),
                              );
                            }
                          },
                    icon: saving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.event_busy, size: 18),
                    label: Text('Save holiday',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ScheduledClosuresScreen(libraryId: _libraryId),
                        ),
                      ).then((_) {
                        if (_libraryId != null) _loadLibrarySpecificData(_libraryId!);
                      });
                    },
                    icon: const Icon(Icons.history, size: 18),
                    label: Text('Holiday history & upcoming',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE65C00),
                      side: const BorderSide(color: Color(0xFFE65C00)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Segment pill for the single-day / date-range toggle.
  Widget _holidaySegment(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? const Color(0xFFE65C00) : Colors.grey[500],
            ),
          ),
        ),
      ),
    );
  }

  Widget _holidayDateRow(String label, DateTime date, VoidCallback onTap) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF475569))),
        TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.calendar_month, size: 16, color: Color(0xFFE65C00)),
          label: Text(
            DateFormat('EEE, dd MMM yyyy').format(date),
            style: GoogleFonts.inter(
                fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
          ),
        ),
      ],
    );
  }

  /// Confirmation before closing: shows the current situation (active members,
  /// and — if the closure covers today — how many are checked in right now and
  /// will be auto-checked-out). Returns true if the admin confirms.
  Future<bool?> _confirmCloseLibrary(DateTime start, DateTime end) async {
    final libId = _libraryId!;
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final coversToday = !today.isBefore(start) && !today.isAfter(end);
    final activeMembers = await HolidayService.instance.activeMembersCount(libId);
    final openNow = coversToday ? await HolidayService.instance.openSessionsNow(libId) : 0;
    if (!mounted) return false;

    final bool single =
        start.year == end.year && start.month == end.month && start.day == end.day;
    final dateLabel = single
        ? DateFormat('EEE, dd MMM yyyy').format(start)
        : '${DateFormat('dd MMM').format(start)} – ${DateFormat('dd MMM yyyy').format(end)}';

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFE65C00), size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Close the library?',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Closing for: $dateLabel',
                style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
            const SizedBox(height: 10),
            Text('$activeMembers active member${activeMembers == 1 ? '' : 's'} in this library.',
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569))),
            if (coversToday && openNow > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(
                  '$openNow member${openNow == 1 ? ' is' : 's are'} checked in right now. '
                  'Closing today will end ${openNow == 1 ? 'their session' : 'their sessions'} immediately.',
                  style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF991B1B), height: 1.35),
                ),
              ),
            ] else if (coversToday) ...[
              const SizedBox(height: 8),
              Text('No one is checked in right now.',
                  style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B))),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65C00),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(coversToday && openNow > 0 ? 'Close & end sessions' : 'Close library',
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildHolidayBanner(Holiday h) {
    final dateLabel = h.isRange
        ? '${DateFormat('dd MMM').format(h.startDate)} – ${DateFormat('dd MMM').format(h.endDate)}'
        : DateFormat('EEEE, dd MMM').format(h.startDate);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE65C00), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: const BoxDecoration(
              color: Color(0xFFE65C00),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.event_busy, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Today is a holiday',
                  style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF9A3412)),
                ),
                const SizedBox(height: 2),
                Text(
                  '$dateLabel · ${h.reason} · Check-in is disabled.',
                  style: GoogleFonts.inter(
                      fontSize: 11.5, color: const Color(0xFF9A3412)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ScheduledClosuresScreen(libraryId: _libraryId),
                ),
              ).then((_) {
                if (_libraryId != null) _loadLibrarySpecificData(_libraryId!);
              });
            },
            child: Text('Manage',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFE65C00))),
          ),
        ],
      ),
    );
  }

  Widget _buildCloseInfoRow(String emoji, String text) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF92400E),
            ),
          ),
        ),
      ],
    );
  }

  void _openQRModal(String qrType) {
    if (_libraryId == null) {
      _showErrorSnackBar('Please complete library details setup first.');
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return QRModal(
          libraryId: _libraryId!,
          libraryCode: _libraryCode,
          libraryName: _libraryName,
          initialQrVersion: _qrVersion,
          qrType: qrType,
          onQrVersionChanged: (newVersion) {
            setState(() {
              _qrVersion = newVersion;
            });
          },
        );
      },
    );
  }

  Widget _buildQRCodesRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'QR Codes',
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildQRCard(
                title: 'Joining QR',
                description: 'Scan to apply & register',
                icon: Icons.person_add_alt_1,
                onTap: () => _openQRModal('join'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQRCard(
                title: 'Attendance QR',
                description: 'Laminate & stick on wall',
                icon: Icons.qr_code_scanner,
                onTap: () => _openQRModal('attendance'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQRCard({
    required String title,
    required String description,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3ED),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFE65C00).withValues(alpha: 0.2),
                ),
              ),
              child: Icon(icon, color: const Color(0xFFE65C00), size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            Text(
              description,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 9,
                color: const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: OutlinedButton(
                      onPressed: onTap,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Text(
                        'PDF',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: OutlinedButton(
                      onPressed: onTap,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: BorderSide(
                          color: const Color(0xFFE65C00).withValues(alpha: 0.3),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Text(
                        'Share',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFE65C00),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _attendanceInitial(String? name) {
    final n = (name ?? '').trim();
    return Container(
      color: const Color(0xFFFFF3ED),
      alignment: Alignment.center,
      child: Text(
        n.isNotEmpty ? n[0].toUpperCase() : '?',
        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
      ),
    );
  }

  Widget _buildAttendanceStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Today's Attendance",
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            Text(
              'Present: $_activeMembers/$_totalMembers',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Horizontal Avatars scroll or Empty State
        _todayAttendance.isEmpty
            ? Container(
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.people_outline,
                        color: Colors.grey[400],
                        size: 36,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No attendance recorded today',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: SizedBox(
                height: 96,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _todayAttendance.length,
                  itemBuilder: (context, index) {
                    final student = _todayAttendance[index];
                    Color ringColor = const Color(0xFFE5E7EB);
                    bool hasOverlay = false;

                    if (student['status'] == 'in') {
                      ringColor = const Color(0xFF22C55E); // Green checked in
                    } else if (student['status'] == 'out') {
                      ringColor = const Color(0xFFEF4444); // Red checked out
                    } else if (student['status'] == 'expired') {
                      ringColor = const Color(0xFFEF4444);
                      hasOverlay = true; // Red overlay expired
                    }

                    return Container(
                      margin: const EdgeInsets.only(right: 16),
                      child: Column(
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: ringColor,
                                    width: 2.5,
                                  ),
                                ),
                                child: ClipOval(
                                  child: (() {
                                    final photo = (student['photo'] ?? '').toString();
                                    if (photo.isNotEmpty) {
                                      return Image.network(
                                        photo,
                                        width: 52,
                                        height: 52,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => _attendanceInitial(student['name']?.toString()),
                                      );
                                    }
                                    return _attendanceInitial(student['name']?.toString());
                                  })(),
                                ),
                              ),
                              if (hasOverlay)
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(
                                      0xFFEF4444,
                                    ).withValues(alpha: 0.4),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.block,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            student['name']?.toString() ?? 'Unknown',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1A1A2E),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Builder(builder: (_) {
                            final bool isIn = student['status'] == 'in';
                            final String time = (student['time'] ?? '').toString();
                            return Text(
                              time.isNotEmpty ? '${isIn ? 'In' : 'Out'} · $time' : (isIn ? 'In' : 'Out'),
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                color: isIn ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          }),
                        ],
                      ),
                    );
                  },
                ),
                ),
              ),
      ],
    );
  }

  Widget _buildRecentActivityFeed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Activities',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _currentTab = 1), // Go to Members
              child: Text(
                'View All →',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFE65C00),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: _recentActivities.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.history_toggle_off,
                          color: Colors.grey[400],
                          size: 36,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No recent activities recorded yet',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: _recentActivities.map((act) {
                    Color dotColor = const Color(0xFFE5E7EB);
                    if (act['type'] == 'in') dotColor = const Color(0xFF22C55E);
                    if (act['type'] == 'out') {
                      dotColor = const Color(0xFFEF4444);
                    }
                    if (act['type'] == 'req') {
                      dotColor = const Color(0xFF3B82F6);
                    }
                    if (act['type'] == 'pay') {
                      dotColor = const Color(0xFFF59E0B);
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: dotColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              act['desc'],
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF1A1A2E),
                              ),
                            ),
                          ),
                          Text(
                            act['time'],
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: const Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Future<void> _handleLogout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Logout Account',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to sign out from SILENCE?',
          style: GoogleFonts.inter(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Logout',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (confirm == true) {
      setState(() {});
      try {
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/auth', (route) => false);
        }
      } catch (e) {
        if (mounted) {
          _showErrorSnackBar('Sign out failed: $e');
        }
      } finally {
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabChildren = [
      _buildHomeTab(),
      ReservationsTab(
        key: ValueKey(
          'reservations_${_libraryId}_${_step3Complete}_$_step4Complete',
        ),
        libraryId: _libraryId,
        libraryName: _libraryName,
        libraryCover: _coverPhotoUrl,
        myLibraries: _myLibraries,
        initialSubTab: _reservationsInitialSubTab,
        onLibraryChanged: (libId) {
          setState(() {
            _libraryId = libId;
          });
          _loadLibrarySpecificData(libId);
        },
      ),
      AdminAnalyticsTab(
        libraryId: _libraryId,
        libraryName: _libraryName,
        myLibraries: _myLibraries,
        onLibraryChanged: (libId) {
          setState(() {
            _libraryId = libId;
          });
          _loadLibrarySpecificData(libId);
        },
      ),
      AdminProfileTab(
        libraryId: _libraryId,
        libraryName: _libraryName,
        coverPhotoUrl: _coverPhotoUrl,
        myLibraries: _myLibraries,
        onLibraryChanged: (libId) {
          setState(() {
            _libraryId = libId;
          });
          _loadLibrarySpecificData(libId);
        },
        onLibraryUpdated: () {
          _loadInitialData();
        },
        onLogout: _handleLogout,
        adminName: _getAdminName(),
        adminEmail:
            Supabase.instance.client.auth.currentUser?.email ??
            'admin@silence.com',
        adminPhone: _phoneController.text.isNotEmpty
            ? _phoneController.text
            : '+91 XXXXX XXXXX',
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFE65C00),
      body: SafeArea(
        top: false,
        child: Container(
          color: const Color(0xFFFBF5EE),
          child: IndexedStack(index: _currentTab, children: tabChildren),
        ),
      ),

      // STATE-OF-THE-ART BOTTOM NAVIGATION BAR (Matching Screenshots perfectly)
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (index) {
          setState(() {
            _currentTab = index;
            if (index != 1) {
              _reservationsInitialSubTab = 0;
            }
          });
          // Returning to the dashboard: refresh the action-required counts so an
          // approval/rejection done in the Reservations tab reflects immediately
          // (doesn't depend on realtime, which may not be enabled on the table).
          if (index == 0 && _libraryId != null) {
            _fetchRealStats(_libraryId!);
            _loadOperationalFeeds(_libraryId!);
          }
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFFE65C00),
        unselectedItemColor: const Color(0xFF94A3B8), // slate-400
        selectedLabelStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_outlined),
            activeIcon: Icon(Icons.grid_view),
            label: 'Reservations',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            activeIcon: Icon(Icons.bar_chart),
            label: 'Analytics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
