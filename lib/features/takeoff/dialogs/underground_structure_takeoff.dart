import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Parametric AQS take-off for underground rectangular structures.
///
/// The rectangle drawn on the PDF is treated as the OUTER wall footprint.
/// The dialog then derives excavation, blinding, base, walls, roof, formwork,
/// waterproofing, backfill, detailed reinforcement, waterstops and covers.
/// Presets only change sensible defaults: every value remains editable.
enum UndergroundStructureSaveAction { cancel, addMore, finish }

class _Preset {
  const _Preset({
    required this.id,
    required this.label,
    required this.icon,
    required this.wallThickness,
    required this.depth,
    required this.baseThickness,
    required this.roofThickness,
    required this.baseOverhang,
    required this.partitions,
    required this.internalWaterproofing,
    required this.externalWaterproofing,
  });

  final String id;
  final String label;
  final IconData icon;
  final double wallThickness;
  final double depth;
  final double baseThickness;
  final double roofThickness;
  final double baseOverhang;
  final int partitions;
  final bool internalWaterproofing;
  final bool externalWaterproofing;
}

const _presets = <_Preset>[
  _Preset(
    id: 'waterTank',
    label: 'Underground water tank',
    icon: Icons.water_drop_outlined,
    wallThickness: .250,
    depth: 4.000,
    baseThickness: .300,
    roofThickness: .200,
    baseOverhang: .250,
    partitions: 0,
    internalWaterproofing: true,
    externalWaterproofing: true,
  ),
  _Preset(
    id: 'septicTank',
    label: 'Septic tank',
    icon: Icons.waves_outlined,
    wallThickness: .200,
    depth: 2.000,
    baseThickness: .200,
    roofThickness: .150,
    baseOverhang: .150,
    partitions: 1,
    internalWaterproofing: true,
    externalWaterproofing: true,
  ),
  _Preset(
    id: 'manhole',
    label: 'Manhole',
    icon: Icons.grid_view_outlined,
    wallThickness: .150,
    depth: 1.200,
    baseThickness: .150,
    roofThickness: .150,
    baseOverhang: .100,
    partitions: 0,
    internalWaterproofing: false,
    externalWaterproofing: false,
  ),
  _Preset(
    id: 'inspectionChamber',
    label: 'Inspection chamber',
    icon: Icons.select_all_outlined,
    wallThickness: .150,
    depth: .900,
    baseThickness: .150,
    roofThickness: .125,
    baseOverhang: .100,
    partitions: 0,
    internalWaterproofing: false,
    externalWaterproofing: false,
  ),
  _Preset(
    id: 'pumpChamber',
    label: 'Pump chamber',
    icon: Icons.water_outlined,
    wallThickness: .250,
    depth: 3.000,
    baseThickness: .300,
    roofThickness: .200,
    baseOverhang: .250,
    partitions: 0,
    internalWaterproofing: true,
    externalWaterproofing: true,
  ),
  _Preset(
    id: 'custom',
    label: 'Custom chamber',
    icon: Icons.tune,
    wallThickness: .200,
    depth: 2.000,
    baseThickness: .200,
    roofThickness: .150,
    baseOverhang: .150,
    partitions: 0,
    internalWaterproofing: false,
    externalWaterproofing: false,
  ),
];


class _RebarLayer {
  _RebarLayer({
    required this.id,
    required this.component,
    required this.face,
    required this.direction,
    this.barMark = '',
    this.diameterMm = 16,
    this.spacingMm = 150,
    this.countMode = 'auto',
    this.manualCount = 0,
    this.lengthMode = 'auto',
    this.manualLengthM = 0,
    this.boq,
  });

  final String id;
  String component;
  String face;
  String direction;
  String barMark;
  double diameterMm;
  double spacingMm;
  String countMode; // auto | manual
  int manualCount;
  String lengthMode; // auto | manual | drawing
  double manualLengthM;
  BoqPick? boq;
}

class _OutputBoq {
  _OutputBoq({
    required this.key,
    required this.label,
    required this.unit,
    required this.icon,
    this.enabled = true,
  });

  final String key;
  final String label;
  final String unit;
  final IconData icon;
  bool enabled;
  BoqPick? boq;
}

