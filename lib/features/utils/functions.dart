// import 'package:aqs/features/utils/helpers.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';

// Future<void> _openRebarSlabFromPolygon({
//   required List<Offset> polygon,
//   required Map<String, dynamic> drawingData,
// }) async {
//   // 1) Need calibration
//   final calibrated = drawingData['calibrated'] == true;
//   final pixelsPerUnitBase = (drawingData['pixelsPerUnit'] ?? 0).toDouble();

//   if (!calibrated || pixelsPerUnitBase <= 0) {
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(
//         content: Text(
//           'Please calibrate the drawing before slab rebar takeoff.',
//         ),
//       ),
//     );
//     return;
//   }

//   if (polygon.length < 3) return;

//   // 2) Bounding box of polygon (assumes roughly rectangular slab)
//   double minX = polygon.first.dx;
//   double maxX = polygon.first.dx;
//   double minY = polygon.first.dy;
//   double maxY = polygon.first.dy;

//   for (final p in polygon) {
//     if (p.dx < minX) minX = p.dx;
//     if (p.dx > maxX) maxX = p.dx;
//     if (p.dy < minY) minY = p.dy;
//     if (p.dy > maxY) maxY = p.dy;
//   }

//   final widthPx = maxX - minX;  // horizontal span
//   final heightPx = maxY - minY; // vertical span

//   final widthM = widthPx / pixelsPerUnitBase;
//   final heightM = heightPx / pixelsPerUnitBase;

//   if (widthM <= 0 || heightM <= 0) return;

//   // 3) Local data model for one rebar set
//   class _RebarSet {
//     final RebarMark mark;
//     final String direction; // 'horizontal' or 'vertical'
//     final double clearSpanM;
//     final double embedEachEndM;
//     final double extraLengthM;
//     final double barLengthM;
//     final double totalLengthM;
//     final double unitWeightKgPerM;
//     final double totalWeightKg;

//     _RebarSet({
//       required this.mark,
//       required this.direction,
//       required this.clearSpanM,
//       required this.embedEachEndM,
//       required this.extraLengthM,
//       required this.barLengthM,
//       required this.totalLengthM,
//       required this.unitWeightKgPerM,
//       required this.totalWeightKg,
//     });
//   }

//   final markController = TextEditingController();
//   final embedController = TextEditingController(text: '0.20'); // m each end
//   final extraController = TextEditingController(text: '0.00'); // extra laps m
//   String barDirection = 'horizontal'; // default

//   String? parseError;
//   _RebarSet? previewSet;

//   final List<_RebarSet> sets = [];

//   // draggable offset
//   Offset dialogOffset = const Offset(0, 0);

//   double _spanForDirection(String dir) =>
//       dir == 'horizontal' ? widthM : heightM;

//   void recomputePreview(StateSetter setStateDialog) {
//     final rawMark = markController.text.trim();
//     final embedStr = embedController.text.trim();
//     final extraStr = extraController.text.trim();

//     if (rawMark.isEmpty) {
//       setStateDialog(() {
//         parseError = null;
//         previewSet = null;
//       });
//       return;
//     }

//     try {
//       final m = RebarMark.parse(rawMark);
//       final embed = double.tryParse(embedStr) ?? 0.0;
//       final extra = double.tryParse(extraStr) ?? 0.0;

//       final span = _spanForDirection(barDirection);
//       final Lbar = span + 2 * embed + extra;
//       final Ltotal = m.quantity * Lbar;
//       final uw = rebarUnitWeightKgPerM(m.diameterMm);
//       final wTotal = Ltotal * uw;

//       setStateDialog(() {
//         parseError = null;
//         previewSet = _RebarSet(
//           mark: m,
//           direction: barDirection,
//           clearSpanM: span,
//           embedEachEndM: embed,
//           extraLengthM: extra,
//           barLengthM: Lbar,
//           totalLengthM: Ltotal,
//           unitWeightKgPerM: uw,
//           totalWeightKg: wTotal,
//         );
//       });
//     } catch (e) {
//       setStateDialog(() {
//         parseError = e.toString();
//         previewSet = null;
//       });
//     }
//   }

//   double get totalLengthAll =>
//       sets.fold(0.0, (sum, s) => sum + s.totalLengthM);

//   double get totalWeightAll =>
//       sets.fold(0.0, (sum, s) => sum + s.totalWeightKg);

//   final result = await showDialog<bool>(
//     context: context,
//     barrierDismissible: false,
//     builder: (ctx) {
//       return StatefulBuilder(
//         builder: (ctx, setStateDialog) {
//           return Stack(
//             children: [
//               Positioned(
//                 right: 24 - dialogOffset.dx,
//                 top: 80 + dialogOffset.dy,
//                 child: GestureDetector(
//                   onPanUpdate: (details) {
//                     setStateDialog(() {
//                       dialogOffset += details.delta;
//                     });
//                   },
//                   child: Material(
//                     elevation: 8,
//                     borderRadius: BorderRadius.circular(12),
//                     color: Theme.of(context).dialogBackgroundColor,
//                     child: ConstrainedBox(
//                       constraints: const BoxConstraints(maxWidth: 380),
//                       child: Padding(
//                         padding: const EdgeInsets.all(8.0),
//                         child: Column(
//                           mainAxisSize: MainAxisSize.min,
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             // HEADER
//                             Row(
//                               children: [
//                                 const Icon(Icons.drag_indicator, size: 18),
//                                 const SizedBox(width: 6),
//                                 const Expanded(
//                                   child: Text(
//                                     'Slab rebar (polygon)',
//                                     style: TextStyle(
//                                       fontWeight: FontWeight.w600,
//                                       fontSize: 14,
//                                     ),
//                                   ),
//                                 ),
//                                 IconButton(
//                                   padding: EdgeInsets.zero,
//                                   constraints: const BoxConstraints(),
//                                   icon: const Icon(Icons.close, size: 18),
//                                   onPressed: () => Navigator.pop(ctx, false),
//                                 ),
//                               ],
//                             ),
//                             const SizedBox(height: 6),

//                             // SLAB DIMENSIONS
//                             const Text(
//                               'Slab dimensions (from polygon):',
//                               style: TextStyle(
//                                 fontWeight: FontWeight.w600,
//                                 fontSize: 12,
//                               ),
//                             ),
//                             const SizedBox(height: 4),
//                             Text(
//                               'Horizontal span: ${widthM.toStringAsFixed(3)} m',
//                               style: const TextStyle(fontSize: 11),
//                             ),
//                             Text(
//                               'Vertical span:   ${heightM.toStringAsFixed(3)} m',
//                               style: const TextStyle(fontSize: 11),
//                             ),
//                             const SizedBox(height: 8),

//                             // DIRECTION
//                             const Text(
//                               'Bars direction (for NEW set):',
//                               style: TextStyle(
//                                 fontWeight: FontWeight.w600,
//                                 fontSize: 12,
//                               ),
//                             ),
//                             Row(
//                               children: [
//                                 Expanded(
//                                   child: RadioListTile<String>(
//                                     dense: true,
//                                     visualDensity: VisualDensity.compact,
//                                     contentPadding: EdgeInsets.zero,
//                                     title: const Text(
//                                       'Horizontal',
//                                       style: TextStyle(fontSize: 11),
//                                     ),
//                                     value: 'horizontal',
//                                     groupValue: barDirection,
//                                     onChanged: (v) {
//                                       if (v == null) return;
//                                       setStateDialog(() {
//                                         barDirection = v;
//                                       });
//                                       recomputePreview(setStateDialog);
//                                     },
//                                   ),
//                                 ),
//                                 Expanded(
//                                   child: RadioListTile<String>(
//                                     dense: true,
//                                     visualDensity: VisualDensity.compact,
//                                     contentPadding: EdgeInsets.zero,
//                                     title: const Text(
//                                       'Vertical',
//                                       style: TextStyle(fontSize: 11),
//                                     ),
//                                     value: 'vertical',
//                                     groupValue: barDirection,
//                                     onChanged: (v) {
//                                       if (v == null) return;
//                                       setStateDialog(() {
//                                         barDirection = v;
//                                       });
//                                       recomputePreview(setStateDialog);
//                                     },
//                                   ),
//                                 ),
//                               ],
//                             ),

//                             const SizedBox(height: 4),
//                             Text(
//                               'Current clear span: '
//                               '${_spanForDirection(barDirection).toStringAsFixed(3)} m',
//                               style: const TextStyle(
//                                 fontSize: 11,
//                                 fontWeight: FontWeight.w600,
//                               ),
//                             ),

//                             const SizedBox(height: 8),
//                             const Text(
//                               'Rebar mark (for NEW set):',
//                               style: TextStyle(
//                                 fontWeight: FontWeight.w600,
//                                 fontSize: 12,
//                               ),
//                             ),
//                             const SizedBox(height: 4),
//                             TextField(
//                               controller: markController,
//                               decoration: const InputDecoration(
//                                 hintText: 'e.g. 67Y12-11-200T1',
//                                 border: OutlineInputBorder(),
//                                 isDense: true,
//                               ),
//                               style: const TextStyle(fontSize: 12),
//                               onChanged: (_) => recomputePreview(setStateDialog),
//                             ),

//                             const SizedBox(height: 8),
//                             const Text(
//                               'Embed / extension each end (m):',
//                               style: TextStyle(
//                                 fontWeight: FontWeight.w600,
//                                 fontSize: 12,
//                               ),
//                             ),
//                             const SizedBox(height: 4),
//                             TextField(
//                               controller: embedController,
//                               keyboardType:
//                                   const TextInputType.numberWithOptions(
//                                 decimal: true,
//                               ),
//                               decoration: const InputDecoration(
//                                 border: OutlineInputBorder(),
//                                 isDense: true,
//                               ),
//                               style: const TextStyle(fontSize: 12),
//                               onChanged: (_) => recomputePreview(setStateDialog),
//                             ),

//                             const SizedBox(height: 8),
//                             const Text(
//                               'Extra length per bar (laps/hooks, m):',
//                               style: TextStyle(
//                                 fontWeight: FontWeight.w600,
//                                 fontSize: 12,
//                               ),
//                             ),
//                             const SizedBox(height: 4),
//                             TextField(
//                               controller: extraController,
//                               keyboardType:
//                                   const TextInputType.numberWithOptions(
//                                 decimal: true,
//                               ),
//                               decoration: const InputDecoration(
//                                 border: OutlineInputBorder(),
//                                 isDense: true,
//                               ),
//                               style: const TextStyle(fontSize: 12),
//                               onChanged: (_) => recomputePreview(setStateDialog),
//                             ),

//                             const SizedBox(height: 6),
//                             if (parseError != null)
//                               Text(
//                                 parseError!,
//                                 style: const TextStyle(
//                                   color: Colors.red,
//                                   fontSize: 11,
//                                 ),
//                               ),

//                             if (previewSet != null) ...[
//                               const SizedBox(height: 4),
//                               Text(
//                                 'Preview: ${previewSet!.mark.quantity}'
//                                 '${previewSet!.mark.barType} '
//                                 '@ ${previewSet!.mark.spacingMm} c/c '
//                                 '(${previewSet!.direction == 'horizontal' ? 'H' : 'V'})',
//                                 style: const TextStyle(fontSize: 11),
//                               ),
//                               Text(
//                                 'L/bar: ${previewSet!.barLengthM.toStringAsFixed(3)} m, '
//                                 'Total: ${previewSet!.totalLengthM.toStringAsFixed(3)} m',
//                                 style: const TextStyle(fontSize: 11),
//                               ),
//                               Text(
//                                 'Weight: ${previewSet!.unitWeightKgPerM.toStringAsFixed(3)} '
//                                 'kg/m → ${previewSet!.totalWeightKg.toStringAsFixed(1)} kg',
//                                 style: const TextStyle(fontSize: 11),
//                               ),
//                             ],

//                             const SizedBox(height: 6),
//                             Align(
//                               alignment: Alignment.centerRight,
//                               child: TextButton.icon(
//                                 icon: const Icon(Icons.add, size: 16),
//                                 label: const Text(
//                                   'Add rebar set',
//                                   style: TextStyle(fontSize: 12),
//                                 ),
//                                 onPressed: () {
//                                   if (previewSet == null) return;
//                                   setStateDialog(() {
//                                     sets.add(previewSet!);
//                                     // clear only mark; keep embed/extra/direction
//                                     markController.clear();
//                                     previewSet = null;
//                                     parseError = null;
//                                   });
//                                 },
//                               ),
//                             ),

//                             if (sets.isNotEmpty) ...[
//                               const Divider(),
//                               const Text(
//                                 'Added rebar sets:',
//                                 style: TextStyle(
//                                   fontWeight: FontWeight.w600,
//                                   fontSize: 12,
//                                 ),
//                               ),
//                               const SizedBox(height: 4),
//                               SizedBox(
//                                 height: 120,
//                                 child: ListView.builder(
//                                   itemCount: sets.length,
//                                   itemBuilder: (ctx, i) {
//                                     final s = sets[i];
//                                     return Row(
//                                       crossAxisAlignment:
//                                           CrossAxisAlignment.start,
//                                       children: [
//                                         Expanded(
//                                           child: Text(
//                                             '${i + 1}. '
//                                             '${s.mark.quantity}${s.mark.barType}'
//                                             '-${s.mark.spacingMm}${s.mark.layer} '
//                                             '(${s.direction == 'horizontal' ? 'H' : 'V'})\n'
//                                             'L/bar ${s.barLengthM.toStringAsFixed(3)} m, '
//                                             'Total ${s.totalLengthM.toStringAsFixed(3)} m, '
//                                             '${s.totalWeightKg.toStringAsFixed(1)} kg',
//                                             style: const TextStyle(
//                                               fontSize: 11,
//                                             ),
//                                           ),
//                                         ),
//                                         IconButton(
//                                           padding: EdgeInsets.zero,
//                                           constraints: const BoxConstraints(),
//                                           icon: const Icon(
//                                             Icons.delete_outline,
//                                             size: 16,
//                                           ),
//                                           onPressed: () {
//                                             setStateDialog(() {
//                                               sets.removeAt(i);
//                                             });
//                                           },
//                                         ),
//                                       ],
//                                     );
//                                   },
//                                 ),
//                               ),
//                               const SizedBox(height: 4),
//                               Text(
//                                 'TOTAL length: ${totalLengthAll.toStringAsFixed(3)} m',
//                                 style: const TextStyle(
//                                   fontSize: 11,
//                                   fontWeight: FontWeight.w600,
//                                 ),
//                               ),
//                               Text(
//                                 'TOTAL weight: ${totalWeightAll.toStringAsFixed(1)} kg',
//                                 style: const TextStyle(
//                                   fontSize: 11,
//                                   fontWeight: FontWeight.w600,
//                                 ),
//                               ),
//                             ],

//                             const SizedBox(height: 8),
//                             Row(
//                               mainAxisAlignment: MainAxisAlignment.end,
//                               children: [
//                                 TextButton(
//                                   onPressed: () => Navigator.pop(ctx, false),
//                                   child: const Text(
//                                     'Cancel',
//                                     style: TextStyle(fontSize: 12),
//                                   ),
//                                 ),
//                                 const SizedBox(width: 8),
//                                 FilledButton(
//                                   onPressed:
//                                       sets.isNotEmpty
//                                           ? () => Navigator.pop(ctx, true)
//                                           : null,
//                                   child: const Text(
//                                     'Save',
//                                     style: TextStyle(fontSize: 12),
//                                   ),
//                                 ),
//                               ],
//                             ),
//                           ],
//                         ),
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//             ],
//           );
//         },
//       );
//     },
//   );

//   if (result != true) return;

//   // 4) Save each rebar set as one measurement doc
//   try {
//     // polygon to store
//     final polyData = polygon.map((p) => {'x': p.dx, 'y': p.dy}).toList();

//     // slab center for drawing "representative" line
//     final centerY = (minY + maxY) / 2;
//     final centerX = (minX + maxX) / 2;

//     for (final s in sets) {
//       late Offset p1;
//       late Offset p2;

//       if (s.direction == 'horizontal') {
//         p1 = Offset(minX, centerY);
//         p2 = Offset(maxX, centerY);
//       } else {
//         p1 = Offset(centerX, minY);
//         p2 = Offset(centerX, maxY);
//       }

//       await _saveRebarSlabMeasurement(
//         mark: s.mark,
//         clearSpanM: s.clearSpanM,
//         embedEachEndM: s.embedEachEndM,
//         extraLengthM: s.extraLengthM,
//         barLengthM: s.barLengthM,
//         totalLengthM: s.totalLengthM,
//         unitWeightKgPerM: s.unitWeightKgPerM,
//         totalWeightKg: s.totalWeightKg,
//         p1: p1,
//         p2: p2,
//         polygon: polyData, // 👈 store area
//       );
//     }

//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('Slab rebar sets saved')),
//     );
//   } catch (e) {
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text('Error saving rebar slab: $e')),
//     );
//   }
// }

