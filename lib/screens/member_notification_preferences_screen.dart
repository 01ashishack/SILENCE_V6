import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MemberNotificationPreferencesScreen extends StatefulWidget {
  const MemberNotificationPreferencesScreen({super.key});

  @override
  State<MemberNotificationPreferencesScreen> createState() => _MemberNotificationPreferencesScreenState();
}

class _MemberNotificationPreferencesScreenState extends State<MemberNotificationPreferencesScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _userId;

  // Preferences state variables
  bool _masterPush = true;
  bool _joinRequests = true;
  bool _payments = true;
  bool _expiry = true;
  bool _hold = true;
  bool _seatChange = true;
  bool _announcements = true;
  bool _trialReminders = true;
  bool _badges = true;
  bool _referralUpdates = true;

  bool _streakRemindersEnabled = true;
  TimeOfDay _streakTime = const TimeOfDay(hour: 19, minute: 0); // Default 7:00 PM

  bool _quietHoursEnabled = false;
  TimeOfDay _quietHoursStart = const TimeOfDay(hour: 22, minute: 0); // Default 10:00 PM
  TimeOfDay _quietHoursEnd = const TimeOfDay(hour: 8, minute: 0); // Default 8:00 AM

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user != null) {
        _userId = user.id;
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        final suffix = _userId!;

        setState(() {
          _masterPush = prefs.getBool('pref_master_push_$suffix') ?? true;
          _joinRequests = prefs.getBool('pref_join_requests_$suffix') ?? true;
          _payments = prefs.getBool('pref_payments_$suffix') ?? true;
          _expiry = prefs.getBool('pref_expiry_$suffix') ?? true;
          _hold = prefs.getBool('pref_hold_$suffix') ?? true;
          _seatChange = prefs.getBool('pref_seat_change_$suffix') ?? true;
          _announcements = prefs.getBool('pref_announcements_$suffix') ?? true;
          _trialReminders = prefs.getBool('pref_trial_reminders_$suffix') ?? true;
          _badges = prefs.getBool('pref_badges_$suffix') ?? true;
          _referralUpdates = prefs.getBool('pref_referral_updates_$suffix') ?? true;

          _streakRemindersEnabled = prefs.getBool('pref_streak_reminders_enabled_$suffix') ?? true;
          final streakTimeStr = prefs.getString('pref_streak_time_$suffix') ?? '19:00';
          _streakTime = _parseTime(streakTimeStr);

          _quietHoursEnabled = prefs.getBool('pref_quiet_hours_enabled_$suffix') ?? false;
          final quietStartStr = prefs.getString('pref_quiet_start_$suffix') ?? '22:00';
          final quietEndStr = prefs.getString('pref_quiet_end_$suffix') ?? '08:00';
          _quietHoursStart = _parseTime(quietStartStr);
          _quietHoursEnd = _parseTime(quietEndStr);
        });
      }
    } catch (e) {
      debugPrint('Error loading preferences: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  TimeOfDay _parseTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
    } catch (e) {
      debugPrint('Error parsing time $timeStr: $e');
    }
    return const TimeOfDay(hour: 19, minute: 0);
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatTimeForDisplay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  Future<void> _savePreferences() async {
    if (_userId == null) return;
    setState(() => _isSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final suffix = _userId!;

      await prefs.setBool('pref_master_push_$suffix', _masterPush);
      await prefs.setBool('pref_join_requests_$suffix', _joinRequests);
      await prefs.setBool('pref_payments_$suffix', _payments);
      await prefs.setBool('pref_expiry_$suffix', _expiry);
      await prefs.setBool('pref_hold_$suffix', _hold);
      await prefs.setBool('pref_seat_change_$suffix', _seatChange);
      await prefs.setBool('pref_announcements_$suffix', _announcements);
      await prefs.setBool('pref_trial_reminders_$suffix', _trialReminders);
      await prefs.setBool('pref_badges_$suffix', _badges);
      await prefs.setBool('pref_referral_updates_$suffix', _referralUpdates);

      await prefs.setBool('pref_streak_reminders_enabled_$suffix', _streakRemindersEnabled);
      await prefs.setString('pref_streak_time_$suffix', _formatTime(_streakTime));

      await prefs.setBool('pref_quiet_hours_enabled_$suffix', _quietHoursEnabled);
      await prefs.setString('pref_quiet_start_$suffix', _formatTime(_quietHoursStart));
      await prefs.setString('pref_quiet_end_$suffix', _formatTime(_quietHoursEnd));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Preferences saved successfully! ✓',
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save preferences: $e',
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _selectStreakTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _streakTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFE65C00),
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (!mounted) return;
    if (picked != null && picked != _streakTime) {
      setState(() => _streakTime = picked);
    }
  }

  Future<void> _selectQuietTime(bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _quietHoursStart : _quietHoursEnd,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFE65C00),
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        if (isStart) {
          _quietHoursStart = picked;
        } else {
          _quietHoursEnd = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE65C00),
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: const Color(0xFFFBF5EE),
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Notification Preferences',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Master push card
                      _buildMasterPushCard(),
                      const SizedBox(height: 16),

                      // Group 1: Subscriptions & Updates
                      if (_masterPush) ...[
                        _buildSectionHeader('Membership & Account Alerts'),
                        _buildPreferenceCard([
                          _buildSwitchRow(
                            'Join Requests',
                            'Receive status updates on your library seat join requests.',
                            _joinRequests,
                            (v) => setState(() => _joinRequests = v),
                            Icons.assignment_outlined,
                            const Color(0xFFEFF6FF),
                            const Color(0xFF3B82F6),
                          ),
                          _buildDivider(),
                          _buildSwitchRow(
                            'Payments & Receipts',
                            'Get notified for success fees, invoices, and renewal plans.',
                            _payments,
                            (v) => setState(() => _payments = v),
                            Icons.receipt_long_outlined,
                            const Color(0xFFECFDF5),
                            const Color(0xFF10B981),
                          ),
                          _buildDivider(),
                          _buildSwitchRow(
                            'Membership Expiry',
                            'Get warnings prior to your active library card expiration.',
                            _expiry,
                            (v) => setState(() => _expiry = v),
                            Icons.hourglass_empty,
                            const Color(0xFFFEF3C7),
                            const Color(0xFFD97706),
                          ),
                          _buildDivider(),
                          _buildSwitchRow(
                            'Hold & Pause Requests',
                            'Notification when your library hold request status updates.',
                            _hold,
                            (v) => setState(() => _hold = v),
                            Icons.pause_circle_outline,
                            const Color(0xFFF3F4F6),
                            const Color(0xFF4B5563),
                          ),
                          _buildDivider(),
                          _buildSwitchRow(
                            'Seat Change Notifications',
                            'Get alerts if your room or assigned desk gets updated.',
                            _seatChange,
                            (v) => setState(() => _seatChange = v),
                            Icons.event_seat_outlined,
                            const Color(0xFFF5F3FF),
                            const Color(0xFF8B5CF6),
                          ),
                        ]),
                        const SizedBox(height: 20),

                        _buildSectionHeader('Community & Activities'),
                        _buildPreferenceCard([
                          _buildSwitchRow(
                            'Announcements',
                            'General library announcements, holiday notices, and rules updates.',
                            _announcements,
                            (v) => setState(() => _announcements = v),
                            Icons.campaign_outlined,
                            const Color(0xFFFDF2F8),
                            const Color(0xFFEC4899),
                          ),
                          _buildDivider(),
                          _buildSwitchRow(
                            'Trial Reminders',
                            'Receive alerts when a trial reservation is coming up.',
                            _trialReminders,
                            (v) => setState(() => _trialReminders = v),
                            Icons.alarm_on,
                            const Color(0xFFFFF7F5),
                            const Color(0xFFE65C00),
                          ),
                          _buildDivider(),
                          _buildSwitchRow(
                            'Badges & Milestones',
                            'Celebration alerts when you unlock study streak milestones.',
                            _badges,
                            (v) => setState(() => _badges = v),
                            Icons.emoji_events_outlined,
                            const Color(0xFFFFFBEB),
                            const Color(0xFFF59E0B),
                          ),
                          _buildDivider(),
                          _buildSwitchRow(
                            'Referral Updates',
                            'Notification when your referred friends purchase passes.',
                            _referralUpdates,
                            (v) => setState(() => _referralUpdates = v),
                            Icons.card_giftcard,
                            const Color(0xFFE0F2FE),
                            const Color(0xFF0284C7),
                          ),
                        ]),
                        const SizedBox(height: 20),

                        _buildSectionHeader('Smart Reminders'),
                        _buildRemindersCard(),
                        const SizedBox(height: 32),
                      ],

                      // Save Button
                      ElevatedButton(
                        onPressed: _isSaving ? null : _savePreferences,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 2,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                              )
                            : Text('Save Preferences',
                                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280), letterSpacing: 1),
      ),
    );
  }

  Widget _buildMasterPushCard() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: SwitchListTile(
        activeThumbColor: const Color(0xFFE65C00),
        value: _masterPush,
        onChanged: (v) => setState(() => _masterPush = v),
        title: Text('Master Push Notifications',
            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
        subtitle: Text('Enable or disable all notifications in the app.',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Color(0xFFFFF3ED),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.notifications_active, color: Color(0xFFE65C00), size: 24),
        ),
      ),
    );
  }

  Widget _buildPreferenceCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSwitchRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
    IconData icon,
    Color bgIconColor,
    Color iconColor,
  ) {
    return SwitchListTile(
      activeThumbColor: const Color(0xFFE65C00),
      value: value,
      onChanged: onChanged,
      title: Text(title, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
      subtitle: Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bgIconColor,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      thickness: 1,
      color: Color(0xFFF3F4F6),
      indent: 64,
    );
  }

  Widget _buildRemindersCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Streak reminder row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF3ED),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.workspace_premium_outlined, color: Color(0xFFE65C00), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Streak Reminders',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                    Text('Remind me to maintain my daily study streak.',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
              ),
              Switch(
                activeThumbColor: const Color(0xFFE65C00),
                value: _streakRemindersEnabled,
                onChanged: (v) => setState(() => _streakRemindersEnabled = v),
              ),
            ],
          ),
          if (_streakRemindersEnabled) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: _selectStreakTime,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBF5EE),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFF3ED)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Reminder Time',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF4B5563))),
                    Row(
                      children: [
                        Text(_formatTimeForDisplay(_streakTime),
                            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down, color: Color(0xFFE65C00)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12.0),
            child: Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6)),
          ),

          // Quiet Hours section
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F4F6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.do_not_disturb_on_outlined, color: Color(0xFF4B5563), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quiet Hours',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                    Text('Mute all notifications during a specified duration.',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
              ),
              Switch(
                activeThumbColor: const Color(0xFFE65C00),
                value: _quietHoursEnabled,
                onChanged: (v) => setState(() => _quietHoursEnabled = v),
              ),
            ],
          ),
          if (_quietHoursEnabled) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectQuietTime(true),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBF5EE),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFF3ED)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('From', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[500])),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatTimeForDisplay(_quietHoursStart),
                                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                              const Icon(Icons.access_time, size: 14, color: Color(0xFFE65C00)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectQuietTime(false),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBF5EE),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFF3ED)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('To', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[500])),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatTimeForDisplay(_quietHoursEnd),
                                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                              const Icon(Icons.access_time, size: 14, color: Color(0xFFE65C00)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

