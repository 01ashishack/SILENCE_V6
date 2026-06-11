import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../utils/audit_logger.dart';
import '../../utils/error_messages.dart';

class LayoutSubTab extends StatefulWidget {
  final String libraryId;
  const LayoutSubTab({super.key, required this.libraryId});

  @override
  State<LayoutSubTab> createState() => LayoutSubTabState();
}

class LayoutSubTabState extends State<LayoutSubTab> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isProfileComplete = true;
  bool _noLibrary = false;

  // Dropdowns Lists
  List<Map<String, dynamic>> _shiftsList = [];
  List<Map<String, dynamic>> _floorsList = [];
  String? _selectedShiftId;
  String? _selectedFloorId;

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

        final libsRes = await supabase.from('libraries').select('id').eq('owner_id', user.id);
        if (mounted) {
          setState(() {
            _noLibrary = libsRes.isEmpty;
          });
        }
      } catch (e) {
        debugPrint('Error in _checkOnboardingStatus: $e');
      }
    }
  }

  // Data collections
  List<Map<String, dynamic>> _sectionsList = [];
  List<Map<String, dynamic>> _seatsList = [];
  List<Map<String, dynamic>> _membershipsList = [];

  // Overview Counts
  int _allFloorsCount = 0;
  int _allSectionsCount = 0;
  int _totalSeatsCount = 0;
  int _availableSeatsCount = 0;

  // Search & Filter state
  final _searchController = TextEditingController();
  String _activeFilter = 'All'; // All, Vacant, Occupied, Hold, Maintenance, Expiring
  bool _showSearchBar = false;
  final Map<String, int> _paginationOffsets = {}; // Section ID (or 'floor' for Case B) -> offset

  // Realtime subscription channels
  RealtimeChannel? _seatsChannel;
  RealtimeChannel? _floorsChannel;
  RealtimeChannel? _sectionsChannel;
  void refresh() {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
      _loadSelectors();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSelectors();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_seatsChannel != null) supabase.removeChannel(_seatsChannel!);
    if (_floorsChannel != null) supabase.removeChannel(_floorsChannel!);
    if (_sectionsChannel != null) supabase.removeChannel(_sectionsChannel!);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LayoutSubTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.libraryId != widget.libraryId) {
      setState(() {
        _isLoading = true;
        _selectedShiftId = null;
        _selectedFloorId = null;
        _shiftsList = [];
        _floorsList = [];
        _seatsList = [];
        _sectionsList = [];
        _membershipsList = [];
        _paginationOffsets.clear();
      });
      _loadSelectors();
    }
  }

  // ── Setup Realtime ────────────────────────────────────────────────────────
  void _setupRealtimeSubscription() {
    _seatsChannel = supabase
        .channel('public:seats')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'seats',
          callback: (payload) {
            if (mounted) {
              _fetchSeatsAndSections();
            }
          },
        )
        .subscribe();

    _floorsChannel = supabase
        .channel('public:floors')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'floors',
          callback: (payload) {
            if (mounted) {
              _loadSelectors();
            }
          },
        )
        .subscribe();

    _sectionsChannel = supabase
        .channel('public:sections')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'sections',
          callback: (payload) {
            if (mounted) {
              _fetchSeatsAndSections();
            }
          },
        )
        .subscribe();
  }

  // ── Fetch Shifts & Floors Selectors ─────────────────────────────────────────
  Future<void> _loadSelectors() async {
    try {
      print('=== LayoutSubTab _loadSelectors START ===');
      await _checkOnboardingStatus();
      print('libraryId passed: ${widget.libraryId}');

      // 1. Fetch non-archived shifts
      final shiftsRes = await supabase
          .from('shifts')
          .select('*')
          .eq('library_id', widget.libraryId)
          .eq('is_archived', false)
          .order('name');
      print('Shifts fetched: ${shiftsRes.length}');
      
      // 2. Fetch Floors
      final floorsRes = await supabase
          .from('floors')
          .select('id, name')
          .eq('library_id', widget.libraryId)
          .order('order_index');
      print('Floors fetched: ${floorsRes.length}');
      for (var f in floorsRes) {
        print(' - Floor ID: ${f['id']}, Name: ${f['name']}');
      }

      if (mounted) {
        setState(() {
          _shiftsList = List<Map<String, dynamic>>.from(shiftsRes);
          _floorsList = List<Map<String, dynamic>>.from(floorsRes);

          _allFloorsCount = _floorsList.length;

          // Check if previous selected IDs are still valid in the new lists, otherwise pick first or null
          final bool hasSelectedShift = _selectedShiftId != null && _shiftsList.any((s) => s['id'] == _selectedShiftId);
          if (!hasSelectedShift) {
            _selectedShiftId = _shiftsList.isNotEmpty ? _shiftsList.first['id'] : null;
          }

          final bool hasSelectedFloor = _selectedFloorId != null && _floorsList.any((f) => f['id'] == _selectedFloorId);
          if (!hasSelectedFloor) {
            _selectedFloorId = _floorsList.isNotEmpty ? _floorsList.first['id'] : null;
          }

          print('Selected Shift: $_selectedShiftId, Selected Floor: $_selectedFloorId');
        });

        if (_selectedShiftId != null && _selectedFloorId != null) {
          _fetchSeatsAndSections();
        } else {
          print('Cannot fetch seats/sections because selected shift or floor is null.');
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      print('Error loading layout selectors: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Fetch Seats, Sections & Memberships ───────────────────────────────────
  Future<void> _fetchSeatsAndSections() async {
    if (_selectedShiftId == null || _selectedFloorId == null) {
      print('Aborting _fetchSeatsAndSections: selected shift or floor is null.');
      return;
    }

    try {
      print('=== LayoutSubTab _fetchSeatsAndSections START ===');
      final floorIds = _floorsList.map((f) => f['id'].toString()).toList();

      // 1. Fetch Sections
      var sectionsQuery = supabase
          .from('sections')
          .select('id, name, tag');
      if (_selectedFloorId == 'all') {
        if (floorIds.isNotEmpty) {
          sectionsQuery = sectionsQuery.inFilter('floor_id', floorIds);
        } else {
          sectionsQuery = sectionsQuery.eq('id', 'non_existent_id');
        }
      } else {
        sectionsQuery = sectionsQuery.eq('floor_id', _selectedFloorId!);
      }
      final sectionsRes = await sectionsQuery;
      print('Sections fetched: ${sectionsRes.length}');

      // 2. Fetch Seats for selected Floor and Shift
      var seatsQuery = supabase
          .from('seats')
          .select('*, occupied_by_member_id(id, full_name, photo_url)')
          .eq('library_id', widget.libraryId);
      
      if (_selectedFloorId != 'all') {
        seatsQuery = seatsQuery.eq('floor_id', _selectedFloorId!);
      }
      if (_selectedShiftId != 'all') {
        seatsQuery = seatsQuery.eq('shift_id', _selectedShiftId!);
      }
      final seatsRes = await seatsQuery;
      print('Seats fetched: ${seatsRes.length}');

      // 3. Fetch active/trial memberships to determine expiry and payment status
      var membershipsQuery = supabase
          .from('memberships')
          .select('*, member_id(full_name)')
          .eq('library_id', widget.libraryId)
          .inFilter('status', ['active', 'trial', 'hold', 'expired']);
      if (_selectedShiftId != 'all') {
        membershipsQuery = membershipsQuery.eq('shift_id', _selectedShiftId!);
      }
      final membershipsRes = await membershipsQuery;
      print('Memberships fetched: ${membershipsRes.length}');

      // 4. Fetch dynamic Overview Metrics for selected Library & Shift
      List<dynamic> allSections = [];
      if (floorIds.isNotEmpty) {
        allSections = await supabase
            .from('sections')
            .select('id')
            .inFilter('floor_id', floorIds);
      }
      print('All sections across all floors count: ${allSections.length}');

      var allShiftSeatsQuery = supabase
          .from('seats')
          .select('id, status')
          .eq('library_id', widget.libraryId);
      if (_selectedShiftId != 'all') {
        allShiftSeatsQuery = allShiftSeatsQuery.eq('shift_id', _selectedShiftId!);
      }
      final allShiftSeats = await allShiftSeatsQuery;
      print('All seats count: ${allShiftSeats.length}');

      if (mounted) {
        setState(() {
          _sectionsList = List<Map<String, dynamic>>.from(sectionsRes);
          _seatsList = List<Map<String, dynamic>>.from(seatsRes);
          _membershipsList = List<Map<String, dynamic>>.from(membershipsRes);

          _allSectionsCount = allSections.length;
          _totalSeatsCount = allShiftSeats.length;
          _availableSeatsCount = allShiftSeats.where((s) => s['status'] == 'vacant').length;

          _isLoading = false;
        });
        print('State set successfully. Sections size: ${_sectionsList.length}, Seats size: ${_seatsList.length}');
      }
    } catch (e) {
      print('Error fetching seats/sections: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Helper to find membership details for a member
  Map<String, dynamic>? _getMemberMembership(String? memberId) {
    if (memberId == null) return null;
    try {
      return _membershipsList.firstWhere(
        (m) => m['member_id'] == memberId,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Seat Expiry & Fee Checks ──────────────────────────────────────────────
  bool _isExpiringSoon(String? memberId) {
    final m = _getMemberMembership(memberId);
    if (m == null) return false;
    final endDateStr = m['end_date'];
    if (endDateStr == null) return false;
    final endDate = DateTime.parse(endDateStr);
    final daysLeft = endDate.difference(DateTime.now()).inDays;
    return daysLeft >= 0 && daysLeft <= 5;
  }

  // ignore: unused_element
  bool _isFeePending(String? memberId) {
    final m = _getMemberMembership(memberId);
    if (m == null) return false;
    return m['status'] == 'expired'; // Simple rule matching specs
  }

  // ── Manual Check In ───────────────────────────────────────────────────────
  Future<void> _manualCheckIn(String memberId, String seatLabel) async {
    try {
      final now = DateTime.now().toIso8601String();
      final membership = _getMemberMembership(memberId);
      final membershipId = membership?['id'];

      if (membershipId == null) {
        throw 'No active membership details found for this member.';
      }

      await supabase.from('attendance').insert({
        'membership_id': membershipId,
        'member_id': memberId,
        'library_id': widget.libraryId,
        'shift_id': _selectedShiftId!,
        'check_in_time': now,
        'session_type': 'manual',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Manually checked in member on Seat $seatLabel ✓', style: GoogleFonts.inter(fontWeight: FontWeight.bold))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error checking in: $e')),
      );
    }
  }

  // ── Seat Action Handlers ─────────────────────────────────────────────────
  /// Release a seat to vacant. If it was occupied, also **unlinks the member's
  /// membership** (`seat_id = null`) so the two never desync, and notifies them.
  Future<void> _releaseSeat(Map<String, dynamic> seat) async {
    final seatId = seat['id'].toString();
    final label = (seat['seat_label'] ?? 'seat').toString();
    final memberId = seat['occupied_by_member_id']?['id']?.toString();
    try {
      await supabase.from('seats').update({
        'status': 'vacant',
        'occupied_by_member_id': null,
      }).eq('id', seatId);

      // Sync the membership so it no longer points at a now-vacant seat.
      if (memberId != null) {
        await supabase
            .from('memberships')
            .update({'seat_id': null})
            .eq('member_id', memberId)
            .eq('library_id', widget.libraryId)
            .eq('seat_id', seatId);

        await _notifySeatMember(
          memberId,
          'Seat released',
          'Your seat ($label) was released by the admin. Please contact the '
              'admin to be assigned a new seat.',
          'seat_change',
        );
        await AuditLogger.instance.log(
          action: 'seat_release',
          category: AuditLogger.categoryMembers,
          title: 'Released seat',
          details: 'Seat $label released to vacant',
          libraryId: widget.libraryId,
        );
      }

      _fetchSeatsAndSections();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(memberId != null
            ? 'Seat $label released. Member notified.'
            : 'Seat $label set to vacant.')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  Future<void> _notifySeatMember(
      String memberId, String title, String message, String type) async {
    try {
      await supabase.from('notifications').insert({
        'user_id': memberId,
        'title': title,
        'body': message,
        'data': {'type': type},
      });
    } catch (e) {
      debugPrint('seat notify failed: $e');
    }
  }

  /// Reassign an occupied seat's member to another **vacant seat in the same
  /// shift**: frees the old seat, occupies the new one, updates the membership's
  /// `seat_id`, notifies the member, and audits. (Was a no-op that just opened
  /// the layout editor.)
  Future<void> _reassignSeat(Map<String, dynamic> seat) async {
    final memberObj = seat['occupied_by_member_id'];
    final memberId = memberObj?['id']?.toString();
    final memberName = (memberObj?['full_name'] ?? 'Member').toString();
    final oldSeatId = seat['id'].toString();
    final oldLabel = (seat['seat_label'] ?? 'seat').toString();
    final shiftId = seat['shift_id']?.toString();

    if (memberId == null) return;

    // Vacant seats in the SAME shift (a member can't move across shifts here).
    final vacant = _seatsList
        .where((s) =>
            s['status'] == 'vacant' &&
            (shiftId == null || s['shift_id']?.toString() == shiftId) &&
            s['id'].toString() != oldSeatId)
        .toList();

    if (vacant.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No vacant seats available in this shift to reassign.')),
      );
      return;
    }

    final chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Reassign $memberName — from seat $oldLabel',
                  style: GoogleFonts.outfit(
                      fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E))),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Pick a vacant seat in the same shift:',
                  style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B))),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: vacant
                    .map((s) => ListTile(
                          leading: const Icon(Icons.event_seat, color: Color(0xFF22C55E)),
                          title: Text('Seat ${s['seat_label']}',
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                          trailing: const Icon(Icons.chevron_right, size: 16),
                          onTap: () => Navigator.pop(ctx, s),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (chosen == null) return;
    final newSeatId = chosen['id'].toString();
    final newLabel = (chosen['seat_label'] ?? 'seat').toString();

    try {
      // Re-validate the target is still vacant (avoid a race).
      final check = await supabase.from('seats').select('status').eq('id', newSeatId).single();
      if (check['status'] != 'vacant') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That seat was just taken. Try another.')),
        );
        return;
      }

      // Free old, occupy new, sync membership.
      await supabase.from('seats').update({
        'status': 'vacant',
        'occupied_by_member_id': null,
      }).eq('id', oldSeatId);
      await supabase.from('seats').update({
        'status': 'occupied',
        'occupied_by_member_id': memberId,
      }).eq('id', newSeatId);
      await supabase
          .from('memberships')
          .update({'seat_id': newSeatId})
          .eq('member_id', memberId)
          .eq('library_id', widget.libraryId)
          .eq('seat_id', oldSeatId);

      await _notifySeatMember(
        memberId,
        'Seat reassigned',
        'Your seat has been changed from $oldLabel to $newLabel by the admin.',
        'seat_reassigned',
      );
      await AuditLogger.instance.log(
        action: 'seat_reassign',
        category: AuditLogger.categoryMembers,
        title: 'Reassigned seat',
        details: '$memberName · $oldLabel → $newLabel',
        libraryId: widget.libraryId,
      );

      _fetchSeatsAndSections();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$memberName moved to seat $newLabel. Member notified.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  Future<void> _markSeatStatus(String seatId, String label, String status) async {
    try {
      await supabase.from('seats').update({
        'status': status,
      }).eq('id', seatId);

      _fetchSeatsAndSections();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seat $label updated to $status ✓')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating status: $e')),
      );
    }
  }

  Future<bool?> _showCustomConfirmDialog({
    required BuildContext context,
    required String title,
    required String content,
    required String confirmLabel,
    required String cancelLabel,
    required IconData icon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: const Color(0xFFE65C00), size: 40),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  content,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF64748B),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(
                          cancelLabel,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(
                          confirmLabel,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteSeat(String seatId, String label) async {
    final confirm = await _showCustomConfirmDialog(
      context: context,
      title: 'Delete Seat',
      content: 'Are you sure you want to delete seat $label permanently?',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      icon: Icons.delete_outline,
    ) ?? false;

    if (!confirm) return;

    try {
      await supabase.from('seats').delete().eq('id', seatId);
      _fetchSeatsAndSections();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seat $label deleted successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting seat: $e')),
      );
    }
  }

  // ── Show Seat Actions Modal (S031-A & S031-B) ────────────────────────────
  void _showSeatActionsBottomSheet(Map<String, dynamic> seat) {
    final bool isOccupied = seat['status'] == 'occupied';
    final member = seat['occupied_by_member_id'];
    final String memberName = member != null ? member['full_name'] ?? 'Unknown' : 'Vacant Seat';
    final membership = _getMemberMembership(member?['id']);
    final String expiryText = membership != null
        ? 'Expires in ${DateTime.parse(membership['end_date']).difference(DateTime.now()).inDays}d'
        : '';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOccupied ? const Color(0xFF3B82F6) : const Color(0xFF22C55E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        seat['seat_label'],
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            memberName,
                            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E)),
                          ),
                          if (isOccupied && expiryText.isNotEmpty)
                            Text(
                              '[Active] • $expiryText',
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF6B7280)),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              if (isOccupied) ...[
                ListTile(
                  leading: const Icon(Icons.person_outline, color: Color(0xFF374151)),
                  title: Text('View Member Details', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                  trailing: const Icon(Icons.chevron_right, size: 16),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (member != null && mounted) {
                      Navigator.pushNamed(context, '/admin/member', arguments: member['id']);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.pause_circle_outline, color: Color(0xFF374151)),
                  title: Text('Mark as Hold', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                  trailing: const Icon(Icons.chevron_right, size: 16),
                  onTap: () {
                    if (mounted) _markSeatStatus(seat['id'], seat['seat_label'], 'hold');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF374151)),
                  title: Text('Reassign Seat', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                  trailing: const Icon(Icons.chevron_right, size: 16),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (mounted) _reassignSeat(seat);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.refresh_rounded, color: Color(0xFF374151)),
                  title: Text('Renew Membership', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                  trailing: const Icon(Icons.chevron_right, size: 16),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (mounted) {
                      Navigator.pushNamed(context, '/admin/library/setup/3').then((_) => _fetchSeatsAndSections());
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.check_circle_outline_rounded, color: Colors.blue),
                  title: Text('Manual Check-In', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.blue)),
                  trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.blue),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (member != null && mounted) {
                      _manualCheckIn(member['id'], seat['seat_label']);
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Remove from Seat', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red)),
                  onTap: () {
                    if (mounted) _releaseSeat(seat);
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.person_add_alt, color: Color(0xFF374151)),
                  title: Text('Assign Member', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                  trailing: const Icon(Icons.chevron_right, size: 16),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please approve pending join requests in the Requests tab to assign members.')),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline_rounded, color: Color(0xFF374151)),
                  title: Text('Reserve Seat', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                  trailing: const Icon(Icons.chevron_right, size: 16),
                  onTap: () {
                    if (mounted) _markSeatStatus(seat['id'], seat['seat_label'], 'hold');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.build_outlined, color: Color(0xFF374151)),
                  title: Text('Mark for Maintenance', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                  trailing: const Icon(Icons.chevron_right, size: 16),
                  onTap: () {
                    if (mounted) _markSeatStatus(seat['id'], seat['seat_label'], 'maintenance');
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Delete Seat', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red)),
                  onTap: () {
                    if (mounted) _deleteSeat(seat['id'], seat['seat_label']);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }




  void showManageLayoutBottomSheet() {
    String resolvedShiftId = _selectedShiftId ?? '';
    if (resolvedShiftId == 'all' || resolvedShiftId.isEmpty) {
      if (_shiftsList.isNotEmpty) {
        resolvedShiftId = _shiftsList.first['id']?.toString() ?? '';
      }
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return ManageLayoutTreeSheet(
          libraryId: widget.libraryId,
          selectedShiftId: resolvedShiftId,
          onRefreshParent: () {
            _loadSelectors();
          },
        );
      },
    );
  }
  // ── Seat Grid Rendering Helper (Used for both Case A & B) ──────────────────
  Widget _buildSeatGrid({required List<Map<String, dynamic>> seats, required String sectionId}) {
    // Pagination (30 seats/page)
    final int totalSeats = seats.length;
    final int offset = _paginationOffsets[sectionId] ?? 0;
    final int end = (offset + 30) > totalSeats ? totalSeats : (offset + 30);
    final List<Map<String, dynamic>> paginatedSeats = seats.sublist(offset, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: paginatedSeats.length + 1, // Add "+ Add Seat" tile at the end
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4, // Exactly 4 circular seats per row on all screens!
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.76, // Generous height to fit circular seat + label below without clipping
          ),
          itemBuilder: (context, index) {
            // Add Seat button
            if (index == paginatedSeats.length) {
              return GestureDetector(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                    builder: (ctx) {
                      return _AddSeatBottomSheet(
                        libraryId: widget.libraryId,
                        floorId: _selectedFloorId!,
                        sectionId: sectionId == 'floor' ? null : sectionId,
                        selectedShiftId: _selectedShiftId!,
                        existingSeats: _seatsList,
                        onComplete: () {
                          _loadSelectors();
                        },
                      );
                    },
                  );
                },
                child: Column(
                  children: [
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: CustomPaint(
                          painter: DashedCirclePainter(
                            color: const Color(0xFFFF9E66),
                            strokeWidth: 1.5,
                            dashCount: 16,
                          ),
                          child: const Center(
                            child: Icon(Icons.add, color: Color(0xFFE65C00), size: 24),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Add Seat',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFE65C00),
                      ),
                    ),
                  ],
                ),
              );
            }

            final seat = paginatedSeats[index];
            final String status = seat['status'];
            final String label = seat['seat_label'];
            final member = seat['occupied_by_member_id'];
            final memberId = member?['id'];
            final String? memberPhoto = member?['photo_url'];

            Color circleColor = const Color(0xFF22C55E); // Vacant (Green)
            Widget innerWidget;
            bool showExpiringBadge = false;

            if (status == 'occupied') {
              final bool showExpiring = _isExpiringSoon(memberId);
              if (showExpiring) {
                circleColor = const Color(0xFFF59E0B); // Expiring (Amber)
                showExpiringBadge = true;
              } else {
                circleColor = const Color(0xFF3B82F6); // Occupied (Blue)
              }

              if (memberPhoto != null && memberPhoto.isNotEmpty) {
                innerWidget = Image.network(
                  memberPhoto,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => const Icon(Icons.person, size: 22, color: Colors.white),
                );
              } else {
                innerWidget = const Icon(Icons.person, size: 22, color: Colors.white);
              }
            } else if (status == 'hold') {
              circleColor = const Color(0xFFF59E0B); // Hold (Amber)
              innerWidget = const Icon(Icons.pause_rounded, size: 22, color: Colors.white);
            } else if (status == 'maintenance') {
              circleColor = const Color(0xFF94A3B8); // Maintenance (Gray)
              innerWidget = const Icon(Icons.build_rounded, size: 22, color: Colors.white);
            } else {
              // Vacant
              circleColor = const Color(0xFF22C55E);
              innerWidget = const Icon(Icons.chair_outlined, size: 22, color: Colors.white);
            }

            final seatCircle = Container(
              decoration: BoxDecoration(
                color: circleColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    // ignore: deprecated_member_use
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: Center(
                  child: innerWidget,
                ),
              ),
            );

            Widget mainContent = seatCircle;

            if (showExpiringBadge) {
              mainContent = Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: seatCircle),
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFFD97706), // Darker amber for contrast
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.access_time_filled_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              );
            }

            return GestureDetector(
              onTap: () => _showSeatActionsBottomSheet(seat),
              child: Column(
                children: [
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: mainContent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        // Pagination controls if more than 30 seats exist in section
        if (totalSeats > 30) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: offset == 0
                    ? null
                    : () {
                        setState(() {
                          _paginationOffsets[sectionId] = offset - 30;
                        });
                      },
                icon: const Icon(Icons.arrow_back_ios_rounded, size: 12),
                label: Text('Prev 30', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
              ),
              Text(
                'Page ${(offset / 30).floor() + 1} of ${(totalSeats / 30).ceil()}',
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF6B7280)),
              ),
              TextButton.icon(
                onPressed: (offset + 30) >= totalSeats
                    ? null
                    : () {
                        setState(() {
                          _paginationOffsets[sectionId] = offset + 30;
                        });
                      },
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 12),
                label: Text('Next 30', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ── Filters & Search Logic ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _getFilteredSeats(List<Map<String, dynamic>> baseSeats) {
    var list = baseSeats;

    // 1. Search Query
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((s) => s['seat_label'].toLowerCase().contains(query)).toList();
    }

    // 2. State Filter
    if (_activeFilter == 'Vacant') {
      list = list.where((s) => s['status'] == 'vacant').toList();
    } else if (_activeFilter == 'Occupied') {
      list = list.where((s) => s['status'] == 'occupied').toList();
    } else if (_activeFilter == 'Hold') {
      list = list.where((s) => s['status'] == 'hold').toList();
    } else if (_activeFilter == 'Maintenance') {
      list = list.where((s) => s['status'] == 'maintenance').toList();
    } else if (_activeFilter == 'Expiring') {
      list = list.where((s) => s['status'] == 'occupied' && _isExpiringSoon(s['occupied_by_member_id']?['id'])).toList();
    }

    return list;
  }

  String _formatTimeHM(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    try {
      final parts = timeStr.split(':');
      if (parts.isNotEmpty) {
        final hour = int.tryParse(parts[0]) ?? 0;
        final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
        final tod = TimeOfDay(hour: hour, minute: minute);
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
        return DateFormat('h:mm a').format(dt); // e.g. "6:00 AM"
      }
    } catch (_) {}
    return timeStr;
  }

  String _getShiftTimingText() {
    if (_selectedShiftId == null) return '';
    if (_selectedShiftId == 'all') return 'All Shifts';
    try {
      final shift = _shiftsList.firstWhere((s) => s['id'] == _selectedShiftId);
      final start = shift['start_time'];
      final end = shift['end_time'];
      if (start != null && end != null) {
        return 'Timings: ${_formatTimeHM(start)} – ${_formatTimeHM(end)}';
      }
    } catch (_) {}
    return '';
  }

  void _showSelectorBottomSheet({
    required String label,
    required String? selectedId,
    required List<dynamic> items,
    required bool isFloor,
    required ValueChanged<String> onChanged,
  }) {
    final displayItems = [
      {'id': 'all', 'name': isFloor ? 'All Floors' : 'All Shifts'},
      ...items,
    ];
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.15),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            constraints: const BoxConstraints(maxWidth: 300, maxHeight: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select ${isFloor ? 'Floor' : 'Shift'}',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: displayItems.map((item) {
                      final String id = item['id'].toString();
                      final bool isSelected = id == selectedId;
                      
                      String subtitleText = '';
                      if (!isFloor && id != 'all') {
                        final start = item['start_time'];
                        final end = item['end_time'];
                        if (start != null && end != null) {
                          subtitleText = 'Timings: ${_formatTimeHM(start)} – ${_formatTimeHM(end)}';
                        }
                      }

                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: Icon(
                          isFloor ? Icons.layers_rounded : Icons.access_time_rounded,
                          color: isSelected ? const Color(0xFFE65C00) : const Color(0xFF94A3B8),
                          size: 16,
                        ),
                        title: Text(
                          item['name'] ?? '',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? const Color(0xFFE65C00) : const Color(0xFF1E293B),
                          ),
                        ),
                        subtitle: subtitleText.isNotEmpty
                            ? Text(
                                subtitleText,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: const Color(0xFF64748B),
                                ),
                              )
                            : null,
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Color(0xFFE65C00), size: 14)
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          onChanged(id);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCustomPopupSelector({
    required String label,
    required String? selectedId,
    required List<dynamic> items,
    required bool isFloor,
    required ValueChanged<String> onChanged,
  }) {
    Map<String, dynamic>? selectedItem;
    for (final item in items) {
      if (item is Map<String, dynamic> &&
          item['id']?.toString() == selectedId) {
        selectedItem = item;
        break;
      }
    }
    final String selectedName = selectedId == 'all'
        ? (isFloor ? 'All Floors' : 'All Shifts')
        : (selectedItem != null ? (selectedItem['name'] ?? '') : 'Select ${isFloor ? 'Floor' : 'Shift'}');

    return GestureDetector(
      onTap: () => _showSelectorBottomSheet(
        label: label,
        selectedId: selectedId,
        items: items,
        isFloor: isFloor,
        onChanged: onChanged,
      ),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isFloor ? Icons.layers_rounded : Icons.access_time_rounded,
              color: const Color(0xFFE65C00),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    selectedName,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF64748B),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))),
      );
    }

    if (_floorsList.isEmpty && _shiftsList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.layers_clear_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No floors configured yet',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 8),
              Text(
                'Use Manage Layout to create your first floor and then configure shifts.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500]),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (_) => ManageLayoutTreeSheet(
                      libraryId: widget.libraryId,
                      selectedShiftId: null,
                      onRefreshParent: () {
                        _loadSelectors();
                      },
                    ),
                  );
                },
                icon: const Icon(Icons.dashboard_customize_outlined, size: 20),
                label: Text(
                  'Manage Layout',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_floorsList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.layers_clear_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No floors configured yet',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 8),
              Text(
                'Use Manage Layout to create your first floor.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500]),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (_) => ManageLayoutTreeSheet(
                      libraryId: widget.libraryId,
                      selectedShiftId: null,
                      onRefreshParent: () {
                        _loadSelectors();
                      },
                    ),
                  );
                },
                icon: const Icon(Icons.dashboard_customize_outlined, size: 20),
                label: Text(
                  'Manage Layout',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_shiftsList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.schedule_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No shifts configured yet',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 8),
              Text(
                'Use Manage Shifts to configure your first shift.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500]),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/admin/settings/shifts'),
                icon: const Icon(Icons.access_time_outlined, size: 20),
                label: Text(
                  'Manage Shifts',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 1. Selector Dropdowns & Buttons Row (Matching layout screen.png Style) ────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  // Floor Selector Dropdown (flex 4)
                  Expanded(
                    flex: 4,
                    child: _buildCustomPopupSelector(
                      label: 'FLOOR',
                      selectedId: _selectedFloorId,
                      items: _floorsList,
                      isFloor: true,
                      onChanged: (val) {
                        setState(() {
                          _selectedFloorId = val;
                          _isLoading = true;
                        });
                        _fetchSeatsAndSections();
                      },
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Shift Selector Dropdown (flex 5)
                  Expanded(
                    flex: 5,
                    child: _buildCustomPopupSelector(
                      label: 'SHIFT',
                      selectedId: _selectedShiftId,
                      items: _shiftsList,
                      isFloor: false,
                      onChanged: (val) {
                        setState(() {
                          _selectedShiftId = val;
                          _isLoading = true;
                        });
                        _fetchSeatsAndSections();
                      },
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Search toggle action button
                  _buildIconActionButton(
                    icon: _showSearchBar ? Icons.close : Icons.search_rounded,
                    onTap: () {
                      setState(() {
                        _showSearchBar = !_showSearchBar;
                        if (!_showSearchBar) {
                          _searchController.clear();
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 6),

                  // Edit Icon (pencil) to open Manage Layout
                  _buildIconActionButton(
                    icon: Icons.edit_outlined,
                    onTap: showManageLayoutBottomSheet,
                  ),
                ],
              ),
              
              // Shift timings printed underneath dropdowns (styled green Color(0xFF22C55E))
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _getShiftTimingText(),
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF22C55E)),
                    ),
                  ),
                  Text(
                    'Active Filter: $_activeFilter',
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── 1b. Dynamically Toggleable Search Bar ──
        if (_showSearchBar)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search seat label...',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                fillColor: const Color(0xFFF8FAFC),
                prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
              onChanged: (val) => setState(() {}),
            ),
          ),

        // ── 1c. Premium Horizontal Filter Chips Row (Horizontally Scrollable) ──
        Container(
          color: Colors.white,
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All', 'All'),
                _buildFilterChip('Vacant', 'Vacant'),
                _buildFilterChip('Occupied', 'Occupied'),
                _buildFilterChip('Expiring', 'Expiring'),
                _buildFilterChip('Hold', 'Hold'),
                _buildFilterChip('Maintenance', 'Maintenance'),
              ],
            ),
          ),
        ),

        // ── 2. Library Layout Overview Stats Section (4 Expanded Sub-Cards, No Wrapper Card, No Scroll) ──
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
          child: Text(
            'Library Layout Overview',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildOverviewStatCard(
                title: 'Floors',
                count: '$_allFloorsCount',
                icon: Icons.layers_outlined,
                bgColor: const Color(0xFFEFF6FF),
                borderColor: const Color(0xFFBFDBFE),
                iconBgColor: const Color(0xFFDBEAFE),
                themeColor: const Color(0xFF1E40AF),
              ),
              const SizedBox(width: 8),
              _buildOverviewStatCard(
                title: 'Sections',
                count: '$_allSectionsCount',
                icon: Icons.grid_view_rounded,
                bgColor: const Color(0xFFF5F3FF),
                borderColor: const Color(0xFFDDD6FE),
                iconBgColor: const Color(0xFFEDE9FE),
                themeColor: const Color(0xFF5B21B6),
              ),
              const SizedBox(width: 8),
              _buildOverviewStatCard(
                title: 'Total Seats',
                count: '$_totalSeatsCount',
                icon: Icons.chair_rounded,
                bgColor: const Color(0xFFECFDF5),
                borderColor: const Color(0xFFA7F3D0),
                iconBgColor: const Color(0xFFD1FAE5),
                themeColor: const Color(0xFF065F46),
              ),
              const SizedBox(width: 8),
              _buildOverviewStatCard(
                title: 'Available',
                count: '$_availableSeatsCount',
                icon: Icons.weekend_rounded,
                bgColor: const Color(0xFFFFF7ED),
                borderColor: const Color(0xFFFFD8BE),
                iconBgColor: const Color(0xFFFFEAD8),
                themeColor: const Color(0xFFC2410C),
              ),
            ],
          ),
        ),

        // ── 3. Scrollable Cards Area (Case A: Sections vs. Case B: Direct Floor) ────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _sectionsList.isNotEmpty
                ? Column(
                    // Case A: Grouped by Sections
                    children: _sectionsList.map((section) {
                      final String sectionId = section['id'];
                      final String sectionName = section['name'];

                      // Find seats belonging to this section on the selected floor
                      final baseSecSeats = _seatsList.where((s) => s['section_id'] == sectionId).toList();
                      final filteredSecSeats = _getFilteredSeats(baseSecSeats);

                      if (filteredSecSeats.isEmpty && _searchController.text.isNotEmpty) {
                        return const SizedBox.shrink();
                      }

                      final int vacantCount = baseSecSeats.where((s) => s['status'] == 'vacant').length;
                      final int occupiedCount = baseSecSeats.where((s) => s['status'] == 'occupied').length;
                      final int expiringCount = baseSecSeats.where((s) => s['status'] == 'occupied' && _isExpiringSoon(s['occupied_by_member_id']?['id'])).length;
                      final int holdCount = baseSecSeats.where((s) => s['status'] == 'hold').length;
                      final int maintCount = baseSecSeats.where((s) => s['status'] == 'maintenance').length;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              sectionName,
                              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 8),
                            
                            // Section Stats badge chips (clickable to filter instantly!)
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildSectionStatusBadge(
                                    color: const Color(0xFF22C55E),
                                    label: 'Vacant',
                                    count: vacantCount,
                                  ),
                                  _buildSectionStatusBadge(
                                    color: const Color(0xFF3B82F6),
                                    label: 'Occupied',
                                    count: occupiedCount,
                                  ),
                                  _buildSectionStatusBadge(
                                    color: const Color(0xFF8B5CF6),
                                    label: 'Expiring',
                                    count: expiringCount,
                                  ),
                                  _buildSectionStatusBadge(
                                    color: const Color(0xFFF97316),
                                    label: 'Hold',
                                    count: holdCount,
                                  ),
                                  _buildSectionStatusBadge(
                                    color: const Color(0xFF94A3B8),
                                    label: 'Maintenance',
                                    count: maintCount,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildSeatGrid(seats: filteredSecSeats, sectionId: sectionId),
                          ],
                        ),
                      );
                    }).toList(),
                  )
                : Container(
                    // Case B: No sections, render floor seats directly in a single card
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'All Floor Seats',
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '👥 Floor seats loaded directly',
                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        
                        // Floor Stats badges row (Clickable)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                               _buildSectionStatusBadge(
                                color: const Color(0xFF22C55E),
                                label: 'Vacant',
                                count: _seatsList.where((s) => s['status'] == 'vacant').length,
                              ),
                              _buildSectionStatusBadge(
                                color: const Color(0xFF3B82F6),
                                label: 'Occupied',
                                count: _seatsList.where((s) => s['status'] == 'occupied').length,
                              ),
                              _buildSectionStatusBadge(
                                color: const Color(0xFF8B5CF6),
                                label: 'Expiring',
                                count: _seatsList.where((s) => s['status'] == 'occupied' && _isExpiringSoon(s['occupied_by_member_id']?['id'])).length,
                              ),
                              _buildSectionStatusBadge(
                                color: const Color(0xFFF97316),
                                label: 'Hold',
                                count: _seatsList.where((s) => s['status'] == 'hold').length,
                              ),
                              _buildSectionStatusBadge(
                                color: const Color(0xFF94A3B8),
                                label: 'Maintenance',
                                count: _seatsList.where((s) => s['status'] == 'maintenance').length,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSeatGrid(seats: _getFilteredSeats(_seatsList), sectionId: 'floor'),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ── Helper builders ──

  Widget _buildIconActionButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFFE65C00), size: 18),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final bool isActive = _activeFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeFilter = value;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE65C00) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? const Color(0xFFE65C00) : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: isActive ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionStatusBadge({
    required Color color,
    required String label,
    required int count,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            '$label $count',
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewStatCard({
    required String title,
    required String count,
    required IconData icon,
    required Color bgColor,
    required Color borderColor,
    required Color iconBgColor,
    required Color themeColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: iconBgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 14,
                color: themeColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              count,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: themeColor,
               ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: themeColor.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dashed Circle Painter for + Add Seat Button ──────────────────────────────
class DashedCirclePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final int dashCount;

  DashedCirclePainter({
    this.color = const Color(0xFFFFD8BE),
    this.strokeWidth = 1.5,
    this.dashCount = 16,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final double radius = size.width / 2;
    final center = Offset(radius, radius);

    final double dashAngle = (2 * 3.1415926535) / dashCount;
    for (int i = 0; i < dashCount; i++) {
      if (i % 2 == 0) {
        final double startAngle = i * dashAngle;
        final double endAngle = (i + 1) * dashAngle;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          endAngle - startAngle,
          false,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedCirclePainter oldDelegate) => false;
}

// ── Modern Bottom Sheet Creators for Floors & Sections ──────────────────────
void showAddFloorBottomSheet({
  required BuildContext context,
  required String libraryId,
  required int floorCount,
  required VoidCallback onCompleted,
}) {
  final controller = TextEditingController();
  final supabase = Supabase.instance.client;
  bool isLoading = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              top: 16,
              left: 24,
              right: 24,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  spreadRadius: 2,
                )
              ]
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Add New Floor',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'Floor Name (e.g. Ground Floor)',
                    labelStyle: GoogleFonts.inter(color: const Color(0xFF64748B)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE65C00), width: 2),
                    ),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final name = controller.text.trim();
                          if (name.isEmpty) return;
                          setState(() => isLoading = true);
                          try {
                            await supabase.from('floors').insert({
                              'library_id': libraryId,
                              'name': name,
                              'order_index': floorCount,
                            });
                            Navigator.pop(ctx);
                            onCompleted();
                          } catch (e) {
                            setState(() => isLoading = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error adding floor: $e')),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          'Add Floor',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ],
            ),
          );
        }
      );
    },
  );
}

