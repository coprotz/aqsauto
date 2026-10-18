import 'package:cloud_firestore/cloud_firestore.dart';

class BoqImportResult {
  const BoqImportResult({
    required this.templateId,
    required this.billCount,
    required this.itemCount,
    required this.headingCount,
  });

  final String templateId;
  final int billCount;
  final int itemCount;
  final int headingCount;
}

class BoqImportService {
  BoqImportService._();

  static final instance = BoqImportService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _readString(dynamic value) {
    if (value == null) {
      return '';
    }

    return value.toString().trim();
  }

  double? _readNumber(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    var text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    text = text.replaceAll(',', '');

    text = text.replaceAll('TZS', '');

    text = text.replaceAll('Shs', '');

    text = text.replaceAll('Tsh', '');

    text = text.replaceAll(' ', '');

    return double.tryParse(text);
  }

  String _normalizeUnit(dynamic value) {
    final unit = _readString(value).toLowerCase();

    switch (unit) {
      case 'm':
      case 'lm':
      case 'lin.m':
      case 'lin m':
      case 'metre':
      case 'meter':
      case 'metres':
      case 'meters':
        return 'm';

      case 'm2':
      case 'm²':
      case 'sqm':
      case 'sq.m':
      case 'sq m':
      case 'square metre':
      case 'square meter':
      case 'square metres':
      case 'square meters':
        return 'm2';

      case 'm3':
      case 'm³':
      case 'cum':
      case 'cu.m':
      case 'cu m':
      case 'cubic metre':
      case 'cubic meter':
      case 'cubic metres':
      case 'cubic meters':
        return 'm3';

      case 'nr':
      case 'no':
      case 'nos':
      case 'number':
      case 'each':
      case 'ea':
        return 'no';

      case 'kg':
      case 'kgs':
      case 'kilogram':
      case 'kilograms':
        return 'kg';

      case 'ton':
      case 'tons':
      case 'tonne':
      case 'tonnes':
        return 'tonne';

      case 'ls':
      case 'l.s':
      case 'l.s.':
      case 'lump sum':
        return 'item';

      case 'item':
        return 'item';

      case 'day':
      case 'days':
        return 'day';

      default:
        return unit;
    }
  }

  bool _looksLikeHeading({
    required String itemNo,
    required String description,
    required String unit,
    required double? quantity,
    required double? rate,
  }) {
    if (description.isEmpty) {
      return false;
    }

    /*
     * Typical BOQ headings usually have:
     * - description
     * - no unit
     * - no quantity
     * - no rate
     */
    if (unit.isEmpty && quantity == null && rate == null) {
      return true;
    }

    /*
     * Heading-like item number:
     * BILL 1
     * SECTION A
     */
    final upperDescription = description.toUpperCase();

    if (upperDescription.startsWith('BILL ') ||
        upperDescription.startsWith('SECTION ') ||
        upperDescription.startsWith('SUBSECTION ') ||
        upperDescription.startsWith('PART ')) {
      return true;
    }

    /*
     * Item number alone is not enough
     * to make something an item.
     */
    if (itemNo.isNotEmpty && unit.isEmpty && quantity == null && rate == null) {
      return true;
    }

    return false;
  }

  bool _looksLikeBillHeading(String description) {
    final value = description.trim().toUpperCase();

    return value.startsWith('BILL ') ||
        value.startsWith('BILL NO') ||
        value.startsWith('BILL NO.');
  }

  String _inferMeasurementType({
    required String description,
    required String unit,
  }) {
    final text = description.toLowerCase();

    /*
     * Unit gives the strongest
     * first indication.
     */
    if (unit == 'm') {
      if (text.contains('dpc') ||
          text.contains('skirting') ||
          text.contains('gutter') ||
          text.contains('pipe') ||
          text.contains('beam') ||
          text.contains('lintel')) {
        return 'length';
      }

      return 'length';
    }

    if (unit == 'm2') {
      if (text.contains('wall') ||
          text.contains('block') ||
          text.contains('brick')) {
        return 'wall_area';
      }

      return 'area';
    }

    if (unit == 'm3') {
      if (text.contains('excavat') ||
          text.contains('concrete') ||
          text.contains('backfill') ||
          text.contains('hardcore')) {
        return 'volume';
      }

      return 'volume';
    }

    if (unit == 'no') {
      return 'count';
    }

    if (unit == 'kg' || unit == 'tonne') {
      return 'weight';
    }

    if (unit == 'item') {
      return 'item';
    }

    /*
     * Description fallback.
     */
    if (text.contains('door') ||
        text.contains('window') ||
        text.contains('sanitary')) {
      return 'count';
    }

    return 'manual';
  }

  String _buildBillNumber(int index) {
    return (index + 1).toString();
  }

