import 'dart:typed_data';
import 'package:aqs/features/boq/boq_order_key_mixin.dart';
import 'package:aqs/features/utils/helpers/boq_helpers.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';

class BoqImportExcelController extends GetxController with BoqOrderKeyMixin {
  final String projectId;
  final String buildingId;
  final String? drawingId;

  BoqImportExcelController({
    required this.projectId,
    required this.buildingId,
    this.drawingId,
  });

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ✅ CHANGE THIS to your exact BOQ path if different
  CollectionReference<Map<String, dynamic>> get boqRef => _db
      .collection('projects')
      .doc(projectId)
      .collection('buildings')
      .doc(buildingId)
      .collection('boq');

  // building name/structure label
  final RxString structureName = ''.obs;
  final RxString projectName = ''.obs;

  // UI state
  final RxBool importing = false.obs;
  final RxString status = ''.obs;
  final RxInt lastImported = 0.obs;
  final RxBool clearBeforeImport = true.obs;
  final RxString importHierarchyMode = 'auto'.obs;
  final RxString detectedHierarchyMode = ''.obs;

  @override
  void onInit() {
    super.onInit();
    _loadStructureName();
    _loadProjectName();
  }

  Future<void> _loadStructureName() async {
    try {
      final snap =
          await _db
              .collection('projects')
              .doc(projectId)
              .collection('buildings')
              .doc(buildingId)
              .get();

      final d = snap.data() ?? {};
      // try common field names
      structureName.value =
          (d['name'] ?? d['structureName'] ?? d['title'] ?? '')
              .toString()
              .trim();
    } catch (_) {
      // ignore, can be empty
    }
  }

  Future<void> _loadProjectName() async {
    try {
      final snap = await _db.collection('projects').doc(projectId).get();

      final d = snap.data() ?? {};
      // try common field names
      projectName.value =
          (d['name'] ?? d['projectName'] ?? d['title'] ?? '').toString().trim();
    } catch (_) {
      // ignore, can be empty
    }
  }

  //   Future<void> _deleteAllItems(String templateId) async {
  //   while (true) {
  //     final snap = await itemsRef(templateId).limit(400).get();
  //     if (snap.docs.isEmpty) break;
  //     final b = _db.batch();
  //     for (final d in snap.docs) {
  //       b.delete(d.reference);
  //     }
  //     await b.commit();
  //   }
  // }

