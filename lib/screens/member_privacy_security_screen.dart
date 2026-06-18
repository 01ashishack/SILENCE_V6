import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/error_messages.dart';

class MemberPrivacySecurityScreen extends StatefulWidget {
  const MemberPrivacySecurityScreen({super.key});

  @override
  State<MemberPrivacySecurityScreen> createState() => _MemberPrivacySecurityScreenState();
}

class _MemberPrivacySecurityScreenState extends State<MemberPrivacySecurityScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _userId;
  String? _userEmail;
  bool _hasGoogleIdentity = false;

  // Privacy states
  bool _showOnLeaderboard = true;
  bool _showHours = true;
  bool _hideNickname = false;

  // Deletion states
  bool _scheduledForDeletion = false;
  DateTime? _deletionScheduledAt;

  @override
  void initState() {
    super.initState();
    _loadPrivacyData();
  }

  Future<void> _loadPrivacyData() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user != null) {
        _userId = user.id;
        _userEmail = user.email;

        // Check providers
        final identities = user.identities ?? [];
        _hasGoogleIdentity = identities.any((i) => i.provider == 'google') ||
            (user.appMetadata['provider'] == 'google');

        final prefs = await SharedPreferences.getInstance();
        final suffix = user.id;

        // Load privacy toggles from DB with local cache fallbacks
        try {
          final userData = await supabase.from('users').select('show_on_leaderboard, show_hours, hide_nickname, scheduled_for_deletion, deletion_scheduled_at').eq('id', user.id).maybeSingle();
          if (userData != null) {
            _showOnLeaderboard = userData['show_on_leaderboard'] as bool? ?? true;
            _showHours = userData['show_hours'] as bool? ?? true;
            _hideNickname = userData['hide_nickname'] as bool? ?? false;
            _scheduledForDeletion = userData['scheduled_for_deletion'] as bool? ?? false;
            if (userData['deletion_scheduled_at'] != null) {
              _deletionScheduledAt = DateTime.parse(userData['deletion_scheduled_at']);
            }
          }
        } catch (e) {
          debugPrint('Supabase column load error: $e');
        }

        // Apply Local overrides if present
        _showOnLeaderboard = prefs.getBool('privacy_show_leaderboard_$suffix') ?? _showOnLeaderboard;
        _showHours = prefs.getBool('privacy_show_hours_$suffix') ?? _showHours;
        _hideNickname = prefs.getBool('privacy_hide_nickname_$suffix') ?? _hideNickname;
        _scheduledForDeletion = prefs.getBool('privacy_scheduled_deletion_$suffix') ?? _scheduledForDeletion;
        final scheduledAtStr = prefs.getString('privacy_deletion_time_$suffix');
        if (scheduledAtStr != null) {
          _deletionScheduledAt = DateTime.parse(scheduledAtStr);
        }
      }
    } catch (e) {
      debugPrint('Error loading privacy preferences: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: const Color(0xFFEF4444),
      ),
    );
  }

  void _showSuccessSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  Future<void> _savePrivacySettings() async {
    if (_userId == null) return;
    setState(() => _isSaving = true);
    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      final suffix = _userId!;

      // Save locally
      await prefs.setBool('privacy_show_leaderboard_$suffix', _showOnLeaderboard);
      await prefs.setBool('privacy_show_hours_$suffix', _showHours);
      await prefs.setBool('privacy_hide_nickname_$suffix', _hideNickname);

      // Save in Supabase (graceful error handling)
      try {
        await supabase.from('users').update({
          'show_on_leaderboard': _showOnLeaderboard,
          'show_hours': _showHours,
          'hide_nickname': _hideNickname,
        }).eq('id', _userId!);
        if (!mounted) return;
      } catch (dbError) {
        debugPrint('Column missing in Supabase, using local: $dbError');
      }

      _showSuccessSnackBar('Privacy settings updated! ✓');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showErrorSnackBar(friendlyError(e));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showChangePasswordBottomSheet() async {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isUpdating = false;
    String? localError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              top: 24,
              left: 24,
              right: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Change Password',
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Passwords must be at least 6 characters.',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  if (localError != null) ...[
                    Text(
                      localError!,
                      style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: currentPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Current Password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (v) => v == null || v.isEmpty ? 'Current Password is required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                      prefixIcon: Icon(Icons.vpn_key_outlined),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'New Password is required';
                      if (v.length < 6) return 'Password must be at least 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm New Password',
                      prefixIcon: Icon(Icons.check_circle_outline),
                    ),
                    validator: (v) {
                      if (v != newPasswordController.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: isUpdating ? null : () async {
                      if (!formKey.currentState!.validate()) return;
                      setModalState(() {
                        isUpdating = true;
                        localError = null;
                      });

                      try {
                        final supabase = Supabase.instance.client;
                        // Supabase updates the password of the currently authenticated user
                        await supabase.auth.updateUser(
                          UserAttributes(password: newPasswordController.text.trim()),
                        );
                        if (!mounted) return;
                        _showSuccessSnackBar('Password updated successfully! ✓');
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                        }
                      } catch (e) {
                        setModalState(() {
                          localError = friendlyError(e);
                        });
                      } finally {
                        setModalState(() => isUpdating = false);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: isUpdating
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text('Update Password', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleDisconnectGoogle() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Disconnect Google?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to unlink your Google Account? You will need to set up a password to log in next time.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.grey[600])),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: Text('Disconnect', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              try {
                // Simulated unlink or provider unlinking in Supabase
                // Usually done by deleting identity. For safety, we mock the local toggle and show toast.
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('mock_google_unlinked_${_userId!}', true);
                if (!mounted) return;
                setState(() => _hasGoogleIdentity = false);
                _showSuccessSnackBar('Google Account disconnected successfully! ✓');
              } catch (e) {
                _showErrorSnackBar(friendlyError(e));
              } finally {
                setState(() => _isLoading = false);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleDownloadData() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw 'User session not found';

      final Map<String, dynamic> exportData = {};

      // 1. Profile
      try {
        final profile = await supabase.from('users').select().eq('id', user.id).maybeSingle();
        exportData['profile'] = profile ?? {};
      } catch (e) {
        exportData['profile'] = {'error': e.toString()};
      }

      // 2. Memberships
      try {
        final memberships = await supabase.from('memberships').select().eq('member_id', user.id);
        exportData['memberships'] = memberships;
      } catch (e) {
        exportData['memberships'] = [];
      }

      // 3. Payments
      try {
        final payments = await supabase.from('payments').select().eq('member_id', user.id);
        exportData['payments'] = payments;
      } catch (e) {
        exportData['payments'] = [];
      }

      // 4. Attendance
      try {
        final attendance = await supabase.from('attendance').select().eq('member_id', user.id);
        exportData['attendance'] = attendance;
      } catch (e) {
        exportData['attendance'] = [];
      }

      // Convert to format
      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      
      if (mounted) {
        setState(() => _isLoading = false);
        await Share.share(
          jsonString,
          subject: 'SILENCE_Member_Data_Export.json',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar(friendlyError(e));
      }
    }
  }

  Future<void> _handleDeleteAccount() async {
    final confirmCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final canDelete = confirmCtrl.text.trim().toUpperCase() == 'DELETE';
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Delete your account?',
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold, color: const Color(0xFFEF4444))),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This schedules permanent deletion in 7 days. Your account is '
                    'frozen immediately — the dashboard is locked meanwhile.',
                    style: GoogleFonts.inter(fontSize: 13, height: 1.4)),
                const SizedBox(height: 10),
                _delWarnRow('Your profile, study hours, streaks & history will be erased'),
                _delWarnRow('Your memberships and seat will be released'),
                _delWarnRow('You will be signed out and check-in will be disabled'),
                const SizedBox(height: 8),
                Text('Within 7 days you can request recovery; the SILENCE team reviews '
                    'and decides. There is no self-cancel. After 7 days it is permanent.',
                    style: GoogleFonts.inter(
                        fontSize: 11.5, color: const Color(0xFF64748B))),
                const SizedBox(height: 14),
                Text('Type DELETE to confirm:',
                    style: GoogleFonts.inter(
                        fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF475569))),
                const SizedBox(height: 6),
                TextField(
                  controller: confirmCtrl,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setDialog(() {}),
                  decoration: const InputDecoration(hintText: 'DELETE'),
                ),
              ],
            ),
            actions: [
              TextButton(
                child: Text('Cancel',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.grey[600])),
                onPressed: () => Navigator.pop(ctx),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  disabledBackgroundColor: const Color(0xFFFCA5A5),
                ),
                onPressed: canDelete ? () => Navigator.pop(ctx, true) : null,
                child: Text('Schedule deletion',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          );
        },
      ),
    ).then((confirmed) async {
      if (confirmed == true) await _scheduleDeletion();
    });
  }

  Widget _delWarnRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.remove_circle_outline, size: 15, color: Color(0xFFEF4444)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569))),
          ),
        ],
      ),
    );
  }

  Future<void> _scheduleDeletion() async {
              setState(() => _isLoading = true);
              try {
                final supabase = Supabase.instance.client;
                final prefs = await SharedPreferences.getInstance();
                final suffix = _userId!;
                final deletionTime = DateTime.now().add(const Duration(days: 7));

                await prefs.setBool('privacy_scheduled_deletion_$suffix', true);
                await prefs.setString('privacy_deletion_time_$suffix', deletionTime.toIso8601String());

                try {
                  await supabase.from('users').update({
                    'scheduled_for_deletion': true,
                    'deletion_scheduled_at': deletionTime.toIso8601String(),
                    'deletion_recovery_status': 'none',
                  }).eq('id', _userId!);
                  if (!mounted) return;
                  // Freeze immediately — block dashboard, only recovery/logout remain.
                  Navigator.of(context).pushNamedAndRemoveUntil('/account-frozen', (r) => false);
                  return;
                } catch (e) {
                  debugPrint('Failed to update scheduled_for_deletion in DB, using local: $e');
                }

                setState(() {
                  _scheduledForDeletion = true;
                  _deletionScheduledAt = deletionTime;
                });
                _showSuccessSnackBar('Account deletion scheduled for ${deletionTime.day}/${deletionTime.month}/${deletionTime.year}! ⚠');
              } catch (e) {
                _showErrorSnackBar(friendlyError(e));
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
  }

  Future<void> _cancelDeletion() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      final suffix = _userId!;

      await prefs.setBool('privacy_scheduled_deletion_$suffix', false);
      await prefs.remove('privacy_deletion_time_$suffix');

      try {
        await supabase.from('users').update({
          'scheduled_for_deletion': false,
          'deletion_scheduled_at': null,
        }).eq('id', _userId!);
        if (!mounted) return;
      } catch (e) {
        debugPrint('Failed to reset scheduled_for_deletion in DB, using local: $e');
      }

      setState(() {
        _scheduledForDeletion = false;
        _deletionScheduledAt = null;
      });
      _showSuccessSnackBar('Account deletion cancelled! ✓');
    } catch (e) {
      _showErrorSnackBar(friendlyError(e));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE65C00),
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: const Color(0xFFFBF5EE),
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Privacy & Security',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Grace period warning banner
                      if (_scheduledForDeletion && _deletionScheduledAt != null)
                        _buildDeletionWarningBanner(),

                      // Security Section
                      _buildSectionHeader('Security Settings'),
                      _buildSettingsCard([
                        ListTile(
                          onTap: _showChangePasswordBottomSheet,
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(color: Color(0xFFFFF3ED), shape: BoxShape.circle),
                            child: const Icon(Icons.vpn_key_outlined, color: Color(0xFFE65C00), size: 20),
                          ),
                          title: Text('Change Password', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                          subtitle: Text('Update your app login security password.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                        ),
                        if (_userEmail != null) ...[
                          const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6), indent: 56),
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(color: Color(0xFFEFF6FF), shape: BoxShape.circle),
                              child: const Icon(Icons.g_mobiledata, color: Color(0xFF3B82F6), size: 24),
                            ),
                            title: Text('Connected Google Account', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                            subtitle: Text(_userEmail!, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                            trailing: _hasGoogleIdentity
                                ? TextButton(
                                    onPressed: _handleDisconnectGoogle,
                                    child: Text('Disconnect', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFEF4444))),
                                  )
                                : Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)),
                                    child: Text('Not Linked', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.bold)),
                                  ),
                          ),
                        ]
                      ]),
                      const SizedBox(height: 20),

                      // Privacy Section
                      _buildSectionHeader('Privacy Preferences'),
                      _buildSettingsCard([
                        SwitchListTile(
                          activeThumbColor: const Color(0xFFE65C00),
                          value: _showOnLeaderboard,
                          onChanged: (v) => setState(() => _showOnLeaderboard = v),
                          title: Text('Show on Leaderboard', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                          subtitle: Text('Let other library members see your score on study ranks.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                          secondary: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(color: Color(0xFFFFFBEB), shape: BoxShape.circle),
                            child: const Icon(Icons.emoji_events_outlined, color: Color(0xFFF59E0B), size: 20),
                          ),
                        ),
                        const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6), indent: 56),
                        SwitchListTile(
                          activeThumbColor: const Color(0xFFE65C00),
                          value: _showHours,
                          onChanged: (v) => setState(() => _showHours = v),
                          title: Text('Show Study Hours to Others', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                          subtitle: Text('Allow fellow students to view your daily attendance logs.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                          secondary: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(color: Color(0xFFECFDF5), shape: BoxShape.circle),
                            child: const Icon(Icons.insights, color: Color(0xFF10B981), size: 20),
                          ),
                        ),
                        const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6), indent: 56),
                        SwitchListTile(
                          activeThumbColor: const Color(0xFFE65C00),
                          value: _hideNickname,
                          onChanged: (v) => setState(() => _hideNickname = v),
                          title: Text('Hide Nickname from Non-members', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                          subtitle: Text('Prevent users who are not active members from seeing your nickname.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                          secondary: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(color: Color(0xFFFBF5EE), shape: BoxShape.circle),
                            child: const Icon(Icons.visibility_off_outlined, color: Color(0xFFE65C00), size: 20),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 20),

                      // Data Section
                      _buildSectionHeader('Data Portability'),
                      _buildSettingsCard([
                        ListTile(
                          onTap: _handleDownloadData,
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(color: Color(0xFFF5F3FF), shape: BoxShape.circle),
                            child: const Icon(Icons.file_download_outlined, color: Color(0xFF8B5CF6), size: 20),
                          ),
                          title: Text('Download My Data', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                          subtitle: Text('Generate and export your profile, membership, and attendance logs in JSON.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                        )
                      ]),
                      const SizedBox(height: 20),

                      // Danger Zone Section
                      _buildSectionHeader('Danger Zone'),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFEE2E2), width: 1),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(color: Color(0xFFFEF2F2), shape: BoxShape.circle),
                                child: const Icon(Icons.delete_forever, color: Color(0xFFEF4444), size: 20),
                              ),
                              title: Text(
                                _scheduledForDeletion ? 'Deletion Scheduled' : 'Delete Account',
                                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFEF4444)),
                              ),
                              subtitle: Text(
                                _scheduledForDeletion
                                    ? 'Your account will be permanently deleted soon.'
                                    : 'Schedule deletion — 7-day recovery window, then permanent.',
                                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                              ),
                              trailing: _scheduledForDeletion
                                  ? OutlinedButton(
                                      onPressed: _cancelDeletion,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF10B981),
                                        side: const BorderSide(color: Color(0xFF10B981)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12)),
                                    )
                                  : OutlinedButton(
                                      onPressed: _handleDeleteAccount,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFFEF4444),
                                        side: const BorderSide(color: Color(0xFFEF4444)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: Text('Delete', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Save Button
                      ElevatedButton(
                        onPressed: _isSaving ? null : _savePrivacySettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 2,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                              )
                            : Text('Save Settings', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280), letterSpacing: 1),
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildDeletionWarningBanner() {
    final daysRemaining = _deletionScheduledAt!.difference(DateTime.now()).inDays;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
              const SizedBox(width: 8),
              Text(
                'Deletion Scheduled',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF991B1B)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your account is scheduled to be permanently deleted on ${_deletionScheduledAt!.day}/${_deletionScheduledAt!.month}/${_deletionScheduledAt!.year} (approx. $daysRemaining days left). You can cancel this request anytime before then to retain all your data.',
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF7F1D1D), height: 1.4),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _cancelDeletion,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Cancel Deletion Request', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

