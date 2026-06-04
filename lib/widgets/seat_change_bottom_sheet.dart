import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SeatChangeBottomSheet extends StatefulWidget {
  final Map<String, dynamic> membership;
  final VoidCallback? onSuccess;

  const SeatChangeBottomSheet({
    super.key,
    required this.membership,
    this.onSuccess,
  });

  @override
  State<SeatChangeBottomSheet> createState() => _SeatChangeBottomSheetState();
}

class _SeatChangeBottomSheetState extends State<SeatChangeBottomSheet> {
  final _supabase = Supabase.instance.client;
  final _reasonController = TextEditingController();
  
  bool _isLoadingSections = true;
  List<Map<String, dynamic>> _sections = [];
  String? _selectedSectionId;
  String? _selectedSectionName;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadSections();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadSections() async {
    final library = widget.membership['libraries'] as Map<String, dynamic>? ?? {};
    final libraryId = library['id'];
    if (libraryId == null) {
      if (mounted) {
        setState(() => _isLoadingSections = false);
      }
      return;
    }

    try {
      // 1. Fetch floors for this library
      final floorsRes = await _supabase
          .from('floors')
          .select('id')
          .eq('library_id', libraryId);
      
      if (floorsRes.isNotEmpty) {
        final floorIds = floorsRes.map((f) => f['id'] as String).toList();
        
        // 2. Fetch sections for these floors
        final sectionsRes = await _supabase
            .from('sections')
            .select('id, name')
            .inFilter('floor_id', floorIds)
            .order('name');
        
        if (mounted) {
          setState(() {
            _sections = List<Map<String, dynamic>>.from(sectionsRes);
            _isLoadingSections = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoadingSections = false);
        }
      }
    } catch (e) {
      debugPrint('Error loading library sections: $e');
      if (mounted) {
        setState(() => _isLoadingSections = false);
      }
    }
  }

  Future<void> _submitRequest() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a reason for the seat change request.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final library = widget.membership['libraries'] as Map<String, dynamic>? ?? {};
      final seat = widget.membership['seats'] as Map<String, dynamic>? ?? {};
      
      // Combine reason with preferred section if selected (since preferred_section_id column is not in DB)
      String finalReason = reason;
      if (_selectedSectionName != null) {
        finalReason = "$reason (Preferred Section: $_selectedSectionName)";
      }

      await _supabase.from('seat_change_requests').insert({
        'membership_id': widget.membership['id'],
        'member_id': widget.membership['member_id'],
        'library_id': library['id'],
        'current_seat_id': seat['id'],
        'reason': finalReason,
        'status': 'pending',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seat change request submitted successfully! ✓'),
            backgroundColor: Color(0xFF22C55E),
          ),
        );
        widget.onSuccess?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error submitting seat change request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit request: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.membership['libraries'] as Map<String, dynamic>? ?? {};
    final seat = widget.membership['seats'] as Map<String, dynamic>? ?? {};

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Request Seat Change',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Text(
            library['name'] ?? 'SILENCE Study Zone',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          const Divider(height: 24),
          
          Text(
            'Current Seat',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF), // blue-50
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              seat.isNotEmpty ? (seat['seat_label'] ?? 'Pending') : 'Pending Seat',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1D4ED8), // blue-700
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Preferred Section Dropdown
          Text(
            'Preferred Section (Optional)',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 6),
          _isLoadingSections
              ? const SizedBox(
                  height: 48,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE65C00)),
                    ),
                  ),
                )
              : _sections.isEmpty
                  ? Text(
                      'No other sections available.',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[400]),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedSectionId,
                          hint: Text('Select preferred section', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500])),
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFFE65C00)),
                          items: _sections.map((sec) {
                            return DropdownMenuItem<String>(
                              value: sec['id'],
                              child: Text(sec['name'] ?? 'Section', style: GoogleFonts.inter(fontSize: 14)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              final matched = _sections.firstWhere((s) => s['id'] == val);
                              setState(() {
                                _selectedSectionId = val;
                                _selectedSectionName = matched['name'];
                              });
                            }
                          },
                        ),
                      ),
                    ),
          const SizedBox(height: 16),
          
          Text(
            'Reason *',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _reasonController,
            maxLines: 3,
            maxLength: 200,
            style: GoogleFonts.inter(fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'e.g. Current seat is too close to the door or AC is too cold...',
            ),
          ),
          const SizedBox(height: 16),
          
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED), // orange-50
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFFE65C00), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Admin will assign the best available seat based on occupancy and layout.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFFC2410C), // orange-800
                    ),
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Submit →'),
                ),
              )
            ],
          )
        ],
      ),
    );
  }
}
