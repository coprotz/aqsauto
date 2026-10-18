// import 'dart:async';
// import 'dart:math' as math;
// import 'dart:typed_data';

// import 'package:aqs/features/drawings/models/drawing_sheet.dart';
// import 'package:aqs/features/drawings/services/drawing_service.dart';
// import 'package:aqs/features/takeoff/models/drawing_calibration.dart';
// import 'package:aqs/features/takeoff/models/takeoff_measurement.dart';
// import 'package:aqs/features/takeoff/models/takeoff_subtool.dart';
// import 'package:aqs/features/takeoff/services/takeoff_measurement_service.dart';
// import 'package:aqs/features/utils/enum.dart';
// import 'package:aqs/features/utils/helpers/helpers.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';

// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:http/http.dart' as http;
// import 'package:pdfx/pdfx.dart';

// class TakeOffWorkspacePage extends StatefulWidget {
//   const TakeOffWorkspacePage({
//     super.key,
//     required this.projectId,
//     required this.facilityId,
//     required this.drawingId,
//   });

//   final String projectId;
//   final String facilityId;
//   final String drawingId;

//   @override
//   State<TakeOffWorkspacePage> createState() => _TakeOffWorkspacePageState();
// }

// class _TakeOffWorkspacePageState extends State<TakeOffWorkspacePage> {
//   PdfControllerPinch? _pdfController;

//   bool _loadingPdf = false;

//   String? _pdfError;

//   String? _loadedPdfUrl;
//   String? _requestedPdfUrl;

//   TakeOffTool _selectedTool = TakeOffTool.select;

//   String? _selectedSubToolId;

//   TakeOffCategory? _selectedCategory;

//   TakeOffMeasurementMode _measurementMode = TakeOffMeasurementMode.pan;

//   Offset? _lengthPointA;
//   Offset? _lengthPointB;

//   double? _currentLengthMeters;

//   bool _savingMeasurement = false;

//   Offset? _calibrationPointA;
//   Offset? _calibrationPointB;

//   bool _savingCalibration = false;

//   DrawingSheet? _drawing;
//   StreamSubscription<DrawingSheet?>? _drawingSubscription;

//   Offset? _calibrationScenePointA;
//   Offset? _calibrationScenePointB;

//   Offset? _calibrationDisplayPointA;
//   Offset? _calibrationDisplayPointB;

//   List<TakeOffMeasurement> _savedMeasurements = [];

//   StreamSubscription<List<TakeOffMeasurement>>? _measurementSubscription;

//   TakeOffMeasurement? _selectedMeasurement;

//   Offset _sceneToViewport(PdfControllerPinch controller, Offset scenePoint) {
//     return MatrixUtils.transformPoint(controller.value, scenePoint);
//   }

//   @override
//   void initState() {
//     super.initState();

//     _drawingSubscription = DrawingService.instance
//         .watchDrawing(
//           projectId: widget.projectId,
//           facilityId: widget.facilityId,
//           drawingId: widget.drawingId,
//         )
//         .listen((drawing) {
//           if (!mounted || drawing == null) {
//             return;
//           }

//           final firstLoad = _drawing == null;

//           setState(() {
//             _drawing = drawing;
//           });

//           if (firstLoad) {
//             _requestPdfLoad(drawing);
//           }
//         });
//     _measurementSubscription = TakeOffMeasurementService.instance
//         .watchDrawingMeasurements(
//           projectId: widget.projectId,
//           facilityId: widget.facilityId,
//           drawingId: widget.drawingId,
//         )
//         .listen((measurements) {
//           if (!mounted) {
//             return;
//           }

//           setState(() {
//             _savedMeasurements = measurements;
//           });
//         });
//   }

//   void _handleSelectMeasurement(Offset viewportPoint) {
//     final controller = _pdfController;

//     if (controller == null) {
//       return;
//     }

//     const hitTolerance = 14.0;

//     TakeOffMeasurement? nearest;
//     double nearestDistance = double.infinity;

//     for (final measurement in _savedMeasurements) {
//       if (measurement.measurementType != 'length') {
//         continue;
//       }

//       final sceneA = Offset(measurement.pointAX, measurement.pointAY);

//       final sceneB = Offset(measurement.pointBX, measurement.pointBY);

//       final screenA = MatrixUtils.transformPoint(controller.value, sceneA);

//       final screenB = MatrixUtils.transformPoint(controller.value, sceneB);

//       final distance = distanceToSegment(viewportPoint, screenA, screenB);

//       if (distance < hitTolerance && distance < nearestDistance) {
//         nearest = measurement;
//         nearestDistance = distance;
//       }
//     }

//     setState(() {
//       _selectedMeasurement = nearest;
//     });
//   }

//   void _requestPdfLoad(DrawingSheet drawing) {
//     final url = drawing.downloadUrl.trim();

//     if (url.isEmpty) {
//       return;
//     }

//     if (_requestedPdfUrl == url) {
//       return;
//     }

//     _requestedPdfUrl = url;

//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       if (!mounted) {
//         return;
//       }

//       _loadPdf(drawing);
//     });
//   }

//   @override
//   void dispose() {
//     _drawingSubscription?.cancel();
//     _measurementSubscription?.cancel();
//     _pdfController?.dispose();

//     super.dispose();
//   }

//   Future<void> _saveCalibration({
//     required Offset pointA,
//     required Offset pointB,
//     required double knownDistance,
//     required String unit,
//   }) async {
//     if (_savingCalibration) {
//       return;
//     }

//     final dx = pointB.dx - pointA.dx;

//     final dy = pointB.dy - pointA.dy;

//     final sceneDistance = math.sqrt((dx * dx) + (dy * dy));

//     if (sceneDistance <= 0) {
//       _showMessage('Calibration points are too close together.');

//       return;
//     }

//     //
//     // Convert QS-entered distance
//     // into millimetres.
//     //
//     final double knownDistanceMm;

//     switch (unit) {
//       case 'm':
//         knownDistanceMm = knownDistance * 1000;
//         break;

//       case 'cm':
//         knownDistanceMm = knownDistance * 10;
//         break;

//       case 'mm':
//       default:
//         knownDistanceMm = knownDistance;
//         break;
//     }

//     if (knownDistanceMm <= 0) {
//       _showMessage('Enter a valid calibration distance.');

//       return;
//     }

//     //
//     // Example:
//     //
//     // known distance = 5000 mm
//     // scene distance = 250
//     //
//     // 5000 / 250 = 20 mm per scene unit
//     //
//     final mmPerSceneUnit = knownDistanceMm / sceneDistance;

//     final calibration = DrawingCalibration(
//       pointAX: pointA.dx,

//       pointAY: pointA.dy,

//       pointBX: pointB.dx,

//       pointBY: pointB.dy,

//       sceneDistance: sceneDistance,

//       knownDistance: knownDistanceMm,

//       unit: 'mm',

//       unitsPerSceneUnit: mmPerSceneUnit,
//     );

//     setState(() {
//       _savingCalibration = true;
//     });

//     try {
//       debugPrint('====================================');

//       debugPrint('SAVING CALIBRATION');

//       debugPrint('Scene distance: $sceneDistance');

//       debugPrint('Known distance: $knownDistanceMm mm');

//       debugPrint(
//         'Calibration factor: '
//         '$mmPerSceneUnit mm/scene-unit',
//       );

//       await DrawingService.instance.saveDrawingCalibration(
//         projectId: widget.projectId,

//         facilityId: widget.facilityId,

//         drawingId: widget.drawingId,

//         calibration: calibration,
//       );

//       debugPrint('CALIBRATION SAVED');

//       debugPrint('====================================');

//       if (!mounted) {
//         return;
//       }

//       setState(() {
//         _savingCalibration = false;

//         //
//         // Return user to Select.
//         //
//         _measurementMode = TakeOffMeasurementMode.select;

//         //
//         // Clear temporary calibration marks.
//         //
//         _calibrationPointA = null;

//         _calibrationPointB = null;
//       });

//       _showMessage('Drawing calibrated successfully.');
//     } catch (error, stackTrace) {
//       debugPrint(
//         'CALIBRATION SAVE ERROR: '
//         '$error',
//       );

//       debugPrint(stackTrace.toString());

//       if (!mounted) {
//         return;
//       }

//       setState(() {
//         _savingCalibration = false;
//       });

//       _showMessage(
//         'Could not save calibration: '
//         '$error',
//       );
//     }
//   }

//   Future<void> _showCalibrationDistanceDialog() async {
//     final pointA = _calibrationPointA;

