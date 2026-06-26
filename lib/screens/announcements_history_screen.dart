import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_gradient_scaffold.dart';

class AnnouncementsHistoryScreen extends StatefulWidget {
  const AnnouncementsHistoryScreen({super.key});

  @override
  State<AnnouncementsHistoryScreen> createState() =>
      _AnnouncementsHistoryScreenState();
}

class _AnnouncementsHistoryScreenState
    extends State<AnnouncementsHistoryScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _announcements = [];

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final libraries = await _supabase
          .from('libraries')
          .select('id')
          .eq('owner_id', user.id);
      final libraryIds =
          List<Map<String, dynamic>>.from(libraries).map((l) => l['id']).toList();

      if (libraryIds.isEmpty) {
        if (mounted) {
          setState(() {
            _announcements = [];
            _isLoading = false;
          });
        }
        return;
      }

      final res = await _supabase
          .from('announcements')
          .select()
          .inFilter('library_id', libraryIds)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _announcements = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load announcements: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) return '';
    try {
      return DateFormat('dd MMM yyyy, hh:mm a')
          .format(DateTime.parse(value.toString()).toLocal());
    } catch (_) {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientScaffold(
      title: 'Announcements History',
      body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFE65C00),
                  ),
                )
              : RefreshIndicator(
                  color: const Color(0xFFE65C00),
                  onRefresh: _loadAnnouncements,
                  child: _announcements.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            const SizedBox(height: 120),
                            Icon(
                              Icons.campaign_outlined,
                              size: 64,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No announcements yet',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: context.palette.textPrimary,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _announcements.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = _announcements[index];
                            final title = item['title'] ?? 'Announcement';
                            final body = item['message'] ?? item['content'] ?? '';
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: context.palette.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title.toString(),
                                    style: GoogleFonts.outfit(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: context.palette.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    body.toString(),
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: context.palette.textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _formatDate(item['created_at']),
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: const Color(0xFF94A3B8),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
