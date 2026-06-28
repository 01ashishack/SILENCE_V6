import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_info.dart';
import '../legal/legal_content.dart';
import '../theme/app_palette.dart';
import 'policy_screens.dart';

/// Member-side About screen. Renders the canonical [legalAbout] doc (identical
/// content to the admin About screen) with a product footer (app version,
/// changelog, and social links).
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
                    style: GoogleFonts.outfit(
                        fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _buildChangelogItem(context, '📱 Contact Verification',
                        'Verify your phone number and email address with OTP.'),
                    _buildChangelogItem(context, '🪪 Document Statuses',
                        'Upload your verification documents and view live statuses (Under Review, Verified).'),
                    _buildChangelogItem(context, '🔒 Deletion Grace Period',
                        'Safety-first scheduled deletion — your account is frozen, with a recovery window.'),
                    _buildChangelogItem(context, '📊 Data Export',
                        'Download your complete profile and study logs in JSON via the sharing sheet.'),
                    _buildChangelogItem(context, '⚙️ Notification Quiet Hours',
                        'Customise when you get notified with time-picker Quiet Hours and Streak Reminders.'),
                    _buildChangelogItem(context, '🐛 Performance & UI Fixes',
                        'Smoother loading, cleaner transitions, and improved error fallbacks.'),
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
          Text(title,
              style: GoogleFonts.outfit(
                  fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
          const SizedBox(height: 4),
          Text(description,
              style: GoogleFonts.inter(fontSize: 12, color: context.palette.textMuted, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildSocialButton(
      {required BuildContext context, required IconData icon, required String label, required String url}) {
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
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 9, fontWeight: FontWeight.bold, color: context.palette.textSecondary)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LegalDocScreen(
      doc: legalAbout,
      footer: [
        const SizedBox(height: 20),
        Center(
          child: Text('Version ${AppInfo.version} (Build ${AppInfo.build})',
              style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted)),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _showChangelogBottomSheet(context),
          icon: const Icon(Icons.history, size: 18, color: Color(0xFFE65C00)),
          label: Text("What's New",
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFFE65C00))),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0x33E65C00))),
        ),
        const SizedBox(height: 20),
        Text('Follow us',
            style: GoogleFonts.outfit(
                fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSocialButton(
                context: context,
                icon: Icons.camera_alt_outlined,
                label: 'Instagram',
                url: 'https://instagram.com/silenceapp'),
            _buildSocialButton(
                context: context,
                icon: Icons.play_circle_outline,
                label: 'YouTube',
                url: 'https://youtube.com/@silenceapp'),
            _buildSocialButton(
                context: context, icon: Icons.tag, label: 'Twitter', url: 'https://twitter.com/silenceapp'),
            _buildSocialButton(
                context: context,
                icon: Icons.business_center_outlined,
                label: 'LinkedIn',
                url: 'https://linkedin.com/company/silenceapp'),
          ],
        ),
      ],
    );
  }
}
