import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_gradient_scaffold.dart';

class AuditEntry {
  final String id;
  final String performerName;
  final String category; // 'members', 'payments', 'qr', 'settings'
  final String actionTitle;
  final String actionDetails;
  final String timestamp;

  AuditEntry({
    required this.id,
    required this.performerName,
    required this.category,
    required this.actionTitle,
    required this.actionDetails,
    required this.timestamp,
  });
}

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;
  String _selectedFilter = 'all'; // 'all', 'members', 'payments', 'qr'
  List<AuditEntry> _logs = [];

  @override
  void initState() {
    super.initState();
    _fetchAuditLogs();
  }

  Future<void> _fetchAuditLogs() async {
    setState(() => _isLoading = true);
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        // Attempt to fetch from Supabase audit_log table
        final List<dynamic> res = await _supabase
            .from('audit_log')
            .select()
            .order('created_at', ascending: false)
            .limit(40);
        
        if (res.isNotEmpty) {
          _logs = res.map((item) {
            // Canonical rows store display fields inside the `details` JSONB.
            // Fall back to legacy flat columns for older rows.
            final d = item['details'];
            final meta = d is Map ? d : const {};
            return AuditEntry(
              id: item['id'].toString(),
              performerName: (meta['performer_name'] ??
                      item['performer_name'] ??
                      'System Admin')
                  .toString(),
              category:
                  (meta['category'] ?? item['category'] ?? 'settings').toString(),
              actionTitle: (meta['title'] ??
                      item['action_title'] ??
                      item['action'] ??
                      'Updated Settings')
                  .toString(),
              actionDetails: (meta['details'] ??
                      item['action_details'] ??
                      (d is String ? d : 'Modified record'))
                  .toString(),
              timestamp: item['created_at'] != null
                  ? item['created_at'].toString().substring(0, 16).replaceAll('T', ' ')
                  : '',
            );
          }).toList();
        }
      } catch (e) {
        debugPrint('Audit logs Supabase query exception: $e');
      }
    }
    setState(() => _isLoading = false);
  }

  List<AuditEntry> _getFilteredLogs() {
    if (_selectedFilter == 'all') return _logs;
    return _logs.where((l) => l.category == _selectedFilter).toList();
  }

  Color _getCategoryColor(String cat) {
    switch (cat) {
      case 'members': return const Color(0xFF3B82F6); // Blue
      case 'payments': return const Color(0xFF10B981); // Emerald Green
      case 'qr': return const Color(0xFFF59E0B); // Amber
      default: return const Color(0xFF7C3AED); // Purple
    }
  }

  IconData _getCategoryIcon(String cat) {
    switch (cat) {
      case 'members': return Icons.people_outline;
      case 'payments': return Icons.receipt_long_outlined;
      case 'qr': return Icons.qr_code_outlined;
      default: return Icons.settings_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = _getFilteredLogs();

    return AppGradientScaffold(
      title: 'Security Audit Log',
      body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
              : Column(
                  children: [
                    // 1. Horizontal filter pills
                    Container(
                      color: context.palette.surface,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            _buildFilterPill('all', 'All Logs'),
                            _buildFilterPill('members', 'Members'),
                            _buildFilterPill('payments', 'Payments'),
                            _buildFilterPill('qr', 'QR Assets'),
                            _buildFilterPill('settings', 'System Settings'),
                          ],
                        ),
                      ),
                    ),

                    // 2. Ledger list
                    Expanded(
                      child: _logs.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.history, size: 64, color: Color(0xFF9CA3AF)),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No actions recorded yet',
                                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF374151)),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Actions appear here as you manage your library.',
                                    style: GoogleFonts.inter(color: const Color(0xFF9CA3AF), fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : (filteredList.isEmpty
                              ? Center(
                                  child: Text(
                                    'No audit logs found for this category.',
                                    style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                                  ),
                                )
                              : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              physics: const BouncingScrollPhysics(),
                              itemCount: filteredList.length,
                              itemBuilder: (context, index) {
                                final log = filteredList[index];
                                final badgeColor = _getCategoryColor(log.category);
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: context.palette.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: context.palette.border),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: badgeColor.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(_getCategoryIcon(log.category), color: badgeColor, size: 12),
                                                const SizedBox(width: 4),
                                                Text(
                                                  log.category.toUpperCase(),
                                                  style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.bold, color: badgeColor),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            log.timestamp,
                                            style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8)),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        log.actionTitle,
                                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        log.actionDetails,
                                        style: GoogleFonts.inter(fontSize: 11.5, color: context.palette.textSecondary, height: 1.4),
                                      ),
                                      const SizedBox(height: 10),
                                      Divider(height: 1, color: context.palette.divider),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(Icons.person, size: 12, color: Color(0xFF94A3B8)),
                                          const SizedBox(width: 6),
                                          Text(
                                            'By: ${log.performerName}',
                                            style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.palette.textMuted),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            )),
                    ),
                  ],
                ),
    );
  }

  Widget _buildFilterPill(String filterKey, String title) {
    final isSelected = filterKey == _selectedFilter;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedFilter = filterKey);
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE65C00) : const Color(0xFFE65C00).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? const Color(0xFFE65C00) : const Color(0xFFE65C00).withValues(alpha: 0.30)),
        ),
        child: Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 11.5, 
            fontWeight: FontWeight.bold, 
            color: isSelected ? Colors.white : const Color(0xFFE65C00),
          ),
        ),
      ),
    );
  }
}
