import 'package:flutter/material.dart';

/// Brightness-aware semantic colours for SILENCE.
///
/// The app historically hardcodes light colours (white cards, cream scaffolds,
/// dark slate text). To support a real dark mode WITHOUT changing the light look,
/// screens should read surfaces/text/lines from this palette via `context.palette`
/// instead of hardcoding hex. Light values mirror the existing `AppColors`
/// tokens exactly, so migrating a screen is visually a no-op in light mode but
/// makes it adapt automatically in dark mode.
///
/// Registered as a [ThemeExtension] on both the light and dark [ThemeData] in
/// main.dart, so `Theme.of(context).extension<AppPalette>()` returns the right
/// set for the active brightness.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color scaffold;      // screen background
  final Color surface;       // cards / sheets
  final Color surfaceMuted;  // subtle fills (search fields, chips)
  final Color textPrimary;   // headings / body
  final Color textSecondary; // secondary text
  final Color textMuted;     // hints / captions
  final Color border;        // outlines
  final Color divider;       // hairlines
  final Color shimmerBase;
  final Color shimmerHighlight;

  const AppPalette({
    required this.scaffold,
    required this.surface,
    required this.surfaceMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.divider,
    required this.shimmerBase,
    required this.shimmerHighlight,
  });

  // Light — mirrors the current AppColors values (visual no-op in light mode).
  static const AppPalette light = AppPalette(
    scaffold: Color(0xFFFBF5EE),
    surface: Colors.white,
    surfaceMuted: Color(0xFFF8FAFC),
    textPrimary: Color(0xFF1E293B),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF94A3B8),
    border: Color(0xFFE5E7EB),
    divider: Color(0xFFF1F5F9),
    shimmerBase: Color(0xFFE9E2D8),
    shimmerHighlight: Color(0xFFF5F0E8),
  );

  // Dark — neutral charcoal surfaces; brand orange stays the same elsewhere.
  static const AppPalette dark = AppPalette(
    scaffold: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    surfaceMuted: Color(0xFF262626),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFFCBD5E1),
    textMuted: Color(0xFF94A3B8),
    border: Color(0xFF334155),
    divider: Color(0xFF2A2A2A),
    shimmerBase: Color(0xFF2A2A2A),
    shimmerHighlight: Color(0xFF3A3A3A),
  );

  @override
  AppPalette copyWith({
    Color? scaffold,
    Color? surface,
    Color? surfaceMuted,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? border,
    Color? divider,
    Color? shimmerBase,
    Color? shimmerHighlight,
  }) {
    return AppPalette(
      scaffold: scaffold ?? this.scaffold,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      shimmerBase: shimmerBase ?? this.shimmerBase,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      scaffold: Color.lerp(scaffold, other.scaffold, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      shimmerBase: Color.lerp(shimmerBase, other.shimmerBase, t)!,
      shimmerHighlight: Color.lerp(shimmerHighlight, other.shimmerHighlight, t)!,
    );
  }
}

/// Convenience accessor: `context.palette.surface`.
extension AppPaletteX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
