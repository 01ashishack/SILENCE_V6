import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AddMemberModeSelection extends StatefulWidget {
  final String? selectedMode;
  final ValueChanged<String> onModeSelected;
  final VoidCallback? onContinue;

  const AddMemberModeSelection({
    super.key,
    required this.selectedMode,
    required this.onModeSelected,
    this.onContinue,
  });

  @override
  State<AddMemberModeSelection> createState() => _AddMemberModeSelectionState();
}

class _AddMemberModeSelectionState extends State<AddMemberModeSelection> {
  String? _hoveredMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFBF5EE),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Icon
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE65C00).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_add,
                      size: 36,
                      color: Color(0xFFE65C00),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  Text(
                    'Choose Registration Mode',
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A1A2E),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select standard mode or pre-existing member mode\nto configure registration options.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF6B7280),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),

                  // New Member Card
                  _ModeCard(
                    mode: 'new',
                    selectedMode: widget.selectedMode,
                    hoveredMode: _hoveredMode,
                    icon: Icons.person_add_alt_1,
                    iconBg: const Color(0xFFDCFCE7),
                    iconColor: const Color(0xFF16A34A),
                    title: 'New Member',
                    subtitle: 'Standard flow (trial days allowed, digital payment requests allowed).',
                    onTap: () {
                      widget.onModeSelected('new');
                    },
                    onHover: (hovered) {
                      setState(() => _hoveredMode = hovered ? 'new' : null);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Existing Member Card
                  _ModeCard(
                    mode: 'existing',
                    selectedMode: widget.selectedMode,
                    hoveredMode: _hoveredMode,
                    icon: Icons.history,
                    iconBg: const Color(0xFFDBEAFE),
                    iconColor: const Color(0xFF2563EB),
                    title: 'Existing Member',
                    subtitle: 'Already studying at the library. Past joining date required. No trials, immediate cash/UPI payment.',
                    onTap: () {
                      widget.onModeSelected('existing');
                    },
                    onHover: (hovered) {
                      setState(() => _hoveredMode = hovered ? 'existing' : null);
                    },
                  ),
                ],
              ),
            ),
          ),

          // Bottom Continue Button
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: widget.selectedMode != null ? widget.onContinue : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE5E7EB),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Continue',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: widget.selectedMode != null ? Colors.white : const Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String mode;
  final String? selectedMode;
  final String? hoveredMode;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  const _ModeCard({
    required this.mode,
    required this.selectedMode,
    required this.hoveredMode,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedMode == mode;

    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFE65C00) : const Color(0xFFE5E7EB),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isSelected ? 0.08 : 0.04),
              blurRadius: isSelected ? 16 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            splashColor: const Color(0xFFE65C00).withValues(alpha: 0.05),
            highlightColor: const Color(0xFFE65C00).withValues(alpha: 0.03),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon circle
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: iconBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: iconColor, size: 24),
                  ),
                  const SizedBox(width: 14),

                  // Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1A1A2E),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: const Color(0xFF6B7280),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Checkmark
                  AnimatedOpacity(
                    opacity: isSelected ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE65C00),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, color: Colors.white, size: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
