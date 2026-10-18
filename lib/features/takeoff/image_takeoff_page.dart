import 'package:aqs/core/state/firestore_state.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:aqs/features/takeoff/controllers/takeoff_controller.dart';
import 'package:aqs/features/takeoff/active_summary_panel.dart';
import 'package:aqs/features/takeoff/builds/slab_composite_content.dart';
import 'package:aqs/features/takeoff/measuring_item_bar.dart';
import 'package:aqs/features/takeoff/models/measured_segment.dart';
import 'package:aqs/features/takeoff/models/rebar-footing_set.dart';
import 'package:aqs/features/takeoff/models/rebar_mark.dart';
import 'package:aqs/features/takeoff/models/rebar_set.dart';
import 'package:aqs/features/takeoff/models/saved_area.dart';
import 'package:aqs/features/takeoff/models/slab_edge_pattern.dart';
import 'package:aqs/features/takeoff/overlays/area_painter.dart';
import 'package:aqs/features/takeoff/overlays/point_painter.dart';
import 'package:aqs/features/takeoff/overlays/saved_area_painter.dart';
// import 'package:aqs/features/utils/customs.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// class SavedArea {
//   final String id;
//   final List<Offset> points;
//   final Color color;

//   SavedArea({required this.id, required this.points, required this.color});
// }

class ImageTakeoffPage extends StatefulWidget {
  final String projectId;
  final String drawingId;
  final String buildingId;
  final String drawingTitle;
  final String imageUrl;

  const ImageTakeoffPage({
    super.key,
    required this.projectId,
    required this.drawingId,
    required this.buildingId,
    required this.drawingTitle,
    required this.imageUrl,
  });

  @override
  State<ImageTakeoffPage> createState() => _ImageTakeoffPageState();
}

class _ImageTakeoffPageState extends State<ImageTakeoffPage> {
  final TransformationController _transformController =
      TransformationController();

  TakeoffMode _mode = TakeoffMode.view;
  String? _selectedSegmentId;

  Offset? _calibP1;
  Offset? _calibP2;

  Offset? _lengthP1;
  Offset? _lengthP2;
  bool _isCompositeBusy = false;

  Color _currentColor = Colors.blue;

  String? _activeLabel; // e.g. "Walling"
  String? _activeBoqCode; // e.g. "3.9(ii)"
  String? _activeUnit; // "m", "m2", "m3", "item", "kg", "ps"
  double? _activeHeightM; // used when unit is m2 (e.g. wall height)
  String? _activePresetKey;
  String?
  _activeMeasureType; // e.g. 'walling', 'compositeFooting', 'compositeSlab', etc.

  bool _previewVisible = false;
  Offset _previewOffset = const Offset(40, 80); // initial position

  double? _previewLengthMeters;
  double? _previewPixelDistanceBase;
  bool _previewCalibrated = false;
  List<Offset> _areaPoints = [];
  // String? _activeMeasureType;
  // e.g. 'walling', 'compositeFooting', 'compositeSlab', 'slabRebar', etc.

  bool get _isWallingActive =>
      (_activeMeasureType ?? '').toLowerCase() == 'walling';

  bool get _isFootingCompositeActive =>
      (_activeMeasureType ?? '').toLowerCase() == 'compositefooting';

  bool get _isSlabCompositeActive =>
      (_activeMeasureType ?? '').toLowerCase() == 'compositeslab';

  bool get _isRebarSlabActive =>
      (_activeMeasureType ?? '').toLowerCase() == 'slabrebar';

  bool get _isFootingRebarActive =>
      (_activeMeasureType ?? '').toLowerCase() == 'footingrebar';

  bool get _isBeamCompositeActive =>
      (_activeMeasureType ?? '').toLowerCase() == 'compositebeam';

  Offset? _previewP1;
  Offset? _previewP2;

  double? _previewHeightM; // for this measurement if unit == m2
  double? _previewQuantity; // computed quantity for display

  bool _isCalibrated = false;
  double _pixelsPerUnitBase = 0.0; // px per meter in image coords

  double _polygonAreaPx(List<Offset> pts) {
    double sum = 0;
    for (int i = 0; i < pts.length; i++) {
      final p1 = pts[i];
      final p2 = pts[(i + 1) % pts.length];
      sum += p1.dx * p2.dy - p2.dx * p1.dy;
    }
    return 0.5 * sum;
  }

  late final CollectionReference<Map<String, dynamic>> _measurementsRef;

  // late final TakeoffController _takeoffController;
  String? _activeBeamName;

  final TextEditingController _previewHeightController =
      TextEditingController();

  DocumentReference<Map<String, dynamic>> get _drawingRef => FirebaseFirestore
      .instance
      .collection('projects')
      .doc(widget.projectId)
      .collection('buildings')
      .doc(widget.buildingId)
      .collection('drawings')
      .doc(widget.drawingId);

  @override
  void initState() {
    super.initState();

    _measurementsRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(widget.projectId)
        .collection('buildings')
        .doc(widget.buildingId)
        .collection('measurements');
  }

  void _resetArea() {
    setState(() {
      _areaPoints = [];
    });
  }

  void _setMode(TakeoffMode mode) {
    setState(() {
      _mode = mode;
      _calibP1 = null;
      _calibP2 = null;
      _lengthP1 = null;
      _lengthP2 = null;
    });
  }

  bool _isBusy = false;

