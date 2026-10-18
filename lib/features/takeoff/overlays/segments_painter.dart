import 'package:aqs/features/takeoff/models/measured_segment.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:flutter/material.dart';

// import 'package:flutter/material.dart';

class SegmentsPainter extends CustomPainter {
  final List<MeasuredSegment> segments;
  final Offset? tempP1;
  final Offset? tempP2;
  final List<Offset> draftPoints;
  final List<List<Offset>> draftSegmentPairs;
  final Color tempColor;
  final String? selectedSegmentId;
  //  final List<MeasuredSegment> segments;
  // final String? selectedSegmentId;
  final Offset? editP1;
  final Offset? editP2;

  // keep your temp line fields too if needed
  // final Offset? tempP1;
  // final Offset? tempP2;
  // final Color tempColor;
  // final List<MeasuredSegment> segments;
  // final String? selectedSegmentId;
  // final Offset? editP1;
  // final Offset? editP2;

  // keep your temp line fields too if needed
  // final Offset? tempP1;
  // final Offset? tempP2;
  // final Color tempColor;

  // zoom aware stroke
  final double zoomScale;
  final StrokeMode strokeMode;
  final double baseStroke; // from slider 0.5..10
  final Color selectedDotColor; // dot color when selected
  final Color selectedLineColor;
  final bool hideIntermediateDots;

  // ✅ dots
  final DotMode dotMode;
  final double dotRadius; // slider-controlled (screen-ish)
  final Color dotColor; // different from segment color
  final bool dotsFollowSegmentColor; // if true ignore dotColor
  final DotScaleMode dotScaleMode;

  // controls how we treat “same point”
  final double pointSnap; // pixels tolerance used for grouping endpoints
  final bool previewLengthOnly;

  SegmentsPainter({
    required this.segments,
    required this.tempP1,
    required this.tempP2,
    this.draftPoints = const <Offset>[],
    this.draftSegmentPairs = const <List<Offset>>[],
    required this.tempColor,
    required this.selectedSegmentId,
    required this.editP1,
    required this.editP2,
    required this.zoomScale,
    required this.strokeMode,
    required this.baseStroke,
    required this.dotScaleMode,

    this.previewLengthOnly = false, // ✅ default off

    this.dotMode = DotMode.chainEndpointsOnly,
    this.dotRadius = 4.0,
    this.dotColor = Colors.black,
    this.dotsFollowSegmentColor = false,
    this.pointSnap = 2.0,
    this.selectedDotColor = Colors.red,
    this.selectedLineColor = const Color(0xFFFF8A00),
    this.hideIntermediateDots = false,
  });

  double _strokeWidth(bool isSelected, {double? segmentStrokeWidth}) {
    final s = zoomScale <= 0 ? 1.0 : zoomScale;
    final effectiveBaseStroke = segmentStrokeWidth ?? baseStroke;

    double w;
    if (strokeMode == StrokeMode.constantOnScreen) {
      w = effectiveBaseStroke / s;
    } else {
      w = effectiveBaseStroke * (0.7 + 0.3 * s);
    }

    if (isSelected) w *= 1.6;
    return w.clamp(0.5, 10.0);
  }

  double _dotRadiusOnCanvas() {
    final s = zoomScale <= 0 ? 1.0 : zoomScale;

    // ✅ if constant on screen: keep same visual size while zooming
    // ✅ if constant on canvas: grows visually when zooming in (bigger on screen)
    final r =
        (dotScaleMode == DotScaleMode.constantOnScreen)
            ? (dotRadius / s)
            : dotRadius;

    // ✅ don’t clamp too high at the minimum (it makes slider “feel stuck”)
    return r.clamp(0.3, 30.0);
  }

  String _keyFor(Offset p) {
    final qx = (p.dx / pointSnap).round();
    final qy = (p.dy / pointSnap).round();
    return '$qx,$qy';
  }

  /// Count endpoints per chain/group so we can hide intermediate points
  Map<String, Map<String, int>> _endpointCountsByGroup() {
    final counts = <String, Map<String, int>>{};
    for (final seg in segments) {
      final g = (seg.groupId ?? '__global__');
      final map = counts.putIfAbsent(g, () => <String, int>{});
      map[_keyFor(seg.p1)] = (map[_keyFor(seg.p1)] ?? 0) + 1;
      map[_keyFor(seg.p2)] = (map[_keyFor(seg.p2)] ?? 0) + 1;
    }
    return counts;
  }

