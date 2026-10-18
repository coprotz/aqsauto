import 'package:cloud_firestore/cloud_firestore.dart';

class DrawingDoc {
  final String id;
  final String projectId;
  final String title;
  final String filePath;
  final String? sheetNumber;
  final String scaleText;
  final bool calibrated;
  final String unit; // "m"
  final double pixelsPerUnit;
  final DateTime createdAt;

  DrawingDoc({
    required this.id,
    required this.projectId,
    required this.title,
    required this.filePath,
    this.sheetNumber,
    required this.scaleText,
    required this.calibrated,
    required this.unit,
    required this.pixelsPerUnit,
    required this.createdAt,
  });

  factory DrawingDoc.fromMap(
    String id,
    Map<String, dynamic> map, {
    required String projectId,
  }) {
    return DrawingDoc(
      id: id,
      projectId: projectId,
      title: map['title'] ?? '',
      filePath: map['filePath'] ?? '',
      sheetNumber: map['sheetNumber'],
      scaleText: map['scaleText'] ?? '',
      calibrated: map['calibrated'] ?? false,
      unit: map['unit'] ?? 'm',
      pixelsPerUnit: (map['pixelsPerUnit'] ?? 0).toDouble(),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'filePath': filePath,
      'sheetNumber': sheetNumber,
      'scaleText': scaleText,
      'calibrated': calibrated,
      'unit': unit,
      'pixelsPerUnit': pixelsPerUnit,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
