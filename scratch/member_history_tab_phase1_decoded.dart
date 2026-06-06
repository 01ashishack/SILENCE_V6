"import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'notifications_screen.dart';
import 'reservations/member_detail_screen.dart';
import '../core/calendar_picker.dart';

class MemberHistoryTab extends StatefulWidget {
  const MemberHistoryTab({super.key});

  @override
  State<MemberHistoryTab> createState() => _MemberHistoryTabState();
}

class _MemberHistoryTabState extends State<MemberHistoryTab> with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  late TabController _tabController;

  // Loading & Error states
  bool _isLoading = true;
  String? _errorMessage;

  // Filter States
  String _selectedLibraryId = 'All'; // 'All' or libraryId
  String _selectedDateRangeOption = 'This Month'; // This Week, This Month, Last Month, Last 3 Months, This Year, Custom
  DateTimeRange? _customDateRange;

  // Lists from Database
  List<Map<String, dynamic>> _memberships = [];
  List<Map<String, dynamic>> _attendanceLogs = [];
  List<Map<String, dynamic>> _closures = [];
  List<Map<String, dynamic>> _payments = [];

  // Dropdown UI Lists
  List<Map<String, dynamic>> _librariesList = [];

  // Sessions Sub-tab state
  String _sessionFilter = 'All'; // All, Present, Absent, Incomplete, Manual, Auto-checkout, Offline Sync
  List<Map<String, dynamic>> _allGeneratedSessions = [];
  List<Map<String, dynamic>> _filteredSessions = [];
  int _visibleSessionsCount = 20;

  // Sessions Stats
  int _presentCount = 0;
  int _absentCount = 0;
  double _totalHours = 0.0;
  double _avgHoursPerDay = 0.0;

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
  void dispose() 
<truncated 52987 bytes>