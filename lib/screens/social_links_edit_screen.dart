import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SocialLinksEditScreen extends StatefulWidget {
  final String? libraryId;
  const SocialLinksEditScreen({super.key, this.libraryId});

  @override
  State<SocialLinksEditScreen> createState() => _SocialLinksEditScreenState();
}

class _SocialLinksEditScreenState extends State<SocialLinksEditScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;
  String? _libId;

  final _instagramController = TextEditingController();
  final _youtubeController = TextEditingController();
  final _facebookController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _websiteController = TextEditingController();

  Map<String, dynamic> _existingSocialLinks = {};

  @override
  void initState() {
    super.initState();
    _libId = widget.libraryId;
    _loadSocialLinks();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_libId == null) {
      final Object? args = ModalRoute.of(context)?.settings.arguments;
      if (args is String) {
        _libId = args;
      }
    }
  }

  Future<void> _loadSocialLinks() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final String? targetLibId = _libId;
      if (targetLibId != null) {
        final libData = await _supabase.from('libraries').select('social_links').eq('id', targetLibId).maybeSingle();
        if (!mounted) return;
        if (libData != null && libData['social_links'] != null) {
          final social = libData['social_links'] as Map<String, dynamic>;
          setState(() {
            _existingSocialLinks = social;
            _instagramController.text = social['instagram']?.toString() ?? '';
            _youtubeController.text = social['youtube']?.toString() ?? '';
            _facebookController.text = social['facebook']?.toString() ?? '';
            _whatsappController.text = social['whatsapp']?.toString() ?? '';
            _websiteController.text = social['website']?.toString() ?? '';
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading social links: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSocialLinks() async {
    final String? targetLibId = _libId;
    if (targetLibId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Library ID not found.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final Map<String, dynamic> updatedSocial = Map<String, dynamic>.from(_existingSocialLinks);
      updatedSocial['instagram'] = _instagramController.text.trim();
      updatedSocial['youtube'] = _youtubeController.text.trim();
      updatedSocial['facebook'] = _facebookController.text.trim();
      updatedSocial['whatsapp'] = _whatsappController.text.trim();
      updatedSocial['website'] = _websiteController.text.trim();

      await _supabase.from('libraries').update({
        'social_links': updatedSocial,
      }).eq('id', targetLibId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Social links updated successfully! ✓'), backgroundColor: Color(0xFF10B981)),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving social links: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _instagramController.dispose();
    _youtubeController.dispose();
    _facebookController.dispose();
    _whatsappController.dispose();
    _websiteController.dispose();
    super.dispose();
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
              'Social Profile Links',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          body: _isLoading && _existingSocialLinks.isEmpty
              ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLinkTextField(
                              label: 'Instagram URL',
                              controller: _instagramController,
                              icon: Icons.camera_alt_outlined,
                              hint: 'https://instagram.com/yourhandle',
                            ),
                            const SizedBox(height: 16),
                            _buildLinkTextField(
                              label: 'YouTube Channel URL',
                              controller: _youtubeController,
                              icon: Icons.video_library_outlined,
                              hint: 'https://youtube.com/c/yourchannel',
                            ),
                            const SizedBox(height: 16),
                            _buildLinkTextField(
                              label: 'Facebook Page URL',
                              controller: _facebookController,
                              icon: Icons.facebook_outlined,
                              hint: 'https://facebook.com/yourpage',
                            ),
                            const SizedBox(height: 16),
                            _buildLinkTextField(
                              label: 'WhatsApp Business Link / Number',
                              controller: _whatsappController,
                              icon: Icons.chat_bubble_outline,
                              hint: 'https://wa.me/919999999999 or phone number',
                            ),
                            const SizedBox(height: 16),
                            _buildLinkTextField(
                              label: 'Website URL',
                              controller: _websiteController,
                              icon: Icons.language_outlined,
                              hint: 'https://yourlibrary.com',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _saveSocialLinks,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                              )
                            : Text('Save Social Links', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildLinkTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF1A1A2E)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: const Color(0xFF9CA3AF).withOpacity(0.5)),
            prefixIcon: Icon(icon, size: 20, color: const Color(0xFFE65C00)),
          ),
        ),
      ],
    );
  }
}
