import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/image_optimizer.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';



class AdminProfileCompleteScreen extends StatefulWidget {
  const AdminProfileCompleteScreen({super.key});

  @override
  State<AdminProfileCompleteScreen> createState() => _AdminProfileCompleteScreenState();
}

class _AdminProfileCompleteScreenState extends State<AdminProfileCompleteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();

  String _gender = 'male';
  DateTime? _dob;
  String? _photoUrl;
  bool _isLoading = false;
  bool _isUploadingPhoto = false;
  bool _isSaving = false;

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
          if (userData['gender'] != null) {
            _gender = userData['gender'];
          }
          if (userData['date_of_birth'] != null) {
            _dob = DateTime.parse(userData['date_of_birth']);
          }
          if (userData['photo_url'] != null) {
            _photoUrl = userData['photo_url'];
          }
          _addressController.text = userData['address'] ?? '';
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

  Future<void> _pickAndUploadPhoto() async {
    try {
      // 1. Show source selection
      final ImageSource? source = await _showImageSourceBottomSheet();
      if (source == null) return;

      // permission_handler, image_cropper and camera capture are MOBILE-ONLY
      // plugins — on Windows/macOS/Linux desktop (and web) they have no platform
      // implementation and throw a MissingPluginException, which force-closes the
      // app. Only run that path on Android/iOS; everywhere else fall straight
      // through to image_picker's file selection and skip cropping.
      final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

      // 2. Check & Request Permission
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

      // 3. Pick image with compression
      final picker = ImagePicker();
      XFile? image;
      try {
        image = await picker.pickImage(
          source: source,
          maxWidth: 1024,
          imageQuality: 80,
        );
      } catch (e) {
        if (mounted) _showErrorSnackBar('Error opening ${source == ImageSource.camera ? 'camera' : 'gallery'}: $e');
        return;
      }

      if (image == null) return;
      if (!mounted) return;

      // 4. Crop Image
      CroppedFile? croppedFile;
      bool cropSuccessOrCancel = false;
      if (isMobile) {
      try {
        croppedFile = await ImageCropper().cropImage(
          sourcePath: image.path,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Profile Photo',
              toolbarColor: const Color(0xFFE65C00),
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
              cropStyle: CropStyle.circle,
            ),
            IOSUiSettings(
              title: 'Crop Profile Photo',
              aspectRatioLockEnabled: true,
              resetAspectRatioEnabled: false,
              cropStyle: CropStyle.circle,
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

      // 5. Show confirmation/preview dialog
      final bool confirmed = await _showPreviewConfirmationDialog(context, XFile(finalPath));
      if (!confirmed) return;
      if (!mounted) return;

      // 6. Upload to Supabase Storage
      setState(() {
        _isUploadingPhoto = true;
      });

      try {
        final supabase = Supabase.instance.client;
        final user = supabase.auth.currentUser;
        if (user == null) {
          if (mounted) _showErrorSnackBar('User session not found.');
          return;
        }

        final bytes = await ImageOptimizer.compressImage(finalPath);
        String fileName = 'profile.jpg';
        final path = 'admin_profiles/${user.id}/$fileName';
        final String bucketName = 'silence_assets';

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
        final String publicUrl = supabase.storage.from(bucketName).getPublicUrl(path);

        if (mounted) {
          setState(() {
            _photoUrl = publicUrl;
          });
          _showSuccessSnackBar('Profile Photo uploaded successfully! ✓');
        }
      } catch (e) {
        if (mounted) _showErrorSnackBar('Upload failed: $e');
      } finally {
        if (mounted) {
          setState(() {
            _isUploadingPhoto = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Unexpected error in _pickAndUploadPhoto: $e');
      if (mounted) {
        _showErrorSnackBar('Something went wrong. Please try again.');
        setState(() {
          _isUploadingPhoto = false;
        });
      }
    }
  }

  Future<bool> _showPreviewConfirmationDialog(BuildContext context, XFile image) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          'Confirm Profile Photo',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(image.path),
                height: 200,
                width: 200,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Do you want to use this photo for your profile?',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65C00),
              foregroundColor: Colors.white,
            ),
            child: Text('Confirm', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    if (_photoUrl == null || _photoUrl!.isEmpty) {
      _showErrorSnackBar('Please upload your profile photo.');
      return;
    }

    if (_dob == null) {
      _showErrorSnackBar('Please select your date of birth.');
      return;
    }

    if (_addressController.text.trim().isEmpty) {
      _showErrorSnackBar('Please enter your address.');
      return;
    }

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
      final String gender = _gender;
      final String? dobStr = _dob != null ? _dob!.toIso8601String().split('T')[0] : null;

      final email = user.email ?? '';
      final Map<String, dynamic> upsertData = {
        'id': user.id,
        'full_name': name,
        'nickname': name.split(' ').first,
        'phone': phone,
        'gender': gender,
        'date_of_birth': dobStr,
        'photo_url': _photoUrl,
        'role': 'admin',
        'address': _addressController.text.trim(),
      };
      if (email.isNotEmpty) {
        upsertData['email'] = email;
      }

      // Update database profile record
      await supabase.from('users').upsert(upsertData, onConflict: 'id');
      if (!mounted) return;

      _showSuccessSnackBar('Profile completed successfully! ✓');
      if (!mounted) return;
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
        _showErrorSnackBar('Error saving profile: ${e.message}');
      }
    } catch (e) {
      _showErrorSnackBar('Error saving profile: $e');
    } finally {
      setState(() => _isSaving = false);
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
              'Complete Profile',
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
                        // Photo Card
                        Container(
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
                              // Profile Image Upload Zone
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
                                        onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
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
                                'Tap camera icon to upload profile picture',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF6B7280)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '“Use your real photo for verification purposes.”',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFE65C00), fontWeight: FontWeight.w600, fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),

                      // Inputs Card
                      Container(
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
                            Text('Full Name *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _nameController,
                              style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
                              decoration: InputDecoration(
                                hintText: 'Your Name',
                                hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
                                prefixIcon: const Icon(Icons.person_outline, size: 20),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
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
                                          fontSize: 11,
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
                                  borderRadius: BorderRadius.circular(12),
                                  color: Colors.white,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _dob == null
                                          ? 'Select your DOB'
                                          : '${_dob!.day} ${_getMonthName(_dob!.month)} ${_dob!.year}',
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

                            Text('Contact Number *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF3ED),
                                    border: Border.all(color: const Color(0xFFE5E7EB)),
                                    borderRadius: BorderRadius.circular(12),
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
                                    style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
                                    decoration: InputDecoration(
                                      hintText: '98765 43210',
                                      hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Color(0xFFE65C00), width: 1.5),
                                      ),
                                    ),
                                    validator: (v) => v == null || v.trim().length < 10 ? 'Enter valid phone' : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            Text('Email Address', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
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

                            Text('Address *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _addressController,
                              style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText: 'Enter your complete address',
                                hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF)),
                                prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Save Button
                      ElevatedButton(
                        onPressed: _isSaving ? null : _handleSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
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

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
}
