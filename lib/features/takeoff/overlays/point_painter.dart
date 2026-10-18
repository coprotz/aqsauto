import 'package:flutter/material.dart';

class PointsPainter extends CustomPainter {
  final Offset? p1;
  final Offset? p2;
  final Color color;
  final double zoomScale;

  PointsPainter({
    required this.p1,
    required this.p2,
    required this.color,
    this.zoomScale = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final safeScale = zoomScale <= 0 ? 1.0 : zoomScale;
    final lineWidth = 3.0 / safeScale;
    final haloWidth = 7.0 / safeScale;
    final markerRadius = 8.0 / safeScale;
    final centerRadius = 3.2 / safeScale;

    final haloPaint =
        Paint()
          ..color = Colors.white.withOpacity(0.95)
          ..strokeWidth = haloWidth
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

    final linePaint =
        Paint()
          ..color = color
          ..strokeWidth = lineWidth
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

    if (p1 != null) {
      _drawMarker(
        canvas,
        point: p1!,
        label: 'START',
        markerRadius: markerRadius,
        centerRadius: centerRadius,
        safeScale: safeScale,
      );
    }
    if (p2 != null) {
      _drawMarker(
        canvas,
        point: p2!,
        label: 'END',
        markerRadius: markerRadius,
        centerRadius: centerRadius,
        safeScale: safeScale,
      );
    }
    if (p1 != null && p2 != null) {
      canvas.drawLine(p1!, p2!, haloPaint);
      canvas.drawLine(p1!, p2!, linePaint);
    }
  }

  void _drawMarker(
    Canvas canvas, {
    required Offset point,
    required String label,
    required double markerRadius,
    required double centerRadius,
    required double safeScale,
  }) {
    final halo =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
    final fill =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;
    final outline =
        Paint()
          ..color = color
          ..strokeWidth = 2 / safeScale
          ..style = PaintingStyle.stroke;

    canvas.drawCircle(point, markerRadius + (3 / safeScale), halo);
    canvas.drawCircle(point, markerRadius, fill);
    canvas.drawCircle(point, markerRadius, outline);
    canvas.drawCircle(point, centerRadius, halo);

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          backgroundColor: color,
          fontSize: 10 / safeScale,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      point + Offset(12 / safeScale, -20 / safeScale),
    );
  }

  @override
  bool shouldRepaint(covariant PointsPainter oldDelegate) {
    return oldDelegate.p1 != p1 ||
        oldDelegate.p2 != p2 ||
        oldDelegate.color != color ||
        oldDelegate.zoomScale != zoomScale;
  }
}
