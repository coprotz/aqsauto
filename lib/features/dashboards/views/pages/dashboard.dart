import 'dart:async';
import 'dart:math';

import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/billing/services/subscription_service.dart';
import 'package:aqs/features/dashboards/components/pagenation_card.dart';
import 'package:aqs/features/dashboards/components/stage_pill.dart';
import 'package:aqs/features/dashboards/components/updrade_card.dart';
import 'package:aqs/features/dashboards/components/welcom_bannner.dart';
import 'package:aqs/features/dashboards/models/project_row_fs.dart';
import 'package:aqs/features/pricing/views/pricing_plans_page.dart';
import 'package:aqs/features/subscription/pages/pricing_plans_page.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../utils/enum.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({
    super.key,
    required TextEditingController search,
    required User user,
    this.fullRegister = false,
    this.onViewAllProjects,
  }) : _search = search,
       _user = user;

  final TextEditingController _search;
  final User _user;
  final bool fullRegister;
  final VoidCallback? onViewAllProjects;

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  String? _selectedDashboardProjectId;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ✅ caches for subcollection counts (so UI doesn’t spam reads on rebuild)
  // final Map<String, int> _drawingsCount = {};
  // final Map<String, int> _boqItemsCount = {};
  // final Map<String, int> _measurementsCount = {};

  Future<void> _handleRowAction(ProjectRowFs row, String action) async {
    final ref = FirebaseFirestore.instance.collection('projects').doc(row.id);

    switch (action) {
      case 'Open Project':
        await ref.set({
          'updatedAt': FieldValue.serverTimestamp(),
          'lastOpenedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        Get.toNamed(AppRoutes.projectBuildingsPath(row.id, row.name));
        // pd.openProject(row as QueryDocumentSnapshot<Map<String, dynamic>>);
        _snack('Open Project: ${row.name}');
        return;

      case 'Start Construction':
        // mark award + move to Progress
        await ref.update({
          'hasContractAward': true,
          'status': 'Progress',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _snack('${row.name}: stage → Progress');
        return;

      case 'Create IPC':
        // increment ipcCount + move to Valuation
        await FirebaseFirestore.instance.runTransaction((tx) async {
          final snap = await tx.get(ref);
          final data = snap.data() ?? {};
          final cur =
              (data['ipcCount'] is num) ? (data['ipcCount'] as num).toInt() : 0;

          tx.update(ref, {
            'hasContractAward': true,
            'ipcCount': cur + 1,
            'status': 'Valuation',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        });
        _snack('${row.name}: IPC created');
        return;

      case 'Verify BOQ':
        await ref.update({
          'status': 'BOQ Verification',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _snack('${row.name}: stage → BOQ Verification');
        return;

      case 'Back to Tender':
        await ref.update({
          'hasContractAward': false,
          'ipcCount': 0,
          'status': 'Tender',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _snack('${row.name}: stage → Tender');
        return;

      case 'Rename':
        {
          final ctl = TextEditingController(text: row.name);
          final newName = await showDialog<String?>(
            context: context,
            builder:
                (ctx) => AlertDialog(
                  title: const Text('Rename project'),
                  content: TextField(
                    controller: ctl,
                    decoration: const InputDecoration(
                      labelText: 'Project name',
                    ),
                    autofocus: true,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, null),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
                      child: const Text('Save'),
                    ),
                  ],
                ),
          );
          ctl.dispose();
          if (newName != null && newName.isNotEmpty) {
            await ref.update({
              'name': newName,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            _snack('Renamed');
          }
          return;
        }

      case 'Archive':
        await ref.update({
          'archived': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _snack('${row.name}: archived');
        return;

      case 'Duplicate':
        {
          final canCreateProject = await SubscriptionService.instance
              .canCreateProject(user: widget._user);
          if (!canCreateProject) {
            _snack(
              'Free plan allows 1 project only. Please subscribe to add more projects.',
            );
            return;
          }

          // Copy project doc only (subcollections are NOT copied here)
          final snap = await ref.get();
          final data = snap.data() ?? {};
          data.remove('createdAt');
          data.remove('updatedAt');

          await FirebaseFirestore.instance.collection('projects').add({
            ...data,
            'name': '${row.name} (Copy)',
            'ipcCount': 0,
            'hasContractAward': false,
            'archived': false,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          _snack('Duplicated (doc only)');
          return;
        }

      case 'Delete':
        // ⚠️ Client apps can’t safely delete subcollections recursively.
        // Best practice: soft delete.
        await ref.update({
          'isDeleted': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _snack('${row.name}: deleted (soft)');
        return;

      default:
        _snack('${row.name}: $action');
    }
  }

  /// ----------- update stage back to Firestore -----------
  Future<void> _changeStage(ProjectRowFs row, ProjectStage newStage) async {
    await FirebaseFirestore.instance.collection('projects').doc(row.id).update({
      'status': stageToStatus(newStage),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, int>> _getCountsForProject(String projectId) async {
    final cached = _countsCacheMap[projectId];
    if (cached != null) return cached;

    final projRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(projectId);
    final buildingsSnap = await projRef.collection('buildings').get();
    final buildingDocs = buildingsSnap.docs;

    int drawingsTotal = 0;
    int measurementsTotal = 0;
    int boqTotal = 0;
    int unmeasuredTotal = 0;

    for (final b in buildingDocs) {
      final bRef = b.reference;

      final drawingsAgg = await bRef.collection('drawings').count().get();
      final measAgg = await bRef.collection('measurements').count().get();

      int boqCount = 0;
      try {
        // The active BOQ workspace writes to `boq`.
        boqCount = (await bRef.collection('boq').count().get()).count!;
      } catch (_) {
        boqCount = 0;
      }

      // Older screens used `boqItems`. An empty collection does not throw, so
      // fallback must be based on the count rather than the catch block.
      if (boqCount == 0) {
        try {
          boqCount = (await bRef.collection('boqItems').count().get()).count!;
        } catch (_) {
          boqCount = 0;
        }
      }

      drawingsTotal += drawingsAgg.count!;
      measurementsTotal += measAgg.count!;
      boqTotal += boqCount;

      final boqDocs =
          (await bRef.collection('boq').get()).docs.isNotEmpty
              ? (await bRef.collection('boq').get()).docs
              : (await bRef.collection('boqItems').get()).docs;
      final measurementDocs = await bRef.collection('measurements').get();
      final measuredKeys = <String>{};
      for (final doc in measurementDocs.docs) {
        final data = doc.data();
        measuredKeys.addAll(
          {
            _key(data['boqCode']),
            _key(data['resolvedBoqCode']),
            _key(data['boqCodeNorm']),
          }..removeWhere((key) => key.isEmpty),
        );
      }
      for (final doc in boqDocs) {
        final data = doc.data();
        if (_rowType(data['rowType']) != 'item') continue;
        final keys = {
          _key(data['boqCode']),
          _key(data['displayCode']),
          _key(data['resolvedBoqCode']),
        }..removeWhere((key) => key.isEmpty);
        final hasMeasurement = keys.any(measuredKeys.contains);
        final hasQtyOverride = _num(data['qtyOverride']) > 0;
        if (!hasMeasurement && !hasQtyOverride) unmeasuredTotal += 1;
      }
    }

    final result = <String, int>{
      'buildings': buildingDocs.length,
      'drawings': drawingsTotal,
      'measurements': measurementsTotal,
      'boqItems': boqTotal,
      'unmeasuredItems': unmeasuredTotal,
    };

    _countsCacheMap[projectId] = result;
    return result;
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? 0;
  }

  String _key(dynamic v) =>
      (v ?? '').toString().trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();

  String _rowType(dynamic v) {
    final value = (v ?? '').toString().trim().toLowerCase();
    return value.isEmpty ? 'item' : value;
  }

  Future<double> _getProjectBoqValue(String projectId) async {
    final cached = _projectValueCacheMap[projectId];
    if (cached != null) return cached;

    final projectRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(projectId);
    final buildings = await projectRef.collection('buildings').get();
    double total = 0;

    for (final building in buildings.docs) {
      final bRef = building.reference;
      var boqDocs = await bRef.collection('boq').get();
      if (boqDocs.docs.isEmpty) {
        boqDocs = await bRef.collection('boqItems').get();
      }
      final measurementDocs = await bRef.collection('measurements').get();

      final totalsByBoq = <String, double>{};
      for (final doc in measurementDocs.docs) {
        final data = doc.data();
        final value = _num(data['value']);
        if (value == 0) continue;
        final keys = {
          _key(data['boqCode']),
          _key(data['resolvedBoqCode']),
          _key(data['boqCodeNorm']),
        }..removeWhere((key) => key.isEmpty);
        for (final key in keys) {
          totalsByBoq[key] = (totalsByBoq[key] ?? 0) + value;
        }
      }

      for (final doc in boqDocs.docs) {
        final data = doc.data();
        if (_rowType(data['rowType']) != 'item') continue;
        final rate = _num(data['rate']);
        if (rate == 0) continue;

        final qtyOverride = data['qtyOverride'];
        final qty =
            qtyOverride is num
                ? qtyOverride.toDouble()
                : double.tryParse('${qtyOverride ?? ''}') ??
                    totalsByBoq[_key(data['resolvedBoqCode'])] ??
                    totalsByBoq[_key(data['displayCode'])] ??
                    totalsByBoq[_key(data['boqCode'])] ??
                    0;
        total += qty * rate;
      }
    }

    _projectValueCacheMap[projectId] = total;
    return total;
  }

  final Map<String, Map<String, int>> _countsCacheMap = {};
  final Map<String, double> _projectValueCacheMap = {};

  void _refreshCounts() {
    setState(() {
      _countsCacheMap.clear();
      _projectValueCacheMap.clear();
    });
  }

  DateTime? _latestProjectDate(List<ProjectRowFs> projects) {
    DateTime? latest;
    for (final project in projects) {
      final date = (project.updatedAt ?? project.createdAt)?.toDate();
      if (date == null) continue;
      if (latest == null || date.isAfter(latest)) latest = date;
    }
    return latest;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // stream: FirebaseFirestore.instance.collection('projects').snapshots(),
      stream: baseQuery().snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const _DashboardLoadingState(
            message: 'Loading projects and project totals',
          );
        }

        // 1) map docs -> rows visible to this user only. Invited members must
        // not see projects unless their uid is in members. Owners can see their
        // own projects even if older docs missed the members array.
        final uid = widget._user.uid;
        final visibleDocs =
            snap.data!.docs.where((doc) {
              final data = doc.data();
              final ownerId = (data['ownerId'] ?? '').toString();
              final members = (data['members'] as List?) ?? const [];
              return ownerId == uid ||
                  members.map((e) => e.toString()).contains(uid);
            }).toList();
        final all = visibleDocs.map(ProjectRowFs.fromDoc).toList();
        all.sort((a, b) {
          final ad = (a.updatedAt ?? a.createdAt)?.millisecondsSinceEpoch ?? 0;
          final bd = (b.updatedAt ?? b.createdAt)?.millisecondsSinceEpoch ?? 0;
          return bd.compareTo(ad);
        });

        // 2) apply client-side filters (search + stage) for the full Projects
        // register. The Dashboard keeps a short recent-projects preview.
        final q = widget._search.text.trim().toLowerCase();
        var filtered = all;

        if (widget.fullRegister && stageFilter != null) {
          filtered = filtered.where((p) => p.stage == stageFilter).toList();
        }
        if (widget.fullRegister && q.isNotEmpty) {
          filtered =
              filtered.where((p) {
                return p.name.toLowerCase().contains(q) ||
                    p.clientName.toLowerCase().contains(q) ||
                    p.currency.toLowerCase().contains(q);
              }).toList();
        }

        // 3) paginate only in the dedicated Projects section.
        final maxPage = max(1, (filtered.length / pageSize).ceil());
        page = min(page, maxPage);
        final start = (page - 1) * pageSize;
        final pageRows = filtered.skip(start).take(pageSize).toList();
        final selectedDashboardProject =
            all.isEmpty
                ? null
                : all.firstWhere(
                  (project) => project.id == _selectedDashboardProjectId,
                  orElse: () => all.first,
                );
        if (selectedDashboardProject != null &&
            _selectedDashboardProjectId != selectedDashboardProject.id) {
          _selectedDashboardProjectId = selectedDashboardProject.id;
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final horizontalPadding = compact ? 16.0 : 24.0;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                compact ? 16 : 22,
                horizontalPadding,
                28,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!widget.fullRegister) ...[
                        WelcomeBanner(
                          user: widget._user,
                          onViewPlans: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const PricingPlansPage(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        _DashboardOverviewStats(projects: all),
                        const SizedBox(height: 24),
                        _LastWorkedProjectCard(
                          project: selectedDashboardProject,
                          projects: all,
                          selectedProjectId: selectedDashboardProject?.id,
                          onProjectChanged:
                              (projectId) => setState(
                                () => _selectedDashboardProjectId = projectId,
                              ),
                          getCounts: _getCountsForProject,
                          getProjectValue: _getProjectBoqValue,
                          onOpen:
                              selectedDashboardProject == null
                                  ? null
                                  : () => _handleRowAction(
                                    selectedDashboardProject,
                                    'Open Project',
                                  ),
                          onNewProject: () => openNewProjectDialog(context),
                          onViewAllProjects: widget.onViewAllProjects,
                        ),
                        const SizedBox(height: 18),
                        const _RecentMeasurementsPanel(),
                        const SizedBox(height: 18),
                        UpgradeCard(
                          onUpgrade:
                              () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const PricingPlansPage(),
                                ),
                              ),
                        ),
                      ],

                      if (widget.fullRegister) ...[
                        _ProjectsRegisterHeader(
                          compact: compact,
                          visibleProjects: filtered.length,
                          totalProjects: all.length,
                          lastUpdated: _latestProjectDate(all),
                          onRefresh: _refreshCounts,
                          onNewProject: () => openNewProjectDialog(context),
                        ),
                        const SizedBox(height: 16),
                        _ProjectCardsGrid(
                          rows: pageRows,
                          getCounts:
                              (projectId) => _getCountsForProject(projectId),
                          onChangeStage: _changeStage,
                          onRowAction: _handleRowAction,
                        ),
                        const SizedBox(height: 12),
                        PaginationRow(
                          page: page,
                          pageSize: pageSize,
                          total: filtered.length,
                          onPrev: () => setState(() => page = max(1, page - 1)),
                          onNext:
                              () =>
                                  setState(() => page = min(maxPage, page + 1)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ProjectsRegisterHeader extends StatelessWidget {
  const _ProjectsRegisterHeader({
    required this.compact,
    required this.visibleProjects,
    required this.totalProjects,
    required this.lastUpdated,
    required this.onRefresh,
    required this.onNewProject,
  });

  final bool compact;
  final int visibleProjects;
  final int totalProjects;
  final DateTime? lastUpdated;
  final VoidCallback onRefresh;
  final VoidCallback onNewProject;

  String get _lastUpdatedLabel {
    if (lastUpdated == null) return 'No project activity yet';
    final date = DateFormat('dd MMM yyyy, HH:mm').format(lastUpdated!);
    return 'Last activity $date';
  }

  @override
  Widget build(BuildContext context) {
    final actionRow = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
        ),
        FilledButton.icon(
          onPressed: onNewProject,
          icon: const Icon(Icons.add_rounded),
          label: const Text('New Project'),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AqsColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child:
          compact
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _ProjectsRegisterTitle(),
                  const SizedBox(height: 16),
                  actionRow,
                  const SizedBox(height: 14),
                  _RegisterStatusLine(
                    visibleProjects: visibleProjects,
                    totalProjects: totalProjects,
                    lastUpdatedLabel: _lastUpdatedLabel,
                  ),
                ],
              )
              : Row(
                children: [
                  const Expanded(child: _ProjectsRegisterTitle()),
                  const SizedBox(width: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      actionRow,
                      const SizedBox(height: 12),
                      _RegisterStatusLine(
                        visibleProjects: visibleProjects,
                        totalProjects: totalProjects,
                        lastUpdatedLabel: _lastUpdatedLabel,
                      ),
                    ],
                  ),
                ],
              ),
    );
  }
}

class _ProjectsRegisterTitle extends StatelessWidget {
  const _ProjectsRegisterTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AqsColors.primarySoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.folder_copy_outlined,
            color: AqsColors.primary,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Project portfolio',
                style: TextStyle(
                  color: AqsColors.ink,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Search, filter, open, rename, archive, and manage every '
                'project from one register.',
                style: TextStyle(
                  color: AqsColors.muted,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RegisterStatusLine extends StatelessWidget {
  const _RegisterStatusLine({
    required this.visibleProjects,
    required this.totalProjects,
    required this.lastUpdatedLabel,
  });

  final int visibleProjects;
  final int totalProjects;
  final String lastUpdatedLabel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        _SmallStatusPill(
          icon: Icons.filter_alt_outlined,
          label: '$visibleProjects of $totalProjects shown',
        ),
        _SmallStatusPill(icon: Icons.update_rounded, label: lastUpdatedLabel),
      ],
    );
  }
}

class _ProjectCardsGrid extends StatelessWidget {
  const _ProjectCardsGrid({
    required this.rows,
    required this.getCounts,
    required this.onChangeStage,
    required this.onRowAction,
  });

  final List<ProjectRowFs> rows;
  final Future<Map<String, int>> Function(String projectId) getCounts;
  final Future<void> Function(ProjectRowFs row, ProjectStage newStage)
  onChangeStage;
  final void Function(ProjectRowFs row, String action) onRowAction;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AqsColors.border),
        ),
        child: const Column(
          children: [
            Icon(Icons.folder_open_outlined, size: 38, color: AqsColors.subtle),
            SizedBox(height: 10),
            Text(
              'No projects match this view',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: AqsColors.text,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 1180
                ? 3
                : constraints.maxWidth >= 760
                ? 2
                : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rows.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: columns == 1 ? 390 : 410,
          ),
          itemBuilder:
              (context, index) => _ProjectPortfolioCard(
                row: rows[index],
                getCounts: getCounts,
                onChangeStage: onChangeStage,
                onRowAction: onRowAction,
              ),
        );
      },
    );
  }
}

class _ProjectPortfolioCard extends StatefulWidget {
  const _ProjectPortfolioCard({
    required this.row,
    required this.getCounts,
    required this.onChangeStage,
    required this.onRowAction,
  });

  final ProjectRowFs row;
  final Future<Map<String, int>> Function(String projectId) getCounts;
  final Future<void> Function(ProjectRowFs row, ProjectStage newStage)
  onChangeStage;
  final void Function(ProjectRowFs row, String action) onRowAction;

  @override
  State<_ProjectPortfolioCard> createState() => _ProjectPortfolioCardState();
}

class _ProjectPortfolioCardState extends State<_ProjectPortfolioCard> {
  bool _hovered = false;
  late Future<Map<String, int>> _countsFuture;
  Timer? _loadingTimer;
  int _loadingPercent = 8;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  @override
  void didUpdateWidget(covariant _ProjectPortfolioCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.id != widget.row.id) _loadCounts();
  }

  void _loadCounts() {
    _loadingTimer?.cancel();
    _loadingPercent = 8;
    _countsFuture = widget.getCounts(widget.row.id);
    _loadingTimer = Timer.periodic(const Duration(milliseconds: 450), (timer) {
      if (!mounted) return;
      setState(() {
        final step = _loadingPercent < 35 ? 9 : (_loadingPercent < 70 ? 6 : 3);
        _loadingPercent = min(92, _loadingPercent + step);
      });
    });
    void finishLoading() {
      _loadingTimer?.cancel();
      if (mounted) setState(() => _loadingPercent = 100);
    }

    _countsFuture.then<void>(
      (_) => finishLoading(),
      onError: (Object _, StackTrace __) => finishLoading(),
    );
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }

  String get _loadingMessage {
    if (_loadingPercent < 30) return 'We’re gathering your project';
    if (_loadingPercent < 60) return 'Loading buildings and drawings';
    if (_loadingPercent < 85) return 'Checking BOQ items and measurements';
    return 'Preparing your project summary';
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final client = row.clientName.trim().isEmpty ? 'No client' : row.clientName;
    final currency = row.currency.trim().isEmpty ? '-' : row.currency;
    final date = (row.updatedAt ?? row.createdAt)?.toDate();
    final lastActive =
        date == null
            ? 'No activity yet'
            : DateFormat('dd MMM yyyy, HH:mm').format(date);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color:
                _hovered
                    ? AqsColors.primary.withOpacity(0.32)
                    : AqsColors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFF101828,
              ).withOpacity(_hovered ? 0.12 : 0.06),
              blurRadius: _hovered ? 28 : 18,
              offset: Offset(0, _hovered ? 16 : 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => widget.onRowAction(row, 'Open Project'),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: FutureBuilder<Map<String, int>>(
                future: _countsFuture,
                builder: (context, snapshot) {
                  final loading =
                      snapshot.connectionState == ConnectionState.waiting;
                  final counts = snapshot.data ?? const <String, int>{};
                  final buildings = counts['buildings'] ?? 0;
                  final drawings = counts['drawings'] ?? 0;
                  final measurements = counts['measurements'] ?? 0;
                  final boqItems = counts['boqItems'] ?? 0;
                  final unmeasured = counts['unmeasuredItems'] ?? 0;
                  final measuredBoq = max(0, boqItems - unmeasured);
                  final progress =
                      boqItems <= 0
                          ? 0.0
                          : (measuredBoq / boqItems).clamp(0.0, 1.0);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0B2B67), Color(0xFF155EEF)],
                              ),
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
                                  row.name.isEmpty ? '(No name)' : row.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AqsColors.ink,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    StagePill(stage: row.stage),
                                    _MiniInfoPill(
                                      icon: Icons.payments_outlined,
                                      label: currency,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Project actions',
                            onSelected:
                                (value) => widget.onRowAction(row, value),
                            itemBuilder:
                                (_) => const [
                                  PopupMenuItem(
                                    value: 'Open Project',
                                    child: Text('Open Project'),
                                  ),
                                  PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: 'Rename',
                                    child: Text('Rename'),
                                  ),
                                  PopupMenuItem(
                                    value: 'Archive',
                                    child: Text('Archive'),
                                  ),
                                  PopupMenuItem(
                                    value: 'Duplicate',
                                    child: Text('Duplicate'),
                                  ),
                                  PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: 'Delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _ProjectProgressBar(
                        progress: progress,
                        measuredBoq: measuredBoq,
                        boqItems: boqItems,
                        loading: loading,
                        loadingPercent: _loadingPercent,
                        loadingMessage: _loadingMessage,
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: GridView.count(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          physics: const NeverScrollableScrollPhysics(),
                          childAspectRatio: 2.35,
                          children: [
                            _ProjectMetricTile(
                              icon: Icons.apartment_rounded,
                              label: 'Facilities / buildings',
                              value: loading ? '...' : buildings.toString(),
                            ),
                            _ProjectMetricTile(
                              icon: Icons.description_outlined,
                              label: 'Drawings',
                              value: loading ? '...' : drawings.toString(),
                            ),
                            _ProjectMetricTile(
                              icon: Icons.straighten_rounded,
                              label: 'Measurements',
                              value: loading ? '...' : measurements.toString(),
                            ),
                            _ProjectMetricTile(
                              icon: Icons.view_list_rounded,
                              label: 'BOQ items',
                              value: loading ? '...' : boqItems.toString(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _MiniInfoPill(
                            icon: Icons.apartment_outlined,
                            label: client,
                          ),
                          _MiniInfoPill(
                            icon: Icons.update_rounded,
                            label: lastActive,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  () => widget.onRowAction(row, 'Open Project'),
                              icon: const Icon(
                                Icons.open_in_new_rounded,
                                size: 18,
                              ),
                              label: const Text('Open project'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          PopupMenuButton<ProjectStage>(
                            tooltip: 'Change stage',
                            onSelected:
                                (stage) => widget.onChangeStage(row, stage),
                            itemBuilder:
                                (_) =>
                                    ProjectStage.values
                                        .map(
                                          (stage) =>
                                              PopupMenuItem<ProjectStage>(
                                                value: stage,
                                                child: Text(stage.label),
                                              ),
                                        )
                                        .toList(),
                            child: Container(
                              height: 48,
                              width: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AqsColors.border),
                              ),
                              child: const Icon(
                                Icons.swap_vert_rounded,
                                color: AqsColors.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectProgressBar extends StatelessWidget {
  const _ProjectProgressBar({
    required this.progress,
    required this.measuredBoq,
    required this.boqItems,
    required this.loading,
    required this.loadingPercent,
    required this.loadingMessage,
  });

  final double progress;
  final int measuredBoq;
  final int boqItems;
  final bool loading;
  final int loadingPercent;
  final String loadingMessage;

  @override
  Widget build(BuildContext context) {
    final percent =
        loading ? '$loadingPercent%' : '${(progress * 100).round()}%';
    final detail =
        loading
            ? loadingMessage
            : boqItems == 0
            ? 'No BOQ items yet'
            : '$measuredBoq of $boqItems BOQ items measured';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AqsColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD6E4FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Taking-off progress',
                  style: TextStyle(
                    color: AqsColors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                percent,
                style: const TextStyle(
                  color: AqsColors.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: loading ? loadingPercent / 100 : progress,
              minHeight: 8,
              backgroundColor: Colors.white,
              color: AqsColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AqsColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectMetricTile extends StatelessWidget {
  const _ProjectMetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AqsColors.primary, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AqsColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AqsColors.muted,
                    fontSize: 11,
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

class _MiniInfoPill extends StatelessWidget {
  const _MiniInfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AqsColors.muted),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AqsColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallStatusPill extends StatelessWidget {
  const _SmallStatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AqsColors.muted),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AqsColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardOverviewStats extends StatelessWidget {
  const _DashboardOverviewStats({required this.projects});

  final List<ProjectRowFs> projects;

  int _count(ProjectStage stage) =>
      projects.where((p) => p.stage == stage).length;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _OverviewStatData(
        label: 'Total projects',
        value: projects.length.toString(),
        icon: Icons.folder_copy_outlined,
        color: const Color(0xFF155EEF),
      ),
      _OverviewStatData(
        label: 'Tender stage',
        value: _count(ProjectStage.tender).toString(),
        icon: Icons.assignment_outlined,
        color: const Color(0xFF7C3AED),
      ),
      _OverviewStatData(
        label: 'In progress',
        value: _count(ProjectStage.progress).toString(),
        icon: Icons.engineering_outlined,
        color: const Color(0xFFEA580C),
      ),
      _OverviewStatData(
        label: 'Valuation',
        value: _count(ProjectStage.valuation).toString(),
        icon: Icons.payments_outlined,
        color: const Color(0xFF047857),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: compact ? 2 : 4,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: compact ? 132 : 124,
          ),
          itemBuilder: (_, i) => _OverviewStatCard(data: cards[i]),
        );
      },
    );
  }
}

class _OverviewStatData {
  const _OverviewStatData({
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

class _OverviewStatCard extends StatelessWidget {
  const _OverviewStatCard({required this.data});

  final _OverviewStatData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E7EC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08101828),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF667085),
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

class _LastWorkedProjectCard extends StatelessWidget {
  const _LastWorkedProjectCard({
    required this.project,
    required this.projects,
    required this.selectedProjectId,
    required this.onProjectChanged,
    required this.getCounts,
    required this.getProjectValue,
    required this.onOpen,
    required this.onNewProject,
    required this.onViewAllProjects,
  });

  final ProjectRowFs? project;
  final List<ProjectRowFs> projects;
  final String? selectedProjectId;
  final ValueChanged<String> onProjectChanged;
  final Future<Map<String, int>> Function(String projectId) getCounts;
  final Future<double> Function(String projectId) getProjectValue;
  final VoidCallback? onOpen;
  final VoidCallback onNewProject;
  final VoidCallback? onViewAllProjects;

  String _dateText(ProjectRowFs project) {
    final date = (project.updatedAt ?? project.createdAt)?.toDate();
    if (date == null) return 'No activity date yet';
    return 'Last worked ${DateFormat('dd MMM yyyy, HH:mm').format(date)}';
  }

  @override
  Widget build(BuildContext context) {
    final p = project;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF102A56), Color(0xFF155EEF)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26155EEF),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child:
          p == null
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No project yet',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create your first project to start drawings, measurements, and BOQ work.',
                    style: TextStyle(color: Color(0xFFD6E4FF), height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onNewProject,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create project'),
                  ),
                ],
              )
              : LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 760;
                  final header = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (projects.length > 1) ...[
                        _DashboardProjectSelector(
                          projects: projects,
                          selectedProjectId: selectedProjectId ?? p.id,
                          onChanged: onProjectChanged,
                        ),
                        const SizedBox(height: 16),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.18),
                          ),
                        ),
                        child: const Text(
                          'SELECTED PROJECT',
                          style: TextStyle(
                            color: Color(0xFFD6E4FF),
                            fontSize: 11,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        p.name.isEmpty ? 'Untitled project' : p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          height: 1.08,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.7,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        [
                          if (p.clientName.trim().isNotEmpty) p.clientName,
                          p.stage.label,
                          _dateText(p),
                        ].join(' • '),
                        style: const TextStyle(
                          color: Color(0xFFD6E4FF),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: onOpen,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Open project'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF155EEF),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: onViewAllProjects,
                            icon: const Icon(Icons.folder_open_outlined),
                            label: const Text('All projects'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withOpacity(0.45),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );

                  final counts = FutureBuilder<Map<String, int>>(
                    future: getCounts(p.id),
                    builder: (context, snap) {
                      final data = snap.data ?? const <String, int>{};
                      return FutureBuilder<double>(
                        future: getProjectValue(p.id),
                        builder: (context, valueSnap) {
                          return _ProjectQuickStats(
                            loading:
                                snap.connectionState ==
                                    ConnectionState.waiting ||
                                valueSnap.connectionState ==
                                    ConnectionState.waiting,
                            currency:
                                p.currency.trim().isEmpty ? 'TZS' : p.currency,
                            projectValue: valueSnap.data ?? 0,
                            buildings: data['buildings'] ?? 0,
                            drawings: data['drawings'] ?? 0,
                            measurements: data['measurements'] ?? 0,
                            boqItems: data['boqItems'] ?? 0,
                            unmeasuredItems: data['unmeasuredItems'] ?? 0,
                          );
                        },
                      );
                    },
                  );

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [header, const SizedBox(height: 22), counts],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(flex: 7, child: header),
                      const SizedBox(width: 24),
                      Expanded(flex: 5, child: counts),
                    ],
                  );
                },
              ),
    );
  }
}

class _DashboardProjectSelector extends StatelessWidget {
  const _DashboardProjectSelector({
    required this.projects,
    required this.selectedProjectId,
    required this.onChanged,
  });

  final List<ProjectRowFs> projects;
  final String selectedProjectId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedProjectId,
          isExpanded: true,
          dropdownColor: const Color(0xFF12356F),
          iconEnabledColor: Colors.white,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
          items:
              projects.map((project) {
                return DropdownMenuItem(
                  value: project.id,
                  child: Text(
                    project.name.isEmpty ? 'Untitled project' : project.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );
              }).toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _ProjectQuickStats extends StatelessWidget {
  const _ProjectQuickStats({
    required this.loading,
    required this.currency,
    required this.projectValue,
    required this.buildings,
    required this.drawings,
    required this.measurements,
    required this.boqItems,
    required this.unmeasuredItems,
  });

  final bool loading;
  final String currency;
  final double projectValue;
  final int buildings;
  final int drawings;
  final int measurements;
  final int boqItems;
  final int unmeasuredItems;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    final items = [
      _HeroMetric(
        'Project cost',
        '$currency ${money.format(projectValue)}',
        Icons.payments_outlined,
      ),
      _HeroMetric('Buildings', buildings.toString(), Icons.apartment_rounded),
      _HeroMetric('Drawings', drawings.toString(), Icons.description_outlined),
      _HeroMetric(
        'Measurements',
        measurements.toString(),
        Icons.straighten_rounded,
      ),
      _HeroMetric(
        'BOQ items',
        boqItems.toString(),
        Icons.receipt_long_outlined,
      ),
      _HeroMetric(
        'Unmeasured',
        unmeasuredItems.toString(),
        Icons.pending_actions_outlined,
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.05,
        ),
        itemBuilder: (_, i) {
          final item = items[i];
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.11),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.09)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    item.icon,
                    color: const Color(0xFFD6E4FF),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loading ? '...' : item.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFBFD2FA),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeroMetric {
  const _HeroMetric(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

class _RecentMeasurementsPanel extends StatelessWidget {
  const _RecentMeasurementsPanel();

  String _measurementTitle(Map<String, dynamic> data) {
    final label = (data['label'] ?? data['memberTypeLabel'] ?? '').toString();
    if (label.trim().isNotEmpty) return label.trim();

    final boq =
        (data['boqDescription'] ?? data['resolvedBoqDescription'] ?? '')
            .toString();
    if (boq.trim().isNotEmpty) return boq.trim();

    final type =
        (data['measureType'] ?? data['type'] ?? 'Measurement').toString();
    return type.trim().isEmpty ? 'Measurement' : type;
  }

  String _quantityText(Map<String, dynamic> data) {
    final raw = data['value'] ?? data['quantity'] ?? data['totalLengthM'];
    final unit = (data['unit'] ?? data['resolvedUnit'] ?? '').toString();
    if (raw is num) {
      final value = raw.toDouble();
      final formatted =
          value.abs() >= 100
              ? value.toStringAsFixed(0)
              : value.toStringAsFixed(2);
      return unit.trim().isEmpty ? formatted : '$formatted $unit';
    }
    final txt = (raw ?? '').toString();
    return txt.trim().isEmpty ? 'Recorded' : txt;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E7EC)),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF155EEF).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.timeline_rounded,
                    color: Color(0xFF155EEF),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recent measurements',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF101828),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Latest quantities recorded across your projects.',
                        style: TextStyle(color: Color(0xFF667085)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream:
                FirebaseFirestore.instance
                    .collectionGroup('measurements')
                    .orderBy('createdAt', descending: true)
                    .limit(6)
                    .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Recent measurements are unavailable. This may need a Firestore collection group index.',
                    style: TextStyle(color: Color(0xFF667085)),
                  ),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(22),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(18, 10, 18, 22),
                  child: Text(
                    'No measurements recorded yet.',
                    style: TextStyle(color: Color(0xFF667085)),
                  ),
                );
              }
              return Column(
                children: [
                  for (final doc in docs)
                    _RecentMeasurementTile(
                      data: doc.data(),
                      title: _measurementTitle(doc.data()),
                      quantity: _quantityText(doc.data()),
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

class _RecentMeasurementTile extends StatelessWidget {
  const _RecentMeasurementTile({
    required this.data,
    required this.title,
    required this.quantity,
  });

  final Map<String, dynamic> data;
  final String title;
  final String quantity;

  @override
  Widget build(BuildContext context) {
    final created = (data['createdAt'] as Timestamp?)?.toDate();
    final createdText =
        created == null
            ? 'Just now'
            : DateFormat('dd MMM, HH:mm').format(created);
    final boqCode =
        (data['boqCode'] ?? data['resolvedBoqCode'] ?? '').toString();
    final drawing =
        (data['drawingTitle'] ?? data['drawingName'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE4E7EC))),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.straighten_rounded,
              color: Color(0xFF475467),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (boqCode.trim().isNotEmpty) 'BOQ $boqCode',
                    if (drawing.trim().isNotEmpty) drawing,
                    createdText,
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF3),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              quantity,
              style: const TextStyle(
                color: Color(0xFF047857),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardLoadingState extends StatelessWidget {
  final String message;

  const _DashboardLoadingState({required this.message});

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
