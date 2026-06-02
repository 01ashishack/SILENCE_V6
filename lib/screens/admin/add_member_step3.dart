import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/vacant_seat_grid.dart';
import '../../models/member_data.dart';

class AddMemberStep3 extends StatefulWidget {
  final String libraryId;
  final MemberData memberData;
  final Function(String seatId, String seatLabel, String floorId, String sectionId, String floorName, String sectionName) onSeatSelected;

  const AddMemberStep3({
    super.key,
    required this.libraryId,
    required this.memberData,
    required this.onSeatSelected,
  });

  @override
  State<AddMemberStep3> createState() => _AddMemberStep3State();
}

class _AddMemberStep3State extends State<AddMemberStep3> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.memberData.selectedShiftId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                'Please select a shift in Step 2 first.',
                style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Choose a Vacant Seat *',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Select a seat from the available vacant seats in the library for this shift.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 24),
          VacantSeatGrid(
            libraryId: widget.libraryId,
            shiftId: widget.memberData.selectedShiftId!,
            selectedSeatId: widget.memberData.selectedSeatId,
            selectedFloorId: widget.memberData.selectedFloorId,
            selectedSectionId: widget.memberData.selectedSectionId,
            onSeatSelected: widget.onSeatSelected,
          ),
        ],
      ),
    );
  }
}
