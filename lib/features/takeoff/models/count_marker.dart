import 'package:flutter/material.dart';

class CountMarker {
  const CountMarker({
    required this.id,
    required this.groupId,
    required this.position,
    required this.color,
    this.mark = 'tick',
    this.label,
  });

  final String id;
  final String groupId;
  final Offset position;
  final Color color;
  final String mark;
  final String? label;
}
