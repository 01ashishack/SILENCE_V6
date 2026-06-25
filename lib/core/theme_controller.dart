import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide theme mode (light/dark), persisted in SharedPreferences and exposed
/// as a [ValueNotifier] so the root [MaterialApp] rebuilds when it changes.
///
/// This makes the Dark Mode toggle a REAL action (no more "simulated" success).
/// Note: many screens still hardcode light colours, so full dark-mode visual
/// polish across every screen is a follow-up; the mechanism itself is real.
class ThemeController {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const String _key = 'app_theme_mode';

  final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(ThemeMode.light);

  bool get isDark => mode.value == ThemeMode.dark;

  /// Restore the saved preference. Call once before runApp.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key);
      mode.value = (v == 'dark') ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {
      mode.value = ThemeMode.light;
    }
  }

  Future<void> setDark(bool dark) async {
    mode.value = dark ? ThemeMode.dark : ThemeMode.light;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, dark ? 'dark' : 'light');
    } catch (_) {
      // Persisting the theme is best-effort.
    }
  }
}
