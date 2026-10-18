import 'package:aqs/features/build_up_rates/models/rate_category.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RateResource {
  const RateResource({
    required this.resourceId,
    required this.name,
    required this.category,
    required this.unit,
    required this.currentRate,
    this.currency = 'TZS',
    this.supplier = '',
    this.notes = '',
  });

  final String resourceId;
  final String name;
  final RateComponentType category;
  final String unit;
  final double currentRate;
  final String currency;
  final String supplier;
  final String notes;

  factory RateResource.fromMap(Map<String, dynamic> map, String id) =>
      RateResource(
        resourceId: id,
        name: '${map['name'] ?? ''}',
        category: RateComponentType.fromValue('${map['category'] ?? 'other'}'),
        unit: '${map['unit'] ?? ''}',
        currentRate: (map['currentRate'] as num?)?.toDouble() ?? 0,
        currency: '${map['currency'] ?? 'TZS'}',
        supplier: '${map['supplier'] ?? ''}',
        notes: '${map['notes'] ?? ''}',
      );

  Map<String, dynamic> toMap() => {
    'resourceId': resourceId,
    'name': name,
    'category': category.name,
    'unit': unit,
    'currentRate': currentRate,
    'currency': currency,
    'supplier': supplier,
    'notes': notes,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
