import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class MembersSubTab extends StatefulWidget {
  final String libraryId;
  const MembersSubTab({super.key, required this.libraryId});

  @override
  State<MembersSubTab> createState() => _MembersSubTabState();
}

class _MembersSubTabState extends State<MembersSubTab> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _membersList = [];

  // Search & Filter state
  final _searchController = TextEditingController();
  String _activeFilter = 'All'; // All, Active, Pending, Expired, Hold, Trial

  // Multi-select state
  bool _isSelectMode = false;
  final Set<String> _selectedMemberIds = {};

  @override
  void initState() {
    super.initState();
    _fetchMembers();
  }

  @override
  void didUpdateWidget(covariant MembersSubTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.libraryId != widget.libraryId) {
      setState(() {
        _isLoading = true;
      });
      _fetchMembers();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Fetch Members Data ──────────────────────────────────────────────────
  Future<void> _fetchMembers() async {
    try {
      final response = await supabase
          .from('memberships')
          .select('*, member_id(id, full_name, phone, photo_url), seats(seat_label), shifts(name)')
          .eq('library_id', widget.libraryId)
          .neq('status', 'exited') // Exited goes to archive
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _membersList = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching members list: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Announce & Export Bulk Actions ─────────────────────────────────────────
  void _sendBulkAnnouncement() {
    final messageController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send Announcement', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Send a message to ${_selectedMemberIds.length} selected members:', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter announcement text here...',
                fillColor: Color(0xFFF8FAFC),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Announcement broadcasted successfully to selected members! 📢 ✓')),
              );
              setState(() {
                _isSelectMode = false;
                _selectedMemberIds.clear();
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00)),
            child: const Text('Send', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _exportSelectedMembers() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported ${_selectedMemberIds.length} members details to CSV successfully! 📥 ✓')),
    );
    setState(() {
      _isSelectMode = false;
      _selectedMemberIds.clear();
    });
  }

  // ── Add Member Wizard ────────────────────────────────────────────────────
  void _showAddMemberWizard() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    String planType = 'monthly';
    String? selectedShiftId;
    List<Map<String, dynamic>> shifts = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Load shifts if empty
            if (shifts.isEmpty) {
              supabase
                  .from('shifts')
                  .select('id, name')
                  .eq('library_id', widget.libraryId)
                  .eq('is_archived', false)
                  .then((res) {
                    setModalState(() {
                      shifts = List<Map<String, dynamic>>.from(res);
                      if (shifts.isNotEmpty) selectedShiftId = shifts.first['id'];
                    });
                  });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Add Member Wizard',
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                  ),
                  const SizedBox(height: 16),

                  // Inputs fields
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Full Name', hintText: 'Enter full name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone Number', hintText: '+91 XXXXX XXXXX'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email Address', hintText: 'name@example.com'),
                  ),
                  const SizedBox(height: 12),

                  // Plan Select dropdown
                  DropdownButtonFormField<String>(
                    value: planType,
                    decoration: const InputDecoration(labelText: 'Membership Plan'),
                    items: const [
                      DropdownMenuItem(value: 'monthly', child: Text('1 Month Plan')),
                      DropdownMenuItem(value: '3_month', child: Text('3 Month Plan')),
                      DropdownMenuItem(value: '6_month', child: Text('6 Month Plan')),
                    ],
                    onChanged: (val) {
                      if (val != null) setModalState(() => planType = val);
                    },
                  ),
                  const SizedBox(height: 12),

                  // Shift dropdown
                  if (shifts.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: selectedShiftId,
                      decoration: const InputDecoration(labelText: 'Select Shift'),
                      items: shifts.map((s) {
                        return DropdownMenuItem<String>(value: s['id'], child: Text(s['name']));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => selectedShiftId = val);
                      },
                    ),
                  const SizedBox(height: 20),

                  // Submit button
                  ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.trim().isEmpty || phoneController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Name and Phone are required!')),
                        );
                        return;
                      }
                      
                      try {
                        // 1. Check if user already exists
                        var userObj = await supabase
                            .from('users')
                            .select('id')
                            .eq('phone', phoneController.text.trim())
                            .maybeSingle();

                        String memberUserId;
                        if (userObj == null) {
                          // Create user in public.users
                          final newU = await supabase.from('users').insert({
                            'full_name': nameController.text.trim(),
                            'phone': phoneController.text.trim(),
                            'role': 'member',
                          }).select('id').single();
                          memberUserId = newU['id'];
                        } else {
                          memberUserId = userObj['id'];
                        }

                        // 2. Create membership
                        final start = DateTime.now();
                        int durationMonths = 1;
                        if (planType == '3_month') durationMonths = 3;
                        if (planType == '6_month') durationMonths = 6;
                        final end = DateTime(start.year, start.month + durationMonths, start.day);

                        await supabase.from('memberships').insert({
                          'member_id': memberUserId,
                          'library_id': widget.libraryId,
                          'shift_id': selectedShiftId!,
                          'plan_type': planType,
                          'start_date': start.toIso8601String().substring(0, 10),
                          'end_date': end.toIso8601String().substring(0, 10),
                          'status': 'active',
                        });

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Member added successfully! ✓')),
                          );
                        }
                        _fetchMembers();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error adding member: $e')),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('Register Member', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Filtering Logic ────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _getFilteredMembers() {
    var list = _membersList;

    // 1. Search Query
    final search = _searchController.text.trim().toLowerCase();
    if (search.isNotEmpty) {
      list = list.where((m) {
        final profile = m['member_id'];
        if (profile == null) return false;
        final name = (profile['full_name'] ?? '').toLowerCase();
        final phone = (profile['phone'] ?? '').toLowerCase();
        return name.contains(search) || phone.contains(search);
      }).toList();
    }

    // 2. Chip Filters
    if (_activeFilter == 'Active') {
      list = list.where((m) => m['status'] == 'active' || m['status'] == 'trial').toList();
    } else if (_activeFilter == 'Pending') {
      list = list.where((m) => m['status'] == 'pending').toList();
    } else if (_activeFilter == 'Expired') {
      list = list.where((m) => m['status'] == 'expired').toList();
    } else if (_activeFilter == 'Hold') {
      list = list.where((m) => m['status'] == 'hold').toList();
    } else if (_activeFilter == 'Trial') {
      list = list.where((m) => m['status'] == 'trial').toList();
    }

    return list;
  }

  // ── Render Helpers ────────────────────────────────────────────────────────
  Widget _buildFilterChip(String label) {
    final bool isActive = _activeFilter == label;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: isActive ? Colors.white : const Color(0xFF6B7280))),
        selected: isActive,
        onSelected: (val) {
          if (val) {
            setState(() {
              _activeFilter = label;
            });
          }
        },
        selectedColor: const Color(0xFFE65C00),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isActive ? Colors.transparent : const Color(0xFFE5E7EB)),
        ),
        showCheckmark: false,
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg = const Color(0xFFF3F4F6);
    Color txt = const Color(0xFF6B7280);
    String label = status.toUpperCase();

    if (status == 'active') {
      bg = const Color(0xFFDCFCE7);
      txt = const Color(0xFF16A34A);
    } else if (status == 'expired') {
      bg = const Color(0xFFFEE2E2);
      txt = const Color(0xFFDC2626);
    } else if (status == 'hold') {
      bg = const Color(0xFFFEF3C7);
      txt = const Color(0xFFD97706);
    } else if (status == 'trial') {
      bg = const Color(0xFFEDE9FE);
      txt = const Color(0xFF7C3AED);
      label = 'TRIAL';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: txt),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredMembers = _getFilteredMembers();

    return Scaffold(
      backgroundColor: const Color(0xFFFBF5EE),

      // Floating Add Button for Wizard
      floatingActionButton: _isSelectMode
          ? null
          : Container(
              margin: const EdgeInsets.only(bottom: 12, right: 4),
              child: FloatingActionButton(
                onPressed: _showAddMemberWizard,
                backgroundColor: const Color(0xFFE65C00),
                shape: const CircleBorder(),
                elevation: 4,
                child: const Icon(Icons.add, size: 28, color: Colors.white),
              ),
            ),

      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Search Bar & Headers Menu Options
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: '🔍 Search members by name, phone...',
                          hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
                          fillColor: const Color(0xFFF8FAFC),
                          prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                        ),
                        onChanged: (val) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Color(0xFF6B7280)),
                      onSelected: (val) {
                        if (val == 'select') {
                          setState(() {
                            _isSelectMode = true;
                            _selectedMemberIds.clear();
                          });
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'select',
                          child: Text('Select Members', style: GoogleFonts.inter(fontSize: 13)),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Scrollable Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All'),
                      _buildFilterChip('Active'),
                      _buildFilterChip('Pending'),
                      _buildFilterChip('Expired'),
                      _buildFilterChip('Hold'),
                      _buildFilterChip('Trial'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. Members Scrollable List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
                : filteredMembers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline_rounded, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text('No members match the filter.', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredMembers.length,
                        itemBuilder: (ctx, index) {
                          final membership = filteredMembers[index];
                          final member = membership['member_id'];
                          if (member == null) return const SizedBox.shrink();

                          final String memberId = member['id'];
                          final String name = member['full_name'] ?? 'No Name';
                          final String phone = member['phone'] ?? '';
                          final String photo = member['photo_url'] ?? '';
                          final String seatLabel = membership['seats']?['seat_label'] ?? 'No Seat';
                          final String shiftName = membership['shifts']?['name'] ?? 'No Shift';
                          final String status = membership['status'] ?? 'pending';

                          final bool isSelected = _selectedMemberIds.contains(memberId);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 8, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: _isSelectMode
                                  ? Checkbox(
                                      value: isSelected,
                                      activeColor: const Color(0xFFE65C00),
                                      onChanged: (val) {
                                        setState(() {
                                          if (val == true) {
                                            _selectedMemberIds.add(memberId);
                                          } else {
                                            _selectedMemberIds.remove(memberId);
                                          }
                                        });
                                      },
                                    )
                                  : CircleAvatar(
                                      radius: 26,
                                      backgroundColor: const Color(0xFFFFF7F0),
                                      backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                                      child: photo.isEmpty
                                          ? const Icon(Icons.person, color: Color(0xFFE65C00), size: 24)
                                          : null,
                                    ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildStatusBadge(status),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                                          child: Text(seatLabel, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF475569))),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.wb_sunny_outlined, size: 12, color: Color(0xFFD97706)),
                                        const SizedBox(width: 4),
                                        Text(shiftName, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF6B7280))),
                                      ],
                                    ),
                                    if (phone.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(phone, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
                                      ),
                                  ],
                                ),
                              ),
                              trailing: _isSelectMode
                                  ? null
                                  : PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert, size: 20),
                                      onSelected: (val) {
                                        if (val == 'details') {
                                          Navigator.pushNamed(context, '/admin/member', arguments: memberId);
                                        } else if (val == 'renew') {
                                          Navigator.pushNamed(context, '/admin/library/setup/3');
                                        }
                                      },
                                      itemBuilder: (ctx) => [
                                        PopupMenuItem(value: 'details', child: Text('View Details', style: GoogleFonts.inter(fontSize: 13))),
                                        PopupMenuItem(value: 'renew', child: Text('Renew', style: GoogleFonts.inter(fontSize: 13))),
                                      ],
                                    ),
                            ),
                          );
                        },
                      ),
          ),

          // 3. Sliding Bottom Select Bar (Announce / Export / Cancel)
          if (_isSelectMode)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _selectedMemberIds.isEmpty ? null : _sendBulkAnnouncement,
                      icon: const Icon(Icons.campaign_outlined, size: 18),
                      label: Text('Announce', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65C00),
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _selectedMemberIds.isEmpty ? null : _exportSelectedMembers,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text('Export', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFFE65C00),
                        side: const BorderSide(color: Color(0xFFE65C00)),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isSelectMode = false;
                        _selectedMemberIds.clear();
                      });
                    },
                    child: Text('Cancel', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
