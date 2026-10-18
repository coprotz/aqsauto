import 'dart:math' as math;

import 'package:aqs/features/takeoff/controllers/measuring_item_controller.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:aqs/features/utils/helpers/roof_helpers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PolylineDrawController extends GetxController {
  final TransformationController tCtrl;
  PolylineDrawController({required this.tCtrl});
  MeasuringItemController get mi => Get.find<MeasuringItemController>();

  // final List<Offset> points = [];
  final pointsWorld = <Offset>[];
  Offset? hover;

  void addWorldPoint(Offset p) {
    pointsWorld.add(p);
    update(); // ✅ replaces notifyListeners()
  }

  bool enabled = false;
  String? type; // e.g. roofRafters150x50, roofPurlins50x50
  String? measureType; // e.g. roofSheetingAndTimber
  String label = '';

  void start({
    required String type,
    required String measureType,
    String label = '',
  }) {
    enabled = true;
    this.type = type;
    this.measureType = measureType;
    this.label = label;
    pointsWorld.clear();
    hover = null;
    update();
  }

  void clear() {
    pointsWorld.clear();
    update();
  }

  void stop() {
    enabled = false;
    type = null;
    measureType = null;
    label = '';
    pointsWorld.clear();
    hover = null;
    update();
  }

  void addPoint(Offset p) {
    if (!enabled) return;
    pointsWorld.add(p);
    update();
  }

  void undo() {
    if (pointsWorld.isEmpty) return;
    pointsWorld.removeLast();
    update();
  }

  void updateHover(Offset? p) {
    hover = p;
    update();
  }

  bool get canFinish => enabled && pointsWorld.length >= 2;

  double lengthPx() {
    if (pointsWorld.length < 2) return 0;
    double s = 0;
    for (int i = 0; i < pointsWorld.length - 1; i++) {
      final a = pointsWorld[i];
      final b = pointsWorld[i + 1];
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      s += math.sqrt(dx * dx + dy * dy);
    }
    // optional: include last->hover preview (not saved)
    return s;
  }

  double lengthPxWithHover() {
    double s = lengthPx();
    if (pointsWorld.isNotEmpty && hover != null) {
      final a = pointsWorld.last;
      final b = hover!;
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      s += math.sqrt(dx * dx + dy * dy);
    }
    return s;
  }
}

// class PolyDrawController extends ChangeNotifier {
//   DrawMode mode = DrawMode.polygon;

//   DraftPath draft = const DraftPath(pts: [], closed: false);
//   Offset? hover; // finger position for preview line

//   final List<DraftPath> saved = []; // completed shapes (polyline or polygon)

//   // config
//   double closeThresholdPx = 18; // tap distance to first point to close

//   bool get hasDraft => draft.pts.isNotEmpty;

//   void setMode(DrawMode m) {
//     mode = m;
//     clearDraft();
//   }

//   void clearDraft() {
//     draft = const DraftPath(pts: [], closed: false);
//     hover = null;
//     notifyListeners();
//   }

//   void updateHover(Offset? p) {
//     hover = p;
//     notifyListeners();
//   }

//   void addPoint(Offset p) {
//     if (mode == DrawMode.none) return;

//     final pts = [...draft.pts];

//     // If polygon mode and user taps near first point -> close
//     if (mode == DrawMode.polygon && pts.length >= 3) {
//       final first = pts.first;
//       final dx = p.dx - first.dx;
//       final dy = p.dy - first.dy;
//       final dist = math.sqrt(dx * dx + dy * dy);
//       if (dist <= closeThresholdPx) {
//         // close: add first point at end (optional)
//         pts.add(first);
//         saved.add(DraftPath(pts: pts, closed: true));
//         clearDraft();
//         return;
//       }
//     }

//     pts.add(p);
//     draft = draft.copyWith(pts: pts, closed: false);
//     notifyListeners();
//   }

//   void finishOpenPolyline() {
//     if (mode != DrawMode.polyline) return;
//     if (draft.pts.length < 2) return;
//     saved.add(DraftPath(pts: [...draft.pts], closed: false));
//     clearDraft();
//   }
// }
