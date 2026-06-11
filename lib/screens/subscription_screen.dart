import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Library-owner subscription screen.
///
/// **Honest beta state:** every library is on the **Free** plan during the beta.
/// Paid plans (Pro ₹499, Premium ₹799) are shown as **mock/indicative** — there
/// is NO in-app billing yet. The app-owner ↔ library-owner Razorpay gateway is
/// integrated later; until then this screen never fakes a payment, invoice, or
/// upgrade. (Replaces the old Razorpay "mock checkout" theatre.)
class _Plan {
  final String name;
  final int price; // ₹ / month
  final String tagline;
  final List<String> features;
  final bool highlight;
  const _Plan(this.name, this.price, this.tagline, this.features,
      {this.highlight = false});
}

const _plans = <_Plan>[
  _Plan(
    'Free',
    0,
    'Everything you need to start — free during beta.',
    [
      'Manage 1 library',
      'Add members + QR check-in',
      'Attendance & basic analytics',
      'Holidays, queries & notifications',
    ],
  ),
  _Plan(
    'Pro',
    499,
    'For a growing study space.',
    [
      'Everything in Free',
      'Multiple libraries',
      'Full analytics + CSV exports',
      'Add-ons & referrals',
    ],
    highlight: true,
  ),
  _Plan(
    'Premium',
    799,
    'For multi-branch owners.',
    [
      'Everything in Pro',
      'Priority support',
      'Advanced reports',
      'Early access to new features',
    ],
  ),
];

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  // Current plan name as a source-of-truth read (defaults to Free in beta).
  String _currentPlan = 'Free';

  @override
  void initState() {
    super.initState();
    _fetchSubscriptionState();
  }

  Future<void> _fetchSubscriptionState() async {
    setState(() => _isLoading = true);
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        final userData =
            await _supabase.from('users').select('subscription_plan').eq('id', user.id).maybeSingle();
        final plan = userData?['subscription_plan']?.toString().toLowerCase();
        if (plan == 'pro' || plan == 'pro_plan') {
          _currentPlan = 'Pro';
        } else if (plan == 'premium') {
          _currentPlan = 'Premium';
        } else {
          _currentPlan = 'Free';
        }
      } catch (e) {
        debugPrint('subscription state load failed: $e');
        _currentPlan = 'Free';
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // Honest: no in-app billing yet. Tapping a paid plan explains the beta state
  // instead of faking a checkout.
  void _onSelectPaidPlan(_Plan plan) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
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
                    color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Icon(Icons.rocket_launch_outlined, color: Color(0xFFE65C00), size: 40),
            const SizedBox(height: 10),
            Text('${plan.name} plan — coming soon',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
            const SizedBox(height: 8),
            Text(
              "You're on the Free plan and everything is free during the beta. "
              'Paid plans (₹${plan.price}/mo) launch later — you\'ll be notified well '
              'before any charges. No payment is taken now.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), height: 1.45),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Got it', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
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
            title: Text('Subscription',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            centerTitle: true,
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
              : RefreshIndicator(
                  color: const Color(0xFFE65C00),
                  onRefresh: _fetchSubscriptionState,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildCurrentPlanBanner(),
                        const SizedBox(height: 20),
                        Text('Choose a plan',
                            style: GoogleFonts.outfit(
                                fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                        const SizedBox(height: 4),
                        Text('Indicative pricing. Billing arrives after the beta.',
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
                        const SizedBox(height: 12),
                        ..._plans.map(_buildPlanCard),
                        const SizedBox(height: 16),
                        _buildBetaNote(),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildCurrentPlanBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE65C00), Color(0xFFFF7E29)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: const Color(0xFFE65C00).withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Your plan: $_currentPlan',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text('FREE DURING BETA',
                    style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('No charges right now. Use every feature free while we’re in beta.',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.white70, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildPlanCard(_Plan plan) {
    final isCurrent = plan.name == _currentPlan || (plan.name == 'Free' && _currentPlan == 'Free');
    final isFree = plan.price == 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: plan.highlight ? const Color(0xFFE65C00) : const Color(0xFFE5E7EB),
          width: plan.highlight ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(plan.name,
                  style: GoogleFonts.outfit(
                      fontSize: 17, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
              const SizedBox(width: 8),
              if (plan.highlight)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFFF3ED), borderRadius: BorderRadius.circular(6)),
                  child: Text('POPULAR',
                      style: GoogleFonts.inter(
                          fontSize: 8.5, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                ),
              const Spacer(),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(8)),
                  child: Text('CURRENT',
                      style: GoogleFonts.inter(
                          fontSize: 8.5, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A))),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(plan.tagline,
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(isFree ? '₹0' : '₹${plan.price}',
                  style: GoogleFonts.outfit(
                      fontSize: 26, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
              const SizedBox(width: 4),
              Text(isFree ? 'always' : '/month',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
            ],
          ),
          const SizedBox(height: 12),
          ...plan.features.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle, size: 15, color: Color(0xFF22C55E)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(f,
                          style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF475569))),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: isCurrent
                ? OutlinedButton(
                    onPressed: null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Current plan',
                        style: GoogleFonts.inter(
                            fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8))),
                  )
                : ElevatedButton(
                    onPressed: () => _onSelectPaidPlan(plan),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: plan.highlight ? const Color(0xFFE65C00) : Colors.white,
                      foregroundColor: plan.highlight ? Colors.white : const Color(0xFFE65C00),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: const Color(0xFFE65C00), width: plan.highlight ? 0 : 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Coming soon',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBetaNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xFF64748B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'In-app billing (Razorpay) is added after the beta. Until then all plans '
              'are free and no card or UPI is charged.',
              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
