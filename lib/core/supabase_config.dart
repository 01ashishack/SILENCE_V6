import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  // Replace these placeholders with your actual Supabase project credentials.
  static const String url = 'https://kndeshxeerldamafweru.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY';

  // ── Google Sign-In ──────────────────────────────────────────────────────
  // Native Google sign-in (google_sign_in v7) needs the **Web** OAuth client ID
  // (NOT the Android one) as `serverClientId`. Create it in Google Cloud Console
  // → APIs & Services → Credentials → "Web application", then paste it here AND
  // register it (plus the Android client ID) in Supabase → Auth → Providers →
  // Google. The Android client ID isn't referenced in code — Android matches the
  // app by package name (com.silence.app.silence) + SHA-1 fingerprint instead.
  // While this is empty the Google button shows a friendly "not configured" msg.
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '1085738355311-4pbt15ndhhcngedpp28ob8ru2bsl7bdl.apps.googleusercontent.com',
  );

  // Optional: iOS Google OAuth client ID (only needed for an iOS build).
  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  static Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: url,
        anonKey: anonKey,
      );
    } catch (e) {
      // Catch initialization errors (e.g. if already initialized or if credentials are empty during testing)
      debugPrint('Supabase initialization warning/error: $e');
    }
  }
}
