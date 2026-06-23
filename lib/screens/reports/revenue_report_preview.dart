import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/calendar_picker.dart';
import '../../utils/pdf_exporter.dart';
import '../../utils/csv_exporter.dart';
import '../../widgets/app_gradient_scaffold.dart';

enum RevenueReportType { revenue, payments, expenses }

/// Preview-then-export screen for the admin Revenue tab reports (Revenue P&L,
/// Payments ledger, Expenses). Has its own date filter; the export buttons emit
/// exactly the previewed (filtered) data through the shared engines.
class RevenueReportPreviewScreen extends StatefulWidget {
  final String libraryId;
  final String libraryName;
  final String libraryAddress;
  final RevenueReportType type;

  const RevenueReportPreviewScreen({
    super.key,
    required this.libraryId,
    required this.libraryName,
    required this.libraryAddress,
    required this.type,
  });

  @override
  State<RevenueReportPreviewScreen> createState() => _RevenueReportPreviewScreenState();
}

class _RevenueReportPreviewScreenState extends State<RevenueReportPreviewScreen> {
  final _supabase = Supabase.instance.client;
  static const _orange = Color(0xFFE65C00);
  final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  bool _loading = true;
  bool _exporting = false;
  String? _error;

  String _preset = 'This Month';
  DateTime _start = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _end = DateTime.now();

  List<Map<String, dynamic>> _rows = [];

