import 'package:cloud_firestore/cloud_firestore.dart';

class AqsProject {
  const AqsProject({
    required this.id,
    required this.name,
    required this.code,
    required this.clientName,
    required this.location,
    required this.description,
    required this.status,
    required this.ownerId,
    required this.members,
    required this.currency,
    required this.measurementStandard,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  final String name;
  final String code;

  final String clientName;
  final String location;
  final String description;

  final String status;

  final String ownerId;
  final List<String> members;

  final String currency;

  final String measurementStandard;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool isOwner(String uid) {
    return ownerId == uid;
  }

  bool isMember(String uid) {
    return members.contains(uid);
  }

  bool get isActive {
    return status.toLowerCase() == 'active';
  }

  factory AqsProject.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    final rawMembers = data['members'] as List? ?? const [];

    return AqsProject(
      id: doc.id,

      name: (data['name'] ?? 'Untitled Project').toString().trim(),

      code: (data['code'] ?? '').toString().trim(),

      clientName: (data['clientName'] ?? '').toString().trim(),

      location: (data['location'] ?? '').toString().trim(),

      description: (data['description'] ?? '').toString().trim(),

      status: (data['status'] ?? 'active').toString().trim(),

      ownerId: (data['ownerId'] ?? '').toString().trim(),

      members: rawMembers.map((value) => value.toString()).toList(),

      currency: (data['currency'] ?? 'TZS').toString().trim(),

      measurementStandard:
          (data['measurementStandard'] ?? 'Standard').toString().trim(),

      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),

      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
