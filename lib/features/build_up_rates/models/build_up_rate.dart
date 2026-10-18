import 'package:aqs/features/build_up_rates/models/rate_category.dart';
import 'package:aqs/features/build_up_rates/models/rate_component.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BuildUpRate {
  const BuildUpRate({
    required this.rateId,
    required this.name,
    required this.category,
    required this.unit,
    required this.currency,
    required this.finalRate,
    required this.directCost,
    required this.overheadsPercent,
    required this.overheadsAmount,
    required this.profitPercent,
    required this.profitAmount,
    required this.wasteAmount,
    this.description = '',
    this.activity = '',
    this.components = const [],
    this.componentCount = 0,
    this.createdBy = '',
    this.isActive = true,
    this.isTemplate = false,
    this.version = 1,
    this.createdAt,
    this.updatedAt,
  });

  final String rateId;
  final String name;
  final String description;
  final String activity;
  final RateCategory category;
  final String unit;
  final String currency;
  final double finalRate;
  final double directCost;
  final double overheadsPercent;
  final double overheadsAmount;
  final double profitPercent;
  final double profitAmount;
  final double wasteAmount;
  final List<RateComponent> components;
  final int componentCount;
  final String createdBy;
  final bool isActive;
  final bool isTemplate;
  final int version;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory BuildUpRate.fromMap(
    Map<String, dynamic> map,
    String id, {
    List<RateComponent> components = const [],
  }) => BuildUpRate(
    rateId: id,
    name: '${map['name'] ?? ''}',
    description: '${map['description'] ?? ''}',
    activity: '${map['activity'] ?? ''}',
    category: RateCategory.fromValue('${map['category'] ?? 'custom'}'),
    unit: '${map['unit'] ?? ''}',
    currency: '${map['currency'] ?? 'TZS'}',
    finalRate: _number(map['finalRate']),
    directCost: _number(map['directCost']),
    overheadsPercent: _number(map['overheadsPercent']),
    overheadsAmount: _number(map['overheadsAmount']),
    profitPercent: _number(map['profitPercent']),
    profitAmount: _number(map['profitAmount']),
    wasteAmount: _number(map['wasteAmount']),
    components: components,
    componentCount:
        (map['componentCount'] as num?)?.toInt() ?? components.length,
    createdBy: '${map['createdBy'] ?? ''}',
    isActive: map['isActive'] != false,
    isTemplate: map['isTemplate'] == true,
    version: (map['version'] as num?)?.toInt() ?? 1,
    createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
  );

  Map<String, dynamic> toMap() => {
    'rateId': rateId,
    'name': name,
    'description': description,
    'activity': activity,
    'category': category.name,
    'unit': unit,
    'currency': currency,
    'finalRate': finalRate,
    'directCost': directCost,
    'overheadsPercent': overheadsPercent,
    'overheadsAmount': overheadsAmount,
    'profitPercent': profitPercent,
    'profitAmount': profitAmount,
    'wasteAmount': wasteAmount,
    'componentCount': components.length,
    'createdBy': createdBy,
    'isActive': isActive,
    'isTemplate': isTemplate,
    'version': version,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static double _number(dynamic value) => (value as num?)?.toDouble() ?? 0;
}
