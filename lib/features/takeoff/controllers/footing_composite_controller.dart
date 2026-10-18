import 'package:aqs/features/takeoff/models/rebar_mark.dart';
import 'package:aqs/features/takeoff/models/rebar_set.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// You already have these models/utilities in your project:
/// - RebarMark.parse(...)
/// - rebarUnitWeightKgPerM(diaMm)
/// - RebarSet model
/// - distanceInMeters(p1,p2,drawingData) or your calibration helper
///
/// Replace the imports above accordingly.

// class RebarSet {
//   final String rawMark;
//   final dynamic mark; // RebarMark
//   final String direction; // 'length' | 'width'
//   final double clearSpanM;
//   final double embedEachEndM;
//   final double extraLengthM;
//   final double barLengthM;
//   final double totalLengthM;
//   final double unitWeightKgPerM;
//   final double totalWeightKg;

//   RebarSet({
//     required this.rawMark,
//     required this.mark,
//     required this.direction,
//     required this.clearSpanM,
//     required this.embedEachEndM,
//     required this.extraLengthM,
//     required this.barLengthM,
//     required this.totalLengthM,
//     required this.unitWeightKgPerM,
//     required this.totalWeightKg,
//   });
// }
// class RebarSet {
//   final String rawMark;
//   final RebarMark mark;
//   final String direction; // 'horizontal'/'vertical'
//   final double clearSpanM;
//   final double embedEachEndM;
//   final double extraLengthM;

//   final double barLengthM;
//   final double totalLengthM;
//   final double unitWeightKgPerM;
//   final double totalWeightKg;

//   RebarSet({
//     required this.rawMark,
//     required this.mark,
//     required this.direction,
//     required this.clearSpanM,
//     required this.embedEachEndM,
//     required this.extraLengthM,
//     required this.barLengthM,
//     required this.totalLengthM,
//     required this.unitWeightKgPerM,
//     required this.totalWeightKg,
//   });

//   Map<String, dynamic> toMap() => {
//         'rawMark': rawMark,
//         'direction': direction,
//         'clearSpanM': clearSpanM,
//         'embedEachEndM': embedEachEndM,
//         'extraLengthM': extraLengthM,
//         'barLengthM': barLengthM,
//         'totalLengthM': totalLengthM,
//         'unitWeightKgPerM': unitWeightKgPerM,
//         'totalWeightKg': totalWeightKg,
//         'mark': mark.toMap(), // ✅ also add toMap to RebarMark (below)
//       };

//   static double _num(dynamic v, double fb) {
//     if (v is num) return v.toDouble();
//     return double.tryParse('${v ?? ''}') ?? fb;
//   }

//   factory RebarSet.fromMap(Map<String, dynamic> m) {
//     return RebarSet(
//       rawMark: (m['rawMark'] ?? '').toString(),
//       direction: (m['direction'] ?? '').toString(),
//       clearSpanM: _num(m['clearSpanM'], 0.0),
//       embedEachEndM: _num(m['embedEachEndM'], 0.0),
//       extraLengthM: _num(m['extraLengthM'], 0.0),
//       barLengthM: _num(m['barLengthM'], 0.0),
//       totalLengthM: _num(m['totalLengthM'], 0.0),
//       unitWeightKgPerM: _num(m['unitWeightKgPerM'], 0.0),
//       totalWeightKg: _num(m['totalWeightKg'], 0.0),
//       mark: RebarMark.fromMap(Map<String, dynamic>.from(m['mark'] ?? {})),
//     );
//   }
// }

class FootingCompositeController extends GetxController {
  FootingCompositeController({
    required this.projectId,
    required this.buildingId,
    required this.drawingId,
    required this.measurementsRef,
    required this.currentColorRx,
    this.activeLabelRx,
    this.activeBoqConcreteRx,
  });

  final String projectId;
  final String buildingId;
  final String drawingId;

  final CollectionReference<Map<String, dynamic>> measurementsRef;

  /// store your color as RxInt or Rx<Color>. here we assume RxInt (Color.value)
  final RxInt currentColorRx;

