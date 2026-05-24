import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'admin_home.dart';
import 'member_home.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _isLoading = false;
  String? _selectedRole;

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _saveRole(String role) async {
    setState(() {
      _selectedRole = role;
      _isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;

      if (userId == null) {
        _showErrorSnackBar('No active user session found. Please sign up or log in.');
        return;
      }

      // Save selection to the database users table
      await supabase.from('users').update({
        'role': role,
      }).eq('id', userId);

      if (!mounted) return;

      // Routing logic
      if (role == 'admin') {
        // Go to Admin Dashboard in setup mode
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const AdminHomeScreen(startInSetupMode: true),
          ),
        );
      } else {
        // Go to Member Dashboard
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const MemberHomeScreen(),
          ),
        );
      }
    } catch (e) {
      _showErrorSnackBar('Failed to save selection: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // WillPopScope/PopScope is used to prevent the user from backing out of this screen (blocking behavior)
    return PopScope(
      canPop: false, // Strongly block back navigation
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _showErrorSnackBar('Please select your profile role to continue.');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Select Your Role',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose how you want to use SILENCE. This setting is permanent.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 48),

                // Option 1: Admin / Library Owner Card
                _buildRoleCard(
                  role: 'admin',
                  title: 'Library Owner',
                  description: 'Register libraries, configure floors, seats, and shifts. Manage check-ins, payments and analytics.',
                  icon: Icons.store_outlined,
                  color: const Color(0xFFE65C00),
                ),

                const SizedBox(height: 20),

                // Option 2: Student / Member Card
                _buildRoleCard(
                  role: 'member',
                  title: 'Library Student',
                  description: 'Find study libraries in your city, request to join, check-in using QR code scanner and view attendance records.',
                  icon: Icons.school_outlined,
                  color: const Color(0xFF0F172A),
                ),

                if (_isLoading) ...[
                  const SizedBox(height: 40),
                  const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
                    ),
                  ),
                ]
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
    required Color color,
  }) {
    final isSelected = _selectedRole == role;

    return InkWell(
      onTap: _isLoading ? null : () => _saveRole(role),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(24.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.grey[200]!,
            width: isSelected ? 2.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected ? color.withOpacity(0.08) : Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 28,
                color: color,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
