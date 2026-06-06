import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InvoiceItem {
  final String id;
  final String date;
  final double amount;
  final String status;

  InvoiceItem({
    required this.id,
    required this.date,
    required this.amount,
    required this.status,
  });
}

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;
  
  // Subscription state
  String _currentPlan = 'Free Trial'; // 'Free Trial', 'Pro Plan'
  double _price = 0;
  String _status = 'Active';
  String _renewalDate = '12 Jun 2026';
  List<InvoiceItem> _invoices = [];

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
        final prefs = await SharedPreferences.getInstance();
        _currentPlan = prefs.getString('sub_plan_${user.id}') ?? 'Free Trial';
        _status = prefs.getString('sub_status_${user.id}') ?? 'Active';
        _renewalDate = prefs.getString('sub_renewal_${user.id}') ?? '12 Jun 2026';
        _price = _currentPlan == 'Pro Plan' ? 799 : 0;

        // Fetch remote user details as source of truth
        final userData = await _supabase.from('users').select().eq('id', user.id).maybeSingle();
        if (userData != null) {
          final plan = userData['subscription_plan'] ?? userData['plan_type'];
          final status = userData['subscription_status'] ?? userData['status'];
          if (plan == 'pro' || plan == 'pro_plan') {
            _currentPlan = 'Pro Plan';
            _price = 799;
          }
          if (status != null) {
            _status = status.toString().toUpperCase() == 'ACTIVE' ? 'Active' : status.toString();
          }
        }

        // Fetch real invoice history from payments table
        try {
          final paymentsRes = await _supabase
              .from('payments')
              .select('id, amount, payment_date, type, method')
              .eq('member_id', user.id)
              .order('payment_date', ascending: false)
              .limit(10);
          _invoices = (paymentsRes as List).map<InvoiceItem>((p) {
            final rawDate = p['payment_date'] as String?;
            String formattedDate = 'N/A';
            if (rawDate != null) {
              try {
                formattedDate = DateFormat('dd MMM yyyy').format(DateTime.parse(rawDate).toLocal());
              } catch (_) {
                formattedDate = rawDate.split('T').first;
              }
            }
            final amt = (p['amount'] as num? ?? 0).toDouble();
            final shortId = 'INV-${(p['id'] as String? ?? '').substring(0, 8).toUpperCase()}';
            final method = (p['method'] as String? ?? 'upi').toUpperCase();
            return InvoiceItem(
              id: shortId,
              date: formattedDate,
              amount: amt,
              status: method,
            );
          }).toList();
        } catch (_) {
          _invoices = [];
        }
      } catch (e) {
        debugPrint('Error loading subscription stats: $e');
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _processUpgradePayment() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _buildRazorpaySimulationSheet();
      },
    );
  }

  Widget _buildRazorpaySimulationSheet() {
    bool isProcessing = false;
    return StatefulBuilder(
      builder: (context, setModalState) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A), // Premium Dark Slate Razorpay color theme
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 24, left: 24, right: 24
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Razorpay Brand Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'R',
                          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Razorpay Secure',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            'TEST MODE • MOCK CHECKOUT',
                            style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Payment Billing card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SILENCE Pro Plan Upgrade',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Monthly recurring subscription',
                          style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                    Text(
                      '₹799.00',
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF3B82F6)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              if (isProcessing) ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40.0),
                    child: Column(
                      children: [
                        CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6))),
                        SizedBox(height: 16),
                        Text('Authorizing payment with bank gateway...', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // Payment Methods list
                Text(
                  'PAYMENT OPTIONS',
                  style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B), fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildSimulatedPaymentRow('UPI (Google Pay / PhonePe)', 'Instant authorization', Icons.qr_code_scanner, () async {
                  setModalState(() => isProcessing = true);
                  await _completeProUpgrade();
                  if (!mounted) return;
                  Navigator.pop(context);
                }),
                const Divider(height: 1, color: Colors.white10),
                _buildSimulatedPaymentRow('Credit / Debit Card', 'Visa, Mastercard, RuPay', Icons.credit_card, () async {
                  setModalState(() => isProcessing = true);
                  await _completeProUpgrade();
                  if (!mounted) return;
                  Navigator.pop(context);
                }),
                const Divider(height: 1, color: Colors.white10),
                _buildSimulatedPaymentRow('Netbanking', 'All Indian banks integrated', Icons.account_balance, () async {
                  setModalState(() => isProcessing = true);
                  await _completeProUpgrade();
                  if (!mounted) return;
                  Navigator.pop(context);
                }),
              ],
              const SizedBox(height: 32),
            ],
          ));
        },
      );
  }

  Widget _buildSimulatedPaymentRow(String title, String subtitle, IconData icon, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: const Color(0xFF3B82F6), size: 20),
      title: Text(
        title,
        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B)),
      ),
      trailing: const Icon(Icons.chevron_right, size: 16, color: Color(0xFF475569)),
      onTap: onTap,
    );
  }

  Future<void> _completeProUpgrade() async {
    await Future.delayed(const Duration(milliseconds: 2000)); // Simulated delay
    final user = _supabase.auth.currentUser;
    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sub_plan_${user.id}', 'Pro Plan');
      await prefs.setString('sub_status_${user.id}', 'Active');
      await prefs.setString('sub_renewal_${user.id}', '27 Jun 2026');

      // Update Supabase users table subscription columns
      try {
        await _supabase.from('users').update({
          'subscription_plan': 'pro',
          'subscription_status': 'active',
        }).eq('id', user.id);
        if (!mounted) return;
      } catch (_) {}
    }

    setState(() {
      _currentPlan = 'Pro Plan';
      _price = 799;
      _status = 'Active';
      _renewalDate = '27 Jun 2026';
      _invoices.insert(0, InvoiceItem(id: 'INV-2026-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}', date: '27 May 2026', amount: 799, status: 'Paid'));
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Plan upgraded to Pro Plan successfully! 👑 ✓'),
        backgroundColor: Color(0xFF10B981),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTrial = _currentPlan == 'Free Trial';
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
              'Subscription & Billing',
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
                      // 1. Current Plan gradient card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE65C00), Color(0xFFFF7E29)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFFE65C00).withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Text('👑', style: TextStyle(fontSize: 22)),
                                    const SizedBox(width: 8),
                                    Text(
                                      _currentPlan,
                                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Text(
                                    _status.toUpperCase(),
                                    style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '₹${_price.toStringAsFixed(0)}/month',
                              style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isTrial 
                                  ? 'Upgrade to Pro Plan for unlimited features'
                                  : 'Next renewal date: $_renewalDate',
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                            ),
                            const SizedBox(height: 20),
                            const Divider(height: 1, color: Colors.white24),
                            const SizedBox(height: 16),
                            _buildPlanFeatureRow('Manage up to 5 library spaces'),
                            _buildPlanFeatureRow('Add unlimited members & scanner check-ins'),
                            _buildPlanFeatureRow('Bespoke CustomPainter charts & CSV exports'),
                            _buildPlanFeatureRow('Priority technical support 24/7'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 2. Pricing details & actions
                      if (isTrial) ...[
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE65C00),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          onPressed: _processUpgradePayment,
                          child: Text(
                            'Upgrade to Pro Plan — ₹799/mo',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ] else ...[
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Subscription cancellation is locked in simulated mode.')),
                            );
                          },
                          child: Text(
                            'Cancel Subscription',
                            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),

                      // 3. Invoice History
                      if (_invoices.isNotEmpty) ...[
                        Text(
                          'Billing Invoices',
                          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            children: _invoices.map((inv) {
                              return ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.receipt_outlined, size: 16, color: Color(0xFF64748B)),
                                ),
                                title: Text(inv.id, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                                subtitle: Text(inv.date, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '₹${inv.amount.toStringAsFixed(0)}',
                                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        inv.status.toUpperCase(),
                                        style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A)),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildPlanFeatureRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 14),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