  String get _title => switch (widget.type) {
        RevenueReportType.revenue => 'Revenue & Expenses',
        RevenueReportType.payments => 'Payments Ledger',
        RevenueReportType.expenses => 'Expenses',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _applyPreset(String p) {
    final now = DateTime.now();
    setState(() {
      _preset = p;
      if (p == 'Today') {
        _start = DateTime(now.year, now.month, now.day);
        _end = now;
      } else if (p == 'This Week') {
        final s = now.subtract(Duration(days: now.weekday - 1));
        _start = DateTime(s.year, s.month, s.day);
        _end = now;
      } else if (p == 'This Month') {
        _start = DateTime(now.year, now.month, 1);
        _end = now;
      }
    });
    _load();
  }

  Future<void> _pickCustom() async {
    final s = await showCalendarGridBottomSheet(context, initialDate: _start, firstDate: DateTime(2024), lastDate: DateTime.now());
    if (!mounted || s == null) return;
    final e = await showCalendarGridBottomSheet(context, initialDate: _end.isBefore(s) ? s : _end, firstDate: s, lastDate: DateTime.now());
    if (!mounted || e == null) return;
    setState(() {
      _preset = 'Custom';
      _start = s;
      _end = e.isBefore(s) ? s : e;
    });
    _load();
  }

  DateTime get _rangeStart => DateTime(_start.year, _start.month, _start.day);
  DateTime get _rangeEndExcl => DateTime(_end.year, _end.month, _end.day + 1);
  String get _periodLabel {
    final df = DateFormat('dd MMM yyyy');
    return '${df.format(_start)} – ${df.format(_end)}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      switch (widget.type) {
        case RevenueReportType.revenue:
          _rows = await _fetchRevenue();
          break;
        case RevenueReportType.payments:
          _rows = await _fetchPayments();
          break;
        case RevenueReportType.expenses:
          _rows = await _fetchExpenses();
          break;
      }
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRevenue() async {
    final payRows = await _supabase
        .from('payments')
        .select('amount, method, payment_date')
        .eq('library_id', widget.libraryId)
        .eq('status', 'confirmed')
        .gte('payment_date', _rangeStart.toIso8601String())
        .lt('payment_date', _rangeEndExcl.toIso8601String());

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
    try {
      final expRows = await _supabase
          .from('expenditures')
          .select('amount, expense_date')
          .eq('library_id', widget.libraryId)
          .gte('expense_date', _rangeStart.toIso8601String())
          .lt('expense_date', _rangeEndExcl.toIso8601String());
      for (final r in List<Map<String, dynamic>>.from(expRows)) {
        final date = (r['expense_date'] ?? '').toString().split('T').first;
        if (date.isEmpty) continue;
        final e = byDate.putIfAbsent(date, () => {'revenue': 0, 'cash': 0, 'upi': 0, 'expenses': 0});
        e['expenses'] = e['expenses']! + ((r['amount'] as num?) ?? 0);
      }
    } catch (_) {}

    final dates = byDate.keys.toList()..sort();
    return dates.map((d) {
      final e = byDate[d]!;
      final rev = e['revenue'] ?? 0;
      final exp = e['expenses'] ?? 0;
      return {'date': d, 'revenue': rev, 'cash': e['cash'] ?? 0, 'upi': e['upi'] ?? 0, 'expenses': exp, 'net_profit': rev - exp};
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchPayments() async {
    final rows = await _supabase
        .from('payments')
        .select('id, amount, method, payment_date, status, member_id(full_name)')
        .eq('library_id', widget.libraryId)
        .gte('payment_date', _rangeStart.toIso8601String())
        .lt('payment_date', _rangeEndExcl.toIso8601String())
        .order('payment_date', ascending: false);
    return List<Map<String, dynamic>>.from(rows).map((r) {
      final m = r['member_id'] is Map ? r['member_id'] as Map : {};
      return {
        'id': r['id'],
        'member_name': m['full_name'] ?? 'N/A',
        'payment_date': r['payment_date'],
        'method': r['method'] ?? 'cash',
        'status': r['status'] ?? 'pending',
        'amount': r['amount'] ?? 0,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchExpenses() async {
    final rows = await _supabase
        .from('expenditures')
        .select('amount, category, notes, expense_date')
        .eq('library_id', widget.libraryId)
        .gte('expense_date', _rangeStart.toIso8601String())
        .lt('expense_date', _rangeEndExcl.toIso8601String())
        .order('expense_date', ascending: false);
    return List<Map<String, dynamic>>.from(rows).map((r) {
      return {
        'expense_date': r['expense_date'],
        'category': r['category'] ?? 'General',
        'note': r['notes'] ?? '',
        'amount': r['amount'] ?? 0,
      };
    }).toList();
  }

  num _n(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
  String _money(dynamic v) => _inr.format(_n(v));
  String _d(dynamic iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso.toString());
    return dt == null ? iso.toString() : DateFormat('dd MMM yyyy').format(dt.toUtc().add(const Duration(hours: 5, minutes: 30)));
  }

  Future<void> _export(bool isPdf) async {
    if (_rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to export for this range.')));
      return;
    }
    setState(() => _exporting = true);
    try {
      switch (widget.type) {
        case RevenueReportType.revenue:
          isPdf
              ? await PdfExporter.exportRevenueSummary(libraryName: widget.libraryName, libraryAddress: widget.libraryAddress, dateRange: _periodLabel, summary: _rows)
              : await CsvExporter.exportRevenueSummary(libraryName: widget.libraryName, summary: _rows, period: _periodLabel);
          break;
        case RevenueReportType.payments:
          isPdf
              ? await PdfExporter.exportPayments(libraryName: widget.libraryName, libraryAddress: widget.libraryAddress, dateRange: _periodLabel, payments: _rows)
              : await CsvExporter.exportPayments(libraryName: widget.libraryName, payments: _rows, period: _periodLabel);
          break;
        case RevenueReportType.expenses:
          isPdf
              ? await PdfExporter.exportExpenses(libraryName: widget.libraryName, libraryAddress: widget.libraryAddress, dateRange: _periodLabel, expenses: _rows)
              : await CsvExporter.exportExpenses(libraryName: widget.libraryName, expenses: _rows, period: _periodLabel);
          break;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientScaffold(
      title: _title,
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _orange))
                : _error != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not load: $_error', textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.grey))))
                    : _rows.isEmpty
                        ? _empty()
                        : _buildPreview(),
          ),
          _exportBar(),
        ],
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.receipt_long_rounded, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No data for this period', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey[500])),
          ]),
        ),
      );

  Widget _buildFilterBar() {
    Widget chip(String p) {
      final sel = _preset == p;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => p == 'Custom' ? _pickCustom() : _applyPreset(p),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? _orange : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(p, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: sel ? Colors.white : const Color(0xFF475569))),
          ),
        ),
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 36,
            child: ListView(scrollDirection: Axis.horizontal, children: [chip('Today'), chip('This Week'), chip('This Month'), chip('Custom')]),
          ),
          const SizedBox(height: 8),
          Text('Period: $_periodLabel', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    switch (widget.type) {
      case RevenueReportType.revenue:
        num tRev = 0, tExp = 0, tNet = 0;
        for (final r in _rows) {
          tRev += _n(r['revenue']);
          tExp += _n(r['expenses']);
          tNet += _n(r['net_profit']);
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _kpis([['Revenue', _money(tRev)], ['Expenses', _money(tExp)], ['Net', _money(tNet)]], 2),
            const SizedBox(height: 12),
            ..._rows.map((r) => _row3(_d(r['date']), 'Rev ${_money(r['revenue'])} • Exp ${_money(r['expenses'])}', _money(r['net_profit']))),
          ],
        );
      case RevenueReportType.payments:
        num collected = 0, pending = 0;
        for (final r in _rows) {
          final s = (r['status'] ?? '').toString().toLowerCase();
          if (s == 'confirmed') collected += _n(r['amount']);
          if (s == 'pending') pending += _n(r['amount']);
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _kpis([['Collected', _money(collected)], ['Pending', _money(pending)], ['Count', '${_rows.length}']], 0),
            const SizedBox(height: 12),
            ..._rows.map((r) => _row3('${r['member_name']}', '${_d(r['payment_date'])} • ${(r['method'] ?? '').toString().toUpperCase()} • ${(r['status'] ?? '').toString().toUpperCase()}', _money(r['amount']))),
          ],
        );
      case RevenueReportType.expenses:
        num total = 0;
        for (final r in _rows) {
          total += _n(r['amount']);
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _kpis([['Entries', '${_rows.length}'], ['Total', _money(total)]], 1),
            const SizedBox(height: 12),
            ..._rows.map((r) => _row3('${r['category']}', '${_d(r['expense_date'])}${(r['note'] ?? '').toString().isNotEmpty ? ' • ${r['note']}' : ''}', _money(r['amount']))),
          ],
        );
    }
  }

  Widget _kpis(List<List<String>> kpis, int accent) {
    return Row(
      children: [
        for (int i = 0; i < kpis.length; i++) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              decoration: BoxDecoration(
                color: i == accent ? const Color(0xFFFFF3ED) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: i == accent ? _orange : const Color(0xFFE2E8F0)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kpis[i][1], style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: i == accent ? _orange : const Color(0xFF1E293B))),
                Text(kpis[i][0], style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[500])),
              ]),
            ),
          ),
          if (i != kpis.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }

  Widget _row3(String title, String subtitle, String trailing) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
              const SizedBox(height: 2),
              Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
            ]),
          ),
          const SizedBox(width: 10),
          Text(trailing, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: _orange)),
        ],
      ),
    );
  }

  Widget _exportBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _exporting ? null : () => _export(false),
              icon: const Icon(Icons.table_chart_outlined, size: 18),
              label: const Text('Export CSV'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _orange,
                side: const BorderSide(color: _orange),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _exporting ? null : () => _export(true),
              icon: _exporting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(_exporting ? 'Working…' : 'Export PDF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
