import 'dart:io';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'attendance_format.dart';

class CsvExporter {
  static Future<void> exportMembers({
    required String libraryName,
    required List<Map<String, dynamic>> members,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('SILENCE Members List Export');
    buffer.writeln('Library:,$libraryName');
    buffer.writeln('Export Date:,${DateFormat('dd MMM yyyy hh:mm a').format(DateTime.now())}');
    buffer.writeln();

    buffer.writeln('Name,Email,Phone,Joined Date,Expiry Date,Status');

    for (var m in members) {
      final name = m['full_name'] ?? 'N/A';
      final email = m['email'] ?? 'N/A';
      final phone = m['phone'] ?? 'N/A';
      final joined = m['created_at'] != null ? DateFormat('dd MMM yyyy').format(DateTime.parse(m['created_at'])) : 'N/A';
      final expiry = m['expiry_date'] != null ? DateFormat('dd MMM yyyy').format(DateTime.parse(m['expiry_date'])) : 'N/A';
      final status = (m['status'] ?? 'expired').toString().toUpperCase();

      buffer.writeln('"$name","$email","$phone","$joined","$expiry","$status"');
    }

    await _shareFile(buffer.toString(), '${libraryName.replaceAll(' ', '_')}_members.csv');
  }

  static Future<void> exportAttendance({
    required String libraryName,
    required List<Map<String, dynamic>> logs,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('SILENCE Attendance Log Export');
    buffer.writeln('Library:,$libraryName');
    buffer.writeln('Export Date:,${DateFormat('dd MMM yyyy hh:mm a').format(DateTime.now())}');
    buffer.writeln();

    buffer.writeln('Member Name,Date,Check-in,Check-out,Shift');

    for (var l in logs) {
      final name = l['member_name'] ?? 'N/A';
      final checkinStr = l['check_in_time'];
      final checkoutStr = l['check_out_time'];
      
      final dateStr = checkinStr != null ? DateFormat('dd MMM yyyy').format(DateTime.parse(checkinStr)) : 'N/A';
      final checkin = checkinStr != null ? DateFormat('hh:mm a').format(DateTime.parse(checkinStr)) : 'N/A';
      final checkout = checkoutStr != null ? DateFormat('hh:mm a').format(DateTime.parse(checkoutStr)) : 'Ongoing';
      final shift = l['shift_name'] ?? 'N/A';

      buffer.writeln('"$name","$dateStr","$checkin","$checkout","$shift"');
    }

    await _shareFile(buffer.toString(), '${libraryName.replaceAll(' ', '_')}_attendance.csv');
  }

  static Future<void> exportPayments({
    required String libraryName,
    required List<Map<String, dynamic>> payments,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('SILENCE Payments Export');
    buffer.writeln('Library:,$libraryName');
    buffer.writeln('Export Date:,${DateFormat('dd MMM yyyy hh:mm a').format(DateTime.now())}');
    buffer.writeln();

    buffer.writeln('Transaction ID,Member Name,Date,Amount,Method,Status');

    for (var p in payments) {
      final txId = p['id'] ?? 'N/A';
      final name = p['member_name'] ?? 'N/A';
      final dateStr = p['payment_date'] != null ? DateFormat('dd MMM yyyy hh:mm a').format(DateTime.parse(p['payment_date'])) : 'N/A';
      final amount = p['amount'] ?? 0;
      final method = (p['method'] ?? 'cash').toString().toUpperCase();
      final status = (p['status'] ?? 'pending').toString().toUpperCase();

      buffer.writeln('"$txId","$name","$dateStr","₹$amount","$method","$status"');
    }

    await _shareFile(buffer.toString(), '${libraryName.replaceAll(' ', '_')}_payments.csv');
  }

  static Future<void> exportRevenueSummary({
    required String libraryName,
    required List<Map<String, dynamic>> summary,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('SILENCE Revenue Summary Export');
    buffer.writeln('Library:,$libraryName');
    buffer.writeln('Export Date:,${DateFormat('dd MMM yyyy hh:mm a').format(DateTime.now())}');
    buffer.writeln();

    buffer.writeln('Date,Revenue,Expenses,Net Profit');

    for (var s in summary) {
      final date = s['date'] ?? '';
      final rev = s['revenue'] ?? 0;
      final exp = s['expenses'] ?? 0;
      final net = s['net_profit'] ?? 0;

      buffer.writeln('"$date","₹$rev","₹$exp","₹$net"');
    }

    await _shareFile(buffer.toString(), '${libraryName.replaceAll(' ', '_')}_revenue_summary.csv');
  }

  static Future<void> exportOccupancy({
    required String libraryName,
    required List<Map<String, dynamic>> reports,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('SILENCE Occupancy Report Export');
    buffer.writeln('Library:,$libraryName');
    buffer.writeln('Export Date:,${DateFormat('dd MMM yyyy hh:mm a').format(DateTime.now())}');
    buffer.writeln();

    buffer.writeln('Date,Total Seats,Occupied Seats,Occupancy Rate (%)');

    for (var r in reports) {
      final date = r['date'] ?? 'N/A';
      final total = r['total_seats'] ?? 0;
      final occupied = r['occupied_seats'] ?? 0;
      final rate = r['rate'] ?? 0.0;

      buffer.writeln('"$date","$total","$occupied","${(rate * 100).toStringAsFixed(1)}%"');
    }

    await _shareFile(buffer.toString(), '${libraryName.replaceAll(' ', '_')}_occupancy.csv');
  }

  static Future<void> exportDues({
    required String libraryName,
    required List<Map<String, dynamic>> dues,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('SILENCE Outstanding Dues Export');
    buffer.writeln('Library:,$libraryName');
    buffer.writeln('Export Date:,${DateFormat('dd MMM yyyy hh:mm a').format(DateTime.now())}');
    buffer.writeln();

    buffer.writeln('Member Name,Email,Phone,Outstanding Due (₹),Due Date');

    for (var d in dues) {
      final name = d['member_name'] ?? 'N/A';
      final email = d['email'] ?? 'N/A';
      final phone = d['phone'] ?? 'N/A';
      final due = d['amount'] ?? 0;
      final dueDate = d['due_date'] != null ? DateFormat('dd MMM yyyy').format(DateTime.parse(d['due_date'])) : 'N/A';

      buffer.writeln('"$name","$email","$phone","₹$due","$dueDate"');
    }

    await _shareFile(buffer.toString(), '${libraryName.replaceAll(' ', '_')}_outstanding_dues.csv');
  }

  static Future<void> exportMemberAttendance({
    required String nickname,
    required String dateRangeLabel,
    required List<Map<String, dynamic>> logs,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('SILENCE - My Attendance Report');
    buffer.writeln('Member:,$nickname');
    buffer.writeln('Period:,$dateRangeLabel');
    buffer.writeln('Export Date:,${DateFormat('dd MMM yyyy hh:mm a').format(DateTime.now())}');
    buffer.writeln();

    buffer.writeln('Date,Check-in Time,Check-out Time,Duration,Session Type,Library,Seat');

    for (var l in logs) {
      final date = l['date'] ?? 'N/A';
      final checkIn = l['check_in'] ?? 'N/A';
      final checkOut = l['check_out'] ?? 'N/A';
      final duration = l['duration'] ?? 'N/A';
      final sessionType = attendanceTag(l['session_type']).label +
          (l['is_overtime'] == true ? ' +OT' : '');
      final library = l['library'] ?? 'N/A';
      final seat = l['seat'] ?? 'N/A';

      buffer.writeln('"$date","$checkIn","$checkOut","$duration","$sessionType","$library","$seat"');
    }

    final safeNickname = nickname.replaceAll(RegExp(r'[^\w]'), '_');
    final safeDateRange = dateRangeLabel.replaceAll(' ', '_').replaceAll('/', '-');
    final filename = 'Silence_Attendance_${safeNickname}_$safeDateRange.csv';

    await _shareFile(buffer.toString(), filename);
  }

  static Future<void> _shareFile(String csvContent, String filename) async {
    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/$filename');
    await tempFile.writeAsString(csvContent);

    await Share.shareXFiles(
      [XFile(tempFile.path, mimeType: 'text/csv')],
      subject: 'SILENCE Data Export - $filename',
    );
  }
}
