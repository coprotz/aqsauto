import 'package:cloud_firestore/cloud_firestore.dart';

class DrawingBundle {
  const DrawingBundle({
    required this.id,
    required this.projectId,
    required this.facilityId,
    required this.name,
    required this.discipline,
    required this.issueType,
    required this.revision,
    required this.description,
    required this.fileName,
    required this.storagePath,
    required this.pageCount,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String projectId;
  final String facilityId;

  final String name;

  /// architectural
  /// structural
  /// civil
  /// mechanical
  /// electrical
  /// plumbing
  /// landscaping
  /// general
  /// other
  final String discipline;

  /// tender
  /// construction
  /// as_built
  /// revised
  /// preliminary
  /// other
  final String issueType;

  final String revision;
  final String description;

  final String fileName;
  final String storagePath;

  final int pageCount;

  /// uploading
  /// processing
  /// ready
  /// failed
  /// superseded
  final String status;

  final String createdBy;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isReady {
    return status.toLowerCase() == 'ready';
  }

  String get disciplineLabel {
    switch (discipline.toLowerCase()) {
      case 'architectural':
        return 'Architectural';

      case 'structural':
        return 'Structural';

      case 'civil':
        return 'Civil';

      case 'mechanical':
        return 'Mechanical';

      case 'electrical':
        return 'Electrical';

      case 'plumbing':
        return 'Plumbing';

      case 'landscaping':
        return 'Landscaping';

      case 'general':
        return 'General';

      default:
        return 'Other';
    }
  }

  factory DrawingBundle.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};

    int readInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();

      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return DrawingBundle(
      id: doc.id,

      projectId: (data['projectId'] ?? '').toString().trim(),

      facilityId: (data['facilityId'] ?? '').toString().trim(),

      name: (data['name'] ?? 'Drawing Bundle').toString().trim(),

      discipline: (data['discipline'] ?? 'general').toString().trim(),

      issueType: (data['issueType'] ?? 'construction').toString().trim(),

      revision: (data['revision'] ?? '').toString().trim(),

      description: (data['description'] ?? '').toString().trim(),

      fileName: (data['fileName'] ?? '').toString().trim(),

      storagePath: (data['storagePath'] ?? '').toString().trim(),

      pageCount: readInt(data['selectedPageCount'] ?? data['pageCount']),

      status: (data['status'] ?? 'uploading').toString().trim(),

      createdBy: (data['createdBy'] ?? '').toString().trim(),

      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),

      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
