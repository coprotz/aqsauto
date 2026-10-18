import 'package:flutter/material.dart';

class SavedArea {
  final String id;
  final String? docId;
  final String? measureType;
  final String? label;
  final double? value;
  final String? unit;
  final List<Offset> points;
  final Color color;

  // Flags so we know what this polygon represents
  final bool isRebarSlab;
  final bool isRebarFooting;
  final bool isRebarColumn;
  final bool isSlabComposite;
  final bool isRoofingComposite;
  final bool isFootingComposite;
  final bool isColumnComposite;
  final bool isCeilingFinish;

  final bool isHidden;

  SavedArea({
    required this.id,
    this.docId,
    this.measureType,
    this.label,
    this.value,
    this.unit,
    required this.points,
    required this.color,
    this.isRebarSlab = false,
    this.isRebarFooting = false,
    this.isRebarColumn = false,
    this.isSlabComposite = false,
    this.isCeilingFinish = false,
    this.isFootingComposite = false,
    this.isColumnComposite = false,
    this.isRoofingComposite = false,
    this.isHidden = false,
  });
}
