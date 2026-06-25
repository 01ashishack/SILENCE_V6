import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/calendar_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'reports/attendance_export_preview.dart';
import 'reports/revenue_report_preview.dart';
import 'reservations/member_detail_screen.dart';
import '../widgets/states/shimmer_box.dart';
import '../core/plan_service.dart';
import '../widgets/upgrade_sheet.dart';
import '../utils/time_utils.dart';
import '../widgets/charts/analytics_painters.dart';


class AdminAnalyticsTab extends StatefulWidget {
  final String? libraryId;
  final String libraryName;
  final List<dynamic> myLibraries;
  final Function(String libId) onLibraryChanged;

  const AdminAnalyticsTab({
    super.key,
    required this.libraryId,
    required this.libraryName,
    required this.myLibraries,
    required this.onLibraryChanged,
  });

  @override
  State<AdminAnalyticsTab> createState() => _AdminAnalyticsTabState();
}

class _AdminAnalyticsTabState extends State<AdminAnalyticsTab>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;

  bool _isLoading = false;
  bool _hasFetchedOnce = false; // gates the full-screen skeleton to the first load only
  bool _isProfileComplete = true;
  bool _noLibrary = false;

  // Active Library State
  String? _filterLibraryId;
  String _libraryAddress = 'Library Address';
  String? _libraryCoverUrl;

  // Dropdown data sources
  List<Map<String, dynamic>> _floors = [];
  List<Map<String, dynamic>> _shifts = [];

  // Tab-independent Floor & Shift filters
  String _revFloorId = 'all';
  String _revShiftId = 'all';

  String _attFloorId = 'all';
  String _attShiftId = 'all';

  String _spFloorId = 'all';
  String _spShiftId = 'all';

  // Tab-independent Date filters
  // Attendance: weekday pills or custom range
  DateTime _attDate = istNow();
  DateTimeRange? _attCustomRange;
  bool _isAttCustomSelected = false;

  // Revenue: preset pills or custom range
  String _revDateFilter = 'month';
  DateTimeRange? _revCustomRange;

  // Shifts & Plans: preset pills or custom range
  String _spDateFilter = 'month';
  DateTimeRange? _spCustomRange;

  // Calculated Metrics (Revenue Tab)
  double _totalRevenue = 0.0;
  double _revenueChangePct = 0.0;
  double _totalExpenses = 0.0;
  double _netProfit = 0.0;
  double _totalPendingDues = 0.0;
  double _expiredDues = 0.0;
  double _expiring7DaysDues = 0.0;

  int _expiringThisWeekCount = 0;
  double _expiringThisWeekRevenue = 0.0;
  int _expiringThisMonthCount = 0;
  double _expiringThisMonthRevenue = 0.0;

  List<Map<String, dynamic>> _recentConfirmedPayments = [];
  List<Map<String, dynamic>> _allExpenses = [];

  double _cashRevenue = 0.0;
  double _upiRevenue = 0.0;
  double _addonRevenue = 0.0;

  int _refundRequestsCount = 0; // open member-initiated refund requests (queries)

  List<double> _trendValues = [];
  List<String> _trendLabels = [];
  int? _hoverTrendIndex;

  List<double> _shiftCompareRevenue = [];
  List<String> _shiftCompareLabels = [];
  List<double> _planCompareRevenue = [];
  List<String> _planCompareLabels = [];

  // Local caching of raw results for subqueries
  List<Map<String, dynamic>> _rawPayments = [];
  List<Map<String, dynamic>> _rawExpenditures = [];
  List<Map<String, dynamic>> _rawMemberships = [];
  List<Map<String, dynamic>> _rawAttendance = [];
  List<Map<String, dynamic>> _rawSeats = [];
  List<Map<String, dynamic>> _rawTrendMemberships = [];

  // Attendance state
  String _attendanceTableToggle = 'date_wise';
  int _holdCount = 0;
  int _checkedInCount = 0;
  int _checkedOutCount = 0;
  int _absentCount = 0;
  int _holidaysThisMonth = 0;
  List<Map<String, dynamic>> _attendanceLogs = [];
  List<double> _leaderboardValues = [];
  List<String> _leaderboardLabels = [];
  List<Map<String, dynamic>> _leastActiveMembers = [];
  List<double> _attendanceTrendValues = [];
  List<String> _attendanceTrendLabels = [];
  List<double> _peakHoursValues = [];
  List<String> _peakHoursLabels = [];

  // Shifts & Plans state
  List<double> _shiftOccupancyValues = [];
  List<String> _shiftOccupancyLabels = [];
  List<double> _planDistValues = [];
  List<String> _planDistLabels = [];
  List<double> _revPerShiftValues = [];
  List<String> _revPerShiftLabels = [];
  List<List<double>> _popularityTrendValues = [];
  List<String> _popularityTrendMonths = [];

  @override
  bool get wantKeepAlive => true;

  Future<void> _checkOnboardingStatus() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        final userData = await _supabase.from('users').select().eq('id', user.id).maybeSingle();
        if (userData != null) {
          final String name = userData['full_name'] ?? '';
          final String phone = userData['phone'] ?? '';
          final String gender = userData['gender'] ?? '';
          final String dob = userData['date_of_birth'] ?? '';
          final String address = userData['address'] ?? '';
          final String photoUrl = userData['photo_url'] ?? '';

          final bool isComplete = name.isNotEmpty &&
              phone.isNotEmpty &&
              gender.isNotEmpty &&
              dob.isNotEmpty &&
              address.isNotEmpty &&
              photoUrl.isNotEmpty;
          
          if (mounted) {
            setState(() {
              _isProfileComplete = isComplete;
            });
          }
        }
        
        final libsRes = await _supabase.from('libraries').select('id').eq('owner_id', user.id);
        if (mounted) {
          setState(() {
            _noLibrary = libsRes.isEmpty;
          });
        }
      } catch (e) {
        debugPrint('Error in _checkOnboardingStatus: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    _filterLibraryId = widget.libraryId;
    _initCoverUrl();
    _checkOnboardingStatus().then((_) {
      _fetchCommonData().then((_) => _triggerActiveTabFetch());
    });
  }

  @override
  void didUpdateWidget(covariant AdminAnalyticsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.libraryId != widget.libraryId ||
        oldWidget.myLibraries != widget.myLibraries) {
      setState(() {
        _filterLibraryId = widget.libraryId;
        _initCoverUrl();
      });
      _checkOnboardingStatus().then((_) {
        _fetchCommonData().then((_) => _triggerActiveTabFetch());
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    setState(() {}); // Repaint header based on active tab
    _triggerActiveTabFetch();
  }

  void _initCoverUrl() {
    if (_filterLibraryId == null) return;
    final selectedLib = widget.myLibraries.cast<Map<String, dynamic>?>().firstWhere(
      (lib) => lib?['id']?.toString().toLowerCase() == _filterLibraryId?.toString().toLowerCase(),
      orElse: () => null as Map<String, dynamic>?,
    );
    if (selectedLib != null) {
      final String? coverUrl = selectedLib['cover_photo_url'];
      final List<dynamic> photos = selectedLib['photos'] ?? [];
      if (coverUrl != null && coverUrl.isNotEmpty) {
        _libraryCoverUrl = coverUrl;
      } else if (photos.isNotEmpty) {
        _libraryCoverUrl = photos.first.toString();
      } else {
        _libraryCoverUrl = null;
      }

      final String city = selectedLib['address_city'] ?? '';
      final String state = selectedLib['address_state'] ?? '';
      if (city.isNotEmpty && state.isNotEmpty) {
        _libraryAddress = '$city, $state';
      } else if (city.isNotEmpty) {
        _libraryAddress = city;
      } else if (state.isNotEmpty) {
        _libraryAddress = state;
      } else {
        _libraryAddress = 'Library Address';
      }
    }
  }

  List<DateTime> _getWeekdayDays() {
    final now = istNow();
    // Most-recent first: today, yesterday, ... (e.g. 19, 18, 17, 16, 15, 14, 13).
    // Keeps the default-selected day (today) visible at the left edge.
    return List.generate(7, (i) => DateTime(now.year, now.month, now.day - i));
  }

  DateTimeRange _getRangeForPreset(String filter, DateTimeRange? customRange) {
    final now = istNow();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    if (filter == 'custom' && customRange != null) {
      return customRange;
    }

    if (filter == 'today') {
      return DateTimeRange(start: todayStart, end: todayEnd);
    } else if (filter == 'week') {
      final weekday = now.weekday;
      final monday = now.subtract(Duration(days: weekday - 1));
      return DateTimeRange(
        start: DateTime(monday.year, monday.month, monday.day),
        end: todayEnd,
      );
    } else if (filter == 'month') {
      return DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: todayEnd,
      );
    }

    return DateTimeRange(start: todayStart, end: todayEnd);
  }

  // Dual Month bottom sheet custom picker
  Future<void> _openTabCustomRangePicker(String tab) async {
    final DateTimeRange? currentRange =
        tab == 'rev' ? _revCustomRange : (tab == 'sp' ? _spCustomRange : _attCustomRange);

    final DateTimeRange? pickedRange = await showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: DualMonthCalendarPicker(
                initialRange: currentRange ?? DateTimeRange(
                  start: DateTime.now(),
                  end: DateTime.now().add(const Duration(days: 7)),
                ),
                scrollController: scrollController,
              ),
            );
          },
        );
      },
    );
    if (!mounted) return;

    if (pickedRange != null) {
      setState(() {
        if (tab == 'rev') {
          _revDateFilter = 'custom';
          _revCustomRange = pickedRange;
        } else if (tab == 'sp') {
          _spDateFilter = 'custom';
          _spCustomRange = pickedRange;
        } else {
          _attCustomRange = pickedRange;
        }
      });
      _triggerActiveTabFetch();
    }
  }

  // Central trigger to dispatch fetch for current tab active parameters
  Future<void> _triggerActiveTabFetch({bool reprocessOnly = false}) async {
    final String activeFloorId = _getActiveFloorIdForTab();
    final String activeShiftId = _getActiveShiftIdForTab();

    dynamic dateFilter;
    if (_tabController.index == 1) {
      dateFilter = _attCustomRange ?? _attDate;
    } else if (_tabController.index == 0) {
      dateFilter = _getRangeForPreset(_revDateFilter, _revCustomRange);
    } else {
      dateFilter = _getRangeForPreset(_spDateFilter, _spCustomRange);
    }

    if (_filterLibraryId != null) {
      await _fetchAnalyticsData(
        libraryId: _filterLibraryId!,
        dateFilter: dateFilter,
        floorId: activeFloorId == 'all' ? null : activeFloorId,
        shiftId: activeShiftId == 'all' ? null : activeShiftId,
        reprocessOnly: reprocessOnly,
      );
    }
  }

  String _getActiveFloorIdForTab() {
    switch (_tabController.index) {
      case 0:
        return _revFloorId;
      case 1:
        return _attFloorId;
      case 2:
      default:
        return _spFloorId;
    }
  }

  String _getActiveShiftIdForTab() {
    switch (_tabController.index) {
      case 0:
        return _revShiftId;
      case 1:
        return _attShiftId;
      case 2:
      default:
        return _spShiftId;
    }
  }

  // Load floors and shifts commonly
  Future<void> _fetchCommonData() async {
    if (!_isProfileComplete || _noLibrary || _filterLibraryId == null) {
      if (mounted) {
        setState(() {
          _floors = [];
          _shifts = [];
        });
      }
      return;
    }
    try {
      final res = await Future.wait([
        _supabase.from('floors').select().eq('library_id', _filterLibraryId!).order('order_index'),
        _supabase.from('shifts').select().eq('library_id', _filterLibraryId!).eq('is_archived', false),
      ]);
      if (!mounted) return;
      setState(() {
        _floors = List<Map<String, dynamic>>.from(res[0]);
        _shifts = List<Map<String, dynamic>>.from(res[1]);
      });
    } catch (e) {
      debugPrint('Error fetching floors/shifts: $e');
    }

    // Holidays in the current month (range-aware: count each closed calendar
    // day that falls inside this month, de-duplicated).
    try {
      final now = istNow();
      final monthStart = DateTime(now.year, now.month, 1);
      final monthEnd = DateTime(now.year, now.month + 1, 0); // last day
      String fmt(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final rows = await _supabase
          .from('scheduled_closures')
          .select('start_date, end_date')
          .eq('library_id', _filterLibraryId!)
          .lte('start_date', fmt(monthEnd))
          .gte('end_date', fmt(monthStart));
      final days = <String>{};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final s = DateTime.tryParse((r['start_date'] ?? '').toString().split('T').first);
        final e = DateTime.tryParse((r['end_date'] ?? r['start_date'] ?? '').toString().split('T').first);
        if (s == null) continue;
        var d = s.isBefore(monthStart) ? monthStart : s;
        final last = (e ?? s).isAfter(monthEnd) ? monthEnd : (e ?? s);
        while (!d.isAfter(last)) {
          days.add(fmt(d));
          d = d.add(const Duration(days: 1));
        }
      }
      if (mounted) setState(() => _holidaysThisMonth = days.length);
    } catch (e) {
      debugPrint('Error fetching holiday count: $e');
    }
  }

  // Central fetch Scaffolding
  Future<void> _fetchAnalyticsData({
    required String libraryId,
    required dynamic dateFilter,
    required String? floorId,
    required String? shiftId,
    bool reprocessOnly = false,
  }) async {
    setState(() {
      // Stale-while-revalidate: only blank to the skeleton on the first load;
      // later fetches (sub-tab switch, filter/date change) keep the current
      // numbers visible and refresh quietly instead of flashing a skeleton.
      if (!_hasFetchedOnce) _isLoading = true;
    });

    try {
      // 1. Calculate date ranges
      DateTimeRange currentRange;
      if (dateFilter is DateTimeRange) {
        currentRange = dateFilter;
      } else {
        currentRange = DateTimeRange(
          start: DateTime(dateFilter.year, dateFilter.month, dateFilter.day),
          end: DateTime(dateFilter.year, dateFilter.month, dateFilter.day, 23, 59, 59),
        );
      }

      final duration = currentRange.end.difference(currentRange.start);
      final prevStart = currentRange.start.subtract(duration);
      final prevEnd = currentRange.start.subtract(const Duration(seconds: 1));

      final fetchStartIso = istWallClockToUtc(prevStart).toIso8601String();
      final fetchEndIso = istWallClockToUtc(currentRange.end).toIso8601String();

      // Construction of Attendance query date range
      DateTimeRange attRange;
      if (_attCustomRange != null) {
        attRange = _attCustomRange!;
      } else {
        attRange = DateTimeRange(
          start: DateTime(_attDate.year, _attDate.month, _attDate.day),
          end: DateTime(_attDate.year, _attDate.month, _attDate.day, 23, 59, 59),
        );
      }

      if (!_isProfileComplete || _noLibrary || libraryId.isEmpty || libraryId == 'null') {
        if (mounted) {
          setState(() {
            _rawPayments = [];
            _rawExpenditures = [];
            _rawMemberships = [];
            _rawAttendance = [];
            _rawSeats = [];
            _rawTrendMemberships = [];
            _holdCount = 0;
            _processRevenueData(currentRange, prevStart, prevEnd, floorId, shiftId);
            _processAttendanceData(floorId, shiftId);
            _processShiftsAndPlansData(floorId, shiftId);
            _isLoading = false;
            _hasFetchedOnce = true;
          });
        }
        return;
      }

      // Floor/Shift filtering is applied client-side inside the _process* methods,
      // so a filter change only needs a re-process of the already-fetched raw data
      // — no network round-trip. (Date changes still go through a full fetch.)
      if (reprocessOnly && _hasFetchedOnce) {
        if (!mounted) return;
        _processRevenueData(currentRange, prevStart, prevEnd, floorId, shiftId);
        _processAttendanceData(floorId, shiftId);
        _processShiftsAndPlansData(floorId, shiftId);
        setState(() => _isLoading = false);
        return;
      }

      // 2. Fetch parallel tables
      final results = await Future.wait([
        _supabase
            .from('payments')
            .select('*, memberships(*, seats(id, seat_label, floor_id), shifts(id, name)), member_id(id, full_name, phone, photo_url, email)')
            .eq('library_id', libraryId)
            .gte('payment_date', fetchStartIso)
            .lte('payment_date', fetchEndIso),
        _supabase
            .from('expenditures')
            .select()
            .eq('library_id', libraryId)
            .gte('expense_date', istWallClockToUtc(currentRange.start).toIso8601String())
            .lte('expense_date', istWallClockToUtc(currentRange.end).toIso8601String())
            .order('expense_date', ascending: false)
            .catchError((err) {
              debugPrint('expenditures select failed: $err');
              return [];
            }),
        _supabase
            .from('memberships')
            .select('*, member_id(id, full_name, phone, photo_url, email), seats(id, seat_label, floor_id), shifts(id, name, price_monthly, price_3month, price_6month)')
            .eq('library_id', libraryId),
        _supabase
            .from('attendance')
            .select('*, member_id(id, full_name, photo_url), memberships(*, seats(id, seat_label, floor_id), shifts(id, name))')
            .eq('library_id', libraryId)
            .gte('check_in_time', istWallClockToUtc(attRange.start).toIso8601String())
            .lte('check_in_time', istWallClockToUtc(attRange.end).toIso8601String())
            .order('check_in_time', ascending: false),
        _supabase
            .from('seats')
            .select()
            .eq('library_id', libraryId),
        _supabase
            .from('memberships')
            .select('created_at, plan_type, status')
            .eq('library_id', libraryId)
            .gte('created_at', DateTime.now().subtract(const Duration(days: 180)).toUtc().toIso8601String()),
      ]);

      if (!mounted) return;

      _rawPayments = List<Map<String, dynamic>>.from(results[0]);
      _rawExpenditures = List<Map<String, dynamic>>.from(results[1]);
      _rawMemberships = List<Map<String, dynamic>>.from(results[2]);
      _rawAttendance = List<Map<String, dynamic>>.from(results[3]);
      _rawSeats = List<Map<String, dynamic>>.from(results[4]);
      _rawTrendMemberships = List<Map<String, dynamic>>.from(results[5]);

      // Calculate hold member no-shows count inside the last 7 days
      int holdNoShowCount = 0;
      final holdMembers = _rawMemberships.where((m) => m['status'] == 'hold').toList();
      if (holdMembers.isNotEmpty) {
        final holdMemberIds = holdMembers.map((m) => m['member_id']?['id']).where((id) => id != null).toList();
        final recentCheckins = await _supabase
            .from('attendance')
            .select('member_id')
            .inFilter('member_id', holdMemberIds)
            .gte('check_in_time', DateTime.now().subtract(const Duration(days: 7)).toUtc().toIso8601String());
        final checkedInHoldIds = List<Map<String, dynamic>>.from(recentCheckins).map((r) => r['member_id']).toSet();
        holdNoShowCount = holdMembers.where((m) => !checkedInHoldIds.contains(m['member_id']?['id'])).length;
      }
      _holdCount = holdNoShowCount;

      // Pending refund requests (member-initiated on exit; type=refund_request,
      // still open). Honest count straight from the queries table.
      try {
        final refundRows = await _supabase
            .from('queries')
            .select('id')
            .eq('library_id', libraryId)
            .eq('type', 'refund_request')
            .eq('status', 'open');
        _refundRequestsCount = (refundRows as List).length;
      } catch (e) {
        debugPrint('refund requests count failed: $e');
      }

      // 3. Process data
      _processRevenueData(currentRange, prevStart, prevEnd, floorId, shiftId);
      _processAttendanceData(floorId, shiftId);
      _processShiftsAndPlansData(floorId, shiftId);

      setState(() {
        _isLoading = false;
        _hasFetchedOnce = true;
      });
    } catch (e) {
      debugPrint('Error fetching analytics data: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _processRevenueData(
    DateTimeRange currentRange,
    DateTime prevStart,
    DateTime prevEnd,
    String? floorId,
    String? shiftId,
  ) {
    double curRev = 0.0;
    double prevRev = 0.0;
    double cash = 0.0;
    double upi = 0.0;
    double addon = 0.0;

    final Map<String, double> shiftRevs = {};
    final Map<String, double> planRevs = {};
    final Map<String, double> dailyTrend = {};

    List<Map<String, dynamic>> recentPays = [];
    double pending = 0.0;
    double expiredPending = 0.0;
    double expiring7DaysPending = 0.0;

    final now = istNow();
    final today = DateTime(now.year, now.month, now.day);
    final in7Days = today.add(const Duration(days: 7));

    // Process Payments
    for (var p in _rawPayments) {
      final mShip = p['memberships'];
      if (mShip == null) continue;
      final seat = mShip['seats'];

      // Filter floor & shift in memory
      if (floorId != null && seat?['floor_id']?.toString() != floorId) continue;
      if (shiftId != null && mShip['shift_id']?.toString() != shiftId) continue;

      final double amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
      final String status = p['status'] ?? 'pending';
      final String method = (p['method'] ?? 'cash').toString().toLowerCase();

      final payDate = toIST(DateTime.parse(p['payment_date']));

      if (status == 'confirmed') {
        if (payDate.isAfter(currentRange.start.subtract(const Duration(seconds: 1))) &&
            payDate.isBefore(currentRange.end.add(const Duration(seconds: 1)))) {
          curRev += amt;
          recentPays.add(p);

          // Split methods
          if (method == 'cash') {
            cash += amt;
          } else if (method == 'upi') {
            upi += amt;
          } else {
            addon += amt;
          }

          // Group by shift
          final String sName = mShip['shifts']?['name'] ?? 'Unknown Shift';
          shiftRevs[sName] = (shiftRevs[sName] ?? 0) + amt;

          // Group by plan type
          final String rawPlan = mShip['plan_type'] ?? 'monthly';
          String planName = 'Monthly';
          if (rawPlan == '3_month') planName = '3-Month';
          if (rawPlan == '6_month') planName = '6-Month';
          planRevs[planName] = (planRevs[planName] ?? 0) + amt;

          // Group by date for trend
          final dateKey = DateFormat('dd MMM').format(payDate);
          dailyTrend[dateKey] = (dailyTrend[dateKey] ?? 0) + amt;
        } else if (payDate.isAfter(prevStart.subtract(const Duration(seconds: 1))) &&
            payDate.isBefore(prevEnd.add(const Duration(seconds: 1)))) {
          prevRev += amt;
        }
      } else if (status == 'pending') {
        pending += amt;
        final mStatus = mShip['status'] ?? 'pending';
        final String? endStr = mShip['end_date'];
        if (endStr != null) {
          final endDate = DateTime.parse(endStr);
          if (mStatus == 'expired' || endDate.isBefore(today)) {
            expiredPending += amt;
          } else if (endDate.isAfter(today.subtract(const Duration(seconds: 1))) &&
              endDate.isBefore(in7Days.add(const Duration(seconds: 1)))) {
            expiring7DaysPending += amt;
          }
        }
      }
    }

    recentPays.sort((a, b) => b['payment_date'].toString().compareTo(a['payment_date'].toString()));
    _recentConfirmedPayments = recentPays.take(5).toList();

    _totalRevenue = curRev;
    _revenueChangePct = prevRev == 0.0 ? 100.0 : ((curRev - prevRev) / prevRev) * 100.0;
    _cashRevenue = cash;
    _upiRevenue = upi;
    _addonRevenue = addon;
    _totalPendingDues = pending;
    _expiredDues = expiredPending;
    _expiring7DaysDues = expiring7DaysPending;

    // Process Expenses
    double curExp = 0.0;
    for (var exp in _rawExpenditures) {
      curExp += (exp['amount'] as num?)?.toDouble() ?? 0.0;
    }
    _totalExpenses = curExp;
    _netProfit = curRev - curExp;
    _allExpenses = _rawExpenditures;

    // Group comparisons
    _shiftCompareRevenue = shiftRevs.values.toList();
    _shiftCompareLabels = shiftRevs.keys.toList();
    _planCompareRevenue = planRevs.values.toList();
    _planCompareLabels = planRevs.keys.toList();

    // Map trends
    if (dailyTrend.isEmpty) {
      _trendValues = [0.0];
      _trendLabels = [DateFormat('dd MMM').format(currentRange.start)];
    } else {
      _trendValues = dailyTrend.values.toList();
      _trendLabels = dailyTrend.keys.toList();
    }

    // Process Renewal Forecast inside next 30 days
    int weekExp = 0;
    double weekRev = 0.0;
    int monthExp = 0;
    double monthRev = 0.0;

    final in30Days = today.add(const Duration(days: 30));

    for (var m in _rawMemberships) {
      final seat = m['seats'];
      if (floorId != null && seat?['floor_id']?.toString() != floorId) continue;
      if (shiftId != null && m['shift_id']?.toString() != shiftId) continue;

      final String? endStr = m['end_date'];
      if (endStr == null) continue;
      final endDate = DateTime.parse(endStr);

      final String plan = m['plan_type'] ?? 'monthly';
      final double monthlyPrice = (m['shifts']?['price_monthly'] as num?)?.toDouble() ?? 1500.0;
      double expectedPrice = monthlyPrice;
      if (plan == '3_month') expectedPrice = (m['shifts']?['price_3month'] as num?)?.toDouble() ?? (monthlyPrice * 3);
      if (plan == '6_month') expectedPrice = (m['shifts']?['price_6month'] as num?)?.toDouble() ?? (monthlyPrice * 6);

      if (endDate.isAfter(today.subtract(const Duration(seconds: 1))) &&
          endDate.isBefore(in7Days.add(const Duration(seconds: 1)))) {
        weekExp++;
        weekRev += expectedPrice;
      } else if (endDate.isAfter(in7Days) &&
          endDate.isBefore(in30Days.add(const Duration(seconds: 1)))) {
        monthExp++;
        monthRev += expectedPrice;
      }
    }

    _expiringThisWeekCount = weekExp;
    _expiringThisWeekRevenue = weekRev;
    _expiringThisMonthCount = monthExp;
    _expiringThisMonthRevenue = monthRev;
  }

  // Maps this screen's dropdown labels to the canonical lowercase expenditure
  // category keys enforced by the DB CHECK (the other entry path,
  // add_expense_bottom_sheet, already lowercases; these two aliases differ).
  static const Map<String, String> _expenseCategoryToKey = {
    'Electricity': 'electricity',
    'Rent': 'rent',
    'Water': 'water',
    'Salaries': 'salary',
    'Internet': 'internet',
    'Maintenance': 'maintenance',
    'Others': 'miscellaneous',
  };

  // Title-Case dropdown label -> canonical key (for writes).
  static String _expenseCategoryKey(String label) =>
      _expenseCategoryToKey[label] ?? label.toLowerCase();

  // Canonical key -> a friendly display label (for reads/display).
  static String _expenseCategoryLabel(String key) {
    final k = key.toLowerCase();
    switch (k) {
      case 'salary':
        return 'Salaries';
      case 'miscellaneous':
        return 'Others';
      default:
        return k.isEmpty ? 'Others' : k[0].toUpperCase() + k.substring(1);
    }
  }

  // Expenditures database actions
  Future<void> _addExpense(double amount, String category, String notes, DateTime date) async {
    if (_filterLibraryId == null) return;
    setState(() => _isLoading = true);
    try {
      await _supabase.from('expenditures').insert({
        'library_id': _filterLibraryId!,
        'amount': amount,
        'category': category,
        'notes': notes,
        'expense_date': date.toUtc().toIso8601String(),
        'added_by': _supabase.auth.currentUser?.id ?? 'admin',
      });
      _triggerActiveTabFetch();
    } catch (e) {
      debugPrint('Error adding expense: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add expense: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _editExpense(String expenseId, double amount, String category, String notes, DateTime date) async {
    setState(() => _isLoading = true);
    try {
      await _supabase.from('expenditures').update({
        'amount': amount,
        'category': category,
        'notes': notes,
        'expense_date': date.toUtc().toIso8601String(),
      }).eq('id', expenseId);
      _triggerActiveTabFetch();
    } catch (e) {
      debugPrint('Error editing expense: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to edit expense: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteExpense(String expenseId) async {
    if (!_isProfileComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Complete your profile first to manage expenses', style: GoogleFonts.inter()),
          backgroundColor: const Color(0xFFE65C00),
        ),
      );
      return;
    }
    if (_noLibrary || widget.libraryId == null || widget.libraryId!.isEmpty || widget.libraryId == 'null') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Set up your library first to manage expenses', style: GoogleFonts.inter()),
          backgroundColor: const Color(0xFFE65C00),
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _supabase.from('expenditures').delete().eq('id', expenseId);
      _triggerActiveTabFetch();
    } catch (e) {
      debugPrint('Error deleting expense: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete expense: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  void _showAddExpenseBottomSheet() async {
    if (!_isProfileComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Complete your profile first to manage expenses', style: GoogleFonts.inter()),
          backgroundColor: const Color(0xFFE65C00),
        ),
      );
      return;
    }
    if (!await ensurePlan(context, AdminFeature.expenditure,
        featureLabel: 'Expense tracking')) {
      return;
    }
    if (!mounted) return;
    if (_noLibrary || widget.libraryId == null || widget.libraryId!.isEmpty || widget.libraryId == 'null') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Set up your library first to manage expenses', style: GoogleFonts.inter()),
          backgroundColor: const Color(0xFFE65C00),
        ),
      );
      return;
    }
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    String selectedCategory = 'Electricity';
    DateTime selectedDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 24, left: 24, right: 24
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Add Expenditures',
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Amount (INR)', prefixText: '₹ '),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: const [
                        DropdownMenuItem(value: 'Electricity', child: Text('Electricity')),
                        DropdownMenuItem(value: 'Rent', child: Text('Rent')),
                        DropdownMenuItem(value: 'Water', child: Text('Water')),
                        DropdownMenuItem(value: 'Salaries', child: Text('Salaries')),
                        DropdownMenuItem(value: 'Internet', child: Text('Internet')),
                        DropdownMenuItem(value: 'Maintenance', child: Text('Maintenance')),
                        DropdownMenuItem(value: 'Others', child: Text('Others')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => selectedCategory = val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        final picked = await showCalendarGridBottomSheet(
                          context,
                          initialDate: selectedDate,
                          firstDate: DateTime(DateTime.now().year - 2),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setSheetState(() => selectedDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[400]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(DateFormat('dd MMMM yyyy').format(selectedDate)),
                            const Icon(Icons.calendar_today, size: 16, color: Color(0xFFE65C00)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(labelText: 'Notes / Remarks'),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65C00),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        final amt = double.tryParse(amountController.text) ?? 0.0;
                        if (amt > 0) {
                          _addExpense(amt, _expenseCategoryKey(selectedCategory), noteController.text.trim(), selectedDate);
                          Navigator.pop(ctx);
                        }
                      },
                      child: Text('Add Expense', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditExpenseBottomSheet(Map<String, dynamic> exp) {
    if (!_isProfileComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Complete your profile first to manage expenses', style: GoogleFonts.inter()),
          backgroundColor: const Color(0xFFE65C00),
        ),
      );
      return;
    }
    if (_noLibrary || widget.libraryId == null || widget.libraryId!.isEmpty || widget.libraryId == 'null') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Set up your library first to manage expenses', style: GoogleFonts.inter()),
          backgroundColor: const Color(0xFFE65C00),
        ),
      );
      return;
    }
    final amountController = TextEditingController(text: (exp['amount'] as num?)?.toDouble().toStringAsFixed(0));
    final noteController = TextEditingController(text: exp['notes'] ?? '');
    final List<String> categories = ['Electricity', 'Rent', 'Water', 'Salaries', 'Internet', 'Maintenance', 'Others'];
    // Stored value is a canonical lowercase key; map it back to a dropdown label.
    String selectedCategory = _expenseCategoryLabel((exp['category'] ?? '').toString());
    if (!categories.contains(selectedCategory)) {
      selectedCategory = 'Others';
    }
    DateTime selectedDate = DateTime.parse(exp['expense_date']).toLocal();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 24, left: 24, right: 24
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Edit Expenditure',
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Amount (INR)', prefixText: '₹ '),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: const [
                        DropdownMenuItem(value: 'Electricity', child: Text('Electricity')),
                        DropdownMenuItem(value: 'Rent', child: Text('Rent')),
                        DropdownMenuItem(value: 'Water', child: Text('Water')),
                        DropdownMenuItem(value: 'Salaries', child: Text('Salaries')),
                        DropdownMenuItem(value: 'Internet', child: Text('Internet')),
                        DropdownMenuItem(value: 'Maintenance', child: Text('Maintenance')),
                        DropdownMenuItem(value: 'Others', child: Text('Others')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => selectedCategory = val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        final picked = await showCalendarGridBottomSheet(
                          context,
                          initialDate: selectedDate,
                          firstDate: DateTime(DateTime.now().year - 2),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setSheetState(() => selectedDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[400]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(DateFormat('dd MMMM yyyy').format(selectedDate)),
                            const Icon(Icons.calendar_today, size: 16, color: Color(0xFFE65C00)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(labelText: 'Notes / Remarks'),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65C00),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        final amt = double.tryParse(amountController.text) ?? 0.0;
                        if (amt > 0) {
                          _editExpense(exp['id'].toString(), amt, _expenseCategoryKey(selectedCategory), noteController.text.trim(), selectedDate);
                          Navigator.pop(ctx);
                        }
                      },
                      child: Text('Save Changes', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showLibrarySwitcherPopup() {
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
                  ...widget.myLibraries.map((lib) {
                    final bool isSelected =
                        lib['id'].toString().toLowerCase() ==
                        (_filterLibraryId ?? '').toString().toLowerCase();
                    final String? city = lib['address_city'] ?? lib['city'];
                    final String? coverUrl = lib['cover_photo_url'];
                    final List<dynamic> photos = lib['photos'] ?? [];
                    String? itemCover;
                    if (coverUrl != null && coverUrl.isNotEmpty) {
                      itemCover = coverUrl;
                    } else if (photos.isNotEmpty) {
                      itemCover = photos.first.toString();
                    }

                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          _filterLibraryId = lib['id'];
                          _initCoverUrl();
                        });
                        widget.onLibraryChanged(lib['id']);
                        _fetchCommonData().then((_) => _triggerActiveTabFetch());
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
                                      child: CachedNetworkImage(
                                        imageUrl: itemCover,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 200,
                                        placeholder: (context, url) => const Center(
                                          child: CircularProgressIndicator(
                                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
                                            strokeWidth: 1.5,
                                          ),
                                        ),
                                        errorWidget: (context, url, error) => const Icon(
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
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/admin/library/setup/1',
                          arguments: 'new');
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
                            'Add Library',
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

  void _showFloorSwitcherPopup(BuildContext context, String currentFloorId, Function(String) onFloorSelected) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Floor Selector',
      barrierColor: Colors.black.withValues(alpha: 0.15),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: const Alignment(-0.5, -0.4),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 220,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
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
                  InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      onFloorSelected('all');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.layers_outlined, color: Color(0xFF64748B), size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'All Floors',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: currentFloorId == 'all' ? FontWeight.bold : FontWeight.normal,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          if (currentFloorId == 'all')
                            const Icon(Icons.check, color: Color(0xFFE65C00), size: 16),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  ..._floors.map((floor) {
                    final String floorId = floor['id'].toString();
                    final String floorName = floor['name'] ?? 'Floor';
                    final bool isSelected = floorId == currentFloorId;
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        onFloorSelected(floorId);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.layers_outlined, color: Color(0xFFE65C00), size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                floorName,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: const Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            if (isSelected)
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

  void _showShiftSwitcherPopup(BuildContext context, String currentShiftId, Function(String) onShiftSelected) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Shift Selector',
      barrierColor: Colors.black.withValues(alpha: 0.15),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: const Alignment(0.5, -0.4),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 220,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
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
                  InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      onShiftSelected('all');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.schedule_outlined, color: Color(0xFF64748B), size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'All Shifts',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: currentShiftId == 'all' ? FontWeight.bold : FontWeight.normal,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          if (currentShiftId == 'all')
                            const Icon(Icons.check, color: Color(0xFFE65C00), size: 16),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  ..._shifts.map((shift) {
                    final String shiftId = shift['id'].toString();
                    final String shiftName = shift['name'] ?? 'Shift';
                    final bool isSelected = shiftId == currentShiftId;
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        onShiftSelected(shiftId);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule_outlined, color: Color(0xFFE65C00), size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                shiftName,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: const Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            if (isSelected)
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

  // --- Rendering UI Helpers ---
  Widget _buildTopCurvedHeader() {
    final todayFormatted = DateFormat('EEE dd/MM').format(istNow()).toUpperCase();

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        bottom: 32,
        left: 16,
        right: 16,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFFF6B00),
            Color(0xFFE65C00),
          ],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Dynamic Library Switcher (Left Side) - matching Reservations Tab
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.0),
                    color: Colors.white,
                  ),
                  child: _libraryCoverUrl != null && _libraryCoverUrl!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(25),
                          child: CachedNetworkImage(
                            imageUrl: _libraryCoverUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 200,
                            placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
                                strokeWidth: 2,
                              ),
                            ),
                            errorWidget: (context, url, error) => const Icon(
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
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _showLibrarySwitcherPopup,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                widget.libraryName,
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
                              size: 18,
                            ),
                          ],
                        ),
                        Text(
                          _libraryAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.95),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Date Pill
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 12,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  todayFormatted,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabBar() {
    return Container(
      color: Colors.white,
      height: 48,
      child: TabBar(
        controller: _tabController,
        indicatorColor: const Color(0xFFE65C00),
        indicatorSize: TabBarIndicatorSize.label,
        indicatorWeight: 2.0,
        dividerColor: Colors.transparent,
        labelColor: const Color(0xFFE65C00),
        unselectedLabelColor: const Color(0xFF64748B),
        labelStyle: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold),
        unselectedLabelStyle: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: 'Revenue'),
          Tab(text: 'Attendance'),
          Tab(text: 'Shifts & Plans'),
        ],
      ),
    );
  }

  Widget _buildCustomPopupSelector({
    required String label,
    required String? selectedId,
    required List<dynamic> items,
    required bool isFloor,
    required ValueChanged<String> onChanged,
  }) {
    Map<String, dynamic>? selectedItem;
    for (final item in items) {
      if (item is Map<String, dynamic> &&
          item['id']?.toString() == selectedId) {
        selectedItem = item;
        break;
      }
    }
    final String selectedName = selectedId == 'all'
        ? (isFloor ? 'All Floors' : 'All Shifts')
        : (selectedItem != null ? (selectedItem['name'] ?? '') : 'Select ${isFloor ? 'Floor' : 'Shift'}');

    return GestureDetector(
      onTap: () => isFloor
          ? _showFloorSwitcherPopup(context, selectedId ?? 'all', onChanged)
          : _showShiftSwitcherPopup(context, selectedId ?? 'all', onChanged),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isFloor ? Icons.layers_rounded : Icons.access_time_rounded,
              color: const Color(0xFFE65C00),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    selectedName,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF64748B),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRowForTab({
    required String floorId,
    required String shiftId,
    required Function(String) onFloorSelected,
    required Function(String) onShiftSelected,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFFBF5EE),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Expanded(
            child: _buildCustomPopupSelector(
              label: 'FLOOR',
              selectedId: floorId,
              items: _floors,
              isFloor: true,
              onChanged: onFloorSelected,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildCustomPopupSelector(
              label: 'SHIFT',
              selectedId: shiftId,
              items: _shifts,
              isFloor: false,
              onChanged: onShiftSelected,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTraditionalDatePresets(String tab) {
    final activeFilter = tab == 'rev' ? _revDateFilter : _spDateFilter;
    final customRange = tab == 'rev' ? _revCustomRange : _spCustomRange;

    final presets = ['week', 'month'];
    final labels = {'today': 'Today', 'week': 'This Week', 'month': 'This Month'};

    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
      color: const Color(0xFFFBF5EE),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ...presets.map((p) {
              final isSelected = activeFilter == p;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (tab == 'rev') {
                      _revDateFilter = p;
                      _revCustomRange = null;
                    } else {
                      _spDateFilter = p;
                      _spCustomRange = null;
                    }
                  });
                  _triggerActiveTabFetch();
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFE65C00) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected
                        ? null
                        : Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Text(
                    labels[p]!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              );
            }),
            GestureDetector(
              onTap: () => _openTabCustomRangePicker(tab),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: activeFilter == 'custom' ? const Color(0xFFE65C00) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: activeFilter == 'custom'
                      ? null
                      : Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: activeFilter == 'custom' ? Colors.white : const Color(0xFF6B7280),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      activeFilter == 'custom' && customRange != null
                          ? '${DateFormat('dd MMM').format(customRange.start)} - ${DateFormat('dd MMM').format(customRange.end)}'
                          : 'Custom',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: activeFilter == 'custom' ? Colors.white : const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceDateFilters() {
    final pastDates = _getWeekdayDays();
    
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
      color: const Color(0xFFFBF5EE),
      child: Row(
        children: [
          Expanded(
            child: _isAttCustomSelected
                ? Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE65C00).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE65C00).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: Color(0xFFE65C00),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Custom: ${DateFormat('dd MMM yyyy').format(_attDate)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFE65C00),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isAttCustomSelected = false;
                              _attDate = istNow();
                              _attCustomRange = null;
                            });
                            _triggerActiveTabFetch();
                          },
                          child: const Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Color(0xFFE65C00),
                          ),
                        ),
                      ],
                    ),
                  )
                : SizedBox(
                    height: 38,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: pastDates.length,
                      itemBuilder: (context, index) {
                        final date = pastDates[index];
                        final isSelected = !_isAttCustomSelected && DateUtils.isSameDay(date, _attDate);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _attDate = date;
                              _isAttCustomSelected = false;
                              _attCustomRange = null;
                            });
                            _triggerActiveTabFetch();
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFE65C00) : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: isSelected
                                  ? null
                                  : Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  DateFormat('EEE').format(date).toUpperCase(),
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF6B7280),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('d').format(date),
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.white : const Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 38,
            child: OutlinedButton.icon(
              onPressed: () async {
                final picked = await showCalendarGridBottomSheet(
                  context,
                  initialDate: _attDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2101),
                );
                if (!mounted) return;
                if (picked != null) {
                  setState(() {
                    _attDate = picked;
                    _isAttCustomSelected = true;
                    _attCustomRange = null;
                  });
                  _triggerActiveTabFetch();
                }
              },
              icon: const Icon(Icons.calendar_month, size: 14, color: Color(0xFFE65C00)),
              label: Text(
                'Custom',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFE65C00),
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE65C00)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return Shimmer(
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Row(
            children: [
              Expanded(
                child: SkeletonBox(
                  height: 100,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SkeletonBox(
                  height: 100,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SkeletonBox(
            height: 120,
            borderRadius: BorderRadius.circular(16),
          ),
          const SizedBox(height: 16),
          SkeletonBox(
            height: 150,
            borderRadius: BorderRadius.circular(16),
          ),
          const SizedBox(height: 16),
          SkeletonBox(
            height: 200,
            borderRadius: BorderRadius.circular(16),
          ),
        ],
      ),
    );
  }


  // --- Card Construction Helpers ---
  Widget _buildHolidayCard() {
    final monthName = DateFormat('MMMM').format(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD1B3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: const BoxDecoration(
              color: Color(0xFFE65C00),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.event_busy, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _holidaysThisMonth == 1
                      ? '1 holiday in $monthName'
                      : '$_holidaysThisMonth holidays in $monthName',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF9A3412),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _holidaysThisMonth == 0
                      ? 'No closures scheduled this month.'
                      : 'Closed days don’t count against attendance.',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: const Color(0xFF9A3412),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    String? subtitle,
    Color? trendColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF7ED),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: const Color(0xFFE65C00), size: 18),
              ),
              const Spacer(),
              if (subtitle != null && trendColor != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: trendColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: trendColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
          ),
          // Non-trend subtitle (e.g. "Expenses: ₹X") sits under the title.
          if (subtitle != null && trendColor == null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- Revenue Subtab View Builder ---
  Widget _buildRevenueTabView() {
    final double changePct = _revenueChangePct;
    final String pctSign = changePct >= 0 ? '↑' : '↓';
    final Color pctColor = changePct >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. KPI Cards Row
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Total Revenue',
                value: '₹${_totalRevenue.toStringAsFixed(0)}',
                icon: Icons.payments,
                subtitle: '$pctSign ${changePct.abs().toStringAsFixed(1)}% vs prev',
                trendColor: pctColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'Net Profit',
                value: '₹${_netProfit.toStringAsFixed(0)}',
                icon: Icons.wallet,
                subtitle: 'Expenses: ₹${_totalExpenses.toStringAsFixed(0)}  ·  Refunds: $_refundRequestsCount',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 2. Pending Dues Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Pending Dues',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '₹${_totalPendingDues.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFDC2626),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFFF1F5F9)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Expired members (not left)',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                  ),
                  Text(
                    '₹${_expiredDues.toStringAsFixed(0)}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
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
                    'Expiring in 7 days',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                  ),
                  Text(
                    '₹${_expiring7DaysDues.toStringAsFixed(0)}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. Renewal Forecast Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Renewal Forecast – Next 30 days',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFE65C00), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_expiringThisWeekCount members expiring this week',
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1E293B)),
                        ),
                        Text(
                          'Expected renewal revenue: ₹${_expiringThisWeekRevenue.toStringAsFixed(0)}',
                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  )
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFE65C00), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_expiringThisMonthCount members expiring this month',
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1E293B)),
                        ),
                        Text(
                          'Expected renewal revenue: ₹${_expiringThisMonthRevenue.toStringAsFixed(0)}',
                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 4. Revenue Trend Line Chart
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Revenue Trend',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              if (_trendValues.isEmpty || _trendValues.every((v) => v == 0.0))
                Container(
                  height: 180,
                  alignment: Alignment.center,
                  child: Text('No Revenue Trend Data',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                )
              else
                GestureDetector(
                  onPanDown: (details) {
                    // Simple hit testing to find index
                    final double localX = details.localPosition.dx - 40;
                    final double chartWidth = MediaQuery.of(context).size.width - 32 - 32 - 80;
                    if (chartWidth > 0 && _trendValues.length > 1) {
                      final double step = chartWidth / (_trendValues.length - 1);
                      final int index = (localX / step).round().clamp(0, _trendValues.length - 1);
                      setState(() {
                        _hoverTrendIndex = index;
                      });
                    }
                  },
                  child: CustomPaint(
                    size: const Size(double.infinity, 180),
                    painter: LineChartPainter(
                      values: _trendValues,
                      labels: _trendLabels,
                      selectedIndex: _hoverTrendIndex,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 5. Payment Split Donut Chart
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Payment Method Split',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CustomPaint(
                      painter: DonutChartPainter(
                        values: [_cashRevenue, _upiRevenue, _addonRevenue],
                        labels: const ['Cash', 'UPI', 'Add-ons'],
                        colors: const [
                          Color(0xFFE65C00),
                          Color(0xFF0F172A),
                          Color(0xFF94A3B8),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildLegendItem('Cash', _cashRevenue, const Color(0xFFE65C00)),
                        const SizedBox(height: 8),
                        _buildLegendItem('UPI', _upiRevenue, const Color(0xFF0F172A)),
                        const SizedBox(height: 8),
                        _buildLegendItem('Add-ons', _addonRevenue, const Color(0xFF94A3B8)),
                      ],
                    ),
                  )
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 6. Recent Payments Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Recent Payments',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildPaymentTypePill('Cash', _cashRevenue),
                  _buildPaymentTypePill('UPI', _upiRevenue),
                  _buildPaymentTypePill('Add-ons', _addonRevenue),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFFF1F5F9)),
              const SizedBox(height: 6),
              if (_recentConfirmedPayments.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  alignment: Alignment.center,
                  child: Text('No Recent Confirmed Payments',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentConfirmedPayments.length,
                  itemBuilder: (ctx, index) {
                    final pay = _recentConfirmedPayments[index];
                    final member = pay['member_id'];
                    final name = member?['full_name'] ?? 'Member';
                    final photo = member?['photo_url'] ?? '';
                    final amt = pay['amount'] ?? 0;
                    final method = (pay['method'] ?? 'UPI').toString().toUpperCase();

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFFFFF7ED),
                            backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                            child: photo.isEmpty
                                ? const Icon(Icons.person, color: Color(0xFFE65C00), size: 16)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              name,
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1E293B)),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₹$amt',
                                style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFE65C00)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFFFF7ED),
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                  method,
                                  style: GoogleFonts.inter(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFFE65C00)),
                                ),
                              )
                            ],
                          )
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 7. Shifts vs Plans Chart Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Revenue Comparison (Shifts vs Plans)',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: CustomPaint(
                  painter: BarChartPainter(
                    shiftValues: _shiftCompareRevenue,
                    shiftLabels: _shiftCompareLabels,
                    planValues: _planCompareRevenue,
                    planLabels: _planCompareLabels,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 8. Expenditure Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Expenditures Breakdown',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (_isProfileComplete && !_noLibrary) ? const Color(0xFFE65C00) : const Color(0xFFE65C00).withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.add, size: 14, color: Colors.white),
                    label: Text(
                      'Add Expense',
                      style: GoogleFonts.inter(
                          fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    onPressed: _showAddExpenseBottomSheet,
                  )
                ],
              ),
              const SizedBox(height: 12),
              if (_allExpenses.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  alignment: Alignment.center,
                  child: Text('No expenditures logged',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _allExpenses.length,
                  itemBuilder: (ctx, index) {
                    final exp = _allExpenses[index];
                    final String id = exp['id'].toString();
                    final double amt = (exp['amount'] as num?)?.toDouble() ?? 0.0;
                    final String category = _expenseCategoryLabel((exp['category'] ?? '').toString());
                    final date = DateTime.parse(exp['expense_date']).toLocal();

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  category,
                                  style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1E293B)),
                                ),
                                Text(
                                  DateFormat('dd MMM yyyy').format(date),
                                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
                                )
                              ],
                            ),
                          ),
                          Text(
                            '- ₹${amt.toStringAsFixed(0)}',
                            style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFDC2626)),
                          ),
                          const SizedBox(width: 10),
                          Opacity(
                            opacity: (_isProfileComplete && !_noLibrary) ? 1.0 : 0.5,
                            child: GestureDetector(
                              onTap: () => _showEditExpenseBottomSheet(exp),
                              child: const Icon(Icons.edit_outlined,
                                  size: 18, color: Color(0xFF64748B)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Opacity(
                            opacity: (_isProfileComplete && !_noLibrary) ? 1.0 : 0.5,
                            child: GestureDetector(
                              onTap: () => _deleteExpense(id),
                              child: const Icon(Icons.delete_outline,
                                  size: 18, color: Color(0xFF64748B)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 9. Export & View Reports Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Export & View Reports',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 64 - 10) / 2,
                    child: _buildReportBtn('Revenue & Expenses', () => _openRevenuePreview(RevenueReportType.revenue)),
                  ),
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 64 - 10) / 2,
                    child: _buildReportBtn('Expense Report', () => _openRevenuePreview(RevenueReportType.expenses)),
                  ),
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 64 - 10) / 2,
                    child: _buildReportBtn('Payment History', () => _openRevenuePreview(RevenueReportType.payments)),
                  ),
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 64 - 10) / 2,
                    child: _buildReportBtn('Payment Details', () => _openRevenuePreview(RevenueReportType.payments)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, double value, Color color) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)))),
        Text('₹${value.toStringAsFixed(0)}',
            style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
      ],
    );
  }

  Widget _buildPaymentTypePill(String label, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: ₹${value.toStringAsFixed(0)}',
        style: GoogleFonts.inter(
            fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
      ),
    );
  }


  void _processAttendanceData(String? floorId, String? shiftId) {
    final List<Map<String, dynamic>> filteredAtt = [];
    final Map<String, double> memberStudyHours = {};
    final Map<String, Map<String, dynamic>> memberDetails = {};
    final Map<String, int> dailyCheckins = {};
    final List<int> hourlyCheckins = List.filled(15, 0);

    int checkedIn = 0;
    int checkedOut = 0;

    for (var att in _rawAttendance) {
      final mShip = att['memberships'];
      final seat = mShip?['seats'];

      if (floorId != null && seat?['floor_id']?.toString() != floorId) continue;
      if (shiftId != null && att['shift_id']?.toString() != shiftId) continue;

      filteredAtt.add(att);

      final String? ciStr = att['check_in_time'];
      final String? coStr = att['check_out_time'];
      if (ciStr == null) continue;

      final checkIn = toIST(DateTime.parse(ciStr));
      final checkOut = coStr != null ? toIST(DateTime.parse(coStr)) : null;

      if (checkOut == null) {
        checkedIn++;
      } else {
        checkedOut++;
      }

      final double durationHrs = checkOut != null
          ? checkOut.difference(checkIn).inMinutes / 60.0
          : DateTime.now().difference(checkIn).inMinutes / 60.0;

      final member = att['member_id'];
      if (member != null) {
        final String mId = member['id'].toString();
        memberStudyHours[mId] = (memberStudyHours[mId] ?? 0.0) + durationHrs;
        memberDetails[mId] = member;
      }

      final dayKey = DateFormat('dd MMM').format(checkIn);
      dailyCheckins[dayKey] = (dailyCheckins[dayKey] ?? 0) + 1;

      final hour = checkIn.hour;
      if (hour >= 8 && hour <= 22) {
        hourlyCheckins[hour - 8]++;
      }
    }

    _attendanceLogs = filteredAtt;
    _checkedInCount = checkedIn;
    _checkedOutCount = checkedOut;

    final activeMemberships = _rawMemberships.where((m) {
      final seat = m['seats'];
      if (floorId != null && seat?['floor_id']?.toString() != floorId) return false;
      if (shiftId != null && m['shift_id']?.toString() != shiftId) return false;
      return m['status'] == 'active';
    }).toList();

    _absentCount = (activeMemberships.length - checkedIn).clamp(0, 99999);

    final sortedMemberHours = memberStudyHours.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    _leaderboardValues = sortedMemberHours.take(10).map((e) => e.value).toList();
    _leaderboardLabels = sortedMemberHours.take(10).map<String>((e) {
      final details = memberDetails[e.key];
      return (details?['full_name'] ?? 'Member').toString();
    }).toList();

    final Map<String, double> allActiveStudyHours = {};
    for (var m in activeMemberships) {
      final member = m['member_id'];
      if (member != null) {
        final String mId = member['id'].toString();
        allActiveStudyHours[mId] = memberStudyHours[mId] ?? 0.0;
        memberDetails[mId] = member;
      }
    }

    final sortedAllActiveHours = allActiveStudyHours.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    _leastActiveMembers = sortedAllActiveHours.take(5).map((e) {
      final details = memberDetails[e.key];
      return {
        'id': e.key,
        'name': details?['full_name'] ?? 'Member',
        'phone': details?['phone'] ?? '',
        'hours': e.value,
      };
    }).toList();

    if (dailyCheckins.isEmpty) {
      _attendanceTrendValues = [0.0];
      _attendanceTrendLabels = ['Today'];
    } else {
      _attendanceTrendValues = dailyCheckins.values.map((v) => v.toDouble()).toList();
      _attendanceTrendLabels = dailyCheckins.keys.toList();
    }

    _peakHoursValues = hourlyCheckins.map((v) => v.toDouble()).toList();
    _peakHoursLabels = List.generate(15, (i) {
      final h = i + 8;
      final ampm = h >= 12 ? 'PM' : 'AM';
      final displayHour = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      return '$displayHour$ampm';
    });
  }

  void _processShiftsAndPlansData(String? floorId, String? shiftId) {
    final int totalSeatsCount = _rawSeats.where((s) => floorId == null || s['floor_id']?.toString() == floorId).length;

    final Map<String, int> activeMembershipsPerShift = {};
    for (var m in _rawMemberships) {
      if (m['status'] != 'active') continue;
      final seat = m['seats'];
      if (floorId != null && seat?['floor_id']?.toString() != floorId) continue;

      final String sName = m['shifts']?['name'] ?? 'Unknown Shift';
      activeMembershipsPerShift[sName] = (activeMembershipsPerShift[sName] ?? 0) + 1;
    }

    _shiftOccupancyLabels = _shifts.map((s) => s['name']?.toString() ?? 'Shift').toList();
    _shiftOccupancyValues = _shifts.map((s) {
      final name = s['name']?.toString() ?? 'Shift';
      final activeCount = activeMembershipsPerShift[name] ?? 0;
      final double totalSeats = totalSeatsCount == 0 ? 30.0 : totalSeatsCount.toDouble();
      return (activeCount / totalSeats * 100.0).clamp(0.0, 100.0);
    }).toList();

    final Map<String, int> planCounts = {};
    for (var m in _rawMemberships) {
      if (m['status'] != 'active') continue;
      final seat = m['seats'];
      if (floorId != null && seat?['floor_id']?.toString() != floorId) continue;
      if (shiftId != null && m['shift_id']?.toString() != shiftId) continue;

      final String rawPlan = m['plan_type'] ?? 'monthly';
      String planName = 'Monthly';
      if (rawPlan == '3_month') planName = '3-Month';
      if (rawPlan == '6_month') planName = '6-Month';

      planCounts[planName] = (planCounts[planName] ?? 0) + 1;
    }

    _planDistLabels = planCounts.keys.toList();
    _planDistValues = planCounts.values.map((v) => v.toDouble()).toList();

    final Map<String, double> shiftRevenue = {};
    for (var p in _rawPayments) {
      if (p['status'] != 'confirmed') continue;
      final mShip = p['memberships'];
      if (mShip == null) continue;
      final seat = mShip['seats'];
      if (floorId != null && seat?['floor_id']?.toString() != floorId) continue;
      if (shiftId != null && mShip['shift_id']?.toString() != shiftId) continue;

      final String sName = mShip['shifts']?['name'] ?? 'Unknown Shift';
      final double amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
      shiftRevenue[sName] = (shiftRevenue[sName] ?? 0.0) + amt;
    }

    _revPerShiftLabels = _shifts.map((s) => s['name']?.toString() ?? 'Shift').toList();
    _revPerShiftValues = _shifts.map((s) {
      final name = s['name']?.toString() ?? 'Shift';
      return shiftRevenue[name] ?? 0.0;
    }).toList();

    final Map<String, List<int>> monthlyPlanCounts = {
      'monthly': List.filled(6, 0),
      '3_month': List.filled(6, 0),
      '6_month': List.filled(6, 0),
    };

    final List<String> months = [];
    final now = DateTime.now();
    for (int i = 5; i >= 0; i--) {
      final mDate = DateTime(now.year, now.month - i, 1);
      months.add(DateFormat('MMM').format(mDate));
    }
    _popularityTrendMonths = months;

    for (var m in _rawTrendMemberships) {
      final String? ciStr = m['created_at'];
      if (ciStr == null) continue;
      final cDate = DateTime.parse(ciStr).toLocal();

      final int diffMonths = (now.year - cDate.year) * 12 + (now.month - cDate.month);
      if (diffMonths >= 0 && diffMonths < 6) {
        final int index = 5 - diffMonths;
        final String rawPlan = m['plan_type'] ?? 'monthly';
        if (monthlyPlanCounts.containsKey(rawPlan)) {
          monthlyPlanCounts[rawPlan]![index]++;
        }
      }
    }

    _popularityTrendValues = [
      monthlyPlanCounts['monthly']!.map((v) => v.toDouble()).toList(),
      monthlyPlanCounts['3_month']!.map((v) => v.toDouble()).toList(),
      monthlyPlanCounts['6_month']!.map((v) => v.toDouble()).toList(),
    ];
  }

  Future<void> _openRevenuePreview(RevenueReportType type) async {
    if (!_isProfileComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Complete your profile first to view/export reports', style: GoogleFonts.inter()),
          backgroundColor: const Color(0xFFE65C00),
        ),
      );
      return;
    }
    if (_noLibrary || widget.libraryId == null || widget.libraryId!.isEmpty || widget.libraryId == 'null') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Set up your library first to view/export reports', style: GoogleFonts.inter()),
          backgroundColor: const Color(0xFFE65C00),
        ),
      );
      return;
    }
    if (!await ensurePlan(context, AdminFeature.export, featureLabel: 'Exporting reports')) {
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RevenueReportPreviewScreen(
          libraryId: widget.libraryId!,
          libraryName: widget.libraryName,
          libraryAddress: _libraryAddress,
          type: type,
        ),
      ),
    );
  }

  Future<void> _openAttendancePreview() async {
    if (!_isProfileComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Complete your profile first to view/export reports', style: GoogleFonts.inter()),
          backgroundColor: const Color(0xFFE65C00),
        ),
      );
      return;
    }
    if (_noLibrary || widget.libraryId == null || widget.libraryId!.isEmpty || widget.libraryId == 'null') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Set up your library first to view/export reports', style: GoogleFonts.inter()),
          backgroundColor: const Color(0xFFE65C00),
        ),
      );
      return;
    }
    if (!await ensurePlan(context, AdminFeature.export, featureLabel: 'Exporting reports')) {
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AttendanceExportPreviewScreen(
          libraryId: widget.libraryId!,
          libraryName: widget.libraryName,
          libraryAddress: _libraryAddress,
          mode: _attendanceTableToggle == 'date_wise'
              ? AttendanceExportMode.dateWise
              : AttendanceExportMode.memberWise,
        ),
      ),
    );
  }

  Widget _buildAttendanceTabView() {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 380;
    final activeMemberships = _rawMemberships.where((m) {
      final seat = m['seats'];
      if (_attFloorId != 'all' && seat?['floor_id']?.toString() != _attFloorId) return false;
      if (_attShiftId != 'all' && m['shift_id']?.toString() != _attShiftId) return false;
      return m['status'] == 'active';
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Two intrinsic-height rows (instead of a fixed-aspect grid) so the
        // taller KPI cards can never overflow on small screens.
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Checked In',
                value: '$_checkedInCount / ${activeMemberships.length}',
                icon: Icons.login,
                subtitle: 'Active Members present',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'Checked Out',
                value: '$_checkedOutCount / ${_attendanceLogs.length}',
                icon: Icons.logout,
                subtitle: 'Completed sessions',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Absent',
                value: '$_absentCount',
                icon: Icons.person_off,
                subtitle: 'No check-in logged',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'Hold Members',
                value: '$_holdCount',
                icon: Icons.pause_circle_outline,
                subtitle: 'On hold & no-show >7 days',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildHolidayCard(),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Attendance Logs',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              if (_attendanceLogs.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  alignment: Alignment.center,
                  child: Text('No attendance logged for this period',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _attendanceLogs.length.clamp(0, 10),
                  itemBuilder: (ctx, index) {
                    final log = _attendanceLogs[index];
                    final member = log['member_id'];
                    final name = member?['full_name'] ?? 'Member';
                    final photo = member?['photo_url'] ?? '';
                    final seatLabel = log['memberships']?['seats']?['seat_label'] ?? 'N/A';
                    final shiftName = log['memberships']?['shifts']?['name'] ?? 'N/A';
                    final ciStr = log['check_in_time'];
                    final coStr = log['check_out_time'];

                    final ci = ciStr != null ? DateFormat('hh:mm a').format(DateTime.parse(ciStr).toLocal()) : 'N/A';
                    final co = coStr != null ? DateFormat('hh:mm a').format(DateTime.parse(coStr).toLocal()) : 'Ongoing';

                    return InkWell(
                      onTap: () {
                        if (member?['id'] != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MemberDetailScreen(),
                              settings: RouteSettings(arguments: member['id'].toString()),
                            ),
                          );
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFFFFF7ED),
                              backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                              child: photo.isEmpty
                                  ? const Icon(Icons.person, color: Color(0xFFE65C00), size: 18)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF1E293B)),
                                  ),
                                  Text(
                                    'Seat: $seatLabel • Shift: $shiftName',
                                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'IN: $ci',
                                  style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF16A34A)),
                                ),
                                Text(
                                  'OUT: $co',
                                  style: GoogleFonts.inter(
                                      fontSize: 10,
                                      color: coStr != null ? const Color(0xFF64748B) : const Color(0xFFE65C00),
                                      fontWeight: coStr != null ? FontWeight.normal : FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Top Members (Study Hours)',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              if (_leaderboardValues.isEmpty)
                Container(
                  height: 180,
                  alignment: Alignment.center,
                  child: Text('No Leaderboard Data',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                )
              else
                SizedBox(
                  height: 200,
                  child: CustomPaint(
                    painter: AttendanceLeaderboardPainter(
                      values: _leaderboardValues,
                      labels: _leaderboardLabels,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Least Active Members',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              if (_leastActiveMembers.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  alignment: Alignment.center,
                  child: Text('No active members logged',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _leastActiveMembers.length,
                  itemBuilder: (ctx, index) {
                    final item = _leastActiveMembers[index];
                    final String name = item['name'] ?? 'Member';
                    final String phone = item['phone'] ?? '';
                    final double hrs = item['hours'] ?? 0.0;

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1E293B)),
                                ),
                                Text(
                                  'Study Hours: ${hrs.toStringAsFixed(1)}h',
                                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.phone_outlined, size: 20, color: Color(0xFF1E293B)),
                                onPressed: () async {
                                  if (phone.isNotEmpty) {
                                    final uri = Uri.parse('tel:$phone');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri);
                                    }
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.chat_bubble_outline, size: 20, color: Color(0xFF16A34A)),
                                onPressed: () async {
                                  if (phone.isNotEmpty) {
                                    final formattedPhone = phone.replaceAll(RegExp(r'\D'), '');
                                    final uri = Uri.parse('https://wa.me/$formattedPhone');
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                height: 240,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Attendance Trend',
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _attendanceTrendValues.isEmpty
                          ? Center(child: Text('No Data', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)))
                          : CustomPaint(
                              painter: AttendanceTrendPainter(
                                values: _attendanceTrendValues,
                                labels: _attendanceTrendLabels,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                height: 240,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Peak Hours (8 AM - 10 PM)',
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _peakHoursValues.isEmpty
                          ? Center(child: Text('No Data', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)))
                          : CustomPaint(
                              painter: PeakHoursPainter(
                                values: _peakHoursValues,
                                labels: _peakHoursLabels,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    'Export Attendance Logs',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildToggleBtn('Date-wise', _attendanceTableToggle == 'date_wise', () {
                        setState(() => _attendanceTableToggle = 'date_wise');
                      }),
                      const SizedBox(width: 6),
                      _buildToggleBtn('Member-wise', _attendanceTableToggle == 'member_wise', () {
                        setState(() => _attendanceTableToggle = 'member_wise');
                      }),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _attendanceTableToggle == 'date_wise'
                    ? "Pick a day or range, preview every member's attendance, then export."
                    : 'Pick a month and one/more/all members, preview, then export.',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), height: 1.35),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openAttendancePreview,
                  icon: const Icon(Icons.visibility_outlined, size: 18, color: Colors.white),
                  label: Text('Preview & Export',
                      style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShiftsPlansTabView() {
    final int activeMembersCount = _rawMemberships.where((m) {
      final seat = m['seats'];
      if (_spFloorId != 'all' && seat?['floor_id']?.toString() != _spFloorId) return false;
      if (_spShiftId != 'all' && m['shift_id']?.toString() != _spShiftId) return false;
      return m['status'] == 'active';
    }).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Shift Occupancy Overview',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              if (_shiftOccupancyValues.isEmpty)
                Container(
                  height: 120,
                  alignment: Alignment.center,
                  child: Text('No Shift Occupancy Data',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                )
              else
                SizedBox(
                  height: 150,
                  child: CustomPaint(
                    painter: ShiftOccupancyPainter(
                      values: _shiftOccupancyValues,
                      labels: _shiftOccupancyLabels,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Plans Distribution',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              if (_planDistValues.isEmpty || _planDistValues.every((v) => v == 0.0))
                Container(
                  height: 150,
                  alignment: Alignment.center,
                  child: Text('No Plans Distribution Data',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                )
              else
                Row(
                  children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: CustomPaint(
                        painter: PlansDistributionPainter(
                          values: _planDistValues,
                          labels: _planDistLabels,
                          colors: const [
                            Color(0xFFE65C00),
                            Color(0xFF0F172A),
                            Color(0xFF94A3B8),
                          ],
                          totalCount: activeMembersCount,
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: List.generate(_planDistLabels.length, (index) {
                          final label = _planDistLabels[index];
                          final val = _planDistValues[index];
                          final colors = [
                            const Color(0xFFE65C00),
                            const Color(0xFF0F172A),
                            const Color(0xFF94A3B8),
                          ];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(color: colors[index % colors.length], shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)))),
                                Text('${val.toStringAsFixed(0)} members',
                                    style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Revenue per Shift',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              if (_revPerShiftValues.isEmpty || _revPerShiftValues.every((v) => v == 0.0))
                Container(
                  height: 160,
                  alignment: Alignment.center,
                  child: Text('No Revenue per Shift Data',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                )
              else
                SizedBox(
                  height: 200,
                  child: CustomPaint(
                    painter: RevenuePerShiftPainter(
                      values: _revPerShiftValues,
                      labels: _revPerShiftLabels,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Popularity of Plans over Time',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              if (_popularityTrendValues.isEmpty || _popularityTrendValues.first.isEmpty)
                Container(
                  height: 160,
                  alignment: Alignment.center,
                  child: Text('No Popularity Trend Data',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                )
              else
                Column(
                  children: [
                    SizedBox(
                      height: 180,
                      child: CustomPaint(
                        painter: PopularityOfPlansPainter(
                          valuesList: _popularityTrendValues,
                          labels: _popularityTrendMonths,
                          colors: const [
                            Color(0xFFE65C00),
                            Color(0xFF0F172A),
                            Color(0xFF94A3B8),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLegendColorDot(const Color(0xFFE65C00), 'Monthly'),
                        const SizedBox(width: 16),
                        _buildLegendColorDot(const Color(0xFF0F172A), '3-Month'),
                        const SizedBox(width: 16),
                        _buildLegendColorDot(const Color(0xFF94A3B8), '6-Month'),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendColorDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B))),
      ],
    );
  }

  Widget _buildReportBtn(String title, VoidCallback onTap) {
    final bool isEnabled = _isProfileComplete && !_noLibrary;
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.5,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFE65C00),
          side: const BorderSide(color: Color(0xFFE65C00), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        ),
        onPressed: isEnabled ? onTap : () {
          final String msg = !_isProfileComplete
              ? 'Complete your profile first to view/export reports'
              : 'Set up your library first to view/export reports';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg, style: GoogleFonts.inter()),
              backgroundColor: const Color(0xFFE65C00),
            ),
          );
        },
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildToggleBtn(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE65C00) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? const Color(0xFFE65C00) : const Color(0xFFE2E8F0),
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFFE65C00).withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);



    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFFBF5EE),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopCurvedHeader(),
            _buildSubTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Revenue Tab View
                  Column(
                    children: [
                      _buildFilterRowForTab(
                        floorId: _revFloorId,
                        shiftId: _revShiftId,
                        onFloorSelected: (val) {
                          setState(() => _revFloorId = val);
                          _triggerActiveTabFetch(reprocessOnly: true);
                        },
                        onShiftSelected: (val) {
                          setState(() => _revShiftId = val);
                          _triggerActiveTabFetch(reprocessOnly: true);
                        },
                      ),
                      _buildTraditionalDatePresets('rev'),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _triggerActiveTabFetch,
                          color: const Color(0xFFE65C00),
                          child: _isLoading
                              ? _buildSkeletonLoader()
                              : _buildRevenueTabView(),
                        ),
                      ),
                    ],
                  ),
                  // Attendance Tab View
                  Column(
                    children: [
                      _buildFilterRowForTab(
                        floorId: _attFloorId,
                        shiftId: _attShiftId,
                        onFloorSelected: (val) {
                          setState(() => _attFloorId = val);
                          _triggerActiveTabFetch(reprocessOnly: true);
                        },
                        onShiftSelected: (val) {
                          setState(() => _attShiftId = val);
                          _triggerActiveTabFetch(reprocessOnly: true);
                        },
                      ),
                      _buildAttendanceDateFilters(),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _triggerActiveTabFetch,
                          color: const Color(0xFFE65C00),
                          child: _isLoading
                              ? _buildSkeletonLoader()
                              : _buildAttendanceTabView(),
                        ),
                      ),
                    ],
                  ),
                  // Shifts & Plans Tab View
                  Column(
                    children: [
                      _buildFilterRowForTab(
                        floorId: _spFloorId,
                        shiftId: _spShiftId,
                        onFloorSelected: (val) {
                          setState(() => _spFloorId = val);
                          _triggerActiveTabFetch(reprocessOnly: true);
                        },
                        onShiftSelected: (val) {
                          setState(() => _spShiftId = val);
                          _triggerActiveTabFetch(reprocessOnly: true);
                        },
                      ),
                      _buildTraditionalDatePresets('sp'),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _triggerActiveTabFetch,
                          color: const Color(0xFFE65C00),
                          child: _isLoading
                              ? _buildSkeletonLoader()
                              : _buildShiftsPlansTabView(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom animated skeleton widget
class SkeletonWidget extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonWidget({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<SkeletonWidget> createState() => _SkeletonWidgetState();
}

class _SkeletonWidgetState extends State<SkeletonWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(
              const Color(0xFFE2E8F0),
              const Color(0xFFF1F5F9),
              _controller.value,
            ),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}

// Custom Dual Month Calendar Picker used in date range filtering
class DualMonthCalendarPicker extends StatefulWidget {
  final DateTimeRange initialRange;
  final ScrollController scrollController;

  const DualMonthCalendarPicker({
    super.key,
    required this.initialRange,
    required this.scrollController,
  });

  @override
  State<DualMonthCalendarPicker> createState() => _DualMonthCalendarPickerState();
}

class _DualMonthCalendarPickerState extends State<DualMonthCalendarPicker> {
  late DateTime _monthPivot;
  DateTime? _selectedStart;
  DateTime? _selectedEnd;

  @override
  void initState() {
    super.initState();
    _selectedStart = widget.initialRange.start;
    _selectedEnd = widget.initialRange.end;
    _monthPivot = DateTime(DateTime.now().year, DateTime.now().month, 1);
  }

  int _daysInMonth(DateTime date) {
    return DateTime(date.year, date.month + 1, 0).day;
  }

  Widget _buildMonthGrid(DateTime month) {
    final daysCount = _daysInMonth(month);
    final firstWeekday = month.weekday % 7;
    final totalCells = daysCount + firstWeekday;
    final weekdays = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            DateFormat('MMMM yyyy').format(month),
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: weekdays.map((day) {
            return SizedBox(
              width: 32,
              child: Text(
                day,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF6B7280),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1.0,
          ),
          itemCount: totalCells,
          itemBuilder: (context, index) {
            if (index < firstWeekday) {
              return const SizedBox.shrink();
            }

            final dayNum = index - firstWeekday + 1;
            final cellDate = DateTime(month.year, month.month, dayNum);

            final isStart = _selectedStart != null &&
                cellDate.day == _selectedStart!.day &&
                cellDate.month == _selectedStart!.month &&
                cellDate.year == _selectedStart!.year;

            final isEnd = _selectedEnd != null &&
                cellDate.day == _selectedEnd!.day &&
                cellDate.month == _selectedEnd!.month &&
                cellDate.year == _selectedEnd!.year;

            final isInRange = _selectedStart != null &&
                _selectedEnd != null &&
                cellDate.isAfter(_selectedStart!) &&
                cellDate.isBefore(_selectedEnd!);

            final isToday = cellDate.day == DateTime.now().day &&
                cellDate.month == DateTime.now().month &&
                cellDate.year == DateTime.now().year;

            return GestureDetector(
              onTap: () {
                setState(() {
                  if (_selectedStart == null) {
                    _selectedStart = cellDate;
                  } else if (_selectedStart != null && _selectedEnd == null) {
                    if (cellDate.isBefore(_selectedStart!)) {
                      _selectedStart = cellDate;
                    } else {
                      _selectedEnd = cellDate;
                    }
                  } else {
                    _selectedStart = cellDate;
                    _selectedEnd = null;
                  }
                });
              },
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isStart || isEnd)
                      ? const Color(0xFFE65C00)
                      : isInRange
                          ? const Color(0xFFFFF3ED)
                          : Colors.transparent,
                  border: isToday && !(isStart || isEnd)
                      ? Border.all(color: const Color(0xFFE65C00), width: 1.5)
                      : null,
                ),
                child: Text(
                  '$dayNum',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: (isStart || isEnd || isToday) ? FontWeight.bold : FontWeight.normal,
                    color: (isStart || isEnd)
                        ? Colors.white
                        : isInRange
                            ? const Color(0xFFE65C00)
                            : const Color(0xFF1E293B),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final prevMonth = DateTime(_monthPivot.year, _monthPivot.month - 1, 1);

    return Column(
      children: [
        // Picker Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: Color(0xFF1A1A2E)),
              onPressed: () {
                setState(() {
                  _monthPivot = DateTime(_monthPivot.year, _monthPivot.month - 1, 1);
                });
              },
            ),
            Text(
              'Select Custom Range',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: Color(0xFF1A1A2E)),
              onPressed: () {
                setState(() {
                  _monthPivot = DateTime(_monthPivot.year, _monthPivot.month + 1, 1);
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Display current selection range
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF5EE),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.calendar_month, size: 16, color: Color(0xFFE65C00)),
              const SizedBox(width: 8),
              Text(
                _selectedStart != null
                    ? '${DateFormat('dd MMM yyyy').format(_selectedStart!)}${_selectedEnd != null ? ' - ${DateFormat('dd MMM yyyy').format(_selectedEnd!)}' : ' (Choose End Date)'}'
                    : 'Choose Start Date',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Scrollable stacked dual months
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            children: [
              _buildMonthGrid(prevMonth),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(color: Color(0xFFE2E8F0)),
              ),
              _buildMonthGrid(_monthPivot),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Cancel', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: (_selectedStart != null && _selectedEnd != null)
                    ? () {
                        Navigator.pop(
                          context,
                          DateTimeRange(
                            start: DateTime(_selectedStart!.year, _selectedStart!.month, _selectedStart!.day),
                            end: DateTime(_selectedEnd!.year, _selectedEnd!.month, _selectedEnd!.day, 23, 59, 59),
                          ),
                        );
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                child: Text('Apply Range', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

