import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme_controller.dart';
import '../core/active_library_store.dart';
import '../theme/app_palette.dart';
import '../widgets/app_gradient_scaffold.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  bool _isLoading = false;
  bool _isDarkMode = false;

  // Overtime auto-checkout (per active library), moved here from the profile tab.
  String? _otLibId;
  bool? _overtimeOn; // null = loading
  int _graceMinutes = 30;
  bool _savingOvertime = false;

  @override
  void initState() {
    super.initState();
    _isDarkMode = ThemeController.instance.isDark;
    _loadOvertime();
  }

  Future<void> _loadOvertime() async {
    try {
      final libId = await ActiveLibraryStore.resolve(null);
      if (libId == null) {
        if (mounted) setState(() => _overtimeOn = true);
        return;
      }
      final row = await Supabase.instance.client
          .from('libraries')
          .select('auto_checkout_overtime, auto_checkout_grace_minutes')
          .eq('id', libId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _otLibId = libId;
        _overtimeOn = row?['auto_checkout_overtime'] != false;
        final m = row?['auto_checkout_grace_minutes'];
        _graceMinutes = (m is int && m >= 5) ? m : 30;
      });
    } catch (e) {
      debugPrint('load overtime failed: $e');
      if (mounted) setState(() => _overtimeOn = true);
    }
  }

  Future<void> _setOvertimeEnabled(bool v) async {
    if (_otLibId == null || _savingOvertime) return;
    setState(() {
      _savingOvertime = true;
      _overtimeOn = v;
    });
    try {
      await Supabase.instance.client
          .from('libraries')
          .update({'auto_checkout_overtime': v}).eq('id', _otLibId!);
    } catch (e) {
      if (mounted) setState(() => _overtimeOn = !v);
    } finally {
      if (mounted) setState(() => _savingOvertime = false);
    }
  }

  Future<void> _setGraceMinutes(int m) async {
    if (_otLibId == null) return;
    final clamped = m.clamp(5, 360);
    setState(() => _graceMinutes = clamped);
    try {
      await Supabase.instance.client
          .from('libraries')
          .update({'auto_checkout_grace_minutes': clamped}).eq('id', _otLibId!);
    } catch (e) {
      debugPrint('save grace minutes failed: $e');
    }
  }

  Future<void> _toggleTheme(bool value) async {
    await ThemeController.instance.setDark(value);
    if (!mounted) return;
    setState(() => _isDarkMode = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${value ? "Dark" : "Light"} mode enabled'),
        backgroundColor: const Color(0xFFE65C00),
      ),
    );
  }

  void _languageComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('More languages (including हिन्दी) are coming soon.'),
        backgroundColor: Color(0xFF334155),
      ),
    );
  }

  Future<void> _clearAppCache() async {
    setState(() => _isLoading = true);
    try {
      // Real cache clear: drop in-memory image cache + non-critical cached prefs
      // (keep auth/session, theme, active-library and accepted-policy keys).
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      final prefs = await SharedPreferences.getInstance();
      const keep = ['session', 'token', 'app_theme_mode', 'admin_active_library_id',
          'accepted_terms', 'accepted_privacy'];
      for (final key in prefs.getKeys().toList()) {
        if (!keep.any((k) => key.contains(k))) {
          await prefs.remove(key);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App cache cleared ✓'), backgroundColor: Color(0xFF10B981)),
        );
      }
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Sign Out', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to sign out of your account?', style: GoogleFonts.inter()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sign Out', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/auth', (route) => false);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Sign out failed: $e'), backgroundColor: Colors.redAccent),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientScaffold(
      title: 'App Settings',
      body: _isLoading
              ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Section 1: App Preferences
                      _buildSectionHeader('App Preferences'),
                      Container(
                        decoration: _buildCardDecoration(),
                        child: Column(
                          children: [
                            _buildNavigationTile(
                              icon: Icons.notifications_active_outlined,
                              title: 'Notification Preferences',
                              subtitle: 'Manage alert sounds, triggers and devices',
                              onTap: () => Navigator.pushNamed(context, '/admin/settings/notifications'),
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildToggleTile(
                              icon: Icons.dark_mode_outlined,
                              title: 'Dark Mode',
                              subtitle: 'Switch application theme mode',
                              value: _isDarkMode,
                              onChanged: _toggleTheme,
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildNavigationTile(
                              icon: Icons.language_outlined,
                              title: 'App Language',
                              subtitle: 'English (more languages coming soon)',
                              trailingText: 'Soon',
                              onTap: _languageComingSoon,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Section: Attendance (overtime auto-checkout)
                      _buildSectionHeader('Attendance'),
                      Container(
                        decoration: _buildCardDecoration(),
                        child: Column(
                          children: [
                            _buildToggleTile(
                              icon: Icons.logout_rounded,
                              title: 'Auto check-out on overtime',
                              subtitle: _overtimeOn == false
                                  ? 'Off — members stay checked in until they check out.'
                                  : 'On — members are auto-checked-out after the grace time below.',
                              value: _overtimeOn ?? true,
                              onChanged: (_overtimeOn == null || _savingOvertime)
                                  ? (_) {}
                                  : _setOvertimeEnabled,
                            ),
                            if (_overtimeOn != false) ...[
                              const Divider(height: 1, color: Color(0xFFF1F5F9)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Grace time after shift ends',
                                              style: GoogleFonts.inter(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: context.palette.textPrimary)),
                                          Text('Auto-checkout this many minutes after shift end',
                                              style: GoogleFonts.inter(
                                                  fontSize: 11, color: context.palette.textMuted)),
                                        ],
                                      ),
                                    ),
                                    _stepperBtn(Icons.remove, () => _setGraceMinutes(_graceMinutes - 5)),
                                    SizedBox(
                                      width: 56,
                                      child: Text('$_graceMinutes m',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.outfit(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFFE65C00))),
                                    ),
                                    _stepperBtn(Icons.add, () => _setGraceMinutes(_graceMinutes + 5)),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Section 2: Data Management
                      _buildSectionHeader('Data Management'),
                      Container(
                        decoration: _buildCardDecoration(),
                        child: Column(
                          children: [
                            _buildActionTile(
                              icon: Icons.delete_outline,
                              title: 'Clear Cache',
                              subtitle: 'Free up local database and memory cache',
                              onTap: _clearAppCache,
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildNavigationTile(
                              icon: Icons.ios_share_outlined,
                              title: 'Export Data & Reports',
                              subtitle: 'Download members, revenue, logs',
                              onTap: () => Navigator.pushNamed(context, '/admin/exports'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Section 3: Account Settings
                      _buildSectionHeader('Account Settings'),
                      Container(
                        decoration: _buildCardDecoration(),
                        child: Column(
                          children: [
                            _buildNavigationTile(
                              icon: Icons.credit_card_outlined,
                              title: 'Manage Subscription',
                              subtitle: 'View subscription status and payment methods',
                              onTap: () => Navigator.pushNamed(context, '/admin/subscription'),
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildActionTile(
                              icon: Icons.logout_outlined,
                              title: 'Logout',
                              subtitle: 'Sign out of current active session',
                              textColor: Colors.redAccent,
                              iconColor: Colors.redAccent,
                              onTap: _logout,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  Widget _stepperBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3ED),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: const Color(0xFFE65C00)),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
      child: Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: context.palette.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  BoxDecoration _buildCardDecoration() {
    return BoxDecoration(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.palette.border),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.01),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Widget _buildNavigationTile({
    required IconData icon,
    required String title,
    required String subtitle,
    String? trailingText,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3ED),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFFE65C00), size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null) ...[
            Text(
              trailingText,
              style: GoogleFonts.inter(fontSize: 13, color: context.palette.textMuted, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 4),
          ],
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFF94A3B8)),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3ED),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFFE65C00), size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted),
      ),
      trailing: Switch(
        value: value,
        activeThumbColor: const Color(0xFFE65C00),
        activeTrackColor: const Color(0xFFFFF3ED),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Color? textColor,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor == Colors.redAccent ? const Color(0xFFFFF1F2) : const Color(0xFFFFF3ED),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor ?? const Color(0xFFE65C00), size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: textColor ?? context.palette.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted),
      ),
      onTap: onTap,
    );
  }
}
