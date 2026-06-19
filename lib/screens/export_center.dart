import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/calendar_picker.dart';
import '../widgets/app_gradient_scaffold.dart';

class ExportCenterScreen extends StatefulWidget {
  const ExportCenterScreen({super.key});

  @override
  State<ExportCenterScreen> createState() => _ExportCenterScreenState();
}

class _ExportCenterScreenState extends State<ExportCenterScreen> {
  final _supabase = Supabase.instance.client;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  bool _isExporting = false;
  String _selectedPreset = 'This Month'; // 'Today', 'This Week', 'This Month', 'Custom'

  @override
  void initState() {
    super.initState();
    _applyPreset('This Month');
  }

  void _applyPreset(String preset) {
    final now = DateTime.now();
    setState(() {
      _selectedPreset = preset;
      if (preset == 'Today') {
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (preset == 'This Week') {
        final weekday = now.weekday; // 1 = Monday, 7 = Sunday
        final start = now.subtract(Duration(days: weekday - 1));
        _startDate = DateTime(start.year, start.month, start.day);
        _endDate = now;
      } else if (preset == 'This Month') {
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = now;
      }
    });
  }

  Future<void> _selectDateRange() async {
    // Uses the app's custom calendar (single-date) twice — pick start, then
    // end — to stay consistent with the rest of the app instead of the stock
    // Material range picker.
    final lastAllowed = DateTime.now().add(const Duration(days: 365));
    final start = await showCalendarGridBottomSheet(
      context,
      initialDate: _startDate,
      firstDate: DateTime(2025),
      lastDate: lastAllowed,
    );
    if (!mounted || start == null) return;
    final end = await showCalendarGridBottomSheet(
      context,
      initialDate: _endDate.isBefore(start) ? start : _endDate,
      firstDate: start,
      lastDate: lastAllowed,
    );
    if (!mounted || end == null) return;
    setState(() {
      _startDate = start;
      _endDate = end.isBefore(start) ? start : end;
      _selectedPreset = 'Custom';
    });
  }

  Future<String?> _firstOwnedLibraryId() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    final res = await _supabase
        .from('libraries')
        .select('id')
        .eq('owner_id', user.id)
        .limit(1)
        .maybeSingle();
    return res?['id']?.toString();
  }

  String _csv(Object? value) {
    final text = (value ?? '').toString().replaceAll('"', '""');
    return '"$text"';
  }