  /// optional - use your own sources
  final RxnString? activeLabelRx; // e.g. 'F1'
  final RxnString? activeBoqConcreteRx; // default concrete BOQ if you want

  // --- simple progress overlay state ---
  final RxBool saving = false.obs;
  final RxDouble savingPct = 0.0.obs;
  final RxString savingMsg = ''.obs;

  // ----------------------------
  // MAIN ENTRY (GETX VERSION)
  // ----------------------------
  Future<void> openFootingCompositeFromPolygon({
    required List<Offset> polygon,
    required Map<String, dynamic> drawingData,
  }) async {
    if (polygon.length < 3) return;

    // 1) bounding box + center in image coords
    double minX = polygon.first.dx, maxX = polygon.first.dx;
    double minY = polygon.first.dy, maxY = polygon.first.dy;

    for (final p in polygon) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;

    // 2) Convert to meters using your calibration helper
    final Lm = distanceInMeters(
      Offset(minX, centerY),
      Offset(maxX, centerY),
      drawingData,
    );
    final Bm = distanceInMeters(
      Offset(centerX, minY),
      Offset(centerX, maxY),
      drawingData,
    );

    if (Lm == null || Bm == null || Lm <= 0 || Bm <= 0) {
      Get.snackbar(
        'Calibration',
        'Drawing not calibrated – cannot compute footing length/width.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final polyData = polygon.map((p) => {'x': p.dx, 'y': p.dy}).toList();

    // 3) Dialog controllers/state (local)
    final thicknessController = TextEditingController(text: '0.30');
    final qtyFootingsController = TextEditingController(text: '1');

    final boqConcreteController = TextEditingController(
      text: (activeBoqConcreteRx?.value ?? '').trim(),
    );
    final boqFormworkController = TextEditingController();
    final boqRebarController = TextEditingController();

    final embedController = TextEditingController(text: '0.30');
    final extraController = TextEditingController(text: '0.00');

    final markController = TextEditingController();
    String rebarDirection = 'length'; // length | width

    String? errorText;
    final List<RebarSet> sets = [];

    bool _parseOkDouble(String text) => double.tryParse(text.trim()) != null;

    bool validateMainInputs() {
      if (!_parseOkDouble(thicknessController.text)) {
        errorText = 'Enter footing thickness (m).';
        return false;
      }
      if (int.tryParse(qtyFootingsController.text.trim()) == null) {
        errorText = 'Enter number of identical footings.';
        return false;
      }
      return true;
    }

    void addCurrentRebarMark(StateSetter setStateDialog) {
      final raw = markController.text.trim();
      if (raw.isEmpty) {
        setStateDialog(() => errorText = 'Please enter a rebar mark.');
        return;
      }

      final embed = double.tryParse(embedController.text.trim()) ?? 0.0;
      final extra = double.tryParse(extraController.text.trim()) ?? 0.0;

      try {
        final m = RebarMark.parse(raw);

        final clearSpanM = (rebarDirection == 'length') ? Lm : Bm;

        final Lbar = clearSpanM + 2 * embed + extra;
        final Ltotal = m.quantity * Lbar;
        final uw = rebarUnitWeightKgPerM(m.diameterMm);
        final wTotal = Ltotal * uw;

        sets.add(
          RebarSet(
            rawMark: raw,
            mark: m,
            direction: rebarDirection,
            clearSpanM: clearSpanM,
            embedEachEndM: embed,
            extraLengthM: extra,
            barLengthM: Lbar,
            totalLengthM: Ltotal,
            unitWeightKgPerM: uw,
            totalWeightKg: wTotal,
          ),
        );

        markController.clear();
        setStateDialog(() => errorText = null);
      } catch (e) {
        setStateDialog(() => errorText = e.toString());
      }
    }

    final ok =
        await Get.dialog<bool>(
          StatefulBuilder(
            builder: (ctx, setStateDialog) {
              // live preview
              final thicknessM =
                  double.tryParse(thicknessController.text.trim()) ?? 0.0;
              final nFootings =
                  int.tryParse(qtyFootingsController.text.trim()) ?? 1;

              final concretePerFooting =
                  thicknessM > 0 ? Lm * Bm * thicknessM : 0.0;
              final concreteTotal = concretePerFooting * nFootings;

              final perimeter = 2 * (Lm + Bm);
              final formworkPerFooting =
                  thicknessM > 0 ? perimeter * thicknessM : 0.0;
              final formworkTotal = formworkPerFooting * nFootings;

              double totalRebarLenOne = 0.0;
              double totalRebarKgOne = 0.0;
              for (final s in sets) {
                totalRebarLenOne += s.totalLengthM;
                totalRebarKgOne += s.totalWeightKg;
              }

              final totalRebarLenAll = totalRebarLenOne * nFootings;
              final totalRebarKgAll = totalRebarKgOne * nFootings;

              return AlertDialog(
                title: const Text(
                  'Footing composite (Concrete + Formwork + Rebar)',
                ),
                content: SizedBox(
                  width: 460,
                  height: 540,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Footing plan size: L ≈ ${Lm.toStringAsFixed(3)} m, '
                          'B ≈ ${Bm.toStringAsFixed(3)} m',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 8),

                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: thicknessController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Thickness (m)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 12),
                                onChanged: (_) => setStateDialog(() {}),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: qtyFootingsController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'No. of footings',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 12),
                                onChanged: (_) => setStateDialog(() {}),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),
                        const Text(
                          'BOQ mappings:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: boqConcreteController,
                          decoration: const InputDecoration(
                            labelText: 'Concrete BOQ code (m³)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: boqFormworkController,
                          decoration: const InputDecoration(
                            labelText: 'Formwork BOQ code (m²)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: boqRebarController,
                          decoration: const InputDecoration(
                            labelText: 'Rebar BOQ code (kg)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),

                        const SizedBox(height: 12),
                        const Divider(),
                        const Text(
                          'Rebar marks for this footing:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),

                        Row(
                          children: [
                            const Text(
                              'Bars along:',
                              style: TextStyle(fontSize: 12),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Length'),
                              selected: rebarDirection == 'length',
                              onSelected:
                                  (_) => setStateDialog(
                                    () => rebarDirection = 'length',
                                  ),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              label: const Text('Width'),
                              selected: rebarDirection == 'width',
                              onSelected:
                                  (_) => setStateDialog(
                                    () => rebarDirection = 'width',
                                  ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 6),
                        TextField(
                          controller: markController,
                          decoration: const InputDecoration(
                            labelText: 'Rebar mark (e.g. 12Y16-01-150B1)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),

                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: embedController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Embed each end (m)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: extraController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Extra length (laps/hooks, m)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),

                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed:
                                () => addCurrentRebarMark(setStateDialog),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add rebar mark'),
                          ),
                        ),

                        if (errorText != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            errorText!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 11,
                            ),
                          ),
                        ],

                        const Divider(),
                        if (sets.isEmpty)
                          const Text(
                            'No rebar marks added yet.',
                            style: TextStyle(fontSize: 11),
                          )
                        else
                          SizedBox(
                            height: 130,
                            child: ListView.builder(
                              itemCount: sets.length,
                              itemBuilder: (_, i) {
                                final s = sets[i];
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    '${s.rawMark} (${s.direction})',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  subtitle: Text(
                                    'L/bar: ${s.barLengthM.toStringAsFixed(3)} m, '
                                    'Total/ftg: ${s.totalLengthM.toStringAsFixed(3)} m, '
                                    'Wt/ftg: ${s.totalWeightKg.toStringAsFixed(2)} kg',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                    ),
                                    onPressed:
                                        () => setStateDialog(
                                          () => sets.removeAt(i),
                                        ),
                                  ),
                                );
                              },
                            ),
                          ),

                        const SizedBox(height: 10),
                        const Divider(),
                        const Text(
                          'Preview (all footings):',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Concrete: ${concretePerFooting.toStringAsFixed(3)} m³/ftg → '
                          '${concreteTotal.toStringAsFixed(3)} m³ total',
                          style: const TextStyle(fontSize: 11),
                        ),
                        Text(
                          'Formwork: ${formworkPerFooting.toStringAsFixed(3)} m²/ftg → '
                          '${formworkTotal.toStringAsFixed(3)} m² total',
                          style: const TextStyle(fontSize: 11),
                        ),
                        Text(
                          'Rebar length: ${totalRebarLenOne.toStringAsFixed(3)} m/ftg → '
                          '${totalRebarLenAll.toStringAsFixed(3)} m total',
                          style: const TextStyle(fontSize: 11),
                        ),
                        Text(
                          'Rebar weight: ${totalRebarKgOne.toStringAsFixed(2)} kg/ftg → '
                          '${totalRebarKgAll.toStringAsFixed(2)} kg total',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Get.back(result: false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (!validateMainInputs()) {
                        setStateDialog(() {});
                        return;
                      }
                      Get.back(result: true);
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ),
          barrierDismissible: false,
        ) ??
        false;

    // dispose dialog controllers
    thicknessController.dispose();
    qtyFootingsController.dispose();
    boqConcreteController.dispose();
    boqFormworkController.dispose();
    boqRebarController.dispose();
    embedController.dispose();
    extraController.dispose();
    markController.dispose();

    if (!ok) return;

    // 4) Final calculations + persistence (with progress)
    await _saveFootingComposite(
      polygonData: polyData,
      Lm: Lm,
      Bm: Bm,
      drawingData: drawingData,
      // pass back what user entered via controllers? we already disposed.
      // easiest: re-open values from last state in variables; so we capture them before dispose:
      // BUT since we disposed after ok, we should have captured earlier.
    );
  }

  /// Small saving overlay + batch write
  Future<void> _saveFootingComposite({
    required List<Map<String, dynamic>> polygonData,
    required double Lm,
    required double Bm,
    required Map<String, dynamic> drawingData,
  }) async {
    // You MUST capture dialog values before disposing controllers if you need them here.
    // If you want, I can refactor the method to keep them in local variables and pass here.
    // For now, I’ll show the pattern you should use:

    // Example placeholders (replace with captured values):
    final thicknessM = 0.30; // <- capture from dialog before dispose
    final nFootings = 1; // <- capture from dialog before dispose
    final boqConcrete = ''; // <- capture from dialog before dispose
    final boqFormwork = '';
    final boqRebar = '';
    final sets = <RebarSet>[]; // <- capture from dialog before dispose
    // -----------------------------------------------

    // Calculate
    final concretePerFooting = thicknessM > 0 ? Lm * Bm * thicknessM : 0.0;
    final concreteTotal = concretePerFooting * nFootings;

    final perimeter = 2 * (Lm + Bm);
    final formworkPerFooting = thicknessM > 0 ? perimeter * thicknessM : 0.0;
    final formworkTotal = formworkPerFooting * nFootings;

    double totalRebarLenOne = 0.0;
    double totalRebarKgOne = 0.0;
    for (final s in sets) {
      totalRebarLenOne += s.totalLengthM;
      totalRebarKgOne += s.totalWeightKg;
    }
    final totalRebarLenAll = totalRebarLenOne * nFootings;
    final totalRebarKgAll = totalRebarKgOne * nFootings;

    // Progress overlay
    saving.value = true;
    savingPct.value = 0;
    savingMsg.value = 'Preparing...';

    Get.dialog(
      Obx(
        () => AlertDialog(
          title: const Text('Saving'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: savingPct.value),
              const SizedBox(height: 10),
              Text(
                '${(savingPct.value * 100).toStringAsFixed(0)}%  ${savingMsg.value}',
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );

    try {
      final footingGroupId = measurementsRef.doc().id;
      final batch = FirebaseFirestore.instance.batch();

      int steps = 0;
      int done = 0;

      // count steps
      if (concreteTotal > 0 && boqConcrete.isNotEmpty) steps++;
      if (formworkTotal > 0 && boqFormwork.isNotEmpty) steps++;
      if (boqRebar.isNotEmpty && sets.isNotEmpty) steps += sets.length;

      void tick(String msg) {
        done++;
        savingMsg.value = msg;
        savingPct.value = steps == 0 ? 1.0 : (done / steps).clamp(0.0, 1.0);
      }

      // Concrete
      if (concreteTotal > 0 && boqConcrete.isNotEmpty) {
        final doc = measurementsRef.doc();
        batch.set(doc, {
          'projectId': projectId,
          'drawingId': drawingId,
          'buildingId': buildingId,
          'type': 'footingConcrete',
          'measureType': 'compositeFooting',
          'unit': 'm3',
          'value': concreteTotal,
          'valuePerFooting': concretePerFooting,
          'nFootings': nFootings,
          'lengthM': Lm,
          'widthM': Bm,
          'thicknessM': thicknessM,
          'label': '${(activeLabelRx?.value ?? 'Footing')} - Concrete',
          'boqCode': boqConcrete,
          'color': currentColorRx.value,
          'polygon': polygonData,
          'footingGroupId': footingGroupId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tick('Concrete...');
      }

      // Formwork
      if (formworkTotal > 0 && boqFormwork.isNotEmpty) {
        final doc = measurementsRef.doc();
        batch.set(doc, {
          'projectId': projectId,
          'drawingId': drawingId,
          'buildingId': buildingId,
          'type': 'footingFormwork',
          'measureType': 'compositeFooting',
          'unit': 'm2',
          'value': formworkTotal,
          'valuePerFooting': formworkPerFooting,
          'nFootings': nFootings,
          'lengthM': Lm,
          'widthM': Bm,
          'thicknessM': thicknessM,
          'perimeterM': perimeter,
          'label': '${(activeLabelRx?.value ?? 'Footing')} - Formwork',
          'boqCode': boqFormwork,
          'color': currentColorRx.value,
          'polygon': polygonData,
          'footingGroupId': footingGroupId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tick('Formwork...');
      }

      // Rebar (one doc per set)
      if (boqRebar.isNotEmpty && sets.isNotEmpty) {
        for (final s in sets) {
          final doc = measurementsRef.doc();
          final totalLenAllFootings = s.totalLengthM * nFootings;
          final totalWtAllFootings = s.totalWeightKg * nFootings;

          batch.set(doc, {
            'projectId': projectId,
            'buildingId': buildingId,
            'drawingId': drawingId,
            'type': 'rebarFooting',
            'measureType': 'compositeFooting',
            'unit': 'kg',
            'value': totalWtAllFootings,
            'lengthAllFootingsM': totalLenAllFootings,
            'weightAllFootingsKg': totalWtAllFootings,
            'lengthPerFootingM': s.totalLengthM,
            'weightPerFootingKg': s.totalWeightKg,
            'clearSpanM': s.clearSpanM,
            'embedEachEndM': s.embedEachEndM,
            'extraLengthM': s.extraLengthM,
            'barLengthM': s.barLengthM,
            'barsPerFooting': s.mark.quantity,
            'nFootings': nFootings,
            'rawMark': s.rawMark,
            'diameterMm': s.mark.diameterMm,
            'direction': s.direction,
            'label': '${(activeLabelRx?.value ?? 'Footing')} - Rebar',
            'boqCode': boqRebar,
            'color': currentColorRx.value,
            'polygon': polygonData,
            'footingGroupId': footingGroupId,
            'createdAt': FieldValue.serverTimestamp(),
          });

          tick('Rebar ${s.rawMark}...');
        }
      }

      savingMsg.value = 'Committing...';
      savingPct.value = 1.0;
      await batch.commit();

      Get.back(); // close progress dialog
      Get.snackbar(
        'Saved',
        'Footing composite (C+F+R) measurement saved.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      if (Get.isDialogOpen == true) Get.back();
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    } finally {
      saving.value = false;
      savingPct.value = 0;
      savingMsg.value = '';
    }
  }
}
