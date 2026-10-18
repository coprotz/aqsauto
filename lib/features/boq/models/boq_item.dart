import 'package:cloud_firestore/cloud_firestore.dart';

class BoqItem {
  final String id;
  final String billCode;
  final String billLabel;
  final String subHeadingNo;
  final String subheading;

  final String boqCode;
  final String description;
  final String unit;

  final String minorNo; // ✅
  final String minorLabel; // ✅

  final num? quantity;
  final num? rate;
  final num? amount;

  final String orderKey;
  final int order;

  BoqItem({
    required this.id,
    required this.billCode,
    required this.billLabel,
    required this.subHeadingNo,
    required this.subheading,
    required this.boqCode,
    required this.description,
    required this.unit,
    required this.minorNo,
    required this.minorLabel,
    required this.orderKey,
    required this.order,
    this.quantity,
    this.rate,
    this.amount,
  });

  factory BoqItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    String s(dynamic v) => (v ?? '').toString().trim();

    num? n(dynamic v) => v is num ? v : num.tryParse((v ?? '').toString());

    return BoqItem(
      id: doc.id,
      billCode: s(d['billCode']),
      billLabel: s(d['billLabel']),
      subHeadingNo: s(d['subHeadingNo']),
      subheading: s(d['subheading']),
      boqCode: s(d['boqCode']),
      description: s(d['description']),
      unit: s(d['unit']),

      // ✅ IMPORTANT: read these
      minorNo: s(d['minorNo']),
      minorLabel: s(d['minorLabel']),

      orderKey: s(d['orderKey']),
      order:
          (d['order'] is int)
              ? d['order'] as int
              : int.tryParse('${d['order']}') ?? 0,

      quantity: n(d['quantity']),
      rate: n(d['rate']),
      amount: n(d['amount']),
    );
  }
}
