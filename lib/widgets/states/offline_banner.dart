import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';

/// A slim "You're offline" bar. Use [OfflineBanner] when you already track the
/// offline state yourself, or wrap content in [ConnectivityBanner] to have it
/// appear/disappear automatically with connectivity changes.
class OfflineBanner extends StatelessWidget {
  final String message;

  const OfflineBanner({
    super.key,
    this.message = "You're offline — showing saved data",
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.warningBg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.orangeText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps [child] and shows an [OfflineBanner] above it whenever the device loses
/// connectivity. Drop it at the top of a screen body:
///
/// ```dart
/// body: ConnectivityBanner(child: _buildContent()),
/// ```
class ConnectivityBanner extends StatefulWidget {
  final Widget child;
  final String message;

  const ConnectivityBanner({
    super.key,
    required this.child,
    this.message = "You're offline — showing saved data",
  });

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final result = await _connectivity.checkConnectivity();
      if (mounted) setState(() => _offline = _isOffline(result));
    } catch (_) {/* assume online if the check fails */}
    _sub = _connectivity.onConnectivityChanged.listen((result) {
      if (mounted) setState(() => _offline = _isOffline(result));
    });
  }

  bool _isOffline(List<ConnectivityResult> result) {
    return result.isEmpty || result.every((r) => r == ConnectivityResult.none);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _offline ? OfflineBanner(message: widget.message) : const SizedBox.shrink(),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
