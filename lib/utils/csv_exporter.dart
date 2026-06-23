import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'attendance_format.dart';

/// SILENCE — unified CSV export engine.
///
/// Machine-friendly by design: the COLUMN HEADER is always row 1 (so the file
/// imports cleanly into Excel / Google Sheets / pandas), amount columns are
/// plain numbers labelled "(INR)" (so `=SUM()` works — no ₹ inside numbers),
/// and dates use a single sortable `yyyy-MM-dd[ HH:mm]` format. A human-readable
/// "# Summary" block (library, period, totals, generated-at) is appended AFTER
/// the data so it never disrupts parsing.
class CsvExporter {
  // ── low-level helpers ─────────────────────────────────────────────────────
  static String _field(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
  static String _line(List<Object?> cells) => cells.map(_field).join(',');

  static num _num(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

  /// Clean numeric string for amount columns (no symbol; integer when whole).
  static String _amt(dynamic v) {
    final n = _num(v);
    return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
  }

  // Stored UTC → IST (timezone-independent, never depends on device clock).
  static DateTime _ist(DateTime d) => d.toUtc().add(const Duration(hours: 5, minutes: 30));

  static String _date(dynamic iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso.toString());
    return d == null ? iso.toString() : DateFormat('yyyy-MM-dd').format(_ist(d));
  }

  static String _dateTime(dynamic iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso.toString());
    return d == null ? iso.toString() : DateFormat('yyyy-MM-dd HH:mm').format(_ist(d));
  }

