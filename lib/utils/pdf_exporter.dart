import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

import 'attendance_format.dart';

class PdfExporter {
  static Future<pw.MemoryImage?> _loadLogo() async {
    try {
      final logoBytes = await rootBundle.load('assets/images/horizontal app logo.png');
      return pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static Future<void> exportMembers({
    required String libraryName,
    required String libraryAddress,
    required List<Map<String, dynamic>> members,
  }) async {
    final pdf = pw.Document();
    final logo = await _loadLogo();
    final dateRange = DateFormat('dd MMM yyyy').format(DateTime.now());

    final data = members.map((m) {
      final name = m['full_name'] ?? 'N/A';
      final email = m['email'] ?? 'N/A';
      final phone = m['phone'] ?? 'N/A';
      final joined = m['created_at'] != null 
          ? DateFormat('dd MMM yyyy').format(DateTime.parse(m['created_at'])) 
          : 'N/A';
      final expiry = m['expiry_date'] != null 
          ? DateFormat('dd MMM yyyy').format(DateTime.parse(m['expiry_date'])) 
          : 'N/A';
      final status = (m['status'] ?? 'expired').toString().toUpperCase();

      return [name, email, phone, joined, expiry, status];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.only(top: 60, left: 40, right: 40, bottom: 50),
        header: (pw.Context context) => _buildHeader(context, libraryName, libraryAddress, 'MEMBERS DIRECTORY', dateRange, logo),
        footer: (pw.Context context) => _buildFooter(context, logo),
        build: (pw.Context context) => [
          _buildReportTitle('Registered Members Directory', 'Total Registered: ${members.length} members'),
          pw.SizedBox(height: 15),
          _buildTable(
            context: context,
            headers: ['Name', 'Email', 'Phone', 'Joined Date', 'Expiry Date', 'Status'],
            data: data,
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${libraryName.replaceAll(' ', '_')}_members_report.pdf',
    );
  }

  static Future<void> exportAttendance({
    required String libraryName,
    required String libraryAddress,
    required String dateRange,
    required List<Map<String, dynamic>> logs,
  }) async {
    final pdf = pw.Document();
    final logo = await _loadLogo();

    // Group logs by date
    final Map<String, List<Map<String, dynamic>>> groupedLogs = {};
    for (final l in logs) {
      final checkinStr = l['check_in_time'];
      final dateStr = checkinStr != null 
          ? DateFormat('yyyy-MM-dd').format(DateTime.parse(checkinStr)) 
          : 'Unknown Date';
      groupedLogs.putIfAbsent(dateStr, () => []);
      groupedLogs[dateStr]!.add(l);
    }

    // Sort dates in descending order
    final sortedDates = groupedLogs.keys.toList()..sort((a, b) => b.compareTo(a));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.only(top: 60, left: 40, right: 40, bottom: 50),
        header: (pw.Context context) => _buildHeader(context, libraryName, libraryAddress, 'ATTENDANCE LOG', dateRange, logo),
        footer: (pw.Context context) => _buildFooter(context, logo),
        build: (pw.Context context) {
          final List<pw.Widget> elements = [
            _buildReportTitle('Member Attendance Roster', 'Total Logs Recorded: ${logs.length}'),
            pw.SizedBox(height: 10),
          ];

          for (final date in sortedDates) {
            final dailyLogs = groupedLogs[date]!;
            final formattedDate = date != 'Unknown Date' 
                ? DateFormat('EEEE, dd MMM yyyy').format(DateTime.parse(date)) 
                : 'Unknown Date';

            elements.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
                padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFFFF3ED),
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  'Date: $formattedDate',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(0xFFC2410C),
                    fontSize: 10,
                  ),
                ),
              ),
            );

            final tableData = dailyLogs.map((l) {
              final name = l['member_name'] ?? 'N/A';
              final seat = l['seat_label'] ?? 'N/A';
              final checkinStr = l['check_in_time'];
              final checkoutStr = l['check_out_time'];
              final shift = l['shift_name'] ?? 'N/A';
              
              final checkin = checkinStr != null 
                  ? DateFormat('hh:mm a').format(DateTime.parse(checkinStr)) 
                  : 'N/A';
              final checkout = checkoutStr != null 
                  ? DateFormat('hh:mm a').format(DateTime.parse(checkoutStr)) 
                  : 'Ongoing';

              String duration = 'Ongoing';
              if (checkinStr != null && checkoutStr != null) {
                final ci = DateTime.parse(checkinStr);
                final co = DateTime.parse(checkoutStr);
                final diff = co.difference(ci);
                final hrs = diff.inHours;
                final mins = diff.inMinutes % 60;
                duration = '${hrs}h ${mins}m';
              }

              final typeLabel = attendanceTag(l['session_type']).label +
                  (l['is_overtime'] == true ? ' +OT' : '');
              return [name, seat, checkin, checkout, shift, duration, typeLabel];
            }).toList();

            elements.add(
              _buildTable(
                context: context,
                headers: ['Member Name', 'Seat', 'Check-In', 'Check-Out', 'Shift', 'Duration', 'Type'],
                data: tableData,
              ),
            );
          }

          return elements;
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${libraryName.replaceAll(' ', '_')}_attendance_report.pdf',
    );
  }

