import 'package:aqs/features/boq/boq_order_key_mixin.dart';
import 'package:aqs/features/boq/controllers/boq_template_controller.dart';
import 'package:aqs/features/boq/models/boq_template.dart';
import 'package:aqs/features/utils/helpers/boq_helpers.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

class BoqTemplatePickController extends GetxController with BoqOrderKeyMixin {
  final String projectId;
  final String buildingId;
  final String templateId;
  final String templateName;
  final String? drawingId;

  BoqTemplatePickController({
    required this.projectId,
    required this.buildingId,
    required this.templateId,
    required this.templateName,
    this.drawingId,
  });

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final RxString structureName = ''.obs;
  final RxBool loadingStructure = true.obs;

  @override
  void onInit() {
    super.onInit();
    _loadStructureName();
  }

  DocumentReference<Map<String, dynamic>> get buildingRef => _db
      .collection('projects')
      .doc(projectId)
      .collection('buildings')
      .doc(buildingId);

  CollectionReference<Map<String, dynamic>> get boqRef =>
      buildingRef.collection('boq'); // adjust if needed

  Future<void> _loadStructureName() async {
    try {
      final snap = await buildingRef.get();
      final d = snap.data() ?? <String, dynamic>{};

      // ✅ pick whichever field you store for building display name
      String s(dynamic v) => (v ?? '').toString().trim();

      structureName.value =
          s(d['name']).isNotEmpty
              ? s(d['name'])
              : s(d['title']).isNotEmpty
              ? s(d['title'])
              : s(d['label']).isNotEmpty
              ? s(d['label'])
              : 'Building $buildingId';
    } catch (_) {
      structureName.value = 'Building $buildingId';
    } finally {
      loadingStructure.value = false;
    }
  }

