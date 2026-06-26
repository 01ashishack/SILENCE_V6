import 'dart:io';
import '../theme/app_palette.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uuid/uuid.dart';
import '../core/image_optimizer.dart';
import '../utils/error_messages.dart';
import '../core/plan_service.dart';
import '../widgets/upgrade_sheet.dart';
import 'library_public_profile_screen.dart';
import 'payment_methods_screen.dart';
import 'admin/copy_library_settings_screen.dart';
import '../core/active_library_store.dart';
import '../widgets/change_password_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';


class AdminProfileTab extends StatefulWidget {
  final String? libraryId;
  final String libraryName;
  final String? coverPhotoUrl;
  final List<dynamic> myLibraries;
  final Function(String libId) onLibraryChanged;
  final VoidCallback onLogout;
  final String adminName;
  final String adminEmail;
  final String adminPhone;
  final VoidCallback? onLibraryUpdated;

  const AdminProfileTab({
    super.key,
    required this.libraryId,
    required this.libraryName,
    required this.coverPhotoUrl,
    required this.myLibraries,
    required this.onLibraryChanged,
    required this.onLogout,
    required this.adminName,
    required this.adminEmail,
    required this.adminPhone,
    this.onLibraryUpdated,
  });

  @override
  State<AdminProfileTab> createState() => _AdminProfileTabState();
}

class _AdminProfileTabState extends State<AdminProfileTab> with AutomaticKeepAliveClientMixin {
  final _supabase = Supabase.instance.client;
  bool _isUploadingPhoto = false;
  bool _isProfileComplete = true;

  // Dynamic Profile Fields
  String _adminName = '';
  String? _adminPhotoUrl;
  List<Map<String, dynamic>> _myLibrariesList = [];
  bool? _currentLibraryVerified;
  DateTime? _currentLibraryVerifiedAt;
  String? _selectedLibraryIdToManage;
  bool _isAppOwner = false; // gates the Recovery Console entry

