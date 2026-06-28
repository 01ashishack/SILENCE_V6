import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_info.dart';
import '../legal/legal_content.dart';
import '../theme/app_palette.dart';
import 'policy_screens.dart';

/// Admin-side About Us. Renders the canonical [legalAbout] doc (same content as
/// the member-side About screen) with an app-version footer line.
class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalDocScreen(
      doc: legalAbout,
      footer: [
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Version ${AppInfo.version} (Build ${AppInfo.build})',
            style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted),
          ),
        ),
      ],
    );
  }
}
