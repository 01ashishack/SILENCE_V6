import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/supabase_config.dart';
import 'core/offline_db.dart';
import 'screens/splash_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/role_selection_screen.dart';
import 'screens/admin_home.dart';
import 'screens/member_home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Supabase Client
  await SupabaseConfig.initialize();

  // 2. Initialize Local SQLite Offline Database Groundwork
  try {
    await OfflineDatabase.instance.database;
    print('SQLite Offline Database initialized successfully.');
  } catch (e) {
    print('SQLite Database initialization failed: $e');
  }

  runApp(const SilenceApp());
}

class SilenceApp extends StatelessWidget {
  const SilenceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SILENCE',
      debugShowCheckedModeBanner: false,
      
      // Global Brand Design System (Premium Orange Aesthetics)
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE65C00),
          primary: const Color(0xFFE65C00),
          secondary: const Color(0xFF0F172A), // Sleek Dark Slate
        ),
        scaffoldBackgroundColor: const Color(0xFFFBF5EE), // premium warm cream
        
        // Custom Typography
        textTheme: GoogleFonts.interTextTheme(
          Theme.of(context).textTheme,
        ),
        
        // Form field decorations
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE65C00), width: 1.5),
          ),
        ),
      ),

      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const AuthScreen(),
        '/auth': (context) => const AuthScreen(),
        '/role': (context) => const RoleSelectionScreen(),
        '/role-select': (context) => const RoleSelectionScreen(),
        '/admin': (context) => const AdminHomeScreen(),
        '/admin/home': (context) => const AdminHomeScreen(),
        '/member': (context) => const MemberHomeScreen(),
        '/member/home': (context) => const MemberHomeScreen(),
      },
    );
  }
}
