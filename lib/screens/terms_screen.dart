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
                  const SizedBox(height: 12),
                  Text(
                    'Welcome to SILENCE. By using our application, you agree to comply with and be bound by the following terms and conditions of use.',
                    style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF475569), height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('1. License & Scope'),
                  _buildSectionBody(
                    'Silence grants library owners a non-exclusive, non-transferable, revocable license to manage their workspace, register students, and configuration details for administrative purposes.',
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('2. User Responsibility'),
                  _buildSectionBody(
                    'Administrators are responsible for safeguarding client and seat allocation details, ensuring correct student profiles, and processing payments inside their specific region correctly.',
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('3. Privacy & Safety'),
                  _buildSectionBody(
                    'We value data confidentiality. All student records, attendance logs, and transactions are stored safely under encrypted Supabase channels.',
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('4. Modifications'),
                  _buildSectionBody(
                    'Silence reserves the right to modify these terms or update subscription tariffs with a prior 30-day notice to active workspace owners.',
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
