import 'package:aqs/core/state/firestore_state.dart';
import 'dart:math' as math;
import 'package:aqs/features/takeoff/active_summary_panel.dart';
import 'package:aqs/features/takeoff/controllers/takeoff_controller.dart';
import 'package:aqs/features/takeoff/models/measured_segment.dart';
import 'package:aqs/features/takeoff/models/preset_choice.dart';
import 'package:aqs/features/takeoff/models/saved_area.dart';
import 'package:aqs/features/takeoff/overlays/area_painter.dart';
import 'package:aqs/features/takeoff/overlays/saved_area_painter.dart';
import 'package:aqs/features/utils/customs.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class DrawingTakeoffPage extends StatefulWidget {
  final String projectId;
  final String drawingId;
  final String buildingId;
  final String drawingTitle;

  const DrawingTakeoffPage({
    super.key,
    required this.projectId,
    required this.drawingId,
    required this.buildingId,
    required this.drawingTitle,
  });

  @override
  State<DrawingTakeoffPage> createState() => _DrawingTakeoffPageState();
}

class _DrawingTakeoffPageState extends State<DrawingTakeoffPage> {
  final PdfViewerController _pdfController = PdfViewerController();
  TakeoffMode _mode = TakeoffMode.view;
  String? _selectedSegmentId;

  Offset? _calibP1;
  Offset? _calibP2;

  Offset? _lengthP1;
  Offset? _lengthP2;
  String? _activeMeasureType;

  // final List<MeasuredSegment> _segments = [];
  Color _currentColor = Colors.blue;

  String? _activeLabel; // e.g. "Walling"
  String? _activeBoqCode; // e.g. "3.9(ii)"
  String? _activeUnit; // "m", "m2", "m3", "item", "kg", "ps"
  double? _activeHeightM; // used when unit is m2 (e.g. wall height)
  String? _activePresetKey;

  bool _previewVisible = false;
  Offset _previewOffset = const Offset(40, 80); // initial position

  double? _previewLengthMeters;
  double? _previewPixelDistanceBase;
  bool _previewCalibrated = false;
  List<Offset> _areaPoints = [];

  Offset? _previewP1;
  Offset? _previewP2;

  double? _previewHeightM; // for this measurement if unit == m2
  double? _previewQuantity; // computed quantity for display

  late final CollectionReference<Map<String, dynamic>> _measurementsRef;
  bool get _isWallingActive {
    final lbl = (_activeLabel ?? '').toLowerCase();
    // you can make this stricter if you want
    return lbl == 'walling' || lbl.contains('wall');
  }

  late final TakeoffController _takeoffController;
  bool _isCompositeBusy = false;

  @override
  void initState() {
    super.initState();

    _measurementsRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(widget.projectId)
        .collection('buildings')
        .doc(widget.buildingId)
        .collection('measurements');

    _takeoffController = TakeoffController(
      measurementsRef: _measurementsRef,
      onCompositeBusyChanged: (busy) {
        if (!mounted) return;
        setState(() {
          _isCompositeBusy = busy;
        });
      },
    );
  }

  final TextEditingController _previewHeightController =
      TextEditingController();

  DocumentReference get _drawingRef => FirebaseFirestore.instance
      .collection('projects')
      .doc(widget.projectId)
      .collection('buildings')
      .doc(widget.buildingId)
      .collection('drawings')
      .doc(widget.drawingId);

  // CollectionReference get _measurementsRef => FirebaseFirestore.instance
  //     .collection('projects')
  //     .doc(widget.projectId)
  //     .collection('measurements');

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

