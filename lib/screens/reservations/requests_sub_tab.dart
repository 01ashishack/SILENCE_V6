import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../utils/audit_logger.dart';
import '../../utils/error_messages.dart';

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
  int _activeRequestTab = 0; // 0: Join Requests, 1: Seat Changes, 2: Hold Requests

  // Lists
  List<Map<String, dynamic>> _joinRequests = [];
  List<Map<String, dynamic>> _seatChangeRequests = [];
  List<Map<String, dynamic>> _holdRequests = [];

  // Local state tracking for UPI confirmations (Request ID -> confirmed in UI)
  final Set<String> _confirmedPaymentsInUi = {};

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
        .channel('public:join_requests')
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

      if (mounted) {
        setState(() {
          _joinRequests = List<Map<String, dynamic>>.from(joinRes);
          _seatChangeRequests = List<Map<String, dynamic>>.from(changeRes);
          _holdRequests = List<Map<String, dynamic>>.from(holdRes);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching requests: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Confirm / Reject Payments ─────────────────────────────────────────────
  void _confirmPayment(String requestId) {
    setState(() {
      _confirmedPaymentsInUi.add(requestId);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payment confirmed! Approve button enabled. ✓')),
    );
  }

  Future<void> _rejectPayment(String requestId) async {
    try {
      await supabase.from('join_requests').update({
        'status': 'rejected',
        'rejection_reason': 'Payment verification failed',
      }).eq('id', requestId);

      _fetchRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment rejected and request cancelled.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // ── Reject Join Request ───────────────────────────────────────────────────
  Future<void> _rejectJoinRequest(Map<String, dynamic> request) async {
    final requestId = request['id']?.toString() ?? '';
    final memberId = request['member_id']?['id']?.toString();
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reject Request', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter reason for rejecting this join request:', style: GoogleFonts.inter(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(hintText: 'e.g. Library occupied or invalid documents'),
            ),
          ],
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
  Future<void> _approveJoinRequestTransaction(BuildContext sheetContext, Map<String, dynamic> request, Map<String, dynamic> seat) async {
    if (_isApproving) return; // ignore double-taps
    _isApproving = true;
    try {
      final String seatId = seat['id'];
      final String seatLabel = seat['seat_label'];
      final String memberId = request['member_id']['id'];
      final String requestId = request['id'];
      final String memberName = request['member_id']['full_name'] ?? 'Member';

      // 1. Re-validate vacancy at DB level to prevent race conditions
      final seatCheck = await supabase.from('seats').select('status').eq('id', seatId).single();
      if (!mounted) return;
      if (seatCheck['status'] != 'vacant') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seat just assigned, pick another! ⚠', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red),
        );
        return;
      }

      // 2. Set seat status to occupied
      await supabase.from('seats').update({
        'status': 'occupied',
        'occupied_by_member_id': memberId,
      }).eq('id', seatId);
      if (!mounted) return;

      // 3. Set request status to approved
      await supabase.from('join_requests').update({
        'status': 'approved',
      }).eq('id', requestId);
      if (!mounted) return;

      final String planType = (request['plan_type'] ?? 'monthly').toString();
      int durationMonths = 1;
      if (planType == '3_month') durationMonths = 3;
      if (planType == '6_month') durationMonths = 6;

      // Selected add-ons carried on the request (may be absent on older rows).
      final List<String> addOnIds = (request['selected_addon_ids'] is List)
          ? List<String>.from(
              (request['selected_addon_ids'] as List).map((e) => e.toString()))
          : <String>[];

      // Fetch add-on prices/deposits once (for amount + member_add_ons rows).
      List<Map<String, dynamic>> addOnRows = [];
      if (addOnIds.isNotEmpty) {
        try {
          final res = await supabase
              .from('add_ons')
              .select('id, price, refundable_deposit')
              .inFilter('id', addOnIds);
          addOnRows = List<Map<String, dynamic>>.from(res);
        } catch (e) {
          debugPrint('add_ons price lookup failed: $e');
        }
      }
      final int addOnsTotal = addOnRows.fold<int>(
          0, (sum, a) => sum + ((a['price'] as int?) ?? 0));

      // Real amount = plan price + add-ons − discount. No hardcoded figures.
      final int planAmount = await _computeApprovalAmount(
        shiftId: request['shift_id']?.toString(),
        planType: planType,
        discount: (request['discount_amount'] as int?) ?? 0,
      );
      final int amount = planAmount + addOnsTotal;

      String membershipId;

      // Check if member already has an active/expiring membership in this library
      final existingMembership = await supabase
          .from('memberships')
          .select('id, end_date, seat_id, shift_id, status')
          .eq('member_id', memberId)
          .eq('library_id', widget.libraryId)
          .inFilter('status', ['active', 'trial', 'expiring', 'expired'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (!mounted) return;

      final bool isRenewal = existingMembership != null;

      if (isRenewal) {
        // RENEWAL: Extend existing membership
        DateTime currentEndDate = DateTime.parse(existingMembership['end_date']);
        if (currentEndDate.isBefore(DateTime.now())) {
          currentEndDate = DateTime.now(); // if expired, start from today
        }
        DateTime newEndDate = _addMonths(currentEndDate, durationMonths);

        await supabase.from('memberships').update({
          'end_date': newEndDate.toIso8601String().substring(0, 10),
          'status': 'active',
          'seat_id': seatId,
          'shift_id': request['shift_id'],
        }).eq('id', existingMembership['id']);
        if (!mounted) return;

        membershipId = existingMembership['id'];
      } else {
        // NEW MEMBERSHIP: Create membership
        final start = DateTime.now();
        final end = _addMonths(start, durationMonths);

        final membership = await supabase.from('memberships').insert({
          'member_id': memberId,
          'library_id': widget.libraryId,
          'shift_id': request['shift_id'],
          'seat_id': seatId,
          'plan_type': planType,
          'start_date': start.toIso8601String().substring(0, 10),
          'end_date': end.toIso8601String().substring(0, 10),
          'status': 'active',
        }).select('id').single();
        if (!mounted) return;

        membershipId = membership['id'];
      }

      // 5. Create confirmed payment record (real, derived amount)
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
      if (!mounted) return;

      // 5b. Persist selected add-ons against this membership.
      if (addOnRows.isNotEmpty) {
        try {
          final rows = addOnRows
              .map((a) => {
                    'membership_id': membershipId,
                    'add_on_id': a['id'],
                    'deposit_paid': (a['refundable_deposit'] as int?) ?? 0,
                  })
              .toList();
          await supabase.from('member_add_ons').insert(rows);
        } catch (e) {
          debugPrint('member_add_ons insert failed: $e');
        }
      }
      if (!mounted) return;

      // 6. Notify the member (honest: only after the writes succeed).
      await _notifyMember(
        memberId: memberId,
        title: isRenewal ? 'Membership renewed' : 'Welcome aboard!',
        message: isRenewal
            ? 'Your renewal is confirmed. Seat $seatLabel is assigned. Payment of ₹$amount recorded.'
            : 'Your membership is approved. Seat $seatLabel is assigned. Payment of ₹$amount recorded. You can check in now.',
        type: isRenewal ? 'join_approved' : 'join_approved',
      );

      // 7. Audit trail.
      await _logAudit(
        action: isRenewal ? 'membership_renew' : 'membership_approve',
        category: AuditLogger.categoryMembers,
        title: isRenewal ? 'Renewed membership' : 'Approved join request',
        details:
            '$memberName · ${_planLabel(planType)} · seat $seatLabel · ₹$amount',
      );

      _fetchRequests();
      if (!mounted) return;
      Navigator.pop(sheetContext); // Close seat picker bottom sheet
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Member $memberName approved and seat $seatLabel assigned successfully.",
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
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569))),
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
        backgroundColor: Colors.white,
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
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
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
                              // Show confirmation dialog before final save
                              final confirmAssign = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: Text('Confirm Assignment', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                                  content: Text('Assign seat ${seat['seat_label']} to ${request['member_id']['full_name']}?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00)),
                                      child: const Text('Confirm', style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              ) ?? false;

                              if (confirmAssign) {
                                _approveJoinRequestTransaction(ctx, request, seat);
                              }
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
              Icon(icon, size: 14, color: isActive ? Colors.white : const Color(0xFF64748B)),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                  color: isActive ? Colors.white : const Color(0xFF64748B),
                ),
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
    final String shiftName = request['shifts']?['name'] ?? 'Shift';
    final String planType = request['plan_type'] == 'monthly'
        ? '1 Month Plan'
        : (request['plan_type'] == '3_month' ? '3 Month Plan' : '6 Month Plan');
    final String payMethod = request['payment_method'] ?? 'cash';
    final String upiProof = request['payment_proof_url'] ?? '';
    final String upiSender = request['upi_sender_name'] ?? '';

    // Payment proof confirmation status
    final bool isUpi = payMethod.toLowerCase() == 'upi';
    final bool isPaymentConfirmed = !isUpi || _confirmedPaymentsInUi.contains(reqId);

    // Calculate aging in days
    final DateTime createdAt = DateTime.parse(request['created_at']);
    final int agingDays = DateTime.now().difference(createdAt).inDays;
    final bool isAging = agingDays >= 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row
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
                    Text(name, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                    const SizedBox(height: 2),
                    Text('Requested on ${createdAt.toString().substring(0, 16)}', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF6B7280))),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 20),

          // Shift & Plan Details
          Row(
            children: [
              const Icon(Icons.wb_sunny_outlined, size: 14, color: Color(0xFFD97706)),
              const SizedBox(width: 6),
              Text(shiftName, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569))),
              const SizedBox(width: 16),
              const Icon(Icons.receipt_long_outlined, size: 14, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              Text(planType, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569))),
            ],
          ),
          const SizedBox(height: 8),

          // Payment mode details
          Row(
            children: [
              const Icon(Icons.payment_outlined, size: 14, color: Colors.blue),
              const SizedBox(width: 6),
              Text('Mode: ${payMethod.toUpperCase()}', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569), fontWeight: FontWeight.bold)),
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
                              image: DecorationImage(image: NetworkImage(upiProof), fit: BoxFit.contain),
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
                        image: DecorationImage(image: NetworkImage(upiProof), fit: BoxFit.cover),
                      ),
                      child: Container(
                        color: Colors.black.withOpacity(0.2),
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
                        Text('Amount: ₹1,500', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Payment Confirm Buttons (UPI verification steps)
          if (isUpi && !_confirmedPaymentsInUi.contains(reqId)) ...[
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
                    onPressed: () => _rejectPayment(reqId),
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
                      : (isPaymentConfirmed ? () => _showSeatPickerBottomSheet(request) : null),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isProfileComplete
                        ? (isPaymentConfirmed ? const Color(0xFFE65C00) : Colors.grey[200])
                        : const Color(0xFFE65C00).withOpacity(0.5),
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
                          : Colors.white.withOpacity(0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _rejectJoinRequest(request),
                  child: Text('Reject', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                ),
              ),
            ],
          ),
        ],
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
              _buildTabToggle(0, 'Join Requests', Icons.person_add_outlined),
              const SizedBox(width: 8),
              _buildTabToggle(1, 'Seat Changes', Icons.swap_horiz_rounded),
              const SizedBox(width: 8),
              _buildTabToggle(2, 'Holds', Icons.pause_circle_outline),
            ],
          ),
        ),

        // 2. Active Tab Screen List Container
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: IndexedStack(
                    index: _activeRequestTab,
                    children: [
                      // Toggle 0: Join Requests list
                      _joinRequests.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.assignment_turned_in_outlined, size: 64, color: Colors.grey[300]),
                                  const SizedBox(height: 16),
                                  Text('No pending join requests.', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _joinRequests.length,
                              itemBuilder: (ctx, index) => _buildJoinRequestCard(_joinRequests[index]),
                            ),

                      // Toggle 1: Seat Changes list (Placeholder / simple Empty matching specs)
                      _seatChangeRequests.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.swap_horiz_rounded, size: 64, color: Colors.grey[300]),
                                  const SizedBox(height: 16),
                                  Text('No pending seat changes.', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                                ],
                              ),
                            )
                          : ListView.builder(
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
                                          child: Text('Reject', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
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
                                            backgroundColor: _isProfileComplete ? const Color(0xFFE65C00) : const Color(0xFFE65C00).withOpacity(0.5),
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
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.pause_circle_outline, size: 64, color: Colors.grey[300]),
                                  const SizedBox(height: 16),
                                  Text('No pending hold requests.', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                                ],
                              ),
                            )
                          : ListView.builder(
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
                                        backgroundColor: _isProfileComplete ? const Color(0xFFE65C00) : const Color(0xFFE65C00).withOpacity(0.5),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Approve'),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  DateTime _addMonths(DateTime date, int months) {
    int newYear = date.year;
    int newMonth = date.month + months;
    while (newMonth > 12) {
      newMonth -= 12;
      newYear++;
    }
    return DateTime(newYear, newMonth, date.day);
  }
}
