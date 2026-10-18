import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/takeoff/models/polyline_draft.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

extension OffsetToMap on Offset {
  Map<String, dynamic> toMap() => {'x': dx, 'y': dy};
}

class PolylineCaptureController extends GetxController {
  // dependencies
  final TransformationController tCtrl;
  final Map<String, dynamic> drawingData;
  final CollectionReference<Map<String, dynamic>> measurementsRef;

  final String projectId;
  final String buildingId;
  final String drawingId;

  // callbacks
  final Future<BoqPick?> Function(BuildContext ctx) showBoqPickerDialog;
  final Map<String, dynamic> lastLineDefaults;

  PolylineCaptureController({
    required this.tCtrl,
    required this.drawingData,
    required this.measurementsRef,
    required this.projectId,
    required this.buildingId,
    required this.drawingId,
    required this.showBoqPickerDialog,
    required this.lastLineDefaults,
  });

  // mode
  final RxBool enabled = true.obs;

  // selection metadata (set from UI)
  final RxString measureType = 'roofSheetingAndTimber'.obs;
  final RxString type = 'roofRidgeCapping'.obs;
  final RxString unit = 'm'.obs;

  PolylineDraft? draft;

  final RxString edgeTag = 'ridge'.obs; // ridge/hip/valley/eave/barge or ''
  final RxString groupId = ''.obs;

  // IMPORTANT: use material.Colors to avoid conflict with vector_math Colors
  final RxInt colorValue = material.Colors.red.value.obs;

  // points in WORLD coords (image/world space)
  final Rxn<Offset> p1World = Rxn<Offset>();
  final Rxn<Offset> hoverWorld = Rxn<Offset>();

  // optional: keep locally saved segments for instant re-paint
  final List<PolylineDraft> _saved = [];
  List<PolylineDraft> get saved => List.unmodifiable(_saved);

  bool get hasStart => p1World.value != null;

  // PolylineDraft? get draft {
  //   final a = p1World.value;
  //   final h = hoverWorld.value;
  //   if (a == null || h == null) return null;
  //   return PolylineDraft(
  //     id: 'draft',
  //     color: material.Color(colorValue.value),
  //     tag: edgeTag.value.trim().isEmpty ? null : edgeTag.value.trim(),
  //     worldPoints: [a, h],
  //   );
  // }

