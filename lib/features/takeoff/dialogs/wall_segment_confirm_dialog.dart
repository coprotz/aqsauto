import 'package:flutter/material.dart';
import 'package:get/get.dart';

enum WallSegmentAction { cancel, addContinue, finishSave }

class WallSegmentDecision {
  final WallSegmentAction action;
  final double? heightM; // edited height from dialog
  const WallSegmentDecision({required this.action, this.heightM});
}

class WallSegmentConfirmDialog extends StatefulWidget {
  const WallSegmentConfirmDialog({
    super.key,
    required this.lengthM,
    required this.heightM,
    required this.totalSoFarM,
  });

  final double lengthM;
  final double heightM;
  final double totalSoFarM;

  @override
  State<WallSegmentConfirmDialog> createState() =>
      _WallSegmentConfirmDialogState();
}

class _WallSegmentConfirmDialogState extends State<WallSegmentConfirmDialog> {
  late final TextEditingController _hCtrl;

  @override
  void initState() {
    super.initState();
    _hCtrl = TextEditingController(text: widget.heightM.toStringAsFixed(3));
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    super.dispose();
  }

  double? _parseH() {
    final v = double.tryParse(_hCtrl.text.trim());
    if (v == null || v <= 0) return null;
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final newTotal = widget.totalSoFarM + widget.lengthM;

    return AlertDialog(
      title: const Text('Confirm wall segment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Segment length: ${widget.lengthM.toStringAsFixed(3)} m'),
          const SizedBox(height: 6),
          Text('Total so far (after add): ${newTotal.toStringAsFixed(3)} m'),
          const SizedBox(height: 12),
          const Text(
            'Wall height (m):',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _hCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tip: Use Continue for U-shape walls.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              () => Navigator.pop(
                context,
                const WallSegmentDecision(action: WallSegmentAction.cancel),
              ),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          onPressed: () {
            final h = _parseH();
            if (h == null) {
              Get.snackbar('Invalid', 'Enter valid height > 0');
              return;
            }
            Navigator.pop(
              context,
              WallSegmentDecision(
                action: WallSegmentAction.addContinue,
                heightM: h,
              ),
            );
          },
          child: const Text('Continue'),
        ),
        FilledButton(
          onPressed: () {
            final h = _parseH();
            if (h == null) {
              Get.snackbar('Invalid', 'Enter valid height > 0');
              return;
            }
            Navigator.pop(
              context,
              WallSegmentDecision(
                action: WallSegmentAction.finishSave,
                heightM: h,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
