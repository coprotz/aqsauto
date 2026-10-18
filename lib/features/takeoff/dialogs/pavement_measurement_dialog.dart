import 'dart:async';
import 'dart:math' as math;

import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/dashboards/controllers/project_buildings_controller.dart';
import 'package:aqs/features/utils/helpers/boq_helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class _PavementOutput {
  _PavementOutput(
    this.type,
    this.title,
    this.unit, {
    this.thicknessMm = 0,
    this.included = true,
  });

  final String type;
  final String title;
  final String unit;
  double thicknessMm;
  bool included;
  BoqPick? boq;
}

class _PavementExtents {
  const _PavementExtents({required this.lengthM, required this.widthM});

  final double lengthM;
  final double widthM;
}

_PavementExtents _estimatePavementExtents(List<Offset> polygon, double ppu) {
  if (polygon.length < 2 || ppu <= 0) {
    return const _PavementExtents(lengthM: 0, widthM: 0);
  }

  // Align the local axes to the longest polygon edge. This gives a much more
  // useful length/width estimate than an axis-aligned screen bounding box when
  // the pavement is rotated on the drawing.
  var longest = 0.0;
  var angle = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final d2 = dx * dx + dy * dy;
    if (d2 > longest) {
      longest = d2;
      angle = math.atan2(dy, dx);
    }
  }

  final c = math.cos(angle);
  final s = math.sin(angle);
  var minX = double.infinity;
  var maxX = double.negativeInfinity;
  var minY = double.infinity;
  var maxY = double.negativeInfinity;

  for (final p in polygon) {
    final x = p.dx * c + p.dy * s;
    final y = -p.dx * s + p.dy * c;
    minX = math.min(minX, x);
    maxX = math.max(maxX, x);
    minY = math.min(minY, y);
    maxY = math.max(maxY, y);
  }

  final a = (maxX - minX).abs() / ppu;
  final b = (maxY - minY).abs() / ppu;
  return _PavementExtents(lengthM: math.max(a, b), widthM: math.min(a, b));
}