  Future<int> importExcelBytes(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return 0;

    bool hasBoqHeaders(Sheet candidate) {
      const codeHeaders = {'item', 'boq', 'code', 'item code', 'boq code'};
      const descriptionHeaders = {'description', 'desc', 'item description'};

      for (int r = 0; r < candidate.rows.length && r < 10; r++) {
        final headers =
            candidate.rows[r]
                .map(
                  (cell) => (cell?.value ?? '').toString().trim().toLowerCase(),
                )
                .toSet();

        if (headers.any(codeHeaders.contains) &&
            headers.any(descriptionHeaders.contains)) {
          return true;
        }
      }

      return false;
    }

    final sheet = excel.tables.values.firstWhere(
      hasBoqHeaders,
      orElse: () => excel.tables.values.first,
    );
    if (sheet.rows.isEmpty) return 0;

    // -----------------------------
    // 1) Find header row (first 10)
    // -----------------------------
    int headerRowIdx = -1;
    Map<String, int> col = {};

    for (int r = 0; r < sheet.rows.length && r < 10; r++) {
      final row = sheet.rows[r];
      final headers =
          row
              .map((c) => (c?.value ?? '').toString().trim().toLowerCase())
              .toList();

      int idxOf(List<String> keys) {
        for (final k in keys) {
          final i = headers.indexOf(k);
          if (i != -1) return i;
        }
        return -1;
      }

      final cCode = idxOf(['item', 'boq', 'code', 'item code', 'boq code']);
      final cDesc = idxOf(['description', 'desc', 'item description']);
      final cUnit = idxOf(['unit', 'uom']);
      final cRate = idxOf([
        'rate',
        'unit rate',
        'unitrate',
        'price',
        'unit price',
        'unitprice',
      ]);

      if (cCode != -1 && cDesc != -1) {
        headerRowIdx = r;
        col = {
          'code': cCode,
          'desc': cDesc,
          'unit': cUnit, // may be -1
          'rate': cRate, // may be -1
        };
        break;
      }
    }

    // If no headers found, assume fixed: 0=code, 1=desc, 2=unit, 3=rate
    if (headerRowIdx == -1) {
      headerRowIdx = 0;
      col = {'code': 0, 'desc': 1, 'unit': 2, 'rate': 3};
    }

    bool containsSeriesHeading() {
      final seriesPattern = RegExp(r'^\s*series\s*\d+', caseSensitive: false);
      final codeIndex = col['code'] ?? 0;
      final descriptionIndex = col['desc'] ?? 1;
      for (final row in sheet.rows.skip(headerRowIdx + 1)) {
        for (final index in [codeIndex, descriptionIndex]) {
          if (index < 0 || index >= row.length) continue;
          final value = (row[index]?.value ?? '').toString().trim();
          if (seriesPattern.hasMatch(value)) return true;
        }
      }
      return false;
    }

    final selectedHierarchy = importHierarchyMode.value.trim().toLowerCase();
    final isCivilWorks =
        selectedHierarchy == 'civil' ||
        (selectedHierarchy == 'auto' && containsSeriesHeading());
    detectedHierarchyMode.value = isCivilWorks ? 'civil' : 'building';

    // -----------------------------
    // 2) Helpers
    // -----------------------------
    String cellAt(List<Data?> row, int i) {
      if (i < 0 || i >= row.length) return '';
      return (row[i]?.value ?? '').toString().trim();
    }

    String normSpaces(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Normalize codes like "B. i" -> "B.i", "A . i" -> "A.i"
    String normCode(String s) {
      var t = s.trim();
      t = t.replaceAll(RegExp(r'\s*\.\s*'), '.'); // dot spacing
      t = t.replaceAll(RegExp(r'\s+'), ' '); // remaining spaces
      return t.trim();
    }

    // parse "1,234.50" "1 234.50" "1234" etc
    double? parseRate(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return null;

      // keep digits, dot, minus
      final cleaned = t
          .replaceAll(RegExp(r'[,\s]'), '')
          .replaceAll(RegExp(r'[^0-9\.\-]'), '');

      if (cleaned.isEmpty) return null;
      final v = double.tryParse(cleaned);
      if (v == null) return null;
      return v;
    }

    bool isRoman(String s) =>
        RegExp(r'^[ivxlcdm]+$', caseSensitive: false).hasMatch(s.trim());

    bool isParenRoman(String s) =>
        RegExp(r'^\([ivxlcdm]+\)$', caseSensitive: false).hasMatch(s.trim());

    String stripParen(String s) {
      final t = s.trim();
      if (t.startsWith('(') && t.endsWith(')') && t.length >= 2) {
        return t.substring(1, t.length - 1).trim();
      }
      return t;
    }

    bool isSectionNo(String s) => RegExp(r'^\d+(?:\.\d+)*$').hasMatch(s.trim());

    String? extractBillCodeFromText(String text) {
      final t = text.toUpperCase();
      final m = RegExp(r'BILL\s*NO\.?\s*(\d+)').firstMatch(t);
      return m?.group(1);
    }

    String? extractSeriesCode(String code, String desc) {
      final text = '$code $desc'.toUpperCase();
      final match = RegExp(r'SERIES\s*(\d+)').firstMatch(text);
      return match?.group(1);
    }

    bool isSeriesHeading(String code, String desc) =>
        extractSeriesCode(code, desc) != null;

    String extractCivilSectionCode(String code) {
      final normalized = normSpaces(code);
      final labeled = RegExp(
        r'^SECTION\s*(\d+)\s*:?$',
        caseSensitive: false,
      ).firstMatch(normalized);
      if (labeled != null) return labeled.group(1) ?? normalized;
      return normalized.replaceFirst(RegExp(r':\s*$'), '').trim();
    }

    bool isCivilSectionHeading(String code, String unit) {
      if (unit.trim().isNotEmpty) return false;
      final normalized = normSpaces(code);
      return RegExp(
            r'^SECTION\s*\d+\s*:?$',
            caseSensitive: false,
          ).hasMatch(normalized) ||
          RegExp(r'^\d{4}\s*:?$').hasMatch(normalized);
    }

    String civilHeadingLabel(String code, String desc) {
      final c = normSpaces(code).replaceFirst(RegExp(r':\s*$'), '');
      var d = normSpaces(desc);
      if (c.isEmpty) return d.toUpperCase();
      if (d.toUpperCase().startsWith(c.toUpperCase())) {
        d = d.substring(c.length).replaceFirst(RegExp(r'^\s*[:\-]\s*'), '');
      }
      if (d.isEmpty || d.toUpperCase() == c.toUpperCase()) {
        return c.toUpperCase();
      }
      return '${c.toUpperCase()} - ${d.toUpperCase()}';
    }

    String detectRowType(String code, String desc, String unit) {
      final c = normCode(code);
      final d = desc.trim().toUpperCase();
      final u = unit.trim();

      if (isCivilWorks && isSeriesHeading(c, d)) return 'bill';
      if (c.isEmpty && d.contains('BILL')) return 'bill';
      if (isCivilWorks && isCivilSectionHeading(c, u)) return 'subheading';
      if (isCivilWorks && u.isEmpty && (c.isNotEmpty || d.isNotEmpty)) {
        return 'minor';
      }
      if (u.isEmpty && isSectionNo(c)) return 'subheading';
      if (u.isEmpty && (isRoman(c) || isParenRoman(c))) return 'minor';
      return 'item';
    }

    ({String main, String sub}) parseItemCode(String raw, String lastMain) {
      final c = normCode(raw);

      final m1 = RegExp(
        r'^([A-Za-z])\.(\s*[ivxlcdm]+)$',
        caseSensitive: false,
      ).firstMatch(c);
      if (m1 != null) {
        final main = (m1.group(1) ?? '').toUpperCase();
        final sub = (m1.group(2) ?? '').trim().toLowerCase();
        return (main: main, sub: sub);
      }

      final m2 = RegExp(r'^([A-Za-z])$').firstMatch(c);
      if (m2 != null) {
        return (main: (m2.group(1) ?? '').toUpperCase(), sub: '');
      }

      if (isRoman(c)) {
        return (main: lastMain.toUpperCase(), sub: c.toLowerCase());
      }

      return (main: lastMain.toUpperCase(), sub: '');
    }

    String buildResolved({
      required String subHeadingNo,
      required String minorNo,
      required String mainNo,
      required String subNo,
      required String rawFallback,
    }) {
      final sh = subHeadingNo.trim();
      final mn = minorNo.trim().toLowerCase();
      final main = mainNo.trim().toUpperCase();
      final sub = subNo.trim().toLowerCase();

      if (sh.isEmpty) return rawFallback.trim();
      if (main.isEmpty && sub.isEmpty) return rawFallback.trim();

      final buf = StringBuffer()..write(sh);
      if (mn.isNotEmpty) buf.write('($mn)');
      if (main.isNotEmpty) buf.write('($main)');
      if (sub.isNotEmpty) buf.write('($sub)');
      return buf.toString();
    }

    String buildDisplayCode({
      required String mainNo,
      required String subNo,
      required String rawFallback,
    }) {
      final main = mainNo.trim().toUpperCase();
      final sub = subNo.trim().toLowerCase();

      if (main.isNotEmpty && sub.isNotEmpty) return '$main.$sub';
      if (main.isNotEmpty) return main;
      if (sub.isNotEmpty) return sub;
      return normCode(rawFallback);
    }

    // -----------------------------
    // 3) Build docs in Excel order
    // -----------------------------
    final now = FieldValue.serverTimestamp();
    final docsToAdd = <Map<String, dynamic>>[];

    String currentBillCode = '';
    String currentBillLabel = '';

    String currentSubNo = '';
    String currentSubheading = '';

    String currentMinorNo = '';
    String currentMinorLabel = '';

    String lastMainNo = '';

    int order = 0;

    for (int r = headerRowIdx + 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];

      final rawCode = cellAt(row, col['code']!);
      final rawDesc = cellAt(row, col['desc']!);
      final rawUnit = cellAt(row, col['unit'] ?? -1);
      final rawRate = cellAt(row, col['rate'] ?? -1);

      final code = normCode(rawCode);
      final desc = normSpaces(rawDesc);
      final unit = normSpaces(rawUnit);
      final rate = parseRate(rawRate); // ✅ NEW

      if (code.isEmpty &&
          desc.isEmpty &&
          unit.isEmpty &&
          (rawRate.trim().isEmpty)) {
        continue;
      }

      final rowType = detectRowType(code, desc, unit);

      // ---- BILL ----
      if (rowType == 'bill') {
        if (isCivilWorks && isSeriesHeading(code, desc)) {
          currentBillCode = extractSeriesCode(code, desc) ?? currentBillCode;
          currentBillLabel = civilHeadingLabel(code, desc);
        } else {
          currentBillLabel = desc.isEmpty ? 'BILL' : desc.toUpperCase();
          currentBillCode =
              extractBillCodeFromText(currentBillLabel) ?? currentBillCode;
        }

        currentSubNo = '';
        currentSubheading = '';
        currentMinorNo = '';
        currentMinorLabel = '';
        lastMainNo = '';

        docsToAdd.add({
          'boqCode': isCivilWorks ? code : '',
          'displayCode': isCivilWorks ? code : '',
          'resolvedBoqCode': isCivilWorks ? currentBillCode : '',
          'description': currentBillLabel,
          'unit': '',
          'rowType': 'bill',
          'sectionType': isCivilWorks ? 'series' : 'bill',
          'boqWorkType': isCivilWorks ? 'civil' : 'building',
          'billCode': currentBillCode,
          'billLabel': currentBillLabel,
          'subHeadingNo': '',
          'subheading': '',
          'structure': structureName.value,
          'minorNo': '',
          'minorLabel': '',
          'mainNo': '',
          'subNo': '',
          // rate not needed on bill row
          'order': order++,
          'orderKey': makeOrderKey(''),
          'createdAt': now,
          'updatedAt': now,
        });
        continue;
      }

      // ---- SUBHEADING ----
      if (rowType == 'subheading') {
        currentSubNo = isCivilWorks ? extractCivilSectionCode(code) : code;
        currentSubheading =
            isCivilWorks
                ? (desc.isEmpty ? code : desc).toUpperCase()
                : desc.toUpperCase();

        currentMinorNo = '';
        currentMinorLabel = '';
        lastMainNo = '';

        if (currentBillCode.isEmpty && currentSubNo.contains('.')) {
          currentBillCode = currentSubNo.split('.').first.trim();
        }

        docsToAdd.add({
          'boqCode': code,
          'displayCode': code,
          'resolvedBoqCode': currentSubNo,
          'description': currentSubheading,
          'unit': '',
          'rowType': 'subheading',
          'sectionType': isCivilWorks ? 'series' : 'bill',
          'boqWorkType': isCivilWorks ? 'civil' : 'building',
          'billCode': currentBillCode,
          'billLabel': currentBillLabel,
          'structure': structureName.value,
          'subHeadingNo': currentSubNo,
          'subheading': currentSubheading,
          'minorNo': '',
          'minorLabel': '',
          'mainNo': '',
          'subNo': '',
          // rate not needed on subheading row
          'order': order++,
          'orderKey': makeOrderKey(currentSubNo),
          'createdAt': now,
          'updatedAt': now,
        });
        continue;
      }

      // ---- MINOR ----
      if (rowType == 'minor') {
        currentMinorNo = isCivilWorks ? code : stripParen(code).toLowerCase();
        currentMinorLabel = desc;
        lastMainNo = '';

        final minorResolved =
            isCivilWorks
                ? civilResolvedBoqCode(minorCode: currentMinorNo, rawCode: '')
                : currentSubNo.isEmpty
                ? '($currentMinorNo)'
                : '${currentSubNo}($currentMinorNo)';
        final minorDisplayCode = isCivilWorks ? code : '($currentMinorNo)';

        docsToAdd.add({
          'boqCode': minorDisplayCode,
          'displayCode': minorDisplayCode,
          'resolvedBoqCode': minorResolved,
          'description': currentMinorLabel.toUpperCase(),
          'unit': '',
          'rowType': 'minor',
          'sectionType': isCivilWorks ? 'series' : 'bill',
          'boqWorkType': isCivilWorks ? 'civil' : 'building',
          'billCode': currentBillCode,
          'billLabel': currentBillLabel,
          'structure': structureName.value,
          'subHeadingNo': currentSubNo,
          'subheading': currentSubheading,
          'minorNo': currentMinorNo,
          'minorLabel': currentMinorLabel,
          'mainNo': '',
          'subNo': '',
          // rate not needed on minor row
          'order': order++,
          'orderKey': makeOrderKey(minorResolved),
          'createdAt': now,
          'updatedAt': now,
        });
        continue;
      }

      // ---- ITEM ----
      final parts = parseItemCode(code, lastMainNo);
      final mainNo = parts.main;
      final subNo = parts.sub;

      if (mainNo.isNotEmpty) lastMainNo = mainNo;

      final displayCode = buildDisplayCode(
        mainNo: mainNo,
        subNo: subNo,
        rawFallback: code,
      );

      final resolved = buildResolved(
        subHeadingNo: currentSubNo,
        minorNo: currentMinorNo,
        mainNo: mainNo,
        subNo: subNo,
        rawFallback: code,
      );
      final storedResolved =
          isCivilWorks
              ? civilResolvedBoqCode(minorCode: currentMinorNo, rawCode: code)
              : resolved;

      final itemDoc = <String, dynamic>{
        'boqCode': code,
        'displayCode': isCivilWorks ? code : displayCode,
        'resolvedBoqCode': storedResolved,
        'description': desc,
        'unit': unit,
        'rowType': 'item',
        'sectionType': isCivilWorks ? 'series' : 'bill',
        'boqWorkType': isCivilWorks ? 'civil' : 'building',

        'billCode': currentBillCode,
        'billLabel': currentBillLabel,
        'subHeadingNo': currentSubNo,
        'subheading': currentSubheading,
        'minorNo': currentMinorNo,
        'minorLabel': currentMinorLabel,
        'structure': structureName.value,
        'mainNo': mainNo,
        'subNo': subNo,

        // ✅ NEW: rate from excel (optional)
        // store only if present
        if (rate != null) 'rate': rate,

        'order': order++,
        'orderKey': makeOrderKey(storedResolved),
        'createdAt': now,
        'updatedAt': now,
      };

      docsToAdd.add(itemDoc);
    }

    if (docsToAdd.isEmpty) return 0;

    // -----------------------------
    // 4) Batch write (Firestore limit 500)
    // -----------------------------
    int added = 0;
    int i = 0;
    while (i < docsToAdd.length) {
      final chunk = docsToAdd.skip(i).take(450).toList();
      final b = _db.batch();

      for (final data in chunk) {
        b.set(boqRef.doc(), data);
      }

      await b.commit();
      added += chunk.length;
      i += chunk.length;
    }

    return added;
  }

