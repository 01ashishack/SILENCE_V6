import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../core/admin_settings_service.dart';

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
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;
  bool _didInit = false;
  String? _libId;
  List<AddonItem> _addons = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return; // run the initial load exactly once
    _didInit = true;
    final Object? args = ModalRoute.of(context)?.settings.arguments;
    if (args is String && args.isNotEmpty) {
      _libId = args;
      debugPrint('AddonServicesScreen: Resolved active library ID from route arguments: $_libId');
      _loadAddons();
    } else {
      debugPrint('AddonServicesScreen: Route arguments empty. Loading fallback library ID.');
      _loadFallbackLibrary();
    }
  }

  Future<void> _loadFallbackLibrary() async {
    setState(() => _isLoading = true);
    try {
      _libId = await AdminSettingsService.firstOwnedLibraryId();
      debugPrint('AddonServicesScreen: Resolved fallback library ID: $_libId');
      if (_libId != null) {
        await _loadAddons();
        if (!mounted) return;
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('AddonServicesScreen: Error loading fallback library ID: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAddons() async {
    if (_libId == null) return;
    setState(() => _isLoading = true);
    debugPrint('AddonServicesScreen: Fetching add-ons for library ID: $_libId');

    try {
      final response = await _supabase
          .from('add_ons')
          .select()
          .eq('library_id', _libId!)
          .eq('active', true);

      // Fetch actual allocations to compute exact counts (P2/Honest UI)
      final List<dynamic> allocationsRes = await _supabase
          .from('member_add_ons')
          .select('add_on_id');
      final Map<String, int> allocationCounts = {};
      for (final row in allocationsRes) {
        final addonId = row['add_on_id']?.toString();
        if (addonId != null) {
          allocationCounts[addonId] = (allocationCounts[addonId] ?? 0) + 1;
        }
      }

      debugPrint('AddonServicesScreen: Supabase returned ${response.length} rows for library $_libId.');

      final List<AddonItem> loadedItems = [];
      for (final row in response) {
        final id = row['id']?.toString() ?? '';
        final name = row['name']?.toString() ?? '';
        final price = (row['price'] as num?)?.toDouble() ?? 0.0;
        final deposit = (row['refundable_deposit'] as num?)?.toDouble() ?? 0.0;
        final totalInventory = (row['max_available'] as num?)?.toInt() ?? 0;
        final int allocated = allocationCounts[id] ?? 0;

        // Determine icon based on name
        IconData icon = Icons.add_shopping_cart;
        final lowerName = name.toLowerCase();
        if (lowerName.contains('locker')) {
          icon = Icons.lock_outline;
        } else if (lowerName.contains('vip') || lowerName.contains('ac') || lowerName.contains('cabin')) {
          icon = Icons.star_border;
        } else if (lowerName.contains('parking') || lowerName.contains('motorcycle') || lowerName.contains('wheeler')) {
          icon = Icons.motorcycle;
        }

        loadedItems.add(AddonItem(
          id: id,
          name: name,
          monthlyRate: price,
          securityDeposit: deposit,
          totalInventory: totalInventory,
          allocatedCount: allocated,
          icon: icon,
        ));
      }

      setState(() {
        _addons = loadedItems;
      });
    } catch (e) {
      debugPrint('AddonServicesScreen: Error loading add-ons: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load add-ons: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveAddonSettings(AddonItem item) async {
    if (_libId == null) {
      debugPrint('AddonServicesScreen: Cannot save addon. Library ID is null.');
      return;
    }

    setState(() => _isLoading = true);
    debugPrint('AddonServicesScreen: Saving addon ${item.id} (${item.name}) to Supabase...');

    try {
      final payload = {
        'id': item.id,
        'library_id': _libId!,
        'name': item.name,
        'price': item.monthlyRate.toInt(),
        'price_type': 'monthly', // required NOT NULL; this screen manages monthly add-ons
        'refundable_deposit': item.securityDeposit.toInt(),
        'max_available': item.totalInventory, // correct column name (was total_inventory)
        'active': true,
      };

      await _supabase.from('add_ons').upsert(payload, onConflict: 'id');
      debugPrint('AddonServicesScreen: Successfully saved addon: ${item.id}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.name} details saved! ✓'), backgroundColor: const Color(0xFFE65C00)),
        );
      }
    } catch (e) {
      debugPrint('AddonServicesScreen: Error saving addon: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save configurations: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _loadAddons();
      }
    }
  }

  void _showEditAddonSheet(AddonItem item) {
    final rateCtrl = TextEditingController(text: item.monthlyRate.toStringAsFixed(0));
    final depCtrl = TextEditingController(text: item.securityDeposit.toStringAsFixed(0));

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
              'Edit ${item.name}',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
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

                setState(() {
                  item.monthlyRate = rate;
                  item.securityDeposit = deposit;
                });
                Navigator.pop(context);
                // Defer the parent setState until the sheet has finished
                // unmounting (avoids the _dependents.isEmpty unmount race).
                WidgetsBinding.instance.addPostFrameCallback((_) => _saveAddonSettings(item));
              },
              child: Text('Save Configurations', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ).whenComplete(() {
      rateCtrl.dispose();
      depCtrl.dispose();
    });
  }

  void _showAddAddonSheet() {
    final nameCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    final depCtrl = TextEditingController(text: '0');

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
              'Add Custom Add-on Service',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
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
              controller: depCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Security Deposit (₹)', prefixText: '₹ '),
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
                final deposit = double.tryParse(depCtrl.text) ?? 0;
                final name = nameCtrl.text.trim();

                if (name.isNotEmpty && rate >= 0) {
                  final newId = const Uuid().v4();
                  
                  // Determine icon based on name
                  IconData icon = Icons.add_shopping_cart;
                  final lowerName = name.toLowerCase();
                  if (lowerName.contains('locker')) {
                    icon = Icons.lock_outline;
                  } else if (lowerName.contains('vip') || lowerName.contains('ac') || lowerName.contains('cabin')) {
                    icon = Icons.star_border;
                  } else if (lowerName.contains('parking') || lowerName.contains('motorcycle') || lowerName.contains('wheeler')) {
                    icon = Icons.motorcycle;
                  }

                  final newItem = AddonItem(
                    id: newId,
                    name: name,
                    monthlyRate: rate,
                    securityDeposit: deposit,
                    totalInventory: 0,
                    icon: icon,
                  );
                  
                  Navigator.pop(context);
                  // Defer parent setState until the sheet finished unmounting.
                  WidgetsBinding.instance.addPostFrameCallback((_) => _saveAddonSettings(newItem));
                }
              },
              child: Text('Create Add-on', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ).whenComplete(() {
      nameCtrl.dispose();
      rateCtrl.dispose();
      depCtrl.dispose();
    });
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
              : _addons.isEmpty
                  ? _buildEmptyState()
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
                            color: context.palette.surface,
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
                                      color: const Color(0x1FE65C00),
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
                                          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
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
                                                style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted),
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
                                    style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted, fontWeight: FontWeight.w500),
                                  ),
                                  Text(
                                    '${item.allocatedCount}/${item.totalInventory} units claimed (${(usagePct * 100).toInt()}%)',
                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_bag_outlined,
                size: 64,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No add-ons configured',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.palette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add-ons like lockers, parking space, or VIP cabins help you manage extra services and refundable security deposits.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: context.palette.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddAddonSheet,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                'Add Your First Add-on',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
