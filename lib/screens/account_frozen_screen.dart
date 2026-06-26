import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';
import '../utils/error_messages.dart';
import '../widgets/states/states.dart';

/// Full-screen block shown when the signed-in account is scheduled for
/// deletion. The dashboard is inaccessible; the only actions are **Request
/// Account Recovery** (sent to the app owner for approval) and **Logout**.
/// After the 7-day window a server cron permanently purges the account.
class AccountFrozenScreen extends StatefulWidget {
  const AccountFrozenScreen({super.key});

  @override
  State<AccountFrozenScreen> createState() => _AccountFrozenScreenState();
}

class _AccountFrozenScreenState extends State<AccountFrozenScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  Object? _error;
  bool _submitting = false;

  DateTime? _purgeDate; // deletion_scheduled_at = permanent-delete date
  String _recoveryStatus = 'none'; // none | requested | approved | denied

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
      final row = await _supabase
          .from('users')
          .select('scheduled_for_deletion, deletion_scheduled_at, deletion_recovery_status')
          .eq('id', user.id)
          .maybeSingle();
      if (!mounted) return;
      // If the account is no longer scheduled (owner approved recovery), leave.
      if (row != null && row['scheduled_for_deletion'] != true) {
        _goToSplash();
        return;
      }
      setState(() {
        _purgeDate = row?['deletion_scheduled_at'] != null
            ? DateTime.tryParse(row!['deletion_scheduled_at'].toString())?.toLocal()
            : null;
        _recoveryStatus = (row?['deletion_recovery_status'] ?? 'none').toString();
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

  int get _daysLeft {
    if (_purgeDate == null) return 0;
    final diff = _purgeDate!.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return diff.inHours ~/ 24 + (diff.inHours % 24 == 0 ? 0 : 1);
  }

  Future<void> _requestRecovery() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.palette.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Request account recovery?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          'Your request will be sent to the SILENCE team. They will review and '
          'decide whether to restore your account. You will stay signed out of '
          'the dashboard until it is approved.',
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
                backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('Request Recovery'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _submitting = true);
    try {
      await _supabase
          .from('users')
          .update({'deletion_recovery_status': 'requested'}).eq('id', user.id);
      if (!mounted) return;
      setState(() {
        _recoveryStatus = 'requested';
        _submitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recovery request sent. The team will review it.'),
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  Future<void> _logout() async {
    try {
      await _supabase.auth.signOut();
    } catch (_) {}
    _goToAuth();
  }

  void _goToAuth() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
  }

  void _goToSplash() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: context.palette.scaffold,
        body: SafeArea(
          child: _loading
              ? const LoadingState()
              : _error != null
                  ? ErrorState(error: _error, onRetry: _load)
                  : _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final requested = _recoveryStatus == 'requested';
    final denied = _recoveryStatus == 'denied';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFFEE2E2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_clock_rounded, size: 48, color: Color(0xFFDC2626)),
            ),
            const SizedBox(height: 20),
            Text(
              'Account Scheduled for Deletion',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  fontSize: 20, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
            ),
            const SizedBox(height: 10),
            Text(
              _daysLeft > 0
                  ? 'Your account is frozen and will be permanently deleted in '
                      '$_daysLeft day${_daysLeft == 1 ? '' : 's'}'
                      '${_purgeDate != null ? ' (on ${_purgeDate!.day}/${_purgeDate!.month}/${_purgeDate!.year})' : ''}.'
                  : 'Your account is past its recovery window and will be permanently deleted shortly.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, height: 1.5, color: context.palette.textSecondary),
            ),
            const SizedBox(height: 24),

            // Recovery status / action
            if (requested) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFD9B3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_top_rounded, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Recovery requested — waiting for the SILENCE team to approve. '
                        'You will regain access once it is restored.',
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF7C2D12)),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              if (denied)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Your previous recovery request was declined. You may request again.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFFDC2626)),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _requestRecovery,
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.restore_rounded),
                  label: const Text('Request Account Recovery'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded, color: Color(0xFF64748B)),
                label: Text('Logout',
                    style: GoogleFonts.inter(color: context.palette.textMuted, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _load,
              child: Text('Refresh status',
                  style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF94A3B8))),
            ),
          ],
        ),
      ),
    );
  }
}
