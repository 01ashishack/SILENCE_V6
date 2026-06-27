import 'package:flutter/material.dart';

/// SILENCE design tokens — single source of truth for the brand palette.
///
/// These values mirror the colors already used inline across the codebase
/// (primary `#E65C00`, slate `#0F172A`, cream scaffold `#FBF5EE`, etc.) so that
/// adopting [AppColors] never changes how an existing screen looks. New widgets
/// and refactors should reference these tokens instead of hardcoding hex values,
/// which keeps the color hierarchy consistent as the UI overhaul proceeds.
class AppColors {
  AppColors._();

  // ── Brand ────────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFFE65C00); // brand orange
  static const Color primaryDark = Color(0xFFB44900); // pressed / deep orange
  static const Color primaryLight = Color(0xFFFF6B00); // header gradient top
  static const Color secondary = Color(0xFF0F172A); // sleek dark slate

  // Canonical brand header gradient (top-left → bottom-right). Use everywhere a
  // curved orange header is drawn so the shade never drifts (#FF6B00 → #E65C00).
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryLight, primary],
  );

  // Standard card corner radius across the app.
  static const double cardRadius = 16.0;

  // ── Surfaces ─────────────────────────────────────────────────────────────
  static const Color scaffold = Color(0xFFFBF5EE); // premium warm cream
  static const Color surface = Colors.white;
  static const Color surfaceMuted = Color(0xFFF8FAFC); // very light slate

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF1E293B); // headings / body
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF94A3B8); // hints / captions

  // ── Lines ────────────────────────────────────────────────────────────────
  static const Color border = Color(0xFFE5E7EB);
  static const Color divider = Color(0xFFF1F5F9);

  // ── Orange tints (cards / chips) — translucent so they adapt to light/dark
  //    surfaces (faint orange on white, subtle orange on charcoal). ──────────
  static const Color orangeTintBg = Color(0x1FE65C00);
  static const Color orangeTintBorder = Color(0x33E65C00);
  static const Color orangeText = Color(0xFFF97316); // readable on light + dark orange tints

  // ── Status ───────────────────────────────────────────────────────────────
  // Background tints are translucent so they read correctly on light AND dark.
  static const Color success = Color(0xFF22C55E);
  static const Color successBg = Color(0x1F22C55E);
  static const Color warning = Color(0xFFF59E0B); // amber (expiring soon)
  static const Color warningBg = Color(0x1FF59E0B);
  static const Color danger = Color(0xFFEF4444); // red (expired / errors)
  static const Color dangerBg = Color(0x1FEF4444);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoBg = Color(0x1F3B82F6);

  // ── Shimmer (skeleton loaders) ───────────────────────────────────────────
  static const Color shimmerBase = Color(0xFFE9E2D8); // tinted for cream bg
  static const Color shimmerHighlight = Color(0xFFF5F0E8);
}
