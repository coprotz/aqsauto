import 'dart:async';
import 'dart:typed_data';

import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/features/dashboards/controllers/project_buildings_controller.dart';
import 'package:aqs/features/dashboards/models/buildings_models.dart';
import 'package:aqs/features/projects/pages/external_quotations_page.dart';
import 'package:aqs/features/projects/pages/project_boq_package_page.dart';
import 'package:aqs/features/projects/services/facility_service.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';

const List<String> _sharedCostCategories = [
  'Electricity',
  'ICT',
  'Mechanical',
  'Plumbing',
  'Fire Fighting',
  'HVAC / Air Conditioning',
  'Water Supply',
  'Drainage and Sewerage',
  'Security Systems',
  'Lifts and Escalators',
  'Generators and Backup Power',
  'Solar and Renewable Energy',
  'Civil Works',
  'Roads and Paving',
  'External Works',
  'Landscaping',
  'Structural Works',
  'Architectural and Finishes',
  'Specialist Works',
  'Temporary Works',
  'Preliminaries',
  'Provisional work',
  'Prime Costs',
  'Additional work allowance',
  'Design development allowance',
  'Contingency',
];

/// --------------------- PROJECT DETAILS PAGE ---------------------
class ProjectBuildingsPage extends StatefulWidget {
  final String projectId;
  final String projectName;

