import 'package:aqs/features/takeoff/dialogs/beam_measured_dialog.dart';
import 'package:aqs/features/takeoff/dialogs/beam_session_dialog.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:aqs/features/utils/helpers/beam_qty_helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/beam_segment.dart';

enum BeamMeasureState { idle, waitingP1, waitingP2 }

class BeamSessionConfig {
  final String beamType;

  final String concreteBoqCode;
  final String sideFormworkBoqCode;
  final String soffitFormworkBoqCode;

  /// Beam size (meters)
  final double bM; // width
  final double hM; // depth

  final bool includeConcrete;
  final bool includeSideFormwork;
  final bool includeSoffitFormwork;
  final bool isGroundBeam;

  const BeamSessionConfig({
    required this.beamType,
    required this.concreteBoqCode,
    required this.sideFormworkBoqCode,
    required this.soffitFormworkBoqCode,
    required this.bM,
    required this.hM,
    required this.includeConcrete,
    required this.includeSideFormwork,
    required this.includeSoffitFormwork,
    required this.isGroundBeam,
  });
}

class CompositeBeamTakeoffController extends GetxController {
  CompositeBeamTakeoffController({
    required this.projectId,
    required this.buildingId,
    required this.drawingId,
  });

  final String projectId;
  final String buildingId;
  final String drawingId;

  late final CollectionReference<Map<String, dynamic>> measurementsRef;
  @override
  void onInit() {
    super.onInit();
    measurementsRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(projectId)
        .collection('buildings')
        .doc(buildingId)
        .collection('measurements');
  }

  /// Provided by your drawing scale calibration
  /// e.g. 1px = 0.002m (depends on your scale tool)
  final RxDouble metersPerPixel = 0.0.obs;

  final Rx<BeamSessionConfig?> activeConfig = Rx<BeamSessionConfig?>(null);

  final Rx<BeamMeasureState> state = BeamMeasureState.idle.obs;

  Offset? _p1;
  Offset? _p2;
  Offset? get tempP1 => _p1;
  Offset? get tempP2 => _p2;

  /// All segments measured (across GB01, GB02, etc.)
  final RxList<BeamSegment> segments = <BeamSegment>[].obs;

  /// Optional: if true, Continue will auto-start next P1 = last P2
  final RxBool chainFromLastP2 = false.obs;

  // late final String projectId;
  // late final String buildingId;
  // late final String drawingId;

  void bind({
    required String projectId,
    required String buildingId,
    required String drawingId,
  }) {
    // this.projectId = projectId;
    // this.buildingId = buildingId;
    // this.drawingId = drawingId;

    measurementsRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(projectId)
        .collection('buildings')
        .doc(buildingId)
        .collection('measurements');
  }

  Future<bool> ensureSessionStarted({String? suggestedBeamType}) async {
    if (activeConfig.value != null) {
      // if session exists but controller is idle, re-arm it
      if (state.value == BeamMeasureState.idle) {
        state.value = BeamMeasureState.waitingP1;
      }
      return true;
    }

    // show session dialog
    final cfg = await Get.dialog<BeamSessionConfig>(
      BeamSessionDialog(
        suggestedBeamType: suggestedBeamType,
        projectId: projectId,
        buildingId: buildingId,
      ),
      barrierDismissible: false,
    );

    if (cfg == null) return false;

    startSession(cfg);
    return true;
  }

  void startSession(BeamSessionConfig config) {
    activeConfig.value = config;
    state.value = BeamMeasureState.waitingP1;
    _p1 = null;
    _p2 = null;
  }

