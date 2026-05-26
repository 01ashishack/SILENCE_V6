import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data models (local, not persisted until Save is tapped)
// ─────────────────────────────────────────────────────────────────────────────

class FloorModel {
  String? id; // null if not yet in DB
  String name;
  List<SectionModel> sections;
  List<SeatModel> floorSeats; // seats without a section

  FloorModel({this.id, required this.name, List<SectionModel>? sections, List<SeatModel>? floorSeats})
      : sections = sections ?? [],
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
  static const _bg = Color(0xFFFBF5EE);
  static const _dark = Color(0xFF1A1A2E);
  static const _grey = Color(0xFF6B7280);

  bool _isLoading = true;
  bool _isSaving = false;
  String? _libraryId;

  List<FloorModel> _floors = [];
  int _activeFloorIndex = 0;

  // ── init ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;
    if (user == null) { setState(() => _isLoading = false); return; }

    try {
      final libRow = await sb.from('libraries').select('id').eq('owner_id', user.id).maybeSingle();
      if (libRow == null) { setState(() => _isLoading = false); return; }
      _libraryId = libRow['id'] as String;

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
          final seats = (seatsRaw as List).map((seat) => SeatModel(
            id: seat['id'] as String,
            label: seat['seat_label'] as String,
            status: (seat['status'] as String?) ?? 'vacant',
          )).toList();
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
        final floorSeats = (floorSeatsRaw as List).map((seat) => SeatModel(
          id: seat['id'] as String,
          label: seat['seat_label'] as String,
          status: (seat['status'] as String?) ?? 'vacant',
        )).toList();

        floors.add(FloorModel(id: floorId, name: f['name'] as String, sections: sections, floorSeats: floorSeats));
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
      backgroundColor: _orange,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── floor operations ──────────────────────────────────────────────────────

  void _showAddFloorSheet() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add Floor', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _dark)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'e.g. Ground Floor, First Floor...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _orange)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final name = ctrl.text.trim();
                if (name.isEmpty) return;
                setState(() {
                  _floors.add(FloorModel(name: name));
                  _activeFloorIndex = _floors.length - 1;
                });
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text('Add Floor', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    );
  }

  void _showFloorMenu(FloorModel floor, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.edit_outlined, color: _orange),
          title: Text('Rename Floor', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
          onTap: () { Navigator.pop(ctx); _showRenameFloorSheet(floor); },
        ),
        ListTile(
          leading: Icon(Icons.delete_outline, color: (floor.sections.isEmpty && floor.floorSeats.isEmpty) ? Colors.red : _grey),
          title: Text('Delete Floor',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w500,
              color: (floor.sections.isEmpty && floor.floorSeats.isEmpty) ? Colors.red : _grey,
            ),
          ),
          onTap: (floor.sections.isEmpty && floor.floorSeats.isEmpty)
              ? () { Navigator.pop(ctx); _deleteFloor(index); }
              : () { Navigator.pop(ctx); _showError('Remove all sections and seats before deleting this floor.'); },
        ),
        const SizedBox(height: 16),
      ]),
    );
  }

  void _showRenameFloorSheet(FloorModel floor) {
    final ctrl = TextEditingController(text: floor.name);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
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
    });
  }

  // ── section operations ────────────────────────────────────────────────────

  void _showAddSectionSheet(FloorModel floor) {
    final nameCtrl = TextEditingController();
    String selectedTag = 'general';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) => Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Add Section', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _dark)),
            const SizedBox(height: 16),
            Text('Section Name', style: GoogleFonts.inter(fontSize: 12, color: _grey, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'e.g. General Study, Girls Section...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _orange)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Section Type', style: GoogleFonts.inter(fontSize: 12, color: _grey, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                for (final t in ['general', 'boys', 'girls', 'premium'])
                  GestureDetector(
                    onTap: () => setS(() => selectedTag = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: selectedTag == t ? _orange : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: selectedTag == t ? _orange : const Color(0xFFE5E7EB)),
                      ),
                      child: Text(
                        _tagLabel(t),
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: selectedTag == t ? Colors.white : _grey),
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
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  setState(() => floor.sections.add(SectionModel(name: name, tag: selectedTag)));
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _orange, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Add Section', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showRenameSectionSheet(SectionModel section) {
    final ctrl = TextEditingController(text: section.name);
    String selectedTag = section.tag;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
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

  // ── seat operations ───────────────────────────────────────────────────────

  void _showAddSeatSheet({SectionModel? section, FloorModel? floor}) {
    // section XOR floor must be non-null
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add Seat', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _dark)),
          const SizedBox(height: 8),
          Text(
            section != null ? 'In section: ${section.name}' : 'Directly on floor (no section)',
            style: GoogleFonts.inter(fontSize: 13, color: _grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Seat label, e.g. G-A-01',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _orange)),
            ),
          ),
          const SizedBox(height: 8),
          _buildBulkAddRow(section: section, floor: floor, closeSheet: () => Navigator.pop(ctx)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final label = ctrl.text.trim();
                if (label.isEmpty) return;
                setState(() {
                  if (section != null) section.seats.add(SeatModel(label: label));
                  else floor!.floorSeats.add(SeatModel(label: label));
                });
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text('Add Seat', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildBulkAddRow({SectionModel? section, FloorModel? floor, required VoidCallback closeSheet}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _orange.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Or bulk-add seats:', style: GoogleFonts.inter(fontSize: 12, color: _orange, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          for (final n in [5, 10, 20, 30])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    final prefix = section != null ? _sectionPrefix(section.name) : 'FL';
                    final existingCount = section != null ? section.seats.length : floor!.floorSeats.length;
                    for (int i = 1; i <= n; i++) {
                      final label = '$prefix-${(existingCount + i).toString().padLeft(2, '0')}';
                      if (section != null) section.seats.add(SeatModel(label: label));
                      else floor!.floorSeats.add(SeatModel(label: label));
                    }
                  });
                  closeSheet();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _orange),
                  ),
                  child: Text('+$n', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _orange)),
                ),
              ),
            ),
        ]),
      ]),
    );
  }

  void _showSeatActionSheet(SeatModel seat, {SectionModel? section, FloorModel? floor}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
                if (section != null) section.seats.remove(seat);
                else floor!.floorSeats.remove(seat);
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

  String _sectionPrefix(String name) {
    // derive short prefix from name, e.g. "General Study" → "GS"
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length == 1) return words[0].substring(0, name.length.clamp(1, 3)).toUpperCase();
    return words.take(2).map((w) => w[0].toUpperCase()).join();
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

  Future<void> _handleSave() async {
    if (_libraryId == null) {
      _showError('No library configured. Complete Stage 1 first.');
      return;
    }
    if (_floors.isEmpty) {
      _showError('Add at least one floor before saving.');
      return;
    }

    setState(() => _isSaving = true);
    final sb = Supabase.instance.client;

    try {
      // Delete all existing floors (cascade removes sections + seats)
      await sb.from('floors').delete().eq('library_id', _libraryId!);

      // Get or create a default shift to attach seats to
      var shiftsRaw = await sb.from('shifts').select('id').eq('library_id', _libraryId!);
      String shiftId;
      if ((shiftsRaw as List).isEmpty) {
        final newShift = await sb.from('shifts').insert({
          'library_id': _libraryId!,
          'name': 'Morning Shift',
          'start_time': '06:00:00',
          'end_time': '14:00:00',
          'price_monthly': 700,
        }).select().single();
        shiftId = newShift['id'] as String;
      } else {
        shiftId = shiftsRaw.first['id'] as String;
      }

      for (int fi = 0; fi < _floors.length; fi++) {
        final floor = _floors[fi];
        final floorRow = await sb.from('floors').insert({
          'library_id': _libraryId!,
          'name': floor.name,
          'order_index': fi,
        }).select().single();
        final floorId = floorRow['id'] as String;
        floor.id = floorId;

        // sections
        for (final section in floor.sections) {
          final secRow = await sb.from('sections').insert({
            'floor_id': floorId,
            'name': section.name,
            'tag': section.tag,
          }).select().single();
          final sectionId = secRow['id'] as String;
          section.id = sectionId;

          // seats in section
          if (section.seats.isNotEmpty) {
            await sb.from('seats').insert(section.seats.map((seat) => {
              'library_id': _libraryId!,
              'floor_id': floorId,
              'section_id': sectionId,
              'shift_id': shiftId,
              'seat_label': seat.label,
              'status': seat.status,
            }).toList());
          }
        }

        // floor-level seats (no section)
        if (floor.floorSeats.isNotEmpty) {
          await sb.from('seats').insert(floor.floorSeats.map((seat) => {
            'library_id': _libraryId!,
            'floor_id': floorId,
            'shift_id': shiftId,
            'seat_label': seat.label,
            'status': seat.status,
          }).toList());
        }
      }

      _showSuccess('Layout saved successfully ✓');
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _showError('Error saving layout: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.layers_outlined, size: 64, color: Color(0xFFD1D5DB)),
        const SizedBox(height: 16),
        Text('No floors added yet.', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: _grey)),
        const SizedBox(height: 8),
        Text('Tap "+ Add Floor" above to start.', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF9CA3AF))),
      ]),
    );
  }

  Widget _buildFloorTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          // + Add Floor button (dashed orange)
          GestureDetector(
            onTap: _showAddFloorSheet,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _orange, style: BorderStyle.solid, width: 1.5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add, size: 16, color: _orange),
                const SizedBox(width: 4),
                Text('Add Floor', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _orange)),
              ]),
            ),
          ),
          // Floor pills
          for (int i = 0; i < _floors.length; i++)
            GestureDetector(
              onTap: () => setState(() => _activeFloorIndex = i),
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
    );
  }

  Widget _buildActiveFloorContent(FloorModel floor) {
    final totalSectionSeats = floor.sections.fold<int>(0, (sum, s) => sum + s.seats.length);
    final totalSeats = totalSectionSeats + floor.floorSeats.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Floor header
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(floor.name, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _dark)),
              Text('$totalSeats seat${totalSeats == 1 ? '' : 's'} total', style: GoogleFonts.inter(fontSize: 12, color: _grey)),
            ]),
          ),
          // Three-dot menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: _grey),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'rename') _showRenameFloorSheet(floor);
              if (val == 'delete') _showFloorMenu(floor, _activeFloorIndex);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Text('Rename Floor', style: GoogleFonts.inter())),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Delete Floor',
                  style: GoogleFonts.inter(color: (floor.sections.isEmpty && floor.floorSeats.isEmpty) ? Colors.red : _grey),
                ),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 16),

        // Sections heading
        Text('Sections (Optional)', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: _grey)),
        const SizedBox(height: 10),

        // Sections
        if (floor.sections.isEmpty)
          _buildEmptySectionState(floor)
        else
          for (final section in floor.sections) ...[
            _buildSectionCard(floor, section),
            const SizedBox(height: 12),
          ],

        // Add section button
        if (floor.sections.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: () => _showAddSectionSheet(floor),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _orange, style: BorderStyle.solid),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.add, size: 18, color: _orange),
                  const SizedBox(width: 6),
                  Text('Add Another Section', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: _orange, fontSize: 13)),
                ]),
              ),
            ),
          ),

        const SizedBox(height: 12),

        // Floor-level seats section
        _buildFloorLevelSeats(floor),
      ]),
    );
  }

  Widget _buildEmptySectionState(FloorModel floor) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(children: [
        const Text('📦', style: TextStyle(fontSize: 32)),
        const SizedBox(height: 8),
        Text('No sections added.', style: GoogleFonts.inter(fontSize: 14, color: _grey, fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => _showAddSectionSheet(floor),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _orange),
            ),
            child: Text('+ Add First Section', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: _orange, fontSize: 13)),
          ),
        ),
      ]),
    );
  }

  Widget _buildSectionCard(FloorModel floor, SectionModel section) {
    const _pageSize = 30;
    // each section holds its own page index in a map
    // We use a simple local variable per build — for interactivity, use ValueNotifier
    return _SectionCardWidget(
      section: section,
      floor: floor,
      pageSize: _pageSize,
      orange: _orange,
      grey: _grey,
      dark: _dark,
      tagLabel: _tagLabel,
      seatColor: _seatColor,
      onRename: () => _showRenameSectionSheet(section),
      onDelete: () => _deleteSection(floor, section),
      onAddSeat: () => _showAddSeatSheet(section: section),
      onSeatTap: (seat) => _showSeatActionSheet(seat, section: section),
    );
  }

  Widget _buildFloorLevelSeats(FloorModel floor) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Seats Directly on Floor', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: _dark)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
            child: Text('${floor.floorSeats.length}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _grey)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Optional — seats without any section', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9CA3AF))),
        const SizedBox(height: 12),
        if (floor.floorSeats.isEmpty)
          GestureDetector(
            onTap: () => _showAddSeatSheet(floor: floor),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7F0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _orange.withOpacity(0.4)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.add, size: 16, color: _orange),
                const SizedBox(width: 6),
                Text('Add Seat on Floor', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _orange)),
              ]),
            ),
          )
        else ...[
          _buildSeatGrid(floor.floorSeats, null, floor),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _showAddSeatSheet(floor: floor),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7F0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _orange.withOpacity(0.4)),
              ),
              child: Text('+ Add More Seats', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _orange)),
            ),
          ),
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
  final VoidCallback onRename, onDelete, onAddSeat;
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
    required this.onAddSeat,
    required this.onSeatTap,
  });

  @override
  State<_SectionCardWidget> createState() => _SectionCardWidgetState();
}

