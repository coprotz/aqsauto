import 'package:aqs/core/state/firestore_state.dart';
import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/features/dashboards/controllers/project_buildings_controller.dart';
import 'package:aqs/features/utils/helpers/boq_helpers.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BoqBillsSummaryPage extends StatefulWidget {
  final String projectId;
  final String buildingId;
  final String projectName;
  final String buildingName;

  /// Keep this only if exportBoqExcel belongs to another workspace controller.
  final dynamic workspaceController;

  const BoqBillsSummaryPage({
    super.key,
    required this.projectId,
    required this.buildingId,
    required this.projectName,
    required this.buildingName,
    required this.workspaceController,
  });

  @override
  State<BoqBillsSummaryPage> createState() => _BoqBillsSummaryPageState();
}

class _BoqBillsSummaryPageState extends State<BoqBillsSummaryPage> {
  late final ProjectBuildingsController controller;

  String _s(dynamic v) => (v ?? '').toString();

  String _key(dynamic v) =>
      _s(v).trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();

  String _rowType(dynamic v) {
    final x = _s(v).trim().toLowerCase();

    if (x.isEmpty) {
      return 'item';
    }

    return x;
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;

    if (v is num) {
      return v.toDouble();
    }

    return double.tryParse('$v');
  }

  String get _cacheKey => '${widget.projectId}::${widget.buildingId}';

  CollectionReference<Map<String, dynamic>> get _generalAllowancesRef =>
      FirebaseFirestore.instance
          .collection('projects')
          .doc(widget.projectId)
          .collection('buildings')
          .doc(widget.buildingId)
          .collection('generalAllowances');

  @override
  void initState() {
    super.initState();

    controller =
        Get.isRegistered<ProjectBuildingsController>()
            ? Get.find<ProjectBuildingsController>()
            : Get.put(ProjectBuildingsController(), permanent: true);

    // Financial totals must reflect measurements just saved from the take-off
    // screen, rather than an older dashboard cache.
    controller.loadMeasurements(
      widget.projectId,
      widget.buildingId,
      forceRefresh: true,
    );

    controller.loadBoq(widget.projectId, widget.buildingId, forceRefresh: true);
  }

  Future<void> _refresh() async {
    await Future.wait([
      controller.loadMeasurements(
        widget.projectId,
        widget.buildingId,
        forceRefresh: true,
      ),
      controller.loadBoq(
        widget.projectId,
        widget.buildingId,
        forceRefresh: true,
      ),
    ]);
  }

