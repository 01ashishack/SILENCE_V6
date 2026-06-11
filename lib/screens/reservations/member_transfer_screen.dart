import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../utils/audit_logger.dart';
import '../../utils/error_messages.dart';
import '../../widgets/states/states.dart';

/// Admin moves a member from one of their libraries to ANOTHER library they own.
///
/// Honest model: this is an admin operation, not a purchase. The member keeps
/// their current expiry (remaining days carry over) and NO new payment is taken.
/// The old seat is freed, the old membership is marked `transferred`, a new
/// active membership is created in the target library, the chosen seat is
/// occupied, a `transfers` audit row is written, and the member is notified.
class MemberTransferScreen extends StatefulWidget {
  final String memberId;
  final String memberName;
  final Map<String, dynamic> fromMembership;

  const MemberTransferScreen({
    super.key,
    required this.memberId,
    required this.memberName,
    required this.fromMembership,
  });

  @override
  State<MemberTransferScreen> createState() => _MemberTransferScreenState();
}

class _MemberTransferScreenState extends State<MemberTransferScreen> {
  final supabase = Supabase.instance.client;

  bool _loadingLibs = true;
  Object? _libErr;
  String _fromLibraryName = 'Current library';
  List<Map<String, dynamic>> _libraries = [];

  Map<String, dynamic>? _selectedLib;
  bool _loadingShifts = false;
  Object? _shiftErr;
  List<Map<String, dynamic>> _shifts = [];

  Map<String, dynamic>? _selectedShift;
  bool _loadingSeats = false;
  Object? _seatErr;
  List<Map<String, dynamic>> _seats = [];

  Map<String, dynamic>? _selectedSeat;
  bool _assignSeatLater = false;

  bool _submitting = false;

  String get _fromLibraryId => widget.fromMembership['library_id'].toString();

  @override
  void initState() {
    super.initState();
    _loadLibraries();
  }

  Future<void> _loadLibraries() async {
    setState(() {
      _loadingLibs = true;
      _libErr = null;
    });
    try {
      final user = supabase.auth.currentUser;
      final res = await supabase
          .from('libraries')
          .select('id, name, address_city')
          .eq('owner_id', user!.id);
      if (!mounted) return;
      final all = List<Map<String, dynamic>>.from(res);
      final fromLib = all.where((l) => l['id'].toString() == _fromLibraryId).toList();
      if (fromLib.isNotEmpty) {
        _fromLibraryName = (fromLib.first['name'] ?? 'Current library').toString();
      }
      setState(() {
        _libraries = all
            .where((l) => l['id'].toString() != _fromLibraryId)
            .toList();
        _loadingLibs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _libErr = e;
        _loadingLibs = false;
      });
    }
  }

  Future<void> _selectLibrary(Map<String, dynamic> lib) async {
    setState(() {
      _selectedLib = lib;
      _selectedShift = null;
      _shifts = [];
      _shiftErr = null;
      _selectedSeat = null;
      _assignSeatLater = false;
      _seats = [];
      _loadingShifts = true;
    });
    try {
      final res = await supabase
          .from('shifts')
          .select('id, name, start_time, end_time')
          .eq('library_id', lib['id'])
          .eq('is_archived', false)
          .order('start_time');
      if (!mounted) return;
      setState(() {
        _shifts = List<Map<String, dynamic>>.from(res);
        _loadingShifts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _shiftErr = e;
        _loadingShifts = false;
      });
    }
  }

  Future<void> _selectShift(Map<String, dynamic> shift) async {
    setState(() {
      _selectedShift = shift;
      _selectedSeat = null;
      _assignSeatLater = false;
      _seats = [];
      _seatErr = null;
      _loadingSeats = true;
    });
    try {
      final res = await supabase
          .from('seats')
          .select('id, seat_label')
          .eq('library_id', _selectedLib!['id'])
          .eq('shift_id', shift['id'])
          .eq('status', 'vacant')
          .order('seat_label');
      if (!mounted) return;
      setState(() {
        _seats = List<Map<String, dynamic>>.from(res);
        _loadingSeats = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _seatErr = e;
        _loadingSeats = false;
      });
    }
  }

  bool get _canTransfer =>
      _selectedLib != null &&
      _selectedShift != null &&
      (_selectedSeat != null || _assignSeatLater) &&
      !_submitting;

