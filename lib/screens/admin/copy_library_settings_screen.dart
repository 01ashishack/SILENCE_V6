import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/admin_settings_service.dart';

/// Time-saver for multi-library owners: copy configuration from ONE source
/// library into the current (target) library, instead of re-entering it.
///
/// Design choice: COPY (one-time), not LINK. Copied rows are independent — later
/// edits to the source do NOT change the target (and vice-versa). This avoids
/// the classic "changed one library, another silently changed too" bug. The
/// owner re-runs this (or edits) whenever they want them to match again.
///
/// All copies are ADDITIVE (they insert new rows / overwrite scalar config);
/// they never delete the target's existing data. Running twice can create
/// duplicate shifts/add-ons, so the UI warns about that.
class CopyLibrarySettingsScreen extends StatefulWidget {
  /// The library being set up (copy INTO this one).
  final String targetLibraryId;
  final String targetLibraryName;

  const CopyLibrarySettingsScreen({
    super.key,
    required this.targetLibraryId,
    required this.targetLibraryName,
  });

  @override
  State<CopyLibrarySettingsScreen> createState() =>
      _CopyLibrarySettingsScreenState();
}

class _CopyLibrarySettingsScreenState extends State<CopyLibrarySettingsScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _copying = false;
  Object? _error;
  List<Map<String, dynamic>> _sourceOptions = [];
  String? _sourceId;

  // What to copy
  bool _copyShifts = true;
  bool _copyAddons = true;
  bool _copyAmenities = true;
  bool _copyRules = true;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw 'Not signed in.';
      final res = await _supabase
          .from('libraries')
          .select('id, name')
          .eq('owner_id', user.id)
          .order('created_at');
      final all = List<Map<String, dynamic>>.from(res);
      // Source can be any OTHER owned library.
      _sourceOptions = all
          .where((l) => l['id'].toString() != widget.targetLibraryId)
          .toList();
      _sourceId = _sourceOptions.isNotEmpty
          ? _sourceOptions.first['id'].toString()
          : null;
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _doCopy() async {
    final source = _sourceId;
    if (source == null) return;
    if (!_copyShifts && !_copyAddons && !_copyAmenities && !_copyRules) {
      _snack('Select at least one thing to copy.');
      return;
    }
    setState(() => _copying = true);
    final summary = <String>[];
    final failures = <String>[];

    // ── Shifts & plans ──────────────────────────────────────────────────────
    if (_copyShifts) {
      try {
        final rows = await _supabase
            .from('shifts')
            .select(
                'name, start_time, end_time, price_monthly, price_3month, price_6month, trial_days, shift_type, hours_per_day')
            .eq('library_id', source)
            .eq('is_archived', false);
        final list = List<Map<String, dynamic>>.from(rows);
        if (list.isNotEmpty) {
          final toInsert = list
              .map((s) => {...s, 'library_id': widget.targetLibraryId})
              .toList();
          await _supabase.from('shifts').insert(toInsert);
          summary.add('${list.length} shift(s) & plans');
        }
      } catch (e) {
        failures.add('shifts');
        debugPrint('copy shifts failed: $e');
      }
    }

    // ── Add-ons ─────────────────────────────────────────────────────────────
    if (_copyAddons) {
      try {
        final rows = await _supabase
            .from('add_ons')
            .select('name, price, price_type, refundable_deposit, max_available, active')
            .eq('library_id', source);
        final list = List<Map<String, dynamic>>.from(rows);
        if (list.isNotEmpty) {
          final toInsert = list
              .map((a) => {...a, 'library_id': widget.targetLibraryId})
              .toList();
          await _supabase.from('add_ons').insert(toInsert);
          summary.add('${list.length} add-on(s)');
        }
      } catch (e) {
        failures.add('add-ons');
        debugPrint('copy add-ons failed: $e');
      }
    }

    // ── Amenities (scalar array on libraries) ────────────────────────────────
    if (_copyAmenities) {
      try {
        final src = await _supabase
            .from('libraries')
            .select('amenities')
            .eq('id', source)
            .maybeSingle();
        final amenities = src?['amenities'];
        if (amenities != null) {
          await _supabase
              .from('libraries')
              .update({'amenities': amenities}).eq('id', widget.targetLibraryId);
          summary.add('amenities');
        }
      } catch (e) {
        failures.add('amenities');
        debugPrint('copy amenities failed: $e');
      }
    }

    // ── Business rules (settings scope + libraries.rules_metadata) ───────────
    if (_copyRules) {
      try {
        final rules = await AdminSettingsService.load(
          scope: 'business_rules',
          libraryId: source,
        );
        if (rules.isNotEmpty) {
          await AdminSettingsService.save(
            scope: 'business_rules',
            libraryId: widget.targetLibraryId,
            value: rules,
          );
        }
        // Mirror the denormalised copy some screens read.
        final src = await _supabase
            .from('libraries')
            .select('rules_metadata')
            .eq('id', source)
            .maybeSingle();
        final meta = src?['rules_metadata'];
        if (meta != null) {
          await _supabase
              .from('libraries')
              .update({'rules_metadata': meta}).eq('id', widget.targetLibraryId);
        }
        if (rules.isNotEmpty || meta != null) summary.add('business rules');
      } catch (e) {
        failures.add('business rules');
        debugPrint('copy rules failed: $e');
      }
    }

    if (!mounted) return;
    setState(() => _copying = false);

    if (failures.isEmpty && summary.isNotEmpty) {
      _snack('Copied: ${summary.join(', ')} ✓', success: true);
      Navigator.of(context).pop(true);
    } else if (failures.isNotEmpty) {
      _snack(
        'Copied: ${summary.isEmpty ? "nothing" : summary.join(', ')}. '
        'Failed: ${failures.join(', ')}.',
      );
    } else {
      _snack('Nothing to copy — the source library has no matching settings.');
    }
  }

  void _snack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: success ? const Color(0xFF16A34A) : const Color(0xFF334155),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF5EE),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE65C00),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Copy settings',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
        ),
      );
    }
    if (_error != null) {
      return Center(child: Text('Could not load: $_error'));
    }
    if (_sourceOptions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'You need at least one other library to copy settings from.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: const Color(0xFF6B7280)),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7F0),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFE0CC)),
          ),
          child: Text(
            'Copy configuration INTO "${widget.targetLibraryName}". '
            'Copies are one-time and independent — editing the source later '
            'won\'t change this library. Running this again can create duplicate '
            'shifts/add-ons.',
            style: GoogleFonts.inter(
                fontSize: 12.5, height: 1.4, color: const Color(0xFF9A3412)),
          ),
        ),
        const SizedBox(height: 16),
        Text('Copy from',
            style: GoogleFonts.inter(
                fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF334155))),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _sourceId,
          dropdownColor: Colors.white,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          items: _sourceOptions
              .map((l) => DropdownMenuItem<String>(
                    value: l['id'].toString(),
                    child: Text(l['name']?.toString() ?? 'Library'),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _sourceId = v),
        ),
        const SizedBox(height: 16),
        Text('What to copy',
            style: GoogleFonts.inter(
                fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF334155))),
        _copyTile('Shifts & plans', 'Shift times + monthly/3-/6-month prices',
            _copyShifts, (v) => setState(() => _copyShifts = v)),
        _copyTile('Add-ons', 'Amenities & add-on items with prices', _copyAddons,
            (v) => setState(() => _copyAddons = v)),
        _copyTile('Amenities list', 'The library\'s amenity tags', _copyAmenities,
            (v) => setState(() => _copyAmenities = v)),
        _copyTile('Business rules', 'Discount cap, grace days, hold limits',
            _copyRules, (v) => setState(() => _copyRules = v)),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _copying ? null : _doCopy,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE65C00),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _copying
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                )
              : Text('Copy into this library',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      ],
    );
  }

  Widget _copyTile(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SwitchListTile(
          activeThumbColor: const Color(0xFFE65C00),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          title: Text(title,
              style: GoogleFonts.inter(
                  fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E))),
          subtitle: Text(subtitle,
              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF94A3B8))),
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
