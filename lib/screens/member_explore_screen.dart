import 'dart:async';
import '../theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'library_public_profile_screen.dart';
import '../utils/error_messages.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isSearching = false;
  String? _errorMessage;

  List<Map<String, dynamic>> _allLibraries = [];
  List<Map<String, dynamic>> _filteredLibraries = [];
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  // Suggest Form Controllers
  final _suggestNameController = TextEditingController();
  final _suggestLocController = TextEditingController();
  final _suggestOwnerController = TextEditingController();
  bool _isSubmittingSuggestion = false;

  @override
  void initState() {
    super.initState();
    _loadLibraries();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    _suggestNameController.dispose();
    _suggestLocController.dispose();
    _suggestOwnerController.dispose();
    super.dispose();
  }

  Future<void> _loadLibraries() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _supabase
          .from('libraries')
          .select('id, name, address_city, address_street, verified, photos, amenities, library_code, status, rules, avg_rating, review_count, created_at, shifts(id, name, price_monthly, trial_days, start_time, end_time)')
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(50);
      
      if (mounted) {
        setState(() {
          _allLibraries = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading libraries in Explore: $e');
      // Fallback
      try {
        final fallbackRes = await _supabase
            .from('libraries')
            .select('id, name, address_city, verified, photos, amenities, library_code, status, avg_rating, review_count, shifts(id, name, price_monthly, trial_days, start_time, end_time)')
            .eq('status', 'active')
            .limit(50);
        if (mounted) {
          setState(() {
            _allLibraries = List<Map<String, dynamic>>.from(fallbackRes);
            _isLoading = false;
          });
        }
      } catch (e2) {
        if (mounted) {
          setState(() {
            _errorMessage = friendlyError(e2);
            _isLoading = false;
          });
        }
      }
    }
  }

  void _onSearchChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _searchLibraries();
    });
  }

  // Server-side search: push the name/city/code filter to PostgREST (ilike) with
  // a bounded result set, so search covers the whole DB — not just the capped
  // browse list — without downloading every library to the client. (audit P1)
  Future<void> _searchLibraries() async {
    final raw = _searchController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _filteredLibraries = [];
        _isSearching = false;
      });
      return;
    }
    // Sanitize: strip chars that would break the PostgREST or() filter grammar.
    final q = raw.replaceAll(RegExp(r'[,()%*:\\]'), ' ').trim();
    if (q.isEmpty) {
      setState(() => _filteredLibraries = []);
      return;
    }

    setState(() => _isSearching = true);
    try {
      final res = await _supabase
          .from('libraries')
          .select('id, name, address_city, address_street, verified, photos, amenities, library_code, status, rules, avg_rating, review_count, created_at, shifts(id, name, price_monthly, trial_days, start_time, end_time)')
          .eq('status', 'active')
          .or('name.ilike.%$q%,address_city.ilike.%$q%,library_code.ilike.%$q%')
          .order('name', ascending: true)
          .limit(50);

      // Drop stale results if the user kept typing while this query was in flight.
      if (!mounted || _searchController.text.trim() != raw) return;
      setState(() {
        _filteredLibraries = List<Map<String, dynamic>>.from(res);
        _isSearching = false;
      });
    } catch (e) {
      debugPrint('Explore search failed: $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }



  void _openJoinWithCodeSheet() {
    final codeCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 20, right: 20, top: 20
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Join with Library Code', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 16),
              
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                onChanged: (val) {
                  String clean = val.replaceAll('-', '').toUpperCase();
                  if (clean.length > 3) {
                    clean = '${clean.substring(0, 3)}-${clean.substring(3)}';
                  }
                  if (clean.length > 10) {
                    clean = '${clean.substring(0, 10)}-${clean.substring(10)}';
                  }
                  codeCtrl.value = TextEditingValue(
                    text: clean,
                    selection: TextSelection.fromPosition(TextPosition(offset: clean.length)),
                  );
                },
                decoration: const InputDecoration(
                  labelText: 'Library Code',
                  hintText: 'e.g. SIL-4K9M-2P',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final code = codeCtrl.text.trim();
                    if (code.isEmpty) return;
                    
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    
                    try {
                      final libRes = await _supabase
                          .from('libraries')
                          .select()
                          .eq('library_code', code)
                          .maybeSingle();
                      
                      if (libRes == null) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Library not found. Check code prefix or suffix.')),
                        );
                        return;
                      }
                      
                      navigator.pop();
                      navigator.push(
                        MaterialPageRoute(
                          builder: (context) => LibraryPublicProfileScreen(
                            libraryId: libRes['id'],
                            isAdmin: false,
                            showProceedButton: true,
                          ),
                        ),
                      );
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text(friendlyError(e))),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Find Library'),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitSuggestion() async {
    final name = _suggestNameController.text.trim();
    final loc = _suggestLocController.text.trim();
    final phone = _suggestOwnerController.text.trim();

    if (name.isEmpty || loc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields.')),
      );
      return;
    }

    setState(() => _isSubmittingSuggestion = true);

    try {
      // Gracefully insert lead. If the table doesn't exist, this will error and catch.
      await _supabase.from('leads').insert({
        'library_name': name,
        'location': loc,
        'owner_phone': phone.isNotEmpty ? phone : null,
        'suggested_by_member_id': _supabase.auth.currentUser?.id,
        'created_at': DateTime.now().toIso8601String(),
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you! Library suggestion submitted successfully. ✓'),
            backgroundColor: Color(0xFF22C55E),
          ),
        );
      }
    } catch (e) {
      debugPrint('Leads insert failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
      // Do NOT clear the form on failure — keep the user's input so they can retry.
      if (mounted) setState(() => _isSubmittingSuggestion = false);
      return;
    }
    // Success path only: clear the form.
    if (mounted) {
      setState(() {
        _isSubmittingSuggestion = false;
        _suggestNameController.clear();
        _suggestLocController.clear();
        _suggestOwnerController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE65C00),
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: context.palette.scaffold,
          body: Column(
            children: [
              _buildOrangeHeader(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
                    : _errorMessage != null
                        ? _buildErrorState()
                        : _buildMainContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrangeHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFE65C00),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              Text(
                'Find a Study Zone',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Colors.white),
                onPressed: () {
                  // Push to standard notifications screen if available
                  Navigator.pushNamed(context, '/member/notifications');
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Search Bar
          Container(
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 4)),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search library, city or code...',
                hintStyle: GoogleFonts.inter(color: Colors.grey[400], fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              'Failed to load libraries',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error occurred.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadLibraries,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final query = _searchController.text.trim();
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Join with code button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openJoinWithCodeSheet,
              icon: const Icon(Icons.vpn_key_outlined, size: 18),
              label: const Text('Join with Code'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: Color(0xFFE65C00), width: 1.5),
                foregroundColor: const Color(0xFFE65C00),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            query.isEmpty ? 'Explore Study Zones' : 'Search Results',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.palette.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // Search condition
          if (query.isEmpty)
            _buildBrowseList()
          else if (_isSearching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_filteredLibraries.isEmpty)
            _buildNoResultsState()
          else
            ..._filteredLibraries.map((lib) => _buildExploreLibraryCard(lib)),

          const SizedBox(height: 32),
          _buildSuggestForm(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildBrowseList() {
    if (_allLibraries.isEmpty) {
      return _buildEmptyState();
    }

    // Build a sorted browse view: highest rated first, then most reviewed,
    // then newest. Gives members something to explore without typing.
    final List<Map<String, dynamic>> browse = List.from(_allLibraries);
    browse.sort((a, b) {
      final aRating = (a['avg_rating'] as num?)?.toDouble() ?? 0.0;
      final bRating = (b['avg_rating'] as num?)?.toDouble() ?? 0.0;
      if (aRating != bRating) return bRating.compareTo(aRating);
      final aReviews = (a['review_count'] as num?)?.toInt() ?? 0;
      final bReviews = (b['review_count'] as num?)?.toInt() ?? 0;
      if (aReviews != bReviews) return bReviews.compareTo(aReviews);
      final aCreated = (a['created_at'] ?? '').toString();
      final bCreated = (b['created_at'] ?? '').toString();
      return bCreated.compareTo(aCreated);
    });

    // Recently added: newest 3 by created_at, flagged with a NEW badge.
    final List<Map<String, dynamic>> recent = List.from(_allLibraries)
      ..sort((a, b) {
        final aCreated = (a['created_at'] ?? '').toString();
        final bCreated = (b['created_at'] ?? '').toString();
        return bCreated.compareTo(aCreated);
      });
    final recentIds = recent.take(3).map((l) => l['id']).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Helper hint
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0x14E65C00),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.explore_outlined, size: 18, color: Color(0xFFE65C00)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Browse all available study zones. Search above by name, city, or code.',
                  style: GoogleFonts.inter(fontSize: 11.5, color: context.palette.textSecondary),
                ),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Text(
            'Popular study zones',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: context.palette.textSecondary),
          ),
        ),

        ...browse.map((lib) => _buildExploreLibraryCard(lib, isNew: recentIds.contains(lib['id']))),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.search, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'Search for Study Zones',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Type a library name, city, or library code above to discover silent spaces near you.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No libraries found',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'We couldn\'t find any libraries matching "${_searchController.text}". Check spelling or search a different city.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildExploreLibraryCard(Map<String, dynamic> lib, {bool isNew = false}) {
    final name = lib['name'] ?? 'SILENCE Zone';
    final street = lib['address_street'] ?? '';
    final city = lib['address_city'] ?? 'Indore';
    String address = street.isNotEmpty ? '$street, $city' : city;
    if (address.length > 30) {
      address = '${address.substring(0, 27)}...';
    }

    final verified = lib['verified'] == true;
    final photos = lib['photos'] as List? ?? [];
    final amenities = lib['amenities'] as List? ?? [];
    final shifts = lib['shifts'] as List? ?? [];

    // Minimum starting price
    int startingPrice = 0;
    for (var s in shifts) {
      final p = s['price_monthly'] as int? ?? 999999;
      if (startingPrice == 0 || p < startingPrice) {
        startingPrice = p;
      }
    }

    final hasTrial = shifts.any((s) => (s['trial_days'] as int? ?? 0) > 0);

    // Rating
    final int reviewCount = (lib['review_count'] as num?)?.toInt() ?? 0;
    final double avgRating = (lib['avg_rating'] as num?)?.toDouble() ?? 0.0;

    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LibraryPublicProfileScreen(
                libraryId: lib['id'],
                isAdmin: false,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Area
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                  child: photos.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: photos.first.toString(),
                          height: 130,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            height: 130,
                            color: const Color(0x1FE65C00),
                            child: const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => _buildPlaceholderPhoto(),
                        )
                      : _buildPlaceholderPhoto(),
                ),
                if (isNew)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'NEW',
                        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
                      ),
                    ),
                  ),
              ],
            ),
            
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (verified) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.verified, color: Colors.blue, size: 16),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (reviewCount > 0)
                        Row(
                          children: [
                            const Icon(Icons.star, size: 12, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 4),
                            Text(
                              '${avgRating.toStringAsFixed(1)}  ($reviewCount)',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                            ),
                          ],
                        )
                      else
                        const Text(
                          'No reviews yet',
                          style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          address,
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Amenity Chips (up to 3)
                  if (amenities.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: amenities.take(3).map((a) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            a.toString(),
                            style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[700]),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Price & Badges
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        startingPrice > 0 ? 'From ₹$startingPrice/month' : 'Price TBA',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                      ),
                      if (hasTrial)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple[50],
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.purple[100]!),
                          ),
                          child: Text(
                            'Free Trial Available',
                            style: GoogleFonts.inter(fontSize: 9, color: Colors.purple[700], fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  
                  // View Profile Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LibraryPublicProfileScreen(
                              libraryId: lib['id'],
                              isAdmin: false,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65C00),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('View Profile'),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderPhoto() {
    return Container(
      height: 130,
      width: double.infinity,
      color: Colors.orange[50],
      child: const Icon(Icons.image, size: 48, color: Color(0xFFE65C00)),
    );
  }

  Widget _buildSuggestForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Don't see your library?",
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            "Suggest a library you want us to add and help expand the SILENCE network.",
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _suggestNameController,
            style: GoogleFonts.inter(fontSize: 14),
            decoration: const InputDecoration(
              labelText: 'Library Name *',
              hintText: 'e.g. Tagore Library',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _suggestLocController,
            style: GoogleFonts.inter(fontSize: 14),
            decoration: const InputDecoration(
              labelText: 'Location / City *',
              hintText: 'e.g. Geeta Nagar, Indore',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _suggestOwnerController,
            style: GoogleFonts.inter(fontSize: 14),
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Owner Phone (Optional)',
              hintText: 'e.g. 9876543210',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmittingSuggestion ? null : _submitSuggestion,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.palette.textPrimary, // Sleek Dark Slate
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _isSubmittingSuggestion
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Suggest Library'),
            ),
          )
        ],
      ),
    );
  }
}