  // Future<int> importExcelBytes(Uint8List bytes) async {
  //   final excel = Excel.decodeBytes(bytes);
  //   if (excel.tables.isEmpty) return 0;

  //   final sheet = excel.tables.values.first;
  //   if (sheet.rows.isEmpty) return 0;

  //   // -----------------------------
  //   // 1) Find header row (first 10)
  //   // -----------------------------
  //   int headerRowIdx = -1;
  //   Map<String, int> col = {};

  //   for (int r = 0; r < sheet.rows.length && r < 10; r++) {
  //     final row = sheet.rows[r];
  //     final headers =
  //         row
  //             .map((c) => (c?.value ?? '').toString().trim().toLowerCase())
  //             .toList();

  //     int idxOf(List<String> keys) {
  //       for (final k in keys) {
  //         final i = headers.indexOf(k);
  //         if (i != -1) return i;
  //       }
  //       return -1;
  //     }

  //     final cCode = idxOf(['item', 'boq', 'code', 'item code', 'boq code']);
  //     final cDesc = idxOf(['description', 'desc', 'item description']);
  //     final cUnit = idxOf(['unit', 'uom']);

  //     if (cCode != -1 && cDesc != -1) {
  //       headerRowIdx = r;
  //       col = {'code': cCode, 'desc': cDesc, 'unit': cUnit}; // unit may be -1
  //       break;
  //     }
  //   }