  double _num(dynamic v, double fb) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? fb;
  }

  bool _isCalibrated(Map<String, dynamic> drawingData) {
    final calibrated = drawingData['calibrated'] == true;
    final pxPerM = _num(drawingData['pixelsPerUnit'], 0);
    return calibrated && pxPerM > 0;
  }

  double _pxPerM(Map<String, dynamic> drawingData) =>
      _num(drawingData['pixelsPerUnit'], 0);

  /// Convert local (screen) coordinates into WORLD (drawing) coordinates.
  /// WORLD here is same space as your PDF/image coordinate system.
  Offset toWorld({
    required Offset local,
    required TransformationController tCtrl,
  }) {
    final vm.Matrix4 inv = vm.Matrix4.inverted(tCtrl.value);
    final vm.Vector3 v = inv.transform3(vm.Vector3(local.dx, local.dy, 0));
    return Offset(v.x, v.y);
  }

  double _distM(
    Offset aWorld,
    Offset bWorld,
    Map<String, dynamic> drawingData,
  ) {
    final pxPerM = _pxPerM(drawingData);
    if (pxPerM <= 0) return 0;
    final dx = bWorld.dx - aWorld.dx;
    final dy = bWorld.dy - aWorld.dy;
    final dPx = math.sqrt(dx * dx + dy * dy);
    return dPx / pxPerM;
  }

  /// Key to remember BOQ per item setup
  String _boqKey() {
    final mt = measureType.value.trim();
    final tp = type.value.trim();
    final ut = unit.value.trim();
    final tag = edgeTag.value.trim();
    return '$mt|$tp|$ut|$tag';
  }

  Map<String, dynamic>? _getBoqMapForKey(String key) {
    final all = lastLineDefaults['boqByKey'];
    if (all is Map) {
      final v = all[key];
      if (v is Map) return Map<String, dynamic>.from(v);
    }
    return null;
  }

  void _setBoqMapForKey(String key, Map<String, dynamic> map) {
    final all =
        (lastLineDefaults['boqByKey'] is Map)
            ? Map<String, dynamic>.from(lastLineDefaults['boqByKey'])
            : <String, dynamic>{};

    all[key] = map;
    lastLineDefaults['boqByKey'] = all;
  }

  Map<String, dynamic>? _pickToMap(BoqPick? p) {
    if (p == null) return null;
    return {'id': p.id, 'code': p.code, 'description': p.description};
  }

  BoqPick? _pickFromMap(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final id = (m['id'] ?? '').toString();
    final code = (m['code'] ?? '').toString();
    final desc = (m['description'] ?? '').toString();
    if (id.isEmpty && code.isEmpty && desc.isEmpty) return null;
    return BoqPick(id: id, code: code, description: desc);
  }

  Future<BoqPick?> _ensureBoqPick(BuildContext ctx) async {
    final key = _boqKey();

    // 1) exact remembered per-key
    final cached = _getBoqMapForKey(key);
    final fromKey = _pickFromMap(cached);
    if (fromKey != null) return fromKey;

    // 2) fallback: last used globally
    final lastGlobal = _pickFromMap(lastLineDefaults['lastBoqPick']);
    if (lastGlobal != null) return lastGlobal;

    // 3) ask user once
    final pick = await showBoqPickerDialog(ctx);
    if (pick != null) {
      final map = _pickToMap(pick)!;
      _setBoqMapForKey(key, map);
      lastLineDefaults['lastBoqPick'] = map;

      // remember other defaults
      lastLineDefaults['measureType'] = measureType.value.trim();
      lastLineDefaults['type'] = type.value.trim();
      lastLineDefaults['unit'] = unit.value.trim();
      lastLineDefaults['edgeTag'] = edgeTag.value.trim();
    }
    return pick;
  }

  void updateHover(Offset worldHover) {
    if (draft == null) return;
    if (draft!.worldPoints.isEmpty) return;

    // keep first point, update last
    final pts = List<Offset>.from(draft!.worldPoints);
    if (pts.length == 1) {
      pts.add(worldHover);
    } else {
      pts[pts.length - 1] = worldHover;
    }

    draft = PolylineDraft(
      id: draft!.id,
      color: draft!.color,
      tag: draft!.tag,
      worldPoints: pts,
    );
    update();
  }

  void cancelDraft() {
    draft = null;
    update();
  }

  /// Tap #1
  void setStart({
    required String id,
    required material.Color color,
    required String? tag,
    required Offset worldStart,
  }) {
    draft = PolylineDraft(
      id: id,
      color: color,
      tag: tag,
      worldPoints: [worldStart, worldStart], // start + hover init
    );
    update();
  }

  /// Call this from GestureDetector onTapDown (local position)
  Future<void> onTapLocal(Offset localPos) async {
    if (!enabled.value) return;

    if (!_isCalibrated(drawingData)) {
      Get.snackbar(
        'Not calibrated',
        'Calibrate drawing first (pixelsPerUnit).',
      );
      return;
    }

    final ctx = Get.context;
    if (ctx == null) {
      Get.snackbar('Context missing', 'No UI context available to pick BOQ.');
      return;
    }

    final w = toWorld(local: localPos, tCtrl: tCtrl);

    // first tap sets start
    if (p1World.value == null) {
      p1World.value = w;
      hoverWorld.value = w;
      update();
      return;
    }

    // second tap = end => save
    final a = p1World.value!;
    final b = w;

    await _saveSegment(ctx, a, b);

    // reset for next segment
    p1World.value = null;
    hoverWorld.value = null;
    update();
  }

  /// Call this from onPanUpdate / onHover to update preview line
  void onMoveLocal(Offset localPos) {
    if (!enabled.value) return;
    if (p1World.value == null) return;

    hoverWorld.value = toWorld(local: localPos, tCtrl: tCtrl);
    update();
  }

  void cancelCurrent() {
    p1World.value = null;
    hoverWorld.value = null;
    update();
  }

  Future<void> _saveSegment(
    BuildContext ctx,
    Offset aWorld,
    Offset bWorld,
  ) async {
    final lenM = _distM(aWorld, bWorld, drawingData);
    if (lenM <= 0) {
      Get.snackbar('Invalid', 'Length is zero. Check points/calibration.');
      return;
    }

    // ✅ ensure BOQ is remembered & reused
    final boqPick = await _ensureBoqPick(ctx);
    if (boqPick == null) {
      Get.snackbar('BOQ required', 'Pick BOQ item to save this segment.');
      return;
    }

    final now = FieldValue.serverTimestamp();
    final id = measurementsRef.doc().id;

    final mt = measureType.value.trim();
    final tp = type.value.trim();
    final ut = unit.value.trim();
    final tag = edgeTag.value.trim();
    final gId = groupId.value.trim();

    // (optional) debug
    // debugPrint('saving: mt=$mt type=$tp unit=$ut tag=$tag len=$lenM');

    try {
      final doc = measurementsRef.doc(id);

      await doc.set({
        'projectId': projectId,
        'buildingId': buildingId,
        'drawingId': drawingId,

        'measureType': mt,
        'type': tp,
        'unit': ut,

        'edgeTag': tag.isEmpty ? null : tag,
        'groupId': gId.isEmpty ? null : gId,

        'color': colorValue.value,

        // values
        'value': lenM,
        'lengthM': lenM,

        // geometry (WORLD points)
        'p1': {'x': aWorld.dx, 'y': aWorld.dy},
        'p2': {'x': bWorld.dx, 'y': bWorld.dy},

        // also keep array if you want
        'polyline': [
          {'x': aWorld.dx, 'y': aWorld.dy},
          {'x': bWorld.dx, 'y': bWorld.dy},
        ],

        // BOQ
        'boqItemId': boqPick.id,
        'boqCode': boqPick.code,
        'boqDescription': boqPick.description,

        // labels
        'label': tag.isEmpty ? 'Line' : tag,
        'lineLabel': '$tp • ${lenM.toStringAsFixed(3)} $ut',

        'createdAt': now,
        'updatedAt': now,
      });

      // ✅ remember BOQ per item setup (fast track)
      final key = _boqKey();
      _setBoqMapForKey(key, _pickToMap(boqPick)!);
      lastLineDefaults['lastBoqPick'] = _pickToMap(boqPick);

      // ✅ keep for instant re-paint
      _saved.add(
        PolylineDraft(
          id: id,
          color: material.Color(colorValue.value),
          tag: tag.isEmpty ? null : tag,
          worldPoints: [aWorld, bWorld],
        ),
      );

      update();

      Get.snackbar(
        'Saved',
        '${boqPick.code} • ${lenM.toStringAsFixed(3)} $ut',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar('Save failed', '$e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  // void cancelDraft() {
  //   draft = null;
  //   update();
  // }

  /// Tap #2 (save)
  Future<void> commitEndTap({
    required Offset worldEnd,
    required Map<String, dynamic> drawingData,
  }) async {
    if (draft == null || draft!.worldPoints.isEmpty) {
      Get.snackbar('Line', 'Start point missing');
      return;
    }

    if (!_isCalibrated(drawingData)) {
      Get.snackbar(
        'Not calibrated',
        'Calibrate drawing first (pixelsPerUnit).',
      );
      cancelDraft();
      return;
    }

    final a = draft!.worldPoints.first;
    final b = worldEnd;

    final lenM = _distM(a, b, drawingData);
    if (lenM <= 0) {
      Get.snackbar('Invalid', 'Length is zero. Check points/calibration.');
      cancelDraft();
      return;
    }

    final ctx = Get.context;
    if (ctx == null) {
      Get.snackbar('Context missing', 'No UI context available.');
      cancelDraft();
      return;
    }

    // ✅ BOQ remember (per measureType/type/tag/unit)
    final BoqPick? boqPick = await _ensureBoqPick(ctx);
    if (boqPick == null) {
      Get.snackbar('BOQ required', 'Pick BOQ item to save this line.');
      // keep draft so user can pick and re-tap? up to you.
      // Here we keep draft (do NOT cancel)
      return;
    }

    final now = FieldValue.serverTimestamp();
    final docId = measurementsRef.doc().id;

    try {
      await measurementsRef.doc(docId).set({
        'projectId': projectId,
        'buildingId': buildingId,
        'drawingId': drawingId,

        'measureType': measureType.value.trim(),
        'type': type.value.trim(),
        'unit': unit.value.trim(),

        'edgeTag': (edgeTag.value.trim().isEmpty) ? null : edgeTag.value.trim(),
        'groupId': (groupId.value.trim().isEmpty) ? null : groupId.value.trim(),

        'color': colorValue.value,

        'value': lenM,
        'lengthM': lenM,

        // WORLD coords
        // 'p1': a.toMap(),
        // 'p2': b.toMap(),
        // 'polyline': [a.toMap(), b.toMap()],
        'boqItemId': boqPick.id,
        'boqCode': boqPick.code,
        'boqDescription': boqPick.description,

        'label': (draft!.tag ?? 'Line'),
        'lineLabel':
            '${type.value.trim()} • ${lenM.toStringAsFixed(3)} ${unit.value.trim()}',

        'createdAt': now,
        'updatedAt': now,
      });

      // ✅ instant paint
      saved.add(
        PolylineDraft(
          id: docId,
          color: draft!.color,
          tag: draft!.tag,
          worldPoints: [a, b],
        ),
      );

      // ✅ clear draft (fast track next line)
      draft = null;
      update();

      // ✅ SUCCESS snackbar (as requested)
      Get.snackbar(
        'Saved',
        '${boqPick.code} • ${lenM.toStringAsFixed(3)} ${unit.value.trim()}',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      // ✅ ERROR snackbar (as requested)
      Get.snackbar('Save failed', '$e', snackPosition: SnackPosition.BOTTOM);

      // keep draft so user can retry
      update();
    }
  }
}
