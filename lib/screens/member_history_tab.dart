import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'reservations/member_detail_screen.dart';

class MemberHistoryTab extends StatefulWidget {
  const MemberHistoryTab({super.key});

  @override
  State<MemberHistoryTab> createState() => _MemberHistoryTabState();
}

class _MemberHistoryTabState extends State<MemberHistoryTab> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _errorMessage;

  // Data State
  Map<String, dynamic>? _activeMembership;
  List<Map<String, dynamic>> _activePayments = [];
  bool _showAllActivePayments = false;

  List<Map<String, dynamic>> _pastMemberships = [];

  List<Map<String, dynamic>> _allPayments = [];
  List<Map<String, dynamic>> _joinedLibrariesList = []; // For filtering

  // Filter States
  String _selectedLibraryId = 'All'; // 'All' or libraryId
  String _selectedDateRange = 'This Month'; // 'Today', 'This Week', 'This Month', 'Custom'
  DateTimeRange? _customDateRange;

  // Pagination
  int _allPaymentsPage = 1;
  final int _paymentsPerPage = 20;
  bool _hasMorePayments = true;
  bool _isLoadingMorePayments = false;

  @override
  void initState() {
    super.initState();
    _loadHistoryData();
  }

  Future<void> _loadHistoryData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception("User session missing.");

      // 1. Fetch Active Membership (active or trial status)
      final activeRes = await _supabase
          .from('memberships')
          .select('*, libraries(*), shifts(*), seats(*)')
          .eq('member_id', user.id)
          .inFilter('status', ['active', 'trial'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      _activeMembership = activeRes;

      // 2. Fetch payments for the active membership
      if (_activeMembership != null) {
        final activePayRes = await _supabase
            .from('payments')
            .select('*')
            .eq('membership_id', _activeMembership!['id'])
            .order('payment_date', ascending: false);
        _activePayments = List<Map<String, dynamic>>.from(activePayRes);
      } else {
        _activePayments = [];
      }

      // 3. Fetch Past Memberships (exited or expired status)
      final pastRes = await _supabase
          .from('memberships')
          .select('*, libraries(*)')
          .eq('member_id', user.id)
          .inFilter('status', ['exited', 'expired'])
          .order('created_at', ascending: false);
      _pastMemberships = List<Map<String, dynamic>>.from(pastRes);

      // 4. Fetch list of unique libraries ever joined to build dropdown filter
      final allJoinedRes = await _supabase
          .from('memberships')
          .select('libraries(id, name)')
          .eq('member_id', user.id);

      final Map<String, String> uniqueLibs = {};
      for (var m in allJoinedRes) {
        final lib = m['libraries'] as Map<String, dynamic>?;
        if (lib != null) {
          uniqueLibs[lib['id']] = lib['name'] ?? 'Study Center';
        }
      }

      _joinedLibrariesList = uniqueLibs.entries
          .map((e) => {'id': e.key, 'name': e.value})
          .toList();

      if (_selectedLibraryId != 'All') {
        final exists = _joinedLibrariesList.any((lib) => lib['id'] == _selectedLibraryId);
        if (!exists) {
          _selectedLibraryId = 'All';
        }
      }

      // Reset payments page
      _allPaymentsPage = 1;
      _hasMorePayments = true;

      // 5. Fetch all payments (filtered & paginated)
      await _fetchFilteredPayments(append: false);

    } catch (e) {
      debugPrint('Error loading history tab data: $e');
      _errorMessage = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchFilteredPayments({required bool append}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    if (append) {
      setState(() => _isLoadingMorePayments = true);
    }

    try {
      var queryBuilder = _supabase
          .from('payments')
          .select('*, memberships(plan_type, shifts(name)), libraries(name)')
          .eq('member_id', user.id);

      // Library filter
      if (_selectedLibraryId != 'All') {
        queryBuilder = queryBuilder.eq('library_id', _selectedLibraryId);
      }

      // Date Range filter
      final now = DateTime.now();
      DateTime? startDate;
      DateTime? endDate = now;

      if (_selectedDateRange == 'Today') {
        startDate = DateTime(now.year, now.month, now.day);
      } else if (_selectedDateRange == 'This Week') {
        startDate = now.subtract(Duration(days: now.weekday - 1));
        startDate = DateTime(startDate.year, startDate.month, startDate.day);
      } else if (_selectedDateRange == 'This Month') {
        startDate = DateTime(now.year, now.month, 1);
      } else if (_selectedDateRange == 'Custom' && _customDateRange != null) {
        startDate = _customDateRange!.start;
        endDate = _customDateRange!.end.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      }

      if (startDate != null && endDate != null) {
        queryBuilder = queryBuilder
            .gte('payment_date', startDate.toUtc().toIso8601String())
            .lte('payment_date', endDate.toUtc().toIso8601String());
      }

      // Pagination limits
      final int fromIndex = (_allPaymentsPage - 1) * _paymentsPerPage;
      final int toIndex = fromIndex + _paymentsPerPage - 1;

      final res = await queryBuilder
          .order('payment_date', ascending: false)
          .range(fromIndex, toIndex);

      final fetchedList = List<Map<String, dynamic>>.from(res);

      if (mounted) {
        setState(() {
          if (append) {
            _allPayments.addAll(fetchedList);
          } else {
            _allPayments = fetchedList;
          }
          _hasMorePayments = fetchedList.length == _paymentsPerPage;
        });
      }
    } catch (e) {
      debugPrint('Error fetching filtered payments: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMorePayments = false;
        });
      }
    }
  }

  void _loadMorePayments() async {
    if (_isLoadingMorePayments || !_hasMorePayments) return;
    _allPaymentsPage++;
    await _fetchFilteredPayments(append: true);
  }

  // Calculate past duration
  int _calculateDurationInMonths(String? startStr, String? endStr) {
    if (startStr == null || endStr == null) return 1;
    try {
      final start = DateTime.parse(startStr);
      final end = DateTime.parse(endStr);
      final diff = end.difference(start).inDays;
      if (diff <= 31) return 1;
      return (diff / 30.0).round();
    } catch (_) {
      return 1;
    }
  }

  // CSV Export for current membership payments
  Future<void> _exportCurrentPaymentsCSV() async {
    if (_activeMembership == null || _activePayments.isEmpty) return;
    final libName = _activeMembership!['libraries']?['name'] ?? 'Library';
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final buffer = StringBuffer();
    buffer.writeln('SILENCE Active Membership Payments Export');
    buffer.writeln('Library:, $libName');
    buffer.writeln('Export Date:, ${DateFormat('dd MMM yyyy hh:mm a').format(DateTime.now())}');
    buffer.writeln();
    buffer.writeln('Date,Amount,Method,Status');

    for (var p in _activePayments) {
      final dateStr = p['payment_date'] != null 
          ? DateFormat('dd MMM yyyy hh:mm a').format(DateTime.parse(p['payment_date']).toLocal()) 
          : 'N/A';
      buffer.writeln('"$dateStr","₹${p['amount']}","${(p['method'] ?? 'UPI').toString().toUpperCase()}","${p['status'] ?? 'pending'}"');
    }

    try {
      final tempDir = Directory.systemTemp;
      final fileName = '${libName.replaceAll(' ', '_')}_active_payments.csv';
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsString(buffer.toString());
      await Share.shareXFiles([XFile(tempFile.path, mimeType: 'text/csv')], subject: 'Active Payments - $libName');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to export CSV: $e')));
      }
    }
  }

  // CSV Export for filtered payments
  Future<void> _exportFilteredPaymentsCSV() async {
    if (_allPayments.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('SILENCE Filtered Payments Export');
    buffer.writeln('Filter Library ID:, $_selectedLibraryId');
    buffer.writeln('Filter Date Range:, $_selectedDateRange');
    buffer.writeln('Export Date:, ${DateFormat('dd MMM yyyy hh:mm a').format(DateTime.now())}');
    buffer.writeln();
    buffer.writeln('Date,Library,Amount,Method,Status');

    for (var p in _allPayments) {
      final dateStr = p['payment_date'] != null 
          ? DateFormat('dd MMM yyyy hh:mm a').format(DateTime.parse(p['payment_date']).toLocal()) 
          : 'N/A';
      final libName = p['libraries']?['name'] ?? 'N/A';
      buffer.writeln('"$dateStr","$libName","₹${p['amount']}","${(p['method'] ?? 'UPI').toString().toUpperCase()}","${p['status'] ?? 'pending'}"');
    }

    try {
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/silence_payments_export.csv');
      await tempFile.writeAsString(buffer.toString());
      await Share.shareXFiles([XFile(tempFile.path, mimeType: 'text/csv')], subject: 'Payments Export');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to export CSV: $e')));
      }
    }
  }

  Future<void> _selectCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 30)),
            end: DateTime.now(),
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFE65C00),
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _selectedDateRange = 'Custom';
        _allPaymentsPage = 1;
      });
      _fetchFilteredPayments(append: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFBF5EE),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFE65C00))),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBF5EE),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text('History Load Error', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_errorMessage!, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13)),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loadHistoryData,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                  child: const Text('Retry'),
                )
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFBF5EE),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Orange gradient header
          Container(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 16, bottom: 24, left: 24, right: 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF6B00), Color(0xFFE65C00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SILENCE',
                  style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.2),
                ),
                const SizedBox(height: 8),
                Text(
                  'Membership & Payments History',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  'Access past invoices, attendance timelines, and exports',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withOpacity(0.85)),
                ),
              ],
            ),
          ),

          // Main scrollable contents
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadHistoryData,
              color: const Color(0xFFE65C00),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: Current Library details
                    _buildCurrentLibrarySection(),
                    const SizedBox(height: 24),

                    // Section 2: Past Libraries list
                    _buildPastLibrariesSection(),
                    const SizedBox(height: 24),

                    // Section 3: All Invoices / Payments history with pagination & filters
                    _buildAllPaymentsSection(),
                    const SizedBox(height: 80), // spacer for FAB
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  // ── 1. Current Library Layout ───────────────────────────────────────────────
  Widget _buildCurrentLibrarySection() {
    if (_activeMembership == null) {
      return const SizedBox.shrink(); // hide section if no active membership
    }

    final library = _activeMembership!['libraries'] as Map<String, dynamic>? ?? {};
    final shift = _activeMembership!['shifts'] as Map<String, dynamic>? ?? {};
    final seat = _activeMembership!['seats'] as Map<String, dynamic>? ?? {};

    final visiblePayments = _showAllActivePayments 
        ? _activePayments 
        : _activePayments.take(5).toList();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Current Active Space',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(6)),
                child: Text('ACTIVE', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A))),
              )
            ],
          ),
          const SizedBox(height: 12),
          Text(
            library['name'] ?? 'Study Center',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.wb_sunny_outlined, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                'Shift: ${shift['name'] ?? 'N/A'}',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569)),
              ),
              const SizedBox(width: 16),
              const Icon(Icons.event_seat_outlined, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                'Seat: ${seat['seat_label'] ?? 'Pending'}',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569)),
              ),
            ],
          ),
          const Divider(height: 24),

          Text(
            'Membership Payments',
            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 8),

          if (_activePayments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Text('No payments recorded for this membership.', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
            )
          else ...[
            ...visiblePayments.map((p) => _buildInvoiceRow(p)),
            if (_activePayments.length > 5)
              Center(
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _showAllActivePayments = !_showAllActivePayments;
                    });
                  },
                  child: Text(
                    _showAllActivePayments ? 'View Less' : 'View All (${_activePayments.length})',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                  ),
                ),
              ),
          ],

          const Divider(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _exportCurrentPaymentsCSV,
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('Export CSV'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
          )
        ],
      ),
    );
  }

  // ── 2. Past Libraries Layout ───────────────────────────────────────────────
  Widget _buildPastLibrariesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Past Libraries',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 10),

        if (_pastMemberships.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Icon(Icons.history, size: 36, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text('No past memberships found.', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500])),
              ],
            ),
          )
        else
          Column(
            children: _pastMemberships.map((m) {
              final library = m['libraries'] as Map<String, dynamic>? ?? {};
              final exitDateStr = m['exited_at'] ?? m['end_date'];
              String exitDate = 'N/A';
              try {
                if (exitDateStr != null) {
                  exitDate = DateFormat('dd MMM yyyy').format(DateTime.parse(exitDateStr).toLocal());
                }
              } catch (_) {}

              final months = _calculateDurationInMonths(m['start_date'], m['end_date']);

              return Card(
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE2E8F0))),
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              library['name'] ?? 'Study Center',
                              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Duration: $months month${months > 1 ? 's' : ''}  •  Exited: $exitDate',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () {
                          // Navigate to Read-only detail view of student details (attendance/payments)
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MemberDetailScreen(),
                              settings: RouteSettings(
                                arguments: {
                                  'memberId': _supabase.auth.currentUser!.id,
                                  'isReadOnly': true,
                                },
                              ),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE65C00)),
                          foregroundColor: const Color(0xFFE65C00),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        child: Text('View History', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  // ── 3. All Invoices & Payments Layout ─────────────────────────────────────────
  Widget _buildAllPaymentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'All Payments Invoices',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            if (_allPayments.isNotEmpty)
              IconButton(
                onPressed: _exportFilteredPaymentsCSV,
                icon: const Icon(Icons.share_rounded, size: 20, color: Color(0xFFE65C00)),
                tooltip: 'Share CSV',
              )
          ],
        ),
        const SizedBox(height: 10),

        // Filter Controls Widget Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Column(
            children: [
              // Library Dropdown Filter
              Row(
                children: [
                  Text('Library:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: (_selectedLibraryId == 'All' || _joinedLibrariesList.any((lib) => lib['id'] == _selectedLibraryId)) ? _selectedLibraryId : 'All',
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF1E293B)),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedLibraryId = val;
                                _allPaymentsPage = 1;
                              });
                              _fetchFilteredPayments(append: false);
                            }
                          },
                          items: [
                            const DropdownMenuItem(value: 'All', child: Text('All Libraries')),
                            ..._joinedLibrariesList.map((lib) => DropdownMenuItem(
                              value: lib['id'],
                              child: Text(lib['name'] ?? 'Library', overflow: TextOverflow.ellipsis),
                            )),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Date Range Filter chips
              Row(
                children: [
                  Text('Date:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildDateFilterChip('Today'),
                          const SizedBox(width: 4),
                          _buildDateFilterChip('This Week'),
                          const SizedBox(width: 4),
                          _buildDateFilterChip('This Month'),
                          const SizedBox(width: 4),
                          _buildDateFilterChip('Custom'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (_allPayments.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Center(
              child: Text(
                'No payments found matching the selected filters.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500]),
              ),
            ),
          )
        else
          Column(
            children: [
              ..._allPayments.map((p) => _buildPaymentInvoiceCard(p)),
              if (_hasMorePayments)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: OutlinedButton(
                    onPressed: _loadMorePayments,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE65C00)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: _isLoadingMorePayments 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
                        : Text('Load More Invoices', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildDateFilterChip(String label) {
    final isSelected = _selectedDateRange == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFFE65C00),
      labelStyle: GoogleFonts.inter(
        fontSize: 11,
        color: isSelected ? Colors.white : const Color(0xFF475569),
        fontWeight: FontWeight.bold,
      ),
      onSelected: (val) {
        if (val) {
          if (label == 'Custom') {
            _selectCustomDateRange();
          } else {
            setState(() {
              _selectedDateRange = label;
              _allPaymentsPage = 1;
            });
            _fetchFilteredPayments(append: false);
          }
        }
      },
    );
  }

  // Row layout inside active library section
  Widget _buildInvoiceRow(Map<String, dynamic> p) {
    final amount = p['amount'] ?? 0;
    final status = p['status'] ?? 'pending';
    final method = (p['method'] ?? 'UPI').toString().toUpperCase();
    final dateStr = p['payment_date'] != null 
        ? DateFormat('dd MMM yyyy').format(DateTime.parse(p['payment_date']).toLocal()) 
        : 'N/A';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                status == 'confirmed' ? Icons.check_circle : Icons.pending,
                color: status == 'confirmed' ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                dateStr,
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(width: 6),
              Text(
                '($method)',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
          Text(
            '₹$amount',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
          ),
        ],
      ),
    );
  }

  // Invoice Card inside list view
  Widget _buildPaymentInvoiceCard(Map<String, dynamic> p) {
    final amount = p['amount'] ?? 0;
    final status = p['status'] ?? 'pending';
    final method = (p['method'] ?? 'UPI').toString().toUpperCase();
    final libName = p['libraries']?['name'] ?? 'N/A';
    final plan = p['memberships']?['plan_type'] ?? '';
    final shiftName = p['memberships']?['shifts']?['name'] ?? '';

    String payDate = 'N/A';
    try {
      if (p['payment_date'] != null) {
        payDate = DateFormat('dd MMMM yyyy, hh:mm a').format(DateTime.parse(p['payment_date']).toLocal());
      }
    } catch (_) {}

    Color statusBg = const Color(0xFFF3F4F6);
    Color statusText = const Color(0xFF6B7280);
    if (status == 'confirmed') {
      statusBg = const Color(0xFFDCFCE7);
      statusText = const Color(0xFF16A34A);
    } else if (status == 'rejected') {
      statusBg = const Color(0xFFFEE2E2);
      statusText = const Color(0xFFDC2626);
    } else if (status == 'pending') {
      statusBg = const Color(0xFFFEF3C7);
      statusText = const Color(0xFFD97706);
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('₹$amount', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                child: Text(status.toUpperCase(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: statusText)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.storefront, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  libName,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 12, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(child: Text(payDate, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600]))),
            ],
          ),
          if (plan.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0, left: 18.0),
              child: Text(
                'Plan: ${plan == 'monthly' ? 'Monthly' : plan == '3_month' ? '3-Month' : '6-Month'} ($shiftName)',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4.0, left: 18.0),
            child: Text(
              'Method: $method • Txn: ${p['id'].toString().substring(0, 8).toUpperCase()}',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[400]),
            ),
          ),
        ],
      ),
    );
  }
}
