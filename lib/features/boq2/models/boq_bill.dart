class BoqBill {
  const BoqBill({
    required this.id,
    required this.projectId,
    required this.number,
    required this.title,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String projectId;

  final String number;
  final String title;

  final int sortOrder;

  final DateTime? createdAt;
  final DateTime? updatedAt;
}