// Future<void> _saveRebarSlabMeasurement({
//   required RebarMark mark,
//   required double clearSpanM,
//   required double embedEachEndM,
//   required double extraLengthM,
//   required double barLengthM,
//   required double totalLengthM,
//   required double unitWeightKgPerM,
//   required double totalWeightKg,
//   required Offset p1,
//   required Offset p2,
//   List<Map<String, double>>? polygon,   // 👈 NEW (nullable)
// }) async {
//   if (_activeBoqCode == null || _activeBoqCode!.trim().isEmpty) return;

//   final unit = _activeUnit ?? 'kg';

//   double value;
//   if (unit == 'kg' || unit == 'tonne') {
//     value = totalWeightKg;
//   } else if (unit == 'm') {
//     value = totalLengthM;
//   } else {
//     value = totalLengthM;
//   }

//   await _measurementsRef.add({
//     'projectId': widget.projectId,
//     'drawingId': widget.drawingId,
//     'type': 'rebarSlab',
//     'label': _activeLabel,
//     'boqCode': _activeBoqCode,
//     'unit': unit,

//     'markRaw':
//         '${mark.quantity}${mark.barType}-${mark.spacingMm}${mark.layer}',
//     'quantity': mark.quantity,
//     'barType': mark.barType,
//     'diameterMm': mark.diameterMm,
//     'spacingMm': mark.spacingMm,
//     'layer': mark.layer,

