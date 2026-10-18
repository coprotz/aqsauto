import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FoundationWallCompositeDetailsDialog extends StatelessWidget {
  final String wallId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> initialDocs;
  final CollectionReference<Map<String, dynamic>> measurementsRef;
  final String projectId;
  final String buildingId;
  final String drawingId;
  final Map<String, dynamic> drawingData;
  final String? activeSegmentDocId;

  const FoundationWallCompositeDetailsDialog({
    super.key,
    required this.wallId,
    required this.initialDocs,
    required this.measurementsRef,
    required this.projectId,
    required this.buildingId,
    required this.drawingId,
    required this.drawingData,
    this.activeSegmentDocId,
  });

  double _asDouble(dynamic v) =>
      (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
  String _asString(dynamic v) => (v ?? '').toString();

  @override
  Widget build(BuildContext context) {
    // summarize by "type" (excavation/backfill/disposal/blinding/footingConcrete/foundationWall)
    final Map<String, Map<String, dynamic>> rows = {};

    for (final d in initialDocs) {
      final m = d.data();
      final type = _asString(m['type']).trim();
      final unit = _asString(m['unit']).trim();
      final val = _asDouble(m['value']);
      final boq = _asString(m['boqCode']).trim();

      rows[type] = {'type': type, 'unit': unit, 'value': val, 'boq': boq};
    }

    // length label if available
    double lengthM = 0.0;
    for (final d in initialDocs) {
      final m = d.data();
      final x =
          m['baseLengthM'] ?? m['lengthM'] ?? m['wallLengthM'] ?? m['value'];
      final v = _asDouble(x);
      if (v > 0) {
        lengthM = v;
        break;
      }
    }

    Future<void> deleteGroup() async {
      try {
        final batch = FirebaseFirestore.instance.batch();
        for (final d in initialDocs) {
          batch.delete(d.reference);
        }
        await batch.commit();
        Get.back(); // close dialog
        Get.snackbar('Deleted', 'Foundation wall group deleted.');
      } catch (e) {
        Get.snackbar(
          'Delete failed',
          '$e',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }

    return AlertDialog(
      title: const Text('Foundation wall'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Wall ID: $wallId'),
              const SizedBox(height: 6),
              if (lengthM > 0) Text('Length: ${lengthM.toStringAsFixed(3)} m'),
              const SizedBox(height: 12),

              const Text(
                'Items',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),

              DataTable(
                columns: const [
                  DataColumn(label: Text('Type')),
                  DataColumn(label: Text('Value')),
                  DataColumn(label: Text('Unit')),
                  DataColumn(label: Text('BOQ')),
                ],
                rows:
                    rows.values.map((r) {
                      final type = (r['type'] ?? '').toString();
                      final unit = (r['unit'] ?? '').toString();
                      final val = (r['value'] as double?) ?? 0.0;
                      final boq = (r['boq'] ?? '').toString();

                      return DataRow(
                        cells: [
                          DataCell(Text(type)),
                          DataCell(Text(val.toStringAsFixed(3))),
                          DataCell(Text(unit)),
                          DataCell(Text(boq)),
                        ],
                      );
                    }).toList(),
              ),

              const SizedBox(height: 10),
              Text(
                'Docs: ${initialDocs.length}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('Close')),
        OutlinedButton.icon(
          onPressed: deleteGroup,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete group'),
        ),
      ],
    );
  }
}
