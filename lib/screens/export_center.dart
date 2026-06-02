import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
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

  Future<void> _triggerCSVExport(String type, String title) async {
    setState(() => _isExporting = true);
    final startFmt = DateFormat('yyyy-MM-dd').format(_startDate);
    final endFmt = DateFormat('yyyy-MM-dd').format(_endDate);

    try {
      final libraryId = await _firstOwnedLibraryId();
      if (libraryId == null) throw 'No library found for this admin.';

      final csvData = switch (type) {
        'members' => await _membersCsv(libraryId),
        'attendance' => await _attendanceCsv(libraryId),
        'payments' => await _paymentsCsv(libraryId),
        'revenue' => await _revenueCsv(libraryId),
        _ => await _occupancyCsv(libraryId),
      };

      if (mounted) setState(() => _isExporting = false);
      await Share.share(
        csvData,
        subject: 'SILENCE_${type}_export_${startFmt}_to_${endFmt}.csv',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<String> _membersCsv(String libraryId) async {
    final rows = await _supabase
        .from('memberships')
        .select('id, plan_type, end_date, status, member_id(full_name, phone, email), seats(seat_label), shifts(name)')
        .eq('library_id', libraryId)
        .order('created_at', ascending: false);
    final buffer = StringBuffer('Membership ID,Full Name,Phone,Email,Seat,Shift,Plan Type,Expiry Date,Status\n');
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final member = row['member_id'] is Map ? row['member_id'] as Map : {};
      final seat = row['seats'] is Map ? row['seats'] as Map : {};
      final shift = row['shifts'] is Map ? row['shifts'] as Map : {};
      buffer.writeln([
        row['id'],
        member['full_name'],
        member['phone'],
        member['email'],
        seat['seat_label'],
        shift['name'],
        row['plan_type'],
        row['end_date'],
        row['status'],
      ].map(_csv).join(','));
    }
    return buffer.toString();
  }

  Future<String> _attendanceCsv(String libraryId) async {
    final rows = await _supabase
        .from('attendance')
        .select('id, check_in_time, check_out_time, member_id(full_name), memberships(seats(seat_label))')
        .eq('library_id', libraryId)
        .gte('check_in_time', _startDate.toIso8601String())
        .lte('check_in_time', DateTime(_endDate.year, _endDate.month, _endDate.day + 1).toIso8601String())
        .order('check_in_time', ascending: false);
    final buffer = StringBuffer('Log ID,Member Name,Seat Label,Check-in Time,Check-out Time,Status\n');
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final member = row['member_id'] is Map ? row['member_id'] as Map : {};
      final membership = row['memberships'] is Map ? row['memberships'] as Map : {};
      final seat = membership['seats'] is Map ? membership['seats'] as Map : {};
      buffer.writeln([
        row['id'],
        member['full_name'],
        seat['seat_label'],
        row['check_in_time'],
        row['check_out_time'],
        row['check_out_time'] == null ? 'Checked In' : 'Completed',
      ].map(_csv).join(','));
    }
    return buffer.toString();
  }

  Future<String> _paymentsCsv(String libraryId) async {
    final rows = await _supabase
        .from('payments')
        .select('id, amount, method, payment_date, status, member_id(full_name)')
        .eq('library_id', libraryId)
        .gte('payment_date', _startDate.toIso8601String())
        .lte('payment_date', DateTime(_endDate.year, _endDate.month, _endDate.day + 1).toIso8601String())
        .order('payment_date', ascending: false);
    final buffer = StringBuffer('Transaction ID,Member Name,Amount,Method,Date,Status\n');
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final member = row['member_id'] is Map ? row['member_id'] as Map : {};
      buffer.writeln([
        row['id'],
        member['full_name'],
        row['amount'],
        row['method'],
        row['payment_date'],
        row['status'],
      ].map(_csv).join(','));
    }
    return buffer.toString();
  }

  Future<String> _revenueCsv(String libraryId) async {
    final rows = await _supabase
        .from('payments')
        .select('amount, method, payment_date, status')
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
    final buffer = StringBuffer('Date,Total Collections,Cash Split,UPI Split\n');
    for (final entry in totals.entries) {
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
    final rows = await _supabase
        .from('seats')
        .select('status, shifts(name)')
        .eq('library_id', libraryId);
    final totals = <String, List<int>>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final shift = row['shifts'] is Map ? row['shifts'] as Map : {};
      final name = (shift['name'] ?? 'All Shifts').toString();
      totals.putIfAbsent(name, () => [0, 0]);
      totals[name]![0]++;
      if (row['status'] == 'occupied') totals[name]![1]++;
    }
    final buffer = StringBuffer('Shift,Total Seats,Occupied Seats,Occupancy %\n');
    for (final entry in totals.entries) {
      final total = entry.value[0];
      final occupied = entry.value[1];
      final pct = total == 0 ? '0' : ((occupied / total) * 100).toStringAsFixed(1);
      buffer.writeln([entry.key, total, occupied, pct].map(_csv).join(','));
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy');
    return Scaffold(
      backgroundColor: const Color(0xFFE65C00),
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: const Color(0xFFFBF5EE),
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Exports & Reports Center',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          body: _isExporting
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFE65C00)),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _selectDateRange(context),
                        icon: const Icon(Icons.date_range, color: Color(0xFFE65C00)),
                        label: Text(
                          '${df.format(_startDate)} - ${df.format(_endDate)}',
                          style: GoogleFonts.inter(
                            color: const Color(0xFFE65C00),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildExportCard('Members', 'Member roster with plans and seats', Icons.people_alt_outlined, 'members'),
                      _buildExportCard('Attendance', 'Attendance logs for the selected date range', Icons.fact_check_outlined, 'attendance'),
                      _buildExportCard('Payments', 'Payment transactions and statuses', Icons.payments_outlined, 'payments'),
                      _buildExportCard('Revenue', 'Daily confirmed collection summary', Icons.trending_up, 'revenue'),
                      _buildExportCard('Occupancy', 'Current seat occupancy by shift', Icons.event_seat_outlined, 'occupancy'),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildExportCard(String title, String subtitle, IconData icon, String type) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFE65C00)),
        title: Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: GoogleFonts.inter(fontSize: 12)),
        trailing: const Icon(Icons.ios_share, color: Color(0xFFE65C00)),
        onTap: () => _triggerCSVExport(type, title),
      ),
    );
  }
}
