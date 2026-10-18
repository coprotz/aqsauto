import 'package:flutter/material.dart';

class MeasuredSegment {
  final String id; // logical id (can be beamId for grouping)
  final String docId; // ✅ always firestore doc id
  Offset p1; // ✅ mutable for live drag
  Offset p2; // ✅ mutable for live drag
  Color color;
  double? strokeWidth;
  final String? label;
  final String? measureType;
  final String? groupId; // wallGroupId / beamId etc

  MeasuredSegment({
    required this.id,
    required this.docId,
    required this.p1,
    required this.p2,
    required this.color,
    this.strokeWidth,
    this.label,
    this.measureType,
    this.groupId,
  });
}
