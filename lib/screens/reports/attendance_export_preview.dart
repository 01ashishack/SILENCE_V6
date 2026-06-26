import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/calendar_picker.dart';
import '../../utils/pdf_exporter.dart';
import '../../utils/csv_exporter.dart';
import '../../widgets/app_gradient_scaffold.dart';

enum AttendanceExportMode { dateWise, memberWise }

/// Preview-then-export screen for admin attendance reports.
///
/// • Date-wise: pick a day or range → every member's attendance that day
///   (name, seat, check-in, check-out, duration, overtime).
/// • Member-wise: pick a month + one/more/all members → each selected member's
///   sessions for the month (date, check-in, check-out, duration, overtime).
class AttendanceExportPreviewScreen extends StatefulWidget {
  final String libraryId;
  final String libraryName;
  final String libraryAddress;
  final AttendanceExportMode mode;

  const AttendanceExportPreviewScreen({
    super.key,
    required this.libraryId,
    required this.libraryName,
    required this.libraryAddress,
    required this.mode,
  });

  @override
  State<AttendanceExportPreviewScreen> createState() => _AttendanceExportPreviewScreenState();
}

class _AttendanceExportPreviewScreenState extends State<AttendanceExportPreviewScreen> {
  final _supabase = Supabase.instance.client;
  static const _orange = Color(0xFFE65C00);

  bool _loading = true;
  bool _exporting = false;
  String? _error;

  // Date-wise range
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();

  // Member-wise
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  // Each member: {id, name, shift, floor, category}
  List<Map<String, dynamic>> _members = [];
  // Facet filters (selected values). Empty set on a facet = "all" for that facet.
  final Set<String> _selShifts = {};
  final Set<String> _selFloors = {};
  final Set<String> _selCategories = {};
  // Manual member narrowing within the facet result; null = follow facets.
  Set<String>? _memberOverride;

  // Loaded attendance (raw)
  List<Map<String, dynamic>> _rows = [];

  bool get _isDateWise => widget.mode == AttendanceExportMode.dateWise;

  @override
  void initState() {
    super.initState();
    _start = DateTime(_start.year, _start.month, _start.day);
    _end = DateTime(_end.year, _end.month, _end.day);
    _init();
  }

  Future<void> _init() async {
    if (_isDateWise) {
      await _loadData();
    } else {
      await _loadMembers();
      await _loadData();
    }
  }

