import 'package:aqs/features/boq/dialogs/boq_picker_dialog.dart';
import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/takeoff/controllers/image_takeoff_controller.dart';
import 'package:flutter/material.dart';

class BoqPickField extends StatelessWidget {
  final TextEditingController codeCtrl;
  final TextEditingController descCtrl;
  final String label;
  final Future<BoqPick?> Function() onPick;
  final bool enabled;

  const BoqPickField({
    super.key,
    required this.codeCtrl,
    required this.descCtrl,
    required this.label,
    required this.onPick,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: codeCtrl,
                readOnly: true,
                enabled: enabled,
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed:
                  !enabled
                      ? null
                      : () async {
                        final picked = await onPick();
                        if (picked == null) return;
                        codeCtrl.text = picked.code.trim();
                        descCtrl.text = picked.description.trim();
                      },
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Pick'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: descCtrl,
          readOnly: true,
          enabled: enabled,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Description',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}
