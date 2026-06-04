import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/image_optimizer.dart';
import 'package:silence/core/calendar_picker.dart';

class MemberProfileEditScreen extends StatefulWidget {
  const MemberProfileEditScreen({super.key});

  @override
  State<MemberProfileEditScreen> createState() => _MemberProfileEditScreenState();
}

class _MemberProfileEditScreenState extends State<MemberProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _emergencyContactController = TextEditingController();

  String? _photoUrl;
  String? _idDocumentUrl;
  String? _idDocument2Url;
  DateTime? _dob;
  String _examCategory = 'UPSC'; // Default category
  String _gender = 'male';
  
  // ID Document type selections
  String _idDocType1 = 'Aadhaar';
  String _idDocType2 = 'PAN Card';

  bool _isLoading = false;
  bool _isUploadingPhoto = false;
  bool _isUploadingDoc = false;
  bool _isUploadingDoc2 = false;
  bool _isSaving = false;

  final List<String> _examCategories = ['UPSC', 'NEET', 'JEE', 'SSC', 'Other'];
  final List<String> _idDocTypes = ['Aadhaar', 'PAN Card', 'Voter ID', 'Driving License', 'Passport', 'Other'];

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _fatherNameController.dispose();
    _emergencyContactController.dispose();
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
          _phoneController.text = userData['phone'] ?? '';
          _addressController.text = userData['address'] ?? '';
          _fatherNameController.text = userData['father_name'] ?? '';
          _emergencyContactController.text = userData['emergency_contact'] ?? '';
          
          if (userData['gender'] != null) {
            _gender = userData['gender'];
          }
          if (userData['date_of_birth'] != null) {
            _dob = DateTime.parse(userData['date_of_birth']);
          }
          if (userData['photo_url'] != null) {
            _photoUrl = userData['photo_url'];
          }
          // Retrieve document URLs
          if (userData['id_proof_url'] != null) {
            _idDocumentUrl = userData['id_proof_url'];
          }
          if (userData['id_proof_2_url'] != null) {
            _idDocument2Url = userData['id_proof_2_url'];
          }
          // ID document types
          if (userData['id_doc_type_1'] != null && _idDocTypes.contains(userData['id_doc_type_1'])) {
            _idDocType1 = userData['id_doc_type_1'];
          }
          if (userData['id_doc_type_2'] != null && _idDocTypes.contains(userData['id_doc_type_2'])) {
            _idDocType2 = userData['id_doc_type_2'];
          }
          if (userData['exam_category'] != null && _examCategories.contains(userData['exam_category'])) {
            _examCategory = userData['exam_category'];
          }
        }
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

  /// Upload type: 'profile' | 'id_doc_1' | 'id_doc_2'
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
      XFile? image;
      try {
        image = await picker.pickImage(
          source: source,
          maxWidth: 1024,
          imageQuality: 80,
        );
      } catch (e) {
        if (mounted) _showErrorSnackBar('Error: $e');
        return;
      }

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

        // Upload directly to pre-provisioned assets bucket

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
            } else {
              _idDocument2Url = publicUrl;
            }
          });
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
      debugPrint('Unexpected error in _pickAndUploadPhoto: $e');
      if (mounted) {
        _showErrorSnackBar('Something went wrong. Please try again.');
        setState(() {
          _isUploadingPhoto = false;
          _isUploadingDoc = false;
          _isUploadingDoc2 = false;
        });
      }
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
      final String phone = _phoneController.text.trim();
      final String address = _addressController.text.trim();
      final String fatherName = _fatherNameController.text.trim();
      final String emergencyContact = _emergencyContactController.text.trim();
      final String? dobStr = _dob != null ? _dob!.toIso8601String().split('T')[0] : null;

      final Map<String, dynamic> upsertData = {
        'id': user.id,
        'email': user.email,
        'full_name': name,
        'nickname': name.split(' ').first,
        'phone': phone,
        'gender': _gender,
        'date_of_birth': dobStr,
        'address': address,
        'exam_category': _examCategory,
        'photo_url': _photoUrl,
        'id_proof_url': _idDocumentUrl,
        'role': 'member',
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Add optional new fields - only include if they have values
      // These fields may not exist in the schema yet, so we wrap in try-catch
      if (fatherName.isNotEmpty) upsertData['father_name'] = fatherName;
      if (emergencyContact.isNotEmpty) upsertData['emergency_contact'] = emergencyContact;
      if (_idDocument2Url != null) upsertData['id_proof_2_url'] = _idDocument2Url;
      upsertData['id_doc_type_1'] = _idDocType1;
      upsertData['id_doc_type_2'] = _idDocType2;

      try {
        await supabase.from('users').upsert(upsertData, onConflict: 'id');
      } catch (e) {
        // If the new columns don't exist yet, retry without them
        debugPrint('Upsert with new fields failed: $e, retrying without new columns...');
        upsertData.remove('father_name');
        upsertData.remove('emergency_contact');
        upsertData.remove('id_proof_2_url');
        upsertData.remove('id_doc_type_1');
        upsertData.remove('id_doc_type_2');
        await supabase.from('users').upsert(upsertData, onConflict: 'id');
      }

      _showSuccessSnackBar('Profile saved successfully! ✓');
      if (!mounted) return;
      Navigator.pop(context, true); // Go back and indicate success
    } catch (e) {
      _showErrorSnackBar('Error saving profile: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildIdDocumentCard({
    required String title,
    required String subtitle,
    required String? docUrl,
    required bool isUploading,
    required String uploadType,
    required String docType,
    required ValueChanged<String?> onDocTypeChanged,
    bool isRequired = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E)),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF6B7280)),
          ),
          const SizedBox(height: 12),
          // Document type dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _idDocTypes.contains(docType) ? docType : _idDocTypes.first,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFFE65C00)),
                items: _idDocTypes.map((String type) {
                  return DropdownMenuItem<String>(
                    value: type,
                    child: Text(type, style: GoogleFonts.inter(fontSize: 14)),
                  );
                }).toList(),
                onChanged: onDocTypeChanged,
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: isUploading ? null : () => _pickAndUploadPhoto(uploadType: uploadType),
            child: Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFF7F0), width: 1),
              ),
              child: isUploading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
                  : docUrl != null && docUrl.isNotEmpty
                      ? Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: docUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                memCacheWidth: 200,
                                placeholder: (context, url) => const Center(
                                  child: CircularProgressIndicator(color: Color(0xFFE65C00)),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.edit, color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text('Change', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            )
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cloud_upload_outlined, size: 36, color: Color(0xFFE65C00)),
                            const SizedBox(height: 8),
                            Text(
                              'Tap to Upload',
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Max file size 5MB (JPG/PNG)',
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                            ),
                          ],
                        ),
            ),
          ),
        ],
      ),
    );
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
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
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
                        ),
                        const SizedBox(height: 16),

                        // 2. Personal Information Fields Card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Full Name *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _nameController,
                                style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
                                decoration: InputDecoration(
                                  hintText: 'Rahul Sharma',
                                  hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
                                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                                ),
                                validator: (v) => v == null || v.trim().isEmpty ? 'Full Name is required' : null,
                              ),
                              const SizedBox(height: 20),

                              // Father's Name (Optional)
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
                              const SizedBox(height: 20),

                              Text('Gender', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: ['male', 'female', 'other'].map((g) {
                                  final isSelected = _gender == g;
                                  String label = 'Other';
                                  if (g == 'male') label = 'Male';
                                  if (g == 'female') label = 'Female';

                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _gender = g),
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 4),
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(
                                          color: isSelected ? const Color(0xFFFFF3ED) : Colors.white,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: isSelected ? const Color(0xFFE65C00) : const Color(0xFFE5E7EB),
                                            width: isSelected ? 1.5 : 1.0,
                                          ),
                                        ),
                                        child: Text(
                                          label,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected ? const Color(0xFFE65C00) : const Color(0xFF6B7280),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 20),

                              Text('Date of Birth', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
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
                              const SizedBox(height: 20),

                              Text('Phone Number *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                              const SizedBox(height: 6),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
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
                                        hintText: '9876543210',
                                        hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
                                      ),
                                      validator: (v) => v == null || v.trim().length < 10 ? 'Enter valid 10-digit number' : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // Emergency Contact (Optional)
                              Text('Emergency Contact (Optional)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                              const SizedBox(height: 6),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
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
                              const SizedBox(height: 20),

                              Text('Email (Optional)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _emailController,
                                readOnly: true,
                                style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF9CA3AF)),
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.email_outlined, size: 20),
                                ),
                              ),
                              const SizedBox(height: 20),

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
                                    value: _examCategory,
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
                              const SizedBox(height: 20),

                              Text('Address', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _addressController,
                                maxLines: 3,
                                style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
                                decoration: InputDecoration(
                                  hintText: 'Enter your address',
                                  hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 3. ID Document 1 (Required)
                        _buildIdDocumentCard(
                          title: 'ID Document 1 (Required)',
                          subtitle: 'Upload your primary identity proof',
                          docUrl: _idDocumentUrl,
                          isUploading: _isUploadingDoc,
                          uploadType: 'id_doc_1',
                          docType: _idDocType1,
                          onDocTypeChanged: (value) {
                            if (value != null) setState(() => _idDocType1 = value);
                          },
                          isRequired: true,
                        ),
                        const SizedBox(height: 16),

                        // 4. ID Document 2 (Optional)
                        _buildIdDocumentCard(
                          title: 'ID Document 2 (Optional)',
                          subtitle: 'Upload a secondary identity proof',
                          docUrl: _idDocument2Url,
                          isUploading: _isUploadingDoc2,
                          uploadType: 'id_doc_2',
                          docType: _idDocType2,
                          onDocTypeChanged: (value) {
                            if (value != null) setState(() => _idDocType2 = value);
                          },
                          isRequired: false,
                        ),
                        const SizedBox(height: 32),

                        // 5. Save Button
                        ElevatedButton(
                          onPressed: _isSaving ? null : _handleSave,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE65C00),
                            foregroundColor: Colors.white,
                            elevation: 2,
                            shadowColor: const Color(0xFFE65C00).withOpacity(0.3),
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
}