void showRenameFloorBottomSheet({
  required BuildContext context,
  required String floorId,
  required String currentName,
  required VoidCallback onCompleted,
}) {
  final controller = TextEditingController(text: currentName);
  final supabase = Supabase.instance.client;
  bool isLoading = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              top: 16,
              left: 24,
              right: 24,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  spreadRadius: 2,
                )
              ]
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
                  'Rename Floor',
                  style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'Floor Name',
                    labelStyle: GoogleFonts.inter(color: const Color(0xFF64748B)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE65C00), width: 2),
                    ),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final name = controller.text.trim();
                          if (name.isEmpty) return;
                          setState(() => isLoading = true);
                          try {
                            await supabase.from('floors').update({'name': name}).eq('id', floorId);
                            Navigator.pop(ctx);
                            onCompleted();
                          } catch (e) {
                            setState(() => isLoading = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error renaming floor: $e')),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                        )
                      : Text('Save Changes', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ],
            ),
          );
        }
      );
    },
  );
}

void showAddSectionBottomSheet({
  required BuildContext context,
  required String floorId,
  required VoidCallback onCompleted,
}) {
  final controller = TextEditingController();
  final supabase = Supabase.instance.client;
  bool isLoading = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              top: 16,
              left: 24,
              right: 24,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  spreadRadius: 2,
                )
              ]
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Add New Section',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'Section Name (e.g. Girls Section)',
                    labelStyle: GoogleFonts.inter(color: const Color(0xFF64748B)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE65C00), width: 2),
                    ),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final name = controller.text.trim();
                          if (name.isEmpty) return;
                          setState(() => isLoading = true);
                          try {
                            await supabase.from('sections').insert({
                              'floor_id': floorId,
                              'name': name,
                            });
                            Navigator.pop(ctx);
                            onCompleted();
                          } catch (e) {
                            setState(() => isLoading = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error adding section: $e')),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          'Add Section',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ],
            ),
          );
        }
      );
    },
  );
}