  const ProjectBuildingsPage({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  @override
  State<ProjectBuildingsPage> createState() => _ProjectBuildingsPageState();
}

class _ProjectBuildingsPageState extends State<ProjectBuildingsPage> {
  final TextEditingController _search = TextEditingController();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _projectSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sitesSubscription;
  bool _multipleSites = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sites = const [];
  String? _selectedSiteId;

  late final ProjectBuildingsController controller;
  late final Stream<QuerySnapshot<Map<String, dynamic>>>
  _projectAllowancesStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>>
  _externalQuotationsStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>>
  _projectBoqPackagesStream;

  CollectionReference<Map<String, dynamic>> get _projectAllowancesRef =>
      FirebaseFirestore.instance
          .collection('projects')
          .doc(widget.projectId)
          .collection('generalAllowances');

  CollectionReference<Map<String, dynamic>> get _externalQuotationsRef =>
      FirebaseFirestore.instance
          .collection('projects')
          .doc(widget.projectId)
          .collection('externalQuotations');

  CollectionReference<Map<String, dynamic>> get _projectBoqPackagesRef =>
      FirebaseFirestore.instance
          .collection('projects')
          .doc(widget.projectId)
          .collection('projectBoqPackages');

  DocumentReference<Map<String, dynamic>> get _projectRef =>
      FirebaseFirestore.instance.collection('projects').doc(widget.projectId);

  CollectionReference<Map<String, dynamic>> get _sitesRef =>
      _projectRef.collection('sites');

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value'.replaceAll(',', '').trim()) ?? 0;
  }

  @override
  void initState() {
    super.initState();

    controller =
        Get.isRegistered<ProjectBuildingsController>()
            ? Get.find<ProjectBuildingsController>()
            : Get.put(ProjectBuildingsController(), permanent: true);

    // Keep these stream instances stable. Building-summary updates rebuild the
    // surrounding Obx frequently; recreating snapshots() here made each
    // StreamBuilder briefly return to its waiting state and flash "Loading…".
    _projectAllowancesStream =
        _projectAllowancesRef
            .orderBy('createdAt', descending: false)
            .snapshots();
    _externalQuotationsStream = _externalQuotationsRef.snapshots();
    _projectBoqPackagesStream = _projectBoqPackagesRef.snapshots();

    _refreshProject();
    _projectSubscription = _projectRef.snapshots().listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _multipleSites = snapshot.data()?['structureMode'] == 'multipleSites';
      });
    });
    _sitesSubscription = _sitesRef.orderBy('createdAt').snapshots().listen((s) {
      if (!mounted) return;
      final active =
          s.docs.where((doc) => doc.data()['isDeleted'] != true).toList();
      setState(() {
        _sites = active;
        if (_selectedSiteId == null ||
            !active.any((doc) => doc.id == _selectedSiteId)) {
          _selectedSiteId = active.isEmpty ? null : active.first.id;
        }
      });
    });
  }

  @override
  void dispose() {
    _projectSubscription?.cancel();
    _sitesSubscription?.cancel();
    _search.dispose();
    super.dispose();
  }

  String get _selectedSiteName {
    for (final site in _sites) {
      if (site.id == _selectedSiteId) {
        return '${site.data()['name'] ?? 'Site'}';
      }
    }
    return '';
  }

  Future<void> _addSite() async {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    String? error;
    final save = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Add site'),
                  content: SizedBox(
                    width: 500,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Site name',
                            hintText: 'For example, Tabora CBD Site',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: codeController,
                          decoration: const InputDecoration(
                            labelText: 'Site code (optional)',
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        if (name.isEmpty) {
                          setDialogState(
                            () => error = 'Site name is required.',
                          );
                          return;
                        }
                        final ref = _sitesRef.doc();
                        await ref.set({
                          'name': name,
                          'code': codeController.text.trim(),
                          'createdAt': FieldValue.serverTimestamp(),
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                        _selectedSiteId = ref.id;
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Create site'),
                    ),
                  ],
                ),
          ),
    );
    nameController.dispose();
    codeController.dispose();
    if (save == true && mounted) setState(() {});
  }

  Future<void> _editSite(
    QueryDocumentSnapshot<Map<String, dynamic>> site,
  ) async {
    final data = site.data();
    final nameController = TextEditingController(text: '${data['name'] ?? ''}');
    final codeController = TextEditingController(text: '${data['code'] ?? ''}');
    String? error;
    final save = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Edit site'),
                  content: SizedBox(
                    width: 500,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Site name',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: codeController,
                          decoration: const InputDecoration(
                            labelText: 'Site code',
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        if (name.isEmpty) {
                          setDialogState(
                            () => error = 'Site name is required.',
                          );
                          return;
                        }
                        await site.reference.update({
                          'name': name,
                          'code': codeController.text.trim(),
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                        final buildings =
                            await _projectRef
                                .collection('buildings')
                                .where('siteId', isEqualTo: site.id)
                                .get();
                        for (
                          var start = 0;
                          start < buildings.docs.length;
                          start += 400
                        ) {
                          final batch = FirebaseFirestore.instance.batch();
                          for (final building in buildings.docs
                              .skip(start)
                              .take(400)) {
                            batch.update(building.reference, {
                              'siteName': name,
                            });
                          }
                          await batch.commit();
                        }
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      },
                      child: const Text('Save changes'),
                    ),
                  ],
                ),
          ),
    );
    nameController.dispose();
    codeController.dispose();
    if (save == true) await controller.refreshBuildings(widget.projectId);
  }

  Future<void> _deleteSite(
    QueryDocumentSnapshot<Map<String, dynamic>> site,
  ) async {
    final buildings =
        controller
            .buildingsFor(widget.projectId)
            .where((building) => building.siteId == site.id)
            .length;
    final costs =
        await site.reference.collection('generalAllowances').limit(1).get();
    if (!mounted) return;
    if (buildings > 0 || costs.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Move or remove this site’s buildings and site costs before deleting it.',
          ),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete site?'),
            content: Text(
              'Delete ${site.data()['name'] ?? 'this site'}? This action removes it from the project.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete site'),
              ),
            ],
          ),
    );
    if (confirmed == true) {
      await site.reference.update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Retained for backward compatibility with facilities already created
  // during the initial multi-site rollout; no longer exposed in this page.
  // ignore: unused_element
  Future<void> _addFacilityToSite(
    QueryDocumentSnapshot<Map<String, dynamic>> site,
  ) async {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final descriptionController = TextEditingController();
    var type = 'building';
    String? error;
    final save = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: Text(
                    'Add facility · ${site.data()['name'] ?? 'Site'}',
                  ),
                  content: SizedBox(
                    width: 560,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'Facility name',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: codeController,
                            decoration: const InputDecoration(
                              labelText: 'Facility code',
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: type,
                            decoration: const InputDecoration(
                              labelText: 'Facility type',
                            ),
                            items:
                                const {
                                      'building': 'Building',
                                      'external_works': 'External works',
                                      'road': 'Road',
                                      'drainage': 'Drainage',
                                      'landscaping': 'Landscaping',
                                      'utility': 'Utility',
                                      'other': 'Other',
                                    }.entries
                                    .map(
                                      (entry) => DropdownMenuItem(
                                        value: entry.key,
                                        child: Text(entry.value),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (value) => type = value ?? type,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: descriptionController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Description (optional)',
                            ),
                          ),
                          if (error != null) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      onPressed: () async {
                        if (nameController.text.trim().isEmpty) {
                          setDialogState(
                            () => error = 'Facility name is required.',
                          );
                          return;
                        }
                        await FacilityService.instance.createFacility(
                          projectId: widget.projectId,
                          name: nameController.text,
                          code: codeController.text,
                          type: type,
                          description: descriptionController.text,
                          siteId: site.id,
                          siteName: '${site.data()['name'] ?? ''}',
                        );
                        await site.reference.set({
                          'facilityCount': FieldValue.increment(1),
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      },
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('Create facility'),
                    ),
                  ],
                ),
          ),
    );
    for (final controller in [
      nameController,
      codeController,
      descriptionController,
    ]) {
      controller.dispose();
    }
    if (save == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Facility added to site.')));
    }
  }

  Future<void> _configureProjectStructure() async {
    var useMultipleSites = _multipleSites;
    final save = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Project structure'),
                  content: SizedBox(
                    width: 560,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RadioListTile<bool>(
                          value: false,
                          groupValue: useMultipleSites,
                          onChanged:
                              (value) => setDialogState(
                                () => useMultipleSites = value ?? false,
                              ),
                          title: const Text('Single site'),
                          subtitle: const Text(
                            'Manage buildings directly on the project page.',
                          ),
                        ),
                        RadioListTile<bool>(
                          value: true,
                          groupValue: useMultipleSites,
                          onChanged:
                              (value) => setDialogState(
                                () => useMultipleSites = value ?? true,
                              ),
                          title: const Text('Multiple sites'),
                          subtitle: const Text(
                            'Group buildings by site while retaining project-wide costs.',
                          ),
                        ),
                        if (_multipleSites &&
                            !useMultipleSites &&
                            _sites.length > 1)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Multiple sites cannot be collapsed while more than one site exists.',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed:
                          _multipleSites &&
                                  !useMultipleSites &&
                                  _sites.length > 1
                              ? null
                              : () => Navigator.pop(dialogContext, true),
                      child: const Text('Save'),
                    ),
                  ],
                ),
          ),
    );
    if (save != true || useMultipleSites == _multipleSites) return;

    if (useMultipleSites) {
      var siteId = _sites.isEmpty ? '' : _sites.first.id;
      var siteName = _sites.isEmpty ? '' : '${_sites.first.data()['name']}';
      if (siteId.isEmpty) {
        final siteRef = _sitesRef.doc();
        siteId = siteRef.id;
        siteName = 'Main Site';
        await siteRef.set({
          'name': siteName,
          'code': 'SITE-01',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      final buildings = await _projectRef.collection('buildings').get();
      for (var start = 0; start < buildings.docs.length; start += 400) {
        final batch = FirebaseFirestore.instance.batch();
        for (final building in buildings.docs.skip(start).take(400)) {
          if ('${building.data()['siteId'] ?? ''}'.isEmpty) {
            batch.update(building.reference, {
              'siteId': siteId,
              'siteName': siteName,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
        await batch.commit();
      }
      _selectedSiteId = siteId;
    }
    await _projectRef.set({
      'structureMode': useMultipleSites ? 'multipleSites' : 'singleSite',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await controller.refreshBuildings(widget.projectId);
  }

  Future<void> _openAddBuildingDialog() async {
    if (_multipleSites && _selectedSiteId == null) {
      await _addSite();
      if (_selectedSiteId == null) return;
      if (!mounted) return;
    }
    final codeCtl = TextEditingController();
    final nameCtl = TextEditingController();
    var isSaving = false;
    String? saveError;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setDialogState) => AlertDialog(
                  title: Text(
                    _multipleSites
                        ? 'Add building to $_selectedSiteName'
                        : 'Add Building',
                  ),
                  content: SizedBox(
                    width: 520,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: codeCtl,
                          decoration: const InputDecoration(
                            labelText: 'Code',
                            hintText: 'e.g. PART B(8)',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: nameCtl,
                          decoration: const InputDecoration(
                            labelText: 'Building name',
                            hintText: 'e.g. WAITING SHED',
                          ),
                        ),
                        if (saveError != null) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              saveError!,
                              style: const TextStyle(color: Color(0xFFD92D20)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          isSaving ? null : () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          isSaving
                              ? null
                              : () async {
                                final code = codeCtl.text.trim();
                                final name = nameCtl.text.trim();
                                if (name.isEmpty) {
                                  setDialogState(() {
                                    saveError = 'Building name is required.';
                                  });
                                  return;
                                }

                                setDialogState(() {
                                  isSaving = true;
                                  saveError = null;
                                });

                                try {
                                  await controller.addBuilding(
                                    projectId: widget.projectId,
                                    code: code,
                                    name: name,
                                    siteId:
                                        _multipleSites
                                            ? _selectedSiteId ?? ''
                                            : '',
                                    siteName:
                                        _multipleSites ? _selectedSiteName : '',
                                  );

                                  if (ctx.mounted) Navigator.pop(ctx, true);
                                } catch (error) {
                                  if (!ctx.mounted) return;
                                  setDialogState(() {
                                    isSaving = false;
                                    saveError =
                                        'Could not add building: $error';
                                  });
                                }
                              },
                      icon:
                          isSaving
                              ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.add_rounded),
                      label: Text(isSaving ? 'Saving…' : 'Create'),
                    ),
                  ],
                ),
          ),
    );

    codeCtl.dispose();
    nameCtl.dispose();

    if (ok == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Building added')));
    }
  }

  Future<void> _openWorkspace(BuildingRowFs b, {required int tab}) async {
    await Get.toNamed(
      AppRoutes.projectBuildingWorkspacePath(
        projectId: widget.projectId,
        buildingId: b.id,
        projectName: widget.projectName,
        buildingName: b.name,
        buildingCode: b.code,
        tab: tab,
      ),
    );
    await controller.loadBuildingFinancialSummary(
      widget.projectId,
      b.id,
      forceRefresh: true,
    );
  }

  void _openProjects() {
    selectedNav.value = 1;
    Get.toNamed(AppRoutes.dashboard);
  }

  void _openDashboard() {
    selectedNav.value = 0;
    Get.toNamed(AppRoutes.dashboard);
  }

  Future<void> _refreshProject() async {
    await controller.refreshBuildings(widget.projectId);
    final buildings = controller.buildingsFor(widget.projectId);
    await Future.wait([
      for (final building in buildings)
        controller.loadBuildingFinancialSummary(
          widget.projectId,
          building.id,
          forceRefresh: true,
        ),
    ]);
  }

  Future<void> _showProjectAllowanceDialog({
    DocumentSnapshot<Map<String, dynamic>>? existing,
    String? siteId,
    String? siteName,
    String? initialCategory,
  }) async {
    final isSiteCost = siteId != null && siteId.isNotEmpty;
    final targetRef =
        isSiteCost
            ? _sitesRef.doc(siteId).collection('generalAllowances')
            : _projectAllowancesRef;
    final data = existing?.data() ?? const <String, dynamic>{};
    final description = TextEditingController(
      text: '${data['description'] ?? ''}',
    );
    final basis = TextEditingController(
      text: '${data['itemCode'] ?? data['basis'] ?? ''}',
    );
    final unit = TextEditingController(
      text: '${data['unit'] ?? ''}'.trim().isEmpty ? 'Item' : '${data['unit']}',
    );
    final quantity = TextEditingController(
      text: (_number(data['quantity']) == 0 ? 1 : _number(data['quantity']))
          .toStringAsFixed(2),
    );
    final rate = TextEditingController(
      text: _number(data['rate']).toStringAsFixed(2),
    );
    final notes = TextEditingController(text: '${data['notes'] ?? ''}');
    var category = '${data['category'] ?? ''}'.trim();
    if (category.isEmpty) category = initialCategory ?? 'Provisional work';
    var included = data['includedInTotal'] != false;
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              final amount = _number(quantity.text) * _number(rate.text);
              return AlertDialog(
                title: Text(
                  initialCategory != null
                      ? '${existing == null ? 'Add' : 'Edit'} $initialCategory item'
                      : existing == null
                      ? 'Add ${isSiteCost ? 'shared site cost' : 'shared project cost'}'
                      : 'Edit ${isSiteCost ? 'shared site cost' : 'shared project cost'}',
                ),
                content: SizedBox(
                  width: 680,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSiteCost
                              ? 'This cost is shared by buildings at ${siteName ?? 'this site'} and will be counted once.'
                              : 'This cost belongs to the whole project and will be counted once, outside individual buildings.',
                          style: const TextStyle(color: AqsColors.muted),
                        ),
                        const SizedBox(height: 16),
                        if (initialCategory == null) ...[
                          DropdownButtonFormField<String>(
                            initialValue: category,
                            decoration: InputDecoration(
                              labelText:
                                  isSiteCost
                                      ? 'Cost category'
                                      : 'Shared cost category',
                              border: OutlineInputBorder(),
                            ),
                            items:
                                _sharedCostCategories
                                    .map(
                                      (value) => DropdownMenuItem(
                                        value: value,
                                        child: Text(value),
                                      ),
                                    )
                                    .toList(),
                            onChanged:
                                (value) => setDialogState(
                                  () => category = value ?? category,
                                ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          controller: description,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            hintText: 'e.g. Supply and install transformer',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: basis,
                          decoration: const InputDecoration(
                            labelText: 'Item No/code',
                            hintText: 'For example, A, ii or 1.2',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: unit,
                                decoration: const InputDecoration(
                                  labelText: 'Unit',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: quantity,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Quantity',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (_) => setDialogState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: rate,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Rate (TZS)',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (_) => setDialogState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: notes,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Notes (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            isSiteCost
                                ? 'Include in site total costs'
                                : 'Include in project total',
                          ),
                          subtitle: Text(
                            isSiteCost
                                ? 'Turn off to keep this item outside the selected site total.'
                                : 'Turn off to retain the item as an excluded allowance.',
                          ),
                          value: included,
                          onChanged:
                              (value) => setDialogState(() => included = value),
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AqsColors.primary.withOpacity(.07),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Amount: TZS ${NumberFormat('#,##0.00').format(amount)}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      if (description.text.trim().isEmpty) {
                        setDialogState(
                          () => error = 'Description is required.',
                        );
                        return;
                      }
                      final payload = <String, dynamic>{
                        'category': category,
                        'description': description.text.trim(),
                        'basis': basis.text.trim(),
                        'itemCode': basis.text.trim(),
                        'unit':
                            unit.text.trim().isEmpty
                                ? 'Item'
                                : unit.text.trim(),
                        'quantity': _number(quantity.text),
                        'rate': _number(rate.text),
                        'amount': _number(quantity.text) * _number(rate.text),
                        'notes': notes.text.trim(),
                        'includedInTotal': included,
                        'source': 'projectGeneralAllowance',
                        'scope': isSiteCost ? 'site' : 'project',
                        'projectId': widget.projectId,
                        if (isSiteCost) 'siteId': siteId,
                        if (isSiteCost) 'siteName': siteName,
                        'updatedAt': FieldValue.serverTimestamp(),
                      };
                      if (existing == null) {
                        payload['createdAt'] = FieldValue.serverTimestamp();
                        await targetRef.add(payload);
                      } else {
                        await existing.reference.update(payload);
                      }
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ),
    );

    for (final item in [description, basis, unit, quantity, rate, notes]) {
      item.dispose();
    }
    if (saved == true && mounted) {
      if (isSiteCost) await _refreshSiteAllowanceTotal(siteId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${isSiteCost ? 'Shared site cost' : 'Shared project cost'} saved',
          ),
        ),
      );
    }
  }

  Future<void> _refreshSiteAllowanceTotal(String siteId) async {
    final siteRef = _sitesRef.doc(siteId);
    final allowances = await siteRef.collection('generalAllowances').get();
    final total = allowances.docs.fold<double>(0, (value, document) {
      final data = document.data();
      if (data['includedInTotal'] == false) return value;
      return value +
          (data['amount'] == null
              ? _number(data['quantity']) * _number(data['rate'])
              : _number(data['amount']));
    });
    await siteRef.set({
      'allowanceTotal': total,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String?> _createSiteCostType(
    QueryDocumentSnapshot<Map<String, dynamic>> site,
  ) async {
    var selected = _sharedCostCategories.first;
    final custom = TextEditingController();
    var useCustom = false;
    String? error;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => AlertDialog(
                  title: const Text('Create site cost type'),
                  content: SizedBox(
                    width: 520,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: useCustom ? '__custom__' : selected,
                          decoration: const InputDecoration(
                            labelText: 'Cost type',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            ..._sharedCostCategories.map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            ),
                            const DropdownMenuItem(
                              value: '__custom__',
                              child: Text('Other / custom type'),
                            ),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              useCustom = value == '__custom__';
                              if (!useCustom && value != null) selected = value;
                              error = null;
                            });
                          },
                        ),
                        if (useCustom) ...[
                          const SizedBox(height: 14),
                          TextField(
                            controller: custom,
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'Custom cost type name',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                        if (error != null) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        final name =
                            useCustom ? custom.text.trim() : selected.trim();
                        if (name.isEmpty) {
                          setDialogState(
                            () => error = 'Enter a cost type name.',
                          );
                          return;
                        }
                        Navigator.pop(dialogContext, name);
                      },
                      child: const Text('Create'),
                    ),
                  ],
                ),
          ),
    );
    custom.dispose();
    if (result == null) return null;
    final existing =
        await site.reference
            .collection('costTypes')
            .where('name', isEqualTo: result)
            .limit(1)
            .get();
    if (existing.docs.isEmpty) {
      await site.reference.collection('costTypes').add({
        'name': result,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return result;
  }

  Future<void> _importSiteCostExcel({
    required String siteId,
    required String category,
  }) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (picked == null) return;
    final bytes = picked.files.single.bytes;
    if (bytes == null) return;
    final workbook = xl.Excel.decodeBytes(Uint8List.fromList(bytes));
    final imported = <Map<String, dynamic>>[];
    String normalise(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    String cellText(xl.Data? cell) => cell?.value?.toString().trim() ?? '';

    for (final table in workbook.tables.values) {
      if (table.rows.isEmpty) continue;
      var headerIndex = -1;
      var headers = <String>[];
      for (var i = 0; i < table.rows.length && i < 40; i++) {
        final candidate =
            table.rows[i].map((c) => normalise(cellText(c))).toList();
        if (candidate.any((h) => h == 'description' || h == 'particulars') &&
            candidate.any((h) => h == 'unit' || h == 'uom')) {
          headerIndex = i;
          headers = candidate;
          break;
        }
      }
      if (headerIndex < 0) continue;
      int column(List<String> names) =>
          headers.indexWhere((header) => names.contains(header));
      final codeCol = column(const [
        'boq code',
        'item code',
        'item no',
        'item',
      ]);
      final descCol = column(const [
        'description',
        'particulars',
        'item description',
      ]);
      final unitCol = column(const ['unit', 'uom']);
      final qtyCol = column(const ['quantity', 'qty']);
      final rateCol = column(const ['rate', 'unit rate']);
      final amountCol = column(const ['amount', 'total amount', 'total']);
      if (descCol < 0) continue;
      var importOrder = 0;
      for (var i = headerIndex + 1; i < table.rows.length; i++) {
        final row = table.rows[i];
        String at(int index) =>
            index < 0 || index >= row.length ? '' : cellText(row[index]);
        final description = at(descCol);
        final unit = at(unitCol);
        final quantity = _number(at(qtyCol));
        final rate = _number(at(rateCol));
        final suppliedAmount = _number(at(amountCol));
        if (description.isEmpty) continue;
        final isHeading =
            unit.isEmpty && quantity == 0 && rate == 0 && suppliedAmount == 0;
        importOrder++;
        imported.add({
          'category': category,
          'description': description,
          'basis': at(codeCol),
          'itemCode': at(codeCol),
          'rowType': isHeading ? 'subheading' : 'item',
          'order': importOrder,
          'unit': isHeading ? '' : (unit.isEmpty ? 'Item' : unit),
          'quantity': isHeading ? 0.0 : (quantity == 0 ? 1.0 : quantity),
          'rate': rate,
          'amount':
              isHeading
                  ? 0.0
                  : suppliedAmount == 0
                  ? (quantity == 0 ? 1.0 : quantity) * rate
                  : suppliedAmount,
          'includedInTotal': !isHeading,
          'source': 'siteCostExcel',
          'scope': 'site',
          'projectId': widget.projectId,
          'siteId': siteId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (imported.isNotEmpty) break;
    }
    if (imported.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No BOQ items found. Use Description, Unit, Quantity and Rate columns.',
          ),
        ),
      );
      return;
    }
    final ref = _sitesRef.doc(siteId).collection('generalAllowances');
    var batch = FirebaseFirestore.instance.batch();
    var operations = 0;
    for (final row in imported) {
      batch.set(ref.doc(), row);
      operations++;
      if (operations == 450) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        operations = 0;
      }
    }
    if (operations > 0) await batch.commit();
    await _refreshSiteAllowanceTotal(siteId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${imported.length} $category items imported.')),
    );
  }

  Future<void> _openSiteCostTypes(
    QueryDocumentSnapshot<Map<String, dynamic>> site,
  ) async {
    final results = await Future.wait([
      site.reference.collection('generalAllowances').get(),
      site.reference.collection('costTypes').get(),
    ]);
    final costs = results[0];
    final typeDocs = results[1];
    if (!mounted) return;
    final storedCategories =
        [...costs.docs, ...typeDocs.docs]
            .map(
              (doc) =>
                  '${doc.data()['category'] ?? doc.data()['name'] ?? ''}'
                      .trim(),
            )
            .where((category) => category.isNotEmpty)
            .toSet();
    final categories = [
      ..._sharedCostCategories,
      ...storedCategories.where(
        (category) => !_sharedCostCategories.contains(category),
      ),
    ];
    final visibleCategories =
        categories.where(storedCategories.contains).toList();
    final selected = await showDialog<String>(
      context: context,
      builder:
          (dialogContext) => SimpleDialog(
            title: Text('${site.data()['name'] ?? 'Site'} · Shared costs'),
            children: [
              if (visibleCategories.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Text(
                    'No shared site cost items have been added yet.',
                    style: TextStyle(color: AqsColors.muted),
                  ),
                ),
              for (final category in visibleCategories)
                Builder(
                  builder: (context) {
                    final matches = costs.docs.where(
                      (doc) =>
                          '${doc.data()['category'] ?? ''}' == category &&
                          '${doc.data()['rowType'] ?? 'item'}' == 'item',
                    );
                    final total = matches.fold<double>(
                      0,
                      (value, doc) =>
                          value +
                          (doc.data()['includedInTotal'] == false
                              ? 0
                              : _number(doc.data()['amount'])),
                    );
                    return SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialogContext, category),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text(category),
                        subtitle: Text(
                          '${matches.length} ${matches.length == 1 ? 'item' : 'items'} · TZS ${NumberFormat('#,##0.00').format(total)}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                    );
                  },
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, '__add__'),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create cost type'),
                ),
              ),
            ],
          ),
    );
    if (selected == null || !mounted) return;
    var selectedCategory = selected;
    if (selected == '__add__') {
      final created = await _createSiteCostType(site);
      if (created == null || !mounted) return;
      selectedCategory = created;
    }
    await _openSiteCostCategory(site, selectedCategory);
  }

  Future<void> _createCostTypeForSelectedSite() async {
    final siteId = _selectedSiteId;
    if (siteId == null) return;
    final matches = _sites.where((site) => site.id == siteId);
    if (matches.isEmpty) return;
    final site = matches.first;
    final category = await _createSiteCostType(site);
    if (category == null || !mounted) return;
    await _openSiteCostCategory(site, category);
  }

  Future<void> _openSiteCostCategory(
    QueryDocumentSnapshot<Map<String, dynamic>> site,
    String category,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => _SiteCostItemsPage(
              siteName: '${site.data()['name'] ?? 'Site'}',
              category: category,
              costsRef: site.reference.collection('generalAllowances'),
              onAdd:
                  () => _showProjectAllowanceDialog(
                    siteId: site.id,
                    siteName: '${site.data()['name'] ?? ''}',
                    initialCategory: category,
                  ),
              onUpload:
                  () =>
                      _importSiteCostExcel(siteId: site.id, category: category),
              onEdit:
                  (cost) => _showProjectAllowanceDialog(
                    existing: cost,
                    siteId: site.id,
                    siteName: '${site.data()['name'] ?? ''}',
                    initialCategory: category,
                  ),
              onDelete: (cost) => _deleteSiteCost(site.id, cost),
              onDeleteAll: (items) => _deleteAllSiteCosts(site.id, items),
            ),
      ),
    );
  }

  Future<void> _deleteAllSiteCosts(
    String siteId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
  ) async {
    var batch = FirebaseFirestore.instance.batch();
    var operations = 0;
    for (final item in items) {
      batch.delete(item.reference);
      operations++;
      if (operations == 450) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        operations = 0;
      }
    }
    if (operations > 0) await batch.commit();
    await _refreshSiteAllowanceTotal(siteId);
  }

  Future<void> _deleteSiteCost(
    String siteId,
    DocumentSnapshot<Map<String, dynamic>> cost,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete site cost?'),
            content: Text(
              'Delete ${cost.data()?['description'] ?? 'this cost item'}?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    await cost.reference.delete();
    await _refreshSiteAllowanceTotal(siteId);
  }

  Future<void> _deleteProjectAllowance(
    DocumentSnapshot<Map<String, dynamic>> allowance,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete provisional work?'),
            content: const Text(
              'This removes the item from the project cost summary.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed == true) await allowance.reference.delete();
  }

  Future<void> _renameBuilding(BuildingRowFs building) async {
    final nameCtl = TextEditingController(text: building.name);
    final codeCtl = TextEditingController(text: building.code);

    final update = await showDialog<Map<String, String>?>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Edit building'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Building name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeCtl,
                    decoration: const InputDecoration(labelText: 'Code'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameCtl.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(ctx, {
                    'name': name,
                    'code': codeCtl.text.trim(),
                  });
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );

    nameCtl.dispose();
    codeCtl.dispose();

    if (update == null) return;
    await controller.updateBuilding(
      projectId: widget.projectId,
      building: building,
      name: update['name']!,
      code: update['code'] ?? '',
    );

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Building updated')));
    }
  }

  Future<void> _moveBuildingToAnotherSite(BuildingRowFs building) async {
    final destinations =
        _sites.where((site) => site.id != building.siteId).toList();
    if (destinations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add another site before moving this building.'),
        ),
      );
      return;
    }
    String destinationId = destinations.first.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Move to another site'),
                  content: SizedBox(
                    width: 520,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Move ${building.name} from ${building.siteName.isEmpty ? 'its current site' : building.siteName}.',
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: destinationId,
                          decoration: const InputDecoration(
                            labelText: 'Destination site',
                            border: OutlineInputBorder(),
                          ),
                          items:
                              destinations
                                  .map(
                                    (site) => DropdownMenuItem(
                                      value: site.id,
                                      child: Text(
                                        '${site.data()['name'] ?? 'Site'}',
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              (value) => setDialogState(
                                () => destinationId = value ?? destinationId,
                              ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'The building value will move to the destination site. The overall project value will not be duplicated.',
                          style: TextStyle(color: AqsColors.muted),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      icon: const Icon(Icons.drive_file_move_outline),
                      label: const Text('Move building'),
                    ),
                  ],
                ),
          ),
    );
    if (confirmed != true) return;
    final destination = destinations.firstWhere(
      (site) => site.id == destinationId,
    );
    await _projectRef.collection('buildings').doc(building.id).update({
      'siteId': destination.id,
      'siteName': '${destination.data()['name'] ?? ''}',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await controller.refreshBuildings(widget.projectId);
    if (!mounted) return;
    setState(() => _selectedSiteId = destination.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${building.name} moved successfully.')),
    );
  }

  Future<void> _deleteBuilding(BuildingRowFs building) async {
    var isDeleting = false;
    String? deleteError;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => AlertDialog(
                  title: const Text('Delete building?'),
                  content: SizedBox(
                    width: 480,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delete ${building.name.trim().isEmpty ? 'this building' : building.name}?',
                        ),
                        if (building.code.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Code: ${building.code.trim()}'),
                        ],
                        const SizedBox(height: 12),
                        const Text(
                          'The building will be removed from this project. Its drawings, measurements, and BOQ data will no longer be accessible.',
                        ),
                        if (deleteError != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            deleteError!,
                            style: TextStyle(
                              color: Theme.of(dialogContext).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          isDeleting
                              ? null
                              : () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            Theme.of(dialogContext).colorScheme.error,
                      ),
                      onPressed:
                          isDeleting
                              ? null
                              : () async {
                                setDialogState(() {
                                  isDeleting = true;
                                  deleteError = null;
                                });

                                try {
                                  await controller.deleteBuilding(
                                    projectId: widget.projectId,
                                    building: building,
                                  );
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                } catch (error) {
                                  if (!dialogContext.mounted) return;
                                  setDialogState(() {
                                    isDeleting = false;
                                    deleteError =
                                        'Could not delete building: $error';
                                  });
                                }
                              },
                      icon:
                          isDeleting
                              ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.delete_outline_rounded),
                      label: Text(isDeleting ? 'Deleting…' : 'Delete'),
                    ),
                  ],
                ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;

    return Scaffold(
      backgroundColor: AqsColors.canvas,
      body: Column(
        children: [
          Container(
            height: 78,
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: const BorderSide(color: AqsColors.border)),
            ),
            child: Row(
              children: [
                const AqsBrand(compact: true, markSize: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.projectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF172033),
                        ),
                      ),
                      if (!compact)
                        const Text(
                          'Project buildings and take-off workspaces',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF667085),
                          ),
                        ),
                    ],
                  ),
                ),
                if (compact)
                  IconButton(
                    tooltip: 'Return to Dashboard',
                    onPressed: _openDashboard,
                    icon: const Icon(Icons.dashboard_outlined),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _openDashboard,
                    icon: const Icon(Icons.dashboard_outlined, size: 18),
                    label: const Text('Dashboard'),
                  ),
                const SizedBox(width: 8),
                if (compact)
                  IconButton(
                    tooltip: 'Open projects',
                    onPressed: _openProjects,
                    icon: const Icon(Icons.folder_copy_outlined),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _openProjects,
                    icon: const Icon(Icons.folder_copy_outlined, size: 18),
                    label: const Text('Projects'),
                  ),
              ],
            ),
          ),

          Expanded(
            child: Obx(() {
              final loading = controller.isLoading(widget.projectId);

              final error = controller.errorFor(widget.projectId);

              final all = controller.buildingsFor(widget.projectId);

              for (final building in all) {
                if (controller.cachedFinancialSummary(
                          widget.projectId,
                          building.id,
                        ) ==
                        null &&
                    !controller.isLoadingFinancialSummary(
                      widget.projectId,
                      building.id,
                    )) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    controller.loadBuildingFinancialSummary(
                      widget.projectId,
                      building.id,
                    );
                  });
                }
              }

              final loadedFinancials = <BuildingFinancialSummary>[
                for (final building in all)
                  if (controller.cachedFinancialSummary(
                        widget.projectId,
                        building.id,
                      )
                      case final summary?)
                    summary,
              ];
              final buildingWorksTotal = loadedFinancials.fold<double>(
                0,
                (sum, item) => sum + item.totalAmount,
              );
              final siteBuildingTotals = <String, double>{};
              for (final building in all) {
                final summary = controller.cachedFinancialSummary(
                  widget.projectId,
                  building.id,
                );
                if (summary == null || building.siteId.isEmpty) continue;
                siteBuildingTotals.update(
                  building.siteId,
                  (value) => value + summary.totalAmount,
                  ifAbsent: () => summary.totalAmount,
                );
              }
              final allFinancialsLoaded = loadedFinancials.length == all.length;

              if (loading && all.isEmpty) {
                return const _ProjectLoadingState(
                  message: 'Loading buildings and take-off information',
                );
              }

              if (error.isNotEmpty && all.isEmpty) {
                return _ProjectMessageState(
                  icon: Icons.error_outline_rounded,
                  title: 'Buildings could not be loaded',
                  message: error,
                  actionLabel: 'Try again',
                  onAction: () {
                    controller.refreshBuildings(widget.projectId);
                  },
                );
              }

              final q = _search.text.trim().toLowerCase();

              final siteBuildings =
                  _multipleSites
                      ? all
                          .where(
                            (building) => building.siteId == _selectedSiteId,
                          )
                          .toList()
                      : all;

              final filtered =
                  q.isEmpty
                      ? siteBuildings
                      : siteBuildings.where((b) {
                        return b.name.toLowerCase().contains(q) ||
                            b.code.toLowerCase().contains(q);
                      }).toList();

              return LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 680;

                  final horizontalPadding = narrow ? 16.0 : 24.0;

                  var columns = 1;

                  if (constraints.maxWidth >= 1260) {
                    columns = 3;
                  } else if (constraints.maxWidth >= 780) {
                    columns = 2;
                  }

                  return RefreshIndicator(
                    onRefresh: _refreshProject,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        narrow ? 18 : 24,
                        horizontalPadding,
                        32,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1440),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ProjectSummary(
                                projectName: widget.projectName,
                                buildingCount: all.length,
                                siteCount: _sites.length,
                                multipleSites: _multipleSites,
                                onAddBuilding: _openAddBuildingDialog,
                                onAddSite: _addSite,
                                onConfigureStructure:
                                    _configureProjectStructure,
                                compact: narrow,
                              ),

                              const SizedBox(height: 16),

                              StreamBuilder<
                                QuerySnapshot<Map<String, dynamic>>
                              >(
                                stream: _projectAllowancesStream,
                                builder: (context, allowanceSnapshot) {
                                  final allowances =
                                      allowanceSnapshot.data?.docs ?? const [];
                                  return StreamBuilder<
                                    QuerySnapshot<Map<String, dynamic>>
                                  >(
                                    stream: _externalQuotationsStream,
                                    builder: (context, quotationSnapshot) {
                                      final quotations =
                                          quotationSnapshot.data?.docs ??
                                          const [];
                                      return StreamBuilder<
                                        QuerySnapshot<Map<String, dynamic>>
                                      >(
                                        stream: _projectBoqPackagesStream,
                                        builder: (context, packageSnapshot) {
                                          return _ProjectFinancialSection(
                                            projectId: widget.projectId,
                                            projectName: widget.projectName,
                                            buildingWorksTotal:
                                                buildingWorksTotal,
                                            siteCostsTotal: _sites.fold<double>(
                                              0,
                                              (total, site) =>
                                                  total +
                                                  _number(
                                                    site.data()['allowanceTotal'],
                                                  ),
                                            ),
                                            allBuildingValuesLoaded:
                                                allFinancialsLoaded,
                                            allowances: allowances,
                                            quotations: quotations,
                                            packages:
                                                packageSnapshot.data?.docs ??
                                                const [],
                                            loadingAllowances:
                                                allowanceSnapshot
                                                    .connectionState ==
                                                ConnectionState.waiting,
                                            loadingQuotations:
                                                quotationSnapshot
                                                    .connectionState ==
                                                ConnectionState.waiting,
                                            loadingPackages:
                                                packageSnapshot
                                                    .connectionState ==
                                                ConnectionState.waiting,
                                            onAdd:
                                                () =>
                                                    _showProjectAllowanceDialog(),
                                            onEdit:
                                                (item) =>
                                                    _showProjectAllowanceDialog(
                                                      existing: item,
                                                    ),
                                            onDelete: _deleteProjectAllowance,
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              ),

                              const SizedBox(height: 24),

                              if (_multipleSites) ...[
                                _SiteSelector(
                                  sites: _sites,
                                  buildings: all,
                                  siteBuildingTotals: siteBuildingTotals,
                                  selectedSiteId: _selectedSiteId,
                                  onSelected:
                                      (siteId) => setState(() {
                                        _selectedSiteId = siteId;
                                        _search.clear();
                                      }),
                                  onAddSite: _addSite,
                                  onEditSite: _editSite,
                                  onDeleteSite: _deleteSite,
                                  onOpenSiteCosts: _openSiteCostTypes,
                                  onAddSiteCost:
                                      _selectedSiteId == null
                                          ? null
                                          : _createCostTypeForSelectedSite,
                                ),
                                const SizedBox(height: 24),
                              ],

                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _multipleSites &&
                                                  _selectedSiteName.isNotEmpty
                                              ? 'Buildings · $_selectedSiteName'
                                              : 'Buildings',
                                          style: TextStyle(
                                            fontSize: 21,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF172033),
                                          ),
                                        ),
                                        SizedBox(height: 3),
                                        const Text(
                                          'Open a building workspace to manage its drawings and take-off.',
                                          style: TextStyle(
                                            color: Color(0xFF667085),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!_multipleSites ||
                                      _selectedSiteId != null) ...[
                                    const SizedBox(width: 12),
                                    FilledButton.icon(
                                      onPressed: _openAddBuildingDialog,
                                      icon: const Icon(Icons.add_rounded),
                                      label: Text(
                                        narrow ? 'Building' : 'Add Building',
                                      ),
                                    ),
                                  ],
                                ],
                              ),

                              const SizedBox(height: 14),

                              SizedBox(
                                width: narrow ? double.infinity : 420,
                                child: TextField(
                                  controller: _search,
                                  decoration: InputDecoration(
                                    hintText: 'Search by building name or code',
                                    prefixIcon: const Icon(
                                      Icons.search_rounded,
                                    ),
                                    suffixIcon:
                                        _search.text.isEmpty
                                            ? null
                                            : IconButton(
                                              tooltip: 'Clear search',
                                              onPressed: () {
                                                _search.clear();
                                                setState(() {});
                                              },
                                              icon: const Icon(
                                                Icons.close_rounded,
                                              ),
                                            ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.black.withOpacity(0.08),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.black.withOpacity(0.08),
                                      ),
                                    ),
                                  ),
                                  onChanged: (_) {
                                    setState(() {});
                                  },
                                ),
                              ),

                              const SizedBox(height: 16),

                              if (filtered.isEmpty)
                                _ProjectMessageState(
                                  icon:
                                      siteBuildings.isEmpty
                                          ? Icons.apartment_outlined
                                          : Icons.search_off_rounded,
                                  title:
                                      siteBuildings.isEmpty
                                          ? 'No buildings yet'
                                          : 'No matching buildings',
                                  message:
                                      siteBuildings.isEmpty
                                          ? (_multipleSites &&
                                                  _selectedSiteName.isNotEmpty
                                              ? 'Add the first building to $_selectedSiteName.'
                                              : 'Create the first building to start drawings, measurements, and BOQ work.')
                                          : 'Try a different building name or code.',
                                  actionLabel:
                                      siteBuildings.isEmpty &&
                                              (!_multipleSites ||
                                                  _selectedSiteId != null)
                                          ? 'Add Building'
                                          : null,
                                  onAction:
                                      siteBuildings.isEmpty &&
                                              (!_multipleSites ||
                                                  _selectedSiteId != null)
                                          ? _openAddBuildingDialog
                                          : null,
                                )
                              else
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: columns,
                                        crossAxisSpacing: 14,
                                        mainAxisSpacing: 14,
                                        mainAxisExtent: 300,
                                      ),
                                  itemCount: filtered.length,
                                  itemBuilder: (_, i) {
                                    final building = filtered[i];

                                    return _BuildingCard(
                                      // colorScheme: cs,
                                      building: building,
                                      projectId: widget.projectId,
                                      controller: controller,
                                      onOpenDrawings:
                                          () =>
                                              _openWorkspace(building, tab: 0),
                                      onEdit: () => _renameBuilding(building),
                                      onMove:
                                          _multipleSites
                                              ? () =>
                                                  _moveBuildingToAnotherSite(
                                                    building,
                                                  )
                                              : null,
                                      onDelete: () => _deleteBuilding(building),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
      floatingActionButton: null,
    );
  }
}

