// import 'package:aqs/features/takeoff/drawing_take_off_page.dart';
import 'package:aqs/features/takeoff/models/measured_segment.dart';
import 'package:aqs/features/takeoff/models/saved_area.dart';
// import 'package:aqs/features/utils/customs.dart';
import 'package:flutter/material.dart';

class SavedAreasPainter extends CustomPainter {
  final List<SavedArea> areas;

  /// Draft points (current drawing). Pass [] when not drawing.
  final List<Offset> draftPoints;

  /// If true, when draft has >= 3 points, draw a closing preview back to start.
  final bool showDraftClosure;

  /// If true, show ONLY the first point marker for each saved polygon.
  final bool showFirstPointOnly;

  /// If true, show dots for all vertices (saved + draft).
  final bool showAllVertexDots;

  /// Base sizes (in screen px if constantOnScreen)
  final double firstPointRadius;
  final double vertexDotRadius;

  final Color? firstPointColor; // if null => use area.color

  /// Base stroke width
  final double strokeWidth;

  /// Zoom scale from InteractiveViewer (getMaxScaleOnAxis).
  /// If provided, sizes become constant-on-screen (recommended).
  final double zoomScale;

  /// Draft styling
  final Color draftColor;
  final double draftOpacityFill;

  /// If true: strokeWidth/dot sizes stay constant on screen while zooming.
  /// If false: sizes stay in canvas units (appear bigger when zoomed in).
  final bool constantOnScreen;

  /// ✅ optional: if true, hidden areas still draw as very faint outline (debug)
  final bool showHiddenAsOutline;
  final String? selectedAreaId;
  final Color selectedColor;

  SavedAreasPainter({
    required this.areas,
    this.draftPoints = const [],
    this.showDraftClosure = true,
    this.showFirstPointOnly = true,
    this.showAllVertexDots = false,
    this.firstPointRadius = 4.0,
    this.vertexDotRadius = 3.0,
    this.firstPointColor,
    this.strokeWidth = 2.0,
    this.zoomScale = 1.0,
    this.draftColor = const Color(0xFFFF9800), // orange
    this.draftOpacityFill = 0.08,
    this.constantOnScreen = true,
    this.showHiddenAsOutline = false,
    this.selectedAreaId,
    this.selectedColor = const Color(0xFFFF8A00),
  });

  double _scaleDiv() {
    final s = zoomScale <= 0 ? 1.0 : zoomScale;
    return constantOnScreen ? s : 1.0;
  }

  double _stroke() => (strokeWidth / _scaleDiv()).clamp(0.4, 10.0);
  double _r(double base) => (base / _scaleDiv()).clamp(0.3, 30.0);

