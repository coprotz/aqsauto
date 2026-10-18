import 'package:aqs/features/takeoff/models/drawing_calibration.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DrawingSheet {
  const DrawingSheet({
    required this.id,
    required this.projectId,
    required this.facilityId,
    required this.bundleId,
    required this.sourcePageNumber,
    required this.sortOrder,
    required this.sourceFileName,
    required this.drawingNumber,
    required this.title,
    required this.discipline,
    required this.revision,
    required this.pageNumber,
    required this.pdfPath,
    required this.thumbnailPath,
    required this.scaleType,
    required this.scaleRatio,
    required this.status,
    required this.calibrated,
    required this.measurementCount,
    required this.pdfSizeBytes,
    required this.storageBytes,
    required this.calibration,
    required this.createdAt,
    required this.updatedAt,
    required this.downloadUrl,
  });

  final String id;

  final String projectId;
  final String facilityId;
  final String bundleId;

  final int sourcePageNumber;
  final int sortOrder;
  final String sourceFileName;

  final String drawingNumber;
  final String title;

  final String discipline;
  final String revision;

  final int pageNumber;

  final String pdfPath;
  final String thumbnailPath;
  final String downloadUrl;

  /// drawing_scale
  /// calibrated
  /// unknown
  final String scaleType;

  /// Example:
  /// 100 means 1:100
  final double? scaleRatio;

  /// ready
  /// needs_calibration
  /// in_progress
  /// measured
  /// superseded
  final String status;

  final bool calibrated;

  final int measurementCount;

  final int pdfSizeBytes;
  final int storageBytes;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DrawingCalibration? calibration;

  bool get needsCalibration {
    return !calibrated;
  }

  bool get hasMeasurements {
    return measurementCount > 0;
  }

  factory DrawingSheet.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final calibrationData = data['calibration'];

    int readInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();

      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    double? readDouble(dynamic value) {
      if (value == null) return null;

      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value.toString());
    }

    return DrawingSheet(
      id: doc.id,

      projectId: (data['projectId'] ?? '').toString().trim(),

      facilityId:
          (data['facilityId'] ?? data['buildingId'] ?? '').toString().trim(),

      bundleId: (data['bundleId'] ?? '').toString().trim(),
      sourceFileName: (data['sourceFileName'] ?? '').toString().trim(),
      calibration:
          calibrationData is Map<String, dynamic>
              ? DrawingCalibration.fromMap(calibrationData)
              : calibrationData is Map
              ? DrawingCalibration.fromMap(
                Map<String, dynamic>.from(calibrationData),
              )
              : null,

      drawingNumber:
          (data['drawingNumber'] ?? data['sheetNumber'] ?? '')
              .toString()
              .trim(),

      title: (data['title'] ?? 'Untitled Drawing').toString().trim(),
      downloadUrl: (data['downloadUrl'] ?? '').toString(),

      discipline: (data['discipline'] ?? 'general').toString().trim(),

      revision: (data['revision'] ?? '').toString().trim(),

      pageNumber: readInt(data['pageNumber']),
      sourcePageNumber: readInt(data['sourcePageNumber']),

      sortOrder: readInt(data['sortOrder']),

      pdfPath: (data['pdfPath'] ?? data['filePath'] ?? '').toString().trim(),

      thumbnailPath:
          (data['thumbnailPath'] ?? data['imagePath'] ?? '').toString().trim(),

      scaleType: (data['scaleType'] ?? 'unknown').toString().trim(),

      scaleRatio: readDouble(data['scaleRatio']),

      status:
          (data['status'] ?? data['processingStatus'] ?? 'needs_calibration')
              .toString()
              .trim(),

      calibrated: data['calibrated'] == true,

      measurementCount: readInt(data['measurementCount']),

      pdfSizeBytes: readInt(
        data['pdfSizeBytes'] ?? data['estimatedPdfSizeBytes'],
      ),

      storageBytes: readInt(data['storageBytes'] ?? data['pdfSizeBytes']),

      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),

      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
