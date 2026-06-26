import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../utils/error_messages.dart';

/// Honest error state with a friendly message and a Retry action. Pass the raw
/// [error] (so the right network-vs-generic copy is chosen) or an explicit
/// [message]. Never render a raw `$e` here.
///
/// ```dart
/// if (_error != null) {
///   return ErrorState(error: _error, onRetry: _load);
/// }
/// ```
class ErrorState extends StatelessWidget {
  final Object? error;
  final String? message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final EdgeInsetsGeometry padding;

  const ErrorState({
    super.key,
    this.error,
    this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.padding = const EdgeInsets.all(32),
  });

  @override
  Widget build(BuildContext context) {
    final offline = isNetworkError(error);
    final text = message ?? friendlyError(error);

    return Center(
      child: SingleChildScrollView(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.dangerBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
                size: 34,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              offline ? "You're offline" : 'Something went wrong',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: context.palette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                height: 1.45,
                color: context.palette.textMuted,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  retryLabel,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
