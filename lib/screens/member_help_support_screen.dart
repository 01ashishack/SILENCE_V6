import 'dart:io';
import '../theme/app_palette.dart';
import '../core/app_snackbar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/image_optimizer.dart';
import '../utils/error_messages.dart';

class MemberHelpSupportScreen extends StatefulWidget {
  const MemberHelpSupportScreen({super.key});

  @override
  State<MemberHelpSupportScreen> createState() => _MemberHelpSupportScreenState();
}

class _MemberHelpSupportScreenState extends State<MemberHelpSupportScreen> {
  final _supabase = Supabase.instance.client;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  final List<Map<String, String>> _faqs = [
    {
      'question': 'How do I check in and check out at the library?',
      'answer': 'Navigate to the Scanner tab (center button on the bottom navigation). Align the camera view with the QR code placed at your library branch reception or desk. The app will automatically check you in. Follow the same steps when leaving to check out.'
    },
    {
      'question': 'Can I pause or put my active membership on hold?',
      'answer': 'Yes. Under the Profile tab, look for your active membership card in the "My Libraries" section. Tap "Request Hold". Select your hold duration and reason, then submit. The admin will review and approve your request.'
    },
    {
      'question': 'How can I renew my expired membership card?',
      'answer': 'Go to your Profile tab. In the "My Libraries" section, you will see your past/expired cards. Tap the "Renew" or "Rejoin" button. Select your preferred seat, slot, and plan, then proceed to payment confirmation.'
    },
    {
      'question': 'How do slot timings work?',
      'answer': 'Libraries offer slots (e.g. morning, evening, night, or 24-hour). Your membership grants you access during your selected slot. Checking in outside of your slot time may require approval from the administrator.'
    },
    {
      'question': 'Can I change my assigned seat?',
      'answer': 'Seat changes depend on availability. Please speak directly with the library administrator. Once they reassign you, your desk details will instantly update on the home screen.'
    },
    {
      'question': 'What should I do if a payment fails?',
      'answer': 'If money was debited but the plan is not active, do not worry. Go to Help & Support -> Report an Issue. Choose "Payment Issue", enter transaction details, and upload a payment receipt screenshot. We will resolve it within 24 hours.'
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, String>> get _filteredFaqs {
    if (_searchQuery.trim().isEmpty) return _faqs;
    return _faqs.where((faq) {
      final q = faq['question']!.toLowerCase();
      final a = faq['answer']!.toLowerCase();
      final s = _searchQuery.toLowerCase();
      return q.contains(s) || a.contains(s);
    }).toList();
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        _showErrorSnackBar('Could not launch links.');
      if (!mounted) return;
      }
    } catch (e) {
      debugPrint('launchUrl failed: $e');
      _showErrorSnackBar('Couldn’t open the link.');
    }
  }

  void _showErrorSnackBar(String msg) {
    if (!mounted) return;
    AppSnackbar.error(context, msg);
  }

  void _showSuccessSnackBar(String msg) {
    if (!mounted) return;
    AppSnackbar.success(context, msg);
  }

  Future<bool> _requestPhotosPermission() async {
    // permission_handler is a MOBILE-ONLY plugin — on Windows/macOS/Linux
    // desktop (and web) it has no platform implementation and throws a
    // MissingPluginException, which force-closes the app. Skip the request on
    // those platforms; image_picker's gallery selection works without it.
    final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (!isMobile) return true;

    if (Platform.isAndroid) {
      final status = await Permission.photos.status;
      if (status.isGranted) return true;
      final result = await Permission.photos.request();
      if (result.isGranted) return true;
      final storageStatus = await Permission.storage.status;
      if (storageStatus.isGranted) return true;
      final storageResult = await Permission.storage.request();
      return storageResult.isGranted;
    }
    final status = await Permission.photos.status;
    if (status.isGranted) return true;
    final result = await Permission.photos.request();
    return result.isGranted;
  }

