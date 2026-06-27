import 'package:flutter/material.dart';
import '../core/picker_theme.dart';

/// Unified with the rest of the app: delegates to the native Material
/// [showDatePicker] themed via [brandPickerTheme] (was a bespoke 3-dropdown
/// bottom sheet with a different look). Signature kept for compatibility.
Future<DateTime?> showYearMonthDayPicker(
  BuildContext context, {
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = 'Select Date',
}) {
  final now = DateTime.now();
  final DateTime first = firstDate ?? DateTime(1950);
  final DateTime last = lastDate ?? DateTime(now.year + 10);
  DateTime initial = initialDate ?? now;
  if (initial.isBefore(first)) initial = first;
  if (initial.isAfter(last)) initial = last;

  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first,
    lastDate: last,
    helpText: title,
    builder: (ctx, child) => brandPickerTheme(ctx, child),
  );
}
