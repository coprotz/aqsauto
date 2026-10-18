import 'package:aqs/features/core/utils/enums.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PointNorm {
  final double x;
  final double y;

  PointNorm({required this.x, required this.y});

  Map<String, dynamic> toMap() => {'x': x, 'y': y};

  factory PointNorm.fromMap(Map<String, dynamic> map) {
    return PointNorm(
      x: (map['x'] ?? 0).toDouble(),
      y: (map['y'] ?? 0).toDouble(),
    );
  }
}

class Measurement {
  final String id;
  final String projectId;
  final String drawingId;
  final String? boqItemId;
  final MeasurementType type;
  final String unit; // "m", "m2", "nr"
  final double value;
  final List<PointNorm> points;
  final String? sheetNumber;
  final String? note;
  final DateTime createdAt;

  Measurement({
    required this.id,
    required this.projectId,
    required this.drawingId,
    this.boqItemId,
    required this.type,
    required this.unit,
    required this.value,
    required this.points,
    this.sheetNumber,
    this.note,
    required this.createdAt,
  });

  factory Measurement.fromMap(
    String id,
    Map<String, dynamic> map, {
    required String projectId,
    required String drawingId,
  }) {
    return Measurement(
      id: id,
      projectId: projectId,
      drawingId: drawingId,
      boqItemId: map['boqItemId'],
      type: _measurementTypeFromString(map['type'] ?? 'length'),
      unit: map['unit'] ?? '',
      value: (map['value'] ?? 0).toDouble(),
      points:
          (map['points'] as List<dynamic>? ?? [])
              .map((e) => PointNorm.fromMap(e as Map<String, dynamic>))
              .toList(),
      sheetNumber: map['sheetNumber'],
      note: map['note'],
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'boqItemId': boqItemId,
      'type': type.name,
      'unit': unit,
      'value': value,
      'points': points.map((p) => p.toMap()).toList(),
      'sheetNumber': sheetNumber,
      'note': note,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

MeasurementType _measurementTypeFromString(String v) {
  switch (v) {
    case 'area':
      return MeasurementType.area;
    case 'count':
      return MeasurementType.count;
    default:
      return MeasurementType.length;
  }
}
