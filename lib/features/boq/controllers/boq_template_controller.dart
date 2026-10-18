import 'dart:typed_data';

import 'package:aqs/features/billing/services/subscription_service.dart';
import 'package:aqs/features/boq/boq_order_key_mixin.dart';
import 'package:aqs/features/boq/models/boq_template.dart';
import 'package:aqs/features/utils/helpers/boq_helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class AqsTemplateAllowance {
  const AqsTemplateAllowance({
    required this.planName,
    required this.limit,
    required this.usedTemplateIds,
  });

  final String planName;
  final int limit;
  final Set<String> usedTemplateIds;

  int get used => usedTemplateIds.length;
  int get remaining {
    final value = limit - used;
    return value < 0 ? 0 : value;
  }

  bool canUse(String templateId) =>
      usedTemplateIds.contains(templateId) || used < limit;
}

class BoqTemplateController extends GetxController with BoqOrderKeyMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _tplRef =>
      _db.collection('boq_templates');
  String? templateName;
  String? templateId;
  CollectionReference<Map<String, dynamic>> itemsRef(String templateId) =>
      _tplRef.doc(templateId).collection('items');

  String get _uid => _auth.currentUser?.uid ?? '';

  Future<bool> isCurrentUserAdmin() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      final token = await user.getIdTokenResult(true);
      final claims = token.claims ?? {};
      return claims['admin'] == true || claims['role'] == 'admin';
    } catch (_) {
      return false;
    }
  }

  Future<bool> isCurrentUserPaid() async {
    final sub = await SubscriptionService.instance.currentSubscription();
    return sub.isActivePaid;
  }

  Future<AqsTemplateAllowance> currentAqsTemplateAllowance() async {
    final uid = _uid;
    if (uid.isEmpty) {
      return const AqsTemplateAllowance(
        planName: 'Free',
        limit: 3,
        usedTemplateIds: <String>{},
      );
    }

    final subscription =
        await SubscriptionService.instance.currentSubscription();
    final limit = switch (subscription.plan) {
      AqsPlan.free => 3,
      AqsPlan.basic => 10,
      AqsPlan.pro => 50,
      AqsPlan.business => 100,
    };

    final userDoc = await _db.collection('users').doc(uid).get();
    final rawIds = userDoc.data()?['aqsTemplateIdsUsed'];
    final usedIds =
        rawIds is Iterable
            ? rawIds
                .map((value) => value.toString().trim())
                .where((value) => value.isNotEmpty)
                .toSet()
            : <String>{};

    return AqsTemplateAllowance(
      planName: subscription.displayName,
      limit: limit,
      usedTemplateIds: usedIds,
    );
  }

  Future<void> recordAqsTemplateUse(String templateId) async {
    final uid = _uid;
    if (uid.isEmpty) {
      throw ArgumentError('Sign in before using AQS templates.');
    }

    final allowance = await currentAqsTemplateAllowance();
    final userRef = _db.collection('users').doc(uid);
    await _db.runTransaction((transaction) async {
      final userDoc = await transaction.get(userRef);
      final rawIds = userDoc.data()?['aqsTemplateIdsUsed'];
      final usedIds =
          rawIds is Iterable
              ? rawIds
                  .map((value) => value.toString().trim())
                  .where((value) => value.isNotEmpty)
                  .toSet()
              : <String>{};

      if (!usedIds.contains(templateId) && usedIds.length >= allowance.limit) {
        throw ArgumentError(
          '${allowance.planName} allows ${allowance.limit} AQS templates. '
          'Upgrade your plan to use another AQS template.',
        );
      }

      usedIds.add(templateId);
      transaction.set(userRef, {
        'aqsTemplateIdsUsed': usedIds.toList()..sort(),
        'aqsTemplateUsageUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<BoqTemplate?> getTemplate(String templateId) async {
    final snap = await _tplRef.doc(templateId).get();
    if (!snap.exists) return null;
    return BoqTemplate.fromDoc(snap);
  }

  bool _isVisibleToCurrentUser(BoqTemplate template) {
    if (template.isDefaultTemplate) return true;
    return template.ownerUid.isNotEmpty && template.ownerUid == _uid;
  }

  Future<bool> canEditTemplate(BoqTemplate template) async {
    if (template.isDefaultTemplate) {
      final isAdmin = await isCurrentUserAdmin();
      return isAdmin;
    }
    return template.ownerUid.isNotEmpty && template.ownerUid == _uid;
  }

  Future<void> assertCanUseTemplate(String templateId) async {
    final template = await getTemplate(templateId);
    if (template == null) throw ArgumentError('Template was not found.');
    if (!_isVisibleToCurrentUser(template)) {
      throw ArgumentError('You cannot use this template.');
    }
    if (!template.isDefaultTemplate) return;

    final allowance = await currentAqsTemplateAllowance();
    if (!allowance.canUse(templateId)) {
      throw ArgumentError(
        '${allowance.planName} allows ${allowance.limit} AQS templates. '
        'Upgrade your plan to use another AQS template.',
      );
    }
  }

  Future<BoqTemplate> _assertCanEditTemplate(String templateId) async {
    final template = await getTemplate(templateId);
    if (template == null) throw ArgumentError('Template was not found.');
    final canEdit = await canEditTemplate(template);
    if (!canEdit) {
      throw ArgumentError('You cannot edit this template.');
    }
    return template;
  }

  // -----------------------------
  // Streams
  // -----------------------------
  Stream<QuerySnapshot<Map<String, dynamic>>> templatesRawStream() {
    return _tplRef.orderBy('name').snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> itemsRawStream(
    String templateId,
  ) {
    // IMPORTANT: keep Excel order
    return itemsRef(templateId).orderBy('order').snapshots();
  }

  // Backwards-compatible streams (so your existing pages don't change)

  Stream<List<BoqTemplate>> templatesStream() {
    return _tplRef.orderBy('name').snapshots().map((q) {
      return q.docs
          .map((d) => BoqTemplate.fromDoc(d))
          .where(_isVisibleToCurrentUser)
          .toList();
    });
  }

  Stream<List<BoqTemplate>> defaultTemplatesStream() {
    return _tplRef.orderBy('name').snapshots().map((q) {
      return q.docs
          .map((d) => BoqTemplate.fromDoc(d))
          .where((template) => template.isDefaultTemplate)
          .toList();
    });
  }

  Stream<List<BoqTemplate>> myTemplatesStream() {
    return _tplRef.orderBy('name').snapshots().map((q) {
      return q.docs
          .map((d) => BoqTemplate.fromDoc(d))
          .where((template) => template.isUserTemplate)
          .where(_isVisibleToCurrentUser)
          .toList();
    });
  }

  Stream<List<BoqTemplateItem>> itemsStream(String templateId) {
    return itemsRef(templateId).orderBy('order').snapshots().map((q) {
      return q.docs.map((d) => BoqTemplateItem.fromDoc(d)).toList();
    });
  }

  // -----------------------------
  // Templates CRUD
  // -----------------------------
  Future<String> createTemplate(String name, {bool isDefault = false}) async {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('Template name is required');
    final uid = _uid;
    if (uid.isEmpty) throw ArgumentError('Sign in before creating templates.');
    final isAdmin = await isCurrentUserAdmin();
    if (isDefault && !isAdmin) {
      throw ArgumentError('Only admins can create default templates.');
    }

    final now = FieldValue.serverTimestamp();
    final doc = await _tplRef.add({
      'name': n,
      'templateScope': isDefault ? 'default' : 'user',
      'visibility': isDefault ? 'public' : 'private',
      'isDefault': isDefault,
      'ownerUid': isDefault ? '' : uid,
      'createdByUid': uid,
      'requiresPaidSubscription': false,
      'createdAt': now,
      'updatedAt': now,
    });
    return doc.id;
  }

  Future<void> renameTemplate(String templateId, String newName) async {
    final n = newName.trim();
    if (n.isEmpty) throw ArgumentError('New name is required');
    await _assertCanEditTemplate(templateId);

    await _tplRef.doc(templateId).update({
      'name': n,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes all items then the template doc.
  Future<void> deleteTemplate(String templateId) async {
    await _assertCanEditTemplate(templateId);
    // delete subcollection items in batches
    while (true) {
      final snap = await itemsRef(templateId).limit(400).get();
      if (snap.docs.isEmpty) break;

      final b = _db.batch();
      for (final d in snap.docs) {
        b.delete(d.reference);
      }
      await b.commit();
    }

    await _tplRef.doc(templateId).delete();
  }

  // -----------------------------
  // Items CRUD
  // -----------------------------
  Future<void> addItem(
    String templateId, {
    required String boqCode,
    required String description,
    required String unit,
    String rowType = 'item',
  }) async {
    await _assertCanEditTemplate(templateId);
    final code = boqCode.trim();
    final desc = description.trim();
    final u = unit.trim();

    if (code.isEmpty && desc.isEmpty) {
      throw ArgumentError('BOQ code or description is required');
    }

    final now = FieldValue.serverTimestamp();
    await itemsRef(templateId).add({
      'boqCode': code,
      'description': desc,
      'unit': u,
      'rowType': rowType, // bill/subheading/minor/item
      'order': DateTime.now().millisecondsSinceEpoch, // put at end by default
      'orderKey': makeOrderKey(code),
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<void> updateItem(
    String templateId,
    String itemId, {
    required String boqCode,
    required String description,
    required String unit,
    String? rowType, // if null, keep existing
    int? order, // optional manual reorder
  }) async {
    await _assertCanEditTemplate(templateId);
    final code = boqCode.trim();
    final desc = description.trim();
    final u = unit.trim();

    final patch = <String, dynamic>{
      'boqCode': code,
      'description': desc,
      'unit': u,
      'orderKey': makeOrderKey(code),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (rowType != null) patch['rowType'] = rowType;
    if (order != null) patch['order'] = order;

    await itemsRef(templateId).doc(itemId).update(patch);
  }

  Future<void> deleteItem(String templateId, String itemId) async {
    await _assertCanEditTemplate(templateId);
    await itemsRef(templateId).doc(itemId).delete();
  }

  Future<int> importExcelBytes(
    String templateId,
    Uint8List bytes, {
    bool clearExisting = false, // set true if you want to wipe old items first
  }) async {
    final template = await _assertCanEditTemplate(templateId);
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
        col = {'code': cCode, 'desc': cDesc, 'unit': cUnit, 'rate': cRate};
        break;
      }
    }

    // If no headers found, assume fixed: 0=code, 1=desc, 2=unit
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

    final isCivilWorks =
        template.name.toLowerCase().contains('civil') ||
        containsSeriesHeading();

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

    double? parseRate(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return null;
      final cleaned = t
          .replaceAll(RegExp(r'[,\s]'), '')
          .replaceAll(RegExp(r'[^0-9\.\-]'), '');
      if (cleaned.isEmpty) return null;
      return double.tryParse(cleaned);
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
      // e.g. "BILL NO. 3:-SUBSTRUCTURE" -> "3"
      final t = text.toUpperCase();
      final m = RegExp(r'BILL\s*NO\.?\s*(\d+)').firstMatch(t);
      return m?.group(1);
    }

    String? extractSeriesCode(String code, String desc) {
      final match = RegExp(
        r'SERIES\s*(\d+)',
      ).firstMatch('$code $desc'.toUpperCase());
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

    // Detect row type from the raw Excel row
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

    // Parse an item code into parts (main letter and sub roman)
    // Supports:
    // - "A" -> main=A
    // - "B.i" -> main=B, sub=i
    // - "ii" -> sub=ii (main will be taken from lastMain if available)
    ({String main, String sub}) parseItemCode(String raw, String lastMain) {
      final c = normCode(raw);

      // "B.i" / "A.ii"
      final m1 = RegExp(
        r'^([A-Za-z])\.(\s*[ivxlcdm]+)$',
        caseSensitive: false,
      ).firstMatch(c);
      if (m1 != null) {
        final main = (m1.group(1) ?? '').toUpperCase();
        final sub = (m1.group(2) ?? '').trim().toLowerCase();
        return (main: main, sub: sub);
      }

      // "A"
      final m2 = RegExp(r'^([A-Za-z])$').firstMatch(c);
      if (m2 != null) {
        return (main: (m2.group(1) ?? '').toUpperCase(), sub: '');
      }

      // "ii" (roman-only)
      if (isRoman(c)) {
        return (main: lastMain.toUpperCase(), sub: c.toLowerCase());
      }

      // fallback (unknown pattern)
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

      // if no main and no sub, fallback raw
      if (main.isEmpty && sub.isEmpty) return rawFallback.trim();

      final buf = StringBuffer();
      buf.write(sh);

      if (mn.isNotEmpty) {
        buf.write('($mn)');
      }

      if (main.isNotEmpty) {
        buf.write('($main)');
      }

      if (sub.isNotEmpty) {
        buf.write('($sub)');
      }

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

    // Context that we carry while scanning rows
    String currentBillCode = '';
    String currentBillLabel = '';

    String currentSubNo = '';
    String currentSubheading = '';

    String currentMinorNo = '';
    String currentMinorLabel = '';
    final civilMinorPath = <String>[];

    String currentCivilMinorCode() {
      if (civilMinorPath.isEmpty) return '';
      final value = StringBuffer(civilMinorPath.first);
      for (final part in civilMinorPath.skip(1)) {
        value.write('(${part.replaceAll(RegExp(r'^\(|\)$'), '')})');
      }
      return value.toString();
    }

    String lastMainNo = ''; // A/B/C… last seen for roman-only rows

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
      final rate = parseRate(rawRate);

      if (code.isEmpty && desc.isEmpty && unit.isEmpty && rawRate.isEmpty) {
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

        // reset lower contexts
        currentSubNo = '';
        currentSubheading = '';
        currentMinorNo = '';
        currentMinorLabel = '';
        civilMinorPath.clear();
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
          'subheadingNo': '',
          'subheading': '',
          'minorCode': '',
          'minorNo': '',
          'minorHeading': '',
          'minorLabel': '',
          'mainNo': '',
          'subNo': '',
          'order': order++,
          'orderKey': makeOrderKey(''), // ok
          'createdAt': now,
          'updatedAt': now,
        });
        continue;
      }

      // ---- SUBHEADING (3.1 / 3.7) ----
      if (rowType == 'subheading') {
        currentSubNo = isCivilWorks ? extractCivilSectionCode(code) : code;
        currentSubheading =
            (isCivilWorks && desc.isEmpty ? code : desc).toUpperCase();

        // reset minor + lastMain under new subheading
        currentMinorNo = '';
        currentMinorLabel = '';
        civilMinorPath.clear();
        lastMainNo = '';

        // If billCode not set from BILL row, infer from subheading (first segment)
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
          'subHeadingNo': currentSubNo,
          'subheadingNo': currentSubNo,
          'subheading': currentSubheading,
          'minorCode': '',
          'minorNo': '',
          'minorHeading': '',
          'minorLabel': '',
          'mainNo': '',
          'subNo': '',
          'order': order++,
          'orderKey': makeOrderKey(currentSubNo),
          'createdAt': now,
          'updatedAt': now,
        });
        continue;
      }

      // ---- MINOR ((i) / i) ----
      if (rowType == 'minor') {
        currentMinorNo = isCivilWorks ? code : stripParen(code).toLowerCase();
        currentMinorLabel = desc; // keep original, UI can upper later
        if (isCivilWorks && currentMinorNo.isNotEmpty) {
          final clean = currentMinorNo.replaceAll(RegExp(r'^\(|\)$'), '');
          if (RegExp(r'^\d+(?:\.\d+)+').hasMatch(clean)) {
            civilMinorPath.clear();
          }
          civilMinorPath.add(clean);
        }

        // reset main under new minor section
        lastMainNo = '';

        final minorResolved =
            isCivilWorks
                ? civilResolvedBoqCode(
                  minorCode: currentCivilMinorCode(),
                  rawCode: '',
                )
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
          'subHeadingNo': currentSubNo,
          'subheadingNo': currentSubNo,
          'subheading': currentSubheading,
          'minorCode': currentMinorNo,
          'minorNo': currentMinorNo,
          'minorHeading': currentMinorLabel,
          'minorLabel': currentMinorLabel,
          'mainNo': '',
          'subNo': '',
          'order': order++,
          'orderKey': makeOrderKey(minorResolved),
          'createdAt': now,
          'updatedAt': now,
        });
        continue;
      }

      // ---- ITEM ----
      // Parse main/sub from item code (supports roman-only rows)
      final parts = parseItemCode(code, lastMainNo);
      final mainNo = parts.main; // may be '' if unknown
      final subNo = parts.sub; // may be ''

      // If this row has a main letter, update lastMainNo (so next roman-only rows attach)
      if (mainNo.isNotEmpty) {
        lastMainNo = mainNo;
      }

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
              ? civilResolvedBoqCode(
                minorCode: currentCivilMinorCode(),
                rawCode: code,
              )
              : resolved;

      docsToAdd.add({
        // keep what was in Excel (raw), but also store resolved
        'boqCode': code,
        'displayCode': isCivilWorks ? code : displayCode,
        'resolvedBoqCode': storedResolved,

        'description': desc,
        'unit': unit,
        'rowType': 'item',
        'sectionType': isCivilWorks ? 'series' : 'bill',
        'boqWorkType': isCivilWorks ? 'civil' : 'building',
        if (rate != null) 'rate': rate,

        // context
        'billCode': currentBillCode,
        'billLabel': currentBillLabel,
        'subHeadingNo': currentSubNo,
        'subheadingNo': currentSubNo,
        'subheading': currentSubheading,
        'minorCode': isCivilWorks ? currentCivilMinorCode() : currentMinorNo,
        'minorNo': isCivilWorks ? currentCivilMinorCode() : currentMinorNo,
        'minorHeading': currentMinorLabel,
        'minorLabel': currentMinorLabel,
        'mainNo': mainNo,
        'subNo': subNo,

        // ordering
        'order': order++,
        'orderKey': makeOrderKey(storedResolved),

        'createdAt': now,
        'updatedAt': now,
      });
    }

    if (docsToAdd.isEmpty) return 0;

    if (clearExisting) {
      await _deleteAllItems(templateId);
    }

    // -----------------------------
    // 4) Batch write (Firestore limit 500)
    // -----------------------------
    int added = 0;
    int i = 0;
    while (i < docsToAdd.length) {
      final chunk = docsToAdd.skip(i).take(450).toList();
      final b = _db.batch();

      for (final data in chunk) {
        final ref = itemsRef(templateId).doc();
        b.set(ref, data);
      }

      await b.commit();
      added += chunk.length;
      i += chunk.length;
    }

    return added;
  }

  Future<void> _deleteAllItems(String templateId) async {
    while (true) {
      final snap = await itemsRef(templateId).limit(400).get();
      if (snap.docs.isEmpty) break;
      final b = _db.batch();
      for (final d in snap.docs) {
        b.delete(d.reference);
      }
      await b.commit();
    }
  }

  // -----------------------------
  // OrderKey builder (kept for later grouping)
  // -----------------------------
  /// Builds a stable sortable key from boqCode.
  /// Handles patterns like:
  /// - 3.1(A)
  /// - 3.7(i)(A)(ii)
  /// - 3.7(A)(ii)
  ///
  /// NOTE: For template display we sort by 'order', not this key.
  // String makeOrderKey(String boqCode) {
  //   final c = boqCode.trim();
  //   if (c.isEmpty) {
  //     return '99|999.999.999|999|ZZZ|999|';
  //   }

  //   final section = _extractSection(c); // "3.7"
  //   final toks = _parenTokens(c); // inside (...)

  //   String minor = '';
  //   String main = '';
  //   String sub = '';

  //   // 3.7(i)(A)(ii) => minor=i, main=A, sub=ii
  //   if (toks.length >= 2 && _isRoman(toks[0]) && _isLetter(toks[1])) {
  //     minor = toks[0].toLowerCase();
  //     main = toks[1].toUpperCase();
  //     if (toks.length >= 3) sub = toks[2].toLowerCase();
  //   }
  //   // 3.7(A)(ii) => main=A, sub=ii
  //   else if (toks.isNotEmpty && _isLetter(toks[0])) {
  //     main = toks[0].toUpperCase();
  //     if (toks.length >= 2) sub = toks[1].toLowerCase();
  //   }

  //   final bill = _extractBill(section);
  //   return '${bill.padLeft(2, '0')}|${_padSection(section)}|'
  //       '${_padRoman(minor)}|${_padLetter(main)}|${_padSub(sub)}|$c';
  // }

  String _extractSection(String code) {
    final idx = code.indexOf('(');
    final head = (idx == -1) ? code : code.substring(0, idx);
    final m = RegExp(r'^\d+(?:\.\d+)*').firstMatch(head.trim());
    return (m?.group(0) ?? head.trim());
  }

  String _extractBill(String section) {
    final p = section.split('.').first.trim();
    return p.isEmpty ? '99' : p;
  }

  String _padSection(String section) {
    final parts = section.split('.').map((e) => e.trim()).toList();
    return parts
        .map((e) => (int.tryParse(e) ?? 0).toString().padLeft(3, '0'))
        .join('.');
  }

  String _padLetter(String s) {
    final t = s.trim();
    if (t.isEmpty) return 'ZZZ';
    return t.toUpperCase();
  }

  String _padRoman(String r) {
    final t = r.trim();
    if (t.isEmpty) return '999';
    return _romanToInt(t).toString().padLeft(3, '0');
  }

  String _padSub(String s) {
    final t = s.trim().toLowerCase();
    if (t.isEmpty) return '999';
    if (_isRoman(t)) return _romanToInt(t).toString().padLeft(3, '0');
    final n = int.tryParse(t);
    if (n != null) return n.toString().padLeft(3, '0');
    return '998';
  }

  List<String> _parenTokens(String code) {
    return RegExp(r'\(([^)]+)\)')
        .allMatches(code)
        .map((m) => (m.group(1) ?? '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  bool _isRoman(String x) =>
      RegExp(r'^[ivxlcdm]+$', caseSensitive: false).hasMatch(x.trim());

  bool _isLetter(String x) => RegExp(r'^[A-Za-z]$').hasMatch(x.trim());

  int _romanToInt(String roman) {
    final s = roman.trim().toUpperCase();
    if (s.isEmpty) return 999;
    const map = <String, int>{
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
    for (int i = s.length - 1; i >= 0; i--) {
      final v = map[s[i]] ?? 0;
      if (v < prev) {
        total -= v;
      } else {
        total += v;
      }
      prev = v;
    }
    return total == 0 ? 999 : total;
  }
}
