import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/image_optimizer.dart';

class RenewalScreen extends StatefulWidget {
  final String libraryId;
  final String? initialPlan; // 'monthly', '3_month', '6_month'
  final String? initialShiftId;

  const RenewalScreen({
    super.key,
    required this.libraryId,
    this.initialPlan,
    this.initialShiftId,
  });

  @override
  State<RenewalScreen> createState() => _RenewalScreenState();
}

class _RenewalScreenState extends State<RenewalScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _errorMessage;

  // Fetched data
  Map<String, dynamic>? _library;
  List<Map<String, dynamic>> _shifts = [];
  Map<String, dynamic>? _userProfile;

  // Selected values
  Map<String, dynamic>? _selectedShift;
  late String _selectedPlan;

  // Payment inputs
  String _paymentMethod = 'cash'; // 'cash' or 'upi'
  final TextEditingController _upiSenderCtrl = TextEditingController();
  File? _proofImageFile;
  bool _isUploadingProof = false;
  String? _proofUrl;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedPlan = widget.initialPlan ?? 'monthly';
    _loadDetails();
  }

  @override
  void dispose() {
    _upiSenderCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User authentication missing.');
      }

      // 1. Fetch library details
      final libRes = await _supabase
          .from('libraries')
          .select()
          .eq('id', widget.libraryId)
          .maybeSingle();

      if (libRes == null) {
        throw Exception('Library not found.');
      }
      _library = libRes;

      // 2. Fetch active shifts
      final shiftsRes = await _supabase
          .from('shifts')
          .select()
          .eq('library_id', widget.libraryId)
          .eq('is_archived', false);
      
      _shifts = List<Map<String, dynamic>>.from(shiftsRes);

      if (widget.initialShiftId != null && _shifts.isNotEmpty) {
        _selectedShift = _shifts.firstWhere(
          (s) => s['id'] == widget.initialShiftId,
          orElse: () => _shifts.first,
        );
      } else if (_shifts.isNotEmpty) {
        _selectedShift = _shifts.first;
      }

      // 3. Fetch user profile
      final profileRes = await _supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      _userProfile = profileRes;

    } catch (e) {
      debugPrint('Error loading renewal details: $e');
      _errorMessage = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickProofImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _proofImageFile = File(image.path);
    });
  }

  Future<bool> _uploadProofImage() async {
    if (_proofImageFile == null) return false;
    setState(() {
      _isUploadingProof = true;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;
      final fileName = 'proof_renewal_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = 'payment_proofs/${user.id}/$fileName';

      final bytes = await ImageOptimizer.compressImage(_proofImageFile!.path);
      await _supabase.storage.from('silence_assets').uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              cacheControl: '3600',
              upsert: true,
            ),
          );

      final String publicUrl = _supabase.storage.from('silence_assets').getPublicUrl(path);
      _proofUrl = publicUrl;
      return true;
    } catch (e) {
      debugPrint('Error uploading proof photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload screenshot: $e')),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingProof = false;
        });
      }
    }
  }

  double _calculateSelectedPlanPrice() {
    final shift = _selectedShift;
    if (shift == null) return 0;

    switch (_selectedPlan) {
      case '3_month':
        return (shift['price_3month'] as int? ?? ((shift['price_monthly'] as int? ?? 0) * 3)).toDouble();
      case '6_month':
        return (shift['price_6month'] as int? ?? ((shift['price_monthly'] as int? ?? 0) * 6)).toDouble();
      case 'monthly':
      default:
        return (shift['price_monthly'] as int? ?? 1200).toDouble();
    }
  }

  Future<void> _submitRenewalRequest() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Check existing pending requests to prevent duplicate submission
      final existingReq = await _supabase
          .from('join_requests')
          .select('id')
          .eq('member_id', user.id)
          .eq('library_id', widget.libraryId)
          .eq('status', 'pending')
          .maybeSingle();

      if (existingReq != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You already have a pending join or renewal request under review.')),
          );
        }
        return;
      }

      // If payment is UPI, upload proof image
      if (_paymentMethod == 'upi') {
        if (_proofImageFile == null) {
          throw Exception('Payment screenshot upload is required for UPI payments.');
        }
        final uploadOk = await _uploadProofImage();
        if (!uploadOk) {
          throw Exception('Screenshot upload failed. Please try again.');
        }
      }

      final shift = _selectedShift;
      if (shift == null) {
        throw Exception('Please select a shift first.');
      }

      // Insert join_request as a renewal request
      final requestPayload = {
        'member_id': user.id,
        'library_id': widget.libraryId,
        'shift_id': shift['id'],
        'plan_type': _selectedPlan,
        'payment_method': _paymentMethod,
        'payment_proof_url': _proofUrl,
        'upi_sender_name': _paymentMethod == 'upi' ? _upiSenderCtrl.text.trim() : null,
        'status': 'pending',
      };

      await _supabase.from('join_requests').insert(requestPayload);

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text('Request Submitted! 🎉', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            content: Text(
              'Your renewal request has been submitted successfully and is pending admin approval.',
              style: GoogleFonts.inter(),
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx); // Close dialog
                  Navigator.pop(context, true); // Return success to home
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        );
      }

    } catch (e) {
      debugPrint('Error submitting renewal: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
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
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text('Renew Membership', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
              : _errorMessage != null
                  ? _buildErrorView()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildLibrarySummaryCard(),
                          const SizedBox(height: 20),
                          _buildShiftSelect(),
                          const SizedBox(height: 20),
                          _buildPlanSelect(),
                          const SizedBox(height: 20),
                          _buildPaymentSection(),
                          const SizedBox(height: 32),
                          _buildSubmitButton(),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text('Error Loading Details', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_errorMessage ?? 'Unknown error', textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.grey[600])),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadDetails,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
              child: const Text('Retry'),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildLibrarySummaryCard() {
    final libName = _library?['name'] ?? 'SILENCE Library';
    final address = _library?['address_city'] ?? 'Jaipur';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF3ED), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.business, color: Color(0xFFE65C00), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(libName, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                const SizedBox(height: 2),
                Text(address, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildShiftSelect() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Shift', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
        const SizedBox(height: 10),
        if (_shifts.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Text('No shifts available', style: GoogleFonts.inter(color: Colors.grey)),
          )
        else
          ..._shifts.map((s) {
            final isSelected = _selectedShift?['id'] == s['id'];
            return InkWell(
              onTap: () => setState(() => _selectedShift = s),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                    color: isSelected ? const Color(0xFFE65C00) : Colors.grey[300]!,
                    width: isSelected ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: isSelected ? const Color(0xFFE65C00) : Colors.grey[400],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s['name'] ?? 'Shift', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('${s['start_time']} – ${s['end_time']}', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                    Text(
                      '₹${s['price_monthly']}/mo',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFFE65C00)),
                    )
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildPlanSelect() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Plan Duration', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
        const SizedBox(height: 10),
        _buildPlanPill('monthly', 'Monthly Plan', '₹${_selectedShift != null ? (_selectedShift!['price_monthly'] ?? 0) : 0}'),
        const SizedBox(height: 8),
        _buildPlanPill('3_month', '3-Month Plan', '₹${_selectedShift != null ? (_selectedShift!['price_3month'] ?? ((_selectedShift!['price_monthly'] as int? ?? 0) * 3)) : 0}'),
        const SizedBox(height: 8),
        _buildPlanPill('6_month', '6-Month Plan', '₹${_selectedShift != null ? (_selectedShift!['price_6month'] ?? ((_selectedShift!['price_monthly'] as int? ?? 0) * 6)) : 0}'),
      ],
    );
  }

  Widget _buildPlanPill(String planKey, String label, String priceLabel) {
    final isSelected = _selectedPlan == planKey;
    return InkWell(
      onTap: () => setState(() => _selectedPlan = planKey),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: isSelected ? const Color(0xFFE65C00) : Colors.grey[300]!, width: isSelected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: isSelected ? const Color(0xFFE65C00) : Colors.grey[400],
                ),
                const SizedBox(width: 12),
                Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            Text(priceLabel, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B))),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSection() {
    final total = _calculateSelectedPlanPrice();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Grand Total', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
              Text('₹$total', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Select Payment Method', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
        const SizedBox(height: 10),
        _buildPaymentMethodOption('cash', '💵 Cash Payment', 'Pay the total amount in cash directly at the library.'),
        const SizedBox(height: 8),
        _buildPaymentMethodOption('upi', '📱 UPI / Online Transfer', 'Pay securely using GPay, PhonePe or other UPI apps.'),
        if (_paymentMethod == 'upi') ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Admin UPI IDs', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                const SizedBox(height: 4),
                SelectableText(
                  'owner@upi\n9876543210@paytm',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.bold),
                ),
                const Divider(height: 20),
                Text('Deep-link Payment Apps:', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildPaymentAppButton('GPay', Colors.blue),
                    const SizedBox(width: 8),
                    _buildPaymentAppButton('PhonePe', Colors.purple),
                    const SizedBox(width: 8),
                    _buildPaymentAppButton('Paytm', Colors.lightBlue),
                  ],
                ),
                const Divider(height: 20),
                Text('Upload Screenshot *', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickProofImage,
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey[50],
                    ),
                    alignment: Alignment.center,
                    child: _proofImageFile != null
                        ? Image.file(_proofImageFile!, fit: BoxFit.contain)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cloud_upload_outlined, size: 32, color: Colors.grey[400]),
                              const SizedBox(height: 6),
                              Text('Tap to select screenshot from gallery', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600])),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _upiSenderCtrl,
                  decoration: const InputDecoration(
                    labelText: 'UPI Sender Name *',
                    hintText: 'Enter name used while transferring',
                  ),
                ),
              ],
            ),
          )
        ]
      ],
    );
  }

  Widget _buildPaymentMethodOption(String key, String label, String desc) {
    final isSelected = _paymentMethod == key;
    return InkWell(
      onTap: () => setState(() => _paymentMethod = key),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: isSelected ? const Color(0xFFE65C00) : Colors.grey[300]!, width: isSelected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? const Color(0xFFE65C00) : Colors.grey[400],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(desc, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentAppButton(String label, Color color) {
    return Expanded(
      child: ElevatedButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Simulated deep link: Opening $label app...')),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.1),
          foregroundColor: color,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return ElevatedButton(
      onPressed: (_isSubmitting || _isUploadingProof) ? null : _submitRenewalRequest,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFE65C00),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: _isSubmitting
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          : Text('Submit Renewal Request', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }
}