  Path _buildPath(List<Offset> pts, {required bool closed}) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    if (closed) path.close();
    return path;
  }

  void _drawDots(Canvas canvas, List<Offset> pts, Paint paint, double radius) {
    for (final p in pts) {
      canvas.drawCircle(p, radius, paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // ----------------------------
    // 1) Saved areas (closed + fill)
    // ----------------------------
    for (final area in areas) {
      // ✅ hide/unhide support
      if (area.isHidden == true && !showHiddenAsOutline) continue;

      final pts = area.points;
      if (pts.length < 3) continue;

      final hidden = area.isHidden == true;
      final selected = area.id == selectedAreaId;

      final linePaint =
          Paint()
            ..color =
                hidden
                    ? area.color.withOpacity(0.18) // faint outline
                    : selected
                    ? selectedColor
                    : area.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = _stroke() * (selected ? 2.2 : 1)
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round
            ..isAntiAlias = true;

      final fillPaint =
          Paint()
            ..color =
                hidden
                    ? area.color.withOpacity(0.03) // faint fill
                    : (selected ? selectedColor : area.color).withOpacity(
                      selected ? 0.24 : 0.12,
                    )
            ..style = PaintingStyle.fill
            ..isAntiAlias = true;

      final path = _buildPath(pts, closed: true);

      // if hidden and showHiddenAsOutline=false we already continued above.
      // if hidden and showHiddenAsOutline=true => draw faint outline/fill for debugging.
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, linePaint);

      // first point marker (skip for hidden if you want)
      if (!hidden && showFirstPointOnly && pts.isNotEmpty) {
        final p0 = pts.first;
        final dotPaint =
            Paint()
              ..color = (firstPointColor ?? area.color)
              ..style = PaintingStyle.fill
              ..isAntiAlias = true;

        canvas.drawCircle(p0, _r(firstPointRadius), dotPaint);
      }

      // all vertex dots (optional) — usually skip when hidden
      if (!hidden && showAllVertexDots) {
        final dp =
            Paint()
              ..color = area.color
              ..style = PaintingStyle.fill
              ..isAntiAlias = true;
        _drawDots(canvas, pts, dp, _r(vertexDotRadius));
      }
    }

    // ----------------------------
    // 2) Draft polygon (open polyline; optional closure preview)
    // ----------------------------
    if (draftPoints.isNotEmpty) {
      final dp = List<Offset>.from(draftPoints);

      final draftLine =
          Paint()
            ..color = draftColor.withOpacity(0.95)
            ..style = PaintingStyle.stroke
            ..strokeWidth = _stroke()
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round
            ..isAntiAlias = true;

      final draftFill =
          Paint()
            ..color = draftColor.withOpacity(draftOpacityFill)
            ..style = PaintingStyle.fill
            ..isAntiAlias = true;

      // If only 1 point -> show a dot only
      if (dp.length == 1) {
        final dotPaint =
            Paint()
              ..color = draftColor
              ..style = PaintingStyle.fill
              ..isAntiAlias = true;
        canvas.drawCircle(dp.first, _r(firstPointRadius), dotPaint);
        return;
      }

      // For 2+ points -> draw polyline
      final openPath = _buildPath(dp, closed: false);
      canvas.drawPath(openPath, draftLine);

      // draw closure preview if 3+ points
      if (showDraftClosure && dp.length >= 3) {
        final closedPath = _buildPath(dp, closed: true);
        canvas.drawPath(closedPath, draftFill);
        canvas.drawPath(closedPath, draftLine);
      }

      // draft dots (always show first + last; optionally all)
      final dotPaint =
          Paint()
            ..color = draftColor
            ..style = PaintingStyle.fill
            ..isAntiAlias = true;

      canvas.drawCircle(dp.first, _r(firstPointRadius), dotPaint);
      canvas.drawCircle(dp.last, _r(firstPointRadius), dotPaint);

      if (showAllVertexDots) {
        _drawDots(canvas, dp, dotPaint, _r(vertexDotRadius));
      }
    }
  }

  @override
  bool shouldRepaint(covariant SavedAreasPainter old) {
    return old.areas != areas ||
        old.draftPoints != draftPoints ||
        old.zoomScale != zoomScale ||
        old.strokeWidth != strokeWidth ||
        old.firstPointRadius != firstPointRadius ||
        old.vertexDotRadius != vertexDotRadius ||
        old.showFirstPointOnly != showFirstPointOnly ||
        old.showAllVertexDots != showAllVertexDots ||
        old.showDraftClosure != showDraftClosure ||
        old.draftColor != draftColor ||
        old.selectedAreaId != selectedAreaId ||
        old.selectedColor != selectedColor ||
        old.constantOnScreen != constantOnScreen ||
        old.showHiddenAsOutline != showHiddenAsOutline;
  }
}

// class SavedAreasPainter extends CustomPainter {
//   final List<SavedArea> areas;

//   /// Draft points (current drawing). Pass [] when not drawing.
//   final List<Offset> draftPoints;

//   /// If true, when draft has >= 3 points, draw a closing preview back to start.
//   final bool showDraftClosure;

//   /// If true, show ONLY the first point marker for each saved polygon.
//   final bool showFirstPointOnly;

//   /// If true, show dots for all vertices (saved + draft).
//   final bool showAllVertexDots;

//   /// Base sizes (in screen px if constantOnScreen)
//   final double firstPointRadius;
//   final double vertexDotRadius;

//   final Color? firstPointColor; // if null => use area.color

//   /// Base stroke width
//   final double strokeWidth;

//   /// Zoom scale from InteractiveViewer (getMaxScaleOnAxis).
//   /// If provided, sizes become constant-on-screen (recommended).
//   final double zoomScale;

//   /// Draft styling
//   final Color draftColor;
//   final double draftOpacityFill;

//   /// If true: strokeWidth/dot sizes stay constant on screen while zooming.
//   /// If false: sizes stay in canvas units (appear bigger when zoomed in).
//   final bool constantOnScreen;

//   SavedAreasPainter({
//     required this.areas,
//     this.draftPoints = const [],
//     this.showDraftClosure = true,

//     this.showFirstPointOnly = true,
//     this.showAllVertexDots = false,

//     this.firstPointRadius = 4.0,
//     this.vertexDotRadius = 3.0,
//     this.firstPointColor,
//     this.strokeWidth = 2.0,

//     this.zoomScale = 1.0,
//     this.draftColor = const Color(0xFFFF9800), // orange
//     this.draftOpacityFill = 0.08,

//     this.constantOnScreen = true,
//   });

//   double _scaleDiv() {
//     final s = zoomScale <= 0 ? 1.0 : zoomScale;
//     return constantOnScreen ? s : 1.0;
//   }

//   double _stroke() => (strokeWidth / _scaleDiv()).clamp(0.4, 10.0);
//   double _r(double base) => (base / _scaleDiv()).clamp(0.3, 30.0);

