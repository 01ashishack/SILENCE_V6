import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_cropper/image_cropper.dart';
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

  String? _photoUrl;
  String? _idDocumentUrl;
  DateTime? _dob;
  String _examCategory = 'UPSC'; // Default category
  String _gender = 'male';

  bool _isLoading = false;
  bool _isUploadingPhoto = false;
  bool _isUploadingDoc = false;
  bool _isSaving = false;

  final List<String> _examCategories = ['UPSC', 'NEET', 'JEE', 'SSC', 'Other'];

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
          
          if (userData['gender'] != null) {
            _gender = userData['gender'];
          }
          if (userData['date_of_birth'] != null) {
            _dob = DateTime.parse(userData['date_of_birth']);
          }
          if (userData['photo_url'] != null) {
            _photoUrl = userData['photo_url'];
          }
          // Note: fcm_token is used to store the ID Document URL
          if (userData['fcm_token'] != null) {
            _idDocumentUrl = userData['fcm_token'];
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

  Future<void> _pickAndUploadPhoto({required bool isIdDoc}) async {
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

      CroppedFile? croppedFile;
      try {
        croppedFile = await ImageCropper().cropImage(
          sourcePath: image.path,
          aspectRatio: isIdDoc ? null : const CropAspectRatio(ratioX: 1, ratioY: 1), // Square for profile, free/landscape for ID Doc
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: isIdDoc ? 'Crop ID Document' : 'Crop Profile Photo',
              toolbarColor: const Color(0xFFE65C00),
              toolbarWidgetColor: Colors.white,
              initAspectRatio: isIdDoc ? CropAspectRatioPreset.original : CropAspectRatioPreset.square,
              lockAspectRatio: !isIdDoc,
            ),
            IOSUiSettings(
              title: isIdDoc ? 'Crop ID Document' : 'Crop Profile Photo',
              aspectRatioLockEnabled: !isIdDoc,
              resetAspectRatioEnabled: isIdDoc,
            ),
          ],
        );
      } catch (e) {
        if (mounted) _showErrorSnackBar('Error cropping image: $e');
        return;
      }

      if (croppedFile == null) return;
      if (!mounted) return;

      setState(() {
        if (isIdDoc) {
          _isUploadingDoc = true;
        } else {
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

        final bytes = await File(croppedFile.path).readAsBytes();
        final fileName = isIdDoc ? 'id_document.jpg' : 'profile.jpg';
        final path = 'member_profiles/${user.id}/$fileName';

        try {
          await supabase.storage.createBucket('silence_assets', const BucketOptions(public: true));
        } catch (_) {}

        await supabase.storage.from('silence_assets').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            cacheControl: '3600',
            upsert: true,
          ),
        );

        final publicUrl = supabase.storage.from('silence_assets').getPublicUrl(path);

        if (mounted) {
          setState(() {
            if (isIdDoc) {
              _idDocumentUrl = publicUrl;
            } else {
              _photoUrl = publicUrl;
            }
          });
          _showSuccessSnackBar('${isIdDoc ? "ID Document" : "Profile Photo"} uploaded successfully! ✓');
        }
      } catch (e) {
        if (mounted) _showErrorSnackBar('Upload failed: $e');
      } finally {
        if (mounted) {
          setState(() {
            if (isIdDoc) {
              _isUploadingDoc = false;
            } else {
              _isUploadingPhoto = false;
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
      final String? dobStr = _dob != null ? _dob!.toIso8601String().split('T')[0] : null;

      await supabase.from('users').upsert({
        'id': user.id,
        'email': user.email!,
        'full_name': name,
        'nickname': name.split(' ').first,
        'phone': phone,
        'gender': _gender,
        'date_of_birth': dobStr,
        'address': address,
        'exam_category': _examCategory,
        'photo_url': _photoUrl,
        'fcm_token': _idDocumentUrl, // Store ID Document URL in unused fcm_token column
        'role': 'member',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id');

      _showSuccessSnackBar('Profile saved successfully! ✓');
      if (!mounted) return;
      Navigator.pop(context, true); // Go back and indicate success
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
                                      backgroundImage: _photoUrl != null && _photoUrl!.isNotEmpty ? NetworkImage(_photoUrl!) : null,
                                      child: _photoUrl == null || _photoUrl!.isEmpty
                                          ? const Icon(Icons.person, size: 48, color: Color(0xFFE65C00))
                                          : null,
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: GestureDetector(
                                        onTap: _isUploadingPhoto ? null : () => _pickAndUploadPhoto(isIdDoc: false),
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

                        // 3. ID Document Proof Card
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
                              Text(
                                'ID Document Proof (Optional)',
                                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Upload Aadhaar, PAN Card, or Voter ID',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF6B7280)),
                              ),
                              const SizedBox(height: 16),
                              GestureDetector(
                                onTap: _isUploadingDoc ? null : () => _pickAndUploadPhoto(isIdDoc: true),
                                child: Container(
                                  height: 180,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF7F0),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFFFF7F0), width: 1),
                                  ),
                                  child: _isUploadingDoc
                                      ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
                                      : _idDocumentUrl != null && _idDocumentUrl!.isNotEmpty
                                          ? Stack(
                                              children: [
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: Image.network(
                                                    _idDocumentUrl!,
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                    height: double.infinity,
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
                                                    child: Row(
                                                      children: const [
                                                        Icon(Icons.edit, color: Colors.white, size: 14),
                                                        SizedBox(width: 4),
                                                        Text('Change ID', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                                      ],
                                                    ),
                                                  ),
                                                )
                                              ],
                                            )
                                          : Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Icon(Icons.cloud_upload_outlined, size: 40, color: Color(0xFFE65C00)),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Tap to Upload ID Photo',
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
                        ),
                        const SizedBox(height: 32),

                        // 4. Save Button
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
