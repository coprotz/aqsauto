import 'package:cloud_firestore/cloud_firestore.dart';

class ProjectFacility {
  const ProjectFacility({
    required this.id,
    required this.projectId,
    this.siteId = '',
    this.siteName = '',
    required this.name,
    required this.code,
    required this.type,
    required this.description,
    required this.status,
    required this.drawingBundleCount,
    required this.drawingCount,
    required this.boqTemplateCount,
    required this.boqItemCount,
    required this.measurementCount,
    required this.takeoffProgress,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String projectId;
  final String siteId;
  final String siteName;

  final String name;
  final String code;

  /// building
  /// external_works
  /// road
  /// drainage
  /// landscaping
  /// utility
  /// zone
  /// block
  /// other
  final String type;

  final String description;

  /// active
  /// completed
  /// archived
  final String status;

  final int drawingBundleCount;
  final int drawingCount;

  final int boqTemplateCount;
  final int boqItemCount;

  final int measurementCount;

  /// 0.0 - 100.0
  final double takeoffProgress;

  final String createdBy;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive {
    return status.toLowerCase() == 'active';
  }

  bool get hasDrawings {
    return drawingCount > 0;
  }

  bool get hasBoq {
    return boqItemCount > 0;
  }

  bool get canStartTakeoff {
    return hasDrawings && hasBoq;
  }

  String get typeLabel {
    switch (type.toLowerCase()) {
      case 'building':
        return 'Building';

      case 'external_works':
        return 'External Works';

      case 'road':
        return 'Road';

      case 'drainage':
        return 'Drainage';

      case 'landscaping':
        return 'Landscaping';

      case 'utility':
        return 'Utility';

      case 'zone':
        return 'Zone';

      case 'block':
        return 'Block';

      default:
        return 'Other';
    }
  }

  factory ProjectFacility.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};

    int readInt(dynamic value) {
      if (value is int) {
        return value;
      }

      if (value is num) {
        return value.toInt();
      }

      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    double readDouble(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    return ProjectFacility(
      id: doc.id,

      projectId: (data['projectId'] ?? '').toString().trim(),

      siteId: (data['siteId'] ?? '').toString().trim(),

      siteName: (data['siteName'] ?? '').toString().trim(),

      name: (data['name'] ?? 'Untitled Facility').toString().trim(),

      code: (data['code'] ?? '').toString().trim(),

      type: (data['type'] ?? 'building').toString().trim(),

      description: (data['description'] ?? '').toString().trim(),

      status: (data['status'] ?? 'active').toString().trim(),

      drawingBundleCount: readInt(data['drawingBundleCount']),

      drawingCount: readInt(data['drawingCount']),

      boqTemplateCount: readInt(data['boqTemplateCount']),

      boqItemCount: readInt(data['boqItemCount']),

      measurementCount: readInt(data['measurementCount']),

      takeoffProgress: readDouble(data['takeoffProgress']),

      createdBy: (data['createdBy'] ?? '').toString().trim(),

      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),

      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
