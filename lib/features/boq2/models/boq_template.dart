class BoqTemplate {
  const BoqTemplate({
    required this.id,
    required this.projectId,
    required this.name,
    required this.originalFileName,
    required this.originalFilePath,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String projectId;

  final String name;

  final String originalFileName;
  final String originalFilePath;

  /// importing
  /// ready
  /// failed
  final String status;

  final DateTime? createdAt;
  final DateTime? updatedAt;
}