void showEditSectionBottomSheet({
  required BuildContext context,
  required Map<String, dynamic> section,
  required VoidCallback onCompleted,
}) {
  final controller = TextEditingController(text: section['name']);
  final supabase = Supabase.instance.client;
  bool isLoading = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              top: 16,
              left: 24,
              right: 24,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  spreadRadius: 2,
                )
              ]
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
                  'Edit Section',
                  style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'Section Name',
                    labelStyle: GoogleFonts.inter(color: const Color(0xFF64748B)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE65C00), width: 2),
                    ),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final name = controller.text.trim();
                          if (name.isEmpty) return;
                          setState(() => isLoading = true);
                          try {
                            await supabase.from('sections').update({
                              'name': name,
                            }).eq('id', section['id']);
                            Navigator.pop(ctx);
                            onCompleted();
                          } catch (e) {
                            setState(() => isLoading = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error updating section: $e')),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                        )
                      : Text('Save Changes', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ],
            ),
          );
        }
      );
    },
  );
}

// ── S071 Overhauled Manage Layout Tree Sheet ─────────────────────────────────
class ManageLayoutTreeSheet extends StatefulWidget {
  final String libraryId;
  final String? selectedShiftId;
  final VoidCallback onRefreshParent;

  const ManageLayoutTreeSheet({
    required this.libraryId,
    required this.selectedShiftId,
    required this.onRefreshParent,
  });

