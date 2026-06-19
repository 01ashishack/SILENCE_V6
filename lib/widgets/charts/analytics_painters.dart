// Chart painters for the Admin Analytics tab.
// Extracted from admin_analytics_tab.dart for maintainability — pure rendering,
// no business logic. Each painter's shouldRepaint compares its inputs by
// reference so charts only repaint when their data actually changes.
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Builds a smooth Catmull-Rom (cubic bezier) path through the given points,
// for premium-looking line charts instead of jagged straight segments.
Path smoothLinePath(List<Offset> pts) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  if (pts.length < 3) {
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    return path;
  }
  for (int i = 0; i < pts.length - 1; i++) {
    final p0 = i == 0 ? pts[i] : pts[i - 1];
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = (i + 2 < pts.length) ? pts[i + 2] : p2;
    final cp1 = Offset(p1.dx + (p2.dx - p0.dx) / 6.0, p1.dy + (p2.dy - p0.dy) / 6.0);
    final cp2 = Offset(p2.dx - (p3.dx - p1.dx) / 6.0, p2.dy - (p3.dy - p1.dy) / 6.0);
    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
  }
  return path;
}

// Custom Painter for Interactive Line Chart
class LineChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final int? selectedIndex;

  LineChartPainter({
    required this.values,
    required this.labels,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final double maxVal = values.reduce((a, b) => a > b ? a : b);
    final double minVal = 0.0;
    final double valRange = maxVal == minVal ? 1.0 : maxVal - minVal;

    final double paddingX = 40.0;
    final double paddingY = 20.0;
    final double width = size.width - paddingX * 2;
    final double height = size.height - paddingY * 2;

    final int pointsCount = values.length;
    final double stepX = pointsCount > 1 ? width / (pointsCount - 1) : width;

    // Draw grid lines
    final Paint gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1.0;

    final int gridLinesCount = 4;
    for (int i = 0; i <= gridLinesCount; i++) {
      final double y = paddingY + height * (1 - i / gridLinesCount);
      canvas.drawLine(Offset(paddingX, y), Offset(paddingX + width, y), gridPaint);
      
      final double gridVal = minVal + valRange * (i / gridLinesCount);
      final TextSpan span = TextSpan(
        style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF94A3B8)),
        text: '₹${gridVal.toStringAsFixed(0)}',
      );
      final TextPainter tp = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(paddingX - tp.width - 5, y - tp.height / 2));
    }

    // Draw lines & area gradient
    final List<Offset> points = [];
    for (int i = 0; i < pointsCount; i++) {
      final double x = paddingX + i * stepX;
      final double y = paddingY + height * (1 - (values[i] - minVal) / valRange);
      points.add(Offset(x, y));
    }

    if (points.isNotEmpty) {
      final Path linePath = smoothLinePath(points);

      final Path areaPath = Path.from(linePath)
        ..lineTo(points.last.dx, paddingY + height)
        ..lineTo(points.first.dx, paddingY + height)
        ..close();

      final Paint areaPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(paddingX, paddingY),
          Offset(paddingX, paddingY + height),
          const [
            Color(0xFFFFEADF),
            Color(0xFFFFF7F4),
            Colors.white,
          ],
        );
      canvas.drawPath(areaPath, areaPaint);

      final Paint linePaint = Paint()
        ..color = const Color(0xFFE65C00)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      canvas.drawPath(linePath, linePaint);

      final Paint pointPaint = Paint()
        ..color = const Color(0xFFE65C00)
        ..style = PaintingStyle.fill;

      final Paint outerRingPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      final Paint ringBorderPaint = Paint()
        ..color = const Color(0xFFE65C00)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < points.length; i++) {
        final p = points[i];
        final bool isSelected = selectedIndex == i;

        if (isSelected) {
          canvas.drawCircle(p, 6.0, outerRingPaint);
          canvas.drawCircle(p, 6.0, ringBorderPaint);
          canvas.drawCircle(p, 3.0, pointPaint);

          final TextSpan tooltipSpan = TextSpan(
            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
            text: '₹${values[i].toStringAsFixed(0)}',
          );
          final TextPainter tooltipTp = TextPainter(
            text: tooltipSpan,
            textDirection: TextDirection.ltr,
          )..layout();

          final RRect tooltipRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(
              p.dx - tooltipTp.width / 2 - 6,
              p.dy - tooltipTp.height - 12,
              tooltipTp.width + 12,
              tooltipTp.height + 6,
            ),
            const Radius.circular(6),
          );

          final Paint tooltipBg = Paint()..color = const Color(0xFF1E293B);
          canvas.drawRRect(tooltipRect, tooltipBg);
          tooltipTp.paint(canvas, Offset(p.dx - tooltipTp.width / 2, p.dy - tooltipTp.height - 9));
        } else {
          if (pointsCount < 10 || i % 2 == 0 || i == pointsCount - 1) {
            canvas.drawCircle(p, 3.0, pointPaint);
          }
        }
      }
    }

    // Draw X labels
    for (int i = 0; i < pointsCount; i++) {
      if (pointsCount > 7 && i % 3 != 0 && i != pointsCount - 1) continue;
      final p = points[i];
      final TextSpan span = TextSpan(
        style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF64748B)),
        text: labels[i],
      );
      final TextPainter tp = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p.dx - tp.width / 2, paddingY + height + 5));
    }
  }

  @override
  bool shouldRepaint(covariant LineChartPainter oldDelegate) => oldDelegate.values != values || oldDelegate.labels != labels || oldDelegate.selectedIndex != selectedIndex;
}

