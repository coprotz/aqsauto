import 'package:aqs/features/utils/enum.dart';

class ProjectRow {
  final String id;
  String name;
  ProjectStage stage;
  String lastActive;
  String revision;
  int files;

  // extra fields you may store later
  bool hasContractAward; // example rule trigger
  int ipcCount; // if > 0 => Valuation

  ProjectRow({
    required this.id,
    required this.name,
    required this.stage,
    required this.lastActive,
    required this.revision,
    required this.files,
    this.hasContractAward = false,
    this.ipcCount = 0,
  });
}
