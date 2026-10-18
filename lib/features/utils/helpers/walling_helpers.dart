import 'dart:math' as math;

import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:flutter/material.dart';

class OpeningType {
  final String name;
  final OpeningCategory category;
  final double widthM;
  final double heightM;
  final bool defaultHasTransom;
  final double defaultTransomHeightM;

  const OpeningType({
    required this.name,
    required this.category,
    required this.widthM,
    required this.heightM,
    this.defaultHasTransom = false,
    this.defaultTransomHeightM = 0.45,
  });
}

class OpeningEntry {
  OpeningType type;
  int qtyPerWall;

  // editable size override
  double? widthOverrideM;
  double? heightOverrideM;

  // optional transom/toplight
  bool hasTransom;
  double transomHeightM;

  // which items to generate
  bool includeLeafOrShutter;
  bool includeFrame;
  bool includeIronmongery;
  bool includeGlazing; // for windows (and transoms)
  FrameMeasureMode frameMeasureMode;
  int doorLeafCount;
  bool leafBoqPerLeaf;
  bool ironmongeryPerLeaf;

  // BOQ picks (optional per item)
  BoqPick? boqLeaf;
  BoqPick? boqFrame;
  BoqPick? boqIron;
  BoqPick? boqGlazing;
  BoqPick? boqTransomGlazing;

  OpeningEntry({
    required this.type,
    this.qtyPerWall = 1,
    this.widthOverrideM,
    this.heightOverrideM,
    bool? hasTransom,
    double? transomHeightM,
    this.includeLeafOrShutter = true,
    this.includeFrame = true,
    this.includeIronmongery = true,
    this.includeGlazing = true,
    this.frameMeasureMode = FrameMeasureMode.number,
    this.doorLeafCount = 1,
    this.leafBoqPerLeaf = false,
    this.ironmongeryPerLeaf = false,
    this.boqLeaf,
    this.boqFrame,
    this.boqIron,
    this.boqGlazing,
    this.boqTransomGlazing,
  }) : hasTransom = hasTransom ?? type.defaultHasTransom,
       transomHeightM = transomHeightM ?? type.defaultTransomHeightM;

  double get w =>
      (widthOverrideM != null && widthOverrideM! > 0)
          ? widthOverrideM!
          : type.widthM;

  double get h =>
      (heightOverrideM != null && heightOverrideM! > 0)
          ? heightOverrideM!
          : type.heightM;

  double get area => w * h * qtyPerWall;

  double get perimeter => 2 * (w + h) * qtyPerWall;

  int get normalizedDoorLeafCount => doorLeafCount == 2 ? 2 : 1;
}

// A remembered template (auto-used next dialog)
class WallTemplate {
  final double heightM;
  final int qtyWalls;
  final int internalFaces; // 0/1/2
  final int externalFaces; // 0/1
  final bool includeWalling;
  final bool includeInternalPlaster;
  final bool includeInternalPaint;
  final bool includeExternalRender;
  final bool includeExternalPaint;

  final Map<String, dynamic>? boqWalling;
  final Map<String, dynamic>? boqIntPlaster;
  final Map<String, dynamic>? boqIntPaint;
  final Map<String, dynamic>? boqExtRender;
  final Map<String, dynamic>? boqExtPaint;

  // A lightweight opening template list (keeps choices + boq picks)
  final List<Map<String, dynamic>> openings;

  const WallTemplate({
    required this.heightM,
    required this.qtyWalls,
    required this.internalFaces,
    required this.externalFaces,
    required this.includeWalling,
    required this.includeInternalPlaster,
    required this.includeInternalPaint,
    required this.includeExternalRender,
    required this.includeExternalPaint,
    required this.boqWalling,
    required this.boqIntPlaster,
    required this.boqIntPaint,
    required this.boqExtRender,
    required this.boqExtPaint,
    required this.openings,
  });
}

Map<String, dynamic> lastWallDefaults = {}; // fast restore
WallTemplate? lastWallTemplate;
String? draftWallGroupId;

// Example opening library (you can expand/replace with Firestore later)
const List<OpeningType> kDefaultOpeningTypes = [
  OpeningType(
    name: 'D1 0.9x2.1',
    category: OpeningCategory.door,
    widthM: 0.90,
    heightM: 2.10,
  ),
  OpeningType(
    name: 'D2 1.2x2.1',
    category: OpeningCategory.door,
    widthM: 1.20,
    heightM: 2.10,
  ),
  OpeningType(
    name: 'W1 1.2x1.2',
    category: OpeningCategory.window,
    widthM: 1.20,
    heightM: 1.20,
  ),
  OpeningType(
    name: 'W2 1.5x1.2',
    category: OpeningCategory.window,
    widthM: 1.50,
    heightM: 1.20,
  ),
  OpeningType(
    name: 'W3 1.5x1.5 + Transom',
    category: OpeningCategory.window,
    widthM: 1.50,
    heightM: 1.50,
    defaultHasTransom: true,
    defaultTransomHeightM: 0.45,
  ),
];

extension OffsetMath on Offset {
  Offset operator -(Offset other) => Offset(dx - other.dx, dy - other.dy);
  double get length => math.sqrt(dx * dx + dy * dy);
}

class FoundationWallLine {
  final String type;
  final String boqCode;
  final String boqDesc;
  final String unit;
  final double qty;

  FoundationWallLine({
    required this.type,
    required this.boqCode,
    required this.boqDesc,
    required this.unit,
    required this.qty,
  });
}

// =========================
// Helper: BoqPick map convert
// =========================
// Map<String, dynamic>? pickToMap(BoqPick? p) {
//   if (p == null) return null;
//   return {'id': p.id, 'code': p.code, 'description': p.description};
// }

// BoqPick? pickFromMap(dynamic v) {
//   if (v is! Map) return null;
//   final m = Map<String, dynamic>.from(v);
//   final id = (m['id'] ?? '').toString();
//   final code = (m['code'] ?? '').toString();
//   final desc = (m['description'] ?? '').toString();
//   if (id.isEmpty && code.isEmpty && desc.isEmpty) return null;
//   return BoqPick(id: id, code: code, description: desc);
// }
