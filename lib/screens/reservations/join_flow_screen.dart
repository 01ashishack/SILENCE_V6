import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

class JoinFlowScreen extends StatefulWidget {
  final String libraryId;
  final String? initialShiftId;

  const JoinFlowScreen({
    super.key,
    required this.libraryId,
    this.initialShiftId,
  });

  @override
  State<JoinFlowScreen> createState() => _JoinFlowScreenState();
}

class _JoinFlowScreenState extends State<JoinFlowScreen> {
  int _currentStep = 1; // 1 = Existing member & profile check, 2 = Shift & Plan, 3 = Add-ons, 4 = Payment, 5 = Review
  bool _isLoading = true;
  String? _errorMessage;

  // Static options or fetched data
  Map<String, dynamic>? _library;
  List<Map<String, dynamic>> _shifts = [];
  List<Map<String, dynamic>> _addOns = [];
  Map<String, dynamic>? _userProfile;
  bool _trialEligible = true;

  // Step 1: Existing member & inline profile details
  bool _isExistingMember = false;
  DateTime? _existingJoinDate;
  String? _existingPlanType = 'monthly';
  DateTime? _existingExpiryDate;
  
  final _profileFormKey = GlobalKey<FormState>();
  final TextEditingController _fullNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _nicknameCtrl = TextEditingController();

  // Step 2: Selected shift & Plan
  Map<String, dynamic>? _selectedShift;
  String _selectedPlan = 'monthly'; // 'monthly', '3_month', '6_month', or 'trial'
  
  // Step 3: Selected Add-ons
  final Map<String, bool> _selectedAddOns = {}; // id -> selected

  // Step 4: Payment
  String _paymentMethod = 'cash'; // 'cash' or 'upi'
  final TextEditingController _upiSenderCtrl = TextEditingController();
  File? _proofImageFile;
  bool _isUploadingProof = false;
  String? _proofUrl;

  // Step 5: Review & Submit
  final TextEditingController _referralCtrl = TextEditingController();
  bool _isSubmitting = false;
  bool _submitSuccess = false;
  String? _submittedRequestId;

  @override
  void initState() {
    super.initState();
    _loadJoinDetails();
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _nicknameCtrl.dispose();
    _upiSenderCtrl.dispose();
    _referralCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadJoinDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User authentication missing.');
      }

      // 1. Fetch library details
      final libRes = await supabase
          .from('libraries')
          .select()
          .eq('id', widget.libraryId)
          .maybeSingle();

      if (libRes == null) {
        throw Exception('Library not found.');
      }
      _library = libRes;

      // 2. Fetch active shifts under library
      final shiftsRes = await supabase
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

      // 3. Fetch add-ons available
      final addOnsRes = await supabase
          .from('add_ons')
          .select()
          .eq('library_id', widget.libraryId)
          .eq('active', true);

      _addOns = List<Map<String, dynamic>>.from(addOnsRes);
      for (var addOn in _addOns) {
        _selectedAddOns[addOn['id']] = false;
      }

      // 4. Fetch user profile
      final profileRes = await supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      
      _userProfile = profileRes;
      if (_userProfile != null) {
        _fullNameCtrl.text = _userProfile!['full_name'] ?? '';
        _phoneCtrl.text = _userProfile!['phone'] ?? '';
        _nicknameCtrl.text = _userProfile!['nickname'] ?? '';
      }

      // 5. Check trial eligibility (has user used trial in this library before?)
      final trialCheck = await supabase
          .from('memberships')
          .select()
          .eq('member_id', user.id)
          .eq('library_id', widget.libraryId)
          .eq('status', 'trial')
          .limit(1);
      