  Future<void> _exportData(String type, String title, bool isPdf) async {
    setState(() => _isExporting = true);
    final startFmt = DateFormat('yyyy-MM-dd').format(_startDate);
    final endFmt = DateFormat('yyyy-MM-dd').format(_endDate);

    try {
      final libraryId = await _firstOwnedLibraryId();
      if (libraryId == null) throw 'No library found for this admin.';

      if (isPdf) {
        final pdfBytes = await _generatePdfReport(type, libraryId);
        final filename = 'SILENCE_${type}_report_${startFmt}_to_$endFmt.pdf';
        if (mounted) setState(() => _isExporting = false);
        await Printing.sharePdf(bytes: pdfBytes, filename: filename);
      } else {
        final content = await _generateCsv(type, libraryId);
        final filename = 'SILENCE_${type}_export_${startFmt}_to_$endFmt.csv';
        if (mounted) setState(() => _isExporting = false);
        await Share.share(
          content,
          subject: filename,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<String> _generateCsv(String type, String libraryId) async {
    switch (type) {
      case 'members':
        return await _membersCsv(libraryId);
      case 'attendance':
        return await _attendanceCsv(libraryId);
      case 'payments':
        return await _paymentsCsv(libraryId);
      case 'revenue':
        return await _revenueCsv(libraryId);
      case 'occupancy':
        return await _occupancyCsv(libraryId);
      case 'dues':
        return await _duesCsv(libraryId);
      case 'expiry':
        return await _expiryCsv(libraryId);
      default:
        throw 'Invalid export type';
    }
  }

  Future<Uint8List> _generatePdfReport(String type, String libraryId) async {
    final startFmt = DateFormat('dd MMM yyyy').format(_startDate);
    final endFmt = DateFormat('dd MMM yyyy').format(_endDate);
    final reportTitle = type.toUpperCase().replaceAll('_', ' ');
    final dateStr = DateFormat('dd MMM yyyy HH:mm').format(DateTime.now());

    final libData = await _supabase.from('libraries').select('name').eq('id', libraryId).maybeSingle();
    final libraryName = libData?['name'] ?? 'SILENCE Space';

    List<String> tableHeaders = [];
    List<List<String>> tableRows = [];
    String? summaryText;

    switch (type) {
      case 'members':
        final list = await _fetchMembers(libraryId);
        tableHeaders = ['Name', 'Phone', 'Seat', 'Plan', 'Expiry', 'Status'];
        tableRows = list.map((r) => [
          r['name'].toString(),
          r['phone'].toString(),
          r['seat'].toString(),
          r['plan'].toString(),
          r['expiry'].toString(),
          r['status'].toString(),
        ]).toList();
        break;

      case 'attendance':
        final list = await _fetchAttendance(libraryId);
        tableHeaders = ['Member Name', 'Seat', 'Check-In', 'Check-Out'];
        tableRows = list.map((r) => [
          r['name'].toString(),
          r['seat'].toString(),
          r['in'].toString(),
          r['out'].toString(),
        ]).toList();
        break;

      case 'payments':
        final list = await _fetchPayments(libraryId);
        tableHeaders = ['Member Name', 'Amount', 'Method', 'Date', 'Status'];
        tableRows = list.map((r) => [
          r['name'].toString(),
          'Rs. ${r['amount']}',
          r['method'].toString(),
          r['date'].toString(),
          r['status'].toString(),
        ]).toList();
        break;

      case 'revenue':
        final map = await _fetchRevenue(libraryId);
        tableHeaders = ['Date', 'Total Collection', 'Cash Split', 'UPI Split'];
        double totalRev = 0;
        tableRows = map.entries.map((entry) {
          final amt = entry.value['total'] ?? 0;
          totalRev += amt;
          return [
            entry.key,
            'Rs. ${amt.toStringAsFixed(0)}',
            'Rs. ${(entry.value['cash'] ?? 0).toStringAsFixed(0)}',
            'Rs. ${(entry.value['upi'] ?? 0).toStringAsFixed(0)}'
          ];
        }).toList();
        summaryText = 'TOTAL REVENUE COLLECTED: Rs. ${totalRev.toStringAsFixed(0)}';
        break;

      case 'occupancy':
        final map = await _fetchOccupancy(libraryId);
        tableHeaders = ['Shift Name', 'Total Seats', 'Occupied Seats', 'Occupancy %'];
        tableRows = map.entries.map((entry) {
          final total = entry.value[0];
          final occupied = entry.value[1];
          final pct = total == 0 ? '0.0%' : '${((occupied / total) * 100).toStringAsFixed(1)}%';
          return [entry.key, total.toString(), occupied.toString(), pct];
        }).toList();
        break;

      case 'dues':
        final list = await _fetchDues(libraryId);
        tableHeaders = ['Member Name', 'Phone', 'Due Amount', 'Due Date'];
        double totalDues = 0;
        tableRows = list.map((r) {
          totalDues += r['amount'];
          return [
            r['name'].toString(),
            r['phone'].toString(),
            'Rs. ${r['amount'].toStringAsFixed(0)}',
            r['date'].toString(),
          ];
        }).toList();
        summaryText = 'TOTAL OUTSTANDING DUES: Rs. ${totalDues.toStringAsFixed(0)}';
        break;

      case 'expiry':
        final list = await _fetchExpiry(libraryId);
        tableHeaders = ['Member Name', 'Phone', 'Seat', 'Expiry Date'];
        tableRows = list.map((r) => [
          r['name'].toString(),
          r['phone'].toString(),
          r['seat'].toString(),
          r['expiry'].toString(),
        ]).toList();
        break;
      default:
        throw 'Invalid export type';
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return [
            // Title Header with App Branding
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'SILENCE – $reportTitle',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#E65C00'),
                  ),
                ),
                pw.Text(
                  libraryName,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#1E293B'),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(color: PdfColor.fromHex('#E65C00'), thickness: 1.5),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Date Range: $startFmt to $endFmt',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                ),
                pw.Text(
                  'Generated on: $dateStr',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            // Report Table
            if (tableRows.isEmpty)
              pw.Center(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.all(20),
                  child: pw.Text(
                    'No data available for the selected range.',
                    style: pw.TextStyle(fontStyle: pw.FontStyle.italic, color: PdfColors.grey500),
                  ),
                ),
              )
            else
              pw.TableHelper.fromTextArray(
                headers: tableHeaders,
                data: tableRows,
                border: const pw.TableBorder(
                  horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                  top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
                headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#E65C00')),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignment: pw.Alignment.centerLeft,
                headerAlignment: pw.Alignment.centerLeft,
                cellHeight: 24,
              ),
            if (summaryText != null) ...[
              pw.SizedBox(height: 16),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  summaryText,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColor.fromHex('#E65C00')),
                ),
              ),
            ],
          ];
        },
        footer: (context) {
          return pw.Column(
            children: [
              pw.Divider(color: PdfColors.grey300, thickness: 0.5),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'SILENCE Silent Study Spaces – Premium Library Management',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                  ),
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  // ----------------------------------------------------
  // DATA FETCHING & FORMATTING HELPERS
  // ----------------------------------------------------
  Future<List<Map<String, dynamic>>> _fetchMembers(String libraryId) async {
    final rows = await _supabase
        .from('memberships')
        .select('plan_type, end_date, status, member_id(full_name, phone), seats(seat_label)')
        .eq('library_id', libraryId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final member = row['member_id'] is Map ? row['member_id'] as Map : {};
      final seat = row['seats'] is Map ? row['seats'] as Map : {};
      return {
        'name': member['full_name']?.toString() ?? 'N/A',
        'phone': member['phone']?.toString() ?? 'N/A',
        'seat': seat['seat_label']?.toString() ?? 'N/A',
        'plan': row['plan_type']?.toString() ?? 'N/A',
        'expiry': row['end_date']?.toString() ?? 'N/A',
        'status': row['status']?.toString() ?? 'N/A',
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchAttendance(String libraryId) async {
    final rows = await _supabase
        .from('attendance')
        .select('check_in_time, check_out_time, member_id(full_name), memberships(seats(seat_label))')
        .eq('library_id', libraryId)
        .gte('check_in_time', _startDate.toIso8601String())
        .lte('check_in_time', DateTime(_endDate.year, _endDate.month, _endDate.day + 1).toIso8601String())
        .order('check_in_time', ascending: false);

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final member = row['member_id'] is Map ? row['member_id'] as Map : {};
      final membership = row['memberships'] is Map ? row['memberships'] as Map : {};
      final seat = membership['seats'] is Map ? membership['seats'] as Map : {};
      
      final inT = row['check_in_time'] != null ? DateFormat('dd MMM HH:mm').format(DateTime.parse(row['check_in_time'])) : 'N/A';
      final outT = row['check_out_time'] != null ? DateFormat('dd MMM HH:mm').format(DateTime.parse(row['check_out_time'])) : 'Active';

      return {
        'name': member['full_name']?.toString() ?? 'N/A',
        'seat': seat['seat_label']?.toString() ?? 'N/A',
        'in': inT,
        'out': outT,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchPayments(String libraryId) async {
    final rows = await _supabase
        .from('payments')
        .select('amount, method, payment_date, status, member_id(full_name)')
        .eq('library_id', libraryId)
        .gte('payment_date', _startDate.toIso8601String())
        .lte('payment_date', DateTime(_endDate.year, _endDate.month, _endDate.day + 1).toIso8601String())
        .order('payment_date', ascending: false);

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final member = row['member_id'] is Map ? row['member_id'] as Map : {};
      final date = row['payment_date'] != null ? DateFormat('dd MMM yyyy').format(DateTime.parse(row['payment_date'])) : 'N/A';
      return {
        'name': member['full_name']?.toString() ?? 'N/A',
        'amount': (row['amount'] as num?)?.toDouble() ?? 0.0,
        'method': row['method']?.toString() ?? 'N/A',
        'date': date,
        'status': row['status']?.toString() ?? 'N/A',
      };
    }).toList();
  }

  Future<Map<String, Map<String, num>>> _fetchRevenue(String libraryId) async {
    final rows = await _supabase
        .from('payments')
        .select('amount, method, payment_date')
        .eq('library_id', libraryId)
        .eq('status', 'confirmed')
        .gte('payment_date', _startDate.toIso8601String())
        .lte('payment_date', DateTime(_endDate.year, _endDate.month, _endDate.day + 1).toIso8601String());

    final totals = <String, Map<String, num>>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final date = (row['payment_date'] ?? '').toString().split('T').first;
      final amount = row['amount'] is num ? row['amount'] as num : 0;
      final method = (row['method'] ?? '').toString().toLowerCase();
      totals.putIfAbsent(date, () => {'total': 0, 'cash': 0, 'upi': 0});
      totals[date]!['total'] = totals[date]!['total']! + amount;
      final bucket = method == 'cash' ? 'cash' : 'upi';
      totals[date]![bucket] = totals[date]![bucket]! + amount;
    }
    return totals;
  }

  Future<Map<String, List<int>>> _fetchOccupancy(String libraryId) async {
    final rows = await _supabase
        .from('seats')
        .select('status, shifts(name)')
        .eq('library_id', libraryId);

    final totals = <String, List<int>>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final shift = row['shifts'] is Map ? row['shifts'] as Map : {};
      final name = (shift['name'] ?? 'General Shift').toString();
      totals.putIfAbsent(name, () => [0, 0]);
      totals[name]![0]++;
      if (row['status'] == 'occupied') totals[name]![1]++;
    }
    return totals;
  }

  Future<List<Map<String, dynamic>>> _fetchDues(String libraryId) async {
    final rows = await _supabase
        .from('payments')
        .select('amount, payment_date, member_id(full_name, phone)')
        .eq('library_id', libraryId)
        .eq('status', 'pending')
        .order('payment_date', ascending: false);

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final member = row['member_id'] is Map ? row['member_id'] as Map : {};
      final date = row['payment_date'] != null ? DateFormat('dd MMM yyyy').format(DateTime.parse(row['payment_date'])) : 'N/A';
      return {
        'name': member['full_name']?.toString() ?? 'N/A',
        'phone': member['phone']?.toString() ?? 'N/A',
        'amount': (row['amount'] as num?)?.toDouble() ?? 0.0,
        'date': date,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchExpiry(String libraryId) async {
    final startFmt = DateFormat('yyyy-MM-dd').format(_startDate);
    final endFmt = DateFormat('yyyy-MM-dd').format(_endDate);
    
    final rows = await _supabase
        .from('memberships')
        .select('end_date, member_id(full_name, phone), seats(seat_label)')
        .eq('library_id', libraryId)
        .gte('end_date', startFmt)
        .lte('end_date', endFmt)
        .order('end_date', ascending: true);

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final member = row['member_id'] is Map ? row['member_id'] as Map : {};
      final seat = row['seats'] is Map ? row['seats'] as Map : {};
      return {
        'name': member['full_name']?.toString() ?? 'N/A',
        'phone': member['phone']?.toString() ?? 'N/A',
        'seat': seat['seat_label']?.toString() ?? 'N/A',
        'expiry': row['end_date']?.toString() ?? 'N/A',
      };
    }).toList();
  }

  // ----------------------------------------------------
  // CSV GENERATION METHODS
  // ----------------------------------------------------
  Future<String> _membersCsv(String libraryId) async {
    final list = await _fetchMembers(libraryId);
    final buffer = StringBuffer('Name,Phone,Seat,Plan Type,Expiry Date,Status\n');
    for (final r in list) {
      buffer.writeln([
        r['name'],
        r['phone'],
        r['seat'],
        r['plan'],
        r['expiry'],
        r['status'],
      ].map(_csv).join(','));
    }
    return buffer.toString();
  }

  Future<String> _attendanceCsv(String libraryId) async {
    final list = await _fetchAttendance(libraryId);
    final buffer = StringBuffer('Member Name,Seat Label,Check-in Time,Check-out Time\n');
    for (final r in list) {
      buffer.writeln([
        r['name'],
        r['seat'],
        r['in'],
        r['out'],
      ].map(_csv).join(','));
    }
    return buffer.toString();
  }

  Future<String> _paymentsCsv(String libraryId) async {
    final list = await _fetchPayments(libraryId);
    final buffer = StringBuffer('Member Name,Amount,Method,Date,Status\n');
    for (final r in list) {
      buffer.writeln([
        r['name'],
        r['amount'],
        r['method'],
        r['date'],
        r['status'],
      ].map(_csv).join(','));
    }
    return buffer.toString();
  }

  Future<String> _revenueCsv(String libraryId) async {
    final map = await _fetchRevenue(libraryId);
    final buffer = StringBuffer('Date,Total Collections,Cash Split,UPI Split\n');
    for (final entry in map.entries) {
      buffer.writeln([
        entry.key,
        entry.value['total'],
        entry.value['cash'],
        entry.value['upi'],
      ].map(_csv).join(','));
    }
    return buffer.toString();
  }

  Future<String> _occupancyCsv(String libraryId) async {
    final map = await _fetchOccupancy(libraryId);
    final buffer = StringBuffer('Shift,Total Seats,Occupied Seats,Occupancy %\n');
    for (final entry in map.entries) {
      final total = entry.value[0];
      final occupied = entry.value[1];
      final pct = total == 0 ? '0.0%' : '${((occupied / total) * 100).toStringAsFixed(1)}%';
      buffer.writeln([entry.key, total, occupied, pct].map(_csv).join(','));
    }
    return buffer.toString();
  }

  Future<String> _duesCsv(String libraryId) async {
    final list = await _fetchDues(libraryId);
    final buffer = StringBuffer('Member Name,Phone,Due Amount,Due Date\n');
    for (final r in list) {
      buffer.writeln([
        r['name'],
        r['phone'],
        r['amount'],
        r['date'],
      ].map(_csv).join(','));
    }
    return buffer.toString();
  }

  Future<String> _expiryCsv(String libraryId) async {
    final list = await _fetchExpiry(libraryId);
    final buffer = StringBuffer('Member Name,Phone,Seat,Expiry Date\n');
    for (final r in list) {
      buffer.writeln([
        r['name'],
        r['phone'],
        r['seat'],
        r['expiry'],
      ].map(_csv).join(','));
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy');
    return AppGradientScaffold(
      title: 'Exports & Reports Center',
      body: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Preset Chips & Date Range selector Row
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            _buildPresetChip('Today'),
                            const SizedBox(width: 8),
                            _buildPresetChip('This Week'),
                            const SizedBox(width: 8),
                            _buildPresetChip('This Month'),
                            const SizedBox(width: 8),
                            _buildPresetChip('Custom'),
                          ],
                        ),
                        if (_selectedPreset == 'Custom') ...[
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () => _selectDateRange(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${df.format(_startDate)} - ${df.format(_endDate)}',
                                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B), fontWeight: FontWeight.w600),
                                  ),
                                  const Icon(Icons.edit_calendar_outlined, size: 18, color: Color(0xFFE65C00)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => Future.delayed(const Duration(milliseconds: 500)),
                      color: const Color(0xFFE65C00),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                        _buildExportCard(
                          title: 'Members Roster',
                          description: 'Active & registered member details, seats, and expiry dates.',
                          icon: Icons.people_alt_outlined,
                          type: 'members',
                        ),
                        _buildExportCard(
                          title: 'Attendance Log',
                          description: 'In/out check-in histories during the selected date range.',
                          icon: Icons.fact_check_outlined,
                          type: 'attendance',
                        ),
                        _buildExportCard(
                          title: 'Payment Register',
                          description: 'Transactional payment histories and collection status details.',
                          icon: Icons.payments_outlined,
                          type: 'payments',
                        ),
                        _buildExportCard(
                          title: 'Revenue Collections',
                          description: 'Confirmed revenue receipts split by cash & UPI methods.',
                          icon: Icons.trending_up,
                          type: 'revenue',
                        ),
                        _buildExportCard(
                          title: 'Occupancy Summary',
                          description: 'Seat usage summaries broken down by shifts and layout rules.',
                          icon: Icons.event_seat_outlined,
                          type: 'occupancy',
                        ),
                        _buildExportCard(
                          title: 'Outstanding Dues',
                          description: 'Roster of members with pending or requested dues.',
                          icon: Icons.money_off,
                          type: 'dues',
                        ),
                        _buildExportCard(
                          title: 'Upcoming Expirations',
                          description: 'Members whose subscriptions are expiring in the selected range.',
                          icon: Icons.hourglass_empty,
                          type: 'expiry',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

              // Full Screen compiling overlay
              if (_isExporting)
                Container(
                  color: Colors.black.withValues(alpha: 0.4),
                  child: Center(
                    child: Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(color: Color(0xFFE65C00)),
                            const SizedBox(height: 16),
                            Text(
                              'Compiling Report...',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Aggregating database tables',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
    );
  }

  Widget _buildPresetChip(String preset) {
    final isSelected = _selectedPreset == preset;
    return Expanded(
      child: ChoiceChip(
        label: Text(
          preset,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
        selected: isSelected,
        selectedColor: const Color(0xFFE65C00),
        backgroundColor: const Color(0xFFF1F5F9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onSelected: (selected) {
          if (selected) {
            if (preset == 'Custom') {
              _selectDateRange();
            } else {
              _applyPreset(preset);
            }
          }
        },
      ),
    );
  }

  Widget _buildExportCard({
    required String title,
    required String description,
    required IconData icon,
    required String type,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3ED),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFFE65C00), size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _exportData(type, title, false),
                  icon: const Icon(Icons.table_chart_outlined, size: 16),
                  label: Text('CSV', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE65C00),
                    side: const BorderSide(color: Color(0xFFE65C00)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _exportData(type, title, true),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 16, color: Colors.white),
                  label: Text('PDF', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
