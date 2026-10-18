import 'dart:math' as math;

import 'package:aqs/features/takeoff/controllers/walling_config_controller.dart';
import 'package:aqs/features/takeoff/dialogs/wall_segment_confirm_dialog.dart';
import 'package:aqs/features/takeoff/dialogs/walling_details_dialog.dart';
import 'package:aqs/features/takeoff/models/wall_segment.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

enum WallingState { idle, waitingP1, waitingP2 }

class WallingDraft {
  final Offset p1;
  final Offset p2;
  final double lengthM;
  final String label;

  WallingDraft({
    required this.p1,
    required this.p2,
    required this.lengthM,
    required this.label,
  });
}

class WallingTakeoffController extends GetxController {
  WallingTakeoffController({
    required this.projectId,
    required this.buildingId,
    required this.drawingId,
    required this.measurementsRef,
    required this.configCtrl,
  });

  final String projectId;
  final String buildingId;
  final String drawingId;
  final CollectionReference<Map<String, dynamic>> measurementsRef;
  final WallingConfigController configCtrl;

  final Rx<WallingState> state = WallingState.idle.obs;

  Offset? tempP1;
  Offset? tempP2;

  final RxList<WallSegment> chain = <WallSegment>[].obs;
  final RxBool isSaving = false.obs;
  final RxDouble saveProgress = 0.0.obs; // 0..1
  final RxString saveStatus = ''.obs;
  final RxList<WallGroup> wallGroups = <WallGroup>[].obs;

  double get totalLengthM => chain.fold(0.0, (a, b) => a + b.lengthM);

