import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/time_utils.dart';
import 'layout_sub_tab.dart';
import 'members_sub_tab.dart';
import 'requests_sub_tab.dart';
import 'archive_sub_tab.dart';

class ReservationsTab extends StatefulWidget {
  final String? libraryId;
  final String libraryName;
  final String? libraryCover;
  final List<Map<String, dynamic>> myLibraries;
  final Function(String) onLibraryChanged;

  final int initialSubTab;

  const ReservationsTab({
    super.key,
    required this.libraryId,
    required this.libraryName,
    required this.libraryCover,
    required this.myLibraries,
    required this.onLibraryChanged,
    this.initialSubTab = 0,
  });

  @override
  State<ReservationsTab> createState() => _ReservationsTabState();
}

class _ReservationsTabState extends State<ReservationsTab> with AutomaticKeepAliveClientMixin {
  final supabase = Supabase.instance.client;

  int _activeSubTab = 0; // 0: Layout, 1: Members, 2: Requests, 3: Archive

  // Lazily-built sub-tabs: a heavy tab (e.g. the 4800-line Layout grid) is only
  // mounted once it has been visited, then kept alive. Saves memory/first-build
  // cost on low-end phones when the user lands directly on another tab.
  final Set<int> _builtTabs = {};

  // Header badges
  int _unreadNotifications = 0; // header bell badge
  int _pendingRequestsCount = 0; // "Requests" sub-tab badge (join + seat-change + hold)

  final List<String> _subTabNames = [
    'Layout',
    'Members',
    'Requests',
    'Archive',
  ];

  // Library switching state
  late List<Map<String, dynamic>> _myLibraries;
  String? _selectedLibraryId;
  late String _selectedLibraryName;
  String? _selectedLibraryCover;

  // Global key to invoke Manage Layout bottom sheet on LayoutSubTab
  final GlobalKey<LayoutSubTabState> _layoutSubTabKey =
      GlobalKey<LayoutSubTabState>();

  @override
  void initState() {
    super.initState();
    _activeSubTab = widget.initialSubTab;
    _builtTabs.add(_activeSubTab);
    _selectedLibraryId = widget.libraryId;
    _selectedLibraryName = widget.libraryName;
    _selectedLibraryCover = widget.libraryCover;
    _myLibraries = widget.myLibraries;
    _loadBadges();
  }

