import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';
import '../widgets/states/states.dart';
import '../core/active_library_store.dart';
import 'contact_admin_screen.dart';

/// Member-facing notification center. Reads the real `notifications` table for
/// the signed-in user (canonical columns: `user_id, title, body, data, sent_at,
/// read_at`; unread = `read_at IS NULL`), with honest loading / empty / error
/// states, tap-to-mark-read, mark-all-read and pull-to-refresh.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _items = [];
  bool _markingAll = false;
  // id -> name for libraries this user OWNS (admins). Drives the per-tile
  // library chip and gates the "switch active library on tap" behaviour.
  Map<String, String> _libNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'Please sign in to see your notifications.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', user.id)
          .order('sent_at', ascending: false)
          .limit(100);
      // Best-effort: load the libraries this user owns so multi-library admins
      // get a "which library" chip + tap can switch to the right library.
      Map<String, String> libNames = {};
      try {
        final libs = await _supabase
            .from('libraries')
            .select('id, name')
            .eq('owner_id', user.id);
        for (final l in List<Map<String, dynamic>>.from(libs)) {
          final id = l['id']?.toString();
          if (id != null) libNames[id] = (l['name'] ?? 'Library').toString();
        }
      } catch (_) {/* chip is a nicety; ignore failures */}
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(rows);
        _libNames = libNames;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  int get _unreadCount => _items.where((n) => n['read_at'] == null).length;

  /// Mark read + route to the screen related to this notification's `data.type`.
  /// Honors an explicit `data.route` (named route) when present; otherwise maps
  /// the type to a sensible destination. Best-effort + guarded so a tap never
  /// crashes the screen.
  void _onTapNotification(Map<String, dynamic> item) {
    _markRead(item);
    final data = item['data'];
    final type =
        (data is Map && data['type'] is String) ? data['type'] as String : '';
    final route =
        (data is Map && data['route'] is String) ? data['route'] as String : null;
    final libId = (data is Map && data['library_id'] is String)
        ? data['library_id'] as String
        : null;
    try {
      if (route != null && route.isNotEmpty) {
        Navigator.of(context).pushNamed(route);
        return;
      }
      switch (type) {
        case 'query_reply':
        case 'new_query':
        case 'refund_request':
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ContactAdminScreen()),
          );
          break;
        // ── member destinations → member home ──
        case 'approval':
        case 'approved':
        case 'join_approved':
        case 'payment_confirmed':
        case 'payment_received':
        case 'rejection':
        case 'rejected':
        case 'join_rejected':
        case 'payment_rejected':
        case 'hold':
        case 'hold_approved':
        case 'hold_lifted':
        case 'seat_change':
        case 'seat_reassigned':
        case 'seat_assigned':
        case 'seat_change_approved':
        case 'seat_change_rejected':
        case 'shift_change':
        case 'membership_renewed':
        case 'membership_transferred':
        case 'membership_removed':
        case 'membership_removed_refund':
        case 'membership_exited':
        case 'expiry':
        case 'renewal':
        case 'badge':
        case 'leaderboard':
        case 'referral_credited':
        case 'streak_reminder':
        case 'shift_end':
        case 'auto_checkout':
        case 'checkin_approved':
        case 'checkin_rejected':
        case 'attendance_manual':
        case 'holiday':
        case 'reopen':
        case 'closure':
          Navigator.of(context).pushNamed('/member/home');
          break;
        // ── admin destinations → admin home ──
        case 'query':
        case 'join_request':
        case 'new_join_request':
        case 'seat_change_request':
        case 'shift_change_request':
        case 'hold_request':
        case 'payment':
        case 'payment_submitted':
        case 'checkin_approval_request':
        case 'member_exited':
        case 'check_in':
        case 'check_out':
        case 'new_review':
        case 'expiring_digest':
        case 'daily_summary':
        case 'dues_digest':
          // Multi-library: jump the admin shell to the library this
          // notification belongs to before opening the dashboard.
          if (libId != null && _libNames.containsKey(libId)) {
            ActiveLibraryStore.requestSwitch(libId);
          }
          Navigator.of(context).pushNamed('/admin/home');
          break;
        case 'announcement':
          _showAnnouncementDialog(item);
          break;
        default:
          break; // unknown: already marked read, no navigation
      }
    } catch (e) {
      debugPrint('Notification tap navigation failed: $e');
    }
  }

  void _showAnnouncementDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.palette.surface,
        surfaceTintColor: Colors.transparent,
        title: Text((item['title'] as String?)?.trim().isNotEmpty == true
            ? item['title'] as String
            : 'Announcement'),
        content: Text((item['body'] as String?) ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _markRead(Map<String, dynamic> item) async {
    if (item['read_at'] != null) return;
    final id = item['id'];
    // Optimistic update.
    setState(() => item['read_at'] = DateTime.now().toIso8601String());
    try {
      await _supabase
          .from('notifications')
          .update({'read_at': DateTime.now().toIso8601String()}).eq('id', id);
    } catch (_) {
      if (mounted) setState(() => item['read_at'] = null); // revert on failure
    }
  }

  Future<void> _markAllRead() async {
    final user = _supabase.auth.currentUser;
    if (user == null || _unreadCount == 0 || _markingAll) return;
    setState(() => _markingAll = true);
    final now = DateTime.now().toIso8601String();
    final previous = _items.map((e) => e['read_at']).toList();
    setState(() {
      for (final n in _items) {
        n['read_at'] ??= now;
      }
    });
    try {
      await _supabase
          .from('notifications')
          .update({'read_at': now})
          .eq('user_id', user.id)
          .isFilter('read_at', null);
    } catch (e) {
      if (mounted) {
        setState(() {
          for (var i = 0; i < _items.length; i++) {
            _items[i]['read_at'] = previous[i];
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not mark all as read. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Notifications', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markingAll ? null : _markAllRead,
              child: Text(
                'Mark all read',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingState();
    if (_error != null) return ErrorState(error: _error, onRetry: _load);
    if (_items.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'No notifications yet',
              message: "Approvals, announcements and reminders will show up here.",
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final data = _items[index]['data'];
          final libId = (data is Map && data['library_id'] is String)
              ? data['library_id'] as String
              : null;
          // Only show the chip for multi-library owners (a single-library admin
          // or a member doesn't need to disambiguate).
          final libraryName =
              (libId != null && _libNames.length > 1) ? _libNames[libId] : null;
          return _NotificationTile(
            item: _items[index],
            libraryName: libraryName,
            onTap: () => _onTapNotification(_items[index]),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final String? libraryName;
  final VoidCallback onTap;

  const _NotificationTile({required this.item, this.libraryName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = item['read_at'] == null;
    final title = (item['title'] as String?)?.trim();
    final body = (item['body'] as String?)?.trim();
    final type = _typeOf(item);
    final style = _NotifStyle.forType(type);
    final time = _timeAgo(item['sent_at']);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: unread
                ? AppColors.primary.withValues(alpha: 0.25)
                : const Color(0xFFEDEDED),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(style.icon, size: 20, color: style.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null && title.isNotEmpty)
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 14.5,
                          fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                          color: context.palette.textPrimary,
                        ),
                      ),
                    if (body != null && body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        body,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.4,
                          color: context.palette.textSecondary,
                        ),
                      ),
                    ],
                    if (time != null || libraryName != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (libraryName != null) ...[
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  libraryName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (time != null)
                            Text(
                              time,
                              style: GoogleFonts.inter(fontSize: 11.5, color: context.palette.textMuted),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (unread)
                Container(
                  margin: const EdgeInsets.only(left: 8, top: 4),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                ),
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _typeOf(Map<String, dynamic> item) {
    final data = item['data'];
    if (data is Map && data['type'] is String) return data['type'] as String;
    return '';
  }
}

/// Icon + color for a notification, keyed off `data.type`.
class _NotifStyle {
  final IconData icon;
  final Color color;
  const _NotifStyle(this.icon, this.color);

  static _NotifStyle forType(String type) {
    switch (type) {
      case 'approval':
      case 'approved':
      case 'join_approved':
      case 'payment_confirmed':
      case 'checkin_approved':
      case 'seat_change_approved':
      case 'membership_renewed':
        return const _NotifStyle(Icons.check_circle_rounded, AppColors.success);
      case 'rejection':
      case 'rejected':
      case 'join_rejected':
      case 'payment_rejected':
      case 'seat_change_rejected':
        return const _NotifStyle(Icons.cancel_rounded, AppColors.danger);
      case 'announcement':
        return const _NotifStyle(Icons.campaign_rounded, AppColors.primary);
      case 'hold':
      case 'hold_approved':
      case 'hold_lifted':
      case 'hold_request':
        return const _NotifStyle(Icons.pause_circle_rounded, AppColors.warning);
      case 'seat_change':
      case 'seat_reassigned':
      case 'seat_assigned':
      case 'seat_change_request':
      case 'shift_change':
      case 'shift_change_request':
        return const _NotifStyle(Icons.event_seat_rounded, AppColors.info);
      case 'badge':
        return const _NotifStyle(Icons.emoji_events_rounded, AppColors.primary);
      case 'leaderboard':
        return const _NotifStyle(Icons.leaderboard_rounded, AppColors.primary);
      case 'referral_credited':
        return const _NotifStyle(Icons.card_giftcard_rounded, AppColors.success);
      case 'streak_reminder':
        return const _NotifStyle(Icons.local_fire_department_rounded, AppColors.warning);
      case 'holiday':
      case 'closure':
      case 'reopen':
        return const _NotifStyle(Icons.beach_access_rounded, AppColors.warning);
      case 'query_reply':
      case 'new_query':
        return const _NotifStyle(Icons.forum_rounded, AppColors.info);
      case 'refund_request':
        return const _NotifStyle(Icons.currency_rupee_rounded, AppColors.warning);
      case 'new_review':
        return const _NotifStyle(Icons.star_rounded, AppColors.warning);
      case 'new_join_request':
      case 'join_request':
        return const _NotifStyle(Icons.person_add_rounded, AppColors.info);
      case 'payment_submitted':
      case 'payment':
        return const _NotifStyle(Icons.payments_rounded, AppColors.success);
      case 'daily_summary':
      case 'dues_digest':
        return const _NotifStyle(Icons.insights_rounded, AppColors.primary);
      case 'expiring_digest':
        return const _NotifStyle(Icons.event_busy_rounded, AppColors.warning);
      case 'member_exited':
      case 'membership_exited':
      case 'membership_removed':
      case 'membership_removed_refund':
      case 'membership_transferred':
        return const _NotifStyle(Icons.exit_to_app_rounded, AppColors.danger);
      case 'expiry':
      case 'renewal':
      case 'shift_end':
        return const _NotifStyle(Icons.schedule_rounded, AppColors.warning);
      case 'payment_received':
        return const _NotifStyle(Icons.hourglass_top_rounded, AppColors.info);
      case 'auto_checkout':
        return const _NotifStyle(Icons.logout_rounded, AppColors.danger);
      case 'check_in':
      case 'attendance_manual':
        return const _NotifStyle(Icons.login_rounded, AppColors.success);
      case 'check_out':
        return const _NotifStyle(Icons.logout_rounded, AppColors.info);
      case 'checkin_rejected':
        return const _NotifStyle(Icons.block_rounded, AppColors.danger);
      case 'checkin_approval_request':
        return const _NotifStyle(Icons.login_rounded, AppColors.info);
      default:
        return const _NotifStyle(Icons.notifications_rounded, AppColors.primary);
    }
  }
}

String? _timeAgo(dynamic raw) {
  if (raw == null) return null;
  DateTime? t;
  if (raw is String) t = DateTime.tryParse(raw);
  if (t == null) return null;
  final now = DateTime.now();
  final diff = now.difference(t.toLocal());
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final d = t.toLocal();
  return '${d.day}/${d.month}/${d.year}';
}
