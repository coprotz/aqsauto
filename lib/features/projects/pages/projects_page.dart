// import 'package:aqs/app_routes.dart';
import 'package:aqs/features/projects/pages/project_dashboard_page.dart';
import 'package:aqs/routes/app_routes.dart';
import 'package:flutter/material.dart';

import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:get/get.dart';

import '../models/aqs_project.dart';
import '../services/project_service.dart';

class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key});

  Future<void> _createProject(BuildContext context) async {
    final result = await showDialog<_CreateProjectResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const _CreateProjectDialog();
      },
    );

    if (result == null) {
      return;
    }

    try {
      final projectId = await ProjectService.instance.createProject(
        name: result.name,

        code: result.code,

        clientName: result.clientName,

        location: result.location,

        description: result.description,
      );

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Project "${result.name}" created.')),
      );

      /*
       * Next step:
       *
       * Navigate directly to
       * ProjectDashboardPage.
       */

      debugPrint('Created project: $projectId');
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create project: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AqsColors.canvas,

      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AqsBrand(compact: true, markSize: 32),
            SizedBox(width: 12),
            Text('Projects Dashboard'),
          ],
        ),

        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: () => _createProject(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Project'),
            ),
          ),
        ],
      ),

      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),

          child: StreamBuilder<List<AqsProject>>(
            stream: ProjectService.instance.watchMyProjects(),

            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load projects:\n'
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final projects = snapshot.data ?? const [];

              return ListView(
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 48),

                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Project Workspaces',
                              style: TextStyle(
                                color: AqsColors.ink,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.6,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Manage drawings, BOQs, measurements and reports from one workspace.',
                              style: TextStyle(
                                color: AqsColors.muted,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Text(
                        '${projects.length} '
                        '${projects.length == 1 ? 'project' : 'projects'}',
                        style: const TextStyle(
                          color: AqsColors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  if (projects.isEmpty)
                    _EmptyProjects(onCreate: () => _createProject(context))
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const gap = 16.0;

                        final columns =
                            constraints.maxWidth >= 1000
                                ? 3
                                : constraints.maxWidth >= 650
                                ? 2
                                : 1;

                        final width =
                            (constraints.maxWidth - (gap * (columns - 1))) /
                            columns;

                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children:
                              projects.map((project) {
                                return SizedBox(
                                  width: width,
                                  child: _ProjectCard(
                                    project: project,
                                    onOpen: () {
                                      Get.toNamed(
                                        AppRoutes.projectDashboard,
                                        parameters: {'projectId': project.id},
                                      );
                                    },
                                  ),
                                );
                              }).toList(),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onOpen});

  final AqsProject project;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE4E7EC)),
          ),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AqsColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.business_center_outlined,
                      color: AqsColors.primary,
                    ),
                  ),

                  const Spacer(),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Active',
                      style: TextStyle(
                        color: Color(0xFF039855),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              Text(
                project.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AqsColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),

              if (project.code.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  project.code,
                  style: const TextStyle(
                    color: AqsColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],

              const SizedBox(height: 16),

              _ProjectMeta(
                icon: Icons.business_outlined,
                value:
                    project.clientName.isEmpty
                        ? 'No client specified'
                        : project.clientName,
              ),

              const SizedBox(height: 9),

              _ProjectMeta(
                icon: Icons.location_on_outlined,
                value:
                    project.location.isEmpty
                        ? 'No location specified'
                        : project.location,
              ),

              const SizedBox(height: 20),

              const Divider(),

              const SizedBox(height: 12),

              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Open workspace',
                      style: TextStyle(
                        color: AqsColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: AqsColors.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectMeta extends StatelessWidget {
  const _ProjectMeta({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: AqsColors.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AqsColors.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 55),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),

      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AqsColors.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.add_business_outlined,
              color: AqsColors.primary,
              size: 34,
            ),
          ),

          const SizedBox(height: 18),

          const Text(
            'Create your first project',
            style: TextStyle(
              color: AqsColors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 7),

          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 500),
            child: Text(
              'Each AQS project is a workspace for drawings, BOQ items, take-off measurements and reports.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AqsColors.muted, height: 1.45),
            ),
          ),

          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create Project'),
          ),
        ],
      ),
    );
  }
}

class _CreateProjectResult {
  const _CreateProjectResult({
    required this.name,
    required this.code,
    required this.clientName,
    required this.location,
    required this.description,
  });

  final String name;
  final String code;
  final String clientName;
  final String location;
  final String description;
}

class _CreateProjectDialog extends StatefulWidget {
  const _CreateProjectDialog();

  @override
  State<_CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<_CreateProjectDialog> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();

  final _code = TextEditingController();

  final _client = TextEditingController();

  final _location = TextEditingController();

  final _description = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _client.dispose();
    _location.dispose();
    _description.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Create Project Workspace',
                    style: TextStyle(
                      color: AqsColors.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 5),

                  const Text(
                    'Set up the basic project information. Drawings and BOQ can be added afterwards.',
                    style: TextStyle(color: AqsColors.muted, height: 1.4),
                  ),

                  const SizedBox(height: 22),

                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Project name *',
                      hintText: 'Proposed Office Building',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Enter project name';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _code,
                    decoration: const InputDecoration(
                      labelText: 'Project code',
                      hintText: 'AQS-2026-001',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _client,
                    decoration: const InputDecoration(
                      labelText: 'Client',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _location,
                    decoration: const InputDecoration(
                      labelText: 'Project location',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _description,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 22),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: const Text('Cancel'),
                      ),

                      const SizedBox(width: 10),

                      FilledButton.icon(
                        onPressed: () {
                          if (!_formKey.currentState!.validate()) {
                            return;
                          }

                          Navigator.of(context).pop(
                            _CreateProjectResult(
                              name: _name.text.trim(),

                              code: _code.text.trim(),

                              clientName: _client.text.trim(),

                              location: _location.text.trim(),

                              description: _description.text.trim(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Create Project'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
