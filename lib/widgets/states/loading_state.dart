import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import 'shimmer_box.dart';

/// Shape of skeleton to render while data loads.
enum SkeletonKind {
  /// A vertical list of card rows (default for most list screens).
  list,

  /// A grid of small cards / stat tiles.
  cards,

  /// A simple centered spinner (use for short or unknown-shape waits).
  spinner,
}

/// Honest loading placeholder. Prefer a skeleton ([SkeletonKind.list] /
/// [SkeletonKind.cards]) over a bare spinner on content-heavy screens so the
/// wait feels shorter and the layout doesn't jump when data arrives.
///
/// ```dart
/// if (_loading) return const LoadingState();              // list skeleton
/// if (_loading) return const LoadingState(kind: SkeletonKind.spinner);
/// ```
class LoadingState extends StatelessWidget {
  final SkeletonKind kind;
  final int itemCount;
  final String? message;
  final EdgeInsetsGeometry padding;

  const LoadingState({
    super.key,
    this.kind = SkeletonKind.list,
    this.itemCount = 6,
    this.message,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case SkeletonKind.spinner:
        return _Spinner(message: message);
      case SkeletonKind.cards:
        return Shimmer(
          child: Padding(
            padding: padding,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: itemCount,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
              ),
              itemBuilder: (_, _) => const SkeletonBox(
                height: double.infinity,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
          ),
        );
      case SkeletonKind.list:
        return Shimmer(
          child: ListView.separated(
            padding: padding,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: itemCount,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, _) => const _SkeletonRow(),
          ),
        );
    }
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const SkeletonBox(
            width: 48,
            height: 48,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 160, height: 13),
                SizedBox(height: 10),
                SkeletonBox(width: 100, height: 11),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const SkeletonBox(width: 40, height: 24),
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  final String? message;
  const _Spinner({this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 14),
            Text(
              message!,
              style: GoogleFonts.inter(fontSize: 13.5, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
