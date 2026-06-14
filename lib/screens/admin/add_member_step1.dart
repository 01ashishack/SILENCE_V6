import 'dart:io';
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
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            title: Text('Draft Registration Found', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
            content: Text(
              'A draft registration exists for this member. Do you want to continue that draft or delete it and create a new one?',
              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569)),
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
      final userObj = await _supabase
          .from('users')
          .select('id, full_name, phone, email, gender, date_of_birth, address, exam_category, photo_url')
          .eq('email', email)
          .maybeSingle();

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

        _showAutofillBottomSheet(userObj, isPhone: false);
      }
    } catch (e) {
      debugPrint('Error looking up email: $e');
    }
  }

  Future<void> _lookupUserByPhone(String phone) async {
    try {
      final userObj = await _supabase
          .from('users')
          .select('id, full_name, phone, email, gender, date_of_birth, address, exam_category, photo_url')
          .eq('phone', phone)
          .maybeSingle();

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

        _showAutofillBottomSheet(userObj, isPhone: true);
      }
    } catch (e) {
      debugPrint('Error looking up phone: $e');
    }
  }

  void _showAutofillBottomSheet(Map<String, dynamic> userObj, {bool isPhone = false}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
                color: const Color(0xFF1E293B),
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
                color: const Color(0xFF475569),
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
                        color: const Color(0xFF6B7280),
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
      backgroundColor: Colors.white,
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
      setState(() {
        if (isId1) {
          widget.memberData.idProof1File = processedFile;
        } else if (isId2) {
          widget.memberData.idProof2File = processedFile;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document captured successfully ✓'), backgroundColor: Colors.green),
        );
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
          fillColor: Colors.white,
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
          labelStyle: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 14),
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
                        backgroundColor: Colors.white,
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
                style: GoogleFonts.inter(color: const Color(0xFF1E293B)),
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
                style: GoogleFonts.inter(color: const Color(0xFF1E293B)),
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
                              color: widget.memberData.dob != null ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
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
                style: GoogleFonts.inter(color: const Color(0xFF1E293B), fontSize: 14),
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
                style: GoogleFonts.inter(color: const Color(0xFF1E293B)),
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
                style: GoogleFonts.inter(color: const Color(0xFF1E293B)),
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
                style: GoogleFonts.inter(color: const Color(0xFF1E293B)),
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
                style: GoogleFonts.inter(color: const Color(0xFF1E293B), fontSize: 14),
                items: const [
                  DropdownMenuItem(value: 'UPSC', child: Text('UPSC')),
                  DropdownMenuItem(value: 'NEET', child: Text('NEET')),
                  DropdownMenuItem(value: 'JEE', child: Text('JEE')),
                  DropdownMenuItem(value: 'SSC', child: Text('SSC')),
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
                        style: GoogleFonts.inter(color: const Color(0xFF1E293B), fontSize: 14),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // ID Documents header
              Text(
                'ID Document Verification (At least one required) *',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),

              // Document slot 1
              _buildDocumentSlot(
                slotNum: 1,
                selectedType: widget.memberData.idProof1Type,
                file: widget.memberData.idProof1File,
                onTypeChanged: (type) {
                  setState(() {
                    widget.memberData.idProof1Type = type;
                  });
                },
                onPick: () => _pickImage(false, isId1: true),
                onClear: () {
                  setState(() {
                    widget.memberData.idProof1File = null;
                  });
                },
              ),
              const SizedBox(height: 12),

              // Document slot 2
              _buildDocumentSlot(
                slotNum: 2,
                selectedType: widget.memberData.idProof2Type,
                file: widget.memberData.idProof2File,
                onTypeChanged: (type) {
                  setState(() {
                    widget.memberData.idProof2Type = type;
                  });
                },
                onPick: () => _pickImage(false, isId2: true),
                onClear: () {
                  setState(() {
                    widget.memberData.idProof2File = null;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentSlot({
    required int slotNum,
    required String? selectedType,
    required File? file,
    required ValueChanged<String?> onTypeChanged,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedType ?? (slotNum == 1 ? 'Aadhaar' : 'PAN'),
                  decoration: InputDecoration(
                    labelText: 'Doc $slotNum Type',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  style: GoogleFonts.inter(color: const Color(0xFF1E293B), fontSize: 13),
                  items: const [
                    DropdownMenuItem(value: 'Aadhaar', child: Text('Aadhaar Card')),
                    DropdownMenuItem(value: 'PAN', child: Text('PAN Card')),
                    DropdownMenuItem(value: 'Passport', child: Text('Passport')),
                    DropdownMenuItem(value: 'Driving License', child: Text('Driving License')),
                    DropdownMenuItem(value: 'Student ID', child: Text('Student ID')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: onTypeChanged,
                ),
              ),
              const SizedBox(width: 12),
              if (file == null)
                ElevatedButton.icon(
                  onPressed: onPick,
                  icon: const Icon(Icons.file_upload, size: 18),
                  label: const Text('Pick Image'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFF7ED),
                    foregroundColor: const Color(0xFFE65C00),
                    side: const BorderSide(color: Color(0xFFFFE0C2)),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                )
              else
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 24),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red, size: 24),
                      onPressed: onClear,
                    ),
                  ],
                ),
            ],
          ),
          if (file != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: kIsWeb
                  ? Image.network(
                      file.path,
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Image.file(
                      file,
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
