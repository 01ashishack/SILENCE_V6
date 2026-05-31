import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/member_draft.dart';
import '../../models/member_data.dart';
import '../../services/draft_service.dart';
import '../../core/image_optimizer.dart';
import 'add_member_step1.dart';
import 'add_member_step2.dart';
import 'add_member_step3.dart';
import 'add_member_step4.dart';
import 'add_member_step5.dart';

class AddMemberWizard extends StatefulWidget {
  const AddMemberWizard({super.key});

  @override
  State<AddMemberWizard> createState() => _AddMemberWizardState();
}

class _AddMemberWizardState extends State<AddMemberWizard> {
  final _supabase = Supabase.instance.client;
  final _pageController = PageController();
  int _currentStep = 0;
  bool _isLoading = false;
  bool _initialized = false;

  late String _libraryId;
  String? _libraryName;
  String? _draftId;

  // Single Model instance containing all step data
  final MemberData _memberData = MemberData();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      _libraryId = args['libraryId'] as String;
      _draftId = args['draftId'] as String?;

      _fetchLibraryName();

      if (_draftId != null) {
        _loadDraft(_draftId!);
      } else {
        // Show mode selection bottom sheet
        WidgetsBinding.instance.addPostFrameCallback((_) => _showModeSelectionSheet());
      }
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetchLibraryName() async {
    try {
      final res = await _supabase.from('libraries').select('name').eq('id', _libraryId).maybeSingle();
      if (res != null && mounted) {
        setState(() {
          _libraryName = res['name'] as String?;
        });
      }
    } catch (e) {
      debugPrint('Error fetching library name: $e');
    }
  }

