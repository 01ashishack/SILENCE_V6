import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_info.dart';

class MemberAboutScreen extends StatelessWidget {
  const MemberAboutScreen({super.key});

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        debugPrint('Could not launch $urlString');
      }
    } catch (e) {
      debugPrint('Error launching url: $e');
    }
  }

  void _showChangelogBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "What's New in V1.0.6",
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    _buildChangelogItem(context,
                      '📱 OTP Contact Verification',
                      'Verify your phone number and email address instantly with mock OTP authentication.',
                    ),
                    _buildChangelogItem(context,
                      '🪪 ID Document Statuses',
                      'Upload document proofs (Aadhaar, Voter, etc.) and view live statuses (Under Review, Verified).',
                    ),
                    _buildChangelogItem(context,
                      '🔒 Deletion Grace Period',
                      'Safety-first 7-day scheduled deletion — account is frozen, with an owner-approved recovery window.',
                    ),
                    _buildChangelogItem(context,
                      '📊 Data Export Portability',
                      'Download your complete profile and study logs in JSON standard format directly via sharing sheets.',
                    ),
                    _buildChangelogItem(context,
                      '⚙️ Notification Quiet Hours',
                      'Customise exactly when you get notified with time-picker based Quiet Hours and daily Streak Reminders.',
                    ),
                    _buildChangelogItem(context,
                      '🐛 Performance & UI Fixes',
                      'Smoother loading skeletons, clean profile page transitions, and improved error fallbacks.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChangelogItem(BuildContext context, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600], height: 1.4),
          ),
        ],
      ),
    );
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
              'About SILENCE',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                // Logo & App Name
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE65C00), Color(0xFFC44E00)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE65C00).withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            )
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.blur_on, size: 48, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'SILENCE',
                        style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppInfo.full,
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Mission Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0x1FE65C00),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x1FE65C00)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Our Mission',
                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'To cultivate quiet, premium, and focused study spaces across the country, empowering student communities to prepare and excel in their academic, professional, and career pursuits with zero distractions.',
                        style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF7F2D0F), height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Actions Card
                Container(
                  decoration: BoxDecoration(
                    color: context.palette.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        onTap: () => _showChangelogBottomSheet(context),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: Color(0xFFEFF6FF), shape: BoxShape.circle),
                          child: const Icon(Icons.history, color: Color(0xFF3B82F6), size: 20),
                        ),
                        title: Text("What's New", style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
                        subtitle: Text('Read latest v1.0.6 release changelog notes.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                      ),
                      const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6), indent: 56),
                      ListTile(
                        onTap: () => _launchUrl('https://play.google.com/store'),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: Color(0xFFFFFBEB), shape: BoxShape.circle),
                          child: const Icon(Icons.star_outline, color: Color(0xFFF59E0B), size: 20),
                        ),
                        title: Text('Rate the App', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
                        subtitle: Text('Show your love by rating us on Play Store.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Contact Card
                _buildSectionHeader(context, 'Support & Contact'),
                Container(
                  decoration: BoxDecoration(
                    color: context.palette.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        onTap: () => _launchUrl('mailto:support@silenceapp.in'),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: Color(0xFFF3F4F6), shape: BoxShape.circle),
                          child: const Icon(Icons.alternate_email, color: Color(0xFF6B7280), size: 20),
                        ),
                        title: Text('Contact Email', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
                        subtitle: Text('support@silenceapp.in', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
                        trailing: const Icon(Icons.open_in_new, size: 14, color: Colors.grey),
                      ),
                      const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6), indent: 56),
                      ListTile(
                        onTap: () => _launchUrl('https://silenceapp.in'),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: Color(0xFFF3F4F6), shape: BoxShape.circle),
                          child: const Icon(Icons.language, color: Color(0xFF6B7280), size: 20),
                        ),
                        title: Text('Official Website', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
                        subtitle: Text('https://silenceapp.in', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
                        trailing: const Icon(Icons.open_in_new, size: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Social Handles
                _buildSectionHeader(context, 'Follow Us'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSocialButton(context: context,
                      icon: Icons.camera_alt_outlined,
                      label: 'Instagram',
                      url: 'https://instagram.com/silenceapp',
                    ),
                    _buildSocialButton(context: context,
                      icon: Icons.play_circle_outline,
                      label: 'YouTube',
                      url: 'https://youtube.com/@silenceapp',
                    ),
                    _buildSocialButton(context: context,
                      icon: Icons.tag,
                      label: 'Twitter',
                      url: 'https://twitter.com/silenceapp',
                    ),
                    _buildSocialButton(context: context,
                      icon: Icons.business_center_outlined,
                      label: 'LinkedIn',
                      url: 'https://linkedin.com/company/silenceapp',
                    ),
                  ],
                ),
                const SizedBox(height: 48),

                // Footer
                Center(
                  child: Column(
                    children: [
                      Text(
                        'Proudly crafted with Flutter, Supabase & Dart',
                        style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '© 2026 Silence Tech Labs. All rights reserved.',
                        style: GoogleFonts.inter(fontSize: 9, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: context.palette.textMuted, letterSpacing: 1),
      ),
    );
  }

  Widget _buildSocialButton({required BuildContext context, required IconData icon, required String label, required String url}) {
    return InkWell(
      onTap: () => _launchUrl(url),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 70,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFFE65C00), size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: context.palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

