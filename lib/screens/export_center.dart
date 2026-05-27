import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class ExportCenterScreen extends StatefulWidget {
  const ExportCenterScreen({super.key});

  @override
  State<ExportCenterScreen> createState() => _ExportCenterScreenState();
}

class _ExportCenterScreenState extends State<ExportCenterScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  bool _isExporting = false;

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
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
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _triggerCSVExport(String type, String title) async {
    setState(() => _isExporting = true);
    await Future.delayed(const Duration(milliseconds: 1500)); // Simulated processing
    
    // Generate beautiful mock CSV content
    String csvData = '';
    final startFmt = DateFormat('yyyy-MM-dd').format(_startDate);
    final endFmt = DateFormat('yyyy-MM-dd').format(_endDate);

    if (type == 'members') {
      csvData = 'Member ID,Full Name,Phone,Email,Plan Type,Expiry Date,Status\n'
          'MEM001,Ashish Kumar,+91 9876543210,ashish@example.com,Monthly,2026-06-25,Active\n'
          'MEM002,Rahul Sharma,+91 8765432109,rahul@example.com,Quarterly,2026-08-14,Active\n'
          'MEM003,Priya Patel,+91 7654321098,priya@example.com,Weekly,2026-06-03,Active\n'
          'MEM004,Amit Singh,+91 6543210987,amit@example.com,Monthly,2026-05-20,Expired\n';
    } else if (type == 'attendance') {
      csvData = 'Log ID,Member Name,Seat Label,Check-in Time,Check-out Time,Status\n'
          'ATT901,Ashish Kumar,Desk A-12,2026-05-26 08:14:02,2026-05-26 15:42:11,Present\n'
          'ATT902,Rahul Sharma,Desk B-04,2026-05-26 09:02:44,2026-05-26 17:01:23,Present\n'
          'ATT903,Priya Patel,Desk A-02,2026-05-26 08:00:15,2026-05-26 14:15:30,Present\n';
    } else if (type == 'payments') {
      csvData = 'Transaction ID,Member Name,Amount,Method,Date,Status\n'
          'TXN801,Ashish Kumar,₹1199,UPI (GPay),2026-05-25 11:24:00,Successful\n'
          'TXN802,Rahul Sharma,₹2999,Cash,2026-05-14 10:15:00,Successful\n'
          'TXN803,Priya Patel,₹399,UPI (PhonePe),2026-05-27 16:30:11,Successful\n';
    } else if (type == 'revenue') {
      csvData = 'Date,Total Collections,Cash Split,UPI Split,Expenses,Net Profit\n'
          '2026-05-25,₹1598,₹400,₹1198,₹150,₹1448\n'
          '2026-05-26,₹2999,₹2999,₹0,₹0,₹2999\n'
          '2026-05-27,₹399,₹0,₹399,₹50,₹349\n';
    } else {
      csvData = 'Date,Morning Shift %,Day Shift %,Evening Shift %,Night Shift %,Aggregate Occupancy %\n'
          '2026-05-25,82%,44%,68%,21%,53.7%\n'
          '2026-05-26,85%,45%,71%,20%,55.2%\n'
          '2026-05-27,78%,42%,64%,22%,51.5%\n';
    }

    setState(() => _isExporting = false);

    // Share via share_plus sheet to allow saving anywhere
    await Share.share(
      csvData,
      subject: 'SILENCE_${type}_export_${startFmt}_to_${endFmt}.csv',
    );
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFE65C00)),
                      SizedBox(height: 16),
                      Text('Generating CSV report, please wait...', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE65C00))),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Date range filter card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Export Date Range Scope',
                              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('START DATE', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
                                    const SizedBox(height: 2),
                                    Text(
                                      df.format(_startDate),
                                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                                    ),
                                  ],
                                ),
                                const Icon(Icons.arrow_forward_outlined, color: Color(0xFF64748B), size: 18),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('END DATE', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
                                    const SizedBox(height: 2),
                                    Text(
                                      df.format(_endDate),
                                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFF3ED),
                                foregroundColor: const Color(0xFFE65C00),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => _selectDateRange(context),
                              icon: const Icon(Icons.calendar_month, size: 16),
                              label: Text('Change Date Scope', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 2. Export items options list
                      Text(
                        'Select Category to Export CSV',
                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 12),

                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            _buildExportRow('Members Directory list', 'Full member details, phone numbers, and plan status', 'members'),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildExportRow('Attendance Entry Ledger', 'Precise check-in, check-out details, and hours', 'attendance'),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildExportRow('Payment transactions list', 'Success/failed receipts and payment modes', 'payments'),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildExportRow('Total revenue & expenditure sheet', 'Date-wise revenue, split cash/UPI, expenditures', 'revenue'),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildExportRow('Occupancy percentage reports', 'Desk occupation trends split per shift session', 'occupancy'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildExportRow(String title, String subtitle, String type) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3ED),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.table_chart, color: Color(0xFFE65C00), size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2.0),
        child: Text(
          subtitle,
          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
        ),
      ),
      trailing: const Icon(Icons.share, size: 16, color: Color(0xFF94A3B8)),
      onTap: () => _triggerCSVExport(type, title),
    );
  }
}