  Future<void> _loadDraft(String draftId) async {
    setState(() => _isLoading = true);
    try {
      final drafts = await DraftService.instance.getDrafts(_libraryId);
      final draft = drafts.firstWhere((d) => d.id == draftId);
      final data = draft.draftData;

      setState(() {
        _memberData.fromJson(data);
      });
    } catch (e) {
      debugPrint('Error loading draft: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load draft: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showModeSelectionSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          Navigator.pop(context); // Close the wizard if selector dismissed
        },
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose Registration Mode',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Select standard mode or pre-existing member mode to configure registration options.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey[200]!),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0FDF4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_add_alt_1, color: Colors.green),
                ),
                title: Text(
                  'New Member',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B)),
                ),
                subtitle: Text(
                  'Standard flow (trial days allowed, digital payment requests allowed).',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                ),
                onTap: () {
                  setState(() {
                    _memberData.mode = 'new';
                    _memberData.paymentFlow = 'paid';
                  });
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey[200]!),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEFF6FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.history, color: Colors.blue),
                ),
                title: Text(
                  'Existing Member',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B)),
                ),
                subtitle: Text(
                  'Already studying at the library. Past joining date required. No trials, immediate cash/UPI payment.',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                ),
                onTap: () {
                  setState(() {
                    _memberData.mode = 'existing';
                    _memberData.paymentFlow = 'paid';
                  });
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveAsDraft() async {
    setState(() => _isLoading = true);
    try {
      final admin = _supabase.auth.currentUser;
      if (admin == null) throw Exception('No active admin session found.');

      final draft = MemberDraft(
        id: _draftId,
        adminId: admin.id,
        libraryId: _libraryId,
        draftData: _memberData.toJson(),
      );

      await DraftService.instance.saveDraft(draft);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration draft saved successfully ✓')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving draft: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save draft: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showExitDraftPrompt() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Exit Wizard?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
        content: Text(
          'Do you want to save this member registration as a draft to resume later?',
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // Close dialog
              Navigator.pop(context); // Pop wizard without saving
            },
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // Close dialog
            },
            child: const Text('Keep Editing'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx); // Close dialog
              _saveAsDraft();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), elevation: 0),
            child: const Text('Save Draft', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  bool _validateStep() {
    if (_currentStep == 0) {
      if (_memberData.name.isEmpty) {
        _showErrorSnackBar('Full Name is required.');
        return false;
      }
      if (_memberData.phone.length != 10) {
        _showErrorSnackBar('Contact number must be exactly 10 digits.');
        return false;
      }
      if (_memberData.dob == null) {
        _showErrorSnackBar('Date of birth is required.');
        return false;
      }
      if (_memberData.gender == null) {
        _showErrorSnackBar('Gender is required.');
        return false;
      }
      if (_memberData.address.isEmpty) {
        _showErrorSnackBar('Correspondence address is required.');
        return false;
      }
      if (_memberData.preparingFor == null) {
        _showErrorSnackBar('Preparing For field is required.');
        return false;
      }
      if (_memberData.idProof1File == null && _memberData.idProof2File == null) {
        _showErrorSnackBar('At least one ID proof document is required.');
        return false;
      }
    } else if (_currentStep == 1) {
      if (_memberData.selectedShiftId == null) {
        _showErrorSnackBar('Please configure and select a shift.');
        return false;
      }
      if (_memberData.mode == 'existing' && _memberData.planStartDate == null) {
        _showErrorSnackBar('Plan start date is required for existing members.');
        return false;
      }
    } else if (_currentStep == 2) {
      if (_memberData.selectedSeatId == null) {
        _showErrorSnackBar('Please allot a seat to proceed.');
        return false;
      }
    }
    return true;
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
        backgroundColor: Colors.red[600],
      ),
    );
  }

  DateTime get _calculatedPlanStart {
    if (_memberData.mode == 'existing') {
      return _memberData.planStartDate ?? _memberData.joiningDate;
    } else {
      if (_memberData.customPlanStart && _memberData.planStartDate != null) {
        return _memberData.planStartDate!;
      }
      return _memberData.joiningDate.add(Duration(days: _memberData.trialDays));
    }
  }

  DateTime get _calculatedExpiry {
    final start = _calculatedPlanStart;
    int durationMonths = 1;
    if (_memberData.planType == '3_month') durationMonths = 3;
    if (_memberData.planType == '6_month') durationMonths = 6;
    return DateTime(start.year, start.month + durationMonths, start.day);
  }

  Future<String?> _uploadFileToStorage(File file, String subFolder) async {
    final bytes = await ImageOptimizer.compressImage(file.path);
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last.split('\\').last}';
    final path = 'library_members/$_libraryId/$subFolder/$fileName';

    try {
      await _supabase.storage.createBucket('silence_assets', const BucketOptions(public: true));
    } catch (_) {}

    await _supabase.storage.from('silence_assets').uploadBinary(
      path,
      Uint8List.fromList(bytes),
      fileOptions: const FileOptions(
        contentType: 'image/jpeg',
        upsert: true,
      ),
    );

    return _supabase.storage.from('silence_assets').getPublicUrl(path);
  }

  Future<String?> _uploadProfilePhoto(File file, String memberId) async {
    final bytes = await ImageOptimizer.compressImage(file.path);
    final path = 'member_profiles/$memberId/profile.jpg';

    try {
      await _supabase.storage.createBucket('silence_private', const BucketOptions(public: false));
    } catch (_) {}

    await _supabase.storage.from('silence_private').uploadBinary(
      path,
      Uint8List.fromList(bytes),
      fileOptions: const FileOptions(
        contentType: 'image/jpeg',
        upsert: true,
      ),
    );

    return _supabase.storage.from('silence_private').getPublicUrl(path);
  }

  Future<void> _finalizeRegistration() async {
    setState(() => _isLoading = true);
    try {
      // 1. Look up or insert user
      var userObj = await _supabase
          .from('users')
          .select('id')
          .eq('phone', _memberData.phone)
          .maybeSingle();

      String memberUserId;
      if (userObj == null) {
        final newU = await _supabase.from('users').insert({
          'full_name': _memberData.name,
          'nickname': _memberData.name.split(' ').first,
          'phone': _memberData.phone,
          'email': _memberData.email.isEmpty ? null : _memberData.email,
          'gender': _memberData.gender,
          'date_of_birth': _memberData.dob?.toIso8601String().substring(0, 10),
          'address': _memberData.address,
          'exam_category': _memberData.preparingFor,
          'role': 'member',
        }).select('id').single();
        memberUserId = newU['id'] as String;
      } else {
        memberUserId = userObj['id'] as String;
        await _supabase.from('users').update({
          'full_name': _memberData.name,
          'email': _memberData.email.isEmpty ? null : _memberData.email,
          'gender': _memberData.gender,
          'date_of_birth': _memberData.dob?.toIso8601String().substring(0, 10),
          'address': _memberData.address,
          'exam_category': _memberData.preparingFor,
        }).eq('id', memberUserId);
      }

      // 2. Upload profile photo to silence_privatebucket
      String? photoUrl;
      if (_memberData.profilePhoto != null) {
        photoUrl = await _uploadProfilePhoto(_memberData.profilePhoto!, memberUserId);
        await _supabase.from('users').update({
          'photo_url': photoUrl,
        }).eq('id', memberUserId);
      }

      // 3. Upload other docs
      String? docUrl;
      if (_memberData.idProof1File != null) {
        docUrl = await _uploadFileToStorage(_memberData.idProof1File!, 'documents');
      } else if (_memberData.idProof2File != null) {
        docUrl = await _uploadFileToStorage(_memberData.idProof2File!, 'documents');
      }

      if (docUrl != null) {
        await _supabase.from('users').update({
          'fcm_token': docUrl,
        }).eq('id', memberUserId);
      }

      // 4. Create membership
      final startStr = _calculatedPlanStart.toIso8601String().substring(0, 10);
      final endStr = _calculatedExpiry.toIso8601String().substring(0, 10);

      final membership = await _supabase.from('memberships').insert({
        'member_id': memberUserId,
        'library_id': _libraryId,
        'shift_id': _memberData.selectedShiftId,
        'seat_id': _memberData.selectedSeatId,
        'plan_type': _memberData.planType,
        'start_date': startStr,
        'end_date': endStr,
        'status': _memberData.paymentFlow == 'paid' ? 'active' : 'pending',
      }).select('id').single();

      final membershipId = membership['id'] as String;

      // 5. Create payment record
      final finalPrice = (_memberData.totalBasePrice - _memberData.discount).clamp(0, double.infinity).toInt();
      await _supabase.from('payments').insert({
        'membership_id': membershipId,
        'member_id': memberUserId,
        'library_id': _libraryId,
        'amount': finalPrice,
        'method': _memberData.paymentFlow == 'paid' ? _memberData.paymentMethod : 'request',
        'status': _memberData.paymentFlow == 'paid' ? 'confirmed' : 'pending',
        'payment_date': DateTime.now().toIso8601String(),
        'confirmed_by_admin_id': _supabase.auth.currentUser?.id,
      });

      // 6. Update seat occupation status
      await _supabase.from('seats').update({
        'status': 'occupied',
        'occupied_by_member_id': memberUserId,
      }).eq('id', _memberData.selectedSeatId!);

      // 7. Delete draft if loaded
      if (_draftId != null) {
        await DraftService.instance.deleteDraft(_draftId!, _libraryId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member registration finalized successfully ✓'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error finalizing registration: $e');
      if (mounted) {
        _showErrorSnackBar('Registration failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_memberData.mode == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBF5EE),
        appBar: AppBar(
          backgroundColor: const Color(0xFFE65C00),
          title: Text('Add Member Wizard', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))),
        ),
      );
    }

    final currentProgress = (_currentStep + 1) / 5.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _showExitDraftPrompt();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFBF5EE),
        appBar: AppBar(
          backgroundColor: const Color(0xFFE65C00),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Member Wizard',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
              Text(
                'Step ${_currentStep + 1} of 5: ${_getStepTitle()}',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            TextButton(
              onPressed: _saveAsDraft,
              child: const Text('Save Draft', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  value: currentProgress,
                  backgroundColor: const Color(0xFFFFEDD5),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
                  minHeight: 4,
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (page) {
                      setState(() {
                        _currentStep = page;
                      });
                    },
                    children: [
                      AddMemberStep1(
                        memberData: _memberData,
                        onAutofillDetails: (user) {
                          setState(() {});
                        },
                      ),
                      AddMemberStep2(
                        libraryId: _libraryId,
                        memberData: _memberData,
                        onTotalAmountChanged: (val) {
                          setState(() {
                            _memberData.totalBasePrice = val;
                          });
                        },
                      ),
                      AddMemberStep3(
                        libraryId: _libraryId,
                        memberData: _memberData,
                        onSeatSelected: (seatId, label, floorId, sectionId, floorName, sectionName) {
                          setState(() {
                            _memberData.selectedSeatId = seatId;
                            _memberData.selectedSeatLabel = label;
                            _memberData.selectedFloorId = floorId;
                            _memberData.selectedFloorName = floorName;
                            _memberData.selectedSectionId = sectionId;
                            _memberData.selectedSectionName = sectionName;
                          });
                        },
                      ),
                      AddMemberStep4(
                        memberData: _memberData,
                      ),
                      AddMemberStep5(
                        memberData: _memberData,
                        libraryName: _libraryName ?? 'Silence Library',
                        onEditStep: (step) {
                          _pageController.animateToPage(
                            step,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                _buildFooter(),
              ],
            ),
            if (_isLoading)
              Container(
                color: Colors.black26,
                child: const Center(
                  child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0:
        return 'Personal Details';
      case 1:
        return 'Plan Configuration';
      case 2:
        return 'Seat Assignment';
      case 3:
        return 'Payment Details';
      case 4:
        return 'Review & Confirm';
      default:
        return '';
    }
  }

  Widget _buildFooter() {
    final isLastStep = _currentStep == 4;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            OutlinedButton(
              onPressed: () {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'Back',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
              ),
            )
          else
            const SizedBox.shrink(),
          ElevatedButton(
            onPressed: () {
              if (_validateStep()) {
                if (isLastStep) {
                  _finalizeRegistration();
                } else {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65C00),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text(
              isLastStep ? 'Confirm & Register' : 'Continue',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
