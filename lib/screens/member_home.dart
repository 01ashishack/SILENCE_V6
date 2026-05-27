import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../core/offline_db.dart';
import '../core/offline_sync.dart';
import 'reservations/qr_scanner_screen.dart';
import 'reservations/join_flow_screen.dart';

class MemberHomeScreen extends StatefulWidget {
  const MemberHomeScreen({super.key});

  @override
  State<MemberHomeScreen> createState() => _MemberHomeScreenState();
}

class _MemberHomeScreenState extends State<MemberHomeScreen> with SingleTickerProviderStateMixin {
  int _currentBottomTab = 0; // 0 = Home, 1 = Analytics, 2 = Profile
  int _currentSubTab = 0; // 0 = My Library, 1 = Explore (Home sub-tabs)
  
  bool _isLoading = true;
  String? _errorMessage;

  // Domain data
  Map<String, dynamic>? _userProfile;
  List<Map<String, dynamic>> _myMemberships = [];
  List<Map<String, dynamic>> _announcements = [];
  Set<String> _readAnnouncementIds = {};
  Map<String, dynamic>? _activeAttendance;
  
  // Explore Tab State
  List<Map<String, dynamic>> _exploreLibraries = [];
  List<Map<String, dynamic>> _filteredLibraries = [];
  final TextEditingController _searchController = TextEditingController();
  
  // Attendance Live Ticker
  Timer? _attendanceTimer;
  String _liveSessionDuration = '0h 0m 0s';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _searchController.addListener(_filterLibraries);
    
