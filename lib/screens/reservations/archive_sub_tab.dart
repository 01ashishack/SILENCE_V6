import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class ArchiveSubTab extends StatefulWidget {
  final String libraryId;
  const ArchiveSubTab({super.key, required this.libraryId});

  @override
  State<ArchiveSubTab> createState() => _ArchiveSubTabState();
}

class _ArchiveSubTabState extends State<ArchiveSubTab> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _archivedList = [];
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchArchiveData();
  }

  @override
  void didUpdateWidget(covariant ArchiveSubTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.libraryId != widget.libraryId) {
      setState(() {
        _isLoading = true;
      });
      _fetchArchiveData();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Fetch Archive Data ───────────────────────────────────────────────────
  Future<void> _fetchArchiveData() async {
    try {
      final response = await supabase
          .from('memberships')
          .select('*, member_id(id, full_name, phone, photo_url)')
          .eq('library_id', widget.libraryId)
          .eq('status', 'exited')
          .order('exited_at', ascending: false);

      if (mounted) {
        setState(() {
          _archivedList = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading archive data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Helper to format dates ────────────────────────────────────────────────
  String _formatDate(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return '';
    }
  }

  String _getDurationText(String planType) {
    if (planType == 'monthly') return '1 Month';
    if (planType == '3_month') return '3 Months';
    if (planType == '6_month') return '6 Months';
    return '1 Month';
  }

  // ── Filtered Search Results ────────────────────────────────────────────────
  List<Map<String, dynamic>> _getFilteredArchive() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _archivedList;

    return _archivedList.where((m) {
      final profile = m['member_id'];
      if (profile == null) return false;
      final name = (profile['full_name'] ?? '').toLowerCase();
      final phone = (profile['phone'] ?? '').toLowerCase();
      return name.contains(query) || phone.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredArchive = _getFilteredArchive();

    return Scaffold(
      backgroundColor: context.palette.scaffold,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Search Bar Sticky Header (S035 Spec)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '🔍 Search archived members...',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
                fillColor: const Color(0xFFF8FAFC),
                prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _fetchArchiveData();
                        },
                      )
                    : null,
              ),
              onChanged: (val) => setState(() {}),
            ),
          ),

          // 2. Scrollable List Container (S035 Spec)
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
                : filteredArchive.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // 📦 Box Empty State Illustration
                              Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text(
                                'No past members yet',
                                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textMuted),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Members who exit their subscription will be moved here for historic tracking.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500], height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredArchive.length,
                        itemBuilder: (ctx, index) {
                          final membership = filteredArchive[index];
                          final member = membership['member_id'];
                          if (member == null) return const SizedBox.shrink();

                          final String name = member['full_name'] ?? 'No Name';
                          final String photo = member['photo_url'] ?? '';
                          final String exitedDate = _formatDate(membership['exited_at'] ?? membership['end_date']);
                          final String joinDate = _formatDate(membership['start_date']);
                          final String durationText = _getDurationText(membership['plan_type'] ?? 'monthly');

                          return Opacity(
                            opacity: 0.7, // Faded effect (70% opacity spec)
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: context.palette.surface,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: const Color(0xFFFFF7F0),
                                  backgroundImage: photo.isNotEmpty ? ResizeImage(NetworkImage(photo), width: 150) : null,
                                  child: photo.isEmpty ? const Icon(Icons.person, color: Color(0xFFE65C00)) : null,
                                ),
                                title: Text(
                                  name,
                                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Exited $exitedDate', style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted)),
                                      const SizedBox(height: 2),
                                      Text('Member since $joinDate', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
                                    ],
                                  ),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9), // Gray duration pill spec
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    durationText,
                                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: context.palette.textSecondary),
                                  ),
                                ),
                                onTap: () {
                                  // Can still deep-dive archived members history logs
                                  Navigator.pushNamed(context, '/admin/member', arguments: member['id']);
                                },
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