  /// Hook this to your canvas tap
  Future<void> onCanvasTap(
    Offset p, {
    required Map<String, dynamic> drawingData,
    required Color color,
    String? activeLabel,
  }) async {
    final cfg = activeConfig.value;
    if (cfg == null) return;

    if (state.value == BeamMeasureState.waitingP1) {
      _p1 = p;
      state.value = BeamMeasureState.waitingP2;
      return;
    }

    if (state.value == BeamMeasureState.waitingP2) {
      _p2 = p;

      // --- compute length ---
      final px = distPx(_p1!, _p2!);
      final lengthM = pxToMeters(px, metersPerPixel.value);

      if (lengthM <= 0) {
        Get.snackbar('Invalid', 'Beam length is invalid. Calibrate first.');
        _p1 = null;
        _p2 = null;
        state.value = BeamMeasureState.waitingP1;
        return;
      }

      // --- compute quantities for dialog preview ---
      final conc = calcConcreteM3(bM: cfg.bM, hM: cfg.hM, lengthM: lengthM);
      final fw = calcFormworkM2(
        bM: cfg.bM,
        hM: cfg.hM,
        lengthM: lengthM,
        includeSoffit: cfg.includeSoffitFormwork,
      );

      final action = await Get.dialog<BeamAction>(
        BeamMeasureDialog(
          beamName: cfg.beamType,
          lengthM: lengthM,
          concM3: conc,
          fwM2: fw,
          chainFromLastP2: chainFromLastP2,
          currentSummary: summaryFor(
            cfg.beamType,
            cfg.concreteBoqCode,
            cfg.sideFormworkBoqCode,
            cfg.soffitFormworkBoqCode,
          ),
        ),
        barrierDismissible: false,
      );

      if (action == null || action == BeamAction.cancel) {
        _p1 = null;
        _p2 = null;
        state.value = BeamMeasureState.waitingP1;
        return;
      }

      // ✅ Accept action (continue OR save) -> persist this beam immediately
      final beamId = measurementsRef.doc().id;

      // Save to Firestore (3 docs: concrete, side fw, soffit fw)
      await _saveBeamToFirestore(
        cfg: cfg,
        beamId: beamId,
        p1: _p1!,
        p2: _p2!,
        lengthM: lengthM,
        color: color,
        activeLabel: activeLabel,
      );

      // Keep local list too (optional, for instant UI before stream updates)
      segments.add(
        BeamSegment.create(
          beamName: cfg.beamType,
          concreteBoqCode: cfg.concreteBoqCode,
          sideFormworkBoqCode: cfg.sideFormworkBoqCode,
          soffitFormworkBoqCode: cfg.soffitFormworkBoqCode,
          p1: _p1!,
          p2: _p2!,
          lengthM: lengthM,
          concreteVolM3: conc,
          formworkAreaM2: fw,
        ),
      );

      // --- next state ---
      if (action == BeamAction.continue_) {
        if (chainFromLastP2.value) {
          _p1 = _p2; // chain: next starts where last ended
          _p2 = null;
          state.value = BeamMeasureState.waitingP2;
        } else {
          _p1 = null;
          _p2 = null;
          state.value = BeamMeasureState.waitingP1;
        }
        return;
      }
      if (action == BeamAction.save || action == BeamAction.saveStop) {
        final beamId =
            FirebaseFirestore.instance
                .collection('_')
                .doc()
                .id; // or measurementsRef.doc().id
        await _saveBeamToFirestore(
          cfg: cfg,
          beamId: beamId,
          p1: _p1!,
          p2: _p2!,
          lengthM: lengthM,
          color: color, // pass from onCanvasTap args
          activeLabel: activeLabel, // pass from onCanvasTap args
        );

        // reset points for next measure
        _p1 = null;
        _p2 = null;
        state.value = BeamMeasureState.waitingP1;

        if (action == BeamAction.saveStop) {
          stopSession(); // ✅ stop here
        }
        return;
      }

      // BeamAction.save
      _p1 = null;
      _p2 = null;
      state.value = BeamMeasureState.waitingP1;
      return;
    }
  }

