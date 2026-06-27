import 'package:flutter/material.dart';
import 'theme_controller.dart';

/// Brightness-aware theme wrapper for `showDatePicker` / `showTimePicker`.
///
/// Many screens used to force `ColorScheme.light(...)` inside the picker
/// `builder`, which kept the picker white even in dark mode. Use this instead:
///
/// ```dart
/// showDatePicker(
///   context: context,
///   ...,
///   builder: (ctx, child) => brandPickerTheme(ctx, child),
/// );
/// ```
///
/// Keeps the brand-orange accent in both themes and a readable surface/text.
Widget brandPickerTheme(BuildContext context, Widget? child) {
  final bool isDark = ThemeController.instance.isDark ||
      Theme.of(context).brightness == Brightness.dark;

  final ColorScheme scheme = isDark
      ? const ColorScheme.dark(
          primary: Color(0xFFE65C00),
          onPrimary: Colors.white,
          surface: Color(0xFF1E1E1E),
          onSurface: Color(0xFFF1F5F9),
        )
      : const ColorScheme.light(
          primary: Color(0xFFE65C00),
          onPrimary: Colors.white,
          onSurface: Color(0xFF1E293B),
        );

  return Theme(
    data: Theme.of(context).copyWith(
      colorScheme: scheme,
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      ),
    ),
    child: child!,
  );
}
