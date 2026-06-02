import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class LibrarySetupStage3Screen extends StatefulWidget {
  const LibrarySetupStage3Screen({super.key});

  @override
  State<LibrarySetupStage3Screen> createState() => _LibrarySetupStage3ScreenState();
}

class _ShiftModel {
  String? id;
  String name;
  TimeOfDay startTime;
  TimeOfDay endTime;
  int priceMonthly;
  int? price3Month;
  int? price6Month;
  int trialDays;
  String shiftType; // 'fixed' or 'hourly'
  int hoursPerDay; // e.g. 4

  _ShiftModel({
    this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.priceMonthly,
    this.price3Month,
    this.price6Month,
    required this.trialDays,
    this.shiftType = 'fixed',
    this.hoursPerDay = 4,
  });

  Map<String, dynamic> toMap(String libraryId) {
    final startStr = '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}:00';
    final endStr   = '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}:00';
    return {
      'library_id': libraryId,
      'name': name,
      'start_time': startStr,
      'end_time': endStr,
      'price_monthly': priceMonthly,
      'price_3month': price3Month,
      'price_6month': price6Month,
      'trial_days': trialDays,
      'shift_type': shiftType,
      'hours_per_day': hoursPerDay,
    };
  }
}

class _LibrarySetupStage3ScreenState extends State<LibrarySetupStage3Screen> {
  static const _orange = Color(0xFFE65C00);
  static const _bg = Color(0xFFFBF5EE);
  static const _dark = Color(0xFF1A1A2E);
  static const _grey = Color(0xFF6B7280);

  bool _isLoading = false;
  String? _libraryId;

  // ── Shifts ────────────────────────────────────────────────────────────────
  final List<_ShiftModel> _shifts = [];

  // ── Payment Options ───────────────────────────────────────────────────────
  bool _cashEnabled = true;
  final List<String> _upiIds = [];
  final TextEditingController _upiInputCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _upiInputCtrl.dispose();
    super.dispose();
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;

