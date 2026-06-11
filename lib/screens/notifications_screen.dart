import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';
import '../widgets/states/states.dart';

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
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(rows);
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
      backgroundColor: AppColors.scaffold,
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
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.divider),
        itemBuilder: (context, index) => _NotificationTile(
          item: _items[index],
          onTap: () => _markRead(_items[index]),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  const _NotificationTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = item['read_at'] == null;
    final title = (item['title'] as String?)?.trim();
    final body = (item['body'] as String?)?.trim();
    final type = _typeOf(item);
    final style = _NotifStyle.forType(type);
    final time = _timeAgo(item['sent_at']);

    return Material(
      color: unread ? AppColors.orangeTintBg.withValues(alpha: 0.45) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                          color: AppColors.textPrimary,
                        ),
                      ),
                    if (body != null && body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        body,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    if (time != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        time,
                        style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted),
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
        return const _NotifStyle(Icons.check_circle_rounded, AppColors.success);
      case 'rejection':
      case 'rejected':
      case 'join_rejected':
      case 'payment_rejected':
        return const _NotifStyle(Icons.cancel_rounded, AppColors.danger);
      case 'announcement':
        return const _NotifStyle(Icons.campaign_rounded, AppColors.primary);
      case 'hold':
      case 'hold_approved':
      case 'hold_lifted':
        return const _NotifStyle(Icons.pause_circle_rounded, AppColors.warning);
      case 'seat_change':
      case 'seat_reassigned':
        return const _NotifStyle(Icons.event_seat_rounded, AppColors.info);
      case 'badge':
        return const _NotifStyle(Icons.emoji_events_rounded, AppColors.primary);
      case 'holiday':
      case 'closure':
        return const _NotifStyle(Icons.beach_access_rounded, AppColors.warning);
      case 'query_reply':
        return const _NotifStyle(Icons.forum_rounded, AppColors.info);
      case 'expiry':
      case 'renewal':
        return const _NotifStyle(Icons.schedule_rounded, AppColors.warning);
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
