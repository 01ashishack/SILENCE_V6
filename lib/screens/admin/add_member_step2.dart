import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/calendar_picker.dart';
import '../../models/member_data.dart';
import '../../core/cache_service.dart';

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
    debugPrint('=== didUpdateWidget Triggered ===');
    debugPrint('old widget.libraryId: "${oldWidget.libraryId}"');
    debugPrint('new widget.libraryId: "${widget.libraryId}"');
    if (widget.libraryId != oldWidget.libraryId && widget.libraryId.isNotEmpty) {
      _isLoading = true;
      _fetchShiftsAndAddons();
    }
  }

  @override
  void dispose() {
    _trialDaysController.dispose();
    super.dispose();
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

  Future<String> _getLibraryId() async {
    if (widget.libraryId.isNotEmpty && widget.libraryId != 'all') {
      return widget.libraryId;
    }
    
    // Check local cache
    try {
      final cached = await CacheService.instance.readCache('admin_owned_libraries');
      if (cached != null && cached is List && cached.isNotEmpty) {
        final libId = cached.first['id'] as String?;
        if (libId != null && libId.isNotEmpty) {
          debugPrint('=== AddMemberStep2 resolved libraryId from cache: $libId ===');
          return libId;
        }
      }
    } catch (e) {
      debugPrint('Error reading cached libraries: $e');
    }

    // Query Supabase
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final res = await _supabase
            .from('libraries')
            .select('id')
            .eq('owner_id', user.id)
            .maybeSingle();
        if (res != null) {
          final libId = res['id'] as String?;
          if (libId != null && libId.isNotEmpty) {
            debugPrint('=== AddMemberStep2 resolved libraryId from DB: $libId ===');
            return libId;
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching libraries from Supabase: $e');
    }

    return '';
  }

  Future<void> _fetchShiftsAndAddons() async {
    try {
      debugPrint('=== DIAGNOSTIC START ===');
      debugPrint('widget.libraryId passed to step: "${widget.libraryId}"');
      
      final libraryId = await _getLibraryId();
      debugPrint('FETCH START');
      debugPrint('libraryId = $libraryId');
      
      if (libraryId.isEmpty) {
        debugPrint('Warning: resolved activeLibraryId is empty. Target line for _shifts = [] triggered at: Empty Library ID check.');
        if (mounted) {
          setState(() {
            _shifts = [];
            _addOns = [];
            _isLoading = false;
          });
        }
        return;
      }

      // 1. Fetch shifts first and update immediately
      final shifts = await _supabase
          .from('shifts')
          .select('id, name, start_time, end_time, price_monthly, price_3month, price_6month, trial_days')
          .eq('library_id', libraryId)
          .eq('is_archived', false);

      debugPrint('Supabase rows returned = ${shifts.length}');

      if (mounted) {
        setState(() {
          _shifts = List<Map<String, dynamic>>.from(shifts);
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
            _ensureValidPlanSelection();
          }
        });
        _calculateTotal();
      }

      // 2. Fetch add-ons independently and handle failure without breaking shifts rendering
      try {
        final addonsRes = await _supabase
            .from('add_ons')
            .select('id, name, price, refundable_deposit, price_type')
            .eq('library_id', libraryId)
            .eq('active', true);

        if (mounted) {
          setState(() {
            _addOns = List<Map<String, dynamic>>.from(addonsRes);
          });
          _calculateTotal();
        }
      } catch (addonsError) {
        debugPrint('Resilient loading: Failed to load add-ons, but shifts are rendered. Error: $addonsError');
      }

      debugPrint('=== DIAGNOSTIC END ===');
    } catch (e) {
      debugPrint('Caught exception during shift loading: $e');
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

  // A duration plan is offered only when the shift has a real configured price.
  bool get _has3MonthPlan {
    final p = _selectedShift?['price_3month'];
    return p is num && p > 0;
  }

  bool get _has6MonthPlan {
    final p = _selectedShift?['price_6month'];
    return p is num && p > 0;
  }

  // Keep planType valid for the current shift: if the admin had selected a
  // duration the shift doesn't configure, fall back to Monthly (always present).
  void _ensureValidPlanSelection() {
    final pt = widget.memberData.planType;
    if ((pt == '3_month' && !_has3MonthPlan) || (pt == '6_month' && !_has6MonthPlan)) {
      widget.memberData.planType = 'monthly';
    }
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
        final deposit = (addOn['refundable_deposit'] as num?)?.toInt() ?? 0;
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

    debugPrint('BUILD START');
    debugPrint('libraryId = ${widget.libraryId}');
    debugPrint('_isLoading = $_isLoading');
    debugPrint('_shifts.length = ${_shifts.length}');

    if (_isLoading) {
      debugPrint('build enters: Loading branch');
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
      debugPrint('build enters: Empty state branch');
      final isLibEmpty = widget.libraryId.isEmpty || widget.libraryId == 'all';
      return Center(
        child: Container(
          margin: const EdgeInsets.all(24.0),
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 48, color: Color(0xFFE65C00)),
              const SizedBox(height: 16),
              Text(
                isLibEmpty
                    ? 'Library ID not found. Please select a library.'
                    : 'No shifts configured for this library.',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A2E),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isLibEmpty
                    ? 'Go back to Admin Home and choose a valid library.'
                    : 'Please add shifts in Library Setup.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: const Color(0xFF6B7280),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                  });
                  _fetchShiftsAndAddons();
                },
                icon: const Icon(Icons.refresh, size: 16, color: Colors.white),
                label: Text(
                  'Refresh Shifts',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final start = _calculatedPlanStart;
    final expiry = _calculatedExpiry;
    debugPrint('build enters: Main content branch');

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
                final formattedStart = _formatTimeHM(startT);
                final formattedEnd = _formatTimeHM(endT);

                return InkWell(
                  onTap: () {
                    setState(() {
                      widget.memberData.selectedShiftId = s['id'];
                      widget.memberData.selectedShiftName = s['name'] ?? '';
                      widget.memberData.selectedShiftPrice = price;
                      _ensureValidPlanSelection();
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
                          color: Colors.black.withValues(alpha: 0.02),
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
                                  '$formattedStart – $formattedEnd',
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
                // Monthly is always configured (price_monthly is required on a shift).
                _buildPlanPill('monthly', 'Monthly', _basePrice),
                if (_has3MonthPlan) ...[
                  const SizedBox(width: 10),
                  _buildPlanPill(
                    '3_month',
                    '3-Month',
                    (_selectedShift!['price_3month'] as num).toInt(),
                  ),
                ],
                if (_has6MonthPlan) ...[
                  const SizedBox(width: 10),
                  _buildPlanPill(
                    '6_month',
                    '6-Month',
                    (_selectedShift!['price_6month'] as num).toInt(),
                  ),
                ],
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
                  if (!mounted) return;
                  if (selected != null) {
                    setState(() {
                      widget.memberData.planStartDate = selected;
                    });
                  }
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: widget.memberData.mode == 'existing' ? 'Plan Start Date *' : 'Custom Plan Start Date *',
                    suffixIcon: const Icon(Icons.calendar_today, size: 20, color: Color(0xFF64748B)),
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
                      const Icon(Icons.info, color: Color(0xFFE65C00), size: 18),
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
                  final deposit = (addOn['refundable_deposit'] as num?)?.toInt() ?? 0;
                  final isMonthly = (addOn['price_type'] ?? 'one_time') == 'monthly';

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
                            color: Colors.black.withValues(alpha: 0.02),
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
                                  'Price: ₹$price${deposit > 0 ? ' • Deposit: ₹$deposit' : ''}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isMonthly ? const Color(0xFFFFF1E6) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isMonthly ? 'Monthly' : 'One-time',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isMonthly ? const Color(0xFFE65C00) : const Color(0xFF64748B),
                                    ),
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
                    color: Colors.black.withValues(alpha: 0.02),
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
