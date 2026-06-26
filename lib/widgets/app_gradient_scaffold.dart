import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// A Scaffold with the brand's curved orange-gradient header — the single,
/// consistent header used across every admin sub-screen (Subscription, Shifts,
/// Exports, Audit Log, etc.) so they all share the same identity as the main
/// tabs instead of each rolling its own flat AppBar.
///
/// Replaces the old `Scaffold(appBar: AppBar(...))` pattern. Pass the page
/// [title], the [body], and optionally [actions] (rendered on the right of the
/// header), a [floatingActionButton] and a [bottomNavigationBar].
class AppGradientScaffold extends StatelessWidget {
  final String title;
  final Widget body;

  /// Optional right-aligned header actions (e.g. an icon button). Rendered in
  /// white to sit on the gradient.
  final List<Widget>? actions;

  final bool showBack;
  final VoidCallback? onBack;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;

  /// Optional widget pinned just under the title, still inside the gradient
  /// (e.g. a subtitle or a small tab strip).
  final Widget? headerBottom;

  const AppGradientScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.showBack = true,
    this.onBack,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.headerBottom,
  });

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: context.palette.scaffold,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        bottomNavigationBar: bottomNavigationBar,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 14,
        bottom: 18,
        left: 8,
        right: 8,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (showBack)
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                )
              else
                const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              if (actions != null) ...actions! else const SizedBox(width: 8),
            ],
          ),
          if (headerBottom != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: headerBottom!,
            ),
          ],
        ],
      ),
    );
  }
}