class _SectionCardWidgetState extends State<_SectionCardWidget> {
  int _page = 0;

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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Section header
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(section.name, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: widget.dark)),
              Text('${widget.tagLabel(section.tag)} · ${seats.length} seats',
                  style: GoogleFonts.inter(fontSize: 11, color: widget.grey)),
            ]),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: widget.grey, size: 20),
            onSelected: (value) {
              if (value == 'rename') {
                widget.onRename();
              } else if (value == 'delete') {
                widget.onDelete();
              }
            },
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, color: widget.orange, size: 18),
                    const SizedBox(width: 8),
                    Text('Rename', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: widget.dark)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Text('Delete', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 12),

        // Seat grid
        if (seats.isEmpty)
          GestureDetector(
            onTap: widget.onAddSeat,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7F0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: widget.orange.withOpacity(0.4)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add, size: 16, color: widget.orange),
                const SizedBox(width: 6),
                Text('Add First Seat', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: widget.orange)),
              ]),
            ),
          )
        else ...[
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6, crossAxisSpacing: 5, mainAxisSpacing: 5, childAspectRatio: 52 / 44,
            ),
            itemCount: pageSeats.length + 1, // +1 for add seat tile
            itemBuilder: (_, i) {
              if (i == pageSeats.length) {
                // dashed add-seat tile
                return GestureDetector(
                  onTap: widget.onAddSeat,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7F0),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: widget.orange.withOpacity(0.5), style: BorderStyle.solid),
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
          // Pagination
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