    if (user != null) {
      try {
        final libData = await sb.from('libraries').select().eq('owner_id', user.id).maybeSingle();
        if (libData != null) {
          _libraryId = libData['id'];

          // Load shifts
          final shiftData = await sb.from('shifts').select().eq('library_id', _libraryId!).eq('is_archived', false);
          if ((shiftData as List).isNotEmpty) {
            _shifts.clear();
            for (final s in shiftData) {
              final startStr = s['start_time'] as String? ?? '08:00';
              final endStr = s['end_time'] as String? ?? '17:00';
              final sp = startStr.split(':');
              final ep = endStr.split(':');
              final startHour = sp.isNotEmpty ? (int.tryParse(sp[0]) ?? 8) : 8;
              final startMinute = sp.length > 1 ? (int.tryParse(sp[1]) ?? 0) : 0;
              final endHour = ep.isNotEmpty ? (int.tryParse(ep[0]) ?? 17) : 17;
              final endMinute = ep.length > 1 ? (int.tryParse(ep[1]) ?? 0) : 0;
              _shifts.add(_ShiftModel(
                id: s['id'],
                name: s['name'] ?? '',
                startTime: TimeOfDay(hour: startHour.clamp(0, 23), minute: startMinute.clamp(0, 59)),
                endTime: TimeOfDay(hour: endHour.clamp(0, 23), minute: endMinute.clamp(0, 59)),
                priceMonthly: s['price_monthly'] ?? 0,
                price3Month: s['price_3month'],
                price6Month: s['price_6month'],
                trialDays: s['trial_days'] ?? 0,
                shiftType: s['shift_type'] ?? 'fixed',
                hoursPerDay: s['hours_per_day'] ?? 4,
              ));
            }
          }

          // Load payment settings from social_links column
          final socialLinks = libData['social_links'] as Map<String, dynamic>?;
          if (socialLinks != null) {
            _cashEnabled = socialLinks['cash_enabled'] as bool? ?? true;
            final dynamic rawUpi = socialLinks['upi_ids'];
            if (rawUpi is List) {
              _upiIds.clear();
              _upiIds.addAll(rawUpi.map((e) => e.toString()));
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading shifts/payment: $e');
      }
    }

    // Do not pre-populate default shift so shifts start empty when no DB data exists.

    setState(() => _isLoading = false);
  }

  // ── Snackbars ─────────────────────────────────────────────────────────────

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Shift operations ──────────────────────────────────────────────────────

  void _addNewShift() {
    setState(() {
      _shifts.add(_ShiftModel(
        name: '',
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 17, minute: 0),
        priceMonthly: 0,
        trialDays: 0,
      ));
    });
  }

  void _removeShift(int index) {
    if (_shifts.length <= 1) { _showError('You must keep at least one shift.'); return; }
    setState(() => _shifts.removeAt(index));
  }

  Future<void> _selectTime(int index, bool isStart) async {
    final shift = _shifts[index];
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? shift.startTime : shift.endTime,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _orange, onPrimary: Colors.white, onSurface: _dark),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) shift.startTime = picked;
        else shift.endTime = picked;
      });
    }
  }

  // ── UPI operations ────────────────────────────────────────────────────────

  void _addUpiId() {
    final id = _upiInputCtrl.text.trim();
    if (id.isEmpty) return;
    if (_upiIds.contains(id)) { _showError('This UPI ID is already added.'); return; }
    setState(() {
      _upiIds.add(id);
      _upiInputCtrl.clear();
    });
  }

  void _removeUpiId(String id) => setState(() => _upiIds.remove(id));

  /// Auto-detect payment app from UPI handle suffix
  String _upiAppName(String id) {
    final handle = id.contains('@') ? id.split('@').last.toLowerCase() : '';
    if (handle == 'paytm') return 'Paytm';
    if (['ybl', 'ibl', 'axl'].contains(handle)) return 'PhonePe';
    if (['oksbi', 'okaxis', 'okicici', 'okhdfcbank'].contains(handle)) return 'GPay';
    if (handle == 'upi') return 'BHIM';
    return '';
  }

  IconData _upiAppIcon(String appName) {
    switch (appName) {
      case 'Paytm': return Icons.account_balance_wallet_outlined;
      case 'PhonePe': return Icons.phone_android_outlined;
      case 'GPay': return Icons.g_mobiledata_outlined;
      default: return Icons.qr_code_outlined;
    }
  }

  Color _upiAppColor(String appName) {
    switch (appName) {
      case 'Paytm': return const Color(0xFF00BAF2);
      case 'PhonePe': return const Color(0xFF5F259F);
      case 'GPay': return const Color(0xFF4285F4);
      default: return _grey;
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _handleSave() async {
    if (_libraryId == null) { _showError('Complete Library Basic Details first.'); return; }

    for (final s in _shifts) {
      if (s.name.trim().isEmpty) { _showError('Shift names cannot be empty.'); return; }
      if (s.priceMonthly <= 0) { _showError('Monthly price must be greater than ₹0.'); return; }
    }

    setState(() => _isLoading = true);
    try {
      final sb = Supabase.instance.client;

      // 1. Archive existing shifts
      await sb.from('shifts').update({'is_archived': true}).eq('library_id', _libraryId!);

      // 2. Insert updated shifts
      for (final shift in _shifts) {
        await sb.from('shifts').insert(shift.toMap(_libraryId!));
      }

      // 3. Save payment settings to libraries.social_links
      await sb.from('libraries').update({
        'social_links': {
          'cash_enabled': _cashEnabled,
          'upi_ids': _upiIds,
        },
      }).eq('id', _libraryId!);

      _showSuccess('Shifts & payment options saved successfully! ✓');
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _showError('Error saving: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _orange,
      body: SafeArea(
        top: true,
        child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _orange,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('Shifts & Pay Method Setup',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          centerTitle: true,
        ),
        body: _isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(_orange)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Shifts section ──────────────────────────────────────
                  _buildSectionHeader('Shifts & Pricing Plans'),
                  const SizedBox(height: 12),

                  _shifts.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No shifts added yet. Add at least one shift to continue.',
                              style: GoogleFonts.inter(color: _grey, fontSize: 13, fontStyle: FontStyle.italic),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _shifts.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 16),
                          itemBuilder: (_, index) => _buildShiftCard(index),
                        ),
                  const SizedBox(height: 16),

                  // Add shift button
                  OutlinedButton.icon(
                    onPressed: _addNewShift,
                    icon: const Icon(Icons.add, color: _orange),
                    label: Text('Add New Shift',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: _orange)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _orange),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Payment Options section ─────────────────────────────
                  _buildSectionHeader('Payment Options'),
                  const SizedBox(height: 12),

                  // Cash toggle
                  _buildCashToggleCard(),
                  const SizedBox(height: 12),

                  // UPI IDs
                  _buildUpiIdsCard(),
                  const SizedBox(height: 28),

                  // Save button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _orange,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                        : Text('Save & Finish ✓',
                            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
      ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _orange.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _orange.withAlpha(40)),
      ),
      child: Text(title,
          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: _orange)),
    );
  }

  Widget _buildShiftCard(int index) {
    final shift = _shifts[index];
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Shift ${index + 1}',
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: _orange)),
          if (_shifts.length > 1)
            GestureDetector(
              onTap: () => _removeShift(index),
              child: const Icon(Icons.close, size: 20, color: Color(0xFFEF4444)),
            ),
        ]),
        const SizedBox(height: 12),

        // Shift Name
        Text('Shift Name', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: _grey)),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: shift.name,
          onChanged: (v) => shift.name = v,
          style: GoogleFonts.inter(fontSize: 15, color: _dark),
          decoration: InputDecoration(
            hintText: 'e.g. Morning Shift',
            hintStyle: TextStyle(color: Colors.grey.withOpacity(0.6)),
          ),
        ),
        const SizedBox(height: 16),

        // Plan Type Choice Toggle (Fixed Hours vs Hourly Plan)
        Text('Plan Type', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: _grey)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => shift.shiftType = 'fixed'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: shift.shiftType == 'fixed' ? _orange : const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: shift.shiftType == 'fixed' ? _orange : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Text(
                  'Fixed Hours',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: shift.shiftType == 'fixed' ? Colors.white : _grey,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => shift.shiftType = 'hourly'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: shift.shiftType == 'hourly' ? _orange : const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: shift.shiftType == 'hourly' ? _orange : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Text(
                  'Hourly Plan',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: shift.shiftType == 'hourly' ? Colors.white : _grey,
                  ),
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 16),

        // Conditionally render time pickers or hours counter
        if (shift.shiftType == 'fixed') ...[
          Row(children: [
            Expanded(child: _buildTimePicker('Start Time', shift.startTime, () => _selectTime(index, true))),
            const SizedBox(width: 12),
            Expanded(child: _buildTimePicker('End Time', shift.endTime, () => _selectTime(index, false))),
          ]),
          const SizedBox(height: 16),
        ] else ...[
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hours per day', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: _dark)),
                Text('Maximum daily access limit', style: GoogleFonts.inter(fontSize: 11, color: _grey)),
              ],
            ),
            Row(children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, color: _orange, size: 22),
                onPressed: shift.hoursPerDay > 1 ? () => setState(() => shift.hoursPerDay--) : null,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7F0),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _orange.withOpacity(0.3)),
                ),
                child: Text(
                  '${shift.hoursPerDay} hrs',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: _orange),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: _orange, size: 22),
                onPressed: () => setState(() => shift.hoursPerDay++),
              ),
            ]),
          ]),
          const SizedBox(height: 16),
        ],

        // Pricing
        Text('Pricing Plans', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: _grey)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _buildPriceField('Monthly *', shift.priceMonthly > 0 ? '${shift.priceMonthly}' : '',
              (v) => shift.priceMonthly = int.tryParse(v) ?? 0)),
          const SizedBox(width: 8),
          Expanded(child: _buildPriceField('3-Month', shift.price3Month != null ? '${shift.price3Month}' : '',
              (v) => shift.price3Month = int.tryParse(v))),
          const SizedBox(width: 8),
          Expanded(child: _buildPriceField('6-Month', shift.price6Month != null ? '${shift.price6Month}' : '',
              (v) => shift.price6Month = int.tryParse(v))),
        ]),
        const SizedBox(height: 16),

        // Trial days
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Free Trial Days:', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _dark)),
          Row(children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: _orange, size: 20),
              onPressed: shift.trialDays > 0 ? () => setState(() => shift.trialDays--) : null,
            ),
            Text('${shift.trialDays}',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: _dark)),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: _orange, size: 20),
              onPressed: () => setState(() => shift.trialDays++),
            ),
          ]),
        ]),
      ]),
    );
  }

  Widget _buildTimePicker(String label, TimeOfDay time, VoidCallback onTap) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: _grey)),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(time.format(context), style: GoogleFonts.inter(fontSize: 14, color: _dark)),
            const Icon(Icons.access_time, size: 18, color: _orange),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildPriceField(String label, String initialValue, void Function(String) onChanged) {
    return TextFormField(
      initialValue: initialValue,
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      style: GoogleFonts.inter(fontSize: 14, color: _dark),
      decoration: InputDecoration(
        prefixText: '₹ ',
        labelText: label,
        labelStyle: const TextStyle(fontSize: 11),
        hintText: 'e.g. 700',
        hintStyle: TextStyle(color: Colors.grey.withOpacity(0.6)),
      ),
    );
  }

  // ── Payment cards ─────────────────────────────────────────────────────────

  Widget _buildCashToggleCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Accept Cash Payments',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _dark)),
          const SizedBox(height: 2),
          Text('Members pay in person at the library',
              style: GoogleFonts.inter(fontSize: 12, color: _grey)),
        ])),
        Switch(
          value: _cashEnabled,
          onChanged: (v) => setState(() => _cashEnabled = v),
          activeThumbColor: _orange,
        ),
      ]),
    );
  }

  Widget _buildUpiIdsCard() {
    // Detect unique app names from UPI IDs for icon display
    final detectedApps = <String>{};
    for (final id in _upiIds) {
      final app = _upiAppName(id);
      if (app.isNotEmpty) detectedApps.add(app);
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('UPI IDs', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _dark)),
        const SizedBox(height: 4),
        Text('Members will use these to pay', style: GoogleFonts.inter(fontSize: 12, color: _grey)),
        const SizedBox(height: 14),

        // Input row
        Row(children: [
          Expanded(
            child: TextField(
              controller: _upiInputCtrl,
              style: GoogleFonts.inter(fontSize: 14, color: _dark),
              decoration: InputDecoration(
                hintText: 'e.g. yourname@paytm',
                hintStyle: TextStyle(color: Colors.grey.withOpacity(0.6)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _orange)),
              ),
              onSubmitted: (_) => _addUpiId(),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _addUpiId,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: _orange, borderRadius: BorderRadius.circular(10),
              ),
              child: Text('+ Add', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ]),

        if (_upiIds.isNotEmpty) ...[
          const SizedBox(height: 14),
          // UPI chips list
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _upiIds.map((id) {
              final app = _upiAppName(id);
              return Chip(
                backgroundColor: const Color(0xFFF3F4F6),
                avatar: app.isNotEmpty
                    ? Icon(_upiAppIcon(app), size: 16, color: _upiAppColor(app))
                    : const Icon(Icons.qr_code, size: 16, color: Color(0xFF6B7280)),
                label: Text(id, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () => _removeUpiId(id),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
              );
            }).toList(),
          ),
        ],

        if (detectedApps.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Payment apps detected:', style: GoogleFonts.inter(fontSize: 11, color: _grey)),
          const SizedBox(height: 8),
          Row(children: detectedApps.map((app) => Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _upiAppColor(app).withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: Icon(_upiAppIcon(app), size: 22, color: _upiAppColor(app)),
              ),
              const SizedBox(height: 4),
              Text(app, style: GoogleFonts.inter(fontSize: 10, color: _grey)),
            ]),
          )).toList()),
        ],
      ]),
    );
  }
}
