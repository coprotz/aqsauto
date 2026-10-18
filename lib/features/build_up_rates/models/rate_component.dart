import 'package:aqs/features/build_up_rates/models/rate_category.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RateComponent {
  const RateComponent({
    required this.componentId,
    required this.type,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitRate,
    this.description = '',
    this.wastePercent = 0,
    this.sortOrder = 0,
  });

  final String componentId;
  final RateComponentType type;
  final String name;
  final String description;
  final String unit;
  final double quantity;
  final double unitRate;
  final double wastePercent;
  final int sortOrder;

  double get baseAmount => quantity * unitRate;
  double get wasteAmount => baseAmount * wastePercent / 100;
  double get amount => baseAmount + wasteAmount;

  RateComponent copyWith({
    String? componentId,
    RateComponentType? type,
    String? name,
    String? description,
    String? unit,
    double? quantity,
    double? unitRate,
    double? wastePercent,
    int? sortOrder,
  }) => RateComponent(
    componentId: componentId ?? this.componentId,
    type: type ?? this.type,
    name: name ?? this.name,
    description: description ?? this.description,
    unit: unit ?? this.unit,
    quantity: quantity ?? this.quantity,
    unitRate: unitRate ?? this.unitRate,
    wastePercent: wastePercent ?? this.wastePercent,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  factory RateComponent.fromMap(Map<String, dynamic> map, String id) =>
      RateComponent(
        componentId: id,
        type: RateComponentType.fromValue('${map['type'] ?? 'other'}'),
        name: '${map['name'] ?? ''}',
        description: '${map['description'] ?? ''}',
        unit: '${map['unit'] ?? ''}',
        quantity: _number(map['quantity']),
        unitRate: _number(map['unitRate']),
        wastePercent: _number(map['wastePercent']),
        sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
    'componentId': componentId,
    'type': type.name,
    'name': name,
    'description': description,
    'unit': unit,
    'quantity': quantity,
    'unitRate': unitRate,
    'wastePercent': wastePercent,
    'amount': amount,
    'sortOrder': sortOrder,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static double _number(dynamic value) {
    final result =
        value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    return result.isFinite ? result : 0;
  }
}
