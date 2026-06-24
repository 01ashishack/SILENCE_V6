import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../utils/error_messages.dart';
import '../../utils/time_utils.dart';

/// Admin-side **direct** membership renewal.
///
/// Unlike the member-facing `RenewalScreen` (which submits a request with UPI
/// proof + "I have paid"), the admin is the authority: this sheet extends the
/// membership's `end_date` immediately, records a confirmed payment, notifies
/// the member, and writes an audit entry. Returns `true` on success.
Future<bool?> showAdminRenewSheet(
  BuildContext context, {
  required Map<String, dynamic> membership,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AdminRenewSheet(membership: membership),
  );
}

class _AdminRenewSheet extends StatefulWidget {
  final Map<String, dynamic> membership;
  const _AdminRenewSheet({required this.membership});

  @override
  State<_AdminRenewSheet> createState() => _AdminRenewSheetState();
}

class _AdminRenewSheetState extends State<_AdminRenewSheet> {
  final supabase = Supabase.instance.client;

  String _plan = 'monthly'; // monthly | 3_month | 6_month
  String _method = 'cash'; // cash | upi
  bool _loading = true;
  bool _submitting = false;

  Map<String, dynamic>? _shift;

  String get _membershipId => widget.membership['id']?.toString() ?? '';
  String? get _shiftId => widget.membership['shift_id']?.toString();

  String get _memberName {
    final m = widget.membership['member_id'];
    if (m is Map) return (m['full_name'] ?? 'Member').toString();
    return 'Member';
  }

  @override
  void initState() {
    super.initState();
    _plan = (widget.membership['plan_type'] ?? 'monthly').toString();
    if (_plan != 'monthly' && _plan != '3_month' && _plan != '6_month') {
      _plan = 'monthly';
    }
    _loadShift();
  }

  Future<void> _loadShift() async {
    try {
      if (_shiftId != null) {
        final res = await supabase
            .from('shifts')
            .select('name, price_monthly, price_3month, price_6month')
            .eq('id', _shiftId!)
            .maybeSingle();
        _shift = res;
      }
    } catch (e) {
      debugPrint('renew shift load failed: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  int _durationMonths(String plan) =>
      plan == '6_month' ? 6 : (plan == '3_month' ? 3 : 1);

  int _priceFor(String plan) {
    final monthly = (_shift?['price_monthly'] as int?) ?? 0;
    switch (plan) {
      case '3_month':
        return (_shift?['price_3month'] as int?) ?? monthly * 3;
      case '6_month':
        return (_shift?['price_6month'] as int?) ?? monthly * 6;
      default:
        return monthly;
    }
  }

  DateTime _addMonths(DateTime d, int months) {
    final y = d.year + ((d.month - 1 + months) ~/ 12);
    final m = (d.month - 1 + months) % 12 + 1;
    final day = d.day;
    final lastDay = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, day > lastDay ? lastDay : day);
  }

  Future<void> _confirm() async {
    if (_membershipId.isEmpty) return;
    setState(() => _submitting = true);
    try {
      // Atomic server-side renewal (audit M7 + C5): the RPC derives the amount
      // from the shift price, extends end_date in IST, records a CONFIRMED
      // payment, writes the audit row and notifies the member — all in one
      // transaction. The client no longer sends the amount or payment status.
      final res = await supabase.rpc('renew_membership', params: {
        'p_membership_id': _membershipId,
        'p_plan_type': _plan,
        'p_method': _method,
      });
      final data = (res is List && res.isNotEmpty) ? res.first : res;
      final newEnd = DateTime.tryParse(
              (data is Map ? data['end_date'] : null)?.toString() ?? '') ??
          _addMonths(istNow(), _durationMonths(_plan));

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$_memberName renewed — new expiry ${DateFormat('dd MMM yyyy').format(newEnd)}.'),
          backgroundColor: const Color(0xFF22C55E),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red[600]),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final endStr = widget.membership['end_date']?.toString();
    final curExpiry = endStr != null ? DateTime.tryParse(endStr) : null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: Color(0xFFE65C00))),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Text('Renew — $_memberName',
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E))),
                  const SizedBox(height: 4),
                  Text(
                    curExpiry != null
                        ? 'Current expiry: ${DateFormat('dd MMM yyyy').format(curExpiry)}'
                        : 'No current expiry on record',
                    style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),
                  Text('Plan', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF475569))),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _planPill('monthly', '1 Month'),
                      const SizedBox(width: 8),
                      _planPill('3_month', '3 Months'),
                      const SizedBox(width: 8),
                      _planPill('6_month', '6 Months'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Payment method', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF475569))),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _methodPill('cash', 'Cash'),
                      const SizedBox(width: 8),
                      _methodPill('upi', 'UPI'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7F0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Amount', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF475569))),
                        Text('₹${_priceFor(_plan)}',
                            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _submitting ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: _submitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('Confirm Renewal', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _planPill(String value, String label) {
    final selected = _plan == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _plan = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE65C00) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? const Color(0xFFE65C00) : const Color(0xFFE2E8F0)),
          ),
          child: Center(
            child: Text(label,
                style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : const Color(0xFF475569))),
          ),
        ),
      ),
    );
  }

  Widget _methodPill(String value, String label) {
    final selected = _method == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _method = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFF1E6) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? const Color(0xFFE65C00) : const Color(0xFFE2E8F0)),
          ),
          child: Center(
            child: Text(label,
                style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? const Color(0xFFE65C00) : const Color(0xFF475569))),
          ),
        ),
      ),
    );
  }
}
