import 'package:aqs/features/takeoff/models/count_marker.dart';
import 'package:flutter/material.dart';

class CountMarkerPainter extends CustomPainter {
  const CountMarkerPainter({
    required this.markers,
    required this.draftPoints,
    required this.zoomScale,
    required this.color,
    this.mark = 'tick',
    this.draftLabelPrefix = '',
  });

  final List<CountMarker> markers;
  final List<Offset> draftPoints;
  final double zoomScale;
  final Color color;
  final String mark;
  final String draftLabelPrefix;

  double get _scale => zoomScale <= 0 ? 1 : zoomScale;

  double _r(double value) => (value / _scale).clamp(1.0, value);

  @override
  void paint(Canvas canvas, Size size) {
    for (final marker in markers) {
      _drawMarker(
        canvas,
        marker.position,
        marker.color,
        marker.mark,
        marker.label,
      );
    }

    for (var i = 0; i < draftPoints.length; i++) {
      final label =
          draftLabelPrefix.trim().isEmpty
              ? '${i + 1}'
              : '${draftLabelPrefix.trim()} ×${i + 1}';
      _drawMarker(canvas, draftPoints[i], color, mark, label);
    }
  }

  void _drawMarker(
    Canvas canvas,
    Offset p,
    Color markerColor,
    String markerType,
    String? label,
  ) {
    final radius = _r(11);
    final stroke = _r(3);
    final bg =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
    final border =
        Paint()
          ..color = markerColor
          ..strokeWidth = stroke
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true
          ..strokeCap = StrokeCap.round;

    canvas.drawCircle(p, radius, bg);
    canvas.drawCircle(p, radius, border);

    if (markerType.toLowerCase() == 'cross') {
      final d = radius * 0.45;
      canvas.drawLine(p.translate(-d, -d), p.translate(d, d), border);
      canvas.drawLine(p.translate(d, -d), p.translate(-d, d), border);
    } else {
      final path =
          Path()
            ..moveTo(p.dx - radius * 0.45, p.dy - radius * 0.02)
            ..lineTo(p.dx - radius * 0.12, p.dy + radius * 0.35)
            ..lineTo(p.dx + radius * 0.52, p.dy - radius * 0.38);
      canvas.drawPath(path, border);
    }

    final text = (label ?? '').trim();
    if (text.isEmpty) return;

    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: markerColor,
          fontSize: _r(11),
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, p.translate(radius + _r(4), -painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant CountMarkerPainter oldDelegate) {
    return oldDelegate.markers != markers ||
        oldDelegate.draftPoints != draftPoints ||
        oldDelegate.zoomScale != zoomScale ||
        oldDelegate.color != color ||
        oldDelegate.mark != mark ||
        oldDelegate.draftLabelPrefix != draftLabelPrefix;
  }
}