//     'clearSpanM': clearSpanM,
//     'embedEachEndM': embedEachEndM,
//     'extraLengthM': extraLengthM,
//     'barLengthM': barLengthM,
//     'totalLengthM': totalLengthM,

//     'unitWeightKgPerM': unitWeightKgPerM,
//     'totalWeightKg': totalWeightKg,

//     'value': value,

//     'color': _currentColor.value,
//     'p1': {'x': p1.dx, 'y': p1.dy},
//     'p2': {'x': p2.dx, 'y': p2.dy},

//     if (polygon != null) 'polygon': polygon, // 👈 save slab area

//     'createdAt': FieldValue.serverTimestamp(),
//   });
// }

// // Future<void> _openRebarSlabFromPolygon({
// //   required List<Offset> polygon,
// //   required Map<String, dynamic> drawingData,
// // }) async {
// //   // 1) Need calibration
// //   final calibrated = drawingData['calibrated'] == true;
// //   final pixelsPerUnitBase = (drawingData['pixelsPerUnit'] ?? 0).toDouble();

// //   if (!calibrated || pixelsPerUnitBase <= 0) {
// //     if (!mounted) return;
// //     ScaffoldMessenger.of(context).showSnackBar(
// //       const SnackBar(
// //         content: Text(
// //           'Please calibrate the drawing before slab rebar takeoff.',
// //         ),
// //       ),
// //     );
// //     return;
// //   }

