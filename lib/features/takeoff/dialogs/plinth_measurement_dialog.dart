import 'dart:math' as math;

import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class _PlinthBoqSelection {
  const _PlinthBoqSelection({
    required this.title,
    required this.codeController,
    required this.descriptionController,
  });

  final String title;
  final TextEditingController codeController;
  final TextEditingController descriptionController;

  void dispose() {
    codeController.dispose();
    descriptionController.dispose();
  }
}

Future<bool> showPlinthMeasurementDialog({
  required List<Offset> polygon,
  required Map<String, dynamic> drawingData,
  required String projectId,
  required String buildingId,
  required String drawingId,
  required Color currentColor,
  required CollectionReference<Map<String, dynamic>> measurementsRef,
  required Future<BoqPick?> Function(BuildContext context) pickBoq,
}) async {
  if (polygon.length < 3) return false;

  final calibrated = drawingData['calibrated'] == true;
  final pxPerM =
      drawingData['pixelsPerUnit'] is num
          ? (drawingData['pixelsPerUnit'] as num).toDouble()
          : double.tryParse('${drawingData['pixelsPerUnit']}') ?? 0;
  if (!calibrated || pxPerM <= 0) {
    Get.snackbar(
      'Not calibrated',
      'Calibrate the drawing before measuring a plinth.',
      snackPosition: SnackPosition.BOTTOM,
    );
    return false;
  }

  double polygonAreaPx2(List<Offset> points) {
    var sum = 0.0;
    for (var index = 0; index < points.length; index++) {
      final current = points[index];
      final next = points[(index + 1) % points.length];
      sum += current.dx * next.dy - next.dx * current.dy;
    }
    return (sum / 2).abs();
  }

  double polygonPerimeterPx(List<Offset> points) {
    var total = 0.0;
    for (var index = 0; index < points.length; index++) {
      final current = points[index];
      final next = points[(index + 1) % points.length];
      total += math.sqrt(
        math.pow(next.dx - current.dx, 2) +
            math.pow(next.dy - current.dy, 2),
      );
    }
    return total;
  }

  final planAreaM2 = polygonAreaPx2(polygon) / (pxPerM * pxPerM);
  final perimeterM = polygonPerimeterPx(polygon) / pxPerM;
  final polygonData =
      polygon.map((point) => {'x': point.dx, 'y': point.dy}).toList();

  final depthController = TextEditingController(text: '0.45');
  final thicknessController = TextEditingController(text: '100');
  final buildingFactorController = TextEditingController(text: '1');
  final repetitionController = TextEditingController(text: '1');

  final plastering = _PlinthBoqSelection(
    title: 'Plinth plastering',
    codeController: TextEditingController(),
    descriptionController: TextEditingController(),
  );
  final bitumen = _PlinthBoqSelection(
    title: 'Bitumen painting',
    codeController: TextEditingController(),
    descriptionController: TextEditingController(),
  );
  final concreteBed = _PlinthBoqSelection(
    title: 'Concrete bed',
    codeController: TextEditingController(),
    descriptionController: TextEditingController(),
  );
  final concreteEdge = _PlinthBoqSelection(
    title: 'Concrete-bed edge',
    codeController: TextEditingController(),
    descriptionController: TextEditingController(),
  );
  final fabricMesh = _PlinthBoqSelection(
    title: 'Fabric mesh',
    codeController: TextEditingController(),
    descriptionController: TextEditingController(),
  );
  final selections = [
    plastering,
    bitumen,
    concreteBed,
    concreteEdge,
    fabricMesh,
  ];

  var includePlastering = true;
  var includeBitumen = true;
  var includeConcreteBed = true;
  var includeConcreteEdge = true;
  var includeFabricMesh = true;
  String? errorText;

  double positiveDouble(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;
  int positiveInt(TextEditingController controller) =>
      int.tryParse(controller.text.trim()) ?? 0;

  Widget metricCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AqsColors.primarySoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD9E5FF)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AqsColors.primary, size: 21),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AqsColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AqsColors.ink,
                      fontWeight: FontWeight.w900,
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

  Widget numberField({
    required TextEditingController controller,
    required String label,
    required String suffix,
    required VoidCallback onChanged,
    bool decimal = true,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => onChanged(),
    );
  }

  Widget outputRow({
    required String title,
    required String subtitle,
    required bool included,
    required ValueChanged<bool> onIncluded,
    required _PlinthBoqSelection selection,
    required BuildContext context,
    required StateSetter setState,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: included ? Colors.white : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                value: included,
                onChanged: (value) => onIncluded(value ?? false),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AqsColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed:
                    included
                        ? () async {
                          final picked = await pickBoq(context);
                          if (picked == null) return;
                          setState(() {
                            selection.codeController.text = picked.code.trim();
                            selection.descriptionController.text =
                                picked.description.trim();
                            errorText = null;
                          });
                        }
                        : null,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Pick BOQ'),
              ),
            ],
          ),
          if (included) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 145,
                  child: TextField(
                    controller: selection.codeController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'BOQ code',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: selection.descriptionController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'BOQ description',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  final accepted =
      await Get.dialog<bool>(
        StatefulBuilder(
          builder: (context, setState) {
            final depthM = positiveDouble(depthController);
            final thicknessMm = positiveDouble(thicknessController);
            final buildingFactor = positiveInt(buildingFactorController);
            final repetitions = positiveInt(repetitionController);
            final multiplier = buildingFactor * repetitions;
            final bedIsArea = thicknessMm <= 150;
            final plasteringArea = perimeterM * depthM * multiplier;
            final concreteQuantity =
                bedIsArea
                    ? planAreaM2 * multiplier
                    : planAreaM2 * (thicknessMm / 1000) * multiplier;
            final edgeLength = perimeterM * multiplier;
            final meshArea = planAreaM2 * multiplier;

            void rebuild() => setState(() => errorText = null);

            return Dialog(
              backgroundColor: const Color(0xFFF8FAFC),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920, maxHeight: 850),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AqsColors.primaryDark, AqsColors.primary],
                        ),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(26),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.foundation_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                          const SizedBox(width: 13),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Plinth measurement',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Configure finishes, concrete bed, edge and fabric mesh',
                                  style: TextStyle(color: Color(0xFFD6E4FF)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Get.back(result: false),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                metricCard(
                                  'Plan area',
                                  '${planAreaM2.toStringAsFixed(3)} m²',
                                  Icons.crop_square_rounded,
                                ),
                                const SizedBox(width: 10),
                                metricCard(
                                  'Perimeter',
                                  '${perimeterM.toStringAsFixed(3)} m',
                                  Icons.polyline_rounded,
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Dimensions and repetition',
                              style: TextStyle(
                                color: AqsColors.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: numberField(
                                    controller: depthController,
                                    label: 'Plinth depth',
                                    suffix: 'm',
                                    onChanged: rebuild,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: numberField(
                                    controller: thicknessController,
                                    label: 'Concrete-bed thickness',
                                    suffix: 'mm',
                                    onChanged: rebuild,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: numberField(
                                    controller: buildingFactorController,
                                    label: 'Buildings / blocks',
                                    suffix: '×',
                                    onChanged: rebuild,
                                    decimal: false,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: numberField(
                                    controller: repetitionController,
                                    label: 'Same polygon repeated',
                                    suffix: '×',
                                    onChanged: rebuild,
                                    decimal: false,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Total multiplier: ×$multiplier · Concrete bed is measured as '
                              '${bedIsArea ? 'area (m²)' : 'volume (m³)'}.',
                              style: const TextStyle(
                                color: AqsColors.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Outputs and BOQ mappings',
                              style: TextStyle(
                                color: AqsColors.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            outputRow(
                              title: 'Plinth plastering',
                              subtitle:
                                  '${plasteringArea.toStringAsFixed(3)} m²',
                              included: includePlastering,
                              onIncluded:
                                  (value) => setState(() {
                                    includePlastering = value;
                                    errorText = null;
                                  }),
                              selection: plastering,
                              context: context,
                              setState: setState,
                            ),
                            const SizedBox(height: 9),
                            outputRow(
                              title: 'Bitumen painting',
                              subtitle:
                                  '${plasteringArea.toStringAsFixed(3)} m²',
                              included: includeBitumen,
                              onIncluded:
                                  (value) => setState(() {
                                    includeBitumen = value;
                                    errorText = null;
                                  }),
                              selection: bitumen,
                              context: context,
                              setState: setState,
                            ),
                            const SizedBox(height: 9),
                            outputRow(
                              title:
                                  bedIsArea
                                      ? 'Concrete bed area'
                                      : 'Concrete bed volume',
                              subtitle:
                                  '${concreteQuantity.toStringAsFixed(3)} '
                                  '${bedIsArea ? 'm²' : 'm³'} · $thicknessMm mm',
                              included: includeConcreteBed,
                              onIncluded:
                                  (value) => setState(() {
                                    includeConcreteBed = value;
                                    errorText = null;
                                  }),
                              selection: concreteBed,
                              context: context,
                              setState: setState,
                            ),
                            const SizedBox(height: 9),
                            outputRow(
                              title: 'Concrete-bed edge',
                              subtitle: '${edgeLength.toStringAsFixed(3)} m',
                              included: includeConcreteEdge,
                              onIncluded:
                                  (value) => setState(() {
                                    includeConcreteEdge = value;
                                    errorText = null;
                                  }),
                              selection: concreteEdge,
                              context: context,
                              setState: setState,
                            ),
                            const SizedBox(height: 9),
                            outputRow(
                              title: 'Fabric mesh',
                              subtitle: '${meshArea.toStringAsFixed(3)} m²',
                              included: includeFabricMesh,
                              onIncluded:
                                  (value) => setState(() {
                                    includeFabricMesh = value;
                                    errorText = null;
                                  }),
                              selection: fabricMesh,
                              context: context,
                              setState: setState,
                            ),
                            if (errorText != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF1F0),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFFDA29B),
                                  ),
                                ),
                                child: Text(
                                  errorText!,
                                  style: const TextStyle(
                                    color: Color(0xFFB42318),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(color: AqsColors.border),
                        ),
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(26),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Get.back(result: false),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: () {
                              final included = <_PlinthBoqSelection>[
                                if (includePlastering) plastering,
                                if (includeBitumen) bitumen,
                                if (includeConcreteBed) concreteBed,
                                if (includeConcreteEdge) concreteEdge,
                                if (includeFabricMesh) fabricMesh,
                              ];
                              if (depthM <= 0) {
                                setState(
                                  () => errorText =
                                      'Enter a plinth depth greater than zero.',
                                );
                                return;
                              }
                              if (thicknessMm <= 0) {
                                setState(
                                  () => errorText =
                                      'Enter a concrete-bed thickness greater than zero.',
                                );
                                return;
                              }
                              if (buildingFactor <= 0 || repetitions <= 0) {
                                setState(
                                  () => errorText =
                                      'Buildings and repetitions must each be at least 1.',
                                );
                                return;
                              }
                              if (included.isEmpty) {
                                setState(
                                  () => errorText =
                                      'Include and map at least one Plinth output.',
                                );
                                return;
                              }
                              final missing = included
                                  .where(
                                    (item) => item.codeController.text
                                        .trim()
                                        .isEmpty,
                                  )
                                  .map((item) => item.title)
                                  .toList();
                              if (missing.isNotEmpty) {
                                setState(
                                  () => errorText =
                                      'Pick a BOQ item for: ${missing.join(', ')}.',
                                );
                                return;
                              }
                              Get.back(result: true);
                            },
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Save Plinth'),
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
      ) ??
      false;

  if (!accepted) {
    depthController.dispose();
    thicknessController.dispose();
    buildingFactorController.dispose();
    repetitionController.dispose();
    for (final selection in selections) {
      selection.dispose();
    }
    return false;
  }

  final depthM = positiveDouble(depthController);
  final thicknessMm = positiveDouble(thicknessController);
  final thicknessM = thicknessMm / 1000;
  final buildingFactor = positiveInt(buildingFactorController);
  final repetitions = positiveInt(repetitionController);
  final multiplier = buildingFactor * repetitions;
  final bedIsArea = thicknessMm <= 150;
  final plasteringAreaM2 = perimeterM * depthM * multiplier;
  final concreteBedQuantity =
      bedIsArea
          ? planAreaM2 * multiplier
          : planAreaM2 * thicknessM * multiplier;
  final concreteBedEdgeM = perimeterM * multiplier;
  final fabricMeshM2 = planAreaM2 * multiplier;
  final plinthGroupId = measurementsRef.doc().id;
  final now = FieldValue.serverTimestamp();

  Map<String, dynamic> common() => {
    'projectId': projectId,
    'buildingId': buildingId,
    'drawingId': drawingId,
    'measureType': 'plinth',
    'plinthGroupId': plinthGroupId,
    'areaGroupId': plinthGroupId,
    'polygon': polygonData,
    'color': currentColor.value,
    'sourcePlanAreaM2': planAreaM2,
    'sourcePerimeterM': perimeterM,
    'polygonAreaM2': planAreaM2,
    'polygonAreaM2_one': planAreaM2,
    'areaM2_one': planAreaM2,
    'perimeterM_one': perimeterM,
    'plinthDepthM': depthM,
    'concreteBedThicknessMm': thicknessMm,
    'concreteBedThicknessM': thicknessM,
    'buildingFactor': buildingFactor,
    'qtySamePolygon': repetitions,
    'multiplier': multiplier,
    'multiplierTotal': multiplier,
    'areaM2_total': planAreaM2 * multiplier,
    'perimeterM_total': perimeterM * multiplier,
    'plasteringAreaM2_total': plasteringAreaM2,
    'bitumenPaintingAreaM2_total': plasteringAreaM2,
    'concreteBedQuantityTotal': concreteBedQuantity,
    'concreteBedUnit': bedIsArea ? 'm2' : 'm3',
    'concreteBedEdgeM_total': concreteBedEdgeM,
    'fabricMeshM2_total': fabricMeshM2,
    'createdAt': now,
    'updatedAt': now,
  };

  var primaryOutputWritten = false;

  void addOutput(
    WriteBatch batch, {
    required String suffix,
    required String type,
    required String title,
    required double quantity,
    required String unit,
    required _PlinthBoqSelection selection,
  }) {
    final documentId =
        primaryOutputWritten ? '$plinthGroupId-$suffix' : plinthGroupId;
    primaryOutputWritten = true;
    batch.set(measurementsRef.doc(documentId), {
      ...common(),
      'type': type,
      'itemType': type,
      'title': title,
      'label': title,
      'quantity': quantity,
      'value': quantity,
      'unit': unit,
      'boqUnit': unit,
      'boqCode': selection.codeController.text.trim(),
      'boqDescription': selection.descriptionController.text.trim(),
    });
  }

  var progressOpen = false;
  try {
    progressOpen = true;
    Get.dialog<void>(
      const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 28, vertical: 22),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  SizedBox(width: 16),
                  Text(
                    'Saving Plinth measurement…',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      barrierDismissible: false,
    );
    await Future<void>.delayed(Duration.zero);

    final batch = FirebaseFirestore.instance.batch();
    if (includePlastering) {
      addOutput(
        batch,
        suffix: 'plastering',
        type: 'plinthPlastering',
        title: 'Plinth plastering',
        quantity: plasteringAreaM2,
        unit: 'm2',
        selection: plastering,
      );
    }
    if (includeBitumen) {
      addOutput(
        batch,
        suffix: 'bitumen',
        type: 'plinthBitumenPainting',
        title: 'Bitumen painting',
        quantity: plasteringAreaM2,
        unit: 'm2',
        selection: bitumen,
      );
    }
    if (includeConcreteBed) {
      addOutput(
        batch,
        suffix: bedIsArea ? 'concrete-bed-area' : 'concrete-bed-volume',
        type:
            bedIsArea
                ? 'plinthConcreteBedArea'
                : 'plinthConcreteBedVolume',
        title: bedIsArea ? 'Concrete bed area' : 'Concrete bed volume',
        quantity: concreteBedQuantity,
        unit: bedIsArea ? 'm2' : 'm3',
        selection: concreteBed,
      );
    }
    if (includeConcreteEdge) {
      addOutput(
        batch,
        suffix: 'concrete-bed-edge',
        type: 'plinthConcreteBedEdge',
        title: 'Concrete-bed edge',
        quantity: concreteBedEdgeM,
        unit: 'm',
        selection: concreteEdge,
      );
    }
    if (includeFabricMesh) {
      addOutput(
        batch,
        suffix: 'fabric-mesh',
        type: 'plinthFabricMesh',
        title: 'Fabric mesh',
        quantity: fabricMeshM2,
        unit: 'm2',
        selection: fabricMesh,
      );
    }
    await batch.commit();

    if (progressOpen && Get.isDialogOpen == true) {
      Get.back<void>();
      progressOpen = false;
    }
    Get.snackbar(
      'Saved',
      'Plinth measurement saved (×$multiplier).',
      snackPosition: SnackPosition.BOTTOM,
    );
    return true;
  } catch (error) {
    if (progressOpen && Get.isDialogOpen == true) {
      Get.back<void>();
      progressOpen = false;
    }
    Get.snackbar(
      'Save failed',
      'Could not save the Plinth measurement: $error',
      snackPosition: SnackPosition.BOTTOM,
    );
    return false;
  } finally {
    if (progressOpen && Get.isDialogOpen == true) {
      Get.back<void>();
    }
    depthController.dispose();
    thicknessController.dispose();
    buildingFactorController.dispose();
    repetitionController.dispose();
    for (final selection in selections) {
      selection.dispose();
    }
  }
}
