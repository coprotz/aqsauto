import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/dashboards/controllers/project_buildings_controller.dart';
import 'package:aqs/features/utils/helpers/boq_helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class _CachedBoqRow {
  const _CachedBoqRow(this.id, this.value);

  final String id;
  final Map<String, dynamic> value;

  Map<String, dynamic> data() => value;
}

class _BoqPickerCache {
  static final Map<String, List<_CachedBoqRow>> _rows = {};
  static final Map<String, Future<List<_CachedBoqRow>>> _loads = {};

  static Future<List<_CachedBoqRow>> load(
    String key,
    CollectionReference<Map<String, dynamic>> ref, {
    bool refresh = false,
  }) {
    if (!refresh && _rows.containsKey(key)) {
      return Future.value(List.unmodifiable(_rows[key]!));
    }
    if (!refresh && _loads.containsKey(key)) return _loads[key]!;

    final Future<List<_CachedBoqRow>> future =
        (() async {
          try {
            final snapshot = await ref.orderBy('order').get();
            final loaded = snapshot.docs
                .map((doc) => _CachedBoqRow(doc.id, doc.data()))
                .toList(growable: true);
            _rows[key] = loaded;
            return List<_CachedBoqRow>.unmodifiable(loaded);
          } finally {
            _loads.remove(key);
          }
        })();
    _loads[key] = future;
    return future;
  }

  static void add(String key, _CachedBoqRow row) {
    // Rows can be seeded from shared state as an unmodifiable/fixed-length
    // list. Always take a growable copy before replacing or inserting an item.
    final rows = List<_CachedBoqRow>.of(
      _rows[key] ?? const <_CachedBoqRow>[],
      growable: true,
    );
    rows.removeWhere((item) => item.id == row.id);
    rows.add(row);
    rows.sort((a, b) {
      double orderOf(dynamic value) =>
          value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
      final aOrder = orderOf(a.value['order']);
      final bOrder = orderOf(b.value['order']);
      return aOrder.compareTo(bOrder);
    });
    _rows[key] = rows;
  }
}


class _PreparedBoqItem {
  const _PreparedBoqItem({
    required this.pick,
    required this.unit,
    required this.searchText,
  });

  final BoqPick pick;
  final String unit;
  final String searchText;
}

class _BoqInsertionAnchor {
  const _BoqInsertionAnchor({
    required this.id,
    required this.data,
    required this.index,
  });

  final String id;
  final Map<String, dynamic> data;
  final int index;

  String get code =>
      (data['resolvedBoqCode'] ?? data['displayCode'] ?? data['boqCode'] ?? '')
          .toString()
          .trim();
  String get description => (data['description'] ?? '').toString().trim();
  String get subheading => (data['subheading'] ?? '').toString().trim();
}

class BoqPickerDialog extends StatefulWidget {
  final String projectId;
  final String buildingId;
  final String? expectedUnit;

  const BoqPickerDialog({
    super.key,
    required this.projectId,
    required this.buildingId,
    this.expectedUnit,
  });

  static Future<void> preload({
    required String projectId,
    required String buildingId,
  }) async {
    try {
      final controller =
          Get.isRegistered<ProjectBuildingsController>()
              ? Get.find<ProjectBuildingsController>()
              : Get.put(ProjectBuildingsController(), permanent: true);
      await controller.loadBoq(projectId, buildingId);
    } catch (_) {
      // Opening the workspace must not fail when the background warm-up is
      // offline. The picker will retry and display its own recoverable error.
    }
  }

  @override
  State<BoqPickerDialog> createState() => _BoqPickerDialogState();
}

class _BoqPickerDialogState extends State<BoqPickerDialog> {
  late final TextEditingController searchCtrl;
  late final CollectionReference<Map<String, dynamic>> boqRef;
  late final String cacheKey;
  late Future<List<_CachedBoqRow>> boqRows;
  String q = '';
  String? _dialogMessage;
  bool _showAllUnits = false;
  List<_PreparedBoqItem>? _preparedItems;

  @override
  void initState() {
    super.initState();
    searchCtrl = TextEditingController();
    cacheKey = '${widget.projectId}/${widget.buildingId}';
    boqRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(widget.projectId)
        .collection('buildings')
        .doc(widget.buildingId)
        .collection('boq');
    boqRows = _loadBoqRows();
  }

