import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/projects/models/project_facility.dart';
import 'package:aqs/features/projects/pages/facility_dashboard_page.dart';
import 'package:aqs/features/projects/services/facility_service.dart';
import 'package:aqs/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FacilitiesPage extends StatefulWidget {
  const FacilitiesPage({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  final String projectId;
  final String projectName;

  @override
  State<FacilitiesPage> createState() => _FacilitiesPageState();
}

class _FacilitiesPageState extends State<FacilitiesPage> {
  Future<void> _createFacility() async {
    final result = await showDialog<_CreateFacilityResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreateFacilityDialog(),
    );

    if (result == null) return;

    try {
      final facilityId = await FacilityService.instance.createFacility(
        projectId: widget.projectId,
        name: result.name,
        code: result.code,
        type: result.type,
        description: result.description,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.name} created successfully.')),
      );

      debugPrint('Created facility: $facilityId');
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create facility: $error')),
      );
    }
  }

  void _openFacility(ProjectFacility facility) {
    Get.toNamed(
      AppRoutes.facilityDashboard,
      parameters: {'projectId': widget.projectId, 'facilityId': facility.id},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AqsColors.canvas,
      appBar: AppBar(
        title: const Text('Facilities'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: _createFacility,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Facility'),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1250),
          child: StreamBuilder<List<ProjectFacility>>(
            stream: FacilityService.instance.watchFacilities(widget.projectId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load facilities:\n'
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final facilities = snapshot.data ?? const [];

              return ListView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
                children: [
                  _Header(
                    projectName: widget.projectName,
                    facilityCount: facilities.length,
                  ),

                  const SizedBox(height: 24),

                  if (facilities.isEmpty)
                    _EmptyFacilities(onCreate: _createFacility)
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const gap = 16.0;

                        final columns =
                            constraints.maxWidth >= 1050
                                ? 3
                                : constraints.maxWidth >= 700
                                ? 2
                                : 1;

                        final width =
                            (constraints.maxWidth - (gap * (columns - 1))) /
                            columns;

                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children:
                              facilities.map((facility) {
                                return SizedBox(
                                  width: width,
                                  child: _FacilityCard(
                                    facility: facility,
                                    onOpen: () {
                                      _openFacility(facility);
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

class _Header extends StatelessWidget {
  const _Header({required this.projectName, required this.facilityCount});

  final String projectName;
  final int facilityCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;

        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              projectName,
              style: const TextStyle(
                color: AqsColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),

            const SizedBox(height: 4),

            const Text(
              'Facilities & Workspaces',
              style: TextStyle(
                color: AqsColors.ink,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Organise each building, facility or work package as its own measurement workspace.',
              style: TextStyle(color: AqsColors.muted, height: 1.45),
            ),
          ],
        );

        final count = Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF8FF),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            '$facilityCount '
            '${facilityCount == 1 ? 'facility' : 'facilities'}',
            style: const TextStyle(
              color: Color(0xFF175CD3),
              fontWeight: FontWeight.w800,
            ),
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 16), count],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [Expanded(child: title), count],
        );
      },
    );
  }
}

class _FacilityCard extends StatelessWidget {
  const _FacilityCard({required this.facility, required this.onOpen});

  final ProjectFacility facility;
  final VoidCallback onOpen;

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

      case 'zone':
        return Icons.grid_view_outlined;

      case 'block':
        return Icons.domain_outlined;

      default:
        return Icons.business_outlined;
    }
  }

  Color get _progressColor {
    if (facility.takeoffProgress >= 100) {
      return const Color(0xFF039855);
    }

    return AqsColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        (facility.takeoffProgress / 100).clamp(0.0, 1.0).toDouble();

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
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AqsColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(_icon, color: AqsColors.primary),
                  ),

                  const Spacer(),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          facility.isActive
                              ? const Color(0xFFECFDF3)
                              : const Color(0xFFF2F4F7),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      facility.isActive
                          ? 'ACTIVE'
                          : facility.status.toUpperCase(),
                      style: TextStyle(
                        color:
                            facility.isActive
                                ? const Color(0xFF027A48)
                                : AqsColors.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 17),

              Text(
                facility.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AqsColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),

              if (facility.code.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  facility.code,
                  style: const TextStyle(
                    color: AqsColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],

              const SizedBox(height: 7),

              Text(
                facility.typeLabel,
                style: const TextStyle(color: AqsColors.muted, fontSize: 12),
              ),

              if (facility.description.isNotEmpty) ...[
                const SizedBox(height: 11),
                Text(
                  facility.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AqsColors.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],

              const SizedBox(height: 20),

              const Divider(),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _FacilityMetric(
                      label: 'Drawings',
                      value: '${facility.drawingCount}',
                    ),
                  ),

                  Expanded(
                    child: _FacilityMetric(
                      label: 'BOQ Items',
                      value: '${facility.boqItemCount}',
                    ),
                  ),

                  Expanded(
                    child: _FacilityMetric(
                      label: 'Measurements',
                      value: '${facility.measurementCount}',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Take-off progress',
                      style: TextStyle(
                        color: AqsColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),

                  Text(
                    '${facility.takeoffProgress.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: _progressColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: const Color(0xFFF2F4F7),
                  color: _progressColor,
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Open Workspace'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FacilityMetric extends StatelessWidget {
  const _FacilityMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AqsColors.ink,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(color: AqsColors.muted, fontSize: 10),
        ),
      ],
    );
  }
}

class _EmptyFacilities extends StatelessWidget {
  const _EmptyFacilities({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 54),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: AqsColors.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.apartment_rounded,
              color: AqsColors.primary,
              size: 36,
            ),
          ),

          const SizedBox(height: 18),

          const Text(
            'Add your first facility',
            style: TextStyle(
              color: AqsColors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 7),

          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 540),
            child: Text(
              'A facility can be a building, road, external works package, drainage system or another measurable part of the project.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AqsColors.muted, height: 1.45),
            ),
          ),

          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Facility'),
          ),
        ],
      ),
    );
  }
}

