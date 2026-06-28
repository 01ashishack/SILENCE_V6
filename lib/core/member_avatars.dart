import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A selectable preset avatar (icon + colour). Members pick one of these instead
/// of uploading a real photo — privacy-friendly and zero asset management.
class MemberAvatar {
  final IconData icon;
  final Color color;
  const MemberAvatar(this.icon, this.color);
}

/// The 10 preloaded avatars. Index in this list == `users.avatar_id`.
/// Append-only (never reorder) so stored ids keep meaning.
const List<MemberAvatar> kMemberAvatars = [
  MemberAvatar(Icons.person_rounded, Color(0xFF3B82F6)),
  MemberAvatar(Icons.school_rounded, Color(0xFFE65C00)),
  MemberAvatar(Icons.auto_stories_rounded, Color(0xFF10B981)),
  MemberAvatar(Icons.rocket_launch_rounded, Color(0xFF7C3AED)),
  MemberAvatar(Icons.bolt_rounded, Color(0xFFF59E0B)),
  MemberAvatar(Icons.pets_rounded, Color(0xFFEC4899)),
  MemberAvatar(Icons.sports_esports_rounded, Color(0xFF6366F1)),
  MemberAvatar(Icons.music_note_rounded, Color(0xFFEF4444)),
  MemberAvatar(Icons.local_cafe_rounded, Color(0xFF92400E)),
  MemberAvatar(Icons.emoji_emotions_rounded, Color(0xFF0EA5E9)),
];

/// Palette for the initials fallback (when a member hasn't picked an avatar).
const List<Color> _initialsPalette = [
  Color(0xFFE65C00), Color(0xFF3B82F6), Color(0xFF10B981),
  Color(0xFF7C3AED), Color(0xFFEC4899), Color(0xFF0EA5E9), Color(0xFFF59E0B),
];

Color _initialsColor(String name) {
  if (name.isEmpty) return _initialsPalette.first;
  final h = name.codeUnits.fold<int>(0, (a, b) => a + b);
  return _initialsPalette[h % _initialsPalette.length];
}

String _initials(String name) {
  final n = name.trim();
  if (n.isEmpty) return '?';
  final parts = n.split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[1].isNotEmpty) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  return n[0].toUpperCase();
}

/// Renders a member's avatar: the chosen preset icon when [avatarId] is a valid
/// index, otherwise a coloured initials circle derived from [name].
class MemberAvatarView extends StatelessWidget {
  final int? avatarId;
  final String name;
  final double radius;
  final Color? ring;

  const MemberAvatarView({
    super.key,
    required this.avatarId,
    required this.name,
    this.radius = 20,
    this.ring,
  });

  @override
  Widget build(BuildContext context) {
    final Widget inner;
    if (avatarId != null && avatarId! >= 0 && avatarId! < kMemberAvatars.length) {
      final a = kMemberAvatars[avatarId!];
      inner = CircleAvatar(
        radius: radius,
        backgroundColor: a.color.withValues(alpha: 0.18),
        child: Icon(a.icon, size: radius * 1.05, color: a.color),
      );
    } else {
      final c = _initialsColor(name);
      inner = CircleAvatar(
        radius: radius,
        backgroundColor: c.withValues(alpha: 0.18),
        child: Text(_initials(name),
            style: GoogleFonts.outfit(
                fontSize: radius * 0.8, fontWeight: FontWeight.bold, color: c)),
      );
    }
    if (ring == null) return inner;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
      child: CircleAvatar(
        radius: radius + 2.5,
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: inner,
      ),
    );
  }
}
