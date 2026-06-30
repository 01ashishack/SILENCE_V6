import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/admin_settings_service.dart';
import '../core/active_library_store.dart';

class BusinessRulesScreen extends StatefulWidget {
  final String? libraryId;
  const BusinessRulesScreen({super.key, this.libraryId});

  @override
  State<BusinessRulesScreen> createState() => _BusinessRulesScreenState();
}

class _BusinessRulesScreenState extends State<BusinessRulesScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _libId;

  // Rule controllers
  final _discountController = TextEditingController(text: '15');
  final _graceDaysController = TextEditingController(text: '3');
  final _holdDurationController = TextEditingController(text: '15');
  final _holdCountController = TextEditingController(text: '2');
  bool _allowExpiredCheckIn = false;
  bool _requireOutOfShiftApproval = true; // out-of-shift check-in needs admin OK

  @override
  void initState() {
    super.initState();
    _fetchRules();
  }

  Future<void> _fetchRules() async {
    setState(() => _isLoading = true);
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        _libId = await ActiveLibraryStore.resolve(widget.libraryId);

        final storedRules = await AdminSettingsService.load(
          scope: 'business_rules',
          libraryId: _libId,
        );
        _discountController.text = storedRules['max_discount']?.toString() ?? '15';
        _graceDaysController.text = storedRules['grace_days']?.toString() ?? '3';
        _holdDurationController.text = storedRules['max_hold_days']?.toString() ?? '15';
        _holdCountController.text = storedRules['max_holds']?.toString() ?? '2';
        _allowExpiredCheckIn = storedRules['allow_expired_checkin'] as bool? ?? false;
        _requireOutOfShiftApproval = storedRules['require_outofshift_approval'] as bool? ?? true;

        // Business rules are loaded from AdminSettingsService (settings table)
      } catch (e) {
        debugPrint('Error loading business rules: $e');
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveRules() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final rulesMap = {
        'max_discount': int.tryParse(_discountController.text) ?? 15,
        'grace_days': int.tryParse(_graceDaysController.text) ?? 3,
        'max_hold_days': int.tryParse(_holdDurationController.text) ?? 15,
        'max_holds': int.tryParse(_holdCountController.text) ?? 2,
        'allow_expired_checkin': _allowExpiredCheckIn,
        'require_outofshift_approval': _requireOutOfShiftApproval,
      };

      await AdminSettingsService.save(
        scope: 'business_rules',
        libraryId: _libId,
        value: rulesMap,
      );

      // Business rules are saved to AdminSettingsService (settings table)

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business rules saved successfully! ✓'), backgroundColor: Color(0xFFE65C00)),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving rules: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE65C00),
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: context.palette.scaffold,
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Business & Conduct Rules',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          body: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
              : Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. General Rules Card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: context.palette.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.rule_folder, color: Color(0xFFE65C00), size: 20),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Membership Discounts',
                                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Max Discount Cap (%)',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _discountController,
                                keyboardType: TextInputType.number,
                                style: GoogleFonts.inter(fontSize: 14),
                                decoration: const InputDecoration(
                                  hintText: 'Enter discount cap (e.g. 15%)',
                                  suffixText: '%',
                                ),
                                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 2. Attendance & Expiry Card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: context.palette.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.hourglass_empty, color: Color(0xFFE65C00), size: 20),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Grace Periods & Holds',
                                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Payment Expiry Grace Days',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _graceDaysController,
                                keyboardType: TextInputType.number,
                                style: GoogleFonts.inter(fontSize: 14),
                                decoration: const InputDecoration(hintText: 'Enter days before account suspension'),
                                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Max Seat Hold Duration (Days)',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _holdDurationController,
                                keyboardType: TextInputType.number,
                                style: GoogleFonts.inter(fontSize: 14),
                                decoration: const InputDecoration(hintText: 'Enter max hold days per calendar year'),
                                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Max Free Holds Per Member',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _holdCountController,
                                keyboardType: TextInputType.number,
                                style: GoogleFonts.inter(fontSize: 14),
                                decoration: const InputDecoration(hintText: 'Enter max number of holds'),
                                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 3. System Permissions
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.palette.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Allow Check-in after Expiry',
                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                                ),
                                subtitle: Text(
                                  'If disabled, scanner will block entries immediately when a plan ends.',
                                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                                ),
                                value: _allowExpiredCheckIn,
                                activeThumbColor: const Color(0xFFE65C00),
                                onChanged: (val) {
                                  setState(() => _allowExpiredCheckIn = val);
                                },
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Require approval for out-of-shift check-in',
                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                                ),
                                subtitle: Text(
                                  'If ON, a member checking in outside their shift hours needs your approval (you get a notification). If OFF, out-of-shift check-ins are allowed directly and counted as overtime.',
                                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                                ),
                                value: _requireOutOfShiftApproval,
                                activeThumbColor: const Color(0xFFE65C00),
                                onChanged: (val) {
                                  setState(() => _requireOutOfShiftApproval = val);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // 4. Save Button
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE65C00),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          onPressed: _saveRules,
                          child: Text(
                            'Save Rules & Config',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