// Custom Painter for Donut Chart
class DonutChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final List<Color> colors;

  DonutChartPainter({
    required this.values,
    required this.labels,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double total = values.fold(0.0, (sum, val) => sum + val);
    final center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width < size.height ? size.width / 2 - 10 : size.height / 2 - 10;
    final double innerRadius = radius * 0.65;

    if (total == 0.0) {
      final Paint emptyPaint = Paint()
        ..color = const Color(0xFFE2E8F0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius - innerRadius;
      canvas.drawCircle(center, (radius + innerRadius) / 2, emptyPaint);
      return;
    }

    double startAngle = -3.14159 / 2;
    final rect = Rect.fromCircle(center: center, radius: (radius + innerRadius) / 2);

    for (int i = 0; i < values.length; i++) {
      final double val = values[i];
      if (val == 0.0) continue;

      final double sweepAngle = 2 * 3.14159 * (val / total);
      
      final Paint paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius - innerRadius
        ..strokeCap = StrokeCap.square;

      canvas.drawArc(rect, startAngle + 0.02, sweepAngle - 0.04, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant DonutChartPainter oldDelegate) => oldDelegate.values != values || oldDelegate.labels != labels || oldDelegate.colors != colors;
}

// Custom Painter for Grouped Revenue Bar Chart
class BarChartPainter extends CustomPainter {
  final List<double> shiftValues;
  final List<String> shiftLabels;
  final List<double> planValues;
  final List<String> planLabels;

  BarChartPainter({
    required this.shiftValues,
    required this.shiftLabels,
    required this.planValues,
    required this.planLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double paddingX = 40.0;
    final double paddingY = 20.0;
    final double width = size.width - paddingX * 2;
    final double height = size.height - paddingY * 2;

    final Paint gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1.0;

    final double maxVal = [
      ...shiftValues,
      ...planValues,
      1000.0,
    ].reduce((a, b) => a > b ? a : b);

    for (int i = 0; i <= 4; i++) {
      final double y = paddingY + height * (1 - i / 4);
      canvas.drawLine(Offset(paddingX, y), Offset(paddingX + width, y), gridPaint);

      final double gridVal = maxVal * (i / 4);
      final TextSpan span = TextSpan(
        style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF94A3B8)),
        text: '₹${gridVal.toStringAsFixed(0)}',
      );
      final TextPainter tp = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(paddingX - tp.width - 5, y - tp.height / 2));
    }

    final double halfWidth = width / 2;
    
    // Draw shifts bars (left half)
    if (shiftValues.isNotEmpty) {
      final double barSpaceWidth = halfWidth / (shiftValues.length + 1);
      final double barWidth = barSpaceWidth * 0.6;
      final Paint shiftPaint = Paint()..color = const Color(0xFFE65C00);

      for (int i = 0; i < shiftValues.length; i++) {
        final double val = shiftValues[i];
        final double barHeight = (val / maxVal) * height;
        final double x = paddingX + barSpaceWidth * (i + 1) - barWidth / 2;
        final double y = paddingY + height - barHeight;

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, barWidth, barHeight),
            const Radius.circular(4),
          ),
          shiftPaint,
        );

        final TextSpan labelSpan = TextSpan(
          style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF64748B)),
          text: shiftLabels[i],
        );
        final TextPainter labelTp = TextPainter(
          text: labelSpan,
          textDirection: TextDirection.ltr,
        )..layout();
        labelTp.paint(canvas, Offset(x + barWidth / 2 - labelTp.width / 2, paddingY + height + 5));
      }
    }

    // Draw plans bars (right half)
    if (planValues.isNotEmpty) {
      final double barSpaceWidth = halfWidth / (planValues.length + 1);
      final double barWidth = barSpaceWidth * 0.6;
      final Paint planPaint = Paint()..color = const Color(0xFF0F172A);

      for (int i = 0; i < planValues.length; i++) {
        final double val = planValues[i];
        final double barHeight = (val / maxVal) * height;
        final double x = paddingX + halfWidth + barSpaceWidth * (i + 1) - barWidth / 2;
        final double y = paddingY + height - barHeight;

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, barWidth, barHeight),
            const Radius.circular(4),
          ),
          planPaint,
        );

        final TextSpan labelSpan = TextSpan(
          style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF64748B)),
          text: planLabels[i],
        );
        final TextPainter labelTp = TextPainter(
          text: labelSpan,
          textDirection: TextDirection.ltr,
        )..layout();
        labelTp.paint(canvas, Offset(x + barWidth / 2 - labelTp.width / 2, paddingY + height + 5));
      }
    }
  }

  @override
  bool shouldRepaint(covariant BarChartPainter oldDelegate) => oldDelegate.shiftValues != shiftValues || oldDelegate.shiftLabels != shiftLabels || oldDelegate.planValues != planValues || oldDelegate.planLabels != planLabels;
}

class AttendanceLeaderboardPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;

  AttendanceLeaderboardPainter({required this.values, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final double maxVal = values.reduce((a, b) => a > b ? a : b);
    final double maxBarWidth = size.width - 120;
    final double rowHeight = size.height / values.length;

    final Paint barPaint = Paint()
      ..color = const Color(0xFFE65C00)
      ..style = PaintingStyle.fill;

    final Paint bgPaint = Paint()
      ..color = const Color(0xFFFFF7ED)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < values.length; i++) {
      final double val = values[i];
      final String label = labels[i];
      final double barWidth = maxVal == 0 ? 0 : (val / maxVal) * maxBarWidth;

      final double y = i * rowHeight + rowHeight * 0.2;
      final double h = rowHeight * 0.6;

      final TextSpan labelSpan = TextSpan(
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
        text: label,
      );
      final TextPainter labelTp = TextPainter(
        text: labelSpan,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 80);
      labelTp.paint(canvas, Offset(0, y + (h - labelTp.height) / 2));

      final RRect bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(85, y, maxBarWidth, h),
        const Radius.circular(6),
      );
      canvas.drawRRect(bgRect, bgPaint);

      if (barWidth > 0) {
        final RRect filledRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(85, y, barWidth, h),
          const Radius.circular(6),
        );
        canvas.drawRRect(filledRect, barPaint);
      }

      final TextSpan valSpan = TextSpan(
        style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
        text: '${val.toStringAsFixed(1)}h',
      );
      final TextPainter valTp = TextPainter(
        text: valSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      valTp.paint(canvas, Offset(85 + barWidth + 8, y + (h - valTp.height) / 2));
    }
  }

  @override
  bool shouldRepaint(covariant AttendanceLeaderboardPainter oldDelegate) => oldDelegate.values != values || oldDelegate.labels != labels;
}

class AttendanceTrendPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;

  AttendanceTrendPainter({required this.values, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final double maxVal = [...values, 5.0].reduce((a, b) => a > b ? a : b);
    final double paddingX = 30.0;
    final double paddingY = 20.0;
    final double width = size.width - paddingX * 2;
    final double height = size.height - paddingY * 2;

    final Paint gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 4; i++) {
      final double y = paddingY + height * (1 - i / 4);
      canvas.drawLine(Offset(paddingX, y), Offset(paddingX + width, y), gridPaint);

      final double gridVal = maxVal * (i / 4);
      final TextSpan span = TextSpan(
        style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF94A3B8)),
        text: gridVal.toStringAsFixed(0),
      );
      final TextPainter tp = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(paddingX - tp.width - 5, y - tp.height / 2));
    }

    final double barSpaceWidth = width / (values.length + 1);
    final double barWidth = (barSpaceWidth * 0.6).clamp(8.0, 32.0);
    final Paint barPaint = Paint()..color = const Color(0xFFE65C00);

    for (int i = 0; i < values.length; i++) {
      final double val = values[i];
      final double barHeight = (val / maxVal) * height;
      final double x = paddingX + barSpaceWidth * (i + 1) - barWidth / 2;
      final double y = paddingY + height - barHeight;

      if (barHeight > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, barWidth, barHeight),
            const Radius.circular(4),
          ),
          barPaint,
        );
      }

      final TextSpan labelSpan = TextSpan(
        style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF64748B)),
        text: labels[i],
      );
      final TextPainter labelTp = TextPainter(
        text: labelSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      labelTp.paint(canvas, Offset(x + barWidth / 2 - labelTp.width / 2, paddingY + height + 5));
    }
  }

  @override
  bool shouldRepaint(covariant AttendanceTrendPainter oldDelegate) => oldDelegate.values != values || oldDelegate.labels != labels;
}

class PeakHoursPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;

  PeakHoursPainter({required this.values, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final double maxVal = [...values, 1.0].reduce((a, b) => a > b ? a : b);
    final double maxBarWidth = size.width - 70;
    final double rowHeight = size.height / values.length;

    final Paint barPaint = Paint()
      ..color = const Color(0xFFE65C00)
      ..style = PaintingStyle.fill;

    final Paint bgPaint = Paint()
      ..color = const Color(0xFFFFF7ED)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < values.length; i++) {
      final double val = values[i];
      final String label = labels[i];
      final double barWidth = maxVal == 0 ? 0 : (val / maxVal) * maxBarWidth;

      final double y = i * rowHeight + rowHeight * 0.15;
      final double h = rowHeight * 0.7;

      final TextSpan labelSpan = TextSpan(
        style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
        text: label,
      );
      final TextPainter labelTp = TextPainter(
        text: labelSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      labelTp.paint(canvas, Offset(0, y + (h - labelTp.height) / 2));

      final RRect bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(50, y, maxBarWidth, h),
        const Radius.circular(4),
      );
      canvas.drawRRect(bgRect, bgPaint);

      if (barWidth > 0) {
        final RRect filledRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(50, y, barWidth, h),
          const Radius.circular(4),
        );
        canvas.drawRRect(filledRect, barPaint);
      }

      if (val > 0) {
        final TextSpan valSpan = TextSpan(
          style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
          text: val.toStringAsFixed(0),
        );
        final TextPainter valTp = TextPainter(
          text: valSpan,
          textDirection: TextDirection.ltr,
        )..layout();
        if (barWidth > valTp.width + 10) {
          valTp.paint(canvas, Offset(50 + barWidth - valTp.width - 5, y + (h - valTp.height) / 2));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant PeakHoursPainter oldDelegate) => oldDelegate.values != values || oldDelegate.labels != labels;
}

class ShiftOccupancyPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;

  ShiftOccupancyPainter({required this.values, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final double maxBarWidth = size.width - 120;
    final double rowHeight = size.height / values.length;

    final Paint barPaint = Paint()
      ..color = const Color(0xFFE65C00)
      ..style = PaintingStyle.fill;

    final Paint bgPaint = Paint()
      ..color = const Color(0xFFFFF7ED)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < values.length; i++) {
      final double val = values[i];
      final String label = labels[i];
      final double barWidth = (val / 100.0) * maxBarWidth;

      final double y = i * rowHeight + rowHeight * 0.2;
      final double h = rowHeight * 0.6;

      final TextSpan labelSpan = TextSpan(
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
        text: label,
      );
      final TextPainter labelTp = TextPainter(
        text: labelSpan,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 80);
      labelTp.paint(canvas, Offset(0, y + (h - labelTp.height) / 2));

      final RRect bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(85, y, maxBarWidth, h),
        const Radius.circular(6),
      );
      canvas.drawRRect(bgRect, bgPaint);

      if (barWidth > 0) {
        final RRect filledRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(85, y, barWidth, h),
          const Radius.circular(6),
        );
        canvas.drawRRect(filledRect, barPaint);
      }

      final TextSpan valSpan = TextSpan(
        style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
        text: '${val.toStringAsFixed(1)}%',
      );
      final TextPainter valTp = TextPainter(
        text: valSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      valTp.paint(canvas, Offset(85 + barWidth + 8, y + (h - valTp.height) / 2));
    }
  }

  @override
  bool shouldRepaint(covariant ShiftOccupancyPainter oldDelegate) => oldDelegate.values != values || oldDelegate.labels != labels;
}

class PlansDistributionPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final List<Color> colors;
  final int totalCount;

  PlansDistributionPainter({
    required this.values,
    required this.labels,
    required this.colors,
    required this.totalCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double total = values.fold(0.0, (sum, val) => sum + val);
    final center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width < size.height ? size.width / 2 - 10 : size.height / 2 - 10;
    final double innerRadius = radius * 0.65;

    if (total == 0.0) {
      final Paint emptyPaint = Paint()
        ..color = const Color(0xFFE2E8F0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius - innerRadius;
      canvas.drawCircle(center, (radius + innerRadius) / 2, emptyPaint);
      return;
    }

    double startAngle = -3.14159 / 2;
    final rect = Rect.fromCircle(center: center, radius: (radius + innerRadius) / 2);

    for (int i = 0; i < values.length; i++) {
      final double val = values[i];
      if (val == 0.0) continue;

      final double sweepAngle = 2 * 3.14159 * (val / total);

      final Paint paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius - innerRadius
        ..strokeCap = StrokeCap.square;

      canvas.drawArc(rect, startAngle + 0.02, sweepAngle - 0.04, false, paint);
      startAngle += sweepAngle;
    }

    final TextSpan centerSpan = TextSpan(
      children: [
        TextSpan(
          text: '$totalCount\n',
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
        ),
        TextSpan(
          text: 'Active',
          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
        ),
      ],
    );
    final TextPainter centerTp = TextPainter(
      text: centerSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    centerTp.paint(canvas, Offset(center.dx - centerTp.width / 2, center.dy - centerTp.height / 2));
  }

  @override
  bool shouldRepaint(covariant PlansDistributionPainter oldDelegate) => oldDelegate.values != values || oldDelegate.labels != labels || oldDelegate.colors != colors || oldDelegate.totalCount != totalCount;
}

class RevenuePerShiftPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;

  RevenuePerShiftPainter({required this.values, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final double maxVal = [...values, 1000.0].reduce((a, b) => a > b ? a : b);
    final double paddingX = 40.0;
    final double paddingY = 20.0;
    final double width = size.width - paddingX * 2;
    final double height = size.height - paddingY * 2;

    final Paint gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 4; i++) {
      final double y = paddingY + height * (1 - i / 4);
      canvas.drawLine(Offset(paddingX, y), Offset(paddingX + width, y), gridPaint);

      final double gridVal = maxVal * (i / 4);
      final TextSpan span = TextSpan(
        style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF94A3B8)),
        text: '₹${gridVal.toStringAsFixed(0)}',
      );
      final TextPainter tp = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(paddingX - tp.width - 5, y - tp.height / 2));
    }

    final double barSpaceWidth = width / (values.length + 1);
    final double barWidth = (barSpaceWidth * 0.5).clamp(16.0, 48.0);
    final Paint barPaint = Paint()..color = const Color(0xFFE65C00);

    for (int i = 0; i < values.length; i++) {
      final double val = values[i];
      final double barHeight = (val / maxVal) * height;
      final double x = paddingX + barSpaceWidth * (i + 1) - barWidth / 2;
      final double y = paddingY + height - barHeight;

      if (barHeight > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, barWidth, barHeight),
            const Radius.circular(4),
          ),
          barPaint,
        );
      }

      final TextSpan labelSpan = TextSpan(
        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
        text: labels[i],
      );
      final TextPainter labelTp = TextPainter(
        text: labelSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      labelTp.paint(canvas, Offset(x + barWidth / 2 - labelTp.width / 2, paddingY + height + 5));
    }
  }

  @override
  bool shouldRepaint(covariant RevenuePerShiftPainter oldDelegate) => oldDelegate.values != values || oldDelegate.labels != labels;
}

