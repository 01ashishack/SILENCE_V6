import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/admin_settings_service.dart';

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
        backgroundColor: const Color(0xFFFBF5EE),
        body: const Center(
          child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))),
        ),
      );
    }

    if (_libraryData == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBF5EE),
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
          backgroundColor: const Color(0xFFFBF5EE),
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
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
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
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
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
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
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
                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569), height: 1.5),
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
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
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
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 4),
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
                                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.access_time, size: 12, color: Color(0xFFE65C00)),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$start - $end',
                                            style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B)),
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
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
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
                                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.01),
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
                  color: const Color(0xFF1E293B),
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
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B), fontWeight: FontWeight.w500),
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
            color: hasLink ? const Color(0xFF1E293B) : Colors.grey[400],
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
              color: hasLink ? const Color(0xFF64748B) : Colors.grey[400],
            ),
          ),
        ),
      ],
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