  Widget _buildDeleteLibraryButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _confirmDeleteLibrary,
        icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFDC2626)),
        label: Text('Delete this library',
            style: GoogleFonts.inter(
                fontSize: 13.5, fontWeight: FontWeight.bold, color: const Color(0xFFDC2626))),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFFECACA)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteLibrary() async {
    final libId = _selectedLibraryIdToManage ?? widget.libraryId;
    if (libId == null) return;
    final lib = _myLibrariesList.firstWhere(
      (l) => l['id'] == libId,
      orElse: () => <String, dynamic>{},
    );
    final name = (lib['name'] ?? 'this library').toString();
    final confirmCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final canDelete = confirmCtrl.text.trim() == name.trim();
          return AlertDialog(
            backgroundColor: context.palette.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Delete library?',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFFDC2626))),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This permanently deletes "$name" and ALL its data — members, '
                  'seats, shifts, attendance, payments and settings. This cannot '
                  'be undone.',
                  style: GoogleFonts.inter(fontSize: 13, height: 1.45, color: context.palette.textSecondary),
                ),
                const SizedBox(height: 14),
                Text('Type the library name to confirm:',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: confirmCtrl,
                  onChanged: (_) => setD(() {}),
                  decoration: InputDecoration(
                    hintText: name,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.grey[600])),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                onPressed: canDelete ? () => Navigator.pop(ctx, true) : null,
                child: Text('Delete', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
    confirmCtrl.dispose();
    if (confirmed != true) return;

    try {
      await _supabase.from('libraries').delete().eq('id', libId);
      // If the deleted library was the persisted active one, clear it so the
      // app re-picks another owned library on reload.
      final persisted = await ActiveLibraryStore.load();
      if (persisted == libId) await ActiveLibraryStore.save(null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$name" deleted.'), backgroundColor: const Color(0xFF334155)),
      );
      widget.onLibraryUpdated?.call();
      _loadProfileData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete the library: ${friendlyError(e)}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant AdminProfileTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.myLibraries != widget.myLibraries || oldWidget.libraryId != widget.libraryId) {
      _myLibrariesList = List<Map<String, dynamic>>.from(widget.myLibraries.map((lib) {
        final coverPhotoUrl = lib['cover_photo_url'] ?? (lib['photos'] != null && (lib['photos'] as List).isNotEmpty ? (lib['photos'] as List).first.toString() : null);
        return {
          'id': lib['id'],
          'name': lib['name'] ?? 'Study Center',
          'address_city': lib['address_city'] ?? 'City',
          'address_street': lib['address_street'] ?? '',
          'cover_photo_url': coverPhotoUrl,
          'verified': lib['verified'] ?? false,
          'verified_at': lib['verified_at'] != null ? DateTime.tryParse(lib['verified_at'].toString()) : null,
          'member_count': 0,
          'occupancy_pct': 0,
        };
      }));
      final currentLibId = widget.libraryId ?? (_myLibrariesList.isNotEmpty ? _myLibrariesList.first['id'] : null);
      _selectedLibraryIdToManage = currentLibId;
      _loadProfileData();
    }
  }

  @override
  void initState() {
    super.initState();
    _adminName = widget.adminName;
    _myLibrariesList = List<Map<String, dynamic>>.from(widget.myLibraries.map((lib) {
      final coverPhotoUrl = lib['cover_photo_url'] ?? (lib['photos'] != null && (lib['photos'] as List).isNotEmpty ? (lib['photos'] as List).first.toString() : null);
      return {
        'id': lib['id'],
        'name': lib['name'] ?? 'Study Center',
        'address_city': lib['address_city'] ?? 'City',
        'address_street': lib['address_street'] ?? '',
        'cover_photo_url': coverPhotoUrl,
        'verified': lib['verified'] ?? false,
        'verified_at': lib['verified_at'] != null ? DateTime.tryParse(lib['verified_at'].toString()) : null,
        'member_count': 0,
        'occupancy_pct': 0,
      };
    }));
    final currentLibId = widget.libraryId ?? (_myLibrariesList.isNotEmpty ? _myLibrariesList.first['id'] : null);
    _selectedLibraryIdToManage = currentLibId;
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    if (!mounted) return;
    setState(() {});

    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        // 1. Fetch user data (full name, subscription plan/status, expiry)
        final userData = await _supabase.from('users').select().eq('id', user.id).maybeSingle();
        if (userData != null && mounted) {
          final String name = userData['full_name'] ?? '';
          final String phone = userData['phone'] ?? '';
          final String gender = userData['gender'] ?? '';
          final String dob = userData['date_of_birth'] ?? '';
          final String address = userData['address'] ?? '';
          final String photoUrl = userData['photo_url'] ?? '';

          final bool isComplete = name.isNotEmpty &&
              phone.isNotEmpty &&
              gender.isNotEmpty &&
              dob.isNotEmpty &&
              address.isNotEmpty &&
              photoUrl.isNotEmpty;

          PlanService.instance.hydrateFromRow(userData); // single source of truth for plan name
          setState(() {
            _isProfileComplete = isComplete;
            _adminName = userData['full_name'] ?? widget.adminName;
            _adminPhotoUrl = userData['photo_url'];
            _isAppOwner = userData['is_app_owner'] == true;
          });
        }

        // 2. Fetch owned libraries list
        final libsRes = await _supabase.from('libraries').select().eq('owner_id', user.id);
        final List<Map<String, dynamic>> rawLibs = List<Map<String, dynamic>>.from(libsRes);

        // 3. Enrich libraries
        final List<Map<String, dynamic>> enrichedLibs = [];
        for (var lib in rawLibs) {
          final libId = lib['id'];
          final name = lib['name'] ?? 'Study Center';
          final addressCity = lib['address_city'] ?? 'City';
          final addressStreet = lib['address_street'] ?? '';
          final coverPhotoUrl = lib['cover_photo_url'] ?? (lib['photos'] != null && (lib['photos'] as List).isNotEmpty ? (lib['photos'] as List).first.toString() : null);

          // Fetch member count (status != 'exited')
          int memberCount = 0;
          try {
            final membersRes = await _supabase.from('memberships').select('id').eq('library_id', libId).neq('status', 'exited');
            memberCount = membersRes.length;
          } catch (_) {}

          // Fetch seats/occupancy
          int occupancyPct = 0;
          try {
            final seatsRes = await _supabase.from('seats').select('status').eq('library_id', libId);
            final totalSeats = seatsRes.length;
            final occupiedSeats = seatsRes.where((s) => s['status'] == 'occupied').length;
            occupancyPct = totalSeats == 0 ? 0 : ((occupiedSeats / totalSeats) * 100).round();
          } catch (_) {}

          enrichedLibs.add({
            ...lib,
            'id': libId,
            'name': name,
            'address_city': addressCity,
            'address_street': addressStreet,
            'cover_photo_url': coverPhotoUrl,
            'verified': lib['verified'] ?? false,
            'verified_at': lib['verified_at'] != null ? DateTime.tryParse(lib['verified_at'].toString()) : null,
            'member_count': memberCount,
            'occupancy_pct': occupancyPct,
          });
        }

        if (mounted) {
          setState(() {
            _myLibrariesList = enrichedLibs;
            // Update selected library verification status
            final currentLibId = widget.libraryId ?? (_myLibrariesList.isNotEmpty ? _myLibrariesList.first['id'] : null);
            if (currentLibId != null) {
              final activeLib = _myLibrariesList.firstWhere((l) => l['id'] == currentLibId, orElse: () => _myLibrariesList.first);
              _currentLibraryVerified = activeLib['verified'] ?? false;
              _currentLibraryVerifiedAt = activeLib['verified_at'];
            }
            if (_selectedLibraryIdToManage != null) {
              final exists = _myLibrariesList.any((l) => l['id'] == _selectedLibraryIdToManage);
              if (!exists) {
                _selectedLibraryIdToManage = currentLibId;
              }
            } else if (currentLibId != null) {
              _selectedLibraryIdToManage = currentLibId;
            }
          });
        }
      } catch (e) {
        debugPrint('Error loading profile tab data: $e');
      }
    }

    if (mounted) {
      setState(() {});
    }
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
              child: Text(
                'Choose Photo Source',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFE65C00),
                ),
              ),
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
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Permission denied. Please grant permission in settings.')),
            );
          }
          return;
        }
      }

      final picker = ImagePicker();
      XFile? image;
      try {
        image = await picker.pickImage(
          source: source,
          maxWidth: 512,
          imageQuality: 80,
        );
      } catch (e) {
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

      if (image == null) return;

      // Crop Image to strict 1:1 square (mobile only)
      CroppedFile? croppedFile;
      if (isMobile) {
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
        if (!mounted) return;

        if (croppedFile == null) return;
      }

      setState(() => _isUploadingPhoto = true);

      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final bytes = await ImageOptimizer.compressImage(croppedFile?.path ?? image.path);
      // Admin photo is public-facing (shown on the library's public profile), so
      // it belongs in the PUBLIC silence_assets bucket. The old code uploaded to
      // silence_private then called getPublicUrl() — an unsigned URL on a private
      // bucket never loads (the photo always appeared broken). Public bucket +
      // getPublicUrl is the correct, working pair.
      final path = 'admin_profiles/${user.id}/profile.jpg';
      await _supabase.storage.from('silence_assets').uploadBinary(
        path,
        Uint8List.fromList(bytes),
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );
      final String publicUrl = _supabase.storage.from('silence_assets').getPublicUrl(path);

      // Update user photo_url in Supabase
      await _supabase.from('users').update({'photo_url': publicUrl}).eq('id', user.id);

      if (mounted) {
        setState(() {
          _adminPhotoUrl = publicUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture updated successfully! ✓'), backgroundColor: Color(0xFF10B981)),
        );
        _loadProfileData();
      }
    } catch (e) {
      debugPrint('Error uploading photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading photo: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  // Role change exists ONLY to fix an accidental wrong-role signup. It is
  // allowed within 7 days of signup, PERMANENTLY deletes the current account's
  // data (including any libraries owned), and starts a brand-new Member account.
  // Enforced server-side by change_my_role() (migrations/2026-06-18_role_change_rpc.sql).
  Future<void> _showChangeRoleDialog() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    // 1) Eligibility: only within 7 days of signup.
    DateTime? createdAt;
    try {
      final row = await _supabase
          .from('users')
          .select('created_at')
          .eq('id', user.id)
          .maybeSingle();
      final raw = row?['created_at'] as String?;
      if (raw != null) createdAt = DateTime.tryParse(raw);
    } catch (_) {
      // fall through → treated as not eligible
    }
    if (!mounted) return;

    final withinWindow =
        createdAt != null && DateTime.now().difference(createdAt).inDays < 7;

    if (!withinWindow) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.palette.surface,
          title: Text('Role change not available',
              style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
          content: Text(
            'You can only change your role within 7 days of creating your account. '
            'That window has closed, so your role is now fixed.',
            style:
                GoogleFonts.inter(fontSize: 14, color: context.palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('OK',
                  style: GoogleFonts.inter(
                      color: const Color(0xFFE65C00),
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    // 2) Strict type-to-confirm dialog.
    final hasActiveLibraries = _myLibrariesList.isNotEmpty;
    final confirmController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final canConfirm =
              confirmController.text.trim().toUpperCase() == 'MEMBER';
          return AlertDialog(
            backgroundColor: context.palette.surface,
            title: Text('Switch to Member — start over?',
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    color: context.palette.textPrimary)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFEF4444), size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('This permanently deletes your account',
                                  style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF991B1B))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your current Admin account and ALL its data — including any '
                          'libraries you own, their seats, members and history — will be '
                          'permanently deleted. You will start as a brand-new Member with '
                          'an empty account. This cannot be undone.',
                          style: GoogleFonts.inter(
                              fontSize: 12.5, color: const Color(0xFF991B1B)),
                        ),
                      ],
                    ),
                  ),
                  if (hasActiveLibraries) ...[
                    const SizedBox(height: 10),
                    Text(
                        'You own active libraries — they and their members will be removed.',
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFB45309))),
                  ],
                  const SizedBox(height: 14),
                  Text('Type MEMBER to confirm:',
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.palette.textSecondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: confirmController,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setLocal(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'MEMBER',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: GoogleFonts.inter(
                        color: context.palette.textMuted,
                        fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                onPressed: canConfirm ? () => Navigator.pop(ctx, true) : null,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    disabledBackgroundColor: const Color(0xFFFCA5A5)),
                child: Text('Delete & become Member',
                    style: GoogleFonts.inter(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      await _supabase.rpc('change_my_role', params: {'p_new_role': 'member'});
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await _supabase.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not switch role: $e')),
        );
      }
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);



    final String dateStr = DateFormat('EEE dd/MM').format(DateTime.now()).toUpperCase();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: context.palette.scaffold,
        body: RefreshIndicator(
          onRefresh: _loadProfileData,
          color: const Color(0xFFE65C00),
          backgroundColor: context.palette.surface,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 20,
                    bottom: 24,
                    left: 16,
                    right: 16,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFF6B00),
                        Color(0xFFE65C00),
                      ],
                    ),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircleAvatar(
                                radius: 38,
                                backgroundColor: Colors.white30,
                                child: CircleAvatar(
                                  radius: 36,
                                  backgroundColor: Colors.white24,
                                  backgroundImage: _adminPhotoUrl != null && _adminPhotoUrl!.isNotEmpty
                                      ? CachedNetworkImageProvider(_adminPhotoUrl!)
                                      : null,
                                  child: _adminPhotoUrl == null || _adminPhotoUrl!.isEmpty
                                      ? Text(
                                          _adminName.isNotEmpty ? _adminName[0].toUpperCase() : 'A',
                                          style: GoogleFonts.outfit(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              if (_isUploadingPhoto)
                                const Positioned.fill(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            _adminName,
                                            style: GoogleFonts.outfit(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (_currentLibraryVerified ?? false) ...[
                                          const SizedBox(width: 4),
                                          const Icon(Icons.verified, color: Color(0xFFE65C00), size: 20),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      dateStr,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Admin • ${_myLibrariesList.length} ${_myLibrariesList.length == 1 ? 'Library' : 'Libraries'}',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                // Single source of truth — same plan name as the
                                // Subscription screen & feature gating (Free/Pro/Premium).
                                PlanService.instance.displayPlanName,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.70),
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // 1.5 Library Profile Completeness
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: _buildProfileCompletenessCard(),
                ),

                const SizedBox(height: 24),

                // 2. Your Libraries Section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Text(
                    'Your Libraries',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: context.palette.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                _myLibrariesList.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: context.palette.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.01),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.storefront_outlined, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text(
                                'Manage Your Study Space',
                                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Register your library, configure seats, set timings, and start accepting memberships.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(fontSize: 12.5, color: context.palette.textMuted, height: 1.4),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _isProfileComplete ? () {
                                  Navigator.pushNamed(context, '/admin/library/setup/1').then((_) => _loadProfileData());
                                } : () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Complete your profile first to create a library', style: GoogleFonts.inter()),
                                      backgroundColor: const Color(0xFFE65C00),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isProfileComplete ? const Color(0xFFE65C00) : const Color(0xFFE65C00).withValues(alpha: 0.5),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                                ),
                                child: Text('Create Your First Library', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      )
                    : (_myLibrariesList.length == 1)
                        ? Center(
                            child: _buildSingleLibraryCard(_myLibrariesList.first, isHorizontalList: false),
                          )
                        : SizedBox(
                            height: 200,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              scrollDirection: Axis.horizontal,
                              itemCount: _myLibrariesList.length,
                              itemBuilder: (context, index) {
                                return _buildSingleLibraryCard(_myLibrariesList[index], isHorizontalList: true);
                              },
                            ),
                          ),

                if (_myLibrariesList.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          if (!_isProfileComplete) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Complete your profile first to add a library',
                                    style: GoogleFonts.inter()),
                                backgroundColor: const Color(0xFFE65C00),
                              ),
                            );
                            return;
                          }
                          // 'new' → start a blank NEW library (not edit an existing one).
                          Navigator.pushNamed(context, '/admin/library/setup/1',
                                  arguments: 'new')
                              .then((_) {
                            _loadProfileData();
                            widget.onLibraryUpdated?.call();
                          });
                        },
                        icon: const Icon(Icons.add_business_outlined,
                            size: 18, color: Color(0xFFE65C00)),
                        label: Text('Add Library',
                            style: GoogleFonts.inter(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFE65C00))),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFFFD8BF)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ],

                if (_myLibrariesList.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _buildLibraryManagementGridCard(),
                  const SizedBox(height: 12),
                  _buildDeleteLibraryButton(),
                ],

                const SizedBox(height: 24),

                // 3. Get Verified Badge Section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: _buildVerifiedBadgeCard(),
                ),

                const SizedBox(height: 24),

                // 4. Settings & Actions List
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      _buildSettingsGroup(
                        title: 'Operations',
                        items: [
                          if (_isAppOwner)
                            _buildSettingsItem(context, Icons.shield_moon_outlined,
                                'Recovery Console', '/owner/recovery-console'),
                          _buildSettingsItem(context, Icons.campaign_outlined, 'Announcement History', '/admin/announcements',
                              feature: AdminFeature.announcements, featureLabel: 'Announcements'),
                          _buildSettingsItem(context, Icons.ios_share, 'Exports & Reports', '/admin/exports',
                              feature: AdminFeature.export, featureLabel: 'Exports & reports'),
                          _buildSettingsItem(context, Icons.history_edu_outlined, 'Audit Log', '/admin/audit-log',
                              feature: AdminFeature.auditLog, featureLabel: 'Audit log'),
                          _buildSettingsItem(context, Icons.card_giftcard_outlined, 'Referral Rewards', '/admin/settings/referrals',
                              feature: AdminFeature.referralConfig, featureLabel: 'Referral rewards'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildSettingsGroup(
                        title: 'App & Support',
                        items: [
                          _buildSettingsItem(context, Icons.workspace_premium_outlined, 'Subscription & Billing', '/admin/subscription'),
                          _buildSettingsItem(context, Icons.settings_outlined, 'Settings', '/admin/app-settings'),
                          _buildShareAppItem(),
                          _buildSettingsItem(context, Icons.info_outline, 'About Us', '/admin/about-us'),
                          _buildSettingsItem(context, Icons.support_agent, 'Help & Support', '/admin/help-support'),
                          _buildSettingsItem(context, Icons.gavel, 'Terms & Conditions', '/admin/terms'),
                          _buildSettingsItem(context, Icons.payments_outlined, 'Refund Policy', '/policy/refund'),
                          _buildSettingsItem(context, Icons.cancel_outlined, 'Cancellation Policy', '/policy/cancellation'),
                          _buildSettingsItem(context, Icons.groups_outlined, 'Community Guidelines', '/policy/community'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Privacy & Account (sensitive / destructive actions live here)
                      _buildSettingsGroup(
                        title: 'Privacy & Account',
                        items: [
                          ListTile(
                            leading: const Icon(Icons.vpn_key_outlined, size: 20, color: Color(0xFFE65C00)),
                            title: Text(
                              'Change Password',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: context.palette.textPrimary,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 16, color: Color(0xFF94A3B8)),
                            onTap: () => showChangePasswordSheet(context),
                          ),
                          ListTile(
                            leading: const Icon(Icons.swap_horiz, size: 20, color: Color(0xFFEF4444)),
                            title: Text(
                              'Change Role',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: context.palette.textPrimary,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 16, color: Color(0xFF94A3B8)),
                            onTap: _showChangeRoleDialog,
                          ),
                          ListTile(
                            leading: const Icon(Icons.logout, size: 20, color: Colors.redAccent),
                            title: Text(
                              'Logout',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: context.palette.textPrimary,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 16, color: Color(0xFF94A3B8)),
                            onTap: widget.onLogout,
                          ),
                          ListTile(
                            leading: const Icon(Icons.delete_forever, size: 20, color: Color(0xFFDC2626)),
                            title: Text(
                              'Delete Account',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFDC2626),
                              ),
                            ),
                            subtitle: Text(
                              'Request permanent deletion of your account & library',
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF991B1B)),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 16, color: Color(0xFFDC2626)),
                            onTap: _handleDeleteAccount,
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Honest account-deletion request (admin) ────────────────────────────────
  // No real purge here (that needs the server tier); this records the request
  // so the app-owner can action it, and tells the user the honest status.
  Future<void> _handleDeleteAccount() async {
    final confirmCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final canDelete = confirmCtrl.text.trim().toUpperCase() == 'DELETE';
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Delete your account?',
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold, color: const Color(0xFFDC2626))),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This schedules permanent deletion in 7 days. Your account is '
                    'frozen immediately — the dashboard is locked meanwhile.',
                    style: GoogleFonts.inter(fontSize: 13, height: 1.4)),
                const SizedBox(height: 10),
                _adminDelWarn('Your library, seats, shifts & settings will be removed'),
                _adminDelWarn('Your members lose access to this library'),
                _adminDelWarn('Analytics, payments & audit history will be erased'),
                const SizedBox(height: 8),
                Text('Within 7 days you can request recovery; the SILENCE team reviews '
                    'and decides. There is no self-cancel. After 7 days it is permanent.',
                    style: GoogleFonts.inter(fontSize: 11.5, color: context.palette.textMuted)),
                const SizedBox(height: 14),
                Text('Type DELETE to confirm:',
                    style: GoogleFonts.inter(
                        fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: confirmCtrl,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setDialog(() {}),
                  decoration: const InputDecoration(hintText: 'DELETE'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.grey[600])),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  disabledBackgroundColor: const Color(0xFFFCA5A5),
                ),
                onPressed: canDelete ? () => Navigator.pop(ctx, true) : null,
                child: Text('Request deletion',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final deletionTime = DateTime.now().add(const Duration(days: 7));
    try {
      await supabase.from('users').update({
        'scheduled_for_deletion': true,
        'deletion_scheduled_at': deletionTime.toIso8601String(),
        'deletion_recovery_status': 'none',
      }).eq('id', user.id);
      if (!mounted) return;
      // Freeze immediately — block the dashboard, only recovery/logout remain.
      Navigator.of(context).pushNamedAndRemoveUntil('/account-frozen', (r) => false);
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit the request: $e')),
      );
    }
  }

  Widget _adminDelWarn(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.remove_circle_outline, size: 15, color: Color(0xFFDC2626)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: GoogleFonts.inter(fontSize: 12, color: context.palette.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifiedBadgeCard() {
    final bool isVerified = _currentLibraryVerified ?? false;

    if (isVerified) {
      final formattedDate = _currentLibraryVerifiedAt != null
          ? DateFormat('dd/MM/yyyy').format(_currentLibraryVerifiedAt!)
          : 'Recently';
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFA7F3D0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified, color: Colors.blue, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Verified Library',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: context.palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Verified on $formattedDate',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: context.palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.01),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified, color: Colors.blue, size: 24),
                const SizedBox(width: 12),
                Text(
                  'Unlock the Verified Badge',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: context.palette.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Meet the criteria to get the blue verified tick on your library profile.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: context.palette.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                if (!await ensurePlan(context, AdminFeature.verifiedBadge,
                    featureLabel: 'The verified badge')) {
                  return;
                }
                if (!mounted) return;
                Navigator.pushNamed(context, '/admin/verified-badge').then((_) => _loadProfileData());
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE65C00)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              ),
              child: Text(
                'Check Eligibility & Apply',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFE65C00),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  // ── Library profile completeness (drives the progress bar) ─────────────────
  // The currently-managed library (or the first one) used for the progress card.
  Map<String, dynamic>? get _activeLibrary {
    if (_myLibrariesList.isEmpty) return null;
    final id = _selectedLibraryIdToManage ?? widget.libraryId;
    return _myLibrariesList.firstWhere(
      (l) => l['id'] == id,
      orElse: () => _myLibrariesList.first,
    );
  }

  // Honest checklist straight off the library row — what still needs filling
  // to make the public library profile rich (and qualify for the badge).
  List<String> _missingProfileDetails(Map<String, dynamic> lib) {
    final missing = <String>[];
    final cover = (lib['cover_photo_url'] ?? '').toString().trim();
    final photos = (lib['photos'] as List?) ?? const [];
    if (cover.isEmpty && photos.isEmpty) missing.add('Cover photo');
    if ((lib['about_text'] ?? '').toString().trim().isEmpty) missing.add('About');
    final amenities = (lib['amenities'] as List?) ?? const [];
    if (amenities.isEmpty) missing.add('Amenities');
    if ((lib['rules'] ?? '').toString().trim().isEmpty) missing.add('Rules');
    if ((lib['address_street'] ?? '').toString().trim().isEmpty) missing.add('Address');
    if ((lib['emergency_phone'] ?? '').toString().trim().isEmpty) missing.add('Emergency contact');
    final social = lib['social_links'];
    final hasSocial = social is Map && social.isNotEmpty;
    if (!hasSocial) missing.add('Social links');
    return missing;
  }

  Widget _buildProfileCompletenessCard() {
    final lib = _activeLibrary;
    if (lib == null) return const SizedBox.shrink();

    final missing = _missingProfileDetails(lib);
    const total = 7;
    final filled = total - missing.length;
    final pct = (filled / total).clamp(0.0, 1.0);
    final bool isComplete = missing.isEmpty;
    const Color accent = Color(0xFF16A34A); // green progress bar

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isComplete ? Icons.verified_rounded : Icons.auto_graph_rounded, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Library Profile',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                ),
              ),
              Text(
                '${(pct * 100).round()}%',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: accent),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: const Color(0xFFF1F5F9),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 12),
          if (isComplete)
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF16A34A)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Profile fully optimised — boosts visibility & helps you qualify for the verified badge.',
                    style: GoogleFonts.inter(fontSize: 12, color: context.palette.textSecondary, height: 1.4),
                  ),
                ),
              ],
            )
          else ...[
            Text(
              'Add these to optimise your profile & qualify for the verified badge:',
              style: GoogleFonts.inter(fontSize: 12, color: context.palette.textMuted, height: 1.4),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: missing.map((m) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFEDD5)),
                  ),
                  child: Text(
                    m,
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF9A3412)),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsGroup({required String title, required List<Widget> items}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
          child: Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: context.palette.textMuted,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: items,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsItem(BuildContext context, IconData icon, String title, String routeName,
      {AdminFeature? feature, String? featureLabel}) {
    final bool locked = feature != null && !PlanService.instance.canUse(feature);
    return ListTile(
      leading: Icon(icon, size: 20, color: const Color(0xFFE65C00)),
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: context.palette.textPrimary,
        ),
      ),
      trailing: locked
          ? const Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFF94A3B8))
          : const Icon(Icons.chevron_right, size: 16, color: Color(0xFF94A3B8)),
      onTap: () async {
        if (feature != null &&
            !await ensurePlan(context, feature, featureLabel: featureLabel ?? title)) {
          return;
        }
        if (!context.mounted) return;
        Navigator.pushNamed(
          context,
          routeName,
          arguments: _selectedLibraryIdToManage ?? widget.libraryId,
        ).then((_) {
          _loadProfileData();
        });
      },
    );
  }

  Widget _buildSingleLibraryCard(Map<String, dynamic> lib, {required bool isHorizontalList}) {
    final String libId = lib['id'];
    final String name = lib['name'] ?? 'Study Center';
    final String city = lib['address_city'] ?? 'City';
    final String street = lib['address_street'] ?? '';
    final String? coverUrl = lib['cover_photo_url'];
    final int members = lib['member_count'] ?? 0;
    final int occupancy = lib['occupancy_pct'] ?? 0;
    final String openingHours = (lib['opening_hours'] ?? '').toString().trim();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LibraryPublicProfileScreen(
              libraryId: libId,
              isAdmin: true,
            ),
          ),
        ).then((_) => _loadProfileData());
      },
      child: Container(
        width: 280,
        height: 200,
        margin: isHorizontalList ? const EdgeInsets.only(right: 16) : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: coverUrl != null && coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: Colors.grey[200]),
                        errorWidget: (context, url, error) => Container(
                          color: const Color(0xFFFFF3ED),
                          child: const Icon(Icons.storefront, color: Color(0xFFE65C00), size: 36),
                        ),
                      )
                    : Container(
                        color: const Color(0xFFFFF3ED),
                        child: const Icon(Icons.storefront, color: Color(0xFFE65C00), size: 36),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: context.palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            street.isNotEmpty ? '$street, $city' : city,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              color: context.palette.textMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.people_outline, size: 12, color: Color(0xFFE65C00)),
                              const SizedBox(width: 4),
                              Text(
                                '$members Members',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: context.palette.textMuted,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Icon(Icons.pie_chart_outline, size: 12, color: Color(0xFFE65C00)),
                              const SizedBox(width: 4),
                              Text(
                                '$occupancy% Occupied',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: context.palette.textMuted,
                                ),
                              ),
                            ],
                          ),
                          if (openingHours.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.access_time, size: 12, color: Color(0xFFE65C00)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    openingHours,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: context.palette.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, size: 20, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShareAppItem() {
    return ListTile(
      leading: const Icon(Icons.share, size: 20, color: Color(0xFFE65C00)),
      title: Text(
        'Share App',
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: const Color(0xFFE65C00),
        ),
      ),
      trailing: const Icon(Icons.ios_share, size: 16, color: Color(0xFFE65C00)),
      onTap: () {
        Share.share('Check out the Silence App at https://silenceapp.in/download');
      },
    );
  }

  Map<String, dynamic>? get _selectedLibrary {
    if (_selectedLibraryIdToManage == null) return null;
    try {
      return _myLibrariesList.firstWhere(
        (lib) => lib['id'] == _selectedLibraryIdToManage,
        orElse: () => _myLibrariesList.first,
      );
    } catch (_) {
      return null;
    }
  }

  Widget _buildLibraryManagementGridCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Library Management',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: context.palette.textPrimary,
              ),
            ),
            if (_myLibrariesList.isEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3ED),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.home_work_outlined,
                      size: 48,
                      color: Color(0xFFE65C00),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No Library Created Yet',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: context.palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Complete library setup steps on the Home tab to start managing your library.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: context.palette.textMuted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Please complete library setup steps in the Home tab.', style: GoogleFonts.inter()),
                            backgroundColor: const Color(0xFFE65C00),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65C00),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Go to Setup Wizard',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_myLibrariesList.length > 1) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _myLibrariesList.any((lib) => lib['id'] == _selectedLibraryIdToManage) ? _selectedLibraryIdToManage : (_myLibrariesList.isNotEmpty ? _myLibrariesList.first['id'] : null),
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(14),
                menuMaxHeight: 320,
                style: GoogleFonts.inter(color: context.palette.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE65C00)),
                  ),
                ),
                items: _myLibrariesList.map((lib) {
                  return DropdownMenuItem<String>(
                    value: lib['id'],
                    child: Text(lib['name'] ?? 'Study Center'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedLibraryIdToManage = val;
                    });
                    // Make this the GLOBAL active library so every settings
                    // screen, the dashboard, analytics and reservations all
                    // act on the same library (single source of truth). Was
                    // previously local-only, which let settings open a
                    // different library than the one selected here.
                    widget.onLibraryChanged(val);
                  }
                },
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  final targetId = _selectedLibraryIdToManage ?? widget.libraryId;
                  if (targetId == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CopyLibrarySettingsScreen(
                        targetLibraryId: targetId,
                        targetLibraryName:
                            (_selectedLibrary?['name'] ?? 'this library').toString(),
                      ),
                    ),
                  ).then((copied) {
                    if (copied == true) {
                      _loadProfileData();
                      widget.onLibraryUpdated?.call();
                    }
                  });
                },
                icon: const Icon(Icons.copy_all_rounded,
                    size: 18, color: Color(0xFFE65C00)),
                label: Text('Copy settings from another library',
                    style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFE65C00))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFFD8BF)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ],
            if (_myLibrariesList.isNotEmpty) ...[
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                childAspectRatio: 0.9,
                children: [
                  _buildGridItem(Icons.person_outline_rounded, 'Edit Profile', () {
                    Navigator.pushNamed(context, '/admin/profile/complete').then((_) => _loadProfileData());
                  }),
                  _buildGridItem(Icons.info_outline, 'Basic Details', _showBasicDetailsBottomSheet),
                  _buildGridItem(Icons.menu_book_outlined, 'About & Info', _showLibraryDetailsBottomSheet),
                  _buildGridItem(Icons.widgets_outlined, 'Amenities & Add-ons', _showAmenitiesBottomSheet),
                  _buildGridItem(Icons.access_time, 'Shift & Plan', _navigateToShiftManagement),
                  _buildGridItem(Icons.payments_outlined, 'Payment Methods', _openPaymentMethods),
                  _buildGridItem(Icons.link, 'Social Links', _showSocialLinksBottomSheet),
                  _buildGridItem(Icons.collections, 'Gallery', _showGalleryBottomSheet),
                  _buildGridItem(Icons.rule_folder, 'Rules', _showRulesBottomSheet),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGridItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3ED),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 24, color: const Color(0xFFE65C00)),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: context.palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToShiftManagement() async {
    if (_selectedLibraryIdToManage == null) return;
    if (!await ensurePlan(context, AdminFeature.shiftEdit, featureLabel: 'Editing shifts & plans')) {
      return;
    }
    if (!mounted) return;
    Navigator.pushNamed(
      context,
      '/admin/settings/shifts',
      arguments: _selectedLibraryIdToManage,
    ).then((_) {
      _loadProfileData();
      widget.onLibraryUpdated?.call();
    });
  }

  // ── Library "About & Info" — About, Opening Hours and Members-Joined label.
  // All three are admin-editable and saved on the library row, so they stay in
  // sync wherever they're shown (public profile + this tab + completeness bar).
  Future<void> _showLibraryDetailsBottomSheet() async {
    final lib = _selectedLibrary;
    if (lib == null) return;
    final libId = lib['id'];

    // Opening hours are owned by Shift & Plan — shown read-only here.
    List<Map<String, dynamic>> shifts = [];
    try {
      final res = await _supabase
          .from('shifts')
          .select('name, start_time, end_time, shift_type')
          .eq('library_id', libId)
          .eq('is_archived', false);
      shifts = List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Error fetching shifts for details sheet: $e');
    }
    if (!mounted) return;

    final aboutCtrl = TextEditingController(text: lib['about_text'] ?? '');
    final hoursCtrl = TextEditingController(text: lib['opening_hours'] ?? '');
    final membersCtrl = TextEditingController(text: lib['display_members_joined'] ?? '');
    bool saving = false;

    String fmt(String? t) {
      if (t == null || t.isEmpty) return '';
      try {
        final p = t.split(':');
        final dt = DateTime(2026, 1, 1, int.parse(p[0]), p.length > 1 ? int.parse(p[1]) : 0);
        return DateFormat.jm().format(dt);
      } catch (_) {
        return t;
      }
    }

    final String shiftRef = shifts.isEmpty
        ? ''
        : shifts.map((s) {
            final type = (s['shift_type'] ?? 'fixed').toString();
            return type == 'hourly'
                ? '${s['name'] ?? 'Shift'}: hourly'
                : '${s['name'] ?? 'Shift'}: ${fmt(s['start_time']?.toString())}–${fmt(s['end_time']?.toString())}';
          }).join('   •   ');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
                top: 24,
                left: 24,
                right: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'About & Info',
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Shown on your public library profile.',
                      style: GoogleFonts.inter(fontSize: 12, color: context.palette.textMuted),
                    ),
                    const SizedBox(height: 16),

                    // About (editable)
                    Text(
                      'About Library',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: context.palette.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: aboutCtrl,
                      maxLines: 4,
                      maxLength: 600,
                      style: GoogleFonts.inter(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Describe your library — the vibe, facilities, who it suits best...',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE65C00)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Opening Hours (editable — shown on the public profile)
                    Text(
                      'Opening Hours',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: context.palette.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: hoursCtrl,
                      style: GoogleFonts.inter(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'e.g. 6:00 AM – 11:00 PM',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
                        prefixIcon: const Icon(Icons.access_time_rounded, size: 18, color: Color(0xFFE65C00)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE65C00)),
                        ),
                      ),
                    ),
                    if (shiftRef.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Your shifts: $shiftRef',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Members Joined (editable label — social proof on profile)
                    Text(
                      'Members Joined',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: context.palette.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: membersCtrl,
                      style: GoogleFonts.inter(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'e.g. 500+',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
                        prefixIcon: const Icon(Icons.groups_rounded, size: 18, color: Color(0xFFE65C00)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE65C00)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Shown as social proof, e.g. "500+ members already joined".',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final navigator = Navigator.of(sheetContext);
                                final aboutText = aboutCtrl.text.trim();
                                setSheet(() => saving = true);
                                try {
                                  await _supabase.from('libraries').update({
                                    'about_text': aboutText,
                                    'opening_hours': hoursCtrl.text.trim(),
                                    'display_members_joined': membersCtrl.text.trim(),
                                  }).eq('id', libId);
                                  if (!mounted) return;
                                  navigator.pop();
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Library details saved ✓'),
                                      backgroundColor: Color(0xFFE65C00),
                                    ),
                                  );
                                  _loadProfileData(); // refreshes the completeness bar
                                  widget.onLibraryUpdated?.call();
                                } catch (e) {
                                  setSheet(() => saving = false);
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('Error: ${friendlyError(e)}')),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: saving
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text('Save', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showBasicDetailsBottomSheet() {
    final lib = _selectedLibrary;
    if (lib == null) return;

    final nameCtrl = TextEditingController(text: lib['name'] ?? '');
    final streetCtrl = TextEditingController(text: lib['address_street'] ?? '');
    final cityCtrl = TextEditingController(text: lib['address_city'] ?? '');
    final stateCtrl = TextEditingController(text: lib['address_state'] ?? '');
    final pinCtrl = TextEditingController(text: lib['address_pincode'] ?? '');
    final locationLinkCtrl = TextEditingController(text: lib['location_link'] ?? '');
    final emergencyCtrl = TextEditingController(text: lib['emergency_phone'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
            top: 24,
            left: 24,
            right: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Basic Details',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Library Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: streetCtrl,
                  decoration: const InputDecoration(labelText: 'Street Address'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: cityCtrl,
                        decoration: const InputDecoration(labelText: 'City'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: stateCtrl,
                        decoration: const InputDecoration(labelText: 'State'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: pinCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Pincode'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: emergencyCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Emergency Phone'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locationLinkCtrl,
                  decoration: const InputDecoration(labelText: 'Google Maps Link', hintText: 'https://maps.google.com/...'),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    showDialog(
                      context: sheetContext,
                      barrierDismissible: false,
                      builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00))),
                    );

                    try {
                      await _supabase.from('libraries').update({
                        'name': nameCtrl.text.trim(),
                        'address_street': streetCtrl.text.trim(),
                        'address_city': cityCtrl.text.trim(),
                        'address_state': stateCtrl.text.trim(),
                        'address_pincode': pinCtrl.text.trim(),
                        'location_link': locationLinkCtrl.text.trim(),
                        'emergency_phone': emergencyCtrl.text.trim(),
                      }).eq('id', lib['id']);

                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                        Navigator.pop(sheetContext);
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text('Library details saved successfully! ✓'),
                            backgroundColor: Color(0xFF10B981),
                          ),
                        );
                      }
                      _loadProfileData();
                      widget.onLibraryUpdated?.call();
                    } catch (e) {
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          SnackBar(
                            content: Text('Failed to save details: $e'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Save Details'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAmenitiesBottomSheet() async {
    final lib = _selectedLibrary;
    if (lib == null) return;
    if (!await ensurePlan(context, AdminFeature.addonsManage,
        featureLabel: 'Managing amenities & add-ons')) {
      return;
    }
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.85,
        child: AddonsAmenitiesSheet(
          libraryId: lib['id'],
          onSaved: () {
            _loadProfileData();
            widget.onLibraryUpdated?.call();
          },
        ),
      ),
    );
  }

  Future<void> _openPaymentMethods() async {
    final lib = _selectedLibrary;
    if (lib == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentMethodsScreen(libraryId: lib['id'] as String),
      ),
    );
    if (changed == true) {
      _loadProfileData();
      widget.onLibraryUpdated?.call();
    }
  }

  void _showSocialLinksBottomSheet() {
    final lib = _selectedLibrary;
    if (lib == null) return;

    final Map<String, dynamic> existing = Map<String, dynamic>.from(lib['social_links'] ?? {});
    final instaCtrl = TextEditingController(text: existing['instagram'] ?? '');
    final ytCtrl = TextEditingController(text: existing['youtube'] ?? '');
    final fbCtrl = TextEditingController(text: existing['facebook'] ?? '');
    final waCtrl = TextEditingController(text: existing['whatsapp'] ?? '');
    final webCtrl = TextEditingController(text: existing['website'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            top: 24,
            left: 24,
            right: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Social Links',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: instaCtrl,
                  decoration: const InputDecoration(labelText: 'Instagram Link/Username', prefixIcon: Icon(Icons.camera_alt_outlined)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ytCtrl,
                  decoration: const InputDecoration(labelText: 'YouTube Channel Link', prefixIcon: Icon(Icons.video_library_outlined)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: fbCtrl,
                  decoration: const InputDecoration(labelText: 'Facebook Page Link', prefixIcon: Icon(Icons.facebook_outlined)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: waCtrl,
                  decoration: const InputDecoration(labelText: 'WhatsApp Group/Number Link', prefixIcon: Icon(Icons.chat_bubble_outline)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: webCtrl,
                  decoration: const InputDecoration(labelText: 'Website Link', prefixIcon: Icon(Icons.language_outlined)),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    showDialog(
                      context: ctx,
                      barrierDismissible: false,
                      builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00))),
                    );

                    // Merge into the existing map so other keys in the same
                    // JSONB (cash_enabled, upi_ids) are preserved, not wiped.
                    final updatedSocial = Map<String, dynamic>.from(existing)
                      ..['instagram'] = instaCtrl.text.trim()
                      ..['youtube'] = ytCtrl.text.trim()
                      ..['facebook'] = fbCtrl.text.trim()
                      ..['whatsapp'] = waCtrl.text.trim()
                      ..['website'] = webCtrl.text.trim();

                    try {
                      await _supabase.from('libraries').update({
                        'social_links': updatedSocial,
                      }).eq('id', lib['id']);

                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        Navigator.pop(ctx);
                      }
                      _loadProfileData();
                      widget.onLibraryUpdated?.call();
                    } catch (e) {
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('Error updating: $e')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Save Social Links'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRulesBottomSheet() {
    final lib = _selectedLibrary;
    if (lib == null) return;

    final rawRules = lib['rules'] as String? ?? '';
    final List<String> initialRules = rawRules.trim().isEmpty ? [] : rawRules.split('\n');
    final List<TextEditingController> controllers = initialRules.map((r) => TextEditingController(text: r)).toList();

    if (controllers.isEmpty) {
      controllers.add(TextEditingController());
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                top: 24,
                left: 24,
                right: 24,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Rules & Guidelines',
                          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setSheetState(() {
                              controllers.add(TextEditingController());
                            });
                          },
                          icon: const Icon(Icons.add, size: 16, color: Color(0xFFE65C00)),
                          label: Text(
                            'Add Rule',
                            style: GoogleFonts.inter(color: const Color(0xFFE65C00), fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Where these rules appear (member-facing, not public profile).
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 15, color: Color(0xFF2563EB)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'These rules are shown to your members inside the member app — not on your public library profile.',
                              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF1E40AF), height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        itemCount: controllers.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: controllers[index],
                                    decoration: InputDecoration(
                                      hintText: 'e.g. Keep silence in the reading room',
                                      hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
                                    ),
                                    style: GoogleFonts.inter(fontSize: 13),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () {
                                    setSheetState(() {
                                      controllers[index].dispose();
                                      controllers.removeAt(index);
                                    });
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        showDialog(
                          context: ctx,
                          barrierDismissible: false,
                          builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00))),
                        );

                        final finalRulesStr = controllers
                            .map((c) => c.text.trim())
                            .where((text) => text.isNotEmpty)
                            .join('\n');

                        try {
                          await _supabase.from('libraries').update({
                            'rules': finalRulesStr,
                          }).eq('id', lib['id']);

                          for (var c in controllers) {
                            c.dispose();
                          }

                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            Navigator.pop(ctx);
                          }
                          _loadProfileData();
                          widget.onLibraryUpdated?.call();
                        } catch (e) {
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Error saving rules: $e')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65C00),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Save Rules'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      for (var c in controllers) {
        c.dispose();
      }
    });
  }

  void _showGalleryBottomSheet() {
    final lib = _selectedLibrary;
    if (lib == null) return;

    final List<dynamic> current = lib['photos'] as List? ?? [];
    List<String> photos = List<String>.from(current.map((e) => e.toString()));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            
            Future<void> updatePhotosInDB() async {
              try {
                await _supabase.from('libraries').update({'photos': photos}).eq('id', lib['id']);
                _loadProfileData();
                widget.onLibraryUpdated?.call();
              } catch (e) {
                debugPrint('Error: $e');
                // Honest failure: tell the admin it did NOT save, and re-pull the
                // true DB state so the optimistic add/remove doesn't linger.
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Could not save photos. Please try again. (${friendlyError(e)})'),
                      backgroundColor: Colors.red[600],
                    ),
                  );
                }
                _loadProfileData();
              }
            }

            Future<void> addPhotoFromPicker() async {
              try {
                final source = await _showImageSourceBottomSheet();
                if (source == null) return;
                
                final picker = ImagePicker();
                final image = await picker.pickImage(source: source, maxWidth: 800, imageQuality: 85);
                if (image == null) return;

                if (!ctx.mounted) return;
                showDialog(
                  context: ctx,
                  barrierDismissible: false,
                  builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00))),
                );

                final bytes = await ImageOptimizer.compressImage(image.path);
                final path = 'libraries/${lib['id']}/gallery_${DateTime.now().millisecondsSinceEpoch}.jpg';

                await _supabase.storage.from('silence_assets').uploadBinary(
                  path,
                  Uint8List.fromList(bytes),
                  fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
                );

                final publicUrl = _supabase.storage.from('silence_assets').getPublicUrl(path);

                if (ctx.mounted) Navigator.pop(ctx);

                setSheetState(() {
                  photos.add(publicUrl);
                });
                await updatePhotosInDB();
              } catch (e) {
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error uploading: $e')));
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                top: 24, left: 24, right: 24
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Gallery & Photos',
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                      ),
                      TextButton.icon(
                        onPressed: addPhotoFromPicker,
                        icon: const Icon(Icons.add_a_photo, size: 16, color: Color(0xFFE65C00)),
                        label: Text('Add Photo', style: GoogleFonts.inter(color: const Color(0xFFE65C00), fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  photos.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40.0),
                          child: Center(
                            child: Text(
                              'No photos uploaded yet.',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
                            ),
                          ),
                        )
                      : SizedBox(
                          height: 120,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: photos.length,
                            itemBuilder: (context, index) {
                              final photoUrl = photos[index];
                              return Stack(
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(right: 12),
                                    width: 150,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: CachedNetworkImage(
                                        imageUrl: photoUrl,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => Container(color: Colors.grey[100]),
                                        errorWidget: (context, url, error) => const Icon(Icons.broken_image),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 16,
                                    child: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: Colors.black54,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.delete, color: Colors.white, size: 16),
                                        onPressed: () async {
                                          setSheetState(() {
                                            photos.remove(photoUrl);
                                          });
                                          await updatePhotosInDB();
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class AddonsAmenitiesSheet extends StatefulWidget {
  final String libraryId;
  final VoidCallback onSaved;

  const AddonsAmenitiesSheet({
    super.key,
    required this.libraryId,
    required this.onSaved,
  });

  @override
  State<AddonsAmenitiesSheet> createState() => _AddonsAmenitiesSheetState();
}

class _AddonsAmenitiesSheetState extends State<AddonsAmenitiesSheet> {
  final _supabase = Supabase.instance.client;
  late Future<Map<String, dynamic>> _dataFuture;
  List<String>? _localAmenities;
  bool _isSavingAmenities = false;

  @override
  void initState() {
    super.initState();
    _dataFuture = _fetchData(); // no setState in initState
  }

  void _refreshData() {
    setState(() {
      _dataFuture = _fetchData();
    });
  }

  Widget _priceTypeChip(String label, String value, String selected, VoidCallback onTap) {
    final bool active = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? const Color(0xFFE65C00) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : context.palette.textSecondary)),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _fetchData() async {
    final addonsRes = await _supabase
        .from('add_ons')
        .select()
        .eq('library_id', widget.libraryId);
    
    final libRes = await _supabase
        .from('libraries')
        .select('amenities')
        .eq('id', widget.libraryId)
        .single();

    final List<dynamic> rawAmenities = libRes['amenities'] as List? ?? [];
    final List<String> dbAmenities = List<String>.from(rawAmenities.map((e) => e.toString()));

    return {
      'add_ons': addonsRes as List<dynamic>,
      'amenities': dbAmenities,
    };
  }

  Future<void> _showAddAmenityDialog() async {
    final textCtrl = TextEditingController();
    final newAmenity = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.palette.surface,
        title: Text(
          'Add New Amenity',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: context.palette.textPrimary),
        ),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Amenity Name',
            hintText: 'e.g. Cafeteria, Study Cabins',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: context.palette.textMuted, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, textCtrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00)),
            child: Text('Add', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (newAmenity != null && newAmenity.isNotEmpty) {
      setState(() {
        _localAmenities ??= [];
        _localAmenities!.add(newAmenity);
      });
    }
  }

  Future<void> _saveAmenities() async {
    if (_localAmenities == null) return;
    setState(() => _isSavingAmenities = true);
    try {
      await _supabase.from('libraries').update({
        'amenities': _localAmenities,
      }).eq('id', widget.libraryId);

      widget.onSaved();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Amenities updated successfully! ✓'), backgroundColor: Color(0xFF10B981)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save amenities: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingAmenities = false);
      }
    }
  }

  Future<void> _showAddEditAddonSheet([Map<String, dynamic>? addon]) async {
    final isEdit = addon != null;
    final nameCtrl = TextEditingController(text: isEdit ? addon['name'] ?? '' : '');
    final priceCtrl = TextEditingController(text: isEdit ? addon['price']?.toString() ?? '' : '');
    final depositCtrl = TextEditingController(text: isEdit ? addon['refundable_deposit']?.toString() ?? '' : '');
    final maxAvailableCtrl = TextEditingController(text: isEdit ? addon['max_available']?.toString() ?? '' : '');
    String priceType = isEdit ? addon['price_type'] ?? 'monthly' : 'monthly';
    bool isActive = isEdit ? addon['active'] == true : true;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (statefulContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
                top: 24,
                left: 24,
                right: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      isEdit ? 'Edit Add-on' : 'Add Add-on',
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Add-on Name', hintText: 'e.g. VIP Locker, Parking'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: priceCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Price (₹)'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Price Type',
                                  style: GoogleFonts.inter(
                                      fontSize: 11, color: context.palette.textMuted)),
                              const SizedBox(height: 4),
                              // Inline segmented toggle instead of a DropdownButton:
                              // a dropdown overlay inside a nested bottom sheet was
                              // the trigger for the _dependents.isEmpty red-screen.
                              Row(
                                children: [
                                  _priceTypeChip('Monthly', 'monthly', priceType,
                                      () => setSheetState(() => priceType = 'monthly')),
                                  const SizedBox(width: 6),
                                  _priceTypeChip('One-time', 'one_time', priceType,
                                      () => setSheetState(() => priceType = 'one_time')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: depositCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Refundable Deposit (₹)', hintText: '0 if none'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: maxAvailableCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Max Available', hintText: 'e.g. 50'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: Text('Active / Available', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                      value: isActive,
                      activeThumbColor: const Color(0xFFE65C00),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setSheetState(() {
                          isActive = val;
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: saving ? null : () async {
                        final name = nameCtrl.text.trim();
                        final price = int.tryParse(priceCtrl.text) ?? 0;
                        final deposit = int.tryParse(depositCtrl.text) ?? 0;
                        final maxAvailable = int.tryParse(maxAvailableCtrl.text) ?? 999;

                        if (name.isEmpty) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(content: Text('Please enter add-on name')),
                          );
                          return;
                        }

                        setSheetState(() => saving = true);
                        try {
                          final Map<String, dynamic> payload = {
                            'library_id': widget.libraryId,
                            'name': name,
                            'price': price,
                            'price_type': priceType,
                            'refundable_deposit': deposit,
                            'max_available': maxAvailable,
                            'active': isActive,
                          };

                          if (isEdit) {
                            await _supabase.from('add_ons').update(payload).eq('id', addon['id']);
                          } else {
                            payload['id'] = const Uuid().v4();
                            await _supabase.from('add_ons').insert(payload);
                          }

                          // Dismiss the keyboard/focus BEFORE popping so the
                          // focus + MediaQuery dependencies are torn down
                          // cleanly (the real _dependents.isEmpty trigger for a
                          // focused TextField inside a popping bottom sheet).
                          FocusManager.instance.primaryFocus?.unfocus();
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          _refreshData();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(isEdit ? 'Add-on updated successfully! ✓' : 'Add-on created successfully! ✓'),
                                backgroundColor: const Color(0xFF10B981),
                              ),
                            );
                          }
                        } catch (e) {
                          setSheetState(() => saving = false);
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              SnackBar(content: Text('Failed to save add-on: $e'), backgroundColor: Colors.redAccent),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65C00),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(isEdit ? 'Save Changes' : 'Add Add-on'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      nameCtrl.dispose();
      priceCtrl.dispose();
      depositCtrl.dispose();
      maxAvailableCtrl.dispose();
    });
  }

  Future<void> _confirmDeleteAddon(Map<String, dynamic> addon) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.palette.surface,
        title: Text('Delete Add-on', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
        content: Text('Are you sure you want to delete "${addon['name']}"? This action cannot be undone.', style: GoogleFonts.inter(fontSize: 14, color: context.palette.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: context.palette.textMuted, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text('Delete', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00))),
      );

      try {
        await _supabase.from('add_ons').delete().eq('id', addon['id']);
        if (mounted) {
          Navigator.pop(context); // Close loader
          _refreshData();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Add-on deleted successfully ✓'), backgroundColor: Color(0xFF10B981)),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Close loader
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete add-on: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Title block
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Amenities & Add-ons',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _dataFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)));
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      'Failed to load: ${snapshot.error}',
                      style: GoogleFonts.inter(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              final data = snapshot.data!;
              final List<dynamic> addOns = data['add_ons'];
              final List<String> dbAmenities = data['amenities'];

              _localAmenities ??= List<String>.from(dbAmenities);

              return ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // Amenities Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Amenities',
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showAddAmenityDialog,
                        icon: const Icon(Icons.add, size: 14, color: Color(0xFFE65C00)),
                        label: Text(
                          'Add Amenity',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE65C00)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Amenities list
                  _localAmenities!.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            'No amenities configured yet.',
                            style: GoogleFonts.inter(fontSize: 12, color: context.palette.textMuted),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _localAmenities!.map((amenity) {
                            return Chip(
                              label: Text(
                                amenity,
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: context.palette.textPrimary),
                              ),
                              backgroundColor: const Color(0xFFE2E8F0),
                              deleteIcon: const Icon(Icons.close, size: 14, color: Color(0xFF475569)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide.none,
                              ),
                              onDeleted: () {
                                setState(() {
                                  _localAmenities!.remove(amenity);
                                });
                              },
                            );
                          }).toList(),
                        ),
                  if (_localAmenities!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed: _isSavingAmenities ? null : _saveAmenities,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        child: _isSavingAmenities
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text('Save Amenities', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Divider(color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 16),
                  // Add-ons Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Add-ons',
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _showAddEditAddonSheet(),
                        icon: const Icon(Icons.add, size: 14, color: Colors.white),
                        label: Text(
                          'Add Add-on',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Add-ons list
                  addOns.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.add_shopping_cart, color: Colors.grey[400], size: 36),
                              const SizedBox(height: 8),
                              Text(
                                'No Add-on Services Configured',
                                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textSecondary),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Add optional services like personal lockers, vehicle parking, or premium VIP cabins.',
                                style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: addOns.map((addon) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.palette.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          addon['name'] ?? 'Add-on',
                                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: context.palette.textPrimary, fontSize: 14),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              'Price: ₹${addon['price']}/${addon['price_type'] == 'one_time' ? 'one-time' : 'monthly'}',
                                              style: GoogleFonts.inter(fontSize: 12, color: context.palette.textMuted),
                                            ),
                                            if ((addon['refundable_deposit'] as num? ?? 0) > 0) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                width: 4,
                                                height: 4,
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFF94A3B8),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Deposit: ₹${addon['refundable_deposit']}',
                                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF10B981), fontWeight: FontWeight.w500),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Max Available: ${addon['max_available'] ?? "Unlimited"} • Active: ${addon['active'] == true ? "Yes" : "No"}',
                                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: Color(0xFF64748B), size: 20),
                                    onPressed: () => _showAddEditAddonSheet(addon),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                    onPressed: () => _confirmDeleteAddon(addon),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}


