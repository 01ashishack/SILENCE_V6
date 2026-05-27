import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        _libId = widget.libraryId;
        if (_libId == null) {
          final libRes = await _supabase.from('libraries').select('id').eq('owner_id', user.id).maybeSingle();
          if (libRes != null) {
            _libId = libRes['id'];
          }
        }

        final prefs = await SharedPreferences.getInstance();
        _discountController.text = prefs.getString('rules_discount_${_libId ?? "default"}') ?? '15';
        _graceDaysController.text = prefs.getString('rules_grace_${_libId ?? "default"}') ?? '3';
        _holdDurationController.text = prefs.getString('rules_hold_duration_${_libId ?? "default"}') ?? '15';
        _holdCountController.text = prefs.getString('rules_hold_count_${_libId ?? "default"}') ?? '2';
        _allowExpiredCheckIn = prefs.getBool('rules_allow_expired_checkin_${_libId ?? "default"}') ?? false;

        // Optionally fetch from supabase libraries metadata/rules field if it exists
        if (_libId != null) {
          final libData = await _supabase.from('libraries').select('rules_metadata').eq('id', _libId!).maybeSingle();
          if (libData != null && libData['rules_metadata'] != null) {
            final rules = Map<String, dynamic>.from(libData['rules_metadata']);
            _discountController.text = rules['max_discount']?.toString() ?? _discountController.text;
            _graceDaysController.text = rules['grace_days']?.toString() ?? _graceDaysController.text;
            _holdDurationController.text = rules['max_hold_days']?.toString() ?? _holdDurationController.text;
            _holdCountController.text = rules['max_holds']?.toString() ?? _holdCountController.text;
            _allowExpiredCheckIn = rules['allow_expired_checkin'] ?? _allowExpiredCheckIn;
          }
        }
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rules_discount_${_libId ?? "default"}', _discountController.text);
      await prefs.setString('rules_grace_${_libId ?? "default"}', _graceDaysController.text);
      await prefs.setString('rules_hold_duration_${_libId ?? "default"}', _holdDurationController.text);
      await prefs.setString('rules_hold_count_${_libId ?? "default"}', _holdCountController.text);
      await prefs.setBool('rules_allow_expired_checkin_${_libId ?? "default"}', _allowExpiredCheckIn);

      if (_libId != null) {
        final rulesMap = {
          'max_discount': int.tryParse(_discountController.text) ?? 15,
          'grace_days': int.tryParse(_graceDaysController.text) ?? 3,
          'max_hold_days': int.tryParse(_holdDurationController.text) ?? 15,
          'max_holds': int.tryParse(_holdCountController.text) ?? 2,
          'allow_expired_checkin': _allowExpiredCheckIn,
        };

        try {
          await _supabase.from('libraries').update({
            'rules_metadata': rulesMap,
          }).eq('id', _libId!);
        } catch (_) {}
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business rules saved successfully! ✓'), backgroundColor: Color(0xFFE65C00)),
      );
      Navigator.pop(context);
    } catch (e) {
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
          backgroundColor: const Color(0xFFFBF5EE),
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
                            color: Colors.white,
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
                                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Max Discount Cap (%)',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
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
                            color: Colors.white,
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
                                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Payment Expiry Grace Days',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
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
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
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
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
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
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Allow Check-in after Expiry',
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                            ),
                            subtitle: Text(
                              'If disabled, scanner will block entries immediately when a plan ends.',
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                            ),
                            value: _allowExpiredCheckIn,
                            activeColor: const Color(0xFFE65C00),
                            onChanged: (val) {
                              setState(() => _allowExpiredCheckIn = val);
                            },
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