// //   if (polygon.length < 3) return;

// //   // 2) Bounding box of polygon (assumes roughly rectangular slab)
// //   double minX = polygon.first.dx;
// //   double maxX = polygon.first.dx;
// //   double minY = polygon.first.dy;
// //   double maxY = polygon.first.dy;

// //   for (final p in polygon) {
// //     if (p.dx < minX) minX = p.dx;
// //     if (p.dx > maxX) maxX = p.dx;
// //     if (p.dy < minY) minY = p.dy;
// //     if (p.dy > maxY) maxY = p.dy;
// //   }

// //   final widthPx = maxX - minX;  // horizontal span
// //   final heightPx = maxY - minY; // vertical span

// //   final widthM = widthPx / pixelsPerUnitBase;
// //   final heightM = heightPx / pixelsPerUnitBase;

// //   if (widthM <= 0 || heightM <= 0) return;

// //   // 3) Local data model for one rebar set

// //   final markController = TextEditingController();
// //   final embedController = TextEditingController(text: '0.20'); // m each end
// //   final extraController = TextEditingController(text: '0.00'); // extra laps m
// //   String barDirection = 'horizontal'; // default

// //   String? parseError;
// //   RebarSet? previewSet;

// //   final List<RebarSet> sets = [];

// //   // draggable offset
// //   Offset dialogOffset = const Offset(0, 0);

