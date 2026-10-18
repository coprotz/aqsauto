import 'package:aqs/features/boq/dialogs/boq_picker_dialog.dart';
import 'package:aqs/features/takeoff/dialogs/edit_part_dialog.dart';
import 'package:aqs/features/takeoff/models/part_option.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Widget sectionTile({
  required String title,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  VoidCallback? onAdd,
}) {
  return Card(
    child: ExpansionTile(
      initiallyExpanded: true,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onAdd != null)
            IconButton(
              tooltip: 'Add part',
              onPressed: onAdd,
              icon: const Icon(Icons.add_circle_outline),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more),
        ],
      ),
      children: [
        if (docs.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: Text('No items.'))
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _measurementRow(docs[i]),
          ),
      ],
    ),
  );
}

Future<void> _deletePart(
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
) async {
  final ok =
      await Get.dialog<bool>(
        AlertDialog(
          title: const Text('Delete measurement?'),
          content: const Text('This will permanently delete this item.'),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Get.back(result: true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;

  if (!ok) return;

  try {
    await doc.reference.delete();
    Get.snackbar('Deleted', 'Measurement removed');
  } catch (e) {
    Get.snackbar('Error', '$e');
  }
}

Future<void> addPartDialog({
  required CollectionReference<Map<String, dynamic>> measurementsRef,
  required String footingGroupId,
  required String projectId,
  required String buildingId,
  required String drawingId,
  required FootingSection defaultSection,
  required QueryDocumentSnapshot<Map<String, dynamic>>? sampleDoc,
}) async {
  // allowed types per section
  final List<PartOption> options = switch (defaultSection) {
    FootingSection.footing => const [
      PartOption(
        type: 'footingConcrete',
        unit: 'm3',
        label: 'Footing - Concrete',
      ),
      PartOption(
        type: 'footingFormwork',
        unit: 'm2',
        label: 'Footing - Formwork',
      ),
      PartOption(type: 'rebarFooting', unit: 'kg', label: 'Footing - Rebar'),
    ],
    FootingSection.column => const [
      PartOption(
        type: 'columnConcrete',
        unit: 'm3',
        label: 'Column - Concrete',
      ),
      PartOption(
        type: 'columnFormworkSides',
        unit: 'm2',
        label: 'Column - Formwork',
      ),
      PartOption(
        type: 'columnMainRebar',
        unit: 'kg',
        label: 'Column - Main Rebar',
      ),
      PartOption(
        type: 'columnStirrups',
        unit: 'kg',
        label: 'Column - Stirrups',
      ),
    ],
    FootingSection.earthworks => const [
      PartOption(
        type: 'excavation',
        unit: 'm3',
        label: 'Earthworks - Excavation',
      ),
      PartOption(type: 'backfill', unit: 'm3', label: 'Earthworks - Backfill'),
      PartOption(type: 'disposal', unit: 'm3', label: 'Earthworks - Disposal'),
      PartOption(type: 'blinding', unit: 'm2', label: 'Blinding - Area'),
    ],
    _ => const [],
  };

  if (options.isEmpty) return;

  PartOption selected = options.first;

  final valueCtrl = TextEditingController(text: '0');
  final boqCodeCtrl = TextEditingController();
  final boqDescCtrl = TextEditingController();

  final ok =
      await Get.dialog<bool>(
        StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('Add measurement part'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<PartOption>(
                      value: selected,
                      items:
                          options.map((o) {
                            return DropdownMenuItem<PartOption>(
                              value: o,
                              child: Text('${o.label} (${o.unit})'),
                            );
                          }).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => selected = v);
                      },
                      decoration: const InputDecoration(labelText: 'Part'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: valueCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Value'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: boqCodeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'BOQ code',
                            ),
                            readOnly: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // OutlinedButton(
                        //   onPressed: () async {
                        //     final picked = await pickBoqItemDialog(
                        //       projectId: projectId,
                        //       buildingId: buildingId,
                        //     );
                        //     if (picked != null) {
                        //       boqCodeCtrl.text = picked.code;
                        //       boqDescCtrl.text = picked.description;
                        //       setState(() {});
                        //     }
                        //   },
                        //   child: const Text('Pick'),
                        // ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: boqDescCtrl,
                      decoration: const InputDecoration(
                        labelText: 'BOQ description',
                      ),
                      readOnly: true,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Get.back(result: false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Get.back(result: true),
                  child: const Text('Add'),
                ),
              ],
            );
          },
        ),
      ) ??
      false;

  if (!ok) return;

  final val = double.tryParse(valueCtrl.text.trim());
  if (val == null) {
    Get.snackbar('Invalid', 'Value must be a number');
    return;
  }

  try {
    final sample = sampleDoc?.data() ?? {};
    await measurementsRef.add({
      'projectId': projectId,
      'buildingId': buildingId,
      'drawingId': drawingId,
      'measureType': 'compositeFooting',
      'type': selected.type,
      'unit': selected.unit,
      'value': val,
      'label': selected.label,
      'boqCode': boqCodeCtrl.text.trim(),
      'boqDescription': boqDescCtrl.text.trim(),
      'footingGroupId': footingGroupId,

      // copy visuals/geometry so it remains linked to the same polygon
      'polygon': sample['polygon'],
      'color': sample['color'],

      'createdAt': FieldValue.serverTimestamp(),
    });

    Get.snackbar('Added', 'New part added');
  } catch (e) {
    Get.snackbar('Error', '$e');
  }
}

Widget _measurementRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final d = doc.data();

  String s(dynamic v) => (v ?? '').toString().trim();
  double numd(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0.0;

  String unitPretty(String u) => u == 'm2' ? 'm²' : (u == 'm3' ? 'm³' : u);

  final label = s(d['label']).isEmpty ? s(d['type']) : s(d['label']);
  final boq = s(d['boqCode']);
  final desc = s(d['boqDescription']);
  final unit = unitPretty(s(d['unit']));
  final val = numd(d['value']);

  return ListTile(
    dense: true,
    title: Text(
      label,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
    ),
    subtitle: Text(
      '$boq ${desc}'.trim(),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              val.toStringAsFixed(3),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(unit, style: const TextStyle(fontSize: 11)),
          ],
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              await editPartDialog(doc);
            } else if (v == 'delete') {
              await _deletePart(doc);
            }
          },
          itemBuilder:
              (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
        ),
      ],
    ),
  );
}
