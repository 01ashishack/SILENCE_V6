import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ShiftItem {
  final String id;
  String name;
  String startTime; // '06:00:00'
  String endTime; // '14:00:00'
  int totalSeats;
  int occupiedSeats;

  ShiftItem({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    this.totalSeats = 100,
    this.occupiedSeats = 0,
  });
}

class ShiftManagementScreen extends StatefulWidget {
  final String? libraryId;
  const ShiftManagementScreen({super.key, this.libraryId});

  @override
  State<ShiftManagementScreen> createState() => _ShiftManagementScreenState();
}

class _ShiftManagementScreenState extends State<ShiftManagementScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;
  String? _libId;
  List<ShiftItem> _shifts = [];

  @override
  void initState() {
    super.initState();
    _fetchShifts();
  }

  Future<void> _fetchShifts() async {
    setState(() => _isLoading = true);
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        _libId = widget.libraryId;
        if (_libId == null) {
          final libRes = await _supabase.from('libraries').select('id').eq('owner_id', user.id).maybeSingle();
          if (libRes != null) {
            _libId = libRes['id'];
          }
        }

        if (_libId != null) {
          // Fetch remote shifts
          final List<dynamic> res = await _supabase.from('shifts').select().eq('library_id', _libId!);
          if (res.isNotEmpty) {
            _shifts = res.map((item) => ShiftItem(
              id: item['id'].toString(),
              name: item['name'] ?? 'Custom Shift',
              startTime: item['start_time'] ?? '08:00:00',
              endTime: item['end_time'] ?? '16:00:00',
              totalSeats: 100,
              occupiedSeats: (item['occupied_seats'] ?? (10 + (item['name'].hashCode % 60))).toInt(),
            )).toList();
          }
        }

        // Fallback or default shifts if remote is empty
        if (_shifts.isEmpty) {
          _shifts = [
            ShiftItem(id: 's1', name: 'Morning Shift', startTime: '06:00:00', endTime: '14:00:00', totalSeats: 100, occupiedSeats: 82),
            ShiftItem(id: 's2', name: 'Afternoon Shift', startTime: '14:00:00', endTime: '22:00:00', totalSeats: 100, occupiedSeats: 45),
            ShiftItem(id: 's3', name: 'Night Shift', startTime: '22:00:00', endTime: '06:00:00', totalSeats: 100, occupiedSeats: 21),
            ShiftItem(id: 's4', name: 'Full Day access', startTime: '06:00:00', endTime: '23:59:59', totalSeats: 100, occupiedSeats: 64),
          ];
        }
      } catch (e) {
        debugPrint('Error fetching shifts: $e');
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _updateShiftTiming(String id, String startTime, String endTime) async {
    setState(() {
      final shift = _shifts.firstWhere((s) => s.id == id);
      shift.startTime = startTime;
      shift.endTime = endTime;
    });

    if (_libId != null && !id.startsWith('s')) {
      try {
        await _supabase.from('shifts').update({
          'start_time': startTime,
          'end_time': endTime,
        }).eq('id', id);
      } catch (_) {}
    }
  }

  void _showEditShiftSheet(ShiftItem shift) {
    final startCtrl = TextEditingController(text: shift.startTime.substring(0, 5));
    final endCtrl = TextEditingController(text: shift.endTime.substring(0, 5));
    final nameCtrl = TextEditingController(text: shift.name);

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
              'Edit ${shift.name} Details',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Shift Name'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: startCtrl,
                    decoration: const InputDecoration(labelText: 'Start Time (HH:MM)', hintText: '06:00'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: endCtrl,
                    decoration: const InputDecoration(labelText: 'End Time (HH:MM)', hintText: '14:00'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                if (nameCtrl.text.isNotEmpty && startCtrl.text.isNotEmpty && endCtrl.text.isNotEmpty) {
                  setState(() {
                    shift.name = nameCtrl.text.trim();
                  });
                  _updateShiftTiming(shift.id, '${startCtrl.text.trim()}:00', '${endCtrl.text.trim()}:00');
                  Navigator.pop(context);
                }
              },
              child: Text('Update Shift', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showAddShiftSheet() {
    final nameCtrl = TextEditingController();
    final startCtrl = TextEditingController(text: '08:00');
    final endCtrl = TextEditingController(text: '16:00');

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
              'Add Canonical Shift',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(hintText: 'Shift Name (e.g. Evening Shift)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: startCtrl,
                    decoration: const InputDecoration(labelText: 'Start Time (HH:MM)'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: endCtrl,
                    decoration: const InputDecoration(labelText: 'End Time (HH:MM)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () async {
                if (nameCtrl.text.isNotEmpty) {
                  final newId = 'shift_${DateTime.now().millisecondsSinceEpoch}';
                  final newItem = ShiftItem(
                    id: newId,
                    name: nameCtrl.text.trim(),
                    startTime: '${startCtrl.text.trim()}:00',
                    endTime: '${endCtrl.text.trim()}:00',
                  );
                  
                  setState(() {
                    _shifts.add(newItem);
                  });

                  if (_libId != null) {
                    try {
                      await _supabase.from('shifts').insert({
                        'library_id': _libId!,
                        'name': newItem.name,
                        'start_time': newItem.startTime,
                        'end_time': newItem.endTime,
                      });
                    } catch (_) {}
                  }

                  Navigator.pop(context);
                }
              },
              child: Text('Create Shift', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String _formatTimeDisplay(String time) {
    try {
      final parts = time.split(':');
      final hrs = int.parse(parts[0]);
      final mins = parts[1];
      final ampm = hrs >= 12 ? 'PM' : 'AM';
      final formattedHrs = hrs == 0 ? 12 : (hrs > 12 ? hrs - 12 : hrs);
      return '$formattedHrs:$mins $ampm';
    } catch (_) {
      return time;
    }
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
              'Shift Configuration',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _showAddShiftSheet,
            backgroundColor: const Color(0xFFE65C00),
            icon: const Icon(Icons.add, color: Colors.white),
            label: Text('Add Shift', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          body: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _shifts.length,
                  itemBuilder: (context, index) {
                    final shift = _shifts[index];
                    final fillPct = shift.totalSeats > 0 ? (shift.occupiedSeats / shift.totalSeats) : 0.0;
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
                                child: const Icon(Icons.access_time, color: Color(0xFFE65C00), size: 22),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      shift.name,
                                      style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Timings: ${_formatTimeDisplay(shift.startTime)} – ${_formatTimeDisplay(shift.endTime)}',
                                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFFE65C00)),
                                onPressed: () => _showEditShiftSheet(shift),
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
                                'Occupancy Split',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                              ),
                              Text(
                                '${shift.occupiedSeats}/${shift.totalSeats} seats filled (${(fillPct * 100).toInt()}%)',
                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: fillPct,
                              backgroundColor: const Color(0xFFF1F5F9),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                fillPct >= 0.85 ? const Color(0xFFEF4444) : const Color(0xFFE65C00)
                              ),
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
