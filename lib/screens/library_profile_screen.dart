import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../core/admin_settings_service.dart';
import 'admin/reply_to_review_bottom_sheet.dart';

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
  List<Map<String, dynamic>> _shifts = [];
  List<Map<String, dynamic>> _addons = [];
  List<Map<String, dynamic>> _reviews = [];
  Map<int, int> _ratingCounts = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
  int _totalReviews = 0;

  @override
  void initState() {
    super.initState();
    _libId = widget.libraryId;
    _fetchLibraryDetails();
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
    _fetchLibraryDetails();
  }

  Future<void> _fetchLibraryDetails() async {
    final String? currentLibId = _libId;
    if (currentLibId == null) return;

    setState(() => _isLoading = true);
    try {
      // 1. Fetch library details
      final libRes = await _supabase.from('libraries').select().eq('id', currentLibId).maybeSingle();
      if (libRes != null) {
        _libraryData = libRes;
      }

      // 2. Fetch shifts
      final shiftsRes = await _supabase.from('shifts').select().eq('library_id', currentLibId).eq('is_archived', false);
      _shifts = List<Map<String, dynamic>>.from(shiftsRes);

      // 3. Fetch add-ons
      final settings = await AdminSettingsService.load(
        scope: 'addon_services',
        libraryId: currentLibId,
      );
      final storedAddons = settings['items'];
      final List<Map<String, dynamic>> enrichedAddons = [];
      if (storedAddons is Map) {
        storedAddons.forEach((key, val) {
          if (val is Map) {
            enrichedAddons.add({
              'id': key,
              'name': val['name'] ?? key,
              'monthly_rate': val['monthly_rate'] ?? 0,
              'security_deposit': val['security_deposit'] ?? 0,
              'total_inventory': val['total_inventory'] ?? 0,
              'allocated_count': val['allocated_count'] ?? 0,
            });
          }
        });
      }
      _addons = enrichedAddons;

      // 4. Fetch reviews (last 5)
      final reviewsRes = await _supabase
          .from('reviews')
          .select('*, member:member_id (nickname, full_name, photo_url)')
          .eq('library_id', currentLibId)
          .order('created_at', ascending: false)
          .limit(5);
      _reviews = List<Map<String, dynamic>>.from(reviewsRes);

      // 5. Fetch all ratings to construct the summary progress bars
      final List<dynamic> ratingsRes = await _supabase
          .from('reviews')
          .select('rating')
          .eq('library_id', currentLibId);
      
      _totalReviews = ratingsRes.length;
      final Map<int, int> newCounts = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
      for (var r in ratingsRes) {
        int rating = r['rating'] ?? 0;
        if (newCounts.containsKey(rating)) {
          newCounts[rating] = newCounts[rating]! + 1;
        }
      }
      _ratingCounts = newCounts;

    } catch (e) {
      debugPrint('Error loading library profile: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_libraryData == null && _isLoading) {
      return Scaffold(
        backgroundColor: context.palette.scaffold,
        body: const Center(
          child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))),
        ),
      );
    }

    if (_libraryData == null) {
      return Scaffold(
        backgroundColor: context.palette.scaffold,
        appBar: AppBar(
          backgroundColor: const Color(0xFFE65C00),
          title: const Text('Library Profile', style: TextStyle(color: Colors.white)),
        ),
        body: Center(
          child: Text('Library details not found.', style: GoogleFonts.inter(fontSize: 14, color: Colors.grey)),
        ),
      );
    }

    final String name = _libraryData!['name'] ?? 'Study Center';
    final String city = _libraryData!['address_city'] ?? '';
    final String state = _libraryData!['address_state'] ?? '';
    final String street = _libraryData!['address_street'] ?? '';
    final String pin = _libraryData!['address_pincode'] ?? '';
    final String emergencyPhone = _libraryData!['emergency_phone'] ?? '';
    final String rules = _libraryData!['rules'] ?? 'No special rules configured yet.';
    final String? coverUrl = _libraryData!['cover_photo_url'];
    final List<dynamic> photos = _libraryData!['photos'] as List? ?? [];
    final List<dynamic> amenities = _libraryData!['amenities'] as List? ?? [];
    final Map<String, dynamic> social = _libraryData!['social_links'] as Map<String, dynamic>? ?? {};

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
              name,
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          body: RefreshIndicator(
            onRefresh: _fetchLibraryDetails,
            color: const Color(0xFFE65C00),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Basic Info Section
                  _buildSectionCard(
                    title: 'Basic Info',
                    onEdit: () => _navigateToEdit('/admin/library/setup/1'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoRow(Icons.storefront, 'Name', name),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          Icons.location_on_outlined,
                          'Address',
                          street.isNotEmpty ? '$street, $city, $state - $pin' : '$city, $state',
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(Icons.phone_callback, 'Emergency Phone', emergencyPhone.isNotEmpty ? emergencyPhone : 'Not configured'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Photos Section
                  _buildSectionCard(
                    title: 'Photos',
                    onEdit: () => _navigateToEdit('/admin/library/setup/1'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cover Photo',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: coverUrl != null && coverUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: coverUrl,
                                  height: 140,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(color: Colors.grey[200]),
                                  errorWidget: (context, url, error) => Container(
                                    color: const Color(0xFFFFF3ED),
                                    child: const Icon(Icons.image_outlined, color: Color(0xFFE65C00), size: 36),
                                  ),
                                )
                              : Container(
                                  height: 140,
                                  color: const Color(0xFFFFF3ED),
                                  child: const Center(child: Icon(Icons.image_outlined, color: Color(0xFFE65C00), size: 36)),
                                ),
                        ),
                        if (photos.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Gallery Photos',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textMuted),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 70,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: photos.length,
                              itemBuilder: (context, index) {
                                final photoUrl = photos[index].toString();
                                return Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  width: 100,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedNetworkImage(
                                      imageUrl: photoUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(color: Colors.grey[200]),
                                      errorWidget: (context, url, error) => Container(
                                        color: const Color(0xFFFFF3ED),
                                        child: const Icon(Icons.broken_image_outlined, color: Color(0xFFE65C00), size: 20),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. Amenities Section
                  _buildSectionCard(
                    title: 'Amenities',
                    onEdit: () => _navigateToEdit('/admin/library/setup/1'),
                    child: amenities.isEmpty
                        ? Text(
                            'No amenities selected yet.',
                            style: GoogleFonts.inter(fontSize: 13, color: context.palette.textMuted),
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: amenities.map((a) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF3ED),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFFFFD0B8)),
                                ),
                                child: Text(
                                  a.toString(),
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: const Color(0xFFE65C00),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                  ),
                  const SizedBox(height: 16),

                  // 4. Rules Section
                  _buildSectionCard(
                    title: 'Rules & Guidelines',
                    onEdit: () => _navigateToEdit('/admin/library/setup/1'),
                    child: Text(
                      rules,
                      style: GoogleFonts.inter(fontSize: 13, color: context.palette.textSecondary, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 5. Social Links Section
                  _buildSectionCard(
                    title: 'Social Links',
                    onEdit: () => _navigateToEdit('/admin/settings/social-links'),
                    child: Column(
                      children: [
                        _buildSocialRow(Icons.camera_alt, 'Instagram', social['instagram']),
                        const SizedBox(height: 8),
                        _buildSocialRow(Icons.video_library, 'YouTube', social['youtube']),
                        const SizedBox(height: 8),
                        _buildSocialRow(Icons.facebook, 'Facebook', social['facebook']),
                        const SizedBox(height: 8),
                        _buildSocialRow(Icons.chat_bubble, 'WhatsApp', social['whatsapp']),
                        const SizedBox(height: 8),
                        _buildSocialRow(Icons.language, 'Website', social['website']),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 6. Timings & Shifts Section
                  _buildSectionCard(
                    title: 'Timings & Shifts',
                    onEdit: () => _navigateToEdit('/admin/settings/shifts'),
                    child: _shifts.isEmpty
                        ? Text(
                            'No shifts configured yet.',
                            style: GoogleFonts.inter(fontSize: 13, color: context.palette.textMuted),
                          )
                        : SizedBox(
                            height: 80,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _shifts.length,
                              itemBuilder: (context, index) {
                                final shift = _shifts[index];
                                final name = shift['name'] ?? 'Shift';
                                final start = shift['start_time'] ?? '08:00';
                                final end = shift['end_time'] ?? '20:00';

                                return Container(
                                  width: 130,
                                  margin: const EdgeInsets.only(right: 12),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: context.palette.surface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.01), blurRadius: 4),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.access_time, size: 12, color: Color(0xFFE65C00)),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$start - $end',
                                            style: GoogleFonts.inter(fontSize: 10, color: context.palette.textMuted),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),

                  // 7. Add-on Services Section
                  _buildSectionCard(
                    title: 'Add-on Services',
                    onEdit: () => _navigateToEdit('/admin/settings/addons'),
                    child: _addons.isEmpty
                        ? Text(
                            'No add-on services configured.',
                            style: GoogleFonts.inter(fontSize: 13, color: context.palette.textMuted),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _addons.length,
                            separatorBuilder: (context, index) => const Divider(color: Color(0xFFF1F5F9), height: 16),
                            itemBuilder: (context, index) {
                              final addon = _addons[index];
                              final rate = addon['monthly_rate'] ?? 0;
                              final deposit = addon['security_deposit'] ?? 0;
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      addon['name'] ?? 'Add-on',
                                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.palette.textPrimary),
                                    ),
                                  ),
                                  Text(
                                    '₹$rate/mo ${deposit > 0 ? "(Deposit: ₹$deposit)" : ""}',
                                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFE65C00), fontWeight: FontWeight.bold),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 16),

                  // 8. Reviews & Ratings Section
                  _buildReviewsSection(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required VoidCallback onEdit,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: context.palette.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFFE65C00)),
                onPressed: onEdit,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFFE65C00)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: context.palette.textMuted),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.inter(fontSize: 13, color: context.palette.textPrimary, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSocialRow(IconData icon, String label, dynamic value) {
    final String displayVal = value?.toString().trim() ?? '';
    final bool hasLink = displayVal.isNotEmpty;

    return Row(
      children: [
        Icon(icon, size: 16, color: hasLink ? const Color(0xFFE65C00) : Colors.grey[400]),
        const SizedBox(width: 12),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: hasLink ? context.palette.textPrimary : Colors.grey[400],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            hasLink ? displayVal : 'Not linked',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: hasLink ? context.palette.textMuted : Colors.grey[400],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewsSection() {
    final double avgRating = (_libraryData!['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final int reviewCount = _libraryData!['review_count'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Ratings & Reviews',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // A) Rating Summary Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Avg Rating
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.star, size: 24, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 4),
                        Text(
                          avgRating.toStringAsFixed(1),
                          style: GoogleFonts.outfit(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: context.palette.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '($reviewCount reviews)',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: context.palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Vertical Divider
              Container(
                height: 100,
                width: 1,
                color: const Color(0xFFE2E8F0),
              ),
              const SizedBox(width: 16),
              // Right: Progress bars
              Expanded(
                flex: 3,
                child: Column(
                  children: List.generate(5, (index) {
                    final int starValue = 5 - index;
                    final int count = _ratingCounts[starValue] ?? 0;
                    final double percentage = _totalReviews > 0 ? (count / _totalReviews) : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Row(
                        children: [
                          Text(
                            '$starValue★',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: context.palette.textMuted,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: percentage,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE65C00),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 16,
                            child: Text(
                              '$count',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: context.palette.textMuted,
                              ),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // B) Individual Review Rows
        if (_reviews.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Center(
              child: Text(
                'No reviews yet',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey),
              ),
            ),
          )
        else ...[
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _reviews.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final review = _reviews[index];
              return _buildReviewItem(review);
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  '/admin/all-reviews',
                  arguments: _libId,
                ).then((_) {
                  _fetchLibraryDetails();
                });
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View All Reviews',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFE65C00),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward, size: 12, color: Color(0xFFE65C00)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReviewItem(Map<String, dynamic> review) {
    final member = review['member'] as Map<String, dynamic>?;
    final nickname = member?['nickname'];
    final fullName = member?['full_name'];
    String displayName = 'Member';
    if (nickname != null && nickname.toString().trim().isNotEmpty) {
      displayName = nickname.toString().trim();
    } else if (fullName != null && fullName.toString().trim().isNotEmpty) {
      displayName = fullName.toString().trim().split(' ').first;
    }

    final photoUrl = member?['photo_url'];
    final rating = review['rating'] as int? ?? 0;
    final reviewText = review['review_text'];
    final createdAtStr = review['created_at'];
    final formattedDate = createdAtStr != null
        ? DateFormat('dd MMM yyyy').format(DateTime.parse(createdAtStr).toLocal())
        : '';

    final replyText = review['admin_reply'];
    final hasReplied = replyText != null && replyText.toString().trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row with Avatar, Name, and Stars
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: context.palette.scaffold,
                backgroundImage: (photoUrl != null && photoUrl.toString().isNotEmpty)
                    ? NetworkImage(photoUrl)
                    : null,
                child: (photoUrl == null || photoUrl.toString().isEmpty)
                    ? const Icon(Icons.person, size: 18, color: Color(0xFFE65C00))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: context.palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formattedDate,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: context.palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (starIdx) {
                  return Icon(
                    starIdx < rating ? Icons.star : Icons.star_border,
                    size: 14,
                    color: starIdx < rating ? const Color(0xFFF59E0B) : Colors.grey[300],
                  );
                }),
              ),
            ],
          ),
          if (reviewText != null && reviewText.toString().trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '"$reviewText"',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: context.palette.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (!hasReplied)
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: () => _openReplyBottomSheet(review),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Reply',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFE65C00),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.arrow_forward, size: 12, color: Color(0xFFE65C00)),
                  ],
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.palette.scaffold,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFD0B8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Admin reply: "$replyText"',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Replied ${DateFormat('dd MMM yyyy').format(DateTime.parse(review['admin_replied_at']).toLocal())}',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: context.palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _openReplyBottomSheet(Map<String, dynamic> review) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return ReplyToReviewBottomSheet(
          review: review,
          onReplySent: _fetchLibraryDetails,
        );
      },
    );
  }

  void _navigateToEdit(String routeName) {
    Navigator.pushNamed(
      context,
      routeName,
      arguments: _libId,
    ).then((val) {
      _fetchLibraryDetails();
    });
  }
}
