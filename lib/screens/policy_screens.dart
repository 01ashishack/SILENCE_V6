import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared, role-agnostic legal/policy screens (used by both member & admin
/// profile tabs). Single source so admin and member always show identical text.
///
/// Content is a production-ready DRAFT for an Indian study-space SaaS; have it
/// reviewed by a lawyer before public launch. Each screen carries a
/// "Last updated" date so changes are traceable.

const String _kPolicyLastUpdated = 'Last updated: 25 June 2026';
const String _kSupportEmail = 'support@silenceapp.in';

class _PolicySection {
  final String heading;
  final String body;
  const _PolicySection(this.heading, this.body);
}

class _PolicyScaffold extends StatelessWidget {
  final String title;
  final String intro;
  final List<_PolicySection> sections;

  const _PolicyScaffold({
    required this.title,
    required this.intro,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffold,
      appBar: AppBar(
        backgroundColor: const Color(0xFFE65C00),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(_kPolicyLastUpdated,
              style: GoogleFonts.inter(
                  fontSize: 11.5, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Text(intro,
              style: GoogleFonts.inter(
                  fontSize: 13.5, height: 1.5, color: context.palette.textSecondary)),
          const SizedBox(height: 20),
          ...sections.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.heading,
                        style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: context.palette.textPrimary)),
                    const SizedBox(height: 6),
                    Text(s.body,
                        style: GoogleFonts.inter(
                            fontSize: 13, height: 1.5, color: context.palette.textSecondary)),
                  ],
                ),
              )),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7F0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFE0CC)),
            ),
            child: Text(
              'Questions about this policy? Email $_kSupportEmail.',
              style: GoogleFonts.inter(
                  fontSize: 12.5, height: 1.4, color: const Color(0xFF9A3412)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class RefundPolicyScreen extends StatelessWidget {
  const RefundPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PolicyScaffold(
      title: 'Refund Policy',
      intro:
          'This policy explains when and how refunds are handled for memberships '
          'and add-ons paid through a SILENCE-listed library.',
      sections: [
        _PolicySection('1. Membership fees',
            'Membership fees are paid directly to the library you join. As a study '
            'seat is reserved for you for the paid period, membership fees are '
            'generally non-refundable once the period has started.'),
        _PolicySection('2. Refundable deposits',
            'Refundable security deposits (where collected) are returned by the '
            'library when you exit, subject to no outstanding dues or damage, as '
            'per that library\'s terms.'),
        _PolicySection('3. Duplicate or failed payments',
            'If you are charged twice for the same membership, or a payment is '
            'deducted but not reflected, contact the library and, if unresolved, '
            'email $_kSupportEmail with proof. Verified duplicate charges are '
            'refunded to the original payment method.'),
        _PolicySection('4. Discretionary refunds',
            'A library may, at its discretion, offer a pro-rata refund for unused '
            'days in genuine cases (relocation, medical, etc.). SILENCE does not '
            'control individual library decisions.'),
        _PolicySection('5. Platform/subscription fees',
            'Fees paid by a library owner to SILENCE for the platform itself are '
            'governed separately by the owner subscription terms shown at purchase.'),
      ],
    );
  }
}

class CancellationPolicyScreen extends StatelessWidget {
  const CancellationPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PolicyScaffold(
      title: 'Cancellation Policy',
      intro:
          'This policy explains how to cancel a membership, a join request, or a '
          'library owner subscription.',
      sections: [
        _PolicySection('1. Cancelling a pending join request',
            'A membership join request that has not yet been approved can be '
            'withdrawn from the app at any time at no charge.'),
        _PolicySection('2. Cancelling an active membership',
            'You may stop using your seat at any time. Active memberships run until '
            'the end of the paid period; cancelling early does not automatically '
            'create a refund (see the Refund Policy).'),
        _PolicySection('3. Membership hold/pause',
            'Where a library enables holds, you can pause your membership within '
            'that library\'s allowed limits; the remaining days resume after the hold.'),
        _PolicySection('4. Owner subscription cancellation',
            'Library owners can stop their SILENCE subscription from billing '
            'settings; access continues until the end of the current billing cycle '
            'and does not auto-renew after cancellation.'),
        _PolicySection('5. Account deletion',
            'Deleting your account schedules permanent removal after a 7-day window '
            'and is separate from cancelling a single membership.'),
      ],
    );
  }
}

class CommunityGuidelinesScreen extends StatelessWidget {
  const CommunityGuidelinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PolicyScaffold(
      title: 'Community Guidelines',
      intro:
          'SILENCE study spaces work because everyone keeps them calm, safe and '
          'respectful. These guidelines apply to all members and library owners.',
      sections: [
        _PolicySection('1. Respect the quiet',
            'Keep noise to a minimum, silence your phone, and take calls outside '
            'the study area. Be considerate of others who are focusing.'),
        _PolicySection('2. Respect people',
            'No harassment, discrimination, threats, or unwanted contact toward any '
            'member or staff. Treat everyone with dignity regardless of gender, '
            'religion, caste, or background.'),
        _PolicySection('3. Honest use',
            'Use your own account, your own seat and your own membership. Do not '
            'share QR codes, impersonate others, or misuse another member\'s booking.'),
        _PolicySection('4. Care for the space',
            'Keep your seat clean, handle furniture and amenities carefully, and '
            'follow each library\'s posted rules and timings.'),
        _PolicySection('5. No unlawful or unsafe activity',
            'Do not use the space for anything illegal, or bring anything that '
            'endangers others. Report safety concerns to the library or to '
            '$_kSupportEmail.'),
        _PolicySection('6. Enforcement',
            'Violations can lead to warnings, removal from a library, or a platform '
            'ban. Serious safety issues may be reported to the authorities.'),
      ],
    );
  }
}
