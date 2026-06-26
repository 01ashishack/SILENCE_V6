import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../utils/time_utils.dart';
import '../utils/error_messages.dart';
import '../widgets/states/states.dart';

/// Member-facing "Contact Admin" hub. Two sub-tabs:
///  • My Queries — everything the member sent, with status + a compose button.
///  • Replies     — the admin's answers to those queries.
/// Submission is a plain query form (NOT a chat thread). Writes to `queries`.
class ContactAdminScreen extends StatefulWidget {
  /// Pre-selected library for a new query (the member's primary library).
  final String? defaultLibraryId;
  const ContactAdminScreen({super.key, this.defaultLibraryId});

  @override
  State<ContactAdminScreen> createState() => _ContactAdminScreenState();
}

class _ContactAdminScreenState extends State<ContactAdminScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  Object? _error;
  List<Map<String, dynamic>> _queries = [];
  // Member's libraries available to contact: [{id, name}].
  List<Map<String, String>> _libraries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw 'You are not signed in.';

      final results = await Future.wait([
        _supabase
            .from('queries')
            .select(
                'id, message, status, admin_reply, created_at, replied_at, library_id, libraries(name)')
            .eq('member_id', user.id)
            .order('created_at', ascending: false),
        _supabase
            .from('memberships')
            .select('library_id, libraries(name)')
            .eq('member_id', user.id),
      ]);

      _queries = List<Map<String, dynamic>>.from(results[0] as List);

      // Distinct libraries the member belongs to (compose targets).
      final seen = <String>{};
      final libs = <Map<String, String>>[];
      for (final m in List<Map<String, dynamic>>.from(results[1] as List)) {
        final id = m['library_id']?.toString();
        final name = (m['libraries']?['name'] ?? 'Library').toString();
        if (id != null && id.isNotEmpty && seen.add(id)) {
          libs.add({'id': id, 'name': name});
        }
      }
      _libraries = libs;
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _canCompose => _libraries.isNotEmpty;

  // ── New query (submit form, not a chat) ────────────────────────────────────
  void _openCompose() {
    if (!_canCompose) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join a library first to contact its admin.')),
      );
      return;
    }
    final messageCtrl = TextEditingController();
    String libraryId = widget.defaultLibraryId != null &&
            _libraries.any((l) => l['id'] == widget.defaultLibraryId)
        ? widget.defaultLibraryId!
        : _libraries.first['id']!;
    bool sending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('New query',
                  style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Send a question or request to your library admin.',
                  style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textMuted)),
              const SizedBox(height: 16),

              // Library selector (only when the member has >1 library).
              if (_libraries.length > 1) ...[
                Text('Library',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: libraryId,
                      items: _libraries
                          .map((l) => DropdownMenuItem(
                                value: l['id'],
                                child: Text(l['name']!,
                                    style: GoogleFonts.inter(fontSize: 14)),
                              ))
                          .toList(),
                      onChanged: (v) => setSheet(() => libraryId = v ?? libraryId),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              Text('Your message',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: messageCtrl,
                maxLines: 6,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Type your question or request here…',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: sending
                    ? null
                    : () async {
                        final msg = messageCtrl.text.trim();
                        if (msg.isEmpty) {
                          ScaffoldMessenger.of(sheetCtx).showSnackBar(
                            const SnackBar(content: Text('Please type your message.')),
                          );
                          return;
                        }
                        setSheet(() => sending = true);
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          final user = _supabase.auth.currentUser;
                          await _supabase.from('queries').insert({
                            'member_id': user!.id,
                            'library_id': libraryId,
                            'message': msg,
                            'status': 'open',
                          });
                          // Notify the library owner so the query shows in their
                          // bell + Queries badge (best-effort; cross-actor insert
                          // is allowed by the notifications insert policy).
                          try {
                            final lib = await _supabase
                                .from('libraries')
                                .select('owner_id')
                                .eq('id', libraryId)
                                .maybeSingle();
                            final ownerId = lib?['owner_id'] as String?;
                            if (ownerId != null) {
                              await _supabase.from('notifications').insert({
                                'user_id': ownerId,
                                'title': 'New member query',
                                'body': msg,
                                'data': {'type': 'new_query', 'library_id': libraryId},
                              });
                            }
                          } catch (e) {
                            debugPrint('notify admin of query failed: $e');
                          }
                          if (!sheetCtx.mounted) return;
                          Navigator.pop(sheetCtx);
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Query sent to admin.'),
                              backgroundColor: AppColors.primary,
                            ),
                          );
                          await _load();
                        } catch (e) {
                          setSheet(() => sending = false);
                          messenger.showSnackBar(
                            SnackBar(content: Text(friendlyError(e))),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: sending
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text('Submit query',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: AppColors.scaffold,
          appBar: AppBar(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text('Contact Admin',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
          floatingActionButton: (_isLoading || _error != null)
              ? null
              : FloatingActionButton.extended(
                  backgroundColor: AppColors.primary,
                  onPressed: _openCompose,
                  icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  label: Text('New query',
                      style: GoogleFonts.inter(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
          body: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const LoadingState(message: 'Loading…');
    if (_error != null) {
      return ErrorState(message: friendlyError(_error), onRetry: _load);
    }
    return _buildMyQueriesTab();
  }

  Widget _buildMyQueriesTab() {
    if (_queries.isEmpty) {
      return _emptyRefresh(
        icon: Icons.forum_outlined,
        title: 'No queries yet',
        message: _canCompose
            ? 'Tap “New query” to send a question or request to your library admin.'
            : 'Join a library to contact its admin.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _queries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _queryCard(_queries[i]),
      ),
    );
  }

  Widget _emptyRefresh(
      {required IconData icon, required String title, required String message}) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.16),
          EmptyState(icon: icon, title: title, message: message),
        ],
      ),
    );
  }

  Widget _queryCard(Map<String, dynamic> q) {
    final status = (q['status'] ?? 'open').toString();
    final reply = (q['admin_reply'] ?? '').toString();
    final libName = (q['libraries']?['name'] ?? 'Library').toString();
    final created = _parse(q['created_at']);
    final replied = _parse(q['replied_at']);

    final (badgeBg, badgeFg, badgeText) = switch (status) {
      'replied' => (AppColors.successBg, const Color(0xFF15803D), 'REPLIED'),
      'closed' => (AppColors.surfaceMuted, AppColors.textMuted, 'CLOSED'),
      _ => (AppColors.warningBg, const Color(0xFFB45309), 'OPEN'),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(libName,
                    style: GoogleFonts.outfit(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: badgeBg, borderRadius: BorderRadius.circular(8)),
                child: Text(badgeText,
                    style: GoogleFonts.inter(
                        fontSize: 9, fontWeight: FontWeight.bold, color: badgeFg)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(q['message']?.toString() ?? '',
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppColors.textSecondary, height: 1.35)),
          if (created != null) ...[
            const SizedBox(height: 4),
            Text('Sent ${_stamp(created)}',
                style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textMuted)),
          ],
          if (reply.isNotEmpty) ...[
            if (reply.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.orangeTintBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.orangeTintBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.support_agent,
                            size: 15, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text('Admin reply',
                            style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary)),
                        const Spacer(),
                        if (replied != null)
                          Text(_stamp(replied),
                              style: GoogleFonts.inter(
                                  fontSize: 10, color: AppColors.textMuted)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(reply,
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                            height: 1.35)),
                  ],
                ),
              ),
            ],
          ] else if (status != 'closed') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.hourglass_empty, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text('Waiting for the admin to reply',
                    style: GoogleFonts.inter(
                        fontSize: 11.5, color: AppColors.textMuted)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  DateTime? _parse(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  String _stamp(DateTime utc) =>
      '${DateFormat('d MMM').format(toIST(utc))}, ${formatTimeIST(utc)}';
}
