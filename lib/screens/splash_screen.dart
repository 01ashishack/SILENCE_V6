import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/offline_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    OfflineSyncManager.instance.startListening(context);
    // Trigger initial sync if online on app startup
    Connectivity().checkConnectivity().then((results) {
      final bool hasInternet = !results.contains(ConnectivityResult.none) && results.isNotEmpty;
      if (hasInternet && mounted) {
        OfflineSyncManager.instance.syncPendingScans(context);
      }
    });
    _checkSession();
  }

  Future<void> _checkSession() async {
    // Enforce 1.5 seconds splash duration
    await Future.delayed(const Duration(milliseconds: 1500));
    
    final supabase = Supabase.instance.client;
    final session = supabase.auth.currentSession;
    final user = supabase.auth.currentUser;

    if (!mounted) return;

    if (session == null || user == null) {
      // 2. No session -> navigate to Auth (S002)
      Navigator.of(context).pushReplacementNamed('/auth');
    } else {
      final userId = user.id;
      try {
        // Fetch user metadata
        final userData = await supabase
            .from('users')
            .select()
            .eq('id', userId)
            .maybeSingle();

        if (!mounted) return;

        if (userData == null) {
          // User record was deleted. Sign out and go to auth.
          await supabase.auth.signOut();
          final prefs = await SharedPreferences.getInstance();
          await prefs.clear();
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/auth');
          }
          return;
        }

        if (userData['role'] == null) {
          // 3. Session but no role -> navigate to Role Selection (S003)
          Navigator.of(context).pushReplacementNamed('/role-select');
        } else if (userData['scheduled_for_deletion'] == true) {
          // Account scheduled for deletion → freeze (block the dashboard).
          Navigator.of(context).pushReplacementNamed('/account-frozen');
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
          final navigator = Navigator.of(context);
          // Clean up stale or invalid session state and route to /auth
          try {
            await supabase.auth.signOut();
          } catch (_) {}
          navigator.pushReplacementNamed('/auth');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE65C00), // Premium orange background
      body: SafeArea(
        child: Stack(
          children: [
            // Center Brand Content
            Center(
              child: Image.asset(
                'assets/images/WHITE_WITH_TAGLINE.png',
                width: 250,
                fit: BoxFit.contain,
              ),
            ),
            // Bottom Loading Indicator
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