  bool _shouldDrawDotForPoint({
    required MeasuredSegment seg,
    required Offset p,
    required Map<String, Map<String, int>> countsByGroup,
    required bool isSelected,
  }) {
    if (dotMode == DotMode.none) return false;
    if (dotMode == DotMode.all) return true;

    // chainEndpointsOnly
    if (isSelected) return true; // always show dots when selected

    final g = (seg.groupId ?? '__global__');
    final key = _keyFor(p);
    final c = (countsByGroup[g]?[key] ?? 0);

    // Endpoints in a chain typically occur once; intermediate joints occur >=2
    return c <= 1;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final drawSegments =
        previewLengthOnly
            ? segments.where((s) {
              final mt = (s.measureType ?? '').toString().toLowerCase().trim();

              // ✅ treat these as "length family"
              if (mt == 'length' ||
                  mt == 'lengthmeasure' ||
                  mt == 'length_measure') {
                return true;
              }

              // if you store cabletray etc in measureType:
              if (mt == 'cabletray' ||
                  mt == 'coping' ||
                  mt == 'windowcill' ||
                  mt == 'foundationwall') {
                return true;
              }

              // OR if you store in s.activeMeasureType, add check there too
              return false;
            }).toList()
            : segments;
    final Map<String, Map<String, int>> countsByGroup =
        (dotMode == DotMode.chainEndpointsOnly)
            ? _endpointCountsByGroup()
            : <String, Map<String, int>>{};

    for (final seg in drawSegments) {
      final isSelected = seg.id == selectedSegmentId;

      // ✅ use edited points when selected
      final p1 = (isSelected && editP1 != null) ? editP1! : seg.p1;
      final p2 = (isSelected && editP2 != null) ? editP2! : seg.p2;

      final linePaint =
          Paint()
            ..color = isSelected ? selectedLineColor : seg.color
            ..strokeWidth = _strokeWidth(
              isSelected,
              segmentStrokeWidth: seg.strokeWidth,
            )
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..isAntiAlias = true;

      // ✅ draw the line using p1/p2
      canvas.drawLine(p1, p2, linePaint);

      // ✅ dot paint (fill only)
      final dColor =
          dotsFollowSegmentColor
              ? seg.color
              : (isSelected ? selectedDotColor : dotColor);

      final dotPaint =
          Paint()
            ..color = dColor
            ..style = PaintingStyle.fill
            ..isAntiAlias = true;

      // ✅ use zoom-aware radius
      final baseR = _dotRadiusOnCanvas();
      final r = isSelected ? baseR * 1.3 : baseR;

      // ✅ draw dots ONLY if allowed by mode
      if (_shouldDrawDotForPoint(
        seg: seg,
        p: p1,
        countsByGroup: countsByGroup,
        isSelected: isSelected,
      )) {
        canvas.drawCircle(p1, r, dotPaint);
      }

      if (_shouldDrawDotForPoint(
        seg: seg,
        p: p2,
        countsByGroup: countsByGroup,
        isSelected: isSelected,
      )) {
        canvas.drawCircle(p2, r, dotPaint);
      }
    }

    final linePaint =
        Paint()
          ..color = tempColor
          ..strokeWidth = _strokeWidth(false)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true;

    final dotPaint =
        Paint()
          ..color = (dotsFollowSegmentColor ? tempColor : dotColor)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;

    final r = _dotRadiusOnCanvas() * 1.2;

    if (draftSegmentPairs.isNotEmpty) {
      for (final pair in draftSegmentPairs) {
        if (pair.length < 2) continue;
        canvas.drawLine(pair[0], pair[1], linePaint);
        canvas.drawCircle(pair[0], r, dotPaint);
        canvas.drawCircle(pair[1], r, dotPaint);
      }
    }

    // A grouped measurement can contain completed, disconnected runs and the
    // continuous run currently being drawn. Paint both instead of treating
    // them as mutually exclusive.
    if (draftPoints.length >= 2) {
      for (var i = 0; i < draftPoints.length - 1; i++) {
        canvas.drawLine(draftPoints[i], draftPoints[i + 1], linePaint);
      }
      canvas.drawCircle(draftPoints.first, r, dotPaint);
      canvas.drawCircle(draftPoints.last, r, dotPaint);
      return;
    }

    // temp (draft) segment
    if (tempP1 != null) {
      final linePaint =
          Paint()
            ..color = tempColor
            ..strokeWidth = _strokeWidth(false)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..isAntiAlias = true;

      canvas.drawCircle(tempP1!, r, dotPaint);

      if (tempP2 != null) {
        canvas.drawLine(tempP1!, tempP2!, linePaint);
        canvas.drawCircle(tempP2!, r, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SegmentsPainter old) {
    return old.previewLengthOnly != previewLengthOnly || // ✅ add
        old.zoomScale != zoomScale ||
        old.baseStroke != baseStroke ||
        old.dotScaleMode != dotScaleMode ||
        old.strokeMode != strokeMode ||
        old.dotMode != dotMode ||
        old.dotRadius != dotRadius ||
        old.dotColor != dotColor ||
        old.selectedLineColor != selectedLineColor ||
        old.dotsFollowSegmentColor != dotsFollowSegmentColor ||
        old.selectedSegmentId != selectedSegmentId ||
        old.segments != segments ||
        old.draftPoints != draftPoints ||
        old.draftSegmentPairs != draftSegmentPairs ||
        old.tempP1 != tempP1 ||
        old.tempP2 != tempP2 ||
        old.tempColor != tempColor;
  }
}

// class SegmentsPainter extends CustomPainter {
//   final List<MeasuredSegment> segments;
//   final Offset? tempP1;
//   final Offset? tempP2;
//   final Color tempColor;
//   final String? selectedSegmentId;

//   final double zoomScale;
//   final double baseStroke; // 0.5 → 10
//   final StrokeMode strokeMode;

//   SegmentsPainter({
//     required this.segments,
//     required this.tempP1,
//     required this.tempP2,
//     required this.tempColor,
//     required this.selectedSegmentId,
//     required this.zoomScale,
//     required this.baseStroke,
//     required this.strokeMode,
//   });

//   double _strokeWidth(bool isSelected) {
//     final s = zoomScale <= 0 ? 1.0 : zoomScale;

//     double w;
//     if (strokeMode == StrokeMode.constantOnScreen) {
//       w = baseStroke / s;
//     } else {
//       // adaptive (optional)
//       w = (baseStroke * (0.7 + 0.3 * s));
//     }

//     if (isSelected) w *= 1.6;
//     return w.clamp(0.5, 10.0);
//   }

//   // ✅ radius tracks stroke width
//   double _pointRadius(bool isSelected) {
//     final w = _strokeWidth(isSelected);

//     // pick a nice relationship: radius slightly bigger than stroke
//     // clamp so it never becomes too tiny or too huge
//     final r = (w * 1.8).clamp(2.0, 10.0);

//     return r;
//   }

//   @override
//   void paint(Canvas canvas, Size size) {
//     for (final seg in segments) {
//       final isSelected = seg.id == selectedSegmentId;

//       final linePaint =
//           Paint()
//             ..color = (isSelected ? Colors.red : seg.color)
//             ..strokeWidth = _strokeWidth(isSelected)
//             ..style = PaintingStyle.stroke
//             ..strokeCap = StrokeCap.round;

//       canvas.drawLine(seg.p1, seg.p2, linePaint);

//       // ✅ use fill paint for points (looks better)
//       final dotPaint =
//           Paint()
//             ..color = (isSelected ? Colors.red : seg.color)
//             ..style = PaintingStyle.fill;

//       final r = _pointRadius(isSelected);
//       canvas.drawCircle(seg.p1, r, dotPaint);
//       canvas.drawCircle(seg.p2, r, dotPaint);
//     }

//     // temp segment while measuring
//     if (tempP1 != null) {
//       final isSelected = false;

//       final linePaint =
//           Paint()
//             ..color = tempColor
//             ..strokeWidth = _strokeWidth(isSelected)
//             ..style = PaintingStyle.stroke
//             ..strokeCap = StrokeCap.round;

//       final dotPaint =
//           Paint()
//             ..color = tempColor
//             ..style = PaintingStyle.fill;

//       final r = _pointRadius(isSelected);

//       canvas.drawCircle(tempP1!, r, dotPaint);

//       if (tempP2 != null) {
//         canvas.drawLine(tempP1!, tempP2!, linePaint);
//         canvas.drawCircle(tempP2!, r, dotPaint);
//       }
//     }
//   }

//   @override
//   bool shouldRepaint(covariant SegmentsPainter old) => true;
// }
