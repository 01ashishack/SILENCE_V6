import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/admin_settings_service.dart';
import '../utils/error_messages.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final _supabase = Supabase.instance.client;
  String? _libraryId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLibraryId();
  }

  Future<void> _loadLibraryId() async {
    try {
      var libId = await AdminSettingsService.firstOwnedLibraryId();
      if (libId == null) {
        final user = _supabase.auth.currentUser;
        if (user != null) {
          final membership = await _supabase
              .from('memberships')
              .select('library_id')
              .eq('member_id', user.id)
              .limit(1)
              .maybeSingle();
          if (!mounted) return;
          if (membership != null) {
            libId = membership['library_id'] as String?;
          }
        }
      }
      setState(() {
        _libraryId = libId;
      });
      debugPrint('HelpSupportScreen: Loaded library ID: $_libraryId');
    } catch (e) {
      debugPrint('HelpSupportScreen: Error loading library ID: $e');
    }
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    if (!mounted) return;
    }
  }

  Future<void> _submitBugReport(String title, String description, String steps) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User session expired. Please sign in again.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    debugPrint('HelpSupportScreen: Submitting bug report. libraryId: $_libraryId, userId: ${user.id}');

    try {
      // Concatenate description and steps to reproduce for the message field
      final fullMessage = '$description\n\nSteps to Reproduce:\n$steps';

      final payload = {
        'library_id': _libraryId,
        'member_id': user.id,
        'subject': title,
        'message': fullMessage,
        'type': 'bug',
        'status': 'open',
        'created_at': DateTime.now().toIso8601String(),
      };

      await _supabase.from('queries').insert(payload);
      
      debugPrint('HelpSupportScreen: Bug report successfully submitted to queries table.');

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 28),
                const SizedBox(width: 8),
                Text('Bug Reported', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              'Thank you! Your bug report has been successfully submitted to our support queue. Our technical team will review it shortly.',
              style: GoogleFonts.inter(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Close', style: GoogleFonts.inter(color: const Color(0xFFE65C00), fontWeight: FontWeight.bold)),
              )
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('HelpSupportScreen: Error submitting bug report: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showReportBugSheet() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final stepsCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: 24, left: 24, right: 24
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Report a Bug',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 4),
              Text(
                'Help us improve. Provide details of the issue you encountered.',
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Bug Title / Summary *',
                  hintText: 'e.g. Settings screen fails to load shifts data',
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description of the Issue *',
                  hintText: 'Explain what went wrong and what you expected to see.',
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Description is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: stepsCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Steps to Reproduce (Optional)',
                  hintText: '1. Go to Profile Tab\n2. Click Settings\n3. Select Clear Cache',
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  if (formKey.currentState?.validate() == true) {
                    Navigator.pop(context);
                    _submitBugReport(
                      titleCtrl.text.trim(),
                      descCtrl.text.trim(),
                      stepsCtrl.text.trim(),
                    );
                  }
                },
                child: Text('Submit Report', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
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
          backgroundColor: const Color(0xFFFBF5EE),
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Help & Support',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Frequently Asked Questions',
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 12),

                      // FAQs Container
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            _buildFaqTile(
                              question: 'How to add a member?',
                              answer: 'Tap the Members tab in the Admin Home screen, then click the floating "+" button to launch the Add Member Wizard. Fill out personal details, assign a shift, allot a seat, configure payment details, and confirm.',
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildFaqTile(
                              question: 'How to generate QR codes?',
                              answer: 'Navigate to Business Settings inside the Admin Profile tab, and tap "QR Assets". You can view, share, or download the check-in QR code for your library branches.',
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildFaqTile(
                              question: 'How to view analytics?',
                              answer: 'Open the "Analytics" tab on the bottom navigation bar of the Admin Panel. It provides deep insights into check-in trends, occupancy rates, and revenue collections.',
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildFaqTile(
                              question: 'How to configure library shifts?',
                              answer: 'Go to Admin Profile -> Shift & Plan Config. Here you can add shifts, set pricing for different durations, and archive obsolete schedules.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      Text(
                        'Still need help?',
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choose one of the support options below to contact us or report issues.',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 16),

                      // Contact Actions Cards
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              onTap: _showReportBugSheet,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFECE5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.bug_report_outlined, color: Color(0xFFE65C00), size: 22),
                              ),
                              title: Text(
                                'Report a Bug',
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                              ),
                              subtitle: Text(
                                'Encountered an issue? Submit a diagnostic report',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                              ),
                              trailing: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF94A3B8)),
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            ListTile(
                              onTap: () => _launchUrl('mailto:support@silenceapp.in'),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.support_agent_outlined, color: Colors.blueAccent, size: 22),
                              ),
                              title: Text(
                                'Technical Support',
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                              ),
                              subtitle: Text(
                                'Contact our support engineers directly via email',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                              ),
                              trailing: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF94A3B8)),
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            ListTile(
                              onTap: () => _launchUrl('https://wa.me/919999999999'),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.chat_bubble_outline, color: Color(0xFF10B981), size: 22),
                              ),
                              title: Text(
                                'WhatsApp Business Support',
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                              ),
                              subtitle: Text(
                                'Chat live with our customer success team',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                              ),
                              trailing: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildFaqTile({required String question, required String answer}) {
    return Theme(
      data: ThemeData().copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          question,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E293B),
          ),
        ),
        iconColor: const Color(0xFFE65C00),
        collapsedIconColor: const Color(0xFF94A3B8),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
            child: Text(
              answer,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: const Color(0xFF475569),
                height: 1.5,
              ),
            ),
          )
        ],
      ),
    );
  }
}
