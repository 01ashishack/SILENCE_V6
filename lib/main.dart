import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kReleaseMode, LicenseRegistry, LicenseEntryWithLineBreaks;
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/supabase_config.dart';
import 'core/offline_db.dart';
import 'core/theme_controller.dart';
import 'core/app_info.dart';
import 'theme/app_palette.dart';
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
import 'screens/marketing_posters_screen.dart';
import 'screens/qr_assets.dart';
import 'screens/addon_services.dart';
import 'screens/notification_preferences.dart';
import 'screens/export_center.dart';
import 'screens/subscription_screen.dart';
import 'screens/audit_log_screen.dart';
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
import 'screens/member_blocked_users_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/policy_screens.dart';

import 'screens/account_frozen_screen.dart';
import 'screens/owner_recovery_console_screen.dart';
import 'screens/owner_abuse_reports_screen.dart';

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

    // L6: in release builds, silence debugPrint so member IDs / library codes
    // logged throughout the app never leak to device logs. Verbose in debug.
    if (kReleaseMode) {
      debugPrint = (String? message, {int? wrapWidth}) {};
    }

    // Perf (low-RAM phones): cap the in-memory image cache so a few large
    // photos can't blow up RAM. Default is ~100MB / 1000 entries.
    PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // 50 MB
    PaintingBinding.instance.imageCache.maximumSize = 200;           // 200 images

    // Restore the saved theme (light/dark) before the app builds.
    await ThemeController.instance.load();
    // Load the real app version/build (single source for About/Profile screens).
    await AppInfo.load();

    // Perf (first-paint jank): the common Inter/Outfit weights are bundled in
    // assets/google_fonts/, so GoogleFonts uses them directly (no network fetch
    // → no text flash on first run). Runtime fetching stays ON as a safety net
    // for any rare unbundled variant (e.g. italics). Register the bundled fonts'
    // OFL-1.1 license so it shows in the app's licence list.
    LicenseRegistry.addLicense(() async* {
      try {
        final license = await rootBundle.loadString('assets/google_fonts/OFL.txt');
        yield LicenseEntryWithLineBreaks(['google_fonts'], license);
      } catch (_) {
        // License file missing from the bundle — skip silently.
      }
    });

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
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.mode,
      builder: (context, themeMode, _) {
        return MaterialApp(
      title: 'SILENCE',
      debugShowCheckedModeBanner: false,
      navigatorKey: PushNotificationService.navigatorKey,
      themeMode: themeMode,
      darkTheme: _buildDarkTheme(),

      // Global Brand Design System (Premium Orange Aesthetics)
      theme: ThemeData(
        useMaterial3: true,
        extensions: const [AppPalette.light],
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

        // Floating snackbars (consistent radius/animation app-wide), matching
        // the dark theme. Per-call green/red backgrounds still take precedence.
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E293B),
          contentTextStyle: const TextStyle(color: Colors.white),
          actionTextColor: const Color(0xFFFFD8BE),
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        datePickerTheme: const DatePickerThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          headerBackgroundColor: Color(0xFFE65C00),
          headerForegroundColor: Colors.white,
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        
        // Custom Typography. Build from a concrete Typography (NOT
        // Theme.of(context) — that context is above this MaterialApp, so it
        // yields the framework default and silently drops our theme) (H5).
        textTheme: GoogleFonts.interTextTheme(
          Typography.material2021().black,
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
        '/member/blocked-users': (context) => const MemberBlockedUsersScreen(),
        '/policy/refund': (context) => const RefundPolicyScreen(),
        '/policy/cancellation': (context) => const CancellationPolicyScreen(),
        '/policy/community': (context) => const CommunityGuidelinesScreen(),
        '/member/notifications': (context) => const NotificationsScreen(),
        '/account-frozen': (context) => const AccountFrozenScreen(),
        '/owner/recovery-console': (context) => const OwnerRecoveryConsoleScreen(),
        '/owner/abuse-reports': (context) => const OwnerAbuseReportsScreen(),
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
        '/admin/marketing-posters': (context) => const MarketingPostersScreen(),
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
      },
    );
  }

  /// Dark theme — real, persisted via ThemeController. AppBars stay brand-orange.
  /// (Per-screen polish for screens that hardcode light colours is a follow-up.)
  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      extensions: const [AppPalette.dark],
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFE65C00),
        brightness: Brightness.dark,
        primary: const Color(0xFFE65C00),
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      cardColor: const Color(0xFF1E1E1E),
      // Legacy DropdownButton menus read their background from canvasColor;
      // keep it dark so any dropdown we didn't touch still adapts.
      canvasColor: const Color(0xFF1E1E1E),
      dividerColor: const Color(0xFF2A2A2A),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF1E1E1E),
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF1E1E1E),
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: Color(0xFF1E1E1E),
      ),
      // Dropdown menus (M3 DropdownMenu + legacy DropdownButton popups).
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(Color(0xFF1E1E1E)),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF1E1E1E),
        surfaceTintColor: Colors.transparent,
        textStyle: const TextStyle(color: Color(0xFFF1F5F9)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(Color(0xFF1E1E1E)),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      // Floating snackbars so they sit ABOVE bottom sheets/dialogs and look
      // identical app-wide. Per-call backgroundColor (green/red) still wins.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF262626),
        contentTextStyle: const TextStyle(color: Color(0xFFF1F5F9)),
        actionTextColor: const Color(0xFFE65C00),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF262626),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 12),
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: Color(0xFF1E1E1E),
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: Color(0xFFE65C00),
        headerForegroundColor: Colors.white,
      ),
      timePickerTheme: const TimePickerThemeData(
        backgroundColor: Color(0xFF1E1E1E),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Color(0xFF1E1E1E),
        collapsedBackgroundColor: Color(0xFF1E1E1E),
        textColor: Color(0xFFF1F5F9),
        collapsedTextColor: Color(0xFFF1F5F9),
        iconColor: Color(0xFFE65C00),
        collapsedIconColor: Color(0xFF94A3B8),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: Color(0xFFCBD5E1),
        textColor: Color(0xFFF1F5F9),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF2A2A2A)),
      iconTheme: const IconThemeData(color: Color(0xFFCBD5E1)),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Color(0xFFE65C00),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Color(0xFFE65C00),
        selectionColor: Color(0x55E65C00),
        selectionHandleColor: Color(0xFFE65C00),
      ),
      // Selection controls: brand-orange when on/checked/selected.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? const Color(0xFFE65C00) : const Color(0xFF94A3B8)),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? const Color(0x55E65C00) : const Color(0xFF3A3A3A)),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? const Color(0xFFE65C00) : Colors.transparent),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: Color(0xFF94A3B8)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? const Color(0xFFE65C00) : const Color(0xFF94A3B8)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF262626),
        selectedColor: const Color(0x33E65C00),
        labelStyle: const TextStyle(color: Color(0xFFF1F5F9)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFFF1F5F9)),
        side: const BorderSide(color: Color(0xFF334155)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
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
      textTheme: GoogleFonts.interTextTheme(
        Typography.material2021().white,
      ),
      // Dark form fields: dark fill + visible borders so typed text (light) is
      // readable. Screens that hardcode `fillColor: Colors.white` use
      // `context.palette.surface` so they adapt too.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
        labelStyle: const TextStyle(color: Color(0xFFCBD5E1)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF334155), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE65C00), width: 1.5),
        ),
      ),
    );
  }
}
