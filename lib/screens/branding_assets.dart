import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/admin_settings_service.dart';
import '../core/image_optimizer.dart';

class BrandingAssetsScreen extends StatefulWidget {
  const BrandingAssetsScreen({super.key});

  @override
  State<BrandingAssetsScreen> createState() => _BrandingAssetsScreenState();
}

class _BrandingAssetsScreenState extends State<BrandingAssetsScreen> {
  bool _isLoading = false;
  String? _libId;
  String? _logoUrl;
  Color _selectedAccent = const Color(0xFFE65C00);

  final List<Color> _brandPalette = [
    const Color(0xFFE65C00), // Default Orange
    const Color(0xFF0F172A), // Slate Dark
    const Color(0xFF3B82F6), // Ocean Blue
    const Color(0xFF10B981), // Emerald Green
    const Color(0xFF7C3AED), // Indigo Purple
    const Color(0xFFEC4899), // Crimson Pink
  ];

  @override
  void initState() {
    super.initState();
    _loadBrandingSettings();
  }

  Future<void> _loadBrandingSettings() async {
    setState(() => _isLoading = true);
    _libId = await AdminSettingsService.firstOwnedLibraryId();
    final settings = await AdminSettingsService.load(
      scope: 'branding',
      libraryId: _libId,
    );
    if (!mounted) return;
    _logoUrl = settings['logo_url']?.toString();
    final colorVal = settings['accent_color'];
    if (colorVal != null) {
      _selectedAccent = Color(colorVal is int ? colorVal : int.parse(colorVal.toString()));
    }
    setState(() => _isLoading = false);
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
                'Do you want to upload this logo?',
                style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF4B5563)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 120,
                  height: 120,
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

  Future<void> _uploadLogo() async {
    if (_libId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot upload logo: No library associated with this account yet.'), backgroundColor: Colors.red),
      );
      return;
    }

    final ImageSource? source = await _showImageSourceBottomSheet(context, 'Choose Logo Photo Source');
    if (!mounted) return;
    if (source == null) return;

    setState(() => _isLoading = true);
    try {
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
          if (!mounted) return;
        }

        if (!hasPermission) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permission denied. Please grant permission in settings.'), backgroundColor: Colors.red),
          );
          return;
        }
      }

      final picker = ImagePicker();
      XFile? image;
      try {
        image = await picker.pickImage(
          source: source,
          maxWidth: 512,
          imageQuality: 85,
        );
      } catch (e) {
        debugPrint('pickImage failed: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(source == ImageSource.camera
                ? 'Camera capture isn\'t supported on this device — choose from gallery/files instead.'
                : 'Could not open the file picker on this device.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (image == null) return;
      if (!mounted) return;

      CroppedFile? croppedFile;
      bool cropSuccessOrCancel = false;
      if (isMobile) {
      try {
        croppedFile = await ImageCropper().cropImage(
          sourcePath: image.path,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Brand Logo',
              toolbarColor: const Color(0xFFE65C00),
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
            ),
            IOSUiSettings(
              title: 'Crop Brand Logo',
              aspectRatioLockEnabled: true,
              resetAspectRatioEnabled: false,
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

      final bool confirmed = await _showPreviewConfirmationDialog(context, XFile(finalPath), 'Confirm Logo Upload');
      if (!confirmed) return;

      final bytes = await ImageOptimizer.compressImage(finalPath);
      final path = 'library_photos/$_libId/logo.jpg';
      
      final supabase = Supabase.instance.client;

      // Upload branding logo directly to pre-provisioned assets bucket

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
        _logoUrl = publicUrl;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logo uploaded successfully! ✓'), backgroundColor: Color(0xFFE65C00)),
      );
    } catch (e) {
      debugPrint('Logo upload failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logo upload failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveBrandingSettings() async {
    setState(() => _isLoading = true);
    await AdminSettingsService.save(
      scope: 'branding',
      libraryId: _libId,
      value: {
        'logo_url': _logoUrl,
        'accent_color': _selectedAccent.toARGB32(),
      },
    );
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Branding assets updated successfully! ✓'), backgroundColor: Color(0xFFE65C00)),
    );
    setState(() => _isLoading = false);
    Navigator.pop(context);
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
              'Branding & Print Collateral',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Logo & Identity section
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Library Visual Assets',
                              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: GestureDetector(
                                onTap: _uploadLogo,
                                child: Stack(
                                  children: [
                                    Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF3ED),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: _selectedAccent, width: 1.5),
                                        image: _logoUrl != null
                                            ? DecorationImage(image: NetworkImage(_logoUrl!), fit: BoxFit.cover)
                                            : null,
                                      ),
                                      child: _logoUrl == null
                                          ? Center(child: Icon(Icons.palette_outlined, size: 28, color: _selectedAccent))
                                          : null,
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: _selectedAccent,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.add_photo_alternate, size: 14, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: Text(
                                'Tap circle to upload brand logo',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 2. Color Palette Accent Selection
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'App Primary Accent Color',
                              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Choose the dominant secondary color used across your member portals.',
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: _brandPalette.map((color) {
                                final isSelected = color.toARGB32() == _selectedAccent.toARGB32();
                                return GestureDetector(
                                  onTap: () {
                                    setState(() => _selectedAccent = color);
                                  },
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected ? Colors.white : Colors.transparent,
                                        width: 3,
                                      ),
                                      boxShadow: [
                                        if (isSelected)
                                          BoxShadow(
                                            color: color.withValues(alpha: 0.4),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                          ),
                                      ],
                                    ),
                                    child: isSelected
                                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                                        : null,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 3. Printable Collateral Templates
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Printable Assets & Collateral',
                              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 12),
                            _buildCollateralRow('A4 Join QR Poster', 'Premium desk board / entry standee poster format', Icons.crop_portrait),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildCollateralRow('A4 Attendance QR Poster', 'Printable Check-in scanner desk banner template', Icons.crop_portrait_outlined),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildCollateralRow('Desk Allocation Tags', 'Printable stickers with desk labels & barcodes', Icons.tag),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildCollateralRow('Student Conduct Booklet', 'Rules & guidelines pamphlet blueprint', Icons.menu_book),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // 4. Update Button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        onPressed: _saveBrandingSettings,
                        child: Text(
                          'Save Branding Config',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildCollateralRow(String title, String subtitle, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3ED),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFFE65C00), size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download, size: 16, color: Color(0xFF64748B)),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Generating $title PDF for sharing...')),
              );
            },
          ),
        ],
      ),
    );
  }
}
