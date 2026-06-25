import 'package:package_info_plus/package_info_plus.dart';

/// Single source of truth for the app's version/build, read from the platform
/// package metadata (pubspec `version:`). Replaces the hardcoded, mismatched
/// version strings that were scattered across the About / Profile screens
/// (1.0.0 vs 1.0.6 vs Build 1 vs Build 42).
class AppInfo {
  AppInfo._();

  static String version = '1.0.0';
  static String build = '1';

  /// "Version 1.0.0 (Build 1)"
  static String get full => 'Version $version (Build $build)';

  /// Load once before runApp.
  static Future<void> load() async {
    try {
      final p = await PackageInfo.fromPlatform();
      if (p.version.isNotEmpty) version = p.version;
      if (p.buildNumber.isNotEmpty) build = p.buildNumber;
    } catch (_) {
      // Keep the safe defaults.
    }
  }
}
