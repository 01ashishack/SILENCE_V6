import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/supabase_config.dart';
import 'core/offline_db.dart';
import 'screens/splash_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/role_selection_screen.dart';
import 'screens/admin_home.dart';
import 'screens/member_home.dart';
import 'screens/member_profile_edit.dart';
import 'screens/library_public_profile_screen.dart';
import 'screens/member_explore_screen.dart';
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
import 'screens/preview/admin_home_v2.dart';
import 'screens/referral_settings.dart';
import 'screens/scheduled_closures.dart';
import 'screens/announcements_history_screen.dart';
import 'screens/member_notification_preferences_screen.dart';
import 'screens/member_privacy_security_screen.dart';
import 'screens/member_help_support_screen.dart';
import 'screens/member_about_screen.dart';
import 'screens/member_terms_screen.dart';
import 'screens/member_privacy_policy_screen.dart';
import 'screens/member_licences_screen.dart';
import 'screens/notifications_screen.dart';

import 'screens/account_frozen_screen.dart';
import 'screens/owner_recovery_console_screen.dart';

import 'screens/admin/add_member_wizard.dart';
import 'screens/reservations/renewal_screen.dart';
import 'screens/reservations/library_query_screen.dart';
import 'screens/member_analytics_tab.dart';
import 'screens/past_library_detail_screen.dart';
import 'screens/admin/all_reviews_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'services/push_notification_service.dart';
/// Handles a push that arrives while the app is in the background or terminated.
/// Must be a top-level function and re-init Firebase (it runs in its own isolate).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('FCM background message: ${message.messageId}');
}

void main() {
  // Global crash safety net: route Flutter framework errors AND any uncaught
  // async error in the app to one place (visible in debug, logged in release) —
  // replaces silent red screens / swallowed crashes (audit P12-01).
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };

  // Initialize Firebase + register the background message handler BEFORE runApp.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }

  // Consistent status bar across all screens: orange background + light icons
  // so the safe-area / top bar always matches the brand color.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFFE65C00),
    statusBarIconBrightness: Brightness.light, // Android icons
    statusBarBrightness: Brightness.dark, // iOS icons
  ));

  // 1. Initialize Supabase Client
  await SupabaseConfig.initialize();

  // 1b. Wire push notifications (permission, token → users.fcm_token, handlers).
  await PushNotificationService.instance.initialize();

  // 2. Initialize Local SQLite Offline Database Groundwork
  try {
    await OfflineDatabase.instance.database;
    debugPrint('SQLite Offline Database initialized successfully.');
  } catch (e) {
    debugPrint('SQLite Database initialization failed: $e');
  }

  runApp(const SilenceApp());
  }, (Object error, StackTrace stack) {
    // Last-resort handler for uncaught async errors anywhere in the app.
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

class SilenceApp extends StatelessWidget {
  const SilenceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SILENCE',
      debugShowCheckedModeBanner: false,
      navigatorKey: PushNotificationService.navigatorKey,
      
      // Global Brand Design System (Premium Orange Aesthetics)
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE65C00),
          primary: const Color(0xFFE65C00),
          secondary: const Color(0xFF0F172A), // Sleek Dark Slate
        ),
        scaffoldBackgroundColor: const Color(0xFFFBF5EE), // premium warm cream

        // Keep every AppBar on-brand: orange bar + white foreground + light
        // status-bar icons (so the top never looks different per screen).
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFE65C00),
          foregroundColor: Colors.white,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Color(0xFFE65C00),
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
        ),
        
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
        '/auth': (context) => const AuthScreen(),
        '/role-select': (context) => const RoleSelectionScreen(),
        '/admin/home': (context) => const AdminHomeScreen(),
        '/member/home': (context) => const MemberHomeScreen(),
        '/member/explore': (context) => const ExploreScreen(),
        '/member/library-profile': (context) => const LibraryPublicProfileScreen(isAdmin: false),
        '/member/edit-profile': (context) => const MemberProfileEditScreen(),
        '/member/settings/notifications': (context) => const MemberNotificationPreferencesScreen(),
        '/member/settings/privacy': (context) => const MemberPrivacySecurityScreen(),
        '/member/help': (context) => const MemberHelpSupportScreen(),
        '/member/about': (context) => const MemberAboutScreen(),
        '/member/terms': (context) => const MemberTermsScreen(),
        '/member/privacy-policy': (context) => const MemberPrivacyPolicyScreen(),
        '/member/licences': (context) => const MemberLicencesScreen(),
        '/member/notifications': (context) => const NotificationsScreen(),
        '/account-frozen': (context) => const AccountFrozenScreen(),
        '/owner/recovery-console': (context) => const OwnerRecoveryConsoleScreen(),
        '/admin/profile/complete': (context) => const AdminProfileCompleteScreen(),
        '/admin/library/setup/1': (context) => const LibrarySetupStage1Screen(),
        '/admin/library/setup/2': (context) => const LibrarySetupStage2Screen(),
        '/admin/library/setup/3': (context) => const LibrarySetupStage3Screen(),
        '/admin/member': (context) => const MemberDetailScreen(),

        // Milestone 5 Admin routes registrations
        '/admin/library/profile': (context) => const LibraryProfileScreen(),
        '/admin/all-reviews': (context) {
          final libraryId = ModalRoute.of(context)?.settings.arguments as String? ?? '';
          return AllReviewsScreen(libraryId: libraryId);
        },
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
        '/preview/admin-v2': (context) => const AdminHomeV2(),
        '/admin/settings/referrals': (context) => const ReferralSettingsScreen(),
        '/admin/settings/closures': (context) => const ScheduledClosuresScreen(),
        '/admin/member/add': (context) => const AddMemberWizard(),
        '/member/renewal': (context) {
          final args = (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?) ?? {};
          return RenewalScreen(
            libraryId: args['libraryId'] ?? '',
            initialPlan: args['initialPlan'],
            initialShiftId: args['initialShiftId'],
          );
        },
        '/member/query': (context) {
          final args = (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?) ?? {};
          return LibraryQueryScreen(
            libraryId: args['libraryId'] ?? '',
            preFilledMessage: args['preFilledMessage'],
          );
        },
        '/member/analytics': (context) {
          final args = (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?) ?? {};
          return MemberAnalyticsTab(
            userProfile: args['userProfile'],
            activeLibraryId: args['activeLibraryId'],
            memberLibraries: args['memberLibraries'] ?? [],
          );
        },
        '/member/library-history': (context) {
          final args = (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?) ?? {};
          return PastLibraryDetailScreen(
            membershipId: args['membershipId'] ?? '',
          );
        },
      },
    );
  }
}
