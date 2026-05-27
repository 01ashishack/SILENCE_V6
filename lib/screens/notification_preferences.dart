import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() => _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState extends State<NotificationPreferencesScreen> {
  bool _isLoading = false;

  // Preferences local state
  bool _announcePush = true;
  bool _remindersPush = true;
  bool _checkinPush = false;
  bool _expiryPush = true;
  bool _weeklyEmail = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _announcePush = prefs.getBool('notif_announce_push') ?? true;
      _remindersPush = prefs.getBool('notif_reminders_push') ?? true;
      _checkinPush = prefs.getBool('notif_checkin_push') ?? false;
      _expiryPush = prefs.getBool('notif_expiry_push') ?? true;
      _weeklyEmail = prefs.getBool('notif_weekly_email') ?? false;
      _isLoading = false;
    });
  }

  Future<void> _savePreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
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
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header title
                      Text(
                        'Alert & Message Settings',
                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 12),

                      // Toggles Card
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            _buildPreferenceSwitch(
                              'Broadcast Announcements',
                              'Receive immediate alerts when you broadcast new messages or notices.',
                              _announcePush,
                              (val) {
                                setState(() => _announcePush = val);
                                _savePreference('notif_announce_push', val);
                              },
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildPreferenceSwitch(
                              'Payment Invoicing Reminders',
                              'Remind members automatically 3 days before their plan expiry dates.',
                              _remindersPush,
                              (val) {
                                setState(() => _remindersPush = val);
                                _savePreference('notif_reminders_push', val);
                              },
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildPreferenceSwitch(
                              'Daily Check-in Alerts',
                              'Notify the admin account immediately whenever a member registers a check-in.',
                              _checkinPush,
                              (val) {
                                setState(() => _checkinPush = val);
                                _savePreference('notif_checkin_push', val);
                              },
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildPreferenceSwitch(
                              'Plan Expiry Push Notices',
                              'Send system dashboard flags when desk slots are released on expiry.',
                              _expiryPush,
                              (val) {
                                setState(() => _expiryPush = val);
                                _savePreference('notif_expiry_push', val);
                              },
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildPreferenceSwitch(
                              'Weekly Analytics Email Reports',
                              'Deliver full CSV summaries and custom painters analytics trends weekly.',
                              _weeklyEmail,
                              (val) {
                                setState(() => _weeklyEmail = val);
                                _savePreference('notif_weekly_email', val);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Back Button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: Text(
                          'Save Notification Preferences',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildPreferenceSwitch(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          title,
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2.0),
          child: Text(
            subtitle,
            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
          ),
        ),
        value: value,
        activeColor: const Color(0xFFE65C00),
        onChanged: onChanged,
      ),
    );
  }
}
