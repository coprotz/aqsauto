import 'package:aqs/features/boq/dialogs/boq_picker_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<void> editPartDialog(
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
) async {
  final d = doc.data();
  final valueCtrl = TextEditingController(text: '${d['value'] ?? ''}');
  final labelCtrl = TextEditingController(text: (d['label'] ?? '').toString());
  final boqCodeCtrl = TextEditingController(
    text: (d['boqCode'] ?? '').toString(),
  );
  final boqDescCtrl = TextEditingController(
    text: (d['boqDescription'] ?? '').toString(),
  );

  final ok =
      await Get.dialog<bool>(
        AlertDialog(
          title: const Text('Edit measurement'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(labelText: 'Label'),
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

                // BOQ pick button (use your BOQ picker)
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
                    //     final picked = await i(
                    //       projectId: d['projectId'],
                    //       buildingId: d['buildingId'],
                    //     );
                    //     if (picked != null) {
                    //       boqCodeCtrl.text = picked.code;
                    //       boqDescCtrl.text = picked.description;
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
              child: const Text('Save'),
            ),
          ],
        ),
      ) ??
      false;

  if (!ok) return;

  final newVal = double.tryParse(valueCtrl.text.trim());
  if (newVal == null) {
    Get.snackbar('Invalid', 'Value must be a number');
    return;
  }

  try {
    await doc.reference.update({
      'label': labelCtrl.text.trim(),
      'value': newVal,
      'boqCode': boqCodeCtrl.text.trim(),
      'boqDescription': boqDescCtrl.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    Get.snackbar('Updated', 'Measurement updated');
  } catch (e) {
    Get.snackbar('Error', '$e');
  }
}