// //   double _spanForDirection(String dir) =>
// //       dir == 'horizontal' ? widthM : heightM;

// //   void recomputePreview(StateSetter setStateDialog) {
// //     final rawMark = markController.text.trim();
// //     final embedStr = embedController.text.trim();
// //     final extraStr = extraController.text.trim();

// //     if (rawMark.isEmpty) {
// //       setStateDialog(() {
// //         parseError = null;
// //         previewSet = null;
// //       });
// //       return;
// //     }

// //     try {
// //       final m = RebarMark.parse(rawMark);
// //       final embed = double.tryParse(embedStr) ?? 0.0;
// //       final extra = double.tryParse(extraStr) ?? 0.0;

// //       final span = _spanForDirection(barDirection);
// //       final Lbar = span + 2 * embed + extra;
// //       final Ltotal = m.quantity * Lbar;
// //       final uw = rebarUnitWeightKgPerM(m.diameterMm);
// //       final wTotal = Ltotal * uw;

// //       setStateDialog(() {
// //         parseError = null;
// //         previewSet = _RebarSet(
// //           mark: m,
// //           direction: barDirection,
// //           clearSpanM: span,
// //           embedEachEndM: embed,
// //           extraLengthM: extra,
// //           barLengthM: Lbar,
// //           totalLengthM: Ltotal,
// //           unitWeightKgPerM: uw,
// //           totalWeightKg: wTotal,
// //         );
// //       });
// //     } catch (e) {
// //       setStateDialog(() {
// //         parseError = e.toString();
// //         previewSet = null;
// //       });
// //     }
// //   }

// //   double get totalLengthAll =>
// //       sets.fold(0.0, (sum, s) => sum + s.totalLengthM);

// //   double get totalWeightAll =>
// //       sets.fold(0.0, (sum, s) => sum + s.totalWeightKg);

