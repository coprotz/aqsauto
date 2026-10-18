import 'package:aqs/core/state/firestore_state.dart';
import 'dart:typed_data';

import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/boq/controllers/boq_controller.dart';
import 'package:aqs/features/utils/helpers/boq_helpers.dart';
import 'package:aqs/features/projects/pages/project_boq_package_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_saver/file_saver.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String? _selectedProjectId;
  String? _selectedSiteId;
  final Set<String> _exportingBuildingIds = <String>{};
  bool _exportingCombinedWorkbook = false;
  bool _exportingCombinedPdf = false;
  Future<_ReportData>? _reportFuture;
  String? _reportFutureProjectId;
  int _reportRevision = 0;

  String _s(dynamic v) => (v ?? '').toString().trim();

  bool _canSeeProject(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final data = doc.data();
    final ownerId = _s(data['ownerId']);
    final members = (data['members'] as List?) ?? const [];
    return ownerId == uid || members.map((e) => e.toString()).contains(uid);
  }

  Future<_ReportData> _reportFor(
    QueryDocumentSnapshot<Map<String, dynamic>> project,
  ) {
    if (_reportFuture == null || _reportFutureProjectId != project.id) {
      _reportFutureProjectId = project.id;
      _reportFuture = _loadReportData(project);
    }
    return _reportFuture!;
  }

  void _refreshReport(QueryDocumentSnapshot<Map<String, dynamic>> project) {
    setState(() {
      _reportFutureProjectId = project.id;
      _reportFuture = _loadReportData(project);
      _reportRevision++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance
              .collection('projects')
              .orderBy('createdAt', descending: true)
              .stateSnapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Reports error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final projects = snap.data!.docs.where(_canSeeProject).toList();
        if (projects.isEmpty) {
          return const _EmptyReportsState();
        }

        final selectedId =
            _selectedProjectId != null &&
                    projects.any((project) => project.id == _selectedProjectId)
                ? _selectedProjectId!
                : projects.first.id;
        final selectedProject = projects.firstWhere(
          (project) => project.id == selectedId,
        );

        return FutureBuilder<_ReportData>(
          key: ValueKey('$selectedId-$_reportRevision'),
          future: _reportFor(selectedProject),
          builder: (context, reportSnap) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 24,
                    compact ? 16 : 22,
                    compact ? 16 : 24,
                    32,
                  ),
                  children: [
                    _ReportsHero(
                      projects: projects,
                      selectedProjectId: selectedId,
                      onProjectChanged:
                          (id) => setState(() {
                            _selectedProjectId = id;
                            _selectedSiteId = null;
                            _reportFuture = null;
                            _reportFutureProjectId = null;
                          }),
                      onRefresh: () => _refreshReport(selectedProject),
                    ),
                    const SizedBox(height: 18),
                    if (reportSnap.hasError)
                      _ReportsErrorState(
                        message: 'Unable to load reports: ${reportSnap.error}',
                      )
                    else if (!reportSnap.hasData)
                      _ReportsLoadingState(
                        projectName:
                            (selectedProject.data()['name'] ?? 'Project')
                                .toString(),
                      )
                    else ...[
                      _KpiGrid(data: reportSnap.data!),
                      const SizedBox(height: 18),
                      _SiteReportSection(
                        data: reportSnap.data!,
                        selectedSiteId: _selectedSiteId,
                        onSiteChanged:
                            (siteId) =>
                                setState(() => _selectedSiteId = siteId),
                        buildings: _buildingsForSite(reportSnap.data!),
                        exportingWorkbook: _exportingCombinedWorkbook,
                        exportingPdf: _exportingCombinedPdf,
                        onDownload:
                            (visibleBuildings) => _downloadCombinedBoqWorkbook(
                              reportSnap.data!,
                              visibleBuildings
                                  .where(
                                    (building) => building.boqItemCount > 0,
                                  )
                                  .toList(),
                            ),
                        onDownloadReports:
                            (visibleBuildings) => _downloadCombinedPdfReports(
                              reportSnap.data!,
                              visibleBuildings
                                  .where(
                                    (building) => building.boqItemCount > 0,
                                  )
                                  .toList(),
                            ),
                      ),
                      const SizedBox(height: 18),
                      _SharedCostsReportSection(data: reportSnap.data!),
                      const SizedBox(height: 18),
                      _BuildingProgressSection(
                        data: reportSnap.data!,
                        buildings: _buildingsForSite(reportSnap.data!),
                        selectedSiteName:
                            _selectedSiteId == null
                                ? null
                                : reportSnap.data!.sites
                                    .where((site) => site.id == _selectedSiteId)
                                    .map((site) => site.name)
                                    .firstOrNull,
                        exportingBuildingIds: _exportingBuildingIds,
                        onExcel:
                            (building) => _downloadBuildingExcel(
                              selectedId,
                              reportSnap.data!,
                              building,
                            ),
                        onPdf:
                            (building) => _downloadBuildingPdf(
                              reportSnap.data!,
                              building,
                            ),
                      ),
                      const SizedBox(height: 18),
                      _AvailableReports(data: reportSnap.data!),
                      const SizedBox(height: 18),
                      _MeasurementSummary(data: reportSnap.data!),
                      const SizedBox(height: 18),
                      _UnmeasuredItems(data: reportSnap.data!),
                      const SizedBox(height: 18),
                      _AuditTrail(data: reportSnap.data!),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  List<_BuildingReportData> _buildingsForSite(_ReportData report) {
    if (_selectedSiteId == null ||
        !report.sites.any((site) => site.id == _selectedSiteId)) {
      return report.buildings;
    }
    if (_selectedSiteId == '__unassigned__') {
      final configuredIds = report.sites.map((site) => site.id).toSet();
      return report.buildings
          .where(
            (building) =>
                building.siteId.isEmpty ||
                !configuredIds.contains(building.siteId),
          )
          .toList();
    }
    return report.buildings
        .where((building) => building.siteId == _selectedSiteId)
        .toList();
  }

  Future<_ReportData> _loadReportData(
    QueryDocumentSnapshot<Map<String, dynamic>> project,
  ) async {
    final projectRef = project.reference;
    final buildings = await projectRef.collection('buildings').get();
    final sitesSnapshot = await projectRef.collection('sites').get();
    final projectAllowances =
        await projectRef.collection('generalAllowances').get();
    final externalQuotations =
        await projectRef.collection('externalQuotations').get();
    final projectPackages =
        await projectRef.collection('projectBoqPackages').get();
    final boqItems = <_BoqReportItem>[];
    final measurements = <_MeasurementReportItem>[];
    final buildingNames = <String, String>{};
    final buildingSiteIds = <String, String>{};
    final buildingAllowanceTotals = <String, double>{};

    await Future.wait(
      buildings.docs.map((building) async {
        final buildingName =
            _s(building.data()['name']).isEmpty
                ? _s(building.data()['code']).isEmpty
                    ? 'Building'
                    : _s(building.data()['code'])
                : _s(building.data()['name']);
        buildingNames[building.id] = buildingName;
        buildingSiteIds[building.id] = _s(building.data()['siteId']);

        var boqSnap = await building.reference.collection('boq').get();
        if (boqSnap.docs.isEmpty) {
          boqSnap = await building.reference.collection('boqItems').get();
        }
        final boqRows =
            boqSnap.docs
                .map((doc) => Map<String, dynamic>.from(doc.data()))
                .toList();
        final measSnap =
            await building.reference.collection('measurements').get();
        final allowanceSnap =
            await building.reference.collection('generalAllowances').get();
        buildingAllowanceTotals[building.id] = allowanceSnap.docs.fold<double>(
          0,
          (sum, item) {
            final data = item.data();
            if (data['includedInTotal'] == false) return sum;
            return sum +
                (data['amount'] == null
                    ? _num(data['quantity']) * _num(data['rate'])
                    : _num(data['amount']));
          },
        );

        for (final doc in boqSnap.docs) {
          final data = doc.data();
          final rowType = _rowType(data['rowType']);
          if (rowType != 'item') continue;
          final code = hierarchicalBoqCodeFromRows(data, boqRows);
          boqItems.add(
            _BoqReportItem(
              id: doc.id,
              buildingId: building.id,
              buildingName: buildingName,
              code: code,
              matchingCodes:
                  {
                    _s(data['resolvedBoqCode']),
                    _s(data['displayCode']),
                    _s(data['boqCode']),
                    code,
                  }.where((value) => value.isNotEmpty).toList(),
              description:
                  _s(data['description']).isNotEmpty
                      ? _s(data['description'])
                      : _s(data['boqDescription']),
              section: _sectionLabelForBoqRow(data, boqRows),
              unit: _s(data['unit']),
              rate: _num(data['rate']),
              order: _num(data['order']),
              qtyOverride:
                  data['qtyOverride'] is num
                      ? (data['qtyOverride'] as num).toDouble()
                      : double.tryParse('${data['qtyOverride'] ?? ''}'),
            ),
          );
        }

        for (final doc in measSnap.docs) {
          final data = doc.data();
          measurements.add(
            _MeasurementReportItem(
              id: doc.id,
              buildingId: building.id,
              buildingName: buildingName,
              boqItemId: _s(data['boqItemId']),
              boqCode:
                  _s(data['resolvedBoqCode']).isNotEmpty
                      ? _s(data['resolvedBoqCode'])
                      : _s(data['boqCode']),
              boqCodes:
                  {
                    _s(data['resolvedBoqCode']),
                    _s(data['boqCode']),
                    _s(data['boqCodeNorm']),
                  }.where((value) => value.isNotEmpty).toList(),
              title: _measurementTitle(data),
              unit: _s(data['unit']),
              value: _num(data['value']),
              createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
              actorName: _firstText(data, [
                'lastActorName',
                'updatedByName',
                'createdByName',
                'actorName',
              ]),
              actorUid: _firstText(data, [
                'lastActorUid',
                'updatedByUid',
                'createdByUid',
                'actorId',
              ]),
            ),
          );
        }
      }),
    );

    final totalsByBoq = <String, double>{};
    final totalsByBoqItemId = <String, double>{};
    for (final measurement in measurements) {
      final boqItemId = measurement.boqItemId.trim();
      if (boqItemId.isNotEmpty) {
        final idKey = '${measurement.buildingId}|$boqItemId';
        totalsByBoqItemId[idKey] =
            (totalsByBoqItemId[idKey] ?? 0) + measurement.value;
        // A unique BOQ document ID must take precedence. Civil Works leaf
        // codes such as A, i, and ii repeat in different sections.
        continue;
      }
      for (final code in measurement.boqCodes) {
        final codeKey = _key(code);
        if (codeKey.isEmpty) continue;
        final key = '${measurement.buildingId}|$codeKey';
        totalsByBoq[key] = (totalsByBoq[key] ?? 0) + measurement.value;
      }
    }

    final aliasCounts = <String, int>{};
    for (final item in boqItems) {
      final aliases =
          item.matchingCodes.map(_key).where((key) => key.isNotEmpty).toSet();
      for (final alias in aliases) {
        final key = '${item.buildingId}|$alias';
        aliasCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
      }
    }

    int measuredBoqItems = 0;
    final measuredSummaries = <_MeasuredBoqSummary>[];
    final unmeasured = <_BoqReportItem>[];
    final boqLinesByBuilding = <String, List<_BuildingBoqLine>>{};

    for (final item in boqItems) {
      var measuredQty = totalsByBoqItemId['${item.buildingId}|${item.id}'];
      if (measuredQty == null) {
        for (final code in item.matchingCodes) {
          final codeKey = '${item.buildingId}|${_key(code)}';
          if (aliasCounts[codeKey] != 1) continue;
          final matched = totalsByBoq[codeKey];
          if (matched != null) {
            measuredQty = matched;
            break;
          }
        }
      }
      measuredQty ??= 0;
      final qty = item.qtyOverride ?? measuredQty;
      final amount = qty * item.rate;
      boqLinesByBuilding
          .putIfAbsent(item.buildingId, () => [])
          .add(_BuildingBoqLine(item: item, quantity: qty, amount: amount));
      if (measuredQty > 0 || (item.qtyOverride ?? 0) > 0) {
        measuredBoqItems += 1;
        measuredSummaries.add(
          _MeasuredBoqSummary(
            code: item.code,
            description: item.description,
            buildingName: item.buildingName,
            unit: item.unit,
            quantity: qty,
            amount: amount,
          ),
        );
      } else {
        unmeasured.add(item);
      }
    }

    measurements.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    measuredSummaries.sort((a, b) => b.amount.compareTo(a.amount));

    final buildingReports =
        buildingNames.entries.map((entry) {
            final lines = List<_BuildingBoqLine>.from(
              boqLinesByBuilding[entry.key] ?? const <_BuildingBoqLine>[],
            )..sort((a, b) {
              final byOrder = a.item.order.compareTo(b.item.order);
              return byOrder != 0
                  ? byOrder
                  : a.item.code.toLowerCase().compareTo(
                    b.item.code.toLowerCase(),
                  );
            });
            final buildingMeasurements =
                measurements
                    .where((measurement) => measurement.buildingId == entry.key)
                    .length;
            final measuredItems =
                lines.where((line) => line.quantity > 0).length;
            return _BuildingReportData(
              id: entry.key,
              name: entry.value,
              siteId: buildingSiteIds[entry.key] ?? '',
              boqItemCount: lines.length,
              measuredBoqItemCount: measuredItems,
              measurementCount: buildingMeasurements,
              value: lines.fold<double>(0, (sum, line) => sum + line.amount),
              allowanceValue: buildingAllowanceTotals[entry.key] ?? 0,
              boqLines: lines,
            );
          }).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

    final siteReports = <_SiteReportData>[];
    for (final site in sitesSnapshot.docs.where(
      (site) => site.data()['isDeleted'] != true,
    )) {
      final siteBuildings =
          buildingReports
              .where((building) => building.siteId == site.id)
              .toList();
      var sharedSiteCosts = _num(site.data()['allowanceTotal']);
      if (sharedSiteCosts == 0) {
        final siteAllowances =
            await site.reference.collection('generalAllowances').get();
        sharedSiteCosts = siteAllowances.docs.fold<double>(0, (sum, item) {
          final data = item.data();
          if (data['includedInTotal'] == false) return sum;
          return sum +
              (data['amount'] == null
                  ? _num(data['quantity']) * _num(data['rate'])
                  : _num(data['amount']));
        });
      }
      siteReports.add(
        _SiteReportData(
          id: site.id,
          name:
              _s(site.data()['name']).isEmpty
                  ? 'Site'
                  : _s(site.data()['name']),
          buildingCount: siteBuildings.length,
          buildingWorksValue: siteBuildings.fold<double>(
            0,
            (sum, building) => sum + building.totalValue,
          ),
          sharedSiteCosts: sharedSiteCosts,
          boqItemCount: siteBuildings.fold<int>(
            0,
            (sum, building) => sum + building.boqItemCount,
          ),
          measuredBoqItemCount: siteBuildings.fold<int>(
            0,
            (sum, building) => sum + building.measuredBoqItemCount,
          ),
        ),
      );
    }
    final configuredSiteIds = siteReports.map((site) => site.id).toSet();
    final unassignedBuildings =
        buildingReports
            .where(
              (building) =>
                  building.siteId.isEmpty ||
                  !configuredSiteIds.contains(building.siteId),
            )
            .toList();
    if (unassignedBuildings.isNotEmpty) {
      siteReports.add(
        _SiteReportData(
          id: '__unassigned__',
          name: siteReports.isEmpty ? 'Main Site' : 'Unassigned buildings',
          buildingCount: unassignedBuildings.length,
          buildingWorksValue: unassignedBuildings.fold<double>(
            0,
            (value, building) => value + building.totalValue,
          ),
          sharedSiteCosts: 0,
          boqItemCount: unassignedBuildings.fold<int>(
            0,
            (value, building) => value + building.boqItemCount,
          ),
          measuredBoqItemCount: unassignedBuildings.fold<int>(
            0,
            (value, building) => value + building.measuredBoqItemCount,
          ),
        ),
      );
    }
    siteReports.sort((a, b) => a.name.compareTo(b.name));

    final sharedCosts = <_SharedCostReportData>[];
    final projectAllowanceTotal = projectAllowances.docs.fold<double>(0, (
      sum,
      item,
    ) {
      final data = item.data();
      if (data['includedInTotal'] == false) return sum;
      return sum +
          (data['amount'] == null
              ? _num(data['quantity']) * _num(data['rate'])
              : _num(data['amount']));
    });
    if (projectAllowanceTotal > 0 || projectAllowances.docs.isNotEmpty) {
      sharedCosts.add(
        _SharedCostReportData(
          label: 'Project provisional works',
          itemCount: projectAllowances.docs.length,
          value: projectAllowanceTotal,
          icon: Icons.playlist_add_check_circle_outlined,
        ),
      );
    }
    for (final package in projectPackages.docs) {
      final data = package.data();
      final count = _num(data['itemCount']).round();
      final value =
          data['includedInProjectTotal'] == false
              ? 0.0
              : _num(data['totalAmount']);
      if (count > 0 || value > 0) {
        final known =
            projectBoqPackageDefinitions
                .where((definition) => definition.key == package.id)
                .firstOrNull;
        final iconKey = _s(data['iconKey']);
        sharedCosts.add(
          _SharedCostReportData(
            label:
                _s(data['title']).isNotEmpty
                    ? _s(data['title'])
                    : known?.title ?? 'Shared Cost',
            itemCount: count,
            value: value,
            icon:
                known?.icon ??
                projectCostPackageIcon(iconKey.isEmpty ? 'receipt' : iconKey),
          ),
        );
      }
    }
    final quotationTotal = externalQuotations.docs.fold<double>(0, (sum, doc) {
      final data = doc.data();
      if (data['includedInProjectTotal'] != true) return sum;
      final effective = _num(data['effectiveAmount']);
      final approved = _num(data['approvedAmount']);
      final assessed = _num(data['assessedAmount']);
      final quoted = _num(data['quotedAmount']);
      return sum +
          (effective > 0
              ? effective
              : approved > 0
              ? approved
              : assessed > 0
              ? assessed
              : quoted);
    });
    if (externalQuotations.docs.isNotEmpty) {
      sharedCosts.add(
        _SharedCostReportData(
          label: 'External quotations',
          itemCount: externalQuotations.docs.length,
          value: quotationTotal,
          icon: Icons.request_quote_outlined,
        ),
      );
    }
    final sitesCost = siteReports.fold<double>(
      0,
      (sum, site) => sum + site.totalValue,
    );
    final sharedProjectCosts = sharedCosts.fold<double>(
      0,
      (sum, cost) => sum + cost.value,
    );

    return _ReportData(
      projectId: project.id,
      projectName:
          _s(project.data()['name']).isEmpty
              ? 'Project'
              : _s(project.data()['name']),
      currency:
          _s(project.data()['currency']).isEmpty
              ? 'TZS'
              : _s(project.data()['currency']),
      buildingCount: buildings.docs.length,
      boqItemCount: boqItems.length,
      measurementCount: measurements.length,
      measuredBoqItemCount: measuredBoqItems,
      projectValue: sitesCost + sharedProjectCosts,
      sitesCost: sitesCost,
      sharedProjectCosts: sharedProjectCosts,
      measuredSummaries: measuredSummaries,
      unmeasuredItems: unmeasured,
      recentMeasurements: measurements.take(12).toList(),
      buildings: buildingReports,
      sites: siteReports,
      sharedCosts: sharedCosts,
    );
  }

  Future<void> _downloadBuildingExcel(
    String projectId,
    _ReportData report,
    _BuildingReportData building,
  ) async {
    await _runBuildingExport(building.id, () async {
      final controller = BoqController(
        projectId: projectId,
        buildingId: building.id,
        builldingName: building.name,
      );
      controller.onInit();
      await controller.exportBoqExcel(
        projectName: report.projectName,
        buildingName: building.name,
      );
    });
  }

  // Retained for compatibility with older report actions that offered a
  // building picker. The primary action now exports every BOQ immediately.
  // ignore: unused_element
  Future<void> _selectAndDownloadBoqs(_ReportData report) async {
    if (_exportingCombinedWorkbook || report.buildings.isEmpty) return;
    final availableBoqs =
        report.buildings
            .where((building) => building.boqItemCount > 0)
            .toList();
    if (availableBoqs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This project has no BOQs to download.')),
      );
      return;
    }
    final selectedIds = availableBoqs.map((building) => building.id).toSet();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final allSelected = selectedIds.length == availableBoqs.length;
            return AlertDialog(
              title: const Text('Download multiple BOQs'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Choose the buildings to include. The workbook will contain a consolidated summary and one BOQ sheet per selected building.',
                      style: TextStyle(color: AqsColors.muted, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed:
                              () => setDialogState(() {
                                selectedIds
                                  ..clear()
                                  ..addAll(
                                    availableBoqs.map(
                                      (building) => building.id,
                                    ),
                                  );
                              }),
                          child: Text(
                            allSelected ? 'All selected' : 'Select all',
                          ),
                        ),
                        TextButton(
                          onPressed:
                              () => setDialogState(() => selectedIds.clear()),
                          child: const Text('Clear'),
                        ),
                        const Spacer(),
                        Text(
                          '${selectedIds.length} selected',
                          style: const TextStyle(
                            color: AqsColors.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: report.buildings.length,
                        itemBuilder: (context, index) {
                          final building = report.buildings[index];
                          final selected = selectedIds.contains(building.id);
                          final hasBoq = building.boqItemCount > 0;
                          return CheckboxListTile(
                            value: selected,
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              building.name,
                              style: const TextStyle(
                                color: AqsColors.ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              hasBoq
                                  ? '${building.measuredBoqItemCount}/${building.boqItemCount} items measured • ${building.measurementCount} measurements'
                                  : 'No BOQ items available',
                            ),
                            onChanged:
                                hasBoq
                                    ? (checked) => setDialogState(() {
                                      if (checked == true) {
                                        selectedIds.add(building.id);
                                      } else {
                                        selectedIds.remove(building.id);
                                      }
                                    })
                                    : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed:
                      selectedIds.isEmpty
                          ? null
                          : () => Navigator.of(
                            dialogContext,
                          ).pop(Set<String>.from(selectedIds)),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Create workbook'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null || result.isEmpty || !mounted) return;
    final selected =
        report.buildings
            .where((building) => result.contains(building.id))
            .toList();
    await _downloadCombinedBoqWorkbook(report, selected);
  }

  Future<void> _downloadCombinedBoqWorkbook(
    _ReportData report,
    List<_BuildingReportData> buildings,
  ) async {
    setState(() => _exportingCombinedWorkbook = true);
    try {
      final sharedCostSheets = await _loadSharedCostSheets(report);

      // Load site-level shared costs grouped by cost type. Each cost type
      // is shown once in the consolidated Summary and exported as its own
      // worksheet so the site total remains fully traceable.
      final siteSharedCostCategories =
          <String, Map<String, List<_WorkbookCostRow>>>{};
      final projectRef = FirebaseFirestore.instance
          .collection('projects')
          .doc(report.projectId);
      final sitesSnapshot = await projectRef.collection('sites').get();
      for (final siteDoc in sitesSnapshot.docs.where(
        (doc) => doc.data()['isDeleted'] != true,
      )) {
        final allowanceDocs =
            await siteDoc.reference.collection('generalAllowances').get();
        final categories = <String, List<_WorkbookCostRow>>{};
        for (final allowance in allowanceDocs.docs) {
          final data = allowance.data();
          if (data['includedInTotal'] == false) continue;
          if (_s(data['rowType']).toLowerCase() == 'subheading') continue;
          final quantity = _num(data['quantity']);
          final rate = _num(data['rate']);
          final amount =
              data['amount'] == null ? quantity * rate : _num(data['amount']);
          final rawCategory = _s(data['category']).trim();
          final category =
              rawCategory.isEmpty ? 'Other shared site costs' : rawCategory;
          categories.putIfAbsent(category, () => <_WorkbookCostRow>[]).add(
            _WorkbookCostRow(
              code: _firstText(data, ['itemCode', 'basis', 'code']),
              description: _firstText(data, [
                'description',
                'title',
                'label',
                'notes',
              ]),
              unit: _s(data['unit']),
              quantity: quantity,
              rate: rate,
              amount: amount,
            ),
          );
        }
        siteSharedCostCategories[siteDoc.id] = categories;
      }

      // If a stored site total contains a retained balance not represented by
      // itemised shared-cost rows, export that balance in its own worksheet too.
      for (final site in report.sites) {
        final categories =
            siteSharedCostCategories[site.id] ??
            <String, List<_WorkbookCostRow>>{};
        final listedTotal = categories.values
            .expand((rows) => rows)
            .fold<double>(0, (value, row) => value + row.amount);
        final retainedBalance = site.sharedSiteCosts - listedTotal;
        if (retainedBalance.abs() > 0.01) {
          categories['Other / retained shared site costs'] = [
            _WorkbookCostRow(
              code: '',
              description: 'Other / retained shared site costs',
              unit: 'Item',
              quantity: 1,
              rate: retainedBalance,
              amount: retainedBalance,
            ),
          ];
          siteSharedCostCategories[site.id] = categories;
          sharedCostSheets.add(
            _WorkbookCostSheet(
              key: 'site:${site.id}:Other / retained shared site costs',
              title: '${site.name} - Other retained site costs',
              rows: categories['Other / retained shared site costs']!,
              siteName: site.name,
              costType: 'Other / retained shared site costs',
            ),
          );
        }
      }

      final workbook = xl.Excel.createExcel();
      workbook.rename('Sheet1', 'Summary');
      final summary = workbook['Summary'];
      final usedNames = <String>{'summary'};
      final sheetNames = <String, String>{};
      final totalRows = <String, int>{};
      final navy = xl.ExcelColor.fromHexString('FF123A78');
      final blue = xl.ExcelColor.fromHexString('FF155EEF');
      final white = xl.ExcelColor.fromHexString('FFFFFFFF');
      final paleGreen = xl.ExcelColor.fromHexString('FFE8F7F0');
      final borderColor = xl.ExcelColor.fromHexString('FFD0D5DD');
      final thin = xl.Border(
        borderStyle: xl.BorderStyle.Thin,
        borderColorHex: borderColor,
      );
      final titleStyle = xl.CellStyle(
        bold: true,
        fontSize: 16,
        fontColorHex: white,
        backgroundColorHex: navy,
        verticalAlign: xl.VerticalAlign.Center,
      );
      final headerStyle = xl.CellStyle(
        bold: true,
        fontColorHex: white,
        backgroundColorHex: blue,
        verticalAlign: xl.VerticalAlign.Center,
        textWrapping: xl.TextWrapping.WrapText,
        topBorder: thin,
        bottomBorder: thin,
        leftBorder: thin,
        rightBorder: thin,
      );
      final textStyle = xl.CellStyle(
        verticalAlign: xl.VerticalAlign.Top,
        textWrapping: xl.TextWrapping.WrapText,
        bottomBorder: thin,
      );
      final numberStyle = xl.CellStyle(
        horizontalAlign: xl.HorizontalAlign.Right,
        verticalAlign: xl.VerticalAlign.Top,
        numberFormat: xl.NumFormat.custom(formatCode: '#,##0.00'),
        bottomBorder: thin,
      );
      final totalStyle = xl.CellStyle(
        bold: true,
        backgroundColorHex: paleGreen,
        horizontalAlign: xl.HorizontalAlign.Right,
        numberFormat: xl.NumFormat.custom(formatCode: '#,##0.00'),
        topBorder: thin,
        bottomBorder: thin,
      );
      final dateStyle = xl.CellStyle(
        numberFormat: xl.NumFormat.custom(formatCode: 'dd mmm yyyy, hh:mm'),
      );
      final generatedAt = DateTime.now();

      for (final building in buildings) {
        final sheetName = _uniqueExcelSheetName(building.name, usedNames);
        sheetNames[building.id] = sheetName;
        final sheet = workbook[sheetName];
        final siteName = _siteNameForBuilding(report, building);
        sheet.appendRow([
          xl.TextCellValue('${building.name} - BILL OF QUANTITIES'),
          ...List<xl.CellValue>.generate(5, (_) => xl.TextCellValue('')),
        ]);
        for (var column = 0; column < 6; column++) {
          sheet
              .cell(
                xl.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0),
              )
              .cellStyle = titleStyle;
        }
        sheet.appendRow([
          xl.TextCellValue('Project'),
          xl.TextCellValue(report.projectName),
          ...List<xl.CellValue>.generate(4, (_) => xl.TextCellValue('')),
        ]);
        sheet.appendRow([
          xl.TextCellValue('Site / Location'),
          xl.TextCellValue(siteName),
          ...List<xl.CellValue>.generate(4, (_) => xl.TextCellValue('')),
        ]);
        sheet.appendRow([
          xl.TextCellValue('Building'),
          xl.TextCellValue(building.name),
          ...List<xl.CellValue>.generate(4, (_) => xl.TextCellValue('')),
        ]);
        sheet.appendRow(
          List<xl.CellValue>.generate(6, (_) => xl.TextCellValue('')),
        );
        sheet.appendRow([
          xl.TextCellValue('BOQ code'),
          xl.TextCellValue('Description'),
          xl.TextCellValue('Unit'),
          xl.TextCellValue('Quantity'),
          xl.TextCellValue('Rate'),
          xl.TextCellValue('Amount (${report.currency})'),
        ]);
        for (var column = 0; column < 6; column++) {
          sheet
              .cell(
                xl.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 5),
              )
              .cellStyle = headerStyle;
        }

        for (var index = 0; index < building.boqLines.length; index++) {
          final line = building.boqLines[index];
          final excelRow = index + 7;
          sheet.appendRow([
            xl.TextCellValue(line.item.code),
            xl.TextCellValue(line.item.description),
            xl.TextCellValue(line.item.unit),
            xl.DoubleCellValue(line.quantity),
            xl.DoubleCellValue(line.item.rate),
            xl.FormulaCellValue('D$excelRow*E$excelRow'),
          ]);
          final rowIndex = index + 6;
          for (var column = 0; column < 6; column++) {
            sheet
                    .cell(
                      xl.CellIndex.indexByColumnRow(
                        columnIndex: column,
                        rowIndex: rowIndex,
                      ),
                    )
                    .cellStyle =
                column >= 3 ? numberStyle : textStyle;
          }
        }

        final totalRowIndex = building.boqLines.length + 6;
        final totalExcelRow = totalRowIndex + 1;
        final firstDataRow = 7;
        final lastDataRow = building.boqLines.length + 6;
        sheet.appendRow([
          ...List<xl.CellValue>.generate(4, (_) => xl.TextCellValue('')),
          xl.TextCellValue('TOTAL'),
          building.boqLines.isEmpty
              ? const xl.DoubleCellValue(0.0)
              : xl.FormulaCellValue('SUM(F$firstDataRow:F$lastDataRow)'),
        ]);
        for (var column = 0; column < 6; column++) {
          sheet
              .cell(
                xl.CellIndex.indexByColumnRow(
                  columnIndex: column,
                  rowIndex: totalRowIndex,
                ),
              )
              .cellStyle = totalStyle;
        }
        totalRows[building.id] = totalExcelRow;
        sheet.setColumnWidth(0, 18);
        sheet.setColumnWidth(1, 72);
        sheet.setColumnWidth(2, 12);
        sheet.setColumnWidth(3, 14);
        sheet.setColumnWidth(4, 16);
        sheet.setColumnWidth(5, 20);
      }

      final sharedSheetNames = <String, String>{};
      final sharedSheetTotalRows = <String, int>{};
      for (final costSchedule in sharedCostSheets) {
        final sheetName = _uniqueExcelSheetName(costSchedule.title, usedNames);
        final sheet = workbook[sheetName];
        sharedSheetNames[costSchedule.key] = sheetName;
        sheet.appendRow([
          xl.TextCellValue(costSchedule.title.toUpperCase()),
          ...List<xl.CellValue>.generate(5, (_) => xl.TextCellValue('')),
        ]);
        for (var column = 0; column < 6; column++) {
          sheet
              .cell(
                xl.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0),
              )
              .cellStyle = titleStyle;
        }
        sheet.appendRow([
          xl.TextCellValue('Project'),
          xl.TextCellValue(report.projectName),
          ...List<xl.CellValue>.generate(4, (_) => xl.TextCellValue('')),
        ]);
        if (costSchedule.siteName.isNotEmpty) {
          sheet.appendRow([
            xl.TextCellValue('Site / Location'),
            xl.TextCellValue(costSchedule.siteName),
            ...List<xl.CellValue>.generate(4, (_) => xl.TextCellValue('')),
          ]);
        }
        if (costSchedule.costType.isNotEmpty) {
          sheet.appendRow([
            xl.TextCellValue('Cost type'),
            xl.TextCellValue(costSchedule.costType),
            ...List<xl.CellValue>.generate(4, (_) => xl.TextCellValue('')),
          ]);
        }
        sheet.appendRow(
          List<xl.CellValue>.generate(6, (_) => xl.TextCellValue('')),
        );
        final headerRowIndex = sheet.maxRows;
        sheet.appendRow([
          xl.TextCellValue('Item No / code'),
          xl.TextCellValue('Description'),
          xl.TextCellValue('Unit'),
          xl.TextCellValue('Quantity'),
          xl.TextCellValue('Rate'),
          xl.TextCellValue('Amount (${report.currency})'),
        ]);
        for (var column = 0; column < 6; column++) {
          sheet
              .cell(
                xl.CellIndex.indexByColumnRow(
                  columnIndex: column,
                  rowIndex: headerRowIndex,
                ),
              )
              .cellStyle = headerStyle;
        }
        for (var index = 0; index < costSchedule.rows.length; index++) {
          final row = costSchedule.rows[index];
          sheet.appendRow([
            xl.TextCellValue(row.code),
            xl.TextCellValue(row.description),
            xl.TextCellValue(row.unit),
            xl.DoubleCellValue(row.quantity),
            xl.DoubleCellValue(row.rate),
            xl.DoubleCellValue(row.amount),
          ]);
          final rowIndex = headerRowIndex + index + 1;
          for (var column = 0; column < 6; column++) {
            sheet
                .cell(
                  xl.CellIndex.indexByColumnRow(
                    columnIndex: column,
                    rowIndex: rowIndex,
                  ),
                )
                .cellStyle = column >= 3 ? numberStyle : textStyle;
          }
        }
        final totalRow = headerRowIndex + costSchedule.rows.length + 1;
        sheet.appendRow([
          ...List<xl.CellValue>.generate(4, (_) => xl.TextCellValue('')),
          xl.TextCellValue('TOTAL'),
          xl.DoubleCellValue(costSchedule.total),
        ]);
        sharedSheetTotalRows[costSchedule.key] = totalRow + 1;
        for (var column = 0; column < 6; column++) {
          sheet
              .cell(
                xl.CellIndex.indexByColumnRow(
                  columnIndex: column,
                  rowIndex: totalRow,
                ),
              )
              .cellStyle = totalStyle;
        }
        sheet.setColumnWidth(0, 18);
        sheet.setColumnWidth(1, 72);
        sheet.setColumnWidth(2, 12);
        sheet.setColumnWidth(3, 14);
        sheet.setColumnWidth(4, 18);
        sheet.setColumnWidth(5, 20);
      }

      summary.appendRow([
        xl.TextCellValue('CONSOLIDATED BOQ SUMMARY'),
        ...List<xl.CellValue>.generate(7, (_) => xl.TextCellValue('')),
      ]);
      for (var column = 0; column < 8; column++) {
        summary
            .cell(
              xl.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0),
            )
            .cellStyle = titleStyle;
      }
      summary.appendRow([
        xl.TextCellValue('Project'),
        xl.TextCellValue(report.projectName),
        ...List<xl.CellValue>.generate(6, (_) => xl.TextCellValue('')),
      ]);
      summary.appendRow([
        xl.TextCellValue('Generated'),
        xl.DateTimeCellValue.fromDateTime(generatedAt),
        ...List<xl.CellValue>.generate(6, (_) => xl.TextCellValue('')),
      ]);
      summary
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2))
          .cellStyle = dateStyle;
      summary.appendRow([
        xl.TextCellValue('Included BOQs'),
        xl.IntCellValue(buildings.length),
        ...List<xl.CellValue>.generate(6, (_) => xl.TextCellValue('')),
      ]);
      summary.appendRow(
        List<xl.CellValue>.generate(8, (_) => xl.TextCellValue('')),
      );

      var summaryGrandTotal = 0.0;
      for (final site in report.sites) {
        final siteBuildings =
            buildings.where((building) => building.siteId == site.id).toList();
        if (siteBuildings.isEmpty) continue;

        final siteTitleRow = summary.maxRows;
        summary.appendRow([
          xl.TextCellValue('SITE / LOCATION: ${site.name.toUpperCase()}'),
          ...List<xl.CellValue>.generate(7, (_) => xl.TextCellValue('')),
        ]);
        for (var column = 0; column < 8; column++) {
          summary
              .cell(
                xl.CellIndex.indexByColumnRow(
                  columnIndex: column,
                  rowIndex: siteTitleRow,
                ),
              )
              .cellStyle = titleStyle;
        }

        final headerRow = summary.maxRows;
        summary.appendRow([
          xl.TextCellValue('Building'),
          xl.TextCellValue('Measurements'),
          xl.TextCellValue('Amount (${report.currency})'),
          ...List<xl.CellValue>.generate(5, (_) => xl.TextCellValue('')),
        ]);
        for (var column = 0; column < 3; column++) {
          summary
              .cell(
                xl.CellIndex.indexByColumnRow(
                  columnIndex: column,
                  rowIndex: headerRow,
                ),
              )
              .cellStyle = headerStyle;
        }

        var siteBuildingTotal = 0.0;
        for (final building in siteBuildings) {
          final sheetName = sheetNames[building.id]!;
          final escapedSheetName = sheetName.replaceAll("'", "''");
          summary.appendRow([
            xl.TextCellValue(building.name),
            xl.IntCellValue(building.measurementCount),
            xl.FormulaCellValue("'$escapedSheetName'!F${totalRows[building.id]}"),
            ...List<xl.CellValue>.generate(5, (_) => xl.TextCellValue('')),
          ]);
          final rowIndex = summary.maxRows - 1;
          summary
              .cell(
                xl.CellIndex.indexByColumnRow(
                  columnIndex: 0,
                  rowIndex: rowIndex,
                ),
              )
              .cellStyle = textStyle;
          summary
              .cell(
                xl.CellIndex.indexByColumnRow(
                  columnIndex: 1,
                  rowIndex: rowIndex,
                ),
              )
              .cellStyle = textStyle;
          summary
              .cell(
                xl.CellIndex.indexByColumnRow(
                  columnIndex: 2,
                  rowIndex: rowIndex,
                ),
              )
              .cellStyle = numberStyle;
          siteBuildingTotal += building.totalValue;
        }

        final buildingSubtotalRow = summary.maxRows;
        summary.appendRow([
          xl.TextCellValue('${site.name.toUpperCase()} - BUILDINGS SUBTOTAL'),
          xl.TextCellValue(''),
          xl.DoubleCellValue(siteBuildingTotal),
          ...List<xl.CellValue>.generate(5, (_) => xl.TextCellValue('')),
        ]);
        for (var column = 0; column < 3; column++) {
          summary
              .cell(
                xl.CellIndex.indexByColumnRow(
                  columnIndex: column,
                  rowIndex: buildingSubtotalRow,
                ),
              )
              .cellStyle = totalStyle;
        }

        final sharedCategories =
            siteSharedCostCategories[site.id] ??
            const <String, List<_WorkbookCostRow>>{};
        if (site.sharedSiteCosts > 0 || sharedCategories.isNotEmpty) {
          final sharedHeaderRow = summary.maxRows;
          summary.appendRow([
            xl.TextCellValue('SHARED SITE COSTS'),
            xl.TextCellValue(''),
            xl.TextCellValue('Amount (${report.currency})'),
            ...List<xl.CellValue>.generate(5, (_) => xl.TextCellValue('')),
          ]);
          for (var column = 0; column < 3; column++) {
            summary
                .cell(
                  xl.CellIndex.indexByColumnRow(
                    columnIndex: column,
                    rowIndex: sharedHeaderRow,
                  ),
                )
                .cellStyle = headerStyle;
          }

          final categories = sharedCategories.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          for (final category in categories) {
            final key = 'site:${site.id}:$category';
            final sheetName = sharedSheetNames[key] ?? '';
            final totalRow = sharedSheetTotalRows[key];
            final rows = sharedCategories[category] ?? const <_WorkbookCostRow>[];
            final categoryTotal = rows.fold<double>(
              0,
              (value, row) => value + row.amount,
            );
            final escapedSheetName = sheetName.replaceAll("'", "''");
            summary.appendRow([
              xl.TextCellValue(category),
              xl.TextCellValue(''),
              sheetName.isNotEmpty && totalRow != null
                  ? xl.FormulaCellValue("'$escapedSheetName'!F$totalRow")
                  : xl.DoubleCellValue(categoryTotal),
              ...List<xl.CellValue>.generate(5, (_) => xl.TextCellValue('')),
            ]);
            final rowIndex = summary.maxRows - 1;
            summary
                .cell(
                  xl.CellIndex.indexByColumnRow(
                    columnIndex: 0,
                    rowIndex: rowIndex,
                  ),
                )
                .cellStyle = textStyle;
            summary
                .cell(
                  xl.CellIndex.indexByColumnRow(
                    columnIndex: 1,
                    rowIndex: rowIndex,
                  ),
                )
                .cellStyle = textStyle;
            summary
                .cell(
                  xl.CellIndex.indexByColumnRow(
                    columnIndex: 2,
                    rowIndex: rowIndex,
                  ),
                )
                .cellStyle = numberStyle;
          }
        }

        final siteTotalRow = summary.maxRows;
        summary.appendRow([
          xl.TextCellValue('${site.name.toUpperCase()} - SITE TOTAL'),
          xl.TextCellValue(''),
          xl.DoubleCellValue(site.totalValue),
          ...List<xl.CellValue>.generate(5, (_) => xl.TextCellValue('')),
        ]);
        for (var column = 0; column < 3; column++) {
          summary
              .cell(
                xl.CellIndex.indexByColumnRow(
                  columnIndex: column,
                  rowIndex: siteTotalRow,
                ),
              )
              .cellStyle = totalStyle;
        }
        summaryGrandTotal += site.totalValue;

        summary.appendRow(
          List<xl.CellValue>.generate(8, (_) => xl.TextCellValue('')),
        );
      }

      final summaryTotalRow = summary.maxRows;
      summary.appendRow([
        xl.TextCellValue('GRAND TOTAL - SITES'),
        xl.TextCellValue(''),
        xl.DoubleCellValue(summaryGrandTotal),
        ...List<xl.CellValue>.generate(5, (_) => xl.TextCellValue('')),
      ]);
      for (var column = 0; column < 3; column++) {
        summary
            .cell(
              xl.CellIndex.indexByColumnRow(
                columnIndex: column,
                rowIndex: summaryTotalRow,
              ),
            )
            .cellStyle = totalStyle;
      }
      summary.appendRow(
        List<xl.CellValue>.generate(8, (_) => xl.TextCellValue('')),
      );
      final costTitleRow = summary.maxRows;
      summary.appendRow([
        xl.TextCellValue('PROJECT COST SUMMARY'),
        ...List<xl.CellValue>.generate(7, (_) => xl.TextCellValue('')),
      ]);
      for (var column = 0; column < 8; column++) {
        summary
            .cell(
              xl.CellIndex.indexByColumnRow(
                columnIndex: column,
                rowIndex: costTitleRow,
              ),
            )
            .cellStyle = titleStyle;
      }
      summary.appendRow([
        xl.TextCellValue('Cost group'),
        xl.TextCellValue('Description'),
        xl.TextCellValue('Amount (${report.currency})'),
        ...List<xl.CellValue>.generate(5, (_) => xl.TextCellValue('')),
      ]);
      final costHeaderRow = costTitleRow + 1;
      for (var column = 0; column < 3; column++) {
        summary
            .cell(
              xl.CellIndex.indexByColumnRow(
                columnIndex: column,
                rowIndex: costHeaderRow,
              ),
            )
            .cellStyle = headerStyle;
      }

      // Site totals first, listed vertically.
      for (final site in report.sites) {
        summary.appendRow([
          xl.TextCellValue('Site'),
          xl.TextCellValue(site.name),
          xl.DoubleCellValue(site.totalValue),
          ...List<xl.CellValue>.generate(5, (_) => xl.TextCellValue('')),
        ]);
        final rowIndex = summary.maxRows - 1;
        for (var column = 0; column < 3; column++) {
          summary
              .cell(
                xl.CellIndex.indexByColumnRow(
                  columnIndex: column,
                  rowIndex: rowIndex,
                ),
              )
              .cellStyle = column == 2 ? numberStyle : textStyle;
        }
      }

      final sitesTotalRow = summary.maxRows;
      summary.appendRow([
        xl.TextCellValue(''),
        xl.TextCellValue('TOTAL SITE COSTS'),
        xl.DoubleCellValue(report.sitesCost),
        ...List<xl.CellValue>.generate(5, (_) => xl.TextCellValue('')),
      ]);
      for (var column = 0; column < 3; column++) {
        summary
            .cell(
              xl.CellIndex.indexByColumnRow(
                columnIndex: column,
                rowIndex: sitesTotalRow,
              ),
            )
            .cellStyle = totalStyle;
      }

      summary.appendRow(
        List<xl.CellValue>.generate(8, (_) => xl.TextCellValue('')),
      );

      // Shared project costs follow directly beneath the site totals.
      for (final cost in report.sharedCosts) {
        summary.appendRow([
          xl.TextCellValue('Shared project cost'),
          xl.TextCellValue(cost.label),
          xl.DoubleCellValue(cost.value),
          ...List<xl.CellValue>.generate(5, (_) => xl.TextCellValue('')),
        ]);
        final rowIndex = summary.maxRows - 1;
        for (var column = 0; column < 3; column++) {
          summary
              .cell(
                xl.CellIndex.indexByColumnRow(
                  columnIndex: column,
                  rowIndex: rowIndex,
                ),
              )
              .cellStyle = column == 2 ? numberStyle : textStyle;
        }
      }

      final sharedTotalRow = summary.maxRows;
      summary.appendRow([
        xl.TextCellValue(''),
        xl.TextCellValue('TOTAL SHARED PROJECT COSTS'),
        xl.DoubleCellValue(report.sharedProjectCosts),
        ...List<xl.CellValue>.generate(5, (_) => xl.TextCellValue('')),
      ]);
      for (var column = 0; column < 3; column++) {
        summary
            .cell(
              xl.CellIndex.indexByColumnRow(
                columnIndex: column,
                rowIndex: sharedTotalRow,
              ),
            )
            .cellStyle = totalStyle;
      }

      summary.appendRow(
        List<xl.CellValue>.generate(8, (_) => xl.TextCellValue('')),
      );

      // Final project total is shown on its own row at the bottom.
      final projectTotalRow = summary.maxRows;
      summary.appendRow([
        xl.TextCellValue(''),
        xl.TextCellValue('TOTAL PROJECT COST'),
        xl.DoubleCellValue(report.projectValue),
        ...List<xl.CellValue>.generate(5, (_) => xl.TextCellValue('')),
      ]);
      for (var column = 0; column < 3; column++) {
        summary
            .cell(
              xl.CellIndex.indexByColumnRow(
                columnIndex: column,
                rowIndex: projectTotalRow,
              ),
            )
            .cellStyle = totalStyle;
      }
      summary.setColumnWidth(0, 38);
      summary.setColumnWidth(1, 18);
      summary.setColumnWidth(2, 22);
      summary.setColumnWidth(3, 16);
      summary.setColumnWidth(4, 14);
      summary.setColumnWidth(5, 16);
      summary.setColumnWidth(6, 24);
      summary.setColumnWidth(7, 20);

      final bytes = workbook.encode();
      if (bytes == null) throw StateError('The workbook could not be created.');
      final safeName = report.projectName
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .replaceAll(' ', '_');
      final stamp = DateFormat('yyyyMMdd_HHmm').format(generatedAt);
      await FileSaver.instance.saveFile(
        name: 'All_BOQs_${safeName}_$stamp',
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${buildings.length} BOQs downloaded in one Excel workbook.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Workbook download failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _exportingCombinedWorkbook = false);
    }
  }

  Future<List<_WorkbookCostSheet>> _loadSharedCostSheets(
    _ReportData report,
  ) async {
    final projectRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(report.projectId);
    final schedules = <_WorkbookCostSheet>[];

    _WorkbookCostRow allowanceRow(Map<String, dynamic> data) {
      final quantity = _num(data['quantity']);
      final rate = _num(data['rate']);
      return _WorkbookCostRow(
        code: _firstText(data, ['itemCode', 'basis', 'code']),
        description: _firstText(data, ['description', 'notes']),
        unit: _s(data['unit']),
        quantity: quantity,
        rate: rate,
        amount: data['amount'] == null ? quantity * rate : _num(data['amount']),
      );
    }

    final projectAllowances =
        await projectRef.collection('generalAllowances').get();
    if (projectAllowances.docs.isNotEmpty) {
      schedules.add(
        _WorkbookCostSheet(
          key: 'project:allowances',
          title: 'Project allowances',
          rows:
              projectAllowances.docs
                  .map((doc) => allowanceRow(doc.data()))
                  .toList(),
        ),
      );
    }

    final packages = await projectRef.collection('projectBoqPackages').get();
    for (final package in packages.docs) {
      final items = await package.reference.collection('items').get();
      if (items.docs.isEmpty) continue;
      final known =
          projectBoqPackageDefinitions
              .where((definition) => definition.key == package.id)
              .firstOrNull;
      final title =
          _s(package.data()['title']).isNotEmpty
              ? _s(package.data()['title'])
              : known?.title ?? 'Shared Cost';
      final rows =
          items.docs
              .where((doc) => _s(doc.data()['rowType']).toLowerCase() == 'item')
              .map((doc) {
                final data = doc.data();
                return _WorkbookCostRow(
                  code: _firstText(data, ['code', 'sourceCode']),
                  description: _s(data['description']),
                  unit: _s(data['unit']),
                  quantity: _num(data['quantity']),
                  rate: _num(data['rate']),
                  amount: _num(data['amount']),
                );
              })
              .toList();
      if (rows.isNotEmpty) {
        schedules.add(
          _WorkbookCostSheet(
            key: 'project:package:${package.id}',
            title: title,
            rows: rows,
          ),
        );
      }
    }

    final quotations = await projectRef.collection('externalQuotations').get();
    if (quotations.docs.isNotEmpty) {
      schedules.add(
        _WorkbookCostSheet(
          key: 'project:externalQuotations',
          title: 'External quotations',
          rows:
              quotations.docs.map((doc) {
                final data = doc.data();
                final effective = _num(data['effectiveAmount']);
                final approved = _num(data['approvedAmount']);
                final assessed = _num(data['assessedAmount']);
                final quoted = _num(data['quotedAmount']);
                final amount =
                    effective > 0
                        ? effective
                        : approved > 0
                        ? approved
                        : assessed > 0
                        ? assessed
                        : quoted;
                return _WorkbookCostRow(
                  code: _firstText(data, ['reference', 'code']),
                  description: _firstText(data, [
                    'title',
                    'contractorName',
                    'supplierName',
                    'description',
                  ]),
                  unit: 'Item',
                  quantity: 1,
                  rate: amount,
                  amount: amount,
                );
              }).toList(),
        ),
      );
    }

    final sites = await projectRef.collection('sites').get();
    for (final site in sites.docs.where(
      (doc) => doc.data()['isDeleted'] != true,
    )) {
      final items = await site.reference.collection('generalAllowances').get();
      if (items.docs.isEmpty) continue;
      final siteName = _s(site.data()['name']).trim();
      final grouped = <String, List<_WorkbookCostRow>>{};
      for (final doc in items.docs) {
        final data = doc.data();
        if (data['includedInTotal'] == false) continue;
        if (_s(data['rowType']).toLowerCase() == 'subheading') continue;
        final rawCategory = _s(data['category']).trim();
        final category =
            rawCategory.isEmpty ? 'Other shared site costs' : rawCategory;
        grouped.putIfAbsent(category, () => <_WorkbookCostRow>[]).add(
          allowanceRow(data),
        );
      }
      final categories = grouped.keys.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      for (final category in categories) {
        final rows = grouped[category]!;
        if (rows.isEmpty) continue;
        schedules.add(
          _WorkbookCostSheet(
            key: 'site:${site.id}:$category',
            title: '$siteName - $category',
            rows: rows,
            siteName: siteName,
            costType: category,
          ),
        );
      }
    }
    return schedules;
  }

  String _uniqueExcelSheetName(String rawName, Set<String> usedNames) {
    var base =
        rawName
            .replaceAll(RegExp(r"[\\/:*?\[\]']"), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    if (base.isEmpty) base = 'Building BOQ';
    if (base.length > 31) base = base.substring(0, 31).trim();
    var candidate = base;
    var suffix = 2;
    while (usedNames.contains(candidate.toLowerCase())) {
      final tail = ' ($suffix)';
      final headLength = 31 - tail.length;
      final cutAt = base.length < headLength ? base.length : headLength;
      candidate = '${base.substring(0, cutAt).trim()}$tail';
      suffix++;
    }
    usedNames.add(candidate.toLowerCase());
    return candidate;
  }

  Future<void> _downloadBuildingPdf(
    _ReportData report,
    _BuildingReportData building,
  ) async {
    await _runBuildingExport(building.id, () async {
      final document = PdfDocument();
      document.pageSettings.margins.all = 34;
      final logo = await rootBundle.load('assets/images/logo.png');
      _appendBuildingTakeoffSummary(
        document,
        report,
        building,
        logo.buffer.asUint8List(),
      );

      final bytes = Uint8List.fromList(await document.save());
      document.dispose();
      final safeName = '${report.projectName}_${building.name}'
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .replaceAll(' ', '_');
      await FileSaver.instance.saveFile(
        name: 'Takeoff_Summary_$safeName',
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${building.name} take-off summary downloaded.')),
      );
    });
  }

  Future<void> _downloadCombinedPdfReports(
    _ReportData report,
    List<_BuildingReportData> buildings,
  ) async {
    if (_exportingCombinedPdf || buildings.isEmpty) return;
    setState(() => _exportingCombinedPdf = true);
    try {
      final document = PdfDocument();
      document.pageSettings.margins.all = 34;
      final logo = await rootBundle.load('assets/images/logo.png');
      final logoBytes = logo.buffer.asUint8List();

      for (final building in buildings) {
        _appendBuildingTakeoffSummary(
          document,
          report,
          building,
          logoBytes,
        );
      }

      final bytes = Uint8List.fromList(await document.save());
      document.dispose();
      final safeName = report.projectName
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .replaceAll(' ', '_');
      await FileSaver.instance.saveFile(
        name: 'Takeoff_Summaries_$safeName',
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${buildings.length} take-off summaries downloaded in one PDF.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF reports download failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _exportingCombinedPdf = false);
    }
  }

  void _appendBuildingTakeoffSummary(
    PdfDocument document,
    _ReportData report,
    _BuildingReportData building,
    Uint8List logoBytes,
  ) {
    final dark = PdfColor(16, 24, 40);
    final blue = PdfColor(21, 94, 239);
    final muted = PdfColor(102, 112, 133);
    final paleBlue = PdfColor(239, 244, 255);
    final quantity = NumberFormat('#,##0.###');
    final page = document.pages.add();
    final bounds = page.getClientSize();
    final siteName = _siteNameForBuilding(report, building);
    final percent = (building.progress * 100).round();

    page.graphics.drawImage(
      PdfBitmap(logoBytes),
      const Rect.fromLTWH(0, 0, 42, 42),
    );
    page.graphics.drawString(
      'AQS Auto BOQ - Take-off Summary Report',
      PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold),
      brush: PdfSolidBrush(dark),
      bounds: const Rect.fromLTWH(54, 2, 430, 22),
    );
    page.graphics.drawString(
      report.projectName,
      PdfStandardFont(PdfFontFamily.helvetica, 10),
      brush: PdfSolidBrush(muted),
      bounds: const Rect.fromLTWH(54, 27, 430, 16),
    );
    page.graphics.drawLine(
      PdfPen(blue, width: 2),
      const Offset(0, 56),
      Offset(bounds.width, 56),
    );

    final info = PdfGrid();
    info.columns.add(count: 4);
    final infoRows = <List<String>>[
      ['Site', siteName, 'Building', building.name],
      ['Take-off progress', '$percent%', 'BOQ items measured', '${building.measuredBoqItemCount}/${building.boqItemCount}'],
      ['Measurements', '${building.measurementCount}', 'Report date', DateFormat('dd MMMM yyyy').format(DateTime.now())],
    ];
    for (final values in infoRows) {
      final row = info.rows.add();
      for (var i = 0; i < values.length; i++) {
        row.cells[i].value = values[i];
      }
      row.cells[0].style.backgroundBrush = PdfSolidBrush(paleBlue);
      row.cells[2].style.backgroundBrush = PdfSolidBrush(paleBlue);
      row.cells[0].style.font = PdfStandardFont(
        PdfFontFamily.helvetica,
        8,
        style: PdfFontStyle.bold,
      );
      row.cells[2].style.font = PdfStandardFont(
        PdfFontFamily.helvetica,
        8,
        style: PdfFontStyle.bold,
      );
    }
    info.columns[0].width = 88;
    info.columns[1].width = 165;
    info.columns[2].width = 96;
    info.columns[3].width = 168;
    info.style = PdfGridStyle(
      cellPadding: PdfPaddings(left: 5, right: 5, top: 6, bottom: 6),
      font: PdfStandardFont(PdfFontFamily.helvetica, 8),
    );
    final infoResult = info.draw(
      page: page,
      bounds: Rect.fromLTWH(0, 70, bounds.width, 0),
    )!;

    var currentPage = infoResult.page;
    var nextY = infoResult.bounds.bottom + 18;
    currentPage.graphics.drawString(
      '1. Take-off progress by work section',
      PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold),
      brush: PdfSolidBrush(dark),
      bounds: Rect.fromLTWH(0, nextY, currentPage.getClientSize().width, 18),
    );
    nextY += 22;

    final sectionGrid = PdfGrid();
    sectionGrid.columns.add(count: 5);
    sectionGrid.headers.add(1);
    const sectionHeadings = ['Work section', 'BOQ items', 'Measured', 'Not measured', 'Progress'];
    for (var i = 0; i < sectionHeadings.length; i++) {
      sectionGrid.headers[0].cells[i].value = sectionHeadings[i];
    }
    for (final summary in _takeoffSectionSummaries(building)) {
      final row = sectionGrid.rows.add();
      row.cells[0].value = summary.section;
      row.cells[1].value = summary.totalItems.toString();
      row.cells[2].value = summary.measuredItems.toString();
      row.cells[3].value = summary.pendingItems.toString();
      row.cells[4].value = '${summary.progressPercent}%';
    }
    sectionGrid.columns[0].width = 267;
    sectionGrid.columns[1].width = 62;
    sectionGrid.columns[2].width = 62;
    sectionGrid.columns[3].width = 62;
    sectionGrid.columns[4].width = 64;
    _stylePdfGrid(sectionGrid, blue);
    final sectionResult = sectionGrid.draw(
      page: currentPage,
      bounds: Rect.fromLTWH(0, nextY, currentPage.getClientSize().width, 0),
    )!;

    currentPage = sectionResult.page;
    nextY = sectionResult.bounds.bottom + 18;
    if (nextY > currentPage.getClientSize().height - 90) {
      currentPage = document.pages.add();
      nextY = 20;
    }
    currentPage.graphics.drawString(
      '2. Measured quantity summary',
      PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold),
      brush: PdfSolidBrush(dark),
      bounds: Rect.fromLTWH(0, nextY, currentPage.getClientSize().width, 18),
    );
    nextY += 22;

    final measuredGrid = PdfGrid();
    measuredGrid.columns.add(count: 5);
    measuredGrid.headers.add(1);
    const measuredHeadings = ['Work section', 'BOQ code', 'Description', 'Unit', 'Quantity'];
    for (var i = 0; i < measuredHeadings.length; i++) {
      measuredGrid.headers[0].cells[i].value = measuredHeadings[i];
    }
    final measuredLines = building.boqLines.where((line) => line.quantity > 0).toList();
    for (final line in measuredLines) {
      final row = measuredGrid.rows.add();
      row.cells[0].value = _pdfText(line.item.section);
      row.cells[1].value = _pdfText(line.item.code);
      row.cells[2].value = _pdfText(line.item.description);
      row.cells[3].value = _pdfText(line.item.unit);
      row.cells[4].value = quantity.format(line.quantity);
    }
    measuredGrid.columns[0].width = 110;
    measuredGrid.columns[1].width = 65;
    measuredGrid.columns[2].width = 245;
    measuredGrid.columns[3].width = 42;
    measuredGrid.columns[4].width = 55;
    _stylePdfGrid(measuredGrid, blue);
    final measuredResult = measuredGrid.draw(
      page: currentPage,
      bounds: Rect.fromLTWH(0, nextY, currentPage.getClientSize().width, 0),
    )!;

    final pendingLines = building.boqLines.where((line) => line.quantity <= 0).toList();
    currentPage = measuredResult.page;
    nextY = measuredResult.bounds.bottom + 18;
    if (nextY > currentPage.getClientSize().height - 110) {
      currentPage = document.pages.add();
      nextY = 20;
    }
    currentPage.graphics.drawString(
      '3. Items with no measured quantity',
      PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold),
      brush: PdfSolidBrush(dark),
      bounds: Rect.fromLTWH(0, nextY, currentPage.getClientSize().width, 18),
    );
    nextY += 22;

    if (pendingLines.isEmpty) {
      currentPage.graphics.drawString(
        'No pending BOQ items are shown in the current take-off.',
        PdfStandardFont(PdfFontFamily.helvetica, 9),
        brush: PdfSolidBrush(muted),
        bounds: Rect.fromLTWH(0, nextY, currentPage.getClientSize().width, 34),
      );
      nextY += 38;
    } else {
      final pendingGrid = PdfGrid();
      pendingGrid.columns.add(count: 4);
      pendingGrid.headers.add(1);
      const pendingHeadings = ['Work section', 'BOQ code', 'Description', 'Unit'];
      for (var i = 0; i < pendingHeadings.length; i++) {
        pendingGrid.headers[0].cells[i].value = pendingHeadings[i];
      }
      for (final line in pendingLines) {
        final row = pendingGrid.rows.add();
        row.cells[0].value = _pdfText(line.item.section);
        row.cells[1].value = _pdfText(line.item.code);
        row.cells[2].value = _pdfText(line.item.description);
        row.cells[3].value = _pdfText(line.item.unit);
      }
      pendingGrid.columns[0].width = 120;
      pendingGrid.columns[1].width = 70;
      pendingGrid.columns[2].width = 285;
      pendingGrid.columns[3].width = 42;
      _stylePdfGrid(pendingGrid, blue);
      final pendingResult = pendingGrid.draw(
        page: currentPage,
        bounds: Rect.fromLTWH(0, nextY, currentPage.getClientSize().width, 0),
      )!;
      currentPage = pendingResult.page;
      nextY = pendingResult.bounds.bottom + 18;
    }

    if (nextY > currentPage.getClientSize().height - 105) {
      currentPage = document.pages.add();
      nextY = 20;
    }
    currentPage.graphics.drawString(
      '4. Measurement notes',
      PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold),
      brush: PdfSolidBrush(dark),
      bounds: Rect.fromLTWH(0, nextY, currentPage.getClientSize().width, 18),
    );
    nextY += 22;
    final note = building.progress >= 0.999
        ? 'The take-off summary reflects the quantities recorded in AQS for the current building. All BOQ items currently show measured quantities.'
        : 'The take-off summary reflects the quantities recorded in AQS to date. Items shown with no measured quantity require review or confirmation before the take-off is treated as complete.';
    currentPage.graphics.drawString(
      note,
      PdfStandardFont(PdfFontFamily.helvetica, 9),
      brush: PdfSolidBrush(muted),
      bounds: Rect.fromLTWH(0, nextY, currentPage.getClientSize().width, 54),
      format: PdfStringFormat(lineSpacing: 2),
    );
  }

  void _stylePdfGrid(PdfGrid grid, PdfColor headerColor) {
    grid.style = PdfGridStyle(
      cellPadding: PdfPaddings(left: 5, right: 5, top: 5, bottom: 5),
      font: PdfStandardFont(PdfFontFamily.helvetica, 7.5),
    );
    grid.headers[0].style = PdfGridRowStyle(
      backgroundBrush: PdfSolidBrush(headerColor),
      textBrush: PdfBrushes.white,
      font: PdfStandardFont(
        PdfFontFamily.helvetica,
        7.5,
        style: PdfFontStyle.bold,
      ),
    );
  }

  List<_TakeoffSectionSummary> _takeoffSectionSummaries(
    _BuildingReportData building,
  ) {
    final grouped = <String, List<_BuildingBoqLine>>{};
    for (final line in building.boqLines) {
      final section = line.item.section.trim().isEmpty
          ? 'General / Unclassified'
          : line.item.section.trim();
      grouped.putIfAbsent(section, () => <_BuildingBoqLine>[]).add(line);
    }
    return grouped.entries.map((entry) {
      final measured = entry.value.where((line) => line.quantity > 0).length;
      return _TakeoffSectionSummary(
        section: entry.key,
        totalItems: entry.value.length,
        measuredItems: measured,
      );
    }).toList();
  }

  String _siteNameForBuilding(
    _ReportData report,
    _BuildingReportData building,
  ) {
    for (final site in report.sites) {
      if (site.id == building.siteId) return site.name;
    }
    return building.siteId.isEmpty ? 'Not assigned' : 'Unassigned / Other';
  }

  Future<void> _runBuildingExport(
    String buildingId,
    Future<void> Function() action,
  ) async {
    if (_exportingBuildingIds.contains(buildingId)) return;
    setState(() => _exportingBuildingIds.add(buildingId));
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Report download failed: $error')));
    } finally {
      if (mounted) setState(() => _exportingBuildingIds.remove(buildingId));
    }
  }

  String _pdfText(String value) =>
      value.replaceAll('²', '2').replaceAll('³', '3');

  String _rowType(dynamic v) {
    final text = _s(v).toLowerCase();
    return text.isEmpty ? 'item' : text;
  }

  String _key(dynamic v) => _s(v).replaceAll(RegExp(r'\s+'), '').toLowerCase();

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? 0;
  }

  String _firstText(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = _s(data[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _sectionLabelForBoqRow(
    Map<String, dynamic> row,
    List<Map<String, dynamic>> allRows,
  ) {
    double orderOf(Map<String, dynamic> value) =>
        value['order'] is num
            ? (value['order'] as num).toDouble()
            : double.tryParse('${value['order']}') ?? double.infinity;
    String descriptionOf(Map<String, dynamic> value) {
      final description = _s(value['description']);
      if (description.isNotEmpty) return description;
      final boqDescription = _s(value['boqDescription']);
      if (boqDescription.isNotEmpty) return boqDescription;
      final code = _s(value['boqCode']);
      return code.isEmpty ? 'General' : code;
    }

    final targetOrder = orderOf(row);
    final targetStructure = _s(row['structure']);
    String bill = '';
    String subheading = '';
    final sorted = List<Map<String, dynamic>>.from(allRows)
      ..sort((a, b) => orderOf(a).compareTo(orderOf(b)));
    for (final candidate in sorted) {
      if (orderOf(candidate) > targetOrder) break;
      final candidateStructure = _s(candidate['structure']);
      if (targetStructure.isNotEmpty &&
          candidateStructure.isNotEmpty &&
          candidateStructure != targetStructure) {
        continue;
      }
      final rowType = _rowType(candidate['rowType']);
      if (rowType == 'bill') {
        bill = descriptionOf(candidate);
        subheading = '';
      } else if (rowType == 'subheading') {
        subheading = descriptionOf(candidate);
      }
    }
    return subheading.isNotEmpty ? subheading : (bill.isNotEmpty ? bill : 'General');
  }

  String _measurementTitle(Map<String, dynamic> data) {
    final label = _s(data['label']);
    if (label.isNotEmpty) return label;
    final member = _s(data['memberTypeLabel']);
    if (member.isNotEmpty) return member;
    final boq = _s(data['boqDescription']);
    if (boq.isNotEmpty) return boq;
    final type = _s(data['measureType']);
    return type.isEmpty ? 'Measurement' : type;
  }
}

class _ReportsHero extends StatelessWidget {
  const _ReportsHero({
    required this.projects,
    required this.selectedProjectId,
    required this.onProjectChanged,
    required this.onRefresh,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> projects;
  final String selectedProjectId;
  final ValueChanged<String> onProjectChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AqsColors.primaryDark, Color(0xFF155EEF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22155EEF),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Reports center',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Review BOQ value, measured quantities, unmeasured items, and audit trail.',
                style: TextStyle(color: Color(0xFFD6E4FF), height: 1.45),
              ),
            ],
          );
          final selector = SizedBox(
            width: compact ? constraints.maxWidth : 480,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedProjectId,
                        isExpanded: true,
                        items:
                            projects.map((project) {
                              final name =
                                  (project.data()['name'] ?? 'Project')
                                      .toString();
                              return DropdownMenuItem(
                                value: project.id,
                                child: Text(
                                  name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                        onChanged: (id) {
                          if (id != null) onProjectChanged(id);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  onPressed: onRefresh,
                  tooltip: 'Refresh report figures',
                  icon: const Icon(Icons.refresh_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AqsColors.primary,
                  ),
                ),
              ],
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [title, const SizedBox(height: 18), selector],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 18),
              selector,
            ],
          );
        },
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.data});

  final _ReportData data;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    final cards = [
      _KpiData(
        label: 'Sites cost',
        value: '${data.currency} ${money.format(data.sitesCost)}',
        icon: Icons.location_city_outlined,
        color: AqsColors.primary,
      ),
      _KpiData(
        label: 'Shared project costs',
        value: '${data.currency} ${money.format(data.sharedProjectCosts)}',
        icon: Icons.hub_outlined,
        color: const Color(0xFF7C3AED),
      ),
      _KpiData(
        label: 'Total project cost',
        value: '${data.currency} ${money.format(data.projectValue)}',
        icon: Icons.payments_outlined,
        color: const Color(0xFF047857),
      ),
      _KpiData(
        label: 'Take-off progress',
        value:
            data.boqItemCount == 0
                ? '0%'
                : '${(data.measuredBoqItemCount / data.boqItemCount * 100).round()}%',
        icon: Icons.check_circle_outline_rounded,
        color: const Color(0xFF0E7490),
      ),
      _KpiData(
        label: 'Measured BOQ items',
        value: '${data.measuredBoqItemCount}/${data.boqItemCount}',
        icon: Icons.straighten_rounded,
        color: const Color(0xFFEA580C),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final phone = constraints.maxWidth < 520;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: phone ? 1 : (compact ? 2 : 5),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: phone ? 104 : (compact ? 126 : 116),
          ),
          itemBuilder: (_, i) => _KpiCard(data: cards[i]),
        );
      },
    );
  }
}