  Future<void> _completeAreaMeasurement(
    Map<String, dynamic> drawingData,
  ) async {
    if (_areaPoints.length < 3) return;

    // 1) Shoelace formula – area in "screen pixels"
    final areaPxScreen = _polygonAreaPx(_areaPoints).abs();
    if (areaPxScreen <= 0) return;

    // 2) Convert to base pixels (independent of zoom)
    double zoom = _pdfController.zoomLevel;
    if (zoom <= 0) zoom = 1.0;
    final areaPxBase = areaPxScreen / (zoom * zoom);

    // 3) Use calibration: pixelsPerUnit = px per meter
    final calibrated = drawingData['calibrated'] == true;
    final pixelsPerUnitBase = (drawingData['pixelsPerUnit'] ?? 0).toDouble();

    double? areaM2;
    if (calibrated && pixelsPerUnitBase > 0) {
      final pxPerMeter = pixelsPerUnitBase;
      final px2PerM2 = pxPerMeter * pxPerMeter;
      areaM2 = areaPxBase / px2PerM2;
    }

    // 4) Confirm + show area to user before saving
    if (!mounted) return;

    final unitDisplay = 'm²';
    final label = _activeLabel ?? '';
    final boq = _activeBoqCode ?? '';

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

    // 5) Save – treat as 'area' type; unit = 'm2'
    await _saveAreaMeasurement(
      polygon: _areaPoints,
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
      'drawingId': widget.drawingId,
      'buildingId': widget.buildingId,
      'type': 'area',
      'unit': 'm2',
      'value': areaM2, // final quantity in m² (may be null if uncalibrated)
      'areaPx': areaPxBase, // px² in base coordinates – useful for debugging
      'label': _activeLabel,
      'boqCode': _activeBoqCode,
      'color': _currentColor.value,
      'polygon': polyData,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  double _polygonAreaPx(List<Offset> pts) {
    double sum = 0;
    for (int i = 0; i < pts.length; i++) {
      final p1 = pts[i];
      final p2 = pts[(i + 1) % pts.length];
      sum += p1.dx * p2.dy - p2.dx * p1.dy;
    }
    return 0.5 * sum;
  }

  void _handleAreaTap(Offset pos, Map<String, dynamic> drawingData) async {
    // add point
    setState(() {
      _areaPoints = List.of(_areaPoints)..add(pos);
    });

    // if less than 3 points, can't close yet
    if (_areaPoints.length < 3) return;

    // You can decide "double-tap last point" or a separate button to finish.
    // Simplest: if user taps close to the first point, finish polygon.
    final first = _areaPoints.first;
    final distToFirst = (pos - first).distance;
    const closeRadius = 12.0;

    if (distToFirst <= closeRadius) {
      // close polygon & compute area
      await _completeAreaMeasurement(drawingData);
      _resetArea();
    }
  }

  void _openFloatingPreview({
    required Offset p1,
    required Offset p2,
    required double? lengthMeters,
    required double pixelDistanceBase,
    required bool calibrated,
  }) {
    setState(() {
      _previewP1 = p1;
      _previewP2 = p2;
      _previewLengthMeters = lengthMeters;
      _previewPixelDistanceBase = pixelDistanceBase;
      _previewCalibrated = calibrated;

      // initial height for this measurement
      if (_activeUnit == 'm2') {
        _previewHeightM = _activeHeightM;
        _previewHeightController.text =
            _previewHeightM != null ? _previewHeightM!.toString() : '';
      } else {
        _previewHeightM = null;
        _previewHeightController.text = '';
      }

      _recomputePreviewQuantity();
      _previewVisible = true;

      // optional: reset position each time
      _previewOffset = const Offset(40, 80);
    });
  }

  void _zoomIn() {
    final current = _pdfController.zoomLevel;
    final next = (current + 0.25).clamp(0.5, 5.0); // min/max zoom
    _pdfController.zoomLevel = next;
  }

  void _zoomOut() {
    final current = _pdfController.zoomLevel;
    final next = (current - 0.25).clamp(0.5, 5.0);
    _pdfController.zoomLevel = next;
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
            // wall area = L × h
            heightForThis = overrideHeightM ?? _activeHeightM;
            if (heightForThis != null && heightForThis > 0) {
              quantity = lengthMeters * heightForThis;
            }
          } else {
            // other m² measured by length mode – default to length
            // (but you will usually use polygon area for floors)
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
      'buildingId': widget.buildingId,
      'drawingId': widget.drawingId,
      'type': isWalling ? 'length' : 'length', // still "length" here
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
    // If we already have everything we need, don't bother the user again
    final hasBoq = _activeBoqCode != null && _activeBoqCode!.trim().isNotEmpty;
    final hasLabel = _activeLabel != null && _activeLabel!.trim().isNotEmpty;
    final hasUnit = _activeUnit != null && _activeUnit!.trim().isNotEmpty;

    // For walling we also need height
    final needsHeight = _isWallingActive && (_activeUnit == 'm2');
    final hasHeight = _activeHeightM != null && _activeHeightM! > 0;
    print(_isWallingActive);

    if (hasBoq && hasLabel && hasUnit && (!needsHeight || hasHeight)) {
      return true; // everything already set, just continue measuring
    }

    // Otherwise open the dialog once
    await _showMeasurementItemDialog();

    final hasBoq2 = _activeBoqCode != null && _activeBoqCode!.trim().isNotEmpty;
    final hasLabel2 = _activeLabel != null && _activeLabel!.trim().isNotEmpty;
    final hasUnit2 = _activeUnit != null && _activeUnit!.trim().isNotEmpty;
    final needsHeight2 = _isWallingActive && (_activeUnit == 'm2');
    final hasHeight2 = _activeHeightM != null && _activeHeightM! > 0;

    if (!hasUnit2) {
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

    return hasBoq2 && hasLabel2 && hasUnit2 && (!needsHeight2 || hasHeight2);
  }

  void _handleSegmentTap(Offset pos, List<MeasuredSegment> segments) async {
    // Find nearest segment to tap (within tolerance)
    const double maxDistance = 10.0; // px – tweak if needed
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
      // Tapped empty area: clear selection
      setState(() {
        _selectedSegmentId = null;
      });
      return;
    }

    // Select the segment and highlight it
    setState(() {
      _selectedSegmentId = closest!.id;
    });

    // Ask user to confirm deletion
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete measurement?'),
            content: const Text('Do you want to delete this measurement line?'),
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
    );

    if (confirm == true && _selectedSegmentId != null) {
      await _measurementsRef.doc(_selectedSegmentId!).delete();
      if (!mounted) return;
      setState(() {
        _selectedSegmentId = null;
      });
    }
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
          // wall area = length × height
          if (h == null || h <= 0) {
            _previewQuantity = null;
          } else {
            _previewQuantity = len * h;
          }
        } else {
          // other area types in m² (if using length mode) – default to length,
          // but usually floor area will use polygon mode instead.
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
    _pdfController.dispose();
    _previewHeightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _drawingRef.stateSnapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
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
        final downloadUrl = data['downloadUrl'] as String?;
        // print('Drawing downloadUrl: $downloadUrl');

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
                  if (ok) {
                    _setMode(TakeoffMode.measureLength);
                  }
                },
              ),
              IconButton(
                tooltip: 'Measure floor area',
                icon: Icon(
                  Icons.crop_square, // or poly icon
                  color: _mode == TakeoffMode.measureArea ? Colors.blue : null,
                ),
                onPressed: () async {
                  // make sure we have an active BOQ item for area (unit m2)
                  final ok = await _ensureActiveMeasurementItem();
                  if (!ok) return;
                  if (_activeUnit != 'm2') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Set unit to m² for floor before measuring area.',
                        ),
                      ),
                    );
                    return;
                  }
                  _setMode(TakeoffMode.measureArea);
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
                    _buildMeasuringItemBar(),
                    // if (_activeLabel != null && _activeBoqCode != null)
                    //   SizedBox(
                    //     width: 300,
                    //     child: Padding(
                    //       padding: const EdgeInsets.symmetric(
                    //         horizontal: 12.0,
                    //         vertical: 4,
                    //       ),
                    //       child: Row(
                    //         children: [
                    //           const Icon(Icons.label, size: 16),
                    //           const SizedBox(width: 6),
                    //           Expanded(
                    //             child: Text(
                    //               'Measuring: $_activeLabel (BOQ: $_activeBoqCode)',
                    //               style: const TextStyle(fontSize: 12),
                    //             ),
                    //           ),
                    //         ],
                    //       ),
                    //     ),
                    //   ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child:
                    downloadUrl == null
                        ? const Center(child: Text('No PDF URL found'))
                        : StreamBuilder<QuerySnapshot>(
                          stream:
                              _measurementsRef
                                  .where(
                                    'drawingId',
                                    isEqualTo: widget.drawingId,
                                  )
                                  // 👇 no .where('type') so we get both length + area + others
                                  .orderBy('createdAt', descending: false)
                                  .stateSnapshots(),
                          builder: (ctx, measSnap) {
                            if (measSnap.hasError) {
                              print(measSnap.error);
                              return Center(
                                child: Text(
                                  'Error loading measurements:\n${measSnap.error}',
                                  textAlign: TextAlign.center,
                                ),
                              );
                            }

                            final segments = <MeasuredSegment>[];
                            final savedAreas = <SavedArea>[];
                            final rebarSlabDocsBySlabId =
                                <String, List<QueryDocumentSnapshot>>{};

                            if (measSnap.hasData) {
                              for (final d in measSnap.data!.docs) {
                                final m = d.data() as Map<String, dynamic>;
                                final type = (m['type'] ?? 'length') as String;
                                final colorInt =
                                    (m['color'] ?? Colors.blue.value) as int;
                                final color = Color(colorInt);

                                if (type == 'length') {
                                  // ... your existing line logic ...
                                } else if (type == 'area') {
                                  // normal area polygon
                                  final polyList =
                                      (m['polygon'] ?? m['points'] ?? [])
                                          as List<dynamic>;
                                  final points = <Offset>[];
                                  for (final p in polyList) {
                                    if (p is Map<String, dynamic>) {
                                      points.add(
                                        Offset(
                                          (p['x'] ?? 0).toDouble(),
                                          (p['y'] ?? 0).toDouble(),
                                        ),
                                      );
                                    }
                                  }
                                  if (points.length >= 3) {
                                    savedAreas.add(
                                      SavedArea(
                                        id: d.id,
                                        points: points,
                                        color: color,
                                        isRebarSlab: false,
                                      ),
                                    );
                                  }
                                } else if (type == 'rebarSlab') {
                                  final slabId =
                                      (m['slabId'] ?? d.id) as String;
                                  final polyList =
                                      (m['polygon'] ?? []) as List<dynamic>;
                                  final points = <Offset>[];

                                  for (final p in polyList) {
                                    if (p is Map<String, dynamic>) {
                                      points.add(
                                        Offset(
                                          (p['x'] ?? 0).toDouble(),
                                          (p['y'] ?? 0).toDouble(),
                                        ),
                                      );
                                    }
                                  }

                                  // Collect docs for this slab
                                  rebarSlabDocsBySlabId
                                      .putIfAbsent(slabId, () => [])
                                      .add(d);

                                  // Only add polygon once per slabId
                                  final already = savedAreas.any(
                                    (a) => a.isRebarSlab && a.id == slabId,
                                  );
                                  if (!already && points.length >= 3) {
                                    savedAreas.add(
                                      SavedArea(
                                        id: slabId,
                                        points: points,
                                        color: color,
                                        isRebarSlab: true,
                                      ),
                                    );
                                  }
                                }
                              }
                            }

                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                SfPdfViewer.network(
                                  downloadUrl,
                                  controller: _pdfController,
                                  scrollDirection: PdfScrollDirection.vertical,
                                  enableDoubleTapZooming: true,
                                  pageSpacing: 8,
                                  onTap:
                                      (details) =>
                                          _onPdfTap(details, data, segments),
                                ),

                                // Calibration preview (red)
                                IgnorePointer(
                                  ignoring: true,
                                  child: CustomPaint(
                                    painter: _PointsPainter(
                                      p1: _calibP1,
                                      p2: _calibP2,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),

                                // 🔹 Saved polygons (floors, slabs, etc.) from Firestore
                                // IgnorePointer(
                                //   ignoring: true,
                                //   child: CustomPaint(
                                //     painter: SavedAreasPainter(
                                //       areas: savedAreas,
                                //     ),
                                //   ),
                                // ),

                                // 🔹 Saved line segments + current temp measurement
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

                                // 🔹 Live area being drawn (current polygon)
                                IgnorePointer(
                                  ignoring: true,
                                  child: CustomPaint(
                                    painter: AreaPainter(
                                      points: _areaPoints,
                                      color: Colors.orange,
                                      zoomScale: 0.0, // or _currentColor
                                    ),
                                  ),
                                ),

                                // Floating measurement preview card
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

                                // Active item summary (totals)
                                ActiveItemSummaryPanel(
                                  drawingId: widget.drawingId,
                                  measurementsRef: _measurementsRef,
                                  activeMeasureType: _activeMeasureType,
                                  activeLabel: _activeLabel,
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

  void _onPdfTap(
    PdfGestureDetails details,
    Map<String, dynamic> drawingData,
    List<MeasuredSegment> segments,
  ) {
    final pos = details.position;
    if (_mode == TakeoffMode.calibrate) {
      // _handleCalibrateTap(pos, drawingData);
    } else if (_mode == TakeoffMode.measureLength) {
      // _handleLengthTap(pos, drawingData);
    } else if (_mode == TakeoffMode.measureArea) {
      _handleAreaTap(pos, drawingData);
    } else if (_mode == TakeoffMode.editSegment) {
      _handleSegmentTap(pos, segments);
    }
  }

  Future<void> _undoLast() async {
    // If in the middle of measuring, just cancel the temp points
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

    // Otherwise delete last saved measurement for this drawing
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
              // header row with drag hint + close
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
                      // validate height for m2
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
                        // also update active height for next walls
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

  Widget _buildMeasuringItemBar() {
    return Expanded(
      child: StreamBuilder<QuerySnapshot>(
        stream:
            _measurementsRef
                .where('drawingId', isEqualTo: widget.drawingId)
                .stateSnapshots(),
        builder: (ctx, snap) {
          final choices = <PresetChoice>[];

          if (snap.hasData) {
            final seenKeys = <String>{};

            for (final d in snap.data!.docs) {
              final m = d.data() as Map<String, dynamic>;

              // We now accept ALL types (length, area, etc.)
              final label = (m['label'] ?? '') as String;
              final boq = (m['boqCode'] ?? '') as String;
              final unit = (m['unit'] ?? 'm') as String;
              final heightM =
                  (m['heightM'] != null)
                      ? (m['heightM'] as num).toDouble()
                      : null;

              if (boq.isEmpty) continue; // must have BOQ code

              final choice = PresetChoice(
                label: label.isNotEmpty ? label : boq,
                boqCode: boq,
                unit: unit,
                heightM: heightM,
                measureType: "",
              );
              final key = choice.key;

              if (seenKeys.add(key)) {
                choices.add(choice);
              }
            }
          }

          String unitToDisplay(String u) =>
              u == 'm2'
                  ? 'm²'
                  : u == 'm3'
                  ? 'm³'
                  : u;

          // if current active combo not in choices (e.g. user just set it manually),
          // optionally add it so dropdown stays in sync
          if (_activeLabel != null &&
              _activeBoqCode != null &&
              _activeUnit != null) {
            final synthetic = PresetChoice(
              measureType: "",
              label: _activeLabel!,
              boqCode: _activeBoqCode!,
              unit: _activeUnit!,
              heightM: _activeHeightM,
            );
            final k = synthetic.key;
            final exists = choices.any((c) => c.key == k);
            if (!exists) {
              choices.insert(0, synthetic);
            }
          }

          // ensure _activePresetKey is consistent with the list
          if (_activePresetKey != null &&
              !choices.any((c) => c.key == _activePresetKey)) {
            _activePresetKey = null;
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _activePresetKey,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Measuring item / BOQ',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    items:
                        choices.map((c) {
                          final displayUnit = unitToDisplay(c.unit);
                          return DropdownMenuItem<String>(
                            value: c.key,
                            child: Text(
                              '${c.label} [${c.boqCode}]  ($displayUnit)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                    onChanged: (key) {
                      if (key == null) return;
                      final choice = choices.firstWhere(
                        (c) => c.key == key,
                        orElse: () => choices.first,
                      );

                      setState(() {
                        _activePresetKey = key;
                        _activeLabel = choice.label;
                        _activeBoqCode = choice.boqCode;
                        _activeUnit = choice.unit;
                        _activeHeightM = choice.heightM;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Add / change measuring item',
                  child: IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _showMeasurementItemDialog,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Future<void> _showMeasurementItemDialog() async {
  //   final selection = await _takeoffController.showMeasurementItemDialog(
  //     context,
  //     currentLabel: _activeLabel,
  //     currentUnit: _activeUnit,
  //     currentBoqCode: _activeBoqCode,
  //     currentHeightM: _activeHeightM,
  //   );

  //   if (selection == null) return;

  //   setState(() {
  //     _activeLabel = selection.label;
  //     _activeBoqCode = selection.boqCode;
  //     _activeUnit = selection.unit;
  //     _activeHeightM = selection.wallHeightM;
  //     _activeMeasureType = selection.measureType;
  //   });
  // }

  Future<void> _showMeasurementItemDialog() async {
    const labelOptions = <String>[
      'Walling',
      'Tiling',
      'Pipe',
      'Beam',
      'Slab edge',
      'Cable tray',
      'Other',
    ];

    const unitOptions = <String>['m', 'm2', 'm3', 'item', 'kg', 'ps'];

    // --- initial local state (copied from active, but local) ---
    String selectedLabel =
        _activeLabel != null && labelOptions.contains(_activeLabel)
            ? _activeLabel!
            : labelOptions.first; // default "Walling"

    String selectedUnit = _activeUnit ?? 'm';

    final customLabelController = TextEditingController(
      text:
          _activeLabel != null && !labelOptions.contains(_activeLabel)
              ? _activeLabel
              : '',
    );

    final boqCodeController = TextEditingController(text: _activeBoqCode ?? '');
    final heightController = TextEditingController(
      text: _activeHeightM != null ? _activeHeightM!.toString() : '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            // ⚠️ IMPORTANT: use *local* selectedLabel, not _activeLabel
            final bool isWalling = selectedLabel.toLowerCase().contains(
              'wall',
            ); // "Walling", "External wall", etc.
            print(isWalling);
            return AlertDialog(
              title: const Text('Measuring item / BOQ'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                          setStateDialog(() {
                            selectedLabel = v!;
                          });
                        },
                        dense: true,
                      ),
                    ),
                    if (selectedLabel == 'Other')
                      TextField(
                        controller: customLabelController,
                        decoration: const InputDecoration(
                          labelText: 'Custom label (e.g. Boundary wall)',
                        ),
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'Unit:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      value: selectedUnit,
                      items:
                          unitOptions.map((u) {
                            final display =
                                u == 'm2'
                                    ? 'm²'
                                    : u == 'm3'
                                    ? 'm³'
                                    : u;
                            return DropdownMenuItem(
                              value: u,
                              child: Text(display),
                            );
                          }).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setStateDialog(() {
                          selectedUnit = v;
                        });
                      },
                    ),

                    // 👇 height ONLY when (unit = m2 AND label is walling)
                    if (selectedUnit == 'm2' && isWalling) ...[
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
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    const Text(
                      'BOQ item code:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    // TextField(
                    //   controller: boqCodeController,
                    //   decoration: const InputDecoration(
                    //     labelText: 'e.g. 3.9(ii)',
                    //     helperText: 'Use same code as in BOQ',
                    //   ),
                    // ),
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

    if (result != true) return;

    // --- After dialog is closed: update *active* state once ---

    // Final label
    String finalLabel;
    if (selectedLabel == 'Other') {
      finalLabel = customLabelController.text.trim();
      if (finalLabel.isEmpty) return;
    } else {
      finalLabel = selectedLabel;
    }

    final boq = boqCodeController.text.trim();
    if (boq.isEmpty) return;

    double? defaultHeight;
    final isWallingFinal = finalLabel.toLowerCase().contains(
      'wall',
    ); // this is now based on what user chose

    if (selectedUnit == 'm2' && isWallingFinal) {
      final hStr = heightController.text.trim();
      final hVal = double.tryParse(hStr);
      if (hVal == null || hVal <= 0) {
        // height required only for walling
        return;
      }
      defaultHeight = hVal;
    }

    setState(() {
      _activeLabel = finalLabel;
      _activeBoqCode = boq;
      _activeUnit = selectedUnit;
      _activeHeightM = defaultHeight;
      // if you use presetKey:
      // _activePresetKey = _PresetChoice(...).key;
    });
  }
}

class _PointsPainter extends CustomPainter {
  final Offset? p1;
  final Offset? p2;
  final Color color;

  _PointsPainter({required this.p1, required this.p2, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 2;

    if (p1 != null) {
      canvas.drawCircle(p1!, 4, paint);
    }
    if (p2 != null) {
      canvas.drawCircle(p2!, 4, paint);
    }
    if (p1 != null && p2 != null) {
      canvas.drawLine(p1!, p2!, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PointsPainter oldDelegate) {
    return oldDelegate.p1 != p1 ||
        oldDelegate.p2 != p2 ||
        oldDelegate.color != color;
  }
}

// class _AreaPainter extends CustomPainter {
//   final List<Offset> points;
//   final Color color;

//   _AreaPainter({required this.points, required this.color});

//   @override
//   void paint(Canvas canvas, Size size) {
//     if (points.length < 2) return;

//     final paintLine =
//         Paint()
//           ..color = color
//           ..style = PaintingStyle.stroke
//           ..strokeWidth = 2.0;

//     final paintFill =
//         Paint()
//           ..color = color.withOpacity(0.12)
//           ..style = PaintingStyle.fill;

//     final path = Path()..moveTo(points.first.dx, points.first.dy);
//     for (int i = 1; i < points.length; i++) {
//       path.lineTo(points[i].dx, points[i].dy);
//     }

//     // draw open poly
//     canvas.drawPath(path, paintLine);

//     // draw vertices
//     for (final p in points) {
//       canvas.drawCircle(p, 3, paintLine);
//     }

//     // If polygon is closed (we'll treat len >= 3 as "show closed")
//     if (points.length >= 3) {
//       path.close();
//       canvas.drawPath(path, paintFill);
//     }
//   }

//   @override
//   bool shouldRepaint(covariant _AreaPainter oldDelegate) => true;
// }
