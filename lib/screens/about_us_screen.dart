import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_info.dart';
import '../widgets/app_gradient_scaffold.dart';

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientScaffold(
      title: 'About Us',
      body: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                // Logo/Brand area
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3ED),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE65C00), width: 2),
                    ),
                    child: const Icon(
                      Icons.storefront,
                      size: 64,
                      color: Color(0xFFE65C00),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'SILENCE',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: context.palette.textPrimary,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    'Study Space Management Redefined',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: context.palette.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Description card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: context.palette.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Our Vision',
                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Silence is built to empower library owners and students by simplifying seat management, attendance tracking, and fee collections. We strive to create the ultimate frictionless study environment.',
                        style: GoogleFonts.inter(fontSize: 13, color: context.palette.textSecondary, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Specs list
                Container(
                  decoration: BoxDecoration(
                    color: context.palette.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        title: Text('Version', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: context.palette.textPrimary)),
                        trailing: Text('${AppInfo.version} (Build ${AppInfo.build})', style: GoogleFonts.inter(fontSize: 13, color: context.palette.textMuted)),
                      ),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      ListTile(
                        title: Text('Privacy Policy', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: context.palette.textPrimary)),
                        trailing: const Icon(Icons.open_in_new, size: 16, color: Color(0xFF64748B)),
                        onTap: () => _launchUrl('https://silenceapp.in/privacy'),
                      ),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      ListTile(
                        title: Text('Terms of Service', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: context.palette.textPrimary)),
                        trailing: const Icon(Icons.open_in_new, size: 16, color: Color(0xFF64748B)),
                        onTap: () => _launchUrl('https://silenceapp.in/terms'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),

                // Copyright
                Center(
                  child: Text(
                    '© 2026 Silence App. All Rights Reserved.',
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
