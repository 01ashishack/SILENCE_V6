import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../core/admin_settings_service.dart';

class VerifiedBadgeScreen extends StatefulWidget {
  final String? libraryId;
  const VerifiedBadgeScreen({super.key, this.libraryId});

  @override
  State<VerifiedBadgeScreen> createState() => _VerifiedBadgeScreenState();
}

class _VerifiedBadgeScreenState extends State<VerifiedBadgeScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _libId;

  // Criteria status state variables
  bool _setupComplete = false;
  int _floorsCount = 0;
  int _sectionsCount = 0;
  int _seatsCount = 0;
  int _shiftsCount = 0;

  bool _active30Days = false;
  int _operatingDays = 0;

  bool _adminPremium = false;
  String _subPlan = 'none';

  bool _has10Members = false;
  int _activeMembersCount = 0;

  bool _has50Checkins = false;
  int _checkinsCount = 0;

  bool _profileComplete = false;
  bool _hasName = false;
  bool _hasPhone = false;
  bool _hasGender = false;
  bool _hasDOB = false;
  bool _hasPhoto = false;

  bool _isClaiming = false;
  bool _isAlreadyVerified = false;
  DateTime? _verifiedAt;

  @override
  void initState() {
    super.initState();
    _libId = widget.libraryId;
    _checkEligibility();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_libId == null) {
      final Object? args = ModalRoute.of(context)?.settings.arguments;
      if (args is String) {
        _libId = args;
      }
    }
  }

  Future<void> _checkEligibility() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      if (_libId == null) {
        _libId = await AdminSettingsService.firstOwnedLibraryId();
        if (!mounted) return;
      }

      if (_libId == null) {
        setState(() => _isLoading = false);
        return;
      }

      final String currentLibId = _libId!;

      // 1. Fetch library info
      final libRes = await _supabase.from('libraries').select().eq('id', currentLibId).maybeSingle();
      if (libRes != null) {
        _isAlreadyVerified = libRes['verified'] ?? false;
        if (libRes['verified_at'] != null) {
          _verifiedAt = DateTime.tryParse(libRes['verified_at'].toString());
        }

        // Calculate operational history days
        if (libRes['created_at'] != null) {
          final created = DateTime.tryParse(libRes['created_at'].toString());
          if (created != null) {
            _operatingDays = DateTime.now().difference(created).inDays;
            _active30Days = _operatingDays >= 30;
          }
        }
      }

      // 2. Setup complete: floors, sections, seats, shifts
      final floorsRes = await _supabase.from('floors').select('id').eq('library_id', currentLibId);
      _floorsCount = floorsRes.length;

      // Fetch sections under those floors
      if (_floorsCount > 0) {
        final floorIds = List<String>.from(floorsRes.map((f) => f['id'].toString()));
        final sectionsRes = await _supabase.from('sections').select('id').inFilter('floor_id', floorIds);
        _sectionsCount = sectionsRes.length;
      } else {
        _sectionsCount = 0;
      }

      final seatsRes = await _supabase.from('seats').select('id').eq('library_id', currentLibId);
      _seatsCount = seatsRes.length;

      final shiftsRes = await _supabase.from('shifts').select('id').eq('library_id', currentLibId).eq('is_archived', false);
      _shiftsCount = shiftsRes.length;

      _setupComplete = _floorsCount > 0 && _sectionsCount > 0 && _seatsCount > 0 && _shiftsCount > 0;

      // 3. Admin user profile details
      final userRes = await _supabase.from('users').select().eq('id', user.id).maybeSingle();
      if (userRes != null) {
        _hasName = userRes['full_name'] != null && userRes['full_name'].toString().trim().isNotEmpty;
        _hasPhone = userRes['phone'] != null && userRes['phone'].toString().trim().isNotEmpty;
        _hasGender = userRes['gender'] != null && userRes['gender'].toString().trim().isNotEmpty;
        _hasDOB = userRes['date_of_birth'] != null && userRes['date_of_birth'].toString().trim().isNotEmpty;
        _hasPhoto = userRes['photo_url'] != null && userRes['photo_url'].toString().trim().isNotEmpty;
        _profileComplete = _hasName && _hasPhone && _hasGender && _hasDOB && _hasPhoto;

        // Admin Premium Plan status
        final plan = userRes['subscription_plan']?.toString() ?? 'none';
        final status = userRes['subscription_status']?.toString() ?? 'trial';
        _subPlan = plan;
        _adminPremium = plan != 'none' && status == 'active';
      }

      // 4. Members with active memberships >= 10
      final membershipsRes = await _supabase.from('memberships').select('id').eq('library_id', currentLibId).eq('status', 'active');
      _activeMembersCount = membershipsRes.length;
      _has10Members = _activeMembersCount >= 10;

      // 5. Total check-ins >= 50
      final attendanceRes = await _supabase.from('attendance').select('id').eq('library_id', currentLibId);
      _checkinsCount = attendanceRes.length;
      _has50Checkins = _checkinsCount >= 50;

    } catch (e) {
      debugPrint('Error checking eligibility: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _claimVerifiedBadge() async {
    final String? currentLibId = _libId;
    if (currentLibId == null) return;

    setState(() => _isClaiming = true);
    try {
      // Server re-checks eligibility + sets verified (the column is locked
      // against direct client writes — see migrations/2026-06-18_lock_library_verified.sql).
      await _supabase.rpc('claim_verified_badge', params: {'p_library': currentLibId});

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            title: Text(
              'Verified Successfully! 🎖️',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
              textAlign: TextAlign.center,
            ),
            content: Text(
              'Congratulations! Your library profile now displays the verified badge.',
              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF4B5563)),
              textAlign: TextAlign.center,
            ),
            actions: [
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx); // Close dialog
                    Navigator.pop(context, true); // Pop screen back
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), elevation: 0),
                  child: Text('Awesome', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Error claiming badge: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to claim badge: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      setState(() => _isClaiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool passesAll = _setupComplete && _active30Days && _adminPremium && _has10Members && _has50Checkins && _profileComplete;

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
              'Verified Badge Status',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Badge Hero Card
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE65C00).withValues(alpha: 0.15),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Gold/Orange badge symbol
                            Container(
                              width: 80,
                              height: 80,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFFF3ED),
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Text(
                                  '🎖️',
                                  style: TextStyle(fontSize: 44),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'SILENCE Verified Badge',
                              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isAlreadyVerified
                                  ? '✓ Your library has been verified successfully!'
                                  : 'Complete all trust building milestones below to earn your trust badge.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8), height: 1.4),
                            ),
                            if (_isAlreadyVerified && _verifiedAt != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(color: const Color(0xFF10B981)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.verified, color: Color(0xFF10B981), size: 16),
                                    const SizedBox(width: 8),
                                    Text(
                                      'VERIFIED • ${DateFormat('dd/MM/yyyy').format(_verifiedAt!)}',
                                      style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      Text(
                        'Milestones & Progress',
                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 12),

                      // 2. Criteria Checklist
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            _buildCriteriaItem(
                              title: 'Library Setup Complete',
                              subtitle: 'Floors: $_floorsCount/1, Sections: $_sectionsCount/1, Seats: $_seatsCount/1, Shifts: $_shiftsCount/1',
                              isCompleted: _setupComplete,
                              onActionTap: () => Navigator.pushNamed(context, '/admin/library/setup/1').then((_) => _checkEligibility()),
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildCriteriaItem(
                              title: '30+ Days Active Operation',
                              subtitle: 'Days active: $_operatingDays / 30',
                              isCompleted: _active30Days,
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildCriteriaItem(
                              title: 'Active Premium Subscription',
                              subtitle: _adminPremium ? 'Status: Active ($_subPlan)' : 'Status: Free Trial / Unpaid',
                              isCompleted: _adminPremium,
                              onActionTap: () => Navigator.pushNamed(context, '/admin/subscription').then((_) => _checkEligibility()),
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildCriteriaItem(
                              title: '10+ Active Memberships',
                              subtitle: 'Members: $_activeMembersCount / 10',
                              isCompleted: _has10Members,
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildCriteriaItem(
                              title: '50+ Total Check-ins Recorded',
                              subtitle: 'Check-ins logged: $_checkinsCount / 50',
                              isCompleted: _has50Checkins,
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildCriteriaItem(
                              title: 'Admin Profile 100% Complete',
                              subtitle: 'Details setup: ${_profileDetailsProgress()}',
                              isCompleted: _profileComplete,
                              onActionTap: () => Navigator.pushNamed(context, '/admin/profile/complete').then((_) => _checkEligibility()),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // 3. Action Button
                      if (_isAlreadyVerified)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          onPressed: null,
                          icon: const Icon(Icons.verified, color: Colors.white),
                          label: Text(
                            'Verification Already Granted ✓',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        )
                      else if (passesAll)
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE65C00),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          onPressed: _isClaiming ? null : _claimVerifiedBadge,
                          child: _isClaiming
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  'Claim Verified Badge 🎖️',
                                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                        )
                      else
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[400],
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          onPressed: null,
                          child: Text(
                            'Not Eligible Yet',
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

  String _profileDetailsProgress() {
    final List<String> list = [];
    if (!_hasName) list.add('Name');
    if (!_hasPhone) list.add('Phone');
    if (!_hasGender) list.add('Gender');
    if (!_hasDOB) list.add('DOB');
    if (!_hasPhoto) list.add('Photo');
    if (list.isEmpty) return '100% Done';
    return 'Missing: ${list.join(", ")}';
  }

  Widget _buildCriteriaItem({
    required String title,
    required String subtitle,
    required bool isCompleted,
    VoidCallback? onActionTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isCompleted ? const Color(0xFFFFF3ED) : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCompleted ? Icons.check : Icons.close,
              color: isCompleted ? const Color(0xFFE65C00) : const Color(0xFF94A3B8),
              size: 16,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isCompleted ? const Color(0xFF1E293B) : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          if (onActionTap != null && !isCompleted) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onActionTap,
              child: Text(
                'Fix',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
