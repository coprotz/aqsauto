import 'dart:math' as math;
import 'dart:ui' as material;

import 'package:flutter/material.dart';

/// Simple draft model for painting
class PolylineDraft {
  final String id;
  final material.Color color;
  final String? tag;
  final List<Offset> worldPoints;

  PolylineDraft({
    required this.id,
    required this.color,
    required this.tag,
    required this.worldPoints,
  });

  double totalLengthM(Map<String, dynamic> drawingData) {
    final calibrated = drawingData['calibrated'] == true;
    final pxPerM =
        (drawingData['pixelsPerUnit'] is num)
            ? (drawingData['pixelsPerUnit'] as num).toDouble()
            : double.tryParse('${drawingData['pixelsPerUnit'] ?? ''}') ?? 0;

    if (!calibrated || pxPerM <= 0) return 0;
    if (worldPoints.length < 2) return 0;

    double sumPx = 0;
    for (int i = 0; i < worldPoints.length - 1; i++) {
      final a = worldPoints[i];
      final b = worldPoints[i + 1];
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      sumPx += math.sqrt(dx * dx + dy * dy);
    }
    return sumPx / pxPerM;
  }
}
