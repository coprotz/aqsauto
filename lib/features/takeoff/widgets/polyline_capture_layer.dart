import 'package:aqs/features/takeoff/controllers/image_takeoff_controller.dart';
import 'package:aqs/features/takeoff/controllers/measuring_item_controller.dart';
import 'package:aqs/features/takeoff/controllers/polyline_capture_controller.dart';
import 'package:aqs/features/takeoff/models/polyline_draft.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

class PolylineCaptureLayer extends StatelessWidget {
  final TransformationController tCtrl;
  final PolylineCaptureController ctrl;
  final Map<String, dynamic> drawingData;
  final Color color;
  final String? tag; // ridge/valley/hip/eave/barge etc

  const PolylineCaptureLayer({
    super.key,
    required this.tCtrl,
    required this.ctrl,
    required this.drawingData,
    required this.color,
    this.tag,
  });

  @override
  Widget build(BuildContext context) {
    final mi = Get.find<MeasuringItemController>();

    Offset _worldFromLocal(Offset local) {
      // ✅ use YOUR existing helper (avoids the toWorld undefined issue)
      return mi.toWorld(local: local, tCtrl: tCtrl);
    }

    Future<void> _handleTap(Offset local) async {
      final world = _worldFromLocal(local);

      // Tap #1 → set start
      if (!ctrl.hasStart) {
        ctrl.setStart(
          id: UniqueKey().toString(),
          color: color,
          tag: tag,
          worldStart: world,
        );
        return;
      }

      // Tap #2 → commit/save segment
      try {
        await ctrl.commitEndTap(worldEnd: world, drawingData: drawingData);
        // ✅ success snackbar should be inside controller (as you requested)
      } catch (e) {
        // ✅ error snackbar should ALSO be inside controller
        // This catch is just a safety net
        debugPrint('❌ commitEndTap failed: $e');
      }
    }

    void _handleMove(Offset local) {
      if (!ctrl.hasStart) return;
      final world = _worldFromLocal(local);
      ctrl.updateHover(world);
    }

    return Listener(
      behavior: HitTestBehavior.opaque,

      onPointerDown: (e) {
        final local = e.localPosition; // ✅ always non-null
        debugPrint('👇 pointerDown local=$local hasStart=${ctrl.hasStart}');
        ctrl.onTapLocal(local); // sets start OR saves segment
      },

      onPointerMove: (e) {
        final local = e.localPosition;
        ctrl.onMoveLocal(local); // preview line
      },
      // ✅ desktop/web preview
      child: GetBuilder<PolylineCaptureController>(
        // animation: ctrl,
        builder: (_) {
          return CustomPaint(
            painter: _PolylinePainter(
              tCtrl: tCtrl,
              startWorld: ctrl.p1World.value,
              hoverWorld: ctrl.hoverWorld.value,
              color: Color(ctrl.colorValue.value),
            ),
          );
        },
      ),
    );
  }
}

class _PolylinePainter extends CustomPainter {
  final TransformationController tCtrl;
  final Offset? startWorld;
  final Offset? hoverWorld;
  final Color color;

  _PolylinePainter({
    required this.tCtrl,
    required this.startWorld,
    required this.hoverWorld,
    required this.color,
  });

  Offset toScreen(Offset world) {
    final m = tCtrl.value;
    final v = vm.Vector3(world.dx, world.dy, 0);
    final r = m.transform3(v);
    return Offset(r.x, r.y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (startWorld == null || hoverWorld == null) return;

    final p1 = toScreen(startWorld!);
    final p2 = toScreen(hoverWorld!);

    final paint =
        Paint()
          ..color = color.withOpacity(0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

    canvas.drawLine(p1, p2, paint);
  }

  @override
  bool shouldRepaint(covariant _PolylinePainter old) =>
      old.startWorld != startWorld ||
      old.hoverWorld != hoverWorld ||
      old.tCtrl != tCtrl ||
      old.color != color;
}