  //   // If no headers found, assume fixed: 0=code, 1=desc, 2=unit
  //   if (headerRowIdx == -1) {
  //     headerRowIdx = 0;
  //     col = {'code': 0, 'desc': 1, 'unit': 2, 'rate': 3, 'amount': 4};
  //   }

  //   // -----------------------------
  //   // 2) Helpers
  //   // -----------------------------
  //   String cellAt(List<Data?> row, int i) {
  //     if (i < 0 || i >= row.length) return '';
  //     return (row[i]?.value ?? '').toString().trim();
  //   }

  //   String normSpaces(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  //   // Normalize codes like "B. i" -> "B.i", "A . i" -> "A.i"
  //   String normCode(String s) {
  //     var t = s.trim();
  //     t = t.replaceAll(RegExp(r'\s*\.\s*'), '.'); // dot spacing
  //     t = t.replaceAll(RegExp(r'\s+'), ' '); // remaining spaces
  //     return t.trim();
  //   }

  //   bool isRoman(String s) =>
  //       RegExp(r'^[ivxlcdm]+$', caseSensitive: false).hasMatch(s.trim());

  //   bool isParenRoman(String s) =>
  //       RegExp(r'^\([ivxlcdm]+\)$', caseSensitive: false).hasMatch(s.trim());

  //   String stripParen(String s) {
  //     final t = s.trim();
  //     if (t.startsWith('(') && t.endsWith(')') && t.length >= 2) {
  //       return t.substring(1, t.length - 1).trim();
  //     }
  //     return t;
  //   }

  //   bool isSectionNo(String s) => RegExp(r'^\d+(?:\.\d+)*$').hasMatch(s.trim());

  //   String? extractBillCodeFromText(String text) {
  //     // e.g. "BILL NO. 3:-SUBSTRUCTURE" -> "3"
  //     final t = text.toUpperCase();
  //     final m = RegExp(r'BILL\s*NO\.?\s*(\d+)').firstMatch(t);
  //     return m?.group(1);
  //   }

