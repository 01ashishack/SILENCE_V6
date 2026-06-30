import 'dart:async';
import '../../theme/app_palette.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/image_optimizer.dart';
import '../../core/calendar_picker.dart';
import '../../theme/app_colors.dart';
import '../../utils/upi_launcher.dart';
import '../../utils/form_draft.dart';
import '../../widgets/states/states.dart';


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
  List<Map<String, dynamic>> _activeMemberships = [];

  // Returning member welcome state
  Map<String, dynamic>? _exitedMembershipToWelcome;
  String _origFullName = '';
  String _origPhone = '';
  String _origNickname = '';
  bool _usedPreviousDetails = false;

  // Step 1: Existing member & inline profile details
  bool _isExistingMember = false;
  DateTime? _existingJoinDate;
  
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
  String? _proofUrl;
  bool _paymentDeclared = false; // member confirms "I have paid" (UPI)

  /// Admin-configured UPI IDs for this library (from libraries.social_links).
  List<String> get _upiIds {
    final sl = _library?['social_links'];
    if (sl is Map && sl['upi_ids'] is List) {
      return (sl['upi_ids'] as List)
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }
    return [];
  }

  // Step 5: Review & Submit
  final TextEditingController _referralCtrl = TextEditingController();
  bool _isSubmitting = false;
  bool _submitSuccess = false;

  // Draft persistence (survives app restart until submitted/discarded)
  late final FormDraft _draft;
  Timer? _draftTimer;
  bool _restoringDraft = false;

  @override
  void initState() {
    super.initState();
    _draft = FormDraft('join', widget.libraryId);
    _loadJoinDetails();
    for (final c in [_fullNameCtrl, _phoneCtrl, _nicknameCtrl, _upiSenderCtrl, _referralCtrl]) {
      c.addListener(_scheduleDraftSave);
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _nicknameCtrl.dispose();
    _upiSenderCtrl.dispose();
    _referralCtrl.dispose();
    super.dispose();
  }

  // ── Draft save / restore ────────────────────────────────────────────────────
  void _scheduleDraftSave() {
    if (_restoringDraft || _submitSuccess || _isSubmitting) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), _saveDraft);
  }

  Future<void> _saveDraft() async {
    if (_restoringDraft || _submitSuccess || _isSubmitting) return;
    await _draft.save({
      'currentStep': _currentStep,
      'isExistingMember': _isExistingMember,
      'existingJoinDate': _existingJoinDate?.toIso8601String(),
      'fullName': _fullNameCtrl.text,
      'phone': _phoneCtrl.text,
      'nickname': _nicknameCtrl.text,
      'selectedShiftId': _selectedShift?['id']?.toString(),
      'selectedPlan': _selectedPlan,
      'selectedAddOns': _selectedAddOns,
      'paymentMethod': _paymentMethod,
      'upiSender': _upiSenderCtrl.text,
      'paymentDeclared': _paymentDeclared,
      'referral': _referralCtrl.text,
    });
  }

  Future<void> _maybeOfferRestore() async {
    final raw = await _draft.load();
    if (raw == null) return;
    final step = (raw['currentStep'] as num?)?.toInt() ?? 1;
    final hasText = ((raw['fullName'] ?? '') as String).trim().isNotEmpty ||
        ((raw['phone'] ?? '') as String).trim().isNotEmpty;
    // Nothing meaningful saved yet — drop it silently.
    if (step <= 1 && !hasText) {
      await _draft.clear();
      return;
    }
    if (!mounted) return;
    final resume = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Resume your application?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
        content: Text(
          'You have an unfinished application for this library, saved ${FormDraft.savedAgo(raw['savedAt'])}. '
          'Continue where you left off, or start fresh?',
          style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: context.palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Start fresh', style: GoogleFonts.inter(color: context.palette.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: Text('Resume', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (resume == true) {
      _applyDraft(raw);
    } else if (resume == false) {
      await _draft.clear();
    }
  }

  void _applyDraft(Map<String, dynamic> raw) {
    _restoringDraft = true;
    setState(() {
      _isExistingMember = raw['isExistingMember'] == true;
      final jd = raw['existingJoinDate'];
      _existingJoinDate = jd is String ? DateTime.tryParse(jd) : null;
      _fullNameCtrl.text = (raw['fullName'] ?? '') as String;
      _phoneCtrl.text = (raw['phone'] ?? '') as String;
      _nicknameCtrl.text = (raw['nickname'] ?? '') as String;
      final shiftId = raw['selectedShiftId']?.toString();
      if (shiftId != null && _shifts.isNotEmpty) {
        final match = _shifts.where((s) => s['id'].toString() == shiftId).toList();
        if (match.isNotEmpty) _selectedShift = match.first;
      }
      _selectedPlan = (raw['selectedPlan'] ?? _selectedPlan) as String;
      final addons = raw['selectedAddOns'];
      if (addons is Map) {
        addons.forEach((k, v) {
          if (_selectedAddOns.containsKey(k)) _selectedAddOns[k.toString()] = v == true;
        });
      }
      _paymentMethod = (raw['paymentMethod'] ?? _paymentMethod) as String;
      _upiSenderCtrl.text = (raw['upiSender'] ?? '') as String;
      _paymentDeclared = raw['paymentDeclared'] == true;
      _referralCtrl.text = (raw['referral'] ?? '') as String;
      final step = (raw['currentStep'] as num?)?.toInt();
      if (step != null && step >= 1 && step <= 5) _currentStep = step;
    });
    _restoringDraft = false;
  }

  int _timeStringToMinutes(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.isEmpty) return 0;
    final hours = int.parse(parts[0]);
    final minutes = parts.length > 1 ? int.parse(parts[1]) : 0;
    return hours * 60 + minutes;
  }

  bool _isShiftOverlapping(Map<String, dynamic> shift1, Map<String, dynamic> shift2) {
    final start1Str = shift1['start_time'] as String?;
    final end1Str = shift1['end_time'] as String?;
    final start2Str = shift2['start_time'] as String?;
    final end2Str = shift2['end_time'] as String?;
    
    if (start1Str == null || end1Str == null || start2Str == null || end2Str == null) {
      return false;
    }
    
    final s1 = _timeStringToMinutes(start1Str);
    final e1 = _timeStringToMinutes(end1Str);
    final s2 = _timeStringToMinutes(start2Str);
    final e2 = _timeStringToMinutes(end2Str);
    
    List<List<int>> getIntervals(int start, int end) {
      if (end > start) {
        return [[start, end]];
      } else {
        return [[start, 1440], [0, end]];
      }
    }
    
    final iv1 = getIntervals(s1, e1);
    final iv2 = getIntervals(s2, e2);
    
    for (final i1 in iv1) {
      for (final i2 in iv2) {
        if (i1[0] < i2[1] && i2[0] < i1[1]) {
          return true;
        }
      }
    }
    
    return false;
  }

  Map<String, dynamic>? _getConflictingActiveMembership(Map<String, dynamic> targetShift) {
    for (var m in _activeMemberships) {
      final activeShift = m['shifts'] as Map<String, dynamic>?;
      if (activeShift == null) continue;
      if (activeShift['id'] == targetShift['id']) continue;
      
      if (_isShiftOverlapping(targetShift, activeShift)) {
        return m;
      }
    }
    return null;
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

      // Fetch active/trial memberships to check timing conflicts
      final activeMembershipsRes = await supabase
          .from('memberships')
          .select('*, shifts(*), libraries(*)')
          .eq('member_id', user.id)
          .inFilter('status', ['active', 'trial']);
      _activeMemberships = List<Map<String, dynamic>>.from(activeMembershipsRes);

      if (widget.initialShiftId != null && _shifts.isNotEmpty) {
        _selectedShift = _shifts.firstWhere(
          (s) => s['id'] == widget.initialShiftId,
          orElse: () => _shifts.first,
        );
      } else if (_shifts.isNotEmpty) {
        // Find first non-conflicting shift
        Map<String, dynamic>? initialSel;
        for (var s in _shifts) {
          if (_getConflictingActiveMembership(s) == null) {
            initialSel = s;
            break;
          }
        }
        _selectedShift = initialSel ?? _shifts.first;
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

      // 4. Fetch exited memberships
      final exitedMembershipsRes = await supabase
          .from('memberships')
          .select('*, libraries(name)')
          .eq('member_id', user.id)
          .eq('status', 'exited')
          .order('end_date', ascending: false)
          .limit(1);

      final exitedMemberships = List<Map<String, dynamic>>.from(exitedMembershipsRes);
      if (exitedMemberships.isNotEmpty) {
        _exitedMembershipToWelcome = exitedMemberships.first;
      }

      // 5. Fetch user profile
      final profileRes = await supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      
      _userProfile = profileRes;
      
      if (_exitedMembershipToWelcome == null) {
        if (_userProfile != null) {
          _fullNameCtrl.text = _userProfile!['full_name'] ?? '';
          _phoneCtrl.text = _userProfile!['phone'] ?? '';
          _nicknameCtrl.text = _userProfile!['nickname'] ?? '';
        }
      }

      // 6. Check trial eligibility
      final trialCheck = await supabase
          .from('memberships')
          .select()
          .eq('member_id', user.id)
          .eq('library_id', widget.libraryId)
          .eq('status', 'trial')
          .limit(1);
      if (!mounted) return;
      
      _trialEligible = (trialCheck as List).isEmpty;

    } catch (e) {
      debugPrint('Error loading join flow details: $e');
      _errorMessage = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      if (_exitedMembershipToWelcome != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showWelcomeBackBottomSheet();
        });
      } else if (_errorMessage == null && mounted) {
        // Offer to restore a saved draft (skip when the welcome-back sheet shows).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeOfferRestore();
        });
      }
    }
  }

  void _showWelcomeBackBottomSheet() {
    final libName = _exitedMembershipToWelcome!['libraries']?['name'] ?? 'SILENCE';
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return PopScope(
          canPop: false,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.waving_hand_outlined,
                  color: Color(0xFFE65C00),
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Welcome Back!',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: context.palette.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'We noticed you were previously a member at $libName. Would you like to use your previous profile details to pre-fill the application?',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    color: context.palette.textMuted,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      _usedPreviousDetails = true;
                      if (_userProfile != null) {
                        _origFullName = _userProfile!['full_name'] ?? '';
                        _origPhone = _userProfile!['phone'] ?? '';
                        _origNickname = _userProfile!['nickname'] ?? '';
                        
                        _fullNameCtrl.text = _origFullName;
                        _phoneCtrl.text = _origPhone;
                        _nicknameCtrl.text = _origNickname;
                      }
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Use Previous Details'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      _usedPreviousDetails = false;
                      _origFullName = '';
                      _origPhone = '';
                      _origNickname = '';
                      _fullNameCtrl.clear();
                      _phoneCtrl.clear();
                      _nicknameCtrl.clear();
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.palette.textSecondary,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Start Fresh'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // File picker helper
  Future<void> _pickProofImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (!mounted) return;
    if (image == null) return;

    setState(() {
      _proofImageFile = File(image.path);
    });
  }

  Future<bool> _uploadProofImage() async {
    if (_proofImageFile == null) return false;

    try {
      final supabase = Supabase.instance.client;
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return false;
      final fileName = 'proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = 'payment_proofs/$uid/$fileName';

      final bytes = await ImageOptimizer.compressImage(_proofImageFile!.path);
      await supabase.storage.from('silence_private').uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              cacheControl: '3600',
              upsert: true,
            ),
          );

      if (!mounted) return false;
      // Store the STORAGE PATH (not a short-lived signed URL): admin review may
      // happen hours later, so the viewer mints a fresh signed URL on demand
      // via StorageUrls.resolve(). (audit P0 — signed-URL expiry)
      _proofUrl = path;
      return true;
    } catch (e) {
      debugPrint('Error uploading proof photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload screenshot: $e')),
        );
      }
      return false;
    }
  }

  // Calculate pricing summaries
  double _calculateSelectedPlanPrice() {
    final shift = _selectedShift;
    if (shift == null) return 0;
    if (_selectedPlan == 'trial') return 0;

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
      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User session expired. Please login again.');
      }

      // Check existing active/pending membership
      final existing = await supabase
          .from('memberships')
          .select('id')
          .eq('member_id', user.id)
          .eq('library_id', widget.libraryId)
          .inFilter('status', ['active', 'trial', 'pending'])
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You are already a member or have a pending request for this library.')),
          );
        }
        return;
      }

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

        if (_exitedMembershipToWelcome != null && _usedPreviousDetails) {
          if (nameStr != _origFullName || phoneStr != _origPhone || nickStr != _origNickname) {
            try {
              await supabase.from('notifications').insert({
                'user_id': _library?['owner_id'] ?? user.id,
                'title': 'Returning Member Profile Modified',
                'body': 'Returning member $nameStr ($phoneStr) modified their profile details during rejoin.',
                'data': {
                  'member_id': user.id,
                  'library_id': widget.libraryId,
                },
              });
            } catch (e) {
              debugPrint('Error logging/notifying profile modification: $e');
            }
          }
        }
      }

      // 2. UPI payment happens outside the app. The member confirms they paid;
      // a screenshot is optional (uploaded only if one was attached).
      if (_paymentMethod == 'upi' && _selectedPlan != 'trial') {
        if (!_paymentDeclared) {
          throw Exception("Please confirm you've made the payment.");
        }
        if (_proofImageFile != null) {
          final uploadOk = await _uploadProofImage();
          if (!uploadOk) {
            throw Exception('Screenshot upload failed. Remove it or try again.');
          }
        }
      }

      final shift = _selectedShift;
      if (shift == null) {
        throw Exception('Please select a shift to proceed.');
      }

      // Selected add-on ids (so the admin can persist them on approval).
      final selectedAddOnIds = _addOns
          .where((a) => _selectedAddOns[a['id']] == true)
          .map((a) => a['id'].toString())
          .toList();

      // 3. Construct join request
      final requestPayload = <String, dynamic>{
        'member_id': user.id,
        'library_id': widget.libraryId,
        'shift_id': shift['id'],
        'plan_type': _selectedPlan,
        'payment_method': _selectedPlan == 'trial' ? 'none' : _paymentMethod,
        'payment_proof_url': _proofUrl,
        'upi_sender_name': _paymentMethod == 'upi' && _selectedPlan != 'trial' ? _upiSenderCtrl.text.trim() : null,
        'existing_member_join_date': _isExistingMember && _existingJoinDate != null
            ? DateFormat('yyyy-MM-dd').format(_existingJoinDate!)
            : null,
        'status': 'pending',
      };
      if (selectedAddOnIds.isNotEmpty) {
        requestPayload['selected_addon_ids'] = selectedAddOnIds;
      }

      try {
        await supabase.from('join_requests').insert(requestPayload);
      } catch (e) {
        // `selected_addon_ids` may not exist yet on older DBs (Phase C adds it).
        // Retry without it so the join still works rather than failing.
        if (selectedAddOnIds.isNotEmpty) {
          debugPrint('join_requests insert retry without addon ids: $e');
          requestPayload.remove('selected_addon_ids');
          await supabase.from('join_requests').insert(requestPayload);
        } else {
          rethrow;
        }
      }

      // Notify the library owner about the new join request.
      // RLS allows an applicant → related-library-owner notification.
      try {
        final ownerId = _library?['owner_id'];
        if (ownerId != null) {
          await supabase.from('notifications').insert({
            'user_id': ownerId,
            'title': 'New join request',
            'body': 'A new member has applied to join your library. Review it in Reservations → Requests.',
            'data': {'type': 'join_request', 'library_id': widget.libraryId},
          });
        }
      } catch (e) {
        debugPrint('Owner join-request notification failed: $e');
      }

      // 4. Save optional referral. This runs AFTER the join_request is already
      // committed, so it must never throw out to the outer catch (that would
      // show "submit failed" for a request that actually succeeded). Best-effort.
      final refCode = _referralCtrl.text.trim();
      if (refCode.isNotEmpty) {
        try {
          // referral_code is unique.
          final referrerRes = await supabase
              .from('users')
              .select('id')
              .eq('referral_code', refCode)
              .limit(1)
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
        } catch (e) {
          debugPrint('Referral save failed (non-fatal): $e');
        }
      }

      _draftTimer?.cancel();
      await _draft.clear();
      setState(() {
        _submitSuccess = true;
      });

    } catch (e) {
      debugPrint('Error submitting join request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit application: $e')),
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
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFBF5EE),
        body: LoadingState(kind: SkeletonKind.spinner, message: 'Loading…'),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: context.palette.scaffold,
        appBar: AppBar(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
        body: ErrorState(error: _errorMessage, onRetry: _loadJoinDetails),
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
          backgroundColor: context.palette.scaffold,
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
                    // Mirror the forward skip: if there are no add-ons, step 3
                    // is skipped in BOTH directions (was only skipped forward).
                    if (_currentStep == 3 && _addOns.isEmpty) _currentStep = 2;
                  });
                  _saveDraft();
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
            backgroundColor: isLastStep ? const Color(0xFFE65C00) : context.palette.textPrimary,
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
      _saveDraft();
    } else if (_currentStep == 2) {
      if (_selectedShift == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a shift to proceed.')),
        );
        return;
      }

      if (_getConflictingActiveMembership(_selectedShift!) != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The selected shift overlaps with an active membership. Please select another shift.')),
        );
        return;
      }

      // Skip Add-ons step if none exist
      if (_addOns.isEmpty) {
        setState(() => _currentStep = _selectedPlan == 'trial' ? 5 : 4);
      } else {
        setState(() => _currentStep = 3);
      }
      _saveDraft();
    } else if (_currentStep == 3) {
      setState(() => _currentStep = _selectedPlan == 'trial' ? 5 : 4);
      _saveDraft();
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
      _saveDraft();
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
          decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Have you studied here before?',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
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
                            Text("New Member", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
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
                            Text("Existing Member", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
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
            decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Optional History', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                
                Text('Approximate Joining Date', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final picked = await showCalendarGridBottomSheet(
                      context,
                      initialDate: DateTime.now().subtract(const Duration(days: 30)),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (!mounted) return;
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
          decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Complete Your Details',
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
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
    final shift = _selectedShift;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose a Shift',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
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
            final isSelected = shift?['id'] == s['id'];
            final conflictM = _getConflictingActiveMembership(s);
            final hasConflict = conflictM != null;
            
            return InkWell(
              onTap: hasConflict ? null : () {
                setState(() {
                  _selectedShift = s;
                });
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: hasConflict ? Colors.grey[100] : Colors.white,
                  border: Border.all(
                    color: isSelected 
                        ? const Color(0xFFE65C00) 
                        : (hasConflict ? Colors.red[200]! : Colors.grey[300]!), 
                    width: isSelected ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected 
                          ? Icons.radio_button_checked 
                          : (hasConflict ? Icons.block : Icons.radio_button_unchecked),
                      color: isSelected 
                          ? const Color(0xFFE65C00) 
                          : (hasConflict ? Colors.red[400] : Colors.grey[400]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s['name'] ?? 'Shift', 
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold, 
                              fontSize: 13,
                              color: hasConflict ? Colors.grey[500] : Colors.black87,
                            ),
                          ),
                          Text(
                            '${s['start_time']} – ${s['end_time']}',
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                          ),
                          if (hasConflict) ...[
                            const SizedBox(height: 4),
                            Text(
                              '⚠️ Timing overlap: ${conflictM['shifts']?['name'] ?? 'Shift'} (${conflictM['libraries']?['name'] ?? 'Library'})',
                              style: GoogleFonts.inter(fontSize: 10, color: Colors.red[600], fontWeight: FontWeight.w600),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      '₹${s['price_monthly']}/mo',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold, 
                        fontSize: 13, 
                        color: hasConflict ? Colors.grey[400] : const Color(0xFFE65C00),
                      ),
                    )
                  ],
                ),
              ),
            );
          }),
        
        const SizedBox(height: 20),
        Text(
          'Choose Plan',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
        ),
        const SizedBox(height: 10),

        // Free Trial option
        if (shift != null && (shift['trial_days'] as int? ?? 0) > 0 && _trialEligible) ...[
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
                        Text('${shift['trial_days']} days trial period', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
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
        _buildPlanPill('monthly', 'Monthly Plan', '₹${shift != null ? (shift['price_monthly'] ?? 0) : 0}'),
        const SizedBox(height: 8),
        _buildPlanPill('3_month', '3-Month Plan', '₹${shift != null ? (shift['price_3month'] ?? ((shift['price_monthly'] as int? ?? 0) * 3)) : 0}'),
        const SizedBox(height: 8),
        _buildPlanPill('6_month', '6-Month Plan', '₹${shift != null ? (shift['price_6month'] ?? ((shift['price_monthly'] as int? ?? 0) * 6)) : 0}'),
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
            Text(priceLabel, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: context.palette.textPrimary)),
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
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
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
                color: context.palette.surface,
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
          decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(12)),
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
                  Text('Grand Total', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
                  Text('₹$grandTotal', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        Text(
          'Select Payment Method',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
        ),
        const SizedBox(height: 10),

        _buildPaymentMethodOption('cash', '💵 Cash Payment', 'Pay the total amount in cash directly at the library.'),
        const SizedBox(height: 8),
        _buildPaymentMethodOption('upi', '📱 UPI / Online Transfer', 'Pay the admin via any UPI app, then confirm below.'),
        const SizedBox(height: 8),
        _buildPaymentMethodOption('pay_later', '🕒 Pay Later', 'Submit now and pay at the library later. The admin can approve and the amount stays as a due.'),

        if (_paymentMethod == 'upi') ...[
          const SizedBox(height: 20),
          _buildUpiCard(_calculateTotalPrice()),
        ],
        if (_paymentMethod == 'pay_later') ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0x14F59E0B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x33F59E0B)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: Color(0xFFB45309)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your request will be sent without payment. Once approved, ₹${_calculateTotalPrice().toStringAsFixed(0)} will show as pending dues until you pay the library.',
                    style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: const Color(0xFFB45309)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// UPI card: admin's configured UPI IDs as tappable deep-link buttons (open
  /// the payer's UPI app pre-filled), an honest note that payment happens
  /// outside the app and the admin verifies it, the required "I have paid"
  /// confirmation, and an OPTIONAL reference + screenshot.
  Widget _buildUpiCard(double total) {
    final ids = _upiIds;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ids.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "This library hasn't added a UPI ID yet. Please pay by cash, or contact the admin.",
                      style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: AppColors.orangeText),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              'Pay to the library',
              style: GoogleFonts.outfit(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: context.palette.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Tap an app to pay ₹${total.toStringAsFixed(0)}, or copy the UPI ID.',
              style: GoogleFonts.inter(fontSize: 11.5, color: context.palette.textMuted),
            ),
            const SizedBox(height: 10),
            ...ids.map((id) => _buildUpiAppButton(id, total)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.infoBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_outlined, size: 16, color: AppColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Payment happens in your UPI app. After paying, confirm below — the admin verifies it and activates your plan.',
                      style: GoogleFonts.inter(fontSize: 11.5, height: 1.4, color: context.palette.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildDeclareCheck(),
            const SizedBox(height: 12),
            TextField(
              controller: _upiSenderCtrl,
              decoration: const InputDecoration(
                labelText: 'Reference / sender name (optional)',
                hintText: 'Helps the admin match your payment',
              ),
            ),
            const SizedBox(height: 12),
            _buildOptionalScreenshot(),
          ],
        ],
      ),
    );
  }

  Widget _buildUpiAppButton(String upiId, double amount) {
    final app = detectUpiApp(upiId);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: context.palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _payViaUpi(upiId, amount),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: app.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(app.icon, size: 18, color: app.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pay with ${app.name}',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.palette.textPrimary),
                    ),
                    Text(
                      upiId,
                      style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy_rounded, size: 18, color: context.palette.textMuted),
                tooltip: 'Copy UPI ID',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: upiId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('UPI ID copied')),
                  );
                },
              ),
              const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeclareCheck() {
    return InkWell(
      onTap: () => setState(() => _paymentDeclared = !_paymentDeclared),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _paymentDeclared ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
            color: _paymentDeclared ? AppColors.primary : context.palette.textMuted,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "I have made this payment to the library's UPI.",
              style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: context.palette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionalScreenshot() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add payment screenshot (optional)',
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: context.palette.textSecondary),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickProofImage,
          child: Container(
            height: 110,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: context.palette.border),
              borderRadius: BorderRadius.circular(8),
              color: context.palette.surfaceMuted,
            ),
            alignment: Alignment.center,
            child: _proofImageFile != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(_proofImageFile!, fit: BoxFit.contain),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 28, color: context.palette.textMuted),
                      const SizedBox(height: 6),
                      Text('Tap to attach a screenshot', style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _payViaUpi(String upiId, double amount) async {
    final libName = (_library?['name'] as String?)?.trim();
    final result = await launchUpiPayment(
      payeeVpa: upiId,
      payeeName: (libName == null || libName.isEmpty) ? 'SILENCE Library' : libName,
      amount: amount,
      note: 'Membership payment',
    );
    if (!mounted) return;
    if (result == UpiLaunchResult.noApp) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No UPI app found. Copy the UPI ID and pay manually.')),
      );
    } else if (result == UpiLaunchResult.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open a UPI app. Copy the UPI ID and pay manually.')),
      );
    }
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

  // STEP 5: REVIEW & SUBMIT
  Widget _buildStep5Review() {
    final double grandTotal = _calculateTotalPrice();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Review Your Application',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildReviewRow('Library', _library?['name'] ?? 'SILENCE Study Zone'),
              const Divider(height: 20),
              _buildReviewRow('Selected Shift', _selectedShift?['name'] ?? 'Morning'),
              const Divider(height: 20),
              _buildReviewRow('Plan type', _selectedPlan == 'trial' ? '🆓 Free Trial' : '${_selectedPlan == 'monthly' ? 'Monthly' : _selectedPlan == '3_month' ? '3-Month' : '6-Month'} plan'),
              const Divider(height: 20),
              _buildReviewRow('Payment method', _selectedPlan == 'trial' ? 'Trial (Skip payment)' : _paymentMethod == 'cash' ? 'Cash at Library' : _paymentMethod == 'pay_later' ? 'Pay Later (dues)' : 'UPI transfer'),
              
              if (_paymentMethod == 'upi' && _selectedPlan != 'trial') ...[
                const Divider(height: 20),
                _buildReviewRow('UPI Sender Name', _upiSenderCtrl.text),
              ],
              
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Grand Total', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
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
        Text(val, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
      ],
    );
  }

  // ==========================================
  // CONFIRMATION SCREEN
  // ==========================================
  Widget _buildConfirmationScreen() {
    return Scaffold(
      backgroundColor: context.palette.scaffold,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: const Color(0xFFE65C00).withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.assignment_turned_in, size: 64, color: Color(0xFFE65C00)),
              ),
              const SizedBox(height: 24),
              Text(
                'Request sent',
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
              ),
              const SizedBox(height: 12),
              Text(
                "Your request has been sent to the library admin. They typically verify the payment and confirm your seat within 24 hours. You'll be notified once it's approved.",
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
                    // Go to the member home dashboard (clear the join/profile
                    // stack) rather than popping back to the library profile.
                    Navigator.of(context).pushNamedAndRemoveUntil(
                        '/member/home', (route) => false);
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
