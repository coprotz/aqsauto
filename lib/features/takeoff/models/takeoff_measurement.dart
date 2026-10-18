import 'package:cloud_firestore/cloud_firestore.dart';

class TakeOffMeasurement {
  const TakeOffMeasurement({
    required this.id,
    required this.projectId,
    required this.facilityId,
    required this.drawingId,
    required this.bundleId,
    required this.category,
    required this.subTool,
    required this.measurementType,
    required this.pointAX,
    required this.pointAY,
    required this.pointBX,
    required this.pointBY,
    required this.quantity,
    required this.unit,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String projectId;
  final String facilityId;
  final String drawingId;
  final String bundleId;

  final String category;
  final String subTool;
  final String measurementType;

  final double pointAX;
  final double pointAY;
  final double pointBX;
  final double pointBY;

  final double quantity;
  final String unit;

  final String status;

  final DateTime? createdAt;

  factory TakeOffMeasurement.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    final points =
        data['points'] is Map
            ? Map<String, dynamic>.from(data['points'] as Map)
            : <String, dynamic>{};

    final pointA =
        points['a'] is Map
            ? Map<String, dynamic>.from(points['a'] as Map)
            : <String, dynamic>{};

    final pointB =
        points['b'] is Map
            ? Map<String, dynamic>.from(points['b'] as Map)
            : <String, dynamic>{};

    return TakeOffMeasurement(
      id: doc.id,
      projectId: (data['projectId'] ?? '').toString(),
      facilityId: (data['facilityId'] ?? '').toString(),
      drawingId: (data['drawingId'] ?? '').toString(),
      bundleId: (data['bundleId'] ?? '').toString(),

      category: (data['category'] ?? '').toString(),

      subTool: (data['subTool'] ?? '').toString(),

      measurementType: (data['measurementType'] ?? '').toString(),

      pointAX: (pointA['x'] as num?)?.toDouble() ?? 0,

      pointAY: (pointA['y'] as num?)?.toDouble() ?? 0,

      pointBX: (pointB['x'] as num?)?.toDouble() ?? 0,

      pointBY: (pointB['y'] as num?)?.toDouble() ?? 0,

      quantity: (data['quantity'] as num?)?.toDouble() ?? 0,

      unit: (data['unit'] ?? '').toString(),

      status: (data['status'] ?? 'active').toString(),

      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
