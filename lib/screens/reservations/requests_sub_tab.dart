import 'dart:async';
import '../../theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../utils/audit_logger.dart';
import '../../utils/error_messages.dart';
import '../../utils/time_utils.dart';
import '../../widgets/states/shimmer_box.dart';

class RequestsSubTab extends StatefulWidget {
  final String libraryId;
  const RequestsSubTab({super.key, required this.libraryId});

  @override
  State<RequestsSubTab> createState() => _RequestsSubTabState();
}

class _RequestsSubTabState extends State<RequestsSubTab> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isProfileComplete = true;
  // Re-entrancy guard so a fast double-tap can't create two memberships/payments.
  bool _isApproving = false;

  // Horizontal Toggle
  int _activeRequestTab = 0; // 0: Join, 1: Seat Changes, 2: Holds, 3: Check-ins

  // Lists
  List<Map<String, dynamic>> _joinRequests = [];
  List<Map<String, dynamic>> _seatChangeRequests = [];
  List<Map<String, dynamic>> _holdRequests = [];
  // Out-of-shift check-in approval requests (2026-06-22).
  List<Map<String, dynamic>> _checkinApprovals = [];

  // Local state tracking for UPI confirmations (Request ID -> confirmed in UI)
  final Set<String> _confirmedPaymentsInUi = {};

  // Honest per-request amount (plan price − discount), Request ID -> ₹. Computed
  // in _fetchRequests so the card shows a real figure (not a hardcoded one).
  Map<String, int> _requestAmounts = {};

  // Realtime subscription channels
  RealtimeChannel? _requestsChannel;

  Future<void> _checkOnboardingStatus() async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        final userData = await supabase.from('users').select().eq('id', user.id).maybeSingle();
        if (userData != null) {
          final String name = userData['full_name'] ?? '';
          final String phone = userData['phone'] ?? '';
          final String gender = userData['gender'] ?? '';
          final String dob = userData['date_of_birth'] ?? '';
          final String address = userData['address'] ?? '';
          final String photoUrl = userData['photo_url'] ?? '';

          final bool isComplete = name.isNotEmpty &&
              phone.isNotEmpty &&
              gender.isNotEmpty &&
              dob.isNotEmpty &&
              address.isNotEmpty &&
              photoUrl.isNotEmpty;
          
          if (mounted) {
            setState(() {
              _isProfileComplete = isComplete;
            });
          }
        }
      } catch (e) {
        debugPrint('Error in _checkOnboardingStatus: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus().then((_) {
      _fetchRequests();
    });
    _setupRealtimeSubscription();
  }

  @override
  void didUpdateWidget(covariant RequestsSubTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.libraryId != widget.libraryId) {
      setState(() {
        _isLoading = true;
      });
      _checkOnboardingStatus().then((_) {
        _fetchRequests();
      });
    }
  }

  @override
  void dispose() {
    if (_requestsChannel != null) {
      supabase.removeChannel(_requestsChannel!);
    }
    super.dispose();
  }

  // ── Setup Realtime ────────────────────────────────────────────────────────
  void _setupRealtimeSubscription() {
    _requestsChannel = supabase
        .channel('public:requests_sub_tab')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'join_requests',
          callback: (payload) {
            if (mounted) {
              _fetchRequests();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'checkin_approvals',
          callback: (payload) {
            if (mounted) {
              _fetchRequests();
            }
          },
        )
        .subscribe();
  }

  // ── Fetch Requests ───────────────────────────────────────────────────────
  Future<void> _fetchRequests() async {
    try {
      // 1. Fetch pending Join Requests
      final joinRes = await supabase
          .from('join_requests')
          .select('*, member_id(id, full_name, phone, photo_url), shifts(name), seats:requested_seat_id(seat_label)')
          .eq('library_id', widget.libraryId)
          .eq('status', 'pending')
          .order('created_at', ascending: true);

      // 2. Fetch pending Seat Changes
      final changeRes = await supabase
          .from('seat_change_requests')
          .select('*, member_id(id, full_name, phone, photo_url), current_seat:current_seat_id(seat_label), new_seat:new_seat_id(seat_label)')
          .eq('library_id', widget.libraryId)
          .eq('status', 'pending')
          .order('created_at', ascending: true);

      // 3. Fetch pending Holds
      final holdRes = await supabase
          .from('hold_requests')
          .select('*, member_id(id, full_name, phone, photo_url)')
          .eq('library_id', widget.libraryId)
          .eq('status', 'pending')
          .order('created_at', ascending: true);

      // 4. Fetch pending out-of-shift Check-in approvals
      final checkinRes = await supabase
          .from('checkin_approvals')
          .select('*, member_id(id, full_name, phone, photo_url), shifts(name, start_time, end_time)')
          .eq('library_id', widget.libraryId)
          .eq('status', 'pending')
          .order('created_at', ascending: true);

      final joinList = List<Map<String, dynamic>>.from(joinRes);

      // Honest amount per join request (plan price − discount). Low volume
      // (pending only), so a per-request lookup is fine.
      final Map<String, int> amounts = {};
      for (final r in joinList) {
        try {
          amounts[r['id'].toString()] = await _computeApprovalAmount(
            shiftId: r['shift_id']?.toString(),
            planType: (r['plan_type'] ?? 'monthly').toString(),
            discount: (r['discount_amount'] as int?) ?? 0,
          );
        } catch (e) {
          debugPrint('amount compute failed: $e');
        }
      }

      if (mounted) {
        setState(() {
          _joinRequests = joinList;
          _seatChangeRequests = List<Map<String, dynamic>>.from(changeRes);
          _holdRequests = List<Map<String, dynamic>>.from(holdRes);
          _checkinApprovals = List<Map<String, dynamic>>.from(checkinRes);
          _requestAmounts = amounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching requests: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Confirm / Reject Payments ─────────────────────────────────────────────
  // Payment verification is now SEPARATE from the membership decision. It only
  // sets join_requests.payment_status; the request stays pending either way, so
  // the admin can still Approve/Reject. Only the membership Reject cancels it.
  Future<void> _confirmPayment(String requestId) async {
    try {
      await supabase.from('join_requests').update({
        'payment_status': 'verified',
      }).eq('id', requestId);
      if (mounted) setState(() => _confirmedPaymentsInUi.add(requestId));
      _fetchRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment verified. You can approve now. ✓')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${friendlyError(e)}')),
      );
    }
  }

  Future<void> _rejectPayment(Map<String, dynamic> request) async {
    final requestId = request['id']?.toString() ?? '';
    final memberId = request['member_id']?['id']?.toString();
    if (requestId.isEmpty) return;
    try {
      // Mark the payment unverified — do NOT cancel the join request.
      await supabase.from('join_requests').update({
        'payment_status': 'rejected',
      }).eq('id', requestId);
      if (mounted) setState(() => _confirmedPaymentsInUi.remove(requestId));

      // Honest: notify the member their payment wasn't verified so they re-pay.
      if (memberId != null) {
        await _notifyMember(
          memberId: memberId,
          title: 'Payment not verified',
          message: "We couldn't verify your payment for the join request. "
              'Please pay again and re-upload the proof — your request is still '
              'pending and will be reviewed once payment is confirmed.',
          type: 'payment_rejected',
        );
      }

      _fetchRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment marked unverified. Member notified to re-pay. Request kept pending.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${friendlyError(e)}')),
      );
    }
  }

  // ── Reject Join Request ───────────────────────────────────────────────────
  Future<void> _rejectJoinRequest(Map<String, dynamic> request) async {
    final requestId = request['id']?.toString() ?? '';
    final memberId = request['member_id']?['id']?.toString();
    final reasonController = TextEditingController();
    // Quick-pick templates so the admin rarely has to type a reason.
    const reasonTemplates = <String>[
      'ID documents are missing or unclear',
      'Payment not received / proof unclear',
      'Selected seat or shift is unavailable',
      'Profile details are incomplete',
    ];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Reject Request', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pick a reason (or type your own):', style: GoogleFonts.inter(fontSize: 13)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: reasonTemplates.map((t) {
                    final selected = reasonController.text == t;
                    return ChoiceChip(
                      label: Text(t, style: GoogleFonts.inter(fontSize: 12)),
                      selected: selected,
                      selectedColor: const Color(0xFFE65C00).withValues(alpha: 0.15),
                      onSelected: (_) => setDialog(() => reasonController.text = t),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  onChanged: (_) => setDialog(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Reason shown to the member',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Reject', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    ) ?? false;

    if (!confirm) return;

    final reason = reasonController.text.trim().isNotEmpty
        ? reasonController.text.trim()
        : 'Rejected by Admin';

    try {
      await supabase.from('join_requests').update({
        'status': 'rejected',
        'rejection_reason': reason,
      }).eq('id', requestId);

      // Notify the member (honest: only after the write).
      if (memberId != null) {
        await _notifyMember(
          memberId: memberId,
          title: 'Join request not approved',
          message: 'Your request was not approved. Reason: $reason. '
              'You can contact the admin or apply again.',
          type: 'join_rejected',
        );
      }
      await _logAudit(
        action: 'membership_reject',
        category: AuditLogger.categoryMembers,
        title: 'Rejected join request',
        details: '${request['member_id']?['full_name'] ?? 'Member'} · $reason',
      );

      _fetchRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join request rejected.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  // ── Final Database Seat Assignment and Activation (S034 Flow) ─────────────
  /// Confirm-assignment dialog with optional discount + an editable start date
  /// (pre-filled with an existing offline member's chosen joining date). Returns
  /// {discount, reason, startDate} or null if cancelled.
  Future<Map<String, dynamic>?> _confirmAssignmentDialog(
      Map<String, dynamic> request, Map<String, dynamic> seat) async {
    final discountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final existingJoin =
        DateTime.tryParse(request['existing_member_join_date']?.toString() ?? '');
    final bool isExisting = existingJoin != null;
    DateTime startDate = existingJoin ?? DateTime.now();
    final memberName = request['member_id']?['full_name'] ?? 'this member';

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('Confirm assignment', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Seat ${seat['seat_label']} → $memberName',
                    style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(isExisting ? 'Joining / plan start date' : 'Plan starts on',
                          style: GoogleFonts.inter(fontSize: 13)),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 15),
                      label: Text(DateFormat('dd MMM yyyy').format(startDate)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: c,
                          initialDate: startDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 31)),
                        );
                        if (picked != null) setD(() => startDate = picked);
                      },
                    ),
                  ],
                ),
                if (isExisting)
                  Text('Existing (offline) member — set their real joining date.',
                      style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted)),
                const SizedBox(height: 8),
                TextField(
                  controller: discountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '₹ Discount on plan (optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Discount reason (optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00)),
              onPressed: () => Navigator.pop(c, {
                'discount': int.tryParse(discountCtrl.text.trim()),
                'reason': reasonCtrl.text.trim(),
                'startDate': startDate,
              }),
              child: const Text('Confirm', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approveJoinRequestTransaction(
    BuildContext sheetContext,
    Map<String, dynamic> request,
    Map<String, dynamic> seat, {
    int? discount,
    String? discountReason,
    DateTime? startDate,
  }) async {
    if (_isApproving) return; // ignore double-taps
    _isApproving = true;
    try {
      final String seatLabel = seat['seat_label'];
      final String requestId = request['id'];
      final String memberName = request['member_id']['full_name'] ?? 'Member';

      // Atomic server-side approval (audit C3 + C5/M7): claims the seat, derives
      // the amount, and upserts membership + payment + add-ons + request status +
      // notification + audit in ONE transaction. A seat race or any mid-step
      // failure rolls the whole thing back — no double-booking, no half-approval.
      final res = await supabase.rpc('approve_join_request', params: {
        'p_request_id': requestId,
        'p_seat_id': seat['id'],
        if (discount != null && discount > 0) 'p_discount': discount,
        if (discountReason != null && discountReason.trim().isNotEmpty)
          'p_discount_reason': discountReason.trim(),
        if (startDate != null) 'p_start_date': DateFormat('yyyy-MM-dd').format(startDate),
      });
      final data = (res is List && res.isNotEmpty) ? res.first : res;
      final assignedSeat =
          (data is Map ? data['seat_label'] : null)?.toString() ?? seatLabel;

      _fetchRequests();
      if (!mounted) return;
      if (sheetContext.mounted) Navigator.pop(sheetContext); // Close seat picker bottom sheet
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Member $memberName approved and seat $assignedSeat assigned successfully.",
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500),
          ),
          backgroundColor: const Color(0xFF22C55E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    } finally {
      _isApproving = false;
    }
  }

  /// Real plan amount = shift price for the chosen plan − discount (≥ 0).
  /// Falls back to monthly×N if a multi-month price column is null.
  Future<int> _computeApprovalAmount({
    required String? shiftId,
    required String planType,
    required int discount,
  }) async {
    int base = 0;
    if (shiftId != null) {
      try {
        final shift = await supabase
            .from('shifts')
            .select('price_monthly, price_3month, price_6month')
            .eq('id', shiftId)
            .maybeSingle();
        if (shift != null) {
          final monthly = (shift['price_monthly'] as int?) ?? 0;
          switch (planType) {
            case '3_month':
              base = (shift['price_3month'] as int?) ?? monthly * 3;
              break;
            case '6_month':
              base = (shift['price_6month'] as int?) ?? monthly * 6;
              break;
            case 'trial':
              base = 0;
              break;
            default:
              base = monthly;
          }
        }
      } catch (e) {
        debugPrint('Shift price lookup failed: $e');
      }
    }
    final net = base - (discount > 0 ? discount : 0);
    return net < 0 ? 0 : net;
  }

  String _planLabel(String planType) {
    switch (planType) {
      case '3_month':
        return '3-month plan';
      case '6_month':
        return '6-month plan';
      case 'trial':
        return 'Trial';
      default:
        return 'Monthly plan';
    }
  }

  // ── Show Seat Picker Modal for Approving (S034 Flow) ──────────────────────
  Future<void> _logAudit({
    required String title,
    required String details,
    required String category,
    String action = 'update',
  }) async {
    await AuditLogger.instance.log(
      action: action,
      category: category,
      title: title,
      details: details,
      libraryId: widget.libraryId,
    );
  }

  Future<void> _notifyMember({
    required String memberId,
    required String title,
    required String message,
    String type = 'info',
  }) async {
    try {
      // Schema columns: user_id, title, body, data, sent_at(default now),
      // read_at(default null = unread). Do NOT send is_read/created_at — those
      // columns don't exist and make the insert throw.
      await supabase.from('notifications').insert({
        'user_id': memberId,
        'title': title,
        'body': message,
        'data': {'type': type},
      });
    } catch (e) {
      debugPrint('Notification insert failed: $e');
    }
  }

  Future<void> _rejectSeatChangeRequest(Map<String, dynamic> request) async {
    final requestId = request['id']?.toString();
    final memberId =
        request['member_id']?['id']?.toString() ?? request['member_id']?.toString();
    if (requestId == null || memberId == null) return;

    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reject Seat Change', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reject this seat change request? The member will be notified.',
                style: GoogleFonts.inter(fontSize: 13, color: context.palette.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Reason (optional)', hintText: 'e.g. Requested seat unavailable'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final reason = reasonController.text.trim();
    try {
      setState(() => _isLoading = true);
      await supabase.from('seat_change_requests').update({'status': 'rejected'}).eq('id', requestId);
      await _logAudit(
        title: 'Seat Change Rejected',
        details: 'Rejected seat change for member $memberId.${reason.isNotEmpty ? ' Reason: $reason' : ''}',
        category: 'members',
      );
      await _notifyMember(
        memberId: memberId,
        title: 'Seat change rejected',
        message: reason.isNotEmpty
            ? 'Your seat change request was rejected. Reason: $reason'
            : 'Your seat change request was rejected.',
        type: 'seat_change',
      );
      await _fetchRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not reject: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _approveSeatChangeRequest(Map<String, dynamic> request) async {
    final requestId = request['id']?.toString();
    final membershipId = request['membership_id']?.toString();
    final memberId =
        request['member_id']?['id']?.toString() ?? request['member_id']?.toString();
    final oldSeatId = request['current_seat_id']?.toString();
    final newSeatId = request['new_seat_id']?.toString();
    final newSeatLabel =
        request['new_seat']?['seat_label']?.toString() ?? 'the new seat';

    if (requestId == null ||
        membershipId == null ||
        memberId == null ||
        newSeatId == null ||
        newSeatId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot approve: this request has no selected target seat.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      setState(() => _isLoading = true);

      final newSeat = await supabase
          .from('seats')
          .select('status, occupied_by_member_id, seat_label')
          .eq('id', newSeatId)
          .single();

      final occupiedBy = newSeat['occupied_by_member_id'];
      if (newSeat['status'] != 'vacant' &&
          occupiedBy != null &&
          occupiedBy.toString() != memberId) {
        throw 'Target seat is no longer vacant. Please choose another seat.';
      }

      await supabase.from('memberships').update({
        'seat_id': newSeatId,
      }).eq('id', membershipId);

      if (oldSeatId != null && oldSeatId.isNotEmpty) {
        await supabase.from('seats').update({
          'status': 'vacant',
          'occupied_by_member_id': null,
        }).eq('id', oldSeatId);
      }

      await supabase.from('seats').update({
        'status': 'occupied',
        'occupied_by_member_id': memberId,
      }).eq('id', newSeatId);

      await supabase.from('seat_change_requests').update({
        'status': 'approved',
        'approved_at': DateTime.now().toIso8601String(),
      }).eq('id', requestId);

      await _logAudit(
        title: 'Seat Change Approved',
        details: 'Approved seat change for member $memberId to $newSeatLabel.',
        category: 'members',
      );
      await _notifyMember(
        memberId: memberId,
        title: 'Seat change approved',
        message: 'Your seat change request was approved. New seat: $newSeatLabel.',
        type: 'seat_change',
      );

      await _fetchRequests();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seat change approved. Assigned $newSeatLabel.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seat change approval failed: $e')),
      );
    }
  }

  // ── Out-of-shift Check-in Approvals (2026-06-22) ─────────────────────────
  Future<void> _approveCheckinApproval(Map<String, dynamic> r) async {
    final requestId = r['id']?.toString();
    final memberId =
        r['member_id']?['id']?.toString() ?? r['member_id']?.toString();
    if (requestId == null || memberId == null) return;
    try {
      setState(() => _isLoading = true);
      // Approved rows are usable for 30 minutes — the member must re-scan within
      // that window. Stored as a real UTC instant.
      final expires = DateTime.now().toUtc().add(const Duration(minutes: 30));
      await supabase.from('checkin_approvals').update({
        'status': 'approved',
        'decided_by': supabase.auth.currentUser?.id,
        'decided_at': DateTime.now().toUtc().toIso8601String(),
        'approval_expires_at': expires.toIso8601String(),
      }).eq('id', requestId);

      await _notifyMember(
        memberId: memberId,
        title: 'Check-in approved',
        message: 'The admin approved your out-of-shift check-in. Scan the QR again '
            'within 30 minutes to check in — this session will count as overtime.',
        type: 'checkin_approved',
      );
      await _logAudit(
        title: 'Check-in approval granted',
        details: 'Approved out-of-shift check-in for member $memberId.',
        category: AuditLogger.categoryMembers,
      );
      await _fetchRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check-in approved. The member can scan again now.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not approve: ${friendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _rejectCheckinApproval(Map<String, dynamic> r) async {
    final requestId = r['id']?.toString();
    final memberId =
        r['member_id']?['id']?.toString() ?? r['member_id']?.toString();
    if (requestId == null || memberId == null) return;

    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reject Check-in', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reject this out-of-shift check-in? The member will be told to contact you.',
                style: GoogleFonts.inter(fontSize: 13, color: context.palette.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Reason (optional)', hintText: 'e.g. Come during your shift hours'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final reason = reasonController.text.trim();
    try {
      setState(() => _isLoading = true);
      await supabase.from('checkin_approvals').update({
        'status': 'rejected',
        'decided_by': supabase.auth.currentUser?.id,
        'decided_at': DateTime.now().toUtc().toIso8601String(),
        'note': reason.isNotEmpty ? reason : null,
      }).eq('id', requestId);

      await _notifyMember(
        memberId: memberId,
        title: 'Check-in not approved',
        message: reason.isNotEmpty
            ? 'Your out-of-shift check-in was not approved. Reason: $reason. Please contact the admin.'
            : 'Your out-of-shift check-in was not approved. Please contact the admin.',
        type: 'checkin_rejected',
      );
      await _logAudit(
        title: 'Check-in approval rejected',
        details: 'Rejected out-of-shift check-in for member $memberId.${reason.isNotEmpty ? ' Reason: $reason' : ''}',
        category: AuditLogger.categoryMembers,
      );
      await _fetchRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not reject: ${friendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildCheckinApprovalCard(Map<String, dynamic> r) {
    final member = r['member_id'];
    final String name = (member is Map ? member['full_name'] : null)?.toString() ?? 'Member';
    final String photo = (member is Map ? member['photo_url'] : null)?.toString() ?? '';
    final String shiftName = r['shifts']?['name']?.toString() ?? 'their shift';
    final String? attemptedRaw = r['attempted_at']?.toString();
    final String attemptedStr = attemptedRaw != null
        ? formatTimeIST(parseDBTimeToUtc(attemptedRaw))
        : '—';
    final String shiftStart = r['shifts']?['start_time']?.toString() ?? '';
    final String shiftEnd = r['shifts']?['end_time']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFFFF7F0),
                backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                child: photo.isEmpty ? const Icon(Icons.person, color: Color(0xFFE65C00)) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
                    const SizedBox(height: 2),
                    Text('Wants to check in at $attemptedStr (outside shift)',
                        style: GoogleFonts.inter(fontSize: 11.5, color: context.palette.textMuted)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('OVERTIME',
                    style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.bold, color: const Color(0xFFE11D48))),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              const Icon(Icons.wb_sunny_outlined, size: 14, color: Color(0xFFD97706)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  shiftStart.isNotEmpty && shiftEnd.isNotEmpty
                      ? '$shiftName · ${formatShiftTimeString(shiftStart)} – ${formatShiftTimeString(shiftEnd)}'
                      : shiftName,
                  style: GoogleFonts.inter(fontSize: 13, color: context.palette.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Approving lets this member check in now; the time counts as overtime.',
            style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _rejectCheckinApproval(r),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    foregroundColor: context.palette.textMuted,
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isProfileComplete
                      ? () => _approveCheckinApproval(r)
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Complete your profile first to approve requests', style: GoogleFonts.inter()),
                              backgroundColor: const Color(0xFFE65C00),
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isProfileComplete ? const Color(0xFFE65C00) : const Color(0xFFE65C00).withValues(alpha: 0.5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Approve handler: a RENEWAL extends the member's existing membership (keeps
  /// the same seat, no false "duplicate" prompt); a fresh join goes through the
  /// seat picker.
  Future<void> _onApprovePressed(Map<String, dynamic> request) async {
    if (request['is_renewal'] == true) {
      await _approveRenewalRequest(request);
    } else {
      await _showSeatPickerBottomSheet(request);
    }
  }

  /// Approve a renewal: extend the member's current membership end_date (from
  /// the later of current-end / today), keep their seat, record the payment,
  /// notify + audit. Falls back to the join flow if no membership is found.
  Future<void> _approveRenewalRequest(Map<String, dynamic> request) async {
    if (_isApproving) return;
    final member = request['member_id'];
    final String memberId =
        member is Map ? (member['id']?.toString() ?? '') : (member?.toString() ?? '');
    final String memberName =
        member is Map ? (member['full_name']?.toString() ?? 'Member') : 'Member';
    if (memberId.isEmpty) return;

    Map<String, dynamic>? existing;
    try {
      existing = await supabase
          .from('memberships')
          .select('id, end_date, seat_id, seats(seat_label)')
          .eq('member_id', memberId)
          .eq('library_id', widget.libraryId)
          .inFilter('status', ['active', 'trial', 'hold', 'expiring', 'expired'])
          .order('end_date', ascending: false)
          .limit(1)
          .maybeSingle();
    } catch (e) {
      debugPrint('renewal lookup failed: $e');
    }
    if (!mounted) return;
    if (existing == null) {
      // No membership to extend — treat as a normal join.
      await _showSeatPickerBottomSheet(request);
      return;
    }

    final planType = (request['plan_type'] ?? 'monthly').toString();
    int durationMonths = 1;
    if (planType == '3_month') durationMonths = 3;
    if (planType == '6_month') durationMonths = 6;

    DateTime base = DateTime.now();
    final curEnd = DateTime.tryParse(existing['end_date']?.toString() ?? '');
    if (curEnd != null && curEnd.isAfter(base)) base = curEnd;
    final newEnd = _addMonths(base, durationMonths);
    final seatLabel = (existing['seats']?['seat_label'] ?? 'their seat').toString();
    final membershipId = existing['id'];

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Approve renewal?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          'Extend $memberName\'s membership to ${DateFormat('dd MMM yyyy').format(newEnd)} '
          '(${_planLabel(planType)}). Seat $seatLabel stays the same.',
          style: GoogleFonts.inter(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(c, true),
            child: Text('Approve renewal', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    _isApproving = true;
    setState(() => _isLoading = true);
    try {
      final amount = await _computeApprovalAmount(
        shiftId: request['shift_id']?.toString(),
        planType: planType,
        discount: (request['discount_amount'] as int?) ?? 0,
      );

      await supabase.from('memberships').update({
        'end_date': newEnd.toIso8601String().substring(0, 10),
        'status': 'active',
        'plan_type': planType,
      }).eq('id', membershipId);

      await supabase.from('join_requests').update({'status': 'approved'}).eq('id', request['id']);

      await supabase.from('payments').insert({
        'membership_id': membershipId,
        'member_id': memberId,
        'library_id': widget.libraryId,
        'amount': amount,
        'method': request['payment_method'] ?? 'cash',
        'status': 'confirmed',
        'payment_date': DateTime.now().toIso8601String(),
        'confirmed_by_admin_id': supabase.auth.currentUser?.id,
        'proof_url': request['payment_proof_url'],
        'upi_sender_name': request['upi_sender_name'],
      });

      await _notifyMember(
        memberId: memberId,
        title: 'Membership renewed',
        message:
            'Your renewal is confirmed. New expiry: ${DateFormat('dd MMM yyyy').format(newEnd)}. Payment of ₹$amount recorded.',
        type: 'join_approved',
      );
      await _logAudit(
        action: 'membership_renew',
        category: AuditLogger.categoryMembers,
        title: 'Renewed membership',
        details: '$memberName · ${_planLabel(planType)} · ₹$amount',
      );

      _fetchRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$memberName renewed — new expiry ${DateFormat('dd MMM yyyy').format(newEnd)}.'),
          backgroundColor: const Color(0xFF22C55E),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      _isApproving = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showSeatPickerBottomSheet(Map<String, dynamic> request) async {
    setState(() => _isLoading = true);
    final String shiftId = request['shift_id'];

    try {
      final member = request['member_id'];
      final String memberId = member is Map ? member['id']?.toString() ?? '' : member?.toString() ?? '';

      if (memberId.isNotEmpty) {
        // Check if this member already has an active or trial membership in this library
        final existing = await supabase
            .from('memberships')
            .select('id')
            .eq('member_id', memberId)
            .eq('library_id', widget.libraryId)
            .inFilter('status', ['active', 'trial'])
            .limit(1)
            .maybeSingle();
        if (!mounted) return;

        if (existing != null) {
          setState(() => _isLoading = false);
          if (!mounted) return;
          
          final bool confirmReject = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                  const SizedBox(width: 8),
                  Text('Duplicate Membership', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                ],
              ),
              content: const Text(
                'This member already has an active membership in this library. '
                'Do you want to reject this request to prevent duplicate memberships?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.pop(c, true),
                  child: Text('Yes, Reject', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ) ?? false;
          if (!mounted) return;

          if (confirmReject) {
            setState(() => _isLoading = true);
            await supabase.from('join_requests').update({
              'status': 'rejected',
            }).eq('id', request['id']);
            _fetchRequests();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Join request rejected successfully ✓')),
              );
            }
          }
          if (mounted) {
            setState(() => _isLoading = false);
          }
          return;
        }
      }

      // Fetch vacant seats for this shift
      final vacantSeats = await supabase
          .from('seats')
          .select('*')
          .eq('library_id', widget.libraryId)
          .eq('shift_id', shiftId)
          .eq('status', 'vacant')
          .order('seat_label');
      if (!mounted) return;

      setState(() => _isLoading = false);

      if (!mounted) return;

      if (vacantSeats.isEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('No Seats Vacant', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            content: Text('There are no vacant seats available in this shift. Please vacate or add seats on Layout sub-tab first.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
        return;
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.palette.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setPickerState) {
              return Container(
                padding: const EdgeInsets.all(16),
                height: MediaQuery.of(context).size.height * 0.7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    Text(
                      'Select a Seat — ${request['shifts']?['name'] ?? 'Shift'}',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    Text('Tap a vacant seat to assign membership.', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500])),
                    const SizedBox(height: 16),

                    Expanded(
                      child: GridView.builder(
                        itemCount: vacantSeats.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 52 / 44,
                        ),
                        itemBuilder: (context, index) {
                          final seat = vacantSeats[index];
                          return InkWell(
                            onTap: () async {
                              // Confirm + optional discount + start/joining date.
                              final result =
                                  await _confirmAssignmentDialog(request, seat);
                              if (result == null) return;
                              if (!ctx.mounted) return;
                              _approveJoinRequestTransaction(
                                ctx, request, seat,
                                discount: result['discount'] as int?,
                                discountReason: result['reason'] as String?,
                                startDate: result['startDate'] as DateTime?,
                              );
                            },
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                seat['seat_label'],
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 11),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Render Helpers ────────────────────────────────────────────────────────
  Widget _buildTabToggle(int index, String label, IconData icon) {
    final bool isActive = _activeRequestTab == index;
    final int count = index == 0
        ? _joinRequests.length
        : index == 1
            ? _seatChangeRequests.length
            : index == 2
                ? _holdRequests.length
                : _checkinApprovals.length;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeRequestTab = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFE65C00) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isActive ? Colors.transparent : const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isActive ? Colors.white : context.palette.textMuted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                    color: isActive ? Colors.white : context.palette.textMuted,
                  ),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.white : const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: isActive ? const Color(0xFFE65C00) : Colors.white,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Past (dead) join requests — rejected + withdrawn — shown in a sheet.
  Future<void> _showPastRequests() async {
    List<Map<String, dynamic>> past = [];
    try {
      final res = await supabase
          .from('join_requests')
          .select('*, member_id(full_name), shifts(name)')
          .eq('library_id', widget.libraryId)
          .inFilter('status', ['rejected', 'withdrawn'])
          .order('created_at', ascending: false)
          .limit(100);
      past = List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('past requests load failed: $e');
    }
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.7, maxChildSize: 0.95, minChildSize: 0.4, expand: false,
        builder: (sheetCtx, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Text('Past requests', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('Rejected & withdrawn', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
            const SizedBox(height: 12),
            Expanded(
              child: past.isEmpty
                  ? Center(child: Text('No past requests.', style: GoogleFonts.inter(color: const Color(0xFF94A3B8))))
                  : ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: past.length,
                      separatorBuilder: (_, i) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        final r = past[i];
                        final nm = (r['member_id']?['full_name'] ?? 'Member').toString();
                        final st = (r['status'] ?? '').toString();
                        final withdrawn = st == 'withdrawn';
                        final reason = (r['rejection_reason'] ?? '').toString().trim();
                        final created = r['created_at']?.toString() ?? '';
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(nm, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold))),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: withdrawn ? const Color(0xFFE2E8F0) : const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(withdrawn ? 'WITHDRAWN' : 'REJECTED',
                                        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold,
                                            color: withdrawn ? context.palette.textSecondary : const Color(0xFFB91C1C))),
                                  ),
                                ],
                              ),
                              if (created.length >= 10) ...[
                                const SizedBox(height: 2),
                                Text(created.substring(0, 10), style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
                              ],
                              if (!withdrawn && reason.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text('Reason: $reason', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF991B1B), fontStyle: FontStyle.italic)),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Small pill on a join-request card: Renewal / Existing(offline) / New.
  Widget _memberTypePill({required bool isRenewal, required bool isExisting}) {
    late final String label;
    late final Color bg, border, fg;
    if (isRenewal) {
      label = 'RENEWAL';
      bg = const Color(0xFFEFF6FF); border = const Color(0xFFBFDBFE); fg = const Color(0xFF2563EB);
    } else if (isExisting) {
      label = 'EXISTING';
      bg = const Color(0xFFFEF3C7); border = const Color(0xFFFDE68A); fg = const Color(0xFFB45309);
    } else {
      label = 'NEW';
      bg = const Color(0xFFDCFCE7); border = const Color(0xFFBBF7D0); fg = const Color(0xFF15803D);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: border),
      ),
      child: Text(label,
          style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Widget _reviewRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: Text(label, style: GoogleFonts.inter(fontSize: 12, color: context.palette.textMuted)),
          ),
          Expanded(
            child: Text(value.trim().isEmpty ? '—' : value,
                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.palette.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _docThumb(String url, String label) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => showDialog(
            context: context,
            builder: (c) => Dialog(
              child: InteractiveViewer(
                child: Image.network(url, fit: BoxFit.contain, cacheWidth: 1080,
                    errorBuilder: (ctx, err, stack) => const SizedBox(height: 200, child: Center(child: Text('Could not load image')))),
              ),
            ),
          ),
          child: Container(
            width: 100, height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              image: DecorationImage(image: ResizeImage(NetworkImage(url), width: 300), fit: BoxFit.cover),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: context.palette.textMuted)),
      ],
    );
  }

  /// Full applicant review sheet (tap a join-request card). Shows personal
  /// details, ID docs, the application (plan/shift/joining date/payment proof),
  /// returning-member history, and Approve/Reject actions.
  Future<void> _showApplicantReview(Map<String, dynamic> request) async {
    final member = request['member_id'];
    final memberId = member is Map ? member['id']?.toString() : null;
    if (memberId == null) return;

    Map<String, dynamic> p = {};
    int pastCount = 0;
    try {
      final prof = await supabase.from('users').select().eq('id', memberId).maybeSingle();
      if (prof != null) p = Map<String, dynamic>.from(prof);
      final past = await supabase
          .from('memberships')
          .select('id')
          .eq('member_id', memberId)
          .eq('library_id', widget.libraryId);
      pastCount = (past as List).length;
    } catch (e) {
      debugPrint('applicant review load failed: $e');
    }
    if (!mounted) return;

    final String name = (p['full_name'] ?? member['full_name'] ?? 'Member').toString();
    final String photo = (p['photo_url'] ?? '').toString();
    final bool isRenewal = request['is_renewal'] == true;
    final existingJoin = request['existing_member_join_date']?.toString();
    final bool isExisting = existingJoin != null;
    final String front = (p['id_proof_url'] ?? '').toString();
    final String back = (p['id_proof_2_url'] ?? '').toString();
    final String proof = (request['payment_proof_url'] ?? '').toString();
    final String planType = request['plan_type'] == 'monthly'
        ? '1 Month'
        : (request['plan_type'] == '3_month' ? '3 Months' : (request['plan_type'] == '6_month' ? '6 Months' : 'Trial'));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.8, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
        builder: (sheetCtx, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              Row(
                children: [
                  CircleAvatar(radius: 26, backgroundColor: const Color(0xFFFFF7F0),
                      backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                      child: photo.isEmpty ? const Icon(Icons.person, color: Color(0xFFE65C00)) : null),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        _memberTypePill(isRenewal: isRenewal, isExisting: isExisting),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Personal details', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
              _reviewRow(Icons.phone, 'Phone', (p['phone'] ?? member['phone'] ?? '').toString()),
              _reviewRow(Icons.email_outlined, 'Email', (p['email'] ?? '').toString()),
              _reviewRow(Icons.wc, 'Gender', (p['gender'] ?? '').toString()),
              _reviewRow(Icons.cake_outlined, 'Date of birth', (p['date_of_birth'] ?? '').toString()),
              _reviewRow(Icons.home_outlined, 'Address', (p['address'] ?? '').toString()),
              const SizedBox(height: 14),
              Text('ID documents', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
              const SizedBox(height: 8),
              if (front.isEmpty && back.isEmpty)
                Text('No ID documents uploaded.', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)))
              else
                Row(children: [
                  if (front.isNotEmpty) _docThumb(front, 'Front'),
                  if (front.isNotEmpty) const SizedBox(width: 12),
                  if (back.isNotEmpty) _docThumb(back, 'Back'),
                ]),
              const SizedBox(height: 14),
              Text('Application', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
              _reviewRow(Icons.receipt_long_outlined, 'Plan', planType),
              _reviewRow(Icons.wb_sunny_outlined, 'Shift', (request['shifts']?['name'] ?? '').toString()),
              if (isExisting) _reviewRow(Icons.event_available, 'Joining date', existingJoin),
              _reviewRow(Icons.payment_outlined, 'Payment', (request['payment_method'] ?? 'cash').toString().toUpperCase()),
              if ((request['upi_sender_name'] ?? '').toString().isNotEmpty)
                _reviewRow(Icons.person_outline, 'UPI sender', request['upi_sender_name'].toString()),
              if (proof.isNotEmpty) ...[
                const SizedBox(height: 8),
                _docThumb(proof, 'Payment proof'),
              ],
              const SizedBox(height: 14),
              _reviewRow(Icons.history, 'History', pastCount > 0
                  ? '$pastCount previous membership${pastCount == 1 ? '' : 's'} at this library'
                  : 'First time at this library'),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () { Navigator.pop(sheetCtx); _rejectJoinRequest(request); },
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                      child: const Text('Reject', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () { Navigator.pop(sheetCtx); _onApprovePressed(request); },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00)),
                      child: const Text('Approve', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJoinRequestCard(Map<String, dynamic> request) {
    final String reqId = request['id'];
    final member = request['member_id'];
    if (member == null) return const SizedBox.shrink();

    final String name = member['full_name'] ?? 'No Name';
    final String photo = member['photo_url'] ?? '';
    final bool isRenewal = request['is_renewal'] == true;
    final bool isExistingMember = request['existing_member_join_date'] != null;
    final String shiftName = request['shifts']?['name'] ?? 'Shift';
    final String planType = request['plan_type'] == 'monthly'
        ? '1 Month Plan'
        : (request['plan_type'] == '3_month' ? '3 Month Plan' : '6 Month Plan');
    final String payMethod = request['payment_method'] ?? 'cash';
    final String upiProof = request['payment_proof_url'] ?? '';
    final String upiSender = request['upi_sender_name'] ?? '';

    // Payment proof confirmation status (persisted on the request now).
    final bool isUpi = payMethod.toLowerCase() == 'upi';
    final String paymentStatus = (request['payment_status'] ?? 'unverified').toString();
    final bool isPaymentConfirmed = !isUpi ||
        paymentStatus == 'verified' ||
        _confirmedPaymentsInUi.contains(reqId);

    // Calculate aging in days
    final DateTime createdAt = DateTime.parse(request['created_at']);
    final int agingDays = DateTime.now().difference(createdAt).inDays;
    final bool isAging = agingDays >= 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.01), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row — tap to open the full applicant review.
          InkWell(
            onTap: () => _showApplicantReview(request),
            borderRadius: BorderRadius.circular(10),
            child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFFFF7F0),
                backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                child: photo.isEmpty ? const Icon(Icons.person, color: Color(0xFFE65C00)) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
                        ),
                        const SizedBox(width: 8),
                        _memberTypePill(isRenewal: isRenewal, isExisting: isExistingMember),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('Requested on ${createdAt.toString().substring(0, 16)}', style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Color(0xFF94A3B8)),
            ],
            ),
          ),
          const Divider(height: 20),

          // Shift & Plan Details
          Row(
            children: [
              const Icon(Icons.wb_sunny_outlined, size: 14, color: Color(0xFFD97706)),
              const SizedBox(width: 6),
              Text(shiftName, style: GoogleFonts.inter(fontSize: 13, color: context.palette.textSecondary)),
              const SizedBox(width: 16),
              const Icon(Icons.receipt_long_outlined, size: 14, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              Text(planType, style: GoogleFonts.inter(fontSize: 13, color: context.palette.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),

          // Payment mode details
          Row(
            children: [
              const Icon(Icons.payment_outlined, size: 14, color: Colors.blue),
              const SizedBox(width: 6),
              Text('Mode: ${payMethod.toUpperCase()}', style: GoogleFonts.inter(fontSize: 13, color: context.palette.textSecondary, fontWeight: FontWeight.bold)),
            ],
          ),

          // Aging Warning label (Submitted 3 days ago - warning day 5+)
          if (isAging) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.amber),
                const SizedBox(width: 6),
                Text(
                  '⚠ Aging — Submitted $agingDays days ago',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.amber[700], fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],

          // UPI Payment Proof Block
          if (isUpi && upiProof.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  // Screenshot preview box
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (c) => Dialog(
                          child: Container(
                            height: 400,
                            decoration: BoxDecoration(
                              image: DecorationImage(image: ResizeImage(NetworkImage(upiProof), width: 1080), fit: BoxFit.contain),
                            ),
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                        image: DecorationImage(image: ResizeImage(NetworkImage(upiProof), width: 150), fit: BoxFit.cover),
                      ),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.2),
                        child: const Icon(Icons.zoom_in, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sender: $upiSender', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF334155))),
                        const SizedBox(height: 4),
                        Text(
                          () {
                            final amt = _requestAmounts[reqId];
                            final hasAddons = (request['selected_addon_ids'] is List) &&
                                (request['selected_addon_ids'] as List).isNotEmpty;
                            if (amt == null) return 'Amount: as per plan';
                            return hasAddons ? 'Amount: ₹$amt + add-ons' : 'Amount: ₹$amt';
                          }(),
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Payment Confirm Buttons (UPI verification steps)
          if (isUpi && !isPaymentConfirmed) ...[
            if (paymentStatus == 'rejected') ...[
              Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFFD97706)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Payment was marked unverified — awaiting the member to re-pay.',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFB45309), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _confirmPayment(reqId),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), elevation: 0),
                    child: Text('Confirm Pay', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _rejectPayment(request),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                    child: Text('Reject Pay', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // Approval & Rejection buttons (Approve is grayed-out until Payment is Confirmed)
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: !_isProfileComplete
                      ? () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Complete your profile first to approve requests', style: GoogleFonts.inter()),
                              backgroundColor: const Color(0xFFE65C00),
                            ),
                          );
                        }
                      : (isPaymentConfirmed ? () => _onApprovePressed(request) : null),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isProfileComplete
                        ? (isPaymentConfirmed ? const Color(0xFFE65C00) : Colors.grey[200])
                        : const Color(0xFFE65C00).withValues(alpha: 0.5),
                    disabledBackgroundColor: Colors.grey[200],
                    elevation: 0,
                  ),
                  child: Text(
                    'Approve',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _isProfileComplete
                          ? (isPaymentConfirmed ? Colors.white : Colors.grey[400])
                          : Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _rejectJoinRequest(request),
                  child: Text('Reject', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: context.palette.textMuted)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerLoader() {
    return Shimmer(
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 3,
        itemBuilder: (context, index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SkeletonBox(
                      width: 40,
                      height: 40,
                      borderRadius: BorderRadius.all(Radius.circular(20)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          SkeletonBox(width: 120, height: 16),
                          SizedBox(height: 6),
                          SkeletonBox(width: 180, height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const SkeletonBox(width: double.infinity, height: 1),
                const SizedBox(height: 16),
                Row(
                  children: const [
                    SkeletonBox(width: 80, height: 14),
                    SizedBox(width: 16),
                    SkeletonBox(width: 100, height: 14),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SkeletonBox(
                        height: 36,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SkeletonBox(
                        height: 36,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Selector Tab Toggle (S034 layout Join, Seat Changes, Hold toggle)
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _buildTabToggle(0, 'Joins', Icons.person_add_outlined),
              const SizedBox(width: 8),
              _buildTabToggle(1, 'Seats', Icons.swap_horiz_rounded),
              const SizedBox(width: 8),
              _buildTabToggle(2, 'Holds', Icons.pause_circle_outline),
              const SizedBox(width: 8),
              _buildTabToggle(3, 'Check-ins', Icons.login_rounded),
            ],
          ),
        ),

        // 2. Active Tab Screen List Container
        Expanded(
          child: _isLoading
              ? _buildShimmerLoader()
              : RefreshIndicator(
                  onRefresh: _fetchRequests,
                  color: const Color(0xFFE65C00),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: IndexedStack(
                      index: _activeRequestTab,
                      children: [
                        // Toggle 0: Join Requests list (+ Past requests entry)
                        Column(
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _showPastRequests,
                                icon: const Icon(Icons.history, size: 16),
                                label: const Text('Past requests'),
                                style: TextButton.styleFrom(foregroundColor: context.palette.textMuted),
                              ),
                            ),
                            Expanded(
                              child: _joinRequests.isEmpty
                                  ? SingleChildScrollView(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      child: Container(
                                        height: MediaQuery.of(context).size.height * 0.5,
                                        alignment: Alignment.center,
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.assignment_turned_in_outlined, size: 64, color: Colors.grey[300]),
                                            const SizedBox(height: 16),
                                            Text('No pending join requests.', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                                          ],
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      itemCount: _joinRequests.length,
                                      itemBuilder: (ctx, index) => _buildJoinRequestCard(_joinRequests[index]),
                                    ),
                            ),
                          ],
                        ),

                        // Toggle 1: Seat Changes list (Placeholder / simple Empty matching specs)
                        _seatChangeRequests.isEmpty
                            ? SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: Container(
                                  height: MediaQuery.of(context).size.height * 0.5,
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.swap_horiz_rounded, size: 64, color: Colors.grey[300]),
                                      const SizedBox(height: 16),
                                      Text('No pending seat changes.', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: _seatChangeRequests.length,
                                itemBuilder: (ctx, index) {
                                  final r = _seatChangeRequests[index];
                                  return Card(
                                    child: ListTile(
                                      title: Text(r['member_id']?['full_name'] ?? 'Member'),
                                      subtitle: Text('Change from ${r['current_seat']?['seat_label']} to Preferred section: ${r['preferred_section']}'),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TextButton(
                                            onPressed: () => _rejectSeatChangeRequest(r),
                                            style: TextButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              minimumSize: const Size(0, 36),
                                            ),
                                            child: Text('Reject', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted)),
                                          ),
                                          const SizedBox(width: 2),
                                          ElevatedButton(
                                            onPressed: _isProfileComplete ? () => _approveSeatChangeRequest(r) : () {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Complete your profile first to approve requests', style: GoogleFonts.inter()),
                                                  backgroundColor: const Color(0xFFE65C00),
                                                ),
                                              );
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: _isProfileComplete ? const Color(0xFFE65C00) : const Color(0xFFE65C00).withValues(alpha: 0.5),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 12),
                                            ),
                                            child: const Text('Approve'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),

                        // Toggle 2: Holds list
                        _holdRequests.isEmpty
                            ? SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: Container(
                                  height: MediaQuery.of(context).size.height * 0.5,
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.pause_circle_outline, size: 64, color: Colors.grey[300]),
                                      const SizedBox(height: 16),
                                      Text('No pending hold requests.', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: _holdRequests.length,
                                itemBuilder: (ctx, index) {
                                  final r = _holdRequests[index];
                                  return Card(
                                    child: ListTile(
                                      title: Text(r['member_id']?['full_name'] ?? 'Member'),
                                      subtitle: Text('Hold from ${r['start_date']} to ${r['end_date']}'),
                                      trailing: ElevatedButton(
                                        onPressed: _isProfileComplete ? () async {
                                          final holdReq = await supabase
                                              .from('hold_requests')
                                              .select('*, membership_id, start_date, end_date')
                                              .eq('id', r['id'])
                                              .single();
                                          if (!mounted) return;
                                          
                                          final membership = await supabase
                                              .from('memberships')
                                              .select('id, end_date, seat_id, member_id')
                                              .eq('id', holdReq['membership_id'])
                                              .single();
                                          if (!mounted) return;
                                          
                                          final startDate = DateTime.parse(holdReq['start_date']);
                                          final endDate = DateTime.parse(holdReq['end_date']);
                                          final holdDays = endDate.difference(startDate).inDays;
                                          
                                          final currentEnd = DateTime.parse(membership['end_date']);
                                          final newEnd = currentEnd.add(Duration(days: holdDays));
                                          
                                          await supabase.from('memberships').update({
                                            'status': 'hold',
                                            'end_date': newEnd.toIso8601String().substring(0, 10),
                                          }).eq('id', membership['id']);
                                          if (!mounted) return;
                                          
                                          await supabase.from('hold_requests').update({
                                            'status': 'approved'
                                          }).eq('id', r['id']);
                                          if (!mounted) return;
                                          
                                          await supabase.from('notifications').insert({
                                            'user_id': membership['member_id'],
                                            'title': 'Hold approved',
                                            'body': 'Your hold request has been approved. Your membership is paused until ${endDate.toLocal().toString().substring(0, 10)}. Your seat is reserved.',
                                            'data': {'type': 'hold_approved', 'membership_id': membership['id']},
                                          });
                                          if (!mounted) return;
                                          
                                          _fetchRequests();
                                        } : () {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Complete your profile first to approve requests', style: GoogleFonts.inter()),
                                              backgroundColor: const Color(0xFFE65C00),
                                            ),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _isProfileComplete ? const Color(0xFFE65C00) : const Color(0xFFE65C00).withValues(alpha: 0.5),
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Approve'),
                                      ),
                                    ),
                                  );
                                },
                              ),

                        // Toggle 3: Out-of-shift Check-in approvals
                        _checkinApprovals.isEmpty
                            ? SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: Container(
                                  height: MediaQuery.of(context).size.height * 0.5,
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.login_rounded, size: 64, color: Colors.grey[300]),
                                      const SizedBox(height: 16),
                                      Text('No pending check-in approvals.', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: _checkinApprovals.length,
                                itemBuilder: (ctx, index) => _buildCheckinApprovalCard(_checkinApprovals[index]),
                              ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  DateTime _addMonths(DateTime date, int months) {
    final y = date.year + ((date.month - 1 + months) ~/ 12);
    final m = (date.month - 1 + months) % 12 + 1;
    // Cap the day to the target month's last day so e.g. Jan 31 + 1 month
    // becomes Feb 28/29, not an overflowed Mar 3 (Dart would roll over).
    final lastDay = DateTime(y, m + 1, 0).day;
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime(y, m, day);
  }
}
