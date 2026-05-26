import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class PaymentSetupScreen extends StatefulWidget {
  const PaymentSetupScreen({super.key});

  @override
  State<PaymentSetupScreen> createState() => _PaymentSetupScreenState();
}

class _PaymentSetupScreenState extends State<PaymentSetupScreen> {
  bool _isLoading = false;
  String? _libraryId;
  bool _cashEnabled = true;

  final List<String> _upiIds = [];
  final _newUpiController = TextEditingController();

  // Handle detection helper booleans
  bool _hasPaytm = false;
  bool _hasPhonePe = false;
  bool _hasGPay = false;

  @override
  void initState() {
    super.initState();
    _loadPaymentSettings();
  }

  @override
  void dispose() {
    _newUpiController.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentSettings() async {
    setState(() => _isLoading = true);
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user != null) {
      try {
        final libData = await supabase.from('libraries').select().eq('owner_id', user.id).maybeSingle();
        if (libData != null) {
          _libraryId = libData['id'];

          final social = libData['social_links'] as Map<String, dynamic>?;
          if (social != null) {
            _cashEnabled = social['cash_enabled'] ?? true;
            if (social['upi_ids'] != null) {
              _upiIds.clear();
              _upiIds.addAll(List<String>.from(social['upi_ids']));
              _updateDetectedApps();
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading payment settings: $e');
      }
    }
    setState(() => _isLoading = false);
  }

  void _updateDetectedApps() {
    setState(() {
      _hasPaytm = false;
      _hasPhonePe = false;
      _hasGPay = false;

      for (final id in _upiIds) {
        final lower = id.toLowerCase();
        if (lower.contains('@paytm')) {
          _hasPaytm = true;
        }
        if (lower.contains('@ybl') || lower.contains('@axl') || lower.contains('@ibl')) {
          _hasPhonePe = true;
        }
        if (lower.contains('@oksbi') || lower.contains('@okhdfcbank') || lower.contains('@okicici') || lower.contains('@okaxis')) {
          _hasGPay = true;
        }
      }
    });
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: const Color(0xFFE65C00),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _addUpiId() {
    final newId = _newUpiController.text.trim();
    if (newId.isEmpty) return;
    if (!newId.contains('@')) {
      _showErrorSnackBar('Please enter a valid UPI ID (containing @)');
      return;
    }
    if (_upiIds.contains(newId)) {
      _showErrorSnackBar('This UPI ID has already been added.');
      return;
    }
    setState(() {
      _upiIds.add(newId);
      _newUpiController.clear();
      _updateDetectedApps();
    });
  }

  void _removeUpiId(int index) {
    setState(() {
      _upiIds.removeAt(index);
      _updateDetectedApps();
    });
  }

  Future<void> _handleSaveAndFinish() async {
    if (_libraryId == null) {
      _showErrorSnackBar('No library configured yet. Please complete Stage 1.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      // Update social_links inside library table
      await supabase.from('libraries').update({
        'social_links': {
          'cash_enabled': _cashEnabled,
          'upi_ids': _upiIds,
        }
      }).eq('id', _libraryId!);

      _showSuccessSnackBar('Payment settings updated successfully! ✓');
      if (!mounted) return;

      // Pop and return true to indicate success
      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackBar('Error saving payment settings: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
            'Payment Setup',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          centerTitle: true,
        ),
        body: _isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Explanation Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Configure Member Payment Methods',
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Define how students will pay membership fees. You can enable physical cash collections or direct UPI deposits.',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Cash Payment Toggle Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Accept Cash Payments',
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Members pay in person at the front desk.',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF6B7280)),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _cashEnabled,
                          activeColor: const Color(0xFFE65C00),
                          activeTrackColor: const Color(0xFFFFF3ED),
                          inactiveThumbColor: Colors.grey[400],
                          inactiveTrackColor: Colors.grey[200],
                          onChanged: (val) {
                            setState(() {
                              _cashEnabled = val;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // UPI ID Configuration Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your UPI IDs',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Direct bank transfers via QR & UPI.',
                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF6B7280)),
                        ),
                        const SizedBox(height: 16),

                        // Input field for new UPI
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _newUpiController,
                                style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF1A1A2E)),
                                decoration: const InputDecoration(
                                  hintText: 'example@paytm',
                                  prefixIcon: Icon(Icons.account_balance_wallet_outlined, size: 20),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _addUpiId,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFF3ED),
                                  foregroundColor: const Color(0xFFE65C00),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: const BorderSide(color: Color(0xFFE65C00), width: 1),
                                  ),
                                ),
                                child: Text('Add', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 20),

                        // List of added IDs
                        if (_upiIds.isNotEmpty) ...[
                          Text(
                            'Added UPI Addresses:',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 8),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _upiIds.length,
                            separatorBuilder: (context, index) => const Divider(color: Color(0xFFF3F4F6), height: 12),
                            itemBuilder: (context, index) {
                              final id = _upiIds[index];
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.circle, size: 6, color: Color(0xFFE65C00)),
                                      const SizedBox(width: 8),
                                      Text(
                                        id,
                                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E)),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                                    onPressed: () => _removeUpiId(index),
                                  )
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Auto-detected Payment Icons Indicator
                        Text(
                          '💳 Connected Payment Apps (Auto-Detected):',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF9CA3AF)),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            // Paytm Icon Badge
                            _buildAppBadge(
                              label: 'Paytm',
                              isActive: _hasPaytm,
                              activeColor: const Color(0xFF00B9F5),
                            ),
                            const SizedBox(width: 8),
                            // PhonePe Icon Badge
                            _buildAppBadge(
                              label: 'PhonePe',
                              isActive: _hasPhonePe,
                              activeColor: const Color(0xFF5F259F),
                            ),
                            const SizedBox(width: 8),
                            // GPay Icon Badge
                            _buildAppBadge(
                              label: 'Google Pay',
                              isActive: _hasGPay,
                              activeColor: const Color(0xFF34A853),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Save Payment Settings Button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleSaveAndFinish,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                          )
                        : Text('Save Payment Settings', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
      ),
      ),
    );
  }

  Widget _buildAppBadge({
    required String label,
    required bool isActive,
    required Color activeColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? activeColor.withOpacity(0.12) : Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive ? activeColor : Colors.grey[300]!,
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? Icons.check_circle : Icons.circle_outlined,
            size: 13,
            color: isActive ? activeColor : Colors.grey[400],
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isActive ? activeColor : Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}
