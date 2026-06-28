import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_snackbar.dart';
import '../services/moderation_service.dart';
import '../theme/app_palette.dart';
import '../utils/error_messages.dart';
import '../widgets/states/empty_state.dart';

/// APP-OWNER-only console to triage UGC abuse reports. Lists open reports and
/// lets the app-owner hide the offending review, dismiss, or mark actioned.
/// RLS (report_select_scoped / report_update_moderator) authorizes the caller;
/// the screen also guards the entry against `users.is_app_owner`.
class OwnerAbuseReportsScreen extends StatefulWidget {
  const OwnerAbuseReportsScreen({super.key});

  @override
  State<OwnerAbuseReportsScreen> createState() => _OwnerAbuseReportsScreenState();
}

class _OwnerAbuseReportsScreenState extends State<OwnerAbuseReportsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _reports = [];
  final Set<String> _busy = {};

  static const Map<String, String> _reasonLabels = {
    'spam': 'Spam or misleading',
    'harassment': 'Harassment or abuse',
    'inappropriate': 'Inappropriate / explicit',
    'impersonation': 'Impersonation',
    'copyright': 'Copyright / IP',
    'other': 'Other',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'Please sign in again.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final me = await _supabase
          .from('users')
          .select('is_app_owner')
          .eq('id', user.id)
          .maybeSingle();
      if (me == null || me['is_app_owner'] != true) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'You are not authorized to view this console.';
        });
        return;
      }
      final rows = await _supabase
          .from('abuse_reports')
          .select()
          .eq('status', 'open')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _reports = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(Map<String, dynamic> report, String status) async {
    final id = report['id'].toString();
    setState(() => _busy.add(id));
    try {
      await _supabase.from('abuse_reports').update({
        'status': status,
        'reviewed_by': _supabase.auth.currentUser?.id,
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
      if (!mounted) return;
      AppSnackbar.success(context, 'Report ${status == 'dismissed' ? 'dismissed' : 'updated'}.');
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(id));
      AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _hideAndAction(Map<String, dynamic> report) async {
    final id = report['id'].toString();
    setState(() => _busy.add(id));
    try {
      await ModerationService.hideReview(report['target_id'].toString(),
          reason: 'Hidden via abuse report');
      await _supabase.from('abuse_reports').update({
        'status': 'actioned',
        'reviewed_by': _supabase.auth.currentUser?.id,
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
      if (!mounted) return;
      AppSnackbar.success(context, 'Review hidden and report actioned.');
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(id));
      AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.scaffold,
      appBar: AppBar(
        backgroundColor: const Color(0xFFE65C00),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Abuse reports', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 14, color: p.textSecondary)),
                  ),
                )
              : _reports.isEmpty
                  ? const EmptyState(
                      icon: Icons.verified_outlined,
                      title: 'No open reports',
                      message: 'Reported content will appear here for review.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: const Color(0xFFE65C00),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _reports.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _buildReportCard(_reports[i]),
                      ),
                    ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> r) {
    final p = context.palette;
    final id = r['id'].toString();
    final type = (r['target_type'] ?? '').toString();
    final reason = _reasonLabels[r['reason']] ?? (r['reason'] ?? '').toString();
    final desc = (r['description'] ?? '').toString();
    final created = r['created_at'] != null
        ? DateFormat('dd MMM yyyy, h:mm a').format(DateTime.parse(r['created_at']).toLocal())
        : '';
    final isReview = type == 'review';
    final busy = _busy.contains(id);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x14E65C00),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(type.toUpperCase(),
                    style: GoogleFonts.inter(
                        fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(reason,
                    style: GoogleFonts.inter(
                        fontSize: 13.5, fontWeight: FontWeight.bold, color: p.textPrimary)),
              ),
            ],
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(desc, style: GoogleFonts.inter(fontSize: 12.5, color: p.textSecondary)),
          ],
          const SizedBox(height: 6),
          Text(created, style: GoogleFonts.inter(fontSize: 10.5, color: p.textMuted)),
          const SizedBox(height: 10),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)))),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (isReview)
                  TextButton.icon(
                    onPressed: () => _hideAndAction(r),
                    icon: const Icon(Icons.visibility_off_outlined, size: 16, color: Color(0xFFDC2626)),
                    label: Text('Hide review',
                        style: GoogleFonts.inter(
                            fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFFDC2626))),
                  ),
                TextButton(
                  onPressed: () => _setStatus(r, 'actioned'),
                  child: Text('Mark actioned',
                      style: GoogleFonts.inter(
                          fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                ),
                TextButton(
                  onPressed: () => _setStatus(r, 'dismissed'),
                  child: Text('Dismiss',
                      style: GoogleFonts.inter(fontSize: 12.5, color: p.textMuted)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
