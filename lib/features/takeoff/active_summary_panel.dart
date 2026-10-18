import 'package:aqs/core/state/firestore_state.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';

// class ActiveItemSummaryPanel extends StatelessWidget {
//   final String drawingId;
//   final CollectionReference<Map<String, dynamic>> measurementsRef;
//   final String? activeMeasureType;
//   final String? activeLabel;
//   final String? activeBoqCode;
//   final String? activeUnit;
//   const ActiveItemSummaryPanel({
//     super.key,
//     required this.drawingId,
//     required this.measurementsRef,
//     required this.activeMeasureType,
//     this.activeLabel,
//     this.activeBoqCode,
//     this.activeUnit,
//   });

//   @override
//   Widget build(BuildContext context) {
//     // No active measuring type → hide panel completely
//     if (activeMeasureType == null || activeMeasureType!.trim().isEmpty) {
//       return const SizedBox.shrink();
//     }

//     final measureType = activeMeasureType!.trim();

//     // 🔹 Query: by drawing + measureType
//     Query<Map<String, dynamic>> q = measurementsRef.where(
//       'drawingId',
//       isEqualTo: drawingId,
//     );
//     q = q.where('measureType', isEqualTo: measureType);

//     return Align(
//       alignment: Alignment.topRight,
//       child: Card(
//         margin: const EdgeInsets.only(right: 12, top: 12),
//         color: Colors.white.withOpacity(0.9),
//         elevation: 4,
//         child: Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
//           child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//             stream: q.stateSnapshots(),
//             builder: (ctx, snap) {
//               if (snap.hasError) {
//                 debugPrint('ActiveItemSummaryPanel error: ${snap.error}');
//                 return _buildCardBody(
//                   context,
//                   child: Text(
//                     'Error loading summary:\n${snap.error}',
//                     style: const TextStyle(fontSize: 11),
//                   ),
//                 );
//               }

//               if (!snap.hasData) {
//                 return _buildCardBody(
//                   context,
//                   child: const SizedBox(
//                     height: 24,
//                     width: 24,
//                     child: CircularProgressIndicator(strokeWidth: 2),
//                   ),
//                 );
//               }

//               final docs = snap.data!.docs;
//               if (docs.isEmpty) {
//                 return _buildCardBody(
//                   context,
//                   child: const Text(
//                     'No measurements yet\nfor this measuring type.',
//                     style: TextStyle(fontSize: 11),
//                   ),
//                 );
//               }

//               // --------------- FLAGS / MODES ---------------
//               final mt = (activeMeasureType ?? '').toLowerCase();
//               final bool isSlabComposite =
//                   mt == 'compositeslab' || mt == 'slabcomposite';
//               final bool isFootingComposite =
//                   mt == 'compositefooting' || mt == 'footingcomposite';
//               final bool isBeamComposite =
//                   mt == 'compositebeam' || mt == 'beamcomposite';

//               // --------------- AGGREGATES ---------------

//               // Generic total (for non-composite types)
//               double totalValue = 0.0;
//               String? unitFromDocs;

//               // Rebar totals (used by all composites)
//               double totalRebarLengthM = 0.0;
//               double totalRebarWeightKg = 0.0;

//               // Footing composite totals
//               double footingConcreteTotalM3 = 0.0;
//               double footingFormworkTotalM2 = 0.0;
//               final footingGroupIds = <String>{};

//               // Slab composite totals
//               double slabConcreteTotalM3 = 0.0;
//               double slabSoffitFormworkTotalM2 = 0.0;
//               double slabEdgeFormworkTotalM2 = 0.0;
//               final slabIds = <String>{};

//               // Total slab panel area (each slabId counted once)
//               double totalSlabPanelAreaM2 = 0.0;
//               final countedSlabAreaIds = <String>{};

//               // Beam composite totals
//               double beamConcreteTotalM3 = 0.0;
//               double beamSideFormworkTotalM2 = 0.0;
//               double beamSoffitFormworkTotalM2 = 0.0;
//               double beamTotalLengthM = 0.0; // sum of lengthM over all beams

//               for (final d in docs) {
//                 final m = d.data();
//                 final type = (m['type'] ?? '') as String;
//                 final rawV = m['value'];
//                 final double value = (rawV is num) ? rawV.toDouble() : 0.0;

//                 final u = (m['unit'] ?? '') as String;
//                 unitFromDocs ??= u.isNotEmpty ? u : null;

//                 // ---------- GENERIC TOTAL (non-composite only) ----------
//                 if (!isSlabComposite &&
//                     !isFootingComposite &&
//                     !isBeamComposite) {
//                   totalValue += value;
//                 }

//                 // ---------- FOOTING COMPOSITE FAMILIES ----------
//                 if (type == 'footingConcrete') {
//                   footingConcreteTotalM3 += value;
//                   final g = (m['footingGroupId'] ?? '') as String;
//                   if (g.trim().isNotEmpty) footingGroupIds.add(g.trim());
//                 } else if (type == 'footingFormwork') {
//                   footingFormworkTotalM2 += value;
//                   final g = (m['footingGroupId'] ?? '') as String;
//                   if (g.trim().isNotEmpty) footingGroupIds.add(g.trim());
//                 } else if (type == 'rebarFooting') {
//                   final lenAll =
//                       (m['lengthAllFootingsM'] as num?)?.toDouble() ?? 0.0;
//                   final wtAll =
//                       (m['weightAllFootingsKg'] as num?)?.toDouble() ?? value;

//                   totalRebarLengthM += lenAll;
//                   totalRebarWeightKg += wtAll;

//                   final g = (m['footingGroupId'] ?? '') as String;
//                   if (g.trim().isNotEmpty) footingGroupIds.add(g.trim());
//                 }

//                 // ---------- SLAB COMPOSITE FAMILIES ----------
//                 if (type == 'slabConcrete') {
//                   slabConcreteTotalM3 += value;

//                   final sId = (m['slabId'] ?? '') as String;
//                   if (sId.trim().isNotEmpty) {
//                     slabIds.add(sId.trim());

//                     final area = (m['areaM2'] as num?)?.toDouble() ?? 0.0;
//                     if (area > 0 && !countedSlabAreaIds.contains(sId)) {
//                       totalSlabPanelAreaM2 += area;
//                       countedSlabAreaIds.add(sId);
//                     }
//                   }
//                 } else if (type == 'slabFormworkSoffit') {
//                   slabSoffitFormworkTotalM2 += value;
//                   final sId = (m['slabId'] ?? '') as String;
//                   if (sId.trim().isNotEmpty) slabIds.add(sId.trim());
//                 } else if (type == 'slabFormworkEdge') {
//                   slabEdgeFormworkTotalM2 += value;
//                   final sId = (m['slabId'] ?? '') as String;
//                   if (sId.trim().isNotEmpty) slabIds.add(sId.trim());
//                 } else if (type == 'rebarSlab') {
//                   final lenAll =
//                       (m['totalLengthAllBarsM'] as num?)?.toDouble() ?? 0.0;
//                   final wtAll =
//                       (m['totalWeightKg'] as num?)?.toDouble() ?? value;

//                   totalRebarLengthM += lenAll;
//                   totalRebarWeightKg += wtAll;

//                   final sId = (m['slabId'] ?? '') as String;
//                   if (sId.trim().isNotEmpty) slabIds.add(sId.trim());
//                 }

//                 // ---------- BEAM COMPOSITE FAMILIES ----------
//                 if (type == 'beamConcrete') {
//                   beamConcreteTotalM3 += value;
//                   final len =
//                       (m['lengthM'] as num?)?.toDouble() ?? 0.0; // beam length
//                   beamTotalLengthM += len;
//                 } else if (type == 'beamFormworkSide') {
//                   beamSideFormworkTotalM2 += value;
//                 } else if (type == 'beamFormworkSoffit') {
//                   beamSoffitFormworkTotalM2 += value;
//                 } else if (type == 'rebarBeam' ||
//                     type == 'rebarBeamLong' ||
//                     type == 'rebarBeamRing') {
//                   // Flexible handling for whatever you've stored
//                   final lenAll =
//                       (m['lengthAllBeamsM'] as num?)?.toDouble() ??
//                       (m['totalLengthAllBarsM'] as num?)?.toDouble() ??
//                       0.0;
//                   final wtAll =
//                       (m['weightAllBeamsKg'] as num?)?.toDouble() ??
//                       (m['totalWeightKg'] as num?)?.toDouble() ??
//                       value;

//                   totalRebarLengthM += lenAll;
//                   totalRebarWeightKg += wtAll;
//                 }
//               }

//               final unit = activeUnit ?? unitFromDocs ?? '';
//               final unitDisplay = _prettyUnit(unit);
//               final hasRebarTotals =
//                   totalRebarLengthM > 0 || totalRebarWeightKg > 0;

//               return _buildCardBody(
//                 context,
//                 child: ConstrainedBox(
//                   constraints: const BoxConstraints(maxWidth: 260),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     mainAxisSize: MainAxisSize.min,
//                     children: [
//                       Row(
//                         children: [
//                           const Icon(Icons.summarize, size: 16),
//                           const SizedBox(width: 6),
//                           Expanded(
//                             child: Text(
//                               _buildTitle(),
//                               style: const TextStyle(
//                                 fontSize: 15,
//                                 fontWeight: FontWeight.w600,
//                               ),
//                               overflow: TextOverflow.ellipsis,
//                             ),
//                           ),
//                         ],
//                       ),
//                       const SizedBox(height: 4),

//                       // ===== NON-COMPOSITE MAIN TOTAL =====
//                       if (!isSlabComposite &&
//                           !isFootingComposite &&
//                           !isBeamComposite)
//                         Text(
//                           'Total: ${totalValue.toStringAsFixed(3)} $unitDisplay',
//                           style: const TextStyle(fontSize: 14),
//                         ),

//                       // ===== SLAB COMPOSITE SUMMARY =====
//                       if (isSlabComposite) ...[
//                         Text(
//                           'Panels area: ${totalSlabPanelAreaM2.toStringAsFixed(3)} m²',
//                           style: const TextStyle(fontSize: 14),
//                         ),
//                         if (slabConcreteTotalM3 > 0)
//                           Text(
//                             'Concrete: ${slabConcreteTotalM3.toStringAsFixed(3)} m³',
//                             style: const TextStyle(fontSize: 13),
//                           ),
//                         if (slabSoffitFormworkTotalM2 > 0)
//                           Text(
//                             'Formwork – soffit: '
//                             '${slabSoffitFormworkTotalM2.toStringAsFixed(3)} m²',
//                             style: const TextStyle(fontSize: 13),
//                           ),
//                         if (slabEdgeFormworkTotalM2 > 0)
//                           Text(
//                             'Formwork – edges: '
//                             '${slabEdgeFormworkTotalM2.toStringAsFixed(3)} m²',
//                             style: const TextStyle(fontSize: 13),
//                           ),
//                         if (hasRebarTotals) ...[
//                           if (totalRebarLengthM > 0)
//                             Text(
//                               'Rebar length: ${totalRebarLengthM.toStringAsFixed(3)} m',
//                               style: const TextStyle(fontSize: 13),
//                             ),
//                           if (totalRebarWeightKg > 0)
//                             Text(
//                               'Rebar weight: ${totalRebarWeightKg.toStringAsFixed(2)} kg',
//                               style: const TextStyle(fontSize: 13),
//                             ),
//                         ],
//                       ],

//                       // ===== FOOTING COMPOSITE SUMMARY =====
//                       if (isFootingComposite) ...[
//                         Text(
//                           'Concrete (all groups): '
//                           '${footingConcreteTotalM3.toStringAsFixed(3)} m³',
//                           style: const TextStyle(fontSize: 13),
//                         ),
//                         if (footingFormworkTotalM2 > 0)
//                           Text(
//                             'Formwork (all groups): '
//                             '${footingFormworkTotalM2.toStringAsFixed(3)} m²',
//                             style: const TextStyle(fontSize: 13),
//                           ),
//                         if (hasRebarTotals) ...[
//                           if (totalRebarLengthM > 0)
//                             Text(
//                               'Rebar (all groups): '
//                               '${totalRebarLengthM.toStringAsFixed(3)} m',
//                               style: const TextStyle(fontSize: 13),
//                             ),
//                           if (totalRebarWeightKg > 0)
//                             Text(
//                               'Rebar (all groups): '
//                               '${totalRebarWeightKg.toStringAsFixed(2)} kg',
//                               style: const TextStyle(fontSize: 13),
//                             ),
//                         ],
//                       ],

//                       // ===== BEAM COMPOSITE SUMMARY =====
//                       if (isBeamComposite) ...[
//                         if (beamTotalLengthM > 0)
//                           Text(
//                             'Total beam length: '
//                             '${beamTotalLengthM.toStringAsFixed(3)} m',
//                             style: const TextStyle(fontSize: 13),
//                           ),
//                         if (beamConcreteTotalM3 > 0)
//                           Text(
//                             'Concrete: ${beamConcreteTotalM3.toStringAsFixed(3)} m³',
//                             style: const TextStyle(fontSize: 13),
//                           ),
//                         if (beamSideFormworkTotalM2 > 0)
//                           Text(
//                             'Formwork – sides: '
//                             '${beamSideFormworkTotalM2.toStringAsFixed(3)} m²',
//                             style: const TextStyle(fontSize: 13),
//                           ),
//                         if (beamSoffitFormworkTotalM2 > 0)
//                           Text(
//                             'Formwork – soffit: '
//                             '${beamSoffitFormworkTotalM2.toStringAsFixed(3)} m²',
//                             style: const TextStyle(fontSize: 13),
//                           ),
//                         if (hasRebarTotals) ...[
//                           if (totalRebarLengthM > 0)
//                             Text(
//                               'Rebar length: ${totalRebarLengthM.toStringAsFixed(3)} m',
//                               style: const TextStyle(fontSize: 13),
//                             ),
//                           if (totalRebarWeightKg > 0)
//                             Text(
//                               'Rebar weight: ${totalRebarWeightKg.toStringAsFixed(2)} kg',
//                               style: const TextStyle(fontSize: 13),
//                             ),
//                         ],
//                       ],

//                       const SizedBox(height: 2),
//                       Text(
//                         'Count: ${docs.length} measurements',
//                         style: const TextStyle(
//                           fontSize: 13,
//                           color: Colors.black54,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               );
//             },
//           ),
//         ),
//       ),
//     );
//   }

//   // ----- helpers -----

//   String _prettyUnit(String u) {
//     switch (u) {
//       case 'm2':
//         return 'm²';
//       case 'm3':
//         return 'm³';
//       default:
//         return u;
//     }
//   }

//   String _buildTitle() {
//     final label = activeLabel ?? '';
//     final boq = activeBoqCode ?? '';
//     if (label.isEmpty && boq.isEmpty) return 'Active item summary';
//     if (label.isNotEmpty && boq.isNotEmpty) {
//       return '$label (BOQ $boq)';
//     }
//     if (label.isNotEmpty) return label;
//     return 'BOQ $boq';
//   }

//   Widget _buildCardBody(BuildContext context, {required Widget child}) {
//     return child;
//   }
// }

import 'dart:async';
import 'dart:math' as math;

