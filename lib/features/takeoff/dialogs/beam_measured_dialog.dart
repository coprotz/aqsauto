import 'package:aqs/features/takeoff/models/beam_segment.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BeamMeasureDialog extends StatelessWidget {
  final String beamName;
  final double lengthM;
  final double concM3;
  final double fwM2;
  final RxBool chainFromLastP2;
  final BeamGroupSummary currentSummary;

  const BeamMeasureDialog({
    super.key,
    required this.beamName,
    required this.lengthM,
    required this.concM3,
    required this.fwM2,
    required this.chainFromLastP2,
    required this.currentSummary,
  });

  String f(double v) => v.toStringAsFixed(3);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Beam $beamName"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("This beam:"),
            const SizedBox(height: 6),
            Text("• Length: ${f(lengthM)} m"),
            Text("• Concrete: ${f(concM3)} m³"),
            Text("• Formwork: ${f(fwM2)} m²"),
            const Divider(height: 22),
            Text("Running total for $beamName (same BOQ codes):"),
            const SizedBox(height: 6),
            Text("• Count: ${currentSummary.count}"),
            Text("• Total length: ${f(currentSummary.totalLengthM)} m"),
            Text("• Total concrete: ${f(currentSummary.totalConcreteM3)} m³"),
            Text("• Total formwork: ${f(currentSummary.totalFormworkM2)} m²"),
            const SizedBox(height: 14),
            Obx(
              () => CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: chainFromLastP2.value,
                onChanged: (v) => chainFromLastP2.value = (v ?? false),
                title: const Text("Continue from last P2 (chain)"),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: BeamAction.cancel),
          child: const Text("Cancel"),
        ),
        FilledButton.tonal(
          onPressed: () => Get.back(result: BeamAction.continue_),
          child: const Text("Continue"),
        ),
        FilledButton(
          onPressed: () => Get.back(result: BeamAction.save),
          child: const Text("Save"),
        ),
        FilledButton(
          onPressed: () => Get.back(result: BeamAction.saveStop),
          child: const Text("Save & Stop"),
        ),
      ],
    );
  }
}

class BeamTotalsDialog extends StatelessWidget {
  final BeamGroupSummary sum;
  const BeamTotalsDialog({super.key, required this.sum});

  String f(double v) => v.toStringAsFixed(3);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Totals: ${sum.beamName}"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Beams count: ${sum.count}"),
          const SizedBox(height: 8),
          Text("Total length: ${f(sum.totalLengthM)} m"),
          Text("Total concrete: ${f(sum.totalConcreteM3)} m³"),
          Text("Total formwork: ${f(sum.totalFormworkM2)} m²"),
          const SizedBox(height: 12),
          Text("Concrete BOQ: ${sum.concreteBoqCode}"),
          Text("Side Formwork BOQ: ${sum.sideFormworkBoqCode}"),
          Text("Soffit Formwork BOQ: ${sum.soffitFormworkBoqCode}"),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text("Close")),
      ],
    );
  }
}
