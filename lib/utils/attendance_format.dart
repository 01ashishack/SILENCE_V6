/// Maps a raw attendance `session_type` to a short, user-friendly label and a
/// flag for whether it was a manual / admin action.
///
/// Raw values in the DB: 'normal' (QR scan), 'manual' (admin manual check-in/out
/// from the layout sheet), 'admin_edited' (admin edited a session in member
/// detail), 'incomplete', 'closed', 'absent'.
///
/// A single source of truth so the "Manual" tag reads the same everywhere —
/// analytics, member detail, history, and the CSV/PDF exports, on both panels.
class AttendanceTag {
  final String label;
  final bool isManual;
  const AttendanceTag(this.label, this.isManual);
}

AttendanceTag attendanceTag(dynamic sessionType) {
  final s = (sessionType ?? 'normal').toString().toLowerCase();
  switch (s) {
    case 'manual':
    case 'admin_edited':
      return const AttendanceTag('Manual', true);
    case 'incomplete':
      return const AttendanceTag('Incomplete', false);
    case 'closed':
      return const AttendanceTag('Closed', false);
    case 'absent':
      return const AttendanceTag('Absent', false);
    default:
      return const AttendanceTag('Auto', false);
  }
}
