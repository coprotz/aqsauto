import 'package:flutter/material.dart';

class RetainingWallDraftPainter extends CustomPainter {
  final List<dynamic>
  segs; // list of _RwSegDraft (kept dynamic to avoid private type issues)
  final Offset? currentP1; // lengthP1
  final Color color;

  /// viewer zoom scale (1.0 normal). If you already have it, pass it.
  final double zoomScale;

  final double strokeWidth;
  final double pointRadius;
  final bool scaleAwareStroke;

  RetainingWallDraftPainter({
    required this.segs,
    required this.currentP1,
    required this.color,
    required this.zoomScale,
    this.strokeWidth = 2.0,
    this.pointRadius = 4.0,
    this.scaleAwareStroke = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = (scaleAwareStroke && zoomScale > 0) ? (1 / zoomScale) : 1.0;

    final linePaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth * s
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    final dotPaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;

    // Draw all drafted segments
    for (final seg in segs) {
      // seg.p1 / seg.p2 are Offsets in your _RwSegDraft
      final Offset p1 = seg.p1 as Offset;
      final Offset p2 = seg.p2 as Offset;

      canvas.drawLine(p1, p2, linePaint);

      // optional small dots at ends (helps user see segment endpoints)
      canvas.drawCircle(p1, (pointRadius * 0.6) * s, dotPaint);
      canvas.drawCircle(p2, (pointRadius * 0.6) * s, dotPaint);
    }

    // Draw current start point (lengthP1) bigger
    if (currentP1 != null) {
      canvas.drawCircle(currentP1!, pointRadius * s, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant RetainingWallDraftPainter old) {
    // Avoid listEquals dependency; use cheap checks that work well.
    if (old.zoomScale != zoomScale) return true;
    if (old.color != color) return true;
    if (old.currentP1 != currentP1) return true;
    if (old.segs.length != segs.length) return true;

    // If last segment changed, repaint
    if (segs.isNotEmpty && old.segs.isNotEmpty) {
      final a = segs.last;
      final b = old.segs.last;
      if (a.p1 != b.p1 || a.p2 != b.p2) return true;
    }
    return false;
  }
}
