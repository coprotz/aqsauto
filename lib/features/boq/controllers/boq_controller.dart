import 'package:aqs/core/state/firestore_state.dart';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aqs/app_routes.dart';
import 'package:aqs/features/boq/controllers/boq_template_controller.dart';
import 'package:aqs/features/boq/dialogs/boq_template_pick_dialog.dart';
import 'package:aqs/features/boq/models/boq_template.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:aqs/features/utils/helpers/boq_helpers.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class BoqController extends GetxController {
  final String projectId;
  final String buildingId;
  final String builldingName;
  String? drawingId;

  BoqController({
    required this.projectId,
    required this.buildingId,
    this.drawingId,
    required this.builldingName,
  });

  late final CollectionReference<Map<String, dynamic>> boqRef;
  late final CollectionReference<Map<String, dynamic>> measRef;
  bool _isBoqItemDialogOpen = false;
  bool _isAddBoqMenuOpen = false;

  @override
  void onInit() {
    super.onInit();

    boqRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(projectId)
        .collection('buildings')
        .doc(buildingId)
        .collection('boq');

    measRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(projectId)
        .collection('buildings')
        .doc(buildingId)
        .collection('measurements');
  }

  Future<void> deleteItem(String itemId) async {
    final ctx = Get.context;
    if (ctx == null) return;

    // ✅ confirm first
    final ok =
        await Get.dialog<bool>(
          AlertDialog(
            title: const Text('Delete BOQ item?'),
            content: const Text(
              'This will permanently delete this BOQ item.\n\nContinue?',
            ),
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
          barrierDismissible: true,
        ) ??
        false;

    if (!ok) return;

    try {
      await boqRef.doc(itemId).delete();

      Get.snackbar(
        'Deleted',
        'BOQ item deleted successfully.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar('Delete failed', '$e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> deleteAllBoqItems() async {
    final ctx = Get.context;
    if (ctx == null) return;

    final ok =
        await Get.dialog<bool>(
          AlertDialog(
            title: const Text('Delete entire BOQ?'),
            content: const Text(
              'This will permanently delete every BOQ row in this building, including items imported from Excel or templates.\n\nMeasurements will not be deleted, but their BOQ links may no longer match until you import or add BOQ items again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(result: false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD92D20),
                ),
                onPressed: () => Get.back(result: true),
                child: const Text('Delete BOQ'),
              ),
            ],
          ),
          barrierDismissible: true,
        ) ??
        false;

    if (!ok) return;

    try {
      var deleted = 0;
      while (true) {
        final snap = await boqRef.limit(400).get();
        if (snap.docs.isEmpty) break;

        final batch = FirebaseFirestore.instance.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
          deleted++;
        }
        await batch.commit();
      }

      Get.snackbar(
        'BOQ deleted',
        deleted == 0
            ? 'There were no BOQ rows to delete.'
            : 'Deleted $deleted BOQ rows.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar('Delete failed', '$e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> showAddBoqMenu() async {
    if (_isAddBoqMenuOpen) return;
    _isAddBoqMenuOpen = true;

    final tplCtrl =
        Get.isRegistered<BoqTemplateController>()
            ? Get.find<BoqTemplateController>()
            : Get.put(BoqTemplateController());
    final allowanceFuture = tplCtrl.currentAqsTemplateAllowance();

    try {
      final choice = await Get.dialog<AddBoqChoice>(
        AlertDialog(
          title: const Text('Add BOQ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Choose how you want to add the BOQ.'),
              const SizedBox(height: 12),
              FutureBuilder<AqsTemplateAllowance>(
                future: allowanceFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const LinearProgressIndicator(minHeight: 3);
                  }
                  final allowance = snapshot.data!;
                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFAEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFEDF89)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.library_books_outlined,
                          size: 18,
                          color: Color(0xFF93370D),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${allowance.planName}: ${allowance.remaining} of '
                            '${allowance.limit} new AQS template slots remaining. '
                            'Personal templates are free and unlimited.',
                            style: const TextStyle(
                              color: Color(0xFF93370D),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: AddBoqChoice.manual),
              child: const Text('ONE BY ONE'),
            ),
            FilledButton.icon(
              onPressed: () => Get.back(result: AddBoqChoice.template),
              icon: const Icon(Icons.library_books_outlined),
              label: const Text('FROM TEMPLATE'),
            ),
            OutlinedButton(
              onPressed: () => Get.back(result: AddBoqChoice.excel),
              child: const Text('UPLOAD EXCEL'),
            ),
          ],
        ),
      );

      if (choice == null) return;

      switch (choice) {
        case AddBoqChoice.manual:
          await showBoqItemDialog(measurementsRef: measRef);
          break;

        case AddBoqChoice.template:
          final picked = await Get.dialog<TplPickResult>(
            BoqTemplatePickDialog(controller: tplCtrl),
            barrierDismissible: true,
          );

          if (picked == null) return;

          Get.toNamed(
            AppRoutes.boqTemplatePickItems,
            arguments: {
              'projectId': projectId,
              'buildingId': buildingId,
              'drawingId': drawingId,
              'templateId': picked.templateId,
              'templateName': picked.templateName,
            },
          );
          break;

        case AddBoqChoice.excel:
          Get.toNamed(
            AppRoutes.boqImportExcel,
            arguments: {
              'projectId': projectId,
              'buildingId': buildingId,
              'drawingId': drawingId,
              'buildingName': builldingName,
            },
          );
          break;
      }
    } finally {
      _isAddBoqMenuOpen = false;
    }
  }

  // Future<void> showAddBoqMenu() async {
  //   final choice = await Get.dialog<AddBoqChoice>(
  //     AlertDialog(
  //       title: const Text('Add BOQ items'),
  //       content: const Text('Choose how you want to add BOQ items.'),
  //       actions: [
  //         TextButton(
  //           onPressed: () => Get.back(result: AddBoqChoice.manual),
  //           child: const Text('ONE BY ONE'),
  //         ),
  //         FilledButton(
  //           onPressed: () => Get.back(result: AddBoqChoice.template),
  //           child: const Text('FROM TEMPLATE'),
  //         ),
  //         OutlinedButton(
  //           onPressed: () => Get.back(result: AddBoqChoice.excel),
  //           child: const Text('UPLOAD EXCEL'),
  //         ),
  //       ],
  //     ),
  //   );

  //   if (choice == null) return;

  //   switch (choice) {
  //     case AddBoqChoice.manual:
  //       await showBoqItemDialog(measurementsRef: measRef);
  //       break;

  //     case AddBoqChoice.template:
  //       {
  //         // ✅ Ensure BoqTemplateController exists before dialog
  //         final tplCtrl =
  //             Get.isRegistered<BoqTemplateController>()
  //                 ? Get.find<BoqTemplateController>()
  //                 : Get.put(BoqTemplateController());

  //         final picked = await Get.dialog<TplPickResult>(
  //           BoqTemplatePickDialog(controller: tplCtrl),
  //           barrierDismissible: true,
  //         );

  //         if (picked == null) break;

  //         Get.toNamed(
  //           AppRoutes.boqTemplatePickItems,
  //           arguments: {
  //             'projectId': projectId,
  //             'buildingId': buildingId,
  //             'drawingId': drawingId,
  //             'templateId': picked.templateId,
  //             'templateName': picked.templateName,
  //           },
  //         );

  //         break;
  //       }

  //     case AddBoqChoice.excel:
  //       Get.toNamed(
  //         AppRoutes.boqImportExcel,
  //         arguments: {
  //           'projectId': projectId,
  //           'buildingId': buildingId,
  //           'drawingId': drawingId,
  //         },
  //       );
  //       break;
  //   }
  // }

  Future<int> addTemplateItemsToProjectBoq({
    required String projectId,
    required String buildingId,
    required String structureName,
    required String templateId,
    required List<BoqTemplateItem> selected,
  }) async {
    if (selected.isEmpty) return 0;

    // Example destination
    final destRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(projectId)
        .collection('buildings')
        .doc(buildingId)
        .collection('boq'); // <-- change to your real BOQ collection

    int added = 0;
    int i = 0;

    // Firestore batch limit 500
    while (i < selected.length) {
      final chunk = selected.skip(i).take(450).toList();
      final batch = FirebaseFirestore.instance.batch();

      for (final it in chunk) {
        final data = <String, dynamic>{
          'boqCode': it.boqCode,
          'description': it.description,
          'unit': it.unit,
          'rate': null,

          // Optional: store these so table grouping works
          'rowType': it.rowType,
          'order':
              DateTime.now().millisecondsSinceEpoch +
              added, // or it.order if you prefer
          'orderKey': it.orderKey,

          // Your project context
          'structure': structureName,

          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        batch.set(destRef.doc(), data);
        added++;
      }

      await batch.commit();
      i += chunk.length;
    }

    return added;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> boqStream() {
    return boqRef.orderBy('order', descending: false).stateSnapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> measStream() {
    return measRef.stateSnapshots();
  }

  Future<num> _computeInsertOrderInSection({
    required CollectionReference<Map<String, dynamic>> boqRef,
    required String billCode,
    required String subheading,
    String minorCode = '',
  }) async {
    String s(dynamic v) => (v ?? '').toString().trim();
    double asD(dynamic v) =>
        (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;

    // 1) find the subheading row "anchor" (where items of this section start)
    final subSnap =
        await boqRef
            .where('rowType', isEqualTo: 'subheading')
            .where('billCode', isEqualTo: billCode)
            .where('subheading', isEqualTo: subheading)
            .orderBy('order', descending: true)
            .limit(1)
            .get();

    // If no explicit subheading row exists, fallback to bill start (or 0)
    final subOrder =
        subSnap.docs.isNotEmpty ? asD(subSnap.docs.first.data()['order']) : 0.0;

    // 2) find the next header after this subheading (next subheading OR next bill)
    final nextHeaderSnap =
        await boqRef
            .where('order', isGreaterThan: subOrder)
            .where('rowType', whereIn: ['subheading', 'bill'])
            .orderBy('order')
            .limit(1)
            .get();

    final nextHeaderOrder =
        nextHeaderSnap.docs.isNotEmpty
            ? asD(nextHeaderSnap.docs.first.data()['order'])
            : double.infinity;

    // 3) find last item inside this section (and minor, if used) BEFORE next header
    Query<Map<String, dynamic>> q = boqRef
        .where('rowType', isEqualTo: 'item')
        .where('billCode', isEqualTo: billCode)
        .where('subheading', isEqualTo: subheading)
        .orderBy('order', descending: true);

    if (minorCode.trim().isNotEmpty) {
      q = q.where('minorCode', isEqualTo: minorCode.trim().toLowerCase());
    }

    final lastItemSnap = await q.limit(1).get();
    final lastItemOrder =
        lastItemSnap.docs.isNotEmpty
            ? asD(lastItemSnap.docs.first.data()['order'])
            : subOrder;

    // 4) place just after last item, but still before next header
    // Use a small step. If there is no "next header", it will just append.
    const step = 0.001;
    var proposed = lastItemOrder + step;

    // If next header exists and we would cross it, pack into the gap
    if (nextHeaderOrder.isFinite && proposed >= nextHeaderOrder) {
      // try midpoint between last item and next header
      proposed = (lastItemOrder + nextHeaderOrder) / 2.0;

      // still no space (orders too tight) -> just put very slightly before next header
      if (proposed == lastItemOrder || proposed == nextHeaderOrder) {
        proposed = nextHeaderOrder - step;
      }
    }

    return proposed;
  }

  Future<bool> showBoqItemDialog({
    String? existingId,
    Map<String, dynamic>? existingData,
    required CollectionReference<Map<String, dynamic>> measurementsRef,
  }) async {
    // A rapid second tap can otherwise mount another editor while the first
    // dialog (including its dropdown routes) is still in the widget tree.
    // Flutter's form controls own GlobalKeys internally, so overlapping copies
    // can trigger "Duplicate GlobalKeys detected in widget tree".
    if (_isBoqItemDialogOpen) return false;
    _isBoqItemDialogOpen = true;
    try {
      return await _showBoqItemDialog(
        existingId: existingId,
        existingData: existingData,
        measurementsRef: measurementsRef,
      );
    } finally {
      _isBoqItemDialogOpen = false;
    }
  }

  Future<bool> _showBoqItemDialog({
    String? existingId,
    Map<String, dynamic>? existingData,
    required CollectionReference<Map<String, dynamic>> measurementsRef,
  }) async {
    final isEdit = existingId != null && existingData != null;

    // -----------------------------
    // SAFE helpers
    // -----------------------------
    String s(dynamic v) => (v ?? '').toString();
    double n(dynamic v) =>
        (v is num)
            ? v.toDouble()
            : double.tryParse((v ?? '').toString()) ?? 0.0;

    bool isRoman(String x) =>
        RegExp(r'^[ivxlcdm]+$', caseSensitive: false).hasMatch(x.trim());
    bool isLetter(String x) => RegExp(r'^[A-Za-z]$').hasMatch(x.trim());

    List<String> parenTokens(String code) {
      return RegExp(r'\(([^)]+)\)')
          .allMatches(code)
          .map((m) => (m.group(1) ?? '').trim())
          .where((t) => t.isNotEmpty)
          .toList();
    }

    /// For 3.7(i)(A)(i) -> "i"
    /// For 3.1(B)(i) -> "" (no minor group)
    String inferMinorCodeFromBoqCode(String boqCode) {
      final toks = parenTokens(boqCode);
      if (toks.length >= 2 && isRoman(toks[0]) && isLetter(toks[1])) {
        return toks[0].toLowerCase();
      }
      return '';
    }

    String displayUnit(String u) => u == 'm2' ? 'm²' : (u == 'm3' ? 'm³' : u);

    // -----------------------------
    // ✅ NEW: Roman helpers (increment ii->iii etc.)
    // -----------------------------
    int _romanToInt(String roman) {
      final r = roman.trim().toUpperCase();
      if (r.isEmpty) return 0;
      final map = <String, int>{
        'I': 1,
        'V': 5,
        'X': 10,
        'L': 50,
        'C': 100,
        'D': 500,
        'M': 1000,
      };
      int total = 0;
      int prev = 0;
      for (int i = r.length - 1; i >= 0; i--) {
        final ch = r[i];
        final val = map[ch] ?? 0;
        if (val < prev) {
          total -= val;
        } else {
          total += val;
          prev = val;
        }
      }
      return total;
    }

    String _intToRoman(int num) {
      if (num <= 0) return '';
      final pairs = <MapEntry<int, String>>[
        const MapEntry(1000, 'M'),
        const MapEntry(900, 'CM'),
        const MapEntry(500, 'D'),
        const MapEntry(400, 'CD'),
        const MapEntry(100, 'C'),
        const MapEntry(90, 'XC'),
        const MapEntry(50, 'L'),
        const MapEntry(40, 'XL'),
        const MapEntry(10, 'X'),
        const MapEntry(9, 'IX'),
        const MapEntry(5, 'V'),
        const MapEntry(4, 'IV'),
        const MapEntry(1, 'I'),
      ];
      var n = num;
      final sb = StringBuffer();
      for (final p in pairs) {
        while (n >= p.key) {
          sb.write(p.value);
          n -= p.key;
        }
      }
      return sb.toString();
    }

    String _nextLetter(String x) {
      final c = x.trim();
      if (c.isEmpty) return 'A';
      final u = c.toUpperCase();
      final code = u.codeUnitAt(0);
      if (code < 65 || code > 90) return 'A';
      if (code == 90) return 'Z'; // clamp
      return String.fromCharCode(code + 1);
    }

    /// Increment LAST token:
    /// - "(ii)" -> "(iii)"
    /// - "(C)"  -> "(D)"
    /// - "C"    -> "D"
    /// - "10.1.3(C)" -> "10.1.3(D)"
    String _incrementLastToken(String code) {
      final raw = code.trim();
      if (raw.isEmpty) return 'A';

      // has parentheses at end or anywhere => increment last (...) token
      final matches = RegExp(r'\(([^)]+)\)').allMatches(raw).toList();
      if (matches.isNotEmpty) {
        final last = matches.last;
        final tok = (last.group(1) ?? '').trim();
        if (tok.isEmpty) return raw;

        String nextTok = tok;

        if (isRoman(tok)) {
          final v = _romanToInt(tok);
          nextTok = _intToRoman(v + 1).toLowerCase(); // keep lowercase style
        } else if (isLetter(tok)) {
          // keep same case style as original token
          final next = _nextLetter(tok);
          nextTok = (tok.toUpperCase() == tok) ? next : next.toLowerCase();
        } else {
          // trailing number?
          final m = RegExp(r'^(\d+)$').firstMatch(tok);
          if (m != null) {
            final v = int.tryParse(m.group(1)!) ?? 0;
            nextTok = '${v + 1}';
          } else {
            // unknown token => default A
            nextTok = 'A';
          }
        }

        final start = raw.substring(0, last.start);
        final end = raw.substring(last.end);
        return '$start($nextTok)$end';
      }

      // no parentheses: single letter like "C"
      if (isLetter(raw)) return _nextLetter(raw);

      // trailing digits
      final m2 = RegExp(r'^(.*?)(\d+)$').firstMatch(raw);
      if (m2 != null) {
        final prefix = m2.group(1) ?? '';
        final v = int.tryParse(m2.group(2) ?? '') ?? 0;
        return '$prefix${v + 1}';
      }

      // fallback
      return 'A';
    }

    // -----------------------------
    // (OPTIONAL) Recompute derived measurements linked to this BOQ doc
    // -----------------------------
    Future<void> _recomputeDerivedMeasurementsForSource({
      required String sourceDocId,
      required double newSourceValue,
    }) async {
      final fs = FirebaseFirestore.instance;
      final now = FieldValue.serverTimestamp();

      final snap =
          await measurementsRef
              .where('isDerived', isEqualTo: true)
              .where('derivedFromMode', isEqualTo: 'doc')
              .where('derivedFromDocId', isEqualTo: sourceDocId)
              .get();

      WriteBatch batch = fs.batch();
      int ops = 0;

      for (final d in snap.docs) {
        final m = d.data();

        final rule = (m['derivedRule'] ?? 'linear').toString().toLowerCase();
        final factor = n(m['derivedFactor']);
        final offset = n(m['derivedOffset']);

        double newValue = n(m['value']); // fallback
        if (rule == 'linear') {
          newValue = (newSourceValue * factor) + offset;
        }

        batch.update(d.reference, {
          'value': newValue,
          'updatedAt': now,
          'sourceValue': newSourceValue,
        });

        ops++;
        if (ops >= 450) {
          await batch.commit();
          batch = fs.batch();
          ops = 0;
        }
      }

      if (ops > 0) await batch.commit();
    }

    Future<void> _syncBoqItemMeasurements({
      required String boqItemId,
      required Map<String, dynamic> previousBoq,
      required String newCode,
      required String newDescription,
    }) async {
      String normalizedBoqCode(String value) =>
          value.replaceAll(RegExp(r'\s+'), '').trim().toLowerCase();

      final matched = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

      Future<void> collect(Query<Map<String, dynamic>> query) async {
        final snapshot = await query.get();
        for (final document in snapshot.docs) {
          matched[document.reference.path] = document;
        }
      }

      // Newer take-off records retain the BOQ document id. This remains stable
      // when a QS changes the visible code and is therefore the primary link.
      if (boqItemId.trim().isNotEmpty) {
        await collect(
          measurementsRef.where('boqItemId', isEqualTo: boqItemId.trim()),
        );
      }

      // Support older measurements that were saved before boqItemId was added.
      final previousCodes = <String>{
        s(previousBoq['boqCode']).trim(),
        s(previousBoq['displayCode']).trim(),
        s(previousBoq['resolvedBoqCode']).trim(),
      }..removeWhere((code) => code.isEmpty);
      for (final previousCode in previousCodes) {
        await collect(
          measurementsRef.where('boqCode', isEqualTo: previousCode),
        );
        await collect(
          measurementsRef.where(
            'boqCodeNorm',
            isEqualTo: normalizedBoqCode(previousCode),
          ),
        );
      }

      if (matched.isEmpty) return;

      final documents = matched.values.toList();
      for (var start = 0; start < documents.length; start += 450) {
        final end = math.min(start + 450, documents.length);
        final batch = FirebaseFirestore.instance.batch();
        for (var index = start; index < end; index++) {
          final document = documents[index];
          final data = document.data();
          final update = <String, dynamic>{
            'boqCode': newCode,
            'boqCodeRaw': newCode,
            'boqCodeNorm': normalizedBoqCode(newCode),
            'boqDescription': newDescription,
            'boqItemId': boqItemId,
            'updatedAt': FieldValue.serverTimestamp(),
          };
          if (data.containsKey('resolvedBoqCode')) {
            update['resolvedBoqCode'] = newCode;
          }
          if (data.containsKey('displayCode')) {
            update['displayCode'] = newCode;
          }
          batch.update(document.reference, update);
        }
        await batch.commit();
      }
    }

    // -----------------------------
    // BOQ ref
    // -----------------------------
    final boqRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(projectId)
        .collection('buildings')
        .doc(buildingId)
        .collection('boq');

    // -----------------------------
    // Load existing structures + bills + subheadings + minors + ALL docs snapshot
    // -----------------------------
    final existingStructures = <String>{};
    final existingBillsByCode = <String, String>{}; // billCode -> billLabel
    final existingSubheadingsByBill = <String, Set<String>>{};
    final existingMinorsByBillSub = <String, Set<String>>{};

    // keep all docs in memory (for auto-code)
    final allBoqDocs = <Map<String, dynamic>>[];

    bool isCivilRow(Map<String, dynamic> row) {
      final workType = s(row['boqWorkType']).trim().toLowerCase();
      final sectionType = s(row['sectionType']).trim().toLowerCase();
      if (workType == 'civil' || sectionType == 'series') return true;

      // Also recognise civil BOQs imported before the explicit metadata was
      // introduced, where the series marker was retained in the visible code.
      return <dynamic>[
        row['boqCode'],
        row['displayCode'],
        row['resolvedBoqCode'],
      ].any(
        (value) => RegExp(
          r'^series\b',
          caseSensitive: false,
        ).hasMatch(s(value).trim()),
      );
    }

    try {
      final snap = await boqRef.get();
      for (final d in snap.docs) {
        final data = d.data();
        allBoqDocs.add({...data, '__id': d.id});

        final structure = s(data['structure']).trim();
        if (structure.isNotEmpty) existingStructures.add(structure);

        final bCode = s(data['billCode']).trim();
        final bLabel = s(data['billLabel']).trim();
        if (bCode.isNotEmpty) {
          existingBillsByCode[bCode] =
              bLabel.isNotEmpty
                  ? bLabel
                  : '${isCivilRow(data) ? 'Series' : 'Bill'} $bCode';
        }

        final sub = s(data['subheading']).trim();
        if (bCode.isNotEmpty && sub.isNotEmpty) {
          existingSubheadingsByBill
              .putIfAbsent(bCode, () => <String>{})
              .add(sub);

          final minorCode = s(data['minorCode']).trim().toLowerCase();
          final minorHeading = s(data['minorHeading']).trim();
          if (minorCode.isNotEmpty || minorHeading.isNotEmpty) {
            final key = '$bCode|$sub';
            final packed = '${minorCode.toLowerCase()}::$minorHeading';
            existingMinorsByBillSub
                .putIfAbsent(key, () => <String>{})
                .add(packed);
          }
        }
      }
    } catch (_) {}

    final isCivilBoq =
        (existingData != null && isCivilRow(existingData)) ||
        allBoqDocs.any(isCivilRow);
    final billTerm = isCivilBoq ? 'Series' : 'Bill';
    final subheadingTerm = isCivilBoq ? 'Section / sub-series' : 'Subheading';
    final parentSubheadingTerm =
        isCivilBoq ? 'parent section / sub-series' : 'parent Subheading';

    Future<void> updateHeadingHierarchy({
      required String headingId,
      required String headingType,
      required Map<String, dynamic> headingPatch,
      required Map<String, dynamic> original,
      required String newCode,
      required String newDescription,
      required String targetBillCode,
      required String targetBillLabel,
      required String targetSubheading,
      required String targetSubheadingCode,
    }) async {
      final originalBillCode =
          s(original['billCode']).trim().isNotEmpty
              ? s(original['billCode']).trim()
              : s(original['boqCode']).trim();
      if (originalBillCode.isEmpty) {
        throw StateError('The heading has no bill identity to propagate.');
      }

      // Query one original bill only. Descendant filtering below further
      // narrows subheading and minor edits without requiring composite indexes.
      final scope =
          await boqRef.where('billCode', isEqualTo: originalBillCode).get();
      final refs = <DocumentReference<Map<String, dynamic>>>[
        boqRef.doc(headingId),
      ];
      final patches = <Map<String, dynamic>>[headingPatch];
      final originalSubheading =
          s(original['subheading']).trim().isNotEmpty
              ? s(original['subheading']).trim()
              : s(original['description']).trim();
      final originalSubheadingCode =
          s(original['subHeadingNo']).trim().isNotEmpty
              ? s(original['subHeadingNo']).trim()
              : s(original['subheadingNo']).trim().isNotEmpty
              ? s(original['subheadingNo']).trim()
              : headingType == 'subheading'
              ? s(original['boqCode']).trim()
              : '';
      final originalMinorCode =
          s(original['minorCode']).trim().isNotEmpty
              ? s(original['minorCode']).trim().toLowerCase()
              : s(original['minorNo']).trim().isNotEmpty
              ? s(original['minorNo']).trim().toLowerCase()
              : s(original['boqCode']).trim().toLowerCase();
      final originalMinorHeading =
          s(original['minorHeading']).trim().isNotEmpty
              ? s(original['minorHeading']).trim()
              : s(original['minorLabel']).trim().isNotEmpty
              ? s(original['minorLabel']).trim()
              : s(original['description']).trim();
      if (headingType == 'subheading' && originalSubheading.isEmpty) {
        throw StateError('The subheading has no identity to propagate.');
      }
      if (headingType == 'minor' &&
          originalMinorCode.isEmpty &&
          originalMinorHeading.isEmpty) {
        throw StateError('The minor heading has no identity to propagate.');
      }

      String normalizedMinorCode(String value) =>
          value.trim().replaceAll(RegExp(r'^\(|\)$'), '').toLowerCase();

      bool belongsToOriginalSubheading(Map<String, dynamic> data) {
        final dataSubheading = s(data['subheading']).trim();
        final dataSubheadingCode =
            s(data['subHeadingNo']).trim().isNotEmpty
                ? s(data['subHeadingNo']).trim()
                : s(data['subheadingNo']).trim();
        if (originalSubheading.isNotEmpty &&
            dataSubheading != originalSubheading) {
          return false;
        }
        if (originalSubheadingCode.isNotEmpty &&
            dataSubheadingCode.isNotEmpty &&
            dataSubheadingCode != originalSubheadingCode) {
          return false;
        }
        return true;
      }

      String replaceLeadingIdentity(
        String value,
        String oldIdentity,
        String newIdentity,
      ) {
        final current = value.trim();
        final oldValue = oldIdentity.trim();
        if (current.isEmpty || oldValue.isEmpty) return current;
        if (current == oldValue) return newIdentity;
        if (current.startsWith('$oldValue.') ||
            current.startsWith('$oldValue(')) {
          return '$newIdentity${current.substring(oldValue.length)}';
        }
        return current;
      }

      String resolvedForBill(Map<String, dynamic> data) {
        final current = s(data['resolvedBoqCode']).trim();
        final replaced = replaceLeadingIdentity(
          current,
          originalBillCode,
          newCode,
        );
        if (replaced != current || current.isNotEmpty) return replaced;
        final rawCode =
            s(data['displayCode']).trim().isNotEmpty
                ? s(data['displayCode']).trim()
                : s(data['boqCode']).trim();
        return bestResolvedCode(billCode: newCode, rawCode: rawCode);
      }

      String resolvedForSubheading(Map<String, dynamic> data) {
        final current = s(data['resolvedBoqCode']).trim();
        final replaced = replaceLeadingIdentity(
          current,
          originalSubheadingCode,
          newCode,
        );
        if (replaced != current || current.isNotEmpty) return replaced;
        final rawCode =
            s(data['displayCode']).trim().isNotEmpty
                ? s(data['displayCode']).trim()
                : s(data['boqCode']).trim();
        return rawCode.isEmpty ? newCode : '$newCode$rawCode';
      }

      String resolvedForMinor(Map<String, dynamic> data) {
        final current = s(data['resolvedBoqCode']).trim();
        final oldMinor = normalizedMinorCode(originalMinorCode);
        final nextMinor = normalizedMinorCode(newCode);
        if (isCivilBoq) {
          final replaced = replaceLeadingIdentity(current, oldMinor, nextMinor);
          if (replaced != current || current.isNotEmpty) return replaced;
          final rawCode =
              s(data['displayCode']).trim().isNotEmpty
                  ? s(data['displayCode']).trim()
                  : s(data['boqCode']).trim();
          return replaceLeadingIdentity(rawCode, oldMinor, nextMinor);
        }
        final oldPrefix =
            originalSubheadingCode.isEmpty
                ? '($oldMinor)'
                : '$originalSubheadingCode($oldMinor)';
        final newPrefix =
            targetSubheadingCode.isEmpty
                ? '($nextMinor)'
                : '$targetSubheadingCode($nextMinor)';
        final replaced = replaceLeadingIdentity(current, oldPrefix, newPrefix);
        if (replaced != current || current.isNotEmpty) return replaced;
        final rawCode =
            s(data['displayCode']).trim().isNotEmpty
                ? s(data['displayCode']).trim()
                : s(data['boqCode']).trim();
        return rawCode.isEmpty ? newPrefix : '$newPrefix$rawCode';
      }

      final originalData = <Map<String, dynamic>>[];

      for (final document in scope.docs) {
        if (document.id == headingId) continue;
        final data = document.data();
        final rowType = s(data['rowType']).trim().toLowerCase();
        if (headingType == 'bill' && rowType == 'bill') continue;
        final descendantPatch = <String, dynamic>{
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (headingType == 'bill') {
          descendantPatch.addAll({
            'billCode': newCode,
            'billLabel': newDescription,
          });
          final oldChildSubheadingCode =
              s(data['subHeadingNo']).trim().isNotEmpty
                  ? s(data['subHeadingNo']).trim()
                  : s(data['subheadingNo']).trim();
          final newChildSubheadingCode = replaceLeadingIdentity(
            oldChildSubheadingCode,
            originalBillCode,
            newCode,
          );
          if (oldChildSubheadingCode.isNotEmpty) {
            descendantPatch['subHeadingNo'] = newChildSubheadingCode;
            descendantPatch['subheadingNo'] = newChildSubheadingCode;
          }
          if (rowType == 'subheading') {
            final oldHeadingCode =
                s(data['boqCode']).trim().isNotEmpty
                    ? s(data['boqCode']).trim()
                    : oldChildSubheadingCode;
            final newHeadingCode = replaceLeadingIdentity(
              oldHeadingCode,
              originalBillCode,
              newCode,
            );
            descendantPatch['boqCode'] = newHeadingCode;
            descendantPatch['displayCode'] = newHeadingCode;
          }
          descendantPatch['resolvedBoqCode'] = resolvedForBill(data);
        } else if (headingType == 'subheading') {
          if ((rowType.isNotEmpty && rowType != 'minor' && rowType != 'item') ||
              !belongsToOriginalSubheading(data)) {
            continue;
          }
          descendantPatch.addAll({
            'billCode': targetBillCode,
            'billLabel': targetBillLabel,
            'subheading': newDescription,
            'subheadingNo': newCode,
            'subHeadingNo': newCode,
          });
          descendantPatch['resolvedBoqCode'] = resolvedForSubheading(data);
        } else if (headingType == 'minor') {
          if ((rowType.isNotEmpty && rowType != 'item') ||
              !belongsToOriginalSubheading(data)) {
            continue;
          }
          final descendantMinorCode =
              s(data['minorCode']).trim().isNotEmpty
                  ? s(data['minorCode']).trim().toLowerCase()
                  : s(data['minorNo']).trim().toLowerCase();
          final descendantMinorHeading =
              s(data['minorHeading']).trim().isNotEmpty
                  ? s(data['minorHeading']).trim()
                  : s(data['minorLabel']).trim();
          final belongsToMinor =
              (originalMinorCode.isEmpty ||
                  normalizedMinorCode(descendantMinorCode) ==
                      normalizedMinorCode(originalMinorCode)) &&
              (originalMinorHeading.isEmpty ||
                  descendantMinorHeading == originalMinorHeading);
          if (!belongsToMinor) continue;
          descendantPatch.addAll({
            'billCode': targetBillCode,
            'billLabel': targetBillLabel,
            'subheading': targetSubheading,
            'minorCode': newCode,
            'minorHeading': newDescription,
            'minorNo': newCode,
            'minorLabel': newDescription,
          });
          descendantPatch['subHeadingNo'] = targetSubheadingCode;
          descendantPatch['subheadingNo'] = targetSubheadingCode;
          descendantPatch['resolvedBoqCode'] = resolvedForMinor(data);
        } else {
          continue;
        }

        refs.add(document.reference);
        patches.add(descendantPatch);
        originalData.add(data);
      }

      // Keep the heading itself in the final batch so it remains the stable
      // hierarchy anchor until all descendants have been updated.
      final headingRef = refs.removeAt(0);
      final finalHeadingPatch = patches.removeAt(0);
      refs.add(headingRef);
      patches.add(finalHeadingPatch);
      originalData.add(original);

      final committedRanges = <({int start, int end})>[];
      try {
        for (var start = 0; start < refs.length; start += 450) {
          final end = math.min(start + 450, refs.length);
          final batch = FirebaseFirestore.instance.batch();
          for (var index = start; index < end; index++) {
            batch.update(refs[index], patches[index]);
          }
          await batch.commit();
          committedRanges.add((start: start, end: end));
        }
      } catch (saveError) {
        try {
          for (final range in committedRanges.reversed) {
            final batch = FirebaseFirestore.instance.batch();
            for (var index = range.start; index < range.end; index++) {
              final rollback = <String, dynamic>{};
              for (final key in patches[index].keys) {
                rollback[key] =
                    originalData[index].containsKey(key)
                        ? originalData[index][key]
                        : FieldValue.delete();
              }
              batch.update(refs[index], rollback);
            }
            await batch.commit();
          }
        } catch (rollbackError) {
          throw StateError(
            'Hierarchy update failed and could not be fully rolled back. '
            'Reload the BOQ before retrying. Save error: $saveError; '
            'rollback error: $rollbackError',
          );
        }
        throw StateError(
          'Hierarchy update failed; no changes were kept: $saveError',
        );
      }
    }

    final structuresList = existingStructures.toList()..sort();

    final unitOptions = <String>[
      'm',
      'm2',
      'm3',
      'kg',
      'tonne',
      'item',
      'PSum',
      'PC',
      'Pair',
      'Nos',
    ];

    const minorCodeOptions = <String>[
      'i',
      'ii',
      'iii',
      'iv',
      'v',
      'vi',
      'vii',
      'viii',
      'ix',
      'x',
    ];

    // -----------------------------
    // initial values
    // -----------------------------
    final editableRowTypes = <String, String>{
      'bill': isCivilBoq ? 'Series heading' : 'Bill heading',
      'subheading': isCivilBoq ? 'Section / sub-series' : 'Subheading',
      'minor': 'Minor heading',
      'item': 'BOQ item',
    };
    final existingRowType = s(existingData?['rowType']).trim().toLowerCase();
    String selectedRowType =
        editableRowTypes.containsKey(existingRowType)
            ? existingRowType
            : 'item';

    String firstNonEmpty(Iterable<dynamic> values) {
      for (final value in values) {
        final text = s(value).trim();
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    final initialCode = switch (existingRowType) {
      'bill' => firstNonEmpty([
        existingData?['billCode'],
        existingData?['billNo'],
        existingData?['boqCode'],
      ]),
      'subheading' => firstNonEmpty([
        existingData?['subHeadingNo'],
        existingData?['subheadingNo'],
        existingData?['boqCode'],
      ]),
      'minor' => firstNonEmpty([
        existingData?['minorCode'],
        existingData?['minorNo'],
        existingData?['boqCode'],
      ]).replaceAll(RegExp(r'^\(|\)$'), ''),
      _ => firstNonEmpty([
        existingData?['boqCode'],
        existingData?['displayCode'],
      ]),
    };
    final initialDescription = switch (existingRowType) {
      'bill' => firstNonEmpty([
        existingData?['billLabel'],
        existingData?['billName'],
        existingData?['description'],
      ]),
      'subheading' => firstNonEmpty([
        existingData?['subheading'],
        existingData?['description'],
      ]),
      'minor' => firstNonEmpty([
        existingData?['minorLabel'],
        existingData?['minorHeading'],
        existingData?['description'],
      ]),
      _ => s(existingData?['description']),
    };

    final codeController = TextEditingController(text: initialCode);
    final descController = TextEditingController(text: initialDescription);
    final rateController = TextEditingController(
      text: s(existingData?['rate']),
    );

    // ✅ qty override
    final qtyOverrideCtrl = TextEditingController(
      text: s(existingData?['qtyOverride']).trim(),
    );
    bool useQtyOverride = qtyOverrideCtrl.text.trim().isNotEmpty;

    double _calcAmount() {
      final qOverride = double.tryParse(qtyOverrideCtrl.text.trim());
      final rate = double.tryParse(rateController.text.trim());
      if (!useQtyOverride || qOverride == null || rate == null) return 0.0;
      return qOverride * rate;
    }

    // Track "touched" fields
    bool touchedStructure = false;
    bool touchedBill = false;
    bool touchedSubheading = false;
    bool touchedMinor = false;

    // Structure
    final existingStructureValue = s(existingData?['structure']).trim();
    String? selectedStructure =
        existingStructureValue.isNotEmpty ? existingStructureValue : null;
    String newStructureName = '';

    if (selectedStructure != null &&
        selectedStructure!.trim().isNotEmpty &&
        !structuresList.contains(selectedStructure)) {
      structuresList.add(selectedStructure!);
      structuresList.sort();
    }
    if (selectedStructure == null && structuresList.isNotEmpty) {
      selectedStructure = structuresList.first;
    }

    // Bill
    final existingBillCode = firstNonEmpty([
      existingData?['billCode'],
      existingData?['billNo'],
      if (existingRowType == 'bill') existingData?['boqCode'],
    ]);
    // ✅ If adding, default to first existing bill (not static list)
    String selectedBillCode =
        (() {
          if (isEdit && existingBillCode.isNotEmpty) return existingBillCode;
          if (existingBillsByCode.isNotEmpty) {
            final keys = existingBillsByCode.keys.toList()..sort();
            return keys.first;
          }
          return '1';
        })();

    // Subheading
    final existingSubheading = firstNonEmpty([
      existingData?['subheading'],
      if (existingRowType == 'subheading') existingData?['description'],
    ]);
    String? selectedSubheading =
        existingSubheading.isNotEmpty ? existingSubheading : null;
    String newSubheadingName = '';

    // Unit
    String selectedUnit =
        (() {
          final raw = s(existingData?['unit']).trim();
          if (raw.isNotEmpty) return raw;
          return 'm';
        })();
    // Imported BOQs can contain project-specific unit labels such as "cu.m"
    // or "Ltr". Keep the stored value available in the editor instead of
    // silently replacing it with the create-form default.
    if (!unitOptions.contains(selectedUnit)) {
      unitOptions.add(selectedUnit);
    }

    // Minor heading (optional)
    final existingMinorCode =
        firstNonEmpty([
          existingData?['minorCode'],
          existingData?['minorNo'],
          if (existingRowType == 'minor') existingData?['boqCode'],
        ]).replaceAll(RegExp(r'^\(|\)$'), '').toLowerCase();
    final existingMinorHeading = firstNonEmpty([
      existingData?['minorHeading'],
      existingData?['minorLabel'],
      if (existingRowType == 'minor') existingData?['description'],
    ]);

    bool hasMinor =
        existingMinorCode.isNotEmpty || existingMinorHeading.isNotEmpty;
    String? selectedMinorPacked =
        hasMinor ? '$existingMinorCode::$existingMinorHeading' : null;

    String newMinorCode =
        existingMinorCode.isNotEmpty ? existingMinorCode : 'i';
    final minorHeadingController = TextEditingController(
      text: existingMinorHeading,
    );

    bool isSaving = false;
    String? errorText;

    Map<String, dynamic>? linkedBoqItem;
    final existingLinkedId = s(existingData?['linkedBoqItemId']).trim();
    if (existingLinkedId.isNotEmpty) {
      for (final item in allBoqDocs) {
        if (s(item['__id']).trim() == existingLinkedId) {
          linkedBoqItem = item;
          break;
        }
      }
    }

    String itemDisplayCode(Map<String, dynamic> item) {
      final resolved = s(item['resolvedBoqCode']).trim();
      if (resolved.isNotEmpty) return resolved;
      final display = s(item['displayCode']).trim();
      if (display.isNotEmpty) return display;
      return s(item['boqCode']).trim();
    }

    Future<Map<String, dynamic>?> pickLinkedBoqItem(
      BuildContext context,
    ) async {
      final candidates =
          allBoqDocs.where((item) {
              final rowType = s(item['rowType']).trim().toLowerCase();
              if (rowType.isNotEmpty && rowType != 'item') return false;
              return s(item['__id']).trim() != s(existingId).trim();
            }).toList()
            ..sort((a, b) => itemDisplayCode(a).compareTo(itemDisplayCode(b)));

      return showDialog<Map<String, dynamic>>(
        context: context,
        builder: (pickerContext) {
          String query = '';
          return StatefulBuilder(
            builder: (pickerContext, setPickerState) {
              final filtered =
                  candidates.where((item) {
                    final haystack =
                        '${itemDisplayCode(item)} ${s(item['description'])}'
                            .toLowerCase();
                    return haystack.contains(query.toLowerCase());
                  }).toList();
              return AlertDialog(
                title: const Text('Link to another BOQ item'),
                content: SizedBox(
                  width: 680,
                  height: 520,
                  child: Column(
                    children: [
                      TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: 'Search BOQ code or description',
                          border: OutlineInputBorder(),
                        ),
                        onChanged:
                            (value) =>
                                setPickerState(() => query = value.trim()),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child:
                            filtered.isEmpty
                                ? const Center(
                                  child: Text('No matching BOQ items found.'),
                                )
                                : ListView.separated(
                                  itemCount: filtered.length,
                                  separatorBuilder:
                                      (_, __) => const Divider(height: 1),
                                  itemBuilder: (_, index) {
                                    final item = filtered[index];
                                    return ListTile(
                                      leading: const Icon(
                                        Icons.receipt_long_outlined,
                                      ),
                                      title: Text(itemDisplayCode(item)),
                                      subtitle: Text(s(item['description'])),
                                      onTap:
                                          () => Navigator.of(
                                            pickerContext,
                                          ).pop(item),
                                    );
                                  },
                                ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(pickerContext).pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              );
            },
          );
        },
      );
    }

    // Derived linkage indicator + checkbox
    bool updateLinked = true;
    bool derivedExists = false;

    if (isEdit) {
      try {
        final q =
            await measurementsRef
                .where('isDerived', isEqualTo: true)
                .where('derivedFromMode', isEqualTo: 'doc')
                .where('derivedFromDocId', isEqualTo: existingId)
                .limit(1)
                .get();
        derivedExists = q.docs.isNotEmpty;
        updateLinked = derivedExists;
      } catch (_) {
        derivedExists = false;
        updateLinked = false;
      }
    }

    // -----------------------------
    // ✅ NEW: Auto-code generator (ADD MODE ONLY)
    // -----------------------------
    String _inferFinalMinorForSection() {
      if (!hasMinor) return '';
      // if user picked a packed minor, use that code
      final packed = (selectedMinorPacked ?? '').trim();
      if (packed.isNotEmpty) {
        final parts = packed.split('::');
        final c = (parts.isNotEmpty ? parts[0] : '').trim().toLowerCase();
        return c;
      }
      // otherwise use dropdown newMinorCode
      return newMinorCode.trim().toLowerCase();
    }

    String _autoNextItemCode() {
      // If no BOQ exists yet => start A
      if (allBoqDocs.isEmpty) return 'A';

      final bill = selectedBillCode.trim();
      final sub = (selectedSubheading ?? '').trim();
      final finalMinor = _inferFinalMinorForSection(); // '' or 'i'...

      if (bill.isEmpty || sub.isEmpty) return 'A';

      // Filter items in SAME section (bill+sub+minor)
      final sectionItems =
          allBoqDocs.where((m) {
            final rowType = s(m['rowType']).trim().toLowerCase();
            if (rowType.isNotEmpty && rowType != 'item') return false;

            final b = s(m['billCode']).trim();
            final sh = s(m['subheading']).trim();
            if (b != bill || sh != sub) return false;

            final mi = s(m['minorCode']).trim().toLowerCase();
            if (finalMinor.isEmpty) {
              // section without minor
              return mi.isEmpty;
            } else {
              return mi == finalMinor;
            }
          }).toList();

      if (sectionItems.isEmpty) {
        // first item in this section
        return 'A';
      }

      // pick last by order (fallback: createdAt)
      sectionItems.sort((a, b) {
        final ao = n(a['order']);
        final bo = n(b['order']);
        if (ao == bo) return 0;
        return ao < bo ? -1 : 1;
      });

      final last = sectionItems.last;

      // prefer displayCode -> boqCode -> resolvedBoqCode
      final lastCode =
          s(last['displayCode']).trim().isNotEmpty
              ? s(last['displayCode']).trim()
              : (s(last['boqCode']).trim().isNotEmpty
                  ? s(last['boqCode']).trim()
                  : s(last['resolvedBoqCode']).trim());

      final next = _incrementLastToken(lastCode);
      return next.trim().isEmpty ? 'A' : next.trim();
    }

    void _regenAutoCode(StateSetter setStateDialog) {
      if (isEdit || selectedRowType != 'item') return;
      final next = _autoNextItemCode();
      setStateDialog(() {
        codeController.text = next;
        touchedMinor = true; // to force re-validate section & minors
        errorText = null;
      });
    }

    // -----------------------------
    // ✅ ADD MODE: require existing BOQ section (no new structure/sub/minor)
    // -----------------------------
    bool _canAddMissingItem() {
      if (isEdit) return true;
      if (existingBillsByCode.isEmpty) return false;
      if (structuresList.isEmpty) return false;
      if (selectedRowType == 'subheading') return true;
      final subs = existingSubheadingsByBill[selectedBillCode] ?? <String>{};
      return subs.isNotEmpty;
    }

    // ✅ Preselect first existing subheading in ADD mode
    if (!isEdit) {
      final subs = existingSubheadingsByBill[selectedBillCode] ?? <String>{};
      if (subs.isNotEmpty) {
        final sorted = subs.toList()..sort();
        selectedSubheading = sorted.first;
      }
      // also reset minor if this section has minors
      final key = '$selectedBillCode|${selectedSubheading ?? ''}';
      final minors = existingMinorsByBillSub[key] ?? <String>{};
      if (minors.isNotEmpty) {
        hasMinor = true;
        selectedMinorPacked = (minors.toList()..sort()).first;
        final parts = selectedMinorPacked!.split('::');
        newMinorCode = (parts.isNotEmpty ? parts[0] : 'i').trim().toLowerCase();
        minorHeadingController.text = (parts.length > 1 ? parts[1] : '').trim();
      } else {
        hasMinor = false;
        selectedMinorPacked = null;
        newMinorCode = 'i';
        minorHeadingController.text = '';
      }
      if (selectedRowType == 'item') {
        codeController.text = _autoNextItemCode();
      }
    }

    // -----------------------------
    // SAVE HANDLER (updated: ADD mode code is auto, read-only)
    // -----------------------------
    BuildContext? editorDialogContext;

    Future<void> handleSave(StateSetter setStateDialog) async {
      if (isSaving) return;

      // ADD mode must have existing BOQ
      if (!_canAddMissingItem()) {
        setStateDialog(() {
          errorText =
              'No existing BOQ sections found.\n\nImport from Excel or apply an Admin template first, then add missing items inside existing sections.';
        });
        return;
      }

      final old = existingData ?? <String, dynamic>{};
      String oldS(String key) => s(old[key]).trim();

      // ✅ code is auto in add mode
      if (!isEdit && selectedRowType == 'item') {
        if (codeController.text.trim().isEmpty) {
          // regenerate once
          _regenAutoCode(setStateDialog);
        }
      }

      final code = codeController.text.trim();
      final normalizedCode =
          selectedRowType == 'minor' && !isCivilBoq
              ? code.replaceAll(RegExp(r'^\(|\)$'), '').trim().toLowerCase()
              : code;
      if (normalizedCode.isEmpty) {
        setStateDialog(
          () =>
              errorText =
                  selectedRowType == 'item'
                      ? 'Item code is required.'
                      : '${editableRowTypes[selectedRowType]} code is required.',
        );
        return;
      }

      final desc = descController.text.trim();
      if (desc.isEmpty) {
        setStateDialog(() {
          errorText =
              selectedRowType == 'item'
                  ? 'Item description is required.'
                  : '${editableRowTypes[selectedRowType]} title is required.';
        });
        return;
      }

      // Rate (measurable BOQ items only)
      final rateStr = rateController.text.trim();
      final double? rate = rateStr.isNotEmpty ? double.tryParse(rateStr) : null;
      if (selectedRowType == 'item' && rateStr.isNotEmpty && rate == null) {
        setStateDialog(() => errorText = 'Invalid rate number.');
        return;
      }

      // Qty override
      double? qtyOverride;
      if (selectedRowType == 'item' && useQtyOverride) {
        qtyOverride = double.tryParse(qtyOverrideCtrl.text.trim());
        if (qtyOverride == null || qtyOverride <= 0) {
          setStateDialog(() => errorText = 'Invalid qty override.');
          return;
        }
      }

      // ✅ ADD MODE: force existing structure/bill/sub/minor selections
      if (!isEdit) {
        final pickedStructure = (selectedStructure ?? '').trim();
        if (pickedStructure.isEmpty ||
            !structuresList.contains(pickedStructure)) {
          setStateDialog(() {
            errorText =
                'Pick an existing Structure/Building.\nNew structure is disabled for missing-item insert.';
          });
          return;
        }

        final billLabel = (existingBillsByCode[selectedBillCode] ?? '').trim();
        if (billLabel.isEmpty) {
          setStateDialog(
            () => errorText = 'Pick an existing $billTerm from BOQ.',
          );
          return;
        }

        final finalSubheading = (selectedSubheading ?? '').trim();
        if (selectedRowType == 'item' || selectedRowType == 'minor') {
          final subs =
              existingSubheadingsByBill[selectedBillCode] ?? <String>{};
          if (finalSubheading.isEmpty || !subs.contains(finalSubheading)) {
            setStateDialog(() {
              errorText = 'Pick an existing $parentSubheadingTerm from BOQ.';
            });
            return;
          }
        }

        final billSubKey = '$selectedBillCode|$finalSubheading';
        final minors = existingMinorsByBillSub[billSubKey] ?? <String>{};
        if (selectedRowType == 'item' && minors.isNotEmpty) {
          if (!hasMinor) {
            setStateDialog(() {
              errorText =
                  'This ${subheadingTerm.toLowerCase()} has Minor headings. Tick "Has minor" and select one.';
            });
            return;
          }
          final packed = (selectedMinorPacked ?? '').trim();
          if (packed.isEmpty || !minors.contains(packed)) {
            setStateDialog(() {
              errorText =
                  'Pick an existing Minor heading for this $subheadingTerm.';
            });
            return;
          }
        }

        if (selectedRowType == 'subheading') {
          final fullCode =
              isCivilBoq || normalizedCode.startsWith('$selectedBillCode.')
                  ? normalizedCode
                  : '$selectedBillCode.$normalizedCode';
          final exists = allBoqDocs.any(
            (row) =>
                s(row['rowType']).trim().toLowerCase() == 'subheading' &&
                s(row['billCode']).trim() == selectedBillCode &&
                firstNonEmpty([
                      row['subHeadingNo'],
                      row['subheadingNo'],
                      row['boqCode'],
                    ]) ==
                    fullCode,
          );
          if (exists) {
            setStateDialog(
              () => errorText = '$subheadingTerm $fullCode already exists.',
            );
            return;
          }
        } else if (selectedRowType == 'minor') {
          final minorCode = normalizedCode.toLowerCase();
          final exists = allBoqDocs.any(
            (row) =>
                s(row['rowType']).trim().toLowerCase() == 'minor' &&
                s(row['billCode']).trim() == selectedBillCode &&
                s(row['subheading']).trim() == finalSubheading &&
                firstNonEmpty([
                      row['minorCode'],
                      row['minorNo'],
                    ]).replaceAll(RegExp(r'^\(|\)$'), '').toLowerCase() ==
                    minorCode,
          );
          if (exists) {
            setStateDialog(
              () => errorText = 'Minor heading ($minorCode) already exists.',
            );
            return;
          }
        }
      }

      final patch = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'rowType': selectedRowType,
      };
      if (isCivilBoq) {
        patch['boqWorkType'] = 'civil';
        patch['sectionType'] = 'series';
      }
      var measurementBoqCode = normalizedCode;

      // core
      if (!isEdit || normalizedCode != oldS('boqCode')) {
        patch['boqCode'] = normalizedCode;
        if (isEdit) {
          patch['displayCode'] = normalizedCode;
          patch['resolvedBoqCode'] = bestResolvedCode(
            billCode:
                selectedRowType == 'bill' ? normalizedCode : selectedBillCode,
            rawCode: normalizedCode,
          );
        }
      }
      if (!isEdit || desc != oldS('description')) patch['description'] = desc;
      if (selectedRowType == 'item' &&
          (!isEdit || selectedUnit != oldS('unit'))) {
        patch['unit'] = selectedUnit;
      }

      // rate
      if (selectedRowType != 'item') {
        if (isEdit) patch['rate'] = FieldValue.delete();
      } else if (!isEdit) {
        patch['rate'] = rate;
      } else {
        if (rateStr.isEmpty) {
          patch['rate'] = FieldValue.delete();
        } else {
          final oldRate = old['rate'];
          final oldRateStr = oldRate == null ? '' : oldRate.toString();
          if (rateStr != oldRateStr) patch['rate'] = rate;
        }
      }

      // qty override
      if (selectedRowType != 'item') {
        if (isEdit) patch['qtyOverride'] = FieldValue.delete();
      } else if (!isEdit) {
        if (useQtyOverride) patch['qtyOverride'] = qtyOverride;
      } else {
        if (useQtyOverride) {
          final oldQ = old['qtyOverride'];
          final oldQStr = oldQ == null ? '' : oldQ.toString();
          final newQStr = qtyOverride!.toString();
          if (oldQStr != newQStr) patch['qtyOverride'] = qtyOverride;
        } else {
          patch['qtyOverride'] = FieldValue.delete();
        }
      }

      if (isEdit && selectedRowType == 'item') {
        if (linkedBoqItem == null) {
          patch['linkedBoqItemId'] = FieldValue.delete();
          patch['linkedBoqCode'] = FieldValue.delete();
          patch['linkedBoqDescription'] = FieldValue.delete();
        } else {
          patch['linkedBoqItemId'] = s(linkedBoqItem!['__id']).trim();
          patch['linkedBoqCode'] = itemDisplayCode(linkedBoqItem!);
          patch['linkedBoqDescription'] =
              s(linkedBoqItem!['description']).trim();
        }
      }

      if (selectedRowType == 'item' && useQtyOverride && rate != null) {
        patch['amountOverride'] = qtyOverride! * rate;
      } else {
        if (isEdit) {
          patch['amountOverride'] = FieldValue.delete();
        } else {
          patch.remove('amountOverride');
        }
      }

      // structure
      final mustValidateStructure =
          !isEdit || touchedStructure || oldS('structure').isEmpty;
      if (mustValidateStructure) {
        final structureName = (selectedStructure ?? newStructureName).trim();
        if (structureName.isEmpty) {
          setStateDialog(() => errorText = 'Structure name is required.');
          return;
        }
        if (!isEdit || structureName != oldS('structure')) {
          patch['structure'] = structureName;
        }
      }

      // bill/sub
      final mustValidateBillSub =
          selectedRowType != 'bill' &&
          (!isEdit ||
              touchedBill ||
              touchedSubheading ||
              (selectedRowType == 'item' && oldS('subheading').isEmpty) ||
              oldS('billCode').isEmpty);

      if (mustValidateBillSub) {
        final finalSubheading =
            (selectedSubheading ?? newSubheadingName).trim();
        if (selectedRowType == 'item' && finalSubheading.isEmpty) {
          setStateDialog(() => errorText = '$subheadingTerm is required.');
          return;
        }

        if (!isEdit) {
          final billLabel =
              (existingBillsByCode[selectedBillCode] ?? '').trim();
          patch['billCode'] = selectedBillCode;
          patch['billLabel'] = billLabel;
          if (selectedRowType == 'item') patch['subheading'] = finalSubheading;
        } else {
          // edit mode: keep your old billOptions logic if you have it, or keep existing
          patch['billCode'] = selectedBillCode;
          patch['billLabel'] =
              s(existingBillsByCode[selectedBillCode]).trim().isNotEmpty
                  ? s(existingBillsByCode[selectedBillCode]).trim()
                  : oldS('billLabel');
          if (selectedRowType == 'item') patch['subheading'] = finalSubheading;
        }
      }

      if (isEdit && selectedRowType == 'bill') {
        patch.addAll({
          'boqCode': normalizedCode,
          'displayCode': normalizedCode,
          'resolvedBoqCode': normalizedCode,
          'billCode': normalizedCode,
          'billLabel': desc,
          'billNo': normalizedCode,
          'billName': desc,
          'subheading': FieldValue.delete(),
          'subheadingNo': FieldValue.delete(),
          'subHeadingNo': FieldValue.delete(),
          'minorCode': FieldValue.delete(),
          'minorHeading': FieldValue.delete(),
          'minorNo': FieldValue.delete(),
          'minorLabel': FieldValue.delete(),
          'unit': FieldValue.delete(),
          'amountOverride': FieldValue.delete(),
          'linkedBoqItemId': FieldValue.delete(),
          'linkedBoqCode': FieldValue.delete(),
          'linkedBoqDescription': FieldValue.delete(),
        });
      } else if (selectedRowType == 'subheading') {
        final subheadingCode =
            isCivilBoq ||
                    normalizedCode == selectedBillCode ||
                    normalizedCode.startsWith('$selectedBillCode.')
                ? normalizedCode
                : '$selectedBillCode.$normalizedCode';
        patch.addAll({
          'boqCode': subheadingCode,
          'displayCode': subheadingCode,
          'resolvedBoqCode': subheadingCode,
          'subheading': desc,
          'subheadingNo': subheadingCode,
          'subHeadingNo': subheadingCode,
          'minorCode': FieldValue.delete(),
          'minorHeading': FieldValue.delete(),
          'minorNo': FieldValue.delete(),
          'minorLabel': FieldValue.delete(),
          'unit': FieldValue.delete(),
          'amountOverride': FieldValue.delete(),
          'linkedBoqItemId': FieldValue.delete(),
          'linkedBoqCode': FieldValue.delete(),
          'linkedBoqDescription': FieldValue.delete(),
        });
      } else if (selectedRowType == 'minor') {
        final parentSubheadingCode =
            (() {
              for (final row in allBoqDocs) {
                if (s(row['rowType']).trim().toLowerCase() != 'subheading' ||
                    s(row['billCode']).trim() != selectedBillCode ||
                    s(row['subheading']).trim() !=
                        (selectedSubheading ?? '').trim()) {
                  continue;
                }
                return firstNonEmpty([
                  row['subHeadingNo'],
                  row['subheadingNo'],
                  row['boqCode'],
                ]);
              }
              return firstNonEmpty([old['subHeadingNo'], old['subheadingNo']]);
            })();
        final minorDisplayCode =
            isCivilBoq ? normalizedCode : '($normalizedCode)';
        patch.addAll({
          'boqCode': minorDisplayCode,
          'displayCode': minorDisplayCode,
          'resolvedBoqCode':
              isCivilBoq
                  ? normalizedCode
                  : parentSubheadingCode.isEmpty
                  ? minorDisplayCode
                  : '$parentSubheadingCode$minorDisplayCode',
          'subHeadingNo': parentSubheadingCode,
          'subheadingNo': parentSubheadingCode,
          'subheading': (selectedSubheading ?? '').trim(),
          'minorCode': normalizedCode,
          'minorHeading': desc,
          'minorNo': normalizedCode,
          'minorLabel': desc,
          'unit': FieldValue.delete(),
          'amountOverride': FieldValue.delete(),
          'linkedBoqItemId': FieldValue.delete(),
          'linkedBoqCode': FieldValue.delete(),
          'linkedBoqDescription': FieldValue.delete(),
        });
      }

      // minor fields
      final mustValidateMinor =
          selectedRowType == 'item' && (!isEdit || touchedMinor);
      if (mustValidateMinor) {
        final inferredMinor = inferMinorCodeFromBoqCode(code);

        String finalMinorCode = '';
        String finalMinorHeading = '';

        if (hasMinor) {
          finalMinorCode = newMinorCode.trim().toLowerCase();
          finalMinorHeading = minorHeadingController.text.trim();
        } else if (inferredMinor.isNotEmpty) {
          finalMinorCode = inferredMinor;
          finalMinorHeading = '';
        }

        if (finalMinorCode.isNotEmpty || finalMinorHeading.isNotEmpty) {
          patch['minorCode'] = finalMinorCode;
          patch['minorHeading'] = finalMinorHeading;
        } else {
          if (isEdit) {
            // ✅ allowed only in update()
            patch['minorCode'] = FieldValue.delete();
            patch['minorHeading'] = FieldValue.delete();
          } else {
            // ✅ create mode: DO NOT send deleteField()
            patch.remove('minorCode');
            patch.remove('minorHeading');
          }
        }
      }

      if (selectedRowType == 'item') {
        var effectiveSubheadingCode = firstNonEmpty([
          patch['subHeadingNo'],
          patch['subheadingNo'],
          old['subHeadingNo'],
          old['subheadingNo'],
        ]);
        final effectiveSubheading =
            (selectedSubheading ?? oldS('subheading')).trim();
        for (final row in allBoqDocs) {
          if (s(row['rowType']).trim().toLowerCase() != 'subheading' ||
              s(row['billCode']).trim() != selectedBillCode ||
              s(row['subheading']).trim() != effectiveSubheading) {
            continue;
          }
          effectiveSubheadingCode = firstNonEmpty([
            row['subHeadingNo'],
            row['subheadingNo'],
            row['boqCode'],
          ]);
          break;
        }

        final effectiveMinorCode =
            patch['minorCode'] is String
                ? s(patch['minorCode']).trim()
                : patch['minorCode'] is FieldValue
                ? ''
                : firstNonEmpty([old['minorCode'], old['minorNo']]);
        measurementBoqCode = hierarchicalBoqCode({
          if (isCivilBoq) 'boqWorkType': 'civil',
          if (isCivilBoq) 'sectionType': 'series',
          'billCode': selectedBillCode,
          'subHeadingNo': effectiveSubheadingCode,
          'minorCode': effectiveMinorCode,
          'displayCode': normalizedCode,
          'boqCode': normalizedCode,
        });
        patch['displayCode'] = normalizedCode;
        patch['resolvedBoqCode'] = measurementBoqCode;
        if (effectiveSubheadingCode.isNotEmpty) {
          patch['subHeadingNo'] = effectiveSubheadingCode;
          patch['subheadingNo'] = effectiveSubheadingCode;
        }
      }

      setStateDialog(() {
        isSaving = true;
        errorText = null;
      });

      try {
        if (isEdit) {
          final isHierarchyEdit =
              selectedRowType == existingRowType &&
              const {'bill', 'subheading', 'minor'}.contains(selectedRowType);
          if (isHierarchyEdit) {
            final targetBill =
                selectedRowType == 'bill' ? normalizedCode : selectedBillCode;
            final targetBillName =
                selectedRowType == 'bill'
                    ? desc
                    : (existingBillsByCode[targetBill] ?? oldS('billLabel'))
                        .trim();
            final targetSubheading =
                (selectedSubheading ?? oldS('subheading')).trim();
            final targetSubheadingCode =
                selectedRowType == 'subheading'
                    ? normalizedCode
                    : (() {
                      for (final row in allBoqDocs) {
                        if (s(row['rowType']).trim().toLowerCase() !=
                                'subheading' ||
                            s(row['billCode']).trim() != targetBill ||
                            s(row['subheading']).trim() != targetSubheading) {
                          continue;
                        }
                        return firstNonEmpty([
                          row['subHeadingNo'],
                          row['subheadingNo'],
                          row['boqCode'],
                        ]);
                      }
                      return firstNonEmpty([
                        old['subHeadingNo'],
                        old['subheadingNo'],
                      ]);
                    })();
            await updateHeadingHierarchy(
              headingId: existingId!,
              headingType: selectedRowType,
              headingPatch: patch,
              original: old,
              newCode: normalizedCode,
              newDescription: desc,
              targetBillCode: targetBill,
              targetBillLabel: targetBillName,
              targetSubheading: targetSubheading,
              targetSubheadingCode: targetSubheadingCode,
            );
          } else {
            await boqRef.doc(existingId!).update(patch);
          }

          if (selectedRowType == 'item') {
            await _syncBoqItemMeasurements(
              boqItemId: existingId!,
              previousBoq: old,
              newCode: measurementBoqCode,
              newDescription: desc,
            );
          }

          if (updateLinked && derivedExists && useQtyOverride) {
            await _recomputeDerivedMeasurementsForSource(
              sourceDocId: existingId!,
              newSourceValue: qtyOverride!,
            );
          }
        } else {
          final finalSubheading =
              (selectedSubheading ?? newSubheadingName).trim();
          late final num insertOrder;
          if (selectedRowType == 'item') {
            final finalMinorCode =
                (hasMinor
                    ? newMinorCode.trim().toLowerCase()
                    : inferMinorCodeFromBoqCode(code));
            insertOrder = await _computeInsertOrderInSection(
              boqRef: boqRef,
              billCode: selectedBillCode,
              subheading: finalSubheading,
              minorCode: finalMinorCode,
            );
          } else {
            double orderOf(Map<String, dynamic> row) =>
                row['order'] is num
                    ? (row['order'] as num).toDouble()
                    : double.tryParse('${row['order']}') ?? 0;
            final scoped =
                allBoqDocs.where((row) {
                  if (s(row['billCode']).trim() != selectedBillCode) {
                    return false;
                  }
                  if (selectedRowType == 'minor') {
                    return s(row['subheading']).trim() == finalSubheading;
                  }
                  return true;
                }).toList();
            final lastOrder = scoped.fold<double>(0, (value, row) {
              final rowOrder = orderOf(row);
              return rowOrder > value ? rowOrder : value;
            });
            final laterOrders =
                allBoqDocs
                    .map(orderOf)
                    .where((value) => value > lastOrder)
                    .toList()
                  ..sort();
            insertOrder =
                laterOrders.isEmpty
                    ? lastOrder + 0.001
                    : (lastOrder + laterOrders.first) / 2;
          }

          patch.removeWhere((k, v) => v is FieldValue);
          final displayCode = code.trim();
          if (selectedRowType == 'item') {
            patch['displayCode'] = displayCode;
            patch['resolvedBoqCode'] = measurementBoqCode;
          }
          await boqRef.add({
            ...patch,
            'order': insertOrder,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        final context = editorDialogContext;
        if (context != null && context.mounted) {
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        print(e.toString());
        setStateDialog(() {
          isSaving = false;
          errorText = 'Failed to save BOQ item: $e';
        });
      }
    }

    // -----------------------------
    // DIALOG UI
    // -----------------------------
    final rootContext = Get.context;
    if (rootContext == null || !rootContext.mounted) return false;

    final result = await showDialog<bool>(
      context: rootContext,
      barrierDismissible: !isSaving,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (ctx, setStateDialog) {
              editorDialogContext = dialogContext;
              // Build subheading list ONLY from existing BOQ in ADD mode
              final usedSubs =
                  existingSubheadingsByBill[selectedBillCode] ?? <String>{};
              final subOptions = usedSubs.toList()..sort();

              if (!isEdit && selectedRowType == 'item') {
                // force selectedSubheading valid
                if (selectedSubheading == null && subOptions.isNotEmpty) {
                  selectedSubheading = subOptions.first;
                }
                if (selectedSubheading != null &&
                    selectedSubheading!.trim().isNotEmpty &&
                    !subOptions.contains(selectedSubheading)) {
                  selectedSubheading =
                      subOptions.isNotEmpty ? subOptions.first : null;
                }
              }

              // minors for selected bill/sub
              final billSubKey =
                  '$selectedBillCode|${selectedSubheading ?? ''}';
              final usedMinors =
                  existingMinorsByBillSub[billSubKey] ?? <String>{};
              final minorOptions =
                  usedMinors.toList()
                    ..removeWhere((x) => x.trim().isEmpty)
                    ..sort();

              // If ADD and section has minors -> default to first minor
              if (!isEdit &&
                  selectedRowType == 'item' &&
                  minorOptions.isNotEmpty) {
                hasMinor = true;
                selectedMinorPacked ??= minorOptions.first;
                final parts = selectedMinorPacked!.split('::');
                newMinorCode =
                    (parts.isNotEmpty ? parts[0] : 'i').trim().toLowerCase();
                minorHeadingController.text =
                    (parts.length > 1 ? parts[1] : '').trim();
              }

              // if ADD and no minors -> force off
              if (!isEdit &&
                  selectedRowType == 'item' &&
                  minorOptions.isEmpty) {
                hasMinor = false;
                selectedMinorPacked = null;
                newMinorCode = 'i';
                minorHeadingController.text = '';
              }

              // ensure auto code updated when key selectors change (ADD mode)
              if (!isEdit && selectedRowType == 'item') {
                // keep code in sync (but avoid infinite loops)
                final next = _autoNextItemCode();
                if (codeController.text.trim() != next.trim()) {
                  codeController.text = next.trim();
                }
              }

              return AlertDialog(
                backgroundColor: const Color(0xFFF8FAFC),
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                titlePadding: EdgeInsets.zero,
                contentPadding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
                actionsPadding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
                title: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 22,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF17366F), Color(0xFF1769EA)],
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.22),
                          ),
                        ),
                        child: const Icon(
                          Icons.receipt_long_outlined,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEdit ? 'Edit BOQ row' : 'Create BOQ row',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              isEdit
                                  ? 'Correct the row type, hierarchy, description, and pricing'
                                  : 'Create an item, ${subheadingTerm.toLowerCase()}, or minor heading',
                              style: const TextStyle(color: Color(0xFFD8E6FF)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed:
                            isSaving
                                ? null
                                : () => Navigator.of(dialogContext).pop(false),
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                content: SizedBox(
                  width: 980,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isEdit && !_canAddMissingItem()) ...[
                          const Text(
                            'No existing BOQ sections found.',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Import from Excel or apply an Admin template first.\n'
                            'Then you can add missing items inside an existing '
                            '$billTerm/$subheadingTerm/Minor.',
                          ),
                          const SizedBox(height: 12),
                        ],

                        ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.account_tree_outlined,
                                      color: Color(0xFF1769EA),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Row classification',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  isEdit
                                      ? 'Change a row between a ${billTerm.toLowerCase()} heading, ${subheadingTerm.toLowerCase()}, minor heading, or measurable BOQ item.'
                                      : 'Choose the kind of BOQ row to create.',
                                  style: TextStyle(color: Color(0xFF667085)),
                                ),
                                const SizedBox(height: 14),
                                DropdownButtonFormField<String>(
                                  value: selectedRowType,
                                  decoration: const InputDecoration(
                                    labelText: 'This row is a',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(
                                      Icons.format_list_bulleted,
                                    ),
                                  ),
                                  items:
                                      editableRowTypes.entries
                                          .where(
                                            (entry) =>
                                                isEdit || entry.key != 'bill',
                                          )
                                          .map(
                                            (entry) => DropdownMenuItem(
                                              value: entry.key,
                                              child: Text(entry.value),
                                            ),
                                          )
                                          .toList(),
                                  onChanged:
                                      isSaving
                                          ? null
                                          : (value) {
                                            if (value == null) return;
                                            setStateDialog(() {
                                              selectedRowType = value;
                                              errorText = null;
                                              if (!isEdit) {
                                                if (value == 'item') {
                                                  codeController.text =
                                                      _autoNextItemCode();
                                                } else if (value == 'minor') {
                                                  codeController.text = 'i';
                                                } else {
                                                  codeController.clear();
                                                }
                                              }
                                            });
                                          },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],

                        const Text(
                          'Structure / building:',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<String>(
                          value:
                              selectedStructure ??
                              (structuresList.isNotEmpty
                                  ? structuresList.first
                                  : null),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                          items:
                              structuresList
                                  .map(
                                    (x) => DropdownMenuItem(
                                      value: x,
                                      child: Text(x),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              (isSaving || (!isEdit))
                                  ? null // ✅ ADD mode: must select existing, no new structure
                                  : (val) {
                                    if (val == null) return;
                                    setStateDialog(() {
                                      touchedStructure = true;
                                      selectedStructure = val;
                                      newStructureName = '';
                                    });
                                  },
                        ),

                        const SizedBox(height: 12),
                        Text(
                          isCivilBoq ? 'Series:' : 'Bill No.:',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<String>(
                          value: selectedBillCode,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                          items:
                              (existingBillsByCode.keys.toList()..sort())
                                  .map(
                                    (k) => DropdownMenuItem(
                                      value: k,
                                      child: Text(
                                        existingBillsByCode[k] ??
                                            '$billTerm $k',
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              isSaving
                                  ? null
                                  : (val) {
                                    if (val == null) return;
                                    setStateDialog(() {
                                      touchedBill = true;
                                      selectedBillCode = val;

                                      // reset subheading
                                      final subs =
                                          existingSubheadingsByBill[val] ??
                                          <String>{};
                                      selectedSubheading =
                                          subs.isNotEmpty
                                              ? ((subs.toList()..sort()).first)
                                              : null;
                                      newSubheadingName = '';
                                      touchedSubheading = true;

                                      // reset minor
                                      final key =
                                          '$selectedBillCode|${selectedSubheading ?? ''}';
                                      final minors =
                                          existingMinorsByBillSub[key] ??
                                          <String>{};
                                      if (minors.isNotEmpty) {
                                        hasMinor = true;
                                        selectedMinorPacked =
                                            (minors.toList()..sort()).first;
                                        final parts = selectedMinorPacked!
                                            .split('::');
                                        newMinorCode =
                                            (parts.isNotEmpty ? parts[0] : 'i')
                                                .trim()
                                                .toLowerCase();
                                        minorHeadingController.text =
                                            (parts.length > 1 ? parts[1] : '')
                                                .trim();
                                      } else {
                                        hasMinor = false;
                                        selectedMinorPacked = null;
                                        newMinorCode = 'i';
                                        minorHeadingController.text = '';
                                      }

                                      if (!isEdit)
                                        _regenAutoCode(setStateDialog);
                                    });
                                  },
                        ),

                        const SizedBox(height: 12),
                        if (selectedRowType == 'item' ||
                            selectedRowType == 'minor') ...[
                          Text(
                            selectedRowType == 'minor'
                                ? '${isCivilBoq ? 'Parent section / sub-series' : 'Parent subheading'}:'
                                : '$subheadingTerm:',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<String>(
                            value: selectedSubheading,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            items:
                                subOptions
                                    .map(
                                      (x) => DropdownMenuItem(
                                        value: x,
                                        child: Text(x),
                                      ),
                                    )
                                    .toList(),
                            onChanged:
                                isSaving
                                    ? null
                                    : (val) {
                                      if (val == null) return;
                                      setStateDialog(() {
                                        touchedSubheading = true;
                                        selectedSubheading = val;
                                        newSubheadingName = '';

                                        // reset minor for this sub
                                        final key = '$selectedBillCode|$val';
                                        final minors =
                                            existingMinorsByBillSub[key] ??
                                            <String>{};
                                        if (minors.isNotEmpty) {
                                          hasMinor = true;
                                          selectedMinorPacked =
                                              (minors.toList()..sort()).first;
                                          final parts = selectedMinorPacked!
                                              .split('::');
                                          newMinorCode =
                                              (parts.isNotEmpty
                                                      ? parts[0]
                                                      : 'i')
                                                  .trim()
                                                  .toLowerCase();
                                          minorHeadingController.text =
                                              (parts.length > 1 ? parts[1] : '')
                                                  .trim();
                                        } else {
                                          hasMinor = false;
                                          selectedMinorPacked = null;
                                          newMinorCode = 'i';
                                          minorHeadingController.text = '';
                                        }

                                        if (!isEdit)
                                          _regenAutoCode(setStateDialog);
                                      });
                                    },
                          ),
                          const SizedBox(height: 12),
                        ],

                        // MINOR (only show if this section actually has minors)
                        if (selectedRowType == 'item' &&
                            minorOptions.isNotEmpty) ...[
                          Row(
                            children: [
                              Checkbox(
                                value: hasMinor,
                                onChanged:
                                    (isSaving)
                                        ? null
                                        : (v) {
                                          setStateDialog(() {
                                            touchedMinor = true;
                                            hasMinor = v ?? false;
                                            if (!hasMinor) {
                                              selectedMinorPacked = null;
                                              newMinorCode = 'i';
                                              minorHeadingController.text = '';
                                            } else {
                                              selectedMinorPacked ??=
                                                  minorOptions.first;
                                              final parts = selectedMinorPacked!
                                                  .split('::');
                                              newMinorCode =
                                                  (parts.isNotEmpty
                                                          ? parts[0]
                                                          : 'i')
                                                      .trim()
                                                      .toLowerCase();
                                              minorHeadingController.text =
                                                  (parts.length > 1
                                                          ? parts[1]
                                                          : '')
                                                      .trim();
                                            }
                                            if (!isEdit)
                                              _regenAutoCode(setStateDialog);
                                          });
                                        },
                              ),
                              const Expanded(
                                child: Text(
                                  'Has minor heading?',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          if (hasMinor) ...[
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: selectedMinorPacked,
                              decoration: const InputDecoration(
                                labelText: 'Minor heading',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  minorOptions.map((p) {
                                    final parts = p.split('::');
                                    final c =
                                        parts.isNotEmpty ? parts[0].trim() : '';
                                    final h =
                                        parts.length > 1 ? parts[1].trim() : '';
                                    final label =
                                        (c.isNotEmpty && h.isNotEmpty)
                                            ? '($c) $h'
                                            : (c.isNotEmpty ? '($c)' : h);
                                    return DropdownMenuItem(
                                      value: p,
                                      child: Tooltip(
                                        message: label,
                                        child: Text(
                                          label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                              selectedItemBuilder:
                                  (context) =>
                                      minorOptions.map((p) {
                                        final parts = p.split('::');
                                        final code =
                                            parts.isNotEmpty
                                                ? parts[0].trim()
                                                : '';
                                        final heading =
                                            parts.length > 1
                                                ? parts[1].trim()
                                                : '';
                                        final label =
                                            (code.isNotEmpty &&
                                                    heading.isNotEmpty)
                                                ? '($code) $heading'
                                                : (code.isNotEmpty
                                                    ? '($code)'
                                                    : heading);
                                        return Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(),
                              onChanged:
                                  isSaving
                                      ? null
                                      : (val) {
                                        if (val == null) return;
                                        setStateDialog(() {
                                          touchedMinor = true;
                                          selectedMinorPacked = val;
                                          final parts = val.split('::');
                                          newMinorCode =
                                              (parts.isNotEmpty
                                                      ? parts[0]
                                                      : 'i')
                                                  .trim()
                                                  .toLowerCase();
                                          minorHeadingController.text =
                                              (parts.length > 1 ? parts[1] : '')
                                                  .trim();

                                          if (!isEdit)
                                            _regenAutoCode(setStateDialog);
                                        });
                                      },
                            ),
                          ],
                          const SizedBox(height: 12),
                        ],

                        // ✅ AUTO ITEM CODE (ADD mode)
                        TextField(
                          controller: codeController,
                          enabled:
                              !isSaving &&
                              (isEdit || selectedRowType != 'item'),
                          readOnly: !isEdit && selectedRowType == 'item',
                          decoration: InputDecoration(
                            labelText:
                                selectedRowType == 'item'
                                    ? 'Item code'
                                    : '${editableRowTypes[selectedRowType]} code',
                            helperText:
                                isEdit
                                    ? 'Edit mode: you can change code'
                                    : selectedRowType != 'item'
                                    ? 'Enter the heading code'
                                    : 'Auto-generated from last item in the selected section',
                            suffixIcon:
                                (!isEdit &&
                                        selectedRowType == 'item' &&
                                        !isSaving)
                                    ? IconButton(
                                      tooltip: 'Regenerate',
                                      icon: const Icon(Icons.refresh),
                                      onPressed:
                                          () => _regenAutoCode(setStateDialog),
                                    )
                                    : null,
                            border: const OutlineInputBorder(),
                          ),
                        ),

                        const SizedBox(height: 8),
                        TextField(
                          controller: descController,
                          enabled: !isSaving,
                          decoration: InputDecoration(
                            labelText:
                                selectedRowType == 'item'
                                    ? 'Description'
                                    : '${editableRowTypes[selectedRowType]} title',
                            border: const OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 8),

                        if (selectedRowType == 'item') ...[
                          DropdownButtonFormField<String>(
                            value: selectedUnit,
                            decoration: const InputDecoration(
                              labelText: 'Unit',
                              border: OutlineInputBorder(),
                            ),
                            items:
                                unitOptions
                                    .map(
                                      (u) => DropdownMenuItem(
                                        value: u,
                                        child: Text(displayUnit(u)),
                                      ),
                                    )
                                    .toList(),
                            onChanged:
                                isSaving
                                    ? null
                                    : (val) {
                                      if (val == null) return;
                                      setStateDialog(() => selectedUnit = val);
                                    },
                          ),

                          const SizedBox(height: 10),

                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: useQtyOverride,
                            onChanged:
                                isSaving
                                    ? null
                                    : (v) => setStateDialog(() {
                                      useQtyOverride = v ?? false;
                                      if (!useQtyOverride)
                                        qtyOverrideCtrl.text = '';
                                    }),
                            title: const Text(
                              'Manual qty override (use instead of takeoff qty)',
                            ),
                            subtitle: const Text(
                              'Your BOQ table qty is computed from measurements by boqCode.',
                            ),
                          ),
                          if (useQtyOverride) ...[
                            TextField(
                              controller: qtyOverrideCtrl,
                              enabled: !isSaving,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Qty override',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (_) => setStateDialog(() {}),
                            ),
                            const SizedBox(height: 8),
                          ],

                          TextField(
                            controller: rateController,
                            enabled: !isSaving,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Rate (optional)',
                            ),
                            onChanged: (_) => setStateDialog(() {}),
                          ),

                          const SizedBox(height: 8),
                          if (useQtyOverride &&
                              rateController.text.trim().isNotEmpty) ...[
                            InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Amount (Override Qty × Rate)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              child: Text(
                                _calcAmount().toStringAsFixed(2),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],

                          if (isEdit) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFE4E7EC),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Linked BOQ item',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    linkedBoqItem == null
                                        ? 'This item is not linked to another BOQ item.'
                                        : '${itemDisplayCode(linkedBoqItem!)} • ${s(linkedBoqItem!['description'])}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF475467),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed:
                                            isSaving
                                                ? null
                                                : () async {
                                                  final picked =
                                                      await pickLinkedBoqItem(
                                                        ctx,
                                                      );
                                                  if (picked == null) return;
                                                  setStateDialog(() {
                                                    linkedBoqItem = picked;
                                                    errorText = null;
                                                  });
                                                },
                                        icon: const Icon(Icons.link_rounded),
                                        label: Text(
                                          linkedBoqItem == null
                                              ? 'Link to another BOQ item'
                                              : 'Change linked BOQ item',
                                        ),
                                      ),
                                      if (linkedBoqItem != null)
                                        TextButton.icon(
                                          onPressed:
                                              isSaving
                                                  ? null
                                                  : () => setStateDialog(
                                                    () => linkedBoqItem = null,
                                                  ),
                                          icon: const Icon(
                                            Icons.link_off_rounded,
                                          ),
                                          label: const Text('Remove link'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: updateLinked,
                              onChanged:
                                  isSaving
                                      ? null
                                      : (v) => setStateDialog(
                                        () => updateLinked = v ?? false,
                                      ),
                              title: const Text(
                                'Update linked derived measurements',
                              ),
                              subtitle: Text(
                                derivedExists
                                    ? 'Derived measurements exist for this BOQ doc id.'
                                    : 'No derived measurements found (derivedFromDocId).',
                              ),
                            ),
                          ],
                        ],

                        if (errorText != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            errorText!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ],

                        if (isSaving) ...[
                          const SizedBox(height: 12),
                          const Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Saving...'),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed:
                        isSaving
                            ? null
                            : () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed:
                        (isSaving || (!isEdit && !_canAddMissingItem()))
                            ? null
                            : () => handleSave(setStateDialog),
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ),
    );

    // dispose
    codeController.dispose();
    descController.dispose();
    rateController.dispose();
    qtyOverrideCtrl.dispose();
    minorHeadingController.dispose();

    if (result == true) {
      Get.snackbar(
        'BOQ',
        isEdit
            ? '${editableRowTypes[existingRowType] ?? 'BOQ row'} updated successfully'
            : 'BOQ item created successfully',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    return result == true;
  }

  // Future<void> showBoqItemDialog({
  //   String? existingId,
  //   Map<String, dynamic>? existingData,
  //   required CollectionReference<Map<String, dynamic>> measurementsRef,
  // }) async {
  //   final isEdit = existingId != null && existingData != null;

  //   // -----------------------------
  //   // SAFE helpers
  //   // -----------------------------
  //   String s(dynamic v) => (v ?? '').toString();

  //   double n(dynamic v) =>
  //       (v is num)
  //           ? v.toDouble()
  //           : double.tryParse((v ?? '').toString()) ?? 0.0;

  //   bool isRoman(String x) =>
  //       RegExp(r'^[ivxlcdm]+$', caseSensitive: false).hasMatch(x.trim());

  //   bool isLetter(String x) => RegExp(r'^[A-Za-z]$').hasMatch(x.trim());

  //   List<String> parenTokens(String code) {
  //     return RegExp(r'\(([^)]+)\)')
  //         .allMatches(code)
  //         .map((m) => (m.group(1) ?? '').trim())
  //         .where((t) => t.isNotEmpty)
  //         .toList();
  //   }

  //   /// For 3.7(i)(A)(i) -> "i"
  //   /// For 3.1(B)(i) -> "" (no minor group)
  //   String inferMinorCodeFromBoqCode(String boqCode) {
  //     final toks = parenTokens(boqCode);
  //     if (toks.length >= 2 && isRoman(toks[0]) && isLetter(toks[1])) {
  //       return toks[0].toLowerCase();
  //     }
  //     return '';
  //   }

  //   String displayUnit(String u) => u == 'm2' ? 'm²' : (u == 'm3' ? 'm³' : u);

  //   // -----------------------------
  //   // (OPTIONAL) Recompute derived measurements linked to this BOQ doc
  //   // -----------------------------
  //   Future<void> _recomputeDerivedMeasurementsForSource({
  //     required String sourceDocId,
  //     required double newSourceValue,
  //   }) async {
  //     final fs = FirebaseFirestore.instance;
  //     final now = FieldValue.serverTimestamp();

  //     final snap =
  //         await measurementsRef
  //             .where('isDerived', isEqualTo: true)
  //             .where('derivedFromMode', isEqualTo: 'doc')
  //             .where('derivedFromDocId', isEqualTo: sourceDocId)
  //             .get();

  //     WriteBatch batch = fs.batch();
  //     int ops = 0;

  //     for (final d in snap.docs) {
  //       final m = d.data();

  //       final rule = (m['derivedRule'] ?? 'linear').toString().toLowerCase();
  //       final factor = n(m['derivedFactor']);
  //       final offset = n(m['derivedOffset']);

  //       double newValue = n(m['value']); // fallback
  //       if (rule == 'linear') {
  //         newValue = (newSourceValue * factor) + offset;
  //       }

  //       batch.update(d.reference, {
  //         'value': newValue,
  //         'updatedAt': now,
  //         'sourceValue': newSourceValue, // audit
  //       });

  //       ops++;
  //       if (ops >= 450) {
  //         await batch.commit();
  //         batch = fs.batch();
  //         ops = 0;
  //       }
  //     }

  //     if (ops > 0) await batch.commit();
  //   }

  //   // -----------------------------
  //   // Load existing structures + subheadings + minors
  //   // -----------------------------
  //   final existingStructures = <String>{};
  //   final existingSubheadingsByBill = <String, Set<String>>{};
  //   final existingMinorsByBillSub = <String, Set<String>>{};

  //   const Map<String, List<String>> kStandardSubheadingsByBill = {
  //     '3': [
  //       'Excavation works',
  //       'Backfills',
  //       'Disposal',
  //       'Hardcore',
  //       'Anti-termite treatment',
  //       'Concrete works',
  //       'DPM',
  //       'DPC',
  //       'Formwork',
  //       'Reinforcements',
  //     ],
  //     '4': ['Concrete works', 'Formworks', 'Reinforcements'],
  //     '5': ['Concrete works', 'Formworks', 'Reinforcements', 'Balustade'],
  //     '6': ['Concrete', 'Blockworks'],
  //     '7': ['Roof Coverings', 'Roof Structure'],
  //     '8': ['Frames', 'Doors', 'Iron Mongeries', 'Glass', 'Grills'],
  //     '9': ['Aluminium', 'Grills'],
  //     '10': [
  //       'Floor Finish',
  //       'Wall Finish',
  //       'Ceiling Finish',
  //       'Painting & Decoration',
  //     ],
  //   };

  //   try {
  //     final snap = await boqRef.get();
  //     for (final d in snap.docs) {
  //       final data = d.data();

  //       final structure = s(data['structure']).trim();
  //       if (structure.isNotEmpty) existingStructures.add(structure);

  //       final bCode = s(data['billCode']).trim();
  //       final sub = s(data['subheading']).trim();

  //       if (bCode.isNotEmpty && sub.isNotEmpty) {
  //         existingSubheadingsByBill
  //             .putIfAbsent(bCode, () => <String>{})
  //             .add(sub);

  //         final minorCode = s(data['minorCode']).trim().toLowerCase();
  //         final minorHeading = s(data['minorHeading']).trim();

  //         if (minorCode.isNotEmpty || minorHeading.isNotEmpty) {
  //           final key = '$bCode|$sub';
  //           final packed = '$minorCode::$minorHeading';
  //           existingMinorsByBillSub
  //               .putIfAbsent(key, () => <String>{})
  //               .add(packed);
  //         }
  //       }
  //     }
  //   } catch (_) {}

  //   final structuresList = existingStructures.toList()..sort();

  //   const billOptions = <Map<String, String>>[
  //     {'boqCode': '1', 'label': 'Bill 1: Preliminaries & General'},
  //     {'boqCode': '2', 'label': 'Bill 2: Demolitions & Alterations'},
  //     {'boqCode': '3', 'label': 'Bill 3: Substructure'},
  //     {'boqCode': '4', 'label': 'Bill 4: Frame'},
  //     {'boqCode': '5', 'label': 'Bill 5: Stairs'},
  //     {'boqCode': '6', 'label': 'Bill 6: Walling'},
  //     {'boqCode': '7', 'label': 'Bill 7: Roofing'},
  //     {'boqCode': '8', 'label': 'Bill 8: Doors'},
  //     {'boqCode': '9', 'label': 'Bill 9: Windows'},
  //     {'boqCode': '10', 'label': 'Bill 10: Finishing'},
  //   ];

  //   const unitOptions = <String>[
  //     'm',
  //     'm2',
  //     'm3',
  //     'kg',
  //     'tonne',
  //     'item',
  //     'PSum',
  //     'PC',
  //     'Nos',
  //   ];

  //   const minorCodeOptions = <String>[
  //     'i',
  //     'ii',
  //     'iii',
  //     'iv',
  //     'v',
  //     'vi',
  //     'vii',
  //     'viii',
  //     'ix',
  //     'x',
  //   ];

  //   // -----------------------------
  //   // initial values
  //   // -----------------------------
  //   final codeController = TextEditingController(
  //     text: s(existingData?['boqCode']),
  //   );
  //   final descController = TextEditingController(
  //     text: s(existingData?['description']),
  //   );
  //   final rateController = TextEditingController(
  //     text: s(existingData?['rate']),
  //   );

  //   // ✅ NEW: qty override (BOQ table qty is from measurements; this is manual override)
  //   final qtyOverrideCtrl = TextEditingController(
  //     text: s(existingData?['qtyOverride']).trim(),
  //   );
  //   bool useQtyOverride = qtyOverrideCtrl.text.trim().isNotEmpty;

  //   double _calcAmount() {
  //     final qOverride = double.tryParse(qtyOverrideCtrl.text.trim());
  //     final rate = double.tryParse(rateController.text.trim());
  //     if (!useQtyOverride || qOverride == null || rate == null) return 0.0;
  //     return qOverride * rate;
  //   }

  //   // Track "touched" fields (important for EDIT mode)
  //   bool touchedStructure = false;
  //   bool touchedBill = false;
  //   bool touchedSubheading = false;
  //   bool touchedMinor = false;

  //   // Structure
  //   final existingStructureValue = s(existingData?['structure']).trim();
  //   const newStructureKey = '__NEW_STRUCTURE__';

  //   String? selectedStructure =
  //       existingStructureValue.isNotEmpty ? existingStructureValue : null;
  //   String newStructureName = '';

  //   if (selectedStructure != null &&
  //       selectedStructure!.trim().isNotEmpty &&
  //       !structuresList.contains(selectedStructure)) {
  //     structuresList.add(selectedStructure!);
  //     structuresList.sort();
  //   }
  //   if (selectedStructure == null && structuresList.isNotEmpty) {
  //     selectedStructure = structuresList.first;
  //   }

  //   // Bill
  //   final existingBillCode = s(existingData?['billCode']).trim();
  //   String selectedBillCode =
  //       billOptions.any((b) => b['boqCode'] == existingBillCode)
  //           ? existingBillCode
  //           : billOptions.first['boqCode']!;

  //   // Subheading
  //   final existingSubheading = s(existingData?['subheading']).trim();
  //   const newSubheadingKey = '__NEW_SUBHEADING__';
  //   String? selectedSubheading =
  //       existingSubheading.isNotEmpty ? existingSubheading : null;
  //   String newSubheadingName = '';

  //   // Unit
  //   String selectedUnit =
  //       (() {
  //         final raw = s(existingData?['unit']).trim();
  //         if (unitOptions.contains(raw)) return raw;
  //         return 'm';
  //       })();

  //   // Minor heading (optional)
  //   const newMinorKey = '__NEW_MINOR__';
  //   final existingMinorCode =
  //       s(existingData?['minorCode']).trim().toLowerCase();
  //   final existingMinorHeading = s(existingData?['minorHeading']).trim();

  //   bool hasMinor =
  //       existingMinorCode.isNotEmpty || existingMinorHeading.isNotEmpty;
  //   String? selectedMinorPacked =
  //       hasMinor ? '$existingMinorCode::$existingMinorHeading' : null;

  //   String newMinorCode =
  //       existingMinorCode.isNotEmpty ? existingMinorCode : 'i';
  //   final minorHeadingController = TextEditingController(
  //     text: existingMinorHeading,
  //   );

  //   bool isSaving = false;
  //   String? errorText;

  //   // Derived linkage indicator + checkbox
  //   bool updateLinked = true;
  //   bool derivedExists = false;

  //   if (isEdit) {
  //     try {
  //       final q =
  //           await measurementsRef
  //               .where('isDerived', isEqualTo: true)
  //               .where('derivedFromMode', isEqualTo: 'doc')
  //               .where('derivedFromDocId', isEqualTo: existingId)
  //               .limit(1)
  //               .get();
  //       derivedExists = q.docs.isNotEmpty;
  //       updateLinked = derivedExists;
  //     } catch (_) {
  //       derivedExists = false;
  //       updateLinked = false;
  //     }
  //   }

  //   Future<void> handleSave(StateSetter setStateDialog) async {
  //     if (isSaving) return;

  //     final old = existingData ?? <String, dynamic>{};
  //     String oldS(String key) => s(old[key]).trim();

  //     final code = codeController.text.trim();
  //     if (code.isEmpty) {
  //       setStateDialog(() => errorText = 'Item code is required.');
  //       return;
  //     }

  //     final desc = descController.text.trim();

  //     // Rate
  //     final rateStr = rateController.text.trim();
  //     final double? rate = rateStr.isNotEmpty ? double.tryParse(rateStr) : null;
  //     if (rateStr.isNotEmpty && rate == null) {
  //       setStateDialog(() => errorText = 'Invalid rate number.');
  //       return;
  //     }

  //     // Qty override
  //     double? qtyOverride;
  //     if (useQtyOverride) {
  //       qtyOverride = double.tryParse(qtyOverrideCtrl.text.trim());
  //       if (qtyOverride == null || qtyOverride <= 0) {
  //         setStateDialog(() => errorText = 'Invalid qty override.');
  //         return;
  //       }
  //     }

  //     // Ensure defaults
  //     if (selectedStructure == null && structuresList.isNotEmpty) {
  //       selectedStructure = structuresList.first;
  //     }

  //     // Build subheading options
  //     final stdSubs = kStandardSubheadingsByBill[selectedBillCode] ?? const [];
  //     final usedSubs =
  //         existingSubheadingsByBill[selectedBillCode] ?? <String>{};
  //     final allSubOptions = <String>{...stdSubs, ...usedSubs}.toList()..sort();

  //     if (selectedSubheading != null &&
  //         selectedSubheading!.trim().isNotEmpty &&
  //         !allSubOptions.contains(selectedSubheading)) {
  //       allSubOptions.add(selectedSubheading!);
  //       allSubOptions.sort();
  //     }
  //     if (selectedSubheading == null && allSubOptions.isNotEmpty) {
  //       selectedSubheading = allSubOptions.first;
  //     }

  //     final patch = <String, dynamic>{
  //       'updatedAt': FieldValue.serverTimestamp(),
  //     };

  //     // core
  //     if (!isEdit || code != oldS('boqCode')) patch['boqCode'] = code;
  //     if (!isEdit || desc != oldS('description')) patch['description'] = desc;
  //     if (!isEdit || selectedUnit != oldS('unit')) patch['unit'] = selectedUnit;

  //     // rate
  //     if (!isEdit) {
  //       patch['rate'] = rate;
  //     } else {
  //       if (rateStr.isEmpty) {
  //         patch['rate'] = FieldValue.delete();
  //       } else {
  //         final oldRate = old['rate'];
  //         final oldRateStr = oldRate == null ? '' : oldRate.toString();
  //         if (rateStr != oldRateStr) patch['rate'] = rate;
  //       }
  //     }

  //     // ✅ qty override (this is what your BOQ UI can use)
  //     if (!isEdit) {
  //       if (useQtyOverride) patch['qtyOverride'] = qtyOverride;
  //     } else {
  //       if (useQtyOverride) {
  //         final oldQ = old['qtyOverride'];
  //         final oldQStr = oldQ == null ? '' : oldQ.toString();
  //         final newQStr = qtyOverride!.toString();
  //         if (oldQStr != newQStr) patch['qtyOverride'] = qtyOverride;
  //       } else {
  //         // remove override
  //         patch['qtyOverride'] = FieldValue.delete();
  //       }
  //     }

  //     // amount override (optional: only meaningful when qtyOverride and rate exist)
  //     if (useQtyOverride && rate != null) {
  //       patch['amountOverride'] = qtyOverride! * rate;
  //     } else if (isEdit) {
  //       patch['amountOverride'] = FieldValue.delete();
  //     }

  //     // Structure validation
  //     final mustValidateStructure =
  //         !isEdit || touchedStructure || oldS('structure').isEmpty;
  //     if (mustValidateStructure) {
  //       final structureName = (selectedStructure ?? newStructureName).trim();
  //       if (structureName.isEmpty) {
  //         setStateDialog(() => errorText = 'Structure name is required.');
  //         return;
  //       }
  //       if (!isEdit || structureName != oldS('structure')) {
  //         patch['structure'] = structureName;
  //       }
  //     }

  //     // Bill/Sub validation
  //     final mustValidateBillSub =
  //         !isEdit ||
  //         touchedBill ||
  //         touchedSubheading ||
  //         oldS('subheading').isEmpty ||
  //         oldS('billCode').isEmpty;

  //     if (mustValidateBillSub) {
  //       final finalSubheading =
  //           (selectedSubheading ?? newSubheadingName).trim();
  //       if (finalSubheading.isEmpty) {
  //         setStateDialog(() => errorText = 'Subheading is required.');
  //         return;
  //       }

  //       final bill = billOptions.firstWhere(
  //         (b) => b['boqCode'] == selectedBillCode,
  //       );

  //       if (!isEdit || bill['boqCode'] != oldS('billCode')) {
  //         patch['billCode'] = bill['boqCode']!;
  //       }
  //       if (!isEdit || bill['label'] != oldS('billLabel')) {
  //         patch['billLabel'] = bill['label']!;
  //       }
  //       if (!isEdit || finalSubheading != oldS('subheading')) {
  //         patch['subheading'] = finalSubheading;
  //       }
  //     }

  //     // Minor fields
  //     final mustValidateMinor = !isEdit || touchedMinor;
  //     if (mustValidateMinor) {
  //       final inferredMinor = inferMinorCodeFromBoqCode(code);

  //       String finalMinorCode = '';
  //       String finalMinorHeading = '';

  //       if (hasMinor) {
  //         finalMinorCode = newMinorCode.trim().toLowerCase();
  //         finalMinorHeading = minorHeadingController.text.trim();
  //       } else if (inferredMinor.isNotEmpty) {
  //         finalMinorCode = inferredMinor;
  //         finalMinorHeading = '';
  //       }

  //       if (finalMinorCode.isNotEmpty || finalMinorHeading.isNotEmpty) {
  //         patch['minorCode'] = finalMinorCode;
  //         patch['minorHeading'] = finalMinorHeading;
  //       } else if (isEdit) {
  //         patch['minorCode'] = FieldValue.delete();
  //         patch['minorHeading'] = FieldValue.delete();
  //       }
  //     }

  //     setStateDialog(() {
  //       isSaving = true;
  //       errorText = null;
  //     });

  //     try {
  //       if (isEdit) {
  //         await boqRef.doc(existingId!).update(patch);

  //         // Optional: propagate to derived measurement docs.
  //         // NOTE: This uses qtyOverride as the "source value" only when enabled,
  //         // because your BOQ table qty normally comes from measurements.
  //         if (updateLinked && derivedExists && useQtyOverride) {
  //           await _recomputeDerivedMeasurementsForSource(
  //             sourceDocId: existingId!,
  //             newSourceValue: qtyOverride!,
  //           );
  //         }
  //       } else {
  //         final finalSubheading =
  //             (selectedSubheading ?? newSubheadingName).trim();
  //         final finalMinorCode =
  //             (hasMinor
  //                 ? newMinorCode.trim().toLowerCase()
  //                 : inferMinorCodeFromBoqCode(code));

  //         final insertOrder = await _computeInsertOrderInSection(
  //           boqRef: boqRef,
  //           billCode: selectedBillCode,
  //           subheading: finalSubheading,
  //           minorCode: finalMinorCode,
  //         );

  //         final displayCode = code.trim();
  //         final resolvedBoqCode = bestResolvedCode(
  //           billCode: selectedBillCode,
  //           rawCode: displayCode,
  //         );
  //         await boqRef.add({
  //           ...patch,
  //           'rowType': 'item',
  //           'displayCode': displayCode,
  //           'resolvedBoqCode': resolvedBoqCode,

  //           // ✅ this is the key: place it inside its section
  //           'order': insertOrder,

  //           'createdAt': FieldValue.serverTimestamp(),
  //           // 'order': DateTime.now().millisecondsSinceEpoch,
  //           // 'createdAt': FieldValue.serverTimestamp(),
  //         });
  //       }

  //       Get.back(result: true);
  //     } catch (e) {
  //       print(e.toString());
  //       setStateDialog(() {
  //         isSaving = false;
  //         errorText = 'Failed to save BOQ item: $e';
  //       });
  //     }
  //   }

  //   final result = await Get.dialog<bool>(
  //     barrierDismissible: !isSaving,
  //     StatefulBuilder(
  //       builder: (ctx, setStateDialog) {
  //         // subheading list
  //         final stdSubs =
  //             kStandardSubheadingsByBill[selectedBillCode] ?? const [];
  //         final usedSubs =
  //             existingSubheadingsByBill[selectedBillCode] ?? <String>{};

  //         final allSubOptions =
  //             <String>{...stdSubs, ...usedSubs}.toList()..sort();

  //         if (selectedSubheading != null &&
  //             selectedSubheading!.trim().isNotEmpty &&
  //             !allSubOptions.contains(selectedSubheading)) {
  //           allSubOptions.add(selectedSubheading!);
  //           allSubOptions.sort();
  //         }
  //         if (selectedSubheading == null && allSubOptions.isNotEmpty) {
  //           selectedSubheading = allSubOptions.first;
  //         }

  //         // minor list
  //         final billSubKey = '$selectedBillCode|${selectedSubheading ?? ''}';
  //         final usedMinors = existingMinorsByBillSub[billSubKey] ?? <String>{};
  //         final minorOptions =
  //             usedMinors.toList()
  //               ..removeWhere((x) => x.trim().isEmpty)
  //               ..sort();

  //         return AlertDialog(
  //           title: Text(isEdit ? 'Edit BOQ item' : 'Add BOQ item'),
  //           content: SingleChildScrollView(
  //             child: Column(
  //               mainAxisSize: MainAxisSize.min,
  //               crossAxisAlignment: CrossAxisAlignment.start,
  //               children: [
  //                 const Text(
  //                   'Structure / building:',
  //                   style: TextStyle(fontWeight: FontWeight.w600),
  //                 ),
  //                 const SizedBox(height: 4),
  //                 DropdownButtonFormField<String>(
  //                   value:
  //                       selectedStructure ??
  //                       (structuresList.isNotEmpty
  //                           ? structuresList.first
  //                           : newStructureKey),
  //                   decoration: const InputDecoration(
  //                     border: OutlineInputBorder(),
  //                   ),
  //                   items: [
  //                     ...structuresList.map(
  //                       (x) => DropdownMenuItem(value: x, child: Text(x)),
  //                     ),
  //                     const DropdownMenuItem(
  //                       value: newStructureKey,
  //                       child: Text('+ New building / structure...'),
  //                     ),
  //                   ],
  //                   onChanged:
  //                       isSaving
  //                           ? null
  //                           : (val) {
  //                             if (val == null) return;
  //                             setStateDialog(() {
  //                               touchedStructure = true;
  //                               if (val == newStructureKey) {
  //                                 selectedStructure = null;
  //                               } else {
  //                                 selectedStructure = val;
  //                                 newStructureName = '';
  //                               }
  //                             });
  //                           },
  //                 ),
  //                 if (selectedStructure == null)
  //                   Padding(
  //                     padding: const EdgeInsets.only(top: 8.0),
  //                     child: TextField(
  //                       enabled: !isSaving,
  //                       decoration: const InputDecoration(
  //                         labelText: 'New structure name',
  //                         border: OutlineInputBorder(),
  //                       ),
  //                       onChanged: (val) {
  //                         touchedStructure = true;
  //                         newStructureName = val;
  //                       },
  //                     ),
  //                   ),
  //                 const SizedBox(height: 12),

  //                 const Text(
  //                   'Bill No.:',
  //                   style: TextStyle(fontWeight: FontWeight.w600),
  //                 ),
  //                 const SizedBox(height: 4),
  //                 DropdownButtonFormField<String>(
  //                   value: selectedBillCode,
  //                   decoration: const InputDecoration(
  //                     border: OutlineInputBorder(),
  //                   ),
  //                   items:
  //                       billOptions
  //                           .map(
  //                             (b) => DropdownMenuItem(
  //                               value: b['boqCode'],
  //                               child: Text(b['label']!),
  //                             ),
  //                           )
  //                           .toList(),
  //                   onChanged:
  //                       isSaving
  //                           ? null
  //                           : (val) {
  //                             if (val == null) return;
  //                             setStateDialog(() {
  //                               touchedBill = true;
  //                               selectedBillCode = val;

  //                               selectedSubheading = null;
  //                               newSubheadingName = '';
  //                               touchedSubheading = true;

  //                               hasMinor = false;
  //                               selectedMinorPacked = null;
  //                               newMinorCode = 'i';
  //                               minorHeadingController.text = '';
  //                               touchedMinor = true;
  //                             });
  //                           },
  //                 ),
  //                 const SizedBox(height: 12),

  //                 const Text(
  //                   'Subheading:',
  //                   style: TextStyle(fontWeight: FontWeight.w600),
  //                 ),
  //                 const SizedBox(height: 4),
  //                 DropdownButtonFormField<String>(
  //                   value:
  //                       selectedSubheading ??
  //                       (allSubOptions.isNotEmpty
  //                           ? allSubOptions.first
  //                           : newSubheadingKey),
  //                   decoration: const InputDecoration(
  //                     border: OutlineInputBorder(),
  //                   ),
  //                   items: [
  //                     ...allSubOptions.map(
  //                       (x) => DropdownMenuItem(value: x, child: Text(x)),
  //                     ),
  //                     const DropdownMenuItem(
  //                       value: newSubheadingKey,
  //                       child: Text('+ New subheading...'),
  //                     ),
  //                   ],
  //                   onChanged:
  //                       isSaving
  //                           ? null
  //                           : (val) {
  //                             if (val == null) return;
  //                             setStateDialog(() {
  //                               touchedSubheading = true;
  //                               if (val == newSubheadingKey) {
  //                                 selectedSubheading = null;
  //                               } else {
  //                                 selectedSubheading = val;
  //                                 newSubheadingName = '';
  //                               }

  //                               hasMinor = false;
  //                               selectedMinorPacked = null;
  //                               newMinorCode = 'i';
  //                               minorHeadingController.text = '';
  //                               touchedMinor = true;
  //                             });
  //                           },
  //                 ),
  //                 if (selectedSubheading == null)
  //                   Padding(
  //                     padding: const EdgeInsets.only(top: 8.0),
  //                     child: TextField(
  //                       enabled: !isSaving,
  //                       decoration: const InputDecoration(
  //                         labelText: 'New subheading',
  //                         border: OutlineInputBorder(),
  //                       ),
  //                       onChanged: (val) {
  //                         touchedSubheading = true;
  //                         newSubheadingName = val;
  //                       },
  //                     ),
  //                   ),
  //                 const SizedBox(height: 12),

  //                 // MINOR
  //                 Row(
  //                   children: [
  //                     Checkbox(
  //                       value: hasMinor,
  //                       onChanged:
  //                           isSaving
  //                               ? null
  //                               : (v) {
  //                                 setStateDialog(() {
  //                                   touchedMinor = true;
  //                                   hasMinor = v ?? false;
  //                                   if (!hasMinor) {
  //                                     selectedMinorPacked = null;
  //                                     newMinorCode = 'i';
  //                                     minorHeadingController.text = '';
  //                                   }
  //                                 });
  //                               },
  //                     ),
  //                     const Expanded(
  //                       child: Text(
  //                         'Has minor heading? (e.g. (i) Normal; Grade 15)',
  //                         style: TextStyle(fontWeight: FontWeight.w600),
  //                       ),
  //                     ),
  //                   ],
  //                 ),
  //                 if (hasMinor) ...[
  //                   DropdownButtonFormField<String>(
  //                     value:
  //                         selectedMinorPacked ??
  //                         (minorOptions.isNotEmpty
  //                             ? minorOptions.first
  //                             : newMinorKey),
  //                     decoration: const InputDecoration(
  //                       labelText: 'Minor heading',
  //                       border: OutlineInputBorder(),
  //                     ),
  //                     items: [
  //                       ...minorOptions.map((p) {
  //                         final parts = p.split('::');
  //                         final c = parts.isNotEmpty ? parts[0].trim() : '';
  //                         final h = parts.length > 1 ? parts[1].trim() : '';
  //                         final label =
  //                             (c.isNotEmpty && h.isNotEmpty)
  //                                 ? '($c) $h'
  //                                 : (c.isNotEmpty ? '($c)' : h);
  //                         return DropdownMenuItem(value: p, child: Text(label));
  //                       }),
  //                       const DropdownMenuItem(
  //                         value: newMinorKey,
  //                         child: Text('+ New minor heading...'),
  //                       ),
  //                     ],
  //                     onChanged:
  //                         isSaving
  //                             ? null
  //                             : (val) {
  //                               if (val == null) return;
  //                               setStateDialog(() {
  //                                 touchedMinor = true;
  //                                 if (val == newMinorKey) {
  //                                   selectedMinorPacked = null;
  //                                   newMinorCode = 'i';
  //                                   minorHeadingController.text = '';
  //                                 } else {
  //                                   selectedMinorPacked = val;
  //                                   final parts = val.split('::');
  //                                   newMinorCode =
  //                                       (parts.isNotEmpty ? parts[0] : 'i')
  //                                           .trim()
  //                                           .toLowerCase();
  //                                   minorHeadingController.text =
  //                                       (parts.length > 1 ? parts[1] : '')
  //                                           .trim();
  //                                 }
  //                               });
  //                             },
  //                   ),
  //                   const SizedBox(height: 8),
  //                   DropdownButtonFormField<String>(
  //                     value:
  //                         minorCodeOptions.contains(newMinorCode)
  //                             ? newMinorCode
  //                             : 'i',
  //                     decoration: const InputDecoration(
  //                       labelText: 'Minor code (i, ii, ...)',
  //                       border: OutlineInputBorder(),
  //                     ),
  //                     items:
  //                         minorCodeOptions
  //                             .map(
  //                               (c) =>
  //                                   DropdownMenuItem(value: c, child: Text(c)),
  //                             )
  //                             .toList(),
  //                     onChanged:
  //                         isSaving
  //                             ? null
  //                             : (val) => setStateDialog(() {
  //                               touchedMinor = true;
  //                               newMinorCode = (val ?? 'i');
  //                             }),
  //                   ),
  //                   const SizedBox(height: 8),
  //                   TextField(
  //                     controller: minorHeadingController,
  //                     enabled: !isSaving,
  //                     decoration: const InputDecoration(
  //                       labelText: 'Minor heading title (optional)',
  //                       border: OutlineInputBorder(),
  //                       hintText: 'e.g. Normal; Grade 15',
  //                     ),
  //                     onChanged: (_) => touchedMinor = true,
  //                   ),
  //                 ],
  //                 const SizedBox(height: 12),

  //                 TextField(
  //                   controller: codeController,
  //                   enabled: !isSaving,
  //                   decoration: const InputDecoration(
  //                     labelText: 'Item code',
  //                     hintText: 'e.g. 3.7(i)(A)(i)',
  //                   ),
  //                 ),
  //                 const SizedBox(height: 8),

  //                 TextField(
  //                   controller: descController,
  //                   enabled: !isSaving,
  //                   decoration: const InputDecoration(labelText: 'Description'),
  //                   maxLines: 2,
  //                 ),
  //                 const SizedBox(height: 8),

  //                 DropdownButtonFormField<String>(
  //                   value: selectedUnit,
  //                   decoration: const InputDecoration(
  //                     labelText: 'Unit',
  //                     border: OutlineInputBorder(),
  //                   ),
  //                   items:
  //                       unitOptions
  //                           .map(
  //                             (u) => DropdownMenuItem(
  //                               value: u,
  //                               child: Text(displayUnit(u)),
  //                             ),
  //                           )
  //                           .toList(),
  //                   onChanged:
  //                       isSaving
  //                           ? null
  //                           : (val) {
  //                             if (val == null) return;
  //                             setStateDialog(() => selectedUnit = val);
  //                           },
  //                 ),
  //                 const SizedBox(height: 10),

  //                 // ✅ manual qty override
  //                 CheckboxListTile(
  //                   contentPadding: EdgeInsets.zero,
  //                   value: useQtyOverride,
  //                   onChanged:
  //                       isSaving
  //                           ? null
  //                           : (v) => setStateDialog(() {
  //                             useQtyOverride = v ?? false;
  //                             if (!useQtyOverride) qtyOverrideCtrl.text = '';
  //                           }),
  //                   title: const Text(
  //                     'Manual qty override (use instead of takeoff qty)',
  //                   ),
  //                   subtitle: const Text(
  //                     'Your BOQ table qty is computed from measurements by boqCode.',
  //                   ),
  //                 ),
  //                 if (useQtyOverride) ...[
  //                   TextField(
  //                     controller: qtyOverrideCtrl,
  //                     enabled: !isSaving,
  //                     keyboardType: const TextInputType.numberWithOptions(
  //                       decimal: true,
  //                     ),
  //                     decoration: const InputDecoration(
  //                       labelText: 'Qty override',
  //                       border: OutlineInputBorder(),
  //                       isDense: true,
  //                     ),
  //                     onChanged: (_) => setStateDialog(() {}),
  //                   ),
  //                   const SizedBox(height: 8),
  //                 ],

  //                 TextField(
  //                   controller: rateController,
  //                   enabled: !isSaving,
  //                   keyboardType: const TextInputType.numberWithOptions(
  //                     decimal: true,
  //                   ),
  //                   decoration: const InputDecoration(
  //                     labelText: 'Rate (optional)',
  //                   ),
  //                   onChanged: (_) => setStateDialog(() {}),
  //                 ),

  //                 const SizedBox(height: 8),

  //                 // amount override display (only meaningful when qtyOverride + rate)
  //                 if (useQtyOverride &&
  //                     rateController.text.trim().isNotEmpty) ...[
  //                   InputDecorator(
  //                     decoration: const InputDecoration(
  //                       labelText: 'Amount (Override Qty × Rate)',
  //                       border: OutlineInputBorder(),
  //                       isDense: true,
  //                     ),
  //                     child: Text(
  //                       _calcAmount().toStringAsFixed(2),
  //                       style: const TextStyle(fontWeight: FontWeight.w700),
  //                     ),
  //                   ),
  //                   const SizedBox(height: 8),
  //                 ],

  //                 // derived linkage checkbox (edit mode)
  //                 if (isEdit) ...[
  //                   CheckboxListTile(
  //                     contentPadding: EdgeInsets.zero,
  //                     value: updateLinked,
  //                     onChanged:
  //                         isSaving
  //                             ? null
  //                             : (v) => setStateDialog(
  //                               () => updateLinked = v ?? false,
  //                             ),
  //                     title: const Text('Update linked derived measurements'),
  //                     subtitle: Text(
  //                       derivedExists
  //                           ? 'Derived measurements exist for this BOQ doc id.'
  //                           : 'No derived measurements found (derivedFromDocId).',
  //                     ),
  //                   ),
  //                 ],

  //                 if (errorText != null) ...[
  //                   const SizedBox(height: 10),
  //                   Text(
  //                     errorText!,
  //                     style: const TextStyle(color: Colors.red, fontSize: 12),
  //                   ),
  //                 ],

  //                 if (isSaving) ...[
  //                   const SizedBox(height: 12),
  //                   const Row(
  //                     children: [
  //                       SizedBox(
  //                         width: 16,
  //                         height: 16,
  //                         child: CircularProgressIndicator(strokeWidth: 2),
  //                       ),
  //                       SizedBox(width: 8),
  //                       Text('Saving...'),
  //                     ],
  //                   ),
  //                 ],
  //               ],
  //             ),
  //           ),
  //           actions: [
  //             TextButton(
  //               onPressed: isSaving ? null : () => Get.back(result: false),
  //               child: const Text('Cancel'),
  //             ),
  //             FilledButton(
  //               onPressed: isSaving ? null : () => handleSave(setStateDialog),
  //               child: const Text('Save'),
  //             ),
  //           ],
  //         );
  //       },
  //     ),
  //   );

  //   // dispose
  //   codeController.dispose();
  //   descController.dispose();
  //   rateController.dispose();
  //   qtyOverrideCtrl.dispose();
  //   minorHeadingController.dispose();

  //   if (result == true) {
  //     Get.snackbar(
  //       'BOQ',
  //       isEdit
  //           ? 'BOQ item updated successfully'
  //           : 'BOQ item created successfully',
  //       snackPosition: SnackPosition.BOTTOM,
  //     );
  //   }
  // }

  Future<void> exportBoqExcel({
    required String projectName,
    required String buildingName,
  }) async {
    try {
      Get.snackbar(
        'Export',
        'Preparing Excel...',
        snackPosition: SnackPosition.BOTTOM,
      );

      // ---------------- helpers ----------------
      String _s(dynamic v) => (v ?? '').toString();
      double _num(dynamic v) =>
          (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

      double _round2(double v) => double.parse(v.toStringAsFixed(2));

      int _billInt(String billCode) => int.tryParse(billCode.trim()) ?? 9999;

      // ----- Roman utilities -----
      bool _isRoman(String x) =>
          RegExp(r'^[ivxlcdm]+$', caseSensitive: false).hasMatch(x.trim());

      int _romanToInt(String s) {
        final x = s.trim().toUpperCase();
        final map = <String, int>{
          'I': 1,
          'V': 5,
          'X': 10,
          'L': 50,
          'C': 100,
          'D': 500,
          'M': 1000,
        };
        int total = 0;
        int prev = 0;
        for (int i = x.length - 1; i >= 0; i--) {
          final ch = x[i];
          final v = map[ch] ?? 0;
          if (v < prev)
            total -= v;
          else {
            total += v;
            prev = v;
          }
        }
        return total;
      }

      // compares codes like: 3.2(A)(ii) vs 3.6(A)(i) vs 3.7(i)(A)(i)
      int _cmpBoqCode(String a, String b) {
        String norm(String x) => x.replaceAll(' ', '').trim();

        // token = (typeOrder, numericValue, stringValue)
        // typeOrder: 0 number, 1 letter, 2 roman, 3 string
        List<List<dynamic>> tokenize(String raw) {
          final s = norm(raw);
          final out = <List<dynamic>>[];

          final re = RegExp(r'(\d+|[A-Za-z]+)');
          for (final m in re.allMatches(s)) {
            final t = (m.group(0) ?? '').trim();
            if (t.isEmpty) continue;

            final n = int.tryParse(t);
            if (n != null) {
              out.add([0, n, '']);
              continue;
            }

            final tl = t.toLowerCase();

            // single letter group (A, B, C...)
            if (RegExp(r'^[a-z]$').hasMatch(tl)) {
              out.add([1, tl.codeUnitAt(0), tl]);
              continue;
            }

            // roman group (i, ii, iv, x...)
            if (_isRoman(tl)) {
              out.add([2, _romanToInt(tl), tl]);
              continue;
            }

            out.add([3, 0, tl]);
          }

          return out;
        }

        final ta = tokenize(a);
        final tb = tokenize(b);
        final n = math.min(ta.length, tb.length);

        for (int i = 0; i < n; i++) {
          final A = ta[i];
          final B = tb[i];

          final typeA = A[0] as int;
          final typeB = B[0] as int;
          if (typeA != typeB) return typeA.compareTo(typeB);

          final numA = A[1] as int;
          final numB = B[1] as int;
          if (numA != numB) return numA.compareTo(numB);

          final strA = A[2] as String;
          final strB = B[2] as String;
          final c = strA.compareTo(strB);
          if (c != 0) return c;
        }

        return ta.length.compareTo(tb.length);
      }

      String _billLabelFrom(String billCode, String billLabelRaw) {
        final b = billLabelRaw.trim();
        if (b.isNotEmpty) return b;
        return 'BILL NO. $billCode';
      }

      // ---------------- Excel styles ----------------
      final cNavy = xc('FF1F4E79');
      final cWhite = xc('FFFFFFFF');
      final cLightBlue = xc('FFD9E1F2');
      final cLightYellow = xc('FFFFF2CC');
      final cLightGray = xc('FFF2F2F2');
      final cSubheading = xc('FFE7E6E6');
      final cMinor = xc('FFF8F8F8');
      final cBlack = xc('FF000000');

      xl.Border _thinBorder() =>
          xl.Border(borderStyle: xl.BorderStyle.Thin, borderColorHex: cBlack);

      xl.CellStyle _styleTitle() => xl.CellStyle(
        bold: true,
        fontColorHex: cWhite,
        backgroundColorHex: cNavy,
        horizontalAlign: xl.HorizontalAlign.Center,
        verticalAlign: xl.VerticalAlign.Center,
        topBorder: _thinBorder(),
        bottomBorder: _thinBorder(),
        leftBorder: _thinBorder(),
        rightBorder: _thinBorder(),
      );

      xl.CellStyle _styleTableHeader() => xl.CellStyle(
        bold: true,
        backgroundColorHex: cLightBlue,
        horizontalAlign: xl.HorizontalAlign.Center,
        verticalAlign: xl.VerticalAlign.Center,
        topBorder: _thinBorder(),
        bottomBorder: _thinBorder(),
        leftBorder: _thinBorder(),
        rightBorder: _thinBorder(),
      );

      xl.CellStyle _styleBillHeading() => xl.CellStyle(
        bold: true,
        backgroundColorHex: cLightGray,
        horizontalAlign: xl.HorizontalAlign.Left,
        verticalAlign: xl.VerticalAlign.Center,
        topBorder: _thinBorder(),
        bottomBorder: _thinBorder(),
        leftBorder: _thinBorder(),
        rightBorder: _thinBorder(),
      );

      xl.CellStyle _styleSubheading() => xl.CellStyle(
        bold: true,
        backgroundColorHex: cSubheading,
        horizontalAlign: xl.HorizontalAlign.Left,
        verticalAlign: xl.VerticalAlign.Center,
        topBorder: _thinBorder(),
        bottomBorder: _thinBorder(),
        leftBorder: _thinBorder(),
        rightBorder: _thinBorder(),
      );

      xl.CellStyle _styleMinor() => xl.CellStyle(
        italic: true,
        backgroundColorHex: cMinor,
        horizontalAlign: xl.HorizontalAlign.Left,
        verticalAlign: xl.VerticalAlign.Center,
        topBorder: _thinBorder(),
        bottomBorder: _thinBorder(),
        leftBorder: _thinBorder(),
        rightBorder: _thinBorder(),
      );

      xl.CellStyle _styleSubtotal() => xl.CellStyle(
        bold: true,
        backgroundColorHex: cLightYellow,
        horizontalAlign: xl.HorizontalAlign.Right,
        verticalAlign: xl.VerticalAlign.Center,
        topBorder: _thinBorder(),
        bottomBorder: _thinBorder(),
        leftBorder: _thinBorder(),
        rightBorder: _thinBorder(),
      );

      xl.CellStyle _styleNormalCell() => xl.CellStyle(
        topBorder: _thinBorder(),
        bottomBorder: _thinBorder(),
        leftBorder: _thinBorder(),
        rightBorder: _thinBorder(),
        verticalAlign: xl.VerticalAlign.Top,
        horizontalAlign: xl.HorizontalAlign.Left,
      );

      xl.CellStyle _styleNumberCell() => xl.CellStyle(
        topBorder: _thinBorder(),
        bottomBorder: _thinBorder(),
        leftBorder: _thinBorder(),
        rightBorder: _thinBorder(),
        verticalAlign: xl.VerticalAlign.Center,
        horizontalAlign: xl.HorizontalAlign.Right,
      );

      // ---------------- 1) Load BOQ docs ----------------
      final boqSnap = await boqRef.get();
      final boqDocs = boqSnap.docs;
      final boqRows =
          boqDocs
              .map(
                (doc) => <String, dynamic>{
                  'id': doc.id,
                  ...Map<String, dynamic>.from(
                    doc.data() as Map<String, dynamic>,
                  ),
                },
              )
              .toList();

      // --- bill labels map (prefer bill rows if present) ---
      final billLabelByCode = <String, String>{};
      for (final doc in boqDocs) {
        final d = doc.data() as Map<String, dynamic>;
        final rowType = _s(d['rowType']).trim().toLowerCase();
        if (rowType != 'bill') continue;

        final billCode = _s(d['billCode']).trim();
        if (billCode.isEmpty) continue;

        final billLabel = _billLabelFrom(billCode, _s(d['billLabel']));
        billLabelByCode[billCode] = billLabel;
      }

      // also capture any billCode from items even if bill-row missing
      final billCodesAll = <String>{};
      for (final doc in boqDocs) {
        final d = doc.data() as Map<String, dynamic>;
        final billCode = _s(d['billCode']).trim();
        if (billCode.isNotEmpty) billCodesAll.add(billCode);
      }

      // ---------------- 2) Load measurements ----------------
      final measSnap = await measRef.get();

      // General allowances are deliberately stored outside drawing
      // measurements so provisional work cannot be mistaken for measured work.
      final allowanceSnap =
          await FirebaseFirestore.instance
              .collection('projects')
              .doc(projectId)
              .collection('buildings')
              .doc(buildingId)
              .collection('generalAllowances')
              .get();

      // Resolve the building site so the individual BOQ summary clearly
      // identifies where the building is located. Shared site/project costs
      // are intentionally not shown in an individual building summary; they
      // belong in the consolidated project workbook.
      final projectRef = FirebaseFirestore.instance
          .collection('projects')
          .doc(projectId);
      final buildingDoc =
          await projectRef.collection('buildings').doc(buildingId).get();
      final siteId = _s(buildingDoc.data()?['siteId']).trim();
      var siteName = '';
      if (siteId.isNotEmpty) {
        final siteDoc = await projectRef.collection('sites').doc(siteId).get();
        siteName = _s(siteDoc.data()?['name']).trim();
      }

      // ---------------- 3) totalsByBoq ----------------
      String codeKey(dynamic value) =>
          _s(value).replaceAll(RegExp(r'\s+'), '').toLowerCase();
      final totalsByBoq = <String, double>{};
      final totalsByBoqItemId = <String, double>{};
      for (final d in measSnap.docs) {
        final m = d.data() as Map<String, dynamic>;
        final v = _num(m['value']);
        if (v == 0) continue;
        final itemId = _s(m['boqItemId']).trim();
        if (itemId.isNotEmpty) {
          totalsByBoqItemId.update(
            itemId,
            (quantity) => quantity + v,
            ifAbsent: () => v,
          );
          continue;
        }
        final aliases = <String>{
          codeKey(m['boqCode']),
          codeKey(m['resolvedBoqCode']),
          codeKey(m['boqCodeNorm']),
        }..removeWhere((key) => key.isEmpty);
        for (final alias in aliases) {
          totalsByBoq.update(
            alias,
            (quantity) => quantity + v,
            ifAbsent: () => v,
          );
        }
      }

      final aliasCounts = <String, int>{};
      for (final data in boqRows) {
        if (_s(data['rowType']).trim().toLowerCase() != 'item') continue;
        final aliases = <String>{
          codeKey(data['resolvedBoqCode']),
          codeKey(data['displayCode']),
          codeKey(data['boqCode']),
          codeKey(hierarchicalBoqCodeFromRows(data, boqRows)),
        }..removeWhere((key) => key.isEmpty);
        for (final alias in aliases) {
          aliasCounts.update(alias, (count) => count + 1, ifAbsent: () => 1);
        }
      }

      // ---------------- 4) Extract item rows only ----------------
      final rawItems = <Map<String, dynamic>>[];

      for (final doc in boqDocs) {
        final d = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
        final rowType = _s(d['rowType']).trim().toLowerCase();
        if (rowType != 'item') continue;

        final billCode = _s(d['billCode']).trim();
        if (billCode.isEmpty) continue;

        final billLabel =
            billLabelByCode[billCode] ??
            _billLabelFrom(billCode, _s(d['billLabel']));
        billLabelByCode[billCode] = billLabel; // cache

        final subheading = _s(d['subheading']).trim();
        final minorLabel = _s(d['minorLabel']).trim();

        final rawBoq = _s(d['boqCode']).trim();
        final resolved = _s(d['resolvedBoqCode']).trim();
        final displayCode = _s(d['displayCode']).trim();
        final itemCode = hierarchicalBoqCodeFromRows(d, boqRows);
        if (itemCode.isEmpty) continue;

        final desc = _s(d['description']).trim();
        final unit = _s(d['unit']).trim();

        final rateRaw = d['rate'];
        final rate =
            (rateRaw is num) ? rateRaw.toDouble() : double.tryParse('$rateRaw');

        var qtyComputed = totalsByBoqItemId[doc.id];
        if (qtyComputed == null) {
          final aliases = <String>{
            codeKey(itemCode),
            codeKey(resolved),
            codeKey(displayCode),
            codeKey(rawBoq),
          }..removeWhere((key) => key.isEmpty);
          for (final alias in aliases) {
            if (aliasCounts[alias] != 1) continue;
            final matched = totalsByBoq[alias];
            if (matched != null) {
              qtyComputed = matched;
              break;
            }
          }
        }
        qtyComputed ??= 0.0;

        // optional manual override at BOQ item level (for QS edit)
        final qo = d['qtyOverride'];
        final qtyOverride =
            (qo is num) ? qo.toDouble() : double.tryParse('$qo');

        final qtyUsed = qtyOverride ?? qtyComputed;

        final amount = (rate == null) ? 0.0 : qtyUsed * rate;

        // skip amount == 0 rows
        if (amount == 0.0) continue;

        rawItems.add({
          'billCode': billCode,
          'billLabel': billLabel,
          'subheading': subheading,
          'minorLabel': minorLabel,
          'itemCode': itemCode,
          'desc': desc,
          'unit': unit,
          'rate': rate,
          'qtyUsed': qtyUsed,
          'amount': amount,
        });
      }

      // ---------------- 5) Group: Bill -> Subheading -> Minor -> items ----------------
      final billMap = <String, Map<String, dynamic>>{};
      for (final it in rawItems) {
        final b = _s(it['billCode']);
        final sub = _s(it['subheading']);
        final minor = _s(it['minorLabel']);

        billMap.putIfAbsent(b, () {
          return {
            'label': _s(it['billLabel']),
            'subs': <String, Map<String, List<Map<String, dynamic>>>>{},
          };
        });

        final subs =
            billMap[b]!['subs']
                as Map<String, Map<String, List<Map<String, dynamic>>>>;

        subs.putIfAbsent(sub, () => <String, List<Map<String, dynamic>>>{});
        subs[sub]!.putIfAbsent(minor, () => <Map<String, dynamic>>[]);
        subs[sub]![minor]!.add(it);
      }

      // sort items inside each minor
      for (final b in billMap.keys) {
        final subs =
            billMap[b]!['subs']
                as Map<String, Map<String, List<Map<String, dynamic>>>>;
        for (final sub in subs.keys) {
          for (final minor in subs[sub]!.keys) {
            subs[sub]![minor]!.sort(
              (x, y) => _cmpBoqCode(_s(x['itemCode']), _s(y['itemCode'])),
            );
          }
        }
      }

      String _minCodeInSub(Map<String, List<Map<String, dynamic>>> minors) {
        String? minC;
        for (final items in minors.values) {
          for (final it in items) {
            final c = _s(it['itemCode']);
            if (minC == null || _cmpBoqCode(c, minC) < 0) minC = c;
          }
        }
        return minC ?? 'zzzz';
      }

      String _minCodeInMinor(List<Map<String, dynamic>> items) {
        if (items.isEmpty) return 'zzzz';
        String minC = _s(items.first['itemCode']);
        for (final it in items) {
          final c = _s(it['itemCode']);
          if (_cmpBoqCode(c, minC) < 0) minC = c;
        }
        return minC;
      }

      // ---------------- 6) Create Excel ----------------
      final xl.Excel excel = xl.Excel.createExcel();
      excel.rename('Sheet1', 'Summary');
      final xl.Sheet wsSum = excel['Summary'];
      final xl.Sheet wsDet = excel['BOQ Details'];

      // columns: A Item | B Description | C Unit | D Qty | E Rate | F Amount
      const int cols = 6;

      // ---- BOQ Details Title row ----
      wsDet.appendRow([
        xl.TextCellValue(''),
        xl.TextCellValue('BOQ DETAILS'),
        xl.TextCellValue(''),
        xl.TextCellValue(''),
        xl.TextCellValue(''),
        xl.TextCellValue(''),
      ]);
      for (int c = 0; c < cols; c++) {
        wsDet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
            .cellStyle = _styleTitle();
      }

      // ---- BOQ Details Header row ----
      wsDet.appendRow([
        xl.TextCellValue('Item'),
        xl.TextCellValue('Description'),
        xl.TextCellValue('Unit'),
        xl.TextCellValue('Qty'),
        xl.TextCellValue('Rate'),
        xl.TextCellValue('Amount'),
      ]);
      for (int c = 0; c < cols; c++) {
        wsDet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1))
            .cellStyle = _styleTableHeader();
      }

      int row = 2;

      // bills sorted: use all bill codes seen in BOQ docs (even if total is 0)
      final billKeysAll =
          billCodesAll.toList()
            ..sort((a, b) => _billInt(a).compareTo(_billInt(b)));

      double grandTotal = 0.0;

      // store per-bill totals for Summary (include 0 bills)
      final billTotals = <Map<String, dynamic>>[];

      // ---------------- 7) Write details with Bill subtotal ----------------
      for (final billCode in billKeysAll) {
        final label = billLabelByCode[billCode] ?? 'BILL NO. $billCode';
        final subs =
            (billMap[billCode]?['subs']
                as Map<String, Map<String, List<Map<String, dynamic>>>>?) ??
            <String, Map<String, List<Map<String, dynamic>>>>{};

        // Bill heading row (ONLY ONCE), label in column B
        wsDet.appendRow([
          xl.TextCellValue(''),
          xl.TextCellValue(label),
          xl.TextCellValue(''),
          xl.TextCellValue(''),
          xl.TextCellValue(''),
          xl.TextCellValue(''),
        ]);
        for (int c = 0; c < cols; c++) {
          wsDet
              .cell(
                xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row),
              )
              .cellStyle = _styleBillHeading();
        }
        row++;

        double billSubtotal = 0.0;

        // If this bill has no valued items, still show subtotal as 0 in details
        if (subs.isEmpty) {
          wsDet.appendRow([
            xl.TextCellValue(''),
            xl.TextCellValue('SUBTOTAL (BILL $billCode)'),
            xl.TextCellValue(''),
            xl.TextCellValue(''),
            xl.TextCellValue(''),
            xl.DoubleCellValue(0.0),
          ]);
          for (int c = 0; c < cols; c++) {
            wsDet
                .cell(
                  xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row),
                )
                .cellStyle = _styleSubtotal();
          }
          row++;

          wsDet.appendRow([
            xl.TextCellValue(''),
            xl.TextCellValue(''),
            xl.TextCellValue(''),
            xl.TextCellValue(''),
            xl.TextCellValue(''),
            xl.TextCellValue(''),
          ]);
          row++;

          billTotals.add({
            'billCode': billCode,
            'billLabel': label,
            'amount': 0.0,
          });
          continue;
        }

        // sort subheadings by min item code (so codes ascend)
        final subKeys =
            subs.keys.toList()..sort(
              (a, b) =>
                  _cmpBoqCode(_minCodeInSub(subs[a]!), _minCodeInSub(subs[b]!)),
            );

        for (final sub in subKeys) {
          if (sub.trim().isNotEmpty) {
            // subheading in column B only
            wsDet.appendRow([
              xl.TextCellValue(''),
              xl.TextCellValue(sub.toUpperCase()),
              xl.TextCellValue(''),
              xl.TextCellValue(''),
              xl.TextCellValue(''),
              xl.TextCellValue(''),
            ]);
            for (int c = 0; c < cols; c++) {
              wsDet
                  .cell(
                    xl.CellIndex.indexByColumnRow(
                      columnIndex: c,
                      rowIndex: row,
                    ),
                  )
                  .cellStyle = _styleSubheading();
            }
            row++;
          }

          final minors = subs[sub]!;
          final minorKeys =
              minors.keys.toList()..sort(
                (a, b) => _cmpBoqCode(
                  _minCodeInMinor(minors[a]!),
                  _minCodeInMinor(minors[b]!),
                ),
              );

          for (final minor in minorKeys) {
            if (minor.trim().isNotEmpty) {
              // minor in column B only
              wsDet.appendRow([
                xl.TextCellValue(''),
                xl.TextCellValue(minor),
                xl.TextCellValue(''),
                xl.TextCellValue(''),
                xl.TextCellValue(''),
                xl.TextCellValue(''),
              ]);
              for (int c = 0; c < cols; c++) {
                wsDet
                    .cell(
                      xl.CellIndex.indexByColumnRow(
                        columnIndex: c,
                        rowIndex: row,
                      ),
                    )
                    .cellStyle = _styleMinor();
              }
              row++;
            }

            final items = minors[minor]!;
            for (final it in items) {
              final rate = it['rate'] as double?;
              final qty = _round2(_num(it['qtyUsed']));
              final amount = _round2(_num(it['amount']));
              billSubtotal += amount;

              wsDet.appendRow([
                xl.TextCellValue(_s(it['itemCode'])),
                xl.TextCellValue(_s(it['desc'])),
                xl.TextCellValue(_s(it['unit'])),
                xl.DoubleCellValue(qty),
                rate == null
                    ? xl.TextCellValue('')
                    : xl.DoubleCellValue(_round2(rate)),
                xl.DoubleCellValue(amount),
              ]);

              // style row
              wsDet
                  .cell(
                    xl.CellIndex.indexByColumnRow(
                      columnIndex: 0,
                      rowIndex: row,
                    ),
                  )
                  .cellStyle = _styleNormalCell();
              wsDet
                  .cell(
                    xl.CellIndex.indexByColumnRow(
                      columnIndex: 1,
                      rowIndex: row,
                    ),
                  )
                  .cellStyle = _styleNormalCell();
              wsDet
                  .cell(
                    xl.CellIndex.indexByColumnRow(
                      columnIndex: 2,
                      rowIndex: row,
                    ),
                  )
                  .cellStyle = _styleNormalCell();

              for (int c = 3; c <= 5; c++) {
                wsDet
                    .cell(
                      xl.CellIndex.indexByColumnRow(
                        columnIndex: c,
                        rowIndex: row,
                      ),
                    )
                    .cellStyle = _styleNumberCell();
              }

              row++;
            }
          }
        }

        // Bill subtotal row
        wsDet.appendRow([
          xl.TextCellValue(''),
          xl.TextCellValue('SUBTOTAL (BILL $billCode)'),
          xl.TextCellValue(''),
          xl.TextCellValue(''),
          xl.TextCellValue(''),
          xl.DoubleCellValue(_round2(billSubtotal)),
        ]);
        for (int c = 0; c < cols; c++) {
          wsDet
              .cell(
                xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row),
              )
              .cellStyle = _styleSubtotal();
        }
        row++;

        // blank row between bills
        wsDet.appendRow([
          xl.TextCellValue(''),
          xl.TextCellValue(''),
          xl.TextCellValue(''),
          xl.TextCellValue(''),
          xl.TextCellValue(''),
          xl.TextCellValue(''),
        ]);
        row++;

        grandTotal += billSubtotal;
        billTotals.add({
          'billCode': billCode,
          'billLabel': label,
          'amount': _round2(billSubtotal),
        });
      }

      // General sums follow the measured bills as a clearly separated
      // allowance section. Draft/excluded allowances remain in the app but do
      // not enter the exported financial total.
      final includedAllowances =
          allowanceSnap.docs.where((doc) {
            final data = doc.data();
            return data['includedInTotal'] != false;
          }).toList();
      if (includedAllowances.isNotEmpty) {
        wsDet.appendRow([
          xl.TextCellValue(''),
          xl.TextCellValue('GENERAL SUMS AND ALLOWANCES'),
          xl.TextCellValue(''),
          xl.TextCellValue(''),
          xl.TextCellValue(''),
          xl.TextCellValue(''),
        ]);
        for (int c = 0; c < cols; c++) {
          wsDet
              .cell(
                xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row),
              )
              .cellStyle = _styleBillHeading();
        }
        row++;

        var allowanceTotal = 0.0;
        for (var index = 0; index < includedAllowances.length; index++) {
          final data = includedAllowances[index].data();
          final quantity = _num(data['quantity']);
          final rate = _num(data['rate']);
          final amount = _round2(
            data['amount'] == null ? quantity * rate : _num(data['amount']),
          );
          allowanceTotal += amount;
          final category = _s(data['category']).trim();
          final description = _s(data['description']).trim();
          final basis = _s(data['basis']).trim();
          final fullDescription = [
            if (category.isNotEmpty) category,
            description,
            if (basis.isNotEmpty) 'Basis: $basis',
          ].join(' - ');
          wsDet.appendRow([
            xl.TextCellValue('GS-${(index + 1).toString().padLeft(2, '0')}'),
            xl.TextCellValue(fullDescription),
            xl.TextCellValue(_s(data['unit'])),
            xl.DoubleCellValue(_round2(quantity)),
            xl.DoubleCellValue(_round2(rate)),
            xl.DoubleCellValue(amount),
          ]);
          for (int c = 0; c < 3; c++) {
            wsDet
                .cell(
                  xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row),
                )
                .cellStyle = _styleNormalCell();
          }
          for (int c = 3; c < cols; c++) {
            wsDet
                .cell(
                  xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row),
                )
                .cellStyle = _styleNumberCell();
          }
          row++;
        }

        wsDet.appendRow([
          xl.TextCellValue(''),
          xl.TextCellValue('SUBTOTAL (GENERAL SUMS)'),
          xl.TextCellValue(''),
          xl.TextCellValue(''),
          xl.TextCellValue(''),
          xl.DoubleCellValue(_round2(allowanceTotal)),
        ]);
        for (int c = 0; c < cols; c++) {
          wsDet
              .cell(
                xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row),
              )
              .cellStyle = _styleSubtotal();
        }
        row++;

        grandTotal += allowanceTotal;
        billTotals.add({
          'billCode': 'GS',
          'billLabel': 'GENERAL SUMS AND ALLOWANCES',
          'amount': _round2(allowanceTotal),
        });
      }

      // Column widths
      wsDet.setColumnWidth(0, 18); // Item
      wsDet.setColumnWidth(1, 70); // Description
      wsDet.setColumnWidth(2, 10); // Unit
      wsDet.setColumnWidth(3, 14); // Qty
      wsDet.setColumnWidth(4, 14); // Rate
      wsDet.setColumnWidth(5, 18); // Amount

      // ---------------- 8) Summary sheet ----------------
      final now = DateTime.now();
      final dt = DateFormat('yyyy-MM-dd HH:mm').format(now);

      // Title row
      wsSum.appendRow([
        xl.TextCellValue('BOQ SUMMARY'),
        xl.TextCellValue(''),
        xl.TextCellValue(''),
      ]);
      for (int c = 0; c < 3; c++) {
        wsSum
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
            .cellStyle = _styleTitle();
      }

      wsSum.appendRow([
        xl.TextCellValue('Project'),
        xl.TextCellValue(projectName),
        xl.TextCellValue(''),
      ]);
      wsSum.appendRow([
        xl.TextCellValue('Site / Location'),
        xl.TextCellValue(siteName.isEmpty ? 'Not specified' : siteName),
        xl.TextCellValue(''),
      ]);
      wsSum.appendRow([
        xl.TextCellValue('Building'),
        xl.TextCellValue(buildingName),
        xl.TextCellValue(''),
      ]);
      wsSum.appendRow([
        xl.TextCellValue('Generated'),
        xl.TextCellValue(dt),
        xl.TextCellValue(''),
      ]);
      wsSum.appendRow([
        xl.TextCellValue(''),
        xl.TextCellValue(''),
        xl.TextCellValue(''),
      ]);

      // Table header
      final headerRow = wsSum.maxRows;
      wsSum.appendRow([
        xl.TextCellValue('Bill No.'),
        xl.TextCellValue('Bill'),
        xl.TextCellValue('Amount'),
      ]);
      for (int c = 0; c < 3; c++) {
        wsSum
            .cell(
              xl.CellIndex.indexByColumnRow(
                columnIndex: c,
                rowIndex: headerRow,
              ),
            )
            .cellStyle = _styleTableHeader();
      }

      // Bills lines (sorted)
      billTotals.sort(
        (a, b) =>
            _billInt(_s(a['billCode'])).compareTo(_billInt(_s(b['billCode']))),
      );

      for (final bt in billTotals) {
        final r = wsSum.maxRows;
        wsSum.appendRow([
          xl.TextCellValue(_s(bt['billCode'])),
          xl.TextCellValue(_s(bt['billLabel'])),
          xl.DoubleCellValue(_round2(_num(bt['amount']))),
        ]);

        // style
        wsSum
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
            .cellStyle = _styleNormalCell();
        wsSum
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
            .cellStyle = _styleNormalCell();
        wsSum
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
            .cellStyle = _styleNumberCell();
      }

      // End the individual building summary at the building BOQ total.
      // Shared site/project costs are only shown in consolidated reports.
      final gtRow = wsSum.maxRows;
      wsSum.appendRow([
        xl.TextCellValue(''),
        xl.TextCellValue('BUILDING BOQ TOTAL'),
        xl.DoubleCellValue(_round2(grandTotal)),
      ]);
      for (int c = 0; c < 3; c++) {
        wsSum
            .cell(
              xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: gtRow),
            )
            .cellStyle = _styleSubtotal();
      }

      wsSum.setColumnWidth(0, 12);
      wsSum.setColumnWidth(1, 55);
      wsSum.setColumnWidth(2, 18);

      // ---------------- 9) Save file ----------------
      final bytes = Uint8List.fromList(excel.encode()!);

      final safeName = '${projectName}_$buildingName'
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .replaceAll(' ', '_');

      final fileName =
          'BOQ_${safeName}_${DateFormat('yyyyMMdd_HHmm').format(now)}.xlsx';

      await FileSaver.instance.saveFile(
        name: fileName.replaceAll('.xlsx', ''),
        bytes: bytes,
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );

      Get.snackbar(
        'Export',
        'Excel saved: $fileName',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar('Export failed', '$e', snackPosition: SnackPosition.BOTTOM);
    }
  }
}