class _SiteReportSection extends StatelessWidget {
  const _SiteReportSection({
    required this.data,
    required this.selectedSiteId,
    required this.onSiteChanged,
    required this.buildings,
    required this.exportingWorkbook,
    required this.exportingPdf,
    required this.onDownload,
    required this.onDownloadReports,
  });

  final _ReportData data;
  final String? selectedSiteId;
  final ValueChanged<String?> onSiteChanged;
  final List<_BuildingReportData> buildings;
  final bool exportingWorkbook;
  final bool exportingPdf;
  final Future<void> Function(List<_BuildingReportData> buildings) onDownload;
  final Future<void> Function(List<_BuildingReportData> buildings)
  onDownloadReports;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    final activeSiteId =
        data.sites.any((site) => site.id == selectedSiteId)
            ? selectedSiteId
            : null;
    return _SectionCard(
      title: 'Site progress',
      subtitle:
          'Choose a site to focus the building reports, or view the complete project.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 300,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(activeSiteId ?? '__all__'),
                  initialValue: activeSiteId ?? '__all__',
                  decoration: const InputDecoration(
                    labelText: 'Report scope',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.filter_alt_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '__all__',
                      child: Text('All sites'),
                    ),
                    for (final site in data.sites)
                      DropdownMenuItem(value: site.id, child: Text(site.name)),
                  ],
                  onChanged:
                      (value) =>
                          onSiteChanged(value == '__all__' ? null : value),
                ),
              ),
              FilledButton.icon(
                onPressed:
                    !buildings.any((building) => building.boqItemCount > 0) ||
                            exportingWorkbook
                        ? null
                        : () => onDownload(buildings),
                icon:
                    exportingWorkbook
                        ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(Icons.file_download_outlined),
                label: Text(
                  exportingWorkbook
                      ? 'Creating workbook...'
                      : activeSiteId == null
                      ? 'Download project BOQs'
                      : 'Download site BOQs',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed:
                    !buildings.any((building) => building.boqItemCount > 0) ||
                            exportingPdf
                        ? null
                        : () => onDownloadReports(buildings),
                icon:
                    exportingPdf
                        ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(
                  exportingPdf
                      ? 'Creating reports...'
                      : activeSiteId == null
                      ? 'Download project reports'
                      : 'Download site reports',
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (data.sites.isEmpty)
            const _MutedText('This project has no configured sites yet.')
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    constraints.maxWidth >= 1050
                        ? 3
                        : constraints.maxWidth >= 650
                        ? 2
                        : 1;
                const gap = 12.0;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final site in data.sites)
                      SizedBox(
                        width: width,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => onSiteChanged(site.id),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color:
                                  activeSiteId == site.id
                                      ? const Color(0xFFEFF4FF)
                                      : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color:
                                    activeSiteId == site.id
                                        ? AqsColors.primary
                                        : AqsColors.border,
                                width: activeSiteId == site.id ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.location_city_outlined,
                                      color: AqsColors.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        site.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${(site.progress * 100).round()}%',
                                      style: const TextStyle(
                                        color: AqsColors.primary,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                LinearProgressIndicator(
                                  value: site.progress,
                                  minHeight: 7,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                const SizedBox(height: 12),
                                Text('${site.buildingCount} buildings'),
                                Text(
                                  'Building works: ${data.currency} ${money.format(site.buildingWorksValue)}',
                                ),
                                Text(
                                  'Shared site costs: ${data.currency} ${money.format(site.sharedSiteCosts)}',
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Site total: ${data.currency} ${money.format(site.totalValue)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SharedCostsReportSection extends StatefulWidget {
  const _SharedCostsReportSection({required this.data});

  final _ReportData data;

  @override
  State<_SharedCostsReportSection> createState() =>
      _SharedCostsReportSectionState();
}

class _SharedCostsReportSectionState extends State<_SharedCostsReportSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    return _SectionCard(
      title: 'Shared project costs',
      subtitle:
          'Costs used by the whole project and counted once in the total project cost.',
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final mobile = constraints.maxWidth < 520;
              final amount =
                  '${widget.data.currency} ${money.format(widget.data.sharedProjectCosts)}';
              if (!mobile) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE8F0FF),
                    child: Icon(Icons.hub_outlined, color: AqsColors.primary),
                  ),
                  title: const Text(
                    'Shared costs total',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${widget.data.sharedCosts.length} active cost categories',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        amount,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                      ),
                    ],
                  ),
                  onTap: () => setState(() => _expanded = !_expanded),
                );
              }
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xFFE8F0FF),
                        child: Icon(
                          Icons.hub_outlined,
                          color: AqsColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Shared costs total',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${widget.data.sharedCosts.length} active cost categories',
                              style: const TextStyle(color: AqsColors.muted),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              amount,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_expanded) ...[
            const Divider(),
            if (widget.data.sharedCosts.isEmpty)
              const _MutedText('No shared project costs have been added.')
            else
              for (final cost in widget.data.sharedCosts)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final mobile = constraints.maxWidth < 520;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(cost.icon, color: AqsColors.primary),
                      title: Text(cost.label),
                      subtitle: Text(
                        '${cost.itemCount} ${cost.itemCount == 1 ? 'item' : 'items'}${mobile ? '\n${widget.data.currency} ${money.format(cost.value)}' : ''}',
                      ),
                      isThreeLine: mobile,
                      trailing:
                          mobile
                              ? null
                              : Text(
                                '${widget.data.currency} ${money.format(cost.value)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                    );
                  },
                ),
          ],
        ],
      ),
    );
  }
}