Future<UndergroundStructureSaveAction> openUndergroundStructureTakeoffFromRectangle({
  required Offset p1,
  required Offset p2,
  required Map<String, dynamic> drawingData,
  required String projectId,
  required String buildingId,
  required String drawingId,
  required Color currentColor,
  required CollectionReference<Map<String, dynamic>> measurementsRef,
  required Map<String, dynamic> lastDefaults,
  required Future<BoqPick?> Function(BuildContext ctx) showBoqPicker,
  String? activeLabel,
  VoidCallback? onUpdateViewer,
}) async {
  final context = Get.context;
  if (context == null) return UndergroundStructureSaveAction.cancel;

  double d(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? fallback;
  }

  bool b(dynamic v, bool fallback) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = '${v ?? ''}'.toLowerCase();
    if (['true', '1', 'yes'].contains(s)) return true;
    if (['false', '0', 'no'].contains(s)) return false;
    return fallback;
  }

  double parse(TextEditingController c, double fallback) =>
      double.tryParse(c.text.trim()) ?? fallback;
  int parseInt(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim()) ?? fallback;

  final pxPerM = d(drawingData['pixelsPerUnit'], 0);
  final calibrated = drawingData['calibrated'] == true || pxPerM > 0;
  if (!calibrated || pxPerM <= 0) {
    Get.snackbar('Not calibrated', 'Calibrate the drawing before using Underground Structures.');
    return UndergroundStructureSaveAction.cancel;
  }

  final measuredLength = (p2.dx - p1.dx).abs() / pxPerM;
  final measuredWidth = (p2.dy - p1.dy).abs() / pxPerM;
  if (measuredLength <= 0 || measuredWidth <= 0) {
    Get.snackbar('Invalid rectangle', 'Draw the outside wall footprint again.');
    return UndergroundStructureSaveAction.cancel;
  }

  String selectedPresetId = '${lastDefaults['presetId'] ?? 'waterTank'}';
  var preset = _presets.firstWhere(
    (p) => p.id == selectedPresetId,
    orElse: () => _presets.first,
  );

  TextEditingController ctrl(String key, String fallback) =>
      TextEditingController(text: '${lastDefaults[key] ?? fallback}');

  final labelCtrl = ctrl('label', activeLabel?.trim().isNotEmpty == true ? activeLabel!.trim() : preset.label);
  // Source rectangle always wins for new geometry.
  final outerLCtrl = TextEditingController(text: measuredLength.toStringAsFixed(3));
  final outerWCtrl = TextEditingController(text: measuredWidth.toStringAsFixed(3));
  final wallTCtrl = ctrl('wallThicknessM', preset.wallThickness.toStringAsFixed(3));
  final depthCtrl = ctrl('wallHeightM', preset.depth.toStringAsFixed(3));
  final baseTCtrl = ctrl('baseThicknessM', preset.baseThickness.toStringAsFixed(3));
  final roofTCtrl = ctrl('roofThicknessM', preset.roofThickness.toStringAsFixed(3));
  final overhangCtrl = ctrl('baseOverhangM', preset.baseOverhang.toStringAsFixed(3));
  final blindingTCtrl = ctrl('blindingThicknessM', '0.050');
  final hardcoreTCtrl = ctrl('hardcoreThicknessM', '0.150');
  final workingCtrl = ctrl('workingSpaceM', '0.600');
  final extraExcDepthCtrl = ctrl('extraExcavationDepthM', '0.000');

  final partitionsCtrl = ctrl('partitionCount', '${preset.partitions}');
  final partitionLengthCtrl = ctrl('partitionLengthM', '0.000');
  final partitionTCtrl = ctrl('partitionThicknessM', preset.wallThickness.toStringAsFixed(3));

  final manholeQtyCtrl = ctrl('manholeQty', '1');
  final manholeLCtrl = ctrl('manholeLengthM', '0.800');
  final manholeWCtrl = ctrl('manholeWidthM', '0.800');

  // Reinforcement is optional and is built from independent layers. Each layer
  // can carry its own face, direction, bar mark, diameter, spacing, length
  // source and BOQ item. This mirrors actual structural drawings and avoids
  // forcing top/bottom or near/far faces to use the same reinforcement.
  final steelWasteCtrl = ctrl('steelWastePercent', '5');

  final rebarLayers = <_RebarLayer>[];
  int nextRebarLayerNo = 1;

  _RebarLayer defaultLayer(String component) {
    final id = 'RL${nextRebarLayerNo++}';
    switch (component) {
      case 'wall':
        return _RebarLayer(id: id, component: component, face: 'Near face', direction: 'Vertical', diameterMm: 16, spacingMm: 150);
      case 'partition':
        return _RebarLayer(id: id, component: component, face: 'Face A', direction: 'Vertical', diameterMm: 16, spacingMm: 150);
      case 'roof':
        return _RebarLayer(id: id, component: component, face: 'Bottom', direction: 'X', diameterMm: 12, spacingMm: 200);
      default:
        return _RebarLayer(id: id, component: 'base', face: 'Bottom', direction: 'X', diameterMm: 16, spacingMm: 150);
    }
  }

  BoqPick? rebarBoqFrom(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    if ('${m['id'] ?? ''}${m['code'] ?? ''}${m['description'] ?? ''}'.trim().isEmpty) return null;
    return BoqPick(id: '${m['id'] ?? ''}', code: '${m['code'] ?? ''}', description: '${m['description'] ?? ''}');
  }

  final savedLayers = lastDefaults['rebarLayers'];
  if (savedLayers is List) {
    for (final raw in savedLayers) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final layer = _RebarLayer(
        id: '${m['id'] ?? 'RL${nextRebarLayerNo++}'}',
        component: '${m['component'] ?? 'base'}',
        face: '${m['face'] ?? 'Bottom'}',
        direction: '${m['direction'] ?? 'X'}',
        barMark: '${m['barMark'] ?? ''}',
        diameterMm: d(m['diameterMm'], 16),
        spacingMm: d(m['spacingMm'], 150),
        countMode: '${m['countMode'] ?? 'auto'}',
        manualCount: (m['manualCount'] is num) ? (m['manualCount'] as num).toInt() : int.tryParse('${m['manualCount'] ?? 0}') ?? 0,
        lengthMode: '${m['lengthMode'] ?? 'auto'}',
        manualLengthM: d(m['manualLengthM'], 0),
        boq: rebarBoqFrom(m['boq']),
      );
      rebarLayers.add(layer);
    }
  }
  if (rebarLayers.isEmpty) {
    rebarLayers
      ..add(defaultLayer('base'))
      ..add(_RebarLayer(id: 'RL${nextRebarLayerNo++}', component: 'base', face: 'Bottom', direction: 'Y', diameterMm: 16, spacingMm: 150))
      ..add(defaultLayer('wall'))
      ..add(_RebarLayer(id: 'RL${nextRebarLayerNo++}', component: 'wall', face: 'Near face', direction: 'Horizontal', diameterMm: 12, spacingMm: 200));
  }

  bool includeRoof = b(lastDefaults['includeRoof'], true);
  bool includeInternalWp = b(lastDefaults['includeInternalWaterproofing'], preset.internalWaterproofing);
  bool includeExternalWp = b(lastDefaults['includeExternalWaterproofing'], preset.externalWaterproofing);
  bool includeHardcore = b(lastDefaults['includeHardcore'], true);
  bool includeBlinding = b(lastDefaults['includeBlinding'], true);
  bool includeRebar = b(lastDefaults['includeRebar'] ?? lastDefaults['includeRebarEstimate'], true);
  bool includeWaterstop = b(lastDefaults['includeWaterstop'], true);
  bool includeBackfill = b(lastDefaults['includeBackfill'], true);

  final outputs = <_OutputBoq>[
    _OutputBoq(key: 'excavation', label: 'Excavation', unit: 'm3', icon: Icons.landscape_outlined),
    _OutputBoq(key: 'hardcore', label: 'Hardcore / sub-base', unit: 'm3', icon: Icons.layers_outlined, enabled: includeHardcore),
    _OutputBoq(key: 'blinding', label: 'Blinding concrete', unit: 'm2', icon: Icons.layers, enabled: includeBlinding),
    _OutputBoq(key: 'baseConcrete', label: 'RC base slab', unit: 'm3', icon: Icons.foundation),
    _OutputBoq(key: 'wallConcrete', label: 'RC walls', unit: 'm3', icon: Icons.view_week_outlined),
    _OutputBoq(key: 'roofConcrete', label: 'RC roof slab', unit: 'm3', icon: Icons.border_top, enabled: includeRoof),
    // Formwork is deliberately split by surface/type so each item can be
    // measured and mapped to its own BOQ code/rate. This is important for
    // underground tanks where wall faces, slab soffits, edges and reveals
    // are commonly billed as separate formwork items.
    _OutputBoq(key: 'formworkBaseEdges', label: 'Formwork to base slab edges', unit: 'm2', icon: Icons.crop_square),
    _OutputBoq(key: 'formworkWallsInternal', label: 'Formwork to walls — internal face', unit: 'm2', icon: Icons.view_sidebar_outlined),
    _OutputBoq(key: 'formworkWallsExternal', label: 'Formwork to walls — external face', unit: 'm2', icon: Icons.view_sidebar),
    _OutputBoq(key: 'formworkPartitions', label: 'Formwork to partition walls — both faces', unit: 'm2', icon: Icons.view_week_outlined),
    _OutputBoq(key: 'formworkRoofSoffit', label: 'Formwork to roof slab soffit', unit: 'm2', icon: Icons.border_top),
    _OutputBoq(key: 'formworkRoofEdges', label: 'Formwork to roof slab edges', unit: 'm2', icon: Icons.border_outer),
    _OutputBoq(key: 'formworkOpeningReveals', label: 'Formwork to manhole / opening reveals', unit: 'm2', icon: Icons.select_all),
    _OutputBoq(key: 'internalWaterproofing', label: 'Internal waterproofing', unit: 'm2', icon: Icons.water_drop_outlined, enabled: includeInternalWp),
    _OutputBoq(key: 'externalWaterproofing', label: 'External waterproofing', unit: 'm2', icon: Icons.shield_outlined, enabled: includeExternalWp),
    _OutputBoq(key: 'waterstop', label: 'Construction-joint waterstop', unit: 'm', icon: Icons.linear_scale, enabled: includeWaterstop),
    _OutputBoq(key: 'backfill', label: 'Backfilling around structure', unit: 'm3', icon: Icons.landscape, enabled: includeBackfill),
    _OutputBoq(key: 'manholeCover', label: 'Manhole / access cover', unit: 'nr', icon: Icons.grid_view_outlined),
  ];

  BoqPick? boqFrom(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    if ('${m['id'] ?? ''}${m['code'] ?? ''}${m['description'] ?? ''}'.trim().isEmpty) return null;
    return BoqPick(
      id: '${m['id'] ?? ''}',
      code: '${m['code'] ?? ''}',
      description: '${m['description'] ?? ''}',
    );
  }

  final savedBoqs = lastDefaults['boqs'];
  if (savedBoqs is Map) {
    // Backward compatibility: older saved defaults had a single `formwork`
    // BOQ target. When no specific formwork target exists, use that legacy
    // target as the starting selection for each new formwork category.
    final legacyFormworkBoq = boqFrom(savedBoqs['formwork']);
    for (final output in outputs) {
      output.boq = boqFrom(savedBoqs[output.key]);
      if (output.boq == null && output.key.startsWith('formwork')) {
        output.boq = legacyFormworkBoq;
      }
    }
  }

  Map<String, double> calculate() {
    final outerL = parse(outerLCtrl, measuredLength).clamp(.001, 100000.0).toDouble();
    final outerW = parse(outerWCtrl, measuredWidth).clamp(.001, 100000.0).toDouble();
    final wallT = parse(wallTCtrl, .2).clamp(.001, outerL < outerW ? outerL / 2 : outerW / 2).toDouble();
    final wallH = parse(depthCtrl, 2).clamp(.001, 10000.0).toDouble();
    final baseT = parse(baseTCtrl, .2).clamp(0.0, 1000.0).toDouble();
    final roofT = includeRoof ? parse(roofTCtrl, .15).clamp(0.0, 1000.0).toDouble() : 0.0;
    final overhang = parse(overhangCtrl, .15).clamp(0.0, 1000.0).toDouble();
    final blindT = includeBlinding ? parse(blindingTCtrl, .05).clamp(0.0, 1000.0).toDouble() : 0.0;
    final hardcoreT = includeHardcore ? parse(hardcoreTCtrl, .15).clamp(0.0, 1000.0).toDouble() : 0.0;
    final working = parse(workingCtrl, .6).clamp(0.0, 1000.0).toDouble();
    final extraDepth = parse(extraExcDepthCtrl, 0).clamp(0.0, 1000.0).toDouble();

    final innerL = (outerL - 2 * wallT).clamp(0.0, outerL).toDouble();
    final innerW = (outerW - 2 * wallT).clamp(0.0, outerW).toDouble();
    final outerArea = outerL * outerW;
    final innerArea = innerL * innerW;
    final baseL = outerL + 2 * overhang;
    final baseW = outerW + 2 * overhang;
    final baseArea = baseL * baseW;

    final partitionCount = parseInt(partitionsCtrl, 0).clamp(0, 50).toInt();
    final enteredPartitionLength = parse(partitionLengthCtrl, 0);
    final partitionLength = enteredPartitionLength > 0 ? enteredPartitionLength : innerW;
    final partitionT = parse(partitionTCtrl, wallT).clamp(.001, 10.0).toDouble();
    final partitionConcrete = partitionCount * partitionLength * wallH * partitionT;

    final wallRingConcrete = (outerArea - innerArea) * wallH;
    final wallConcrete = wallRingConcrete + partitionConcrete;
    final baseConcrete = baseArea * baseT;

    final manholeQty = parseInt(manholeQtyCtrl, 0).clamp(0, 100).toInt();
    final manholeArea = parse(manholeLCtrl, .8).clamp(0.0, outerL) *
        parse(manholeWCtrl, .8).clamp(0.0, outerW) * manholeQty;
    final roofPlanNet = (outerArea - manholeArea).clamp(0.0, outerArea).toDouble();
    final roofConcrete = roofPlanNet * roofT;

    final excavationL = baseL + 2 * working;
    final excavationW = baseW + 2 * working;
    final excavationDepth = wallH + baseT + blindT + hardcoreT + roofT + extraDepth;
    final excavation = excavationL * excavationW * excavationDepth;
    final blindingArea = includeBlinding ? baseArea : 0.0;
    final blindingVolume = blindingArea * blindT;
    final hardcoreArea = includeHardcore ? baseArea : 0.0;
    final hardcore = hardcoreArea * hardcoreT;

    final innerPerimeter = 2 * (innerL + innerW);
    final outerPerimeter = 2 * (outerL + outerW);

    // Formwork quantities by type/surface. Keep these quantities separate all
    // the way through saving so the Engineer/QS may use different BOQ codes
    // and rates, or deliberately map several categories to the same BOQ item.
    final formworkWallsInternal = innerPerimeter * wallH;
    final formworkWallsExternal = outerPerimeter * wallH;
    final formworkPartitions = partitionCount * partitionLength * wallH * 2;
    final formworkRoofSoffit = includeRoof ? (innerArea - manholeArea).clamp(0.0, innerArea).toDouble() : 0.0;
    final formworkRoofEdges = includeRoof ? outerPerimeter * roofT : 0.0;
    final formworkOpeningReveals = includeRoof && manholeQty > 0
        ? manholeQty * 2 * (parse(manholeLCtrl, .8) + parse(manholeWCtrl, .8)) * roofT
        : 0.0;
    final formworkBaseEdges = 2 * (baseL + baseW) * baseT;
    final formwork = formworkBaseEdges +
        formworkWallsInternal +
        formworkWallsExternal +
        formworkPartitions +
        formworkRoofSoffit +
        formworkRoofEdges +
        formworkOpeningReveals;

    final partitionFaces = formworkPartitions;

    final internalWp = innerArea + innerPerimeter * wallH + partitionFaces;
    final externalWp = outerPerimeter * wallH;
    final waterstop = outerPerimeter + partitionCount * partitionLength;

    // Reinforcement layers are measured independently. Auto mode derives bar
    // count and length from geometry; manual/drawing mode allows complex U/L/
    // cranked bars to use a QS-entered developed length. Unit mass = d²/162.
    double barKgM(double diameterMm) => (diameterMm * diameterMm) / 162.0;
    int barsAcross(double dimensionM, double spacingMm) {
      if (dimensionM <= 0 || spacingMm <= 0) return 0;
      return (dimensionM / (spacingMm / 1000.0)).ceil() + 1;
    }

    final wasteFactor = 1 + parse(steelWasteCtrl, 5).clamp(0.0, 100.0).toDouble() / 100;
    final totalMainWallRun = outerPerimeter;
    final totalPartitionRun = partitionCount * partitionLength;

    int autoCount(_RebarLayer layer) {
      if (layer.countMode == 'manual') return layer.manualCount < 0 ? 0 : layer.manualCount;
      final spacing = layer.spacingMm.clamp(1.0, 5000.0).toDouble();
      switch (layer.component) {
        case 'base':
          return layer.direction == 'Y' ? barsAcross(baseL, spacing) : barsAcross(baseW, spacing);
        case 'roof':
          return layer.direction == 'Y' ? barsAcross(outerL, spacing) : barsAcross(outerW, spacing);
        case 'partition':
          if (partitionCount <= 0) return 0;
          if (layer.direction == 'Horizontal') return barsAcross(wallH, spacing) * partitionCount;
          return barsAcross(totalPartitionRun, spacing);
        case 'wall':
          if (layer.direction == 'Horizontal') return barsAcross(wallH, spacing);
          return barsAcross(totalMainWallRun, spacing);
        default:
          return layer.manualCount;
      }
    }

    double autoBarLength(_RebarLayer layer) {
      if (layer.lengthMode != 'auto') return layer.manualLengthM.clamp(0.0, 100000.0).toDouble();
      switch (layer.component) {
        case 'base':
          return layer.direction == 'Y' ? baseW : baseL;
        case 'roof':
          return layer.direction == 'Y' ? outerW : outerL;
        case 'partition':
          if (layer.direction == 'Horizontal') return partitionLength;
          return wallH;
        case 'wall':
          if (layer.direction == 'Horizontal') return totalMainWallRun;
          return wallH;
        default:
          return layer.manualLengthM.clamp(0.0, 100000.0).toDouble();
      }
    }

    double layerWeight(_RebarLayer layer) {
      if (!includeRebar) return 0;
      if (layer.component == 'roof' && !includeRoof) return 0;
      if (layer.component == 'partition' && partitionCount <= 0) return 0;
      final count = autoCount(layer);
      final length = autoBarLength(layer);
      final faceMultiplier = layer.face.startsWith('Both') ? 2.0 : 1.0;
      return count * length * faceMultiplier * barKgM(layer.diameterMm.clamp(4.0, 60.0).toDouble()) * wasteFactor;
    }

    double componentWeight(String component) => rebarLayers
        .where((layer) => layer.component == component)
        .fold<double>(0, (sum, layer) => sum + layerWeight(layer));

    final baseReinforcement = componentWeight('base');
    final wallReinforcement = componentWeight('wall');
    final partitionReinforcement = componentWeight('partition');
    final roofReinforcement = componentWeight('roof');
    final reinforcement = baseReinforcement + wallReinforcement + partitionReinforcement + roofReinforcement;

    // Backfill is excavation outside the structural envelope. The internal
    // chamber void is deliberately NOT counted as backfill.
    final structuralEnvelope =
        baseArea * (hardcoreT + blindT + baseT) + outerArea * (wallH + roofT);
    final backfill = includeBackfill ? (excavation - structuralEnvelope).clamp(0.0, excavation).toDouble() : 0.0;

    return {
      'outerLengthM': outerL,
      'outerWidthM': outerW,
      'innerLengthM': innerL,
      'innerWidthM': innerW,
      'wallThicknessM': wallT,
      'wallHeightM': wallH,
      'baseLengthM': baseL,
      'baseWidthM': baseW,
      'baseThicknessM': baseT,
      'roofThicknessM': roofT,
      'excavationLengthM': excavationL,
      'excavationWidthM': excavationW,
      'excavationDepthM': excavationDepth,
      'excavation': excavation,
      'hardcore': hardcore,
      'hardcoreAreaM2': hardcoreArea,
      'hardcoreThicknessM': hardcoreT,
      'blinding': blindingArea,
      'blindingAreaM2': blindingArea,
      'blindingThicknessM': blindT,
      'blindingVolumeM3': blindingVolume,
      'baseConcrete': baseConcrete,
      'wallConcrete': wallConcrete,
      'roofConcrete': roofConcrete,
      'formwork': formwork, // total retained for live summary / compatibility
      'formworkBaseEdges': formworkBaseEdges,
      'formworkWallsInternal': formworkWallsInternal,
      'formworkWallsExternal': formworkWallsExternal,
      'formworkPartitions': formworkPartitions,
      'formworkRoofSoffit': formworkRoofSoffit,
      'formworkRoofEdges': formworkRoofEdges,
      'formworkOpeningReveals': formworkOpeningReveals,
      'baseReinforcement': baseReinforcement,
      'wallReinforcement': wallReinforcement,
      'partitionReinforcement': partitionReinforcement,
      'roofReinforcement': roofReinforcement,
      'reinforcement': reinforcement,
      'internalWaterproofing': includeInternalWp ? internalWp : 0,
      'externalWaterproofing': includeExternalWp ? externalWp : 0,
      'waterstop': includeWaterstop ? waterstop : 0,
      'backfill': backfill,
      'manholeCover': manholeQty.toDouble(),
      'manholeAreaM2': manholeArea,
      'partitionConcreteM3': partitionConcrete,
    };
  }

  InputDecoration deco(String label, {String? suffix}) => InputDecoration(
        labelText: label,
        suffixText: suffix,
        isDense: true,
        border: const OutlineInputBorder(),
      );

  VoidCallback? refreshDialog;

  Widget numberField(TextEditingController c, String label, {String? suffix, double width = 165}) =>
      SizedBox(
        width: width,
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: deco(label, suffix: suffix),
          onChanged: (_) => refreshDialog?.call(),
        ),
      );

  Widget metric(String label, double value, String unit) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 2),
            Text('${value.toStringAsFixed(value.abs() >= 100 ? 1 : 3)} $unit',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      );

  void applyPreset(_Preset p) {
    preset = p;
    selectedPresetId = p.id;
    labelCtrl.text = p.label;
    wallTCtrl.text = p.wallThickness.toStringAsFixed(3);
    depthCtrl.text = p.depth.toStringAsFixed(3);
    baseTCtrl.text = p.baseThickness.toStringAsFixed(3);
    roofTCtrl.text = p.roofThickness.toStringAsFixed(3);
    overhangCtrl.text = p.baseOverhang.toStringAsFixed(3);
    partitionsCtrl.text = '${p.partitions}';
    partitionTCtrl.text = p.wallThickness.toStringAsFixed(3);
    includeInternalWp = p.internalWaterproofing;
    includeExternalWp = p.externalWaterproofing;
  }

  bool allEnabledBoqsSelected() {
    final q = calculate();
    final standardOk = outputs.where((o) => o.enabled && (q[o.key] ?? 0) > 0).every((o) => o.boq != null);
    if (!standardOk || !includeRebar) return standardOk;
    final activeLayers = rebarLayers.where((layer) {
      if (layer.component == 'roof' && !includeRoof) return false;
      if (layer.component == 'partition' && parseInt(partitionsCtrl, 0) <= 0) return false;
      return true;
    });
    return activeLayers.every((layer) => layer.boq != null);
  }

  bool dialogMaximized = false;
  bool dialogMinimized = false;

  final action = await Get.dialog<UndergroundStructureSaveAction>(
        StatefulBuilder(
          builder: (dialogContext, setState) {
            refreshDialog = () => setState(() {});
            final q = calculate();
            // Keep output toggles in sync with component toggles.
            for (final o in outputs) {
              if (o.key == 'hardcore') o.enabled = includeHardcore;
              if (o.key == 'blinding') o.enabled = includeBlinding;
              if (o.key == 'roofConcrete') o.enabled = includeRoof;
              if (o.key == 'formworkRoofSoffit' || o.key == 'formworkRoofEdges' || o.key == 'formworkOpeningReveals') {
                o.enabled = includeRoof;
              }
              if (o.key == 'formworkPartitions') {
                o.enabled = parseInt(partitionsCtrl, 0) > 0;
              }
              if (o.key == 'internalWaterproofing') o.enabled = includeInternalWp;
              if (o.key == 'externalWaterproofing') o.enabled = includeExternalWp;
              if (o.key == 'waterstop') o.enabled = includeWaterstop;
              if (o.key == 'backfill') o.enabled = includeBackfill;
            }

            return AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              title: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Underground Structures')),
                  IconButton(
                    tooltip: dialogMinimized ? 'Restore' : 'Minimize',
                    onPressed: () => setState(() {
                      dialogMinimized = !dialogMinimized;
                      if (dialogMinimized) dialogMaximized = false;
                    }),
                    icon: Icon(dialogMinimized ? Icons.open_in_full : Icons.minimize),
                  ),
                  if (!dialogMinimized)
                    IconButton(
                      tooltip: dialogMaximized ? 'Restore size' : 'Maximize',
                      onPressed: () => setState(() => dialogMaximized = !dialogMaximized),
                      icon: Icon(dialogMaximized ? Icons.close_fullscreen : Icons.open_in_full),
                    ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Get.back(result: UndergroundStructureSaveAction.cancel),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              content: dialogMinimized
                  ? const SizedBox(width: 420, height: 1)
                  : SizedBox(
                width: dialogMaximized
                    ? MediaQuery.sizeOf(dialogContext).width * .94
                    : 1040,
                height: dialogMaximized
                    ? MediaQuery.sizeOf(dialogContext).height * .84
                    : MediaQuery.sizeOf(dialogContext).height * .76,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('1  Choose structure preset', style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _presets.map((p) {
                          final selected = p.id == selectedPresetId;
                          return ChoiceChip(
                            avatar: Icon(p.icon, size: 18),
                            label: Text(p.label),
                            selected: selected,
                            onSelected: (_) => setState(() => applyPreset(p)),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 18),
                      TextField(controller: labelCtrl, decoration: deco('Take-off label')),
                      const SizedBox(height: 18),
                      Text('2  Geometry', style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text('The rectangle you drew is the outside face of the chamber walls. Dimensions remain editable.',
                          style: Theme.of(dialogContext).textTheme.bodySmall),
                      const SizedBox(height: 12),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        numberField(outerLCtrl, 'Outer length', suffix: 'm'),
                        numberField(outerWCtrl, 'Outer width', suffix: 'm'),
                        numberField(wallTCtrl, 'Wall thickness', suffix: 'm'),
                        numberField(depthCtrl, 'Wall / clear depth', suffix: 'm'),
                        numberField(baseTCtrl, 'Base thickness', suffix: 'm'),
                        numberField(overhangCtrl, 'Base projection', suffix: 'm'),
                        numberField(roofTCtrl, 'Roof thickness', suffix: 'm'),
                        numberField(workingCtrl, 'Working space', suffix: 'm'),
                        numberField(extraExcDepthCtrl, 'Extra excavation depth', suffix: 'm'),
                      ]),
                      const SizedBox(height: 12),
                      Wrap(spacing: 10, runSpacing: 4, children: [
                        FilterChip(label: const Text('Roof slab'), selected: includeRoof, onSelected: (v) => setState(() => includeRoof = v)),
                        FilterChip(label: const Text('Backfill'), selected: includeBackfill, onSelected: (v) => setState(() => includeBackfill = v)),
                        FilterChip(label: const Text('Include reinforcement'), selected: includeRebar, onSelected: (v) => setState(() => includeRebar = v)),
                        FilterChip(label: const Text('Internal waterproofing'), selected: includeInternalWp, onSelected: (v) => setState(() => includeInternalWp = v)),
                        FilterChip(label: const Text('External waterproofing'), selected: includeExternalWp, onSelected: (v) => setState(() => includeExternalWp = v)),
                        FilterChip(label: const Text('Waterstop'), selected: includeWaterstop, onSelected: (v) => setState(() => includeWaterstop = v)),
                      ]),
                      const SizedBox(height: 18),
                      Text('3  Formation layers', style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text('Include only the layers shown in the BOQ/drawings. Blinding is measured by plan area (m²); its thickness is retained for geometry and excavation depth.', style: Theme.of(dialogContext).textTheme.bodySmall),
                      const SizedBox(height: 10),
                      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        FilterChip(label: const Text('Include hardcore'), selected: includeHardcore, onSelected: (v) => setState(() => includeHardcore = v)),
                        if (includeHardcore) numberField(hardcoreTCtrl, 'Hardcore thickness', suffix: 'm'),
                        FilterChip(label: const Text('Include blinding'), selected: includeBlinding, onSelected: (v) => setState(() => includeBlinding = v)),
                        if (includeBlinding) numberField(blindingTCtrl, 'Blinding thickness', suffix: 'm'),
                      ]),
                      const SizedBox(height: 18),
                      Text('4  Partitions & access opening', style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        numberField(partitionsCtrl, 'Partition count', suffix: 'nr'),
                        numberField(partitionLengthCtrl, 'Each partition length', suffix: 'm'),
                        numberField(partitionTCtrl, 'Partition thickness', suffix: 'm'),
                        numberField(manholeQtyCtrl, 'Access opening qty', suffix: 'nr'),
                        numberField(manholeLCtrl, 'Opening length', suffix: 'm'),
                        numberField(manholeWCtrl, 'Opening width', suffix: 'm'),
                      ]),
                      const SizedBox(height: 6),
                      Text('Leave partition length at 0.000 to use the calculated internal width.', style: Theme.of(dialogContext).textTheme.bodySmall),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('5  Reinforcement', style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text('Optional. Add each actual reinforcement layer separately so top/bottom and near/far faces can use different bars, spacing and BOQ codes.', style: Theme.of(dialogContext).textTheme.bodySmall),
                              ],
                            ),
                          ),
                          Switch.adaptive(value: includeRebar, onChanged: (v) => setState(() => includeRebar = v)),
                        ],
                      ),
                      if (includeRebar) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(onPressed: () => setState(() => rebarLayers.add(defaultLayer('base'))), icon: const Icon(Icons.add), label: const Text('Base layer')),
                            FilledButton.tonalIcon(onPressed: () => setState(() => rebarLayers.add(defaultLayer('wall'))), icon: const Icon(Icons.add), label: const Text('Wall layer')),
                            if (parseInt(partitionsCtrl, 0) > 0) FilledButton.tonalIcon(onPressed: () => setState(() => rebarLayers.add(defaultLayer('partition'))), icon: const Icon(Icons.add), label: const Text('Partition layer')),
                            if (includeRoof) FilledButton.tonalIcon(onPressed: () => setState(() => rebarLayers.add(defaultLayer('roof'))), icon: const Icon(Icons.add), label: const Text('Roof layer')),
                            SizedBox(width: 210, child: numberField(steelWasteCtrl, 'Steel waste / laps', suffix: '%', width: 210)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (rebarLayers.isEmpty)
                          const Text('No reinforcement layers added. Use the buttons above, or switch reinforcement off and measure steel separately with the Rebar Slab/Length tools.'),
                        ...rebarLayers.asMap().entries.map((entry) {
                          final index = entry.key;
                          final layer = entry.value;
                          final weight = (() {
                            final all = calculate();
                            final wasteFactor = 1 + parse(steelWasteCtrl, 5).clamp(0.0, 100.0).toDouble() / 100;
                            double kgm(double dia) => dia * dia / 162.0;
                            int count;
                            double length;
                            if (layer.countMode == 'manual') {
                              count = layer.manualCount;
                            } else {
                              final spacing = layer.spacingMm <= 0 ? 150 : layer.spacingMm;
                              int across(double m) => (m / (spacing / 1000)).ceil() + 1;
                              switch (layer.component) {
                                case 'base': count = layer.direction == 'Y' ? across(all['baseLengthM']!) : across(all['baseWidthM']!); break;
                                case 'roof': count = layer.direction == 'Y' ? across(all['outerLengthM']!) : across(all['outerWidthM']!); break;
                                case 'wall': count = layer.direction == 'Horizontal' ? across(all['wallHeightM']!) : across(2 * (all['outerLengthM']! + all['outerWidthM']!)); break;
                                case 'partition': count = layer.direction == 'Horizontal' ? across(all['wallHeightM']!) * parseInt(partitionsCtrl, 0) : across(parse(partitionLengthCtrl, 0) > 0 ? parse(partitionLengthCtrl, 0) * parseInt(partitionsCtrl, 0) : all['innerWidthM']! * parseInt(partitionsCtrl, 0)); break;
                                default: count = layer.manualCount;
                              }
                            }
                            if (layer.lengthMode == 'auto') {
                              switch (layer.component) {
                                case 'base': length = layer.direction == 'Y' ? all['baseWidthM']! : all['baseLengthM']!; break;
                                case 'roof': length = layer.direction == 'Y' ? all['outerWidthM']! : all['outerLengthM']!; break;
                                case 'wall': length = layer.direction == 'Horizontal' ? 2 * (all['outerLengthM']! + all['outerWidthM']!) : all['wallHeightM']!; break;
                                case 'partition': length = layer.direction == 'Horizontal' ? (parse(partitionLengthCtrl, 0) > 0 ? parse(partitionLengthCtrl, 0) : all['innerWidthM']!) : all['wallHeightM']!; break;
                                default: length = layer.manualLengthM;
                              }
                            } else {
                              length = layer.manualLengthM;
                            }
                            final faceMultiplier = layer.face.startsWith('Both') ? 2.0 : 1.0;
                            return count * length * faceMultiplier * kgm(layer.diameterMm) * wasteFactor;
                          })();
                          List<String> facesFor(String component) => component == 'wall'
                              ? const ['Near face', 'Far face', 'Both faces', 'Custom']
                              : component == 'partition'
                                  ? const ['Face A', 'Face B', 'Both faces', 'Custom']
                                  : const ['Top', 'Bottom', 'Custom'];
                          List<String> dirsFor(String component) => (component == 'wall' || component == 'partition')
                              ? const ['Vertical', 'Horizontal', 'Custom']
                              : const ['X', 'Y', 'Custom'];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(child: Text('${layer.component.toUpperCase()} • ${layer.face} • ${layer.direction}', style: const TextStyle(fontWeight: FontWeight.w700))),
                                    Text('${weight.toStringAsFixed(2)} kg', style: const TextStyle(fontWeight: FontWeight.w700)),
                                    IconButton(tooltip: 'Delete layer', onPressed: () => setState(() => rebarLayers.removeAt(index)), icon: const Icon(Icons.delete_outline)),
                                  ]),
                                  const SizedBox(height: 8),
                                  Wrap(spacing: 10, runSpacing: 10, children: [
                                    SizedBox(width: 150, child: DropdownButtonFormField<String>(value: layer.component, decoration: deco('Component'), items: const [
                                      DropdownMenuItem(value: 'base', child: Text('Base slab')),
                                      DropdownMenuItem(value: 'wall', child: Text('Walls')),
                                      DropdownMenuItem(value: 'partition', child: Text('Partitions')),
                                      DropdownMenuItem(value: 'roof', child: Text('Roof slab')),
                                    ], onChanged: (v) => setState(() { if (v != null) { layer.component = v; layer.face = facesFor(v).first; layer.direction = dirsFor(v).first; } }))),
                                    SizedBox(width: 150, child: DropdownButtonFormField<String>(value: facesFor(layer.component).contains(layer.face) ? layer.face : facesFor(layer.component).first, decoration: deco('Face / layer'), items: facesFor(layer.component).map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() { if (v != null) layer.face = v; }))),
                                    SizedBox(width: 140, child: DropdownButtonFormField<String>(value: dirsFor(layer.component).contains(layer.direction) ? layer.direction : dirsFor(layer.component).first, decoration: deco('Direction'), items: dirsFor(layer.component).map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() { if (v != null) layer.direction = v; }))),
                                    SizedBox(width: 120, child: TextFormField(initialValue: layer.barMark, decoration: deco('Bar mark'), onChanged: (v) { layer.barMark = v; refreshDialog?.call(); })),
                                    SizedBox(width: 130, child: TextFormField(initialValue: layer.diameterMm.toStringAsFixed(0), keyboardType: TextInputType.number, decoration: deco('Diameter', suffix: 'mm'), onChanged: (v) { layer.diameterMm = double.tryParse(v) ?? layer.diameterMm; refreshDialog?.call(); })),
                                    SizedBox(width: 130, child: TextFormField(initialValue: layer.spacingMm.toStringAsFixed(0), keyboardType: TextInputType.number, decoration: deco('Spacing', suffix: 'mm'), onChanged: (v) { layer.spacingMm = double.tryParse(v) ?? layer.spacingMm; refreshDialog?.call(); })),
                                  ]),
                                  const SizedBox(height: 10),
                                  Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                    SizedBox(width: 150, child: DropdownButtonFormField<String>(value: layer.countMode, decoration: deco('Bar count'), items: const [DropdownMenuItem(value: 'auto', child: Text('Auto')), DropdownMenuItem(value: 'manual', child: Text('Manual'))], onChanged: (v) => setState(() { if (v != null) layer.countMode = v; }))),
                                    if (layer.countMode == 'manual') SizedBox(width: 130, child: TextFormField(initialValue: '${layer.manualCount}', keyboardType: TextInputType.number, decoration: deco('No. bars'), onChanged: (v) { layer.manualCount = int.tryParse(v) ?? layer.manualCount; refreshDialog?.call(); })),
                                    SizedBox(width: 180, child: DropdownButtonFormField<String>(value: layer.lengthMode, decoration: deco('Bar length source'), items: const [
                                      DropdownMenuItem(value: 'auto', child: Text('Auto from geometry')),
                                      DropdownMenuItem(value: 'manual', child: Text('Enter manually')),
                                      DropdownMenuItem(value: 'drawing', child: Text('Drawing / Length tool')),
                                    ], onChanged: (v) => setState(() { if (v != null) layer.lengthMode = v; }))),
                                    if (layer.lengthMode != 'auto') SizedBox(width: 150, child: TextFormField(initialValue: layer.manualLengthM == 0 ? '' : layer.manualLengthM.toStringAsFixed(3), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: deco('Bar length', suffix: 'm'), onChanged: (v) { layer.manualLengthM = double.tryParse(v) ?? layer.manualLengthM; refreshDialog?.call(); })),
                                    OutlinedButton.icon(onPressed: () async { final picked = await showBoqPicker(dialogContext); if (picked != null) setState(() => layer.boq = picked); }, icon: Icon(layer.boq == null ? Icons.add_link : Icons.edit_outlined), label: Text(layer.boq == null ? 'Select BOQ' : '${layer.boq!.code}')),
                                  ]),
                                  if (layer.lengthMode == 'drawing') ...[
                                    const SizedBox(height: 8),
                                    Row(children: [
                                      const Expanded(child: Text('For U/L/cranked bars, minimize this form, measure the developed bar length with the Length tool, then enter the measured length here.')),
                                      TextButton.icon(onPressed: () => setState(() { dialogMinimized = true; dialogMaximized = false; }), icon: const Icon(Icons.minimize), label: const Text('Minimize form')),
                                    ]),
                                  ],
                                  if (layer.boq == null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Select a BOQ item for this reinforcement layer.', style: TextStyle(color: Theme.of(dialogContext).colorScheme.error, fontSize: 12))),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 4),
                        Text('Complex hooks, laps, curtailment and trimming bars can be recorded as separate layers with manual count/length. Detailed BBS remains the final authority.', style: Theme.of(dialogContext).textTheme.bodySmall),
                      ],
                      const SizedBox(height: 18),
                      Text('6  Live quantity summary', style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        metric('Internal size', q['innerLengthM']!, 'm L'),
                        metric('Internal width', q['innerWidthM']!, 'm'),
                        metric('Excavation', q['excavation']!, 'm³'),
                        if (includeHardcore) metric('Hardcore', q['hardcore']!, 'm³'),
                        if (includeBlinding) metric('Blinding', q['blinding']!, 'm²'),
                        metric('Base concrete', q['baseConcrete']!, 'm³'),
                        metric('Wall concrete', q['wallConcrete']!, 'm³'),
                        if (includeRoof) metric('Roof concrete', q['roofConcrete']!, 'm³'),
                        metric('Formwork — total', q['formwork']!, 'm²'),
                        metric('FW base edges', q['formworkBaseEdges']!, 'm²'),
                        metric('FW wall internal', q['formworkWallsInternal']!, 'm²'),
                        metric('FW wall external', q['formworkWallsExternal']!, 'm²'),
                        if (q['formworkPartitions']! > 0) metric('FW partitions', q['formworkPartitions']!, 'm²'),
                        if (includeRoof && q['formworkRoofSoffit']! > 0) metric('FW roof soffit', q['formworkRoofSoffit']!, 'm²'),
                        if (includeRoof && q['formworkRoofEdges']! > 0) metric('FW roof edges', q['formworkRoofEdges']!, 'm²'),
                        if (includeRoof && q['formworkOpeningReveals']! > 0) metric('FW opening reveals', q['formworkOpeningReveals']!, 'm²'),
                        if (includeRebar) metric('Base rebar', q['baseReinforcement']!, 'kg'),
                        if (includeRebar) metric('Wall rebar', q['wallReinforcement']!, 'kg'),
                        if (includeRebar && q['partitionReinforcement']! > 0) metric('Partition rebar', q['partitionReinforcement']!, 'kg'),
                        if (includeRebar && includeRoof) metric('Roof rebar', q['roofReinforcement']!, 'kg'),
                        if (includeRebar) metric('Total rebar', q['reinforcement']!, 'kg'),
                        if (includeInternalWp) metric('Internal W/P', q['internalWaterproofing']!, 'm²'),
                        if (includeBackfill) metric('Backfill', q['backfill']!, 'm³'),
                      ]),
                      const SizedBox(height: 18),
                      Text('7  Map calculated outputs to BOQ', style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      ...outputs.where((o) => o.enabled && (q[o.key] ?? 0) > 0).map((o) {
                        final value = q[o.key] ?? 0;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 7),
                          child: ListTile(
                            leading: Icon(o.icon),
                            title: Text(o.label),
                            subtitle: Text(o.boq == null
                                ? '${value.toStringAsFixed(3)} ${o.unit} • Select BOQ item'
                                : '${value.toStringAsFixed(3)} ${o.unit} • ${o.boq!.code} — ${o.boq!.description}'),
                            trailing: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showBoqPicker(dialogContext);
                                if (picked != null) setState(() => o.boq = picked);
                              },
                              icon: Icon(o.boq == null ? Icons.add_link : Icons.edit_outlined, size: 18),
                              label: Text(o.boq == null ? 'Select BOQ' : 'Change'),
                            ),
                          ),
                        );
                      }),
                      if (!allEnabledBoqsSelected())
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Select a BOQ item for every enabled output before saving.',
                              style: TextStyle(color: Theme.of(dialogContext).colorScheme.error, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ),
              ),
              actions: dialogMinimized ? const [] : [
                TextButton(onPressed: () => Get.back(result: UndergroundStructureSaveAction.cancel), child: const Text('Cancel')),
                OutlinedButton.icon(
                  onPressed: allEnabledBoqsSelected() ? () => Get.back(result: UndergroundStructureSaveAction.addMore) : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Save & Add another'),
                ),
                FilledButton.icon(
                  onPressed: allEnabledBoqsSelected() ? () => Get.back(result: UndergroundStructureSaveAction.finish) : null,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save & Finish'),
                ),
              ],
            );
          },
        ),
        barrierDismissible: false,
      ) ??
      UndergroundStructureSaveAction.cancel;

  if (action == UndergroundStructureSaveAction.cancel) {
    for (final c in [
      labelCtrl, outerLCtrl, outerWCtrl, wallTCtrl, depthCtrl, baseTCtrl,
      roofTCtrl, overhangCtrl, blindingTCtrl, hardcoreTCtrl, workingCtrl,
      extraExcDepthCtrl, partitionsCtrl, partitionLengthCtrl, partitionTCtrl,
      manholeQtyCtrl, manholeLCtrl, manholeWCtrl,
steelWasteCtrl,
    ]) {
      c.dispose();
    }
    return action;
  }

  final q = calculate();
  final assemblyId = measurementsRef.doc().id;
  final now = FieldValue.serverTimestamp();
  final label = labelCtrl.text.trim().isEmpty ? preset.label : labelCtrl.text.trim();
  final p1m = {'x': p1.dx, 'y': p1.dy};
  final p2m = {'x': p2.dx, 'y': p2.dy};
  final polygon = [p1m, {'x': p2.dx, 'y': p1.dy}, p2m, {'x': p1.dx, 'y': p2.dy}];

  Map<String, dynamic> common() => {
        'projectId': projectId,
        'buildingId': buildingId,
        'drawingId': drawingId,
        'measureType': 'undergroundStructureAssembly',
        'typeGroup': 'undergroundStructureAssembly',
        'assemblyId': assemblyId,
        'structurePreset': selectedPresetId,
        'structurePresetLabel': preset.label,
        'label': label,
        'p1': p1m,
        'p2': p2m,
        'polygon': polygon,
        'rectangleSource': 'outerWallOppositeCorners',
        'sourceRectangleWidthPx': (p2.dx - p1.dx).abs(),
        'sourceRectangleHeightPx': (p2.dy - p1.dy).abs(),
        ...q,
        'partitionCount': parseInt(partitionsCtrl, 0),
        'partitionLengthM': parse(partitionLengthCtrl, 0),
        'partitionThicknessM': parse(partitionTCtrl, .2),
        'manholeQty': parseInt(manholeQtyCtrl, 0),
        'manholeLengthM': parse(manholeLCtrl, .8),
        'manholeWidthM': parse(manholeWCtrl, .8),
        'includeRoof': includeRoof,
        'includeHardcore': includeHardcore,
        'includeBlinding': includeBlinding,
        'includeRebar': includeRebar,
        'reinforcementMode': 'layered',
        'steelWastePercent': parse(steelWasteCtrl, 5),
        'rebarLayers': rebarLayers.map((layer) => {
          'id': layer.id,
          'component': layer.component,
          'face': layer.face,
          'direction': layer.direction,
          'barMark': layer.barMark,
          'diameterMm': layer.diameterMm,
          'spacingMm': layer.spacingMm,
          'countMode': layer.countMode,
          'manualCount': layer.manualCount,
          'lengthMode': layer.lengthMode,
          'manualLengthM': layer.manualLengthM,
          'boq': layer.boq == null ? null : {'id': layer.boq!.id, 'code': layer.boq!.code, 'description': layer.boq!.description},
        }).toList(),
        'includeInternalWaterproofing': includeInternalWp,
        'includeExternalWaterproofing': includeExternalWp,
        'includeWaterstop': includeWaterstop,
        'includeBackfill': includeBackfill,
        'color': currentColor.value,
        'createdAt': now,
        'updatedAt': now,
      };

  final batch = FirebaseFirestore.instance.batch();
  for (final o in outputs.where((o) => o.enabled && o.boq != null)) {
    final value = q[o.key] ?? 0;
    if (value <= 0) continue;
    batch.set(measurementsRef.doc('$assemblyId-${o.key}'), {
      ...common(),
      'type': 'undergroundStructure${o.key[0].toUpperCase()}${o.key.substring(1)}',
      'componentKey': o.key,
      'componentLabel': o.label,
      'unit': o.unit,
      'value': value,
      if (o.key == 'blinding') ...{
        'areaM2': q['blindingAreaM2'] ?? value,
        'thicknessM': q['blindingThicknessM'] ?? 0,
        'volumeM3': q['blindingVolumeM3'] ?? 0,
      },
      if (o.key == 'hardcore') ...{
        'areaM2': q['hardcoreAreaM2'] ?? 0,
        'thicknessM': q['hardcoreThicknessM'] ?? 0,
        'volumeM3': value,
      },
      'boqItemId': o.boq!.id,
      'boqCode': o.boq!.code,
      'boqDescription': o.boq!.description,
    });
  }

  if (includeRebar) {
    final baseL = q['baseLengthM'] ?? 0;
    final baseW = q['baseWidthM'] ?? 0;
    final outerL = q['outerLengthM'] ?? 0;
    final outerW = q['outerWidthM'] ?? 0;
    final wallH = q['wallHeightM'] ?? 0;
    final innerW = q['innerWidthM'] ?? 0;
    final partCount = parseInt(partitionsCtrl, 0);
    final partLength = parse(partitionLengthCtrl, 0) > 0 ? parse(partitionLengthCtrl, 0) : innerW;
    final wasteFactor = 1 + parse(steelWasteCtrl, 5).clamp(0.0, 100.0).toDouble() / 100;
    int across(double dim, double spacing) => spacing <= 0 ? 0 : (dim / (spacing / 1000)).ceil() + 1;
    for (final layer in rebarLayers) {
      if (layer.boq == null) continue;
      if (layer.component == 'roof' && !includeRoof) continue;
      if (layer.component == 'partition' && partCount <= 0) continue;
      int count;
      if (layer.countMode == 'manual') {
        count = layer.manualCount;
      } else {
        switch (layer.component) {
          case 'base': count = layer.direction == 'Y' ? across(baseL, layer.spacingMm) : across(baseW, layer.spacingMm); break;
          case 'roof': count = layer.direction == 'Y' ? across(outerL, layer.spacingMm) : across(outerW, layer.spacingMm); break;
          case 'wall': count = layer.direction == 'Horizontal' ? across(wallH, layer.spacingMm) : across(2 * (outerL + outerW), layer.spacingMm); break;
          case 'partition': count = layer.direction == 'Horizontal' ? across(wallH, layer.spacingMm) * partCount : across(partLength * partCount, layer.spacingMm); break;
          default: count = layer.manualCount;
        }
      }
      double length;
      if (layer.lengthMode == 'auto') {
        switch (layer.component) {
          case 'base': length = layer.direction == 'Y' ? baseW : baseL; break;
          case 'roof': length = layer.direction == 'Y' ? outerW : outerL; break;
          case 'wall': length = layer.direction == 'Horizontal' ? 2 * (outerL + outerW) : wallH; break;
          case 'partition': length = layer.direction == 'Horizontal' ? partLength : wallH; break;
          default: length = layer.manualLengthM;
        }
      } else {
        length = layer.manualLengthM;
      }
      final faceMultiplier = layer.face.startsWith('Both') ? 2.0 : 1.0;
      final totalLength = count * length * faceMultiplier;
      final kgPerM = layer.diameterMm * layer.diameterMm / 162.0;
      final weight = totalLength * kgPerM * wasteFactor;
      if (weight <= 0) continue;
      batch.set(measurementsRef.doc('$assemblyId-rebar-${layer.id}'), {
        ...common(),
        'type': 'undergroundStructureReinforcementLayer',
        'componentKey': 'reinforcementLayer',
        'componentLabel': '${layer.component} • ${layer.face} • ${layer.direction}${layer.barMark.trim().isEmpty ? '' : ' • Mark ${layer.barMark.trim()}'}',
        'rebarLayerId': layer.id,
        'rebarComponent': layer.component,
        'rebarFace': layer.face,
        'rebarDirection': layer.direction,
        'barMark': layer.barMark.trim(),
        'barDiameterMm': layer.diameterMm,
        'barSpacingMm': layer.spacingMm,
        'barCount': count,
        'faceMultiplier': faceMultiplier,
        'barCountMode': layer.countMode,
        'barLengthM': length,
        'barLengthMode': layer.lengthMode,
        'totalBarLengthM': totalLength,
        'kgPerM': kgPerM,
        'wasteFactor': wasteFactor,
        'unit': 'kg',
        'value': weight,
        'boqItemId': layer.boq!.id,
        'boqCode': layer.boq!.code,
        'boqDescription': layer.boq!.description,
      });
    }
  }

  try {
    await batch.commit();
    lastDefaults
      ..['presetId'] = selectedPresetId
      ..['label'] = label
      ..['wallThicknessM'] = parse(wallTCtrl, .2)
      ..['wallHeightM'] = parse(depthCtrl, 2)
      ..['baseThicknessM'] = parse(baseTCtrl, .2)
      ..['roofThicknessM'] = parse(roofTCtrl, .15)
      ..['baseOverhangM'] = parse(overhangCtrl, .15)
      ..['blindingThicknessM'] = parse(blindingTCtrl, .05)
      ..['hardcoreThicknessM'] = parse(hardcoreTCtrl, 0)
      ..['workingSpaceM'] = parse(workingCtrl, .6)
      ..['extraExcavationDepthM'] = parse(extraExcDepthCtrl, 0)
      ..['partitionCount'] = parseInt(partitionsCtrl, 0)
      ..['partitionLengthM'] = parse(partitionLengthCtrl, 0)
      ..['partitionThicknessM'] = parse(partitionTCtrl, .2)
      ..['manholeQty'] = parseInt(manholeQtyCtrl, 0)
      ..['manholeLengthM'] = parse(manholeLCtrl, .8)
      ..['manholeWidthM'] = parse(manholeWCtrl, .8)
      ..['steelWastePercent'] = parse(steelWasteCtrl, 5)
      ..['rebarLayers'] = rebarLayers.map((layer) => {
        'id': layer.id,
        'component': layer.component,
        'face': layer.face,
        'direction': layer.direction,
        'barMark': layer.barMark,
        'diameterMm': layer.diameterMm,
        'spacingMm': layer.spacingMm,
        'countMode': layer.countMode,
        'manualCount': layer.manualCount,
        'lengthMode': layer.lengthMode,
        'manualLengthM': layer.manualLengthM,
        'boq': layer.boq == null ? null : {'id': layer.boq!.id, 'code': layer.boq!.code, 'description': layer.boq!.description},
      }).toList()
      ..['includeRoof'] = includeRoof
      ..['includeHardcore'] = includeHardcore
      ..['includeBlinding'] = includeBlinding
      ..['includeRebar'] = includeRebar
      ..['includeInternalWaterproofing'] = includeInternalWp
      ..['includeExternalWaterproofing'] = includeExternalWp
      ..['includeWaterstop'] = includeWaterstop
      ..['includeBackfill'] = includeBackfill
      ..['boqs'] = {
        for (final o in outputs)
          if (o.boq != null)
            o.key: {
              'id': o.boq!.id,
              'code': o.boq!.code,
              'description': o.boq!.description,
            },
      };

    onUpdateViewer?.call();
    Get.snackbar('Underground structure saved', '${preset.label} take-off saved to measurements.');
  } catch (e) {
    Get.snackbar('Could not save take-off', '$e');
    return UndergroundStructureSaveAction.cancel;
  } finally {
    for (final c in [
      labelCtrl, outerLCtrl, outerWCtrl, wallTCtrl, depthCtrl, baseTCtrl,
      roofTCtrl, overhangCtrl, blindingTCtrl, hardcoreTCtrl, workingCtrl,
      extraExcDepthCtrl, partitionsCtrl, partitionLengthCtrl, partitionTCtrl,
      manholeQtyCtrl, manholeLCtrl, manholeWCtrl,
steelWasteCtrl,
    ]) {
      c.dispose();
    }
  }

  return action;
}