  /// Group summary by beamName + codes (in case GB01 can have multiple configs)
  BeamGroupSummary summaryFor(
    String beamName,
    String concCode,
    String SideFwCode,
    String SoffitFwCode,
  ) {
    final list =
        segments
            .where(
              (s) =>
                  s.beamName == beamName &&
                  s.concreteBoqCode == concCode &&
                  s.sideFormworkBoqCode == SideFwCode &&
                  s.soffitFormworkBoqCode == SoffitFwCode,
            )
            .toList();

    final count = list.length;
    final totalL = list.fold<double>(0, (a, b) => a + b.lengthM);
    final totalC = list.fold<double>(0, (a, b) => a + b.concreteVolM3);
    final totalF = list.fold<double>(0, (a, b) => a + b.formworkAreaM2);

    return BeamGroupSummary(
      beamName: beamName,
      concreteBoqCode: concCode,
      sideFormworkBoqCode: SideFwCode,
      soffitFormworkBoqCode: SoffitFwCode,
      count: count,
      totalLengthM: totalL,
      totalConcreteM3: totalC,
      totalFormworkM2: totalF,
    );
  }

  /// When user clicks any segment in canvas, call this:
  void showBeamTotalsForSegment(BeamSegment seg) {
    final sum = summaryFor(
      seg.beamName,
      seg.concreteBoqCode,
      seg.sideFormworkBoqCode,
      seg.soffitFormworkBoqCode,
    );
    Get.dialog(BeamTotalsDialog(sum: sum), barrierDismissible: true);
  }

  Future<void> _saveBeamToFirestore({
    required BeamSessionConfig cfg,
    required String beamId,
    required Offset p1,
    required Offset p2,
    required double lengthM,
    required Color color,
    String? activeLabel,
  }) async {
    final concVolM3 = lengthM * cfg.bM * cfg.hM;
    final sideFwM2 = 2 * cfg.hM * lengthM;
    final soffitFwM2 = cfg.isGroundBeam ? 0.0 : cfg.bM * lengthM;

    final p1Map = {'x': p1.dx, 'y': p1.dy};
    final p2Map = {'x': p2.dx, 'y': p2.dy};

    Map<String, dynamic> common(String labelSuffix) => {
      'projectId': projectId,
      'buildingId': buildingId,
      'drawingId': drawingId,

      'measureType': 'compositeBeam',
      'beamId': beamId,
      'beamType': cfg.beamType,

      'beamLengthM': lengthM,
      'beamWidthM': cfg.bM,
      'beamDepthM': cfg.hM,
      'isGroundBeam': cfg.isGroundBeam,

      'p1': p1Map,
      'p2': p2Map,
      'color': color.value,
      'label': '${(activeLabel ?? 'Beam').trim()} - $labelSuffix',

      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt':
          FieldValue.serverTimestamp(), // ok even if overwritten; or remove if you want
    };

    final batch = FirebaseFirestore.instance.batch();

    final concDoc = measurementsRef.doc('$beamId-beamConcrete');
    final sideDoc = measurementsRef.doc('$beamId-beamFormworkSide');
    final soffitDoc = measurementsRef.doc('$beamId-beamFormworkSoffit');

    if (cfg.includeConcrete &&
        concVolM3 > 0 &&
        cfg.concreteBoqCode.trim().isNotEmpty) {
      batch.set(concDoc, {
        ...common('Concrete'),
        'type': 'beamConcrete',
        'unit': 'm3',
        'value': concVolM3,
        'boqCode': cfg.concreteBoqCode.trim(),
      });
    }

    if (cfg.includeSideFormwork &&
        sideFwM2 > 0 &&
        cfg.sideFormworkBoqCode.trim().isNotEmpty) {
      batch.set(sideDoc, {
        ...common('Side formwork'),
        'type': 'beamFormworkSide',
        'unit': 'm2',
        'value': sideFwM2,
        'boqCode': cfg.sideFormworkBoqCode.trim(),
      });
    }

    if (!cfg.isGroundBeam &&
        cfg.includeSoffitFormwork &&
        soffitFwM2 > 0 &&
        cfg.soffitFormworkBoqCode.trim().isNotEmpty) {
      batch.set(soffitDoc, {
        ...common('Soffit formwork'),
        'type': 'beamFormworkSoffit',
        'unit': 'm2',
        'value': soffitFwM2,
        'boqCode': cfg.soffitFormworkBoqCode.trim(),
      });
    }

    await batch.commit();
  }

  void stopSession() {
    activeConfig.value = null;
    state.value = BeamMeasureState.idle;
    _p1 = null;
    _p2 = null;
  }
}
