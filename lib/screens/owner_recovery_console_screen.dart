import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';
import '../utils/error_messages.dart';
import '../widgets/states/states.dart';
import '../widgets/app_gradient_scaffold.dart';

/// APP-OWNER-only console to review account-recovery requests. Lists users who
/// requested recovery within their 7-day deletion window; the owner Approves
/// (restores the account) or Denies (account stays scheduled → purged).
///
/// Backed by SECURITY DEFINER RPCs (`owner_list_recovery_requests`,
/// `owner_decide_recovery`) because it must read/update arbitrary users — which
/// normal RLS forbids. Both RPCs authorize the caller against the app-owner id.
class OwnerRecoveryConsoleScreen extends StatefulWidget {
  const OwnerRecoveryConsoleScreen({super.key});

  @override
  State<OwnerRecoveryConsoleScreen> createState() => _OwnerRecoveryConsoleScreenState();
}

class _OwnerRecoveryConsoleScreenState extends State<OwnerRecoveryConsoleScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _requests = [];
  final Set<String> _busy = {};

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
      // Only the app owner (users.is_app_owner = true) may use this console.
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
      final rows = await _supabase.rpc('owner_list_recovery_requests');
      if (!mounted) return;
      setState(() {
        _requests = rows is List ? List<Map<String, dynamic>>.from(rows) : [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _decide(Map<String, dynamic> req, bool approve) async {
    final id = req['id']?.toString();
    if (id == null) return;
    final name = (req['full_name'] ?? 'this user').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.palette.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(approve ? 'Restore account?' : 'Deny recovery?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          approve
              ? 'Restore $name\'s account? They will regain full access.'
              : 'Deny $name\'s recovery? Their account stays scheduled and will be '
                  'permanently deleted at the end of the window.',
          style: GoogleFonts.inter(fontSize: 13.5, color: context.palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: context.palette.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: approve ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: Text(approve ? 'Restore' : 'Deny'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy.add(id));
    try {
      await _supabase.rpc('owner_decide_recovery', params: {
        'p_user_id': id,
        'p_approve': approve,
      });
      if (!mounted) return;
      setState(() {
        _requests.removeWhere((r) => r['id']?.toString() == id);
        _busy.remove(id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Account restored ✓' : 'Recovery denied'),
          backgroundColor: approve ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientScaffold(
      title: 'Recovery Console',
      body: _loading
          ? const LoadingState()
          : _error != null
              ? ErrorState(error: _error, onRetry: _load)
              : _requests.isEmpty
                  ? RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: _load,
                      child: ListView(children: const [
                        SizedBox(height: 120),
                        EmptyState(
                          icon: Icons.verified_user_outlined,
                          title: 'No recovery requests',
                          message: 'Account-recovery requests from deleted accounts will appear here.',
                        ),
                      ]),
                    )
                  : RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _requests.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _buildCard(_requests[i]),
                      ),
                    ),
    );
  }

  Widget _buildCard(Map<String, dynamic> req) {
    final id = req['id']?.toString() ?? '';
    final name = (req['full_name'] ?? 'Unknown').toString();
    final email = (req['email'] ?? '').toString();
    final phone = (req['phone'] ?? '').toString();
    final role = (req['role'] ?? '').toString();
    final purge = req['deletion_scheduled_at'] != null
        ? DateTime.tryParse(req['deletion_scheduled_at'].toString())?.toLocal()
        : null;
    final busy = _busy.contains(id);

    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
              ),
              if (role.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(6)),
                  child: Text(role.toUpperCase(),
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF1D4ED8))),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (email.isNotEmpty)
            Text(email, style: GoogleFonts.inter(fontSize: 12.5, color: context.palette.textMuted)),
          if (phone.isNotEmpty)
            Text('+91 $phone', style: GoogleFonts.inter(fontSize: 12.5, color: context.palette.textMuted)),
          if (purge != null) ...[
            const SizedBox(height: 6),
            Text('Permanent deletion: ${purge.day}/${purge.month}/${purge.year}',
                style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFFDC2626))),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => _decide(req, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Deny'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : () => _decide(req, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Restore'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
