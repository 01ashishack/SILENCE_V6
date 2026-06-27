import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MemberTermsScreen extends StatefulWidget {
  const MemberTermsScreen({super.key});

  @override
  State<MemberTermsScreen> createState() => _MemberTermsScreenState();
}

class _MemberTermsScreenState extends State<MemberTermsScreen> {
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
          final res = await supabase.from('users').select('accepted_terms_version').eq('id', user.id).maybeSingle();
          if (!mounted) return;
          if (res != null) {
            dbVersion = res['accepted_terms_version'] as String?;
          }
        } catch (e) {
          debugPrint('accepted_terms_version column query failed: $e');
        }

        final localVersion = prefs.getString('accepted_terms_version_$suffix') ?? dbVersion;
        setState(() {
          _hasAcceptedLatest = (localVersion == _latestVersion);
        });
      }
    } catch (e) {
      debugPrint('Error checking terms version: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _acceptTerms() async {
    if (_userId == null) return;
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      final suffix = _userId!;

      // Save locally
      await prefs.setString('accepted_terms_version_$suffix', _latestVersion);

      // Save to Supabase (graceful fail)
      try {
        await supabase.from('users').update({
          'accepted_terms_version': _latestVersion,
        }).eq('id', _userId!);
        if (!mounted) return;
      } catch (e) {
        debugPrint('Failed to update accepted_terms_version in DB, using local: $e');
      }

      setState(() {
        _hasAcceptedLatest = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Terms & Conditions accepted successfully! ✓',
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error accepting terms: $e');
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
          backgroundColor: context.palette.scaffold,
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Terms & Conditions',
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
                                  'SILENCE Usage Agreement',
                                  style: GoogleFonts.outfit(
                                      fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0x1FE65C00),
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
                            _buildTermsText(),
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
            'We have updated our terms. Please read and accept them to continue using your SILENCE membership services.',
            style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey[600], height: 1.4),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _acceptTerms,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65C00),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              'Accept Terms & Conditions',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermsText() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        '1. INTRODUCTION\n'
        'Welcome to SILENCE. These Terms & Conditions govern your use of the SILENCE mobile application and the physical library space services offered at our branches. By accessing or using our services, you agree to comply with and be bound by these terms.\n\n'
        '2. ELIGIBILITY & MEMBERSHIP\n'
        'Memberships are individual and non-transferable. You agree to provide accurate, complete information during profile setup. Sharing your account or library QR code with non-members is strictly prohibited and will result in immediate termination without refund.\n\n'
        '3. ACCESS RULES & CHECK-IN\n'
        '• Members must check in by scanning the QR code upon entry and check out when leaving.\n'
        '• Desks are assigned by the administrator or via slot booking. You may only occupy your assigned seat.\n'
        '• Silence must be maintained inside the library rooms at all times. Phone calls and group discussions should only take place in designated zones.\n\n'
        '4. SUBSCRIPTION PAYMENTS & RENEWAL\n'
        'Fees are collected in advance for the subscription cycle. Failure to renew prior to expiration will result in seat forfeiture. Payment histories and receipts can be viewed directly under the My History tab.\n\n'
        '5. REFUNDS, PAUSE & HOLD POLICY\n'
        '• All subscription plans are non-refundable.\n'
        '• Pause or hold requests are subject to approval by the administrator and must follow the guidelines detailed under My Libraries hold configuration.\n\n'
        '6. TERMINATION OF ACCESS\n'
        'SILENCE reserves the right to suspend or terminate access to any member who repeatedly violates silence guidelines, exhibits misconduct, or damages facility property.',
        style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF334155), height: 1.6),
      ),
    );
  }
}

