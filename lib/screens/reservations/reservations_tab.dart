import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
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

  const ReservationsTab({
    super.key,
    required this.libraryId,
    required this.libraryName,
    required this.libraryCover,
    required this.myLibraries,
    required this.onLibraryChanged,
  });

  @override
  State<ReservationsTab> createState() => _ReservationsTabState();
}

class _ReservationsTabState extends State<ReservationsTab> {
  int _activeSubTab = 0; // 0: Layout, 1: Members, 2: Requests, 3: Archive

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
    _selectedLibraryId = widget.libraryId;
    _selectedLibraryName = widget.libraryName;
    _selectedLibraryCover = widget.libraryCover;
    _myLibraries = widget.myLibraries;
  }

  @override
  void didUpdateWidget(covariant ReservationsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    }
  }

  void _showLibrarySwitcherPopup(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Library Switcher',
      // ignore: deprecated_member_use
      barrierColor: Colors.black.withOpacity(0.15),
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
                    color: Colors.black.withOpacity(0.12),
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
                                      child: Image.network(
                                        itemCover,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
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

  @override
  Widget build(BuildContext context) {
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

    final todayFormatted = DateFormat(
      'EEE, d MMM',
    ).format(DateTime.now()).toUpperCase();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(
          0xFFE65C00,
        ), // Matching top status bar perfectly
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Orange Curved Header (Matching Admin Home & Screenshots exactly)
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 12,
                bottom: 24,
                left: 16,
                right: 16,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFF6B00), // Vibrant Bright Orange
                    Color(0xFFE65C00), // Primary Brand Orange
                  ],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
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
                                  child: Image.network(
                                    _selectedLibraryCover!,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
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
                            child: Row(
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
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Header Right Side Actions
                  _activeSubTab == 0
                      ? ElevatedButton.icon(
                          onPressed: () {
                            // Trigger S071 Bottom Sheet on the active LayoutSubTab State
                            _layoutSubTabKey.currentState
                                ?.showManageLayoutBottomSheet();
                          },
                          icon: const Icon(
                            Icons.settings,
                            size: 14,
                            color: Color(0xFFE65C00),
                          ),
                          label: Text(
                            'Manage Layout',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFE65C00),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFFE65C00),
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        )
                      : Row(
                          children: [
                            // Date Pill
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.5),
                                  width: 1.0,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                color: Colors.white.withOpacity(0.12),
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
                            const SizedBox(width: 8),
                            // Bell Icon
                            Icon(
                              Icons.notifications_none_rounded,
                              color: Colors.white.withOpacity(0.9),
                              size: 20,
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
                  return Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _activeSubTab = index;
                        });
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
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
                    LayoutSubTab(
                      key: _layoutSubTabKey,
                      libraryId: _selectedLibraryId!,
                    ), // Layout Sub-tab
                    MembersSubTab(
                      libraryId: _selectedLibraryId!,
                    ), // Members Sub-tab
                    RequestsSubTab(
                      libraryId: _selectedLibraryId!,
                    ), // Requests Sub-tab
                    ArchiveSubTab(
                      libraryId: _selectedLibraryId!,
                    ), // Archive Sub-tab
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
