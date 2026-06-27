import 'dart:io';
import '../../theme/app_palette.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/calendar_picker.dart';
import '../../core/image_optimizer.dart';
import '../../models/member_data.dart';
import '../../services/draft_service.dart';
import '../../models/member_draft.dart';



class AddMemberStep1 extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final MemberData memberData;
  final String libraryId;
  final String? currentDraftId;
  final Function(String) onDraftSelected;
  final Function(Map<String, dynamic>) onAutofillDetails;

  const AddMemberStep1({
    super.key,
    required this.formKey,
    required this.memberData,
    required this.libraryId,
    required this.currentDraftId,
    required this.onDraftSelected,
    required this.onAutofillDetails,
  });

  @override
  State<AddMemberStep1> createState() => _AddMemberStep1State();
}

class _AddMemberStep1State extends State<AddMemberStep1> with AutomaticKeepAliveClientMixin {
  final _supabase = Supabase.instance.client;
  Timer? _debounce;
  final _picker = ImagePicker();
  bool _isPhotoUploading = false;
  bool _isId1Uploading = false;
  bool _isId2Uploading = false;

  late final TextEditingController _nameController;
  late final TextEditingController _fatherNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.memberData.name);
    _fatherNameController = TextEditingController(text: widget.memberData.fatherName);
    _phoneController = TextEditingController(text: widget.memberData.phone);
    _emailController = TextEditingController(text: widget.memberData.email);
    _addressController = TextEditingController(text: widget.memberData.address);

    _nameController.addListener(() => widget.memberData.name = _nameController.text.trim());
    _fatherNameController.addListener(() => widget.memberData.fatherName = _fatherNameController.text.trim());
    _phoneController.addListener(() => widget.memberData.phone = _phoneController.text.trim());
    _emailController.addListener(() => widget.memberData.email = _emailController.text.trim());
    _addressController.addListener(() => widget.memberData.address = _addressController.text.trim());
  }

  @override
  void didUpdateWidget(covariant AddMemberStep1 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.memberData.name != _nameController.text) {
      _nameController.text = widget.memberData.name;
    }
    if (widget.memberData.fatherName != _fatherNameController.text) {
      _fatherNameController.text = widget.memberData.fatherName;
    }
    if (widget.memberData.phone != _phoneController.text) {
      _phoneController.text = widget.memberData.phone;
    }
    if (widget.memberData.email != _emailController.text) {
      _emailController.text = widget.memberData.email;
    }
    if (widget.memberData.address != _addressController.text) {
      _addressController.text = widget.memberData.address;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _fatherNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onEmailChanged(String email) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final emailVal = email.trim();
      if (emailVal.isNotEmpty && emailVal.contains('@')) {
        _checkDraftAndUser(emailVal, isPhone: false);
      }
    });
  }

  void _onPhoneChanged(String phone) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final phoneVal = phone.trim();
      if (phoneVal.length == 10) {
        _checkDraftAndUser(phoneVal, isPhone: true);
      }
    });
  }

  Future<void> _checkDraftAndUser(String value, {required bool isPhone}) async {
    try {
      final queryVal = value.trim();
      if (queryVal.isEmpty) return;

      // 1. Check if a draft exists for same phone/email in draft_members
      final drafts = await DraftService.instance.getDrafts(widget.libraryId);
      final existingDraft = drafts.firstWhere(
        (d) {
          if (widget.currentDraftId != null && d.id == widget.currentDraftId) return false;
          final dPhone = d.draftData['phone']?.toString().trim();
          final dEmail = d.draftData['email']?.toString().trim();
          if (isPhone) {
            return dPhone == queryVal;
          } else {
            return dEmail?.toLowerCase() == queryVal.toLowerCase();
          }
        },
        orElse: () => MemberDraft(id: null, adminId: '', libraryId: '', draftData: {}),
      );

      if (existingDraft.id != null && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: context.palette.surface,
            surfaceTintColor: Colors.transparent,
            title: Text('Draft Registration Found', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
            content: Text(
              'A draft registration exists for this member. Do you want to continue that draft or delete it and create a new one?',
              style: GoogleFonts.inter(fontSize: 14, color: context.palette.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  // Delete the draft
                  setState(() => _isPhotoUploading = true);
                  try {
                    await DraftService.instance.deleteDraft(existingDraft.id!, widget.libraryId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Existing draft deleted successfully ✓')),
                      );
                    }
                    // After deleting, look up if a user exists
                    if (isPhone) {
                      _lookupUserByPhone(queryVal);
                    } else {
                      _lookupUserByEmail(queryVal);
                    }
                  } catch (e) {
                    debugPrint('Error deleting draft: $e');
                  } finally {
                    if (mounted) setState(() => _isPhotoUploading = false);
                  }
                },
                child: Text('Delete & New', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.red)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.onDraftSelected(existingDraft.id!);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  elevation: 0,
                ),
                child: Text('Continue Draft', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
        );
        return;
      }

      // 2. If no draft exists, check if user exists in users table
      if (isPhone) {
        _lookupUserByPhone(queryVal);
      } else {
        _lookupUserByEmail(queryVal);
      }
    } catch (e) {
      debugPrint('Error in _checkDraftAndUser: $e');
    }
  }

  Future<void> _lookupUserByEmail(String email) async {
    try {
      // Owner-only server-side resolver (replaces a broad cross-library
      // users.select; see migrations/2026-06-12_rpc_find_user_by_contact.sql).
      final rows = await _supabase.rpc(
        'find_user_by_contact',
        params: {'p_email': email},
      );
      final list = rows is List ? rows : const [];
      final userObj = list.isNotEmpty
          ? Map<String, dynamic>.from(list.first as Map)
          : null;

      if (userObj != null && mounted) {
        // Query memberships to check if they already have an active/trial/hold membership
        final activeMemberships = await _supabase
            .from('memberships')
            .select('id')
            .eq('member_id', userObj['id'])
            .eq('library_id', widget.libraryId)
            .inFilter('status', ['active', 'trial', 'hold']);

        if (activeMemberships.isNotEmpty) {
          if (mounted) {
            _emailController.clear();
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

        _showAutofillBottomSheet(userObj, isPhone: false);
      } else if (userObj == null && mounted) {
        await _blockIfContactReserved(email: email);
      }
    } catch (e) {
      debugPrint('Error looking up email: $e');
    }
  }

  Future<void> _lookupUserByPhone(String phone) async {
    try {
      // Owner-only server-side resolver (replaces a broad cross-library
      // users.select; see migrations/2026-06-12_rpc_find_user_by_contact.sql).
      final rows = await _supabase.rpc(
        'find_user_by_contact',
        params: {'p_phone': phone},
      );
      final list = rows is List ? rows : const [];
      final userObj = list.isNotEmpty
          ? Map<String, dynamic>.from(list.first as Map)
          : null;

      if (userObj != null && mounted) {
        // Query memberships to check if they already have an active/trial/hold membership
        final activeMemberships = await _supabase
            .from('memberships')
            .select('id')
            .eq('member_id', userObj['id'])
            .eq('library_id', widget.libraryId)
            .inFilter('status', ['active', 'trial', 'hold']);

        if (activeMemberships.isNotEmpty) {
          if (mounted) {
            _phoneController.clear();
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

        _showAutofillBottomSheet(userObj, isPhone: true);
      } else if (userObj == null && mounted) {
        await _blockIfContactReserved(phone: phone);
      }
    } catch (e) {
      debugPrint('Error looking up phone: $e');
    }
  }

  /// Blocks reusing a contact that belongs to an ADMIN / library-owner account.
  /// Existing MEMBERS are handled by find_user_by_contact (autofill); this only
  /// catches the admin/owner case the resolver deliberately hides, so a member
  /// can never be registered on an admin's email/phone. Best-effort: if the
  /// contact_in_use RPC isn't applied yet, this fails open (the users UNIQUE
  /// constraint still blocks an actual duplicate at insert time).
  Future<void> _blockIfContactReserved({String? email, String? phone}) async {
    final isEmail = email != null && email.trim().isNotEmpty;
    final isPhone = phone != null && phone.trim().isNotEmpty;
    if (!isEmail && !isPhone) return;
    try {
      final params = <String, dynamic>{};
      if (isEmail) params['p_email'] = email.trim();
      if (isPhone) params['p_phone'] = phone.trim();

      final res = await _supabase.rpc('contact_in_use', params: params);
      if (res == true && mounted) {
        if (isEmail) {
          _emailController.clear();
          widget.memberData.email = '';
        } else {
          _phoneController.clear();
          widget.memberData.phone = '';
        }
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: context.palette.surface,
            surfaceTintColor: Colors.transparent,
            title: Text('Already Registered',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.red)),
            content: Text(
              'This ${isEmail ? 'email' : 'phone number'} is already registered to '
              'another account and cannot be used to add a member. Please use a '
              'different ${isEmail ? 'email' : 'number'}.',
              style: GoogleFonts.inter(fontSize: 14, color: context.palette.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('OK',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('contact_in_use check skipped: $e');
    }
  }

  void _showAutofillBottomSheet(Map<String, dynamic> userObj, {bool isPhone = false}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Existing User Found',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.palette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A user with this ${isPhone ? 'phone number' : 'email'} already exists in the system:\n'
              '• Name: ${userObj['full_name'] ?? 'N/A'}\n'
              '• Phone: ${userObj['phone'] ?? 'N/A'}\n'
              '• Email: ${userObj['email'] ?? 'N/A'}\n\n'
              'Do you want to link this membership to the existing user?',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: context.palette.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Skip',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: context.palette.textMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _autofillDetails(userObj);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: Text(
                      'Link & Copy',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _autofillDetails(Map<String, dynamic> userObj) {
    setState(() {
      _nameController.text = userObj['full_name'] ?? '';
      _phoneController.text = userObj['phone'] ?? '';
      _emailController.text = userObj['email'] ?? '';
      widget.memberData.gender = userObj['gender'];
      if (userObj['date_of_birth'] != null) {
        widget.memberData.dob = DateTime.tryParse(userObj['date_of_birth']);
      }
      _addressController.text = userObj['address'] ?? '';
      widget.memberData.preparingFor = userObj['exam_category'];
      widget.memberData.existingPhotoUrl = userObj['photo_url'];
    });
    widget.onAutofillDetails(userObj);
    // Re-validate fields after autofill
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.formKey.currentState?.validate();
    });
  }

  Future<void> _pickImage(bool isProfile, {bool isId1 = false, bool isId2 = false}) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: context.palette.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    // permission_handler, image_cropper and camera capture are MOBILE-ONLY
    // plugins — on Windows/macOS/Linux desktop (and web) they have no platform
    // implementation and throw a MissingPluginException, which is what
    // force-closed the app while testing on Windows. Only run that path on
    // Android/iOS; everywhere else fall straight through to image_picker's file
    // selection (works for gallery on desktop) and skip cropping.
    final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    if (isMobile) {
      if (source == ImageSource.camera) {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Camera permission is required to take photos.')),
            );
          }
          return;
        }
      } else if (source == ImageSource.gallery) {
        final photoStatus = await Permission.photos.request();
        if (!photoStatus.isGranted && !photoStatus.isLimited) {
          final storageStatus = await Permission.storage.request();
          if (!storageStatus.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Gallery/Storage permission is required to select photos.')),
              );
            }
            return;
          }
        }
      }
    }

    XFile? pickedFile;
    try {
      pickedFile = await _picker.pickImage(source: source, maxWidth: 1024, imageQuality: 85);
    } catch (e) {
      // Most commonly on desktop: camera capture isn't available, or the
      // platform's image_picker isn't wired up. Don't crash — tell the user.
      debugPrint('pickImage failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(source == ImageSource.camera
              ? 'Camera capture isn\'t supported on this device — choose from gallery/files instead.'
              : 'Could not open the file picker on this device.')),
        );
      }
      return;
    }
    if (pickedFile == null) return;

    File? processedFile;
    if (kIsWeb || !isMobile) {
      // No native cropper on web/desktop — use the picked file as-is.
      processedFile = File(pickedFile.path);
    } else {
      CroppedFile? croppedFile;
      bool cropSuccessOrCancel = false;
      try {
        croppedFile = await ImageCropper().cropImage(
          sourcePath: pickedFile.path,
          aspectRatio: isProfile ? const CropAspectRatio(ratioX: 1, ratioY: 1) : null,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: isProfile ? 'Crop Profile Photo' : 'Crop Document',
              toolbarColor: const Color(0xFFE65C00),
              toolbarWidgetColor: Colors.white,
              initAspectRatio: isProfile ? CropAspectRatioPreset.square : CropAspectRatioPreset.original,
              lockAspectRatio: isProfile,
              cropStyle: isProfile ? CropStyle.circle : CropStyle.rectangle,
            ),
            IOSUiSettings(
              title: isProfile ? 'Crop Profile Photo' : 'Crop Document',
              aspectRatioLockEnabled: isProfile,
              cropStyle: isProfile ? CropStyle.circle : CropStyle.rectangle,
            ),
          ],
        );
        cropSuccessOrCancel = true;
      } catch (e) {
        debugPrint('Crop failed, falling back to original: $e');
      }

      if (cropSuccessOrCancel && croppedFile == null) return; // User actively cancelled cropping

      processedFile = File(croppedFile?.path ?? pickedFile.path);
    }



    if (isProfile) {
      setState(() {
        widget.memberData.profilePhoto = processedFile;
        _isPhotoUploading = true;
      });

      try {
        final compressedBytes = kIsWeb
            ? await pickedFile.readAsBytes()
            : await ImageOptimizer.compressImage(processedFile.path);

        final path = 'member_profiles/${widget.memberData.tempId}/profile.jpg';

        await _supabase.storage.from('silence_assets').uploadBinary(
          path,
          Uint8List.fromList(compressedBytes),
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
        if (!mounted) return;

        final publicUrl = _supabase.storage.from('silence_assets').getPublicUrl(path);
        setState(() {
          widget.memberData.existingPhotoUrl = publicUrl;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile photo uploaded successfully ✓'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        debugPrint('Error uploading profile photo: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upload profile photo: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isPhotoUploading = false;
          });
        }
      }
    } else {
      // ID document — upload immediately so the admin gets an honest, visible
      // confirmation (with a circular progress indicator) that it's actually
      // stored, instead of only being captured locally and uploaded later.
      setState(() {
        if (isId1) {
          widget.memberData.idProof1File = processedFile;
          widget.memberData.idProof1Url = null;
          _isId1Uploading = true;
        } else if (isId2) {
          widget.memberData.idProof2File = processedFile;
          widget.memberData.idProof2Url = null;
          _isId2Uploading = true;
        }
      });

      try {
        final compressedBytes = kIsWeb
            ? await pickedFile.readAsBytes()
            : await ImageOptimizer.compressImage(processedFile.path);

        final slot = isId1 ? 'front' : 'back';
        final path =
            'library_members/${widget.libraryId}/documents/${widget.memberData.tempId}_$slot.jpg';

        await _supabase.storage.from('silence_private').uploadBinary(
          path,
          Uint8List.fromList(compressedBytes),
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
        if (!mounted) return;

        setState(() {
          if (isId1) {
            widget.memberData.idProof1Url = path;
          } else if (isId2) {
            widget.memberData.idProof2Url = path;
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ID uploaded successfully ✓'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        debugPrint('Error uploading ID document: $e');
        if (!mounted) return;
        // Honest failure: clear the captured file so the slot doesn't look done.
        setState(() {
          if (isId1) {
            widget.memberData.idProof1File = null;
            widget.memberData.idProof1Url = null;
          } else if (isId2) {
            widget.memberData.idProof2File = null;
            widget.memberData.idProof2Url = null;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload ID: $e'), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) {
          setState(() {
            if (isId1) {
              _isId1Uploading = false;
            } else if (isId2) {
              _isId2Uploading = false;
            }
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: context.palette.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE65C00), width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.red[600]!, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.red[600]!, width: 1.5),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
          ),
          labelStyle: GoogleFonts.inter(color: context.palette.textMuted, fontSize: 14),
          hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 14),
        ),
      ),
      child: Form(
        key: widget.formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mode indicator (Hidden)
              const SizedBox.shrink(),

              // Profile Photo Slot
              Center(
                child: GestureDetector(
                  onTap: _isPhotoUploading ? null : () => _pickImage(true),
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 54,
                        backgroundColor: context.palette.surface,
                        backgroundImage: widget.memberData.profilePhoto != null
                            ? (kIsWeb ? NetworkImage(widget.memberData.profilePhoto!.path) : FileImage(widget.memberData.profilePhoto!) as ImageProvider)
                            : (widget.memberData.existingPhotoUrl != null
                                ? NetworkImage(widget.memberData.existingPhotoUrl!)
                                : null),
                        child: _isPhotoUploading
                            ? const CircularProgressIndicator(color: Color(0xFFE65C00))
                            : (widget.memberData.profilePhoto == null && widget.memberData.existingPhotoUrl == null
                                ? Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.add_a_photo, size: 36, color: Color(0xFFE65C00)),
                                    ),
                                  )
                                : null),
                      ),
                      if (!_isPhotoUploading)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFFE65C00),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.edit, color: Colors.white, size: 16),
                          ),
                        )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Full Name Field
              TextFormField(
                controller: _nameController,
                style: GoogleFonts.inter(color: context.palette.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  hintText: 'Enter full name',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Full Name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Father's Name Field
              TextFormField(
                controller: _fatherNameController,
                style: GoogleFonts.inter(color: context.palette.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Father\'s Name',
                  hintText: 'Enter father\'s name',
                ),
              ),
              const SizedBox(height: 16),

              // DOB calendar picker
              FormField<DateTime>(
                initialValue: widget.memberData.dob,
                validator: (val) {
                  if (widget.memberData.dob == null) {
                    return 'Date of Birth is required';
                  }
                  return null;
                },
                builder: (formFieldState) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () async {
                          final selected = await showCalendarGridBottomSheet(
                            context,
                            initialDate: widget.memberData.dob ?? DateTime(2000, 1, 1),
                            firstDate: DateTime(1950),
                            lastDate: DateTime.now(),
                          );
                          if (!mounted) return;
                          if (selected != null) {
                            setState(() {
                              widget.memberData.dob = selected;
                              formFieldState.didChange(selected);
                            });
                          }
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Date of Birth *',
                            suffixIcon: const Icon(Icons.calendar_today, size: 20, color: Color(0xFF64748B)),
                            errorText: formFieldState.errorText,
                          ),
                          child: Text(
                            widget.memberData.dob != null
                                ? '${widget.memberData.dob!.day}/${widget.memberData.dob!.month}/${widget.memberData.dob!.year}'
                                : 'Select date of birth',
                            style: GoogleFonts.inter(
                              color: widget.memberData.dob != null ? context.palette.textPrimary : const Color(0xFF94A3B8),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),

              // Gender Dropdown
              DropdownButtonFormField<String>(
                initialValue: widget.memberData.gender,
                decoration: const InputDecoration(labelText: 'Gender *'),
                style: GoogleFonts.inter(color: context.palette.textPrimary, fontSize: 14),
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(14),
                items: const [
                  DropdownMenuItem(value: 'male', child: Text('Male')),
                  DropdownMenuItem(value: 'female', child: Text('Female')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (val) {
                  setState(() {
                    widget.memberData.gender = val;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Gender is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Email address with onChanges debounced lookup
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: GoogleFonts.inter(color: context.palette.textPrimary),
                onChanged: _onEmailChanged,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  hintText: 'name@example.com (autofills if user exists)',
                ),
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty && !value.contains('@')) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Contact Number
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                style: GoogleFonts.inter(color: context.palette.textPrimary),
                onChanged: _onPhoneChanged,
                decoration: const InputDecoration(
                  labelText: 'Contact Number *',
                  prefixText: '+91 ',
                  hintText: '10 digit mobile number',
                  counterText: '',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Contact number is required';
                  }
                  if (value.trim().length != 10) {
                    return 'Contact number must be 10 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Address Field
              TextFormField(
                controller: _addressController,
                maxLines: 2,
                style: GoogleFonts.inter(color: context.palette.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Address *',
                  hintText: 'Enter full correspondence address',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Correspondence address is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Preparing For Dropdown
              DropdownButtonFormField<String>(
                initialValue: widget.memberData.preparingFor,
                decoration: const InputDecoration(labelText: 'Preparing For *'),
                style: GoogleFonts.inter(color: context.palette.textPrimary, fontSize: 14),
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(14),
                items: const [
                  DropdownMenuItem(value: 'UPSC', child: Text('UPSC')),
                  DropdownMenuItem(value: 'NEET', child: Text('NEET')),
                  DropdownMenuItem(value: 'JEE', child: Text('JEE')),
                  DropdownMenuItem(value: 'SSC', child: Text('SSC')),
                  DropdownMenuItem(value: 'Teacher', child: Text('Teacher')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (val) {
                  setState(() {
                    widget.memberData.preparingFor = val;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Preparing For field is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Joining Date picker
              FormField<DateTime>(
                initialValue: widget.memberData.joiningDate,
                builder: (formFieldState) {
                  return InkWell(
                    onTap: () async {
                       final selected = await showCalendarGridBottomSheet(
                        context,
                        initialDate: widget.memberData.joiningDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                       if (!mounted) return;
                      if (selected != null) {
                        setState(() {
                          widget.memberData.joiningDate = selected;
                          formFieldState.didChange(selected);
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Joining Date *',
                        suffixIcon: Icon(Icons.calendar_today_outlined, size: 20, color: Color(0xFF64748B)),
                      ),
                      child: Text(
                        '${widget.memberData.joiningDate.day}/${widget.memberData.joiningDate.month}/${widget.memberData.joiningDate.year}',
                        style: GoogleFonts.inter(color: context.palette.textPrimary, fontSize: 14),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // Upload ID header
              Text(
                'Upload ID',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: context.palette.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Add a clear photo of the member\'s ID. Front is required.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: context.palette.textMuted,
                ),
              ),
              const SizedBox(height: 14),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildIdTileLabel('Front', isRequired: true),
                        const SizedBox(height: 6),
                        _buildIdTile(
                          file: widget.memberData.idProof1File,
                          url: widget.memberData.idProof1Url,
                          uploading: _isId1Uploading,
                          onPick: () => _pickImage(false, isId1: true),
                          onClear: () {
                            setState(() {
                              widget.memberData.idProof1File = null;
                              widget.memberData.idProof1Url = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildIdTileLabel('Back', isRequired: false),
                        const SizedBox(height: 6),
                        _buildIdTile(
                          file: widget.memberData.idProof2File,
                          url: widget.memberData.idProof2Url,
                          uploading: _isId2Uploading,
                          onPick: () => _pickImage(false, isId2: true),
                          onClear: () {
                            setState(() {
                              widget.memberData.idProof2File = null;
                              widget.memberData.idProof2Url = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdTileLabel(String label, {required bool isRequired}) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.palette.textPrimary,
          ),
        ),
        if (isRequired)
          Text(
            ' *',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFE65C00),
            ),
          ),
      ],
    );
  }

  Widget _buildIdTile({
    required File? file,
    required String? url,
    required bool uploading,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    final bool done = file != null && url != null && !uploading;

    return AspectRatio(
      aspectRatio: 1,
      child: GestureDetector(
        onTap: (uploading || done) ? null : onPick,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0x1FE65C00),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: done ? const Color(0xFFFFB877) : const Color(0xFFFFD9B3),
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Local preview behind everything (shown while uploading & when done)
              if (file != null)
                kIsWeb
                    ? Image.network(file.path, fit: BoxFit.cover)
                    : Image.file(file, fit: BoxFit.cover),

              if (uploading) ...[
                Container(color: Colors.black.withValues(alpha: 0.45)),
                const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Uploading…',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ] else if (file == null) ...[
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFFFD9B3)),
                        ),
                        child: const Icon(Icons.add_a_photo_outlined, color: Color(0xFFE65C00), size: 22),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tap to upload',
                        style: GoogleFonts.inter(
                          color: const Color(0xFFE65C00),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Done — uploaded check badge + remove control
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                    child: const Icon(Icons.check, color: Colors.white, size: 14),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: onClear,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
