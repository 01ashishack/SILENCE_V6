import 'package:flutter/material.dart';
import '../legal/legal_content.dart';
import 'policy_screens.dart';

/// Admin-side Terms & Conditions. Renders the same canonical [legalTerms] doc
/// as the member-side Terms screen (single source of truth).
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) => const LegalDocScreen(doc: legalTerms);
}