    // Start listening for internet status to sync offline scans
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OfflineSyncManager.instance.startListening(context);
    });
  }

  @override
  void dispose() {
    _attendanceTimer?.cancel();
    _searchController.dispose();
    OfflineSyncManager.instance.stopListening();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        throw Exception('No logged in user found.');
      }

      // 1. Load User Profile
      final profileRes = await supabase
          .from('users')
          .select()
          .eq('id', currentUser.id)
          .maybeSingle();
      
      _userProfile = profileRes;

      if (_userProfile == null) {
        // Create placeholder profile if missing
        final email = currentUser.email ?? '';
        final name = email.split('@').first;
        final newProfile = {
          'id': currentUser.id,
          'email': email,
          'full_name': name,
          'role': 'member',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        };
        await supabase.from('users').insert(newProfile);
        _userProfile = newProfile;
      }

      // 2. Load My Memberships (Joining Shifts, Libraries, Seats)
      final membershipsRes = await supabase
          .from('memberships')
          .select('*, libraries(*), shifts(*), seats(*)')
          .eq('member_id', currentUser.id)
          .order('created_at', ascending: false);

      _myMemberships = List<Map<String, dynamic>>.from(membershipsRes);

      // 3. Load Active Attendance (if checked in)
      final attendanceRes = await supabase
          .from('attendance')
          .select('*, memberships(*), shifts(*), libraries(*)')
          .eq('member_id', currentUser.id)
          .isFilter('check_out_time', null)
          .order('check_in_time', ascending: false)
          .limit(1)
          .maybeSingle();

      _activeAttendance = attendanceRes;
      if (_activeAttendance != null) {
        final checkInStr = _activeAttendance!['check_in_time'] as String;
        _startAttendanceTicker(DateTime.parse(checkInStr));
      } else {
        _attendanceTimer?.cancel();
        _liveSessionDuration = '0h 0m 0s';
      }

      // 4. Load Announcements for my joined libraries
      if (_myMemberships.isNotEmpty) {
        final libraryIds = _myMemberships
            .map((m) => m['library_id'] as String)
            .toSet()
            .toList();

        final announcementsRes = await supabase
            .from('announcements')
            .select('*, libraries(name)')
            .inFilter('library_id', libraryIds)
            .order('sent_at', ascending: false)
            .limit(3);

        _announcements = List<Map<String, dynamic>>.from(announcementsRes);

        // Load read announcements
        final readsRes = await supabase
            .from('announcement_reads')
            .select('announcement_id')
            .eq('member_id', currentUser.id);
        
        _readAnnouncementIds = (readsRes as List)
            .map((r) => r['announcement_id'] as String)
            .toSet();
      } else {
        _announcements = [];
        _readAnnouncementIds = {};
      }

      // 5. Load Explore Libraries (All active libraries)
      final exploreRes = await supabase
          .from('libraries')
          .select('*, shifts(*)')
          .eq('status', 'active');

      _exploreLibraries = List<Map<String, dynamic>>.from(exploreRes);
      _filteredLibraries = List.from(_exploreLibraries);

    } catch (e) {
      debugPrint('Error loading member home data: $e');
      _errorMessage = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startAttendanceTicker(DateTime checkInTime) {
    _attendanceTimer?.cancel();
    _updateLiveDuration(checkInTime);
    _attendanceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateLiveDuration(checkInTime);
    });
  }

  void _updateLiveDuration(DateTime checkInTime) {
    final diff = DateTime.now().difference(checkInTime.toLocal());
    final hrs = diff.inHours;
    final mins = diff.inMinutes.remainder(60);
    final secs = diff.inSeconds.remainder(60);
    if (mounted) {
      setState(() {
        _liveSessionDuration = '${hrs}h ${mins}m ${secs}s';
      });
    }
  }

  void _filterLibraries() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredLibraries = List.from(_exploreLibraries);
      });
      return;
    }

    setState(() {
      _filteredLibraries = _exploreLibraries.where((lib) {
        final name = (lib['name'] ?? '').toString().toLowerCase();
        final city = (lib['address_city'] ?? '').toString().toLowerCase();
        final code = (lib['library_code'] ?? '').toString().toLowerCase();
        return name.contains(query) || city.contains(query) || code.contains(query);
      }).toList();
    });
  }

  bool _isProfileIncomplete() {
    if (_userProfile == null) return true;
    final name = _userProfile!['full_name'] as String?;
    final phone = _userProfile!['phone'] as String?;
    final photo = _userProfile!['photo_url'] as String?;
    return name == null || name.isEmpty || phone == null || phone.isEmpty || photo == null || photo.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE65C00), // Match Status Bar orange color
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: const Color(0xFFFBF5EE), // Premium Warm Cream
          body: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
              : _errorMessage != null
                  ? _buildErrorState()
                  : _buildCurrentTabContent(),
          bottomNavigationBar: _buildBottomNav(),
          floatingActionButton: _currentBottomTab == 0
              ? FloatingActionButton.large(
                  onPressed: _openQRScanner,
                  backgroundColor: const Color(0xFFE65C00),
                  foregroundColor: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 6,
                  child: const Icon(Icons.qr_code_scanner, size: 36),
                )
              : null,
          floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              'Failed to load dashboard',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error occurred.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadInitialData,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTabContent() {
    switch (_currentBottomTab) {
      case 1:
        return _buildAnalyticsTab();
      case 2:
        return _buildProfileTab();
      case 0:
      default:
        return _buildHomeTab();
    }
  }

  // ==========================================
  // TAB 0: HOME TAB (My Library + Explore)
  // ==========================================
  Widget _buildHomeTab() {
    return Column(
      children: [
        _buildOrangeHeader(),
        _buildSubTabBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadInitialData,
            color: const Color(0xFFE65C00),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: _currentSubTab == 0 ? _buildMyLibraryContent() : _buildExploreContent(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrangeHeader() {
    final userName = _userProfile?['full_name'] ?? 'Student';
    
    // Quick unread announcements logic
    final unreadCount = _announcements.where((a) => !_readAnnouncementIds.contains(a['id'])).length;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: const Color(0xFFE65C00),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SILENCE',
                style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.2),
              ),
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none, color: Colors.white, size: 28),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => _buildNotificationsScreen()),
                      );
                    },
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          '$unreadCount',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                ],
              )
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Good afternoon, $userName 👋',
            style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'Track your attendance and manage seats effortlessly',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withOpacity(0.85)),
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _currentSubTab = 0),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'My Library',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _currentSubTab == 0 ? const Color(0xFFE65C00) : Colors.grey[600],
                      ),
                    ),
                  ),
                  Container(
                    height: 3,
                    width: 60,
                    color: _currentSubTab == 0 ? const Color(0xFFE65C00) : Colors.transparent,
                  )
                ],
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _currentSubTab = 1),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Explore',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _currentSubTab == 1 ? const Color(0xFFE65C00) : Colors.grey[600],
                      ),
                    ),
                  ),
                  Container(
                    height: 3,
                    width: 60,
                    color: _currentSubTab == 1 ? const Color(0xFFE65C00) : Colors.transparent,
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // MY LIBRARY VIEW
  Widget _buildMyLibraryContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Conditionally show profile incomplete card
        if (_isProfileIncomplete()) _buildProfileSetupCard(),
        
        // 2. Today's Attendance Ticking Card
        _buildTodayAttendanceCard(),
        const SizedBox(height: 16),

        // 3. Membership cards
        Text(
          'My Memberships',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 10),

        if (_myMemberships.isEmpty) 
          _buildNoLibraryState()
        else
          ..._myMemberships.map((m) => _buildMembershipCard(m)),

        const SizedBox(height: 16),

        // 4. Announcements
        if (_announcements.isNotEmpty) ...[
          Text(
            'Announcements',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 10),
          _buildAnnouncementsSection(),
        ],
        const SizedBox(height: 80), // extra padding for large FAB
      ],
    );
  }

  Widget _buildProfileSetupCard() {
    final hasName = _userProfile?['full_name'] != null && (_userProfile!['full_name'] as String).isNotEmpty;
    final hasPhone = _userProfile?['phone'] != null && (_userProfile!['phone'] as String).isNotEmpty;
    final hasPhoto = _userProfile?['photo_url'] != null && (_userProfile!['photo_url'] as String).isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: const Border(
          left: BorderSide(color: Color(0xFFE65C00), width: 4),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Complete Your Profile',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 4),
          Text(
            'Ensure full access to scanner and layout requests.',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          // Step 1: Complete details
          _buildProfileStepRow(
            title: 'Complete details (Name, Phone)',
            isDone: hasName && hasPhone,
          ),
          const SizedBox(height: 12),
          // Step 2: Upload ID proof
          _buildProfileStepRow(
            title: 'Upload ID proof & profile picture',
            isDone: hasPhoto,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _currentBottomTab = 2; // Jump to Profile
                });
              },
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Complete Now'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE65C00),
                textStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildProfileStepRow({required String title, required bool isDone}) {
    return Row(
      children: [
        Icon(
          isDone ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isDone ? const Color(0xFF22C55E) : Colors.grey[400],
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 13, 
              fontWeight: isDone ? FontWeight.w500 : FontWeight.normal,
              color: isDone ? const Color(0xFF1E293B) : Colors.grey[600],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTodayAttendanceCard() {
    final checkedIn = _activeAttendance != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: checkedIn ? const Color(0xFFDCFCE7) : Colors.white, // Green tint if checked-in
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Today's Attendance",
            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 12),
          if (checkedIn) ...[
            Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Checked In • ${_formatTimeString(_activeAttendance!['check_in_time'])}',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF15803D)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Session Time: $_liveSessionDuration',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFF166534), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openQRScanner,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Scan to Check Out'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                const Icon(Icons.location_off, color: Colors.grey, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Not checked in yet',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Scan your library QR to check in.',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openQRScanner,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Scan to Check In'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildNoLibraryState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          Icon(Icons.library_books, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Join a library to start',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
          ),
          const SizedBox(height: 8),
          Text(
            'Find your nearest study zone in explore or use a code.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => setState(() => _currentSubTab = 1),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65C00),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Find a Library →'),
          ),
        ],
      ),
    );
  }

  Widget _buildMembershipCard(Map<String, dynamic> membership) {
    final status = membership['status'] as String? ?? 'pending';
    final library = membership['libraries'] as Map<String, dynamic>? ?? {};
    final shift = membership['shifts'] as Map<String, dynamic>? ?? {};
    final seat = membership['seats'] as Map<String, dynamic>? ?? {};
    
    // Left border color-coding
    Color borderColor;
    String statusLabel;
    
    // Check custom expiry logic for active
    DateTime? endDate;
    if (membership['end_date'] != null) {
      endDate = DateTime.parse(membership['end_date']);
    }
    final remainingDays = endDate != null ? endDate.difference(DateTime.now()).inDays : -1;

    if (status == 'active' && remainingDays <= 7 && remainingDays >= 0) {
      borderColor = const Color(0xFFF59E0B); // expiring (amber)
      statusLabel = 'Expiring Soon';
    } else {
      switch (status) {
        case 'active':
          borderColor = const Color(0xFF22C55E); // green
          statusLabel = 'Active';
          break;
        case 'expired':
          borderColor = const Color(0xFFEF4444); // red
          statusLabel = 'Expired';
          break;
        case 'hold':
          borderColor = const Color(0xFFD97706); // orange-amber
          statusLabel = 'Hold';
          break;
        case 'trial':
          borderColor = const Color(0xFF7C3AED); // purple
          statusLabel = 'Trial';
          break;
        case 'pending':
        default:
          borderColor = const Color(0xFF9CA3AF); // gray
          statusLabel = 'Pending';
          break;
      }
    }

    final isVerified = library['verified'] == true;
    final totalSeats = seat.isNotEmpty ? 1 : 0;
    
    // Progress calculation
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

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: borderColor, width: 4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      library['name'] ?? 'SILENCE Zone',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
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
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: borderColor),
                ),
              )
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.event_seat, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                seat.isNotEmpty ? (seat['seat_label'] ?? 'G-A-01') : 'Seat Pending',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFE65C00)),
              ),
              const SizedBox(width: 24),
              const Icon(Icons.wb_sunny_outlined, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                shift.isNotEmpty ? (shift['name'] ?? 'Morning') : 'Shift Pending',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[700]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.receipt_long, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                '${membership['plan_type'] == 'monthly' ? 'Monthly' : membership['plan_type'] == '3_month' ? '3-Month' : '6-Month'} Plan',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(width: 24),
              Text(
                '₹${shift.isNotEmpty ? (membership['plan_type'] == 'monthly' ? (shift['price_monthly'] ?? 0) : membership['plan_type'] == '3_month' ? (shift['price_3month'] ?? 0) : (shift['price_6month'] ?? 0)) : 0}',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
            ],
          ),
          
          // Expiry bar
          if (endDate != null && status != 'pending') ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey[200],
                color: borderColor,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Expires: ${DateFormat('dd MMM yyyy').format(endDate)}',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                ),
                Text(
                  remainingDays > 0 ? '$remainingDays days left' : remainingDays == 0 ? 'Expires today' : 'Expired',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: remainingDays <= 7 ? Colors.redAccent : Colors.grey[600]),
                ),
              ],
            ),
          ],
          
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    // Navigate to Join Flow to renew
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => JoinFlowScreen(
                          libraryId: library['id'],
                          initialShiftId: shift['id'],
                        ),
                      ),
                    ).then((_) => _loadInitialData());
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: const BorderSide(color: Color(0xFFE65C00)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Renew Plan', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openSeatChangeSheet(membership),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: const BorderSide(color: Color(0xFFE65C00)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Seat Chg', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: const Icon(Icons.more_horiz, color: Colors.grey, size: 20),
                  onPressed: () => _openMembershipMoreOptions(membership),
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildAnnouncementsSection() {
    return Column(
      children: _announcements.map((announce) {
        final isUnread = !_readAnnouncementIds.contains(announce['id']);
        final libraryName = announce['libraries']?['name'] ?? 'Library';
        final sentAtStr = announce['sent_at'] as String?;
        String sentTime = 'Just now';
        if (sentAtStr != null) {
          final dt = DateTime.parse(sentAtStr).toLocal();
          final diff = DateTime.now().difference(dt);
          if (diff.inHours < 1) {
            sentTime = '${diff.inMinutes} mins ago';
          } else if (diff.inDays < 1) {
            sentTime = '${diff.inHours} hours ago';
          } else {
            sentTime = DateFormat('dd MMM').format(dt);
          }
        }

        return InkWell(
          onTap: () => _viewAnnouncement(announce),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(
                  color: isUnread ? const Color(0xFFE65C00) : Colors.grey[350]!, 
                  width: 4
                )
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      libraryName,
                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                    ),
                    Text(
                      sentTime,
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                    )
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  announce['title'] ?? 'Notice',
                  style: GoogleFonts.inter(
                    fontSize: 13, 
                    fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                    color: const Color(0xFF1E293B)
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  announce['message'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ==========================================
  // EXPLORE TAB (S060-B)
  // ==========================================
  Widget _buildExploreContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Search Bar
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4)),
            ],
          ),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search library, city or code...',
              hintStyle: GoogleFonts.inter(color: Colors.grey[400], fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 2. Join with Code button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openJoinWithCodeSheet,
            icon: const Icon(Icons.vpn_key_outlined, size: 18),
            label: const Text('Join with Code'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: const BorderSide(color: Color(0xFFE65C00), width: 1.5),
              foregroundColor: const Color(0xFFE65C00),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 20),

        Text(
          'Available Libraries',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 12),

        if (_filteredLibraries.isEmpty)
          _buildEmptyExploreState()
        else
          ..._filteredLibraries.map((lib) => _buildExploreLibraryCard(lib)),

        const SizedBox(height: 24),
        _buildLibrarySuggestForm(),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildEmptyExploreState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No libraries found',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different name or use a library code.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildExploreLibraryCard(Map<String, dynamic> lib) {
    final name = lib['name'] ?? 'SILENCE Zone';
    final city = lib['address_city'] ?? 'Indore';
    final verified = lib['verified'] == true;
    final photos = lib['photos'] as List? ?? [];
    final amenities = lib['amenities'] as List? ?? [];
    final shifts = lib['shifts'] as List? ?? [];

    // Calculate starting price
    int startingPrice = 0;
    for (var s in shifts) {
      final p = s['price_monthly'] as int? ?? 999999;
      if (startingPrice == 0 || p < startingPrice) {
        startingPrice = p;
      }
    }

    final hasTrial = shifts.any((s) => (s['trial_days'] as int? ?? 0) > 0);
    
    // Check if user is already a member
    final isAlreadyMember = _myMemberships.any((m) => m['library_id'] == lib['id'] && m['status'] != 'exited');

    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () => _openLibraryDetailModal(lib),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image area
            ClipRRect(
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
              child: photos.isNotEmpty
                  ? Image.network(
                      photos.first,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _buildPlaceholderPhoto(),
                    )
                  : _buildPlaceholderPhoto(),
            ),
            
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                      ),
                      if (verified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, color: Colors.blue, size: 16),
                      ]
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    city,
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),

                  // Shift pills
                  if (shifts.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: shifts.take(3).map((s) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20)),
                        child: Text(s['name'] ?? 'Shift', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[700])),
                      )).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Price
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        startingPrice > 0 ? 'From ₹$startingPrice/month' : 'Price TBA',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                      ),
                      if (hasTrial)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.purple[50], borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.purple[200]!)),
                          child: Text('🆓 Free Trial', style: GoogleFonts.inter(fontSize: 10, color: Colors.purple[700], fontWeight: FontWeight.bold)),
                        )
                    ],
                  ),

                  // Amenity Icons
                  if (amenities.isNotEmpty) ...[
                    const Divider(height: 24),
                    Row(
                      children: amenities.take(4).map((a) {
                        IconData icon;
                        switch (a.toString().toLowerCase()) {
                          case 'ac':
                          case 'air conditioning':
                            icon = Icons.ac_unit;
                            break;
                          case 'wifi':
                          case 'internet':
                            icon = Icons.wifi;
                            break;
                          case 'lockers':
                          case 'locker':
                            icon = Icons.lock_outline;
                            break;
                          case 'cctv':
                            icon = Icons.videocam_outlined;
                            break;
                          default:
                            icon = Icons.done;
                        }
                        return Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Icon(icon, size: 16, color: Colors.grey[500]),
                        );
                      }).toList(),
                    )
                  ],

                  const SizedBox(height: 16),
                  
                  // Action button
                  SizedBox(
                    width: double.infinity,
                    child: isAlreadyMember
                        ? OutlinedButton(
                            onPressed: null,
                            style: OutlinedButton.styleFrom(
                              disabledForegroundColor: Colors.grey,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Already a Member ✓'),
                          )
                        : ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => JoinFlowScreen(libraryId: lib['id'])),
                              ).then((_) => _loadInitialData());
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE65C00),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Apply to Join →'),
                          ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderPhoto() {
    return Container(
      height: 140,
      width: double.infinity,
      color: Colors.orange[50],
      child: const Icon(Icons.image, size: 48, color: Color(0xFFE65C00)),
    );
  }

  Widget _buildLibrarySuggestForm() {
    final nameCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    final ownerCtrl = TextEditingController();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Don't see your library?",
            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 4),
          Text(
            "Suggest a library you want us to add.",
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Library Name *'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: locCtrl,
            decoration: const InputDecoration(labelText: 'Location / City *'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: ownerCtrl,
            decoration: const InputDecoration(labelText: 'Owner Phone (optional)'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.isEmpty || locCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all required fields.')),
                  );
                  return;
                }
                // Mock submit
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Suggestion submitted! Thank you. ✓')),
                );
                nameCtrl.clear();
                locCtrl.clear();
                ownerCtrl.clear();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Submit Suggestion'),
            ),
          )
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: ANALYTICS TAB (S063 Placeholder)
  // ==========================================
  Widget _buildAnalyticsTab() {
    return Column(
      children: [
        // Premium Header
        Container(
          width: double.infinity,
          color: const Color(0xFFE65C00),
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text(
              'Analytics',
              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ),
        
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Summary grid cards
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  childAspectRatio: 1.4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: [
                    _buildStatCard('Days Present', '12', '↑ +12%', const Color(0xFF22C55E)),
                    _buildStatCard('Days Absent', '3', '↓ -8%', const Color(0xFFEF4444)),
                    _buildStatCard('Total Study Hours', '48h', '↑ +5h', const Color(0xFFE65C00)),
                    _buildStatCard('Attendance Rate', '80%', '↑ +3%', const Color(0xFF22C55E)),
                  ],
                ),
                const SizedBox(height: 16),

                // Streak card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65C00),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 36)),
                      const SizedBox(height: 8),
                      Text(
                        '12',
                        style: GoogleFonts.outfit(fontSize: 48, fontWeight: FontWeight.w800, color: Colors.white, height: 1),
                      ),
                      Text(
                        'Day Streak',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Best: 28 days',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withOpacity(0.8)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Badges placeholder
                Container(
                  padding: const EdgeInsets.all(16),
                  width: double.infinity,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Earned Badges', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildBadgeWidget('🔥', '7d Streak', true),
                          _buildBadgeWidget('💯', '30d Streak', true),
                          _buildBadgeWidget('⏰', 'Early Bird', true),
                          _buildBadgeWidget('🦉', 'Night Owl', false),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Chart Placeholder
                Container(
                  padding: const EdgeInsets.all(16),
                  width: double.infinity,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Study Hours Chart', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      Container(
                        height: 120,
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _buildChartBar(30, 'Mon'),
                            _buildChartBar(60, 'Tue'),
                            _buildChartBar(45, 'Wed'),
                            _buildChartBar(80, 'Thu'),
                            _buildChartBar(50, 'Fri'),
                            _buildChartBar(90, 'Sat', isToday: true),
                            _buildChartBar(10, 'Sun'),
                          ],
                        ),
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildStatCard(String title, String val, String trend, Color trendColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
          const SizedBox(height: 4),
          Text(val, style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
          const SizedBox(height: 4),
          Text(trend, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: trendColor)),
        ],
      ),
    );
  }

  Widget _buildBadgeWidget(String emoji, String name, bool earned) {
    return Opacity(
      opacity: earned ? 1.0 : 0.35,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: earned ? const Color(0xFFFFF3ED) : Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(height: 4),
          Text(name, style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[700])),
        ],
      ),
    );
  }

  Widget _buildChartBar(double heightPct, String label, {bool isToday = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          height: heightPct,
          width: 14,
          decoration: BoxDecoration(
            color: isToday ? const Color(0xFF0F172A) : const Color(0xFFE65C00),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: GoogleFonts.inter(fontSize: 9, color: Colors.grey[500])),
      ],
    );
  }

  // ==========================================
  // TAB 2: PROFILE TAB (S064 Placeholder)
  // ==========================================
  Widget _buildProfileTab() {
    final name = _userProfile?['full_name'] ?? 'Rahul Sharma';
    final email = _userProfile?['email'] ?? '';
    final phone = _userProfile?['phone'] ?? 'Enter Phone Number';
    final nickname = _userProfile?['nickname'] ?? 'N/A';
    final photoUrl = _userProfile?['photo_url'] as String?;

    return Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          color: const Color(0xFFE65C00),
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text(
              'Profile',
              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ),
        
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Profile Header Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE65C00), width: 3),
                        ),
                        child: CircleAvatar(
                          backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                          backgroundColor: Colors.orange[50],
                          child: photoUrl == null ? const Icon(Icons.person, size: 40, color: Color(0xFFE65C00)) : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                      ),
                      if (nickname != 'N/A') ...[
                        const SizedBox(height: 2),
                        Text(
                          '@$nickname',
                          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500]),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _openEditProfileModal,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text('Edit Profile'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Account items
                Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      _buildProfileItem(Icons.phone, 'Phone', phone),
                      const Divider(height: 1, indent: 56),
                      _buildProfileItem(Icons.email, 'Email', email),
                      const Divider(height: 1, indent: 56),
                      _buildProfileItem(Icons.badge, 'Referral Monospace', 'REF-A3K9-7XP'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Logout
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await Supabase.instance.client.auth.signOut();
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(context, '/login');
                      }
                    },
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Logout'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[50],
                      foregroundColor: Colors.redAccent,
                      elevation: 0,
                      side: BorderSide(color: Colors.red[100]!),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildProfileItem(IconData icon, String title, String val) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFFE65C00)),
      title: Text(title, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500])),
      subtitle: Text(val, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
    );
  }

  // ==========================================
  // SHARED BOTTOM NAV & TRIGGERS
  // ==========================================
  Widget _buildBottomNav() {
    return BottomAppBar(
      color: Colors.white,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8.0,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      height: 64,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, Icons.home, 'Home'),
          _buildNavItem(1, Icons.bar_chart, 'Analytics'),
          const SizedBox(width: 40), // Space for floating button
          _buildNavItem(2, Icons.person, 'Profile'),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final selected = _currentBottomTab == index;
    return InkWell(
      onTap: () => setState(() => _currentBottomTab = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: selected ? const Color(0xFFE65C00) : Colors.grey[500]),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11, 
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? const Color(0xFFE65C00) : Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  // Helper formatting methods
  String _formatTimeString(String isoString) {
    final dt = DateTime.parse(isoString).toLocal();
    return DateFormat('hh:mm a').format(dt);
  }

  // ==========================================
  // SCANNER & ACTIONS INTEGRATIONS
  // ==========================================
  void _openQRScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    ).then((_) => _loadInitialData());
  }

  // ==========================================
  // BOTTOM SHEETS IMPLEMENTATIONS (Milestone 4 Specs)
  // ==========================================
  void _openSeatChangeSheet(Map<String, dynamic> membership) {
    final library = membership['libraries'] as Map<String, dynamic>? ?? {};
    final seat = membership['seats'] as Map<String, dynamic>? ?? {};
    final reasonCtrl = TextEditingController();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 20, right: 20, top: 20
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Request Seat Change', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              Text(
                library['name'] ?? 'SILENCE Study Zone',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
              ),
              const Divider(height: 24),
              
              Text('Current Seat', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(20)),
                child: Text(
                  seat.isNotEmpty ? (seat['seat_label'] ?? 'G-A-12') : 'Pending',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue[700]),
                ),
              ),
              const SizedBox(height: 16),
              
              Text('Reason *', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(height: 6),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                maxLength: 200,
                decoration: const InputDecoration(
                  hintText: 'e.g. Current seat has poor lighting or broken chair...',
                ),
              ),
              const SizedBox(height: 16),
              
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFFE65C00), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Admin will assign the best available seat based on availability.',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.orange[800]),
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (reasonCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a reason.')),
                          );
                          return;
                        }
                        
                        try {
                          final supabase = Supabase.instance.client;
                          await supabase.from('seat_change_requests').insert({
                            'membership_id': membership['id'],
                            'member_id': membership['member_id'],
                            'library_id': library['id'],
                            'current_seat_id': seat['id'],
                            'reason': reasonCtrl.text.trim(),
                            'status': 'pending',
                          });
                          
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Seat change request submitted! ✓')),
                            );
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to submit: $e')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65C00),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Submit →'),
                    ),
                  )
                ],
              )
            ],
          ),
        );
      },
    );
  }

  void _openMembershipMoreOptions(Map<String, dynamic> membership) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.pause_circle_outline, color: Color(0xFFD97706)),
                title: Text('Request Hold / Pause', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _openHoldRequestSheet(membership);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.redAccent),
                title: Text('Exit Library', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  _openExitLibrarySheetFlow(membership);
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Cancel'),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  void _openHoldRequestSheet(Map<String, dynamic> membership) {
    final library = membership['libraries'] as Map<String, dynamic>? ?? {};
    final reasonCtrl = TextEditingController();
    
    DateTime holdStart = DateTime.now().add(const Duration(days: 1)); // min tomorrow
    DateTime holdEnd = holdStart.add(const Duration(days: 7)); // default 7 days

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                left: 20, right: 20, top: 20
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Pause Membership', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  Text(
                    library['name'] ?? 'SILENCE Study Zone',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const Divider(height: 24),
                  
                  Text('Reason *', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500])),
                  const SizedBox(height: 6),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(hintText: 'e.g. Preparing for examinations at home...'),
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Start Date *', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: holdStart,
                                  firstDate: DateTime.now().add(const Duration(days: 1)),
                                  lastDate: DateTime.now().add(const Duration(days: 30)),
                                );
                                if (picked != null) {
                                  setSheetState(() {
                                    holdStart = picked;
                                    if (holdEnd.isBefore(holdStart)) {
                                      holdEnd = holdStart.add(const Duration(days: 7));
                                    }
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(DateFormat('dd MMM yyyy').format(holdStart), style: GoogleFonts.inter(fontSize: 13)),
                                    const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                                  ],
                                ),
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('End Date *', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: holdEnd,
                                  firstDate: holdStart.add(const Duration(days: 1)),
                                  lastDate: holdStart.add(const Duration(days: 30)),
                                );
                                if (picked != null) {
                                  setSheetState(() {
                                    holdEnd = picked;
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(DateFormat('dd MMM yyyy').format(holdEnd), style: GoogleFonts.inter(fontSize: 13)),
                                    const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                                  ],
                                ),
                              ),
                            )
                          ],
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFBF5EE), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE65C00).withOpacity(0.3))),
                    child: Column(
                      children: [
                        _buildHoldBullet('Seat stays reserved for you'),
                        const SizedBox(height: 6),
                        _buildHoldBullet('Billing parses and extends after pause'),
                        const SizedBox(height: 6),
                        _buildHoldBullet('Expiry extends automatically by pause length'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            if (reasonCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please provide a reason.')),
                              );
                              return;
                            }
                            
                            try {
                              final supabase = Supabase.instance.client;
                              await supabase.from('hold_requests').insert({
                                'membership_id': membership['id'],
                                'member_id': membership['member_id'],
                                'library_id': library['id'],
                                'start_date': DateFormat('yyyy-MM-dd').format(holdStart),
                                'end_date': DateFormat('yyyy-MM-dd').format(holdEnd),
                                'reason': reasonCtrl.text.trim(),
                                'status': 'pending',
                              });
                              
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Hold Request submitted! ✓')),
                                );
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE65C00),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Submit →'),
                        ),
                      )
                    ],
                  )
                ],
              ),
            );
          }
        );
      },
    );
  }

  Widget _buildHoldBullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check, size: 16, color: Color(0xFF22C55E)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[700]))),
      ],
    );
  }

  void _openExitLibrarySheetFlow(Map<String, dynamic> membership) {
    final library = membership['libraries'] as Map<String, dynamic>? ?? {};
    final seat = membership['seats'] as Map<String, dynamic>? ?? {};
    
    // 1. Dues checking (mock check, but can be real if payments exist)
    // For safety, let's pretend dues = 0, but if there's any dues, we block.
    const int dues = 0; 
    
    if (dues > 0) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
        builder: (context) {
          return Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('⚠️ Cannot Exit', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                const Divider(height: 24),
                Text(
                  'You have ₹$dues in pending dues at ${library['name'] ?? 'SILENCE Study Zone'}.',
                  style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF1E293B)),
                ),
                const SizedBox(height: 12),
                Text(
                  'Please clear all dues before exiting, or contact your library admin.',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          // Contact admin/queries
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Contact details: Jaipur, Rajasthan')),
                          );
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                        child: const Text('Contact Library'),
                      ),
                    )
                  ],
                )
              ],
            ),
          );
        },
      );
      return;
    }

    // Step 1 warning
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Exit Library?', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(
                library['name'] ?? 'SILENCE Study Zone',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
              ),
              const Divider(height: 24),
              
              Text('This will:', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[700])),
              const SizedBox(height: 12),
              _buildBulletRow(false, 'Free your seat ${seat['seat_label'] ?? 'G-A-12'} immediately'),
              const SizedBox(height: 8),
              _buildBulletRow(false, 'End your membership subscription'),
              const SizedBox(height: 8),
              _buildBulletRow(false, 'Lose any remaining plan days'),
              const SizedBox(height: 8),
              _buildBulletRow(true, 'Your attendance history remains preserved'),
              const SizedBox(height: 8),
              _buildBulletRow(true, 'All earned badges will be kept in your profile'),
              
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        // Trigger final confirm after 500ms
                        Future.delayed(const Duration(milliseconds: 500), () {
                          _openExitLibraryFinalConfirmSheet(membership);
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Yes, Exit →'),
                    ),
                  )
                ],
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildBulletRow(bool isPositive, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isPositive ? Icons.check : Icons.close,
          color: isPositive ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[700]),
          ),
        )
      ],
    );
  }

  void _openExitLibraryFinalConfirmSheet(Map<String, dynamic> membership) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.red[50], // Red tint as per specs S069
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text(
                '⚠️ Final Confirmation',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent),
              ),
              const SizedBox(height: 12),
              Text(
                'This cannot be undone. Your seat will be freed immediately and you will no longer be an active member of this library.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red[900]),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Colors.redAccent),
                        foregroundColor: Colors.redAccent,
                      ),
                      child: const Text('← Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          final supabase = Supabase.instance.client;
                          // 1. Free the seat if assigned
                          final seatId = membership['seat_id'];
                          if (seatId != null) {
                            await supabase.from('seats').update({
                              'status': 'vacant',
                              'occupied_by_member_id': null,
                            }).eq('id', seatId);
                          }
                          
                          // 2. Mark membership as exited
                          await supabase.from('memberships').update({
                            'status': 'exited',
                            'exited_at': DateTime.now().toIso8601String(),
                          }).eq('id', membership['id']);
                          
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Successfully exited library. ✓')),
                            );
                            _loadInitialData();
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Confirm Exit'),
                    ),
                  )
                ],
              )
            ],
          ),
        );
      },
    );
  }

  void _viewAnnouncement(Map<String, dynamic> announce) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                announce['title'] ?? 'Notice',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 4),
              Text(
                announce['libraries']?['name'] ?? 'Library notice',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFE65C00), fontWeight: FontWeight.bold),
              ),
              const Divider(height: 24),
              Text(
                announce['message'] ?? '',
                style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[800], height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    
                    // Mark as read in Supabase
                    final supabase = Supabase.instance.client;
                    final currentUser = supabase.auth.currentUser;
                    if (currentUser != null) {
                      try {
                        await supabase.from('announcement_reads').upsert({
                          'announcement_id': announce['id'],
                          'member_id': currentUser.id,
                          'read_at': DateTime.now().toIso8601String(),
                        });
                        
                        setState(() {
                          _readAnnouncementIds.add(announce['id']);
                        });
                      } catch (e) {
                        debugPrint('Error marking read: $e');
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                  child: const Text('Close'),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  void _openJoinWithCodeSheet() {
    final codeCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 20, right: 20, top: 20
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Join with Library Code', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 16),
              
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                onChanged: (val) {
                  // Format code automatically with hyphens e.g. SIL-XXXXXX
                  String clean = val.replaceAll('-', '').toUpperCase();
                  if (clean.length > 3) {
                    clean = '${clean.substring(0, 3)}-${clean.substring(3)}';
                  }
                  if (clean.length > 10) {
                    clean = '${clean.substring(0, 10)}-${clean.substring(10)}';
                  }
                  codeCtrl.value = TextEditingValue(
                    text: clean,
                    selection: TextSelection.fromPosition(TextPosition(offset: clean.length)),
                  );
                },
                decoration: const InputDecoration(
                  labelText: 'Library Code',
                  hintText: 'e.g. SIL-4K9M-2P',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final code = codeCtrl.text.trim();
                    if (code.isEmpty) return;
                    
                    try {
                      final supabase = Supabase.instance.client;
                      final libRes = await supabase
                          .from('libraries')
                          .select()
                          .eq('library_code', code)
                          .maybeSingle();
                      
                      if (libRes == null) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Library not found. Check code prefix or suffix.')),
                          );
                        }
                        return;
                      }
                      
                      if (context.mounted) {
                        Navigator.pop(context);
                        // Open Join flow for this library
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => JoinFlowScreen(libraryId: libRes['id'])),
                        ).then((_) => _loadInitialData());
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error finding library: $e')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Find Library'),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  void _openLibraryDetailModal(Map<String, dynamic> lib) {
    final name = lib['name'] ?? 'SILENCE Study Zone';
    final about = lib['about_text'] ?? 'No description available.';
    final rules = lib['rules'] ?? 'No rules configured.';
    final emergency = lib['emergency_phone'] ?? '9876543210';
    final verified = lib['verified'] == true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(name, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
                      if (verified) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.verified, color: Colors.blue, size: 18),
                      ]
                    ],
                  ),
                  const Divider(height: 24),
                  
                  Text('About Library', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                  const SizedBox(height: 6),
                  Text(about, style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: Colors.grey[750])),
                  const SizedBox(height: 16),
                  
                  Text('Library Rules', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                  const SizedBox(height: 6),
                  Text(rules, style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: Colors.grey[750])),
                  const SizedBox(height: 20),
                  
                  // Contact row
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Emergency Contact', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                            Text(emergency, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.phone, color: Color(0xFF22C55E)),
                          onPressed: () {
                            // Dial number tel:emergency
                            // For security / compile safety without url_launcher, use normal logging or just copy to clipboard
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Dialing: $emergency')),
                            );
                          },
                        )
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => JoinFlowScreen(libraryId: lib['id'])),
                        ).then((_) => _loadInitialData());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65C00),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Apply to Join Library →'),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openEditProfileModal() {
    final nameCtrl = TextEditingController(text: _userProfile?['full_name']);
    final nickCtrl = TextEditingController(text: _userProfile?['nickname']);
    final phoneCtrl = TextEditingController(text: _userProfile?['phone']);
    final photoCtrl = TextEditingController(text: _userProfile?['photo_url']);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 20, right: 20, top: 20
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Complete Profile Details', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 12),
              
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Full Name *'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nickCtrl,
                decoration: const InputDecoration(labelText: 'Nickname (for leaderboard)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone Number (+91) *'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: photoCtrl,
                decoration: const InputDecoration(labelText: 'ID Proof Photo URL *'),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.isEmpty || phoneCtrl.text.isEmpty || photoCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please fill all required fields.')),
                      );
                      return;
                    }
                    
                    try {
                      final supabase = Supabase.instance.client;
                      await supabase.from('users').update({
                        'full_name': nameCtrl.text.trim(),
                        'nickname': nickCtrl.text.trim(),
                        'phone': phoneCtrl.text.trim(),
                        'photo_url': photoCtrl.text.trim(),
                        'updated_at': DateTime.now().toIso8601String(),
                      }).eq('id', _userProfile!['id']);
                      
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Profile updated successfully! ✓')),
                        );
                        _loadInitialData();
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to update: $e')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Save Details'),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildNotificationsScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFFE65C00),
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: const Color(0xFFFBF5EE),
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            foregroundColor: Colors.white,
            title: Text('Notifications', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  "You're all caught up!",
                  style: GoogleFonts.outfit(fontSize: 16, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
