import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../core/member_analytics_service.dart';
import '../utils/pdf_exporter.dart';
import '../utils/attendance_format.dart';
import 'member_history_tab.dart';
import 'reservations/join_flow_screen.dart';
import 'library_public_profile_screen.dart';
import 'notifications_screen.dart';

class PastLibraryDetailScreen extends StatefulWidget {
  final String membershipId;

  const PastLibraryDetailScreen({
    super.key,
    required this.membershipId,
  });

  @override
  State<PastLibraryDetailScreen> createState() => _PastLibraryDetailScreenState();
}

class _PastLibraryDetailScreenState extends State<PastLibraryDetailScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _errorMessage;

  // Data
  Map<String, dynamic>? _membership;
  Map<String, dynamic>? _userReview;
  int _selectedStars = 0;
  final _reviewController = TextEditingController();
  bool _isSubmittingReview = false;
  List<Map<String, dynamic>> _attendanceLogs = [];
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _closures = [];
  List<Map<String, dynamic>> _badges = [];

  // Heatmap UI months list
  List<DateTime> _heatmapMonths = [];

  // Paginated session history
  int _visibleSessionsLimit = 20;

  // Calculated Stats
  int _presentDays = 0;
  double _totalHours = 0.0;
  double _totalPaid = 0.0;
  int _bestStreak = 0;

  @override
  void initState() {
    super.initState();
    _loadPastLibraryDetails();
  }

  Future<void> _loadPastLibraryDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception("User session missing");

      // 1. Fetch Membership record
      final membershipRes = await _supabase
          .from('memberships')
          .select('*, libraries(*), shifts(*), seats(*)')
          .eq('id', widget.membershipId)
          .maybeSingle();

      if (membershipRes == null) {
        throw Exception("Membership record not found");
      }
      _membership = membershipRes;

      final libraryId = _membership!['library_id'];
      final startDateStr = _membership!['start_date'];
      final endDateStr = _membership!['exited_at'] ?? _membership!['end_date'];

      if (startDateStr == null || endDateStr == null) {
        throw Exception("Membership start or end date is missing");
      }

      final startDate = DateTime.parse(startDateStr);
      final endDate = DateTime.parse(endDateStr);

      // Generate months for the heatmap
      _heatmapMonths = _getMonthsInRange(startDate, endDate);

      // 2. Fetch Attendance Logs during membership period
      final attendanceRes = await _supabase
          .from('attendance')
          .select('*, libraries(name), shifts(name), seats(seat_label)')
          .eq('member_id', user.id)
          .eq('library_id', libraryId)
          .gte('check_in_time', startDate.toUtc().toIso8601String())
          .lte('check_in_time', endDate.add(const Duration(days: 1)).toUtc().toIso8601String())
          .order('check_in_time', ascending: false);
      _attendanceLogs = List<Map<String, dynamic>>.from(attendanceRes);

      // 3. Fetch Payments during membership period (or linked)
      final paymentsRes = await _supabase
          .from('payments')
          .select('*, memberships(plan_type, shifts(name)), libraries(name)')
          .eq('member_id', user.id)
          .eq('library_id', libraryId)
          .eq('status', 'confirmed')
          .order('payment_date', ascending: false);
      _payments = List<Map<String, dynamic>>.from(paymentsRes);

      // 4. Fetch Scheduled Closures for this library
      try {
        final closuresRes = await _supabase
            .from('scheduled_closures')
            .select('*')
            .eq('library_id', libraryId);
        _closures = List<Map<String, dynamic>>.from(closuresRes);
      } catch (e) {
        debugPrint('Could not fetch closures: $e');
        _closures = [];
      }

      // 5. Fetch Badges earned at this library
      final badgesRes = await _supabase
          .from('badges')
          .select('*')
          .eq('member_id', user.id)
          .eq('library_id', libraryId);
      _badges = List<Map<String, dynamic>>.from(badgesRes);

      // 6. Compute stats
      _calculateStats(startDate, endDate);

      // Fetch user's review for this library
      final reviewRes = await _supabase
          .from('reviews')
          .select('*')
          .eq('library_id', libraryId)
          .eq('member_id', user.id)
          .maybeSingle();
      
      _userReview = reviewRes;
      if (_userReview != null) {
        _selectedStars = _userReview!['rating'] ?? 0;
        _reviewController.text = _userReview!['review_text'] ?? '';
      } else {
        _selectedStars = 0;
        _reviewController.clear();
      }

    } catch (e) {
      debugPrint('Error loading past library details: $e');
      _errorMessage = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<DateTime> _getMonthsInRange(DateTime start, DateTime end) {
    final List<DateTime> months = [];
    var current = DateTime(start.year, start.month, 1);
    final last = DateTime(end.year, end.month, 1);

    while (current.isBefore(last) || current.isAtSameMomentAs(last)) {
      months.add(current);
      current = DateTime(current.year, current.month + 1, 1);
    }
    return months;
  }

  void _calculateStats(DateTime start, DateTime end) {
    // Unique days present
    final Set<String> presentDaysSet = {};
    _totalHours = 0.0;

    for (var log in _attendanceLogs) {
      if (log['check_in_time'] != null) {
        final ci = DateTime.parse(log['check_in_time']).toLocal();
        presentDaysSet.add(DateFormat('yyyy-MM-dd').format(ci));

        if (log['check_out_time'] != null) {
          final co = DateTime.parse(log['check_out_time']).toLocal();
          final diff = co.difference(ci).inMinutes;
          _totalHours += diff / 60.0;
        }
      }
    }
    _presentDays = presentDaysSet.length;

    // Total paid
    _totalPaid = 0.0;
    for (var p in _payments) {
      final amt = p['amount'];
      if (amt != null) {
        _totalPaid += (amt as num).toDouble();
      }
    }

    // Best streak
    _bestStreak = _computeBestStreak();
  }

  int _computeBestStreak() {
    if (_attendanceLogs.isEmpty) return 0;
    final Set<String> uniqueDates = {};
    for (var l in _attendanceLogs) {
      if (l['check_in_time'] != null) {
        final date = DateTime.parse(l['check_in_time'] as String).toLocal();
        uniqueDates.add(DateFormat('yyyy-MM-dd').format(date));
      }
    }
    final sortedDates = uniqueDates.map((d) => DateTime.parse(d)).toList()..sort();
    if (sortedDates.isEmpty) return 0;

    int bestStreak = 0;
    int currentStreak = 1;

    for (int i = 0; i < sortedDates.length - 1; i++) {
      final diff = sortedDates[i+1].difference(sortedDates[i]).inDays;
      if (diff == 1) {
        currentStreak++;
      } else if (diff > 1) {
        if (currentStreak > bestStreak) {
          bestStreak = currentStreak;
        }
        currentStreak = 1;
      }
    }
    if (currentStreak > bestStreak) {
      bestStreak = currentStreak;
    }
    return bestStreak;
  }

  void _showDayDetailPopup(String dateStr, String status) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final DateTime date = DateTime.parse(dateStr);
    final heading = DateFormat('EEEE, dd MMM yyyy').format(date);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: MemberAnalyticsService.instance.fetchDaySessions(user.id, dateStr),
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
                    'Error loading session logs: ${snapshot.error}',
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
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'This day was scheduled as a closure. Your study streak was protected!',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
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
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'No sessions on this day',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
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
                          color: const Color(0xFFFBF5EE),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  log['shift'] ?? 'N/A',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF1E293B)),
                                ),
                                Builder(builder: (_) {
                                  final tag = attendanceTag(log['session_type']);
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: tag.isManual ? Colors.amber[100] : const Color(0xFFE65C00).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      tag.label.toUpperCase(),
                                      style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: tag.isManual ? Colors.amber[900] : const Color(0xFFE65C00)),
                                    ),
                                  );
                                }),
                              ],
                            ),
                            const Divider(height: 16, color: Color(0xFFCBD5E1)),
                            _buildPopupDetailRow('Seat', log['seat']?.toString() ?? 'N/A'),
                            _buildPopupDetailRow('Check-in', log['check_in'] ?? 'N/A'),
                            _buildPopupDetailRow('Check-out', log['check_out'] ?? 'N/A'),
                            _buildPopupDetailRow('Duration', durationStr),
                          ],
                        ),
                      );
                    },
                  ),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, top: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    heading,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 12),
                  content,
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Close'),
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

  Widget _buildPopupDetailRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
          Text(val, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
        ],
      ),
    );
  }

  void _showExportOptions() {
    if (_membership == null) return;
    
    // Map attendance logs to match the export sheet's format
    final List<Map<String, dynamic>> formattedAttendance = _attendanceLogs.map((log) {
      final checkIn = DateTime.parse(log['check_in_time']).toLocal();
      return {
        'date': checkIn,
        'type': 'present',
        'session_type': log['session_type'] ?? 'normal',
        'data': log,
      };
    }).toList();

    // Map closures to match the format
    final List<Map<String, dynamic>> formattedClosures = _closures.map((c) {
      final dateStr = c['closure_date'] ?? c['start_date'] ?? c['date'];
      return {
        'date': dateStr != null ? DateTime.parse(dateStr) : DateTime.now(),
        'type': 'closed',
        'reason': c['reason'] ?? 'Closed',
      };
    }).toList();

    final allItems = [...formattedAttendance, ...formattedClosures];
    allItems.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));

    final rangeLabel = '${DateFormat('dd MMM yyyy').format(DateTime.parse(_membership!['start_date']))} to ${DateFormat('dd MMM yyyy').format(DateTime.parse(_membership!['exited_at'] ?? _membership!['end_date']))}';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return ExportOptionsBottomSheet(
          libraryId: _membership!['library_id'],
          dateRange: DateTimeRange(
            start: DateTime.parse(_membership!['start_date']),
            end: DateTime.parse(_membership!['exited_at'] ?? _membership!['end_date']),
          ),
          dateRangeLabel: rangeLabel,
          payments: _payments,
          attendance: allItems,
          memberships: [_membership!],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBF5EE),
        body: const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00))),
      );
    }

    if (_errorMessage != null || _membership == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBF5EE),
        appBar: AppBar(
          backgroundColor: const Color(0xFF475569),
          foregroundColor: Colors.white,
          title: Text('History Detail', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text('Error Loading History Details', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_errorMessage ?? 'Record not found.', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600])),
              ],
            ),
          ),
        ),
      );
    }

    final lib = _membership!['libraries'] as Map<String, dynamic>?;
    final shift = _membership!['shifts'] as Map<String, dynamic>?;
    final seat = _membership!['seats'] as Map<String, dynamic>?;

    final libName = lib?['name'] ?? 'SILENCE Space';
    final cityState = '${lib?['address_city'] ?? ""}, ${lib?['address_state'] ?? ""}';
    final durationStr = '${DateFormat('dd MMM yyyy').format(DateTime.parse(_membership!['start_date']))} - ${DateFormat('dd MMM yyyy').format(DateTime.parse(_membership!['exited_at'] ?? _membership!['end_date']))}';

    return Scaffold(
      backgroundColor: const Color(0xFFFBF5EE),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Muted Gray Header
          _buildHeader(libName, cityState),
          
          // 2. Scrollable Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Membership Summary Card
                  _buildMembershipSummaryCard(shift, seat, durationStr),
                  const SizedBox(height: 16),

                  // Stats Grid (2x2)
                  _buildStatsGrid(),
                  const SizedBox(height: 20),

                  // Badges Earned Here
                  if (_badges.isNotEmpty) ...[
                    _buildBadgesSection(),
                    const SizedBox(height: 20),
                  ],

                  // Achievements block
                  _buildAchievementsSection(),
                  const SizedBox(height: 20),

                  // Month-by-month Heatmap
                  _buildHeatmapSection(),
                  const SizedBox(height: 20),

                  // Session History List (Paginated)
                  _buildSessionsSection(),
                  const SizedBox(height: 20),

                  // Payment History
                  _buildPaymentHistorySection(libName, cityState),
                  const SizedBox(height: 20),

                  // Library Info
                  _buildLibraryInfoSection(lib),
                  const SizedBox(height: 12),

                  // Reviews & Ratings
                  _buildReviewSection(lib),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // 3. Sticky Bottom Actions Bar
          _buildBottomActionBar(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    if (_selectedStars < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 1 star')),
      );
      return;
    }

    setState(() {
      _isSubmittingReview = true;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception("User session missing");

      final libraryId = _membership?['library_id'];
      if (libraryId == null) throw Exception("Library ID not found");

      await _supabase.from('reviews').insert({
        'library_id': libraryId,
        'member_id': user.id,
        'membership_id': widget.membershipId,
        'rating': _selectedStars,
        'review_text': _reviewController.text.trim().isEmpty ? null : _reviewController.text.trim(),
      });

      // Reload/update the details
      await _loadPastLibraryDetails();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review submitted ✓')),
      );
    } catch (e) {
      debugPrint('Error submitting review: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit review: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingReview = false;
        });
      }
    }
  }

  Widget _buildReviewSection(Map<String, dynamic>? lib) {
    if (lib == null) return const SizedBox.shrink();

    final isReviewed = _userReview != null;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isReviewed) ...[
            Text(
              'How was your experience here?',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starIndex = index + 1;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedStars = starIndex;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: Icon(
                      starIndex <= _selectedStars ? Icons.star : Icons.star_border,
                      color: starIndex <= _selectedStars ? const Color(0xFFE65C00) : Colors.grey[350],
                      size: 36,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reviewController,
              maxLines: 3,
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B)),
              decoration: InputDecoration(
                hintText: 'Write a review... (optional)',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE65C00), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isSubmittingReview ? null : _submitReview,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
                disabledBackgroundColor: Colors.grey[300],
              ),
              child: _isSubmittingReview
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Submit Review',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
            ),
          ] else ...[
            Text(
              'Your Review',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: List.generate(5, (index) {
                final ratingVal = _userReview!['rating'] as int? ?? 0;
                return Icon(
                  index < ratingVal ? Icons.star : Icons.star_border,
                  color: index < ratingVal ? const Color(0xFFE65C00) : Colors.grey[350],
                  size: 20,
                );
              }),
            ),
            if (_userReview!['review_text'] != null &&
                _userReview!['review_text'].toString().trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '"${_userReview!['review_text']}"',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF475569),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Submitted: ${DateFormat('dd MMM yyyy').format(DateTime.parse(_userReview!['created_at']).toLocal())}',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // WIDGET BUILDERS
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildHeader(String libName, String cityState) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12, bottom: 20, left: 16, right: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF475569), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  libName,
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  cityState.isNotEmpty ? cityState : 'SILENCE Group',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => NotificationsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMembershipSummaryCard(Map<String, dynamic>? shift, Map<String, dynamic>? seat, String durationStr) {
    final status = (_membership!['status'] ?? '').toString().toUpperCase();
    final exitReason = _membership!['exited_at'] != null ? 'Voluntarily Exited' : 'Membership Expired';
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 3))],
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Membership Summary',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          _buildSummaryRow(Icons.event, 'Membership Period', durationStr),
          const SizedBox(height: 8),
          _buildSummaryRow(Icons.wb_sunny_outlined, 'Shift Assigned', '${shift?['name'] ?? "N/A"} (${shift?['start_time'] ?? ""} - ${shift?['end_time'] ?? ""})'),
          const SizedBox(height: 8),
          _buildSummaryRow(Icons.event_seat_outlined, 'Seat Assigned', seat?['seat_label'] ?? 'N/A'),
          const SizedBox(height: 8),
          _buildSummaryRow(Icons.card_membership, 'Plan Purchased', (_membership!['plan_type'] ?? 'N/A').toString().toUpperCase()),
          const SizedBox(height: 8),
          _buildSummaryRow(Icons.logout, 'Exit Status', exitReason),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.6,
      children: [
        _buildStatCard('Present Days', '$_presentDays Days', Icons.check_circle_outline, const Color(0xFF22C55E)),
        _buildStatCard('Study Hours', '${_totalHours.toStringAsFixed(1)} Hrs', Icons.hourglass_empty, const Color(0xFFE65C00)),
        _buildStatCard('Total Paid', '₹${NumberFormat('#,##,###').format(_totalPaid)}', Icons.payment, const Color(0xFF3B82F6)),
        _buildStatCard('Best Streak', '$_bestStreak Days', Icons.local_fire_department, const Color(0xFFEF4444)),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w500, color: const Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
        ],
      ),
    );
  }

  Widget _buildBadgesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Badges Earned Here',
          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 60,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _badges.length,
            separatorBuilder: (c, i) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final type = _badges[index]['badge_type'] as String? ?? '';
              
              String badgeName = "Study Badge";
              String badgeIcon = "🏆";
              switch (type) {
                case '7_day_streak':
                  badgeName = "7-Day Streak";
                  badgeIcon = "🔥";
                  break;
                case '30_day_streak':
                  badgeName = "30-Day Streak";
                  badgeIcon = "👑";
                  break;
                case 'early_bird':
                  badgeName = "Early Bird";
                  badgeIcon = "🌅";
                  break;
                case 'night_owl':
                  badgeName = "Night Owl";
                  badgeIcon = "🦉";
                  break;
                case 'top_of_week':
                  badgeName = "Top of Week";
                  badgeIcon = "🏆";
                  break;
                case '100_days_club':
                  badgeName = "100 Days Club";
                  badgeIcon = "💯";
                  break;
                case 'consistent':
                  badgeName = "Consistent";
                  badgeIcon = "🎯";
                  break;
              }

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.01), blurRadius: 4)],
                ),
                child: Row(
                  children: [
                    Text(badgeIcon, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Text(badgeName, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAchievementsSection() {
    // Compute milestones
    final List<Map<String, String>> milestones = [];
    if (_totalHours >= 150) {
      milestones.add({'title': 'Gold Scholar 🏅', 'desc': 'Studied 150+ hours at this library!'});
    } else if (_totalHours >= 80) {
      milestones.add({'title': 'Silver Scholar 🥈', 'desc': 'Studied 80+ hours at this library!'});
    } else if (_totalHours >= 30) {
      milestones.add({'title': 'Bronze Scholar 🥉', 'desc': 'Studied 30+ hours at this library!'});
    }

    if (_bestStreak >= 15) {
      milestones.add({'title': 'Streak Legend ⚡', 'desc': 'Crossed a 15-day streak of consecutive study!'});
    } else if (_bestStreak >= 7) {
      milestones.add({'title': 'Consistent Learner 🎯', 'desc': 'Crossed a 7-day study streak!'});
    }

    // Early Check-ins count
    int earlyCheckins = 0;
    for (var log in _attendanceLogs) {
      if (log['check_in_time'] != null) {
        final ci = DateTime.parse(log['check_in_time']).toLocal();
        if (ci.hour < 8) earlyCheckins++;
      }
    }
    if (earlyCheckins >= 5) {
      milestones.add({'title': 'Early Riser 🌅', 'desc': 'Checked in before 8 AM on $earlyCheckins days.'});
    }

    if (milestones.isEmpty) {
      milestones.add({'title': 'Rising Star ✨', 'desc': 'Began study journey at this library!'});
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Study Achievements Here',
          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: milestones.map((m) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.workspace_premium_outlined, color: Color(0xFFE65C00), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m['title']!, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                          const SizedBox(height: 2),
                          Text(m['desc']!, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                        ],
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

  Widget _buildHeatmapSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Attendance Heatmap',
          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
        ),
        const SizedBox(height: 8),
        ..._heatmapMonths.map((month) => _buildHeatmapForMonth(month)),
      ],
    );
  }

  Widget _buildHeatmapForMonth(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final offset = firstDay.weekday - 1;

    final List<Widget> cells = [];
    final List<String> weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    // Weekday headers
    for (var day in weekdays) {
      cells.add(
        Center(
          child: Text(
            day,
            style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)),
          ),
        ),
      );
    }

    // Offset cells (empty spaces)
    for (int i = 0; i < offset; i++) {
      cells.add(const SizedBox.shrink());
    }

    // Group logs and closures for quick lookup
    final Map<String, double> attendanceHoursMap = {};
    for (var log in _attendanceLogs) {
      if (log['check_in_time'] == null) continue;
      final ci = DateTime.parse(log['check_in_time']).toLocal();
      final key = DateFormat('yyyy-MM-dd').format(ci);
      
      double duration = 0.0;
      if (log['check_out_time'] != null) {
        final co = DateTime.parse(log['check_out_time']).toLocal();
        duration = co.difference(ci).inMinutes / 60.0;
      }
      attendanceHoursMap[key] = (attendanceHoursMap[key] ?? 0.0) + duration;
    }

    final Set<String> closedDatesSet = {};
    for (var c in _closures) {
      final dateStr = c['closure_date'] ?? c['start_date'] ?? c['date'];
      if (dateStr != null) {
        closedDatesSet.add(DateFormat('yyyy-MM-dd').format(DateTime.parse(dateStr)));
      }
    }

    final start = DateTime.parse(_membership!['start_date']);
    final end = DateTime.parse(_membership!['exited_at'] ?? _membership!['end_date']);

    final endDateKey = DateFormat('yyyy-MM-dd').format(end);

    for (int i = 1; i <= lastDay.day; i++) {
      final date = DateTime(month.year, month.month, i);
      final dateKey = DateFormat('yyyy-MM-dd').format(date);

      // Check if inside membership bounds
      final bool inRange = (date.isAfter(start.subtract(const Duration(days: 1))) && date.isBefore(end.add(const Duration(days: 1))));

      Color cellColor = Colors.transparent;
      Widget? centerChild;
      bool isLastDay = dateKey == endDateKey;
      bool showStreakBorder = isLastDay;
      bool hasAttendance = attendanceHoursMap.containsKey(dateKey);

      if (inRange) {
        if (hasAttendance) {
          final hours = attendanceHoursMap[dateKey] ?? 0.0;
          if (hours >= 5.0) {
            cellColor = const Color(0xFFE65C00); // Dark orange
          } else if (hours >= 2.0) {
            cellColor = const Color(0xFFFF9A4D); // Medium orange
          } else {
            cellColor = const Color(0xFFFFCBA0); // Light orange
          }
          centerChild = Text(
            '$i',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: hours >= 5.0 ? Colors.white : const Color(0xFF1E293B),
            ),
          );
        } else if (closedDatesSet.contains(dateKey)) {
          cellColor = const Color(0xFFE2E8F0); // Gray for closed
          centerChild = const Text('❄', style: TextStyle(fontSize: 8, color: Color(0xFF64748B)));
        } else {
          cellColor = const Color(0xFFF1F5F9); // White/slate for absent
          centerChild = Text('$i', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8)));
        }
      }

      cells.add(
        GestureDetector(
          onTap: hasAttendance
              ? () => _showDayDetailPopup(dateKey, 'present')
              : (closedDatesSet.contains(dateKey)
                  ? () => _showDayDetailPopup(dateKey, 'closed')
                  : null),
          child: Container(
            margin: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              color: cellColor,
              borderRadius: BorderRadius.circular(6),
              border: showStreakBorder
                  ? Border.all(color: const Color(0xFFE65C00), width: 1.8)
                  : (inRange ? Border.all(color: Colors.grey.withValues(alpha: 0.08), width: 0.5) : null),
            ),
            child: Center(
              child: centerChild,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            DateFormat('MMMM yyyy').format(month),
            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 10),
          GridView.custom(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.0,
            ),
            childrenDelegate: SliverChildListDelegate(cells),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsSection() {
    final paginatedLogs = _attendanceLogs.take(_visibleSessionsLimit).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Session History',
          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
        ),
        const SizedBox(height: 8),
        if (_attendanceLogs.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Center(
              child: Text(
                'No sessions recorded.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
              ),
            ),
          )
        else ...[
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: paginatedLogs.length,
            separatorBuilder: (c, i) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final log = paginatedLogs[index];
              final checkInStr = log['check_in_time'] as String;
              final checkOutStr = log['check_out_time'] as String?;

              final ci = DateTime.parse(checkInStr).toLocal();
              final dateStr = DateFormat('dd MMM yyyy').format(ci);
              final String timeStr = checkOutStr != null
                  ? '${DateFormat('hh:mm a').format(ci)} - ${DateFormat('hh:mm a').format(DateTime.parse(checkOutStr).toLocal())}'
                  : '${DateFormat('hh:mm a').format(ci)} - Ongoing';

              String durationStr = 'Ongoing';
              if (checkOutStr != null) {
                final diff = DateTime.parse(checkOutStr).difference(ci);
                final hrs = diff.inHours;
                final mins = diff.inMinutes % 60;
                durationStr = hrs > 0 ? '${hrs}h ${mins}m' : '${mins}m';
              }

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dateStr, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                        const SizedBox(height: 2),
                        Text(timeStr, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(durationStr, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                        const SizedBox(height: 2),
                        Text('Seat ${log['seats']?['seat_label'] ?? "N/A"}', style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8))),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          if (_attendanceLogs.length > _visibleSessionsLimit) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _visibleSessionsLimit += 20;
                });
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE65C00),
                side: const BorderSide(color: Color(0xFFE65C00)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                minimumSize: const Size(double.infinity, 40),
              ),
              child: const Text('Load More Sessions'),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildPaymentHistorySection(String libName, String libAddress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment History',
          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
        ),
        const SizedBox(height: 8),
        if (_payments.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Center(
              child: Text(
                'No payments found.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _payments.length,
            separatorBuilder: (c, i) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final p = _payments[index];
              final dateStr = p['payment_date'] != null
                  ? DateFormat('dd MMM yyyy').format(DateTime.parse(p['payment_date']).toLocal())
                  : 'N/A';
              final amt = p['amount'] ?? 0;
              final method = (p['method'] ?? 'cash').toString().toUpperCase();

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('₹$amt', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                        const SizedBox(height: 2),
                        Text('$dateStr • $method', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.download_outlined, color: Color(0xFFE65C00), size: 20),
                      onPressed: () async {
                        try {
                          final user = _supabase.auth.currentUser;
                          final profile = await _supabase.from('users').select('full_name').eq('id', user!.id).maybeSingle();
                          final memberName = profile != null ? (profile['full_name'] ?? 'User') : 'User';
                          
                          await PdfExporter.exportPaymentReceipt(
                            libraryName: libName,
                            libraryAddress: libAddress,
                            payment: p,
                            memberName: memberName,
                          );
                          if (!mounted) return;
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to download receipt: $e')));
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildLibraryInfoSection(Map<String, dynamic>? lib) {
    if (lib == null) return const SizedBox.shrink();
    final address = '${lib['address_street'] ?? ""}, ${lib['address_city'] ?? ""}, ${lib['address_state'] ?? ""} ${lib['address_pincode'] ?? ""}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Library Info',
          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lib['name'] ?? 'SILENCE Library',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 6),
              Text(
                address,
                style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LibraryPublicProfileScreen(
                        libraryId: lib['id'],
                        isAdmin: false,
                      ),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE65C00),
                  side: const BorderSide(color: Color(0xFFE65C00)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  minimumSize: const Size(double.infinity, 36),
                ),
                child: const Text('View Library Profile'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _showExportOptions,
              icon: const Icon(Icons.share_outlined, size: 16),
              label: const Text('Export History'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF475569),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                final libId = _membership?['library_id'];
                if (libId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => JoinFlowScreen(libraryId: libId),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Rejoin Library'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
