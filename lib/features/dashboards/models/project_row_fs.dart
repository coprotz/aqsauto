import 'package:aqs/features/utils/enum.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProjectRowFs {
  final String id;
  final String name;
  final String clientName;
  final String currency;
  final ProjectStage stage;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  // ✅ add
  final int ipcCount;
  final bool hasContractAward;

  ProjectRowFs({
    required this.id,
    required this.name,
    required this.clientName,
    required this.currency,
    required this.stage,
    required this.createdAt,
    required this.updatedAt,
    required this.ipcCount,
    required this.hasContractAward,
  });

  factory ProjectRowFs.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return ProjectRowFs(
      id: doc.id,
      name: (d['name'] ?? '').toString().trim(),
      clientName: (d['clientName'] ?? d['client'] ?? '').toString().trim(),
      currency: (d['currency'] ?? '').toString().trim(),
      stage: stageFromStatus(d['status']?.toString()),
      createdAt: d['createdAt'] as Timestamp?,
      updatedAt: d['updatedAt'] as Timestamp?,

      // ✅ safe parsing
      ipcCount:
          (d['ipcCount'] is num)
              ? (d['ipcCount'] as num).toInt()
              : int.tryParse('${d['ipcCount'] ?? 0}') ?? 0,
      hasContractAward: (d['hasContractAward'] == true),
    );
  }
}