  Future<void> _handleCalibrateTap(
    Offset pos,
    Map<String, dynamic> drawingData,
  ) async {
    // pos is in image/local coordinates (independent of zoom)
    setState(() {
      if (_calibP1 == null) {
        _calibP1 = pos;
      } else if (_calibP2 == null) {
        _calibP2 = pos;
      } else {
        _calibP1 = pos;
        _calibP2 = null;
      }
    });

    if (_calibP1 != null && _calibP2 != null) {
      final p1 = _calibP1!;
      final p2 = _calibP2!;
      final dx = p2.dx - p1.dx;
      final dy = p2.dy - p1.dy;

      // In image-based view we already get base coordinates,
      // so no need to divide by zoom.
      final pixelDistanceBase = math.sqrt(dx * dx + dy * dy);

      final controller = TextEditingController();

      final ok =
          await showDialog<bool>(
            context: context,
            builder: (ctx) {
              return AlertDialog(
                title: const Text('Set scale'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Enter the real distance (m) between the two points you clicked.',
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Real distance (m)',
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ) ??
          false;

      if (ok) {
        final realStr = controller.text.trim();
        final realDist = double.tryParse(realStr);
        if (realDist != null && realDist > 0) {
          final pixelsPerUnitBase = pixelDistanceBase / realDist;

          await _drawingRef.update({
            'calibrated': true,
            'unit': 'm',
            'pixelsPerUnit': pixelsPerUnitBase,
            'scaleText':
                'Calibrated: ~${pixelsPerUnitBase.toStringAsFixed(2)} px per meter (image base)',
          });

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Scale calibrated successfully')),
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Invalid distance')));
        }
      }

      setState(() {
        _calibP1 = null;
        _calibP2 = null;
      });
    }
  }

  Future<void> _completeAreaMeasurement({
    required Map<String, dynamic> drawingData,
    required List<Offset> polygon,
  }) async {
    if (polygon.length < 3) return;

    // 1) area in image pixels² (base coords)
    final areaPxBase = _polygonAreaPx(polygon).abs();
    if (areaPxBase <= 0) return;

    // 2) use calibration
    final calibrated = drawingData['calibrated'] == true;
    final pixelsPerUnitBase = (drawingData['pixelsPerUnit'] ?? 0).toDouble();

    double? areaM2;
    if (calibrated && pixelsPerUnitBase > 0) {
      final pxPerMeter = pixelsPerUnitBase; // px per 1 m
      final px2PerM2 = pxPerMeter * pxPerMeter; // px² per 1 m²
      areaM2 = areaPxBase / px2PerM2;
    }

    if (!mounted) return;

    final label = _activeLabel ?? '';
    final boq = _activeBoqCode ?? '';
    final unitDisplay = 'm²';

    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('Floor area measurement'),
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
                  child: const Text('Save'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirm) return;

    // 3) Save area measurement (unit m2)
    await _saveAreaMeasurement(
      polygon: polygon,
      areaM2: areaM2,
      areaPxBase: areaPxBase,
    );
  }

  Future<void> _saveAreaMeasurement({
    required List<Offset> polygon,
    required double? areaM2,
    required double areaPxBase,
  }) async {
    if (_activeBoqCode == null || _activeBoqCode!.trim().isEmpty) return;

    final polyData = polygon.map((p) => {'x': p.dx, 'y': p.dy}).toList();

    await _measurementsRef.add({
      'projectId': widget.projectId,
      'buildingId': widget.buildingId,
      'drawingId': widget.drawingId,
      'type': 'area',
      'measureType':
          _activeMeasureType ?? inferMeasureTypeFromLabel(_activeLabel ?? ''),
      'unit': 'm2',
      'value': areaM2,
      'areaPx': areaPxBase,
      'label': _activeLabel,
      'boqCode': _activeBoqCode,
      'color': _currentColor.value,
      'polygon': polyData,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  //  bool get _isBeamCompositeActive =>
  //     (_activeMeasureType ?? '').toLowerCase() == 'compositebeam';
  // void _handleLengthTap(
  //   Offset imagePos,
  //   Map<String, dynamic> drawingData,
  // ) async {
  //   if (_lengthP1 == null) {
  //     setState(() {
  //       _lengthP1 = imagePos;
  //       _lengthP2 = null;
  //     });
  //     return;
  //   }

  //   // second tap → close segment
  //   final p1 = _lengthP1!;
  //   final p2 = imagePos;
  //   // print(_isBeamCompositeActive);

  //   _resetLength();

  //   if (_isBeamCompositeActive) {
  //     // 👇 Beam composite flow (Option B: concrete + formwork only)
  //     // await _takeoffController.openBeamCompositeFromSegment(
  //     //   context: context,
  //     //   projectId: widget.projectId,
  //     //   buildingId: widget.buildingId,
  //     //   drawingId: widget.drawingId,
  //     //   p1: _lengthP1!,
  //     //   p2: _lengthP2!,
  //     //   drawingData: drawingData,
  //     //   currentColor: _currentColor,
  //     //   activeLabel: _activeLabel,
  //     //   activeBeamName: _activeBeamName, // 👈 NEW
  //     // );
  //   } else {
  //     // your existing length measurement logic
  //     await _completeLengthMeasurement(p1, p2, drawingData);
  //   }
  // }

  void _handleAreaTap(Offset pos, Map<String, dynamic> drawingData) async {
    print(
      'measureType=$_activeMeasureType '
      ' slabCompositeActive=$_isSlabCompositeActive '
      ' footingCompositeActive=$_isFootingCompositeActive',
    );

    // 1) Add point to the current polygon being drawn
    setState(() {
      _areaPoints = List.of(_areaPoints)..add(pos);
    });

    // Needs at least 3 points to close a polygon
    if (_areaPoints.length < 3) return;

    // 2) Check if we tapped near the FIRST point to close the polygon
    final first = _areaPoints.first;
    final distToFirst = (pos - first).distance;
    const closeRadius = 12.0;

    if (distToFirst <= closeRadius) {
      // polygon closed
      final polygon = List<Offset>.from(_areaPoints);

      // reset UI poly
      _resetArea();

      // 3) Route according to the active measure type
      if (_isFootingCompositeActive) {
        // 👉 Footing composite (C + R + F)
        await _openFootingCompositeFromPolygon(
          polygon: polygon,
          drawingData: drawingData,
        );
      } else if (_isSlabCompositeActive) {
        // 👉 Suspended slab composite via controller (C + soffit + edge + R)
        // Optionally show a local busy spinner
        setState(() {
          _isBusy = true; // define bool _isBusy = false in your state
        });
        try {
          // await _takeoffController.openSlabCompositeFromPolygon(
          //   context: context,
          //   projectId: widget.projectId,
          //   buildingId: widget.buildingId,
          //   drawingId: widget.drawingId,
          //   polygon: polygon,
          //   drawingData: drawingData,
          //   currentColor: _currentColor,
          //   activeLabel: _activeLabel,
          // );
        } finally {
          if (!mounted) return;
          setState(() {
            _isBusy = false;
          });
        }
      } else if (_isRebarSlabActive) {
        // 👉 Rebar-only slab (old flow)
        await _openRebarSlabFromPolygon(
          polygon: polygon,
          drawingData: drawingData,
        );
      } else {
        // 👉 Normal floor / tiling / plain area
        await _completeAreaMeasurement(
          polygon: polygon,
          drawingData: drawingData,
        );
      }
    }
  }

  void _zoomIn() {
    final m = _transformController.value.clone();
    m.scale(1.25);
    _transformController.value = m;
  }

  void _zoomOut() {
    final m = _transformController.value.clone();
    m.scale(0.8);
    _transformController.value = m;
  }

  Future<void> _saveMeasurement({
    required Offset p1,
    required Offset p2,
    required double? lengthMeters,
    double? overrideHeightM,
  }) async {
    if (_activeBoqCode == null || _activeBoqCode!.trim().isEmpty) return;

    final unit = _activeUnit ?? 'm';
    final isWalling = _isWallingActive;

    double? quantity;
    double? heightForThis;

    if (lengthMeters != null) {
      switch (unit) {
        case 'm':
          quantity = lengthMeters;
          break;
        case 'm2':
          if (isWalling) {
            heightForThis = overrideHeightM ?? _activeHeightM;
            if (heightForThis != null && heightForThis > 0) {
              quantity = lengthMeters * heightForThis;
            }
          } else {
            quantity = lengthMeters;
          }
          break;
        case 'item':
        case 'ps':
          quantity = 1.0;
          break;
        case 'm3':
        case 'kg':
          quantity = lengthMeters;
          break;
        default:
          quantity = lengthMeters;
          break;
      }
    }

    await _measurementsRef.add({
      'projectId': widget.projectId,
      'drawingId': widget.drawingId,
      'buildingId': widget.buildingId,
      'type': 'length',
      'measureType':
          _activeMeasureType ?? inferMeasureTypeFromLabel(_activeLabel ?? ''),
      'unit': unit,
      'value': quantity,
      'baseLengthM': lengthMeters,
      'heightM': heightForThis,
      'label': _activeLabel,
      'boqCode': _activeBoqCode,
      'color': _currentColor.value,
      'p1': {'x': p1.dx, 'y': p1.dy},
      'p2': {'x': p2.dx, 'y': p2.dy},
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> _ensureActiveMeasurementItem() async {
    // 1) If we already have a measureType, try to auto-fill a sensible unit.
    if ((_activeUnit == null || _activeUnit!.trim().isEmpty) &&
        _activeMeasureType != null &&
        _activeMeasureType!.trim().isNotEmpty) {
      final defUnit = _defaultUnitForMeasureType(_activeMeasureType!);
      if (defUnit != null) {
        setState(() {
          _activeUnit = defUnit;
        });
      }
    }

    final hasLabel = _activeLabel != null && _activeLabel!.trim().isNotEmpty;
    final hasUnit = _activeUnit != null && _activeUnit!.trim().isNotEmpty;
    final hasMeasureType =
        _activeMeasureType != null && _activeMeasureType!.trim().isNotEmpty;

    // Helpers for special behaviour
    bool measureTypeNeedsHeight(String? t) =>
        t == 'walling'; // only walling needs height (m2)

    bool measureTypeCanSkipLabelAndUnit(String? t) =>
        t == 'compositeFooting' || t == 'compositeSlab' || t == 'compositeBeam';

    // 2) Composite flows: only measureType is required.
    if (hasMeasureType && measureTypeCanSkipLabelAndUnit(_activeMeasureType)) {
      // For composite footing/slab we don't care about label/unit/height here.
      return true;
    }

    // 3) Non-composite: normal checks (walling may need height)
    final needsHeight =
        measureTypeNeedsHeight(_activeMeasureType) && (_activeUnit == 'm2');
    final hasHeight = _activeHeightM != null && _activeHeightM! > 0;

    if (hasLabel && hasUnit && hasMeasureType && (!needsHeight || hasHeight)) {
      // We already have everything needed → no dialog.
      return true;
    }

    // 4) Ask once via the dialog to fill missing pieces.
    await _showMeasurementItemDialog();

    final hasLabel2 = _activeLabel != null && _activeLabel!.trim().isNotEmpty;
    final hasUnit2 = _activeUnit != null && _activeUnit!.trim().isNotEmpty;
    final hasMeasureType2 =
        _activeMeasureType != null && _activeMeasureType!.trim().isNotEmpty;

    final needsHeight2 =
        measureTypeNeedsHeight(_activeMeasureType) && (_activeUnit == 'm2');
    final hasHeight2 = _activeHeightM != null && _activeHeightM! > 0;

    if (!hasMeasureType2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose a measuring type (e.g. Walling).'),
        ),
      );
    }

    if (!hasUnit2 && !measureTypeCanSkipLabelAndUnit(_activeMeasureType)) {
      // For composites we skip this warning; others still need a unit.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set measuring unit before proceeding.'),
        ),
      );
    }

    if (needsHeight2 && !hasHeight2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set wall height for walling (m²).'),
        ),
      );
    }

    return hasLabel2 &&
        hasUnit2 &&
        hasMeasureType2 &&
        (!needsHeight2 || hasHeight2);
  }

  /// Helper: default unit per measureType.
  /// Call this from inside your State class.
  String? _defaultUnitForMeasureType(String? t) {
    switch (t) {
      case 'walling':
      case 'tiling':
        return 'm2';
      case 'pipe':
      case 'beam':
      case 'slabEdge':
      case 'cableTray':
        return 'm';
      case 'slabRebar':
      case 'footingRebar':
        return 'kg';
      // For composite types we let unit be cosmetic / unused.
      case 'compositeFooting':
      case 'compositeSlab':
      case 'compositeBeam':
      case 'compositeColumn':
        return null;
      default:
        return null;
    }
  }

  void _handleSegmentTap(Offset pos, List<MeasuredSegment> segments) async {
    const double maxDistance = 10.0;
    MeasuredSegment? closest;
    double closestDist = double.infinity;

    for (final seg in segments) {
      final d = _distancePointToSegment(pos, seg.p1, seg.p2);
      if (d < closestDist) {
        closestDist = d;
        closest = seg;
      }
    }

    if (closest == null || closestDist > maxDistance) {
      setState(() {
        _selectedSegmentId = null;
      });
      return;
    }

    setState(() {
      _selectedSegmentId = closest!.id;
    });

    final confirm =
        await showDialog<bool>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Delete measurement?'),
                content: const Text(
                  'Do you want to delete this measurement line?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
        ) ??
        false;

    if (confirm && _selectedSegmentId != null) {
      await _measurementsRef.doc(_selectedSegmentId!).delete();
      if (!mounted) return;
      setState(() {
        _selectedSegmentId = null;
      });
    }
  }

  bool _pointInPolygon(Offset p, List<Offset> poly) {
    // Ray casting algorithm
    bool inside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].dx;
      final yi = poly[i].dy;
      final xj = poly[j].dx;
      final yj = poly[j].dy;

      final intersect =
          ((yi > p.dy) != (yj > p.dy)) &&
          (p.dx <
              (xj - xi) * (p.dy - yi) / ((yj - yi) == 0 ? 1e-9 : (yj - yi)) +
                  xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  Future<void> _showRebarFootingDetailsDialog(
    String footingGroupId,
    List<QueryDocumentSnapshot> docs,
  ) async {
    if (docs.isEmpty) return;

    // mutable copy so we can update after deletions
    List<QueryDocumentSnapshot> localDocs = List.of(docs);

    double _asDouble(dynamic v) => v is num ? v.toDouble() : 0.0;
    int _asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            if (localDocs.isEmpty) {
              final firstData = localDocs.first.data() as Map<String, dynamic>;

              // ---- compute summary as before ----
              double totalLengthAllM = 0.0;
              double totalWeightAllKg = 0.0;
              int footingCount = 0;

              for (final d in localDocs) {
                final data = d.data() as Map<String, dynamic>;
                totalLengthAllM += _asDouble(data['lengthAllFootingsM']);
                totalWeightAllKg += _asDouble(data['weightAllFootingsKg']);
                footingCount = _asInt(data['nFootings'] ?? footingCount);
              }
              return AlertDialog(
                title: const Text('Footing composite details'),
                content: const Text(
                  'No measurements remain for this footing group.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              );
            }

            // ---- split into concrete / formwork / rebar Footing ----
            final concreteDocs =
                localDocs.where((d) {
                  final m = d.data() as Map<String, dynamic>;
                  return (m['type'] ?? '') == 'footingConcrete';
                }).toList();

            final formworkDocs =
                localDocs.where((d) {
                  final m = d.data() as Map<String, dynamic>;
                  return (m['type'] ?? '') == 'footingFormwork';
                }).toList();

            final rebarDocs =
                localDocs.where((d) {
                  final m = d.data() as Map<String, dynamic>;
                  return (m['type'] ?? '') == 'rebarFooting';
                }).toList();

            // ---- read nFootings from any of the docs ----
            int nFootings = 0;
            Map<String, dynamic>? firstAny;
            if (concreteDocs.isNotEmpty) {
              firstAny = concreteDocs.first.data() as Map<String, dynamic>;
            } else if (formworkDocs.isNotEmpty) {
              firstAny = formworkDocs.first.data() as Map<String, dynamic>;
            } else if (rebarDocs.isNotEmpty) {
              firstAny = rebarDocs.first.data() as Map<String, dynamic>;
            }

            if (firstAny != null) {
              nFootings = _asInt(
                firstAny['nFootings'] ?? firstAny['footingCount'],
              );
            }

            // ---- totals ----
            final totalConcreteM3 = concreteDocs.fold<double>(
              0.0,
              (sum, d) =>
                  sum + _asDouble((d.data() as Map<String, dynamic>)['value']),
            );

            final totalFormworkM2 = formworkDocs.fold<double>(
              0.0,
              (sum, d) =>
                  sum + _asDouble((d.data() as Map<String, dynamic>)['value']),
            );

            final totalRebarKg = rebarDocs.fold<double>(
              0.0,
              (sum, d) =>
                  sum +
                  _asDouble(
                    (d.data() as Map<String, dynamic>)['weightAllFootingsKg'] ??
                        (d.data()
                            as Map<
                              String,
                              dynamic
                            >)['totalWeightAllFootingsKg'],
                  ),
            );
            final firstData = localDocs.first.data() as Map<String, dynamic>;

            // ---- compute summary as before ----
            double totalLengthAllM = 0.0;
            double totalWeightAllKg = 0.0;
            int footingCount = 0;

            return AlertDialog(
              title: const Text('Footing composite details'),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ---- SUMMARY HEADER ----
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (nFootings > 0)
                              Text(
                                'Footings in this group: $nFootings',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (totalConcreteM3 > 0)
                              Text(
                                'Concrete: ${totalConcreteM3.toStringAsFixed(3)} m³',
                                style: const TextStyle(fontSize: 11),
                              ),
                            if (totalFormworkM2 > 0)
                              Text(
                                'Formwork: ${totalFormworkM2.toStringAsFixed(3)} m²',
                                style: const TextStyle(fontSize: 11),
                              ),
                            if (totalRebarKg > 0)
                              Text(
                                'Rebar: ${totalRebarKg.toStringAsFixed(2)} kg',
                                style: const TextStyle(fontSize: 11),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Divider(),

                      // ---- DETAILS LIST ----
                      SizedBox(
                        // height: 260,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // --- Concrete section ---
                              if (concreteDocs.isNotEmpty) ...[
                                const Text(
                                  'Concrete',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ...concreteDocs.map((d) {
                                  final m = d.data() as Map<String, dynamic>;
                                  final vTotal = _asDouble(m['value']);
                                  final boqCode = m['boqCode'] ?? '';
                                  final vPerFoot = _asDouble(
                                    m['valuePerFooting'],
                                  );
                                  final L = _asDouble(m['lengthM']);
                                  final B = _asDouble(m['widthM']);
                                  final t = _asDouble(m['thicknessM']);

                                  return ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      'Footing concrete',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Size ~ ${L.toStringAsFixed(3)}m × '
                                      '${B.toStringAsFixed(3)}m × '
                                      '${t.toStringAsFixed(3)}m\n'
                                      'Per footing: ${vPerFoot.toStringAsFixed(3)} m³, '
                                      'Total: ${vTotal.toStringAsFixed(3)} m³\n'
                                      'BoQ Code: $boqCode',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                      ),
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: ctx,
                                          builder: (ctx2) {
                                            return AlertDialog(
                                              title: const Text(
                                                'Delete concrete measurement?',
                                              ),
                                              content: const Text(
                                                'This will remove the concrete entry for this footing group.',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed:
                                                      () => Navigator.pop(
                                                        ctx2,
                                                        false,
                                                      ),
                                                  child: const Text('Cancel'),
                                                ),
                                                FilledButton(
                                                  onPressed:
                                                      () => Navigator.pop(
                                                        ctx2,
                                                        true,
                                                      ),
                                                  child: const Text('Delete'),
                                                ),
                                              ],
                                            );
                                          },
                                        );

                                        if (confirm == true) {
                                          await _measurementsRef
                                              .doc(d.id)
                                              .delete();
                                          setStateDialog(() {
                                            localDocs.removeWhere(
                                              (x) => x.id == d.id,
                                            );
                                          });
                                        }
                                      },
                                    ),
                                  );
                                }).toList(),
                                const Divider(),
                              ],

                              // --- Formwork section ---
                              if (formworkDocs.isNotEmpty) ...[
                                const Text(
                                  'Formwork',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ...formworkDocs.map((d) {
                                  final m = d.data() as Map<String, dynamic>;
                                  final boqCode = m['boqCode'] ?? '';
                                  final vTotal = _asDouble(m['value']);
                                  final vPerFoot = _asDouble(
                                    m['valuePerFooting'],
                                  );
                                  final L = _asDouble(m['lengthM']);
                                  final B = _asDouble(m['widthM']);
                                  final t = _asDouble(m['thicknessM']);
                                  final per = _asDouble(m['perimeterM']);

                                  return ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      'Footing formwork',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Perimeter: ${per.toStringAsFixed(3)} m\n'
                                      'Size ~ ${L.toStringAsFixed(3)}m × '
                                      '${B.toStringAsFixed(3)}m × '
                                      '${t.toStringAsFixed(3)}m\n'
                                      'Per footing: ${vPerFoot.toStringAsFixed(3)} m², '
                                      'Total: ${vTotal.toStringAsFixed(3)} m²\n'
                                      'BoQ Code: $boqCode',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                      ),
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: ctx,
                                          builder: (ctx2) {
                                            return AlertDialog(
                                              title: const Text(
                                                'Delete formwork measurement?',
                                              ),
                                              content: const Text(
                                                'This will remove the formwork entry for this footing group.',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed:
                                                      () => Navigator.pop(
                                                        ctx2,
                                                        false,
                                                      ),
                                                  child: const Text('Cancel'),
                                                ),
                                                FilledButton(
                                                  onPressed:
                                                      () => Navigator.pop(
                                                        ctx2,
                                                        true,
                                                      ),
                                                  child: const Text('Delete'),
                                                ),
                                              ],
                                            );
                                          },
                                        );

                                        if (confirm == true) {
                                          await _measurementsRef
                                              .doc(d.id)
                                              .delete();
                                          setStateDialog(() {
                                            localDocs.removeWhere(
                                              (x) => x.id == d.id,
                                            );
                                          });
                                        }
                                      },
                                    ),
                                  );
                                }).toList(),
                                const Divider(),
                              ],

                              // --- Rebar section ---
                              // --- Rebar section ---
                              if (rebarDocs.isNotEmpty) ...[
                                const Text(
                                  'Rebar',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ...rebarDocs.map((d) {
                                  final m = d.data() as Map<String, dynamic>;

                                  final markRaw =
                                      (m['rawMark'] ?? m['markRaw'] ?? '')
                                          as String;
                                  final direction =
                                      (m['direction'] ?? '') as String;
                                  final diaMm = _asInt(
                                    m['diameterMm'] ?? m['rebarDiameterMm'],
                                  );
                                  final qtyPerFooting = _asInt(
                                    m['barsPerFooting'] ??
                                        m['rebarQuantityPerFooting'],
                                  );
                                  final spacingMm =
                                      m['spacingMm']; // may be null/num

                                  final clearSpanM = _asDouble(m['clearSpanM']);
                                  final embedEachEndM = _asDouble(
                                    m['embedEachEndM'],
                                  );
                                  final extraM = _asDouble(m['extraLengthM']);
                                  final barLengthM = _asDouble(m['barLengthM']);

                                  final lenPerFoot = _asDouble(
                                    m['lengthPerFootingM'],
                                  );
                                  final lenAllFoot = _asDouble(
                                    m['lengthAllFootingsM'] ??
                                        m['totalLengthAllFootingsM'],
                                  );
                                  final wtPerFoot = _asDouble(
                                    m['weightPerFootingKg'],
                                  );
                                  final wtAllFoot = _asDouble(
                                    m['weightAllFootingsKg'] ??
                                        m['totalWeightAllFootingsKg'],
                                  );
                                  final boqCode = m['boqCode'] ?? '';

                                  return ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      markRaw.isNotEmpty
                                          ? markRaw
                                          : 'Rebar Ø$diaMm',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (direction.isNotEmpty)
                                          Text(
                                            'Direction: ${direction[0].toUpperCase()}${direction.substring(1)}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                        Text(
                                          'Ø$diaMm, bars/footing: $qtyPerFooting'
                                          '${spacingMm != null ? ', @ ${spacingMm}mm' : ''}',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        Text(
                                          'Clear span: ${clearSpanM.toStringAsFixed(3)} m, '
                                          'embed each end: ${embedEachEndM.toStringAsFixed(3)} m, '
                                          'extra: ${extraM.toStringAsFixed(3)} m',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        Text(
                                          'L/bar: ${barLengthM.toStringAsFixed(3)} m',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        Text(
                                          'Per footing → L: ${lenPerFoot.toStringAsFixed(3)} m, '
                                          'Wt: ${wtPerFoot.toStringAsFixed(2)} kg',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        Text(
                                          'All footings → L: ${lenAllFoot.toStringAsFixed(3)} m, '
                                          'Wt: ${wtAllFoot.toStringAsFixed(2)} kg',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        Text(
                                          'BoQ Code: $boqCode',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // ✏️ EDIT BUTTON
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            size: 18,
                                          ),
                                          tooltip: 'Edit rebar mark',
                                          onPressed: () async {
                                            await _showEditRebarFootingMarkDialog(
                                              d.reference,
                                              m,
                                            );
                                            // After edit, simply close this details dialog and let user tap again
                                            if (Navigator.of(ctx).canPop()) {
                                              Navigator.of(ctx).pop();
                                            }
                                          },
                                        ),
                                        // 🗑 DELETE BUTTON
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                          ),
                                          onPressed: () async {
                                            final confirm = await showDialog<
                                              bool
                                            >(
                                              context: ctx,
                                              builder: (ctx2) {
                                                return AlertDialog(
                                                  title: const Text(
                                                    'Delete rebar mark?',
                                                  ),
                                                  content: Text(
                                                    'Delete "$markRaw" from this footing group?',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed:
                                                          () => Navigator.pop(
                                                            ctx2,
                                                            false,
                                                          ),
                                                      child: const Text(
                                                        'Cancel',
                                                      ),
                                                    ),
                                                    FilledButton(
                                                      onPressed:
                                                          () => Navigator.pop(
                                                            ctx2,
                                                            true,
                                                          ),
                                                      child: const Text(
                                                        'Delete',
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              },
                                            );

                                            if (confirm == true) {
                                              await _measurementsRef
                                                  .doc(d.id)
                                                  .delete();
                                              setStateDialog(() {
                                                localDocs.removeWhere(
                                                  (x) => x.id == d.id,
                                                );
                                              });
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
                FilledButton(
                  onPressed: () async {
                    // use data from first doc as base
                    await _showAddRebarFootingMarkDialog(
                      footingGroupId,
                      firstData,
                    );
                    // after adding, just close this dialog;
                    // when you tap the polygon again you’ll see updated list
                    if (Navigator.of(ctx).canPop()) {
                      Navigator.of(ctx).pop();
                    }
                  },
                  child: const Text('Add rebar mark'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showRebarSlabDetailsDialog(
    String slabId,
    List<QueryDocumentSnapshot> docs,
  ) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Slab rebar details'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) {
                      final d = docs[i];
                      final m = d.data() as Map<String, dynamic>;

                      final markRaw = (m['markRaw'] ?? '') as String;
                      final dir =
                          (m['clearSpanM'] ?? 0.0) == (m['widthM'] ?? -9999.0)
                              ? 'H'
                              : 'V'; // optional – or store direction explicitly

                      final clearSpan =
                          (m['clearSpanM'] ?? 0.0 as num).toDouble();
                      final barLen = (m['barLengthM'] ?? 0.0 as num).toDouble();
                      final totalLen =
                          (m['totalLengthM'] ?? 0.0 as num).toDouble();
                      final totalKg =
                          (m['totalWeightKg'] ?? 0.0 as num).toDouble();

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 0,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(6.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      markRaw.isNotEmpty
                                          ? markRaw
                                          : 'Rebar set ${i + 1}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Clear span: ${clearSpan.toStringAsFixed(3)} m, '
                                      'L/bar: ${barLen.toStringAsFixed(3)} m',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    Text(
                                      'Total length: ${totalLen.toStringAsFixed(3)} m, '
                                      'Weight: ${totalKg.toStringAsFixed(1)} kg',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                children: [
                                  IconButton(
                                    tooltip: 'Edit',
                                    icon: const Icon(Icons.edit, size: 18),
                                    onPressed: () async {
                                      Navigator.pop(ctx); // close main dialog
                                      await _showEditRebarSlabMarkDialog(d);
                                    },
                                  ),
                                  IconButton(
                                    tooltip: 'Delete',
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                    ),
                                    onPressed: () async {
                                      await d.reference.delete();
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditRebarSlabMarkDialog(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;

    final markRaw = (data['markRaw'] ?? '') as String;
    final clearSpanM = (data['clearSpanM'] ?? 0.0 as num).toDouble();
    final oldEmbed = (data['embedEachEndM'] ?? 0.0 as num).toDouble();
    final oldExtra = (data['extraLengthM'] ?? 0.0 as num).toDouble();

    final markController = TextEditingController(text: markRaw);
    final embedController = TextEditingController(
      text: oldEmbed.toStringAsFixed(3),
    );
    final extraController = TextEditingController(
      text: oldExtra.toStringAsFixed(3),
    );

    RebarMark? parsed;
    double? barLengthM;
    double? totalLengthM;
    double? unitWeight;
    double? totalWeightKg;
    String? error;

    void recompute(StateSetter setStateDialog) {
      final rawMark = markController.text.trim();
      final embedStr = embedController.text.trim();
      final extraStr = extraController.text.trim();

      if (rawMark.isEmpty) {
        setStateDialog(() {
          parsed = null;
          barLengthM = null;
          totalLengthM = null;
          unitWeight = null;
          totalWeightKg = null;
          error = null;
        });
        return;
      }

      try {
        final m = RebarMark.parse(rawMark);
        final embed = double.tryParse(embedStr) ?? 0.0;
        final extra = double.tryParse(extraStr) ?? 0.0;

        final Lbar = clearSpanM + 2 * embed + extra;
        final Ltotal = m.quantity * Lbar;
        final uw = rebarUnitWeightKgPerM(m.diameterMm);
        final wTotal = Ltotal * uw;

        setStateDialog(() {
          parsed = m;
          barLengthM = Lbar;
          totalLengthM = Ltotal as double?;
          unitWeight = uw;
          totalWeightKg = wTotal;
          error = null;
        });
      } catch (e) {
        setStateDialog(() {
          parsed = null;
          barLengthM = null;
          totalLengthM = null;
          unitWeight = null;
          totalWeightKg = null;
          error = e.toString();
        });
      }
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Edit rebar mark'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Clear span: ${clearSpanM.toStringAsFixed(3)} m',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Rebar mark:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: markController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 12),
                      onChanged: (_) => recompute(setStateDialog),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Embed each end (m):',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: embedController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 12),
                      onChanged: (_) => recompute(setStateDialog),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Extra length (laps/hooks, m):',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: extraController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 12),
                      onChanged: (_) => recompute(setStateDialog),
                    ),
                    const SizedBox(height: 8),
                    if (error != null)
                      Text(
                        error!,
                        style: const TextStyle(color: Colors.red, fontSize: 11),
                      ),
                    if (parsed != null && barLengthM != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Bars: ${parsed!.quantity}${parsed!.barType}'
                        '-${parsed!.spacingMm}${parsed!.layer}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      Text(
                        'L/bar: ${barLengthM!.toStringAsFixed(3)} m, '
                        'Total: ${totalLengthM!.toStringAsFixed(3)} m',
                        style: const TextStyle(fontSize: 11),
                      ),
                      Text(
                        'Weight: ${unitWeight!.toStringAsFixed(3)} kg/m → '
                        '${totalWeightKg!.toStringAsFixed(1)} kg',
                        style: const TextStyle(fontSize: 11),
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
                  onPressed:
                      parsed != null &&
                              barLengthM != null &&
                              totalLengthM != null &&
                              totalWeightKg != null
                          ? () => Navigator.pop(ctx, true)
                          : null,
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) return;
    if (parsed == null ||
        barLengthM == null ||
        totalLengthM == null ||
        totalWeightKg == null)
      return;

    // Update Firestore doc
    final m = parsed!;
    final embed = double.tryParse(embedController.text.trim()) ?? 0.0;
    final extra = double.tryParse(extraController.text.trim()) ?? 0.0;

    await doc.reference.update({
      'markRaw': '${m.quantity}${m.barType}-${m.spacingMm}${m.layer}',
      'quantity': m.quantity,
      'barType': m.barType,
      'diameterMm': m.diameterMm,
      'spacingMm': m.spacingMm,
      'layer': m.layer,
      'embedEachEndM': embed,
      'extraLengthM': extra,
      'barLengthM': barLengthM,
      'totalLengthM': totalLengthM,
      'unitWeightKgPerM': unitWeight,
      'totalWeightKg': totalWeightKg,
      'value':
          (_activeUnit == 'kg' || _activeUnit == 'tonne')
              ? totalWeightKg
              : totalLengthM,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  double _distancePointToSegment(Offset p, Offset a, Offset b) {
    final ap = p - a;
    final ab = b - a;
    final ab2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (ab2 == 0) return (p - a).distance;

    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / ab2).clamp(0.0, 1.0);
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distance;
  }

  void _recomputePreviewQuantity() {
    final unit = _activeUnit ?? 'm';
    final len = _previewLengthMeters;
    final h = _previewHeightM;
    final isWalling = _isWallingActive;

    if (len == null) {
      _previewQuantity = null;
      return;
    }

    switch (unit) {
      case 'm':
        _previewQuantity = len;
        break;
      case 'm2':
        if (isWalling) {
          if (h == null || h <= 0) {
            _previewQuantity = null;
          } else {
            _previewQuantity = len * h;
          }
        } else {
          _previewQuantity = len;
        }
        break;
      case 'item':
      case 'ps':
        _previewQuantity = 1.0;
        break;
      case 'm3':
      case 'kg':
        _previewQuantity = len;
        break;
      default:
        _previewQuantity = len;
        break;
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    _previewHeightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _drawingRef.stateSnapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          print(snapshot.error);
          return Scaffold(
            appBar: AppBar(title: Text(widget.drawingTitle)),
            body: const Center(child: Text('Error loading drawing')),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.drawingTitle)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final calibrated = data['calibrated'] == true;
        final scaleText = (data['scaleText'] ?? '') as String;

        return Scaffold(
          appBar: AppBar(
            title: Text(widget.drawingTitle),
            actions: [
              IconButton(
                tooltip: 'Delete a line (tap on it)',
                icon: Icon(
                  Icons.delete_sweep,
                  color: _mode == TakeoffMode.editSegment ? Colors.red : null,
                ),
                onPressed: () {
                  _setMode(TakeoffMode.editSegment);
                },
              ),
              IconButton(
                tooltip: 'Zoom out',
                icon: const Icon(Icons.zoom_out),
                onPressed: _zoomOut,
              ),
              IconButton(
                tooltip: 'Zoom in',
                icon: const Icon(Icons.zoom_in),
                onPressed: _zoomIn,
              ),
              IconButton(
                tooltip: 'Undo last',
                icon: const Icon(Icons.undo),
                onPressed: _undoLast,
              ),
              PopupMenuButton<Color>(
                tooltip: 'Measurement color',
                icon: Icon(Icons.color_lens, color: _currentColor),
                onSelected: (color) {
                  setState(() {
                    _currentColor = color;
                  });
                },
                itemBuilder:
                    (ctx) => [
                      PopupMenuItem(
                        value: Colors.blue,
                        child: Row(
                          children: const [
                            Icon(Icons.circle, color: Colors.blue, size: 16),
                            SizedBox(width: 8),
                            Text('Blue'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: Colors.red,
                        child: Row(
                          children: const [
                            Icon(Icons.circle, color: Colors.red, size: 16),
                            SizedBox(width: 8),
                            Text('Red'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: Colors.green,
                        child: Row(
                          children: const [
                            Icon(Icons.circle, color: Colors.green, size: 16),
                            SizedBox(width: 8),
                            Text('Green'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: Colors.orange,
                        child: Row(
                          children: const [
                            Icon(Icons.circle, color: Colors.orange, size: 16),
                            SizedBox(width: 8),
                            Text('Orange'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: Colors.purple,
                        child: Row(
                          children: const [
                            Icon(Icons.circle, color: Colors.purple, size: 16),
                            SizedBox(width: 8),
                            Text('Purple'),
                          ],
                        ),
                      ),
                    ],
              ),
              IconButton(
                tooltip: 'View',
                icon: Icon(
                  Icons.pan_tool_outlined,
                  color: _mode == TakeoffMode.view ? Colors.blue : null,
                ),
                onPressed: () => _setMode(TakeoffMode.view),
              ),
              IconButton(
                tooltip: 'Calibrate',
                icon: Icon(
                  Icons.straighten,
                  color: _mode == TakeoffMode.calibrate ? Colors.blue : null,
                ),
                onPressed: () => _setMode(TakeoffMode.calibrate),
              ),
              IconButton(
                tooltip: 'Measure length',
                icon: Icon(
                  Icons.timeline,
                  color:
                      _mode == TakeoffMode.measureLength ? Colors.blue : null,
                ),
                onPressed: () async {
                  final ok = await _ensureActiveMeasurementItem();
                  if (!ok) return;

                  final unit = _activeUnit ?? '';
                  final isBeamComposite = _isBeamCompositeActive;

                  if (isBeamComposite) {
                    // for composite beam rebar we don’t care about unit here; we always store kg
                    _setMode(TakeoffMode.measureLength);
                    return;
                  }
                },
              ),
              IconButton(
                tooltip: 'Measure area / composite',
                icon: Icon(
                  Icons.crop_square,
                  color: _mode == TakeoffMode.measureArea ? Colors.blue : null,
                ),
                onPressed: () async {
                  final ok = await _ensureActiveMeasurementItem();
                  if (!ok) return;

                  final unit = _activeUnit ?? '';
                  final mt = _activeMeasureType ?? '';

                  final bool isSlabRebar = mt == 'slabRebar';
                  final bool isFootingComposite = mt == 'compositeFooting';
                  final bool isSlabComposite = mt == 'compositeSlab';
                  final bool isStairComposite = mt == 'compositeStair';
                  final bool isRampComposite = mt == 'compositeRamp';
                  // final bool isBeamComposite = mt == 'compositeBeam';
                  // final bool isStairComposite = mt == 'compositeRamp';

                  if (isSlabRebar) {
                    // Slab rebar → usually kg / tonne / m2
                    if (unit != 'kg' && unit != 'tonne' && unit != 'm2') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'For slab rebar use unit kg, tonne or m² before measuring area.',
                          ),
                        ),
                      );
                      return;
                    }
                    _setMode(TakeoffMode.measureArea);
                  } else if (isFootingComposite) {
                    // Footing composite: we compute m³, m², kg inside the composite dialog
                    _setMode(TakeoffMode.measureArea);
                  } else if (isSlabComposite) {
                    // Slab composite: we compute m³, m², kg inside the composite dialog
                    _setMode(TakeoffMode.measureArea);
                  } else if (isStairComposite) {
                    // Footing composite: we compute m³, m², kg inside the composite dialog
                    _setMode(TakeoffMode.measureArea);
                  } else if (isRampComposite) {
                    // Slab composite: we compute m³, m², kg inside the composite dialog
                    _setMode(TakeoffMode.measureArea);
                  } else {
                    // Normal floors/tiling/finishes → must be m²
                    if (unit != 'm2') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Set unit to m² for floor/area before measuring.',
                          ),
                        ),
                      );
                      return;
                    }
                    _setMode(TakeoffMode.measureArea);
                  }
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // Status bar
              Container(
                width: double.infinity,
                color:
                    calibrated ? Colors.green.shade50 : Colors.orange.shade50,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            calibrated
                                ? Icons.check_circle
                                : Icons.error_outline,
                            size: 18,
                            color: calibrated ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              calibrated
                                  ? (scaleText.isNotEmpty
                                      ? scaleText
                                      : 'Drawing calibrated')
                                  : 'Not calibrated. Choose a known distance in Calibrate mode.',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // _buildMeasuringItemBar(),
                    MeasuringItemBar(
                      drawingId: widget.drawingId,
                      measurementsRef: _measurementsRef,
                      activeMeasureType: _activeMeasureType,
                      onMeasureTypeChanged: (type) {
                        setState(() {
                          _activeMeasureType = type;

                          // optional: clear item-specific config when you switch type
                          _activePresetKey = null;
                          _activeLabel = null;
                          _activeBoqCode = null;
                          _activeUnit = null;
                          _activeHeightM = null;
                        });
                      },
                      onConfigurePressed: _showMeasurementItemDialog,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream:
                      _measurementsRef
                          .where('drawingId', isEqualTo: widget.drawingId)
                          .orderBy('createdAt', descending: false)
                          .stateSnapshots(),
                  builder: (ctx, measSnap) {
                    if (measSnap.hasError) {
                      return Center(
                        child: Text(
                          'Error loading measurements:\n${measSnap.error}',
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    final segments = <MeasuredSegment>[];
                    final savedAreas = <SavedArea>[];

                    final slabCompositeDocsBySlabId =
                        <
                          String,
                          List<QueryDocumentSnapshot<Map<String, dynamic>>>
                        >{};
                    final footingCompositeDocsByGroupId =
                        <
                          String,
                          List<QueryDocumentSnapshot<Map<String, dynamic>>>
                        >{};
                    final rebarSlabDocsBySlabId =
                        <
                          String,
                          List<QueryDocumentSnapshot<Map<String, dynamic>>>
                        >{};
                    final rebarFootingDocsByGroupId =
                        <
                          String,
                          List<QueryDocumentSnapshot<Map<String, dynamic>>>
                        >{};

                    // 👇 NEW
                    final beamCompositeDocsByBeamId =
                        <
                          String,
                          List<QueryDocumentSnapshot<Map<String, dynamic>>>
                        >{};

                    if (measSnap.hasData) {
                      for (final d in measSnap.data!.docs) {
                        final m = d.data();
                        final type = (m['type'] ?? 'length') as String;
                        final colorInt =
                            (m['color'] ?? Colors.blue.value) as int;
                        final color = Color(colorInt);

                        // -------- LINE-BASED MEASUREMENTS --------
                        final isBeamLine =
                            type == 'beamConcrete' ||
                            type == 'beamFormworkSide' ||
                            type == 'beamFormworkSoffit';

                        if (type == 'length' || isBeamLine) {
                          // get P1/P2
                          final p1Map = (m['p1'] ?? {}) as Map<String, dynamic>;
                          final p2Map = (m['p2'] ?? {}) as Map<String, dynamic>;

                          final p1 = Offset(
                            (p1Map['x'] ?? 0).toDouble(),
                            (p1Map['y'] ?? 0).toDouble(),
                          );
                          final p2 = Offset(
                            (p2Map['x'] ?? 0).toDouble(),
                            (p2Map['y'] ?? 0).toDouble(),
                          );

                          final measureType =
                              (m['measureType'] ?? '') as String;
                          final unitStr = (m['unit'] ?? '') as String;
                          final valueNum = m['value'];
                          final double? lengthValue =
                              (valueNum is num) ? valueNum.toDouble() : null;

                          String? lengthLabel;
                          String? beamId;

                          if (measureType == 'compositeBeam') {
                            beamId = (m['beamId'] ?? d.id) as String;
                            final beamLength = (m['beamLengthM'] ?? 0) as num;
                            final beamLenM =
                                beamLength.toDouble() > 0
                                    ? beamLength.toDouble()
                                    : lengthValue ?? 0.0;

                            final unitForLabel =
                                (unitStr.isEmpty || unitStr == 'm')
                                    ? 'm'
                                    : unitStr;
                            lengthLabel =
                                '${beamLenM.toStringAsFixed(3)} $unitForLabel';

                            // group all beam docs by beamId
                            beamCompositeDocsByBeamId
                                .putIfAbsent(beamId, () => [])
                                .add(d);
                          }

                          // segments.add(
                          //   MeasuredSegment(
                          //     id: beamId ?? d.id,
                          //     p1: p1,
                          //     p2: p2,
                          //     color: color,
                          //     label: lengthLabel,
                          //     measureType:
                          //         measureType, // 👈 extend MeasuredSegment to hold this
                          //   ),
                          // );
                        } else {
                          // -------- POLYGON-BASED MEASUREMENTS (unchanged, your slab/footing logic) --------
                          // ...
                        }
                      }
                    }

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // 🔹 Only the drawing + lines/polygons are inside InteractiveViewer
                        InteractiveViewer(
                          transformationController: _transformController,
                          minScale: 0.5,
                          maxScale: 6.0, // a bit more zoom is usually helpful
                          clipBehavior: Clip.none,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Drawing image (hi-quality)
                              Positioned.fill(
                                child: RepaintBoundary(
                                  child: Image.network(
                                    widget.imageUrl,
                                    fit: BoxFit.contain,
                                    filterQuality:
                                        FilterQuality
                                            .high, // 👈 sharper when zoomed
                                    isAntiAlias: true, // 👈 smoother edges/text
                                  ),
                                ),
                              ),

                              // Tap handling layer (for calibrate / measure / delete)
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTapDown: (details) {
                                    final imagePos = details.localPosition;
                                    _onImageTap(
                                      imagePos,
                                      data,
                                      segments,
                                      savedAreas,
                                      slabCompositeDocsBySlabId,
                                      footingCompositeDocsByGroupId,
                                      rebarSlabDocsBySlabId,
                                      rebarFootingDocsByGroupId,
                                      beamCompositeDocsByBeamId,
                                    );
                                  },
                                ),
                              ),

                              // Calibration preview (red)
                              // IgnorePointer(
                              //   ignoring: true,
                              //   child: CustomPaint(
                              //     painter: PointsPainter(
                              //       p1: _calibP1,
                              //       p2: _calibP2,
                              //       color: Colors.red,
                              //     ),
                              //   ),
                              // ),

                              // Saved polygons (areas)
                              // IgnorePointer(
                              //   ignoring: true,
                              //   child: CustomPaint(
                              //     painter: SavedAreasPainter(areas: savedAreas),
                              //   ),
                              // ),

                              // Saved segments + current temp line
                              // IgnorePointer(
                              //   ignoring: true,
                              //   child: CustomPaint(
                              //     painter: SegmentsPainter(
                              //       segments: segments,
                              //       tempP1: _lengthP1,
                              //       tempP2: _lengthP2,
                              //       tempColor: _currentColor,
                              //       selectedSegmentId: _selectedSegmentId,
                              //     ),
                              //   ),
                              // ),

                              // Live area polygon being drawn
                              IgnorePointer(
                                ignoring: true,
                                child: CustomPaint(
                                  painter: AreaPainter(
                                    points: _areaPoints,
                                    color: Colors.orange,
                                    zoomScale: 0.0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 🔹 Floating measurement preview card – OUTSIDE InteractiveViewer
                        if (_previewVisible)
                          Positioned(
                            left: _previewOffset.dx,
                            top: _previewOffset.dy,
                            child: GestureDetector(
                              onPanUpdate: (details) {
                                setState(() {
                                  _previewOffset += details.delta;
                                });
                              },
                              child: _buildPreviewCard(context),
                            ),
                          ),

                        // 🔹 Active item summary panel – also OUTSIDE InteractiveViewer
                        ActiveItemSummaryPanel(
                          drawingId: widget.drawingId,
                          measurementsRef: _measurementsRef,
                          activeMeasureType: _activeMeasureType,
                          activeLabel: _activeLabel,
                          activeBoqCode: _activeBoqCode,
                          activeUnit: _activeUnit,
                        ),
                        if (_isCompositeBusy)
                          Container(
                            color: Colors.black38,
                            child: const Center(
                              child: SizedBox(
                                width: 100,
                                height: 100,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 6,
                                  backgroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        if (_isBusy)
                          Container(
                            color: Colors.black26,
                            child: SizedBox(
                              width: 100,
                              height: 100,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 6,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onImageTap(
    Offset imagePos,
    Map<String, dynamic> drawingData,
    List<MeasuredSegment> segments,
    List<SavedArea> areas,
    Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    slabCompositeDocsBySlabId,
    Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    footingCompositeDocsByGroupId,
    Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    rebarSlabDocsBySlabId,
    Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    rebarFootingDocsByGroupId,
    Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    beamCompositeDocsByBeamId, // 👈 NEW
  ) {
    if (_mode == TakeoffMode.view) {
      // 1) try polygon composites (slab/footing/rebar)
      final handledAreas = _handleCompositeAreaTap(
        imagePos,
        areas,
        slabCompositeDocsBySlabId,
        footingCompositeDocsByGroupId,
        rebarSlabDocsBySlabId,
        rebarFootingDocsByGroupId,
      );
      if (handledAreas) return;

      // 2) try beam composites
      final handledBeam = _handleCompositeBeamTap(
        imagePos,
        segments,
        beamCompositeDocsByBeamId,
      );
      if (handledBeam) return;
    }

    // other modes as before...
    if (_mode == TakeoffMode.calibrate) {
      // _handleCalibrateTap(imagePos, drawingData);
    } else if (_mode == TakeoffMode.measureLength) {
      // _handleLengthTap(imagePos, drawingData);
    } else if (_mode == TakeoffMode.measureArea) {
      _handleAreaTap(imagePos, drawingData);
    } else if (_mode == TakeoffMode.editSegment) {
      _handleSegmentTap(imagePos, segments);
    }
  }

  Future<void> _undoLast() async {
    if (_lengthP1 != null && _lengthP2 == null) {
      setState(() {
        _lengthP1 = null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cancelled current measurement')),
      );
      return;
    }

    final snap =
        await _measurementsRef
            .where('drawingId', isEqualTo: widget.drawingId)
            .where('type', isEqualTo: 'length')
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();

    if (snap.docs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No measurement to undo')));
      return;
    }

    await snap.docs.first.reference.delete();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Removed last measurement')));
  }

  Widget _buildPreviewCard(BuildContext context) {
    final unit = _activeUnit ?? 'm';
    final unitDisplay =
        unit == 'm2'
            ? 'm²'
            : unit == 'm3'
            ? 'm³'
            : unit;

    final label = _activeLabel ?? '';
    final boq = _activeBoqCode ?? '';
    final isWalling = _isWallingActive;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Card(
        color: Colors.amber,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.drag_indicator, size: 18),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Measurement preview',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _previewVisible = false;
                      });
                    },
                    child: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (label.isNotEmpty || boq.isNotEmpty)
                Text(
                  '${label.isNotEmpty ? label : ''} '
                  '${boq.isNotEmpty ? '[$boq]' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text(
                    'Unit: ',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  Text(unitDisplay, style: const TextStyle(fontSize: 12)),
                ],
              ),
              const SizedBox(height: 2),
              if (_previewLengthMeters != null)
                Row(
                  children: [
                    const Text(
                      'L: ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${_previewLengthMeters!.toStringAsFixed(3)} m',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    const Text(
                      'Not calibrated ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '(px = ${_previewPixelDistanceBase?.toStringAsFixed(1) ?? '-'} )',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              if (unit == 'm2' && isWalling) ...[
                const SizedBox(height: 4),
                const Text(
                  'Height (h, m):',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _previewHeightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      final hVal = double.tryParse(value.trim());
                      setState(() {
                        _previewHeightM = hVal;
                        _recomputePreviewQuantity();
                      });
                    },
                  ),
                ),
              ],
              if (_previewQuantity != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text(
                      'Qty: ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${_previewQuantity!.toStringAsFixed(3)} $unitDisplay',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                    ),
                    onPressed: () {
                      setState(() {
                        _previewVisible = false;
                      });
                    },
                    child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                    ),
                    onPressed: () async {
                      final unit = _activeUnit ?? 'm';
                      final isWalling = _isWallingActive;
                      double? heightForThis;

                      if (unit == 'm2' && isWalling) {
                        final hVal = double.tryParse(
                          _previewHeightController.text.trim(),
                        );
                        if (hVal == null || hVal <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a valid height.'),
                            ),
                          );
                          return;
                        }
                        heightForThis = hVal;
                        setState(() {
                          _activeHeightM = hVal;
                        });
                      }

                      if (_previewP1 != null && _previewP2 != null) {
                        await _saveMeasurement(
                          p1: _previewP1!,
                          p2: _previewP2!,
                          lengthMeters: _previewLengthMeters,
                          overrideHeightM: heightForThis,
                        );
                      }

                      if (!mounted) return;
                      setState(() {
                        _previewVisible = false;
                      });
                    },
                    child: const Text('Save', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMeasurementItemDialog() async {
    // final selection = await _takeoffController.showMeasurementItemDialog(
    //   context,
    //   currentLabel: _activeLabel,
    //   currentUnit: _activeUnit,
    //   currentBoqCode: _activeBoqCode,
    //   currentHeightM: _activeHeightM,
    // );

    // if (selection == null) return;

    // setState(() {
    //   _activeLabel = selection.label;
    //   _activeBoqCode = selection.boqCode;
    //   _activeUnit = selection.unit;
    //   _activeHeightM = selection.wallHeightM;
    //   _activeMeasureType = selection.measureType;
    // });
  }

  Future<void> _saveRebarSlabMeasurement({
    required RebarMark mark,
    required String markRawString, // 👈 NEW
    required double clearSpanM,
    required double embedEachEndM,
    required double extraLengthM,
    required double barLengthM,
    required double totalLengthM,
    required double unitWeightKgPerM,
    required double totalWeightKg,
    required Offset p1,
    required Offset p2,
    List<Map<String, double>>? polygon, // 👈 for slab polygons
    String? slabId, // 👈 group multiple sets
    String? direction, // 👈 'horizontal' / 'vertical'
  }) async {
    if (_activeBoqCode == null || _activeBoqCode!.trim().isEmpty) return;

    final unit = _activeUnit ?? 'kg';
    final value =
        (unit == 'kg' || unit == 'tonne') ? totalWeightKg : totalLengthM;

    await _measurementsRef.add({
      'projectId': widget.projectId,
      'drawingId': widget.drawingId,
      'buildingId': widget.buildingId,
      'type': 'rebarSlab',
      'measureType': 'compositeSlab',
      'label': _activeLabel,
      'boqCode': _activeBoqCode,
      'unit': unit,

      // 🔹 full raw marking exactly as typed: "38Y12-01-150B2"
      'markRaw': markRawString,

      // structured pieces
      'quantity': mark.quantity,
      'barType': mark.barType,
      'diameterMm': mark.diameterMm,
      'spacingMm': mark.spacingMm,
      'layer': mark.layer,

      'clearSpanM': clearSpanM,
      'embedEachEndM': embedEachEndM,
      'extraLengthM': extraLengthM,
      'barLengthM': barLengthM,
      'totalLengthM': totalLengthM,

      'unitWeightKgPerM': unitWeightKgPerM,
      'totalWeightKg': totalWeightKg,
      'value': value,

      'direction': direction ?? 'horizontal',

      'color': _currentColor.value,
      'p1': {'x': p1.dx, 'y': p1.dy},
      'p2': {'x': p2.dx, 'y': p2.dy},

      if (polygon != null) 'polygon': polygon,
      if (slabId != null) 'slabId': slabId,

      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _openRebarSlabFromPolygon({
    required List<Offset> polygon,
    required Map<String, dynamic> drawingData,
  }) async {
    // 1) Check calibration
    final calibrated = drawingData['calibrated'] == true;
    final pxPerUnit = (drawingData['pixelsPerUnit'] ?? 0).toDouble();

    if (!calibrated || pxPerUnit <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Drawing not calibrated – cannot compute slab spans.'),
        ),
      );
      return;
    }

    // 2) Bounding box in image coords
    double minX = polygon.first.dx;
    double maxX = polygon.first.dx;
    double minY = polygon.first.dy;
    double maxY = polygon.first.dy;

    for (final p in polygon) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    final widthPx = maxX - minX;
    final heightPx = maxY - minY;

    if (widthPx <= 0 || heightPx <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid slab polygon – zero width or height.'),
        ),
      );
      return;
    }

    // 3) Convert to meters (pxPerUnit = px per meter)
    final spanXM = widthPx / pxPerUnit;
    final spanYM = heightPx / pxPerUnit;

    final lengthM = math.max(spanXM, spanYM);
    final widthM = math.min(spanXM, spanYM);

    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;

    final polyData = polygon.map((p) => {'x': p.dx, 'y': p.dy}).toList();

    // 4) Multi-mark state
    final List<RebarSet> sets = [];

    final markController = TextEditingController();
    final embedController = TextEditingController(text: '0.30');
    final extraController = TextEditingController(text: '0.00');
    String direction = 'horizontal';
    String? errorText;

    // 👇 initial dialog position (like your other floating cards)
    Offset dialogOffset = const Offset(40, 80);

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            void addCurrentMark() {
              final raw = markController.text.trim();
              if (raw.isEmpty) {
                setStateDialog(() {
                  errorText = 'Please enter rebar mark.';
                });
                return;
              }

              final embed = double.tryParse(embedController.text.trim()) ?? 0.0;
              final extra = double.tryParse(extraController.text.trim()) ?? 0.0;

              try {
                final m = RebarMark.parse(raw);

                final clearSpanM =
                    (direction == 'horizontal') ? lengthM : widthM;

                final Lbar = clearSpanM + 2 * embed + extra;
                final Ltotal = m.quantity * Lbar;
                final uw = rebarUnitWeightKgPerM(m.diameterMm);
                final wTotal = Ltotal * uw;

                sets.add(
                  RebarSet(
                    rawMark: raw,
                    mark: m,
                    direction: direction,
                    clearSpanM: clearSpanM,
                    embedEachEndM: embed,
                    extraLengthM: extra,
                    barLengthM: Lbar,
                    totalLengthM: Ltotal,
                    unitWeightKgPerM: uw,
                    totalWeightKg: wTotal,
                  ),
                );

                markController.clear();
                setStateDialog(() {
                  errorText = null;
                });
              } catch (e) {
                setStateDialog(() {
                  errorText = e.toString();
                });
              }
            }

            // 🔹 DRAGGABLE WRAPPER
            return Stack(
              children: [
                // (optional) tap outside to cancel:
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, false),
                    child: Container(color: Colors.black.withOpacity(0.2)),
                  ),
                ),

                Positioned(
                  left: dialogOffset.dx,
                  top: dialogOffset.dy,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setStateDialog(() {
                        dialogOffset += details.delta;
                      });
                    },
                    child: Material(
                      color: Colors.transparent,
                      child: AlertDialog(
                        title: Row(
                          children: const [
                            Icon(Icons.drag_indicator, size: 18),
                            SizedBox(width: 6),
                            Text('Slab rebar (multiple marks)'),
                          ],
                        ),
                        content: SizedBox(
                          width: 420,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Slab spans: L ≈ ${lengthM.toStringAsFixed(3)} m, '
                                'W ≈ ${widthM.toStringAsFixed(3)} m',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text(
                                    'Bars lay:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: const Text('Horizontal'),
                                    selected: direction == 'horizontal',
                                    onSelected: (_) {
                                      setStateDialog(() {
                                        direction = 'horizontal';
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  ChoiceChip(
                                    label: const Text('Vertical'),
                                    selected: direction == 'vertical',
                                    onSelected: (_) {
                                      setStateDialog(() {
                                        direction = 'vertical';
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: markController,
                                decoration: const InputDecoration(
                                  labelText: 'Rebar mark (e.g. 38Y12-01-150B2)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: embedController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Embed each end (m)',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: TextField(
                                      controller: extraController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText:
                                            'Extra length (laps/hooks, m)',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              if (errorText != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  errorText!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: addCurrentMark,
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Add mark'),
                                ),
                              ),
                              const Divider(),
                              if (sets.isEmpty)
                                const Text(
                                  'No rebar marks added yet.',
                                  style: TextStyle(fontSize: 12),
                                )
                              else
                                SizedBox(
                                  height: 140,
                                  child: ListView.builder(
                                    itemCount: sets.length,
                                    itemBuilder: (ctx, i) {
                                      final s = sets[i];
                                      return ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(
                                          '${s.rawMark} '
                                          '(${s.direction == "horizontal" ? "Horizontal" : "Vertical"})',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        subtitle: Text(
                                          'L/bar: ${s.barLengthM.toStringAsFixed(3)} m, '
                                          'Total: ${s.totalLengthM!.toStringAsFixed(3)} m, '
                                          'Wt: ${s.totalWeightKg!.toStringAsFixed(1)} kg',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        trailing: IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            setStateDialog(() {
                                              sets.removeAt(i);
                                            });
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed:
                                sets.isEmpty
                                    ? null
                                    : () => Navigator.pop(ctx, true),
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true || sets.isEmpty) return;

    // 5) Save all marks under one slabId
    final slabId = _measurementsRef.doc().id;

    for (final s in sets) {
      final Offset p1;
      final Offset p2;

      if (s.direction == 'horizontal') {
        p1 = Offset(minX, centerY);
        p2 = Offset(maxX, centerY);
      } else {
        p1 = Offset(centerX, minY);
        p2 = Offset(centerX, maxY);
      }

      await _saveRebarSlabMeasurement(
        mark: s.mark,
        markRawString: s.rawMark,
        clearSpanM: s.clearSpanM,
        embedEachEndM: s.embedEachEndM,
        extraLengthM: s.extraLengthM,
        barLengthM: s.barLengthM,
        totalLengthM: s.totalLengthM!,
        unitWeightKgPerM: s.unitWeightKgPerM,
        totalWeightKg: s.totalWeightKg!,
        p1: p1,
        p2: p2,
        polygon: polyData,
        slabId: slabId,
        direction: s.direction,
      );
    }
  }

  Future<void> _openFootingCompositeFromPolygon({
    required List<Offset> polygon,
    required Map<String, dynamic> drawingData,
  }) async {
    if (polygon.length < 3) return;

    // 1) Get bounding box + centre in image coordinates
    double minX = polygon.first.dx;
    double maxX = polygon.first.dx;
    double minY = polygon.first.dy;
    double maxY = polygon.first.dy;

    for (final p in polygon) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;

    // 2) Convert to meters using calibration
    final Lm = distanceInMeters(
      Offset(minX, centerY),
      Offset(maxX, centerY),
      drawingData,
    ); // length
    final Bm = distanceInMeters(
      Offset(centerX, minY),
      Offset(centerX, maxY),
      drawingData,
    ); // width

    if (Lm == null || Bm == null || Lm <= 0 || Bm <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Drawing not calibrated – cannot compute footing length/width.',
          ),
        ),
      );
      return;
    }

    final polyData = polygon.map((p) => {'x': p.dx, 'y': p.dy}).toList();

    // 3) Dialog state
    final thicknessController = TextEditingController(text: '0.30'); // m
    final qtyFootingsController = TextEditingController(text: '1');

    // BOQ codes for each component
    final boqConcreteController = TextEditingController(
      text: _activeBoqCode ?? '',
    );
    final boqFormworkController = TextEditingController();
    final boqRebarController = TextEditingController();

    final embedController = TextEditingController(
      text: '0.30',
    ); // embed each end
    final extraController = TextEditingController(text: '0.00');

    final markController = TextEditingController();
    String rebarDirection = 'horizontal'; // or 'along width'

    String? errorText;
    final List<RebarSet> sets = []; // from your slab rebar code

    bool parseOkDouble(String text) => double.tryParse(text.trim()) != null;

    bool validateMainInputs() {
      if (!parseOkDouble(thicknessController.text)) {
        errorText = 'Enter footing thickness (m).';
        return false;
      }
      if (int.tryParse(qtyFootingsController.text.trim()) == null) {
        errorText = 'Enter number of identical footings.';
        return false;
      }
      return true;
    }

    void addCurrentRebarMark(StateSetter setStateDialog) {
      final raw = markController.text.trim();
      if (raw.isEmpty) {
        setStateDialog(() {
          errorText = 'Please enter a rebar mark.';
        });
        return;
      }
      final embed = double.tryParse(embedController.text.trim()) ?? 0.0;
      final extra = double.tryParse(extraController.text.trim()) ?? 0.0;

      try {
        final m = RebarMark.parse(raw);

        // choose which physical span to use
        final clearSpanM = rebarDirection == 'horizontal' ? Lm : Bm;

        final Lbar = clearSpanM + 2 * embed + extra;
        final Ltotal = m.quantity * Lbar;
        final uw = rebarUnitWeightKgPerM(m.diameterMm);
        final wTotal = Ltotal * uw;

        sets.add(
          RebarSet(
            rawMark: raw,
            mark: m,
            direction: rebarDirection,
            clearSpanM: clearSpanM,
            embedEachEndM: embed,
            extraLengthM: extra,
            barLengthM: Lbar,
            totalLengthM: Ltotal,
            unitWeightKgPerM: uw,
            totalWeightKg: wTotal,
          ),
        );

        markController.clear();
        // don't clear embed/extra – often same for several marks

        setStateDialog(() {
          errorText = null;
        });
      } catch (e) {
        setStateDialog(() {
          errorText = e.toString();
        });
      }
    }

    final bool ok =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return StatefulBuilder(
              builder: (ctx, setStateDialog) {
                // live preview
                final thicknessM =
                    double.tryParse(thicknessController.text.trim()) ?? 0.0;
                final nFootings =
                    int.tryParse(qtyFootingsController.text.trim()) ?? 1;

                final concretePerFooting =
                    thicknessM > 0 ? Lm * Bm * thicknessM : 0.0;
                final concreteTotal = concretePerFooting * nFootings;

                final perimeter = 2 * (Lm + Bm);
                final formworkPerFooting =
                    thicknessM > 0
                        ? perimeter * thicknessM
                        : 0.0; // shutter to full depth
                final formworkTotal = formworkPerFooting * nFootings;

                double totalRebarLenOne = 0.0;
                double totalRebarKgOne = 0.0;
                for (final s in sets) {
                  totalRebarLenOne += s.totalLengthM!;
                  totalRebarKgOne += s.totalWeightKg!;
                }
                final totalRebarLenAll = totalRebarLenOne * nFootings;
                final totalRebarKgAll = totalRebarKgOne * nFootings;

                return AlertDialog(
                  title: const Text(
                    'Footing composite (Concrete + Formwork + Rebar)',
                  ),
                  content: SizedBox(
                    width: 460,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Footing plan size: '
                            'L ≈ ${Lm.toStringAsFixed(3)} m, '
                            'B ≈ ${Bm.toStringAsFixed(3)} m',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: thicknessController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Thickness (m)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                  onChanged: (_) => setStateDialog(() {}),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextField(
                                  controller: qtyFootingsController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'No. of footings',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                  onChanged: (_) => setStateDialog(() {}),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'BOQ mappings:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: boqConcreteController,
                            decoration: const InputDecoration(
                              labelText: 'Concrete BOQ code (m³)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: boqFormworkController,
                            decoration: const InputDecoration(
                              labelText: 'Formwork BOQ code (m²)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: boqRebarController,
                            decoration: const InputDecoration(
                              labelText: 'Rebar BOQ code (kg)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),

                          const SizedBox(height: 12),
                          const Divider(),
                          const Text(
                            'Rebar marks for this footing:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Text(
                                'Bars along:',
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('Length'),
                                selected: rebarDirection == 'vertical',
                                onSelected: (_) {
                                  setStateDialog(() {
                                    rebarDirection = 'vertical';
                                  });
                                },
                              ),
                              const SizedBox(width: 4),
                              ChoiceChip(
                                label: const Text('Width'),
                                selected: rebarDirection == 'horizontal',
                                onSelected: (_) {
                                  setStateDialog(() {
                                    rebarDirection = 'horizontal';
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: markController,
                            decoration: const InputDecoration(
                              labelText: 'Rebar mark (e.g. 12Y16-01-150B1)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: embedController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Embed each end (m)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: TextField(
                                  controller: extraController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Extra length (laps/hooks, m)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed:
                                  () => addCurrentRebarMark(setStateDialog),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add rebar mark'),
                            ),
                          ),
                          if (errorText != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              errorText!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          const Divider(),
                          if (sets.isEmpty)
                            const Text(
                              'No rebar marks added yet.',
                              style: TextStyle(fontSize: 11),
                            )
                          else
                            SizedBox(
                              height: 130,
                              child: ListView.builder(
                                itemCount: sets.length,
                                itemBuilder: (ctx, i) {
                                  final s = sets[i];
                                  return ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      '${s.rawMark} (${s.direction})',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    subtitle: Text(
                                      'L/bar: ${s.barLengthM.toStringAsFixed(3)} m, '
                                      'Total/ftg: ${s.totalLengthM!.toStringAsFixed(3)} m, '
                                      'Wt/ftg: ${s.totalWeightKg!.toStringAsFixed(2)} kg',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        setStateDialog(() {
                                          sets.removeAt(i);
                                        });
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),

                          const SizedBox(height: 8),
                          const Divider(),
                          const Text(
                            'Preview (all footings):',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Concrete: '
                            '${concretePerFooting.toStringAsFixed(3)} m³/ftg  '
                            '→ ${concreteTotal.toStringAsFixed(3)} m³ total',
                            style: const TextStyle(fontSize: 11),
                          ),
                          Text(
                            'Formwork: '
                            '${formworkPerFooting.toStringAsFixed(3)} m²/ftg  '
                            '→ ${formworkTotal.toStringAsFixed(3)} m² total',
                            style: const TextStyle(fontSize: 11),
                          ),
                          Text(
                            'Rebar length: '
                            '${totalRebarLenOne.toStringAsFixed(3)} m/ftg  '
                            '→ ${totalRebarLenAll.toStringAsFixed(3)} m total',
                            style: const TextStyle(fontSize: 11),
                          ),
                          Text(
                            'Rebar weight: '
                            '${totalRebarKgOne.toStringAsFixed(2)} kg/ftg  '
                            '→ ${totalRebarKgAll.toStringAsFixed(2)} kg total',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        if (!validateMainInputs()) {
                          setStateDialog(() {});
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                      child: const Text('Save'),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        false;

    if (!ok) return;

    // 4) Final calculations & Firestore persistence
    final thicknessM = double.tryParse(thicknessController.text.trim()) ?? 0.0;
    final nFootings = int.tryParse(qtyFootingsController.text.trim()) ?? 1;

    final concretePerFooting = thicknessM > 0 ? Lm * Bm * thicknessM : 0.0;
    final concreteTotal = concretePerFooting * nFootings;

    final perimeter = 2 * (Lm + Bm);
    final formworkPerFooting = thicknessM > 0 ? perimeter * thicknessM : 0.0;
    final formworkTotal = formworkPerFooting * nFootings;

    double totalRebarLenOne = 0.0;
    double totalRebarKgOne = 0.0;
    for (final s in sets) {
      totalRebarLenOne += s.totalLengthM!;
      totalRebarKgOne += s.totalWeightKg!;
    }
    final totalRebarLenAll = totalRebarLenOne * nFootings;
    final totalRebarKgAll = totalRebarKgOne * nFootings;

    final boqConcrete = boqConcreteController.text.trim();
    final boqFormwork = boqFormworkController.text.trim();
    final boqRebar = boqRebarController.text.trim();

    final footingGroupId = _measurementsRef.doc().id;

    // Concrete doc
    if (concreteTotal > 0 && boqConcrete.isNotEmpty) {
      await _measurementsRef.add({
        'projectId': widget.projectId,
        'drawingId': widget.drawingId,
        'buildingId': widget.buildingId,
        'type': 'footingConcrete',
        'measureType': 'compositeFooting',
        'unit': 'm3',
        'value': concreteTotal,
        'valuePerFooting': concretePerFooting,
        'nFootings': nFootings,
        'lengthM': Lm,
        'widthM': Bm,
        'thicknessM': thicknessM,
        'label': '${_activeLabel ?? 'Footing'} - Concrete',
        'boqCode': boqConcrete,
        'color': _currentColor.value,
        'polygon': polyData,
        'footingGroupId': footingGroupId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // Formwork doc
    if (formworkTotal > 0 && boqFormwork.isNotEmpty) {
      await _measurementsRef.add({
        'projectId': widget.projectId,
        'drawingId': widget.drawingId,
        'buildingId': widget.buildingId,
        'type': 'footingFormwork',
        'measureType': 'compositeFooting',
        'unit': 'm2',
        'value': formworkTotal,
        'valuePerFooting': formworkPerFooting,
        'nFootings': nFootings,
        'lengthM': Lm,
        'widthM': Bm,
        'thicknessM': thicknessM,
        'perimeterM': perimeter,
        'label': '${_activeLabel ?? 'Footing'} - Formwork',
        'boqCode': boqFormwork,
        'color': _currentColor.value,
        'polygon': polyData,
        'footingGroupId': footingGroupId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // Rebar docs – one per mark
    if (boqRebar.isNotEmpty && sets.isNotEmpty) {
      for (final s in sets) {
        final totalLenAllFootings = s.totalLengthM! * nFootings;
        final totalWtAllFootings = s.totalWeightKg! * nFootings;

        await _measurementsRef.add({
          'projectId': widget.projectId,
          'buildingId': widget.buildingId,
          'drawingId': widget.drawingId,
          'type': 'rebarFooting',
          'measureType': 'compositeFooting',
          'unit': 'kg',
          'value': totalWtAllFootings,
          'lengthAllFootingsM': totalLenAllFootings,
          'weightAllFootingsKg': totalWtAllFootings,
          'lengthPerFootingM': s.totalLengthM,
          'weightPerFootingKg': s.totalWeightKg,
          'clearSpanM': s.clearSpanM,
          'embedEachEndM': s.embedEachEndM,
          'extraLengthM': s.extraLengthM,
          'barLengthM': s.barLengthM,
          'barsPerFooting': s.mark.quantity,
          'nFootings': nFootings,
          'rawMark': s.rawMark,
          'diameterMm': s.mark.diameterMm,
          'direction': s.direction,
          'label': '${_activeLabel ?? 'Footing'} - Rebar',
          'boqCode': boqRebar,
          'color': _currentColor.value,
          'polygon': polyData,
          'footingGroupId': footingGroupId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Footing composite (C+F+R) measurement saved.'),
      ),
    );
  }

  Future<void> _showEditRebarFootingMarkDialog(
    DocumentReference docRef,
    Map<String, dynamic> data,
  ) async {
    double _asDouble(dynamic v) => v is num ? v.toDouble() : 0.0;
    int _asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);

    final existingMark = (data['rawMark'] ?? data['markRaw'] ?? '') as String;
    final existingDirection = (data['direction'] ?? 'horizontal') as String;
    final boqCode = (data['boqCode'] ?? '') as String;
    final diaMm = _asInt(data['diameterMm'] ?? data['rebarDiameterMm']);
    final nFootings = _asInt(data['nFootings'] ?? data['footingCount'] ?? 1);
    final existingClearSpan = _asDouble(data['clearSpanM']);
    final existingEmbed = _asDouble(data['embedEachEndM']);
    final existingExtra = _asDouble(data['extraLengthM']);

    final markController = TextEditingController(text: existingMark);
    final boqController = TextEditingController(text: boqCode);
    final clearSpanController = TextEditingController(
      text: existingClearSpan.toStringAsFixed(3),
    );
    final embedController = TextEditingController(
      text: existingEmbed.toStringAsFixed(3),
    );
    final extraController = TextEditingController(
      text: existingExtra.toStringAsFixed(3),
    );

    String direction = existingDirection; // 'horizontal' / 'vertical'
    String? errorText;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Edit footing rebar mark'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Dia: Ø$diaMm   Footings: $nFootings',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: markController,
                      decoration: const InputDecoration(
                        labelText: 'Rebar mark (e.g. 38Y12-01-150B2)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: boqController,
                      decoration: const InputDecoration(
                        labelText: 'BoQ Code (e.g. 3.9)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          'Bars lay:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Horizontal'),
                          selected: direction == 'horizontal',
                          onSelected: (_) {
                            setStateDialog(() {
                              direction = 'horizontal';
                            });
                          },
                        ),
                        const SizedBox(width: 4),
                        ChoiceChip(
                          label: const Text('Vertical'),
                          selected: direction == 'vertical',
                          onSelected: (_) {
                            setStateDialog(() {
                              direction = 'vertical';
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: clearSpanController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Clear span (m)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: embedController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Embed each end (m)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 190,
                        child: TextField(
                          controller: extraController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Extra length (laps/hooks, m)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        errorText!,
                        style: const TextStyle(fontSize: 11, color: Colors.red),
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
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;

    // ---- validate & recompute ----
    final raw = markController.text.trim();
    final boq = boqController.text.trim();
    final clearSpanM = double.tryParse(clearSpanController.text.trim()) ?? 0.0;
    final embed = double.tryParse(embedController.text.trim()) ?? 0.0;
    final extra = double.tryParse(extraController.text.trim()) ?? 0.0;

    if (raw.isEmpty || clearSpanM <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter valid mark and clear span.'),
        ),
      );
      return;
    }

    try {
      // parse mark – will give quantity + diameter + (optionally spacing/layer)
      final mark = RebarMark.parse(raw);

      final barsPerFooting = mark.quantity;
      final barLengthM = clearSpanM + 2 * embed + extra;
      final lengthPerFootingM = barsPerFooting * barLengthM;
      final lengthAllFootingsM = lengthPerFootingM * nFootings;

      final uw = rebarUnitWeightKgPerM(mark.diameterMm);
      final weightPerFootingKg = lengthPerFootingM * uw;
      final weightAllFootingsKg = lengthAllFootingsM * uw;

      await docRef.update({
        // key BOQ fields
        'rawMark': raw,
        'diameterMm': mark.diameterMm,
        'barsPerFooting': barsPerFooting,
        'direction': direction,
        'boqCode': boq,

        // geometry
        'clearSpanM': clearSpanM,
        'embedEachEndM': embed,
        'extraLengthM': extra,
        'barLengthM': barLengthM,

        // totals
        'lengthPerFootingM': lengthPerFootingM,
        'lengthAllFootingsM': lengthAllFootingsM,
        'weightPerFootingKg': weightPerFootingKg,
        'weightAllFootingsKg': weightAllFootingsKg,

        // main value for this doc (used by ActiveItemSummaryPanel)
        'value': weightAllFootingsKg,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to parse mark: $e')));
      return;
    }
  }

  Future<void> _showAddRebarFootingMarkDialog(
    String footingGroupId,
    Map<String, dynamic> baseData,
  ) async {
    // double _asDouble(dynamic v) => v is num ? v.toDouble() : 0.0;
    int _asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);

    // Common fields from any existing footing doc in this group
    final projectId = baseData['projectId'] as String?;
    final buildingId = baseData['buildingId'] as String?;
    final drawingId = baseData['drawingId'] as String?;
    final nFootings = _asInt(
      baseData['nFootings'] ?? baseData['footingCount'] ?? 1,
    );
    final baseColor = (baseData['color'] ?? Colors.blue.value) as int;
    final defaultBoq = (baseData['boqCode'] ?? '') as String;

    // Polygon for drawing the area + for p1/p2 line
    final polyList = (baseData['polygon'] ?? []) as List<dynamic>;
    final points = <Offset>[];
    for (final p in polyList) {
      if (p is Map<String, dynamic>) {
        points.add(Offset((p['x'] ?? 0).toDouble(), (p['y'] ?? 0).toDouble()));
      }
    }

    // Compute bounding box for representative line
    double minX = points.isNotEmpty ? points.first.dx : 0.0;
    double maxX = minX;
    double minY = points.isNotEmpty ? points.first.dy : 0.0;
    double maxY = minY;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;

    // --- Dialog controllers ---
    final markController = TextEditingController(); // new mark
    final clearSpanController = TextEditingController(); // clear span (m)
    final embedController = TextEditingController(text: '0.30');
    final extraController = TextEditingController(text: '0.00');
    final boqController = TextEditingController(text: defaultBoq);

    String direction = 'horizontal'; // or 'vertical'
    String? errorText;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Add footing rebar mark'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Footings in this group: $nFootings',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: markController,
                      decoration: const InputDecoration(
                        labelText: 'Rebar mark (e.g. 38Y12-01-150B2)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          'Bars lay:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Horizontal'),
                          selected: direction == 'horizontal',
                          onSelected: (_) {
                            setStateDialog(() {
                              direction = 'horizontal';
                            });
                          },
                        ),
                        const SizedBox(width: 4),
                        ChoiceChip(
                          label: const Text('Vertical'),
                          selected: direction == 'vertical',
                          onSelected: (_) {
                            setStateDialog(() {
                              direction = 'vertical';
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: clearSpanController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Clear span (m)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: embedController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Embed each end (m)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 190,
                        child: TextField(
                          controller: extraController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Extra length (laps/hooks, m)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: boqController,
                      decoration: const InputDecoration(
                        labelText: 'BOQ code for this rebar',
                        helperText: 'e.g. 3.14(i)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        errorText!,
                        style: const TextStyle(fontSize: 11, color: Colors.red),
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
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;

    final raw = markController.text.trim();
    final clearSpanM = double.tryParse(clearSpanController.text.trim()) ?? 0.0;
    final embed = double.tryParse(embedController.text.trim()) ?? 0.0;
    final extra = double.tryParse(extraController.text.trim()) ?? 0.0;
    final boqCode = boqController.text.trim();

    if (raw.isEmpty || clearSpanM <= 0 || boqCode.isEmpty) {
      print(boqCode);
      print(raw);
      print(clearSpanM);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter valid mark, span and BOQ code.'),
        ),
      );
      return;
    }

    try {
      // Parse the mark → quantity, diameter, etc.
      final mark = RebarMark.parse(raw);

      final barsPerFooting = mark.quantity;
      final barLengthM = clearSpanM + 2 * embed + extra;
      final lengthPerFootingM = barsPerFooting * barLengthM;
      final lengthAllFootingsM = lengthPerFootingM * nFootings;

      final uw = rebarUnitWeightKgPerM(mark.diameterMm);
      final weightPerFootingKg = lengthPerFootingM * uw;
      final weightAllFootingsKg = lengthAllFootingsM * uw;

      // Representative line inside polygon depending on direction
      final Offset p1;
      final Offset p2;
      if (direction == 'horizontal') {
        p1 = Offset(minX, centerY);
        p2 = Offset(maxX, centerY);
      } else {
        p1 = Offset(centerX, minY);
        p2 = Offset(centerX, maxY);
      }

      // Save new rebarFooting doc
      await _measurementsRef.add({
        'projectId': projectId,
        'drawingId': drawingId,
        'buildingId': buildingId,
        'type': 'rebarFooting',
        'measureType': 'compositeFooting',
        'unit': 'kg',
        'value': weightAllFootingsKg,

        'lengthPerFootingM': lengthPerFootingM,
        'lengthAllFootingsM': lengthAllFootingsM,
        'weightPerFootingKg': weightPerFootingKg,
        'weightAllFootingsKg': weightAllFootingsKg,

        'clearSpanM': clearSpanM,
        'embedEachEndM': embed,
        'extraLengthM': extra,
        'barLengthM': barLengthM,

        'barsPerFooting': barsPerFooting,
        'nFootings': nFootings,

        'rawMark': raw,
        'diameterMm': mark.diameterMm,
        'direction': direction,

        'boqCode': boqCode,
        'label': '${_activeLabel ?? 'Footing'} - Rebar',

        'polygon': polyList,
        'p1': {'x': p1.dx, 'y': p1.dy},
        'p2': {'x': p2.dx, 'y': p2.dy},
        'footingGroupId': footingGroupId,
        'color': baseColor,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to parse rebar mark: $e')));
    }
  }

  Future<void> _showSlabCompositeDetailsDialog(
    String slabId,
    List<QueryDocumentSnapshot> docs,
  ) async {
    if (docs.isEmpty) return;

    // We'll mutate this list as we delete/add marks
    List<QueryDocumentSnapshot> localDocs = List.of(docs);

    double _asDouble(dynamic v) => v is num ? v.toDouble() : 0.0;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            if (localDocs.isEmpty) {
              return AlertDialog(
                title: const Text('Slab composite details'),
                content: const Text('No data remains for this slab.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              );
            }

            // ---- Classify docs by type ----
            Map<String, dynamic>? concData;
            Map<String, dynamic>? soffitData;
            Map<String, dynamic>? edgeData;
            final List<QueryDocumentSnapshot> rebarDocs = [];

            for (final d in localDocs) {
              final m = d.data() as Map<String, dynamic>;
              final type = (m['type'] ?? '') as String;

              if (type == 'slabConcrete') {
                concData = m;
              } else if (type == 'slabFormworkSoffit') {
                soffitData = m;
              } else if (type == 'slabFormworkEdge') {
                edgeData = m;
              } else if (type == 'rebarSlab') {
                rebarDocs.add(d);
              }
            }

            // ---- Basic geometry (from concrete if available, otherwise first doc) ----
            final baseData =
                concData ?? (localDocs.first.data() as Map<String, dynamic>);

            final lengthM = _asDouble(baseData['lengthM']);
            final widthM = _asDouble(baseData['widthM']);
            final areaM2 = _asDouble(baseData['areaM2']);

            // ---- Concrete summary ----
            final double concM3 = _asDouble(
              concData?['value'],
            ); // we stored 'value' = volume
            final String boqConc = (concData?['boqCode'] ?? '') as String;

            // ---- Soffit summary ----
            final double soffitM2 = _asDouble(soffitData?['value']);
            final String boqSoffit = (soffitData?['boqCode'] ?? '') as String;

            // ---- Edge summary ----
            final double edgeM2 = _asDouble(edgeData?['value']);
            final String boqEdge = (edgeData?['boqCode'] ?? '') as String;

            // ---- Rebar summary ----
            double totalRebarLengthM = 0.0;
            double totalRebarWeightKg = 0.0;
            for (final d in rebarDocs) {
              final m = d.data() as Map<String, dynamic>;
              totalRebarLengthM += _asDouble(m['totalLengthAllBarsM']);
              // in your schema: 'value' == totalWeightKg
              totalRebarWeightKg += _asDouble(m['totalWeightKg'] ?? m['value']);
            }

            // Helper to reload docs after add/edit/delete
            Future<void> _reloadDocs() async {
              final snap =
                  await _measurementsRef
                      .where('drawingId', isEqualTo: widget.drawingId)
                      .where('slabId', isEqualTo: slabId)
                      .get();
              setStateDialog(() {
                localDocs = snap.docs;
              });
            }

            return AlertDialog(
              title: const Text('Slab composite details'),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ---- Geometry ----
                      Text(
                        'Geometry',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'L ≈ ${lengthM.toStringAsFixed(3)} m, '
                        'W ≈ ${widthM.toStringAsFixed(3)} m, '
                        'Area ≈ ${areaM2.toStringAsFixed(3)} m²',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      const Divider(),

                      // ---- Concrete / formwork summary with BOQ ----
                      Text(
                        'Concrete & formwork (BOQ)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (concData != null)
                        Text(
                          'Concrete: ${concM3.toStringAsFixed(3)} m³'
                          '${boqConc.isNotEmpty ? '  (BOQ $boqConc)' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      if (soffitData != null)
                        Text(
                          'Formwork – soffit: ${soffitM2.toStringAsFixed(3)} m²'
                          '${boqSoffit.isNotEmpty ? '  (BOQ $boqSoffit)' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      if (edgeData != null)
                        Text(
                          'Formwork – edge: ${edgeM2.toStringAsFixed(3)} m²'
                          '${boqEdge.isNotEmpty ? '  (BOQ $boqEdge)' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      if (concData == null &&
                          soffitData == null &&
                          edgeData == null)
                        const Text(
                          'No concrete/formwork data for this slab.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      const SizedBox(height: 8),
                      const Divider(),

                      // ---- Rebar summary + Add button ----
                      Row(
                        children: [
                          Text(
                            'Rebar marks',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () async {
                              await _addOrEditSlabRebarMark(
                                slabId: slabId,
                                baseData: baseData,
                                dialogContext: ctx,
                                existingDoc: null,
                              );
                              await _reloadDocs();
                            },
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add rebar mark'),
                          ),
                        ],
                      ),
                      if (rebarDocs.isNotEmpty) ...[
                        Text(
                          'Total rebar length: '
                          '${totalRebarLengthM.toStringAsFixed(3)} m',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'Total rebar weight: '
                          '${totalRebarWeightKg.toStringAsFixed(2)} kg',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ] else
                        const Text(
                          'No rebar marks for this slab.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      const SizedBox(height: 6),

                      if (rebarDocs.isNotEmpty)
                        SizedBox(
                          height: 220,
                          child: ListView.builder(
                            itemCount: rebarDocs.length,
                            itemBuilder: (ctxList, i) {
                              final d = rebarDocs[i];
                              final data = d.data() as Map<String, dynamic>;

                              final markRaw = (data['rawMark'] ?? '') as String;
                              final diaMm = (data['diameterMm'] ?? 0) as int;
                              final barsCount = (data['barsCount'] ?? 0) as int;
                              final direction =
                                  (data['direction'] ?? '') as String;
                              final boqRebar =
                                  (data['boqCode'] ?? '') as String;

                              final clearSpanM = _asDouble(data['clearSpanM']);
                              final embedM = _asDouble(data['embedEachEndM']);
                              final extraM = _asDouble(data['extraLengthM']);
                              final barLengthM = _asDouble(data['barLengthM']);
                              final totalLenM = _asDouble(
                                data['totalLengthAllBarsM'],
                              );
                              final totalWtKg = _asDouble(
                                data['totalWeightKg'] ?? data['value'],
                              );

                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  markRaw.isNotEmpty
                                      ? markRaw
                                      : 'Rebar Ø$diaMm',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (boqRebar.isNotEmpty)
                                      Text(
                                        'BOQ: $boqRebar',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    if (direction.isNotEmpty)
                                      Text(
                                        'Direction: $direction',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    Text(
                                      'Ø$diaMm, bars: $barsCount',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    Text(
                                      'Clear span: ${clearSpanM.toStringAsFixed(3)} m, '
                                      'embed: ${embedM.toStringAsFixed(3)} m, '
                                      'extra: ${extraM.toStringAsFixed(3)} m',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    Text(
                                      'L/bar: ${barLengthM.toStringAsFixed(3)} m',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    Text(
                                      'Total L: ${totalLenM.toStringAsFixed(3)} m, '
                                      'Wt: ${totalWtKg.toStringAsFixed(2)} kg',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 18),
                                      tooltip: 'Edit rebar mark',
                                      onPressed: () async {
                                        await _addOrEditSlabRebarMark(
                                          slabId: slabId,
                                          baseData: baseData,
                                          dialogContext: ctx,
                                          existingDoc: d,
                                        );
                                        await _reloadDocs();
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                      ),
                                      tooltip: 'Delete rebar mark',
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: ctx,
                                          builder: (ctx2) {
                                            return AlertDialog(
                                              title: const Text(
                                                'Delete rebar mark?',
                                              ),
                                              content: Text(
                                                'Delete "$markRaw" from this slab?',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed:
                                                      () => Navigator.pop(
                                                        ctx2,
                                                        false,
                                                      ),
                                                  child: const Text('Cancel'),
                                                ),
                                                FilledButton(
                                                  onPressed:
                                                      () => Navigator.pop(
                                                        ctx2,
                                                        true,
                                                      ),
                                                  child: const Text('Delete'),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                        if (confirm == true) {
                                          await _measurementsRef
                                              .doc(d.id)
                                              .delete();
                                          await _reloadDocs();
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _handleCompositeAreaTap(
    Offset imagePos,
    List<SavedArea> areas,
    Map<String, List<QueryDocumentSnapshot>> slabCompositeDocsBySlabId,
    Map<String, List<QueryDocumentSnapshot>> footingCompositeDocsByGroupId,
    Map<String, List<QueryDocumentSnapshot>> rebarSlabDocsBySlabId,
    Map<String, List<QueryDocumentSnapshot>> rebarFootingDocsByGroupId,
  ) {
    for (final a in areas) {
      // Only consider polygons that the tap is inside
      if (!_pointInPolygon(imagePos, a.points)) continue;

      // 1) Suspended slab composite (concrete + formwork + rebar)
      if (a.isSlabComposite) {
        final docs = slabCompositeDocsBySlabId[a.id] ?? const [];
        if (docs.isEmpty) return true; // swallow tap
        _showSlabCompositeDetailsDialog(a.id, docs);
        return true;
      }

      // 2) Footing composite (concrete + formwork + rebar)
      if (a.isFootingComposite) {
        final docs = footingCompositeDocsByGroupId[a.id] ?? const [];
        if (docs.isEmpty) return true;
        // _showFootingCompositeDetailsDialog(a.id, docs);
        return true;
      }

      // 3) Old rebar-only slab polygons (if you still use them)
      if (a.isRebarSlab) {
        final docs = rebarSlabDocsBySlabId[a.id] ?? const [];
        if (docs.isEmpty) return true;
        _showRebarSlabDetailsDialog(a.id, docs);
        return true;
      }

      // 4) Old rebar-only footing groups
      if (a.isRebarFooting) {
        final docs = rebarFootingDocsByGroupId[a.id] ?? const [];
        if (docs.isEmpty) return true;
        _showRebarFootingDetailsDialog(a.id, docs);
        return true;
      }
    }
    return false;
  }

  Future<void> _addOrEditSlabRebarMark({
    required String slabId,
    required Map<String, dynamic> baseData,
    required BuildContext dialogContext,
    QueryDocumentSnapshot? existingDoc,
  }) async {
    double _asDouble(dynamic v) => v is num ? v.toDouble() : 0.0;

    // We assume baseData contains lengthM & widthM (from slabConcrete) OR at least areaBox
    final lengthM = _asDouble(baseData['lengthM']);
    final widthM = _asDouble(baseData['widthM']);

    // polygon + color + label reused from baseData
    final List<dynamic> polyList = (baseData['polygon'] ?? []) as List<dynamic>;
    final polyData =
        polyList
            .whereType<Map<String, dynamic>>()
            .map((p) => {'x': p['x'], 'y': p['y']})
            .toList();

    final int colorInt = (baseData['color'] ?? Colors.blue.value) as int;
    final Color color = Color(colorInt);

    final String baseLabel = (baseData['label'] ?? 'Slab - Rebar') as String;

    // --- Controllers & initial values ---
    final markController = TextEditingController();
    final embedController = TextEditingController(text: '0.30');
    final extraController = TextEditingController(text: '0.00');
    final boqController = TextEditingController();

    String direction = 'along length'; // or 'along width'
    String? errorText;

    if (existingDoc != null) {
      final data = existingDoc.data() as Map<String, dynamic>;
      markController.text = (data['rawMark'] ?? '') as String;
      embedController.text = _asDouble(
        data['embedEachEndM'],
      ).toStringAsFixed(3);
      extraController.text = _asDouble(data['extraLengthM']).toStringAsFixed(3);
      direction = (data['direction'] ?? 'along length') as String;
      boqController.text = (data['boqCode'] ?? '') as String;
    }

    final ok = await showDialog<bool>(
      context: dialogContext,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: Text(
                existingDoc == null
                    ? 'Add slab rebar mark'
                    : 'Edit slab rebar mark',
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: markController,
                        decoration: const InputDecoration(
                          labelText: 'Rebar mark (e.g. 38Y12-01-150B2)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text(
                            'Bars run:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(
                              'Along length (L ≈ ${lengthM.toStringAsFixed(2)}m)',
                            ),
                            selected: direction == 'along length',
                            onSelected: (_) {
                              setStateDialog(() {
                                direction = 'along length';
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const SizedBox(width: 55), // align chips
                          ChoiceChip(
                            label: Text(
                              'Along width (W ≈ ${widthM.toStringAsFixed(2)}m)',
                            ),
                            selected: direction == 'along width',
                            onSelected: (_) {
                              setStateDialog(() {
                                direction = 'along width';
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: embedController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Embed each end (m)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: extraController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Extra length (laps/hooks, m)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: boqController,
                        decoration: const InputDecoration(
                          labelText: 'BOQ code for this rebar mark',
                          border: OutlineInputBorder(),
                          isDense: true,
                          helperText: 'e.g. 3.12(ii)',
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          errorText!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final raw = markController.text.trim();
                    if (raw.isEmpty) {
                      setStateDialog(() {
                        errorText = 'Please enter rebar mark.';
                      });
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;

    // ---- Calculate lengths / weight ----
    final rawMark = markController.text.trim();
    final embed = double.tryParse(embedController.text.trim()) ?? 0.0;
    final extra = double.tryParse(extraController.text.trim()) ?? 0.0;
    final boqRebar = boqController.text.trim();

    try {
      final m = RebarMark.parse(rawMark);

      final clearSpanM = (direction == 'along length') ? lengthM : widthM;
      final Lbar = clearSpanM + 2 * embed + extra;
      final totalLen = m.quantity * Lbar;
      final uw = rebarUnitWeightKgPerM(m.diameterMm);
      final totalWt = totalLen * uw;

      final now = FieldValue.serverTimestamp();

      final payload = {
        'projectId': widget.projectId,
        'drawingId': widget.drawingId,
        'slabId': slabId,
        'measureType': 'compositeSlab',
        'type': 'rebarSlab',
        'unit': 'kg',
        'value': totalWt,
        'totalLengthAllBarsM': totalLen,
        'totalWeightKg': totalWt,
        'clearSpanM': clearSpanM,
        'embedEachEndM': embed,
        'extraLengthM': extra,
        'barLengthM': Lbar,
        'rawMark': rawMark,
        'diameterMm': m.diameterMm,
        'barsCount': m.quantity,
        'direction': direction,
        'boqCode': boqRebar,
        'label': baseLabel,
        'color': color.value,
        'polygon': polyData,
        'updatedAt': now,
        if (existingDoc == null) 'createdAt': now,
      };

      if (existingDoc == null) {
        await _measurementsRef.add(payload);
      } else {
        await _measurementsRef.doc(existingDoc.id).update(payload);
      }
    } catch (e) {
      // Optional: show error as snackbar if parse fails after dialog
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving rebar mark: $e')));
    }
  }

  _completeLengthMeasurement(
    Offset p1,
    Offset p2,
    Map<String, dynamic> drawingData,
  ) {}

  Future<void> _showBeamCompositeDetailsDialog(
    String beamId,
    List<DocumentSnapshot<Map<String, dynamic>>> docs, {
    String? beamTypeLabel,
    int sameTypeCount = 0,
    double sameTypeTotalLengthM = 0.0,
  }) async {
    if (docs.isEmpty) return;

    // Local mutable copy so we can update after deletes / adds
    // List<QueryDocumentSnapshot> localDocs = List.of(docs);
    List<DocumentSnapshot<Map<String, dynamic>>> localDocs = List.of(docs);

    double _asDouble(dynamic v) => v is num ? v.toDouble() : 0.0;

    // --- helpers for rebar weight ---
    double _beamUnitWeightKgPerM(int diaMm) {
      // standard formula ~ 0.00617 * φ^2
      return 0.00617 * diaMm * diaMm;
    }

    // --- Controllers for adding a MAIN BAR SEGMENT ---
    final mainSegMarkController = TextEditingController(); // 3Y25-01
    final mainSegClearLenController =
        TextEditingController(); // clear length (m)
    final mainSegEmbedController = TextEditingController(text: '0.30');
    final mainSegExtraController = TextEditingController(text: '0.00');
    final mainSegSegmentCountController = TextEditingController(text: '1');
    final mainSegBoqController = TextEditingController();
    final mainSegNoteController =
        TextEditingController(); // optional zone / span note
    String? mainSegError;

    /// Parse a simple main bar mark like "3Y25-01"
    Map<String, dynamic> _parseBeamMainMark(String raw) {
      // Allow things like: 3Y25-01, 3y25, 4 Y16 - T1, etc.
      final pattern = RegExp(
        r'^\s*(\d+)\s*[Yy]\s*(\d+)(?:\s*-\s*([A-Za-z0-9]+))?\s*$',
      );
      final m = pattern.firstMatch(raw);
      if (m == null) {
        throw FormatException(
          'Invalid mark. Use like "3Y25-01" where 3 = bars, 25 = diameter, 01 = mark.',
        );
      }
      final qty = int.parse(m.group(1)!);
      final dia = int.parse(m.group(2)!);
      final markCode = m.group(3) ?? '';
      return {'quantity': qty, 'diameterMm': dia, 'markCode': markCode};
    }

    // ---------- INPUT CONTROLLERS / STATE FOR *ADDING* MAIN BARS ----------
    final mainMarkController = TextEditingController(); // e.g. "3Y20-T"
    final mainBoqController = TextEditingController();
    final mainEmbedController = TextEditingController(text: '0.30'); // m
    final mainExtraController = TextEditingController(text: '0.00'); // m
    final mainBarLengthController = TextEditingController(); // direct L/bar
    final mainSegmentNoteController = TextEditingController(); // optional note

    bool mainUseDirectLength =
        false; // false = compute from span + embed + extra
    String mainPosition = 'bottom'; // "top" / "bottom" / "centre" / "extra"
    String? mainError;

    // ---------- INPUT CONTROLLERS / STATE FOR *ADDING* STIRRUPS ----------
    final stirrupMarkController = TextEditingController(); // label only
    final stirrupBoqController = TextEditingController();
    final stirrupDiaController = TextEditingController(text: '10'); // mm
    final stirrupSpacingController = TextEditingController(text: '150'); // mm
    final stirrupCountController = TextEditingController(); // optional
    final stirrupCoverController = TextEditingController(text: '0.05'); // m
    final stirrupHookController = TextEditingController(
      text: '0.10',
    ); // m (each hook)

    String? stirrupError;

    print('Beam composite dialog for $beamId');

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            if (localDocs.isEmpty) {
              return AlertDialog(
                title: const Text('Beam composite details'),
                content: const Text('No items remain for this beam.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              );
            }

            // ---------- SUMMARY AGGREGATION ----------
            double beamLengthM = 0.0;
            double beamWidthM = 0.0;
            double beamDepthM = 0.0;
            bool isGroundBeam = false;

            double concreteTotalM3 = 0.0;
            double sideFormworkTotalM2 = 0.0;
            double soffitFormworkTotalM2 = 0.0;

            double mainRebarLenM = 0.0;
            double mainRebarWtKg = 0.0;
            double stirrupLenM = 0.0;
            double stirrupWtKg = 0.0;

            for (final d in localDocs) {
              final data = d.data() as Map<String, dynamic>;
              final type = (data['type'] ?? '') as String;

              // geometry
              if (beamLengthM <= 0) {
                beamLengthM = _asDouble(
                  data['beamLengthM'] ?? data['lengthM'] ?? 0,
                );
              }
              if (beamWidthM <= 0) {
                beamWidthM = _asDouble(
                  data['beamWidthM'] ?? data['widthM'] ?? 0,
                );
              }
              if (beamDepthM <= 0) {
                beamDepthM = _asDouble(
                  data['beamDepthM'] ?? data['depthM'] ?? 0,
                );
              }
              if (data['isGroundBeam'] == true) {
                isGroundBeam = true;
              }

              if (type == 'beamConcrete') {
                concreteTotalM3 += _asDouble(data['value']);
              } else if (type == 'beamFormworkSide') {
                sideFormworkTotalM2 += _asDouble(data['value']);
              } else if (type == 'beamFormworkSoffit') {
                soffitFormworkTotalM2 += _asDouble(data['value']);
              } else if (type == 'rebarBeamMain') {
                final len = _asDouble(
                  data['totalLengthAllBarsM'] ?? data['totalLengthM'] ?? 0,
                );
                final wt = _asDouble(
                  data['totalWeightKg'] ?? data['value'] ?? 0,
                );
                mainRebarLenM += len;
                mainRebarWtKg += wt;
              } else if (type == 'rebarBeamStirrups') {
                final len = _asDouble(
                  data['totalLengthAllStirrupsM'] ?? data['totalLengthM'] ?? 0,
                );
                final wt = _asDouble(
                  data['totalWeightKg'] ?? data['value'] ?? 0,
                );
                stirrupLenM += len;
                stirrupWtKg += wt;
              }
            }

            final totalRebarLenM = mainRebarLenM + stirrupLenM;
            final totalRebarWtKg = mainRebarWtKg + stirrupWtKg;

            // ---------- HELPERS TO ADD NEW REBAR DOCS ----------
            Future<void> addSegmentBarSet() async {
              try {
                final raw = mainSegMarkController.text.trim();
                if (raw.isEmpty) {
                  setStateDialog(() {
                    mainSegError = 'Enter bar mark, e.g. 3Y25-01';
                  });
                  return;
                }

                final clearLenM =
                    double.tryParse(mainSegClearLenController.text.trim()) ??
                    0.0;
                if (clearLenM <= 0) {
                  setStateDialog(() {
                    mainSegError = 'Clear length must be > 0.';
                  });
                  return;
                }

                final embedM =
                    double.tryParse(mainSegEmbedController.text.trim()) ?? 0.0;
                final extraM =
                    double.tryParse(mainSegExtraController.text.trim()) ?? 0.0;
                final segCount =
                    int.tryParse(mainSegSegmentCountController.text.trim()) ??
                    0;
                if (segCount <= 0) {
                  setStateDialog(() {
                    mainSegError = 'No. of segments must be ≥ 1.';
                  });
                  return;
                }

                final boq = mainSegBoqController.text.trim();
                if (boq.isEmpty) {
                  setStateDialog(() {
                    mainSegError =
                        'Please enter BOQ code for this bar segment.';
                  });
                  return;
                }

                final parsed = _parseBeamMainMark(raw);
                final barsPerSegment = parsed['quantity'] as int;
                final diaMm = parsed['diameterMm'] as int;
                final markCode = parsed['markCode'] as String? ?? '';

                final barLenM = clearLenM + 2 * embedM + extraM;
                final totalBars = barsPerSegment * segCount;
                final totalLengthAllBarsM = totalBars * barLenM;
                final uw = rebarUnitWeightKgPerM(diaMm);
                final totalWeightKg = totalLengthAllBarsM * uw;

                // Save to Firestore
                final docRef = _measurementsRef.doc();
                await docRef.set({
                  'projectId': widget.projectId,
                  'buildingId': widget.buildingId,
                  'drawingId': widget.drawingId,
                  'type': 'rebarBeamMain',
                  'measureType': 'compositeBeam',
                  'unit': 'kg',
                  'value': totalWeightKg,
                  'beamId': beamId,
                  'rawMark': raw,
                  'markCode': markCode,
                  'diameterMm': diaMm,
                  'barsPerSegment': barsPerSegment,
                  'segmentCount': segCount,
                  'totalBars': totalBars,
                  'clearLengthM': clearLenM,
                  'embedEachEndM': embedM,
                  'extraLengthM': extraM,
                  'barLengthM': barLenM,
                  'totalLengthAllBarsM': totalLengthAllBarsM,
                  'segmentNote': mainSegNoteController.text.trim(),
                  'boqCode': boq,
                  'createdAt': FieldValue.serverTimestamp(),
                });

                final snap = await docRef.get();

                setStateDialog(() {
                  localDocs.add(snap);
                  mainSegMarkController.clear();
                  mainSegClearLenController.clear();
                  mainSegSegmentCountController.text = '1';
                  mainSegBoqController.clear();
                  mainSegNoteController.clear();
                  mainSegError = null;
                });
              } catch (e) {
                setStateDialog(() {
                  mainSegError = e.toString();
                });
              }
            }

            Future<void> addMainBarSet() async {
              setStateDialog(() {
                mainError = null;
              });

              final raw = mainMarkController.text.trim();
              final boq = mainBoqController.text.trim();
              if (raw.isEmpty) {
                setStateDialog(() {
                  mainError = 'Please enter main bar mark (e.g. 3Y20-T).';
                });
                return;
              }
              if (boq.isEmpty) {
                setStateDialog(() {
                  mainError = 'Please enter BOQ code for main bars.';
                });
                return;
              }
              if (beamLengthM <= 0) {
                setStateDialog(() {
                  mainError =
                      'Beam length is 0 – re-open dialog after measuring beam.';
                });
                return;
              }

              // Parse mark using your existing RebarMark utility.
              RebarMark mark;
              try {
                mark = RebarMark.parse(raw);
              } catch (e) {
                setStateDialog(() {
                  mainError = 'Cannot parse rebar mark: $e';
                });
                return;
              }

              final qty = mark.quantity;
              final dia = mark.diameterMm;

              double Lbar;
              if (mainUseDirectLength) {
                final LbarVal =
                    double.tryParse(mainBarLengthController.text.trim()) ?? 0.0;
                if (LbarVal <= 0) {
                  setStateDialog(() {
                    mainError = 'Enter a positive bar length (m).';
                  });
                  return;
                }
                Lbar = LbarVal;
              } else {
                final embed =
                    double.tryParse(mainEmbedController.text.trim()) ?? 0.0;
                final extra =
                    double.tryParse(mainExtraController.text.trim()) ?? 0.0;
                Lbar = beamLengthM + 2 * embed + extra;
              }

              final Ltotal = qty * Lbar;
              final uw = _beamUnitWeightKgPerM(dia);
              final Wtotal = Ltotal * uw;

              final docRef = _measurementsRef.doc();
              await docRef.set({
                'projectId': widget.projectId,
                'buildingId': widget.buildingId,
                'drawingId': widget.drawingId,
                'beamId': beamId,
                'type': 'rebarBeamMain',
                'measureType': 'compositeBeam',
                'unit': 'kg',
                'value': Wtotal, // used in summary as fallback
                'rawMark': raw,
                'diameterMm': dia,
                'barsCount': qty,
                'position': mainPosition, // top/bottom/centre/extra
                'segmentNote': mainSegmentNoteController.text.trim(),
                'beamLengthM': beamLengthM,
                'clearSpanM': beamLengthM,
                'embedEachEndM':
                    mainUseDirectLength
                        ? null
                        : double.tryParse(mainEmbedController.text.trim()) ??
                            0.0,
                'extraLengthM':
                    mainUseDirectLength
                        ? null
                        : double.tryParse(mainExtraController.text.trim()) ??
                            0.0,
                'barLengthM': Lbar,
                'totalLengthAllBarsM': Ltotal,
                'totalWeightKg': Wtotal,
                'unitWeightKgPerM': uw,
                'boqCode': boq,
                'color': _currentColor.value,
                'source': mainUseDirectLength ? 'bbs' : 'drawing',
                'createdAt': FieldValue.serverTimestamp(),
              });

              final snap = await docRef.get();
              setStateDialog(() {
                localDocs.add(snap);
                mainMarkController.clear();
                mainBoqController.clear();
                mainBarLengthController.clear();
                mainSegmentNoteController.clear();
                mainError = null;
              });
            }

            Future<void> addStirrupsSet() async {
              setStateDialog(() {
                stirrupError = null;
              });

              final raw = stirrupMarkController.text.trim();
              final boq = stirrupBoqController.text.trim();
              if (raw.isEmpty) {
                setStateDialog(() {
                  stirrupError = 'Please enter stirrup mark/label.';
                });
                return;
              }
              if (boq.isEmpty) {
                setStateDialog(() {
                  stirrupError = 'Please enter BOQ code for stirrups.';
                });
                return;
              }
              if (beamLengthM <= 0 || beamWidthM <= 0 || beamDepthM <= 0) {
                setStateDialog(() {
                  stirrupError =
                      'Beam geometry missing – re-open dialog after measuring beam.';
                });
                return;
              }

              final dia =
                  int.tryParse(stirrupDiaController.text.trim()) ?? 0; // mm
              if (dia <= 0) {
                setStateDialog(() {
                  stirrupError = 'Enter stirrup diameter in mm.';
                });
                return;
              }

              final spacingMm = int.tryParse(
                stirrupSpacingController.text.trim(),
              );
              int nStirrups =
                  int.tryParse(stirrupCountController.text.trim()) ?? 0;

              if (nStirrups <= 0 && spacingMm != null && spacingMm > 0) {
                final spacingM = spacingMm / 1000.0;
                // approximate: one at each end + intermediate
                nStirrups = (beamLengthM / spacingM).ceil() + 1;
              }

              if (nStirrups <= 0) {
                setStateDialog(() {
                  stirrupError =
                      'Provide either spacing or number of stirrups (or both).';
                });
                return;
              }

              final cover =
                  double.tryParse(stirrupCoverController.text.trim()) ?? 0.05;
              final hook =
                  double.tryParse(stirrupHookController.text.trim()) ?? 0.10;

              // internal dimensions minus cover each side
              final bInner = (beamWidthM - 2 * cover).clamp(
                0.0,
                double.infinity,
              );
              final hInner = (beamDepthM - 2 * cover).clamp(
                0.0,
                double.infinity,
              );

              final perimeterPerStirrupM = 2 * (bInner + hInner) + 2 * hook;
              final totalLength = nStirrups * perimeterPerStirrupM;
              final uw = _beamUnitWeightKgPerM(dia);
              final totalWeight = totalLength * uw;

              final docRef = _measurementsRef.doc();
              await docRef.set({
                'projectId': widget.projectId,
                'buildingId': widget.buildingId,
                'drawingId': widget.drawingId,
                'beamId': beamId,
                'type': 'rebarBeamStirrups',
                'measureType': 'compositeBeam',
                'unit': 'kg',
                'value': totalWeight, // fallback weight
                'rawMark': raw,
                'diameterMm': dia,
                'spacingMm': spacingMm,
                'nStirrups': nStirrups,
                'coverM': cover,
                'hookLengthM': hook,
                'perimeterPerStirrupM': perimeterPerStirrupM,
                'totalLengthAllStirrupsM': totalLength,
                'totalWeightKg': totalWeight,
                'unitWeightKgPerM': uw,
                'boqCode': boq,
                'color': _currentColor.value,
                'source': 'drawing',
                'createdAt': FieldValue.serverTimestamp(),
              });

              final snap = await docRef.get();
              setStateDialog(() {
                localDocs.add(snap);
                stirrupMarkController.clear();
                stirrupBoqController.clear();
                // keep spacing / dia / cover defaults for next span
                stirrupCountController.clear();
                stirrupError = null;
              });
            }

            return AlertDialog(
              title: const Text('Beam composite details'),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ---------- SUMMARY ----------
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Beam ID: $beamId',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          if (beamTypeLabel != null && beamTypeLabel.isNotEmpty)
                            Text(
                              'Beam type: $beamTypeLabel',
                              style: const TextStyle(fontSize: 12),
                            ),

                          // 👇 NEW repeated-type summary
                          if (sameTypeCount > 0) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Same type beams in this drawing: $sameTypeCount',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'Total length (all $beamTypeLabel): '
                              '${sameTypeTotalLengthM.toStringAsFixed(3)} m',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                          if (beamLengthM > 0)
                            Text(
                              'Length ≈ ${beamLengthM.toStringAsFixed(3)} m',
                              style: const TextStyle(fontSize: 12),
                            ),
                          if (beamWidthM > 0 && beamDepthM > 0)
                            Text(
                              'Section ≈ ${beamWidthM.toStringAsFixed(3)} m × '
                              '${beamDepthM.toStringAsFixed(3)} m',
                              style: const TextStyle(fontSize: 12),
                            ),
                          if (isGroundBeam)
                            const Text(
                              'Ground beam (no soffit formwork)',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blueGrey,
                              ),
                            ),
                          const SizedBox(height: 4),
                          if (concreteTotalM3 > 0)
                            Text(
                              'Concrete: ${concreteTotalM3.toStringAsFixed(3)} m³',
                              style: const TextStyle(fontSize: 12),
                            ),
                          if (sideFormworkTotalM2 > 0)
                            Text(
                              'Formwork – sides: '
                              '${sideFormworkTotalM2.toStringAsFixed(3)} m²',
                              style: const TextStyle(fontSize: 12),
                            ),
                          if (!isGroundBeam && soffitFormworkTotalM2 > 0)
                            Text(
                              'Formwork – soffit: '
                              '${soffitFormworkTotalM2.toStringAsFixed(3)} m²',
                              style: const TextStyle(fontSize: 12),
                            ),
                          if (totalRebarWtKg > 0) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Rebar (total): ${totalRebarWtKg.toStringAsFixed(2)} kg',
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (totalRebarLenM > 0)
                              Text(
                                'Rebar length: ${totalRebarLenM.toStringAsFixed(3)} m',
                                style: const TextStyle(fontSize: 12),
                              ),
                            const Text(
                              'Beam mark / ID (from drawing):',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),
                    const Divider(),

                    // ---------- ADD MAIN BAR SET ----------
                    Container(
                      height: 500,
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Add main bar set',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blueGrey.shade800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: mainMarkController,
                              decoration: const InputDecoration(
                                labelText: 'Main bar mark (e.g. 3Y20-T)',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: mainPosition,
                                    decoration: const InputDecoration(
                                      labelText: 'Position',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'top',
                                        child: Text('Top'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'bottom',
                                        child: Text('Bottom'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'centre',
                                        child: Text('Centre'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'extra',
                                        child: Text('Extra'),
                                      ),
                                    ],
                                    onChanged: (v) {
                                      if (v == null) return;
                                      setStateDialog(() {
                                        mainPosition = v;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextField(
                                    controller: mainBoqController,
                                    decoration: const InputDecoration(
                                      labelText: 'BOQ (main bars)',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Switch(
                                  value: mainUseDirectLength,
                                  onChanged: (v) {
                                    setStateDialog(() {
                                      mainUseDirectLength = v;
                                    });
                                  },
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    mainUseDirectLength
                                        ? 'Use direct bar length (from schedule)'
                                        : 'Compute L/bar from span + embed + extra',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            if (!mainUseDirectLength) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: mainEmbedController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Embed each end (m)',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: TextField(
                                      controller: mainExtraController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Extra length (m)',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              TextField(
                                controller: mainBarLengthController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Bar length (m)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            TextField(
                              controller: mainSegmentNoteController,
                              decoration: const InputDecoration(
                                labelText: 'Segment / note (optional)',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                            if (mainError != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                mainError!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add main set'),
                                onPressed: addMainBarSet,
                              ),
                            ),

                            const Divider(),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Add main bar segment',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: mainSegMarkController,
                                    decoration: const InputDecoration(
                                      labelText: 'Mark (e.g. 3Y25-01)',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: mainSegClearLenController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Clear length (m)',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: mainSegEmbedController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Embed each end (m)',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: mainSegExtraController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Extra length (m)',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: mainSegSegmentCountController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'No. of segments',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: mainSegBoqController,
                                    decoration: const InputDecoration(
                                      labelText: 'BOQ code',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: mainSegNoteController,
                              decoration: const InputDecoration(
                                labelText: 'Zone / note (optional)',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                            if (mainSegError != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                mainSegError!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Add segment bars'),
                                onPressed: addSegmentBarSet,
                              ),
                            ),
                            const Divider(),

                            // ---------- ADD STIRRUPS SET ----------
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Add stirrups set',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blueGrey.shade800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: stirrupMarkController,
                              decoration: const InputDecoration(
                                labelText:
                                    'Stirrups mark / label (e.g. R10-150)',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: stirrupDiaController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: false,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Ø (mm)',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextField(
                                    controller: stirrupSpacingController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: false,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Spacing (mm)',
                                      helperText: 'Optional if count given',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextField(
                                    controller: stirrupCountController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: false,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'No. of stirrups',
                                      helperText: 'Optional – will use spacing',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: stirrupCoverController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Cover (m)',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextField(
                                    controller: stirrupHookController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Hook length each (m)',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextField(
                                    controller: stirrupBoqController,
                                    decoration: const InputDecoration(
                                      labelText: 'BOQ (stirrups)',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (stirrupError != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                stirrupError!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add stirrups set'),
                                onPressed: addStirrupsSet,
                              ),
                            ),
                            SizedBox(
                              height: 220,
                              child: ListView.builder(
                                itemCount: localDocs.length,
                                itemBuilder: (ctx, i) {
                                  final d = localDocs[i];
                                  final data = d.data() as Map<String, dynamic>;
                                  final type = (data['type'] ?? '') as String;
                                  final label = (data['label'] ?? '') as String;
                                  final boq = (data['boqCode'] ?? '') as String;
                                  final unit = (data['unit'] ?? '') as String;
                                  final value = _asDouble(data['value']);

                                  Widget subtitle;

                                  if (type == 'beamConcrete') {
                                    subtitle = Text(
                                      'Concrete: ${value.toStringAsFixed(3)} m³'
                                      '${boq.isNotEmpty ? '  (BOQ: $boq)' : ''}',
                                      style: const TextStyle(fontSize: 11),
                                    );
                                  } else if (type == 'beamFormworkSide') {
                                    final areaM2 = _asDouble(data['value']);
                                    subtitle = Text(
                                      'Formwork – sides: '
                                      '${areaM2.toStringAsFixed(3)} m²'
                                      '${boq.isNotEmpty ? '  (BOQ: $boq)' : ''}',
                                      style: const TextStyle(fontSize: 11),
                                    );
                                  } else if (type == 'beamFormworkSoffit') {
                                    final areaM2 = _asDouble(data['value']);
                                    subtitle = Text(
                                      'Formwork – soffit: '
                                      '${areaM2.toStringAsFixed(3)} m²'
                                      '${boq.isNotEmpty ? '  (BOQ: $boq)' : ''}',
                                      style: const TextStyle(fontSize: 11),
                                    );
                                  } else if (type == 'rebarBeamMain') {
                                    final markRaw =
                                        (data['rawMark'] ?? '') as String;
                                    final dia =
                                        data['diameterMm'] ?? data['diaMm'];
                                    final barsCount =
                                        (data['barsCount'] ??
                                                data['quantity'] ??
                                                0)
                                            as int;
                                    final pos =
                                        (data['position'] ?? '') as String;
                                    final lenAll = _asDouble(
                                      data['totalLengthAllBarsM'] ??
                                          data['totalLengthM'],
                                    );
                                    final wtAll = _asDouble(
                                      data['totalWeightKg'] ?? value,
                                    );
                                    final segNote =
                                        (data['segmentNote'] ?? '') as String?;

                                    subtitle = Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          markRaw.isNotEmpty
                                              ? markRaw
                                              : 'Main rebar Ø$dia',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          'Bars: $barsCount'
                                          '${pos.isNotEmpty ? ', pos: $pos' : ''}',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        Text(
                                          'L: ${lenAll.toStringAsFixed(3)} m, '
                                          'Wt: ${wtAll.toStringAsFixed(2)} kg',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        if (segNote != null &&
                                            segNote.isNotEmpty)
                                          Text(
                                            'Segment: $segNote',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        if (boq.isNotEmpty)
                                          Text(
                                            'BOQ: $boq',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                            ),
                                          ),
                                      ],
                                    );
                                  } else if (type == 'rebarBeamMainSegment') {
                                    final raw =
                                        (data['rawMark'] ?? '').toString();
                                    final dia = data['diameterMm'];
                                    final segCount =
                                        (data['segmentCount'] ?? 0).toString();
                                    final clear = _asDouble(
                                      data['clearLengthM'],
                                    );
                                    final barL = _asDouble(data['barLengthM']);
                                    final wt = _asDouble(
                                      data['totalWeightKg'] ?? data['value'],
                                    );

                                    subtitle = Text(
                                      '$raw Ø$dia | seg=$segCount | clear=${clear.toStringAsFixed(2)}m | '
                                      'L/bar=${barL.toStringAsFixed(2)}m | Wt=${wt.toStringAsFixed(2)}kg'
                                      '${boq.isNotEmpty ? ' (BOQ $boq)' : ''}',
                                      style: const TextStyle(fontSize: 11),
                                    );
                                  } else if (type == 'rebarBeamStirrups') {
                                    final markRaw =
                                        (data['rawMark'] ?? '') as String;
                                    final dia =
                                        data['diameterMm'] ?? data['diaMm'];
                                    final spacingMm = data['spacingMm'];
                                    final nStirrups =
                                        (data['nStirrups'] ??
                                                data['stirrupCount'] ??
                                                0)
                                            as int;
                                    final lenAll = _asDouble(
                                      data['totalLengthAllStirrupsM'] ??
                                          data['totalLengthM'],
                                    );
                                    final wtAll = _asDouble(
                                      data['totalWeightKg'] ?? value,
                                    );

                                    subtitle = Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          markRaw.isNotEmpty
                                              ? markRaw
                                              : 'Stirrups Ø$dia',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          'Rings: $nStirrups'
                                          '${spacingMm != null ? ', @ ${spacingMm}mm' : ''}',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        Text(
                                          'L: ${lenAll.toStringAsFixed(3)} m, '
                                          'Wt: ${wtAll.toStringAsFixed(2)} kg',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        if (boq.isNotEmpty)
                                          Text(
                                            'BOQ: $boq',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                            ),
                                          ),
                                      ],
                                    );
                                  } else {
                                    // fallback for any unexpected type
                                    subtitle = Text(
                                      '$type: ${value.toStringAsFixed(3)} $unit'
                                      '${boq.isNotEmpty ? '  (BOQ: $boq)' : ''}',
                                      style: const TextStyle(fontSize: 11),
                                    );
                                  }

                                  final titleText =
                                      label.isNotEmpty ? label : type;
                                  final isRebarDoc =
                                      type == 'rebarBeamMain' ||
                                      type == 'rebarBeamMainSegment' ||
                                      type == 'rebarBeamStirrups';

                                  return ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      titleText,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: subtitle,
                                    trailing:
                                        isRebarDoc
                                            ? IconButton(
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                size: 18,
                                              ),
                                              onPressed: () async {
                                                final confirm = await showDialog<
                                                  bool
                                                >(
                                                  context: ctx,
                                                  builder: (ctx2) {
                                                    return AlertDialog(
                                                      title: const Text(
                                                        'Delete rebar item?',
                                                      ),
                                                      content: Text(
                                                        'Delete this rebar record from beam $beamId?',
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed:
                                                              () =>
                                                                  Navigator.pop(
                                                                    ctx2,
                                                                    false,
                                                                  ),
                                                          child: const Text(
                                                            'Cancel',
                                                          ),
                                                        ),
                                                        FilledButton(
                                                          onPressed:
                                                              () =>
                                                                  Navigator.pop(
                                                                    ctx2,
                                                                    true,
                                                                  ),
                                                          child: const Text(
                                                            'Delete',
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                );

                                                if (confirm == true) {
                                                  await _measurementsRef
                                                      .doc(d.id)
                                                      .delete();
                                                  setStateDialog(() {
                                                    localDocs.removeAt(i);
                                                  });
                                                }
                                              },
                                            )
                                            : null,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Divider(),

                    // ---------- LIST OF EXISTING DOCS ----------
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _resetLength() {
    setState(() {
      _lengthP1 = null;
      _lengthP2 = null;
      _selectedSegmentId = null; // if you use this
    });
  }

  // bool _handleCompositeBeamTap(
  //   Offset imagePos,
  //   List<MeasuredSegment> segments,
  //   Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  //   beamCompositeDocsByBeamId,
  // ) {
  //   // find closest compositeBeam segment
  //   const maxHitDist = 12.0;
  //   MeasuredSegment? best;
  //   double bestDist = maxHitDist;

  //   for (final s in segments) {
  //     if (s.measureType != 'compositeBeam') continue;

  //     final d = _distancePointToSegment(imagePos, s.p1, s.p2);
  //     if (d < bestDist) {
  //       bestDist = d;
  //       best = s;
  //     }
  //   }

  //   if (best == null) return false;

  //   final docs = beamCompositeDocsByBeamId[best.id] ?? const [];
  //   if (docs.isEmpty) return true;

  //   _openBeamTypeSummaryAndDetails(best.id, docs); // async fire-and-forget
  //   return true;
  // }

  bool _handleCompositeBeamTap(
    Offset imagePos,
    List<MeasuredSegment> segments,
    Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    beamCompositeDocsByBeamId,
  ) {
    const maxHitDist = 12.0;
    MeasuredSegment? best;
    double bestDist = maxHitDist;

    for (final s in segments) {
      if (s.measureType != 'compositeBeam') continue;

      final d = _distancePointToSegment(imagePos, s.p1, s.p2);
      if (d < bestDist) {
        bestDist = d;
        best = s;
      }
    }

    if (best == null) return false;

    final beamId = best.id;

    // ✅ get docs (maybe too many), then FILTER to this beamId
    final rawDocs = beamCompositeDocsByBeamId[beamId] ?? const [];
    final docs =
        rawDocs.where((d) {
          final data = d.data();
          final id = (data['beamId'] ?? '').toString().trim();
          return id == beamId;
        }).toList();

    // If map keying was wrong and returned empty after filtering,
    // you can decide to return true (handled tap) or false.
    if (docs.isEmpty) return true;

    // ✅ open dialog safely (no fire-and-forget errors)
    unawaited(_openBeamTypeSummaryAndDetails(beamId, docs));
    return true;
  }

  Future<void> _openBeamTypeSummaryAndDetails(
    String beamId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (docs.isEmpty) return;

    // 1) beamType
    final firstData = docs.first.data();
    final beamType =
        (firstData['beamType'] ?? firstData['label'] ?? '').toString().trim();

    int sameTypeCount = 0;
    double sameTypeTotalLenM = 0.0;

    if (beamType.isNotEmpty) {
      final snap =
          await _measurementsRef
              .where('drawingId', isEqualTo: widget.drawingId)
              .where('measureType', isEqualTo: 'compositeBeam')
              .where('beamType', isEqualTo: beamType)
              .where(
                'type',
                isEqualTo: 'beamConcrete',
              ) // one doc per beam (ideally)
              .get();

      final seenBeamIds = <String>{};

      for (final d in snap.docs) {
        final data = d.data();
        final bId = (data['beamId'] ?? d.id).toString().trim();

        // ✅ only add length the first time we see this beamId
        if (seenBeamIds.add(bId)) {
          final lenAny = data['beamLengthM'] ?? data['lengthM'] ?? 0;
          final len = (lenAny is num) ? lenAny.toDouble() : 0.0;
          sameTypeTotalLenM += len;
        }
      }

      sameTypeCount = seenBeamIds.length;
    }

    await _showBeamCompositeDetailsDialog(
      beamId,
      docs,
      beamTypeLabel: beamType,
      sameTypeCount: sameTypeCount,
      sameTypeTotalLengthM: sameTypeTotalLenM,
    );
  }

  // Future<void> _openBeamTypeSummaryAndDetails(
  //   String beamId,
  //   List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  // ) async {
  //   if (docs.isEmpty) return;

  //   // 1) find beamType from one of the docs
  //   final firstData = docs.first.data();
  //   final beamType =
  //       (firstData['beamType'] ?? firstData['label'] ?? '').toString().trim();

  //   int sameTypeCount = 0;
  //   double sameTypeTotalLenM = 0.0;

  //   if (beamType.isNotEmpty) {
  //     final snap =
  //         await _measurementsRef
  //             .where('drawingId', isEqualTo: widget.drawingId)
  //             .where('measureType', isEqualTo: 'compositeBeam')
  //             .where('beamType', isEqualTo: beamType)
  //             .where('type', isEqualTo: 'beamConcrete') // one doc per beam
  //             .get();

  //     final seenBeamIds = <String>{};

  //     for (final d in snap.docs) {
  //       final data = d.data();
  //       final bId = (data['beamId'] ?? d.id).toString();
  //       final lenNum = (data['beamLengthM'] ?? data['lengthM'] ?? 0) as num;

  //       seenBeamIds.add(bId);
  //       sameTypeTotalLenM += lenNum.toDouble();
  //     }

  //     sameTypeCount = seenBeamIds.length;
  //   }

  //   await _showBeamCompositeDetailsDialog(
  //     beamId,
  //     docs,
  //     beamTypeLabel: beamType,
  //     sameTypeCount: sameTypeCount,
  //     sameTypeTotalLengthM: sameTypeTotalLenM,
  //   );
  // }
}
