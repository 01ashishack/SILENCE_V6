import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/calendar_picker.dart';
import '../core/active_library_store.dart';
import '../utils/pdf_exporter.dart';
import '../utils/csv_exporter.dart';
import '../widgets/app_gradient_scaffold.dart';
import 'reports/attendance_export_preview.dart';

/// Admin "Exports & Reports Center".
///
/// Thin screen: it owns the date-range UI and the data queries, then hands the
/// shaped rows to the single shared [PdfExporter] / [CsvExporter] engines so the
/// output matches every other export in the app (no second formatting code path).
class ExportCenterScreen extends StatefulWidget {
  const ExportCenterScreen({super.key});

  @override
  State<ExportCenterScreen> createState() => _ExportCenterScreenState();
}

class _ExportCenterScreenState extends State<ExportCenterScreen> {
  final _supabase = Supabase.instance.client;
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();
  bool _isExporting = false;

  void _applyPresetRange(String preset) {
    final now = DateTime.now();
    if (preset == 'Today') {
      _startDate = DateTime(now.year, now.month, now.day);
      _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else if (preset == 'This Week') {
      final start = now.subtract(Duration(days: now.weekday - 1));
      _startDate = DateTime(start.year, start.month, start.day);
      _endDate = now;
    } else {
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = now;
    }
  }

  Future<bool> _pickCustomRange() async {
    final lastAllowed = DateTime.now().add(const Duration(days: 365));
    final start = await showCalendarGridBottomSheet(context, initialDate: _startDate, firstDate: DateTime(2024), lastDate: lastAllowed);
    if (!mounted || start == null) return false;
    final end = await showCalendarGridBottomSheet(context, initialDate: _endDate.isBefore(start) ? start : _endDate, firstDate: start, lastDate: lastAllowed);
    if (!mounted || end == null) return false;
    _startDate = start;
    _endDate = end.isBefore(start) ? start : end;
    return true;
  }

  /// Asks which period to export, then runs the export for that range.
  Future<void> _chooseRangeAndExport(String type, bool isPdf) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(children: [
                Expanded(child: Text('Export period', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold))),
                Text(isPdf ? 'PDF' : 'CSV', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
              ]),
            ),
            ...['Today', 'This Week', 'This Month', 'Custom Range'].map((o) => ListTile(
                  leading: Icon(o == 'Custom Range' ? Icons.edit_calendar_outlined : Icons.date_range_outlined, color: const Color(0xFFE65C00)),
                  title: Text(o, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(ctx, o),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'Custom Range') {
      final ok = await _pickCustomRange();
      if (!ok) return;
    } else {
      _applyPresetRange(choice);
    }
    await _exportData(type, isPdf);
  }

  /// Attendance Log → the full preview screen (date-wise / member-wise).
  Future<void> _openAttendanceLog(AttendanceExportMode mode) async {
    setState(() => _isExporting = true);
    try {
      final libraryId = await _firstOwnedLibraryId();
      if (libraryId == null) throw 'No library found for this admin.';
      final (libName, libAddr) = await _libraryMeta(libraryId);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AttendanceExportPreviewScreen(
            libraryId: libraryId,
            libraryName: libName,
            libraryAddress: libAddr,
            mode: mode,
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  String get _periodLabel {
    final df = DateFormat('dd MMM yyyy');
    return '${df.format(_startDate)} – ${df.format(_endDate)}';
  }

  DateTime get _rangeStart => DateTime(_startDate.year, _startDate.month, _startDate.day);
  DateTime get _rangeEndExclusive => DateTime(_endDate.year, _endDate.month, _endDate.day + 1);

  Future<String?> _firstOwnedLibraryId() async {
    // Prefer the admin's active (persisted) library over an arbitrary first.
    return ActiveLibraryStore.resolve(null);
  }

  Future<(String, String)> _libraryMeta(String libraryId) async {
    final r = await _supabase
        .from('libraries')
        .select('name, address_street, address_city, address_state')
        .eq('id', libraryId)
        .maybeSingle();
    final name = (r?['name'] ?? 'SILENCE Space').toString();
    final addr = [r?['address_street'], r?['address_city'], r?['address_state']]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .join(', ');
    return (name, addr);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // EXPORT DISPATCH — fetch raw rows, hand to the shared engines.
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _exportData(String type, bool isPdf) async {
    setState(() => _isExporting = true);
    try {
      final libraryId = await _firstOwnedLibraryId();
      if (libraryId == null) throw 'No library found for this admin.';
      final (libName, libAddr) = await _libraryMeta(libraryId);
      final period = _periodLabel;

      switch (type) {
        case 'members':
          final rows = await _fetchMembers(libraryId);
          isPdf
              ? await PdfExporter.exportMembers(libraryName: libName, libraryAddress: libAddr, members: rows, dateRange: period)
              : await CsvExporter.exportMembers(libraryName: libName, members: rows, period: period);
          break;
        case 'attendance':
          final rows = await _fetchAttendance(libraryId);
          isPdf
              ? await PdfExporter.exportAttendance(libraryName: libName, libraryAddress: libAddr, dateRange: period, logs: rows)
              : await CsvExporter.exportAttendance(libraryName: libName, logs: rows, period: period);
          break;
        case 'payments':
          final rows = await _fetchPayments(libraryId);
          isPdf
              ? await PdfExporter.exportPayments(libraryName: libName, libraryAddress: libAddr, dateRange: period, payments: rows)
              : await CsvExporter.exportPayments(libraryName: libName, payments: rows, period: period);
          break;
        case 'revenue':
          final rows = await _fetchRevenue(libraryId);
          isPdf
              ? await PdfExporter.exportRevenueSummary(libraryName: libName, libraryAddress: libAddr, dateRange: period, summary: rows)
              : await CsvExporter.exportRevenueSummary(libraryName: libName, summary: rows, period: period);
          break;
        case 'occupancy':
          final rows = await _fetchOccupancy(libraryId);
          isPdf
              ? await PdfExporter.exportOccupancy(libraryName: libName, libraryAddress: libAddr, reports: rows)
              : await CsvExporter.exportOccupancy(libraryName: libName, reports: rows);
          break;
        case 'dues':
          final rows = await _fetchDues(libraryId);
          isPdf
              ? await PdfExporter.exportDues(libraryName: libName, libraryAddress: libAddr, dues: rows, period: period)
              : await CsvExporter.exportDues(libraryName: libName, dues: rows, period: period);
          break;
        case 'expiry':
          final rows = await _fetchExpiry(libraryId);
          isPdf
              ? await PdfExporter.exportExpiringMembers(libraryName: libName, libraryAddress: libAddr, members: rows, period: period)
              : await CsvExporter.exportExpiringMembers(libraryName: libName, members: rows, period: period);
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // DATA FETCHERS — shaped to the keys the shared engines read.
  // ───────────────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchMembers(String libraryId) async {
    final rows = await _supabase
        .from('memberships')
        .select('plan_type, end_date, status, created_at, member_id(full_name, phone, email), seats(seat_label), shifts(name)')
        .eq('library_id', libraryId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final m = row['member_id'] is Map ? row['member_id'] as Map : {};
      return {
        'full_name': m['full_name'] ?? 'N/A',
        'phone': m['phone'] ?? '',
        'email': m['email'] ?? '',
        'seat_label': row['seats'] is Map ? row['seats']['seat_label'] : null,
        'shift_name': row['shifts'] is Map ? row['shifts']['name'] : null,
        'plan_type': row['plan_type'],
        'created_at': row['created_at'],
        'end_date': row['end_date'],
        'status': row['status'] ?? 'expired',
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchAttendance(String libraryId) async {
    final rows = await _supabase
        .from('attendance')
        .select('check_in_time, check_out_time, duration_minutes, session_type, is_overtime, '
            'member_id(full_name), memberships(seats(seat_label)), shifts(name)')
        .eq('library_id', libraryId)
        .gte('check_in_time', _rangeStart.toIso8601String())
        .lte('check_in_time', _rangeEndExclusive.toIso8601String())
        .order('check_in_time', ascending: false);

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final m = row['member_id'] is Map ? row['member_id'] as Map : {};
      final ms = row['memberships'] is Map ? row['memberships'] as Map : {};
      final seat = ms['seats'] is Map ? ms['seats'] as Map : {};
      return {
        'member_name': m['full_name'] ?? 'N/A',
        'seat_label': seat['seat_label'] ?? '',
        'shift_name': row['shifts'] is Map ? row['shifts']['name'] : '',
        'check_in_time': row['check_in_time'],
        'check_out_time': row['check_out_time'],
        'duration_minutes': row['duration_minutes'],
        'session_type': row['session_type'] ?? 'normal',
        'is_overtime': row['is_overtime'] == true,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchPayments(String libraryId) async {
    final rows = await _supabase
        .from('payments')
        .select('id, amount, method, payment_date, status, member_id(full_name)')
        .eq('library_id', libraryId)
        .gte('payment_date', _rangeStart.toIso8601String())
        .lte('payment_date', _rangeEndExclusive.toIso8601String())
        .order('payment_date', ascending: false);

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final m = row['member_id'] is Map ? row['member_id'] as Map : {};
      return {
        'id': row['id'],
        'member_name': m['full_name'] ?? 'N/A',
        'payment_date': row['payment_date'],
        'method': row['method'] ?? 'cash',
        'status': row['status'] ?? 'pending',
        'amount': row['amount'] ?? 0,
      };
    }).toList();
  }

  /// Confirmed revenue per day with cash/UPI split, merged with expenditures so
  /// the report is a real daily P&L.
  Future<List<Map<String, dynamic>>> _fetchRevenue(String libraryId) async {
    final payRows = await _supabase
        .from('payments')
        .select('amount, method, payment_date')
        .eq('library_id', libraryId)
        .eq('status', 'confirmed')
        .gte('payment_date', _rangeStart.toIso8601String())
        .lte('payment_date', _rangeEndExclusive.toIso8601String());

    final byDate = <String, Map<String, num>>{};
    for (final r in List<Map<String, dynamic>>.from(payRows)) {
      final date = (r['payment_date'] ?? '').toString().split('T').first;
      if (date.isEmpty) continue;
      final amt = (r['amount'] as num?) ?? 0;
      final method = (r['method'] ?? '').toString().toLowerCase();
      final e = byDate.putIfAbsent(date, () => {'revenue': 0, 'cash': 0, 'upi': 0, 'expenses': 0});
      e['revenue'] = e['revenue']! + amt;
      e[method == 'cash' ? 'cash' : 'upi'] = e[method == 'cash' ? 'cash' : 'upi']! + amt;
    }

    // Merge expenditures (best-effort — table may be empty).
    try {
      final expRows = await _supabase
          .from('expenditures')
          .select('amount, expense_date')
          .eq('library_id', libraryId)
          .gte('expense_date', _rangeStart.toIso8601String())
          .lte('expense_date', _rangeEndExclusive.toIso8601String());
      for (final r in List<Map<String, dynamic>>.from(expRows)) {
        final date = (r['expense_date'] ?? '').toString().split('T').first;
        if (date.isEmpty) continue;
        final amt = (r['amount'] as num?) ?? 0;
        final e = byDate.putIfAbsent(date, () => {'revenue': 0, 'cash': 0, 'upi': 0, 'expenses': 0});
        e['expenses'] = e['expenses']! + amt;
      }
    } catch (_) {/* expenditures optional */}

    final dates = byDate.keys.toList()..sort();
    return dates.map((d) {
      final e = byDate[d]!;
      final rev = e['revenue'] ?? 0;
      final exp = e['expenses'] ?? 0;
      return {
        'date': d,
        'revenue': rev,
        'cash': e['cash'] ?? 0,
        'upi': e['upi'] ?? 0,
        'expenses': exp,
        'net_profit': rev - exp,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchOccupancy(String libraryId) async {
    final rows = await _supabase
        .from('seats')
        .select('status, shifts(name)')
        .eq('library_id', libraryId);

    final byShift = <String, List<int>>{};
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final shift = r['shifts'] is Map ? r['shifts'] as Map : {};
      final name = (shift['name'] ?? 'General').toString();
      final e = byShift.putIfAbsent(name, () => [0, 0]);
      e[0]++;
      if (r['status'] == 'occupied') e[1]++;
    }
    return byShift.entries
        .map((e) => {'shift': e.key, 'total_seats': e.value[0], 'occupied_seats': e.value[1]})
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchDues(String libraryId) async {
    final rows = await _supabase
        .from('payments')
        .select('amount, payment_date, member_id(full_name, phone, email)')
        .eq('library_id', libraryId)
        .eq('status', 'pending')
        .order('payment_date', ascending: false);

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final m = row['member_id'] is Map ? row['member_id'] as Map : {};
      return {
        'member_name': m['full_name'] ?? 'N/A',
        'phone': m['phone'] ?? '',
        'email': m['email'] ?? '',
        'amount': row['amount'] ?? 0,
        'due_date': row['payment_date'],
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
      final m = row['member_id'] is Map ? row['member_id'] as Map : {};
      return {
        'member_name': m['full_name'] ?? 'N/A',
        'phone': m['phone'] ?? '',
        'seat': row['seats'] is Map ? row['seats']['seat_label'] : '',
        'end_date': row['end_date'],
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientScaffold(
      title: 'Exports & Reports Center',
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFE65C00)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Tap CSV or PDF on a report — you'll pick the date / month / range next.",
                        style: GoogleFonts.inter(fontSize: 12, color: context.palette.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _buildExportCard(
                      title: 'Members Roster',
                      description: 'Member details with seat, shift, plan and validity.',
                      icon: Icons.people_alt_outlined,
                      type: 'members',
                    ),
                    _buildExportCard(
                      title: 'Attendance Log',
                      description: 'Check-in/out history with duration and overtime for the range.',
                      icon: Icons.fact_check_outlined,
                      type: 'attendance',
                    ),
                    _buildExportCard(
                      title: 'Payment Register',
                      description: 'Transactions with collected vs pending totals.',
                      icon: Icons.payments_outlined,
                      type: 'payments',
                    ),
                    _buildExportCard(
                      title: 'Revenue & Expenses',
                      description: 'Daily P&L: revenue split by cash/UPI, net of expenses.',
                      icon: Icons.trending_up,
                      type: 'revenue',
                    ),
                    _buildExportCard(
                      title: 'Occupancy Snapshot',
                      description: 'Current seat usage by shift (live snapshot, not date-ranged).',
                      icon: Icons.event_seat_outlined,
                      type: 'occupancy',
                    ),
                    _buildExportCard(
                      title: 'Outstanding Dues',
                      description: 'Members with pending payments and the total outstanding.',
                      icon: Icons.money_off,
                      type: 'dues',
                    ),
                    _buildExportCard(
                      title: 'Upcoming Expirations',
                      description: 'Memberships expiring within the selected range.',
                      icon: Icons.hourglass_empty,
                      type: 'expiry',
                    ),
                  ],
                ),
              ),
            ],
          ),
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
                        Text('Compiling Report...', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('Aggregating database tables', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500])),
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
        color: context.palette.surface,
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
                    Text(title, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
                    const SizedBox(height: 4),
                    Text(description, style: GoogleFonts.inter(fontSize: 12, color: context.palette.textMuted, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),
          if (type == 'attendance')
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isExporting ? null : () => _openAttendanceLog(AttendanceExportMode.dateWise),
                    icon: const Icon(Icons.event_outlined, size: 16),
                    label: Text('Date-wise', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12.5)),
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
                    onPressed: _isExporting ? null : () => _openAttendanceLog(AttendanceExportMode.memberWise),
                    icon: const Icon(Icons.groups_outlined, size: 16, color: Colors.white),
                    label: Text('Member-wise', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isExporting ? null : () => _chooseRangeAndExport(type, false),
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
                    onPressed: _isExporting ? null : () => _chooseRangeAndExport(type, true),
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
