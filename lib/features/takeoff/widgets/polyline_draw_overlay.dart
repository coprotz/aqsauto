import 'package:aqs/features/takeoff/controllers/poly_draw_controller.dart';
import 'package:flutter/material.dart';

class PolylineDrawOverlay extends StatelessWidget {
  final PolylineDrawController c;
  final Offset Function(Offset local) toWorld;
  final Offset Function(Offset world) toScreen;

  final Color color;
  final double stroke;

  const PolylineDrawOverlay({
    super.key,
    required this.c,
    required this.toWorld,
    required this.toScreen,
    this.color = Colors.red,
    this.stroke = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    if (!c.enabled) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,

      // ✅ tap = add point
      onTapDown: (d) {
        final w = toWorld(d.localPosition);
        c.addPoint(w);
      },

      // ✅ hover/drag preview
      onPanStart: (d) => c.updateHover(toWorld(d.localPosition)),
      onPanUpdate: (d) => c.updateHover(toWorld(d.localPosition)),
      onPanEnd: (_) => c.updateHover(null),

      // ✅ double tap = finish (we’ll handle in “Save” step)
      onDoubleTap: () {
        // just stop hover preview; saving handled outside
        c.updateHover(null);
      },

      child: AnimatedBuilder(
        animation: c,
        builder: (_, __) {
          return CustomPaint(
            painter: _PolylinePainter(
              pointsWorld: c.pointsWorld,
              hoverWorld: c.hover,
              toScreen: toScreen,
              color: color,
              stroke: stroke,
            ),
          );
        },
      ),
    );
  }
}

class _PolylinePainter extends CustomPainter {
  final List<Offset> pointsWorld;
  final Offset? hoverWorld;
  final Offset Function(Offset world) toScreen;
  final Color color;
  final double stroke;

  _PolylinePainter({
    required this.pointsWorld,
    required this.hoverWorld,
    required this.toScreen,
    required this.color,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (pointsWorld.isEmpty) return;

    final paintLine =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke;

    final paintDot =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;

    final path = Path();
    final first = toScreen(pointsWorld.first);
    path.moveTo(first.dx, first.dy);

    for (int i = 1; i < pointsWorld.length; i++) {
      final p = toScreen(pointsWorld[i]);
      path.lineTo(p.dx, p.dy);
    }

    // preview to hover
    if (hoverWorld != null && pointsWorld.isNotEmpty) {
      final h = toScreen(hoverWorld!);
      path.lineTo(h.dx, h.dy);
    }

    canvas.drawPath(path, paintLine);

    // draw vertices
    for (final w in pointsWorld) {
      final s = toScreen(w);
      canvas.drawCircle(s, 3.5, paintDot);
    }
  }

  @override
  bool shouldRepaint(covariant _PolylinePainter old) {
    return old.pointsWorld != pointsWorld ||
        old.hoverWorld != hoverWorld ||
        old.color != color ||
        old.stroke != stroke;
  }
}
