import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';

class LibraryProfileScreen extends StatefulWidget {
  final String? libraryId;
  const LibraryProfileScreen({super.key, this.libraryId});

  @override
  State<LibraryProfileScreen> createState() => _LibraryProfileScreenState();
}

class _LibraryProfileScreenState extends State<LibraryProfileScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;
  String? _libId;
  Map<String, dynamic>? _libraryData;

  // Editable fields local state
  String _name = 'Downtown Study Space';
  String _about = 'Premium, distraction-free study space with high-speed Wi-Fi, ergonomic seating, and power backup at every desk. Perfect for competitive exams preparation and remote working professionals.';
  String _emergencyPhone = '+91 98765 43210';
  List<String> _selectedAmenities = ['Air Conditioning (AC)', 'High-Speed Wi-Fi', 'Personal Lockers', 'RO Drinking Water'];
  List<String> _galleryUrls = [];
  String? _coverUrl;
  
  // Rating values
  double _rating = 4.8;
  int _reviewsCount = 42;
  Map<int, int> _ratingBreakdown = {5: 32, 4: 8, 3: 2, 2: 0, 1: 0};

  @override
  void initState() {
    super.initState();
    _libId = widget.libraryId;
    _fetchLibraryDetails();
  }

  Future<void> _fetchLibraryDetails() async {
    setState(() => _isLoading = true);
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        final Object? args = ModalRoute.of(context)?.settings.arguments;
        if (args is String) {
          _libId = args;
        }

        // Fetch library ID from args if not provided
        if (_libId == null) {
          final res = await _supabase.from('libraries').select().eq('owner_id', user.id).maybeSingle();
          if (res != null) {
            _libId = res['id'];
            _libraryData = res;
          }
        } else {
          final res = await _supabase.from('libraries').select().eq('id', _libId!).maybeSingle();
          if (res != null) {
            _libraryData = res;
          }
        }

        if (_libraryData != null) {
          _name = _libraryData!['name'] ?? _name;
          _emergencyPhone = _libraryData!['emergency_phone'] ?? _emergencyPhone;
          _coverUrl = _libraryData!['cover_photo_url'];
          
          if (_libraryData!['amenities'] != null) {
            _selectedAmenities = List<String>.from(_libraryData!['amenities']);
          }
          
          final photos = _libraryData!['photos'] as List?;
          if (photos != null && photos.isNotEmpty) {
            if (_coverUrl == null) _coverUrl = photos.first;
            _galleryUrls = List<String>.from(photos);
          }
        }

        // Fetch local settings details as fallback
        final prefs = await SharedPreferences.getInstance();
        _about = prefs.getString('lib_profile_about_${_libId ?? "default"}') ?? _about;
        _emergencyPhone = prefs.getString('lib_profile_phone_${_libId ?? "default"}') ?? _emergencyPhone;
      } catch (e) {
        debugPrint('Error loading library profile: $e');
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _updateAbout(String newAbout) async {
    setState(() => _about = newAbout);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lib_profile_about_${_libId ?? "default"}', newAbout);
    
    // Attempt updating remote database
    if (_libId != null) {
      try {
        await _supabase.from('libraries').update({
          'about_text': newAbout, // update if column exists, otherwise will fall back
        }).eq('id', _libId!);
      } catch (_) {}
    }
  }

  Future<void> _updatePhone(String newPhone) async {
    setState(() => _emergencyPhone = newPhone);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lib_profile_phone_${_libId ?? "default"}', newPhone);
    
    if (_libId != null) {
      try {
        await _supabase.from('libraries').update({
          'emergency_phone': newPhone,
        }).eq('id', _libId!);
      } catch (_) {}
    }
  }

  Future<void> _uploadCoverImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (image == null) return;

    setState(() => _isLoading = true);
    try {
      final bytes = await File(image.path).readAsBytes();
      final path = 'library_photos/${_libId ?? "temp"}/cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      // Upload to supabase storage bucket
      try {
        await _supabase.storage.createBucket('silence_assets', const BucketOptions(public: true));
      } catch (_) {}

      await _supabase.storage.from('silence_assets').uploadBinary(path, bytes, 
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));

      final publicUrl = _supabase.storage.from('silence_assets').getPublicUrl(path);
      setState(() => _coverUrl = publicUrl);

      if (_libId != null) {
        await _supabase.from('libraries').update({
          'cover_photo_url': publicUrl,
        }).eq('id', _libId!);
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cover image uploaded successfully!'), backgroundColor: Color(0xFFE65C00)),
      );
    } catch (e) {
      debugPrint('Upload error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading cover: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  double _calculateProfileCompletion() {
    double score = 0.2; // Base details
    if (_coverUrl != null) score += 0.15;
    if (_about.isNotEmpty) score += 0.15;
    if (_emergencyPhone.isNotEmpty) score += 0.15;
    if (_selectedAmenities.length >= 3) score += 0.15;
    if (_galleryUrls.isNotEmpty) score += 0.2;
    return score;
  }

  void _showEditAboutSheet() {
    final controller = TextEditingController(text: _about);
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Edit About Description',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 5,
              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF334155)),
              decoration: InputDecoration(
                hintText: 'Enter description about your study library...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                _updateAbout(controller.text.trim());
                Navigator.pop(context);
              },
              child: Text('Save Description', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showEditContactSheet() {
    final controller = TextEditingController(text: _emergencyPhone);
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Edit Public Contact Info',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF334155)),
              decoration: InputDecoration(
                hintText: 'Enter phone number...',
                prefixIcon: const Icon(Icons.phone_outlined, color: Color(0xFFE65C00)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                _updatePhone(controller.text.trim());
                Navigator.pop(context);
              },
              child: Text('Save Contact', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final completion = _calculateProfileCompletion();
    final isVerified = completion >= 0.85;

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
              'Library Profile',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          body: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
              : SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Cover Photo Area
                      Stack(
                        children: [
                          Container(
                            height: 200,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0),
                              image: _coverUrl != null 
                                  ? DecorationImage(image: NetworkImage(_coverUrl!), fit: BoxFit.cover)
                                  : null,
                            ),
                            child: _coverUrl == null 
                                ? Center(
                                    child: Icon(Icons.image_outlined, size: 48, color: Colors.grey[400]),
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 12,
                            right: 12,
                            child: InkWell(
                              onTap: _uploadCoverImage,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.edit_outlined, size: 18, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),

                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 2. Identity Row
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF3ED),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: const Color(0xFFE65C00), width: 1.5),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.store, color: Color(0xFFE65C00), size: 30),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              _name,
                                              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                            ),
                                            if (isVerified) ...[
                                              const SizedBox(width: 4),
                                              const Icon(Icons.verified, size: 16, color: Color(0xFFE65C00)),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(Icons.star, size: 14, color: Colors.amber),
                                            const SizedBox(width: 2),
                                            Text(
                                              '$_rating',
                                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '($_reviewsCount reviews)',
                                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF3ED),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '120 Members',
                                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 3. Quick Actions
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildQuickActionItem(Icons.share_outlined, 'Share', () {
                                    Clipboard.setData(ClipboardData(text: 'Check out our library: $_name at SILENCE App! Code: SIL-${_libId?.substring(0, 6).toUpperCase() ?? "ABC123"}'));
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Library link copied to clipboard!')));
                                  }),
                                  _buildQuickActionItem(Icons.preview_outlined, 'Preview', () {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Previewing public member card...')));
                                  }),
                                  _buildQuickActionItem(Icons.qr_code_2, 'QR Code', () {
                                    Navigator.pushNamed(context, '/admin/settings/qr');
                                  }),
                                  _buildQuickActionItem(Icons.edit_outlined, 'Edit Info', () {
                                    Navigator.pushNamed(context, '/admin/library/setup/1');
                                  }),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 4. Profile Completion Progress
                            InkWell(
                              onTap: () {
                                Navigator.pushNamed(context, '/admin/verified-badge');
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFFF3ED), Color(0xFFFFE0D1)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFFFD0B8)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Profile Completion',
                                          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                        ),
                                        Text(
                                          '${(completion * 100).toInt()}%',
                                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: completion,
                                        backgroundColor: Colors.white54,
                                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
                                        minHeight: 8,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      completion >= 0.85 
                                          ? '🎖️ Excellent! You are eligible for a Verified Badge status.'
                                          : 'Complete details to 85% to receive a Verified Badge tick! 🌟',
                                      style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF475569), fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 5. About Description
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'About & Description',
                                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                      ),
                                      TextButton(
                                        onPressed: _showEditAboutSheet,
                                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                        child: Text(
                                          'Edit',
                                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _about,
                                    style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF475569), height: 1.5),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 6. Stats Row Card
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildStatColumn('120', 'Members'),
                                  _buildStatColumn('86%', 'Occupancy'),
                                  _buildStatColumn('3', 'Shifts'),
                                  _buildStatColumn('2 yrs', 'Operation'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 7. Settings List Navigation
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                children: [
                                  _buildSettingsListItem('General Information', Icons.info_outline, () => Navigator.pushNamed(context, '/admin/library/setup/1')),
                                  _buildSettingsListItem('Amenities Configuration', Icons.wifi, () => Navigator.pushNamed(context, '/admin/library/setup/1')),
                                  _buildSettingsListItem('Membership Plans', Icons.credit_card, () => Navigator.pushNamed(context, '/admin/settings/pricing')),
                                  _buildSettingsListItem('Rules & Guidelines', Icons.rule_folder_outlined, () => Navigator.pushNamed(context, '/admin/settings/business-rules')),
                                  _buildSettingsListItem('Social Profile Links', Icons.link, _showEditAboutSheet),
                                  _buildSettingsListItem('Add-on Services Settings', Icons.widgets_outlined, () => Navigator.pushNamed(context, '/admin/settings/addons')),
                                  _buildSettingsListItem('Emergency Contact Info', Icons.phone_android, _showEditContactSheet),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 8. Emergency Contact Banner
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF1F2),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFFECDD3)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFFE4E6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.phone_callback, color: Color(0xFFE11D48), size: 20),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Public Emergency Contact',
                                          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFE11D48)),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _emergencyPhone,
                                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          'Visible to members in their emergency drawer.',
                                          style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 18, color: Color(0xFFE11D48)),
                                    onPressed: _showEditContactSheet,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 9. Ratings & Reviews breakdown
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Ratings & Reviews Breakdown',
                                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Column(
                                        children: [
                                          Text(
                                            '$_rating',
                                            style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: List.generate(5, (index) => Icon(
                                              index < _rating.floor() ? Icons.star : Icons.star_half,
                                              size: 14, color: Colors.amber,
                                            )),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '$_reviewsCount reviews',
                                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 24),
                                      Expanded(
                                        child: Column(
                                          children: [5, 4, 3, 2, 1].map((stars) {
                                            final count = _ratingBreakdown[stars] ?? 0;
                                            final pct = _reviewsCount > 0 ? count / _reviewsCount : 0.0;
                                            return Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                                              child: Row(
                                                children: [
                                                  Text('$stars★', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF475569))),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: ClipRRect(
                                                      borderRadius: BorderRadius.circular(3),
                                                      child: LinearProgressIndicator(
                                                        value: pct,
                                                        backgroundColor: const Color(0xFFF1F5F9),
                                                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
                                                        minHeight: 6,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  SizedBox(
                                                    width: 20,
                                                    child: Text('$count', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B), fontWeight: FontWeight.bold)),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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

  Widget _buildQuickActionItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3ED),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFFE65C00)),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String val, String label) {
    return Column(
      children: [
        Text(
          val,
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _buildSettingsListItem(String title, IconData icon, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, size: 18, color: const Color(0xFF64748B)),
      title: Text(
        title,
        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w500, color: const Color(0xFF1E293B)),
      ),
      trailing: const Icon(Icons.chevron_right, size: 16, color: Color(0xFF94A3B8)),
      onTap: onTap,
    );
  }
}