//   Path _buildPath(List<Offset> pts, {required bool closed}) {
//     final path = Path()..moveTo(pts.first.dx, pts.first.dy);
//     for (int i = 1; i < pts.length; i++) {
//       path.lineTo(pts[i].dx, pts[i].dy);
//     }
//     if (closed) path.close();
//     return path;
//   }

//   void _drawDots(Canvas canvas, List<Offset> pts, Paint paint, double radius) {
//     for (final p in pts) {
//       canvas.drawCircle(p, radius, paint);
//     }
//   }

//   @override
//   void paint(Canvas canvas, Size size) {
//     // ----------------------------
//     // 1) Saved areas (closed + fill)
//     // ----------------------------
//     for (final area in areas) {
//       final pts = area.points;
//       if (pts.length < 3) continue;

//       final linePaint =
//           Paint()
//             ..color = area.color
//             ..style = PaintingStyle.stroke
//             ..strokeWidth = _stroke()
//             ..strokeJoin = StrokeJoin.round
//             ..strokeCap = StrokeCap.round
//             ..isAntiAlias = true;

//       final fillPaint =
//           Paint()
//             ..color = area.color.withOpacity(0.12)
//             ..style = PaintingStyle.fill
//             ..isAntiAlias = true;

//       final path = _buildPath(pts, closed: true);
//       canvas.drawPath(path, fillPaint);
//       canvas.drawPath(path, linePaint);

//       // first point marker
//       if (showFirstPointOnly && pts.isNotEmpty) {
//         final p0 = pts.first;
//         final dotPaint =
//             Paint()
//               ..color = (firstPointColor ?? area.color)
//               ..style = PaintingStyle.fill
//               ..isAntiAlias = true;

//         canvas.drawCircle(p0, _r(firstPointRadius), dotPaint);
//       }

//       // all vertex dots (optional)
//       if (showAllVertexDots) {
//         final dp =
//             Paint()
//               ..color = area.color
//               ..style = PaintingStyle.fill
//               ..isAntiAlias = true;
//         _drawDots(canvas, pts, dp, _r(vertexDotRadius));
//       }
//     }

//     // ----------------------------
//     // 2) Draft polygon (open polyline; optional closure preview)
//     // ----------------------------
//     if (draftPoints.isNotEmpty) {
//       final dp = List<Offset>.from(draftPoints);

//       final draftLine =
//           Paint()
//             ..color = draftColor.withOpacity(0.95)
//             ..style = PaintingStyle.stroke
//             ..strokeWidth = _stroke()
//             ..strokeJoin = StrokeJoin.round
//             ..strokeCap = StrokeCap.round
//             ..isAntiAlias = true;

//       final draftFill =
//           Paint()
//             ..color = draftColor.withOpacity(draftOpacityFill)
//             ..style = PaintingStyle.fill
//             ..isAntiAlias = true;

//       // If only 1 point -> show a dot only
//       if (dp.length == 1) {
//         final dotPaint =
//             Paint()
//               ..color = draftColor
//               ..style = PaintingStyle.fill
//               ..isAntiAlias = true;
//         canvas.drawCircle(dp.first, _r(firstPointRadius), dotPaint);
//         return;
//       }

//       // For 2+ points -> draw polyline
//       final openPath = _buildPath(dp, closed: false);
//       canvas.drawPath(openPath, draftLine);

//       // draw closure preview if 3+ points
//       if (showDraftClosure && dp.length >= 3) {
//         final closedPath = _buildPath(dp, closed: true);
//         canvas.drawPath(closedPath, draftFill);
//         canvas.drawPath(closedPath, draftLine);
//       }

//       // draft dots (always show first + last; optionally all)
//       final dotPaint =
//           Paint()
//             ..color = draftColor
//             ..style = PaintingStyle.fill
//             ..isAntiAlias = true;

//       canvas.drawCircle(dp.first, _r(firstPointRadius), dotPaint);
//       canvas.drawCircle(dp.last, _r(firstPointRadius), dotPaint);

//       if (showAllVertexDots) {
//         _drawDots(canvas, dp, dotPaint, _r(vertexDotRadius));
//       }
//     }
//   }

//   @override
//   bool shouldRepaint(covariant SavedAreasPainter old) {
//     return old.areas != areas ||
//         old.draftPoints != draftPoints ||
//         old.zoomScale != zoomScale ||
//         old.strokeWidth != strokeWidth ||
//         old.firstPointRadius != firstPointRadius ||
//         old.vertexDotRadius != vertexDotRadius ||
//         old.showFirstPointOnly != showFirstPointOnly ||
//         old.showAllVertexDots != showAllVertexDots ||
//         old.showDraftClosure != showDraftClosure ||
//         old.draftColor != draftColor ||
//         old.constantOnScreen != constantOnScreen;
//   }
// }
