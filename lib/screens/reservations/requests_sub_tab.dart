import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

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
          final String examCategory = userData['exam_category'] ?? '';
          final String idProofUrl = userData['id_proof_url'] ?? '';

          final bool isComplete = name.isNotEmpty &&
              phone.isNotEmpty &&
              gender.isNotEmpty &&
              dob.isNotEmpty &&
              address.isNotEmpty &&
              examCategory.isNotEmpty &&
              idProofUrl.isNotEmpty;
          
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
  Future<void> _rejectJoinRequest(String requestId) async {
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

    try {
      await supabase.from('join_requests').update({
        'status': 'rejected',
        'rejection_reason': reasonController.text.trim().isNotEmpty ? reasonController.text.trim() : 'Rejected by Admin',
      }).eq('id', requestId);

      _fetchRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join request rejected successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // ── Final Database Seat Assignment and Activation (S034 Flow) ─────────────
  Future<void> _approveJoinRequestTransaction(BuildContext sheetContext, Map<String, dynamic> request, Map<String, dynamic> seat) async {
    try {
      final String seatId = seat['id'];
      final String seatLabel = seat['seat_label'];
      final String memberId = request['member_id']['id'];
      final String requestId = request['id'];
      final String memberName = request['member_id']['full_name'] ?? 'Member';

      // 1. Re-validate vacancy at DB level to prevent race conditions
      final seatCheck = await supabase.from('seats').select('status').eq('id', seatId).single();
      if (seatCheck['status'] != 'vacant') {
        if (!mounted) return;
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

      // 3. Set request status to approved
      await supabase.from('join_requests').update({
        'status': 'approved',
      }).eq('id', requestId);

      // 4. Create membership
      final start = DateTime.now();
      int durationMonths = 1;
      if (request['plan_type'] == '3_month') durationMonths = 3;
      if (request['plan_type'] == '6_month') durationMonths = 6;
      final end = DateTime(start.year, start.month + durationMonths, start.day);

      final membership = await supabase.from('memberships').insert({
        'member_id': memberId,
        'library_id': widget.libraryId,
        'shift_id': request['shift_id'],
        'seat_id': seatId,
        'plan_type': request['plan_type'],
        'start_date': start.toIso8601String().substring(0, 10),
        'end_date': end.toIso8601String().substring(0, 10),
        'status': 'active',
      }).select('id').single();

      // 5. Create confirmed payment record
      await supabase.from('payments').insert({
        'membership_id': membership['id'],
        'member_id': memberId,
        'library_id': widget.libraryId,
        'amount': request['plan_type'] == 'monthly' ? 1500 : (request['plan_type'] == '3_month' ? 4000 : 7500), // generic pricing
        'method': request['payment_method'] ?? 'cash',
        'status': 'confirmed',
        'payment_date': DateTime.now().toIso8601String(),
        'confirmed_by_admin_id': supabase.auth.currentUser?.id,
        'proof_url': request['payment_proof_url'],
        'upi_sender_name': request['upi_sender_name'],
      });

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
        SnackBar(content: Text('Error approving request: $e')),
      );
    }
  }

  // ── Show Seat Picker Modal for Approving (S034 Flow) ──────────────────────
  Future<void> _logAudit({
    required String title,
    required String details,
    required String category,
  }) async {
    final admin = supabase.auth.currentUser;
    try {
      await supabase.from('audit_log').insert({
        'performer_name': admin?.email ?? 'Admin',
        'category': category,
        'action_title': title,
        'action_details': details,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Audit log insert failed: $e');
    }
  }

  Future<void> _notifyMember({
    required String memberId,
    required String title,
    required String message,
  }) async {
    try {
      await supabase.from('notifications').insert({
        'user_id': memberId,
        'title': title,
        'body': message,
        'data': {
          'type': 'seat_change',
        },
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Notification insert failed: $e');
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
                  onPressed: () => _rejectJoinRequest(reqId),
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
                                    trailing: ElevatedButton(
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
                                      ),
                                      child: const Text('Approve'),
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
                                        await supabase.from('hold_requests').update({'status': 'approved'}).eq('id', r['id']);
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
}
