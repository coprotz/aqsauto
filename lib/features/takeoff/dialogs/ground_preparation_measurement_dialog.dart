import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class _GroundPreparationOutput {
  _GroundPreparationOutput(this.type, this.title);

  final String type;
  final String title;
  bool included = true;
  BoqPick? boq;
}

Future<bool> showGroundPreparationMeasurementDialog({
  required List<List<Offset>> polygons,
  required Map<String, dynamic> drawingData,
  required String projectId,
  required String buildingId,
  required String drawingId,
  required Color currentColor,
  required CollectionReference<Map<String, dynamic>> measurementsRef,
  required Future<BoqPick?> Function(BuildContext context) pickBoq,
}) async {
  final pixelsPerUnit =
      drawingData['pixelsPerUnit'] is num
          ? (drawingData['pixelsPerUnit'] as num).toDouble()
          : double.tryParse('${drawingData['pixelsPerUnit'] ?? ''}') ?? 0;
  if (drawingData['calibrated'] != true || pixelsPerUnit <= 0) {
    Get.snackbar('Calibration required', 'Calibrate the drawing first.');
    return false;
  }

  double polygonArea(List<Offset> points) {
    var sum = 0.0;
    for (var i = 0; i < points.length; i++) {
      final next = points[(i + 1) % points.length];
      sum += points[i].dx * next.dy - next.dx * points[i].dy;
    }
    return sum.abs() / 2 / (pixelsPerUnit * pixelsPerUnit);
  }

  final areas = polygons.map(polygonArea).toList();
  final combinedArea = areas.fold<double>(0, (sum, value) => sum + value);
  final outputs = <_GroundPreparationOutput>[
    _GroundPreparationOutput('groundPreparationHardcore', 'Hardcore'),
    _GroundPreparationOutput('groundPreparationDpm', 'DPM'),
    _GroundPreparationOutput('groundPreparationMakeUp', 'Make up level'),
    _GroundPreparationOutput(
      'groundPreparationAntiTermite',
      'Anti-termite treatment',
    ),
  ];
  String? error;
  var saving = false;

  final saved = await showDialog<bool>(
    context: Get.context!,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Ground preparation take-off'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${polygons.length} area${polygons.length == 1 ? '' : 's'} selected · ${combinedArea.toStringAsFixed(3)} m² combined',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                for (final output in outputs)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(output.title),
                            subtitle: Text(
                              '${combinedArea.toStringAsFixed(3)} m²',
                            ),
                            value: output.included,
                            onChanged: saving
                                ? null
                                : (value) => setState(() {
                                    output.included = value;
                                    error = null;
                                  }),
                          ),
                          if (output.included)
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    output.boq == null
                                        ? 'No BOQ item selected'
                                        : '${output.boq!.code} — ${output.boq!.description}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton.icon(
                                  onPressed: saving
                                      ? null
                                      : () async {
                                          final picked = await pickBoq(context);
                                          if (picked == null) return;
                                          setState(() {
                                            output.boq = picked;
                                            error = null;
                                          });
                                        },
                                  icon: const Icon(Icons.search_rounded),
                                  label: const Text('Pick BOQ'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: saving
                ? null
                : () async {
                    final included = outputs.where((item) => item.included).toList();
                    if (included.isEmpty) {
                      setState(() => error = 'Include at least one output.');
                      return;
                    }
                    if (included.any((item) => item.boq == null)) {
                      setState(() => error = 'Pick a BOQ item for every included output.');
                      return;
                    }
                    setState(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      final groupId = measurementsRef.doc().id;
                      final batch = FirebaseFirestore.instance.batch();
                      for (var polygonIndex = 0;
                          polygonIndex < polygons.length;
                          polygonIndex++) {
                        final polygon = polygons[polygonIndex];
                        final area = areas[polygonIndex];
                        final polygonData = polygon
                            .map((point) => {'x': point.dx, 'y': point.dy})
                            .toList();
                        for (final output in included) {
                          final boq = output.boq!;
                          final id =
                              '$groupId-$polygonIndex-${output.type.toLowerCase()}';
                          batch.set(measurementsRef.doc(id), {
                            'projectId': projectId,
                            'buildingId': buildingId,
                            'drawingId': drawingId,
                            'measureType': 'groundPreparation',
                            'type': output.type,
                            'itemType': output.type,
                            'title': output.title,
                            'label': output.title,
                            'groundPreparationGroupId': groupId,
                            'areaGroupId': '$groupId-area-$polygonIndex',
                            'polygon': polygonData,
                            'polygonIndex': polygonIndex,
                            'polygonCount': polygons.length,
                            'polygonAreaM2': area,
                            'combinedAreaM2': combinedArea,
                            'quantity': area,
                            'value': area,
                            'unit': 'm2',
                            'boqUnit': 'm2',
                            'boqItemId': boq.id,
                            'boqCode': boq.code,
                            'boqDescription': boq.description,
                            'color': currentColor.value,
                            'createdAt': FieldValue.serverTimestamp(),
                            'updatedAt': FieldValue.serverTimestamp(),
                          });
                        }
                      }
                      await batch.commit();
                      if (context.mounted) Navigator.pop(context, true);
                    } catch (exception) {
                      setState(() {
                        saving = false;
                        error = 'Could not save: $exception';
                      });
                    }
                  },
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Save all'),
          ),
        ],
      ),
    ),
  );
  return saved == true;
}
