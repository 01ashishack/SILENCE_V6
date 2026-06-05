import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MemberPrivacyPolicyScreen extends StatefulWidget {
  const MemberPrivacyPolicyScreen({super.key});

  @override
  State<MemberPrivacyPolicyScreen> createState() => _MemberPrivacyPolicyScreenState();
}

class _MemberPrivacyPolicyScreenState extends State<MemberPrivacyPolicyScreen> {
  bool _isLoading = true;
  bool _hasAcceptedLatest = true;
  String? _userId;
  final String _latestVersion = '1.0.6';

  @override
  void initState() {
    super.initState();
    _checkAcceptedVersion();
  }

  Future<void> _checkAcceptedVersion() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user != null) {
        _userId = user.id;
        final prefs = await SharedPreferences.getInstance();
        final suffix = user.id;

        // Try load from DB first
        String? dbVersion;
        try {
          final res = await supabase.from('users').select('accepted_privacy_version').eq('id', user.id).maybeSingle();
          if (res != null) {
            dbVersion = res['accepted_privacy_version'] as String?;
          }
        } catch (e) {
          debugPrint('accepted_privacy_version column query failed: $e');
        }

        final localVersion = prefs.getString('accepted_privacy_version_$suffix') ?? dbVersion;
        setState(() {
          _hasAcceptedLatest = (localVersion == _latestVersion);
        });
      }
    } catch (e) {
      debugPrint('Error checking privacy version: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _acceptPrivacy() async {
    if (_userId == null) return;
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      final suffix = _userId!;

      // Save locally
      await prefs.setString('accepted_privacy_version_$suffix', _latestVersion);

      // Save to Supabase (graceful fail)
      try {
        await supabase.from('users').update({
          'accepted_privacy_version': _latestVersion,
        }).eq('id', _userId!);
      } catch (e) {
        debugPrint('Failed to update accepted_privacy_version in DB, using local: $e');
      }

      setState(() {
        _hasAcceptedLatest = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Privacy Policy accepted successfully! ✓',
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error accepting privacy policy: $e');
    } finally {
      setState(() => _isLoading = false);
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
              'Privacy Policy',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'SILENCE Data Privacy',
                                  style: GoogleFonts.outfit(
                                      fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF3ED),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'v$_latestVersion',
                                    style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFFE65C00)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Last updated: June 5, 2026',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
                            ),
                            const SizedBox(height: 20),
                            _buildPrivacyText(),
                          ],
                        ),
                      ),
                    ),
                    if (!_hasAcceptedLatest) _buildAcceptStickyBanner(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildAcceptStickyBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Action Required',
            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
          ),
          const SizedBox(height: 4),
          Text(
            'We have updated our Privacy Policy. Please review and accept to continue using SILENCE services.',
            style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey[600], height: 1.4),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _acceptPrivacy,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65C00),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              'Accept Privacy Policy',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyText() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        '1. WHAT INFORMATION WE COLLECT\n'
        'We collect details necessary to register your membership, coordinate seat assignments, and track attendance. This includes your name, nickname, email, phone number, physical address, exam category, profile picture, and identity verification documents (e.g. Aadhaar or Voter ID thumbnails).\n\n'
        '2. HOW WE USE YOUR INFORMATION\n'
        '• To run check-in and check-out logic and compute daily study hours.\n'
        '• To manage slot allocations and process subscription renewals.\n'
        '• To send push alerts regarding slot expiry, seat changes, or library announcements.\n'
        '• To display nicknames and study streaks on the leaderboard (this can be disabled in Privacy Settings).\n\n'
        '3. DATA SECURITY & RETENTION\n'
        'Your profile details and uploaded documents are stored securely using Supabase and silence_assets storage buckets. Telemetry details (app version, OS, model) are optionally appended to issue reports to debug errors. Telemetry is never sold or shared with third parties.\n\n'
        '4. YOUR RIGHTS & CONTROL\n'
        'You have full control over your privacy options:\n'
        '• You can hide your nickname or study statistics from the leaderboard.\n'
        '• You can export your profile, membership, and attendance data into JSON via the Download My Data feature.\n'
        '• You can request account deletion. Once requested, your account is scheduled for deletion with a 30-day grace period, during which you can cancel it.\n\n'
        '5. CHANGES TO THIS POLICY\n'
        'We may update our Privacy Policy to align with new features or security requirements. We will prompt you to accept the updated policy whenever key revisions occur.',
        style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF334155), height: 1.6),
      ),
    );
  }
}

