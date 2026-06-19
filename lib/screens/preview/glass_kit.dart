import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Midnight Focus (V2) design tokens + glassmorphism building blocks.
/// PREVIEW ONLY — isolated from the live (Warm Sunrise) screens.
class Midnight {
  static const bg0 = Color(0xFF0B0E14); // deepest
  static const bg1 = Color(0xFF121826); // gradient end
  static const textPrimary = Color(0xFFF1F5F9);
  static const textSecondary = Color(0xFF94A3B8);
  static const textFaint = Color(0xFF64748B);

  // Accent gradient (violet → cyan) used for glows, rings, primary CTAs.
  static const accentA = Color(0xFF7C5CFF);
  static const accentB = Color(0xFF22D3EE);
  static const success = Color(0xFF34D399);
  static const danger = Color(0xFFFB7185);

  static const LinearGradient accent = LinearGradient(
    colors: [accentA, accentB],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static TextStyle head(double size, {FontWeight w = FontWeight.w700, Color? c}) =>
      GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: w, color: c ?? textPrimary);
  static TextStyle body(double size, {FontWeight w = FontWeight.w500, Color? c}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? textSecondary);
}

/// Full-screen dark gradient background with soft blurred colour "blobs" that
/// give the premium glassmorphism glow. Put content on top via [child].
class MidnightBackground extends StatelessWidget {
  final Widget child;
  const MidnightBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Midnight.bg0, Midnight.bg1],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          Positioned(top: -90, left: -70, child: _blob(Midnight.accentA.withValues(alpha: 0.35), 240)),
          Positioned(top: 120, right: -90, child: _blob(Midnight.accentB.withValues(alpha: 0.22), 220)),
          Positioned(bottom: -110, left: 30, child: _blob(Midnight.accentA.withValues(alpha: 0.16), 260)),
          child,
        ],
      ),
    );
  }

  Widget _blob(Color c, double size) => IgnorePointer(
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
          ),
        ),
      );
}

/// A frosted-glass card: blur + translucent fill + hairline border.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Gradient? border;
  final VoidCallback? onTap;
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.border,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}

/// A gradient progress ring (e.g., setup 4/4) drawn with a sweep gradient.
class GradientRing extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final Widget center;
  const GradientRing({super.key, required this.value, this.size = 84, required this.center});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(value),
        child: Center(child: center),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  _RingPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const stroke = 9.0;
    final inset = rect.deflate(stroke / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.10);
    canvas.drawArc(inset, 0, 6.28318, false, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [Midnight.accentA, Midnight.accentB, Midnight.accentA],
      ).createShader(inset);
    canvas.drawArc(inset, -1.5708, 6.28318 * value.clamp(0.0, 1.0), false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.value != value;
}
