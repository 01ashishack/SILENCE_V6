import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/calendar_picker.dart';
import '../../models/member_data.dart';

class AddMemberStep2 extends StatefulWidget {
  final String libraryId;
  final MemberData memberData;
  final Function(int) onTotalAmountChanged;

  const AddMemberStep2({
    super.key,
    required this.libraryId,
    required this.memberData,
    required this.onTotalAmountChanged,
  });

  @override
  State<AddMemberStep2> createState() => _AddMemberStep2State();
}

class _AddMemberStep2State extends State<AddMemberStep2> with AutomaticKeepAliveClientMixin {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;

  List<Map<String, dynamic>> _shifts = [];
  List<Map<String, dynamic>> _addOns = [];

  late final TextEditingController _trialDaysController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _trialDaysController = TextEditingController(text: widget.memberData.trialDays.toString());
    _trialDaysController.addListener(() {
      final days = int.tryParse(_trialDaysController.text.trim()) ?? 0;
      widget.memberData.trialDays = days;
    });
    _fetchShiftsAndAddons();
  }

  @override
  void didUpdateWidget(covariant AddMemberStep2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_trialDaysController.text != widget.memberData.trialDays.toString()) {
      _trialDaysController.text = widget.memberData.trialDays.toString();
    }
  }

  @override
  void dispose() {
    _trialDaysController.dispose();
    super.dispose();
  }

  Future<void> _fetchShiftsAndAddons() async {
    try {
      final shiftsRes = await _supabase
          .from('shifts')
          .select('id, name, start_time, end_time, price_monthly, price_3month, price_6month, trial_days')
          .eq('library_id', widget.libraryId)
          .eq('is_archived', false);

      final addonsRes = await _supabase
          .from('add_ons')
          .select('id, name, price, deposit')
          .eq('library_id', widget.libraryId)
          .eq('active', true);

      if (mounted) {
        setState(() {
          _shifts = List<Map<String, dynamic>>.from(shiftsRes);
          _addOns = List<Map<String, dynamic>>.from(addonsRes);
          _isLoading = false;

          // Default shift selection if none is set or selected shift doesn't exist anymore
          if (_shifts.isNotEmpty) {
            final exists = _shifts.any((s) => s['id'] == widget.memberData.selectedShiftId);
            if (widget.memberData.selectedShiftId == null || !exists) {
              final defShift = _shifts.first;
              final price = (defShift['price_monthly'] as num?)?.toInt() ?? 1500;
              widget.memberData.selectedShiftId = defShift['id'];
              widget.memberData.selectedShiftName = defShift['name'] ?? '';
              widget.memberData.selectedShiftPrice = price;
            }
          }
        });
        _calculateTotal();
      }
    } catch (e) {
      debugPrint('Error loading shifts/addons: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Map<String, dynamic>? get _selectedShift {
    if (widget.memberData.selectedShiftId == null) return null;
    try {
      return _shifts.firstWhere((s) => s['id'] == widget.memberData.selectedShiftId);
    } catch (_) {
      return null;
    }
  }

  int get _basePrice {
    final shift = _selectedShift;
    if (shift == null) return widget.memberData.selectedShiftPrice;
    return (shift['price_monthly'] as num?)?.toInt() ?? 1500;
  }

  int get _planPrice {
    final shift = _selectedShift;
    if (shift == null) return widget.memberData.selectedShiftPrice;
    final base = (shift['price_monthly'] as num?)?.toInt() ?? 1500;
    if (widget.memberData.planType == '3_month') {
      final dbPrice = (shift['price_3month'] as num?)?.toInt();
      return dbPrice ?? (base * 3 * 0.90).round();
    } else if (widget.memberData.planType == '6_month') {
      final dbPrice = (shift['price_6month'] as num?)?.toInt();
      return dbPrice ?? (base * 6 * 0.80).round();
    }
    return base; // Monthly
  }

  int get _addonsPrice {
    int total = 0;
    for (final addOn in _addOns) {
      if (widget.memberData.selectedAddonIds.contains(addOn['id'])) {
        final price = (addOn['price'] as num?)?.toInt() ?? 0;
        final deposit = (addOn['deposit'] as num?)?.toInt() ?? 0;
        total += price + deposit;
      }
    }
    return total;
  }

  void _calculateTotal() {
    final total = _planPrice + _addonsPrice;
    widget.onTotalAmountChanged(total);
  }

  DateTime get _calculatedPlanStart {
    if (widget.memberData.mode == 'existing') {
      return widget.memberData.planStartDate ?? widget.memberData.joiningDate;
    } else {
      if (widget.memberData.customPlanStart && widget.memberData.planStartDate != null) {
        return widget.memberData.planStartDate!;
      }
      return widget.memberData.joiningDate.add(Duration(days: widget.memberData.trialDays));
    }
  }

  DateTime get _calculatedExpiry {
    final start = _calculatedPlanStart;
    int durationMonths = 1;
    if (widget.memberData.planType == '3_month') durationMonths = 3;
    if (widget.memberData.planType == '6_month') durationMonths = 6;
    return DateTime(start.year, start.month + durationMonths, start.day);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
          ),
        ),
      );
    }

    if (_shifts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning_amber_rounded, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                'No active shifts configured for this library.',
                style: GoogleFonts.inter(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    final start = _calculatedPlanStart;
    final expiry = _calculatedExpiry;

    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE65C00), width: 1.5),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
          ),
          labelStyle: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 14),
          hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 14),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Select Shift
            Text(
              'Select Shift *',
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _shifts.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final s = _shifts[index];
                final isSelected = widget.memberData.selectedShiftId == s['id'];
                final price = (s['price_monthly'] as num?)?.toInt() ?? 1500;
                final startT = s['start_time'] ?? '08:00';
                final endT = s['end_time'] ?? '16:00';
                final cleanStart = startT.length > 5 ? startT.substring(0, 5) : startT;
                final cleanEnd = endT.length > 5 ? endT.substring(0, 5) : endT;

                return InkWell(
                  onTap: () {
                    setState(() {
                      widget.memberData.selectedShiftId = s['id'];
                      widget.memberData.selectedShiftName = s['name'] ?? '';
                      widget.memberData.selectedShiftPrice = price;
                    });
                    _calculateTotal();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? const Color(0xFFE65C00) : const Color(0xFFE5E7EB),
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s['name'] ?? 'Shift',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                                const SizedBox(width: 4),
                                Text(
                                  '$cleanStart - $cleanEnd',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Text(
                          '₹$price/mo',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isSelected ? const Color(0xFFE65C00) : const Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Plan Options pills
            Text(
              'Plan Options *',
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildPlanPill('monthly', 'Monthly', _basePrice),
                const SizedBox(width: 10),
                _buildPlanPill(
                  '3_month',
                  '3-Month',
                  (_selectedShift != null && _selectedShift!['price_3month'] != null)
                      ? (_selectedShift!['price_3month'] as num).toInt()
                      : (_basePrice * 3 * 0.90).round(),
                ),
                const SizedBox(width: 10),
                _buildPlanPill(
                  '6_month',
                  '6-Month',
                  (_selectedShift != null && _selectedShift!['price_6month'] != null)
                      ? (_selectedShift!['price_6month'] as num).toInt()
                      : (_basePrice * 6 * 0.80).round(),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Trial Days configuration (Only for new members)
            if (widget.memberData.mode == 'new') ...[
              Text(
                'Trial Days (Plan starts after trial)',
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _trialDaysController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.inter(color: const Color(0xFF1E293B)),
                decoration: const InputDecoration(
                  hintText: 'Enter trial days (0 for none)',
                ),
              ),
              const SizedBox(height: 16),

              // Custom plan start checkbox
              Row(
                children: [
                  Checkbox(
                    value: widget.memberData.customPlanStart,
                    activeColor: const Color(0xFFE65C00),
                    onChanged: (val) {
                      setState(() {
                        widget.memberData.customPlanStart = val ?? false;
                      });
                    },
                  ),
                  Expanded(
                    child: Text(
                      'Set custom plan start date (overrides default)',
                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Plan Start Date Picker
            if (widget.memberData.mode == 'existing' || widget.memberData.customPlanStart) ...[
              InkWell(
                onTap: () async {
                  final selected = await showCalendarGridBottomSheet(
                    context,
                    initialDate: widget.memberData.planStartDate ?? widget.memberData.joiningDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (selected != null) {
                    setState(() {
                      widget.memberData.planStartDate = selected;
                    });
                  }
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: widget.memberData.mode == 'existing' ? 'Plan Start Date *' : 'Custom Plan Start Date *',
                    suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20, color: Color(0xFF64748B)),
                  ),
                  child: Text(
                    '${start.day}/${start.month}/${start.year}',
                    style: GoogleFonts.inter(color: const Color(0xFF1E293B), fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Calculated Dates Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                border: Border.all(color: const Color(0xFFFFEDD5)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFFE65C00), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Membership Schedule',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFF9A3412)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start Date: ${start.day}/${start.month}/${start.year}\n'
                    'Expiry Date: ${expiry.day}/${expiry.month}/${expiry.year}',
                    style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: const Color(0xFFC2410C)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Optional Add-ons List
            if (_addOns.isNotEmpty) ...[
              Text(
                'Optional Add-ons & Deposits',
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 12),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _addOns.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final addOn = _addOns[index];
                  final addonId = addOn['id'] as String;
                  final isSelected = widget.memberData.selectedAddonIds.contains(addonId);
                  final price = (addOn['price'] as num?)?.toInt() ?? 0;
                  final deposit = (addOn['deposit'] as num?)?.toInt() ?? 0;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        final current = Set<String>.from(widget.memberData.selectedAddonIds);
                        if (isSelected) {
                          current.remove(addonId);
                        } else {
                          current.add(addonId);
                        }
                        widget.memberData.selectedAddonIds = current;
                      });
                      _calculateTotal();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? const Color(0xFFE65C00) : const Color(0xFFE5E7EB),
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: isSelected,
                            activeColor: const Color(0xFFE65C00),
                            onChanged: (val) {
                              setState(() {
                                final current = Set<String>.from(widget.memberData.selectedAddonIds);
                                if (val == true) {
                                  current.add(addonId);
                                } else {
                                  current.remove(addonId);
                                }
                                widget.memberData.selectedAddonIds = current;
                              });
                              _calculateTotal();
                            },
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  addOn['name'] ?? 'Add-on',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: const Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Price: ₹$price' + (deposit > 0 ? ' • Deposit: ₹$deposit' : ''),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (deposit > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Refundable',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[700],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],

            // Pricing Summary Box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Plan Price (${widget.memberData.planType == 'monthly' ? 'Monthly' : (widget.memberData.planType == '3_month' ? '3-Month' : '6-Month')})',
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                      ),
                      Text('₹$_planPrice', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                    ],
                  ),
                  if (_addonsPrice > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Add-ons & Deposits', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
                        Text('₹$_addonsPrice', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                      ],
                    ),
                  ],
                  const Divider(height: 24, color: Color(0xFFE5E7EB)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Amount', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                      Text('₹${_planPrice + _addonsPrice}', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanPill(String value, String title, int price) {
    final isSelected = widget.memberData.planType == value;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            widget.memberData.planType = value;
          });
          _calculateTotal();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFE65C00) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFFE65C00) : const Color(0xFFE5E7EB),
            ),
          ),
          child: Column(
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isSelected ? Colors.white : const Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '₹$price',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: isSelected ? Colors.white70 : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
