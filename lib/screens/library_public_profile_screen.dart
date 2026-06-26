import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'reservations/join_flow_screen.dart';
import 'member_profile_edit.dart';
import '../services/notification_service.dart';


class LibraryPublicProfileScreen extends StatefulWidget {
  final String? libraryId;
  final bool isAdmin;
  final bool showProceedButton;

  const LibraryPublicProfileScreen({
    super.key,
    this.libraryId,
    this.isAdmin = false,
    this.showProceedButton = false,
  });

  @override
  State<LibraryPublicProfileScreen> createState() => _LibraryPublicProfileScreenState();
}

class _LibraryPublicProfileScreenState extends State<LibraryPublicProfileScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;

  String get libraryId {
    if (widget.libraryId != null) return widget.libraryId!;
    final args = ModalRoute.of(context)!.settings.arguments;
    if (args is String) return args;
    if (args is Map) return args['libraryId'] as String;
    throw Exception("Library ID is missing");
  }

  bool get showProceedButton {
    if (widget.showProceedButton) return true;
    final args = ModalRoute.of(context)!.settings.arguments;
    if (args is Map) return args['showProceedButton'] == true;
    return false;
  }

  // Database Data
  Map<String, dynamic>? _library;
  List<Map<String, dynamic>> _shifts = [];
  List<Map<String, dynamic>> _reviews = [];
  bool _hasActiveMembership = false;
  bool _hasReviewed = false;
  int _membersServed = 0; // distinct members who have ever joined this library

  // Active UI States
  double _avgRating = 0.0;
  int _reviewCount = 0;
  String _selectedReviewFilter = 'Latest';
  int _reviewsPageLimit = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadPublicData();
      }
    });
  }

  Future<void> _checkAndJoinLibrary({String? shiftId}) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first.')),
      );
      return;
    }

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
        ),
      ),
    );

    try {
      // Guard: if the user is ALREADY an active member of this library, do not
      // send them through the join flow again (this is what happened when an
      // existing member scanned the join QR). Show their status + how to check in.
      final activeMs = await supabase
          .from('memberships')
          .select('status')
          .eq('member_id', user.id)
          .eq('library_id', libraryId)
          .inFilter('status', ['active', 'trial', 'hold', 'expired', 'pending'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (activeMs != null) {
        navigator.pop();
        if (mounted) _showAlreadyMemberDialog((activeMs['status'] ?? 'active').toString());
        return;
      }

      final profileRes = await supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      navigator.pop();

      bool complete = false;
      if (profileRes != null) {
        final reqs = [
          'full_name', 'phone', 'nickname', 'gender', 'date_of_birth',
          'address', 'exam_category', 'photo_url', 'id_proof_url'
        ];
        complete = reqs.every((field) => 
          profileRes[field] != null && profileRes[field].toString().trim().isNotEmpty
        );
      }

      if (!complete) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (dialogCtx) => AlertDialog(
              title: Text('Complete Your Profile', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              content: const Text('Please complete your profile before joining a library.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    navigator.push(
                      MaterialPageRoute(builder: (_) => const MemberProfileEditScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Edit Profile', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
        return;
      }

      navigator.push(
        MaterialPageRoute(
          builder: (dialogCtx) => JoinFlowScreen(
            libraryId: libraryId,
            initialShiftId: shiftId,
          ),
        ),
      ).then((_) {
        if (mounted) {
          _loadPublicData();
        }
      });
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Error validating profile: $e')),
      );
    }
  }

  /// Shown when an EXISTING member opens/scans the join QR — they should not
  /// re-run the join flow. Tells them they're already a member and that check
  /// in/out uses a different (attendance) QR.
  void _showAlreadyMemberDialog(String status) {
    final pretty = status == 'pending'
        ? 'Your membership request is awaiting admin approval.'
        : status == 'expired'
            ? 'Your membership here has expired — renew it from your home screen.'
            : status == 'hold'
                ? 'Your membership here is currently on hold.'
                : "You're already a member of this library.";
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.verified_user_rounded, color: Color(0xFF22C55E), size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Already a member',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pretty,
                style: GoogleFonts.inter(fontSize: 13.5, height: 1.4, color: context.palette.textSecondary)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFD1B3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner_rounded, size: 18, color: Color(0xFFB45309)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This is the JOIN QR. To check in or out, scan the library\'s '
                      'attendance QR instead.',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF92400E), height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65C00),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: Text('Got it', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadPublicData() async {
    setState(() => _isLoading = true);

    try {
      final user = _supabase.auth.currentUser;

      // 1. Fetch library details
      final libRes = await _supabase
          .from('libraries')
          .select()
          .eq('id', libraryId)
          .maybeSingle();
      if (!mounted) return;
      _library = libRes;

      // 2. Fetch library shifts
      final shiftsRes = await _supabase
          .from('shifts')
          .select()
          .eq('library_id', libraryId)
          .eq('is_archived', false);
      if (!mounted) return;
      _shifts = List<Map<String, dynamic>>.from(shiftsRes);

      // 2b. Members served — distinct members who have ever joined (any status).
      // Honest "trusted by N students" social-proof stat.
      try {
        final msRes = await _supabase
            .from('memberships')
            .select('member_id')
            .eq('library_id', libraryId);
        final distinct = List<Map<String, dynamic>>.from(msRes)
            .map((m) => m['member_id'])
            .where((id) => id != null)
            .toSet();
        _membersServed = distinct.length;
      } catch (e) {
        debugPrint('Error counting members served: $e');
      }

      // 3. Fetch reviews
      try {
        final reviewsRes = await _supabase
            .from('reviews')
            .select()
            .eq('library_id', libraryId)
            .order('created_at', ascending: false);
        if (mounted) {
          _reviews = List<Map<String, dynamic>>.from(reviewsRes);

          // 4. Enrich reviews with nicknames from users table
          for (var review in _reviews) {
            final memberId = review['member_id'];
            final memberRes = await _supabase
                .from('users')
                .select('nickname, full_name')
                .eq('id', memberId)
                .maybeSingle();
            if (memberRes != null) {
              review['nickname'] = memberRes['nickname'] ?? memberRes['full_name'] ?? 'Anonymous';
            } else {
              review['nickname'] = 'Anonymous';
            }
          }

          // 5. Calculate ratings
          if (_reviews.isNotEmpty) {
            final totalRating = _reviews.fold<int>(0, (sum, item) => sum + (item['rating'] as int));
            _avgRating = totalRating / _reviews.length;
            _reviewCount = _reviews.length;
          } else {
            _avgRating = 0.0;
            _reviewCount = 0;
          }
        }
      } catch (e) {
        debugPrint('Error fetching reviews: $e');
        _reviews = [];
        _avgRating = 0.0;
        _reviewCount = 0;
      }

      // 6. Check review restrictions if user is logged in
      if (user != null) {
        // Active membership check
        final membershipRes = await _supabase
            .from('memberships')
            .select('id')
            .eq('member_id', user.id)
            .eq('library_id', libraryId)
            .neq('status', 'pending')
            .limit(1)
            .maybeSingle();
        _hasActiveMembership = membershipRes != null;

        // Already reviewed check
        try {
          final userReviewRes = await _supabase
              .from('reviews')
              .select('id')
              .eq('member_id', user.id)
              .eq('library_id', libraryId)
              .maybeSingle();
          _hasReviewed = userReviewRes != null;
        } catch (_) {
          _hasReviewed = false;
        }
      }
    } catch (e) {
      debugPrint('Error loading public profile: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatTime(String time24) {
    if (time24.isEmpty) return '';
    try {
      final parts = time24.split(':');
      if (parts.isEmpty) return time24;
      final hour = int.parse(parts[0]);
      final minute = parts.length > 1 ? int.parse(parts[1]) : 0;
      final dt = DateTime(2026, 1, 1, hour, minute);
      return DateFormat.jm().format(dt);
    } catch (_) {
      return time24;
    }
  }

  // Mini stat used in the public-profile quick-stats strip.
  Widget _publicStat(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFFE65C00)),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _publicStatDivider() {
    return Container(width: 1, height: 34, color: const Color(0xFFE2E8F0));
  }

  String _getOperatingHours(List<dynamic> shifts) {
    if (shifts.isEmpty) return "Hours Not Configured";
        
    int minMin = 1440;
    int maxMin = 0;
    bool covers24h = false;
    bool hasHourly = false;
    
    for (var shift in shifts) {
      final shiftType = shift['shift_type'] as String? ?? 'fixed';
      if (shiftType == 'hourly') {
        hasHourly = true;
        continue;
      }
      
      final startStr = shift['start_time'] as String?;
      final endStr = shift['end_time'] as String?;
      if (startStr != null && endStr != null) {
        try {
          final startParts = startStr.split(':');
          final endParts = endStr.split(':');
          
          final startHour = int.parse(startParts[0]);
          final startMin = int.parse(startParts[1]);
          
          final endHour = int.parse(endParts[0]);
          final endMin = int.parse(endParts[1]);
          
          int startMinutes = startHour * 60 + startMin;
          int endMinutes = endHour * 60 + endMin;
          
          if (endMinutes < startMinutes) {
            endMinutes += 1440; 
          }
          
          if (startMinutes < minMin) minMin = startMinutes;
          if (endMinutes > maxMin) maxMin = endMinutes;
          
          if ((endMinutes - startMinutes) >= 1440) {
            covers24h = true;
          }
        } catch (_) {}
      }
    }
    
    if (covers24h || (maxMin - minMin) >= 1440) {
      return "Open 24 Hours";
    }
    
    if (minMin == 1440 || maxMin == 0) {
      if (hasHourly) {
        return "Hourly Slots Available";
      }
      return "Hours Not Configured";
    }
    
    String formatMinutes(int totalMin) {
      final h = (totalMin ~/ 60) % 24;
      final m = totalMin % 60;
      final period = h >= 12 ? "PM" : "AM";
      final displayHour = h % 12 == 0 ? 12 : h % 12;
      final displayMin = m.toString().padLeft(2, '0');
      return "$displayHour:$displayMin $period";
    }
    
    String fixedHours = "${formatMinutes(minMin)} – ${formatMinutes(maxMin)}";
    if (hasHourly) {
      return "$fixedHours (Hourly Slots Available)";
    }
    return fixedHours;
  }

  Future<void> _launchURL(String urlString) async {
    try {
      final Uri uri = Uri.parse(urlString);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $uri');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open page: $e')),
        );
      }
    }
  }

  void _writeReviewBottomSheet() {
    int selectedRating = 5;
    final commentCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 24, left: 24, right: 24
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Write a Review',
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                  ),
                  const SizedBox(height: 16),
                  
                  // Stars Selector
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starVal = index + 1;
                      return IconButton(
                        icon: Icon(
                          starVal <= selectedRating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 32,
                        ),
                        onPressed: () {
                          setSheetState(() => selectedRating = starVal);
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: commentCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Share your experience studying here (amenities, silence level, behavior of admin)...',
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final user = _supabase.auth.currentUser;
                        if (user == null) return;
                        
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        
                        try {
                          await _supabase.from('reviews').insert({
                            'library_id': libraryId,
                            'member_id': user.id,
                            'rating': selectedRating,
                            'review_text': commentCtrl.text.trim(),
                          });

                          // Notify the library owner about the new review.
                          await NotificationService.notifyLibraryOwner(
                            libraryId: libraryId,
                            title: 'New review',
                            body: 'A member left a $selectedRating★ review on your library.',
                            type: 'new_review',
                          );

                          navigator.pop();
                          if (mounted) {
                            _loadPublicData();
                          }
                        } catch (e) {
                          String errorMsg = e.toString();
                          if (errorMsg.contains('23505') || errorMsg.contains('unique_review') || errorMsg.contains('duplicate key')) {
                            errorMsg = 'You have already submitted a review for this library.';
                          }
                          messenger.showSnackBar(
                            SnackBar(content: Text(errorMsg)),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65C00),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Submit Review'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _adminReplyBottomSheet(Map<String, dynamic> review) {
    final replyCtrl = TextEditingController(text: review['admin_reply'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            top: 24, left: 24, right: 24
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                review['admin_reply'] != null ? 'Edit Admin Reply' : 'Add Admin Reply',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: replyCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Type your reply as the library administrator...',
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await _supabase.from('reviews').update({
                        'admin_reply': replyCtrl.text.trim(),
                        'replied_at': DateTime.now().toIso8601String(),
                      }).eq('id', review['id']);

                      navigator.pop();
                      if (mounted) {
                        _loadPublicData();
                      }
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Error saving reply: $e')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Save Reply'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFullImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFBF5EE),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFE65C00))),
      );
    }

    if (_library == null) {
      return Scaffold(
        backgroundColor: context.palette.scaffold,
        appBar: AppBar(backgroundColor: const Color(0xFFE65C00), title: const Text('Not Found')),
        body: const Center(child: Text('Library not found.')),
      );
    }

    final name = _library!['name'] ?? 'SILENCE Space';
    final addressCity = _library!['address_city'] ?? '';
    final addressState = _library!['address_state'] ?? '';
    final addressStreet = _library!['address_street'] ?? '';
    final addressPin = _library!['address_pincode'] ?? '';
    final aboutText = _library!['about_text'] as String?;
    final photos = _library!['photos'] as List? ?? [];
    final amenities = _library!['amenities'] as List? ?? [];
    final emergency = _library!['emergency_phone'] as String?;
    final locationLink = _library!['location_link'] as String?;

    final List<Map<String, dynamic>> allPlans = [];
    for (var shift in _shifts) {
      final sName = shift['name'] ?? 'Shift';
      final sStart = shift['start_time'] ?? '00:00';
      final sEnd = shift['end_time'] ?? '00:00';
      final shiftType = shift['shift_type'] ?? 'fixed';
      final hoursPerDay = shift['hours_per_day'] ?? 4;

      String timings = "";
      if (shiftType == 'hourly') {
        timings = "$hoursPerDay hours/day";
      } else {
        timings = "${_formatTime(sStart)} – ${_formatTime(sEnd)}";
      }

      final mPrice = shift['price_monthly'] ?? 0;
      final tPrice = shift['price_3month'] ?? 0;
      final sPrice = shift['price_6month'] ?? 0;

      if (mPrice > 0) {
        allPlans.add({
          'planName': 'Monthly',
          'price': mPrice,
          'priceSuffix': '/month',
          'shiftName': sName,
          'timings': timings,
          'shiftId': shift['id'],
        });
      }
      if (tPrice > 0) {
        allPlans.add({
          'planName': '3-Month',
          'price': tPrice,
          'priceSuffix': '/3 months',
          'shiftName': sName,
          'timings': timings,
          'shiftId': shift['id'],
        });
      }
      if (sPrice > 0) {
        allPlans.add({
          'planName': '6-Month',
          'price': sPrice,
          'priceSuffix': '/6 months',
          'shiftName': sName,
          'timings': timings,
          'shiftId': shift['id'],
        });
      }
    }

    List<Map<String, dynamic>> filteredReviews = List.from(_reviews);
    if (_selectedReviewFilter == 'Bad Review') {
      filteredReviews = filteredReviews.where((r) => (r['rating'] as int) <= 2).toList();
    } else if (_selectedReviewFilter == 'Top Review') {
      filteredReviews = filteredReviews.where((r) => (r['rating'] as int) >= 4).toList();
    }
    // Sort
    if (_selectedReviewFilter == 'Latest') {
      filteredReviews.sort((a, b) {
        final aDate = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
    } else if (_selectedReviewFilter == 'Bad Review') {
      filteredReviews.sort((a, b) {
        final rComp = (a['rating'] as int).compareTo(b['rating'] as int);
        if (rComp != 0) return rComp;
        final aDate = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
    } else if (_selectedReviewFilter == 'Top Review') {
      filteredReviews.sort((a, b) {
        final rComp = (b['rating'] as int).compareTo(a['rating'] as int);
        if (rComp != 0) return rComp;
        final aDate = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
    }
    final showLoadMore = filteredReviews.length > _reviewsPageLimit;
    final reviewsToShow = filteredReviews.take(_reviewsPageLimit).toList();
    final fullAddress = "$addressStreet, $addressCity, $addressState $addressPin";
    final coverPhoto = photos.isNotEmpty ? photos.first.toString() : '';

    return Scaffold(
      backgroundColor: context.palette.scaffold,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Cover Photo Header Stack
            Stack(
              children: [
                coverPhoto.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: coverPhoto,
                        height: 250,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(height: 250, color: Colors.grey[300]),
                        errorWidget: (context, url, error) => Container(height: 250, color: Colors.orange[50], child: const Icon(Icons.image, size: 64)),
                      )
                    : Container(
                        height: 250,
                        color: Colors.orange[50],
                        child: const Icon(Icons.storefront, size: 64, color: Color(0xFFE65C00)),
                      ),
                Container(
                  height: 250,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  left: 16,
                  child: CircleAvatar(
                    backgroundColor: Colors.black45,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "$addressStreet, $addressCity",
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Colors.white.withValues(alpha: 0.8)),
                          const SizedBox(width: 6),
                          Text(
                            (_library?['opening_hours'] ?? '').toString().trim().isNotEmpty
                                ? _library!['opening_hours'].toString()
                                : _getOperatingHours(_shifts),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.star, size: 14, color: Colors.amber[300]),
                          const SizedBox(width: 4),
                          Text(
                            _reviewCount > 0 ? "${_avgRating.toStringAsFixed(1)} ★ ($_reviewCount reviews)" : "No reviews yet",
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick stats (social proof): members served · rating · reviews
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    decoration: BoxDecoration(
                      color: context.palette.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      children: [
                        _publicStat(
                          Icons.groups_rounded,
                          (_library?['display_members_joined'] ?? '').toString().trim().isNotEmpty
                              ? _library!['display_members_joined'].toString()
                              : (_membersServed > 0 ? '$_membersServed' : '—'),
                          'Members joined',
                        ),
                        _publicStatDivider(),
                        _publicStat(Icons.star_rounded, _reviewCount > 0 ? _avgRating.toStringAsFixed(1) : '—', 'Rating'),
                        _publicStatDivider(),
                        _publicStat(Icons.rate_review_outlined, '$_reviewCount', 'Reviews'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 2. Amenities Section
                  if (amenities.isNotEmpty) ...[
                    Text(
                      'Amenities Available',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: amenities.map((a) {
                        return Chip(
                          label: Text(a.toString(), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                          backgroundColor: context.palette.surface,
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // 3. Membership Plans Section
                  if (allPlans.isNotEmpty) ...[
                    Text(
                      'Membership Plans',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 240,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: allPlans.length,
                        itemBuilder: (context, index) {
                          return _buildPlanCard(allPlans[index]);
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // 4. Gallery Section
                  if (photos.isNotEmpty) ...[
                    Text(
                      'Photo Gallery',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 80,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: photos.length,
                        itemBuilder: (context, index) {
                          final photoUrl = photos[index].toString();
                          return GestureDetector(
                            onTap: () => _showFullImage(photoUrl),
                            child: Container(
                              margin: const EdgeInsets.only(right: 12),
                              width: 100,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: photoUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(color: Colors.grey[200]),
                                  errorWidget: (context, url, error) => const Icon(Icons.image),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // 5. About Section
                  Text(
                    'About',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (aboutText != null && aboutText.trim().isNotEmpty) ? aboutText : 'No description provided.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.5,
                      color: (aboutText != null && aboutText.trim().isNotEmpty) ? context.palette.textSecondary : Colors.grey[500],
                      fontStyle: (aboutText != null && aboutText.trim().isNotEmpty) ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 6. Location & Direction
                  Text(
                    'Location Details',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.palette.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_on, color: Color(0xFFE65C00)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                fullAddress,
                                style: GoogleFonts.inter(fontSize: 13, color: context.palette.textSecondary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            final targetLink = (locationLink != null && locationLink.isNotEmpty)
                                ? locationLink
                                : "https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(fullAddress)}";
                            _launchURL(targetLink);
                          },
                          icon: const Icon(Icons.navigation),
                          label: const Text('Get Directions'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.palette.textPrimary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 7. Contact Info
                  if (emergency != null && emergency.trim().isNotEmpty) ...[
                    Text(
                      'Contact Admin',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _launchURL("tel:$emergency"),
                            icon: const Icon(Icons.phone),
                            label: const Text('Call'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.palette.surface,
                              foregroundColor: Colors.green[700],
                              side: BorderSide(color: Colors.green[700]!),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              final cleanPhone = emergency.replaceAll(RegExp(r'\D'), '');
                              final targetWhatsApp = "https://wa.me/91$cleanPhone";
                              _launchURL(targetWhatsApp);
                            },
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: const Text('WhatsApp'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],

                  // 8. Ratings & Reviews Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'User Reviews',
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                      ),
                      if (_hasActiveMembership && !_hasReviewed && !widget.isAdmin)
                        TextButton.icon(
                          onPressed: _writeReviewBottomSheet,
                          icon: const Icon(Icons.rate_review, size: 16, color: Color(0xFFE65C00)),
                          label: Text(
                            'Write Review',
                            style: GoogleFonts.inter(color: const Color(0xFFE65C00), fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildRatingSummary(),
                  const SizedBox(height: 16),
                  if (_reviews.isEmpty)
                    Card(
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.rate_review_outlined, size: 40, color: Colors.grey[400]),
                              const SizedBox(height: 8),
                              Text(
                                'No reviews yet. Be the first to review!',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: context.palette.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else ...[
                    // Filter chips
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _buildReviewFilterChip('Latest'),
                          const SizedBox(width: 8),
                          _buildReviewFilterChip('Bad Review'),
                          const SizedBox(width: 8),
                          _buildReviewFilterChip('Top Review'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (reviewsToShow.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(
                          child: Text(
                            'No reviews match this filter.',
                            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500]),
                          ),
                        ),
                      )
                    else
                      Column(
                        children: [
                          ...reviewsToShow.map((r) => _buildReviewCard(r)),
                          if (showLoadMore)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: OutlinedButton(
                                onPressed: () {
                                  setState(() {
                                    _reviewsPageLimit += 10;
                                  });
                                },
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFE65C00)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: Text(
                                  'Load More',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFE65C00),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: (!widget.isAdmin)
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: ElevatedButton(
                onPressed: () {
                  _checkAndJoinLibrary();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  showProceedButton ? 'Proceed to Join' : 'Join Library Spaces',
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final planName = plan['planName'];
    final price = plan['price'];
    final suffix = plan['priceSuffix'];
    final shiftName = plan['shiftName'];
    final timings = plan['timings'];

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(14), // Reduced from 18 to 14
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              planName,
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: context.palette.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '₹$price',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFE65C00),
                    ),
                  ),
                  TextSpan(
                    text: ' $suffix',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: context.palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.schedule, size: 12, color: Color(0xFFE65C00)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '$shiftName • $timings',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 12),
            _buildFeatureRow('High-speed Wi-Fi'),
            const SizedBox(height: 3),
            _buildFeatureRow('Comfortable Seating'),
            const SizedBox(height: 3),
            _buildFeatureRow('Power Socket & RO Water'),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(String text) {
    return Row(
      children: [
        const Text('✅ ', style: TextStyle(fontSize: 11)),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              color: context.palette.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewFilterChip(String filterVal) {
    final isSelected = _selectedReviewFilter == filterVal;
    return ChoiceChip(
      label: Text(filterVal),
      selected: isSelected,
      selectedColor: const Color(0xFFE65C00),
      labelStyle: GoogleFonts.inter(
        color: isSelected ? Colors.white : context.palette.textSecondary,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
      onSelected: (val) {
        if (val) {
          setState(() {
            _selectedReviewFilter = filterVal;
            _reviewsPageLimit = 10;
          });
        }
      },
    );
  }

  String _getRelativeTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      final diff = DateTime.now().difference(date);
      if (diff.inDays >= 365) {
        final yr = diff.inDays ~/ 365;
        return "$yr year${yr > 1 ? 's' : ''} ago";
      } else if (diff.inDays >= 30) {
        final mo = diff.inDays ~/ 30;
        return "$mo month${mo > 1 ? 's' : ''} ago";
      } else if (diff.inDays >= 7) {
        final wk = diff.inDays ~/ 7;
        return "$wk week${wk > 1 ? 's' : ''} ago";
      } else if (diff.inDays >= 1) {
        return "${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago";
      } else if (diff.inHours >= 1) {
        return "${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago";
      } else if (diff.inMinutes >= 1) {
        return "${diff.inMinutes} minute${diff.inMinutes > 1 ? 's' : ''} ago";
      } else {
        return 'just now';
      }
    } catch (_) {
      return '';
    }
  }

  Widget _buildRatingSummary() {
    int total = _reviews.length;
    int c5 = _reviews.where((r) => r['rating'] == 5).length;
    int c4 = _reviews.where((r) => r['rating'] == 4).length;
    int c3 = _reviews.where((r) => r['rating'] == 3).length;
    int c2 = _reviews.where((r) => r['rating'] == 2).length;
    int c1 = _reviews.where((r) => r['rating'] == 1).length;

    double p5 = total == 0 ? 0.0 : c5 / total;
    double p4 = total == 0 ? 0.0 : c4 / total;
    double p3 = total == 0 ? 0.0 : c3 / total;
    double p2 = total == 0 ? 0.0 : c2 / total;
    double p1 = total == 0 ? 0.0 : c1 / total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _reviewCount > 0 ? _avgRating.toStringAsFixed(1) : '0.0',
                  style: GoogleFonts.outfit(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: context.palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return Icon(
                      index < _avgRating.round() ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 16,
                    );
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  '$_reviewCount reviews',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: context.palette.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 100,
            width: 1,
            color: const Color(0xFFE2E8F0),
            margin: const EdgeInsets.symmetric(horizontal: 16),
          ),
          Expanded(
            flex: 3,
            child: Column(
              children: [
                _buildRatingBarRow(5, p5, c5),
                _buildRatingBarRow(4, p4, c4),
                _buildRatingBarRow(3, p3, c3),
                _buildRatingBarRow(2, p2, c2),
                _buildRatingBarRow(1, p1, c1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingBarRow(int stars, double pct, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '$stars★',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: context.palette.textMuted,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: const Color(0xFFF1F5F9),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 35,
            child: Text(
              '${(pct * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.end,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: context.palette.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> r) {
    final nick = r['nickname'] ?? 'Anonymous';
    final comment = r['review_text'] ?? r['comment'] ?? '';
    final rating = r['rating'] as int? ?? 5;
    final dateStr = _getRelativeTime(r['created_at']);
    final reply = r['admin_reply'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFFFF3ED),
                    child: Text(
                      nick.isNotEmpty ? nick[0].toUpperCase() : 'A',
                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nick,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                      ),
                      Text(
                        dateStr,
                        style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: List.generate(5, (index) {
                  return Icon(
                    index < rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 14,
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            comment,
            style: GoogleFonts.inter(fontSize: 13, color: context.palette.textSecondary),
          ),
          
          // Indented admin reply
          if (reply != null && reply.trim().isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(top: 12, left: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Admin Response',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reply,
                    style: GoogleFonts.inter(fontSize: 12, color: context.palette.textSecondary),
                  ),
                ],
              ),
            ),
          ],

          // Admin action triggers
          if (widget.isAdmin) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.bottomRight,
              child: TextButton.icon(
                onPressed: () => _adminReplyBottomSheet(r),
                icon: const Icon(Icons.reply, size: 14, color: Color(0xFFE65C00)),
                label: Text(
                  reply != null ? 'Edit Reply' : 'Reply',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFE65C00), fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
