import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  // Replace these placeholders with your actual Supabase project credentials.
  static const String url = 'https://kndeshxeerldamafweru.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY';

  static Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: url,
        anonKey: anonKey,
      );
    } catch (e) {
      // Catch initialization errors (e.g. if already initialized or if credentials are empty during testing)
      print('Supabase initialization warning/error: $e');
    }
  }
}
