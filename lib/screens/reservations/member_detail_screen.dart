import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/error_messages.dart';
import '../../utils/audit_logger.dart';
import '../../utils/pdf_exporter.dart';
import '../../utils/attendance_format.dart';
import '../../utils/csv_exporter.dart';
import 'member_transfer_screen.dart';

class MemberDetailScreen extends StatefulWidget {
  final String? memberId;
  final bool isReadOnly;

  const MemberDetailScreen({
    super.key,
    this.memberId,
    this.isReadOnly = false,
  });

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _errorMessage;
  String? _memberId;
  bool _isReadOnly = false;

  // Core data
  Map<String, dynamic>? _membershipData;
  Map<String, dynamic>? _userProfile;
  List<Map<String, dynamic>> _attendanceList = [];
  List<Map<String, dynamic>> _paymentsList = [];
  List<Map<String, dynamic>> _allMemberships = [];

  // Number of libraries this admin owns — used to hide the "Transfer to another
  // library" action when there is nowhere to transfer to (only one library).
  int _ownedLibraryCount = 0;

  // Calendar State
  DateTime _calendarMonth = DateTime.now();

  // Attendance analytics date-range (null = default to the current month).
  DateTime? _attnRangeStart;
  DateTime? _attnRangeEnd;

  // Notes controller
  final _notesController = TextEditingController();
  bool _isSavingNote = false;

  // True while building/sharing the full-profile PDF.
  bool _isExportingPdf = false;