// //   final result = await showDialog<bool>(
// //     context: context,
// //     barrierDismissible: false,
// //     builder: (ctx) {
// //       return StatefulBuilder(
// //         builder: (ctx, setStateDialog) {
// //           return Stack(
// //             children: [
// //               Positioned(
// //                 right: 24 - dialogOffset.dx,
// //                 top: 80 + dialogOffset.dy,
// //                 child: GestureDetector(
// //                   onPanUpdate: (details) {
// //                     setStateDialog(() {
// //                       dialogOffset += details.delta;
// //                     });
// //                   },
// //                   child: Material(
// //                     elevation: 8,
// //                     borderRadius: BorderRadius.circular(12),
// //                     color: Theme.of(context).dialogBackgroundColor,
// //                     child: ConstrainedBox(
// //                       constraints: const BoxConstraints(maxWidth: 380),
// //                       child: Padding(
// //                         padding: const EdgeInsets.all(8.0),
// //                         child: Column(
// //                           mainAxisSize: MainAxisSize.min,
// //                           crossAxisAlignment: CrossAxisAlignment.start,
// //                           children: [
// //                             // HEADER
// //                             Row(
// //                               children: [
// //                                 const Icon(Icons.drag_indicator, size: 18),
// //                                 const SizedBox(width: 6),
// //                                 const Expanded(
// //                                   child: Text(
// //                                     'Slab rebar (polygon)',
// //                                     style: TextStyle(
// //                                       fontWeight: FontWeight.w600,
// //                                       fontSize: 14,
// //                                     ),
// //                                   ),
// //                                 ),
// //                                 IconButton(
// //                                   padding: EdgeInsets.zero,
// //                                   constraints: const BoxConstraints(),
// //                                   icon: const Icon(Icons.close, size: 18),
// //                                   onPressed: () => Navigator.pop(ctx, false),
// //                                 ),
// //                               ],
// //                             ),
// //                             const SizedBox(height: 6),

// //                             // SLAB DIMENSIONS
// //                             const Text(
// //                               'Slab dimensions (from polygon):',
// //                               style: TextStyle(
// //                                 fontWeight: FontWeight.w600,
// //                                 fontSize: 12,
// //                               ),
// //                             ),
// //                             const SizedBox(height: 4),
// //                             Text(
// //                               'Horizontal span: ${widthM.toStringAsFixed(3)} m',
// //                               style: const TextStyle(fontSize: 11),
// //                             ),
// //                             Text(
// //                               'Vertical span:   ${heightM.toStringAsFixed(3)} m',
// //                               style: const TextStyle(fontSize: 11),
// //                             ),
// //                             const SizedBox(height: 8),

// //                             // DIRECTION
// //                             const Text(
// //                               'Bars direction (for NEW set):',
// //                               style: TextStyle(
// //                                 fontWeight: FontWeight.w600,
// //                                 fontSize: 12,
// //                               ),
// //                             ),
// //                             Row(
// //                               children: [
// //                                 Expanded(
// //                                   child: RadioListTile<String>(
// //                                     dense: true,
// //                                     visualDensity: VisualDensity.compact,
// //                                     contentPadding: EdgeInsets.zero,
// //                                     title: const Text(
// //                                       'Horizontal',
// //                                       style: TextStyle(fontSize: 11),
// //                                     ),
// //                                     value: 'horizontal',
// //                                     groupValue: barDirection,
// //                                     onChanged: (v) {
// //                                       if (v == null) return;
// //                                       setStateDialog(() {
// //                                         barDirection = v;
// //                                       });
// //                                       recomputePreview(setStateDialog);
// //                                     },
// //                                   ),
// //                                 ),
// //                                 Expanded(
// //                                   child: RadioListTile<String>(
// //                                     dense: true,
// //                                     visualDensity: VisualDensity.compact,
// //                                     contentPadding: EdgeInsets.zero,
// //                                     title: const Text(
// //                                       'Vertical',
// //                                       style: TextStyle(fontSize: 11),
// //                                     ),
// //                                     value: 'vertical',
// //                                     groupValue: barDirection,
// //                                     onChanged: (v) {
// //                                       if (v == null) return;
// //                                       setStateDialog(() {
// //                                         barDirection = v;
// //                                       });
// //                                       recomputePreview(setStateDialog);
// //                                     },
// //                                   ),
// //                                 ),
// //                               ],
// //                             ),

// //                             const SizedBox(height: 4),
// //                             Text(
// //                               'Current clear span: '
// //                               '${_spanForDirection(barDirection).toStringAsFixed(3)} m',
// //                               style: const TextStyle(
// //                                 fontSize: 11,
// //                                 fontWeight: FontWeight.w600,
// //                               ),
// //                             ),

