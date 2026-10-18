import 'package:flutter/material.dart';

class WallSegment {
  final Offset p1;
  final Offset p2;
  final double lengthM;

  const WallSegment({
    required this.p1,
    required this.p2,
    required this.lengthM,
  });

  Map<String, dynamic> toMap() => {
    'p1': {'x': p1.dx, 'y': p1.dy},
    'p2': {'x': p2.dx, 'y': p2.dy},
    'lengthM': lengthM,
  };
}

class WallGroup {
  final String id;
  final String label;
  final double heightM;
  final List<WallSegment> segments; // each has p1,p2,lengthM
  final Color color;

  WallGroup({
    required this.id,
    required this.label,
    required this.heightM,
    required this.segments,
    required this.color,
  });

  double get totalLengthM => segments.fold(0, (s, seg) => s + seg.lengthM);
  double get areaM2 => totalLengthM * heightM;
}
