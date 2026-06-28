import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_palette.dart';
import '../legal/legal_content.dart';

/// Shared, role-agnostic legal/policy rendering. All legal screens (member and
/// admin) render a [LegalDoc] from `lib/legal/legal_content.dart`, so there is a
/// single in-app source of truth and the member/admin variants always match.
///
/// Content is informational, not legal advice; have it reviewed by a qualified
/// Indian lawyer before public launch.

/// Renders the body of a [LegalDoc] (last-updated, intro, sections, related
/// links, contact footer) as a scrollable column. Reused by the standalone
/// [LegalDocScreen] and by screens that wrap it in their own scaffold (e.g. the
/// member Terms/Privacy screens that add a version-acceptance banner).
Widget buildLegalBody(
  BuildContext context,
  LegalDoc doc, {
  EdgeInsetsGeometry padding = const EdgeInsets.all(20),
  List<Widget> footer = const [],
}) {
  final p = context.palette;
  return ListView(
    padding: padding,
    children: [
      Text(kLegalLastUpdated,
          style: GoogleFonts.inter(
              fontSize: 11.5, color: p.textMuted, fontWeight: FontWeight.w500)),
      const SizedBox(height: 12),
      Text(doc.intro,
          style: GoogleFonts.inter(fontSize: 13.5, height: 1.5, color: p.textSecondary)),
      const SizedBox(height: 20),
      ...doc.sections.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.heading,
                    style: GoogleFonts.outfit(
                        fontSize: 15, fontWeight: FontWeight.bold, color: p.textPrimary)),
                const SizedBox(height: 6),
                Text(s.body,
                    style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: p.textSecondary)),
              ],
            ),
          )),
      if (doc.related.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text('Related policies',
            style: GoogleFonts.outfit(
                fontSize: 12, fontWeight: FontWeight.bold, color: p.textMuted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: doc.related
              .map((r) => ActionChip(
                    label: Text(r.label,
                        style: GoogleFonts.inter(
                            fontSize: 12, color: const Color(0xFFE65C00), fontWeight: FontWeight.w600)),
                    backgroundColor: const Color(0x14E65C00),
                    side: const BorderSide(color: Color(0x33E65C00)),
                    onPressed: () => Navigator.pushNamed(context, r.route),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
      ],
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0x1FE65C00),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFE0CC)),
        ),
        child: Text(
          'Questions about this policy? Email $kSupportEmail or call $kSupportPhone.',
          style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: const Color(0xFF9A3412)),
        ),
      ),
      ...footer,
      const SizedBox(height: 24),
    ],
  );
}

/// Renders just the intro + sections of a [LegalDoc] as a non-scrolling Column
/// (for embedding inside screens that already provide their own scroll view,
/// e.g. the member Terms/Privacy screens with a version-acceptance banner).
Widget legalSectionsColumn(BuildContext context, LegalDoc doc) {
  final p = context.palette;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(doc.intro,
          style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: p.textSecondary)),
      const SizedBox(height: 18),
      ...doc.sections.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.heading,
                    style: GoogleFonts.outfit(
                        fontSize: 14, fontWeight: FontWeight.bold, color: p.textPrimary)),
                const SizedBox(height: 6),
                Text(s.body,
                    style: GoogleFonts.inter(fontSize: 12.5, height: 1.55, color: p.textSecondary)),
              ],
            ),
          )),
    ],
  );
}

/// A complete standalone screen that renders a [LegalDoc]. Dark-aware via
/// `context.palette`; warm-orange Material 3 app bar.
class LegalDocScreen extends StatelessWidget {
  final LegalDoc doc;
  final List<Widget> footer;
  const LegalDocScreen({super.key, required this.doc, this.footer = const []});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffold,
      appBar: AppBar(
        backgroundColor: const Color(0xFFE65C00),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(doc.title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      ),
      body: buildLegalBody(context, doc, footer: footer),
    );
  }
}

class RefundPolicyScreen extends StatelessWidget {
  const RefundPolicyScreen({super.key});
  @override
  Widget build(BuildContext context) => const LegalDocScreen(doc: legalRefund);
}

class CancellationPolicyScreen extends StatelessWidget {
  const CancellationPolicyScreen({super.key});
  @override
  Widget build(BuildContext context) => const LegalDocScreen(doc: legalCancellation);
}

class CommunityGuidelinesScreen extends StatelessWidget {
  const CommunityGuidelinesScreen({super.key});
  @override
  Widget build(BuildContext context) => const LegalDocScreen(doc: legalCommunity);
}
