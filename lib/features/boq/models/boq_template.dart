import 'package:cloud_firestore/cloud_firestore.dart';

class BoqTemplate {
  final String id;
  final String name;
  final String templateScope;
  final String ownerUid;
  final String createdByUid;
  final bool requiresPaidSubscription;

  BoqTemplate({
    required this.id,
    required this.name,
    required this.templateScope,
    required this.ownerUid,
    required this.createdByUid,
    required this.requiresPaidSubscription,
  });

  factory BoqTemplate.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    String s(dynamic v) => (v ?? '').toString().trim();
    final scope =
        s(d['templateScope']).isNotEmpty
            ? s(d['templateScope'])
            : s(d['scope']).isNotEmpty
            ? s(d['scope'])
            : s(d['visibility']).toLowerCase() == 'private'
            ? 'user'
            : s(d['ownerUid']).isEmpty
            ? 'default'
            : 'user';
    final isDefault =
        scope.toLowerCase() == 'default' || d['isDefault'] == true;
    return BoqTemplate(
      id: doc.id,
      name: s(d['name']),
      templateScope: isDefault ? 'default' : 'user',
      ownerUid: s(d['ownerUid']),
      createdByUid: s(d['createdByUid']),
      requiresPaidSubscription:
          d['requiresPaidSubscription'] is bool
              ? d['requiresPaidSubscription'] as bool
              : isDefault,
    );
  }

  bool get isDefaultTemplate => templateScope.toLowerCase() == 'default';

  bool get isUserTemplate => !isDefaultTemplate;
}

class BoqTemplateItem {
  final String id;
  final String boqCode;
  final String description;
  final String unit;
  final double? rate;

  final int order;
  final String orderKey;
  final String rowType;
  final Map<String, dynamic> raw;

  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  BoqTemplateItem({
    required this.id,
    required this.boqCode,
    required this.description,
    required this.unit,
    this.rate,
    required this.order,
    required this.orderKey,
    required this.rowType,
    this.raw = const <String, dynamic>{},
    this.createdAt,
    this.updatedAt,
  });

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static String _safeRowType(dynamic v) {
    final t = _s(v).toLowerCase();
    const allowed = {'bill', 'subheading', 'minor', 'item'};
    return allowed.contains(t) ? t : 'item';
  }

  static int _safeInt(dynamic v, {int fallback = 999999999}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    final p = int.tryParse(_s(v));
    return p ?? fallback;
  }

  static double? _safeDouble(dynamic v) {
    if (v is num) return v.toDouble();
    final text = _s(
      v,
    ).replaceAll(RegExp(r'[,\s]'), '').replaceAll(RegExp(r'[^0-9\.\-]'), '');
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  factory BoqTemplateItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    final raw = Map<String, dynamic>.from(d)..['id'] = doc.id;

    return BoqTemplateItem(
      id: doc.id,
      boqCode: _s(d['boqCode']),
      description: _s(d['description']),
      unit: _s(d['unit']),
      rate: _safeDouble(d['rate']),
      order: _safeInt(d['order']),
      orderKey: _s(d['orderKey']),
      rowType: _safeRowType(d['rowType']),
      raw: raw,
      createdAt:
          d['createdAt'] is Timestamp ? d['createdAt'] as Timestamp : null,
      updatedAt:
          d['updatedAt'] is Timestamp ? d['updatedAt'] as Timestamp : null,
    );
  }

  Map<String, dynamic> toMapForSave({bool includeTimestamps = false}) {
    final m = <String, dynamic>{
      'boqCode': boqCode.trim(),
      'description': description.trim(),
      'unit': unit.trim(),
      'order': order,
      'orderKey': orderKey,
      'rowType': rowType,
    };
    if (rate != null) m['rate'] = rate;

    const hierarchyFields = [
      'displayCode',
      'resolvedBoqCode',
      'billCode',
      'billLabel',
      'subHeadingNo',
      'subheadingNo',
      'subheading',
      'minorCode',
      'minorNo',
      'minorHeading',
      'minorLabel',
      'mainNo',
      'subNo',
      'sectionType',
      'boqWorkType',
    ];
    for (final field in hierarchyFields) {
      if (raw.containsKey(field)) m[field] = raw[field];
    }

    if (includeTimestamps) {
      m['createdAt'] = createdAt;
      m['updatedAt'] = updatedAt;
    }
    return m;
  }
}
