import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_cropper/image_cropper.dart';
import '../core/image_optimizer.dart';


class LibrarySetupStage1Screen extends StatefulWidget {
  const LibrarySetupStage1Screen({super.key});

  @override
  State<LibrarySetupStage1Screen> createState() => _LibrarySetupStage1ScreenState();
}

class _LibrarySetupStage1ScreenState extends State<LibrarySetupStage1Screen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _streetController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pinController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();

  final _customAmenityController = TextEditingController();

  String _libraryCode = '';
  String? _libraryId;
  bool _isLoading = false;
  bool _isUploadingCover = false;
  bool _isUploadingGallery = false;
  
  // Cover photo URL
  String? _coverPhotoUrl;

  // Additional facility photos (Up to 4)
  final List<String> _uploadedPhotos = [];

  final List<String> _recommendedAmenities = [
    'Air Conditioning (AC)',
    'High-Speed Wi-Fi',
    'Personal Lockers',
    'RO Drinking Water',
    'CCTV Surveillance',
    'Discussion Sections',
    'Parking Space',
    'Washroom'
  ];

  final List<String> _availableAmenities = [
    'Air Conditioning (AC)',
    'High-Speed Wi-Fi',
    'Personal Lockers',
    'RO Drinking Water',
    'CCTV Surveillance',
    'Discussion Sections',
    'Parking Space',
    'Washroom'
  ];
  List<String> _selectedAmenities = [];

  final List<String> _indianStates = [
    'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh',
    'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka',
    'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram',
    'Nagaland', 'Odisha', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu',
    'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
    'Delhi', 'Jammu & Kashmir', 'Ladakh', 'Puducherry'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadExistingLibrary();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pinController.dispose();
    _emergencyPhoneController.dispose();
    _customAmenityController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingLibrary() async {
    setState(() => _isLoading = true);
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user != null) {
      try {
        debugPrint('--- [STAGE 1] Loading library details for owner_id: ${user.id} ---');
        final Object? args = ModalRoute.of(context)?.settings.arguments;
        String? passedId;
        if (args is String) {
          passedId = args;
        }
        debugPrint('Passed route arguments (libraryId): $passedId');

        final query = supabase.from('libraries').select().eq('owner_id', user.id);
        final libData = passedId != null
            ? await query.eq('id', passedId).maybeSingle()
            : await query.maybeSingle();

        debugPrint('Supabase query result libData: $libData');

        if (libData != null) {
          _libraryId = libData['id'];
          _libraryCode = libData['library_code'] ?? '';
          _nameController.text = libData['name'] ?? '';
          _streetController.text = libData['address_street'] ?? '';
          _cityController.text = libData['address_city'] ?? '';
          _stateController.text = libData['address_state'] ?? '';
          _pinController.text = libData['address_pincode'] ?? '';
          _emergencyPhoneController.text = libData['emergency_phone'] ?? '';
          _coverPhotoUrl = libData['cover_photo_url'];

          debugPrint('Controller values after assignment:');
          debugPrint('  _libraryId: $_libraryId');
          debugPrint('  name: ${_nameController.text}');
          debugPrint('  street: ${_streetController.text}');
          debugPrint('  city: ${_cityController.text}');
          debugPrint('  state: ${_stateController.text}');
          debugPrint('  pincode: ${_pinController.text}');
          debugPrint('  emergency_phone: ${_emergencyPhoneController.text}');
          debugPrint('  coverPhotoUrl: $_coverPhotoUrl');

          if (libData['amenities'] != null) {
            _selectedAmenities = List<String>.from(libData['amenities']);
            for (final amt in _selectedAmenities) {
              if (!_availableAmenities.contains(amt)) {
                _availableAmenities.add(amt);
              }
            }
          }

          final images = libData['gallery_urls'] as List?;
          if (images != null) {
            _uploadedPhotos.clear();
            _uploadedPhotos.addAll(List<String>.from(images));
          } else {
            // Check photos array if gallery_urls was empty
            final photosArr = libData['photos'] as List?;
            if (photosArr != null && photosArr.isNotEmpty) {
              _uploadedPhotos.clear();
              // Skip first one if we assume it's cover photo
              if (_coverPhotoUrl == null) {
                _coverPhotoUrl = photosArr.first.toString();
                if (photosArr.length > 1) {
                  _uploadedPhotos.addAll(List<String>.from(photosArr.sublist(1)));
                }
              } else {
                _uploadedPhotos.addAll(List<String>.from(photosArr));
              }
            }
          }
        } else {
          debugPrint('No library record found matching current criteria.');
        }
      } catch (e, stackTrace) {
        debugPrint('EXCEPTION in _loadExistingLibrary: $e');
        debugPrint('Stack trace: $stackTrace');
      }
    }
    setState(() => _isLoading = false);
  }



  String _generateTempLibraryCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    final code = List.generate(6, (index) => chars[rand.nextInt(chars.length)]).join();
    return 'TEMP-$code';
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: const Color(0xFFE65C00),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<String> _ensureLibraryId() async {
    if (_libraryId != null) return _libraryId!;
    
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('No user session found');

    // Ensure users table record exists to prevent libraries_owner_id_fkey violation
    try {
      final userData = await supabase.from('users').select('id').eq('id', user.id).maybeSingle();
      if (userData == null) {
        await supabase.from('users').insert({
          'id': user.id,
          'email': user.email ?? '',
          'full_name': 'Super Admin',
          'role': 'admin',
        });
        debugPrint('Placeholder user profile inserted successfully.');
      }
    } catch (e) {
      debugPrint('Error ensuring user profile: $e');
    }

    final tempCode = _generateTempLibraryCode();
    final newLib = await supabase.from('libraries').insert({
      'owner_id': user.id,
      'name': _nameController.text.trim().isEmpty ? 'My Library Space' : _nameController.text.trim(),
      'library_code': tempCode, 
      'address_city': _cityController.text.trim().isEmpty ? 'City' : _cityController.text.trim(),
      'status': 'setup',
    }).select().single();

    _libraryId = newLib['id'];
    _libraryCode = tempCode;
    return _libraryId!;
  }

  Future<ImageSource?> _showImageSourceBottomSheet(BuildContext context, String title) async {
    return await showModalBottomSheet<ImageSource?>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
                child: Text(
                  title,
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFFE65C00)),
                title: Text('Camera (Take Photo)', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFFE65C00)),
                title: Text('Gallery (Choose Photo)', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
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

  Future<bool> _showPreviewConfirmationDialog(BuildContext context, XFile image, String title) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            title,
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Do you want to upload this selected photo?',
                style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF4B5563)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.file(
                    File(image.path),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(color: const Color(0xFF9CA3AF), fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Upload',
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    ) ?? false;
  }

  Future<void> _uploadCoverPhoto() async {
    final ImageSource? source = await _showImageSourceBottomSheet(context, 'Choose Cover Photo Source');
    if (!mounted) return;
    if (source == null) return;

    setState(() => _isUploadingCover = true);
    try {
      // permission_handler, image_cropper and camera capture are MOBILE-ONLY
      // plugins — on Windows/macOS/Linux desktop (and web) they have no platform
      // implementation and throw a MissingPluginException, which force-closes the
      // app. Only run that path on Android/iOS; everywhere else fall straight
      // through to image_picker's file selection and skip cropping.
      final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

      // 1. Request runtime permission
      if (isMobile) {
        bool hasPermission = false;
        if (source == ImageSource.camera) {
          hasPermission = await _requestCameraPermission();
        } else {
          hasPermission = await _requestGalleryPermission();
          if (!mounted) return;
        }

        if (!hasPermission) {
          _showErrorSnackBar('Permission denied. Please grant permission in settings.');
          return;
        }
      }

      // 2. Pick image
      final picker = ImagePicker();
      XFile? image;
      try {
        image = await picker.pickImage(
          source: source,
          maxWidth: 1024,
          imageQuality: 85,
        );
      } catch (e) {
        debugPrint('pickImage failed: $e');
        _showErrorSnackBar(source == ImageSource.camera
            ? 'Camera capture isn\'t supported on this device — choose from gallery/files instead.'
            : 'Could not open the file picker on this device.');
        return;
      }

      if (image == null) return;
      if (!mounted) return;

      // Crop Image to landscape 16:9 (mobile only)
      CroppedFile? croppedFile;
      bool cropSuccessOrCancel = false;
      if (isMobile) {
      try {
        croppedFile = await ImageCropper().cropImage(
          sourcePath: image.path,
          aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Cover Photo',
              toolbarColor: const Color(0xFFE65C00),
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.ratio16x9,
              lockAspectRatio: true,
              cropStyle: CropStyle.rectangle,
            ),
            IOSUiSettings(
              title: 'Crop Cover Photo',
              aspectRatioLockEnabled: true,
              resetAspectRatioEnabled: false,
              cropStyle: CropStyle.rectangle,
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

      // 3. Show preview dialog
      if (!mounted) return;
      final bool confirmed = await _showPreviewConfirmationDialog(context, XFile(finalPath), 'Confirm Cover Photo Upload');
      if (!confirmed) return;

      // 4. Upload
      final libId = await _ensureLibraryId();
      final bytes = await ImageOptimizer.compressImage(finalPath);
      final path = 'library_photos/$libId/cover.jpg';
      
      final supabase = Supabase.instance.client;

      // Upload cover directly to pre-provisioned assets bucket

      await supabase.storage.from('silence_assets').uploadBinary(
        path,
        Uint8List.fromList(bytes),
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          cacheControl: '3600', 
          upsert: true,
        ),
      );
      if (!mounted) return;

      final publicUrl = supabase.storage.from('silence_assets').getPublicUrl(path);
      
      setState(() {
        _coverPhotoUrl = publicUrl;
      });

      // Update the library database record directly with the new cover photo URL if library ID exists
      try {
        final photosList = <String>[];
        photosList.add(publicUrl);
        photosList.addAll(_uploadedPhotos);

        await supabase.from('libraries').update({
          'photos': photosList,
        }).eq('id', libId);
        if (!mounted) return;
      } catch (_) {}

      _showSuccessSnackBar('Cover photo uploaded successfully! ✓');
    } catch (e) {
      debugPrint('Cover upload failed: $e');
      _showErrorSnackBar('Cover upload failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isUploadingCover = false);
      }
    }
  }

  Future<void> _uploadGalleryPhoto() async {
    if (_uploadedPhotos.length >= 4) {
      _showErrorSnackBar('You can upload up to 4 photos only.');
      return;
    }

    final ImageSource? source = await _showImageSourceBottomSheet(context, 'Choose Gallery Photo Source');
    if (!mounted) return;
    if (source == null) return;

    setState(() => _isUploadingGallery = true);
    try {
      // permission_handler, image_cropper and camera capture are MOBILE-ONLY
      // plugins — on Windows/macOS/Linux desktop (and web) they have no platform
      // implementation and throw a MissingPluginException, which force-closes the
      // app. Only run that path on Android/iOS; everywhere else fall straight
      // through to image_picker's file selection and skip cropping.
      final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

      // 1. Request runtime permission
      if (isMobile) {
        bool hasPermission = false;
        if (source == ImageSource.camera) {
          hasPermission = await _requestCameraPermission();
        } else {
          hasPermission = await _requestGalleryPermission();
          if (!mounted) return;
        }

        if (!hasPermission) {
          _showErrorSnackBar('Permission denied. Please grant permission in settings.');
          return;
        }
      }

      // 2. Pick image
      final picker = ImagePicker();
      XFile? image;
      try {
        image = await picker.pickImage(
          source: source,
          maxWidth: 1024,
          imageQuality: 85,
        );
      } catch (e) {
        debugPrint('pickImage failed: $e');
        _showErrorSnackBar(source == ImageSource.camera
            ? 'Camera capture isn\'t supported on this device — choose from gallery/files instead.'
            : 'Could not open the file picker on this device.');
        return;
      }

      if (image == null) return;
      if (!mounted) return;

      // Crop Image to landscape 16:9 (mobile only)
      CroppedFile? croppedFile;
      bool cropSuccessOrCancel = false;
      if (isMobile) {
      try {
        croppedFile = await ImageCropper().cropImage(
          sourcePath: image.path,
          aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Photo',
              toolbarColor: const Color(0xFFE65C00),
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.ratio16x9,
              lockAspectRatio: true,
              cropStyle: CropStyle.rectangle,
            ),
            IOSUiSettings(
              title: 'Crop Photo',
              aspectRatioLockEnabled: true,
              resetAspectRatioEnabled: false,
              cropStyle: CropStyle.rectangle,
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

      // 3. Show preview dialog
      if (!mounted) return;
      final bool confirmed = await _showPreviewConfirmationDialog(context, XFile(finalPath), 'Confirm Gallery Photo Upload');
      if (!confirmed) return;

      // 4. Upload
      final libId = await _ensureLibraryId();
      final bytes = await ImageOptimizer.compressImage(finalPath);

      final index = _uploadedPhotos.length + 1;
      final path = 'library_photos/$libId/gallery_$index.jpg';
      
      final supabase = Supabase.instance.client;

      // Upload gallery photo directly to pre-provisioned assets bucket

      await supabase.storage.from('silence_assets').uploadBinary(
        path,
        Uint8List.fromList(bytes),
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          cacheControl: '3600', 
          upsert: true,
        ),
      );
      if (!mounted) return;

      final publicUrl = supabase.storage.from('silence_assets').getPublicUrl(path);
      
      setState(() {
        _uploadedPhotos.add(publicUrl);
      });

      // Update the library database record directly with updated photos list if library ID exists
      try {
        final photosList = <String>[];
        if (_coverPhotoUrl != null) photosList.add(_coverPhotoUrl!);
        photosList.addAll(_uploadedPhotos);

        await supabase.from('libraries').update({
          'photos': photosList,
        }).eq('id', libId);
        if (!mounted) return;
      } catch (_) {}

      _showSuccessSnackBar('Gallery photo uploaded successfully! ✓');
    } catch (e) {
      debugPrint('Gallery upload failed: $e');
      _showErrorSnackBar('Gallery upload failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isUploadingGallery = false);
      }
    }
  }


  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) return;

      final photosList = <String>[];
      if (_coverPhotoUrl != null) photosList.add(_coverPhotoUrl!);
      photosList.addAll(_uploadedPhotos);

      if (_libraryId == null) {
        // Ensure public.users row exists before inserting library (FK guard)
        try {
          await supabase.from('users').upsert({
            'id': user.id,
            'email': user.email ?? '',
            'full_name': 'Admin',
            'role': 'admin',
          }, onConflict: 'id');
        } catch (e) {
          debugPrint('User upsert error (non-fatal): $e');
        }

        // Create new library
        final newLib = await supabase.from('libraries').insert({
          'owner_id': user.id,
          'name': _nameController.text.trim(),
          'library_code': _libraryCode,
          'address_street': _streetController.text.trim(),
          'address_city': _cityController.text.trim(),
          'address_state': _stateController.text.trim(),
          'address_pincode': _pinController.text.trim(),
          'emergency_phone': _emergencyPhoneController.text.trim(),
          'amenities': _selectedAmenities,
          'photos': photosList,
          'status': 'setup',
        }).select().single();
        _libraryId = newLib['id'];
      } else {
        // Update existing library
        await supabase.from('libraries').update({
          'name': _nameController.text.trim(),
          'address_street': _streetController.text.trim(),
          'address_city': _cityController.text.trim(),
          'address_state': _stateController.text.trim(),
          'address_pincode': _pinController.text.trim(),
          'emergency_phone': _emergencyPhoneController.text.trim(),
          'photos': photosList,
          'amenities': _selectedAmenities,
          'library_code': _libraryCode,
        }).eq('id', _libraryId!);
        if (!mounted) return;
      }

      _showSuccessSnackBar('Library details saved successfully! ✓');
      if (!mounted) return;
      
      Navigator.pop(context, true); // Pop back to Admin Home and trigger refresh
    } catch (e) {
      _showErrorSnackBar('Error saving library details: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
            'Library Basic Details',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          centerTitle: true,
        ),
        body: _isLoading && _nameController.text.isEmpty
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Basic Details Card (Including Cover Photo)
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
                          
                          // COVER PHOTO UPLOAD ZONE (Matching premium circular profile photo card style)
                          Center(
                            child: Column(
                              children: [
                                Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 48,
                                      backgroundColor: const Color(0xFFFFF7F0),
                                      backgroundImage: _coverPhotoUrl != null && _coverPhotoUrl!.isNotEmpty
                                          ? ResizeImage(NetworkImage(_coverPhotoUrl!), width: 200)
                                          : null,
                                      child: _coverPhotoUrl == null || _coverPhotoUrl!.isEmpty
                                          ? const Icon(Icons.camera_alt, size: 36, color: Color(0xFFE65C00))
                                          : null,
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: GestureDetector(
                                        onTap: _isUploadingCover ? null : _uploadCoverPhoto,
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFE65C00),
                                            shape: BoxShape.circle,
                                          ),
                                          child: _isUploadingCover
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                  ),
                                                )
                                              : const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Cover Photo',
                                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E)),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tap camera icon to upload cover photo',
                                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF6B7280)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          Text('Library Name *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _nameController,
                            style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
                            decoration: InputDecoration(
                              hintText: 'Enter library name',
                              hintStyle: TextStyle(color: const Color(0xFF9CA3AF).withValues(alpha: 0.5)),
                              prefixIcon: const Icon(Icons.store_outlined, size: 20),
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                          ),
                          const SizedBox(height: 16),

                          Text('Street Address', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _streetController,
                            style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
                            decoration: InputDecoration(
                              hintText: 'Enter street address',
                              hintStyle: TextStyle(color: const Color(0xFF9CA3AF).withValues(alpha: 0.5)),
                              prefixIcon: const Icon(Icons.map_outlined, size: 20),
                            ),
                          ),
                          const SizedBox(height: 16),

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('City *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                                    const SizedBox(height: 6),
                                    TextFormField(
                                      controller: _cityController,
                                      style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
                                      decoration: InputDecoration(
                                        hintText: 'Enter city',
                                        hintStyle: TextStyle(color: const Color(0xFF9CA3AF).withValues(alpha: 0.5)),
                                      ),
                                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('State', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                                    const SizedBox(height: 6),
                                    DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      initialValue: _stateController.text.isNotEmpty && _indianStates.contains(_stateController.text)
                                          ? _stateController.text
                                          : null,
                                      hint: Text('Select State', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                                      decoration: const InputDecoration(
                                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      ),
                                      items: _indianStates.map((state) {
                                        return DropdownMenuItem<String>(
                                          value: state,
                                          child: Text(state, style: const TextStyle(fontSize: 14)),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() {
                                            _stateController.text = val;
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Text('PIN Code', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _pinController,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
                            decoration: InputDecoration(
                              hintText: 'Enter PIN code',
                              hintStyle: TextStyle(color: const Color(0xFF9CA3AF).withValues(alpha: 0.5)),
                              prefixIcon: const Icon(Icons.pin_drop_outlined, size: 20),
                            ),
                          ),
                          const SizedBox(height: 16),

                          Text('Emergency Phone *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _emergencyPhoneController,
                            keyboardType: TextInputType.phone,
                            style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
                            decoration: InputDecoration(
                              hintText: 'Enter emergency phone',
                              hintStyle: TextStyle(color: const Color(0xFF9CA3AF).withValues(alpha: 0.5)),
                              prefixIcon: const Icon(Icons.emergency_outlined, size: 20),
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Photos Card (Up to 4)
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
                          Text(
                            'Library Photos',
                            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 4),
                          Text('Add Photos (up to 4) - horizontal 16:9 aspect ratio', style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF9CA3AF))),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ..._uploadedPhotos.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final url = entry.value;
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        width: 120,
                                        height: 68,
                                        decoration: BoxDecoration(
                                          border: Border.all(color: const Color(0xFFE5E7EB)),
                                        ),
                                        child: Image.network(
                                          url,
                                          fit: BoxFit.cover,
                                          cacheWidth: 360,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: -6,
                                      right: -6,
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _uploadedPhotos.removeAt(idx);
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.close, size: 12, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }),
                              if (_uploadedPhotos.length < 4)
                                GestureDetector(
                                  onTap: _isUploadingGallery ? null : _uploadGalleryPhoto,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                        width: 120,
                                        height: 68,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: const Color(0xFFE65C00).withValues(alpha: 0.4), style: BorderStyle.solid),
                                        ),
                                        child: const Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.add, size: 20, color: Color(0xFFE65C00)),
                                              SizedBox(height: 2),
                                              Text('Add Photo', style: TextStyle(fontSize: 9, color: Color(0xFFE65C00), fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (_isUploadingGallery)
                                        Container(
                                          width: 120,
                                          height: 68,
                                          decoration: BoxDecoration(
                                            color: Colors.black26,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Center(
                                            child: CircularProgressIndicator(
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Amenities Card
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
                          Text('Amenities', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                          const SizedBox(height: 12),
                          if (_availableAmenities.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Text(
                                'No amenities listed yet. Add custom amenities below.',
                                style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: const Color(0xFF9CA3AF)),
                              ),
                            ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _availableAmenities.map((amenity) {
                              final isSelected = _selectedAmenities.contains(amenity);
                              final isRecommended = _recommendedAmenities.contains(amenity);
                              return Container(
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFFE65C00) : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFFE65C00) : const Color(0xFFE5E7EB),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          if (isSelected) {
                                            _selectedAmenities.remove(amenity);
                                          } else {
                                            _selectedAmenities.add(amenity);
                                          }
                                        });
                                      },
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          left: 12,
                                          right: isRecommended ? 12 : 6,
                                          top: 8,
                                          bottom: 8,
                                        ),
                                        child: Row(
                                          children: [
                                            Text(
                                              amenity,
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: isSelected ? Colors.white : const Color(0xFF6B7280),
                                              ),
                                            ),
                                            if (isSelected) ...[
                                              const SizedBox(width: 4),
                                              const Icon(Icons.check, size: 10, color: Colors.white),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (!isRecommended)
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _availableAmenities.remove(amenity);
                                            _selectedAmenities.remove(amenity);
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.only(right: 8.0, left: 2.0, top: 8.0, bottom: 8.0),
                                          child: Icon(
                                            Icons.close,
                                            size: 12,
                                            color: isSelected ? Colors.white70 : const Color(0xFF9CA3AF),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _customAmenityController,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: 'Add custom amenity...',
                                    hintStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF9CA3AF)),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: Color(0xFFE65C00)),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  style: GoogleFonts.inter(fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () {
                                  final text = _customAmenityController.text.trim();
                                  if (text.isNotEmpty) {
                                    setState(() {
                                      if (!_availableAmenities.contains(text)) {
                                        _availableAmenities.add(text);
                                      }
                                      if (!_selectedAmenities.contains(text)) {
                                        _selectedAmenities.add(text);
                                      }
                                      _customAmenityController.clear();
                                    });
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE65C00),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                                child: const Icon(Icons.add, color: Colors.white, size: 18),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),



                    // Save Button
                    ElevatedButton(
                      onPressed: _isLoading || _isUploadingCover || _isUploadingGallery ? null : _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65C00),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                            )
                          : Text('Save Library Details', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
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
