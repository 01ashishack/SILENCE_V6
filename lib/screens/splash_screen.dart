import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'auth_screen.dart';
import 'role_selection_screen.dart';
import 'admin_home.dart';
import 'member_home.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();

    // Check session after splash animation
    Future.delayed(const Duration(milliseconds: 2500), _checkSession);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkSession() async {
    final supabase = Supabase.instance.client;
    final session = supabase.auth.currentSession;

    if (!mounted) return;

    if (session == null) {
      // No active session -> Navigate to Auth Screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AuthScreen()),
      );
    } else {
      // Active session -> Fetch user details from database
      final userId = session.user.id;
      try {
        final userData = await supabase
            .from('users')
            .select()
            .eq('id', userId)
            .maybeSingle();

        if (!mounted) return;

        if (userData == null || userData['role'] == null) {
          // If no user record or no role selected, go to Role Selection
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
          );
        } else {
          final String role = userData['role'];
          if (role == 'admin') {
            // Check if admin has a library configured
            final libraries = await supabase
                .from('libraries')
                .select('id')
                .eq('owner_id', userId);

            if (!mounted) return;

            final hasLibrary = libraries.isNotEmpty;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => AdminHomeScreen(startInSetupMode: !hasLibrary),
              ),
            );
          } else if (role == 'member') {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const MemberHomeScreen()),
            );
          }
        }
      } catch (e) {
        // Safe fallback in case of errors (e.g. table doesn't exist yet or connection issues)
        print('Error fetching user info: $e');
        if (mounted) {
          // Redirect to RoleSelection as safety fallback
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF97316), // Light Orange
              Color(0xFFE65C00), // Primary Orange (#E65C00)
            ],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Load premium brand assets
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/images/horizontal app logo.png',
                    width: 280,
                    height: 120,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback typography styled branding
                      return Text(
                        'SILENCE',
                        style: GoogleFonts.outfit(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2.0,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Library Management & QR Attendance',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 48),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
