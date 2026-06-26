import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class LibraryQueryScreen extends StatefulWidget {
  final String libraryId;
  final String? preFilledMessage;

  const LibraryQueryScreen({
    super.key,
    required this.libraryId,
    this.preFilledMessage,
  });

  @override
  State<LibraryQueryScreen> createState() => _LibraryQueryScreenState();
}

class _LibraryQueryScreenState extends State<LibraryQueryScreen> {
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  bool _isLoading = true;
  bool _isSubmitting = false;
  Map<String, dynamic>? _library;

  @override
  void initState() {
    super.initState();
    if (widget.preFilledMessage != null) {
      _messageController.text = widget.preFilledMessage!;
    }
    _fetchLibraryDetails();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _fetchLibraryDetails() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final res = await _supabase
          .from('libraries')
          .select('name')
          .eq('id', widget.libraryId)
          .maybeSingle();

      if (res != null) {
        _library = res;
      }
    } catch (e) {
      debugPrint('Error loading library details: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitQuery() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message.')),
      );
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isSubmitting = true);

    try {
      await _supabase.from('queries').insert({
        'member_id': user.id,
        'library_id': widget.libraryId,
        'message': message,
        'status': 'open',
      });
      // Notify the library owner (best-effort).
      try {
        final lib = await _supabase
            .from('libraries')
            .select('owner_id')
            .eq('id', widget.libraryId)
            .maybeSingle();
        final ownerId = lib?['owner_id'] as String?;
        if (ownerId != null) {
          await _supabase.from('notifications').insert({
            'user_id': ownerId,
            'title': 'New member query',
            'body': message,
            'data': {'type': 'new_query', 'library_id': widget.libraryId},
          });
        }
      } catch (e) {
        debugPrint('notify admin of query failed: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Support query submitted to Admin! ✓'),
            backgroundColor: Color(0xFF22C55E),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error submitting query: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit query: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final libName = _library?['name'] ?? 'SILENCE Library';

    return Scaffold(
      backgroundColor: const Color(0xFFE65C00),
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: context.palette.scaffold,
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text('Contact Library', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Send a Message to Admin',
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'You are messaging: $libName',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Message/Query *',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _messageController,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          hintText: 'Type your question or request details here...',
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitQuery,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Text('Send Message', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
