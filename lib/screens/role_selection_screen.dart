import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
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
      final Map<String, dynamic> upsertData = {
        'id': user.id,
        'role': _selectedRole,
        'full_name': user.userMetadata?['full_name'] ?? 'Admin User',
        'nickname': (user.userMetadata?['full_name'] as String?)?.split(' ').first ?? 'Admin',
      };
      if (email.isNotEmpty) {
        upsertData['email'] = email;
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
      _showErrorSnackBar('Failed to save selection: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pushReplacementNamed('/auth');
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
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A2E)),
                    onPressed: () {
                      Navigator.of(context).pushReplacementNamed('/auth');
                    },
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
                          'assets/images/transparent_logo_with_black_name.png',
                          height: 54,
                          fit: BoxFit.contain,
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
                    const Icon(Icons.lock_outline, size: 14, color: Color(0xFF9CA3AF)),
                    const SizedBox(width: 6),
                    Text(
                      'You cannot change your role after selection.',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF9CA3AF), fontStyle: FontStyle.italic),
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

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedRole = role;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFE65C00) : const Color(0xFFE5E7EB),
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
              const Icon(Icons.chevron_right, size: 20, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }
}
