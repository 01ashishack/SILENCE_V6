import 'package:intl/intl.dart';

DateTime toIST(DateTime utcTime) {
  final utc = utcTime.isUtc ? utcTime : utcTime.toUtc();
  return utc.add(const Duration(hours: 5, minutes: 30));
}

String formatTimeIST(DateTime utcTime) {
  return DateFormat('hh:mm a').format(toIST(utcTime));
}

String formatDateIST(DateTime utcTime) {
  return DateFormat('EEEE, d MMM yyyy').format(toIST(utcTime));
}

String formatDurationHMS(Duration duration) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final hours = twoDigits(duration.inHours);
  final minutes = twoDigits(duration.inMinutes.remainder(60));
  final seconds = twoDigits(duration.inSeconds.remainder(60));
  return '$hours:$minutes:$seconds';
}

String formatDurationHuman(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

DateTime parseDBTimeToUtc(String timeStr) {
  if (timeStr.endsWith('Z') || timeStr.contains('+')) {
    return DateTime.parse(timeStr).toUtc();
  }
  final dt = DateTime.parse(timeStr);
  return DateTime.utc(
    dt.year,
    dt.month,
    dt.day,
    dt.hour,
    dt.minute,
    dt.second,
    dt.millisecond,
    dt.microsecond,
  );
}

DateTime parseShiftTime(String timeStr, DateTime dateInIst) {
  final parts = timeStr.split(':');
  int hour = 0;
  int minute = 0;
  int second = 0;
  if (parts.length >= 2) {
    hour = int.tryParse(parts[0]) ?? 0;
    minute = int.tryParse(parts[1]) ?? 0;
    if (parts.length >= 3) {
      final secPart = parts[2].split(' ')[0];
      second = int.tryParse(secPart) ?? 0;
    }
  }
  if (timeStr.toLowerCase().contains('pm') && hour < 12) {
    hour += 12;
  } else if (timeStr.toLowerCase().contains('am') && hour == 12) {
    hour = 0;
  }
  return DateTime(dateInIst.year, dateInIst.month, dateInIst.day, hour, minute, second);
}

// ── Canonical IST clock (P8-01) ─────────────────────────────────────────────
// Day boundaries ("today", streaks, "studied today", closures) must use IST
// (UTC+5:30) as the single source of truth — NOT DateTime.now() (device-local)
// or a UTC date-key (off-by-one between 00:00–05:30 IST). Use these everywhere.

/// Current wall-clock time in IST.
DateTime istNow() => toIST(DateTime.now().toUtc());

/// Today at 00:00 in IST (date-only).
DateTime istToday() {
  final n = istNow();
  return DateTime(n.year, n.month, n.day);
}

/// `yyyy-MM-dd` for today, in IST.
String istTodayKey() => DateFormat('yyyy-MM-dd').format(istNow());

/// `yyyy-MM-dd` (IST) for a DB timestamp string (e.g. attendance.check_in_time),
/// tolerant of values with or without a trailing `Z`.
String istDateKeyFromDb(String dbTime) =>
    DateFormat('yyyy-MM-dd').format(toIST(parseDBTimeToUtc(dbTime)));

/// Interpret [istWallClock]'s Y/M/D/H/M/S as IST wall-clock values and return
/// the equivalent UTC instant — used to build DB query bounds (gte/lte) against
/// UTC-stored timestamps from an IST-built date range. Example: IST midnight
/// 2026-06-19 00:00 → 2026-06-18 18:30:00Z.
DateTime istWallClockToUtc(DateTime istWallClock) => DateTime.utc(
      istWallClock.year,
      istWallClock.month,
      istWallClock.day,
      istWallClock.hour,
      istWallClock.minute,
      istWallClock.second,
      istWallClock.millisecond,
    ).subtract(const Duration(hours: 5, minutes: 30));
