import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../core/calendar_picker.dart';
import '../theme/app_colors.dart';
import '../utils/holiday_service.dart';
import '../utils/error_messages.dart';
import '../widgets/states/states.dart';

class ScheduledClosuresScreen extends StatefulWidget {
  final String? libraryId;
  const ScheduledClosuresScreen({super.key, this.libraryId});

  @override
  State<ScheduledClosuresScreen> createState() => _ScheduledClosuresScreenState();
}

class _ScheduledClosuresScreenState extends State<ScheduledClosuresScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;

  bool _isLoading = true;
  Object? _loadError;
  String? _libId;
  List<Holiday> _holidays = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      _libId = widget.libraryId;
      if (_libId == null) {
        final user = _supabase.auth.currentUser;
        if (user != null) {
          final res = await _supabase
              .from('libraries')
              .select('id')
              .eq('owner_id', user.id)
              .maybeSingle();
          _libId = res?['id']?.toString();
        }
      }
      if (_libId == null) {
        throw 'No library found for this account.';
      }
      _holidays = await HolidayService.instance.fetchForLibrary(_libId!);
    } catch (e) {
      _loadError = e;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  List<Holiday> get _upcoming =>
      _holidays.where((h) => !h.endDate.isBefore(_today)).toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));

  List<Holiday> get _past =>
      _holidays.where((h) => h.endDate.isBefore(_today)).toList()
        ..sort((a, b) => b.startDate.compareTo(a.startDate));

  // ── Add holiday sheet ──────────────────────────────────────────────────────
  void _showAddHolidaySheet() {
    final reasonCtrl = TextEditingController();
    bool isRange = false;
    DateTime startDate = _today.add(const Duration(days: 1));
    DateTime endDate = _today.add(const Duration(days: 1));
    bool notify = true;
    bool saving = false;
    String? reasonError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          Future<void> pickStart() async {
            final picked = await showCalendarGridBottomSheet(
              sheetCtx,
              initialDate: startDate,
              firstDate: _today,
              lastDate: _today.add(const Duration(days: 365)),
            );
            if (picked != null) {
              setSheet(() {
                startDate = DateTime(picked.year, picked.month, picked.day);
                if (endDate.isBefore(startDate)) endDate = startDate;
              });
            }
          }

          Future<void> pickEnd() async {
            final picked = await showCalendarGridBottomSheet(
              sheetCtx,
              initialDate: endDate.isBefore(startDate) ? startDate : endDate,
              firstDate: startDate,
              lastDate: startDate.add(const Duration(days: 365)),
            );
            if (picked != null) {
              setSheet(() => endDate = DateTime(picked.year, picked.month, picked.day));
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
              top: 20,
              left: 24,
              right: 24,
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
                Text(
                  'Add Holiday / Closure',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),

                // Single day vs Range toggle
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _segment('Single day', !isRange, () {
                        setSheet(() {
                          isRange = false;
                          endDate = startDate;
                        });
                      }),
                      _segment('Date range', isRange, () {
                        setSheet(() {
                          isRange = true;
                          if (endDate.isBefore(startDate)) {
                            endDate = startDate.add(const Duration(days: 1));
                          }
                        });
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _dateRow(isRange ? 'From' : 'Date', startDate, pickStart),
                if (isRange) ...[
                  const SizedBox(height: 8),
                  _dateRow('To', endDate, pickEnd),
                ],
                const SizedBox(height: 14),

                TextField(
                  controller: reasonCtrl,
                  style: GoogleFonts.inter(fontSize: 14),
                  onChanged: reasonError == null
                      ? null
                      : (_) => setSheet(() => reasonError = null),
                  decoration: InputDecoration(
                    hintText: 'Reason (e.g. Diwali, Maintenance)',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                    errorText: reasonError,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Notify all members',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    'Sends an in-app notification and protects their streak.',
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                  ),
                  value: notify,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setSheet(() => notify = v),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: saving
                      ? null
                      : () async {
                          if (reasonCtrl.text.trim().isEmpty) {
                            setSheet(() => reasonError = 'Please add a reason.');
                            return;
                          }
                          final end = isRange ? endDate : startDate;
                          final ok = await _confirmClose(startDate, end);
                          if (ok != true) return;
                          if (!mounted) return;
                          setSheet(() => saving = true);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            final created = await HolidayService.instance.addHoliday(
                              libraryId: _libId!,
                              start: startDate,
                              end: end,
                              reason: reasonCtrl.text.trim(),
                              notifyMembers: notify,
                            );
                            int ended = 0;
                            if (created.covers(_today)) {
                              ended = await HolidayService.instance
                                  .closeOpenSessionsNow(_libId!);
                            }
                            if (!sheetCtx.mounted) return;
                            Navigator.pop(sheetCtx);
                            final extra = ended > 0
                                ? ' $ended active session${ended == 1 ? '' : 's'} ended.'
                                : '';
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text((notify
                                        ? 'Holiday saved. Members notified.'
                                        : 'Holiday saved.') +
                                    extra),
                                backgroundColor: AppColors.primary,
                              ),
                            );
                            await _load();
                          } catch (e) {
                            setSheet(() => saving = false);
                            messenger.showSnackBar(
                              SnackBar(content: Text(friendlyError(e))),
                            );
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text('Save Holiday',
                          style: GoogleFonts.inter(
                              color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _segment(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? AppColors.primary : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateRow(String label, DateTime date, VoidCallback onTap) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.calendar_month, size: 16, color: AppColors.primary),
          label: Text(
            DateFormat('EEE, dd MMM yyyy').format(date),
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmRemove(Holiday h) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove holiday?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          'Remove "${h.reason}" (${_rangeLabel(h)})? Members will not be re-notified.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final removed = h;
    setState(() => _holidays.removeWhere((x) => x.id == h.id));
    try {
      await HolidayService.instance.removeHoliday(h.id, holiday: h);
      messenger.showSnackBar(SnackBar(
        content: Text(h.notifyMembers && !h.endDate.isBefore(_today)
            ? 'Holiday removed. Members notified the library is open.'
            : 'Holiday removed.'),
      ));
    } catch (e) {
      setState(() => _holidays.add(removed));
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  String _rangeLabel(Holiday h) {
    if (!h.isRange) return DateFormat('dd MMM yyyy').format(h.startDate);
    return '${DateFormat('dd MMM').format(h.startDate)} – ${DateFormat('dd MMM yyyy').format(h.endDate)}';
  }

  /// Confirmation before saving a closure: shows active-member count and — when
  /// the closure covers today — how many are checked in now (auto-checked-out).
  Future<bool?> _confirmClose(DateTime start, DateTime end) async {
    if (_libId == null) return false;
    final coversToday = !_today.isBefore(start) && !_today.isAfter(end);
    final activeMembers = await HolidayService.instance.activeMembersCount(_libId!);
    final openNow = coversToday ? await HolidayService.instance.openSessionsNow(_libId!) : 0;
    if (!mounted) return false;

    final bool single = start.year == end.year && start.month == end.month && start.day == end.day;
    final dateLabel = single
        ? DateFormat('EEE, dd MMM yyyy').format(start)
        : '${DateFormat('dd MMM').format(start)} – ${DateFormat('dd MMM yyyy').format(end)}';

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.primary, size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Close the library?',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Closing for: $dateLabel',
                style: GoogleFonts.inter(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            Text('$activeMembers active member${activeMembers == 1 ? '' : 's'} in this library.',
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
            if (coversToday && openNow > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(
                  '$openNow member${openNow == 1 ? ' is' : 's are'} checked in right now. '
                  'Closing today will end ${openNow == 1 ? 'their session' : 'their sessions'} immediately.',
                  style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF991B1B), height: 1.35),
                ),
              ),
            ] else if (coversToday) ...[
              const SizedBox(height: 8),
              Text('No one is checked in right now.',
                  style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textMuted)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: AppColors.textMuted, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(coversToday && openNow > 0 ? 'Close & end sessions' : 'Close library',
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
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
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Holidays & Closures',
              style: GoogleFonts.outfit(
                  fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3.0,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(text: 'Upcoming'),
                Tab(text: 'Past'),
              ],
            ),
          ),
          body: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const LoadingState(message: 'Loading holidays…');
    }
    if (_loadError != null) {
      return ErrorState(message: friendlyError(_loadError), onRetry: _load);
    }
    return Column(
      children: [
        // Add-holiday composer merged onto the main screen (was a FAB).
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showAddHolidaySheet,
              icon: const Icon(Icons.add, color: Colors.white, size: 18),
              label: Text('Add holiday / closure',
                  style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildList(_upcoming, true),
              _buildList(_past, false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildList(List<Holiday> list, bool isUpcoming) {
    if (list.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.18),
            EmptyState(
              icon: Icons.event_available_outlined,
              title: isUpcoming ? 'No upcoming holidays' : 'No past holidays',
              message: isUpcoming
                  ? 'Tap “Add holiday” to close the library for a day, a range, or a future date.'
                  : 'Past closures will appear here.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
        physics: const AlwaysScrollableScrollPhysics(),
        children: list.map((h) => _holidayCard(h, isUpcoming)).toList(),
      ),
    );
  }

  Widget _holidayCard(Holiday h, bool isUpcoming) {
    final coversToday = h.covers(_today);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: coversToday ? AppColors.primary : AppColors.border,
          width: coversToday ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isUpcoming ? AppColors.orangeTintBg : AppColors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.event_busy,
              color: isUpcoming ? AppColors.primary : AppColors.textMuted,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _rangeLabel(h),
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (coversToday)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.orangeTintBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('TODAY',
                            style: GoogleFonts.inter(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary)),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  h.reason,
                  style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (h.isRange)
                      _chip('${h.dayCount} days', AppColors.infoBg, AppColors.info),
                    if (h.isRange) const SizedBox(width: 6),
                    _chip(
                      h.notifyMembers ? 'Members notified' : 'Not notified',
                      h.notifyMembers ? AppColors.successBg : AppColors.dangerBg,
                      h.notifyMembers ? const Color(0xFF15803D) : AppColors.danger,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isUpcoming)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
              onPressed: () => _confirmRemove(h),
            ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        text,
        style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}
