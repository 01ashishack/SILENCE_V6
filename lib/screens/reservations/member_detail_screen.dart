import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class MemberDetailScreen extends StatefulWidget {
  const MemberDetailScreen({super.key});

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _errorMessage;
  String? _memberId;

  // Data states
  Map<String, dynamic>? _membershipData;
  List<Map<String, dynamic>> _attendanceList = [];
  List<Map<String, dynamic>> _paymentsList = [];

  // Tab state
  int _activeTab = 0;
  final List<String> _tabNames = ['Overview', 'Attendance', 'Payments', 'Activity', 'Notes'];

  // Calendar State
  DateTime _calendarMonth = DateTime.now();

  // Notes controller
  final _notesController = TextEditingController();
  bool _isSavingNote = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_memberId == null) {
      final args = ModalRoute.of(context)!.settings.arguments;
      if (args is String) {
        _memberId = args;
        _fetchMemberData();
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Invalid or missing Member ID argument';
        });
      }
    }
  }

  // ── Fetch All Member Details ──────────────────────────────────────────────
  Future<void> _fetchMemberData() async {
    final mId = _memberId;
    if (mId == null) return;

    try {
      if (mounted) setState(() => _isLoading = true);

      // 1. Fetch current membership details
      final membershipRes = await supabase
          .from('memberships')
          .select('*, member_id(id, full_name, phone, photo_url, nickname, created_at), seats(seat_label), shifts(name)')
          .eq('member_id', mId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      // 2. Fetch attendance history
      final attendanceRes = await supabase
          .from('attendance')
          .select('*')
          .eq('member_id', mId)
          .order('check_in_time', ascending: false);

      // 3. Fetch payment history
      final paymentsRes = await supabase
          .from('payments')
          .select('*')
          .eq('member_id', mId)
          .order('payment_date', ascending: false);

      if (mounted) {
        setState(() {
          _membershipData = membershipRes;
          _attendanceList = List<Map<String, dynamic>>.from(attendanceRes);
          _paymentsList = List<Map<String, dynamic>>.from(paymentsRes);
          
          // Pre-populate private note
          final String userNote = membershipRes?['member_id']?['nickname'] ?? '';
          _notesController.text = userNote;
          
          _isLoading = false;
          _errorMessage = null;
        });
      }
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

  // ── Edit Member Details Dialog ─────────────────────────────────────────────
  void _showEditMemberDialog() {
    final name = _membershipData?['member_id']?['full_name'] ?? '';
    final phone = _membershipData?['member_id']?['phone'] ?? '';

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
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number'),
            ),
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
                }).eq('id', _memberId!);

                _fetchMemberData();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member profile updated successfully! ✓')));
                }
              } catch (e) {
                if (context.mounted) {
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

  // ── Save Private Note ──────────────────────────────────────────────────────
  Future<void> _savePrivateNote() async {
    final mId = _memberId;
    if (mId == null) return;

    try {
      setState(() => _isSavingNote = true);

      await supabase.from('users').update({
        'nickname': _notesController.text.trim(),
      }).eq('id', mId);

      // Refresh local membership details cache to update UI state
      if (_membershipData != null && _membershipData!['member_id'] != null) {
        _membershipData!['member_id']!['nickname'] = _notesController.text.trim();
      }

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

  // ── Confirms Pending Payment Directly ──────────────────────────────────────
  Future<void> _confirmPayment(String paymentId) async {
    try {
      setState(() => _isLoading = true);
      
      final currentAdminId = supabase.auth.currentUser?.id;

      await supabase.from('payments').update({
        'status': 'confirmed',
        'confirmed_by_admin_id': currentAdminId,
      }).eq('id', paymentId);

      await _fetchMemberData();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment confirmed successfully! ✓')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error confirming payment: $e')),
        );
      }
    }
  }

  // ── Rejects Pending Payment Directly ───────────────────────────────────────
  Future<void> _rejectPayment(String paymentId) async {
    try {
      setState(() => _isLoading = true);

      await supabase.from('payments').update({
        'status': 'rejected',
      }).eq('id', paymentId);

      await _fetchMemberData();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment marked as rejected. ✓')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error rejecting payment: $e')),
        );
      }
    }
  }

  // ── Manual Attendance Edit/Addition Modal ──────────────────────────────────
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
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    session != null ? 'Edit Attendance Session' : 'Add Manual Attendance',
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Date: ${DateFormat('dd MMMM yyyy').format(date)}',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),

                  // Check In Time Picker
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Check-in Time:', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                      TextButton.icon(
                        icon: const Icon(Icons.access_time_rounded, size: 18, color: Color(0xFFE65C00)),
                        label: Text(checkInTime.format(context), style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: checkInTime);
                          if (picked != null) {
                            setModalState(() => checkInTime = picked);
                          }
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 1),

                  // Check Out Time Picker
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Check-out Time:', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                      TextButton.icon(
                        icon: const Icon(Icons.access_time_rounded, size: 18, color: Color(0xFFE65C00)),
                        label: Text(checkOutTime.format(context), style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: checkOutTime);
                          if (picked != null) {
                            setModalState(() => checkOutTime = picked);
                          }
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 16),

                  // Edit Reason Field
                  TextField(
                    controller: reasonController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Edit Reason (Required)',
                      hintText: 'e.g. Forgot to scan out / manual addition by Admin',
                      fillColor: Color(0xFFF8FAFC),
                    ),
                  ),
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
                          // Update attendance record
                          await supabase.from('attendance').update({
                            'check_in_time': checkInDateTime.toUtc().toIso8601String(),
                            'check_out_time': checkOutDateTime.toUtc().toIso8601String(),
                            'duration_minutes': durationMins,
                            'session_type': 'admin_edited',
                            'edited_by_admin_id': currentAdminId,
                            'edit_reason': reasonController.text.trim(),
                          }).eq('id', session['id']);
                        } else {
                          // Insert new manual attendance record
                          final membershipId = _membershipData?['id'];
                          final libraryId = _membershipData?['library_id'];
                          final shiftId = _membershipData?['shift_id'];

                          if (membershipId == null || libraryId == null || shiftId == null) {
                            throw 'Membership details missing. Cannot log attendance.';
                          }

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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
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

  // ── Calculation Helpers ────────────────────────────────────────────────────
  int _calculateStreak() {
    if (_attendanceList.isEmpty) return 0;
    
    final dates = _attendanceList
        .map((a) {
          try {
            final dt = DateTime.parse(a['check_in_time']).toLocal();
            return DateTime(dt.year, dt.month, dt.day);
          } catch (_) {
            return null;
          }
        })
        .whereType<DateTime>()
        .toSet()
        .toList();
    
    dates.sort((a, b) => b.compareTo(a)); // Descending
    if (dates.isEmpty) return 0;

    final today = DateTime.now();
    final dateToday = DateTime(today.year, today.month, today.day);
    final dateYesterday = dateToday.subtract(const Duration(days: 1));

    // If the latest check-in is before yesterday, streak is broken
    if (dates.first.isBefore(dateYesterday)) {
      return 0;
    }

    int streak = 0;
    DateTime current = dates.first;

    for (int i = 0; i < dates.length; i++) {
      if (i == 0) {
        streak = 1;
        continue;
      }
      final expectedPrev = current.subtract(const Duration(days: 1));
      if (dates[i] == expectedPrev) {
        streak++;
        current = dates[i];
      } else if (dates[i] == current) {
        continue; // Same day duplicates
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
      } catch (_) {
        return false;
      }
    }).length;
  }

  int _calculateTotalPaid() {
    return _paymentsList
        .where((p) => p['status'] == 'confirmed')
        .fold(0, (sum, p) => sum + ((p['amount'] as num?)?.toInt() ?? 0));
  }

  int _calculateDues() {
    final String planType = _membershipData?['plan_type'] ?? 'monthly';
    int planCost = 1500;
    if (planType == '3_month') planCost = 4000;
    if (planType == '6_month') planCost = 7500;
    
    final paid = _calculateTotalPaid();
    final dues = planCost - paid;
    return dues > 0 ? dues : 0;
  }

  String _getLastPayDate() {
    final confirmedPays = _paymentsList.where((p) => p['status'] == 'confirmed').toList();
    if (confirmedPays.isEmpty) return 'No payments yet';
    try {
      final dt = DateTime.parse(confirmedPays.first['payment_date']).toLocal();
      return DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {
      return 'N/A';
    }
  }

  // ── Render Utilities ───────────────────────────────────────────────────────
  Widget _buildStatusBadge(String status) {
    Color bg = const Color(0xFFF3F4F6);
    Color txt = const Color(0xFF6B7280);
    String label = status.toUpperCase();

    if (status == 'active') {
      bg = const Color(0xFFDCFCE7);
      txt = const Color(0xFF16A34A);
    } else if (status == 'expired') {
      bg = const Color(0xFFFEE2E2);
      txt = const Color(0xFFDC2626);
    } else if (status == 'hold') {
      bg = const Color(0xFFFEF3C7);
      txt = const Color(0xFFD97706);
    } else if (status == 'trial') {
      bg = const Color(0xFFEDE9FE);
      txt = const Color(0xFF7C3AED);
      label = 'TRIAL';
    } else if (status == 'exited') {
      bg = const Color(0xFFF3F4F6);
      txt = const Color(0xFF6B7280);
      label = 'EXITED';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: txt),
      ),
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
        Text(value, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E))),
      ],
    );
  }

  // ── Tab 1: Overview Tab ────────────────────────────────────────────────────
  Widget _buildOverviewTab() {
    final String startDateStr = _membershipData?['start_date'] ?? '';
    final String endDateStr = _membershipData?['end_date'] ?? '';
    final String status = _membershipData?['status'] ?? 'pending';

    String fmtStart = 'N/A';
    String fmtEnd = 'N/A';
    try {
      if (startDateStr.isNotEmpty) fmtStart = DateFormat('dd MMM yyyy').format(DateTime.parse(startDateStr));
      if (endDateStr.isNotEmpty) fmtEnd = DateFormat('dd MMM yyyy').format(DateTime.parse(endDateStr));
    } catch (_) {}

    final totalVisits = _attendanceList.length;
    final thisMonthVisits = _calculateThisMonthVisits();
    final streak = _calculateStreak();

    final totalPaid = _calculateTotalPaid();
    final dues = _calculateDues();
    final lastPay = _getLastPayDate();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Membership Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Membership Details', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Started', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280))),
                    Text(fmtStart, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Expires', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280))),
                    Text(fmtEnd, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Status', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280))),
                    _buildStatusBadge(status),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Attendance Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Attendance Summary', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text('$totalVisits', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                        const SizedBox(height: 4),
                        Text('Total Visits', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF6B7280))),
                      ],
                    ),
                    Column(
                      children: [
                        Text('$thisMonthVisits', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                        const SizedBox(height: 4),
                        Text('This Month', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF6B7280))),
                      ],
                    ),
                    Column(
                      children: [
                        Text('$streak', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                        const SizedBox(height: 4),
                        Text('Streak Days', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF6B7280))),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Payment Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Payment Summary', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Paid', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280))),
                    Text('₹$totalPaid', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Dues Outstanding', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: dues == 0 ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '₹$dues',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: dues == 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Last Payment', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280))),
                    Text(lastPay, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 2: Attendance Tab (Interactive Monthly Calendar) ───────────────────
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
    final prefixEmptyCells = firstDayOfMonth.weekday % 7; // Su: 0, Mo: 1, ... Sa: 6 in DateTime Su=7, but Su%7=0

    final List<String> weekdays = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Month Switcher Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Color(0xFFE65C00)),
                  onPressed: () {
                    setState(() {
                      _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1, 1);
                    });
                  },
                ),
                Text(
                  DateFormat('MMMM yyyy').format(_calendarMonth),
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFFE65C00)),
                  onPressed: () {
                    setState(() {
                      _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1);
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Weekday row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: weekdays.map((day) {
                return SizedBox(
                  width: 38,
                  child: Text(
                    day,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),

            // Days Grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: prefixEmptyCells + totalDaysInMonth,
              itemBuilder: (ctx, index) {
                if (index < prefixEmptyCells) {
                  return const SizedBox.shrink();
                }

                final day = index - prefixEmptyCells + 1;
                final date = DateTime(_calendarMonth.year, _calendarMonth.month, day);
                final sessions = sessionMap[day] ?? [];
                final hasAttendance = sessions.isNotEmpty;

                return InkWell(
                  onTap: () {
                    // Open attendance detail/edit bottom sheet
                    _showAttendanceDayDetailSheet(date: date, sessions: sessions);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: hasAttendance ? const Color(0xFFFFF7F0) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: hasAttendance ? const Color(0xFFFFD8BE) : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          '$day',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: hasAttendance ? FontWeight.bold : FontWeight.normal,
                            color: hasAttendance ? const Color(0xFFE65C00) : const Color(0xFF1E293B),
                          ),
                        ),
                        if (hasAttendance)
                          Positioned(
                            bottom: 4,
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(color: Color(0xFFE65C00), shape: BoxShape.circle),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
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
              Text(
                DateFormat('EEEE, dd MMMM yyyy').format(date),
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 16),
              if (sessions.isEmpty) ...[
                Text('No attendance sessions logged for this day.', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500])),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showAttendanceModal(date: date);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Manual Session'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                ),
              ] else ...[
                ...sessions.map((s) {
                  final String ciStr = s['check_in_time'] ?? '';
                  final String? coStr = s['check_out_time'];
                  final int? dur = s['duration_minutes'];
                  final String sessionType = s['session_type'] ?? 'normal';

                  String checkIn = 'N/A';
                  String checkOut = 'Not scanned out';
                  try {
                    if (ciStr.isNotEmpty) checkIn = DateFormat('hh:mm a').format(DateTime.parse(ciStr).toLocal());
                    if (coStr != null && coStr.isNotEmpty) checkOut = DateFormat('hh:mm a').format(DateTime.parse(coStr).toLocal());
                  } catch (_) {}

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
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
                              child: Text(
                                sessionType.toUpperCase(),
                                style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('In: $checkIn', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B))),
                        Text('Out: $checkOut', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B))),
                        if (dur != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Duration: $dur minutes (${(dur / 60).toStringAsFixed(1)} hours)', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic)),
                          ),
                        if (s['edit_reason'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Reason: ${s['edit_reason']}', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFDC2626))),
                          ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showAttendanceModal(session: s, date: date);
                          },
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Edit Duration'),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white, elevation: 0),
                        ),
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

  // ── Tab 3: Payments Tab ────────────────────────────────────────────────────
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
        
        String payDate = 'N/A';
        try {
          if (payment['payment_date'] != null) {
            payDate = DateFormat('dd MMMM yyyy, hh:mm a').format(DateTime.parse(payment['payment_date']).toLocal());
          }
        } catch (_) {}

        Color statusBg = const Color(0xFFF3F4F6);
        Color statusText = const Color(0xFF6B7280);
        if (status == 'confirmed') {
          statusBg = const Color(0xFFDCFCE7);
          statusText = const Color(0xFF16A34A);
        } else if (status == 'rejected') {
          statusBg = const Color(0xFFFEE2E2);
          statusText = const Color(0xFFDC2626);
        } else if (status == 'pending') {
          statusBg = const Color(0xFFFEF3C7);
          statusText = const Color(0xFFD97706);
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 8, offset: const Offset(0, 2))],
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
                  Text('$method', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF475569))),
                  const SizedBox(width: 8),
                  Text('•  $payDate', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600])),
                ],
              ),
              if (refId.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Ref ID: $refId', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic)),
                ),
              if (sender.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Sender: $sender', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
                ),
              
              // Approve / Reject actions for pending payments
              if (status == 'pending') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _rejectPayment(payment['id']),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          side: const BorderSide(color: Color(0xFFDC2626)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: Text('Reject Pay', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _confirmPayment(payment['id']),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: Text('Confirm Pay', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
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

  // ── Tab 4: Activity Timeline Tab ───────────────────────────────────────────
  Widget _buildActivityTab() {
    // Collect and sort all events chronologically desc
    final List<_ActivityEventItem> events = [];

    // 1. Registration / Join date
    final String regDateStr = _membershipData?['member_id']?['created_at'] ?? '';
    if (regDateStr.isNotEmpty) {
      try {
        events.add(_ActivityEventItem(
          timestamp: DateTime.parse(regDateStr).toLocal(),
          title: 'Joined library',
          subtitle: 'Profile successfully registered.',
          icon: Icons.person_add_rounded,
          color: const Color(0xFF3B82F6),
        ));
      } catch (_) {}
    }

    // 2. Seat Assignment
    final String approvedAtStr = _membershipData?['approved_at'] ?? _membershipData?['created_at'] ?? '';
    final String seatLabel = _membershipData?['seats']?['seat_label'] ?? '';
    if (approvedAtStr.isNotEmpty && seatLabel.isNotEmpty) {
      try {
        events.add(_ActivityEventItem(
          timestamp: DateTime.parse(approvedAtStr).toLocal(),
          title: 'Seat assigned',
          subtitle: 'Seat $seatLabel assigned.',
          icon: Icons.chair_alt_rounded,
          color: const Color(0xFFE65C00),
        ));
      } catch (_) {}
    }

    // 3. Attendance records
    for (final a in _attendanceList) {
      try {
        final start = DateTime.parse(a['check_in_time']).toLocal();
        String outStr = '';
        if (a['check_out_time'] != null) {
          final outDt = DateTime.parse(a['check_out_time']).toLocal();
          outStr = ' (Out: ${DateFormat('hh:mm a').format(outDt)})';
        }
        events.add(_ActivityEventItem(
          timestamp: start,
          title: 'Check-in registered',
          subtitle: 'Logged check-in at ${DateFormat('hh:mm a').format(start)}$outStr.',
          icon: Icons.qr_code_scanner_rounded,
          color: const Color(0xFF10B981),
        ));
      } catch (_) {}
    }

    // 4. Payments
    for (final p in _paymentsList) {
      try {
        final payDt = DateTime.parse(p['payment_date']).toLocal();
        final amt = p['amount'] ?? 0;
        final status = p['status'] ?? 'pending';
        events.add(_ActivityEventItem(
          timestamp: payDt,
          title: 'Payment processed',
          subtitle: 'Amount ₹$amt status: $status.',
          icon: Icons.payment_rounded,
          color: status == 'confirmed' ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
        ));
      } catch (_) {}
    }

    // Sort descending by timestamp
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No timeline activity records.', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
          ],
        ),
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
            // Dot & Line column
            Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: ev.color.withOpacity(0.12), shape: BoxShape.circle),
                  child: Icon(ev.icon, size: 15, color: ev.color),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 50,
                    color: Colors.grey[200],
                  ),
              ],
            ),
            const SizedBox(width: 16),

            // Content column
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(ev.title, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                        Text(
                          DateFormat('dd MMM, hh:mm a').format(ev.timestamp),
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[400]),
                        ),
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

  // ── Tab 5: Notes Tab ───────────────────────────────────────────────────────
  Widget _buildNotesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Private Admin Notes', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
            const SizedBox(height: 6),
            Text(
              'These notes are fully private and only visible to library administrators. They are never shown to the members.',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500], height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: 'Type admin notes, member reminders or history logs here...',
                fillColor: Color(0xFFF8FAFC),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isSavingNote ? null : _savePrivateNote,
              icon: _isSavingNote
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                  : const Icon(Icons.save_rounded, size: 16),
              label: Text('Save Note', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFBF5EE),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBF5EE),
        appBar: AppBar(
          backgroundColor: const Color(0xFFE65C00),
          title: Text('Profile Error', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, size: 64, color: Color(0xFFDC2626)),
                const SizedBox(height: 16),
                Text(_errorMessage!, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[700])),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _fetchMemberData,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final member = _membershipData?['member_id'];
    if (member == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBF5EE),
        appBar: AppBar(
          backgroundColor: const Color(0xFFE65C00),
          title: Text('No Data Found', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        body: Center(
          child: Text('This user does not have an active membership profile.', style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[700])),
        ),
      );
    }

    final String name = member['full_name'] ?? 'No Name';
    final String photo = member['photo_url'] ?? '';
    final String status = _membershipData?['status'] ?? 'pending';

    // 4-cell fields
    final String seatLabel = _membershipData?['seats']?['seat_label'] ?? 'No Seat';
    final String shiftName = _membershipData?['shifts']?['name'] ?? 'No Shift';
    final String rawPlan = _membershipData?['plan_type'] ?? 'monthly';
    final String expiryStr = _membershipData?['end_date'] ?? '';

    String planText = '1 Month';
    if (rawPlan == '3_month') planText = '3 Months';
    if (rawPlan == '6_month') planText = '6 Months';

    String expiryText = 'N/A';
    try {
      if (expiryStr.isNotEmpty) {
        expiryText = DateFormat('dd MMM').format(DateTime.parse(expiryStr));
      }
    } catch (_) {}

    return Scaffold(
      backgroundColor: const Color(0xFFFBF5EE),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Vibrant Orange Header
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              bottom: 16,
              left: 12,
              right: 12,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFF6B00),
                  Color(0xFFE65C00),
                ],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      'Member Details',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.edit_rounded, color: Colors.white),
                  onPressed: _showEditMemberDialog,
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 2. White Profile Header Card
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Dynamic photo with orange ring border
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: Color(0xFFE65C00), shape: BoxShape.circle),
                          child: CircleAvatar(
                            radius: 32,
                            backgroundColor: const Color(0xFFFFF7F0),
                            backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                            child: photo.isEmpty
                                ? const Icon(Icons.person, color: Color(0xFFE65C00), size: 32)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Name 20px 700
                        Text(
                          name,
                          style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E)),
                        ),
                        const SizedBox(height: 6),

                        // Status Badge
                        _buildStatusBadge(status),
                        const SizedBox(height: 6),

                        // Member ID
                        Text(
                          'ID: ${_memberId?.substring(0, 8).toUpperCase() ?? "N/A"}',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF6B7280)),
                        ),
                        const SizedBox(height: 16),

                        // 4-cell info grid
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFF1F5F9)),
                          ),
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

                  // 3. Tab Bar navigation (Overview, Attendance, Payments, Activity, Notes)
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
                                  Text(
                                    _tabNames[index],
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                                      color: isActive ? const Color(0xFFE65C00) : const Color(0xFF6B7280),
                                    ),
                                  ),
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
