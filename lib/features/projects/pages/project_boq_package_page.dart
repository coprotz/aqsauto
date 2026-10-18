import 'dart:typed_data';

import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ProjectBoqPackageDefinition {
  const ProjectBoqPackageDefinition(
    this.key,
    this.title,
    this.icon, {
    this.iconKey = 'receipt',
  });

  final String key;
  final String title;
  final IconData icon;
  final String iconKey;
}

const Map<String, IconData> projectCostPackageIcons = {
  'receipt': Icons.receipt_long_outlined,
  'electricity': Icons.electrical_services_outlined,
  'plumbing': Icons.plumbing_outlined,
  'ict': Icons.router_outlined,
  'mechanical': Icons.settings_outlined,
  'fire': Icons.fire_extinguisher_outlined,
  'civil': Icons.construction_outlined,
  'variation': Icons.change_circle_outlined,
  'money': Icons.price_check_outlined,
  'assignment': Icons.assignment_outlined,
  'security': Icons.security_outlined,
  'landscape': Icons.park_outlined,
};

IconData projectCostPackageIcon(String key) =>
    projectCostPackageIcons[key] ?? Icons.receipt_long_outlined;

const projectBoqPackageDefinitions = <ProjectBoqPackageDefinition>[
  ProjectBoqPackageDefinition(
    'variations',
    'Variations',
    Icons.change_circle_outlined,
  ),
  ProjectBoqPackageDefinition(
    'electricity',
    'Electricity',
    Icons.electrical_services_outlined,
  ),
  ProjectBoqPackageDefinition(
    'preliminaries',
    'Preliminaries',
    Icons.assignment_outlined,
  ),
  ProjectBoqPackageDefinition('plumbing', 'Plumbing', Icons.plumbing_outlined),
  ProjectBoqPackageDefinition('ict', 'ICT', Icons.router_outlined),
  ProjectBoqPackageDefinition(
    'fire_fighting',
    'Fire Fighting',
    Icons.fire_extinguisher_outlined,
  ),
  ProjectBoqPackageDefinition(
    'provisional_sums',
    'Provisional Sums',
    Icons.playlist_add_check_circle_outlined,
  ),
  ProjectBoqPackageDefinition(
    'prime_cost_sums',
    'Prime Cost Sums',
    Icons.price_check_outlined,
  ),
];

class ProjectBoqPackagePage extends StatefulWidget {
  const ProjectBoqPackagePage({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.definition,
  });

  final String projectId;
  final String projectName;
  final ProjectBoqPackageDefinition definition;

  @override
  State<ProjectBoqPackagePage> createState() => _ProjectBoqPackagePageState();
}

class _ProjectBoqPackagePageState extends State<ProjectBoqPackagePage> {
  DocumentReference<Map<String, dynamic>> get _packageRef => FirebaseFirestore
      .instance
      .collection('projects')
      .doc(widget.projectId)
      .collection('projectBoqPackages')
      .doc(widget.definition.key);

