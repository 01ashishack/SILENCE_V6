import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/active_library_store.dart';

class PlanItem {
  final String id;
  String name;
  double price;
  String duration; // '1 Day', '1 Week', '1 Month', '3 Months', '6 Months'
  bool isActive;
  bool isPopular;

  PlanItem({
    required this.id,
    required this.name,
    required this.price,
    required this.duration,
    this.isActive = true,
    this.isPopular = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'duration': duration,
        'isActive': isActive,
        'isPopular': isPopular,
      };

  factory PlanItem.fromJson(Map<String, dynamic> json) => PlanItem(
        id: json['id'],
        name: json['name'],
        price: (json['price'] as num).toDouble(),
        duration: json['duration'],
        isActive: json['isActive'] ?? true,
        isPopular: json['isPopular'] ?? false,
      );
}

class PricingPlansScreen extends StatefulWidget {
  final String? libraryId;
  const PricingPlansScreen({super.key, this.libraryId});

  @override
  State<PricingPlansScreen> createState() => _PricingPlansScreenState();
}

class _PricingPlansScreenState extends State<PricingPlansScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;
  String? _libId;
  List<PlanItem> _plans = [];

  bool _isInit = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.isNotEmpty) {
        _libId = args;
      }
      _fetchPlans();
      _isInit = false;
    }
  }

  Future<void> _fetchPlans() async {
    setState(() => _isLoading = true);
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        _libId ??= widget.libraryId;
        _libId = await ActiveLibraryStore.resolve(_libId);

        // Setup canonical plans if cache is empty
        _plans = [
          PlanItem(id: 'daily', name: 'Daily Pass', price: 99, duration: '1 Day', isActive: true),
          PlanItem(id: 'weekly', name: 'Weekly Access', price: 399, duration: '1 Week', isActive: true),
          PlanItem(id: 'monthly', name: 'Monthly Pass', price: 1199, duration: '1 Month', isActive: true, isPopular: true),
          PlanItem(id: 'quarterly', name: 'Quarterly Saver', price: 2999, duration: '3 Months', isActive: true),
          PlanItem(id: 'semi_annual', name: 'Semi-Annual Saver', price: 5499, duration: '6 Months', isActive: true),
        ];

        // Sync with db prices from shifts if available
        if (_libId != null) {
          final shiftRes = await _supabase.from('shifts').select().eq('library_id', _libId!).limit(1).maybeSingle();
          if (shiftRes != null) {
            final monthlyPrice = shiftRes['price_monthly'] ?? shiftRes['monthly_price'];
            final quarterlyPrice = shiftRes['price_3month'] ?? shiftRes['price_3_month'];
            final semiPrice = shiftRes['price_6month'] ?? shiftRes['price_6_month'];

            if (monthlyPrice != null) {
              _plans.firstWhere((p) => p.id == 'monthly').price = (monthlyPrice as num).toDouble();
            }
            if (quarterlyPrice != null) {
              _plans.firstWhere((p) => p.id == 'quarterly').price = (quarterlyPrice as num).toDouble();
            }
            if (semiPrice != null) {
              _plans.firstWhere((p) => p.id == 'semi_annual').price = (semiPrice as num).toDouble();
            }
          }
        }
      } catch (e) {
        debugPrint('Error fetching pricing plans: $e');
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _savePlansToCache() async {
    final prefs = await SharedPreferences.getInstance();
    // Simple key-value persistence
    for (final plan in _plans) {
      await prefs.setDouble('pricing_plan_price_${plan.id}_${_libId ?? "default"}', plan.price);
      await prefs.setBool('pricing_plan_active_${plan.id}_${_libId ?? "default"}', plan.isActive);
      await prefs.setBool('pricing_plan_popular_${plan.id}_${_libId ?? "default"}', plan.isPopular);
      if (!mounted) return;
    }
  }

  Future<void> _updatePlanPrice(String id, double newPrice) async {
    setState(() {
      _plans.firstWhere((p) => p.id == id).price = newPrice;
    });
    await _savePlansToCache();

    // Sync with remote supabase shifts table columns if appropriate
    if (_libId != null) {
      try {
        if (id == 'monthly') {
          await _supabase.from('shifts').update({'price_monthly': newPrice}).eq('library_id', _libId!);
        } else if (id == 'quarterly') {
          await _supabase.from('shifts').update({'price_3month': newPrice}).eq('library_id', _libId!);
        } else if (id == 'semi_annual') {
          await _supabase.from('shifts').update({'price_6month': newPrice}).eq('library_id', _libId!);
          if (!mounted) return;
        }
      } catch (_) {}
    }
  }

  Future<void> _togglePlanActive(String id, bool active) async {
    setState(() {
      _plans.firstWhere((p) => p.id == id).isActive = active;
    });
    await _savePlansToCache();
    if (!mounted) return;
  }

  Future<void> _setPopularPlan(String id) async {
    setState(() {
      for (final plan in _plans) {
        plan.isPopular = (plan.id == id);
      }
    });
    await _savePlansToCache();
  }

  void _showEditPriceSheet(PlanItem plan) {
    final controller = TextEditingController(text: plan.price.toStringAsFixed(0));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: 24, left: 24, right: 24
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Edit ${plan.name} Price',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Enter price (INR)...',
                prefixText: '₹ ',
                prefixStyle: TextStyle(color: Color(0xFFE65C00), fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                final double? price = double.tryParse(controller.text);
                if (price != null) {
                  _updatePlanPrice(plan.id, price);
                  Navigator.pop(context);
                }
              },
              child: Text('Update Price', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showAddPlanSheet() {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    String selectedDuration = '1 Month';
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 24, left: 24, right: 24
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add Membership Plan',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: const InputDecoration(hintText: 'Plan Name (e.g. VIP AC Pass)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: const InputDecoration(hintText: 'Price', prefixText: '₹ '),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedDuration,
                decoration: const InputDecoration(labelText: 'Duration'),
                items: ['1 Day', '1 Week', '1 Month', '3 Months', '6 Months', '12 Months']
                    .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setModalState(() => selectedDuration = val);
                  }
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  final price = double.tryParse(priceCtrl.text) ?? 0;
                  if (nameCtrl.text.isNotEmpty && price > 0) {
                    setState(() {
                      _plans.add(PlanItem(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: nameCtrl.text.trim(),
                        price: price,
                        duration: selectedDuration,
                      ));
                    });
                    _savePlansToCache();
                    Navigator.pop(context);
                  }
                },
                child: Text('Create Plan', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 24),
            ],
          ),
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
          backgroundColor: context.palette.scaffold,
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Seat Pricing Plans',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _showAddPlanSheet,
            backgroundColor: const Color(0xFFE65C00),
            icon: const Icon(Icons.add, color: Colors.white),
            label: Text('Add Plan', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          body: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _plans.length,
                  itemBuilder: (context, index) {
                    final plan = _plans[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.palette.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: plan.isPopular ? const Color(0xFFFFD0B8) : const Color(0xFFE2E8F0), width: plan.isPopular ? 1.5 : 1.0),
                        boxShadow: [
                          if (plan.isPopular)
                            BoxShadow(color: const Color(0xFFE65C00).withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF3ED),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.receipt_long, color: Color(0xFFE65C00), size: 22),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          plan.name,
                                          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                                        ),
                                        if (plan.isPopular) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE65C00),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Popular',
                                              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Duration: ${plan.duration}',
                                      style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: plan.isActive,
                                activeThumbColor: const Color(0xFFE65C00),
                                onChanged: (val) {
                                  _togglePlanActive(plan.id, val);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Plan Pricing Rate',
                                    style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '₹${plan.price.toStringAsFixed(0)}',
                                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _showEditPriceSheet(plan),
                                    icon: const Icon(Icons.edit, size: 14, color: Color(0xFFE65C00)),
                                    label: Text('Edit Price', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                                  ),
                                  if (!plan.isPopular) ...[
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => _setPopularPlan(plan.id),
                                      child: Text(
                                        'Set Popular',
                                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: context.palette.textMuted),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