  Future<BoqImportResult> importBoq({
    required String projectId,
    required String facilityId,
    required String templateName,
    required String originalFileName,
    required String worksheetName,
    required List<Map<String, dynamic>> rows,
  }) async {
    if (projectId.trim().isEmpty) {
      throw Exception('Project ID is required.');
    }
    if (facilityId.trim().isEmpty) {
      throw Exception('Facility ID is required.');
    }

    if (rows.isEmpty) {
      throw Exception('No BOQ rows were provided.');
    }

    final projectRef = _db.collection('projects').doc(projectId);

    final facilityRef = projectRef.collection('facilities').doc(facilityId);

    final templateRef = projectRef.collection('boqTemplates').doc();

    final billsCollection = projectRef.collection('boqBills');

    final itemsCollection = projectRef.collection('boqItems');

    final batch = _db.batch();

    batch.set(templateRef, {
      'templateId': templateRef.id,

      'projectId': projectId,
      'facilityId': facilityId,

      'name': templateName.trim(),

      'originalFileName': originalFileName,

      'worksheetName': worksheetName,

      'status': 'ready',

      'source': 'excel',

      'createdAt': FieldValue.serverTimestamp(),

      'updatedAt': FieldValue.serverTimestamp(),
    });

    int billCount = 0;
    int itemCount = 0;
    int headingCount = 0;
    int sortOrder = 0;

    DocumentReference<Map<String, dynamic>>? currentBillRef;

    String currentBillNumber = '';

    String currentBillTitle = '';

    /*
     * Create a default bill if the
     * imported Excel has no explicit
     * BILL headings.
     */
    Future<DocumentReference<Map<String, dynamic>>> ensureBill() async {
      if (currentBillRef != null) {
        return currentBillRef!;
      }

      currentBillNumber = _buildBillNumber(billCount);

      currentBillTitle = 'Imported BOQ';

      currentBillRef = billsCollection.doc();

      batch.set(currentBillRef!, {
        'billId': currentBillRef!.id,

        'templateId': templateRef.id,

        'projectId': projectId,
        'facilityId': facilityId,

        'number': currentBillNumber,

        'title': currentBillTitle,

        'sortOrder': billCount,

        'createdAt': FieldValue.serverTimestamp(),

        'updatedAt': FieldValue.serverTimestamp(),
      });

      billCount++;

      return currentBillRef!;
    }

    for (final rawRow in rows) {
      final itemNo = _readString(rawRow['itemNo']);

      final description = _readString(rawRow['description']);

      final unit = _normalizeUnit(rawRow['unit']);

      final quantity = _readNumber(rawRow['quantity']);

      final rate = _readNumber(rawRow['rate']);

      final amount = _readNumber(rawRow['amount']);

      if (itemNo.isEmpty && description.isEmpty && unit.isEmpty) {
        continue;
      }

      final isHeading = _looksLikeHeading(
        itemNo: itemNo,
        description: description,
        unit: unit,
        quantity: quantity,
        rate: rate,
      );

      /*
       * New BILL heading.
       */
      if (isHeading && _looksLikeBillHeading(description)) {
        currentBillRef = billsCollection.doc();

        currentBillNumber =
            itemNo.isNotEmpty ? itemNo : _buildBillNumber(billCount);

        currentBillTitle = description;

        batch.set(currentBillRef!, {
          'billId': currentBillRef!.id,

          'templateId': templateRef.id,

          'projectId': projectId,
          'facilityId': facilityId,

          'number': currentBillNumber,

          'title': currentBillTitle,

          'sortOrder': billCount,

          'createdAt': FieldValue.serverTimestamp(),

          'updatedAt': FieldValue.serverTimestamp(),
        });

        billCount++;

        /*
         * We also keep the heading as a
         * BOQ item for visual structure.
         */
        final headingRef = itemsCollection.doc();

        batch.set(headingRef, {
          'boqItemId': headingRef.id,

          'templateId': templateRef.id,

          'projectId': projectId,
          'facilityId': facilityId,

          'billId': currentBillRef!.id,

          'itemNo': itemNo,

          'description': description,

          'unit': '',

          'originalQuantity': null,

          'measuredQuantity': 0.0,

          'approvedQuantity': null,

          'rate': null,

          'amount': null,

          'measurementType': 'heading',

          'isHeading': true,

          'sortOrder': sortOrder++,

          'createdAt': FieldValue.serverTimestamp(),

          'updatedAt': FieldValue.serverTimestamp(),
        });

        headingCount++;

        continue;
      }

      final billRef = await ensureBill();

      final measurementType =
          isHeading
              ? 'heading'
              : _inferMeasurementType(description: description, unit: unit);

      final itemRef = itemsCollection.doc();

      batch.set(itemRef, {
        'boqItemId': itemRef.id,

        'templateId': templateRef.id,

        'projectId': projectId,
        'facilityId': facilityId,

        'billId': billRef.id,

        'billNumber': currentBillNumber,

        'billTitle': currentBillTitle,

        'itemNo': itemNo,

        'description': description,

        'unit': unit,

        'originalQuantity': quantity,

        'measuredQuantity': 0.0,

        'approvedQuantity': null,

        'rate': rate,

        'amount': amount,

        'measurementType': measurementType,

        'isHeading': isHeading,

        'sortOrder': sortOrder++,

        'createdAt': FieldValue.serverTimestamp(),

        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (isHeading) {
        headingCount++;
      } else {
        itemCount++;
      }
    }

    batch.update(templateRef, {
      'billCount': billCount,

      'itemCount': itemCount,

      'headingCount': headingCount,

      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.update(facilityRef, {
      'boqTemplateCount': FieldValue.increment(1),

      'boqItemCount': FieldValue.increment(itemCount),

      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    return BoqImportResult(
      templateId: templateRef.id,

      billCount: billCount,

      itemCount: itemCount,

      headingCount: headingCount,
    );
  }
}
