import 'package:flutter/material.dart';
import 'picker_theme.dart';

/// Unified date picker for the whole app.
///
/// Previously this rendered a bespoke grid dialog with its own colours/layout,
/// which made date selection look different from the native `showDatePicker`
/// used elsewhere. To keep ONE consistent picker (same colours, typography,
/// corner radius, buttons, animation, and full light/dark support), this now
/// delegates to Flutter's Material [showDatePicker], themed via
/// [brandPickerTheme]. The signature is unchanged so every existing call site
/// works as-is.
Future<DateTime?> showCalendarGridBottomSheet(
  BuildContext context, {
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final now = DateTime.now();
  final DateTime first = firstDate ?? DateTime(now.year - 100);
  final DateTime last = lastDate ?? DateTime(now.year + 100);
  DateTime initial = initialDate ?? now;
  // Clamp the initial date into [first, last] — showDatePicker asserts on this.
  if (initial.isBefore(first)) initial = first;
  if (initial.isAfter(last)) initial = last;

  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first,
    lastDate: last,
    builder: (ctx, child) => brandPickerTheme(ctx, child),
  );
}

/// Semantic alias kept for existing references — same unified picker.
Future<DateTime?> showCustomCalendarDialog(
  BuildContext context, {
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showCalendarGridBottomSheet(
    context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
  );
}