Future<bool> showPavementMeasurementDialog({
  required List<List<Offset>> polygons,
  List<List<Offset>> deductionPolygons = const <List<Offset>>[],
  List<String> deductionLabels = const <String>[],
  required Map<String, dynamic> drawingData,
  required String projectId,
  required String buildingId,
  required String drawingId,
  required Color currentColor,
  required CollectionReference<Map<String, dynamic>> measurementsRef,
  required Future<BoqPick?> Function(BuildContext context) pickBoq,
}) async {
  final ppu =
      drawingData['pixelsPerUnit'] is num
          ? (drawingData['pixelsPerUnit'] as num).toDouble()
          : double.tryParse('${drawingData['pixelsPerUnit'] ?? ''}') ?? 0;
  if (drawingData['calibrated'] != true || ppu <= 0) {
    Get.snackbar(
      'Calibration required',
      'Calibrate the drawing before measuring pavement.',
    );
    return false;
  }

  double polygonAreaM2(List<Offset> polygon) {
    if (polygon.length < 3) return 0;
    var areaPx = 0.0;
    for (var i = 0; i < polygon.length; i++) {
      final n = polygon[(i + 1) % polygon.length];
      areaPx += polygon[i].dx * n.dy - n.dx * polygon[i].dy;
    }
    return areaPx.abs() / 2 / (ppu * ppu);
  }

  final validPolygons =
      polygons
          .where((polygon) => polygon.length >= 3)
          .map(List<Offset>.from)
          .toList();
  if (validPolygons.isEmpty) return false;

  bool pointInPolygon(Offset point, List<Offset> polygon) {
    if (polygon.length < 3) return false;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final pi = polygon[i];
      final pj = polygon[j];
      final intersects =
          ((pi.dy > point.dy) != (pj.dy > point.dy)) &&
          (point.dx <
              (pj.dx - pi.dx) *
                      (point.dy - pi.dy) /
                      ((pj.dy - pi.dy).abs() < 1e-9 ? 1e-9 : (pj.dy - pi.dy)) +
                  pi.dx);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  Offset polygonCentroid(List<Offset> polygon) {
    if (polygon.isEmpty) return Offset.zero;
    var x = 0.0;
    var y = 0.0;
    for (final p in polygon) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / polygon.length, y / polygon.length);
  }

  final validDeductionPolygons =
      deductionPolygons
          .where((polygon) => polygon.length >= 3)
          .map(List<Offset>.from)
          .toList();
  final validDeductionLabels = <String>[
    for (var i = 0; i < validDeductionPolygons.length; i++)
      i < deductionLabels.length && deductionLabels[i].trim().isNotEmpty
          ? deductionLabels[i].trim()
          : 'Deduction ${i + 1}',
  ];

  final zoneAreasM2 = validPolygons.map(polygonAreaM2).toList();
  final grossAreaM2 = zoneAreasM2.fold<double>(0.0, (sum, area) => sum + area);
  final deductionAreasM2 = validDeductionPolygons.map(polygonAreaM2).toList();
  final totalDeductionM2 = deductionAreasM2.fold<double>(
    0.0,
    (sum, area) => sum + area,
  );
  final zoneDeductionM2 = List<double>.filled(validPolygons.length, 0.0);
  var unassignedDeductionM2 = 0.0;
  for (var i = 0; i < validDeductionPolygons.length; i++) {
    final centroid = polygonCentroid(validDeductionPolygons[i]);
    var assigned = false;
    for (var z = 0; z < validPolygons.length; z++) {
      if (pointInPolygon(centroid, validPolygons[z])) {
        zoneDeductionM2[z] += deductionAreasM2[i];
        assigned = true;
        break;
      }
    }
    if (!assigned) unassignedDeductionM2 += deductionAreasM2[i];
  }
  if (unassignedDeductionM2 > 0 && grossAreaM2 > 0) {
    // Fallback for a deduction crossing zone boundaries: distribute by gross area.
    for (var z = 0; z < zoneDeductionM2.length; z++) {
      zoneDeductionM2[z] +=
          unassignedDeductionM2 * zoneAreasM2[z] / grossAreaM2;
    }
  }
  final zoneNetAreasM2 = <double>[
    for (var z = 0; z < zoneAreasM2.length; z++)
      math.max(0.0, zoneAreasM2[z] - zoneDeductionM2[z]).toDouble(),
  ];
  final areaM2 = zoneNetAreasM2.fold<double>(0.0, (sum, area) => sum + area);
  if (grossAreaM2 <= 0 || areaM2 <= 0 || totalDeductionM2 >= grossAreaM2) {
    Get.snackbar(
      'Invalid pavement area',
      'Deductions must leave a positive net pavement area.',
    );
    return false;
  }

  final zoneExtents =
      validPolygons
          .map((polygon) => _estimatePavementExtents(polygon, ppu))
          .toList();

  var pavementType = 'Pavement block';
  var blockSize = '200 x 100 x 80 mm';
  var topsoilMm = 150.0;
  var excavationAuto = true;
  var excavationMm = 0.0;
  var saving = false;
  var restoringLastCodes = false;
  String? error;
  String? restoreStatus;

  // Rigid pavement defaults taken from the supplied typical joint detail.
  var jointAuto = true;
  var panelLengthM = 5.0;
  var panelWidthM = 5.0;
  var manualContractionJointM = 0.0;
  var manualExpansionJointM = 0.0;
  var includeSideEdgeJoints = false;
  var dowelDiameterMm = 32.0;
  var dowelLengthMm = 800.0;
  var dowelSpacingMm =
      0.0; // Drawing does not state c/c spacing: user must enter it.
  var chairDiameterMm = 12.0;
  var chairSpacingMm =
      0.0; // Drawing identifies R12 chairs but not their spacing.
  var crossBarDiameterMm = 12.0;
  var crossBarFollowsJointLength = true;

  List<_PavementOutput> makeLayers(String type) =>
      type == 'Rigid concrete pavement'
          ? [
            _PavementOutput(
              'rigidConcrete',
              'Rigid concrete pavement',
              'm3',
              thicknessMm: 200,
            ),
            _PavementOutput('c1', 'C1 layer', 'm3', thicknessMm: 150),
            _PavementOutput('g15', 'G15 layer', 'm3', thicknessMm: 150),
            _PavementOutput('g7', 'G7 layer', 'm3', thicknessMm: 150),
            _PavementOutput('g3', 'G3 layer', 'm3', thicknessMm: 200),
          ]
          : [
            _PavementOutput(
              'sandCapping',
              'Sand capping / bedding',
              'm3',
              thicknessMm: 30,
            ),
            _PavementOutput('g45', 'G45 layer', 'm3', thicknessMm: 150),
            _PavementOutput('g15', 'G15 layer', 'm3', thicknessMm: 150),
            _PavementOutput('g7', 'G7 layer', 'm3', thicknessMm: 150),
            _PavementOutput('g3', 'G3 layer', 'm3', thicknessMm: 200),
            _PavementOutput(
              'pavingBlocks',
              'Interlocking pavement blocks',
              'm2',
            ),
          ];

  var layers = makeLayers(pavementType);
  final siteClearance = _PavementOutput(
    'siteClearance',
    'Site clearance',
    'ha',
  );
  final topsoil = _PavementOutput(
    'topsoilExcavation',
    'Excavate / remove topsoil',
    'm3',
  );
  final commonExc = _PavementOutput(
    'commonExcavation',
    'Common excavation to formation',
    'm3',
  );

  final contractionJoint = _PavementOutput(
    'contractionJoint',
    'Contraction joints',
    'm',
  );
  final expansionJoint = _PavementOutput(
    'expansionJoint',
    'Expansion joints',
    'm',
  );
  final dowelBars = _PavementOutput(
    'dowelBars',
    'Dowel bars',
    'No.',
    included: false,
  );
  final chairBars = _PavementOutput(
    'chairBars',
    'Chair bars',
    'No.',
    included: false,
  );
  final crossBars = _PavementOutput(
    'crossBars',
    'Cross bars',
    'm',
    included: false,
  );

  List<_PavementOutput> currentOutputs() => [
    siteClearance,
    topsoil,
    commonExc,
    ...layers,
    if (pavementType == 'Rigid concrete pavement') ...[
      contractionJoint,
      expansionJoint,
      dowelBars,
      chairBars,
      crossBars,
    ],
  ];

  Future<void> restoreLastCodes(
    BuildContext dialogContext,
    StateSetter setState,
  ) async {
    setState(() {
      restoringLastCodes = true;
      restoreStatus = null;
      error = null;
    });

    try {
      final sharedController =
          Get.isRegistered<ProjectBuildingsController>()
              ? Get.find<ProjectBuildingsController>()
              : null;
      var measurementRows =
          sharedController
              ?.measurementsFor(projectId, buildingId)
              .where(
                (row) =>
                    (row['measureType'] ?? '').toString().toLowerCase() ==
                    'pavement',
              )
              .map(Map<String, dynamic>.from)
              .toList() ??
          <Map<String, dynamic>>[];

      if (measurementRows.isEmpty) {
        final measurementSnapshot = await measurementsRef
            .where('measureType', isEqualTo: 'pavement')
            .get()
            .timeout(const Duration(seconds: 8));
        if (!dialogContext.mounted) return;
        measurementRows =
            measurementSnapshot.docs
                .map(
                  (doc) => <String, dynamic>{'id': doc.id, ...doc.data()},
                )
                .toList();
      }

      final mappedRows =
          measurementRows.where((data) {
            return (data['boqItemId'] ?? '').toString().trim().isNotEmpty &&
                (data['itemType'] ?? data['type'] ?? '')
                    .toString()
                    .trim()
                    .isNotEmpty;
          }).toList();

      if (mappedRows.isEmpty) {
        setState(() {
          restoreStatus = 'No previously saved pavement BOQ codes were found.';
        });
        return;
      }

      int savedAt(Map<String, dynamic> row) {
        final value = row['updatedAt'] ?? row['createdAt'];
        return value is Timestamp ? value.millisecondsSinceEpoch : 0;
      }

      mappedRows.sort((a, b) => savedAt(b).compareTo(savedAt(a)));
      final matchingTypeDocs =
          mappedRows
              .where(
                (row) =>
                    (row['pavementType'] ?? '').toString().trim() ==
                    pavementType,
              )
              .toList();
      final latestDoc =
          (matchingTypeDocs.isEmpty ? mappedRows : matchingTypeDocs).first;
      final latestData = latestDoc;
      final latestGroupId =
          (latestData['pavementGroupId'] ?? '').toString().trim();
      final latestGroupDocs =
          latestGroupId.isEmpty
              ? [latestDoc]
              : mappedRows
                  .where(
                    (row) =>
                        (row['pavementGroupId'] ?? '')
                            .toString()
                            .trim() ==
                        latestGroupId,
                  )
                  .toList();

      String normalizedCode(dynamic value) =>
          value.toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

      var boqRows =
          sharedController
              ?.boqFor(projectId, buildingId)
              .map(Map<String, dynamic>.from)
              .toList() ??
          <Map<String, dynamic>>[];
      if (boqRows.isEmpty) {
        final boqSnapshot = await FirebaseFirestore.instance
            .collection('projects')
            .doc(projectId)
            .collection('buildings')
            .doc(buildingId)
            .collection('boq')
            .get()
            .timeout(const Duration(seconds: 8));
        if (!dialogContext.mounted) return;
        boqRows =
            boqSnapshot.docs
                .map(
                  (doc) => <String, dynamic>{'id': doc.id, ...doc.data()},
                )
                .toList();
      }

      final boqById = <String, Map<String, dynamic>>{};
      final boqByResolvedCode = <String, Map<String, dynamic>>{};
      final ambiguousResolvedCodes = <String>{};
      for (final row in boqRows) {
        final data = Map<String, dynamic>.from(row);
        if ((data['rowType'] ?? 'item').toString().toLowerCase() != 'item') {
          continue;
        }
        final id = (data['id'] ?? '').toString().trim();
        final resolvedCode = hierarchicalBoqCodeFromRows(data, boqRows).trim();
        if (id.isNotEmpty) {
          data['_restoreResolvedCode'] = resolvedCode;
          boqById[id] = data;
        }
        final normalizedResolved = normalizedCode(resolvedCode);
        if (id.isNotEmpty && normalizedResolved.isNotEmpty) {
          if (boqByResolvedCode.containsKey(normalizedResolved)) {
            boqByResolvedCode.remove(normalizedResolved);
            ambiguousResolvedCodes.add(normalizedResolved);
          } else if (!ambiguousResolvedCodes.contains(normalizedResolved)) {
            boqByResolvedCode[normalizedResolved] = data;
          }
        }
      }

      final savedByType = <String, Map<String, dynamic>>{};
      for (final data in latestGroupDocs) {
        final type =
            (data['itemType'] ?? data['type'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
        if (type.isNotEmpty) savedByType.putIfAbsent(type, () => data);
      }

      var restored = 0;
      for (final output in currentOutputs()) {
        final saved = savedByType[output.type.toLowerCase()];
        if (saved == null) continue;
        final savedId = (saved['boqItemId'] ?? '').toString().trim();
        final savedCode = normalizedCode(saved['boqCode'] ?? '');
        // Document identity is authoritative. Code fallback is deliberately
        // limited to hierarchy-resolved codes, so a repeated raw leaf such as
        // "a" or "b" can never attach a measurement to the wrong BOQ item.
        final current =
            boqById[savedId] ?? boqByResolvedCode[savedCode];
        if (current == null) continue;
        final code =
            (current['_restoreResolvedCode'] ?? '').toString().trim();
        if (code.isEmpty) continue;
        final description =
            (current['description'] ?? saved['boqDescription'] ?? '')
                .toString()
                .trim();
        output.boq = BoqPick(
          id: (current['id'] ?? '').toString(),
          code: code,
          description: description,
        );
        restored++;
      }

      setState(() {
        restoreStatus =
            restored == 0
                ? 'The last pavement codes are no longer available in this BOQ.'
                : 'Restored $restored BOQ code${restored == 1 ? '' : 's'} '
                    'from the last pavement take-off.';
      });
    } on TimeoutException {
      if (!dialogContext.mounted) return;
      setState(() {
        error =
            'Restoring the last codes timed out. Check the connection and try again.';
      });
    } catch (e) {
      if (!dialogContext.mounted) return;
      setState(() {
        error = 'Could not restore the last pavement BOQ codes: $e';
      });
    } finally {
      if (dialogContext.mounted) {
        setState(() => restoringLastCodes = false);
      }
    }
  }

  double totalConstructionMm() =>
      layers
          .where((e) => e.included && e.unit == 'm3')
          .fold<double>(0.0, (s, e) => s + e.thicknessMm) +
      (pavementType == 'Pavement block'
          ? (blockSize.contains('80') ? 80.0 : 60.0)
          : 0.0);

  int internalJointLines(double spanM, double spacingM) {
    if (spanM <= 0 || spacingM <= 0) return 0;
    return math.max(0, (spanM / spacingM).ceil() - 1).toInt();
  }

  double zoneAutoContractionJointM(_PavementExtents extents) {
    final length = extents.lengthM;
    final width = extents.widthM;
    if (length <= 0 || width <= 0) return 0;
    final acrossLength = internalJointLines(length, panelLengthM);
    final acrossWidth = internalJointLines(width, panelWidthM);
    var result = acrossLength * width + acrossWidth * length;
    if (includeSideEdgeJoints) result += 2 * length;
    return result;
  }

  double zoneAutoExpansionJointM(_PavementExtents extents) {
    if (extents.widthM <= 0) return 0;
    // The supplied typical layout shows expansion joints at the two pavement
    // ends. Other projects can switch to manual mode if their arrangement differs.
    return 2 * extents.widthM;
  }

  double zoneNetFactor(int zoneIndex) {
    final gross = zoneAreasM2[zoneIndex];
    if (gross <= 0) return 0;
    return (zoneNetAreasM2[zoneIndex] / gross).clamp(0.0, 1.0).toDouble();
  }

  double autoContractionJointM() {
    var total = 0.0;
    for (var i = 0; i < zoneExtents.length; i++) {
      total += zoneAutoContractionJointM(zoneExtents[i]) * zoneNetFactor(i);
    }
    return total;
  }

  double autoExpansionJointM() {
    var total = 0.0;
    for (var i = 0; i < zoneExtents.length; i++) {
      total += zoneAutoExpansionJointM(zoneExtents[i]) * zoneNetFactor(i);
    }
    return total;
  }

  double contractionJointM() =>
      jointAuto ? autoContractionJointM() : manualContractionJointM;
  double expansionJointM() =>
      jointAuto ? autoExpansionJointM() : manualExpansionJointM;
  double totalJointM() => contractionJointM() + expansionJointM();

  double dowelCount() {
    if (dowelSpacingMm <= 0) return 0;
    return (totalJointM() / (dowelSpacingMm / 1000)).ceilToDouble();
  }

  double chairCount() {
    if (chairSpacingMm <= 0) return 0;
    return (totalJointM() / (chairSpacingMm / 1000)).ceilToDouble();
  }

  double crossBarLengthM() => crossBarFollowsJointLength ? totalJointM() : 0;

  double qty(_PavementOutput o) {
    if (o.type == 'siteClearance') return areaM2 / 10000;
    if (o.type == 'topsoilExcavation') return areaM2 * topsoilMm / 1000;
    if (o.type == 'commonExcavation') {
      return areaM2 *
          (excavationAuto ? totalConstructionMm() : excavationMm) /
          1000;
    }
    if (o.type == 'contractionJoint') return contractionJointM();
    if (o.type == 'expansionJoint') return expansionJointM();
    if (o.type == 'dowelBars') return dowelCount();
    if (o.type == 'chairBars') return chairCount();
    if (o.type == 'crossBars') return crossBarLengthM();
    if (o.unit == 'm3') return areaM2 * o.thicknessMm / 1000;
    return areaM2;
  }

  double qtyForZone(_PavementOutput o, int zoneIndex) {
    final zoneArea = zoneNetAreasM2[zoneIndex];
    if (o.type == 'siteClearance') return zoneArea / 10000;
    if (o.type == 'topsoilExcavation') return zoneArea * topsoilMm / 1000;
    if (o.type == 'commonExcavation') {
      return zoneArea *
          (excavationAuto ? totalConstructionMm() : excavationMm) /
          1000;
    }
    if (o.type == 'contractionJoint') {
      if (jointAuto)
        return zoneAutoContractionJointM(zoneExtents[zoneIndex]) *
            zoneNetFactor(zoneIndex);
      return areaM2 > 0 ? manualContractionJointM * zoneArea / areaM2 : 0;
    }
    if (o.type == 'expansionJoint') {
      if (jointAuto)
        return zoneAutoExpansionJointM(zoneExtents[zoneIndex]) *
            zoneNetFactor(zoneIndex);
      return areaM2 > 0 ? manualExpansionJointM * zoneArea / areaM2 : 0;
    }
    if (o.type == 'dowelBars') {
      final total = totalJointM();
      if (total <= 0) return 0;
      final zoneJoint =
          qtyForZone(contractionJoint, zoneIndex) +
          qtyForZone(expansionJoint, zoneIndex);
      return dowelCount() * zoneJoint / total;
    }
    if (o.type == 'chairBars') {
      final total = totalJointM();
      if (total <= 0) return 0;
      final zoneJoint =
          qtyForZone(contractionJoint, zoneIndex) +
          qtyForZone(expansionJoint, zoneIndex);
      return chairCount() * zoneJoint / total;
    }
    if (o.type == 'crossBars') {
      return crossBarFollowsJointLength
          ? qtyForZone(contractionJoint, zoneIndex) +
              qtyForZone(expansionJoint, zoneIndex)
          : 0;
    }
    if (o.unit == 'm3') return zoneArea * o.thicknessMm / 1000;
    return zoneArea;
  }

  final saved = await showDialog<bool>(
    context: Get.context!,
    barrierDismissible: false,
    builder:
        (dialogContext) => StatefulBuilder(
          builder: (context, setState) {
            Widget numberField({
              required String label,
              required double value,
              required ValueChanged<double> onChanged,
              double width = 120,
              String? suffix,
            }) => SizedBox(
              width: width,
              child: TextFormField(
                initialValue:
                    value == 0
                        ? ''
                        : value.toStringAsFixed(value % 1 == 0 ? 0 : 2),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: label,
                  suffixText: suffix,
                  isDense: true,
                ),
                onChanged:
                    (v) => setState(() => onChanged(double.tryParse(v) ?? 0)),
              ),
            );

            Widget boqRow(_PavementOutput o) => Row(
              children: [
                Expanded(
                  child: Text(
                    o.boq == null
                        ? 'No BOQ item selected'
                        : '${o.boq!.code} — ${o.boq!.description}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed:
                      saving || restoringLastCodes
                          ? null
                          : () async {
                            final b = await pickBoq(context);
                            if (b != null) {
                              setState(() {
                                o.boq = b;
                                error = null;
                              });
                            }
                          },
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('BOQ'),
                ),
              ],
            );

            Widget outputCard(
              _PavementOutput o, {
              bool thickness = false,
              String? subtitle,
            }) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: o.included,
                          onChanged:
                              saving
                                  ? null
                                  : (v) =>
                                      setState(() => o.included = v ?? false),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                o.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (subtitle != null)
                                Text(
                                  subtitle,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        if (thickness && o.included)
                          SizedBox(
                            width: 105,
                            child: TextFormField(
                              initialValue: o.thicknessMm.toStringAsFixed(0),
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'mm',
                                isDense: true,
                              ),
                              onChanged:
                                  (v) => setState(
                                    () =>
                                        o.thicknessMm = double.tryParse(v) ?? 0,
                                  ),
                            ),
                          ),
                        const SizedBox(width: 10),
                        Text(
                          '${qty(o).toStringAsFixed(o.unit == 'ha' ? 4 : (o.unit == 'No.' ? 0 : 3))} ${o.unit}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    if (o.included) boqRow(o),
                  ],
                ),
              ),
            );

            Widget rigidJointSection() => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                ExpansionTile(
                  initiallyExpanded: true,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: const Text(
                    'Rigid pavement joint system',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${validPolygons.length} zone${validPolygons.length == 1 ? '' : 's'} · ${areaM2.toStringAsFixed(3)} m² net · joints calculated per zone',
                  ),
                  children: [
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Switch(
                                  value: jointAuto,
                                  onChanged:
                                      saving
                                          ? null
                                          : (v) =>
                                              setState(() => jointAuto = v),
                                ),
                                Expanded(
                                  child: Text(
                                    jointAuto
                                        ? 'Automatic joint layout from measured pavement geometry'
                                        : 'Manual joint lengths',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (jointAuto) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  numberField(
                                    label: 'Panel length',
                                    value: panelLengthM,
                                    suffix: 'm',
                                    onChanged: (v) => panelLengthM = v,
                                  ),
                                  numberField(
                                    label: 'Panel width',
                                    value: panelWidthM,
                                    suffix: 'm',
                                    onChanged: (v) => panelWidthM = v,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                value: includeSideEdgeJoints,
                                onChanged:
                                    saving
                                        ? null
                                        : (v) => setState(
                                          () =>
                                              includeSideEdgeJoints =
                                                  v ?? false,
                                        ),
                                title: const Text(
                                  'Include the two long side-edge joints as contraction joints',
                                ),
                              ),
                              Text(
                                'Auto basis: internal grid lines are contraction joints; the two pavement ends are expansion joints.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  numberField(
                                    label: 'Contraction joints',
                                    value: manualContractionJointM,
                                    suffix: 'm',
                                    width: 150,
                                    onChanged:
                                        (v) => manualContractionJointM = v,
                                  ),
                                  numberField(
                                    label: 'Expansion joints',
                                    value: manualExpansionJointM,
                                    suffix: 'm',
                                    width: 150,
                                    onChanged: (v) => manualExpansionJointM = v,
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    outputCard(contractionJoint),
                    outputCard(expansionJoint),
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Joint reinforcement / accessories',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                numberField(
                                  label: 'Dowel dia.',
                                  value: dowelDiameterMm,
                                  suffix: 'mm',
                                  onChanged: (v) => dowelDiameterMm = v,
                                ),
                                numberField(
                                  label: 'Dowel length',
                                  value: dowelLengthMm,
                                  suffix: 'mm',
                                  onChanged: (v) => dowelLengthMm = v,
                                ),
                                numberField(
                                  label: 'Dowel spacing',
                                  value: dowelSpacingMm,
                                  suffix: 'mm',
                                  width: 145,
                                  onChanged: (v) => dowelSpacingMm = v,
                                ),
                                numberField(
                                  label: 'Chair dia.',
                                  value: chairDiameterMm,
                                  suffix: 'mm',
                                  onChanged: (v) => chairDiameterMm = v,
                                ),
                                numberField(
                                  label: 'Chair spacing',
                                  value: chairSpacingMm,
                                  suffix: 'mm',
                                  width: 145,
                                  onChanged: (v) => chairSpacingMm = v,
                                ),
                                numberField(
                                  label: 'Cross bar dia.',
                                  value: crossBarDiameterMm,
                                  suffix: 'mm',
                                  width: 145,
                                  onChanged: (v) => crossBarDiameterMm = v,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'The supplied detail identifies 32 mm dowels, 800 mm dowel length, R12 chairs and R12 cross bars. Dowel/chair spacing is not shown, so enter the project spacing before enabling those quantities.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              value: crossBarFollowsJointLength,
                              onChanged:
                                  saving
                                      ? null
                                      : (v) => setState(
                                        () => crossBarFollowsJointLength = v,
                                      ),
                              title: const Text(
                                'Cross bar quantity follows total joint length',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    outputCard(
                      dowelBars,
                      subtitle:
                          dowelSpacingMm > 0
                              ? 'Ø${dowelDiameterMm.toStringAsFixed(0)} × ${dowelLengthMm.toStringAsFixed(0)} mm @ ${dowelSpacingMm.toStringAsFixed(0)} mm c/c'
                              : 'Enter dowel spacing to calculate quantity',
                    ),
                    outputCard(
                      chairBars,
                      subtitle:
                          chairSpacingMm > 0
                              ? 'R${chairDiameterMm.toStringAsFixed(0)} @ ${chairSpacingMm.toStringAsFixed(0)} mm c/c'
                              : 'Enter chair spacing to calculate quantity',
                    ),
                    outputCard(
                      crossBars,
                      subtitle:
                          'R${crossBarDiameterMm.toStringAsFixed(0)} cross bars',
                    ),
                  ],
                ),
              ],
            );

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text('Pavement take-off'),
              content: SizedBox(
                width: 780,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Measured pavement: ${validPolygons.length} zone${validPolygons.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 18,
                        runSpacing: 4,
                        children: [
                          Text('Gross: ${grossAreaM2.toStringAsFixed(3)} m²'),
                          Text(
                            'Deductions: ${totalDeductionM2.toStringAsFixed(3)} m²',
                          ),
                          Text(
                            'Net: ${areaM2.toStringAsFixed(3)} m²',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                      if (validDeductionPolygons.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Wrap(
                            spacing: 14,
                            runSpacing: 4,
                            children: [
                              for (var i = 0; i < deductionAreasM2.length; i++)
                                Text(
                                  '${validDeductionLabels[i]}: -${deductionAreasM2[i].toStringAsFixed(3)} m²',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed:
                              saving || restoringLastCodes
                                  ? null
                                  : () => restoreLastCodes(context, setState),
                          icon:
                              restoringLastCodes
                                  ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(Icons.restore_rounded),
                          label: Text(
                            restoringLastCodes
                                ? 'Restoring codes...'
                                : 'Restore last codes',
                          ),
                        ),
                      ),
                      if (restoreStatus != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          restoreStatus!,
                          style: const TextStyle(color: Color(0xFF15803D)),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: pavementType,
                              decoration: const InputDecoration(
                                labelText: 'Pavement type',
                              ),
                              items:
                                  const [
                                        'Pavement block',
                                        'Rigid concrete pavement',
                                      ]
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(e),
                                        ),
                                      )
                                      .toList(),
                              onChanged:
                                  saving || restoringLastCodes
                                      ? null
                                      : (v) => setState(() {
                                        pavementType = v!;
                                        layers = makeLayers(v);
                                        error = null;
                                      }),
                            ),
                          ),
                          if (pavementType == 'Pavement block') ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: blockSize,
                                decoration: const InputDecoration(
                                  labelText: 'Block size',
                                ),
                                items:
                                    const [
                                          '200 x 100 x 80 mm',
                                          '200 x 100 x 60 mm',
                                        ]
                                        .map(
                                          (e) => DropdownMenuItem(
                                            value: e,
                                            child: Text(e),
                                          ),
                                        )
                                        .toList(),
                                onChanged:
                                    saving
                                        ? null
                                        : (v) => setState(() => blockSize = v!),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Earthworks',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      outputCard(siteClearance),
                      outputCard(topsoil),
                      Padding(
                        padding: const EdgeInsets.only(left: 48, bottom: 8),
                        child: SizedBox(
                          width: 180,
                          child: TextFormField(
                            initialValue: '150',
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Topsoil depth (mm)',
                              isDense: true,
                            ),
                            onChanged:
                                (v) => setState(
                                  () => topsoilMm = double.tryParse(v) ?? 0,
                                ),
                          ),
                        ),
                      ),
                      outputCard(commonExc),
                      Padding(
                        padding: const EdgeInsets.only(left: 48, bottom: 12),
                        child: Row(
                          children: [
                            Switch(
                              value: excavationAuto,
                              onChanged:
                                  saving
                                      ? null
                                      : (v) =>
                                          setState(() => excavationAuto = v),
                            ),
                            Expanded(
                              child: Text(
                                excavationAuto
                                    ? 'Excavation depth: AUTO = ${totalConstructionMm().toStringAsFixed(0)} mm'
                                    : 'Manual excavation depth',
                              ),
                            ),
                            if (!excavationAuto) ...[
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 110,
                                child: TextFormField(
                                  initialValue: excavationMm.toStringAsFixed(0),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'mm',
                                    isDense: true,
                                  ),
                                  onChanged:
                                      (v) => setState(
                                        () =>
                                            excavationMm =
                                                double.tryParse(v) ?? 0,
                                      ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Text(
                        'Pavement layers',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      for (final o in layers)
                        outputCard(o, thickness: o.unit == 'm3'),
                      if (pavementType == 'Pavement block')
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Procurement guide: ${(areaM2 * 50).ceil()} blocks nominal (50 No./m²), before wastage.',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      if (pavementType == 'Rigid concrete pavement')
                        rigidJointSection(),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving ? null : () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed:
                      saving || restoringLastCodes
                          ? null
                          : () async {
                            final rigidOutputs =
                                pavementType == 'Rigid concrete pavement'
                                    ? [
                                      contractionJoint,
                                      expansionJoint,
                                      dowelBars,
                                      chairBars,
                                      crossBars,
                                    ]
                                    : <_PavementOutput>[];
                            final all =
                                [
                                  siteClearance,
                                  topsoil,
                                  commonExc,
                                  ...layers,
                                  ...rigidOutputs,
                                ].where((o) => o.included).toList();

                            if (all.any((o) => o.boq == null)) {
                              setState(
                                () =>
                                    error =
                                        'Pick a BOQ item for every included item.',
                              );
                              return;
                            }
                            if (all.any(
                              (o) =>
                                  o.unit == 'm3' &&
                                  o.type != 'topsoilExcavation' &&
                                  o.type != 'commonExcavation' &&
                                  o.thicknessMm <= 0,
                            )) {
                              setState(
                                () =>
                                    error =
                                        'Layer thickness must be greater than zero.',
                              );
                              return;
                            }
                            if (pavementType == 'Rigid concrete pavement' &&
                                jointAuto &&
                                (panelLengthM <= 0 || panelWidthM <= 0)) {
                              setState(
                                () =>
                                    error =
                                        'Panel/grid spacing must be greater than zero.',
                              );
                              return;
                            }
                            if (dowelBars.included && dowelSpacingMm <= 0) {
                              setState(
                                () =>
                                    error =
                                        'Enter dowel spacing before including dowel bars.',
                              );
                              return;
                            }
                            if (chairBars.included && chairSpacingMm <= 0) {
                              setState(
                                () =>
                                    error =
                                        'Enter chair spacing before including chair bars.',
                              );
                              return;
                            }

                            setState(() {
                              saving = true;
                              error = null;
                            });
                            try {
                              final groupId = measurementsRef.doc().id;
                              final batch = FirebaseFirestore.instance.batch();
                              for (
                                var zoneIndex = 0;
                                zoneIndex < validPolygons.length;
                                zoneIndex++
                              ) {
                                final polygon = validPolygons[zoneIndex];
                                final zoneGrossAreaM2 = zoneAreasM2[zoneIndex];
                                final zoneDeductionAreaM2 =
                                    zoneDeductionM2[zoneIndex];
                                final zoneAreaM2 = zoneNetAreasM2[zoneIndex];
                                final zoneExtent = zoneExtents[zoneIndex];
                                final poly =
                                    polygon
                                        .map((p) => {'x': p.dx, 'y': p.dy})
                                        .toList();

                                for (final o in all) {
                                  final b = o.boq!;
                                  final isRigid =
                                      pavementType == 'Rigid concrete pavement';
                                  String title = o.title;
                                  if (o.type == 'pavingBlocks') {
                                    title = '$blockSize pavement blocks';
                                  } else if (o.type == 'dowelBars') {
                                    title =
                                        'Ø${dowelDiameterMm.toStringAsFixed(0)} mm dowel bars, ${dowelLengthMm.toStringAsFixed(0)} mm long';
                                  } else if (o.type == 'chairBars') {
                                    title =
                                        'R${chairDiameterMm.toStringAsFixed(0)} chair bars';
                                  } else if (o.type == 'crossBars') {
                                    title =
                                        'R${crossBarDiameterMm.toStringAsFixed(0)} cross bars';
                                  }

                                  final zoneQty = qtyForZone(o, zoneIndex);
                                  batch.set(
                                    measurementsRef.doc(
                                      '$groupId-$zoneIndex-${o.type.toLowerCase()}',
                                    ),
                                    {
                                      'projectId': projectId,
                                      'buildingId': buildingId,
                                      'drawingId': drawingId,
                                      'measureType': 'pavement',
                                      'type': o.type,
                                      'itemType': o.type,
                                      'title': title,
                                      'label': title,
                                      'pavementGroupId': groupId,
                                      'areaGroupId': '$groupId-area-$zoneIndex',
                                      'polygon': poly,
                                      'polygonIndex': zoneIndex,
                                      'polygonCount': validPolygons.length,
                                      'polygonAreaM2': zoneGrossAreaM2,
                                      'polygonGrossAreaM2': zoneGrossAreaM2,
                                      'polygonDeductionAreaM2':
                                          zoneDeductionAreaM2,
                                      'polygonNetAreaM2': zoneAreaM2,
                                      'combinedAreaM2': areaM2,
                                      'grossAreaM2': grossAreaM2,
                                      'totalDeductionAreaM2': totalDeductionM2,
                                      'netAreaM2': areaM2,
                                      // Firestore does not allow an array to contain
                                      // another array directly. Wrap each deduction's
                                      // point array in a map so its geometry remains
                                      // available without producing nested arrays.
                                      'deductionPolygons': [
                                        for (
                                          var deductionIndex = 0;
                                          deductionIndex <
                                              validDeductionPolygons.length;
                                          deductionIndex++
                                        )
                                          {
                                            'points':
                                                validDeductionPolygons[deductionIndex]
                                                    .map(
                                                      (p) => {
                                                        'x': p.dx,
                                                        'y': p.dy,
                                                      },
                                                    )
                                                    .toList(),
                                            'label':
                                                validDeductionLabels[deductionIndex],
                                            'areaM2':
                                                deductionAreasM2[deductionIndex],
                                          },
                                      ],
                                      'deductionLabels': validDeductionLabels,
                                      'deductionAreasM2': deductionAreasM2,
                                      'pavementType': pavementType,
                                      'blockSize':
                                          pavementType == 'Pavement block'
                                              ? blockSize
                                              : null,
                                      'thicknessMm':
                                          o.type == 'topsoilExcavation'
                                              ? topsoilMm
                                              : (o.type == 'commonExcavation'
                                                  ? (excavationAuto
                                                      ? totalConstructionMm()
                                                      : excavationMm)
                                                  : o.thicknessMm),
                                      'excavationDepthMode':
                                          excavationAuto ? 'auto' : 'manual',
                                      'quantity': zoneQty,
                                      'value': zoneQty,
                                      'combinedQuantity': qty(o),
                                      'unit': o.unit,
                                      'boqUnit': o.unit,
                                      'boqItemId': b.id,
                                      'boqCode': b.code,
                                      'resolvedBoqCode': b.code,
                                      'boqDescription': b.description,
                                      if (isRigid) ...{
                                        'pavementLengthM': zoneExtent.lengthM,
                                        'pavementWidthM': zoneExtent.widthM,
                                        'jointCalculationMode':
                                            jointAuto ? 'auto' : 'manual',
                                        'panelLengthM': panelLengthM,
                                        'panelWidthM': panelWidthM,
                                        'includeSideEdgeJoints':
                                            includeSideEdgeJoints,
                                        'zoneContractionJointM': qtyForZone(
                                          contractionJoint,
                                          zoneIndex,
                                        ),
                                        'zoneExpansionJointM': qtyForZone(
                                          expansionJoint,
                                          zoneIndex,
                                        ),
                                        'contractionJointM':
                                            contractionJointM(),
                                        'expansionJointM': expansionJointM(),
                                        'totalJointM': totalJointM(),
                                        'dowelDiameterMm': dowelDiameterMm,
                                        'dowelLengthMm': dowelLengthMm,
                                        'dowelSpacingMm': dowelSpacingMm,
                                        'chairDiameterMm': chairDiameterMm,
                                        'chairSpacingMm': chairSpacingMm,
                                        'crossBarDiameterMm':
                                            crossBarDiameterMm,
                                        'crossBarFollowsJointLength':
                                            crossBarFollowsJointLength,
                                      },
                                      'color': currentColor.value,
                                      'createdAt': FieldValue.serverTimestamp(),
                                      'updatedAt': FieldValue.serverTimestamp(),
                                    },
                                  );
                                }
                              }
                              await batch.commit();
                              if (context.mounted) Navigator.pop(context, true);
                            } catch (e) {
                              setState(() {
                                saving = false;
                                error = 'Could not save: $e';
                              });
                            }
                          },
                  icon:
                      saving
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.save_outlined),
                  label: const Text('Save pavement'),
                ),
              ],
            );
          },
        ),
  );
  return saved == true;
}
