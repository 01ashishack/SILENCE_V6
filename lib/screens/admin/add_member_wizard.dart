import 'dart:io';
import '../../theme/app_palette.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/member_draft.dart';
import '../../models/member_data.dart';
import '../../services/draft_service.dart';
import '../../core/image_optimizer.dart';
import '../../utils/error_messages.dart';
import '../../core/app_snackbar.dart';
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

      if (!mounted) return;
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
        backgroundColor: context.palette.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Exit Wizard?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
        content: Text(
          'Do you want to save this member registration as a draft to resume later?',
          style: GoogleFonts.inter(fontSize: 14, color: context.palette.textSecondary),
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
      if (_memberData.idProof1Url == null && _memberData.idProof1File == null) {
        _showErrorSnackBar('Front side of the ID is required.');
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
    if (!mounted) return;
    AppSnackbar.error(context, message);
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
    // Add whole months, capping the day to the target month's last day so
    // e.g. Jan 31 + 1 month = Feb 28/29 (not an overflowed Mar 3).
    final y = start.year + ((start.month - 1 + durationMonths) ~/ 12);
    final m = (start.month - 1 + durationMonths) % 12 + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, start.day > lastDay ? lastDay : start.day);
  }

  Future<String?> _uploadFileToStorage(File file, String subFolder) async {
    final bytes = await ImageOptimizer.compressImage(file.path);
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last.split('\\').last}';
    final path = 'library_members/$_libraryId/$subFolder/$fileName';

    await _supabase.storage.from('silence_private').uploadBinary(
      path,
      Uint8List.fromList(bytes),
      fileOptions: const FileOptions(
        contentType: 'image/jpeg',
        upsert: true,
      ),
    );

    return path;
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
    // Names the DB write currently in flight so a permission/RLS rejection can
    // be pinned to the exact operation (memberships / seat / payment) instead of
    // collapsing to a single opaque "You don't have permission" message.
    String opLabel = 'preparing';
    try {
      // Guard: every owner-scoped write below (membership, seat, payment) checks
      // that auth.uid() OWNS this library. If _libraryId was passed in via route
      // args without being verified against the signed-in admin's owned
      // libraries, ALL of them fail with RLS 42501 ("permission") AFTER a
      // half-created member. Fail fast with an honest message instead.
      final ownsLibrary = _ownedLibraries.any((l) => l['id'] == _libraryId);
      if (_libraryId.isEmpty || (_ownedLibraries.isNotEmpty && !ownsLibrary)) {
        setState(() => _isLoading = false);
        _showErrorSnackBar(
          'This library isn\'t linked to your account, so members can\'t be '
          'added to it. Please pick one of your own libraries and try again.',
        );
        return;
      }

      // 1. Look up or insert user by phone or email. For a NEW member we insert
      // the basic profile now; the photo / ID documents are written LATER (step
      // 4), AFTER the membership exists. RLS only lets an owner update a user
      // who is a member of one of their libraries, so writing the member's
      // photo/ID before the membership would be silently rejected — which is why
      // those used to never persist (see
      // migrations/2026-06-12_users_owner_update_rls.sql).
      // Owner-only server-side resolver (replaces a broad cross-library
      // users.select; see migrations/2026-06-12_rpc_find_user_by_contact.sql).
      // Resolve an existing account. The RPC is an owner-scoped PII guard; if it
      // is unavailable or rejects (e.g. not yet applied, or an ownership edge),
      // do NOT hard-fail the whole add — fall back to "no match found" and let
      // the users-table unique constraint catch a genuine duplicate with an
      // honest message, instead of a blanket "permission" error.
      List<dynamic> lookupList = const [];
      try {
        final lookupRows = await _supabase.rpc(
          'find_user_by_contact',
          params: {
            'p_phone': _memberData.phone,
            'p_email': _memberData.email,
          },
        );
        lookupList = lookupRows is List ? lookupRows : const [];
      } catch (e) {
        debugPrint('find_user_by_contact failed; proceeding without autofill: $e');
      }
      final Map<String, dynamic>? userObj = lookupList.isNotEmpty
          ? Map<String, dynamic>.from(lookupList.first as Map)
          : null;

      final bool isExistingUser = userObj != null;
      String memberUserId;
      if (userObj == null) {
        opLabel = 'creating the member profile';
        // Generate the new member's id CLIENT-SIDE and insert WITHOUT a
        // RETURNING clause (no .select()).
        //
        // WHY: the users SELECT policy is tenant-scoped
        // ("Admins can view library members",
        // migrations/2026-06-14_users_select_tenant_scope.sql) — an owner may
        // read a user only once that user is a MEMBER (or pending applicant) of
        // one of their libraries. A brand-new member has no membership yet (it
        // is created in the next step), so `INSERT ... RETURNING id` is rejected
        // by RLS with 42501 "new row violates row-level security policy": the
        // INSERT itself is allowed, but Postgres cannot return a row the owner
        // is not yet permitted to SELECT. Supplying our own id removes the need
        // to read the row back, so no RETURNING / SELECT visibility is required.
        memberUserId = const Uuid().v4();
        await _supabase.from('users').insert({
          'id': memberUserId,
          'full_name': _memberData.name,
          'nickname': _memberData.name.split(' ').first,
          'phone': _memberData.phone,
          'email': _memberData.email.isEmpty ? null : _memberData.email,
          'gender': _memberData.gender,
          'date_of_birth': _memberData.dob?.toIso8601String().substring(0, 10),
          'address': _memberData.address,
          'exam_category': _memberData.preparingFor,
          'role': 'member',
        });
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
                backgroundColor: context.palette.surface,
                surfaceTintColor: Colors.transparent,
                title: Text('Active Membership Found', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.red)),
                content: Text(
                  'This member already has an active membership in this library. Please renew or exit the existing membership before adding a new one.',
                  style: GoogleFonts.inter(fontSize: 14, color: context.palette.textSecondary),
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
        // An existing member's detail refresh is also deferred to step 4 (it is
        // an UPDATE on their row, which the same RLS link gates).
      }

      // 2. Create the membership FIRST. The membership is what links this member
      // to the owner's library, and the users-table owner-update RLS policy
      // checks for exactly that link before allowing the photo / ID writes below.
      final startStr = _calculatedPlanStart.toIso8601String().substring(0, 10);
      final endStr = _calculatedExpiry.toIso8601String().substring(0, 10);

      opLabel = 'creating the membership';
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

      // 3. Occupy the seat immediately after the membership is created, BEFORE
      // the payment insert. If payment ever fails, the seat/membership stay in
      // sync (no "assigned but shows vacant"); the layout grid also self-heals.
      if (_memberData.selectedSeatId != null) {
        opLabel = 'assigning the seat';
        await _supabase.from('seats').update({
          'status': 'occupied',
          'occupied_by_member_id': memberUserId,
        }).eq('id', _memberData.selectedSeatId!);
        occupiedSeatId = _memberData.selectedSeatId;
      }

      // 4. Persist the member's photo, ID documents, and (existing member only)
      // refreshed contact details. The membership above grants RLS access to
      // this member's row. Best-effort: a media/upload hiccup must NOT roll back
      // an otherwise valid (and paid) registration — the admin can re-upload
      // from the member's profile later.
      final mediaFailures = await _writeMemberProfile(memberUserId, refreshDetails: isExistingUser);

      // 5. Create payment record
      opLabel = 'recording the payment';
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

      // 6. Delete draft if loaded
      if (_draftId != null) {
        await DraftService.instance.deleteDraft(_draftId!, _libraryId);
      }

      if (mounted) {
        // Honest: the member IS added, but flag any best-effort media that
        // didn't attach so the admin can re-upload from the profile later.
        if (mediaFailures.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Member added successfully ✓'), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Member added ✓ — but ${mediaFailures.join(' & ')} couldn\'t be saved. '
                  'You can add it later from the member\'s profile.'),
              backgroundColor: const Color(0xFFF59E0B),
              duration: const Duration(seconds: 5),
            ),
          );
        }

        // A manually-added member has no app account yet, so no in-app
        // notification can reach them. Offer the admin a one-tap WhatsApp
        // share with all their membership details instead. Awaited so the
        // wizard stays open until the admin dismisses the sheet.
        await _showWhatsAppShareSheet(
          startStr: startStr,
          endStr: endStr,
          finalPrice: finalPrice,
        );

        // Close the wizard and signal members_sub_tab to refresh the member list.
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      // Log the exact exception (incl. PostgREST/RLS details) AND which write
      // was in flight — do not swallow. A 42501 here almost always means a
      // missing owner-scoped RLS policy on that specific table (e.g. the
      // payments admin-insert policy: migrations/2026-06-12_payments_admin_insert_rls.sql).
      final pgCode = e is PostgrestException ? (e.code ?? '') : '';
      if (e is PostgrestException) {
        debugPrint('Error finalizing registration while "$opLabel": '
            'code=${e.code} | message=${e.message} | details=${e.details} | hint=${e.hint}');
      } else {
        debugPrint('Error finalizing registration while "$opLabel": $e');
      }
      // Capture the auth/tenant context at the moment of failure — this tells us
      // whether the RLS rejection is a missing policy vs. a null/expired
      // auth.uid() vs. a library the signed-in user does not actually own.
      final session = _supabase.auth.currentSession;
      final nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      debugPrint('AUTH/TENANT @ failure: uid=${_supabase.auth.currentUser?.id} '
          'hasSession=${session != null} '
          'sessionExpired=${session?.expiresAt != null ? session!.expiresAt! < nowSecs : 'n/a'} '
          'libraryId=$_libraryId '
          'ownedLibraryIds=${_ownedLibraries.map((l) => l['id']).toList()}');
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
        // For a permission/RLS rejection, name the blocked step so the cause is
        // actionable instead of an opaque "permission" message.
        final isPermission = pgCode == '42501' ||
            (e is PostgrestException &&
                (e.message.toLowerCase().contains('row-level security') ||
                    e.message.toLowerCase().contains('permission')));
        final expired = session == null ||
            (session.expiresAt != null && session.expiresAt! < nowSecs);
        _showErrorSnackBar(
          isPermission
              ? (expired
                  ? 'Your login session has expired. Please sign out and sign in '
                      'again, then retry adding the member.'
                  : 'Permission denied while $opLabel. Please retry; if it keeps '
                      'happening, the database access rules for this step need to be applied.')
              : friendlyError(e),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Builds the membership summary text and offers a one-tap WhatsApp share.
  /// A manually-added member has no app account, so this is the honest way to
  /// communicate their seat/shift/plan/dates to them.
  Future<void> _showWhatsAppShareSheet({
    required String startStr,
    required String endStr,
    required int finalPrice,
  }) async {
    final libName = _libraryName ?? 'Silence Library';
    final memberName = _memberData.name.trim().isEmpty ? 'Member' : _memberData.name.trim();
    final shift = _memberData.selectedShiftName.trim().isEmpty ? '—' : _memberData.selectedShiftName.trim();
    final seat = (_memberData.selectedSeatLabel ?? '').trim().isEmpty ? 'Not assigned' : _memberData.selectedSeatLabel!.trim();
    final plan = _memberData.planType.isEmpty ? 'monthly' : _memberData.planType;
    final joining = _memberData.joiningDate.toIso8601String().substring(0, 10);
    final payLine = _memberData.paymentFlow == 'paid'
        ? 'Payment: ₹$finalPrice (Paid)'
        : 'Payment: ₹$finalPrice (Pending — please pay to confirm)';

    final message = '🙏 Welcome to $libName!\n\n'
        'Aapki membership add kar di gayi hai. Details:\n\n'
        '👤 Name: $memberName\n'
        '🪑 Seat: $seat\n'
        '🕒 Shift: $shift\n'
        '📋 Plan: $plan\n'
        '📅 Joining: $joining\n'
        '📆 Valid: $startStr → $endStr\n'
        '💳 $payLine\n\n'
        'Apni attendance aur details app me dekhne ke liye SILENCE app download karein.\n\n'
        '— $libName';

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Member added — share details?',
                      style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Yeh member app par nahi hai, isliye unhe membership details WhatsApp par bhej sakte hain.',
                style: GoogleFonts.inter(fontSize: 12.5, color: context.palette.textSecondary),
              ),
              const SizedBox(height: 14),
              // Preview of the message
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.palette.scaffold,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.palette.border),
                ),
                child: Text(
                  message,
                  style: GoogleFonts.inter(fontSize: 12, color: context.palette.textPrimary, height: 1.45),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _launchWhatsAppShare(_memberData.phone, message),
                  icon: const Icon(Icons.chat, size: 18),
                  label: const Text('Share via WhatsApp'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: Text(
                    'Skip',
                    style: GoogleFonts.inter(color: context.palette.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Launches WhatsApp with the prefilled message. If the member's phone is a
  /// plain 10-digit Indian number, prefix country code 91 so the chat opens
  /// directly; otherwise fall back to wa.me without a number (user picks chat).
  Future<void> _launchWhatsAppShare(String rawPhone, String message) async {
    final messenger = ScaffoldMessenger.of(context);
    final encoded = Uri.encodeComponent(message);
    final digits = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    String phonePart = '';
    if (digits.length == 10) {
      phonePart = '91$digits';
    } else if (digits.length > 10) {
      phonePart = digits;
    }

    final uri = Uri.parse(
      phonePart.isNotEmpty
          ? 'https://wa.me/$phonePart?text=$encoded'
          : 'https://wa.me/?text=$encoded',
    );

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp. Is it installed?')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  /// Writes the member's profile photo, ID documents, and (for an existing
  /// member) refreshed contact details to their `users` row. Called AFTER the
  /// membership exists so the owner-update RLS policy applies (see
  /// migrations/2026-06-12_users_owner_update_rls.sql). Every write is
  /// independent and swallowed — a single media/upload failure must not abort a
  /// valid registration; without the RLS migration applied these silently
  /// no-op (the member is still added, just without the media).
  /// Returns the labels of any best-effort writes that FAILED (e.g. ['photo',
  /// 'ID documents']) so the caller can honestly tell the admin what didn't
  /// attach — the member is still added regardless.
  Future<List<String>> _writeMemberProfile(String memberUserId, {required bool refreshDetails}) async {
    final failed = <String>[];
    // Refresh an existing member's contact details (deferred from step 1).
    if (refreshDetails) {
      try {
        await _supabase.from('users').update({
          'full_name': _memberData.name,
          'email': _memberData.email.isEmpty ? null : _memberData.email,
          'gender': _memberData.gender,
          'date_of_birth': _memberData.dob?.toIso8601String().substring(0, 10),
          'address': _memberData.address,
          'exam_category': _memberData.preparingFor,
        }).eq('id', memberUserId);
      } catch (e) {
        debugPrint('Existing-member detail refresh skipped: $e');
        failed.add('contact details');
      }
    }

    // Profile photo → public silence_assets bucket; store the public URL.
    String? photoUrl = _memberData.existingPhotoUrl?.trim();
    bool photoFailed = false;
    if (_memberData.profilePhoto != null) {
      try {
        photoUrl = await _uploadProfilePhoto(_memberData.profilePhoto!, memberUserId);
      } catch (e) {
        debugPrint('Profile photo upload skipped: $e');
        photoFailed = true;
      }
    }
    if (photoUrl != null && photoUrl.isNotEmpty) {
      try {
        await _supabase.from('users').update({
          'photo_url': photoUrl,
        }).eq('id', memberUserId);
      } catch (e) {
        debugPrint('Profile photo save skipped: $e');
        photoFailed = true;
      }
    }
    if (photoFailed) failed.add('photo');

    // ID documents → private silence_private bucket; store the storage path
    // (member_detail resolves a short-lived signed URL to display them).
    String? docUrl1;
    String? docUrl2;
    bool idFailed = false;
    try {
      // Front/Back are uploaded immediately in step 1, so reuse those storage
      // paths; only fall back to uploading here for older drafts that still
      // carry a local file without a URL.
      if (_memberData.idProof1Url != null) {
        docUrl1 = _memberData.idProof1Url;
      } else if (_memberData.idProof1File != null) {
        docUrl1 = await _uploadFileToStorage(_memberData.idProof1File!, 'documents');
      }
      if (_memberData.idProof2Url != null) {
        docUrl2 = _memberData.idProof2Url;
      } else if (_memberData.idProof2File != null) {
        docUrl2 = await _uploadFileToStorage(_memberData.idProof2File!, 'documents');
      }
    } catch (e) {
      debugPrint('ID document upload skipped: $e');
      idFailed = true;
    }
    if (docUrl1 != null) {
      try {
        await _supabase.from('users').update({
          'id_proof_url': docUrl1,
        }).eq('id', memberUserId);
      } catch (e) {
        debugPrint('ID proof save skipped: $e');
        idFailed = true;
      }
    }
    final optionalUserFields = <String, dynamic>{};
    if (_memberData.idProof1Type != null) {
      optionalUserFields['id_type'] = _memberData.idProof1Type;
    }
    if (docUrl2 != null) {
      optionalUserFields['id_proof_2_url'] = docUrl2;
    }
    await _updateOptionalUserFields(memberUserId, optionalUserFields);
    if (idFailed) failed.add('ID documents');
    return failed;
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

  Future<void> _updateOptionalUserFields(String memberUserId, Map<String, dynamic> fields) async {
    for (final entry in fields.entries) {
      try {
        await _supabase.from('users').update({entry.key: entry.value}).eq('id', memberUserId);
      } catch (e) {
        debugPrint('Optional user field ${entry.key} update skipped: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && !_initialized) {
      return Scaffold(
        backgroundColor: context.palette.scaffold,
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
        libraryId: _libraryId,
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
        // Hardware/gesture back: step back through the wizard; only exit (with a
        // save-draft prompt) from the first step.
        if (_currentStep > 0) {
          _pageController.previousPage(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        } else {
          _showExitDraftPrompt();
        }
      },
      child: Scaffold(
        backgroundColor: context.palette.scaffold,
        appBar: AppBar(
          backgroundColor: const Color(0xFFE65C00),
          // Top-left back: previous step when not on the first page (was exiting
          // the whole wizard); on the first page it offers save-draft / exit.
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_currentStep > 0) {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                );
              } else {
                _showExitDraftPrompt();
              }
            },
          ),
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
                  backgroundColor: const Color(0x33E65C00),
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
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(top: BorderSide(color: context.palette.border)),
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
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: context.palette.textMuted),
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
      color: context.palette.scaffold,
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
                      color: context.palette.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please select the library branch where the member wants to register.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: context.palette.textMuted,
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
                          color: context.palette.surface,
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
                                  color: context.palette.textPrimary,
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
            decoration: BoxDecoration(
              color: context.palette.surface,
              border: Border(top: BorderSide(color: context.palette.border)),
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
