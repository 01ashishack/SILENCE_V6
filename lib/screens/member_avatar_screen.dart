import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_snackbar.dart';
import '../core/member_avatars.dart';
import '../theme/app_palette.dart';
import '../utils/error_messages.dart';

/// Lets a member pick a preset avatar (one of [kMemberAvatars]) and edit their
/// nickname. Both are shown on the leaderboard.
class MemberAvatarScreen extends StatefulWidget {
  const MemberAvatarScreen({super.key});

  @override
  State<MemberAvatarScreen> createState() => _MemberAvatarScreenState();
}

class _MemberAvatarScreenState extends State<MemberAvatarScreen> {
  final _sb = Supabase.instance.client;
  final _nickCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  int? _avatarId;
  String _fullName = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nickCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid != null) {
        final row = await _sb
            .from('users')
            .select('avatar_id, nickname, full_name')
            .eq('id', uid)
            .maybeSingle();
        if (row != null) {
          _avatarId = (row['avatar_id'] as num?)?.toInt();
          _fullName = (row['full_name'] ?? '').toString();
          _nickCtrl.text = (row['nickname'] ?? '').toString();
        }
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final nick = _nickCtrl.text.trim();
    if (nick.isEmpty) {
      AppSnackbar.warning(context, 'Please enter a nickname.');
      return;
    }
    setState(() => _saving = true);
    try {
      final uid = _sb.auth.currentUser!.id;
      await _sb.from('users').update({
        'avatar_id': _avatarId,
        'nickname': nick,
      }).eq('id', uid);
      if (!mounted) return;
      AppSnackbar.success(context, 'Avatar & nickname updated ✓');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackbar.error(context, friendlyError(e));
    }
  }

  String get _previewName => _nickCtrl.text.trim().isEmpty ? _fullName : _nickCtrl.text.trim();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.scaffold,
      appBar: AppBar(
        backgroundColor: const Color(0xFFE65C00),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Avatar & Nickname', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Live preview
                Center(
                  child: MemberAvatarView(
                    avatarId: _avatarId,
                    name: _previewName,
                    radius: 44,
                    ring: const Color(0xFFE65C00),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(_previewName.isEmpty ? 'Your nickname' : _previewName,
                      style: GoogleFonts.outfit(
                          fontSize: 16, fontWeight: FontWeight.bold, color: p.textPrimary)),
                ),
                const SizedBox(height: 24),
                Text('Choose an avatar',
                    style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w700, color: p.textSecondary)),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: kMemberAvatars.length,
                  itemBuilder: (_, i) {
                    final selected = _avatarId == i;
                    final a = kMemberAvatars[i];
                    return GestureDetector(
                      onTap: () => setState(() => _avatarId = i),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: a.color.withValues(alpha: 0.15),
                          border: Border.all(
                            color: selected ? const Color(0xFFE65C00) : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: Center(child: Icon(a.icon, color: a.color, size: 26)),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text('Nickname',
                    style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w700, color: p.textSecondary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _nickCtrl,
                  maxLength: 20,
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.inter(fontSize: 14, color: p.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'e.g. rahulstudy',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: p.textMuted),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 4),
                Text('Shown on the leaderboard. Numbers and links are not allowed.',
                    style: GoogleFonts.inter(fontSize: 11, color: p.textMuted)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                        : Text('Save', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
    );
  }
}