  Future<List<_CachedBoqRow>> _loadBoqRows({bool refresh = false}) async {
    final controller =
        Get.isRegistered<ProjectBuildingsController>()
            ? Get.find<ProjectBuildingsController>()
            : Get.put(ProjectBuildingsController(), permanent: true);

    // Prefer the shared in-memory BOQ state. Opening a picker should not wait
    // for Firestore again when the workspace has already loaded this BOQ.
    if (!refresh && controller.boqLoaded(widget.projectId, widget.buildingId)) {
      return _mapSharedRows(
        controller.boqFor(widget.projectId, widget.buildingId),
      );
    }

    await controller.loadBoq(
      widget.projectId,
      widget.buildingId,
      forceRefresh: refresh,
    );
    final rows = controller.boqFor(widget.projectId, widget.buildingId);
    if (rows.isNotEmpty ||
        controller.boqLoaded(widget.projectId, widget.buildingId)) {
      return _mapSharedRows(rows);
    }
    return _BoqPickerCache.load(cacheKey, boqRef, refresh: refresh);
  }

  List<_CachedBoqRow> _mapSharedRows(List<Map<String, dynamic>> rows) {
    final mapped = rows
        .map((row) {
          final value = Map<String, dynamic>.from(row);
          final id = (value.remove('id') ?? '').toString();
          return _CachedBoqRow(id, value);
        })
        .toList(growable: true);
    _BoqPickerCache._rows[cacheKey] = List<_CachedBoqRow>.of(
      mapped,
      growable: true,
    );
    return List<_CachedBoqRow>.unmodifiable(mapped);
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  String norm(String s) {
    final x = s.toLowerCase().trim();
    return x.replaceAll(RegExp(r'\s+'), ''); // "12 mm" -> "12mm"
  }

  String _canonicalUnit(String? raw) {
    final value = (raw ?? '').toLowerCase().trim();
    final compact = value
        .replaceAll('²', '2')
        .replaceAll('³', '3')
        .replaceAll(RegExp(r'[\s._-]+'), '');
    if (<String>{'m3', 'cum', 'cubicm', 'cubicmeter', 'cubicmetre'}.contains(compact)) return 'm3';
    if (<String>{'m2', 'sqm', 'squarem', 'squaremeter', 'squaremetre'}.contains(compact)) return 'm2';
    if (<String>{'m', 'lm', 'linm', 'linearmeter', 'linearmetre'}.contains(compact)) return 'm';
    if (<String>{'ha', 'hectare', 'hectares'}.contains(compact)) return 'ha';
    if (<String>{'l', 'ltr', 'litre', 'liter', 'litres', 'liters'}.contains(compact)) return 'l';
    if (<String>{'kg', 'kilogram', 'kilograms'}.contains(compact)) return 'kg';
    if (<String>{'ton', 'tons', 'tonne', 'tonnes', 't'}.contains(compact)) return 'ton';
    if (<String>{'no', 'nos', 'nr', 'number', 'item', 'each', 'ea'}.contains(compact)) return 'no';
    return compact;
  }

  List<_PreparedBoqItem> _prepareItems(List<_CachedBoqRow> rows) {
    if (_preparedItems != null) return _preparedItems!;
    final hierarchyRows = rows
        .map((row) => <String, dynamic>{...row.data(), 'id': row.id})
        .toList(growable: false);
    final prepared = <_PreparedBoqItem>[];
    for (final row in rows) {
      final data = row.data();
      final code = hierarchicalBoqCodeFromRows(
        <String, dynamic>{...data, 'id': row.id},
        hierarchyRows,
      );
      final desc = (data['description'] ?? '').toString().trim();
      if (code.isEmpty || desc.isEmpty || row.id.isEmpty) continue;
      final rawUnit = (data['unit'] ?? '').toString().trim();
      final unit = _canonicalUnit(rawUnit);
      final pick = BoqPick(code: code, description: desc, id: row.id);
      prepared.add(
        _PreparedBoqItem(
          pick: pick,
          unit: unit,
          searchText: norm('$code $desc $rawUnit'),
        ),
      );
    }
    _preparedItems = List<_PreparedBoqItem>.unmodifiable(prepared);
    return _preparedItems!;
  }

  Future<void> _createBoqItem(
    CollectionReference<Map<String, dynamic>> boqRef,
  ) async {
    late final List<_CachedBoqRow> orderedDocs;
    try {
      orderedDocs = await _BoqPickerCache.load(cacheKey, boqRef);
    } catch (e) {
      if (mounted) {
        setState(() {
          _dialogMessage = 'Could not load BOQ positions: $e';
        });
      }
      return;
    }
    final anchors = <_BoqInsertionAnchor>[];

    for (var i = 0; i < orderedDocs.length; i++) {
      final data = orderedDocs[i].data();
      final rowType = (data['rowType'] ?? 'item').toString().toLowerCase();
      final description = (data['description'] ?? '').toString().trim();
      if (rowType == 'item' && description.isNotEmpty) {
        anchors.add(
          _BoqInsertionAnchor(id: orderedDocs[i].id, data: data, index: i),
        );
      }
    }

    if (!mounted) return;
    if (anchors.isEmpty) {
      setState(() {
        _dialogMessage = 'Please add BOQ template first.';
      });
      return;
    }

    setState(() => _dialogMessage = null);

    final codeCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController(text: searchCtrl.text.trim());
    final rateCtrl = TextEditingController();
    String unit = 'kg';
    String position = 'after';
    _BoqInsertionAnchor selectedAnchor = anchors.firstWhere((anchor) {
      final text =
          '${anchor.subheading} ${anchor.data['structure'] ?? ''}'
              .toLowerCase();
      return text.contains('roof structure');
    }, orElse: () => anchors.first);
    String? error;
    bool saving = false;

    final created = await showDialog<BoqPick>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              Future<void> save() async {
                final code = codeCtrl.text.trim();
                final description = descriptionCtrl.text.trim();
                final rate = double.tryParse(rateCtrl.text.trim());

                if (code.isEmpty || description.isEmpty) {
                  setDialogState(
                    () => error = 'BOQ code and description are required.',
                  );
                  return;
                }

                setDialogState(() {
                  saving = true;
                  error = null;
                });

                try {
                  double orderOf(int index) {
                    final value = orderedDocs[index].data()['order'];
                    return value is num
                        ? value.toDouble()
                        : double.tryParse('$value') ?? index.toDouble();
                  }

                  final anchorOrder = orderOf(selectedAnchor.index);
                  late final double insertOrder;
                  if (position == 'before') {
                    final previousOrder =
                        selectedAnchor.index > 0
                            ? orderOf(selectedAnchor.index - 1)
                            : anchorOrder - 1000;
                    insertOrder =
                        previousOrder < anchorOrder
                            ? (previousOrder + anchorOrder) / 2
                            : anchorOrder - 0.001;
                  } else {
                    final nextOrder =
                        selectedAnchor.index < orderedDocs.length - 1
                            ? orderOf(selectedAnchor.index + 1)
                            : anchorOrder + 1000;
                    insertOrder =
                        nextOrder > anchorOrder
                            ? (anchorOrder + nextOrder) / 2
                            : anchorOrder + 0.001;
                  }

                  final anchorData = selectedAnchor.data;
                  final inheritedHierarchy = <String, dynamic>{};
                  for (final key in const [
                    'structure',
                    'billCode',
                    'billLabel',
                    'subheading',
                    'subHeadingNo',
                    'minorCode',
                    'minorLabel',
                    'minorNo',
                  ]) {
                    if (anchorData.containsKey(key)) {
                      inheritedHierarchy[key] = anchorData[key];
                    }
                  }

                  final doc = boqRef.doc();
                  final newItemData = <String, dynamic>{
                    ...inheritedHierarchy,
                    'boqCode': code,
                    'displayCode': code,
                    'resolvedBoqCode': code,
                    'description': description,
                    'unit': unit,
                    'rate': rate,
                    'amount': null,
                    'rowType': 'item',
                    'order': insertOrder,
                    'orderKey':
                        '${anchorData['orderKey'] ?? ''}|introduced|${code.toLowerCase()}',
                    'isIntroducedItem': true,
                    'insertedRelativeToId': selectedAnchor.id,
                    'insertedRelativePosition': position,
                    'createdAt': FieldValue.serverTimestamp(),
                    'updatedAt': FieldValue.serverTimestamp(),
                  };
                  final hierarchyRows = <Map<String, dynamic>>[
                    for (final row in orderedDocs)
                      <String, dynamic>{...row.data(), 'id': row.id},
                    <String, dynamic>{...newItemData, 'id': doc.id},
                  ];
                  final resolvedCode = hierarchicalBoqCodeFromRows(
                    <String, dynamic>{...newItemData, 'id': doc.id},
                    hierarchyRows,
                  );
                  newItemData['resolvedBoqCode'] = resolvedCode;

                  final duplicate =
                      await boqRef
                          .where('resolvedBoqCode', isEqualTo: resolvedCode)
                          .limit(1)
                          .get();
                  if (duplicate.docs.isNotEmpty) {
                    setDialogState(() {
                      saving = false;
                      error =
                          'A BOQ item with code $resolvedCode already exists. Select it from the list.';
                    });
                    return;
                  }
                  await doc.set(newItemData);
                  _BoqPickerCache.add(
                    cacheKey,
                    _CachedBoqRow(doc.id, newItemData),
                  );
                  if (Get.isRegistered<ProjectBuildingsController>()) {
                    await Get.find<ProjectBuildingsController>().loadBoq(
                      widget.projectId,
                      widget.buildingId,
                      forceRefresh: true,
                    );
                  }

                  if (dialogContext.mounted) {
                    Navigator.pop(
                      dialogContext,
                      BoqPick(
                        id: doc.id,
                        code: resolvedCode,
                        description: description,
                      ),
                    );
                  }
                } catch (e) {
                  setDialogState(() {
                    saving = false;
                    error = 'Could not create BOQ item: $e';
                  });
                }
              }

              return AlertDialog(
                title: const Text('Create BOQ item'),
                content: SizedBox(
                  width: 620,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: codeCtrl,
                          autofocus: true,
                          enabled: !saving,
                          decoration: const InputDecoration(
                            labelText: 'BOQ code',
                            hintText: 'e.g. A.v or A.vi',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: descriptionCtrl,
                          enabled: !saving,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            hintText:
                                'Describe the new roof structure item clearly.',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: unit,
                                decoration: const InputDecoration(
                                  labelText: 'Unit',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'kg',
                                    child: Text('kg'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'm',
                                    child: Text('m'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'm2',
                                    child: Text('m²'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'm3',
                                    child: Text('m³'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'nr',
                                    child: Text('Nr'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Nos',
                                    child: Text('Nos'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Item',
                                    child: Text('Item'),
                                  ),
                                ],
                                onChanged:
                                    saving
                                        ? null
                                        : (value) {
                                          if (value != null) {
                                            setDialogState(() => unit = value);
                                          }
                                        },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: rateCtrl,
                                enabled: !saving,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Rate (optional)',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<_BoqInsertionAnchor>(
                          value: selectedAnchor,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Position relative to BOQ item',
                          ),
                          items:
                              anchors
                                  .map(
                                    (anchor) => DropdownMenuItem(
                                      value: anchor,
                                      child: Text(
                                        '${anchor.code} — ${anchor.description}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              saving
                                  ? null
                                  : (value) {
                                    if (value != null) {
                                      setDialogState(
                                        () => selectedAnchor = value,
                                      );
                                    }
                                  },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: position,
                                decoration: const InputDecoration(
                                  labelText: 'Insert',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'before',
                                    child: Text('Before selected item'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'after',
                                    child: Text('After selected item'),
                                  ),
                                ],
                                onChanged:
                                    saving
                                        ? null
                                        : (value) {
                                          if (value != null) {
                                            setDialogState(
                                              () => position = value,
                                            );
                                          }
                                        },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Section: ${selectedAnchor.subheading.isEmpty ? (selectedAnchor.data['structure'] ?? 'Same as selected item') : selectedAnchor.subheading}',
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              error!,
                              style: const TextStyle(
                                color: Color(0xFFB42318),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed:
                        saving ? null : () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: saving ? null : save,
                    icon:
                        saving
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                            : const Icon(Icons.add_rounded),
                    label: Text(saving ? 'Creating…' : 'Create and use'),
                  ),
                ],
              );
            },
          ),
    );

    codeCtrl.dispose();
    descriptionCtrl.dispose();
    rateCtrl.dispose();

    if (created != null && mounted) {
      Navigator.pop(context, created);
    }
  }

  @override
  Widget build(BuildContext context) {
    final qq = norm(q);

    return SafeArea(
      child: RepaintBoundary(
        child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 720),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 20, 18, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF102A56), Color(0xFF155EEF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(
                          Icons.receipt_long_outlined,
                          color: Color(0xFFD6E4FF),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select BOQ item',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Search, select, or introduce a new BOQ item',
                              style: TextStyle(
                                color: Color(0xFFD6E4FF),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF155EEF),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                        ),
                        onPressed: () => _createBoqItem(boqRef),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New item'),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Refresh BOQ items',
                        onPressed: () {
                          setState(() {
                            _preparedItems = null;
                            boqRows = _loadBoqRows(refresh: true);
                          });
                        },
                        color: Colors.white,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context, null),
                        color: Colors.white,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    child: Column(
                      children: [
                        TextField(
                          controller: searchCtrl,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            labelText: 'Search by BOQ code or description',
                            hintText: 'e.g. 12mm rebar, excavation, concrete',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: Color(0xFFE4E7EC),
                              ),
                            ),
                            isDense: true,
                            suffixIcon:
                                q.isEmpty
                                    ? null
                                    : IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        searchCtrl.clear();
                                        setState(() => q = '');
                                      },
                                    ),
                          ),
                          onChanged: (v) => setState(() => q = v),
                        ),
                        if ((widget.expectedUnit ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF4FF),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Suggested unit: ${widget.expectedUnit}',
                                  style: const TextStyle(
                                    color: Color(0xFF17448A),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Checkbox(
                                value: _showAllUnits,
                                onChanged: (v) => setState(() => _showAllUnits = v ?? false),
                              ),
                              const Text(
                                'Show all BOQ units',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ],
                        if (_dialogMessage != null) ...[
                          const SizedBox(height: 12),
                          _BoqDialogMessage(message: _dialogMessage!),
                        ],
                        const SizedBox(height: 12),
                        Expanded(
                          child: FutureBuilder<List<_CachedBoqRow>>(
                            future: boqRows,
                            builder: (ctx, snap) {
                              if (snap.hasError) {
                                return Center(
                                  child: Text('Failed: ${snap.error}'),
                                );
                              }
                              if (!snap.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              final rows = snap.data!;
                              final prepared = _prepareItems(rows);
                              final expected = _canonicalUnit(widget.expectedUnit);
                              final unitFiltered = expected.isEmpty || _showAllUnits
                                  ? prepared
                                  : prepared
                                      .where((item) => item.unit == expected)
                                      .toList(growable: false);
                              final filteredPrepared = qq.isEmpty
                                  ? unitFiltered
                                  : unitFiltered
                                      .where((item) => item.searchText.contains(qq))
                                      .toList(growable: false);
                              final items = prepared.map((e) => e.pick).toList(growable: false);
                              final filtered = filteredPrepared
                                  .map((e) => e.pick)
                                  .toList(growable: false);
                              final hasBoqTemplate = prepared.isNotEmpty;

                              if (filtered.isEmpty) {
                                return Center(
                                  child: _BoqEmptyState(
                                    hasBoqTemplate: hasBoqTemplate,
                                    onCreate:
                                        hasBoqTemplate
                                            ? () => _createBoqItem(boqRef)
                                            : null,
                                  ),
                                );
                              }

                              return Column(
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        '${filtered.length} item${filtered.length == 1 ? '' : 's'} found',
                                        style: const TextStyle(
                                          color: Color(0xFF667085),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (q.isNotEmpty)
                                        Text(
                                          'Filtered from ${items.length}',
                                          style: const TextStyle(
                                            color: Color(0xFF98A2B3),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: ListView.separated(
                                      keyboardDismissBehavior:
                                          ScrollViewKeyboardDismissBehavior
                                              .onDrag,
                                      itemCount: filtered.length,
                                      separatorBuilder:
                                          (_, __) => const SizedBox(height: 8),
                                      itemBuilder: (itemCtx, i) {
                                        final b = filtered[i];
                                        return Material(
                                          color: const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            onTap: () {
                                              FocusScope.of(itemCtx).unfocus();

                                              // ✅ still keep "next tick" pop to avoid dirty build scope error
                                              Future.microtask(() {
                                                if (mounted) {
                                                  Navigator.pop(context, b);
                                                }
                                              });
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 12,
                                                  ),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFFE4E7EC,
                                                  ),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 7,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFFEFF4FF,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            999,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      b.code,
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF17448A,
                                                        ),
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Text(
                                                      b.description,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF344054,
                                                        ),
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        height: 1.25,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  const Icon(
                                                    Icons.chevron_right_rounded,
                                                    color: Color(0xFF98A2B3),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BoqDialogMessage extends StatelessWidget {
  const _BoqDialogMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFEDF89)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFB54708),
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF93370D),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoqEmptyState extends StatelessWidget {
  const _BoqEmptyState({required this.hasBoqTemplate, required this.onCreate});

  final bool hasBoqTemplate;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final title =
        hasBoqTemplate
            ? 'No matching BOQ items'
            : 'Please add BOQ template first';
    final subtitle =
        hasBoqTemplate
            ? 'Create a new item and place it before or after the right BOQ row.'
            : 'Open the BOQ tab and add or import the BOQ template before selecting an item.';

    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasBoqTemplate
                ? Icons.search_off_rounded
                : Icons.receipt_long_outlined,
            size: 42,
            color: const Color(0xFF98A2B3),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF101828),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          if (onCreate != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create new BOQ item'),
            ),
          ],
        ],
      ),
    );
  }
}