  //   // Detect row type from the raw Excel row
  //   String detectRowType(String code, String desc, String unit) {
  //     final c = normCode(code);
  //     final d = desc.trim().toUpperCase();
  //     final u = unit.trim();

  //     // BILL: code empty + desc contains BILL
  //     if (c.isEmpty && d.contains('BILL')) return 'bill';

  //     // SUBHEADING: code like 3.1, 3.7, 10.2 AND unit empty
  //     if (u.isEmpty && isSectionNo(c)) return 'subheading';

  //     // MINOR: unit empty AND code roman like i, ii OR (i)
  //     if (u.isEmpty && (isRoman(c) || isParenRoman(c))) return 'minor';

  //     return 'item';
  //   }

  //   // Parse an item code into parts (main letter and sub roman)
  //   // Supports:
  //   // - "A" -> main=A
  //   // - "B.i" -> main=B, sub=i
  //   // - "ii" -> sub=ii (main will be taken from lastMain if available)
  //   ({String main, String sub}) parseItemCode(String raw, String lastMain) {
  //     final c = normCode(raw);

  //     // "B.i" / "A.ii"
  //     final m1 = RegExp(
  //       r'^([A-Za-z])\.(\s*[ivxlcdm]+)$',
  //       caseSensitive: false,
  //     ).firstMatch(c);
  //     if (m1 != null) {
  //       final main = (m1.group(1) ?? '').toUpperCase();
  //       final sub = (m1.group(2) ?? '').trim().toLowerCase();
  //       return (main: main, sub: sub);
  //     }

  //     // "A"
  //     final m2 = RegExp(r'^([A-Za-z])$').firstMatch(c);
  //     if (m2 != null) {
  //       return (main: (m2.group(1) ?? '').toUpperCase(), sub: '');
  //     }

  //     // "ii" (roman-only)
  //     if (isRoman(c)) {
  //       return (main: lastMain.toUpperCase(), sub: c.toLowerCase());
  //     }

  //     // fallback (unknown pattern)
  //     return (main: lastMain.toUpperCase(), sub: '');
  //   }

  //   String buildResolved({
  //     required String subHeadingNo,
  //     required String minorNo,
  //     required String mainNo,
  //     required String subNo,
  //     required String rawFallback,
  //   }) {
  //     final sh = subHeadingNo.trim();
  //     final mn = minorNo.trim().toLowerCase();
  //     final main = mainNo.trim().toUpperCase();
  //     final sub = subNo.trim().toLowerCase();

  //     if (sh.isEmpty) return rawFallback.trim();

  //     // if no main and no sub, fallback raw
  //     if (main.isEmpty && sub.isEmpty) return rawFallback.trim();

  //     final buf = StringBuffer();
  //     buf.write(sh);

  //     if (mn.isNotEmpty) {
  //       buf.write('($mn)');
  //     }

  //     if (main.isNotEmpty) {
  //       buf.write('($main)');
  //     }

  //     if (sub.isNotEmpty) {
  //       buf.write('($sub)');
  //     }

  //     return buf.toString();
  //   }

  //   String buildDisplayCode({
  //     required String mainNo,
  //     required String subNo,
  //     required String rawFallback,
  //   }) {
  //     final main = mainNo.trim().toUpperCase();
  //     final sub = subNo.trim().toLowerCase();

  //     if (main.isNotEmpty && sub.isNotEmpty) return '$main.$sub';
  //     if (main.isNotEmpty) return main;
  //     if (sub.isNotEmpty) return sub;
  //     return normCode(rawFallback);
  //   }

  //   // -----------------------------
  //   // 3) Build docs in Excel order
  //   // -----------------------------
  //   // if (clearExisting) {
  //   //   await _deleteAllItems(templateId);
  //   // }

  //   final now = FieldValue.serverTimestamp();
  //   final docsToAdd = <Map<String, dynamic>>[];

  //   // Context that we carry while scanning rows
  //   String currentBillCode = '';
  //   String currentBillLabel = '';

  //   String currentSubNo = '';
  //   String currentSubheading = '';

  //   String currentMinorNo = '';
  //   String currentMinorLabel = '';

  //   String lastMainNo = ''; // A/B/C… last seen for roman-only rows

  //   int order = 0;
  //   // final docsToAdd = <Map<String, dynamic>>[];

  //   for (int r = headerRowIdx + 1; r < sheet.rows.length; r++) {
  //     final row = sheet.rows[r];

  //     final rawCode = cellAt(row, col['code']!);
  //     final rawDesc = cellAt(row, col['desc']!);
  //     final rawUnit = cellAt(row, col['unit'] ?? -1);

  //     final code = normCode(rawCode);
  //     final desc = normSpaces(rawDesc);
  //     final unit = normSpaces(rawUnit);

  //     if (code.isEmpty && desc.isEmpty && unit.isEmpty) continue;

  //     final rowType = detectRowType(code, desc, unit);

  //     // ---- BILL ----
  //     if (rowType == 'bill') {
  //       currentBillLabel = desc.isEmpty ? 'BILL' : desc.toUpperCase();
  //       currentBillCode =
  //           extractBillCodeFromText(currentBillLabel) ?? currentBillCode;

  //       // reset lower contexts
  //       currentSubNo = '';
  //       currentSubheading = '';
  //       currentMinorNo = '';
  //       currentMinorLabel = '';
  //       lastMainNo = '';

  //       docsToAdd.add({
  //         'boqCode': '',
  //         'displayCode': '',
  //         'resolvedBoqCode': '',
  //         'description': currentBillLabel,
  //         'unit': '',
  //         'rowType': 'bill',
  //         'billCode': currentBillCode,
  //         'billLabel': currentBillLabel,
  //         'subHeadingNo': '',
  //         'subheading': '',
  //         'minorNo': '',
  //         'minorLabel': '',
  //         'mainNo': '',
  //         'subNo': '',
  //         'order': order++,
  //         'orderKey': makeOrderKey(''), // ok
  //         'createdAt': now,
  //         'updatedAt': now,
  //       });
  //       continue;
  //     }