// //                             const SizedBox(height: 8),
// //                             const Text(
// //                               'Rebar mark (for NEW set):',
// //                               style: TextStyle(
// //                                 fontWeight: FontWeight.w600,
// //                                 fontSize: 12,
// //                               ),
// //                             ),
// //                             const SizedBox(height: 4),
// //                             TextField(
// //                               controller: markController,
// //                               decoration: const InputDecoration(
// //                                 hintText: 'e.g. 67Y12-11-200T1',
// //                                 border: OutlineInputBorder(),
// //                                 isDense: true,
// //                               ),
// //                               style: const TextStyle(fontSize: 12),
// //                               onChanged: (_) => recomputePreview(setStateDialog),
// //                             ),

// //                             const SizedBox(height: 8),
// //                             const Text(
// //                               'Embed / extension each end (m):',
// //                               style: TextStyle(
// //                                 fontWeight: FontWeight.w600,
// //                                 fontSize: 12,
// //                               ),
// //                             ),
// //                             const SizedBox(height: 4),
// //                             TextField(
// //                               controller: embedController,
// //                               keyboardType:
// //                                   const TextInputType.numberWithOptions(
// //                                 decimal: true,
// //                               ),
// //                               decoration: const InputDecoration(
// //                                 border: OutlineInputBorder(),
// //                                 isDense: true,
// //                               ),
// //                               style: const TextStyle(fontSize: 12),
// //                               onChanged: (_) => recomputePreview(setStateDialog),
// //                             ),

// //                             const SizedBox(height: 8),
// //                             const Text(
// //                               'Extra length per bar (laps/hooks, m):',
// //                               style: TextStyle(
// //                                 fontWeight: FontWeight.w600,
// //                                 fontSize: 12,
// //                               ),
// //                             ),
// //                             const SizedBox(height: 4),
// //                             TextField(
// //                               controller: extraController,
// //                               keyboardType:
// //                                   const TextInputType.numberWithOptions(
// //                                 decimal: true,
// //                               ),
// //                               decoration: const InputDecoration(
// //                                 border: OutlineInputBorder(),
// //                                 isDense: true,
// //                               ),
// //                               style: const TextStyle(fontSize: 12),
// //                               onChanged: (_) => recomputePreview(setStateDialog),
// //                             ),

// //                             const SizedBox(height: 6),
// //                             if (parseError != null)
// //                               Text(
// //                                 parseError!,
// //                                 style: const TextStyle(
// //                                   color: Colors.red,
// //                                   fontSize: 11,
// //                                 ),
// //                               ),

// //                             if (previewSet != null) ...[
// //                               const SizedBox(height: 4),
// //                               Text(
// //                                 'Preview: ${previewSet!.mark.quantity}'
// //                                 '${previewSet!.mark.barType} '
// //                                 '@ ${previewSet!.mark.spacingMm} c/c '
// //                                 '(${previewSet!.direction == 'horizontal' ? 'H' : 'V'})',
// //                                 style: const TextStyle(fontSize: 11),
// //                               ),
// //                               Text(
// //                                 'L/bar: ${previewSet!.barLengthM.toStringAsFixed(3)} m, '
// //                                 'Total: ${previewSet!.totalLengthM.toStringAsFixed(3)} m',
// //                                 style: const TextStyle(fontSize: 11),
// //                               ),
// //                               Text(
// //                                 'Weight: ${previewSet!.unitWeightKgPerM.toStringAsFixed(3)} '
// //                                 'kg/m → ${previewSet!.totalWeightKg.toStringAsFixed(1)} kg',
// //                                 style: const TextStyle(fontSize: 11),
// //                               ),
// //                             ],

// //                             const SizedBox(height: 6),
// //                             Align(
// //                               alignment: Alignment.centerRight,
// //                               child: TextButton.icon(
// //                                 icon: const Icon(Icons.add, size: 16),
// //                                 label: const Text(
// //                                   'Add rebar set',
// //                                   style: TextStyle(fontSize: 12),
// //                                 ),
// //                                 onPressed: () {
// //                                   if (previewSet == null) return;
// //                                   setStateDialog(() {
// //                                     sets.add(previewSet!);
// //                                     // clear only mark; keep embed/extra/direction
// //                                     markController.clear();
// //                                     previewSet = null;
// //                                     parseError = null;
// //                                   });
// //                                 },
// //                               ),
// //                             ),