class _SiteSelector extends StatelessWidget {
  const _SiteSelector({
    required this.sites,
    required this.buildings,
    required this.siteBuildingTotals,
    required this.selectedSiteId,
    required this.onSelected,
    required this.onAddSite,
    required this.onEditSite,
    required this.onDeleteSite,
    required this.onOpenSiteCosts,
    required this.onAddSiteCost,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> sites;
  final List<BuildingRowFs> buildings;
  final Map<String, double> siteBuildingTotals;
  final String? selectedSiteId;
  final ValueChanged<String> onSelected;
  final VoidCallback onAddSite;
  final ValueChanged<QueryDocumentSnapshot<Map<String, dynamic>>> onEditSite;
  final ValueChanged<QueryDocumentSnapshot<Map<String, dynamic>>> onDeleteSite;
  final ValueChanged<QueryDocumentSnapshot<Map<String, dynamic>>>
  onOpenSiteCosts;
  final VoidCallback? onAddSiteCost;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    const heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sites',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            color: Color(0xFF172033),
          ),
        ),
        SizedBox(height: 3),
        Text(
          'Select a site to view and manage its buildings.',
          style: TextStyle(color: Color(0xFF667085)),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: onAddSiteCost,
          icon: const Icon(Icons.playlist_add_rounded),
          label: const Text('Create cost type'),
        ),
        OutlinedButton.icon(
          onPressed: onAddSite,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Add site'),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact) ...[
          heading,
          const SizedBox(height: 12),
          actions,
        ] else
          Row(
            children: [
              const Expanded(child: heading),
              const SizedBox(width: 16),
              actions,
            ],
          ),
        const SizedBox(height: 12),
        if (sites.isEmpty)
          _ProjectMessageState(
            icon: Icons.location_city_outlined,
            title: 'No sites yet',
            message: 'Create the first site before adding buildings.',
            actionLabel: 'Add site',
            onAction: onAddSite,
          )
        else
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: sites.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final site = sites[index];
                final data = site.data();
                final selected = site.id == selectedSiteId;
                final count =
                    buildings.where((item) => item.siteId == site.id).length;
                final sharedCosts =
                    (data['allowanceTotal'] as num?)?.toDouble() ?? 0;
                final siteTotal =
                    (siteBuildingTotals[site.id] ?? 0) + sharedCosts;
                return InkWell(
                  onTap: () => onSelected(site.id),
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 340,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFEFF4FF) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color:
                            selected
                                ? Theme.of(context).colorScheme.primary
                                : AqsColors.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_city_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${data['name'] ?? 'Untitled site'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '$count ${count == 1 ? 'building' : 'buildings'}',
                                style: const TextStyle(
                                  color: Color(0xFF667085),
                                ),
                              ),
                              Text(
                                'Site total: TZS ${NumberFormat.compact().format(siteTotal)}',
                                style: const TextStyle(
                                  color: Color(0xFF667085),
                                  fontSize: 12,
                                ),
                              ),
                              InkWell(
                                onTap: () => onOpenSiteCosts(site),
                                child: Text(
                                  'Shared site costs: TZS ${NumberFormat.compact().format(sharedCosts)}',
                                  style: const TextStyle(
                                    color: AqsColors.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                              if ('${data['code'] ?? ''}'.isNotEmpty)
                                Text(
                                  'Code: ${data['code']}',
                                  style: const TextStyle(
                                    color: Color(0xFF667085),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (selected)
                          Icon(
                            Icons.check_circle_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        PopupMenuButton<String>(
                          tooltip: 'Site actions',
                          onSelected: (action) {
                            switch (action) {
                              case 'edit':
                                onEditSite(site);
                                return;
                              case 'delete':
                                onDeleteSite(site);
                                return;
                            }
                          },
                          itemBuilder:
                              (context) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    leading: Icon(Icons.edit_outlined),
                                    title: Text('Edit site'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                PopupMenuDivider(),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.red,
                                    ),
                                    title: Text(
                                      'Delete site',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                          icon: const Icon(Icons.more_vert_rounded),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SiteCostItemsPage extends StatelessWidget {
  const _SiteCostItemsPage({
    required this.siteName,
    required this.category,
    required this.costsRef,
    required this.onAdd,
    required this.onUpload,
    required this.onEdit,
    required this.onDelete,
    required this.onDeleteAll,
  });

  final String siteName;
  final String category;
  final CollectionReference<Map<String, dynamic>> costsRef;
  final Future<void> Function() onAdd;
  final Future<void> Function() onUpload;
  final Future<void> Function(DocumentSnapshot<Map<String, dynamic>>) onEdit;
  final Future<void> Function(DocumentSnapshot<Map<String, dynamic>>) onDelete;
  final Future<void> Function(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
  )
  onDeleteAll;

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value'.replaceAll(',', '').trim()) ?? 0;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _categoryItems(
    QuerySnapshot<Map<String, dynamic>>? snapshot,
  ) {
    String codeOf(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
        '${doc.data()['itemCode'] ?? doc.data()['basis'] ?? ''}'.trim();
    int compareCodes(String left, String right) {
      if (left.isEmpty && right.isNotEmpty) return 1;
      if (right.isEmpty && left.isNotEmpty) return -1;
      final leftTokens =
          RegExp(r'\d+|[A-Za-z]+')
              .allMatches(left)
              .map((match) => match.group(0)!.toLowerCase())
              .toList();
      final rightTokens =
          RegExp(r'\d+|[A-Za-z]+')
              .allMatches(right)
              .map((match) => match.group(0)!.toLowerCase())
              .toList();
      final count =
          leftTokens.length < rightTokens.length
              ? leftTokens.length
              : rightTokens.length;
      for (var index = 0; index < count; index++) {
        final leftNumber = int.tryParse(leftTokens[index]);
        final rightNumber = int.tryParse(rightTokens[index]);
        final comparison =
            leftNumber != null && rightNumber != null
                ? leftNumber.compareTo(rightNumber)
                : leftNumber != null
                ? -1
                : rightNumber != null
                ? 1
                : leftTokens[index].compareTo(rightTokens[index]);
        if (comparison != 0) return comparison;
      }
      return leftTokens.length.compareTo(rightTokens.length);
    }

    final items = [...?snapshot?.docs]
      ..removeWhere((doc) => '${doc.data()['category'] ?? ''}' != category);
    final hasStructuredRows = items.any(
      (doc) => '${doc.data()['rowType'] ?? ''}' == 'subheading',
    );
    items.sort((a, b) {
      if (hasStructuredRows) {
        final leftOrder = _number(a.data()['order']);
        final rightOrder = _number(b.data()['order']);
        final byOrder = leftOrder.compareTo(rightOrder);
        if (byOrder != 0) return byOrder;
      }
      final byCode = compareCodes(codeOf(a), codeOf(b));
      if (byCode != 0) return byCode;
      final left = a.data()['createdAt'] as Timestamp?;
      final right = b.data()['createdAt'] as Timestamp?;
      return (left?.millisecondsSinceEpoch ?? 0).compareTo(
        right?.millisecondsSinceEpoch ?? 0,
      );
    });
    return items;
  }

  Future<void> _confirmDeleteAll(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
  ) async {
    if (items.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text('Delete all $category items?'),
            content: Text(
              'This will permanently delete all ${items.length} ${items.length == 1 ? 'item' : 'items'} from $category. The shared site cost total will be recalculated. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Delete all items'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    await onDeleteAll(items);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('All $category items were deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    return Scaffold(
      backgroundColor: AqsColors.canvas,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(category),
            Text(
              siteName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: costsRef.snapshots(),
            builder: (context, snapshot) {
              final items = _categoryItems(snapshot.data);
              if (items.isEmpty) return const SizedBox.shrink();
              return IconButton(
                onPressed: () => _confirmDeleteAll(context, items),
                tooltip: 'Delete all items',
                color: Colors.red,
                icon: const Icon(Icons.delete_sweep_outlined),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add item'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Upload Excel BOQ'),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: costsRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load site costs: ${snapshot.error}'),
            );
          }
          final items = _categoryItems(snapshot.data);
          final boqItems =
              items
                  .where(
                    (item) => '${item.data()['rowType'] ?? 'item'}' == 'item',
                  )
                  .toList();
          final includedTotal = boqItems.fold<double>(
            0,
            (value, item) =>
                value +
                (item.data()['includedInTotal'] == false
                    ? 0
                    : _number(item.data()['amount'])),
          );
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  _SiteCostMetricCard(
                    width: 350,
                    icon: Icons.list_alt_rounded,
                    label: 'BOQ items',
                    value: '${boqItems.length}',
                  ),
                  _SiteCostMetricCard(
                    width: 360,
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Package value',
                    value: 'TZS ${money.format(includedTotal)}',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (items.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        const Icon(Icons.receipt_long_outlined, size: 38),
                        const SizedBox(height: 10),
                        Text('No $category items at this site.'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: onAdd,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add first item'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: onUpload,
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Upload Excel BOQ'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 28,
                      horizontalMargin: 28,
                      headingRowHeight: 64,
                      dataRowMinHeight: 52,
                      dataRowMaxHeight: double.infinity,
                      dividerThickness: 0.7,
                      headingRowColor: WidgetStatePropertyAll(AqsColors.canvas),
                      headingTextStyle: const TextStyle(
                        color: AqsColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                      dataTextStyle: const TextStyle(
                        color: AqsColors.ink,
                        fontSize: 14,
                        height: 1.35,
                      ),
                      columns: const [
                        DataColumn(label: Text('BOQ code')),
                        DataColumn(label: Text('Description')),
                        DataColumn(label: Text('Unit')),
                        DataColumn(label: Text('Quantity'), numeric: true),
                        DataColumn(label: Text('Rate'), numeric: true),
                        DataColumn(label: Text('Amount'), numeric: true),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows:
                          items.map((item) {
                            final data = item.data();
                            final isHeading =
                                '${data['rowType'] ?? 'item'}' == 'subheading';
                            final headingCode =
                                '${data['itemCode'] ?? data['basis'] ?? ''}'
                                    .trim();
                            final isMainHeading =
                                isHeading && headingCode.isEmpty;
                            final isMinorHeading =
                                isHeading &&
                                RegExp(
                                  r'^(?:[ivxlcdm]+|[a-z])$',
                                  caseSensitive: false,
                                ).hasMatch(headingCode);
                            final headingColor =
                                isMainHeading
                                    ? const Color(0xFFF8FAFC)
                                    : isMinorHeading
                                    ? const Color(0xFFF8FAFC)
                                    : const Color(0xFFEEF4FF);
                            return DataRow(
                              color:
                                  isHeading
                                      ? WidgetStatePropertyAll(headingColor)
                                      : null,
                              cells: [
                                DataCell(
                                  SizedBox(
                                    width: 120,
                                    child: Text(
                                      '${data['itemCode'] ?? data['basis'] ?? ''}',
                                      style:
                                          isHeading
                                              ? const TextStyle(
                                                color: AqsColors.primary,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 14,
                                              )
                                              : null,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: SizedBox(
                                      width: 650,
                                      child: Text(
                                        '${data['description'] ?? ''}',
                                        softWrap: true,
                                        style:
                                            isHeading
                                                ? const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 14,
                                                  height: 1.4,
                                                )
                                                : null,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    isHeading ? '' : '${data['unit'] ?? ''}',
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    isHeading ? '' : '${data['quantity'] ?? 0}',
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    isHeading
                                        ? ''
                                        : money.format(_number(data['rate'])),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    isHeading
                                        ? ''
                                        : money.format(_number(data['amount'])),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!isHeading)
                                        IconButton(
                                          tooltip: 'Edit cost',
                                          onPressed: () => onEdit(item),
                                          icon: const Icon(Icons.edit_outlined),
                                        ),
                                      IconButton(
                                        tooltip: 'Delete cost',
                                        onPressed: () => onDelete(item),
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
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

class _SiteCostMetricCard extends StatelessWidget {
  const _SiteCostMetricCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Icon(icon, size: 30),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: AqsColors.muted)),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectSummary extends StatelessWidget {
  final String projectName;
  final int buildingCount;
  final int siteCount;
  final bool multipleSites;
  final VoidCallback onAddBuilding;
  final VoidCallback onAddSite;
  final VoidCallback onConfigureStructure;
  final bool compact;

  const _ProjectSummary({
    required this.projectName,
    required this.buildingCount,
    required this.siteCount,
    required this.multipleSites,
    required this.onAddBuilding,
    required this.onAddSite,
    required this.onConfigureStructure,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final details = Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.domain_outlined, color: cs.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                projectName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF172033),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                multipleSites
                    ? '$siteCount ${siteCount == 1 ? 'site' : 'sites'} · $buildingCount ${buildingCount == 1 ? 'building' : 'buildings'}'
                    : '$buildingCount ${buildingCount == 1 ? 'building' : 'buildings'} in this project',
                style: const TextStyle(color: Color(0xFF667085)),
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AqsColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child:
          compact
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  details,
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onConfigureStructure,
                        icon: const Icon(Icons.account_tree_outlined),
                        label: const Text('Project structure'),
                      ),
                      FilledButton.icon(
                        onPressed: multipleSites ? onAddSite : onAddBuilding,
                        icon: const Icon(Icons.add_rounded),
                        label: Text(
                          multipleSites ? 'Add Site' : 'Add Building',
                        ),
                      ),
                    ],
                  ),
                ],
              )
              : Row(
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onConfigureStructure,
                        icon: const Icon(Icons.account_tree_outlined),
                        label: const Text('Project structure'),
                      ),
                      FilledButton.icon(
                        onPressed: multipleSites ? onAddSite : onAddBuilding,
                        icon: const Icon(Icons.add_rounded),
                        label: Text(
                          multipleSites ? 'Add Site' : 'Add Building',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
    );
  }
}

class _ProjectFinancialSection extends StatefulWidget {
  const _ProjectFinancialSection({
    required this.projectId,
    required this.projectName,
    required this.buildingWorksTotal,
    required this.siteCostsTotal,
    required this.allBuildingValuesLoaded,
    required this.allowances,
    required this.quotations,
    required this.packages,
    required this.loadingAllowances,
    required this.loadingQuotations,
    required this.loadingPackages,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final String projectId;
  final String projectName;
  final double buildingWorksTotal;
  final double siteCostsTotal;
  final bool allBuildingValuesLoaded;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> allowances;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> quotations;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> packages;
  final bool loadingAllowances;
  final bool loadingQuotations;
  final bool loadingPackages;
  final VoidCallback onAdd;
  final ValueChanged<DocumentSnapshot<Map<String, dynamic>>> onEdit;
  final ValueChanged<DocumentSnapshot<Map<String, dynamic>>> onDelete;

  @override
  State<_ProjectFinancialSection> createState() =>
      _ProjectFinancialSectionState();
}

class _ProjectFinancialSectionState extends State<_ProjectFinancialSection> {
  bool _showSharedCostDetails = false;

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value'.replaceAll(',', '').trim()) ?? 0;
  }

  Future<void> _createSharedProjectCost() async {
    final name = TextEditingController();
    var iconKey = 'receipt';
    String? error;
    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => AlertDialog(
                  title: const Text('Create shared project cost'),
                  content: SizedBox(
                    width: 560,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: name,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Cost name',
                            hintText: 'For example, Mechanical Services',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Choose an icon',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final entry in projectCostPackageIcons.entries)
                              ChoiceChip(
                                selected: iconKey == entry.key,
                                showCheckmark: false,
                                avatar: Icon(entry.value, size: 20),
                                label: Text(
                                  entry.key[0].toUpperCase() +
                                      entry.key.substring(1),
                                ),
                                onSelected:
                                    (_) => setDialogState(
                                      () => iconKey = entry.key,
                                    ),
                              ),
                          ],
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        final title = name.text.trim();
                        if (title.isEmpty) {
                          setDialogState(
                            () => error = 'Enter a shared-cost name.',
                          );
                          return;
                        }
                        Navigator.pop(dialogContext, {
                          'title': title,
                          'iconKey': iconKey,
                        });
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Create'),
                    ),
                  ],
                ),
          ),
    );
    name.dispose();
    if (result == null || !mounted) return;
    final title = result['title']!;
    final baseKey = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final key =
        '${baseKey.isEmpty ? 'shared_cost' : baseKey}_${DateTime.now().millisecondsSinceEpoch}';
    final definition = ProjectBoqPackageDefinition(
      key,
      title,
      projectCostPackageIcon(result['iconKey']!),
      iconKey: result['iconKey']!,
    );
    await FirebaseFirestore.instance
        .collection('projects')
        .doc(widget.projectId)
        .collection('projectBoqPackages')
        .doc(key)
        .set({
          'key': key,
          'title': title,
          'iconKey': result['iconKey'],
          'itemCount': 0,
          'rowCount': 0,
          'totalAmount': 0.0,
          'includedInProjectTotal': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
    if (!mounted) return;
    _openProjectBoqPackage(context, definition);
  }

  @override
  Widget build(BuildContext context) {
    final buildingWorksTotal = widget.buildingWorksTotal;
    final siteCostsTotal = widget.siteCostsTotal;
    final allBuildingValuesLoaded = widget.allBuildingValuesLoaded;
    final allowances = widget.allowances;
    final quotations = widget.quotations;
    final packages = widget.packages;
    final loadingAllowances = widget.loadingAllowances;
    final loadingQuotations = widget.loadingQuotations;
    final loadingPackages = widget.loadingPackages;
    final onEdit = widget.onEdit;
    final onDelete = widget.onDelete;
    final compact = MediaQuery.sizeOf(context).width < 700;
    final money = NumberFormat('#,##0.00');
    final activePackageDefinitions =
        packages.where((doc) => _number(doc.data()['itemCount']) > 0).map((
            doc,
          ) {
            final known =
                projectBoqPackageDefinitions
                    .where((definition) => definition.key == doc.id)
                    .firstOrNull;
            if (known != null) return known;
            final data = doc.data();
            final key = '${data['key'] ?? doc.id}'.trim();
            final title = '${data['title'] ?? 'Shared Cost'}'.trim();
            final iconKey = '${data['iconKey'] ?? 'receipt'}'.trim();
            return ProjectBoqPackageDefinition(
              key,
              title.isEmpty ? 'Shared Cost' : title,
              projectCostPackageIcon(iconKey),
              iconKey: iconKey,
            );
          }).toList()
          ..sort((a, b) => a.title.compareTo(b.title));
    final includedTotal = allowances.fold<double>(0, (sum, item) {
      final data = item.data();
      if (data['includedInTotal'] == false) return sum;
      final amount =
          data['amount'] == null
              ? _number(data['quantity']) * _number(data['rate'])
              : _number(data['amount']);
      return sum + amount;
    });
    final includedQuotationTotal = quotations.fold<double>(0, (sum, item) {
      final data = item.data();
      if (data['includedInProjectTotal'] != true) return sum;
      final approved = _number(data['approvedAmount']);
      final assessed = _number(data['assessedAmount']);
      final quoted = _number(data['quotedAmount']);
      final effective = _number(data['effectiveAmount']);
      final amount =
          effective > 0
              ? effective
              : (approved > 0 ? approved : (assessed > 0 ? assessed : quoted));
      return sum + amount;
    });
    final includedPackageTotal = packages.fold<double>(0, (sum, item) {
      final data = item.data();
      if (data['includedInProjectTotal'] == false) return sum;
      return sum + _number(data['totalAmount']);
    });
    final sitesCost = buildingWorksTotal + siteCostsTotal;
    final sharedProjectCosts =
        includedTotal + includedQuotationTotal + includedPackageTotal;
    final total = sitesCost + sharedProjectCosts;
    final totalsReady =
        allBuildingValuesLoaded &&
        !loadingAllowances &&
        !loadingQuotations &&
        !loadingPackages;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact)
            Column(
              children: [
                _CostTile(
                  fullWidth: true,
                  icon: Icons.location_city_outlined,
                  label: 'Sites cost',
                  value:
                      allBuildingValuesLoaded
                          ? 'TZS ${money.format(sitesCost)}'
                          : 'Calculating…',
                ),
                const SizedBox(height: 10),
                _CostTile(
                  fullWidth: true,
                  icon: Icons.hub_outlined,
                  label: 'Shared Costs',
                  value:
                      loadingAllowances || loadingQuotations || loadingPackages
                          ? 'Loading…'
                          : 'TZS ${money.format(sharedProjectCosts)}',
                  onTap:
                      () => setState(
                        () => _showSharedCostDetails = !_showSharedCostDetails,
                      ),
                  expanded: _showSharedCostDetails,
                ),
                const SizedBox(height: 10),
                _CostTile(
                  fullWidth: true,
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Total project cost',
                  value:
                      totalsReady
                          ? 'TZS ${money.format(total)}'
                          : 'Calculating…',
                  highlighted: true,
                ),
              ],
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _CostTile(
                  icon: Icons.location_city_outlined,
                  label: 'Sites cost',
                  value:
                      allBuildingValuesLoaded
                          ? 'TZS ${money.format(sitesCost)}'
                          : 'Calculating…',
                ),
                _CostTile(
                  icon: Icons.hub_outlined,
                  label: 'Shared Costs',
                  value:
                      loadingAllowances || loadingQuotations || loadingPackages
                          ? 'Loading…'
                          : 'TZS ${money.format(sharedProjectCosts)}',
                  onTap:
                      () => setState(
                        () => _showSharedCostDetails = !_showSharedCostDetails,
                      ),
                  expanded: _showSharedCostDetails,
                ),
                _CostTile(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Total project cost',
                  value:
                      totalsReady
                          ? 'TZS ${money.format(total)}'
                          : 'Calculating…',
                  highlighted: true,
                ),
              ],
            ),
          if (_showSharedCostDetails) ...[
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Shared Costs',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _createSharedProjectCost,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create shared cost'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Upload full specialist and cost-plan BOQs. Open a package to review its descriptions, units, quantities and rates.',
              style: TextStyle(color: AqsColors.muted),
            ),
            const SizedBox(height: 12),
            if (loadingPackages)
              const LinearProgressIndicator()
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth =
                      constraints.maxWidth < 620
                          ? constraints.maxWidth
                          : constraints.maxWidth < 980
                          ? (constraints.maxWidth - 12) / 2
                          : (constraints.maxWidth - 36) / 4;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final definition in activePackageDefinitions)
                        _ProjectBoqPackageCard(
                          width: cardWidth,
                          definition: definition,
                          data:
                              packages
                                  .where((doc) => doc.id == definition.key)
                                  .firstOrNull
                                  ?.data(),
                          onTap:
                              () => _openProjectBoqPackage(context, definition),
                        ),
                      if (activePackageDefinitions.isEmpty)
                        SizedBox(
                          width: constraints.maxWidth,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No shared-cost packages contain items yet.',
                              style: TextStyle(color: AqsColors.muted),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            if (allowances.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Project provisional works',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              for (final allowance in allowances)
                _ProjectAllowanceRow(
                  allowance: allowance,
                  onEdit: () => onEdit(allowance),
                  onDelete: () => onDelete(allowance),
                ),
            ],
            if (quotations.isNotEmpty) ...[
              const SizedBox(height: 24),
              if (allowances.isNotEmpty) const Divider(height: 1),
              if (allowances.isNotEmpty) const SizedBox(height: 20),
              const Text(
                'External quotations',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              for (final quotation in quotations.take(4))
                _ExternalQuotationSummaryRow(quotation: quotation),
              if (quotations.length > 4) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _openExternalQuotations(context),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text('View all ${quotations.length} quotations'),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  void _openExternalQuotations(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ExternalQuotationsPage(
              projectId: widget.projectId,
              projectName: widget.projectName,
            ),
      ),
    );
  }

  void _openProjectBoqPackage(
    BuildContext context,
    ProjectBoqPackageDefinition definition,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ProjectBoqPackagePage(
              projectId: widget.projectId,
              projectName: widget.projectName,
              definition: definition,
            ),
      ),
    );
  }
}

class _ProjectBoqPackageCard extends StatelessWidget {
  const _ProjectBoqPackageCard({
    required this.width,
    required this.definition,
    required this.data,
    required this.onTap,
  });

  final double width;
  final ProjectBoqPackageDefinition definition;
  final Map<String, dynamic>? data;
  final VoidCallback onTap;

  double _number(dynamic value) =>
      value is num
          ? value.toDouble()
          : double.tryParse('${value ?? ''}'.replaceAll(',', '')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final itemCount = (data?['itemCount'] as num?)?.toInt() ?? 0;
    final total = _number(data?['totalAmount']);
    return SizedBox(
      width: width,
      child: Material(
        color: AqsColors.canvas,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AqsColors.border),
            ),
            child: Row(
              children: [
                CircleAvatar(child: Icon(definition.icon)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        definition.title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        itemCount == 0
                            ? 'Upload Excel BOQ'
                            : '$itemCount items · TZS ${NumberFormat('#,##0.00').format(total)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AqsColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExternalQuotationSummaryRow extends StatelessWidget {
  const _ExternalQuotationSummaryRow({required this.quotation});

  final QueryDocumentSnapshot<Map<String, dynamic>> quotation;

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value'.replaceAll(',', '').trim()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final data = quotation.data();
    final included = data['includedInProjectTotal'] == true;
    final approved = _number(data['approvedAmount']);
    final assessed = _number(data['assessedAmount']);
    final quoted = _number(data['quotedAmount']);
    final effective = _number(data['effectiveAmount']);
    final amount =
        effective > 0
            ? effective
            : (approved > 0 ? approved : (assessed > 0 ? assessed : quoted));
    final money = NumberFormat('#,##0.00');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AqsColors.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.request_quote_outlined,
            color:
                included
                    ? Theme.of(context).colorScheme.primary
                    : AqsColors.muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${data['contractor'] ?? 'External quotation'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${data['discipline'] ?? ''} · ${data['status'] ?? 'Draft'} · ${included ? 'Included' : 'Excluded'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AqsColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'TZS ${money.format(amount)}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _CostTile extends StatelessWidget {
  const _CostTile({
    required this.icon,
    required this.label,
    required this.value,
    this.highlighted = false,
    this.fullWidth = false,
    this.onTap,
    this.expanded = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlighted;
  final bool fullWidth;
  final VoidCallback? onTap;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: fullWidth ? double.infinity : 310,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: highlighted ? AqsColors.primary : AqsColors.canvas,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                expanded
                    ? AqsColors.primary
                    : highlighted
                    ? AqsColors.primary
                    : AqsColors.border,
            width: expanded ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: highlighted ? Colors.white : AqsColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: highlighted ? Colors.white70 : AqsColors.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          highlighted ? Colors.white : const Color(0xFF172033),
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      expanded ? 'Hide details' : 'Show details',
                      style: TextStyle(
                        color: highlighted ? Colors.white70 : AqsColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: highlighted ? Colors.white : AqsColors.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class _ProjectAllowanceRow extends StatelessWidget {
  const _ProjectAllowanceRow({
    required this.allowance,
    required this.onEdit,
    required this.onDelete,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> allowance;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value'.replaceAll(',', '').trim()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final data = allowance.data();
    final included = data['includedInTotal'] != false;
    final amount =
        data['amount'] == null
            ? _number(data['quantity']) * _number(data['rate'])
            : _number(data['amount']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AqsColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child:
          compact
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        included
                            ? Icons.check_circle_rounded
                            : Icons.remove_circle_outline,
                        color:
                            included
                                ? const Color(0xFF039855)
                                : AqsColors.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${data['description'] ?? 'Untitled provisional work'}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${data['category'] ?? 'Provisional work'} · ${included ? 'Included' : 'Excluded'}',
                    style: const TextStyle(
                      color: AqsColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'TZS ${NumberFormat('#,##0.00').format(amount)}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: onDelete,
                        color: Colors.red,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ],
              )
              : Row(
                children: [
                  Icon(
                    included
                        ? Icons.check_circle_rounded
                        : Icons.remove_circle_outline,
                    color: included ? const Color(0xFF039855) : AqsColors.muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${data['description'] ?? 'Untitled provisional work'}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${data['category'] ?? 'Provisional work'} · ${included ? 'Included' : 'Excluded'}',
                          style: const TextStyle(
                            color: AqsColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'TZS ${NumberFormat('#,##0.00').format(amount)}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  IconButton(
                    tooltip: 'Edit',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: onDelete,
                    color: Colors.red,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
    );
  }
}

class _ProjectMessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ProjectMessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: const Color(0xFF98A2B3)),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF344054),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF667085), height: 1.45),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectLoadingState extends StatelessWidget {
  final String message;

  const _ProjectLoadingState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 42,
            height: 42,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// --------------------- BUILDING CARD ---------------------
class _BuildingCard extends StatelessWidget {
  final BuildingRowFs building;
  final String projectId;
  final ProjectBuildingsController controller;

  final VoidCallback onOpenDrawings;
  final VoidCallback onEdit;
  final VoidCallback? onMove;
  final VoidCallback onDelete;

  const _BuildingCard({
    // required this.colorScheme,
    required this.building,
    // required this.countsFuture,
    required this.onOpenDrawings,
    required this.onEdit,
    required this.onMove,
    required this.onDelete,
    required this.projectId,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final created = building.createdAt?.toDate();
    final createdTxt =
        created == null ? '-' : DateFormat('dd MMM yyyy').format(created);

    final codeTxt = building.code.trim().isEmpty ? '—' : building.code.trim();
    final nameTxt =
        building.name.trim().isEmpty ? '(No name)' : building.name.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // title row
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AqsColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.apartment_rounded, color: AqsColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  nameTxt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Building actions',
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'move') onMove?.call();
                  if (value == 'delete') onDelete();
                },
                itemBuilder:
                    (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Edit building'),
                          ],
                        ),
                      ),
                      if (onMove != null)
                        const PopupMenuItem(
                          value: 'move',
                          child: Row(
                            children: [
                              Icon(Icons.drive_file_move_outline, size: 18),
                              SizedBox(width: 10),
                              Text('Move to another site'),
                            ],
                          ),
                        ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: Colors.red,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Delete building',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Text(
            'Code: $codeTxt',
            style: TextStyle(
              color: Colors.black.withOpacity(0.65),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Created: $createdTxt',
            style: TextStyle(
              color: Colors.black.withOpacity(0.55),
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 14),
          Obx(() {
            final summary = controller.cachedFinancialSummary(
              projectId,
              building.id,
            );
            final loading = controller.isLoadingFinancialSummary(
              projectId,
              building.id,
            );
            if (summary == null) {
              return Container(
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AqsColors.canvas,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (loading)
                      const SizedBox.square(
                        dimension: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    const SizedBox(width: 8),
                    const Text(
                      'Calculating take-off value…',
                      style: TextStyle(color: AqsColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              );
            }

            final coverage = summary.coverage.clamp(0.0, 1.0).toDouble();
            return Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AqsColors.primary.withOpacity(.055),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AqsColors.primary.withOpacity(.14)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        'Take-off ${(coverage * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: AqsColors.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${summary.measuredBoqItems}/${summary.totalBoqItems} items',
                        style: const TextStyle(
                          color: AqsColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: coverage,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(99),
                    backgroundColor: AqsColors.primary.withOpacity(.12),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      const Text(
                        'Current value',
                        style: TextStyle(color: AqsColors.muted, fontSize: 11),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          'TZS ${NumberFormat('#,##0.00').format(summary.totalAmount)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),

          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpenDrawings,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Go to Workspace'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),

          // FutureBuilder<BuildingCounts>(
          //   future: countsFuture,
          //   builder: (_, s) {
          //     final c = s.data;
          //     final drawings = c?.drawings;
          //     final meas = c?.measurements;
          //     final boq = c?.boqItems;
          //     final loading = s.connectionState == ConnectionState.waiting;
          //     final unavailable = s.hasError;

          //     String value(int? count) {
          //       if (loading) return 'Loading...';
          //       if (unavailable) return 'Unavailable';
          //       return '${count ?? 0}';
          //     }

          //     return Row(
          //       children: [
          //         Expanded(
          //           child: _MiniStat(
          //             icon: Icons.picture_as_pdf_rounded,
          //             label: 'Drawings',
          //             value: value(drawings),
          //             loading: loading,
          //             onTap: loading ? null : onOpenDrawings,
          //           ),
          //         ),
          //         Expanded(
          //           child: _MiniStat(
          //             icon: Icons.straighten_rounded,
          //             label: 'Measures',
          //             value: value(meas),
          //             loading: loading,
          //             onTap: loading ? null : onOpenMeasurements,
          //           ),
          //         ),
          //         Expanded(
          //           child: _MiniStat(
          //             icon: Icons.list_alt_rounded,
          //             label: 'BOQ items',
          //             value: value(boq),
          //             loading: loading,
          //             onTap: loading ? null : onOpenBoq,
          //           ),
          //         ),
          //       ],
          //     );
          //   },
          // ),
        ],
      ),
    );
  }
}

/// --------------------- TAKEOFF PAGE (stub) ---------------------
/// Replace body with your real takeoff canvas page.
class TakeoffPage extends StatelessWidget {
  final String projectId;
  final String projectName;
  final String buildingId;
  final String buildingName;
  final String buildingCode;

  const TakeoffPage({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.buildingId,
    required this.buildingName,
    required this.buildingCode,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text('$buildingName  •  $buildingCode'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Drawings'),
              Tab(text: 'BOQ'),
              Tab(text: 'Measurements'),
              Tab(text: 'Notes'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            Center(child: Text('Drawings for $projectId / $buildingId')),
            Center(child: Text('BOQ for $projectId / $buildingId')),
            Center(child: Text('Measurements for $projectId / $buildingId')),
            Center(child: Text('Notes for $projectId / $buildingId')),
          ],
        ),
      ),
    );
  }
}