  Future<void> _showAllowanceDialog({
    DocumentSnapshot<Map<String, dynamic>>? existing,
  }) async {
    final data = existing?.data() ?? const <String, dynamic>{};
    final descriptionCtrl = TextEditingController(
      text: _s(data['description']),
    );
    final basisCtrl = TextEditingController(text: _s(data['basis']));
    final unitCtrl = TextEditingController(
      text: _s(data['unit']).trim().isEmpty ? 'Item' : _s(data['unit']),
    );
    final quantityCtrl = TextEditingController(
      text: (_asDouble(data['quantity']) ?? 1).toStringAsFixed(2),
    );
    final rateCtrl = TextEditingController(
      text: (_asDouble(data['rate']) ?? 0).toStringAsFixed(2),
    );
    final notesCtrl = TextEditingController(text: _s(data['notes']));
    var category =
        _s(data['category']).trim().isEmpty
            ? 'Provisional work'
            : _s(data['category']);
    var included = data['includedInTotal'] != false;
    String? error;

    double number(TextEditingController controller) =>
        double.tryParse(controller.text.trim().replaceAll(',', '')) ?? 0;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              final amount = number(quantityCtrl) * number(rateCtrl);
              return AlertDialog(
                title: Text(
                  existing == null
                      ? 'Add general allowance'
                      : 'Edit general allowance',
                ),
                content: SizedBox(
                  width: 680,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Use this for work that cannot yet be measured from complete drawings. It remains separate from drawing take-off.',
                          style: TextStyle(color: AqsColors.muted),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: category,
                          decoration: const InputDecoration(
                            labelText: 'Allowance type',
                            border: OutlineInputBorder(),
                          ),
                          items:
                              const [
                                    'Provisional work',
                                    'Additional work allowance',
                                    'Design development allowance',
                                    'Contingency',
                                  ]
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
                        TextField(
                          controller: descriptionCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Description of work',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: basisCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Basis or reason',
                            hintText:
                                'For example: design incomplete; quantity to be confirmed',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: unitCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Unit',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: quantityCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (_) => setDialogState(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'Estimated quantity',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: rateCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (_) => setDialogState(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'Rate (TZS)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AqsColors.primarySoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Allowance amount: ${fmtMoney(amount)} TZS',
                            style: const TextStyle(
                              color: AqsColors.ink,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: notesCtrl,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Notes or scope assumptions',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: included,
                          onChanged:
                              (value) => setDialogState(() => included = value),
                          title: const Text('Include in general total'),
                          subtitle: const Text(
                            'Turn off to retain the allowance without affecting the current total.',
                          ),
                        ),
                        if (error != null)
                          Text(
                            error!,
                            style: const TextStyle(color: Color(0xFFD92D20)),
                          ),
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
                      final description = descriptionCtrl.text.trim();
                      final quantity = number(quantityCtrl);
                      final rate = number(rateCtrl);
                      if (description.isEmpty || quantity <= 0 || rate < 0) {
                        setDialogState(
                          () =>
                              error =
                                  'Enter a description, a quantity greater than zero, and a valid rate.',
                        );
                        return;
                      }
                      final payload = <String, dynamic>{
                        'category': category,
                        'description': description,
                        'basis': basisCtrl.text.trim(),
                        'unit':
                            unitCtrl.text.trim().isEmpty
                                ? 'Item'
                                : unitCtrl.text.trim(),
                        'quantity': quantity,
                        'rate': rate,
                        'amount': quantity * rate,
                        'notes': notesCtrl.text.trim(),
                        'includedInTotal': included,
                        'source': 'generalAllowance',
                        'updatedAt': FieldValue.serverTimestamp(),
                      };
                      if (existing == null) {
                        payload['createdAt'] = FieldValue.serverTimestamp();
                        await _generalAllowancesRef.add(payload);
                      } else {
                        await existing.reference.update(payload);
                      }
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save allowance'),
                  ),
                ],
              );
            },
          ),
    );

    descriptionCtrl.dispose();
    basisCtrl.dispose();
    unitCtrl.dispose();
    quantityCtrl.dispose();
    rateCtrl.dispose();
    notesCtrl.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('General allowance saved.')));
    }
  }

  Future<void> _deleteAllowance(
    DocumentSnapshot<Map<String, dynamic>> allowance,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete allowance?'),
            content: Text(
              'Remove “${_s(allowance.data()?['description'])}” from the general sums?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD92D20),
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed == true) await allowance.reference.delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AqsColors.canvas,
      appBar: AppBar(
        toolbarHeight: 72,
        title: const AqsAppBarTitle(
          title: 'Bills Summary',
          subtitle: 'BOQ financial overview',
        ),
        actions: [
          Obx(() {
            final loading =
                controller.loadingMeasurements.contains(_cacheKey) ||
                controller.loadingBoq.contains(_cacheKey);

            return IconButton(
              tooltip: 'Refresh',
              onPressed: loading ? null : _refresh,
              icon:
                  loading
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.refresh_rounded),
            );
          }),
          const SizedBox(width: 8),
        ],
      ),

      body: Obx(() {
        final measurements =
            controller.measurementsByBuilding[_cacheKey] ??
            const <Map<String, dynamic>>[];

        final boqItems =
            controller.boqByBuilding[_cacheKey] ??
            const <Map<String, dynamic>>[];

        final measurementsLoaded = controller.measurementsByBuilding
            .containsKey(_cacheKey);

        final boqLoaded = controller.boqByBuilding.containsKey(_cacheKey);

        final loadingMeasurements = controller.loadingMeasurements.contains(
          _cacheKey,
        );

        final loadingBoq = controller.loadingBoq.contains(_cacheKey);

        final measurementError = controller.measurementErrors[_cacheKey] ?? '';

        final boqError = controller.boqErrors[_cacheKey] ?? '';

        // -----------------------------------------------
        // First load only.
        // If cached data exists, keep displaying it.
        // -----------------------------------------------

        if ((!measurementsLoaded || !boqLoaded) &&
            (loadingMeasurements || loadingBoq)) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                SizedBox(height: 14),
                Text(
                  'Preparing BOQ summary...',
                  style: TextStyle(
                    color: AqsColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }

        if (!measurementsLoaded && measurementError.isNotEmpty) {
          return _BillsSummaryErrorState(
            title: 'Measurements could not be loaded',
            message: measurementError,
            onRetry: _refresh,
          );
        }

        if (!boqLoaded && boqError.isNotEmpty) {
          return _BillsSummaryErrorState(
            title: 'BOQ could not be loaded',
            message: boqError,
            onRetry: _refresh,
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _generalAllowancesRef.stateSnapshots(),
          builder: (context, allowanceSnapshot) {
            if (allowanceSnapshot.hasError) {
              return _BillsSummaryErrorState(
                title: 'General allowances could not be loaded',
                message: '${allowanceSnapshot.error}',
                onRetry: _refresh,
              );
            }
            final allowances =
                allowanceSnapshot.data?.docs ??
                const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            return _buildSummary(
              boqItems: boqItems,
              measurements: measurements,
              allowances: allowances,
            );
          },
        );
      }),
    );
  }

  Widget _buildSummary({
    required List<Map<String, dynamic>> boqItems,
    required List<Map<String, dynamic>> measurements,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> allowances,
  }) {
    // =====================================================
    // 1. TOTALS BY BOQ FROM MEASUREMENTS
    // =====================================================

    final totalsByBoq = <String, double>{};
    final totalsByBoqItemId = <String, double>{};

    for (final m in measurements) {
      final q = _asDouble(m['value']);

      if (q == null) continue;

      final boqItemId = _s(m['boqItemId']).trim();
      if (boqItemId.isNotEmpty) {
        totalsByBoqItemId.update(
          boqItemId,
          (value) => value + q,
          ifAbsent: () => q,
        );
        // Stable document identity takes precedence over raw BOQ-code
        // aliases. Civil leaf codes such as "a" and "b" repeat throughout
        // the BOQ and must never receive another item's measurement.
        continue;
      }

      final keys = {
        _key(m['boqCode']),
        _key(m['resolvedBoqCode']),
        _key(m['boqCodeNorm']),
      }..removeWhere((key) => key.isEmpty);

      for (final key in keys) {
        totalsByBoq[key] = (totalsByBoq[key] ?? 0.0) + q;
      }
    }

    // =====================================================
    // 2. BUILD BILL SUMMARIES
    // =====================================================

    final bills = <String, _BillSum>{};
    final aliasCounts = <String, int>{};
    for (final data in boqItems) {
      if (_rowType(data['rowType']) != 'item') continue;
      final aliases = <String>{
        _key(data['resolvedBoqCode']),
        _key(data['displayCode']),
        _key(data['boqCode']),
        _key(hierarchicalBoqCodeFromRows(data, boqItems)),
      }..removeWhere((key) => key.isEmpty);
      for (final alias in aliases) {
        aliasCounts.update(alias, (count) => count + 1, ifAbsent: () => 1);
      }
    }

    for (final d in boqItems) {
      final type = _rowType(d['rowType']);

      // Only actual BOQ items contribute to totals.
      if (type != 'item') continue;

      final billCode = _s(d['billCode']).trim();

      if (billCode.isEmpty) continue;

      final rawBillLabel = _s(d['billLabel']).trim();

      final billLabel =
          rawBillLabel.isNotEmpty ? rawBillLabel : 'Bill $billCode';

      final rawBoqCode = _s(d['boqCode']).trim();
      final boqItemId = _s(d['id']).trim();

      final displayCode = _s(d['displayCode']).trim();

      final resolved = _s(d['resolvedBoqCode']).trim();

      final resolvedKey = resolved.isNotEmpty ? resolved : rawBoqCode;

      final viewKey = displayCode.isNotEmpty ? displayCode : rawBoqCode;
      final canonical = hierarchicalBoqCodeFromRows(d, boqItems);

      // ---------------------------------------------
      // Computed quantity from measurement state
      // ---------------------------------------------

      var qtyComputed = totalsByBoqItemId[boqItemId];
      if (qtyComputed == null) {
        final aliases = <String>{
          _key(resolvedKey),
          _key(viewKey),
          _key(rawBoqCode),
          _key(canonical),
        }..removeWhere((key) => key.isEmpty);
        for (final alias in aliases) {
          if (aliasCounts[alias] != 1) continue;
          final matched = totalsByBoq[alias];
          if (matched != null) {
            qtyComputed = matched;
            break;
          }
        }
      }
      qtyComputed ??= 0.0;

      // ---------------------------------------------
      // Optional BOQ quantity override
      // ---------------------------------------------

      final qOverrideNum = d['qtyOverride'];

      final qtyOverride =
          qOverrideNum is num
              ? qOverrideNum.toDouble()
              : double.tryParse('$qOverrideNum');

      final qty = qtyOverride ?? qtyComputed;

      // ---------------------------------------------
      // Rate
      // ---------------------------------------------

      final rateNum = d['rate'];

      final rate =
          rateNum is num ? rateNum.toDouble() : double.tryParse('$rateNum');

      final amount = rate == null ? 0.0 : qty * rate;

      final bill = bills.putIfAbsent(
        billCode,
        () => _BillSum(billCode: billCode, billLabel: billLabel),
      );

      bill.totalAmount += amount;
      bill.itemCount += 1;

      if (qty > 0) {
        bill.measuredItemCount += 1;
      }

      if (amount > 0) {
        bill.valuedItemCount += 1;
      }
    }

    // =====================================================
    // 3. SORT BILLS
    // =====================================================

    final billList =
        bills.values.toList()..sort((a, b) {
          final ai = int.tryParse(a.billCode) ?? 9999;

          final bi = int.tryParse(b.billCode) ?? 9999;

          return ai.compareTo(bi);
        });

    // =====================================================
    // 4. KPIs
    // =====================================================

    final measuredWorksTotal = billList.fold<double>(
      0.0,
      (sum, bill) => sum + bill.totalAmount,
    );

    final generalAllowancesTotal = allowances.fold<double>(0.0, (
      sum,
      allowance,
    ) {
      final data = allowance.data();
      if (data['includedInTotal'] == false) return sum;
      final storedAmount = _asDouble(data['amount']);
      final amount =
          storedAmount ??
          ((_asDouble(data['quantity']) ?? 0) * (_asDouble(data['rate']) ?? 0));
      return sum + amount;
    });

    final grandTotal = measuredWorksTotal + generalAllowancesTotal;

    final totalItems = billList.fold<int>(
      0,
      (sum, bill) => sum + bill.itemCount,
    );

    final measuredItems = billList.fold<int>(
      0,
      (sum, bill) => sum + bill.measuredItemCount,
    );

    final valuedBills = billList.where((bill) => bill.totalAmount > 0).length;

    // =====================================================
    // 5. UI
    // =====================================================

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          _SummaryHero(
            projectName: widget.projectName,
            buildingName: widget.buildingName,
            grandTotal: grandTotal,
            measuredWorksTotal: measuredWorksTotal,
            generalAllowancesTotal: generalAllowancesTotal,
            onProjectTap:
                () => Get.toNamed(
                  AppRoutes.projectBuildingsPath(
                    widget.projectId,
                    widget.projectName,
                  ),
                ),
          ),

          const SizedBox(height: 14),

          _KpiGrid(
            billCount: billList.length,
            valuedBills: valuedBills,
            totalItems: totalItems,
            measuredItems: measuredItems,
          ),

          const SizedBox(height: 18),

          _buildGeneralAllowancesSection(
            allowances: allowances,
            includedTotal: generalAllowancesTotal,
          ),

          const SizedBox(height: 22),

          LayoutBuilder(
            builder: (context, constraints) {
              const heading = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bill distribution',
                    style: TextStyle(
                      color: AqsColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Value and measurement progress across every bill.',
                    style: TextStyle(color: AqsColors.muted, fontSize: 12),
                  ),
                ],
              );
              final exportButton = OutlinedButton.icon(
                onPressed: () async {
                  await widget.workspaceController.exportBoqExcel(
                    projectName: widget.projectName,
                    buildingName: widget.buildingName,
                  );
                },
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Export Excel'),
              );
              if (constraints.maxWidth < 620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading,
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: exportButton),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 16),
                  exportButton,
                ],
              );
            },
          ),

          const SizedBox(height: 12),

          if (billList.isEmpty)
            const _EmptyBillsState()
          else
            ...billList.asMap().entries.map((entry) {
              final bill = entry.value;

              final percentage =
                  grandTotal <= 0 ? 0.0 : bill.totalAmount / grandTotal;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BillSummaryCard(
                  bill: bill,
                  percentage: percentage,
                  accentIndex: entry.key,
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildGeneralAllowancesSection({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> allowances,
    required double includedTotal,
  }) {
    final sorted = [...allowances]..sort((a, b) {
      final aDescription = _s(a.data()['description']).toLowerCase();
      final bDescription = _s(b.data()['description']).toLowerCase();
      return aDescription.compareTo(bDescription);
    });

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AqsColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F101828),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final heading = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'General sums and allowances',
                    style: TextStyle(
                      color: AqsColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Provisional or additional work that is not supported by complete design information.',
                    style: TextStyle(color: AqsColors.muted, fontSize: 12),
                  ),
                  if (sorted.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      '${sorted.length} allowance${sorted.length == 1 ? '' : 's'} · ${fmtMoney(includedTotal)} TZS included',
                      style: const TextStyle(
                        color: AqsColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              );
              final addButton = FilledButton.icon(
                onPressed: () => _showAllowanceDialog(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add allowance'),
              );
              if (constraints.maxWidth < 680) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading,
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: addButton),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 16),
                  addButton,
                ],
              );
            },
          ),
          if (sorted.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 18),
              child: Text(
                'No general allowances added. Measured BOQ quantities remain unchanged.',
                style: TextStyle(color: AqsColors.muted),
              ),
            )
          else ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            ...sorted.map((allowance) {
              final data = allowance.data();
              final included = data['includedInTotal'] != false;
              final quantity = _asDouble(data['quantity']) ?? 0;
              final rate = _asDouble(data['rate']) ?? 0;
              final amount = _asDouble(data['amount']) ?? quantity * rate;
              final basis = _s(data['basis']).trim();
              return Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color:
                        included
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AqsColors.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color:
                              included
                                  ? const Color(0xFFFFF4E5)
                                  : const Color(0xFFE4E7EC),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          Icons.pending_actions_rounded,
                          color:
                              included
                                  ? const Color(0xFFB54708)
                                  : AqsColors.muted,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  _s(data['description']),
                                  style: const TextStyle(
                                    color: AqsColors.ink,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: AqsColors.border),
                                  ),
                                  child: Text(
                                    _s(data['category']),
                                    style: const TextStyle(
                                      color: AqsColors.muted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (!included)
                                  const Text(
                                    'Excluded from total',
                                    style: TextStyle(
                                      color: Color(0xFFB54708),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                              ],
                            ),
                            if (basis.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Text(
                                basis,
                                style: const TextStyle(
                                  color: AqsColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const SizedBox(height: 7),
                            Text(
                              '${quantity.toStringAsFixed(2)} ${_s(data['unit'])} × ${fmtMoney(rate)} TZS',
                              style: const TextStyle(color: AqsColors.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${fmtMoney(amount)} TZS',
                            style: const TextStyle(
                              color: AqsColors.ink,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit allowance',
                                onPressed:
                                    () => _showAllowanceDialog(
                                      existing: allowance,
                                    ),
                                icon: const Icon(Icons.edit_outlined, size: 19),
                              ),
                              IconButton(
                                tooltip: 'Delete allowance',
                                onPressed: () => _deleteAllowance(allowance),
                                color: const Color(0xFFD92D20),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _BillsSummaryErrorState extends StatelessWidget {
  const _BillsSummaryErrorState({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFD92D20),
                size: 42,
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AqsColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AqsColors.muted),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () {
                  onRetry();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// class BoqBillsSummaryPage extends StatelessWidget {
//   final dynamic controller; // use your controller type if you want
//   final String projectName;
//   final String buildingName;

//   const BoqBillsSummaryPage({
//     super.key,
//     required this.controller,
//     required this.projectName,
//     required this.buildingName,
//   });

//   String _s(dynamic v) => (v ?? '').toString();
//   String _key(dynamic v) =>
//       _s(v).trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();

//   String _rowType(dynamic v) {
//     final x = _s(v).trim().toLowerCase();
//     if (x.isEmpty) return 'item';
//     return x;
//   }

//   double? _asDouble(dynamic v) =>
//       v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

//   @override
//   Widget build(BuildContext context) {
//     final boqRef = controller.boqRef; // <- your BOQ collection reference

//     return Scaffold(
//       backgroundColor: AqsColors.canvas,
//       appBar: AppBar(
//         toolbarHeight: 72,
//         title: const AqsAppBarTitle(
//           title: 'Bills Summary',
//           subtitle: 'BOQ financial overview',
//         ),
//       ),
//       body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//         stream: boqRef.stateSnapshots(),
//         builder: (ctx, boqSnap) {
//           if (boqSnap.hasError) {
//             return Center(child: Text('BOQ error: ${boqSnap.error}'));
//           }
//           if (!boqSnap.hasData) {
//             return const Center(child: CircularProgressIndicator());
//           }

//           final boqDocs = boqSnap.data!.docs;

//           return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//             stream: controller.measStream(), // <- your measurements stream
//             builder: (ctx, measSnap) {
//               if (measSnap.hasError) {
//                 return Center(
//                   child: Text('Measurements error: ${measSnap.error}'),
//                 );
//               }
//               if (!measSnap.hasData) {
//                 return const Center(child: CircularProgressIndicator());
//               }

//               // -------------------------
//               // 1) totalsByBoq from measurements
//               // -------------------------
//               final totalsByBoq = <String, double>{};

//               for (final d in measSnap.data!.docs) {
//                 final m = d.data();
//                 final q = _asDouble(m['value']);
//                 if (q == null) continue;

//                 final keys = {
//                   _key(m['boqCode']),
//                   _key(m['resolvedBoqCode']),
//                   _key(m['boqCodeNorm']),
//                 }..removeWhere((key) => key.isEmpty);
//                 for (final key in keys) {
//                   totalsByBoq[key] = (totalsByBoq[key] ?? 0.0) + q;
//                 }
//               }

//               // -------------------------
//               // 2) Build bill summaries from BOQ items
//               // -------------------------
//               final bills = <String, _BillSum>{};

//               for (final doc in boqDocs) {
//                 final d = doc.data();
//                 final type = _rowType(d['rowType']);

//                 // only items contribute to totals
//                 if (type != 'item') continue;

//                 final billCode = _s(d['billCode']).trim();
//                 if (billCode.isEmpty) continue;

//                 final billLabel =
//                     _s(d['billLabel']).trim().isNotEmpty
//                         ? _s(d['billLabel']).trim()
//                         : 'Bill $billCode';

//                 final rawBoqCode = _s(d['boqCode']).trim();
//                 final displayCode = _s(d['displayCode']).trim();
//                 final resolved = _s(d['resolvedBoqCode']).trim();

//                 final resolvedKey = resolved.isNotEmpty ? resolved : rawBoqCode;
//                 final viewKey =
//                     displayCode.isNotEmpty ? displayCode : rawBoqCode;

//                 // qty from measurements
//                 final qtyComputed =
//                     totalsByBoq[_key(resolvedKey)] ??
//                     totalsByBoq[_key(viewKey)] ??
//                     totalsByBoq[_key(rawBoqCode)] ??
//                     0.0;

//                 // qty override from BOQ item
//                 final qOverrideNum = d['qtyOverride'];
//                 final qtyOverride =
//                     (qOverrideNum is num)
//                         ? qOverrideNum.toDouble()
//                         : double.tryParse('$qOverrideNum');

//                 final qty = qtyOverride ?? qtyComputed;

//                 // rate from BOQ item
//                 final rateNum = d['rate'];
//                 final rate =
//                     (rateNum is num)
//                         ? rateNum.toDouble()
//                         : double.tryParse('$rateNum');

//                 final amount = (rate == null) ? 0.0 : qty * rate;

//                 final b = bills.putIfAbsent(
//                   billCode,
//                   () => _BillSum(billCode: billCode, billLabel: billLabel),
//                 );

//                 b.totalAmount += amount;
//                 b.itemCount += 1;
//                 if (qty > 0) b.measuredItemCount += 1;
//                 if (amount > 0) b.valuedItemCount += 1;
//               }

//               final billList =
//                   bills.values.toList()..sort((a, b) {
//                     final ai = int.tryParse(a.billCode) ?? 9999;
//                     final bi = int.tryParse(b.billCode) ?? 9999;
//                     return ai.compareTo(bi);
//                   });

//               final grandTotal = billList.fold<double>(
//                 0.0,
//                 (s, b) => s + b.totalAmount,
//               );
//               final totalItems = billList.fold<int>(
//                 0,
//                 (sum, bill) => sum + bill.itemCount,
//               );
//               final measuredItems = billList.fold<int>(
//                 0,
//                 (sum, bill) => sum + bill.measuredItemCount,
//               );
//               final valuedBills =
//                   billList.where((bill) => bill.totalAmount > 0).length;

//               // -------------------------
//               // UI
//               // -------------------------
//               return ListView(
//                 padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
//                 children: [
//                   _SummaryHero(
//                     projectName: projectName,
//                     buildingName: buildingName,
//                     grandTotal: grandTotal,
//                   ),
//                   const SizedBox(height: 14),
//                   _KpiGrid(
//                     billCount: billList.length,
//                     valuedBills: valuedBills,
//                     totalItems: totalItems,
//                     measuredItems: measuredItems,
//                   ),
//                   const SizedBox(height: 22),
//                   Row(
//                     children: [
//                       const Expanded(
//                         child: Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Text(
//                               'Bill distribution',
//                               style: TextStyle(
//                                 color: AqsColors.ink,
//                                 fontSize: 18,
//                                 fontWeight: FontWeight.w900,
//                               ),
//                             ),
//                             SizedBox(height: 3),
//                             Text(
//                               'Value and measurement progress across every bill.',
//                               style: TextStyle(
//                                 color: AqsColors.muted,
//                                 fontSize: 12,
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                       OutlinedButton.icon(
//                         onPressed: () async {
//                           await controller.exportBoqExcel(
//                             projectName: projectName,
//                             buildingName: buildingName,
//                           );
//                         },
//                         icon: const Icon(Icons.download_rounded, size: 18),
//                         label: const Text('Export Excel'),
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: 12),
//                   if (billList.isEmpty)
//                     const _EmptyBillsState()
//                   else
//                     ...billList.asMap().entries.map((entry) {
//                       final bill = entry.value;
//                       final percentage =
//                           grandTotal <= 0
//                               ? 0.0
//                               : bill.totalAmount / grandTotal;
//                       return Padding(
//                         padding: const EdgeInsets.only(bottom: 10),
//                         child: _BillSummaryCard(
//                           bill: bill,
//                           percentage: percentage,
//                           accentIndex: entry.key,
//                         ),
//                       );
//                     }),
//                 ],
//               );
//             },
//           );
//         },
//       ),
//     );
//   }
// }

class _BillSum {
  final String billCode;
  final String billLabel;
  double totalAmount = 0.0;
  int itemCount = 0;
  int measuredItemCount = 0;
  int valuedItemCount = 0;

  _BillSum({required this.billCode, required this.billLabel});
}

class _SummaryHero extends StatelessWidget {
  const _SummaryHero({
    required this.projectName,
    required this.buildingName,
    required this.grandTotal,
    required this.measuredWorksTotal,
    required this.generalAllowancesTotal,
    required this.onProjectTap,
  });

  final String projectName;
  final String buildingName;
  final double grandTotal;
  final double measuredWorksTotal;
  final double generalAllowancesTotal;
  final VoidCallback onProjectTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AqsColors.primaryDark, Color(0xFF17448A)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24155EEF),
            blurRadius: 26,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final identity = Row(
            children: [
              const AqsLogoMark(size: 48, inverted: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: 'Open $projectName project details',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onProjectTap,
                          borderRadius: BorderRadius.circular(7),
                          hoverColor: Colors.white.withValues(alpha: 0.10),
                          focusColor: Colors.white.withValues(alpha: 0.12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    projectName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      decoration: TextDecoration.underline,
                                      decorationColor: Color(0x99FFFFFF),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.open_in_new_rounded,
                                  color: Color(0xFFCBD9F5),
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$buildingName · Consolidated BOQ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFCBD9F5)),
                    ),
                  ],
                ),
              ),
            ],
          );
          final total = Column(
            crossAxisAlignment:
                compact ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              const Text(
                'TOTAL VALUE',
                style: TextStyle(
                  color: Color(0xFFBFD2FA),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${fmtMoney(grandTotal)} TZS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 24 : 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Measured ${fmtMoney(measuredWorksTotal)} + allowances ${fmtMoney(generalAllowancesTotal)}',
                style: const TextStyle(
                  color: Color(0xFFCBD9F5),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [identity, const SizedBox(height: 22), total],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 24),
              total,
            ],
          );
        },
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({
    required this.billCount,
    required this.valuedBills,
    required this.totalItems,
    required this.measuredItems,
  });

  final int billCount;
  final int valuedBills;
  final int totalItems;
  final int measuredItems;

  @override
  Widget build(BuildContext context) {
    final double takeoffProgress =
        totalItems == 0
            ? 0.0
            : (measuredItems / totalItems).clamp(0.0, 1.0).toDouble();
    final cards = [
      _KpiCard(
        icon: Icons.folder_copy_outlined,
        value: '$billCount',
        label: 'Bills',
        color: AqsColors.primary,
        background: AqsColors.primarySoft,
      ),
      _KpiCard(
        icon: Icons.price_check_rounded,
        value: '$valuedBills',
        label: 'Valued bills',
        color: const Color(0xFF027A48),
        background: AqsColors.successSoft,
      ),
      _KpiCard(
        icon: Icons.format_list_numbered_rounded,
        value: '$totalItems',
        label: 'BOQ items',
        color: const Color(0xFFB54708),
        background: const Color(0xFFFFFAEB),
      ),
      _KpiCard(
        icon: Icons.straighten_rounded,
        value: '$measuredItems',
        label: 'Measured items',
        color: const Color(0xFF6941C6),
        background: const Color(0xFFF4F3FF),
      ),
      _KpiCard(
        icon: Icons.donut_large_rounded,
        value: '${(takeoffProgress * 100).toStringAsFixed(1)}%',
        label: 'Overall take-off coverage',
        color: const Color(0xFF026AA2),
        background: const Color(0xFFF0F9FF),
        progress: takeoffProgress,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.2,
                children: cards.take(4).toList(),
              ),
              const SizedBox(height: 10),
              SizedBox(height: 94, width: double.infinity, child: cards.last),
            ],
          );
        }
        final columns = constraints.maxWidth < 1050 ? 3 : 5;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: columns == 2 ? 2.2 : 2.15,
          children: cards,
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.background,
    this.progress,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final Color background;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      color: AqsColors.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AqsColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress!.clamp(0.0, 1.0).toDouble(),
                        minHeight: 4,
                        backgroundColor: background,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BillSummaryCard extends StatelessWidget {
  const _BillSummaryCard({
    required this.bill,
    required this.percentage,
    required this.accentIndex,
  });

  final _BillSum bill;
  final double percentage;
  final int accentIndex;

  static const accents = [
    AqsColors.primary,
    Color(0xFF039855),
    Color(0xFF7F56D9),
    Color(0xFFF79009),
    Color(0xFF06AED4),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = accents[accentIndex % accents.length];
    final measuredProgress =
        bill.itemCount == 0 ? 0.0 : bill.measuredItemCount / bill.itemCount;
    final identity = Row(
      children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text(
            bill.billCode,
            style: TextStyle(color: accent, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                bill.billLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AqsColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${bill.itemCount} items · ${bill.measuredItemCount} measured',
                style: const TextStyle(color: AqsColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
    final financial = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${fmtMoney(bill.totalAmount)} TZS',
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: AqsColors.ink,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${(percentage * 100).toStringAsFixed(1)}% of total',
          style: const TextStyle(color: AqsColors.muted, fontSize: 11),
        ),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 520) {
                  return Column(
                    children: [
                      identity,
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerRight, child: financial),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: 12),
                    financial,
                  ],
                );
              },
            ),
            const SizedBox(height: 13),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: measuredProgress.clamp(0.0, 1.0).toDouble(),
                minHeight: 7,
                backgroundColor: AqsColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                const Text(
                  'Measurement coverage',
                  style: TextStyle(color: AqsColors.muted, fontSize: 11),
                ),
                const Spacer(),
                Text(
                  '${(measuredProgress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBillsState extends StatelessWidget {
  const _EmptyBillsState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const AqsLogoMark(size: 52),
            const SizedBox(height: 16),
            const Text(
              'No bill totals available',
              style: TextStyle(
                color: AqsColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add BOQ items with bill codes, rates and linked measurements to build this summary.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AqsColors.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