  void _showReportIssueSheet() {
    final formKey = GlobalKey<FormState>();
    final descController = TextEditingController();
    String issueType = 'Bug';
    String? screenshotUrl;
    bool isUploadingFile = false;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> pickAndUploadScreenshot() async {
            final hasPerm = await _requestPhotosPermission();
            if (!mounted) return;
            if (!hasPerm) {
              setModalState(() {});
              _showErrorSnackBar('Permission denied. Please grant library permissions.');
              return;
            }

            final picker = ImagePicker();
            XFile? image;
            try {
              image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 75);
            } catch (e) {
              debugPrint('pickImage failed: $e');
              if (mounted) _showErrorSnackBar('Could not open the file picker on this device.');
              return;
            }
            if (image == null) return;

            setModalState(() => isUploadingFile = true);
            try {
              final user = _supabase.auth.currentUser;
              if (user == null) throw 'Session expired';

              // Optimise image
              final bytes = await ImageOptimizer.compressImage(image.path);
              final String fileName = 'screenshot_${DateTime.now().millisecondsSinceEpoch}.jpg';
              final path = 'queries/${user.id}/$fileName';

              await _supabase.storage.from('silence_assets').uploadBinary(
                path,
                Uint8List.fromList(bytes),
                fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
              );
              if (!mounted) return;

              final publicUrl = _supabase.storage.from('silence_assets').getPublicUrl(path);
              setModalState(() {
                screenshotUrl = publicUrl;
              });
              _showSuccessSnackBar('Screenshot attached! ✓');
            } catch (e) {
              _showErrorSnackBar(friendlyError(e));
            } finally {
              setModalState(() => isUploadingFile = false);
            }
          }

