import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AddonItem {
  final String id;
  String name;
  double monthlyRate;
  double securityDeposit;
  int totalInventory;
  int allocatedCount;
  IconData icon;

  AddonItem({
    required this.id,
    required this.name,
    required this.monthlyRate,
    required this.securityDeposit,
    required this.totalInventory,
    this.allocatedCount = 0,
    required this.icon,
  });
}

class AddonServicesScreen extends StatefulWidget {
  const AddonServicesScreen({super.key});

  @override
  State<AddonServicesScreen> createState() => _AddonServicesScreenState();
}

class _AddonServicesScreenState extends State<AddonServicesScreen> {
  bool _isLoading = false;
  List<AddonItem> _addons = [];

  @override
  void initState() {
    super.initState();
    _loadAddons();
  }

  Future<void> _loadAddons() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    
    // Set standard default items
    _addons = [
      AddonItem(
        id: 'lockers',
        name: 'Personal Locker (Standard)',
        monthlyRate: 150,
        securityDeposit: 200,
        totalInventory: 40,
        allocatedCount: 18,
        icon: Icons.lock_outline,
      ),
      AddonItem(
        id: 'vip_ac',
        name: 'VIP Cabin AC Desks',
        monthlyRate: 500,
        securityDeposit: 0,
        totalInventory: 12,
        allocatedCount: 5,
        icon: Icons.star_border,
      ),
      AddonItem(
        id: 'parking',
        name: 'Reserved Two-Wheeler Parking',
        monthlyRate: 100,
        securityDeposit: 100,
        totalInventory: 20,
        allocatedCount: 12,
        icon: Icons.motorcycle,
      ),
    ];

    // Read stored settings if available
    for (final item in _addons) {
      final rate = prefs.getDouble('addon_rate_${item.id}');
      final deposit = prefs.getDouble('addon_deposit_${item.id}');
      final total = prefs.getInt('addon_total_${item.id}');
      if (rate != null) item.monthlyRate = rate;
      if (deposit != null) item.securityDeposit = deposit;
      if (total != null) item.totalInventory = total;
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveAddonSettings(AddonItem item) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('addon_rate_${item.id}', item.monthlyRate);
    await prefs.setDouble('addon_deposit_${item.id}', item.securityDeposit);
    await prefs.setInt('addon_total_${item.id}', item.totalInventory);
  }

  void _showEditAddonSheet(AddonItem item) {
    final rateCtrl = TextEditingController(text: item.monthlyRate.toStringAsFixed(0));
    final depCtrl = TextEditingController(text: item.securityDeposit.toStringAsFixed(0));
    final limitCtrl = TextEditingController(text: item.totalInventory.toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
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
              'Edit ${item.name}',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: rateCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Monthly Rate (₹)', prefixText: '₹ '),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: depCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Security Deposit (₹)', prefixText: '₹ '),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: limitCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Total Available Inventory'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                final rate = double.tryParse(rateCtrl.text) ?? item.monthlyRate;
                final deposit = double.tryParse(depCtrl.text) ?? item.securityDeposit;
                final total = int.tryParse(limitCtrl.text) ?? item.totalInventory;
                
                setState(() {
                  item.monthlyRate = rate;
                  item.securityDeposit = deposit;
                  item.totalInventory = total;
                });
                _saveAddonSettings(item);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${item.name} details saved! ✓'), backgroundColor: const Color(0xFFE65C00)),
                );
              },
              child: Text('Save Configurations', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showAddAddonSheet() {
    final nameCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    final limitCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
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
              'Add Custom Add-on Service',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(hintText: 'Service Name (e.g. VIP AC Cabin)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rateCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Monthly Rate (₹)', prefixText: '₹ '),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: limitCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Total Available Inventory'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                final rate = double.tryParse(rateCtrl.text) ?? 0;
                final limit = int.tryParse(limitCtrl.text) ?? 0;
                if (nameCtrl.text.isNotEmpty && rate > 0) {
                  final newItem = AddonItem(
                    id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                    name: nameCtrl.text.trim(),
                    monthlyRate: rate,
                    securityDeposit: 0,
                    totalInventory: limit,
                    icon: Icons.add_shopping_cart,
                  );
                  setState(() {
                    _addons.add(newItem);
                  });
                  _saveAddonSettings(newItem);
                  Navigator.pop(context);
                }
              },
              child: Text('Create Add-on', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
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
            title: Text(
              'Add-on Services Settings',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _showAddAddonSheet,
            backgroundColor: const Color(0xFFE65C00),
            icon: const Icon(Icons.add, color: Colors.white),
            label: Text('New Add-on', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _addons.length,
                  itemBuilder: (context, index) {
                    final item = _addons[index];
                    final usagePct = item.totalInventory > 0 ? (item.allocatedCount / item.totalInventory) : 0.0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                                child: Icon(item.icon, color: const Color(0xFFE65C00), size: 22),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          '₹${item.monthlyRate.toStringAsFixed(0)}/mo',
                                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                                        ),
                                        if (item.securityDeposit > 0) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            '• Deposit: ₹${item.securityDeposit.toStringAsFixed(0)}',
                                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFFE65C00)),
                                onPressed: () => _showEditAddonSheet(item),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Allocation Statistics',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                              ),
                              Text(
                                '${item.allocatedCount}/${item.totalInventory} units claimed (${(usagePct * 100).toInt()}%)',
                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: usagePct,
                              backgroundColor: const Color(0xFFF1F5F9),
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
                              minHeight: 8,
                            ),
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