  CollectionReference<Map<String, dynamic>> get _itemsRef =>
      _packageRef.collection('items');

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(
          '${value ?? ''}'
              .replaceAll(',', '')
              .replaceAll(RegExp(r'[^0-9.\-]'), ''),
        ) ??
        0;
  }

  String _cellText(Data? cell) => cell?.value?.toString().trim() ?? '';

  String _normalise(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  bool _isPercentageUnit(String unit) {
    final value = unit.trim().toLowerCase();
    return value == '%' || value == 'percent' || value == 'percentage';
  }

  double _calculateAmount({
    required String unit,
    required double quantity,
    required double rate,
  }) => (_isPercentageUnit(unit) ? quantity / 100 : quantity) * rate;

  Future<void> _addManualItem() async {
    final existing = await _itemsRef.get();
    if (!mounted) return;
    var highestItemNumber = 0;
    var highestSortOrder = -1.0;
    for (final doc in existing.docs) {
      final data = doc.data();
      if ((data['rowType'] ?? 'item') == 'item') {
        final number = int.tryParse('${data['code'] ?? ''}'.trim()) ?? 0;
        if (number > highestItemNumber) highestItemNumber = number;
      }
      final order = _number(data['sortOrder'] ?? data['sourceRow']);
      if (order > highestSortOrder) highestSortOrder = order;
    }

    final codeController = TextEditingController(
      text: '${highestItemNumber + 1}',
    );
    final seriesController = TextEditingController();
    final descriptionController = TextEditingController();
    final unitController = TextEditingController(text: 'Item');
    final quantityController = TextEditingController(text: '1');
    final rateController = TextEditingController();
    String? error;

    final save = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (context, setState) {
              final amount = _calculateAmount(
                unit: unitController.text,
                quantity: _number(quantityController.text),
                rate: _number(rateController.text),
              );
              return AlertDialog(
                title: Text('Add ${widget.definition.title} item'),
                content: SizedBox(
                  width: 720,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: 220,
                              child: TextField(
                                controller: codeController,
                                keyboardType: TextInputType.text,
                                decoration: const InputDecoration(
                                  labelText: 'BOQ item number / code',
                                  hintText: 'For example, 1, A or ii',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 440,
                              child: TextField(
                                controller: seriesController,
                                decoration: const InputDecoration(
                                  labelText: 'Part / series (optional)',
                                  hintText: 'For example, PART A',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: descriptionController,
                          minLines: 2,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: 160,
                              child: TextField(
                                controller: unitController,
                                onChanged: (_) => setState(() => error = null),
                                decoration: const InputDecoration(
                                  labelText: 'Unit',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 220,
                              child: TextField(
                                controller: quantityController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (_) => setState(() => error = null),
                                decoration: const InputDecoration(
                                  labelText: 'Quantity',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 260,
                              child: TextField(
                                controller: rateController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (_) => setState(() => error = null),
                                decoration: const InputDecoration(
                                  labelText: 'Rate (TZS)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF4FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Amount: TZS ${NumberFormat('#,##0.00').format(amount)}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF12356B),
                            ),
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
                  FilledButton.icon(
                    onPressed: () {
                      final code = codeController.text.trim();
                      if (code.isEmpty) {
                        setState(
                          () => error = 'Enter a BOQ item number or code.',
                        );
                        return;
                      }
                      final series = seriesController.text.trim().toUpperCase();
                      final duplicate = existing.docs.any((doc) {
                        final data = doc.data();
                        return (data['rowType'] ?? 'item') == 'item' &&
                            '${data['code'] ?? ''}'.trim().toUpperCase() ==
                                code.toUpperCase() &&
                            '${data['series'] ?? ''}'.trim().toUpperCase() ==
                                series;
                      });
                      if (duplicate) {
                        setState(
                          () =>
                              error =
                                  'Item $code already exists${series.isEmpty ? '' : ' in $series'}.',
                        );
                        return;
                      }
                      if (descriptionController.text.trim().isEmpty ||
                          unitController.text.trim().isEmpty ||
                          _number(quantityController.text) <= 0 ||
                          _number(rateController.text) < 0) {
                        setState(
                          () =>
                              error =
                                  'Enter a description, unit, positive quantity and valid rate.',
                        );
                        return;
                      }
                      Navigator.pop(dialogContext, true);
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save item'),
                  ),
                ],
              );
            },
          ),
    );

    if (save == true) {
      final quantity = _number(quantityController.text);
      final rate = _number(rateController.text);
      final unit = unitController.text.trim();
      await _itemsRef.add({
        'code': codeController.text.trim(),
        'sourceCode': codeController.text.trim(),
        'series': seriesController.text.trim().toUpperCase(),
        'description': descriptionController.text.trim(),
        'unit': unit,
        'quantity': quantity,
        'rate': rate,
        'amount': _calculateAmount(unit: unit, quantity: quantity, rate: rate),
        'rowType': 'item',
        'sortOrder': highestSortOrder + 1,
        'source': 'manual',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _refreshPackageSummary();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('BOQ item added successfully.')),
        );
      }
    }

    codeController.dispose();
    seriesController.dispose();
    descriptionController.dispose();
    unitController.dispose();
    quantityController.dispose();
    rateController.dispose();
  }

  Future<void> _editItem(
    QueryDocumentSnapshot<Map<String, dynamic>> item,
  ) async {
    final original = item.data();
    final originalSourceCode = '${original['sourceCode'] ?? ''}'.trim();
    final codeController = TextEditingController(
      text:
          originalSourceCode.isNotEmpty
              ? originalSourceCode
              : '${original['code'] ?? ''}',
    );
    final seriesController = TextEditingController(
      text: '${original['series'] ?? ''}',
    );
    final descriptionController = TextEditingController(
      text: '${original['description'] ?? ''}',
    );
    final unitController = TextEditingController(
      text: '${original['unit'] ?? ''}',
    );
    final quantityController = TextEditingController(
      text: '${original['quantity'] ?? ''}',
    );
    final rateController = TextEditingController(
      text: '${original['rate'] ?? ''}',
    );
    String? error;

    final save = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (context, setState) {
              final amount = _calculateAmount(
                unit: unitController.text,
                quantity: _number(quantityController.text),
                rate: _number(rateController.text),
              );
              void changed(String _) => setState(() => error = null);
              return AlertDialog(
                title: const Text('Edit BOQ item'),
                content: SizedBox(
                  width: 720,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: 220,
                              child: TextField(
                                controller: codeController,
                                onChanged: changed,
                                decoration: const InputDecoration(
                                  labelText: 'BOQ item number / code',
                                  hintText: 'For example, 1, A or ii',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 440,
                              child: TextField(
                                controller: seriesController,
                                onChanged: changed,
                                decoration: const InputDecoration(
                                  labelText: 'Part / series (optional)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: descriptionController,
                          minLines: 2,
                          maxLines: 5,
                          onChanged: changed,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: 160,
                              child: TextField(
                                controller: unitController,
                                onChanged: changed,
                                decoration: const InputDecoration(
                                  labelText: 'Unit',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 220,
                              child: TextField(
                                controller: quantityController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: changed,
                                decoration: const InputDecoration(
                                  labelText: 'Quantity',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 260,
                              child: TextField(
                                controller: rateController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: changed,
                                decoration: const InputDecoration(
                                  labelText: 'Rate (TZS)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF4FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Amount: TZS ${NumberFormat('#,##0.00').format(amount)}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF12356B),
                            ),
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
                  FilledButton.icon(
                    onPressed: () async {
                      final code = codeController.text.trim();
                      final series = seriesController.text.trim().toUpperCase();
                      if (code.isEmpty) {
                        setState(
                          () => error = 'Enter a BOQ item number or code.',
                        );
                        return;
                      }
                      final existing = await _itemsRef.get();
                      final duplicate = existing.docs.any((doc) {
                        final data = doc.data();
                        return doc.id != item.id &&
                            (data['rowType'] ?? 'item') == 'item' &&
                            '${data['code'] ?? ''}'.trim().toUpperCase() ==
                                code.toUpperCase() &&
                            '${data['series'] ?? ''}'.trim().toUpperCase() ==
                                series;
                      });
                      if (duplicate) {
                        setState(
                          () =>
                              error =
                                  'Item $code already exists${series.isEmpty ? '' : ' in $series'}.',
                        );
                        return;
                      }
                      if (descriptionController.text.trim().isEmpty ||
                          unitController.text.trim().isEmpty ||
                          _number(quantityController.text) <= 0 ||
                          _number(rateController.text) < 0) {
                        setState(
                          () =>
                              error =
                                  'Enter a description, unit, positive quantity and valid rate.',
                        );
                        return;
                      }
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save changes'),
                  ),
                ],
              );
            },
          ),
    );

    if (save == true) {
      final unit = unitController.text.trim();
      final quantity = _number(quantityController.text);
      final rate = _number(rateController.text);
      await item.reference.update({
        'code': codeController.text.trim(),
        'sourceCode': codeController.text.trim(),
        'series': seriesController.text.trim().toUpperCase(),
        'description': descriptionController.text.trim(),
        'unit': unit,
        'quantity': quantity,
        'rate': rate,
        'amount': _calculateAmount(unit: unit, quantity: quantity, rate: rate),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _refreshPackageSummary();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('BOQ item updated successfully.')),
        );
      }
    }

    codeController.dispose();
    seriesController.dispose();
    descriptionController.dispose();
    unitController.dispose();
    quantityController.dispose();
    rateController.dispose();
  }

  Future<void> _deleteItem(
    QueryDocumentSnapshot<Map<String, dynamic>> item,
  ) async {
    final data = item.data();
    final code = '${data['code'] ?? ''}'.trim();
    final description = '${data['description'] ?? 'this BOQ item'}'.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete BOQ item?'),
            content: Text(
              'Delete ${code.isEmpty ? '' : '$code – '}$description? This will remove its value from the shared costs and project total.',
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
                label: const Text('Delete item'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    await item.reference.delete();
    await _refreshPackageSummary();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('BOQ item deleted.')));
  }

  Future<void> _removeAllItems() async {
    final existing = await _itemsRef.get();
    if (!mounted) return;
    if (existing.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This shared-cost package is empty.')),
      );
      return;
    }

    final itemCount =
        existing.docs
            .where((doc) => (doc.data()['rowType'] ?? 'item') == 'item')
            .length;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            icon: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.red,
              size: 42,
            ),
            title: Text('Remove all ${widget.definition.title} items?'),
            content: Text(
              'This will permanently delete $itemCount BOQ ${itemCount == 1 ? 'item' : 'items'} and all headings in this shared-cost package. Its value will become TZS 0.00 and the project total will be recalculated. This cannot be undone.',
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
                label: const Text('Remove all items'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;

    for (var start = 0; start < existing.docs.length; start += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in existing.docs.skip(start).take(400)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    await _packageRef.set({
      'key': widget.definition.key,
      'title': widget.definition.title,
      'itemCount': 0,
      'rowCount': 0,
      'totalAmount': 0.0,
      'sourceFileName': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'All ${widget.definition.title} items were removed. Project totals have been updated.',
        ),
      ),
    );
  }

  Future<void> _refreshPackageSummary({String? sourceFileName}) async {
    final allRows = await _itemsRef.get();
    final pricedItems =
        allRows.docs
            .where((doc) => (doc.data()['rowType'] ?? 'item') == 'item')
            .toList();
    final total = pricedItems.fold<double>(
      0,
      (sum, doc) => sum + _number(doc.data()['amount']),
    );
    await _packageRef.set({
      'key': widget.definition.key,
      'title': widget.definition.title,
      'itemCount': pricedItems.length,
      'rowCount': allRows.docs.length,
      'totalAmount': total,
      'includedInProjectTotal': true,
      if (sourceFileName != null) 'sourceFileName': sourceFileName,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  int? _columnFor(List<String> headers, Iterable<String> names) {
    final candidates = names.map(_normalise).toSet();
    for (var index = 0; index < headers.length; index++) {
      final header = headers[index];
      if (candidates.contains(header)) return index;
    }
    for (var index = 0; index < headers.length; index++) {
      final header = headers[index];
      if (candidates.any((name) => header.contains(name))) return index;
    }
    return null;
  }

  Future<void> _uploadExcel() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
      withData: true,
    );
    if (picked == null || picked.files.single.bytes == null) return;

    final bytes = Uint8List.fromList(picked.files.single.bytes!);
    List<Map<String, dynamic>> rows;
    try {
      rows = _parseWorkbook(bytes);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read this workbook: $error')),
      );
      return;
    }
    if (rows.isEmpty || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No BOQ rows were found. Include Description, Unit, Quantity and Rate headings.',
            ),
          ),
        );
      }
      return;
    }

    var replaceExisting = true;
    final pricedItemCount =
        rows.where((row) => row['rowType'] == 'item').length;
    final hierarchyRowCount = rows.length - pricedItemCount;
    final total = rows.fold<double>(
      0,
      (sum, row) => sum + _number(row['amount']),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: Text('Import ${widget.definition.title} BOQ'),
                  content: SizedBox(
                    width: 520,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$pricedItemCount BOQ items and $hierarchyRowCount hierarchy rows found · TZS ${NumberFormat('#,##0.00').format(total)}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 14),
                        RadioListTile<bool>(
                          value: true,
                          groupValue: replaceExisting,
                          onChanged:
                              (value) => setState(() => replaceExisting = true),
                          title: const Text('Replace existing package'),
                          subtitle: const Text(
                            'Use this when uploading the complete revised BOQ.',
                          ),
                        ),
                        RadioListTile<bool>(
                          value: false,
                          groupValue: replaceExisting,
                          onChanged:
                              (value) =>
                                  setState(() => replaceExisting = false),
                          title: const Text('Append to existing package'),
                          subtitle: const Text(
                            'Keep the existing items and add these rows.',
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
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Import BOQ'),
                    ),
                  ],
                ),
          ),
    );
    if (confirmed != true) return;

    await _saveRows(
      rows,
      replaceExisting: replaceExisting,
      fileName: picked.files.single.name,
    );
  }

  List<Map<String, dynamic>> _parseWorkbook(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    final result = <Map<String, dynamic>>[];
    for (final tableName in workbook.tables.keys) {
      final table = workbook.tables[tableName];
      if (table == null || table.rows.isEmpty) continue;
      var headerIndex = -1;
      List<String> headers = const [];
      for (
        var rowIndex = 0;
        rowIndex < table.rows.length && rowIndex < 40;
        rowIndex++
      ) {
        final candidate =
            table.rows[rowIndex]
                .map((cell) => _normalise(_cellText(cell)))
                .toList();
        final description = _columnFor(candidate, const [
          'description',
          'item description',
          'particulars',
        ]);
        final unit = _columnFor(candidate, const ['unit', 'uom']);
        final quantity = _columnFor(candidate, const ['quantity', 'qty']);
        final rate = _columnFor(candidate, const ['rate', 'unit rate']);
        if (description != null &&
            unit != null &&
            quantity != null &&
            rate != null) {
          headerIndex = rowIndex;
          headers = candidate;
          break;
        }
      }
      if (headerIndex < 0) continue;

      final codeCol = _columnFor(headers, const [
        'boq code',
        'item code',
        'code',
        'item',
        'item no',
        'item number',
      ]);
      final descriptionCol =
          _columnFor(headers, const [
            'description',
            'item description',
            'particulars',
          ])!;
      final unitCol = _columnFor(headers, const ['unit', 'uom'])!;
      final quantityCol = _columnFor(headers, const ['quantity', 'qty'])!;
      final rateCol = _columnFor(headers, const ['rate', 'unit rate'])!;
      final amountCol = _columnFor(headers, const [
        'amount',
        'total amount',
        'total',
      ]);
      var currentSeries = '';
      var nextAlphabeticItem = 0;

      for (
        var rowIndex = headerIndex + 1;
        rowIndex < table.rows.length;
        rowIndex++
      ) {
        final row = table.rows[rowIndex];
        String textAt(int? index) =>
            index == null || index >= row.length ? '' : _cellText(row[index]);
        final code = textAt(codeCol);
        final description = textAt(descriptionCol);
        final unit = textAt(unitCol);
        final quantity = _number(textAt(quantityCol));
        final rate = _number(textAt(rateCol));
        final suppliedAmount = _number(textAt(amountCol));
        if (description.isEmpty ||
            description.replaceAll(RegExp(r'[.\s\-]'), '').isEmpty) {
          continue;
        }
        final isBoqItem =
            unit.isNotEmpty ||
            quantity != 0 ||
            rate != 0 ||
            suppliedAmount != 0;
        var hierarchyType =
            isBoqItem ? 'item' : _inferHierarchyRowType(code, description);
        if (hierarchyType == 'series') {
          final candidateSeries = _seriesName(code, description);
          if (currentSeries == candidateSeries && currentSeries.isNotEmpty) {
            hierarchyType = 'subheading';
          } else {
            currentSeries = candidateSeries;
          }
        }
        if (!isBoqItem &&
            (hierarchyType == 'series' ||
                hierarchyType == 'heading' ||
                hierarchyType == 'subheading' ||
                hierarchyType == 'minorHeading')) {
          nextAlphabeticItem = 0;
        }
        var displayCode = code;
        if (isBoqItem) {
          final sourceCode = code.trim();
          if (sourceCode.isNotEmpty) {
            // BOQ item identifiers are labels, not numbers. Preserve values
            // such as A, B, C, ii, etc. exactly as supplied by the QS.
            displayCode = sourceCode;
          } else {
            nextAlphabeticItem += 1;
            displayCode = _alphabeticItemCode(nextAlphabeticItem);
          }
        }
        result.add({
          'code': displayCode,
          'sourceCode': code,
          'series': currentSeries,
          'description': description,
          'unit': unit,
          'quantity': quantity,
          'rate': rate,
          'amount':
              isBoqItem
                  ? (suppliedAmount != 0
                      ? suppliedAmount
                      : _calculateAmount(
                        unit: unit,
                        quantity: quantity,
                        rate: rate,
                      ))
                  : 0.0,
          'rowType': hierarchyType,
          'sortOrder': result.length,
          'sheetName': tableName,
          'sourceRow': rowIndex + 1,
        });
      }
    }
    return result;
  }

  String _alphabeticItemCode(int value) {
    var remaining = value;
    final characters = <int>[];
    while (remaining > 0) {
      remaining -= 1;
      characters.add(65 + (remaining % 26));
      remaining ~/= 26;
    }
    return String.fromCharCodes(characters.reversed);
  }

  String _inferHierarchyRowType(String code, String description) {
    final codeKey = code.trim().toUpperCase();
    final descriptionKey = description.trim().toUpperCase();
    if (descriptionKey.startsWith('PART ') || codeKey.startsWith('PART ')) {
      return 'series';
    }
    if (descriptionKey.startsWith('BILL ') ||
        descriptionKey.startsWith('SECTION ')) {
      return 'heading';
    }
    if (RegExp(r'^[ivxlcdm]+$', caseSensitive: false).hasMatch(codeKey)) {
      return 'minorHeading';
    }
    if (codeKey.isNotEmpty) {
      return 'subheading';
    }
    return 'subheading';
  }

  String _seriesName(String code, String description) {
    final source =
        code.trim().toUpperCase().startsWith('PART ')
            ? code.trim()
            : description.trim();
    final match = RegExp(
      r'PART\s+[A-Z0-9]+',
      caseSensitive: false,
    ).firstMatch(source);
    return match?.group(0)?.toUpperCase() ?? source;
  }

  Future<void> _saveRows(
    List<Map<String, dynamic>> rows, {
    required bool replaceExisting,
    required String fileName,
  }) async {
    if (replaceExisting) {
      final existing = await _itemsRef.get();
      for (var start = 0; start < existing.docs.length; start += 400) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in existing.docs.skip(start).take(400)) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    }

    for (var start = 0; start < rows.length; start += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final row in rows.skip(start).take(400)) {
        final doc = _itemsRef.doc();
        batch.set(doc, {
          ...row,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    final allItems = await _itemsRef.get();
    final total = allItems.docs.fold<double>(
      0,
      (sum, doc) => sum + _number(doc.data()['amount']),
    );
    final pricedItemCount =
        allItems.docs
            .where((doc) => (doc.data()['rowType'] ?? 'item') == 'item')
            .length;
    await _packageRef.set({
      'key': widget.definition.key,
      'title': widget.definition.title,
      'itemCount': pricedItemCount,
      'rowCount': allItems.docs.length,
      'totalAmount': total,
      'includedInProjectTotal': true,
      'sourceFileName': fileName,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    final importedItemCount =
        rows.where((row) => row['rowType'] == 'item').length;
    final importedHierarchyCount = rows.length - importedItemCount;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$importedItemCount BOQ items and $importedHierarchyCount hierarchy rows imported successfully.',
        ),
      ),
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
            Text(widget.definition.title),
            Text(
              widget.projectName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Remove all items',
            onPressed: _removeAllItems,
            color: Colors.red,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          OutlinedButton.icon(
            onPressed: _addManualItem,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add item'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _uploadExcel,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Upload Excel BOQ'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _itemsRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load BOQ: ${snapshot.error}'));
          }
          final items = [...?snapshot.data?.docs]..sort(
            (left, right) => (_number(
              left.data()['sortOrder'] ?? left.data()['sourceRow'],
            )).compareTo(
              _number(right.data()['sortOrder'] ?? right.data()['sourceRow']),
            ),
          );
          final boqItems =
              items
                  .where((item) => (item.data()['rowType'] ?? 'item') == 'item')
                  .toList();
          final total = boqItems.fold<double>(
            0,
            (sum, item) => sum + _number(item.data()['amount']),
          );
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _metric(
                    'BOQ items',
                    '${boqItems.length}',
                    Icons.list_alt_outlined,
                  ),
                  _metric(
                    'Package value',
                    'TZS ${money.format(total)}',
                    Icons.account_balance_wallet_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (items.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(36),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            widget.definition.icon,
                            size: 42,
                            color: AqsColors.muted,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Upload an Excel BOQ or add an item manually.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed: _addManualItem,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Add item manually'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _uploadExcel,
                                icon: const Icon(Icons.upload_file_outlined),
                                label: const Text('Upload Excel BOQ'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 1640,
                      child: Table(
                        columnWidths: const {
                          0: FixedColumnWidth(130),
                          1: FixedColumnWidth(680),
                          2: FixedColumnWidth(110),
                          3: FixedColumnWidth(140),
                          4: FixedColumnWidth(210),
                          5: FixedColumnWidth(230),
                          6: FixedColumnWidth(140),
                        },
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        border: const TableBorder(
                          horizontalInside: BorderSide(
                            color: Color(0xFFE4E7EC),
                          ),
                        ),
                        children: [
                          _packageHeaderRow(),
                          for (final item in items)
                            _packageTableRow(item, money),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  TableRow _packageHeaderRow() => TableRow(
    decoration: const BoxDecoration(color: Colors.white),
    children: [
      _tableCell('BOQ code', header: true),
      _tableCell('Description', header: true),
      _tableCell('Unit', header: true),
      _tableCell('Quantity', header: true, alignRight: true),
      _tableCell('Rate', header: true, alignRight: true),
      _tableCell('Amount', header: true, alignRight: true),
      _tableCell('Actions', header: true),
    ],
  );

  TableRow _packageTableRow(
    QueryDocumentSnapshot<Map<String, dynamic>> item,
    NumberFormat money,
  ) {
    final data = item.data();
    final rowType = (data['rowType'] ?? 'item').toString();
    final isItem = rowType == 'item';
    final isSeries = rowType == 'series';
    final isHeading = rowType == 'heading' || isSeries;
    final sourceCode = (data['sourceCode'] ?? '').toString().trim();
    final description = (data['description'] ?? '').toString();
    final displayedDescription =
        !isItem && !isSeries && sourceCode.isNotEmpty
            ? '$sourceCode  $description'
            : description;
    final emphasis = TextStyle(
      fontWeight: isItem ? FontWeight.w500 : FontWeight.w900,
      fontSize: isSeries ? 15 : null,
      color: isHeading ? const Color(0xFF12356B) : null,
    );
    return TableRow(
      decoration: BoxDecoration(
        color:
            isItem
                ? Colors.white
                : isSeries
                ? const Color(0xFFEFF4FF)
                : const Color(0xFFF8FAFC),
      ),
      children: [
        _tableCell(
          isItem
              ? (sourceCode.isNotEmpty ? sourceCode : '${data['code'] ?? ''}')
              : isSeries
              ? '${data['series'] ?? ''}'
              : '',
          style: emphasis,
        ),
        _tableCell(displayedDescription, style: emphasis),
        _tableCell(isItem ? '${data['unit'] ?? ''}' : ''),
        _tableCell(
          isItem
              ? NumberFormat('#,##0.###').format(_number(data['quantity']))
              : '',
          alignRight: true,
        ),
        _tableCell(
          isItem ? money.format(_number(data['rate'])) : '',
          alignRight: true,
        ),
        _tableCell(
          isItem ? money.format(_number(data['amount'])) : '',
          alignRight: true,
          style:
              isItem ? const TextStyle(fontWeight: FontWeight.w800) : emphasis,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child:
              isItem
                  ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit BOQ item',
                        onPressed: () => _editItem(item),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Delete BOQ item',
                        onPressed: () => _deleteItem(item),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  )
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _tableCell(
    String text, {
    bool header = false,
    bool alignRight = false,
    TextStyle? style,
  }) => Padding(
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: header ? 16 : 13),
    child: Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        text,
        style:
            style ??
            TextStyle(
              fontWeight: header ? FontWeight.w800 : FontWeight.w500,
              color: header ? const Color(0xFF344054) : null,
            ),
      ),
    ),
  );

  Widget _metric(String label, String value, IconData icon) => SizedBox(
    width: 300,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: AqsColors.muted)),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
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
