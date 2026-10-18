// controller.dart
import 'dart:ui';
import 'package:aqs/features/takeoff/builds/slab_composite_content.dart';
import 'package:aqs/features/takeoff/models/rebar_mark.dart';
import 'package:aqs/features/takeoff/models/rebar_set.dart';
import 'package:aqs/features/takeoff/models/slab_edge_pattern.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TakeoffController {
  final FirebaseFirestore firestore;
  final void Function(bool busy)? onCompositeBusyChanged;
  final void Function(String beamName)? onBeamNameChanged;
  final CollectionReference<Map<String, dynamic>> measurementsRef;

  TakeoffController({
    FirebaseFirestore? firestore,
    this.onCompositeBusyChanged,
    required this.measurementsRef,
    this.onBeamNameChanged,
  }) : firestore = firestore ?? FirebaseFirestore.instance;

  // ---------- small helpers ----------

  // ---------- MAIN: slab composite from polygon ----------

  // Future<void> openBeamCompositeFromSegment({
  //   required BuildContext context,
  //   required String projectId,
  //   required String buildingId,
  //   required String drawingId,
  //   required Offset p1,
  //   required Offset p2,
  //   required Map<String, dynamic> drawingData,
  //   required Color currentColor,
  //   required String? activeLabel,
  // }) async {
  //   // 1) Compute length from calibration
  //   final lengthM = distanceInMeters(p1, p2, drawingData);
  //   if (lengthM <= 0) {
  //     if (context.mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(
  //           content: Text(
  //             'Drawing not calibrated – cannot compute beam length.',
  //           ),
  //         ),
  //       );
  //     }
  //     return;
  //   }

  //   // This id will be used both as:
  //   //  - the doc id of the visual length line
  //   //  - the "beamId" field in all composite docs
  //   final beamId = measurementsRef.doc().id;

  //   // prefill BOQs from last beam composite
  //   final lastConcBoq = await _findLastSlabBoqCode(
  //     projectId: projectId,
  //     buildingId: buildingId,
  //     drawingId: drawingId,
  //     type: 'beamConcrete',
  //   );
  //   final lastSoffitBoq = await _findLastSlabBoqCode(
  //     projectId: projectId,
  //     buildingId: buildingId,
  //     drawingId: drawingId,
  //     type: 'beamFormworkSoffit',
  //   );
  //   final lastSideBoq = await _findLastSlabBoqCode(
  //     projectId: projectId,
  //     buildingId: buildingId,
  //     drawingId: drawingId,
  //     type: 'beamFormworkSide',
  //   );
  //   final lastRebarBoq = await _findLastSlabBoqCode(
  //     projectId: projectId,
  //     buildingId: buildingId,
  //     drawingId: drawingId,
  //     type: 'rebarBeam',
  //   ); // not yet used in this function, but ok to keep

  //   // Input controllers
  //   final widthController = TextEditingController(text: '0.30'); // 300 mm
  //   final depthController = TextEditingController(text: '0.45'); // 450 mm

  //   final boqConcController = TextEditingController(text: lastConcBoq ?? '');
  //   final boqSideFwController = TextEditingController(text: lastSideBoq ?? '');
  //   final boqSoffitFwController = TextEditingController(
  //     text: lastSoffitBoq ?? '',
  //   );

  //   bool includeConcrete = true;
  //   bool includeSideFormwork = true;
  //   bool includeSoffitFormwork = true;
  //   bool isGroundBeam = false;

  //   Offset dialogOffset = Offset.zero;
  //   bool saving = false;

  //   final ok = await showDialog<bool>(
  //     context: context,
  //     barrierDismissible: false,
  //     builder: (ctx) {
  //       return StatefulBuilder(
  //         builder: (ctx, setStateDialog) {
  //           // if ground beam, we usually don’t have soffit formwork
  //           if (isGroundBeam && includeSoffitFormwork) {
  //             includeSoffitFormwork = false;
  //           }

  //           return GestureDetector(
  //             onPanUpdate: (details) {
  //               setStateDialog(() {
  //                 dialogOffset += details.delta;
  //               });
  //             },
  //             child: Transform.translate(
  //               offset: dialogOffset,
  //               child: Dialog(
  //                 insetPadding: const EdgeInsets.symmetric(
  //                   horizontal: 24,
  //                   vertical: 24,
  //                 ),
  //                 child: ConstrainedBox(
  //                   constraints: const BoxConstraints(maxWidth: 450),
  //                   child: Column(
  //                     mainAxisSize: MainAxisSize.min,
  //                     children: [
  //                       // Header / drag handle
  //                       Container(
  //                         padding: const EdgeInsets.symmetric(
  //                           horizontal: 12,
  //                           vertical: 6,
  //                         ),
  //                         decoration: const BoxDecoration(
  //                           border: Border(
  //                             bottom: BorderSide(color: Colors.black12),
  //                           ),
  //                         ),
  //                         child: Row(
  //                           children: [
  //                             const Icon(Icons.drag_handle, size: 18),
  //                             const SizedBox(width: 8),
  //                             Expanded(
  //                               child: Text(
  //                                 'Beam composite (concrete + formwork)',
  //                                 style: const TextStyle(
  //                                   fontWeight: FontWeight.w600,
  //                                 ),
  //                               ),
  //                             ),
  //                           ],
  //                         ),
  //                       ),

  //                       Flexible(
  //                         child: SingleChildScrollView(
  //                           padding: const EdgeInsets.all(12),
  //                           child: Column(
  //                             crossAxisAlignment: CrossAxisAlignment.start,
  //                             mainAxisSize: MainAxisSize.min,
  //                             children: [
  //                               Text(
  //                                 'Beam length: ${lengthM.toStringAsFixed(3)} m',
  //                                 style: const TextStyle(fontSize: 12),
  //                               ),
  //                               const SizedBox(height: 8),

  //                               // Geometry
  //                               const Text(
  //                                 'Beam dimensions (m):',
  //                                 style: TextStyle(fontWeight: FontWeight.w600),
  //                               ),
  //                               const SizedBox(height: 4),
  //                               Row(
  //                                 children: [
  //                                   Expanded(
  //                                     child: TextField(
  //                                       controller: widthController,
  //                                       keyboardType:
  //                                           const TextInputType.numberWithOptions(
  //                                             decimal: true,
  //                                           ),
  //                                       decoration: const InputDecoration(
  //                                         labelText: 'Width b (m)',
  //                                         isDense: true,
  //                                         border: OutlineInputBorder(),
  //                                       ),
  //                                     ),
  //                                   ),
  //                                   const SizedBox(width: 8),
  //                                   Expanded(
  //                                     child: TextField(
  //                                       controller: depthController,
  //                                       keyboardType:
  //                                           const TextInputType.numberWithOptions(
  //                                             decimal: true,
  //                                           ),
  //                                       decoration: const InputDecoration(
  //                                         labelText: 'Depth h (m)',
  //                                         isDense: true,
  //                                         border: OutlineInputBorder(),
  //                                       ),
  //                                     ),
  //                                   ),
  //                                 ],
  //                               ),

  //                               const SizedBox(height: 8),
  //                               Row(
  //                                 children: [
  //                                   Switch(
  //                                     value: isGroundBeam,
  //                                     onChanged: (v) {
  //                                       setStateDialog(() {
  //                                         isGroundBeam = v;
  //                                         if (isGroundBeam) {
  //                                           includeSoffitFormwork = false;
  //                                         }
  //                                       });
  //                                     },
  //                                   ),
  //                                   const SizedBox(width: 4),
  //                                   const Expanded(
  //                                     child: Text(
  //                                       'Ground beam (no soffit formwork)',
  //                                       style: TextStyle(fontSize: 12),
  //                                     ),
  //                                   ),
  //                                 ],
  //                               ),

  //                               const Divider(height: 20),

  //                               // Components toggles + BOQs
  //                               const Text(
  //                                 'Components & BOQ codes:',
  //                                 style: TextStyle(fontWeight: FontWeight.w600),
  //                               ),
  //                               const SizedBox(height: 6),

  //                               // Concrete
  //                               Row(
  //                                 children: [
  //                                   Checkbox(
  //                                     value: includeConcrete,
  //                                     onChanged: (v) {
  //                                       setStateDialog(() {
  //                                         includeConcrete = v ?? true;
  //                                       });
  //                                     },
  //                                   ),
  //                                   const SizedBox(width: 4),
  //                                   const Expanded(
  //                                     child: Text(
  //                                       'Concrete (m³)',
  //                                       style: TextStyle(fontSize: 12),
  //                                     ),
  //                                   ),
  //                                 ],
  //                               ),
  //                               Padding(
  //                                 padding: const EdgeInsets.only(left: 32.0),
  //                                 child: TextField(
  //                                   controller: boqConcController,
  //                                   decoration: const InputDecoration(
  //                                     labelText: 'BOQ code (Concrete)',
  //                                     isDense: true,
  //                                     border: OutlineInputBorder(),
  //                                   ),
  //                                 ),
  //                               ),

  //                               const SizedBox(height: 8),

  //                               // Side formwork
  //                               Row(
  //                                 children: [
  //                                   Checkbox(
  //                                     value: includeSideFormwork,
  //                                     onChanged: (v) {
  //                                       setStateDialog(() {
  //                                         includeSideFormwork = v ?? true;
  //                                       });
  //                                     },
  //                                   ),
  //                                   const SizedBox(width: 4),
  //                                   const Expanded(
  //                                     child: Text(
  //                                       'Side formwork (2 × h × L) (m²)',
  //                                       style: TextStyle(fontSize: 12),
  //                                     ),
  //                                   ),
  //                                 ],
  //                               ),
  //                               Padding(
  //                                 padding: const EdgeInsets.only(left: 32.0),
  //                                 child: TextField(
  //                                   controller: boqSideFwController,
  //                                   decoration: const InputDecoration(
  //                                     labelText: 'BOQ code (Side formwork)',
  //                                     isDense: true,
  //                                     border: OutlineInputBorder(),
  //                                   ),
  //                                 ),
  //                               ),

  //                               const SizedBox(height: 8),

  //                               // Soffit formwork
  //                               Row(
  //                                 children: [
  //                                   Checkbox(
  //                                     value: includeSoffitFormwork,
  //                                     onChanged:
  //                                         isGroundBeam
  //                                             ? null // disabled
  //                                             : (v) {
  //                                               setStateDialog(() {
  //                                                 includeSoffitFormwork =
  //                                                     v ?? true;
  //                                               });
  //                                             },
  //                                   ),
  //                                   const SizedBox(width: 4),
  //                                   Expanded(
  //                                     child: Text(
  //                                       'Soffit formwork (b × L) (m²)'
  //                                       '${isGroundBeam ? ' – disabled for ground beams' : ''}',
  //                                       style: const TextStyle(fontSize: 12),
  //                                     ),
  //                                   ),
  //                                 ],
  //                               ),
  //                               Padding(
  //                                 padding: const EdgeInsets.only(left: 32.0),
  //                                 child: TextField(
  //                                   controller: boqSoffitFwController,
  //                                   enabled: !isGroundBeam,
  //                                   decoration: const InputDecoration(
  //                                     labelText: 'BOQ code (Soffit formwork)',
  //                                     isDense: true,
  //                                     border: OutlineInputBorder(),
  //                                   ),
  //                                 ),
  //                               ),

  //                               if (saving) ...[
  //                                 const SizedBox(height: 12),
  //                                 const Center(
  //                                   child: SizedBox(
  //                                     width: 24,
  //                                     height: 24,
  //                                     child: CircularProgressIndicator(
  //                                       strokeWidth: 2,
  //                                     ),
  //                                   ),
  //                                 ),
  //                               ],
  //                             ],
  //                           ),
  //                         ),
  //                       ),

  //                       // Actions
  //                       Padding(
  //                         padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
  //                         child: Row(
  //                           mainAxisAlignment: MainAxisAlignment.end,
  //                           children: [
  //                             TextButton(
  //                               onPressed:
  //                                   saving
  //                                       ? null
  //                                       : () => Navigator.pop(ctx, false),
  //                               child: const Text('Cancel'),
  //                             ),
  //                             const SizedBox(width: 8),
  //                             FilledButton(
  //                               onPressed:
  //                                   saving
  //                                       ? null
  //                                       : () {
  //                                         setStateDialog(() {
  //                                           saving = true;
  //                                         });
  //                                         Navigator.pop(ctx, true);
  //                                       },
  //                               child:
  //                                   saving
  //                                       ? const Text('Saving...')
  //                                       : const Text('Save'),
  //                             ),
  //                           ],
  //                         ),
  //                       ),
  //                     ],
  //                   ),
  //                 ),
  //               ),
  //             ),
  //           );
  //         },
  //       );
  //     },
  //   );

  //   if (ok != true) return;

  //   // 2) Parse values
  //   final widthM = double.tryParse(widthController.text.trim()) ?? 0.0;
  //   final depthM = double.tryParse(depthController.text.trim()) ?? 0.0;

  //   if (widthM <= 0 || depthM <= 0) {
  //     if (context.mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(content: Text('Beam width/depth must be > 0.')),
  //       );
  //     }
  //     return;
  //   }

  //   final boqConc = boqConcController.text.trim();
  //   final boqSideFw = boqSideFwController.text.trim();
  //   final boqSoffitFw = boqSoffitFwController.text.trim();

  //   // 3) Compute quantities
  //   final concVolM3 = lengthM * widthM * depthM;
  //   final sideFwM2 = 2 * depthM * lengthM;
  //   final soffitFwM2 = isGroundBeam ? 0.0 : widthM * lengthM;

  //   final p1Map = {'x': p1.dx, 'y': p1.dy};
  //   final p2Map = {'x': p2.dx, 'y': p2.dy};

  //   // 4) Save docs
  //   final batch = FirebaseFirestore.instance.batch();

  //   // 4a) Master beam LENGTH doc – this is what your viewer draws
  //   final lengthDocRef = measurementsRef.doc(beamId);
  //   batch.set(lengthDocRef, {
  //     'projectId': projectId,
  //     'buildingId': buildingId,
  //     'drawingId': drawingId,
  //     'type': 'length', // 👈 so SegmentsPainter will draw it
  //     'measureType': 'compositeBeam', // 👈 so you can filter in summary
  //     'unit': 'm',
  //     'value': lengthM,
  //     'p1': p1Map,
  //     'p2': p2Map,
  //     'color': currentColor.value,
  //     'label': activeLabel ?? 'Beam',
  //     'beamId': beamId, // self id for grouping if needed
  //     'isGroundBeam': isGroundBeam,
  //     'createdAt': FieldValue.serverTimestamp(),
  //   });

  //   // 4b) Concrete
  //   if (includeConcrete && concVolM3 > 0 && boqConc.isNotEmpty) {
  //     final docRef = measurementsRef.doc();
  //     batch.set(docRef, {
  //       'projectId': projectId,
  //       'buildingId': buildingId,
  //       'drawingId': drawingId,
  //       'type': 'beamConcrete',
  //       'measureType': 'compositeBeam',
  //       'unit': 'm3',
  //       'value': concVolM3,
  //       'lengthM': lengthM,
  //       'widthM': widthM,
  //       'depthM': depthM,
  //       'label': '${activeLabel ?? 'Beam'} - Concrete',
  //       'boqCode': boqConc,
  //       'color': currentColor.value,
  //       'p1': p1Map,
  //       'p2': p2Map,
  //       'beamId': beamId,
  //       'isGroundBeam': isGroundBeam,
  //       'createdAt': FieldValue.serverTimestamp(),
  //     });
  //   }

  //   // 4c) Side formwork
  //   if (includeSideFormwork && sideFwM2 > 0 && boqSideFw.isNotEmpty) {
  //     final docRef = measurementsRef.doc();
  //     batch.set(docRef, {
  //       'projectId': projectId,
  //       'buildingId': buildingId,
  //       'drawingId': drawingId,
  //       'type': 'beamFormworkSide',
  //       'measureType': 'compositeBeam',
  //       'unit': 'm2',
  //       'value': sideFwM2,
  //       'lengthM': lengthM,
  //       'depthM': depthM,
  //       'label': '${activeLabel ?? 'Beam'} - Side formwork',
  //       'boqCode': boqSideFw,
  //       'color': currentColor.value,
  //       'p1': p1Map,
  //       'p2': p2Map,
  //       'beamId': beamId,
  //       'isGroundBeam': isGroundBeam,
  //       'createdAt': FieldValue.serverTimestamp(),
  //     });
  //   }

  //   // 4d) Soffit formwork (skip for ground beams)
  //   if (!isGroundBeam &&
  //       includeSoffitFormwork &&
  //       soffitFwM2 > 0 &&
  //       boqSoffitFw.isNotEmpty) {
  //     final docRef = measurementsRef.doc();
  //     batch.set(docRef, {
  //       'projectId': projectId,
  //       'buildingId': buildingId,
  //       'drawingId': drawingId,
  //       'type': 'beamFormworkSoffit',
  //       'measureType': 'compositeBeam',
  //       'unit': 'm2',
  //       'value': soffitFwM2,
  //       'lengthM': lengthM,
  //       'widthM': widthM,
  //       'label': '${activeLabel ?? 'Beam'} - Soffit formwork',
  //       'boqCode': boqSoffitFw,
  //       'color': currentColor.value,
  //       'p1': p1Map,
  //       'p2': p2Map,
  //       'beamId': beamId,
  //       'isGroundBeam': isGroundBeam,
  //       'createdAt': FieldValue.serverTimestamp(),
  //     });
  //   }

  //   await batch.commit();

  //   if (context.mounted) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text('Beam composite (concrete + formwork) saved.'),
  //       ),
  //     );
  //   }
  // }
}
