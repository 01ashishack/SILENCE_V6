import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

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

  // Calendar State
  DateTime _calendarMonth = DateTime.now();

  // Notes controller
  final _notesController = TextEditingController();
  bool _isSavingNote = false;

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
    if (mId == null) return;

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
            .select('*, seats(seat_label, floor_id), shifts(name, price_monthly)')
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
      ]);

      if (!mounted) return;

      setState(() {
        _userProfile = results[0] as Map<String, dynamic>?;
        _membershipData = results[1] as Map<String, dynamic>?;
        _allMemberships = List<Map<String, dynamic>>.from(results[2] as List);
        _attendanceList = List<Map<String, dynamic>>.from(results[3] as List);
        _paymentsList = List<Map<String, dynamic>>.from(results[4] as List);

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
      await _fetchMemberData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment confirmed successfully! ✓')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error confirming payment: $e')));
      }
    }
  }

  Future<void> _rejectPayment(String paymentId) async {
    try {
      setState(() => _isLoading = true);
      await supabase.from('payments').update({'status': 'rejected'}).eq('id', paymentId);
      await _fetchMemberData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment marked as rejected. ✓')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error rejecting payment: $e')));
      }
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
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance saved successfully! ✓')));
                        }
                      } catch (e) {
                        if (mounted) {
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

  // ── Force Exit Member ──────────────────────────────────────────────────────
  Future<void> _forceExitMember() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 28),
          const SizedBox(width: 8),
          Text('Force Exit Member', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFFDC2626))),
        ]),
        content: Text(
          'This will permanently mark this member as EXITED. They will lose their seat assignment and active membership. This action cannot be undone.\n\nAre you absolutely sure?',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569), height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF64748B)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            child: Text('Yes, Force Exit', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      setState(() => _isLoading = true);
      final membershipId = _membershipData?['id'];
      if (membershipId != null) {
        await supabase.from('memberships').update({
          'status': 'exited',
          'end_date': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', membershipId);
      }
      await _fetchMemberData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member has been force-exited successfully.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error force-exiting member: $e')));
      }
    }
  }

  // ── Export Member Data CSV ─────────────────────────────────────────────────
  Future<void> _exportMemberData() async {
    final user = _userProfile;
    final ms = _membershipData;
    if (user == null) return;

    final buffer = StringBuffer();
    buffer.writeln('SILENCE Member Data Export');
    buffer.writeln('Export Date:,${DateFormat('dd MMM yyyy hh:mm a').format(DateTime.now())}');
    buffer.writeln();
    buffer.writeln('Field,Value');
    buffer.writeln('"Name","${user['full_name'] ?? 'N/A'}"');
    buffer.writeln('"Phone","${user['phone'] ?? 'N/A'}"');
    buffer.writeln('"Email","${user['email'] ?? 'N/A'}"');
    buffer.writeln('"Gender","${user['gender'] ?? 'N/A'}"');
    buffer.writeln('"Date of Birth","${user['date_of_birth'] ?? 'N/A'}"');
    buffer.writeln('"Address","${user['address'] ?? 'N/A'}"');
    buffer.writeln('"Exam/Preparing","${user['exam_category'] ?? 'N/A'}"');
    buffer.writeln('"Status","${ms?['status'] ?? 'N/A'}"');
    buffer.writeln('"Plan","${ms?['plan_type'] ?? 'N/A'}"');
    buffer.writeln('"Start Date","${ms?['start_date'] ?? 'N/A'}"');
    buffer.writeln('"End Date","${ms?['end_date'] ?? 'N/A'}"');
    buffer.writeln('"Seat","${ms?['seats']?['seat_label'] ?? 'N/A'}"');
    buffer.writeln('"Shift","${ms?['shifts']?['name'] ?? 'N/A'}"');
    buffer.writeln('"Total Visits","${_attendanceList.length}"');
    buffer.writeln('"Total Paid","₹${_calculateTotalPaid()}"');
    buffer.writeln('"Streak Days","${_calculateStreak()}"');
    buffer.writeln();

    // Attendance History
    buffer.writeln('Attendance History');
    buffer.writeln('Date,Check-in,Check-out,Duration (min)');
    for (final a in _attendanceList.take(50)) {
      final ci = a['check_in_time'];
      final co = a['check_out_time'];
      final dur = a['duration_minutes'] ?? '';
      buffer.writeln('"${ci != null ? DateFormat('dd MMM yyyy').format(DateTime.parse(ci).toLocal()) : 'N/A'}","${ci != null ? DateFormat('hh:mm a').format(DateTime.parse(ci).toLocal()) : 'N/A'}","${co != null ? DateFormat('hh:mm a').format(DateTime.parse(co).toLocal()) : 'N/A'}","$dur"');
    }
    buffer.writeln();

    // Payment History
    buffer.writeln('Payment History');
    buffer.writeln('Date,Amount,Method,Status');
    for (final p in _paymentsList.take(50)) {
      final pd = p['payment_date'];
      buffer.writeln('"${pd != null ? DateFormat('dd MMM yyyy').format(DateTime.parse(pd).toLocal()) : 'N/A'}","₹${p['amount'] ?? 0}","${p['method'] ?? 'N/A'}","${p['status'] ?? 'N/A'}"');
    }

    final tempDir = Directory.systemTemp;
    final name = (user['full_name'] ?? 'member').toString().replaceAll(' ', '_');
    final tempFile = File('${tempDir.path}/${name}_profile_export.csv');
    await tempFile.writeAsString(buffer.toString());
    await Share.shareXFiles([XFile(tempFile.path, mimeType: 'text/csv')], subject: 'SILENCE Member Data – ${user['full_name']}');
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
              if (user['id_type'] != null && user['id_type'].toString().isNotEmpty)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        user['id_type']?.toString().toUpperCase() ?? 'DOCUMENT',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                      ),
                    ),
                    if (user['id_document_url'] != null && user['id_document_url'].toString().isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 14, color: Color(0xFFE65C00)),
                        label: Text('View', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                        onPressed: () async {
                          final url = user['id_document_url'].toString();
                          if (url.isNotEmpty) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                        },
                      ),
                  ],
                )
              else
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.download_rounded, size: 18, color: Color(0xFFE65C00)),
                  label: Text('Export Data', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE65C00)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _exportMemberData,
                ),
              ),
              if (!_isReadOnly) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.person_remove_rounded, size: 18, color: Colors.white),
                    label: Text('Force Exit', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _forceExitMember,
                  ),
                ),
              ],
            ],
          ),
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
      child: _buildSectionCard(
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
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFFFF7F0), borderRadius: BorderRadius.circular(6)),
                              child: Text(sessionType.toUpperCase(), style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                            ),
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
            title: mStatus == 'active' ? 'Membership activated' : 'Membership ${mStatus}',
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
                  IconButton(icon: const Icon(Icons.edit_rounded, color: Colors.white), onPressed: _showEditMemberDialog),
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
                          child: CircleAvatar(
                            radius: 36,
                            backgroundColor: const Color(0xFFFFF7F0),
                            backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                            child: photo.isEmpty ? const Icon(Icons.person, color: Color(0xFFE65C00), size: 36) : null,
                          ),
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

                  // 4. Tab Views
                  IndexedStack(
                    index: _activeTab,
                    children: [
                      _buildOverviewTab(),
                      _buildAttendanceTab(),
                      _buildPaymentsTab(),
                      _buildActivityTab(),
                      _buildNotesTab(),
                    ],
                  ),
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