import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/dashboards/controllers/project_buildings_controller.dart';
import 'package:aqs/features/takeoff/controllers/image_takeoff_controller.dart';
import 'package:aqs/features/utils/helpers/boq_helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ActiveItemSummaryPanel extends StatelessWidget {
  final String drawingId;
  final CollectionReference<Map<String, dynamic>> measurementsRef;
  final String? activeMeasureType;
  final String? activeLabel;
  final String? activeBoqCode;
  final String? activeUnit;
  final int pendingTimberMemberCount;
  final bool savingTimberTruss;
  final Future<bool> Function()? onSaveTimberTruss;
  final VoidCallback? onDiscardTimberTruss;

  const ActiveItemSummaryPanel({
    super.key,
    required this.drawingId,
    required this.measurementsRef,
    required this.activeMeasureType,
    this.activeLabel,
    this.activeBoqCode,
    this.activeUnit,
    this.pendingTimberMemberCount = 0,
    this.savingTimberTruss = false,
    this.onSaveTimberTruss,
    this.onDiscardTimberTruss,
  });

  @override
  Widget build(BuildContext context) {
    final showDrawingRegister =
        activeMeasureType == null || activeMeasureType!.trim().isEmpty;
    final measureType = activeMeasureType?.trim() ?? '';
    final mtLower = measureType.toLowerCase();
    final bool isRoofStructure =
        mtLower == 'trusstemplate' ||
        mtLower == 'roofstructure' ||
        mtLower == 'roofstructuremember';

    Query<Map<String, dynamic>> q = measurementsRef.where(
      'drawingId',
      isEqualTo: drawingId,
    );

    String canonicalMeasureType(dynamic value) {
      final normalized = (value ?? '')
          .toString()
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[_\s-]+'), '');
      switch (normalized) {
        case 'footingcomposite':
          return 'compositefooting';
        case 'slabcomposite':
          return 'compositeslab';
        case 'beamcomposite':
          return 'compositebeam';
        case 'columncomposite':
          return 'compositecolumn';
        case 'ceilingfinish':
        case 'ceilingfinishes':
        case 'ceilingfinishings':
          return 'ceiling';
        case 'liftshaft':
        case 'liftshaftassembly':
        case 'liftshafttakeoff':
        case 'liftshaftassemblytakeoff':
        case 'liftshaftcomposite':
          return 'liftshaft';
        default:
          return normalized;
      }
    }

    final canonicalActiveMeasureType = canonicalMeasureType(measureType);
    final bool isLiftShaft = canonicalActiveMeasureType == 'liftshaft';
    final bool isPavement = canonicalActiveMeasureType == 'pavement';
    final bool isRoadProfile = canonicalActiveMeasureType == 'roadprofile';

    final bool isWalling = mtLower == 'walling';
    final bool isAreaMeasurement = mtLower == 'area';
    final bool isSlabComposite =
        mtLower == 'compositeslab' || mtLower == 'slabcomposite';
    final bool isFootingComposite =
        mtLower == 'compositefooting' || mtLower == 'footingcomposite';
    final bool isBeamComposite =
        mtLower == 'compositebeam' || mtLower == 'beamcomposite';
    final bool isColumnComposite =
        mtLower == 'compositecolumn' || mtLower == 'columncomposite';
    final bool isRoofSheetTimber =
        mtLower == 'roofsheetingandtimber' ||
        mtLower == 'roofingtimber' ||
        mtLower == 'roofsheeting' ||
        mtLower == 'compositeroofing';
    final bool isFoundationWall =
        mtLower == 'foundationwall' ||
        mtLower == 'compositefoundationwall' ||
        mtLower == 'foundationwallcomposite' ||
        mtLower == 'foundation_wall';

    return Align(
      alignment: Alignment.topRight,
      child: Card(
        margin: const EdgeInsets.only(right: 12, top: 12),
        color: Colors.white.withValues(alpha: 0.97),
        elevation: 10,
        shadowColor: AqsColors.primary.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AqsColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: q.stateSnapshots(),
            builder: (ctx, snap) {
              if (snap.hasError) {
                debugPrint('ActiveItemSummaryPanel error: ${snap.error}');
                return _buildCardBody(
                  context,
                  child: Text(
                    'Error loading summary:\n${snap.error}',
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              }

              if (!snap.hasData) {
                return _buildCardBody(
                  context,
                  child: const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }

              final docs =
                  snap.data!.docs.where((doc) {
                    if (showDrawingRegister) return true;
                    final type = canonicalMeasureType(
                      doc.data()['measureType'] ?? doc.data()['typeGroup'],
                    );
                    if (isRoofStructure) {
                      return type == 'roofstructuremember' ||
                          type == 'roofstructureaccessory' ||
                          type == 'roofstructuresupport';
                    }
                    return type == canonicalActiveMeasureType;
                  }).toList();
              if (showDrawingRegister) {
                return _buildCardBody(
                  context,
                  child: _drawingTakeoffRegister(
                    context,
                    docs,
                    canonicalMeasureType,
                  ),
                );
              }
              if (docs.isEmpty) {
                return _buildCardBody(
                  context,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _summaryHero(
                          title: _buildTitle(),
                          subtitle:
                              isRoofStructure
                                  ? 'Tap two points to record the first roof member.'
                                  : 'Your live quantities will appear here.',
                          icon:
                              isRoofStructure
                                  ? Icons.change_history_rounded
                                  : Icons.straighten_rounded,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Ready to measure',
                          style: TextStyle(
                            color: AqsColors.text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isRoofStructure
                              ? 'Start point → end point → classify member and link BOQ items.'
                              : 'Measurements saved on this drawing will update the summary automatically.',
                          style: const TextStyle(
                            color: AqsColors.muted,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                        if (mtLower == 'compositeroofing' &&
                            pendingTimberMemberCount > 0) ...[
                          const SizedBox(height: 12),
                          Text(
                            '$pendingTimberMemberCount timber member${pendingTimberMemberCount == 1 ? '' : 's'} waiting in the current truss.',
                            style: const TextStyle(
                              color: AqsColors.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed:
                                  savingTimberTruss || onSaveTimberTruss == null
                                      ? null
                                      : () async {
                                        await onSaveTimberTruss!.call();
                                      },
                              icon:
                                  savingTimberTruss
                                      ? const SizedBox(
                                        width: 15,
                                        height: 15,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.cloud_done_outlined),
                              label: Text(
                                savingTimberTruss
                                    ? 'Saving truss…'
                                    : 'Save truss',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }

              double _num(dynamic v) =>
                  (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

              if (isLiftShaft) {
                final assemblies = docs.map(_measurementGroupId).toSet();
                final totalsByUnit = <String, double>{};
                final itemLabels = <String>{};

                String summaryUnit(dynamic value) {
                  final unit = (value ?? '').toString().trim().toLowerCase();
                  switch (unit) {
                    case 'm3':
                    case 'm³':
                      return 'm³';
                    case 'm2':
                    case 'm²':
                      return 'm²';
                    case 'kg':
                      return 'kg';
                    case 'm':
                    case 'lm':
                      return 'm';
                    case 'no':
                    case 'nr':
                    case 'nos':
                    case 'item':
                    case 'items':
                    case 'each':
                      return 'no';
                    default:
                      return unit;
                  }
                }

                for (final doc in docs) {
                  final m = doc.data();
                  final unit = summaryUnit(m['unit']);
                  if (unit.isNotEmpty) {
                    totalsByUnit.update(
                      unit,
                      (total) => total + _num(m['value'] ?? m['quantity']),
                      ifAbsent: () => _num(m['value'] ?? m['quantity']),
                    );
                  }
                  itemLabels.add(_savedItemLabel(m));
                }
                final sortedItemLabels = itemLabels.toList()..sort();
                const preferredUnits = ['m³', 'm²', 'kg', 'm', 'no'];
                final units = <String>[
                  ...preferredUnits.where(totalsByUnit.containsKey),
                  ...totalsByUnit.keys.where(
                    (unit) => !preferredUnits.contains(unit),
                  ),
                ];

                return _buildCardBody(
                  context,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _summaryHero(
                          title: 'Lift shaft summary',
                          subtitle:
                              '${assemblies.length} measurement${assemblies.length == 1 ? '' : 's'} · ${docs.length} saved item${docs.length == 1 ? '' : 's'}',
                          icon: Icons.elevator_outlined,
                        ),
                        if (units.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final unit in units)
                                SizedBox(
                                  width: 108,
                                  child: _summaryMetric(
                                    'Total $unit',
                                    totalsByUnit[unit]!,
                                    unit,
                                  ),
                                ),
                            ],
                          ),
                        ],
                        if (sortedItemLabels.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Saved lift-shaft items',
                            style: TextStyle(
                              color: AqsColors.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 150),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: sortedItemLabels.length,
                              separatorBuilder:
                                  (_, __) => const SizedBox(height: 4),
                              itemBuilder:
                                  (_, index) => Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(top: 5),
                                        child: Icon(
                                          Icons.circle,
                                          size: 5,
                                          color: AqsColors.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          sortedItemLabels[index],
                                          style: const TextStyle(
                                            color: AqsColors.text,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }

              if (isPavement) {
                final pavementGroups = <String>{};
                final countedZones = <String>{};
                final totalsByUnit = <String, double>{};
                var netAreaM2 = 0.0;

                String pavementUnit(dynamic value) {
                  final unit = (value ?? '').toString().trim().toLowerCase();
                  switch (unit) {
                    case 'm3':
                    case 'm³':
                      return 'm³';
                    case 'm2':
                    case 'm²':
                      return 'm²';
                    case 'ha':
                      return 'ha';
                    case 'm':
                    case 'lm':
                      return 'm';
                    case 'no':
                    case 'no.':
                    case 'nr':
                    case 'nos':
                      return 'no';
                    default:
                      return unit;
                  }
                }

                for (final doc in docs) {
                  final data = doc.data();
                  final pavementGroup =
                      (data['pavementGroupId'] ?? '').toString().trim();
                  if (pavementGroup.isNotEmpty) {
                    pavementGroups.add(pavementGroup);
                  }

                  final zoneId =
                      (data['areaGroupId'] ??
                              '$pavementGroup-${data['polygonIndex'] ?? 0}')
                          .toString()
                          .trim();
                  if (countedZones.add(zoneId)) {
                    netAreaM2 += _num(
                      data['polygonNetAreaM2'] ?? data['polygonAreaM2'],
                    );
                  }

                  final unit = pavementUnit(data['unit']);
                  if (unit.isNotEmpty) {
                    totalsByUnit.update(
                      unit,
                      (total) => total + _num(data['value']),
                      ifAbsent: () => _num(data['value']),
                    );
                  }
                }

                const preferredUnits = ['m³', 'm²', 'ha', 'm', 'no'];
                final units = <String>[
                  ...preferredUnits.where(totalsByUnit.containsKey),
                  ...totalsByUnit.keys.where(
                    (unit) => !preferredUnits.contains(unit),
                  ),
                ];

                return _buildCardBody(
                  context,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _summaryHero(
                          title: 'Pavement area summary',
                          subtitle:
                              '${pavementGroups.length} take-off${pavementGroups.length == 1 ? '' : 's'} · ${countedZones.length} area${countedZones.length == 1 ? '' : 's'}',
                          icon: Icons.texture_rounded,
                        ),
                        const SizedBox(height: 12),
                        _summaryStatCard(
                          icon: Icons.crop_square_rounded,
                          label: 'Net pavement area',
                          value: netAreaM2.toStringAsFixed(3),
                          unit: 'm²',
                          color: AqsColors.primary,
                        ),
                        if (units.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final unit in units)
                                SizedBox(
                                  width: 108,
                                  child: _summaryMetric(
                                    'BOQ total',
                                    totalsByUnit[unit]!,
                                    unit,
                                  ),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        _countPill('Saved outputs', docs.length),
                      ],
                    ),
                  ),
                );
              }

              if (isRoadProfile) {
                final roadGroups = <String, Map<String, dynamic>>{};
                for (final doc in docs) {
                  final data = doc.data();
                  final groupId =
                      (data['roadProfileGroupId'] ?? doc.id).toString().trim();
                  roadGroups.putIfAbsent(
                    groupId.isEmpty ? doc.id : groupId,
                    () => data,
                  );
                }
                final measurements = roadGroups.values.toList();

                return _buildCardBody(
                  context,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _titleRow(),
                        const SizedBox(height: 12),
                        const Text(
                          'All measurements',
                          style: TextStyle(
                            color: AqsColors.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 7),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 360),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: measurements.length,
                            separatorBuilder:
                                (_, __) => const SizedBox(height: 6),
                            itemBuilder: (_, index) {
                              final data = measurements[index];
                              var length = _num(data['lengthM']);
                              final unit =
                                  (data['unit'] ?? '')
                                      .toString()
                                      .trim()
                                      .toLowerCase();
                              if (length <= 0 &&
                                  (unit == 'm' || unit == 'lm')) {
                                length = _num(
                                  data['value'] ?? data['quantity'],
                                );
                              }
                              return _roadProfileMeasurementRow(
                                index: index + 1,
                                lengthM: length,
                                profile: (data['roadProfile'] ?? '').toString(),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        _countPill('Measurements', measurements.length),
                      ],
                    ),
                  ),
                );
              }

              if (mtLower == 'door' || mtLower == 'compositedoor') {
                final seenGroups = <String>{};
                var doorCount = 0.0;
                var panelQty = 0.0;
                var frameLength = 0.0;
                var finishArea = 0.0;
                var ventArea = 0.0;
                var ventGlassArea = 0.0;
                var ironmongeryItems = 0;
                for (final doc in docs) {
                  final m = doc.data();
                  final groupId =
                      (m['doorGroupId'] ?? m['countGroupId'] ?? doc.id)
                          .toString()
                          .trim();
                  if (seenGroups.add(groupId)) {
                    doorCount += _num(m['doorCount']);
                  }
                  final key = (m['componentKey'] ?? '').toString();
                  if (key == 'panel') panelQty += _num(m['value']);
                  if (key == 'frame') frameLength += _num(m['value']);
                  if (key == 'finish') finishArea += _num(m['value']);
                  if (key == 'vent') ventArea += _num(m['value']);
                  if (key == 'ventGlass') ventGlassArea += _num(m['value']);
                  if ({
                    'hinges',
                    'lockset',
                    'cylinder',
                    'closer',
                    'kickPlate',
                    'pushPlate',
                    'pullPlate',
                    'pullHandle',
                    'wcIndicator',
                    'signage',
                    'doorStop',
                  }.contains(key)) {
                    ironmongeryItems++;
                  }
                }
                final panelUnit =
                    docs.any(
                          (doc) =>
                              (doc.data()['componentKey'] ?? '') == 'panel' &&
                              (doc.data()['unit'] ?? '') == 'm2',
                        )
                        ? 'm²'
                        : 'No';
                return _buildCardBody(
                  context,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _summaryHero(
                          title: 'Door Take-off Summary',
                          subtitle:
                              '${seenGroups.length} door type${seenGroups.length == 1 ? '' : 's'} · ${doorCount.toStringAsFixed(0)} counted',
                          icon: Icons.door_front_door_outlined,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _summaryMetric(
                                'Door panel',
                                panelQty,
                                panelUnit,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _summaryMetric('Frame', frameLength, 'm'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _summaryMetric(
                                'Vent / fanlight',
                                ventArea,
                                'm²',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _summaryMetric(
                                'Vent glass',
                                ventGlassArea,
                                'm²',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _summaryMetric(
                                'Finish (2 faces)',
                                finishArea,
                                'm²',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _summaryMetric(
                                'Ironmongery links',
                                ironmongeryItems.toDouble(),
                                '',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (mtLower == 'count') {
                final seenGroups = <String>{};
                var total = 0.0;
                var groups = 0;
                var markers = 0;
                for (final doc in docs) {
                  final m = doc.data();
                  final groupId =
                      (m['countGroupId'] ?? doc.id).toString().trim();
                  if (seenGroups.contains(groupId)) continue;
                  seenGroups.add(groupId);
                  groups++;
                  total += _num(m['value'] ?? m['count'] ?? m['baseValue']);
                  final points = m['points'];
                  markers += points is List ? points.length : 0;
                }

                return _buildCardBody(
                  context,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 330),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _summaryHero(
                          title: 'Count Summary',
                          subtitle:
                              '$groups count session${groups == 1 ? '' : 's'} · $markers marked object${markers == 1 ? '' : 's'}',
                          icon: Icons.fact_check_outlined,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _summaryMetric('Quantity', total, 'nr'),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _summaryMetric(
                                'Sessions',
                                groups.toDouble(),
                                '',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (isRoofStructure) {
                double measuredLengthM = 0;
                double steelWeightKg = 0;
                double cleats = 0;
                double bolts = 0;
                double plates = 0;
                double basePlates = 0;
                double anchorBolts = 0;
                int memberCount = 0;
                final groups = <String>{};

                for (final doc in docs) {
                  final m = doc.data();
                  final recordType = (m['measureType'] ?? '').toString();
                  final type = (m['type'] ?? '').toString();
                  final value = _num(m['value']);
                  final group = (m['roofGroupId'] ?? '').toString().trim();
                  if (group.isNotEmpty) groups.add(group);

                  if (recordType == 'roofStructureMember') {
                    memberCount++;
                    measuredLengthM += _num(
                      m['totalLengthM'] ?? m['measuredLengthM'],
                    );
                    steelWeightKg += value;
                  } else if (type == 'cleat') {
                    cleats += value;
                  } else if (type == 'bolt') {
                    bolts += value;
                  } else if (type == 'gussetPlate') {
                    plates += value;
                  } else if (type == 'basePlate') {
                    basePlates += value;
                  } else if (type == 'anchorBolt') {
                    anchorBolts += value;
                  }
                }

                return _buildCardBody(
                  context,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 310),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _summaryHero(
                          title: 'Roof structure',
                          subtitle:
                              '${groups.length} truss session${groups.length == 1 ? '' : 's'} · $memberCount measured member${memberCount == 1 ? '' : 's'}',
                          icon: Icons.change_history_rounded,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _summaryMetric(
                                'Member length',
                                measuredLengthM,
                                'm',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _summaryMetric(
                                'Steel weight',
                                steelWeightKg,
                                'kg',
                              ),
                            ),
                          ],
                        ),
                        if (cleats > 0 ||
                            bolts > 0 ||
                            plates > 0 ||
                            basePlates > 0 ||
                            anchorBolts > 0) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Linked BOQ accessories',
                            style: TextStyle(
                              color: AqsColors.text,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (cleats > 0) _quantityPill('Cleats', cleats),
                              if (bolts > 0) _quantityPill('Bolts', bolts),
                              if (plates > 0)
                                _quantityPill('Gusset plates', plates),
                              if (basePlates > 0)
                                _quantityPill('Base plates', basePlates),
                              if (anchorBolts > 0)
                                _quantityPill('Anchor bolts', anchorBolts),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }

              if (mtLower == 'roofsheeting' || mtLower == 'compositeroofing') {
                double sheetingM2 = 0;
                double ridgeM = 0;
                double hipM = 0;
                double valleyM = 0;
                double purlinsM = 0;
                double raftersM = 0;
                double wallPlatesM = 0;
                double tieBeamsM = 0;
                double kingPostsM = 0;
                double strutsM = 0;
                double boltsNos = 0;
                double otherTimberM = 0;
                final roofGroups = <String>{};

                for (final d in docs) {
                  final m = d.data();
                  final type = (m['type'] ?? '').toString();
                  final timberType =
                      (m['timberMemberType'] ?? m['memberType'] ?? '')
                          .toString();
                  final value = _num(m['value']);
                  final group = (m['roofGroupId'] ?? '').toString().trim();
                  if (group.isNotEmpty) roofGroups.add(group);

                  switch (type) {
                    case 'roofSheeting':
                      sheetingM2 += value;
                      break;
                    case 'roofRidgeCapping':
                      ridgeM += value;
                      break;
                    case 'roofHipCapping':
                      hipM += value;
                      break;
                    case 'roofValleys':
                      valleyM += value;
                      break;
                    case 'roofPurlins50x50':
                      purlinsM += value;
                      break;
                    case 'roofRafters150x50':
                      raftersM += value;
                      break;
                    case 'roofWallPlates150x50':
                      wallPlatesM += value;
                      break;
                    case 'roofTieBeams150x50':
                      tieBeamsM += value;
                      break;
                    case 'roofKingPosts150x50':
                      kingPostsM += value;
                      break;
                    case 'roofStrutsPosts100x50':
                      strutsM += value;
                      break;
                  }

                  switch (timberType) {
                    case 'purlin':
                      purlinsM += value;
                      break;
                    case 'rafter':
                      raftersM += value;
                      break;
                    case 'wallPlate':
                      wallPlatesM += value;
                      break;
                    case 'tieBeam':
                      tieBeamsM += value;
                      break;
                    case 'kingPost':
                      kingPostsM += value;
                      break;
                    case 'strut':
                      strutsM += value;
                      break;
                    case 'bolt':
                      boltsNos += value;
                      break;
                    case 'other':
                      otherTimberM += value;
                      break;
                  }
                }

                final isCovering = mtLower == 'roofsheeting';
                return _buildCardBody(
                  context,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 330),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _summaryHero(
                          title:
                              isCovering
                                  ? 'Roof covering'
                                  : 'Timber roof structure',
                          subtitle:
                              '${roofGroups.length} roof panel${roofGroups.length == 1 ? '' : 's'} measured',
                          icon:
                              isCovering
                                  ? Icons.roofing_rounded
                                  : Icons.carpenter_rounded,
                        ),
                        const SizedBox(height: 12),
                        if (isCovering) ...[
                          Row(
                            children: [
                              Expanded(
                                child: _summaryMetric(
                                  'Roof sheets',
                                  sheetingM2,
                                  'm²',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _summaryMetric(
                                  'Cappings',
                                  ridgeM + hipM + valleyM,
                                  'm',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _quantityPill('Ridge m', ridgeM),
                              _quantityPill('Hip m', hipM),
                              _quantityPill('Valley m', valleyM),
                            ],
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: _summaryMetric('Purlins', purlinsM, 'm'),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _summaryMetric('Rafters', raftersM, 'm'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _quantityPill('Wall plates m', wallPlatesM),
                              _quantityPill('Tie beams m', tieBeamsM),
                              _quantityPill('King posts m', kingPostsM),
                              _quantityPill('Struts m', strutsM),
                              if (boltsNos > 0)
                                _quantityPill('Bolts Nos', boltsNos),
                              if (otherTimberM > 0)
                                _quantityPill('Other m', otherTimberM),
                            ],
                          ),
                          if (pendingTimberMemberCount > 0) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF4FF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFC7D7FE),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.inventory_2_outlined,
                                    size: 18,
                                    color: AqsColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '$pendingTimberMemberCount member${pendingTimberMemberCount == 1 ? '' : 's'} in current truss',
                                      style: const TextStyle(
                                        color: AqsColors.text,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (onDiscardTimberTruss != null)
                                  TextButton(
                                    onPressed:
                                        savingTimberTruss
                                            ? null
                                            : onDiscardTimberTruss,
                                    child: const Text('Discard draft'),
                                  ),
                                const Spacer(),
                                FilledButton.icon(
                                  onPressed:
                                      savingTimberTruss ||
                                              onSaveTimberTruss == null
                                          ? null
                                          : () async {
                                            await onSaveTimberTruss!.call();
                                          },
                                  icon:
                                      savingTimberTruss
                                          ? const SizedBox(
                                            width: 15,
                                            height: 15,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                          : const Icon(
                                            Icons.cloud_done_outlined,
                                          ),
                                  label: Text(
                                    savingTimberTruss
                                        ? 'Saving truss…'
                                        : 'Save truss',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                );
              }

              if (mtLower == 'plinth') {
                double plasteringM2 = 0;
                double bitumenM2 = 0;
                double concreteBedM2 = 0;
                double concreteBedM3 = 0;
                double concreteBedEdgeM = 0;
                double fabricMeshM2 = 0;
                final groups = <String>{};

                for (final doc in docs) {
                  final data = doc.data();
                  final type =
                      (data['type'] ?? '').toString().trim().toLowerCase();
                  final value = _num(data['value']);
                  final group = (data['plinthGroupId'] ?? '').toString().trim();
                  if (group.isNotEmpty) groups.add(group);

                  switch (type) {
                    case 'plinthplastering':
                      plasteringM2 += value;
                      break;
                    case 'plinthbitumenpainting':
                      bitumenM2 += value;
                      break;
                    case 'plinthconcretebedarea':
                      concreteBedM2 += value;
                      break;
                    case 'plinthconcretebedvolume':
                      concreteBedM3 += value;
                      break;
                    case 'plinthconcretebededge':
                      concreteBedEdgeM += value;
                      break;
                    case 'plinthfabricmesh':
                      fabricMeshM2 += value;
                      break;
                  }
                }

                return _buildCardBody(
                  context,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _summaryHero(
                          title: 'Plinth',
                          subtitle:
                              '${groups.length} polygon${groups.length == 1 ? '' : 's'} measured',
                          icon: Icons.layers_outlined,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _summaryMetric(
                                'Plastering',
                                plasteringM2,
                                'm²',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _summaryMetric(
                                'Bitumen paint',
                                bitumenM2,
                                'm²',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (concreteBedM2 > 0)
                              _quantityPill('Concrete bed m²', concreteBedM2),
                            if (concreteBedM3 > 0)
                              _quantityPill('Concrete bed m³', concreteBedM3),
                            if (concreteBedEdgeM > 0)
                              _quantityPill(
                                'Concrete-bed edge m',
                                concreteBedEdgeM,
                              ),
                            if (fabricMeshM2 > 0)
                              _quantityPill('Fabric mesh m²', fabricMeshM2),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _saasMeasurementFooter(docs.length),
                      ],
                    ),
                  ),
                );
              }

              if (mtLower == 'tiling') {
                double floorTilesM2 = 0;
                double wallTilesM2 = 0;
                double backingBedM2 = 0;
                double skirtingM = 0;
                double openingDeductionsM2 = 0;
                final groups = <String>{};

                for (final d in docs) {
                  final m = d.data();
                  final type = (m['type'] ?? '').toString();
                  final value = _num(m['value']);
                  final group = (m['tileGroupId'] ?? '').toString().trim();
                  if (group.isNotEmpty) groups.add(group);

                  if (type == 'floorTiles') {
                    floorTilesM2 += value;
                  } else if (type == 'wallTiles') {
                    wallTilesM2 += value;
                    openingDeductionsM2 += _num(m['openingDeductionM2']);
                  } else if (type == 'tileBackingBed') {
                    backingBedM2 += value;
                  } else if (type == 'tileSkirting') {
                    skirtingM += value;
                  }
                }

                return _buildCardBody(
                  context,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 330),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _summaryHero(
                          title: 'Tiles',
                          subtitle:
                              '${groups.length} tile area${groups.length == 1 ? '' : 's'} measured',
                          icon: Icons.grid_on_rounded,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _summaryMetric(
                                'Floor tiles',
                                floorTilesM2,
                                'm²',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _summaryMetric(
                                'Wall tiles',
                                wallTilesM2,
                                'm²',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (backingBedM2 > 0)
                              _quantityPill('Backing bed m²', backingBedM2),
                            if (skirtingM > 0)
                              _quantityPill('Skirting m', skirtingM),
                            if (openingDeductionsM2 > 0)
                              _quantityPill(
                                'Openings deducted m²',
                                openingDeductionsM2,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (isFoundationWall) {
                double excavationM3 = 0;
                double backfillM3 = 0;
                double disposalM3 = 0;
                double blindingM2 = 0;
                double stripConcreteM3 = 0;
                double stripFormworkM2 = 0;
                double wallAreaM2 = 0;
                final segmentIds = <String>{};
                final groupIds = <String>{};
                final lengthBySegment = <String, double>{};

                for (final d in docs) {
                  final m = d.data();
                  final type = (m['type'] ?? '').toString();
                  final value = _num(m['value']);
                  final segmentId = (m['segmentId'] ?? '').toString().trim();
                  final groupId =
                      (m['foundationGroupId'] ?? '').toString().trim();

                  if (segmentId.isNotEmpty) segmentIds.add(segmentId);
                  if (groupId.isNotEmpty) groupIds.add(groupId);

                  switch (type) {
                    case 'excavation':
                      excavationM3 += value;
                      break;
                    case 'backfill':
                      backfillM3 += value;
                      break;
                    case 'disposal':
                      disposalM3 += value;
                      break;
                    case 'blinding':
                      blindingM2 += value;
                      break;
                    case 'stripConcrete':
                      stripConcreteM3 += value;
                      break;
                    case 'stripFormwork2Side':
                      stripFormworkM2 += value;
                      break;
                    case 'foundationWall':
                      wallAreaM2 += value;
                      break;
                  }

                  if (type != 'foundationWallGroup' &&
                      segmentId.isNotEmpty &&
                      !lengthBySegment.containsKey(segmentId)) {
                    lengthBySegment[segmentId] = _num(m['lengthEachM']);
                  }
                }
                final totalLengthM = lengthBySegment.values.fold<double>(
                  0,
                  (sum, value) => sum + value,
                );

                return _buildCardBody(
                  context,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 330),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _summaryHero(
                          title: 'Foundation wall',
                          subtitle:
                              '${segmentIds.length} segment${segmentIds.length == 1 ? '' : 's'} · ${groupIds.length} group${groupIds.length == 1 ? '' : 's'}',
                          icon: Icons.account_balance_rounded,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _summaryMetric(
                                'Excavation',
                                excavationM3,
                                'm³',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _summaryMetric(
                                'Backfill',
                                backfillM3,
                                'm³',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _summaryMetric(
                                'Disposal',
                                disposalM3,
                                'm³',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _summaryMetric(
                                'Wall area',
                                wallAreaM2,
                                'm²',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _quantityPill('Length m', totalLengthM),
                            _quantityPill('Blinding m²', blindingM2),
                            _quantityPill('Strip m³', stripConcreteM3),
                            _quantityPill('Strip FW m²', stripFormworkM2),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }

              // ---------------------------------------------------------
              // WALLING SUMMARY (NET area = gross - openings)
              // ---------------------------------------------------------
              if (isWalling) {
                final openingsQ = measurementsRef
                    .where('drawingId', isEqualTo: drawingId)
                    .where('measureType', isEqualTo: 'wallingOpening');

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: openingsQ.stateSnapshots(),
                  builder: (ctx2, openSnap) {
                    double totalLenM = 0.0;
                    double heightM = 0.0;
                    double grossAreaM2 = 0.0;
                    final wallGroupIds = <String>{};

                    for (final d in docs) {
                      final m = d.data();
                      totalLenM += _num(m['baseLengthM']);
                      if (heightM == 0.0) heightM = _num(m['heightM']);
                      grossAreaM2 += _num(m['value']);

                      final gid = (m['wallGroupId'] ?? '').toString().trim();
                      if (gid.isNotEmpty) wallGroupIds.add(gid);
                    }

                    if (grossAreaM2 == 0.0 && totalLenM > 0 && heightM > 0) {
                      grossAreaM2 = totalLenM * heightM;
                    }

                    double openingsAreaM2 = 0.0;
                    int openingItems = 0;

                    if (openSnap.hasData) {
                      for (final d in openSnap.data!.docs) {
                        final m = d.data();
                        final comp = (m['component'] ?? '').toString();
                        if (comp == 'deduction' || comp == 'window') {
                          openingsAreaM2 += _num(m['value']);
                          openingItems++;
                        }
                      }
                    }

                    final netAreaM2 = (grossAreaM2 - openingsAreaM2).clamp(
                      0.0,
                      double.infinity,
                    );

                    return _buildCardBody(
                      context,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 310),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _summaryHero(
                              title: 'Walling summary',
                              subtitle:
                                  '${wallGroupIds.length} group${wallGroupIds.length == 1 ? '' : 's'} · ${docs.length} wall segment${docs.length == 1 ? '' : 's'}',
                              icon: Icons.view_week_outlined,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _summaryMetric(
                                    'Net area',
                                    netAreaM2,
                                    'm²',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _summaryMetric(
                                    'Gross area',
                                    grossAreaM2,
                                    'm²',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _quantityPill('Length m', totalLenM),
                                if (heightM > 0)
                                  _quantityPill('Height m', heightM),
                                _quantityPill('Openings m²', openingsAreaM2),
                                _countPill('Groups', wallGroupIds.length),
                                _countPill('Segments', docs.length),
                                _countPill('Openings', openingItems),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }

              // ---------------------------------------------------------
              // AGGREGATION (generic + composites)
              // ---------------------------------------------------------
              double totalValue = 0.0;
              String? unitFromDocs;

              // rebar totals (slab/footing/beam/column if you add later)
              double totalRebarLengthM = 0.0;
              double totalRebarWeightKg = 0.0;

              // footing
              double footingConcreteTotalM3 = 0.0;
              double footingFormworkTotalM2 = 0.0;
              double footingExcavationTotalM3 = 0.0;
              double footingBlindingTotalM2 = 0.0;
              double footingBackfillTotalM3 = 0.0;
              double footingDisposalTotalM3 = 0.0;

              // slab
              double slabConcreteTotalM2 = 0.0;
              double slabConcreteTotalM3 = 0.0;
              double slabSoffitFormworkTotalM2 = 0.0;
              double slabEdgeFormworkTotalM = 0.0;
              double slabEdgeFormworkTotalM2 = 0.0;
              double totalSlabPanelAreaM2 = 0.0;
              final countedSlabAreaIds = <String>{};

              // beam
              double beamConcreteTotalM3 = 0.0;
              double beamSideFormworkTotalM2 = 0.0;
              double beamSoffitFormworkTotalM2 = 0.0;
              double beamTotalLengthM = 0.0;

              // column ✅ NEW
              double columnConcreteTotalM3 = 0.0;
              double columnFormworkTotalM2 = 0.0;
              double columnMainRebarTotalKg = 0.0;
              double columnStirrupsTotalKg = 0.0;
              double columnMainRebarLengthM = 0.0;
              double columnStirrupsLengthM = 0.0;
              int columnQtyTotal = 0;
              double columnTotalHeightM = 0.0;
              final columnIds = <String>{};
              final countedColumnGeometry = <String>{};

              for (final d in docs) {
                final m = d.data();
                final type = (m['type'] ?? '').toString();
                final rawV = m['value'];
                final double value = (rawV is num) ? rawV.toDouble() : 0.0;

                final u = (m['unit'] ?? '').toString();
                unitFromDocs ??= u.isNotEmpty ? u : null;

                // generic total only for non-composites
                if (!isSlabComposite &&
                    !isFootingComposite &&
                    !isBeamComposite &&
                    !isColumnComposite) {
                  totalValue += value;
                }

                // footing
                if (type == 'footingConcrete') {
                  footingConcreteTotalM3 += value;
                } else if (type == 'footingFormwork' ||
                    type == 'footingSideFormwork') {
                  footingFormworkTotalM2 += value;
                } else if (type == 'rebarFooting' ||
                    type == 'footingRebarAuto') {
                  final lenAll =
                      (m['lengthAllFootingsM'] as num?)?.toDouble() ??
                      (m['totalLengthM'] as num?)?.toDouble() ??
                      0.0;
                  final wtAll =
                      (m['weightAllFootingsKg'] as num?)?.toDouble() ??
                      (m['totalWeightKg'] as num?)?.toDouble() ??
                      value;
                  totalRebarLengthM += lenAll;
                  totalRebarWeightKg += wtAll;
                } else if (type == 'earthworkExcavation') {
                  footingExcavationTotalM3 += value;
                } else if (type == 'earthworkBlinding') {
                  footingBlindingTotalM2 += value;
                } else if (type == 'footingBackfill') {
                  footingBackfillTotalM3 += value;
                } else if (type == 'footingDisposal') {
                  footingDisposalTotalM3 += value;
                }

                // slab
                if (type == 'slabConcrete') {
                  final normalizedUnit = u.toLowerCase().replaceAll('²', '2');
                  if (normalizedUnit == 'm2' ||
                      normalizedUnit == 'sqm' ||
                      normalizedUnit == 'square meter' ||
                      normalizedUnit == 'square metre') {
                    slabConcreteTotalM2 += value;
                  } else {
                    slabConcreteTotalM3 += value;
                  }

                  final areaId =
                      (m['segmentId'] ??
                              m['slabGroupId'] ??
                              m['slabId'] ??
                              d.id)
                          .toString()
                          .trim();
                  if (areaId.isNotEmpty && countedSlabAreaIds.add(areaId)) {
                    final areaOne = _num(
                      m['polygonAreaM2_one'] ?? m['areaM2_one'] ?? m['areaM2'],
                    );
                    final totalQty = _num(
                      m['totalQty'],
                    ).clamp(1, double.infinity);
                    final areaTotal =
                        normalizedUnit == 'm2' ? value : areaOne * totalQty;
                    if (areaTotal > 0) totalSlabPanelAreaM2 += areaTotal;
                  }
                } else if (type == 'slabFormworkSoffit' ||
                    type == 'slabSoffitFormwork') {
                  slabSoffitFormworkTotalM2 += value;
                } else if (type == 'slabFormworkEdge' ||
                    type == 'slabEdgeFormwork') {
                  final thicknessM = _num(m['thicknessM']);
                  final normalizedEdgeUnit = u.toLowerCase().replaceAll(
                    '²',
                    '2',
                  );
                  final usesLinearMetres =
                      normalizedEdgeUnit == 'm' ||
                      (thicknessM > 0 && thicknessM <= 0.15);
                  if (usesLinearMetres) {
                    final edgeOne = _num(m['exposedEdgeLenM_one']);
                    final totalQty = _num(
                      m['totalQty'],
                    ).clamp(1, double.infinity);
                    slabEdgeFormworkTotalM +=
                        edgeOne > 0 ? edgeOne * totalQty : value;
                  } else {
                    slabEdgeFormworkTotalM2 += value;
                  }
                } else if (type == 'rebarSlab' ||
                    type == 'rebarSlabManual' ||
                    type == 'rebarSlabAi' ||
                    (m['measureType'] ?? '') == 'slabRebarAi') {
                  final lenAll =
                      (m['totalLengthAllBarsM'] as num?)?.toDouble() ??
                      (m['totalLengthM'] as num?)?.toDouble() ??
                      0.0;
                  final wtAll =
                      (m['totalWeightKg'] as num?)?.toDouble() ?? value;
                  totalRebarLengthM += lenAll;
                  totalRebarWeightKg += wtAll;
                }

                // beam
                if (type == 'beamConcrete') {
                  beamConcreteTotalM3 += value;
                  final len = (m['lengthM'] as num?)?.toDouble() ?? 0.0;
                  beamTotalLengthM += len;
                } else if (type == 'beamFormworkSide') {
                  beamSideFormworkTotalM2 += value;
                } else if (type == 'beamFormworkSoffit') {
                  beamSoffitFormworkTotalM2 += value;
                } else if (type == 'rebarBeam' ||
                    type == 'rebarBeamLong' ||
                    type == 'rebarBeamRing' ||
                    type == 'rebarBeamMain' ||
                    type == 'rebarBeamMainSegment' ||
                    type == 'rebarBeamStirrups') {
                  final lenAll =
                      (m['lengthAllBeamsM'] as num?)?.toDouble() ??
                      (m['totalLengthAllBarsM'] as num?)?.toDouble() ??
                      (m['totalLengthAllStirrupsM'] as num?)?.toDouble() ??
                      0.0;
                  final wtAll =
                      (m['weightAllBeamsKg'] as num?)?.toDouble() ??
                      (m['totalWeightKg'] as num?)?.toDouble() ??
                      value;

                  totalRebarLengthM += lenAll;
                  totalRebarWeightKg += wtAll;
                }

                // column ✅ NEW
                if (type == 'columnConcrete') {
                  columnConcreteTotalM3 += value;
                  final cid =
                      (m['columnGroupId'] ??
                              m['columnId'] ??
                              m['segmentId'] ??
                              d.id)
                          .toString()
                          .trim();
                  if (cid.isNotEmpty) columnIds.add(cid);
                  if (countedColumnGeometry.add(cid)) {
                    final q =
                        (m['totalQty'] as num?)?.toInt() ??
                        (m['qty'] as num?)?.toInt() ??
                        1;
                    final height = _num(m['heightM']);
                    columnQtyTotal += q;
                    columnTotalHeightM += height * q;
                  }
                } else if (type == 'columnSideFormwork' ||
                    type == 'columnFormworkSides') {
                  columnFormworkTotalM2 += value;
                  final cid =
                      (m['columnGroupId'] ??
                              m['columnId'] ??
                              m['segmentId'] ??
                              '')
                          .toString()
                          .trim();
                  if (cid.isNotEmpty) columnIds.add(cid);
                } else if (type == 'columnGeom') {
                  // useful for qty/height even if concrete/formwork not included
                  final cid = (m['columnId'] ?? '').toString().trim();
                  if (cid.isNotEmpty) columnIds.add(cid);
                } else if (type == 'columnMainRebar' || type == 'rebarColumn') {
                  final totalQty = _num(
                    m['totalQty'],
                  ).clamp(1, double.infinity);
                  final lenAll = _num(
                    m['totalLengthAllBarsM'] ??
                        (_num(m['totalLengthPerColumnM']) * totalQty),
                  );
                  columnMainRebarLengthM += lenAll;
                  columnMainRebarTotalKg += value;
                  totalRebarLengthM += lenAll;
                  totalRebarWeightKg += value;
                } else if (type == 'columnStirrups') {
                  final totalQty = _num(
                    m['totalQty'],
                  ).clamp(1, double.infinity);
                  final lenAll =
                      _num(m['stirrupTotalLenPerColumnM']) * totalQty;
                  columnStirrupsLengthM += lenAll;
                  columnStirrupsTotalKg += value;
                  totalRebarLengthM += lenAll;
                  totalRebarWeightKg += value;
                }
              }

              final unit = activeUnit ?? unitFromDocs ?? '';
              final unitDisplay = _prettyUnit(unit);
              final hasRebarTotals =
                  totalRebarLengthM > 0 || totalRebarWeightKg > 0;

              return _buildCardBody(
                context,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth:
                        isBeamComposite ||
                                isFootingComposite ||
                                isColumnComposite ||
                                isAreaMeasurement ||
                                isSlabComposite
                            ? 340
                            : 260,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _titleRow(),
                      const SizedBox(height: 4),

                      // ===== GENERIC =====
                      if (!isSlabComposite &&
                          !isFootingComposite &&
                          !isBeamComposite &&
                          !isRoofSheetTimber &&
                          !isColumnComposite &&
                          !isFoundationWall &&
                          !isAreaMeasurement)
                        _summaryStatCard(
                          icon: Icons.straighten,
                          label: 'Total length',
                          value: totalValue.toStringAsFixed(3),
                          unit: unitDisplay,
                          color: AqsColors.primary,
                        ),

                      if (isAreaMeasurement) ...[
                        _summaryStatCard(
                          icon: Icons.crop_square_rounded,
                          label: 'Total area',
                          value: totalValue.toStringAsFixed(3),
                          unit: 'm²',
                          color: AqsColors.primary,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'All measurements',
                          style: TextStyle(
                            color: AqsColors.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 7),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 320),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: docs.length,
                            separatorBuilder:
                                (_, __) => const SizedBox(height: 6),
                            itemBuilder: (_, index) {
                              final data = docs[index].data();
                              return _areaMeasurementRow(
                                index: index + 1,
                                value: _num(data['value']),
                                label: (data['label'] ?? '').toString(),
                                boqCode: (data['boqCode'] ?? '').toString(),
                              );
                            },
                          ),
                        ),
                      ],

                      // ===== SLAB =====
                      if (isSlabComposite) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _saasMetricTile(
                              icon: Icons.crop_square_rounded,
                              label: 'Panel area',
                              value: totalSlabPanelAreaM2.toStringAsFixed(3),
                              unit: 'm²',
                            ),
                            if (slabConcreteTotalM3 > 0)
                              _saasMetricTile(
                                icon: Icons.view_in_ar_rounded,
                                label: 'Concrete',
                                value: slabConcreteTotalM3.toStringAsFixed(3),
                                unit: 'm³',
                              ),
                            if (slabConcreteTotalM2 > 0)
                              _saasMetricTile(
                                icon: Icons.crop_square_rounded,
                                label: 'Concrete',
                                value: slabConcreteTotalM2.toStringAsFixed(3),
                                unit: 'm²',
                              ),
                            if (slabSoffitFormworkTotalM2 > 0)
                              _saasMetricTile(
                                icon: Icons.grid_view_rounded,
                                label: 'Soffit formwork',
                                value: slabSoffitFormworkTotalM2
                                    .toStringAsFixed(3),
                                unit: 'm²',
                              ),
                            if (slabEdgeFormworkTotalM2 > 0)
                              _saasMetricTile(
                                icon: Icons.border_outer_rounded,
                                label: 'Edge formwork',
                                value: slabEdgeFormworkTotalM2.toStringAsFixed(
                                  3,
                                ),
                                unit: 'm²',
                              ),
                            if (slabEdgeFormworkTotalM > 0)
                              _saasMetricTile(
                                icon: Icons.border_outer_rounded,
                                label: 'Edge formwork',
                                value: slabEdgeFormworkTotalM.toStringAsFixed(
                                  3,
                                ),
                                unit: 'm',
                              ),
                            if (hasRebarTotals && totalRebarWeightKg > 0)
                              _saasMetricTile(
                                icon: Icons.density_medium_rounded,
                                label: 'Rebar weight',
                                value: totalRebarWeightKg.toStringAsFixed(2),
                                unit: 'kg',
                              ),
                            if (hasRebarTotals && totalRebarLengthM > 0)
                              _saasMetricTile(
                                icon: Icons.linear_scale_rounded,
                                label: 'Rebar length',
                                value: totalRebarLengthM.toStringAsFixed(3),
                                unit: 'm',
                              ),
                          ],
                        ),
                      ],

                      // ===== FOOTING =====
                      if (isFootingComposite) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (footingConcreteTotalM3 > 0)
                              _saasMetricTile(
                                icon: Icons.view_in_ar_rounded,
                                label: 'Concrete',
                                value: footingConcreteTotalM3.toStringAsFixed(
                                  3,
                                ),
                                unit: 'm³',
                              ),
                            if (footingFormworkTotalM2 > 0)
                              _saasMetricTile(
                                icon: Icons.view_week_outlined,
                                label: 'Side formwork',
                                value: footingFormworkTotalM2.toStringAsFixed(
                                  3,
                                ),
                                unit: 'm²',
                              ),
                            if (totalRebarWeightKg > 0)
                              _saasMetricTile(
                                icon: Icons.density_medium_rounded,
                                label: 'Rebar weight',
                                value: totalRebarWeightKg.toStringAsFixed(2),
                                unit: 'kg',
                              ),
                            if (footingExcavationTotalM3 > 0)
                              _saasMetricTile(
                                icon: Icons.landscape_outlined,
                                label: 'Excavation',
                                value: footingExcavationTotalM3.toStringAsFixed(
                                  3,
                                ),
                                unit: 'm³',
                              ),
                            if (footingBlindingTotalM2 > 0)
                              _saasMetricTile(
                                icon: Icons.layers_outlined,
                                label: 'Blinding',
                                value: footingBlindingTotalM2.toStringAsFixed(
                                  3,
                                ),
                                unit: 'm²',
                              ),
                            if (footingBackfillTotalM3 > 0)
                              _saasMetricTile(
                                icon: Icons.vertical_align_bottom_rounded,
                                label: 'Backfill',
                                value: footingBackfillTotalM3.toStringAsFixed(
                                  3,
                                ),
                                unit: 'm³',
                              ),
                            if (footingDisposalTotalM3 > 0)
                              _saasMetricTile(
                                icon: Icons.local_shipping_outlined,
                                label: 'Disposal',
                                value: footingDisposalTotalM3.toStringAsFixed(
                                  3,
                                ),
                                unit: 'm³',
                              ),
                          ],
                        ),
                      ],

                      // ===== BEAM =====
                      if (isBeamComposite) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (beamTotalLengthM > 0)
                              _saasMetricTile(
                                icon: Icons.straighten_rounded,
                                label: 'Total length',
                                value: beamTotalLengthM.toStringAsFixed(3),
                                unit: 'm',
                              ),
                            if (beamConcreteTotalM3 > 0)
                              _saasMetricTile(
                                icon: Icons.view_in_ar_rounded,
                                label: 'Concrete',
                                value: beamConcreteTotalM3.toStringAsFixed(3),
                                unit: 'm³',
                              ),
                            if (beamSideFormworkTotalM2 > 0)
                              _saasMetricTile(
                                icon: Icons.view_week_outlined,
                                label: 'Formwork sides',
                                value: beamSideFormworkTotalM2.toStringAsFixed(
                                  3,
                                ),
                                unit: 'm²',
                              ),
                            if (beamSoffitFormworkTotalM2 > 0)
                              _saasMetricTile(
                                icon: Icons.horizontal_rule_rounded,
                                label: 'Formwork soffit',
                                value: beamSoffitFormworkTotalM2
                                    .toStringAsFixed(3),
                                unit: 'm²',
                              ),
                            if (totalRebarWeightKg > 0)
                              _saasMetricTile(
                                icon: Icons.density_medium_rounded,
                                label: 'Rebar weight',
                                value: totalRebarWeightKg.toStringAsFixed(2),
                                unit: 'kg',
                              ),
                            if (totalRebarLengthM > 0)
                              _saasMetricTile(
                                icon: Icons.linear_scale_rounded,
                                label: 'Rebar length',
                                value: totalRebarLengthM.toStringAsFixed(3),
                                unit: 'm',
                              ),
                          ],
                        ),
                      ],

                      // ===== COLUMN ✅ NEW =====
                      if (isColumnComposite) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _saasMetricTile(
                              icon: Icons.view_in_ar_rounded,
                              label: 'Concrete',
                              value: columnConcreteTotalM3.toStringAsFixed(3),
                              unit: 'm³',
                            ),
                            _saasMetricTile(
                              icon: Icons.view_week_outlined,
                              label: 'Side formwork',
                              value: columnFormworkTotalM2.toStringAsFixed(3),
                              unit: 'm²',
                            ),
                            _saasMetricTile(
                              icon: Icons.vertical_align_center_rounded,
                              label: 'Main rebars',
                              value: columnMainRebarTotalKg.toStringAsFixed(2),
                              unit: 'kg',
                            ),
                            _saasMetricTile(
                              icon: Icons.all_inclusive_rounded,
                              label: 'Stirrups',
                              value: columnStirrupsTotalKg.toStringAsFixed(2),
                              unit: 'kg',
                            ),
                            _saasMetricTile(
                              icon: Icons.density_medium_rounded,
                              label: 'Total rebar',
                              value: totalRebarWeightKg.toStringAsFixed(2),
                              unit: 'kg',
                            ),
                            _saasMetricTile(
                              icon: Icons.linear_scale_rounded,
                              label: 'Rebar length',
                              value: (columnMainRebarLengthM +
                                      columnStirrupsLengthM)
                                  .toStringAsFixed(3),
                              unit: 'm',
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _countPill('Column groups', columnIds.length),
                            _countPill('Total columns', columnQtyTotal),
                            _quantityPill('Total height m', columnTotalHeightM),
                          ],
                        ),
                      ],

                      const SizedBox(height: 12),
                      if (isBeamComposite ||
                          isFootingComposite ||
                          isColumnComposite ||
                          isSlabComposite ||
                          isAreaMeasurement)
                        _saasMeasurementFooter(docs.length)
                      else
                        _countPill('Measurements', docs.length),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _measurementGroupId(dynamic doc) {
    final m = doc.data();
    for (final key in const [
      'assemblyId',
      'plinthGroupId',
      'pavementGroupId',
      'roadProfileGroupId',
      'groundPreparationGroupId',
      'segmentId',
      'areaSessionId',
      'areaGroupId',
      'beamId',
      'columnGroupId',
      'columnId',
      'footingGroupId',
      'slabId',
      'wallGroupId',
      'foundationGroupId',
      'finishGroupId',
      'ceilingGroupId',
      'tileGroupId',
      'roofGroupId',
      'countGroupId',
      'lengthGroupId',
      'groupId',
    ]) {
      final value = (m[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return doc.id;
  }

  String _toolName(String key) {
    switch (key) {
      case 'area':
        return 'Area';
      case 'compositebeam':
        return 'Beam composite';
      case 'compositecolumn':
        return 'Column composite';
      case 'compositefooting':
        return 'Footing composite';
      case 'compositeslab':
        return 'Slab composite';
      case 'plinth':
        return 'Plinth';
      case 'groundpreparation':
        return 'Ground preparation';
      case 'liftshaft':
        return 'Lift shaft';
      case 'length':
        return 'Length';
      case 'count':
        return 'Count';
      case 'walling':
        return 'Walling';
      default:
        if (key.isEmpty) return 'Other';
        return key[0].toUpperCase() + key.substring(1);
    }
  }

  IconData _toolIcon(String key) {
    if (key == 'liftshaft') return Icons.elevator_outlined;
    if (key == 'plinth') return Icons.layers_outlined;
    if (key == 'groundpreparation') return Icons.landscape_outlined;
    if (key == 'area') return Icons.crop_square_rounded;
    if (key.contains('beam')) return Icons.horizontal_rule_rounded;
    if (key.contains('column')) return Icons.view_column_rounded;
    if (key.contains('footing')) return Icons.foundation_rounded;
    if (key.contains('slab')) return Icons.grid_on_rounded;
    if (key == 'count') return Icons.fact_check_outlined;
    if (key == 'length') return Icons.straighten_rounded;
    return Icons.architecture_rounded;
  }

  Widget _drawingTakeoffRegister(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String Function(dynamic) canonical,
  ) {
    final byTool =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in docs) {
      final key = canonical(
        doc.data()['measureType'] ?? doc.data()['typeGroup'],
      );
      byTool.putIfAbsent(key.isEmpty ? 'other' : key, () => []).add(doc);
    }
    final keys =
        byTool.keys.toList()
          ..sort((a, b) => _toolName(a).compareTo(_toolName(b)));

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summaryHero(
            title: 'Drawing take-off register',
            subtitle:
                docs.isEmpty
                    ? 'No measurements saved on this drawing.'
                    : '${keys.length} tool${keys.length == 1 ? '' : 's'} used on this drawing',
            icon: Icons.inventory_2_outlined,
          ),
          if (keys.isNotEmpty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 430),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: keys.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final key = keys[index];
                  final toolDocs = byTool[key]!;
                  final groups = toolDocs.map(_measurementGroupId).toSet();
                  return Material(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap:
                          () => _showToolMeasurements(
                            context,
                            key,
                            canonical,
                            initialDocs: toolDocs,
                          ),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AqsColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AqsColors.primarySoft,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(
                                _toolIcon(key),
                                color: AqsColors.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _toolName(key),
                                    style: const TextStyle(
                                      color: AqsColors.text,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${groups.length} measurement${groups.length == 1 ? '' : 's'} · ${toolDocs.length} saved item${toolDocs.length == 1 ? '' : 's'}',
                                    style: const TextStyle(
                                      color: AqsColors.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AqsColors.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showToolMeasurements(
    BuildContext context,
    String toolKey,
    String Function(dynamic) canonical, {
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> initialDocs,
  }) async {
    final ids = _measurementContextIds();
    if (ids == null) return;
    final controller =
        Get.isRegistered<ProjectBuildingsController>()
            ? Get.find<ProjectBuildingsController>()
            : Get.put(ProjectBuildingsController(), permanent: true);
    final cacheKey = controller.buildingKey(ids.projectId, ids.buildingId);
    final cachedRows = controller.measurementsFor(
      ids.projectId,
      ids.buildingId,
    );
    controller.measurementsByBuilding[cacheKey] = [
      for (final row in cachedRows)
        if ((row['drawingId'] ?? '').toString() != drawingId ||
            canonical(row['measureType'] ?? row['typeGroup']) != toolKey)
          row,
      for (final doc in initialDocs) {'id': doc.id, ...doc.data()},
    ];
    unawaited(
      controller.loadMeasurements(
        ids.projectId,
        ids.buildingId,
        forceRefresh: true,
      ),
    );
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => Dialog(
            insetPadding: const EdgeInsets.all(24),
            backgroundColor: const Color(0xFFF6F8FC),
            elevation: 24,
            shadowColor: AqsColors.primary.withValues(alpha: 0.22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920, maxHeight: 820),
              child: Obx(() {
                final cacheIsLoading = controller.loadingMeasurements.contains(
                  cacheKey,
                );
                final loadError = controller.measurementErrors[cacheKey];
                final cachedToolDocs =
                    controller
                        .measurementsFor(ids.projectId, ids.buildingId)
                        .where(
                          (row) =>
                              (row['drawingId'] ?? '').toString() ==
                                  drawingId &&
                              canonical(
                                    row['measureType'] ?? row['typeGroup'],
                                  ) ==
                                  toolKey,
                        )
                        .map(
                          (row) => _SavedMeasurementRecord(
                            id: (row['id'] ?? '').toString(),
                            dataMap: row,
                            reference: measurementsRef.doc(
                              (row['id'] ?? '').toString(),
                            ),
                          ),
                        )
                        .where((record) => record.id.isNotEmpty)
                        .toList();
                final toolDocs = cachedToolDocs;
                final isLoading = cacheIsLoading && toolDocs.isEmpty;
                final buildingRows = controller.measurementsFor(
                  ids.projectId,
                  ids.buildingId,
                );
                final buildingFactors =
                    buildingRows.map((row) {
                      final raw = row['takeoffBuildingFactor'];
                      final parsed =
                          raw is num ? raw.toDouble() : double.tryParse('$raw');
                      return parsed != null && parsed > 0 ? parsed : 1.0;
                    }).toList();
                final currentBuildingFactor =
                    buildingFactors.isEmpty ? 1.0 : buildingFactors.first;
                final hasMixedBuildingFactors = buildingFactors.any(
                  (factor) => (factor - currentBuildingFactor).abs() > 0.000001,
                );
                final buildingFactorLabel =
                    hasMixedBuildingFactors
                        ? 'Building ×Mixed'
                        : 'Building ×${currentBuildingFactor == currentBuildingFactor.roundToDouble() ? currentBuildingFactor.toStringAsFixed(0) : currentBuildingFactor.toStringAsFixed(2)}';
                final grouped = <String, List<_SavedMeasurementRecord>>{};
                for (final doc in toolDocs) {
                  grouped
                      .putIfAbsent(_measurementGroupId(doc), () => [])
                      .add(doc);
                }
                final groups = grouped.entries.toList();
                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AqsColors.primaryDark, AqsColors.primary],
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.24),
                              ),
                            ),
                            child: Icon(
                              _toolIcon(toolKey),
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_toolName(toolKey)} measurements',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  isLoading
                                      ? 'Loading saved take-off records…'
                                      : '${groups.length} measurement${groups.length == 1 ? '' : 's'} · ${toolDocs.length} saved item${toolDocs.length == 1 ? '' : 's'}',
                                  style: const TextStyle(
                                    color: Color(0xFFD6E4FF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!isLoading && buildingRows.isNotEmpty)
                            Tooltip(
                              message:
                                  'Apply one quantity factor to every measurement in this building',
                              child: TextButton.icon(
                                onPressed:
                                    cacheIsLoading
                                        ? null
                                        : () => _changeBuildingTakeoffFactor(
                                          dialogContext,
                                          ids,
                                          currentBuildingFactor,
                                          buildingRows,
                                        ),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  disabledForegroundColor: Colors.white54,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 9,
                                  ),
                                ),
                                icon: const Icon(Icons.apartment_rounded),
                                label: Text(
                                  MediaQuery.sizeOf(dialogContext).width < 760
                                      ? '×${hasMixedBuildingFactors
                                          ? '—'
                                          : currentBuildingFactor == currentBuildingFactor.roundToDouble()
                                          ? currentBuildingFactor.toStringAsFixed(0)
                                          : currentBuildingFactor.toStringAsFixed(2)}'
                                      : buildingFactorLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          if (!isLoading && toolDocs.isNotEmpty)
                            Tooltip(
                              message:
                                  'Delete all ${_toolName(toolKey)} measurements',
                              child: TextButton.icon(
                                onPressed:
                                    cacheIsLoading
                                        ? null
                                        : () => _deleteAllToolMeasurements(
                                          dialogContext,
                                          toolKey,
                                          groups.length,
                                          toolDocs,
                                        ),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  disabledForegroundColor: Colors.white54,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 9,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.delete_sweep_outlined,
                                  size: 21,
                                ),
                                label: Text(
                                  MediaQuery.sizeOf(dialogContext).width < 700
                                      ? ''
                                      : 'Delete all',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          IconButton(
                            onPressed:
                                cacheIsLoading
                                    ? null
                                    : () => controller.loadMeasurements(
                                      ids.projectId,
                                      ids.buildingId,
                                      forceRefresh: true,
                                    ),
                            color: Colors.white,
                            disabledColor: Colors.white54,
                            tooltip: 'Refresh measurements',
                            icon:
                                cacheIsLoading
                                    ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                    : const Icon(Icons.refresh_rounded),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            color: Colors.white,
                            tooltip: 'Close',
                            icon: const Icon(Icons.close_rounded, size: 28),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child:
                          isLoading
                              ? const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 42,
                                      height: 42,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                      ),
                                    ),
                                    SizedBox(height: 14),
                                    Text(
                                      'Loading measurements…',
                                      style: TextStyle(
                                        color: AqsColors.muted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              : loadError != null
                              ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    'Could not load measurements.\n$loadError',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFFD92D20),
                                    ),
                                  ),
                                ),
                              )
                              : groups.isEmpty
                              ? const Center(
                                child: Text('No saved measurements.'),
                              )
                              : ListView.separated(
                                padding: const EdgeInsets.all(20),
                                itemCount: groups.length,
                                separatorBuilder:
                                    (_, __) => const SizedBox(height: 14),
                                itemBuilder:
                                    (_, index) => _measurementGroupCard(
                                      context,
                                      groups[index],
                                      index + 1,
                                    ),
                              ),
                    ),
                  ],
                );
              }),
            ),
          ),
    );
  }

  String _savedItemLabel(Map<String, dynamic> m) {
    final type = (m['type'] ?? '').toString().trim().toLowerCase();
    switch (type) {
      case 'ceilinggypsumplasterboard':
        return 'Gypsum plasterboards';
      case 'ceilingcornice':
        return 'Cornice';
      case 'ceilingaccesspanels':
        return 'Ceiling access panels';
      case 'ceilingbranderings50x50':
        return 'Branderings 50 × 50 mm';
      case 'ceilingdecorationpaint':
        return 'Ceiling decoration / paint';
      case 'floorterrazzo':
        return 'Terrazzo floor finish';
      case 'floorsandscreed':
        return 'Sand and cement screed';
      case 'floorgranolithicscreed':
        return 'Granolithic screed';
      case 'floortiles':
        return 'Floor tiles';
      case 'walltiles':
        return 'Wall tiles';
      case 'tilebackingbed':
        return 'Backing bed / screed bed';
      case 'tileskirting':
        return 'Skirting, 100 mm high';
      case 'terrazzoskirting100mm':
        return 'Terrazzo skirting, 100 mm high';
      case 'terrazzotreads300mmroundednosing':
        return 'Terrazzo treads, 300 mm wide; one rounded nosing';
      case 'plinthplastering':
        return 'Plinth plastering';
      case 'plinthbitumenpainting':
        return 'Bitumen painting';
      case 'plinthconcretebedarea':
        return 'Concrete bed area';
      case 'plinthconcretebedvolume':
        return 'Concrete bed volume';
      case 'plinthconcretebededge':
        return 'Concrete-bed edge';
      case 'plinthfabricmesh':
        return 'Fabric mesh';
      case 'liftshaftexcavationband':
        final band = m['excavationBandIndex'];
        return band == null ? 'Excavation' : 'Excavation band $band';
      case 'liftshaftbackfillreuse':
        return 'Reused excavated backfill';
      case 'liftshaftbackfillimported':
        return 'Imported backfill';
      case 'liftshaftdisposaloffsite':
        return 'Surplus disposal off site';
      case 'liftshafthardcore':
        return 'Hardcore filling';
      case 'liftshaftblinding':
        return 'Concrete blinding';
      case 'liftshaftbaseconcrete':
        return 'Lift-shaft base concrete';
      case 'liftshaftwallconcretesubstructure':
        return 'Lift-shaft wall concrete — substructure';
      case 'liftshaftwallconcretesuperstructure':
        return 'Lift-shaft wall concrete — superstructure';
      case 'liftshaftwallformworksubstructure':
        return 'Lift-shaft wall formwork — substructure';
      case 'liftshaftwallformworksuperstructure':
        return 'Lift-shaft wall formwork — superstructure';
      case 'liftshaftwallrebarsubstructure':
        return 'Lift-shaft wall rebar — substructure';
      case 'liftshaftwallrebarsuperstructure':
        return 'Lift-shaft wall rebar — superstructure';
      case 'liftshaftbaserebar':
        return 'Lift-shaft base rebar';
      default:
        return (m['label'] ?? m['type'] ?? 'Item').toString();
    }
  }

  Widget _measurementGroupCard(
    BuildContext context,
    MapEntry<String, List<_SavedMeasurementRecord>> group,
    int index,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AqsColors.border),
        boxShadow: [
          BoxShadow(
            color: AqsColors.primary.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Measurement $index',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${group.value.length} saved item${group.value.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AqsColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => _deleteMeasurementGroup(context, group.value),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text(
                  'Remove',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AqsColors.primarySoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    'Saved item',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                  ),
                ),
                SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: Text(
                    'BOQ code',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                  ),
                ),
                SizedBox(width: 24),
                Expanded(
                  flex: 4,
                  child: Text(
                    'BOQ description',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                  ),
                ),
                SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Quantity',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                  ),
                ),
                SizedBox(width: 76),
              ],
            ),
          ),
          const SizedBox(height: 4),
          ...group.value.map((doc) {
            final m = doc.data();
            final unit = _prettyUnit((m['unit'] ?? '').toString());
            final value =
                (m['value'] is num)
                    ? (m['value'] as num).toDouble()
                    : double.tryParse('${m['value']}') ?? 0;
            final label = _savedItemLabel(m);
            final currentBoq = _currentBoqRowFor(m);
            final boq =
                currentBoq == null
                    ? (m['boqCode'] ?? '').toString().trim()
                    : _hierarchicalCodeForCurrentBoq(currentBoq);
            final currentDescription =
                (currentBoq?['description'] ?? '').toString().trim();
            final boqDescription =
                currentDescription.isNotEmpty
                    ? currentDescription
                    : _boqDescriptionFor(m, boq);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AqsColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 2,
                    child: Text(
                      boq.isEmpty ? 'Not linked' : boq,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: boq.isEmpty ? AqsColors.muted : AqsColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 4,
                    child: Text(
                      boqDescription.isEmpty ? '—' : boqDescription,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            boqDescription.isEmpty
                                ? AqsColors.muted
                                : AqsColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${value.toStringAsFixed(3)} $unit',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 68,
                    child: OutlinedButton(
                      onPressed: () => _editMeasurementItem(context, doc),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text(
                        'Update',
                        style: TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _boqDescriptionFor(Map<String, dynamic> measurement, String boqCode) {
    final savedDescription =
        (measurement['boqDescription'] ?? '').toString().trim();
    if (savedDescription.isNotEmpty) return savedDescription;
    if (boqCode.isEmpty || !Get.isRegistered<ProjectBuildingsController>()) {
      return '';
    }

    final pathParts = measurementsRef.path.split('/');
    final projectIndex = pathParts.indexOf('projects');
    final buildingIndex = pathParts.indexOf('buildings');
    if (projectIndex < 0 ||
        projectIndex + 1 >= pathParts.length ||
        buildingIndex < 0 ||
        buildingIndex + 1 >= pathParts.length) {
      return '';
    }

    final projectId = pathParts[projectIndex + 1];
    final buildingId = pathParts[buildingIndex + 1];
    final normalizedCode = boqCode.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final rows = Get.find<ProjectBuildingsController>().boqFor(
      projectId,
      buildingId,
    );
    for (final row in rows) {
      final candidates = {
        (row['boqCode'] ?? '').toString(),
        (row['resolvedBoqCode'] ?? '').toString(),
        (row['displayCode'] ?? '').toString(),
        hierarchicalBoqCodeFromRows(row, rows),
      }.map((code) => code.replaceAll(RegExp(r'\s+'), '').toLowerCase());
      if (candidates.contains(normalizedCode)) {
        return (row['description'] ?? '').toString().trim();
      }
    }
    return '';
  }

  Map<String, dynamic>? _currentBoqRowFor(Map<String, dynamic> measurement) {
    final boqItemId = (measurement['boqItemId'] ?? '').toString().trim();
    if (boqItemId.isEmpty || !Get.isRegistered<ProjectBuildingsController>()) {
      return null;
    }

    final contextIds = _measurementContextIds();
    if (contextIds == null) return null;
    final rows = Get.find<ProjectBuildingsController>().boqFor(
      contextIds.projectId,
      contextIds.buildingId,
    );
    for (final row in rows) {
      final rowId = (row['id'] ?? row['__id'] ?? '').toString().trim();
      if (rowId == boqItemId) return row;
    }
    return null;
  }

  String _hierarchicalCodeForCurrentBoq(Map<String, dynamic> row) {
    final contextIds = _measurementContextIds();
    if (contextIds == null || !Get.isRegistered<ProjectBuildingsController>()) {
      return hierarchicalBoqCode(row);
    }
    final rows = Get.find<ProjectBuildingsController>().boqFor(
      contextIds.projectId,
      contextIds.buildingId,
    );
    return hierarchicalBoqCodeFromRows(row, rows);
  }

  _MeasurementContextIds? _measurementContextIds() {
    final pathParts = measurementsRef.path.split('/');
    final projectIndex = pathParts.indexOf('projects');
    final buildingIndex = pathParts.indexOf('buildings');
    if (projectIndex < 0 ||
        projectIndex + 1 >= pathParts.length ||
        buildingIndex < 0 ||
        buildingIndex + 1 >= pathParts.length) {
      return null;
    }
    return _MeasurementContextIds(
      projectId: pathParts[projectIndex + 1],
      buildingId: pathParts[buildingIndex + 1],
    );
  }

  Future<void> _refreshSharedMeasurements() async {
    final ids = _measurementContextIds();
    if (ids == null || !Get.isRegistered<ProjectBuildingsController>()) {
      return;
    }
    await Get.find<ProjectBuildingsController>().loadMeasurements(
      ids.projectId,
      ids.buildingId,
      forceRefresh: true,
    );
  }

  Future<void> _refreshEditedMeasurement(
    _SavedMeasurementRecord measurement,
  ) async {
    final ids = _measurementContextIds();
    if (ids == null || !Get.isRegistered<ProjectBuildingsController>()) {
      return;
    }

    final snapshot = await measurement.reference.get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return;

    final controller = Get.find<ProjectBuildingsController>();
    final cacheKey = controller.buildingKey(ids.projectId, ids.buildingId);
    final rows = controller.measurementsFor(ids.projectId, ids.buildingId);
    controller.measurementsByBuilding[cacheKey] = [
      for (final row in rows)
        if ((row['id'] ?? '').toString() == measurement.id)
          {'id': measurement.id, ...data}
        else
          row,
    ];
  }

  Future<void> _deleteMeasurementGroup(
    BuildContext context,
    List<_SavedMeasurementRecord> docs,
  ) async {
    var docsToDelete = docs;
    final finishGroupId =
        docs.isEmpty
            ? ''
            : (docs.first.data()['finishGroupId'] ?? '').toString().trim();
    if (finishGroupId.isNotEmpty) {
      final groupedSnapshot =
          await measurementsRef
              .where('drawingId', isEqualTo: drawingId)
              .where('finishGroupId', isEqualTo: finishGroupId)
              .get();
      docsToDelete =
          groupedSnapshot.docs
              .map(
                (doc) => _SavedMeasurementRecord(
                  id: doc.id,
                  dataMap: doc.data(),
                  reference: doc.reference,
                ),
              )
              .toList();
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                title: const Text('Remove measurement?'),
                content: Text(
                  'This will remove ${docsToDelete.length} saved item${docsToDelete.length == 1 ? '' : 's'} and update the BOQ summary.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Remove'),
                  ),
                ],
              ),
        ) ??
        false;
    if (!confirmed) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in docsToDelete) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    await _refreshSharedMeasurements();
  }

  Future<void> _deleteAllToolMeasurements(
    BuildContext context,
    String toolKey,
    int measurementCount,
    List<_SavedMeasurementRecord> docs,
  ) async {
    if (docs.isEmpty) return;
    final toolName = _toolName(toolKey);
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder:
              (confirmationContext) => AlertDialog(
                icon: const Icon(
                  Icons.delete_sweep_outlined,
                  color: Color(0xFFD92D20),
                  size: 34,
                ),
                title: Text('Delete all $toolName measurements?'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This will permanently delete $measurementCount measurement${measurementCount == 1 ? '' : 's'} containing ${docs.length} saved item${docs.length == 1 ? '' : 's'} from this drawing.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Their quantities will also be removed from the BOQ totals. This action cannot be undone.',
                      style: TextStyle(
                        color: Color(0xFFD92D20),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(confirmationContext, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(confirmationContext, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD92D20),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Delete all'),
                  ),
                ],
              ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder:
            (_) => const PopScope(
              canPop: false,
              child: AlertDialog(
                content: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        'Deleting all measurements…',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;

    try {
      const maxDeletesPerBatch = 450;
      for (var start = 0; start < docs.length; start += maxDeletesPerBatch) {
        final end = math.min(start + maxDeletesPerBatch, docs.length);
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in docs.sublist(start, end)) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      await _refreshSharedMeasurements();
      if (context.mounted && rootNavigator.canPop()) rootNavigator.pop();
      Get.snackbar(
        'Measurements deleted',
        'All $toolName measurements were removed from this drawing.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (error) {
      if (context.mounted && rootNavigator.canPop()) rootNavigator.pop();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder:
            (errorContext) => AlertDialog(
              icon: const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFD92D20),
              ),
              title: const Text('Could not delete all measurements'),
              content: Text(
                'Some measurements may already have been removed. Refresh the register and try again.\n\n$error',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(errorContext),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
      await _refreshSharedMeasurements();
    }
  }

  Future<void> _changeBuildingTakeoffFactor(
    BuildContext context,
    _MeasurementContextIds ids,
    double currentFactor,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final factorController = TextEditingController(
      text:
          currentFactor == currentFactor.roundToDouble()
              ? currentFactor.toStringAsFixed(0)
              : currentFactor.toStringAsFixed(2),
    );
    String? validationMessage;
    final factor = await showDialog<double>(
      context: context,
      builder:
          (factorContext) => StatefulBuilder(
            builder: (factorContext, setFactorState) {
              final parsed = double.tryParse(factorController.text.trim());
              final valid = parsed != null && parsed > 0 && parsed <= 999999;
              return AlertDialog(
                icon: const Icon(
                  Icons.apartment_rounded,
                  color: AqsColors.primary,
                  size: 34,
                ),
                title: const Text('Building quantity factor'),
                content: SizedBox(
                  width: 430,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Use one factor for identical buildings that share this BOQ and drawing set.',
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: factorController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Factor (×)',
                          hintText: '1',
                          prefixIcon: const Icon(Icons.close_rounded),
                          border: const OutlineInputBorder(),
                          errorText: validationMessage,
                          helperText:
                              '×1 keeps the original take-off; ×2 doubles every quantity.',
                        ),
                        onChanged:
                            (_) =>
                                setFactorState(() => validationMessage = null),
                        onSubmitted: (_) {
                          if (valid) Navigator.pop(factorContext, parsed);
                        },
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AqsColors.primarySoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${rows.length} saved item${rows.length == 1 ? '' : 's'} across this building will be recalculated from their original unscaled quantities.',
                          style: const TextStyle(
                            color: AqsColors.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(factorContext),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      if (!valid) {
                        setFactorState(
                          () =>
                              validationMessage =
                                  'Enter a factor greater than 0.',
                        );
                        return;
                      }
                      Navigator.pop(factorContext, parsed);
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Apply factor'),
                  ),
                ],
              );
            },
          ),
    );
    factorController.dispose();
    if (factor == null || !context.mounted) return;

    final validRows =
        rows.where((row) {
          final id = (row['id'] ?? '').toString().trim();
          final rawValue = row['value'];
          return id.isNotEmpty &&
              (rawValue is num || double.tryParse('$rawValue') != null);
        }).toList();
    if (validRows.isEmpty) {
      Get.snackbar(
        'No quantities found',
        'There are no saved numeric quantities to update.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder:
            (_) => PopScope(
              canPop: false,
              child: AlertDialog(
                content: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        'Applying building factor ×${factor == factor.roundToDouble() ? factor.toStringAsFixed(0) : factor.toStringAsFixed(2)}…',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;

    try {
      const maxWritesPerBatch = 450;
      for (
        var start = 0;
        start < validRows.length;
        start += maxWritesPerBatch
      ) {
        final end = math.min(start + maxWritesPerBatch, validRows.length);
        final batch = FirebaseFirestore.instance.batch();
        for (final row in validRows.sublist(start, end)) {
          final id = (row['id'] ?? '').toString().trim();
          final rawValue = row['value'];
          final currentValue =
              rawValue is num ? rawValue.toDouble() : double.parse('$rawValue');
          final savedBase = row['valueBeforeBuildingFactor'];
          final previousFactorRaw = row['takeoffBuildingFactor'];
          final previousFactor =
              previousFactorRaw is num
                  ? previousFactorRaw.toDouble()
                  : double.tryParse('$previousFactorRaw') ?? 1.0;
          final baseValue =
              savedBase is num
                  ? savedBase.toDouble()
                  : double.tryParse('$savedBase') ??
                      (previousFactor > 0
                          ? currentValue / previousFactor
                          : currentValue);
          batch.update(measurementsRef.doc(id), {
            'valueBeforeBuildingFactor': baseValue,
            'takeoffBuildingFactor': factor,
            'value': baseValue * factor,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
      await Get.find<ProjectBuildingsController>().loadMeasurements(
        ids.projectId,
        ids.buildingId,
        forceRefresh: true,
      );
      if (context.mounted && rootNavigator.canPop()) rootNavigator.pop();
      Get.snackbar(
        'Building factor updated',
        'All saved take-off quantities now use factor ×${factor == factor.roundToDouble() ? factor.toStringAsFixed(0) : factor.toStringAsFixed(2)}.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (error) {
      if (context.mounted && rootNavigator.canPop()) rootNavigator.pop();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder:
            (errorContext) => AlertDialog(
              icon: const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFD92D20),
              ),
              title: const Text('Could not update every quantity'),
              content: Text(
                'Some batches may already use the new factor. Refresh the measurements and apply the same factor again to finish safely.\n\n$error',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(errorContext),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
      await _refreshSharedMeasurements();
    }
  }

  Future<void> _editMeasurementItem(
    BuildContext context,
    _SavedMeasurementRecord doc,
  ) async {
    final m = doc.data();
    double savedNumber(dynamic value) =>
        value is num ? value.toDouble() : double.tryParse('$value') ?? 0.0;
    final valueCtrl = TextEditingController(text: '${m['value'] ?? 0}');
    final boqCtrl = TextEditingController(
      text: (m['boqCode'] ?? '').toString(),
    );
    final type = (m['type'] ?? '').toString();
    final typeKey = type.trim().toLowerCase();
    final isRoadProfile =
        typeKey == 'roadprofile' ||
        (m['measureType'] ?? '').toString().trim().toLowerCase() ==
            'roadprofile' ||
        (m['roadProfileGroupId'] ?? '').toString().trim().isNotEmpty;
    final roadOutputKey =
        (m['roadProfileOutputKey'] ?? '').toString().trim().toLowerCase();
    final roadLengthM = savedNumber(m['lengthM']);
    final roadUsesClearingWidth = roadOutputKey == 'clearing';
    final roadUsesEarthworkWidth = const {
      'topsoil',
      'common_excavation',
      'fill',
    }.contains(roadOutputKey);
    final roadWidthField =
        roadUsesClearingWidth
            ? 'roadClearingWidthM'
            : roadUsesEarthworkWidth
            ? 'roadEarthworkWidthM'
            : 'roadPavementWidthM';
    final roadWidthCtrl = TextEditingController(
      text: '${m[roadWidthField] ?? 0}',
    );
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
    final roadThicknessField = roadThicknessFields[roadOutputKey];
    final roadThicknessCtrl = TextEditingController(
      text: '${roadThicknessField == null ? 0 : m[roadThicknessField] ?? 0}',
    );
    final roadIsMc30 =
        roadOutputKey == 'mc30_prime_coat' ||
        roadOutputKey == 'mc30_curing_membrane';
    final roadRateField =
        roadOutputKey == 'mc30_curing_membrane'
            ? 'mc30CuringMembraneRateLPerM2'
            : 'mc30PrimeCoatRateLPerM2';
    final roadRateCtrl = TextEditingController(
      text: '${m[roadRateField] ?? 0}',
    );
    final isSlabRebar = typeKey == 'rebarslab';
    final isBeamMainRebar = typeKey == 'rebarbeammaingroup';
    final isBeamStirrups = typeKey == 'rebarbeamstirrupszone';
    final isColumnMainRebar = typeKey == 'columnmainrebar';
    final isColumnStirrups = typeKey == 'columnstirrups';
    final isFootingRebar = typeKey == 'footingrebarauto';
    final isStairMainRebar = typeKey == 'rebarstairmain';
    final isStairDistributionRebar = typeKey == 'rebarstairdistribution';
    final isRecognizedRebar =
        typeKey.contains('rebar') ||
        typeKey.contains('mainbar') ||
        typeKey.contains('stirrup');
    final isAnyRebar =
        isSlabRebar ||
        isBeamMainRebar ||
        isBeamStirrups ||
        isColumnMainRebar ||
        isColumnStirrups ||
        isFootingRebar ||
        isStairMainRebar ||
        isStairDistributionRebar ||
        isRecognizedRebar;
    final hasEditableBarArrangement =
        isSlabRebar ||
        isBeamMainRebar ||
        isBeamStirrups ||
        isColumnMainRebar ||
        isColumnStirrups ||
        isFootingRebar ||
        isStairMainRebar ||
        isStairDistributionRebar;
    final diameterCtrl = TextEditingController(
      text:
          '${m['diameterMm'] ?? m['mainDiaMm'] ?? m['stirDiaMm'] ?? m['stirrupDiaMm'] ?? m['diaMm'] ?? m['distDiaMm'] ?? 12}',
    );
    final storedSpacingM = savedNumber(
      m['spacingM'] ?? m['spacingAcrossWidthM'],
    );
    final spacingCtrl = TextEditingController(
      text:
          '${m['spacingMm'] ?? m['mainSpacingMm'] ?? m['distSpacingMm'] ?? (storedSpacingM > 0 ? storedSpacingM * 1000 : 150)}',
    );
    final secondarySpacingCtrl = TextEditingController(
      text:
          '${savedNumber(m['spacingAcrossLengthM']) > 0 ? savedNumber(m['spacingAcrossLengthM']) * 1000 : double.tryParse(spacingCtrl.text) ?? 150}',
    );
    final barsCtrl = TextEditingController(
      text: '${m['barsInGroup'] ?? m['barsPerColumn'] ?? 1}',
    );
    final embedCtrl = TextEditingController(
      text:
          '${m['embedEachEndM'] ?? m['embedTopM'] ?? m['coverM'] ?? m['mainEmbedEachEndM'] ?? m['distEmbedEachEndM'] ?? 0}',
    );
    final secondEmbedCtrl = TextEditingController(
      text: '${m['embedBotM'] ?? m['embedEachEndM'] ?? 0}',
    );
    final extraCtrl = TextEditingController(
      text:
          '${m['lapExtraM'] ?? m['extraM'] ?? m['hookExtraM'] ?? m['mainEmbedEachEndM'] ?? m['distEmbedEachEndM'] ?? 0}',
    );
    final memberLengthCtrl = TextEditingController(
      text:
          '${m['zoneLengthM'] ?? m['beamLengthM'] ?? m['heightM'] ?? m['lengthM'] ?? 0}',
    );
    final slabLengthCtrl = TextEditingController(text: '${m['lengthM'] ?? 0}');
    final slabWidthCtrl = TextEditingController(text: '${m['widthM'] ?? 0}');
    var rebarDirection = (m['direction'] ?? 'alongL').toString();
    var rebarPosition = (m['position'] ?? 'bottom').toString();

    double? calculateRoadProfile() {
      if (!isRoadProfile || roadLengthM <= 0) return null;
      final width = double.tryParse(roadWidthCtrl.text.trim());
      if (width == null || width <= 0) return null;
      if (roadUsesClearingWidth) return roadLengthM * width / 10000.0;
      if (roadIsMc30) {
        final rate = double.tryParse(roadRateCtrl.text.trim());
        if (rate == null || rate < 0) return null;
        return roadLengthM * width * rate;
      }
      final thickness = double.tryParse(roadThicknessCtrl.text.trim());
      if (roadThicknessField == null || thickness == null || thickness < 0) {
        return null;
      }
      final volume = roadLengthM * width * thickness / 1000.0;
      if (roadOutputKey == 'bitumen_binder') {
        return volume *
            savedNumber(m['asphaltDensityTPerM3']) *
            savedNumber(m['bitumenContentPercent']) /
            100.0;
      }
      if (roadOutputKey == 'cement_stabiliser') {
        return volume *
            savedNumber(m['stabilisedDryDensityTPerM3']) *
            savedNumber(m['cementContentPercent']) /
            100.0;
      }
      return volume;
    }

    void refreshRoadProfilePreview() {
      final quantity = calculateRoadProfile();
      if (quantity != null) valueCtrl.text = quantity.toStringAsFixed(3);
    }

    Map<String, dynamic>? calculateRebar() {
      final diameter = int.tryParse(diameterCtrl.text.trim());
      final spacing = double.tryParse(spacingCtrl.text.trim());
      if (diameter == null || diameter <= 0) return null;
      if ((isSlabRebar ||
              isBeamStirrups ||
              isColumnStirrups ||
              isFootingRebar ||
              isStairMainRebar ||
              isStairDistributionRebar) &&
          (spacing == null || spacing <= 0)) {
        return null;
      }
      final uw = diameter * diameter / 162.0;
      final totalQty = savedNumber(
        m['totalQty'] ?? m['qtyTotal'],
      ).clamp(1, double.infinity);

      if (isBeamMainRebar) {
        final bars = int.tryParse(barsCtrl.text.trim());
        final lengthM = double.tryParse(memberLengthCtrl.text.trim()) ?? 0;
        final embed = double.tryParse(embedCtrl.text.trim());
        final extra = double.tryParse(extraCtrl.text.trim());
        if (bars == null ||
            bars <= 0 ||
            lengthM <= 0 ||
            embed == null ||
            extra == null) {
          return null;
        }
        final barLength = lengthM + 2 * embed + extra;
        final totalLength = bars * barLength * totalQty;
        return {
          'value': totalLength * uw,
          'mainDiaMm': diameter,
          'barsInGroup': bars,
          'embedEachEndM': embed,
          'lapExtraM': extra,
          'barLenOneM': barLength,
          'totalLenM': totalLength,
          'unitWeightKgPerM': uw,
        };
      }

      if (isColumnMainRebar) {
        final bars = int.tryParse(barsCtrl.text.trim());
        final height = double.tryParse(memberLengthCtrl.text.trim()) ?? 0;
        final embedTop = double.tryParse(embedCtrl.text.trim());
        final embedBottom = double.tryParse(secondEmbedCtrl.text.trim());
        final extra = double.tryParse(extraCtrl.text.trim());
        if (bars == null ||
            bars <= 0 ||
            height <= 0 ||
            embedTop == null ||
            embedBottom == null ||
            extra == null) {
          return null;
        }
        final barLength = height + embedTop + embedBottom + extra;
        final weightOne = bars * barLength * uw;
        return {
          'value': weightOne * totalQty,
          'valuePerColumn': weightOne,
          'valuePerBuilding':
              weightOne *
              savedNumber(m['qtyPerBuilding']).clamp(1, double.infinity),
          'diameterMm': diameter,
          'barsPerColumn': bars,
          'barLengthM': barLength,
          'totalLengthPerColumnM': bars * barLength,
          'embedTopM': embedTop,
          'embedBotM': embedBottom,
          'extraM': extra,
          'rawMark': '${bars}Y$diameter',
        };
      }

      if (isBeamStirrups || isColumnStirrups) {
        final spacingM = spacing! / 1000;
        final cover = double.tryParse(embedCtrl.text.trim());
        final hook = double.tryParse(extraCtrl.text.trim());
        final length = double.tryParse(memberLengthCtrl.text.trim()) ?? 0;
        final sectionL = savedNumber(
          isBeamStirrups
              ? m['beamWidthM']
              : (m['planLengthUsedM'] ?? m['lengthM']),
        );
        final sectionW = savedNumber(
          isBeamStirrups
              ? m['beamDepthM']
              : (m['planWidthUsedM'] ?? m['widthM']),
        );
        if (cover == null ||
            hook == null ||
            length <= 0 ||
            sectionL <= 0 ||
            sectionW <= 0) {
          return null;
        }
        final oneLength =
            2 *
                ((sectionL - 2 * cover).clamp(0, double.infinity) +
                    (sectionW - 2 * cover).clamp(0, double.infinity)) +
            hook;
        final count = (length / spacingM).ceil() + 1;
        final weightOne = oneLength * count * uw;
        return {
          'value': weightOne * totalQty,
          if (isBeamStirrups) ...{
            'stirDiaMm': diameter,
            'stirCountPerBeam': count,
            'stirLenOneM': oneLength,
            'totalLenM': oneLength * count * totalQty,
          } else ...{
            'stirrupDiaMm': diameter,
            'stirrupCountPerColumn': count,
            'stirrupLenOneM': oneLength,
            'stirrupTotalLenPerColumnM': oneLength * count,
            'valuePerColumn': weightOne,
            'valuePerBuilding':
                weightOne *
                savedNumber(m['qtyPerBuilding']).clamp(1, double.infinity),
          },
          'spacingM': spacingM,
          'coverM': cover,
          'hookExtraM': hook,
          'unitWeightKgPerM': uw,
        };
      }

      if (isFootingRebar) {
        final spacingLength = double.tryParse(secondarySpacingCtrl.text.trim());
        final cover = double.tryParse(embedCtrl.text.trim());
        final extra = double.tryParse(extraCtrl.text.trim());
        final length = savedNumber(m['lengthM']);
        final width = savedNumber(m['widthM']);
        if (spacingLength == null ||
            spacingLength <= 0 ||
            cover == null ||
            extra == null ||
            length <= 0 ||
            width <= 0) {
          return null;
        }
        final embed = savedNumber(m['embedEachEndM']);
        final barsAlongL =
            (((width - 2 * cover).clamp(0, double.infinity)) /
                    (spacing! / 1000))
                .floor() +
            1;
        final barsAlongW =
            (((length - 2 * cover).clamp(0, double.infinity)) /
                    (spacingLength / 1000))
                .floor() +
            1;
        final barL = length + 2 * embed + extra;
        final barW = width + 2 * embed + extra;
        final totalLengthOne = barsAlongL * barL + barsAlongW * barW;
        final valueOne = totalLengthOne * uw;
        return {
          'value': valueOne * totalQty,
          'valuePerFooting': valueOne,
          'valuePerBuilding':
              valueOne *
              savedNumber(m['qtyPerBuilding']).clamp(1, double.infinity),
          'diaMm': diameter,
          'coverM': cover,
          'extraM': extra,
          'spacingAcrossWidthM': spacing / 1000,
          'spacingAcrossLengthM': spacingLength / 1000,
          'nBarsAlongLength': barsAlongL,
          'barLengthAlongLengthM': barL,
          'totalLengthAlongLengthM': barsAlongL * barL,
          'nBarsAlongWidth': barsAlongW,
          'barLengthAlongWidthM': barW,
          'totalLengthAlongWidthM': barsAlongW * barW,
          'unitWeightKgPerM': uw,
        };
      }

      if (isStairMainRebar || isStairDistributionRebar) {
        final embed = double.tryParse(extraCtrl.text.trim());
        final width = savedNumber(m['stairWidthM']);
        final slope = savedNumber(m['slopingLengthM']);
        final landing = savedNumber(m['landingLenM']);
        final includeLanding = m['includeLanding'] == true;
        if (embed == null || width <= 0 || slope <= 0) return null;
        double weightOne;
        if (isStairMainRebar) {
          final bars = (width * 1000 / spacing!).floor() + 1;
          weightOne = bars * (slope + 2 * embed) * uw;
          if (includeLanding && landing > 0) {
            weightOne += bars * (landing + 2 * embed) * uw;
          }
        } else {
          final bars = (slope * 1000 / spacing!).floor() + 1;
          weightOne = bars * (width + 2 * embed) * uw;
          if (includeLanding && landing > 0) {
            final landingBars = (landing * 1000 / spacing).floor() + 1;
            weightOne += landingBars * (width + 2 * embed) * uw;
          }
        }
        return {
          'value': weightOne * totalQty,
          'valueOne': weightOne,
          if (isStairMainRebar) ...{
            'mainDiaMm': diameter,
            'mainSpacingMm': spacing,
            'mainEmbedEachEndM': embed,
          } else ...{
            'distDiaMm': diameter,
            'distSpacingMm': spacing,
            'distEmbedEachEndM': embed,
          },
        };
      }

      // Rebar families such as ramp, foundation and manually captured slab
      // bars do not all retain the same geometry fields. Their saved weight
      // and former unit weight still give a reliable total bar length, so a
      // diameter correction can recalculate kg without changing that length.
      if (!isSlabRebar && isAnyRebar) {
        final oldDiameter = savedNumber(
          m['diameterMm'] ??
              m['mainDiaMm'] ??
              m['stirDiaMm'] ??
              m['stirrupDiaMm'] ??
              m['diaMm'] ??
              m['distDiaMm'],
        );
        final oldUnitWeight =
            savedNumber(m['unitWeightKgPerM']) > 0
                ? savedNumber(m['unitWeightKgPerM'])
                : oldDiameter > 0
                ? oldDiameter * oldDiameter / 162.0
                : 0.0;
        var totalLength = savedNumber(
          m['totalLenM'] ??
              m['lengthAllM'] ??
              m['totalLengthM'] ??
              m['stirrupTotalLengthM'],
        );
        if (totalLength <= 0 && oldUnitWeight > 0) {
          totalLength = savedNumber(m['value']) / oldUnitWeight;
        }
        if (totalLength <= 0) return null;
        return {
          'value': totalLength * uw,
          'diameterMm': diameter,
          'diaMm': diameter,
          'unitWeightKgPerM': uw,
          'totalLenM': totalLength,
        };
      }

      if (!isSlabRebar) return null;
      final lengthM = double.tryParse(slabLengthCtrl.text.trim()) ?? 0;
      final widthM = double.tryParse(slabWidthCtrl.text.trim()) ?? 0;
      if (lengthM <= 0 || widthM <= 0) return null;
      final clearSpan = rebarDirection == 'alongL' ? lengthM : widthM;
      final across = rebarDirection == 'alongL' ? widthM : lengthM;
      final barsPerSlab = ((across * 1000 / spacing!).floor() + 1).clamp(
        1,
        1000000,
      );
      final lengthOneM = barsPerSlab * clearSpan;
      final unitWeightKgPerM = uw;
      final weightOneKg = lengthOneM * unitWeightKgPerM;
      return {
        'diameter': diameter,
        'spacing': spacing,
        'barsPerSlab': barsPerSlab,
        'barLengthM': clearSpan,
        'unitWeightKgPerM': unitWeightKgPerM,
        'lengthOneM': lengthOneM,
        'lengthAllM': lengthOneM * totalQty,
        'weightOneKg': weightOneKg,
        'weightAllKg': weightOneKg * totalQty,
      };
    }

    void refreshRebarPreview() {
      final calculation = calculateRebar();
      if (calculation != null) {
        valueCtrl.text = (calculation['value'] as num).toStringAsFixed(3);
      }
    }

    BoqPick? selectedBoq;
    String? error;
    final saved =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder:
              (dialogContext) => StatefulBuilder(
                builder:
                    (context, setState) => AlertDialog(
                      title: const Text('Modify saved item'),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isRoadProfile) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Measured road length: ${roadLengthM.toStringAsFixed(3)} m',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: roadWidthCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (_) {
                                  refreshRoadProfilePreview();
                                  setState(() => error = null);
                                },
                                decoration: InputDecoration(
                                  labelText:
                                      roadUsesClearingWidth
                                          ? 'Clearing width (m)'
                                          : roadUsesEarthworkWidth
                                          ? 'Road earthwork width (m)'
                                          : 'Pavement layer width (m)',
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                              if (roadThicknessField != null) ...[
                                const SizedBox(height: 12),
                                TextField(
                                  controller: roadThicknessCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged: (_) {
                                    refreshRoadProfilePreview();
                                    setState(() => error = null);
                                  },
                                  decoration: InputDecoration(
                                    labelText:
                                        roadOutputKey == 'common_excavation' ||
                                                roadOutputKey == 'fill'
                                            ? 'Average depth (mm)'
                                            : 'Layer thickness (mm)',
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ],
                              if (roadIsMc30) ...[
                                const SizedBox(height: 12),
                                TextField(
                                  controller: roadRateCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged: (_) {
                                    refreshRoadProfilePreview();
                                    setState(() => error = null);
                                  },
                                  decoration: const InputDecoration(
                                    labelText: 'Application rate (L/m²)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                            ],
                            if (isAnyRebar) ...[
                              if (isBeamMainRebar ||
                                  isBeamStirrups ||
                                  isColumnMainRebar ||
                                  isColumnStirrups) ...[
                                TextField(
                                  controller: memberLengthCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged: (_) {
                                    refreshRebarPreview();
                                    setState(() => error = null);
                                  },
                                  decoration: InputDecoration(
                                    labelText:
                                        (isColumnMainRebar || isColumnStirrups)
                                            ? 'Column height (m)'
                                            : isBeamStirrups
                                            ? 'Beam / stirrup zone length (m)'
                                            : 'Beam length (m)',
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (isSlabRebar) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: slabLengthCtrl,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        onChanged: (_) {
                                          refreshRebarPreview();
                                          setState(() => error = null);
                                        },
                                        decoration: const InputDecoration(
                                          labelText: 'Slab length (m)',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextField(
                                        controller: slabWidthCtrl,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        onChanged: (_) {
                                          refreshRebarPreview();
                                          setState(() => error = null);
                                        },
                                        decoration: const InputDecoration(
                                          labelText: 'Slab width (m)',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (hasEditableBarArrangement)
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: diameterCtrl,
                                        keyboardType: TextInputType.number,
                                        onChanged: (_) {
                                          refreshRebarPreview();
                                          setState(() => error = null);
                                        },
                                        decoration: const InputDecoration(
                                          labelText: 'Bar diameter (mm)',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextField(
                                        controller:
                                            (isBeamMainRebar ||
                                                    isColumnMainRebar)
                                                ? barsCtrl
                                                : spacingCtrl,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        onChanged: (_) {
                                          refreshRebarPreview();
                                          setState(() => error = null);
                                        },
                                        decoration: const InputDecoration(
                                          labelText: 'Spacing / number of bars',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                TextField(
                                  controller: diameterCtrl,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) {
                                    refreshRebarPreview();
                                    setState(() => error = null);
                                  },
                                  decoration: const InputDecoration(
                                    labelText: 'Bar diameter (mm)',
                                    helperText:
                                        'The saved bar length is retained and the weight is recalculated.',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              if (isSlabRebar)
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: rebarDirection,
                                        decoration: const InputDecoration(
                                          labelText: 'Bar direction',
                                          border: OutlineInputBorder(),
                                        ),
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'alongL',
                                            child: Text('Along length'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'alongW',
                                            child: Text('Along width'),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value == null) return;
                                          rebarDirection = value;
                                          refreshRebarPreview();
                                          setState(() => error = null);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: rebarPosition,
                                        decoration: const InputDecoration(
                                          labelText: 'Position',
                                          border: OutlineInputBorder(),
                                        ),
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'bottom',
                                            child: Text('Bottom'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'top',
                                            child: Text('Top'),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value == null) return;
                                          setState(() {
                                            rebarPosition = value;
                                            error = null;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              if (isFootingRebar) ...[
                                TextField(
                                  controller: secondarySpacingCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged: (_) {
                                    refreshRebarPreview();
                                    setState(() => error = null);
                                  },
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Spacing across footing length (mm)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (isBeamMainRebar || isColumnMainRebar) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: embedCtrl,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        onChanged: (_) {
                                          refreshRebarPreview();
                                          setState(() => error = null);
                                        },
                                        decoration: InputDecoration(
                                          labelText:
                                              isColumnMainRebar
                                                  ? 'Embed top (m)'
                                                  : 'Embed each end (m)',
                                          border: const OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    if (isColumnMainRebar) ...[
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: TextField(
                                          controller: secondEmbedCtrl,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          onChanged: (_) {
                                            refreshRebarPreview();
                                            setState(() => error = null);
                                          },
                                          decoration: const InputDecoration(
                                            labelText: 'Embed bottom (m)',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (isBeamMainRebar ||
                                  isColumnMainRebar ||
                                  isBeamStirrups ||
                                  isColumnStirrups ||
                                  isFootingRebar ||
                                  isStairMainRebar ||
                                  isStairDistributionRebar) ...[
                                Row(
                                  children: [
                                    if (isBeamStirrups ||
                                        isColumnStirrups ||
                                        isFootingRebar) ...[
                                      Expanded(
                                        child: TextField(
                                          controller: embedCtrl,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          onChanged: (_) {
                                            refreshRebarPreview();
                                            setState(() => error = null);
                                          },
                                          decoration: const InputDecoration(
                                            labelText: 'Cover (m)',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    Expanded(
                                      child: TextField(
                                        controller: extraCtrl,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        onChanged: (_) {
                                          refreshRebarPreview();
                                          setState(() => error = null);
                                        },
                                        decoration: InputDecoration(
                                          labelText:
                                              (isBeamStirrups ||
                                                      isColumnStirrups)
                                                  ? 'Hooks add (m)'
                                                  : (isStairMainRebar ||
                                                      isStairDistributionRebar)
                                                  ? 'Embed each end (m)'
                                                  : 'Extra / laps (m)',
                                          border: const OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                              const SizedBox(height: 12),
                            ],
                            TextField(
                              controller: valueCtrl,
                              readOnly: isAnyRebar || isRoadProfile,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText:
                                    '${isAnyRebar || isRoadProfile ? 'Recalculated quantity' : 'Quantity'} (${_prettyUnit((m['unit'] ?? '').toString())})',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: boqCtrl,
                                    readOnly: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Selected BOQ code',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    if (!Get.isRegistered<
                                      ImageTakeoffController
                                    >()) {
                                      setState(
                                        () =>
                                            error =
                                                'BOQ picker is not available.',
                                      );
                                      return;
                                    }
                                    final picked =
                                        await Get.find<ImageTakeoffController>()
                                            .showBoqPickerDialog(
                                              context: dialogContext,
                                            );
                                    if (picked == null) return;
                                    setState(() {
                                      selectedBoq = picked;
                                      boqCtrl.text = picked.code;
                                      error = null;
                                    });
                                  },
                                  icon: const Icon(Icons.search_rounded),
                                  label: const Text('Pick BOQ'),
                                ),
                              ],
                            ),
                            if (selectedBoq != null &&
                                selectedBoq!.description.trim().isNotEmpty) ...[
                              const SizedBox(height: 7),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  selectedBoq!.description,
                                  style: const TextStyle(
                                    color: AqsColors.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                            if (error != null) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  error!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () {
                            if (isRoadProfile &&
                                calculateRoadProfile() == null) {
                              setState(
                                () =>
                                    error =
                                        'Enter a valid width and layer thickness or application rate.',
                              );
                              return;
                            }
                            if (isAnyRebar && calculateRebar() == null) {
                              setState(
                                () =>
                                    error =
                                        'Enter valid reinforcement details. The saved member geometry is also required for recalculation.',
                              );
                              return;
                            }
                            if (boqCtrl.text.trim().isEmpty) {
                              setState(() => error = 'Pick a BOQ item.');
                              return;
                            }
                            final value = double.tryParse(
                              valueCtrl.text.trim(),
                            );
                            if (value == null || value < 0) {
                              setState(() => error = 'Enter a valid quantity.');
                              return;
                            }
                            Navigator.pop(dialogContext, true);
                          },
                          child: const Text('Save'),
                        ),
                      ],
                    ),
              ),
        ) ??
        false;
    if (saved) {
      final rebar = isAnyRebar ? calculateRebar() : null;
      final roadQuantity = isRoadProfile ? calculateRoadProfile() : null;
      await doc.reference.update({
        'value': roadQuantity ?? double.parse(valueCtrl.text.trim()),
        if (isRoadProfile) 'quantity': roadQuantity,
        'boqCode': boqCtrl.text.trim(),
        if (isRoadProfile) ...{
          roadWidthField: double.parse(roadWidthCtrl.text.trim()),
          if (roadThicknessField != null)
            roadThicknessField: double.parse(roadThicknessCtrl.text.trim()),
          if (roadIsMc30) roadRateField: double.parse(roadRateCtrl.text.trim()),
        },
        if (isBeamMainRebar) ...{
          'beamLengthM': double.parse(memberLengthCtrl.text.trim()),
          'lengthM': double.parse(memberLengthCtrl.text.trim()),
        },
        if (isBeamStirrups) ...{
          'zoneLengthM': double.parse(memberLengthCtrl.text.trim()),
          'beamLengthM': double.parse(memberLengthCtrl.text.trim()),
        },
        if (isColumnMainRebar || isColumnStirrups)
          'heightM': double.parse(memberLengthCtrl.text.trim()),
        if (isSlabRebar) ...{
          'lengthM': double.parse(slabLengthCtrl.text.trim()),
          'widthM': double.parse(slabWidthCtrl.text.trim()),
        },
        if (selectedBoq != null) ...{
          'boqItemId': selectedBoq!.id,
          'boqDescription': selectedBoq!.description,
        },
        if (rebar != null) ...{
          ...rebar,
          if (isSlabRebar) ...{
            'diameterMm': rebar['diameter'],
            'spacingMm': rebar['spacing'],
            'direction': rebarDirection,
            'position': rebarPosition,
            'barsPerSlab': rebar['barsPerSlab'],
            'barLengthM': rebar['barLengthM'],
            'unitWeightKgPerM': rebar['unitWeightKgPerM'],
            'lengthOneM': rebar['lengthOneM'],
            'lengthPerBuildingM':
                (rebar['lengthOneM'] as num) *
                savedNumber(m['qtyPerBuilding']).clamp(1, double.infinity),
            'lengthAllM': rebar['lengthAllM'],
            'valueOne': rebar['weightOneKg'],
            'valuePerBuilding':
                (rebar['weightOneKg'] as num) *
                savedNumber(m['qtyPerBuilding']).clamp(1, double.infinity),
            'value': rebar['weightAllKg'],
          },
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _refreshEditedMeasurement(doc);
      await _refreshSharedMeasurements();
    }
    valueCtrl.dispose();
    boqCtrl.dispose();
    diameterCtrl.dispose();
    spacingCtrl.dispose();
    secondarySpacingCtrl.dispose();
    barsCtrl.dispose();
    embedCtrl.dispose();
    secondEmbedCtrl.dispose();
    extraCtrl.dispose();
  }

  // --- UI helper ---
  Widget _summaryHero({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AqsColors.primaryDark, Color(0xFF17448A)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24155EEF),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const AqsLogoMark(size: 38, inverted: true),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 15, color: const Color(0xFFBFD2FA)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFCBD9F5),
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryMetric(String label, double value, String unit) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AqsColors.primarySoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFD2FA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AqsColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${value.toStringAsFixed(2)} $unit',
            style: const TextStyle(
              color: AqsColors.primaryDark,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryStatCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AqsColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$value $unit',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AqsColors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quantityPill(String label, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AqsColors.successSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFA6F4C5)),
      ),
      child: Text(
        '$label ${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}',
        style: const TextStyle(
          color: Color(0xFF027A48),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _countPill(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AqsColors.border),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(
          color: AqsColors.text,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _saasMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
  }) {
    return Container(
      width: 157,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AqsColors.primarySoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: AqsColors.primary),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AqsColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    text: value,
                    children: [
                      TextSpan(
                        text: ' $unit',
                        style: const TextStyle(
                          color: AqsColors.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AqsColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _areaMeasurementRow({
    required int index,
    required double value,
    required String label,
    required String boqCode,
  }) {
    final cleanLabel = label.trim();
    final cleanBoq = boqCode.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AqsColors.primarySoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                color: AqsColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cleanLabel.isEmpty ? 'Area $index' : cleanLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AqsColors.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (cleanBoq.isNotEmpty)
                  Text(
                    'BOQ $cleanBoq',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AqsColors.muted, fontSize: 9),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${value.toStringAsFixed(3)} m²',
            style: const TextStyle(
              color: AqsColors.primaryDark,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _roadProfileMeasurementRow({
    required int index,
    required double lengthM,
    required String profile,
  }) {
    final cleanProfile = profile.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AqsColors.primarySoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                color: AqsColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              cleanProfile.isEmpty ? 'Road measurement $index' : cleanProfile,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AqsColors.text,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${lengthM.toStringAsFixed(3)} m',
            style: const TextStyle(
              color: AqsColors.primaryDark,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _saasMeasurementFooter(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: AqsColors.primarySoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFD2FA)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 17,
            color: AqsColors.primary,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Saved measurements',
              style: TextStyle(
                color: AqsColors.primaryDark,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFBFD2FA)),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: AqsColors.primaryDark,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _titleRow() {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AqsColors.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.summarize,
            size: 18,
            color: AqsColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _buildTitle(),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AqsColors.text,
              letterSpacing: -0.2,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _prettyUnit(String u) {
    switch (u) {
      case 'm2':
        return 'm²';
      case 'm3':
        return 'm³';
      default:
        return u;
    }
  }

  // ✅ Titles for all named types + fallback "Summary"
  String _buildTitle() {
    final mt = (activeMeasureType ?? '').trim();
    final lower = mt.toLowerCase();

    if (lower == 'walling') return 'Walling Summary';
    if (lower == 'plinth') return 'Plinth Summary';
    if (lower == 'groundpreparation') return 'Ground Preparation Summary';
    if (lower == 'liftshaft' || lower == 'liftshaftassembly') {
      return 'Lift Shaft Summary';
    }
    if (lower == 'count') return 'Count Summary';
    if (lower == 'compositeslab' || lower == 'slabcomposite') {
      return 'Composite Slab Summary';
    }
    if (lower == 'compositefooting' || lower == 'footingcomposite') {
      return 'Composite Footing Summary';
    }
    if (lower == 'compositebeam' || lower == 'beamcomposite') {
      return 'Composite Beam Summary';
    }
    if (lower == 'compositecolumn' || lower == 'columncomposite') {
      return 'Composite Column Summary';
    }
    if (lower == 'roofsheeting') {
      return 'Roof Covering Summary';
    }
    if (lower == 'compositeroofing') {
      return 'Timber Roof Structure Summary';
    }
    if (lower == 'roofsheetingandtimber' || lower == 'roofingfinsh') {
      return 'Roof Sheet and Timber';
    }
    if (lower == 'trusstemplate' ||
        lower == 'roofstructure' ||
        lower == 'roofstructuremember') {
      return 'Steel Roof Structure Summary';
    }

    final label = (activeLabel ?? '').trim();
    final boq = (activeBoqCode ?? '').trim();

    if (label.isNotEmpty && boq.isNotEmpty) return '$label Summary (BOQ $boq)';
    if (label.isNotEmpty) return '$label Summary';
    if (boq.isNotEmpty) {
      return '${_prettyNameFromMeasureType(mt)} Summary (BOQ $boq)';
    }
    return '${_prettyNameFromMeasureType(mt)} Summary';
  }

  String _prettyNameFromMeasureType(String t) {
    final lower = t.trim().toLowerCase();
    if (lower == 'tiling') return 'Tiling';
    if (lower == 'plinth') return 'Plinth';
    if (lower == 'groundpreparation') return 'Ground Preparation';
    if (lower == 'liftshaft' || lower == 'liftshaftassembly') {
      return 'Lift Shaft';
    }
    if (lower == 'hardcore') return 'Hardcore';
    if (lower == 'pavement') return 'Pavement';
    if (lower == 'roofing') return 'Roofing';
    if (lower == 'roofsheeting') return 'Roof Covering';
    if (lower == 'compositeroofing') return 'Timber Roof Structure';
    if (lower == 'roofsheetingandtimber') return 'Roofing with Timber';
    if (lower == 'beam') return 'Beam';
    if (lower == 'pipe') return 'Pipe';
    if (lower == 'door') return 'Door';
    if (lower == 'window') return 'Window';
    if (lower == 'count') return 'Count';

    return t.isEmpty
        ? 'Active Item'
        : t
            .split(RegExp(r'[_\s]+'))
            .map(
              (w) =>
                  w.isEmpty
                      ? ''
                      : w[0].toUpperCase() + w.substring(1).toLowerCase(),
            )
            .join(' ');
  }

  Widget _buildCardBody(BuildContext context, {required Widget child}) {
    return child;
  }
}

class _MeasurementContextIds {
  final String projectId;
  final String buildingId;

  const _MeasurementContextIds({
    required this.projectId,
    required this.buildingId,
  });
}

class _SavedMeasurementRecord {
  final String id;
  final Map<String, dynamic> dataMap;
  final DocumentReference<Map<String, dynamic>> reference;

  const _SavedMeasurementRecord({
    required this.id,
    required this.dataMap,
    required this.reference,
  });

  Map<String, dynamic> data() => dataMap;
}