  Future<int> addSelectedToProjectBoq(List<BoqTemplateItem> selected) async {
    if (selected.isEmpty) return 0;

    final templateController =
        Get.isRegistered<BoqTemplateController>()
            ? Get.find<BoqTemplateController>()
            : Get.put(BoqTemplateController());
    await templateController.assertCanUseTemplate(templateId);
    final sourceTemplate = await templateController.getTemplate(templateId);
    if (sourceTemplate?.isDefaultTemplate == true) {
      await templateController.recordAqsTemplateUse(templateId);
    }

    // Ensure structureName loaded
    if (structureName.value.trim().isEmpty) {
      await _loadStructureName();
    }

    // Selected set
    final selectedSet = selected.map((e) => e.id).toSet();

    // Fetch ALL items to carry headings (bill/subheading/minor)
    final allSnap =
        await _db
            .collection('boq_templates')
            .doc(templateId)
            .collection('items')
            .orderBy('order')
            .get();

    final allItems =
        allSnap.docs.map((d) => BoqTemplateItem.fromDoc(d)).toList();
    final allRows = allItems.map((item) => item.raw).toList();
    final isCivilTemplate =
        templateName.toLowerCase().contains('civil') ||
        allItems.any(
          (item) =>
              '${item.raw['boqWorkType']}'.trim().toLowerCase() == 'civil' ||
              '${item.raw['sectionType']}'.trim().toLowerCase() == 'series',
        );
    String rawText(BoqTemplateItem item, String field) =>
        (item.raw[field] ?? '').toString().trim();

    // Carry state
    BoqTemplateItem? currentBillItem;
    BoqTemplateItem? currentSubheadingItem;
    final currentMinorItems = <BoqTemplateItem>[];

    String currentBillLabel = '';
    String currentBillCode = '';
    String currentSubheading = '';
    String currentSubHeadingNo = '';

    String currentMinorLabel = '';
    String currentMinorNo = '';

    String lastMainNo = ''; // A/B/C...

    final nowTs = FieldValue.serverTimestamp();
    final base = DateTime.now().millisecondsSinceEpoch * 1000;

    final toInsert = <Map<String, dynamic>>[];
    final insertedHeadingIds = <String>{};
    int selectedItemsAdded = 0;

    void addHeadingIfNeeded(
      BoqTemplateItem? source,
      Map<String, dynamic> data,
    ) {
      if (source == null) return;
      if (!insertedHeadingIds.add(source.id)) return;
      toInsert.add({
        ...data,
        'structure': structureName.value,
        'sourceTemplateId': templateId,
        'sourceTemplateName': templateName,
        'sourceTemplateScope': sourceTemplate?.templateScope ?? '',
        'sourceTemplateItemId': source.id,
        'createdAt': nowTs,
        'updatedAt': nowTs,
      });
    }

    for (final it in allItems) {
      final rt = it.rowType.toLowerCase();
      final rawCode = it.boqCode.trim();
      final desc = it.description.trim();
      final unit = it.unit.trim();

      if (rt == 'bill') {
        currentBillItem = it;
        currentBillLabel =
            rawText(it, 'billLabel').isNotEmpty
                ? rawText(it, 'billLabel')
                : desc;
        currentBillCode =
            rawText(it, 'billCode').isNotEmpty
                ? rawText(it, 'billCode')
                : billFromLabel(currentBillLabel);
        // reset section context
        currentSubheadingItem = null;
        currentMinorItems.clear();
        currentSubheading = '';
        currentSubHeadingNo = '';
        currentMinorLabel = '';
        currentMinorNo = '';
        lastMainNo = '';
        continue;
      }

      if (rt == 'subheading') {
        currentSubheadingItem = it;
        currentMinorItems.clear();
        currentSubheading =
            rawText(it, 'subheading').isNotEmpty
                ? rawText(it, 'subheading')
                : desc;
        currentSubHeadingNo =
            rawText(it, 'subHeadingNo').isNotEmpty
                ? rawText(it, 'subHeadingNo')
                : rawText(it, 'subheadingNo').isNotEmpty
                ? rawText(it, 'subheadingNo')
                : rawCode.trim();
        currentMinorLabel = '';
        currentMinorNo = '';
        lastMainNo = '';
        continue;
      }

      if (rt == 'minor') {
        if (isCivilTemplate) {
          final cleanCode = rawCode.replaceAll(RegExp(r'^\(|\)$'), '');
          if (RegExp(r'^\d+(?:\.\d+)+').hasMatch(cleanCode)) {
            currentMinorItems.clear();
          }
          currentMinorItems.add(it);
        } else {
          currentMinorItems
            ..clear()
            ..add(it);
        }
        // minor code typically "(i)" or "i"
        currentMinorLabel = desc;
        final storedMinor =
            rawText(it, 'minorNo').isNotEmpty
                ? rawText(it, 'minorNo')
                : rawText(it, 'minorCode');
        final t = rawCode.replaceAll('(', '').replaceAll(')', '').trim();
        currentMinorNo =
            storedMinor.isNotEmpty
                ? storedMinor
                : isCivilTemplate
                ? rawCode
                : isRoman(t)
                ? t.toLowerCase()
                : '';
        lastMainNo = '';
        continue;
      }

      // ITEM
      if (!selectedSet.contains(it.id)) continue;

      // Defensive: must have subHeadingNo to build full codes
      if (currentSubHeadingNo.trim().isEmpty) {
        currentSubHeadingNo =
            '${currentBillCode.isEmpty ? '99' : currentBillCode}.0';
      }

      String fullCode = rawCode;
      String mainNo = '';
      String subNo = '';

      if (isCivilTemplate) {
        fullCode = hierarchicalBoqCodeFromRows(it.raw, allRows);
        mainNo = rawText(it, 'mainNo');
        subNo = rawText(it, 'subNo');
      } else if (looksFullCode(rawCode)) {
        fullCode = rawCode;
        // Optional: you can also parse main/sub from fullCode if you want
      } else {
        // Parse short code and carry "lastMainNo"
        final parsed = parseTemplateShortCode(rawCode, lastMainNo);
        lastMainNo = parsed.lastMainOut;
        mainNo = parsed.mainNo;
        subNo = parsed.subNo;

        fullCode = buildFullBoqCode(
          subHeadingNo: currentSubHeadingNo,
          minorNo: currentMinorNo,
          mainNo: mainNo,
          subNo: subNo,
        );
      }

      final billCodeFinal =
          currentBillCode.isNotEmpty
              ? currentBillCode
              : fullCode.split('.').first;

      final billLabelFinal =
          currentBillLabel.isNotEmpty
              ? currentBillLabel
              : 'BILL NO. $billCodeFinal';

      final orderKey = makeOrderKey(fullCode);
      final rawLeaf = rawCode.replaceAll(RegExp(r'^\(|\)$'), '');
      final leafSuffix = '($rawLeaf)';
      final itemMinorNo =
          isCivilTemplate && rawLeaf.isNotEmpty && fullCode.endsWith(leafSuffix)
              ? fullCode.substring(0, fullCode.length - leafSuffix.length)
              : currentMinorNo;
      final applicableMinorItems =
          isCivilTemplate
              ? currentMinorItems.where((minor) {
                final resolved = hierarchicalBoqCodeFromRows(
                  minor.raw,
                  allRows,
                );
                return resolved.isNotEmpty &&
                    (fullCode == resolved || fullCode.startsWith('$resolved('));
              }).toList()
              : currentMinorItems;
      final itemMinorLabel =
          applicableMinorItems.isEmpty
              ? ''
              : applicableMinorItems.last.description.trim();

      if (currentBillItem != null) {
        addHeadingIfNeeded(currentBillItem, {
          'billCode': billCodeFinal,
          'billLabel': billLabelFinal,
          'boqCode': isCivilTemplate ? currentBillItem.boqCode : '',
          'displayCode':
              isCivilTemplate ? rawText(currentBillItem, 'displayCode') : '',
          'resolvedBoqCode':
              isCivilTemplate
                  ? rawText(currentBillItem, 'resolvedBoqCode')
                  : '',
          'description': billLabelFinal,
          'unit': '',
          'rowType': 'bill',
          'sectionType': isCivilTemplate ? 'series' : 'bill',
          'boqWorkType': isCivilTemplate ? 'civil' : 'building',
          'subHeadingNo': '',
          'subheadingNo': '',
          'subheading': '',
          'minorCode': '',
          'minorNo': '',
          'minorHeading': '',
          'minorLabel': '',
          'mainNo': '',
          'subNo': '',
          'order': base + currentBillItem.order,
          'orderKey': makeOrderKey(''),
        });
      }

      if (currentSubheadingItem != null) {
        addHeadingIfNeeded(currentSubheadingItem, {
          'billCode': billCodeFinal,
          'billLabel': billLabelFinal,
          'boqCode': currentSubHeadingNo,
          'displayCode': currentSubHeadingNo,
          'resolvedBoqCode': currentSubHeadingNo,
          'description': currentSubheading,
          'unit': '',
          'rowType': 'subheading',
          'sectionType': isCivilTemplate ? 'series' : 'bill',
          'boqWorkType': isCivilTemplate ? 'civil' : 'building',
          'subHeadingNo': currentSubHeadingNo,
          'subheadingNo': currentSubHeadingNo,
          'subheading': currentSubheading,
          'minorCode': '',
          'minorNo': '',
          'minorHeading': '',
          'minorLabel': '',
          'mainNo': '',
          'subNo': '',
          'order': base + currentSubheadingItem.order,
          'orderKey': makeOrderKey(currentSubHeadingNo),
        });
      }

      for (final currentMinorItem in applicableMinorItems) {
        final sourceMinorNo =
            rawText(currentMinorItem, 'minorNo').isNotEmpty
                ? rawText(currentMinorItem, 'minorNo')
                : rawText(currentMinorItem, 'minorCode').isNotEmpty
                ? rawText(currentMinorItem, 'minorCode')
                : currentMinorItem.boqCode;
        final sourceMinorLabel =
            rawText(currentMinorItem, 'minorHeading').isNotEmpty
                ? rawText(currentMinorItem, 'minorHeading')
                : rawText(currentMinorItem, 'minorLabel').isNotEmpty
                ? rawText(currentMinorItem, 'minorLabel')
                : currentMinorItem.description.trim();
        final minorResolved =
            isCivilTemplate
                ? hierarchicalBoqCodeFromRows(currentMinorItem.raw, allRows)
                : currentSubHeadingNo.isEmpty || sourceMinorNo.isEmpty
                ? rawCode
                : '$currentSubHeadingNo($sourceMinorNo)';
        addHeadingIfNeeded(currentMinorItem, {
          'billCode': billCodeFinal,
          'billLabel': billLabelFinal,
          'boqCode':
              isCivilTemplate
                  ? currentMinorItem.boqCode
                  : sourceMinorNo.isEmpty
                  ? rawCode
                  : '($sourceMinorNo)',
          'displayCode':
              isCivilTemplate
                  ? currentMinorItem.boqCode
                  : sourceMinorNo.isEmpty
                  ? rawCode
                  : '($sourceMinorNo)',
          'resolvedBoqCode': minorResolved,
          'description': sourceMinorLabel,
          'unit': '',
          'rowType': 'minor',
          'sectionType': isCivilTemplate ? 'series' : 'bill',
          'boqWorkType': isCivilTemplate ? 'civil' : 'building',
          'subHeadingNo': currentSubHeadingNo,
          'subheadingNo': currentSubHeadingNo,
          'subheading': currentSubheading,
          'minorCode': sourceMinorNo,
          'minorNo': sourceMinorNo,
          'minorHeading': sourceMinorLabel,
          'minorLabel': sourceMinorLabel,
          'mainNo': '',
          'subNo': '',
          'order': base + currentMinorItem.order,
          'orderKey': makeOrderKey(minorResolved),
        });
      }

      toInsert.add({
        'billCode': billCodeFinal,
        'billLabel': billLabelFinal,

        'subHeadingNo': currentSubHeadingNo,
        'subheadingNo': currentSubHeadingNo,
        'subheading': currentSubheading,

        // ✅ minor context (fixes missing minor label)
        'minorCode': itemMinorNo,
        'minorNo': itemMinorNo,
        'minorHeading': isCivilTemplate ? itemMinorLabel : currentMinorLabel,
        'minorLabel': isCivilTemplate ? itemMinorLabel : currentMinorLabel,

        // ✅ store split parts too (helps UI/measurement)
        'mainNo': mainNo,
        'subNo': subNo,

        // ✅ store FULL code (fixes roman + heading repeats)
        'boqCode': fullCode,
        'displayCode': rawCode,
        'resolvedBoqCode': fullCode,
        'description': desc,
        'unit': unit,
        'rowType': 'item',
        'sectionType': isCivilTemplate ? 'series' : 'bill',
        'boqWorkType': isCivilTemplate ? 'civil' : 'building',

        'rate': it.rate,
        'structure': structureName.value,

        // keep items inserted together and stable
        'order': base + it.order,
        'orderKey': orderKey,

        'createdAt': nowTs,
        'updatedAt': nowTs,

        // tracing
        'sourceTemplateId': templateId,
        'sourceTemplateName': templateName,
        'sourceTemplateScope': sourceTemplate?.templateScope ?? '',
        'sourceTemplateItemId': it.id, // ✅ helps prevent duplicates later
      });
      selectedItemsAdded++;
    }

    if (toInsert.isEmpty) return 0;

    // Batch insert
    int i = 0;
    while (i < toInsert.length) {
      final chunk = toInsert.skip(i).take(450).toList();
      final b = _db.batch();
      for (final data in chunk) {
        b.set(boqRef.doc(), data);
      }
      await b.commit();
      i += chunk.length;
    }

    return selectedItemsAdded;
  }
}
