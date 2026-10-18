import 'package:flutter/material.dart';

class DraftSegmentPainter extends CustomPainter {
  final Offset? p1;
  final Offset? p2;

  DraftSegmentPainter({required this.p1, required this.p2});

  @override
  void paint(Canvas canvas, Size size) {
    if (p1 == null || p2 == null) return;

    final linePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

    canvas.drawLine(p1!, p2!, linePaint);

    // endpoints
    final dotPaint = Paint()..style = PaintingStyle.fill;
    canvas.drawCircle(p1!, 4, dotPaint);
    canvas.drawCircle(p2!, 4, dotPaint);

    // labels
    final tp1 = TextPainter(
      text: TextSpan(
        text: 'P1 (${p1!.dx.toStringAsFixed(0)}, ${p1!.dy.toStringAsFixed(0)})',
        style: const TextStyle(fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final tp2 = TextPainter(
      text: TextSpan(
        text: 'P2 (${p2!.dx.toStringAsFixed(0)}, ${p2!.dy.toStringAsFixed(0)})',
        style: const TextStyle(fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp1.paint(canvas, p1! + const Offset(6, -18));
    tp2.paint(canvas, p2! + const Offset(6, -18));
  }

  @override
  bool shouldRepaint(covariant DraftSegmentPainter old) =>
      old.p1 != p1 || old.p2 != p2;
}
