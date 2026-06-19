import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/admin_settings_service.dart';
import '../widgets/app_gradient_scaffold.dart';

class ReferralSettingsScreen extends StatefulWidget {
  const ReferralSettingsScreen({super.key});

  @override
  State<ReferralSettingsScreen> createState() => _ReferralSettingsScreenState();
}

class _ReferralSettingsScreenState extends State<ReferralSettingsScreen> {
  bool _isLoading = false;
  String? _libId;
  
  // Program status state
  bool _isEnabled = true;
  final _referrerDaysCtrl = TextEditingController(text: '5');
  final _refereeDaysCtrl = TextEditingController(text: '3');

  // Stats aggregate
  int _totalReferred = 0;
  int _pendingReferred = 0;
  int _rewardedReferred = 0;

  @override
  void initState() {
    super.initState();
    _loadReferralRules();
  }

  @override
  void dispose() {
    _referrerDaysCtrl.dispose();
    _refereeDaysCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReferralRules() async {
    setState(() => _isLoading = true);
    _libId = await AdminSettingsService.firstOwnedLibraryId();
    final settings = await AdminSettingsService.load(
      scope: 'referral_settings',
      libraryId: _libId,
    );

    int total = 0;
    int pending = 0;
    int rewarded = 0;

    try {
      final supabase = Supabase.instance.client;
      if (_libId != null) {
        final referrals = await supabase
            .from('referrals')
            .select('*')
            .eq('library_id', _libId!);
        if (!mounted) return;

        total = referrals.length;
        pending = referrals.where((r) => r['status'] == 'pending').length;
        rewarded = referrals.where((r) => r['status'] == 'credited' || r['status'] == 'rewarded').length;
      }
    } catch (e) {
      debugPrint('Error loading referral stats: $e');
    }

    setState(() {
      _isEnabled = settings['enabled'] as bool? ?? true;
      _referrerDaysCtrl.text = settings['referrer_days']?.toString() ?? '5';
      _refereeDaysCtrl.text = settings['referee_days']?.toString() ?? '3';
      _totalReferred = total;
      _pendingReferred = pending;
      _rewardedReferred = rewarded;
      _isLoading = false;
    });
  }

  Future<void> _saveReferralRules() async {
    setState(() => _isLoading = true);
    await AdminSettingsService.save(
      scope: 'referral_settings',
      libraryId: _libId,
      value: {
        'enabled': _isEnabled,
        'referrer_days': int.tryParse(_referrerDaysCtrl.text.trim()) ?? 5,
        'referee_days': int.tryParse(_refereeDaysCtrl.text.trim()) ?? 3,
      },
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Referral configurations saved! ✓'), backgroundColor: Color(0xFFE65C00)),
    );
    setState(() => _isLoading = false);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientScaffold(
      title: 'Referrals Settings',
      body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Program switch Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Referral Rewards Program',
                            style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                          ),
                          subtitle: Text(
                            'Enable incentives to reward active members for referring new students.',
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                          ),
                          value: _isEnabled,
                          activeThumbColor: const Color(0xFFE65C00),
                          onChanged: (val) {
                            setState(() => _isEnabled = val);
                          },
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 2. Configuration panel (Visible when program enabled)
                      if (_isEnabled) ...[
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Rewards Configuration',
                                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                              ),
                              const SizedBox(height: 16),
                              
                              Text(
                                'Free Days for Referrer (Exiting Member)',
                                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  SizedBox(
                                    width: 80,
                                    child: TextFormField(
                                      controller: _referrerDaysCtrl,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Free membership extension days',
                                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              Text(
                                'Free Days for Referee (New Joining Student)',
                                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  SizedBox(
                                    width: 80,
                                    child: TextFormField(
                                      controller: _refereeDaysCtrl,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Free extension days added to plan',
                                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // Info Alert abuse prevention
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.info_outline, color: Color(0xFF2563EB), size: 16),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'ℹ This sets your reward policy. Crediting is applied manually for now — extend the referrer’s membership once the new member is active. Automatic crediting comes later.',
                                        style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF1D4ED8), height: 1.4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // 3. Stats Aggregations
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Aggregate Metrics',
                              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 16),
                            if (_totalReferred == 0)
                              Center(
                                child: Column(
                                  children: [
                                    const Icon(Icons.people_outline, size: 40, color: Colors.grey),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No referrals yet. Share your library code to get started.',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildMetricColumn('$_totalReferred', 'Total Referred'),
                                  _buildMetricColumn('$_pendingReferred', 'Pending'),
                                  _buildMetricColumn('$_rewardedReferred', 'Rewarded'),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // 4. Save Button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        onPressed: _saveReferralRules,
                        child: Text(
                          'Save Settings',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildMetricColumn(String val, String label) {
    return Column(
      children: [
        Text(
          val,
          style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
        ),
      ],
    );
  }
}
