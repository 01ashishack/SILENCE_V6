import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../legal/legal_content.dart';
import 'policy_screens.dart';

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
                              kLegalLastUpdated,
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
      child: legalSectionsColumn(context, legalTerms),
    );
  }
}

