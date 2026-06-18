import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  // Replace these placeholders with your actual Supabase project credentials.
  static const String url = 'https://kndeshxeerldamafweru.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY';

  /// The APP OWNER's user id (your account). Only this account sees the
  /// Recovery Console and can approve/deny account-recovery requests.
  /// TODO: set this to your real app-owner account id.
  static const String appOwnerUserId = '1ce8bdfb-8364-4eef-91e1-aa70ab84edc1';

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
