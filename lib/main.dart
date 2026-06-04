import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/supabase_config.dart';
import 'core/offline_db.dart';
import 'screens/splash_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/role_selection_screen.dart';
import 'screens/admin_home.dart';
import 'screens/member_home.dart';
import 'screens/admin_profile_complete.dart';
import 'screens/library_setup_stage1.dart';
import 'screens/library_setup_stage2.dart';
import 'screens/library_setup_stage3.dart';
import 'screens/reservations/member_detail_screen.dart';

// Milestone 5 remaining Admin Panel screens imports
import 'screens/library_profile_screen.dart';
import 'screens/social_links_edit_screen.dart';
import 'screens/about_us_screen.dart';
import 'screens/help_support_screen.dart';
import 'screens/terms_screen.dart';
import 'screens/app_settings_screen.dart';
import 'screens/verified_badge_screen.dart';
import 'screens/pricing_plans.dart';
import 'screens/shift_management.dart';
import 'screens/business_rules.dart';
import 'screens/branding_assets.dart';
import 'screens/qr_assets.dart';
import 'screens/addon_services.dart';
import 'screens/notification_preferences.dart';
import 'screens/export_center.dart';
import 'screens/subscription_screen.dart';
import 'screens/audit_log_screen.dart';
import 'screens/referral_settings.dart';
import 'screens/scheduled_closures.dart';
import 'screens/announcements_history_screen.dart';

import 'screens/admin/add_member_wizard.dart';

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
        
        // Dialog and Bottom Sheet themes set to crisp white
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        
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
        '/admin/profile/complete': (context) => const AdminProfileCompleteScreen(),
        '/admin/library/setup/1': (context) => const LibrarySetupStage1Screen(),
        '/admin/library/setup/2': (context) => const LibrarySetupStage2Screen(),
        '/admin/library/setup/3': (context) => const LibrarySetupStage3Screen(),
        '/admin/member': (context) => const MemberDetailScreen(),

        // Milestone 5 Admin routes registrations
        '/admin/library/profile': (context) => const LibraryProfileScreen(),
        '/admin/settings/social-links': (context) => const SocialLinksEditScreen(),
        '/admin/about-us': (context) => const AboutUsScreen(),
        '/admin/help-support': (context) => const HelpSupportScreen(),
        '/admin/terms': (context) => const TermsScreen(),
        '/admin/app-settings': (context) => const AppSettingsScreen(),
        '/admin/verified-badge': (context) => const VerifiedBadgeScreen(),
        '/admin/settings/shifts': (context) => const ShiftManagementScreen(),
        '/admin/settings/pricing': (context) => const PricingPlansScreen(),
        '/admin/settings/business-rules': (context) => const BusinessRulesScreen(),
        '/admin/settings/branding': (context) => const BrandingAssetsScreen(),
        '/admin/settings/qr': (context) => const QRAssetsScreen(),
        '/admin/settings/addons': (context) => const AddonServicesScreen(),
        '/admin/settings/notifications': (context) => const NotificationPreferencesScreen(),
        '/admin/exports': (context) => const ExportCenterScreen(),
        '/admin/announcements': (context) => const AnnouncementsHistoryScreen(),
        '/admin/subscription': (context) => const SubscriptionScreen(),
        '/admin/audit-log': (context) => const AuditLogScreen(),
        '/admin/settings/referrals': (context) => const ReferralSettingsScreen(),
        '/admin/settings/closures': (context) => const ScheduledClosuresScreen(),
        '/admin/member/add': (context) => const AddMemberWizard(),
      },
    );
  }
}
