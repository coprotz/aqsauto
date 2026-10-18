import 'package:aqs/features/admin/models/admin_models.dart';
import 'package:aqs/features/admin/models/project_client_row.dart';

class ProjectsAdminData {
  const ProjectsAdminData({
    required this.projectCount,
    required this.clientCount,
    required this.inviteCount,
    required this.workspaceMemberCount,
    required this.projects,
    required this.clients,
    required this.invites,
    required this.workspaceMembers,
  });

  final int projectCount;
  final int clientCount;
  final int inviteCount;
  final int workspaceMemberCount;

  final List<AdminProjectRow> projects;
  final List<AdminClientRow> clients;
  final List<AdminInviteRow> invites;
  final List<AdminWorkspaceMemberRow> workspaceMembers;
}
