import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/image_optimizer.dart';
import '../core/calendar_picker.dart';

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
  DateTime? _dob;
  String _examCategory = 'UPSC';
  String _gender = 'male';
  
  String _idDocType1 = 'Aadhaar';
  String _idDocType2 = 'PAN Card';

  bool _phoneVerified = false;
  bool _emailVerified = false;

  String _idProofStatus = 'Not uploaded';
  String _idProof2Status = 'Not uploaded';

  bool _isLoading = false;
  bool _isUploadingPhoto = false;
  bool _isUploadingDoc = false;
  bool _isUploadingDoc2 = false;
  bool _isSaving = false;

  final List<String> _examCategories = [
    'UPSC', 'NEET', 'JEE', 'SSC', 'PCS', 'CAT', 'Banking', 'State PCS', 'Class 10-12', 'Other'
  ];
  final List<String> _idDocTypes = ['Aadhaar', 'PAN Card', 'Voter ID', 'Driving License', 'Passport', 'Other'];

  @override
  void initState() {
    super.initState();
    _loadProfileData();
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
          _phoneController.text = userData['phone'] ?? '';
          _addressController.text = userData['address'] ?? '';
          _fatherNameController.text = userData['father_name'] ?? '';
          _emergencyContactController.text = userData['emergency_contact'] ?? '';
          _phoneVerified = userData['phone_verified'] as bool? ?? false;
          _emailVerified = userData['email_verified'] as bool? ?? false;
          
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
      backgroundColor: Colors.white,
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

      final picker = ImagePicker();
      XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 80,
      );

      if (image == null) return;
      if (!mounted) return;

      final bool isIdDoc = uploadType != 'profile';
      CroppedFile? croppedFile;
      bool cropSuccessOrCancel = false;
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

      final String finalPath = croppedFile?.path ?? image.path;

      setState(() {
        if (uploadType == 'profile') {
          _isUploadingPhoto = true;
        } else if (uploadType == 'id_doc_1') {
          _isUploadingDoc = true;
        } else {
          _isUploadingDoc2 = true;
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

        await supabase.storage.from('silence_assets').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            cacheControl: '3600',
            upsert: true,
          ),
        );

        final publicUrl = supabase.storage.from('silence_assets').getPublicUrl(path);

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
        if (mounted) _showErrorSnackBar('Upload failed: $e');
      } finally {
        if (mounted) {
          setState(() {
            if (uploadType == 'profile') {
              _isUploadingPhoto = false;
            } else if (uploadType == 'id_doc_1') {
              _isUploadingDoc = false;
            } else {
              _isUploadingDoc2 = false;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Unexpected error: $e');
    }
  }

  void _showVerifyOtpBottomSheet(String targetType, String value) {
    final otpController = TextEditingController();
    bool isSending = false;
    bool isVerifying = false;
    String? localError;
    String sentCode = "123456"; // Mock code

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              top: 24,
              left: 24,
              right: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Verify ${targetType == 'phone' ? 'Phone Number' : 'Email'}',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                ),
                const SizedBox(height: 8),
                Text(
                  'We will send a 6-digit verification code to $value.',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                if (localError != null) ...[
                  Text(
                    localError!,
                    style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceMono(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
                  decoration: const InputDecoration(
                    hintText: '000000',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: isSending ? null : () {
                        setModalState(() {
                          isSending = true;
                          localError = null;
                        });
                        Future.delayed(const Duration(seconds: 1), () {
                          if (ctx.mounted) {
                            setModalState(() {
                              isSending = false;
                              _showSuccessSnackBar('Mock OTP Code Sent: 123456');
                            });
                          }
                        });
                      },
                      child: Text(
                        isSending ? 'Sending...' : 'Resend Code',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: isVerifying ? null : () async {
                        if (otpController.text.trim() != sentCode) {
                          setModalState(() {
                            localError = 'Invalid code. Please enter 123456 for testing.';
                          });
                          return;
                        }
                        setModalState(() {
                          isVerifying = true;
                          localError = null;
                        });
                        
                        try {
                          final supabase = Supabase.instance.client;
                          final user = supabase.auth.currentUser;
                          if (user != null) {
                            if (targetType == 'phone') {
                              await supabase.from('users').update({'phone_verified': true}).eq('id', user.id);
                              setState(() => _phoneVerified = true);
                            } else {
                              await supabase.from('users').update({'email_verified': true}).eq('id', user.id);
                              setState(() => _emailVerified = true);
                            }
                            _showSuccessSnackBar('Verified successfully! ✓');
                            Navigator.pop(ctx);
                          }
                        } catch (e) {
                          setModalState(() {
                            localError = 'Verification failed: $e';
                          });
                        } finally {
                          setModalState(() => isVerifying = false);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65C00),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: isVerifying
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text('Verify Code', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
                    )
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
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
      final String nickname = _nicknameController.text.trim();
      final String phone = _phoneController.text.trim();
      final String address = _addressController.text.trim();
      final String fatherName = _fatherNameController.text.trim();
      final String emergencyContact = _emergencyContactController.text.trim();
      final String? dobStr = _dob != null ? _dob!.toIso8601String().split('T')[0] : null;

      final Map<String, dynamic> upsertData = {
        'id': user.id,
        'email': user.email,
        'full_name': name,
        'nickname': nickname.isNotEmpty ? nickname : name.split(' ').first,
        'phone': phone,
        'gender': _gender,
        'date_of_birth': dobStr,
        'address': address,
        'exam_category': _examCategory == 'Other' ? _customExamController.text.trim() : _examCategory,
        'photo_url': _photoUrl,
        'id_proof_url': _idDocumentUrl,
        'phone_verified': _phoneVerified,
        'email_verified': _emailVerified,
        'role': 'member',
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (fatherName.isNotEmpty) upsertData['father_name'] = fatherName;
      if (emergencyContact.isNotEmpty) upsertData['emergency_contact'] = emergencyContact;

      await supabase.from('users').upsert(upsertData, onConflict: 'id');

      // Save SharedPreferences fallbacks
      final prefs = await SharedPreferences.getInstance();
      final userId = user.id;
      if (_idDocument2Url != null) prefs.setString('id_proof_2_url_$userId', _idDocument2Url!);
      prefs.setString('id_doc_type_1_$userId', _idDocType1);
      prefs.setString('id_doc_type_2_$userId', _idDocType2);
      prefs.setString('id_proof_status_$userId', _idProofStatus);
      prefs.setString('id_proof_status_2_$userId', _idProof2Status);

      _showSuccessSnackBar('Profile saved successfully! ✓');
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackBar('Error saving profile: $e');
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
          backgroundColor: const Color(0xFFFBF5EE),
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Edit Profile',
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
                              : Text('Save Profile', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
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
        color: Colors.white,
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
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E)),
          ),
          const SizedBox(height: 4),
          Text(
            'Upload a clear front-facing picture',
            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF6B7280)),
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
        color: Colors.white,
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
          
          Text('Full Name *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nameController,
            style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
            decoration: InputDecoration(
              hintText: 'Enter full name',
              hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
              prefixIcon: const Icon(Icons.person_outline, size: 20),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Full Name is required' : null,
          ),
          const SizedBox(height: 16),

          Text('Nickname (Optional)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nicknameController,
            style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
            decoration: InputDecoration(
              hintText: 'Enter nickname',
              hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
              prefixIcon: const Icon(Icons.alternate_email_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 16),

          // Father's name
          Text("Father's Name (Optional)", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
          const SizedBox(height: 6),
          TextFormField(
            controller: _fatherNameController,
            style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
            decoration: InputDecoration(
              hintText: 'Enter father\'s name',
              hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
              prefixIcon: const Icon(Icons.family_restroom_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 16),

          Text('Gender *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
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
                backgroundColor: Colors.white,
                labelStyle: TextStyle(color: isSelected ? const Color(0xFFE65C00) : const Color(0xFF6B7280)),
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

          Text('Date of Birth *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () async {
              final selectedDate = await showCalendarGridBottomSheet(
                context,
                initialDate: _dob ?? DateTime(2000),
                firstDate: DateTime(1950),
                lastDate: DateTime.now(),
              );
              if (selectedDate != null) {
                setState(() {
                  _dob = selectedDate;
                });
              }
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
                      color: _dob == null ? const Color(0xFF9CA3AF) : const Color(0xFF1A1A2E),
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

          Text('Exam Preparing For', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _examCategories.contains(_examCategory) ? _examCategory : 'Other',
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFFE65C00)),
                items: _examCategories.map((String category) {
                  return DropdownMenuItem<String>(
                    value: category,
                    child: Text(category, style: GoogleFonts.inter(fontSize: 15)),
                  );
                }).toList(),
                onChanged: (String? value) {
                  if (value != null) {
                    setState(() => _examCategory = value);
                  }
                },
              ),
            ),
          ),
          if (_examCategory == 'Other') ...[
            const SizedBox(height: 12),
            Text('Custom Exam Name *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
            const SizedBox(height: 6),
            TextFormField(
              controller: _customExamController,
              style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
              decoration: InputDecoration(
                hintText: 'Enter custom exam name',
                hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
              ),
              validator: (v) => _examCategory == 'Other' && (v == null || v.trim().isEmpty) ? 'Custom Exam Name is required' : null,
            ),
          ],
          const SizedBox(height: 16),

          Text('Address *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
          const SizedBox(height: 6),
          TextFormField(
            controller: _addressController,
            maxLines: 3,
            style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
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
        color: Colors.white,
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

          Text('Phone Number *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
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
                  keyboardType: TextInputType.phone,
                  style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
                  decoration: InputDecoration(
                    hintText: 'Enter 10 digit number',
                    hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
                  ),
                  validator: (v) => v == null || v.trim().length < 10 ? 'Enter valid 10-digit number' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _buildVerifyRow('phone', _phoneVerified, () => _showVerifyOtpBottomSheet('phone', '+91 ${_phoneController.text}')),
          const SizedBox(height: 16),

          // Emergency Contact
          Text('Emergency Contact (Optional)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
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
                  keyboardType: TextInputType.phone,
                  style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
                  decoration: InputDecoration(
                    hintText: 'Emergency phone number',
                    hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text('Email (Optional)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailController,
            style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.email_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 6),
          _buildVerifyRow('email', _emailVerified, () => _showVerifyOtpBottomSheet('email', _emailController.text)),
        ],
      ),
    );
  }

  Widget _buildVerifyRow(String type, bool isVerified, VoidCallback onVerify) {
    if (isVerified) {
      return Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 14),
          const SizedBox(width: 4),
          Text(
            'Verified',
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF10B981), fontWeight: FontWeight.bold),
          ),
        ],
      );
    } else {
      return GestureDetector(
        onTap: onVerify,
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFE65C00), size: 14),
            const SizedBox(width: 4),
            Text(
              'Unverified. [Verify →]',
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFE65C00), fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildIdDocumentsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ID Verification Documents', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
          const SizedBox(height: 16),
          
          _buildDocRow('Document 1 (Required)', _idDocType1, _idDocumentUrl, _idProofStatus, 'id_doc_1', (v) {
            if (v != null) setState(() => _idDocType1 = v);
          }),
          const Divider(height: 24),
          _buildDocRow('Document 2 (Optional)', _idDocType2, _idDocument2Url, _idProof2Status, 'id_doc_2', (v) {
            if (v != null) setState(() => _idDocType2 = v);
          }),
        ],
      ),
    );
  }

  Widget _buildDocRow(
    String label, 
    String docType, 
    String? docUrl, 
    String status, 
    String uploadType,
    ValueChanged<String?> onTypeChanged
  ) {
    Color statusColor = Colors.grey;
    if (status == 'Verified') statusColor = const Color(0xFF10B981);
    if (status == 'Under Review') statusColor = const Color(0xFFF59E0B);
    if (status == 'Rejected') statusColor = const Color(0xFFEF4444);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                status,
                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
              ),
            )
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: docType,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFFE65C00), size: 18),
              items: _idDocTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: GoogleFonts.inter(fontSize: 13)))).toList(),
              onChanged: onTypeChanged,
            ),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _pickAndUploadPhoto(uploadType: uploadType),
          child: Container(
            height: 110,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFFBF5EE),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: docUrl != null && docUrl.isNotEmpty
                ? Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: docUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                      Container(
                        color: Colors.black26,
                        child: const Center(
                          child: Icon(Icons.cloud_done, color: Colors.white, size: 28),
                        ),
                      )
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_upload_outlined, size: 24, color: Color(0xFFE65C00)),
                      const SizedBox(height: 4),
                      Text('Upload Document', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                    ],
                  ),
          ),
        )
      ],
    );
  }
}
