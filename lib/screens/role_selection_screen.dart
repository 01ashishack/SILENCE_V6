import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import '../core/app_snackbar.dart';
import '../utils/error_messages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _isLoading = false;
  String? _selectedRole;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null && mounted) {
        Navigator.of(context).pushReplacementNamed('/auth');
      }
    });
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    AppSnackbar.error(context, message);
  }

  Future<void> _handleSaveRole() async {
    if (_selectedRole == null) return;
    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        _showErrorSnackBar('No active session found. Please log in.');
        return;
      }

      final email = user.email ?? '';
      final metaName = (user.userMetadata?['full_name'] as String?)?.trim();
      final Map<String, dynamic> upsertData = {
        'id': user.id,
        'role': _selectedRole,
      };
      if (email.isNotEmpty) {
        upsertData['email'] = email;
      }
      // Only set the name if we actually have one — never clobber the name the
      // user gave at signup with a placeholder (old bug: members became 'Admin User').
      if (metaName != null && metaName.isNotEmpty) {
        upsertData['full_name'] = metaName;
        upsertData['nickname'] = metaName.split(' ').first;
      }

      // Save selection to DB users table (Using upsert to satisfy non-null role constraint)
      await supabase.from('users').upsert(upsertData);

      if (!mounted) return;

      // Navigate based on selected role
      if (_selectedRole == 'admin') {
        Navigator.of(context).pushReplacementNamed('/admin/home');
      } else {
        Navigator.of(context).pushReplacementNamed('/member/home');
      }
    } catch (e) {
      _showErrorSnackBar(friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Leaving role-selection mid-onboarding (role still null) → sign out so /auth
  // is a clean state, not a confusing "logged-in but on the login screen" loop.
  Future<void> _exitToAuth() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    if (mounted) Navigator.of(context).pushReplacementNamed('/auth');
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final String logoAsset = isDark
        ? 'assets/images/transparent_logo_with_white_name.png'
        : 'assets/images/transparent_logo_with_black_name.png';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitToAuth();
      },
      child: Scaffold(
        backgroundColor: context.palette.scaffold,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: Icon(Icons.arrow_back, color: context.palette.textPrimary),
                    tooltip: 'Back',
                    onPressed: _exitToAuth,
                  ),
                ),
                const SizedBox(height: 12),
                // Centered branding & logo
                Center(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Image.asset(
                          logoAsset,
                          height: 54,
                          fit: BoxFit.contain,
                          semanticLabel: 'SILENCE',
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Select Your Role',
                        style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose the role that best describes you',
                        style: GoogleFonts.inter(fontSize: 14, color: context.palette.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),

                // Card 1: Admin / Library Owner
                _buildRoleCard(
                  role: 'admin',
                  title: 'Admin',
                  description: 'Runs and manages the library/study space.',
                  icon: Icons.admin_panel_settings_outlined,
                ),
                const SizedBox(height: 16),

                // Card 2: Student / Member
                _buildRoleCard(
                  role: 'member',
                  title: 'Member',
                  description: 'Studies, tracks attendance, manages membership.',
                  icon: Icons.people_outline,
                ),
                const SizedBox(height: 24),

                // Lock warning indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, size: 14, color: context.palette.textMuted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Changing your role later resets your account.',
                        style: GoogleFonts.inter(fontSize: 12, color: context.palette.textMuted, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
                const Spacer(),

                // Continue Button
                if (_selectedRole != null)
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleSaveRole,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                          )
                        : Text(
                            _selectedRole == 'admin' ? 'Continue as Library Owner' : 'Continue as Student',
                            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required String role,
    required String title,
    required String description,
    required IconData icon,
  }) {
    final isSelected = _selectedRole == role;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '$title. $description',
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedRole = role;
          });
        },
        child: Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0x14E65C00) : context.palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? const Color(0xFFE65C00) : context.palette.border,
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected ? const Color(0xFFE65C00).withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Color(0x1FE65C00), // constant light orange tint backdrop
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: const Color(0xFFE65C00)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: GoogleFonts.inter(fontSize: 13, color: context.palette.textMuted),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE65C00),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 12, color: Colors.white),
                )
              else
                Icon(Icons.chevron_right, size: 20, color: context.palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
