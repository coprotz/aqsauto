import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aqs/features/boq/dialogs/boq_picker_dialog.dart';
import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/dashboards/controllers/project_buildings_controller.dart';
import 'package:aqs/features/takeoff/controllers/composite_beam_takeoff_controller.dart';
import 'package:aqs/features/takeoff/controllers/image_takeoff_controller.dart';
import 'package:aqs/features/takeoff/controllers/poly_draw_controller.dart';
import 'package:aqs/features/takeoff/controllers/walling_taleofff_controller.dart';
import 'package:aqs/features/takeoff/dialogs/column_composite_details_dialog.dart';
import 'package:aqs/features/takeoff/dialogs/concrete_bench_worktop_dialog.dart';
import 'package:aqs/features/takeoff/dialogs/ground_preparation_measurement_dialog.dart';
import 'package:aqs/features/takeoff/dialogs/lift_shaft_takeoff.dart';
import 'package:aqs/features/takeoff/dialogs/underground_structure_takeoff.dart';
import 'package:aqs/features/takeoff/dialogs/plinth_measurement_dialog.dart';
import 'package:aqs/features/takeoff/dialogs/pavement_measurement_dialog.dart';
import 'package:aqs/features/takeoff/dialogs/roof_member_measurement_dialog.dart';
import 'package:aqs/features/takeoff/dialogs/show_boq_multi_picker_dialog.dart';
import 'package:aqs/features/takeoff/dialogs/timber_roof_member_measurement_dialog.dart';
import 'package:aqs/features/takeoff/models/door_input.dart';
import 'package:aqs/features/takeoff/models/measured_segment.dart';
import 'package:aqs/features/takeoff/models/saved_area.dart';
import 'package:aqs/features/takeoff/models/walling_finishes_input.dart';
import 'package:aqs/features/takeoff/models/window_input.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:aqs/features/utils/helpers/boq_helpers.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

mixin DrawingImageSizeEnsurer on GetxController {
  final _ensured = <String>{};
  bool _ensuring = false;

  bool get ensuringImageSize => _ensuring;

  Offset toWorld({
    required Offset local,
    required TransformationController tCtrl,
  }) {
    final Matrix4 m = tCtrl.value;
    final Matrix4 inv = Matrix4.inverted(m);
    final vm.Vector3 v = inv.transform3(vm.Vector3(local.dx, local.dy, 0));
    return Offset(v.x, v.y);
  }

  Offset toScreen({
    required Offset world,
    required TransformationController tCtrl,
  }) {
    final Matrix4 m = tCtrl.value;
    final vm.Vector3 v = m.transform3(vm.Vector3(world.dx, world.dy, 0));
    return Offset(v.x, v.y);
  }

  /// Ensures drawing doc has imageW/imageH (png pixel size) and also fills drawingData map.
  Future<void> ensureImageSizeOnDrawingDoc({
    required DocumentReference<Map<String, dynamic>> drawingRef,
    required Map<String, dynamic> drawingData,
    String? fallbackImageUrl,
  }) async {
    final drawingId = (drawingRef.id).toString();
    if (_ensured.contains(drawingId)) return;

    final w = (drawingData['imageW'] as num?)?.toDouble() ?? 0.0;
    final h = (drawingData['imageH'] as num?)?.toDouble() ?? 0.0;
    if (w > 0 && h > 0) {
      _ensured.add(drawingId);
      return;
    }

    if (_ensuring) return;
    _ensuring = true;
    update(['viewer']);

    try {
      // 1) Resolve imageUrl (prefer stored URL, else storage path, else fallback)
      String url = (drawingData['imageUrl'] ?? '').toString().trim();

      if (url.isEmpty) {
        final imagePath = (drawingData['imagePath'] ?? '').toString().trim();
        if (imagePath.isNotEmpty) {
          url = await FirebaseStorage.instance.ref(imagePath).getDownloadURL();
        }
      }

      if (url.isEmpty && (fallbackImageUrl ?? '').trim().isNotEmpty) {
        url = fallbackImageUrl!.trim();
      }

      if (url.isEmpty) {
        // Can't fix without an URL/path
        return;
      }

      // 2) Fetch image pixel size from NetworkImage
      final info = await getNetworkImageInfo(url);
      final width = info.image.width.toDouble();
      final height = info.image.height.toDouble();

      if (width <= 0 || height <= 0) return;

      // 3) Update Firestore drawing doc
      await drawingRef.update({
        'imageW': width,
        'imageH': height,
        'imageUrl': url, // helpful to cache
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 4) Update local map so UI can proceed immediately
      drawingData['imageW'] = width;
      drawingData['imageH'] = height;
      drawingData['imageUrl'] = url;

      _ensured.add(drawingId);
    } catch (_) {
      // swallow — UI will show retry
    } finally {
      _ensuring = false;
      update(['viewer']);
    }
  }

  Future<ImageInfo> getNetworkImageInfo(String url) {
    final completer = Completer<ImageInfo>();
    final stream = NetworkImage(url).resolve(const ImageConfiguration());
    late final ImageStreamListener listener;

    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        completer.complete(info);
      },
      onError: (e, st) {
        stream.removeListener(listener);
        completer.completeError(e, st);
      },
    );

    stream.addListener(listener);
    return completer.future;
  }
}

class _AreaConfirmChip extends StatelessWidget {
  const _AreaConfirmChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF4FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF155EEF), size: 17),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF101828),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AreaBoqRow {
  final TextEditingController labelCtrl;
  final TextEditingController boqCodeCtrl;
  final TextEditingController boqDescCtrl;

  _AreaBoqRow({
    required String label,
    required String boqCode,
    required String boqDesc,
  }) : labelCtrl = TextEditingController(text: label),
       boqCodeCtrl = TextEditingController(text: boqCode),
       boqDescCtrl = TextEditingController(text: boqDesc);

  void dispose() {
    labelCtrl.dispose();
    boqCodeCtrl.dispose();
    boqDescCtrl.dispose();
  }
}

class _LengthBoqRow {
  final TextEditingController labelCtrl;
  final TextEditingController boqCodeCtrl;
  final TextEditingController boqDescCtrl;

  _LengthBoqRow({
    required String label,
    required String boqCode,
    required String boqDesc,
  }) : labelCtrl = TextEditingController(text: label),
       boqCodeCtrl = TextEditingController(text: boqCode),
       boqDescCtrl = TextEditingController(text: boqDesc);

  void dispose() {
    labelCtrl.dispose();
    boqCodeCtrl.dispose();
    boqDescCtrl.dispose();
  }
}

class _DoorScheduleItem {
  _DoorScheduleItem({
    required this.key,
    required this.label,
    required this.unit,
    required this.formula,
    required this.factor,
    this.enabled = false,
  });

  final String key;
  final String label;
  final String unit;
  final String formula;
  double factor;
  bool enabled;
  BoqPick? boq;
}

class LengthDraftSegment {
  const LengthDraftSegment({
    required this.p1,
    required this.p2,
    required this.lengthM,
    required this.lengthPx,
  });

  final Offset p1;
  final Offset p2;
  final double lengthM;
  final double lengthPx;
}

class _PendingKerbChain {
  const _PendingKerbChain({required this.id, required this.segments});

  final String id;
  final List<LengthDraftSegment> segments;

  double get lengthM =>
      segments.fold<double>(0.0, (sum, segment) => sum + segment.lengthM);
}

enum _KerbSessionAction { cancel, addAnother, commit }

enum _DrainSessionAction { cancel, addAnother, commit }

class _PendingDrainChain {
  const _PendingDrainChain({
    required this.id,
    required this.segments,
    required this.startDepthM,
    required this.endDepthM,
  });

  final String id;
  final List<LengthDraftSegment> segments;
  final double startDepthM;
  final double endDepthM;

  double get lengthM => segments.fold<double>(0.0, (sum, e) => sum + e.lengthM);
}

enum WallLengthCaptureStyle { continuous, segments }

class _LengthMetricPill extends StatelessWidget {
  const _LengthMetricPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 170),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MeasuringItemController extends GetxController
    with DrawingImageSizeEnsurer {
  static const double viewerMinScale = 0.05;
  static const double viewerMaxScale = 8.0;
  static const double viewerInitialScale = 0.64;

  MeasuringItemController({
    required this.projectId,
    required this.buildingId,
    required this.drawingId,
    required this.drawingTitle,
    required this.imageUrl,
    this.imageBytes,
    this.imageWidth,
    this.imageHeight,
    required this.it,
    required this.pctr,
    TransformationController? transformController,
  }) : transformController = transformController ?? TransformationController();

  final String projectId;
  final String buildingId;
  final String drawingId;
  final String drawingTitle;
  final String imageUrl;
  final Uint8List? imageBytes;
  final double? imageWidth;
  final double? imageHeight;
  final ImageTakeoffController it;
  bool get usesInlineImage => imageBytes != null && imageBytes!.isNotEmpty;

  String? activeLabel;
  String? activeBoqCode;
  String? activeUnit;
  double? activeHeightM;
  String? activePresetKey;
  String? activeMeasureType;

  Color currentColor = Colors.blue;
  final mode = TakeoffMode.view.obs;
  bool previewVisible = false;

  final Rxn<Offset> stairP1World = Rxn<Offset>();
  final Rxn<Offset> stairHoverWorld = Rxn<Offset>();

  final Map<String, dynamic> lastLiftShaftDefaults = <String, dynamic>{};
  final Map<String, dynamic> lastUndergroundStructureDefaults = <String, dynamic>{};

  final Set<String> hiddenMeasurementOverlayGroups = <String>{};

  bool isMeasurementOverlayHidden(String groupId) =>
      groupId.isNotEmpty && hiddenMeasurementOverlayGroups.contains(groupId);

  void setMeasurementOverlayVisible(String groupId, bool visible) {
    if (groupId.isEmpty) return;
    if (visible) {
      hiddenMeasurementOverlayGroups.remove(groupId);
    } else {
      hiddenMeasurementOverlayGroups.add(groupId);
    }
    update(['overlayVisibility', 'viewer', 'topbar']);
  }

  void setAllMeasurementOverlaysVisible(
    Iterable<String> groupIds,
    bool visible,
  ) {
    final ids = groupIds.where((id) => id.isNotEmpty);
    if (visible) {
      hiddenMeasurementOverlayGroups.removeAll(ids);
    } else {
      hiddenMeasurementOverlayGroups.addAll(ids);
    }
    update(['overlayVisibility', 'viewer', 'topbar']);
  }

  // beam mark memory
  String? activeBeamName;

  // busy overlays
  bool isCompositeBusy = false;
  bool isBusy = false;
  double getCurrentScale(TransformationController tc) {
    final m = tc.value;
    // uniform scale on x usually equals y
    return m.storage[0]; // scaleX
  }

  late final DocumentReference<Map<String, dynamic>> drawingRef;
  late final CollectionReference<Map<String, dynamic>> measurementsRef;

  final TransformationController transformController;

  Size? _lastViewportSize;

  final PolylineDrawController pctr;

  bool didInitialFit = false;
  double? baseW;
  double? baseH;

  ui.Image? uiImg;
  Object? imageLoadError;
  // double? baseW, baseH;
  // bool didInitialFit = false;

  Future<ui.Image> _resolveUiImage(ImageProvider provider) {
    final c = Completer<ui.Image>();
    final stream = provider.resolve(const ImageConfiguration());

    late final ImageStreamListener l;
    l = ImageStreamListener(
      (info, _) {
        c.complete(info.image);
        stream.removeListener(l);
      },
      onError: (e, st) {
        c.completeError(e, st);
        stream.removeListener(l);
      },
    );

    stream.addListener(l);
    return c.future;
  }

  Future<void> initImage(String url) async {
    try {
      imageLoadError = null;
      final bytes = imageBytes;
      if (usesInlineImage && (imageWidth ?? 0) > 0 && (imageHeight ?? 0) > 0) {
        baseW = imageWidth;
        baseH = imageHeight;
        didInitialFit = false;
        update(['viewer']);
      }
      final ImageProvider provider =
          bytes != null && bytes.isNotEmpty
              ? MemoryImage(bytes)
              : NetworkImage(url);
      uiImg = await _resolveUiImage(provider);

      baseW = uiImg!.width.toDouble();
      baseH = uiImg!.height.toDouble();

      didInitialFit = false; // important when size changes
    } catch (e) {
      imageLoadError = e;
      uiImg = null;
      baseW = null;
      baseH = null;
    } finally {
      update(['viewer']);
    }
  }

  Future<void> loadImageSize(String url) async {
    final completer = Completer<ui.Image>();
    final stream = NetworkImage(url).resolve(const ImageConfiguration());

    late final ImageStreamListener l;
    l = ImageStreamListener(
      (info, _) {
        completer.complete(info.image);
        stream.removeListener(l);
      },
      onError: (e, st) {
        completer.completeError(e, st);
        stream.removeListener(l);
      },
    );

    stream.addListener(l);
    final img = await completer.future;

    baseW = img.width.toDouble();
    baseH = img.height.toDouble();
    update(['viewer']);
  }

  void fitToView(BoxConstraints cts) {
    if (didInitialFit || baseW == null || baseH == null) return;

    final viewW = cts.maxWidth;
    final viewH = cts.maxHeight;

    final scale = math.min(viewW / baseW!, viewH / baseH!);
    final tx = (viewW - baseW! * scale) / 2;
    final ty = (viewH - baseH! * scale) / 2;

    transformController.value =
        Matrix4.identity()
          ..translate(tx, ty)
          ..scale(scale);

    didInitialFit = true;
  }

  String? selectedSegmentId;
  String? selectedAreaId;

  Offset? calibP1;
  Offset? calibP2;

  Offset? lengthP1;
  Offset? lengthP2;

  // area polygon being drawn
  List<Offset> areaPoints = [];
  final List<List<Offset>> _pendingAreaPolygons = [];
  final List<List<Offset>> _pendingAreaDeductionPolygons = [];
  bool _nextAreaPolygonIsDeduction = false;
  final List<List<Offset>> _pendingGroundPreparationPolygons = [];
  final List<List<Offset>> _pendingPavementPolygons = [];
  final List<List<Offset>> _pendingPavementDeductionPolygons = [];
  final List<String> _pendingPavementDeductionLabels = [];
  bool _nextPavementPolygonIsDeduction = false;

  /// Completed pavement polygons that belong to the current unsaved session.
  /// The viewer uses snapshots so a previously captured zone remains painted
  /// while the QS traces the next disconnected zone.
  List<List<Offset>> get pendingPavementPolygons => _pendingPavementPolygons
      .map((points) => List<Offset>.unmodifiable(points))
      .toList(growable: false);

  List<List<Offset>> get pendingPavementDeductionPolygons =>
      _pendingPavementDeductionPolygons
          .map((points) => List<Offset>.unmodifiable(points))
          .toList(growable: false);

  Offset previewOffset = const Offset(40, 80);

  double? previewLengthMeters;
  double? previewPixelDistanceBase;
  bool previewCalibrated = false;

  Offset? previewP1;
  Offset? previewP2;

  double? previewHeightM;
  double? previewQuantity;

  bool _wallEditorOpen = false;

  /// store initial transform per drawing so it doesn't reset on rebuild
  final Map<String, Matrix4> _initTransformByDrawing = {};

  String? _lastResetDrawingId;

  @override
  void onInit() {
    super.onInit();
    initImage(imageUrl);

    final p = projectId.trim();
    final b = buildingId.trim();
    final d = drawingId.trim();
    if (p.isEmpty || b.isEmpty || d.isEmpty) {
      throw ArgumentError(
        'MeasuringItemController: projectId/buildingId/drawingId must not be empty '
        '(projectId="$projectId", buildingId="$buildingId", drawingId="$drawingId")',
      );
    }

    drawingRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(p)
        .collection('buildings')
        .doc(b)
        .collection('drawings')
        .doc(d);

    measurementsRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(p)
        .collection('buildings')
        .doc(b)
        .collection('measurements');

    measureConfigsRef = drawingRef.collection('measureConfigs');
    forceResetZoomNextBuild();
  }

  @override
  void onClose() {
    transformController.dispose();
    previewHeightController.dispose();
    super.onClose();
  }

  final ValueNotifier<int> areaDraftTick = ValueNotifier<int>(0);
  void _tickDraft() => areaDraftTick.value++;

  void resetArea() {
    areaPoints = <Offset>[]; // ✅ replace list, don’t clear
    _tickDraft(); // ✅ force repaint
    update(['viewer']);
  }

  void applyInitialFit(BoxConstraints constraints, double baseW, double baseH) {
    final viewW = constraints.maxWidth;
    final viewH = constraints.maxHeight;

    // "zoom out to fit whole page" scale
    final fitScale = math.min(viewW / baseW, viewH / baseH);

    // If your PDFs are huge and fitScale becomes extremely tiny,
    // clamp to something reasonable (optional)
    final s = fitScale.clamp(0.15, 10.0);

    // ✅ Center-based matrix (most robust)
    transformController.value =
        Matrix4.identity()
          ..translate(viewW / 2, viewH / 2) // go to viewport center
          ..scale(s) // scale around center
          ..translate(-baseW / 2, -baseH / 2); // move image center to origin
  }

  /// Call this when you intentionally want to re-fit the same drawing again.
  void forceResetZoomNextBuild() {
    _lastResetDrawingId = null;
  }

  bool hasInitTransformForDrawing(String drawingId) =>
      _initTransformByDrawing.containsKey(drawingId);

  Matrix4? getInitTransformForDrawing(String drawingId) =>
      _initTransformByDrawing[drawingId];

  void setInitTransformForDrawing(String drawingId, Matrix4 m) {
    _initTransformByDrawing[drawingId] = m;
  }

  /// IMPORTANT: call this when you change drawings
  void clearInitTransformForDrawing(String drawingId) {
    _initTransformByDrawing.remove(drawingId);
  }

  void resetZoomForDrawing({
    required String drawingId,
    required double baseW,
    required double baseH,
    required Size viewport,
    EdgeInsets viewportPadding = EdgeInsets.zero,
    bool centerInViewport = false,
  }) {
    if (drawingId.isEmpty) return;

    final viewW = viewport.width;
    final viewH = viewport.height;
    final availableW = viewW - viewportPadding.left - viewportPadding.right;
    final availableH = viewH - viewportPadding.top - viewportPadding.bottom;
    if (baseW <= 0 ||
        baseH <= 0 ||
        viewW <= 0 ||
        viewH <= 0 ||
        availableW <= 0 ||
        availableH <= 0 ||
        !baseW.isFinite ||
        !baseH.isFinite ||
        !viewW.isFinite ||
        !viewH.isFinite ||
        !availableW.isFinite ||
        !availableH.isFinite) {
      transformController.value = Matrix4.identity();
      return;
    }

    final resetSignature =
        '$drawingId|${baseW.round()}|${baseH.round()}|${viewW.round()}|${viewH.round()}|'
        '${viewportPadding.left.round()}|${viewportPadding.top.round()}|'
        '${viewportPadding.right.round()}|${viewportPadding.bottom.round()}|'
        '${centerInViewport ? 'centered' : 'topLeft'}FitV3';
    if (_lastResetDrawingId == resetSignature) return;

    final fitScale = math.min(availableW / baseW, availableH / baseH);
    if (!fitScale.isFinite || fitScale <= 0) {
      transformController.value = Matrix4.identity();
      return;
    }

    final s = fitScale.clamp(viewerMinScale, viewerMaxScale).toDouble();
    final tx =
        viewportPadding.left +
        (centerInViewport ? (availableW - baseW * s) / 2 : 0);
    final ty =
        viewportPadding.top +
        (centerInViewport ? (availableH - baseH * s) / 2 : 0);

    transformController.value =
        Matrix4.identity()
          ..translate(tx, ty)
          ..scale(s);
    _lastResetDrawingId = resetSignature;
  }

  void setViewportSize(Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    _lastViewportSize = size;
  }

  Offset get _viewportCenter {
    final size = _lastViewportSize;
    if (size != null && size.width > 0 && size.height > 0) {
      return Offset(size.width / 2, size.height / 2);
    }
    if ((baseW ?? 0) > 0 && (baseH ?? 0) > 0) {
      return toScreen(
        world: Offset(baseW! / 2, baseH! / 2),
        tCtrl: transformController,
      );
    }
    return Offset.zero;
  }

  void zoomBy(double factor, {Offset? focalPoint}) {
    if (factor <= 0) return;

    final currentScale = transformController.value.getMaxScaleOnAxis();
    if (currentScale <= 0) return;

    final nextScale =
        (currentScale * factor)
            .clamp(viewerMinScale, viewerMaxScale)
            .toDouble();
    final focal = focalPoint ?? _viewportCenter;
    final sceneAtFocal = transformController.toScene(focal);

    transformController.value =
        Matrix4.identity()
          ..translate(focal.dx, focal.dy)
          ..scale(nextScale)
          ..translate(-sceneAtFocal.dx, -sceneAtFocal.dy);

    update(['viewer']);
  }

  bool isAreaDialogOpen = false;

  final TextEditingController previewHeightController = TextEditingController();

  final Map<String, MeasurementItemSelection> _configByType = {};

  String get _typeKey => (activeMeasureType ?? '').trim().toLowerCase();
  late final CollectionReference<Map<String, dynamic>> measureConfigsRef;

  SegHandle _activeHandle = SegHandle.none;
  MeasuredSegment? _dragSeg;
  Offset? _lastPan;
  double strokeWidth = 0.0;

  final editTool = SegmentEditTool.move.obs;

  // for toolbar drag position
  Offset editToolbarPos = const Offset(20, 80);

  // expose sizes if you want
  double handleRadius = 7.0;
  double rotateHandleRadius = 7.0;

  bool _near(Offset a, Offset b, double r) => (a - b).distance <= r;

  SegHandle _hitHandle(Offset pos, MeasuredSegment seg, double r) {
    if (_near(pos, seg.p1, r)) return SegHandle.p1;
    if (_near(pos, seg.p2, r)) return SegHandle.p2;

    final mid = Offset(
      (seg.p1.dx + seg.p2.dx) / 2,
      (seg.p1.dy + seg.p2.dy) / 2,
    );
    if (_near(pos, mid, r)) return SegHandle.move;

    final d = distancePointToSegment(pos, seg.p1, seg.p2);
    if (d <= r) return SegHandle.move;

    return SegHandle.none;
  }

  void onSegmentPanStart(Offset pos, List<MeasuredSegment> segments) {
    const maxDist = 12.0;

    MeasuredSegment? closest;
    double best = double.infinity;

    for (final s in segments) {
      final d = distancePointToSegment(pos, s.p1, s.p2);
      if (d < best) {
        best = d;
        closest = s;
      }
    }

    if (closest == null || best > maxDist) {
      selectedSegmentId = null;
      _dragSeg = null;
      _activeHandle = SegHandle.none;
      update(['viewer']);
      return;
    }

    selectedSegmentId = closest.id; // highlight
    _dragSeg = closest;
    _activeHandle = _hitHandle(pos, closest, 16.0);
    _lastPan = pos;

    update(['viewer']);
  }

  bool selectSegmentAt(Offset pos, List<MeasuredSegment> segments) {
    final zoom = transformController.value.getMaxScaleOnAxis();
    final maxDist = (zoom <= 0 ? 12.0 : 12.0 / zoom).clamp(10.0, 80.0);

    MeasuredSegment? closest;
    double best = double.infinity;

    for (final s in segments) {
      final d = distancePointToSegment(pos, s.p1, s.p2);
      if (d < best) {
        best = d;
        closest = s;
      }
    }

    if (closest == null || best > maxDist) {
      selectedSegmentId = null;
      update(['viewer']);
      return false;
    }

    selectedSegmentId = closest.id;
    selectedAreaId = null;
    update(['viewer']);
    return true;
  }

  bool _pointInsidePolygon(Offset point, List<Offset> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final crosses =
          ((a.dy > point.dy) != (b.dy > point.dy)) &&
          point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx;
      if (crosses) inside = !inside;
    }
    return inside;
  }

  SavedArea? selectAreaAt(Offset pos, List<SavedArea> areas) {
    final zoom = transformController.value.getMaxScaleOnAxis();
    final edgeTolerance = (zoom <= 0 ? 12.0 : 12.0 / zoom).clamp(8.0, 40.0);
    for (final area in areas.reversed) {
      if (area.points.length < 3 || area.isHidden) continue;
      if (_pointInsidePolygon(pos, area.points)) {
        selectedAreaId = area.id;
        selectedSegmentId = null;
        update(['viewer']);
        return area;
      }
      for (var index = 0; index < area.points.length; index++) {
        final next = area.points[(index + 1) % area.points.length];
        if (distancePointToSegment(pos, area.points[index], next) <=
            edgeTolerance) {
          selectedAreaId = area.id;
          selectedSegmentId = null;
          update(['viewer']);
          return area;
        }
      }
    }
    selectedAreaId = null;
    update(['viewer']);
    return null;
  }

  Future<void> showSavedAreaDialog(SavedArea area) async {
    final docId = area.docId;
    if (docId == null || docId.isEmpty) return;
    await _openSavedMeasurementInspector(docId);
  }

  Future<void> showSelectedLineMeasurementDialog() async {
    final selectedId = selectedSegmentId;
    if (selectedId == null || selectedId.isEmpty) return;
    final segment = lastSegments.firstWhereOrNull(
      (item) => item.id == selectedId,
    );
    if (segment == null) return;
    final segmentPrefix = '${segment.docId}-';
    final polylineIndex =
        selectedId.startsWith(segmentPrefix)
            ? int.tryParse(selectedId.substring(segmentPrefix.length))
            : null;
    await _openSavedMeasurementInspector(
      segment.docId,
      selectedPolylineIndex: polylineIndex,
    );
  }

  void onSegmentPanUpdate(Offset pos) {
    if (_dragSeg == null || _activeHandle == SegHandle.none) return;

    final delta = (_lastPan == null) ? Offset.zero : (pos - _lastPan!);
    _lastPan = pos;

    final seg = _dragSeg!;
    if (_activeHandle == SegHandle.p1) {
      seg.p1 = seg.p1 + delta;
    } else if (_activeHandle == SegHandle.p2) {
      seg.p2 = seg.p2 + delta;
    } else if (_activeHandle == SegHandle.move) {
      seg.p1 = seg.p1 + delta;
      seg.p2 = seg.p2 + delta;
    }

    update(['viewer']);
  }

  Future<void> onSegmentPanEnd({bool cancelled = false}) async {
    if (cancelled) {
      _dragSeg = null;
      _activeHandle = SegHandle.none;
      _lastPan = null;
      return;
    }

    final seg = _dragSeg;
    if (seg == null) return;

    // ✅ Persist only this doc (docId)
    await measurementsRef.doc(seg.docId).update({
      'p1': {'x': seg.p1.dx, 'y': seg.p1.dy},
      'p2': {'x': seg.p2.dx, 'y': seg.p2.dy},
      'updatedAt': FieldValue.serverTimestamp(),
    });

    _dragSeg = null;
    _activeHandle = SegHandle.none;
    _lastPan = null;

    update(['viewer', 'summary']);
  }

  bool get isActiveConfigured {
    final t = _typeKey;
    if (t.isEmpty) return false;

    // composites don't require label/unit/boq here
    final isComposite =
        t == 'compositefooting' ||
        t == 'compositeslab' ||
        t == 'slabrebarai' ||
        t == 'compositebeam' ||
        t == 'plinth' ||
        t == 'groundpreparation' ||
        t == 'civilwork' ||
        t == 'drainage' ||
        t == 'compositestair' ||
        t == 'compositeramp' ||
        t == 'concretebenchworktop';
    if (isComposite) return true;

    final hasLabel = (activeLabel ?? '').trim().isNotEmpty;
    final hasUnit = (activeUnit ?? '').trim().isNotEmpty;
    final hasBoq = (activeBoqCode ?? '').trim().isNotEmpty;

    final needsH = t == 'walling' && (activeUnit == 'm2');
    final hasH = (activeHeightM ?? 0) > 0;

    return hasLabel && hasUnit && hasBoq && (!needsH || hasH);
  }

  // ---- Walling chain measurement ----
  ChainState chainState = ChainState.idle;
  String? chainId;
  Offset? chainP1;
  final List<Offset> chainPoints = [];
  double chainTotalMeters = 0.0;
  int chainSegmentIndex = 0;

  bool get isWallingChainMode =>
      (activeMeasureType ?? '').toLowerCase() == 'walling' &&
      (activeUnit ?? '') == 'm2'; // walling needs height -> m2

  void resetChain() {
    chainState = ChainState.idle;
    chainId = null;
    chainP1 = null;
    chainPoints.clear();
    chainTotalMeters = 0.0;
    chainSegmentIndex = 0;

    // clear temp line painter if you use lengthP1/lengthP2
    lengthP1 = null;
    lengthP2 = null;

    update(['viewer', 'preview', 'topbar']);
  }

  /// Call this when dropdown changes measuring type
  void setActiveMeasureType(String type) {
    it.keepPendingFinishSessionForTool(drawingId: drawingId, measureType: type);
    final key = type.trim().toLowerCase();
    final previousKey = (activeMeasureType ?? '').trim().toLowerCase();
    if (previousKey.isNotEmpty && previousKey != key) {
      if (it.isCountingFastSlabRebarBundles) {
        it.cancelFastSlabRebarBundleCount();
      }
      _pendingAreaPolygons.clear();
      _pendingAreaDeductionPolygons.clear();
      _nextAreaPolygonIsDeduction = false;
    }
    activeMeasureType = type;

    if (key != 'groundpreparation') {
      _pendingGroundPreparationPolygons.clear();
    }
    if (key != 'pavement') {
      _pendingPavementPolygons.clear();
      _pendingPavementDeductionPolygons.clear();
      _pendingPavementDeductionLabels.clear();
      _nextPavementPolygonIsDeduction = false;
    }
    if (key != 'civilwork') {
      _pendingKerbChains.clear();
      _kerbSessionId = null;
    }
    if (key != 'drainage') {
      _pendingDrainChains.clear();
      _drainSessionId = null;
    }
    final cached = _configByType[key];

    if (cached != null) {
      activeLabel = cached.label;
      activeUnit = cached.unit;
      activeBoqCode = cached.boqCode;
      activeHeightM = cached.wallHeightM;
      activePresetKey = null;
    } else {
      // no config yet for this type -> require configure once
      activeLabel = null;
      activeUnit = defaultUnitForMeasureType(type); // optional
      activeBoqCode = null;
      activeHeightM = null;
      activePresetKey = null;
    }

    update(['topbar', 'summary', 'preview']);
  }

  Future<void> selectMeasurementTool({
    required String measureType,
    required String label,
    String? unit,
  }) async {
    setActiveMeasureType(measureType);
    activeLabel = label;
    activeUnit = unit ?? activeUnit ?? defaultUnitForMeasureType(measureType);

    final lower = measureType.trim().toLowerCase();
    isBeamCompositeActive =
        lower == 'compositebeam' || lower == 'beamcomposite';
    isSlabCompositeActive =
        lower == 'compositeslab' || lower == 'slabcomposite';
    isCeilingActive = lower == 'ceilingfinish' || lower == 'ceiling';
    isColumnCompositeActive =
        lower == 'compositecolumn' || lower == 'columncomposite';
    isRetainingWallActive.value =
        lower == 'retainingwall' || lower == 'compositeretainingwall';

    setMode(defaultModeForMeasureType(measureType));

    if (isRetainingWallActive.value) {
      await startNewRetainingWallGroupIfNeeded();
    }

    if (lower == 'trusstemplate') {
      Get.snackbar(
        'Steel roof structure',
        'Tap connected points continuously. Right-click or long-press to add '
            'another segment or continue to steel member details.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    if (lower == 'liftshaft') {
      Get.snackbar(
        'Lift shaft',
        'Tap two opposite corners of the lift shaft outer rectangle.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    if (lower == 'compositeroofing') {
      Get.snackbar(
        'Timber roof structure',
        'Tap connected points continuously. Right-click or long-press to add '
            'another segment or continue to timber member details.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    if (lower == 'foundationwall') {
      Get.snackbar(
        'Foundation wall',
        'Tap connected points continuously. Right-click or long-press to add '
            'another segment or continue to foundation wall details.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    if (lower == 'concretebenchworktop') {
      Get.snackbar(
        'Concrete Bench & Worktop',
        'Trace the top/worktop outline and close the polygon. Then add supports, openings, reinforcement and BOQ links.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    if (lower == 'roadprofile') {
      Get.snackbar(
        'Road profile',
        'Tap connected points continuously. Right-click or long-press to add '
            'another segment or continue to road profile details.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    if (lower == 'civilwork') {
      Get.snackbar(
        'Kerbstone',
        'Tap connected points continuously. Right-click or long-press to add '
            'another segment or continue to kerbstone details.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    if (lower == 'drainage') {
      Get.snackbar(
        'Drainage',
        'Tap connected points continuously. Right-click or long-press to add '
            'another segment or continue to drainage details.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    if (lower == 'slabrebarai') {
      Get.snackbar(
        'Slab Rebar',
        'Tap the start and end points of one bar length, then enter its '
            'mark, size, number and spacing.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    if (lower == 'count') {
      Get.snackbar(
        'Count',
        'Tap each object to mark it, then use Finish & save.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    if (lower == 'door') {
      Get.snackbar(
        'Door count',
        'Tap every door of one type, then choose Finish to configure its schedule.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }

    update(['topbar', 'toolbar', 'viewer', 'summary', 'preview']);
  }

  Future<void> configureActiveMeasurementTool() async {
    final lower = (activeMeasureType ?? '').trim().toLowerCase();
    const selfConfigured = {
      'compositebeam',
      'beamcomposite',
      'compositeslab',
      'slabcomposite',
      'slabrebarai',
      'compositecolumn',
      'columncomposite',
      'compositefooting',
      'footingcomposite',
      'compositestair',
      'staircomposite',
      'compositeramp',
      'rampcomposite',
      'retainingwall',
      'compositeretainingwall',
      'foundationwall',
      'compositeroofing',
      'roofsheeting',
      'trusstemplate',
      'openings',
      'door',
      'plinth',
      'groundpreparation',
      'civilwork',
      'drainage',
    };

    if (selfConfigured.contains(lower)) {
      Get.snackbar(
        activeLabel ?? 'Measurement tool',
        'This tool is configured after you draw its geometry.',
      );
      return;
    }

    final selection = await showMeasurementItemDialog();
    if (selection == null) return;

    activeLabel = selection.label;
    activeUnit = selection.unit;
    activeBoqCode = selection.boqCode;
    activeHeightM = selection.wallHeightM;
    activeMeasureType = activeMeasureType ?? selection.measureType;
    update(['topbar', 'summary', 'preview']);
  }

  void setMode(TakeoffMode m) {
    if (m != TakeoffMode.measureLength && it.isCountingFastSlabRebarBundles) {
      it.cancelFastSlabRebarBundleCount();
    }
    mode.value = m;
    if (m != TakeoffMode.editSegment) {
      selectedSegmentId = null;
      selectedAreaId = null;
    }
    it.clearCalibrationDraft();
    _lengthChainGroupId = null;
    _lengthChainSegmentIndex = 0;
    _roofChainBoq = null;
    _roofChainSessionDefaults = null;
    _timberRoofChainBoq = null;
    _timberRoofChainSessionDefaults = null;
    calibP1 = null;
    calibP2 = null;
    lengthP1 = null;
    lengthP2 = null;
    _draftLengthPoints.clear();
    _draftIndependentSegments.clear();
    _draftLenP1.value = null;
    _draftLenP2.value = null;
    _draftCountPoints.clear();
    _countGroupId = null;
    update(['viewer', 'topbar', 'overlay', 'summary']);
  }

  void showPreview({
    required Offset p1,
    required Offset p2,
    required Map<String, dynamic> drawingData,
  }) {
    previewP1 = p1;
    previewP2 = p2;

    // compute px distance
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final distPx = math.sqrt(dx * dx + dy * dy);
    previewPixelDistanceBase = distPx;

    final calibrated = drawingData['calibrated'] == true;
    final pxPerM = (drawingData['pixelsPerUnit'] ?? 0).toDouble();

    if (calibrated && pxPerM > 0) {
      previewLengthMeters = distPx / pxPerM;
      previewCalibrated = true;
    } else {
      previewLengthMeters = null;
      previewCalibrated = false;
    }

    previewHeightM = null;
    previewHeightController.clear();
    recomputePreviewQuantity();

    previewVisible = true;
    update(['preview']);
  }

  void hidePreview() {
    previewVisible = false;
    update(['preview']);
  }

  void recomputePreviewQuantity() {
    final unit = activeUnit ?? 'm';
    final len = previewLengthMeters;
    final h = previewHeightM;
    final walling = isWallingActive;

    if (len == null) {
      previewQuantity = null;
      return;
    }

    switch (unit) {
      case 'm':
        previewQuantity = len;
        break;
      case 'm2':
        previewQuantity =
            walling ? ((h == null || h <= 0) ? null : len * h) : len;
        break;
      case 'item':
      case 'ps':
        previewQuantity = 1.0;
        break;
      case 'm3':
      case 'kg':
        previewQuantity = len;
        break;
      default:
        previewQuantity = len;
        break;
    }
  }

  void dragPreview(Offset delta) {
    previewOffset += delta;
    update(['preview']);
  }

  double _polygonAreaPx(List<Offset> polygon) {
    if (polygon.length < 3) return 0;
    double sum = 0.0;
    for (int i = 0; i < polygon.length; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % polygon.length];
      sum += p1.dx * p2.dy - p2.dx * p1.dy;
    }
    return sum / 2.0;
  }

  Future<LenDialogAction> _saveLengthMeasurement({
    required CollectionReference<Map<String, dynamic>> measurementsRef,
    required String projectId,
    required String buildingId,
    required String drawingId,

    required String? activeLabel,
    required String? activeBoqCode,
    required String? activeMeasureType,
    required String unit,

    required double lengthM,
    required double lengthPx,
    required Offset p1,
    required Offset p2,
    List<LengthDraftSegment>? draftSegments,

    required int currentColorValue,

    double? initialHeightM,
    String? lengthGroupId,
    int? chainSegmentIndex,
  }) async {
    final ctx = Get.context;
    if (ctx == null) return LenDialogAction.cancel;

    if (lengthM <= 0) {
      Get.snackbar(
        'Invalid',
        'Length must be > 0',
        snackPosition: SnackPosition.BOTTOM,
      );
      return LenDialogAction.cancel;
    }

    String _s(dynamic v) => (v ?? '').toString().trim();

    // keep a normalized version for debug/migration (does NOT “fix” a short code)
    String _normBoq(String code) {
      var c = code.trim();
      c = c.replaceAll(RegExp(r'\s+'), ''); // remove spaces like "3.12 (A)"
      return c;
    }

    final segmentsToSave =
        (draftSegments == null || draftSegments.isEmpty)
            ? <LengthDraftSegment>[
              LengthDraftSegment(
                p1: p1,
                p2: p2,
                lengthM: lengthM,
                lengthPx: lengthPx,
              ),
            ]
            : draftSegments;

    // geometry
    final segData = {
      'p1': {'x': p1.dx, 'y': p1.dy},
      'p2': {'x': p2.dx, 'y': p2.dy},
    };
    final polylineData =
        segmentsToSave
            .map(
              (s) => {
                'p1': {'x': s.p1.dx, 'y': s.p1.dy},
                'p2': {'x': s.p2.dx, 'y': s.p2.dy},
                'lengthM': s.lengthM,
                'lengthPx': s.lengthPx,
              },
            )
            .toList();

    final u = unit.trim().toLowerCase(); // expected 'm' or 'm2'
    final needsHeight =
        u == 'm2'; // your original "height" mode (length * height)
    final defaults = getLengthDefaults(activeMeasureType);
    final defaultRows =
        defaults?.rows
            .where((r) => _s(r['boqCode']).isNotEmpty)
            .map(
              (r) => _LengthBoqRow(
                label: _s(r['label']).isEmpty ? 'Length' : _s(r['label']),
                boqCode: _s(r['boqCode']),
                boqDesc: _s(r['boqDescription']),
              ),
            )
            .toList() ??
        <_LengthBoqRow>[];

    final heightCtrl = TextEditingController(
      text:
          (initialHeightM != null && initialHeightM > 0)
              ? initialHeightM.toString()
              : (defaults?.heightM != null && defaults!.heightM! > 0)
              ? defaults.heightM.toString()
              : '',
    );

    // ✅ NEW: width-area option (length × width => m²)
    bool useWidthArea = false;
    final widthCtrl = TextEditingController(text: '');

    // ✅ multiplying factor
    final factorCtrl = TextEditingController(text: '1');

    double _d(String s, [double def = 0.0]) => double.tryParse(s.trim()) ?? def;

    /// Base value BEFORE factor
    /// - if width area ON: base = length * width (m²)
    /// - else if needsHeight (unit m²): base = length * height (m²)
    /// - else: base = length (m)
    double baseComputedValue() {
      if (useWidthArea) {
        final w = _d(widthCtrl.text, 0.0);
        return (w > 0) ? (lengthM * w) : 0.0;
      }

      if (!needsHeight) return lengthM;

      final h = _d(heightCtrl.text, 0.0);
      return (h > 0) ? (lengthM * h) : 0.0;
    }

    /// Final value AFTER factor
    double computedValue() {
      final base = baseComputedValue();
      final f = _d(factorCtrl.text, 1.0);
      if (base <= 0 || f <= 0) return 0.0;
      return base * f;
    }

    // ---- rows (multi BOQ) ----
    final rows =
        defaultRows.isNotEmpty
            ? defaultRows
            : <_LengthBoqRow>[
              _LengthBoqRow(
                label: (activeLabel ?? 'Length').trim(),
                boqCode: _s(activeBoqCode),
                boqDesc: '',
              ),
            ];

    bool isSaving = false;
    String? errorText;

    final action =
        await Get.dialog<LenDialogAction>(
          StatefulBuilder(
            builder: (dCtx, setStateDialog) {
              Future<void> pickForRow(_LengthBoqRow r) async {
                final picked = await it.showBoqPickerDialog(context: dCtx);
                if (picked == null) return;

                final pickedCode = _s(picked.code);
                final pickedDesc = _s(picked.description);

                setStateDialog(() {
                  r.boqCodeCtrl.text = pickedCode;
                  r.boqDescCtrl.text = pickedDesc;

                  final t = r.labelCtrl.text.trim().toLowerCase();
                  if (r.labelCtrl.text.trim().isEmpty ||
                      t == 'length' ||
                      t == 'area') {
                    r.labelCtrl.text =
                        pickedDesc.isNotEmpty ? pickedDesc : 'Measurement item';
                  }
                });
              }

              // for UI preview
              final f = _d(factorCtrl.text, 1.0);
              final w = _d(widthCtrl.text, 0.0);
              final h = _d(heightCtrl.text, 0.0);

              final base = baseComputedValue();
              final fin = computedValue();

              final modeLabel =
                  useWidthArea
                      ? 'Area by width (L×W)'
                      : (needsHeight ? 'Area by height (L×H)' : 'Length');

              final unitPreview =
                  useWidthArea ? 'm²' : (needsHeight ? 'm²' : 'm');
              final pickedBoqCount =
                  rows
                      .where((r) => r.boqCodeCtrl.text.trim().isNotEmpty)
                      .length;
              final hasPickedBoq = pickedBoqCount > 0;

              return AlertDialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                clipBehavior: Clip.antiAlias,
                titlePadding: EdgeInsets.zero,
                contentPadding: EdgeInsets.zero,
                actionsPadding: const EdgeInsets.fromLTRB(28, 0, 28, 26),
                title: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0F2F6F), Color(0xFF1E63F0)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        child: const Icon(
                          Icons.straighten,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Save length measurement',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 24,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Review quantity, factor, and BOQ mappings before saving.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            (defaults == null || isSaving)
                                ? null
                                : () {
                                  setStateDialog(() {
                                    // paste unit + height (existing behavior)
                                    if (defaults.unit == 'm2') {
                                      heightCtrl.text =
                                          (defaults.heightM ?? 0).toString();
                                    } else {
                                      heightCtrl.text = '';
                                    }

                                    // NOTE: width mode + width value not stored in defaults currently.
                                    // Keep current width settings as-is.

                                    // replace rows
                                    for (final r in rows) {
                                      r.dispose();
                                    }
                                    rows
                                      ..clear()
                                      ..addAll(
                                        defaults.rows.map(
                                          (m) => _LengthBoqRow(
                                            label:
                                                (m['label'] ?? '').toString(),
                                            boqCode:
                                                (m['boqCode'] ?? '').toString(),
                                            boqDesc:
                                                (m['boqDescription'] ?? '')
                                                    .toString(),
                                          ),
                                        ),
                                      );
                                  });
                                },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white54,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.32),
                          ),
                          backgroundColor: Colors.white.withValues(alpha: 0.10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        icon: const Icon(Icons.content_paste, size: 18),
                        label: const Text('Paste last'),
                      ),
                    ],
                  ),
                ),
                content: SizedBox(
                  width: 720,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _LengthMetricPill(
                                    icon: Icons.straighten,
                                    label: 'Measured length',
                                    value: '${lengthM.toStringAsFixed(3)} m',
                                    color: const Color(0xFF2563EB),
                                  ),
                                  _LengthMetricPill(
                                    icon: Icons.calculate_outlined,
                                    label: 'Mode',
                                    value: modeLabel,
                                    color: const Color(0xFF7C3AED),
                                  ),
                                  _LengthMetricPill(
                                    icon: Icons.square_foot_outlined,
                                    label: 'Unit',
                                    value: unitPreview,
                                    color: const Color(0xFF059669),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    size: 18,
                                    color: Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Save & measure next keeps this endpoint as the start of the next segment.',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF475569),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: SwitchListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            secondary: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.crop_square_outlined,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                            title: const Text(
                              'Compute area using width (L × W)',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: const Text(
                              'Turn ON to save m² as Length × Width for DPM, formwork strips, trench width, and similar items.',
                              style: TextStyle(color: Color(0xFF64748B)),
                            ),
                            value: useWidthArea,
                            onChanged:
                                isSaving
                                    ? null
                                    : (v) {
                                      setStateDialog(() {
                                        useWidthArea = v;
                                        errorText = null;
                                      });
                                    },
                          ),
                        ),

                        if (useWidthArea) ...[
                          const SizedBox(height: 6),
                          TextField(
                            controller: widthCtrl,
                            enabled: !isSaving,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Width (m) e.g. 0.60',
                              border: OutlineInputBorder(),
                              isDense: true,
                              helperText: 'Area base = Length × Width',
                            ),
                            onChanged: (_) => setStateDialog(() {}),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Width: ${w.toStringAsFixed(3)} m',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ] else if (needsHeight) ...[
                          const SizedBox(height: 12),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Height (m) for m² items (plinth/plaster/bitumen):',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: heightCtrl,
                            enabled: !isSaving,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Height in meters (e.g. 0.45)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => setStateDialog(() {}),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Height: ${h.toStringAsFixed(3)} m',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],

                        // ✅ multiplying factor
                        const SizedBox(height: 12),
                        TextField(
                          controller: factorCtrl,
                          enabled: !isSaving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Multiplying factor (e.g. 1, 2, 0.5)',
                            border: OutlineInputBorder(),
                            isDense: true,
                            helperText: 'Final value = Base × Factor',
                          ),
                          onChanged: (_) => setStateDialog(() {}),
                        ),

                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF4FF),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFD1E0FF)),
                          ),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _LengthMetricPill(
                                icon: Icons.layers_outlined,
                                label: 'Base',
                                value:
                                    '${base.toStringAsFixed(3)} $unitPreview',
                                color: const Color(0xFF2563EB),
                              ),
                              _LengthMetricPill(
                                icon: Icons.functions,
                                label: 'Factor',
                                value: '× ${f.toStringAsFixed(2)}',
                                color: const Color(0xFFEA580C),
                              ),
                              _LengthMetricPill(
                                icon: Icons.check_circle_outline,
                                label: 'Final quantity',
                                value: '${fin.toStringAsFixed(3)} $unitPreview',
                                color: const Color(0xFF059669),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),
                        const Row(
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              color: Color(0xFF2563EB),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'BOQ mappings',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Add one or more BOQ items for this same measurement.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        if (!hasPickedBoq) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFFED7AA),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Color(0xFFEA580C),
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'BOQ item is required. Pick at least one BOQ item before saving.',
                                    style: TextStyle(
                                      color: Color(0xFF9A3412),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),

                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: rows.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final r = rows[i];
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF0F172A,
                                    ).withValues(alpha: 0.04),
                                    blurRadius: 18,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: r.labelCtrl,
                                          enabled: !isSaving,
                                          decoration: const InputDecoration(
                                            labelText:
                                                'Label (e.g. Coping / Window cill / DPM strip)',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (rows.length > 1)
                                        Container(
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFEF2F2),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: IconButton(
                                            tooltip: 'Remove',
                                            onPressed:
                                                isSaving
                                                    ? null
                                                    : () {
                                                      setStateDialog(() {
                                                        rows
                                                            .removeAt(i)
                                                            .dispose();
                                                      });
                                                    },
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: Color(0xFFDC2626),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: r.boqCodeCtrl,
                                          readOnly: true,
                                          decoration: const InputDecoration(
                                            labelText: 'BOQ code',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        onPressed:
                                            isSaving
                                                ? null
                                                : () => pickForRow(r),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 18,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.search,
                                          size: 18,
                                        ),
                                        label: const Text('Pick'),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: r.boqDescCtrl,
                                    readOnly: true,
                                    maxLines: 2,
                                    decoration: const InputDecoration(
                                      labelText: 'BOQ description',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed:
                                isSaving
                                    ? null
                                    : () {
                                      setStateDialog(() {
                                        rows.add(
                                          _LengthBoqRow(
                                            label: '',
                                            boqCode: '',
                                            boqDesc: '',
                                          ),
                                        );
                                      });
                                    },
                            icon: const Icon(Icons.add, size: 18),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            label: const Text('Add another BOQ item'),
                          ),
                        ),

                        if (errorText != null) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              errorText!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed:
                        isSaving
                            ? null
                            : () => Get.back(result: LenDialogAction.cancel),
                    child: const Text('Cancel'),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 18,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed:
                        (isSaving || !hasPickedBoq)
                            ? null
                            : () {
                              setStateDialog(() {
                                errorText = null;

                                final f = _d(factorCtrl.text, 0.0);
                                if (f <= 0) {
                                  errorText = 'Factor must be > 0.';
                                  return;
                                }

                                if (useWidthArea) {
                                  final w = _d(widthCtrl.text, 0.0);
                                  if (w <= 0) {
                                    errorText =
                                        'Width must be > 0 to compute area.';
                                    return;
                                  }
                                } else if (needsHeight) {
                                  final h = _d(heightCtrl.text, 0.0);
                                  if (h <= 0) {
                                    errorText =
                                        'Height must be > 0 for m² items.';
                                    return;
                                  }
                                }

                                if (computedValue() <= 0) {
                                  errorText = 'Computed value must be > 0.';
                                  return;
                                }
                              });

                              if (errorText != null) return;
                              Get.back(result: LenDialogAction.cont);
                            },
                    child: const Text('Save & measure next'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 18,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed:
                        (isSaving || !hasPickedBoq)
                            ? null
                            : () {
                              setStateDialog(() {
                                errorText = null;

                                final f = _d(factorCtrl.text, 0.0);
                                if (f <= 0) {
                                  errorText = 'Factor must be > 0.';
                                  return;
                                }

                                if (useWidthArea) {
                                  final w = _d(widthCtrl.text, 0.0);
                                  if (w <= 0) {
                                    errorText =
                                        'Width must be > 0 to compute area.';
                                    return;
                                  }
                                } else if (needsHeight) {
                                  final h = _d(heightCtrl.text, 0.0);
                                  if (h <= 0) {
                                    errorText =
                                        'Height must be > 0 for m² items.';
                                    return;
                                  }
                                }

                                if (computedValue() <= 0) {
                                  errorText = 'Computed value must be > 0.';
                                  return;
                                }
                              });

                              if (errorText != null) return;
                              Get.back(result: LenDialogAction.save);
                            },
                    child: const Text('Save & Finish'),
                  ),
                ],
              );
            },
          ),
          barrierDismissible: false,
        ) ??
        LenDialogAction.cancel;

    if (action == LenDialogAction.cancel) {
      for (final r in rows) r.dispose();
      heightCtrl.dispose();
      widthCtrl.dispose();
      factorCtrl.dispose();
      return LenDialogAction.cancel;
    }

    // Validate rows (at least one boqCode)
    final cleaned =
        rows
            .map(
              (r) => (
                label: r.labelCtrl.text.trim(),
                boq: r.boqCodeCtrl.text.trim(),
                desc: r.boqDescCtrl.text.trim(),
              ),
            )
            .where((x) => x.boq.isNotEmpty)
            .toList();

    if (cleaned.isEmpty) {
      for (final r in rows) r.dispose();
      heightCtrl.dispose();
      widthCtrl.dispose();
      factorCtrl.dispose();
      Get.snackbar(
        'Missing BOQ',
        'Pick at least one BOQ code to save.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return LenDialogAction.cancel;
    }

    final factor = _d(factorCtrl.text, 1.0);
    final widthM = useWidthArea ? _d(widthCtrl.text, 0.0) : null;
    final heightM =
        (!useWidthArea && needsHeight) ? _d(heightCtrl.text, 0.0) : null;

    final baseValueToSave = baseComputedValue(); // before factor
    final valueToSave = computedValue(); // after factor

    // unit saved depends on mode
    final unitToSave = useWidthArea ? 'm2' : (needsHeight ? 'm2' : 'm');

    // Optional: remember defaults (width not persisted by your current defaults structure)
    rememberLengthDefaults(
      activeMeasureType: activeMeasureType,
      unit: unitToSave,
      heightM: (!useWidthArea && unitToSave == 'm2') ? heightM : null,
      rows:
          cleaned
              .map(
                (x) => <String, String>{
                  'label': x.label,
                  'boqCode': x.boq,
                  'boqDescription': x.desc,
                },
              )
              .toList(),
    );

    final resolvedLengthGroupId = lengthGroupId ?? measurementsRef.doc().id;
    var saved = false;
    OverlayEntry? progressOverlay;

    void showSaveProgressDialog() {
      final overlayContext = Get.overlayContext ?? ctx;
      final overlay = Overlay.maybeOf(overlayContext, rootOverlay: true);
      if (overlay == null) return;

      progressOverlay = OverlayEntry(
        builder:
            (_) => Material(
              color: Colors.black.withValues(alpha: 0.58),
              child: Center(
                child: Container(
                  width: 360,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.18),
                        blurRadius: 36,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Saving measurement',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        action == LenDialogAction.cont
                            ? 'Saving this segment, then preparing the next measurement point...'
                            : 'Saving this length measurement and BOQ mapping...',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      );
      overlay.insert(progressOverlay!);
    }

    void closeSaveProgressDialog() {
      progressOverlay?.remove();
      progressOverlay = null;
    }

    try {
      showSaveProgressDialog();
      await Future<void>.delayed(Duration.zero);

      final batch = FirebaseFirestore.instance.batch();
      final now = FieldValue.serverTimestamp();

      for (final x in cleaned) {
        for (var i = 0; i < segmentsToSave.length; i++) {
          final segment = segmentsToSave[i];
          final docRef = measurementsRef.doc();
          final segmentBaseValue =
              useWidthArea
                  ? (widthM != null && widthM > 0
                      ? segment.lengthM * widthM
                      : 0)
                  : (needsHeight
                      ? (heightM != null && heightM > 0
                          ? segment.lengthM * heightM
                          : 0)
                      : segment.lengthM);
          final segmentValueToSave = segmentBaseValue * factor;

          batch.set(docRef, {
            'projectId': projectId,
            'buildingId': buildingId,
            'drawingId': drawingId,

            'lengthGroupId': resolvedLengthGroupId,
            'chainSegmentIndex': (chainSegmentIndex ?? 0) + i,
            'chainSegmentCount': segmentsToSave.length,

            'isDerived': false,

            'measureType': 'length', // geometry is still a segment
            'activeMeasureType': (activeMeasureType ?? '').toString().trim(),
            'type': 'lengthMeasure',

            'unit': unitToSave,
            'value': segmentValueToSave,
            'factor': factor,
            'baseValue': segmentBaseValue,
            'groupValue': valueToSave, // total after factor
            'groupBaseValue': baseValueToSave,

            // raw inputs
            'lengthM': segment.lengthM,
            'lengthPx': segment.lengthPx,
            'totalLengthM': lengthM,
            'totalLengthPx': lengthPx,

            // ✅ NEW: area-by-width mode fields (optional)
            'useWidthArea': useWidthArea,
            'widthM': widthM,
            'heightM': heightM, // only when NOT using width-area and unit is m2
            'areaMode':
                useWidthArea
                    ? 'width'
                    : (unitToSave == 'm2' ? 'height' : 'none'),

            'label': x.label.isEmpty ? 'Measurement item' : x.label,

            'boqCode': x.boq,
            'boqCodeRaw': x.boq,
            'boqCodeNorm': _normBoq(x.boq),
            'boqDescription': x.desc,

            // geometry
            'p1': {'x': segment.p1.dx, 'y': segment.p1.dy},
            'p2': {'x': segment.p2.dx, 'y': segment.p2.dy},
            'segment': {
              'p1': {'x': segment.p1.dx, 'y': segment.p1.dy},
              'p2': {'x': segment.p2.dx, 'y': segment.p2.dy},
            },
            'groupSegment': segData,
            'polylineSegments': polylineData,

            'color': currentColorValue,

            'createdAt': now,
            'updatedAt': now,
          });
        }
      }

      await batch.commit();
      saved = true;
    } catch (e) {
      closeSaveProgressDialog();
      await Get.dialog<void>(
        AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('Save failed'),
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => Get.back<void>(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      closeSaveProgressDialog();
      for (final r in rows) r.dispose();
      heightCtrl.dispose();
      widthCtrl.dispose();
      factorCtrl.dispose();
    }

    return saved ? action : LenDialogAction.cancel;
  }

  double _num(dynamic v, [double def = 0]) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? def;
  }

  String _unitDisplay(String u) => u == 'm2' ? 'm²' : (u == 'm3' ? 'm³' : u);

  Future<void> handleallingViewTap({
    required Map<String, dynamic> drawingData,
    required Offset p1,
    required Offset p2,
  }) async {
    // Prevent re-entry while dialog is open (optional but recommended)
    if (_wallEditorOpen == true) return;

    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final lengthPx = math.sqrt(dx * dx + dy * dy);

    final lenM = distanceInMeters(p1, p2, drawingData);

    if (lenM == null || lenM <= 0) {
      Get.snackbar('Walling', 'Invalid length (check calibration).');
      return;
    }

    String? currentWallGroupId;

    // Defaults
    final groupId =
        currentWallGroupId ?? 'WALL-${DateTime.now().millisecondsSinceEpoch}';
    final initialHeightM = 3.0;
    final grossAreaM2 = lenM * initialHeightM;

    _wallEditorOpen = true;

    try {
      final ok = await it.openWallingEditorDialog(
        groupId: groupId,
        label: '',
        grossLengthM: lenM,
        grossAreaM2: grossAreaM2,
        initialHeightM: initialHeightM,
        initialWallBoqCode: '',
        doors: <DoorInput>[],
        windows: <WindowInput>[],
        finishes: WallingFinishInput(),
      );

      if (ok == true) {
        // ✅ If you want to persist geometry, do it here BEFORE clearing:
        // segments.add(WallSegment(p1: lengthP1!, p2: lengthP2!, lengthM: lenM));
        // update(['viewer', 'summary']);
      }
    } finally {
      // ✅ ALWAYS clear draft points when dialog closes (OK or Cancel)
      lengthP1 = null;
      lengthP2 = null;
      _wallEditorOpen = false;
      update(['viewer']);
    }
  }

  Future<FoundationSaveAction> handleFoundationWallTap({
    required Map<String, dynamic> drawingData,
    required Offset p1,
    required Offset p2,
    // String? currentWallId, // ✅ NEW (optional) passed from onImageTap(...)
  }) async {
    return handleFoundationWall(
      measurementsRef: measurementsRef,
      projectId: projectId,
      buildingId: buildingId,
      drawingId: drawingId,
      drawingData: drawingData,
      p1: p1,
      p2: p2,

      activeLabel: activeLabel,
      activeBoqCode: activeBoqCode,
      activeMeasureType: activeMeasureType,

      // activeUnit: activeUnit,
      // activeHeightM: activeHeightM,
      // setActiveHeightM: (h) => activeHeightM = h,
      currentColorValue: currentColor.value,
    );
  }

  Future<FoundationSaveAction> handleFoundationWall({
    required CollectionReference<Map<String, dynamic>> measurementsRef,
    required String projectId,
    required String buildingId,
    required String drawingId,

    required Map<String, dynamic> drawingData,
    required Offset p1,
    required Offset p2,

    // from your controller state
    required String? activeLabel,
    required String? activeBoqCode,
    required String? activeMeasureType,
    required int currentColorValue,
  }) async {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final lengthPx = math.sqrt(dx * dx + dy * dy);

    final lenM = distanceInMeters(p1, p2, drawingData);
    if (lenM == null || lenM <= 0) {
      Get.snackbar('Foundation wall', 'Invalid length (check calibration).');
      return FoundationSaveAction.cancel;
    }

    return it.openFoundationWallSegmentDialog(
      p1: p1,
      p2: p2,
      drawingData: drawingData,
      wallGroupId: currentWallId, // ✅ add
    );

    // keep active id so next segments continue same wall (unless user changes)
    // activeFoundationWallId = wallGroupId;
  }

  Future<LenDialogAction> completeLengthMeasurementTap({
    required Map<String, dynamic> drawingData,
    required Offset p1,
    required Offset p2,
    List<LengthDraftSegment>? draftSegments,
    String? lengthGroupId,
    int? chainSegmentIndex,
  }) async {
    return completeLengthMeasurement(
      measurementsRef: measurementsRef,
      projectId: projectId,
      buildingId: buildingId,
      drawingId: drawingId,
      drawingData: drawingData,
      p1: p1,
      p2: p2,
      draftSegments: draftSegments,

      activeLabel: activeLabel,
      activeBoqCode: activeBoqCode,
      activeMeasureType: activeMeasureType,
      activeUnit: activeUnit,
      activeHeightM: activeHeightM,

      currentColorValue: currentColor.value,
      lengthGroupId: lengthGroupId,
      chainSegmentIndex: chainSegmentIndex,
    );
  }

  Future<LenDialogAction> completeLengthMeasurement({
    required CollectionReference<Map<String, dynamic>> measurementsRef,
    required String projectId,
    required String buildingId,
    required String drawingId,

    required Map<String, dynamic> drawingData,
    required Offset p1,
    required Offset p2,
    List<LengthDraftSegment>? draftSegments,

    // from your controller state
    required String? activeLabel,
    required String? activeBoqCode,
    required String? activeMeasureType,
    required String? activeUnit,
    required double? activeHeightM, // used + prefill for m2 line items

    required int currentColorValue,
    String? lengthGroupId,
    int? chainSegmentIndex,
  }) async {
    final cleanDraftSegments =
        draftSegments?.where((s) => s.lengthM > 0 && s.lengthPx > 0).toList();

    // 1) px length
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final lengthPx =
        (cleanDraftSegments != null && cleanDraftSegments.isNotEmpty)
            ? cleanDraftSegments.fold<double>(0, (sum, s) => sum + s.lengthPx)
            : math.sqrt(dx * dx + dy * dy);
    if (lengthPx <= 0) return LenDialogAction.cancel;

    // 2) calibration -> meters
    final calibrated = drawingData['calibrated'] == true;
    final pxPerM = _num(drawingData['pixelsPerUnit'], 0); // px per 1m
    final double? lengthM =
        (cleanDraftSegments != null && cleanDraftSegments.isNotEmpty)
            ? cleanDraftSegments.fold<double>(0, (sum, s) => sum + s.lengthM)
            : (calibrated && pxPerM > 0)
            ? (lengthPx / pxPerM)
            : null;

    final unit = (activeUnit ?? 'm').trim();

    if (lengthM == null) {
      Get.snackbar(
        'Not calibrated',
        'Calibrate drawing first to measure length.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return LenDialogAction.cancel;
    }

    return _saveLengthMeasurement(
      measurementsRef: measurementsRef,
      projectId: projectId,
      buildingId: buildingId,
      drawingId: drawingId,
      activeLabel: activeLabel,
      activeBoqCode: activeBoqCode,
      activeMeasureType: activeMeasureType,
      unit: unit,
      lengthM: lengthM,
      lengthPx: lengthPx,
      p1: p1,
      p2: p2,
      draftSegments: cleanDraftSegments,
      currentColorValue: currentColorValue,
      initialHeightM: activeHeightM,
      lengthGroupId: lengthGroupId,
      chainSegmentIndex: chainSegmentIndex,
    );
  }

  Future<void> _saveAreaMeasurement({
    required List<Offset> polygon,
    required double areaPxBase,
    required double? areaM2,
    List<List<Offset>>? polygons,
    List<List<Offset>> deductionPolygons = const [],
  }) async {
    final ctx = Get.context;

    // ---- must have m2 to save as real measurement ----
    if (areaM2 == null || areaM2 <= 0) {
      if (ctx != null) {
        Get.snackbar(
          'Not calibrated',
          'Cannot save in m² because drawing is not calibrated.',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
      return;
    }

    final polygonsToSave =
        (polygons == null || polygons.isEmpty) ? [polygon] : polygons;
    final polygonAreasPx =
        polygonsToSave.map((points) => _polygonAreaPx(points).abs()).toList();
    final totalPolygonAreaPx = polygonAreasPx.fold<double>(0, (a, b) => a + b);
    final deductionAreasPx =
        deductionPolygons
            .map((points) => _polygonAreaPx(points).abs())
            .toList();
    final totalDeductionAreaPx = deductionAreasPx.fold<double>(
      0,
      (a, b) => a + b,
    );
    final netAreaPx = totalPolygonAreaPx - totalDeductionAreaPx;
    if (netAreaPx <= 0) {
      Get.snackbar(
        'Invalid deduction',
        'The deducted area must be smaller than the gross measured area.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final grossAreaM2 = areaM2 * totalPolygonAreaPx / netAreaPx;
    final deductionAreaM2 = areaM2 * totalDeductionAreaPx / netAreaPx;
    final deductionPolygonData =
        deductionPolygons
            .map(
              (points) => {
                'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
              },
            )
            .toList();

    // ---- rows (multi BOQ) ----
    final rows = <_AreaBoqRow>[
      _AreaBoqRow(
        label: (activeLabel ?? 'Area').trim(),
        boqCode: (activeBoqCode ?? '').trim(),
        boqDesc: '',
      ),
    ];

    String? errorText;

    // ✅ multiplying factor (default 1)
    final multiplyingFactorCtrl = TextEditingController(text: '1');

    // ✅ roof covering extra controls (default from last template if exists)
    final activeTypeLower = (activeMeasureType ?? '').trim().toLowerCase();
    bool isRoofCovering =
        activeTypeLower == 'roofsheeting' ||
        (lastAreaTemplate?.isRoofCovering ?? false);
    final roofAngleCtrl = TextEditingController(
      text: (lastAreaTemplate?.roofAngleDeg ?? 30).toString(),
    );

    // ✅ NEW: volume option + depth
    bool asVolume =
        activeTypeLower == 'volume' || (lastAreaTemplate?.asVolume ?? false);
    final depthCtrl = TextEditingController(
      text: (lastAreaTemplate?.depthM ?? 0.15).toString(),
    );

    double _d(String s, [double def = 0.0]) => double.tryParse(s.trim()) ?? def;
    double _degToRad(double deg) => deg * (math.pi / 180.0);
    double _cosDeg(double deg) => math.cos(_degToRad(deg));

    double _mult() {
      final v = _d(multiplyingFactorCtrl.text, 1.0);
      if (v.isNaN || v.isInfinite) return 1.0;
      return v;
    }

    double _depth() {
      final v = _d(depthCtrl.text, 0.0);
      if (v.isNaN || v.isInfinite) return 0.0;
      return v;
    }

    // returns (planArea, slopeFactor, slopeArea, angleDeg) based on UI state (BASE values, not multiplied)
    ({double planArea, double slopeFactor, double slopeArea, double? angleDeg})
    _roofCalcBase() {
      final plan = areaM2!;
      if (!isRoofCovering) {
        return (
          planArea: plan,
          slopeFactor: 1.0,
          slopeArea: plan,
          angleDeg: null,
        );
      }

      final ang = _d(roofAngleCtrl.text, 0.0);
      final c = _cosDeg(ang);

      if (ang <= 0 || ang >= 89.9 || c <= 0.000001) {
        return (
          planArea: plan,
          slopeFactor: 0.0,
          slopeArea: 0.0,
          angleDeg: ang,
        );
      }

      final factor = 1.0 / c;
      final slope = plan * factor;
      return (
        planArea: plan,
        slopeFactor: factor,
        slopeArea: slope,
        angleDeg: ang,
      );
    }

    // ✅ build template from dialog state (for remembering)
    AreaTemplate _buildTemplateFromDialog() {
      final angle = _d(roofAngleCtrl.text, 30);
      final tplRows =
          rows
              .map(
                (r) => AreaBoqTemplateRow(
                  label: r.labelCtrl.text.trim(),
                  boqCode: r.boqCodeCtrl.text.trim(),
                  boqDesc: r.boqDescCtrl.text.trim(),
                ),
              )
              .where((r) => r.boqCode.isNotEmpty)
              .toList();

      return AreaTemplate(
        isRoofCovering: isRoofCovering,
        roofAngleDeg: angle,
        rows: tplRows,

        // ✅ NEW fields (make sure AreaTemplate has these)
        asVolume: asVolume,
        depthM: _depth(),
      );
    }

    // ✅ apply previous template into current dialog UI
    void _applyTemplateToDialog(AreaTemplate tpl, StateSetter setStateDialog) {
      for (final r in rows) {
        r.dispose();
      }
      rows.clear();

      if (tpl.rows.isEmpty) {
        rows.add(_AreaBoqRow(label: 'Area', boqCode: '', boqDesc: ''));
      } else {
        for (final tr in tpl.rows) {
          rows.add(
            _AreaBoqRow(
              label: tr.label,
              boqCode: tr.boqCode,
              boqDesc: tr.boqDesc,
            ),
          );
        }
      }

      isRoofCovering = tpl.isRoofCovering;
      roofAngleCtrl.text = tpl.roofAngleDeg.toString();

      // ✅ NEW restore volume mode
      asVolume = tpl.asVolume;
      depthCtrl.text = tpl.depthM.toString();

      errorText = null;
      setStateDialog(() {});
    }

    final ok =
        await Get.dialog<bool>(
          StatefulBuilder(
            builder: (dCtx, setStateDialog) {
              Future<void> pickForRow(_AreaBoqRow r) async {
                final picked = await it.showBoqPickerDialog(context: dCtx);
                if (picked == null) return;

                final code = (picked.code ?? '').toString().trim();
                final desc = (picked.description ?? '').toString().trim();

                setStateDialog(() {
                  r.boqCodeCtrl.text = code;
                  r.boqDescCtrl.text = desc;

                  final lt = r.labelCtrl.text.trim().toLowerCase();
                  if (r.labelCtrl.text.trim().isEmpty || lt == 'area') {
                    r.labelCtrl.text = desc.isNotEmpty ? desc : 'Area item';
                  }
                });
              }

              final calcBase = _roofCalcBase();
              final mf = _mult();

              // ✅ area used depends on roof covering
              final areaUsedBase =
                  isRoofCovering ? calcBase.slopeArea : calcBase.planArea;

              // ✅ volume uses depth
              final d = asVolume ? _depth() : 0.0;

              final valueBase = asVolume ? (areaUsedBase * d) : areaUsedBase;
              final valueScaled = valueBase * mf;

              final showScaled = mf != 1.0;

              final canPaste = lastAreaTemplate != null;

              final summary =
                  asVolume
                      ? 'Area used (base): ${areaUsedBase.toStringAsFixed(3)} m²\n'
                          'Depth: ${d.toStringAsFixed(3)} m\n'
                          'Volume (base): ${valueBase.toStringAsFixed(3)} m³'
                          '${showScaled ? '\n\n× ${mf.toStringAsFixed(2)}  →  ${valueScaled.toStringAsFixed(3)} m³' : ''}'
                      : (isRoofCovering
                          ? 'Plan area (base): ${calcBase.planArea.toStringAsFixed(3)} m²\n'
                              'Slope factor: ${calcBase.slopeFactor.toStringAsFixed(4)}\n'
                              'Roof covering (slope base): ${calcBase.slopeArea.toStringAsFixed(3)} m²'
                              '${showScaled ? '\n\n× ${mf.toStringAsFixed(2)}  →  Plan: ${(calcBase.planArea * mf).toStringAsFixed(3)} m²,  Slope: ${(calcBase.slopeArea * mf).toStringAsFixed(3)} m²' : ''}'
                          : 'Area (base): ${calcBase.planArea.toStringAsFixed(3)} m²'
                              '${showScaled ? '\n× ${mf.toStringAsFixed(2)}  →  ${(calcBase.planArea * mf).toStringAsFixed(3)} m²' : ''}');

              Widget summaryChip(String label, String value, IconData icon) {
                return Container(
                  constraints: const BoxConstraints(minWidth: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE4E7EC)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: const Color(0xFF155EEF), size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF101828),
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              Widget savePanel({
                required String title,
                required String subtitle,
                required IconData icon,
                required Widget child,
                Widget? trailing,
              }) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE4E7EC)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0A101828),
                        blurRadius: 18,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF155EEF), Color(0xFF0B3B8F)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(icon, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    color: Color(0xFF101828),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  style: const TextStyle(
                                    color: Color(0xFF667085),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (trailing != null) trailing,
                        ],
                      ),
                      const SizedBox(height: 14),
                      child,
                    ],
                  ),
                );
              }

              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                clipBehavior: Clip.antiAlias,
                titlePadding: EdgeInsets.zero,
                contentPadding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                actionsPadding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                title: Container(
                  padding: const EdgeInsets.fromLTRB(22, 20, 18, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF102A56), Color(0xFF155EEF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(
                          Icons.save_alt_outlined,
                          color: Color(0xFFD6E4FF),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Save measurement',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              asVolume
                                  ? 'Map measured area to volume and BOQ items'
                                  : 'Review area, factor, and BOQ mappings',
                              style: const TextStyle(
                                color: Color(0xFFD6E4FF),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                content: SizedBox(
                  width: 680,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        savePanel(
                          title: 'Measured quantity',
                          subtitle:
                              'Base value, multiplier, and live saved result',
                          icon: Icons.analytics_outlined,
                          trailing:
                              canPaste
                                  ? OutlinedButton.icon(
                                    onPressed: () {
                                      _applyTemplateToDialog(
                                        lastAreaTemplate!,
                                        setStateDialog,
                                      );
                                      Get.snackbar(
                                        'Pasted',
                                        'Previous inputs restored.',
                                        snackPosition: SnackPosition.BOTTOM,
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.content_paste,
                                      size: 18,
                                    ),
                                    label: const Text('Paste previous'),
                                  )
                                  : null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  summaryChip(
                                    'Plan area',
                                    '${calcBase.planArea.toStringAsFixed(3)} m²',
                                    Icons.crop_square_rounded,
                                  ),
                                  if (isRoofCovering)
                                    summaryChip(
                                      'Slope area',
                                      '${calcBase.slopeArea.toStringAsFixed(3)} m²',
                                      Icons.roofing_outlined,
                                    ),
                                  if (asVolume)
                                    summaryChip(
                                      'Volume',
                                      '${valueScaled.toStringAsFixed(3)} m³',
                                      Icons.view_in_ar_outlined,
                                    )
                                  else
                                    summaryChip(
                                      'Saved value',
                                      '${valueScaled.toStringAsFixed(3)} m²',
                                      Icons.done_all_outlined,
                                    ),
                                  if (showScaled)
                                    summaryChip(
                                      'Factor',
                                      '× ${mf.toStringAsFixed(2)}',
                                      Icons.close_fullscreen_outlined,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                summary,
                                style: const TextStyle(
                                  color: Color(0xFF344054),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: multiplyingFactorCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  labelText:
                                      'Multiplying factor (e.g. 2 for 2 identical areas)',
                                  helperText:
                                      'Final saved value = base value × multiplying factor.',
                                ),
                                onChanged:
                                    (_) =>
                                        setStateDialog(() => errorText = null),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFE4E7EC),
                                  ),
                                ),
                                child: SwitchListTile(
                                  dense: true,
                                  title: const Text(
                                    'Compute volume (Area × Depth)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'If ON, unit will be m³. If OFF, unit remains m².',
                                  ),
                                  value: asVolume,
                                  onChanged:
                                      (v) => setStateDialog(() {
                                        asVolume = v;
                                        errorText = null;
                                      }),
                                ),
                              ),
                              if (asVolume) ...[
                                const SizedBox(height: 10),
                                TextField(
                                  controller: depthCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    labelText:
                                        'Depth / thickness (m) e.g. 0.15',
                                    helperText: 'Volume = (area used) × depth.',
                                  ),
                                  onChanged:
                                      (_) => setStateDialog(
                                        () => errorText = null,
                                      ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFE4E7EC),
                                  ),
                                ),
                                child: SwitchListTile(
                                  dense: true,
                                  title: const Text(
                                    'Roof covering (use slope area)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  value: isRoofCovering,
                                  onChanged:
                                      (v) => setStateDialog(() {
                                        isRoofCovering = v;
                                        errorText = null;
                                      }),
                                ),
                              ),
                              if (isRoofCovering) ...[
                                const SizedBox(height: 10),
                                TextField(
                                  controller: roofAngleCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    labelText: 'Roof angle (degrees) e.g. 30',
                                    helperText:
                                        'Slope factor = 1 / cos(angle). Used value = planArea × slopeFactor.',
                                  ),
                                  onChanged:
                                      (_) => setStateDialog(
                                        () => errorText = null,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        savePanel(
                          title: 'BOQ mappings',
                          subtitle:
                              'Add one or more BOQ items for this same measurement',
                          icon: Icons.receipt_long_outlined,
                          trailing: OutlinedButton.icon(
                            onPressed: () {
                              setStateDialog(() {
                                rows.add(
                                  _AreaBoqRow(
                                    label: '',
                                    boqCode: '',
                                    boqDesc: '',
                                  ),
                                );
                              });
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add BOQ item'),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: rows.length,
                            separatorBuilder:
                                (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final r = rows[i];

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  border: Border.all(
                                    color: const Color(0xFFE4E7EC),
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: r.labelCtrl,
                                            decoration: const InputDecoration(
                                              labelText:
                                                  'Label (e.g. Hardcore / DPM / Roof covering / Concrete)',
                                              border: OutlineInputBorder(),
                                              isDense: true,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (rows.length > 1)
                                          IconButton(
                                            tooltip: 'Remove',
                                            onPressed: () {
                                              setStateDialog(() {
                                                rows.removeAt(i).dispose();
                                              });
                                            },
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: r.boqCodeCtrl,
                                            readOnly: true,
                                            decoration: const InputDecoration(
                                              labelText: 'BOQ code',
                                              border: OutlineInputBorder(),
                                              isDense: true,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          onPressed: () => pickForRow(r),
                                          icon: const Icon(
                                            Icons.search,
                                            size: 18,
                                          ),
                                          label: const Text('Pick'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: r.boqDescCtrl,
                                      readOnly: true,
                                      maxLines: 2,
                                      decoration: const InputDecoration(
                                        labelText: 'BOQ description',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                        if (errorText != null) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              errorText!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Get.back(result: false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      // validate multiplying factor
                      final mf = _mult();
                      if (mf <= 0) {
                        setStateDialog(() {
                          errorText =
                              'Multiplying factor must be greater than 0.';
                        });
                        return;
                      }

                      // validate depth if volume
                      if (asVolume) {
                        final d = _depth();
                        if (d <= 0) {
                          setStateDialog(() {
                            errorText = 'Enter a valid depth/thickness (> 0).';
                          });
                          return;
                        }
                      }

                      // validate roof angle if needed
                      if (isRoofCovering) {
                        final ang = _d(roofAngleCtrl.text, 0.0);
                        final c = _cosDeg(ang);
                        if (ang <= 0 || ang >= 89.9 || c <= 0.000001) {
                          setStateDialog(() {
                            errorText =
                                'Enter a valid roof angle (between 0 and 89 degrees).';
                          });
                          return;
                        }
                      }

                      setStateDialog(() => errorText = null);
                      Get.back(result: true);
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ),
          barrierDismissible: false,
        ) ??
        false;

    if (!ok) {
      for (final r in rows) r.dispose();
      roofAngleCtrl.dispose();
      multiplyingFactorCtrl.dispose();
      depthCtrl.dispose();
      return;
    }

    // Validate rows: at least 1 has boqCode
    final cleaned =
        rows
            .map(
              (r) => (
                label: r.labelCtrl.text.trim(),
                boq: r.boqCodeCtrl.text.trim(),
                desc: r.boqDescCtrl.text.trim(),
              ),
            )
            .where((x) => x.boq.isNotEmpty)
            .toList();

    if (cleaned.isEmpty) {
      for (final r in rows) r.dispose();
      roofAngleCtrl.dispose();
      multiplyingFactorCtrl.dispose();
      depthCtrl.dispose();
      Get.snackbar(
        'Missing BOQ',
        'Pick at least one BOQ code to save.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    // ✅ compute final save value
    final calcBase = _roofCalcBase();
    final mf = _mult();

    final areaUsedBase =
        isRoofCovering ? calcBase.slopeArea : calcBase.planArea;
    final d = asVolume ? _depth() : 0.0;

    final valueBase = asVolume ? (areaUsedBase * d) : areaUsedBase;
    final valueScaled = valueBase * mf;

    final unit = asVolume ? 'm3' : 'm2';
    final measureTypeSaved = asVolume ? 'volume' : 'area';
    final typeSaved = asVolume ? 'volumeMeasure' : 'areaMeasure';

    // ---- Save many docs under same groupId ----
    final sessionId = measurementsRef.doc().id;

    try {
      final batch = FirebaseFirestore.instance.batch();
      final now = FieldValue.serverTimestamp();

      for (final x in cleaned) {
        for (
          var polygonIndex = 0;
          polygonIndex < polygonsToSave.length;
          polygonIndex++
        ) {
          final docRef = measurementsRef.doc();
          final polygonPoints = polygonsToSave[polygonIndex];
          final polyData =
              polygonPoints.map((p) => {'x': p.dx, 'y': p.dy}).toList();
          final ratio =
              totalPolygonAreaPx > 0
                  ? polygonAreasPx[polygonIndex] / totalPolygonAreaPx
                  : 1 / polygonsToSave.length;
          final polygonGroupId = '$sessionId-area-${polygonIndex + 1}';

          batch.set(docRef, {
            'projectId': projectId,
            'buildingId': buildingId,
            'drawingId': drawingId,

            // keep grouping (same for both)
            'areaGroupId': polygonGroupId,
            'areaSessionId': sessionId,
            'areaIndex': polygonIndex,
            'areaCount': polygonsToSave.length,

            'measureType': measureTypeSaved,
            'activeMeasureType':
                (activeMeasureType ?? measureTypeSaved).toString().trim(),
            'type': typeSaved,

            'unit': unit,

            // ✅ value now SAVED as scaled
            'value': valueScaled * ratio,
            'valueBase': valueBase * ratio,
            'multiplyingFactor': mf,

            'areaPx2': polygonAreasPx[polygonIndex],
            'grossAreaM2_one': grossAreaM2 * ratio,
            'deductionAreaM2_allocated': deductionAreaM2 * ratio,
            'netAreaM2_one': areaM2 * ratio,
            'grossAreaM2Total': grossAreaM2,
            'deductionAreaM2Total': deductionAreaM2,
            'netAreaM2Total': areaM2,
            'hasAreaDeductions': deductionPolygons.isNotEmpty,
            'deductionCount': deductionPolygons.length,
            'deductionPolygons': deductionPolygonData,

            // ✅ NEW: volume fields
            'asVolume': asVolume,
            'depthM': asVolume ? d : null,
            'areaUsedM2': areaUsedBase * ratio,
            'areaUsedM2Scaled': areaUsedBase * mf * ratio,
            'volumeM3': asVolume ? (areaUsedBase * d * ratio) : null,
            'volumeM3Scaled': asVolume ? (areaUsedBase * d * mf * ratio) : null,

            // existing roof fields (still useful even if asVolume)
            'isRoofCovering': isRoofCovering,
            'planAreaM2': calcBase.planArea * ratio,
            'roofAngleDeg': calcBase.angleDeg,
            'slopeFactor': calcBase.slopeFactor,
            'slopeAreaM2': calcBase.slopeArea * ratio,
            'planAreaM2Scaled': calcBase.planArea * mf * ratio,
            'slopeAreaM2Scaled': calcBase.slopeArea * mf * ratio,

            'label': x.label.isEmpty ? 'Area item' : x.label,
            'boqCode': x.boq,
            'boqDescription': x.desc,

            'polygon': polyData,
            'color': currentColor.value,

            'createdAt': now,
            'updatedAt': now,
          });
        }
      }

      await batch.commit();

      // ✅ AUTO-REMEMBER: store last template after successful save
      lastAreaTemplate = _buildTemplateFromDialog();

      Get.snackbar(
        'Saved',
        deductionPolygons.isEmpty
            ? 'Saved ${polygonsToSave.length} area(s) for ${cleaned.length} item(s).'
            : 'Saved net area ${areaM2.toStringAsFixed(3)} m² after deducting ${deductionAreaM2.toStringAsFixed(3)} m².',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar('Save failed', '$e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      for (final r in rows) r.dispose();
      roofAngleCtrl.dispose();
      multiplyingFactorCtrl.dispose();
      depthCtrl.dispose();
    }
  }

  Future<void> completeAreaMeasurement({
    required Map<String, dynamic> drawingData,
    required List<Offset> polygon,
  }) async {
    if (polygon.length < 3) return;

    // 1) area in image pixels² (base coords)
    final areaPxBase = _polygonAreaPx(polygon).abs();
    if (areaPxBase <= 0) return;

    // 2) use calibration
    final calibrated = drawingData['calibrated'] == true;
    final pixelsPerUnitBase =
        (drawingData['pixelsPerUnit'] is num)
            ? (drawingData['pixelsPerUnit'] as num).toDouble()
            : double.tryParse('${drawingData['pixelsPerUnit'] ?? ''}') ?? 0.0;

    double? areaM2;
    if (calibrated && pixelsPerUnitBase > 0) {
      final pxPerMeter = pixelsPerUnitBase; // px per 1 m
      final px2PerM2 = pxPerMeter * pxPerMeter; // px² per 1 m²
      areaM2 = areaPxBase / px2PerM2;
    }

    final currentIsDeduction = _nextAreaPolygonIsDeduction;
    _nextAreaPolygonIsDeduction = false;
    final sessionPolygons = <List<Offset>>[
      ..._pendingAreaPolygons.map(List<Offset>.from),
      if (!currentIsDeduction) List<Offset>.from(polygon),
    ];
    final sessionDeductionPolygons = <List<Offset>>[
      ..._pendingAreaDeductionPolygons.map(List<Offset>.from),
      if (currentIsDeduction) List<Offset>.from(polygon),
    ];
    final sessionGrossAreaPx = sessionPolygons.fold<double>(
      0,
      (total, points) => total + _polygonAreaPx(points).abs(),
    );
    final sessionDeductionAreaPx = sessionDeductionPolygons.fold<double>(
      0,
      (total, points) => total + _polygonAreaPx(points).abs(),
    );
    final sessionNetAreaPx = sessionGrossAreaPx - sessionDeductionAreaPx;
    final sessionGrossAreaM2 =
        calibrated && pixelsPerUnitBase > 0
            ? sessionGrossAreaPx / (pixelsPerUnitBase * pixelsPerUnitBase)
            : null;
    final sessionDeductionAreaM2 =
        calibrated && pixelsPerUnitBase > 0
            ? sessionDeductionAreaPx / (pixelsPerUnitBase * pixelsPerUnitBase)
            : null;
    final sessionNetAreaM2 =
        calibrated && pixelsPerUnitBase > 0
            ? sessionNetAreaPx / (pixelsPerUnitBase * pixelsPerUnitBase)
            : null;

    final ctx = Get.context;
    if (ctx == null) {
      if (currentIsDeduction) {
        _pendingAreaPolygons.clear();
        _pendingAreaDeductionPolygons.clear();
        return;
      }

      // No UI context – attempt to save (will refuse if not calibrated)
      await _saveAreaMeasurement(
        polygon: polygon,
        areaPxBase: sessionNetAreaPx,
        areaM2: sessionNetAreaM2,
        polygons: sessionPolygons,
        deductionPolygons: sessionDeductionPolygons,
      );
      _pendingAreaPolygons.clear();
      _pendingAreaDeductionPolygons.clear();
      return;
    }

    // Optional quick confirm (you can remove this and always open the big dialog)
    final rawLabel = (activeLabel ?? '').trim();
    final label = rawLabel.isEmpty ? 'Area measurement' : rawLabel;
    final rawBoq = (activeBoqCode ?? '').trim();
    final boq =
        rawBoq.isEmpty || rawBoq.toLowerCase() == 'null'
            ? 'Not linked'
            : rawBoq;
    const unitDisplay = 'm²';

    final action =
        await Get.dialog<int>(
          AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
            clipBehavior: Clip.antiAlias,
            titlePadding: EdgeInsets.zero,
            contentPadding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
            actionsPadding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
            title: Container(
              padding: const EdgeInsets.fromLTRB(22, 20, 18, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF102A56), Color(0xFF155EEF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(
                      Icons.crop_square_rounded,
                      color: Color(0xFFD6E4FF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Floor area measurement',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Add gross areas and deduct openings or voids',
                          style: TextStyle(
                            color: Color(0xFFD6E4FF),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            content: SizedBox(
              width: 430,
              child:
                  calibrated && areaM2 != null
                      ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFFE4E7EC),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentIsDeduction
                                      ? 'Measured deduction'
                                      : 'Measured area',
                                  style: const TextStyle(
                                    color: Color(0xFF667085),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${areaM2.toStringAsFixed(3)} $unitDisplay',
                                  style: const TextStyle(
                                    color: Color(0xFF101828),
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFBFD2FA),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Gross (${sessionPolygons.length}): ${sessionGrossAreaM2!.toStringAsFixed(3)} m²',
                                  style: const TextStyle(
                                    color: Color(0xFF102A56),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Less deductions (${sessionDeductionPolygons.length}): ${sessionDeductionAreaM2!.toStringAsFixed(3)} m²',
                                  style: const TextStyle(
                                    color: Color(0xFFB42318),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Divider(height: 14),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.functions_rounded,
                                      color: Color(0xFF155EEF),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Net area: ${sessionNetAreaM2!.toStringAsFixed(3)} m²',
                                        style: TextStyle(
                                          color:
                                              sessionNetAreaM2 > 0
                                                  ? const Color(0xFF102A56)
                                                  : const Color(0xFFB42318),
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _AreaConfirmChip(
                                  label: 'Item',
                                  value: label,
                                  icon: Icons.label_outline,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _AreaConfirmChip(
                                  label: 'BOQ',
                                  value: boq,
                                  icon: Icons.receipt_long_outlined,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                      : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Drawing is not calibrated.',
                            style: TextStyle(
                              color: Color(0xFF101828),
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Polygon area: ${areaPxBase.toStringAsFixed(1)} px²',
                            style: const TextStyle(color: Color(0xFF667085)),
                          ),
                        ],
                      ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 0),
                child: const Text('Cancel'),
              ),
              OutlinedButton.icon(
                onPressed:
                    calibrated && areaM2 != null
                        ? () => Navigator.pop(ctx, 1)
                        : null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add another area'),
              ),
              OutlinedButton.icon(
                onPressed:
                    calibrated && areaM2 != null && sessionPolygons.isNotEmpty
                        ? () => Navigator.pop(ctx, 3)
                        : null,
                icon: const Icon(Icons.remove_circle_outline),
                label: const Text('Deduct area'),
              ),
              FilledButton(
                onPressed:
                    calibrated &&
                            sessionNetAreaM2 != null &&
                            sessionNetAreaM2 > 0
                        ? () => Navigator.pop(ctx, 2)
                        : null,
                child: const Text('Finish & Continue'),
              ),
            ],
          ),
        ) ??
        0;

    if (action == 0) {
      _pendingAreaPolygons.clear();
      _pendingAreaDeductionPolygons.clear();
      _nextAreaPolygonIsDeduction = false;
      return;
    }
    if (action == 1 || action == 3) {
      if (currentIsDeduction) {
        _pendingAreaDeductionPolygons.add(List<Offset>.from(polygon));
      } else {
        _pendingAreaPolygons.add(List<Offset>.from(polygon));
      }
      _nextAreaPolygonIsDeduction = action == 3;
      update(['viewer']);
      Get.snackbar(
        action == 3 ? 'Deduction mode' : 'Area mode',
        action == 3
            ? 'Trace the opening or void to subtract from the gross area.'
            : 'Trace the next area to add to the gross total.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    await _saveAreaMeasurement(
      polygon: polygon,
      areaPxBase: sessionNetAreaPx,
      areaM2: sessionNetAreaM2,
      polygons: sessionPolygons,
      deductionPolygons: sessionDeductionPolygons,
    );
    _pendingAreaPolygons.clear();
    _pendingAreaDeductionPolygons.clear();
    _nextAreaPolygonIsDeduction = false;
  }

  Future<void> completeVolumeMeasurement({
    required Map<String, dynamic> drawingData,
    required List<Offset> polygon,
  }) async {
    if (polygon.length < 3) return;

    // 1) area in image pixels² (base coords)
    final areaPxBase = _polygonAreaPx(polygon).abs();
    if (areaPxBase <= 0) return;

    // 2) use calibration
    final calibrated = drawingData['calibrated'] == true;
    final pixelsPerUnitBase =
        (drawingData['pixelsPerUnit'] is num)
            ? (drawingData['pixelsPerUnit'] as num).toDouble()
            : double.tryParse('${drawingData['pixelsPerUnit'] ?? ''}') ?? 0.0;

    double? areaM2;
    if (calibrated && pixelsPerUnitBase > 0) {
      final pxPerMeter = pixelsPerUnitBase; // px per 1 m
      final px2PerM2 = pxPerMeter * pxPerMeter; // px² per 1 m²
      areaM2 = areaPxBase / px2PerM2;
    }

    final ctx = Get.context;
    if (ctx == null) {
      // No UI context – attempt to save (will refuse if not calibrated)
      await _saveVolumeMeasurementFromArea(
        polygon: polygon,
        areaPxBase: areaPxBase,
        areaM2: areaM2,
      );
      return;
    }

    // Optional quick confirm (you can remove this and always open the big dialog)
    final label = activeLabel;
    final boq = activeBoqCode;
    const unitDisplay = 'm²';

    final confirm =
        await Get.dialog<bool>(
          AlertDialog(
            title: const Text('Floor Volume measurement'),
            content:
                calibrated && areaM2 != null
                    ? Text(
                      'Item: $label [$boq]\n'
                      'Area: ${areaM2.toStringAsFixed(3)} $unitDisplay',
                    )
                    : Text(
                      'Drawing not calibrated.\n'
                      'Polygon area (px²): ${areaPxBase.toStringAsFixed(1)}',
                    ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    await _saveVolumeMeasurementFromArea(
      polygon: polygon,
      areaPxBase: areaPxBase,
      areaM2: areaM2,
    );
  }

  VolumeTemplate? lastVolumeTemplate;

  Future<void> _saveVolumeMeasurementFromArea({
    required List<Offset> polygon,
    required double areaPxBase,
    required double? areaM2,
  }) async {
    final ctx = Get.context;

    // ---- must have m2 to save as real measurement ----
    if (areaM2 == null || areaM2 <= 0) {
      if (ctx != null) {
        Get.snackbar(
          'Not calibrated',
          'Cannot save because drawing is not calibrated (area in m² is missing).',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
      return;
    }

    // polygon data for firestore
    final polyData = polygon.map((p) => {'x': p.dx, 'y': p.dy}).toList();

    // ---- rows (multi BOQ) ----
    final rows = <_AreaBoqRow>[
      _AreaBoqRow(
        label: (activeLabel ?? 'Volume').trim(),
        boqCode: (activeBoqCode ?? '').trim(),
        boqDesc: '',
      ),
    ];

    String? errorText;

    // ✅ multiplying factor (default 1)
    final multiplyingFactorCtrl = TextEditingController(text: '1');

    // ✅ depth/thickness in meters (default from last template if you keep it)
    // If you don't have lastVolumeTemplate, keep default like 0.15
    final depthCtrl = TextEditingController(
      text: ((lastVolumeTemplate?.depthM ?? 0.15)).toString(),
    );

    double _d(String s, [double def = 0.0]) => double.tryParse(s.trim()) ?? def;

    double _mult() {
      final v = _d(multiplyingFactorCtrl.text, 1.0);
      if (v.isNaN || v.isInfinite) return 1.0;
      return v <= 0 ? 1.0 : v;
    }

    double _depth() {
      final v = _d(depthCtrl.text, 0.0);
      if (v.isNaN || v.isInfinite) return 0.0;
      return v;
    }

    // returns (area, depth, volume) BASE values (not multiplied)
    ({double areaM2, double depthM, double volumeM3}) _volCalcBase() {
      final a = areaM2!;
      final t = _depth();
      return (areaM2: a, depthM: t, volumeM3: a * t);
    }

    // ✅ build template from dialog state (for remembering)
    // NOTE: You need a simple model like:
    // class VolumeTemplate { final double depthM; final List<AreaBoqTemplateRow> rows; ... }
    VolumeTemplate _buildTemplateFromDialog() {
      final tplRows =
          rows
              .map(
                (r) => AreaBoqTemplateRow(
                  label: r.labelCtrl.text.trim(),
                  boqCode: r.boqCodeCtrl.text.trim(),
                  boqDesc: r.boqDescCtrl.text.trim(),
                ),
              )
              .where((r) => r.boqCode.isNotEmpty)
              .toList();

      return VolumeTemplate(
        depthM: _depth(),
        rows: tplRows,
        // If you want to remember multiplying factor too, add it to VolumeTemplate.
      );
    }

    // ✅ apply previous template into current dialog UI
    void _applyTemplateToDialog(
      VolumeTemplate tpl,
      StateSetter setStateDialog,
    ) {
      for (final r in rows) {
        r.dispose();
      }
      rows.clear();

      if (tpl.rows.isEmpty) {
        rows.add(_AreaBoqRow(label: 'Volume', boqCode: '', boqDesc: ''));
      } else {
        for (final tr in tpl.rows) {
          rows.add(
            _AreaBoqRow(
              label: tr.label,
              boqCode: tr.boqCode,
              boqDesc: tr.boqDesc,
            ),
          );
        }
      }

      depthCtrl.text = tpl.depthM.toString();

      errorText = null;
      setStateDialog(() {});
    }

    final ok =
        await Get.dialog<bool>(
          StatefulBuilder(
            builder: (dCtx, setStateDialog) {
              Future<void> pickForRow(_AreaBoqRow r) async {
                final picked = await it.showBoqPickerDialog(context: dCtx);
                if (picked == null) return;

                final code = (picked.code ?? '').toString().trim();
                final desc = (picked.description ?? '').toString().trim();

                setStateDialog(() {
                  r.boqCodeCtrl.text = code;
                  r.boqDescCtrl.text = desc;

                  final lt = r.labelCtrl.text.trim().toLowerCase();
                  if (r.labelCtrl.text.trim().isEmpty ||
                      lt == 'area' ||
                      lt == 'volume') {
                    r.labelCtrl.text = desc.isNotEmpty ? desc : 'Volume item';
                  }
                });
              }

              final base = _volCalcBase();
              final mf = _mult();

              final volScaled = base.volumeM3 * mf;
              final showScaled = mf != 1.0;

              final canPaste = lastVolumeTemplate != null;

              return AlertDialog(
                title: const Text('Save volume measurement'),
                content: SizedBox(
                  width: 560,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ✅ Paste previous inputs
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (canPaste)
                                OutlinedButton.icon(
                                  onPressed: () {
                                    _applyTemplateToDialog(
                                      lastVolumeTemplate!,
                                      setStateDialog,
                                    );
                                    Get.snackbar(
                                      'Pasted',
                                      'Previous inputs restored.',
                                      snackPosition: SnackPosition.BOTTOM,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.content_paste,
                                    size: 18,
                                  ),
                                  label: const Text('Paste previous inputs'),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Area (base): ${base.areaM2.toStringAsFixed(3)} m²\n'
                            'Depth (base): ${base.depthM.toStringAsFixed(3)} m\n'
                            'Volume (base): ${base.volumeM3.toStringAsFixed(3)} m³'
                            '${showScaled ? '\n\n× ${mf.toStringAsFixed(2)}  →  ${volScaled.toStringAsFixed(3)} m³' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // ✅ depth/thickness
                        TextField(
                          controller: depthCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            labelText: 'Depth / thickness (m) e.g. 0.15',
                            helperText:
                                'Volume = Area × Depth. Enter depth in meters.',
                          ),
                          onChanged:
                              (_) => setStateDialog(() => errorText = null),
                        ),

                        const SizedBox(height: 12),

                        // ✅ multiplying factor
                        TextField(
                          controller: multiplyingFactorCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            labelText:
                                'Multiplying factor (e.g. 2 for 2 identical volumes)',
                            helperText:
                                'Final saved value = (Area × Depth) × multiplying factor.',
                          ),
                          onChanged:
                              (_) => setStateDialog(() => errorText = null),
                        ),

                        const SizedBox(height: 12),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'BOQ mappings (you can add multiple items for the same volume):',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // rows list
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: rows.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final r = rows[i];

                            return Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.black12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: r.labelCtrl,
                                          decoration: const InputDecoration(
                                            labelText:
                                                'Label (e.g. Excavation / Concrete / Hardcore)',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (rows.length > 1)
                                        IconButton(
                                          tooltip: 'Remove',
                                          onPressed: () {
                                            setStateDialog(() {
                                              rows.removeAt(i).dispose();
                                            });
                                          },
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: r.boqCodeCtrl,
                                          readOnly: true,
                                          decoration: const InputDecoration(
                                            labelText: 'BOQ code',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        onPressed: () => pickForRow(r),
                                        icon: const Icon(
                                          Icons.search,
                                          size: 18,
                                        ),
                                        label: const Text('Pick'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: r.boqDescCtrl,
                                    readOnly: true,
                                    maxLines: 2,
                                    decoration: const InputDecoration(
                                      labelText: 'BOQ description',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setStateDialog(() {
                                rows.add(
                                  _AreaBoqRow(
                                    label: '',
                                    boqCode: '',
                                    boqDesc: '',
                                  ),
                                );
                              });
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add another BOQ item'),
                          ),
                        ),

                        if (errorText != null) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              errorText!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Get.back(result: false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final mf = _mult();
                      if (mf <= 0) {
                        setStateDialog(() {
                          errorText =
                              'Multiplying factor must be greater than 0.';
                        });
                        return;
                      }

                      final d = _depth();
                      if (d <= 0) {
                        setStateDialog(() {
                          errorText = 'Depth/thickness must be greater than 0.';
                        });
                        return;
                      }

                      setStateDialog(() => errorText = null);
                      Get.back(result: true);
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ),
          barrierDismissible: false,
        ) ??
        false;

    if (!ok) {
      for (final r in rows) r.dispose();
      depthCtrl.dispose();
      multiplyingFactorCtrl.dispose();
      return;
    }

    // Validate rows: at least 1 has boqCode
    final cleaned =
        rows
            .map(
              (r) => (
                label: r.labelCtrl.text.trim(),
                boq: r.boqCodeCtrl.text.trim(),
                desc: r.boqDescCtrl.text.trim(),
              ),
            )
            .where((x) => x.boq.isNotEmpty)
            .toList();

    if (cleaned.isEmpty) {
      for (final r in rows) r.dispose();
      depthCtrl.dispose();
      multiplyingFactorCtrl.dispose();
      Get.snackbar(
        'Missing BOQ',
        'Pick at least one BOQ code to save.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    // ✅ compute final save value
    final base = _volCalcBase();
    final mf = _mult();

    final valueBase = base.volumeM3; // area*depth
    final valueScaled = valueBase * mf;

    // ---- Save many docs under same volumeGroupId ----
    final volumeGroupId = measurementsRef.doc().id;

    try {
      final batch = FirebaseFirestore.instance.batch();
      final now = FieldValue.serverTimestamp();

      for (final x in cleaned) {
        final docRef = measurementsRef.doc();

        batch.set(docRef, {
          'projectId': projectId,
          'buildingId': buildingId,
          'drawingId': drawingId,

          'volumeGroupId': volumeGroupId,

          'measureType': 'volume',
          'activeMeasureType':
              (activeMeasureType ?? 'volume').toString().trim(),
          'type': 'volumeMeasure',

          'unit': 'm3',

          // ✅ value now SAVED as scaled
          'value': valueScaled,
          'valueBase': valueBase,
          'multiplyingFactor': mf,

          // source geometry
          'areaPx2': areaPxBase,
          'areaM2': base.areaM2,
          'depthM': base.depthM,

          // optional breakdown
          'volumeM3': base.volumeM3,
          'volumeM3Scaled': base.volumeM3 * mf,

          'label': x.label.isEmpty ? 'Volume item' : x.label,
          'boqCode': x.boq,
          'boqDescription': x.desc,

          'polygon': polyData,
          'color': currentColor.value,

          'createdAt': now,
          'updatedAt': now,
        });
      }

      await batch.commit();

      // ✅ AUTO-REMEMBER: store last template after successful save
      lastVolumeTemplate = _buildTemplateFromDialog();

      Get.snackbar(
        'Saved',
        'Saved ${cleaned.length} item(s).',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar('Save failed', '$e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      for (final r in rows) r.dispose();
      depthCtrl.dispose();
      multiplyingFactorCtrl.dispose();
    }
  }

  void zoomIn() {
    zoomBy(1.25);
  }

  void zoomOut() {
    zoomBy(1 / 1.25);
  }

  final Map<String, Map<String, dynamic>> _lastUndoneMeasurements = {};

  Future<void> undoLast() async {
    if (_draftLengthPoints.isNotEmpty || _draftIndependentSegments.isNotEmpty) {
      final removed = undoDraftLengthPoint();
      if (removed) {
        Get.snackbar(
          'Undo',
          hasLengthDraftSession
              ? 'Removed last length point or segment'
              : 'Cancelled current length draft',
        );
      }
      return;
    }

    if (_draftLenP1.value != null || areaPoints.isNotEmpty) {
      _finishLengthChain();
      resetArea();
      Get.snackbar('Undo', 'Cancelled current draft');
      return;
    }

    final snap =
        await measurementsRef
            .where('drawingId', isEqualTo: drawingId)
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();

    if (snap.docs.isEmpty) {
      Get.snackbar('Undo', 'No measurement to undo');
      return;
    }

    final lastDoc = snap.docs.first;
    final lastData = lastDoc.data();
    const groupFields = [
      'assemblyId',
      'plinthGroupId',
      'pavementGroupId',
      'groundPreparationGroupId',
      'finishGroupId',
      'lengthGroupId',
      'areaGroupId',
      'volumeGroupId',
      'wallGroupId',
      'foundationWallId',
      'foundationGroupId',
      'beamId',
      'slabId',
      'slabGroupId',
      'footingGroupId',
      'retainingWallId',
      'stairId',
      'rampId',
      'roofGroupId',
      'ceilingGroupId',
      'tileGroupId',
      'civilWorkId',
    ];

    String? groupField;
    String? groupValue;
    for (final field in groupFields) {
      final value = (lastData[field] ?? '').toString().trim();
      if (value.isNotEmpty) {
        groupField = field;
        groupValue = value;
        break;
      }
    }

    final docs =
        groupField == null
            ? <QueryDocumentSnapshot<Map<String, dynamic>>>[lastDoc]
            : (await measurementsRef
                    .where('drawingId', isEqualTo: drawingId)
                    .where(groupField, isEqualTo: groupValue)
                    .get())
                .docs;

    _lastUndoneMeasurements.clear();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in docs) {
      _lastUndoneMeasurements[doc.id] = Map<String, dynamic>.from(doc.data());
      batch.delete(doc.reference);
    }
    await batch.commit();
    Get.snackbar('Undo', 'Removed the last measurement operation');
  }

  Future<void> redoLast() async {
    if (_lastUndoneMeasurements.isEmpty) {
      Get.snackbar('Redo', 'No measurement to restore');
      return;
    }

    final batch = FirebaseFirestore.instance.batch();
    for (final entry in _lastUndoneMeasurements.entries) {
      batch.set(measurementsRef.doc(entry.key), entry.value);
    }
    await batch.commit();
    _lastUndoneMeasurements.clear();
    Get.snackbar('Redo', 'Restored the measurement operation');
  }

  Future<void> refreshWorkspace() async {
    _finishLengthChain();
    resetArea();
    it.clearCalibrationDraft();
    selectedSegmentId = null;
    setMode(TakeoffMode.view);
    forceResetZoomNextBuild();
    await initImage(imageUrl);
    update(['viewer', 'topbar', 'summary']);
  }

  Future<void> chooseMeasurementColor() async {
    final picked = await _pickColorDialog(initial: currentColor);
    if (picked == null) return;
    currentColor = picked;
    update(['viewer', 'topbar']);
  }

  // ...
  String? currentWallId; // group id for currently drawn retaining wall
  String? boqCode;

  final isRetainingWallActive = false.obs;
  String? retainingWallGroupId;

  bool get isRetainingWallCompositeActive {
    final lower = (activeMeasureType ?? '').trim().toLowerCase();
    return lower == 'compositeretainingwall';
  }

  // final mt = (activeMeasureType ?? '').trim().toLowerCase();

  Future<void> startNewRetainingWallGroupIfNeeded() async {
    if (!isRetainingWallActive.value) return;
    if (retainingWallGroupId != null && retainingWallGroupId!.isNotEmpty) {
      return;
    }
    retainingWallGroupId = measurementsRef.doc().id;
  }

  void resetRetainingWallGroup() {
    currentWallId = null;
    update(['viewer', 'toolbar', 'summary']);
  }

  // --------------------------
  // Computed flags
  // --------------------------
  bool get isWallingActive =>
      (activeMeasureType ?? '').toLowerCase() == 'walling';

  bool get isFootingCompositeActive =>
      (activeMeasureType ?? '').toLowerCase() == 'compositefooting';
  // bool get isSlabCompositeActive =>
  //     (activeMeasureType ?? '').toLowerCase() == 'compositeslab';
  // bool get isBeamCompositeActive =>
  //     (activeMeasureType ?? '').toLowerCase() == 'compositebeam';
  // bool get isColumnCompositeActive =>
  //     (activeMeasureType ?? '').toLowerCase() == 'compositecolumn';

  bool get isRebarSlabActive =>
      (activeMeasureType ?? '').toLowerCase() == 'slabrebar';
  bool get isFootingRebarActive =>
      (activeMeasureType ?? '').toLowerCase() == 'footingrebar';
  bool get isRoofingActive =>
      (activeMeasureType ?? '').toLowerCase() == 'roofing';
  // bool get isCeilingActive =>
  //     (activeMeasureType ?? '').toLowerCase() == 'ceiling';
  bool isBeamCompositeActive = false;
  bool isSlabCompositeActive = false;
  bool isCeilingActive = false;

  void setBeamCompositeActive(bool v) {
    isBeamCompositeActive = v;
    update(['viewer', 'toolbar']);
  }

  bool isColumnCompositeActive = false;
  Offset? beamP1;
  Offset? beamP2;
  // bool isRetainingWallActive = false;

  void setColumnCompositeActive(bool v) {
    isColumnCompositeActive = v;
    update(['viewer', 'toolbar']);
  }

  late final CollectionReference<Map<String, dynamic>> configsRef;

  String? defaultUnitForMeasureType(String? t) {
    switch ((t ?? '').toLowerCase()) {
      case 'walling':
      case 'tiling':
      case 'area':
      case 'pavement':
      case 'ceiling':
      case 'roofsheeting':
        return 'm2';
      case 'volume':
        return 'm3';
      case 'count':
      case 'door':
        return 'nr';
      case 'length':
      case 'pipe':
      case 'beam':
      case 'compositeroofing':
      case 'slabedge':
      case 'cabletray':
        return 'm';
      case 'slabrebar':
      case 'slabrebarai':
      case 'footingrebar':
        return 'kg';
      case 'compositestair':
      case 'liftshaft':
      case 'compositeslab':
      case 'compositefooting':
      case 'civilwork':
      case 'drainage':
      case 'compositeramp':
      case 'compositebeam':
      case 'roofing':
      case 'compositecolumn':
      case 'compositeretainingwall':
      case 'plinth':
      case 'groundpreparation':
        return null; // composite → unit handled by components
      default:
        return null;
    }
  }

  bool _needsHeight(String? t, String? unit) =>
      (t ?? '').toLowerCase() == 'walling' && unit == 'm2';

  bool _canSkipLabelUnit(String? measureType) {
    final t = (measureType ?? '').trim().toLowerCase();
    return t == 'retainingwall' ||
        t == 'compositeretainingwall' ||
        t == 'retainingwallcomposite' ||
        t == 'foundationwall' ||
        t == 'compositefoundationwall' ||
        t == 'retainingwallcomposite' ||
        t == 'compositeramp' ||
        t == 'compositebeam' ||
        t == 'compositestair' ||
        t == 'liftshaft' ||
        t == 'plinth' ||
        t == 'groundpreparation' ||
        t == 'roofing' ||
        t == 'civilwork' ||
        t == 'drainage';
  }

  /// Call this before measuring; ensures you have label/unit/boqCode etc.
  Future<bool> ensureActiveMeasurementItem({
    bool forceConfigure = false,
  }) async {
    String norm(String? v) => (v ?? '').trim().toLowerCase();

    bool isRetaining(String t) =>
        t == 'retainingwall' ||
        t == 'compositeretainingwall' ||
        t == 'retainingwallcomposite' ||
        t == 'compositeRetainingWall'.toLowerCase();
    bool isRoofing(String t) =>
        t == 'roofingcomposite' || t == 'compositeroofing' || t == 'roofing';
    bool isOpenings(String t) =>
        t == 'openings' ||
        t == 'windordoor' ||
        t == 'doorandwindow' ||
        t == 'doorsandwindows'.toLowerCase();
    bool isDoor(String t) => t == 'door' || t == 'compositedoor';
    bool isWindow(String t) => t == 'window' || t == 'compositewindow';
    bool isTrussTemplate(String t) =>
        t == 'trusstemplate' ||
        t == 'truss_template' ||
        t == 'template_truss' ||
        t == 'truss'.toLowerCase();

    bool isFoundation(String t) =>
        t == 'foundationwall' ||
        t == 'compositefoundationwall' ||
        t == 'foundationwallcomposite' ||
        t == 'foundation_wall';
    bool isBeam(String t) => t == 'compositebaem' || t == 'beamcomposite';
    bool isFooting(String t) =>
        t == 'compositefooting' || t == 'footingcomposite';
    bool isSlab(String t) => t == 'compositeslab' || t == 'slabcomposite';
    bool isStair(String t) =>
        t == 'stair' || t == 'compositestair' || t == 'staircomposite';

    bool isRamp(String t) =>
        t == 'ramp' || t == 'compositeramp' || t == 'rampcomposite';

    bool isCivilWork(String t) =>
        t == 'civilwork' || t == 'workcivil' || t == 'civil';

    bool isDialogDrivenComposite(String t) {
      // ✅ These are configured inside their own dialogs (not topbar item dialog)
      if (isRetaining(t) ||
          isFoundation(t) ||
          isStair(t) ||
          isRamp(t) ||
          isSlab(t) ||
          isRoofing(t) ||
          isFooting(t) ||
          isBeam(t) ||
          isOpenings(t) ||
          isDoor(t) ||
          isWindow(t) ||
          isCivilWork(t) ||
          t == 'drainage')
        return true;

      // Optional: include other composites if you don't want to force label/unit/boq
      // (only keep these if your composites already pick BOQs inside their dialogs)
      if (t == 'compositebeam') return true;
      if (t == 'compositeslab') return true;
      if (t == 'compositefooting') return true;
      if (t == 'compositecolumn') return true;
      if (t == 'compositeramp') return true;
      if (t == 'compositestair') return true;
      if (t == 'plinth') return true;
      if (t == 'groundpreparation') return true;
      if (t == 'roofing') return true;
      if (t == 'openings') return true;
      if (t == 'civilwork') return true;

      return false;
    }

    final typeLower = norm(activeMeasureType);

    // If already configured & not forcing reconfigure, exit early
    if (!forceConfigure && isActiveConfigured) return true;

    // Must have a measure type selected (otherwise open dialog)
    final hasType = typeLower.isNotEmpty;
    if (!hasType) {
      final selection = await showMeasurementItemDialog();
      if (selection == null) return false;

      activeLabel = selection.label;
      activeUnit = selection.unit;
      activeBoqCode = selection.boqCode;
      activeHeightM = selection.wallHeightM;
      it.keepPendingFinishSessionForTool(
        drawingId: drawingId,
        measureType: selection.measureType,
      );
      activeMeasureType = selection.measureType;

      _configByType[norm(selection.measureType)] = selection;

      update(['topbar', 'summary', 'preview']);
      return true;
    }

    // ✅ For dialog-driven composites, don't require label/unit/boq/height here
    // They are chosen in the segment dialog (foundation wall dialog, retaining wall dialog, etc.)
    if (isDialogDrivenComposite(typeLower)) {
      // set default unit if you still want a unit for previews (optional)
      if ((activeUnit == null || activeUnit!.trim().isEmpty)) {
        final def = defaultUnitForMeasureType(activeMeasureType);
        if (def != null) activeUnit = def;
      }
      return true;
    }

    // For other measure types, keep your existing validation
    if ((activeUnit == null || activeUnit!.trim().isEmpty) &&
        (activeMeasureType ?? '').trim().isNotEmpty) {
      final def = defaultUnitForMeasureType(activeMeasureType);
      if (def != null) activeUnit = def;
    }

    // If this type can skip label/unit entirely, let it pass
    if (_canSkipLabelUnit(activeMeasureType)) return true;

    final hasLabel = (activeLabel ?? '').trim().isNotEmpty;
    final hasUnit = (activeUnit ?? '').trim().isNotEmpty;
    final hasBoq = (activeBoqCode ?? '').trim().isNotEmpty;

    final needsH = _needsHeight(activeMeasureType, activeUnit);
    final hasH = (activeHeightM ?? 0) > 0;

    if (hasLabel && hasUnit && hasBoq && (!needsH || hasH)) {
      return true;
    }

    final selection = await showMeasurementItemDialog();
    if (selection == null) return false;

    activeLabel = selection.label;
    activeUnit = selection.unit;
    activeBoqCode = selection.boqCode;
    activeHeightM = selection.wallHeightM;
    it.keepPendingFinishSessionForTool(
      drawingId: drawingId,
      measureType: selection.measureType,
    );
    activeMeasureType = selection.measureType;

    _configByType[norm(selection.measureType)] = selection;

    update(['topbar', 'summary', 'preview']);
    return true;
  }

  Future<MeasurementItemSelection?> showMeasurementItemDialog() async {
    final context = Get.context;
    if (context == null) return null;

    const labelOptions = <String>[
      'Walling',
      'Ramp composite',
      'Roof composite',
      'Stair composite',
      'Lift shaft',
      'Civil works',
      'Footing composite',
      'Slab composite',
      'Slab reinforcement (AI)',
      'Beam composite',
      'Ceiling',
      'Truss Template',
      'Roof sheeting',
      'Column composite',
      'Openings',
      'Retaining wall composite',
      'Foundation wall composite', // ✅ ADD
      'Other',
    ];

    const unitOptions = <String>[
      'm',
      'm2',
      'm3',
      'item',
      'kg',
      'ps',
      'tonne',
      'Nos',
      'Pair',
    ];

    String selectedLabel =
        (activeLabel != null && labelOptions.contains(activeLabel))
            ? activeLabel!
            : labelOptions.first;

    String selectedUnit = (activeUnit ?? 'm');

    bool isCompositeLabel(String label) =>
        label.toLowerCase().contains('composite');

    bool isFoundationCompositeLabel(String label) =>
        label.toLowerCase().contains('foundation') &&
        label.toLowerCase().contains('composite');
    bool isOpenings(String label) =>
        label.toLowerCase().contains('openings') &&
        label.toLowerCase().contains('door') &&
        label.toLowerCase().contains('window');

    bool isRetainingCompositeLabel(String label) =>
        label.toLowerCase().contains('retaining') &&
        label.toLowerCase().contains('composite');
    bool isCeilingLabel(String label) =>
        label.toLowerCase().contains('ceiling') &&
        label.toLowerCase().contains('composite');
    bool isRampCompositeLabel(String label) =>
        label.toLowerCase().contains('ramp') &&
        label.toLowerCase().contains('composite');
    bool isStairsCompositeLabel(String label) =>
        label.toLowerCase().contains('stair') &&
        label.toLowerCase().contains('composite');
    bool isBeamCompositeLabel(String label) =>
        label.toLowerCase().contains('beam') &&
        label.toLowerCase().contains('composite');
    // bool isRoofingCompositeLabel(String label) =>
    //     label.toLowerCase().contains('roof') &&
    //     label.toLowerCase().contains('composite');

    // ✅ Auto unit rules
    void applyAutoUnitRules(String label) {
      if (label.toLowerCase().contains('slab reinforcement')) {
        selectedUnit = 'kg';
        return;
      }

      // Line-based composites should default to meters
      if (isFoundationCompositeLabel(label) ||
          isRetainingCompositeLabel(label) ||
          isRampCompositeLabel(label) ||
          isStairsCompositeLabel(label) ||
          isBeamCompositeLabel(label)) {
        selectedUnit = 'm';
        return;
      }

      // Other composites can keep user's current unit (do nothing)
    }

    // Apply once at init
    applyAutoUnitRules(selectedLabel);

    final customLabelController = TextEditingController(
      text:
          (activeLabel != null && !labelOptions.contains(activeLabel))
              ? activeLabel!
              : '',
    );

    final heightController = TextEditingController(
      text: activeHeightM != null ? activeHeightM.toString() : '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            String displayUnit(String u) =>
                u == 'm2' ? 'm²' : (u == 'm3' ? 'm³' : u);

            final labelLower = selectedLabel.toLowerCase();

            // ✅ Height only for Walling (NOT for composites)
            final isWalling = selectedLabel == 'Walling';
            final showHeight = (selectedUnit == 'm2') && isWalling;

            void onLabelChanged(String v) {
              setStateDialog(() {
                selectedLabel = v;
                applyAutoUnitRules(v);
              });
            }

            return AlertDialog(
              title: const Text('Measuring item'),
              content: SizedBox(
                width: double.maxFinite,
                height: math.min(MediaQuery.of(ctx).size.height * 0.70, 520),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    const Text(
                      'Item type:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),

                    ...labelOptions.map(
                      (opt) => RadioListTile<String>(
                        title: Text(opt),
                        value: opt,
                        groupValue: selectedLabel,
                        onChanged: (v) {
                          if (v == null) return;
                          onLabelChanged(v);
                        },
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),

                    if (selectedLabel == 'Other') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: customLabelController,
                        decoration: const InputDecoration(
                          labelText: 'Custom label (e.g. Boundary wall)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    const Text(
                      'Unit:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),

                    DropdownButtonFormField<String>(
                      value: selectedUnit,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items:
                          unitOptions
                              .map(
                                (u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(displayUnit(u)),
                                ),
                              )
                              .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setStateDialog(() => selectedUnit = v);
                      },
                    ),

                    // ✅ Only for Walling @ m²
                    if (showHeight) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Wall height (h, m):',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: heightController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Height in meters (e.g. 3.0)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],

                    // Optional helper text for composites
                    if (isCompositeLabel(selectedLabel)) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Note: Composite items are configured inside their own segment dialog.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Use'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) return null;

    String finalLabel =
        selectedLabel == 'Other'
            ? customLabelController.text.trim()
            : selectedLabel;

    if (finalLabel.isEmpty) return null;

    // ✅ Height validation only for Walling m²
    double? wallH;
    if (selectedUnit == 'm2' && finalLabel == 'Walling') {
      final hVal = double.tryParse(heightController.text.trim());
      if (hVal == null || hVal <= 0) return null;
      wallH = hVal;
    }

    // ✅ You can keep your existing infer method, but we should ensure it maps:
    // "Foundation wall composite" -> "foundationWallComposite" (or "compositeFoundationWall")
    // "Retaining wall composite"  -> "compositeRetainingWall"
    final measureType = inferMeasureTypeFromLabel(finalLabel);

    return MeasurementItemSelection(
      label: finalLabel,
      unit: selectedUnit,
      wallHeightM: wallH,
      measureType: measureType,
    );
  }

  Future<void> saveMeasurement({
    required Offset p1,
    required Offset p2,
    required double? lengthMeters,
    double? overrideHeightM,
  }) async {
    if ((activeMeasureType ?? '').trim().isEmpty) {
      Get.snackbar('Missing', 'Select measuring type first.');
      return;
    }

    final unit = activeUnit ?? 'm';
    final walling = isWallingActive;

    double? quantity;
    double? heightForThis;

    if (lengthMeters == null || lengthMeters <= 0) {
      Get.snackbar('Calibration', 'Drawing not calibrated (length is null).');
      return;
    }

    // if (lengthMeters != null) {
    switch (unit) {
      case 'm':
        quantity = lengthMeters;
        break;

      case 'm2':
        if (walling) {
          heightForThis = overrideHeightM ?? activeHeightM;
          if ((heightForThis ?? 0) <= 0) {
            Get.snackbar('Height required', 'Enter wall height (m).');
            return;
          }
          quantity = lengthMeters * heightForThis!;
        } else {
          quantity = lengthMeters;
        }
        break;

      case 'item':
      case 'ps':
        quantity = 1.0;
        break;

      default:
        quantity = lengthMeters;
        break;
    }
    switch (unit) {
      case 'm':
        quantity = lengthMeters;
        break;

      case 'm2':
        if (walling) {
          heightForThis = overrideHeightM ?? activeHeightM;
          if ((heightForThis ?? 0) <= 0) {
            Get.snackbar('Height required', 'Enter wall height (m).');
            return;
          }
          quantity = lengthMeters * heightForThis!;
        } else {
          quantity = lengthMeters;
        }
        break;

      case 'item':
      case 'ps':
        quantity = 1.0;
        break;

      default:
        quantity = lengthMeters;
        break;
    }
    // }

    // if (quantity == null) return;
    //
    await measurementsRef.add({
      'projectId': projectId,
      'buildingId': buildingId,
      'drawingId': drawingId,
      'type': 'length',
      'measureType':
          activeMeasureType ?? inferMeasureTypeFromLabel(activeLabel ?? ''),
      'unit': unit,
      'value': quantity,
      'baseLengthM': lengthMeters,
      'heightM': heightForThis,
      'label': activeLabel,
      'boqCode': activeBoqCode,
      'color': currentColor.value,
      'p1': {'x': p1.dx, 'y': p1.dy},
      'p2': {'x': p2.dx, 'y': p2.dy},
      'createdAt': FieldValue.serverTimestamp(),
    });
    Get.snackbar('Saved', 'Measurement saved.');
  }

  final Rxn<Offset> _draftLenP1 = Rxn<Offset>();
  final Rxn<Offset> _draftLenP2 = Rxn<Offset>();
  String? _lengthChainGroupId;
  int _lengthChainSegmentIndex = 0;
  BoqPick? _roofChainBoq;
  BoqPick? _lastRoofBoq;
  Map<String, dynamic>? _roofChainSessionDefaults;
  Map<String, dynamic>? _lastRoofSessionDefaults;
  BoqPick? _timberRoofChainBoq;
  BoqPick? _lastTimberRoofBoq;
  Map<String, dynamic>? _timberRoofChainSessionDefaults;
  Map<String, dynamic>? _lastTimberRoofSessionDefaults;
  final Map<String, BoqPick> _lastTimberRoofBoqByMember = <String, BoqPick>{};
  final List<BoqPick> _recentTimberRoofBoqs = <BoqPick>[];

  // Current unsaved timber truss. Members are kept only in memory until the
  // user explicitly presses Save truss. This makes member-to-member take-off
  // instant and turns the database operation into one batch commit.
  final List<Map<String, dynamic>> _pendingTimberTrussMembers =
      <Map<String, dynamic>>[];
  String? _pendingTimberTrussId;
  bool _savingPendingTimberTruss = false;

  List<Map<String, dynamic>> get pendingTimberTrussMembers =>
      List<Map<String, dynamic>>.unmodifiable(_pendingTimberTrussMembers);
  int get pendingTimberTrussMemberCount => _pendingTimberTrussMembers.length;
  bool get hasPendingTimberTruss => _pendingTimberTrussMembers.isNotEmpty;
  bool get savingPendingTimberTruss => _savingPendingTimberTruss;

  void _addPendingTimberTrussMember(Map<String, dynamic>? member) {
    if (member == null || member.isEmpty) return;
    _pendingTimberTrussId ??= measurementsRef.doc().id;
    final payload = Map<String, dynamic>.from(member);
    payload['draftId'] = measurementsRef.doc().id;
    payload['trussId'] = _pendingTimberTrussId;
    payload['isDraft'] = true;
    _pendingTimberTrussMembers.add(payload);
    update(['overlayVisibility', 'overlay', 'viewer', 'summary']);
  }

  Future<bool> savePendingTimberTruss({String? trussMark}) async {
    if (_pendingTimberTrussMembers.isEmpty || _savingPendingTimberTruss) {
      return false;
    }
    _savingPendingTimberTruss = true;
    update(['summary']);
    try {
      final trussId = _pendingTimberTrussId ?? measurementsRef.doc().id;
      final batch = FirebaseFirestore.instance.batch();
      for (var i = 0; i < _pendingTimberTrussMembers.length; i++) {
        final member = Map<String, dynamic>.from(_pendingTimberTrussMembers[i]);
        member.remove('draftId');
        member.remove('isDraft');
        member['trussId'] = trussId;
        member['trussMark'] = (trussMark ?? '').trim();
        member['trussMemberIndex'] = i;
        member['createdAt'] = FieldValue.serverTimestamp();
        member['updatedAt'] = FieldValue.serverTimestamp();
        batch.set(measurementsRef.doc(), member);
      }
      await batch.commit();
      final count = _pendingTimberTrussMembers.length;
      _pendingTimberTrussMembers.clear();
      _pendingTimberTrussId = null;
      update(['overlayVisibility', 'overlay', 'viewer', 'summary']);
      Get.snackbar(
        'Truss saved',
        '$count timber member${count == 1 ? '' : 's'} committed together.',
      );
      return true;
    } catch (e) {
      Get.snackbar('Save truss failed', '$e');
      return false;
    } finally {
      _savingPendingTimberTruss = false;
      update(['summary']);
    }
  }

  void discardPendingTimberTruss() {
    if (_pendingTimberTrussMembers.isEmpty) return;
    _pendingTimberTrussMembers.clear();
    _pendingTimberTrussId = null;
    update(['overlayVisibility', 'overlay', 'viewer', 'summary']);
  }

  void _rememberTimberRoofBoq(String? memberType, BoqPick? boq) {
    if (boq == null) return;
    final key = memberType?.trim() ?? '';
    if (key.isNotEmpty) _lastTimberRoofBoqByMember[key] = boq;

    _recentTimberRoofBoqs.removeWhere((item) {
      if (boq.id.trim().isNotEmpty && item.id.trim().isNotEmpty) {
        return item.id.trim() == boq.id.trim();
      }
      return item.code.trim() == boq.code.trim() &&
          item.description.trim() == boq.description.trim();
    });
    _recentTimberRoofBoqs.insert(0, boq);
    if (_recentTimberRoofBoqs.length > 8) {
      _recentTimberRoofBoqs.removeRange(8, _recentTimberRoofBoqs.length);
    }
  }

  final List<Offset> _draftCountPoints = <Offset>[];
  String? _countGroupId;
  List<Map<String, String>> _lastCountRows = <Map<String, String>>[];
  String _countMark = 'tick';
  Map<String, dynamic> _lastDoorScheduleDefaults = <String, dynamic>{};
  // Door take-off may be minimized and continued on another drawing. These
  // static values intentionally survive controller disposal while navigating
  // between drawings in the same app session.
  static Map<String, dynamic> _sharedDoorScheduleDefaults = <String, dynamic>{};
  static final List<Map<String, dynamic>> _sharedDoorCountChunks =
      <Map<String, dynamic>>[];
  static String? _sharedDoorSessionScope;
  static String? _sharedDoorSessionId;
  Map<String, dynamic> _lastWindowScheduleDefaults = <String, dynamic>{};

  Offset? get draftLenP1 => _draftLenP1.value;
  Offset? get draftLenP2 => _draftLenP2.value;
  final List<Offset> _draftLengthPoints = <Offset>[];
  final List<LengthDraftSegment> _draftIndependentSegments =
      <LengthDraftSegment>[];
  final List<_PendingKerbChain> _pendingKerbChains = <_PendingKerbChain>[];
  BoqPick? _pendingKerbBoq;
  String _pendingKerbType = 'Prefabricated semi-mountable Concrete Kerb Type 1';
  String? _kerbSessionId;
  final List<_PendingDrainChain> _pendingDrainChains = <_PendingDrainChain>[];
  String? _drainSessionId;
  String _pendingDrainType = 'Open lined drain';
  String _pendingDrainProfile = 'Open Lined Drain Type 1 - 500mm invert';
  final Map<String, BoqPick> _pendingDrainBoqs = <String, BoqPick>{};
  // Remember BOQ mappings by drainage profile for the lifetime of this drawing
  // controller so repeated drains rarely need the picker again.
  final Map<String, Map<String, BoqPick>> _lastDrainBoqsByProfile =
      <String, Map<String, BoqPick>>{};
  Map<String, double> _pendingDrainParams = <String, double>{};

  String _drainBoqProfileKey(String type, String profile) => '$type::$profile';

  List<List<Offset>> get pendingDrainSegmentPairs => _pendingDrainChains
      .expand((chain) => chain.segments)
      .map((segment) => <Offset>[segment.p1, segment.p2])
      .toList(growable: false);

  List<List<Offset>> get pendingKerbSegmentPairs => _pendingKerbChains
      .expand((chain) => chain.segments)
      .map((segment) => <Offset>[segment.p1, segment.p2])
      .toList(growable: false);

  WallLengthCaptureStyle wallLengthCaptureStyle =
      WallLengthCaptureStyle.continuous;
  final List<Offset> polyWorld = [];

  List<Offset> get draftLengthPoints => List.unmodifiable(_draftLengthPoints);
  List<List<Offset>> get draftIndependentSegmentPairs =>
      _draftIndependentSegments
          .map((segment) => <Offset>[segment.p1, segment.p2])
          .toList(growable: false);
  List<Offset> get draftCountPoints => List.unmodifiable(_draftCountPoints);
  String get draftCountLabelPrefix =>
      it.isCountingFastSlabRebarBundles
          ? it.pendingFastSlabRebarBundleMark
          : '';

  bool get hasContinuousLengthDraft =>
      _draftLengthPoints.length >= 2 || _draftIndependentSegments.isNotEmpty;
  bool get canFinishLengthDraft =>
      hasContinuousLengthDraft &&
      !(wallLengthCaptureStyle == WallLengthCaptureStyle.segments &&
          _draftLenP1.value != null) &&
      !(wallLengthCaptureStyle == WallLengthCaptureStyle.continuous &&
          _draftLengthPoints.length == 1);
  bool get hasLengthDraftSession =>
      _draftLenP1.value != null ||
      _draftLengthPoints.isNotEmpty ||
      _draftIndependentSegments.isNotEmpty;
  bool get isWallMeasurementActive =>
      _isWallType(_lowerType(activeMeasureType));
  String get lengthDraftFinishLabel {
    final lower = _lowerType(activeMeasureType);
    if (_isWallType(lower)) return 'Next: wall details';
    if (_isBeamType(lower)) return 'Next: beam details';
    if (_isFoundationType(lower)) return 'Next: foundation wall details';
    if (_isTimberRoofStructureType(lower)) return 'Next: timber details';
    if (_isTrussType(lower)) return 'Next: steel roof details';
    if (_isRoadProfileType(lower)) return 'Next: road profile details';
    if (_isCivilworkType(lower)) return 'Next: kerbstone details';
    if (_isDrainageType(lower)) return 'Next: drainage details';
    return 'Next: details';
  }

  bool get supportsLengthCaptureStyle {
    final lower = _lowerType(activeMeasureType);
    return _isWallType(lower) ||
        lower == 'length' ||
        _isCivilworkType(lower) ||
        _isRoadProfileType(lower) ||
        _isDrainageType(lower) ||
        _isBeamType(lower) ||
        _isFoundationType(lower) ||
        _isTimberRoofStructureType(lower) ||
        _isTrussType(lower) ||
        lower == 'slabrebarai';
  }

  bool get hasCountDraft => _draftCountPoints.isNotEmpty;
  int get draftCountTotal => _draftCountPoints.length;

  int get draftLengthSegmentCount =>
      wallLengthCaptureStyle == WallLengthCaptureStyle.segments
          ? _draftIndependentSegments.length
          : _draftIndependentSegments.length +
              (_draftLengthPoints.length > 1
                  ? _draftLengthPoints.length - 1
                  : 0);

  double draftLengthTotalMeters(Map<String, dynamic> drawingData) {
    if (wallLengthCaptureStyle == WallLengthCaptureStyle.segments) {
      return _draftIndependentSegments.fold<double>(
        0,
        (total, segment) => total + segment.lengthM,
      );
    }
    double total = _draftIndependentSegments.fold<double>(
      0,
      (sum, segment) => sum + segment.lengthM,
    );
    for (var i = 0; i < _draftLengthPoints.length - 1; i++) {
      final len = distanceInMeters(
        _draftLengthPoints[i],
        _draftLengthPoints[i + 1],
        drawingData,
      );
      if (len > 0) total += len;
    }
    return total;
  }

  onPanUpdate(details) {
    final world = toWorld(
      local: details.localPosition,
      tCtrl: transformController,
    );
    polyWorld.add(world);
  }

  bool get hasDraftLength =>
      _draftLenP1.value != null && _draftLenP2.value != null;

  void startDraftLength(Offset p) {
    _draftLenP1.value = p;
    _draftLenP2.value = p;
    update(['overlay', 'viewer']); // your overlay GetBuilder id
  }

  void updateDraftLength(Offset p) {
    _draftLenP2.value = p;
    update(['overlay', 'viewer']);
  }

  void clearDraftLength() {
    _draftLenP1.value = null;
    _draftLenP2.value = null;
    _draftLengthPoints.clear();
    _draftIndependentSegments.clear();
    wallLengthCaptureStyle = WallLengthCaptureStyle.continuous;
    update(['overlayVisibility', 'overlay', 'viewer', 'summary']);
  }

  void clearDraftCount() {
    _draftCountPoints.clear();
    _countGroupId = null;
    if (it.isCountingFastSlabRebarBundles) {
      it.cancelFastSlabRebarBundleCount();
    }
    update(['overlay', 'viewer', 'summary']);
  }

  bool undoDraftCountPoint() {
    if (_draftCountPoints.isEmpty) return false;
    _draftCountPoints.removeLast();
    update(['overlay', 'viewer', 'summary']);
    return true;
  }

  void _handleCountTap(Offset imagePos) {
    _countGroupId ??= measurementsRef.doc().id;
    _draftCountPoints.add(imagePos);
    update(['overlay', 'viewer', 'summary']);
  }

  void _startContinuousLengthDraft(Offset p) {
    _draftLengthPoints
      ..clear()
      ..add(p);
    _draftLenP1.value = p;
    _draftLenP2.value = p;
    update(['overlay', 'viewer']);
  }

  bool undoDraftLengthPoint() {
    if (wallLengthCaptureStyle == WallLengthCaptureStyle.segments) {
      if (_draftLenP1.value != null) {
        _draftLenP1.value = null;
        _draftLenP2.value = null;
      } else if (_draftIndependentSegments.isNotEmpty) {
        _draftIndependentSegments.removeLast();
      } else {
        return false;
      }
      update(['overlay', 'viewer', 'summary']);
      return true;
    }
    if (_draftLengthPoints.isNotEmpty) {
      _draftLengthPoints.removeLast();
      if (_draftLengthPoints.isEmpty) {
        _draftLenP1.value = null;
        _draftLenP2.value = null;
      } else {
        final last = _draftLengthPoints.last;
        _draftLenP1.value = last;
        _draftLenP2.value = last;
      }
      update(['overlay', 'viewer', 'summary']);
      return true;
    }
    if (_draftIndependentSegments.isNotEmpty) {
      _draftIndependentSegments.removeLast();
      update(['overlay', 'viewer', 'summary']);
      return true;
    }
    return false;
  }

  List<LengthDraftSegment> _buildCurrentContinuousLengthSegments(
    Map<String, dynamic> drawingData,
  ) {
    final segments = <LengthDraftSegment>[];
    for (var i = 0; i < _draftLengthPoints.length - 1; i++) {
      final p1 = _draftLengthPoints[i];
      final p2 = _draftLengthPoints[i + 1];
      final dx = p2.dx - p1.dx;
      final dy = p2.dy - p1.dy;
      final lengthPx = math.sqrt(dx * dx + dy * dy);
      final lengthM = distanceInMeters(p1, p2, drawingData);
      if (lengthPx <= 0 || lengthM <= 0) continue;
      segments.add(
        LengthDraftSegment(
          p1: p1,
          p2: p2,
          lengthM: lengthM,
          lengthPx: lengthPx,
        ),
      );
    }
    return segments;
  }

  bool startAnotherLengthSegment(Map<String, dynamic> drawingData) {
    final currentSegments = _buildCurrentContinuousLengthSegments(drawingData);
    if (currentSegments.isEmpty && _draftIndependentSegments.isEmpty) {
      return false;
    }

    _draftIndependentSegments.addAll(currentSegments);
    _draftLengthPoints.clear();
    _draftLenP1.value = null;
    _draftLenP2.value = null;
    wallLengthCaptureStyle = WallLengthCaptureStyle.continuous;
    update(['overlay', 'viewer', 'summary']);
    return true;
  }

  List<LengthDraftSegment>? _buildDraftLengthSegments(
    Map<String, dynamic> drawingData,
  ) {
    if (wallLengthCaptureStyle == WallLengthCaptureStyle.segments) {
      return _draftIndependentSegments.isEmpty
          ? null
          : List<LengthDraftSegment>.from(_draftIndependentSegments);
    }
    final segments = List<LengthDraftSegment>.from(_draftIndependentSegments)
      ..addAll(_buildCurrentContinuousLengthSegments(drawingData));
    return segments.isEmpty ? null : segments;
  }

  void setWallLengthCaptureStyle(WallLengthCaptureStyle style) {
    if (wallLengthCaptureStyle == style) return;
    final anchor = _draftLenP1.value;
    _draftLengthPoints.clear();
    _draftIndependentSegments.clear();
    wallLengthCaptureStyle = style;
    if (anchor != null) {
      _draftLenP1.value = anchor;
      _draftLenP2.value = anchor;
      if (style == WallLengthCaptureStyle.continuous) {
        _draftLengthPoints.add(anchor);
      }
    }
    update(['overlay', 'viewer', 'summary']);
  }

  Future<void> chooseWallLengthCaptureStyle(
    WallLengthCaptureStyle style,
  ) async {
    if (wallLengthCaptureStyle == style) return;
    if (draftLengthSegmentCount > 0) {
      final shouldChange = await Get.dialog<bool>(
        AlertDialog(
          title: const Text('Change measuring mode?'),
          content: const Text(
            'Changing the mode will clear the current temporary measurement group.',
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('Keep current'),
            ),
            FilledButton(
              onPressed: () => Get.back(result: true),
              child: const Text('Change mode'),
            ),
          ],
        ),
        barrierDismissible: false,
      );
      if (shouldChange != true) return;
      clearDraftLength();
      wallLengthCaptureStyle = style;
      update(['overlay', 'viewer', 'summary']);
      return;
    }
    setWallLengthCaptureStyle(style);
  }

  Future<void> finishContinuousLengthMeasurement(
    Map<String, dynamic> drawingData,
  ) async {
    final lower = _lowerType(activeMeasureType);
    if (_isWallType(lower)) {
      await finishContinuousWallMeasurement(drawingData);
      return;
    }

    final draftSegments = _buildDraftLengthSegments(drawingData);
    if (draftSegments == null || draftSegments.isEmpty) {
      Get.snackbar(
        'Length',
        'Tap at least two points before saving.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    if (lower == 'slabrebarai') {
      final totalLengthM = draftSegments.fold<double>(
        0.0,
        (total, segment) => total + segment.lengthM,
      );
      final geometrySegments = draftSegments
          .map(
            (segment) => <String, dynamic>{
              'p1': {'x': segment.p1.dx, 'y': segment.p1.dy},
              'p2': {'x': segment.p2.dx, 'y': segment.p2.dy},
              'lengthM': segment.lengthM,
            },
          )
          .toList(growable: false);
      final action = await it.saveFastSlabRebarLength(
        p1: draftSegments.first.p1,
        p2: draftSegments.last.p2,
        measuredLengthM: totalLengthM,
        geometrySegments: geometrySegments,
        captureStyle:
            wallLengthCaptureStyle == WallLengthCaptureStyle.segments
                ? 'segments'
                : 'continuous',
      );
      clearDraftLength();
      if (action == SlabRebarLengthSaveAction.countBundles) {
        _draftCountPoints.clear();
        _countGroupId = null;
        setMode(TakeoffMode.measureLength);
        Get.snackbar(
          'Count related bundles',
          'Tap every related bundle for bar ${it.pendingFastSlabRebarBundleMark}. Each tap will be labelled on the drawing.',
          snackPosition: SnackPosition.BOTTOM,
        );
      } else if (action == SlabRebarLengthSaveAction.measureAnother) {
        setMode(TakeoffMode.measureLength);
        Get.snackbar(
          'Measure another rebar',
          wallLengthCaptureStyle == WallLengthCaptureStyle.segments
              ? 'Tap start and end for each segment, then press Next: details.'
              : 'Tap the start, then every bend or turn point, then press Next: details.',
          snackPosition: SnackPosition.BOTTOM,
        );
      } else if (action == SlabRebarLengthSaveAction.finish) {
        setMode(TakeoffMode.view);
      }
      update(['toolbar', 'topbar', 'overlay', 'viewer', 'summary']);
      return;
    }

    if (_isBeamType(lower)) {
      final totalLengthM = draftSegments.fold<double>(
        0,
        (total, segment) => total + segment.lengthM,
      );
      final action = await it.openBeamCompositeDialog(
        p1: draftSegments.first.p1,
        p2: draftSegments.last.p2,
        drawingData: drawingData,
        activeLabel: activeLabel,
        baseLengthM: totalLengthM,
        polylineSegments: draftSegments
            .map(
              (segment) => <String, dynamic>{
                'p1': {'x': segment.p1.dx, 'y': segment.p1.dy},
                'p2': {'x': segment.p2.dx, 'y': segment.p2.dy},
                'lengthM': segment.lengthM,
              },
            )
            .toList(growable: false),
      );
      if (action == BeamSaveAction.cancel) return;
      clearDraftLength();
      update(['overlay', 'viewer', 'summary']);
      return;
    }

    if (_isFoundationType(lower)) {
      final totalLengthM = draftSegments.fold<double>(
        0,
        (total, segment) => total + segment.lengthM,
      );
      final action = await it.openFoundationWallSegmentDialog(
        p1: draftSegments.first.p1,
        p2: draftSegments.last.p2,
        drawingData: drawingData,
        measuredLengthM: totalLengthM,
        polylineSegments: draftSegments
            .map(
              (segment) => <String, dynamic>{
                'p1': {'x': segment.p1.dx, 'y': segment.p1.dy},
                'p2': {'x': segment.p2.dx, 'y': segment.p2.dy},
                'lengthM': segment.lengthM,
              },
            )
            .toList(growable: false),
        wallGroupId: currentWallId,
      );
      if (action == FoundationSaveAction.cancel) return;
      clearDraftLength();
      update(['overlay', 'viewer', 'summary']);
      return;
    }

    if (_isTimberRoofStructureType(lower) || _isTrussType(lower)) {
      await _finishRoofMemberDrafts(
        drawingData: drawingData,
        segments: draftSegments,
        timber: _isTimberRoofStructureType(lower),
      );
      return;
    }

    if (_isRoadProfileType(lower)) {
      await _finishRoadProfileTakeoff(draftSegments);
      return;
    }

    if (_isDrainageType(lower)) {
      await _finishDrainageTakeoff(draftSegments);
      return;
    }

    if (_isCivilworkType(lower)) {
      await _finishKerbChainTakeoff(draftSegments);
      return;
    }

    _lengthChainGroupId ??= measurementsRef.doc().id;
    final action = await completeLengthMeasurementTap(
      drawingData: drawingData,
      p1: draftSegments.first.p1,
      p2: draftSegments.last.p2,
      draftSegments: draftSegments,
      lengthGroupId: _lengthChainGroupId,
      chainSegmentIndex: 0,
    );

    if (action == LenDialogAction.cont) {
      final nextStart = draftSegments.last.p2;
      _lengthChainGroupId = measurementsRef.doc().id;
      _lengthChainSegmentIndex = 0;
      _draftLengthPoints
        ..clear()
        ..add(nextStart);
      _draftLenP1.value = nextStart;
      _draftLenP2.value = nextStart;
      update(['overlay', 'viewer', 'summary']);
      return;
    }

    _finishLengthChain();
    update(['overlay', 'viewer', 'summary']);
  }

  Future<void> _finishRoadProfileTakeoff(
    List<LengthDraftSegment> currentSegments,
  ) async {
    final context = Get.context;
    if (context == null || currentSegments.isEmpty) return;

    final totalLengthM = currentSegments.fold<double>(
      0.0,
      (sum, segment) => sum + segment.lengthM,
    );

    const profiles = <String, Map<String, double>>{
      'Tabora Bing Road': {'widthM': 6.5},
      'Entrance Bus Terminal': {'widthM': 6.5},
      'Daladala Stand': {'widthM': 6.0},
      'Custom': {'widthM': 6.5},
    };

    var profile = 'Tabora Bing Road';
    var asphaltGrade = 'AC14';
    var includeClearing = true;
    var includeTopsoil = true;
    var includeCommonExc = false;
    var includeFill = true;
    var includeAc14 = true;
    var includeBitumenBinder = true;
    var includeCrrBase = true;
    var includeMc30PrimeCoat = true;
    var includeMc30CuringMembrane = false;
    var includeC1Subbase = true;
    var includeG15UpperSubgrade = false;
    var includeG7LowerSubgrade = false;
    var includeCementStabiliser = false;
    final widthCtrl = TextEditingController(text: '6.5');
    final pavementWidthCtrl = TextEditingController(text: '6.5');
    final clearingWidthCtrl = TextEditingController(text: '6.5');
    final topsoilCtrl = TextEditingController(text: '150');
    final commonExcCtrl = TextEditingController(text: '0');
    final fillDepthCtrl = TextEditingController(text: '200');
    final ac14ThicknessCtrl = TextEditingController(text: '50');
    final asphaltDensityCtrl = TextEditingController(text: '2.35');
    final bitumenContentCtrl = TextEditingController(text: '5.0');
    final crrBaseThicknessCtrl = TextEditingController(text: '150');
    final mc30PrimeRateCtrl = TextEditingController(text: '1.0');
    final mc30CuringRateCtrl = TextEditingController(text: '1.0');
    final c1SubbaseThicknessCtrl = TextEditingController(text: '200');
    final g15UpperThicknessCtrl = TextEditingController(text: '150');
    final g7LowerThicknessCtrl = TextEditingController(text: '150');
    final stabilisedDepthCtrl = TextEditingController(text: '150');
    final stabilisedDryDensityCtrl = TextEditingController(text: '2.0');
    final cementContentCtrl = TextEditingController(text: '4.0');
    final boqs = <String, BoqPick?>{
      'clearing': null,
      'topsoil': null,
      'common_excavation': null,
      'fill': null,
      'ac14_wearing_course': null,
      'bitumen_binder': null,
      'crr_base': null,
      'mc30_prime_coat': null,
      'mc30_curing_membrane': null,
      'c1_subbase': null,
      'g15_upper_subgrade': null,
      'g7_lower_subgrade': null,
      'cement_stabiliser': null,
    };

    double parse(TextEditingController c) =>
        double.tryParse(c.text.trim()) ?? 0.0;
    double qClearing() =>
        includeClearing
            ? totalLengthM * math.max(0.0, parse(clearingWidthCtrl)) / 10000.0
            : 0.0;
    double qTopsoil() =>
        includeTopsoil
            ? totalLengthM *
                math.max(0.0, parse(widthCtrl)) *
                math.max(0.0, parse(topsoilCtrl)) /
                1000.0
            : 0.0;
    double qCommon() =>
        includeCommonExc
            ? totalLengthM *
                math.max(0.0, parse(widthCtrl)) *
                math.max(0.0, parse(commonExcCtrl)) /
                1000.0
            : 0.0;
    double qFill() =>
        includeFill
            ? totalLengthM *
                math.max(0.0, parse(widthCtrl)) *
                math.max(0.0, parse(fillDepthCtrl)) /
                1000.0
            : 0.0;
    double qPavementLayer(bool included, TextEditingController thicknessCtrl) =>
        included
            ? totalLengthM *
                math.max(0.0, parse(pavementWidthCtrl)) *
                math.max(0.0, parse(thicknessCtrl)) /
                1000.0
            : 0.0;
    double qBitumenBinder() =>
        includeAc14 && includeBitumenBinder
            ? qPavementLayer(true, ac14ThicknessCtrl) *
                math.max(0.0, parse(asphaltDensityCtrl)) *
                parse(bitumenContentCtrl).clamp(0.0, 100.0).toDouble() /
                100.0
            : 0.0;
    double qMc30(bool included, TextEditingController rateCtrl) =>
        included
            ? totalLengthM *
                math.max(0.0, parse(pavementWidthCtrl)) *
                math.max(0.0, parse(rateCtrl))
            : 0.0;
    double qCementStabiliser() =>
        includeCementStabiliser
            ? totalLengthM *
                math.max(0.0, parse(pavementWidthCtrl)) *
                math.max(0.0, parse(stabilisedDepthCtrl)) /
                1000.0 *
                math.max(0.0, parse(stabilisedDryDensityCtrl)) *
                parse(cementContentCtrl).clamp(0.0, 100.0).toDouble() /
                100.0
            : 0.0;

    String fmt(double q, String unit) {
      if (unit == 'ha') return '${q.toStringAsFixed(4)} ha';
      if (unit == 'Tons') return '${q.toStringAsFixed(3)} Tons';
      if (unit == 'tonne') return '${q.toStringAsFixed(3)} tonne';
      if (unit == 'Ltr') return '${q.toStringAsFixed(3)} Ltr';
      return '${q.toStringAsFixed(3)} m3';
    }

    Future<void> pickBoq(BuildContext ctx, StateSetter setD, String key) async {
      final picked = await it.showBoqPickerDialog(context: ctx);
      if (picked == null) return;
      setD(() => boqs[key] = picked);
    }

    bool saveAndAnother = false;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (dCtx) => StatefulBuilder(
            builder: (dCtx, setD) {
              Widget numberField(
                String label,
                TextEditingController ctrl, {
                String suffix = 'mm',
              }) => TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setD(() {}),
                decoration: InputDecoration(
                  labelText: label,
                  suffixText: suffix,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              );

              Widget pavementLayerField({
                required String title,
                required String subtitle,
                required bool included,
                required ValueChanged<bool> onChanged,
                required TextEditingController thicknessController,
              }) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CheckboxListTile(
                    value: included,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(title),
                    subtitle: Text(subtitle),
                    onChanged: (value) => onChanged(value ?? false),
                  ),
                  if (included)
                    numberField('$title thickness', thicknessController),
                  const SizedBox(height: 10),
                ],
              );

              Widget outputRow(
                String key,
                String label,
                double qty,
                String unit,
              ) {
                if (qty <= 0.0000001) return const SizedBox.shrink();
                final boq = boqs[key];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(flex: 5, child: Text(label)),
                      Expanded(
                        flex: 2,
                        child: Text(
                          fmt(qty, unit),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 3,
                        child: Text(
                          boq == null ? 'No BOQ selected' : boq.code,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => pickBoq(dCtx, setD, key),
                        child: const Text('Pick'),
                      ),
                    ],
                  ),
                );
              }

              return AlertDialog(
                title: const Text('Road profile take-off'),
                content: SizedBox(
                  width: math.min(MediaQuery.of(dCtx).size.width * 0.86, 1050),
                  height: math.min(MediaQuery.of(dCtx).size.height * 0.78, 760),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Measured road length: ${totalLengthM.toStringAsFixed(3)} m',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Measure the road earthworks and pavement build-up together. Walkways, kerbs and drains remain separate to avoid double counting.',
                        ),
                        const SizedBox(height: 18),
                        DropdownButtonFormField<String>(
                          value: profile,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Road profile',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items:
                              profiles.keys
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: p,
                                      child: Text(p),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setD(() {
                              profile = v;
                              final w = profiles[v]?['widthM'] ?? 6.5;
                              widthCtrl.text = w.toStringAsFixed(1);
                              pavementWidthCtrl.text = w.toStringAsFixed(1);
                              clearingWidthCtrl.text = w.toStringAsFixed(1);
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: numberField(
                                'Road earthwork width',
                                widthCtrl,
                                suffix: 'm',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: numberField(
                                'Clearing width',
                                clearingWidthCtrl,
                                suffix: 'm',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        numberField(
                          'Carriageway / pavement layer width',
                          pavementWidthCtrl,
                          suffix: 'm',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Use formation width for earthworks and carriageway width for pavement layers. Do not add separately measured walkways, kerbs or drains.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF667085),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Road earthworks',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        CheckboxListTile(
                          value: includeClearing,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Clearing & grubbing'),
                          onChanged:
                              (v) => setD(() => includeClearing = v ?? false),
                        ),
                        CheckboxListTile(
                          value: includeTopsoil,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Remove & dispose topsoil'),
                          onChanged:
                              (v) => setD(() => includeTopsoil = v ?? false),
                        ),
                        if (includeTopsoil)
                          numberField('Topsoil thickness', topsoilCtrl),
                        const SizedBox(height: 10),
                        CheckboxListTile(
                          value: includeCommonExc,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Common excavation to formation'),
                          subtitle: const Text(
                            'Enter average cut depth for this measured road chain.',
                          ),
                          onChanged:
                              (v) => setD(() => includeCommonExc = v ?? false),
                        ),
                        if (includeCommonExc)
                          numberField(
                            'Average common excavation depth',
                            commonExcCtrl,
                          ),
                        const SizedBox(height: 10),
                        CheckboxListTile(
                          value: includeFill,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'G3 fill / embankment to formation',
                          ),
                          subtitle: const Text(
                            'Depth may vary along the road; enter the average '
                            'depth for this measured chain.',
                          ),
                          onChanged:
                              (v) => setD(() => includeFill = v ?? false),
                        ),
                        if (includeFill)
                          numberField('Average G3 depth', fillDepthCtrl),
                        const SizedBox(height: 22),
                        const Text(
                          'Pavement layers',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Volumes use measured road length × pavement width × layer thickness.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF667085),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: asphaltGrade,
                          decoration: const InputDecoration(
                            labelText: 'Asphalt concrete grade',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'AC14',
                              child: Text('AC14'),
                            ),
                            DropdownMenuItem(
                              value: 'AC20',
                              child: Text('AC20'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setD(() => asphaltGrade = value);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        pavementLayerField(
                          title: '$asphaltGrade asphalt concrete surfacing',
                          subtitle: 'CC / asphalt concrete layer',
                          included: includeAc14,
                          onChanged: (value) => setD(() => includeAc14 = value),
                          thicknessController: ac14ThicknessCtrl,
                        ),
                        if (includeAc14) ...[
                          CheckboxListTile(
                            value: includeBitumenBinder,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Bitumen binder for asphalt concrete',
                            ),
                            subtitle: const Text(
                              '60/70 penetration-grade asphalt, saved separately in tonnes',
                            ),
                            onChanged:
                                (value) => setD(
                                  () => includeBitumenBinder = value ?? false,
                                ),
                          ),
                          if (includeBitumenBinder) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: numberField(
                                    'Compacted asphalt density',
                                    asphaltDensityCtrl,
                                    suffix: 't/m³',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: numberField(
                                    'Bitumen content by mass',
                                    bitumenContentCtrl,
                                    suffix: '%',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Bitumen = asphalt volume × density × binder content = ${qBitumenBinder().toStringAsFixed(3)} Tons',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF667085),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                        pavementLayerField(
                          title: 'CRR base',
                          subtitle: 'Crushed rock road base',
                          included: includeCrrBase,
                          onChanged:
                              (value) => setD(() => includeCrrBase = value),
                          thicknessController: crrBaseThicknessCtrl,
                        ),
                        CheckboxListTile(
                          value: includeMc30PrimeCoat,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('MC-30 prime coat on CRR base'),
                          subtitle: const Text(
                            'Measured from pavement area and saved in litres.',
                          ),
                          onChanged:
                              (value) => setD(
                                () => includeMc30PrimeCoat = value ?? false,
                              ),
                        ),
                        if (includeMc30PrimeCoat)
                          numberField(
                            'MC-30 prime coat application rate',
                            mc30PrimeRateCtrl,
                            suffix: 'L/m²',
                          ),
                        const SizedBox(height: 10),
                        CheckboxListTile(
                          value: includeMc30CuringMembrane,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'MC-30 bituminous curing membrane on C2 base',
                          ),
                          subtitle: const Text(
                            'Optional treatment measured from pavement area.',
                          ),
                          onChanged:
                              (value) => setD(
                                () =>
                                    includeMc30CuringMembrane = value ?? false,
                              ),
                        ),
                        if (includeMc30CuringMembrane)
                          numberField(
                            'MC-30 curing membrane application rate',
                            mc30CuringRateCtrl,
                            suffix: 'L/m²',
                          ),
                        const SizedBox(height: 10),
                        pavementLayerField(
                          title: 'C1 subbase',
                          subtitle: 'Selected subbase layer',
                          included: includeC1Subbase,
                          onChanged:
                              (value) => setD(() => includeC1Subbase = value),
                          thicknessController: c1SubbaseThicknessCtrl,
                        ),
                        pavementLayerField(
                          title: 'G15 improved upper subgrade',
                          subtitle: 'Optional upper improvement layer',
                          included: includeG15UpperSubgrade,
                          onChanged:
                              (value) =>
                                  setD(() => includeG15UpperSubgrade = value),
                          thicknessController: g15UpperThicknessCtrl,
                        ),
                        pavementLayerField(
                          title: 'G7 improved lower subgrade',
                          subtitle: 'Optional lower improvement layer',
                          included: includeG7LowerSubgrade,
                          onChanged:
                              (value) =>
                                  setD(() => includeG7LowerSubgrade = value),
                          thicknessController: g7LowerThicknessCtrl,
                        ),
                        CheckboxListTile(
                          value: includeCementStabiliser,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Chemical stabiliser – Ordinary Portland cement',
                          ),
                          subtitle: const Text(
                            'Optional additive calculated from the treated '
                            'layer mass and saved in tonnes.',
                          ),
                          onChanged:
                              (value) => setD(
                                () => includeCementStabiliser = value ?? false,
                              ),
                        ),
                        if (includeCementStabiliser) ...[
                          Row(
                            children: [
                              Expanded(
                                child: numberField(
                                  'Stabilised layer depth',
                                  stabilisedDepthCtrl,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: numberField(
                                  'Compacted dry density',
                                  stabilisedDryDensityCtrl,
                                  suffix: 't/m³',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: numberField(
                                  'Cement content by mass',
                                  cementContentCtrl,
                                  suffix: '%',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Cement = treated volume × dry density × cement '
                            'content = ${qCementStabiliser().toStringAsFixed(3)} tonne',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF667085),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 18),
                        const Text(
                          'Calculated BOQ outputs',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        outputRow(
                          'clearing',
                          'Clearing and grubbing',
                          qClearing(),
                          'ha',
                        ),
                        outputRow(
                          'topsoil',
                          'Removal and disposal of topsoil',
                          qTopsoil(),
                          'm3',
                        ),
                        outputRow(
                          'common_excavation',
                          'Common excavation to formation',
                          qCommon(),
                          'm3',
                        ),
                        outputRow(
                          'fill',
                          'G3 fill / embankment to formation',
                          qFill(),
                          'm3',
                        ),
                        outputRow(
                          'ac14_wearing_course',
                          '$asphaltGrade asphalt concrete surfacing',
                          qPavementLayer(includeAc14, ac14ThicknessCtrl),
                          'm3',
                        ),
                        outputRow(
                          'bitumen_binder',
                          'Bitumen for asphalt concrete surfacing (60/70 penetration grade)',
                          qBitumenBinder(),
                          'Tons',
                        ),
                        outputRow(
                          'crr_base',
                          'CRR base',
                          qPavementLayer(includeCrrBase, crrBaseThicknessCtrl),
                          'm3',
                        ),
                        outputRow(
                          'mc30_prime_coat',
                          'MC-30 cut-back bitumen prime coat on CRR base',
                          qMc30(includeMc30PrimeCoat, mc30PrimeRateCtrl),
                          'Ltr',
                        ),
                        outputRow(
                          'mc30_curing_membrane',
                          'MC-30 bituminous curing membrane on C2 base',
                          qMc30(includeMc30CuringMembrane, mc30CuringRateCtrl),
                          'Ltr',
                        ),
                        outputRow(
                          'c1_subbase',
                          'C1 subbase',
                          qPavementLayer(
                            includeC1Subbase,
                            c1SubbaseThicknessCtrl,
                          ),
                          'm3',
                        ),
                        outputRow(
                          'g15_upper_subgrade',
                          'G15 improved upper subgrade',
                          qPavementLayer(
                            includeG15UpperSubgrade,
                            g15UpperThicknessCtrl,
                          ),
                          'm3',
                        ),
                        outputRow(
                          'g7_lower_subgrade',
                          'G7 improved lower subgrade',
                          qPavementLayer(
                            includeG7LowerSubgrade,
                            g7LowerThicknessCtrl,
                          ),
                          'm3',
                        ),
                        outputRow(
                          'cement_stabiliser',
                          'Chemical stabiliser agent – Ordinary Portland cement',
                          qCementStabiliser(),
                          'tonne',
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dCtx, false),
                    child: const Text('Cancel'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      saveAndAnother = true;
                      Navigator.pop(dCtx, true);
                    },
                    icon: const Icon(Icons.add_road),
                    label: const Text('Save & measure another'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      saveAndAnother = false;
                      Navigator.pop(dCtx, true);
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save road profile'),
                  ),
                ],
              );
            },
          ),
    );

    if (accepted != true) return;

    final outputs = <Map<String, dynamic>>[
      if (qClearing() > 0.0000001)
        {
          'key': 'clearing',
          'label': 'Clearing and grubbing',
          'unit': 'ha',
          'qty': qClearing(),
        },
      if (qTopsoil() > 0.0000001)
        {
          'key': 'topsoil',
          'label': 'Removal and disposal of topsoil',
          'unit': 'm3',
          'qty': qTopsoil(),
        },
      if (qCommon() > 0.0000001)
        {
          'key': 'common_excavation',
          'label': 'Common excavation to formation',
          'unit': 'm3',
          'qty': qCommon(),
        },
      if (qFill() > 0.0000001)
        {
          'key': 'fill',
          'label': 'G3 fill / embankment to formation',
          'unit': 'm3',
          'qty': qFill(),
        },
      if (qPavementLayer(includeAc14, ac14ThicknessCtrl) > 0.0000001)
        {
          'key': 'ac14_wearing_course',
          'label': '$asphaltGrade asphalt concrete surfacing',
          'unit': 'm3',
          'qty': qPavementLayer(includeAc14, ac14ThicknessCtrl),
        },
      if (qBitumenBinder() > 0.0000001)
        {
          'key': 'bitumen_binder',
          'label':
              'Bitumen for asphalt concrete surfacing (60/70 penetration grade)',
          'unit': 'Tons',
          'qty': qBitumenBinder(),
        },
      if (qPavementLayer(includeCrrBase, crrBaseThicknessCtrl) > 0.0000001)
        {
          'key': 'crr_base',
          'label': 'CRR base',
          'unit': 'm3',
          'qty': qPavementLayer(includeCrrBase, crrBaseThicknessCtrl),
        },
      if (qMc30(includeMc30PrimeCoat, mc30PrimeRateCtrl) > 0.0000001)
        {
          'key': 'mc30_prime_coat',
          'label': 'MC-30 cut-back bitumen prime coat on CRR base',
          'unit': 'Ltr',
          'qty': qMc30(includeMc30PrimeCoat, mc30PrimeRateCtrl),
        },
      if (qMc30(includeMc30CuringMembrane, mc30CuringRateCtrl) > 0.0000001)
        {
          'key': 'mc30_curing_membrane',
          'label': 'MC-30 bituminous curing membrane on C2 base',
          'unit': 'Ltr',
          'qty': qMc30(includeMc30CuringMembrane, mc30CuringRateCtrl),
        },
      if (qPavementLayer(includeC1Subbase, c1SubbaseThicknessCtrl) > 0.0000001)
        {
          'key': 'c1_subbase',
          'label': 'C1 subbase',
          'unit': 'm3',
          'qty': qPavementLayer(includeC1Subbase, c1SubbaseThicknessCtrl),
        },
      if (qPavementLayer(includeG15UpperSubgrade, g15UpperThicknessCtrl) >
          0.0000001)
        {
          'key': 'g15_upper_subgrade',
          'label': 'G15 improved upper subgrade',
          'unit': 'm3',
          'qty': qPavementLayer(includeG15UpperSubgrade, g15UpperThicknessCtrl),
        },
      if (qPavementLayer(includeG7LowerSubgrade, g7LowerThicknessCtrl) >
          0.0000001)
        {
          'key': 'g7_lower_subgrade',
          'label': 'G7 improved lower subgrade',
          'unit': 'm3',
          'qty': qPavementLayer(includeG7LowerSubgrade, g7LowerThicknessCtrl),
        },
      if (qCementStabiliser() > 0.0000001)
        {
          'key': 'cement_stabiliser',
          'label': 'Chemical stabiliser agent – Ordinary Portland cement',
          'unit': 'tonne',
          'qty': qCementStabiliser(),
        },
    ];

    if (outputs.isEmpty) {
      Get.snackbar('Road profile', 'No positive quantities to save.');
      return;
    }

    final roadGroupId = measurementsRef.doc().id;
    final now = FieldValue.serverTimestamp();
    final polyline = currentSegments
        .map(
          (segment) => <String, dynamic>{
            'p1': {'x': segment.p1.dx, 'y': segment.p1.dy},
            'p2': {'x': segment.p2.dx, 'y': segment.p2.dy},
            'lengthM': segment.lengthM,
          },
        )
        .toList(growable: false);

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (var i = 0; i < outputs.length; i++) {
        final out = outputs[i];
        final key = out['key'] as String;
        final boq = boqs[key];
        final doc = measurementsRef.doc();
        final data = <String, dynamic>{
          'projectId': projectId,
          'buildingId': buildingId,
          'drawingId': drawingId,
          'measureType': 'roadProfile',
          'activeMeasureType': 'roadProfile',
          'type': 'roadProfile',
          'roadProfileGroupId': roadGroupId,
          'roadProfile': profile,
          'asphaltGrade': asphaltGrade,
          'roadProfileOutputKey': key,
          'label': out['label'],
          'unit': out['unit'],
          'value': out['qty'],
          'quantity': out['qty'],
          'lengthM': totalLengthM,
          'roadEarthworkWidthM': math.max(0.0, parse(widthCtrl)),
          'roadPavementWidthM': math.max(0.0, parse(pavementWidthCtrl)),
          'roadClearingWidthM': math.max(0.0, parse(clearingWidthCtrl)),
          'topsoilThicknessMm': math.max(0.0, parse(topsoilCtrl)),
          'commonExcavationDepthMm': math.max(0.0, parse(commonExcCtrl)),
          'fillDepthMm': math.max(0.0, parse(fillDepthCtrl)),
          'ac14ThicknessMm': math.max(0.0, parse(ac14ThicknessCtrl)),
          'asphaltDensityTPerM3': math.max(0.0, parse(asphaltDensityCtrl)),
          'bitumenContentPercent': math.max(
            0.0,
            parse(bitumenContentCtrl).clamp(0.0, 100.0).toDouble(),
          ),
          'crrBaseThicknessMm': math.max(0.0, parse(crrBaseThicknessCtrl)),
          'mc30PrimeCoatRateLPerM2': math.max(0.0, parse(mc30PrimeRateCtrl)),
          'mc30CuringMembraneRateLPerM2': math.max(
            0.0,
            parse(mc30CuringRateCtrl),
          ),
          'c1SubbaseThicknessMm': math.max(0.0, parse(c1SubbaseThicknessCtrl)),
          'g15UpperSubgradeThicknessMm': math.max(
            0.0,
            parse(g15UpperThicknessCtrl),
          ),
          'g7LowerSubgradeThicknessMm': math.max(
            0.0,
            parse(g7LowerThicknessCtrl),
          ),
          'stabilisedLayerDepthMm': math.max(0.0, parse(stabilisedDepthCtrl)),
          'stabilisedDryDensityTPerM3': math.max(
            0.0,
            parse(stabilisedDryDensityCtrl),
          ),
          'cementContentPercent':
              parse(cementContentCtrl).clamp(0.0, 100.0).toDouble(),
          'color': currentColor.value,
          'createdAt': now,
          'updatedAt': now,
          if (boq != null) ...{
            'boqCode': boq.code.trim(),
            'boqCodeRaw': boq.code.trim(),
            'boqCodeNorm': boq.code.replaceAll(RegExp(r'\s+'), '').trim(),
            'boqDescription': boq.description.trim(),
          },
          // One drawable geometry record per road profile group is enough.
          if (i == 0) ...{
            'p1': {
              'x': currentSegments.first.p1.dx,
              'y': currentSegments.first.p1.dy,
            },
            'p2': {
              'x': currentSegments.last.p2.dx,
              'y': currentSegments.last.p2.dy,
            },
            'polylineSegments': polyline,
          },
        };
        batch.set(doc, data);
      }
      await batch.commit();
      clearDraftLength();
      update(['overlay', 'viewer', 'summary']);
      Get.snackbar(
        'Road profile saved',
        '${totalLengthM.toStringAsFixed(3)} m road chain saved with ${outputs.length} BOQ output${outputs.length == 1 ? '' : 's'}.',
        snackPosition: SnackPosition.BOTTOM,
      );
      if (saveAndAnother) {
        setMode(TakeoffMode.measureLength);
      } else {
        setMode(TakeoffMode.view);
      }
    } catch (e) {
      Get.snackbar(
        'Road profile save failed',
        '$e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> _finishKerbChainTakeoff(
    List<LengthDraftSegment> currentSegments,
  ) async {
    final context = Get.context;
    if (context == null || currentSegments.isEmpty) return;

    _kerbSessionId ??= measurementsRef.doc().id;
    final currentChain = _PendingKerbChain(
      id: measurementsRef.doc().id,
      segments: List<LengthDraftSegment>.from(currentSegments),
    );

    final kerbTypes = <String>[
      'Prefabricated semi-mountable Concrete Kerb Type 1',
      'Prefabricated mountable Kerb Type 2',
      'In-situ concrete edge beam 200 x 300 mm',
      'In-situ concrete berm at high fills',
      'Prefabricated concrete chute',
      'Other linear civil work',
    ];

    String selectedType = _pendingKerbType;
    BoqPick? selectedBoq = _pendingKerbBoq;
    bool saving = false;
    String? errorText;

    double pendingLength() => _pendingKerbChains.fold<double>(
      0.0,
      (sum, chain) => sum + chain.lengthM,
    );
    final currentLength = currentChain.lengthM;

    final action = await showDialog<_KerbSessionAction>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              final sessionLength = pendingLength() + currentLength;
              return AlertDialog(
                title: const Text('Kerb chain take-off'),
                content: SizedBox(
                  width: 650,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Chip(
                              avatar: const Icon(Icons.route, size: 18),
                              label: Text(
                                'Current chain: ${currentLength.toStringAsFixed(3)} m',
                              ),
                            ),
                            Chip(
                              avatar: const Icon(
                                Icons.format_list_numbered,
                                size: 18,
                              ),
                              label: Text(
                                'Chains: ${_pendingKerbChains.length + 1}',
                              ),
                            ),
                            Chip(
                              avatar: const Icon(Icons.functions, size: 18),
                              label: Text(
                                'Session total: ${sessionLength.toStringAsFixed(3)} m',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value:
                              kerbTypes.contains(selectedType)
                                  ? selectedType
                                  : kerbTypes.first,
                          decoration: const InputDecoration(
                            labelText: 'Kerb / civil work type',
                            border: OutlineInputBorder(),
                          ),
                          items:
                              kerbTypes
                                  .map(
                                    (type) => DropdownMenuItem<String>(
                                      value: type,
                                      child: Text(type),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              (saving || _pendingKerbChains.isNotEmpty)
                                  ? null
                                  : (value) {
                                    if (value == null) return;
                                    setDialogState(() {
                                      selectedType = value;
                                      errorText = null;
                                    });
                                  },
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.receipt_long_outlined),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      selectedBoq?.code.trim().isNotEmpty ==
                                              true
                                          ? selectedBoq!.code
                                          : 'No BOQ item selected',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (selectedBoq?.description
                                            .trim()
                                            .isNotEmpty ==
                                        true)
                                      Text(
                                        selectedBoq!.description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed:
                                    (saving || _pendingKerbChains.isNotEmpty)
                                        ? null
                                        : () async {
                                          final picked = await it
                                              .showBoqPickerDialog(
                                                context: dialogContext,
                                              );
                                          if (picked == null ||
                                              !dialogContext.mounted) {
                                            return;
                                          }
                                          setDialogState(() {
                                            selectedBoq = picked;
                                            errorText = null;
                                          });
                                        },
                                icon: const Icon(Icons.search),
                                label: const Text('BOQ'),
                              ),
                            ],
                          ),
                        ),
                        if (_pendingKerbChains.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          const Text(
                            'Temporary chains',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          for (var i = 0; i < _pendingKerbChains.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                'Chain ${i + 1}: ${_pendingKerbChains[i].lengthM.toStringAsFixed(3)} m',
                              ),
                            ),
                        ],
                        const SizedBox(height: 12),
                        const Text(
                          'Use Add another chain for another disconnected kerb run with the same BOQ item. Commit all saves every temporary chain in one batch.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                        if (errorText != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            errorText!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed:
                        saving
                            ? null
                            : () => Navigator.pop(
                              dialogContext,
                              _KerbSessionAction.cancel,
                            ),
                    child: const Text('Cancel session'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        saving
                            ? null
                            : () {
                              if (selectedBoq == null ||
                                  selectedBoq!.code.trim().isEmpty) {
                                setDialogState(() {
                                  errorText = 'Select a BOQ item first.';
                                });
                                return;
                              }
                              Navigator.pop(
                                dialogContext,
                                _KerbSessionAction.addAnother,
                              );
                            },
                    icon: const Icon(Icons.add_road),
                    label: const Text('Add another chain'),
                  ),
                  FilledButton.icon(
                    onPressed:
                        saving
                            ? null
                            : () {
                              if (selectedBoq == null ||
                                  selectedBoq!.code.trim().isEmpty) {
                                setDialogState(() {
                                  errorText = 'Select a BOQ item first.';
                                });
                                return;
                              }
                              setDialogState(() => saving = true);
                              Navigator.pop(
                                dialogContext,
                                _KerbSessionAction.commit,
                              );
                            },
                    icon: const Icon(Icons.cloud_done_outlined),
                    label: const Text('Commit all'),
                  ),
                ],
              );
            },
          ),
    );

    if (action == null || action == _KerbSessionAction.cancel) {
      _clearKerbSession();
      clearDraftLength();
      return;
    }

    _pendingKerbType = selectedType;
    _pendingKerbBoq = selectedBoq;
    _pendingKerbChains.add(currentChain);

    if (action == _KerbSessionAction.addAnother) {
      _draftLenP1.value = null;
      _draftLenP2.value = null;
      _draftLengthPoints.clear();
      _draftIndependentSegments.clear();
      update(['overlay', 'viewer', 'summary']);
      Get.snackbar(
        'Kerb chain added',
        '${_pendingKerbChains.length} chain${_pendingKerbChains.length == 1 ? '' : 's'} temporary. Trace the next kerb run and press Finish.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final saved = await _commitKerbSession();
    if (saved) {
      Get.snackbar(
        'Kerb take-off saved',
        'All kerb chains were committed to ${selectedBoq!.code}.',
        snackPosition: SnackPosition.BOTTOM,
      );
      _clearKerbSession();
      clearDraftLength();
      update(['overlay', 'viewer', 'summary']);
    }
  }

  Future<bool> _commitKerbSession() async {
    final boq = _pendingKerbBoq;
    final sessionId = _kerbSessionId;
    if (boq == null || boq.code.trim().isEmpty || sessionId == null) {
      return false;
    }
    if (_pendingKerbChains.isEmpty) return false;

    final totalLength = _pendingKerbChains.fold<double>(
      0.0,
      (sum, chain) => sum + chain.lengthM,
    );
    try {
      final batch = FirebaseFirestore.instance.batch();
      final now = FieldValue.serverTimestamp();
      for (
        var chainIndex = 0;
        chainIndex < _pendingKerbChains.length;
        chainIndex++
      ) {
        final chain = _pendingKerbChains[chainIndex];
        for (
          var segmentIndex = 0;
          segmentIndex < chain.segments.length;
          segmentIndex++
        ) {
          final segment = chain.segments[segmentIndex];
          final docRef = measurementsRef.doc();
          batch.set(docRef, <String, dynamic>{
            'projectId': projectId,
            'buildingId': buildingId,
            'drawingId': drawingId,
            'measureType': 'length',
            'activeMeasureType': 'civilWork',
            'type': 'civilWork',
            'unit': 'm',
            'value': segment.lengthM,
            'lengthM': segment.lengthM,
            'lengthPx': segment.lengthPx,
            'groupValue': totalLength,
            'civilWorkId': sessionId,
            'civilworkId': sessionId,
            'kerbSessionId': sessionId,
            'kerbChainId': chain.id,
            'kerbChainIndex': chainIndex,
            'kerbChainCount': _pendingKerbChains.length,
            'chainSegmentIndex': segmentIndex,
            'chainSegmentCount': chain.segments.length,
            'kerbType': _pendingKerbType,
            'label': _pendingKerbType,
            'boqCode': boq.code.trim(),
            'boqCodeRaw': boq.code.trim(),
            'boqCodeNorm': boq.code.replaceAll(RegExp(r'\\s+'), '').trim(),
            'boqDescription': boq.description.trim(),
            'p1': {'x': segment.p1.dx, 'y': segment.p1.dy},
            'p2': {'x': segment.p2.dx, 'y': segment.p2.dy},
            'segment': {
              'p1': {'x': segment.p1.dx, 'y': segment.p1.dy},
              'p2': {'x': segment.p2.dx, 'y': segment.p2.dy},
            },
            'color': currentColor.value,
            'createdAt': now,
            'updatedAt': now,
          });
        }
      }
      await batch.commit();
      return true;
    } catch (e) {
      Get.snackbar(
        'Kerb save failed',
        '$e',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }
  }

  void _clearKerbSession() {
    _pendingKerbChains.clear();
    _kerbSessionId = null;
    // Keep the last selected BOQ/type as the default for the next kerb session.
  }

  String _drainTypeForProfile(String profile) {
    if (profile.startsWith('Closed') || profile.startsWith('Covered RC')) {
      return 'Closed concrete drain';
    }
    if (profile.startsWith('Concrete Channel'))
      return 'Concrete channel / channelling';
    if (profile.startsWith('Open Masonry'))
      return 'Open masonry / blockwork drain';
    if (profile.startsWith('Earth Drain')) return 'Earth drain';
    if (profile.startsWith('Pipe Drain')) return 'Pipe drain';
    if (profile.startsWith('Underground Stormwater'))
      return 'Underground stormwater drain';
    if (profile.startsWith('Pipe Culvert')) return 'Pipe culvert';
    return 'Open lined drain';
  }

  String _drainSystemForType(String type) {
    if (type == 'Pipe drain' || type == 'Underground stormwater drain') {
      return 'Underground drainage';
    }
    if (type == 'Pipe culvert') return 'Cross-drainage';
    return 'Surface drainage';
  }

  List<String> _drainTypesForSystem(String system) {
    switch (system) {
      case 'Underground drainage':
        return const <String>['Pipe drain', 'Underground stormwater drain'];
      case 'Cross-drainage':
        return const <String>['Pipe culvert'];
      default:
        return const <String>[
          'Open lined drain',
          'Open masonry / blockwork drain',
          'Concrete channel / channelling',
          'Earth drain',
          'Closed concrete drain',
        ];
    }
  }

  List<String> _drainProfilesForType(String type) {
    switch (type) {
      case 'Open masonry / blockwork drain':
        return const <String>[
          'Open Masonry Drain - No Cover',
          'Blockwork Covered Drain - 300mm clear',
        ];
      case 'Concrete channel / channelling':
        return const <String>[
          'Concrete Channel - Rectangular',
          'Concrete Channel - Trapezoidal',
        ];
      case 'Earth drain':
        return const <String>['Earth Drain - Trapezoidal'];
      case 'Closed concrete drain':
        return const <String>[
          'Closed Concrete Drain Type 2A - Inala 500mm',
          'Covered RC Drain Type 2A - CBD vehicular 800mm',
          'Covered RC Drain Type 2B - CBD pedestrian 800mm',
        ];
      case 'Pipe drain':
        return const <String>[
          'Pipe Drain 300mm',
          'Pipe Drain 450mm',
          'Pipe Drain 600mm',
          'Pipe Drain 900mm',
          'Pipe Drain 1200mm',
        ];
      case 'Underground stormwater drain':
        return const <String>[
          'Underground Stormwater 450mm',
          'Underground Stormwater 600mm',
          'Underground Stormwater 900mm',
          'Underground Stormwater 1200mm',
        ];
      case 'Pipe culvert':
        return const <String>[
          'Pipe Culvert 1 x 600mm',
          'Pipe Culvert 1 x 900mm',
          'Pipe Culvert 1 x 1200mm',
          'Pipe Culvert 2 x 900mm',
          'Pipe Culvert 2 x 1000mm',
          'Pipe Culvert 3 x 900mm',
        ];
      default:
        return const <String>[
          'Open Lined Drain Type 1 - 500mm invert',
          'Open Lined Drain Type 2 - 500mm invert',
        ];
    }
  }

  Map<String, double> _drainProfileDefaults(String type, String profile) {
    if (type == 'Open masonry / blockwork drain') {
      final covered = profile.startsWith('Blockwork Covered');
      return <String, double>{
        'bottomMm': 300,
        'startDepthMm': covered ? 640 : 600,
        'endDepthMm': covered ? 640 : 600,
        'sideSlopeH': 0,
        'thicknessMm': 100, // concrete invert
        'blockWallMm': 230,
        'baseCourseMm': 150,
        'baseCourseWidthMm': 760,
        'coverWidthMm': covered ? 540 : 0,
        'coverThicknessMm': covered ? 120 : 0,
        'coverRebarKgM2': 10.5,
        'expansionSpacingM': 0,
        'constructionSpacingM': 0,
        'bitumenRateLpm2': 0,
        'formworkSideFactorM2PerM': 0,
        'pavementCutEdges': 0,
      };
    }
    if (type == 'Concrete channel / channelling') {
      final trapezoidal = profile.contains('Trapezoidal');
      return <String, double>{
        'bottomMm': 300,
        'startDepthMm': 300,
        'endDepthMm': 300,
        'sideSlopeH': trapezoidal ? 1 : 0,
        'thicknessMm': 100,
        'meshKgM2': 0,
        'expansionSpacingM': 20,
        'constructionSpacingM': 5,
        'bitumenRateLpm2': 0,
        'formworkSideFactorM2PerM': trapezoidal ? 0 : 0.6,
        'pavementCutEdges': 0,
      };
    }
    if (type == 'Earth drain') {
      return <String, double>{
        'bottomMm': 500,
        'startDepthMm': 500,
        'endDepthMm': 500,
        'sideSlopeH': 2,
        'thicknessMm': 0,
        'meshKgM2': 0,
        'expansionSpacingM': 0,
        'constructionSpacingM': 0,
        'bitumenRateLpm2': 0,
        'formworkSideFactorM2PerM': 0,
        'pavementCutEdges': 0,
      };
    }
    if (type == 'Pipe drain' || type == 'Underground stormwater drain') {
      var diameterMm = 450.0;
      final match = RegExp(r'(\d+)mm').firstMatch(profile);
      if (match != null)
        diameterMm = double.tryParse(match.group(1) ?? '') ?? diameterMm;
      return <String, double>{
        'barrels': 1,
        'diameterMm': diameterMm,
        'startDepthMm': 1200,
        'endDepthMm': 1200,
        'barrelSpacingMm': 300,
        'excavAllowanceMm': 300,
        'beddingMm': 150,
        'headwallConcretePerEndM3': 0,
        'headwallFormworkPerEndM2': 0,
        'apronConcretePerEndM3': 0,
        'headwallSteelKgM3': 120,
      };
    }
    if (type == 'Closed concrete drain') {
      final cbdVehicular = profile.contains('CBD vehicular');
      final cbdPedestrian = profile.contains('CBD pedestrian');
      return <String, double>{
        'bottomMm': cbdVehicular || cbdPedestrian ? 800 : 500,
        'startDepthMm': 800,
        'endDepthMm': 800,
        'wallMm': cbdPedestrian ? 150 : 200,
        'baseMm': cbdPedestrian ? 150 : 200,
        'coverMm': cbdVehicular ? 200 : (cbdPedestrian ? 100 : 150),
        // The CBD access slab projects beyond the drain walls in section.
        'coverWidthMm': cbdVehicular || cbdPedestrian ? 1500 : 900,
        'blindingMm': 0,
        'excavAllowanceMm': 300,
        'steelKgM3': 120,
        'wallFormworkFaces': 4,
        'expansionSpacingM': 20,
        'constructionSpacingM': 5,
        'bitumenRateLpm2': 0,
        // Closed-drain BOQ presentation: 1 = composite structural concrete, 0 = components.
        'closedCompositeMode': 1,
        // Set to 1 when the selected structural-concrete BOQ rate includes formwork.
        'closedCompositeIncludesFormwork': 1,
      };
    }
    if (type == 'Pipe culvert') {
      var barrels = 1.0;
      var diameterMm = 600.0;
      if (profile.contains('1 x 900')) diameterMm = 900;
      if (profile.contains('1 x 1200')) diameterMm = 1200;
      if (profile.contains('2 x 900')) {
        barrels = 2;
        diameterMm = 900;
      }
      if (profile.contains('2 x 1000')) {
        barrels = 2;
        diameterMm = 1000;
      }
      if (profile.contains('3 x 900')) {
        barrels = 3;
        diameterMm = 900;
      }
      return <String, double>{
        'barrels': barrels,
        'diameterMm': diameterMm,
        'startDepthMm': 1500,
        'endDepthMm': 1500,
        'barrelSpacingMm': 300,
        'excavAllowanceMm': 300,
        'beddingMm': 150,
        'headwallConcretePerEndM3': 0,
        'headwallFormworkPerEndM2': 0,
        'apronConcretePerEndM3': 0,
        'headwallSteelKgM3': 120,
      };
    }
    final type1 = profile.contains('Type 1');
    return <String, double>{
      'bottomMm': 500,
      'startDepthMm': type1 ? 300 : 500,
      'endDepthMm': type1 ? 300 : 500,
      'sideSlopeH': 2,
      'thicknessMm': 100,
      'meshKgM2': 2.22,
      'expansionSpacingM': 20,
      'constructionSpacingM': 5,
      'bitumenRateLpm2': 0.5,
      'formworkSideFactorM2PerM': 0,
      'pavementCutEdges': 0,
      'kerbPatternFactor': type1 ? (2 / 3) : 0,
      'pavingStripWidthMm': type1 ? 1000 : 0,
      'sandMm': type1 ? 20 : 0,
      'g15Mm': type1 ? 150 : 0,
      'subgradeMm': type1 ? 150 : 0,
    };
  }

  Map<String, String> _drainOutputLabels(
    String type,
    String profile,
    String backfillMaterial,
  ) {
    final common = <String, String>{
      'clearing_grubbing': 'Clearing and grubbing',
      'manhole_excavation': 'Excavation for stormwater manhole',
      'manhole_base_course': 'Base course below stormwater manhole',
      'manhole_invert_concrete':
          'Concrete invert to stormwater manhole Class 15/19',
      'manhole_blockwork': '230 mm block wall to stormwater manhole',
      'manhole_cover_concrete': 'Precast concrete manhole covers Class 25/19',
      'manhole_cover_rebar': 'Reinforcement to precast manhole covers',
      'topsoil_remove': 'Removal and disposal of topsoil',
      'common_excavation': 'Common excavation before drain/trench excavation',
      'excavation_0_1_5': 'Excavation - depth up to 1.5 m',
      'excavation_1_5_3': 'Excavation - depth >1.5 m to 3.0 m',
      'excavation_3_4_5': 'Excavation - depth >3.0 m to 4.5 m',
      'excavation_4_5_6': 'Excavation - depth >4.5 m to 6.0 m',
      'rock_extra': 'Extra over excavation in rock',
    };
    if (type == 'Open masonry / blockwork drain') {
      common.addAll(<String, String>{
        'blockwork': '230 mm block wall to open drain',
        'invert_concrete': 'Concrete invert to open masonry drain',
        'base_course': 'Base course material below open masonry drain',
      });
      if (profile.startsWith('Blockwork Covered')) {
        common.addAll(<String, String>{
          'precast_cover_concrete':
              'Precast concrete covers to blockwork drain Class 25/19',
          'precast_cover_rebar':
              'Reinforcement to precast concrete drain covers',
        });
      }
      return common;
    }
    if (type == 'Concrete channel / channelling') {
      common.addAll(<String, String>{
        'trimming_soft':
            'Trimming / preparation of channel excavation in soft material',
        'trimming_rock': 'Trimming / preparation of channel excavation in rock',
        'channel_run': 'Concrete channel / channelling',
        'channel_concrete': 'Concrete to channel / channelling',
        'finish': 'Surface finish to concrete channel',
        'formwork_sides': 'Formwork to channel sides / edges where required',
        'mesh': 'Reinforcement / welded steel fabric to channel',
        'polythene': 'Polyethylene sheeting below channel',
        'bitumen': 'Bitumen emulsion to prepared surface',
        'cut_pavement': 'Cutting existing pavement / surfacing',
        'expansion': 'Expansion joints',
        'construction': 'Construction joints',
      });
      return common;
    }
    if (type == 'Earth drain') {
      common.addAll(<String, String>{
        'trimming_soft': 'Trimming / shaping earth drain in soft material',
        'trimming_rock': 'Trimming / shaping earth drain in rock',
        'earth_drain_run': 'Earth drain / channel run',
      });
      return common;
    }
    if (type == 'Open lined drain') {
      common.addAll(<String, String>{
        'trimming_soft': 'Trimming of excavation in soft material',
        'trimming_rock': 'Trimming of excavation in rock',
        'concrete': 'Concrete lining',
        'finish': 'U2 surface finish to concrete lining',
        'formwork_sides': 'Formwork to sides / edges where required',
        'mesh': 'Welded steel fabric / A142 reinforcement',
        'polythene': 'Polyethylene sheeting',
        'bitumen': 'Bitumen emulsion to prepared surface',
        'cut_pavement': 'Cutting existing pavement / surfacing',
        'expansion': 'Expansion joints',
        'construction': 'Construction joints',
      });
      if (profile.contains('Type 1') && profile.contains('Block wall')) {
        common.addAll(<String, String>{
          'blockwork': '230 mm block wall to sides',
          'invert_concrete': '100 mm concrete invert Class 15/19',
          'base_course': 'Base course material below drain',
          'precast_cover_concrete': 'Precast concrete drain covers Class 25/19',
          'precast_cover_rebar':
              'Reinforcement to precast concrete drain covers',
        });
      }
      return common;
    }
    if (type == 'Closed concrete drain') {
      common.addAll(<String, String>{
        'blinding': 'Concrete blinding below drain',
        'structural_concrete':
            'Structural concrete to closed drain (base + walls + cover)',
        'base_concrete': 'Concrete to drain base slab',
        'wall_concrete': 'Concrete to drain walls',
        'cover_concrete': 'Concrete to drain cover slab',
        'wall_formwork': 'Formwork to drain wall faces',
        'cover_soffit_formwork': 'Formwork to soffit of cover slab',
        'reinforcement': 'Reinforcement to closed concrete drain',
        'polythene': 'Polyethylene sheeting below base',
        'backfill': 'Backfilling around closed drain',
        'expansion': 'Expansion joints',
        'construction': 'Construction joints',
      });
      return common;
    }
    if (type == 'Pipe drain' || type == 'Underground stormwater drain') {
      common.addAll(<String, String>{
        'pipe_run': '$profile - installed pipe length',
        'bedding': 'Bedding to stormwater pipe drain',
        'backfill': '$backfillMaterial backfilling to stormwater pipe drain',
      });
      return common;
    }
    common.addAll(<String, String>{
      'culvert_run': '$profile - installed culvert length',
      'bedding': 'Class A / selected bedding to culvert',
      'backfill': '$backfillMaterial backfilling to culvert',
      'headwall_concrete':
          'Concrete to culvert headwalls / inlet-outlet structures',
      'headwall_formwork': 'Formwork to culvert headwalls / structures',
      'apron_concrete': 'Concrete to culvert aprons / protection works',
      'headwall_reinforcement':
          'Reinforcement to culvert headwalls / structures',
    });
    return common;
  }

  String _drainOutputUnit(String key) {
    const m3 = <String>{
      'topsoil_remove',
      'common_excavation',
      'excavation_0_1_5',
      'excavation_1_5_3',
      'excavation_3_4_5',
      'excavation_4_5_6',
      'rock_extra',
      'concrete',
      'channel_concrete',
      'blinding',
      'structural_concrete',
      'base_concrete',
      'wall_concrete',
      'cover_concrete',
      'backfill',
      'bedding',
      'headwall_concrete',
      'apron_concrete',
      'sand_bedding',
      'g15',
      'improved_subgrade',
      'invert_concrete',
      'base_course',
      'precast_cover_concrete',
      'manhole_excavation',
      'manhole_base_course',
      'manhole_invert_concrete',
      'manhole_cover_concrete',
    };
    const m2 = <String>{
      'trimming_soft',
      'trimming_rock',
      'finish',
      'formwork_sides',
      'polythene',
      'wall_formwork',
      'cover_soffit_formwork',
      'headwall_formwork',
      'paving_blocks',
      'blockwork',
      'manhole_blockwork',
    };
    if (key == 'clearing_grubbing') return 'ha';
    if (m3.contains(key)) return 'm3';
    if (m2.contains(key)) return 'm2';
    if (key == 'mesh' ||
        key == 'reinforcement' ||
        key == 'headwall_reinforcement' ||
        key == 'precast_cover_rebar' ||
        key == 'manhole_cover_rebar')
      return 'ton';
    if (key == 'bitumen') return 'L';
    return 'm';
  }

  String? _drainSuggestedBoqCode(
    String type,
    String profile,
    String key,
    String backfillMaterial,
  ) {
    final openWork =
        type == 'Open lined drain' ||
        type == 'Open masonry / blockwork drain' ||
        type == 'Concrete channel / channelling' ||
        type == 'Earth drain';
    switch (key) {
      case 'excavation_0_1_5':
        return openWork ? '21.01(A)(i)' : '22.01(A)(i)';
      case 'excavation_1_5_3':
        return openWork ? '21.01(A)(ii)' : '22.01(A)(ii)';
      case 'excavation_3_4_5':
      case 'excavation_4_5_6':
        return openWork ? null : '22.01(A)(iii)';
      case 'rock_extra':
        return openWork ? '21.01(B)' : '22.01(B)';
      case 'trimming_soft':
        return '23.07(a)';
      case 'trimming_rock':
        return '23.07(b)';
      case 'concrete':
      case 'channel_concrete':
        return '23.08(a)';
      case 'finish':
        return '23.08(b)';
      case 'formwork_sides':
        return '23.09(b)';
      case 'expansion':
        return '23.10(i)';
      case 'construction':
        return '23.10(ii)';
      case 'culvert_run':
        if (profile.contains('1 x 600')) return '22.03(a)';
        if (profile.contains('1 x 900')) return '22.03(b)';
        if (profile.contains('1 x 1200')) return '22.03(c)';
        if (profile.contains('2 x 1000')) return '22.03(d)';
        if (profile.contains('2 x 900')) return '22.03(e)';
        if (profile.contains('3 x 900')) return '22.03(f)';
        return null;
      case 'bedding':
        return '22.07(a)';
      case 'backfill':
        if (backfillMaterial == 'Selected imported material') {
          return '22.02(b)';
        }
        if (backfillMaterial == 'Soil cement') return '22.02(c)';
        return '22.02(a)';
      case 'headwall_concrete':
      case 'apron_concrete':
      case 'structural_concrete':
      case 'base_concrete':
      case 'wall_concrete':
      case 'cover_concrete':
      case 'manhole_invert_concrete':
        return '22.07(c)';
      case 'headwall_formwork':
      case 'wall_formwork':
      case 'cover_soffit_formwork':
        return '22.07(d)';
      case 'headwall_reinforcement':
      case 'reinforcement':
        return '22.11';
      case 'pipe_run':
        if (profile.contains('300mm')) return '22.23(a)(i)';
        if (profile.contains('450mm')) return '22.23(a)(ii)';
        return null;
    }
    return null;
  }

  void _addDrainDepthBandedVolume(
    Map<String, double> result, {
    required double lengthM,
    required double startDepthM,
    required double endDepthM,
    required double Function(double depthM) areaAtDepth,
  }) {
    if (lengthM <= 0) return;
    const slices = 40;
    final sliceLength = lengthM / slices;
    for (var i = 0; i < slices; i++) {
      final f = (i + 0.5) / slices;
      final depth = startDepthM + (endDepthM - startDepthM) * f;
      final volume = areaAtDepth(depth) * sliceLength;
      String key;
      if (depth <= 1.5) {
        key = 'excavation_0_1_5';
      } else if (depth <= 3.0) {
        key = 'excavation_1_5_3';
      } else if (depth <= 4.5) {
        key = 'excavation_3_4_5';
      } else {
        key = 'excavation_4_5_6';
      }
      result[key] = (result[key] ?? 0) + volume;
    }
  }

  Map<String, double> _calculateDrainQuantities({
    required String type,
    required String profile,
    required List<_PendingDrainChain> chains,
    required Map<String, double> params,
    required double rockPercent,
  }) {
    final q = <String, double>{
      'length': chains.fold<double>(0, (a, b) => a + b.lengthM),
      'excavation_0_1_5': 0,
      'excavation_1_5_3': 0,
      'excavation_3_4_5': 0,
      'excavation_4_5_6': 0,
      'rock_extra': 0,
    };
    if (chains.isEmpty) return q;

    // Site preparation quantities are derived from the same measured chain.
    // A width override of 0 means AQS derives the width from the selected profile.
    final sitePrepOverrideM = (params['sitePrepWidthMm'] ?? 0) / 1000;
    final siteWorkingAllowanceM =
        (params['siteWorkingAllowanceMm'] ?? 500) / 1000;
    var sitePrepAreaM2 = 0.0;
    for (final chain in chains) {
      final avgDepth = (chain.startDepthM + chain.endDepthM) / 2;
      double autoWidthM;
      if (type == 'Open lined drain' ||
          type == 'Open masonry / blockwork drain' ||
          type == 'Concrete channel / channelling' ||
          type == 'Earth drain') {
        final bottom = (params['bottomMm'] ?? 300) / 1000;
        final z = params['sideSlopeH'] ?? 2;
        final topWidth = bottom + 2 * z * avgDepth;
        autoWidthM = topWidth + 2 * siteWorkingAllowanceM;
      } else if (type == 'Closed concrete drain') {
        final internalWidth = (params['bottomMm'] ?? 500) / 1000;
        final wall = (params['wallMm'] ?? 200) / 1000;
        final excavAllowance = (params['excavAllowanceMm'] ?? 300) / 1000;
        autoWidthM = internalWidth + 2 * wall + 2 * excavAllowance;
      } else {
        final barrels = params['barrels'] ?? 1;
        final diameter = (params['diameterMm'] ?? 600) / 1000;
        final spacing = (params['barrelSpacingMm'] ?? 300) / 1000;
        final excavAllowance = (params['excavAllowanceMm'] ?? 300) / 1000;
        autoWidthM =
            barrels * diameter +
            (barrels > 1 ? (barrels - 1) * spacing : 0) +
            2 * excavAllowance;
      }
      final widthM = sitePrepOverrideM > 0 ? sitePrepOverrideM : autoWidthM;
      if (widthM > 0) sitePrepAreaM2 += chain.lengthM * widthM;
    }
    final includeClearing = (params['includeClearing'] ?? 0) > 0;
    final includeTopsoil = (params['includeTopsoil'] ?? 0) > 0;
    final includeCommonExcavation =
        (params['includeCommonExcavation'] ?? 0) > 0;
    final topsoilDepthM = (params['topsoilMm'] ?? 150) / 1000;
    final commonExcavDepthM = (params['commonExcavationMm'] ?? 0) / 1000;
    if (includeClearing) q['clearing_grubbing'] = sitePrepAreaM2 / 10000;
    if (includeTopsoil && topsoilDepthM > 0) {
      // The project BOQ measures stripping and disposal together as one item.
      q['topsoil_remove'] = sitePrepAreaM2 * topsoilDepthM;
    }
    if (includeCommonExcavation && commonExcavDepthM > 0) {
      q['common_excavation'] = sitePrepAreaM2 * commonExcavDepthM;
    }

    if (type == 'Open masonry / blockwork drain') {
      final internalWidth = (params['bottomMm'] ?? 300) / 1000;
      final invertThickness = (params['thicknessMm'] ?? 100) / 1000;
      final baseCourseThickness = (params['baseCourseMm'] ?? 150) / 1000;
      final baseCourseWidth =
          (params['baseCourseWidthMm'] ??
              ((params['bottomMm'] ?? 300) +
                  2 * (params['blockWallMm'] ?? 230))) /
          1000;
      var blockworkArea = 0.0;
      var invertConcrete = 0.0;
      var baseCourse = 0.0;
      var coverConcrete = 0.0;
      var coverPlanArea = 0.0;
      final coverWidth = (params['coverWidthMm'] ?? 0) / 1000;
      final coverThickness = (params['coverThicknessMm'] ?? 0) / 1000;
      final coverRebarRate = params['coverRebarKgM2'] ?? 10.5;
      for (final chain in chains) {
        final L = chain.lengthM;
        final avgDepth = (chain.startDepthM + chain.endDepthM) / 2;
        blockworkArea += 2 * avgDepth * L;
        invertConcrete += internalWidth * invertThickness * L;
        baseCourse += baseCourseWidth * baseCourseThickness * L;
        coverConcrete += coverWidth * coverThickness * L;
        coverPlanArea += coverWidth * L;
        _addDrainDepthBandedVolume(
          q,
          lengthM: L,
          startDepthM:
              chain.startDepthM + invertThickness + baseCourseThickness,
          endDepthM: chain.endDepthM + invertThickness + baseCourseThickness,
          areaAtDepth: (_) => baseCourseWidth,
        );
      }
      q['blockwork'] = blockworkArea;
      q['invert_concrete'] = invertConcrete;
      q['base_course'] = baseCourse;
      q['precast_cover_concrete'] = coverConcrete;
      q['precast_cover_rebar'] = coverPlanArea * coverRebarRate / 1000;
    } else if (type == 'Concrete channel / channelling') {
      final bottom = (params['bottomMm'] ?? 300) / 1000;
      final z = params['sideSlopeH'] ?? 0;
      final thickness = (params['thicknessMm'] ?? 100) / 1000;
      final meshRate = params['meshKgM2'] ?? 0;
      final bitumenRate = params['bitumenRateLpm2'] ?? 0;
      var developedArea = 0.0;
      var concrete = 0.0;
      for (final chain in chains) {
        const slices = 40;
        final dl = chain.lengthM / slices;
        for (var i = 0; i < slices; i++) {
          final f = (i + 0.5) / slices;
          final depth =
              chain.startDepthM + (chain.endDepthM - chain.startDepthM) * f;
          final side =
              z > 0
                  ? math.sqrt(depth * depth + (z * depth) * (z * depth))
                  : depth;
          final developed = bottom + 2 * side;
          developedArea += developed * dl;
          concrete += developed * thickness * dl;
        }
        _addDrainDepthBandedVolume(
          q,
          lengthM: chain.lengthM,
          startDepthM: chain.startDepthM,
          endDepthM: chain.endDepthM,
          areaAtDepth: (depth) => depth * (bottom + z * depth),
        );
      }
      final rockFraction = (rockPercent / 100).clamp(0.0, 1.0).toDouble();
      q['trimming_soft'] = developedArea * (1 - rockFraction);
      q['trimming_rock'] = developedArea * rockFraction;
      q['channel_run'] = q['length'] ?? 0;
      q['channel_concrete'] = concrete;
      q['finish'] = developedArea;
      q['formwork_sides'] =
          (q['length'] ?? 0) * (params['formworkSideFactorM2PerM'] ?? 0);
      q['mesh'] = developedArea * meshRate / 1000;
      q['polythene'] = developedArea;
      q['bitumen'] = developedArea * bitumenRate;
      q['cut_pavement'] =
          (q['length'] ?? 0) * (params['pavementCutEdges'] ?? 0);
      final expSpacing = params['expansionSpacingM'] ?? 20;
      final conSpacing = params['constructionSpacingM'] ?? 5;
      var expLength = 0.0;
      var conLength = 0.0;
      for (final chain in chains) {
        final avgDepth = (chain.startDepthM + chain.endDepthM) / 2;
        final side =
            z > 0
                ? math.sqrt(
                  avgDepth * avgDepth + (z * avgDepth) * (z * avgDepth),
                )
                : avgDepth;
        final developed = bottom + 2 * side;
        if (expSpacing > 0) {
          expLength += (chain.lengthM / expSpacing).floor() * developed;
        }
        if (conSpacing > 0) {
          conLength += (chain.lengthM / conSpacing).floor() * developed;
        }
      }
      q['expansion'] = expLength;
      q['construction'] = conLength;
    } else if (type == 'Earth drain') {
      final bottom = (params['bottomMm'] ?? 500) / 1000;
      final z = params['sideSlopeH'] ?? 2;
      var trimArea = 0.0;
      for (final chain in chains) {
        const slices = 40;
        final dl = chain.lengthM / slices;
        for (var i = 0; i < slices; i++) {
          final f = (i + 0.5) / slices;
          final depth =
              chain.startDepthM + (chain.endDepthM - chain.startDepthM) * f;
          final side = math.sqrt(depth * depth + (z * depth) * (z * depth));
          trimArea += (bottom + 2 * side) * dl;
        }
        _addDrainDepthBandedVolume(
          q,
          lengthM: chain.lengthM,
          startDepthM: chain.startDepthM,
          endDepthM: chain.endDepthM,
          areaAtDepth: (depth) => depth * (bottom + z * depth),
        );
      }
      final rockFraction = (rockPercent / 100).clamp(0.0, 1.0).toDouble();
      q['trimming_soft'] = trimArea * (1 - rockFraction);
      q['trimming_rock'] = trimArea * rockFraction;
      q['earth_drain_run'] = q['length'] ?? 0;
    } else if (type == 'Open lined drain' &&
        profile.contains('Type 1') &&
        profile.contains('Block wall')) {
      final internalWidth = (params['bottomMm'] ?? 300) / 1000;
      final invertThickness = (params['thicknessMm'] ?? 100) / 1000;
      final baseCourseThickness = (params['baseCourseMm'] ?? 150) / 1000;
      final baseCourseWidth = (params['baseCourseWidthMm'] ?? 860) / 1000;
      final coverWidth = (params['coverWidthMm'] ?? 540) / 1000;
      final coverThickness = (params['coverThicknessMm'] ?? 120) / 1000;
      final coverRebarRate = params['coverRebarKgM2'] ?? 10.5;
      var blockworkArea = 0.0;
      var invertConcrete = 0.0;
      var baseCourse = 0.0;
      var coverConcrete = 0.0;
      var coverArea = 0.0;
      for (final chain in chains) {
        final L = chain.lengthM;
        final avgDepth = (chain.startDepthM + chain.endDepthM) / 2;
        blockworkArea += 2 * avgDepth * L;
        invertConcrete += internalWidth * invertThickness * L;
        baseCourse += baseCourseWidth * baseCourseThickness * L;
        coverConcrete += coverWidth * coverThickness * L;
        coverArea += coverWidth * L;
        _addDrainDepthBandedVolume(
          q,
          lengthM: L,
          startDepthM:
              chain.startDepthM + invertThickness + baseCourseThickness,
          endDepthM: chain.endDepthM + invertThickness + baseCourseThickness,
          areaAtDepth: (_) => baseCourseWidth,
        );
      }
      q['blockwork'] = blockworkArea;
      q['invert_concrete'] = invertConcrete;
      q['base_course'] = baseCourse;
      q['precast_cover_concrete'] = coverConcrete;
      q['precast_cover_rebar'] = coverArea * coverRebarRate / 1000;
    } else if (type == 'Open lined drain') {
      final bottom = (params['bottomMm'] ?? 300) / 1000;
      final z = params['sideSlopeH'] ?? 2;
      final thickness = (params['thicknessMm'] ?? 100) / 1000;
      final meshRate = params['meshKgM2'] ?? 2.22;
      final bitumenRate = params['bitumenRateLpm2'] ?? 0.5;
      var liningArea = 0.0;
      var concrete = 0.0;
      for (final chain in chains) {
        const slices = 40;
        final dl = chain.lengthM / slices;
        for (var i = 0; i < slices; i++) {
          final f = (i + 0.5) / slices;
          final depth =
              chain.startDepthM + (chain.endDepthM - chain.startDepthM) * f;
          final side = math.sqrt(depth * depth + (z * depth) * (z * depth));
          final developed = bottom + 2 * side;
          liningArea += developed * dl;
          concrete += developed * thickness * dl;
        }
        _addDrainDepthBandedVolume(
          q,
          lengthM: chain.lengthM,
          startDepthM: chain.startDepthM,
          endDepthM: chain.endDepthM,
          areaAtDepth: (depth) => depth * (bottom + z * depth),
        );
      }
      final rockFraction = (rockPercent / 100).clamp(0.0, 1.0).toDouble();
      q['trimming_soft'] = liningArea * (1 - rockFraction);
      q['trimming_rock'] = liningArea * rockFraction;
      q['concrete'] = concrete;
      q['finish'] = liningArea;
      q['formwork_sides'] =
          (q['length'] ?? 0) * (params['formworkSideFactorM2PerM'] ?? 0);
      q['mesh'] = liningArea * meshRate / 1000;
      q['polythene'] = liningArea;
      q['bitumen'] = liningArea * bitumenRate;
      q['cut_pavement'] =
          (q['length'] ?? 0) * (params['pavementCutEdges'] ?? 0);
      final expSpacing = params['expansionSpacingM'] ?? 20;
      final conSpacing = params['constructionSpacingM'] ?? 5;
      var expLength = 0.0;
      var conLength = 0.0;
      for (final chain in chains) {
        final avgDepth = (chain.startDepthM + chain.endDepthM) / 2;
        final side = math.sqrt(
          avgDepth * avgDepth + (z * avgDepth) * (z * avgDepth),
        );
        final developed = bottom + 2 * side;
        if (expSpacing > 0) {
          expLength += (chain.lengthM / expSpacing).floor() * developed;
        }
        if (conSpacing > 0) {
          conLength += (chain.lengthM / conSpacing).floor() * developed;
        }
      }
      q['expansion'] = expLength;
      q['construction'] = conLength;
    } else if (type == 'Closed concrete drain') {
      final internalWidth = (params['bottomMm'] ?? 500) / 1000;
      final wall = (params['wallMm'] ?? 200) / 1000;
      final base = (params['baseMm'] ?? 200) / 1000;
      final cover = (params['coverMm'] ?? 150) / 1000;
      final coverWidth =
          (params['coverWidthMm'] ??
              (params['bottomMm'] ?? 500) + 2 * (params['wallMm'] ?? 200)) /
          1000;
      final blind = (params['blindingMm'] ?? 0) / 1000;
      final allowance = (params['excavAllowanceMm'] ?? 300) / 1000;
      final outerWidth = internalWidth + 2 * wall;
      final trenchWidth = outerWidth + 2 * allowance;
      var baseConcrete = 0.0;
      var wallConcrete = 0.0;
      var coverConcrete = 0.0;
      var blinding = 0.0;
      var wallFormwork = 0.0;
      var soffitFormwork = 0.0;
      var polythene = 0.0;
      var backfill = 0.0;
      var expansionJoints = 0.0;
      var constructionJoints = 0.0;
      final expSpacing = params['expansionSpacingM'] ?? 20;
      final conSpacing = params['constructionSpacingM'] ?? 5;
      for (final chain in chains) {
        final L = chain.lengthM;
        final avgClearDepth = (chain.startDepthM + chain.endDepthM) / 2;
        final startExcDepth = chain.startDepthM + base + cover + blind;
        final endExcDepth = chain.endDepthM + base + cover + blind;
        _addDrainDepthBandedVolume(
          q,
          lengthM: L,
          startDepthM: startExcDepth,
          endDepthM: endExcDepth,
          areaAtDepth: (_) => trenchWidth,
        );
        baseConcrete += outerWidth * base * L;
        wallConcrete += 2 * wall * avgClearDepth * L;
        coverConcrete += coverWidth * cover * L;
        blinding += outerWidth * blind * L;
        final faces = params['wallFormworkFaces'] ?? 4;
        wallFormwork += faces * avgClearDepth * L;
        soffitFormwork += internalWidth * L;
        polythene += outerWidth * L;
        final avgExcDepth = (startExcDepth + endExcDepth) / 2;
        final sideVoid = trenchWidth - outerWidth;
        backfill += sideVoid > 0 ? sideVoid * avgExcDepth * L : 0;
        final jointDeveloped = outerWidth + 2 * avgClearDepth;
        if (expSpacing > 0) {
          expansionJoints +=
              (L / expSpacing).floor().toDouble() * jointDeveloped;
        }
        if (conSpacing > 0) {
          constructionJoints +=
              (L / conSpacing).floor().toDouble() * jointDeveloped;
        }
      }
      final totalConcrete = baseConcrete + wallConcrete + coverConcrete;
      final compositeMode = (params['closedCompositeMode'] ?? 1) > 0;
      final compositeIncludesFormwork =
          (params['closedCompositeIncludesFormwork'] ?? 1) > 0;
      q['blinding'] = blinding;
      // Keep the engineering calculation detailed, but present it to the BOQ
      // according to the selected payment/measurement mode.
      q['structural_concrete'] = compositeMode ? totalConcrete : 0;
      q['base_concrete'] = compositeMode ? 0 : baseConcrete;
      q['wall_concrete'] = compositeMode ? 0 : wallConcrete;
      q['cover_concrete'] = compositeMode ? 0 : coverConcrete;
      q['wall_formwork'] =
          compositeMode && compositeIncludesFormwork ? 0 : wallFormwork;
      q['cover_soffit_formwork'] =
          compositeMode && compositeIncludesFormwork ? 0 : soffitFormwork;
      q['reinforcement'] = totalConcrete * (params['steelKgM3'] ?? 120) / 1000;
      // Closed Drain Type 2A detail does not specify polyethylene below the base.
      // Do not create an unsupported BOQ output for this profile.
      q['polythene'] =
          profile == 'Closed Concrete Drain Type 2A' ? 0 : polythene;
      q['backfill'] = backfill;
      q['expansion'] = expansionJoints;
      q['construction'] = constructionJoints;
    } else {
      final barrels = params['barrels'] ?? 1;
      final diameter = (params['diameterMm'] ?? 600) / 1000;
      final spacing = (params['barrelSpacingMm'] ?? 300) / 1000;
      final allowance = (params['excavAllowanceMm'] ?? 300) / 1000;
      final bedding = (params['beddingMm'] ?? 150) / 1000;
      final trenchWidth =
          barrels * diameter +
          (barrels > 1 ? (barrels - 1) * spacing : 0) +
          2 * allowance;
      var beddingVolume = 0.0;
      var backfill = 0.0;
      for (final chain in chains) {
        _addDrainDepthBandedVolume(
          q,
          lengthM: chain.lengthM,
          startDepthM: chain.startDepthM,
          endDepthM: chain.endDepthM,
          areaAtDepth: (_) => trenchWidth,
        );
        beddingVolume += trenchWidth * bedding * chain.lengthM;
        final avgDepth = (chain.startDepthM + chain.endDepthM) / 2;
        final excavation = trenchWidth * avgDepth * chain.lengthM;
        final pipeDisplacement =
            barrels * math.pi * diameter * diameter / 4 * chain.lengthM;
        final chainBedding = trenchWidth * bedding * chain.lengthM;
        final available = excavation - chainBedding - pipeDisplacement;
        if (available > 0) backfill += available;
      }
      if (type == 'Pipe drain' || type == 'Underground stormwater drain') {
        q['pipe_run'] = q['length'] ?? 0;
      } else {
        q['culvert_run'] = q['length'] ?? 0;
      }
      q['bedding'] = beddingVolume;
      q['backfill'] = backfill;
      if (type == 'Pipe culvert') {
        final ends = chains.length * 2.0;
        q['headwall_concrete'] =
            ends * (params['headwallConcretePerEndM3'] ?? 0);
        q['headwall_formwork'] =
            ends * (params['headwallFormworkPerEndM2'] ?? 0);
        q['apron_concrete'] = ends * (params['apronConcretePerEndM3'] ?? 0);
        q['headwall_reinforcement'] =
            (q['headwall_concrete'] ?? 0) *
            (params['headwallSteelKgM3'] ?? 120) /
            1000;
      }
    }

    // Optional associated stormwater manholes are measured as components
    // from the drawing-based Type 1 manhole detail.
    final manholeCount = params['manholeCount'] ?? 0;
    if (manholeCount > 0) {
      final clearM = (params['manholeClearMm'] ?? 600) / 1000;
      final wallM = (params['manholeWallMm'] ?? 230) / 1000;
      final depthM = (params['manholeDepthMm'] ?? 600) / 1000;
      final baseCourseM = (params['manholeBaseCourseMm'] ?? 150) / 1000;
      final invertM = (params['manholeInvertMm'] ?? 100) / 1000;
      final externalM = clearM + 2 * wallM;
      final centrelinePerimeterM = 4 * (clearM + wallM);
      final coverThicknessM = (params['manholeCoverThicknessMm'] ?? 120) / 1000;
      final coverWidthM = (params['manholeCoverWidthMm'] ?? 840) / 1000;
      final coverRebarRate = params['manholeCoverRebarKgM2'] ?? 10.5;
      final coverAreaPer = coverWidthM * coverWidthM;
      q['manhole_excavation'] =
          manholeCount *
          externalM *
          externalM *
          (depthM + baseCourseM + invertM);
      q['manhole_base_course'] =
          manholeCount * externalM * externalM * baseCourseM;
      q['manhole_invert_concrete'] =
          manholeCount * externalM * externalM * invertM;
      q['manhole_blockwork'] = manholeCount * centrelinePerimeterM * depthM;
      q['manhole_cover_concrete'] =
          manholeCount * coverAreaPer * coverThicknessM;
      q['manhole_cover_rebar'] =
          manholeCount * coverAreaPer * coverRebarRate / 1000;
    }

    final excavationTotal =
        (q['excavation_0_1_5'] ?? 0) +
        (q['excavation_1_5_3'] ?? 0) +
        (q['excavation_3_4_5'] ?? 0) +
        (q['excavation_4_5_6'] ?? 0);
    final rockFraction = (rockPercent / 100).clamp(0.0, 1.0).toDouble();
    q['rock_extra'] = excavationTotal * rockFraction;
    return q;
  }

  Future<void> _finishDrainageTakeoff(
    List<LengthDraftSegment> currentSegments,
  ) async {
    final context = Get.context;
    if (context == null || currentSegments.isEmpty) return;
    _drainSessionId ??= measurementsRef.doc().id;

    String drainType = _pendingDrainType;
    String profile = _pendingDrainProfile;
    String drainSystem = _drainSystemForType(drainType);
    if (!_drainProfilesForType(drainType).contains(profile)) {
      drainType = _drainTypeForProfile(profile);
      if (!_drainProfilesForType(drainType).contains(profile)) {
        profile = _drainProfilesForType(drainType).first;
      }
      drainSystem = _drainSystemForType(drainType);
    }

    final initialDefaults = _drainProfileDefaults(drainType, profile);
    double initial(String key, double fallback) =>
        _pendingDrainParams[key] ?? initialDefaults[key] ?? fallback;

    final bottomCtrl = TextEditingController(
      text: initial('bottomMm', 300).toStringAsFixed(0),
    );
    final startDepthCtrl = TextEditingController(
      text: initial('startDepthMm', 500).toStringAsFixed(0),
    );
    final endDepthCtrl = TextEditingController(
      text: initial('endDepthMm', 500).toStringAsFixed(0),
    );
    final slopeCtrl = TextEditingController(
      text: initial('sideSlopeH', 2).toStringAsFixed(2),
    );
    final thickCtrl = TextEditingController(
      text: initial('thicknessMm', 100).toStringAsFixed(0),
    );
    final meshCtrl = TextEditingController(
      text: initial('meshKgM2', 2.22).toStringAsFixed(2),
    );
    final expCtrl = TextEditingController(
      text: initial('expansionSpacingM', 20).toStringAsFixed(1),
    );
    final conCtrl = TextEditingController(
      text: initial('constructionSpacingM', 5).toStringAsFixed(1),
    );
    final bitumenCtrl = TextEditingController(
      text: initial('bitumenRateLpm2', 0.5).toStringAsFixed(2),
    );
    final formworkFactorCtrl = TextEditingController(
      text: initial('formworkSideFactorM2PerM', 0).toStringAsFixed(2),
    );
    final pavementCutEdgesCtrl = TextEditingController(
      text: initial('pavementCutEdges', 0).toStringAsFixed(0),
    );
    final kerbFactorCtrl = TextEditingController(
      text: initial('kerbPatternFactor', 2 / 3).toStringAsFixed(3),
    );
    final pavingWidthCtrl = TextEditingController(
      text: initial('pavingStripWidthMm', 1000).toStringAsFixed(0),
    );
    final sandCtrl = TextEditingController(
      text: initial('sandMm', 30).toStringAsFixed(0),
    );
    final g15Ctrl = TextEditingController(
      text: initial('g15Mm', 150).toStringAsFixed(0),
    );
    final subgradeCtrl = TextEditingController(
      text: initial('subgradeMm', 150).toStringAsFixed(0),
    );
    final blockWallCtrl = TextEditingController(
      text: initial('blockWallMm', 230).toStringAsFixed(0),
    );
    final baseCourseCtrl = TextEditingController(
      text: initial('baseCourseMm', 150).toStringAsFixed(0),
    );
    final baseCourseWidthCtrl = TextEditingController(
      text: initial('baseCourseWidthMm', 860).toStringAsFixed(0),
    );
    final coverWidthCtrl = TextEditingController(
      text: initial('coverWidthMm', 540).toStringAsFixed(0),
    );
    final coverThicknessCtrl = TextEditingController(
      text: initial('coverThicknessMm', 120).toStringAsFixed(0),
    );
    final coverRebarCtrl = TextEditingController(
      text: initial('coverRebarKgM2', 10.5).toStringAsFixed(2),
    );

    final wallCtrl = TextEditingController(
      text: initial('wallMm', 200).toStringAsFixed(0),
    );
    final baseCtrl = TextEditingController(
      text: initial('baseMm', 200).toStringAsFixed(0),
    );
    final coverCtrl = TextEditingController(
      text: initial('coverMm', 150).toStringAsFixed(0),
    );
    final blindingCtrl = TextEditingController(
      text: initial('blindingMm', 0).toStringAsFixed(0),
    );
    final allowanceCtrl = TextEditingController(
      text: initial('excavAllowanceMm', 300).toStringAsFixed(0),
    );
    final steelCtrl = TextEditingController(
      text: initial('steelKgM3', 120).toStringAsFixed(1),
    );
    final wallFacesCtrl = TextEditingController(
      text: initial('wallFormworkFaces', 4).toStringAsFixed(0),
    );

    final barrelsCtrl = TextEditingController(
      text: initial('barrels', 1).toStringAsFixed(0),
    );
    final diameterCtrl = TextEditingController(
      text: initial('diameterMm', 600).toStringAsFixed(0),
    );
    final barrelSpacingCtrl = TextEditingController(
      text: initial('barrelSpacingMm', 300).toStringAsFixed(0),
    );
    final beddingCtrl = TextEditingController(
      text: initial('beddingMm', 150).toStringAsFixed(0),
    );
    final headwallConcreteCtrl = TextEditingController(
      text: initial('headwallConcretePerEndM3', 0).toStringAsFixed(3),
    );
    final headwallFormworkCtrl = TextEditingController(
      text: initial('headwallFormworkPerEndM2', 0).toStringAsFixed(3),
    );
    final apronConcreteCtrl = TextEditingController(
      text: initial('apronConcretePerEndM3', 0).toStringAsFixed(3),
    );
    final headwallSteelCtrl = TextEditingController(
      text: initial('headwallSteelKgM3', 120).toStringAsFixed(1),
    );

    final sitePrepWidthCtrl = TextEditingController(
      text: initial('sitePrepWidthMm', 0).toStringAsFixed(0),
    );
    final siteWorkingAllowanceCtrl = TextEditingController(
      text: initial('siteWorkingAllowanceMm', 500).toStringAsFixed(0),
    );
    final topsoilCtrl = TextEditingController(
      text: initial('topsoilMm', 150).toStringAsFixed(0),
    );
    final commonExcavationCtrl = TextEditingController(
      text: initial('commonExcavationMm', 0).toStringAsFixed(0),
    );
    String associatedStructure =
        (_pendingDrainParams['manholeCount'] ?? 0) > 0
            ? 'Stormwater manhole - Type 1'
            : 'None';
    final manholeCountCtrl = TextEditingController(
      text: initial('manholeCount', 0).toStringAsFixed(0),
    );
    final manholeDepthCtrl = TextEditingController(
      text: initial('manholeDepthMm', 600).toStringAsFixed(0),
    );
    final manholeClearCtrl = TextEditingController(
      text: initial('manholeClearMm', 600).toStringAsFixed(0),
    );
    final manholeWallCtrl = TextEditingController(
      text: initial('manholeWallMm', 230).toStringAsFixed(0),
    );
    final manholeInvertCtrl = TextEditingController(
      text: initial('manholeInvertMm', 100).toStringAsFixed(0),
    );
    final manholeBaseCourseCtrl = TextEditingController(
      text: initial('manholeBaseCourseMm', 150).toStringAsFixed(0),
    );
    final manholeCoverThicknessCtrl = TextEditingController(
      text: initial('manholeCoverThicknessMm', 120).toStringAsFixed(0),
    );
    final manholeCoverWidthCtrl = TextEditingController(
      text: initial('manholeCoverWidthMm', 840).toStringAsFixed(0),
    );
    final manholeCoverRebarCtrl = TextEditingController(
      text: initial('manholeCoverRebarKgM2', 10.5).toStringAsFixed(2),
    );
    bool includeClearing = (_pendingDrainParams['includeClearing'] ?? 0) > 0;
    bool includeTopsoil = (_pendingDrainParams['includeTopsoil'] ?? 0) > 0;
    bool includeCommonExcavation =
        (_pendingDrainParams['includeCommonExcavation'] ?? 0) > 0;
    bool closedCompositeMode =
        (_pendingDrainParams['closedCompositeMode'] ?? 1) > 0;
    bool closedCompositeIncludesFormwork =
        (_pendingDrainParams['closedCompositeIncludesFormwork'] ?? 1) > 0;

    String excavationMaterial =
        (_pendingDrainParams['rockPercent'] ?? 0) >= 100
            ? 'Rock'
            : ((_pendingDrainParams['rockPercent'] ?? 0) > 0
                ? 'Mixed'
                : 'Soft');
    final rockCtrl = TextEditingController(
      text: (_pendingDrainParams['rockPercent'] ?? 0).toStringAsFixed(0),
    );
    String backfillMaterial = 'Excavated material';
    if ((_pendingDrainParams['backfillSelected'] ?? 0) > 0) {
      backfillMaterial = 'Selected imported material';
    } else if ((_pendingDrainParams['backfillSoilCement'] ?? 0) > 0) {
      backfillMaterial = 'Soil cement';
    }

    String? error;
    final boqs = Map<String, BoqPick>.from(
      _pendingDrainBoqs.isNotEmpty
          ? _pendingDrainBoqs
          : (_lastDrainBoqsByProfile[_drainBoqProfileKey(drainType, profile)] ??
              const <String, BoqPick>{}),
    );
    // Backward compatibility with sessions created before topsoil removal/disposal
    // were merged into one BOQ output.
    if (!boqs.containsKey('topsoil_remove') &&
        boqs.containsKey('topsoil_disposal')) {
      boqs['topsoil_remove'] = boqs['topsoil_disposal']!;
    }
    boqs.remove('topsoil_disposal');

    double n(TextEditingController c, double fallback) =>
        double.tryParse(c.text.trim()) ?? fallback;

    void applyProfileDefaults(
      String newType,
      String newProfile, {
      bool keepDepth = true,
    }) {
      final defaults = _drainProfileDefaults(newType, newProfile);
      final oldStart = startDepthCtrl.text;
      final oldEnd = endDepthCtrl.text;
      void set(TextEditingController c, String key, double fallback) {
        c.text = (defaults[key] ?? fallback).toStringAsFixed(
          key.contains('Slope') || key.contains('Kg') ? 2 : 0,
        );
      }

      set(bottomCtrl, 'bottomMm', 300);
      set(slopeCtrl, 'sideSlopeH', 2);
      set(thickCtrl, 'thicknessMm', 100);
      set(meshCtrl, 'meshKgM2', 2.22);
      expCtrl.text = (defaults['expansionSpacingM'] ?? 20).toStringAsFixed(1);
      conCtrl.text = (defaults['constructionSpacingM'] ?? 5).toStringAsFixed(1);
      bitumenCtrl.text = (defaults['bitumenRateLpm2'] ?? 0.5).toStringAsFixed(
        2,
      );
      formworkFactorCtrl.text = (defaults['formworkSideFactorM2PerM'] ?? 0)
          .toStringAsFixed(2);
      pavementCutEdgesCtrl.text = (defaults['pavementCutEdges'] ?? 0)
          .toStringAsFixed(0);
      kerbFactorCtrl.text = (defaults['kerbPatternFactor'] ?? 0)
          .toStringAsFixed(3);
      set(pavingWidthCtrl, 'pavingStripWidthMm', 0);
      set(sandCtrl, 'sandMm', 0);
      set(g15Ctrl, 'g15Mm', 0);
      set(subgradeCtrl, 'subgradeMm', 0);
      set(blockWallCtrl, 'blockWallMm', 230);
      set(baseCourseCtrl, 'baseCourseMm', 150);
      set(baseCourseWidthCtrl, 'baseCourseWidthMm', 860);
      set(coverWidthCtrl, 'coverWidthMm', 540);
      set(coverThicknessCtrl, 'coverThicknessMm', 120);
      coverRebarCtrl.text = (defaults['coverRebarKgM2'] ?? 10.5)
          .toStringAsFixed(2);
      set(wallCtrl, 'wallMm', 200);
      set(baseCtrl, 'baseMm', 200);
      set(coverCtrl, 'coverMm', 150);
      set(blindingCtrl, 'blindingMm', 0);
      set(allowanceCtrl, 'excavAllowanceMm', 300);
      steelCtrl.text = (defaults['steelKgM3'] ?? 120).toStringAsFixed(1);
      set(wallFacesCtrl, 'wallFormworkFaces', 4);
      barrelsCtrl.text = (defaults['barrels'] ?? 1).toStringAsFixed(0);
      diameterCtrl.text = (defaults['diameterMm'] ?? 600).toStringAsFixed(0);
      set(barrelSpacingCtrl, 'barrelSpacingMm', 300);
      set(beddingCtrl, 'beddingMm', 150);
      headwallConcreteCtrl.text = (defaults['headwallConcretePerEndM3'] ?? 0)
          .toStringAsFixed(3);
      headwallFormworkCtrl.text = (defaults['headwallFormworkPerEndM2'] ?? 0)
          .toStringAsFixed(3);
      apronConcreteCtrl.text = (defaults['apronConcretePerEndM3'] ?? 0)
          .toStringAsFixed(3);
      headwallSteelCtrl.text = (defaults['headwallSteelKgM3'] ?? 120)
          .toStringAsFixed(1);
      if (!keepDepth) {
        startDepthCtrl.text = (defaults['startDepthMm'] ?? 500).toStringAsFixed(
          0,
        );
        endDepthCtrl.text = (defaults['endDepthMm'] ?? 500).toStringAsFixed(0);
      } else {
        startDepthCtrl.text = oldStart;
        endDepthCtrl.text = oldEnd;
      }
    }

    void applyRememberedBoqMappings(String newType, String newProfile) {
      final remembered =
          _lastDrainBoqsByProfile[_drainBoqProfileKey(newType, newProfile)];
      boqs.clear();
      if (remembered != null) boqs.addAll(remembered);
    }

    Map<String, double> paramsFromFields() {
      final profileDefaults = _drainProfileDefaults(drainType, profile);
      return <String, double>{
        ...profileDefaults,
        'bottomMm': n(bottomCtrl, profileDefaults['bottomMm'] ?? 300),
        'startDepthMm': n(startDepthCtrl, 500),
        'endDepthMm': n(endDepthCtrl, 500),
        'sideSlopeH': n(slopeCtrl, 2),
        'thicknessMm': n(thickCtrl, 100),
        'meshKgM2': n(meshCtrl, 2.22),
        'expansionSpacingM': n(expCtrl, 20),
        'constructionSpacingM': n(conCtrl, 5),
        'bitumenRateLpm2': n(bitumenCtrl, 0.5),
        'formworkSideFactorM2PerM': n(formworkFactorCtrl, 0),
        'pavementCutEdges': n(pavementCutEdgesCtrl, 0),
        'kerbPatternFactor': n(kerbFactorCtrl, 2 / 3),
        'pavingStripWidthMm': n(pavingWidthCtrl, 1000),
        'sandMm': n(sandCtrl, 30),
        'g15Mm': n(g15Ctrl, 150),
        'subgradeMm': n(subgradeCtrl, 150),
        'blockWallMm': n(blockWallCtrl, 230),
        'baseCourseMm': n(baseCourseCtrl, 150),
        'baseCourseWidthMm': n(baseCourseWidthCtrl, 860),
        'coverWidthMm': n(coverWidthCtrl, 540),
        'coverThicknessMm': n(coverThicknessCtrl, 120),
        'coverRebarKgM2': n(coverRebarCtrl, 10.5),
        'wallMm': n(wallCtrl, 200),
        'baseMm': n(baseCtrl, 200),
        'coverMm': n(coverCtrl, 150),
        'blindingMm': n(blindingCtrl, 0),
        'excavAllowanceMm': n(allowanceCtrl, 300),
        'steelKgM3': n(steelCtrl, 120),
        'wallFormworkFaces': n(wallFacesCtrl, 4),
        'barrels': n(barrelsCtrl, profileDefaults['barrels'] ?? 1),
        'diameterMm': n(diameterCtrl, profileDefaults['diameterMm'] ?? 600),
        'barrelSpacingMm': n(barrelSpacingCtrl, 300),
        'beddingMm': n(beddingCtrl, 150),
        'headwallConcretePerEndM3': n(headwallConcreteCtrl, 0),
        'headwallFormworkPerEndM2': n(headwallFormworkCtrl, 0),
        'apronConcretePerEndM3': n(apronConcreteCtrl, 0),
        'headwallSteelKgM3': n(headwallSteelCtrl, 120),
        'sitePrepWidthMm': n(sitePrepWidthCtrl, 0),
        'siteWorkingAllowanceMm': n(siteWorkingAllowanceCtrl, 500),
        'topsoilMm': n(topsoilCtrl, 150),
        'commonExcavationMm': n(commonExcavationCtrl, 0),
        'manholeCount':
            associatedStructure == 'Stormwater manhole - Type 1'
                ? n(manholeCountCtrl, 0)
                : 0,
        'manholeDepthMm': n(manholeDepthCtrl, 600),
        'manholeClearMm': n(manholeClearCtrl, 600),
        'manholeWallMm': n(manholeWallCtrl, 230),
        'manholeInvertMm': n(manholeInvertCtrl, 100),
        'manholeBaseCourseMm': n(manholeBaseCourseCtrl, 150),
        'manholeCoverThicknessMm': n(manholeCoverThicknessCtrl, 120),
        'manholeCoverWidthMm': n(manholeCoverWidthCtrl, 840),
        'manholeCoverRebarKgM2': n(manholeCoverRebarCtrl, 10.5),
        'includeClearing': includeClearing ? 1 : 0,
        'includeTopsoil': includeTopsoil ? 1 : 0,
        'includeCommonExcavation': includeCommonExcavation ? 1 : 0,
        'closedCompositeMode': closedCompositeMode ? 1 : 0,
        'closedCompositeIncludesFormwork':
            closedCompositeIncludesFormwork ? 1 : 0,
        'rockPercent':
            excavationMaterial == 'Rock'
                ? 100
                : (excavationMaterial == 'Mixed' ? n(rockCtrl, 20) : 0),
        'backfillSelected':
            backfillMaterial == 'Selected imported material' ? 1 : 0,
        'backfillSoilCement': backfillMaterial == 'Soil cement' ? 1 : 0,
      };
    }

    _PendingDrainChain previewChain() => _PendingDrainChain(
      id: measurementsRef.doc().id,
      segments: List<LengthDraftSegment>.of(currentSegments),
      startDepthM: n(startDepthCtrl, 500) / 1000,
      endDepthM: n(endDepthCtrl, 500) / 1000,
    );

    String visualTab = 'Section';

    final action = await showDialog<_DrainSessionAction>(
      context: context,
      barrierDismissible: false,
      builder:
          (dc) => StatefulBuilder(
            builder: (dc, setState) {
              final params = paramsFromFields();
              final chains = <_PendingDrainChain>[
                ..._pendingDrainChains,
                previewChain(),
              ];
              final q = _calculateDrainQuantities(
                type: drainType,
                profile: profile,
                chains: chains,
                params: params,
                rockPercent: params['rockPercent'] ?? 0,
              );
              final labels = _drainOutputLabels(
                drainType,
                profile,
                backfillMaterial,
              );
              final activeEntries = labels.entries
                  .where((entry) => (q[entry.key] ?? 0).abs() > 0.0000001)
                  .toList(growable: false);

              Widget field(
                String label,
                TextEditingController controller, {
                String suffix = 'mm',
                double width = 185,
              }) => SizedBox(
                width: width,
                child: TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: label,
                    suffixText: suffix,
                    border: const OutlineInputBorder(),
                  ),
                ),
              );

              List<Widget> geometryFields() {
                if (drainType == 'Open masonry / blockwork drain') {
                  final fields = <Widget>[
                    field('Clear internal width', bottomCtrl),
                    field('Start drain depth', startDepthCtrl),
                    field('End drain depth', endDepthCtrl),
                    field('Block wall thickness', blockWallCtrl),
                    field('Concrete invert thickness', thickCtrl),
                    field('Base course thickness', baseCourseCtrl),
                    field('Base course width', baseCourseWidthCtrl),
                  ];
                  if (profile.startsWith('Blockwork Covered')) {
                    fields.addAll(<Widget>[
                      field('Precast cover width', coverWidthCtrl),
                      field('Precast cover thickness', coverThicknessCtrl),
                      field(
                        'Cover reinforcement allowance',
                        coverRebarCtrl,
                        suffix: 'kg/m2',
                      ),
                    ]);
                  }
                  return fields;
                }
                if (drainType == 'Open lined drain' ||
                    drainType == 'Concrete channel / channelling') {
                  final isChannel =
                      drainType == 'Concrete channel / channelling';
                  final fields = <Widget>[
                    field('Bottom width', bottomCtrl),
                    field('Start depth', startDepthCtrl),
                    field('End depth', endDepthCtrl),
                    field('Side slope H:1V', slopeCtrl, suffix: 'H'),
                    field(
                      isChannel
                          ? 'Channel concrete thickness'
                          : 'Concrete thickness',
                      thickCtrl,
                    ),
                    field('Fabric / rebar rate', meshCtrl, suffix: 'kg/m2'),
                    field('Expansion joint spacing', expCtrl, suffix: 'm'),
                    field('Construction joint spacing', conCtrl, suffix: 'm'),
                    field('Bitumen rate', bitumenCtrl, suffix: 'L/m2'),
                    field(
                      'Formwork factor',
                      formworkFactorCtrl,
                      suffix: 'm2/m',
                    ),
                    field(
                      'Pavement cut edges',
                      pavementCutEdgesCtrl,
                      suffix: 'No.',
                    ),
                  ];
                  if (!isChannel &&
                      profile.contains('Type 1') &&
                      profile.contains('Block wall')) {
                    return <Widget>[
                      field('Internal drain width', bottomCtrl),
                      field('Start clear depth', startDepthCtrl),
                      field('End clear depth', endDepthCtrl),
                      field('Block wall thickness', blockWallCtrl),
                      field('Invert concrete thickness', thickCtrl),
                      field('Base course thickness', baseCourseCtrl),
                      field('Base course width', baseCourseWidthCtrl),
                      field('Precast cover width', coverWidthCtrl),
                      field('Precast cover thickness', coverThicknessCtrl),
                      field(
                        'Cover reinforcement allowance',
                        coverRebarCtrl,
                        suffix: 'kg/m2',
                      ),
                    ];
                  }
                  return fields;
                }
                if (drainType == 'Earth drain') {
                  return <Widget>[
                    field('Bottom width', bottomCtrl),
                    field('Start depth', startDepthCtrl),
                    field('End depth', endDepthCtrl),
                    field('Side slope H:1V', slopeCtrl, suffix: 'H'),
                  ];
                }
                if (drainType == 'Closed concrete drain') {
                  return <Widget>[
                    field('Internal width', bottomCtrl),
                    field('Start clear depth', startDepthCtrl),
                    field('End clear depth', endDepthCtrl),
                    field('Wall thickness', wallCtrl),
                    field('Base thickness', baseCtrl),
                    field('Cover slab width', coverWidthCtrl),
                    field('Cover slab thickness', coverCtrl),
                    field('Blinding thickness (optional)', blindingCtrl),
                    field('Excavation allowance each side', allowanceCtrl),
                    field(
                      'Rebar allowance (manual)',
                      steelCtrl,
                      suffix: 'kg/m3',
                    ),
                    field('Wall formwork faces', wallFacesCtrl, suffix: 'No.'),
                    field('Expansion joint spacing', expCtrl, suffix: 'm'),
                    field('Construction joint spacing', conCtrl, suffix: 'm'),
                  ];
                }
                return <Widget>[
                  field('Start trench depth', startDepthCtrl),
                  field('End trench depth', endDepthCtrl),
                  field('Pipe diameter', diameterCtrl, suffix: 'mm'),
                  field('No. barrels', barrelsCtrl, suffix: 'No.'),
                  field('Barrel spacing', barrelSpacingCtrl),
                  field('Excavation allowance each side', allowanceCtrl),
                  field('Bedding thickness', beddingCtrl),
                  field(
                    'Headwall concrete / end',
                    headwallConcreteCtrl,
                    suffix: 'm3',
                  ),
                  field(
                    'Headwall formwork / end',
                    headwallFormworkCtrl,
                    suffix: 'm2',
                  ),
                  field(
                    'Apron concrete / end',
                    apronConcreteCtrl,
                    suffix: 'm3',
                  ),
                  field(
                    'Headwall rebar allowance',
                    headwallSteelCtrl,
                    suffix: 'kg/m3',
                  ),
                ];
              }

              return AlertDialog(
                title: const Text('Drainage take-off'),
                content: SizedBox(
                  width:
                      math
                          .min(MediaQuery.of(dc).size.width - 120, 1240.0)
                          .toDouble(),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            Chip(
                              label: Text(
                                'Current ${previewChain().lengthM.toStringAsFixed(3)} m',
                              ),
                            ),
                            Chip(
                              label: Text(
                                'Chains ${_pendingDrainChains.length + 1}',
                              ),
                            ),
                            Chip(
                              label: Text(
                                'Total ${(q['length'] ?? 0).toStringAsFixed(3)} m',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: <Widget>[
                            SizedBox(
                              width: 270,
                              child: DropdownButtonFormField<String>(
                                value: drainSystem,
                                decoration: const InputDecoration(
                                  labelText: 'Drainage system',
                                  border: OutlineInputBorder(),
                                ),
                                items:
                                    const <String>[
                                          'Surface drainage',
                                          'Underground drainage',
                                          'Cross-drainage',
                                        ]
                                        .map(
                                          (e) => DropdownMenuItem<String>(
                                            value: e,
                                            child: Text(e),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() {
                                    drainSystem = v;
                                    drainType = _drainTypesForSystem(v).first;
                                    profile =
                                        _drainProfilesForType(drainType).first;
                                    applyProfileDefaults(
                                      drainType,
                                      profile,
                                      keepDepth: false,
                                    );
                                    applyRememberedBoqMappings(
                                      drainType,
                                      profile,
                                    );
                                  });
                                },
                              ),
                            ),
                            SizedBox(
                              width: 290,
                              child: DropdownButtonFormField<String>(
                                value: drainType,
                                decoration: const InputDecoration(
                                  labelText: 'Drain type',
                                  border: OutlineInputBorder(),
                                ),
                                items:
                                    _drainTypesForSystem(drainSystem)
                                        .map(
                                          (e) => DropdownMenuItem<String>(
                                            value: e,
                                            child: Text(e),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() {
                                    drainType = v;
                                    profile = _drainProfilesForType(v).first;
                                    applyProfileDefaults(
                                      v,
                                      profile,
                                      keepDepth: false,
                                    );
                                    applyRememberedBoqMappings(v, profile);
                                  });
                                },
                              ),
                            ),
                            SizedBox(
                              width: 310,
                              child: DropdownButtonFormField<String>(
                                value: profile,
                                decoration: const InputDecoration(
                                  labelText: 'Profile',
                                  border: OutlineInputBorder(),
                                ),
                                items:
                                    _drainProfilesForType(drainType)
                                        .map(
                                          (e) => DropdownMenuItem<String>(
                                            value: e,
                                            child: Text(e),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() {
                                    profile = v;
                                    applyProfileDefaults(drainType, profile);
                                    applyRememberedBoqMappings(
                                      drainType,
                                      profile,
                                    );
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _DrainageVisualPanel(
                          tab: visualTab,
                          onTabChanged:
                              (value) => setState(() => visualTab = value),
                          type: drainType,
                          profile: profile,
                          bottomMm: n(bottomCtrl, 300),
                          depthMm:
                              (n(startDepthCtrl, 500) + n(endDepthCtrl, 500)) /
                              2,
                          sideSlopeH: n(slopeCtrl, 2),
                          wallMm:
                              drainType == 'Closed concrete drain'
                                  ? n(wallCtrl, 200)
                                  : n(blockWallCtrl, 230),
                          baseMm:
                              drainType == 'Closed concrete drain'
                                  ? n(baseCtrl, 200)
                                  : n(thickCtrl, 100),
                          coverMm: n(coverCtrl, 150),
                          thicknessMm: n(thickCtrl, 100),
                          diameterMm: n(diameterCtrl, 600),
                          barrels: n(barrelsCtrl, 1).round(),
                          quantities: q,
                          labels: Map<String, String>.fromEntries(
                            activeEntries,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Geometry / section parameters',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: geometryFields(),
                        ),
                        if (drainType == 'Closed concrete drain') ...<Widget>[
                          const SizedBox(height: 14),
                          const Text(
                            'BOQ measurement / payment mode',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value:
                                closedCompositeMode
                                    ? 'Composite'
                                    : 'Components',
                            decoration: const InputDecoration(
                              labelText: 'Closed-drain BOQ mode',
                              border: OutlineInputBorder(),
                            ),
                            items: const <DropdownMenuItem<String>>[
                              DropdownMenuItem(
                                value: 'Composite',
                                child: Text('Composite structural concrete'),
                              ),
                              DropdownMenuItem(
                                value: 'Components',
                                child: Text('Measure by components'),
                              ),
                            ],
                            onChanged:
                                (v) => setState(() {
                                  closedCompositeMode = v != 'Components';
                                }),
                          ),
                          if (closedCompositeMode)
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: closedCompositeIncludesFormwork,
                              onChanged:
                                  (v) => setState(
                                    () =>
                                        closedCompositeIncludesFormwork =
                                            v ?? true,
                                  ),
                              title: const Text(
                                'Selected structural-concrete BOQ rate includes formwork',
                              ),
                              subtitle: const Text(
                                'When enabled, separate wall and cover-soffit formwork outputs are hidden to prevent double counting.',
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Composite mode combines base slab + walls + cover slab for BOQ payment while retaining the detailed geometry for calculation. Blinding, reinforcement, earthworks, backfill, joints and other applicable outputs remain separate.',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        const Text(
                          'Associated structures',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: associatedStructure,
                          decoration: const InputDecoration(
                            labelText: 'Associated structure',
                            border: OutlineInputBorder(),
                          ),
                          items:
                              const <String>[
                                    'None',
                                    'Stormwater manhole - Type 1',
                                  ]
                                  .map(
                                    (e) => DropdownMenuItem<String>(
                                      value: e,
                                      child: Text(e),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              (v) => setState(() {
                                associatedStructure = v ?? 'None';
                                if (associatedStructure != 'None' &&
                                    n(manholeCountCtrl, 0) <= 0) {
                                  manholeCountCtrl.text = '1';
                                }
                              }),
                        ),
                        if (associatedStructure ==
                            'Stormwater manhole - Type 1') ...<Widget>[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: <Widget>[
                              field(
                                'Manhole count',
                                manholeCountCtrl,
                                suffix: 'No.',
                              ),
                              field('Clear opening', manholeClearCtrl),
                              field('Manhole depth', manholeDepthCtrl),
                              field('Block wall thickness', manholeWallCtrl),
                              field(
                                'Invert concrete thickness',
                                manholeInvertCtrl,
                              ),
                              field(
                                'Base course thickness',
                                manholeBaseCourseCtrl,
                              ),
                              field(
                                'Overall cover width',
                                manholeCoverWidthCtrl,
                              ),
                              field(
                                'Precast cover thickness',
                                manholeCoverThicknessCtrl,
                              ),
                              field(
                                'Cover reinforcement allowance',
                                manholeCoverRebarCtrl,
                                suffix: 'kg/m2',
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'Defaults follow the uploaded Inala Type 1 stormwater manhole detail and remain editable.',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        const Text(
                          'Optional site preparation / preliminary earthworks',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          children: <Widget>[
                            SizedBox(
                              width: 220,
                              child: CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: includeClearing,
                                onChanged:
                                    (v) => setState(
                                      () => includeClearing = v ?? true,
                                    ),
                                title: const Text('Clearing & grubbing'),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                            ),
                            SizedBox(
                              width: 220,
                              child: CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: includeTopsoil,
                                onChanged:
                                    (v) => setState(
                                      () => includeTopsoil = v ?? true,
                                    ),
                                title: const Text('Remove & dispose topsoil'),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                            ),
                            SizedBox(
                              width: 240,
                              child: CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: includeCommonExcavation,
                                onChanged:
                                    (v) => setState(
                                      () =>
                                          includeCommonExcavation = v ?? false,
                                    ),
                                title: const Text('Common excavation'),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: <Widget>[
                            field(
                              'Site prep width override (0 = Auto)',
                              sitePrepWidthCtrl,
                            ),
                            if (sitePrepWidthCtrl.text.trim().isEmpty ||
                                n(sitePrepWidthCtrl, 0) <= 0)
                              field(
                                'Working allowance each side',
                                siteWorkingAllowanceCtrl,
                              ),
                            if (includeTopsoil)
                              field('Topsoil thickness', topsoilCtrl),
                            if (includeCommonExcavation)
                              field(
                                'Common excavation depth',
                                commonExcavationCtrl,
                              ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'Use these only for standalone drainage works. Where the drain is within a measured road corridor, leave them off so road earthworks are not counted twice.',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: excavationMaterial,
                                decoration: const InputDecoration(
                                  labelText: 'Excavation material',
                                  border: OutlineInputBorder(),
                                ),
                                items:
                                    const <String>['Soft', 'Mixed', 'Rock']
                                        .map(
                                          (e) => DropdownMenuItem<String>(
                                            value: e,
                                            child: Text(e),
                                          ),
                                        )
                                        .toList(),
                                onChanged:
                                    (v) => setState(
                                      () =>
                                          excavationMaterial =
                                              v ?? excavationMaterial,
                                    ),
                              ),
                            ),
                            if (excavationMaterial == 'Mixed') ...<Widget>[
                              const SizedBox(width: 10),
                              field('Rock portion', rockCtrl, suffix: '%'),
                            ],
                            if (drainType == 'Pipe culvert' ||
                                drainType == 'Pipe drain' ||
                                drainType ==
                                    'Underground stormwater drain') ...<Widget>[
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: backfillMaterial,
                                  decoration: const InputDecoration(
                                    labelText: 'Backfill material',
                                    border: OutlineInputBorder(),
                                  ),
                                  items:
                                      const <String>[
                                            'Excavated material',
                                            'Selected imported material',
                                            'Soil cement',
                                          ]
                                          .map(
                                            (e) => DropdownMenuItem<String>(
                                              value: e,
                                              child: Text(e),
                                            ),
                                          )
                                          .toList(),
                                  onChanged:
                                      (v) => setState(
                                        () =>
                                            backfillMaterial =
                                                v ?? backfillMaterial,
                                      ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Calculated BOQ outputs',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...activeEntries.map((entry) {
                          final qty = q[entry.key] ?? 0;
                          final unit = _drainOutputUnit(entry.key);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Row(
                              children: <Widget>[
                                Expanded(flex: 4, child: Text(entry.value)),
                                SizedBox(
                                  width: 135,
                                  child: Text(
                                    '${qty.toStringAsFixed(unit == 'ton' ? 4 : 3)} $unit',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        boqs[entry.key]?.code ??
                                            'No BOQ selected',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (boqs[entry.key] == null &&
                                          _drainSuggestedBoqCode(
                                                drainType,
                                                profile,
                                                entry.key,
                                                backfillMaterial,
                                              ) !=
                                              null)
                                        Text(
                                          'Suggested: ${_drainSuggestedBoqCode(drainType, profile, entry.key, backfillMaterial)}',
                                          style: const TextStyle(
                                            color: Color(0xFF64748B),
                                            fontSize: 11,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: () async {
                                    final picked = await it.showBoqPickerDialog(
                                      context: dc,
                                      expectedUnit: unit,
                                    );
                                    if (picked != null && dc.mounted) {
                                      setState(() => boqs[entry.key] = picked);
                                    }
                                  },
                                  child: const Text('Pick'),
                                ),
                              ],
                            ),
                          );
                        }),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        const SizedBox(height: 8),
                        const Text(
                          'Changing Drainage type, Profile or Closed-drain BOQ mode recalculates the output list and quantities immediately. Zero/hidden outputs are not committed. Only visible outputs with a BOQ selected are committed.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed:
                        () => Navigator.pop(dc, _DrainSessionAction.cancel),
                    child: const Text('Cancel session'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      final activeKeys =
                          activeEntries.map((e) => e.key).toSet();
                      if (!boqs.keys.any(activeKeys.contains)) {
                        setState(
                          () => error = 'Pick at least one visible BOQ output.',
                        );
                        return;
                      }
                      Navigator.pop(dc, _DrainSessionAction.addAnother);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Save temporary & measure another'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      final activeKeys =
                          activeEntries.map((e) => e.key).toSet();
                      if (!boqs.keys.any(activeKeys.contains)) {
                        setState(
                          () => error = 'Pick at least one visible BOQ output.',
                        );
                        return;
                      }
                      Navigator.pop(dc, _DrainSessionAction.commit);
                    },
                    icon: const Icon(Icons.cloud_done_outlined),
                    label: Text(
                      'Commit all (${_pendingDrainChains.length + 1})',
                    ),
                  ),
                ],
              );
            },
          ),
    );

    if (action == null || action == _DrainSessionAction.cancel) {
      _clearDrainSession();
      clearDraftLength();
      return;
    }

    final params = paramsFromFields();
    final activeLabels = _drainOutputLabels(
      drainType,
      profile,
      backfillMaterial,
    );
    _pendingDrainType = drainType;
    _pendingDrainProfile = profile;
    _lastDrainBoqsByProfile[_drainBoqProfileKey(
      drainType,
      profile,
    )] = Map<String, BoqPick>.fromEntries(
      boqs.entries.where((entry) => activeLabels.containsKey(entry.key)),
    );
    _pendingDrainBoqs
      ..clear()
      ..addEntries(
        boqs.entries.where((entry) => activeLabels.containsKey(entry.key)),
      );
    _pendingDrainParams = params;
    _pendingDrainChains.add(previewChain());

    if (action == _DrainSessionAction.addAnother) {
      _draftLenP1.value = null;
      _draftLenP2.value = null;
      _draftLengthPoints.clear();
      _draftIndependentSegments.clear();
      update(['overlay', 'viewer', 'summary']);
      Get.snackbar(
        'Drain chain added',
        '${_pendingDrainChains.length} chain(s) temporary. Measure the next drain run.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    if (await _commitDrainSession()) {
      Get.snackbar(
        'Drainage saved',
        '$_pendingDrainProfile BOQ quantities committed.',
        snackPosition: SnackPosition.BOTTOM,
      );
      _clearDrainSession();
      clearDraftLength();
      update(['overlay', 'viewer', 'summary']);
    }
  }

  Future<bool> _commitDrainSession() async {
    if (_pendingDrainChains.isEmpty ||
        _drainSessionId == null ||
        _pendingDrainBoqs.isEmpty) {
      return false;
    }

    final backfillMaterial =
        (_pendingDrainParams['backfillSelected'] ?? 0) > 0
            ? 'Selected imported material'
            : ((_pendingDrainParams['backfillSoilCement'] ?? 0) > 0
                ? 'Soil cement'
                : 'Excavated material');
    final labels = _drainOutputLabels(
      _pendingDrainType,
      _pendingDrainProfile,
      backfillMaterial,
    );
    final q = _calculateDrainQuantities(
      type: _pendingDrainType,
      profile: _pendingDrainProfile,
      chains: _pendingDrainChains,
      params: _pendingDrainParams,
      rockPercent: _pendingDrainParams['rockPercent'] ?? 0,
    );

    try {
      final batch = FirebaseFirestore.instance.batch();
      final now = FieldValue.serverTimestamp();
      var drainageGeometryWritten = false;
      for (final entry in _pendingDrainBoqs.entries) {
        final key = entry.key;
        if (!labels.containsKey(key)) continue;
        final boq = entry.value;
        if (boq.code.trim().isEmpty) continue;
        final value = q[key] ?? 0;
        if (value.abs() <= 0.0000001) continue;
        final ref = measurementsRef.doc();
        batch.set(ref, <String, dynamic>{
          'projectId': projectId,
          'buildingId': buildingId,
          'drawingId': drawingId,
          'measureType': 'drainage',
          'activeMeasureType': 'drainage',
          'type': 'drainage',
          'drainageSessionId': _drainSessionId,
          'drainageSystem': _drainSystemForType(_pendingDrainType),
          'drainageType': _pendingDrainType,
          'drainProfile': _pendingDrainProfile,
          'drainOutputKey': key,
          'label': labels[key] ?? key,
          'unit': _drainOutputUnit(key),
          'value': value,
          'groupValue': value,
          'drainLengthM': q['length'] ?? 0,
          'boqCode': boq.code.trim(),
          'boqCodeRaw': boq.code.trim(),
          'boqCodeNorm': boq.code.replaceAll(RegExp(r'\s+'), '').trim(),
          'boqDescription': boq.description.trim(),
          'excavationMaterial':
              (_pendingDrainParams['rockPercent'] ?? 0) >= 100
                  ? 'Rock'
                  : ((_pendingDrainParams['rockPercent'] ?? 0) > 0
                      ? 'Mixed'
                      : 'Soft'),
          'rockPercent': _pendingDrainParams['rockPercent'] ?? 0,
          'backfillMaterial': backfillMaterial,
          'drainParameters': Map<String, double>.from(_pendingDrainParams),
          // Store one drawable copy of the physical drain geometry for the session.
          // BOQ output documents after the first deliberately omit it so the same
          // drain is not painted once for every mapped BOQ item.
          if (!drainageGeometryWritten)
            'polylineSegments': _pendingDrainChains
                .expand((c) => c.segments)
                .map(
                  (s) => <String, dynamic>{
                    'p1': <String, double>{'x': s.p1.dx, 'y': s.p1.dy},
                    'p2': <String, double>{'x': s.p2.dx, 'y': s.p2.dy},
                    'lengthM': s.lengthM,
                  },
                )
                .toList(growable: false),
          if (!drainageGeometryWritten) 'lengthM': q['length'] ?? 0,
          if (!drainageGeometryWritten) 'lengthGroupId': _drainSessionId,
          'chains':
              _pendingDrainChains
                  .map(
                    (c) => <String, dynamic>{
                      'id': c.id,
                      'lengthM': c.lengthM,
                      'startDepthM': c.startDepthM,
                      'endDepthM': c.endDepthM,
                      'segments':
                          c.segments
                              .map(
                                (s) => <String, dynamic>{
                                  'p1': <String, double>{
                                    'x': s.p1.dx,
                                    'y': s.p1.dy,
                                  },
                                  'p2': <String, double>{
                                    'x': s.p2.dx,
                                    'y': s.p2.dy,
                                  },
                                  'lengthM': s.lengthM,
                                },
                              )
                              .toList(),
                    },
                  )
                  .toList(),
          'createdAt': now,
          'updatedAt': now,
        });
        if (!drainageGeometryWritten) drainageGeometryWritten = true;
      }
      await batch.commit();
      return true;
    } catch (e) {
      Get.snackbar(
        'Drainage save failed',
        '$e',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }
  }

  void _clearDrainSession() {
    _pendingDrainChains.clear();
    _drainSessionId = null;
  }

  Future<void> _finishRoofMemberDrafts({
    required Map<String, dynamic> drawingData,
    required List<LengthDraftSegment> segments,
    required bool timber,
  }) async {
    final context = Get.context;
    if (context == null) return;
    _lengthChainGroupId ??= measurementsRef.doc().id;

    final totalChainLengthM = segments.fold<double>(
      0.0,
      (sum, segment) => sum + segment.lengthM,
    );
    final polylineSegments = segments
        .map(
          (segment) => <String, dynamic>{
            'p1': {'x': segment.p1.dx, 'y': segment.p1.dy},
            'p2': {'x': segment.p2.dx, 'y': segment.p2.dy},
            'lengthM': segment.lengthM,
          },
        )
        .toList(growable: false);
    final dynamic result =
        timber
            ? await showTimberRoofMemberMeasurementDialog(
              context: context,
              projectId: projectId,
              buildingId: buildingId,
              drawingId: drawingId,
              drawingTitle: drawingTitle,
              measurementsRef: measurementsRef,
              p1: segments.first.p1,
              p2: segments.last.p2,
              measuredLengthM: totalChainLengthM,
              color: currentColor,
              chainId: _lengthChainGroupId!,
              segmentIndex: 0,
              polylineSegments: polylineSegments,
              initialBoq: _timberRoofChainBoq,
              lastBoq: _lastTimberRoofBoq,
              lastBoqByMember: _lastTimberRoofBoqByMember,
              recentBoqs: _recentTimberRoofBoqs,
              initialSessionDefaults:
                  _timberRoofChainSessionDefaults ??
                  _lastTimberRoofSessionDefaults,
            )
            : await showRoofMemberMeasurementDialog(
              context: context,
              projectId: projectId,
              buildingId: buildingId,
              drawingId: drawingId,
              drawingTitle: drawingTitle,
              measurementsRef: measurementsRef,
              p1: segments.first.p1,
              p2: segments.last.p2,
              currentSegmentLengthM: totalChainLengthM,
              chainLengthM: totalChainLengthM,
              color: currentColor,
              chainId: _lengthChainGroupId!,
              segmentIndex: 0,
              polylineSegments: polylineSegments,
              initialBoq: _roofChainBoq,
              lastBoq: _lastRoofBoq,
              initialSessionDefaults:
                  _roofChainSessionDefaults ?? _lastRoofSessionDefaults,
            );

    if (result.action == RoofMemberSaveAction.cancel) return;
    if (timber) {
      _addPendingTimberTrussMember(result.memberData);
    }
    if (result.boq != null) {
      if (timber) {
        _timberRoofChainBoq = result.boq;
        _lastTimberRoofBoq = result.boq;
        _timberRoofChainSessionDefaults = result.sessionDefaults;
        _lastTimberRoofSessionDefaults = result.sessionDefaults;
        _rememberTimberRoofBoq(result.memberType, result.boq);
      } else {
        _roofChainBoq = result.boq;
        _lastRoofBoq = result.boq;
        _roofChainSessionDefaults = result.sessionDefaults;
        _lastRoofSessionDefaults = result.sessionDefaults;
      }
    }

    _finishLengthChain();
    update(['overlay', 'viewer', 'summary']);
  }

  Future<void> finishContinuousWallMeasurement(
    Map<String, dynamic> drawingData,
  ) async {
    final draftSegments = _buildDraftLengthSegments(drawingData);
    if (draftSegments == null || draftSegments.isEmpty) {
      Get.snackbar(
        'Walling',
        'Tap at least two wall points before saving.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final action = await it.openWallingFromSegment(
      p1: draftSegments.first.p1,
      p2: draftSegments.last.p2,
      wallSegments:
          draftSegments
              .map(
                (segment) => {
                  'p1': {'x': segment.p1.dx, 'y': segment.p1.dy},
                  'p2': {'x': segment.p2.dx, 'y': segment.p2.dy},
                  'lengthM': segment.lengthM,
                  'lengthPx': segment.lengthPx,
                },
              )
              .toList(),
      drawingData: drawingData,
      projectId: projectId,
      buildingId: buildingId,
      drawingId: drawingId,
      currentColor: currentColor,
      activeLabel: activeLabel,
      measurementsRef: measurementsRef,
      showBoqPickerDialog: (ctx) => it.showBoqPickerDialog(context: ctx),
      onCloseDraft: () {
        clearDraftLength();
        update(['overlay', 'viewer']);
      },
    );

    if (action == WallSaveAction.finish) {
      clearDraftLength();
      update(['overlay', 'viewer', 'summary']);
      return;
    }

    if (action == WallSaveAction.minimize) {
      Get.snackbar(
        'Walling take-off minimized',
        'The wall draft and form values are kept. Inspect the drawing, then restore when ready.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(days: 1),
        mainButton: TextButton.icon(
          onPressed: () {
            if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();
            finishContinuousWallMeasurement(drawingData);
          },
          icon: const Icon(Icons.open_in_full_rounded),
          label: const Text('Restore'),
        ),
      );
    }

    update(['overlay', 'viewer', 'summary']);
  }

  Future<void> finishCountMeasurement() async {
    final ctx = Get.context;
    if (ctx == null) return;

    if (_draftCountPoints.isEmpty) {
      Get.snackbar(
        'Count',
        'Tap at least one object before saving.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    if (it.isCountingFastSlabRebarBundles) {
      try {
        final action = await it.finishFastSlabRebarBundleCount(
          List<Offset>.from(_draftCountPoints),
        );
        if (action == SlabRebarLengthSaveAction.cancel) return;
        _draftCountPoints.clear();
        _countGroupId = null;
        if (action == SlabRebarLengthSaveAction.measureAnother) {
          setMode(TakeoffMode.measureLength);
          Get.snackbar(
            'Measure another rebar',
            'Tap the next representative bar length, then enter its details.',
            snackPosition: SnackPosition.BOTTOM,
          );
        } else if (action == SlabRebarLengthSaveAction.finish) {
          setMode(TakeoffMode.view);
        }
        update(['toolbar', 'topbar', 'overlay', 'viewer', 'summary']);
      } catch (error) {
        Get.snackbar(
          'Could not save reinforcement',
          '$error',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
      return;
    }

    if (_isDoorType(activeMeasureType ?? '')) {
      await _finishDoorCountMeasurement(ctx);
      return;
    }
    if (_isWindowType(activeMeasureType ?? '')) {
      await _finishWindowCountMeasurement(ctx);
      return;
    }

    String s(dynamic v) => (v ?? '').toString().trim();
    String normBoq(String code) => code.trim().replaceAll(RegExp(r'\s+'), '');

    final factorCtrl = TextEditingController(text: '1');
    final rows =
        _lastCountRows.isNotEmpty
            ? _lastCountRows
                .map(
                  (r) => _LengthBoqRow(
                    label:
                        s(r['label']).isEmpty
                            ? (activeLabel ?? 'Count')
                            : s(r['label']),
                    boqCode: s(r['boqCode']),
                    boqDesc: s(r['boqDescription']),
                  ),
                )
                .toList()
            : <_LengthBoqRow>[
              _LengthBoqRow(
                label: (activeLabel ?? 'Count').trim(),
                boqCode: s(activeBoqCode),
                boqDesc: '',
              ),
            ];

    var mark = _countMark;

    final action = await Get.dialog<CountDialogAction>(
      StatefulBuilder(
        builder: (dCtx, setStateDialog) {
          Future<void> pickForRow(_LengthBoqRow row) async {
            final picked = await it.showBoqPickerDialog(context: dCtx);
            if (picked == null) return;
            setStateDialog(() {
              row.boqCodeCtrl.text = s(picked.code);
              row.boqDescCtrl.text = s(picked.description);
              if (row.labelCtrl.text.trim().isEmpty ||
                  row.labelCtrl.text.trim().toLowerCase() == 'count') {
                row.labelCtrl.text =
                    s(picked.description).isNotEmpty
                        ? s(picked.description)
                        : 'Count';
              }
            });
          }

          final pickedCount =
              rows.where((r) => r.boqCodeCtrl.text.trim().isNotEmpty).length;
          final canSave = pickedCount > 0;
          final factor = double.tryParse(factorCtrl.text.trim()) ?? 1.0;
          final finalQty = _draftCountPoints.length * factor;

          Widget metric({
            required IconData icon,
            required String label,
            required String value,
            required Color color,
          }) {
            return Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: color.withValues(alpha: 0.22)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            value,
                            style: const TextStyle(
                              color: Color(0xFF101828),
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          void closeWith(CountDialogAction action) {
            if (action == CountDialogAction.cancel) {
              Get.back(result: action);
              return;
            }
            if (!canSave) {
              Get.snackbar(
                'Missing BOQ',
                'Pick at least one BOQ item before saving.',
                snackPosition: SnackPosition.BOTTOM,
              );
              return;
            }
            Get.back(result: action);
          }

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 20,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF143A82), Color(0xFF2563EB)],
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                          child: const Icon(
                            Icons.fact_check_outlined,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 18),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Save count measurement',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Review counted objects and map them to one or more BOQ items.',
                                style: TextStyle(
                                  color: Color(0xFFD9E6FF),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              metric(
                                icon: Icons.pin_drop_outlined,
                                label: 'Counted objects',
                                value: '${_draftCountPoints.length}',
                                color: const Color(0xFF155EEF),
                              ),
                              const SizedBox(width: 14),
                              metric(
                                icon: Icons.close_fullscreen_rounded,
                                label: 'Factor',
                                value: '× ${factor.toStringAsFixed(2)}',
                                color: const Color(0xFFF97316),
                              ),
                              const SizedBox(width: 14),
                              metric(
                                icon: Icons.check_circle_outline,
                                label: 'Final quantity',
                                value: finalQty.toStringAsFixed(
                                  finalQty.truncateToDouble() == finalQty
                                      ? 0
                                      : 2,
                                ),
                                color: const Color(0xFF079455),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: factorCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Multiplying factor',
                                      helperText:
                                          'Use 1 for normal count, 2 for repeated identical items, etc.',
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (_) => setStateDialog(() {}),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(
                                      value: 'tick',
                                      icon: Icon(Icons.check_rounded),
                                      label: Text('Tick'),
                                    ),
                                    ButtonSegment(
                                      value: 'cross',
                                      icon: Icon(Icons.close_rounded),
                                      label: Text('Cross'),
                                    ),
                                  ],
                                  selected: {mark},
                                  onSelectionChanged:
                                      (v) => setStateDialog(() {
                                        mark = v.first;
                                        _countMark = mark;
                                      }),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              const Icon(
                                Icons.receipt_long_outlined,
                                color: Color(0xFF155EEF),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'BOQ mappings',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      'Add one or more BOQ items for this same counted quantity.',
                                      style: TextStyle(
                                        color: Color(0xFF667085),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      canSave
                                          ? const Color(0xFFE7F8EF)
                                          : const Color(0xFFFFF1F3),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  canSave
                                      ? '$pickedCount picked'
                                      : 'BOQ required',
                                  style: TextStyle(
                                    color:
                                        canSave
                                            ? const Color(0xFF067647)
                                            : const Color(0xFFC01048),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          for (var i = 0; i < rows.length; i++) ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Column(
                                children: [
                                  TextField(
                                    controller: rows[i].labelCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Label',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: rows[i].boqCodeCtrl,
                                          readOnly: true,
                                          decoration: const InputDecoration(
                                            labelText: 'BOQ code',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      OutlinedButton.icon(
                                        onPressed: () => pickForRow(rows[i]),
                                        icon: const Icon(Icons.search_rounded),
                                        label: const Text('Pick'),
                                      ),
                                      if (rows.length > 1) ...[
                                        const SizedBox(width: 8),
                                        IconButton(
                                          tooltip: 'Remove BOQ mapping',
                                          onPressed:
                                              () => setStateDialog(
                                                () => rows.removeAt(i),
                                              ),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Color(0xFFD92D20),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: rows[i].boqDescCtrl,
                                    readOnly: true,
                                    maxLines: 2,
                                    decoration: const InputDecoration(
                                      labelText: 'BOQ description',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          OutlinedButton.icon(
                            onPressed:
                                () => setStateDialog(
                                  () => rows.add(
                                    _LengthBoqRow(
                                      label: activeLabel ?? 'Count',
                                      boqCode: '',
                                      boqDesc: '',
                                    ),
                                  ),
                                ),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add another BOQ item'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => closeWith(CountDialogAction.cancel),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed:
                              canSave
                                  ? () => closeWith(CountDialogAction.cont)
                                  : null,
                          child: const Text('Save & Count Next'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed:
                              canSave
                                  ? () => closeWith(CountDialogAction.save)
                                  : null,
                          child: const Text('Save & Finish'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      barrierDismissible: false,
    );

    if (action == null || action == CountDialogAction.cancel) {
      factorCtrl.dispose();
      for (final row in rows) {
        row.dispose();
      }
      return;
    }

    final cleaned =
        rows
            .map(
              (r) => (
                label:
                    s(r.labelCtrl.text).isEmpty ? 'Count' : s(r.labelCtrl.text),
                boq: s(r.boqCodeCtrl.text),
                desc: s(r.boqDescCtrl.text),
              ),
            )
            .where((r) => r.boq.isNotEmpty)
            .toList();

    if (cleaned.isEmpty) {
      factorCtrl.dispose();
      for (final row in rows) {
        row.dispose();
      }
      Get.snackbar(
        'Missing BOQ',
        'Pick at least one BOQ item before saving.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final factor = double.tryParse(factorCtrl.text.trim()) ?? 1.0;
    final baseCount = _draftCountPoints.length;
    final finalQty = baseCount * factor;
    final groupId = _countGroupId ?? measurementsRef.doc().id;
    final points = _draftCountPoints
        .map((p) => {'x': p.dx, 'y': p.dy})
        .toList(growable: false);

    OverlayEntry? progressOverlay;

    void showProgress() {
      final overlayContext = Get.overlayContext ?? ctx;
      final overlay = Overlay.maybeOf(overlayContext, rootOverlay: true);
      if (overlay == null) return;
      progressOverlay = OverlayEntry(
        builder:
            (_) => Material(
              color: Colors.black.withValues(alpha: 0.58),
              child: Center(
                child: Container(
                  width: 360,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.18),
                        blurRadius: 36,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      SizedBox(height: 18),
                      Text(
                        'Saving count',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Saving counted objects and BOQ mappings...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      );
      overlay.insert(progressOverlay!);
    }

    void closeProgress() {
      progressOverlay?.remove();
      progressOverlay = null;
    }

    var saved = false;
    try {
      showProgress();
      await Future<void>.delayed(Duration.zero);
      final batch = FirebaseFirestore.instance.batch();
      final now = FieldValue.serverTimestamp();
      for (final item in cleaned) {
        final docRef = measurementsRef.doc();
        batch.set(docRef, {
          'projectId': projectId,
          'buildingId': buildingId,
          'drawingId': drawingId,
          'countGroupId': groupId,
          'measureType': 'count',
          'activeMeasureType': 'count',
          'type': 'countMeasure',
          'unit': 'nr',
          'value': finalQty,
          'baseValue': baseCount,
          'count': baseCount,
          'factor': factor,
          'mark': mark,
          'label': item.label,
          'boqCode': item.boq,
          'boqCodeRaw': item.boq,
          'boqCodeNorm': normBoq(item.boq),
          'boqDescription': item.desc,
          'points': points,
          'color': currentColor.value,
          'createdAt': now,
          'updatedAt': now,
        });
      }
      await batch.commit();
      saved = true;
      _lastCountRows =
          cleaned
              .map(
                (item) => {
                  'label': item.label,
                  'boqCode': item.boq,
                  'boqDescription': item.desc,
                },
              )
              .toList();
    } catch (e) {
      closeProgress();
      await Get.dialog<void>(
        AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('Save failed'),
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => Get.back<void>(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      closeProgress();
      factorCtrl.dispose();
      for (final row in rows) {
        row.dispose();
      }
    }

    if (!saved) return;

    _draftCountPoints.clear();
    _countGroupId =
        action == CountDialogAction.cont ? measurementsRef.doc().id : null;
    if (action == CountDialogAction.save) {
      setMode(TakeoffMode.view);
    } else {
      update(['overlay', 'viewer', 'summary']);
    }
  }

  Future<void> _finishDoorCountMeasurement(BuildContext context) async {
    String text(dynamic value) => (value ?? '').toString().trim();
    double number(String value, [double fallback = 0]) =>
        double.tryParse(value.trim()) ?? fallback;
    String normBoq(String code) => code.trim().replaceAll(RegExp(r'\s+'), '');

    final doorScope = '$projectId::$buildingId';
    if (_sharedDoorSessionScope != null &&
        _sharedDoorSessionScope != doorScope) {
      _sharedDoorCountChunks.clear();
      _sharedDoorScheduleDefaults = <String, dynamic>{};
    }
    _sharedDoorSessionScope = doorScope;
    final defaults =
        _sharedDoorScheduleDefaults.isNotEmpty
            ? _sharedDoorScheduleDefaults
            : _lastDoorScheduleDefaults;
    final typeCtrl = TextEditingController(
      text:
          text(defaults['doorType']).isEmpty
              ? 'D1'
              : text(defaults['doorType']),
    );
    final widthCtrl = TextEditingController(
      text:
          text(defaults['widthM']).isEmpty ? '0.900' : text(defaults['widthM']),
    );
    final heightCtrl = TextEditingController(
      text:
          text(defaults['heightM']).isEmpty
              ? '2.600'
              : text(defaults['heightM']),
    );
    final shutterWidthCtrl = TextEditingController(
      text:
          text(defaults['shutterWidthM']).isEmpty
              ? '0.900'
              : text(defaults['shutterWidthM']),
    );
    final shutterHeightCtrl = TextEditingController(
      text:
          text(defaults['shutterHeightM']).isEmpty
              ? '2.100'
              : text(defaults['shutterHeightM']),
    );
    var shutterFillsOpening = defaults['shutterFillsOpening'] == true;
    var shutterArrangement =
        text(defaults['shutterArrangement']).isEmpty
            ? 'Single leaf'
            : text(defaults['shutterArrangement']);
    final activeLeafWidthCtrl = TextEditingController(
      text:
          text(defaults['activeLeafWidthM']).isEmpty
              ? '0.900'
              : text(defaults['activeLeafWidthM']),
    );
    var material =
        text(defaults['material']).isEmpty
            ? 'Timber'
            : text(defaults['material']);
    var doorBasis =
        text(defaults['doorBasis']).isEmpty
            ? 'No'
            : text(defaults['doorBasis']);
    var saving = false;
    String? formError;

    final remembered =
        defaults['items'] is Map
            ? Map<String, dynamic>.from(defaults['items'] as Map)
            : <String, dynamic>{};
    BoqPick? rememberedBoq(String key) {
      final value = remembered[key];
      if (value is! Map) return null;
      final map = Map<String, dynamic>.from(value);
      final code = text(map['code']);
      if (code.isEmpty) return null;
      return BoqPick(
        id: text(map['id']),
        code: code,
        description: text(map['description']),
      );
    }

    final items = <_DoorScheduleItem>[
      _DoorScheduleItem(
        key: 'panel',
        label: 'Door panel / complete door',
        unit: 'nr',
        formula: 'door',
        factor: 1,
        enabled: true,
      ),
      _DoorScheduleItem(
        key: 'frame',
        label: 'Door frame',
        unit: 'm',
        formula: 'frame',
        factor: 1,
        enabled: true,
      ),
      _DoorScheduleItem(
        key: 'finish',
        label: 'Paint / varnish to both faces',
        unit: 'm2',
        formula: 'finish',
        factor: 2,
        enabled: true,
      ),
      _DoorScheduleItem(
        key: 'architrave',
        label: 'Architraves',
        unit: 'm',
        formula: 'architrave',
        factor: 2,
        enabled: true,
      ),
      _DoorScheduleItem(
        key: 'transom',
        label: 'Transom',
        unit: 'm',
        formula: 'width',
        factor: 1,
        enabled: true,
      ),
      _DoorScheduleItem(
        key: 'vent',
        label: 'Vent / fanlight assembly',
        unit: 'm2',
        formula: 'ventArea',
        factor: 1,
        enabled: true,
      ),
      _DoorScheduleItem(
        key: 'ventGlass',
        label: 'Glass infill to vent / fanlight',
        unit: 'm2',
        formula: 'ventArea',
        factor: 1,
        enabled: true,
      ),
      _DoorScheduleItem(
        key: 'hinges',
        label: '100 mm fire-rated butt hinges',
        unit: 'pair',
        formula: 'perLeaf',
        factor: 1.5,
        enabled: true,
      ),
      _DoorScheduleItem(
        key: 'lockset',
        label: 'Lockset / mortise with face plate',
        unit: 'nr',
        formula: 'perDoor',
        factor: 1,
      ),
      _DoorScheduleItem(
        key: 'handles',
        label: 'Handle / lever furniture set',
        unit: 'set',
        formula: 'perDoor',
        factor: 1,
        enabled: true,
      ),
      _DoorScheduleItem(
        key: 'towerBolts',
        label: 'Tower bolts to inactive leaf',
        unit: 'nr',
        formula: 'inactiveLeaf',
        factor: 2,
      ),
      _DoorScheduleItem(
        key: 'cylinder',
        label: 'Lock cylinder',
        unit: 'nr',
        formula: 'perDoor',
        factor: 1,
      ),
      _DoorScheduleItem(
        key: 'closer',
        label: 'Overhead hydraulic door closer',
        unit: 'nr',
        formula: 'perDoor',
        factor: 1,
      ),
      _DoorScheduleItem(
        key: 'kickPlate',
        label: 'Kick plate',
        unit: 'nr',
        formula: 'perDoor',
        factor: 1,
      ),
      _DoorScheduleItem(
        key: 'pushPlate',
        label: 'Push plate',
        unit: 'nr',
        formula: 'perDoor',
        factor: 1,
      ),
      _DoorScheduleItem(
        key: 'pullPlate',
        label: 'Pull plate',
        unit: 'nr',
        formula: 'perDoor',
        factor: 1,
      ),
      _DoorScheduleItem(
        key: 'pullHandle',
        label: 'Pull handle',
        unit: 'nr',
        formula: 'perDoor',
        factor: 1,
      ),
      _DoorScheduleItem(
        key: 'wcIndicator',
        label: 'WC indicator and emergency release',
        unit: 'nr',
        formula: 'perDoor',
        factor: 1,
      ),
      _DoorScheduleItem(
        key: 'signage',
        label: 'Door signage',
        unit: 'nr',
        formula: 'perDoor',
        factor: 1,
      ),
      _DoorScheduleItem(
        key: 'doorStop',
        label: 'Door stop',
        unit: 'nr',
        formula: 'perLeaf',
        factor: 1,
      ),
    ];
    for (final item in items) {
      final saved = remembered[item.key];
      if (saved is Map) {
        item.enabled = saved['enabled'] == true;
        item.factor = (saved['factor'] as num?)?.toDouble() ?? item.factor;
      }
      item.boq = rememberedBoq(item.key);
    }
    if (remembered['towerBolts'] is! Map) {
      final tower = items.firstWhere((item) => item.key == 'towerBolts');
      tower.enabled = shutterArrangement != 'Single leaf';
    }
    if (shutterFillsOpening) {
      for (final item in items.where(
        (item) => {'transom', 'vent', 'ventGlass'}.contains(item.key),
      )) {
        item.enabled = false;
      }
    }

    int leafCount() => shutterArrangement == 'Single leaf' ? 1 : 2;

    bool isCompleteDoorMaterial() =>
        material == 'Metal' || material == 'Aluminium';

    void applyDoorMaterialDefaults() {
      final completeDoor = isCompleteDoorMaterial();
      for (final item in items) {
        if (item.key == 'panel') {
          item.enabled = true;
          continue;
        }
        if (completeDoor) {
          item.enabled = false;
          continue;
        }

        // Timber doors retain the normal component-based take-off defaults.
        switch (item.key) {
          case 'frame':
          case 'finish':
          case 'architrave':
          case 'hinges':
          case 'handles':
          case 'doorStop':
            item.enabled = true;
            break;
          case 'transom':
          case 'vent':
          case 'ventGlass':
            item.enabled = !shutterFillsOpening;
            break;
          case 'towerBolts':
            item.enabled = shutterArrangement != 'Single leaf';
            break;
          default:
            item.enabled = false;
        }
      }
    }

    // Aluminium and metal doors are treated as complete door sets by default.
    // Frames, transoms, architraves/finishes and ironmongery stay OFF so they
    // cannot be double-counted against a complete-door BOQ rate.
    if (isCompleteDoorMaterial()) {
      applyDoorMaterialDefaults();
    }

    double quantityFor(_DoorScheduleItem item, {double? countOverride}) {
      final pendingCount = _sharedDoorCountChunks.fold<double>(
        0,
        (sum, chunk) => sum + ((chunk['count'] as num?)?.toDouble() ?? 0),
      );
      final count =
          countOverride ?? (pendingCount + _draftCountPoints.length.toDouble());
      final width = number(widthCtrl.text);
      final height = number(heightCtrl.text);
      final shutterWidth =
          shutterFillsOpening ? width : number(shutterWidthCtrl.text);
      final shutterHeight =
          shutterFillsOpening ? height : number(shutterHeightCtrl.text);
      final ventArea = math.max(
        0,
        (width * height) - (shutterWidth * shutterHeight),
      );
      switch (item.formula) {
        case 'door':
          return doorBasis == 'm2'
              ? shutterWidth * shutterHeight * count
              : count;
        case 'frame':
          return (2 * height + width) * count * item.factor;
        case 'finish':
          return shutterWidth * shutterHeight * count * item.factor;
        case 'architrave':
          return (2 * height + width) * count * item.factor;
        case 'width':
          return width * count * item.factor;
        case 'ventArea':
          return ventArea * count * item.factor;
        case 'perLeaf':
          return count * leafCount() * item.factor;
        case 'inactiveLeaf':
          return shutterArrangement == 'Single leaf' ? 0 : count * item.factor;
        default:
          return count * item.factor;
      }
    }

    await Get.dialog<void>(
      StatefulBuilder(
        builder: (dialogContext, setStateDialog) {
          Future<void> pick(_DoorScheduleItem item) async {
            final selected = await it.showBoqPickerDialog(
              context: dialogContext,
            );
            if (selected == null) return;
            setStateDialog(() {
              item.boq = selected;
              formError = null;
            });
          }

          final enabled = items.where((item) => item.enabled).toList();
          final pendingDoorCount = _sharedDoorCountChunks.fold<double>(
            0,
            (sum, chunk) => sum + ((chunk['count'] as num?)?.toDouble() ?? 0),
          );
          final currentDoorCount = _draftCountPoints.length.toDouble();
          final totalDoorCount = pendingDoorCount + currentDoorCount;
          final width = number(widthCtrl.text);
          final height = number(heightCtrl.text);
          final shutterWidth =
              shutterFillsOpening ? width : number(shutterWidthCtrl.text);
          final shutterHeight =
              shutterFillsOpening ? height : number(shutterHeightCtrl.text);
          final activeLeafWidth = number(activeLeafWidthCtrl.text);
          final unequalLeafValid =
              shutterArrangement != 'Double leaf - unequal' ||
              (activeLeafWidth > 0 && activeLeafWidth < shutterWidth);
          final dimensionsValid =
              width > 0 &&
              height > 0 &&
              shutterWidth > 0 &&
              shutterHeight > 0 &&
              shutterWidth <= width &&
              shutterHeight <= height &&
              unequalLeafValid &&
              totalDoorCount > 0;
          final canSave =
              !saving &&
              dimensionsValid &&
              enabled.isNotEmpty &&
              enabled.every((item) => item.boq != null);

          Map<String, dynamic> currentDoorDefaults() => {
            'doorType': typeCtrl.text.trim(),
            'material': material,
            'doorBasis': doorBasis,
            'widthM': widthCtrl.text.trim(),
            'heightM': heightCtrl.text.trim(),
            'shutterWidthM': shutterWidthCtrl.text.trim(),
            'shutterHeightM': shutterHeightCtrl.text.trim(),
            'shutterFillsOpening': shutterFillsOpening,
            'shutterArrangement': shutterArrangement,
            'activeLeafWidthM': activeLeafWidthCtrl.text.trim(),
            'items': {
              for (final item in items)
                item.key: {
                  'enabled': item.enabled,
                  'factor': item.factor,
                  if (item.boq != null) ...item.boq!.toMap(),
                },
            },
          };

          void addCurrentChunkToSharedSession() {
            if (_draftCountPoints.isEmpty) return;
            _sharedDoorSessionId ??= _countGroupId ?? measurementsRef.doc().id;
            _sharedDoorCountChunks.add({
              'projectId': projectId,
              'buildingId': buildingId,
              'drawingId': drawingId,
              'count': _draftCountPoints.length,
              'points': _draftCountPoints
                  .map((p) => {'x': p.dx, 'y': p.dy})
                  .toList(growable: false),
              'color': currentColor.value,
            });
            _draftCountPoints.clear();
            _countGroupId = null;
            update(['overlay', 'viewer', 'summary']);
          }

          Future<void> minimizeDoorTakeoff() async {
            _sharedDoorScheduleDefaults = currentDoorDefaults();
            _lastDoorScheduleDefaults = Map<String, dynamic>.from(
              _sharedDoorScheduleDefaults,
            );
            addCurrentChunkToSharedSession();
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            Get.snackbar(
              'Door take-off minimized',
              'Door settings and ${_sharedDoorCountChunks.fold<int>(0, (sum, chunk) => sum + ((chunk['count'] as num?)?.toInt() ?? 0))} counted door(s) are retained. You can open another drawing, count more doors, then continue the same door take-off.',
              snackPosition: SnackPosition.BOTTOM,
              duration: const Duration(days: 1),
              mainButton: TextButton.icon(
                onPressed: () {
                  if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();
                  _finishDoorCountMeasurement(context);
                },
                icon: const Icon(Icons.open_in_full_rounded),
                label: const Text('Restore'),
              ),
            );
          }

          Future<void> save() async {
            if (!canSave) {
              setStateDialog(() {
                formError =
                    !dimensionsValid
                        ? 'Enter valid dimensions. For an unequal double leaf, the active leaf width must be smaller than the total shutter width.'
                        : enabled.isEmpty
                        ? 'Select at least one door quantity.'
                        : 'Pick a BOQ item for every selected quantity.';
              });
              return;
            }
            setStateDialog(() {
              saving = true;
              formError = null;
            });
            try {
              _sharedDoorScheduleDefaults = currentDoorDefaults();
              _lastDoorScheduleDefaults = Map<String, dynamic>.from(
                _sharedDoorScheduleDefaults,
              );
              addCurrentChunkToSharedSession();
              final chunks = List<Map<String, dynamic>>.from(
                _sharedDoorCountChunks,
              );
              if (chunks.isEmpty) {
                throw StateError('No counted doors are available to save.');
              }
              final groupId = _sharedDoorSessionId ?? measurementsRef.doc().id;
              final batch = FirebaseFirestore.instance.batch();
              final now = FieldValue.serverTimestamp();
              for (final chunk in chunks) {
                final chunkCount = ((chunk['count'] as num?)?.toDouble() ?? 0);
                if (chunkCount <= 0) continue;
                final chunkPoints = (chunk['points'] as List?) ?? const [];
                final chunkDrawingId = text(chunk['drawingId']);
                final chunkColor =
                    (chunk['color'] as num?)?.toInt() ?? currentColor.value;
                for (final item in enabled) {
                  final boq = item.boq!;
                  batch.set(measurementsRef.doc(), {
                    'projectId': projectId,
                    'buildingId': buildingId,
                    'drawingId':
                        chunkDrawingId.isEmpty ? drawingId : chunkDrawingId,
                    'doorGroupId': groupId,
                    'countGroupId': groupId,
                    'measureType': 'door',
                    'activeMeasureType': 'door',
                    'type':
                        'door${item.key[0].toUpperCase()}${item.key.substring(1)}',
                    'componentKey': item.key,
                    'label': '${typeCtrl.text.trim()} - ${item.label}',
                    'doorType': typeCtrl.text.trim(),
                    'doorMaterial': material,
                    'doorMeasureBasis': doorBasis,
                    'openingWidthM': width,
                    'openingHeightM': height,
                    'shutterWidthM': shutterWidth,
                    'shutterHeightM': shutterHeight,
                    'shutterFillsOpening': shutterFillsOpening,
                    'shutterArrangement': shutterArrangement,
                    'leafCount': leafCount(),
                    'activeLeafWidthM':
                        shutterArrangement == 'Double leaf - unequal'
                            ? activeLeafWidth
                            : (shutterArrangement == 'Single leaf'
                                ? shutterWidth
                                : shutterWidth / 2),
                    'secondaryLeafWidthM':
                        shutterArrangement == 'Double leaf - unequal'
                            ? math.max(0, shutterWidth - activeLeafWidth)
                            : (shutterArrangement == 'Single leaf'
                                ? 0
                                : shutterWidth / 2),
                    'openingAreaM2': width * height,
                    'shutterAreaM2': shutterWidth * shutterHeight,
                    'ventAreaM2': math.max(
                      0,
                      (width * height) - (shutterWidth * shutterHeight),
                    ),
                    'doorCount': chunkCount,
                    'unit':
                        item.key == 'panel'
                            ? (doorBasis == 'm2' ? 'm2' : 'nr')
                            : item.unit,
                    'value': quantityFor(item, countOverride: chunkCount),
                    'factorPerDoor': item.factor,
                    'boqItemId': boq.id,
                    'boqCode': boq.code,
                    'boqCodeRaw': boq.code,
                    'boqCodeNorm': normBoq(boq.code),
                    'boqDescription': boq.description,
                    'points': chunkPoints,
                    'color': chunkColor,
                    'createdAt': now,
                    'updatedAt': now,
                  });
                }
              }
              await batch.commit();
              _sharedDoorCountChunks.clear();
              _sharedDoorSessionId = null;
              _draftCountPoints.clear();
              _countGroupId = null;
              update(['overlay', 'viewer', 'summary']);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            } catch (error) {
              setStateDialog(() {
                saving = false;
                formError = 'Could not save the door schedule. $error';
              });
            }
          }

          Widget sectionTitle(String title, String subtitle) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );

          Widget itemTile(_DoorScheduleItem item) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: CheckboxListTile(
              value: item.enabled,
              onChanged:
                  saving || (isCompleteDoorMaterial() && item.key != 'panel')
                      ? null
                      : (value) => setStateDialog(() {
                        item.enabled = value == true;
                        formError = null;
                      }),
              title: Text(
                item.label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                isCompleteDoorMaterial() && item.key != 'panel'
                    ? 'OFF for $material complete-door take-off'
                    : item.enabled
                    ? '${quantityFor(item).toStringAsFixed(3)} ${item.key == 'panel' ? (doorBasis == 'm2' ? 'm²' : 'No') : item.unit}  ·  ${item.boq?.code ?? 'BOQ not selected'}'
                    : 'Not included',
              ),
              secondary:
                  item.enabled
                      ? OutlinedButton.icon(
                        onPressed: saving ? null : () => pick(item),
                        icon: const Icon(Icons.search_rounded),
                        label: Text(
                          item.boq == null ? 'Pick BOQ' : 'Change BOQ code',
                        ),
                      )
                      : null,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          );

          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 900),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(28, 22, 20, 22),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF15366F), Color(0xFF1769EA)],
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.door_front_door_outlined,
                          color: Colors.white,
                          size: 34,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Door take-off',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 27,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                '${totalDoorCount.toStringAsFixed(0)} doors counted · single / double-leaf door take-off',
                                style: const TextStyle(
                                  color: Color(0xFFD8E6FF),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: saving ? null : minimizeDoorTakeoff,
                          icon: const Icon(
                            Icons.minimize_rounded,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Minimize',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          onPressed:
                              saving
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          sectionTitle(
                            'Door type and opening',
                            'Count each D1, D2 or D3 continuously, then enter its opening once.',
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: typeCtrl,
                                  onChanged: (_) => setStateDialog(() {}),
                                  decoration: const InputDecoration(
                                    labelText: 'Door type / mark',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: material,
                                  decoration: const InputDecoration(
                                    labelText: 'Material',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'Timber',
                                      child: Text('Timber'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Metal',
                                      child: Text('Metal'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Aluminium',
                                      child: Text('Aluminium'),
                                    ),
                                  ],
                                  onChanged:
                                      saving
                                          ? null
                                          : (value) => setStateDialog(() {
                                            material = value ?? 'Timber';
                                            applyDoorMaterialDefaults();
                                            formError = null;
                                          }),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: doorBasis,
                                  decoration: const InputDecoration(
                                    labelText: 'Measure door panel by',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'No',
                                      child: Text('Number (No)'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'm2',
                                      child: Text('Area (m²)'),
                                    ),
                                  ],
                                  onChanged:
                                      saving
                                          ? null
                                          : (value) => setStateDialog(
                                            () => doorBasis = value ?? 'No',
                                          ),
                                ),
                              ),
                            ],
                          ),
                          if (isCompleteDoorMaterial()) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF7ED),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFFED7AA),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline_rounded,
                                    color: Color(0xFFC2410C),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '$material door is treated as a complete door set. Frame, transom, architrave/finishes and all ironmongery outputs are OFF by default.',
                                      style: const TextStyle(
                                        color: Color(0xFF9A3412),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F7FF),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFD7E4FB),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.door_sliding_outlined,
                                  color: Color(0xFF1769EA),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Choose single or double leaf below. Accessory quantities update automatically from the leaf arrangement.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: widthCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged:
                                      (_) => setStateDialog(() {
                                        if (shutterFillsOpening) {
                                          shutterWidthCtrl.text =
                                              widthCtrl.text;
                                        }
                                        formError = null;
                                      }),
                                  decoration: const InputDecoration(
                                    labelText: 'Opening width (m)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: heightCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged:
                                      (_) => setStateDialog(() {
                                        if (shutterFillsOpening) {
                                          shutterHeightCtrl.text =
                                              heightCtrl.text;
                                        }
                                        formError = null;
                                      }),
                                  decoration: const InputDecoration(
                                    labelText: 'Opening height (m)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: shutterArrangement,
                                  decoration: const InputDecoration(
                                    labelText: 'Shutter arrangement',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'Single leaf',
                                      child: Text('Single leaf'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Double leaf - equal',
                                      child: Text('Double leaf - equal'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Double leaf - unequal',
                                      child: Text('Double leaf - unequal'),
                                    ),
                                  ],
                                  onChanged:
                                      saving
                                          ? null
                                          : (value) => setStateDialog(() {
                                            shutterArrangement =
                                                value ?? 'Single leaf';
                                            final tower = items.firstWhere(
                                              (item) =>
                                                  item.key == 'towerBolts',
                                            );
                                            tower.enabled =
                                                shutterArrangement !=
                                                'Single leaf';
                                            if (shutterArrangement ==
                                                'Double leaf - equal') {
                                              activeLeafWidthCtrl
                                                  .text = (number(
                                                        shutterWidthCtrl.text,
                                                      ) /
                                                      2)
                                                  .toStringAsFixed(3);
                                            } else if (shutterArrangement ==
                                                'Single leaf') {
                                              activeLeafWidthCtrl.text =
                                                  shutterWidthCtrl.text;
                                            }
                                            if (isCompleteDoorMaterial()) {
                                              applyDoorMaterialDefaults();
                                            }
                                            formError = null;
                                          }),
                                ),
                              ),
                              if (shutterArrangement ==
                                  'Double leaf - unequal') ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: activeLeafWidthCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    onChanged:
                                        (_) => setStateDialog(() {
                                          formError = null;
                                        }),
                                    decoration: const InputDecoration(
                                      labelText: 'Active / main leaf width (m)',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Builder(
                            builder: (_) {
                              final totalShutterWidth = number(
                                shutterWidthCtrl.text,
                              );
                              final activeWidth =
                                  shutterArrangement == 'Single leaf'
                                      ? totalShutterWidth
                                      : shutterArrangement ==
                                          'Double leaf - equal'
                                      ? totalShutterWidth / 2
                                      : number(activeLeafWidthCtrl.text);
                              final secondaryWidth =
                                  shutterArrangement == 'Single leaf'
                                      ? 0.0
                                      : math.max(
                                        0,
                                        totalShutterWidth - activeWidth,
                                      );
                              return Text(
                                shutterArrangement == 'Single leaf'
                                    ? '1 door set = 1 shutter leaf'
                                    : '1 door set = 2 shutter leaves · Active leaf ${activeWidth.toStringAsFixed(3)} m · Secondary leaf ${secondaryWidth.toStringAsFixed(3)} m',
                                style: const TextStyle(
                                  color: Color(0xFF475467),
                                  fontWeight: FontWeight.w700,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: CheckboxListTile(
                              value: shutterFillsOpening,
                              onChanged:
                                  saving
                                      ? null
                                      : (value) => setStateDialog(() {
                                        shutterFillsOpening = value == true;
                                        final openingItems = items.where(
                                          (item) => {
                                            'transom',
                                            'vent',
                                            'ventGlass',
                                          }.contains(item.key),
                                        );
                                        if (shutterFillsOpening) {
                                          shutterWidthCtrl.text =
                                              widthCtrl.text;
                                          shutterHeightCtrl.text =
                                              heightCtrl.text;
                                          for (final item in openingItems) {
                                            item.enabled = false;
                                          }
                                        } else {
                                          for (final item in openingItems) {
                                            item.enabled = true;
                                          }
                                        }
                                        if (isCompleteDoorMaterial()) {
                                          applyDoorMaterialDefaults();
                                        }
                                        formError = null;
                                      }),
                              title: const Text(
                                'Door shutter fills the complete opening',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: const Text(
                                'When selected, shutter size equals opening size and no vent, glass infill or transom is measured.',
                              ),
                            ),
                          ),
                          if (!shutterFillsOpening) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: shutterWidthCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    onChanged:
                                        (_) => setStateDialog(() {
                                          formError = null;
                                        }),
                                    decoration: const InputDecoration(
                                      labelText: 'Door shutter width (m)',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: shutterHeightCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    onChanged:
                                        (_) => setStateDialog(() {
                                          formError = null;
                                        }),
                                    decoration: const InputDecoration(
                                      labelText: 'Door shutter height (m)',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Opening area: ${(number(widthCtrl.text) * number(heightCtrl.text)).toStringAsFixed(3)} m²  ·  '
                              'Shutter area: ${(number(shutterWidthCtrl.text) * number(shutterHeightCtrl.text)).toStringAsFixed(3)} m²  ·  '
                              'Vent/glass area: ${math.max(0, (number(widthCtrl.text) * number(heightCtrl.text)) - (number(shutterWidthCtrl.text) * number(shutterHeightCtrl.text))).toStringAsFixed(3)} m² per door',
                              style: const TextStyle(
                                color: Color(0xFF475467),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          sectionTitle(
                            'Door, frame and finishes',
                            'Finish area is both panel faces. Architrave is twice the frame length.',
                          ),
                          ...items.take(7).map(itemTile),
                          const SizedBox(height: 18),
                          sectionTitle(
                            'Ironmongery',
                            'Accessory quantities react to the shutter arrangement. Hinges and door stops are calculated per leaf; double doors also enable tower bolts for the inactive leaf.',
                          ),
                          ...items.skip(7).map(itemTile),
                          if (formError != null)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF1F3),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFFDA4AF),
                                ),
                              ),
                              child: Text(
                                formError!,
                                style: const TextStyle(
                                  color: Color(0xFFB42318),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(28, 16, 28, 22),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed:
                              saving
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: canSave ? save : null,
                          icon:
                              saving
                                  ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : const Icon(Icons.save_outlined),
                          label: Text(saving ? 'Saving...' : 'Save'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      barrierDismissible: false,
    );

    typeCtrl.dispose();
    widthCtrl.dispose();
    heightCtrl.dispose();
    shutterWidthCtrl.dispose();
    shutterHeightCtrl.dispose();
    activeLeafWidthCtrl.dispose();
  }

  Future<void> _finishWindowCountMeasurement(BuildContext context) async {
    String text(dynamic value) => (value ?? '').toString().trim();
    double number(String value, [double fallback = 0]) =>
        double.tryParse(value.trim()) ?? fallback;
    String normBoq(String code) => code.trim().replaceAll(RegExp(r'\s+'), '');

    final defaults = _lastWindowScheduleDefaults;
    final typeCtrl = TextEditingController(
      text:
          text(defaults['windowType']).isEmpty
              ? 'W1'
              : text(defaults['windowType']),
    );
    final widthCtrl = TextEditingController(
      text:
          text(defaults['widthM']).isEmpty ? '1.200' : text(defaults['widthM']),
    );
    final heightCtrl = TextEditingController(
      text:
          text(defaults['heightM']).isEmpty
              ? '1.200'
              : text(defaults['heightM']),
    );
    var windowBasis =
        text(defaults['windowBasis']).isEmpty
            ? 'No'
            : text(defaults['windowBasis']);
    var includeGrille = defaults['includeGrille'] == true;
    var includeCill = defaults['includeCill'] == true;
    var saving = false;
    String? formError;

    BoqPick? pickFrom(dynamic value) {
      if (value is! Map) return null;
      final map = Map<String, dynamic>.from(value);
      final code = text(map['code']);
      if (code.isEmpty) return null;
      return BoqPick(
        id: text(map['id']),
        code: code,
        description: text(map['description']),
      );
    }

    BoqPick? windowBoq = pickFrom(defaults['windowBoq']);
    BoqPick? grilleBoq = pickFrom(defaults['grilleBoq']);
    BoqPick? cillBoq = pickFrom(defaults['cillBoq']);

    await Get.dialog<void>(
      StatefulBuilder(
        builder: (dialogContext, setStateDialog) {
          final count = _draftCountPoints.length.toDouble();
          final width = number(widthCtrl.text);
          final height = number(heightCtrl.text);
          final totalArea = width * height * count;
          const cillBearingEachSideM = 0.075;
          final cillLengthEachM = width + (2 * cillBearingEachSideM);
          final totalCillLengthM = cillLengthEachM * count;
          final dimensionsValid = width > 0 && height > 0;
          final canSave =
              !saving &&
              dimensionsValid &&
              windowBoq != null &&
              (!includeGrille || grilleBoq != null) &&
              (!includeCill || cillBoq != null);

          Future<void> pickBoq({
            required bool grille,
            bool cill = false,
          }) async {
            final selected = await it.showBoqPickerDialog(
              context: dialogContext,
            );
            if (selected == null) return;
            setStateDialog(() {
              if (cill) {
                cillBoq = selected;
              } else if (grille) {
                grilleBoq = selected;
              } else {
                windowBoq = selected;
              }
              formError = null;
            });
          }

          Future<void> save() async {
            if (!canSave) {
              setStateDialog(() {
                formError =
                    !dimensionsValid
                        ? 'Enter a valid opening width and height.'
                        : windowBoq == null
                        ? 'Pick a BOQ item for the complete window.'
                        : includeGrille && grilleBoq == null
                        ? 'Pick a BOQ item for the selected grille quantity.'
                        : 'Pick a BOQ item for the selected window cill.';
              });
              return;
            }
            setStateDialog(() {
              saving = true;
              formError = null;
            });
            try {
              final groupId = _countGroupId ?? measurementsRef.doc().id;
              final points = _draftCountPoints
                  .map((point) => {'x': point.dx, 'y': point.dy})
                  .toList(growable: false);
              final batch = FirebaseFirestore.instance.batch();
              final now = FieldValue.serverTimestamp();

              Map<String, dynamic> measurement({
                required String type,
                required String component,
                required String label,
                required String unit,
                required double value,
                required BoqPick boq,
                Map<String, dynamic> extra = const <String, dynamic>{},
              }) => {
                'projectId': projectId,
                'buildingId': buildingId,
                'drawingId': drawingId,
                'windowGroupId': groupId,
                'countGroupId': groupId,
                'measureType': 'window',
                'activeMeasureType': 'window',
                'type': type,
                'componentKey': component,
                'label': '${typeCtrl.text.trim()} - $label',
                'windowType': typeCtrl.text.trim(),
                'windowMeasureBasis': windowBasis,
                'openingWidthM': width,
                'openingHeightM': height,
                'openingAreaM2': width * height,
                'windowCount': _draftCountPoints.length,
                'unit': unit,
                'value': value,
                'boqItemId': boq.id,
                'boqCode': boq.code,
                'boqCodeRaw': boq.code,
                'boqCodeNorm': normBoq(boq.code),
                'boqDescription': boq.description,
                'points': points,
                'color': currentColor.value,
                ...extra,
                'createdAt': now,
                'updatedAt': now,
              };

              batch.set(
                measurementsRef.doc(),
                measurement(
                  type: 'windowComplete',
                  component: 'window',
                  label: 'Complete window',
                  unit: windowBasis == 'm2' ? 'm2' : 'nr',
                  value: windowBasis == 'm2' ? totalArea : count,
                  boq: windowBoq!,
                ),
              );
              if (includeGrille) {
                batch.set(
                  measurementsRef.doc(),
                  measurement(
                    type: 'windowGrille',
                    component: 'grille',
                    label: 'Window grille',
                    unit: 'm2',
                    value: totalArea,
                    boq: grilleBoq!,
                  ),
                );
              }
              if (includeCill) {
                batch.set(
                  measurementsRef.doc(),
                  measurement(
                    type: 'windowCill',
                    component: 'cill',
                    label: 'Window cill',
                    unit: 'm',
                    value: totalCillLengthM,
                    boq: cillBoq!,
                    extra: {
                      'cillBearingEachSideM': cillBearingEachSideM,
                      'cillLengthEachM': cillLengthEachM,
                      'cillLengthTotalM': totalCillLengthM,
                    },
                  ),
                );
              }
              await batch.commit();

              _lastWindowScheduleDefaults = {
                'windowType': typeCtrl.text.trim(),
                'windowBasis': windowBasis,
                'widthM': widthCtrl.text.trim(),
                'heightM': heightCtrl.text.trim(),
                'includeGrille': includeGrille,
                'includeCill': includeCill,
                'windowBoq': windowBoq!.toMap(),
                if (grilleBoq != null) 'grilleBoq': grilleBoq!.toMap(),
                if (cillBoq != null) 'cillBoq': cillBoq!.toMap(),
              };
              _draftCountPoints.clear();
              _countGroupId = null;
              update(['overlay', 'viewer', 'summary']);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            } catch (error) {
              setStateDialog(() {
                saving = false;
                formError = 'Could not save the window measurement. $error';
              });
            }
          }

          Widget boqTile({
            required String title,
            required String quantity,
            required BoqPick? boq,
            required VoidCallback onPick,
            Widget? leading,
          }) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
              leading: leading,
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                '$quantity  ·  ${boq?.code ?? 'BOQ not selected'}',
              ),
              trailing: OutlinedButton.icon(
                onPressed: saving ? null : onPick,
                icon: const Icon(Icons.search_rounded),
                label: Text(boq == null ? 'Pick BOQ' : 'Change BOQ code'),
              ),
            ),
          );

          return Dialog(
            backgroundColor: Colors.white,
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980, maxHeight: 820),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(28, 22, 20, 22),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF15366F), Color(0xFF1769EA)],
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.window_outlined,
                          color: Colors.white,
                          size: 34,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Window take-off',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 27,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                '${_draftCountPoints.length} windows counted · configure one window type',
                                style: const TextStyle(
                                  color: Color(0xFFD8E6FF),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed:
                              saving
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Window type and opening',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Count each W1, W2 or W3 continuously, then enter its opening once.',
                            style: TextStyle(
                              color: Color(0xFF667085),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: typeCtrl,
                                  enabled: !saving,
                                  decoration: const InputDecoration(
                                    labelText: 'Window type / mark',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: windowBasis,
                                  decoration: const InputDecoration(
                                    labelText: 'Measure complete window by',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'No',
                                      child: Text('Number (No)'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'm2',
                                      child: Text('Area (m²)'),
                                    ),
                                  ],
                                  onChanged:
                                      saving
                                          ? null
                                          : (value) => setStateDialog(
                                            () => windowBasis = value ?? 'No',
                                          ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: widthCtrl,
                                  enabled: !saving,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged:
                                      (_) => setStateDialog(
                                        () => formError = null,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Opening width (m)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: heightCtrl,
                                  enabled: !saving,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged:
                                      (_) => setStateDialog(
                                        () => formError = null,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Opening height (m)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF4FF),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              'Opening area: ${(width * height).toStringAsFixed(3)} m² per window  ·  Total: ${totalArea.toStringAsFixed(3)} m²',
                              style: const TextStyle(
                                color: Color(0xFF17448A),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Quantities and BOQ links',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 12),
                          boqTile(
                            title: 'Complete window',
                            quantity:
                                windowBasis == 'm2'
                                    ? '${totalArea.toStringAsFixed(3)} m²'
                                    : '${count.toStringAsFixed(0)} No',
                            boq: windowBoq,
                            onPick: () => pickBoq(grille: false),
                          ),
                          boqTile(
                            title: 'Window grille',
                            quantity:
                                includeGrille
                                    ? '${totalArea.toStringAsFixed(3)} m²'
                                    : 'Not included',
                            boq: grilleBoq,
                            onPick: () => pickBoq(grille: true),
                            leading: Checkbox(
                              value: includeGrille,
                              onChanged:
                                  saving
                                      ? null
                                      : (value) => setStateDialog(() {
                                        includeGrille = value == true;
                                        formError = null;
                                      }),
                            ),
                          ),
                          boqTile(
                            title: 'Window cill (+75 mm each side)',
                            quantity:
                                includeCill
                                    ? '${cillLengthEachM.toStringAsFixed(3)} m each × ${count.toStringAsFixed(0)} = ${totalCillLengthM.toStringAsFixed(3)} m'
                                    : 'Not included',
                            boq: cillBoq,
                            onPick: () => pickBoq(grille: false, cill: true),
                            leading: Checkbox(
                              value: includeCill,
                              onChanged:
                                  saving
                                      ? null
                                      : (value) => setStateDialog(() {
                                        includeCill = value == true;
                                        formError = null;
                                      }),
                            ),
                          ),
                          if (formError != null)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 6),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF1F3),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFFDA4AF),
                                ),
                              ),
                              child: Text(
                                formError!,
                                style: const TextStyle(
                                  color: Color(0xFFB42318),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(28, 16, 28, 22),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed:
                              saving
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: canSave ? save : null,
                          icon:
                              saving
                                  ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : const Icon(Icons.save_outlined),
                          label: Text(saving ? 'Saving...' : 'Save'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      barrierDismissible: false,
    );

    typeCtrl.dispose();
    widthCtrl.dispose();
    heightCtrl.dispose();
  }

  void _finishLengthChain() {
    _lengthChainGroupId = null;
    _lengthChainSegmentIndex = 0;
    _roofChainBoq = null;
    _roofChainSessionDefaults = null;
    _timberRoofChainBoq = null;
    _timberRoofChainSessionDefaults = null;
    clearDraftLength();
  }

  String _lowerType(String? v) => (v ?? '').trim().toLowerCase();

  bool _isRetainingType(String t) {
    final v = t.trim().toLowerCase();
    return v == 'retainingwall' ||
        v == 'compositeretainingwall' ||
        v == 'retainingwallcomposite' ||
        v == 'composite_retaining_wall' ||
        v == 'retaining_wall' ||
        v.contains('retaining');
  }

  bool _isTrussType(String t) {
    final v = t.trim().toLowerCase();
    return v == 'trusstemplate' ||
        v == 'templatetruss' ||
        v == 'truss_template' ||
        v == 'trussTemplate' ||
        v.contains('truss');
  }

  bool _isStairType(String lower) {
    lower = lower.trim().toLowerCase();
    return lower == 'compositestair' ||
        lower == 'stairs' ||
        lower == 'staircase' ||
        lower.contains('Stair');
  }

  bool _isRampType(String lower) {
    lower = lower.trim().toLowerCase();
    return lower == 'compositeramp' ||
        lower == 'ramps' ||
        lower.contains('Ramp');
  }

  bool _isLiftShaftType(String lower) {
    lower = lower.trim().toLowerCase();
    return lower == 'liftshaft' ||
        lower == 'liftshaftassembly' ||
        (lower.contains('lift') && lower.contains('shaft'));
  }

  bool _isUndergroundStructureType(String lower) {
    lower = lower.trim().toLowerCase();
    return lower == 'undergroundstructure' ||
        lower == 'undergroundstructureassembly' ||
        lower == 'watertank' ||
        lower == 'septictank' ||
        lower == 'manhole' ||
        lower == 'inspectionchamber' ||
        (lower.contains('underground') && lower.contains('structure'));
  }

  bool _isRoofingType(String lower) {
    lower = lower.trim().toLowerCase();
    return lower == 'compositeroofing' || lower == 'roofingcomposite';
  }

  bool _isTimberRoofStructureType(String lower) {
    lower = lower.trim().toLowerCase();
    return lower == 'compositeroofing' || lower == 'timberroofstructure';
  }

  bool _isCivilworkType(String lower) {
    lower = lower.trim().toLowerCase();
    return lower == 'civilwork' ||
        lower == 'civilworks' ||
        lower.contains('civil');
  }

  bool _isRoadProfileType(String lower) {
    lower = lower.trim().toLowerCase();
    return lower == 'roadprofile' || lower == 'road_profile';
  }

  bool _isDrainageType(String lower) {
    lower = lower.trim().toLowerCase();
    return lower == 'drainage' || lower == 'drain' || lower == 'opendrain';
  }

  bool _isOpenings(String lower) {
    lower = lower.trim().toLowerCase();
    return lower == 'openings' ||
        lower.contains('window') ||
        lower.contains('door');
  }

  bool _isFoundationType(String t) {
    final v = t.trim().toLowerCase();
    if (v == 'foundation' || v == 'foundationwall' || v == 'foundationWall') {
      return true;
    }
    if (v.contains('foundation') && v.contains('composite')) return true;
    // if (v.contains('wall') && v.contains('composite')) return true;
    return false;
  }

  bool _isBeamType(String t) {
    final v = t.trim().toLowerCase();
    if (v == 'beam' || v == 'compositeBeam' || v == 'compositebeam') {
      return true;
    }
    if (v.contains('beam') && v.contains('composite')) return true;
    return false;
  }

  bool _isWallType(String t) {
    final v = t.trim().toLowerCase();
    if (v == 'walling' || v == 'wall' || v == 'Walling') {
      return true;
    }
    return false;
  }

  bool _isCountType(String t) => t.trim().toLowerCase() == 'count';

  bool _isDoorType(String t) {
    final value = t.trim().toLowerCase();
    return value == 'door' || value == 'compositedoor';
  }

  bool _isWindowType(String t) {
    final value = t.trim().toLowerCase();
    return value == 'window' || value == 'compositewindow';
  }

  Future<void> handleBeamTap(
    Offset imagePos,
    Map<String, dynamic> drawingData, {
    String? activeLabel,
  }) async {
    // 1st tap
    if (beamP1 == null) {
      beamP1 = imagePos;
      beamP2 = null;
      update(['viewer']);
      return;
    }

    // 2nd tap
    beamP2 = imagePos;

    final baseLenM = distanceInMeters(beamP1!, beamP2!, drawingData);
    if (baseLenM == null || baseLenM <= 0) {
      Get.snackbar('Beam', 'Invalid length (check calibration).');
      beamP1 = null;
      beamP2 = null;
      update(['viewer']);
      return;
    }

    try {
      // ✅ open composite beam dialog
      final action = await it.openBeamCompositeDialog(
        p1: beamP1!,
        p2: beamP2!,
        drawingData: drawingData,
        activeLabel: activeLabel,
        baseLengthM: baseLenM,
      );

      // A successful save completes this beam measurement. The next dialog is
      // opened only after the user starts another beam measurement.
      if (action != BeamSaveAction.cancel) {
        // nothing else
      }
    } finally {
      // ✅ ALWAYS reset draft points so p1 is not “stuck”
      beamP1 = null;
      beamP2 = null;
      update(['viewer']);
    }
  }

  Future<void> _handleMeasureLengthTap({
    required Offset imagePos,
    required Map<String, dynamic> drawingData,
    String? currentWallId,
    required List<MeasuredSegment> segments,
  }) async {
    if (it.isCountingFastSlabRebarBundles) {
      _handleCountTap(imagePos);
      Get.snackbar(
        'Bundle ${_draftCountPoints.length} counted',
        'Marked for bar ${it.pendingFastSlabRebarBundleMark}. Continue tapping or finish the count.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(milliseconds: 900),
      );
      return;
    }

    if (it.hasPendingSlabRebarLengthCapture) {
      if (_draftLenP1.value == null) {
        startDraftLength(imagePos);
        Get.snackbar(
          'Bar start recorded',
          'Tap the other end of this bar to measure its actual length.',
          snackPosition: SnackPosition.BOTTOM,
        );
        update(['overlay', 'viewer']);
        return;
      }

      final p1 = _draftLenP1.value!;
      final lengthM = distanceInMeters(p1, imagePos, drawingData);
      if (lengthM <= 0) {
        Get.snackbar(
          'Invalid length',
          'Check the drawing calibration and tap the end point again.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      final saved = await it.completePendingSlabRebarLength(
        p1: p1,
        p2: imagePos,
        measuredLengthM: lengthM,
      );
      if (saved) {
        // The point-to-point length capture is only a temporary phase of the
        // Slab Rebar tool. After saving, return that same selected tool to its
        // polygon capture mode so the next bar mark can be taken off without
        // making the user select Slab Rebar again.
        setMode(TakeoffMode.measureArea);
        resetArea();
        update(['toolbar', 'topbar', 'overlay', 'viewer', 'summary']);
      }
      return;
    }

    final lower = _lowerType(activeMeasureType);
    if (lower == 'slabrebarai') {
      if (_draftLenP1.value == null) {
        if (wallLengthCaptureStyle == WallLengthCaptureStyle.segments) {
          startDraftLength(imagePos);
          Get.snackbar(
            'Segment start recorded',
            'Tap the end of this rebar segment. Repeat for other segments, then press Next: details.',
            snackPosition: SnackPosition.BOTTOM,
          );
        } else {
          _startContinuousLengthDraft(imagePos);
          Get.snackbar(
            'Rebar start recorded',
            'Tap each bend or turn point to continue the bar path, then press Next: details.',
            snackPosition: SnackPosition.BOTTOM,
          );
        }
        update(['overlay', 'viewer']);
        return;
      }

      if (wallLengthCaptureStyle == WallLengthCaptureStyle.segments) {
        final p1 = _draftLenP1.value!;
        final dx = imagePos.dx - p1.dx;
        final dy = imagePos.dy - p1.dy;
        final lengthPx = math.sqrt(dx * dx + dy * dy);
        final lengthM = distanceInMeters(p1, imagePos, drawingData);
        if (lengthPx <= 0 || lengthM <= 0) {
          Get.snackbar('Invalid length', 'Check the drawing calibration.');
          return;
        }
        _draftIndependentSegments.add(
          LengthDraftSegment(
            p1: p1,
            p2: imagePos,
            lengthM: lengthM,
            lengthPx: lengthPx,
          ),
        );
        _draftLenP1.value = null;
        _draftLenP2.value = null;
      } else {
        if (_draftLengthPoints.isEmpty) {
          _draftLengthPoints.add(_draftLenP1.value!);
        }
        final lastPoint = _draftLengthPoints.last;
        final lengthM = distanceInMeters(lastPoint, imagePos, drawingData);
        if (lengthM <= 0) {
          Get.snackbar('Invalid length', 'Check the drawing calibration.');
          return;
        }
        _draftLengthPoints.add(imagePos);
        _draftLenP1.value = imagePos;
        _draftLenP2.value = imagePos;
      }
      update(['overlay', 'viewer', 'summary']);
      return;
    }

    if (_isCountType(lower) || _isDoorType(lower) || _isWindowType(lower)) {
      _handleCountTap(imagePos);
      return;
    }

    if (_draftLenP1.value == null) {
      final genericLength =
          !_isRetainingType(lower) &&
          !_isTimberRoofStructureType(lower) &&
          !_isTrussType(lower) &&
          !_isFoundationType(lower) &&
          !_isStairType(lower) &&
          !_isLiftShaftType(lower) &&
          !_isUndergroundStructureType(lower) &&
          !_isRampType(lower) &&
          !_isBeamType(lower) &&
          !_isWallType(lower);
      if (supportsLengthCaptureStyle &&
          wallLengthCaptureStyle == WallLengthCaptureStyle.segments) {
        startDraftLength(imagePos);
      } else if (genericLength || supportsLengthCaptureStyle) {
        _startContinuousLengthDraft(imagePos);
      } else {
        startDraftLength(imagePos); // sets p1=p2 and update overlay
      }
      update(['overlay', 'viewer']); // viewer optional
      return;
    }

    // Beam, foundation, linear, and roof-member tools now collect their
    // geometry first, just like walling. Their details dialog opens only when
    // the user finishes the temporary group.
    if (!_isWallType(lower) && supportsLengthCaptureStyle) {
      if (wallLengthCaptureStyle == WallLengthCaptureStyle.segments) {
        final p1 = _draftLenP1.value!;
        final dx = imagePos.dx - p1.dx;
        final dy = imagePos.dy - p1.dy;
        final lengthPx = math.sqrt(dx * dx + dy * dy);
        final lengthM = distanceInMeters(p1, imagePos, drawingData);
        if (lengthPx <= 0 || lengthM <= 0) {
          Get.snackbar(
            'Invalid length',
            'Check the drawing calibration.',
            snackPosition: SnackPosition.BOTTOM,
          );
          return;
        }
        _draftIndependentSegments.add(
          LengthDraftSegment(
            p1: p1,
            p2: imagePos,
            lengthM: lengthM,
            lengthPx: lengthPx,
          ),
        );
        _draftLenP1.value = null;
        _draftLenP2.value = null;
      } else {
        if (_draftLengthPoints.isEmpty) {
          _draftLengthPoints.add(_draftLenP1.value!);
        }
        final lastPoint = _draftLengthPoints.last;
        final lengthM = distanceInMeters(lastPoint, imagePos, drawingData);
        if (lengthM <= 0) {
          Get.snackbar(
            'Invalid length',
            'Check the drawing calibration.',
            snackPosition: SnackPosition.BOTTOM,
          );
          return;
        }
        _draftLengthPoints.add(imagePos);
        _draftLenP1.value = imagePos;
        _draftLenP2.value = imagePos;
      }
      update(['overlay', 'viewer', 'summary']);
      return;
    }

    // ✅ special types first (no draft line)
    if (_isUndergroundStructureType(lower)) {
      _draftLenP2.value = imagePos;
      update(['overlay', 'viewer']);

      final p1 = _draftLenP1.value!;
      final p2 = _draftLenP2.value!;
      final action = await openUndergroundStructureTakeoffFromRectangle(
        p1: p1,
        p2: p2,
        drawingData: drawingData,
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId,
        currentColor: currentColor,
        measurementsRef: measurementsRef,
        lastDefaults: lastUndergroundStructureDefaults,
        showBoqPicker: (ctx) => it.showBoqPickerDialog(context: ctx),
        activeLabel: activeLabel ?? 'Underground structure',
        onUpdateViewer: () => update(['overlay', 'viewer', 'summary']),
      );

      clearDraftLength();
      update(['overlay', 'viewer', 'summary']);
      if (action == UndergroundStructureSaveAction.finish) {
        setMode(TakeoffMode.view);
      }
      return;
    }
    if (_isLiftShaftType(lower)) {
      _draftLenP2.value = imagePos;
      update(['overlay', 'viewer']);

      final p1 = _draftLenP1.value!;
      final p2 = _draftLenP2.value!;
      final action = await openLiftShaftTakeoffFromRectangle(
        p1: p1,
        p2: p2,
        drawingData: drawingData,
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId,
        currentColor: currentColor,
        measurementsRef: measurementsRef,
        lastDefaults: lastLiftShaftDefaults,
        showBoqPicker: (ctx) => it.showBoqPickerDialog(context: ctx),
        activeLabel: activeLabel ?? 'Lift shaft',
        onUpdateViewer: () => update(['overlay', 'viewer', 'summary']),
      );

      clearDraftLength();
      update(['overlay', 'viewer', 'summary']);
      if (action == LiftShaftSaveAction.finish) {
        setMode(TakeoffMode.view);
      }
      return;
    }
    if (_isRetainingType(lower)) {
      _draftLenP2.value = imagePos;
      update(['overlay', 'viewer']);

      final p1 = _draftLenP1.value!;
      final p2 = _draftLenP2.value!;
      await it.openRetainingWallCompositeFromSegments(
        drawingData: drawingData,
        p1: p1,
        p2: p2,
      );
      clearDraftLength();
      update(['overlay', 'viewer']);
      return;
    }
    if (_isTimberRoofStructureType(lower)) {
      _draftLenP2.value = imagePos;
      update(['overlay', 'viewer']);

      final p1 = _draftLenP1.value!;
      final p2 = _draftLenP2.value!;
      final lengthM = distanceInMeters(p1, p2, drawingData);
      if (lengthM == null || lengthM <= 0) {
        Get.snackbar('Invalid timber member', 'Check the drawing calibration.');
        clearDraftLength();
        return;
      }

      final context = Get.context;
      if (context == null) {
        clearDraftLength();
        return;
      }

      _lengthChainGroupId ??= measurementsRef.doc().id;
      final result = await showTimberRoofMemberMeasurementDialog(
        context: context,
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId,
        drawingTitle: drawingTitle,
        measurementsRef: measurementsRef,
        p1: p1,
        p2: p2,
        measuredLengthM: lengthM,
        color: currentColor,
        chainId: _lengthChainGroupId!,
        segmentIndex: _lengthChainSegmentIndex,
        initialBoq: _timberRoofChainBoq,
        lastBoq: _lastTimberRoofBoq,
        lastBoqByMember: _lastTimberRoofBoqByMember,
        recentBoqs: _recentTimberRoofBoqs,
        initialSessionDefaults:
            _timberRoofChainSessionDefaults ?? _lastTimberRoofSessionDefaults,
      );

      if (result.action != RoofMemberSaveAction.cancel) {
        _addPendingTimberTrussMember(result.memberData);
      }

      if (result.action != RoofMemberSaveAction.cancel && result.boq != null) {
        _timberRoofChainBoq = result.boq;
        _lastTimberRoofBoq = result.boq;
        _timberRoofChainSessionDefaults = result.sessionDefaults;
        _lastTimberRoofSessionDefaults = result.sessionDefaults;
        _rememberTimberRoofBoq(result.memberType, result.boq);
      }

      if (result.action == RoofMemberSaveAction.saveAndContinue) {
        _lengthChainSegmentIndex += 1;
        startDraftLength(p2);
        update(['overlay', 'viewer', 'summary']);
        Get.snackbar(
          'Timber member saved',
          'The next segment starts at the previous endpoint. Tap its endpoint.',
        );
      } else {
        _finishLengthChain();
        update(['overlay', 'viewer', 'summary']);
      }

      if (result.action == RoofMemberSaveAction.saveAndFinish) {
        setMode(TakeoffMode.view);
      }
      return;
    }
    if (_isTrussType(lower)) {
      _draftLenP2.value = imagePos;
      update(['overlay', 'viewer']);

      final p1 = _draftLenP1.value!;
      final p2 = _draftLenP2.value!;
      final lengthM = distanceInMeters(p1, p2, drawingData);
      if (lengthM == null || lengthM <= 0) {
        Get.snackbar('Invalid member', 'Check the drawing calibration.');
        clearDraftLength();
        return;
      }
      final totalChainLengthM = segments.fold<double>(
        0.0,
        (sum, s) => sum + lengthM,
      );

      final context = Get.context;
      if (context == null) {
        clearDraftLength();
        return;
      }

      _lengthChainGroupId ??= measurementsRef.doc().id;
      final result = await showRoofMemberMeasurementDialog(
        context: context,
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId,
        drawingTitle: drawingTitle,
        measurementsRef: measurementsRef,
        chainLengthM: totalChainLengthM,
        p1: p1,
        p2: p2,
        currentSegmentLengthM: lengthM,
        color: currentColor,
        chainId: _lengthChainGroupId!,
        segmentIndex: _lengthChainSegmentIndex,
        initialBoq: _roofChainBoq,
        lastBoq: _lastRoofBoq,
        initialSessionDefaults:
            _roofChainSessionDefaults ?? _lastRoofSessionDefaults,
      );

      if (result.action != RoofMemberSaveAction.cancel && result.boq != null) {
        _roofChainBoq = result.boq;
        _lastRoofBoq = result.boq;
        _roofChainSessionDefaults = result.sessionDefaults;
        _lastRoofSessionDefaults = result.sessionDefaults;
      }

      if (result.action == RoofMemberSaveAction.saveAndContinue) {
        _lengthChainSegmentIndex += 1;
        startDraftLength(p2);
        update(['overlay', 'viewer', 'summary']);
        Get.snackbar(
          'Member saved',
          'The next segment starts at the previous endpoint. Tap its endpoint.',
        );
      } else {
        _finishLengthChain();
        update(['overlay', 'viewer', 'summary']);
      }

      if (result.action == RoofMemberSaveAction.saveAndFinish) {
        setMode(TakeoffMode.view);
      }
      return;
    }

    if (_isFoundationType(lower)) {
      _draftLenP2.value = imagePos;
      update(['overlay', 'viewer']);

      final p1 = _draftLenP1.value!;
      final p2 = _draftLenP2.value!;
      final action = await handleFoundationWallTap(
        drawingData: drawingData,
        p1: p1,
        p2: p2,
      );
      if (action == FoundationSaveAction.addMore) {
        startDraftLength(p2);
        Get.snackbar(
          'Segment saved',
          'The next foundation segment starts at the previous endpoint.',
        );
      } else {
        clearDraftLength();
      }
      update(['overlay', 'viewer']);
      return;
    }
    if (_isStairType(lower)) {
      _draftLenP2.value = imagePos;
      update(['overlay', 'viewer']);

      final p1 = _draftLenP1.value!;
      final p2 = _draftLenP2.value!;
      await handleStairTapP1P2(
        drawingData: drawingData,
        p1: p1,
        // tCtrl: TransformationController(),
        // onUpdateViewer: () => update(['overlay', 'viewer']),
        p2: p2,
      );
      clearDraftLength();
      update(['overlay', 'viewer']);
      return;
    }
    if (_isRampType(lower)) {
      _draftLenP2.value = imagePos;
      update(['overlay', 'viewer']);

      final p1 = _draftLenP1.value!;
      final p2 = _draftLenP2.value!;
      await handleRampTapP1P2(
        drawingData: drawingData,
        p1: p1,
        // tCtrl: TransformationController(),
        // onUpdateViewer: () => update(['overlay', 'viewer']),
        p2: p2,
      );
      clearDraftLength();
      update(['overlay', 'viewer']);
      return;
    }
    if (_isBeamType(lower)) {
      final p1 = _draftLenP1.value;
      if (p1 == null) {
        _draftLenP1.value = imagePos;
        _draftLenP2.value = null;
        update(['overlay', 'viewer']);
        return;
      }

      _draftLenP2.value = imagePos;
      update(['overlay', 'viewer']);

      // ✅ Open dialog using BOTH points you already have
      final baseLenM = distanceInMeters(p1, imagePos, drawingData);
      if (baseLenM == null || baseLenM <= 0) {
        Get.snackbar('Beam', 'Drawing not calibrated / invalid length');
        clearDraftLength();
        update(['overlay', 'viewer']);
        return;
      }

      await it.openBeamCompositeDialog(
        p1: p1,
        p2: imagePos,
        drawingData: drawingData,
        activeLabel: activeLabel,
        baseLengthM: baseLenM,
      );

      clearDraftLength();
      update(['overlay', 'viewer']);
      return;
    }
    if (_isWallType(lower)) {
      if (wallLengthCaptureStyle == WallLengthCaptureStyle.segments) {
        final p1 = _draftLenP1.value;
        if (p1 == null) {
          startDraftLength(imagePos);
          return;
        }
        final dx = imagePos.dx - p1.dx;
        final dy = imagePos.dy - p1.dy;
        final lengthPx = math.sqrt(dx * dx + dy * dy);
        final lengthM = distanceInMeters(p1, imagePos, drawingData);
        if (lengthPx <= 0 || lengthM <= 0) {
          Get.snackbar(
            'Invalid wall length',
            'Check the drawing calibration.',
            snackPosition: SnackPosition.BOTTOM,
          );
          return;
        }
        _draftIndependentSegments.add(
          LengthDraftSegment(
            p1: p1,
            p2: imagePos,
            lengthM: lengthM,
            lengthPx: lengthPx,
          ),
        );
        _draftLenP1.value = null;
        _draftLenP2.value = null;
        update(['overlay', 'viewer', 'summary']);
        return;
      }
      if (_draftLengthPoints.isEmpty) {
        final p1 = _draftLenP1.value;
        if (p1 == null) {
          _startContinuousLengthDraft(imagePos);
          return;
        }
        _draftLengthPoints.add(p1);
      }
      final lastPoint = _draftLengthPoints.last;
      final lenM = distanceInMeters(lastPoint, imagePos, drawingData);
      if (lenM <= 0) {
        Get.snackbar(
          'Invalid wall length',
          'Check the drawing calibration.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      _draftLengthPoints.add(imagePos);
      _draftLenP1.value = imagePos;
      _draftLenP2.value = imagePos;
      update(['overlay', 'viewer', 'summary']);
      return;
    } else {
      if (_draftLengthPoints.isEmpty) {
        final p1 = _draftLenP1.value;
        if (p1 == null) {
          _startContinuousLengthDraft(imagePos);
          return;
        }
        _draftLengthPoints.add(p1);
      }
      final lastPoint = _draftLengthPoints.last;
      final lenM = distanceInMeters(lastPoint, imagePos, drawingData);
      if (lenM <= 0) {
        Get.snackbar(
          'Invalid length',
          'Check the drawing calibration.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      _draftLengthPoints.add(imagePos);
      _draftLenP1.value = imagePos;
      _draftLenP2.value = imagePos;
      update(['overlay', 'viewer', 'summary']);
    }

    // ✅ normal length drafting (coping/cill/plinth/etc.)

    // second tap: set p2 and show line immediately
  }

  // Future<void> handleStairTap({
  //   required Offset localPos,
  //   required TransformationController tCtrl,
  //   required Map<String, dynamic> drawingData,

  //   // ids
  //   required String projectId,
  //   required String buildingId,
  //   required String drawingId,

  //   required Color currentColor,
  //   required String? activeLabel,
  //   required CollectionReference<Map<String, dynamic>> measurementsRef,

  //   required Future<BoqPick?> Function(BuildContext ctx) showBoqPickerDialog,

  //   // choose what this segment is: "slope1", "slope2", "width", "landingTop", "landingBottom"
  //   required String segmentKind,

  //   VoidCallback? onUpdateViewer,
  // }) async {
  //   // 1) validate calibration
  //   final calibrated = drawingData['calibrated'] == true;
  //   final pxPerM = _num(drawingData['pixelsPerUnit'], 0);
  //   if (!calibrated || pxPerM <= 0) {
  //     Get.snackbar(
  //       'Not calibrated',
  //       'Calibrate drawing first (pixelsPerUnit).',
  //     );
  //     return;
  //   }

  //   // 2) convert tap to world
  //   final world = toWorld(local: localPos, tCtrl: tCtrl);

  //   // Tap #1: set start
  //   if (stairP1World.value == null) {
  //     stairP1World.value = world;
  //     stairHoverWorld.value = world;
  //     update(['overlay']); // if you paint preview line
  //     Get.snackbar('Stairs', 'Start point set. Tap end point.');
  //     return;
  //   }

  //   // Tap #2: compute length and route it
  //   final a = stairP1World.value!;
  //   final b = world;
  //   final lenM = distM(a, b, drawingData);

  //   // reset capture points immediately (prevents crash on next tap)
  //   stairP1World.value = null;
  //   stairHoverWorld.value = null;
  //   update(['overlay']);

  //   if (lenM <= 0) {
  //     Get.snackbar('Invalid', 'Length is zero. Check calibration.');
  //     return;
  //   }

  //   // 3) store the measured value depending on segmentKind
  //   switch (segmentKind) {
  //     case 'slope1':
  //       lastStairSlopingLenM = lenM;
  //       Get.snackbar(
  //         'Stairs',
  //         'Sloping length 1 saved: ${lenM.toStringAsFixed(3)} m',
  //       );
  //       break;

  //     case 'slope2':
  //       // store as second slope; we keep it in a separate var (use lastLandingTopM if you prefer)
  //       // Better: create lastStairSlopingLen2M variable
  //       lastLandingTopM = lenM; // ❌ not recommended; see better below
  //       break;

  //     case 'width':
  //       lastStairWidthM = lenM;
  //       Get.snackbar(
  //         'Stairs',
  //         'Stair width saved: ${lenM.toStringAsFixed(3)} m',
  //       );
  //       break;

  //     case 'landingTop':
  //       lastLandingTopM = lenM;
  //       Get.snackbar(
  //         'Stairs',
  //         'Top landing saved: ${lenM.toStringAsFixed(3)} m',
  //       );
  //       break;

  //     case 'landingBottom':
  //       lastLandingBottomM = lenM;
  //       Get.snackbar(
  //         'Stairs',
  //         'Bottom landing saved: ${lenM.toStringAsFixed(3)} m',
  //       );
  //       break;

  //     default:
  //       Get.snackbar('Stairs', 'Segment saved: ${lenM.toStringAsFixed(3)} m');
  //   }

  //   // 4) decide when to open dialog:
  //   //    Minimum required: slope1 + width
  //   final Ls1 = lastStairSlopingLenM ?? 0.0;
  //   final W = lastStairWidthM ?? 0.0;

  //   if (Ls1 > 0 && W > 0) {
  //     // You can open immediately after capturing width, or after capturing slope1, up to you.
  //     // Here: open after EVERY segment as long as required fields exist.

  //     // OPTIONAL: if you also want slope2 variable, declare it properly:
  //     final Ls2 = (this as dynamic).lastStairSlopingLen2M ?? 0.0; // if you add
  //     final top = lastLandingTopM ?? 0.0;
  //     final bottom = lastLandingBottomM ?? 0.0;

  //     await it.openStairCompositeFromSegments(
  //       slopingLen1M: Ls1,
  //       slopingLen2M: Ls2,
  //       stairWidthM: W,
  //       landingTopLenM: top,
  //       landingBottomLenM: bottom,
  //       drawingData: drawingData,
  //       // projectId: projectId,
  //       // buildingId: buildingId,
  //       // drawingId: drawingId,
  //       currentColor: currentColor,
  //       activeLabel: activeLabel,
  //       // measurementsRef: measurementsRef,
  //       // showBoqPickerDialog: showBoqPickerDialog,
  //       onUpdateViewer: onUpdateViewer,
  //     );

  //     // after dialog close you may keep lengths for next stair flight or clear them:
  //     // Clear if you want fresh measurement each time:
  //     // lastStairSlopingLenM = null;
  //     // lastStairWidthM = null;
  //   }
  // }

  Offset? _trussStartWorld;

  Future<void> handleTapForTruss({
    required Offset local,
    // required MeasuringItemController it,
    // required ImageTakeoffController mi,
    required TransformationController tCtrl,
    required Map<String, dynamic> drawingData,
    // required String projectId,
    // required String buildingId,
    // required String drawingId,
    // required Color currentColor,
    // required CollectionReference<Map<String, dynamic>> measurementsRef,
    // required VoidCallback clearDraftLength,
    required VoidCallback updateViewer,
    // required PolylineDrawController pctr, // if you still want to draw preview
  }) async {
    final world = toWorld(local: local, tCtrl: tCtrl);

    // Tap #1
    if (_trussStartWorld == null) {
      _trussStartWorld = world;

      // optional: show a small preview point/line
      pctr.clear();
      pctr.addWorldPoint(world); // if your controller supports add
      Get.snackbar('Truss', 'Start point set. Tap end point.');
      return;
    }

    // Tap #2
    final a = _trussStartWorld!;
    final b = world;
    _trussStartWorld = null;

    // optional: draw the final segment in preview
    pctr.addWorldPoint(b);

    await it.openTrussTemplateFromSegment(
      p1World: a,
      p2World: b,
      drawingData: drawingData,
      projectId: projectId,
      buildingId: buildingId,
      drawingId: drawingId,
      currentColor: currentColor,
      activeLabel: 'Truss T1',
      measurementsRef: measurementsRef,
      onCloseDraft: () {
        clearDraftLength();
        pctr.clear();
      },
      onUpdateViewer: updateViewer,
      // showBoqPickerDialog:
      //     it.showBoqPickerDialog, // ✅ IMPORTANT: don't return null
    );
  }

  Future<void> onImageTap(
    BuildContext? context,
    Offset imagePos,
    Map<String, dynamic> drawingData,
    List<MeasuredSegment> segments,
    List<SavedArea> areas, {
    required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    slabCompositeDocsBySlabId,
    required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    footingCompositeDocsByGroupId,
    required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    rebarSlabDocsBySlabId,
    required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    rebarFootingDocsByGroupId,
    required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    beamCompositeDocsByBeamId,
    required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    rebarDocsByBeamType,
    required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    rebarColumnDocsByGroupId,
    required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    columnDocsByColumnId,
    required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    retainingWallCompositeDocsByWallId,
    required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    foundationWallCompositeDocsByWallId,
    required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    wallCDocsByWallId,
    required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    roofingCompositeDocsBySlabId,
    required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    ceilingFinishId,
    String? currentWallId,
  }) async {
    print('id: $ceilingFinishId');
    // ======================
    // VIEW MODE
    // ======================
    if (mode.value == TakeoffMode.view) {
      final handledColumn = await it.handleColumnViewTap(
        imagePos,
        areas,
        columnDocsByColumnId,
        buildingId: buildingId,
        projectId: projectId,
        measurementsRef,
        drawingId: drawingId,
      );
      if (handledColumn) return;

      final handledFooting = await it.handleFootingViewTap(
        imagePos,
        footingCompositeDocsByGroupId,
        rebarFootingDocsByGroupId,
        rebarColumnDocsByGroupId,
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId,
        measurementsRef: measurementsRef,
      );
      if (handledFooting) return;

      final handledArea = await it.handleAreaViewTap(
        context!,
        imagePos,
        areas,
        slabCompositeDocsBySlabId,
        rebarSlabDocsBySlabId,
        drawingId: drawingId,
      );
      if (handledArea) return;

      final handledBeam = await it.handleCompositeBeamTap(
        imagePos,
        segments,
        beamCompositeDocsByBeamId,
        rebarDocsByBeamType,
      );
      if (handledBeam) return;

      final handledRW = await it.handleRetainingWallViewTap(
        imagePos,
        segments,
        retainingWallCompositeDocsByWallId,
        drawingData,
      );
      if (handledRW) return;

      final handledFW = await it.handleFoundationWallViewTap(
        imagePos,
        segments,
        foundationWallCompositeDocsByWallId,
        drawingData,
      );
      if (handledFW) return;
      final handledWalling = await it.handleWallViewTap(
        imagePos,
        segments,
        wallCDocsByWallId,
        drawingData,
      );
      if (handledWalling) return;
      final handledLength = await it.handlelineViewTap(
        imagePos,
        segments,
        wallCDocsByWallId,
        drawingData,
      );
      if (handledLength) return;
      final handledCF = await it.handlelineViewTap(
        imagePos,
        segments,
        ceilingFinishId,
        drawingData,
      );
      if (handledCF) return;
      final stairlength = await it.handlelineViewTap(
        imagePos,
        segments,
        ceilingFinishId,
        drawingData,
      );
      if (stairlength) return;

      // final handledWalling = await it.handleWallingViewTap(imagePos, segments as Map<String, dynamic>);
      // if (handledWalling) return;

      // return;
    }

    // ======================
    // CALIBRATE
    // ======================
    if (mode.value == TakeoffMode.calibrate) {
      await it.handleCalibrateTap(imagePos, drawingData);
      return;
    }

    // ======================
    // MEASURE LENGTH ✅ merged here
    // ======================
    if (mode.value == TakeoffMode.measureLength) {
      await _handleMeasureLengthTap(
        imagePos: imagePos,
        drawingData: drawingData,
        currentWallId: currentWallId,
        segments: segments,
      );
      return;
    }

    // ======================
    // MEASURE AREA
    // ======================
    if (mode.value == TakeoffMode.measureArea) {
      await handleAreaTap(context, imagePos, drawingData);
      return;
    }

    // ======================
    // EDIT SEGMENT (optional)
    // ======================
    // if (mode.value == TakeoffMode.editSegment) {
    //   await it.handleSegmentTap(imagePos, segments);
    //   return;
    // }
  }

  Future<void> handleStairTapP1P2({
    required Offset p1,
    required Offset p2,
    required Map<String, dynamic> drawingData,

    VoidCallback? onUpdateViewer,
  }) async {
    // validate calibration
    final calibrated = drawingData['calibrated'] == true;
    final pxPerM = _num(drawingData['pixelsPerUnit'], 0);
    if (!calibrated || pxPerM <= 0) {
      Get.snackbar(
        'Not calibrated',
        'Calibrate drawing first (pixelsPerUnit).',
      );
      return;
    }

    // final world = toWorld(local: localPos, tCtrl: tCtrl);
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final lengthPx = math.sqrt(dx * dx + dy * dy);

    final lenM = distanceInMeters(p1, p2, drawingData);
    if (lenM == null || lenM <= 0) {
      Get.snackbar('Starir', 'Invalid length (check calibration).');
      return;
    }

    // open dialog right away
    await it.openStairCompositeFromSegments(
      p1: p1,
      p2: p2,
      // baseLenM: lenM,
      drawingData: drawingData,
      projectId: projectId,
      buildingId: buildingId,
      drawingId: drawingId,
      currentColor: currentColor,
      activeLabel: activeLabel,
      measurementsRef: measurementsRef,
      // showBoqPickerDialog: showBoqPickerDialog,
      onUpdateViewer: onUpdateViewer,
    );
  }

  Future<void> handleRampTapP1P2({
    required Offset p1,
    required Offset p2,
    required Map<String, dynamic> drawingData,

    VoidCallback? onUpdateViewer,
  }) async {
    // validate calibration
    final calibrated = drawingData['calibrated'] == true;
    final pxPerM = _num(drawingData['pixelsPerUnit'], 0);
    if (!calibrated || pxPerM <= 0) {
      Get.snackbar(
        'Not calibrated',
        'Calibrate drawing first (pixelsPerUnit).',
      );
      return;
    }

    // final world = toWorld(local: localPos, tCtrl: tCtrl);
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final lengthPx = math.sqrt(dx * dx + dy * dy);

    final lenM = distanceInMeters(p1, p2, drawingData);
    if (lenM == null || lenM <= 0) {
      Get.snackbar('Starir', 'Invalid length (check calibration).');
      return;
    }

    // open dialog right away
    await it.openRampCompositeFromSegments(
      p1: p1,
      p2: p2,
      // baseLenM: lenM,
      drawingData: drawingData,
      projectId: projectId,
      buildingId: buildingId,
      drawingId: drawingId,
      currentColor: currentColor,
      activeLabel: activeLabel,
      measurementsRef: measurementsRef,
      // showBoqPickerDialog: showBoqPickerDialog,
      onUpdateViewer: onUpdateViewer,
    );
  }

  Future<void> _saveActiveMeasureConfig() async {
    final mt = (activeMeasureType ?? '').trim().toLowerCase();
    if (mt.isEmpty) return;

    await measureConfigsRef.doc(mt).set({
      'measureType': mt,
      'label': (activeLabel ?? '').trim(),
      'unit': (activeUnit ?? '').trim(),
      'boqCode': (activeBoqCode ?? '').trim(),
      'wallHeightM': activeHeightM,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> savePreview() async {
    final unit = activeUnit ?? 'm';
    final walling = isWallingActive;
    double? heightForThis;

    if (previewP1 == null || previewP2 == null) return;

    if (unit == 'm2' && walling) {
      final hVal = double.tryParse(previewHeightController.text.trim());
      if (hVal == null || hVal <= 0) {
        Get.snackbar('Invalid', 'Please enter a valid height.');
        return;
      }
      heightForThis = hVal;
      activeHeightM = hVal; // keep it as current config
    }

    if (previewP1 != null && previewP2 != null) {
      await saveMeasurement(
        p1: previewP1!,
        p2: previewP2!,
        lengthMeters: previewLengthMeters,
        overrideHeightM: heightForThis,
      );

      // ✅ Persist the measuring config used for this save
      await _saveActiveMeasureConfig();
    }

    hidePreview();
    update(['topbar', 'summary', 'preview']);
  }

  StrokeMode strokeMode = StrokeMode.constantOnScreen;

  double baseStroke = 5.0; // ✅ NORMAL
  final double minStroke = 0.5;
  final double maxStroke = 10.0;

  void setBaseStroke(double v) {
    baseStroke = v.clamp(minStroke, maxStroke);
    update(['viewer', 'topbar']);
  }

  void setStrokeMode(StrokeMode m) {
    strokeMode = m;
    update(['viewer', 'topbar']);
  }

  void resetStrokeNormal() {
    baseStroke = 2.0;
    update(['viewer', 'topbar']);
  }

  // ===== Dots =====
  DotMode dotMode = DotMode.chainEndpointsOnly;

  double dotRadius = 7.0; // ✅ NORMAL
  final double minDot = 1;
  final double maxDot = 15.0;

  Color dotColor = Colors.red;
  bool dotsFollowSegmentColor = false;
  DotScaleMode dotScaleMode = DotScaleMode.constantOnScreen;

  void setDotRadius(double v) {
    dotRadius = v.clamp(minDot, maxDot);
    update(['viewer', 'topbar']);
  }

  void setDotMode(DotMode m) {
    dotMode = m;
    update(['viewer', 'topbar']);
  }

  void setDotColor(Color c) {
    dotColor = c;
    update(['viewer', 'topbar']);
  }

  void setDotsFollowSegment(bool v) {
    dotsFollowSegmentColor = v;
    update(['viewer', 'topbar']);
  }

  void resetDotsNormal() {
    dotRadius = 4.0;
    dotColor = Colors.black;
    dotMode = DotMode.chainEndpointsOnly;
    dotsFollowSegmentColor = false;
    update(['viewer', 'topbar']);
  }

  void setDotScaleMode(DotScaleMode m) {
    dotScaleMode = m;
    update(['viewer', 'topbar']);
  }

  Future<bool> deleteSelectedSegment() async {
    final selId = selectedSegmentId;
    if (selId == null || selId.isEmpty) return false;

    // find the segment (you may already have it in memory)
    final seg = lastSegments.firstWhereOrNull((s) => s.id == selId);
    if (seg == null) return false;

    final ok =
        await Get.dialog<bool>(
          AlertDialog(
            title: const Text('Delete selected measurement?'),
            content: const Text(
              'This will remove the selected segment and its saved measurement.',
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(result: false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Get.back(result: true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return false;

    final selectedRef = measurementsRef.doc(seg.docId);
    final selectedSnapshot = await selectedRef.get();
    final selectedData = selectedSnapshot.data();
    final measureType =
        (selectedData?['measureType'] ?? seg.measureType ?? '')
            .toString()
            .trim()
            .toLowerCase();
    final isCompositeBeam =
        measureType == 'compositebeam' || measureType == 'beamcomposite';
    final segmentId = (selectedData?['segmentId'] ?? '').toString().trim();

    if (isCompositeBeam && segmentId.isNotEmpty) {
      final related =
          await measurementsRef.where('segmentId', isEqualTo: segmentId).get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in related.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } else {
      await selectedRef.delete();
    }

    selectedSegmentId = null;
    lastSegments.removeWhere(
      (segment) =>
          segment.docId == seg.docId ||
          (segmentId.isNotEmpty && segment.groupId == segmentId),
    );
    update(['viewer', 'summary']);
    return true;
  }

  Future<bool> editSelectedMeasurement() async {
    final selId = selectedSegmentId;
    if (selId == null || selId.isEmpty) return false;

    final seg = lastSegments.firstWhereOrNull((segment) => segment.id == selId);
    if (seg == null) return false;

    final selectedSnapshot = await measurementsRef.doc(seg.docId).get();
    final selectedData = selectedSnapshot.data();
    if (selectedData == null) return false;

    final measureType =
        (selectedData['measureType'] ?? seg.measureType ?? '')
            .toString()
            .trim()
            .toLowerCase();

    if (measureType == 'compositebeam' || measureType == 'beamcomposite') {
      final segmentId = (selectedData['segmentId'] ?? '').toString().trim();
      if (segmentId.isEmpty) return false;

      final snapshot =
          await measurementsRef.where('segmentId', isEqualTo: segmentId).get();
      final docs =
          snapshot.docs.where((doc) {
            final type =
                (doc.data()['measureType'] ?? '').toString().toLowerCase();
            return type == 'compositebeam' || type == 'beamcomposite';
          }).toList();
      if (docs.isEmpty) return false;

      final beamType =
          (selectedData['beamType'] ?? selectedData['beamName'] ?? 'Beam')
              .toString()
              .trim();

      await it.showBeamCompositeDetailsDialog(
        beamId: segmentId,
        docs: docs,
        beamType: beamType.isEmpty ? 'Beam' : beamType,
      );
      return true;
    }

    return false;
  }

  List<MeasuredSegment> lastSegments = [];
  final Map<String, Map<String, dynamic>> _visibleMeasurementDataByDocId = {};
  bool _selectionInspectorLoading = false;

  void cacheVisibleMeasurementDocuments(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) {
    _visibleMeasurementDataByDocId
      ..clear()
      ..addEntries(
        documents.map(
          (document) => MapEntry(document.id, <String, dynamic>{
            'id': document.id,
            ...document.data(),
          }),
        ),
      );
  }

  Future<bool> updateSelectedSegmentStyle({
    required Color color,
    required double strokeWidth,
  }) async {
    final selId = selectedSegmentId;
    if (selId == null || selId.isEmpty) return false;

    final seg = lastSegments.firstWhereOrNull((s) => s.id == selId);
    if (seg == null) return false;

    final lineWeight = strokeWidth.clamp(minStroke, maxStroke).toDouble();
    await measurementsRef.doc(seg.docId).update({
      'color': color.value,
      'strokeWidth': lineWeight,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    seg.color = color;
    seg.strokeWidth = lineWeight;
    update(['viewer', 'summary']);
    return true;
  }

  MapEntry<String, String>? _savedMeasurementGroup(Map<String, dynamic> data) {
    for (final field in const [
      // Prefer the exact drawn geometry. Broader assembly/session ids can
      // contain several separately selectable polygons or lines.
      'segmentId',
      'areaGroupId',
      'lengthGroupId',
      'roadProfileGroupId',
      'assemblyId',
      'groundPreparationGroupId',
      'plinthGroupId',
      'pavementGroupId',
      'finishGroupId',
      'areaSessionId',
      'wallGroupId',
      'beamId',
      'footingGroupId',
      'slabGroupId',
      'slabId',
      'columnGroupId',
      'columnId',
      'roofGroupId',
      'ceilingGroupId',
      'tileGroupId',
      'foundationGroupId',
      'foundationWallId',
      'stairId',
      'rampId',
      'civilWorkId',
    ]) {
      final value = (data[field] ?? '').toString().trim();
      if (value.isNotEmpty) return MapEntry(field, value);
    }
    return null;
  }

  Future<void> _deleteSavedMeasurement(
    String docId,
    Map<String, dynamic> data,
  ) async {
    final group = _savedMeasurementGroup(data);
    final cachedGroup = _cachedMeasurementGroup(data);
    final count =
        group == null
            ? 1
            : cachedGroup.isNotEmpty
            ? cachedGroup.length
            : (await measurementsRef
                    .where(group.key, isEqualTo: group.value)
                    .get())
                .docs
                .length;
    final confirmed =
        await Get.dialog<bool>(
          AlertDialog(
            title: const Text('Delete measurement?'),
            content: Text(
              count > 1
                  ? 'This removes the complete grouped measurement ($count saved items).'
                  : 'This removes the selected measurement.',
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(result: false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Get.back(result: true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _withSelectionLoadingOverlay(() async {
      if (group == null) {
        await measurementsRef.doc(docId).delete();
        return;
      }
      final cachedIds =
          cachedGroup
              .map((item) => (item['id'] ?? '').toString().trim())
              .where((id) => id.isNotEmpty)
              .toList();
      final ids =
          cachedIds.isNotEmpty
              ? cachedIds
              : (await measurementsRef
                      .where(group.key, isEqualTo: group.value)
                      .get())
                  .docs
                  .map((document) => document.id)
                  .toList();
      final batch = FirebaseFirestore.instance.batch();
      for (final id in ids) {
        batch.delete(measurementsRef.doc(id));
      }
      await batch.commit();
    }, message: 'Deleting measurement…');
    selectedSegmentId = null;
    selectedAreaId = null;
    update(['viewer', 'summary']);
  }

  List<Map<String, dynamic>> _cachedMeasurementGroup(
    Map<String, dynamic> selectedData,
  ) {
    final group = _savedMeasurementGroup(selectedData);
    if (group == null) return [selectedData];
    return _visibleMeasurementDataByDocId.values
        .where(
          (item) => (item[group.key] ?? '').toString().trim() == group.value,
        )
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<T> _withSelectionLoadingOverlay<T>(
    Future<T> Function() load, {
    String message = 'Loading measurement details…',
  }) async {
    final hostContext = Get.context;
    if (hostContext == null) return load();

    BuildContext? progressContext;
    final overlayClosed = showDialog<void>(
      context: hostContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        progressContext = dialogContext;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 14),
                Text(
                  message,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        );
      },
    );
    await WidgetsBinding.instance.endOfFrame;

    try {
      return await load();
    } finally {
      if (progressContext?.mounted == true) {
        Navigator.of(progressContext!).pop();
      }
      await overlayClosed;
    }
  }

  Future<({Map<String, dynamic> data, List<Map<String, dynamic>> grouped})?>
  _loadSavedMeasurementInspectorData(String docId) async {
    final cached = _visibleMeasurementDataByDocId[docId];
    if (cached != null) {
      final grouped = _cachedMeasurementGroup(cached);
      if (grouped.isNotEmpty) {
        return (data: Map<String, dynamic>.from(cached), grouped: grouped);
      }
    }

    return _withSelectionLoadingOverlay(() async {
      final selectedSnapshot = await measurementsRef
          .doc(docId)
          .get()
          .timeout(const Duration(seconds: 8));
      final selected = selectedSnapshot.data();
      if (selected == null) return null;
      final selectedData = <String, dynamic>{
        'id': selectedSnapshot.id,
        ...selected,
      };
      final group = _savedMeasurementGroup(selectedData);
      if (group == null) {
        return (data: selectedData, grouped: [selectedData]);
      }
      final related = await measurementsRef
          .where(group.key, isEqualTo: group.value)
          .get()
          .timeout(const Duration(seconds: 8));
      final grouped =
          related.docs
              .map(
                (document) => <String, dynamic>{
                  'id': document.id,
                  ...document.data(),
                },
              )
              .toList();
      return (data: selectedData, grouped: grouped);
    });
  }

  Future<void> _openSavedMeasurementInspector(
    String docId, {
    int? selectedPolylineIndex,
  }) async {
    if (_selectionInspectorLoading) return;
    _selectionInspectorLoading = true;
    try {
      final loaded = await _loadSavedMeasurementInspectorData(docId);
      if (loaded == null) {
        Get.snackbar(
          'Measurement unavailable',
          'This saved measurement could not be found.',
        );
        return;
      }
      final groupedData = _withCurrentInspectorBoqCodes(loaded.grouped);
      final selectedData =
          groupedData.firstWhereOrNull(
            (item) => (item['id'] ?? '').toString() == docId,
          ) ??
          loaded.data;
      await _showSavedMeasurementInspector(
        docId: docId,
        data: selectedData,
        groupedData: groupedData,
        selectedPolylineIndex: selectedPolylineIndex,
      );
    } on TimeoutException {
      Get.snackbar(
        'Loading took too long',
        'Check the connection and tap the measurement again.',
      );
    } catch (exception) {
      Get.snackbar('Could not open measurement', exception.toString());
    } finally {
      _selectionInspectorLoading = false;
    }
  }

  List<Map<String, dynamic>> _withCurrentInspectorBoqCodes(
    List<Map<String, dynamic>> measurements,
  ) {
    if (!Get.isRegistered<ProjectBuildingsController>()) {
      return measurements;
    }
    final boqRows =
        Get.find<ProjectBuildingsController>()
            .boqFor(projectId, buildingId)
            .map(Map<String, dynamic>.from)
            .toList();
    if (boqRows.isEmpty) return measurements;

    final boqById = <String, Map<String, dynamic>>{
      for (final row in boqRows)
        if ((row['id'] ?? '').toString().trim().isNotEmpty)
          (row['id'] ?? '').toString().trim(): row,
    };
    return measurements.map((measurement) {
      final result = Map<String, dynamic>.from(measurement);
      final boqItemId = (result['boqItemId'] ?? '').toString().trim();
      final boqRow = boqById[boqItemId];
      if (boqRow == null) return result;
      final resolvedCode = hierarchicalBoqCodeFromRows(boqRow, boqRows).trim();
      if (resolvedCode.isNotEmpty) result['resolvedBoqCode'] = resolvedCode;
      final description = (boqRow['description'] ?? '').toString().trim();
      if (description.isNotEmpty) result['boqDescription'] = description;
      return result;
    }).toList();
  }

  double _wallNumber(dynamic value, [double fallback = 0]) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

  Map<String, dynamic> _wallPointMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Map<String, dynamic>> _editableWallSegments(Map<String, dynamic> data) {
    final defaultHeight = _wallNumber(data['heightM']);
    final raw = data['polylineSegments'];
    final result = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final segment = Map<String, dynamic>.from(item);
        final p1 = _wallPointMap(segment['p1']);
        final p2 = _wallPointMap(segment['p2']);
        if (p1.isEmpty || p2.isEmpty) continue;
        segment['p1'] = p1;
        segment['p2'] = p2;
        segment['heightM'] = _wallNumber(segment['heightM'], defaultHeight);
        result.add(segment);
      }
    }
    if (result.isNotEmpty) return result;

    final p1 = _wallPointMap(data['p1']);
    final p2 = _wallPointMap(data['p2']);
    if (p1.isEmpty || p2.isEmpty) return result;
    return [
      <String, dynamic>{
        'p1': p1,
        'p2': p2,
        'lengthM': _wallNumber(
          data['lengthM'] ?? data['baseLengthM'] ?? data['totalLengthM'],
        ),
        'heightM': defaultHeight,
      },
    ];
  }

  double _wallSegmentLength(Map<String, dynamic> segment) {
    final saved = _wallNumber(segment['lengthM']);
    if (saved > 0) return saved;
    final p1 = _wallPointMap(segment['p1']);
    final p2 = _wallPointMap(segment['p2']);
    final dx = _wallNumber(p2['x']) - _wallNumber(p1['x']);
    final dy = _wallNumber(p2['y']) - _wallNumber(p1['y']);
    final lengthPx = math.sqrt(dx * dx + dy * dy);
    final savedPx = _wallNumber(segment['lengthPx']);
    return savedPx > 0 ? lengthPx / savedPx * saved : 0;
  }

  double? _wallSurfaceMultiplier(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString().trim().toLowerCase();
    if (type == 'wallingnet') return 1;
    if (type == 'finishinternalplaster' || type == 'finishinternalpaint') {
      return _wallNumber(data['internalFinishFaces'] ?? data['faces'], 1);
    }
    if (type == 'finishexternalrender' || type == 'finishexternalpaint') {
      return _wallNumber(data['externalFinishFaces'] ?? data['faces'], 1);
    }
    if (type == 'finishinternaltiles') {
      return _wallNumber(data['internalTileFaces'] ?? data['faces'], 1);
    }
    if (type == 'finishexternaltiles') {
      return _wallNumber(data['externalTileFaces'] ?? data['faces'], 1);
    }
    if (type == 'tilebackingbed') {
      final surface = (data['surface'] ?? '').toString().toLowerCase();
      return surface == 'external'
          ? _wallNumber(data['externalTileFaces'] ?? data['faces'], 1)
          : _wallNumber(data['internalTileFaces'] ?? data['faces'], 1);
    }
    return null;
  }

  Future<void> _saveWallSegmentGeometry({
    required Map<String, dynamic> selectedData,
    required List<Map<String, dynamic>> groupedData,
    required List<Map<String, dynamic>> segments,
  }) async {
    if (segments.isEmpty) {
      throw StateError('At least one wall portion must remain.');
    }

    final segmentId = (selectedData['segmentId'] ?? '').toString().trim();
    List<QueryDocumentSnapshot<Map<String, dynamic>>> snapshots = const [];
    if (segmentId.isNotEmpty) {
      snapshots =
          (await measurementsRef.where('segmentId', isEqualTo: segmentId).get())
              .docs
              .where(
                (snapshot) =>
                    (snapshot.data()['drawingId'] ?? '').toString() ==
                    drawingId,
              )
              .toList();
    }

    final dataById = <String, Map<String, dynamic>>{
      for (final item in groupedData)
        if ((item['id'] ?? '').toString().trim().isNotEmpty)
          (item['id'] ?? '').toString().trim(): item,
      for (final snapshot in snapshots) snapshot.id: snapshot.data(),
    };
    if (dataById.isEmpty) {
      final id = (selectedData['id'] ?? '').toString().trim();
      if (id.isNotEmpty) dataById[id] = selectedData;
    }

    var totalLengthM = 0.0;
    var grossAreaPerWallM2 = 0.0;
    for (final segment in segments) {
      final length = _wallSegmentLength(segment);
      final height = _wallNumber(
        segment['heightM'],
        _wallNumber(selectedData['heightM']),
      );
      segment['lengthM'] = length;
      segment['heightM'] = height;
      totalLengthM += length;
      grossAreaPerWallM2 += length * height;
    }

    final quantityWalls = _wallNumber(
      selectedData['qtyWallsPerBuilding'],
      1,
    ).clamp(1, 999999);
    final buildingFactor = _wallNumber(
      selectedData['buildingFactor'],
      1,
    ).clamp(1, 999999);
    final openingsPerBuilding = _wallNumber(
      selectedData['openingsAreaPerBuildingM2'],
    );
    final grossPerBuilding = grossAreaPerWallM2 * quantityWalls;
    final netPerBuilding = math.max(0, grossPerBuilding - openingsPerBuilding);
    final grossTotal = grossPerBuilding * buildingFactor;
    final openingsTotal = openingsPerBuilding * buildingFactor;
    final netTotal = netPerBuilding * buildingFactor;
    final effectiveHeight =
        totalLengthM > 0 ? grossAreaPerWallM2 / totalLengthM : 0.0;
    final now = FieldValue.serverTimestamp();
    final firstPoint = _wallPointMap(segments.first['p1']);
    final lastPoint = _wallPointMap(segments.last['p2']);

    final batch = FirebaseFirestore.instance.batch();
    for (final entry in dataById.entries) {
      final item = entry.value;
      final updates = <String, dynamic>{
        'polylineSegments': segments,
        'wallSegmentCount': segments.length,
        'p1': firstPoint,
        'p2': lastPoint,
        'lengthM': totalLengthM,
        'baseLengthM': totalLengthM,
        'totalLengthM': totalLengthM,
        'heightM': effectiveHeight,
        'grossAreaPerBuildingM2': grossPerBuilding,
        'openingsAreaPerBuildingM2': openingsPerBuilding,
        'netAreaPerBuildingM2': netPerBuilding,
        'grossAreaTotalM2': grossTotal,
        'openingsAreaTotalM2': openingsTotal,
        'netAreaTotalM2': netTotal,
        'updatedAt': now,
      };
      final multiplier = _wallSurfaceMultiplier(item);
      if (multiplier != null) {
        final perBuilding = netPerBuilding * multiplier;
        final total = perBuilding * buildingFactor;
        updates['valuePerBuilding'] = perBuilding;
        updates['value'] = total;
        updates['quantity'] = total;
      }
      batch.update(measurementsRef.doc(entry.key), updates);
    }
    await batch.commit();
  }

  Future<List<Map<String, dynamic>>?> _cutWallSegmentDialog({
    required BuildContext context,
    required List<Map<String, dynamic>> segments,
    required int segmentIndex,
  }) async {
    final source = Map<String, dynamic>.from(segments[segmentIndex]);
    final sourceLength = _wallSegmentLength(source);
    final sourceHeight = _wallNumber(source['heightM']);
    final fromController = TextEditingController(text: '0.000');
    final lengthController = TextEditingController(
      text: (sourceLength / 2).toStringAsFixed(3),
    );
    final heightController = TextEditingController(
      text: sourceHeight.toStringAsFixed(3),
    );
    var deletePortion = false;
    String? error;

    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  title: const Text('Cut wall portion'),
                  content: SizedBox(
                    width: 440,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Segment ${segmentIndex + 1} · ${sourceLength.toStringAsFixed(3)} m long · ${sourceHeight.toStringAsFixed(3)} m high',
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: fromController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Cut starts at (m)',
                                  helperText: '0 starts at the first point',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: lengthController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Portion length (m)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: false,
                              icon: Icon(Icons.edit_outlined),
                              label: Text('Update portion'),
                            ),
                            ButtonSegment(
                              value: true,
                              icon: Icon(Icons.delete_outline),
                              label: Text('Delete portion'),
                            ),
                          ],
                          selected: {deletePortion},
                          onSelectionChanged:
                              (value) =>
                                  setState(() => deletePortion = value.first),
                        ),
                        if (!deletePortion) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: heightController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'New height for cut portion (m)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                        if (error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            error!,
                            style: const TextStyle(color: Color(0xFFB42318)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        final start = double.tryParse(
                          fromController.text.trim(),
                        );
                        final cutLength = double.tryParse(
                          lengthController.text.trim(),
                        );
                        final newHeight = double.tryParse(
                          heightController.text.trim(),
                        );
                        if (start == null ||
                            cutLength == null ||
                            start < 0 ||
                            cutLength <= 0 ||
                            start + cutLength > sourceLength + 0.000001) {
                          setState(
                            () =>
                                error =
                                    'The cut must stay within the ${sourceLength.toStringAsFixed(3)} m segment.',
                          );
                          return;
                        }
                        if (!deletePortion &&
                            (newHeight == null || newHeight <= 0)) {
                          setState(() => error = 'Enter a valid new height.');
                          return;
                        }

                        final p1 = _wallPointMap(source['p1']);
                        final p2 = _wallPointMap(source['p2']);
                        final x1 = _wallNumber(p1['x']);
                        final y1 = _wallNumber(p1['y']);
                        final x2 = _wallNumber(p2['x']);
                        final y2 = _wallNumber(p2['y']);
                        Map<String, dynamic> pointAt(double distance) {
                          final t = (distance / sourceLength).clamp(0.0, 1.0);
                          return <String, dynamic>{
                            'x': x1 + (x2 - x1) * t,
                            'y': y1 + (y2 - y1) * t,
                          };
                        }

                        Map<String, dynamic> piece(
                          double from,
                          double to,
                          double height,
                        ) {
                          final ratio = (to - from) / sourceLength;
                          return <String, dynamic>{
                            ...source,
                            'p1': pointAt(from),
                            'p2': pointAt(to),
                            'lengthM': to - from,
                            if (_wallNumber(source['lengthPx']) > 0)
                              'lengthPx':
                                  _wallNumber(source['lengthPx']) * ratio,
                            'heightM': height,
                          };
                        }

                        final replacement = <Map<String, dynamic>>[];
                        const epsilon = 0.000001;
                        if (start > epsilon) {
                          replacement.add(piece(0, start, sourceHeight));
                        }
                        if (!deletePortion) {
                          replacement.add(
                            piece(start, start + cutLength, newHeight!),
                          );
                        }
                        if (start + cutLength < sourceLength - epsilon) {
                          replacement.add(
                            piece(
                              start + cutLength,
                              sourceLength,
                              sourceHeight,
                            ),
                          );
                        }
                        final updated =
                            segments.map(Map<String, dynamic>.from).toList();
                        updated.replaceRange(
                          segmentIndex,
                          segmentIndex + 1,
                          replacement,
                        );
                        if (updated.isEmpty) {
                          setState(
                            () =>
                                error =
                                    'Use Delete measurement to remove the complete wall.',
                          );
                          return;
                        }
                        Navigator.pop(context, updated);
                      },
                      icon: Icon(
                        deletePortion
                            ? Icons.delete_outline
                            : Icons.call_split_rounded,
                      ),
                      label: Text(
                        deletePortion ? 'Delete portion' : 'Apply update',
                      ),
                    ),
                  ],
                ),
          ),
    );
    fromController.dispose();
    lengthController.dispose();
    heightController.dispose();
    return result;
  }

  Future<void> _showSavedMeasurementInspector({
    required String docId,
    required Map<String, dynamic> data,
    required List<Map<String, dynamic>> groupedData,
    int? selectedPolylineIndex,
  }) async {
    var selectedDocId = docId;
    var selectedData = Map<String, dynamic>.from(data);
    String boqCodeOf(Map<String, dynamic> item) {
      for (final value in [item['resolvedBoqCode'], item['boqCode']]) {
        final code = (value ?? '').toString().trim();
        if (code.isNotEmpty) return code;
      }
      return '';
    }

    String quantityOf(Map<String, dynamic> item) {
      final raw = item['quantity'] ?? item['value'];
      final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (value == null) return '—';
      final unit = (item['unit'] ?? item['boqUnit'] ?? '').toString();
      final decimals = unit.toLowerCase().contains('no') ? 0 : 3;
      return '${value.toStringAsFixed(decimals)} $unit'.trim();
    }

    final labelController = TextEditingController(
      text: (selectedData['label'] ?? selectedData['title'] ?? '').toString(),
    );
    final quantityValue =
        selectedData['quantity'] is num
            ? (selectedData['quantity'] as num).toDouble()
            : selectedData['value'] is num
            ? (selectedData['value'] as num).toDouble()
            : double.tryParse(
              '${selectedData['quantity'] ?? selectedData['value'] ?? ''}',
            );
    final quantityController = TextEditingController(
      text: quantityValue?.toString() ?? '',
    );
    final unitController = TextEditingController(
      text: (selectedData['unit'] ?? selectedData['boqUnit'] ?? '').toString(),
    );
    var boqItemId = (selectedData['boqItemId'] ?? '').toString();
    var boqCode = boqCodeOf(selectedData);
    var boqDescription = (selectedData['boqDescription'] ?? '').toString();
    var saving = false;
    String? error;
    final groupedItems = groupedData.length;
    final isWalling =
        (data['measureType'] ?? data['type'] ?? '')
            .toString()
            .trim()
            .toLowerCase() ==
        'walling';
    final isRoadProfile =
        (data['measureType'] ?? data['type'] ?? '')
            .toString()
            .trim()
            .toLowerCase() ==
        'roadprofile';
    final isSlabRebar =
        (data['measureType'] ?? data['type'] ?? '')
            .toString()
            .trim()
            .toLowerCase() ==
        'slabrebarai';
    double rebarNumber(dynamic value, [double fallback = 0]) =>
        value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;
    String rebarText(dynamic value, [String fallback = '']) {
      final text = (value ?? '').toString().trim();
      return text.isEmpty ? fallback : text;
    }
    final rebarMarkController = TextEditingController(
      text: rebarText(selectedData['barMark'], rebarText(selectedData['mark'], '01')),
    );
    final rebarDiameterController = TextEditingController(
      text: rebarNumber(selectedData['diameterMm'], 12).toStringAsFixed(0),
    );
    final rebarLengthController = TextEditingController(
      text: rebarNumber(
        selectedData['measuredLengthM'],
        rebarNumber(selectedData['barLengthM']),
      ).toStringAsFixed(3),
    );
    final rebarCountController = TextEditingController(
      text: rebarNumber(
        selectedData['numberOfBars'],
        rebarNumber(selectedData['barsCount'], 1),
      ).toStringAsFixed(0),
    );
    final rebarSpacingController = TextEditingController(
      text: rebarNumber(selectedData['spacingMm'], 150).toStringAsFixed(0),
    );
    final rebarFactorController = TextEditingController(
      text: rebarNumber(
        selectedData['groupFactor'],
        rebarNumber(selectedData['multiplyingFactor'], 1),
      ).toStringAsFixed(2),
    );
    var rebarLayer = rebarText(selectedData['layer'], 'T1');
    var rebarDirection = rebarText(selectedData['direction'], 'X');
    double roadNumber(dynamic value) =>
        value is num ? value.toDouble() : double.tryParse('$value') ?? 0.0;
    String roadKey(Map<String, dynamic> item) =>
        (item['roadProfileOutputKey'] ?? '').toString().trim().toLowerCase();
    bool roadUsesClearingWidth(String key) => key == 'clearing';
    bool roadUsesEarthworkWidth(String key) =>
        const {'topsoil', 'common_excavation', 'fill'}.contains(key);
    String roadWidthField(String key) =>
        roadUsesClearingWidth(key)
            ? 'roadClearingWidthM'
            : roadUsesEarthworkWidth(key)
            ? 'roadEarthworkWidthM'
            : 'roadPavementWidthM';
    const roadThicknessFields = <String, String>{
      'topsoil': 'topsoilThicknessMm',
      'common_excavation': 'commonExcavationDepthMm',
      'fill': 'fillDepthMm',
      'ac14_wearing_course': 'ac14ThicknessMm',
      'bitumen_binder': 'ac14ThicknessMm',
      'crr_base': 'crrBaseThicknessMm',
      'c1_subbase': 'c1SubbaseThicknessMm',
      'g15_upper_subgrade': 'g15UpperSubgradeThicknessMm',
      'g7_lower_subgrade': 'g7LowerSubgradeThicknessMm',
      'cement_stabiliser': 'stabilisedLayerDepthMm',
    };
    bool roadIsMc30(String key) =>
        key == 'mc30_prime_coat' || key == 'mc30_curing_membrane';
    String roadRateField(String key) =>
        key == 'mc30_curing_membrane'
            ? 'mc30CuringMembraneRateLPerM2'
            : 'mc30PrimeCoatRateLPerM2';
    final roadWidthControllers = <String, TextEditingController>{};
    final roadThicknessControllers = <String, TextEditingController>{};
    final roadRateControllers = <String, TextEditingController>{};
    for (final item in groupedData) {
      final id = (item['id'] ?? '').toString();
      final key = roadKey(item);
      roadWidthControllers[id] = TextEditingController(
        text: '${item[roadWidthField(key)] ?? 0}',
      );
      final thicknessField = roadThicknessFields[key];
      if (thicknessField != null) {
        roadThicknessControllers[id] = TextEditingController(
          text: '${item[thicknessField] ?? 0}',
        );
      }
      if (roadIsMc30(key)) {
        roadRateControllers[id] = TextEditingController(
          text: '${item[roadRateField(key)] ?? 0}',
        );
      }
    }

    double? roadQuantity(Map<String, dynamic> item) {
      final id = (item['id'] ?? '').toString();
      final key = roadKey(item);
      final length = roadNumber(item['lengthM']);
      final width = double.tryParse(
        roadWidthControllers[id]?.text.trim() ?? '',
      );
      if (length <= 0 || width == null || width <= 0) return null;
      if (roadUsesClearingWidth(key)) return length * width / 10000.0;
      if (roadIsMc30(key)) {
        final rate = double.tryParse(
          roadRateControllers[id]?.text.trim() ?? '',
        );
        if (rate == null || rate < 0) return null;
        return length * width * rate;
      }
      final thickness = double.tryParse(
        roadThicknessControllers[id]?.text.trim() ?? '',
      );
      if (thickness == null || thickness < 0) return null;
      final volume = length * width * thickness / 1000.0;
      if (key == 'bitumen_binder') {
        return volume *
            roadNumber(item['asphaltDensityTPerM3']) *
            roadNumber(item['bitumenContentPercent']) /
            100.0;
      }
      if (key == 'cement_stabiliser') {
        return volume *
            roadNumber(item['stabilisedDryDensityTPerM3']) *
            roadNumber(item['cementContentPercent']) /
            100.0;
      }
      return volume;
    }

    var wallSegments =
        isWalling ? _editableWallSegments(data) : <Map<String, dynamic>>[];
    var activeWallSegmentIndex =
        wallSegments.isEmpty
            ? 0
            : math.min(
              math.max(selectedPolylineIndex ?? 0, 0),
              wallSegments.length - 1,
            );
    final wallHeightController = TextEditingController(
      text:
          wallSegments.isEmpty
              ? ''
              : _wallNumber(
                wallSegments[activeWallSegmentIndex]['heightM'],
              ).toStringAsFixed(3),
    );

    void selectGroupedItem(Map<String, dynamic> item, StateSetter setState) {
      setState(() {
        selectedData = Map<String, dynamic>.from(item);
        selectedDocId = (item['id'] ?? selectedDocId).toString();
        labelController.text =
            (item['label'] ?? item['title'] ?? '').toString();
        quantityController.text =
            (item['quantity'] ?? item['value'] ?? '').toString();
        unitController.text =
            (item['unit'] ?? item['boqUnit'] ?? '').toString();
        boqItemId = (item['boqItemId'] ?? '').toString();
        boqCode = boqCodeOf(item);
        boqDescription = (item['boqDescription'] ?? '').toString();
        if (isSlabRebar) {
          rebarMarkController.text = rebarText(
            item['barMark'],
            rebarText(item['mark'], '01'),
          );
          rebarDiameterController.text = rebarNumber(
            item['diameterMm'],
            12,
          ).toStringAsFixed(0);
          rebarLengthController.text = rebarNumber(
            item['measuredLengthM'],
            rebarNumber(item['barLengthM']),
          ).toStringAsFixed(3);
          rebarCountController.text = rebarNumber(
            item['numberOfBars'],
            rebarNumber(item['barsCount'], 1),
          ).toStringAsFixed(0);
          rebarSpacingController.text = rebarNumber(
            item['spacingMm'],
            150,
          ).toStringAsFixed(0);
          rebarFactorController.text = rebarNumber(
            item['groupFactor'],
            rebarNumber(item['multiplyingFactor'], 1),
          ).toStringAsFixed(2);
          rebarLayer = rebarText(item['layer'], 'T1');
          rebarDirection = rebarText(item['direction'], 'X');
        }
        error = null;
      });
    }

    await Get.dialog<void>(
      StatefulBuilder(
        builder:
            (context, setState) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text('Selected measurement'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (selectedData['measureType'] ??
                                selectedData['type'] ??
                                'Measurement')
                            .toString(),
                        style: const TextStyle(
                          color: Color(0xFF155EEF),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (groupedItems > 1)
                        Text('$groupedItems saved items in this measurement'),
                      if (isWalling && wallSegments.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFD0D5DD)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Wall segments',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Select a segment to change its height or cut out a portion.',
                                style: TextStyle(
                                  color: Color(0xFF667085),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 150,
                                ),
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      for (
                                        var index = 0;
                                        index < wallSegments.length;
                                        index++
                                      )
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 6,
                                          ),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            onTap:
                                                saving
                                                    ? null
                                                    : () => setState(() {
                                                      activeWallSegmentIndex =
                                                          index;
                                                      wallHeightController
                                                          .text = _wallNumber(
                                                        wallSegments[index]['heightM'],
                                                      ).toStringAsFixed(3);
                                                      error = null;
                                                    }),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 9,
                                                  ),
                                              decoration: BoxDecoration(
                                                color:
                                                    index ==
                                                            activeWallSegmentIndex
                                                        ? const Color(
                                                          0xFFEFF4FF,
                                                        )
                                                        : Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color:
                                                      index ==
                                                              activeWallSegmentIndex
                                                          ? const Color(
                                                            0xFF84ADFF,
                                                          )
                                                          : const Color(
                                                            0xFFE4E7EC,
                                                          ),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 28,
                                                    height: 28,
                                                    alignment: Alignment.center,
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFFD1E0FF,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      '${index + 1}',
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF155EEF,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      '${_wallSegmentLength(wallSegments[index]).toStringAsFixed(3)} m long',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    'H ${_wallNumber(wallSegments[index]['heightM']).toStringAsFixed(3)} m',
                                                    style: const TextStyle(
                                                      color: Color(0xFF344054),
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: wallHeightController,
                                      enabled: !saving,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: InputDecoration(
                                        labelText:
                                            'Segment ${activeWallSegmentIndex + 1} height (m)',
                                        prefixIcon: const Icon(
                                          Icons.height_rounded,
                                        ),
                                        border: const OutlineInputBorder(),
                                      ),
                                      onChanged: (value) {
                                        final height = double.tryParse(
                                          value.trim(),
                                        );
                                        if (height == null || height <= 0) {
                                          return;
                                        }
                                        setState(() {
                                          wallSegments[activeWallSegmentIndex]['heightM'] =
                                              height;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  OutlinedButton.icon(
                                    onPressed:
                                        saving
                                            ? null
                                            : () async {
                                              final height = double.tryParse(
                                                wallHeightController.text
                                                    .trim(),
                                              );
                                              if (height == null ||
                                                  height <= 0) {
                                                setState(
                                                  () =>
                                                      error =
                                                          'Enter a valid wall height before cutting.',
                                                );
                                                return;
                                              }
                                              wallSegments[activeWallSegmentIndex]['heightM'] =
                                                  height;
                                              final changed =
                                                  await _cutWallSegmentDialog(
                                                    context: context,
                                                    segments: wallSegments,
                                                    segmentIndex:
                                                        activeWallSegmentIndex,
                                                  );
                                              if (changed == null) return;
                                              setState(() {
                                                wallSegments = changed;
                                                activeWallSegmentIndex = math
                                                    .min(
                                                      activeWallSegmentIndex,
                                                      wallSegments.length - 1,
                                                    );
                                                wallHeightController
                                                    .text = _wallNumber(
                                                  wallSegments[activeWallSegmentIndex]['heightM'],
                                                ).toStringAsFixed(3);
                                                error = null;
                                              });
                                            },
                                    icon: const Icon(Icons.content_cut_rounded),
                                    label: const Text('Cut portion'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (isRoadProfile) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFD0D5DD)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Road profile outputs · $groupedItems items',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Edit each layer below. Saving recalculates the complete road profile from its measured length.',
                                style: TextStyle(
                                  color: Color(0xFF667085),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 10),
                              for (final item in groupedData) ...[
                                Builder(
                                  builder: (context) {
                                    final id = (item['id'] ?? '').toString();
                                    final key = roadKey(item);
                                    final thicknessField =
                                        roadThicknessFields[key];
                                    final calculated = roadQuantity(item);
                                    final unit =
                                        (item['unit'] ?? '').toString();
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color:
                                              id == selectedDocId
                                                  ? const Color(0xFF84ADFF)
                                                  : const Color(0xFFE4E7EC),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          InkWell(
                                            onTap:
                                                saving
                                                    ? null
                                                    : () => selectGroupedItem(
                                                      item,
                                                      setState,
                                                    ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    (item['label'] ??
                                                            'Road profile item')
                                                        .toString(),
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  calculated == null
                                                      ? 'Invalid values'
                                                      : '${calculated.toStringAsFixed(unit == 'ha' ? 4 : 3)} $unit',
                                                  style: TextStyle(
                                                    color:
                                                        calculated == null
                                                            ? Colors.red
                                                            : const Color(
                                                              0xFF155EEF,
                                                            ),
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  controller:
                                                      roadWidthControllers[id],
                                                  enabled: !saving,
                                                  keyboardType:
                                                      const TextInputType.numberWithOptions(
                                                        decimal: true,
                                                      ),
                                                  onChanged:
                                                      (_) => setState(
                                                        () => error = null,
                                                      ),
                                                  decoration: InputDecoration(
                                                    labelText:
                                                        roadUsesClearingWidth(
                                                              key,
                                                            )
                                                            ? 'Clearing width (m)'
                                                            : roadUsesEarthworkWidth(
                                                              key,
                                                            )
                                                            ? 'Earthwork width (m)'
                                                            : 'Layer width (m)',
                                                    isDense: true,
                                                    border:
                                                        const OutlineInputBorder(),
                                                  ),
                                                ),
                                              ),
                                              if (thicknessField != null) ...[
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: TextField(
                                                    controller:
                                                        roadThicknessControllers[id],
                                                    enabled: !saving,
                                                    keyboardType:
                                                        const TextInputType.numberWithOptions(
                                                          decimal: true,
                                                        ),
                                                    onChanged:
                                                        (_) => setState(
                                                          () => error = null,
                                                        ),
                                                    decoration: InputDecoration(
                                                      labelText:
                                                          key == 'common_excavation' ||
                                                                  key == 'fill'
                                                              ? 'Depth (mm)'
                                                              : 'Thickness (mm)',
                                                      isDense: true,
                                                      border:
                                                          const OutlineInputBorder(),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              if (roadIsMc30(key)) ...[
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: TextField(
                                                    controller:
                                                        roadRateControllers[id],
                                                    enabled: !saving,
                                                    keyboardType:
                                                        const TextInputType.numberWithOptions(
                                                          decimal: true,
                                                        ),
                                                    onChanged:
                                                        (_) => setState(
                                                          () => error = null,
                                                        ),
                                                    decoration:
                                                        const InputDecoration(
                                                          labelText:
                                                              'Rate (L/m²)',
                                                          isDense: true,
                                                          border:
                                                              OutlineInputBorder(),
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ] else if (groupedItems > 1) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 180),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE4E7EC)),
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                for (final item in groupedData)
                                  InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap:
                                        saving
                                            ? null
                                            : () => selectGroupedItem(
                                              item,
                                              setState,
                                            ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            (item['id'] ?? '').toString() ==
                                                    selectedDocId
                                                ? const Color(0xFFEFF4FF)
                                                : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  boqCodeOf(item).isEmpty
                                                      ? 'No BOQ code'
                                                      : boqCodeOf(item),
                                                  style: const TextStyle(
                                                    color: Color(0xFF155EEF),
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                                Text(
                                                  (item['label'] ??
                                                          item['title'] ??
                                                          item['type'] ??
                                                          'Saved item')
                                                      .toString(),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            quantityOf(item),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.edit_outlined,
                                            size: 18,
                                            color: Color(0xFF155EEF),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (isSlabRebar) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFD0D5DD)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Reinforcement details',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Changing these values recalculates the total bar length and reinforcement weight.',
                                style: TextStyle(
                                  color: Color(0xFF667085),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 12,
                                children: [
                                  SizedBox(
                                    width: 160,
                                    child: TextField(
                                      controller: rebarMarkController,
                                      enabled: !saving,
                                      decoration: const InputDecoration(
                                        labelText: 'Bar mark',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 150,
                                    child: TextField(
                                      controller: rebarDiameterController,
                                      enabled: !saving,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Bar size (mm)',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 175,
                                    child: TextField(
                                      controller: rebarLengthController,
                                      enabled: !saving,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Bar length (m)',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 160,
                                    child: TextField(
                                      controller: rebarCountController,
                                      enabled: !saving,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Number of bars',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 165,
                                    child: TextField(
                                      controller: rebarSpacingController,
                                      enabled: !saving,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Spacing (mm c/c)',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 145,
                                    child: TextField(
                                      controller: rebarFactorController,
                                      enabled: !saving,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Multiplier',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 145,
                                    child: DropdownButtonFormField<String>(
                                      value: const {
                                            'T1', 'T2', 'B1', 'B2', 'Other',
                                          }.contains(rebarLayer)
                                          ? rebarLayer
                                          : 'Other',
                                      decoration: const InputDecoration(
                                        labelText: 'Layer',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const ['T1', 'T2', 'B1', 'B2', 'Other']
                                          .map(
                                            (value) => DropdownMenuItem(
                                              value: value,
                                              child: Text(value),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: saving
                                          ? null
                                          : (value) => setState(
                                            () => rebarLayer = value ?? 'T1',
                                          ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 145,
                                    child: DropdownButtonFormField<String>(
                                      value: const {'X', 'Y', 'Other'}.contains(rebarDirection)
                                          ? rebarDirection
                                          : 'Other',
                                      decoration: const InputDecoration(
                                        labelText: 'Direction',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const ['X', 'Y', 'Other']
                                          .map(
                                            (value) => DropdownMenuItem(
                                              value: value,
                                              child: Text(value),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: saving
                                          ? null
                                          : (value) => setState(
                                            () => rebarDirection = value ?? 'X',
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: labelController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Measurement label',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: quantityController,
                              enabled:
                                  !saving &&
                                  !isWalling &&
                                  !isRoadProfile &&
                                  !isSlabRebar,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: 'Quantity',
                                helperText:
                                    isWalling
                                        ? 'Calculated from segment lengths and heights'
                                        : null,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: unitController,
                              enabled:
                                  !saving &&
                                  !isWalling &&
                                  !isRoadProfile &&
                                  !isSlabRebar,
                              decoration: const InputDecoration(
                                labelText: 'Unit',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              boqCode.isEmpty
                                  ? 'No BOQ item selected'
                                  : '$boqCode — $boqDescription',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                saving
                                    ? null
                                    : () async {
                                      final picked = await it
                                          .showBoqPickerDialog(
                                            context: context,
                                          );
                                      if (picked == null) return;
                                      setState(() {
                                        boqItemId = picked.id;
                                        boqCode = picked.code;
                                        boqDescription = picked.description;
                                      });
                                    },
                            icon: const Icon(Icons.search_rounded),
                            label: const Text('Change BOQ'),
                          ),
                        ],
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Text(error!, style: const TextStyle(color: Colors.red)),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                if ((selectedData['measureType'] ?? selectedData['type'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase() ==
                    'pavement')
                  FilledButton.tonalIcon(
                    onPressed:
                        saving
                            ? null
                            : () async {
                              double numOf(dynamic v) =>
                                  v is num
                                      ? v.toDouble()
                                      : double.tryParse('${v ?? ''}') ?? 0.0;
                              final areaGroupId =
                                  (selectedData['areaGroupId'] ?? '')
                                      .toString()
                                      .trim();
                              final sourceArea =
                                  numOf(selectedData['combinedAreaM2']) > 0
                                      ? numOf(selectedData['combinedAreaM2'])
                                      : numOf(selectedData['netAreaM2']) > 0
                                      ? numOf(selectedData['netAreaM2'])
                                      : numOf(
                                            selectedData['polygonNetAreaM2'],
                                          ) >
                                          0
                                      ? numOf(selectedData['polygonNetAreaM2'])
                                      : numOf(selectedData['polygonAreaM2']) > 0
                                      ? numOf(selectedData['polygonAreaM2'])
                                      : numOf(selectedData['value']);

                              if (areaGroupId.isEmpty || sourceArea <= 0) {
                                setState(() {
                                  error =
                                      'This pavement measurement does not contain enough area information to split.';
                                });
                                return;
                              }

                              it.requestPavementTransfer(
                                areaGroupId: areaGroupId,
                                sourcePolygonAreaM2: sourceArea,
                              );
                              Navigator.pop(context);
                              await selectMeasurementTool(
                                measureType: 'pavement',
                                label: 'Pavement area',
                                unit: 'm2',
                              );
                              Get.snackbar(
                                'Split / transfer pavement area',
                                'Polygon only the portion to move to another pavement type. AQS will save it as a new pavement measurement and deduct it from this one.',
                                snackPosition: SnackPosition.BOTTOM,
                                duration: const Duration(seconds: 6),
                              );
                            },
                    icon: const Icon(Icons.call_split_rounded),
                    label: const Text('Split / transfer area'),
                  ),
                TextButton.icon(
                  onPressed:
                      saving
                          ? null
                          : () async {
                            Navigator.pop(context);
                            await _deleteSavedMeasurement(
                              selectedDocId,
                              selectedData,
                            );
                          },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text(
                    'Delete measurement',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
                FilledButton.icon(
                  onPressed:
                      saving
                          ? null
                          : () async {
                            final quantity = double.tryParse(
                              quantityController.text.trim(),
                            );
                            double? rebarWeight;
                            double? rebarTotalLength;
                            int? rebarDiameter;
                            int? rebarCount;
                            double? rebarLength;
                            double? rebarSpacing;
                            double? rebarFactor;
                            if (isSlabRebar) {
                              rebarDiameter = int.tryParse(
                                rebarDiameterController.text.trim(),
                              );
                              rebarCount = int.tryParse(
                                rebarCountController.text.trim(),
                              );
                              rebarLength = double.tryParse(
                                rebarLengthController.text.trim(),
                              );
                              rebarSpacing = double.tryParse(
                                rebarSpacingController.text.trim(),
                              );
                              rebarFactor = double.tryParse(
                                rebarFactorController.text.trim(),
                              );
                              if (rebarMarkController.text.trim().isEmpty ||
                                  rebarDiameter == null ||
                                  rebarDiameter <= 0 ||
                                  rebarCount == null ||
                                  rebarCount <= 0 ||
                                  rebarLength == null ||
                                  rebarLength <= 0 ||
                                  rebarSpacing == null ||
                                  rebarSpacing <= 0 ||
                                  rebarFactor == null ||
                                  rebarFactor <= 0) {
                                setState(
                                  () =>
                                      error =
                                          'Enter a mark and valid positive rebar dimensions, quantity, spacing and multiplier.',
                                );
                                return;
                              }
                              final unitWeight =
                                  rebarDiameter * rebarDiameter / 162.0;
                              rebarTotalLength =
                                  rebarLength * rebarCount * rebarFactor;
                              rebarWeight = rebarTotalLength * unitWeight;
                            }
                            if (!isWalling &&
                                !isRoadProfile &&
                                !isSlabRebar &&
                                (quantity == null || quantity < 0)) {
                              setState(() => error = 'Enter a valid quantity.');
                              return;
                            }
                            if (isWalling) {
                              final height = double.tryParse(
                                wallHeightController.text.trim(),
                              );
                              if (height == null || height <= 0) {
                                setState(
                                  () => error = 'Enter a valid wall height.',
                                );
                                return;
                              }
                              wallSegments[activeWallSegmentIndex]['heightM'] =
                                  height;
                            }
                            setState(() {
                              saving = true;
                              error = null;
                            });
                            try {
                              if (isRoadProfile) {
                                for (final item in groupedData) {
                                  if (roadQuantity(item) == null) {
                                    setState(() {
                                      saving = false;
                                      error =
                                          'Enter valid positive widths and valid thicknesses or rates for every road-profile item.';
                                    });
                                    return;
                                  }
                                }
                                final batch =
                                    FirebaseFirestore.instance.batch();
                                for (final item in groupedData) {
                                  final id = (item['id'] ?? '').toString();
                                  final key = roadKey(item);
                                  final widthField = roadWidthField(key);
                                  final thicknessField =
                                      roadThicknessFields[key];
                                  final updateData = <String, dynamic>{
                                    'value': roadQuantity(item),
                                    'quantity': roadQuantity(item),
                                    widthField: double.parse(
                                      roadWidthControllers[id]!.text.trim(),
                                    ),
                                    if (thicknessField != null)
                                      thicknessField: double.parse(
                                        roadThicknessControllers[id]!.text
                                            .trim(),
                                      ),
                                    if (roadIsMc30(key))
                                      roadRateField(key): double.parse(
                                        roadRateControllers[id]!.text.trim(),
                                      ),
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  };
                                  if (id == selectedDocId) {
                                    updateData.addAll({
                                      'label': labelController.text.trim(),
                                      'title': labelController.text.trim(),
                                      'boqItemId': boqItemId,
                                      'boqCode': boqCode,
                                      'resolvedBoqCode': boqCode,
                                      'boqDescription': boqDescription,
                                    });
                                  }
                                  batch.update(
                                    measurementsRef.doc(id),
                                    updateData,
                                  );
                                }
                                await batch.commit();
                                if (context.mounted) Navigator.pop(context);
                                update(['viewer', 'summary', 'topbar']);
                                return;
                              }
                              final selectedUpdate = <String, dynamic>{
                                'label': labelController.text.trim(),
                                'title': labelController.text.trim(),
                                'unit': unitController.text.trim(),
                                'boqUnit': unitController.text.trim(),
                                'boqItemId': boqItemId,
                                'boqCode': boqCode,
                                'resolvedBoqCode': boqCode,
                                'boqDescription': boqDescription,
                                'updatedAt': FieldValue.serverTimestamp(),
                              };
                              if (isSlabRebar) {
                                final mark = rebarMarkController.text.trim();
                                final spacingLabel =
                                    rebarSpacing == rebarSpacing!.roundToDouble()
                                        ? rebarSpacing.toStringAsFixed(0)
                                        : rebarSpacing.toStringAsFixed(1);
                                final unitWeight =
                                    rebarDiameter! * rebarDiameter / 162.0;
                                selectedUpdate.addAll({
                                  'label': 'Slab reinforcement - $mark',
                                  'title': 'Slab reinforcement - $mark',
                                  'description': 'Slab reinforcement - $mark',
                                  'unit': 'kg',
                                  'boqUnit': 'kg',
                                  'value': rebarWeight,
                                  'quantity': rebarWeight,
                                  'barMark': mark,
                                  'mark': mark,
                                  'diameterMm': rebarDiameter,
                                  'numberOfBars': rebarCount,
                                  'barsCount': rebarCount,
                                  'groupFactor': rebarFactor,
                                  'multiplyingFactor': rebarFactor,
                                  'effectiveBarsCount': rebarCount! * rebarFactor!,
                                  'spacingMm': rebarSpacing,
                                  'spacingM': rebarSpacing / 1000.0,
                                  'layer': rebarLayer,
                                  'position': rebarLayer,
                                  'direction': rebarDirection,
                                  'measuredLengthM': rebarLength,
                                  'lengthM': rebarLength,
                                  'barLengthM': rebarLength,
                                  'lengthOneM': rebarLength,
                                  'baseTotalLengthM': rebarLength! * rebarCount,
                                  'totalLengthM': rebarTotalLength,
                                  'totalLengthAllBarsM': rebarTotalLength,
                                  'unitWeightKgPerM': unitWeight,
                                  'totalWeightKg': rebarWeight,
                                  'rawMark':
                                      '${rebarCount}Y$rebarDiameter-$mark-$spacingLabel$rebarLayer',
                                });
                              } else if (!isWalling) {
                                selectedUpdate['quantity'] = quantity;
                                selectedUpdate['value'] = quantity;
                              }
                              await measurementsRef
                                  .doc(selectedDocId)
                                  .update(selectedUpdate);
                              if (isWalling) {
                                await _saveWallSegmentGeometry(
                                  selectedData: selectedData,
                                  groupedData: groupedData,
                                  segments: wallSegments,
                                );
                              }
                              if (context.mounted) Navigator.pop(context);
                              update(['viewer', 'summary', 'topbar']);
                            } catch (exception) {
                              setState(() {
                                saving = false;
                                error = 'Could not update: $exception';
                              });
                            }
                          },
                  icon:
                      saving
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(Icons.save_outlined),
                  label: Text(
                    saving
                        ? 'Saving...'
                        : isWalling
                        ? 'Save wall segment'
                        : 'Save selected item',
                  ),
                ),
              ],
            ),
      ),
      barrierDismissible: false,
    );
    labelController.dispose();
    quantityController.dispose();
    unitController.dispose();
    rebarMarkController.dispose();
    rebarDiameterController.dispose();
    rebarLengthController.dispose();
    rebarCountController.dispose();
    rebarSpacingController.dispose();
    rebarFactorController.dispose();
    wallHeightController.dispose();
    for (final controller in roadWidthControllers.values) {
      controller.dispose();
    }
    for (final controller in roadThicknessControllers.values) {
      controller.dispose();
    }
    for (final controller in roadRateControllers.values) {
      controller.dispose();
    }
  }

  Future<void> showSelectedSegmentDialog() async {
    final selId = selectedSegmentId;
    if (selId == null || selId.isEmpty) return;

    final seg = lastSegments.firstWhereOrNull((s) => s.id == selId);
    if (seg == null) return;

    Color tempColor = seg.color;
    double tempStroke =
        (seg.strokeWidth ?? baseStroke).clamp(minStroke, maxStroke).toDouble();

    await Get.dialog<void>(
      StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Selected measurement'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Color',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () async {
                          final picked = await _pickColorDialog(
                            initial: tempColor,
                          );
                          if (picked == null) return;
                          setState(() => tempColor = picked);
                        },
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: tempColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black26),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Line weight: ${tempStroke.toStringAsFixed(1)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Slider(
                    min: minStroke,
                    max: maxStroke,
                    divisions: ((maxStroke - minStroke) * 2).round(),
                    value: tempStroke,
                    label: tempStroke.toStringAsFixed(1),
                    onChanged: (v) => setState(() => tempStroke = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back<void>(),
                child: const Text('Cancel'),
              ),
              TextButton.icon(
                onPressed: () async {
                  Get.back<void>();
                  await deleteSelectedSegment();
                },
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  Get.back<void>();
                  await editSelectedMeasurement();
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
            ],
          );
        },
      ),
      barrierDismissible: true,
    );
  }

  Future<bool> pickColorForSelected() async {
    final selId = selectedSegmentId;
    if (selId == null || selId.isEmpty) return false;

    final seg = lastSegments.firstWhereOrNull((s) => s.id == selId);
    if (seg == null) return false;

    final picked = await _pickColorDialog(initial: seg.color);
    if (picked == null) return false;

    await measurementsRef.doc(seg.docId).update({'color': picked.value});
    update(['viewer', 'summary']);
    return true;
  }

  void beginEdit(MeasuredSegment seg, Offset pointerPos) {
    selectedSegmentId = seg.id;
    editP1 = seg.p1;
    editP2 = seg.p2;

    _dragStartPos = pointerPos;
    _origP1 = seg.p1;
    _origP2 = seg.p2;

    // decide which handle user grabbed (endpoint vs line)
    activeHandle = _pickHandle(pointerPos, seg);
    update(['viewer']);
  }

  void updateEditDrag(Offset pos) {
    if (editP1 == null || editP2 == null) return;

    if (editTool.value == SegmentEditTool.extend) {
      // extend: drag only chosen endpoint
      if (activeHandle == SegmentHandle.p1) {
        editP1 = pos;
      } else if (activeHandle == SegmentHandle.p2) {
        editP2 = pos;
      } else {
        // if user grabbed line (not endpoint), treat as move
        final delta = pos - (_dragStartPos ?? pos);
        editP1 = (_origP1 ?? editP1!) + delta;
        editP2 = (_origP2 ?? editP2!) + delta;
      }
    }

    // (move/rotate can be added later)
    update(['viewer']);
  }

  void endEditDrag() {
    _dragStartPos = null;
    _origP1 = null;
    _origP2 = null;
    activeHandle = SegmentHandle.none;
  }

  SegmentHandle _pickHandle(Offset pos, MeasuredSegment seg) {
    const r = 14.0; // touch radius (px)
    if ((pos - seg.p1).distance <= r) return SegmentHandle.p1;
    if ((pos - seg.p2).distance <= r) return SegmentHandle.p2;
    return SegmentHandle.line;
  }

  // ---------------------------------------------------------
  Future<void> handleAreaTap(
    BuildContext? context,
    Offset pos,
    Map<String, dynamic> drawingData,
  ) async {
    if (isAreaDialogOpen) return;

    // areaPoints = List.of(areaPoints)..add(pos);
    areaPoints = [...areaPoints, pos];
    update(['viewer']);

    if (areaPoints.length < 3) return;

    final zoom = transformController.value.getMaxScaleOnAxis();

    const closeRadius = 12.0;
    final first = areaPoints.first;
    final distToFirst = (pos - first).distance;

    if (distToFirst > closeRadius) return;

    final polygon = List<Offset>.from(areaPoints);
    polygon[polygon.length - 1] = first;
    // ✅ clear draft BEFORE opening dialog
    // it.resetArea();
    isAreaDialogOpen = true;

    try {
      if (isFootingCompositeActive) {
        await it.openFootingCompositeFromPolygon(
          polygon: polygon,
          drawingData: drawingData,
          projectId: projectId,
          buildingId: buildingId,
          drawingId: drawingId,
          currentColor: currentColor,
          activeLabel: activeLabel,
          // measurementsRef: measureConfigsRef,
          // showBoqPickerDialog: it.showBoqPickerDialog(context: context!),
        );
      } else if ({
        'compositeslab',
        'slabcomposite',
      }.contains((activeMeasureType ?? '').trim().toLowerCase())) {
        await it.openSlabCompositeFromPolygon(
          polygon: polygon,
          drawingData: drawingData,
          projectId: projectId,
          buildingId: buildingId,
          drawingId: drawingId,
          currentColor: currentColor,
          activeLabel: activeLabel,
          // measurementsRef: measureConfigsRef,
          // showBoqPickerDialog: (ctx) => showBoqMultiPickerDialog(context: context, allBoqs: allBoqs),
        );
      } else if ((activeMeasureType ?? '').trim().toLowerCase() ==
          'slabrebarai') {
        final measureLength = await it.openAiSlabRebarFromPolygon(
          polygon: polygon,
          drawingData: drawingData,
        );
        if (measureLength) {
          clearDraftLength();
          mode.value = TakeoffMode.measureLength;
          Get.snackbar(
            'Measure this bar',
            'Tap the start point, then tap the end point on the drawing.',
            snackPosition: SnackPosition.BOTTOM,
          );
          update(['overlay', 'viewer']);
        }
      } else if ((activeMeasureType ?? '').trim().toLowerCase() == 'ceiling') {
        await it.openCeilingFinishesFromPolygon(
          polygon: polygon,
          drawingData: drawingData,
          projectId: projectId,
          buildingId: buildingId,
          drawingId: drawingId,
          currentColor: currentColor,
          activeLabel: activeLabel,
          initialSurfaceKind: 'ceiling',
        );
      } else if ((activeMeasureType ?? '').trim().toLowerCase() == 'tiling') {
        await it.openCeilingFinishesFromPolygon(
          polygon: polygon,
          drawingData: drawingData,
          projectId: projectId,
          buildingId: buildingId,
          drawingId: drawingId,
          currentColor: currentColor,
          activeLabel: activeLabel,
          initialSurfaceKind: 'floor',
        );
      } else if ((activeMeasureType ?? '').trim().toLowerCase() == 'pavement') {
        final pixelsPerUnit =
            drawingData['pixelsPerUnit'] is num
                ? (drawingData['pixelsPerUnit'] as num).toDouble()
                : double.tryParse('${drawingData['pixelsPerUnit'] ?? ''}') ?? 0;
        if (drawingData['calibrated'] != true || pixelsPerUnit <= 0) {
          Get.snackbar(
            'Calibration required',
            'Calibrate the drawing before measuring pavement.',
          );
          _pendingPavementPolygons.clear();
          _pendingPavementDeductionPolygons.clear();
          _pendingPavementDeductionLabels.clear();
          _nextPavementPolygonIsDeduction = false;
          return;
        }

        double areaOf(List<Offset> points) =>
            _polygonAreaPx(points).abs() / (pixelsPerUnit * pixelsPerUnit);

        final context = Get.context;
        if (context == null) return;

        // Existing pavement correction: polygon a portion of a saved area,
        // create it as a new pavement measurement, then deduct the same area
        // from the source group. This avoids tracing the transferred area twice.
        final transferRequest = it.pendingPavementTransfer;
        if (transferRequest != null) {
          final transferAreaM2 = areaOf(polygon);
          if (transferAreaM2 <= 0 ||
              transferAreaM2 > transferRequest.sourcePolygonAreaM2 + 0.001) {
            Get.snackbar(
              'Invalid transfer area',
              'The transfer polygon must be a positive area and cannot exceed the selected source pavement area.',
              snackPosition: SnackPosition.BOTTOM,
            );
            return;
          }

          final proceed =
              await showDialog<bool>(
                context: context,
                builder:
                    (dialogContext) => AlertDialog(
                      title: const Text('Transfer pavement area?'),
                      content: Text(
                        'Selected polygon: ${transferAreaM2.toStringAsFixed(3)} m²\n\n'
                        'AQS will create this polygon as a new pavement measurement. After it is saved, the same area will be deducted from the original pavement measurement.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Continue'),
                        ),
                      ],
                    ),
              ) ??
              false;
          if (!proceed) return;

          final savedNewArea = await showPavementMeasurementDialog(
            polygons: <List<Offset>>[List<Offset>.from(polygon)],
            drawingData: drawingData,
            projectId: projectId,
            buildingId: buildingId,
            drawingId: drawingId,
            currentColor: currentColor,
            measurementsRef: measurementsRef,
            pickBoq: (ctx) => it.showBoqPickerDialog(context: ctx),
          );

          if (savedNewArea) {
            try {
              await it.applyPavementTransferDeduction(
                measurementsRef: measurementsRef,
                transferAreaM2: transferAreaM2,
                transferPolygon: polygon,
              );
              it.cancelPavementTransfer();
              Get.snackbar(
                'Pavement area transferred',
                '${transferAreaM2.toStringAsFixed(3)} m² was deducted from the original area and saved as a new pavement measurement.',
                snackPosition: SnackPosition.BOTTOM,
              );
              update(['viewer', 'summary']);
            } catch (e) {
              Get.snackbar(
                'Transfer incomplete',
                'The new pavement area was saved, but the original area could not be reduced: $e',
                snackPosition: SnackPosition.BOTTOM,
              );
            }
          }
          return;
        }

        Future<void> waitForPavementDialogExit(
          BuildContext? closingDialogContext,
        ) async {
          // showDialog completes as soon as Navigator.pop is called, while the
          // outgoing route can still be unmounting. Do not rebuild the viewer
          // or open the next pavement dialog during that transition.
          for (
            var frame = 0;
            frame < 30 && closingDialogContext?.mounted == true;
            frame++
          ) {
            await WidgetsBinding.instance.endOfFrame;
          }
        }

        final currentIsDeduction = _nextPavementPolygonIsDeduction;
        String? currentDeductionLabel;

        if (currentIsDeduction) {
          final controller = TextEditingController(
            text: 'Deduction ${_pendingPavementDeductionPolygons.length + 1}',
          );
          BuildContext? deductionDialogContext;
          currentDeductionLabel = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) {
              deductionDialogContext = dialogContext;
              return AlertDialog(
                title: const Text('Describe deduction'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Deduction area: ${areaOf(polygon).toStringAsFixed(3)} m²',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'e.g. Building, landscape island',
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel deduction'),
                  ),
                  FilledButton(
                    onPressed:
                        () => Navigator.pop(
                          dialogContext,
                          controller.text.trim().isEmpty
                              ? 'Deduction ${_pendingPavementDeductionPolygons.length + 1}'
                              : controller.text.trim(),
                        ),
                    child: const Text('Use deduction'),
                  ),
                ],
              );
            },
          );
          await waitForPavementDialogExit(deductionDialogContext);
          controller.dispose();
          if (currentDeductionLabel == null) {
            _nextPavementPolygonIsDeduction = false;
            update(['viewer']);
            return;
          }
        }

        final additions = <List<Offset>>[
          ..._pendingPavementPolygons.map(List<Offset>.from),
          if (!currentIsDeduction) List<Offset>.from(polygon),
        ];
        final deductions = <List<Offset>>[
          ..._pendingPavementDeductionPolygons.map(List<Offset>.from),
          if (currentIsDeduction) List<Offset>.from(polygon),
        ];
        final deductionLabels = <String>[
          ..._pendingPavementDeductionLabels,
          if (currentIsDeduction) currentDeductionLabel!,
        ];

        if (additions.isEmpty) {
          Get.snackbar(
            'Add pavement first',
            'Capture at least one pavement area before deductions.',
          );
          _nextPavementPolygonIsDeduction = false;
          return;
        }

        final zoneAreas = additions.map(areaOf).toList();
        final deductionAreas = deductions.map(areaOf).toList();
        final grossArea = zoneAreas.fold<double>(
          0.0,
          (sum, area) => sum + area,
        );
        final totalDeduction = deductionAreas.fold<double>(
          0.0,
          (sum, area) => sum + area,
        );
        final netArea = grossArea - totalDeduction;

        if (netArea <= 0) {
          Get.snackbar(
            'Invalid pavement area',
            'Total deductions must be smaller than the gross pavement area.',
          );
          _nextPavementPolygonIsDeduction = false;
          return;
        }

        final reviewContext = Get.context;
        if (reviewContext == null) return;
        BuildContext? reviewDialogContext;
        var addingArea = false;
        final action =
            await showDialog<int>(
              context: reviewContext,
              barrierDismissible: false,
              builder: (dialogContext) {
                reviewDialogContext = dialogContext;
                return AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  title: const Text('Pavement areas'),
                  content: SizedBox(
                    width: 520,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${additions.length} added area${additions.length == 1 ? '' : 's'} · ${deductions.length} deduction${deductions.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Gross: ${grossArea.toStringAsFixed(3)} m²',
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'Deductions: ${totalDeduction.toStringAsFixed(3)} m²',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'NET PAVEMENT AREA: ${netArea.toStringAsFixed(3)} m²',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Added pavement areas',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                for (var i = 0; i < zoneAreas.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Text(
                                      'Zone ${i + 1}: +${zoneAreas[i].toStringAsFixed(3)} m²',
                                    ),
                                  ),
                                if (deductionAreas.isNotEmpty) ...[
                                  const Divider(height: 18),
                                  const Text(
                                    'Deductions',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  for (
                                    var i = 0;
                                    i < deductionAreas.length;
                                    i++
                                  )
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: Text(
                                        '${deductionLabels[i]}: -${deductionAreas[i].toStringAsFixed(3)} m²',
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Add Area captures another disconnected pavement zone. Deduct Area captures buildings, landscaped islands or other exclusions. Finish Pavement opens one take-off form using the net area.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, 0),
                      child: const Text('Cancel'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(dialogContext, 2),
                      icon: const Icon(Icons.remove_circle_outline),
                      label: const Text('Deduct area'),
                    ),
                    StatefulBuilder(
                      builder:
                          (
                            buttonContext,
                            setButtonState,
                          ) => OutlinedButton.icon(
                            onPressed:
                                addingArea
                                    ? null
                                    : () {
                                      setButtonState(() => addingArea = true);
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            if (dialogContext.mounted) {
                                              Navigator.pop(dialogContext, 1);
                                            }
                                          });
                                    },
                            icon:
                                addingArea
                                    ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Icon(Icons.add_rounded),
                            label: Text(
                              addingArea ? 'Adding area...' : 'Add area',
                            ),
                          ),
                    ),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(dialogContext, 3),
                      icon: const Icon(Icons.done_all_rounded),
                      label: const Text('Finish pavement'),
                    ),
                  ],
                );
              },
            ) ??
            0;
        await waitForPavementDialogExit(reviewDialogContext);

        if (action == 0) {
          _pendingPavementPolygons.clear();
          _pendingPavementDeductionPolygons.clear();
          _pendingPavementDeductionLabels.clear();
          _nextPavementPolygonIsDeduction = false;
          update(['viewer']);
          return;
        }

        // Commit the polygon that was just captured to the pending session.
        if (currentIsDeduction) {
          _pendingPavementDeductionPolygons.add(List<Offset>.from(polygon));
          _pendingPavementDeductionLabels.add(currentDeductionLabel!);
        } else {
          _pendingPavementPolygons.add(List<Offset>.from(polygon));
        }

        if (action == 1 || action == 2) {
          _nextPavementPolygonIsDeduction = action == 2;
          update(['viewer']);
          Get.snackbar(
            action == 2
                ? 'Deduction saved temporarily'
                : 'Area saved temporarily',
            action == 2
                ? '${_pendingPavementDeductionPolygons.length} deduction${_pendingPavementDeductionPolygons.length == 1 ? '' : 's'} ready. Trace the next excluded area.'
                : '${_pendingPavementPolygons.length} pavement area${_pendingPavementPolygons.length == 1 ? '' : 's'} ready. Trace the next area.',
            snackPosition: SnackPosition.BOTTOM,
          );
          return;
        }

        final saved = await showPavementMeasurementDialog(
          polygons: additions,
          deductionPolygons: deductions,
          deductionLabels: deductionLabels,
          drawingData: drawingData,
          projectId: projectId,
          buildingId: buildingId,
          drawingId: drawingId,
          currentColor: currentColor,
          measurementsRef: measurementsRef,
          pickBoq: (ctx) => it.showBoqPickerDialog(context: ctx),
        );
        _pendingPavementPolygons.clear();
        _pendingPavementDeductionPolygons.clear();
        _pendingPavementDeductionLabels.clear();
        _nextPavementPolygonIsDeduction = false;
        if (saved) {
          update(['viewer', 'summary']);
        } else {
          update(['viewer']);
        }
      } else if ((activeMeasureType ?? '').trim().toLowerCase() ==
          'groundpreparation') {
        final pixelsPerUnit =
            drawingData['pixelsPerUnit'] is num
                ? (drawingData['pixelsPerUnit'] as num).toDouble()
                : double.tryParse('${drawingData['pixelsPerUnit'] ?? ''}') ?? 0;
        if (drawingData['calibrated'] != true || pixelsPerUnit <= 0) {
          Get.snackbar(
            'Calibration required',
            'Calibrate the drawing before measuring ground preparation.',
          );
          _pendingGroundPreparationPolygons.clear();
          return;
        }
        final polygons = <List<Offset>>[
          ..._pendingGroundPreparationPolygons.map(List<Offset>.from),
          List<Offset>.from(polygon),
        ];
        final combinedArea = polygons.fold<double>(
          0,
          (sum, points) =>
              sum +
              _polygonAreaPx(points).abs() / (pixelsPerUnit * pixelsPerUnit),
        );
        final context = Get.context;
        if (context == null) return;
        final action =
            await showDialog<int>(
              context: context,
              barrierDismissible: false,
              builder:
                  (dialogContext) => AlertDialog(
                    title: const Text('Ground preparation areas'),
                    content: Text(
                      '${polygons.length} area${polygons.length == 1 ? '' : 's'} selected\n'
                      'Combined area: ${combinedArea.toStringAsFixed(3)} m²',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, 0),
                        child: const Text('Cancel'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pop(dialogContext, 1),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add another area'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, 2),
                        child: const Text('Pick BOQ & save'),
                      ),
                    ],
                  ),
            ) ??
            0;
        if (action == 0) {
          _pendingGroundPreparationPolygons.clear();
          update(['viewer']);
          return;
        }
        if (action == 1) {
          _pendingGroundPreparationPolygons.add(List<Offset>.from(polygon));
          update(['viewer']);
          return;
        }
        final saved = await showGroundPreparationMeasurementDialog(
          polygons: polygons,
          drawingData: drawingData,
          projectId: projectId,
          buildingId: buildingId,
          drawingId: drawingId,
          currentColor: currentColor,
          measurementsRef: measurementsRef,
          pickBoq: (ctx) => it.showBoqPickerDialog(context: ctx),
        );
        if (saved) {
          _pendingGroundPreparationPolygons.clear();
          update(['viewer', 'summary']);
        } else {
          _pendingGroundPreparationPolygons.clear();
          update(['viewer']);
        }
      } else if ((activeMeasureType ?? '').trim().toLowerCase() == 'plinth') {
        final saved = await showPlinthMeasurementDialog(
          polygon: polygon,
          drawingData: drawingData,
          projectId: projectId,
          buildingId: buildingId,
          drawingId: drawingId,
          currentColor: currentColor,
          measurementsRef: measurementsRef,
          pickBoq: (ctx) => it.showBoqPickerDialog(context: ctx),
        );
        if (saved) {
          update(['viewer', 'summary']);
        }
      } else if ((activeMeasureType ?? '').trim().toLowerCase() ==
          'concretebenchworktop') {
        final saved = await showConcreteBenchWorktopDialog(
          polygon: polygon,
          drawingData: drawingData,
          projectId: projectId,
          buildingId: buildingId,
          drawingId: drawingId,
          currentColor: currentColor,
          measurementsRef: measurementsRef,
          pickBoq: (ctx) => it.showBoqPickerDialog(context: ctx),
          activeLabel: activeLabel,
        );
        if (saved) update(['viewer', 'summary']);
      } else if ((activeMeasureType ?? '').trim().toLowerCase() ==
          'compositecolumn') {
        await it.openColumnCompositeFromPolygon(
          polygon: polygon,
          drawingData: drawingData,
          projectId: projectId,
          buildingId: buildingId,
          drawingId: drawingId,
          currentColor: currentColor,
          activeLabel: activeLabel,
        );
      } else if ((activeMeasureType ?? '').trim().toLowerCase() ==
          'roofsheeting') {
        await it.openRoofSheetingAndTimberFromPolygon(
          polygon: polygon,
          drawingData: drawingData,
          projectId: projectId,
          buildingId: buildingId,
          drawingId: drawingId,
          currentColor: currentColor,
          activeLabel: activeLabel,
          coveringOnly: true,
        );
        // } else if (_isRampType((activeMeasureType ?? '').trim().toLowerCase())) {
        //   await it.openRampCompositeFromPolygon(
        //     polygon: polygon,
        //     drawingData: drawingData,
        //     projectId: projectId,
        //     buildingId: buildingId,
        //     drawingId: drawingId,
        //     currentColor: currentColor,
        //     activeLabel: activeLabel,
        //     measurementsRef: measurementsRef,
        //     showBoqPickerDialog: (ctx) => it.showBoqPickerDialog(context: ctx),
        //     commitMeasurementBatchOrThrow: it.commitMeasurementBatchOrThrow,
        //   );
        return;
        // } else if (_isStairType((activeMeasureType ?? '').trim().toLowerCase())) {
        //   await it.openStairCompositeFromPolygon(
        //     polygon: polygon,
        //     drawingData: drawingData,
        //     projectId: projectId,
        //     buildingId: buildingId,
        //     drawingId: drawingId,
        //     currentColor: currentColor,
        //     activeLabel: activeLabel,
        //     measurementsRef: measurementsRef,
        //     showBoqPickerDialog: (ctx) => it.showBoqPickerDialog(context: ctx),
        //     commitMeasurementBatchOrThrow: it.commitMeasurementBatchOrThrow,
        //   );
        //   return;
      } else if ((activeMeasureType ?? '').trim().toLowerCase() ==
          'compositeroofing') {
        Get.snackbar(
          'Timber roof structure',
          'This tool is measured by length. Tap the start and end points of a member.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      } else if (_isOpenings((activeMeasureType ?? '').trim().toLowerCase())) {
        await it.openOpeningsDialogFromPolygon(
          polygon: polygon,
          drawingData: drawingData,
          projectId: projectId,
          buildingId: buildingId,
          drawingId: drawingId,
          currentColor: currentColor,
          activeLabel: activeLabel,
          measurementsRef: measurementsRef,
          showBoqPickerDialog: (ctx) => it.showBoqPickerDialog(context: ctx),
          // commitMeasurementBatchOrThrow: it.commitMeasurementBatchOrThrow,
        );
        return;
      } else {
        await completeAreaMeasurement(
          drawingData: drawingData,
          polygon: polygon,
        );
      }
    } finally {
      isAreaDialogOpen = false;

      // ✅ clear again (in case any code path left points)
      resetArea();
    }
  }

  Future<Color?> _pickColorDialog({required Color initial}) async {
    const colors = <Color>[
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.black,
      Colors.brown,
      Colors.teal,
    ];

    return await Get.dialog<Color>(
      AlertDialog(
        title: const Text('Pick color'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children:
              colors.map((c) {
                return InkWell(
                  onTap: () => Get.back(result: c),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black12),
                    ),
                  ),
                );
              }).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
        ],
      ),
      barrierDismissible: true,
    );
  }

  Future<void> updateSegmentGeometry({
    required MeasuredSegment seg,
    required Offset newP1,
    required Offset newP2,
    required Map<String, dynamic> drawingData,
  }) async {
    final mpp = metersPerPixelFromDrawing(drawingData);
    if (mpp <= 0) {
      Get.snackbar('Calibration', 'Calibrate the drawing first.');
      return;
    }

    final lengthM = (newP2 - newP1).distance * mpp;
    final mt = (seg.measureType ?? '').trim().toLowerCase();

    // Load doc so we can read height/group info safely
    final snap = await measurementsRef.doc(seg.docId).get();
    if (!snap.exists) return;
    final m = snap.data()!;

    // Always update geometry fields
    final baseUpdate = <String, dynamic>{
      'p1': {'x': newP1.dx, 'y': newP1.dy},
      'p2': {'x': newP2.dx, 'y': newP2.dy},
      'baseLengthM': lengthM, // ✅ your new field
      'totalLengthM': lengthM, // ✅ keep compatibility if you still use it
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // WALLING => recompute area
    if (mt == 'walling') {
      final heightM =
          (m['heightM'] is num) ? (m['heightM'] as num).toDouble() : 0.0;
      final areaM2 = (heightM > 0) ? (lengthM * heightM) : 0.0;

      await measurementsRef.doc(seg.docId).update({
        ...baseUpdate,
        'unit': 'm2',
        'value': areaM2, // ✅ area per segment
      });

      // ✅ optionally update wall-group totals (recommended)
      final wallGroupId = (m['wallGroupId'] ?? '').toString().trim();
      if (wallGroupId.isNotEmpty) {
        await _recomputeWallGroupTotals(wallGroupId: wallGroupId);
      }

      return;
    }

    // NORMAL LENGTH => recompute length value
    await measurementsRef.doc(seg.docId).update({
      ...baseUpdate,
      'unit': 'm',
      'value': lengthM, // ✅ store length
    });
  }
  // List<MeasuredSegment> lastSegments = const [];

  // final editTool = SegmentEditTool.none.obs;
  SegmentHandle activeHandle = SegmentHandle.none;

  Offset? editP1;
  Offset? editP2;

  // optional: used for move/rotate
  Offset? _dragStartPos;
  Offset? _origP1;
  Offset? _origP2;

  MeasuredSegment? get selectedSeg {
    final id = selectedSegmentId;
    if (id == null || id.isEmpty) return null;

    for (final s in lastSegments) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> _recomputeWallGroupTotals({required String wallGroupId}) async {
    double _num(dynamic v) =>
        (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

    final qs =
        await measurementsRef
            .where('measureType', isEqualTo: 'walling')
            .where('wallGroupId', isEqualTo: wallGroupId)
            .where('drawingId', isEqualTo: drawingId)
            .get();

    if (qs.docs.isEmpty) return;

    double totalLen = 0;
    double totalArea = 0;
    double heightM = 0;

    for (final d in qs.docs) {
      final m = d.data();
      totalLen += _num(m['baseLengthM'] ?? m['totalLengthM']);
      totalArea += _num(m['value']);
      if (heightM == 0) heightM = _num(m['heightM']);
    }

    if (totalArea == 0 && heightM > 0) totalArea = totalLen * heightM;

    // If you have a known "total doc" per group, update it here.
    // Example: query type == 'wallingChainTotal' with chainId == wallGroupId (or your structure)
    final totalDoc =
        await measurementsRef
            .where('type', isEqualTo: 'wallingChainTotal')
            .where('chainId', isEqualTo: wallGroupId)
            .where('drawingId', isEqualTo: drawingId)
            .limit(1)
            .get();

    if (totalDoc.docs.isEmpty) return;

    await totalDoc.docs.first.reference.update({
      'totalLengthM': totalLen,
      'value': totalArea,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> showColumnCompositeDetailsDialog({
    required String columnId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required CollectionReference<Map<String, dynamic>> measurementsRef,
    required String projectId,
    required String buildingId,
    required String drawingId,
    required Color currentColor,
    String? label,
  }) async {
    await Get.dialog(
      ColumnCompositeDetailsDialog(
        columnId: columnId,
        initialDocs: docs,
        measurementsRef: measurementsRef,
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId,
        currentColor: currentColor,
        defaultLabel: label,
      ),
      barrierDismissible: true,
    );
  }

  Future<void> handleBeamCompositeTap({
    required Map<String, dynamic> drawingData,
    required ui.Offset p1,
    required ui.Offset p2,
  }) async {}

  Future<void> savePolylineMeasurement({
    required Offset p1World,
    required Offset p2World,
    required Map<String, dynamic> drawingData,

    required String projectId,
    required String buildingId,
    required String drawingId,

    required String measureType, // e.g. roofSheetingAndTimber
    required String
    type, // e.g. roofRidgeCapping, roofValleys, roofRafters150x50
    required String unit, // "m"
    required Color color,

    required CollectionReference<Map<String, dynamic>> measurementsRef,

    // grouping (optional but recommended)
    String? groupId,

    // tagging (optional)
    String? edgeTag, // "ridge" | "hip" | "valley" | "eave" | "barge"
    // remember previous picks/settings
    required Map<String, dynamic> lastLineDefaults,
    required Future<BoqPick?> Function(BuildContext ctx) showBoqPickerDialog,
    BuildContext? ctx,

    // UI label fields
    String? label,
    String? lineLabel,
  }) async {
    // validate calibration
    final calibrated = drawingData['calibrated'] == true;
    final pxPerM = _num(drawingData['pixelsPerUnit'], 0);
    if (!calibrated || pxPerM <= 0) {
      Get.snackbar(
        'Not calibrated',
        'Calibrate drawing first (pixelsPerUnit).',
      );
      return;
    }

    // compute length
    final lengthM = distM(p1World, p2World, drawingData);
    if (lengthM <= 0) {
      Get.snackbar('Invalid', 'Length is zero. Check points/calibration.');
      return;
    }

    // restore last BOQ pick (auto)
    BoqPick? boqPick = pickFromMap(lastLineDefaults['lastBoqPick']);

    // if no pick and UI available -> ask pick (optional)
    final bctx = ctx ?? Get.context;
    if (boqPick == null && bctx != null) {
      final pick = await showBoqPickerDialog(bctx);
      if (pick != null) boqPick = pick;
    }

    final now = FieldValue.serverTimestamp();
    final docId = measurementsRef.doc().id;

    try {
      await measurementsRef.doc(docId).set({
        'projectId': projectId,
        'buildingId': buildingId,
        'drawingId': drawingId,

        'measureType': measureType,
        'type': type,
        'unit': unit,
        'value': lengthM,

        'p1': {'x': p1World.dx, 'y': p1World.dy},
        'p2': {'x': p2World.dx, 'y': p2World.dy},

        'groupId': (groupId ?? '').toString().trim(),
        'edgeTag': (edgeTag ?? '').toString().trim(),

        'label': (label ?? '').toString(),
        'lineLabel': (lineLabel ?? '').toString(),

        'color': color.value,

        if (boqPick != null) ...{
          'boqItemId': boqPick.id,
          'boqCode': boqPick.code,
          'boqDescription': boqPick.description,
        },

        'createdAt': now,
        'updatedAt': now,
      });

      // remember BOQ for faster next time
      lastLineDefaults['lastBoqPick'] = pickToMap(boqPick);
      lastLineDefaults['lastMeasureType'] = measureType;
      lastLineDefaults['lastType'] = type;
      lastLineDefaults['lastUnit'] = unit;

      Get.snackbar('Saved', '$type: ${lengthM.toStringAsFixed(3)} m');
    } catch (e) {
      Get.snackbar('Save failed', '$e', snackPosition: SnackPosition.BOTTOM);
    }
  }
}

class _DrainageVisualPanel extends StatelessWidget {
  const _DrainageVisualPanel({
    required this.tab,
    required this.onTabChanged,
    required this.type,
    required this.profile,
    required this.bottomMm,
    required this.depthMm,
    required this.sideSlopeH,
    required this.wallMm,
    required this.baseMm,
    required this.coverMm,
    required this.thicknessMm,
    required this.diameterMm,
    required this.barrels,
    required this.quantities,
    required this.labels,
  });

  final String tab;
  final ValueChanged<String> onTabChanged;
  final String type;
  final String profile;
  final double bottomMm;
  final double depthMm;
  final double sideSlopeH;
  final double wallMm;
  final double baseMm;
  final double coverMm;
  final double thicknessMm;
  final double diameterMm;
  final int barrels;
  final Map<String, double> quantities;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    const tabs = <String>['Section', '3D', 'Plan', 'Summary'];
    final selected = tabs.indexOf(tab).clamp(0, tabs.length - 1).toInt();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE5F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(
                  value: 0,
                  icon: Icon(Icons.view_in_ar_outlined),
                  label: Text('Section view'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  icon: Icon(Icons.view_in_ar),
                  label: Text('3D view'),
                ),
                ButtonSegment<int>(
                  value: 2,
                  icon: Icon(Icons.account_tree_outlined),
                  label: Text('Plan / detail'),
                ),
                ButtonSegment<int>(
                  value: 3,
                  icon: Icon(Icons.calculate_outlined),
                  label: Text('Calculation summary'),
                ),
              ],
              selected: <int>{selected},
              onSelectionChanged: (values) => onTabChanged(tabs[values.first]),
              showSelectedIcon: false,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 310,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child:
                  tab == 'Summary'
                      ? _DrainageSummaryPreview(
                        quantities: quantities,
                        labels: labels,
                      )
                      : CustomPaint(
                        key: ValueKey<String>(tab),
                        painter:
                            tab == '3D'
                                ? _Drain3DPainter(
                                  type: type,
                                  profile: profile,
                                  bottomMm: bottomMm,
                                  depthMm: depthMm,
                                  wallMm: wallMm,
                                  baseMm: baseMm,
                                  coverMm: coverMm,
                                  diameterMm: diameterMm,
                                  barrels: barrels,
                                )
                                : tab == 'Plan'
                                ? _DrainPlanPainter(
                                  type: type,
                                  bottomMm: bottomMm,
                                  wallMm: wallMm,
                                )
                                : _DrainSectionPainter(
                                  type: type,
                                  profile: profile,
                                  bottomMm: bottomMm,
                                  depthMm: depthMm,
                                  sideSlopeH: sideSlopeH,
                                  wallMm: wallMm,
                                  baseMm: baseMm,
                                  coverMm: coverMm,
                                  thicknessMm: thicknessMm,
                                  diameterMm: diameterMm,
                                  barrels: barrels,
                                ),
                        child: const SizedBox.expand(),
                      ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Text(
              '$type • $profile • preview updates from the geometry fields',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrainageSummaryPreview extends StatelessWidget {
  const _DrainageSummaryPreview({
    required this.quantities,
    required this.labels,
  });
  final Map<String, double> quantities;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    final rows = labels.entries
        .where((e) => (quantities[e.key] ?? 0).abs() > 0.0000001)
        .take(9)
        .toList(growable: false);
    if (rows.isEmpty) {
      return const Center(child: Text('No calculated outputs yet.'));
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Item',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: Text(
                    'Quantity',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final e = rows[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          e.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 130,
                        child: Text(
                          (quantities[e.key] ?? 0).toStringAsFixed(3),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

abstract class _DrainPainterBase extends CustomPainter {
  const _DrainPainterBase();
  Paint line([double width = 2]) =>
      Paint()
        ..color = const Color(0xFF334155)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width;
  Paint fill(Color c) => Paint()..color = c;
  void text(
    Canvas canvas,
    String value,
    Offset p, {
    double size = 12,
    Color color = const Color(0xFF334155),
    FontWeight weight = FontWeight.w600,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(fontSize: size, color: color, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, p);
  }

  void dim(Canvas canvas, Offset a, Offset b, String label) {
    final p =
        Paint()
          ..color = const Color(0xFFEF4444)
          ..strokeWidth = 1.4;
    canvas.drawLine(a, b, p);
    final d = b - a;
    if (d.distance > 0) {
      final u = d / d.distance;
      final n = Offset(-u.dy, u.dx);
      canvas.drawLine(a - n * 5, a + n * 5, p);
      canvas.drawLine(b - n * 5, b + n * 5, p);
    }
    final mid = (a + b) / 2;
    text(
      canvas,
      label,
      mid + const Offset(4, -18),
      color: const Color(0xFFDC2626),
      size: 11,
    );
  }
}

class _DrainSectionPainter extends _DrainPainterBase {
  const _DrainSectionPainter({
    required this.type,
    required this.profile,
    required this.bottomMm,
    required this.depthMm,
    required this.sideSlopeH,
    required this.wallMm,
    required this.baseMm,
    required this.coverMm,
    required this.thicknessMm,
    required this.diameterMm,
    required this.barrels,
  });
  final String type, profile;
  final double bottomMm,
      depthMm,
      sideSlopeH,
      wallMm,
      baseMm,
      coverMm,
      thicknessMm,
      diameterMm;
  final int barrels;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );
    canvas.drawRRect(bg, fill(Colors.white));
    text(
      canvas,
      'Typical section',
      const Offset(18, 14),
      size: 14,
      weight: FontWeight.w800,
    );
    final cx = size.width / 2;
    final top = 62.0;
    final floor = size.height - 52;
    final drawDepth = math.min(150.0, size.height - 120).toDouble();

    if (type == 'Pipe drain' ||
        type == 'Underground stormwater drain' ||
        type == 'Pipe culvert') {
      final r = math.min(48.0, math.max(24.0, diameterMm / 12)).toDouble();
      final totalW = barrels * r * 2 + (barrels - 1) * 18;
      var x = cx - totalW / 2 + r;
      canvas.drawRect(
        Rect.fromLTWH(
          cx - totalW / 2 - 28,
          top + 8,
          totalW + 56,
          drawDepth + 45,
        ),
        fill(const Color(0xFFF1F5F9)),
      );
      for (var i = 0; i < barrels; i++) {
        canvas.drawCircle(Offset(x, floor - r - 12), r, line(3));
        x += r * 2 + 18;
      }
      dim(
        canvas,
        Offset(cx - totalW / 2, floor + 8),
        Offset(cx + totalW / 2, floor + 8),
        '${diameterMm.toStringAsFixed(0)} mm${barrels > 1 ? ' × $barrels' : ''}',
      );
      text(
        canvas,
        'Pipe / culvert trench',
        Offset(cx - 70, floor - drawDepth - 6),
        color: const Color(0xFF64748B),
      );
      return;
    }

    if (type == 'Earth drain' ||
        type == 'Open lined drain' ||
        type == 'Concrete channel / channelling') {
      final isRect =
          type == 'Concrete channel / channelling' && sideSlopeH <= 0.01;
      final b = math.min(150.0, math.max(70.0, bottomMm / 4)).toDouble();
      final h = drawDepth;
      final spread =
          isRect ? 0.0 : math.min(100.0, sideSlopeH * h * 0.45).toDouble();
      final path =
          Path()
            ..moveTo(cx - b / 2 - spread, top + 25)
            ..lineTo(cx - b / 2, top + 25 + h)
            ..lineTo(cx + b / 2, top + 25 + h)
            ..lineTo(cx + b / 2 + spread, top + 25);
      canvas.drawPath(path, line(type == 'Earth drain' ? 3 : 8));
      dim(
        canvas,
        Offset(cx - b / 2, floor - 12),
        Offset(cx + b / 2, floor - 12),
        '${bottomMm.toStringAsFixed(0)} mm',
      );
      dim(
        canvas,
        Offset(cx + b / 2 + spread + 28, top + 25),
        Offset(cx + b / 2 + spread + 28, top + 25 + h),
        '${depthMm.toStringAsFixed(0)} mm',
      );
      return;
    }

    final masonry = type == 'Open masonry / blockwork drain';
    final closed = type == 'Closed concrete drain';
    final innerW = math.min(170.0, math.max(85.0, bottomMm / 3.5)).toDouble();
    final wallW = math.min(48.0, math.max(24.0, wallMm / 6)).toDouble();
    final h = drawDepth;
    final left = cx - innerW / 2 - wallW;
    final right = cx + innerW / 2;
    final wallColor =
        masonry ? const Color(0xFFD8DEE7) : const Color(0xFFC7D2FE);
    canvas.drawRect(Rect.fromLTWH(left, top + 25, wallW, h), fill(wallColor));
    canvas.drawRect(Rect.fromLTWH(right, top + 25, wallW, h), fill(wallColor));
    canvas.drawRect(
      Rect.fromLTWH(
        left,
        top + 25 + h,
        innerW + 2 * wallW,
        math.max(14.0, baseMm / 10).toDouble(),
      ),
      fill(const Color(0xFFCBD5E1)),
    );
    if (closed) {
      canvas.drawRect(
        Rect.fromLTWH(
          left,
          top + 10,
          innerW + 2 * wallW,
          math.max(12.0, coverMm / 10).toDouble(),
        ),
        fill(const Color(0xFFCBD5E1)),
      );
    }
    dim(
      canvas,
      Offset(cx - innerW / 2, floor - 10),
      Offset(cx + innerW / 2, floor - 10),
      '${bottomMm.toStringAsFixed(0)} mm',
    );
    dim(
      canvas,
      Offset(right + wallW + 28, top + 25),
      Offset(right + wallW + 28, top + 25 + h),
      '${depthMm.toStringAsFixed(0)} mm',
    );
    text(
      canvas,
      masonry ? '230 mm blockwork with mortar' : 'Concrete wall',
      Offset(right + wallW + 45, top + 58),
      size: 11,
    );
    if (masonry)
      text(
        canvas,
        'OPEN — NO COVER',
        Offset(cx - 58, top - 2),
        color: const Color(0xFF2563EB),
        size: 11,
        weight: FontWeight.w800,
      );
  }

  @override
  bool shouldRepaint(covariant _DrainSectionPainter oldDelegate) =>
      type != oldDelegate.type ||
      profile != oldDelegate.profile ||
      bottomMm != oldDelegate.bottomMm ||
      depthMm != oldDelegate.depthMm ||
      sideSlopeH != oldDelegate.sideSlopeH ||
      wallMm != oldDelegate.wallMm ||
      baseMm != oldDelegate.baseMm ||
      coverMm != oldDelegate.coverMm ||
      diameterMm != oldDelegate.diameterMm ||
      barrels != oldDelegate.barrels;
}

class _Drain3DPainter extends _DrainPainterBase {
  const _Drain3DPainter({
    required this.type,
    required this.profile,
    required this.bottomMm,
    required this.depthMm,
    required this.wallMm,
    required this.baseMm,
    required this.coverMm,
    required this.diameterMm,
    required this.barrels,
  });
  final String type, profile;
  final double bottomMm, depthMm, wallMm, baseMm, coverMm, diameterMm;
  final int barrels;
  Offset iso(double x, double y, double z, Offset o) =>
      Offset(o.dx + (x - y) * .82, o.dy + (x + y) * .34 - z);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      fill(Colors.white),
    );
    text(
      canvas,
      '3D view (schematic)',
      const Offset(18, 14),
      size: 14,
      weight: FontWeight.w800,
    );
    final o = Offset(size.width * .48, size.height * .63);
    final L = math.min(170.0, size.width * .28).toDouble();
    final W = math.min(90.0, math.max(55.0, bottomMm / 6)).toDouble();
    final H = math.min(105.0, math.max(55.0, depthMm / 7)).toDouble();
    final masonry = type == 'Open masonry / blockwork drain';
    final pipe =
        type == 'Pipe drain' ||
        type == 'Underground stormwater drain' ||
        type == 'Pipe culvert';
    if (pipe) {
      final trench =
          Path()
            ..moveTo(iso(-W, 0, 0, o).dx, iso(-W, 0, 0, o).dy)
            ..lineTo(iso(W, 0, 0, o).dx, iso(W, 0, 0, o).dy)
            ..lineTo(iso(W, L, 0, o).dx, iso(W, L, 0, o).dy)
            ..lineTo(iso(-W, L, 0, o).dx, iso(-W, L, 0, o).dy)
            ..close();
      canvas.drawPath(trench, fill(const Color(0xFFE7D3B5)));
      final r = math.min(28.0, math.max(16.0, diameterMm / 28)).toDouble();
      for (var i = 0; i < barrels; i++) {
        canvas.drawCircle(
          Offset(o.dx + (i - (barrels - 1) / 2) * (r * 2 + 12), o.dy - r),
          r,
          line(3),
        );
      }
      text(
        canvas,
        '$barrels × ${diameterMm.toStringAsFixed(0)} mm',
        Offset(o.dx - 55, o.dy + 35),
        color: const Color(0xFF2563EB),
      );
      return;
    }
    final wallT = math.min(28.0, math.max(14.0, wallMm / 10)).toDouble();
    final concrete =
        masonry ? const Color(0xFFB8C0CC) : const Color(0xFFCBD5E1);
    void prism(double x1, double x2, double z1, double z2, Color c) {
      final a = iso(x1, 0, z1, o),
          b = iso(x2, 0, z1, o),
          c1 = iso(x2, L, z1, o),
          d = iso(x1, L, z1, o);
      final a2 = iso(x1, 0, z2, o),
          b2 = iso(x2, 0, z2, o),
          c2 = iso(x2, L, z2, o),
          d2 = iso(x1, L, z2, o);
      final p1 =
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(b.dx, b.dy)
            ..lineTo(b2.dx, b2.dy)
            ..lineTo(a2.dx, a2.dy)
            ..close();
      final p2 =
          Path()
            ..moveTo(b.dx, b.dy)
            ..lineTo(c1.dx, c1.dy)
            ..lineTo(c2.dx, c2.dy)
            ..lineTo(b2.dx, b2.dy)
            ..close();
      final p3 =
          Path()
            ..moveTo(a2.dx, a2.dy)
            ..lineTo(b2.dx, b2.dy)
            ..lineTo(c2.dx, c2.dy)
            ..lineTo(d2.dx, d2.dy)
            ..close();
      canvas.drawPath(p1, fill(c));
      canvas.drawPath(p2, fill(Color.lerp(c, Colors.black, .08)!));
      canvas.drawPath(p3, fill(Color.lerp(c, Colors.white, .08)!));
      canvas.drawPath(p1, line(1));
      canvas.drawPath(p2, line(1));
      canvas.drawPath(p3, line(1));
    }

    prism(-W / 2 - wallT, -W / 2, 0, H, concrete);
    prism(W / 2, W / 2 + wallT, 0, H, concrete);
    prism(-W / 2 - wallT, W / 2 + wallT, -14, 0, const Color(0xFFAEB8C6));
    if (type == 'Closed concrete drain')
      prism(-W / 2 - wallT, W / 2 + wallT, H, H + 14, const Color(0xFFAEB8C6));
    text(
      canvas,
      '${bottomMm.toStringAsFixed(0)} mm clear',
      Offset(o.dx - 38, o.dy + 35),
      color: const Color(0xFFEF4444),
      size: 11,
    );
    text(
      canvas,
      masonry ? 'Open blockwork drain' : type,
      Offset(18, size.height - 30),
      color: const Color(0xFF64748B),
      size: 11,
    );
  }

  @override
  bool shouldRepaint(covariant _Drain3DPainter oldDelegate) =>
      type != oldDelegate.type ||
      bottomMm != oldDelegate.bottomMm ||
      depthMm != oldDelegate.depthMm ||
      wallMm != oldDelegate.wallMm ||
      diameterMm != oldDelegate.diameterMm ||
      barrels != oldDelegate.barrels;
}

class _DrainPlanPainter extends _DrainPainterBase {
  const _DrainPlanPainter({
    required this.type,
    required this.bottomMm,
    required this.wallMm,
  });
  final String type;
  final double bottomMm, wallMm;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      fill(Colors.white),
    );
    text(
      canvas,
      'Plan / detail view',
      const Offset(18, 14),
      size: 14,
      weight: FontWeight.w800,
    );
    final cx = size.width / 2, cy = size.height / 2 + 12;
    final inner = math.min(150.0, math.max(80.0, bottomMm / 4)).toDouble();
    final wall = math.min(45.0, math.max(22.0, wallMm / 7)).toDouble();
    final outer = inner + 2 * wall;
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy), width: outer, height: outer),
      fill(const Color(0xFFD8DEE7)),
    );
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy), width: inner, height: inner),
      fill(Colors.white),
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(cx + outer * .68, cy),
        width: inner * .65,
        height: inner * .45,
      ),
      fill(const Color(0xFFD8DEE7)),
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(cx + outer * .68, cy),
        width: inner * .45,
        height: inner * .25,
      ),
      fill(Colors.white),
    );
    dim(
      canvas,
      Offset(cx - inner / 2, cy - inner / 2 - 24),
      Offset(cx + inner / 2, cy - inner / 2 - 24),
      '${bottomMm.toStringAsFixed(0)} mm',
    );
    text(
      canvas,
      type.contains('masonry')
          ? 'Stormwater masonry drain / manhole schematic'
          : 'Drainage plan schematic',
      Offset(cx - 125, size.height - 35),
      color: const Color(0xFF2563EB),
      size: 11,
    );
  }

  @override
  bool shouldRepaint(covariant _DrainPlanPainter oldDelegate) =>
      type != oldDelegate.type ||
      bottomMm != oldDelegate.bottomMm ||
      wallMm != oldDelegate.wallMm;
}
