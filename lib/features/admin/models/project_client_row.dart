class AdminProjectRow {
  const AdminProjectRow({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.ownerName,
    required this.clientName,
    required this.facilities,
    required this.drawings,
    required this.measurements,
    required this.boqItems,
    required this.createdAt,
  });

  final String id;
  final String name;

  final String ownerId;
  final String ownerName;

  final String clientName;

  final int facilities;
  final int drawings;
  final int measurements;
  final int boqItems;

  final DateTime? createdAt;

  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    return 'Unnamed project';
  }

  String get ownerLabel {
    if (ownerName.trim().isNotEmpty) return ownerName.trim();
    if (ownerId.trim().isNotEmpty) return ownerId.trim();
    return 'Unknown owner';
  }
}
