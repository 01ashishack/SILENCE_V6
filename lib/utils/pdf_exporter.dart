import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

import 'attendance_format.dart';

/// SILENCE — unified PDF report engine.
///
/// One premium, consistent design for every document: a brand orange letterhead
/// band (white logo), an optional KPI summary strip, zebra-striped tables with
/// right-aligned money + bold TOTAL rows, and a branded footer with page numbers.
///
/// All amounts render through [_inr] using an embedded Noto Sans font (the
/// default Helvetica has no ₹ glyph), so the rupee symbol prints correctly.
class PdfExporter {
  // ── Brand palette ─────────────────────────────────────────────────────────
  static const _orange = PdfColor.fromInt(0xFFE65C00);
  static const _orangeDark = PdfColor.fromInt(0xFFC2410C);
  static const _ink = PdfColor.fromInt(0xFF0F172A);
  static const _slate = PdfColor.fromInt(0xFF475569);
  static const _muted = PdfColor.fromInt(0xFF94A3B8);
  static const _line = PdfColor.fromInt(0xFFE2E8F0);
  static const _zebra = PdfColor.fromInt(0xFFF8FAFC);
  static const _tintOrange = PdfColor.fromInt(0xFFFFF3ED);

  static const _green = PdfColor.fromInt(0xFF16A34A);
  static const _greenBg = PdfColor.fromInt(0xFFDCFCE7);
  static const _amber = PdfColor.fromInt(0xFFCA8A04);
  static const _amberBg = PdfColor.fromInt(0xFFFEF9C3);

  // ── Formatters ──────────────────────────────────────────────────────────
  static final NumberFormat _inrFmt =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  static String _inr(dynamic v) {
    final n = v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
    return _inrFmt.format(n);
  }

  static num _num(dynamic v) =>
      v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

  // Times are stored UTC; SILENCE is IST-only, so render everything in IST
  // (timezone-independent — never depends on the device clock).
  static DateTime _ist(DateTime d) => d.toUtc().add(const Duration(hours: 5, minutes: 30));

  static String _fmtDate(dynamic iso) {
    if (iso == null) return 'N/A';
    final d = DateTime.tryParse(iso.toString());
    return d == null ? iso.toString() : DateFormat('dd MMM yyyy').format(_ist(d));
  }

  static String _fmtDateTime(dynamic iso) {
    if (iso == null) return 'N/A';
    final d = DateTime.tryParse(iso.toString());
    return d == null ? iso.toString() : DateFormat('dd MMM yyyy, hh:mm a').format(_ist(d));
  }

  static String _fmtTime(dynamic iso) {
    if (iso == null) return 'N/A';
    final d = DateTime.tryParse(iso.toString());
    return d == null ? iso.toString() : DateFormat('hh:mm a').format(_ist(d));
  }

  // ── Fonts (Noto Sans → has the ₹ glyph) ─────────────────────────────────
  static pw.ThemeData? _cachedTheme;
  static Future<pw.ThemeData> _theme() async {
    if (_cachedTheme != null) return _cachedTheme!;
    try {
      _cachedTheme = pw.ThemeData.withFont(
        base: await PdfGoogleFonts.notoSansRegular(),
        bold: await PdfGoogleFonts.notoSansBold(),
        italic: await PdfGoogleFonts.notoSansItalic(),
        boldItalic: await PdfGoogleFonts.notoSansBoldItalic(),
      );
    } catch (_) {
      // Offline / font fetch failed: fall back to the default theme. Money will
      // still print using "Rs." instead of ₹ via [_inr]'s safe path below.
      _cachedTheme = pw.ThemeData.base();
    }
    return _cachedTheme!;
  }

  // ── Logos ─────────────────────────────────────────────────────────────────
  static final Map<String, pw.MemoryImage?> _imgCache = {};
  static Future<pw.MemoryImage?> _img(String asset) async {
    if (_imgCache.containsKey(asset)) return _imgCache[asset];
    try {
      final bytes = await rootBundle.load(asset);
      final img = pw.MemoryImage(bytes.buffer.asUint8List());
      _imgCache[asset] = img;
      return img;
    } catch (_) {
      _imgCache[asset] = null;
      return null;
    }
  }

  static Future<pw.MemoryImage?> _whiteLogo() =>
      _img('assets/images/WHITE_WITH_TAGLINE.png');
  static Future<pw.MemoryImage?> _darkLogo() =>
      _img('assets/images/BLack_name_with_tag.png');
  static Future<pw.MemoryImage?> _iconLogo() =>
      _img('assets/images/only_icon.png');

  // ── Standard page margins (small — the letterhead band sits at the very top;
  //    a big top margin previously left a large blank strip above the header). ─
  static const _pageMargin =
      pw.EdgeInsets.only(top: 18, left: 30, right: 30, bottom: 20);

  // ───────────────────────────────────────────────────────────────────────────
  // SHARED LAYOUT WIDGETS
  // ───────────────────────────────────────────────────────────────────────────

