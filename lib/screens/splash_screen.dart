import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    // Enforce 1.5 seconds splash duration
    await Future.delayed(const Duration(milliseconds: 1500));
    
    final supabase = Supabase.instance.client;
    final session = supabase.auth.currentSession;

    if (!mounted) return;

    if (session == null) {
      // 2. No session -> navigate to Auth (S002)
      Navigator.of(context).pushReplacementNamed('/auth');
    } else {
      final userId = session.user.id;
      try {
        // Fetch user metadata
        final userData = await supabase
            .from('users')
            .select()
            .eq('id', userId)
            .maybeSingle();

        if (!mounted) return;

        if (userData == null || userData['role'] == null) {
          // 3. Session but no role -> navigate to Role Selection (S003)
          Navigator.of(context).pushReplacementNamed('/role-select');
        } else {
          final String role = userData['role'];
          if (role == 'admin') {
            // Check library count for admin
            final libraries = await supabase
                .from('libraries')
                .select('id')
                .eq('owner_id', userId);

            if (!mounted) return;

            final hasLibrary = libraries.isNotEmpty;
            if (!hasLibrary) {
              // 4. Admin + 0 libraries -> navigate to Setup Mode Admin Home with modal/setup card
              Navigator.of(context).pushReplacementNamed('/admin/home');
            } else {
              // 4. Admin + >0 libraries -> navigate to Admin Home (Operational)
              Navigator.of(context).pushReplacementNamed('/admin/home');
            }
          } else if (role == 'member') {
            // 5. Member -> navigate to Member Home (S040)
            Navigator.of(context).pushReplacementNamed('/member/home');
          }
        }
      } catch (e) {
        debugPrint('Error checking user session in splash: $e');
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/role-select');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF5EE), // warm cream background
      body: SafeArea(
        child: Stack(
          children: [
            // Center Brand Content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo Placeholder / Brand Icon
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3ED),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE65C00), width: 2),
                    ),
                    child: const Icon(
                      Icons.book_outlined,
                      size: 40,
                      color: Color(0xFFE65C00),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Silence',
                    style: GoogleFonts.outfit(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'LIBRARY MANAGEMENT & QR',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6B7280),
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            // Bottom Loading Indicator
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 24,
                  height: 24,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
