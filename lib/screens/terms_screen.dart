import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/app_gradient_scaffold.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppGradientScaffold(
      title: 'Terms & Conditions',
      body: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Terms & Conditions of Use',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 4),
                  Text('Last updated: 25 June 2026',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  Text(
                    'These terms govern use of the SILENCE application by library owners (admins) and members. By creating an account or using the app, you agree to these terms.',
                    style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF475569), height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('1. Eligibility & accounts'),
                  _buildSectionBody(
                    'You must provide accurate information and keep your login secure. You are responsible for activity under your account. Library owners are responsible for the accuracy of their library, seat, shift and pricing details.',
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('2. License'),
                  _buildSectionBody(
                    'SILENCE grants you a non-exclusive, non-transferable, revocable licence to use the app for managing or joining a study space. You may not copy, resell, reverse-engineer or misuse the service.',
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('3. Payments'),
                  _buildSectionBody(
                    'Membership fees are paid by members directly to the library (e.g. via UPI); SILENCE is not a party to those payments. Platform subscription fees payable by owners are shown at purchase. Refunds and cancellations are governed by the Refund Policy and Cancellation Policy.',
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('4. Acceptable use'),
                  _buildSectionBody(
                    'You agree to follow the Community Guidelines and applicable laws. Harassment, fraud, impersonation, sharing of access credentials, or any unlawful or unsafe activity is prohibited and may lead to suspension.',
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('5. Data & privacy'),
                  _buildSectionBody(
                    'We process personal data as described in the Privacy Policy, in line with India\'s Digital Personal Data Protection Act, 2023. You can request export or deletion of your data from the app.',
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('6. Availability & liability'),
                  _buildSectionBody(
                    'The service is provided "as is". We do not guarantee uninterrupted availability and are not liable for indirect or consequential losses to the maximum extent permitted by law. Libraries are independently responsible for their premises and services.',
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('7. Termination'),
                  _buildSectionBody(
                    'You may stop using the app and delete your account at any time. We may suspend or terminate access for breach of these terms or unlawful activity.',
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('8. Changes & governing law'),
                  _buildSectionBody(
                    'We may update these terms with reasonable notice for material changes. These terms are governed by the laws of India. Questions: support@silenceapp.in.',
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF1E293B),
        ),
      ),
    );
  }

  Widget _buildSectionBody(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 12.5,
        color: const Color(0xFF64748B),
        height: 1.5,
      ),
    );
  }
}
