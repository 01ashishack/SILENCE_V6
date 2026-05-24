import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  // Replace these placeholders with your actual Supabase project credentials.
  static const String url = 'https://your-supabase-project.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.your-anon-key';

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