  void _showSavingDialog() {
    Get.dialog(
      Obx(() {
        final p = saveProgress.value.clamp(0.0, 1.0);
        return AlertDialog(
          title: const Text('Saving walling...'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: p),
              const SizedBox(height: 12),
              Text(
                saveStatus.value.isEmpty ? 'Please wait...' : saveStatus.value,
              ),
              const SizedBox(height: 6),
              Text('${(p * 100).toStringAsFixed(0)}%'),
            ],
          ),
        );
      }),
      barrierDismissible: false,
    );
  }

  void _closeSavingDialogIfOpen() {
    if (Get.isDialogOpen == true) Get.back();
  }

  void start() {
    chain.clear();
    tempP1 = null;
    tempP2 = null;
    state.value = WallingState.waitingP1;
    update(['walling']);
  }

  void stop() {
    chain.clear();
    tempP1 = null;
    tempP2 = null;
    state.value = WallingState.idle;
    update(['walling']);
  }

  double _distancePx(Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _metersPerPixelFromDrawing(Map<String, dynamic> drawingData) {
    final calibrated = drawingData['calibrated'] == true;
    final pxPerM = (drawingData['pixelsPerUnit'] ?? 0);
    final pxPerMDouble = (pxPerM is num) ? pxPerM.toDouble() : 0.0;
    if (!calibrated || pxPerMDouble <= 0) return 0.0;
    return 1.0 / pxPerMDouble;
  }

  Future<void> onTap(
    Offset imagePos, {
    required Map<String, dynamic> drawingData,
    required Color color,
    required String? activeLabel,
  }) async {
    final mpp = _metersPerPixelFromDrawing(drawingData);
    if (mpp <= 0) {
      Get.snackbar('Calibration', 'Calibrate the drawing first.');
      return;
    }

    final okCfg = await configCtrl.ensureConfig();
    if (!okCfg) return;

    if (state.value == WallingState.idle) start();

    if (state.value == WallingState.waitingP1) {
      tempP1 = imagePos;
      tempP2 = null;
      state.value = WallingState.waitingP2;
      update(['walling']);
      return;
    }

    if (state.value == WallingState.waitingP2) {
      tempP2 = imagePos;

      final p1 = tempP1!;
      final p2 = tempP2!;
      final lengthM = _distancePx(p1, p2) * mpp;

      final cfg = configCtrl.activeConfig.value!;
      final decision = await Get.dialog<WallSegmentDecision>(
        WallSegmentConfirmDialog(
          lengthM: lengthM,
          heightM: cfg.wallHeightM,
          totalSoFarM: totalLengthM, // computed from chain
        ),
        barrierDismissible: false,
      );

      if (decision == null || decision.action == WallSegmentAction.cancel) {
        tempP1 = null;
        tempP2 = null;
        state.value = WallingState.waitingP1;
        update(['walling']);
        return;
      }

      final heightM = decision.heightM!;
      // Persist edited height in config so next segments use it
      await configCtrl.updateWallHeight(heightM);

      // add segment to chain
      chain.add(WallSegment(p1: p1, p2: p2, lengthM: lengthM));

      if (decision.action == WallSegmentAction.addContinue) {
        tempP1 = p2; // chain next
        tempP2 = null;
        state.value = WallingState.waitingP2;
        update(['walling']);
        return;
      }

      if (decision.action == WallSegmentAction.finishSave) {
        final cfg = configCtrl.activeConfig.value!;
        await _saveWallGroup(
          cfg: cfg,
          projectId: projectId,
          buildingId: buildingId,
          drawingId: drawingId,
          measurementsRef: measurementsRef,
          chain: chain,
          heightM: heightM,
          color: color,
          label: (activeLabel ?? 'Walling').trim(),
        );

        // reset
        chain.clear();
        tempP1 = null;
        tempP2 = null;
        state.value = WallingState.waitingP1;
        update(['walling', 'view', 'summary']);
        Get.snackbar('Saved', 'Walling group saved.');
        return;
      }
    }
  }

  Future<void> _saveWallGroup({
    required WallingConfig cfg,
    required String projectId,
    required String buildingId,
    required String drawingId,
    required CollectionReference<Map<String, dynamic>> measurementsRef,
    required List<WallSegment> chain,
    required double heightM,
    required Color color,
    required String label,
  }) async {
    if (!measurementsRef.path.endsWith('/measurements')) {
      throw Exception('BUG: saving to wrong ref: ${measurementsRef.path}');
    }
    final boq = cfg.boqCode.trim();
    if (boq.isEmpty || heightM <= 0 || chain.isEmpty) return;

    if (chain.isEmpty) return;

    isSaving.value = true;
    saveProgress.value = 0.0;
    saveStatus.value = 'Preparing...';
    _showSavingDialog();

    try {
      final wallGroupId = measurementsRef.doc().id;

      // Build payloads first
      final payloads = <Map<String, dynamic>>[];
      for (final seg in chain) {
        payloads.add({
          'projectId': projectId,
          'buildingId': buildingId,
          'drawingId': drawingId,

          'type': 'length',
          'measureType': 'walling',
          'wallGroupId': wallGroupId,

          'unit': 'm2',
          'baseLengthM': seg.lengthM,
          'heightM': heightM,
          'value': seg.lengthM * heightM,

          'label': label,
          'boqCode': cfg.boqCode,
          'measureConfigRef': cfg.measureConfigRef,

          'color': color.value,
          'p1': {'x': seg.p1.dx, 'y': seg.p1.dy},
          'p2': {'x': seg.p2.dx, 'y': seg.p2.dy},

          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Firestore batch limit is 500 writes.
      // Use 300-450 to be safe if you later add more docs per segment.
      const chunkSize = 300;

      int saved = 0;
      final total = payloads.length;

      for (int i = 0; i < total; i += chunkSize) {
        final chunk = payloads.sublist(
          i,
          (i + chunkSize > total) ? total : i + chunkSize,
        );

        saveStatus.value =
            'Saving ${saved + chunk.length} / $total segments...';

        final batch = FirebaseFirestore.instance.batch();
        for (final data in chunk) {
          batch.set(measurementsRef.doc(), data);
        }

        await batch.commit();

        saved += chunk.length;
        saveProgress.value = saved / total;
      }

      saveStatus.value = 'Done.';
      saveProgress.value = 1.0;
    } catch (e) {
      Get.snackbar('Save failed', e.toString());
      rethrow;
    } finally {
      isSaving.value = false;
      _closeSavingDialogIfOpen();
    }
  }

  Future<bool> tryOpenDetailsAtTap(
    Offset imagePos, {
    double thresholdPx = 12, // tweak
  }) async {
    WallGroup? bestGroup;
    double bestDist = double.infinity;

    for (final g in wallGroups) {
      for (final seg in g.segments) {
        final d = _distancePointToSegment(imagePos, seg.p1, seg.p2);
        if (d < bestDist) {
          bestDist = d;
          bestGroup = g;
        }
      }
    }

    if (bestGroup != null && bestDist <= thresholdPx) {
      await Get.dialog(
        WallingDetailsDialog(group: bestGroup),
        barrierDismissible: true,
      );
      return true;
    }
    return false;
  }

  /// Distance (in pixels) from point P to line segment AB
  double _distancePointToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final ab2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (ab2 == 0) return (p - a).distance;

    var t = (ap.dx * ab.dx + ap.dy * ab.dy) / ab2;
    t = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distance;
  }
}
