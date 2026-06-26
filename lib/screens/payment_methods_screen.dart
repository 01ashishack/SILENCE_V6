import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';
import '../utils/upi_launcher.dart';
import '../utils/error_messages.dart';
import '../widgets/states/states.dart';
import '../widgets/app_gradient_scaffold.dart';

/// Admin-facing screen to manage how members pay this library: a cash toggle and
/// a list of UPI IDs. These are the exact values members see as deep-link app
/// buttons on the join / renewal screens. Stored in `libraries.social_links`
/// (`cash_enabled`, `upi_ids`) — saved by MERGING so social-media links in the
/// same JSONB are never wiped.
class PaymentMethodsScreen extends StatefulWidget {
  final String libraryId;

  const PaymentMethodsScreen({super.key, required this.libraryId});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _upiCtrl = TextEditingController();

  bool _loading = true;
  Object? _error;
  bool _saving = false;

  // Working copy of the whole social_links map (so we never drop other keys).
  Map<String, dynamic> _social = {};
  bool _cashEnabled = true;
  List<String> _upiIds = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _upiCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final row = await _supabase
          .from('libraries')
          .select('social_links')
          .eq('id', widget.libraryId)
          .maybeSingle();
      final social = (row?['social_links'] is Map)
          ? Map<String, dynamic>.from(row!['social_links'])
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _social = social;
        _cashEnabled = social['cash_enabled'] is bool ? social['cash_enabled'] as bool : true;
        _upiIds = (social['upi_ids'] is List)
            ? (social['upi_ids'] as List)
                .map((e) => e.toString())
                .where((s) => s.trim().isNotEmpty)
                .toList()
            : <String>[];
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

  void _addUpi() {
    final id = _upiCtrl.text.trim();
    if (id.isEmpty) return;
    if (!_isValidUpi(id)) {
      _toast('Enter a valid UPI ID like yourname@paytm');
      return;
    }
    if (_upiIds.contains(id)) {
      _toast('This UPI ID is already added');
      return;
    }
    setState(() {
      _upiIds.add(id);
      _upiCtrl.clear();
    });
  }

  bool _isValidUpi(String id) {
    final parts = id.split('@');
    return parts.length == 2 && parts[0].trim().isNotEmpty && parts[1].trim().isNotEmpty;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = Map<String, dynamic>.from(_social)
        ..['cash_enabled'] = _cashEnabled
        ..['upi_ids'] = _upiIds;
      await _supabase.from('libraries').update({'social_links': updated}).eq('id', widget.libraryId);
      if (!mounted) return;
      _social = updated;
      _toast('Payment methods saved');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientScaffold(
      title: 'Payment Methods',
      body: _loading
          ? const LoadingState(kind: SkeletonKind.spinner, message: 'Loading…')
          : _error != null
              ? ErrorState(error: _error, onRetry: _load)
              : _buildForm(),
      bottomNavigationBar: (_loading || _error != null) ? null : _buildSaveBar(),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _infoBanner(),
        const SizedBox(height: 20),
        _cashCard(),
        const SizedBox(height: 20),
        _upiSection(),
      ],
    );
  }

  Widget _infoBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.info),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Members pay you directly via these methods. You verify the payment in your own UPI/bank app, then confirm their request.',
              style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: context.palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cashCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.border),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeThumbColor: AppColors.primary,
        value: _cashEnabled,
        onChanged: (v) => setState(() => _cashEnabled = v),
        title: Text(
          'Accept cash at the library',
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: context.palette.textPrimary),
        ),
        subtitle: Text(
          'Members can choose to pay cash at the desk.',
          style: GoogleFonts.inter(fontSize: 12, color: context.palette.textMuted),
        ),
      ),
    );
  }

  Widget _upiSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'UPI IDs',
            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            'Add the UPI IDs where members should send payment.',
            style: GoogleFonts.inter(fontSize: 12, color: context.palette.textMuted),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _upiCtrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. yourname@paytm',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addUpi(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _addUpi,
                child: Text('Add', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_upiIds.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No UPI IDs added yet.',
                style: GoogleFonts.inter(fontSize: 12.5, color: context.palette.textMuted),
              ),
            )
          else
            ..._upiIds.map(_upiRow),
        ],
      ),
    );
  }

  Widget _upiRow(String id) {
    final app = detectUpiApp(id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.palette.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: app.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(app.icon, size: 17, color: app.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(id, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.palette.textPrimary)),
                Text(app.name, style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.danger),
            tooltip: 'Remove',
            onPressed: () => setState(() => _upiIds.remove(id)),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text('Save', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
