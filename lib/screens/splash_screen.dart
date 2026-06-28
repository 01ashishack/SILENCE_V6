import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/offline_sync.dart';
import '../utils/error_messages.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _connectionFailed = false;

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
    if (mounted) setState(() => _connectionFailed = false);
    // Enforce 1.5 seconds splash duration
    await Future.delayed(const Duration(milliseconds: 1500));

    final supabase = Supabase.instance.client;
    final session = supabase.auth.currentSession;
    final user = supabase.auth.currentUser;

    if (!mounted) return;

    if (session == null || user == null) {
      // No session -> Auth (S002)
      Navigator.of(context).pushReplacementNamed('/auth');
      return;
    }

    try {
      // Timeout so a hanging/slow network never freezes the splash forever.
      final userData = await supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;

      if (userData == null) {
        // User record was deleted server-side. Sign out and go to auth.
        await supabase.auth.signOut();
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        if (mounted) Navigator.of(context).pushReplacementNamed('/auth');
        return;
      }

      if (userData['role'] == null) {
        // Session but no role -> Role Selection (S003)
        Navigator.of(context).pushReplacementNamed('/role-select');
      } else if (userData['scheduled_for_deletion'] == true) {
        // Account scheduled for deletion → freeze (block the dashboard).
        Navigator.of(context).pushReplacementNamed('/account-frozen');
      } else if (userData['role'] == 'admin') {
        // Admin (with or without libraries) -> Admin Home (handles setup state).
        Navigator.of(context).pushReplacementNamed('/admin/home');
      } else {
        // Member -> Member Home (S040)
        Navigator.of(context).pushReplacementNamed('/member/home');
      }
    } on TimeoutException {
      // Slow / no network — keep the (valid) session and let the user retry
      // instead of force-logging-out or hanging forever.
      if (mounted) setState(() => _connectionFailed = true);
    } catch (e) {
      debugPrint('Error checking user session in splash: $e');
      if (isNetworkError(e)) {
        if (mounted) setState(() => _connectionFailed = true);
      } else {
        // A genuine (non-network) error → clean up the stale session.
        try {
          await supabase.auth.signOut();
        } catch (_) {}
        if (mounted) Navigator.of(context).pushReplacementNamed('/auth');
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
                semanticLabel: 'SILENCE — Library Management & QR Attendance',
              ),
            ),
            // Bottom: spinner while loading, or a Retry affordance if offline.
            Positioned(
              bottom: 48,
              left: 24,
              right: 24,
              child: Center(
                child: _connectionFailed
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Couldn't connect. Check your internet.",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _checkSession,
                            icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                            label: Text(
                              'Retry',
                              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                            ),
                          ),
                        ],
                      )
                    : const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
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