class _CreateFacilityResult {
  const _CreateFacilityResult({
    required this.name,
    required this.code,
    required this.type,
    required this.description,
  });

  final String name;
  final String code;
  final String type;
  final String description;
}

class _CreateFacilityDialog extends StatefulWidget {
  const _CreateFacilityDialog();

  @override
  State<_CreateFacilityDialog> createState() => _CreateFacilityDialogState();
}

class _CreateFacilityDialogState extends State<_CreateFacilityDialog> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();

  final _code = TextEditingController();

  final _description = TextEditingController();

  String _type = 'building';

  static const _types = {
    'building': 'Building',
    'external_works': 'External Works',
    'road': 'Road',
    'drainage': 'Drainage',
    'landscaping': 'Landscaping',
    'utility': 'Utility',
    'zone': 'Zone',
    'block': 'Block',
    'other': 'Other',
  };

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 570),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add Facility',
                  style: TextStyle(
                    color: AqsColors.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 5),

                const Text(
                  'Create a separate workspace for a building or another project component.',
                  style: TextStyle(color: AqsColors.muted, height: 1.4),
                ),

                const SizedBox(height: 22),

                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Facility name *',
                    hintText: 'Main Hospital Building',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Enter facility name';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 14),

                TextFormField(
                  controller: _code,
                  decoration: const InputDecoration(
                    labelText: 'Facility code',
                    hintText: 'BLDG-01',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 14),

                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(
                    labelText: 'Facility type',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      _types.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        );
                      }).toList(),
                  onChanged: (value) {
                    if (value == null) return;

                    setState(() {
                      _type = value;
                    });
                  },
                ),

                const SizedBox(height: 14),

                TextFormField(
                  controller: _description,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Five-storey main hospital block',
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
                          _CreateFacilityResult(
                            name: _name.text.trim(),
                            code: _code.text.trim(),
                            type: _type,
                            description: _description.text.trim(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Create Facility'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
