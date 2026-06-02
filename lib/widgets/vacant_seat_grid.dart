import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class VacantSeatGrid extends StatefulWidget {
  final String libraryId;
  final String shiftId;
  final String? selectedSeatId;
  final String? selectedFloorId;
  final String? selectedSectionId;
  final Function(String seatId, String seatLabel, String floorId, String sectionId, String floorName, String sectionName) onSeatSelected;

  const VacantSeatGrid({
    super.key,
    required this.libraryId,
    required this.shiftId,
    this.selectedSeatId,
    this.selectedFloorId,
    this.selectedSectionId,
    required this.onSeatSelected,
  });

  @override
  State<VacantSeatGrid> createState() => _VacantSeatGridState();
}

class _VacantSeatGridState extends State<VacantSeatGrid> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;

  List<Map<String, dynamic>> _floors = [];
  List<Map<String, dynamic>> _sections = [];
  List<Map<String, dynamic>> _seats = [];

  String? _selectedFloorId;
  String? _selectedSectionId;
  String? _currentSelectedSeatId;
  String? _currentSelectedSeatLabel;

  @override
  void initState() {
    super.initState();
    _currentSelectedSeatId = widget.selectedSeatId;
    _selectedFloorId = widget.selectedFloorId;
    _selectedSectionId = widget.selectedSectionId;
    _fetchData();
  }

  @override
  void didUpdateWidget(covariant VacantSeatGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shiftId != widget.shiftId || oldWidget.libraryId != widget.libraryId) {
      setState(() {
        _isLoading = true;
        _selectedFloorId = null;
        _selectedSectionId = null;
      });
      _fetchData();
    }
  }

  Future<void> _fetchData() async {
    try {
      // 1. Fetch Floors
      final floorsRes = await _supabase
          .from('floors')
          .select('id, name')
          .eq('library_id', widget.libraryId);

      final floorIds = floorsRes.map((f) => f['id']).toList();
      List<dynamic> sectionsRes = [];
      List<dynamic> seatsRes = [];

      if (floorIds.isNotEmpty) {
        // 2. Fetch Sections belonging to these floors
        sectionsRes = await _supabase
            .from('sections')
            .select('id, name, floor_id')
            .inFilter('floor_id', floorIds);

        // 3. Fetch Seats for shift
        seatsRes = await _supabase
            .from('seats')
            .select('id, floor_id, section_id, seat_label, status')
            .eq('library_id', widget.libraryId)
            .eq('shift_id', widget.shiftId);
      }

      // 4. Fetch Shifts to count them for debug logs
      final shiftsRes = await _supabase
          .from('shifts')
          .select('id')
          .eq('library_id', widget.libraryId);

      // 5. Output detailed debug logs
      debugPrint('=== VacantSeatGrid Layout Loading Audit ===');
      debugPrint('- selected libraryId: "${widget.libraryId}"');
      debugPrint('- floors count: ${floorsRes.length}');
      debugPrint('- sections count: ${sectionsRes.length}');
      debugPrint('- seats count: ${seatsRes.length}');
      debugPrint('- shifts count: ${shiftsRes.length}');
      debugPrint('============================================');

      if (mounted) {
        setState(() {
          _floors = List<Map<String, dynamic>>.from(floorsRes);
          _sections = List<Map<String, dynamic>>.from(sectionsRes);
          _seats = List<Map<String, dynamic>>.from(seatsRes);

          // Find current selected seat label if any
          if (_currentSelectedSeatId != null) {
            final match = _seats.firstWhere(
              (s) => s['id'] == _currentSelectedSeatId,
              orElse: () => {},
            );
            if (match.isNotEmpty) {
              _currentSelectedSeatLabel = match['seat_label'];
              _selectedFloorId = match['floor_id'];
              _selectedSectionId = match['section_id'];
            }
          }

          // Default Floor & Section
          if (_selectedFloorId == null && _floors.isNotEmpty) {
            _selectedFloorId = _floors.first['id'];
          }
          if (_selectedSectionId == null && _sections.isNotEmpty && _selectedFloorId != null) {
            final floorSections = _sections.where((s) => s['floor_id'] == _selectedFloorId).toList();
            if (floorSections.isNotEmpty) {
              _selectedSectionId = floorSections.first['id'];
            }
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading vacant seat grid data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> _getFilteredSeats() {
    return _seats.where((s) {
      final isVacant = s['status'] == 'vacant' || s['id'] == _currentSelectedSeatId;
      final matchFloor = _selectedFloorId == null || s['floor_id'] == _selectedFloorId;
      final matchSection = _selectedSectionId == null || s['section_id'] == _selectedSectionId;
      return isVacant && matchFloor && matchSection;
    }).toList();
  }

  void _onSeatTap(Map<String, dynamic> seat) {
    setState(() {
      _currentSelectedSeatId = seat['id'];
      _currentSelectedSeatLabel = seat['seat_label'];
    });
    final floorId = seat['floor_id'] ?? '';
    final sectionId = seat['section_id'] ?? '';
    final floorName = _floors.firstWhere((f) => f['id'] == floorId, orElse: () => {})['name'] ?? '';
    final sectionName = _sections.firstWhere((s) => s['id'] == sectionId, orElse: () => {})['name'] ?? '';

    widget.onSeatSelected(
      seat['id'],
      seat['seat_label'],
      floorId,
      sectionId,
      floorName,
      sectionName,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
          ),
        ),
      );
    }

    if (_floors.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Icon(Icons.layers_clear_outlined, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                'No floors configured for this library.',
                style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final floorSections = _sections.where((s) => s['floor_id'] == _selectedFloorId).toList();
    final filteredSeats = _getFilteredSeats();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Floor & Section Selector
        Row(
          children: [
            // Floor Dropdown
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedFloorId,
                decoration: const InputDecoration(
                  labelText: 'Floor',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: _floors.map((f) {
                  return DropdownMenuItem<String>(
                    value: f['id'],
                    child: Text(f['name'] ?? 'Floor'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedFloorId = val;
                      final fSections = _sections.where((s) => s['floor_id'] == val).toList();
                      _selectedSectionId = fSections.isNotEmpty ? fSections.first['id'] : null;
                    });
                  }
                },
              ),
            ),
            if (floorSections.isNotEmpty) ...[
              const SizedBox(width: 12),
              // Section Dropdown
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedSectionId,
                  decoration: const InputDecoration(
                    labelText: 'Section',
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: floorSections.map((s) {
                    return DropdownMenuItem<String>(
                      value: s['id'],
                      child: Text(s['name'] ?? 'Section'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedSectionId = val;
                    });
                  },
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // Vacant seats info
        if (_currentSelectedSeatLabel != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              border: Border.all(color: const Color(0xFFFFEDD5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFFE65C00), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Selected Seat: ',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: const Color(0xFF9A3412)),
                ),
                Text(
                  _currentSelectedSeatLabel!,
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                ),
              ],
            ),
          ),

        // Grid of vacant seats
        filteredSeats.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      Icon(Icons.chair_alt_outlined, size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text(
                        'No vacant seats in this section.',
                        style: GoogleFonts.inter(color: Colors.grey[500], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            : GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredSeats.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.8,
                ),
                itemBuilder: (ctx, index) {
                  final seat = filteredSeats[index];
                  final isSelected = seat['id'] == _currentSelectedSeatId;

                  return GestureDetector(
                    onTap: () => _onSeatTap(seat),
                    child: Column(
                      children: [
                        Expanded(
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFE65C00) : const Color(0xFF22C55E),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? const Color(0xFFB44900) : Colors.transparent,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Icon(
                                  isSelected ? Icons.check_rounded : Icons.chair_outlined,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          seat['seat_label'],
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? const Color(0xFFE65C00) : const Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ],
    );
  }
}