  Future<void> _confirmAndTransfer() async {
    final toLibName = (_selectedLib!['name'] ?? 'the selected library').toString();
    final seatLabel = _selectedSeat != null
        ? 'Seat ${_selectedSeat!['seat_label']}'
        : 'No seat (assign later)';
    final endDate = widget.fromMembership['end_date']?.toString();
    final expiryText = _formatDate(endDate);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Confirm transfer',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _confirmRow('Member', widget.memberName),
            _confirmRow('From', _fromLibraryName),
            _confirmRow('To', toLibName),
            _confirmRow('Shift', (_selectedShift!['name'] ?? '—').toString()),
            _confirmRow('Seat', seatLabel),
            _confirmRow('Membership valid until', expiryText),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.infoBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Text(
                'The member keeps their remaining days. No new payment is taken — this is an admin move.',
                style: GoogleFonts.inter(fontSize: 11.5, height: 1.4, color: const Color(0xFF1D4ED8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text('Transfer', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _performTransfer();
    }
  }

  Future<void> _performTransfer() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final user = supabase.auth.currentUser;
    final toLibId = _selectedLib!['id'].toString();
    final toShiftId = _selectedShift!['id'].toString();
    final oldMembershipId = widget.fromMembership['id'].toString();
    final oldSeatId = widget.fromMembership['seat_id']?.toString();
    final newSeatId = _assignSeatLater ? null : _selectedSeat?['id']?.toString();

    try {
      // Guard: don't create a duplicate active membership in the target library.
      final existing = await supabase
          .from('memberships')
          .select('id')
          .eq('member_id', widget.memberId)
          .eq('library_id', toLibId)
          .inFilter('status', ['active', 'trial', 'hold'])
          .limit(1)
          .maybeSingle();
      if (!mounted) return;
      if (existing != null) {
        _fail('This member already has an active membership in that library.');
        return;
      }

      // Race check: the chosen seat must still be vacant.
      if (newSeatId != null) {
        final check = await supabase
            .from('seats')
            .select('status')
            .eq('id', newSeatId)
            .single();
        if (!mounted) return;
        if (check['status'] != 'vacant') {
          _fail('That seat was just taken. Pick another seat.');
          return;
        }
      }

      // 1. Free the old seat (only if no other active membership holds it).
      if (oldSeatId != null) {
        final otherActive = await supabase
            .from('memberships')
            .select('id')
            .eq('seat_id', oldSeatId)
            .neq('id', oldMembershipId)
            .inFilter('status', ['active', 'trial', 'hold'])
            .limit(1)
            .maybeSingle();
        if (!mounted) return;
        if (otherActive == null) {
          await supabase.from('seats').update({
            'status': 'vacant',
            'occupied_by_member_id': null,
          }).eq('id', oldSeatId);
        }
      }

      // 2. Mark the old membership transferred + release its seat link.
      await supabase.from('memberships').update({
        'status': 'transferred',
        'seat_id': null,
        'exited_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', oldMembershipId);

      // 3. Create the new membership in the target library (expiry preserved).
      final oldStatus = widget.fromMembership['status']?.toString();
      final newStatus = oldStatus == 'trial' ? 'trial' : 'active';
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final endDate = widget.fromMembership['end_date']?.toString() ?? today;

      final inserted = await supabase
          .from('memberships')
          .insert({
            'member_id': widget.memberId,
            'library_id': toLibId,
            'shift_id': toShiftId,
            'seat_id': newSeatId,
            'plan_type': widget.fromMembership['plan_type'] ?? 'monthly',
            'start_date': today,
            'end_date': endDate,
            'status': newStatus,
            'trial_used': widget.fromMembership['trial_used'] ?? false,
            'discount_amount': widget.fromMembership['discount_amount'] ?? 0,
            'discount_reason': widget.fromMembership['discount_reason'],
            'transferred_from': oldMembershipId,
            'approved_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select('id')
          .single();
      if (!mounted) return;
      final newMembershipId = inserted['id'].toString();

      // 4. Occupy the new seat.
      if (newSeatId != null) {
        await supabase.from('seats').update({
          'status': 'occupied',
          'occupied_by_member_id': widget.memberId,
        }).eq('id', newSeatId);
      }

      // 5. Record the transfer.
      await supabase.from('transfers').insert({
        'member_id': widget.memberId,
        'from_membership_id': oldMembershipId,
        'to_membership_id': newMembershipId,
        'from_library_id': _fromLibraryId,
        'to_library_id': toLibId,
        'transfer_date': DateTime.now().toUtc().toIso8601String(),
        'initiated_by_admin_id': user!.id,
      });

      // 6. Notify the member.
      final toLibName = (_selectedLib!['name'] ?? 'a new library').toString();
      try {
        await supabase.from('notifications').insert({
          'user_id': widget.memberId,
          'title': 'Membership transferred',
          'body':
              'Your membership has been moved from $_fromLibraryName to $toLibName by the admin. '
              'It stays valid until ${_formatDate(endDate)}.',
          'data': {'type': 'membership_transferred'},
        });
      } catch (e) {
        debugPrint('transfer notify failed: $e');
      }

      // 7. Audit.
      await AuditLogger.instance.log(
        action: 'member_transfer',
        category: AuditLogger.categoryMembers,
        title: 'Transferred member',
        details: '${widget.memberName} · $_fromLibraryName → $toLibName',
        libraryId: _fromLibraryId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.memberName} transferred to $toLibName.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      _fail(friendlyError(e));
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: AppColors.scaffold,
          appBar: AppBar(
            backgroundColor: AppColors.primary,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('Transfer Member',
                style: GoogleFonts.outfit(
                    fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            centerTitle: true,
          ),
          body: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingLibs) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_libErr != null) {
      return ErrorState(error: _libErr, onRetry: _loadLibraries);
    }
    if (_libraries.isEmpty) {
      return const EmptyState(
        icon: Icons.account_balance_outlined,
        title: 'No other library to transfer to',
        message:
            'You only own one library. Member transfers move someone to another library you own.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      physics: const BouncingScrollPhysics(),
      children: [
        _memberHeader(),
        const SizedBox(height: 20),
        _sectionTitle('1. Choose destination library'),
        const SizedBox(height: 8),
        ..._libraries.map(_libraryTile),
        if (_selectedLib != null) ...[
          const SizedBox(height: 20),
          _sectionTitle('2. Choose shift'),
          const SizedBox(height: 8),
          _buildShiftSection(),
        ],
        if (_selectedShift != null) ...[
          const SizedBox(height: 20),
          _sectionTitle('3. Choose seat'),
          const SizedBox(height: 8),
          _buildSeatSection(),
        ],
        const SizedBox(height: 28),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: const Color(0xFFE2C7B5),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          onPressed: _canTransfer ? _confirmAndTransfer : null,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text('Transfer Member',
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _memberHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: AppColors.orangeTintBg, shape: BoxShape.circle),
            child: const Icon(Icons.person_outline, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.memberName,
                    style: GoogleFonts.outfit(
                        fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text('Currently at $_fromLibraryName',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(text,
        style: GoogleFonts.outfit(
            fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary));
  }

  Widget _libraryTile(Map<String, dynamic> lib) {
    final selected = _selectedLib?['id'] == lib['id'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _selectLibrary(lib),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? AppColors.orangeTintBg : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? AppColors.primary : AppColors.textMuted, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((lib['name'] ?? 'Library').toString(),
                        style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    if ((lib['address_city'] ?? '').toString().isNotEmpty)
                      Text((lib['address_city']).toString(),
                          style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShiftSection() {
    if (_loadingShifts) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_shiftErr != null) {
      return ErrorState(error: _shiftErr, onRetry: () => _selectLibrary(_selectedLib!));
    }
    if (_shifts.isEmpty) {
      return _infoCard('This library has no active shifts set up yet.');
    }
    return Column(
      children: _shifts.map((shift) {
        final selected = _selectedShift?['id'] == shift['id'];
        final time = _shiftTime(shift);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _selectShift(shift),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected ? AppColors.orangeTintBg : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                    width: selected ? 1.5 : 1),
              ),
              child: Row(
                children: [
                  Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: selected ? AppColors.primary : AppColors.textMuted, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      time.isEmpty
                          ? (shift['name'] ?? 'Shift').toString()
                          : '${shift['name'] ?? 'Shift'}  ·  $time',
                      style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSeatSection() {
    if (_loadingSeats) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_seatErr != null) {
      return ErrorState(error: _seatErr, onRetry: () => _selectShift(_selectedShift!));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_seats.isEmpty)
          _infoCard('No vacant seats in this shift. You can still transfer and assign a seat later.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _seats.map((seat) {
              final selected = !_assignSeatLater && _selectedSeat?['id'] == seat['id'];
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() {
                  _selectedSeat = seat;
                  _assignSeatLater = false;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: selected ? AppColors.primary : AppColors.border),
                  ),
                  child: Text(
                    'Seat ${seat['seat_label']}',
                    style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : AppColors.textPrimary),
                  ),
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() {
            _assignSeatLater = true;
            _selectedSeat = null;
          }),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _assignSeatLater ? AppColors.orangeTintBg : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _assignSeatLater ? AppColors.primary : AppColors.border,
                  width: _assignSeatLater ? 1.5 : 1),
            ),
            child: Row(
              children: [
                Icon(
                    _assignSeatLater
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: _assignSeatLater ? AppColors.primary : AppColors.textMuted,
                    size: 20),
                const SizedBox(width: 10),
                Text('Assign a seat later',
                    style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoCard(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.info, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: GoogleFonts.inter(
                    fontSize: 11.5, height: 1.4, color: const Color(0xFF1D4ED8))),
          ),
        ],
      ),
    );
  }

  Widget _confirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.inter(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  String _shiftTime(Map<String, dynamic> shift) {
    final start = shift['start_time']?.toString();
    final end = shift['end_time']?.toString();
    if (start == null || end == null) return '';
    return '${_fmtTime(start)} – ${_fmtTime(end)}';
  }

  String _fmtTime(String raw) {
    try {
      final parts = raw.split(':');
      final h = int.parse(parts[0]);
      final m = parts.length > 1 ? parts[1] : '00';
      final period = h >= 12 ? 'PM' : 'AM';
      final h12 = h % 12 == 0 ? 12 : h % 12;
      return '$h12:$m $period';
    } catch (_) {
      return raw;
    }
  }
}