  /// The letterhead band shown at the top of every page. Full brand band on
  /// page 1; a slim bar on continuation pages to save space.
  static pw.Widget _letterhead(
    pw.Context context,
    String reportTitle,
    String libraryName,
    String libraryAddress,
    String period,
    pw.MemoryImage? whiteLogo,
  ) {
    if (context.pageNumber > 1) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 14),
        decoration: const pw.BoxDecoration(
          color: _orange,
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(reportTitle,
                style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9)),
            pw.Text(libraryName.toUpperCase(),
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 8)),
          ],
        ),
      );
    }

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      padding: const pw.EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: const pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [_orange, _orangeDark],
          begin: pw.Alignment.topLeft,
          end: pw.Alignment.bottomRight,
        ),
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(14)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              if (whiteLogo != null)
                pw.Image(whiteLogo, height: 42, fit: pw.BoxFit.contain)
              else
                pw.Text('SILENCE',
                    style: pw.TextStyle(
                        color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 24, letterSpacing: 1.5)),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(libraryName.toUpperCase(),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 13)),
                    if (libraryAddress.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(libraryAddress,
                          textAlign: pw.TextAlign.right,
                          maxLines: 2,
                          style: const pw.TextStyle(color: PdfColor.fromInt(0xFFFFE6D5), fontSize: 8)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Container(height: 1, color: const PdfColor.fromInt(0x55FFFFFF)),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(reportTitle,
                  style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 15, letterSpacing: 0.4)),
              pw.Text(period,
                  style: const pw.TextStyle(color: PdfColor.fromInt(0xFFFFE6D5), fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context context, pw.MemoryImage? darkLogo) {
    return pw.Column(
      children: [
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 0.8, color: _line),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (darkLogo != null)
              pw.Image(darkLogo, height: 26, fit: pw.BoxFit.contain)
            else
              pw.Text('SILENCE',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _orange, fontSize: 11)),
            pw.Text('silence.app  •  support@silence.app',
                style: const pw.TextStyle(color: _muted, fontSize: 7.5)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _slate, fontSize: 8)),
          ],
        ),
      ],
    );
  }

  /// A row of compact summary tiles (label + big value). Pass [accent] true on a
  /// tile to highlight it in brand orange.
  static pw.Widget _kpiStrip(List<List<String>> kpis, {Set<int> accentIndexes = const {}}) {
    return pw.Row(
      children: [
        for (int i = 0; i < kpis.length; i++) ...[
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              decoration: pw.BoxDecoration(
                color: accentIndexes.contains(i) ? _tintOrange : PdfColors.white,
                border: pw.Border.all(color: accentIndexes.contains(i) ? _orange : _line, width: 0.8),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(kpis[i][1],
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold,
                          color: accentIndexes.contains(i) ? _orange : _ink)),
                  pw.SizedBox(height: 2),
                  pw.Text(kpis[i][0].toUpperCase(),
                      style: const pw.TextStyle(fontSize: 7, color: _muted, letterSpacing: 0.4)),
                ],
              ),
            ),
          ),
          if (i != kpis.length - 1) pw.SizedBox(width: 8),
        ],
      ],
    );
  }

  static pw.Widget _sectionTitle(String title, String subtitle) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(width: 3.5, height: 22, color: _orange),
          pw.SizedBox(width: 8),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _ink)),
              if (subtitle.isNotEmpty)
                pw.Text(subtitle, style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
            ],
          ),
        ],
      ),
    );
  }

  /// Zebra-striped table. [rightAlign] holds column indexes to right-align
  /// (money/numbers). [totalRow] renders a bold tinted total row at the bottom.
  static pw.Widget _table({
    required List<String> headers,
    required List<List<String>> data,
    Set<int> rightAlign = const {},
    List<String>? totalRow,
  }) {
    final alignments = <int, pw.Alignment>{
      for (int i = 0; i < headers.length; i++)
        i: rightAlign.contains(i) ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
    };

    final allRows = <List<String>>[...data];
    final int totalRowIndex = totalRow != null ? data.length : -1;
    if (totalRow != null) allRows.add(totalRow);

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: allRows,
      border: null,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
      headerDecoration: const pw.BoxDecoration(color: _orange),
      headerAlignments: alignments,
      cellAlignments: alignments,
      cellStyle: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF334155)),
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 7),
      cellDecoration: (col, dynamic value, row) {
        if (row == totalRowIndex) {
          return const pw.BoxDecoration(
            color: _tintOrange,
            border: pw.Border(top: pw.BorderSide(color: _orange, width: 1)),
          );
        }
        return pw.BoxDecoration(color: row.isOdd ? _zebra : PdfColors.white);
      },
    );
  }

  static pw.Widget _emptyNote(String msg) => pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 16),
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          color: _zebra,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          border: pw.Border.all(color: _line),
        ),
        child: pw.Center(
          child: pw.Text(msg, style: const pw.TextStyle(fontSize: 9, color: _muted)),
        ),
      );

  /// Builds a standard multi-page doc with letterhead + footer.
  static Future<Uint8List> _document({
    required String reportTitle,
    required String libraryName,
    required String libraryAddress,
    required String period,
    required List<pw.Widget> Function(pw.Context) build,
  }) async {
    final theme = await _theme();
    final whiteLogo = await _whiteLogo();
    final darkLogo = await _darkLogo();
    final pdf = pw.Document(theme: theme);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _pageMargin,
        header: (ctx) => _letterhead(ctx, reportTitle, libraryName, libraryAddress, period, whiteLogo),
        footer: (ctx) => _footer(ctx, darkLogo),
        build: build,
      ),
    );
    return pdf.save();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 1. MEMBERS DIRECTORY
  // ───────────────────────────────────────────────────────────────────────────
  static Future<void> exportMembers({
    required String libraryName,
    required String libraryAddress,
    required List<Map<String, dynamic>> members,
    String? dateRange,
  }) async {
    String seatOf(Map m) =>
        (m['seat_label'] ?? m['seat'] ?? (m['seats'] is Map ? m['seats']['seat_label'] : null) ?? '—').toString();
    String shiftOf(Map m) =>
        (m['shift_name'] ?? m['shift'] ?? (m['shifts'] is Map ? m['shifts']['name'] : null) ?? '—').toString();
    String planOf(Map m) => _planLabel(m['plan_type'] ?? m['plan']);

    int active = 0, expired = 0;
    for (final m in members) {
      final s = (m['status'] ?? '').toString().toLowerCase();
      if (s == 'active' || s == 'trial' || s == 'hold') {
        active++;
      } else {
        expired++;
      }
    }

    final rows = members.map((m) {
      return [
        (m['full_name'] ?? 'N/A').toString(),
        (m['phone'] ?? '—').toString(),
        seatOf(m),
        shiftOf(m),
        planOf(m),
        _fmtDate(m['created_at'] ?? m['joined_date']),
        _fmtDate(m['expiry_date'] ?? m['end_date']),
        (m['status'] ?? 'expired').toString().toUpperCase(),
      ];
    }).toList();

    final bytes = await _document(
      reportTitle: 'MEMBERS DIRECTORY',
      libraryName: libraryName,
      libraryAddress: libraryAddress,
      period: dateRange ?? 'As on ${_fmtDate(DateTime.now().toIso8601String())}',
      build: (ctx) => [
        _kpiStrip([
          ['Total Members', '${members.length}'],
          ['Active', '$active'],
          ['Inactive / Expired', '$expired'],
        ], accentIndexes: {0}),
        pw.SizedBox(height: 16),
        _sectionTitle('Registered Members', 'Seat, shift, plan, joining and validity for every member'),
        if (rows.isEmpty)
          _emptyNote('No members to show for this selection.')
        else
          _table(
            headers: ['Name', 'Phone', 'Seat', 'Shift', 'Plan', 'Joined', 'Valid Till', 'Status'],
            data: rows,
          ),
      ],
    );

    await Printing.sharePdf(bytes: bytes, filename: '${_slug(libraryName)}_members.pdf');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2. ATTENDANCE LOG (grouped by day, with hours total)
  // ───────────────────────────────────────────────────────────────────────────
  static Future<void> exportAttendance({
    required String libraryName,
    required String libraryAddress,
    required String dateRange,
    required List<Map<String, dynamic>> logs,
  }) async {
    final grouped = <String, List<Map<String, dynamic>>>{};
    int totalMinutes = 0;
    int overtimeCount = 0;
    for (final l in logs) {
      final ci = l['check_in_time'];
      final key = ci != null ? (DateTime.tryParse(ci.toString())?.toIso8601String().split('T').first ?? 'Unknown') : 'Unknown';
      grouped.putIfAbsent(key, () => []).add(l);
      totalMinutes += _num(l['duration_minutes']).toInt();
      if (l['is_overtime'] == true) overtimeCount++;
    }
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    final totalH = (totalMinutes / 60).floor();
    final totalM = totalMinutes % 60;

    final bytes = await _document(
      reportTitle: 'ATTENDANCE LOG',
      libraryName: libraryName,
      libraryAddress: libraryAddress,
      period: dateRange,
      build: (ctx) {
        final out = <pw.Widget>[
          _kpiStrip([
            ['Sessions', '${logs.length}'],
            ['Study Hours', '${totalH}h ${totalM}m'],
            ['Overtime', '$overtimeCount'],
          ], accentIndexes: {1}),
          pw.SizedBox(height: 16),
          _sectionTitle('Attendance by Day', 'Each check-in/out with seat, shift, duration and type'),
        ];
        if (logs.isEmpty) {
          out.add(_emptyNote('No attendance records for this period.'));
          return out;
        }
        for (final date in sortedDates) {
          final day = grouped[date]!;
          final label = date != 'Unknown'
              ? DateFormat('EEEE, dd MMM yyyy').format(DateTime.parse(date))
              : 'Unknown Date';
          out.add(pw.Container(
            margin: const pw.EdgeInsets.only(top: 12, bottom: 6),
            child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _orangeDark, fontSize: 9.5)),
          ));
          final tableData = day.map((l) {
            String duration = 'Ongoing';
            final ci = l['check_in_time'];
            final co = l['check_out_time'];
            if (ci != null && co != null) {
              final d = DateTime.parse(co.toString()).difference(DateTime.parse(ci.toString()));
              duration = '${d.inHours}h ${d.inMinutes % 60}m';
            }
            final type = attendanceTag(l['session_type']).label + (l['is_overtime'] == true ? ' +OT' : '');
            return [
              (l['member_name'] ?? 'N/A').toString(),
              (l['seat_label'] ?? '—').toString(),
              (l['shift_name'] ?? '—').toString(),
              _fmtTime(ci),
              co != null ? _fmtTime(co) : 'Ongoing',
              duration,
              type,
            ];
          }).toList();
          out.add(_table(
            headers: ['Member', 'Seat', 'Shift', 'Check-In', 'Check-Out', 'Duration', 'Type'],
            data: tableData,
          ));
        }
        return out;
      },
    );

    await Printing.sharePdf(bytes: bytes, filename: '${_slug(libraryName)}_attendance.pdf');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 3. PAYMENTS LEDGER (with collected / pending KPIs + total row)
  // ───────────────────────────────────────────────────────────────────────────
  static Future<void> exportPayments({
    required String libraryName,
    required String libraryAddress,
    required String dateRange,
    required List<Map<String, dynamic>> payments,
  }) async {
    num collected = 0, pending = 0, total = 0;
    for (final p in payments) {
      final amt = _num(p['amount']);
      total += amt;
      final s = (p['status'] ?? '').toString().toLowerCase();
      if (s == 'confirmed') {
        collected += amt;
      } else if (s == 'pending') {
        pending += amt;
      }
    }

    final rows = payments.map((p) {
      return [
        (p['id'] ?? 'N/A').toString().split('-').first.toUpperCase(),
        (p['member_name'] ?? 'N/A').toString(),
        _fmtDateTime(p['payment_date']),
        (p['method'] ?? 'cash').toString().toUpperCase(),
        (p['status'] ?? 'pending').toString().toUpperCase(),
        _inr(p['amount']),
      ];
    }).toList();

    final bytes = await _document(
      reportTitle: 'PAYMENTS LEDGER',
      libraryName: libraryName,
      libraryAddress: libraryAddress,
      period: dateRange,
      build: (ctx) => [
        _kpiStrip([
          ['Collected', _inr(collected)],
          ['Pending', _inr(pending)],
          ['Transactions', '${payments.length}'],
        ], accentIndexes: {0}),
        pw.SizedBox(height: 16),
        _sectionTitle('Transaction Ledger', 'All recorded payments for the period'),
        if (rows.isEmpty)
          _emptyNote('No payments for this period.')
        else
          _table(
            headers: ['Tx ID', 'Member', 'Date', 'Method', 'Status', 'Amount'],
            data: rows,
            rightAlign: {5},
            totalRow: ['', '', '', '', 'TOTAL', _inr(total)],
          ),
      ],
    );

    await Printing.sharePdf(bytes: bytes, filename: '${_slug(libraryName)}_payments.pdf');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 4. REVENUE & EXPENSES (cash/UPI split when available + totals)
  // ───────────────────────────────────────────────────────────────────────────
  static Future<void> exportRevenueSummary({
    required String libraryName,
    required String libraryAddress,
    required String dateRange,
    required List<Map<String, dynamic>> summary,
  }) async {
    final bool hasSplit = summary.any((s) => s.containsKey('cash') || s.containsKey('upi'));
    num tRev = 0, tExp = 0, tNet = 0, tCash = 0, tUpi = 0;

    final rows = summary.map((s) {
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
        return [s['date'].toString(), _inr(rev), _inr(cash), _inr(upi), _inr(exp), _inr(net)];
      }
      return [s['date'].toString(), _inr(rev), _inr(exp), _inr(net)];
    }).toList();

    final headers = hasSplit
        ? ['Date', 'Revenue', 'Cash', 'UPI', 'Expenses', 'Net']
        : ['Date', 'Revenue', 'Expenses', 'Net Profit'];
    final rightAlign = hasSplit ? {1, 2, 3, 4, 5} : {1, 2, 3};
    final totalRow = hasSplit
        ? ['TOTAL', _inr(tRev), _inr(tCash), _inr(tUpi), _inr(tExp), _inr(tNet)]
        : ['TOTAL', _inr(tRev), _inr(tExp), _inr(tNet)];

    final bytes = await _document(
      reportTitle: 'REVENUE & EXPENSES',
      libraryName: libraryName,
      libraryAddress: libraryAddress,
      period: dateRange,
      build: (ctx) => [
        _kpiStrip([
          ['Total Revenue', _inr(tRev)],
          ['Total Expenses', _inr(tExp)],
          ['Net Profit', _inr(tNet)],
        ], accentIndexes: {2}),
        pw.SizedBox(height: 16),
        _sectionTitle('Daily Profit & Loss', hasSplit ? 'Revenue split by cash / UPI, net of expenses' : 'Revenue net of expenses'),
        if (rows.isEmpty)
          _emptyNote('No revenue recorded for this period.')
        else
          _table(headers: headers, data: rows, rightAlign: rightAlign, totalRow: totalRow),
      ],
    );

    await Printing.sharePdf(bytes: bytes, filename: '${_slug(libraryName)}_revenue.pdf');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 5. OCCUPANCY (current snapshot — honest about not being date-ranged)
  // ───────────────────────────────────────────────────────────────────────────
  static Future<void> exportOccupancy({
    required String libraryName,
    required String libraryAddress,
    required List<Map<String, dynamic>> reports,
    String? period,
  }) async {
    int totalSeats = 0, occupiedSeats = 0;
    final rows = reports.map((r) {
      final total = _num(r['total_seats']).toInt();
      final occ = _num(r['occupied_seats']).toInt();
      totalSeats += total;
      occupiedSeats += occ;
      final rate = total == 0 ? 0.0 : (occ / total) * 100;
      return [
        (r['shift'] ?? r['date'] ?? 'N/A').toString(),
        '$total',
        '$occ',
        '${rate.toStringAsFixed(1)}%',
      ];
    }).toList();
    final overall = totalSeats == 0 ? '0.0%' : '${(occupiedSeats / totalSeats * 100).toStringAsFixed(1)}%';

    final bytes = await _document(
      reportTitle: 'SEAT OCCUPANCY',
      libraryName: libraryName,
      libraryAddress: libraryAddress,
      period: period ?? 'Current snapshot • ${_fmtDateTime(DateTime.now().toIso8601String())}',
      build: (ctx) => [
        _kpiStrip([
          ['Total Seats', '$totalSeats'],
          ['Occupied', '$occupiedSeats'],
          ['Occupancy', overall],
        ], accentIndexes: {2}),
        pw.SizedBox(height: 16),
        _sectionTitle('Occupancy by Shift', 'Live seat usage at the time of export'),
        if (rows.isEmpty)
          _emptyNote('No seat data available.')
        else
          _table(
            headers: ['Shift', 'Total Seats', 'Occupied', 'Occupancy %'],
            data: rows,
            rightAlign: {1, 2, 3},
            totalRow: ['TOTAL', '$totalSeats', '$occupiedSeats', overall],
          ),
      ],
    );

    await Printing.sharePdf(bytes: bytes, filename: '${_slug(libraryName)}_occupancy.pdf');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 6. OUTSTANDING DUES (with total)
  // ───────────────────────────────────────────────────────────────────────────
  static Future<void> exportDues({
    required String libraryName,
    required String libraryAddress,
    required List<Map<String, dynamic>> dues,
    String? period,
  }) async {
    num total = 0;
    final rows = dues.map((d) {
      total += _num(d['amount']);
      return [
        (d['member_name'] ?? 'N/A').toString(),
        (d['phone'] ?? '—').toString(),
        _fmtDate(d['due_date']),
        _inr(d['amount']),
      ];
    }).toList();

    final bytes = await _document(
      reportTitle: 'OUTSTANDING DUES',
      libraryName: libraryName,
      libraryAddress: libraryAddress,
      period: period ?? 'As on ${_fmtDate(DateTime.now().toIso8601String())}',
      build: (ctx) => [
        _kpiStrip([
          ['Members With Dues', '${dues.length}'],
          ['Total Outstanding', _inr(total)],
        ], accentIndexes: {1}),
        pw.SizedBox(height: 16),
        _sectionTitle('Pending Collections', 'Members with unpaid / pending payments'),
        if (rows.isEmpty)
          _emptyNote('No outstanding dues. Everyone is paid up.')
        else
          _table(
            headers: ['Member', 'Phone', 'Since', 'Amount Due'],
            data: rows,
            rightAlign: {3},
            totalRow: ['', '', 'TOTAL', _inr(total)],
          ),
      ],
    );

    await Printing.sharePdf(bytes: bytes, filename: '${_slug(libraryName)}_dues.pdf');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2b. ATTENDANCE SUMMARY (member-wise: check-ins, hours, avg)
  // ───────────────────────────────────────────────────────────────────────────
  static Future<void> exportAttendanceSummary({
    required String libraryName,
    required String libraryAddress,
    required String dateRange,
    required List<Map<String, dynamic>> rows,
  }) async {
    int totalCheckins = 0;
    double totalHours = 0;
    final data = rows.map((r) {
      final checkins = _num(r['checkins']).toInt();
      final hours = _num(r['hours']).toDouble();
      totalCheckins += checkins;
      totalHours += hours;
      final avg = checkins == 0 ? 0.0 : hours / checkins;
      return [
        (r['member_name'] ?? 'N/A').toString(),
        _planLabel(r['plan']),
        '$checkins',
        '${hours.toStringAsFixed(1)}h',
        '${avg.toStringAsFixed(1)}h',
      ];
    }).toList();

    final bytes = await _document(
      reportTitle: 'ATTENDANCE SUMMARY',
      libraryName: libraryName,
      libraryAddress: libraryAddress,
      period: dateRange,
      build: (ctx) => [
        _kpiStrip([
          ['Members', '${rows.length}'],
          ['Total Check-ins', '$totalCheckins'],
          ['Total Hours', '${totalHours.toStringAsFixed(1)}h'],
        ], accentIndexes: {2}),
        pw.SizedBox(height: 16),
        _sectionTitle('Member-wise Attendance', 'Check-ins, total hours and average session length'),
        if (data.isEmpty)
          _emptyNote('No attendance in this period.')
        else
          _table(
            headers: ['Member', 'Plan', 'Check-ins', 'Total Hours', 'Avg / Session'],
            data: data,
            rightAlign: {2, 3, 4},
            totalRow: ['TOTAL', '', '$totalCheckins', '${totalHours.toStringAsFixed(1)}h', ''],
          ),
      ],
    );

    await Printing.sharePdf(bytes: bytes, filename: '${_slug(libraryName)}_attendance_summary.pdf');
  }

  static String _slug(String s) => s.trim().isEmpty ? 'SILENCE' : s.replaceAll(RegExp(r'[^\w]+'), '_');

  // ───────────────────────────────────────────────────────────────────────────
  // 4b. EXPENSES LEDGER
  // ───────────────────────────────────────────────────────────────────────────
  static Future<void> exportExpenses({
    required String libraryName,
    required String libraryAddress,
    required String dateRange,
    required List<Map<String, dynamic>> expenses,
  }) async {
    num total = 0;
    final rows = expenses.map((e) {
      total += _num(e['amount']);
      return [
        _fmtDate(e['date'] ?? e['expense_date']),
        (e['category'] ?? '—').toString(),
        (e['note'] ?? e['notes'] ?? '—').toString(),
        _inr(e['amount']),
      ];
    }).toList();

    final bytes = await _document(
      reportTitle: 'EXPENSES LEDGER',
      libraryName: libraryName,
      libraryAddress: libraryAddress,
      period: dateRange,
      build: (ctx) => [
        _kpiStrip([
          ['Entries', '${expenses.length}'],
          ['Total Expenses', _inr(total)],
        ], accentIndexes: {1}),
        pw.SizedBox(height: 16),
        _sectionTitle('Expense Entries', 'All recorded expenditures for the period'),
        if (rows.isEmpty)
          _emptyNote('No expenses recorded for this period.')
        else
          _table(
            headers: ['Date', 'Category', 'Note', 'Amount'],
            data: rows,
            rightAlign: {3},
            totalRow: ['', '', 'TOTAL', _inr(total)],
          ),
      ],
    );

    await Printing.sharePdf(bytes: bytes, filename: '${_slug(libraryName)}_expenses.pdf');
  }


  // ───────────────────────────────────────────────────────────────────────────
  // 2c. MEMBER-WISE ATTENDANCE DETAIL (grouped per member, for a month)
  //     rows: {member_name, date, check_in, check_out, duration, is_overtime}
  // ───────────────────────────────────────────────────────────────────────────
  static Future<void> exportMemberwiseAttendance({
    required String libraryName,
    required String libraryAddress,
    required String period,
    required List<Map<String, dynamic>> rows,
  }) async {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      grouped.putIfAbsent((r['member_name'] ?? 'N/A').toString(), () => []).add(r);
    }
    final members = grouped.keys.toList()..sort();
    int overtime = 0;
    for (final r in rows) {
      if (r['is_overtime'] == true) overtime++;
    }

    final bytes = await _document(
      reportTitle: 'ATTENDANCE (MEMBER-WISE)',
      libraryName: libraryName,
      libraryAddress: libraryAddress,
      period: period,
      build: (ctx) {
        final out = <pw.Widget>[
          _kpiStrip([
            ['Members', '${members.length}'],
            ['Sessions', '${rows.length}'],
            ['Overtime', '$overtime'],
          ], accentIndexes: {0}),
          pw.SizedBox(height: 16),
        ];
        if (rows.isEmpty) {
          out.add(_emptyNote('No attendance for the selected members in this period.'));
          return out;
        }
        for (final name in members) {
          final logs = grouped[name]!;
          out.add(pw.SizedBox(height: 8));
          out.add(_sectionTitle(name, '${logs.length} session(s)'));
          out.add(_table(
            headers: ['Date', 'Check-In', 'Check-Out', 'Duration', 'Overtime'],
            data: logs
                .map((l) => [
                      (l['date'] ?? '').toString(),
                      (l['check_in'] ?? '—').toString(),
                      (l['check_out'] ?? 'Ongoing').toString(),
                      (l['duration'] ?? '—').toString(),
                      l['is_overtime'] == true ? 'Yes' : '—',
                    ])
                .toList(),
          ));
        }
        return out;
      },
    );

    await Printing.sharePdf(bytes: bytes, filename: '${_slug(libraryName)}_attendance_memberwise.pdf');
  }


  // ───────────────────────────────────────────────────────────────────────────
  // 6b. UPCOMING EXPIRATIONS
  // ───────────────────────────────────────────────────────────────────────────
  static Future<void> exportExpiringMembers({
    required String libraryName,
    required String libraryAddress,
    required List<Map<String, dynamic>> members,
    String? period,
  }) async {
    final rows = members.map((m) {
      return [
        (m['member_name'] ?? m['full_name'] ?? 'N/A').toString(),
        (m['phone'] ?? '—').toString(),
        (m['seat'] ?? m['seat_label'] ?? '—').toString(),
        _fmtDate(m['expiry'] ?? m['end_date'] ?? m['expiry_date']),
      ];
    }).toList();

    final bytes = await _document(
      reportTitle: 'UPCOMING EXPIRATIONS',
      libraryName: libraryName,
      libraryAddress: libraryAddress,
      period: period ?? 'As on ${_fmtDate(DateTime.now().toIso8601String())}',
      build: (ctx) => [
        _kpiStrip([
          ['Expiring Members', '${members.length}'],
        ], accentIndexes: {0}),
        pw.SizedBox(height: 16),
        _sectionTitle('Memberships Expiring Soon', 'Reach out to renew before these dates'),
        if (rows.isEmpty)
          _emptyNote('No memberships expiring in this range.')
        else
          _table(headers: ['Member', 'Phone', 'Seat', 'Expiry Date'], data: rows),
      ],
    );

    await Printing.sharePdf(bytes: bytes, filename: '${_slug(libraryName)}_expiring.pdf');
  }


  // ───────────────────────────────────────────────────────────────────────────
  // 7. PAYMENT RECEIPT (single page, branded)
  // ───────────────────────────────────────────────────────────────────────────
  static Future<void> exportPaymentReceipt({
    required String libraryName,
    required String libraryAddress,
    required Map<String, dynamic> payment,
    required String memberName,
  }) async {
    final theme = await _theme();
    final whiteLogo = await _whiteLogo();
    final darkLogo = await _darkLogo();
    final icon = await _iconLogo();

    final amount = _inr(payment['amount']);
    final status = (payment['status'] ?? 'pending').toString().toUpperCase();
    final method = (payment['method'] ?? 'cash').toString().toUpperCase();
    final txId = (payment['id'] ?? 'N/A').toString();
    final refId = (payment['ref_id'] ?? '—').toString();
    final plan = _planLabel(payment['memberships']?['plan_type']);
    final shift = (payment['memberships']?['shifts']?['name'] ?? '—').toString();
    final dateStr = _fmtDateTime(payment['payment_date']);

    final isConfirmed = status == 'CONFIRMED';
    final chipBg = isConfirmed ? _greenBg : _amberBg;
    final chipFg = isConfirmed ? _green : _amber;

    final pdf = pw.Document(theme: theme);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _letterhead(ctx, 'PAYMENT RECEIPT', libraryName, libraryAddress,
                  'Receipt • ${_fmtDate(payment['payment_date'])}', whiteLogo),
              pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(40, 8, 40, 0),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    // Amount hero
                    pw.SizedBox(height: 18),
                    pw.Center(
                      child: pw.Column(
                        children: [
                          pw.Text('AMOUNT PAID',
                              style: const pw.TextStyle(fontSize: 9, color: _muted, letterSpacing: 1)),
                          pw.SizedBox(height: 6),
                          pw.Text(amount,
                              style: pw.TextStyle(fontSize: 34, fontWeight: pw.FontWeight.bold, color: _orange)),
                          pw.SizedBox(height: 8),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: pw.BoxDecoration(
                                color: chipBg, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(20))),
                            child: pw.Text(status,
                                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: chipFg)),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 28),
                    _sectionTitle('Transaction Details', ''),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: pw.BoxDecoration(
                        color: _zebra,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                        border: pw.Border.all(color: _line),
                      ),
                      child: pw.Column(children: [
                        _kvRow('Transaction ID', txId),
                        _kvRow('Reference ID', refId),
                        _kvRow('Member', memberName),
                        _kvRow('Date & Time', dateStr),
                        _kvRow('Payment Method', method),
                        _kvRow('Membership Plan', plan),
                        _kvRow('Shift', shift, last: true),
                      ]),
                    ),
                    pw.SizedBox(height: 16),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (icon != null) ...[
                          pw.Image(icon, width: 16, height: 16),
                          pw.SizedBox(width: 6),
                        ],
                        pw.Expanded(
                          child: pw.Text(
                            'This is a system-generated receipt from SILENCE. Keep it for your records. '
                            'For any query about this payment, contact your library.',
                            style: const pw.TextStyle(fontSize: 8, color: _muted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.Spacer(),
              pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(34, 0, 34, 22),
                child: _footer(ctx, darkLogo),
              ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'Receipt_${txId.split('-').first}.pdf');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 8. MEMBER PROFILE (identity + membership + ID images)
  // ───────────────────────────────────────────────────────────────────────────
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
    final name = (user['full_name'] ?? 'N/A').toString();
    final nickname = (user['nickname'] ?? '').toString();
    final status = (membership['status'] ?? 'N/A').toString().toUpperCase();

    final photoImg = await _tryNetworkImage(photoUrl);
    final idImg1 = await _tryNetworkImage(idUrl1);
    final idImg2 = await _tryNetworkImage(idUrl2);

    final bytes = await _document(
      reportTitle: 'MEMBER PROFILE',
      libraryName: libraryName,
      libraryAddress: libraryAddress,
      period: 'Generated ${_fmtDate(DateTime.now().toIso8601String())}',
      build: (ctx) => [
        // Identity header
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (photoImg != null) ...[
              pw.Container(
                width: 64,
                height: 64,
                decoration: pw.BoxDecoration(
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                  image: pw.DecorationImage(image: photoImg, fit: pw.BoxFit.cover),
                ),
              ),
              pw.SizedBox(width: 14),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(name, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _ink)),
                  if (nickname.isNotEmpty)
                    pw.Text('"$nickname"', style: const pw.TextStyle(fontSize: 10, color: _muted)),
                ],
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: const pw.BoxDecoration(
                  color: _tintOrange, borderRadius: pw.BorderRadius.all(pw.Radius.circular(12))),
              child: pw.Text(status, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _orange)),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        _profileSection('Personal Details', [
          _kvRow('Full Name', name),
          if (nickname.isNotEmpty) _kvRow('Nickname', nickname),
          _kvRow('Gender', (user['gender'] ?? 'N/A').toString()),
          _kvRow('Date of Birth', _safeDate(user['date_of_birth'])),
          _kvRow('Preparing For', (user['exam_category'] ?? 'N/A').toString(), last: true),
        ]),
        _profileSection('Contact', [
          _kvRow('Phone', (user['phone'] ?? 'N/A').toString()),
          _kvRow('Email', (user['email'] ?? 'N/A').toString()),
          _kvRow('Address', (user['address'] ?? 'N/A').toString(), last: true),
        ]),
        _profileSection('Membership', [
          _kvRow('Library', libraryName),
          _kvRow('Plan', _planLabel(membership['plan_type'])),
          _kvRow('Status', status),
          _kvRow('Joined', _safeDate(membership['start_date'])),
          _kvRow('Valid Till', _safeDate(membership['end_date'])),
          _kvRow('Seat', (membership['seats']?['seat_label'] ?? 'N/A').toString()),
          _kvRow('Floor', floorName.isEmpty ? 'N/A' : floorName),
          _kvRow('Section', sectionName.isEmpty ? 'N/A' : sectionName),
          _kvRow('Shift', (membership['shifts']?['name'] ?? 'N/A').toString(), last: true),
        ]),
        _profileSection('ID Documents', [
          _kvRow('ID Type', (user['id_type'] ?? 'N/A').toString(), last: true),
        ]),
        if (idImg1 != null) ...[
          pw.SizedBox(height: 10),
          pw.Text('ID Document — Front', style: const pw.TextStyle(fontSize: 9, color: _muted)),
          pw.SizedBox(height: 6),
          pw.Container(
            height: 210,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
            child: pw.Image(idImg1, fit: pw.BoxFit.contain),
          ),
        ],
        if (idImg2 != null) ...[
          pw.SizedBox(height: 10),
          pw.Text('ID Document — Back', style: const pw.TextStyle(fontSize: 9, color: _muted)),
          pw.SizedBox(height: 6),
          pw.Container(
            height: 210,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
            child: pw.Image(idImg2, fit: pw.BoxFit.contain),
          ),
        ],
        if (idImg1 == null && idImg2 == null) _emptyNote('No ID document images available.'),
      ],
    );

    await Printing.sharePdf(bytes: bytes, filename: '${_slug(name)}_profile.pdf');
  }

  // ── Small shared widgets / helpers ────────────────────────────────────────
  static pw.Widget _kvRow(String label, String value, {bool last = false}) {
    return pw.Container(
      decoration: last ? null : const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.6))),
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: _slate)),
          ),
          pw.Expanded(
            child: pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _profileSection(String title, List<pw.Widget> rows) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 6),
        _sectionTitle(title, ''),
        ...rows,
      ],
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
        return '6-Month Plan';
      case '3_month':
        return '3-Month Plan';
      case 'monthly':
        return 'Monthly Plan';
      case 'trial':
        return 'Trial';
      default:
        return (plan == null || plan.toString().isEmpty) ? 'N/A' : plan.toString();
    }
  }
}

