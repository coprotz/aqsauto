import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AreaPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double zoomScale;

  final bool showFirstPointDot;
  final double firstPointRadius;
  final Color? firstPointColor;
  final double strokeWidth;
  final bool scaleAwareStroke;

  AreaPainter({
    required this.points,
    required this.color,
    required this.zoomScale,
    this.showFirstPointDot = true,
    this.firstPointRadius = 4.0,
    this.firstPointColor,
    this.strokeWidth = 2.0,
    this.scaleAwareStroke = true,
    Listenable? repaint, // ✅ add this
  }) : super(repaint: repaint); // ✅ and pass to super

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final s = (scaleAwareStroke && zoomScale > 0) ? (1 / zoomScale) : 1.0;

    final paintLine =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth * s;

    final paintFill =
        Paint()
          ..color = color.withOpacity(0.12)
          ..style = PaintingStyle.fill;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    if (points.length >= 3) {
      path.close();
      canvas.drawPath(path, paintFill);
    }

    canvas.drawPath(path, paintLine);

    if (showFirstPointDot) {
      final dotPaint =
          Paint()
            ..color = (firstPointColor ?? color)
            ..style = PaintingStyle.fill;
      canvas.drawCircle(points.first, firstPointRadius * s, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant AreaPainter oldDelegate) {
    // repaint is already driven by the notifier, but keep this correct too
    return !listEquals(oldDelegate.points, points) ||
        oldDelegate.color != color ||
        oldDelegate.zoomScale != zoomScale ||
        oldDelegate.showFirstPointDot != showFirstPointDot ||
        oldDelegate.firstPointRadius != firstPointRadius ||
        oldDelegate.firstPointColor != firstPointColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.scaleAwareStroke != scaleAwareStroke;
  }
}
