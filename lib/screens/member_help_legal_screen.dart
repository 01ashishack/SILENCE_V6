import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_info.dart';
import '../theme/app_palette.dart';
import 'contact_admin_screen.dart';

/// Single hub for all help & legal links, opened from one entry on the Profile
/// tab (keeps the profile screen short).
class MemberHelpLegalScreen extends StatelessWidget {
  const MemberHelpLegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.scaffold,
      appBar: AppBar(
        backgroundColor: const Color(0xFFE65C00),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Help & Legal', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(context, 'SUPPORT', [
            _row(context, Icons.forum_outlined, const Color(0xFFE65C00), 'Contact Admin',
                'Send queries & see admin replies',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ContactAdminScreen()))),
            _row(context, Icons.chat_bubble_outline, const Color(0xFF2563EB), 'Help & Support',
                'FAQs, contact us, report issues',
                route: '/member/help'),
            _row(context, Icons.info_outline, const Color(0xFF4B5563), 'About SILENCE',
                'Version ${AppInfo.version} · Meet the team',
                route: '/member/about'),
          ]),
          const SizedBox(height: 16),
          _section(context, 'LEGAL & POLICIES', [
            _row(context, Icons.description_outlined, const Color(0xFF4B5563), 'Terms & Conditions', '',
                route: '/member/terms'),
            _row(context, Icons.shield_outlined, const Color(0xFF4B5563), 'Privacy Policy', '',
                route: '/member/privacy-policy'),
            _row(context, Icons.payments_outlined, const Color(0xFF4B5563), 'Refund Policy',
                'When refunds apply',
                route: '/policy/refund'),
            _row(context, Icons.cancel_outlined, const Color(0xFF4B5563), 'Cancellation Policy',
                'Cancelling memberships & subscriptions',
                route: '/policy/cancellation'),
            _row(context, Icons.groups_outlined, const Color(0xFF4B5563), 'Community Guidelines',
                'How we keep spaces calm & safe',
                route: '/policy/community'),
            _row(context, Icons.assignment_outlined, const Color(0xFF4B5563), 'Licences',
                'Third-party libraries used',
                route: '/member/licences'),
          ]),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> rows) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title,
              style: GoogleFonts.outfit(
                  fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFF9CA3AF), letterSpacing: 1.5)),
        ),
        Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.border),
          ),
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 56, color: p.divider),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, IconData icon, Color color, String title, String subtitle,
      {String? route, VoidCallback? onTap}) {
    final p = context.palette;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title,
          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: p.textPrimary)),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: p.textMuted)),
      trailing: const Icon(Icons.chevron_right, size: 16, color: Color(0xFF94A3B8)),
      onTap: onTap ?? (route != null ? () => Navigator.pushNamed(context, route) : null),
    );
  }
}