  static Future<void> exportPayments({
    required String libraryName,
    required String libraryAddress,
    required String dateRange,
    required List<Map<String, dynamic>> payments,
  }) async {
    final pdf = pw.Document();
    final logo = await _loadLogo();

    final data = payments.map((p) {
      final txId = (p['id'] ?? 'N/A').toString().split('-').first;
      final name = p['member_name'] ?? 'N/A';
      final dateStr = p['payment_date'] != null 
          ? DateFormat('dd MMM yyyy hh:mm a').format(DateTime.parse(p['payment_date'])) 
          : 'N/A';
      final amount = '₹${p['amount'] ?? 0}';
      final method = (p['method'] ?? 'cash').toString().toUpperCase();
      final status = (p['status'] ?? 'pending').toString().toUpperCase();

      return [txId, name, dateStr, amount, method, status];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.only(top: 60, left: 40, right: 40, bottom: 50),
        header: (pw.Context context) => _buildHeader(context, libraryName, libraryAddress, 'PAYMENT TRANSACTIONS', dateRange, logo),
        footer: (pw.Context context) => _buildFooter(context, logo),
        build: (pw.Context context) => [
          _buildReportTitle('Transaction Ledger', 'Total Confirmed / Pending Transactions: ${payments.length}'),
          pw.SizedBox(height: 15),
          _buildTable(
            context: context,
            headers: ['Tx ID', 'Member Name', 'Payment Date', 'Amount', 'Method', 'Status'],
            data: data,
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${libraryName.replaceAll(' ', '_')}_payments_report.pdf',
    );
  }

  static Future<void> exportRevenueSummary({
    required String libraryName,
    required String libraryAddress,
    required String dateRange,
    required List<Map<String, dynamic>> summary,
  }) async {
    final pdf = pw.Document();
    final logo = await _loadLogo();

    final data = summary.map((s) {
      final date = s['date'] ?? '';
      final rev = '₹${s['revenue'] ?? 0}';
      final exp = '₹${s['expenses'] ?? 0}';
      final net = '₹${s['net_profit'] ?? 0}';

      return [date, rev, exp, net];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.only(top: 60, left: 40, right: 40, bottom: 50),
        header: (pw.Context context) => _buildHeader(context, libraryName, libraryAddress, 'REVENUE & EXPENSES SUMMARY', dateRange, logo),
        footer: (pw.Context context) => _buildFooter(context, logo),
        build: (pw.Context context) => [
          _buildReportTitle('Daily Profit & Loss Ledger', 'Total Logged Periods: ${summary.length} days'),
          pw.SizedBox(height: 15),
          _buildTable(
            context: context,
            headers: ['Date', 'Collections (Revenue)', 'Expenditure (Expenses)', 'Net Profit / Loss'],
            data: data,
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${libraryName.replaceAll(' ', '_')}_revenue_report.pdf',
    );
  }

  static Future<void> exportOccupancy({
    required String libraryName,
    required String libraryAddress,
    required List<Map<String, dynamic>> reports,
  }) async {
    final pdf = pw.Document();
    final logo = await _loadLogo();
    final dateRange = DateFormat('dd MMM yyyy').format(DateTime.now());

    final data = reports.map((r) {
      final date = r['date'] ?? 'N/A';
      final total = (r['total_seats'] ?? 0).toString();
      final occupied = (r['occupied_seats'] ?? 0).toString();
      final rate = '${((r['rate'] ?? 0.0) * 100).toStringAsFixed(1)}%';

      return [date, total, occupied, rate];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.only(top: 60, left: 40, right: 40, bottom: 50),
        header: (pw.Context context) => _buildHeader(context, libraryName, libraryAddress, 'SEAT OCCUPANCY REPORT', dateRange, logo),
        footer: (pw.Context context) => _buildFooter(context, logo),
        build: (pw.Context context) => [
          _buildReportTitle('Shift-wise Seat Occupancy Statistics', 'Daily occupancy logs across shifts'),
          pw.SizedBox(height: 15),
          _buildTable(
            context: context,
            headers: ['Shift / Date', 'Total Desks', 'Occupied Desks', 'Occupancy Rate'],
            data: data,
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${libraryName.replaceAll(' ', '_')}_occupancy_report.pdf',
    );
  }

  static Future<void> exportDues({
    required String libraryName,
    required String libraryAddress,
    required List<Map<String, dynamic>> dues,
  }) async {
    final pdf = pw.Document();
    final logo = await _loadLogo();
    final dateRange = DateFormat('dd MMM yyyy').format(DateTime.now());

    final data = dues.map((d) {
      final name = d['member_name'] ?? 'N/A';
      final email = d['email'] ?? 'N/A';
      final phone = d['phone'] ?? 'N/A';
      final due = '₹${d['amount'] ?? 0}';
      final dueDate = d['due_date'] != null 
          ? DateFormat('dd MMM yyyy').format(DateTime.parse(d['due_date'])) 
          : 'N/A';

      return [name, email, phone, due, dueDate];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.only(top: 60, left: 40, right: 40, bottom: 50),
        header: (pw.Context context) => _buildHeader(context, libraryName, libraryAddress, 'OUTSTANDING DUES ROSTER', dateRange, logo),
        footer: (pw.Context context) => _buildFooter(context, logo),
        build: (pw.Context context) => [
          _buildReportTitle('Defaulters Directory', 'Total Outstanding Records: ${dues.length}'),
          pw.SizedBox(height: 15),
          _buildTable(
            context: context,
            headers: ['Member Name', 'Email', 'Phone Number', 'Due Amount', 'Expected Pay Date'],
            data: data,
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${libraryName.replaceAll(' ', '_')}_outstanding_dues.pdf',
    );
  }

  static pw.Widget _buildReceiptDetailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF64748B))),
          pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F172A))),
        ],
      ),
    );
  }

  static Future<void> exportPaymentReceipt({
    required String libraryName,
    required String libraryAddress,
    required Map<String, dynamic> payment,
    required String memberName,
  }) async {
    final pdf = pw.Document();
    final logo = await _loadLogo();
    final dateStr = payment['payment_date'] != null 
        ? DateFormat('dd MMM yyyy hh:mm a').format(DateTime.parse(payment['payment_date'])) 
        : 'N/A';
    final amount = '₹${payment['amount'] ?? 0}';
    final method = (payment['method'] ?? 'cash').toString().toUpperCase();
    final status = (payment['status'] ?? 'pending').toString().toUpperCase();
    final txId = (payment['id'] ?? 'N/A').toString();
    final refId = payment['ref_id'] ?? 'N/A';
    final plan = payment['memberships']?['plan_type'] ?? 'N/A';
    final shift = payment['memberships']?['shifts']?['name'] ?? 'N/A';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(context, libraryName, libraryAddress, 'PAYMENT RECEIPT', dateStr, logo),
              pw.SizedBox(height: 30),
              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Column(
                  children: [
                    pw.Text('RECEIPT TOTAL', style: const pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFF64748B))),
                    pw.SizedBox(height: 5),
                    pw.Text(amount, style: pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFFE65C00))),
                    pw.SizedBox(height: 5),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: pw.BoxDecoration(
                        color: status == 'CONFIRMED' ? const PdfColor.fromInt(0xFFDCFCE7) : const PdfColor.fromInt(0xFFFEF9C3),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                      ),
                      child: pw.Text(
                        status,
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: status == 'CONFIRMED' ? const PdfColor.fromInt(0xFF16A34A) : const PdfColor.fromInt(0xFFCA8A04),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 40),
              pw.Text('TRANSACTION DETAILS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF1E293B))),
              pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFFE2E8F0)),
              pw.SizedBox(height: 10),
              _buildReceiptDetailRow('Transaction ID', txId),
              _buildReceiptDetailRow('Reference ID', refId),
              _buildReceiptDetailRow('Member Name', memberName),
              _buildReceiptDetailRow('Payment Date', dateStr),
              _buildReceiptDetailRow('Payment Method', method),
              _buildReceiptDetailRow('Membership Plan', plan),
              _buildReceiptDetailRow('Shift Assigned', shift),
              pw.Spacer(),
              _buildFooter(context, logo),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Receipt_${txId.split('-').first}.pdf',
    );
  }

  /// Full member-profile PDF: personal details, contact, membership (plan,
  /// seat, floor, section, shift, library, dates) and the member's ID document
  /// images. Image URLs are fetched best-effort — a missing/blocked image is
  /// simply omitted, never an error.
  static Future<void> exportMemberProfile({
    required String libraryName,
    required String libraryAddress,
    required Map<String, dynamic> user,
    required Map<String, dynamic> membership,
    String floorName = '',
    String sectionName = '',
    String? photoUrl,
    String? idUrl1,
    String? idUrl2,
  }) async {
    final pdf = pw.Document();
    final logo = await _loadLogo();
    final generatedOn = DateFormat('dd MMM yyyy hh:mm a').format(DateTime.now());

    final name = (user['full_name'] ?? 'N/A').toString();
    final nickname = (user['nickname'] ?? '').toString();
    final gender = (user['gender'] ?? 'N/A').toString();
    final dob = _safeDate(user['date_of_birth']);
    final exam = (user['exam_category'] ?? 'N/A').toString();
    final phone = (user['phone'] ?? 'N/A').toString();
    final email = (user['email'] ?? 'N/A').toString();
    final address = (user['address'] ?? 'N/A').toString();
    final idType = (user['id_type'] ?? 'N/A').toString();

    final plan = _planLabel(membership['plan_type']);
    final status = (membership['status'] ?? 'N/A').toString().toUpperCase();
    final joinDate = _safeDate(membership['start_date']);
    final endDate = _safeDate(membership['end_date']);
    final seat = (membership['seats']?['seat_label'] ?? 'N/A').toString();
    final shift = (membership['shifts']?['name'] ?? 'N/A').toString();

    final photoImg = await _tryNetworkImage(photoUrl);
    final idImg1 = await _tryNetworkImage(idUrl1);
    final idImg2 = await _tryNetworkImage(idUrl2);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.only(top: 60, left: 40, right: 40, bottom: 50),
        header: (ctx) => _buildHeader(ctx, libraryName, libraryAddress, 'MEMBER PROFILE', generatedOn, logo),
        footer: (ctx) => _buildFooter(ctx, logo),
        build: (ctx) => [
          // Identity header: photo + name + status
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (photoImg != null) ...[
                pw.Container(
                  width: 64,
                  height: 64,
                  decoration: pw.BoxDecoration(
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                    image: pw.DecorationImage(image: photoImg, fit: pw.BoxFit.cover),
                  ),
                ),
                pw.SizedBox(width: 14),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(name, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F172A))),
                    if (nickname.isNotEmpty)
                      pw.Text('"$nickname"', style: const pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFF64748B))),
                    pw.SizedBox(height: 4),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: const pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFFFF3ED),
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
                      ),
                      child: pw.Text(status, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFFE65C00))),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _profileSection('PERSONAL DETAILS', [
            _buildReceiptDetailRow('Full name', name),
            if (nickname.isNotEmpty) _buildReceiptDetailRow('Nickname', nickname),
            _buildReceiptDetailRow('Gender', gender),
            _buildReceiptDetailRow('Date of birth', dob),
            _buildReceiptDetailRow('Preparing for', exam),
          ]),
          _profileSection('CONTACT', [
            _buildReceiptDetailRow('Phone', phone),
            _buildReceiptDetailRow('Email', email),
            _buildReceiptDetailRow('Address', address),
          ]),
          _profileSection('MEMBERSHIP', [
            _buildReceiptDetailRow('Library', libraryName),
            _buildReceiptDetailRow('Plan', plan),
            _buildReceiptDetailRow('Status', status),
            _buildReceiptDetailRow('Joining date', joinDate),
            _buildReceiptDetailRow('Valid till', endDate),
            _buildReceiptDetailRow('Seat', seat),
            _buildReceiptDetailRow('Floor', floorName.isEmpty ? 'N/A' : floorName),
            _buildReceiptDetailRow('Section', sectionName.isEmpty ? 'N/A' : sectionName),
            _buildReceiptDetailRow('Shift', shift),
          ]),
          _profileSection('ID DOCUMENTS', [
            _buildReceiptDetailRow('ID type', idType),
          ]),
          if (idImg1 != null) ...[
            pw.SizedBox(height: 10),
            pw.Text('ID Document 1', style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF64748B))),
            pw.SizedBox(height: 6),
            pw.Container(
              height: 220,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0))),
              child: pw.Image(idImg1, fit: pw.BoxFit.contain),
            ),
          ],
          if (idImg2 != null) ...[
            pw.SizedBox(height: 10),
            pw.Text('ID Document 2', style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF64748B))),
            pw.SizedBox(height: 6),
            pw.Container(
              height: 220,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0))),
              child: pw.Image(idImg2, fit: pw.BoxFit.contain),
            ),
          ],
          if (idImg1 == null && idImg2 == null)
            pw.Text('No ID document images available.', style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF94A3B8))),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${name.replaceAll(' ', '_')}_profile.pdf',
    );
  }

  static Future<pw.ImageProvider?> _tryNetworkImage(String? url) async {
    if (url == null || url.trim().isEmpty) return null;
    try {
      return await networkImage(url.trim());
    } catch (_) {
      return null;
    }
  }

  static String _safeDate(dynamic v) {
    if (v == null) return 'N/A';
    final s = v.toString();
    if (s.isEmpty) return 'N/A';
    final d = DateTime.tryParse(s);
    return d == null ? 'N/A' : DateFormat('dd MMM yyyy').format(d);
  }

  static String _planLabel(dynamic plan) {
    switch ((plan ?? '').toString()) {
      case '6_month':
        return '6-month plan';
      case '3_month':
        return '3-month plan';
      case 'monthly':
        return 'Monthly plan';
      case 'trial':
        return 'Trial';
      default:
        return (plan == null || plan.toString().isEmpty) ? 'N/A' : plan.toString();
    }
  }

  static pw.Widget _profileSection(String title, List<pw.Widget> rows) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 14),
        pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF1E293B))),
        pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFFE2E8F0)),
        ...rows,
      ],
    );
  }

  // --- PRIVATE HEADER/FOOTER/CELL BUILDERS ---

  static pw.Widget _buildHeader(
    pw.Context context,
    String libraryName,
    String libraryAddress,
    String reportTitle,
    String dateRange,
    pw.MemoryImage? logoImage,
  ) {
    if (context.pageNumber > 1) {
      return pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('SILENCE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFFE65C00), fontSize: 10)),
              pw.Text('$libraryName • $reportTitle', style: const pw.TextStyle(color: PdfColor.fromInt(0xFF64748B), fontSize: 8)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFFE2E8F0)),
          pw.SizedBox(height: 10),
        ],
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // Left Logo
            if (logoImage != null)
              pw.Image(logoImage, width: 100, height: 32, fit: pw.BoxFit.contain)
            else
              pw.Text(
                'SILENCE',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFFE65C00),
                  fontSize: 20,
                  letterSpacing: 1.5,
                ),
              ),
            // Right Library Info
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    libraryName.toUpperCase(),
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFF0F172A),
                      fontSize: 11,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    libraryAddress.isEmpty ? 'Smart Library Hub' : libraryAddress,
                    textAlign: pw.TextAlign.right,
                    style: const pw.TextStyle(
                      color: PdfColor.fromInt(0xFF64748B),
                      fontSize: 7,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 1.5, color: const PdfColor.fromInt(0xFFE65C00)),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              reportTitle,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF1E293B), fontSize: 11),
            ),
            pw.Text(
              'Period: $dateRange',
              style: const pw.TextStyle(color: PdfColor.fromInt(0xFF64748B), fontSize: 8),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
      ],
    );
  }

  static pw.Widget _buildFooter(pw.Context context, pw.MemoryImage? logoImage) {
    return pw.Column(
      children: [
        pw.SizedBox(height: 10),
        pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFFE2E8F0)),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    if (logoImage != null)
                      pw.Image(logoImage, width: 45, height: 14, fit: pw.BoxFit.contain)
                    else
                      pw.Text('SILENCE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFFE65C00), fontSize: 9)),
                    pw.SizedBox(width: 4),
                    pw.Text('Library App', style: const pw.TextStyle(color: PdfColor.fromInt(0xFF64748B), fontSize: 7)),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Text('Available on Play Store & App Store', style: const pw.TextStyle(color: PdfColor.fromInt(0xFF94A3B8), fontSize: 6)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('www.silence.app', style: const pw.TextStyle(color: PdfColor.fromInt(0xFF64748B), fontSize: 7)),
                pw.Text('support@silence.app', style: const pw.TextStyle(color: PdfColor.fromInt(0xFF94A3B8), fontSize: 7)),
              ],
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF475569), fontSize: 8),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildReportTitle(String title, String subtitle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: const PdfColor.fromInt(0xFF0F172A),
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          subtitle,
          style: const pw.TextStyle(
            fontSize: 9,
            color: PdfColor.fromInt(0xFF64748B),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTable({
    required pw.Context context,
    required List<String> headers,
    required List<List<dynamic>> data,
  }) {
    return pw.TableHelper.fromTextArray(
      context: context,
      headers: headers,
      data: data,
      border: null,
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
        fontSize: 8,
      ),
      headerDecoration: const pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFE65C00),
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      cellDecoration: (int columnIndex, dynamic data, int rowIndex) {
        if (rowIndex == 0) {
          return const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFE65C00),
          );
        }
        if (rowIndex % 2 == 0) {
          return const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFF8FAFC),
          );
        }
        return const pw.BoxDecoration(
          color: PdfColors.white,
        );
      },
      cellStyle: const pw.TextStyle(
        fontSize: 7.5,
        color: PdfColor.fromInt(0xFF334155),
      ),
      cellAlignment: pw.Alignment.centerLeft,
      headerAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
    );
  }
}
