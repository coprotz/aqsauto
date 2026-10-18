class BoqItem {
  const BoqItem({
    required this.id,
    required this.projectId,
    required this.billId,
    required this.itemNo,
    required this.description,
    required this.unit,
    required this.originalQuantity,
    required this.measuredQuantity,
    required this.approvedQuantity,
    required this.rate,
    required this.amount,
    required this.measurementType,
    required this.sortOrder,
    required this.isHeading,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String projectId;
  final String billId;

  final String itemNo;
  final String description;
  final String unit;

  final double? originalQuantity;
  final double measuredQuantity;
  final double? approvedQuantity;

  final double? rate;
  final double? amount;

  /// Examples:
  /// length
  /// area
  /// count
  /// wall_area
  /// volume
  /// composite
  final String measurementType;

  final int sortOrder;

  /// Allows us to preserve BOQ headings,
  /// sections and sub-sections.
  final bool isHeading;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get currentQuantity {
    if (approvedQuantity != null) {
      return approvedQuantity!;
    }

    if (measuredQuantity > 0) {
      return measuredQuantity;
    }

    return originalQuantity ?? 0;
  }

  double? get calculatedAmount {
    if (rate == null) {
      return amount;
    }

    return currentQuantity * rate!;
  }

  BoqItem copyWith({
    String? id,
    String? projectId,
    String? billId,
    String? itemNo,
    String? description,
    String? unit,
    double? originalQuantity,
    double? measuredQuantity,
    double? approvedQuantity,
    double? rate,
    double? amount,
    String? measurementType,
    int? sortOrder,
    bool? isHeading,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BoqItem(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      billId: billId ?? this.billId,
      itemNo: itemNo ?? this.itemNo,
      description: description ?? this.description,
      unit: unit ?? this.unit,
      originalQuantity: originalQuantity ?? this.originalQuantity,
      measuredQuantity: measuredQuantity ?? this.measuredQuantity,
      approvedQuantity: approvedQuantity ?? this.approvedQuantity,
      rate: rate ?? this.rate,
      amount: amount ?? this.amount,
      measurementType: measurementType ?? this.measurementType,
      sortOrder: sortOrder ?? this.sortOrder,
      isHeading: isHeading ?? this.isHeading,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