class PopularityOfPlansPainter extends CustomPainter {
  final List<List<double>> valuesList;
  final List<String> labels;
  final List<Color> colors;

  PopularityOfPlansPainter({
    required this.valuesList,
    required this.labels,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (valuesList.isEmpty || valuesList.first.isEmpty) return;

    double maxVal = 5.0;
    for (var list in valuesList) {
      for (var val in list) {
        if (val > maxVal) maxVal = val;
      }
    }

    final double paddingX = 30.0;
    final double paddingY = 20.0;
    final double width = size.width - paddingX * 2;
    final double height = size.height - paddingY * 2;

    final Paint gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 4; i++) {
      final double y = paddingY + height * (1 - i / 4);
      canvas.drawLine(Offset(paddingX, y), Offset(paddingX + width, y), gridPaint);

      final double gridVal = maxVal * (i / 4);
      final TextSpan span = TextSpan(
        style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF94A3B8)),
        text: gridVal.toStringAsFixed(0),
      );
      final TextPainter tp = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(paddingX - tp.width - 5, y - tp.height / 2));
    }

    final int pointsCount = labels.length;
    final double stepX = pointsCount > 1 ? width / (pointsCount - 1) : width;

    for (int l = 0; l < valuesList.length; l++) {
      final List<double> values = valuesList[l];
      final Color color = colors[l % colors.length];

      final List<Offset> points = [];
      final Path path = Path();
      for (int i = 0; i < values.length; i++) {
        final double x = paddingX + i * stepX;
        final double y = paddingY + height * (1 - (values[i] / maxVal));
        final p = Offset(x, y);
        points.add(p);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      final Paint linePaint = Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(path, linePaint);

      final Paint pointPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      for (final p in points) {
        canvas.drawCircle(p, 3.0, pointPaint);
      }
    }

    for (int i = 0; i < pointsCount; i++) {
      final double x = paddingX + i * stepX;
      final TextSpan span = TextSpan(
        style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF64748B)),
        text: labels[i],
      );
      final TextPainter tp = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, paddingY + height + 5));
    }
  }

  @override
  bool shouldRepaint(covariant PopularityOfPlansPainter oldDelegate) => oldDelegate.valuesList != valuesList || oldDelegate.labels != labels || oldDelegate.colors != colors;
}