          Future<void> submitIssue() async {
            if (!formKey.currentState!.validate()) return;
            setModalState(() => isSubmitting = true);

            try {
              final user = _supabase.auth.currentUser;
              if (user == null) throw 'User session expired';

              // Load active library_id from membership if available
              String? activeLibraryId;
              try {
                final membership = await _supabase
                    .from('memberships')
                    .select('library_id')
                    .eq('member_id', user.id)
                    .limit(1)
                    .maybeSingle();
                if (membership != null) {
                  activeLibraryId = membership['library_id'] as String?;
                }
              } catch (e) {
                debugPrint('Failed to query library ID for issue: $e');
              }

              // Build telemetry/diagnostics data
              final String deviceOS = Platform.operatingSystem;
              final String deviceOSVersion = Platform.operatingSystemVersion;
              final String appVersion = "1.0.6"; // Configured app build
              final String timestampStr = DateTime.now().toIso8601String();
              
              final telemetry = '\n\n--- Device Telemetry ---\nApp Version: $appVersion\nOS: $deviceOS ($deviceOSVersion)\nTimestamp: $timestampStr';
              final fullMessage = '${descController.text.trim()}$telemetry';

              final Map<String, dynamic> insertPayload = {
                'member_id': user.id,
                'subject': '[$issueType] Issue Report by Student',
                'message': fullMessage,
                'type': 'bug', // Standardised bug report
                'status': 'open',
                'created_at': DateTime.now().toIso8601String(),
              };

              if (activeLibraryId != null) {
                insertPayload['library_id'] = activeLibraryId;
              }

              // Check if table contains screenshot_url or if we append to message
              if (screenshotUrl != null) {
                insertPayload['screenshot_url'] = screenshotUrl;
              }

              // Try Supabase insert
              try {
                await _supabase.from('queries').insert(insertPayload);
              } catch (dbErr) {
                // If column screenshot_url is missing, append it directly in message field
                if (screenshotUrl != null) {
                  insertPayload['message'] = '$fullMessage\nAttachment URL: $screenshotUrl';
                  insertPayload.remove('screenshot_url');
                }
                await _supabase.from('queries').insert(insertPayload);
              }

              if (!mounted) return;
              _showSuccessSnackBar('Issue reported successfully! Our team is on it. ✓');
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
            } catch (e) {
              if (mounted) _showErrorSnackBar(friendlyError(e));
            } finally {
              setModalState(() => isSubmitting = false);
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              top: 24,
              left: 24,
              right: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Report an Issue',
                          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    Text('Issue Category', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: issueType,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: ['Bug', 'Payment Issue', 'Seat Allocation', 'App Suggestion', 'Other'].map((type) {
                        return DropdownMenuItem<String>(
                          value: type,
                          child: Text(type, style: GoogleFonts.inter(fontSize: 14)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) issueType = val;
                      },
                    ),
                    const SizedBox(height: 16),

                    Text('Describe the Issue *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: descController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Describe exactly what happened. If it is a payment issue, mention the reference number.',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Please enter issue details' : null,
                    ),
                    const SizedBox(height: 16),

                    // Screenshot Upload Row
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: isUploadingFile ? null : pickAndUploadScreenshot,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0x1FE65C00),
                            foregroundColor: const Color(0xFFE65C00),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.camera_alt_outlined, size: 16),
                          label: Text(
                            isUploadingFile ? 'Uploading...' : 'Attach Screenshot',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (screenshotUrl != null)
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 16),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Screenshot_attached.jpg',
                                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600]),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.redAccent, size: 16),
                                  onPressed: () => setModalState(() => screenshotUrl = null),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: isSubmitting || isUploadingFile ? null : submitIssue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65C00),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: isSubmitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text('Submit Report', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
          backgroundColor: context.palette.scaffold,
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
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // FAQ Search Bar
                _buildSearchBar(),
                const SizedBox(height: 16),

                // FAQs accordion list
                _buildSectionHeader('Frequently Asked Questions'),
                _buildFaqsList(),
                const SizedBox(height: 20),

                // Contact Us Card
                _buildSectionHeader('Contact Us'),
                _buildContactUsCard(),
                const SizedBox(height: 20),

                // App Guide Slideshow Placeholder
                _buildSectionHeader('App Walkthrough Guide'),
                _buildAppGuideCard(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: context.palette.textMuted, letterSpacing: 1),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: TextFormField(
        controller: _searchController,
        style: GoogleFonts.inter(fontSize: 14),
        onChanged: (val) => setState(() => _searchQuery = val),
        decoration: InputDecoration(
          hintText: 'Search FAQ questions or topics...',
          hintStyle: GoogleFonts.inter(color: Colors.grey[400]),
          prefixIcon: const Icon(Icons.search, color: Color(0xFFE65C00)),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildFaqsList() {
    final list = _filteredFaqs;
    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.search_off_outlined, color: Colors.grey[400], size: 40),
              const SizedBox(height: 8),
              Text(
                'No matching FAQs found',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                'Try searching other keywords or submit a report below.',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: list.length,
        separatorBuilder: (context, index) => const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6)),
        itemBuilder: (context, index) {
          final faq = list[index];
          return Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(
                faq['question']!,
                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
              ),
              iconColor: const Color(0xFFE65C00),
              collapsedIconColor: Colors.grey,
              childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              children: [
                Text(
                  faq['answer']!,
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF4B5563), height: 1.5),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildContactUsCard() {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            onTap: _showReportIssueSheet,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Color(0x1FE65C00), shape: BoxShape.circle),
              child: const Icon(Icons.bug_report_outlined, color: Color(0xFFE65C00), size: 20),
            ),
            title: Text('Report an Issue', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
            subtitle: Text('File bug reports, payment issues, or slot feedback.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6), indent: 56),
          ListTile(
            onTap: () => _launchUrl('https://wa.me/917297879930'),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Color(0xFFECFDF5), shape: BoxShape.circle),
              child: const Icon(Icons.chat, color: Color(0xFF10B981), size: 20),
            ),
            title: Text('WhatsApp Support', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
            subtitle: Text('Chat instantly with the support executive.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6), indent: 56),
          ListTile(
            onTap: () => _launchUrl('mailto:support@silenceapp.in'),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Color(0xFFEFF6FF), shape: BoxShape.circle),
              child: const Icon(Icons.email_outlined, color: Color(0xFF3B82F6), size: 20),
            ),
            title: Text('Email Support', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
            subtitle: Text('Email details of your query to support team.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6), indent: 56),
          ListTile(
            onTap: null, // Disabled
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Color(0xFFF3F4F6), shape: BoxShape.circle),
              child: const Icon(Icons.question_answer_outlined, color: Colors.grey, size: 20),
            ),
            title: Text('In-App Live Chat', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
            subtitle: Text('💬 In-app chat coming soon!', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[400])),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
              child: Text('SOON', style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey[600])),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppGuideCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 160,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE65C00), Color(0xFFC44E00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.1,
                    child: Icon(Icons.menu_book, size: 180, color: Colors.white),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow, size: 36, color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'SILENCE Member App Walkthrough',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Video Guide & Feature Tutorial Slideshow',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'App Walkthrough Slideshow (Coming Soon)',
            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'We are preparing step-by-step tutorial cards and a visual guide for the SILENCE app to help you easily locate features, print receipts, and configure preferences.',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500], height: 1.4),
          ),
        ],
      ),
    );
  }
}