class _BuildingProgressSection extends StatelessWidget {
  const _BuildingProgressSection({
    required this.data,
    required this.buildings,
    required this.selectedSiteName,
    required this.exportingBuildingIds,
    required this.onExcel,
    required this.onPdf,
  });

  final _ReportData data;
  final List<_BuildingReportData> buildings;
  final String? selectedSiteName;
  final Set<String> exportingBuildingIds;
  final Future<void> Function(_BuildingReportData building) onExcel;
  final Future<void> Function(_BuildingReportData building) onPdf;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    return _SectionCard(
      title:
          selectedSiteName == null
              ? 'Building take-off progress'
              : 'Buildings · $selectedSiteName',
      subtitle:
          'Review measurement coverage and download an Excel BOQ or take-off summary PDF for each building.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (buildings.isEmpty)
            const _MutedText('No buildings are available for this selection.')
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    constraints.maxWidth >= 1120
                        ? 3
                        : constraints.maxWidth >= 700
                        ? 2
                        : 1;
                const gap = 12.0;
                final cardWidth =
                    (constraints.maxWidth - (gap * (columns - 1))) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children:
                      buildings.map((building) {
                        final busy = exportingBuildingIds.contains(building.id);
                        final percent = (building.progress * 100).round();
                        return SizedBox(
                          width: cardWidth,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AqsColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE8F0FF),
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                      child: const Icon(
                                        Icons.apartment_rounded,
                                        color: AqsColors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        building.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AqsColors.ink,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '$percent%',
                                      style: const TextStyle(
                                        color: AqsColors.primary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: building.progress,
                                    minHeight: 8,
                                    backgroundColor: const Color(0xFFE2E8F0),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                          AqsColors.primary,
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '${building.measuredBoqItemCount} of ${building.boqItemCount} BOQ items measured',
                                  style: const TextStyle(
                                    color: AqsColors.muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _BuildingMetric(
                                        label: 'Measurements',
                                        value:
                                            building.measurementCount
                                                .toString(),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _BuildingMetric(
                                        label: 'Measured value',
                                        value:
                                            '${data.currency} ${money.format(building.value)}',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                if (busy)
                                  const SizedBox(
                                    height: 42,
                                    child: Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => onExcel(building),
                                          icon: const Icon(
                                            Icons.table_view_outlined,
                                            size: 18,
                                          ),
                                          label: const Text('Excel BOQ'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: () => onPdf(building),
                                          icon: const Icon(
                                            Icons.picture_as_pdf_outlined,
                                            size: 18,
                                          ),
                                          label: const Text('PDF report'),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _BuildingMetric extends StatelessWidget {
  const _BuildingMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AqsColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AqsColors.muted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _AvailableReports extends StatelessWidget {
  const _AvailableReports({required this.data});

  final _ReportData data;

  @override
  Widget build(BuildContext context) {
    final reports = [
      (
        'BOQ Bills Summary',
        'Financial view of BOQ value and bill distribution.',
      ),
      ('Measurement Summary', 'Quantities grouped by BOQ item and building.'),
      ('Unmeasured BOQ Items', 'Items that still have no measured quantity.'),
      ('Measurement Audit Trail', 'Recent measurements with date and source.'),
    ];
    return _SectionCard(
      title: 'Available reports',
      subtitle: 'First report set for review and export preparation.',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children:
            reports
                .map(
                  (r) => Container(
                    width: 260,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AqsColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.analytics_outlined,
                          color: AqsColors.primary,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          r.$1,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          r.$2,
                          style: const TextStyle(
                            color: AqsColors.muted,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
      ),
    );
  }
}

class _MeasurementSummary extends StatelessWidget {
  const _MeasurementSummary({required this.data});

  final _ReportData data;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    return _SectionCard(
      title: 'Measurement summary by BOQ item',
      subtitle: 'Measured quantities and calculated BOQ value.',
      child:
          data.measuredSummaries.isEmpty
              ? const _MutedText('No measured BOQ items yet.')
              : Column(
                children:
                    data.measuredSummaries.take(10).map((item) {
                      return _ReportRow(
                        title: '${item.code}  ${item.description}',
                        subtitle:
                            '${item.buildingName} • ${item.quantity.toStringAsFixed(3)} ${item.unit}',
                        trailing:
                            '${data.currency} ${money.format(item.amount)}',
                      );
                    }).toList(),
              ),
    );
  }
}

class _UnmeasuredItems extends StatelessWidget {
  const _UnmeasuredItems({required this.data});

  final _ReportData data;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Unmeasured BOQ items',
      subtitle: 'BOQ items with no linked measured quantity.',
      child:
          data.unmeasuredItems.isEmpty
              ? const _MutedText('All BOQ items have measured quantities.')
              : Column(
                children:
                    data.unmeasuredItems.take(10).map((item) {
                      return _ReportRow(
                        title: '${item.code}  ${item.description}',
                        subtitle: '${item.buildingName} • ${item.unit}',
                        trailing: 'Pending',
                      );
                    }).toList(),
              ),
    );
  }
}

class _AuditTrail extends StatelessWidget {
  const _AuditTrail({required this.data});

  final _ReportData data;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd MMM yyyy, HH:mm');
    return _SectionCard(
      title: 'Measurement audit trail',
      subtitle: 'Latest saved measurements for this project.',
      child:
          data.recentMeasurements.isEmpty
              ? const _MutedText('No measurement activity yet.')
              : Column(
                children:
                    data.recentMeasurements.map((item) {
                      return _ReportRow(
                        title: item.title,
                        subtitle: item.auditSubtitle,
                        trailing:
                            item.createdAt == null
                                ? 'No date'
                                : date.format(item.createdAt!),
                      );
                    }).toList(),
              ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AqsColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08101828),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AqsColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: AqsColors.muted)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ReportsLoadingState extends StatelessWidget {
  const _ReportsLoadingState({required this.projectName});

  final String projectName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AqsColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08101828),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 42,
            height: 42,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading reports for $projectName',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AqsColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Calculating BOQ values, measured items, unmeasured items, and audit trail.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AqsColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _ReportsErrorState extends StatelessWidget {
  const _ReportsErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF991B1B), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AqsColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AqsColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            trailing,
            style: const TextStyle(
              color: AqsColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});

  final _KpiData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: data.color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(data.icon, color: data.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.value,
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(
                    color: AqsColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data.label,
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(
                    color: AqsColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(color: AqsColors.muted));
  }
}

class _EmptyReportsState extends StatelessWidget {
  const _EmptyReportsState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No accessible projects found for reports.',
        style: TextStyle(color: AqsColors.muted),
      ),
    );
  }
}

class _KpiData {
  const _KpiData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _ReportData {
  const _ReportData({
    required this.projectId,
    required this.projectName,
    required this.currency,
    required this.buildingCount,
    required this.boqItemCount,
    required this.measurementCount,
    required this.measuredBoqItemCount,
    required this.projectValue,
    required this.sitesCost,
    required this.sharedProjectCosts,
    required this.measuredSummaries,
    required this.unmeasuredItems,
    required this.recentMeasurements,
    required this.buildings,
    required this.sites,
    required this.sharedCosts,
  });

  final String projectId;
  final String projectName;
  final String currency;
  final int buildingCount;
  final int boqItemCount;
  final int measurementCount;
  final int measuredBoqItemCount;
  final double projectValue;
  final double sitesCost;
  final double sharedProjectCosts;
  final List<_MeasuredBoqSummary> measuredSummaries;
  final List<_BoqReportItem> unmeasuredItems;
  final List<_MeasurementReportItem> recentMeasurements;
  final List<_BuildingReportData> buildings;
  final List<_SiteReportData> sites;
  final List<_SharedCostReportData> sharedCosts;
}

class _BoqReportItem {
  const _BoqReportItem({
    required this.id,
    required this.buildingId,
    required this.buildingName,
    required this.code,
    required this.matchingCodes,
    required this.description,
    required this.section,
    required this.unit,
    required this.rate,
    required this.order,
    required this.qtyOverride,
  });

  final String id;
  final String buildingId;
  final String buildingName;
  final String code;
  final List<String> matchingCodes;
  final String description;
  final String section;
  final String unit;
  final double rate;
  final double order;
  final double? qtyOverride;
}

class _MeasurementReportItem {
  const _MeasurementReportItem({
    required this.id,
    required this.buildingId,
    required this.buildingName,
    required this.boqItemId,
    required this.boqCode,
    required this.boqCodes,
    required this.title,
    required this.unit,
    required this.value,
    required this.createdAt,
    required this.actorName,
    required this.actorUid,
  });

  final String id;
  final String buildingId;
  final String buildingName;
  final String boqItemId;
  final String boqCode;
  final List<String> boqCodes;
  final String title;
  final String unit;
  final double value;
  final DateTime? createdAt;
  final String actorName;
  final String actorUid;

  String get auditSubtitle {
    final parts = [
      buildingName,
      'BOQ ${boqCode.isEmpty ? '-' : boqCode}',
      if (actorName.isNotEmpty) 'By $actorName',
      if (actorUid.isNotEmpty) 'UID: $actorUid',
    ];
    return parts.where((part) => part.trim().isNotEmpty).join(' • ');
  }
}

class _BuildingBoqLine {
  const _BuildingBoqLine({
    required this.item,
    required this.quantity,
    required this.amount,
  });

  final _BoqReportItem item;
  final double quantity;
  final double amount;
}

class _BuildingReportData {
  const _BuildingReportData({
    required this.id,
    required this.name,
    required this.siteId,
    required this.boqItemCount,
    required this.measuredBoqItemCount,
    required this.measurementCount,
    required this.value,
    required this.allowanceValue,
    required this.boqLines,
  });

  final String id;
  final String name;
  final String siteId;
  final int boqItemCount;
  final int measuredBoqItemCount;
  final int measurementCount;
  final double value;
  final double allowanceValue;
  final List<_BuildingBoqLine> boqLines;

  double get progress =>
      boqItemCount == 0 ? 0 : measuredBoqItemCount / boqItemCount;

  double get totalValue => value + allowanceValue;
}

class _TakeoffSectionSummary {
  const _TakeoffSectionSummary({
    required this.section,
    required this.totalItems,
    required this.measuredItems,
  });

  final String section;
  final int totalItems;
  final int measuredItems;

  int get pendingItems => totalItems - measuredItems;
  int get progressPercent =>
      totalItems == 0 ? 0 : (measuredItems / totalItems * 100).round();
}

class _SiteReportData {
  const _SiteReportData({
    required this.id,
    required this.name,
    required this.buildingCount,
    required this.buildingWorksValue,
    required this.sharedSiteCosts,
    required this.boqItemCount,
    required this.measuredBoqItemCount,
  });

  final String id;
  final String name;
  final int buildingCount;
  final double buildingWorksValue;
  final double sharedSiteCosts;
  final int boqItemCount;
  final int measuredBoqItemCount;

  double get totalValue => buildingWorksValue + sharedSiteCosts;
  double get progress =>
      boqItemCount == 0 ? 0 : measuredBoqItemCount / boqItemCount;
}

class _SharedCostReportData {
  const _SharedCostReportData({
    required this.label,
    required this.itemCount,
    required this.value,
    required this.icon,
  });

  final String label;
  final int itemCount;
  final double value;
  final IconData icon;
}

class _WorkbookCostSheet {
  const _WorkbookCostSheet({
    required this.key,
    required this.title,
    required this.rows,
    this.siteName = '',
    this.costType = '',
  });

  final String key;
  final String title;
  final List<_WorkbookCostRow> rows;
  final String siteName;
  final String costType;

  double get total => rows.fold<double>(0, (value, row) => value + row.amount);
}

class _WorkbookCostRow {
  const _WorkbookCostRow({
    required this.code,
    required this.description,
    required this.unit,
    required this.quantity,
    required this.rate,
    required this.amount,
  });

  final String code;
  final String description;
  final String unit;
  final double quantity;
  final double rate;
  final double amount;
}

class _MeasuredBoqSummary {
  const _MeasuredBoqSummary({
    required this.code,
    required this.description,
    required this.buildingName,
    required this.unit,
    required this.quantity,
    required this.amount,
  });

  final String code;
  final String description;
  final String buildingName;
  final String unit;
  final double quantity;
  final double amount;
}
