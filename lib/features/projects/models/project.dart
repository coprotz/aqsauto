import 'package:cloud_firestore/cloud_firestore.dart';

class Project {
  final String id;
  final String name;
  final String? clientName;
  final String? location;
  final String currency;
  final DateTime createdAt;

  Project({
    required this.id,
    required this.name,
    this.clientName,
    this.location,
    required this.currency,
    required this.createdAt,
  });

  factory Project.fromMap(String id, Map<String, dynamic> map) {
    return Project(
      id: id,
      name: map['name'] ?? '',
      clientName: map['clientName'],
      location: map['location'],
      currency: map['currency'] ?? 'TZS',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'clientName': clientName,
      'location': location,
      'currency': currency,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
