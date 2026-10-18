import 'package:aqs/features/takeoff/controllers/polyline_capture_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

class PolylineCaptureOverlay extends StatelessWidget {
  final PolylineCaptureController c;

  const PolylineCaptureOverlay({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<PolylineCaptureController>(
      init: c,
      builder: (_) {
        return MouseRegion(
          onHover: (ev) => c.onMoveLocal(ev.localPosition),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (d) => c.onTapLocal(d.localPosition),
            onPanUpdate: (d) => c.onMoveLocal(d.localPosition),
            child: CustomPaint(
              painter: _PolylinePreviewPainter(
                p1World: c.p1World.value,
                hoverWorld: c.hoverWorld.value,
                tCtrl: c.tCtrl,
                color: Color(c.colorValue.value),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

class _PolylinePreviewPainter extends CustomPainter {
  final Offset? p1World;
  final Offset? hoverWorld;
  final TransformationController tCtrl;
  final Color color;

  _PolylinePreviewPainter({
    required this.p1World,
    required this.hoverWorld,
    required this.tCtrl,
    required this.color,
  });

  Offset _toScreen(Offset world) {
    // apply current transform (world -> screen)
    final vm.Vector3 v = tCtrl.value.transform3(
      vm.Vector3(world.dx, world.dy, 0),
    );
    return Offset(v.x, v.y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (p1World == null || hoverWorld == null) return;

    final a = _toScreen(p1World!);
    final b = _toScreen(hoverWorld!);

    final paint =
        Paint()
          ..color = color.withOpacity(0.9)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;

    canvas.drawLine(a, b, paint);

    // draw small circle on start
    canvas.drawCircle(a, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PolylinePreviewPainter old) {
    return old.p1World != p1World ||
        old.hoverWorld != hoverWorld ||
        old.color != color ||
        old.tCtrl.value != tCtrl.value;
  }
}