  static String _time(dynamic iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso.toString());
    return d == null ? iso.toString() : DateFormat('HH:mm').format(_ist(d));
  }

  static String _planLabel(dynamic plan) {
    switch ((plan ?? '').toString()) {
      case '6_month':
        return '6-Month';
      case '3_month':
        return '3-Month';
      case 'monthly':
        return 'Monthly';
      case 'trial':
        return 'Trial';
      default:
        return (plan == null || plan.toString().isEmpty) ? 'N/A' : plan.toString();
    }
  }

  /// Appends the trailing, human-readable summary block (kept out of the data
  /// rows so importers see a clean table first).
  static void _summary(StringBuffer b, String libraryName, {String? period, Map<String, String> totals = const {}}) {
    b.writeln();
    b.writeln('# Summary');
    b.writeln('${_field('Library')},${_field(libraryName)}');
    if (period != null) b.writeln('${_field('Period')},${_field(period)}');
    totals.forEach((k, v) => b.writeln('${_field(k)},${_field(v)}'));
    b.writeln('${_field('Generated')},${_field(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()))}');
  }

  // ── 1. Members ────────────────────────────────────────────────────────────
  static Future<void> exportMembers({
    required String libraryName,
    required List<Map<String, dynamic>> members,
    String? period,
  }) async {
    String seatOf(Map m) => (m['seat_label'] ?? m['seat'] ?? (m['seats'] is Map ? m['seats']['seat_label'] : null) ?? '').toString();
    String shiftOf(Map m) => (m['shift_name'] ?? m['shift'] ?? (m['shifts'] is Map ? m['shifts']['name'] : null) ?? '').toString();

    final b = StringBuffer();
    b.writeln(_line(['Name', 'Phone', 'Email', 'Seat', 'Shift', 'Plan', 'Joined Date', 'Expiry Date', 'Status']));
    int active = 0;
    for (final m in members) {
      final s = (m['status'] ?? 'expired').toString();
      if (['active', 'trial', 'hold'].contains(s.toLowerCase())) active++;
      b.writeln(_line([
        m['full_name'] ?? 'N/A',
        m['phone'] ?? '',
        m['email'] ?? '',
        seatOf(m),
        shiftOf(m),
        _planLabel(m['plan_type'] ?? m['plan']),
        _date(m['created_at']),
        _date(m['expiry_date'] ?? m['end_date']),
        s.toUpperCase(),
      ]));
    }
    _summary(b, libraryName, period: period, totals: {
      'Total Members': '${members.length}',
      'Active': '$active',
      'Inactive': '${members.length - active}',
    });

    await _shareFile(b.toString(), '${_slug(libraryName)}_members.csv');
  }

  // ── 2. Attendance (library-wide) ──────────────────────────────────────────
  static Future<void> exportAttendance({
    required String libraryName,
    required List<Map<String, dynamic>> logs,
    String? period,
  }) async {
    final b = StringBuffer();
    b.writeln(_line(['Date', 'Member Name', 'Seat', 'Shift', 'Check-in', 'Check-out', 'Duration (min)', 'Type', 'Overtime']));
    int totalMinutes = 0;
    int overtime = 0;
    for (final l in logs) {
      final ci = l['check_in_time'];
      final co = l['check_out_time'];
      int mins = _num(l['duration_minutes']).toInt();
      if (mins == 0 && ci != null && co != null) {
        mins = DateTime.parse(co.toString()).difference(DateTime.parse(ci.toString())).inMinutes;
      }
      totalMinutes += mins;
      final isOt = l['is_overtime'] == true;
      if (isOt) overtime++;
      b.writeln(_line([
        _date(ci),
        l['member_name'] ?? 'N/A',
        l['seat_label'] ?? '',
        l['shift_name'] ?? '',
        _time(ci),
        co != null ? _time(co) : 'Ongoing',
        mins,
        attendanceTag(l['session_type']).label,
        isOt ? 'YES' : 'NO',
      ]));
    }
    _summary(b, libraryName, period: period, totals: {
      'Total Sessions': '${logs.length}',
      'Total Hours': (totalMinutes / 60).toStringAsFixed(1),
      'Overtime Sessions': '$overtime',
    });

    await _shareFile(b.toString(), '${_slug(libraryName)}_attendance.csv');
  }

  // ── 3. Payments ───────────────────────────────────────────────────────────
  static Future<void> exportPayments({
    required String libraryName,
    required List<Map<String, dynamic>> payments,
    String? period,
  }) async {
    final b = StringBuffer();
    b.writeln(_line(['Transaction ID', 'Member Name', 'Date', 'Method', 'Status', 'Amount (INR)']));
    num collected = 0, pending = 0, total = 0;
    for (final p in payments) {
      final amt = _num(p['amount']);
      total += amt;
      final s = (p['status'] ?? 'pending').toString();
      if (s.toLowerCase() == 'confirmed') {
        collected += amt;
      } else if (s.toLowerCase() == 'pending') {
        pending += amt;
      }
      b.writeln(_line([
        p['id'] ?? 'N/A',
        p['member_name'] ?? 'N/A',
        _dateTime(p['payment_date']),
        (p['method'] ?? 'cash').toString().toUpperCase(),
        s.toUpperCase(),
        _amt(amt),
      ]));
    }
    _summary(b, libraryName, period: period, totals: {
      'Total Amount (INR)': _amt(total),
      'Collected (INR)': _amt(collected),
      'Pending (INR)': _amt(pending),
      'Transactions': '${payments.length}',
    });

    await _shareFile(b.toString(), '${_slug(libraryName)}_payments.csv');
  }

  // ── 4. Revenue summary ────────────────────────────────────────────────────
  static Future<void> exportRevenueSummary({
    required String libraryName,
    required List<Map<String, dynamic>> summary,
    String? period,
  }) async {
    final hasSplit = summary.any((s) => s.containsKey('cash') || s.containsKey('upi'));
    final b = StringBuffer();
    if (hasSplit) {
      b.writeln(_line(['Date', 'Revenue (INR)', 'Cash (INR)', 'UPI (INR)', 'Expenses (INR)', 'Net (INR)']));
    } else {
      b.writeln(_line(['Date', 'Revenue (INR)', 'Expenses (INR)', 'Net Profit (INR)']));
    }
    num tRev = 0, tExp = 0, tNet = 0, tCash = 0, tUpi = 0;
    for (final s in summary) {
      final rev = _num(s['revenue'] ?? s['total']);
      final exp = _num(s['expenses']);
      final net = s.containsKey('net_profit') ? _num(s['net_profit']) : (rev - exp);
      tRev += rev;
      tExp += exp;
      tNet += net;
      if (hasSplit) {
        final cash = _num(s['cash']);
        final upi = _num(s['upi']);
        tCash += cash;
        tUpi += upi;
        b.writeln(_line([s['date'] ?? '', _amt(rev), _amt(cash), _amt(upi), _amt(exp), _amt(net)]));
      } else {
        b.writeln(_line([s['date'] ?? '', _amt(rev), _amt(exp), _amt(net)]));
      }
    }
    _summary(b, libraryName, period: period, totals: {
      'Total Revenue (INR)': _amt(tRev),
      if (hasSplit) 'Total Cash (INR)': _amt(tCash),
      if (hasSplit) 'Total UPI (INR)': _amt(tUpi),
      'Total Expenses (INR)': _amt(tExp),
      'Net Profit (INR)': _amt(tNet),
    });

    await _shareFile(b.toString(), '${_slug(libraryName)}_revenue.csv');
  }

  // ── 5. Occupancy ──────────────────────────────────────────────────────────
  static Future<void> exportOccupancy({
    required String libraryName,
    required List<Map<String, dynamic>> reports,
    String? period,
  }) async {
    final b = StringBuffer();
    b.writeln(_line(['Shift', 'Total Seats', 'Occupied Seats', 'Occupancy Rate (%)']));
    int totalSeats = 0, occupied = 0;
    for (final r in reports) {
      final total = _num(r['total_seats']).toInt();
      final occ = _num(r['occupied_seats']).toInt();
      totalSeats += total;
      occupied += occ;
      // 'rate' may be a 0..1 fraction (legacy) or absent; compute from counts.
      final rate = total == 0 ? 0.0 : (occ / total) * 100;
      b.writeln(_line([r['shift'] ?? r['date'] ?? 'N/A', total, occ, rate.toStringAsFixed(1)]));
    }
    _summary(b, libraryName, period: period, totals: {
      'Total Seats': '$totalSeats',
      'Occupied': '$occupied',
      'Occupancy (%)': totalSeats == 0 ? '0.0' : (occupied / totalSeats * 100).toStringAsFixed(1),
    });

    await _shareFile(b.toString(), '${_slug(libraryName)}_occupancy.csv');
  }

  // ── 6. Outstanding dues ───────────────────────────────────────────────────
  static Future<void> exportDues({
    required String libraryName,
    required List<Map<String, dynamic>> dues,
    String? period,
  }) async {
    final b = StringBuffer();
    b.writeln(_line(['Member Name', 'Phone', 'Email', 'Outstanding Due (INR)', 'Since']));
    num total = 0;
    for (final d in dues) {
      total += _num(d['amount']);
      b.writeln(_line([
        d['member_name'] ?? 'N/A',
        d['phone'] ?? '',
        d['email'] ?? '',
        _amt(d['amount']),
        _date(d['due_date']),
      ]));
    }
    _summary(b, libraryName, period: period, totals: {
      'Members With Dues': '${dues.length}',
      'Total Outstanding (INR)': _amt(total),
    });

    await _shareFile(b.toString(), '${_slug(libraryName)}_outstanding_dues.csv');
  }

  // ── 7. Member's own attendance ────────────────────────────────────────────
  static Future<void> exportMemberAttendance({
    required String nickname,
    required String dateRangeLabel,
    required List<Map<String, dynamic>> logs,
  }) async {
    final b = StringBuffer();
    b.writeln(_line(['Date', 'Check-in', 'Check-out', 'Duration', 'Shift', 'Type', 'Overtime', 'Library', 'Seat']));
    int overtime = 0;
    for (final l in logs) {
      final isOt = l['is_overtime'] == true;
      if (isOt) overtime++;
      b.writeln(_line([
        l['date'] ?? '',
        l['check_in'] ?? '',
        l['check_out'] ?? '',
        l['duration'] ?? '',
        l['shift'] ?? '',
        attendanceTag(l['session_type']).label,
        isOt ? 'YES' : 'NO',
        l['library'] ?? '',
        l['seat'] ?? '',
      ]));
    }
    _summary(b, nickname, period: dateRangeLabel, totals: {
      'Total Sessions': '${logs.length}',
      'Overtime Sessions': '$overtime',
    });

    final filename = 'Silence_Attendance_${_slug(nickname)}_${_slug(dateRangeLabel)}.csv';
    await _shareFile(b.toString(), filename);
  }

  // ── 8. Upcoming expirations ───────────────────────────────────────────────
  static Future<void> exportExpiringMembers({
    required String libraryName,
    required List<Map<String, dynamic>> members,
    String? period,
  }) async {
    final b = StringBuffer();
    b.writeln(_line(['Member Name', 'Phone', 'Seat', 'Expiry Date']));
    for (final m in members) {
      b.writeln(_line([
        m['member_name'] ?? m['full_name'] ?? 'N/A',
        m['phone'] ?? '',
        m['seat'] ?? m['seat_label'] ?? '',
        _date(m['expiry'] ?? m['end_date'] ?? m['expiry_date']),
      ]));
    }
    _summary(b, libraryName, period: period, totals: {'Expiring Members': '${members.length}'});

    await _shareFile(b.toString(), '${_slug(libraryName)}_expiring.csv');
  }

  // ── 9. Attendance summary (member-wise) ───────────────────────────────────
  static Future<void> exportAttendanceSummary({
    required String libraryName,
    required List<Map<String, dynamic>> rows,
    String? period,
  }) async {
    final b = StringBuffer();
    b.writeln(_line(['Member Name', 'Plan', 'Total Check-ins', 'Total Hours', 'Avg Hours/Session']));
    int totalCheckins = 0;
    double totalHours = 0;
    for (final r in rows) {
      final checkins = _num(r['checkins']).toInt();
      final hours = _num(r['hours']).toDouble();
      totalCheckins += checkins;
      totalHours += hours;
      final avg = checkins == 0 ? 0.0 : hours / checkins;
      b.writeln(_line([
        r['member_name'] ?? 'N/A',
        _planLabel(r['plan']),
        checkins,
        hours.toStringAsFixed(1),
        avg.toStringAsFixed(1),
      ]));
    }
    _summary(b, libraryName, period: period, totals: {
      'Members': '${rows.length}',
      'Total Check-ins': '$totalCheckins',
      'Total Hours': totalHours.toStringAsFixed(1),
    });

    await _shareFile(b.toString(), '${_slug(libraryName)}_attendance_summary.csv');
  }

  // ── 9b. Member-wise attendance detail (grouped, for a month) ──────────────
  static Future<void> exportMemberwiseAttendance({
    required String libraryName,
    required String period,
    required List<Map<String, dynamic>> rows,
  }) async {
    final b = StringBuffer();
    b.writeln(_line(['Member Name', 'Date', 'Check-in', 'Check-out', 'Duration', 'Overtime']));
    int overtime = 0;
    for (final r in rows) {
      final isOt = r['is_overtime'] == true;
      if (isOt) overtime++;
      b.writeln(_line([
        r['member_name'] ?? 'N/A',
        r['date'] ?? '',
        r['check_in'] ?? '',
        r['check_out'] ?? '',
        r['duration'] ?? '',
        isOt ? 'YES' : 'NO',
      ]));
    }
    _summary(b, libraryName, period: period, totals: {
      'Total Sessions': '${rows.length}',
      'Overtime Sessions': '$overtime',
    });

    await _shareFile(b.toString(), '${_slug(libraryName)}_attendance_memberwise.csv');
  }

  // ── 9c. Expenses ──────────────────────────────────────────────────────────
  static Future<void> exportExpenses({
    required String libraryName,
    required List<Map<String, dynamic>> expenses,
    String? period,
  }) async {
    final b = StringBuffer();
    b.writeln(_line(['Date', 'Category', 'Note', 'Amount (INR)']));
    num total = 0;
    for (final e in expenses) {
      total += _num(e['amount']);
      b.writeln(_line([
        _date(e['date'] ?? e['expense_date']),
        e['category'] ?? '',
        e['note'] ?? e['notes'] ?? '',
        _amt(e['amount']),
      ]));
    }
    _summary(b, libraryName, period: period, totals: {
      'Entries': '${expenses.length}',
      'Total Expenses (INR)': _amt(total),
    });

    await _shareFile(b.toString(), '${_slug(libraryName)}_expenses.csv');
  }

  // ── share ─────────────────────────────────────────────────────────────────
  static String _slug(String s) => s.trim().isEmpty ? 'SILENCE' : s.replaceAll(RegExp(r'[^\w]+'), '_');

  static Future<void> _shareFile(String csvContent, String filename) async {
    // UTF-8 BOM keeps Excel's encoding detection happy.
    final content = '\uFEFF$csvContent';
    if (kIsWeb) {
      // Web has no filesystem — share the bytes directly (writing to
      // Directory.systemTemp throws "Unsupported operation: _Namespace").
      final bytes = Uint8List.fromList(utf8.encode(content));
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'text/csv', name: filename)],
        subject: 'SILENCE Data Export - $filename',
      );
    } else {
      final tempFile = File('${Directory.systemTemp.path}/$filename');
      await tempFile.writeAsString(content);
      await Share.shareXFiles(
        [XFile(tempFile.path, mimeType: 'text/csv')],
        subject: 'SILENCE Data Export - $filename',
      );
    }
  }
}
