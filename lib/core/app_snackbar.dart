import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralised, consistent snackbars for SILENCE.
///
/// Why: success messages used to use the brand orange, which blended into the
/// app's orange UI. Now every snackbar has a clear, semantic colour, a floating
/// rounded shape, and consistent typography — and it renders ABOVE any open
/// BottomSheet/Dialog because it uses the *root* [ScaffoldMessenger].
///
/// Usage:
/// ```dart
/// AppSnackbar.success(context, 'Saved ✓');
/// AppSnackbar.error(context, friendlyError(e));
/// AppSnackbar.warning(context, 'Heads up…');
/// AppSnackbar.info(context, 'FYI…');
/// ```
class AppSnackbar {
  AppSnackbar._();

  // Semantic colours (white text sits on all of these with good contrast).
  static const Color _success = Color(0xFF16A34A); // green-600
  static const Color _error = Color(0xFFDC2626); // red-600
  static const Color _warning = Color(0xFFD97706); // amber-600
  static const Color _info = Color(0xFF334155); // slate-700

  static void success(BuildContext context, String message) =>
      _show(context, message, _success, Icons.check_circle_rounded);

  static void error(BuildContext context, String message) =>
      _show(context, message, _error, Icons.error_rounded);

  static void warning(BuildContext context, String message) =>
      _show(context, message, _warning, Icons.warning_amber_rounded);

  static void info(BuildContext context, String message) =>
      _show(context, message, _info, Icons.info_rounded);

  static void _show(
    BuildContext context,
    String message,
    Color bg,
    IconData icon,
  ) {
    // Root messenger → the snackbar floats above bottom sheets / dialogs and is
    // never trapped between a sheet and the screen.
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: bg,
          elevation: 6,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
