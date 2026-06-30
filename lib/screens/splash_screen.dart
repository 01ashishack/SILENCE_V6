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
    // The minimum splash time runs CONCURRENTLY with the session check (instead
    // of a sequential 1.5s sleep + then the query), so we route as soon as both
    // the short splash and the decision are ready — no dead time.
    final minSplash = Future.delayed(const Duration(milliseconds: 700));

    final supabase = Supabase.instance.client;
    final session = supabase.auth.currentSession;
    final user = supabase.auth.currentUser;

    if (session == null || user == null) {
      await minSplash;
      if (!mounted) return;
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
          .timeout(const Duration(seconds: 5));

      if (!mounted) return;

      if (userData == null) {
        // User record was deleted server-side. Sign out and go to auth.
        await supabase.auth.signOut();
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        await minSplash;
        if (mounted) Navigator.of(context).pushReplacementNamed('/auth');
        return;
      }

      final role = userData['role'] as String?;
      final scheduledForDeletion = userData['scheduled_for_deletion'] == true;
      // Remember the last-known routing decision so the next cold start can open
      // straight to the cached dashboard even when offline.
      await _saveLastKnown(role, scheduledForDeletion);

      await minSplash;
      if (!mounted) return;
      _routeForRole(role, scheduledForDeletion);
    } on TimeoutException {
      await _routeOfflineOrFail(minSplash);
    } catch (e) {
      debugPrint('Error checking user session in splash: $e');
      if (isNetworkError(e)) {
        await _routeOfflineOrFail(minSplash);
      } else {
        // A genuine (non-network) error → clean up the stale session.
        try {
          await supabase.auth.signOut();
        } catch (_) {}
        await minSplash;
        if (mounted) Navigator.of(context).pushReplacementNamed('/auth');
      }
    }
  }

  void _routeForRole(String? role, bool scheduledForDeletion) {
    if (role == null) {
      Navigator.of(context).pushReplacementNamed('/role-select');
    } else if (scheduledForDeletion) {
      Navigator.of(context).pushReplacementNamed('/account-frozen');
    } else if (role == 'admin') {
      Navigator.of(context).pushReplacementNamed('/admin/home');
    } else {
      Navigator.of(context).pushReplacementNamed('/member/home');
    }
  }

  Future<void> _saveLastKnown(String? role, bool scheduledForDeletion) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (role == null) {
        await prefs.remove('last_known_role');
      } else {
        await prefs.setString('last_known_role', role);
      }
      await prefs.setBool('last_known_deletion', scheduledForDeletion);
    } catch (_) {}
  }

  /// Offline / network failure WITH a valid session: open straight to the last
  /// known cached dashboard (it renders cached data + an offline banner) instead
  /// of dead-ending on a "connection failed" screen. Falls back to that screen
  /// only when we have no remembered role to route to (e.g. first launch with no
  /// network).
  Future<void> _routeOfflineOrFail(Future<void> minSplash) async {
    String? role;
    bool scheduled = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      role = prefs.getString('last_known_role');
      scheduled = prefs.getBool('last_known_deletion') ?? false;
    } catch (_) {}
    await minSplash;
    if (!mounted) return;
    if (role != null) {
      _routeForRole(role, scheduled);
    } else {
      setState(() => _connectionFailed = true);
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