      _trialEligible = (trialCheck as List).isEmpty;

    } catch (e) {
      debugPrint('Error loading join flow details: $e');
      _errorMessage = e.toString();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // File picker helper
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
      final supabase = Supabase.instance.client;
      final fileExtension = _proofImageFile!.path.split('.').last;
      final fileName = 'proof_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final path = 'payment_proofs/${supabase.auth.currentUser!.id}/$fileName';

      await supabase.storage.from('silence_assets').upload(
            path,
            _proofImageFile!,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );

      final String publicUrl = supabase.storage.from('silence_assets').getPublicUrl(path);
      _proofUrl = publicUrl;
      return true;
    } catch (e) {
      debugPrint('Error uploading proof photo: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload screenshot: $e')),
      );
      return false;
    } finally {
      setState(() {
        _isUploadingProof = false;
      });
    }
  }

  // Calculate pricing summaries
  double _calculateSelectedPlanPrice() {
    if (_selectedShift == null) return 0;
    if (_selectedPlan == 'trial') return 0;

    switch (_selectedPlan) {
      case '3_month':
        return (_selectedShift!['price_3month'] as int? ?? (_selectedShift!['price_monthly'] * 3)).toDouble();
      case '6_month':
        return (_selectedShift!['price_6month'] as int? ?? (_selectedShift!['price_monthly'] * 6)).toDouble();
      case 'monthly':
      default:
        return (_selectedShift!['price_monthly'] as int? ?? 1200).toDouble();
    }
  }

  double _calculateAddOnsPrice() {
    double total = 0;
    for (var addOn in _addOns) {
      if (_selectedAddOns[addOn['id']] == true) {
        total += (addOn['price'] as int? ?? 0).toDouble();
      }
    }
    return total;
  }

  double _calculateTotalPrice() {
    return _calculateSelectedPlanPrice() + _calculateAddOnsPrice();
  }

  // Submission handler
  Future<void> _submitJoinRequest() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser!;

      // 1. If inline profile was updated, commit to Supabase profile
      final nameStr = _fullNameCtrl.text.trim();
      final phoneStr = _phoneCtrl.text.trim();
      final nickStr = _nicknameCtrl.text.trim();
      
      if (nameStr.isNotEmpty && phoneStr.isNotEmpty) {
        await supabase.from('users').update({
          'full_name': nameStr,
          'phone': phoneStr,
          'nickname': nickStr.isNotEmpty ? nickStr : null,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', user.id);
      }

      // 2. Upload photo proof if UPI
      if (_paymentMethod == 'upi' && _selectedPlan != 'trial') {
        final uploadOk = await _uploadProofImage();
        if (!uploadOk) {
          throw Exception('Payment screenshot upload is required for UPI payments.');
        }
      }

      // 3. Construct join request
      final requestPayload = {
        'member_id': user.id,
        'library_id': widget.libraryId,
        'shift_id': _selectedShift!['id'],
        'plan_type': _selectedPlan,
        'payment_method': _selectedPlan == 'trial' ? 'none' : _paymentMethod,
        'payment_proof_url': _proofUrl,
        'upi_sender_name': _paymentMethod == 'upi' && _selectedPlan != 'trial' ? _upiSenderCtrl.text.trim() : null,
        'existing_member_join_date': _isExistingMember && _existingJoinDate != null 
            ? DateFormat('yyyy-MM-dd').format(_existingJoinDate!) 
            : null,
        'status': 'pending',
      };

      final insertedRes = await supabase
          .from('join_requests')
          .insert(requestPayload)
          .select()
          .single();

      _submittedRequestId = insertedRes['id'];

      // 4. Save optional referral
      final refCode = _referralCtrl.text.trim();
      if (refCode.isNotEmpty) {
        // Find referrer by nickname or profile code if configured
        final referrerRes = await supabase
            .from('users')
            .select('id')
            .eq('nickname', refCode)
            .maybeSingle();

        if (referrerRes != null) {
          await supabase.from('referrals').insert({
            'referrer_member_id': referrerRes['id'],
            'referred_member_id': user.id,
            'library_id': widget.libraryId,
            'referral_code_used': refCode,
            'status': 'pending',
            'reward_days': 3, // Reward 3 days by default
          });
        }
      }

      setState(() {
        _submitSuccess = true;
      });

    } catch (e) {
      debugPrint('Error submitting join request: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit application: $e')),
      );
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBF5EE),
        body: const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00))),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBF5EE),
        appBar: AppBar(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text('Join Flow Error', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_errorMessage!, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13)),
              ],
            ),
          ),
        ),
      );
    }

    if (_submitSuccess) {
      return _buildConfirmationScreen();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFE65C00),
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: const Color(0xFFFBF5EE),
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            foregroundColor: Colors.white,
            title: Text('Join ${_library?['name'] ?? 'Library'}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (_currentStep > 1) {
                  setState(() {
                    _currentStep--;
                  });
                } else {
                  Navigator.pop(context);
                }
              },
            ),
          ),
          body: Column(
            children: [
              _buildProgressHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildCurrentStepForm(),
                ),
              ),
              _buildBottomActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressHeader() {
    final pct = (_currentStep / 5.0).clamp(0.0, 1.0);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Step $_currentStep of 5',
                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[700]),
              ),
              Text(
                '${(pct * 100).toInt()}% Complete',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
              )
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: Colors.grey[200],
              color: const Color(0xFFE65C00),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildBottomActionButtons() {
    final bool isLastStep = _currentStep == 5;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _handleNextClick,
          style: ElevatedButton.styleFrom(
            backgroundColor: isLastStep ? const Color(0xFFE65C00) : const Color(0xFF0F172A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _isSubmitting 
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(
                  isLastStep ? 'Submit Application' : 'Next →',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                ),
        ),
      ),
    );
  }

  void _handleNextClick() {
    if (_currentStep == 1) {
      if (_fullNameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Full Name and Phone Number are required fields.')),
        );
        return;
      }
      setState(() => _currentStep = 2);
    } else if (_currentStep == 2) {
      if (_selectedShift == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a shift to proceed.')),
        );
        return;
      }
      
      // Skip Add-ons step if none exist
      if (_addOns.isEmpty) {
        setState(() => _currentStep = _selectedPlan == 'trial' ? 5 : 4);
      } else {
        setState(() => _currentStep = 3);
      }
    } else if (_currentStep == 3) {
      setState(() => _currentStep = _selectedPlan == 'trial' ? 5 : 4);
    } else if (_currentStep == 4) {
      if (_paymentMethod == 'upi') {
        if (_upiSenderCtrl.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('UPI Sender Name is required to help admin verify.')),
          );
          return;
        }
        if (_proofImageFile == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payment screenshot proof is required for UPI.')),
          );
          return;
        }
      }
      setState(() => _currentStep = 5);
    } else if (_currentStep == 5) {
      _submitJoinRequest();
    }
  }

  // ==========================================
  // STEPS LAYOUT IMPLEMENTATIONS
  // ==========================================
  Widget _buildCurrentStepForm() {
    switch (_currentStep) {
      case 2:
        return _buildStep2ShiftPlan();
      case 3:
        return _buildStep3AddOns();
      case 4:
        return _buildStep4Payment();
      case 5:
        return _buildStep5Review();
      case 1:
      default:
        return _buildStep1ProfileHistory();
    }
  }

  // STEP 1: HISTORY & PROFILE INLINE
  Widget _buildStep1ProfileHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Returning history
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Have you studied here before?',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 12),
              
              InkWell(
                onTap: () => setState(() => _isExistingMember = false),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: !_isExistingMember ? const Color(0xFFE65C00) : Colors.grey[300]!, width: !_isExistingMember ? 1.5 : 1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.radio_button_checked, color: !_isExistingMember ? const Color(0xFFE65C00) : Colors.grey[400]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("No, I'm new", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text("First time studying at SILENCE", style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              
              InkWell(
                onTap: () => setState(() => _isExistingMember = true),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: _isExistingMember ? const Color(0xFFE65C00) : Colors.grey[300]!, width: _isExistingMember ? 1.5 : 1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.radio_button_checked, color: _isExistingMember ? const Color(0xFFE65C00) : Colors.grey[400]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Yes, returning member", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text("I have studied here previously", style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        
        if (_isExistingMember) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Optional History', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                
                Text('Approximate Joining Date', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().subtract(const Duration(days: 30)),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() {
                        _existingJoinDate = picked;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_existingJoinDate == null ? 'Select Date' : DateFormat('dd MMM yyyy').format(_existingJoinDate!)),
                        const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )
        ],

        // 3. Complete Details
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Complete Your Details',
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 12),
              
              TextField(
                controller: _fullNameCtrl,
                decoration: const InputDecoration(labelText: 'Full Name *'),
              ),
              const SizedBox(height: 12),
              
              TextField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone Number (+91) *'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              
              TextField(
                controller: _nicknameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nickname (leaderboard)',
                  hintText: 'Enter a custom tag e.g. rahulstudy',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // STEP 2: SHIFT & PLAN SELECT
  Widget _buildStep2ShiftPlan() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose a Shift',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 10),

        if (_shifts.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Text('No shifts defined in this library. Contact admin.', style: GoogleFonts.inter(color: Colors.grey)),
          )
        else
          ..._shifts.map((s) {
            final isSelected = _selectedShift?['id'] == s['id'];
            return InkWell(
              onTap: () {
                setState(() {
                  _selectedShift = s;
                });
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
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
                          Text(s['name'] ?? 'Shift', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(
                            '${s['start_time']} – ${s['end_time']}',
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                          ),
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
        
        const SizedBox(height: 20),
        Text(
          'Choose Plan',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 10),

        // Free Trial option
        if (_selectedShift != null && (_selectedShift!['trial_days'] as int? ?? 0) > 0 && _trialEligible) ...[
          InkWell(
            onTap: () => setState(() => _selectedPlan = 'trial'),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _selectedPlan == 'trial' ? const Color(0xFFFAF5FF) : Colors.white,
                border: Border.all(
                  color: _selectedPlan == 'trial' ? const Color(0xFF7C3AED) : Colors.purple[100]!,
                  width: _selectedPlan == 'trial' ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    _selectedPlan == 'trial' ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: _selectedPlan == 'trial' ? const Color(0xFF7C3AED) : Colors.grey[400],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🆓 Free Trial', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF7C3AED), fontSize: 13)),
                        Text('${_selectedShift!['trial_days']} days trial period', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: Text('—— or pay now ——', style: TextStyle(color: Colors.grey, fontSize: 12))),
          )
        ],

        // Plan types
        _buildPlanPill('monthly', 'Monthly Plan', '₹${_selectedShift != null ? _selectedShift!['price_monthly'] : 0}'),
        const SizedBox(height: 8),
        _buildPlanPill('3_month', '3-Month Plan', '₹${_selectedShift != null ? (_selectedShift!['price_3month'] ?? (_selectedShift!['price_monthly'] * 3)) : 0}'),
        const SizedBox(height: 8),
        _buildPlanPill('6_month', '6-Month Plan', '₹${_selectedShift != null ? (_selectedShift!['price_6month'] ?? (_selectedShift!['price_monthly'] * 6)) : 0}'),
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

  // STEP 3: ADD-ONS SELECT
  Widget _buildStep3AddOns() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Extra Add-ons',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 4),
        Text(
          'Custom add-ons for your stay (optional)',
          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
        ),
        const SizedBox(height: 16),

        if (_addOns.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Text('No add-ons configured.', style: GoogleFonts.inter(color: Colors.grey)),
          )
        else
          ..._addOns.map((add) {
            final active = _selectedAddOns[add['id']] == true;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: active ? const Color(0xFFE65C00) : Colors.grey[200]!, width: active ? 1.5 : 1),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: active,
                    activeColor: const Color(0xFFE65C00),
                    onChanged: (val) {
                      setState(() {
                        _selectedAddOns[add['id']] = val ?? false;
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(add['name'] ?? 'Add-on', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(
                          'Price: ₹${add['price']}/${add['price_type'] == 'one_time' ? 'one-time' : 'month'}',
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                        ),
                        if ((add['refundable_deposit'] as int? ?? 0) > 0)
                          Text(
                            'Refundable Deposit: ₹${add['refundable_deposit']} 🔄',
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF10B981), fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  )
                ],
              ),
            );
          }),
      ],
    );
  }

  // STEP 4: PAYMENT PAGE
  Widget _buildStep4Payment() {
    final double subPlan = _calculateSelectedPlanPrice();
    final double subAdd = _calculateAddOnsPrice();
    final double grandTotal = _calculateTotalPrice();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Price breakdown
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Payment Summary', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold)),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Shift & Plan', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600])),
                  Text('₹$subPlan', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
              if (subAdd > 0) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Select Add-ons', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600])),
                    Text('+₹$subAdd', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Grand Total', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                  Text('₹$grandTotal', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        Text(
          'Select Payment Method',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 10),

        _buildPaymentMethodOption('cash', '💵 Cash Payment', 'Pay the total amount in cash directly at the library.'),
        const SizedBox(height: 8),
        _buildPaymentMethodOption('upi', '📱 UPI / Online Transfer', 'Pay securely using GPay, PhonePe or other UPI apps.'),

        if (_paymentMethod == 'upi') ...[
          const SizedBox(height: 20),
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
                  style: GoogleFonts.monospace(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.bold),
                ),
                const Divider(height: 24),
                
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
                const Divider(height: 24),
                
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
        ],
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
        child: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // STEP 5: REVIEW & SUBMIT
  Widget _buildStep5Review() {
    final double subPlan = _calculateSelectedPlanPrice();
    final double subAdd = _calculateAddOnsPrice();
    final double grandTotal = _calculateTotalPrice();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Review Your Application',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildReviewRow('Library', _library?['name'] ?? 'SILENCE Study Zone'),
              const Divider(height: 20),
              _buildReviewRow('Selected Shift', _selectedShift?['name'] ?? 'Morning'),
              const Divider(height: 20),
              _buildReviewRow('Plan type', _selectedPlan == 'trial' ? '🆓 Free Trial' : '${_selectedPlan == 'monthly' ? 'Monthly' : _selectedPlan == '3_month' ? '3-Month' : '6-Month'} plan'),
              const Divider(height: 20),
              _buildReviewRow('Payment method', _selectedPlan == 'trial' ? 'Trial (Skip payment)' : _paymentMethod == 'cash' ? 'Cash at Library' : 'UPI transfer'),
              
              if (_paymentMethod == 'upi' && _selectedPlan != 'trial') ...[
                const Divider(height: 20),
                _buildReviewRow('UPI Sender Name', _upiSenderCtrl.text),
              ],
              
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Grand Total', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                  Text('₹$grandTotal', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        Text('Referral Code', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: _referralCtrl,
          decoration: const InputDecoration(
            labelText: 'Referral Nickname (optional)',
            hintText: 'e.g. rahulstudy',
          ),
        ),
      ],
    );
  }

  Widget _buildReviewRow(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
        const SizedBox(height: 2),
        Text(val, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
      ],
    );
  }

  // ==========================================
  // CONFIRMATION SCREEN
  // ==========================================
  Widget _buildConfirmationScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF5EE),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: const Color(0xFFE65C00).withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.assignment_turned_in, size: 64, color: Color(0xFFE65C00)),
              ),
              const SizedBox(height: 24),
              Text(
                'Application Submitted!',
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 12),
              Text(
                'Your payment screenshot is under review by our admin. We typically verify and confirm spaces within 24 hours.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600], height: 1.5),
              ),
              const SizedBox(height: 16),
              
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber[200]!)),
                child: Text(
                  'Status: Review Pending',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFD97706)),
                ),
              ),
              
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Go to Home'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
