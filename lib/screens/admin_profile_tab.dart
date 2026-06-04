import 'dart:io';
import 'dart:typed_data';
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
import 'library_public_profile_screen.dart';

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
  });

  @override
  State<AdminProfileTab> createState() => _AdminProfileTabState();
}

class _AdminProfileTabState extends State<AdminProfileTab> with AutomaticKeepAliveClientMixin {
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;
  bool _isUploadingPhoto = false;

  // Dynamic Profile Fields
  String _adminName = '';
  String? _adminPhotoUrl;
  String _subscriptionPlan = 'trial';
  String _subscriptionStatus = 'trial';
  DateTime? _subscriptionExpiry;
  List<Map<String, dynamic>> _myLibrariesList = [];
  bool? _currentLibraryVerified;
  DateTime? _currentLibraryVerifiedAt;
  String? _selectedLibraryIdToManage;

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
    setState(() => _isLoading = true);

    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        // 1. Fetch user data (full name, subscription plan/status, expiry)
        final userData = await _supabase.from('users').select().eq('id', user.id).maybeSingle();
        if (userData != null && mounted) {
          setState(() {
            _adminName = userData['full_name'] ?? widget.adminName;
            _adminPhotoUrl = userData['photo_url'];
            _subscriptionPlan = userData['subscription_plan'] ?? 'trial';
            _subscriptionStatus = userData['subscription_status'] ?? 'trial';
            if (userData['subscription_expiry'] != null) {
              _subscriptionExpiry = DateTime.tryParse(userData['subscription_expiry'].toString());
            }
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
      setState(() => _isLoading = false);
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
      backgroundColor: Colors.white,
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

      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 512,
        imageQuality: 80,
      );

      if (image == null) return;

      // Crop Image to strict 1:1 square
      final CroppedFile? croppedFile = await ImageCropper().cropImage(
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

      if (croppedFile == null) return;

      setState(() => _isUploadingPhoto = true);

      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final bytes = await ImageOptimizer.compressImage(croppedFile.path);
      final path = 'admin_profiles/${user.id}/profile.jpg';

      // Try uploading to silence_private, fallback to silence_assets
      String publicUrl = '';
      try {
        await _supabase.storage.from('silence_private').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
        publicUrl = _supabase.storage.from('silence_private').getPublicUrl(path);
      } catch (_) {
        // Fallback
        await _supabase.storage.from('silence_assets').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
        publicUrl = _supabase.storage.from('silence_assets').getPublicUrl(path);
      }

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

  int _getTrialDaysLeft() {
    if (_subscriptionExpiry == null) return 14; // Default/Fallback
    final diff = _subscriptionExpiry!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          'Logout Account',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
        ),
        content: Text(
          'Are you sure you want to logout from Silence?',
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onLogout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, elevation: 0),
            child: Text('Logout', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final String dateStr = DateFormat('EEE dd/MM').format(DateTime.now()).toUpperCase();
    final bool isTrial = _subscriptionPlan == 'trial' || _subscriptionPlan == 'free' || _subscriptionStatus == 'trial';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFFBF5EE),
        body: RefreshIndicator(
          onRefresh: _loadProfileData,
          color: const Color(0xFFE65C00),
          backgroundColor: Colors.white,
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
                                          const Icon(Icons.verified, color: Colors.blue, size: 20),
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
                                  color: Colors.white.withOpacity(0.85),
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                (_subscriptionPlan == null ||
                                        _subscriptionPlan.isEmpty ||
                                        _subscriptionPlan.toLowerCase() == 'trial' ||
                                        _subscriptionPlan.toLowerCase() == 'free')
                                    ? 'Free Tier'
                                    : (_subscriptionPlan.toLowerCase() == 'pro' || _subscriptionPlan.toLowerCase() == 'pro_plan' ? 'Premium' : _subscriptionPlan[0].toUpperCase() + _subscriptionPlan.substring(1)),
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.70),
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF10B981),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'All systems operational',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: Colors.white.withOpacity(0.8),
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
                      color: const Color(0xFF1E293B),
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
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.01),
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
                                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Register your library, configure seats, set timings, and start accepting memberships.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B), height: 1.4),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.pushNamed(context, '/admin/library/setup/1').then((_) => _loadProfileData());
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE65C00),
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
                  const SizedBox(height: 24),
                  _buildLibraryManagementGridCard(),
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
                          _buildSettingsItem(context, Icons.campaign_outlined, 'Announcement History', '/admin/announcements'),
                          _buildSettingsItem(context, Icons.ios_share, 'Exports & Reports', '/admin/exports'),
                          _buildSettingsItem(context, Icons.history_edu_outlined, 'Audit Log', '/admin/audit-log'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildSettingsGroup(
                        title: 'App & Support',
                        items: [
                          _buildSettingsItem(context, Icons.settings_outlined, 'Settings', '/admin/app-settings'),
                          _buildShareAppItem(),
                          _buildSettingsItem(context, Icons.info_outline, 'About Us', '/admin/about-us'),
                          _buildSettingsItem(context, Icons.support_agent, 'Help & Support', '/admin/help-support'),
                          _buildSettingsItem(context, Icons.gavel, 'Terms & Conditions', '/admin/terms'),
                        ],
                      ),
                      const SizedBox(height: 24),
                      ListTile(
                        onTap: _showLogoutConfirmation,
                        tileColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.red.withOpacity(0.2)),
                        ),
                        leading: const Icon(Icons.logout, color: Colors.redAccent),
                        title: Text(
                          'Logout',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.redAccent),
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
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Verified on $formattedDate',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF64748B),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.01),
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
                    color: const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Meet the criteria to get the blue verified tick on your library profile.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: const Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
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
              color: const Color(0xFF64748B),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
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

  Widget _buildSettingsItem(BuildContext context, IconData icon, String title, String routeName) {
    return ListTile(
      leading: Icon(icon, size: 20, color: const Color(0xFFE65C00)),
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF1E293B),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 16, color: Color(0xFF94A3B8)),
      onTap: () {
        Navigator.pushNamed(
          context,
          routeName,
          arguments: widget.libraryId,
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
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
                              color: const Color(0xFF1E293B),
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
                              color: const Color(0xFF64748B),
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
                                  color: const Color(0xFF64748B),
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
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
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
                color: const Color(0xFF1E293B),
              ),
            ),
            if (_myLibrariesList.length > 1) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _myLibrariesList.any((lib) => lib['id'] == _selectedLibraryIdToManage) ? _selectedLibraryIdToManage : (_myLibrariesList.isNotEmpty ? _myLibrariesList.first['id'] : null),
                dropdownColor: Colors.white,
                style: GoogleFonts.inter(color: const Color(0xFF1E293B), fontSize: 13, fontWeight: FontWeight.bold),
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
                  }
                },
              ),
            ],
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 16,
              crossAxisSpacing: 12,
              childAspectRatio: 0.9,
              children: [
                _buildGridItem(Icons.info_outline, 'Basic Details', _showBasicDetailsBottomSheet),
                _buildGridItem(Icons.widgets_outlined, 'Amenities', _showAmenitiesBottomSheet),
                _buildGridItem(Icons.access_time, 'Shift & Plan', _navigateToShiftManagement),
                _buildGridItem(Icons.link, 'Social Links', _showSocialLinksBottomSheet),
                _buildGridItem(Icons.rule_folder, 'Rules', _showRulesBottomSheet),
                _buildGridItem(Icons.collections, 'Gallery', _showGalleryBottomSheet),
              ],
            ),
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
              color: const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToShiftManagement() {
    if (_selectedLibraryIdToManage == null) return;
    Navigator.pushNamed(
      context,
      '/admin/settings/shifts',
      arguments: _selectedLibraryIdToManage,
    ).then((_) => _loadProfileData());
  }

  void _showBasicDetailsBottomSheet() {
    final lib = _selectedLibrary;
    if (lib == null) return;

    final nameCtrl = TextEditingController(text: lib['name'] ?? '');
    final streetCtrl = TextEditingController(text: lib['address_street'] ?? '');
    final cityCtrl = TextEditingController(text: lib['address_city'] ?? '');
    final stateCtrl = TextEditingController(text: lib['address_state'] ?? '');
    final pinCtrl = TextEditingController(text: lib['address_pin'] ?? '');
    final locationLinkCtrl = TextEditingController(text: lib['location_link'] ?? '');
    final emergencyCtrl = TextEditingController(text: lib['emergency_phone'] ?? '');
    final latitudeCtrl = TextEditingController(text: lib['latitude']?.toString() ?? '');
    final longitudeCtrl = TextEditingController(text: lib['longitude']?.toString() ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
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
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
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
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: latitudeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Latitude', hintText: 'e.g. 22.7196'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: longitudeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Longitude', hintText: 'e.g. 75.8577'),
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
                        'address_pin': pinCtrl.text.trim(),
                        'location_link': locationLinkCtrl.text.trim(),
                        'emergency_phone': emergencyCtrl.text.trim(),
                        'latitude': double.tryParse(latitudeCtrl.text.trim()),
                        'longitude': double.tryParse(longitudeCtrl.text.trim()),
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

  void _showAmenitiesBottomSheet() {
    final lib = _selectedLibrary;
    if (lib == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.85,
        child: AddonsAmenitiesSheet(
          libraryId: lib['id'],
          onSaved: () {
            _loadProfileData();
          },
        ),
      ),
    );
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
      backgroundColor: Colors.white,
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
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
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

                    final updatedSocial = {
                      'instagram': instaCtrl.text.trim(),
                      'youtube': ytCtrl.text.trim(),
                      'facebook': fbCtrl.text.trim(),
                      'whatsapp': waCtrl.text.trim(),
                      'website': webCtrl.text.trim(),
                    };

                    try {
                      await _supabase.from('libraries').update({
                        'social_links': updatedSocial,
                      }).eq('id', lib['id']);

                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        Navigator.pop(ctx);
                      }
                      _loadProfileData();
                    } catch (e) {
                      if (ctx.mounted) Navigator.pop(ctx);
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
      backgroundColor: Colors.white,
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
                          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
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
                        } catch (e) {
                          if (ctx.mounted) Navigator.pop(ctx);
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
      backgroundColor: Colors.white,
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
              } catch (e) {
                debugPrint('Error: $e');
              }
            }

            Future<void> addPhotoFromPicker() async {
              try {
                final source = await _showImageSourceBottomSheet();
                if (source == null) return;
                
                final picker = ImagePicker();
                final image = await picker.pickImage(source: source, maxWidth: 800, imageQuality: 85);
                if (image == null) return;

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
                if (ctx.mounted) Navigator.pop(ctx);
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
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
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
    _refreshData();
  }

  void _refreshData() {
    setState(() {
      _dataFuture = _fetchData();
    });
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
        backgroundColor: Colors.white,
        title: Text(
          'Add New Amenity',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
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
            child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, textCtrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00)),
            child: Text('Add', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

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

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
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
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
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
                          child: DropdownButtonFormField<String>(
                            value: ['monthly', 'one_time'].contains(priceType) ? priceType : 'monthly',
                            dropdownColor: Colors.white,
                            decoration: const InputDecoration(labelText: 'Price Type'),
                            items: const [
                              DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                              DropdownMenuItem(value: 'one_time', child: Text('One-time')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setSheetState(() {
                                  priceType = val;
                                });
                              }
                            },
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
                      activeColor: const Color(0xFFE65C00),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setSheetState(() {
                          isActive = val;
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () async {
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

                        // Show loader dialog
                        showDialog(
                          context: sheetContext,
                          barrierDismissible: false,
                          builder: (c) => const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00))),
                        );

                        try {
                          final payload = {
                            'library_id': widget.libraryId,
                            'name': name,
                            'price': price,
                            'price_type': priceType,
                            'refundable_deposit': deposit,
                            'max_available': maxAvailable,
                            'active': isActive,
                          };

                          if (isEdit) {
                            await _supabase
                                .from('add_ons')
                                .update(payload)
                                .eq('id', addon['id']);
                          } else {
                            final newId = const Uuid().v4();
                            payload['id'] = newId;
                            await _supabase.from('add_ons').insert(payload);
                          }

                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext); // Close loader
                            Navigator.pop(sheetContext); // Close sheet
                          }

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
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext); // Close loader
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
                      child: Text(isEdit ? 'Save Changes' : 'Add Add-on'),
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
        backgroundColor: Colors.white,
        title: Text('Delete Add-on', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
        content: Text('Are you sure you want to delete "${addon['name']}"? This action cannot be undone.', style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontWeight: FontWeight.bold)),
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
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
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
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
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
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
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
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF1E293B)),
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
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
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
                                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Add optional services like personal lockers, vehicle parking, or premium VIP cabins.',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
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
                                color: Colors.white,
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
                                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B), fontSize: 14),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              'Price: ₹${addon['price']}/${addon['price_type'] == 'one_time' ? 'one-time' : 'monthly'}',
                                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
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


