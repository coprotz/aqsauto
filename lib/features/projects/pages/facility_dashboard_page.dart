import 'package:aqs/core/theme/aqs_theme.dart';
// import 'package:aqs/features/boq/pages/upload_boq_page.dart';
import 'package:aqs/features/boq2/pages/upload_boq_page.dart';
import 'package:aqs/features/projects/models/project_facility.dart';
import 'package:aqs/features/projects/services/facility_service.dart';
import 'package:aqs/routes/app_routes.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FacilityDashboardPage extends StatelessWidget {
  const FacilityDashboardPage({
    super.key,
    required this.projectId,
    required this.facilityId,
  });

  final String projectId;
  final String facilityId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AqsColors.canvas,
      appBar: AppBar(title: const Text('Facility Workspace')),
      body: StreamBuilder<ProjectFacility?>(
        stream: FacilityService.instance.watchFacility(
          projectId: projectId,
          facilityId: facilityId,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load facility:\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final facility = snapshot.data;

          if (facility == null) {
            return const Center(child: Text('Facility not found.'));
          }

          final hasDrawings = facility.drawingCount > 0;

          final hasBoq = facility.boqItemCount > 0;

          final takeoffReady = hasDrawings && hasBoq;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1250),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
                children: [
                  _FacilityHeader(facility: facility),

                  const SizedBox(height: 24),

                  _FacilitySummary(facility: facility),

                  const SizedBox(height: 26),

                  const Text(
                    'Workspace',
                    style: TextStyle(
                      color: AqsColors.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),

                  const SizedBox(height: 6),

                  const Text(
                    'Manage drawings, BOQ, measurements and take-off for this facility.',
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
                          title: 'Drawings',
                          subtitle:
                              'Upload drawing bundles and manage drawing sheets, revisions and scales.',
                          icon: Icons.architecture_outlined,
                          metric: '${facility.drawingCount} drawings',
                          statusLabel: hasDrawings ? 'Ready' : 'Not uploaded',
                          status:
                              hasDrawings
                                  ? _CardStatus.ready
                                  : _CardStatus.pending,
                          actionLabel:
                              hasDrawings ? 'View Drawings' : 'Upload Drawings',
                          onPressed: () {
                            Get.toNamed(
                              AppRoutes.facilityDrawings,
                              parameters: {
                                'projectId': projectId,
                                'facilityId': facilityId,
                                'facilityName': facility.name,
                              },
                            );
                          },
                        ),

                        _WorkspaceCard(
                          title: 'BOQ',
                          subtitle:
                              'Import or create BOQ items and map them to measurement methods.',
                          icon: Icons.table_view_outlined,
                          metric: '${facility.boqItemCount} items',
                          statusLabel: hasBoq ? 'Ready' : 'Not imported',
                          status:
                              hasBoq ? _CardStatus.ready : _CardStatus.pending,
                          actionLabel: hasBoq ? 'View BOQ' : 'Import BOQ',
                          onPressed: () {
                            Get.toNamed(
                              AppRoutes.uploadBoq,
                              parameters: {
                                'projectId': projectId,
                                'facilityId': facilityId,
                              },
                            );
                          },
                        ),

                        _WorkspaceCard(
                          title: 'Take-off',
                          subtitle:
                              takeoffReady
                                  ? 'Measure directly from drawings and automatically update linked BOQ quantities.'
                                  : 'Upload drawings and import a BOQ before starting take-off.',
                          icon: Icons.straighten_outlined,
                          metric:
                              '${facility.takeoffProgress.toStringAsFixed(0)}% complete',
                          statusLabel:
                              takeoffReady ? 'Ready' : 'Setup required',
                          status:
                              takeoffReady
                                  ? _CardStatus.ready
                                  : _CardStatus.disabled,
                          actionLabel:
                              facility.takeoffProgress > 0
                                  ? 'Continue Take-off'
                                  : 'Start Take-off',
                          onPressed:
                              takeoffReady
                                  ? () {
                                    /*
                                       * Future:
                                       *
                                       * TakeoffWorkspacePage(
                                       *   projectId:
                                       *       projectId,
                                       *   facilityId:
                                       *       facilityId,
                                       * )
                                       */
                                  }
                                  : null,
                        ),

                        _WorkspaceCard(
                          title: 'Measurements',
                          subtitle:
                              'Review quantities, deductions, measurement groups and quantity build-ups.',
                          icon: Icons.calculate_outlined,
                          metric: '${facility.measurementCount} measurements',
                          statusLabel:
                              facility.measurementCount > 0
                                  ? 'Available'
                                  : 'No measurements',
                          status:
                              facility.measurementCount > 0
                                  ? _CardStatus.neutral
                                  : _CardStatus.disabled,
                          actionLabel: 'View Measurements',
                          onPressed:
                              facility.measurementCount > 0 ? () {} : null,
                        ),

                        _WorkspaceCard(
                          title: 'Reports',
                          subtitle:
                              'Generate measurement sheets, BOQ summaries and marked-up drawing reports.',
                          icon: Icons.description_outlined,
                          metric: 'Facility reports',
                          statusLabel:
                              facility.measurementCount > 0
                                  ? 'Available'
                                  : 'Not ready',
                          status:
                              facility.measurementCount > 0
                                  ? _CardStatus.neutral
                                  : _CardStatus.disabled,
                          actionLabel: 'View Reports',
                          onPressed:
                              facility.measurementCount > 0 ? () {} : null,
                        ),

                        _WorkspaceCard(
                          title: 'Facility Settings',
                          subtitle:
                              'Edit facility information, coding, classification and workspace settings.',
                          icon: Icons.settings_outlined,
                          metric: facility.typeLabel,
                          statusLabel:
                              facility.isActive ? 'Active' : facility.status,
                          status:
                              facility.isActive
                                  ? _CardStatus.ready
                                  : _CardStatus.neutral,
                          actionLabel: 'Manage Facility',
                          onPressed: () {},
                        ),
                      ];

                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children:
                            cards
                                .map(
                                  (card) => SizedBox(width: width, child: card),
                                )
                                .toList(),
                      );
                    },
                  ),

                  const SizedBox(height: 28),

                  _TakeoffReadiness(facility: facility),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FacilityHeader extends StatelessWidget {
  const _FacilityHeader({required this.facility});

  final ProjectFacility facility;

  IconData get _icon {
    switch (facility.type) {
      case 'building':
        return Icons.apartment_rounded;

      case 'external_works':
        return Icons.landscape_outlined;

      case 'road':
        return Icons.add_road_rounded;

      case 'drainage':
        return Icons.water_outlined;

      case 'landscaping':
        return Icons.park_outlined;

      case 'utility':
        return Icons.electrical_services_outlined;

      default:
        return Icons.business_outlined;
    }
  }

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

          final details = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(_icon, color: Colors.white, size: 27),
              ),

              const SizedBox(width: 15),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      facility.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),

                    if (facility.code.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        facility.code,
                        style: const TextStyle(
                          color: Color(0xFFBFD2FA),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),

                    Text(
                      facility.typeLabel,
                      style: const TextStyle(
                        color: Color(0xFFD0D5DD),
                        fontSize: 12,
                      ),
                    ),

                    if (facility.description.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Text(
                        facility.description,
                        style: const TextStyle(
                          color: Color(0xFF98A2B3),
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
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
                  horizontal: 13,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF3),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text(
                  'FACILITY WORKSPACE',
                  style: TextStyle(
                    color: Color(0xFF027A48),
                    fontSize: 10,
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

class _FacilitySummary extends StatelessWidget {
  const _FacilitySummary({required this.facility});

  final ProjectFacility facility;

  @override
  Widget build(BuildContext context) {
    final progress =
        (facility.takeoffProgress / 100).clamp(0.0, 1.0).toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 750;

          final metrics = Wrap(
            spacing: 34,
            runSpacing: 20,
            children: [
              _SummaryMetric(
                label: 'Drawings',
                value: '${facility.drawingCount}',
                icon: Icons.architecture_outlined,
              ),

              _SummaryMetric(
                label: 'BOQ Items',
                value: '${facility.boqItemCount}',
                icon: Icons.table_rows_outlined,
              ),

              _SummaryMetric(
                label: 'Measurements',
                value: '${facility.measurementCount}',
                icon: Icons.calculate_outlined,
              ),
            ],
          );

          final progressBlock = SizedBox(
            width: compact ? double.infinity : 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Take-off progress',
                        style: TextStyle(
                          color: AqsColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),

                    Text(
                      '${facility.takeoffProgress.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: AqsColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 9),

                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: progress,
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
              children: [metrics, const SizedBox(height: 22), progressBlock],
            );
          }

          return Row(
            children: [
              Expanded(child: metrics),

              const SizedBox(width: 24),

              progressBlock,
            ],
          );
        },
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AqsColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(11),
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

enum _CardStatus { ready, pending, neutral, disabled }

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.metric,
    required this.statusLabel,
    required this.status,
    required this.actionLabel,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String metric;

  final String statusLabel;
  final _CardStatus status;

  final String actionLabel;
  final VoidCallback? onPressed;

  Color get _background {
    switch (status) {
      case _CardStatus.ready:
        return const Color(0xFFECFDF3);

      case _CardStatus.pending:
        return const Color(0xFFFFFAEB);

      case _CardStatus.neutral:
        return const Color(0xFFEFF8FF);

      case _CardStatus.disabled:
        return const Color(0xFFF2F4F7);
    }
  }

  Color get _foreground {
    switch (status) {
      case _CardStatus.ready:
        return const Color(0xFF027A48);

      case _CardStatus.pending:
        return const Color(0xFFB54708);

      case _CardStatus.neutral:
        return const Color(0xFF175CD3);

      case _CardStatus.disabled:
        return const Color(0xFF667085);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 255),
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
                      color: _background,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _foreground,
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

          const SizedBox(height: 6),

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
                status == _CardStatus.disabled
                    ? Icons.lock_outline_rounded
                    : Icons.arrow_forward_rounded,
                size: 18,
              ),
              label: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _TakeoffReadiness extends StatelessWidget {
  const _TakeoffReadiness({required this.facility});

  final ProjectFacility facility;

  @override
  Widget build(BuildContext context) {
    final drawingsReady = facility.drawingCount > 0;

    final boqReady = facility.boqItemCount > 0;

    final ready = drawingsReady && boqReady;

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
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Take-off readiness',
                      style: TextStyle(
                        color: AqsColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      ready
                          ? 'This facility is ready for digital take-off.'
                          : 'Complete the required setup before starting take-off.',
                      style: const TextStyle(color: AqsColors.muted),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color:
                      ready ? const Color(0xFFECFDF3) : const Color(0xFFFFFAEB),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  ready ? 'READY' : 'SETUP REQUIRED',
                  style: TextStyle(
                    color:
                        ready
                            ? const Color(0xFF027A48)
                            : const Color(0xFFB54708),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          _ReadinessItem(
            icon: Icons.check_circle_outline,
            title: 'Facility created',
            subtitle: facility.name,
            completed: true,
          ),

          const SizedBox(height: 14),

          _ReadinessItem(
            icon: Icons.architecture_outlined,
            title: 'Drawings uploaded',
            subtitle:
                drawingsReady
                    ? '${facility.drawingCount} drawings available.'
                    : 'Upload drawing bundles for this facility.',
            completed: drawingsReady,
          ),

          const SizedBox(height: 14),

          _ReadinessItem(
            icon: Icons.table_view_outlined,
            title: 'BOQ prepared',
            subtitle:
                boqReady
                    ? '${facility.boqItemCount} measurable BOQ items available.'
                    : 'Import or create BOQ items.',
            completed: boqReady,
          ),

          const SizedBox(height: 14),

          _ReadinessItem(
            icon: Icons.straighten_outlined,
            title: 'Digital take-off',
            subtitle:
                ready
                    ? 'Take-off can now begin.'
                    : 'Available after drawings and BOQ are ready.',
            completed: facility.takeoffProgress > 0,
            enabled: ready,
          ),
        ],
      ),
    );
  }
}

class _ReadinessItem extends StatelessWidget {
  const _ReadinessItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.completed,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  final bool completed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground =
        !enabled
            ? const Color(0xFF98A2B3)
            : completed
            ? const Color(0xFF039855)
            : AqsColors.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: foreground.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(
            completed ? Icons.check_rounded : icon,
            color: foreground,
            size: 19,
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: enabled ? AqsColors.ink : AqsColors.muted,
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
