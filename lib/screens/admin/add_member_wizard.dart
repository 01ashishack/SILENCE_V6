import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/member_draft.dart';
import '../../models/member_data.dart';
import '../../services/draft_service.dart';
import '../../core/image_optimizer.dart';
import '../../core/cache_service.dart';
import '../../utils/error_messages.dart';
import 'add_member_mode_selection.dart';
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

  String _libraryId = '';
  String? _libraryName;
  String? _draftId;

  List<Map<String, dynamic>> _ownedLibraries = [];
  bool _showLibrarySelection = false;

  // Single Model instance containing all step data
  final MemberData _memberData = MemberData();
  final _step1FormKey = GlobalKey<FormState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initWizard();
    }
  }

  Future<void> _initWizard() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('No active admin session found.');
      }

      // Query all owned libraries
      final res = await _supabase
          .from('libraries')
          .select('id, name')
          .eq('owner_id', user.id);
      
      _ownedLibraries = List<Map<String, dynamic>>.from(res);

      final Object? routeArgs = ModalRoute.of(context)?.settings.arguments;
      String? parsedLibId;
      if (routeArgs is Map<String, dynamic>) {
        parsedLibId = routeArgs['libraryId'] as String?;
        _draftId = routeArgs['draftId'] as String?;
      } else if (routeArgs is String) {
        parsedLibId = routeArgs;
      }

      final String passedLibId = parsedLibId ?? '';
      
      if (passedLibId.isNotEmpty && passedLibId != 'all') {
        // A specific library was passed, skip library selection
        _libraryId = passedLibId;
        _showLibrarySelection = false;
      } else {
        // No specific library passed
        if (_ownedLibraries.length == 1) {
          // Admin owns only 1 library, auto-select it and skip library selection step
          _libraryId = _ownedLibraries.first['id'] as String;
          _showLibrarySelection = false;
        } else if (_ownedLibraries.length > 1) {
          // Multiple libraries owned, show library selection step!
          _showLibrarySelection = true;
          _libraryId = '';
        } else {
          // No libraries owned
          _showLibrarySelection = false;
          _libraryId = '';
        }
      }

      if (_libraryId.isNotEmpty) {
        await _fetchLibraryName();
        if (_draftId != null) {
          await _loadDraft(_draftId!);
        } else {
          _currentStep = 0;
        }
      } else {
        _currentStep = 0;
      }
      _initialized = true;
    } catch (e) {
      debugPrint('Error initializing wizard: $e');
      if (mounted) {
        _showErrorSnackBar('Initialization failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      if (!mounted) return;
      final draft = drafts.firstWhere((d) => d.id == draftId);
      final data = draft.draftData;

      setState(() {
        _memberData.fromJson(data);
        final savedStep = data['currentStep'] as int?;
        if (savedStep != null && savedStep >= 0 && savedStep < 5) {
          int targetPage = savedStep + 1; // Shifting because Step 0 is Mode Selection
          if (_showLibrarySelection) {
            targetPage = savedStep + 2; // Shifting because Step 0 is Library Selection
          }
          _currentStep = targetPage;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_pageController.hasClients) {
              _pageController.jumpToPage(targetPage);
            }
          });
        }
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

  Future<void> _saveAsDraft() async {
    setState(() => _isLoading = true);
    try {
      final admin = _supabase.auth.currentUser;
      if (admin == null) throw Exception('No active admin session found.');

      final draftData = _memberData.toJson();
      // Shifting back so drafts are saved in 0..4 index format for compatibility
      draftData['currentStep'] = (_currentStep - 1).clamp(0, 4);

      final draft = MemberDraft(
        id: _draftId,
        adminId: admin.id,
        libraryId: _libraryId,
        draftData: draftData,
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
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
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
    int adjustedStep = _currentStep;
    if (_showLibrarySelection) {
      if (_currentStep == 0) {
        if (_libraryId.isEmpty) {
          _showErrorSnackBar('Please select a library first.');
          return false;
        }
        return true;
      }
      adjustedStep = _currentStep - 1;
    }

    if (adjustedStep == 1) {
      if (_step1FormKey.currentState?.validate() == false) {
        return false;
      }
      if (_memberData.idProof1File == null && _memberData.idProof2File == null) {
        _showErrorSnackBar('At least one ID proof document is required.');
        return false;
      }
    } else if (adjustedStep == 2) {
      if (_memberData.selectedShiftId == null) {
        _showErrorSnackBar('Please configure and select a shift.');
        return false;
      }
      if (_memberData.mode == 'existing' && _memberData.planStartDate == null) {
        _showErrorSnackBar('Plan start date is required for existing members.');
        return false;
      }
    } else if (adjustedStep == 3) {
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

  Future<void> _finalizeRegistration() async {
    setState(() => _isLoading = true);
    // Track partial writes so we can roll them back if a later step fails —
    // there is no server-side transaction (see _rollbackPartialRegistration).
    String? createdMembershipId;
    String? occupiedSeatId;
    try {
      // 1. Look up or insert user by phone or email
      var userObj = await _supabase
          .from('users')
          .select('id')
          .or('phone.eq.${_memberData.phone},email.eq.${_memberData.email}')
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

        // Prevent duplicate active memberships (incl. 'pending' — a member
        // awaiting payment confirmation must not be added a second time).
        final activeMemberships = await _supabase
            .from('memberships')
            .select('id')
            .eq('member_id', memberUserId)
            .eq('library_id', _libraryId)
            .inFilter('status', ['active', 'trial', 'hold', 'pending']);

        if (activeMemberships.isNotEmpty) {
          if (mounted) {
            setState(() => _isLoading = false);
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                title: Text('Active Membership Found', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.red)),
                content: Text(
                  'This member already has an active membership in this library. Please renew or exit the existing membership before adding a new one.',
                  style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569)),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('OK', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                  ),
                ],
              ),
            );
          }
          return;
        }

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
          'id_proof_url': docUrl,
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
      createdMembershipId = membershipId;

      // 5. Occupy the seat immediately after the membership is created, BEFORE
      // the payment insert. If payment ever fails, the seat/membership stay in
      // sync (no "assigned but shows vacant"); the layout grid also self-heals.
      if (_memberData.selectedSeatId != null) {
        await _supabase.from('seats').update({
          'status': 'occupied',
          'occupied_by_member_id': memberUserId,
        }).eq('id', _memberData.selectedSeatId!);
        occupiedSeatId = _memberData.selectedSeatId;
      }

      // 6. Create payment record
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

      // 7. Delete draft if loaded
      if (_draftId != null) {
        await DraftService.instance.deleteDraft(_draftId!, _libraryId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member added successfully ✓'), backgroundColor: Colors.green),
        );
        // Close the wizard and signal members_sub_tab to refresh the member list.
        Navigator.pop(context, true);
      }
    } catch (e) {
      // Log the exact exception (incl. PostgREST/RLS details) — do not swallow.
      debugPrint('Error finalizing registration: $e');
      // Compensating rollback: a later step (commonly the payment insert) can
      // fail AFTER the membership + seat were written, leaving a "ghost" member
      // in the list. Undo those writes so the admin can cleanly retry. There is
      // no server transaction; this is best-effort.
      if (createdMembershipId != null) {
        await _rollbackPartialRegistration(createdMembershipId, occupiedSeatId);
      }
      if (mounted) {
        // Keep the wizard OPEN so the admin can correct and retry. Do NOT save a
        // draft on error — that path is what produced duplicate member records.
        _showErrorSnackBar(friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Best-effort undo of a half-finished registration (no DB transaction
  /// exists). Frees the seat we occupied and marks the just-created membership
  /// `exited` so it stops showing as an active member. Each step is independent
  /// and swallowed — a cleanup failure must not mask the original error.
  Future<void> _rollbackPartialRegistration(String membershipId, String? seatId) async {
    if (seatId != null) {
      try {
        await _supabase.from('seats').update({
          'status': 'vacant',
          'occupied_by_member_id': null,
        }).eq('id', seatId);
      } catch (e) {
        debugPrint('Rollback: free seat failed: $e');
      }
    }
    try {
      await _supabase.from('memberships').update({
        'status': 'exited',
        'seat_id': null,
      }).eq('id', membershipId);
    } catch (e) {
      debugPrint('Rollback: cancel membership failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && !_initialized) {
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

    final List<Widget> steps = [];
    if (_showLibrarySelection) {
      steps.add(_buildLibrarySelectionStep());
    }
    steps.addAll([
      AddMemberModeSelection(
        selectedMode: _memberData.mode,
        onModeSelected: (mode) {
          setState(() {
            _memberData.mode = mode;
            _memberData.paymentFlow = 'paid';
          });
        },
        onContinue: () {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
      ),
      AddMemberStep1(
        formKey: _step1FormKey,
        memberData: _memberData,
        libraryId: _libraryId,
        currentDraftId: _draftId,
        onDraftSelected: (draftId) {
          _draftId = draftId;
          _loadDraft(draftId);
        },
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
    ]);

    if (_memberData.mode != 'existing') {
      steps.add(AddMemberStep4(
        memberData: _memberData,
      ));
    }

    steps.add(AddMemberStep5(
      memberData: _memberData,
      libraryName: _libraryName ?? 'Silence Library',
      onEditStep: (step) {
        int targetPage = step + 1; // standard Mode Selection is step + 1
        if (_memberData.mode == 'existing' && step >= 4) {
          targetPage = step; // Adjust since AddMemberStep4 is omitted
        }
        if (_showLibrarySelection) {
          targetPage += 1;
        }
        _pageController.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
      onSaveDraft: _saveAsDraft,
      onConfirmRegister: _finalizeRegistration,
    ));

    final currentProgress = (_currentStep + 1) / steps.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentStep == 0) {
          Navigator.pop(context);
        } else {
          _showExitDraftPrompt();
        }
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
                'Step ${_currentStep + 1} of ${steps.length}: ${_getStepTitle(steps)}',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            if (_currentStep > 0)
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
                    children: steps,
                  ),
                ),
                if (_currentStep > 0 && !(_showLibrarySelection && _currentStep == 0)) _buildFooter(steps),
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

  String _getStepTitle(List<Widget> steps) {
    if (_currentStep < 0 || _currentStep >= steps.length) return '';
    final widget = steps[_currentStep];
    if (widget is AddMemberModeSelection) {
      return 'Choose Mode';
    } else if (widget is AddMemberStep1) {
      return 'Personal Details';
    } else if (widget is AddMemberStep2) {
      return 'Plan Configuration';
    } else if (widget is AddMemberStep3) {
      return 'Seat Assignment';
    } else if (widget is AddMemberStep4) {
      return 'Payment Details';
    } else if (widget is AddMemberStep5) {
      return 'Review & Confirm';
    } else {
      return 'Select Library';
    }
  }

  Widget _buildFooter(List<Widget> steps) {
    final isLastStep = _currentStep == steps.length - 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          OutlinedButton(
            onPressed: () {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFE5E7EB)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              'Back',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)),
            ),
          ),
          if (!isLastStep)
            ElevatedButton(
              onPressed: () {
                if (_validateStep()) {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
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
                'Continue',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLibrarySelectionStep() {
    return Container(
      color: const Color(0xFFFBF5EE),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE65C00).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.storefront,
                      size: 36,
                      color: Color(0xFFE65C00),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Select Library branch',
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A1A2E),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please select the library branch where the member wants to register.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF6B7280),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),
                  
                  // Library cards
                  ..._ownedLibraries.map((lib) {
                    final isSelected = _libraryId == lib['id'];
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _libraryId = lib['id'] as String;
                          _libraryName = lib['name'] as String?;
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
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
                              color: Colors.black.withValues(alpha: isSelected ? 0.06 : 0.02),
                              blurRadius: isSelected ? 12 : 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                              color: isSelected ? const Color(0xFFE65C00) : Colors.grey[400],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                lib['name'] ?? 'Silence Library',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: const Color(0xFF1E293B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          
          // Next Button
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _libraryId.isNotEmpty
                    ? () {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE5E7EB),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Continue',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _libraryId.isNotEmpty ? Colors.white : const Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
