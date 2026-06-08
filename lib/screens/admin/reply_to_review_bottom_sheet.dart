import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReplyToReviewBottomSheet extends StatefulWidget {
  final Map<String, dynamic> review;
  final VoidCallback onReplySent;

  const ReplyToReviewBottomSheet({
    super.key,
    required this.review,
    required this.onReplySent,
  });

  @override
  State<ReplyToReviewBottomSheet> createState() => _ReplyToReviewBottomSheetState();
}

class _ReplyToReviewBottomSheetState extends State<ReplyToReviewBottomSheet> {
  final _supabase = Supabase.instance.client;
  final _replyController = TextEditingController();
  int _charCount = 0;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _replyController.addListener(_updateCharCount);
  }

  void _updateCharCount() {
    setState(() {
      _charCount = _replyController.text.length;
    });
  }

  @override
  void dispose() {
    _replyController.removeListener(_updateCharCount);
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final replyText = _replyController.text.trim();
    if (replyText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write a reply')),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final reviewId = widget.review['id'];
      await _supabase
          .from('reviews')
          .update({
            'admin_reply': replyText,
            'admin_replied_at': DateTime.now().toIso8601String(),
            'is_read_by_admin': true,
          })
          .eq('id', reviewId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reply sent ✓')),
      );
      Navigator.pop(context);
      widget.onReplySent();
    } catch (e) {
      debugPrint('Error sending reply: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send reply: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.review['member'] as Map<String, dynamic>?;
    final nickname = member?['nickname'];
    final fullName = member?['full_name'];
    String displayName = 'Member';
    if (nickname != null && nickname.toString().trim().isNotEmpty) {
      displayName = nickname.toString().trim();
    } else if (fullName != null && fullName.toString().trim().isNotEmpty) {
      displayName = fullName.toString().trim().split(' ').first;
    }

    final reviewText = widget.review['review_text'] ?? '(No review text)';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Reply to Review',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const Divider(height: 24, color: Color(0xFFE2E8F0)),
          Text(
            '$displayName wrote:',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              '"$reviewText"',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF475569),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Your reply:',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              Text(
                '$_charCount/200',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _charCount > 200 ? Colors.red : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _replyController,
            maxLines: 3,
            maxLength: 200,
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) => const SizedBox.shrink(),
            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B)),
            decoration: InputDecoration(
              hintText: 'Type your reply here...',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE65C00), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: (_isSending || _charCount > 200) ? null : _sendReply,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65C00),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
              disabledBackgroundColor: Colors.grey[300],
            ),
            child: _isSending
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    'Send Reply',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
          ),
        ],
      ),
    );
  }
}
