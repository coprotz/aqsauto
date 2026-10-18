// import 'link_models.dart';
import 'package:aqs/features/links/links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

double _asNum(dynamic v, [double def = 0]) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? def;
}

String _sumKey({
  required String projectId,
  required String buildingId,
  required String boqCode,
  required String unit,
}) {
  return '$projectId|$buildingId|$boqCode|$unit';
}

Future<PickSourceOutcome> showPickSourceMeasuredOutcomeDialog({
  required CollectionReference<Map<String, dynamic>> measurementsRef,
  required String projectId,
  required String buildingId,
  required bool allDrawingsInBuilding, // recommended true
  required String drawingId, // only used if allDrawingsInBuilding==false
  bool allowSingleEntries = false, // ✅ useful in Option B
}) async {
  // loading
  Get.dialog(
    const AlertDialog(
      content: SizedBox(
        height: 54,
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Loading measured items...')),
          ],
        ),
      ),
    ),
    barrierDismissible: false,
  );

  try {
    Query<Map<String, dynamic>> q = measurementsRef;

    // If your measurementsRef is already building-scoped, this is redundant but safe
    q = q.where('buildingId', isEqualTo: buildingId);

    if (!allDrawingsInBuilding) {
      q = q.where('drawingId', isEqualTo: drawingId);
    }

    final snap = await q.limit(1500).get();

    // --------- Build: sums + counts + best desc ----------
    final sums = <String, double>{}; // key = boqCode||unit
    final counts = <String, int>{};
    final desc = <String, String>{};

    // Optional: single entry list
    final single = <QtySourceDoc>[];

    for (final d in snap.docs) {
      final m = d.data();
      if (m['isDerived'] == true) continue;

      final boqCode = (m['boqCode'] ?? '').toString().trim();
      final unit = (m['unit'] ?? '').toString().trim();
      final value = _asNum(m['value'], 0);

      if (boqCode.isEmpty || unit.isEmpty) continue;

      final key = '$boqCode||$unit';

      sums[key] = (sums[key] ?? 0) + value;
      counts[key] = (counts[key] ?? 0) + 1;

      final dsc = (m['boqDescription'] ?? '').toString().trim();
      if ((desc[key] ?? '').isEmpty && dsc.isNotEmpty) desc[key] = dsc;

      if (allowSingleEntries) {
        // single entry source (doc-based)
        single.add(
          QtySourceDoc.fromMeasured(
            docId: d.id,
            boqCode: boqCode,
            boqDescription: dsc,
            unit: unit,
            value: value,
          ),
        );
      }
    }

    if (Get.isDialogOpen == true) Get.back(); // close loading

    if (sums.isEmpty) {
      return PickSourceOutcome.fail(
        'No measured items found to use as SOURCE.\n'
        'Ensure measurement docs include boqCode + unit + value.',
      );
    }

    // --------- Build SUM sources ----------
    final sumSources =
        sums.entries.map((e) {
            final parts = e.key.split('||');
            final code = parts[0];
            final unit = parts[1];
            final dsc = desc[e.key] ?? '';

            return QtySourceDoc.fromMeasured(
              // A summed source is not one Firestore measurement document.
              // Give it a stable aggregate identifier so saved links can
              // reference and later replace this source safely.
              docId: _sumKey(
                projectId: projectId,
                buildingId: buildingId,
                boqCode: code,
                unit: unit,
              ),
              boqCode: code,
              boqDescription: dsc,
              unit: unit,
              value: e.value,
            );
          }).toList()
          ..sort((a, b) => a.boqCode.compareTo(b.boqCode));

    single.sort((a, b) => a.boqCode.compareTo(b.boqCode));

    final searchCtrl = TextEditingController();
    final RxString queryRx = ''.obs;

    // 0 = SUM, 1 = SINGLE
    int tabIndex = 0;

    final picked = await Get.dialog<QtySourceDoc>(
      StatefulBuilder(
        builder: (ctx, setState) {
          Widget listFor(List<QtySourceDoc> sources, {required bool isSum}) {
            return Obx(() {
              final qtxt = queryRx.value.trim().toLowerCase();
              final filtered =
                  qtxt.isEmpty
                      ? sources
                      : sources.where((x) {
                        final t =
                            ('${x.boqCode} ${x.boqDescription} ${x.unit}')
                                .toLowerCase();
                        return t.contains(qtxt);
                      }).toList();

              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final s = filtered[i];
                  final key = '${s.boqCode}||${s.unit}';
                  final n = counts[key] ?? 1;

                  final title =
                      isSum
                          ? '${s.boqCode} — Σ ${s.value.toStringAsFixed(3)} ${s.unit}'
                          : '${s.boqCode} — ${s.value.toStringAsFixed(3)} ${s.unit}';

                  final subtitle =
                      isSum
                          ? '${s.boqDescription}\nFrom $n entries'
                          : '${s.boqDescription}\n(Part of Σ: ${(sums[key] ?? 0).toStringAsFixed(3)} ${s.unit} from $n entries)';

                  return ListTile(
                    title: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Get.back(result: s),
                  );
                },
              );
            });
          }

          return AlertDialog(
            title: const Text('Pick SOURCE'),
            content: SizedBox(
              width: 740,
              height: 560,
              child: Column(
                children: [
                  // search
                  TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      labelText: 'Search BOQ code/description',
                    ),
                    onChanged: (v) => queryRx.value = v,
                  ),
                  const SizedBox(height: 10),

                  // mode selector
                  if (allowSingleEntries) ...[
                    Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<int>(
                            segments: const [
                              ButtonSegment(value: 0, label: Text('Σ Totals')),
                              ButtonSegment(
                                value: 1,
                                label: Text('Single entries'),
                              ),
                            ],
                            selected: {tabIndex},
                            onSelectionChanged: (s) {
                              setState(() => tabIndex = s.first);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],

                  Expanded(
                    child:
                        allowSingleEntries && tabIndex == 1
                            ? listFor(single, isSum: false)
                            : listFor(sumSources, isSum: true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
      barrierDismissible: true,
    );

    return PickSourceOutcome.ok(picked); // cancel => ok(null)
  } catch (e) {
    if (Get.isDialogOpen == true) Get.back();
    return PickSourceOutcome.fail('$e');
  }
}

// Future<PickSourceOutcome> showPickSourceMeasuredOutcomeDialog({
//   required CollectionReference<Map<String, dynamic>> measurementsRef,
//   required String projectId,
//   required String buildingId,
//   required bool allDrawingsInBuilding, // recommended true
//   required String drawingId, // only used if allDrawingsInBuilding==false
// }) async {
//   // print('darwingid: $drawingId');
//   // print('projectId: $projectId');
//   // print('buildingId: $buildingId');
//   // loading
//   Get.dialog(
//     const AlertDialog(
//       content: SizedBox(
//         height: 54,
//         child: Row(
//           children: [
//             SizedBox(
//               width: 22,
//               height: 22,
//               child: CircularProgressIndicator(strokeWidth: 2),
//             ),
//             SizedBox(width: 12),
//             Expanded(child: Text('Loading measured items...')),
//           ],
//         ),
//       ),
//     ),
//     barrierDismissible: false,
//   );

//   try {
//     Query<Map<String, dynamic>> q = measurementsRef;

//     // If your measurementsRef is building-scoped, you don't need buildingId filter.
//     // Keep it anyway if your docs contain buildingId (harmless):
//     q = q.where('buildingId', isEqualTo: buildingId);

//     if (!allDrawingsInBuilding) {
//       q = q.where('drawingId', isEqualTo: drawingId);
//     }

//     final snap = await q.limit(1500).get();

//     // group sums by (boqCode, unit)
//     final sums = <String, double>{};
//     final counts = <String, int>{};
//     final desc = <String, String>{};

//     for (final d in snap.docs) {
//       final m = d.data();
//       if (m['isDerived'] == true) continue;

//       final boqCode = (m['boqCode'] ?? '').toString().trim();
//       final unit = (m['unit'] ?? '').toString().trim();
//       final value = _asNum(m['value'], 0);

//       if (boqCode.isEmpty || unit.isEmpty) continue;

//       final key = '$boqCode||$unit';
//       sums[key] = (sums[key] ?? 0) + value;
//       counts[key] = (counts[key] ?? 0) + 1;

//       // best-effort description
//       final dsc = (m['boqDescription'] ?? '').toString().trim();
//       if ((desc[key] ?? '').isEmpty && dsc.isNotEmpty) desc[key] = dsc;
//     }

//     if (Get.isDialogOpen == true) Get.back(); // close loading

//     if (sums.isEmpty) {
//       return PickSourceOutcome.fail(
//         'No measured items found to use as SOURCE.\n'
//         'Make sure measurement docs include boqCode + unit + value.',
//       );
//     }

//     // build list of SUM sources
//     final sources =
//         sums.entries.map((e) {
//             final parts = e.key.split('||');
//             final code = parts[0];
//             final unit = parts[1];
//             final dsc = desc[e.key] ?? '';
//             return QtySourceDoc(
//               kind: SourceKind.boqCodeSum,
//               boqCode: code,
//               boqDescription: dsc,
//               unit: unit,
//               value: e.value,
//               projectId: projectId,
//               buildingId: buildingId,
//             );
//           }).toList()
//           ..sort((a, b) => a.boqCode.compareTo(b.boqCode));

//     final searchCtrl = TextEditingController();
//     final RxString query = ''.obs;

//     final picked = await Get.dialog<QtySourceDoc>(
//       AlertDialog(
//         title: const Text('Pick SOURCE (Σ total by BOQ code)'),
//         content: SizedBox(
//           width: 720,
//           height: 520,
//           child: Column(
//             children: [
//               TextField(
//                 controller: searchCtrl,
//                 decoration: const InputDecoration(
//                   border: OutlineInputBorder(),
//                   isDense: true,
//                   labelText: 'Search BOQ code/description',
//                 ),
//                 onChanged: (v) => query.value = v,
//               ),
//               const SizedBox(height: 10),
//               Expanded(
//                 child: Obx(() {
//                   final q = query.value.trim().toLowerCase();
//                   final filtered =
//                       q.isEmpty
//                           ? sources
//                           : sources.where((x) {
//                             final t =
//                                 ('${x.boqCode} ${x.boqDescription} ${x.unit}')
//                                     .toLowerCase();
//                             return t.contains(q);
//                           }).toList();

//                   return ListView.builder(
//                     itemCount: filtered.length,
//                     itemBuilder: (_, i) {
//                       final s = filtered[i];
//                       final key = '${s.boqCode}||${s.unit}';
//                       final n = counts[key] ?? 1;

//                       return ListTile(
//                         title: Text(
//                           '${s.boqCode} — Σ ${s.value.toStringAsFixed(3)} ${s.unit}',
//                           style: const TextStyle(fontWeight: FontWeight.w700),
//                         ),
//                         subtitle: Text(
//                           '${s.boqDescription}\nFrom $n entries',
//                           maxLines: 3,
//                           overflow: TextOverflow.ellipsis,
//                         ),
//                         onTap: () => Get.back(result: s),
//                       );
//                     },
//                   );
//                 }),
//               ),
//             ],
//           ),
//         ),
//         actions: [
//           TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
//         ],
//       ),
//       barrierDismissible: true,
//     );

//     return PickSourceOutcome.ok(picked); // cancel => ok(null)
//   } catch (e) {
//     if (Get.isDialogOpen == true) Get.back();
//     return PickSourceOutcome.fail('$e');
//   }
// }
