import 'package:flutter/material.dart';

class DraftLenPainter extends CustomPainter {
  final Offset? p1;
  final Offset? p2;

  DraftLenPainter({required this.p1, required this.p2});

  @override
  void paint(Canvas canvas, Size size) {
    if (p1 == null || p2 == null) return;

    final linePaint =
        Paint()
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;

    final dotPaint = Paint()..style = PaintingStyle.fill;

    canvas.drawLine(p1!, p2!, linePaint);
    canvas.drawCircle(p1!, 4, dotPaint);
    canvas.drawCircle(p2!, 4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant DraftLenPainter old) =>
      old.p1 != p1 || old.p2 != p2;
}