  @override
  State<ManageLayoutTreeSheet> createState() => _ManageLayoutTreeSheetState();
}

class _ManageLayoutTreeSheetState extends State<ManageLayoutTreeSheet> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _floors = [];
  List<Map<String, dynamic>> _sections = [];
  List<Map<String, dynamic>> _seats = [];

  // Expanded status for tree view (using Floor and Section IDs)
  final Set<String> _expandedNodeIds = {};

  @override
  void initState() {
    super.initState();
    _fetchTreeData();
  }

  Future<void> _fetchTreeData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final floorsRes = await supabase
          .from('floors')
          .select('*')
          .eq('library_id', widget.libraryId)
          .order('order_index');

      final floorIds = floorsRes.map((f) => f['id']).toList();
      List<dynamic> sectionsRes = [];
      List<dynamic> seatsRes = [];

      if (floorIds.isNotEmpty) {
        sectionsRes = await supabase
            .from('sections')
            .select('*')
            .inFilter('floor_id', floorIds)
            .order('name');

        if (widget.selectedShiftId != null) {
          seatsRes = await supabase
              .from('seats')
              .select('*')
              .inFilter('floor_id', floorIds)
              .eq('shift_id', widget.selectedShiftId!)
              .order('seat_label');
        }
      }

      if (mounted) {
        setState(() {
          _floors = List<Map<String, dynamic>>.from(floorsRes);
          _sections = List<Map<String, dynamic>>.from(sectionsRes);
          _seats = List<Map<String, dynamic>>.from(seatsRes);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tree layout: $e')),
        );
      }
    }
  }

  // ── Action Dialogs ──
  void _showAddFloorDialog() {
    showAddFloorBottomSheet(
      context: context,
      libraryId: widget.libraryId,
      floorCount: _floors.length,
      onCompleted: () {
        _fetchTreeData();
        widget.onRefreshParent();
      },
    );
  }

  void _showRenameFloorDialog(String floorId, String currentName) {
    showRenameFloorBottomSheet(
      context: context,
      floorId: floorId,
      currentName: currentName,
      onCompleted: () {
        _fetchTreeData();
        widget.onRefreshParent();
      },
    );
  }

  void _showAddSectionDialog(String floorId) {
    showAddSectionBottomSheet(
      context: context,
      floorId: floorId,
      onCompleted: () {
        _fetchTreeData();
        widget.onRefreshParent();
      },
    );
  }

  void _showEditSectionDialog(Map<String, dynamic> sec) {
    showEditSectionBottomSheet(
      context: context,
      section: sec,
      onCompleted: () {
        _fetchTreeData();
        widget.onRefreshParent();
      },
    );
  }

  void _showEditSeatDialog(Map<String, dynamic> seat) {
    final controller = TextEditingController(text: seat['seat_label']);
    String status = seat['status'] ?? 'vacant';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('Edit Seat', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: controller, decoration: const InputDecoration(labelText: 'Seat Label')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: ['vacant', 'occupied', 'hold', 'maintenance'].contains(status) ? status : 'vacant',
                decoration: const InputDecoration(labelText: 'Seat Status'),
                items: const [
                  DropdownMenuItem(value: 'vacant', child: Text('Vacant')),
                  DropdownMenuItem(value: 'occupied', child: Text('Occupied')),
                  DropdownMenuItem(value: 'hold', child: Text('Hold')),
                  DropdownMenuItem(value: 'maintenance', child: Text('Under Maintenance')),
                ],
                onChanged: (val) {
                  if (val != null) setDlgState(() => status = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final label = controller.text.trim();
                if (label.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  setState(() => _isLoading = true);
                  await supabase.from('seats').update({
                    'seat_label': label,
                    'status': status,
                  }).eq('id', seat['id']);
                  _fetchTreeData();
                  widget.onRefreshParent();
                } catch (e) {
                  setState(() => _isLoading = false);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating seat: $e')));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showCustomConfirmDialog({
    required BuildContext context,
    required String title,
    required String content,
    required String confirmLabel,
    required String cancelLabel,
    required IconData icon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: const Color(0xFFE65C00), size: 40),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  content,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF64748B),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(
                          cancelLabel,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(
                          confirmLabel,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Cascade Deletions ──
  Future<void> _deleteFloor(String floorId, String name) async {
    final confirm = await _showCustomConfirmDialog(
      context: context,
      title: 'Delete Floor',
      content: 'Delete floor "$name" and all its sections and seats? This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      icon: Icons.delete_outline,
    ) ?? false;

    if (!confirm) return;

    setState(() => _isLoading = true);
    try {
      // Bulletproof App-level cascade deletion
      await supabase.from('seats').delete().eq('floor_id', floorId);
      await supabase.from('sections').delete().eq('floor_id', floorId);
      await supabase.from('floors').delete().eq('id', floorId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Floor "$name" and all its sections/seats deleted successfully! ✓')),
      );

      _fetchTreeData();
      widget.onRefreshParent();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting floor: $e')));
    }
  }

  Future<void> _deleteSection(String sectionId, String name) async {
    final confirm = await _showCustomConfirmDialog(
      context: context,
      title: 'Delete Section',
      content: 'Delete section "$name" and all its seats? This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      icon: Icons.delete_outline,
    ) ?? false;

    if (!confirm) return;

    setState(() => _isLoading = true);
    try {
      await supabase.from('seats').delete().eq('section_id', sectionId);
      await supabase.from('sections').delete().eq('id', sectionId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Section "$name" and all its seats deleted successfully! ✓')),
      );

      _fetchTreeData();
      widget.onRefreshParent();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting section: $e')));
    }
  }

  Future<void> _deleteSeat(String seatId, String label) async {
    final confirm = await _showCustomConfirmDialog(
      context: context,
      title: 'Delete Seat',
      content: 'Delete seat "$label"? This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      icon: Icons.delete_outline,
    ) ?? false;

    if (!confirm) return;

    setState(() => _isLoading = true);
    try {
      await supabase.from('seats').delete().eq('id', seatId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seat "$label" deleted successfully! ✓')),
      );

      _fetchTreeData();
      widget.onRefreshParent();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting seat: $e')));
    }
  }

  void _showAddSeatBottomSheet({required String floorId, required String? sectionId}) {
    if (widget.selectedShiftId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please configure shifts first before adding seats.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return _AddSeatBottomSheet(
          libraryId: widget.libraryId,
          floorId: floorId,
          sectionId: sectionId,
          selectedShiftId: widget.selectedShiftId!,
          existingSeats: _seats,
          onComplete: () {
            _fetchTreeData();
            widget.onRefreshParent();
          },
        );
      },
    );
  }


  Widget _buildStatusBadge(String? status) {
    final cleanStatus = status?.toLowerCase() ?? 'vacant';
    Color bgColor = const Color(0xFFDCFCE7);
    Color textColor = const Color(0xFF15803D);
    String text = 'Vacant';

    if (cleanStatus == 'occupied') {
      bgColor = const Color(0xFFFEE2E2);
      textColor = const Color(0xFFB91C1C);
      text = 'Occupied';
    } else if (cleanStatus == 'hold') {
      bgColor = const Color(0xFFFEF3C7);
      textColor = const Color(0xFFD97706);
      text = 'Hold';
    } else if (cleanStatus == 'maintenance') {
      bgColor = const Color(0xFFF1F5F9);
      textColor = const Color(0xFF475569);
      text = 'Maint.';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.settings_outlined, color: Color(0xFFE65C00)),
                  const SizedBox(width: 8),
                  Text(
                    'Manage Layout',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          const SizedBox(height: 16),

          if (_isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))),
              ),
            )
          else if (_floors.isEmpty)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.layers_clear_outlined, size: 64, color: Colors.grey[350]),
                  const SizedBox(height: 12),
                  Text(
                    'No layout configured yet',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _showAddFloorDialog,
                    icon: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    label: const Text('Add First Floor'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: _floors.length,
                      itemBuilder: (context, idx) {
                        final floor = _floors[idx];
                        final String floorId = floor['id'];
                        final bool isFloorExpanded = _expandedNodeIds.contains(floorId);

                        final floorSections = _sections.where((s) => s['floor_id'] == floorId).toList();
                        final directSeats = _seats.where((s) => s['floor_id'] == floorId && s['section_id'] == null).toList();

                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: Color(0xFFF1F5F9)),
                          ),
                          color: const Color(0xFFF8FAFC),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Floor Title Tile
                              ListTile(
                                leading: const Icon(Icons.apartment_rounded, color: Color(0xFFE65C00)),
                                title: Text(
                                  floor['name'] ?? '',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF64748B)),
                                      onPressed: () => _showRenameFloorDialog(floorId, floor['name'] ?? ''),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_outlined, size: 18, color: Colors.red),
                                      onPressed: () => _deleteFloor(floorId, floor['name'] ?? ''),
                                    ),
                                    Icon(
                                      isFloorExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  setState(() {
                                    if (isFloorExpanded) {
                                      _expandedNodeIds.remove(floorId);
                                    } else {
                                      _expandedNodeIds.add(floorId);
                                    }
                                  });
                                },
                              ),

                              // Expanded floor contents
                              if (isFloorExpanded) ...[
                                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      // Render Sections under Floor
                                      ...floorSections.map((sec) {
                                        final String secId = sec['id'];
                                        final bool isSecExpanded = _expandedNodeIds.contains(secId);
                                        final secSeats = _seats.where((s) => s['section_id'] == secId).toList();

                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: const Color(0xFFF1F5F9)),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              ListTile(
                                                dense: true,
                                                leading: const Icon(Icons.grid_view_rounded, color: Color(0xFFE65C00), size: 18),
                                                title: Text(
                                                  sec['name'] ?? '',
                                                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF334155)),
                                                ),
                                                trailing: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF64748B)),
                                                      onPressed: () => _showEditSectionDialog(sec),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.delete_outline_outlined, size: 16, color: Colors.red),
                                                      onPressed: () => _deleteSection(secId, sec['name'] ?? ''),
                                                    ),
                                                    Icon(
                                                      isSecExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                                                      size: 18,
                                                      color: const Color(0xFF64748B),
                                                    ),
                                                  ],
                                                ),
                                                onTap: () {
                                                  setState(() {
                                                    if (isSecExpanded) {
                                                      _expandedNodeIds.remove(secId);
                                                    } else {
                                                      _expandedNodeIds.add(secId);
                                                    }
                                                  });
                                                },
                                              ),

                                              // Expanded Section seats
                                              if (isSecExpanded) ...[
                                                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                                ...secSeats.map((seat) {
                                                  return Padding(
                                                    padding: const EdgeInsets.only(left: 28, right: 12, top: 4, bottom: 4),
                                                    child: Row(
                                                      children: [
                                                        const Icon(Icons.chair_rounded, size: 14, color: Color(0xFFE65C00)),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          seat['seat_label'] ?? '',
                                                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        _buildStatusBadge(seat['status']),
                                                        const Spacer(),
                                                        IconButton(
                                                          icon: const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF64748B)),
                                                          onPressed: () => _showEditSeatDialog(seat),
                                                          padding: EdgeInsets.zero,
                                                          constraints: const BoxConstraints(),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        IconButton(
                                                          icon: const Icon(Icons.delete_outline_outlined, size: 14, color: Colors.red),
                                                          onPressed: () => _deleteSeat(seat['id'], seat['seat_label'] ?? ''),
                                                          padding: EdgeInsets.zero,
                                                          constraints: const BoxConstraints(),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                }),
                                                Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  child: TextButton.icon(
                                                    onPressed: () => _showAddSeatBottomSheet(floorId: floorId, sectionId: secId),
                                                    icon: const Icon(Icons.add_rounded, size: 14, color: Color(0xFFE65C00)),
                                                    label: Text('Add Seat to Section', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      }),

                                      // Direct Floor Seats (no section)
                                      ...directSeats.map((seat) {
                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 6),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFFF1F5F9)),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.chair_rounded, size: 16, color: Color(0xFFE65C00)),
                                              const SizedBox(width: 8),
                                              Text(
                                                seat['seat_label'] ?? '',
                                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                                              ),
                                              const SizedBox(width: 8),
                                              _buildStatusBadge(seat['status']),
                                              const Spacer(),
                                              IconButton(
                                                icon: const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF64748B)),
                                                onPressed: () => _showEditSeatDialog(seat),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                              ),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline_outlined, size: 14, color: Colors.red),
                                                onPressed: () => _deleteSeat(seat['id'], seat['seat_label'] ?? ''),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),

                                      // Action Buttons at bottom of expanded floor card
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          TextButton.icon(
                                            onPressed: () => _showAddSectionDialog(floorId),
                                            icon: const Icon(Icons.add_rounded, size: 14, color: Color(0xFFE65C00)),
                                            label: Text('Add Section', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                                          ),
                                          if (floorSections.isEmpty)
                                            TextButton.icon(
                                              onPressed: () => _showAddSeatBottomSheet(floorId: floorId, sectionId: null),
                                              icon: const Icon(Icons.add_rounded, size: 14, color: Color(0xFFE65C00)),
                                              label: Text('Add Direct Seat', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // Bottom Add Floor button
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _showAddFloorDialog,
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
                    label: Text('Add New Floor', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── S072 Dual-Tab Add/Generate Seats Bottom Sheet ───────────────────────────
class _AddSeatBottomSheet extends StatefulWidget {
  final String libraryId;
  final String floorId;
  final String? sectionId;
  final String selectedShiftId;
  final List<Map<String, dynamic>> existingSeats;
  final VoidCallback onComplete;

  const _AddSeatBottomSheet({
    required this.libraryId,
    required this.floorId,
    required this.sectionId,
    required this.selectedShiftId,
    required this.existingSeats,
    required this.onComplete,
  });

  @override
  State<_AddSeatBottomSheet> createState() => _AddSeatBottomSheetState();
}

class _AddSeatBottomSheetState extends State<_AddSeatBottomSheet> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;

  // Single Seat Controllers (no defaults, empty by default)
  final _singlePrefixCtrl = TextEditingController();
  final _singleNumCtrl = TextEditingController();
  bool _singleOverlap = false;
  String _singleFullLabel = '';

  // Bulk Generate Controllers (no defaults, empty by default)
  final _bulkPrefixCtrl = TextEditingController();
  final _bulkStartCtrl = TextEditingController();
  final _bulkCountCtrl = TextEditingController();
  String _bulkFormat = '1, 2'; // or '01, 02'
  List<String> _bulkPreview = [];
  List<String> _bulkOverlapLabels = [];
  bool _bulkHasOverlap = false;

  String? _bulkLimitWarning;
  bool _bulkLimitExceeded = false;

  List<Map<String, dynamic>> _sections = [];
  String? _selectedSectionId;
  bool _loadingSections = false;

  String? _prefixHint;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _singlePrefixCtrl.addListener(_validateSingleSeat);
    _singleNumCtrl.addListener(_validateSingleSeat);

    _bulkPrefixCtrl.addListener(_validateBulkGenerate);
    _bulkStartCtrl.addListener(_validateBulkGenerate);
    _bulkCountCtrl.addListener(_validateBulkGenerate);

    _selectedSectionId = widget.sectionId;
    _autoDetectPrefix();
    _validateSingleSeat();
    _validateBulkGenerate();
    _fetchSections();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _singlePrefixCtrl.dispose();
    _singleNumCtrl.dispose();
    _bulkPrefixCtrl.dispose();
    _bulkStartCtrl.dispose();
    _bulkCountCtrl.dispose();
    super.dispose();
  }

  void _autoDetectPrefix() {
    final relevantSeats = widget.existingSeats.where((s) =>
        s['floor_id'] == widget.floorId &&
        s['section_id'] == _selectedSectionId
    ).toList();

    if (relevantSeats.isEmpty) {
      setState(() {
        _singlePrefixCtrl.text = '';
        _bulkPrefixCtrl.text = '';
        _prefixHint = null;
      });
      return;
    }

    String getPrefix(String label) {
      int i = label.length - 1;
      while (i >= 0 && RegExp(r'[0-9]').hasMatch(label[i])) {
        i--;
      }
      String prefixPart = label.substring(0, i + 1);
      if (prefixPart.endsWith('-')) {
        prefixPart = prefixPart.substring(0, prefixPart.length - 1);
      }
      return prefixPart.trim();
    }

    final uniquePrefixes = relevantSeats
        .map((s) => getPrefix(s['seat_label']?.toString() ?? ''))
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList();

    setState(() {
      if (uniquePrefixes.length == 1) {
        _singlePrefixCtrl.text = uniquePrefixes.first;
        _bulkPrefixCtrl.text = uniquePrefixes.first;
        _prefixHint = null;
      } else if (uniquePrefixes.length > 1) {
        _singlePrefixCtrl.text = '';
        _bulkPrefixCtrl.text = '';
        _prefixHint = 'Multiple prefixes found. Enter a new prefix manually.';
      } else {
        _singlePrefixCtrl.text = '';
        _bulkPrefixCtrl.text = '';
        _prefixHint = null;
      }
    });
  }

  Future<void> _fetchSections() async {
    setState(() => _loadingSections = true);
    try {
      final res = await supabase
          .from('sections')
          .select('id, name')
          .eq('floor_id', widget.floorId)
          .order('name');
      setState(() {
        _sections = List<Map<String, dynamic>>.from(res);
        _loadingSections = false;
        if (_selectedSectionId != null) {
          final exists = _sections.any((sec) => sec['id'] == _selectedSectionId);
          if (!exists) {
            _selectedSectionId = null;
          }
        }
      });
    } catch (e) {
      setState(() => _loadingSections = false);
    }
  }

  void _validateSingleSeat() {
    final prefix = _singlePrefixCtrl.text.trim();
    final number = _singleNumCtrl.text.trim();
    String calculatedLabel = '';

    if (prefix.isNotEmpty && number.isNotEmpty) {
      final cleanPrefix = prefix.endsWith('-') ? prefix.substring(0, prefix.length - 1) : prefix;
      calculatedLabel = '$cleanPrefix-$number';
    } else {
      calculatedLabel = prefix + number;
    }

    final String normLabel = calculatedLabel.toLowerCase().replaceAll(' ', '');

    final bool duplicate = widget.existingSeats.any((s) =>
        s['floor_id'] == widget.floorId &&
        s['seat_label'].toString().toLowerCase().replaceAll(' ', '') == normLabel);

    setState(() {
      _singleFullLabel = calculatedLabel;
      _singleOverlap = duplicate;
    });
  }

  void _validateBulkGenerate() {
    final prefix = _bulkPrefixCtrl.text.trim();
    final start = int.tryParse(_bulkStartCtrl.text.trim());
    final count = int.tryParse(_bulkCountCtrl.text.trim());

    if (start == null || count == null || count <= 0 || prefix.isEmpty) {
      setState(() {
        _bulkPreview = [];
        _bulkOverlapLabels = [];
        _bulkHasOverlap = false;
        _bulkLimitWarning = null;
        _bulkLimitExceeded = false;
      });
      return;
    }

    if (count > 500) {
      setState(() {
        _bulkPreview = [];
        _bulkOverlapLabels = [];
        _bulkHasOverlap = false;
        _bulkLimitWarning = "⚠️ Limit exceeded: You cannot generate more than 500 seats at once.";
        _bulkLimitExceeded = true;
      });
      return;
    }

    final bool pad = _bulkFormat == '01, 02';
    final List<String> generated = [];
    final List<String> preview = [];
    final List<String> duplicates = [];
    final cleanPrefix = prefix.endsWith('-') ? prefix.substring(0, prefix.length - 1) : prefix;

    final to = start + count - 1;

    for (int i = start; i <= to; i++) {
      final String numStr = pad ? i.toString().padLeft(2, '0') : i.toString();
      final String label = '$cleanPrefix-$numStr';
      generated.add(label);

      final String norm = label.toLowerCase().replaceAll(' ', '');
      final bool exists = widget.existingSeats.any((s) =>
          s['floor_id'] == widget.floorId &&
          s['seat_label'].toString().toLowerCase().replaceAll(' ', '') == norm);

      if (exists) {
        duplicates.add(label);
      }

      if (preview.length < 6) {
        preview.add(label);
      }
    }

    setState(() {
      _bulkPreview = preview;
      _bulkOverlapLabels = duplicates;
      _bulkHasOverlap = duplicates.isNotEmpty;
      if (count >= 80) {
        _bulkLimitWarning = "⚠️ Generating $count seats may take a few seconds. Continue?";
        _bulkLimitExceeded = false;
      } else {
        _bulkLimitWarning = null;
        _bulkLimitExceeded = false;
      }
    });
  }

  Future<void> _addSingleSeat() async {
    final labelToInsert = _singleFullLabel.trim();
    if (_singleOverlap || labelToInsert.isEmpty) return;

    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    setState(() => _isSaving = true);
    try {
      // 1. Direct Supabase uniqueness check
      final dupCheck = await supabase
          .from('seats')
          .select('id')
          .eq('library_id', widget.libraryId)
          .eq('shift_id', widget.selectedShiftId)
          .eq('seat_label', labelToInsert)
          .maybeSingle();

      if (dupCheck != null) {
        setState(() => _isSaving = false);
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Seat label already exists. Choose a different prefix or number.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
        return;
      }

      // 2. Direct Supabase insert
      await supabase.from('seats').insert({
        'library_id': widget.libraryId,
        'floor_id': widget.floorId,
        'section_id': _selectedSectionId,
        'shift_id': widget.selectedShiftId,
        'seat_label': labelToInsert,
        'status': 'vacant',
      });

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Seat "$labelToInsert" added successfully! ✓')),
      );
      navigator.pop();
      widget.onComplete();
    } catch (e) {
      setState(() => _isSaving = false);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error adding seat: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _bulkGenerateSeats() async {
    if (_bulkHasOverlap || _bulkPreview.isEmpty || _bulkLimitExceeded) return;

    final prefix = _bulkPrefixCtrl.text.trim();
    final cleanPrefix = prefix.endsWith('-') ? prefix.substring(0, prefix.length - 1) : prefix;
    final start = int.parse(_bulkStartCtrl.text.trim());
    final count = int.parse(_bulkCountCtrl.text.trim());
    final bool pad = _bulkFormat == '01, 02';

    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Show warning/confirmation dialog if count >= 80
    if (count >= 80) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
              const SizedBox(width: 8),
              Text('Generate Seats', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'Generating $count seats may take a few seconds. Do you want to continue?',
            style: GoogleFonts.inter(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
              ),
              child: Text('Continue', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (proceed != true) return;
    }

    setState(() => _isSaving = true);
    try {
      final List<String> labelsToInsert = [];
      final List<Map<String, dynamic>> seatsToInsert = [];
      final to = start + count - 1;
      for (int i = start; i <= to; i++) {
        final String numStr = pad ? i.toString().padLeft(2, '0') : i.toString();
        final String label = '$cleanPrefix-$numStr';
        labelsToInsert.add(label);
        seatsToInsert.add({
          'library_id': widget.libraryId,
          'floor_id': widget.floorId,
          'section_id': _selectedSectionId,
          'shift_id': widget.selectedShiftId,
          'seat_label': label,
          'status': 'vacant',
        });
      }

      // 1. Direct Supabase uniqueness check across the bulk set
      final existingRes = await supabase
          .from('seats')
          .select('seat_label')
          .eq('library_id', widget.libraryId)
          .eq('shift_id', widget.selectedShiftId)
          .inFilter('seat_label', labelsToInsert);

      final List<dynamic> dbExistingList = existingRes as List<dynamic>;
      if (dbExistingList.isNotEmpty) {
        final List<String> dupLabels = dbExistingList.map((e) => e['seat_label'].toString()).toList();
        setState(() => _isSaving = false);
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Seat labels already exist: ${dupLabels.join(", ")}. Choose a different range or prefix.'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
        return;
      }

      // 2. Direct Supabase insert
      await supabase.from('seats').insert(seatsToInsert);

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Generated ${seatsToInsert.length} seats successfully! ✓')),
      );
      navigator.pop();
      widget.onComplete();
    } catch (e) {
      setState(() => _isSaving = false);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error generating seats: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'Add Seat Layout',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),

          if (_loadingSections)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: SizedBox(
                height: 48,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
                    ),
                  ),
                ),
              ),
            )
          else if (_sections.isNotEmpty) ...[
            DropdownButtonFormField<String?>(
              value: (_selectedSectionId == null || _sections.any((sec) => sec['id'] == _selectedSectionId)) ? _selectedSectionId : null,
              decoration: const InputDecoration(
                labelText: 'Select Section',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Direct Floor Seat (No Section)'),
                ),
                ..._sections.map((sec) {
                  return DropdownMenuItem<String?>(
                    value: sec['id'],
                    child: Text(sec['name'] ?? ''),
                  );
                }),
              ],
              onChanged: (val) {
                setState(() {
                  _selectedSectionId = val;
                });
                _autoDetectPrefix();
              },
            ),
            const SizedBox(height: 12),
          ],

          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFFE65C00),
            labelColor: const Color(0xFFE65C00),
            unselectedLabelColor: const Color(0xFF64748B),
            labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(text: 'Single Seat'),
              Tab(text: 'Bulk Generate'),
            ],
          ),
          const SizedBox(height: 16),

          if (_isSaving)
            const SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))),
              ),
            )
          else
            SizedBox(
              height: 300,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Single Seat
                  SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                flex: 1,
                                child: TextField(
                                  controller: _singlePrefixCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Prefix',
                                    hintText: 'e.g. S',
                                    helperText: _prefixHint,
                                    helperStyle: _prefixHint != null
                                        ? const TextStyle(color: Color(0xFFD97706), fontSize: 10, fontWeight: FontWeight.bold)
                                        : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 1,
                                child: TextField(
                                  controller: _singleNumCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Number',
                                    hintText: 'e.g. 1',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Overlap warnings
                          if (_singleOverlap)
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFCA5A5)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "Seat label '$_singleFullLabel' already exists. Choose a different number or prefix.",
                                      style: GoogleFonts.inter(color: const Color(0xFFB91C1C), fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (_singleFullLabel.trim().isNotEmpty)
                            Text(
                              "Generated seat will be: $_singleFullLabel",
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                          const SizedBox(height: 24),

                          Tooltip(
                            message: (_singlePrefixCtrl.text.trim().isEmpty || _singleNumCtrl.text.trim().isEmpty)
                                ? 'Enter prefix and seat numbers'
                                : '',
                            child: ElevatedButton(
                              onPressed: _singleOverlap ||
                                      _singleFullLabel.trim().isEmpty ||
                                      _singlePrefixCtrl.text.trim().isEmpty ||
                                      _singleNumCtrl.text.trim().isEmpty
                                  ? null
                                  : _addSingleSeat,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE65C00),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text('Add Single Seat', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Tab 2: Bulk Generate
                  SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _bulkPrefixCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Seat Label Prefix',
                                    hintText: 'e.g. S',
                                    helperText: _prefixHint,
                                    helperStyle: _prefixHint != null
                                        ? const TextStyle(color: Color(0xFFD97706), fontSize: 10, fontWeight: FontWeight.bold)
                                        : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _bulkStartCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Start Number',
                                    hintText: 'e.g. 1',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _bulkCountCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Total Seats Count',
                                    hintText: 'e.g. 10',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Format selector
                          Row(
                            children: [
                              Text('Number Format:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569))),
                              const SizedBox(width: 12),
                              DropdownButton<String>(
                                value: ['1, 2', '01, 02'].contains(_bulkFormat) ? _bulkFormat : '1, 2',
                                underline: Container(),
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                items: const [
                                  DropdownMenuItem(value: '1, 2', child: Text('Standard (1, 2, ...)')),
                                  DropdownMenuItem(value: '01, 02', child: Text('Padded (01, 02, ...)')),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _bulkFormat = val;
                                    });
                                    _validateBulkGenerate();
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Real-time Preview tags
                          if (_bulkPreview.isNotEmpty && !_bulkHasOverlap && !_bulkLimitExceeded) ...[
                            Text(
                              'Preview (First 6 labels):',
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: _bulkPreview.map((lbl) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFCBD5E1)),
                                  ),
                                  child: Text(
                                    lbl,
                                    style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF334155), fontWeight: FontWeight.bold),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],

                          // Overlap validation banner
                          if (_bulkHasOverlap)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFCA5A5)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 16),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "These seat labels already exist: ${_bulkOverlapLabels.join(', ')}. Remove them from the range or use a different prefix.",
                                      style: GoogleFonts.inter(color: const Color(0xFFB91C1C), fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Limit exceeded or warning banner
                          if (_bulkLimitWarning != null)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _bulkLimitExceeded ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _bulkLimitExceeded ? const Color(0xFFFCA5A5) : const Color(0xFFFDE68A)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _bulkLimitExceeded ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                                    color: _bulkLimitExceeded ? const Color(0xFFEF4444) : const Color(0xFFD97706),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _bulkLimitWarning!,
                                      style: GoogleFonts.inter(
                                        color: _bulkLimitExceeded ? const Color(0xFFB91C1C) : const Color(0xFFB45309),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          const SizedBox(height: 16),
                          Tooltip(
                            message: (_bulkPrefixCtrl.text.trim().isEmpty ||
                                    _bulkStartCtrl.text.trim().isEmpty ||
                                    _bulkCountCtrl.text.trim().isEmpty)
                                ? 'Enter prefix and seat numbers'
                                : '',
                            child: ElevatedButton(
                              onPressed: _bulkHasOverlap ||
                                      _bulkPreview.isEmpty ||
                                      _bulkLimitExceeded ||
                                      _bulkPrefixCtrl.text.trim().isEmpty ||
                                      _bulkStartCtrl.text.trim().isEmpty ||
                                      _bulkCountCtrl.text.trim().isEmpty
                                  ? null
                                  : _bulkGenerateSeats,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE65C00),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text('Generate Seats', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

