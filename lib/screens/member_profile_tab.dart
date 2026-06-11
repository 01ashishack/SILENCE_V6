import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/image_optimizer.dart';
import 'notifications_screen.dart';
import 'contact_admin_screen.dart';
import 'reservations/renewal_screen.dart';
import 'reservations/join_flow_screen.dart';
import 'library_public_profile_screen.dart';

class MemberProfileTab extends StatefulWidget {
  final void Function(int) onSwitchTab;
  const MemberProfileTab({super.key, required this.onSwitchTab});

  @override
  State<MemberProfileTab> createState() => _MemberProfileTabState();
}

class _MemberProfileTabState extends State<MemberProfileTab> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _errorMessage;

  // Data
  Map<String, dynamic>? _userProfile;
  List<Map<String, dynamic>> _activeMemberships = [];
  List<Map<String, dynamic>> _pastMemberships = [];
  List<Map<String, dynamic>> _allAttendance = [];
  
  // Referral Stats
  int _totalReferred = 0;
  int _pendingReferrals = 0;
  int _rewardsEarnedDays = 0;
  bool _referralRewardsEnabled = false;

  // Computed Stats
  double _totalStudyHours = 0.0;
  int _daysPresent = 0;
  int _bestStreak = 0;
  int _incompleteSessionsCount = 0;

  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User authentication missing.');
      }

      // 1. Fetch User Profile
      final profileRes = await _supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      
      _userProfile = profileRes;

      // Generate referral code if missing
      if (_userProfile != null && (_userProfile!['referral_code'] == null || _userProfile!['referral_code'].toString().isEmpty)) {
        final shortId = user.id.length >= 5 ? user.id.substring(0, 5).toUpperCase() : 'XXXXX';
        final generatedCode = 'REF-$shortId';
        try {
          await _supabase.from('users').update({'referral_code': generatedCode}).eq('id', user.id);
          _userProfile!['referral_code'] = generatedCode;
        } catch (e) {
          debugPrint('Could not update referral_code in database (column might be missing): $e');
          // Fallback locally so the app doesn't crash and user sees a placeholder code
          _userProfile!['referral_code'] = generatedCode;
        }
      }

      // 2. Fetch Memberships
      final membershipsRes = await _supabase
          .from('memberships')
          .select('*, libraries(*), shifts(*), seats(*)')
          .eq('member_id', user.id);

      final allMemberships = List<Map<String, dynamic>>.from(membershipsRes);

      // Filter active memberships
      _activeMemberships = allMemberships.where((m) {
        final status = m['status'] as String? ?? '';
        return ['active', 'trial', 'hold', 'expired'].contains(status);
      }).toList();

      // Check if any library has referral_rewards_enabled
      _referralRewardsEnabled = false;
      for (var m in allMemberships) {
        final lib = m['libraries'] as Map<String, dynamic>?;
        if (lib != null && lib['referral_rewards_enabled'] == true) {
          _referralRewardsEnabled = true;
        }
      }

      // Filter past memberships (exited or expired, and not active in that library)
      final activeLibIds = _activeMemberships.map((m) => m['library_id'] as String).toSet();
      _pastMemberships = allMemberships.where((m) {
        final status = m['status'] as String? ?? '';
        final libId = m['library_id'] as String? ?? '';
        return (status == 'exited' || status == 'expired') && !activeLibIds.contains(libId);
      }).toList();

      // 3. Fetch Attendance
      final attRes = await _supabase
          .from('attendance')
          .select('check_in_time, check_out_time, session_type, library_id, duration_minutes')
          .eq('member_id', user.id)
          .order('check_in_time', ascending: false);

      _allAttendance = List<Map<String, dynamic>>.from(attRes);

      // Calculate Stats
      Set<String> studyDates = {};
      double hoursSum = 0.0;
      int incompleteCount = 0;

      for (var a in _allAttendance) {
        final checkIn = a['check_in_time'] as String?;
        final checkOut = a['check_out_time'] as String?;
        final sessionType = a['session_type'] as String?;

        if (checkIn != null) {
          final localIn = DateTime.parse(checkIn).toLocal();
          studyDates.add(DateFormat('yyyy-MM-dd').format(localIn));

          if (checkOut != null) {
            final localOut = DateTime.parse(checkOut).toLocal();
            hoursSum += localOut.difference(localIn).inMinutes / 60.0;
          } else if (sessionType == 'incomplete') {
            incompleteCount++;
          }
        }
      }

      _daysPresent = studyDates.length;
      _totalStudyHours = hoursSum;
      _incompleteSessionsCount = incompleteCount;
      _bestStreak = _calculateBestStreak(studyDates);

      // 4. Fetch Referrals
      final referralsRes = await _supabase
          .from('referrals')
          .select()
          .eq('referrer_member_id', user.id);

      final referralsList = List<Map<String, dynamic>>.from(referralsRes);
      _totalReferred = referralsList.length;
      _pendingReferrals = referralsList.where((r) => r['status'] == 'pending').length;
      
      int rewardsDaysSum = 0;
      for (var r in referralsList) {
        if (r['status'] == 'credited') {
          rewardsDaysSum += (r['reward_days'] as int? ?? 3);
        }
      }
      _rewardsEarnedDays = rewardsDaysSum;

    } catch (e) {
      debugPrint('Error loading profile tab data: $e');
      _errorMessage = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  int _calculateBestStreak(Set<String> studyDates) {
    if (studyDates.isEmpty) return 0;
    
    List<DateTime> sortedDates = studyDates
        .map((d) => DateTime.parse(d))
        .toList()
      ..sort();
      
    int maxStreak = 0;
    int currentStreak = 0;
    DateTime? prevDate;
    
    for (var date in sortedDates) {
      if (prevDate == null) {
        currentStreak = 1;
      } else {
        final diff = date.difference(prevDate).inDays;
        if (diff == 1) {
          currentStreak++;
        } else if (diff > 1) {
          if (currentStreak > maxStreak) {
            maxStreak = currentStreak;
          }
          currentStreak = 1;
        }
      }
      prevDate = date;
    }
    
    if (currentStreak > maxStreak) {
      maxStreak = currentStreak;
    }
    
    return maxStreak;
  }

  bool _isProfileIncomplete() {
    final name = _userProfile?['full_name'] as String?;
    final phone = _userProfile?['phone'] as String?;
    final nickname = _userProfile?['nickname'] as String?;
    final gender = _userProfile?['gender'] as String?;
    final dob = _userProfile?['date_of_birth'] as String?;
    final address = _userProfile?['address'] as String?;
    final examCategory = _userProfile?['exam_category'] as String?;
    final photo = _userProfile?['photo_url'] as String?;
    final idProof = _userProfile?['id_proof_url'] as String?;
    
    return name == null || name.trim().isEmpty || 
           phone == null || phone.trim().isEmpty || 
           nickname == null || nickname.trim().isEmpty ||
           gender == null || gender.trim().isEmpty ||
           dob == null || dob.trim().isEmpty ||
           address == null || address.trim().isEmpty ||
           examCategory == null || examCategory.trim().isEmpty ||
           photo == null || photo.trim().isEmpty ||
           idProof == null || idProof.trim().isEmpty;
  }

  // Upload Profile photo helpers
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

  Future<void> _pickAndUploadPhoto() async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
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
              child: Text('Choose Profile Photo Source', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFFE65C00)),
              title: Text('Take Photo (Front Camera)', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFFE65C00)),
              title: Text('Choose from Gallery', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

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
          const SnackBar(content: Text('Camera/Gallery permission denied. Please enable it in Settings.')),
        );
      }
      return;
    }

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 512,
      imageQuality: 80,
    );

    if (image == null) return;

    // Crop Image 1:1
    CroppedFile? croppedFile;
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
      if (!mounted) return;
    } catch (e) {
      debugPrint('Cropping failed: $e');
    }

    final finalPath = croppedFile?.path ?? image.path;

    setState(() {
      _isUploadingPhoto = true;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final bytes = await ImageOptimizer.compressImage(finalPath);
      final fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storagePath = 'member_profiles/${user.id}/$fileName';

      await _supabase.storage.from('silence_assets').uploadBinary(
        storagePath,
        Uint8List.fromList(bytes),
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          cacheControl: '3600',
          upsert: true,
        ),
      );

      final publicUrl = _supabase.storage.from('silence_assets').getPublicUrl(storagePath);

      // Update database
      await _supabase.from('users').update({'photo_url': publicUrl}).eq('id', user.id);
      if (!mounted) return;

      setState(() {
        if (_userProfile != null) {
          _userProfile!['photo_url'] = publicUrl;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated successfully! ✓'), backgroundColor: Color(0xFF10B981)),
        );
      }

    } catch (e) {
      debugPrint('Photo upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload profile photo: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      setState(() {
        _isUploadingPhoto = false;
      });
    }
  }

  // Dial call
  Future<void> _makeCall(String phone) async {
    final Uri url = Uri.parse('tel:$phone');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    } catch (_) {}
  }

  // Open URL
  Future<void> _launchSocial(String urlString) async {
    if (urlString.isEmpty) return;
    String formattedUrl = urlString;
    if (!formattedUrl.startsWith('http://') && !formattedUrl.startsWith('https://')) {
      formattedUrl = 'https://$formattedUrl';
    }
    final Uri url = Uri.parse(formattedUrl);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildSkeletonLoading();
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBF5EE),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text('Error Loading Profile', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_errorMessage!, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600])),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loadData,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                  child: const Text('Retry'),
                )
              ],
            ),
          ),
        ),
      );
    }

    final isProfileIncomplete = _isProfileIncomplete();

    return Scaffold(
      backgroundColor: const Color(0xFFFBF5EE),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildGradientHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isProfileIncomplete) ...[
                    _buildCompletionBanner(),
                    const SizedBox(height: 16),
                  ],
                  _buildMyLibrariesSection(),
                  if (_referralRewardsEnabled || _rewardsEarnedDays > 0) ...[
                    const SizedBox(height: 24),
                    _buildReferralsCard(),
                  ],
                  const SizedBox(height: 24),
                  _buildAccountSection(),
                  const SizedBox(height: 24),
                  _buildShareAppCard(),
                  const SizedBox(height: 24),
                  _buildSupportAndLegalSection(),
                  const SizedBox(height: 24),
                  _buildLogoutRow(),
                  const SizedBox(height: 24),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  // 1. GRADIENT HEADER WITH STATS STRIP
  Widget _buildGradientHeader() {
    final photoUrl = _userProfile?['photo_url'] as String?;
    final name = _userProfile?['full_name'] ?? 'Silence Student';
    final nickname = _userProfile?['nickname'] ?? 'N/A';
    final examCategory = _userProfile?['exam_category'] ?? 'UPSC';
    final address = _userProfile?['address'] as String? ?? '';
    
    // Parse City/State from Address
    String displayLocation = 'No address set';
    if (address.isNotEmpty) {
      final parts = address.split(',');
      if (parts.length >= 2) {
        displayLocation = '${parts[parts.length - 2].trim()}, ${parts[parts.length - 1].trim()}';
      } else {
        displayLocation = address.trim();
        if (displayLocation.length > 25) {
          displayLocation = '${displayLocation.substring(0, 22)}...';
        }
      }
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE65C00), Color(0xFFC44E00)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        bottom: 24,
      ),
      child: Column(
        children: [
          // Top Row (Title + Bell Icon)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 32), // spacer for symmetry
              Text(
                'Profile',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Colors.white, size: 24),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Avatar Row
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: CircleAvatar(
                      radius: 36,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      backgroundImage: photoUrl != null && photoUrl.isNotEmpty ? CachedNetworkImageProvider(photoUrl) : null,
                      child: photoUrl == null || photoUrl.isEmpty
                          ? const Icon(Icons.person, size: 36, color: Colors.white)
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: _isUploadingPhoto
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFE65C00)),
                              )
                            : const Icon(Icons.camera_alt, size: 12, color: Color(0xFFE65C00)),
                      ),
                    ),
                  )
                ],
              ),
              const SizedBox(width: 16),
              // User info texts
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      nickname != 'N/A' ? '@$nickname' : '@silence_user',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            examCategory.toString().toUpperCase(),
                            style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.location_on, size: 10, color: Colors.white70),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            displayLocation,
                            style: GoogleFonts.inter(fontSize: 10, color: Colors.white70),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 20),
          // Stats Strip (Glass Card)
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('${_totalStudyHours.toStringAsFixed(1)}h', 'STUDY HOURS', 0),
                _buildDivider(),
                _buildStatItem('$_daysPresent', 'DAYS PRESENT', 1),
                _buildDivider(),
                _buildStatItem('$_bestStreak d', 'BEST STREAK', 2),
                _buildDivider(),
                _buildStatItem('$_incompleteSessionsCount', 'INCOMPLETE', 3),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatItem(String val, String label, int index) {
    return GestureDetector(
      onTap: () {
        // Switch to Analytics tab (index 1)
        widget.onSwitchTab(1);
      },
      child: Column(
        children: [
          Text(
            val,
            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.6)),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 24,
      color: Colors.white.withOpacity(0.15),
    );
  }

  // 2. PROFILE COMPLETION BANNER
  Widget _buildCompletionBanner() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3ED),
        borderRadius: BorderRadius.circular(14),
        border: const Border(left: BorderSide(color: Color(0xFFE65C00), width: 4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFE65C00), size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Complete your profile',
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                ),
                const SizedBox(height: 2),
                Text(
                  'Add your ID document to complete setup',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pushNamed(context, '/member/edit-profile').then((_) => _loadData());
            },
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: Row(
              children: [
                Text(
                  'Complete Now',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                ),
                const Icon(Icons.chevron_right, size: 16, color: Color(0xFFE65C00)),
              ],
            ),
          )
        ],
      ),
    );
  }

  // 3. MY LIBRARIES SECTION
  Widget _buildMyLibrariesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title
        Text(
          'MY LIBRARIES',
          style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFF9CA3AF), letterSpacing: 1.5),
        ),
        const SizedBox(height: 8),

        if (_activeMemberships.isEmpty && _pastMemberships.isEmpty) ...[
          // Empty state
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.business_outlined, size: 48, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text(
                  'You haven\'t joined any libraries yet.',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500]),
                ),
              ],
            ),
          )
        ] else ...[
          // Active Memberships
          ..._activeMemberships.map((m) => _buildActiveMembershipCard(m)),
          
          // Past Libraries Sub-section
          if (_pastMemberships.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'PAST LIBRARIES',
              style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFF9CA3AF), letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            ..._pastMemberships.map((m) => _buildPastMembershipCard(m)),
          ],
        ],
      ],
    );
  }

  Widget _buildActiveMembershipCard(Map<String, dynamic> membership) {
    final status = membership['status'] as String? ?? 'pending';
    final library = membership['libraries'] as Map<String, dynamic>? ?? {};
    final shift = membership['shifts'] as Map<String, dynamic>? ?? {};
    final seat = membership['seats'] as Map<String, dynamic>? ?? {};

    // Get border color and label
    Color borderColor = const Color(0xFF22C55E); // active: green
    String statusLabel = 'Active';

    if (status == 'trial') {
      borderColor = const Color(0xFF7C3AED); // trial: purple
      statusLabel = 'Trial';
    } else if (status == 'hold') {
      borderColor = const Color(0xFF92400E); // hold: amber-brown
      statusLabel = 'On Hold';
    } else if (status == 'expired') {
      borderColor = const Color(0xFFEF4444); // expired: red
      statusLabel = 'Expired';
    }

    DateTime? endDate;
    if (membership['end_date'] != null) {
      endDate = DateTime.parse(membership['end_date']);
    }
    final remainingDays = endDate != null ? endDate.difference(DateTime.now()).inDays : -1;

    // Check expiring soon
    if (status == 'active' && remainingDays <= 7 && remainingDays >= 0) {
      borderColor = const Color(0xFFF59E0B); // expiringSoon: amber
      statusLabel = 'Expiring Soon';
    }

    // Progress bar calculation
    double progress = 0.0;
    if (membership['start_date'] != null && membership['end_date'] != null) {
      final start = DateTime.parse(membership['start_date']);
      final end = DateTime.parse(membership['end_date']);
      final total = end.difference(start).inDays;
      if (total > 0) {
        final elapsed = DateTime.now().difference(start).inDays;
        progress = (elapsed / total).clamp(0.0, 1.0);
      }
    }

    final isVerified = library['verified'] == true;
    final Map<String, dynamic> socialLinks = library['social_links'] as Map<String, dynamic>? ?? {};
    final String phone = library['emergency_phone']?.toString() ?? '';

    // Verify if there are social links
    final hasInstagram = socialLinks['instagram'] != null && socialLinks['instagram'].toString().trim().isNotEmpty;
    final hasYoutube = socialLinks['youtube'] != null && socialLinks['youtube'].toString().trim().isNotEmpty;
    final hasFacebook = socialLinks['facebook'] != null && socialLinks['facebook'].toString().trim().isNotEmpty;
    final hasWhatsapp = socialLinks['whatsapp'] != null && socialLinks['whatsapp'].toString().trim().isNotEmpty;
    final hasWebsite = socialLinks['website'] != null && socialLinks['website'].toString().trim().isNotEmpty;
    final hasSocials = hasInstagram || hasYoutube || hasFacebook || hasWhatsapp || hasWebsite;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: borderColor, width: 4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // Navigate to library profile read-only
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => LibraryPublicProfileScreen(
                  libraryId: library['id'],
                  isAdmin: false,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + Status badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              library['name'] ?? 'SILENCE Library',
                              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified, color: Colors.blue, size: 16),
                          ]
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: borderColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: borderColor),
                      ),
                    )
                  ],
                ),
                // Address
                if (library['address_street'] != null || library['address_city'] != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${library['address_street'] ?? ''}, ${library['address_city'] ?? ''}',
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
                const SizedBox(height: 12),
                
                // Seat + Shift Row
                Row(
                  children: [
                    const Icon(Icons.event_seat, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      seat.isNotEmpty ? (seat['seat_label'] ?? 'Pending') : 'Seat Pending',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFFE65C00)),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.wb_sunny_outlined, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        shift.isNotEmpty ? '${shift['name']} (${shift['start_time']} - ${shift['end_time']})' : 'Shift Pending',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[700]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                // Plan type
                Row(
                  children: [
                    const Icon(Icons.card_membership, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      'Plan: ${membership['plan_type'] == 'monthly' ? 'Monthly' : membership['plan_type'] == '3_month' ? '3-Month' : membership['plan_type'] == '6_month' ? '6-Month' : 'Trial'}',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),

                if (endDate != null) ...[
                  const SizedBox(height: 12),
                  // Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey[200],
                      color: borderColor,
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Expires: ${DateFormat('dd MMM yyyy').format(endDate)}',
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => RenewalScreen(
                                    libraryId: library['id'],
                                    initialShiftId: shift['id'],
                                    initialPlan: membership['plan_type'],
                                  ),
                                ),
                              ).then((_) => _loadData());
                            },
                            child: Text(
                              'Renew',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00), decoration: TextDecoration.underline),
                            ),
                          )
                        ],
                      ),
                      Text(
                        remainingDays > 0 ? '$remainingDays days left' : remainingDays == 0 ? 'Expires today' : 'Expired',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: remainingDays <= 7 ? Colors.redAccent : Colors.grey[600]),
                      ),
                    ],
                  ),
                ],

                // Call Emergency row
                if (phone.isNotEmpty) ...[
                  const Divider(height: 24),
                  InkWell(
                    onTap: () => _makeCall(phone),
                    child: Row(
                      children: [
                        const Icon(Icons.phone_in_talk, size: 14, color: Color(0xFFE65C00)),
                        const SizedBox(width: 8),
                        Text(
                          'Call Library: $phone',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFFE65C00)),
                        ),
                      ],
                    ),
                  ),
                ],

                // Social Links row
                if (hasSocials) ...[
                  const Divider(height: 24),
                  Row(
                    children: [
                      Text(
                        'Social Links: ',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                      ),
                      const SizedBox(width: 8),
                      if (hasInstagram)
                        _buildSocialIcon(Icons.camera_alt_outlined, () => _launchSocial(socialLinks['instagram'])),
                      if (hasYoutube)
                        _buildSocialIcon(Icons.video_library_outlined, () => _launchSocial(socialLinks['youtube'])),
                      if (hasFacebook)
                        _buildSocialIcon(Icons.facebook_outlined, () => _launchSocial(socialLinks['facebook'])),
                      if (hasWhatsapp)
                        _buildSocialIcon(Icons.chat_bubble_outline, () => _launchSocial(socialLinks['whatsapp'])),
                      if (hasWebsite)
                        _buildSocialIcon(Icons.language_outlined, () => _launchSocial(socialLinks['website'])),
                    ],
                  ),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSocialIcon(IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3ED),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: const Color(0xFFE65C00)),
        ),
      ),
    );
  }

  Widget _buildPastMembershipCard(Map<String, dynamic> membership) {
    final library = membership['libraries'] as Map<String, dynamic>? ?? {};
    final libId = library['id'] as String? ?? '';
    final String lastDateStr = membership['end_date'] ?? membership['updated_at'] ?? '';
    
    String dateLabel = 'Last active date unavailable';
    if (lastDateStr.isNotEmpty) {
      dateLabel = 'Left: ${DateFormat('dd MMM yyyy').format(DateTime.parse(lastDateStr))}';
    }

    // Calculate dynamic past study hours
    final double libHours = _allAttendance
        .where((a) => a['library_id'] == libId && a['check_out_time'] != null)
        .fold(0.0, (sum, a) {
          final start = DateTime.parse(a['check_in_time']);
          final end = DateTime.parse(a['check_out_time']);
          return sum + end.difference(start).inMinutes / 60.0;
        });

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
        border: const Border(left: BorderSide(color: Color(0xFF9CA3AF), width: 4)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => LibraryPublicProfileScreen(
                  libraryId: libId,
                  isAdmin: false,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        library['name'] ?? 'SILENCE Study Zone',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF4B5563)),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => JoinFlowScreen(
                              libraryId: libId,
                            ),
                          ),
                        ).then((_) => _loadData());
                      },
                      child: Text(
                        'Rejoin →',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                      ),
                    )
                  ],
                ),
                if (library['address_city'] != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    library['address_city'],
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dateLabel,
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                    ),
                    Text(
                      '🔁 ${libHours.toStringAsFixed(1)} hours studied',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF4B5563)),
                    )
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'History preserved ✓ Badges kept',
                  style: GoogleFonts.inter(fontSize: 9, color: Colors.grey[400], fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 4. REFERRALS CARD
  Widget _buildReferralsCard() {
    final refCode = _userProfile?['referral_code']?.toString() ?? 'REF-XXXX';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Label
          Text(
            'REFERRAL',
            style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFF9CA3AF), letterSpacing: 1.5),
          ),
          const SizedBox(height: 12),
          
          Row(
            children: [
              Text(
                'Refer a Friend 🎁',
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Share your referral code and earn extension days when they join SILENCE!',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),

          // Monospace Code Container
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3ED),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFD8C2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SelectableText(
                  refCode,
                  style: GoogleFonts.spaceMono(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00), letterSpacing: 1.5),
                ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: refCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Referral code copied to clipboard! ✓'), backgroundColor: Color(0xFF10B981)),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.copy, size: 16, color: Color(0xFFE65C00)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        Share.share(
                          'Join me at SILENCE Study Zone using my referral code: $refCode. Download the app here: https://silenceapp.in/download',
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.share, size: 16, color: Color(0xFFE65C00)),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          if (_totalReferred == 0) ...[
            Text(
              'Share your code to earn free study days.',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[400], fontStyle: FontStyle.italic),
            ),
          ] else ...[
            // Referral Stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildReferralStatCol('Referred Friends', '$_totalReferred'),
                _buildReferralStatCol('Rewards Earned', '$_rewardsEarnedDays days'),
                _buildReferralStatCol('Pending', '$_pendingReferrals'),
              ],
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildReferralStatCol(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[500]),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
        ),
      ],
    );
  }

  // SKELETON LOADERS
  Widget _buildSkeletonLoading() {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF5EE),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header Skeleton
            Container(
              height: 200,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFE65C00), Color(0xFFC44E00)],
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildShimmerCard(height: 70),
                  const SizedBox(height: 16),
                  _buildShimmerCard(height: 160),
                  const SizedBox(height: 16),
                  _buildShimmerCard(height: 120),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  void _showChangeRoleDialog() {
    final hasActive = _activeMemberships.isNotEmpty;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          'Switch to Admin Role?',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to switch your account type to Admin?',
              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569)),
            ),
            const SizedBox(height: 12),
            if (hasActive) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning, color: Color(0xFFEF4444), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'WARNING: You currently have active memberships. Changing your role will block your access to these libraries.',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF991B1B)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'You will be signed out. Upon logging back in, you will configure your library workspace as an Admin.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              try {
                final user = _supabase.auth.currentUser;
                if (user != null) {
                  await _supabase.from('users').update({'role': 'admin'}).eq('id', user.id);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear();
                  await _supabase.auth.signOut();
                  if (context.mounted) {
                    Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to switch role: $e')),
                  );
                }
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text('Confirm - Switch to Admin', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 5. ACCOUNT SECTION
  Widget _buildAccountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ACCOUNT',
          style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFF9CA3AF), letterSpacing: 1.5),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            children: [
              _buildRowItem(
                icon: Icons.person_outline,
                iconBg: const Color(0xFFFFF3ED),
                iconColor: const Color(0xFFE65C00),
                title: 'Edit Profile',
                subtitle: 'Name, photo, DOB, address, ID documents',
                onTap: () {
                  Navigator.pushNamed(context, '/member/edit-profile').then((_) => _loadData());
                },
              ),
              const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
              _buildRowItem(
                icon: Icons.notifications_none_outlined,
                iconBg: const Color(0xFFDBEAFE),
                iconColor: const Color(0xFF2563EB),
                title: 'Notification Preferences',
                subtitle: 'Control what you get notified about',
                onTap: () {
                  Navigator.pushNamed(context, '/member/settings/notifications');
                },
              ),
              const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
              _buildRowItem(
                icon: Icons.lock_outline,
                iconBg: const Color(0xFFDCFCE7),
                iconColor: const Color(0xFF16A34A),
                title: 'Privacy & Security',
                subtitle: 'Password, phone verification, leaderboard visibility',
                onTap: () {
                  Navigator.pushNamed(context, '/member/settings/privacy');
                },
              ),
              const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
              _buildRowItem(
                icon: Icons.language_outlined,
                iconBg: const Color(0xFFF3F4F6),
                iconColor: const Color(0xFF4B5563),
                title: 'Language',
                subtitle: 'English',
                badgeText: '🔜 Coming Soon',
                onTap: () {
                  _showLanguageDialog();
                },
              ),
              const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
              _buildRowItem(
                icon: Icons.swap_horiz,
                iconBg: const Color(0xFFFEE2E2),
                iconColor: const Color(0xFFEF4444),
                title: 'Change Role',
                subtitle: 'Switch between Admin and Member (requires confirmation)',
                onTap: _showChangeRoleDialog,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Helper row builder
  Widget _buildRowItem({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? badgeText,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconBg,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
      ),
      trailing: badgeText != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3ED),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badgeText,
                style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
              ),
            )
          : const Icon(Icons.chevron_right, size: 16, color: Color(0xFF94A3B8)),
      onTap: onTap,
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF3ED),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.translate, color: Color(0xFFE65C00), size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                'More Languages',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 8),
              Text(
                'More languages will be available in future updates. Stay tuned!',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Got it', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // 6. SHARE APP CARD
  Widget _buildShareAppCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE65C00), Color(0xFFC44E00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Share.share(
              'Hey! Download the SILENCE Study Zone App to find silent study spaces near you: https://silenceapp.in/download',
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
            child: Row(
              children: [
                const Text(
                  '📲',
                  style: TextStyle(fontSize: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Share SILENCE App',
                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Invite your study buddies to join!',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 7. SUPPORT & LEGAL SECTION
  Widget _buildSupportAndLegalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'HELP & LEGAL',
          style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFF9CA3AF), letterSpacing: 1.5),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            children: [
              _buildRowItem(
                icon: Icons.forum_outlined,
                iconBg: const Color(0xFFFFEDD5),
                iconColor: const Color(0xFFE65C00),
                title: 'Contact Admin',
                subtitle: 'Send queries & see admin replies',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ContactAdminScreen(),
                    ),
                  );
                },
              ),
              const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
              _buildRowItem(
                icon: Icons.chat_bubble_outline,
                iconBg: const Color(0xFFDBEAFE),
                iconColor: const Color(0xFF2563EB),
                title: 'Help & Support',
                subtitle: 'FAQs, contact us, report issues',
                onTap: () {
                  Navigator.pushNamed(context, '/member/help');
                },
              ),
              const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
              _buildRowItem(
                icon: Icons.info_outline,
                iconBg: const Color(0xFFF3F4F6),
                iconColor: const Color(0xFF4B5563),
                title: 'About SILENCE',
                subtitle: 'Version 1.0.0 · Meet the team',
                onTap: () {
                  Navigator.pushNamed(context, '/member/about');
                },
              ),
              const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
              _buildRowItem(
                icon: Icons.description_outlined,
                iconBg: const Color(0xFFF3F4F6),
                iconColor: const Color(0xFF4B5563),
                title: 'Terms & Conditions',
                subtitle: 'Last updated: Jan 2026',
                onTap: () {
                  Navigator.pushNamed(context, '/member/terms');
                },
              ),
              const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
              _buildRowItem(
                icon: Icons.shield_outlined,
                iconBg: const Color(0xFFF3F4F6),
                iconColor: const Color(0xFF4B5563),
                title: 'Privacy Policy',
                subtitle: 'Last updated: Jan 2026',
                onTap: () {
                  Navigator.pushNamed(context, '/member/privacy-policy');
                },
              ),
              const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
              _buildRowItem(
                icon: Icons.assignment_outlined,
                iconBg: const Color(0xFFF3F4F6),
                iconColor: const Color(0xFF4B5563),
                title: 'Licences',
                subtitle: 'Third-party libraries used',
                onTap: () {
                  Navigator.pushNamed(context, '/member/licences');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 8. LOGOUT ROW
  Widget _buildLogoutRow() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Color(0xFFFEE2E2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.exit_to_app, color: Color(0xFFDC2626), size: 20),
        ),
        title: Text(
          'Logout',
          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFDC2626)),
        ),
        trailing: const Icon(Icons.chevron_right, size: 16, color: Color(0xFFDC2626)),
        onTap: () {
          _showLogoutDialog();
        },
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Confirm Logout',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'Are you sure you want to log out?',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.grey[500]),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() {
                _isLoading = true;
              });
              try {
                await _supabase.auth.signOut();
                if (mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to logout: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              } finally {
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                  });
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              elevation: 0,
            ),
            child: Text(
              'Log Out',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerCard({required double height}) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: CircularProgressIndicator(
          color: const Color(0xFFE65C00).withValues(alpha: 0.15),
          strokeWidth: 2,
        ),
      ),
    );
  }
}
