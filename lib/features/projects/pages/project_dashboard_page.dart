import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/projects/models/aqs_project.dart';
import 'package:aqs/features/projects/pages/facilities_page.dart';
import 'package:aqs/features/projects/pages/external_quotations_page.dart';
import 'package:aqs/features/projects/services/project_service.dart';
import 'package:aqs/routes/app_routes.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProjectDashboardPage extends StatelessWidget {
  const ProjectDashboardPage({super.key, required this.projectId});

  final String projectId;

  Stream<QuerySnapshot<Map<String, dynamic>>> _facilitiesStream() {
    return FirebaseFirestore.instance
        .collection('projects')
        .doc(projectId)
        .collection('facilities')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AqsColors.canvas,
      appBar: AppBar(title: const Text('Project Workspace')),
      body: StreamBuilder<AqsProject?>(
        stream: ProjectService.instance.watchProject(projectId),
        builder: (context, projectSnapshot) {
          if (projectSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (projectSnapshot.hasError) {
            return Center(
              child: Text(
                'Could not load project:\n'
                '${projectSnapshot.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final project = projectSnapshot.data;

          if (project == null) {
            return const Center(child: Text('Project not found.'));
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _facilitiesStream(),
            builder: (context, facilitySnapshot) {
              if (facilitySnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final facilityDocs = facilitySnapshot.data?.docs ?? const [];

              final facilityCount = facilityDocs.length;

              var drawingCount = 0;
              var boqItemCount = 0;
              var measurementCount = 0;

              double progressTotal = 0;

              for (final doc in facilityDocs) {
                final data = doc.data();

                drawingCount += _readInt(data['drawingCount']);

                boqItemCount += _readInt(data['boqItemCount']);

                measurementCount += _readInt(data['measurementCount']);

                progressTotal += _readDouble(data['takeoffProgress']);
              }

              final averageProgress =
                  facilityCount == 0 ? 0.0 : progressTotal / facilityCount;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1250),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
                    children: [
                      _ProjectHeader(project: project),

                      const SizedBox(height: 22),

                      _ProjectSummary(
                        facilityCount: facilityCount,
                        drawingCount: drawingCount,
                        boqItemCount: boqItemCount,
                        measurementCount: measurementCount,
                        progress: averageProgress,
                      ),

                      const SizedBox(height: 28),

                      const Text(
                        'Project Workspace',
                        style: TextStyle(
                          color: AqsColors.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),

                      const SizedBox(height: 6),

                      const Text(
                        'Manage facilities and review the project as a whole.',
                        style: TextStyle(color: AqsColors.muted, height: 1.4),
                      ),

                      const SizedBox(height: 20),

                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns =
                              constraints.maxWidth >= 1000
                                  ? 3
                                  : constraints.maxWidth >= 650
                                  ? 2
                                  : 1;

                          const gap = 16.0;

                          final width =
                              (constraints.maxWidth - (gap * (columns - 1))) /
                              columns;

                          final cards = <Widget>[
                            _WorkspaceCard(
                              title: 'Facilities',
                              subtitle:
                                  'Manage buildings, external works, roads and other project workspaces.',
                              icon: Icons.apartment_rounded,
                              metric:
                                  '$facilityCount '
                                  '${facilityCount == 1 ? 'facility' : 'facilities'}',
                              statusLabel:
                                  facilityCount > 0
                                      ? 'Active'
                                      : 'Setup required',
                              statusType:
                                  facilityCount > 0
                                      ? _WorkspaceStatus.ready
                                      : _WorkspaceStatus.pending,
                              primaryLabel:
                                  facilityCount > 0
                                      ? 'Manage Facilities'
                                      : 'Add Facility',
                              onPressed: () {
                                Get.toNamed(
                                  AppRoutes.facilities,
                                  parameters: {
                                    'projectId': project.id,
                                    'projectName': project.name,
                                  },
                                );
                              },
                            ),

                            _WorkspaceCard(
                              title: 'Project Summary',
                              subtitle:
                                  'Review quantities, drawing totals and measurement progress across all facilities.',
                              icon: Icons.dashboard_outlined,
                              metric: '$measurementCount measurements',
                              statusLabel:
                                  facilityCount > 0 ? 'Available' : 'No data',
                              statusType:
                                  facilityCount > 0
                                      ? _WorkspaceStatus.neutral
                                      : _WorkspaceStatus.disabled,
                              primaryLabel: 'View Summary',
                              onPressed:
                                  facilityCount > 0
                                      ? () {
                                        /*
                                           * Later:
                                           *
                                           * ProjectSummaryPage(
                                           *   projectId: projectId,
                                           * )
                                           */
                                      }
                                      : null,
                            ),

                            _WorkspaceCard(
                              title: 'Consolidated BOQ',
                              subtitle:
                                  'Review BOQ quantities from all facilities in one project-level summary.',
                              icon: Icons.table_view_outlined,
                              metric: '$boqItemCount BOQ items',
                              statusLabel:
                                  boqItemCount > 0
                                      ? 'Available'
                                      : 'No BOQ data',
                              statusType:
                                  boqItemCount > 0
                                      ? _WorkspaceStatus.neutral
                                      : _WorkspaceStatus.disabled,
                              primaryLabel: 'View Project BOQ',
                              onPressed:
                                  boqItemCount > 0
                                      ? () {
                                        /*
                                           * Later:
                                           *
                                           * ProjectBoqSummaryPage(
                                           *   projectId: projectId,
                                           * )
                                           */
                                      }
                                      : null,
                            ),

                            _WorkspaceCard(
                              title: 'External Quotations',
                              subtitle:
                                  'Add specialist and contractor quotations, track QS assessment/approval, and include approved values in the project cost.',
                              icon: Icons.request_quote_outlined,
                              metric: 'Specialist works',
                              statusLabel: 'Available',
                              statusType: _WorkspaceStatus.neutral,
                              primaryLabel: 'Manage Quotations',
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ExternalQuotationsPage(
                                      projectId: project.id,
                                      projectName: project.name,
                                    ),
                                  ),
                                );
                              },
                            ),

                            _WorkspaceCard(
                              title: 'Project Reports',
                              subtitle:
                                  'Generate project-wide BOQ, take-off, variance and measurement reports.',
                              icon: Icons.description_outlined,
                              metric: '$drawingCount drawings',
                              statusLabel:
                                  measurementCount > 0
                                      ? 'Available'
                                      : 'Not ready',
                              statusType:
                                  measurementCount > 0
                                      ? _WorkspaceStatus.neutral
                                      : _WorkspaceStatus.disabled,
                              primaryLabel: 'View Reports',
                              onPressed: measurementCount > 0 ? () {} : null,
                            ),

                            _WorkspaceCard(
                              title: 'Project Team',
                              subtitle:
                                  'Manage quantity surveyors, reviewers, checkers and other project members.',
                              icon: Icons.groups_outlined,
                              metric:
                                  '${project.members.length} '
                                  '${project.members.length == 1 ? 'member' : 'members'}',
                              statusLabel: 'Project access',
                              statusType: _WorkspaceStatus.neutral,
                              primaryLabel: 'Manage Team',
                              onPressed: () {},
                            ),

                            _WorkspaceCard(
                              title: 'Project Settings',
                              subtitle:
                                  'Manage project details, measurement standards, currency and workspace configuration.',
                              icon: Icons.settings_outlined,
                              metric: project.currency,
                              statusLabel:
                                  project.isActive ? 'Active' : project.status,
                              statusType:
                                  project.isActive
                                      ? _WorkspaceStatus.ready
                                      : _WorkspaceStatus.neutral,
                              primaryLabel: 'Project Settings',
                              onPressed: () {},
                            ),
                          ];

                          return Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children:
                                cards
                                    .map(
                                      (card) =>
                                          SizedBox(width: width, child: card),
                                    )
                                    .toList(),
                          );
                        },
                      ),

                      const SizedBox(height: 28),

                      _ProjectReadinessCard(
                        facilityCount: facilityCount,
                        drawingCount: drawingCount,
                        boqItemCount: boqItemCount,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _readDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({required this.project});

  final AqsProject project;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF101828),
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;

          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.business_center_outlined,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),

                        if (project.code.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            project.code,
                            style: const TextStyle(
                              color: Color(0xFFBFD2FA),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _HeaderMeta(
                    icon: Icons.business_outlined,
                    value:
                        project.clientName.isEmpty
                            ? 'Client not specified'
                            : project.clientName,
                  ),

                  _HeaderMeta(
                    icon: Icons.location_on_outlined,
                    value:
                        project.location.isEmpty
                            ? 'Location not specified'
                            : project.location,
                  ),

                  _HeaderMeta(
                    icon: Icons.payments_outlined,
                    value: project.currency,
                  ),
                ],
              ),
            ],
          );

          if (compact) {
            return details;
          }

          return Row(
            children: [
              Expanded(child: details),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF3),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text(
                  'ACTIVE PROJECT',
                  style: TextStyle(
                    color: Color(0xFF039855),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderMeta extends StatelessWidget {
  const _HeaderMeta({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: const Color(0xFF98A2B3)),

        const SizedBox(width: 7),

        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFD0D5DD),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ProjectSummary extends StatelessWidget {
  const _ProjectSummary({
    required this.facilityCount,
    required this.drawingCount,
    required this.boqItemCount,
    required this.measurementCount,
    required this.progress,
  });

  final int facilityCount;
  final int drawingCount;
  final int boqItemCount;
  final int measurementCount;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final safeProgress = (progress / 100).clamp(0.0, 1.0).toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 780;

          final metrics = Wrap(
            spacing: 32,
            runSpacing: 18,
            children: [
              _SummaryMetric(
                icon: Icons.apartment_outlined,
                label: 'Facilities',
                value: '$facilityCount',
              ),

              _SummaryMetric(
                icon: Icons.architecture_outlined,
                label: 'Drawings',
                value: '$drawingCount',
              ),

              _SummaryMetric(
                icon: Icons.table_rows_outlined,
                label: 'BOQ Items',
                value: '$boqItemCount',
              ),

              _SummaryMetric(
                icon: Icons.calculate_outlined,
                label: 'Measurements',
                value: '$measurementCount',
              ),
            ],
          );

          final progressWidget = SizedBox(
            width: compact ? double.infinity : 270,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Overall Take-off',
                        style: TextStyle(
                          color: AqsColors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),

                    Text(
                      '${progress.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: AqsColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: safeProgress,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFF2F4F7),
                  ),
                ),
              ],
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [metrics, const SizedBox(height: 22), progressWidget],
            );
          }

          return Row(
            children: [
              Expanded(child: metrics),

              const SizedBox(width: 24),

              progressWidget,
            ],
          );
        },
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AqsColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: AqsColors.primary),
        ),

        const SizedBox(width: 10),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: AqsColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),

            Text(
              label,
              style: const TextStyle(color: AqsColors.muted, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}

enum _WorkspaceStatus { ready, pending, neutral, disabled }

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.metric,
    required this.statusLabel,
    required this.statusType,
    required this.primaryLabel,
    required this.onPressed,
  });

  final String title;
  final String subtitle;

  final IconData icon;

  final String metric;
  final String statusLabel;

  final _WorkspaceStatus statusType;

  final String primaryLabel;
  final VoidCallback? onPressed;

  Color get _statusBackground {
    switch (statusType) {
      case _WorkspaceStatus.ready:
        return const Color(0xFFECFDF3);

      case _WorkspaceStatus.pending:
        return const Color(0xFFFFFAEB);

      case _WorkspaceStatus.disabled:
        return const Color(0xFFF2F4F7);

      case _WorkspaceStatus.neutral:
        return const Color(0xFFEFF8FF);
    }
  }

  Color get _statusForeground {
    switch (statusType) {
      case _WorkspaceStatus.ready:
        return const Color(0xFF027A48);

      case _WorkspaceStatus.pending:
        return const Color(0xFFB54708);

      case _WorkspaceStatus.disabled:
        return const Color(0xFF667085);

      case _WorkspaceStatus.neutral:
        return const Color(0xFF175CD3);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 260),
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AqsColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AqsColors.primary),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _statusBackground,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _statusForeground,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Text(
            title,
            style: const TextStyle(
              color: AqsColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            metric,
            style: const TextStyle(
              color: AqsColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            subtitle,
            style: const TextStyle(
              color: AqsColors.muted,
              fontSize: 13,
              height: 1.45,
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(
                statusType == _WorkspaceStatus.disabled
                    ? Icons.lock_outline_rounded
                    : Icons.arrow_forward_rounded,
                size: 18,
              ),
              label: Text(primaryLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectReadinessCard extends StatelessWidget {
  const _ProjectReadinessCard({
    required this.facilityCount,
    required this.drawingCount,
    required this.boqItemCount,
  });

  final int facilityCount;
  final int drawingCount;
  final int boqItemCount;

  @override
  Widget build(BuildContext context) {
    final hasFacility = facilityCount > 0;

    final hasDrawings = drawingCount > 0;

    final hasBoq = boqItemCount > 0;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Project readiness',
            style: TextStyle(
              color: AqsColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 5),

          const Text(
            'Project progress is built from the facilities within this workspace.',
            style: TextStyle(color: AqsColors.muted),
          ),

          const SizedBox(height: 20),

          const _ReadinessStep(
            number: '1',
            title: 'Project created',
            subtitle: 'The main project workspace is ready.',
            completed: true,
          ),

          const _ReadinessConnector(),

          _ReadinessStep(
            number: '2',
            title: 'Add facilities',
            subtitle:
                hasFacility
                    ? '$facilityCount facility workspace(s) created.'
                    : 'Add buildings, external works or other project components.',
            completed: hasFacility,
          ),

          const _ReadinessConnector(),

          _ReadinessStep(
            number: '3',
            title: 'Prepare facilities',
            subtitle:
                hasDrawings || hasBoq
                    ? '$drawingCount drawings and $boqItemCount BOQ items currently available.'
                    : 'Upload drawings and BOQs inside each facility.',
            completed: hasDrawings && hasBoq,
          ),

          const _ReadinessConnector(),

          _ReadinessStep(
            number: '4',
            title: 'Project take-off',
            subtitle:
                hasDrawings && hasBoq
                    ? 'Facility take-off work can proceed.'
                    : 'Take-off becomes available within prepared facilities.',
            completed: false,
          ),
        ],
      ),
    );
  }
}

class _ReadinessStep extends StatelessWidget {
  const _ReadinessStep({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.completed,
  });

  final String number;
  final String title;
  final String subtitle;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                completed ? const Color(0xFFECFDF3) : const Color(0xFFF2F4F7),
            shape: BoxShape.circle,
          ),
          child:
              completed
                  ? const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: Color(0xFF039855),
                  )
                  : Text(
                    number,
                    style: const TextStyle(
                      color: AqsColors.muted,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
        ),

        const SizedBox(width: 13),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AqsColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                subtitle,
                style: const TextStyle(color: AqsColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadinessConnector extends StatelessWidget {
  const _ReadinessConnector();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 16),
      child: SizedBox(
        height: 17,
        child: VerticalDivider(
          width: 1,
          thickness: 1,
          color: Color(0xFFD0D5DD),
        ),
      ),
    );
  }
}