//     final pointB = _calibrationPointB;

//     if (pointA == null || pointB == null) {
//       return;
//     }

//     final distanceController = TextEditingController();

//     String unit = 'mm';

//     final result = await showDialog<_CalibrationInput>(
//       context: context,
//       barrierDismissible: false,
//       builder: (dialogContext) {
//         return StatefulBuilder(
//           builder: (context, setDialogState) {
//             return AlertDialog(
//               title: const Text('Calibrate Drawing'),

//               content: SizedBox(
//                 width: 420,
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     const Text(
//                       'Enter the actual distance '
//                       'between Point A and Point B.',
//                     ),

//                     const SizedBox(height: 18),

//                     Row(
//                       children: [
//                         Expanded(
//                           child: TextField(
//                             controller: distanceController,

//                             autofocus: true,

//                             keyboardType: const TextInputType.numberWithOptions(
//                               decimal: true,
//                             ),

//                             decoration: const InputDecoration(
//                               labelText: 'Known distance',
//                               hintText: '5000',
//                               border: OutlineInputBorder(),
//                             ),
//                           ),
//                         ),

//                         const SizedBox(width: 12),

//                         SizedBox(
//                           width: 110,
//                           child: DropdownButtonFormField<String>(
//                             value: unit,

//                             decoration: const InputDecoration(
//                               labelText: 'Unit',
//                               border: OutlineInputBorder(),
//                             ),

//                             items: const [
//                               DropdownMenuItem(value: 'mm', child: Text('mm')),
//                               DropdownMenuItem(value: 'cm', child: Text('cm')),
//                               DropdownMenuItem(value: 'm', child: Text('m')),
//                             ],

//                             onChanged: (value) {
//                               if (value == null) {
//                                 return;
//                               }

//                               setDialogState(() {
//                                 unit = value;
//                               });
//                             },
//                           ),
//                         ),
//                       ],
//                     ),
//                   ],
//                 ),
//               ),

//               actions: [
//                 TextButton(
//                   onPressed: () {
//                     Navigator.of(dialogContext).pop();
//                   },
//                   child: const Text('Cancel'),
//                 ),

//                 FilledButton(
//                   onPressed: () {
//                     final value = double.tryParse(
//                       distanceController.text.trim(),
//                     );

//                     if (value == null || value <= 0) {
//                       return;
//                     }

//                     Navigator.of(
//                       dialogContext,
//                     ).pop(_CalibrationInput(distance: value, unit: unit));
//                   },
//                   child: const Text('Apply Calibration'),
//                 ),
//               ],
//             );
//           },
//         );
//       },
//     );

//     distanceController.dispose();

//     if (result == null) {
//       setState(() {
//         _calibrationPointA = null;

//         _calibrationPointB = null;
//       });

//       return;
//     }

//     await _saveCalibration(
//       pointA: pointA,
//       pointB: pointB,
//       knownDistance: result.distance,
//       unit: result.unit,
//     );
//   }

//   void _handleLengthTap(Offset viewportPoint, DrawingSheet drawing) {
//     _debugCoordinate(viewportPoint);
//     final calibration = drawing.calibration;

//     if (!drawing.calibrated || calibration == null) {
//       _showMessage('Calibrate the drawing first.');
//       return;
//     }

//     if (_selectedCategory == null || _selectedSubToolId == null) {
//       _showMessage('Select a construction category and take-off item.');
//       return;
//     }

//     final controller = _pdfController;

//     if (controller == null) {
//       return;
//     }

//     final scenePoint = controller.toScene(viewportPoint);

//     if (_lengthPointA == null) {
//       setState(() {
//         _lengthPointA = scenePoint;

//         _lengthPointB = null;

//         _currentLengthMeters = null;
//       });

//       return;
//     }

//     if (_lengthPointB == null) {
//       final a = _lengthPointA!;

//       final dx = scenePoint.dx - a.dx;

//       final dy = scenePoint.dy - a.dy;

//       final sceneDistance = math.sqrt((dx * dx) + (dy * dy));

//       final lengthMm = sceneDistance * calibration.unitsPerSceneUnit;

//       final lengthMeters = lengthMm / 1000;

//       setState(() {
//         _lengthPointB = scenePoint;

//         _currentLengthMeters = lengthMeters;
//       });

//       _showLengthResultDialog(drawing);

//       return;
//     }

//     setState(() {
//       _lengthPointA = scenePoint;

//       _lengthPointB = null;

//       _currentLengthMeters = null;
//     });
//   }

//   Future<void> _saveLengthMeasurement(DrawingSheet drawing) async {
//     final pointA = _lengthPointA;

//     final pointB = _lengthPointB;

//     final length = _currentLengthMeters;

//     final category = _selectedCategory;

//     final subTool = _selectedSubToolId;

//     if (pointA == null ||
//         pointB == null ||
//         length == null ||
//         category == null ||
//         subTool == null) {
//       return;
//     }

//     if (_savingMeasurement) {
//       return;
//     }

//     setState(() {
//       _savingMeasurement = true;
//     });

//     try {
//       await TakeOffMeasurementService.instance.createLengthMeasurement(
//         projectId: widget.projectId,

//         facilityId: widget.facilityId,

//         drawingId: drawing.id,

//         bundleId: drawing.bundleId,

//         category: category.name,

//         subTool: subTool,

//         pointAX: pointA.dx,

//         pointAY: pointA.dy,

//         pointBX: pointB.dx,

//         pointBY: pointB.dy,

//         lengthMeters: length,
//       );

//       await DrawingService.instance.incrementMeasurementCount(
//         projectId: widget.projectId,

//         facilityId: widget.facilityId,

//         drawingId: drawing.id,
//       );

//       if (!mounted) {
//         return;
//       }

//       setState(() {
//         _savingMeasurement = false;

//         _lengthPointA = null;

//         _lengthPointB = null;

//         _currentLengthMeters = null;
//       });

//       _showMessage('Measurement saved.');
//     } catch (error) {
//       if (!mounted) {
//         return;
//       }

//       setState(() {
//         _savingMeasurement = false;
//       });

//       _showMessage('Could not save measurement: $error');
//     }
//   }

//   Future<void> _loadPdf(DrawingSheet drawing) async {
//     final downloadUrl = drawing.downloadUrl.trim();

//     if (downloadUrl.isEmpty) {
//       if (!mounted) {
//         return;
//       }

//       setState(() {
//         _loadingPdf = false;

//         _pdfError = 'This drawing does not have a download URL.';
//       });

//       return;
//     }

//     if (_loadedPdfUrl == downloadUrl && _pdfController != null) {
//       return;
//     }

//     if (_loadingPdf) {
//       return;
//     }

//     setState(() {
//       _loadingPdf = true;
//       _pdfError = null;
//     });

//     try {
//       final response = await http
//           .get(Uri.parse(downloadUrl))
//           .timeout(const Duration(seconds: 60));

//       if (response.statusCode != 200) {
//         throw Exception(
//           'Could not download drawing. '
//           'HTTP ${response.statusCode}',
//         );
//       }

//       if (response.bodyBytes.isEmpty) {
//         throw Exception('Drawing PDF is empty.');
//       }

//       final safeBytes = Uint8List.fromList(response.bodyBytes);

//       final controller = PdfControllerPinch(
//         document: PdfDocument.openData(safeBytes),
//       );

//       final document = await controller.document.timeout(
//         const Duration(seconds: 30),
//       );

//       debugPrint(
//         'TAKEOFF PDF READY: '
//         '${document.pagesCount} page(s)',
//       );

//       if (!mounted) {
//         controller.dispose();

//         return;
//       }

//       final oldController = _pdfController;

//       setState(() {
//         _pdfController = controller;

//         _loadedPdfUrl = downloadUrl;

//         _loadingPdf = false;

//         _pdfError = null;
//       });

//       oldController?.dispose();
//     } catch (error, stackTrace) {
//       debugPrint('TAKEOFF PDF ERROR: $error');

//       debugPrint(stackTrace.toString());

//       if (!mounted) {
//         return;
//       }

//       setState(() {
//         _loadingPdf = false;

//         _pdfError = error.toString();
//       });
//     }
//   }

//   void _debugCoordinate(Offset viewportPoint) {
//     final controller = _pdfController;

//     if (controller == null) {
//       return;
//     }

//     final scenePoint = controller.toScene(viewportPoint);

//     final backToViewport = MatrixUtils.transformPoint(
//       controller.value,
//       scenePoint,
//     );

//     debugPrint('VIEWPORT ORIGINAL: $viewportPoint');

//     debugPrint('SCENE: $scenePoint');

//     debugPrint('BACK TO VIEWPORT: $backToViewport');

//     debugPrint('ZOOM: ${controller.zoomRatio}');
//   }

//   @override
//   Widget build(BuildContext context) {
//     final drawing = _drawing;

//     if (drawing == null) {
//       return const Scaffold(body: Center(child: CircularProgressIndicator()));
//     }

//     return Scaffold(
//       backgroundColor: const Color(0xFFF5F7FA),

//       body: Column(
//         children: [
//           _TakeOffHeader(
//             drawing: drawing,

//             onBack: () {
//               Get.back();
//             },
//           ),

//           Expanded(
//             child: Row(
//               children: [
//                 _TakeOffToolbar(
//                   selectedMode: _measurementMode,

//                   calibrated: drawing.calibrated,

//                   onModeChanged: (mode) {
//                     setState(() {
//                       _measurementMode = mode;
//                     });
//                   },
//                 ),

//                 Expanded(child: _buildDrawingArea(drawing)),

//                 SizedBox(
//                   width: 320,

//                   child: _TakeOffSidePanel(
//                     drawing: drawing,

//                     selectedMode: _measurementMode,

//                     selectedCategory: _selectedCategory,

//                     selectedSubToolId: _selectedSubToolId,

//                     onCategoryChanged: (category) {
//                       setState(() {
//                         _selectedCategory = category;

//                         _selectedSubToolId = null;
//                       });
//                     },

//                     onSubToolSelected: (toolId) {
//                       _handleSubToolSelected(drawing, toolId);
//                     },

//                     selectedMeasurement: _selectedMeasurement,

//                     onEditSelectedMeasurement: () {
//                       // Handle edit selected measurement
//                     },

//                     onDeleteSelectedMeasurement: () {
//                       // Handle delete selected measurement
//                     },
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildDrawingArea(DrawingSheet drawing) {
//     if (_loadingPdf) {
//       return const Center(child: CircularProgressIndicator());
//     }

//     if (_pdfError != null) {
//       return Center(
//         child: Column(
//           mainAxisSize: MainAxisSize.min,

//           children: [
//             Text(_pdfError!),

//             const SizedBox(height: 14),

//             OutlinedButton.icon(
//               onPressed: () {
//                 setState(() {
//                   _requestedPdfUrl = null;

//                   _loadedPdfUrl = null;

//                   _pdfError = null;
//                 });

//                 _loadPdf(drawing);
//               },

//               icon: const Icon(Icons.refresh),

//               label: const Text('Retry'),
//             ),
//           ],
//         ),
//       );
//     }

//     final controller = _pdfController;

//     if (controller == null) {
//       return const Center(child: Text('Preparing drawing...'));
//     }

//     return Container(
//       color: const Color(0xFFE5E7EB),
//       child: Stack(
//         fit: StackFit.expand,
//         children: [
//           PdfViewPinch(controller: controller, minScale: 1, maxScale: 20),
//           if (_measurementMode == TakeOffMeasurementMode.select)
//             Positioned.fill(
//               child: GestureDetector(
//                 behavior: HitTestBehavior.translucent,
//                 onTapDown: (details) {
//                   _handleSelectMeasurement(details.localPosition);
//                 },
//               ),
//             ),
//           // 2. Saved measurements
//           //
//           Positioned.fill(
//             child: IgnorePointer(
//               child: _SavedMeasurementsOverlay(
//                 controller: controller,

//                 measurements: _savedMeasurements,

//                 selectedMeasurementId: _selectedMeasurement?.id,
//               ),
//             ),
//           ),

//           if (_measurementMode == TakeOffMeasurementMode.calibrate)
//             Positioned.fill(
//               child: GestureDetector(
//                 behavior: HitTestBehavior.translucent,

//                 onTapDown: (details) {
//                   _handleCalibrationTap(details.localPosition);
//                 },

//                 child: _CalibrationOverlay(
//                   // controller: contsroller,
//                   pointA: _calibrationPointA,

//                   pointB: _calibrationPointB,
//                 ),
//               ),
//             ),

//           //
//           // Length measurement overlay
//           //
//           if (_measurementMode == TakeOffMeasurementMode.length)
//             Positioned.fill(
//               child: GestureDetector(
//                 behavior: HitTestBehavior.translucent,

//                 onTapDown: (details) {
//                   _handleLengthTap(details.localPosition, drawing);
//                 },

//                 child: _LengthMeasurementOverlay(
//                   controller: controller,

//                   pointA: _lengthPointA,

//                   pointB: _lengthPointB,

//                   lengthMeters: _currentLengthMeters,
//                 ),
//               ),
//             ),
//           Positioned(
//             right: 18,
//             bottom: 18,
//             child: _ZoomControls(controller: controller),
//           ),
//         ],
//       ),
//     );
//   }

//   void _handleSubToolSelected(DrawingSheet drawing, String toolId) {
//     final category = _selectedCategory;

//     if (category == null) {
//       _showMessage('Select a construction category first.');
//       return;
//     }

//     //
//     // Save selected sub-tool first.
//     //
//     setState(() {
//       _selectedSubToolId = toolId;
//     });

//     //
//     // Decide which measurement mode
//     // this sub-tool should use.
//     //
//     TakeOffMeasurementMode? requiredMode;

//     switch (category) {
//       case TakeOffCategory.wallsFinishes:
//         switch (toolId) {
//           case 'blockwork':
//             requiredMode = TakeOffMeasurementMode.length;
//             break;

//           case 'plaster':
//           case 'painting':
//           case 'wall_tiles':
//             requiredMode = TakeOffMeasurementMode.area;
//             break;

//           case 'skirting':
//           case 'dpc':
//             requiredMode = TakeOffMeasurementMode.length;
//             break;
//         }
//         break;

//       case TakeOffCategory.beamsLintels:
//         switch (toolId) {
//           case 'beam_concrete':
//             requiredMode = TakeOffMeasurementMode.volume;
//             break;

//           case 'beam_formwork':
//             requiredMode = TakeOffMeasurementMode.area;
//             break;

//           case 'beam_reinforcement':
//             requiredMode = TakeOffMeasurementMode.length;
//             break;

//           case 'lintels':
//             requiredMode = TakeOffMeasurementMode.length;
//             break;
//         }
//         break;

//       case TakeOffCategory.slabsFloors:
//         switch (toolId) {
//           case 'slab_concrete':
//             requiredMode = TakeOffMeasurementMode.volume;
//             break;

//           case 'slab_formwork':
//           case 'floor_finish':
//           case 'screed':
//             requiredMode = TakeOffMeasurementMode.area;
//             break;

//           case 'slab_reinforcement':
//             requiredMode = TakeOffMeasurementMode.length;
//             break;
//         }
//         break;

//       case TakeOffCategory.foundations:
//         switch (toolId) {
//           case 'excavation':
//           case 'strip_footing':
//           case 'pad_footing':
//           case 'raft_foundation':
//           case 'ground_beam':
//           case 'backfilling':
//             requiredMode = TakeOffMeasurementMode.volume;
//             break;

//           case 'blinding':
//             requiredMode = TakeOffMeasurementMode.area;
//             break;
//         }
//         break;

//       case TakeOffCategory.stairsRamps:
//         switch (toolId) {
//           case 'stairs_concrete':
//             requiredMode = TakeOffMeasurementMode.volume;
//             break;

//           case 'stairs_formwork':
//           case 'stairs_finishes':
//             requiredMode = TakeOffMeasurementMode.area;
//             break;

//           case 'stairs_reinforcement':
//             requiredMode = TakeOffMeasurementMode.length;
//             break;
//         }
//         break;

//       case TakeOffCategory.roofCoverings:
//         switch (toolId) {
//           case 'roof_covering':
//             requiredMode = TakeOffMeasurementMode.area;
//             break;

//           case 'ridge':
//           case 'valley':
//           case 'flashing':
//           case 'gutters':
//             requiredMode = TakeOffMeasurementMode.length;
//             break;
//         }
//         break;

//       case TakeOffCategory.roofStructure:
//         requiredMode = TakeOffMeasurementMode.length;
//         break;

//       case TakeOffCategory.roadsKerbs:
//         switch (toolId) {
//           case 'road_area':
//           case 'paving':
//             requiredMode = TakeOffMeasurementMode.area;
//             break;

//           case 'road_excavation':
//           case 'subbase':
//           case 'basecourse':
//             requiredMode = TakeOffMeasurementMode.volume;
//             break;

//           case 'kerbs':
//             requiredMode = TakeOffMeasurementMode.length;
//             break;
//         }
//         break;

//       case TakeOffCategory.areasVolumes:
//         switch (toolId) {
//           case 'general_area':
//             requiredMode = TakeOffMeasurementMode.area;
//             break;

//           case 'general_volume':
//             requiredMode = TakeOffMeasurementMode.volume;
//             break;

//           case 'perimeter':
//             requiredMode = TakeOffMeasurementMode.length;
//             break;
//         }
//         break;

//       case TakeOffCategory.doorsWindows:
//         //
//         // Usually measured by number.
//         //
//         requiredMode = TakeOffMeasurementMode.count;
//         break;

//       case TakeOffCategory.servicesPipework:
//         switch (toolId) {
//           case 'pipe_length':
//           case 'cable_conduit':
//             requiredMode = TakeOffMeasurementMode.length;
//             break;

//           case 'fittings':
//           case 'fixtures':
//             requiredMode = TakeOffMeasurementMode.count;
//             break;
//         }
//         break;

//       case TakeOffCategory.boqVerification:
//         //
//         // BOQ verification is not a geometric
//         // measurement mode.
//         //
//         requiredMode = TakeOffMeasurementMode.select;
//         break;
//     }

//     if (requiredMode == null) {
//       _showMessage('This take-off item has not been configured yet.');
//       return;
//     }

//     //
//     // Count does not require calibration.
//     //
//     final requiresCalibration =
//         requiredMode == TakeOffMeasurementMode.length ||
//         requiredMode == TakeOffMeasurementMode.area ||
//         requiredMode == TakeOffMeasurementMode.volume;

//     if (requiresCalibration &&
//         (!drawing.calibrated || drawing.calibration == null)) {
//       setState(() {
//         _measurementMode = TakeOffMeasurementMode.calibrate;
//       });

//       _showMessage(
//         'Calibrate the drawing before measuring ${subToolLabel(toolId)}.',
//       );

//       return;
//     }

//     setState(() {
//       _measurementMode = requiredMode!;
//     });
//   }

//   void _showMessage(String message) {
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).hideCurrentSnackBar();
//     ScaffoldMessenger.of(
//       context,
//     ).showSnackBar(SnackBar(content: Text(message)));
//   }

//   Future<void> _showLengthResultDialog(DrawingSheet drawing) async {
//     final length = _currentLengthMeters;

//     if (length == null) {
//       return;
//     }

//     final result = await showDialog<bool>(
//       context: context,

//       barrierDismissible: false,

//       builder: (dialogContext) {
//         return AlertDialog(
//           title: const Text('Length Measurement'),

//           content: Column(
//             mainAxisSize: MainAxisSize.min,

//             crossAxisAlignment: CrossAxisAlignment.start,

//             children: [
//               const Text(
//                 'Measured length',
//                 style: TextStyle(color: Color(0xFF667085)),
//               ),

//               const SizedBox(height: 6),

//               Text(
//                 '${length.toStringAsFixed(3)} m',
//                 style: const TextStyle(
//                   fontSize: 28,

//                   fontWeight: FontWeight.w900,
//                 ),
//               ),

//               const SizedBox(height: 18),

//               Text(_selectedCategory?.label ?? ''),

//               const SizedBox(height: 4),

//               Text(
//                 _selectedSubToolId ?? '',
//                 style: const TextStyle(color: Color(0xFF667085)),
//               ),
//             ],
//           ),

//           actions: [
//             TextButton(
//               onPressed: () {
//                 Navigator.of(dialogContext).pop(false);
//               },

//               child: const Text('Discard'),
//             ),

//             FilledButton.icon(
//               onPressed: () {
//                 Navigator.of(dialogContext).pop(true);
//               },

//               icon: const Icon(Icons.save_outlined),

//               label: const Text('Save Measurement'),
//             ),
//           ],
//         );
//       },
//     );

//     if (result == true) {
//       await _saveLengthMeasurement(drawing);
//     } else {
//       setState(() {
//         _lengthPointA = null;

//         _lengthPointB = null;

//         _currentLengthMeters = null;
//       });
//     }
//   }

//   void _handleCalibrationTap(Offset viewportPoint) {
//     final controller = _pdfController;

//     if (controller == null) {
//       return;
//     }

//     final scenePoint = controller.toScene(viewportPoint);

//     if (_calibrationScenePointA == null) {
//       setState(() {
//         _calibrationScenePointA = scenePoint;

//         _calibrationDisplayPointA = viewportPoint;

//         _calibrationScenePointB = null;

//         _calibrationDisplayPointB = null;
//       });

//       return;
//     }

//     if (_calibrationScenePointB == null) {
//       setState(() {
//         _calibrationScenePointB = scenePoint;

//         _calibrationDisplayPointB = viewportPoint;
//       });

//       _showCalibrationDistanceDialog();

//       return;
//     }

//     setState(() {
//       _calibrationScenePointA = scenePoint;

//       _calibrationDisplayPointA = viewportPoint;

//       _calibrationScenePointB = null;

//       _calibrationDisplayPointB = null;
//     });
//   }
// }

// enum TakeOffTool { select, length, area, count, wall }

// class _ZoomControls extends StatelessWidget {
//   const _ZoomControls({required this.controller});

//   final PdfControllerPinch controller;

//   @override
//   Widget build(BuildContext context) {
//     return Material(
//       elevation: 6,
//       borderRadius: BorderRadius.circular(12),
//       child: Container(
//         padding: const EdgeInsets.all(4),
//         decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: BorderRadius.circular(12),
//         ),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             IconButton(
//               tooltip: 'Zoom in',
//               onPressed: () {
//                 _zoom(controller, 1.25);
//               },
//               icon: const Icon(Icons.add_rounded),
//             ),

//             IconButton(
//               tooltip: 'Fit drawing',
//               onPressed: () {
//                 controller.value = Matrix4.identity();
//               },
//               icon: const Icon(Icons.fit_screen_rounded),
//             ),

//             IconButton(
//               tooltip: 'Zoom out',
//               onPressed: () {
//                 _zoom(controller, 0.8);
//               },
//               icon: const Icon(Icons.remove_rounded),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   void _zoom(PdfControllerPinch controller, double factor) {
//     final matrix = controller.value.clone();

//     final currentScale = matrix.getMaxScaleOnAxis();

//     final targetScale = (currentScale * factor).clamp(1.0, 20.0);

//     final adjustment = targetScale / currentScale;

//     matrix.scale(adjustment, adjustment);

//     controller.value = matrix;
//   }
// }

// class _LengthMeasurementOverlay extends StatelessWidget {
//   const _LengthMeasurementOverlay({
//     required this.controller,
//     required this.pointA,
//     required this.pointB,
//     required this.lengthMeters,
//   });

//   final PdfControllerPinch controller;

//   final Offset? pointA;
//   final Offset? pointB;

//   final double? lengthMeters;

//   @override
//   Widget build(BuildContext context) {
//     return AnimatedBuilder(
//       animation: controller,

//       builder: (context, child) {
//         final matrix = controller.value;

//         Offset? screenA;
//         Offset? screenB;

//         if (pointA != null) {
//           screenA = MatrixUtils.transformPoint(matrix, pointA!);
//         }

//         if (pointB != null) {
//           screenB = MatrixUtils.transformPoint(matrix, pointB!);
//         }

//         return CustomPaint(
//           painter: _LengthPainter(
//             pointA: screenA,

//             pointB: screenB,

//             lengthMeters: lengthMeters,
//           ),
//         );
//       },
//     );
//   }
// }

// class _LengthPainter extends CustomPainter {
//   const _LengthPainter({
//     required this.pointA,
//     required this.pointB,
//     required this.lengthMeters,
//   });

//   final Offset? pointA;
//   final Offset? pointB;

//   final double? lengthMeters;

//   @override
//   void paint(Canvas canvas, Size size) {
//     final a = pointA;

//     if (a == null) {
//       return;
//     }

//     final linePaint =
//         Paint()
//           ..color = const Color(0xFF2563EB)
//           ..strokeWidth = 2.5
//           ..style = PaintingStyle.stroke;

//     final pointPaint =
//         Paint()
//           ..color = const Color(0xFF2563EB)
//           ..style = PaintingStyle.fill;

//     canvas.drawCircle(a, 5, pointPaint);

//     final b = pointB;

//     if (b == null) {
//       return;
//     }

//     canvas.drawLine(a, b, linePaint);

//     canvas.drawCircle(b, 5, pointPaint);

//     final value = lengthMeters;

//     if (value == null) {
//       return;
//     }

//     final midpoint = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

//     final textPainter = TextPainter(
//       text: TextSpan(
//         text: '${value.toStringAsFixed(2)} m',

//         style: const TextStyle(
//           color: Colors.white,

//           fontSize: 12,

//           fontWeight: FontWeight.w800,

//           backgroundColor: Color(0xFF2563EB),
//         ),
//       ),

//       textDirection: TextDirection.ltr,
//     );

//     textPainter.layout();

//     textPainter.paint(
//       canvas,
//       midpoint - Offset(textPainter.width / 2, textPainter.height / 2),
//     );
//   }

//   @override
//   bool shouldRepaint(covariant _LengthPainter oldDelegate) {
//     return oldDelegate.pointA != pointA ||
//         oldDelegate.pointB != pointB ||
//         oldDelegate.lengthMeters != lengthMeters;
//   }
// }

// class _TakeOffHeader extends StatelessWidget {
//   const _TakeOffHeader({required this.drawing, required this.onBack});

//   final DrawingSheet drawing;

//   final VoidCallback onBack;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       height: 72,

//       padding: const EdgeInsets.symmetric(horizontal: 18),

//       decoration: const BoxDecoration(
//         color: Colors.white,

//         border: Border(bottom: BorderSide(color: Color(0xFFE4E7EC))),
//       ),

//       child: Row(
//         children: [
//           IconButton(
//             onPressed: onBack,

//             icon: const Icon(Icons.arrow_back_rounded),
//           ),

//           const SizedBox(width: 8),

//           Expanded(
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.center,

//               crossAxisAlignment: CrossAxisAlignment.start,

//               children: [
//                 Text(
//                   drawing.drawingNumber.trim().isEmpty
//                       ? 'Take-Off'
//                       : drawing.drawingNumber,

//                   style: const TextStyle(
//                     fontSize: 18,

//                     fontWeight: FontWeight.w900,

//                     color: Color(0xFF101828),
//                   ),
//                 ),

//                 if (drawing.title.trim().isNotEmpty)
//                   Text(
//                     drawing.title,

//                     overflow: TextOverflow.ellipsis,

//                     style: const TextStyle(
//                       color: Color(0xFF667085),

//                       fontSize: 12,
//                     ),
//                   ),
//               ],
//             ),
//           ),

//           if (!drawing.calibrated)
//             Container(
//               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),

//               decoration: BoxDecoration(
//                 color: const Color(0xFFFFFAEB),

//                 borderRadius: BorderRadius.circular(999),
//               ),

//               child: const Row(
//                 children: [
//                   Icon(
//                     Icons.warning_amber_rounded,

//                     size: 16,

//                     color: Color(0xFFB54708),
//                   ),

//                   SizedBox(width: 6),

//                   Text(
//                     'Calibration Required',

//                     style: TextStyle(
//                       color: Color(0xFFB54708),

//                       fontSize: 12,

//                       fontWeight: FontWeight.w800,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//         ],
//       ),
//     );
//   }
// }

// class _TakeOffToolbar extends StatelessWidget {
//   const _TakeOffToolbar({
//     required this.selectedMode,
//     required this.calibrated,
//     required this.onModeChanged,
//   });

//   final TakeOffMeasurementMode selectedMode;
//   final bool calibrated;

//   final ValueChanged<TakeOffMeasurementMode> onModeChanged;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: 76,
//       padding: const EdgeInsets.symmetric(vertical: 14),
//       decoration: const BoxDecoration(
//         color: Colors.white,
//         border: Border(right: BorderSide(color: Color(0xFFE4E7EC))),
//       ),
//       child: Column(
//         children: [
//           _ToolButton(
//             icon: Icons.pan_tool_outlined,
//             label: 'Pan',
//             selected: selectedMode == TakeOffMeasurementMode.pan,
//             onPressed: () {
//               onModeChanged(TakeOffMeasurementMode.pan);
//             },
//           ),
//           _ToolButton(
//             icon: Icons.near_me_outlined,
//             label: 'Select',
//             selected: selectedMode == TakeOffMeasurementMode.select,
//             onPressed: () {
//               onModeChanged(TakeOffMeasurementMode.select);
//             },
//           ),

//           _ToolButton(
//             icon: Icons.straighten_rounded,
//             label: 'Calibrate',
//             selected: selectedMode == TakeOffMeasurementMode.calibrate,
//             onPressed: () {
//               onModeChanged(TakeOffMeasurementMode.calibrate);
//             },
//           ),

//           const Padding(
//             padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//             child: Divider(),
//           ),

//           _ToolButton(
//             icon: Icons.straighten_outlined,
//             label: 'Length',
//             enabled: calibrated,
//             selected: selectedMode == TakeOffMeasurementMode.length,
//             onPressed: () {
//               onModeChanged(TakeOffMeasurementMode.length);
//             },
//           ),

//           _ToolButton(
//             icon: Icons.crop_square_outlined,
//             label: 'Area',
//             enabled: calibrated,
//             selected: selectedMode == TakeOffMeasurementMode.area,
//             onPressed: () {
//               onModeChanged(TakeOffMeasurementMode.area);
//             },
//           ),

//           _ToolButton(
//             icon: Icons.pin_outlined,
//             label: 'Count',
//             selected: selectedMode == TakeOffMeasurementMode.count,
//             onPressed: () {
//               onModeChanged(TakeOffMeasurementMode.count);
//             },
//           ),

//           _ToolButton(
//             icon: Icons.view_in_ar_outlined,
//             label: 'Volume',
//             enabled: calibrated,
//             selected: selectedMode == TakeOffMeasurementMode.volume,
//             onPressed: () {
//               onModeChanged(TakeOffMeasurementMode.volume);
//             },
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _ToolButton extends StatelessWidget {
//   const _ToolButton({
//     required this.icon,
//     required this.label,
//     required this.selected,
//     required this.onPressed,
//     this.enabled = true,
//   });

//   final IconData icon;
//   final String label;
//   final bool selected;
//   final bool enabled;
//   final VoidCallback onPressed;

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//       child: Tooltip(
//         message: enabled ? label : 'Calibrate drawing first',
//         child: InkWell(
//           borderRadius: BorderRadius.circular(12),

//           onTap: enabled ? onPressed : null,

//           child: Opacity(
//             opacity: enabled ? 1.0 : 0.35,

//             child: Container(
//               width: 58,

//               padding: const EdgeInsets.symmetric(vertical: 10),

//               decoration: BoxDecoration(
//                 color: selected ? const Color(0xFFEEF4FF) : Colors.transparent,

//                 borderRadius: BorderRadius.circular(12),
//               ),

//               child: Column(
//                 mainAxisSize: MainAxisSize.min,

//                 children: [
//                   Icon(
//                     icon,

//                     color:
//                         selected
//                             ? const Color(0xFF3538CD)
//                             : const Color(0xFF667085),
//                   ),

//                   const SizedBox(height: 4),

//                   Text(
//                     label,

//                     textAlign: TextAlign.center,

//                     style: TextStyle(
//                       fontSize: 10,

//                       fontWeight: selected ? FontWeight.w800 : FontWeight.w600,

//                       color:
//                           selected
//                               ? const Color(0xFF3538CD)
//                               : const Color(0xFF667085),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _TakeOffSidePanel extends StatelessWidget {
//   const _TakeOffSidePanel({
//     required this.drawing,
//     required this.selectedMode,
//     required this.selectedCategory,
//     required this.selectedSubToolId,
//     required this.onCategoryChanged,
//     required this.onSubToolSelected,
//     required this.selectedMeasurement,
//     required this.onEditSelectedMeasurement,
//     required this.onDeleteSelectedMeasurement,
//   });

//   final DrawingSheet drawing;

//   final TakeOffMeasurementMode selectedMode;

//   final TakeOffCategory? selectedCategory;

//   final ValueChanged<TakeOffCategory> onCategoryChanged;
//   final String? selectedSubToolId;

//   final ValueChanged<String> onSubToolSelected;

//   final TakeOffMeasurement? selectedMeasurement;

//   final VoidCallback onEditSelectedMeasurement;

//   final VoidCallback onDeleteSelectedMeasurement;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       height: double.infinity,
//       padding: const EdgeInsets.all(18),
//       decoration: const BoxDecoration(
//         color: Colors.white,
//         border: Border(left: BorderSide(color: Color(0xFFE4E7EC))),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Text(
//             'Take-Off',
//             style: TextStyle(
//               fontSize: 18,
//               fontWeight: FontWeight.w900,
//               color: Color(0xFF101828),
//             ),
//           ),

//           const SizedBox(height: 4),

//           Text(
//             _modeLabel(selectedMode),
//             style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
//           ),

//           const SizedBox(height: 20),

//           const Text(
//             'Construction Category',
//             style: TextStyle(
//               fontWeight: FontWeight.w900,
//               color: Color(0xFF344054),
//             ),
//           ),

//           const SizedBox(height: 12),

//           Expanded(
//             child: SingleChildScrollView(
//               child: Wrap(
//                 spacing: 8,
//                 runSpacing: 8,
//                 children:
//                     TakeOffCategory.values.map((category) {
//                       final selected = category == selectedCategory;

//                       return _CategoryChip(
//                         category: category,

//                         selected: selected,

//                         onPressed: () {
//                           onCategoryChanged(category);
//                         },
//                       );
//                     }).toList(),
//               ),
//             ),
//           ),
//           if (selectedMeasurement != null) ...[
//             const Divider(),

//             const Text(
//               'Selected Measurement',
//               style: TextStyle(fontWeight: FontWeight.w900),
//             ),

//             const SizedBox(height: 10),

//             Text(
//               '${selectedMeasurement!.quantity.toStringAsFixed(3)} '
//               '${selectedMeasurement!.unit}',
//             ),

//             const SizedBox(height: 12),

//             Row(
//               children: [
//                 Expanded(
//                   child: OutlinedButton.icon(
//                     onPressed: () {
//                       onEditSelectedMeasurement();
//                     },
//                     icon: const Icon(Icons.edit_outlined),
//                     label: const Text('Edit'),
//                   ),
//                 ),

//                 const SizedBox(width: 8),

//                 Expanded(
//                   child: OutlinedButton.icon(
//                     onPressed: () {
//                       onDeleteSelectedMeasurement();
//                     },
//                     icon: const Icon(Icons.delete_outline),
//                     label: const Text('Delete'),
//                   ),
//                 ),
//               ],
//             ),
//           ],

//           // if (selectedCategory != null) ...[
//           //   const Divider(),

//           //   const SizedBox(height: 10),

//           //   _CategoryToolPanel(
//           //     category: selectedCategory!,
//           //     selectedSubToolId: selectedSubToolId,
//           //     onSubToolSelected: onSubToolSelected,
//           //   ),
//           // ],
//         ],
//       ),
//     );
//   }

//   static String _modeLabel(TakeOffMeasurementMode mode) {
//     switch (mode) {
//       case TakeOffMeasurementMode.pan:
//         return 'Pan / Zoom Mode';
//       case TakeOffMeasurementMode.select:
//         return 'Select Mode';

//       case TakeOffMeasurementMode.calibrate:
//         return 'Calibration Mode';

//       case TakeOffMeasurementMode.length:
//         return 'Length Measurement';

//       case TakeOffMeasurementMode.area:
//         return 'Area Measurement';

//       case TakeOffMeasurementMode.count:
//         return 'Count Measurement';

//       case TakeOffMeasurementMode.volume:
//         return 'Volume Measurement';
//     }
//   }

//   Future<void> deleteMeasurement({
//     required String projectId,
//     required String facilityId,
//     required String measurementId,
//   }) async {
//     // Delegate deletion to the TakeOffMeasurementService.
//     await TakeOffMeasurementService.instance.deleteMeasurement(
//       projectId: projectId,
//       facilityId: facilityId,
//       measurementId: measurementId,
//     );
//   }
// }

// class _CalibrationOverlay extends StatelessWidget {
//   const _CalibrationOverlay({required this.pointA, required this.pointB});

//   final Offset? pointA;
//   final Offset? pointB;

//   @override
//   Widget build(BuildContext context) {
//     return IgnorePointer(
//       child: CustomPaint(
//         painter: _CalibrationPainter(pointA: pointA, pointB: pointB),
//       ),
//     );
//   }
// }

// // class _CalibrationOverlay extends StatelessWidget {
// //   const _CalibrationOverlay({
// //     required this.controller,
// //     required this.pointA,
// //     required this.pointB,
// //   });

// //   final PdfControllerPinch controller;
// //   final Offset? pointA;
// //   final Offset? pointB;

// //   @override
// //   Widget build(BuildContext context) {
// //     return AnimatedBuilder(
// //       animation: controller,
// //       builder: (context, child) {
// //         final matrix = controller.value;

// //         Offset? screenA;
// //         Offset? screenB;

// //         if (pointA != null) {
// //           screenA = MatrixUtils.transformPoint(matrix, pointA!);
// //         }

// //         if (pointB != null) {
// //           screenB = MatrixUtils.transformPoint(matrix, pointB!);
// //         }

// //         return IgnorePointer(
// //           child: CustomPaint(
// //             painter: _CalibrationPainter(pointA: screenA, pointB: screenB),
// //           ),
// //         );
// //       },
// //     );
// //   }
// // }

// class _CalibrationPainter extends CustomPainter {
//   const _CalibrationPainter({required this.pointA, required this.pointB});

//   final Offset? pointA;
//   final Offset? pointB;

//   @override
//   void paint(Canvas canvas, Size size) {
//     final a = pointA;

//     if (a == null) {
//       return;
//     }

//     final linePaint =
//         Paint()
//           ..color = const Color(0xFFDC2626)
//           ..strokeWidth = 2.5
//           ..style = PaintingStyle.stroke;

//     final pointPaint =
//         Paint()
//           ..color = const Color(0xFFDC2626)
//           ..style = PaintingStyle.fill;

//     //
//     // Point A
//     //
//     canvas.drawCircle(a, 6, pointPaint);

//     canvas.drawCircle(a, 11, linePaint);

//     final b = pointB;

//     if (b == null) {
//       return;
//     }

//     //
//     // Line A-B
//     //
//     canvas.drawLine(a, b, linePaint);

//     //
//     // Point B
//     //
//     canvas.drawCircle(b, 6, pointPaint);

//     canvas.drawCircle(b, 11, linePaint);

//     //
//     // Labels
//     //
//     _drawLabel(canvas, 'A', a + const Offset(10, -24));

//     _drawLabel(canvas, 'B', b + const Offset(10, -24));
//   }

//   void _drawLabel(Canvas canvas, String text, Offset position) {
//     final painter = TextPainter(
//       text: TextSpan(
//         text: text,
//         style: const TextStyle(
//           color: Colors.white,
//           fontSize: 11,
//           fontWeight: FontWeight.w900,
//           backgroundColor: Color(0xFFDC2626),
//         ),
//       ),
//       textDirection: TextDirection.ltr,
//     );

//     painter.layout();

//     painter.paint(canvas, position);
//   }

//   @override
//   bool shouldRepaint(covariant _CalibrationPainter oldDelegate) {
//     return oldDelegate.pointA != pointA || oldDelegate.pointB != pointB;
//   }
// }

// class _CategoryChip extends StatelessWidget {
//   const _CategoryChip({
//     required this.category,
//     required this.selected,
//     required this.onPressed,
//   });

//   final TakeOffCategory category;
//   final bool selected;
//   final VoidCallback onPressed;

//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       onTap: onPressed,
//       borderRadius: BorderRadius.circular(12),
//       child: Container(
//         width: 135,
//         padding: const EdgeInsets.all(12),
//         decoration: BoxDecoration(
//           color: selected ? const Color(0xFFEEF4FF) : const Color(0xFFF9FAFB),
//           borderRadius: BorderRadius.circular(12),
//           border: Border.all(
//             color: selected ? const Color(0xFF6172F3) : const Color(0xFFE4E7EC),
//           ),
//         ),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Icon(
//               category.icon,
//               size: 20,
//               color:
//                   selected ? const Color(0xFF3538CD) : const Color(0xFF667085),
//             ),

//             const SizedBox(height: 8),

//             Text(
//               category.label,
//               style: TextStyle(
//                 fontSize: 11,
//                 fontWeight: FontWeight.w800,
//                 color:
//                     selected
//                         ? const Color(0xFF3538CD)
//                         : const Color(0xFF344054),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _CategoryToolPanel extends StatelessWidget {
//   const _CategoryToolPanel({
//     required this.category,
//     required this.selectedSubToolId,
//     required this.onSubToolSelected,
//   });

//   final TakeOffCategory category;
//   final String? selectedSubToolId;

//   final ValueChanged<String> onSubToolSelected;

//   @override
//   Widget build(BuildContext context) {
//     final tools = _toolsForCategory(category);

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           category.label,
//           style: const TextStyle(
//             fontSize: 15,
//             fontWeight: FontWeight.w900,
//             color: Color(0xFF101828),
//           ),
//         ),

//         const SizedBox(height: 10),

//         ...tools.map((tool) {
//           final selected = tool.id == selectedSubToolId;

//           return Padding(
//             padding: const EdgeInsets.only(bottom: 8),
//             child: InkWell(
//               borderRadius: BorderRadius.circular(10),

//               onTap: () {
//                 onSubToolSelected(tool.id);
//               },

//               child: Container(
//                 width: double.infinity,

//                 padding: const EdgeInsets.symmetric(
//                   horizontal: 12,
//                   vertical: 11,
//                 ),

//                 decoration: BoxDecoration(
//                   color:
//                       selected
//                           ? const Color(0xFFEEF4FF)
//                           : const Color(0xFFF9FAFB),

//                   borderRadius: BorderRadius.circular(10),

//                   border: Border.all(
//                     color:
//                         selected
//                             ? const Color(0xFF6172F3)
//                             : const Color(0xFFE4E7EC),
//                   ),
//                 ),

//                 child: Row(
//                   children: [
//                     Expanded(
//                       child: Text(
//                         tool.label,

//                         style: TextStyle(
//                           color:
//                               selected
//                                   ? const Color(0xFF3538CD)
//                                   : const Color(0xFF344054),

//                           fontSize: 12,

//                           fontWeight: FontWeight.w700,
//                         ),
//                       ),
//                     ),

//                     if (selected)
//                       const Icon(
//                         Icons.check_circle_rounded,

//                         size: 17,

//                         color: Color(0xFF3538CD),
//                       ),
//                   ],
//                 ),
//               ),
//             ),
//           );
//         }),
//       ],
//     );
//   }

//   static List<TakeOffSubTool> _toolsForCategory(TakeOffCategory category) {
//     switch (category) {
//       case TakeOffCategory.wallsFinishes:
//         return const [
//           TakeOffSubTool(id: 'blockwork', label: 'Blockwork / Brickwork'),
//           TakeOffSubTool(id: 'plaster', label: 'Plaster / Render'),
//           TakeOffSubTool(id: 'painting', label: 'Painting'),
//           TakeOffSubTool(id: 'wall_tiles', label: 'Wall Tiles'),
//           TakeOffSubTool(id: 'skirting', label: 'Skirting'),
//           TakeOffSubTool(id: 'dpc', label: 'DPC'),
//         ];

//       case TakeOffCategory.beamsLintels:
//         return const [
//           TakeOffSubTool(id: 'beam_concrete', label: 'Concrete'),
//           TakeOffSubTool(id: 'beam_formwork', label: 'Formwork'),
//           TakeOffSubTool(id: 'beam_reinforcement', label: 'Reinforcement'),
//           TakeOffSubTool(id: 'lintels', label: 'Lintels'),
//         ];

//       case TakeOffCategory.slabsFloors:
//         return const [
//           TakeOffSubTool(id: 'slab_concrete', label: 'Concrete Slab'),
//           TakeOffSubTool(id: 'slab_formwork', label: 'Formwork'),
//           TakeOffSubTool(id: 'slab_reinforcement', label: 'Reinforcement'),
//           TakeOffSubTool(id: 'floor_finish', label: 'Floor Finish'),
//           TakeOffSubTool(id: 'screed', label: 'Screed'),
//         ];

//       case TakeOffCategory.foundations:
//         return const [
//           TakeOffSubTool(id: 'excavation', label: 'Excavation'),
//           TakeOffSubTool(id: 'blinding', label: 'Blinding'),
//           TakeOffSubTool(id: 'strip_footing', label: 'Strip Footing'),
//           TakeOffSubTool(id: 'pad_footing', label: 'Pad Footing'),
//           TakeOffSubTool(id: 'raft_foundation', label: 'Raft Foundation'),
//           TakeOffSubTool(id: 'ground_beam', label: 'Ground Beam'),
//           TakeOffSubTool(id: 'backfilling', label: 'Backfilling'),
//         ];

//       case TakeOffCategory.stairsRamps:
//         return const [
//           TakeOffSubTool(id: 'stairs_concrete', label: 'Concrete'),
//           TakeOffSubTool(id: 'stairs_formwork', label: 'Formwork'),
//           TakeOffSubTool(id: 'stairs_reinforcement', label: 'Reinforcement'),
//           TakeOffSubTool(id: 'stairs_finishes', label: 'Finishes'),
//         ];

//       case TakeOffCategory.roofCoverings:
//         return const [
//           TakeOffSubTool(id: 'roof_covering', label: 'Roof Sheet / Tile Area'),
//           TakeOffSubTool(id: 'ridge', label: 'Ridge'),
//           TakeOffSubTool(id: 'valley', label: 'Valley'),
//           TakeOffSubTool(id: 'flashing', label: 'Flashing'),
//           TakeOffSubTool(id: 'gutters', label: 'Gutters'),
//         ];

//       case TakeOffCategory.roofStructure:
//         return const [
//           TakeOffSubTool(id: 'trusses', label: 'Trusses'),
//           TakeOffSubTool(id: 'rafters', label: 'Rafters'),
//           TakeOffSubTool(id: 'purlins', label: 'Purlins'),
//           TakeOffSubTool(id: 'battens', label: 'Battens'),
//           TakeOffSubTool(id: 'bracing', label: 'Bracing'),
//         ];

//       case TakeOffCategory.roadsKerbs:
//         return const [
//           TakeOffSubTool(id: 'road_area', label: 'Road Area'),
//           TakeOffSubTool(id: 'road_excavation', label: 'Excavation'),
//           TakeOffSubTool(id: 'subbase', label: 'Subbase'),
//           TakeOffSubTool(id: 'basecourse', label: 'Basecourse'),
//           TakeOffSubTool(id: 'kerbs', label: 'Kerbs'),
//           TakeOffSubTool(id: 'paving', label: 'Paving'),
//         ];

//       case TakeOffCategory.areasVolumes:
//         return const [
//           TakeOffSubTool(id: 'general_area', label: 'General Area'),
//           TakeOffSubTool(id: 'general_volume', label: 'General Volume'),
//           TakeOffSubTool(id: 'perimeter', label: 'Perimeter'),
//         ];

//       case TakeOffCategory.doorsWindows:
//         return const [
//           TakeOffSubTool(id: 'doors', label: 'Doors'),
//           TakeOffSubTool(id: 'windows', label: 'Windows'),
//           TakeOffSubTool(id: 'frames', label: 'Frames'),
//           TakeOffSubTool(id: 'ironmongery', label: 'Ironmongery'),
//         ];

//       case TakeOffCategory.servicesPipework:
//         return const [
//           TakeOffSubTool(id: 'pipe_length', label: 'Pipe Length'),
//           TakeOffSubTool(id: 'fittings', label: 'Fittings'),
//           TakeOffSubTool(id: 'fixtures', label: 'Fixtures'),
//           TakeOffSubTool(id: 'cable_conduit', label: 'Cable / Conduit'),
//         ];

//       case TakeOffCategory.boqVerification:
//         return const [
//           TakeOffSubTool(id: 'compare_boq', label: 'Compare BOQ Quantity'),
//           TakeOffSubTool(id: 'variance', label: 'Flag Variance'),
//           TakeOffSubTool(id: 'measurement_audit', label: 'Measurement Audit'),
//         ];
//     }
//   }
// }

// class _CalibrationInput {
//   const _CalibrationInput({required this.distance, required this.unit});

//   final double distance;
//   final String unit;
// }

// class _SavedMeasurementsOverlay extends StatelessWidget {
//   const _SavedMeasurementsOverlay({
//     required this.controller,
//     required this.measurements,
//     required this.selectedMeasurementId,
//   });

//   final PdfControllerPinch controller;
//   final List<TakeOffMeasurement> measurements;
//   final String? selectedMeasurementId;

//   @override
//   Widget build(BuildContext context) {
//     return AnimatedBuilder(
//       animation: controller,
//       builder: (context, child) {
//         final matrix = controller.value;

//         return CustomPaint(
//           painter: _SavedMeasurementsPainter(
//             matrix: matrix,

//             measurements: measurements,

//             selectedMeasurementId: selectedMeasurementId,
//           ),
//         );
//       },
//     );
//   }
// }

// // class _SavedMeasurementsOverlay extends StatelessWidget {
// //   const _SavedMeasurementsOverlay({
// //     required this.controller,
// //     required this.measurements,
// //   });

// //   final PdfControllerPinch controller;

// //   final List<TakeOffMeasurement> measurements;

// //   @override
// //   Widget build(BuildContext context) {
// //     return AnimatedBuilder(
// //       animation: controller,

// //       builder: (context, child) {
// //         final matrix = controller.value;

// //         return CustomPaint(
// //           painter: _SavedMeasurementsPainter(
// //             matrix: matrix,

// //             measurements: measurements,
// //           ),
// //         );
// //       },
// //     );
// //   }
// // }

// class _SavedMeasurementsPainter extends CustomPainter {
//   const _SavedMeasurementsPainter({
//     required this.matrix,
//     required this.measurements,
//     required this.selectedMeasurementId,
//   });

//   final Matrix4 matrix;
//   final List<TakeOffMeasurement> measurements;
//   final String? selectedMeasurementId;

//   @override
//   void paint(Canvas canvas, Size size) {
//     for (final measurement in measurements) {
//       if (measurement.measurementType != 'length') {
//         continue;
//       }

//       final isSelected = measurement.id == selectedMeasurementId;

//       final lineColor =
//           isSelected ? const Color(0xFFF59E0B) : const Color(0xFF2563EB);

//       final linePaint =
//           Paint()
//             ..color = lineColor
//             ..strokeWidth = isSelected ? 4.0 : 2.2
//             ..strokeCap = StrokeCap.round
//             ..style = PaintingStyle.stroke;

//       final pointPaint =
//           Paint()
//             ..color = lineColor
//             ..style = PaintingStyle.fill;

//       final pointOutlinePaint =
//           Paint()
//             ..color = Colors.white
//             ..strokeWidth = 2
//             ..style = PaintingStyle.stroke;

//       //
//       // Stored PDF scene coordinates
//       //
//       final sceneA = Offset(measurement.pointAX, measurement.pointAY);

//       final sceneB = Offset(measurement.pointBX, measurement.pointBY);

//       //
//       // Convert scene coordinates to current
//       // viewport coordinates so measurements
//       // remain aligned while zooming/panning.
//       //
//       final screenA = MatrixUtils.transformPoint(matrix, sceneA);

//       final screenB = MatrixUtils.transformPoint(matrix, sceneB);

//       //
//       // Main measurement line
//       //
//       canvas.drawLine(screenA, screenB, linePaint);

//       //
//       // End points
//       //
//       final pointRadius = isSelected ? 6.0 : 4.0;

//       canvas.drawCircle(screenA, pointRadius, pointPaint);

//       canvas.drawCircle(screenB, pointRadius, pointPaint);

//       //
//       // Give selected endpoints a white
//       // outline so editing handles are clear.
//       //
//       if (isSelected) {
//         canvas.drawCircle(screenA, 9, pointOutlinePaint);

//         canvas.drawCircle(screenB, 9, pointOutlinePaint);
//       }

//       //
//       // Measurement label
//       //
//       final midpoint = Offset(
//         (screenA.dx + screenB.dx) / 2,
//         (screenA.dy + screenB.dy) / 2,
//       );

//       final label =
//           '${measurement.quantity.toStringAsFixed(2)} '
//           '${measurement.unit.isEmpty ? 'm' : measurement.unit}';

//       final textPainter = TextPainter(
//         text: TextSpan(
//           text: label,
//           style: const TextStyle(
//             color: Colors.white,
//             fontSize: 11,
//             fontWeight: FontWeight.w800,
//           ),
//         ),
//         textDirection: TextDirection.ltr,
//       );

//       textPainter.layout();

//       //
//       // Draw proper rounded label background
//       // instead of TextStyle.backgroundColor.
//       //
//       const horizontalPadding = 7.0;
//       const verticalPadding = 4.0;

//       final labelRect = Rect.fromCenter(
//         center: midpoint,
//         width: textPainter.width + (horizontalPadding * 2),
//         height: textPainter.height + (verticalPadding * 2),
//       );

//       final labelBackground =
//           Paint()
//             ..color = lineColor
//             ..style = PaintingStyle.fill;

//       canvas.drawRRect(
//         RRect.fromRectAndRadius(labelRect, const Radius.circular(6)),
//         labelBackground,
//       );

//       textPainter.paint(
//         canvas,
//         Offset(
//           labelRect.left + horizontalPadding,
//           labelRect.top + verticalPadding,
//         ),
//       );

//       //
//       // Selected marker.
//       //
//       if (isSelected) {
//         _drawSelectedBadge(canvas, screenA);
//       }
//     }
//   }

//   void _drawSelectedBadge(Canvas canvas, Offset anchor) {
//     const text = 'SELECTED';

//     final textPainter = TextPainter(
//       text: const TextSpan(
//         text: text,
//         style: TextStyle(
//           color: Colors.white,
//           fontSize: 9,
//           fontWeight: FontWeight.w900,
//         ),
//       ),
//       textDirection: TextDirection.ltr,
//     );

//     textPainter.layout();

//     const horizontalPadding = 6.0;
//     const verticalPadding = 3.0;

//     final position = anchor + const Offset(12, -22);

//     final rect = Rect.fromLTWH(
//       position.dx,
//       position.dy,
//       textPainter.width + (horizontalPadding * 2),
//       textPainter.height + (verticalPadding * 2),
//     );

//     final backgroundPaint =
//         Paint()
//           ..color = const Color(0xFFF59E0B)
//           ..style = PaintingStyle.fill;

//     canvas.drawRRect(
//       RRect.fromRectAndRadius(rect, const Radius.circular(5)),
//       backgroundPaint,
//     );

//     textPainter.paint(
//       canvas,
//       Offset(rect.left + horizontalPadding, rect.top + verticalPadding),
//     );
//   }

//   @override
//   bool shouldRepaint(covariant _SavedMeasurementsPainter oldDelegate) {
//     return oldDelegate.matrix != matrix ||
//         oldDelegate.measurements != measurements ||
//         oldDelegate.selectedMeasurementId != selectedMeasurementId;
//   }
// }

// // class _SavedMeasurementsPainter extends CustomPainter {
// //   const _SavedMeasurementsPainter({
// //     required this.matrix,
// //     required this.measurements,
// //   });

// //   final Matrix4 matrix;

// //   final List<TakeOffMeasurement> measurements;

// //   @override
// //   void paint(Canvas canvas, Size size) {
// //     final linePaint =
// //         Paint()
// //           ..color = const Color(0xFF2563EB)
// //           ..strokeWidth = 2.2
// //           ..style = PaintingStyle.stroke;

// //     final pointPaint =
// //         Paint()
// //           ..color = const Color(0xFF2563EB)
// //           ..style = PaintingStyle.fill;

// //     for (final measurement in measurements) {
// //       if (measurement.measurementType != 'length') {
// //         continue;
// //       }

// //       final sceneA = Offset(measurement.pointAX, measurement.pointAY);

// //       final sceneB = Offset(measurement.pointBX, measurement.pointBY);

// //       final screenA = MatrixUtils.transformPoint(matrix, sceneA);

// //       final screenB = MatrixUtils.transformPoint(matrix, sceneB);

// //       canvas.drawLine(screenA, screenB, linePaint);

// //       canvas.drawCircle(screenA, 4, pointPaint);

// //       canvas.drawCircle(screenB, 4, pointPaint);

// //       final midpoint = Offset(
// //         (screenA.dx + screenB.dx) / 2,

// //         (screenA.dy + screenB.dy) / 2,
// //       );

// //       final textPainter = TextPainter(
// //         text: TextSpan(
// //           text: '${measurement.quantity.toStringAsFixed(2)} m',

// //           style: const TextStyle(
// //             color: Colors.white,

// //             fontSize: 11,

// //             fontWeight: FontWeight.w800,

// //             backgroundColor: Color(0xFF2563EB),
// //           ),
// //         ),

// //         textDirection: TextDirection.ltr,
// //       );

// //       textPainter.layout();

// //       textPainter.paint(
// //         canvas,
// //         midpoint - Offset(textPainter.width / 2, textPainter.height / 2),
// //       );
// //     }
// //   }

// //   @override
// //   bool shouldRepaint(covariant _SavedMeasurementsPainter oldDelegate) {
// //     return oldDelegate.matrix != matrix ||
// //         oldDelegate.measurements != measurements;
// //   }
// // }