// //                             if (sets.isNotEmpty) ...[
// //                               const Divider(),
// //                               const Text(
// //                                 'Added rebar sets:',
// //                                 style: TextStyle(
// //                                   fontWeight: FontWeight.w600,
// //                                   fontSize: 12,
// //                                 ),
// //                               ),
// //                               const SizedBox(height: 4),
// //                               SizedBox(
// //                                 height: 120,
// //                                 child: ListView.builder(
// //                                   itemCount: sets.length,
// //                                   itemBuilder: (ctx, i) {
// //                                     final s = sets[i];
// //                                     return Row(
// //                                       crossAxisAlignment:
// //                                           CrossAxisAlignment.start,
// //                                       children: [
// //                                         Expanded(
// //                                           child: Text(
// //                                             '${i + 1}. '
// //                                             '${s.mark.quantity}${s.mark.barType}'
// //                                             '-${s.mark.spacingMm}${s.mark.layer} '
// //                                             '(${s.direction == 'horizontal' ? 'H' : 'V'})\n'
// //                                             'L/bar ${s.barLengthM.toStringAsFixed(3)} m, '
// //                                             'Total ${s.totalLengthM.toStringAsFixed(3)} m, '
// //                                             '${s.totalWeightKg.toStringAsFixed(1)} kg',
// //                                             style: const TextStyle(
// //                                               fontSize: 11,
// //                                             ),
// //                                           ),
// //                                         ),
// //                                         IconButton(
// //                                           padding: EdgeInsets.zero,
// //                                           constraints: const BoxConstraints(),
// //                                           icon: const Icon(
// //                                             Icons.delete_outline,
// //                                             size: 16,
// //                                           ),
// //                                           onPressed: () {
// //                                             setStateDialog(() {
// //                                               sets.removeAt(i);
// //                                             });
// //                                           },
// //                                         ),
// //                                       ],
// //                                     );
// //                                   },
// //                                 ),
// //                               ),
// //                               const SizedBox(height: 4),
// //                               Text(
// //                                 'TOTAL length: ${totalLengthAll.toStringAsFixed(3)} m',
// //                                 style: const TextStyle(
// //                                   fontSize: 11,
// //                                   fontWeight: FontWeight.w600,
// //                                 ),
// //                               ),
// //                               Text(
// //                                 'TOTAL weight: ${totalWeightAll.toStringAsFixed(1)} kg',
// //                                 style: const TextStyle(
// //                                   fontSize: 11,
// //                                   fontWeight: FontWeight.w600,
// //                                 ),
// //                               ),
// //                             ],

// //                             const SizedBox(height: 8),
// //                             Row(
// //                               mainAxisAlignment: MainAxisAlignment.end,
// //                               children: [
// //                                 TextButton(
// //                                   onPressed: () => Navigator.pop(ctx, false),
// //                                   child: const Text(
// //                                     'Cancel',
// //                                     style: TextStyle(fontSize: 12),
// //                                   ),
// //                                 ),
// //                                 const SizedBox(width: 8),
// //                                 FilledButton(
// //                                   onPressed:
// //                                       sets.isNotEmpty
// //                                           ? () => Navigator.pop(ctx, true)
// //                                           : null,
// //                                   child: const Text(
// //                                     'Save',
// //                                     style: TextStyle(fontSize: 12),
// //                                   ),
// //                                 ),
// //                               ],
// //                             ),
// //                           ],
// //                         ),
// //                       ),
// //                     ),
// //                   ),
// //                 ),
// //               ),
// //             ],
// //           );
// //         },
// //       );
// //     },
// //   );

// //   if (result != true) return;

// //   // 4) Save each rebar set as one measurement doc
// //   try {
// //     // polygon to store
// //     final polyData = polygon.map((p) => {'x': p.dx, 'y': p.dy}).toList();

// //     // slab center for drawing "representative" line
// //     final centerY = (minY + maxY) / 2;
// //     final centerX = (minX + maxX) / 2;

// //     for (final s in sets) {
// //       late Offset p1;
// //       late Offset p2;

// //       if (s.direction == 'horizontal') {
// //         p1 = Offset(minX, centerY);
// //         p2 = Offset(maxX, centerY);
// //       } else {
// //         p1 = Offset(centerX, minY);
// //         p2 = Offset(centerX, maxY);
// //       }

// //       await _saveRebarSlabMeasurement(
// //         mark: s.mark,
// //         clearSpanM: s.clearSpanM,
// //         embedEachEndM: s.embedEachEndM,
// //         extraLengthM: s.extraLengthM,
// //         barLengthM: s.barLengthM,
// //         totalLengthM: s.totalLengthM,
// //         unitWeightKgPerM: s.unitWeightKgPerM,
// //         totalWeightKg: s.totalWeightKg,
// //         p1: p1,
// //         p2: p2,
// //         polygon: polyData, // 👈 store area
// //       );
// //     }

// //     if (!mounted) return;
// //     ScaffoldMessenger.of(context).showSnackBar(
// //       const SnackBar(content: Text('Slab rebar sets saved')),
// //     );
// //   } catch (e) {
// //     if (!mounted) return;
// //     ScaffoldMessenger.of(context).showSnackBar(
// //       SnackBar(content: Text('Error saving rebar slab: $e')),
// //     );
// //   }
// // }
