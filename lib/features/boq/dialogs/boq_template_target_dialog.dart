import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/projects/models/aqs_project.dart';
import 'package:aqs/features/projects/services/project_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class BoqTemplateTarget {
  const BoqTemplateTarget({
    required this.projectId,
    required this.projectName,
    required this.buildingId,
    required this.buildingName,
    required this.buildingCode,
  });

  final String projectId;
  final String projectName;
  final String buildingId;
  final String buildingName;
  final String buildingCode;
}

class BoqTemplateTargetDialog extends StatefulWidget {
  const BoqTemplateTargetDialog({
    super.key,
    this.title = 'Connect BOQ template',
    this.description =
        'Select the project and building that should receive this BOQ.',
    this.confirmLabel = 'Connect',
  });

  final String title;
  final String description;
  final String confirmLabel;

  @override
  State<BoqTemplateTargetDialog> createState() =>
      _BoqTemplateTargetDialogState();
}

class _BoqTemplateTargetDialogState extends State<BoqTemplateTargetDialog> {
  late final Stream<List<AqsProject>> _projectsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _buildingsStream;
  List<AqsProject> _projects = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _buildings = const [];
  String? _projectId;
  String? _buildingId;

  @override
  void initState() {
    super.initState();
    _projectsStream = ProjectService.instance.watchMyProjects();
  }

  String _projectLabel(AqsProject project) {
    return project.code.isEmpty
        ? project.name
        : '${project.code} — ${project.name}';
  }

  String _buildingName(
    QueryDocumentSnapshot<Map<String, dynamic>> building,
  ) {
    return (building.data()['name'] ?? 'Untitled building').toString().trim();
  }

  String _buildingCode(
    QueryDocumentSnapshot<Map<String, dynamic>> building,
  ) {
    return (building.data()['code'] ?? '').toString().trim();
  }

  String _buildingLabel(
    QueryDocumentSnapshot<Map<String, dynamic>> building,
  ) {
    final name = _buildingName(building);
    final code = _buildingCode(building);
    return code.isEmpty ? name : '$code — $name';
  }

  BoqTemplateTarget? _target() {
    AqsProject? project;
    for (final item in _projects) {
      if (item.id == _projectId) project = item;
    }
    QueryDocumentSnapshot<Map<String, dynamic>>? building;
    for (final item in _buildings) {
      if (item.id == _buildingId) building = item;
    }
    if (project == null || building == null) return null;

    return BoqTemplateTarget(
      projectId: project.id,
      projectName: project.name,
      buildingId: building.id,
      buildingName: _buildingName(building),
      buildingCode: _buildingCode(building),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: StreamBuilder<List<AqsProject>>(
          stream: _projectsStream,
          builder: (context, projectSnapshot) {
            if (projectSnapshot.hasError) {
              return Text('Could not load projects: ${projectSnapshot.error}');
            }
            if (!projectSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            _projects = projectSnapshot.data!;
            final selectedProjectId =
                _projects.any((project) => project.id == _projectId)
                    ? _projectId
                    : null;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.description,
                  style: const TextStyle(color: AqsColors.muted),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  value: selectedProjectId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Project',
                    prefixIcon: Icon(Icons.folder_outlined),
                    border: OutlineInputBorder(),
                  ),
                  hint: Text(
                    _projects.isEmpty
                        ? 'No projects available'
                        : 'Select project',
                  ),
                  items:
                      _projects
                          .map(
                            (project) => DropdownMenuItem(
                              value: project.id,
                              child: Text(
                                _projectLabel(project),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                  onChanged:
                      _projects.isEmpty
                          ? null
                          : (value) {
                            setState(() {
                              _projectId = value;
                              _buildingId = null;
                              _buildings = const [];
                              _buildingsStream =
                                  value == null
                                      ? null
                                      : FirebaseFirestore.instance
                                          .collection('projects')
                                          .doc(value)
                                          .collection('buildings')
                                          .snapshots();
                            });
                          },
                ),
                const SizedBox(height: 14),
                if (selectedProjectId == null)
                  DropdownButtonFormField<String>(
                    items: const [],
                    onChanged: null,
                    decoration: const InputDecoration(
                      labelText: 'Building',
                      prefixIcon: Icon(Icons.apartment_outlined),
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Select a project first'),
                  )
                else
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _buildingsStream,
                    builder: (context, buildingSnapshot) {
                      if (buildingSnapshot.hasError) {
                        return Text(
                          'Could not load buildings: ${buildingSnapshot.error}',
                        );
                      }
                      if (!buildingSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      _buildings =
                          buildingSnapshot.data!.docs
                              .where(
                                (building) =>
                                    building.data()['isDeleted'] != true,
                              )
                              .toList()
                            ..sort(
                              (a, b) =>
                                  _buildingLabel(a).compareTo(_buildingLabel(b)),
                            );
                      final selectedBuildingId =
                          _buildings.any(
                                (building) => building.id == _buildingId,
                              )
                              ? _buildingId
                              : null;

                      return DropdownButtonFormField<String>(
                        value: selectedBuildingId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Building',
                          prefixIcon: Icon(Icons.apartment_outlined),
                          border: OutlineInputBorder(),
                        ),
                        hint: Text(
                          _buildings.isEmpty
                              ? 'No buildings in this project'
                              : 'Select building',
                        ),
                        items:
                            _buildings
                                .map(
                                  (building) => DropdownMenuItem(
                                    value: building.id,
                                    child: Text(
                                      _buildingLabel(building),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            _buildings.isEmpty
                                ? null
                                : (value) {
                                  setState(() => _buildingId = value);
                                },
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed:
              _target() == null
                  ? null
                  : () => Navigator.pop(context, _target()),
          icon: const Icon(Icons.link_rounded),
          label: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
