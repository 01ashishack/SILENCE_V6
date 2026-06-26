import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/active_library_store.dart';
import '../widgets/seat_generation_inline_widget.dart';


// ─────────────────────────────────────────────────────────────────────────────
// Data models (local, not persisted until Save is tapped)
// ─────────────────────────────────────────────────────────────────────────────

class FloorModel {
  String? id; // null if not yet in DB
  String name;
  List<SectionModel> sections;
  List<SeatModel> floorSeats; // seats without a section
  bool addSeatsDirectly;

  FloorModel({
    this.id,
    required this.name,
    List<SectionModel>? sections,
    List<SeatModel>? floorSeats,
    this.addSeatsDirectly = false,
  })  : sections = sections ?? [],
        floorSeats = floorSeats ?? [];
}

class SectionModel {
  String? id;
  String name;
  String tag; // 'boys'|'girls'|'general'|'premium'
  List<SeatModel> seats;

  SectionModel({this.id, required this.name, this.tag = 'general', List<SeatModel>? seats})
      : seats = seats ?? [];
}

class SeatModel {
  String? id;
  String label;
  String status; // 'vacant'|'occupied'|'hold'|'maintenance'

  SeatModel({this.id, required this.label, this.status = 'vacant'});
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class LibrarySetupStage2Screen extends StatefulWidget {
  const LibrarySetupStage2Screen({super.key});

  @override
  State<LibrarySetupStage2Screen> createState() => _LibrarySetupStage2ScreenState();
}

class _LibrarySetupStage2ScreenState extends State<LibrarySetupStage2Screen> {
  static const _orange = Color(0xFFE65C00);
  Color get _bg => context.palette.scaffold;
  Color get _dark => context.palette.textPrimary;
  Color get _grey => context.palette.textMuted;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _libraryId;
  // Add-library flow: when true, saving the layout finalises a brand-new
  // library (flip status -> active + show the "created" popup).
  bool _isNewLibrary = false;
  bool _sourceCopied = false;

  List<FloorModel> _floors = [];
  int _activeFloorIndex = 0;
  int _floorSeatsPage = 0;

  // Inline content creation state
  String _creationMode = 'section'; // 'section' or 'direct'
  bool _isAddingFloorSeat = false;

  // ── init ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadData();
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;
    if (user == null) { setState(() => _isLoading = false); return; }

