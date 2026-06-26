import 'dart:io';
import '../theme/app_palette.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/image_optimizer.dart';
import '../widgets/styled_dropdown_button.dart';
import 'package:flutter/services.dart';
import '../utils/error_messages.dart';


class MemberProfileEditScreen extends StatefulWidget {
  const MemberProfileEditScreen({super.key});

  @override
  State<MemberProfileEditScreen> createState() => _MemberProfileEditScreenState();
}

class _MemberProfileEditScreenState extends State<MemberProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _customExamController = TextEditingController();

  String? _photoUrl;
  String? _idDocumentUrl;
  String? _idDocument2Url;
  // Originals (to detect if the nickname was auto-derived from the name vs
  // deliberately customised — so a name fix follows through to the leaderboard).
  String _origFullName = '';
  String _origNickname = '';
  DateTime? _dob;
  String _examCategory = 'UPSC';
  String _gender = 'male';
  
  String _idDocType1 = 'Aadhaar';
  String _idDocType2 = 'PAN Card';

  String _idProofStatus = 'Not uploaded';
  String _idProof2Status = 'Not uploaded';

  bool _isLoading = false;
  bool _isUploadingPhoto = false;
  bool _isSaving = false;

  /// New members (just signed up) have an empty profile → show "Complete
  /// Profile"; an existing member editing → "Edit Profile".
  bool get _isProfileIncomplete =>
      _dob == null ||
      _phoneController.text.trim().isEmpty ||
      _addressController.text.trim().isEmpty;

  final List<String> _examCategories = [
    'UPSC', 'NEET', 'JEE', 'SSC', 'PCS', 'CAT', 'Banking', 'State PCS', 'Class 10-12', 'Other'
  ];

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_onPhoneChanged);
    _emailController.addListener(_onEmailChanged);
    _loadProfileData();
  }

  void _onPhoneChanged() {
    setState(() {});
  }

  void _onEmailChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _fatherNameController.dispose();
    _emergencyContactController.dispose();
    _customExamController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user != null) {
      _emailController.text = user.email ?? '';
      try {
        final userData = await supabase.from('users').select().eq('id', user.id).maybeSingle();
        if (userData != null) {
          _nameController.text = userData['full_name'] ?? '';
          _nicknameController.text = userData['nickname'] ?? '';
          _origFullName = (userData['full_name'] ?? '').toString();
          _origNickname = (userData['nickname'] ?? '').toString();
          _phoneController.text = userData['phone'] ?? '';
          _addressController.text = userData['address'] ?? '';
          _fatherNameController.text = userData['father_name'] ?? '';
          _emergencyContactController.text = userData['emergency_contact'] ?? '';
          if (userData['id_type'] != null) {
            _idDocType1 = userData['id_type'];
          }
          if (userData['id_proof_2_url'] != null) {
            _idDocument2Url = userData['id_proof_2_url'];
          }
          
          if (userData['gender'] != null) {
            _gender = userData['gender'];
          }
          if (userData['date_of_birth'] != null) {
            _dob = DateTime.parse(userData['date_of_birth']);
          }
          if (userData['photo_url'] != null) {
            _photoUrl = userData['photo_url'];
          }
          if (userData['id_proof_url'] != null) {
            _idDocumentUrl = userData['id_proof_url'];
          }

          // Load dropdown category
          final exam = userData['exam_category'] as String?;
          if (exam != null) {
            if (_examCategories.contains(exam)) {
              _examCategory = exam;
            } else {
              _examCategory = 'Other';
              _customExamController.text = exam;
            }
          }
        }

        // Load SharedPreferences fallback for missing columns
        final prefs = await SharedPreferences.getInstance();
        final userId = user.id;
        _idDocument2Url = prefs.getString('id_proof_2_url_$userId') ?? _idDocument2Url;
        _idDocType1 = prefs.getString('id_doc_type_1_$userId') ?? _idDocType1;
        _idDocType2 = prefs.getString('id_doc_type_2_$userId') ?? _idDocType2;
        
        _idProofStatus = prefs.getString('id_proof_status_$userId') ?? 
            (_idDocumentUrl != null ? 'Under Review' : 'Not uploaded');
        _idProof2Status = prefs.getString('id_proof_status_2_$userId') ?? 
            (_idDocument2Url != null ? 'Under Review' : 'Not uploaded');
            
      } catch (e) {
        debugPrint('Error loading profile: $e');
      }
    }
    setState(() => _isLoading = false);
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: const Color(0xFFEF4444),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  int? _calculateAge(DateTime? birthDate) {
    if (birthDate == null) return null;
    DateTime today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month || (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  Future<bool> _requestCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) return true;
    final result = await Permission.camera.request();
    return result.isGranted;
  }

  Future<bool> _requestGalleryPermission() async {
    if (Platform.isAndroid) {
      final statusPhotos = await Permission.photos.status;
      if (statusPhotos.isGranted) return true;
      final resultPhotos = await Permission.photos.request();
      if (resultPhotos.isGranted) return true;
      final statusStorage = await Permission.storage.status;
      if (statusStorage.isGranted) return true;
      final resultStorage = await Permission.storage.request();
      return resultStorage.isGranted;
    } else {
      final status = await Permission.photos.status;
      if (status.isGranted) return true;
      final result = await Permission.photos.request();
      return result.isGranted;
    }
  }

  Future<ImageSource?> _showImageSourceBottomSheet() async {
    return await showModalBottomSheet<ImageSource?>(
      context: context,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
              child: Text('Choose Photo Source', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFFE65C00)),
              title: Text('Camera (Take Photo)', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFFE65C00)),
              title: Text('Gallery (Choose Photo)', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadPhoto({required String uploadType}) async {
    try {
      final ImageSource? source = await _showImageSourceBottomSheet();
      if (source == null) return;

      // permission_handler, image_cropper and camera capture are MOBILE-ONLY
      // plugins — on Windows/macOS/Linux desktop (and web) they have no platform
      // implementation and throw a MissingPluginException, which force-closes the
      // app. Only run that path on Android/iOS; everywhere else fall straight
      // through to image_picker's file selection and skip cropping.
      final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

      if (isMobile) {
        bool hasPermission = false;
        if (source == ImageSource.camera) {
          hasPermission = await _requestCameraPermission();
        } else {
          hasPermission = await _requestGalleryPermission();
        }
        if (!hasPermission) {
          if (mounted) _showErrorSnackBar('Permission denied. Please grant permission in settings.');
          return;
        }
      }

      final picker = ImagePicker();
      XFile? image;
      try {
        image = await picker.pickImage(
          source: source,
          maxWidth: 1024,
          imageQuality: 80,
        );
      } catch (e) {
        debugPrint('pickImage failed: $e');
        if (mounted) {
          _showErrorSnackBar(source == ImageSource.camera
              ? 'Camera capture isn\'t supported on this device — choose from gallery/files instead.'
              : 'Could not open the file picker on this device.');
        }
        return;
      }

      if (image == null) return;
      if (!mounted) return;

      final bool isIdDoc = uploadType != 'profile';
      CroppedFile? croppedFile;
      bool cropSuccessOrCancel = false;
      if (isMobile) {
      try {
        croppedFile = await ImageCropper().cropImage(
          sourcePath: image.path,
          aspectRatio: isIdDoc ? null : const CropAspectRatio(ratioX: 1, ratioY: 1),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: isIdDoc ? 'Crop ID Document' : 'Crop Profile Photo',
              toolbarColor: const Color(0xFFE65C00),
              toolbarWidgetColor: Colors.white,
              initAspectRatio: isIdDoc ? CropAspectRatioPreset.original : CropAspectRatioPreset.square,
              lockAspectRatio: !isIdDoc,
              cropStyle: isIdDoc ? CropStyle.rectangle : CropStyle.circle,
            ),
            IOSUiSettings(
              title: isIdDoc ? 'Crop ID Document' : 'Crop Profile Photo',
              aspectRatioLockEnabled: !isIdDoc,
              resetAspectRatioEnabled: isIdDoc,
              cropStyle: isIdDoc ? CropStyle.rectangle : CropStyle.circle,
            ),
          ],
        );
        cropSuccessOrCancel = true;
      } catch (e) {
        debugPrint('Crop failed, falling back to original: $e');
      }

      if (cropSuccessOrCancel && croppedFile == null) return;
      if (!mounted) return;
      } // end isMobile crop gate

      final String finalPath = croppedFile?.path ?? image.path;

      setState(() {
        if (uploadType == 'profile') {
          _isUploadingPhoto = true;
        }
      });

      try {
        final supabase = Supabase.instance.client;
        final user = supabase.auth.currentUser;
        if (user == null) {
          if (mounted) _showErrorSnackBar('User session not found.');
          return;
        }

        final bytes = await ImageOptimizer.compressImage(finalPath);
        String fileName;
        if (uploadType == 'profile') {
          fileName = 'profile.jpg';
        } else if (uploadType == 'id_doc_1') {
          fileName = 'id_document_1.jpg';
        } else {
          fileName = 'id_document_2.jpg';
        }
        final path = 'member_profiles/${user.id}/$fileName';

        final String bucketName = (uploadType == 'profile') ? 'silence_assets' : 'silence_private';

        await supabase.storage.from(bucketName).uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            cacheControl: '3600',
            upsert: true,
          ),
        );

        if (!mounted) return;
        final String publicUrl;
        if (uploadType == 'profile') {
          publicUrl = supabase.storage.from(bucketName).getPublicUrl(path);
        } else {
          publicUrl = await supabase.storage.from(bucketName).createSignedUrl(path, 3600);
        }

        if (mounted) {
          setState(() {
            if (uploadType == 'profile') {
              _photoUrl = publicUrl;
            } else if (uploadType == 'id_doc_1') {
              _idDocumentUrl = publicUrl;
              _idProofStatus = 'Under Review';
            } else {
              _idDocument2Url = publicUrl;
              _idProof2Status = 'Under Review';
            }
          });
          
          final prefs = await SharedPreferences.getInstance();
          if (!mounted) return;
          if (uploadType == 'id_doc_1') {
            prefs.setString('id_proof_status_${user.id}', 'Under Review');
          } else if (uploadType == 'id_doc_2') {
            prefs.setString('id_proof_2_url_${user.id}', publicUrl);
            prefs.setString('id_proof_status_2_${user.id}', 'Under Review');
          }

          final label = uploadType == 'profile' ? 'Profile Photo' : (uploadType == 'id_doc_1' ? 'ID Document 1' : 'ID Document 2');
          _showSuccessSnackBar('$label uploaded successfully! ✓');
        }
      } catch (e) {
        if (mounted) _showErrorSnackBar(friendlyError(e));
      } finally {
        if (mounted) {
          setState(() {
            if (uploadType == 'profile') {
              _isUploadingPhoto = false;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Unexpected error: $e');
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        _showErrorSnackBar('User session expired. Please login again.');
        return;
      }

      final String name = _nameController.text.trim();
      final String nicknameInput = _nicknameController.text.trim();
      // The leaderboard displays the nickname. If the nickname was merely
      // auto-derived from the OLD name (never customised by the member), follow
      // the corrected name so the leaderboard updates too. A nickname the member
      // deliberately set is preserved.
      final bool nicknameWasAutoDerived =
          _origNickname.isEmpty || _origNickname == _origFullName.trim().split(' ').first;
      final String nickname = nicknameInput.isEmpty
          ? name.split(' ').first
          : ((nicknameWasAutoDerived && nicknameInput == _origNickname)
              ? name.split(' ').first
              : nicknameInput);
      final String phone = _phoneController.text.trim();
      final String address = _addressController.text.trim();
      final String fatherName = _fatherNameController.text.trim();
      final String emergencyContact = _emergencyContactController.text.trim();
      final String? dobStr = _dob != null ? _dob!.toIso8601String().split('T')[0] : null;

      final email = user.email ?? '';
      final Map<String, dynamic> upsertData = {
        'id': user.id,
        'full_name': name,
        'nickname': nickname,
        'phone': phone,
        'gender': _gender,
        'date_of_birth': dobStr,
        'address': address,
        'exam_category': _examCategory == 'Other' ? _customExamController.text.trim() : _examCategory,
        'photo_url': _photoUrl,
        'id_proof_url': _idDocumentUrl,
        'id_proof_2_url': _idDocument2Url,
        'id_type': _idDocType1,
        'role': 'member',
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (email.isNotEmpty) {
        upsertData['email'] = email;
      }

      upsertData['father_name'] = fatherName.isNotEmpty ? fatherName : null;
      if (emergencyContact.isNotEmpty) upsertData['emergency_contact'] = emergencyContact;

      await supabase.from('users').upsert(upsertData, onConflict: 'id');

      // Keep the Supabase Auth user metadata (Authentication → Users display
      // name) in sync with the profile name — otherwise the dashboard keeps the
      // original signup name forever.
      try {
        await supabase.auth.updateUser(UserAttributes(data: {'full_name': name}));
      } catch (e) {
        debugPrint('Auth metadata name sync failed (non-fatal): $e');
      }

      // Local fallbacks are best-effort: a prefs hiccup must NOT turn a
      // successful DB save into an error.
      try {
        final prefs = await SharedPreferences.getInstance();
        final userId = user.id;
        if (_idDocument2Url != null) prefs.setString('id_proof_2_url_$userId', _idDocument2Url!);
        prefs.setString('id_doc_type_1_$userId', _idDocType1);
        prefs.setString('id_doc_type_2_$userId', _idDocType2);
        prefs.setString('id_proof_status_$userId', _idProofStatus);
        prefs.setString('id_proof_status_2_$userId', _idProof2Status);
      } catch (_) {}

      if (!mounted) return;
      _showSuccessSnackBar('Profile saved successfully! ✓');
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      if (e.code == '23505') {
        final msg = e.message.toLowerCase();
        if (msg.contains('phone')) {
          _showErrorSnackBar('This mobile number is already registered with another account.');
        } else if (msg.contains('email')) {
          _showErrorSnackBar('This email is already registered with another account.');
        } else {
          _showErrorSnackBar('Some of these details are already registered with another account.');
        }
      } else {
        _showErrorSnackBar(friendlyError(e));
      }
    } catch (e) {
      _showErrorSnackBar(friendlyError(e));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE65C00),
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: context.palette.scaffold,
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              _isProfileIncomplete ? 'Complete Profile' : 'Edit Profile',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
              : Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. Profile Photo Card
                        _buildPhotoSection(),
                        const SizedBox(height: 16),

                        // 2. Personal Information Fields Card
                        _buildPersonalDetailsCard(),
                        const SizedBox(height: 16),

                        // 3. Contact Details Card
                        _buildContactDetailsCard(),
                        const SizedBox(height: 16),

                        // 4. ID Documents Card
                        _buildIdDocumentsCard(),
                        const SizedBox(height: 32),

                        // 5. Save Button
                        ElevatedButton(
                          onPressed: _isSaving ? null : _handleSave,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE65C00),
                            foregroundColor: Colors.white,
                            elevation: 2,
                            shadowColor: const Color(0xFFE65C00).withValues(alpha: 0.3),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                                )
                              : Text(_isProfileIncomplete ? 'Complete Profile' : 'Save Profile', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: const Color(0xFFFFF7F0),
                  backgroundImage: _photoUrl != null && _photoUrl!.isNotEmpty ? CachedNetworkImageProvider(_photoUrl!, maxWidth: 200) : null,
                  child: _photoUrl == null || _photoUrl!.isEmpty
                      ? const Icon(Icons.person, size: 48, color: Color(0xFFE65C00))
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _isUploadingPhoto ? null : () => _pickAndUploadPhoto(uploadType: 'profile'),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE65C00),
                        shape: BoxShape.circle,
                      ),
                      child: _isUploadingPhoto
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                            )
                          : const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Profile Photo',
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Upload a clear front-facing picture',
            style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalDetailsCard() {
    final age = _calculateAge(_dob);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Personal Details', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
          const SizedBox(height: 16),
          
          Text('Full Name *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nameController,
            style: GoogleFonts.inter(fontSize: 15, color: context.palette.textPrimary),
            decoration: InputDecoration(
              hintText: 'Enter full name',
              hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
              prefixIcon: const Icon(Icons.person_outline, size: 20),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Full Name is required' : null,
          ),
          const SizedBox(height: 16),

          Text('Nickname (Optional)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nicknameController,
            style: GoogleFonts.inter(fontSize: 15, color: context.palette.textPrimary),
            decoration: InputDecoration(
              hintText: 'Enter nickname',
              hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
              prefixIcon: const Icon(Icons.alternate_email_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 16),

          // Father's name
          Text("Father's Name", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _fatherNameController,
            style: GoogleFonts.inter(fontSize: 15, color: context.palette.textPrimary),
            decoration: InputDecoration(
              hintText: 'Enter father\'s name',
              hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
              prefixIcon: const Icon(Icons.family_restroom_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 16),

          Text('Gender *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['male', 'female', 'other', 'prefer_not_to_say'].map((g) {
              final isSelected = _gender == g;
              String label = 'Prefer not to say';
              if (g == 'male') label = 'Male';
              if (g == 'female') label = 'Female';
              if (g == 'other') label = 'Other';

              return ChoiceChip(
                label: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                selected: isSelected,
                selectedColor: const Color(0xFFFFF3ED),
                backgroundColor: context.palette.surface,
                labelStyle: TextStyle(color: isSelected ? const Color(0xFFE65C00) : context.palette.textMuted),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: isSelected ? const Color(0xFFE65C00) : const Color(0xFFE5E7EB)),
                ),
                onSelected: (selected) {
                  if (selected) setState(() => _gender = g);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          Text('Date of Birth *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () {
              DateTime tempDate = _dob ?? DateTime(2000, 1, 1);
              showCupertinoModalPopup(
                context: context,
                builder: (BuildContext context) {
                  return Container(
                    height: 320,
                    color: Colors.white,
                    child: Column(
                      children: [
                        Container(
                          color: Colors.grey[100],
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text('Cancel', style: GoogleFonts.inter(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _dob = tempDate;
                                  });
                                  Navigator.pop(context);
                                },
                                child: Text('Done', style: GoogleFonts.inter(color: const Color(0xFFE65C00), fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: CupertinoDatePicker(
                            mode: CupertinoDatePickerMode.date,
                            initialDateTime: tempDate,
                            minimumYear: 1950,
                            maximumDate: DateTime.now(),
                            onDateTimeChanged: (DateTime newDate) {
                              tempDate = newDate;
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE5E7EB)),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _dob == null
                        ? 'Select Date of Birth'
                        : '${_dob!.day}/${_dob!.month}/${_dob!.year}',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: _dob == null ? const Color(0xFF9CA3AF) : context.palette.textPrimary,
                    ),
                  ),
                  const Icon(Icons.calendar_today, size: 18, color: Color(0xFFE65C00)),
                ],
              ),
            ),
          ),
          if (age != null) ...[
            const SizedBox(height: 4),
            Text(
              'Age: $age years',
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFE65C00), fontWeight: FontWeight.bold),
            ),
          ],
          const SizedBox(height: 16),

          Text('Exam Preparing For', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted)),
          const SizedBox(height: 6),
          StyledDropdownButton<String>(
            value: _examCategories.contains(_examCategory) ? _examCategory : 'Other',
            items: _examCategories,
            itemLabelBuilder: (String category) => category,
            onChanged: (String? value) {
              if (value != null) {
                setState(() => _examCategory = value);
              }
            },
            title: 'Select Exam Preparing For',
          ),
          if (_examCategory == 'Other') ...[
            const SizedBox(height: 12),
            Text('Custom Exam Name *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _customExamController,
              style: GoogleFonts.inter(fontSize: 15, color: context.palette.textPrimary),
              decoration: InputDecoration(
                hintText: 'Enter custom exam name',
                hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
              ),
              validator: (v) => _examCategory == 'Other' && (v == null || v.trim().isEmpty) ? 'Custom Exam Name is required' : null,
            ),
          ],
          const SizedBox(height: 16),

          Text('Address *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _addressController,
            maxLines: 3,
            style: GoogleFonts.inter(fontSize: 15, color: context.palette.textPrimary),
            decoration: InputDecoration(
              hintText: 'Enter multiline address',
              hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Address is required' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildContactDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Contact Details', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
          const SizedBox(height: 16),

          Text('Phone Number *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3ED),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '+91',
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  style: GoogleFonts.inter(fontSize: 15, color: context.palette.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Enter 10 digit number',
                    hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
                  ),
                  validator: (v) => v == null || v.trim().length < 10 ? 'Enter valid 10-digit number' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Emergency Contact
          Text('Emergency Contact (Optional)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3ED),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '+91',
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _emergencyContactController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  style: GoogleFonts.inter(fontSize: 15, color: context.palette.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Emergency phone number',
                    hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text('Email', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailController,
            style: GoogleFonts.inter(fontSize: 15, color: context.palette.textPrimary),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.email_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildIdDocumentsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ID Verification', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
          const SizedBox(height: 4),
          Text(
            'Upload a clear photo of your ID. Front is required.',
            style: GoogleFonts.inter(fontSize: 12.5, color: context.palette.textMuted),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildIdPhotoTile('ID Front', true, _idDocumentUrl, _idProofStatus, 'id_doc_1')),
              const SizedBox(width: 12),
              Expanded(child: _buildIdPhotoTile('ID Back', false, _idDocument2Url, _idProof2Status, 'id_doc_2')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIdPhotoTile(String label, bool isRequired, String? docUrl, String status, String uploadType) {
    Color statusColor = Colors.grey;
    if (status == 'Verified') statusColor = const Color(0xFF10B981);
    if (status == 'Under Review') statusColor = const Color(0xFFF59E0B);
    if (status == 'Rejected') statusColor = const Color(0xFFEF4444);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
            if (isRequired)
              Text('  *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFFEF4444))),
          ],
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => _pickAndUploadPhoto(uploadType: uploadType),
          child: Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              color: context.palette.scaffold,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: docUrl != null && docUrl.isNotEmpty
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: docUrl,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(child: Icon(Icons.edit, color: Colors.white, size: 22)),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_a_photo_outlined, size: 24, color: Color(0xFFE65C00)),
                      const SizedBox(height: 6),
                      Text('Add Photo', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          status,
          style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: statusColor),
        ),
      ],
    );
  }
}
