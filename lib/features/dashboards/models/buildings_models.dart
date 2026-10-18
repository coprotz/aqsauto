import 'package:cloud_firestore/cloud_firestore.dart';

/// --------------------- MODELS ---------------------
class BuildingRowFs {
  final String id;
  final String code; // e.g. "PART B(8)"
  final String name; // e.g. "WAITING SHED"
  final String siteId;
  final String siteName;
  final Timestamp? createdAt;

  const BuildingRowFs({
    required this.id,
    required this.code,
    required this.name,
    this.siteId = '',
    this.siteName = '',
    required this.createdAt,
  });

  factory BuildingRowFs.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return BuildingRowFs(
      id: doc.id,
      code: (d['code'] ?? '').toString().trim(),
      name: (d['name'] ?? '').toString().trim(),
      siteId: (d['siteId'] ?? '').toString().trim(),
      siteName: (d['siteName'] ?? '').toString().trim(),
      createdAt: d['createdAt'] as Timestamp?,
    );
  }
}

/// counts under building
class BuildingCounts {
  final int drawings;
  final int measurements;
  final int boqItems;

  const BuildingCounts({
    required this.drawings,
    required this.measurements,
    required this.boqItems,
  });
}

class BuildingFinancialSummary {
  final int totalBoqItems;
  final int measuredBoqItems;
  final double measuredWorksAmount;
  final double buildingAllowancesAmount;

  const BuildingFinancialSummary({
    required this.totalBoqItems,
    required this.measuredBoqItems,
    required this.measuredWorksAmount,
    required this.buildingAllowancesAmount,
  });

  double get coverage =>
      totalBoqItems == 0 ? 0 : measuredBoqItems / totalBoqItems;

  double get totalAmount => measuredWorksAmount + buildingAllowancesAmount;
}