  // Tab state
  int _activeTab = 0;
  final List<String> _tabNames = ['Overview', 'Attendance', 'Payments', 'Activity', 'Notes'];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_memberId == null) {
      final route = ModalRoute.of(context);
      final args = route?.settings.arguments;
      if (args is String) {
        _memberId = args;
        _isReadOnly = widget.isReadOnly;
      } else if (args is Map<String, dynamic>) {
        _memberId = args['memberId'] as String? ?? args['id'] as String?;
        _isReadOnly = args['isReadOnly'] as bool? ?? widget.isReadOnly;
      } else {
        _memberId = widget.memberId;
        _isReadOnly = widget.isReadOnly;
      }
      
      if (_isReadOnly && _tabNames.contains('Notes')) {
        _tabNames.remove('Notes');
      }
      
      _fetchMemberData();
    }
  }

  // ── Fetch All Member Details ──────────────────────────────────────────────
  Future<void> _fetchMemberData() async {
    final mId = _memberId;
    if (mId == null || mId.isEmpty) {
      // No id was passed — show the error state instead of an endless spinner.
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No member was selected. Please reopen this profile from the members list.';
        });
      }
      return;
    }

    try {
      if (mounted) setState(() => _isLoading = true);

      final results = await Future.wait([
        // 1. Fetch user profile
        supabase
            .from('users')
            .select()
            .eq('id', mId)
            .maybeSingle(),
        // 2. Fetch current membership with relations
        supabase
            .from('memberships')
            .select('*, seats(seat_label, floor_id, section_id), shifts(name, price_monthly), libraries(name, address_street, address_city, address_state, address_pincode)')
            .eq('member_id', mId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle(),
        // 3. Fetch all memberships (for activity timeline)
        supabase
            .from('memberships')
            .select('*, seats(seat_label), shifts(name)')
            .eq('member_id', mId)
            .order('created_at', ascending: false),
        // 4. Fetch attendance history
        supabase
            .from('attendance')
            .select('*')
            .eq('member_id', mId)
            .order('check_in_time', ascending: false),
        // 5. Fetch payment history
        supabase
            .from('payments')
            .select('*')
            .eq('member_id', mId)
            .order('payment_date', ascending: false),
        // 6. Owned-library count — gates the Transfer action (hidden when 1).
        supabase
            .from('libraries')
            .select('id')
            .eq('owner_id', supabase.auth.currentUser?.id ?? ''),
      ]);

      if (!mounted) return;

      setState(() {
        _userProfile = results[0] as Map<String, dynamic>?;
        _membershipData = results[1] as Map<String, dynamic>?;
        _allMemberships = List<Map<String, dynamic>>.from(results[2] as List);
        _attendanceList = List<Map<String, dynamic>>.from(results[3] as List);
        _paymentsList = List<Map<String, dynamic>>.from(results[4] as List);
        _ownedLibraryCount = (results[5] as List).length;

        // Pre-populate private note
        final String userNote = _userProfile?['nickname'] ?? '';
        _notesController.text = userNote;

        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      debugPrint('Error fetching member details: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error loading member profile: $e';
        });
      }
    }
  }

  // ── Calculation Helpers ────────────────────────────────────────────────────
  int _calculateStreak() {
    if (_attendanceList.isEmpty) return 0;
    final dates = _attendanceList
        .map((a) {
          try {
            final dt = DateTime.parse(a['check_in_time']).toLocal();
            return DateTime(dt.year, dt.month, dt.day);
          } catch (_) { return null; }
        })
        .whereType<DateTime>()
        .toSet()
        .toList();
    dates.sort((a, b) => b.compareTo(a));
    if (dates.isEmpty) return 0;

    final today = DateTime.now();
    final dateToday = DateTime(today.year, today.month, today.day);
    final dateYesterday = dateToday.subtract(const Duration(days: 1));
    if (dates.first.isBefore(dateYesterday)) return 0;

    int streak = 0;
    DateTime current = dates.first;
    for (int i = 0; i < dates.length; i++) {
      if (i == 0) { streak = 1; continue; }
      final expectedPrev = current.subtract(const Duration(days: 1));
      if (dates[i] == expectedPrev) {
        streak++;
        current = dates[i];
      } else if (dates[i] == current) {
        continue;
      } else {
        break;
      }
    }
    return streak;
  }

  int _calculateThisMonthVisits() {
    final now = DateTime.now();
    return _attendanceList.where((a) {
      try {
        final dt = DateTime.parse(a['check_in_time']).toLocal();
        return dt.year == now.year && dt.month == now.month;
      } catch (_) { return false; }
    }).length;
  }

  double _calculateAvgSessionDuration() {
    final sessionsWithDuration = _attendanceList.where((a) {
      return a['check_in_time'] != null && a['check_out_time'] != null;
    }).toList();
    if (sessionsWithDuration.isEmpty) return 0.0;
    double totalMins = 0.0;
    for (final a in sessionsWithDuration) {
      try {
        final ci = DateTime.parse(a['check_in_time']);
        final co = DateTime.parse(a['check_out_time']);
        totalMins += co.difference(ci).inMinutes;
      } catch (_) {}
    }
    return totalMins / sessionsWithDuration.length / 60.0;
  }

  int _calculateTotalPaid() {
    return _paymentsList
        .where((p) => p['status'] == 'confirmed')
        .fold(0, (sum, p) => sum + ((p['amount'] as num?)?.toInt() ?? 0));
  }

  // ── Save Private Note ──────────────────────────────────────────────────────
  Future<void> _savePrivateNote() async {
    final mId = _memberId;
    if (mId == null) return;
    try {
      setState(() => _isSavingNote = true);
      await supabase.from('users').update({
        'nickname': _notesController.text.trim(),
      }).eq('id', mId);
      if (mounted) {
        setState(() => _isSavingNote = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Private admin note saved successfully! ✓')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingNote = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save note: $e')),
        );
      }
    }
  }

  // ── Confirm / Reject Payment ───────────────────────────────────────────────
  Future<void> _confirmPayment(String paymentId) async {
    try {
      setState(() => _isLoading = true);
      final currentAdminId = supabase.auth.currentUser?.id;
      await supabase.from('payments').update({
        'status': 'confirmed',
        'confirmed_by_admin_id': currentAdminId,
      }).eq('id', paymentId);

      await _notifyMemberOfPayment(
        confirmed: true,
        title: 'Payment confirmed',
        message: 'Your payment has been verified and confirmed by the admin.',
      );
      await AuditLogger.instance.log(
        action: 'payment_confirm',
        category: AuditLogger.categoryPayments,
        title: 'Confirmed payment',
        details: '${_userProfile?['full_name'] ?? 'Member'} · payment $paymentId',
        libraryId: _membershipData?['library_id']?.toString(),
      );

      await _fetchMemberData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment confirmed. Member notified.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _rejectPayment(String paymentId) async {
    try {
      setState(() => _isLoading = true);
      await supabase.from('payments').update({'status': 'rejected'}).eq('id', paymentId);

      await _notifyMemberOfPayment(
        confirmed: false,
        title: 'Payment not verified',
        message: 'Your payment could not be verified. Please re-check the '
            'transaction or contact the admin.',
      );
      await AuditLogger.instance.log(
        action: 'payment_reject',
        category: AuditLogger.categoryPayments,
        title: 'Rejected payment',
        details: '${_userProfile?['full_name'] ?? 'Member'} · payment $paymentId',
        libraryId: _membershipData?['library_id']?.toString(),
      );

      await _fetchMemberData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment marked as rejected. Member notified.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  /// Notify the member of a payment verdict. Best-effort.
  Future<void> _notifyMemberOfPayment({
    required bool confirmed,
    required String title,
    required String message,
  }) async {
    final memberId = _memberId ?? _userProfile?['id']?.toString();
    if (memberId == null) return;
    try {
      await supabase.from('notifications').insert({
        'user_id': memberId,
        'title': title,
        'body': message,
        'data': {'type': confirmed ? 'payment_confirmed' : 'payment_rejected'},
      });
    } catch (e) {
      debugPrint('payment notify failed: $e');
    }
  }

  // ── Edit Member Dialog ─────────────────────────────────────────────────────
  void _showEditMemberDialog() {
    final name = _userProfile?['full_name'] ?? '';
    final phone = _userProfile?['phone'] ?? '';
    final nameController = TextEditingController(text: name);
    final phoneController = TextEditingController(text: phone);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit Member Profile', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full Name')),
            const SizedBox(height: 12),
            TextField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty || phoneController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and phone cannot be empty')));
                return;
              }
              Navigator.pop(ctx);
              try {
                setState(() => _isLoading = true);
                await supabase.from('users').update({
                  'full_name': nameController.text.trim(),
                  'phone': phoneController.text.trim(),
                }).eq('id', _memberId ?? '');
                _fetchMemberData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member profile updated successfully! ✓')));
                }
              } catch (e) {
                if (mounted) {
                  setState(() => _isLoading = false);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating profile: $e')));
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── Manual Attendance Modal ────────────────────────────────────────────────
  void _showAttendanceModal({Map<String, dynamic>? session, required DateTime date}) {
    TimeOfDay checkInTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay checkOutTime = const TimeOfDay(hour: 17, minute: 0);
    final reasonController = TextEditingController();

    if (session != null) {
      try {
        final ci = DateTime.parse(session['check_in_time']).toLocal();
        checkInTime = TimeOfDay(hour: ci.hour, minute: ci.minute);
        if (session['check_out_time'] != null) {
          final co = DateTime.parse(session['check_out_time']).toLocal();
          checkOutTime = TimeOfDay(hour: co.hour, minute: co.minute);
        }
        reasonController.text = session['edit_reason'] ?? '';
      } catch (_) {}
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text(
                    session != null ? 'Edit Attendance Session' : 'Add Manual Attendance',
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                  ),
                  const SizedBox(height: 8),
                  Text('Date: ${DateFormat('dd MMMM yyyy').format(date)}', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600])),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Check-in Time:', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                      TextButton.icon(
                        icon: const Icon(Icons.access_time_rounded, size: 18, color: Color(0xFFE65C00)),
                        label: Text(checkInTime.format(context), style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: checkInTime);
                          if (picked != null) setModalState(() => checkInTime = picked);
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Check-out Time:', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                      TextButton.icon(
                        icon: const Icon(Icons.access_time_rounded, size: 18, color: Color(0xFFE65C00)),
                        label: Text(checkOutTime.format(context), style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: checkOutTime);
                          if (picked != null) setModalState(() => checkOutTime = picked);
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  TextField(controller: reasonController, maxLines: 2, decoration: const InputDecoration(labelText: 'Edit Reason (Required)', hintText: 'e.g. Forgot to scan out / manual addition by Admin', fillColor: Color(0xFFF8FAFC))),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () async {
                      if (reasonController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please provide an edit reason')));
                        return;
                      }
                      final checkInDateTime = DateTime(date.year, date.month, date.day, checkInTime.hour, checkInTime.minute);
                      final checkOutDateTime = DateTime(date.year, date.month, date.day, checkOutTime.hour, checkOutTime.minute);
                      if (checkOutDateTime.isBefore(checkInDateTime)) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check-out time must be after check-in time')));
                        return;
                      }
                      final int durationMins = checkOutDateTime.difference(checkInDateTime).inMinutes;
                      final currentAdminId = supabase.auth.currentUser?.id;
                      Navigator.pop(ctx);
                      try {
                        setState(() => _isLoading = true);
                        if (session != null) {
                          await supabase.from('attendance').update({
                            'check_in_time': checkInDateTime.toUtc().toIso8601String(),
                            'check_out_time': checkOutDateTime.toUtc().toIso8601String(),
                            'duration_minutes': durationMins,
                            'session_type': 'admin_edited',
                            'edited_by_admin_id': currentAdminId,
                            'edit_reason': reasonController.text.trim(),
                          }).eq('id', session['id']);
                        } else {
                          final membershipId = _membershipData?['id'];
                          final libraryId = _membershipData?['library_id'];
                          final shiftId = _membershipData?['shift_id'];
                          if (membershipId == null || libraryId == null || shiftId == null) throw 'Membership details missing.';
                          await supabase.from('attendance').insert({
                            'membership_id': membershipId,
                            'member_id': _memberId!,
                            'library_id': libraryId,
                            'shift_id': shiftId,
                            'check_in_time': checkInDateTime.toUtc().toIso8601String(),
                            'check_out_time': checkOutDateTime.toUtc().toIso8601String(),
                            'duration_minutes': durationMins,
                            'session_type': 'admin_edited',
                            'edited_by_admin_id': currentAdminId,
                            'edit_reason': reasonController.text.trim(),
                          });
                        }
                        await _fetchMemberData();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance saved successfully! ✓')));
                        }
                      } catch (e) {
                        if (context.mounted) {
                          setState(() => _isLoading = false);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving attendance: $e')));
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: Text('Save Changes', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _canHoldOrResume() {
    final s = _membershipData?['status'];
    return s == 'active' || s == 'trial' || s == 'expiring' || s == 'hold';
  }

  bool _canTransfer() {
    if (_membershipData == null || _membershipData!['library_id'] == null) return false;
    // Nowhere to transfer to if the admin owns only this one library.
    if (_ownedLibraryCount <= 1) return false;
    final s = _membershipData?['status'];
    return s == 'active' || s == 'trial' || s == 'expiring' || s == 'hold' || s == 'expired';
  }

  // ── Per-member export (CSV / PDF) ──────────────────────────────────────────
  String _fmt(String? iso, String pattern) {
    if (iso == null) return '';
    try {
      return DateFormat(pattern).format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '';
    }
  }

  void _showExportSheet() {
    final now = DateTime.now();
    DateTime rStart = DateTime(now.year, now.month, 1);
    DateTime rEnd = DateTime(now.year, now.month + 1, 0);
    bool expAttendance = true;
    bool expPayments = true;
    bool busy = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> pickRange() async {
            final picked = await showDateRangePicker(
              context: ctx,
              initialDateRange: DateTimeRange(start: rStart, end: rEnd),
              firstDate: DateTime(2024, 1, 1),
              lastDate: DateTime(now.year + 1, 12, 31),
              builder: (c, child) => Theme(
                data: Theme.of(c).copyWith(
                  colorScheme: const ColorScheme.light(
                      primary: Color(0xFFE65C00), onPrimary: Colors.white, onSurface: Color(0xFF1E293B)),
                ),
                child: child!,
              ),
            );
            if (picked != null) setSheet(() { rStart = picked.start; rEnd = picked.end; });
          }

          Future<void> run(String format) async {
            if (!expAttendance && !expPayments) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Select at least one section to export.')));
              return;
            }
            // Capture before the await so we don't touch a BuildContext across
            // the async gap (and don't setState the sheet after it's popped).
            final messenger = ScaffoldMessenger.of(context);
            final nav = Navigator.of(sheetCtx);
            setSheet(() => busy = true);
            try {
              final ok = await _runMemberExport(
                format: format, start: rStart, end: rEnd,
                includeAttendance: expAttendance, includePayments: expPayments);
              if (ok) {
                nav.pop();
                return;
              }
              setSheet(() => busy = false); // empty range: keep the sheet open
            } catch (e) {
              messenger.showSnackBar(
                SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red));
              setSheet(() => busy = false);
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.ios_share_rounded, color: Color(0xFFE65C00)),
                  const SizedBox(width: 10),
                  Text('Export member data', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                ]),
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFFE65C00),
                  controlAffinity: ListTileControlAffinity.leading,
                  value: expAttendance,
                  onChanged: busy ? null : (v) => setSheet(() => expAttendance = v ?? false),
                  title: Text('Attendance ledger', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFFE65C00),
                  controlAffinity: ListTileControlAffinity.leading,
                  value: expPayments,
                  onChanged: busy ? null : (v) => setSheet(() => expPayments = v ?? false),
                  title: Text('Payments ledger', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: busy ? null : pickRange,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7F0),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFD8BE)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.date_range_rounded, size: 18, color: Color(0xFFE65C00)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${DateFormat('dd MMM yyyy').format(rStart)}  –  ${DateFormat('dd MMM yyyy').format(rEnd)}',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                        ),
                      ),
                      Text('Change', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                if (busy)
                  const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)))))
                else
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => run('csv'),
                        icon: const Icon(Icons.table_chart_outlined, size: 18, color: Color(0xFFE65C00)),
                        label: Text('CSV (Excel)', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE65C00)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => run('pdf'),
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18, color: Colors.white),
                        label: Text('PDF', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ]),
                const SizedBox(height: 4),
              ],
            ),
          );
        });
      },
    );
  }

  /// Exports the selected sections for THIS member, filtered to [start, end],
  /// reusing the shared CSV/PDF utilities. Returns false (with an honest
  /// snackbar) when the range has nothing — so we never share an empty file.
  Future<bool> _runMemberExport({
    required String format,
    required DateTime start,
    required DateTime end,
    required bool includeAttendance,
    required bool includePayments,
  }) async {
    final sDay = DateTime(start.year, start.month, start.day);
    final eDay = DateTime(end.year, end.month, end.day);
    bool inRange(String? iso) {
      if (iso == null) return false;
      try {
        final d = DateTime.parse(iso).toLocal();
        final day = DateTime(d.year, d.month, d.day);
        return !day.isBefore(sDay) && !day.isAfter(eDay);
      } catch (_) {
        return false;
      }
    }

    final attn = includeAttendance ? _attendanceList.where((a) => inRange(a['check_in_time'])).toList() : <Map<String, dynamic>>[];
    final pays = includePayments ? _paymentsList.where((p) => inRange(p['payment_date'])).toList() : <Map<String, dynamic>>[];

    if (attn.isEmpty && pays.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to export in this date range.')));
      }
      return false;
    }

    final memberName = (_userProfile?['full_name'] ?? 'Member').toString();
    final nickname = (_userProfile?['nickname'] ?? memberName).toString();
    final seat = _membershipData?['seats']?['seat_label']?.toString() ?? '';
    final rangeLabel = '${DateFormat('dd MMM yyyy').format(sDay)} - ${DateFormat('dd MMM yyyy').format(eDay)}';

    if (format == 'csv') {
      if (attn.isNotEmpty) {
        final logs = attn.map((a) => {
              'date': _fmt(a['check_in_time'], 'dd MMM yyyy'),
              'check_in': _fmt(a['check_in_time'], 'hh:mm a'),
              'check_out': a['check_out_time'] != null ? _fmt(a['check_out_time'], 'hh:mm a') : 'Open',
              'duration': a['duration_minutes'] != null ? _fmtStudyMinutes((a['duration_minutes'] as num).toInt()) : '',
              'session_type': a['session_type'] ?? 'normal',
              'is_overtime': a['is_overtime'] == true,
              'shift': (_membershipData?['shifts']?['name'] ?? '').toString(),
              'library': '',
              'seat': seat,
            }).toList();
        await CsvExporter.exportMemberAttendance(nickname: nickname, dateRangeLabel: rangeLabel, logs: logs);
      }
      if (pays.isNotEmpty) {
        final withName = pays.map((p) => {...p, 'member_name': memberName}).toList();
        await CsvExporter.exportPayments(libraryName: memberName, payments: withName);
      }
    } else {
      if (attn.isNotEmpty) {
        final shiftName = (_membershipData?['shifts']?['name'] ?? '').toString();
        final logs = attn.map((a) => {
              'member_name': memberName,
              'seat_label': seat,
              'shift_name': shiftName,
              'check_in_time': a['check_in_time'],
              'check_out_time': a['check_out_time'],
              'duration_minutes': a['duration_minutes'],
              'session_type': a['session_type'] ?? 'normal',
              'is_overtime': a['is_overtime'] == true,
            }).toList();
        await PdfExporter.exportAttendance(libraryName: memberName, libraryAddress: 'Member report', dateRange: rangeLabel, logs: logs);
      }
      if (pays.isNotEmpty) {
        final withName = pays.map((p) => {...p, 'member_name': memberName}).toList();
        await PdfExporter.exportPayments(libraryName: memberName, libraryAddress: 'Member report', dateRange: rangeLabel, payments: withName);
      }
    }
    return true;
  }

  Future<void> _openTransfer() async {
    final ms = _membershipData;
    if (ms == null) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MemberTransferScreen(
          memberId: _memberId ?? _userProfile?['id']?.toString() ?? '',
          memberName: (_userProfile?['full_name'] ?? 'Member').toString(),
          fromMembership: ms,
        ),
      ),
    );
    if (result == true) {
      await _fetchMemberData();
    }
  }

  // ── Hold a member's membership ──────────────────────────────────────────────
  // Pauses the membership: status -> 'hold' and records the hold window in
  // hold_requests. The paused days are added back to end_date on resume, so the
  // member never loses paid days.
  Future<void> _holdMembership() async {
    final ms = _membershipData;
    if (ms == null) return;
    final daysCtrl = TextEditingController(text: '7');
    final reasonCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.pause_circle_outline, color: Color(0xFFD97706), size: 26),
          const SizedBox(width: 8),
          Text('Hold Membership', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pause this membership. The paused days are added back to the plan when you resume it. The seat stays reserved.',
              style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF475569), height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: daysCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Number of days', hintText: 'e.g. 7'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Reason', hintText: 'e.g. Member travelling'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF64748B)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white),
            child: Text('Put on Hold', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final days = int.tryParse(daysCtrl.text.trim()) ?? 0;
    if (days <= 0) {
      _snack('Enter a valid number of days');
      return;
    }
    final reason = reasonCtrl.text.trim().isEmpty ? 'Hold by admin' : reasonCtrl.text.trim();

    try {
      setState(() => _isLoading = true);
      final today = DateTime.now();
      final holdEnd = today.add(Duration(days: days));
      final dateFmt = DateFormat('yyyy-MM-dd');
      final memberId = ms['member_id'] ?? _memberId;

      await supabase.from('hold_requests').insert({
        'membership_id': ms['id'],
        'member_id': memberId,
        'library_id': ms['library_id'],
        'start_date': dateFmt.format(today),
        'end_date': dateFmt.format(holdEnd),
        'reason': reason,
        'status': 'approved',
      });
      if (!mounted) return;

      await supabase.from('memberships').update({'status': 'hold'}).eq('id', ms['id']);
      if (!mounted) return;

      await supabase.from('notifications').insert({
        'user_id': memberId,
        'title': 'Membership on hold',
        'body': 'Your membership has been put on hold for $days day${days == 1 ? '' : 's'} (until ${DateFormat('dd MMM yyyy').format(holdEnd)}). Your seat is reserved and the paused days will be added back when it resumes.',
        'data': {'type': 'hold', 'membership_id': ms['id']},
      });
      if (!mounted) return;

      _snack('Membership put on hold');
      _fetchMemberData();
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Resume (un-hold) a membership ───────────────────────────────────────────
  // Lifts the hold: status -> 'active' and extends end_date by the number of
  // days actually paused (today - hold start), so the member regains exactly the
  // paused days whether resumed early or on time.
  Future<void> _resumeMembership() async {
    final ms = _membershipData;
    if (ms == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Resume Membership', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          'Lift the hold and reactivate this membership now? The paused days will be added back to the plan.',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569), height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF64748B)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white),
            child: Text('Resume', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      setState(() => _isLoading = true);
      final memberId = ms['member_id'] ?? _memberId;

      // Find the active hold window to compute days actually paused.
      final hold = await supabase
          .from('hold_requests')
          .select('id, start_date')
          .eq('membership_id', ms['id'])
          .eq('status', 'approved')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (!mounted) return;

      int heldDays = 0;
      if (hold != null && hold['start_date'] != null) {
        final start = DateTime.parse(hold['start_date'].toString());
        final startDay = DateTime(start.year, start.month, start.day);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        heldDays = today.difference(startDay).inDays;
        if (heldDays < 0) heldDays = 0;
      }

      // Extend end_date by the paused days.
      final updates = <String, dynamic>{'status': 'active'};
      if (ms['end_date'] != null && heldDays > 0) {
        final end = DateTime.parse(ms['end_date'].toString());
        final newEnd = end.add(Duration(days: heldDays));
        updates['end_date'] = DateFormat('yyyy-MM-dd').format(newEnd);
      }
      await supabase.from('memberships').update(updates).eq('id', ms['id']);
      if (!mounted) return;

      if (hold != null) {
        await supabase.from('hold_requests').update({'status': 'cancelled'}).eq('id', hold['id']);
        if (!mounted) return;
      }

      await supabase.from('notifications').insert({
        'user_id': memberId,
        'title': 'Membership resumed',
        'body': heldDays > 0
            ? 'Your membership is active again. $heldDays paused day${heldDays == 1 ? '' : 's'} ${heldDays == 1 ? 'was' : 'were'} added back to your plan.'
            : 'Your membership is active again.',
        'data': {'type': 'hold_lifted', 'membership_id': ms['id']},
      });
      if (!mounted) return;

      _snack('Membership resumed');
      _fetchMemberData();
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Force Exit Member ──────────────────────────────────────────────────────
  Future<void> _forceExitMember() async {
    final ms = _membershipData;
    final status = (ms?['status'] ?? '').toString();
    final endStr = ms?['end_date']?.toString();
    final endDate = endStr != null ? DateTime.tryParse(endStr) : null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int daysLeft = 0;
    if (endDate != null) {
      daysLeft = DateTime(endDate.year, endDate.month, endDate.day).difference(today).inDays;
      if (daysLeft < 0) daysLeft = 0;
    }
    final bool isActiveLike = status == 'active' || status == 'trial' || status == 'hold';
    final memberName = (_userProfile?['full_name'] ?? 'this member').toString();

    // Optional refund inputs (only meaningful when removing an active member).
    bool wantRefund = false;
    final refundCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Remove from library', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFFDC2626), fontSize: 17)),
            ),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This marks $memberName as EXITED, frees their seat and ends their membership. This cannot be undone.',
                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569), height: 1.45),
                ),
                if (isActiveLike && endDate != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFD1B3)),
                    ),
                    child: Text(
                      'Their membership is still ACTIVE with $daysLeft day${daysLeft == 1 ? '' : 's'} left '
                      '(till ${DateFormat('dd MMM yyyy').format(endDate)}).',
                      style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF92400E), height: 1.35),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: wantRefund,
                        activeColor: const Color(0xFFE65C00),
                        onChanged: (v) => setLocal(() => wantRefund = v ?? false),
                      ),
                      Expanded(
                        child: Text('Refund part of their payment',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                      ),
                    ],
                  ),
                  if (wantRefund)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: TextField(
                        controller: refundCtrl,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.inter(fontSize: 14),
                        decoration: InputDecoration(
                          prefixText: '₹ ',
                          labelText: 'Refund amount',
                          hintText: 'e.g. 600',
                          hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF64748B)))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
              child: Text('Remove member', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true) return;

    // Parse refund (only if asked + active).
    int refundAmount = 0;
    if (isActiveLike && wantRefund) {
      refundAmount = int.tryParse(refundCtrl.text.trim()) ?? 0;
      if (refundAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid refund amount, or uncheck refund.')),
        );
        return;
      }
    }

    try {
      setState(() => _isLoading = true);
      final membershipId = _membershipData?['id'];
      final memberId = (_membershipData?['member_id'] ?? _memberId)?.toString();
      final libraryId = _membershipData?['library_id']?.toString();
      if (membershipId != null) {
        final membership = await supabase
            .from('memberships')
            .select('seat_id')
            .eq('id', membershipId)
            .single();
        if (!mounted) return;

        final seatId = membership['seat_id'];

        await supabase.from('memberships').update({
          'status': 'exited',
          'exited_at': DateTime.now().toUtc().toIso8601String(),
          'end_date': DateTime.now().toUtc().toIso8601String().substring(0, 10),
        }).eq('id', membershipId);
        if (!mounted) return;

        if (seatId != null) {
          final otherActive = await supabase
              .from('memberships')
              .select('id')
              .eq('seat_id', seatId)
              .neq('id', membershipId)
              .inFilter('status', ['active', 'trial', 'hold'])
              .limit(1)
              .maybeSingle();
          if (!mounted) return;
          if (otherActive == null) {
            await supabase.from('seats').update({
              'status': 'vacant',
              'occupied_by_member_id': null,
            }).eq('id', seatId);
            if (!mounted) return;
          }
        }

        // Record the refund as a negative confirmed payment so it flows into
        // revenue/analytics everywhere (a refund reduces net revenue).
        if (refundAmount > 0 && memberId != null && libraryId != null) {
          await supabase.from('payments').insert({
            'membership_id': membershipId,
            'member_id': memberId,
            'library_id': libraryId,
            'amount': -refundAmount,
            'method': 'cash',
            'status': 'confirmed',
            'payment_date': DateTime.now().toIso8601String(),
            'confirmed_by_admin_id': supabase.auth.currentUser?.id,
            'notes': 'Refund on early removal ($daysLeft days left)',
          });
          if (!mounted) return;
          await supabase.from('notifications').insert({
            'user_id': memberId,
            'title': 'Membership ended — refund issued',
            'body': 'Your membership was ended by the admin. A refund of ₹$refundAmount has been recorded.',
            'data': {'type': 'membership_removed_refund', 'amount': refundAmount},
          });
        } else if (memberId != null) {
          await supabase.from('notifications').insert({
            'user_id': memberId,
            'title': 'Membership ended',
            'body': 'Your membership at this library was ended by the admin.',
            'data': {'type': 'membership_removed'},
          });
        }

        try {
          await AuditLogger.instance.log(
            action: 'membership_remove',
            category: AuditLogger.categoryMembers,
            title: refundAmount > 0 ? 'Removed member (refunded)' : 'Removed member',
            details: refundAmount > 0
                ? '$memberName · $daysLeft days left · refund ₹$refundAmount'
                : '$memberName · removed',
            libraryId: libraryId,
          );
        } catch (_) {}
      }
      await _fetchMemberData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(refundAmount > 0
              ? 'Member removed. ₹$refundAmount refund recorded.'
              : 'Member removed.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  // ── Export full member profile as PDF (with ID document images) ─────────────
  Future<void> _exportMemberProfilePdf() async {
    final user = _userProfile;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member data is still loading. Please try again.')),
      );
      return;
    }
    setState(() => _isExportingPdf = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ms = _membershipData ?? {};
      final lib = ms['libraries'] as Map<String, dynamic>?;
      final libName = (lib?['name'] ?? 'Library').toString();
      final libAddress = [
        lib?['address_street'],
        lib?['address_city'],
        lib?['address_state'],
        lib?['address_pincode'],
      ].where((x) => x != null && x.toString().trim().isNotEmpty).join(', ');

      // Resolve floor + section names from the seat (best-effort).
      String floorName = '';
      String sectionName = '';
      final seat = ms['seats'] as Map<String, dynamic>?;
      if (seat != null) {
        final floorId = seat['floor_id'];
        final sectionId = seat['section_id'];
        if (floorId != null) {
          try {
            final f = await supabase.from('floors').select('name').eq('id', floorId).maybeSingle();
            floorName = (f?['name'] ?? '').toString();
          } catch (_) {}
        }
        if (sectionId != null) {
          try {
            final s = await supabase.from('sections').select('name').eq('id', sectionId).maybeSingle();
            sectionName = (s?['name'] ?? '').toString();
          } catch (_) {}
        }
      }

      // Resolve image URLs: photo is public; ID docs need a signed URL.
      final photoUrl = (user['photo_url'] ?? '').toString().trim();
      String? idUrl1;
      String? idUrl2;
      final id1 = (user['id_proof_url'] ?? '').toString().trim();
      final id2 = (user['id_proof_2_url'] ?? '').toString().trim();
      if (id1.isNotEmpty) {
        try {
          idUrl1 = await _documentUrl(id1);
        } catch (_) {}
      }
      if (id2.isNotEmpty) {
        try {
          idUrl2 = await _documentUrl(id2);
        } catch (_) {}
      }

      await PdfExporter.exportMemberProfile(
        libraryName: libName,
        libraryAddress: libAddress.isEmpty ? 'Member profile' : libAddress,
        user: user,
        membership: ms,
        floorName: floorName,
        sectionName: sectionName,
        photoUrl: photoUrl.isEmpty ? null : photoUrl,
        idUrl1: idUrl1,
        idUrl2: idUrl2,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  // ── Render Utilities ───────────────────────────────────────────────────────
  Widget _buildStatusBadge(String status) {
    Color bg = const Color(0xFFF3F4F6);
    Color txt = const Color(0xFF6B7280);
    String label = status.toUpperCase();

    if (status == 'active') { bg = const Color(0xFFDCFCE7); txt = const Color(0xFF16A34A); }
    else if (status == 'expired') { bg = const Color(0xFFFEE2E2); txt = const Color(0xFFDC2626); }
    else if (status == 'hold') { bg = const Color(0xFFFEF3C7); txt = const Color(0xFFD97706); }
    else if (status == 'trial') { bg = const Color(0xFFEDE9FE); txt = const Color(0xFF7C3AED); label = 'TRIAL'; }
    else if (status == 'exited') { bg = const Color(0xFFF3F4F6); txt = const Color(0xFF6B7280); label = 'EXITED'; }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: txt)),
    );
  }

  Widget _buildInfoCell({required IconData icon, required String label, required String value}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: const Color(0xFFE65C00)),
        const SizedBox(height: 6),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF6B7280))),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E)), maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: const Color(0xFFE65C00)),
            const SizedBox(width: 8),
            Text(title, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
          ]),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280))),
          Flexible(
            child: Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor ?? const Color(0xFF1E293B)),
                textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePhoto(String photo) {
    Widget fallback() {
      return const CircleAvatar(
        radius: 36,
        backgroundColor: Color(0xFFFFF7F0),
        child: Icon(Icons.person, color: Color(0xFFE65C00), size: 36),
      );
    }

    final trimmedPhoto = photo.trim();
    if (trimmedPhoto.isEmpty) return fallback();

    return ClipOval(
      child: Image.network(
        trimmedPhoto,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        cacheWidth: 200, // downscale decode (low-RAM)
        errorBuilder: (context, error, stackTrace) => fallback(),
      ),
    );
  }

  String? _privateStoragePath(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) return null;

    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) {
      final decodedPath = Uri.decodeComponent(uri.path);
      const bucketMarker = '/silence_private/';
      final bucketIndex = decodedPath.indexOf(bucketMarker);
      if (bucketIndex != -1) {
        return decodedPath.substring(bucketIndex + bucketMarker.length);
      }
      return null;
    }

    var path = raw;
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    const bucketPrefix = 'silence_private/';
    if (path.startsWith(bucketPrefix)) {
      path = path.substring(bucketPrefix.length);
    }
    return path.isEmpty ? null : path;
  }

  // Memoize signed-URL futures per raw value so returning to the Overview tab
  // (or any setState) doesn't re-sign the ID document URLs on every rebuild.
  final Map<String, Future<String>> _docUrlFutures = {};

  Future<String> _documentUrl(String rawValue) async {
    final raw = rawValue.trim();
    final storagePath = _privateStoragePath(raw);
    if (storagePath == null) return raw;
    return supabase.storage.from('silence_private').createSignedUrl(storagePath, 3600);
  }

  Widget _documentFallback() {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFEDD5)),
      ),
      child: const Center(
        child: Icon(Icons.image_not_supported_outlined, color: Color(0xFFE65C00), size: 32),
      ),
    );
  }

  Widget _buildDocumentImage(String title, String rawUrl) {
    return FutureBuilder<String>(
      future: _docUrlFutures.putIfAbsent(rawUrl, () => _documentUrl(rawUrl)),
      builder: (context, snapshot) {
        final resolvedUrl = snapshot.data;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF5EE),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 14, color: Color(0xFFE65C00)),
                    label: Text('View', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                    onPressed: resolvedUrl == null
                        ? null
                        : () async {
                            await launchUrl(Uri.parse(resolvedUrl), mode: LaunchMode.externalApplication);
                          },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (snapshot.connectionState == ConnectionState.waiting)
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE65C00))),
                )
              else if (snapshot.hasError || resolvedUrl == null || resolvedUrl.isEmpty)
                _documentFallback()
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    resolvedUrl,
                    height: 150,
                    fit: BoxFit.cover,
                    cacheWidth: 720, // downscale decode of large ID-doc uploads
                    errorBuilder: (context, error, stackTrace) => _documentFallback(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Tab 1: Overview ────────────────────────────────────────────────────────
  Widget _buildOverviewTab() {
    final user = _userProfile ?? {};
    final ms = _membershipData;
    final String status = ms?['status'] ?? 'pending';
    final String startDateStr = ms?['start_date'] ?? '';
    final String endDateStr = ms?['end_date'] ?? '';

    String fmtStart = 'N/A', fmtEnd = 'N/A';
    try {
      if (startDateStr.isNotEmpty) fmtStart = DateFormat('dd MMM yyyy').format(DateTime.parse(startDateStr));
      if (endDateStr.isNotEmpty) fmtEnd = DateFormat('dd MMM yyyy').format(DateTime.parse(endDateStr));
    } catch (_) {}

    final String rawPlan = ms?['plan_type'] ?? 'monthly';
    String planName = 'Monthly';
    if (rawPlan == '3_month') planName = '3-Month';
    if (rawPlan == '6_month') planName = '6-Month';

    final totalVisits = _attendanceList.length;
    final thisMonthVisits = _calculateThisMonthVisits();
    final streak = _calculateStreak();
    final avgSession = _calculateAvgSessionDuration();

    final totalPaid = _calculateTotalPaid();
    final String lastPay = _paymentsList.where((p) => p['status'] == 'confirmed').isNotEmpty
        ? DateFormat('dd MMM yyyy').format(DateTime.parse(_paymentsList.firstWhere((p) => p['status'] == 'confirmed')['payment_date']).toLocal())
        : 'No payments yet';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Contact & Personal Info
          _buildSectionCard(
            title: 'Contact & Personal Info',
            icon: Icons.person_outline_rounded,
            children: [
              _buildDetailRow('Phone', user['phone'] ?? 'N/A'),
              _buildDetailRow('Email', user['email'] ?? 'N/A'),
              _buildDetailRow('Gender', (user['gender'] ?? 'N/A').toString().toUpperCase()),
              _buildDetailRow('Date of Birth', user['date_of_birth'] ?? 'N/A'),
              _buildDetailRow('Address', user['address'] ?? 'N/A'),
              _buildDetailRow('Exam / Preparing', user['exam_category'] ?? 'N/A'),
              // Quick contact actions
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.phone_outlined, size: 16, color: Color(0xFFE65C00)),
                      label: Text('Call', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFE65C00)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      onPressed: () async {
                        final phone = user['phone'];
                        if (phone != null && phone.isNotEmpty) {
                          final uri = Uri.parse('tel:$phone');
                          if (await canLaunchUrl(uri)) await launchUrl(uri);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.white),
                      label: Text('WhatsApp', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      onPressed: () async {
                        final phone = (user['phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
                        if (phone.isNotEmpty) {
                          await launchUrl(Uri.parse('https://wa.me/$phone'), mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 2. ID Documents
          _buildSectionCard(
            title: 'ID Documents',
            icon: Icons.badge_outlined,
            children: [
              if ((user['id_proof_url'] != null && user['id_proof_url'].toString().isNotEmpty) ||
                  (user['id_proof_2_url'] != null && user['id_proof_2_url'].toString().isNotEmpty)) ...[
                if (user['id_proof_url'] != null && user['id_proof_url'].toString().isNotEmpty)
                  _buildDocumentImage(
                    '${user['id_type']?.toString().toUpperCase() ?? 'ID PROOF'} (FRONT)',
                    user['id_proof_url'].toString(),
                  ),
                if (user['id_proof_2_url'] != null && user['id_proof_2_url'].toString().isNotEmpty) ...[
                  _buildDocumentImage(
                    '${user['id_type']?.toString().toUpperCase() ?? 'ID PROOF'} (BACK)',
                    user['id_proof_2_url'].toString(),
                  ),
                ],
              ] else
                Text('No documents uploaded', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
            ],
          ),

          // 3. Membership Details
          _buildSectionCard(
            title: 'Membership Details',
            icon: Icons.card_membership_rounded,
            children: [
              _buildDetailRow('Plan Type', planName),
              _buildDetailRow('Start Date', fmtStart),
              _buildDetailRow('End Date', fmtEnd),
              _buildDetailRow('Status', status.toUpperCase(), valueColor: status == 'active' ? const Color(0xFF16A34A) : (status == 'expired' ? const Color(0xFFDC2626) : null)),
              if (ms?['discount_amount'] != null && (ms?['discount_amount'] as num? ?? 0) > 0)
                _buildDetailRow('Discount Applied', '₹${ms?['discount_amount']}', valueColor: const Color(0xFF16A34A)),
              if (ms?['is_trial'] == true)
                _buildDetailRow('Trial', 'Yes (${ms?['trial_days'] ?? 0} days)', valueColor: const Color(0xFF7C3AED)),
            ],
          ),

          // 4. Attendance Summary
          _buildSectionCard(
            title: 'Attendance Summary',
            icon: Icons.insights_rounded,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn('$totalVisits', 'Total Visits'),
                  _buildStatColumn('$thisMonthVisits', 'This Month'),
                  _buildStatColumn('$streak', 'Streak Days'),
                  _buildStatColumn('${avgSession.toStringAsFixed(1)}h', 'Avg Session'),
                ],
              ),
            ],
          ),

          // 5. Payment Summary
          _buildSectionCard(
            title: 'Payment Summary',
            icon: Icons.payments_outlined,
            children: [
              _buildDetailRow('Total Paid', '₹$totalPaid', valueColor: const Color(0xFF16A34A)),
              _buildDetailRow('Last Payment', lastPay),
              _buildDetailRow('Confirmed Payments', '${_paymentsList.where((p) => p['status'] == 'confirmed').length}'),
              _buildDetailRow('Pending Payments', '${_paymentsList.where((p) => p['status'] == 'pending').length}',
                  valueColor: _paymentsList.any((p) => p['status'] == 'pending') ? const Color(0xFFD97706) : null),
            ],
          ),

          // 6. Referral Block
          _buildSectionCard(
            title: 'Referrals',
            icon: Icons.share_rounded,
            children: [
              if (user['referral_code'] != null && user['referral_code'].toString().isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          user['referral_code'] ?? '',
                          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00), letterSpacing: 2),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18, color: Color(0xFFE65C00)),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: user['referral_code'] ?? ''));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Referral code copied!')));
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _buildDetailRow('Members Referred', '${user['referral_count'] ?? 0}'),
                _buildDetailRow('Reward Days Earned', '${user['referral_reward_days'] ?? 0}'),
              ] else
                Text('No referral code generated', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
            ],
          ),

          // 7. Admin Actions
          const SizedBox(height: 8),
          if (!_isReadOnly && _canHoldOrResume()) ...[
            SizedBox(
              width: double.infinity,
              child: (_membershipData?['status'] == 'hold')
                  ? OutlinedButton.icon(
                      icon: const Icon(Icons.play_circle_outline, size: 18, color: Color(0xFF16A34A)),
                      label: Text('Resume Membership', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A))),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF16A34A)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _resumeMembership,
                    )
                  : OutlinedButton.icon(
                      icon: const Icon(Icons.pause_circle_outline, size: 18, color: Color(0xFFD97706)),
                      label: Text('Hold Membership', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFD97706))),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFD97706)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _holdMembership,
                    ),
            ),
            const SizedBox(height: 12),
          ],
          if (!_isReadOnly && _canTransfer()) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.swap_horiz_rounded, size: 18, color: Color(0xFFE65C00)),
                label: Text('Transfer to another library',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE65C00)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _openTransfer,
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _isExportingPdf
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.white),
              label: Text(_isExportingPdf ? 'Preparing PDF…' : 'Export Profile PDF',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isExportingPdf ? null : _exportMemberProfilePdf,
            ),
          ),
          if (!_isReadOnly) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.person_remove_rounded, size: 18, color: Colors.white),
                label: Text('Remove from library', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _forceExitMember,
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String value, String label) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
        const SizedBox(height: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF6B7280))),
      ],
    );
  }

  // ── Tab 2: Attendance Calendar ─────────────────────────────────────────────
  Widget _buildAttendanceTab() {
    final Map<int, List<Map<String, dynamic>>> sessionMap = {};
    for (final a in _attendanceList) {
      try {
        final dt = DateTime.parse(a['check_in_time']).toLocal();
        if (dt.year == _calendarMonth.year && dt.month == _calendarMonth.month) {
          sessionMap.putIfAbsent(dt.day, () => []).add(a);
        }
      } catch (_) {}
    }

    final firstDayOfMonth = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final totalDaysInMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    final prefixEmptyCells = firstDayOfMonth.weekday % 7;
    final List<String> weekdays = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

    // Calculate max sessions for heatmap intensity
    int maxSessions = 1;
    for (final entry in sessionMap.values) {
      if (entry.length > maxSessions) maxSessions = entry.length;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionCard(
        title: 'Attendance Heatmap',
        icon: Icons.calendar_month_rounded,
        children: [
          // Month Switcher
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Color(0xFFE65C00)),
                onPressed: () => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1, 1)),
              ),
              Text(
                DateFormat('MMMM yyyy').format(_calendarMonth),
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFFE65C00)),
                onPressed: () => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Weekday headers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: weekdays.map((day) => SizedBox(
              width: 38,
              child: Text(day, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8))),
            )).toList(),
          ),
          const SizedBox(height: 8),
          // Days Grid with heatmap shading
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1),
            itemCount: prefixEmptyCells + totalDaysInMonth,
            itemBuilder: (ctx, index) {
              if (index < prefixEmptyCells) return const SizedBox.shrink();
              final day = index - prefixEmptyCells + 1;
              final date = DateTime(_calendarMonth.year, _calendarMonth.month, day);
              final sessions = sessionMap[day] ?? [];
              final hasAttendance = sessions.isNotEmpty;

              // Heatmap intensity: more sessions = darker orange
              final double intensity = hasAttendance ? (sessions.length / maxSessions).clamp(0.3, 1.0) : 0.0;

              return InkWell(
                onTap: () => _showAttendanceDayDetailSheet(date: date, sessions: sessions),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  decoration: BoxDecoration(
                    color: hasAttendance ? Color.lerp(const Color(0xFFFFF7F0), const Color(0xFFE65C00), intensity * 0.6) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: hasAttendance ? const Color(0xFFFFD8BE) : const Color(0xFFF1F5F9), width: 1),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        '$day',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: hasAttendance ? FontWeight.bold : FontWeight.normal,
                          color: hasAttendance ? (intensity > 0.5 ? Colors.white : const Color(0xFFE65C00)) : const Color(0xFF1E293B),
                        ),
                      ),
                      if (hasAttendance && sessions.length > 1)
                        Positioned(
                          bottom: 2,
                          child: Text('${sessions.length}', style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: intensity > 0.5 ? Colors.white70 : const Color(0xFFE65C00))),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          // Heatmap legend
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Less', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
              const SizedBox(width: 4),
              ...List.generate(5, (i) => Container(
                width: 16, height: 16, margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: Color.lerp(const Color(0xFFFFF7F0), const Color(0xFFE65C00), (i + 1) / 5 * 0.6),
                  borderRadius: BorderRadius.circular(3),
                ),
              )),
              const SizedBox(width: 4),
              Text('More', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
            ],
          ),
        ],
          ),
          const SizedBox(height: 16),
          _buildAttendanceRangeAnalytics(),
        ],
      ),
    );
  }

  // Date-wise attendance analytics for an arbitrary range (defaults to the
  // current month). Computed from the already-loaded _attendanceList — no extra
  // query. Lets the admin see check-in / check-out / study-time per day.
  Future<void> _pickAttendanceRange() async {
    final now = DateTime.now();
    final start = _attnRangeStart ?? DateTime(now.year, now.month, 1);
    final end = _attnRangeEnd ?? DateTime(now.year, now.month + 1, 0);
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: start, end: end),
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: Color(0xFFE65C00), onPrimary: Colors.white, onSurface: Color(0xFF1E293B)),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _attnRangeStart = picked.start;
        _attnRangeEnd = picked.end;
      });
    }
  }

  String _fmtStudyMinutes(int minutes) {
    if (minutes <= 0) return '0m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  Widget _buildAttendanceRangeAnalytics() {
    final now = DateTime.now();
    final rangeStart = _attnRangeStart ?? DateTime(now.year, now.month, 1);
    final rangeEnd = _attnRangeEnd ?? DateTime(now.year, now.month + 1, 0);
    final sDay = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final eDay = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);

    // Group in-range sessions by day.
    final Map<String, List<Map<String, dynamic>>> byDay = {};
    for (final a in _attendanceList) {
      try {
        final ci = DateTime.parse(a['check_in_time']).toLocal();
        final d = DateTime(ci.year, ci.month, ci.day);
        if (d.isBefore(sDay) || d.isAfter(eDay)) continue;
        byDay.putIfAbsent(DateFormat('yyyy-MM-dd').format(d), () => []).add(a);
      } catch (_) {}
    }
    final dayKeys = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    int totalSessions = 0, totalMinutes = 0, longest = 0;
    for (final list in byDay.values) {
      totalSessions += list.length;
      for (final s in list) {
        final d = (s['duration_minutes'] as num?)?.toInt() ?? 0;
        totalMinutes += d;
        if (d > longest) longest = d;
      }
    }
    final daysPresent = byDay.length;
    final avg = daysPresent > 0 ? (totalMinutes / daysPresent).round() : 0;

    return _buildSectionCard(
      title: 'Attendance Details',
      icon: Icons.insights_rounded,
      children: [
        // Range selector
        InkWell(
          onTap: _pickAttendanceRange,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7F0),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFD8BE)),
            ),
            child: Row(
              children: [
                const Icon(Icons.date_range_rounded, size: 18, color: Color(0xFFE65C00)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${DateFormat('dd MMM yyyy').format(sDay)}  –  ${DateFormat('dd MMM yyyy').format(eDay)}',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                  ),
                ),
                Text('Change', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (dayKeys.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(children: [
              Icon(Icons.event_busy_rounded, size: 44, color: Colors.grey[300]),
              const SizedBox(height: 10),
              Text('No attendance in this range.', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280))),
            ]),
          ),
        ] else ...[
          // Summary
          Row(
            children: [
              Expanded(child: _buildStatColumn('$daysPresent', 'Days present')),
              Expanded(child: _buildStatColumn('$totalSessions', 'Sessions')),
              Expanded(child: _buildStatColumn(_fmtStudyMinutes(totalMinutes), 'Study time')),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildStatColumn(_fmtStudyMinutes(avg), 'Avg / day')),
              Expanded(child: _buildStatColumn(_fmtStudyMinutes(longest), 'Longest')),
            ],
          ),
          const Divider(height: 28),
          // Per-day breakdown (tap → full session detail sheet)
          ...dayKeys.map((key) {
            final list = byDay[key]!;
            DateTime? firstIn, lastOut;
            int dayMinutes = 0;
            for (final s in list) {
              try {
                final ci = DateTime.parse(s['check_in_time']).toLocal();
                if (firstIn == null || ci.isBefore(firstIn)) firstIn = ci;
              } catch (_) {}
              if (s['check_out_time'] != null) {
                try {
                  final co = DateTime.parse(s['check_out_time']).toLocal();
                  if (lastOut == null || co.isAfter(lastOut)) lastOut = co;
                } catch (_) {}
              }
              dayMinutes += (s['duration_minutes'] as num?)?.toInt() ?? 0;
            }
            final date = DateTime.parse(key);
            return InkWell(
              onTap: () => _showAttendanceDayDetailSheet(date: date, sessions: list),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Column(
                      children: [
                        Text(DateFormat('dd').format(date), style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                        Text(DateFormat('MMM').format(date), style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${firstIn != null ? DateFormat('hh:mm a').format(firstIn) : '—'}  →  ${lastOut != null ? DateFormat('hh:mm a').format(lastOut) : 'Open'}',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                          ),
                          const SizedBox(height: 2),
                          Text('${list.length} session${list.length > 1 ? 's' : ''}', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: const Color(0xFFFFF7F0), borderRadius: BorderRadius.circular(8)),
                      child: Text(_fmtStudyMinutes(dayMinutes), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  void _showAttendanceDayDetailSheet({required DateTime date, required List<Map<String, dynamic>> sessions}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(DateFormat('EEEE, dd MMMM yyyy').format(date), style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
              const SizedBox(height: 16),
              if (sessions.isEmpty) ...[
                Text('No attendance sessions logged for this day.', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500])),
                if (!_isReadOnly) ...[
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () { Navigator.pop(ctx); _showAttendanceModal(date: date); },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Manual Session'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                  ),
                ],
              ] else ...[
                ...sessions.map((s) {
                  final String ciStr = s['check_in_time'] ?? '';
                  final String? coStr = s['check_out_time'];
                  final int? dur = s['duration_minutes'];
                  final String sessionType = s['session_type'] ?? 'normal';
                  String checkIn = 'N/A', checkOut = 'Not scanned out';
                  try {
                    if (ciStr.isNotEmpty) checkIn = DateFormat('hh:mm a').format(DateTime.parse(ciStr).toLocal());
                    if (coStr != null && coStr.isNotEmpty) checkOut = DateFormat('hh:mm a').format(DateTime.parse(coStr).toLocal());
                  } catch (_) {}

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Session Detail', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF475569))),
                            Builder(builder: (_) {
                              final tag = attendanceTag(sessionType);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: tag.isManual ? const Color(0xFFFFF7E6) : const Color(0xFFFFF7F0),
                                    borderRadius: BorderRadius.circular(6)),
                                child: Text(tag.label.toUpperCase(),
                                    style: GoogleFonts.inter(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: tag.isManual ? const Color(0xFFB45309) : const Color(0xFFE65C00))),
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('In: $checkIn', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B))),
                        Text('Out: $checkOut', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B))),
                        if (dur != null)
                          Padding(padding: const EdgeInsets.only(top: 4), child: Text('Duration: $dur minutes (${(dur / 60).toStringAsFixed(1)} hours)', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic))),
                        if (s['edit_reason'] != null)
                          Padding(padding: const EdgeInsets.only(top: 4), child: Text('Reason: ${s['edit_reason']}', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFDC2626)))),
                        if (!_isReadOnly) ...[
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () { Navigator.pop(ctx); _showAttendanceModal(session: s, date: date); },
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('Edit Duration'),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white, elevation: 0),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Tab 3: Payments ────────────────────────────────────────────────────────
  Widget _buildPaymentsTab() {
    if (_paymentsList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payment_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No payments registered yet.', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      // Shrink-wrap: this list lives inside the screen's outer
      // SingleChildScrollView, so it must size to its content (an unbounded
      // ListView here threw a layout error and froze the tab).
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _paymentsList.length,
      itemBuilder: (ctx, index) {
        final payment = _paymentsList[index];
        final amount = payment['amount'] ?? 0;
        final status = payment['status'] ?? 'pending';
        final method = (payment['method'] ?? 'UPI').toString().toUpperCase();
        final refId = payment['ref_id'] ?? '';
        final sender = payment['upi_sender_name'] ?? '';
        final String planType = payment['plan_type'] ?? '';
        final discount = payment['discount_amount'];

        String payDate = 'N/A';
        try {
          if (payment['payment_date'] != null) payDate = DateFormat('dd MMMM yyyy, hh:mm a').format(DateTime.parse(payment['payment_date']).toLocal());
        } catch (_) {}

        Color statusBg = const Color(0xFFF3F4F6);
        Color statusText = const Color(0xFF6B7280);
        if (status == 'confirmed') { statusBg = const Color(0xFFDCFCE7); statusText = const Color(0xFF16A34A); }
        else if (status == 'rejected') { statusBg = const Color(0xFFFEE2E2); statusText = const Color(0xFFDC2626); }
        else if (status == 'pending') { statusBg = const Color(0xFFFEF3C7); statusText = const Color(0xFFD97706); }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('₹$amount', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                    child: Text(status.toUpperCase(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: statusText)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.payments_outlined, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  Text(method, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF475569))),
                  const SizedBox(width: 8),
                  Expanded(child: Text('•  $payDate', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]), overflow: TextOverflow.ellipsis)),
                ],
              ),
              if (planType.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text('Plan: $planType', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)))),
              if (discount != null && (discount as num) > 0)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text('Discount: ₹$discount', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF16A34A)))),
              if (refId.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text('Ref ID: $refId', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic))),
              if (sender.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text('Sender: $sender', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]))),
              if (payment['id'] != null)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text('Txn: ${payment['id'].toString().substring(0, 8).toUpperCase()}', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[400]))),
              if (status == 'pending' && !_isReadOnly) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _rejectPayment(payment['id']),
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626), side: const BorderSide(color: Color(0xFFDC2626)), padding: const EdgeInsets.symmetric(vertical: 8)),
                        child: Text('Reject', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _confirmPayment(payment['id']),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8)),
                        child: Text('Confirm', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Tab 4: Activity Timeline ───────────────────────────────────────────────
  Widget _buildActivityTab() {
    final List<_ActivityEventItem> events = [];

    // 1. Registration
    final String regDateStr = _userProfile?['created_at'] ?? '';
    if (regDateStr.isNotEmpty) {
      try {
        events.add(_ActivityEventItem(timestamp: DateTime.parse(regDateStr).toLocal(), title: 'Joined library', subtitle: 'Profile successfully registered.', icon: Icons.person_add_rounded, color: const Color(0xFF3B82F6)));
      } catch (_) {}
    }

    // 2. Seat Assignments / Memberships
    for (final m in _allMemberships.reversed) {
      final String createdAt = m['created_at'] ?? '';
      final String seatLabel = m['seats']?['seat_label'] ?? '';
      final String shiftName = m['shifts']?['name'] ?? '';
      final String mStatus = m['status'] ?? '';
      if (createdAt.isNotEmpty) {
        try {
          events.add(_ActivityEventItem(
            timestamp: DateTime.parse(createdAt).toLocal(),
            title: mStatus == 'active' ? 'Membership activated' : 'Membership $mStatus',
            subtitle: 'Seat: $seatLabel, Shift: $shiftName',
            icon: Icons.chair_alt_rounded,
            color: const Color(0xFFE65C00),
          ));
        } catch (_) {}
      }

      // Hold event
      if (mStatus == 'hold') {
        events.add(_ActivityEventItem(
          timestamp: DateTime.parse(m['updated_at'] ?? createdAt).toLocal(),
          title: 'Membership put on hold',
          subtitle: 'Seat: $seatLabel',
          icon: Icons.pause_circle_rounded,
          color: const Color(0xFFD97706),
        ));
      }

      // Exit event
      if (mStatus == 'exited') {
        events.add(_ActivityEventItem(
          timestamp: DateTime.parse(m['end_date'] ?? m['updated_at'] ?? createdAt).toLocal(),
          title: 'Member exited',
          subtitle: 'Seat: $seatLabel released.',
          icon: Icons.exit_to_app_rounded,
          color: const Color(0xFFDC2626),
        ));
      }
    }

    // 3. Payments
    for (final p in _paymentsList) {
      try {
        final payDt = DateTime.parse(p['payment_date']).toLocal();
        final amt = p['amount'] ?? 0;
        final status = p['status'] ?? 'pending';
        events.add(_ActivityEventItem(
          timestamp: payDt,
          title: 'Payment ₹$amt',
          subtitle: 'Status: ${status.toUpperCase()} • ${(p['method'] ?? 'N/A').toString().toUpperCase()}',
          icon: Icons.payment_rounded,
          color: status == 'confirmed' ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
        ));
      } catch (_) {}
    }

    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (events.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.history_toggle_off_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('No timeline activity records.', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      // Shrink-wrap inside the outer SingleChildScrollView — an unbounded list
      // here threw a layout exception (after build, so the tab's try/catch
      // couldn't catch it) and froze the screen.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      itemBuilder: (ctx, index) {
        final ev = events[index];
        final isLast = index == events.length - 1;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: ev.color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(ev.icon, size: 15, color: ev.color),
              ),
              if (!isLast) Container(width: 2, height: 50, color: Colors.grey[200]),
            ]),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(ev.title, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)))),
                        Text(DateFormat('dd MMM, hh:mm a').format(ev.timestamp), style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[400])),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(ev.subtitle, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Tab 5: Notes ───────────────────────────────────────────────────────────
  Widget _buildNotesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _buildSectionCard(
        title: 'Private Admin Notes',
        icon: Icons.sticky_note_2_outlined,
        children: [
          Text(
            'These notes are fully private and only visible to library administrators. They are never shown to the members.',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500], height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(hintText: 'Type admin notes, member reminders or history logs here...', fillColor: Color(0xFFF8FAFC)),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isSavingNote ? null : _savePrivateNote,
            icon: _isSavingNote
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                : const Icon(Icons.save_rounded, size: 16),
            label: Text('Save Note', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          ),
        ],
      ),
    );
  }

  // ── Build Method ───────────────────────────────────────────────────────────
  // Build only the active tab, selected by NAME (so a removed tab in read-only
  // mode can't cause an index mismatch). Any per-tab build error is caught and
  // shown inline instead of blanking the whole screen.
  Widget _buildTabContent() {
    final String tab = (_activeTab >= 0 && _activeTab < _tabNames.length)
        ? _tabNames[_activeTab]
        : 'Overview';
    try {
      switch (tab) {
        case 'Attendance':
          return _buildAttendanceTab();
        case 'Payments':
          return _buildPaymentsTab();
        case 'Activity':
          return _buildActivityTab();
        case 'Notes':
          return _buildNotesTab();
        case 'Overview':
        default:
          return _buildOverviewTab();
      }
    } catch (e) {
      debugPrint('Error building "$tab" tab: $e');
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 40, color: Color(0xFFDC2626)),
              const SizedBox(height: 12),
              Text(
                'Couldn\'t load the $tab tab.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFBF5EE),
        body: Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)))),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBF5EE),
        appBar: AppBar(backgroundColor: const Color(0xFFE65C00), title: Text('Profile Error', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.error_outline_rounded, size: 64, color: Color(0xFFDC2626)),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[700])),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _fetchMemberData, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white), child: const Text('Retry')),
            ]),
          ),
        ),
      );
    }

    final user = _userProfile;
    if (user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBF5EE),
        appBar: AppBar(backgroundColor: const Color(0xFFE65C00), title: Text('No Data Found', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white))),
        body: Center(child: Text('This user does not have an active membership profile.', style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[700]))),
      );
    }

    final String name = user['full_name'] ?? 'No Name';
    final String photo = user['photo_url'] ?? '';
    final String status = _membershipData?['status'] ?? 'pending';
    final String joinedStr = user['created_at'] ?? '';
    String joinedDate = '';
    try {
      if (joinedStr.isNotEmpty) joinedDate = 'Joined ${DateFormat('dd MMM yyyy').format(DateTime.parse(joinedStr).toLocal())}';
    } catch (_) {}

    final String seatLabel = _membershipData?['seats']?['seat_label'] ?? 'No Seat';
    final String shiftName = _membershipData?['shifts']?['name'] ?? 'No Shift';
    final String rawPlan = _membershipData?['plan_type'] ?? 'monthly';
    final String expiryStr = _membershipData?['end_date'] ?? '';

    String planText = '1 Month';
    if (rawPlan == '3_month') planText = '3 Months';
    if (rawPlan == '6_month') planText = '6 Months';

    String expiryText = 'N/A';
    try {
      if (expiryStr.isNotEmpty) expiryText = DateFormat('dd MMM').format(DateTime.parse(expiryStr));
    } catch (_) {}

    return Scaffold(
      backgroundColor: const Color(0xFFFBF5EE),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Orange Header
          Container(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, bottom: 16, left: 12, right: 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF6B00), Color(0xFFE65C00)]),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  Text('Member Details', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                ]),
                if (!_isReadOnly)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.ios_share_rounded, color: Colors.white), tooltip: 'Export', onPressed: _showExportSheet),
                    IconButton(icon: const Icon(Icons.edit_rounded, color: Colors.white), onPressed: _showEditMemberDialog),
                  ]),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 2. Profile Header Card
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      children: [
                        // Photo with status ring
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: status == 'active' ? const Color(0xFF16A34A)
                                  : status == 'expired' ? const Color(0xFFDC2626)
                                  : status == 'hold' ? const Color(0xFFD97706)
                                  : const Color(0xFFE65C00),
                              width: 3,
                            ),
                          ),
                          child: _buildProfilePhoto(photo),
                        ),
                        const SizedBox(height: 12),
                        Text(name, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E))),
                        const SizedBox(height: 6),
                        _buildStatusBadge(status),
                        const SizedBox(height: 4),
                        Text('ID: ${_memberId?.substring(0, 8).toUpperCase() ?? "N/A"}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF6B7280))),
                        if (joinedDate.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(joinedDate, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
                        ],
                        const SizedBox(height: 16),
                        // 4-cell info grid
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF1F5F9))),
                          child: Row(
                            children: [
                              Expanded(child: _buildInfoCell(icon: Icons.chair_alt_rounded, label: 'Seat', value: seatLabel)),
                              Container(width: 1, height: 40, color: const Color(0xFFE2E8F0)),
                              Expanded(child: _buildInfoCell(icon: Icons.wb_sunny_outlined, label: 'Shift', value: shiftName)),
                              Container(width: 1, height: 40, color: const Color(0xFFE2E8F0)),
                              Expanded(child: _buildInfoCell(icon: Icons.card_membership_rounded, label: 'Plan', value: planText)),
                              Container(width: 1, height: 40, color: const Color(0xFFE2E8F0)),
                              Expanded(child: _buildInfoCell(icon: Icons.event_available_rounded, label: 'Exp', value: expiryText)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 3. Tab Bar
                  Container(
                    color: Colors.white,
                    height: 48,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(_tabNames.length, (index) {
                          final bool isActive = _activeTab == index;
                          return InkWell(
                            onTap: () => setState(() => _activeTab = index),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(_tabNames[index], style: GoogleFonts.outfit(fontSize: 14, fontWeight: isActive ? FontWeight.bold : FontWeight.w500, color: isActive ? const Color(0xFFE65C00) : const Color(0xFF6B7280))),
                                  const SizedBox(height: 4),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    height: 3,
                                    width: isActive ? 40 : 0,
                                    decoration: BoxDecoration(color: const Color(0xFFE65C00), borderRadius: BorderRadius.circular(2)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),

                  // 4. Tab View — build ONLY the active tab. Building all five
                  // eagerly meant one bad tab's parse error blanked the whole
                  // screen; this isolates each tab and is driven by _tabNames so
                  // removing "Notes" in read-only mode can't index past children.
                  _buildTabContent(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityEventItem {
  final DateTime timestamp;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  _ActivityEventItem({
    required this.timestamp,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}
