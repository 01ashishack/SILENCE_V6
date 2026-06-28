import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_snackbar.dart';
import '../services/moderation_service.dart';
import '../theme/app_palette.dart';
import '../utils/error_messages.dart';
import '../widgets/states/empty_state.dart';

/// Lets a user view and undo the users they have blocked (Play UGC "block
/// users" requirement). Honest: the list reflects only confirmed DB state.
class MemberBlockedUsersScreen extends StatefulWidget {
  const MemberBlockedUsersScreen({super.key});

  @override
  State<MemberBlockedUsersScreen> createState() => _MemberBlockedUsersScreenState();
}

class _MemberBlockedUsersScreenState extends State<MemberBlockedUsersScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _blocks = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final blocks = await ModerationService.myBlocks();
      if (!mounted) return;
      setState(() {
        _blocks = blocks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _unblock(String blockedId, String name) async {
    try {
      await ModerationService.unblockUser(blockedId);
      if (!mounted) return;
      AppSnackbar.success(context, 'Unblocked $name.');
      _load();
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
    }
  }

  String _name(Map<String, dynamic> b) {
    final u = b['blocked'];
    if (u is Map) {
      final n = (u['nickname'] ?? u['full_name'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
    }
    return 'User';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.scaffold,
      appBar: AppBar(
        backgroundColor: const Color(0xFFE65C00),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Blocked users', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
          : _blocks.isEmpty
              ? const EmptyState(
                  icon: Icons.block,
                  title: 'No blocked users',
                  message: 'People you block won\'t appear in your reviews and feeds. '
                      'You can block someone from their review.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _blocks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final b = _blocks[i];
                      final name = _name(b);
                      final photo = (b['blocked'] is Map) ? (b['blocked']['photo_url'] ?? '') : '';
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: p.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.border),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0x1FE65C00),
                              backgroundImage:
                                  (photo is String && photo.isNotEmpty) ? NetworkImage(photo) : null,
                              child: (photo is String && photo.isNotEmpty)
                                  ? null
                                  : Text(name[0].toUpperCase(),
                                      style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(name,
                                  style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: p.textPrimary)),
                            ),
                            TextButton(
                              onPressed: () => _unblock((b['blocked_id'] ?? '').toString(), name),
                              child: Text('Unblock',
                                  style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