    try {
      final Object? args = ModalRoute.of(context)?.settings.arguments;
      String? passedId;
      if (args is String) {
        passedId = args;
      } else if (args is Map) {
        passedId = args['libraryId']?.toString();
        _isNewLibrary = args['isNew'] == true;
        _sourceCopied = args['sourceCopied'] == true;
      }

      String? libId = await ActiveLibraryStore.resolve(passedId);

      if (!mounted) return;
      if (libId == null) { setState(() => _isLoading = false); return; }
      _libraryId = libId;

      final floorsRaw = await sb.from('floors').select().eq('library_id', _libraryId!).order('order_index');
      final List<FloorModel> floors = [];

      for (final f in floorsRaw) {
        final floorId = f['id'] as String;

        // sections for this floor
        final sectionsRaw = await sb.from('sections').select().eq('floor_id', floorId);
        final List<SectionModel> sections = [];
        for (final s in sectionsRaw) {
          final sectionId = s['id'] as String;
          final seatsRaw = await sb.from('seats').select().eq('section_id', sectionId);
          // A physical seat has one DB row PER shift (same label, different
          // shift_id). Dedupe by label so the layout shows one logical seat.
          final seenSecLabels = <String>{};
          final seats = <SeatModel>[];
          for (final seat in (seatsRaw as List)) {
            final label = seat['seat_label'] as String;
            if (!seenSecLabels.add(label)) continue;
            seats.add(SeatModel(
              id: seat['id'] as String,
              label: label,
              status: (seat['status'] as String?) ?? 'vacant',
            ));
          }
          sections.add(SectionModel(
            id: sectionId,
            name: s['name'] as String,
            tag: (s['tag'] as String?) ?? 'general',
            seats: seats,
          ));
        }

        // floor-level seats (section_id is null)
        final floorSeatsRaw = await sb.from('seats').select()
            .eq('floor_id', floorId)
            .isFilter('section_id', null);
        final seenFloorLabels = <String>{};
        final floorSeats = <SeatModel>[];
        for (final seat in (floorSeatsRaw as List)) {
          final label = seat['seat_label'] as String;
          if (!seenFloorLabels.add(label)) continue;
          floorSeats.add(SeatModel(
            id: seat['id'] as String,
            label: label,
            status: (seat['status'] as String?) ?? 'vacant',
          ));
        }

        floors.add(FloorModel(
          id: floorId,
          name: f['name'] as String,
          sections: sections,
          floorSeats: floorSeats,
          addSeatsDirectly: floorSeats.isNotEmpty,
        ));
      }

      setState(() { _floors = floors; _activeFloorIndex = 0; });
    } catch (e) {
      _showError('Error loading layout: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── snackbars ─────────────────────────────────────────────────────────────

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── floor operations ──────────────────────────────────────────────────────

  void _showAddFloorSheet() {
    final ctrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add Floor', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _dark)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Floor Name',
                hintText: 'e.g. Ground Floor, First Floor...',
                hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _orange)),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _grey),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: _grey)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final name = ctrl.text.trim();
                      if (name.isEmpty) return;
                      setState(() {
                        _floors.add(FloorModel(name: name, addSeatsDirectly: false));
                        _activeFloorIndex = _floors.length - 1;
                        _floorSeatsPage = 0;
                      });
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Create', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameFloorSheet(FloorModel floor) {
    final ctrl = TextEditingController(text: floor.name);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Rename Floor', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _dark)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'e.g. Ground Floor, First Floor...',
              hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _orange)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (ctrl.text.trim().isEmpty) return;
                setState(() => floor.name = ctrl.text.trim());
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text('Rename', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    );
  }

  void _deleteFloor(int index) {
    setState(() {
      _floors.removeAt(index);
      if (_activeFloorIndex >= _floors.length) _activeFloorIndex = _floors.isEmpty ? 0 : _floors.length - 1;
      _floorSeatsPage = 0;
    });
  }

  // ── section operations ────────────────────────────────────────────────────

  void _showRenameSectionSheet(SectionModel section) {
    final ctrl = TextEditingController(text: section.name);
    String selectedTag = section.tag;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) => Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Edit Section', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _dark)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _orange)),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                for (final t in ['general', 'boys', 'girls', 'premium'])
                  GestureDetector(
                    onTap: () => setS(() => selectedTag = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: selectedTag == t ? _orange : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: selectedTag == t ? _orange : const Color(0xFFE5E7EB)),
                      ),
                      child: Text(
                        _tagLabel(t),
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: selectedTag == t ? Colors.white : _grey),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (ctrl.text.trim().isEmpty) return;
                  setState(() { section.name = ctrl.text.trim(); section.tag = selectedTag; });
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _orange, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Save', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _deleteSection(FloorModel floor, SectionModel section) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Section', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          'Delete "${section.name}"? This will remove all ${section.seats.length} seats in it.',
          style: GoogleFonts.inter(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () { setState(() => floor.sections.remove(section)); Navigator.pop(ctx); },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showSeatActionSheet(SeatModel seat, {SectionModel? section, FloorModel? floor}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Seat: ${seat.label}', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _dark)),
          const SizedBox(height: 8),
          Text('Status: ${seat.status}', style: GoogleFonts.inter(fontSize: 13, color: _grey)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.build_outlined, color: Colors.amber),
            title: Text('Mark as Maintenance', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
            contentPadding: EdgeInsets.zero,
            onTap: () { setState(() => seat.status = 'maintenance'); Navigator.pop(ctx); },
          ),
          ListTile(
            leading: const Icon(Icons.check_circle_outline, color: Color(0xFF22C55E)),
            title: Text('Mark as Vacant', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
            contentPadding: EdgeInsets.zero,
            onTap: () { setState(() => seat.status = 'vacant'); Navigator.pop(ctx); },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: Text('Delete Seat', style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: Colors.red)),
            contentPadding: EdgeInsets.zero,
            onTap: () {
              setState(() {
                if (section != null) {
                  section.seats.remove(seat);
                } else {
                  floor!.floorSeats.remove(seat);
                }
              });
              Navigator.pop(ctx);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  String _tagLabel(String tag) {
    switch (tag) {
      case 'boys': return '♂ Boys';
      case 'girls': return '♀ Girls';
      case 'general': return '🧑 General';
      case 'premium': return '⭐ Premium';
      default: return tag;
    }
  }

  Color _seatColor(String status) {
    switch (status) {
      case 'occupied': return const Color(0xFF3B82F6);
      case 'maintenance': return const Color(0xFF9CA3AF);
      case 'hold': return const Color(0xFFD97706);
      default: return const Color(0xFF22C55E);
    }
  }

  // ── save to Supabase ──────────────────────────────────────────────────────

  Future<bool> _hasActiveMemberships(String floorId) async {
    final sb = Supabase.instance.client;
    final seats = await sb.from('seats').select('id').eq('floor_id', floorId);
    if (seats.isEmpty) return false;
    final seatIds = seats.map((s) => s['id'] as String).toList();
    final memberships = await sb.from('memberships')
        .select('id')
        .inFilter('seat_id', seatIds)
        .inFilter('status', ['active', 'trial']);
    return memberships.isNotEmpty;
  }

  Future<bool> _sectionHasActiveMemberships(String sectionId) async {
    final sb = Supabase.instance.client;
    final seats = await sb.from('seats').select('id').eq('section_id', sectionId);
    if (seats.isEmpty) return false;
    final seatIds = seats.map((s) => s['id'] as String).toList();
    final memberships = await sb.from('memberships')
        .select('id')
        .inFilter('seat_id', seatIds)
        .inFilter('status', ['active', 'trial']);
    return memberships.isNotEmpty;
  }

  Future<bool> _seatHasActiveMemberships(String seatId) async {
    final sb = Supabase.instance.client;
    final memberships = await sb.from('memberships')
        .select('id')
        .eq('seat_id', seatId)
        .inFilter('status', ['active', 'trial']);
    return memberships.isNotEmpty;
  }

  T? _firstWhereOrNull<T>(Iterable<T> iterable, bool Function(T) test) {
    for (var element in iterable) {
      if (test(element)) return element;
    }
    return null;
  }

  Future<void> _handleSave() async {
    if (_libraryId == null) {
      _showError('No library configured. Complete Stage 1 first.');
      return;
    }
    if (_floors.isEmpty) {
      _showError('Add at least one floor before saving.');
      return;
    }
    int totalSeats = 0;
    for (final f in _floors) {
      totalSeats += f.floorSeats.length;
      for (final s in f.sections) {
        totalSeats += s.seats.length;
      }
    }
    if (totalSeats == 0) {
      _showError('Add at least one seat before saving.');
      return;
    }

    setState(() => _isSaving = true);
    final sb = Supabase.instance.client;

    try {
      // 1. Fetch all existing floors from DB for this library
      final dbFloors = await sb.from('floors').select('id, name').eq('library_id', _libraryId!);
      final List<String> deletedFloorIds = [];
      final List<String> deletedFloorNames = [];
      final List<Map<String, String>> deletedSections = [];
      final List<Map<String, String>> deletedSeats = [];

      for (final dbF in dbFloors) {
        final fId = dbF['id'] as String;
        final fName = dbF['name'] as String;
        final keptFloor = _firstWhereOrNull(_floors, (f) => f.id == fId);
        
        if (keptFloor == null) {
          deletedFloorIds.add(fId);
          deletedFloorNames.add(fName);
        } else {
          // If floor is kept, check sections
          final dbSections = await sb.from('sections').select('id, name').eq('floor_id', fId);
          for (final dbS in dbSections) {
            final sId = dbS['id'] as String;
            final sName = dbS['name'] as String;
            final keptSection = _firstWhereOrNull(keptFloor.sections, (s) => s.id == sId);
            
            if (keptSection == null) {
              deletedSections.add({'id': sId, 'name': sName});
            } else {
              // If section is kept, check seats in section
              final dbSeatsRaw = await sb.from('seats').select('id, seat_label').eq('section_id', sId);
              for (final dbSeat in dbSeatsRaw) {
                final seatId = dbSeat['id'] as String;
                final seatLabel = dbSeat['seat_label'] as String;
                // Label-aware: a kept seat has multiple shift rows (different
                // ids). Only delete rows whose label is no longer in the layout.
                if (!keptSection.seats.any((s) => s.id == seatId || s.label == seatLabel)) {
                  deletedSeats.add({'id': seatId, 'label': seatLabel});
                }
              }
            }
          }
          // Also check floor-level seats
          final dbFloorSeatsRaw = await sb.from('seats').select('id, seat_label').eq('floor_id', fId).isFilter('section_id', null);
          for (final dbSeat in dbFloorSeatsRaw) {
            final seatId = dbSeat['id'] as String;
            final seatLabel = dbSeat['seat_label'] as String;
            if (!keptFloor.floorSeats.any((s) => s.id == seatId || s.label == seatLabel)) {
              deletedSeats.add({'id': seatId, 'label': seatLabel});
            }
          }
        }
      }

      // 2. Pre-check active memberships for all deletions
      final List<String> activeFloorBlocks = [];
      for (int i = 0; i < deletedFloorIds.length; i++) {
        final hasActive = await _hasActiveMemberships(deletedFloorIds[i]);
        if (hasActive) {
          activeFloorBlocks.add(deletedFloorNames[i]);
        }
      }

      final List<String> activeSectionBlocks = [];
      for (final sec in deletedSections) {
        final hasActive = await _sectionHasActiveMemberships(sec['id']!);
        if (hasActive) {
          activeSectionBlocks.add(sec['name']!);
        }
      }

      final List<String> activeSeatBlocks = [];
      for (final seat in deletedSeats) {
        final hasActive = await _seatHasActiveMemberships(seat['id']!);
        if (hasActive) {
          activeSeatBlocks.add(seat['label']!);
        }
      }

      if (!mounted) return;
      if (activeFloorBlocks.isNotEmpty || activeSectionBlocks.isNotEmpty || activeSeatBlocks.isNotEmpty) {
        setState(() => _isSaving = false);
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: context.palette.surface,
              surfaceTintColor: Colors.transparent,
              title: Text(
                'Cannot Save Layout Changes',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.red),
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'The following elements cannot be deleted because they currently contain active or trial members:',
                      style: GoogleFonts.inter(),
                    ),
                    const SizedBox(height: 12),
                    if (activeFloorBlocks.isNotEmpty) ...[
                      Text('Floors:', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                      ...activeFloorBlocks.map((f) => Text('• $f', style: GoogleFonts.inter())),
                      const SizedBox(height: 8),
                    ],
                    if (activeSectionBlocks.isNotEmpty) ...[
                      Text('Sections:', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                      ...activeSectionBlocks.map((s) => Text('• $s', style: GoogleFonts.inter())),
                      const SizedBox(height: 8),
                    ],
                    if (activeSeatBlocks.isNotEmpty) ...[
                      Text('Seats:', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                      ...activeSeatBlocks.map((s) => Text('• $s', style: GoogleFonts.inter())),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Seats are created PER SHIFT (one row per shift, same label) so a
      // physical seat works across every shift — the multi-shift model the
      // product is built on. Get all shifts (create a default if none).
      var shiftsRaw = await sb.from('shifts').select('id').eq('library_id', _libraryId!);
      List<String> shiftIds;
      if ((shiftsRaw as List).isEmpty) {
        final newShift = await sb.from('shifts').insert({
          'library_id': _libraryId!,
          'name': 'Morning Shift',
          'start_time': '06:00:00',
          'end_time': '14:00:00',
          'price_monthly': 700,
        }).select().single();
        shiftIds = [newShift['id'] as String];
      } else {
        shiftIds = shiftsRaw.map((s) => s['id'] as String).toList();
      }

      // 3. Perform Deletions (since they have been checked and verified to be safe)
      for (final fId in deletedFloorIds) {
        await sb.from('floors').delete().eq('id', fId);
      }
      for (final sec in deletedSections) {
        await sb.from('sections').delete().eq('id', sec['id']!);
      }
      for (final seat in deletedSeats) {
        await sb.from('seats').delete().eq('id', seat['id']!);
      }

      // 4. Perform Updates and Inserts
      for (int fi = 0; fi < _floors.length; fi++) {
        final floor = _floors[fi];
        String floorId;

        if (floor.id != null) {
          // Update existing floor name and order index
          await sb.from('floors').update({
            'name': floor.name,
            'order_index': fi,
          }).eq('id', floor.id!);
          floorId = floor.id!;
        } else {
          // Insert new floor
          final floorRow = await sb.from('floors').insert({
            'library_id': _libraryId!,
            'name': floor.name,
            'order_index': fi,
          }).select().single();
          floorId = floorRow['id'] as String;
          floor.id = floorId;
        }

        // Handle sections
        for (final section in floor.sections) {
          String sectionId;
          if (section.id != null) {
            // Update section name and tag
            await sb.from('sections').update({
              'name': section.name,
              'tag': section.tag,
            }).eq('id', section.id!);
            sectionId = section.id!;
          } else {
            // Insert section
            final secRow = await sb.from('sections').insert({
              'floor_id': floorId,
              'name': section.name,
              'tag': section.tag,
            }).select().single();
            sectionId = secRow['id'] as String;
            section.id = sectionId;
          }

          // Handle seats in section
          for (final seat in section.seats) {
            if (seat.id != null) {
              // Update seat
              await sb.from('seats').update({
                'seat_label': seat.label,
                'status': seat.status,
              }).eq('id', seat.id!);
            } else {
              // Insert new seat: one row per shift (same label) so the seat
              // exists in every shift. status is per-shift independent.
              String? firstSeatId;
              for (final sid in shiftIds) {
                final seatRow = await sb.from('seats').insert({
                  'library_id': _libraryId!,
                  'floor_id': floorId,
                  'section_id': sectionId,
                  'shift_id': sid,
                  'seat_label': seat.label,
                  'status': seat.status,
                }).select().single();
                firstSeatId ??= seatRow['id'] as String;
              }
              seat.id = firstSeatId;
            }
          }
        }

        // Handle floor-level seats (no section)
        for (final seat in floor.floorSeats) {
          if (seat.id != null) {
            // Update seat
            await sb.from('seats').update({
              'seat_label': seat.label,
              'status': seat.status,
            }).eq('id', seat.id!);
          } else {
            // Insert seat: one row per shift (same label).
            String? firstSeatId;
            for (final sid in shiftIds) {
              final seatRow = await sb.from('seats').insert({
                'library_id': _libraryId!,
                'floor_id': floorId,
                'shift_id': sid,
                'seat_label': seat.label,
                'status': seat.status,
              }).select().single();
              firstSeatId ??= seatRow['id'] as String;
            }
            seat.id = firstSeatId;
          }
        }
      }

      if (!mounted) return;

      // Add-library flow: finalise the brand-new library now that its layout
      // is done — flip status to active (so the home onboarding wizard does NOT
      // reappear) and show the "created" popup mentioning inherited settings.
      if (_isNewLibrary && _libraryId != null) {
        try {
          await sb.from('libraries').update({'status': 'active'}).eq('id', _libraryId!);
        } catch (e) {
          debugPrint('finalise new library status failed: $e');
        }
        if (!mounted) return;
        setState(() => _isSaving = false);
        await _showNewLibraryCreatedDialog();
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      _showSuccess('Layout saved successfully ✓');
      Navigator.pop(context, true);
    } catch (e) {
      _showError('Error saving layout: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showNewLibraryCreatedDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF16A34A)),
            const SizedBox(width: 8),
            Text('Library created',
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
          ],
        ),
        content: Text(
          _sourceCopied
              ? 'Your new library is ready! Its shifts, plans, amenities, add-ons '
                  'and rules have been copied from your primary library. To change '
                  'any of them, go to Profile → Library Management and pick this '
                  'library.'
              : 'Your new library is ready! Set up its shifts, plans and other '
                  'details anytime from Profile → Library Management.',
          style: GoogleFonts.inter(
              fontSize: 13.5, height: 1.5, color: context.palette.textSecondary),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00)),
            onPressed: () => Navigator.pop(ctx),
            child: Text('Done',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _orange,
      body: SafeArea(
        top: true,
        child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _orange,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('Layout Setup', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          centerTitle: true,
        ),
        body: _isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(_orange)))
          : Column(children: [
              // Floor tabs
              _buildFloorTabs(),
              // Active floor content
              Expanded(
                child: _floors.isEmpty
                    ? _buildEmptyFloorState()
                    : _buildActiveFloorContent(_floors[_activeFloorIndex]),
              ),
              // Save button
              _buildSaveButton(),
            ]),
      ),
      ),
    );
  }

  Widget _buildEmptyFloorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: GestureDetector(
          onTap: _showAddFloorSheet,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _orange,
                width: 1.5,
                style: BorderStyle.solid,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.layers_outlined, size: 48, color: _orange),
                const SizedBox(height: 16),
                Text(
                  'No Floors Added Yet',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap here to add your first floor and configure layout',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: context.palette.textMuted,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3ED),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, size: 16, color: _orange),
                      const SizedBox(width: 4),
                      Text(
                        'Add Floor',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineAddContentPanel(FloorModel floor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _creationMode = 'section'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _creationMode == 'section' ? _orange : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Add Section',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _creationMode == 'section' ? Colors.white : _grey,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _creationMode = 'direct'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _creationMode == 'direct' ? _orange : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Add Direct Seat',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _creationMode == 'direct' ? Colors.white : _grey,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SeatGenerationInlineWidget(
          key: ValueKey('setup_inline_${_creationMode}_${floor.id ?? "new"}'),
          creationMode: _creationMode,
          onSave: (sectionName, seatLabels) async {
            final Set<String> existingLabels = {};
            for (final sec in floor.sections) {
              for (final seat in sec.seats) {
                existingLabels.add(seat.label.toUpperCase().trim());
              }
            }
            for (final seat in floor.floorSeats) {
              existingLabels.add(seat.label.toUpperCase().trim());
            }

            final List<String> duplicates = [];
            for (final label in seatLabels) {
              if (existingLabels.contains(label.toUpperCase().trim())) {
                duplicates.add(label);
              }
            }

            if (duplicates.isNotEmpty) {
              throw Exception('Duplicate seat labels found on this floor: ${duplicates.join(", ")}');
            }

            if (_creationMode == 'section') {
              final secName = sectionName!;
              final sectionExists = floor.sections.any(
                (sec) => sec.name.toLowerCase().trim() == secName.toLowerCase().trim()
              );
              if (sectionExists) {
                throw Exception('Section name "$secName" already exists on this floor.');
              }

              final newSection = SectionModel(
                name: secName,
                tag: 'general',
                seats: seatLabels.map((l) => SeatModel(label: l)).toList(),
              );

              setState(() {
                floor.sections.add(newSection);
              });
              _showSuccess('Section "$secName" and ${seatLabels.length} seats added! ✓');
            } else {
              setState(() {
                for (final l in seatLabels) {
                  floor.floorSeats.add(SeatModel(label: l));
                }
              });
              _showSuccess('${seatLabels.length} seats added directly to floor! ✓');
            }
          },
          onCancel: () {
            setState(() {
              _creationMode = 'section';
            });
          },
        ),
      ],
    );
  }

  Widget _buildFloorTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (int i = 0; i < _floors.length; i++)
                  GestureDetector(
                    onTap: () => setState(() { _activeFloorIndex = i; _floorSeatsPage = 0; }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _activeFloorIndex == i ? _orange : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _activeFloorIndex == i ? _orange : const Color(0xFFE5E7EB)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          _floors[i].name,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _activeFloorIndex == i ? Colors.white : _grey,
                          ),
                        ),
                        if (_activeFloorIndex == i) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.circle, size: 6, color: Colors.white),
                        ],
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _showAddFloorSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3ED),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _orange, width: 1.2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, size: 14, color: _orange),
                  const SizedBox(width: 4),
                  Text(
                    'Floor',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _orange,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFloorContent(FloorModel floor) {
    final totalSectionSeats = floor.sections.fold<int>(0, (sum, s) => sum + s.seats.length);
    final totalSeats = totalSectionSeats + floor.floorSeats.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Floor header card
        Container(
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF1F5F9)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.layers, color: _orange, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(floor.name, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: _dark)),
                Text('$totalSeats seat${totalSeats == 1 ? '' : 's'} total', style: GoogleFonts.inter(fontSize: 12, color: _grey)),
              ]),
            ),
            // Custom modern three-dot popup menu
            IconButton(
              icon: Icon(Icons.more_vert, color: _grey),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => Dialog(
                    backgroundColor: context.palette.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text(
                              'Floor Options',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _dark,
                              ),
                            ),
                          ),
                          const Divider(),
                          ListTile(
                            leading: const Icon(Icons.edit_outlined, color: _orange),
                            title: Text('Rename Floor', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                            onTap: () {
                              Navigator.pop(ctx);
                              _showRenameFloorSheet(floor);
                            },
                          ),
                          ListTile(
                            leading: Icon(
                              Icons.delete_outline,
                              color: (floor.sections.isEmpty && floor.floorSeats.isEmpty) ? Colors.red : _grey,
                            ),
                            title: Text(
                              'Delete Floor',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w500,
                                color: (floor.sections.isEmpty && floor.floorSeats.isEmpty) ? Colors.red : _grey,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              if (floor.sections.isEmpty && floor.floorSeats.isEmpty) {
                                _deleteFloor(_activeFloorIndex);
                              } else {
                                _showError('Remove all sections and seats before deleting this floor.');
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // Inline Add Content Card
        _buildInlineAddContentPanel(floor),
        const SizedBox(height: 24),

        // Sections
        if (floor.sections.isNotEmpty) ...[
          Text('Sections', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: _grey)),
          const SizedBox(height: 10),
          for (final section in floor.sections) ...[
            _buildSectionCard(floor, section),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
        ],

        // Floor-level seats section
        if (floor.floorSeats.isNotEmpty) ...[
          _buildFloorLevelSeats(floor),
          const SizedBox(height: 12),
        ],

        if (floor.sections.isEmpty && floor.floorSeats.isEmpty) ...[
          const SizedBox(height: 20),
          Center(
            child: Text(
              'This floor has no sections or seats. Use the card above to add some!',
              style: GoogleFonts.inter(fontSize: 12, color: _grey, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildFloorSeatGenerator(FloorModel floor) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      child: SeatGenerationInlineWidget(
        key: ValueKey('setup_inline_floor_direct_${floor.id ?? "new"}'),
        creationMode: 'direct',
        onSave: (sectionName, seatLabels) async {
          // Validate duplicates
          final Set<String> existingLabels = {};
          for (final sec in floor.sections) {
            for (final seat in sec.seats) {
              existingLabels.add(seat.label.toUpperCase().trim());
            }
          }
          for (final seat in floor.floorSeats) {
            existingLabels.add(seat.label.toUpperCase().trim());
          }

          final List<String> duplicates = [];
          for (final label in seatLabels) {
            if (existingLabels.contains(label.toUpperCase().trim())) {
              duplicates.add(label);
            }
          }

          if (duplicates.isNotEmpty) {
            throw Exception('Duplicate seat labels found on this floor: ${duplicates.join(", ")}');
          }

          setState(() {
            for (final l in seatLabels) {
              floor.floorSeats.add(SeatModel(label: l));
            }
            _isAddingFloorSeat = false;
          });
          _showSuccess('${seatLabels.length} seats added directly to floor! ✓');
        },
        onCancel: () {
          setState(() {
            _isAddingFloorSeat = false;
          });
        },
      ),
    );
  }

  Widget _buildFloorLevelSeats(FloorModel floor) {
    final seats = floor.floorSeats;
    const pageSize = 30;
    final totalPages = (seats.length / pageSize).ceil();
    final startIndex = _floorSeatsPage * pageSize;
    final endIndex = (startIndex + pageSize).clamp(0, seats.length);
    final pageSeats = seats.isEmpty ? <SeatModel>[] : seats.sublist(startIndex, endIndex);

    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(floor.addSeatsDirectly ? 'Floor Seats' : 'Seats Directly on Floor', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: _dark)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
            child: Text('${seats.length}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _grey)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(floor.addSeatsDirectly ? 'Create and manage seats directly on this floor' : 'Optional — seats without any section', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9CA3AF))),
        const SizedBox(height: 12),
        if (seats.isEmpty) ...[
          if (_isAddingFloorSeat)
            _buildFloorSeatGenerator(floor)
          else
            GestureDetector(
              onTap: () => setState(() => _isAddingFloorSeat = true),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7F0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _orange.withValues(alpha: 0.4)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.add, size: 16, color: _orange),
                  const SizedBox(width: 6),
                  Text('Add Seat on Floor', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _orange)),
                ]),
              ),
            ),
        ] else ...[
          _buildSeatGrid(pageSeats, null, floor),
          const SizedBox(height: 10),
          if (_isAddingFloorSeat)
            _buildFloorSeatGenerator(floor)
          else
            GestureDetector(
              onTap: () => setState(() => _isAddingFloorSeat = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7F0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _orange.withValues(alpha: 0.4)),
                ),
                child: Text('+ Add More Seats', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _orange)),
              ),
            ),
          if (totalPages > 1) ...[
            const SizedBox(height: 12),
            Row(children: [
              GestureDetector(
                onTap: _floorSeatsPage > 0 ? () => setState(() => _floorSeatsPage--) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: _floorSeatsPage > 0 ? _orange : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('◀ Prev $pageSize',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
              const Spacer(),
              Text('Page ${_floorSeatsPage + 1}/$totalPages', style: GoogleFonts.inter(fontSize: 11, color: _grey)),
              const Spacer(),
              GestureDetector(
                onTap: _floorSeatsPage < totalPages - 1 ? () => setState(() => _floorSeatsPage++) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: _floorSeatsPage < totalPages - 1 ? _orange : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Next $pageSize ▶',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ]),
          ],
        ],
      ]),
    );
  }

  Widget _buildSeatGrid(List<SeatModel> seats, SectionModel? section, FloorModel floor) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
        childAspectRatio: 52 / 44,
      ),
      itemCount: seats.length,
      itemBuilder: (_, i) {
        final seat = seats[i];
        return GestureDetector(
          onTap: () => _showSeatActionSheet(seat, section: section, floor: section == null ? floor : null),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _seatColor(seat.status),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              seat.label,
              style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionCard(FloorModel floor, SectionModel section) {
    const pageSize = 30;
    return _SectionCardWidget(
      section: section,
      floor: floor,
      pageSize: pageSize,
      orange: _orange,
      grey: _grey,
      dark: _dark,
      tagLabel: _tagLabel,
      seatColor: _seatColor,
      onRename: () => _showRenameSectionSheet(section),
      onDelete: () => _deleteSection(floor, section),
      onSeatsUpdated: () => setState(() {}),
      onSeatTap: (seat) => _showSeatActionSheet(seat, section: section),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: ElevatedButton(
        onPressed: (_isSaving || _isLoading) ? null : _handleSave,
        style: ElevatedButton.styleFrom(
          backgroundColor: _orange,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size(double.infinity, 52),
        ),
        child: _isSaving
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
            : Text('Save Layout', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section card as a separate StatefulWidget to handle per-section pagination
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCardWidget extends StatefulWidget {
  final SectionModel section;
  final FloorModel floor;
  final int pageSize;
  final Color orange, grey, dark;
  final String Function(String) tagLabel;
  final Color Function(String) seatColor;
  final VoidCallback onRename, onDelete, onSeatsUpdated;
  final void Function(SeatModel) onSeatTap;

  const _SectionCardWidget({
    required this.section,
    required this.floor,
    required this.pageSize,
    required this.orange,
    required this.grey,
    required this.dark,
    required this.tagLabel,
    required this.seatColor,
    required this.onRename,
    required this.onDelete,
    required this.onSeatsUpdated,
    required this.onSeatTap,
  });

  @override
  State<_SectionCardWidget> createState() => _SectionCardWidgetState();
}

class _SectionCardWidgetState extends State<_SectionCardWidget> {
  int _page = 0;
  bool _isAddingSeat = false;
  String _mode = 'bulk'; // 'bulk' or 'single'

  late TextEditingController _inlinePrefixCtrl;
  late TextEditingController _inlineStartCtrl;
  late TextEditingController _inlineEndCtrl;
  late TextEditingController _inlineSingleCtrl;

  @override
  void initState() {
    super.initState();
    final name = widget.section.name;
    final trimmed = name.trim();
    final words = trimmed.isEmpty ? <String>[] : trimmed.split(RegExp(r'\s+'));
    String defaultPrefix = '';
    if (words.isNotEmpty) {
      if (words.length == 1) {
        final w = words[0];
        defaultPrefix = w.substring(0, w.length.clamp(1, 3)).toUpperCase();
      } else {
        defaultPrefix = words.take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
      }
    }

    _inlinePrefixCtrl = TextEditingController(text: defaultPrefix);
    _inlineStartCtrl = TextEditingController();
    _inlineEndCtrl = TextEditingController();
    _inlineSingleCtrl = TextEditingController();

    _inlinePrefixCtrl.addListener(_updateLocalPreview);
    _inlineStartCtrl.addListener(_updateLocalPreview);
    _inlineEndCtrl.addListener(_updateLocalPreview);
  }

  @override
  void dispose() {
    _inlinePrefixCtrl.dispose();
    _inlineStartCtrl.dispose();
    _inlineEndCtrl.dispose();
    _inlineSingleCtrl.dispose();
    super.dispose();
  }

  void _updateLocalPreview() {
    if (mounted) setState(() {});
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showSuccessSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _getInlinePreviewText() {
    final prefix = _inlinePrefixCtrl.text.trim();
    final int? start = int.tryParse(_inlineStartCtrl.text.trim());
    final int? end = int.tryParse(_inlineEndCtrl.text.trim());

    if (start == null || end == null || start > end || end - start > 100) {
      return 'Invalid range (max 100 seats)';
    }

    final List<String> samples = [];
    for (int i = start; i <= end; i++) {
      final label = prefix.isEmpty ? '$i' : '$prefix-$i';
      samples.add(label);
      if (samples.length >= 3) break;
    }

    final total = end - start + 1;
    if (total <= 3) {
      return 'Will generate: ${samples.join(", ")}';
    } else {
      final lastLabel = prefix.isEmpty ? '$end' : '$prefix-$end';
      return 'Will generate: ${samples.join(", ")}, ..., $lastLabel ($total seats total)';
    }
  }

  void _createSeats() {
    final List<String> newLabels = [];
    if (_mode == 'bulk') {
      final prefix = _inlinePrefixCtrl.text.trim();
      final int? start = int.tryParse(_inlineStartCtrl.text.trim());
      final int? end = int.tryParse(_inlineEndCtrl.text.trim());

      if (start == null || end == null) {
        _showErrorSnackBar('Please enter valid start and end numbers.');
        return;
      }
      if (start > end) {
        _showErrorSnackBar('Start number cannot be greater than end number.');
        return;
      }
      if (end - start > 100) {
        _showErrorSnackBar('Bulk generation is limited to 100 seats at a time.');
        return;
      }

      for (int i = start; i <= end; i++) {
        final label = prefix.isEmpty ? '$i' : '$prefix-$i';
        newLabels.add(label);
      }
    } else {
      final text = _inlineSingleCtrl.text.trim();
      if (text.isEmpty) {
        _showErrorSnackBar('Please enter at least one seat label.');
        return;
      }
      final parts = text.split(',');
      for (final p in parts) {
        final label = p.trim();
        if (label.isNotEmpty) {
          final prefix = _inlinePrefixCtrl.text.trim();
          final fullLabel = prefix.isEmpty ? label : '$prefix-$label';
          newLabels.add(fullLabel);
        }
      }
    }

    if (newLabels.isEmpty) {
      _showErrorSnackBar('No seat labels generated.');
      return;
    }

    final Set<String> existingLabels = {};
    for (final sec in widget.floor.sections) {
      for (final seat in sec.seats) {
        existingLabels.add(seat.label.toUpperCase().trim());
      }
    }
    for (final seat in widget.floor.floorSeats) {
      existingLabels.add(seat.label.toUpperCase().trim());
    }

    final List<String> duplicates = [];
    for (final label in newLabels) {
      if (existingLabels.contains(label.toUpperCase().trim())) {
        duplicates.add(label);
      }
    }

    if (duplicates.isNotEmpty) {
      _showErrorSnackBar('Duplicate seat labels found on this floor: ${duplicates.join(", ")}');
      return;
    }

    setState(() {
      for (final label in newLabels) {
        widget.section.seats.add(SeatModel(label: label));
      }
      _isAddingSeat = false;
      _inlineStartCtrl.clear();
      _inlineEndCtrl.clear();
      _inlineSingleCtrl.clear();
    });

    widget.onSeatsUpdated();
    _showSuccessSnackBar('${newLabels.length} seats added! ✓');
  }

  Widget _buildInlineSeatGenerator() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add Seat / Generator',
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: widget.dark),
          ),
          const SizedBox(height: 12),
          Text('Seat Prefix (Optional)', style: GoogleFonts.inter(fontSize: 11, color: widget.grey, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          SizedBox(
            height: 44,
            child: TextField(
              controller: _inlinePrefixCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. A',
                hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: widget.orange)),
              ),
              style: GoogleFonts.inter(fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _mode = 'bulk'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _mode == 'bulk' ? widget.orange : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Bulk Range',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: _mode == 'bulk' ? FontWeight.bold : FontWeight.normal,
                        color: _mode == 'bulk' ? widget.orange : widget.grey,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _mode = 'single'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _mode == 'single' ? widget.orange : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Single Seats',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: _mode == 'single' ? FontWeight.bold : FontWeight.normal,
                        color: _mode == 'single' ? widget.orange : widget.grey,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_mode == 'bulk') ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('From', style: GoogleFonts.inter(fontSize: 11, color: widget.grey)),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 44,
                        child: TextField(
                          controller: _inlineStartCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            hintText: 'e.g. 1',
                            hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          style: GoogleFonts.inter(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('To', style: GoogleFonts.inter(fontSize: 11, color: widget.grey)),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 44,
                        child: TextField(
                          controller: _inlineEndCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            hintText: 'e.g. 10',
                            hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          style: GoogleFonts.inter(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3ED),
                borderRadius: BorderRadius.circular(6),
              ),
              width: double.infinity,
              child: Text(
                _getInlinePreviewText(),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFFD97706),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ] else ...[
            Text('Comma-separated numbers', style: GoogleFonts.inter(fontSize: 11, color: widget.grey)),
            const SizedBox(height: 4),
            TextField(
              controller: _inlineSingleCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. 1, 2, 5A',
                hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: widget.orange)),
              ),
              style: GoogleFonts.inter(fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _isAddingSeat = false;
                    _inlineStartCtrl.clear();
                    _inlineEndCtrl.clear();
                    _inlineSingleCtrl.clear();
                  });
                },
                child: Text('Cancel', style: GoogleFonts.inter(color: widget.grey, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _createSeats,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: Text('Create seats', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final seats = section.seats;
    final totalPages = (seats.length / widget.pageSize).ceil();
    final startIndex = _page * widget.pageSize;
    final endIndex = (startIndex + widget.pageSize).clamp(0, seats.length);
    final pageSeats = seats.sublist(startIndex, endIndex);

    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(section.name, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: widget.dark)),
              Text('${widget.tagLabel(section.tag)} · ${seats.length} seats',
                  style: GoogleFonts.inter(fontSize: 11, color: widget.grey)),
            ]),
          ),
          IconButton(
            icon: Icon(Icons.more_vert, color: widget.grey, size: 20),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => Dialog(
                  backgroundColor: context.palette.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text(
                            'Section Options',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: widget.dark,
                            ),
                          ),
                        ),
                        const Divider(),
                        ListTile(
                          leading: Icon(Icons.edit_outlined, color: widget.orange),
                          title: Text('Rename', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                          onTap: () {
                            Navigator.pop(ctx);
                            widget.onRename();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.delete_outline, color: Colors.red),
                          title: Text('Delete', style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: Colors.red)),
                          onTap: () {
                            Navigator.pop(ctx);
                            widget.onDelete();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ]),
        const SizedBox(height: 12),

        // Seat grid
        if (seats.isEmpty) ...[
          if (_isAddingSeat)
            _buildInlineSeatGenerator()
          else
            GestureDetector(
              onTap: () => setState(() => _isAddingSeat = true),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7F0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: widget.orange.withValues(alpha: 0.4)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add, size: 16, color: widget.orange),
                  const SizedBox(width: 6),
                  Text('Add First Seat', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: widget.orange)),
                ]),
              ),
            ),
        ] else ...[
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6, crossAxisSpacing: 5, mainAxisSpacing: 5, childAspectRatio: 52 / 44,
            ),
            itemCount: pageSeats.length + 1, // +1 for add seat tile
            itemBuilder: (_, i) {
              if (i == pageSeats.length) {
                return GestureDetector(
                  onTap: () => setState(() => _isAddingSeat = true),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7F0),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: widget.orange.withValues(alpha: 0.5), style: BorderStyle.solid),
                    ),
                    child: Icon(Icons.add, size: 18, color: widget.orange),
                  ),
                );
              }
              final seat = pageSeats[i];
              return GestureDetector(
                onTap: () => widget.onSeatTap(seat),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.seatColor(seat.status),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    seat.label,
                    style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
          if (_isAddingSeat) _buildInlineSeatGenerator(),
          if (totalPages > 1) ...[
            const SizedBox(height: 10),
            Row(children: [
              GestureDetector(
                onTap: _page > 0 ? () => setState(() => _page--) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: _page > 0 ? widget.orange : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('◀ Prev ${widget.pageSize}',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
              const Spacer(),
              Text('Page ${_page + 1}/$totalPages', style: GoogleFonts.inter(fontSize: 11, color: widget.grey)),
              const Spacer(),
              GestureDetector(
                onTap: _page < totalPages - 1 ? () => setState(() => _page++) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: _page < totalPages - 1 ? widget.orange : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Next ${widget.pageSize} ▶',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ]),
          ],
        ],
      ]),
    );
  }
}