  @override
  void didUpdateWidget(covariant ReservationsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSubTab != widget.initialSubTab) {
      setState(() {
        _activeSubTab = widget.initialSubTab;
        _builtTabs.add(_activeSubTab);
      });
    }
    if (oldWidget.libraryId != widget.libraryId ||
        oldWidget.libraryName != widget.libraryName ||
        oldWidget.libraryCover != widget.libraryCover ||
        oldWidget.myLibraries != widget.myLibraries) {
      setState(() {
        _selectedLibraryId = widget.libraryId;
        _selectedLibraryName = widget.libraryName;
        _selectedLibraryCover = widget.libraryCover;
        _myLibraries = widget.myLibraries;
      });
      _loadBadges();
      // Trigger a refresh on LayoutSubTab state
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _layoutSubTabKey.currentState?.refresh();
      });
    }
  }

  // ── Header badge counts (bell + pending requests) ──────────────────────────
  Future<void> _loadBadges() async {
    await Future.wait([_loadUnreadNotifications(), _loadPendingRequestsCount()]);
  }

  Future<void> _loadUnreadNotifications() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final rows = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', user.id)
          .isFilter('read_at', null);
      if (mounted) setState(() => _unreadNotifications = (rows as List).length);
    } catch (e) {
      debugPrint('Reservations: unread notifications load failed: $e');
    }
  }

  Future<void> _loadPendingRequestsCount() async {
    final libId = _selectedLibraryId;
    if (libId == null || libId.isEmpty || libId == 'null') return;
    try {
      final results = await Future.wait([
        supabase.from('join_requests').select('id').eq('library_id', libId).eq('status', 'pending'),
        supabase.from('seat_change_requests').select('id').eq('library_id', libId).eq('status', 'pending'),
        supabase.from('hold_requests').select('id').eq('library_id', libId).eq('status', 'pending'),
      ]);
      final total = results.fold<int>(0, (sum, r) => sum + (r as List).length);
      if (mounted) setState(() => _pendingRequestsCount = total);
    } catch (e) {
      debugPrint('Reservations: pending requests count load failed: $e');
    }
  }

  void _showLibrarySwitcherPopup(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Library Switcher',
      // ignore: deprecated_member_use
      barrierColor: Colors.black.withValues(alpha: 0.15),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: const Alignment(-0.85, -0.72),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 280,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    // ignore: deprecated_member_use
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  ..._myLibraries.map((lib) {
                    final bool isSelected =
                        lib['id'].toString().toLowerCase() ==
                        (_selectedLibraryId ?? '').toString().toLowerCase();
                    final String? city = lib['address_city'];
                    final String? coverUrl = lib['cover_photo_url'];
                    final List<dynamic> photos = lib['photos'] ?? [];
                    String? itemCover;
                    if (coverUrl != null && coverUrl.isNotEmpty) {
                      itemCover = coverUrl;
                    } else if (photos.isNotEmpty) {
                      itemCover = photos.first.toString();
                    }

                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          _selectedLibraryId = lib['id'];
                          _selectedLibraryName = lib['name'] ?? 'Library';
                          _selectedLibraryCover = itemCover;
                        });
                        widget.onLibraryChanged(lib['id']);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFF1F5F9),
                              ),
                              child: itemCover != null && itemCover.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(20),
                                      child: CachedNetworkImage(
                                        imageUrl: itemCover,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 200,
                                        placeholder: (context, url) => const Center(
                                          child: CircularProgressIndicator(
                                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
                                            strokeWidth: 1.5,
                                          ),
                                        ),
                                        errorWidget:
                                            (context, url, error) =>
                                                const Icon(
                                                  Icons.business_rounded,
                                                  color: Color(0xFFE65C00),
                                                  size: 20,
                                                ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.business_rounded,
                                      color: Color(0xFFE65C00),
                                      size: 20,
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    lib['name'] ?? 'Library',
                                    style: GoogleFonts.outfit(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    city ?? 'Location',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check,
                                color: Color(0xFFE65C00),
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(
                        context,
                        '/admin/library/setup/1',
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.add,
                            color: Color(0xFFE65C00),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '+ Add Library',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFE65C00),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(opacity: anim1, child: child);
      },
    );
  }

  String _getLibraryAddress() {
    final selectedLib = _myLibraries.firstWhere(
      (lib) => lib['id']?.toString().toLowerCase() == _selectedLibraryId?.toString().toLowerCase(),
      orElse: () => <String, dynamic>{},
    );
    final String city = selectedLib['address_city'] ?? '';
    final String state = selectedLib['address_state'] ?? '';
    if (city.isNotEmpty && state.isNotEmpty) {
      return '$city, $state';
    } else if (city.isNotEmpty) {
      return city;
    } else if (state.isNotEmpty) {
      return state;
    }
    return 'Library Address';
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_selectedLibraryId == null || _selectedLibraryId!.isEmpty || _selectedLibraryId == 'null') {
      return Scaffold(
        backgroundColor: const Color(0xFFFBF5EE),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 64,
                  color: Color(0xFFE65C00),
                ),
                const SizedBox(height: 16),
                Text(
                  'Complete Library Setup First',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please finish your library setup steps on the Home tab to activate reservations management.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF6B7280),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final todayFormatted = DateFormat('EEE dd/MM').format(istNow()).toUpperCase();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        color: const Color(0xFFFBF5EE),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Orange Curved Header (Matching Admin Home & Screenshots exactly)
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                bottom: 32,
                left: 16,
                right: 16,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFFF6B00),
                    Color(0xFFE65C00),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Dynamic Library Switcher (Left Side) - matching Admin Home style but without address/location line underneath
                  Expanded(
                    child: Row(
                      children: [
                        // Circular avatar with actual library cover photo or default business icon fallback
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 2.0,
                            ),
                            color: Colors.white,
                          ),
                          child:
                              _selectedLibraryCover != null &&
                                  _selectedLibraryCover!.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(25),
                                  child: CachedNetworkImage(
                                    imageUrl: _selectedLibraryCover!,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 200,
                                    placeholder: (context, url) => const Center(
                                      child: CircularProgressIndicator(
                                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    errorWidget:
                                        (context, url, error) =>
                                            const Icon(
                                              Icons.business_rounded,
                                              color: Color(0xFFE65C00),
                                              size: 26,
                                            ),
                                  ),
                                )
                              : const Icon(
                                  Icons.business_rounded,
                                  color: Color(0xFFE65C00),
                                  size: 26,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () => _showLibrarySwitcherPopup(context),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _selectedLibraryName,
                                        style: GoogleFonts.outfit(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.keyboard_arrow_down,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ],
                                ),
                                Text(
                                  _getLibraryAddress(),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.95),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Header Right Side Actions (Date Pill + Notification Bell)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5),
                        width: 1.0,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          todayFormatted,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),

                  // Notification Bell (consistent with Admin Home)
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.notifications_none_rounded,
                          color: Colors.white.withValues(alpha: 0.9),
                          size: 26,
                        ),
                        onPressed: () async {
                          await Navigator.pushNamed(
                            context,
                            '/member/notifications',
                          );
                          _loadUnreadNotifications();
                        },
                      ),
                      if (_unreadNotifications > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white, width: 1.4),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _unreadNotifications > 9 ? '9+' : '$_unreadNotifications',
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // 2. White Horizontal Sub-tabs (Layout, Members, Requests, Archive)
            Container(
              color: Colors.white,
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(_subTabNames.length, (index) {
                  final bool isActive = _activeSubTab == index;
                  // Pending-count badge for the "Requests" sub-tab (index 2).
                  final bool showBadge = index == 2 && _pendingRequestsCount > 0;
                  return Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _activeSubTab = index;
                          _builtTabs.add(index);
                        });
                        if (index == 0) {
                          _layoutSubTabKey.currentState?.refresh();
                        }
                        // Keep header badges fresh as the admin moves around.
                        _loadBadges();
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _subTabNames[index],
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: isActive
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isActive
                                      ? const Color(0xFFE65C00)
                                      : const Color(0xFF6B7280),
                                ),
                              ),
                              if (showBadge) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  constraints: const BoxConstraints(minWidth: 16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _pendingRequestsCount > 9 ? '9+' : '$_pendingRequestsCount',
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 3,
                            width: isActive ? 48 : 0,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE65C00),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),

            // 3. Active Sub-tab View Container
            Expanded(
              child: Container(
                color: const Color(
                  0xFFFBF5EE,
                ), // Warm cream background for sub-tab contents
                child: IndexedStack(
                  index: _activeSubTab,
                  children: [
                    _builtTabs.contains(0)
                        ? LayoutSubTab(
                            key: _layoutSubTabKey,
                            libraryId: _selectedLibraryId!,
                          )
                        : const SizedBox.shrink(), // Layout Sub-tab (lazy)
                    _builtTabs.contains(1)
                        ? MembersSubTab(
                            libraryId: _selectedLibraryId!,
                            ownedLibraryCount: _myLibraries.length,
                          )
                        : const SizedBox.shrink(), // Members Sub-tab (lazy)
                    _builtTabs.contains(2)
                        ? RequestsSubTab(
                            key: ValueKey('requests_tab_${_activeSubTab == 2}_$_selectedLibraryId'),
                            libraryId: _selectedLibraryId!,
                          )
                        : const SizedBox.shrink(), // Requests Sub-tab (lazy)
                    _builtTabs.contains(3)
                        ? ArchiveSubTab(
                            libraryId: _selectedLibraryId!,
                          )
                        : const SizedBox.shrink(), // Archive Sub-tab (lazy)
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