  //     // ---- SUBHEADING (3.1 / 3.7) ----
  //     if (rowType == 'subheading') {
  //       currentSubNo = code; // e.g. "3.1"
  //       currentSubheading = desc.toUpperCase();

  //       // reset minor + lastMain under new subheading
  //       currentMinorNo = '';
  //       currentMinorLabel = '';
  //       lastMainNo = '';

  //       // If billCode not set from BILL row, infer from subheading (first segment)
  //       if (currentBillCode.isEmpty && currentSubNo.contains('.')) {
  //         currentBillCode = currentSubNo.split('.').first.trim();
  //       }

  //       docsToAdd.add({
  //         'boqCode': currentSubNo,
  //         'displayCode': currentSubNo,
  //         'resolvedBoqCode': currentSubNo,
  //         'description': currentSubheading,
  //         'unit': '',
  //         'rowType': 'subheading',
  //         'billCode': currentBillCode,
  //         'billLabel': currentBillLabel,
  //         'subHeadingNo': currentSubNo,
  //         'subheading': currentSubheading,
  //         'minorNo': '',
  //         'minorLabel': '',
  //         'mainNo': '',
  //         'subNo': '',
  //         'order': order++,
  //         'orderKey': makeOrderKey(currentSubNo),
  //         'createdAt': now,
  //         'updatedAt': now,
  //       });
  //       continue;
  //     }

  //     // ---- MINOR ((i) / i) ----
  //     if (rowType == 'minor') {
  //       currentMinorNo = stripParen(code).toLowerCase(); // i / ii
  //       currentMinorLabel = desc; // keep original, UI can upper later

  //       // reset main under new minor section
  //       lastMainNo = '';

  //       docsToAdd.add({
  //         'boqCode': '($currentMinorNo)',
  //         'displayCode': '($currentMinorNo)',
  //         'resolvedBoqCode':
  //             currentSubNo.isEmpty
  //                 ? '($currentMinorNo)'
  //                 : '${currentSubNo}($currentMinorNo)',
  //         'description': currentMinorLabel.toUpperCase(),
  //         'unit': '',
  //         'rowType': 'minor',
  //         'billCode': currentBillCode,
  //         'billLabel': currentBillLabel,
  //         'subHeadingNo': currentSubNo,
  //         'subheading': currentSubheading,
  //         'minorNo': currentMinorNo,
  //         'minorLabel': currentMinorLabel,
  //         'mainNo': '',
  //         'subNo': '',
  //         'order': order++,
  //         'orderKey': makeOrderKey(
  //           currentSubNo.isEmpty
  //               ? '($currentMinorNo)'
  //               : '${currentSubNo}($currentMinorNo)',
  //         ),
  //         'createdAt': now,
  //         'updatedAt': now,
  //       });
  //       continue;
  //     }

  //     // ---- ITEM ----
  //     // Parse main/sub from item code (supports roman-only rows)
  //     final parts = parseItemCode(code, lastMainNo);
  //     final mainNo = parts.main; // may be '' if unknown
  //     final subNo = parts.sub; // may be ''

  //     // If this row has a main letter, update lastMainNo (so next roman-only rows attach)
  //     if (mainNo.isNotEmpty) {
  //       lastMainNo = mainNo;
  //     }

  //     final displayCode = buildDisplayCode(
  //       mainNo: mainNo,
  //       subNo: subNo,
  //       rawFallback: code,
  //     );

  //     final resolved = buildResolved(
  //       subHeadingNo: currentSubNo,
  //       minorNo: currentMinorNo,
  //       mainNo: mainNo,
  //       subNo: subNo,
  //       rawFallback: code,
  //     );

  //     docsToAdd.add({
  //       // keep what was in Excel (raw), but also store resolved
  //       'boqCode': code,
  //       'displayCode': displayCode,
  //       'resolvedBoqCode': resolved,

  //       'description': desc,
  //       'unit': unit,
  //       'rowType': 'item',

  //       // context
  //       'billCode': currentBillCode,
  //       'billLabel': currentBillLabel,
  //       'subHeadingNo': currentSubNo,
  //       'subheading': currentSubheading,
  //       'minorNo': currentMinorNo,
  //       'minorLabel': currentMinorLabel,
  //       'mainNo': mainNo,
  //       'subNo': subNo,

  //       // ordering
  //       'order': order++,
  //       'orderKey': makeOrderKey(resolved),

  //       'createdAt': now,
  //       'updatedAt': now,
  //     });
  //   }

  //   if (docsToAdd.isEmpty) return 0;

  //   // -----------------------------
  //   // 4) Batch write (Firestore limit 500)
  //   // -----------------------------
  //   int added = 0;
  //   int i = 0;
  //   while (i < docsToAdd.length) {
  //     final chunk = docsToAdd.skip(i).take(450).toList();
  //     final b = _db.batch();

  //     for (final data in chunk) {
  //       b.set(boqRef.doc(), data);
  //     }

  //     await b.commit();
  //     added += chunk.length;
  //     i += chunk.length;
  //   }

  //   return added;
  // }

  Future<void> pickAndImportExcel() async {
    try {
      status.value = '';
      lastImported.value = 0;

      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xls'],
        withData: true, // ✅ important for web
      );

      if (res == null || res.files.isEmpty) return;
      final bytes = res.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        status.value = 'Failed to read file bytes.';
        return;
      }

      importing.value = true;

      if (clearBeforeImport.value) {
        status.value = 'Clearing existing BOQ...';
        await _deleteAllBoqRows();
      }

