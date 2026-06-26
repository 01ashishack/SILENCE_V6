import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'reply_to_review_bottom_sheet.dart';

class AllReviewsScreen extends StatefulWidget {
  final String libraryId;
  const AllReviewsScreen({super.key, required this.libraryId});

  @override
  State<AllReviewsScreen> createState() => _AllReviewsScreenState();
}

class _AllReviewsScreenState extends State<AllReviewsScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;
  List<Map<String, dynamic>> _reviews = [];

  @override
  void initState() {
    super.initState();
    _fetchReviews();
  }

  Future<void> _fetchReviews() async {
    setState(() => _isLoading = true);
    try {
      final res = await _supabase
          .from('reviews')
          .select('*, member:member_id (nickname, full_name, photo_url)')
          .eq('library_id', widget.libraryId)
          .order('created_at', ascending: false);
      
      if (mounted) {
        setState(() {
          _reviews = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (e) {
      debugPrint('Error fetching reviews: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load reviews: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
          onReplySent: _fetchReviews,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffold,
      appBar: AppBar(
        backgroundColor: const Color(0xFFE65C00),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'All Reviews',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchReviews,
        color: const Color(0xFFE65C00),
        child: _isLoading && _reviews.isEmpty
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
                ),
              )
            : _reviews.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                      Center(
                        child: Text(
                          'No reviews yet',
                          style: GoogleFonts.inter(fontSize: 14, color: Colors.grey),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _reviews.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final review = _reviews[index];
                      return _buildReviewItem(review);
                    },
                  ),
      ),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
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
                color: const Color(0xFFFBF5EE),
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
}
