import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../core/cache_service.dart';
import '../../models/member_draft.dart';
import '../../services/draft_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/audit_logger.dart';
import '../../utils/csv_exporter.dart';
import 'member_transfer_screen.dart';
import '../../widgets/states/shimmer_box.dart';

enum MemberListItemType {
  draft,
  member,
  header
}

class MemberListItem {
  final MemberListItemType type;
  final String? headerText;
  final MemberDraft? draft;
  final Map<String, dynamic>? membership;

  MemberListItem.draft(this.draft) : type = MemberListItemType.draft, headerText = null, membership = null;
  MemberListItem.member(this.membership) : type = MemberListItemType.member, headerText = null, draft = null;
  MemberListItem.header(this.headerText) : type = MemberListItemType.header, draft = null, membership = null;
}

class MembersSubTab extends StatefulWidget {
  final String libraryId;
  // How many libraries this admin owns — the Transfer action is hidden when 1.
  final int ownedLibraryCount;
  const MembersSubTab({super.key, required this.libraryId, this.ownedLibraryCount = 0});

  @override
  State<MembersSubTab> createState() => _MembersSubTabState();
}

class _MembersSubTabState extends State<MembersSubTab> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isProfileComplete = true;
  List<Map<String, dynamic>> _membersList = [];
  List<MemberDraft> _draftsList = [];

  // Search & Filter state
  final _searchController = TextEditingController();
  String _activeFilter = 'All'; // All, Active, Pending, Expired, Hold, Trial, Pending Drafts
  bool _isSearching = false;
  String _selectedSort = 'joining_desc';

  // Floor & Shift filters state
  List<Map<String, dynamic>> _floors = [];
  List<Map<String, dynamic>> _shifts = [];
  String _selectedFloorId = 'all';
  String _selectedShiftId = 'all';

  // Multi-select state
  bool _isSelectMode = false;
  final Set<String> _selectedMemberIds = {};

  // Pagination & Cache state
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 0;
  final int _pageSize = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  Future<void> _checkOnboardingStatus() async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        final userData = await supabase.from('users').select().eq('id', user.id).maybeSingle();
        if (userData != null) {
          final String name = userData['full_name'] ?? '';
          final String phone = userData['phone'] ?? '';
          final String gender = userData['gender'] ?? '';
          final String dob = userData['date_of_birth'] ?? '';
          final String address = userData['address'] ?? '';
          final String photoUrl = userData['photo_url'] ?? '';

          final bool isComplete = name.isNotEmpty &&
              phone.isNotEmpty &&
              gender.isNotEmpty &&
              dob.isNotEmpty &&
              address.isNotEmpty &&
              photoUrl.isNotEmpty;
          
          if (mounted) {
            setState(() {
              _isProfileComplete = isComplete;
            });
          }
        }
      } catch (e) {
        debugPrint('Error in _checkOnboardingStatus: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _checkOnboardingStatus().then((_) {
      _loadCacheAndFetch();
      _fetchFiltersData();
    });
  }

  Future<void> _fetchDrafts() async {
    try {
      final list = await DraftService.instance.getDrafts(widget.libraryId);
      if (mounted) {
        setState(() {
          _draftsList = list;
        });
      }
    } catch (e) {
      debugPrint('Error fetching drafts: $e');
    }
  }

  Future<void> _fetchFiltersData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      var floorsQuery = supabase.from('floors').select('id, name, library_id');
      var shiftsQuery = supabase.from('shifts').select('id, name, library_id').eq('is_archived', false);

      if (widget.libraryId != 'all') {
        floorsQuery = floorsQuery.eq('library_id', widget.libraryId);
        shiftsQuery = shiftsQuery.eq('library_id', widget.libraryId);
      }

      final floorsRes = await floorsQuery;
      final shiftsRes = await shiftsQuery;

      if (mounted) {
        setState(() {
          _floors = List<Map<String, dynamic>>.from(floorsRes);
          _shifts = List<Map<String, dynamic>>.from(shiftsRes);
          
          if (widget.libraryId == 'all') {
            _selectedFloorId = 'all';
            _selectedShiftId = 'all';
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching floors/shifts filters: $e');
    }
  }

  @override
  void didUpdateWidget(covariant MembersSubTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.libraryId != widget.libraryId) {
      setState(() {
        _isLoading = true;
        if (widget.libraryId == 'all') {
          _selectedFloorId = 'all';
          _selectedShiftId = 'all';
        }
      });
      _checkOnboardingStatus().then((_) {
        _loadCacheAndFetch();
        _fetchFiltersData();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore && !_isLoading && _activeFilter != 'Pending Drafts') {
        _fetchMembers();
      }
    }
  }

  Future<void> _loadCacheAndFetch() async {
    _fetchDrafts();
    final cacheKey = 'members_list_page1_${widget.libraryId}';
    final cached = await CacheService.instance.readCache(cacheKey);
    if (cached != null && cached is List) {
      if (mounted) {
        setState(() {
          _membersList = List<Map<String, dynamic>>.from(cached);
          _isLoading = false;
        });
      }
      _fetchMembers(isRefresh: true);
    } else {
      _fetchMembers(isRefresh: true);
    }
  }

  // ── Fetch Members Data ──────────────────────────────────────────────────
  Future<void> _fetchMembers({bool isRefresh = false}) async {
    if (isRefresh) {
      _currentPage = 0;
      _hasMore = true;
    }

    if (!_hasMore) return;

    if (_currentPage == 0) {
      if (!isRefresh) {
        setState(() {
          _isLoading = true;
        });
      }
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final fromIndex = _currentPage * _pageSize;
      final toIndex = fromIndex + _pageSize - 1;

      var query = supabase
          .from('memberships')
          .select('id, member_id, library_id, shift_id, seat_id, plan_type, status, start_date, end_date, created_at, member_id(id, full_name, phone, photo_url, gender), seats(seat_label, floor_id), shifts(name)')
          .neq('status', 'exited'); // Exited goes to archive

      if (widget.libraryId != 'all') {
        query = query.eq('library_id', widget.libraryId);
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(fromIndex, toIndex);

      final List<Map<String, dynamic>> newMembers = List<Map<String, dynamic>>.from(response);

      if (mounted) {
        setState(() {
          if (_currentPage == 0) {
            _membersList = newMembers;
            _isLoading = false;
            CacheService.instance.writeCache('members_list_page1_${widget.libraryId}', newMembers);
          } else {
            _membersList.addAll(newMembers);
            _isLoadingMore = false;
          }

          if (newMembers.length < _pageSize) {
            _hasMore = false;
          } else {
            _currentPage++;
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching members list: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
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
              final msg = messageController.text.trim();
              if (msg.isEmpty) return; // need a message before sending
              Navigator.pop(ctx);
              _broadcastAnnouncement(msg);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00)),
            child: const Text('Send', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Insert a real notification for each selected member. Honest: success is
  // shown only after the rows are written; a failure surfaces friendlyError.
  Future<void> _broadcastAnnouncement(String message) async {
    final ids = _selectedMemberIds.toList();
    if (ids.isEmpty) return;
    try {
      final rows = ids
          .map((id) => {
                'user_id': id,
                'title': 'Announcement',
                'body': message,
                'data': {'type': 'announcement'},
              })
          .toList();
      await supabase.from('notifications').insert(rows);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Announcement sent to ${ids.length} member(s) 📢'),
          backgroundColor: const Color(0xFFE65C00),
        ),
      );
      setState(() {
        _isSelectMode = false;
        _selectedMemberIds.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red[600]),
      );
    }
  }

  // Export the selected members to a real CSV (CsvExporter shares the file).
  // Honest: the OS share/save sheet is the result — no fake "exported ✓".
  Future<void> _exportSelectedMembers() async {
    final selected = _membersList.where((m) {
      final mid = m['member_id'] is Map
          ? m['member_id']['id']?.toString()
          : m['member_id']?.toString();
      return mid != null && _selectedMemberIds.contains(mid);
    }).map((m) {
      final user = m['member_id'] is Map ? m['member_id'] as Map : null;
      return <String, dynamic>{
        'full_name': user?['full_name'],
        'email': user?['email'],
        'phone': user?['phone'],
        'created_at': m['created_at'],
        'expiry_date': m['end_date'],
        'status': m['status'],
      };
    }).toList();

    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No members selected to export.')),
      );
      return;
    }

    try {
      await CsvExporter.exportMembers(libraryName: 'Members', members: selected);
      if (!mounted) return;
      setState(() {
        _isSelectMode = false;
        _selectedMemberIds.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red[600]),
      );
    }
  }

  // ── Add Member Wizard ────────────────────────────────────────────────────
  void _showAddMemberWizard() {
    Navigator.pushNamed(
      context,
      '/admin/member/add',
      arguments: {'libraryId': widget.libraryId},
    ).then((result) {
      if (result == true) {
        _fetchMembers(isRefresh: true);
        _fetchDrafts();
      }
    });
  }

  // ── Sorting & Action Bottom Sheet ─────────────────────────────────────────
  PopupMenuItem<String> _buildPopupSortItem(String id, String label, IconData icon) {
    final bool isSelected = _selectedSort == id;
    return PopupMenuItem<String>(
      value: id,
      child: Row(
        children: [
          Icon(
            icon,
            color: isSelected ? const Color(0xFFE65C00) : const Color(0xFF64748B),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? const Color(0xFFE65C00) : const Color(0xFF1E293B),
              ),
            ),
          ),
          if (isSelected)
            const Icon(Icons.check, color: Color(0xFFE65C00), size: 14),
        ],
      ),
    );
  }

  Widget _buildSortMenuButton() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.tune_rounded, color: Color(0xFF6B7280)),
      tooltip: 'Sort Options',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      onSelected: (String id) {
        if (id == 'bulk_select') {
          setState(() {
            _isSelectMode = true;
            _selectedMemberIds.clear();
          });
        } else {
          setState(() {
            _selectedSort = id;
          });
        }
      },
      itemBuilder: (BuildContext context) => [
        _buildPopupSortItem('joining_desc', 'Joining Date (Newest)', Icons.calendar_today),
        _buildPopupSortItem('joining_asc', 'Joining Date (Oldest)', Icons.calendar_today_outlined),
        _buildPopupSortItem('expiry_asc', 'Expiry Date (Soonest)', Icons.running_with_errors),
        _buildPopupSortItem('expiry_desc', 'Expiry Date (Latest)', Icons.timer),
        _buildPopupSortItem('seat_asc', 'Seat Label (A-Z)', Icons.chair_alt),
        _buildPopupSortItem('seat_desc', 'Seat Label (Z-A)', Icons.chair_alt_outlined),
        _buildPopupSortItem('gender', 'Gender', Icons.person_outline),
        _buildPopupSortItem('name_asc', 'Name (A-Z)', Icons.sort_by_alpha),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'bulk_select',
          child: Row(
            children: [
              const Icon(Icons.check_box_outlined, color: Color(0xFFE65C00), size: 18),
              const SizedBox(width: 8),
              Text(
                'Select Members',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Member Actions Bottom Sheet ─────────────────────────────────────────
  void _showMemberActionsBottomSheet(Map<String, dynamic> membership) {
    final member = membership['member_id'];
    if (member == null) return;
    final String memberId = member['id']?.toString() ?? '';
    final String name = member['full_name']?.toString() ?? 'Member';
    final String status = (membership['status'] ?? 'pending').toString();
    final bool isHold = status == 'hold';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.autorenew, color: Color(0xFFE65C00)),
                title: Text('Renew', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text('Open profile to renew', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.pushNamed(context, '/admin/member', arguments: memberId)
                      .then((_) => _fetchMembers(isRefresh: true));
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(isHold ? Icons.play_arrow_rounded : Icons.pause_rounded, color: const Color(0xFFD97706)),
                title: Text(isHold ? 'Resume Membership' : 'Hold Membership', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _holdOrResumeMember(membership, resume: isHold);
                },
              ),
              // Transfer only makes sense with 2+ owned libraries.
              if (widget.ownedLibraryCount > 1) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF2563EB)),
                  title: Text('Transfer to another library', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MemberTransferScreen(
                          memberId: memberId,
                          memberName: name,
                          fromMembership: membership,
                        ),
                      ),
                    ).then((result) {
                      if (result == true) _fetchMembers(isRefresh: true);
                    });
                  },
                ),
              ],
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.person_remove_rounded, color: Color(0xFFDC2626)),
                title: Text('Remove from library', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFFDC2626))),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _removeMember(membership);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Hold or resume a membership: flip status + the seat's status, notify, audit.
  Future<void> _holdOrResumeMember(Map<String, dynamic> membership, {required bool resume}) async {
    final member = membership['member_id'];
    final String memberId = member?['id']?.toString() ?? '';
    final String name = member?['full_name']?.toString() ?? 'Member';
    final String membershipId = membership['id']?.toString() ?? '';
    final String? seatId = membership['seat_id']?.toString();
    final String libraryId = membership['library_id']?.toString() ?? '';
    if (membershipId.isEmpty) return;

    final confirmed = await _showCustomConfirmDialog(
      context: context,
      title: resume ? 'Resume membership?' : 'Hold membership?',
      content: resume
          ? 'Reactivate $name\'s membership and re-occupy their seat.'
          : 'Pause $name\'s membership. Their seat will be marked on-hold.',
      confirmLabel: resume ? 'Resume' : 'Hold',
      cancelLabel: 'Cancel',
      icon: resume ? Icons.play_arrow_rounded : Icons.pause_rounded,
    );
    if (confirmed != true) return;

    try {
      await supabase.from('memberships').update({
        'status': resume ? 'active' : 'hold',
      }).eq('id', membershipId);

      if (seatId != null && seatId.isNotEmpty) {
        await supabase.from('seats').update({
          'status': resume ? 'occupied' : 'hold',
        }).eq('id', seatId);
      }

      if (memberId.isNotEmpty) {
        await supabase.from('notifications').insert({
          'user_id': memberId,
          'title': resume ? 'Membership resumed' : 'Membership on hold',
          'body': resume
              ? 'Your membership is active again.'
              : 'Your membership has been put on hold by the admin.',
          'data': {'type': resume ? 'membership_resumed' : 'membership_hold'},
        });
      }

      await AuditLogger.instance.log(
        action: resume ? 'resume_membership' : 'hold_membership',
        category: AuditLogger.categoryMembers,
        title: resume ? 'Resumed membership' : 'Held membership',
        details: name,
        libraryId: libraryId.isEmpty ? null : libraryId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resume ? 'Membership resumed' : 'Membership put on hold'),
            backgroundColor: const Color(0xFFE65C00),
          ),
        );
        _fetchMembers(isRefresh: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red[600]),
        );
      }
    }
  }

  // Remove a member from the library: exit membership + free their seat, notify, audit.
  Future<void> _removeMember(Map<String, dynamic> membership) async {
    final member = membership['member_id'];
    final String memberId = member?['id']?.toString() ?? '';
    final String name = member?['full_name']?.toString() ?? 'Member';
    final String membershipId = membership['id']?.toString() ?? '';
    final String? seatId = membership['seat_id']?.toString();
    final String libraryId = membership['library_id']?.toString() ?? '';
    if (membershipId.isEmpty) return;

    final confirmed = await _showCustomConfirmDialog(
      context: context,
      title: 'Remove $name?',
      content: 'This exits their membership and frees their seat. This cannot be undone.',
      confirmLabel: 'Remove',
      cancelLabel: 'Cancel',
      icon: Icons.person_remove_rounded,
    );
    if (confirmed != true) return;

    try {
      await supabase.from('memberships').update({
        'status': 'exited',
        'seat_id': null,
        'exited_at': DateTime.now().toIso8601String(),
      }).eq('id', membershipId);

      if (seatId != null && seatId.isNotEmpty) {
        await supabase.from('seats').update({
          'status': 'vacant',
          'occupied_by_member_id': null,
        }).eq('id', seatId);
      }

      if (memberId.isNotEmpty) {
        await supabase.from('notifications').insert({
          'user_id': memberId,
          'title': 'Membership ended',
          'body': 'Your membership at this library has been ended by the admin.',
          'data': {'type': 'membership_exited'},
        });
      }

      await AuditLogger.instance.log(
        action: 'remove_member',
        category: AuditLogger.categoryMembers,
        title: 'Removed member',
        details: name,
        libraryId: libraryId.isEmpty ? null : libraryId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name removed'), backgroundColor: const Color(0xFFE65C00)),
        );
        _fetchMembers(isRefresh: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red[600]),
        );
      }
    }
  }

  // ── Custom Confirmation Dialog ──────────────────────────────────────────
  Future<bool?> _showCustomConfirmDialog({
    required BuildContext context,
    required String title,
    required String content,
    required String confirmLabel,
    required String cancelLabel,
    required IconData icon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: const Color(0xFFE65C00), size: 40),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  content,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF64748B),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(
                          cancelLabel,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(
                          confirmLabel,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTimeHM(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    try {
      final parts = timeStr.split(':');
      if (parts.isNotEmpty) {
        final hour = int.tryParse(parts[0]) ?? 0;
        final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
        final tod = TimeOfDay(hour: hour, minute: minute);
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
        return DateFormat('h:mm a').format(dt); // e.g. "6:00 AM"
      }
    } catch (_) {}
    return timeStr;
  }


  void _showSelectorBottomSheet({
    required String label,
    required String? selectedId,
    required List<dynamic> items,
    required bool isFloor,
    required ValueChanged<String> onChanged,
  }) {
    final displayItems = [
      {'id': 'all', 'name': isFloor ? 'All Floors' : 'All Shifts'},
      ...items,
    ];
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.15),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            constraints: const BoxConstraints(maxWidth: 300, maxHeight: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select ${isFloor ? 'Floor' : 'Shift'}',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: displayItems.map((item) {
                      final String id = item['id'].toString();
                      final bool isSelected = id == selectedId;
                      
                      String subtitleText = '';
                      if (!isFloor && id != 'all') {
                        final start = item['start_time'];
                        final end = item['end_time'];
                        if (start != null && end != null) {
                          subtitleText = 'Timings: ${_formatTimeHM(start)} – ${_formatTimeHM(end)}';
                        }
                      }

                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: Icon(
                          isFloor ? Icons.layers_rounded : Icons.access_time_rounded,
                          color: isSelected ? const Color(0xFFE65C00) : const Color(0xFF94A3B8),
                          size: 16,
                        ),
                        title: Text(
                          item['name'] ?? '',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? const Color(0xFFE65C00) : const Color(0xFF1E293B),
                          ),
                        ),
                        subtitle: subtitleText.isNotEmpty
                            ? Text(
                                subtitleText,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: const Color(0xFF64748B),
                                ),
                              )
                            : null,
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Color(0xFFE65C00), size: 14)
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          onChanged(id);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCustomPopupSelector({
    required String label,
    required String? selectedId,
    required List<dynamic> items,
    required bool isFloor,
    required ValueChanged<String> onChanged,
  }) {
    Map<String, dynamic>? selectedItem;
    for (final item in items) {
      if (item is Map<String, dynamic> &&
          item['id']?.toString() == selectedId) {
        selectedItem = item;
        break;
      }
    }
    final String selectedName = selectedId == 'all'
        ? (isFloor ? 'All Floors' : 'All Shifts')
        : (selectedItem != null ? (selectedItem['name'] ?? '') : 'Select ${isFloor ? 'Floor' : 'Shift'}');

    return GestureDetector(
      onTap: () => _showSelectorBottomSheet(
        label: label,
        selectedId: selectedId,
        items: items,
        isFloor: isFloor,
        onChanged: onChanged,
      ),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isFloor ? Icons.layers_rounded : Icons.access_time_rounded,
              color: const Color(0xFFE65C00),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    selectedName,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF64748B),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  // ── Filtering & Sorting Logic ─────────────────────────────────────────────
  List<Map<String, dynamic>> _getFilteredMembers() {
    var list = _membersList;

    // 1. Floor Filter
    if (_selectedFloorId != 'all') {
      list = list.where((m) {
        final seat = m['seats'];
        if (seat == null) return false;
        return seat['floor_id']?.toString() == _selectedFloorId;
      }).toList();
    }

    // 2. Shift Filter
    if (_selectedShiftId != 'all') {
      list = list.where((m) => m['shift_id']?.toString() == _selectedShiftId).toList();
    }

    // 3. Search Query
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

    // 4. Chip Filters
    if (_activeFilter == 'Active') {
      list = list.where((m) => m['status'] == 'active' || m['status'] == 'trial').toList();
    } else if (_activeFilter == 'Pending') {
      list = list.where((m) => m['status'] == 'pending').toList();
    } else if (_activeFilter == 'Expired') {
      // Handled globally in items mapping, but we load both expired and soon-to-expire
      final now = DateTime.now();
      final todayMidnight = DateTime(now.year, now.month, now.day);
      final sevenDaysLater = todayMidnight.add(const Duration(days: 7));
      
      list = list.where((m) {
        final status = m['status'] ?? '';
        if (status == 'expired') return true;
        final endDateStr = m['end_date'];
        if (endDateStr != null) {
          final endDate = DateTime.tryParse(endDateStr);
          if (endDate != null) {
            return endDate.isBefore(sevenDaysLater) && !endDate.isBefore(todayMidnight) && (status == 'active' || status == 'trial');
          }
        }
        return false;
      }).toList();
    } else if (_activeFilter == 'Hold') {
      list = list.where((m) => m['status'] == 'hold').toList();
    } else if (_activeFilter == 'Trial') {
      list = list.where((m) => m['status'] == 'trial').toList();
    }

    // 5. Sorting
    list = List<Map<String, dynamic>>.from(list);
    list.sort((a, b) {
      if (_selectedSort == 'joining_desc') {
        final dateA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(1970);
        final dateB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(1970);
        return dateB.compareTo(dateA);
      } else if (_selectedSort == 'joining_asc') {
        final dateA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(1970);
        final dateB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(1970);
        return dateA.compareTo(dateB);
      } else if (_selectedSort == 'expiry_asc') {
        final dateA = DateTime.tryParse(a['end_date'] ?? '') ?? DateTime(2100);
        final dateB = DateTime.tryParse(b['end_date'] ?? '') ?? DateTime(2100);
        return dateA.compareTo(dateB);
      } else if (_selectedSort == 'expiry_desc') {
        final dateA = DateTime.tryParse(a['end_date'] ?? '') ?? DateTime(1970);
        final dateB = DateTime.tryParse(b['end_date'] ?? '') ?? DateTime(1970);
        return dateB.compareTo(dateA);
      } else if (_selectedSort == 'seat' || _selectedSort == 'seat_asc') {
        final labelA = a['seats']?['seat_label'] ?? '';
        final labelB = b['seats']?['seat_label'] ?? '';
        return labelA.compareTo(labelB);
      } else if (_selectedSort == 'seat_desc') {
        final labelA = a['seats']?['seat_label'] ?? '';
        final labelB = b['seats']?['seat_label'] ?? '';
        return labelB.compareTo(labelA);
      } else if (_selectedSort == 'gender') {
        final genA = a['member_id']?['gender'] ?? '';
        final genB = b['member_id']?['gender'] ?? '';
        return genA.compareTo(genB);
      } else if (_selectedSort == 'name_asc') {
        final nameA = a['member_id']?['full_name'] ?? '';
        final nameB = b['member_id']?['full_name'] ?? '';
        return nameA.compareTo(nameB);
      }
      return 0;
    });

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
      label = 'PRESENT';
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

  Widget _buildDraftCard(MemberDraft draft) {
    final name = draft.draftData['name'] as String? ?? 'Unnamed Member';
    final phone = draft.draftData['phone'] as String? ?? 'No phone';
    final shift = draft.draftData['selectedShiftName'] as String? ?? 'No shift chosen';
    final seat = draft.draftData['selectedSeatLabel'] as String? ?? 'No seat chosen';
    final date = draft.updatedAt ?? draft.createdAt ?? DateTime.now();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.01), blurRadius: 8, offset: const Offset(0, 2)),
        ],
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFFFF7ED),
                  child: const Icon(Icons.edit_note, color: Color(0xFFE65C00), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isNotEmpty ? name : 'Unnamed Member',
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Phone: $phone',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Seat: $seat • Shift: $shift',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEDD5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'DRAFT',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFC2410C)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Saved: ${date.day}/${date.month}/${date.year}',
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[400]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final confirm = await _showCustomConfirmDialog(
                          context: context,
                          title: 'Delete Draft?',
                          content: 'Are you sure you want to permanently delete this member registration draft?',
                          confirmLabel: 'Delete',
                          cancelLabel: 'Cancel',
                          icon: Icons.delete_outline,
                        );

                        if (confirm == true) {
                          await DraftService.instance.deleteDraft(draft.id!, widget.libraryId);
                          _fetchDrafts();
                        }
                      },
                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      label: const Text('Delete', style: TextStyle(fontSize: 12, color: Colors.red)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isProfileComplete ? () {
                        Navigator.pushNamed(
                          context,
                          '/admin/member/add',
                          arguments: {'libraryId': widget.libraryId == 'all' ? draft.libraryId : widget.libraryId, 'draftId': draft.id},
                        ).then((result) {
                          if (result == true) {
                            _fetchMembers(isRefresh: true);
                          }
                          _fetchDrafts();
                        });
                      } : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Complete your profile first to register members', style: GoogleFonts.inter()),
                            backgroundColor: const Color(0xFFE65C00),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isProfileComplete ? const Color(0xFFE65C00) : const Color(0xFFE65C00).withValues(alpha: 0.5),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        minimumSize: Size.zero,
                      ),
                      child: Text(
                        'Continue',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberAvatar(String photo) {
    Widget fallback() {
      return const CircleAvatar(
        radius: 26,
        backgroundColor: Color(0xFFFFF7F0),
        child: Icon(Icons.person, color: Color(0xFFE65C00), size: 24),
      );
    }

    final trimmedPhoto = photo.trim();
    if (trimmedPhoto.isEmpty) return fallback();

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: trimmedPhoto,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        memCacheWidth: 200,
        placeholder: (context, url) => const CircleAvatar(
          radius: 26,
          backgroundColor: Color(0xFFFFF7F0),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE65C00)),
          ),
        ),
        errorWidget: (context, url, error) => fallback(),
      ),
    );
  }

  Widget _buildMemberCard(Map<String, dynamic> membership) {
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.01), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Stack(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              if (_isSelectMode) {
                setState(() {
                  if (isSelected) {
                    _selectedMemberIds.remove(memberId);
                  } else {
                    _selectedMemberIds.add(memberId);
                  }
                });
              } else {
                // Tapping the card opens the member's full profile.
                Navigator.pushNamed(context, '/admin/member', arguments: memberId)
                    .then((_) => _fetchMembers(isRefresh: true));
              }
            },
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 44, 8),
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
            : _buildMemberAvatar(photo),
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
                  Expanded(
                    child: Text(
                      shiftName,
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF6B7280)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
            ),
          ),
          // 3-dot menu pinned to the top-right corner of the card.
          if (!_isSelectMode)
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.more_vert, size: 20, color: Color(0xFF64748B)),
                visualDensity: VisualDensity.compact,
                onPressed: () => _showMemberActionsBottomSheet(membership),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF64748B),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredMembers = _getFilteredMembers();
    final List<MemberListItem> listItems = [];

    // Construct unified items list
    if (_activeFilter == 'All') {
      for (final draft in _draftsList) {
        listItems.add(MemberListItem.draft(draft));
      }
      for (final m in filteredMembers) {
        listItems.add(MemberListItem.member(m));
      }
    } else if (_activeFilter == 'Pending Drafts') {
      for (final draft in _draftsList) {
        listItems.add(MemberListItem.draft(draft));
      }
    } else if (_activeFilter == 'Expired') {
      final now = DateTime.now();
      final todayMidnight = DateTime(now.year, now.month, now.day);
      final sevenDaysLater = todayMidnight.add(const Duration(days: 7));
      
      final expiredPart = filteredMembers.where((m) => m['status'] == 'expired').toList();
      final expiringSoonPart = filteredMembers.where((m) {
        final status = m['status'] ?? '';
        if (status == 'expired') return false;
        final endDateStr = m['end_date'];
        if (endDateStr != null) {
          final endDate = DateTime.tryParse(endDateStr);
          if (endDate != null) {
            return endDate.isBefore(sevenDaysLater) && !endDate.isBefore(todayMidnight);
          }
        }
        return false;
      }).toList();

      expiringSoonPart.sort((a, b) {
        final dateA = DateTime.tryParse(a['end_date'] ?? '') ?? DateTime(2100);
        final dateB = DateTime.tryParse(b['end_date'] ?? '') ?? DateTime(2100);
        return dateA.compareTo(dateB);
      });

      if (expiredPart.isNotEmpty) {
        listItems.add(MemberListItem.header('Expired'));
        for (final m in expiredPart) {
          listItems.add(MemberListItem.member(m));
        }
      }

      if (expiringSoonPart.isNotEmpty) {
        String? lastDateStr;
        for (final m in expiringSoonPart) {
          final dateStr = m['end_date'];
          if (dateStr != null) {
            final dt = DateTime.tryParse(dateStr);
            if (dt != null) {
              final formattedDate = DateFormat('dd MMM').format(dt);
              final groupHeader = 'Expiring on $formattedDate';
              if (groupHeader != lastDateStr) {
                listItems.add(MemberListItem.header(groupHeader));
                lastDateStr = groupHeader;
              }
            }
          }
          listItems.add(MemberListItem.member(m));
        }
      }
    } else {
      for (final m in filteredMembers) {
        listItems.add(MemberListItem.member(m));
      }
    }

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
                if (!_isSearching)
                  Row(
                    children: [
                      // Floor Selector dropdown
                      Expanded(
                        flex: 4,
                        child: _buildCustomPopupSelector(
                          label: 'FLOOR',
                          selectedId: _selectedFloorId,
                          items: _floors,
                          isFloor: true,
                          onChanged: (val) {
                            setState(() {
                              _selectedFloorId = val;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Shift Selector dropdown
                      Expanded(
                        flex: 5,
                        child: _buildCustomPopupSelector(
                          label: 'SHIFT',
                          selectedId: _selectedShiftId,
                          items: _shifts,
                          isFloor: false,
                          onChanged: (val) {
                            setState(() {
                              _selectedShiftId = val;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Search Icon
                      IconButton(
                        icon: const Icon(Icons.search, color: Color(0xFF6B7280)),
                        onPressed: () {
                          setState(() {
                            _isSearching = true;
                          });
                        },
                      ),

                      // Sort/Tune Icon
                      _buildSortMenuButton(),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            style: GoogleFonts.inter(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Search by name, phone...',
                              hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
                              prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                                onPressed: () {
                                  setState(() {
                                    _searchController.clear();
                                    _isSearching = false;
                                  });
                                },
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onChanged: (val) => setState(() {}),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildSortMenuButton(),
                    ],
                  ),
                const SizedBox(height: 12),

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
                      _buildFilterChip('Pending Drafts'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Title "Member List"
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 4),
            child: Text(
              'Member List',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1A2E),
              ),
            ),
          ),

          // 2. Members Scrollable List
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _fetchMembers(isRefresh: true),
              color: const Color(0xFFE65C00),
              child: _isLoading
                  ? Shimmer(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: 6,
                        itemBuilder: (context, index) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                const SkeletonBox(width: 52, height: 52, borderRadius: BorderRadius.all(Radius.circular(26))),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: const [
                                      SkeletonBox(width: 140, height: 16),
                                      SizedBox(height: 8),
                                      SkeletonBox(width: 80, height: 12),
                                      SizedBox(height: 6),
                                      SkeletonBox(width: 100, height: 12),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    )
                  : listItems.isEmpty
                      ? SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Container(
                            height: MediaQuery.of(context).size.height * 0.5,
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_outline_rounded, size: 64, color: Colors.grey[300]),
                                const SizedBox(height: 16),
                                Text('No members added yet', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                                const SizedBox(height: 8),
                                Text('Add your first member using the + button above.', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: listItems.length + (_hasMore ? 1 : 0),
                          itemBuilder: (ctx, index) {
                            if (index == listItems.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16.0),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
                                  ),
                                ),
                              );
                            }
                            
                            final item = listItems[index];
                            switch (item.type) {
                              case MemberListItemType.header:
                                return _buildSectionHeader(item.headerText!);
                              case MemberListItemType.draft:
                                return _buildDraftCard(item.draft!);
                              case MemberListItemType.member:
                                return _buildMemberCard(item.membership!);
                            }
                          },
                        ),
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