      status.value = 'Importing Excel...';
      final added = await importExcelBytes(bytes);

      lastImported.value = added;
      final hierarchyLabel =
          detectedHierarchyMode.value == 'civil'
              ? 'Civil works (SERIES)'
              : 'Building works (BILL)';
      status.value = 'Done. Imported $added rows as $hierarchyLabel.';
    } catch (e) {
      status.value = 'Error: $e';
    } finally {
      importing.value = false;
    }
  }

  Future<void> _deleteAllBoqRows() async {
    while (true) {
      final snap = await boqRef.limit(400).get();
      if (snap.docs.isEmpty) break;

      final b = _db.batch();
      for (final d in snap.docs) {
        b.delete(d.reference);
      }
      await b.commit();
    }
  }

  // -----------------------------
  // EXCEL -> PROJECT BOQ IMPORT
  // -----------------------------
  // Future<int> importExcelBytesToProjectBoq(Uint8List bytes) async {
  //   final excel = Excel.decodeBytes(bytes);
  //   if (excel.tables.isEmpty) return 0;

  //   final sheet = excel.tables.values.first;
  //   if (sheet.rows.isEmpty) return 0;

  //   // ---- detect header row ----
  //   int headerRowIdx = -1;
  //   Map<String, int> col = {};

  //   for (int r = 0; r < sheet.rows.length && r < 10; r++) {
  //     final row = sheet.rows[r];
  //     final headers =
  //         row
  //             .map((c) => (c?.value ?? '').toString().trim().toLowerCase())
  //             .toList();

  //     int idxOf(List<String> keys) {
  //       for (final k in keys) {
  //         final i = headers.indexOf(k);
  //         if (i != -1) return i;
  //       }
  //       return -1;
  //     }

  //     final cCode = idxOf(['item', 'boq', 'code', 'item code', 'boq code']);
  //     final cDesc = idxOf(['description', 'desc', 'item description']);
  //     final cUnit = idxOf(['unit', 'uom']);

  //     if (cCode != -1 && cDesc != -1) {
  //       headerRowIdx = r;
  //       col = {'code': cCode, 'desc': cDesc, 'unit': cUnit}; // unit can be -1
  //       break;
  //     }
  //   }

  //   if (headerRowIdx == -1) {
  //     headerRowIdx = 0;
  //     col = {'code': 0, 'desc': 1, 'unit': 2};
  //   }

  //   String cellAt(List<Data?> row, int i) {
  //     if (i < 0 || i >= row.length) return '';
  //     return (row[i]?.value ?? '').toString().trim();
  //   }

  //   bool isRoman(String s) =>
  //       RegExp(r'^[ivxlcdm]+$', caseSensitive: false).hasMatch(s.trim());

  //   // normalize codes like "B. i" -> "B.i"
  //   String normCode(String s) {
  //     var t = s.trim();
  //     t = t.replaceAll(RegExp(r'\s+'), ' ');
  //     t = t.replaceAll('. ', '.');
  //     t = t.replaceAll(' .', '.');
  //     return t.trim();
  //   }

  //   // Track headings while iterating
  //   String currentBillLabel = '';
  //   String currentBillCode = '';

  //   String currentSubheading = '';
  //   String currentSubHeadingNo = '';

  //   String currentMinorLabel = '';
  //   String currentMinorNo = '';

  //   // Track last main letter so "ii" can become "B.ii" if it follows "B.i"
  //   String lastMainNo = '';

  //   // output docs
  //   final now = FieldValue.serverTimestamp();
  //   final docsToAdd = <Map<String, dynamic>>[];

  //   int order = 0;

  //   for (int r = headerRowIdx + 1; r < sheet.rows.length; r++) {
  //     final row = sheet.rows[r];

  //     final rawCode = normCode(cellAt(row, col['code']!));
  //     final desc = cellAt(row, col['desc']!);
  //     final unit = cellAt(row, col['unit'] ?? -1);

  //     // skip fully empty row
  //     if (rawCode.isEmpty && desc.trim().isEmpty && unit.trim().isEmpty)
  //       continue;

  //     final dUpper = desc.trim().toUpperCase();
  //     final u = unit.trim();

  //     // ---- BILL ROW ----
  //     if (rawCode.isEmpty && dUpper.contains('BILL')) {
  //       currentBillLabel = desc.trim();
  //       // try extract bill number from label
  //       final m = RegExp(r'\b(\d+)\b').firstMatch(currentBillLabel);
  //       currentBillCode = (m?.group(1) ?? '').trim();
  //       // reset section context
  //       currentSubheading = '';
  //       currentSubHeadingNo = '';
  //       currentMinorLabel = '';
  //       currentMinorNo = '';
  //       lastMainNo = '';
  //       continue;
  //     }

  //     // ---- SUBHEADING ROW (e.g., 3.1, 3.7) ----
  //     if (u.isEmpty && RegExp(r'^\d+(?:\.\d+)*$').hasMatch(rawCode)) {
  //       currentSubHeadingNo = rawCode;
  //       currentSubheading = desc.trim();
  //       // reset minor + main
  //       currentMinorLabel = '';
  //       currentMinorNo = '';
  //       lastMainNo = '';
  //       continue;
  //     }

  //     // ---- MINOR ROW (e.g., (i), i, (ii)...) ----
  //     final parenRoman = RegExp(r'^\([ivxlcdm]+\)$', caseSensitive: false);
  //     if (u.isEmpty && (isRoman(rawCode) || parenRoman.hasMatch(rawCode))) {
  //       // minorNo
  //       var minor = rawCode.replaceAll('(', '').replaceAll(')', '').trim();
  //       currentMinorNo = minor.toLowerCase();

  //       // label
  //       currentMinorLabel = desc.trim();

  //       // reset main under new minor
  //       lastMainNo = '';
  //       continue;
  //     }

  //     // ---- ITEM ROW ----
  //     // Parse code into main + sub when possible.
  //     String mainNo = '';
  //     String subNo = '';
  //     String boqCodeToStore = rawCode;

  //     // A
  //     final onlyLetter = RegExp(r'^[A-Za-z]$');
  //     // A.i  OR  B.ii  OR  C.10
  //     final letterDotSomething = RegExp(r'^([A-Za-z])\.(.+)$');

  //     if (onlyLetter.hasMatch(rawCode)) {
  //       mainNo = rawCode.toUpperCase();
  //       subNo = '';
  //       lastMainNo = mainNo;
  //       boqCodeToStore = mainNo;
  //     } else {
  //       final m = letterDotSomething.firstMatch(rawCode);
  //       if (m != null) {
  //         mainNo = (m.group(1) ?? '').toUpperCase();
  //         subNo = (m.group(2) ?? '').trim().toLowerCase();
  //         lastMainNo = mainNo;
  //         boqCodeToStore = '$mainNo.$subNo';
  //       } else {
  //         // pure roman like "ii" that likely continues the previous letter section
  //         if (isRoman(rawCode) && lastMainNo.isNotEmpty) {
  //           mainNo = lastMainNo;
  //           subNo = rawCode.toLowerCase();
  //           boqCodeToStore = '$mainNo.$subNo';
  //         } else {
  //           // keep as-is (e.g., "ii" alone)
  //           boqCodeToStore = rawCode;
  //         }
  //       }
  //     }

  //     // If no bill label, fallback
  //     final billLabel =
  //         currentBillLabel.isNotEmpty
  //             ? currentBillLabel
  //             : (currentBillCode.isNotEmpty
  //                 ? 'BILL NO. $currentBillCode'
  //                 : 'BILL');

  //     // If no subheading, fallback using subHeadingNo
  //     final subLabel = currentSubheading;

  //     docsToAdd.add({
  //       'billCode': currentBillCode,
  //       'billLabel': billLabel,

  //       'subHeadingNo': currentSubHeadingNo,
  //       'subheading': subLabel,

  //       'minorNo': currentMinorNo, // ✅ store minor
  //       'minorLabel': currentMinorLabel, // ✅ store minor label

  //       'mainNo': mainNo, // optional
  //       'subNo': subNo, // optional
  //       'boqCode': boqCodeToStore, // normalized display-ish

  //       'description': desc.trim(),
  //       'unit': u,

  //       'quantity': 0.0,
  //       'rate': null,

  //       'structure': structureName.value.trim(),

  //       'order': order++,
  //       'orderKey': makeOrderKey(
  //         billCode: currentBillCode,
  //         subHeadingNo: currentSubHeadingNo,
  //         minorNo: currentMinorNo,
  //         mainNo: mainNo,
  //         subNo: subNo,
  //         fallback: boqCodeToStore,
  //       ),

  //       'createdAt': now,
  //       'updatedAt': now,
  //       'drawingId': drawingId,
  //       'source': 'excel',
  //     });
  //   }

  //   if (docsToAdd.isEmpty) return 0;

  //   // ---- batch insert ----
  //   int added = 0;
  //   int i = 0;
  //   while (i < docsToAdd.length) {
  //     final chunk = docsToAdd.skip(i).take(450).toList();
  //     final b = _db.batch();
  //     for (final data in chunk) {
  //       b.set(boqRef.doc(), data);
  //     }
  //     await b.commit();
  //     added += chunk.length;
  //     i += chunk.length;
  //   }

  //   return added;
  // }

  // stable ordering key so UI grouping stays correct
  //   String makeOrderKey({
  //     required String billCode,
  //     required String subHeadingNo,
  //     required String minorNo,
  //     required String mainNo,
  //     required String subNo,
  //     required String fallback,
  //   }) {
  //     String padBill(String s) {
  //       final n = int.tryParse(s.trim()) ?? 99;
  //       return n.toString().padLeft(2, '0');
  //     }

  //     String padSection(String s) {
  //       if (s.trim().isEmpty) return '999.999.999';
  //       final parts =
  //           s.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
  //       return parts.map((n) => n.toString().padLeft(3, '0')).join('.');
  //     }

  //     int romanToInt(String roman) {
  //       final s = roman.trim().toUpperCase();
  //       if (s.isEmpty) return 999;
  //       const map = {
  //         'I': 1,
  //         'V': 5,
  //         'X': 10,
  //         'L': 50,
  //         'C': 100,
  //         'D': 500,
  //         'M': 1000,
  //       };
  //       int total = 0;
  //       int prev = 0;
  //       for (int i = s.length - 1; i >= 0; i--) {
  //         final v = map[s[i]] ?? 0;
  //         if (v < prev)
  //           total -= v;
  //         else
  //           total += v;
  //         prev = v;
  //       }
  //       return total == 0 ? 999 : total;
  //     }

  //     String padRoman(String s) {
  //       final t = s.trim();
  //       if (t.isEmpty) return '999';
  //       return romanToInt(t).toString().padLeft(3, '0');
  //     }

  //     String padLetter(String s) =>
  //         s.trim().isEmpty ? 'ZZZ' : s.trim().toUpperCase();

  //     // minor & sub might be roman; keep sortable
  //     final minorPart = padRoman(minorNo);
  //     final mainPart = padLetter(mainNo);
  //     final subPart =
  //         isRoman(subNo)
  //             ? padRoman(subNo)
  //             : (int.tryParse(subNo) != null ? subNo.padLeft(3, '0') : '998');

  //     return '${padBill(billCode)}|${padSection(subHeadingNo)}|$minorPart|$mainPart|$subPart|$fallback';
  //   }
  // }
}
