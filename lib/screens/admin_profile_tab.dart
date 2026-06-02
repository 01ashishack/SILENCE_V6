import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  // Dynamic Profile Fields
  String _adminName = '';
  String? _adminPhotoUrl;
  String _subscriptionStatus = 'Active Subscription';
  String _defaultLibraryName = 'SILENCE Study Zone';
  List<Map<String, dynamic>> _myLibrariesList = [];

  @override
  void initState() {
    super.initState();
    // Fallback/Initial state from widget inputs to avoid flash of empty elements
    _adminName = widget.adminName;
    _defaultLibraryName = widget.libraryName;
    
    _myLibrariesList = List<Map<String, dynamic>>.from(widget.myLibraries.map((lib) {
      final coverPhotoUrl = lib['cover_photo_url'] ?? (lib['photos'] != null && (lib['photos'] as List).isNotEmpty ? (lib['photos'] as List).first.toString() : null);
      return {
        'id': lib['id'],
        'name': lib['name'] ?? 'Study Center',
        'address_city': lib['address_city'] ?? 'City',
        'cover_photo_url': coverPhotoUrl,
        'member_count': 0, // starts at 0; loaded dynamically below
        'occupancy_pct': 0, // starts at 0; loaded dynamically below
      };
    }));

    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        // 1. Fetch user data (full name, subscription status, etc.)
        final userData = await _supabase.from('users').select().eq('id', user.id).maybeSingle();
        if (userData != null && mounted) {
          setState(() {
            _adminName = userData['full_name'] ?? widget.adminName;
            _adminPhotoUrl = userData['photo_url'];
            final subStatus = userData['subscription_status'] ?? 'trial';
            _subscriptionStatus = subStatus.toString().toLowerCase() == 'active' ? 'Active Subscription' : 'Trial Plan';
          });
        }

        // 2. Fetch owned libraries list
        final libsRes = await _supabase.from('libraries').select().eq('owner_id', user.id);
        final List<Map<String, dynamic>> rawLibs = List<Map<String, dynamic>>.from(libsRes);

        // 3. For each library, load memberships and seat stats dynamically
        final List<Map<String, dynamic>> enrichedLibs = [];
        for (var lib in rawLibs) {
          final libId = lib['id'];
          final name = lib['name'] ?? 'Study Center';
          final addressCity = lib['address_city'] ?? 'City';
          final coverPhotoUrl = lib['cover_photo_url'] ?? (lib['photos'] != null && (lib['photos'] as List).isNotEmpty ? (lib['photos'] as List).first.toString() : null);

          // Fetch member count
          int memberCount = 0;
          try {
            final membersRes = await _supabase.from('memberships').select('id').eq('library_id', libId);
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
            'id': libId,
            'name': name,
            'address_city': addressCity,
            'cover_photo_url': coverPhotoUrl,
            'member_count': memberCount,
            'occupancy_pct': occupancyPct,
          });
        }

        if (mounted) {
          setState(() {
            _myLibrariesList = enrichedLibs;
            if (_myLibrariesList.isNotEmpty) {
              _defaultLibraryName = _myLibrariesList.first['name'];
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

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFFBF5EE), // Cream background for premium visual harmony
        body: RefreshIndicator(
          onRefresh: _loadProfileData,
          color: const Color(0xFFE65C00),
          backgroundColor: Colors.white,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Curved Orange Header with Overlapping Systems Operational Pill
                _buildPremiumHeader(),
                
                // Extra gap to offset overlapping pill cleanly
                const SizedBox(height: 32),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 2. Your Libraries List Section
                      _buildYourLibrariesCard(context),
                      const SizedBox(height: 20),

                      // 3. Business Settings Grid
                      _buildBusinessSettingsGrid(context),
                      const SizedBox(height: 20),

                      // 4. Account Actions List
                      _buildAccountSettingsCard(context),
                      const SizedBox(height: 24),

                      // 5. Logout Account Action
                      OutlinedButton.icon(
                        onPressed: widget.onLogout,
                        icon: const Icon(Icons.logout, color: Colors.redAccent, size: 18),
                        label: Text(
                          'Logout Account',
                          style: GoogleFonts.inter(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.redAccent, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.white,
                        ),
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

  Widget _buildPremiumHeader() {
    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        // Orange Gradient Container matching Reservations Tab layout exactly
        Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 16,
            bottom: 36, // bottom padding leaves enough space for pill overlap
            left: 16,
            right: 16,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFF6B00), // Vibrant Bright Orange
                Color(0xFFE65C00), // Primary Brand Orange
              ],
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Circular avatar matching mockup screenshot exactly
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 34,
                      backgroundColor: const Color(0xFFFFF7F0),
                      backgroundImage: _adminPhotoUrl != null && _adminPhotoUrl!.isNotEmpty
                          ? NetworkImage(_adminPhotoUrl!)
                          : null,
                      child: _adminPhotoUrl == null || _adminPhotoUrl!.isEmpty
                          ? Text(
                              _adminName.isNotEmpty ? _adminName[0].toUpperCase() : 'A',
                              style: GoogleFonts.outfit(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFE65C00),
                              ),
                            )
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: 1,
                    right: 1,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981), // Emerald green online dot
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              // Main content Column next to avatar
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _adminName,
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Owner • $_defaultLibraryName',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.85),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    // Libraries and active subscription details in high-fidelity pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${_myLibrariesList.length} ${_myLibrariesList.length == 1 ? 'Library' : 'Libraries'}'),
                            const TextSpan(
                              text: '  •  ',
                              style: TextStyle(color: Color(0xFFFF8E40), fontWeight: FontWeight.bold),
                            ),
                            TextSpan(text: _subscriptionStatus),
                          ],
                        ),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Translucent square shortcut button at the top-right
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                ),
                child: IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 18),
                  tooltip: 'Edit Profile',
                  onPressed: () {
                    Navigator.pushNamed(context, '/admin/profile/complete').then((val) {
                      if (val == true) {
                        _loadProfileData();
                      }
                    });
                  },
                ),
              ),
            ],
          ),
        ),
        
        // Premium overlapping "All systems operational" status pill
        Positioned(
          bottom: -16, // places it perfectly in the center of the bottom curved boundary
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5), // Light emerald/mint background
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFFA7F3D0), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 15,
                  color: Color(0xFF059669), // premium green icon
                ),
                const SizedBox(width: 6),
                Text(
                  'All systems operational',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF059669), // premium green text
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildYourLibrariesCard(BuildContext context) {
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
          Text(
            'Your Libraries',
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          _myLibrariesList.isEmpty
              ? Container(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No libraries found. Click manage libraries to add.',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _myLibrariesList.length,
                  separatorBuilder: (context, idx) => const Divider(height: 20, color: Color(0xFFF1F5F9)),
                  itemBuilder: (context, idx) {
                    final lib = _myLibrariesList[idx];
                    final name = lib['name'] ?? 'Study Center';
                    final city = lib['address_city'] ?? 'City';
                    final coverPhotoUrl = lib['cover_photo_url'];
                    final memberCount = lib['member_count'] ?? 0;
                    final occupancyPct = lib['occupancy_pct'] ?? 0;
                    final libId = lib['id'];

                    return InkWell(
                      onTap: () {
                        Navigator.pushNamed(context, '/admin/library/profile', arguments: libId).then((_) {
                          _loadProfileData();
                        });
                      },
                      child: Row(
                        children: [
                          // Cover Photo or fall back icon
                          coverPhotoUrl != null && coverPhotoUrl.toString().isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    coverPhotoUrl.toString(),
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      width: 48,
                                      height: 48,
                                      color: const Color(0xFFFFF3ED),
                                      child: const Icon(Icons.storefront, color: Color(0xFFE65C00), size: 24),
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF3ED),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.storefront, color: Color(0xFFE65C00), size: 24),
                                  ),
                                ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$city • $memberCount Members • $occupancyPct% Occupancy',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: const Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 18, color: Color(0xFF94A3B8)),
                        ],
                      ),
                    );
                  },
                ),
          const SizedBox(height: 16),
          
          // Manage Libraries Outline Button matching layout perfectly
          OutlinedButton(
            onPressed: () {
              Navigator.pushNamed(
                context, 
                '/admin/library/profile', 
                arguments: widget.libraryId ?? (_myLibrariesList.isNotEmpty ? _myLibrariesList.first['id'] : null)
              ).then((_) {
                _loadProfileData();
              });
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              backgroundColor: Colors.white,
            ),
            child: Center(
              child: Text(
                'Manage Libraries',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFE65C00), // Primary theme brand orange
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessSettingsGrid(BuildContext context) {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Business Settings',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const Icon(Icons.settings, size: 16, color: Color(0xFF6B7280)),
            ],
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            childAspectRatio: 0.9,
            children: [
              _buildGridItem(context, Icons.access_time, 'Hours & Shifts', '/admin/settings/shifts'),
              _buildGridItem(context, Icons.receipt_long, 'Seat Pricing', '/admin/settings/pricing'),
              _buildGridItem(context, Icons.rule_folder, 'Conduct Rules', '/admin/settings/business-rules'),
              _buildGridItem(context, Icons.palette_outlined, 'Branding', '/admin/settings/branding'),
              _buildGridItem(context, Icons.qr_code, 'QR Assets', '/admin/settings/qr'),
              _buildGridItem(context, Icons.widgets_outlined, 'Add-on Services', '/admin/settings/addons'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, IconData icon, String label, String routeName) {
    return InkWell(
      onTap: () {
        Navigator.pushNamed(
          context,
          routeName,
          arguments: widget.libraryId,
        ).then((_) {
          _loadProfileData();
        });
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3ED),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: const Color(0xFFE65C00)),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF4B5563),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSettingsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
          _buildListItem(context, Icons.person_outline, 'Edit Admin Profile', '/admin/profile/complete'),
          _buildListItem(context, Icons.stars_outlined, 'Subscription & Billing', '/admin/subscription'),
          _buildListItem(context, Icons.campaign_outlined, 'Announcements History', '/admin/announcements'),
          _buildListItem(context, Icons.ios_share, 'Exports & Reports', '/admin/exports'),
          _buildListItem(context, Icons.history_edu_outlined, 'Audit Log History', '/admin/audit-log'),
          _buildListItem(context, Icons.people_outline, 'Referrals Configuration', '/admin/settings/referrals'),
          _buildListItem(context, Icons.calendar_month_outlined, 'Scheduled Closures', '/admin/settings/closures'),
          _buildListItem(context, Icons.notifications_active_outlined, 'Notification Preferences', '/admin/settings/notifications'),
        ],
      ),
    );
  }

  Widget _buildListItem(BuildContext context, IconData icon, String title, String routeName) {
    return ListTile(
      leading: Icon(icon, size: 20, color: const Color(0xFF6B7280)),
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
}