  Future<void> _loadMembers() async {
    try {
      // Floor id → name for the library.
      final floorRows = await _supabase.from('floors').select('id, name').eq('library_id', widget.libraryId);
      final floorNames = <String, String>{};
      for (final f in List<Map<String, dynamic>>.from(floorRows)) {
        floorNames[f['id'].toString()] = (f['name'] ?? 'Floor').toString();
      }

      final rows = await _supabase
          .from('memberships')
          .select('shift_id, shifts(name), seats(floor_id), member_id(id, full_name, exam_category)')
          .eq('library_id', widget.libraryId);

      final seen = <String>{};
      final list = <Map<String, dynamic>>[];
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final m = r['member_id'];
        if (m is! Map) continue;
        final id = m['id']?.toString();
        if (id == null || seen.contains(id)) continue;
        seen.add(id);
        final seat = r['seats'] is Map ? r['seats'] as Map : {};
        final floorId = seat['floor_id']?.toString();
        list.add({
          'id': id,
          'name': (m['full_name'] ?? 'Member').toString(),
          'shift': (r['shifts'] is Map ? r['shifts']['name'] : null)?.toString() ?? 'No shift',
          'floor': floorId != null ? (floorNames[floorId] ?? 'Floor') : 'No floor',
          'category': (m['exam_category'] ?? '').toString().trim().isEmpty ? 'Uncategorized' : m['exam_category'].toString(),
        });
      }
      list.sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
      _members = list;
      // Default: every facet "all" (empty set) → all members included.
      _selShifts.clear();
      _selFloors.clear();
      _selCategories.clear();
      _memberOverride = null;
    } catch (e) {
      _error = 'Could not load members: $e';
    }
  }

  // Distinct facet values.
  List<String> get _shiftOptions => _members.map((m) => m['shift'] as String).toSet().toList()..sort();
  List<String> get _floorOptions => _members.map((m) => m['floor'] as String).toSet().toList()..sort();
  List<String> get _categoryOptions => _members.map((m) => m['category'] as String).toSet().toList()..sort();

  bool _facetPasses(Map<String, dynamic> m) {
    if (_selShifts.isNotEmpty && !_selShifts.contains(m['shift'])) return false;
    if (_selFloors.isNotEmpty && !_selFloors.contains(m['floor'])) return false;
    if (_selCategories.isNotEmpty && !_selCategories.contains(m['category'])) return false;
    return true;
  }

  /// Members passing the facet filters (Shift/Floor/Category).
  List<Map<String, dynamic>> get _facetMembers => _members.where(_facetPasses).toList();

  /// Final selected member ids = facet members, optionally narrowed by manual
  /// member-checklist selection.
  Set<String> get _effectiveMemberIds {
    final facetIds = _facetMembers.map((m) => m['id'] as String).toSet();
    if (_memberOverride == null) return facetIds;
    return facetIds.intersection(_memberOverride!);
  }

  DateTime get _periodStart => _isDateWise
      ? DateTime(_start.year, _start.month, _start.day)
      : DateTime(_month.year, _month.month, 1);
  DateTime get _periodEndExclusive => _isDateWise
      ? DateTime(_end.year, _end.month, _end.day + 1)
      : DateTime(_month.year, _month.month + 1, 1);

  String get _periodLabel {
    if (_isDateWise) {
      final df = DateFormat('dd MMM yyyy');
      return _start == _end ? df.format(_start) : '${df.format(_start)} – ${df.format(_end)}';
    }
    return DateFormat('MMMM yyyy').format(_month);
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var q = _supabase
          .from('attendance')
          .select('check_in_time, check_out_time, duration_minutes, session_type, is_overtime, '
              'member_id(id, full_name), memberships(seats(seat_label)), shifts(name)')
          .eq('library_id', widget.libraryId)
          .gte('check_in_time', _periodStart.toIso8601String())
          .lt('check_in_time', _periodEndExclusive.toIso8601String());

      if (!_isDateWise) {
        final ids = _effectiveMemberIds;
        if (ids.isEmpty) {
          setState(() {
            _rows = [];
            _loading = false;
          });
          return;
        }
        q = q.inFilter('member_id', ids.toList());
      }

      final res = await q.order('check_in_time', ascending: true);
      _rows = List<Map<String, dynamic>>.from(res);
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── formatting helpers (IST) ───────────────────────────────────────────────
  DateTime _ist(String iso) => DateTime.parse(iso).toUtc().add(const Duration(hours: 5, minutes: 30));
  String _t(dynamic iso) => iso == null ? '—' : DateFormat('hh:mm a').format(_ist(iso.toString()));
  String _d(dynamic iso) => iso == null ? '—' : DateFormat('dd MMM yyyy').format(_ist(iso.toString()));

  String _durationOf(Map<String, dynamic> r) {
    int mins = (r['duration_minutes'] as num?)?.toInt() ?? 0;
    if (mins == 0 && r['check_in_time'] != null && r['check_out_time'] != null) {
      mins = DateTime.parse(r['check_out_time']).difference(DateTime.parse(r['check_in_time'])).inMinutes;
    }
    if (r['check_out_time'] == null) return 'Ongoing';
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  String _seatOf(Map<String, dynamic> r) {
    final ms = r['memberships'];
    final seat = ms is Map ? ms['seats'] : null;
    return (seat is Map ? seat['seat_label'] : null)?.toString() ?? '—';
  }

  String _nameOf(Map<String, dynamic> r) =>
      (r['member_id'] is Map ? r['member_id']['full_name'] : null)?.toString() ?? 'N/A';

  // ── exports ─────────────────────────────────────────────────────────────-─
  Future<void> _export(bool isPdf) async {
    if (_rows.isEmpty) {
      _toast('Nothing to export for this selection.');
      return;
    }
    setState(() => _exporting = true);
    try {
      if (_isDateWise) {
        final logs = _rows
            .map((r) => {
                  'member_name': _nameOf(r),
                  'seat_label': _seatOf(r),
                  'shift_name': (r['shifts'] is Map ? r['shifts']['name'] : null) ?? '—',
                  'check_in_time': r['check_in_time'],
                  'check_out_time': r['check_out_time'],
                  'duration_minutes': r['duration_minutes'],
                  'session_type': r['session_type'] ?? 'normal',
                  'is_overtime': r['is_overtime'] == true,
                })
            .toList();
        isPdf
            ? await PdfExporter.exportAttendance(
                libraryName: widget.libraryName, libraryAddress: widget.libraryAddress, dateRange: _periodLabel, logs: logs)
            : await CsvExporter.exportAttendance(libraryName: widget.libraryName, logs: logs, period: _periodLabel);
      } else {
        final rows = _rows
            .map((r) => {
                  'member_name': _nameOf(r),
                  'date': _d(r['check_in_time']),
                  'check_in': _t(r['check_in_time']),
                  'check_out': r['check_out_time'] != null ? _t(r['check_out_time']) : 'Ongoing',
                  'duration': _durationOf(r),
                  'is_overtime': r['is_overtime'] == true,
                })
            .toList();
        isPdf
            ? await PdfExporter.exportMemberwiseAttendance(
                libraryName: widget.libraryName, libraryAddress: widget.libraryAddress, period: _periodLabel, rows: rows)
            : await CsvExporter.exportMemberwiseAttendance(
                libraryName: widget.libraryName, period: _periodLabel, rows: rows);
      }
    } catch (e) {
      _toast('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── date / month pickers ────────────────────────────────────────────────-─
  Future<void> _pickRange() async {
    final s = await showCalendarGridBottomSheet(context,
        initialDate: _start, firstDate: DateTime(2024), lastDate: DateTime.now());
    if (!mounted || s == null) return;
    final e = await showCalendarGridBottomSheet(context,
        initialDate: _end.isBefore(s) ? s : _end, firstDate: s, lastDate: DateTime.now());
    if (!mounted || e == null) return;
    setState(() {
      _start = s;
      _end = e.isBefore(s) ? s : e;
    });
    _loadData();
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientScaffold(
      title: _isDateWise ? 'Attendance — Date-wise' : 'Attendance — Member-wise',
      body: Column(
        children: [
          _buildControls(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _orange))
                : _error != null
                    ? _buildError()
                    : _isDateWise
                        ? _buildDateWisePreview()
                        : _buildMemberWisePreview(),
          ),
          _buildExportBar(),
        ],
      ),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 44),
            const SizedBox(height: 12),
            Text('Could not load attendance', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            Text('$_error', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(backgroundColor: _orange, foregroundColor: Colors.white),
              child: const Text('Retry'),
            ),
          ]),
        ),
      );

  Widget _buildControls() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: _isDateWise
          ? InkWell(
              onTap: _pickRange,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.date_range_rounded, size: 18, color: _orange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Date: $_periodLabel',
                          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.palette.textPrimary)),
                    ),
                    Text('Change', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _orange)),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                // Month stepper
                Row(
                  children: [
                    IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left, color: _orange)),
                    Expanded(
                      child: Text(DateFormat('MMMM yyyy').format(_month),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
                    ),
                    IconButton(
                      onPressed: (_month.year == DateTime.now().year && _month.month == DateTime.now().month)
                          ? null
                          : () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_right, color: _orange),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _buildMemberSelector(),
              ],
            ),
    );
  }

  Widget _buildMemberSelector() {
    final facetCount = _facetMembers.length;
    final effective = _effectiveMemberIds.length;
    String lbl(String name, Set<String> sel) => sel.isEmpty ? '$name: All' : '$name: ${sel.length}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _facetChip(lbl('Shift', _selShifts), () => _openFacetSheet('Shift', _shiftOptions, _selShifts)),
              _facetChip(lbl('Floor', _selFloors), () => _openFacetSheet('Floor', _floorOptions, _selFloors)),
              _facetChip(lbl('Category', _selCategories), () => _openFacetSheet('Category', _categoryOptions, _selCategories)),
              _facetChip('Members: ${_memberOverride == null ? 'All ($facetCount)' : '$effective/$facetCount'}', _openMemberSheet),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text('$effective member(s) selected', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  Widget _facetChip(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3ED),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _orange.withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _orange)),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 16, color: _orange),
          ]),
        ),
      ),
    );
  }

  /// Generic facet checklist (All + values). Empty selection set = "All".
  Future<void> _openFacetSheet(String title, List<String> options, Set<String> selected) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          final allSelected = selected.isEmpty || selected.length == options.length;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(children: [
                    Expanded(child: Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold))),
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
                  ]),
                ),
                CheckboxListTile(
                  value: allSelected,
                  activeColor: _orange,
                  title: Text('All', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  onChanged: (v) {
                    setSheet(() => selected.clear()); // empty = all
                    setState(() {
                      _memberOverride = null;
                    });
                    _loadData();
                  },
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: options.map((o) {
                      final checked = selected.isEmpty ? true : selected.contains(o);
                      return CheckboxListTile(
                        value: checked,
                        activeColor: _orange,
                        title: Text(o, style: GoogleFonts.inter(fontSize: 13.5)),
                        onChanged: (v) {
                          setSheet(() {
                            // Materialise the "all" set first so we can deselect one.
                            if (selected.isEmpty) selected.addAll(options);
                            if (v == true) {
                              selected.add(o);
                            } else {
                              selected.remove(o);
                            }
                            if (selected.length == options.length) selected.clear(); // back to "all"
                          });
                          setState(() => _memberOverride = null);
                          _loadData();
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  /// Member checklist (within current facets). Default all checked.
  Future<void> _openMemberSheet() async {
    final facetMembers = _facetMembers;
    // initialise override to current facet members (all checked) if null
    _memberOverride ??= facetMembers.map((m) => m['id'] as String).toSet();
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.palette.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          final ids = facetMembers.map((m) => m['id'] as String).toSet();
          final allChecked = _memberOverride!.containsAll(ids) && ids.isNotEmpty;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(children: [
                      Expanded(child: Text('Members', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold))),
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
                    ]),
                  ),
                  CheckboxListTile(
                    value: allChecked,
                    activeColor: _orange,
                    title: Text('All', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    onChanged: (v) {
                      setSheet(() {
                        if (v == true) {
                          _memberOverride = ids.toSet();
                        } else {
                          _memberOverride = <String>{};
                        }
                      });
                      setState(() {});
                      _loadData();
                    },
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: facetMembers.map((m) {
                        final id = m['id'] as String;
                        final checked = _memberOverride!.contains(id);
                        return CheckboxListTile(
                          value: checked,
                          activeColor: _orange,
                          title: Text(m['name'] as String, style: GoogleFonts.inter(fontSize: 13.5)),
                          subtitle: Text('${m['shift']} • ${m['floor']} • ${m['category']}',
                              style: GoogleFonts.inter(fontSize: 10.5, color: Colors.grey[500])),
                          onChanged: (v) {
                            setSheet(() {
                              if (v == true) {
                                _memberOverride!.add(id);
                              } else {
                                _memberOverride!.remove(id);
                              }
                            });
                            setState(() {});
                            _loadData();
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.event_busy_rounded, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No attendance for this selection',
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey[500])),
          ]),
        ),
      );

  Widget _buildDateWisePreview() {
    if (_rows.isEmpty) return _emptyState();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _summaryBar([
          ['Sessions', '${_rows.length}'],
          ['Members', '${_rows.map(_nameOf).toSet().length}'],
          ['Overtime', '${_rows.where((r) => r['is_overtime'] == true).length}'],
        ]),
        const SizedBox(height: 12),
        ..._rows.map((r) => _previewCard(
              title: _nameOf(r),
              subtitle: 'Seat ${_seatOf(r)}  •  ${_d(r['check_in_time'])}',
              chips: [
                ['In', _t(r['check_in_time'])],
                ['Out', r['check_out_time'] != null ? _t(r['check_out_time']) : 'Ongoing'],
                ['Duration', _durationOf(r)],
              ],
              overtime: r['is_overtime'] == true,
            )),
      ],
    );
  }

  Widget _buildMemberWisePreview() {
    if (_effectiveMemberIds.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Select at least one member (adjust the filters above).',
              textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.grey[600])),
        ),
      );
    }
    if (_rows.isEmpty) return _emptyState();

    // group by member
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final r in _rows) {
      grouped.putIfAbsent(_nameOf(r), () => []).add(r);
    }
    final names = grouped.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _summaryBar([
          ['Members', '${names.length}'],
          ['Sessions', '${_rows.length}'],
          ['Overtime', '${_rows.where((r) => r['is_overtime'] == true).length}'],
        ]),
        const SizedBox(height: 12),
        ...names.map((name) {
          final logs = grouped[name]!;
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
                Text('${logs.length} session(s)', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                const Divider(height: 16),
                ...logs.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          SizedBox(width: 86, child: Text(_d(r['check_in_time']), style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600))),
                          Expanded(child: Text('${_t(r['check_in_time'])} – ${r['check_out_time'] != null ? _t(r['check_out_time']) : 'Ongoing'}', style: GoogleFonts.inter(fontSize: 11.5, color: context.palette.textSecondary))),
                          Text(_durationOf(r), style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600)),
                          if (r['is_overtime'] == true) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFFFF1F2), borderRadius: BorderRadius.circular(4)),
                              child: Text('OT', style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: const Color(0xFFE11D48))),
                            ),
                          ],
                        ],
                      ),
                    )),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _summaryBar(List<List<String>> kpis) {
    return Row(
      children: [
        for (int i = 0; i < kpis.length; i++) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              decoration: BoxDecoration(
                color: i == 2 ? const Color(0xFFFFF3ED) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: i == 2 ? _orange : const Color(0xFFE2E8F0)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kpis[i][1], style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: i == 2 ? _orange : context.palette.textPrimary)),
                Text(kpis[i][0], style: GoogleFonts.inter(fontSize: 10.5, color: Colors.grey[500])),
              ]),
            ),
          ),
          if (i != kpis.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }

  Widget _previewCard({required String title, required String subtitle, required List<List<String>> chips, required bool overtime}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary))),
              if (overtime)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFFFFF1F2), borderRadius: BorderRadius.circular(6)),
                  child: Text('OVERTIME', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.bold, color: const Color(0xFFE11D48))),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey[500])),
          const SizedBox(height: 10),
          Row(
            children: chips
                .map((c) => Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c[0].toUpperCase(), style: GoogleFonts.inter(fontSize: 9, color: Colors.grey[400], fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(c[1], style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF334155))),
                      ]),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildExportBar() {
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
